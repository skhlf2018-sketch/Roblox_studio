--!strict
--[[
	BaseService — 베이스 플롯 배정(서버 7명 = 7칸), 배달 패드, 부화 슬롯, 부화, 안전 구역, 밤 텔레포트

	흐름: 알을 들고 내 베이스 배달 패드(DELIVERY_RADIUS 안)에 오면
	      → 빈 부화 슬롯에 등록 (data.incubators, 저장됨)
	      → 1초마다 자람: 진행 += 1 × 성장 속도(밤 30배, 게임패스 2배 플래그)
	      → 다 자라면 클라가 HatchEgg(eggUid) 요청 → 서버 검증 후 펫 생성 (보관함 + 빈 칸이면 자동 장착)
	오프라인 동안에도 알은 자랍니다 (밤 가속 없이 실제 시간, 상한 24시간).
	안전 구역(베이스 반경 SAFE_ZONE_RADIUS): 경비가 안 쫓아오고, 도구 사용·피격 불가 (GuardianService/ToolService 에서 검사).
	밤이 되면 알을 든 사람은 자기 베이스로 텔레포트 (알은 계속 듦 → 배달 가능).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
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
local Validate = require(Server.Logic.Validate)
local DataSchema = require(Server.Logic.DataSchema)
local MapBuilder = require(script.Parent.MapBuilder)
local CycleService = require(script.Parent.CycleService)
local EggService = require(script.Parent.EggService)
local PetService = require(script.Parent.PetService)
local IndexService = require(script.Parent.IndexService)

type IncubatorRecord = Types.IncubatorRecord

type Visual = {
	part: BasePart,
	label: TextLabel,
}

local Attr = Tags.PlayerAttributes

local BaseService = {}

local plotOwners: { [number]: Player } = {}
local visuals: { [Player]: { [string]: Visual } } = {}

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
	for index = 1, MapBuilder.plotCount() do
		if plotOwners[index] == nil and MapBuilder.getPlot(index) then
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

function BaseService.releasePlot(player: Player)
	for index, owner in plotOwners do
		if owner == player then
			plotOwners[index] = nil
			MapBuilder.setPlotOwner(index, nil)
		end
	end
end

function BaseService.teleportHome(player: Player)
	local session = Sessions.get(player)
	local character = player.Character
	if not session or not character or session.plotIndex == 0 then
		return
	end
	local plot = MapBuilder.getPlot(session.plotIndex)
	local target = if plot then (plot.spawn or plot.floor) else nil
	if target then
		character:PivotTo(CFrame.new(target.Position + Vector3.new(0, 4, 0)))
	end
end

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

local function createVisual(player: Player, record: IncubatorRecord)
	local session = Sessions.get(player)
	if not session or session.plotIndex == 0 then
		return
	end
	local plot = MapBuilder.getPlot(session.plotIndex)
	local slotPart = if plot then plot.incubatorSlots[record.slot] else nil
	if not slotPart then
		return
	end
	local size = Sizes.get(record.size)
	local petDef = Pets.get(record.petId)
	local rarity = if petDef then Rarities.get(petDef.rarity) else nil
	local d = Config.EGG_BASE_DIAMETER * (if size then size.eggScale else 1)
	local part = Instance.new("Part")
	part.Name = "Incubating_" .. record.uid
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(d, d * 1.25, d)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Color = if rarity
		then Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
		else Color3.new(1, 1, 1)
	part.CFrame = CFrame.new(slotPart.Position + Vector3.new(0, slotPart.Size.Y / 2 + part.Size.Y / 2, 0))
	part:SetAttribute("EggUid", record.uid)
	part:SetAttribute("OwnerUserId", player.UserId)
	part:SetAttribute("PetId", record.petId)
	part:SetAttribute("SlotIndex", record.slot)
	part:SetAttribute("Progress", record.progress)
	part:SetAttribute("Required", record.required)
	part:SetAttribute("Ready", record.progress >= record.required)
	CollectionService:AddTag(part, Tags.IncubatingEgg)
	part.Parent = MapBuilder.getFolder("Incubating")
	local label = Gui.billboard(part, visualText(record, 1), d + 1.5, 60)

	local perPlayer = visuals[player]
	if not perPlayer then
		perPlayer = {}
		visuals[player] = perPlayer
	end
	perPlayer[record.uid] = { part = part, label = label }
end

local function destroyVisual(player: Player, uid: string)
	local perPlayer = visuals[player]
	local visual = if perPlayer then perPlayer[uid] else nil
	if perPlayer and visual then
		visual.part:Destroy()
		perPlayer[uid] = nil
	end
end

------------------------------------------------------------------
-- 배달 / 부화
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
	local egg = EggService.takeCarried(player)
	if not egg then
		return
	end
	local record: IncubatorRecord = {
		uid = DataSchema.newUid(data, "i"),
		petId = egg.petId,
		size = egg.size,
		mutations = egg.mutations,
		biomeId = egg.biomeId,
		slot = slot,
		progress = 0,
		required = Economy.hatchSeconds(egg.petId),
	}
	table.insert(data.incubators, record)
	createVisual(player, record)
	Net.fire(player, Remotes.ToClient.EggDelivered, record)
	Snapshot.section(player, "incubators")
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
	PetService.addPet(player, pet)
	local isNew = IndexService.discover(player, record.petId)
	data.stats.eggsHatched = (data.stats.eggsHatched or 0) + 1
	Net.fire(player, Remotes.ToClient.HatchResult, {
		pet = pet,
		isNew = isNew,
		income = Economy.recordIncome(pet),
		equipped = table.find(data.equipped, pet.uid) ~= nil,
	})
	Snapshot.section(player, "incubators")
end

------------------------------------------------------------------
-- 주기 처리
------------------------------------------------------------------

-- 1초마다: 알 자라기
local function growTick(dt: number)
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

-- 0.2초마다: 배달 패드 확인, 안전 구역 표시
local function baseTick()
	local carriers = EggService.carriers()
	for player, session in Sessions.all() do
		local root = Character.getRoot(player)
		if root then
			local inSafe = MapBuilder.isInSafeZone(root.Position)
			if inSafe ~= session.inSafeZone then
				session.inSafeZone = inSafe
				player:SetAttribute(Attr.InSafeZone, inSafe)
			end
			if carriers[player] and session.plotIndex > 0 then
				local plot = MapBuilder.getPlot(session.plotIndex)
				local pad = if plot then plot.deliveryPad else nil
				if pad then
					local dx = root.Position.X - pad.Position.X
					local dz = root.Position.Z - pad.Position.Z
					local dy = math.abs(root.Position.Y - pad.Position.Y)
					if dx * dx + dz * dz <= Config.DELIVERY_RADIUS * Config.DELIVERY_RADIUS and dy < 10 then
						BaseService.deliver(player)
					end
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
	BaseService.releasePlot(player)
end

function BaseService.start()
	Net.on(Remotes.ToServer.HatchEgg, function(player: Player, uid: unknown)
		local eggUid = Validate.uid(uid)
		if eggUid then
			BaseService.hatch(player, eggUid)
		end
	end)

	-- 밤: 알 든 사람 → 자기 베이스로
	CycleService.changed:connect(function(phase: Types.Phase)
		if phase ~= "Night" then
			return
		end
		for player in EggService.carriers() do
			local root = Character.getRoot(player)
			local session = Sessions.get(player)
			if root and session and not MapBuilder.isInPlot(session.plotIndex, root.Position) then
				BaseService.teleportHome(player)
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
