--!strict
--[[
	BaseService — 베이스 플롯 배정(서버 7명 = 7칸), 배달(→ 씨앗 가방), 정원에 씨앗 심기·다시 줍기, 성장 → 성체,
	              건너뛰기, 정원 파트(자라는 씨앗·성체 식물), 구역 표시, 밤 텔레포트

	6판 "씨앗을 훔치세요" 용어 (모듈·Remote 이름은 5판 그대로):
	  알 → 씨앗 · 우리(pen) → 정원 · 부화 → 성체 되기 · 펫 → 성체 식물 · 돈 → 코인
	  data.eggs = 씨앗 가방 · data.incubators = 정원에 심어 자라는 씨앗 · data.pets = 정원의 성체 식물 (PetService)

	배달 (2판 수정 그대로): 씨앗을 든 채 허브(안전 구역, MapLayout.isInHub = z < 0)에 들어오는 순간 자동.
	    경비 추격 끝(ChaseEnded reason "safe")과 같은 순간. 베이스가 없는 사람(8번째)도 똑같이 받음.
	    → 씨앗 가방(data.eggs, 최대 EGG_INVENTORY_MAX)으로 → EggDelivered(BagEgg) + DataUpdate("eggs")
	      + BaseService.delivered:fire(player, bagEgg) (사쿠라 크리스탈·튜토리얼)
	    가방이 가득 차면 배달 안 됨: 씨앗은 손에 그대로, 안내는 3초에 한 번.
	심기 — Remote PlaceEgg(eggUid, x, z) (월드 x, z):
	    검증: 내 베이스가 있음 · 가방에 그 씨앗 · 정원에 빈칸(자라는 씨앗 + 성체 < 정원 칸 수 = 정원 업그레이드 칸)
	          · 내가 내 베이스 안(또는 그 자리 14 안) · 그 자리가 내 정원 안(울타리에서 2 안쪽)
	          · 다른 씨앗·성체 식물과 간격 (shared/EggPlacement)
	    → data.incubators 에 베이스 기준 좌표(x, z)로 저장 → 그 자리에 IncubatingEgg 파트 + 자라기 시작
	다시 줍기 — Remote PickUpPlacedEgg(eggUid): 아직 자라는 씨앗을 가방으로 (자란 만큼 유지, Config.ALLOW_EGG_PICKUP)
	성장 (1초마다): 심은 씨앗만 자람 (진행 += 1 × 성장 속도, 밤 30배, 게임패스 2배 플래그). 가방 속 씨앗은 안 자람.
	    단계 = GardenRules.stage → IncubatingEgg 파트 Attribute "Stage" (sprout/stem/bud)
	    100% 가 되면 **그 자리에서 성체** (부화 버튼 없음): incubators 에서 빼고 같은 uid·자리로 PetService.addPlant
	      (열매 Config.FRUITS_ON_ADULT(1)개 달린 채) → IndexService.discover (도감) → PlantGrown + Notify
	      → BaseService.grown:fire(player, plantRecord) (튜토리얼 4단계). IncubatingEgg 파트가 GardenPlant 파트로 바뀜
	건너뛰기 — Remote SkipGrowth(eggUid, "all" | "half"): 코인으로 남은 성장 시간 전부/절반 (GardenRules.skipCost:
	    남은 1분당 10코인 × 등급 배수). 코인이 모자라면 Notify error. 거리 검사 없음 (화면 버튼)
	선물 씨앗(grantEgg: 사쿠라 나무 뽑기·개발 명령)도 가방으로. 가방이 차면 못 받음
	0.2초마다 구역 표시: 플레이어 Attr CurrentZone(구역 id | "hub" | ""), InSafeZone(허브 안),
	    새 구역에 들어가면 ZoneEntered { biomeId, name, nameEn } 1회 (허브는 안 보냄)
	밤이 되면: 허브 밖(z ≥ 0)에 있던 사람 → 자기 베이스로 순간이동 (밤 벽에 안 갇히게). 베이스가 없으면 허브 기본 스폰.
	오프라인 동안에도 심은 씨앗은 자랍니다 (밤 가속 없이 실제 시간, 상한 24시간) — 접속하면 다 자란 것은 바로 성체.

	정원 파트 (선임이 모양을 꾸미는 자리, 서버는 단순한 공 + 이름표만 만듦):
	  IncubatingEgg (자라는 씨앗): Attr EggUid, OwnerUserId, PlotIndex, PetId, Size, Mutations, Special, Progress, Required,
	    Ready, Stage — 1초마다 갱신
	  GardenPlant (성체): Attr PlantUid, OwnerUserId, PlotIndex, PetId, Size, Mutations, Stage = "adult", Fruits, FruitMax,
	    FruitValue, FruitInterval, FruitProgress — 1초마다 갱신 (열매는 FruitService 가 맺음)

	2단계 (그대로): 순간이동 치트 방지 (배달 너무 빠름 → 씨앗은 둥지로, 든 채 순간이동 → 이전 위치에 떨어뜨림),
	  베이스가 없는 사람(plotIndex = 0)은 누가 나가서 베이스가 비면 바로 배정 + 집으로 이동
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local MapLayout = require(Shared.Data.MapLayout)
local Plants = require(Shared.Data.Plants)
local Rarities = require(Shared.Data.Rarities)
local Sizes = require(Shared.Data.Sizes)
local Economy = require(Shared.Economy)
local EggPlacement = require(Shared.EggPlacement)
local GardenRules = require(Shared.GardenRules)
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
local Wallet = require(script.Parent.Wallet)

type IncubatorRecord = Types.IncubatorRecord
type BagEgg = Types.BagEgg
type PetRecord = Types.PetRecord

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

-- 씨앗을 들고 허브에 들어와 가방에 들어감 (player, egg: BagEgg) → 사쿠라 크리스탈·튜토리얼
BaseService.delivered = Signal.new()
-- 정원에 씨앗을 심음 (player, IncubatorRecord) / 심은 씨앗을 다시 가방으로 (player, BagEgg)
BaseService.placed = Signal.new()
BaseService.unplaced = Signal.new()
-- 6판: 심은 씨앗이 성체가 됨 (player, PetRecord) — 튜토리얼 4단계
BaseService.grown = Signal.new()

local plotOwners: { [number]: Player? } = {}
local visuals: { [Player]: { [string]: Visual } } = {} -- 자라는 씨앗 파트 (uid →)
local plantVisuals: { [Player]: { [string]: Visual } } = {} -- 성체 식물 파트 (uid →)
local carryTracks: { [Player]: CarryTrack } = {}

local function coins(n: number): string
	return Format.number(n) .. " 코인"
end

local function plantName(petId: string): string
	local plant = Plants.get(petId)
	return if plant then plant.name else petId
end

------------------------------------------------------------------
-- 정원 파트 (선임 EggVisualService / 식물 모양이 꾸밈)
------------------------------------------------------------------

local function seedText(record: IncubatorRecord): string
	local stage = GardenRules.stage(record.progress, record.required)
	-- 남은 "성장 시간"을 그대로 보여 줌 (밤에는 이 숫자가 30배 빨리 줄어듦)
	return string.format(
		"%s\n%s · %s",
		Plants.seedName(record.petId),
		GardenRules.stageName(stage),
		Format.duration(Economy.timerSeconds(record.progress, record.required))
	)
end

local function plantText(record: PetRecord): string
	return string.format("%s\n열매 %d/%d", plantName(record.petId), record.fruits, Config.FRUIT_MAX_PER_PLANT)
end

-- 바닥 높이 (아래로 레이캐스트: 정원 바닥 윗면)
local function floorAt(spot: MapLayout.XZ): number
	return MapBuilder.groundY(Vector3.new(spot.x, MapLayout.FLOOR_Y + 1, spot.z), {})
end

local function rarityColor(petId: string): Color3
	local plant = Plants.get(petId)
	local rarity = if plant then Rarities.get(plant.rarity) else nil
	return if rarity then Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3]) else Color3.new(1, 1, 1)
