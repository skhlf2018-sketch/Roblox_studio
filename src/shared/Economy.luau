--!strict
--[[
	Economy — 수입·부화 시간·러닝머신·트레일·오프라인 수입 계산 (순수 로직, Lune 테스트 대상)

	데이터 표(Pets, Upgrades)는 원본 숫자를 그대로 두고,
	GROWTH_MULTIPLIER 는 오직 이 모듈에서만 적용합니다 (펫 수입 ×G, 러닝머신 ×G).
	2판 수정: 부화 시간에는 안 씀 (원작 부화 시간 그대로, 밤 30배만).
]]

local Data = script.Parent.Data
local Config = require(Data.Config)
local Pets = require(Data.Pets)
local Sizes = require(Data.Sizes)
local Mutations = require(Data.Mutations)
local Upgrades = require(Data.Upgrades)
local Types = require(script.Parent.Types)

type PetRecord = Types.PetRecord

local Economy = {}

function Economy.growthMultiplier(): number
	return Config.GROWTH_MULTIPLIER
end

------------------------------------------------------------------
-- 수입
------------------------------------------------------------------

function Economy.sizeMultiplier(sizeId: string): number
	local size = Sizes.get(sizeId)
	return if size then size.incomeMultiplier else 1
end

-- 돌연변이 배율: 전부 곱함 (중첩). 모르는 id 는 무시.
function Economy.mutationMultiplier(mutations: { string }): number
	local total = 1
	for _, id in mutations do
		local mutation = Mutations.get(id)
		if mutation then
			total *= mutation.multiplier
		end
	end
	return total
end

-- 같은 group 돌연변이가 2개 이상이면 false (예: 실버+골든 동시 불가)
function Economy.isValidMutationSet(mutations: { string }): boolean
	local seen: { [string]: boolean } = {}
	for _, id in mutations do
		local mutation = Mutations.get(id)
		if not mutation then
			return false
		end
		if seen[mutation.group] then
			return false
		end
		seen[mutation.group] = true
	end
	return true
end

-- 펫 1마리 초당 수입 = 기본(원본) × G × 크기 × 돌연변이
function Economy.petIncome(petId: string, sizeId: string, mutations: { string }): number
	local pet = Pets.get(petId)
	if not pet then
		return 0
	end
	return pet.income
		* Config.GROWTH_MULTIPLIER
		* Economy.sizeMultiplier(sizeId)
		* Economy.mutationMultiplier(mutations)
end

function Economy.recordIncome(record: PetRecord): number
	return Economy.petIncome(record.petId, record.size, record.mutations)
end

-- 장착된 펫들의 초당 수입 합 (moneyMultiplier: 게임패스·부스터, 기본 1)
function Economy.totalIncome(records: { PetRecord }, equippedUids: { string }, moneyMultiplier: number?): number
	local byUid: { [string]: PetRecord } = {}
	for _, record in records do
		byUid[record.uid] = record
	end
	local total = 0
	local counted: { [string]: boolean } = {}
	for _, uid in equippedUids do
		local record = byUid[uid]
		if record and not counted[uid] then
			counted[uid] = true
			total += Economy.recordIncome(record)
		end
	end
	return total * (moneyMultiplier or 1)
end

-- Equip Best: 수입이 높은 순서로 slots 마리의 uid (수입은 정렬 전에 한 번만 계산)
type Entry = { uid: string, income: number }

