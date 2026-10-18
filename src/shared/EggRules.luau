--!strict
--[[
	EggRules — 구역 판정과 "잡혔을 때 알을 어떻게 하나" 규칙 (순수 로직, Lune 테스트 대상)

	설계문서 1-2:
	  - 알의 원래 구역 안에서 경비한테 잡히면 → 알은 둥지로 돌아감 ("ReturnToNest")
	  - 알의 구역을 이미 벗어난 뒤 잡히면   → 떨어진 자리에 그대로, 누구나 주울 수 있음 ("DropHere")
	  - 다른 플레이어(방망이/곰덫)한테 당하면 → 항상 떨어진 자리에 ("DropHere") [수석 결정: 뺏을 수 있어야 하므로]

	좌표는 Vector3 대신 x, z 숫자로 받습니다 (Lune 에서도 돌아가게).
	구역은 축 정렬 직사각형 (centerX, centerZ, halfX, halfZ).
]]

export type Zone = {
	centerX: number,
	centerZ: number,
	halfX: number,
	halfZ: number,
}

export type CatchCause = "guard" | "player" | "death" | "leave"
export type EggOutcome = "ReturnToNest" | "DropHere"

local EggRules = {}

function EggRules.isInsideZone(zone: Zone, x: number, z: number): boolean
	return math.abs(x - zone.centerX) <= zone.halfX and math.abs(z - zone.centerZ) <= zone.halfZ
end

function EggRules.distanceFromCenter(zone: Zone, x: number, z: number): number
	local dx, dz = x - zone.centerX, z - zone.centerZ
	return math.sqrt(dx * dx + dz * dz)
end

-- 경비 추격 포기 반경 = 구역 반경(긴 쪽 half) × leashFactor × persistence
function EggRules.leashRadius(zone: Zone, leashFactor: number, persistence: number?): number
	return math.max(zone.halfX, zone.halfZ) * leashFactor * (persistence or 1)
end

function EggRules.withinLeash(zone: Zone, x: number, z: number, leashFactor: number, persistence: number?): boolean
	return EggRules.distanceFromCenter(zone, x, z) <= EggRules.leashRadius(zone, leashFactor, persistence)
end

function EggRules.isWithinRadius(centerX: number, centerZ: number, radius: number, x: number, z: number): boolean
	local dx, dz = x - centerX, z - centerZ
	return dx * dx + dz * dz <= radius * radius
end

-- 알을 놓쳤을 때 결과. eggZone = 알의 "원래 구역"(eggs biome) 의 Zone.
function EggRules.dropOutcome(cause: CatchCause, eggZone: Zone?, x: number, z: number): EggOutcome
	if cause == "player" then
		return "DropHere"
	end
	if eggZone and EggRules.isInsideZone(eggZone, x, z) then
		return "ReturnToNest"
	end
	return "DropHere"
end

return EggRules
