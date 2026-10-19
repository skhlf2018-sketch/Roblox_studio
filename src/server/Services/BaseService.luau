--!strict
--[[
	BaseService — 베이스 플롯 배정(서버 7명 = 7칸), 배달(→ 알 가방), 우리에 알 놓기·다시 줍기, 부화, 구역 표시, 밤 텔레포트

	2판 수정 (사장님: "안전 구역 다 들어오면 알 획득"):
	  - 배달 = 알을 든 채 허브(안전 구역, MapLayout.isInHub = z < 0)에 들어오는 순간 자동.
	      경비 추격 끝(ChaseEnded reason "safe")과 같은 순간. 베이스가 없는 사람(8번째)도 똑같이 받음.
	      → 알은 알 가방(data.eggs, 최대 EGG_INVENTORY_MAX, 저장)으로 → EggDelivered(BagEgg) + DataUpdate("eggs")
	        + BaseService.delivered:fire(player, bagEgg) (퀘스트·사쿠라 크리스탈)
	      가방이 가득 차면 배달 안 됨: 알은 손에 그대로, 안내는 3초에 한 번 (가방을 비우면 다음 틱에 배달).
	  - 가방의 알은 플레이어가 우리(penRect) 안 원하는 자리에 놓음: Remote PlaceEgg(eggUid, x, z) (월드 x, z)
	      검증: 내 베이스가 있음 · 가방에 그 알 · 놓인 알 < PLACED_EGG_MAX · 내가 내 베이스 안(또는 그 자리 14 안)
	            · 그 자리가 내 우리 안(울타리에서 2 안쪽) · 다른 놓인 알·내 우리 펫과 간격 (shared/EggPlacement)
	      → data.incubators 에 베이스 기준 좌표(x, z, MapLayout.toLocal)로 저장 → 그 자리에 IncubatingEgg 파트 + 부화 시작
	  - Remote PickUpPlacedEgg(eggUid): 놓인 알을 다시 가방으로 (진행도 유지). Config.ALLOW_EGG_PICKUP 으로 켜고 끔.
	      (부화 버튼처럼 거리 검사 없음 — 가방으로 옮기는 것뿐이라 이득이 없음)
	  - 1초마다 자람: 우리에 놓인 알만 (진행 += 1 × 성장 속도, 밤 30배, 게임패스 2배 플래그). 가방 속 알은 안 자람
	  - 다 자라면 클라가 HatchEgg(eggUid) 요청 (우리 안 알 ProximityPrompt / 성장하는 달걀 패널) → 펫 생성
	  - 선물 알(grantEgg: 제단·비밀 통로 합성·퀘스트)도 가방으로 (2단계 대기 줄 eggQueue 없앰). 가방이 차면 못 받음
	  - 0.2초마다 구역 표시: 플레이어 Attr CurrentZone(구역 id | "hub" | ""), InSafeZone(허브 안),
	      새 구역에 들어가면 ZoneEntered { biomeId, name, nameEn } 1회 (허브는 안 보냄)
	  - 밤이 되면: 허브 밖(z ≥ 0)에 있던 사람(알을 들었든 아니든) → 자기 베이스로 순간이동 (밤 벽에 안 갇히게).
	      알을 들고 있었으면 허브라 다음 틱에 가방으로 배달. 베이스가 없으면 허브 기본 스폰.
	오프라인 동안에도 놓인 알은 자랍니다 (밤 가속 없이 실제 시간, 상한 24시간).

	2단계 (그대로):
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
local Visuals = require(Shared.Data.Visuals)
local Economy = require(Shared.Economy)
local EggPlacement = require(Shared.EggPlacement)
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
type BagEgg = Types.BagEgg

type Visual = {
	part: BasePart,
	label: TextLabel,
}

type CarryTrack = {
	position: Vector3,
	time: number,
}

export type GrantResult = "bag"

local Attr = Tags.PlayerAttributes

local BaseService = {}

-- 알을 들고 허브에 들어와 가방에 들어감 (player, egg: BagEgg) → 퀘스트·사쿠라 크리스탈
BaseService.delivered = Signal.new()

local plotOwners: { [number]: Player? } = {}
local visuals: { [Player]: { [string]: Visual } } = {}
local carryTracks: { [Player]: CarryTrack } = {}

------------------------------------------------------------------
-- 우리에 놓인 알 겉모습 (선임 EggVisualService 가 껍데기를 꾸밈)
------------------------------------------------------------------

local function visualText(record: IncubatorRecord, rate: number): string
	local pet = Pets.get(record.petId)
	local name = if pet then pet.name else record.petId
	if record.progress >= record.required then
		return name .. "\n부화 준비 완료!"
	end
	return name .. "\n" .. Format.duration(Economy.remainingSeconds(record.progress, record.required, rate))
end

-- 바닥 높이 (아래로 레이캐스트: 우리 바닥 윗면)
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
	local spot = MapLayout.toWorld(session.plotIndex, record.x, record.z)
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
	part:SetAttribute("PlotIndex", session.plotIndex)
	part:SetAttribute("PetId", record.petId)
	part:SetAttribute("Size", record.size)
	part:SetAttribute("Mutations", table.concat(record.mutations, ","))
	part:SetAttribute("Special", record.special)
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

local function incubatorIndex(data: Types.PlayerData, uid: string): number?
	for i, record in data.incubators do
		if record.uid == uid then
			return i
		end
	end
	return nil
end

local function bagIndex(data: Types.PlayerData, uid: string): number?
	for i, egg in data.eggs do
		if egg.uid == uid then
			return i
		end
	end
	return nil
end

-- 우리에 놓인 알 기록 찾기 (사쿠라 인큐베이터 등)
function BaseService.findIncubator(player: Player, uid: string): IncubatorRecord?
	local _, data = Sessions.getLoaded(player)
	local index = if data then incubatorIndex(data, uid) else nil
	return if data and index then data.incubators[index] else nil
end

-- 가방 속 알 찾기 (사쿠라 인큐베이터 등)
function BaseService.findBagEgg(player: Player, uid: string): BagEgg?
	local _, data = Sessions.getLoaded(player)
	local index = if data then bagIndex(data, uid) else nil
	return if data and index then data.eggs[index] else nil
end

-- 놓인 알의 돌연변이가 바뀌었을 때 겉모습 Attribute 갱신
function BaseService.refreshIncubator(player: Player, uid: string)
	local record = BaseService.findIncubator(player, uid)
	local perPlayer = visuals[player]
	local visual = if perPlayer then perPlayer[uid] else nil
	if record and visual then
		visual.part:SetAttribute("Mutations", table.concat(record.mutations, ","))
	end
	Snapshot.section(player, "incubators")
end

-- 가방 속 알이 바뀌었을 때 (사쿠라 블룸 등)
function BaseService.refreshBag(player: Player)
	Snapshot.section(player, "eggs")
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

-- 늦게 베이스를 받은 사람: 놓인 알 겉모습 + 집으로 + 상태 다시 보내기
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
-- 배달 (→ 가방) / 선물 알 / 우리에 놓기·다시 줍기 / 부화
------------------------------------------------------------------

local function newBagEgg(
	data: Types.PlayerData,
	petId: string,
	size: string,
	mutations: { string },
	special: boolean
): BagEgg
	local pet = Pets.get(petId)
	return {
		uid = DataSchema.newUid(data, "i"),
		petId = petId,
		size = size,
		mutations = table.clone(mutations),
		biomeId = if pet then pet.biome else "",
		special = special,
		progress = 0,
		required = Economy.hatchSeconds(petId),
	}
end

local function bagFullText(): string
	return string.format(
		"알 가방이 가득 찼어요 (%d개)! 가방의 알을 우리에 놓거나 부화시키세요.",
		Config.EGG_INVENTORY_MAX
	)
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

-- 들고 있는 알을 가방으로 (baseTick 이 허브 안에서 부름)
function BaseService.deliver(player: Player)
	local session, data = Sessions.getLoaded(player)
	if not session or not data or not EggService.getCarried(player) then
		return
	end
	if #data.eggs >= Config.EGG_INVENTORY_MAX then
		if Sessions.useCooldown(session, "eggBagFullNotice", 3, os.clock()) then
			Net.notify(player, "error", bagFullText())
		end
		return
	end
	-- 배달한 곳 = 지금 캐릭터 위치 (없으면 허브 경계)
	local root = Character.getRoot(player)
	local at = if root then root.Position else Vector3.new(0, MapLayout.FLOOR_Y, MapLayout.SAFE_ZONE_Z)
	if isTooFast(player, at) then
		EggService.confiscate(player)
		AntiCheatService.flag(player, "배달이 너무 빨라요 (순간이동 의심)")
		return
	end
	local egg = EggService.takeCarried(player)
	if not egg then
		return
	end
	carryTracks[player] = nil
	local bagEgg = newBagEgg(data, egg.petId, egg.size, egg.mutations, egg.special == true)
	table.insert(data.eggs, bagEgg)
	data.stats.eggsDelivered = (data.stats.eggsDelivered or 0) + 1
	Net.fire(player, Remotes.ToClient.EggDelivered, bagEgg)
	Snapshot.section(player, "eggs")
	BaseService.delivered:fire(player, bagEgg)
end

-- 선물 알을 받을 자리가 있나 (가방에 빈칸)
function BaseService.canReceiveEgg(player: Player): boolean
	local _, data = Sessions.getLoaded(player)
	return data ~= nil and #data.eggs < Config.EGG_INVENTORY_MAX
end

-- 선물 알 (제단·비밀 통로·퀘스트): 가방으로. 가방이 가득 찼거나 모르는 펫이면 nil
function BaseService.grantEgg(
	player: Player,
	petId: string,
	size: string,
	mutations: { string },
	source: string
): GrantResult?
	local _, data = Sessions.getLoaded(player)
	if not data or not Pets.get(petId) or #data.eggs >= Config.EGG_INVENTORY_MAX then
		return nil
	end
	local egg = newBagEgg(data, petId, size, mutations, false)
	table.insert(data.eggs, egg)
	-- queued 는 2단계 클라 호환용 (대기 줄은 없어져서 항상 false)
	Net.fire(player, Remotes.ToClient.EggGranted, { egg = egg, queued = false, source = source })
	Snapshot.section(player, "eggs")
	return "bag"
end

-- 놓인 알 자리 목록 (EggPlacement 용, 로컬 좌표)
local function placedSpots(data: Types.PlayerData): { EggPlacement.Spot }
	local spots: { EggPlacement.Spot } = {}
	for _, record in data.incubators do
		table.insert(spots, { x = record.x, z = record.z, size = record.size })
	end
	return spots
end

-- 내 우리에 서 있는 펫 자리 (로컬). 선임 PetVisualService 가 놓은 PenPet 모델 위치
local function penPetSpots(plotIndex: number): { EggPlacement.Spot }
	local spots: { EggPlacement.Spot } = {}
	for _, inst in CollectionService:GetTagged(Visuals.Tags.PenPet) do
		if inst:IsA("Model") then
			local position = inst:GetPivot().Position
			if MapLayout.isInPen(position, plotIndex) then
				local l = MapLayout.toLocal(plotIndex, position)
				if l then
					table.insert(spots, { x = l.x, z = l.z })
				end
			end
		end
	end
	return spots
end

-- PlaceEgg: 가방의 알을 내 우리 (x, z)(월드)에 놓음 → 부화 시작. 성공하면 true
function BaseService.placeEgg(player: Player, uid: string, x: number, z: number): boolean
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return false
	end
	local index = bagIndex(data, uid)
	if not index then
		return false -- 가방에 없는 알 (남의 알·이미 놓은 알·이상한 uid)
	end
	if session.plotIndex == 0 then
		Net.notify(
			player,
			"error",
			"아직 내 베이스가 없어요! 베이스를 받으면 알을 놓을 수 있어요."
		)
		return false
	end
	if #data.incubators >= Config.PLACED_EGG_MAX then
		Net.notify(player, "error", EggPlacement.message("full"))
		return false
	end
	local root = Character.getRoot(player)
	if not root then
		return false
	end
	local near = MoveCheck.horizontalDistance(root.Position.X, root.Position.Z, x, z) <= Config.EGG_PLACE_RADIUS
	if not near and not MapLayout.isInPlot(root.Position, session.plotIndex) then
		Net.notify(player, "error", "내 베이스 우리 가까이에서 놓아 주세요!")
		return false
	end
	local l = MapLayout.toLocal(session.plotIndex, { x = x, z = z })
	if not l then
		return false
	end
	local egg = data.eggs[index]
	local lx, lz = EggPlacement.round(l.x), EggPlacement.round(l.z)
	local ok, reason = EggPlacement.check(lx, lz, egg.size, placedSpots(data), penPetSpots(session.plotIndex))
	if not ok then
		Net.notify(player, "error", EggPlacement.message(reason))
		return false
	end
	table.remove(data.eggs, index)
	local required = Economy.hatchSeconds(egg.petId)
	local record: IncubatorRecord = {
		uid = egg.uid,
		petId = egg.petId,
		size = egg.size,
		mutations = egg.mutations,
		biomeId = egg.biomeId,
		special = egg.special,
		x = lx,
		z = lz,
		progress = math.min(egg.progress, required),
		required = required,
	}
	table.insert(data.incubators, record)
	createVisual(player, record)
	Snapshot.section(player, "eggs")
	Snapshot.section(player, "incubators")
	return true
end

-- PickUpPlacedEgg: 놓인 알을 다시 가방으로 (진행도 유지). 성공하면 true
function BaseService.pickUpEgg(player: Player, uid: string): boolean
	if not Config.ALLOW_EGG_PICKUP then
		return false
	end
	local _, data = Sessions.getLoaded(player)
	local index = if data then incubatorIndex(data, uid) else nil
	if not data or not index then
		return false
	end
	if #data.eggs >= Config.EGG_INVENTORY_MAX then
		Net.notify(player, "error", bagFullText())
		return false
	end
	local record = table.remove(data.incubators, index) :: IncubatorRecord
	destroyVisual(player, record.uid)
	table.insert(data.eggs, {
		uid = record.uid,
		petId = record.petId,
		size = record.size,
		mutations = record.mutations,
		biomeId = record.biomeId,
		special = record.special,
		progress = record.progress,
		required = record.required,
	})
	Snapshot.section(player, "eggs")
	Snapshot.section(player, "incubators")
	return true
end

function BaseService.hatch(player: Player, uid: string)
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	local index = incubatorIndex(data, uid)
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
end

------------------------------------------------------------------
-- 주기 처리
------------------------------------------------------------------

-- 1초마다: 우리에 놓인 알 자라기 (가방 속 알은 안 자람)
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

-- 0.2초마다: 구역 표시, 알 든 사람 순간이동 검사, 알을 든 채 허브(안전 구역)에 들어오면 배달
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
			if carriers[player] and not checkCarryJump(player, session, root, now) then
				if MapLayout.isInHub(root.Position) and root.Position.Y - MapLayout.FLOOR_Y < DELIVERY_MAX_HEIGHT then
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
	-- 오프라인 동안 자란 만큼 (놓인 알만, 밤 가속 없음)
	local offline = Economy.offlineGrowthSeconds(data.lastSaveTime, os.time())
	local rate = Economy.growthRate(false, session.hasGrowthPass)
	for _, record in data.incubators do
		record.progress = Economy.advanceIncubation(record.progress, record.required, offline, rate)
		createVisual(player, record)
	end
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
	Net.on(Remotes.ToServer.PlaceEgg, function(player: Player, uid: unknown, x: unknown, z: unknown)
		local eggUid = Validate.uid(uid)
		local px, pz = Validate.finiteNumber(x), Validate.finiteNumber(z)
		if eggUid and px and pz then
			BaseService.placeEgg(player, eggUid, px, pz)
		end
	end)
	Net.on(Remotes.ToServer.PickUpPlacedEgg, function(player: Player, uid: unknown)
		local eggUid = Validate.uid(uid)
		if eggUid then
			BaseService.pickUpEgg(player, eggUid)
		end
	end)

	-- 밤: 허브 밖(z ≥ 0)에 있던 사람 → 자기 베이스로 (밤 벽이 허브 경계 z = 0 을 막으므로 밖에 갇히지 않게).
	--   알을 들고 있었으면 베이스(허브 안)에 도착하자마자 다음 틱에 가방으로 배달
	CycleService.changed:connect(function(phase: Types.Phase)
		if phase ~= "Night" then
			return
		end
		for player in Sessions.all() do
			local root = Character.getRoot(player)
			if root and not MapLayout.isInHub(root.Position) then
				BaseService.teleportToSafety(player)
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