end

-- 공 모양 파트 하나 (자리·크기·색). 선임이 모양을 바꾸면 이 함수만 손보면 됨
local function gardenBall(
	name: string,
	spot: MapLayout.XZ,
	diameter: number,
	heightScale: number,
	color: Color3
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "EggShape"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, heightScale, 1)
	mesh.Parent = part
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Color = color
	part.CFrame = CFrame.new(spot.x, floorAt(spot) + diameter * heightScale / 2, spot.z)
	return part
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
	local d = Config.EGG_BASE_DIAMETER * (if size then size.eggScale else 1)
	local part = gardenBall("Incubating_" .. record.uid, spot, d, 1.25, rarityColor(record.petId))
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
	part:SetAttribute("Stage", GardenRules.stage(record.progress, record.required))
	CollectionService:AddTag(part, Tags.IncubatingEgg)
	part.Parent = MapBuilder.getFolder("Incubating")
	local label = Gui.billboard(part, seedText(record), d * 1.25 + 1.5, 60)

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

-- 성체 파트 Attribute (FruitProgress 는 열매 수가 바뀔 때만 — 매초 복제하지 않게. 클라는 FruitInterval 로 이어 셈)
local function setPlantAttributes(part: BasePart, record: PetRecord)
	local fruitsChanged = part:GetAttribute("Fruits") ~= record.fruits
	part:SetAttribute("Mutations", table.concat(record.mutations, ","))
	part:SetAttribute("Fruits", record.fruits)
	part:SetAttribute("FruitValue", Economy.recordFruitValue(record))
	if fruitsChanged then
		part:SetAttribute("FruitProgress", record.fruitProgress)
	end
