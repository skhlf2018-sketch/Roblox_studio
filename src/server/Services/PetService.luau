--!strict
--[[
	PetService — 6판 "씨앗을 훔치세요": 정원의 성체 식물 (5판 펫 보관함·장착 자리. 파일·함수 이름은 5판 그대로 둠)

	6판 용어: 펫 = 성체 식물 · 우리 = 정원 · 쓰다듬기(PetPet) = 물 주기 · 돈 = 코인
	  - data.pets = 정원에 서 있는 성체 식물 목록 (PetRecord: uid, petId(식물 id), size, mutations, x, z, fruits, fruitProgress)
	    씨앗이 다 자라면 BaseService 가 그 자리·uid 그대로 addPlant. 자라는 씨앗(data.incubators) + 성체 ≤ 정원 칸 수
	  - "장착/보관함" 개념은 없앰 (5판 EquipPet·UnequipPet·EquipBest·보관함 500 상한·자동 판매·SellPet 삭제)
	  - 자동 수입 없음 (IncomeService 삭제) — 코인은 열매(FruitService)
	  - 신호 plantsChanged(player): 성체 목록이 바뀜 → BaseService 가 정원 파트(GardenPlant)를 맞춤

	Remote:
	  SellPlant(plantUid) — 성체를 뽑아서 팔기. 검증: uid 형식 · 내 정원의 성체 · 내 정원(울타리 사각형) 에서
	    GARDEN_ACTION_RADIUS(20) 안 또는 판매 가판대 SELL_RADIUS(14) 안. 값 = 열매 1개 값 × 20 (GardenRules.sellPrice)
	    (코인 2배 게임패스면 × 2). 정원 자리가 빔 → Notify + DataUpdate("pets")
	  PetPet(uid) — 물 주기 (5판 쓰다듬기 자리). uid = 내 정원의 자라는 씨앗(성장 +WATER_GROWTH_SECONDS 10초) 또는
	    성체(다음 열매까지 +10초). 검증: uid 형식 · 내 정원의 것 · 내 정원 PET_PET_RADIUS(20) 안 · 사람마다 PET_PET_COOLDOWN(1초)
	    · 식물마다 WATER_COOLDOWN(60초, 아직이면 Notify info). 통과하면 PetPetted(ownerUserId, uid) 를 서버 전체에
	    (물방울·소리 연출은 클라). 다 자란 씨앗은 BaseService 다음 1초 틱에 성체가 됨.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Plants = require(Shared.Data.Plants)
local Economy = require(Shared.Economy)
local GardenRules = require(Shared.GardenRules)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local MapLayout = require(Shared.Data.MapLayout)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)
local Character = require(Server.Util.Character)
local Landmarks = require(Server.Util.Landmarks)
local Signal = require(Server.Util.Signal)
local Wallet = require(script.Parent.Wallet)

type PetRecord = Types.PetRecord

local Attr = Tags.PlayerAttributes

local PetService = {}

-- 성체 목록이 바뀜 (player) — 성체가 됨 / 팔림 / 바침 / 돌연변이 → BaseService 정원 파트 맞추기
PetService.plantsChanged = Signal.new()

local function coins(n: number): string
	return Format.number(n) .. " 코인"
end

local function plantName(petId: string): string
	local plant = Plants.get(petId)
	return if plant then plant.name else petId
end

-- 정원 레벨·칸 수 Attribute (UpgradeService 가 정원 업그레이드 뒤에도 부름)
function PetService.recalc(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	player:SetAttribute(Attr.PenLevel, data.penLevel)
	player:SetAttribute(Attr.PenSlots, Economy.penSlots(data.penLevel))
end

local function indexOf(data: Types.PlayerData, uid: string): number?
	for i, pet in data.pets do
		if pet.uid == uid then
			return i
		end
	end
	return nil
end

-- 내 정원의 성체 찾기
function PetService.findPlant(player: Player, uid: string): PetRecord?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	local i = indexOf(data, uid)
	return if i then data.pets[i] else nil
end

-- [5판 이름] = findPlant
function PetService.findPet(player: Player, uid: string): PetRecord?
	return PetService.findPlant(player, uid)
end

-- 정원에 하나 더 들어갈 자리가 있나 (자라는 씨앗 + 성체 < 정원 칸 수)
function PetService.hasGardenRoom(player: Player): boolean
	local _, data = Sessions.getLoaded(player)
	return data ~= nil and GardenRules.hasRoom(#data.incubators, #data.pets, data.penLevel)
end

-- 성체를 정원에 더함 (씨앗이 다 자람 · 개발 명령 /plant). 정원이 가득 찼거나 같은 uid 가 있으면 false
function PetService.addPlant(player: Player, record: PetRecord): boolean
	local _, data = Sessions.getLoaded(player)
	if not data or indexOf(data, record.uid) then
		return false
	end
	if not GardenRules.hasRoom(#data.incubators, #data.pets, data.penLevel) then
		return false
	end
	table.insert(data.pets, record)
	Snapshot.section(player, "pets")
	PetService.plantsChanged:fire(player)
	return true
end

-- 성체 여러 그루 없애기 (사쿠라 나무에 바치기 등). 전부 있어야 함 (하나라도 없으면 아무것도 안 함)
function PetService.removePlants(player: Player, uids: { string }): { PetRecord }?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	for _, uid in uids do
		if not indexOf(data, uid) then
			return nil
		end
	end
	local removed: { PetRecord } = {}
	for _, uid in uids do
		local i = indexOf(data, uid)
		if i then
			table.insert(removed, table.remove(data.pets, i) :: PetRecord)
		end
	end
	Snapshot.section(player, "pets")
	PetService.plantsChanged:fire(player)
	return removed
end

-- 성체 속성(돌연변이·열매)이 바뀐 뒤
function PetService.changed(player: Player)
	Snapshot.section(player, "pets")
	PetService.plantsChanged:fire(player)
end

-- 판매 가판대 근처인가: 맵의 SellStall 태그 파트 표면 또는 MapLayout 판매 자리(허브 + 베이스마다)에서 SELL_RADIUS 안
function PetService.isNearSellStall(player: Player): boolean
	local root = Character.getRoot(player)
	if not root or not Character.isAlive(player) then
		return false
	end
	if Landmarks.nearest(player, Landmarks.tagged(Tags.SellStall), Config.SELL_RADIUS) then
		return true
	end
	local p = root.Position
	for _, spot in MapLayout.sellSpots() do
		local dx, dz = p.X - spot.x, p.Z - spot.z
		if dx * dx + dz * dz <= Config.SELL_RADIUS * Config.SELL_RADIUS then
			return true
		end
	end
	return false
end

-- 내 캐릭터가 내 정원(울타리 사각형) 에서 radius 안인가 (수평 거리, 정원 안이면 0)
function PetService.isNearOwnPen(player: Player, radius: number): boolean
	local session = Sessions.get(player)
	local root = Character.getRoot(player)
	if not session or session.plotIndex == 0 or not root or not Character.isAlive(player) then
		return false
	end
	local rect = MapLayout.penRect(session.plotIndex)
	if not rect then
		return false
	end
	local p = root.Position
	local dx = math.max(rect.xMin - p.X, 0, p.X - rect.xMax)
	local dz = math.max(rect.zMin - p.Z, 0, p.Z - rect.zMax)
	return dx * dx + dz * dz <= radius * radius
end

-- 코인 2배 게임패스 배율 (플래그만)
function PetService.coinMultiplier(player: Player): number
	local session = Sessions.get(player)
	return if session and session.hasMoneyPass then Config.GAMEPASS_MONEY_MULTIPLIER else 1
end

-- SellPlant: 성체를 뽑아서 팔기. 받은 코인 (못 팔면 nil)
function PetService.sellPlant(player: Player, uid: string): number?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	local record = PetService.findPlant(player, uid)
	if not record then
		return nil -- 남의 식물·이상한 uid (조용히)
	end
	if not PetService.isNearOwnPen(player, Config.GARDEN_ACTION_RADIUS) and not PetService.isNearSellStall(player) then
		Net.notify(player, "error", "내 정원이나 판매 가판대 가까이에서 뽑아서 팔 수 있어요!")
		return nil
	end
	local price = GardenRules.sellPrice(record) * PetService.coinMultiplier(player)
	if not PetService.removePlants(player, { uid }) then
		return nil
	end
	Wallet.addMoney(player, price)
	data.stats.plantsSold = (data.stats.plantsSold or 0) + 1
	Net.notify(
		player,
		"success",
		string.format(
			"%s 을(를) 뽑아서 %s 에 팔았어요! 정원 자리가 생겼어요.",
			plantName(record.petId),
			coins(price)
		)
	)
	return price
end

-- [5판 이름] = sellPlant
function PetService.sell(player: Player, uid: string): number?
	return PetService.sellPlant(player, uid)
end

-- PetPet = 물 주기: 자라는 씨앗 성장 +10초 / 성체 다음 열매 +10초 → PetPetted 서버 전체. 성공하면 true
function PetService.petPet(player: Player, uid: string): boolean
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return false
	end
	local seed: Types.IncubatorRecord? = nil
	for _, record in data.incubators do
		if record.uid == uid then
			seed = record
			break
		end
	end
	local plant = if seed then nil else PetService.findPlant(player, uid)
	if not seed and not plant then
		return false -- 내 정원의 것이 아님
	end
	if not PetService.isNearOwnPen(player, Config.PET_PET_RADIUS) then
		return false
	end
	local now = os.clock()
	if not Sessions.useCooldown(session, "petPet", Config.PET_PET_COOLDOWN, now) then
		return false
	end
	local key = "water:" .. uid
	local last = session.cooldowns[key]
	if last and now - last < Config.WATER_COOLDOWN then
		Net.notify(
			player,
			"info",
			string.format(
				"이 식물은 %d초 뒤에 또 물을 줄 수 있어요.",
				math.ceil(Config.WATER_COOLDOWN - (now - last))
			)
		)
		return false
	end
	session.cooldowns[key] = now
	if seed then
		seed.progress = GardenRules.watered(seed.progress, seed.required)
		Snapshot.section(player, "incubators")
	elseif plant then
		local interval = Economy.fruitInterval(plant.petId)
		if plant.fruits < Config.FRUIT_MAX_PER_PLANT and interval ~= math.huge then
			plant.fruitProgress = math.min(interval, plant.fruitProgress + Config.WATER_GROWTH_SECONDS)
		end
		Snapshot.section(player, "pets")
	end
	data.stats.watered = (data.stats.watered or 0) + 1
	Net.fireAll(Remotes.ToClient.PetPetted, player.UserId, uid)
	return true
end

-- [6판 이름] = petPet
function PetService.water(player: Player, uid: string): boolean
	return PetService.petPet(player, uid)
end

function PetService.onPlayerReady(player: Player)
	PetService.recalc(player)
end

function PetService.start()
	Net.on(Remotes.ToServer.SellPlant, function(player: Player, uid: unknown)
		local plantUid = Validate.uid(uid)
		if plantUid then
			PetService.sellPlant(player, plantUid)
		end
	end)
	Net.on(Remotes.ToServer.PetPet, function(player: Player, uid: unknown)
		local id = Validate.uid(uid)
		if id then
			PetService.petPet(player, id)
		end
	end)
end

return PetService
