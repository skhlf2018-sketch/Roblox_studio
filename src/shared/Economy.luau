--!strict
--[[
	Economy — 열매 값·성장 시간·정원 칸·러닝머신·트레일 계산 (6판 "씨앗을 훔치세요", 순수 로직, Lune 테스트 대상)

	6판: 자동 수입 없음 (코인 = 열매를 따서 판매 가판대에 팔기). 데이터 표(Data/Plants)의 숫자를 그대로 씀
	  (5판 GROWTH_MULTIPLIER ×3 는 없앰 — 러닝머신 배율 Config.TREADMILL_MULTIPLIER 만 남음).
	  열매 1개 값 = 식물 열매 값(Plants.fruitValue) × 크기 배율(Sizes.incomeMultiplier) × 돌연변이 배율(곱)
	  recordIncome = 열매로 환산한 초당 코인 (표시용 — 정원 이름표·도감 등)
	  성장 시간 = Plants.growSeconds ÷ Config.GROWTH_SPEED_MULTIPLIER (7판 성장 3배, growSeconds 한 곳. 밤 30배는 growthRate)
	  정원 칸 수 = Upgrades.Pen 칸 수 (penSlots — 5판 우리 장착 칸 숫자 그대로)
]]

local Data = script.Parent.Data
local Config = require(Data.Config)
local Plants = require(Data.Plants)
local Sizes = require(Data.Sizes)
local Mutations = require(Data.Mutations)
local Upgrades = require(Data.Upgrades)
local Types = require(script.Parent.Types)

type PetRecord = Types.PetRecord

local Economy = {}

------------------------------------------------------------------
-- 열매 값
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

-- 같은 group 돌연변이가 2개 이상이면 false (예: 실버+황금 동시 불가)
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

-- 열매 1개 값(코인) = 식물 열매 값 × 크기 × 돌연변이. 모르는 식물이면 0
function Economy.fruitValue(petId: string, sizeId: string, mutations: { string }): number
	local plant = Plants.get(petId)
	if not plant then
		return 0
	end
	return plant.fruitValue
		* Economy.earlyCoinMultiplier(plant.rarity)
		* Economy.sizeMultiplier(sizeId)
		* Economy.mutationMultiplier(mutations)
end

-- 초반 코인 2배 (사장님 2026-10-28): 초반 구역 등급(일반·고급)의 열매 값 × Config.EARLY_COIN_MULTIPLIER[등급] (없으면 1)
function Economy.earlyCoinMultiplier(rarityId: string): number
	return Config.EARLY_COIN_MULTIPLIER[rarityId] or 1
end

function Economy.recordFruitValue(record: { petId: string, size: string, mutations: { string } }): number
	return Economy.fruitValue(record.petId, record.size, record.mutations)
end

-- 열매 맺는 간격(초) = 표(Data/Plants) 간격 ÷ FRUIT_SPEED_MULTIPLIER(1.8, 사장님 지시). 모르는 식물이면 math.huge (열매 안 맺음)
function Economy.fruitInterval(petId: string): number
	local plant = Plants.get(petId)
	return if plant then math.max(1, plant.fruitIntervalSeconds / Config.FRUIT_SPEED_MULTIPLIER) else math.huge
end

-- 열매로 환산한 초당 코인 (표시용, 6판은 자동으로 들어오지 않음)
function Economy.recordIncome(record: { petId: string, size: string, mutations: { string } }): number
	local interval = Economy.fruitInterval(record.petId)
	if interval == math.huge then
		return 0
	end
	return Economy.recordFruitValue(record) / interval
end

------------------------------------------------------------------
-- 성장 (씨앗 → 성체)
------------------------------------------------------------------

-- 성장 속도 배율 (7판 사장님 지시 "성장 속도 3배" = Config.GROWTH_SPEED_MULTIPLIER). 0 이하·이상한 값이면 1
function Economy.growthSpeedMultiplier(): number
	local m = Config.GROWTH_SPEED_MULTIPLIER
	return if typeof(m) == "number" and m == m and m > 0 and m < math.huge then m else 1
end

-- 식물 표에 적힌 성체까지 시간(초, 3배 적용 전 — 문서 10장 "성체까지" 칸). 모르는 식물이면 nil
function Economy.tableGrowSeconds(petId: string): number?
	local plant = Plants.get(petId)
	return if plant then plant.growSeconds else nil
end

-- 성체까지 **실제** 시간(초, 낮 기준) = 표 시간(Data/Plants.growSeconds) ÷ 성장 속도 3배 (7판).
--   씨앗 Required · 타이머 · 건너뛰기 가격(남은 시간)이 전부 이 값을 씀 — 3배를 나누는 곳은 여기 한 곳뿐.
--   강아지풀 표 3초 → 1초 · 일반 약 3.3초 · … · 해커 글리치 표 48~60일 → 16~20일. 밤 30배는 growthRate
function Economy.growSeconds(petId: string): number
	local plant = Plants.get(petId)
	if not plant then
		return 1
	end
	return plant.growSeconds / Economy.growthSpeedMultiplier()
end

-- [5판 호환 이름] = growSeconds
function Economy.hatchSeconds(petId: string): number
	return Economy.growSeconds(petId)
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

-- 씨앗 성장 진행: (새 진행도, 다 자랐나 = 성체)
function Economy.advanceIncubation(progress: number, required: number, dt: number, rate: number): (number, boolean)
	local nextProgress = math.min(required, progress + math.max(0, dt) * rate)
	return nextProgress, nextProgress >= required
end

-- 씨앗 위 타이머에 보여 줄 숫자 = 남은 "성장 시간"(초). 밤에는 이 숫자가 1초에 30씩 줄고, 낮이면 1씩 줆
-- (4판: 밤이 되자마자 표시가 ÷30 으로 확 줄었다가 낮에 다시 늘어나던 것을 고침 — 숫자는 그대로, 줄어드는 빠르기만 바뀜)
function Economy.timerSeconds(progress: number, required: number): number
	return math.max(0, required - progress)
end

-- 지금 속도가 계속될 때 실제로 남는 시간(초) — 계산·테스트용 (표시에는 timerSeconds 를 씀)
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

-- 다음 정원 레벨 비용 (최대면 nil)
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

-- 러닝머신 위 1초당 속도 증가 = 걸음당 속도 × 러닝머신 배율(6판 4) × 초당 걸음 × 부스터 (20레벨 = 1,000,000/초)
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
-- 오프라인 (6판: 오프라인 수입 없음 — 씨앗이 자라고 성체가 열매를 맺을 뿐)
------------------------------------------------------------------

-- 오프라인 동안 정원에 심은 씨앗이 자란 시간·성체가 열매를 맺은 시간 (밤 가속 없음, 상한 24시간). 시계가 거꾸로면 0
function Economy.offlineGrowthSeconds(lastSaveTime: number, now: number): number
	if lastSaveTime <= 0 then
		return 0
	end
	return math.clamp(now - lastSaveTime, 0, Config.OFFLINE_GROWTH_CAP_SECONDS)
end

return Economy