end

local function createPlantVisual(player: Player, plotIndex: number, record: PetRecord)
	local spot = MapLayout.toWorld(plotIndex, record.x, record.z)
	if not spot then
		return
	end
	local size = Sizes.get(record.size)
	local d = Config.EGG_BASE_DIAMETER * 1.6 * (if size then size.eggScale else 1)
	local part = gardenBall("Plant_" .. record.uid, spot, d, 1.6, rarityColor(record.petId))
	part:SetAttribute("PlantUid", record.uid)
	part:SetAttribute("OwnerUserId", player.UserId)
	part:SetAttribute("PlotIndex", plotIndex)
	part:SetAttribute("PetId", record.petId)
	part:SetAttribute("Size", record.size)
	part:SetAttribute("Stage", "adult")
	part:SetAttribute("FruitMax", Config.FRUIT_MAX_PER_PLANT)
	part:SetAttribute("FruitInterval", Economy.fruitInterval(record.petId))
	setPlantAttributes(part, record)
	CollectionService:AddTag(part, Tags.GardenPlant)
	part.Parent = MapBuilder.getFolder("Incubating")
	local label = Gui.billboard(part, plantText(record), d * 1.6 + 1.5, 60)
	local list: { [string]: Visual } = plantVisuals[player] or {}
	plantVisuals[player] = list
	list[record.uid] = { part = part, label = label }
end

-- 성체 파트를 data.pets 에 맞춤 (새로 생긴 것 만들기, 없어진 것 지우기, 나머지 Attribute 갱신)
local function syncPlants(player: Player)
	local session, data = Sessions.getLoaded(player)
	local list: { [string]: Visual } = plantVisuals[player] or {}
	plantVisuals[player] = list
	local alive: { [string]: PetRecord } = {}
	if session and data and session.plotIndex > 0 then
		for _, record in data.pets do
			alive[record.uid] = record
		end
	end
	for uid, visual in list do
		if not alive[uid] then
			visual.part:Destroy()
			list[uid] = nil
		end
	end
	if not session or session.plotIndex == 0 then
		return
	end
	for uid, record in alive do
		local visual = list[uid]
		if visual then
			setPlantAttributes(visual.part, record)
			visual.label.Text = plantText(record)
		else
			createPlantVisual(player, session.plotIndex, record)
		end
	end
