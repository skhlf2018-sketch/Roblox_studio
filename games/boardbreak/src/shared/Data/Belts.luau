--!strict
--[[
	Belts — 띠 22개 (설계서 4장 + 9장 숫자 표, 사장님 결정 16번). 순수 데이터.
	  { index, id, name, world, color (RGB), colors (띠 천 색 1~3개 — 왼쪽 → 오른쪽 그러데이션, 한 색 띠는 { color }),
	    moneyMultiplier (깬 돈 배율), needPower (추천 힘 — 시작 조건 아님), duel (true = 시험관 대결로만 받음 — 각 월드의 마지막 띠),
	    examBoardHp (승급 심사 송판 1장 체력, 대결 띠·흰 띠는 0), duelBoardHp (대결 송판 1장 체력, 대결 띠만) }
	월드와 대결 여부는 아래 표의 칸에서 읽음 (월드마다 띠 개수가 다름: 7 · 7 · 8). 다른 코드는 "4개씩" 을 가정하지 말고
	Belts.ofWorld(w) · Belts.duelOf(w) · belt.world · belt.duel 을 쓸 것.
	1번(흰 띠)은 처음부터 맴 (needPower 0). 승급은 1칸씩만 (앞 띠가 있어야 다음 띠). 마지막 띠(천상 띠) = 그랜드 마스터.
	승급 심사: 20초 안에 송판 10장 — 송판 체력 = needPower × EXAM_HITS_AT_NEED (막 승급할 힘이면 1장에 그만큼 침).

	숫자 (tests/tune_numbers.luau 가 만듦 — 설계서 9장, sim 다시 맞추기 2026-11-16):
	  심사 띠 추천 힘 = 그 심사를 보는 물건 바로 앞 물건이 편해지는 힘(hp / 3) × 1.8 — 월드 안에서 물건 2개마다 한 번
	    (똑똑한 플레이어는 그 0.57배쯤, 앞 물건이 편해질 때 합격). 대결 띠 3개는 옛 값 (3.1e13 · 1.66e27 · 1.97e40).
	  배율 = 옛 12개 표의 (추천 힘, 배율) 꺾은선을 로그-로그로 따라간 두 자리 수 (같은 힘이면 옛날과 같은 배율).
]]

