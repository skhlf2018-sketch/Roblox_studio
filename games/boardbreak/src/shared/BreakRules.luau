--!strict
--[[
	BreakRules — 물건 치기 판정 (순수 로직, Lune 테스트 대상). 설계서 2장·3장·7장.

	  물건 체력은 **플레이어마다 따로** — 세션의 hpTable[targetId] = 남은 체력 (없으면 가득 = target.hp). 남이 깨도 내 것은 그대로.
	  BreakRules.check(...)  칠 수 있나: 없는 id · 닫힌 월드 · 너무 먼 거리 → 무시 (reason "unknown" | "closed" | "far")
	  BreakRules.hit(...)    한 번 치기: 치는 힘 < minPower 면 피해 0 + reason "weak" (힘이 부족해요, 체력 안 깎임).
	                         체력이 0 이하가 되면 깨짐 → 그 물건 체력은 다시 가득 (hpTable 에서 지움). 넘친 피해는 버림.
	거리: 수평 거리 ≤ reach + slack (reach = 선임 MapLayout.targetReach(id) — 물건 크기에 맞는 거리), 높이 차 ≤ reach + VERTICAL_SLACK.
]]

local Targets = require(script.Parent.Data.Targets)
local Economy = require(script.Parent.Economy)

local BreakRules = {}

BreakRules.VERTICAL_SLACK = 20

export type HpTable = { [string]: number }
export type Point = { x: number, y: number, z: number }

export type HitOutcome = {
	damage: number,
	hp: number,
	hpMax: number,
	broken: boolean,
	reason: string?,
}

-- 캐릭터 위치가 물건에 닿을 만큼 가까운가 (pos 는 {x,y,z} 또는 Vector3 처럼 X/Y/Z)
function BreakRules.inReach(characterPos: any, targetPos: Point?, reach: number, slack: number): boolean
	if characterPos == nil or targetPos == nil then
		return false
	end
	local cx = tonumber(characterPos.x or characterPos.X)
	local cy = tonumber(characterPos.y or characterPos.Y)
	local cz = tonumber(characterPos.z or characterPos.Z)
	if cx == nil or cy == nil or cz == nil or cx ~= cx or cy ~= cy or cz ~= cz then
		return false
	end
	local r = (if type(reach) == "number" and reach == reach then reach else 0)
		+ (if type(slack) == "number" and slack == slack then slack else 0)
	if r <= 0 then
		return false
	end
	local dx, dz = cx - targetPos.x, cz - targetPos.z
	if dx * dx + dz * dz > r * r then
		return false
	end
	return math.abs(cy - targetPos.y) <= r + BreakRules.VERTICAL_SLACK
end

-- 칠 수 있나 (힘은 안 봄 — 힘 부족은 hit 이 "weak" 로). (target, nil) 또는 (nil, reason)
function BreakRules.check(
	targetId: unknown,
	openedWorld: number,
	characterPos: any,
	targetPos: Point?,
	reach: number,
	slack: number
): (Targets.Target?, string?)
	if typeof(targetId) ~= "string" then
		return nil, "unknown"
	end
	local target = Targets.get(targetId :: string)
	if not target then
		return nil, "unknown"
	end
	if type(openedWorld) ~= "number" or target.world > openedWorld then
		return nil, "closed"
	end
	if not BreakRules.inReach(characterPos, targetPos, reach, slack) then
		return nil, "far"
	end
	return target, nil
end

-- 지금 남은 체력 (처음이면 가득)
function BreakRules.currentHp(hpTable: HpTable, target: Targets.Target): number
	local hp = hpTable[target.id]
	if type(hp) ~= "number" or hp ~= hp or hp <= 0 or hp > target.hp then
		return target.hp
	end
	return hp
end

-- 한 번 치기 (hpTable 을 바꿈). damage = Economy.hitDamage(power, boost)
function BreakRules.hit(hpTable: HpTable, target: Targets.Target, damage: number): HitOutcome
	local d = Economy.clampPower(damage)
	local hp = BreakRules.currentHp(hpTable, target)
	if d < target.minPower or d <= 0 then
		return { damage = 0, hp = hp, hpMax = target.hp, broken = false, reason = "weak" }
	end
	local left = hp - d
	if left <= 0 then
		hpTable[target.id] = nil -- 깨짐 → 다시 가득
		return { damage = hp, hp = target.hp, hpMax = target.hp, broken = true }
	end
	hpTable[target.id] = left
	return { damage = d, hp = left, hpMax = target.hp, broken = false }
end

return BreakRules
