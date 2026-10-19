--!strict
--[[
	SpeedMath — 속도 숫자 → 실제 WalkSpeed, 경비 추격 속도 (순수 로직, Lune 테스트 대상)

	1) 플레이어 속도(숫자, 수십억 이상 커짐)는 로그 곡선으로 WalkSpeed 16~150 에 대응 (2판 수정: 원작 영상 기준):
	     walkSpeed = clamp(16 × (1 + log10(max(speed, 10) / 10)), 16, 150)     (SPEED_LOG_BASE / _FLOOR / SPEED_WALK_MAX)
	   예) 10 이하 → 16, 20 → 20.8, 200 → 36.8, 10K → 64, 64K → 76.9, 1M → 96, 5.8M → 108.2, 1B → 144, 2.37B~ → 150
	   (속도 숫자 자체·러닝머신·도감 보상은 그대로, 숫자 → 걷기 변환만 바뀜)

	2) 실효 속도 = 모은 속도 × 트레일 배율 × (1 - 알 무게 감소)
	   알을 들면 WalkSpeed 도 (1 - 감소) 만큼 줄어 "무겁다"는 느낌이 남.

	3) 경비 속도 = 추천 속도 × GUARD_SPEED_RATIO × (1 - 보통 알 무게 감소 0.10)   (guardSpeedFor, Biomes.guardSpeed)
	   → 표지판 추천 속도면 보통 알(-10%)을 들어도 안전, 큰 알일수록 더 필요 (requiredSpeed):
	      보통 ×0.99 / 큼 ×1.11 / 거대 ×1.37 / 초거대 ×1.78 (GUARD_CHASE_MARGIN 0.99 기준)

	4) 경비 추격 속도 (설계 2판 B — 추격 포기 없음, 허브까지):
	     raw   = (경비 속도 / 알 든 실효 속도) ^ EXPONENT × MARGIN(0.99)     ≈ 추천 속도 / 내 실효 속도
	     ratio = raw ≥ 1 이면 max(raw, SLOW_MIN_RATIO 1.2)  (모자라면 확실히 따라잡음)
	     ratio = clamp(ratio, MIN_RATIO 0.85, MAX_RATIO 3.0)
	     추격 WalkSpeed = 플레이어 WalkSpeed × ratio                           (guardChaseSpeed)
	   → ratio < 1 (추천 이상) 이면 0.85 ~ 0.99배라 절대 못 잡음, 모자랄수록 빨라짐 (최대 3배)
	   비율은 속도 "숫자"로 정하고 플레이어 WalkSpeed 에 곱하므로 곡선을 바꿔도 이 성질은 그대로
	   (플레이어 WalkSpeed 상한 150 × 1.2 = 180 < 경비 상한 GUARD_MAX_WALKSPEED 250 → 모자라면 항상 더 빠름).
	   경비가 집으로 돌아갈 때(평소) 속도는 같은 로그 곡선으로 변환한 toWalkSpeed(경비 속도).
]]

local Config = require(script.Parent.Data.Config)
local Sizes = require(script.Parent.Data.Sizes)

local NORMAL_PENALTY = (Sizes.get(Sizes.DEFAULT) :: Sizes.Size).speedPenalty

local SpeedMath = {}

function SpeedMath.toWalkSpeed(speed: number): number
	local floor = Config.SPEED_LOG_FLOOR
	local s = if speed == speed then math.max(floor, speed) else floor -- NaN 방지
	local ws = Config.SPEED_LOG_BASE * (1 + math.log10(s / floor))
	return math.clamp(ws, Config.SPEED_LOG_BASE, Config.SPEED_WALK_MAX)
end

-- 모은 속도 × 트레일 배율
function SpeedMath.effectiveSpeed(baseSpeed: number, trailMultiplier: number): number
	return math.max(0, baseSpeed) * math.max(1, trailMultiplier)
end

-- 알을 들었을 때 실효 속도 (경비 비교용)
function SpeedMath.carrySpeed(effectiveSpeed: number, penalty: number): number
	return effectiveSpeed * (1 - math.clamp(penalty, 0, 0.95))
end

-- 알을 들었을 때 WalkSpeed
function SpeedMath.carryWalkSpeed(effectiveSpeed: number, penalty: number): number
	local ws = SpeedMath.toWalkSpeed(effectiveSpeed) * (1 - math.clamp(penalty, 0, 0.95))
	return math.max(Config.CARRY_WALKSPEED_MIN, ws)
end

-- 지금 WalkSpeed (알 안 들었으면 penalty = 0)
function SpeedMath.walkSpeedFor(effectiveSpeed: number, penalty: number): number
	if penalty > 0 then
		return SpeedMath.carryWalkSpeed(effectiveSpeed, penalty)
	end
	return SpeedMath.toWalkSpeed(effectiveSpeed)
end

-- 경비 추격 배율 (플레이어 WalkSpeed 에 곱함). 1 미만 = 못 따라잡음
function SpeedMath.guardChaseRatio(guardSpeed: number, carrierSpeed: number): number
	local carrier = math.max(carrierSpeed, 1e-6)
	local raw = (math.max(guardSpeed, 0) / carrier) ^ Config.GUARD_CHASE_EXPONENT * Config.GUARD_CHASE_MARGIN
	if raw ~= raw then -- NaN 방지 (속도 0 / 0)
		raw = Config.GUARD_CHASE_MAX_RATIO
	end
	if raw >= 1 then
		raw = math.max(raw, Config.GUARD_CHASE_SLOW_MIN_RATIO)
	end
	return math.clamp(raw, Config.GUARD_CHASE_MIN_RATIO, Config.GUARD_CHASE_MAX_RATIO)
end

-- 경비 추격 WalkSpeed = 플레이어 WalkSpeed × guardChaseRatio (상한 GUARD_MAX_WALKSPEED)
function SpeedMath.guardChaseSpeed(guardSpeed: number, carrierSpeed: number, carrierWalkSpeed: number): number
	local ws = carrierWalkSpeed * SpeedMath.guardChaseRatio(guardSpeed, carrierSpeed)
	return math.clamp(ws, 1, Config.GUARD_MAX_WALKSPEED)
end

-- (1판 이름, 같은 함수)
SpeedMath.guardChaseWalkSpeed = SpeedMath.guardChaseSpeed

-- 평소(집으로 돌아갈 때) 경비 WalkSpeed = 같은 로그 곡선
function SpeedMath.guardBaseWalkSpeed(guardSpeed: number): number
	return SpeedMath.toWalkSpeed(guardSpeed)
end

-- 이 속도로 이 경비한테서 도망칠 수 있나 (경비가 더 느린가)
function SpeedMath.canEscape(guardSpeed: number, carrierSpeed: number): boolean
	return SpeedMath.guardChaseRatio(guardSpeed, carrierSpeed) < 1
end

-- 구역 추천 속도 → 경비 속도 (보통 알 무게 감소를 기준에 포함: 추천 속도면 보통 알은 안전)
function SpeedMath.guardSpeedFor(recommendedSpeed: number): number
	return math.max(0, recommendedSpeed) * Config.GUARD_SPEED_RATIO * (1 - NORMAL_PENALTY)
end

-- 이 크기(penalty) 알을 들고 경비를 따돌리려면 넘어야 하는 실효 속도 (UI 힌트용, 이 값보다 커야 안전)
function SpeedMath.requiredSpeed(recommendedSpeed: number, penalty: number): number
	return SpeedMath.guardSpeedFor(recommendedSpeed) * Config.GUARD_CHASE_MARGIN / (1 - math.clamp(penalty, 0, 0.95))
end

return SpeedMath
