--!strict
--[[
	MoveCheck — 서버 위치 검증 계산 (순수 로직, Lune 테스트 대상). 실제 적용은 Services/AntiCheatService, BaseService.

	좌표는 Vector3 대신 x, z 숫자 (수평 거리만 봄 → 떨어지기·점프는 오탐 안 함)

	1) 1초 검사: 이동 거리 > (WalkSpeed × MOVE_CHECK_SPEED_FACTOR) × 경과초 + MOVE_CHECK_SLACK 이면 위반
	   → 설계: "1초에 (현재 WalkSpeed × 1.5 + 30) 스터드 이상 이동했으면" (경과초 = 1 일 때 똑같음)
	2) 알 든 사람 0.2초 검사: 거리 > WalkSpeed × 경과초 × CARRY_JUMP_SPEED_FACTOR + CARRY_JUMP_SLACK 이면 위반
	3) 배달 최소 시간: 주운 곳 → 패드 거리 ÷ (WalkSpeed × DELIVERY_TIME_SPEED_FACTOR)
	4) 경고: MOVE_CHECK_WARNING_DECAY_SECONDS 마다 1개씩 줄어듦, MOVE_CHECK_KICK_WARNINGS 개면 Kick
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Data.Config)

export type Warnings = {
	count: number,
	lastDecayAt: number,
}

local MoveCheck = {}

function MoveCheck.horizontalDistance(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	return math.sqrt(dx * dx + dz * dz)
end

-- 1초 검사 허용 거리
function MoveCheck.allowedDistance(walkSpeed: number, dt: number): number
	return math.max(0, walkSpeed) * Config.MOVE_CHECK_SPEED_FACTOR * math.max(0, dt) + Config.MOVE_CHECK_SLACK
end

function MoveCheck.isViolation(distance: number, walkSpeed: number, dt: number): boolean
	return distance > MoveCheck.allowedDistance(walkSpeed, dt)
end

-- 알 든 사람 한 틱 허용 거리
function MoveCheck.carryAllowedDistance(walkSpeed: number, dt: number): number
	return math.max(0, walkSpeed) * math.max(0, dt) * Config.CARRY_JUMP_SPEED_FACTOR + Config.CARRY_JUMP_SLACK
end

function MoveCheck.isCarryJump(distance: number, walkSpeed: number, dt: number): boolean
	return distance > MoveCheck.carryAllowedDistance(walkSpeed, dt)
end

-- 이 거리를 가는 데 걸려야 하는 최소 시간 (초)
function MoveCheck.minTravelSeconds(distance: number, walkSpeed: number): number
	local speed = math.max(walkSpeed, 1) * Config.DELIVERY_TIME_SPEED_FACTOR
	return math.max(0, distance) / speed
end

function MoveCheck.isTooFastDelivery(distance: number, elapsed: number, walkSpeed: number): boolean
	return elapsed < MoveCheck.minTravelSeconds(distance, walkSpeed)
end

function MoveCheck.newWarnings(now: number): Warnings
	return { count = 0, lastDecayAt = now }
end

-- 시간이 지난 만큼 경고를 줄임
function MoveCheck.decay(w: Warnings, now: number)
	local period = Config.MOVE_CHECK_WARNING_DECAY_SECONDS
	if period <= 0 then
		return
	end
	if w.count <= 0 then
		w.lastDecayAt = now
		return
	end
	local steps = math.floor((now - w.lastDecayAt) / period)
	if steps > 0 then
		w.count = math.max(0, w.count - steps)
		w.lastDecayAt += steps * period
	end
end

-- 경고 1개 추가. (지금 경고 수, Kick 해야 하나)
function MoveCheck.addWarning(w: Warnings, now: number): (number, boolean)
	MoveCheck.decay(w, now)
	if w.count == 0 then
		w.lastDecayAt = now
	end
	w.count += 1
	return w.count, w.count >= Config.MOVE_CHECK_KICK_WARNINGS
end

return MoveCheck