end

-- 정원 파트 전부 지우기 (나갈 때·베이스가 바뀔 때)
local function clearVisuals(player: Player)
	local seeds = visuals[player]
	if seeds then
		for _, visual in seeds do
			visual.part:Destroy()
		end
		visuals[player] = nil
	end
	local adults = plantVisuals[player]
	if adults then
		for _, visual in adults do
			visual.part:Destroy()
		end
		plantVisuals[player] = nil
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

-- 정원에 심은 씨앗 기록 찾기
function BaseService.findIncubator(player: Player, uid: string): IncubatorRecord?
	local _, data = Sessions.getLoaded(player)
	local index = if data then incubatorIndex(data, uid) else nil
	return if data and index then data.incubators[index] else nil
end

-- 가방 속 씨앗 찾기
function BaseService.findBagEgg(player: Player, uid: string): BagEgg?
	local _, data = Sessions.getLoaded(player)
	local index = if data then bagIndex(data, uid) else nil
	return if data and index then data.eggs[index] else nil
end

-- 심은 씨앗의 돌연변이가 바뀌었을 때 겉모습 Attribute 갱신
function BaseService.refreshIncubator(player: Player, uid: string)
	local record = BaseService.findIncubator(player, uid)
	local perPlayer = visuals[player]
	local visual = if perPlayer then perPlayer[uid] else nil
	if record and visual then
		visual.part:SetAttribute("Mutations", table.concat(record.mutations, ","))
	end
	Snapshot.section(player, "incubators")
end

-- 가방 속 씨앗이 바뀌었을 때
function BaseService.refreshBag(player: Player)
	Snapshot.section(player, "eggs")
end

-- 성체 파트를 바로 맞춤 (PetService.plantsChanged 에도 연결됨)
function BaseService.refreshPlants(player: Player)
	syncPlants(player)
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

-- 서버 순간이동 (위치 검증 쉼 + 씨앗 배달 기준점 옮김). look 방향을 바라봄
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

-- 늦게 베이스를 받은 사람: 정원 파트 + 집으로 + 상태 다시 보내기
local function onPlotAssigned(player: Player)
	local session, data = Sessions.getLoaded(player)
	if session and data then
		for _, record in data.incubators do
			createVisual(player, record)
		end
		syncPlants(player)
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
-- 배달 (→ 가방) / 선물 씨앗 / 정원에 심기·다시 줍기
------------------------------------------------------------------

local function newBagEgg(
	data: Types.PlayerData,
	petId: string,
	size: string,
	mutations: { string },
	special: boolean
): BagEgg
	local plant = Plants.get(petId)
	return {
		uid = DataSchema.newUid(data, "i"),
		petId = petId,
		size = size,
		mutations = table.clone(mutations),
		biomeId = if plant then plant.biome else "",
		special = special,
		progress = 0,
		required = Economy.growSeconds(petId),
	}
end

