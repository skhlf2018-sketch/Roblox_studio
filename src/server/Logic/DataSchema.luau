--!strict
--[[
	DataSchema — 저장 데이터 기본값 / 검증·보정(reconcile) / 마이그레이션 (순수 로직, Lune 테스트 대상)

	스키마 버전 7 (7판 — 칸 모양은 6판 "씨앗을 훔치세요" 그대로). 불러온 데이터는 믿지 않고 reconcile 로 한 칸씩 검사합니다.
	(모르는 식물 id, 잘못된 숫자, 중복 uid, 정원 칸 수 초과 등은 고치거나 버림)
	6판 용어: pets = 정원의 성체 식물, incubators = 정원에 심어 자라는 씨앗, eggs = 씨앗 가방, fruits = 열매 가방, money = 코인

	버전 기록:
	  1~5 (계란 훔치기): 돈·속도·펫·장착·업그레이드·도감·도구·알·트레일(3)·알 가방(4)·튜토리얼(5)
	  6 (6판 씨앗을 훔치세요, 새 게임): + fruits (열매 가방). pets 한 칸 = 성체 식물 { uid, petId, size, mutations,
	     x, z(심은 자리), fruits(달린 열매), fruitProgress }. equipped(장착)·sakuraUnlocked·shrineUsed 칸 없앰.
	     5 이하 → 6: **초기화** (사장님 지시: 새 사람으로 시작). 남기는 것 = 속도(speed)·트레일(trails, equippedTrail)·
	       러닝머신 레벨(treadmillLevel) 만. 펫·알·돈·도감·정원(우리) 레벨·곰덫·무기·크리스탈·통계는 버리고 튜토리얼 1단계부터.
	       (옛 펫 id 는 6판 식물에 없어서 어차피 못 씀. 3 이전 데이터는 장착 트레일이 없으니 가진 것 중 최고를 장착)
	  7 (7판): 칸 모양은 6 그대로. 성장 3배(Config.GROWTH_SPEED_MULTIPLIER) → 씨앗 Required = 표 시간 ÷ 3.
	     6 → 7: 정원·가방 씨앗의 progress 를 "자란 비율" 이 같게 새 Required 에 맞춤 (rescaleProgress). 등급 16개로
	     바뀌었지만 저장 데이터에는 등급 id 가 없고(식물 id 만) 옛 슈퍼 울트라디바인 식물 2종은 id 그대로라 보정할 것 없음.
	  보정: 정원(자라는 씨앗 + 성체)이 정원 칸 수를 넘으면 자라는 씨앗은 가방으로, 그래도 넘치는 성체는 코인으로 바꿈
	        (팔기 값 = GardenRules.sellPrice). 자리가 깨진 씨앗·성체는 빈 격자 자리로.
	  저장된 버전이 지금 서버보다 크면(롤백·순차 배포 중) DataService 가 이번 접속 저장을 끔 → 새 필드 보호
	  (DataSchema.isNewerVersion)
	경고 카운트(치트 방지)는 저장하지 않음.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Plants = require(Shared.Data.Plants)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local Upgrades = require(Shared.Data.Upgrades)
local Weapons = require(Shared.Data.Weapons)
local Economy = require(Shared.Economy)
local EggPlacement = require(Shared.EggPlacement)
local GardenRules = require(Shared.GardenRules)
local Progression = require(Shared.Progression)
local TutorialRules = require(Shared.TutorialRules)
local Types = require(Shared.Types)

type PlayerData = Types.PlayerData
type PetRecord = Types.PetRecord
type IncubatorRecord = Types.IncubatorRecord
type BagEgg = Types.BagEgg

local DataSchema = {}

DataSchema.VERSION = Config.SCHEMA_VERSION

-- 6판 초기화 때 남기는 옛 칸 (속도·트레일·러닝머신)
DataSchema.KEPT_ON_RESET = { "speed", "trails", "equippedTrail", "treadmillLevel" }

function DataSchema.default(_now: number): PlayerData
	-- _now 는 나중 스키마(가입 시각 등)용으로 받아 둠
	return {
		version = Config.SCHEMA_VERSION,
		money = Config.STARTING_MONEY,
		speed = Config.STARTING_SPEED,
		pets = {},
		penLevel = 1,
		treadmillLevel = 0,
		trails = {},
		indexDiscovered = {},
		indexClaimed = {},
		indexCompleteClaimed = false,
		tools = { bearTrap = Config.STARTING_BEAR_TRAPS },
		incubators = {},
		lastSaveTime = 0,
		nextUid = 1,
		stats = { eggsStolen = 0, eggsHatched = 0 },
		weapons = {},
		sakuraCrystals = 0,
		equippedTrail = Upgrades.NO_TRAIL,
		eggs = {},
		tutorialStep = 1, -- 처음 온 사람은 튜토리얼 1단계부터
		fruits = {},
	}
end

------------------------------------------------------------------
-- 작은 검사 도우미
------------------------------------------------------------------

local function finiteNonNegative(value: unknown, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	local n = value :: number
	if n ~= n or n == math.huge or n == -math.huge or n < 0 then
		return fallback
	end
	return n
end

local function integerIn(value: unknown, minValue: number, maxValue: number, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	local n = value :: number
	if n ~= n then
		return fallback
	end
	return math.clamp(math.floor(n), minValue, maxValue)
end

local function isUid(value: unknown): boolean
	return typeof(value) == "string" and #(value :: string) > 0 and #(value :: string) <= 48
end

-- 알려진 돌연변이만, 같은 group 은 첫 번째만 남김
function DataSchema.cleanMutations(value: unknown): { string }
	local result: { string } = {}
	if typeof(value) ~= "table" then
		return result
	end
	local groups: { [string]: boolean } = {}
	for _, id in value :: { unknown } do
		if typeof(id) == "string" then
			local mutation = Mutations.get(id :: string)
			if mutation and not groups[mutation.group] then
				groups[mutation.group] = true
				table.insert(result, mutation.id)
			end
		end
	end
	return result
end

local function cleanSize(value: unknown): string
	if typeof(value) == "string" and Sizes.get(value :: string) then
		return value :: string
	end
	return Sizes.DEFAULT
end

local function uidNumber(uid: string): number
	local digits = string.match(uid, "(%d+)$")
	return if digits then (tonumber(digits) or 0) else 0
end

-- 저장 데이터의 version (없으면 1)
function DataSchema.versionOf(raw: unknown): number
	if typeof(raw) ~= "table" then
		return 1
	end
	local v = (raw :: { [string]: unknown }).version
	if typeof(v) == "number" and v == v then
		return v :: number
	end
	return 1
end

-- 지금 서버보다 새 버전 서버가 저장한 데이터인가 (이 경우 저장을 꺼야 함)
function DataSchema.isNewerVersion(raw: unknown): boolean
	return typeof(raw) == "table" and DataSchema.versionOf(raw) > Config.SCHEMA_VERSION
end

-- 아무 값 → 도감 발견 표 (알려진 식물만)
local function cleanDiscovered(value: unknown): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if typeof(value) == "table" then
		for petId, flag in value :: { [unknown]: unknown } do
			if typeof(petId) == "string" and flag == true and Plants.get(petId :: string) then
				result[petId :: string] = true
			end
		end
	end
	return result
end

-- 씨앗 항목(가방·심은 씨앗 공용) → 올바른 BagEgg 모양, 안 되면 nil. uid 는 seenUid 에 기록 (중복이면 nil)
-- required 는 지금 데이터(Plants.growSeconds)로 다시 계산, progress 는 0 ~ required
local function cleanEgg(entry: unknown, seenUid: { [string]: boolean }): BagEgg?
	if typeof(entry) ~= "table" then
		return nil
	end
	local e = entry :: { [string]: unknown }
	local uid, petId = e.uid, e.petId
	if not isUid(uid) or seenUid[uid :: string] or typeof(petId) ~= "string" then
		return nil
	end
	local plant = Plants.get(petId :: string)
	if not plant then
		return nil
	end
	seenUid[uid :: string] = true
	local required = Economy.growSeconds(plant.id)
	return {
		uid = uid :: string,
		petId = plant.id,
		size = cleanSize(e.size),
		mutations = DataSchema.cleanMutations(e.mutations),
		biomeId = plant.biome,
		special = e.special == true,
		progress = math.min(required, finiteNonNegative(e.progress, 0)),
		required = required,
	}
end

local function finiteOrNil(value: unknown): number?
	if typeof(value) ~= "number" then
		return nil
	end
	local n = value :: number
	if n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

-- 정원 자리 (저장된 x, z 가 쓸 수 있으면 그것, 아니면 빈 격자 자리, 없으면 nil)
type XZ = { x: number, z: number }

local function gardenSpot(e: { [string]: unknown }, size: string, taken: { EggPlacement.Spot }): XZ?
	local lx, lz = finiteOrNil(e.x), finiteOrNil(e.z)
	if lx and lz and EggPlacement.check(lx, lz, size, taken) then
		return { x = lx, z = lz }
	end
	return EggPlacement.firstFreeGrid(size, taken)
end
------------------------------------------------------------------
-- reconcile: 아무 값이나 받아 올바른 PlayerData 로 (버전 6 모양)
------------------------------------------------------------------

function DataSchema.reconcile(raw: unknown, now: number): PlayerData
	local data = DataSchema.default(now)
	if typeof(raw) ~= "table" then
		return data
	end
	local src = raw :: { [string]: unknown }

	data.money = math.min(Config.MONEY_MAX, finiteNonNegative(src.money, data.money))
	data.speed = math.min(Config.SPEED_MAX, finiteNonNegative(src.speed, data.speed))
	data.penLevel = integerIn(src.penLevel, 1, Upgrades.PEN_MAX_LEVEL, 1)
	data.treadmillLevel = integerIn(src.treadmillLevel, 0, Upgrades.TREADMILL_MAX_LEVEL, 0)
	data.lastSaveTime = finiteNonNegative(src.lastSaveTime, 0)
	data.indexCompleteClaimed = src.indexCompleteClaimed == true

	local maxUid = 0
	local seenUid: { [string]: boolean } = {}
	local capacity = GardenRules.capacity(data.penLevel)
	local taken: { EggPlacement.Spot } = {} -- 정원에서 이미 차지한 자리 (성체 + 자라는 씨앗)

	-- 정원의 성체 식물 (6판). 칸 수를 넘거나 자리가 없으면 코인으로 바꿈
	local soldCoins = 0
	if typeof(src.pets) == "table" then
		for _, entry in src.pets :: { unknown } do
			if typeof(entry) == "table" then
				local e = entry :: { [string]: unknown }
				local uid, petId = e.uid, e.petId
				local plant = if typeof(petId) == "string" then Plants.get(petId :: string) else nil
				if isUid(uid) and not seenUid[uid :: string] and plant then
					seenUid[uid :: string] = true
					maxUid = math.max(maxUid, uidNumber(uid :: string))
					local size = cleanSize(e.size)
					local mutations = DataSchema.cleanMutations(e.mutations)
					local spot = if #data.pets < capacity then gardenSpot(e, size, taken) else nil
					if spot then
						local record: PetRecord = {
							uid = uid :: string,
							petId = plant.id,
							size = size,
							mutations = mutations,
							x = spot.x,
							z = spot.z,
							fruits = integerIn(e.fruits, 0, Config.FRUIT_MAX_PER_PLANT, 0),
							fruitProgress = math.min(
								finiteNonNegative(e.fruitProgress, 0),
								Economy.fruitInterval(plant.id)
							),
						}
						table.insert(data.pets, record)
						table.insert(taken, { x = spot.x, z = spot.z, size = size })
					else
						soldCoins += GardenRules.sellPrice({ petId = plant.id, size = size, mutations = mutations })
					end
				end
			end
		end
	end
	if soldCoins > 0 then
		data.money = math.min(Config.MONEY_MAX, data.money + soldCoins)
	end

	-- 트레일
	if typeof(src.trails) == "table" then
		local owned: { [string]: boolean } = {}
		for _, id in src.trails :: { unknown } do
			if typeof(id) == "string" and Upgrades.getTrail(id :: string) and not owned[id :: string] then
				owned[id :: string] = true
				table.insert(data.trails, id :: string)
			end
		end
	end
	-- 장착 트레일: 가진 것만, 아니면 해제
	if typeof(src.equippedTrail) == "string" and table.find(data.trails, src.equippedTrail :: string) then
		data.equippedTrail = src.equippedTrail :: string
	end

	-- 도감
	data.indexDiscovered = cleanDiscovered(src.indexDiscovered)
	if typeof(src.indexClaimed) == "table" then
		for petId, flag in src.indexClaimed :: { [unknown]: unknown } do
			if typeof(petId) == "string" and flag == true and data.indexDiscovered[petId :: string] then
				data.indexClaimed[petId :: string] = true
			end
		end
	end

	-- 도구
	if typeof(src.tools) == "table" then
		local tools = src.tools :: { [string]: unknown }
		data.tools.bearTrap = integerIn(tools.bearTrap, 0, Config.BEAR_TRAP_MAX_OWNED, data.tools.bearTrap)
	end

	-- 정원에 심어 자라는 씨앗. 자리가 깨졌으면 빈 격자 자리로, 칸 수를 넘거나 자리가 없으면 가방으로
	local toBag: { BagEgg } = {}
	if typeof(src.incubators) == "table" then
		for _, entry in src.incubators :: { unknown } do
			local egg = cleanEgg(entry, seenUid)
			if egg then
				maxUid = math.max(maxUid, uidNumber(egg.uid))
				local spot = if #data.pets + #data.incubators < capacity
					then gardenSpot(entry :: { [string]: unknown }, egg.size, taken)
					else nil
				if spot then
					local record: IncubatorRecord = {
						uid = egg.uid,
						petId = egg.petId,
						size = egg.size,
						mutations = egg.mutations,
						biomeId = egg.biomeId,
						special = egg.special,
						x = spot.x,
						z = spot.z,
						progress = egg.progress,
						required = egg.required,
					}
					table.insert(data.incubators, record)
					table.insert(taken, { x = spot.x, z = spot.z, size = egg.size })
				else
					table.insert(toBag, egg)
				end
			end
		end
	end

	-- 씨앗 가방: 저장된 가방 → (자리가 없어 넘친 씨앗) 순서, EGG_INVENTORY_MAX 까지
	if typeof(src.eggs) == "table" then
		for _, entry in src.eggs :: { unknown } do
			if #data.eggs >= Config.EGG_INVENTORY_MAX then
				break
			end
			local egg = cleanEgg(entry, seenUid)
			if egg then
				maxUid = math.max(maxUid, uidNumber(egg.uid))
				table.insert(data.eggs, egg)
			end
		end
	end
	for _, egg in toBag do
		if #data.eggs < Config.EGG_INVENTORY_MAX then
			table.insert(data.eggs, egg)
		end
	end

	-- 열매 가방 (6판): 알려진 식물 id 만, 개수는 정수, 합은 FRUIT_BAG_MAX 까지
	if typeof(src.fruits) == "table" then
		local total = 0
		for petId, stack in src.fruits :: { [unknown]: unknown } do
			if typeof(petId) == "string" and Plants.get(petId :: string) and typeof(stack) == "table" then
				local s = stack :: { [string]: unknown }
				local count = integerIn(s.count, 0, Config.FRUIT_BAG_MAX, 0)
				count = math.min(count, Config.FRUIT_BAG_MAX - total)
				if count > 0 then
					local value = math.min(Config.MONEY_MAX, finiteNonNegative(s.value, 0))
					data.fruits[petId :: string] = { count = count, value = value }
					total += count
				end
			end
		end
	end

	-- 통계
	if typeof(src.stats) == "table" then
		for key, value in src.stats :: { [unknown]: unknown } do
			if typeof(key) == "string" and typeof(value) == "number" then
				data.stats[key :: string] = finiteNonNegative(value, 0)
			end
		end
	end

	-- 무기: 저장된 것(알려진 구역 무기만) ∪ 지금 도감 기록으로 해금되는 것 (규칙이 바뀌어도 잃지 않음)
	local weaponSet: { [string]: boolean } = {}
	if typeof(src.weapons) == "table" then
		for _, id in src.weapons :: { unknown } do
			if typeof(id) == "string" then
				local weapon = Weapons.get(id :: string)
				if weapon and weapon.biome then
					weaponSet[weapon.id] = true
				end
			end
		end
	end
	for _, id in Progression.unlockedWeapons(data.indexDiscovered) do
		weaponSet[id] = true
	end
	for _, weapon in Weapons.list do -- 데이터 순서대로 (구역 순서)
		if weaponSet[weapon.id] then
			table.insert(data.weapons, weapon.id)
		end
	end

	data.sakuraCrystals = integerIn(src.sakuraCrystals, 0, Config.SAKURA_CRYSTAL_MAX, 0)

	-- 튜토리얼 단계 (1 ~ DONE 정수). 칸이 없으면 끝난 것으로 (이상한 저장 데이터에 튜토리얼이 다시 뜨지 않게.
	-- 6판 초기화로 온 사람은 migrate 가 1 을 넣어 둠)
	data.tutorialStep = TutorialRules.clean(src.tutorialStep, TutorialRules.DONE)

	-- uid 카운터는 기존 uid 보다 항상 크게
	data.nextUid = math.max(integerIn(src.nextUid, 1, 2 ^ 52, 1), maxUid + 1)

	data.version = Config.SCHEMA_VERSION
	return data
end

-- 6 → 7: 씨앗 한 칸의 진행도를 새 Required(Economy.growSeconds = 표 ÷ 3)에 같은 비율로 맞춤. 고쳤으면 true
function DataSchema.rescaleProgress(entry: unknown): boolean
	if typeof(entry) ~= "table" then
		return false
	end
	local e = entry :: { [string]: unknown }
	local petId = e.petId
	local plant = if typeof(petId) == "string" then Plants.get(petId :: string) else nil
	local progress = e.progress
	if not plant or typeof(progress) ~= "number" then
		return false
	end
	local p = progress :: number
	if p ~= p or p < 0 then
		return false
	end
	local saved = e.required
	local oldRequired = plant.growSeconds
	if typeof(saved) == "number" then
		local s = saved :: number
		if s == s and s > 0 and s < math.huge then
			oldRequired = s
		end
	end
	local fraction = math.clamp(p / oldRequired, 0, 1)
	local newRequired = Economy.growSeconds(plant.id)
	e.progress = fraction * newRequired
	e.required = newRequired
	return true
end

-- 버전 마이그레이션 (reconcile 전에 실행). 표를 그 자리에서 고쳐서 돌려줌.
function DataSchema.migrate(raw: unknown): unknown
	if typeof(raw) ~= "table" then
		return raw
	end
	local src = raw :: { [string]: unknown }
	local version = DataSchema.versionOf(src)
	if version < 6 then
		-- 5 이하 → 6 (6판 새 게임): 속도·트레일·러닝머신 레벨만 남기고 초기화. 튜토리얼은 1단계부터
		local equippedTrail = src.equippedTrail
		if version < 3 then
			-- 3 이전: 장착 트레일 칸이 없었고 가진 것 중 최고 배율이 자동 적용 → 그 트레일을 장착 (속도가 안 바뀜)
			local owned: { string } = {}
			if typeof(src.trails) == "table" then
				for _, id in src.trails :: { unknown } do
					if typeof(id) == "string" then
						table.insert(owned, id :: string)
					end
				end
			end
			equippedTrail = Economy.bestTrailId(owned)
		end
		local kept: { [string]: unknown } = {}
		for _, key in DataSchema.KEPT_ON_RESET do
			kept[key] = src[key]
		end
		kept.equippedTrail = equippedTrail
		table.clear(src)
		for key, value in kept do
			src[key] = value
		end
		src.tutorialStep = 1
		src.resetFromVersion = version -- 기록용 (reconcile 이 버리므로 저장 데이터에 남지 않음)
		version = 6
	end
	if version < 7 then
		-- 6 → 7 (7판 성장 3배): 씨앗 Required 가 표 시간 ÷ 3 으로 줄었으므로, 정원·가방 씨앗의 진행도(progress)도
		-- 같은 "자란 비율" 이 되게 새 Required 에 맞춤 (안 하면 3분의 1 넘게 자란 씨앗이 접속하자마자 성체가 됨).
		-- 저장된 required 가 쓸 수 있으면 그것, 아니면 표 시간(6판 Required) 기준. 이상한 칸은 reconcile 이 고침
		for _, key in { "incubators", "eggs" } do
			local entries = src[key]
			if typeof(entries) == "table" then
				for _, entry in entries :: { unknown } do
					DataSchema.rescaleProgress(entry)
				end
			end
		end
		version = 7
	end
	-- 더 새 버전 서버가 저장한 데이터(version > SCHEMA_VERSION)는 그대로 둠
	-- (DataService 가 isNewerVersion 으로 확인해서 이번 접속 저장을 끔)
	src.version = version
	return src
end

-- 새 uid (플레이어 안에서만 유일하면 됨): prefix .. 숫자
function DataSchema.newUid(data: PlayerData, prefix: string): string
	local n = data.nextUid
	data.nextUid = n + 1
	return prefix .. tostring(n)
end

return DataSchema