export type Belt = {
	index: number,
	id: string,
	name: string,
	world: number,
	color: { number },
	colors: { { number } },
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

type Row = {
	id: string,
	name: string,
	world: number,
	duel: boolean?,
	colors: { { number } }, -- 첫 색 = color
	mult: number,
	need: number,
}

-- 사장님 결정 16번 순서 그대로. 월드 1 = 7개 · 월드 2 = 7개 · 월드 3 = 8개, 각 월드 마지막 = 대결
local ROWS: { Row } = {
	-- 월드 1 (태권도장 마을) — 심사: 나무 송판 · 강철 · 컴퓨터 · 육교 · 학교 앞에서
	{ id = "white", name = "흰 띠", world = 1, colors = { { 245, 245, 245 } }, mult = 1, need = 0 },
	{ id = "yellow", name = "노랑 띠", world = 1, colors = { { 255, 214, 64 } }, mult = 1.3, need = 4110 },
	{ id = "green", name = "초록 띠", world = 1, colors = { { 76, 190, 90 } }, mult = 1.5, need = 3.99e5 },
	{ id = "blue", name = "파랑 띠", world = 1, colors = { { 64, 128, 230 } }, mult = 1.7, need = 3.79e7 },
	{ id = "purple", name = "보라 띠", world = 1, colors = { { 150, 80, 210 } }, mult = 2, need = 3.59e9 },
	{ id = "brown", name = "갈색 띠", world = 1, colors = { { 140, 90, 50 } }, mult = 2.4, need = 2.64e11 },
	{ id = "red", name = "빨강 띠", world = 1, duel = true, colors = { { 220, 50, 50 } }, mult = 3, need = 3.1e13 },
	-- 월드 2 (지구 한 바퀴) — 심사: 고층 빌딩 · 댐 · 항공모함 · 피라미드 · 화산 · 섬 앞에서
	{ id = "black", name = "검정 띠", world = 2, colors = { { 30, 30, 30 } }, mult = 3.5, need = 2.16e14 },
	{ id = "dan_1", name = "1단 띠", world = 2, colors = { { 40, 40, 60 } }, mult = 5, need = 2.05e16 },
	{ id = "dan_3", name = "3단 띠", world = 2, colors = { { 60, 40, 80 } }, mult = 6.4, need = 1.94e18 },
	{ id = "dan_6", name = "6단 띠", world = 2, colors = { { 90, 40, 100 } }, mult = 8, need = 1.56e20 },
	{ id = "dan_9", name = "9단 띠", world = 2, colors = { { 200, 160, 40 } }, mult = 9.8, need = 1.35e22 },
	{
		id = "master",
		name = "마스터 띠",
		world = 2,
		colors = { { 25, 25, 25 }, { 230, 180, 40 } }, -- 검정 + 금
		mult = 12,
		need = 1.28e24,
	},
	{
		id = "rainbow",
		name = "무지개 띠",
		world = 2,
		duel = true,
		colors = { { 230, 50, 50 }, { 250, 210, 50 }, { 60, 110, 230 } }, -- 빨 · 노 · 파 (선임: id rainbow 면 무지개 전체로 그려도 됨)
		mult = 20,
		need = 1.66e27,
	},
	-- 월드 3 (우주) — 심사: 수성 · 금성 · 해왕성 · 토성 · 태양 · 은하 · 우주 앞에서
	{
		id = "taegeuk",
		name = "태극 띠",
		world = 3,
		colors = { { 205, 40, 50 }, { 30, 70, 160 } }, -- 빨강 + 파랑
		mult = 23,
		need = 9.85e27,
	},
	{
		id = "infinity",
		name = "무한 띠",
		world = 3,
		colors = { { 250, 250, 250 }, { 175, 180, 190 } }, -- 흰색 + 은색
		mult = 35,
		need = 9.3e29,
	},
	{
		id = "cosmos",
		name = "우주 띠",
		world = 3,
		colors = { { 20, 25, 70 }, { 120, 60, 190 } }, -- 짙은 남색 + 보라
		mult = 51,
		need = 8.82e31,
	},
	{
		id = "youtube",
		name = "유튜브 띠",
		world = 3,
		colors = { { 230, 30, 30 }, { 255, 255, 255 } }, -- 빨강 + 흰색 (이름만 — 로고 없음)
		mult = 68,
		need = 7.08e33,
	},
	{
		id = "super",
		name = "슈퍼 띠",
		world = 3,
		colors = { { 255, 210, 40 }, { 40, 90, 220 } }, -- 노랑 + 파랑
		mult = 88,
		need = 6.18e35,
	},
	{
		id = "crazy",
		name = "미친 띠",
		world = 3,
		colors = { { 60, 255, 80 }, { 255, 40, 200 } }, -- 형광 초록 + 자홍
		mult = 120,
		need = 5.7e37,
	},
	{
		id = "legendary",
		name = "레전더리 띠",
		world = 3,
		colors = { { 255, 130, 20 }, { 255, 200, 50 } }, -- 주황 + 금
		mult = 180,
		need = 5.39e39,
	},
	{
		id = "heavenly",
		name = "천상 띠 (그랜드 마스터)",
		world = 3,
		duel = true,
		colors = { { 120, 200, 255 }, { 255, 255, 255 }, { 255, 210, 80 } }, -- 하늘색 + 흰색 + 금
		mult = 200,
		need = 1.97e40,
	},
}

local list: { Belt } = {}
local byId: { [string]: Belt } = {}
local byWorld: { [number]: { Belt } } = {}
local worldCount = 0

for index, row in ROWS do
	local duel = row.duel == true
	local colors: { { number } } = {}
	for _, c in row.colors do
		table.insert(colors, table.clone(c))
	end
	local belt: Belt = {
		index = index,
		id = row.id,
		name = row.name,
		world = row.world,
		color = table.clone(row.colors[1]),
		colors = colors,
		moneyMultiplier = row.mult,
		needPower = row.need,
		duel = duel,
		examBoardHp = if duel or index == 1 then 0 else row.need * EXAM_HITS_AT_NEED,
		duelBoardHp = if duel then row.need * DUEL_HITS_AT_NEED else 0,
	}
	table.insert(list, belt)
	byId[belt.id] = belt
	local inWorld = byWorld[row.world]
	if not inWorld then
		inWorld = {}
		byWorld[row.world] = inWorld
	end
	table.insert(inWorld, belt)
	worldCount = math.max(worldCount, row.world)
end

local Belts = {
	list = list,
	COUNT = #list,
	WORLD_COUNT = worldCount,
	EXAM_HITS_AT_NEED = EXAM_HITS_AT_NEED,
	DUEL_HITS_AT_NEED = DUEL_HITS_AT_NEED,
}

-- 띠 번호(1~COUNT)로. 범위 밖·소수·NaN 이면 nil
function Belts.get(index: number): Belt?
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
		return nil
	end
	return list[index]
end

function Belts.byId(id: string): Belt?
	return byId[id]
end

-- 그 월드의 띠 (순서대로). 없는 월드면 빈 표
function Belts.ofWorld(world: number): { Belt }
	local found = if type(world) == "number" then byWorld[world] else nil
	return if found then table.clone(found) else {}
end

-- 그 월드의 대결 띠 (= 그 월드의 마지막 띠 — 이기면 다음 월드가 열림). 없으면 nil
function Belts.duelOf(world: number): Belt?
	local found = if type(world) == "number" then byWorld[world] else nil
	if not found then
		return nil
	end
	for _, belt in found do
		if belt.duel then
			return belt
		end
	end
	return nil
end

return Belts
