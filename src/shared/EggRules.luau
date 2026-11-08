--!strict
--[[
	EggRules — "잡혔을 때 알을 어떻게 하나" 규칙 + 구역 사각형 도우미 (순수 로직, Lune 테스트 대상)

	설계문서 1-2 (2판도 같음):
	  - 알의 원래 구역 안에서 경비한테 잡히면 → 알은 둥지로 돌아감 ("ReturnToNest")
	  - 알의 구역을 이미 벗어난 뒤 잡히면   → 떨어진 자리에 그대로, 누구나 주울 수 있음 ("DropHere")
	  - 다른 플레이어(방망이/곰덫)한테 당하면 → 항상 떨어진 자리에 ("DropHere") [수석 결정: 뺏을 수 있어야 하므로]
	  - 2판: 스스로 버리면(DropEgg, cause "drop") → 항상 그 자리에 ("DropHere")

	2판: "구역 안" 은 MapLayout.zoneAt(z) 로 판정 (일자 복도라 z 범위만 봄).
	     dropOutcome(cause, 알의 구역 id, 지금 있는 곳의 구역 id)
	Zone 사각형 함수(isInsideZone 등)는 1판 MapBuilder 가 쓰던 것 — 서버 로직은 이제 안 씀.

	8판 (사장님 2026-11-08) 바닥에 떨어진("DropHere") 씨앗이 그 뒤에 어떻게 되나 — groundFate(알의 구역, 떨어진 곳의 구역):
	  - 그 씨앗을 얻은 구역 **안** → "Stay"   : 둥지로 안 가고 그 자리에 그대로 (누구나 줍기, 다음 초기화까지 — 카운트다운 없음)
	  - 그 구역 **밖**(다른 구역·허브·맵 밖) → "Return" : Config.DROPPED_EGG_RETURN_SECONDS(5초) 뒤 둥지로 돌아감
	  (7판까지: 어디든 60초 뒤 사라지고 그 둥지는 30초 뒤 새 씨앗)
]]

export type Zone = {
	centerX: number,
	centerZ: number,
	halfX: number,
	halfZ: number,
}

export type CatchCause = "guard" | "player" | "death" | "leave" | "drop"
export type EggOutcome = "ReturnToNest" | "DropHere"
export type GroundFate = "Stay" | "Return"

local EggRules = {}

function EggRules.isInsideZone(zone: Zone, x: number, z: number): boolean
	return math.abs(x - zone.centerX) <= zone.halfX and math.abs(z - zone.centerZ) <= zone.halfZ
end

function EggRules.distanceFromCenter(zone: Zone, x: number, z: number): number
	local dx, dz = x - zone.centerX, z - zone.centerZ
	return math.sqrt(dx * dx + dz * dz)
end

function EggRules.isWithinRadius(centerX: number, centerZ: number, radius: number, x: number, z: number): boolean
	local dx, dz = x - centerX, z - centerZ
	return dx * dx + dz * dz <= radius * radius
end

-- 알을 놓쳤을 때 결과. eggBiomeId = 알의 "원래 구역", zoneHere = 놓친 자리의 구역 (MapLayout.zoneAt, nil/"hub" 가능)
function EggRules.dropOutcome(cause: CatchCause, eggBiomeId: string?, zoneHere: string?): EggOutcome
	if cause == "player" or cause == "drop" then
		return "DropHere"
	end
	if eggBiomeId ~= nil and zoneHere ~= nil and zoneHere == eggBiomeId then
		return "ReturnToNest"
	end
	return "DropHere"
end

-- 8판: 바닥에 떨어진 씨앗의 운명. 그 씨앗 구역 안이면 그대로("Stay"), 밖이면 잠시 뒤 둥지로("Return")
function EggRules.groundFate(eggBiomeId: string?, zoneHere: string?): GroundFate
	if eggBiomeId ~= nil and zoneHere ~= nil and zoneHere == eggBiomeId then
		return "Stay"
	end
	return "Return"
end

return EggRules