function Economy.bestEquipSet(records: { PetRecord }, slots: number): { string }
	local entries: { Entry } = table.create(#records)
	for i, record in records do
		entries[i] = { uid = record.uid, income = Economy.recordIncome(record) }
	end
	table.sort(entries, function(a: Entry, b: Entry): boolean
		if a.income == b.income then
			return a.uid < b.uid
		end
		return a.income > b.income
	end)
	local result: { string } = {}
	for i = 1, math.min(slots, #entries) do
		table.insert(result, entries[i].uid)
	end
	return result
end

-- 보관함이 넘칠 때 팔 펫: 장착 안 된 펫 중 수입이 가장 낮은 펫의 uid (없으면 nil)
function Economy.cheapestUnequipped(records: { PetRecord }, equippedUids: { string }): string?
	local equipped: { [string]: boolean } = {}
	for _, uid in equippedUids do
		equipped[uid] = true
	end
	local bestUid: string? = nil
	local bestIncome = math.huge
	for _, record in records do
		if not equipped[record.uid] then
			local income = Economy.recordIncome(record)
			if income < bestIncome or (income == bestIncome and bestUid ~= nil and record.uid < bestUid) then
				bestUid, bestIncome = record.uid, income
			end
		end
	end
	return bestUid
end

------------------------------------------------------------------
-- 부화
------------------------------------------------------------------

-- 실제 부화 시간(초) = 원본 그대로 (2판 수정, 사장님 "모든 알이 3초로 끝나면 안 됨": ÷ GROWTH_MULTIPLIER 없앰,
-- 하한 없음). 닭 10초 · 전설 5분 · 비밀 1.5시간 · 신성 12~24시간. 빨라지는 건 밤 30배(growthRate)뿐
function Economy.hatchSeconds(petId: string): number
	local pet = Pets.get(petId)
	if not pet then
		return 1
	end
	return pet.hatchSeconds
end

-- 1초에 몇 초만큼 자라나: 밤 30배, 성장 2배 게임패스
function Economy.growthRate(isNight: boolean, hasGrowthPass: boolean): number
	local rate = 1
	if isNight then
		rate *= Config.NIGHT_GROWTH_MULTIPLIER
	end
	if hasGrowthPass then
		rate *= Config.GAMEPASS_GROWTH_MULTIPLIER
	end
	return rate
end

-- 알 성장 진행: (새 진행도, 다 자랐나)
function Economy.advanceIncubation(progress: number, required: number, dt: number, rate: number): (number, boolean)
	local nextProgress = math.min(required, progress + math.max(0, dt) * rate)
	return nextProgress, nextProgress >= required
end

-- 남은 실제 시간(초) — UI 표시용
function Economy.remainingSeconds(progress: number, required: number, rate: number): number
	if rate <= 0 then
		return math.huge
	end
	return math.max(0, required - progress) / rate
end

------------------------------------------------------------------
-- 업그레이드
------------------------------------------------------------------

function Economy.penSlots(level: number): number
	local entry = Upgrades.Pen[math.clamp(level, 1, Upgrades.PEN_MAX_LEVEL)]
	return entry.slots
end

-- 다음 우리 레벨 비용 (최대면 nil)
function Economy.nextPenCost(level: number): number?
	local entry = Upgrades.Pen[level + 1]
	return if entry then entry.cost else nil
end

function Economy.treadmillPerStep(level: number): number
	if level < 1 then
		return 0
	end
	local entry = Upgrades.Treadmill[math.min(level, Upgrades.TREADMILL_MAX_LEVEL)]
	return entry.perStep
end

-- 러닝머신 위 1초당 속도 증가 = 걸음당 속도 × 러닝머신 배율(기본 G = 3) × 초당 걸음 × 부스터
function Economy.treadmillGainPerSecond(level: number, boost: number?): number
	return Economy.treadmillPerStep(level)
		* Config.TREADMILL_MULTIPLIER
		* Config.TREADMILL_STEPS_PER_SECOND
		* (boost or 1)
end

-- 다음 러닝머신 레벨 비용 (0 → 1 은 해금 비용, 최대면 nil)
function Economy.nextTreadmillCost(level: number): number?
	local entry = Upgrades.Treadmill[level + 1]
	return if entry then entry.cost else nil
end

-- 가진 트레일 중 가장 높은 배율 (없으면 1). 중첩 아님.
function Economy.bestTrailMultiplier(ownedTrailIds: { string }): number
	local best = 1
	for _, id in ownedTrailIds do
		local trail = Upgrades.getTrail(id)
		if trail and trail.multiplier > best then
			best = trail.multiplier
		end
	end
	return best
end

-- 가진 트레일 중 배율이 가장 높은 것의 id (없으면 Upgrades.NO_TRAIL). 스키마 2 → 3 마이그레이션용
function Economy.bestTrailId(ownedTrailIds: { string }): string
	local bestId, best = Upgrades.NO_TRAIL, 1
	for _, id in ownedTrailIds do
		local trail = Upgrades.getTrail(id)
		if trail and trail.multiplier > best then
			bestId, best = trail.id, trail.multiplier
		end
	end
	return bestId
end

-- 장착한 트레일의 배율 (2판 마무리: 장착한 것만 적용). "none"·모르는 id 면 1
function Economy.trailMultiplier(equippedTrailId: string?): number
	local trail = if equippedTrailId then Upgrades.getTrail(equippedTrailId) else nil
	return if trail then math.max(1, trail.multiplier) else 1
end

------------------------------------------------------------------
-- 오프라인 수입
------------------------------------------------------------------

-- (지급액, 인정된 오프라인 초). 상한 24시간, 시계가 거꾸로면 0.
function Economy.offlineIncome(incomePerSecond: number, lastSaveTime: number, now: number): (number, number)
	if lastSaveTime <= 0 or incomePerSecond <= 0 then
		return 0, 0
	end
	local seconds = math.clamp(now - lastSaveTime, 0, Config.OFFLINE_INCOME_CAP_SECONDS)
	return math.floor(incomePerSecond * seconds * Config.OFFLINE_INCOME_RATE), seconds
end

-- 오프라인 동안 부화 슬롯 알이 자란 시간 (밤 가속 없음, 상한 24시간)
function Economy.offlineGrowthSeconds(lastSaveTime: number, now: number): number
	if lastSaveTime <= 0 then
		return 0
	end
	return math.clamp(now - lastSaveTime, 0, Config.OFFLINE_INCOME_CAP_SECONDS)
end

return Economy
