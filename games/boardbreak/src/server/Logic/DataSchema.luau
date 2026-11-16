--!strict
--[[
	DataSchema — 송판 깨기 저장 데이터 기본값 / 검증·보정(reconcile) / 마이그레이션 (순수 로직, Lune 테스트 대상)
	첫 게임 DataSchema 를 줄여 복사 (같은 함수 이름: default · reconcile · migrate · versionOf · isNewerVersion · cleanReceipts).

	스키마 1 (설계서 7장 "저장"): power · money · dumbbellLevel · belt · world · broken · powerBoost · moneyPass · grandMaster
	  · receipts · stats · settings · lastSaveTime.
	불러온 데이터는 믿지 않고 한 칸씩 검사:
	  - 힘·돈: 0 이상 유한수, 1e60 에서 자름 (NaN·무한·음수 → 0)
	  - dumbbellLevel 1~20 · belt 1~12 (정수) · world = 1 ~ 띠로 열리는 월드 (Progression.worldsFromBelt) — 띠보다 앞선 월드는 못 감
	  - broken: 아는 물건 id → 0 이상 정수만
	  - powerBoost: 1 또는 표의 배수 (2 … 2048) — 아니면 1 · moneyPass·grandMaster: bool (grandMaster 는 띠 12 일 때만)
	  - receipts: 1~64자 글자, 중복 없이 최근 RECEIPT_HISTORY_MAX 개 · stats: 칸마다 0 이상 유한수 · settings: 아는 키만 bool
	저장된 버전이 이 서버보다 크면 DataService 가 이번 접속 저장을 끔 (isNewerVersion).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Targets = require(Shared.Data.Targets)
local Dumbbells = require(Shared.Data.Dumbbells)
local Belts = require(Shared.Data.Belts)
local Economy = require(Shared.Economy)
local Progression = require(Shared.Progression)
local Types = require(Shared.Types)

type PlayerData = Types.PlayerData

local DataSchema = {}

DataSchema.VERSION = Config.SCHEMA_VERSION

DataSchema.STAT_KEYS = {
	"trains",
	"hits",
	"breaks",
	"moneyEarned",
	"examsPassed",
	"examsFailed",
	"duelsWon",
	"duelsLost",
	"playSeconds",
}

function DataSchema.defaultStats(): Types.Stats
	return {
		trains = 0,
		hits = 0,
		breaks = 0,
		moneyEarned = 0,
		examsPassed = 0,
		examsFailed = 0,
		duelsWon = 0,
		duelsLost = 0,
		playSeconds = 0,
	}
end

function DataSchema.defaultSettings(): Types.Settings
	return table.clone(Config.SETTINGS)
end

function DataSchema.default(_now: number): PlayerData
	return {
		version = Config.SCHEMA_VERSION,
		power = 0,
		money = 0,
		dumbbellLevel = 1,
		belt = 1,
		world = 1,
		broken = {},
		powerBoost = 1,
		moneyPass = false,
		grandMaster = false,
		receipts = {},
		stats = DataSchema.defaultStats(),
		settings = DataSchema.defaultSettings(),
		lastSaveTime = 0,
	}
end

------------------------------------------------------------------
-- 작은 검사 도우미
------------------------------------------------------------------

local function integerIn(value: unknown, minValue: number, maxValue: number, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	local n = value :: number
	if n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return math.clamp(math.floor(n), minValue, maxValue)
end

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

function DataSchema.isNewerVersion(raw: unknown): boolean
	return typeof(raw) == "table" and DataSchema.versionOf(raw) > Config.SCHEMA_VERSION
end

function DataSchema.cleanReceipts(value: unknown): { string }
	local result: { string } = {}
	if typeof(value) ~= "table" then
		return result
	end
	local seen: { [string]: boolean } = {}
	for _, id in value :: { unknown } do
		if typeof(id) == "string" and #(id :: string) > 0 and #(id :: string) <= 64 and not seen[id :: string] then
			seen[id :: string] = true
			table.insert(result, id :: string)
		end
	end
	while #result > Config.RECEIPT_HISTORY_MAX do
		table.remove(result, 1)
	end
	return result
end

function DataSchema.cleanBroken(value: unknown): { [string]: number }
	local result: { [string]: number } = {}
	if typeof(value) ~= "table" then
		return result
	end
	for key, count in value :: { [unknown]: unknown } do
		if typeof(key) == "string" and Targets.get(key :: string) then
			local n = integerIn(count, 0, 1e15, 0)
			if n > 0 then
				result[key :: string] = n
			end
		end
	end
	return result
end

function DataSchema.cleanStats(value: unknown): Types.Stats
	local stats = DataSchema.defaultStats()
	if typeof(value) ~= "table" then
		return stats
	end
	local src = value :: { [string]: unknown }
	local out = stats :: any
	for _, key in DataSchema.STAT_KEYS do
		out[key] = Economy.sanitize(src[key], Config.MONEY_MAX)
	end
	return stats
end

function DataSchema.cleanSettings(value: unknown): Types.Settings
	local settings = DataSchema.defaultSettings()
	if typeof(value) ~= "table" then
		return settings
	end
	local src = value :: { [string]: unknown }
	for key in Config.SETTINGS do
		if typeof(src[key]) == "boolean" then
			settings[key] = src[key] :: boolean
		end
	end
	return settings
end

-- 불러온 데이터 → 쓸 수 있는 데이터 (모르는 칸은 버림)
function DataSchema.reconcile(raw: unknown, now: number): PlayerData
	local data = DataSchema.default(now)
	if typeof(raw) ~= "table" then
		return data
	end
	local src = raw :: { [string]: unknown }
	data.power = Economy.clampPower(src.power)
	data.money = Economy.clampMoney(src.money)
	data.dumbbellLevel = integerIn(src.dumbbellLevel, 1, Dumbbells.COUNT, 1)
	data.belt = integerIn(src.belt, 1, Belts.COUNT, 1)
	data.world = integerIn(src.world, 1, Progression.worldsFromBelt(data.belt), 1)
	data.broken = DataSchema.cleanBroken(src.broken)
	data.powerBoost = Economy.boost(src.powerBoost)
	data.moneyPass = src.moneyPass == true
	data.grandMaster = src.grandMaster == true and Progression.isGrandMaster(data.belt)
	data.receipts = DataSchema.cleanReceipts(src.receipts)
	data.stats = DataSchema.cleanStats(src.stats)
	data.settings = DataSchema.cleanSettings(src.settings)
	data.lastSaveTime = integerIn(src.lastSaveTime, 0, 1e12, 0)
	return data
end

-- 옛 버전 → 지금 버전 (스키마 1 이 처음이라 고칠 것 없음. 더 새 버전은 그대로 — DataService 가 저장을 끔)
function DataSchema.migrate(raw: unknown): unknown
	if typeof(raw) ~= "table" then
		return raw
	end
	local src = raw :: { [string]: unknown }
	local version = DataSchema.versionOf(src)
	if version > Config.SCHEMA_VERSION then
		return src
	end
	src.version = Config.SCHEMA_VERSION
	return src
end

return DataSchema
