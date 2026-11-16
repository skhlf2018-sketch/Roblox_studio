--!strict
--[[
	Sizes — 힘이 셀수록 몸·월드·아령이 커지는 규칙 (사장님 결정 13·14번, 설계서 1장 · 7장). 순수 계산.

	  Sizes.playerScale(power)   → 1 (힘 0) … MAX_SCALE (마지막 물건 "우주" 추천 힘). 힘 배수(로벅스)는 안 넣은 맨 힘.
	  Sizes.muscle(power)        → 0 … 1 (근육: 어깨·팔 굵기에 씀)
	  Sizes.worldScale(world)    → 월드 1 = 1 · 월드 2·3 = "그 월드 힘 평균(추천 힘의 로그 평균)"인 플레이어의 몸 배율
	  Sizes.dumbbellScale(level) → 아령 자체가 커지는 배율 1 … DUMBBELL_MAX (몸 배율과 곱해서 씀)
	  Sizes.walkSpeed(scale)     → BASE_WALK_SPEED × 몸 배율 (사장님: 속도 지금보다 2배 → 16 이 32)
	  Sizes.jumpHeight(scale)    → BASE_JUMP_HEIGHT × 몸 배율
	  Sizes.quantize(scale)      → 서버가 몸을 다시 키울 값 (STEP 단위로 내림 — 들 때마다 다시 키우지 않게)

	마지막 크기 (사장님 결정 13번, 고쳐 말함): "월드 1 아파트의 2배" 는 **마지막 아령** —
	  가장 큰 몸(MAX_SCALE)이 마지막 아령을 들면 그 봉 길이 = 아파트 높이 × 2 (FINAL_DUMBBELL_LENGTH).
	  LAST_DUMBBELL_LENGTH × MAX_SCALE × DUMBBELL_MAX = FINAL_DUMBBELL_LENGTH (sizes.spec 이 검사, 선임 smoke 는 실제로 만든 아령으로).
	몸 최대 MAX_SCALE (= 아파트 2배 ÷ 아바타 키 ≈ 13.97, 키 약 75 스터드) 는 사장님이 정한 기준이 아니라 본부장이 고른 값.
	APARTMENT_HEIGHT 는 맵이 실제로 만든 아파트 높이와 같아야 함 (smoke_visuals 가 검사). 월드 1 은 배율 1 이라 아파트 크기는 안 바뀜.
	이상한 입력 (NaN · ±무한 · 음수 · 숫자 아님) 은 오류 없이 가장 작은 쪽 (배율 1 · 근육 0 · 아령 1단계) 으로.
]]

local Dumbbells = require(script.Parent.Dumbbells)
local Targets = require(script.Parent.Targets)

local Sizes = {}

Sizes.AVATAR_HEIGHT = 5.4 -- 보통 R15 아바타 키 (스터드)
Sizes.APARTMENT_HEIGHT = 37.725 -- 월드 1 아파트 (반지름 13.75 → 건물 33 + 옥상 0.6 + 물탱크 4.125)
Sizes.MAX_SCALE = 2 * Sizes.APARTMENT_HEIGHT / Sizes.AVATAR_HEIGHT -- ≈ 13.97 (본부장 — 몸 최대)
Sizes.CURVE = 1.5 -- 처음엔 천천히, 뒤로 갈수록 쑥쑥
Sizes.STEP = 0.02 -- 몸 배율이 2% 넘게 달라졌을 때만 다시 키움
Sizes.FINAL_DUMBBELL_LENGTH = 2 * Sizes.APARTMENT_HEIGHT -- 75.45 (사장님: 마지막 아령 = 아파트 2배)
-- 마지막 아령을 shared/DumbbellLook.build 가 배율 1 로 만들 때 봉 길이: 손잡이 0.9 + 2 × (원판 4장 × 0.16 + 끝 0.12)
Sizes.LAST_DUMBBELL_LENGTH = 2.42
-- 아령 배율 최대 = 가장 큰 몸이 든 마지막 아령이 FINAL_DUMBBELL_LENGTH 가 되게 (≈ 2.232)
Sizes.DUMBBELL_MAX = Sizes.FINAL_DUMBBELL_LENGTH / (Sizes.LAST_DUMBBELL_LENGTH * Sizes.MAX_SCALE)
Sizes.BASE_WALK_SPEED = 32
Sizes.BASE_JUMP_HEIGHT = 7.2

local lastTarget = Targets.list[#Targets.list]
Sizes.MAX_POWER = lastTarget.recommendPower

local LOG_MAX = math.log10(1 + Sizes.MAX_POWER)

-- 쓸 수 있는 숫자 (숫자 아님 · NaN → nil)
local function number(value: unknown): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return value :: number
end

local function progress(power: number): number
	local p = number(power)
	if not p or p <= 0 then
		return 0
	end
	return math.clamp(math.log10(1 + p) / LOG_MAX, 0, 1) -- +무한 → 1
end

-- 몸 배율 (1 … MAX_SCALE 로 맞춤, 이상한 값 → 1)
local function bodyScale(scale: number): number
	local s = number(scale)
	if not s then
		return 1
	end
	return math.clamp(s, 1, Sizes.MAX_SCALE)
end

function Sizes.playerScale(power: number): number
	return 1 + (Sizes.MAX_SCALE - 1) * progress(power) ^ Sizes.CURVE
end

function Sizes.muscle(power: number): number
	return progress(power)
end

-- STEP 단위로 내림 (1, 1.02, 1.0404 … — 큰 몸에서도 2% 씩). 결과는 입력보다 크지 않음 (1 아래 입력은 1).
-- 맨 위는 MAX_SCALE 그대로 (가장 큰 몸이 정확히 최대 — 마지막 아령 길이가 딱 맞게)
function Sizes.quantize(scale: number): number
	local s = bodyScale(scale)
	if s >= Sizes.MAX_SCALE then
		return Sizes.MAX_SCALE
	end
	local ratio = 1 + Sizes.STEP
	local steps = math.floor(math.log(s) / math.log(ratio) + 1e-9)
	local q = ratio ^ steps
	if q > s then -- 소수점 오차로 한 칸 넘쳤으면 한 칸 내림
		q = ratio ^ (steps - 1)
	end
	return math.max(1, q)
end

local worldScales: { [number]: number } = {}

function Sizes.worldScale(world: number): number
	local w = number(tonumber(world))
	if not w then
		return 1
	end
	w = math.floor(w)
	if w <= 1 or w == math.huge then
		return 1
	end
	local cached = worldScales[w]
	if cached then
		return cached
	end
	local list = Targets.byWorld(w)
	if #list == 0 then
		return 1
	end
	local sum = 0
	for _, target in list do
		sum += math.log10(target.recommendPower)
	end
	local averagePower = 10 ^ (sum / #list)
	-- 0.1 단위로 반올림 (맵 숫자가 깔끔하게)
	local scale = math.floor(Sizes.playerScale(averagePower) * 10 + 0.5) / 10
	worldScales[w] = scale
	return scale
end

function Sizes.dumbbellScale(level: number): number
	local count = #Dumbbells.list
	if count <= 1 then
		return 1
	end
	local n = number(tonumber(level)) or 1
	local lv = math.clamp(math.floor(n), 1, count) -- ±무한도 1 · count 로
	return 1 + (Sizes.DUMBBELL_MAX - 1) * (lv - 1) / (count - 1)
end

function Sizes.walkSpeed(scale: number): number
	return Sizes.BASE_WALK_SPEED * bodyScale(scale)
end

function Sizes.jumpHeight(scale: number): number
	return Sizes.BASE_JUMP_HEIGHT * bodyScale(scale)
end

return Sizes
