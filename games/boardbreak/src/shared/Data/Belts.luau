--!strict
--[[
	Belts — 띠 12개 (설계서 4장 + 9장 숫자 표). 순수 데이터.
	  { index, id, name, world, color (RGB), moneyMultiplier (깬 돈 배율), needPower (승급에 필요한 힘),
	    duel (true = 시험관 대결로만 받음 — 각 월드의 네 번째 띠), examBoardHp (승급 심사 송판 1장 체력, 대결 띠는 0),
	    duelBoardHp (대결 송판 1장 체력, 대결 띠만) }
	1번(흰 띠)은 처음부터 맴 (needPower 0). 승급은 1칸씩만 (앞 띠가 있어야 다음 띠).
	승급 심사: 20초 안에 송판 10장 — 송판 체력 = needPower × EXAM_HITS_AT_NEED (막 승급할 힘이면 1장에 그만큼 침).
]]

export type Belt = {
	index: number,
	id: string,
	name: string,
	world: number,
	color: { number },
	moneyMultiplier: number,
	needPower: number,
	duel: boolean,
	examBoardHp: number,
	duelBoardHp: number,
}

-- 승급할 힘(needPower)으로 심사 송판 1장을 몇 번 쳐야 하나 (10장 × 4번 = 40번 = 초당 4번이면 10초 — 20초 안에 넉넉)
local EXAM_HITS_AT_NEED = 4
-- 대결 띠: 대결을 시작할 힘(needPower)으로 대결 송판 1장을 몇 번 쳐야 하나 (15장 × 3번 = 45번 ≈ 11초 + 카운트다운 3초.
--   시험관은 15장 × 1.6 / 1.4 / 1.2초 = 24 / 21 / 18초 → 넉넉히 이김)
local DUEL_HITS_AT_NEED = 3

-- { id, 이름, 색, moneyMultiplier, needPower } — 숫자는 tests/sim_progress.luau 로 맞춘 것 (설계서 9장)
local ROWS: { { any } } = {
	{ "white", "흰 띠", { 245, 245, 245 }, 1, 0 },
	{ "yellow", "노랑 띠", { 255, 214, 64 }, 1.5, 1.33e8 },
	{ "green", "초록 띠", { 76, 190, 90 }, 2, 1.36e12 },
	{ "blue", "파랑 띠", { 64, 128, 230 }, 3, 1.69e16 },
	{ "purple", "보라 띠", { 150, 80, 210 }, 5, 1.01e19 },
	{ "brown", "갈색 띠", { 140, 90, 50 }, 8, 1.14e23 },
	{ "red", "빨강 띠", { 220, 50, 50 }, 12, 2.55e29 },
	{ "black", "검정 띠", { 30, 30, 30 }, 20, 5.85e29 },
	{ "dan_1", "1단 띠", { 40, 40, 60 }, 35, 2.13e33 },
	{ "dan_3", "3단 띠", { 60, 40, 80 }, 60, 1.47e36 },
	{ "dan_6", "6단 띠", { 90, 40, 100 }, 100, 3.68e38 },
	{ "dan_9", "9단 띠 (그랜드 마스터)", { 200, 160, 40 }, 200, 1.67e43 },
}

local list: { Belt } = {}
local byId: { [string]: Belt } = {}

for index, row in ROWS do
	local duel = index % 4 == 0
	local belt: Belt = {
		index = index,
		id = row[1],
		name = row[2],
		world = math.ceil(index / 4),
		color = row[3],
		moneyMultiplier = row[4],
		needPower = row[5],
		duel = duel,
		examBoardHp = if duel or index == 1 then 0 else row[5] * EXAM_HITS_AT_NEED,
		duelBoardHp = if duel then row[5] * DUEL_HITS_AT_NEED else 0,
	}
	table.insert(list, belt)
	byId[belt.id] = belt
end

local Belts = {
	list = list,
	COUNT = #list,
	EXAM_HITS_AT_NEED = EXAM_HITS_AT_NEED,
	DUEL_HITS_AT_NEED = DUEL_HITS_AT_NEED,
}

-- 띠 번호(1~12)로. 범위 밖·소수·NaN 이면 nil
function Belts.get(index: number): Belt?
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
		return nil
	end
	return list[index]
end

function Belts.byId(id: string): Belt?
	return byId[id]
end

return Belts
