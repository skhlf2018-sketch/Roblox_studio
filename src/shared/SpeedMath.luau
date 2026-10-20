--!strict
--[[
	SpeedMath — 속도 숫자 → 실제 WalkSpeed, 경비 추격 속도 (순수 로직, Lune 테스트 대상)

	1) 플레이어 속도(숫자, 수십억 이상 커짐)는 로그 곡선으로 WalkSpeed 20~230 에 대응 (4판: 체감 속도 ↑):
	     walkSpeed = clamp(BASE × (1 + SLOPE × log10(max(speed, 10) / 10)), BASE, MAX)
	       (SPEED_LOG_BASE 20 / SPEED_LOG_SLOPE 0.95 / SPEED_LOG_FLOOR 10 / SPEED_WALK_MAX 230)
	   예) 10 이하 → 20, 20 → 25.7, 200 → 44.7, 10K → 77, 1M → 115, 5.8M → 129.5, 1B → 172, 500B → 222, 1.1T~ → 230

	2) 실효 속도 = 모은 속도 × 트레일 배율 × (1 - 알 무게 감소)   (carrySpeed)
	   알을 들면 WalkSpeed = toWalkSpeed(실효 속도 × (1 - 감소)) — 무게 감소를 "속도 숫자"에 적용한 뒤 곡선을 탐
	   (4판: 경비 속도와 같은 잣대로 비교되게. 숫자가 크면 걷기도 빠르다는 순서가 항상 지켜짐)

	3) 경비 속도(숫자) = 추천 속도 × GUARD_SPEED_RATIO × (1 - 보통 알 무게 감소 0.10)   (guardSpeedFor, Biomes.guardSpeed)
	   → 표지판 추천 속도면 보통 알(-10%)을 들어도 안전, 큰 알일수록 더 필요 (requiredSpeed):
	      보통 ×0.99 / 큼 ×1.11 / 거대 ×1.37 / 초거대 ×1.78 (GUARD_CHASE_MARGIN 0.99 기준)

	4) 경비 추격 속도 (4판, 사장님: "플레이어 속도에 맞춰 달라지면 안 되고 무조건 같은 속도"):
	     추격 WalkSpeed = toWalkSpeed(경비 속도 × MARGIN 0.99)   — 구역마다 고정, 누구를 쫓든 같음   (guardChaseSpeed)
	   → 내 실효 속도(알 무게 반영)가 경비 속도 × 0.99 보다 크면 내가 더 빠름 = 못 잡음 (canEscape),
	     작으면 경비가 더 빠름 = 언젠가 잡힘 (추격 포기 없음, 허브까지).
	   경비가 집으로 돌아갈 때(평소) 속도는 toWalkSpeed(경비 속도) (guardBaseWalkSpeed).
	   guardChaseRatio 는 옛 2판(플레이어 속도 비례) 식 — 지금 게임은 안 쓰고 "얼마나 모자란가" 참고용으로만 남김.
]]

local Config = require(script.Parent.Data.Config)
local Sizes = require(script.Parent.Data.Sizes)

local NORMAL_PENALTY = (Sizes.get(Sizes.DEFAULT) :: Sizes.Size).speedPenalty

local SpeedMath = {}

function SpeedMath.toWalkSpeed(speed: number): number
	local floor = Config.SPEED_LOG_FLOOR
	local s = if speed == speed then math.max(floor, speed) else floor -- NaN 방지
	local ws = Config.SPEED_LOG_BASE * (1 + Config.SPEED_LOG_SLOPE * math.log10(s / floor))
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

-- 알을 들었을 때 WalkSpeed = 무게를 뺀 속도 숫자를 곡선에 넣음 (하한 CARRY_WALKSPEED_MIN)
function SpeedMath.carryWalkSpeed(effectiveSpeed: number, penalty: number): number
	local ws = SpeedMath.toWalkSpeed(SpeedMath.carrySpeed(effectiveSpeed, penalty))
	return math.max(Config.CARRY_WALKSPEED_MIN, ws)
end

-- 지금 WalkSpeed (알 안 들었으면 penalty = 0)
function SpeedMath.walkSpeedFor(effectiveSpeed: number, penalty: number): number
	if penalty > 0 then
		return SpeedMath.carryWalkSpeed(effectiveSpeed, penalty)
	end
	return SpeedMath.toWalkSpeed(effectiveSpeed)
end

-- (옛 2판 참고용) 경비 속도 / 알 든 실효 속도 비율. 1 미만 = 플레이어가 더 빠름. 게임 로직은 더 이상 안 씀
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

-- 경비 추격 WalkSpeed — 구역마다 고정 (플레이어가 누구든, 얼마나 빠르든 같음). 상한 GUARD_MAX_WALKSPEED
function SpeedMath.guardChaseSpeed(guardSpeed: number): number
	local ws = SpeedMath.toWalkSpeed(math.max(0, guardSpeed) * Config.GUARD_CHASE_MARGIN)
	return math.clamp(ws, 1, Config.GUARD_MAX_WALKSPEED)
end

-- 평소(집으로 돌아갈 때) 경비 WalkSpeed = 같은 로그 곡선
function SpeedMath.guardBaseWalkSpeed(guardSpeed: number): number
	return SpeedMath.toWalkSpeed(guardSpeed)
end

-- 이 실효 속도(알 무게 반영)로 이 경비한테서 도망칠 수 있나 = 내가 경비 추격 속도보다 빠른가
function SpeedMath.canEscape(guardSpeed: number, carrierSpeed: number): boolean
	if carrierSpeed ~= carrierSpeed then -- NaN
		return false
	end
	return carrierSpeed > math.max(0, guardSpeed) * Config.GUARD_CHASE_MARGIN
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
