--!strict
--[[
	DataSchema — 저장 데이터 기본값 / 검증·보정(reconcile) / 마이그레이션 (순수 로직, Lune 테스트 대상)

	스키마 버전 5. 불러온 데이터는 믿지 않고 reconcile 로 한 칸씩 검사합니다.
	(모르는 펫 id, 잘못된 숫자, 중복 uid, 칸 수 초과 장착 등은 고치거나 버림)

	버전 기록:
	  1 (1단계) 돈·속도·펫·장착·업그레이드·도감·도구·부화 슬롯·통계
	  2 (2단계) + weapons(해금 무기), sakuraCrystals, sakuraUnlocked, shrineUsed, quests, questsRewarded, eggQueue
	     1 → 2: weapons 를 도감 발견 기록으로 채움 (나머지는 기본값)
	  3 (2판 마무리) + equippedTrail (장착한 트레일, "none" = 해제). 배율은 장착한 트레일만 적용
	     2 → 3: 가진 트레일 중 가장 높은 배율을 장착 (전에는 그게 자동 적용이었음 → 속도 그대로)
	  4 (2판 수정) + eggs (알 가방, 최대 EGG_INVENTORY_MAX). 놓인 알(incubators)은 슬롯 번호 대신 베이스 기준 x, z
	     3 → 4: 부화 슬롯 n번 알 → 우리 안 격자 자리 MapLayout.eggGridLocal(n) (1~8 = 옛 슬롯 자리 그대로)
	     옛 선물 알 대기 줄(eggQueue)은 reconcile 이 가방 뒤에 새 uid 로 붙임 (저장 데이터에 남지 않음)
	  5 (5판) + tutorialStep (튜토리얼 단계 1~5, 6 = 끝). 퀘스트(quests, questsRewarded)·무료 보상(freeRewardClaimed) 칸 없앰
	     4 → 5: 이미 놀던 사람(펫·놓인 알·가방 알이 있거나 알을 훔친/배달한/부화한 적 있음)은 튜토리얼 끝(6),
	            아무것도 안 한 사람은 1단계부터 (TutorialRules.migratedStep). 옛 칸 3개는 지움 (보상으로 받은 속도·알은 그대로)
	  놓인 알 보정: 위치가 없거나 우리 밖·다른 알과 겹치면 빈 격자 자리로, PLACED_EGG_MAX 를 넘거나 자리가 없으면 가방으로
	  (알은 버리지 않음 — 가방까지 가득 찰 때만 버림)
	  저장된 버전이 지금 서버보다 크면(롤백·순차 배포 중) DataService 가 이번 접속 저장을 끔 → 새 필드 보호
	  (DataSchema.isNewerVersion)
	경고 카운트(치트 방지)는 저장하지 않음.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local MapLayout = require(Shared.Data.MapLayout)
local Pets = require(Shared.Data.Pets)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local Upgrades = require(Shared.Data.Upgrades)
local Weapons = require(Shared.Data.Weapons)
local Economy = require(Shared.Economy)
local EggPlacement = require(Shared.EggPlacement)
local Progression = require(Shared.Progression)
local AltarRules = require(Shared.AltarRules)
local TutorialRules = require(Shared.TutorialRules)
local Types = require(Shared.Types)

type PlayerData = Types.PlayerData
type PetRecord = Types.PetRecord
type IncubatorRecord = Types.IncubatorRecord
type BagEgg = Types.BagEgg

local DataSchema = {}

DataSchema.VERSION = Config.SCHEMA_VERSION

function DataSchema.default(_now: number): PlayerData
	-- _now 는 나중 스키마(가입 시각 등)용으로 받아 둠
	return {
		version = Config.SCHEMA_VERSION,
		money = Config.STARTING_MONEY,
		speed = Config.STARTING_SPEED,
		pets = {},
		equipped = {},
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
		sakuraUnlocked = false,
		shrineUsed = {},
		equippedTrail = Upgrades.NO_TRAIL,
		eggs = {},
		tutorialStep = 1, -- 5판: 처음 온 사람은 튜토리얼 1단계부터
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

-- 아무 값 → 도감 발견 표 (알려진 펫만)
local function cleanDiscovered(value: unknown): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if typeof(value) == "table" then
		for petId, flag in value :: { [unknown]: unknown } do
			if typeof(petId) == "string" and flag == true and Pets.get(petId :: string) then
				result[petId :: string] = true
			end
		end
	end
	return result
end

-- 알 항목(가방·놓인 알 공용) → 올바른 BagEgg 모양, 안 되면 nil. uid 는 seenUid 에 기록 (중복이면 nil)
-- required 는 지금 성장 배율로 다시 계산, progress 는 0 ~ required
local function cleanEgg(entry: unknown, seenUid: { [string]: boolean }): BagEgg?
	if typeof(entry) ~= "table" then
		return nil
	end
	local e = entry :: { [string]: unknown }
	local uid, petId = e.uid, e.petId
	if not isUid(uid) or seenUid[uid :: string] or typeof(petId) ~= "string" then
		return nil
	end
	local pet = Pets.get(petId :: string)
	if not pet then
		return nil
	end
	seenUid[uid :: string] = true
	local required = Economy.hatchSeconds(pet.id)
	return {
		uid = uid :: string,
		petId = pet.id,
		size = cleanSize(e.size),
		mutations = DataSchema.cleanMutations(e.mutations),
		biomeId = pet.biome,
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

------------------------------------------------------------------
-- reconcile: 아무 값이나 받아 올바른 PlayerData 로
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

	-- 펫
	local seenUid: { [string]: boolean } = {}
	if typeof(src.pets) == "table" then
		for _, entry in src.pets :: { unknown } do
			if typeof(entry) == "table" then
				local e = entry :: { [string]: unknown }
				local uid, petId = e.uid, e.petId
				if
					isUid(uid)
					and not seenUid[uid :: string]
					and typeof(petId) == "string"
					and Pets.get(petId :: string)
				then
					seenUid[uid :: string] = true
					maxUid = math.max(maxUid, uidNumber(uid :: string))
					local record: PetRecord = {
						uid = uid :: string,
						petId = petId :: string,
						size = cleanSize(e.size),
						mutations = DataSchema.cleanMutations(e.mutations),
					}
					table.insert(data.pets, record)
				end
			end
		end
	end

	-- 장착: 있는 펫만, 중복 없이, 칸 수까지
	local slots = Economy.penSlots(data.penLevel)
	if typeof(src.equipped) == "table" then
		local used: { [string]: boolean } = {}
		for _, uid in src.equipped :: { unknown } do
			if #data.equipped >= slots then
				break
			end
			if typeof(uid) == "string" and seenUid[uid :: string] and not used[uid :: string] then
				used[uid :: string] = true
				table.insert(data.equipped, uid :: string)
			end
		end
	end

	-- 보관함 상한 (PET_INVENTORY_MAX): 넘치면 장착 안 된 펫 중 수입이 낮은 펫부터 팔고 돈으로 바꿈
	-- (PetService 의 자동 판매와 같은 규칙: 돈 = 초당 수입 × PET_AUTO_SELL_SECONDS)
	local excess = #data.pets - Config.PET_INVENTORY_MAX
	if excess > 0 then
		local equippedSet: { [string]: boolean } = {}
		for _, uid in data.equipped do
			equippedSet[uid] = true
		end
		local candidates: { { uid: string, income: number } } = {}
		for _, record in data.pets do
			if not equippedSet[record.uid] then
				table.insert(candidates, { uid = record.uid, income = Economy.recordIncome(record) })
			end
		end
		table.sort(candidates, function(a, b): boolean
			if a.income == b.income then
				return a.uid < b.uid
			end
			return a.income < b.income
		end)
		local sell: { [string]: boolean } = {}
		local earned = 0
		for i = 1, math.min(excess, #candidates) do
			sell[candidates[i].uid] = true
			earned += candidates[i].income * Config.PET_AUTO_SELL_SECONDS
		end
		local kept: { PetRecord } = {}
		for _, record in data.pets do
			if not sell[record.uid] then
				table.insert(kept, record)
			end
		end
		data.pets = kept
		data.money = math.min(Config.MONEY_MAX, data.money + earned)
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
	-- 장착 트레일 (버전 3): 가진 것만, 아니면 해제
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

	-- 우리에 놓인 알 (2판 수정: 베이스 기준 x, z). 자리가 깨졌으면 빈 격자 자리로, 넘치면 가방으로
	local placedSpots: { EggPlacement.Spot } = {}
	local toBag: { BagEgg } = {}
	if typeof(src.incubators) == "table" then
		for _, entry in src.incubators :: { unknown } do
			local egg = cleanEgg(entry, seenUid)
			if egg then
				maxUid = math.max(maxUid, uidNumber(egg.uid))
				local e = entry :: { [string]: unknown }
				local lx, lz = finiteOrNil(e.x), finiteOrNil(e.z)
				local spot: MapLayout.XZ? = nil
				if #data.incubators < Config.PLACED_EGG_MAX then
					if lx and lz and EggPlacement.check(lx, lz, egg.size, placedSpots) then
						spot = { x = lx, z = lz }
					else
						spot = EggPlacement.firstFreeGrid(egg.size, placedSpots)
					end
				end
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
					table.insert(placedSpots, { x = spot.x, z = spot.z, size = egg.size })
				else
					table.insert(toBag, egg)
				end
			end
		end
	end

	-- 알 가방 (2판 수정): 저장된 가방 → (자리가 없어 넘친 놓인 알) 순서, EGG_INVENTORY_MAX 까지
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

	-- 통계
	if typeof(src.stats) == "table" then
		for key, value in src.stats :: { [unknown]: unknown } do
			if typeof(key) == "string" and typeof(value) == "number" then
				data.stats[key :: string] = finiteNonNegative(value, 0)
			end
		end
	end

	------------------------------------------------------------------
	-- 버전 2 필드
	------------------------------------------------------------------

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
	data.sakuraUnlocked = src.sakuraUnlocked == true

	if typeof(src.shrineUsed) == "table" then
		local used = src.shrineUsed :: { [unknown]: unknown }
		for _, recipe in AltarRules.RECIPES do
			if used[recipe.result] == true then
				data.shrineUsed[recipe.result] = true
			end
		end
	end

	------------------------------------------------------------------
	-- 버전 5 필드
	------------------------------------------------------------------

	-- 튜토리얼 단계 (1 ~ DONE 정수). 저장 데이터에 칸이 없으면 끝난 것으로 (이미 놀던 사람에게 다시 안 뜨게)
	data.tutorialStep = TutorialRules.clean(src.tutorialStep, TutorialRules.DONE)

	-- uid 카운터는 기존 uid 보다 항상 크게
	data.nextUid = math.max(integerIn(src.nextUid, 1, 2 ^ 52, 1), maxUid + 1)

	-- 옛 선물 알 대기 줄 (버전 2·3 의 eggQueue) → 가방 뒤에 새 uid 로 (2판 수정에서 대기 줄 없앰)
	if typeof(src.eggQueue) == "table" then
		for _, entry in src.eggQueue :: { unknown } do
			if #data.eggs >= Config.EGG_INVENTORY_MAX then
				break
			end
			if typeof(entry) == "table" then
				local e = entry :: { [string]: unknown }
				local pet = if typeof(e.petId) == "string" then Pets.get(e.petId :: string) else nil
				if pet then
					table.insert(data.eggs, {
						uid = DataSchema.newUid(data, "i"),
						petId = pet.id,
						size = cleanSize(e.size),
						mutations = DataSchema.cleanMutations(e.mutations),
						biomeId = pet.biome,
						special = false,
						progress = 0,
						required = Economy.hatchSeconds(pet.id),
					})
				end
			end
		end
	end

	data.version = Config.SCHEMA_VERSION
	return data
end

-- 버전 마이그레이션 (reconcile 전에 실행). 표를 그 자리에서 고쳐서 돌려줌.
function DataSchema.migrate(raw: unknown): unknown
	if typeof(raw) ~= "table" then
		return raw
	end
	local src = raw :: { [string]: unknown }
	local version = DataSchema.versionOf(src)
	if version < 2 then
		-- 1 → 2: 해금 무기를 도감 발견 기록으로 채움 (2단계 규칙: 천사&악마는 합성 펫 제외 18종)
		src.weapons = Progression.unlockedWeapons(cleanDiscovered(src.indexDiscovered))
		src.sakuraCrystals = 0
		src.sakuraUnlocked = false
		src.shrineUsed = {}
		src.eggQueue = {}
		version = 2
	end
	if version < 3 then
		-- 2 → 3: 전에는 가진 것 중 최고 배율이 자동 적용 → 그 트레일을 장착한 상태로 (속도가 안 바뀜)
		local owned: { string } = {}
		if typeof(src.trails) == "table" then
			for _, id in src.trails :: { unknown } do
				if typeof(id) == "string" then
					table.insert(owned, id :: string)
				end
			end
		end
		src.equippedTrail = Economy.bestTrailId(owned)
		version = 3
	end
	if version < 4 then
		-- 3 → 4: 부화 슬롯 n번 알 → 우리 안 격자 자리 n (1~8 = 옛 슬롯 자리 그대로). 이상한 슬롯은 reconcile 이 빈 자리로
		-- (옛 eggQueue 는 reconcile 이 가방으로 옮김 — 새 uid 가 필요해서)
		if typeof(src.incubators) == "table" then
			for _, entry in src.incubators :: { unknown } do
				if typeof(entry) == "table" then
					local e = entry :: { [string]: unknown }
					local spot = if typeof(e.slot) == "number" then MapLayout.eggGridLocal(e.slot :: number) else nil
					if spot and e.x == nil and e.z == nil then
						e.x = spot.x
						e.z = spot.z
					end
					e.slot = nil
				end
			end
		end
		version = 4
	end
	if version < 5 then
		-- 4 → 5 (5판): 튜토리얼 단계 추가 (놀던 사람은 끝, 아무것도 안 한 사람은 1단계), 퀘스트·무료 보상 칸 지움
		src.tutorialStep = TutorialRules.migratedStep(src)
		src.quests = nil
		src.questsRewarded = nil
		src.freeRewardClaimed = nil
		version = 5
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
