--!nocheck
--[[
	numbers_doc — 설계서 9장 "숫자 표"를 코드(Data/Targets · Dumbbells · Belts · Worlds)에서 만들어 출력 (저장소 루트에서):
	  lune run games/boardbreak/tests/numbers_doc.luau
	숫자를 고친 뒤 이 출력으로 docs/DESIGN.md 9장의 표를 바꾸세요 (design_doc.spec 이 문서와 코드가 같은지 검사).
	표의 숫자 칸은 e 표기 (Luau 숫자 그대로) — 옆 칸은 화면 표시(Format.number).
]]

local Loader = require("./Loader")
Loader.get("ReplicatedStorage/Shared/Data/Config")
local Targets = Loader.require("ReplicatedStorage/Shared/Data/Targets")
local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")
local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")
local Worlds = Loader.require("ReplicatedStorage/Shared/Data/Worlds")
local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
local Format = Loader.require("ReplicatedStorage/Shared/Format")

local function e(n: number): string
	if n == 0 then
		return "0"
	end
	if n < 1e4 and n % 1 == 0 then
		return tostring(n)
	end
	local s = string.format("%.3g", n)
	s = string.gsub(s, "e%+0*", "e")
	return s
end

local lines = {}
local function add(s)
	table.insert(lines, s)
end

add("### 9-1. 물건 41개 (hp · minPower)")
add("")
add("| # | id | minPower | hp | 막 열렸을 때 타격 | 화면 (minPower / hp) |")
add("|---|---|---|---|---|---|")
for _, t in Targets.list do
	add(
		string.format(
			"| %d | %s | %s | %s | %d | %s / %s |",
			t.index,
			t.id,
			e(t.minPower),
			e(t.hp),
			Economy.hitsToBreak(t.hp, t.minPower),
			Format.number(t.minPower),
			Format.number(t.hp)
		)
	)
end
add("")
add("### 9-2. 아령 20개")
add("")
add("| 레벨 | id | 이름 | powerPerRep | price | 화면 (힘/번 · 값) |")
add("|---|---|---|---|---|---|")
for _, d in Dumbbells.list do
	add(
		string.format(
			"| %d | %s | %s | %s | %s | %s · %s |",
			d.level,
			d.id,
			d.name,
			e(d.powerPerRep),
			e(d.price),
			Format.number(d.powerPerRep),
			Format.number(d.price)
		)
	)
end
add("")
add("### 9-3. 띠 12개")
add("")
add("| # | id | 이름 | moneyMultiplier | needPower | 받는 법 | 송판 1장 체력 |")
add("|---|---|---|---|---|---|---|")
for _, b in Belts.list do
	local how = if b.index == 1 then "처음" elseif b.duel then "대결" else "심사"
	local boardHp = if b.duel then b.duelBoardHp else b.examBoardHp
	add(
		string.format(
			"| %d | %s | %s | %s | %s | %s | %s |",
			b.index,
			b.id,
			b.name,
			tostring(b.moneyMultiplier),
			e(b.needPower),
			how,
			e(boardHp)
		)
	)
end
add("")
add("### 9-4. 시험관 3명")
add("")
add("| 월드 | 시험관 | 송판 1장 (초) | 15장 (초) | 대결 송판 체력 |")
add("|---|---|---|---|---|")
for _, w in Worlds.list do
	add(
		string.format(
			"| %d | %s | %s | %s | %s |",
			w.index,
			w.examiner,
			tostring(w.examinerSecondsPerBoard),
			tostring(w.examinerSecondsPerBoard * 15),
			e(w.duelBoardHp)
		)
	)
end
print(table.concat(lines, "\n"))
