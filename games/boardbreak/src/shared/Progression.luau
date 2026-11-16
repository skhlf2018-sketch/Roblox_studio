--!strict
--[[
	Progression — 띠 승급 · 월드 열림 · 아령 구매 조건 (순수 로직, Lune 테스트 대상). 설계서 2장·4장·6장.

	  띠: 1칸씩만 오름 (앞 띠가 있어야). 힘 조건 없음 — 언제든 도전 (사장님 결정 11번, needPower 는 추천 힘).
	      각 월드의 마지막 띠(Belts.duelOf(w) — 지금 7 빨강 · 14 무지개 · 22 천상)는 대결로만.
	  월드: 월드 w 대결 띠를 받으면 월드 w+1 이 열림 (Progression.worldsFromBelt — 띠 표에서 읽음, "4개씩" 가정 없음).
	      마지막 띠 = 그랜드 마스터.
	  아령: 순서대로만 (다음 아령 = 지금 + 1), 돈 ≥ price.
	  2048배 패스를 사도 순서는 못 건너뜀 (힘이 빨리 오를 뿐 — 띠는 1칸씩, 월드는 대결로만)
	이유 코드(reason): "max" 끝까지 다 함 · "duel" 대결로만 받는 띠 · "exam" 심사로 받는 띠 · "money" 돈 부족
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

-- 띠로 열리는 월드 = 1 + (가진 대결 띠 수) (지금: 띠 1~6 → 1, 7~13 → 2, 14~22 → 3)
function Progression.worldsFromBelt(belt: number): number
	local b = int(belt, 1, Belts.COUNT)
	local opened = 1
	for _, item in Belts.list do
		if item.duel and item.index <= b then
			opened += 1
		end
	end
	return math.min(Worlds.COUNT, opened)
end

-- 그 월드가 열리는 가장 낮은 띠 (월드 1 = 1, 월드 w = 월드 w-1 의 대결 띠). 개발 명령 /world 가 씀
function Progression.beltToOpen(world: number): number
	local w = int(world, 1, Worlds.COUNT)
	if w <= 1 then
		return 1
	end
	local duel = Belts.duelOf(w - 1)
	return if duel then duel.index else 1
end

-- 다음 띠 (마지막 띠면 nil)
function Progression.nextBelt(belt: number): Belts.Belt?
	return Belts.get(int(belt, 1, Belts.COUNT) + 1)
end

-- 승급 심사를 볼 수 있나 (힘은 안 봄 — 첫 인자는 옛 호출 모양 그대로 두려고): (ok, reason, 다음 띠)
function Progression.canExam(_power: number, belt: number): (boolean, string?, Belts.Belt?)
	local nextBelt = Progression.nextBelt(belt)
	if not nextBelt then
		return false, "max", nil
	end
	if nextBelt.duel then
		return false, "duel", nextBelt
	end
	return true, nil, nextBelt
end

-- 시험관 대결을 할 수 있나 (힘은 안 봄): (ok, reason, 다음 띠)
function Progression.canDuel(_power: number, belt: number): (boolean, string?, Belts.Belt?)
	local nextBelt = Progression.nextBelt(belt)
	if not nextBelt then
		return false, "max", nil
	end
	if not nextBelt.duel then
		return false, "exam", nextBelt
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
