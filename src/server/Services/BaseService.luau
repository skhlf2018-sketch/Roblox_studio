--!strict
--[[
	BaseService — 베이스 플롯 배정(서버 7명 = 7칸), 배달, 부화 슬롯, 부화, 구역 표시, 밤 텔레포트

	2판 (맵 배치는 shared/Data/MapLayout):
	  - 배달 = 알을 든 채 자기 베이스 영역(MapLayout.isInPlot, 울타리 안 전체)에 들어오면 자동. 배달 패드 없음.
	      → 빈 부화 슬롯에 등록 (data.incubators, 저장됨) → EggDelivered + BaseService.delivered:fire(player, record)
	  - 부화 중 알 파트(IncubatingEgg)는 우리(pen) 안 MapLayout.incubatorSpots(plotIndex)[slot] 자리에 놓임.
	      Attribute Progress/Required/Ready 는 1초마다 갱신 (선임이 머리 위 "에그 1m 52s" 표시)
	  - 1초마다 자람: 진행 += 1 × 성장 속도(밤 30배, 게임패스 2배 플래그)
	  - 다 자라면 클라가 HatchEgg(eggUid) 요청 (우리 안 알 ProximityPrompt / Growing Eggs 패널) → 펫 생성
	  - 0.2초마다 구역 표시: 플레이어 Attr CurrentZone(구역 id | "hub" | ""), InSafeZone(허브 안),
	      새 구역에 들어가면 ZoneEntered { biomeId, name, nameEn } 1회 (허브는 안 보냄)
	  - 밤이 되면: 알 든 사람(자기 베이스 밖) + 허브 밖(z ≥ 0)에 있던 사람 → 자기 베이스로 순간이동
	      (허브 경계 밤 벽 1장에 막혀 못 돌아오지 않게). 베이스가 없으면 허브 기본 스폰.
	오프라인 동안에도 알은 자랍니다 (밤 가속 없이 실제 시간, 상한 24시간).

	2단계 (그대로):
	  - 선물 알(grantEgg): 제단·비밀 통로 합성·퀘스트 보상 알은 부화 슬롯에 바로 들어감.
	    슬롯이 가득 차면 data.eggQueue(저장, 최대 EGG_QUEUE_MAX)에서 기다렸다가 부화로 슬롯이 비면 자동으로 들어감.
	  - 순간이동 치트 방지:
	      배달: 주운 곳 → 배달한 곳 거리 ÷ (WalkSpeed × 1.3) 보다 빨리 왔으면 거부, 알은 둥지로 (EggService.confiscate)
	      0.2초 틱: 알 든 사람이 WalkSpeed × 경과초 × 1.5 + 8 스터드보다 멀리 움직이면 알을 이전 위치에 떨어뜨림
	      서버가 순간이동시킬 때(teleportHome)는 기준점을 옮기고 위치 검증을 잠깐 쉼
	  - 베이스가 없는 사람(8번째 접속 등, plotIndex = 0)은 누가 나가서 베이스가 비면 바로 배정 + 집으로 이동
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local MapLayout = require(Shared.Data.MapLayout)
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Sizes = require(Shared.Data.Sizes)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Character = require(Server.Util.Character)
local Gui = require(Server.Util.Gui)
local Signal = require(Server.Util.Signal)
local Validate = require(Server.Logic.Validate)
local DataSchema = require(Server.Logic.DataSchema)
local MoveCheck = require(Server.Logic.MoveCheck)
local MapBuilder = require(script.Parent.MapBuilder)
local CycleService = require(script.Parent.CycleService)
local EggService = require(script.Parent.EggService)
local PetService = require(script.Parent.PetService)
local IndexService = require(script.Parent.IndexService)
local AntiCheatService = require(script.Parent.AntiCheatService)

type IncubatorRecord = Types.IncubatorRecord
type QueuedEgg = Types.QueuedEgg

type Visual = {
	part: BasePart,
	label: TextLabel,
}

type CarryTrack = {
	position: Vector3,
	time: number,
}

export type GrantResult = "slot" | "queued"

local Attr = Tags.PlayerAttributes

local BaseService = {}

-- 알을 베이스에 배달해 부화 슬롯에 들어감 (player, record: IncubatorRecord) → 퀘스트·사쿠라 크리스탈
BaseService.delivered = Signal.new()

local plotOwners: { [number]: Player? } = {}
local visuals: { [Player]: { [string]: Visual } } = {}
local carryTracks: { [Player]: CarryTrack } = {}

------------------------------------------------------------------
-- 부화 슬롯 겉모습 (선임이 바꿀 자리)
------------------------------------------------------------------

local function visualText(record: IncubatorRecord, rate: number): string
	local pet = Pets.get(record.petId)
	local name = if pet then pet.name else record.petId
	if record.progress >= record.required then
		return name .. "\n부화 준비 완료!"
	end
	return name .. "\n" .. Format.duration(Economy.remainingSeconds(record.progress, record.required, rate))
end

-- 바닥 높이 (아래로 레이캐스트: 선임이 IncubatorSlot 받침·스폰 판을 두었으면 그 윗면)
local function floorAt(spot: MapLayout.XZ): number
	return MapBuilder.groundY(Vector3.new(spot.x, MapLayout.FLOOR_Y + 1, spot.z), {})
end

local function createVisual(player: Player, record: IncubatorRecord)
	local session = Sessions.get(player)
	if not session or session.plotIndex == 0 then
		return
	end
	local perPlayer = visuals[player]
	if perPlayer and perPlayer[record.uid] then
		return -- 이미 있음
	end
	local spot = MapLayout.incubatorSpots(session.plotIndex)[record.slot]
	if not spot then
		return
	end
	local size = Sizes.get(record.size)
	local petDef = Pets.get(record.petId)
	local rarity = if petDef then Rarities.get(petDef.rarity) else nil
	local d = Config.EGG_BASE_DIAMETER * (if size then size.eggScale else 1)
	local part = Instance.new("Part")
	part.Name = "Incubating_" .. record.uid
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(d, d, d) -- Ball 은 크기가 같은 값 → 길쭉한 모양은 SpecialMesh
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "EggShape"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.25, 1)
	mesh.Parent = part
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Color = if rarity
		then Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
		else Color3.new(1, 1, 1)
	part.CFrame = CFrame.new(spot.x, floorAt(spot) + d * 1.25 / 2, spot.z)
	part:SetAttribute("EggUid", record.uid)
	part:SetAttribute("OwnerUserId", player.UserId)
	part:SetAttribute("PetId", record.petId)
	part:SetAttribute("SlotIndex", record.slot)
	part:SetAttribute("Size", record.size)
	part:SetAttribute("Mutations", table.concat(record.mutations, ","))
	part:SetAttribute("Progress", record.progress)
	part:SetAttribute("Required", record.required)
	part:SetAttribute("Ready", record.progress >= record.required)
	CollectionService:AddTag(part, Tags.IncubatingEgg)
	part.Parent = MapBuilder.getFolder("Incubating")
	local label = Gui.billboard(part, visualText(record, 1), d * 1.25 + 1.5, 60)

	local list: { [string]: Visual } = perPlayer or {}
	visuals[player] = list
	list[record.uid] = { part = part, label = label }
end

local function destroyVisual(player: Player, uid: string)
	local perPlayer = visuals[player]
	local visual = if perPlayer then perPlayer[uid] else nil
	if perPlayer and visual then
		visual.part:Destroy()
		perPlayer[uid] = nil
	end
end

-- 부화 중 알 기록 찾기 (사쿠라 인큐베이터 등)
function BaseService.findIncubator(player: Player, uid: string): IncubatorRecord?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	for _, record in data.incubators do
		if record.uid == uid then
			return record
		end
	end
	return nil
end

-- 부화 중 알의 돌연변이가 바뀌었을 때 겉모습 Attribute 갱신
function BaseService.refreshIncubator(player: Player, uid: string)
	local record = BaseService.findIncubator(player, uid)
	local perPlayer = visuals[player]
	local visual = if perPlayer then perPlayer[uid] else nil
	if record and visual then
		visual.part:SetAttribute("Mutations", table.concat(record.mutations, ","))
	end
	Snapshot.section(player, "incubators")
end

------------------------------------------------------------------
-- 플롯
------------------------------------------------------------------

function BaseService.assignPlot(player: Player): number
	local session = Sessions.get(player)
	if not session then
		return 0
	end
	if session.plotIndex > 0 then
		return session.plotIndex
	end
	for index = 1, MapLayout.PLOT_COUNT do
		if plotOwners[index] == nil then
			plotOwners[index] = player
			session.plotIndex = index
			player:SetAttribute(Attr.PlotIndex, index)
			MapBuilder.setPlotOwner(index, player)
			return index
		end
	end
	warn("[BaseService] 빈 베이스가 없음: " .. player.Name)
	return 0
end

-- 서버 순간이동 (위치 검증 쉼 + 알 배달 기준점 옮김). look 방향을 바라봄
local function serverTeleport(player: Player, session: Sessions.Session, spot: MapLayout.XZ, look: Vector3)
	local character = player.Character
	if not character then
		return
	end
	local destination = Vector3.new(spot.x, floorAt(spot) + 4, spot.z)
	Sessions.exemptMovement(session, Config.MOVE_CHECK_EXEMPT_AFTER_TELEPORT)
	character:PivotTo(CFrame.lookAt(destination, destination + look))
	EggService.resetCarryOrigin(player, destination)
	carryTracks[player] = nil
end

-- 내 베이스 앞마당 스폰 자리로 (복도 가운데를 바라봄)
function BaseService.teleportHome(player: Player)
	local session = Sessions.get(player)
	if not session or not player.Character or session.plotIndex == 0 then
		return
	end
	local plot = MapLayout.plot(session.plotIndex)
	if plot then
		serverTeleport(player, session, plot.spawn, Vector3.new(plot.facing, 0, 0))
	end
end

-- 내 베이스로, 베이스가 없으면(8번째 사람) 허브 기본 스폰(MapLayout.hubSpots.mainSpawn)으로
function BaseService.teleportToSafety(player: Player)
	local session = Sessions.get(player)
	if not session or not player.Character then
		return
	end
	if session.plotIndex > 0 then
		BaseService.teleportHome(player)
		return
	end
	serverTeleport(player, session, MapLayout.hubSpots.mainSpawn, Vector3.new(0, 0, 1))
end

-- 늦게 베이스를 받은 사람: 부화 슬롯 겉모습 + 집으로 + 상태 다시 보내기
local function onPlotAssigned(player: Player)
	local session, data = Sessions.getLoaded(player)
	if session and data then
		for _, record in data.incubators do
			createVisual(player, record)
		end
		Snapshot.send(player)
	end
	BaseService.teleportHome(player)
	Net.notify(player, "success", "빈 베이스가 생겨서 내 베이스를 받았어요!")
end

function BaseService.releasePlot(player: Player)
	for index, owner in plotOwners do
		if owner == player then
			plotOwners[index] = nil
			MapBuilder.setPlotOwner(index, nil)
		end
	end
	-- 베이스 없이 기다리던 사람에게 빈 베이스 배정
	for other, session in Sessions.all() do
		if other ~= player and other.Parent ~= nil and session.plotIndex == 0 then
			if BaseService.assignPlot(other) > 0 then
				task.spawn(onPlotAssigned, other)
			end
		end
	end
end

------------------------------------------------------------------
-- 배달 / 선물 알 / 부화
------------------------------------------------------------------

local function freeSlot(data: Types.PlayerData): number?
	local used: { [number]: boolean } = {}
	for _, record in data.incubators do
		used[record.slot] = true
	end
	for slot = 1, Config.INCUBATOR_SLOTS do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

local function newRecord(
	data: Types.PlayerData,
	petId: string,
	size: string,
	mutations: { string },
	slot: number
): IncubatorRecord
	local pet = Pets.get(petId)
	return {
		uid = DataSchema.newUid(data, "i"),
		petId = petId,
		size = size,
		mutations = table.clone(mutations),
		biomeId = if pet then pet.biome else "",
		slot = slot,
		progress = 0,
		required = Economy.hatchSeconds(petId),
	}
end

-- 배달 직전 순간이동 검사: 주운 곳에서 배달한 곳까지 너무 빨리 왔나
local function isTooFast(player: Player, at: Vector3): boolean
	local egg = EggService.getCarried(player)
	local session = Sessions.get(player)
	local origin = if egg then egg.pickedPosition else nil
	if not egg or not session or not origin then
		return false
	end
	local distance = MoveCheck.horizontalDistance(origin.X, origin.Z, at.X, at.Z)
	local elapsed = os.clock() - egg.originAt
	return MoveCheck.isTooFastDelivery(distance, elapsed, session.walkSpeed)
end

function BaseService.deliver(player: Player)
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	local slot = freeSlot(data)
	if not slot then
		if Sessions.useCooldown(session, "incubatorFullNotice", 3, os.clock()) then
			Net.notify(
				player,
				"error",
				"부화 슬롯이 가득 찼어요! 다 자란 알을 먼저 부화시키세요."
			)
		end
		return
	end
	-- 배달한 곳 = 지금 캐릭터 위치 (없으면 베이스 가운데)
	local root = Character.getRoot(player)
	local plot = MapLayout.plot(session.plotIndex)
	local at = if root then root.Position elseif plot then Vector3.new(plot.center.x, 0, plot.center.z) else nil
	if at and isTooFast(player, at) then
		EggService.confiscate(player)
		AntiCheatService.flag(player, "배달이 너무 빨라요 (순간이동 의심)")
		return
	end
	local egg = EggService.takeCarried(player)
	if not egg then
		return
	end
	carryTracks[player] = nil
	local record = newRecord(data, egg.petId, egg.size, egg.mutations, slot)
	table.insert(data.incubators, record)
	data.stats.eggsDelivered = (data.stats.eggsDelivered or 0) + 1
	createVisual(player, record)
	Net.fire(player, Remotes.ToClient.EggDelivered, record)
	Snapshot.section(player, "incubators")
	BaseService.delivered:fire(player, record)
end

-- 선물 알을 받을 자리가 있나 (빈 슬롯 또는 대기 줄)
function BaseService.canReceiveEgg(player: Player): boolean
	local _, data = Sessions.getLoaded(player)
	if not data then
		return false
	end
	return freeSlot(data) ~= nil or #data.eggQueue < Config.EGG_QUEUE_MAX
end

-- 선물 알 (제단·비밀 통로·퀘스트): 빈 슬롯에 바로, 없으면 대기 줄. 자리가 없으면 nil
function BaseService.grantEgg(
	player: Player,
	petId: string,
	size: string,
	mutations: { string },
	source: string
): GrantResult?
	local _, data = Sessions.getLoaded(player)
	if not data or not Pets.get(petId) then
		return nil
	end
	local slot = freeSlot(data)
	if slot then
		local record = newRecord(data, petId, size, mutations, slot)
		table.insert(data.incubators, record)
		createVisual(player, record)
		Net.fire(player, Remotes.ToClient.EggGranted, { record = record, queued = false, source = source })
		Snapshot.section(player, "incubators")
		return "slot"
	end
	if #data.eggQueue >= Config.EGG_QUEUE_MAX then
		return nil
	end
	local queued: QueuedEgg = { petId = petId, size = size, mutations = table.clone(mutations), source = source }
	table.insert(data.eggQueue, queued)
	Net.fire(player, Remotes.ToClient.EggGranted, { egg = queued, queued = true, source = source })
	Net.notify(
		player,
		"info",
		"부화 슬롯이 가득 차서 선물 알이 기다리고 있어요. 알을 부화시키면 들어가요!"
	)
	Snapshot.section(player, "incubators")
	return "queued"
end

-- 대기 줄 알을 빈 슬롯으로
local function fillFromQueue(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	local moved = false
	while #data.eggQueue > 0 do
		local slot = freeSlot(data)
		if not slot then
			break
		end
		local queued = table.remove(data.eggQueue, 1) :: QueuedEgg
		local record = newRecord(data, queued.petId, queued.size, queued.mutations, slot)
		table.insert(data.incubators, record)
		createVisual(player, record)
		Net.fire(player, Remotes.ToClient.EggGranted, { record = record, queued = false, source = queued.source })
		moved = true
	end
	if moved then
		Snapshot.section(player, "incubators")
	end
end

function BaseService.hatch(player: Player, uid: string)
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	local index: number? = nil
	for i, record in data.incubators do
		if record.uid == uid then
			index = i
			break
		end
	end
	if not index then
		return
	end
	local record = data.incubators[index]
	if record.progress < record.required then
		Net.notify(player, "error", "아직 다 자라지 않았어요!")
		return
	end
	table.remove(data.incubators, index)
	destroyVisual(player, record.uid)

	local pet: Types.PetRecord = {
		uid = DataSchema.newUid(data, "p"),
		petId = record.petId,
		size = record.size,
		mutations = record.mutations,
	}
	local isNew = IndexService.discover(player, record.petId)
	local kept = PetService.addPet(player, pet)
	data.stats.eggsHatched = (data.stats.eggsHatched or 0) + 1
	Net.fire(player, Remotes.ToClient.HatchResult, {
		pet = pet,
		isNew = isNew,
		income = Economy.recordIncome(pet),
		equipped = table.find(data.equipped, pet.uid) ~= nil,
		sold = not kept, -- 보관함이 가득 차서 바로 팔렸나
	})
	Snapshot.section(player, "incubators")
	fillFromQueue(player)
end

------------------------------------------------------------------
-- 주기 처리
------------------------------------------------------------------

-- 1초마다: 알 자라기
local function growTick(dt: number): ...any
	local isNight = CycleService.isNight()
	for player, session in Sessions.all() do
		local data = session.data
		if session.loaded and data then
			local rate = Economy.growthRate(isNight, session.hasGrowthPass)
			local becameReady = false
			for _, record in data.incubators do
				local wasReady = record.progress >= record.required
				local progress, ready = Economy.advanceIncubation(record.progress, record.required, dt, rate)
				record.progress = progress
				if ready and not wasReady then
					becameReady = true
				end
				local perPlayer = visuals[player]
				local visual = if perPlayer then perPlayer[record.uid] else nil
				if visual then
					visual.part:SetAttribute("Progress", progress)
					visual.part:SetAttribute("Ready", ready)
					visual.label.Text = visualText(record, rate)
				end
			end
			if becameReady then
				Net.notify(player, "success", "알이 다 자랐어요! 부화시킬 수 있어요.")
				Snapshot.section(player, "incubators")
			end
		end
	end
end

-- 알 든 사람이 한 틱에 너무 멀리 움직였나 (순간이동) → 이전 위치에 알을 떨어뜨림
local function checkCarryJump(player: Player, session: Sessions.Session, root: BasePart, now: number): boolean
	local last = carryTracks[player]
	local position = root.Position
	if not last or now < session.moveExemptUntil then
		carryTracks[player] = { position = position, time = now }
		return false
	end
	local distance = MoveCheck.horizontalDistance(last.position.X, last.position.Z, position.X, position.Z)
	if MoveCheck.isCarryJump(distance, session.walkSpeed, now - last.time) then
		EggService.dropCarriedAt(player, last.position)
		carryTracks[player] = nil
		AntiCheatService.flag(player, "알을 든 채 너무 멀리 순간이동했어요")
		return true
	end
	carryTracks[player] = { position = position, time = now }
	return false
end

-- 구역 표시: CurrentZone / InSafeZone Attribute, 새 구역(구역 id)에 들어가면 ZoneEntered 1회
local function updateZone(player: Player, session: Sessions.Session, position: Vector3)
	local zoneId = MapLayout.zoneAt(position.Z) or ""
	if zoneId ~= session.currentZone then
		session.currentZone = zoneId
		player:SetAttribute(Attr.CurrentZone, zoneId)
		local range = MapLayout.biome(zoneId)
		if range then
			Net.fire(player, Remotes.ToClient.ZoneEntered, {
				biomeId = range.id,
				name = range.name,
				nameEn = range.nameEn,
			})
		end
	end
	local inSafe = MapLayout.isInHub(position)
	if inSafe ~= session.inSafeZone then
		session.inSafeZone = inSafe
		player:SetAttribute(Attr.InSafeZone, inSafe)
	end
end

-- 배달 높이 제한: 바닥에서 이보다 높이 떠 있으면(날아가는 중 등) 배달 안 함
local DELIVERY_MAX_HEIGHT = 20

-- 0.2초마다: 구역 표시, 알 든 사람 순간이동 검사, 베이스 영역에 들어오면 배달
local function baseTick(): ...any
	local carriers = EggService.carriers()
	local now = os.clock()
	for player in carryTracks do
		if not carriers[player] then
			carryTracks[player] = nil
		end
	end
	for player, session in Sessions.all() do
		local root = Character.getRoot(player)
		if root then
			updateZone(player, session, root.Position)
			if carriers[player] and not checkCarryJump(player, session, root, now) and session.plotIndex > 0 then
				if
					MapLayout.isInPlot(root.Position, session.plotIndex)
					and root.Position.Y - MapLayout.FLOOR_Y < DELIVERY_MAX_HEIGHT
				then
					BaseService.deliver(player)
				end
			end
		end
	end
end

------------------------------------------------------------------
-- 플레이어 이벤트
------------------------------------------------------------------

function BaseService.onPlayerReady(player: Player)
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	-- 오프라인 동안 자란 만큼 (밤 가속 없음)
	local offline = Economy.offlineGrowthSeconds(data.lastSaveTime, os.time())
	local rate = Economy.growthRate(false, session.hasGrowthPass)
	for _, record in data.incubators do
		record.progress = Economy.advanceIncubation(record.progress, record.required, offline, rate)
		createVisual(player, record)
	end
	fillFromQueue(player)
end

function BaseService.onCharacterAdded(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		task.wait() -- 엔진이 스폰 위치에 놓은 다음 프레임에 옮김
		BaseService.teleportHome(player)
	end
end

function BaseService.onPlayerLeaving(player: Player)
	local perPlayer = visuals[player]
	if perPlayer then
		for _, visual in perPlayer do
			visual.part:Destroy()
		end
		visuals[player] = nil
	end
	carryTracks[player] = nil
	BaseService.releasePlot(player)
end

function BaseService.start()
	Net.on(Remotes.ToServer.HatchEgg, function(player: Player, uid: unknown)
		local eggUid = Validate.uid(uid)
		if eggUid then
			BaseService.hatch(player, eggUid)
		end
	end)

	-- 밤: 알 든 사람(자기 베이스 밖) + 허브 밖(z ≥ 0)에 있던 사람(알 없어도) → 자기 베이스로
	--   (밤 벽이 허브 경계 z = 0 을 막으므로 밖에 갇히지 않게)
	CycleService.changed:connect(function(phase: Types.Phase)
		if phase ~= "Night" then
			return
		end
		local carriers = EggService.carriers()
		for player, session in Sessions.all() do
			local root = Character.getRoot(player)
			if root then
				if carriers[player] then
					if not MapLayout.isInPlot(root.Position, session.plotIndex) then
						BaseService.teleportToSafety(player)
					end
				elseif not MapLayout.isInHub(root.Position) then
					BaseService.teleportToSafety(player)
				end
			end
		end
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local ok, err = pcall(growTick, now - last)
			last = now
			if not ok then
				warn("[BaseService] grow 오류: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.BASE_TICK_SECONDS)
			local ok, err = pcall(baseTick)
			if not ok then
				warn("[BaseService] tick 오류: " .. tostring(err))
			end
		end
	end)
end

return BaseService
