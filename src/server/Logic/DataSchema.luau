--!strict
--[[
	DataSchema — 저장 데이터 기본값 / 검증·보정(reconcile) / 마이그레이션 (순수 로직, Lune 테스트 대상)

	스키마 버전 2. 불러온 데이터는 믿지 않고 reconcile 로 한 칸씩 검사합니다.
	(모르는 펫 id, 잘못된 숫자, 중복 uid, 칸 수 초과 장착 등은 고치거나 버림)

	버전 기록:
	  1 (1단계) 돈·속도·펫·장착·업그레이드·도감·도구·부화 슬롯·통계
	  2 (2단계) + weapons(해금 무기), sakuraCrystals, sakuraUnlocked, shrineUsed, quests, questsRewarded, eggQueue
	     1 → 2: weapons 를 도감 발견 기록으로 채움 (나머지는 기본값)
	  저장된 버전이 지금 서버보다 크면(롤백·순차 배포 중) DataService 가 이번 접속 저장을 끔 → 새 필드 보호
	  (DataSchema.isNewerVersion)
	경고 카운트(치트 방지)는 저장하지 않음.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local Upgrades = require(Shared.Data.Upgrades)
local Weapons = require(Shared.Data.Weapons)
local Quests = require(Shared.Data.Quests)
local Economy = require(Shared.Economy)
local Progression = require(Shared.Progression)
local AltarRules = require(Shared.AltarRules)
local Types = require(Shared.Types)

type PlayerData = Types.PlayerData
type PetRecord = Types.PetRecord
type IncubatorRecord = Types.IncubatorRecord
type QueuedEgg = Types.QueuedEgg

local DataSchema = {}

DataSchema.VERSION = Config.SCHEMA_VERSION

local QUEUE_SOURCES: { [string]: boolean } = { altar = true, shrine = true, quest = true }

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
		freeRewardClaimed = false,
		nextUid = 1,
		stats = { eggsStolen = 0, eggsHatched = 0 },
		weapons = {},
		sakuraCrystals = 0,
		sakuraUnlocked = false,
		shrineUsed = {},
		quests = {},
		questsRewarded = false,
		eggQueue = {},
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

------------------------------------------------------------------
-- reconcile: 아무 값이나 받아 올바른 PlayerData 로
------------------------------------------------------------------

function DataSchema.reconcile(raw: unknown, now: number): PlayerData
	local data = DataSchema.default(now)
	if typeof(raw) ~= "table" then
		return data
	end
	local src = raw :: { [string]: unknown }

	data.money = finiteNonNegative(src.money, data.money)
	data.speed = finiteNonNegative(src.speed, data.speed)
	data.penLevel = integerIn(src.penLevel, 1, Upgrades.PEN_MAX_LEVEL, 1)
	data.treadmillLevel = integerIn(src.treadmillLevel, 0, Upgrades.TREADMILL_MAX_LEVEL, 0)
	data.lastSaveTime = finiteNonNegative(src.lastSaveTime, 0)
	data.freeRewardClaimed = src.freeRewardClaimed == true
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
		data.tools.bearTrap = integerIn(tools.bearTrap, 0, 999, data.tools.bearTrap)
	end

	-- 부화 슬롯
	if typeof(src.incubators) == "table" then
		local usedSlots: { [number]: boolean } = {}
		for _, entry in src.incubators :: { unknown } do
			if typeof(entry) == "table" then
				local e = entry :: { [string]: unknown }
				local uid, petId = e.uid, e.petId
				local slot = if typeof(e.slot) == "number" then math.floor(e.slot :: number) else 0
				if slot < 1 or slot > Config.INCUBATOR_SLOTS then
					slot = 0 -- 범위 밖 슬롯은 버림
				end
				if
					isUid(uid)
					and not seenUid[uid :: string]
					and typeof(petId) == "string"
					and Pets.get(petId :: string)
					and slot >= 1
					and not usedSlots[slot]
				then
					seenUid[uid :: string] = true
					usedSlots[slot] = true
					maxUid = math.max(maxUid, uidNumber(uid :: string))
					local pet = Pets.get(petId :: string)
					local required = Economy.hatchSeconds(petId :: string) -- 성장 배율이 바뀌어도 맞게 다시 계산
					local record: IncubatorRecord = {
						uid = uid :: string,
						petId = petId :: string,
						size = cleanSize(e.size),
						mutations = DataSchema.cleanMutations(e.mutations),
						biomeId = if pet then pet.biome else "",
						slot = slot,
						progress = math.min(required, finiteNonNegative(e.progress, 0)),
						required = required,
					}
					table.insert(data.incubators, record)
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

	if typeof(src.quests) == "table" then
		local quests = src.quests :: { [unknown]: unknown }
		for _, quest in Quests.list do
			local value = integerIn(quests[quest.id], 0, quest.target, 0)
			if value > 0 then
				data.quests[quest.id] = value
			end
		end
	end
	data.questsRewarded = src.questsRewarded == true

	if typeof(src.eggQueue) == "table" then
		for _, entry in src.eggQueue :: { unknown } do
			if #data.eggQueue >= Config.EGG_QUEUE_MAX then
				break
			end
			if typeof(entry) == "table" then
				local e = entry :: { [string]: unknown }
				local petId, source = e.petId, e.source
				if typeof(petId) == "string" and Pets.get(petId :: string) then
					local queued: QueuedEgg = {
						petId = petId :: string,
						size = cleanSize(e.size),
						mutations = DataSchema.cleanMutations(e.mutations),
						source = if typeof(source) == "string" and QUEUE_SOURCES[source :: string]
							then source :: string
							else "altar",
					}
					table.insert(data.eggQueue, queued)
				end
			end
		end
	end

	-- uid 카운터는 기존 uid 보다 항상 크게
	data.nextUid = math.max(integerIn(src.nextUid, 1, 2 ^ 52, 1), maxUid + 1)
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
		src.quests = {}
		src.questsRewarded = false
		src.eggQueue = {}
		version = 2
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