local function bagFullText(): string
	return string.format(
		"씨앗 가방이 가득 찼어요 (%d개)! 가방의 씨앗을 정원에 심어 주세요.",
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

-- 들고 있는 씨앗을 가방으로 (baseTick 이 허브 안에서 부름)
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

-- 선물 씨앗을 받을 자리가 있나 (가방에 빈칸)
function BaseService.canReceiveEgg(player: Player): boolean
	local _, data = Sessions.getLoaded(player)
	return data ~= nil and #data.eggs < Config.EGG_INVENTORY_MAX
end

-- 선물 씨앗 (사쿠라 나무 뽑기 "sakura" · 개발 명령 "dev"): 가방으로. 가방이 가득 찼거나 모르는 식물이면 nil
function BaseService.grantEgg(
	player: Player,
	petId: string,
	size: string,
	mutations: { string },
	source: string
): GrantResult?
	local _, data = Sessions.getLoaded(player)
	if not data or not Plants.get(petId) or #data.eggs >= Config.EGG_INVENTORY_MAX then
		return nil
	end
	local egg = newBagEgg(data, petId, size, mutations, false)
	table.insert(data.eggs, egg)
	-- queued 는 2단계 클라 호환용 (대기 줄은 없어져서 항상 false)
	Net.fire(player, Remotes.ToClient.EggGranted, { egg = egg, queued = false, source = source })
	Snapshot.section(player, "eggs")
	return "bag"
end

-- 정원에서 차지한 자리 (EggPlacement 용, 로컬 좌표): 자라는 씨앗 + 성체 식물
local function gardenSpots(data: Types.PlayerData): { EggPlacement.Spot }
	local spots: { EggPlacement.Spot } = {}
	for _, record in data.incubators do
		table.insert(spots, { x = record.x, z = record.z, size = record.size })
	end
	for _, record in data.pets do
		table.insert(spots, { x = record.x, z = record.z, size = record.size })
	end
	return spots
end

-- 정원의 빈 격자 자리 (개발 명령 /plant 등)
function BaseService.freeGardenSpot(player: Player, sizeId: string): MapLayout.XZ?
	local _, data = Sessions.getLoaded(player)
	return if data then EggPlacement.firstFreeGrid(sizeId, gardenSpots(data)) else nil
end

-- PlaceEgg: 가방의 씨앗을 내 정원 (x, z)(월드)에 심음 → 자라기 시작. 성공하면 true
function BaseService.placeEgg(player: Player, uid: string, x: number, z: number): boolean
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return false
	end
	local index = bagIndex(data, uid)
	if not index then
		return false -- 가방에 없는 씨앗 (남의 것·이미 심은 것·이상한 uid)
	end
	if session.plotIndex == 0 then
		Net.notify(
			player,
			"error",
			"아직 내 베이스가 없어요! 베이스를 받으면 씨앗을 심을 수 있어요."
		)
		return false
	end
	if not GardenRules.hasRoom(#data.incubators, #data.pets, data.penLevel) then
		Net.notify(player, "error", EggPlacement.message("full"))
		return false
	end
	local root = Character.getRoot(player)
	if not root then
		return false
	end
	local near = MoveCheck.horizontalDistance(root.Position.X, root.Position.Z, x, z) <= Config.EGG_PLACE_RADIUS
	if not near and not MapLayout.isInPlot(root.Position, session.plotIndex) then
		Net.notify(player, "error", "내 베이스 정원 가까이에서 심어 주세요!")
		return false
	end
	local l = MapLayout.toLocal(session.plotIndex, { x = x, z = z })
	if not l then
		return false
	end
	local egg = data.eggs[index]
	local lx, lz = EggPlacement.round(l.x), EggPlacement.round(l.z)
	local ok, reason = EggPlacement.check(lx, lz, egg.size, gardenSpots(data))
	if not ok then
		Net.notify(player, "error", EggPlacement.message(reason))
		return false
	end
	table.remove(data.eggs, index)
	local required = Economy.growSeconds(egg.petId)
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
	BaseService.placed:fire(player, record)
	return true
end

-- PickUpPlacedEgg: 자라는 씨앗을 다시 가방으로 (자란 만큼 유지). 성공하면 true
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
	local bagEgg: BagEgg = {
		uid = record.uid,
		petId = record.petId,
		size = record.size,
		mutations = record.mutations,
		biomeId = record.biomeId,
		special = record.special,
		progress = record.progress,
		required = record.required,
	}
	table.insert(data.eggs, bagEgg)
	Snapshot.section(player, "eggs")
	Snapshot.section(player, "incubators")
	BaseService.unplaced:fire(player, bagEgg)
	return true
end

------------------------------------------------------------------
-- 성장 → 성체 / 건너뛰기
------------------------------------------------------------------

-- 다 자란 씨앗 하나를 그 자리에서 성체로 (quiet = 접속 때 오프라인 성장: 알림·PlantGrown 을 한 번에 몰아서). 성체 기록
local function becomeAdult(player: Player, data: Types.PlayerData, record: IncubatorRecord, quiet: boolean): PetRecord?
	local index = incubatorIndex(data, record.uid)
	if not index then
		return nil
	end
	table.remove(data.incubators, index)
	destroyVisual(player, record.uid)
	local plant: PetRecord = {
		uid = record.uid,
		petId = record.petId,
		size = record.size,
		mutations = record.mutations,
		x = record.x,
		z = record.z,
		fruits = math.min(Config.FRUITS_ON_ADULT, Config.FRUIT_MAX_PER_PLANT),
		fruitProgress = 0,
	}
	if not PetService.addPlant(player, plant) then
		-- 정원이 가득 찬 일은 없어야 함 (씨앗이 칸을 차지하고 있었음) — 만약 그래도 넘치면 씨앗으로 되돌림
		table.insert(data.incubators, index, record)
		createVisual(player, record)
		return nil
	end
	local isNew = IndexService.discover(player, record.petId)
	data.stats.eggsHatched = (data.stats.eggsHatched or 0) + 1
	Net.fire(player, Remotes.ToClient.PlantGrown, {
		plant = plant,
		isNew = isNew,
		fruitValue = Economy.recordFruitValue(plant),
		fruitInterval = Economy.fruitInterval(plant.petId),
	})
	if not quiet then
		Net.notify(
			player,
			"success",
			plantName(plant.petId)
				.. " 이(가) 성체가 됐어요! 열매를 따 보세요."
				.. (if isNew then " (도감 새로 발견!)" else "")
		)
	end
	Snapshot.section(player, "incubators")
	BaseService.grown:fire(player, plant)
	return plant
end

-- 정원의 다 자란 씨앗을 전부 성체로 (성체가 된 수)
local function growReady(player: Player, data: Types.PlayerData, quiet: boolean): number
	local ready: { IncubatorRecord } = {}
	for _, record in data.incubators do
		if record.progress >= record.required then
			table.insert(ready, record)
		end
	end
	local count = 0
	for _, record in ready do
		if becomeAdult(player, data, record, quiet) then
			count += 1
		end
	end
	return count
end

-- 다 자란 씨앗을 바로 성체로 (개발 명령 /grow 등)
function BaseService.growReadyNow(player: Player): number
	local _, data = Sessions.getLoaded(player)
	return if data then growReady(player, data, false) else 0
end

-- SkipGrowth: 코인으로 남은 성장 시간 전부("all")/절반("half"). 성공하면 낸 코인 (못 하면 nil)
function BaseService.skipGrowth(player: Player, uid: string, mode: GardenRules.SkipMode): number?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	local record = BaseService.findIncubator(player, uid)
	if not record then
		return nil -- 내 정원에 자라는 씨앗이 아님 (조용히)
	end
	local seconds = GardenRules.skipSeconds(record.progress, record.required, mode)
	local cost = GardenRules.skipCost(record.petId, record.progress, record.required, mode)
	if not cost or seconds <= 0 then
		return nil
	end
	if not Wallet.trySpend(player, cost) then
		Net.notify(player, "error", "코인이 부족해요! (" .. coins(cost) .. " 필요)")
		return nil
	end
	record.progress = math.min(record.required, record.progress + seconds)
	data.stats.skips = (data.stats.skips or 0) + 1
	local perPlayer = visuals[player]
	local visual = if perPlayer then perPlayer[record.uid] else nil
	if visual then
		visual.part:SetAttribute("Progress", record.progress)
		visual.part:SetAttribute("Stage", GardenRules.stage(record.progress, record.required))
		visual.label.Text = seedText(record)
	end
	Snapshot.section(player, "incubators")
	if record.progress >= record.required then
		Net.notify(player, "success", coins(cost) .. " 로 성장을 건너뛰었어요!")
		becomeAdult(player, data, record, false)
	else
		Net.notify(
			player,
			"success",
			string.format(
				"%s 로 성장 시간을 절반 건너뛰었어요! (남은 %s)",
				coins(cost),
				Format.duration(record.required - record.progress)
			)
		)
	end
	return cost
end

------------------------------------------------------------------
-- 주기 처리
------------------------------------------------------------------

-- 1초마다: 심은 씨앗 자라기 (가방 속 씨앗은 안 자람) → 다 자라면 성체. 성체 파트 Attribute 갱신
local function growTick(dt: number): ...any
	local isNight = CycleService.isNight()
	for player, session in Sessions.all() do
		local data = session.data
		if session.loaded and data then
			local rate = Economy.growthRate(isNight, session.hasGrowthPass)
			local anyReady = false
			for _, record in data.incubators do
				local progress, ready = Economy.advanceIncubation(record.progress, record.required, dt, rate)
				record.progress = progress
				if ready then
					anyReady = true
				end
				local perPlayer = visuals[player]
				local visual = if perPlayer then perPlayer[record.uid] else nil
				if visual then
					visual.part:SetAttribute("Progress", progress)
					visual.part:SetAttribute("Ready", ready)
					visual.part:SetAttribute("Stage", GardenRules.stage(progress, record.required))
					visual.label.Text = seedText(record)
				end
			end
			if anyReady then
				growReady(player, data, false)
			end
			syncPlants(player)
		end
	end
end

-- 씨앗 든 사람이 한 틱에 너무 멀리 움직였나 (순간이동) → 이전 위치에 씨앗을 떨어뜨림
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
		AntiCheatService.flag(player, "씨앗을 든 채 너무 멀리 순간이동했어요")
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

-- 0.2초마다: 구역 표시, 씨앗 든 사람 순간이동 검사, 씨앗을 든 채 허브(안전 구역)에 들어오면 배달
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

-- 접속 준비 (FruitService.onPlayerReady 다음: 오프라인 열매는 이미 성체였던 식물만)
function BaseService.onPlayerReady(player: Player)
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	-- 오프라인 동안 자란 만큼 (심은 씨앗만, 밤 가속 없음)
	local offline = Economy.offlineGrowthSeconds(data.lastSaveTime, os.time())
	local rate = Economy.growthRate(false, session.hasGrowthPass)
	for _, record in data.incubators do
		record.progress = Economy.advanceIncubation(record.progress, record.required, offline, rate)
	end
	local grown = growReady(player, data, true)
	if grown > 0 then
		Net.notify(
			player,
			"success",
			string.format("자리를 비운 동안 씨앗 %d개가 성체가 됐어요!", grown)
		)
	end
	for _, record in data.incubators do
		createVisual(player, record)
	end
	syncPlants(player)
end

function BaseService.onCharacterAdded(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		task.wait() -- 엔진이 스폰 위치에 놓은 다음 프레임에 옮김
		BaseService.teleportHome(player)
	end
end

function BaseService.onPlayerLeaving(player: Player)
	clearVisuals(player)
	carryTracks[player] = nil
	BaseService.releasePlot(player)
end

function BaseService.start()
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
	Net.on(Remotes.ToServer.SkipGrowth, function(player: Player, uid: unknown, mode: unknown)
		local eggUid = Validate.uid(uid)
		local skipMode = Validate.oneOf(mode, Remotes.SkipModes)
		if eggUid and skipMode then
			BaseService.skipGrowth(player, eggUid, skipMode :: GardenRules.SkipMode)
		end
	end)

	PetService.plantsChanged:connect(function(player: Player)
		syncPlants(player)
	end)

	-- 밤: 허브 밖(z ≥ 0)에 있던 사람 → 자기 베이스로 (밤 벽이 허브 경계 z = 0 을 막으므로 밖에 갇히지 않게).
	--   씨앗을 들고 있었으면 베이스(허브 안)에 도착하자마자 다음 틱에 가방으로 배달
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
