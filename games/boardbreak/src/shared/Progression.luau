--!strict
--[[
	Progression — 띠 승급 · 월드 열림 · 아령 구매 조건 (순수 로직, Lune 테스트 대상). 설계서 2장·4장·6장.

	  띠: 1칸씩만 오름 (앞 띠가 있어야). 다음 띠의 needPower ≤ 저장된 힘(Power). 각 월드의 네 번째 띠(4·8·12)는 대결로만.
	  월드: 띠 4 → 월드 2, 띠 8 → 월드 3 이 열림 (Progression.worldsFromBelt). 띠 12 = 그랜드 마스터.
	  아령: 순서대로만 (다음 아령 = 지금 + 1), 돈 ≥ price.
	  2048배 패스를 사도 순서는 못 건너뜀 (힘이 빨리 오를 뿐 — 띠는 1칸씩, 월드는 대결로만)
	이유 코드(reason): "max" 끝까지 다 함 · "weak" 힘 부족 · "duel" 대결로만 받는 띠 · "exam" 심사로 받는 띠 · "money" 돈 부족
]]

local Belts = require(script.Parent.Data.Belts)
local Dumbbells = require(script.Parent.Data.Dumbbells)
local Worlds = require(script.Parent.Data.Worlds)

local Progression = {}

local function int(value: number, minValue: number, maxValue: number): number
	if type(value) ~= "number" or value ~= value then
		return minValue
	end
	return math.clamp(math.floor(value), minValue, maxValue)
end

-- 띠로 열리는 월드 (띠 1~3 → 1, 4~7 → 2, 8~12 → 3)
function Progression.worldsFromBelt(belt: number): number
	local b = int(belt, 1, Belts.COUNT)
	return math.min(Worlds.COUNT, 1 + math.floor(b / 4))
end

-- 다음 띠 (12 면 nil)
function Progression.nextBelt(belt: number): Belts.Belt?
	return Belts.get(int(belt, 1, Belts.COUNT) + 1)
end

-- 승급 심사를 볼 수 있나: (ok, reason, 다음 띠)
function Progression.canExam(power: number, belt: number): (boolean, string?, Belts.Belt?)
	local nextBelt = Progression.nextBelt(belt)
	if not nextBelt then
		return false, "max", nil
	end
	if nextBelt.duel then
		return false, "duel", nextBelt
	end
	if not (type(power) == "number" and power == power and power >= nextBelt.needPower) then
		return false, "weak", nextBelt
	end
	return true, nil, nextBelt
end

-- 시험관 대결을 할 수 있나: (ok, reason, 다음 띠)
function Progression.canDuel(power: number, belt: number): (boolean, string?, Belts.Belt?)
	local nextBelt = Progression.nextBelt(belt)
	if not nextBelt then
		return false, "max", nil
	end
	if not nextBelt.duel then
		return false, "exam", nextBelt
	end
	if not (type(power) == "number" and power == power and power >= nextBelt.needPower) then
		return false, "weak", nextBelt
	end
	return true, nil, nextBelt
end

-- 월드가 열렸나 (openedWorld = 저장된 world)
function Progression.isWorldOpen(world: number, openedWorld: number): boolean
	if type(world) ~= "number" or world ~= world or world % 1 ~= 0 then
		return false
	end
	return world >= 1 and world <= Worlds.COUNT and world <= int(openedWorld, 1, Worlds.COUNT)
end

-- 그랜드 마스터 (마지막 띠)
function Progression.isGrandMaster(belt: number): boolean
	return int(belt, 1, Belts.COUNT) >= Belts.COUNT
end

-- 다음 아령을 살 수 있나: (ok, reason, 다음 아령)
function Progression.canBuyDumbbell(level: number, money: number): (boolean, string?, Dumbbells.Dumbbell?)
	local nextDumbbell = Dumbbells.get(int(level, 1, Dumbbells.COUNT) + 1)
	if not nextDumbbell then
		return false, "max", nil
	end
	if not (type(money) == "number" and money == money and money >= nextDumbbell.price) then
		return false, "money", nextDumbbell
	end
	return true, nil, nextDumbbell
end

return Progression
