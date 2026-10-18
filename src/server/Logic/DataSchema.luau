--!strict
--[[
	DataSchema — 저장 데이터 기본값 / 검증·보정(reconcile) / 마이그레이션 (순수 로직, Lune 테스트 대상)

	스키마 버전 1. 불러온 데이터는 믿지 않고 reconcile 로 한 칸씩 검사합니다.
	(모르는 펫 id, 잘못된 숫자, 중복 uid, 칸 수 초과 장착 등은 고치거나 버림)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local Upgrades = require(Shared.Data.Upgrades)
local Economy = require(Shared.Economy)
local Types = require(Shared.Types)

type PlayerData = Types.PlayerData
type PetRecord = Types.PetRecord
type IncubatorRecord = Types.IncubatorRecord

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
		freeRewardClaimed = false,
		nextUid = 1,
		stats = { eggsStolen = 0, eggsHatched = 0 },
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
	if typeof(src.indexDiscovered) == "table" then
		for petId, flag in src.indexDiscovered :: { [unknown]: unknown } do
			if typeof(petId) == "string" and flag == true and Pets.get(petId :: string) then
				data.indexDiscovered[petId :: string] = true
			end
		end
	end
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

	-- uid 카운터는 기존 uid 보다 항상 크게
	data.nextUid = math.max(integerIn(src.nextUid, 1, 2 ^ 52, 1), maxUid + 1)
	data.version = Config.SCHEMA_VERSION
	return data
end

-- 버전 마이그레이션 (지금은 버전 1 하나뿐). 나중에 버전 2 가 생기면 여기서 변환.
function DataSchema.migrate(raw: unknown): unknown
	if typeof(raw) ~= "table" then
		return raw
	end
	local src = raw :: { [string]: unknown }
	local version = if typeof(src.version) == "number" then src.version :: number else 1
	-- 버전 1 → 2 변환이 생기면: if version < 2 then ... version = 2 end
	-- 더 새 버전 서버가 저장한 데이터(version > SCHEMA_VERSION)는 그대로 둠 (reconcile 이 아는 칸만 읽음)
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
