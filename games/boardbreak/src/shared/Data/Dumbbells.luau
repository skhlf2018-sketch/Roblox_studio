--!strict
--[[
	Dumbbells — 아령 20개 (설계서 4장 + 9장 숫자 표). 순수 데이터. 순서대로만 산다 (BuyDumbbell = 다음 아령).
	  { level, id, name, powerPerRep (한 번 들 때 오르는 힘, 힘 배수 전), price (돈) }
	1번(1kg 아령)은 처음부터 가짐 (price 0).
]]

export type Dumbbell = {
	level: number,
	id: string,
	name: string,
	powerPerRep: number,
	price: number,
}

-- { id, 이름, powerPerRep, price } — 숫자는 tests/sim_progress.luau 로 맞춘 것 (설계서 9장)
local ROWS: { { any } } = {
	{ "db_1kg", "1kg 아령", 1, 0 },
	{ "db_3kg", "3kg 아령", 100, 422 },
	{ "db_5kg", "5kg 아령", 1e4, 1320 },
	{ "db_10kg", "10kg 아령", 1e6, 1.49e4 },
	{ "db_25kg", "25kg 아령", 1e8, 1.34e5 },
	{ "db_50kg", "50kg 아령", 1e10, 1.8e6 },
	{ "db_100kg", "100kg 아령", 1e12, 1.45e8 },
	{ "db_steel", "강철 아령", 1e14, 1.54e9 },
	{ "db_gold", "황금 아령", 1e16, 4.47e10 },
	{ "db_diamond", "다이아 아령", 1e18, 7.16e11 },
	{ "db_lava", "용암 아령", 1e20, 2.16e13 },
	{ "db_ice", "얼음 아령", 1e22, 3.54e14 },
	{ "db_thunder", "번개 아령", 1e24, 8.85e15 },
	{ "db_rainbow", "무지개 아령", 1e26, 1.42e17 },
	{ "db_moon", "달 아령", 1e29, 4.54e19 },
	{ "db_star", "별 아령", 1e31, 3.74e20 },
	{ "db_sun", "태양 아령", 1e33, 1.17e22 },
	{ "db_galaxy", "은하 아령", 1e35, 1.91e23 },
	{ "db_supernova", "초신성 아령", 1e38, 1.57e26 },
	{ "db_blackhole", "블랙홀 아령", 1e40, 5.54e26 },
}

local list: { Dumbbell } = {}
local byId: { [string]: Dumbbell } = {}

for level, row in ROWS do
	local dumbbell: Dumbbell = {
		level = level,
		id = row[1],
		name = row[2],
		powerPerRep = row[3],
		price = row[4],
	}
	table.insert(list, dumbbell)
	byId[dumbbell.id] = dumbbell
end

local Dumbbells = {
	list = list,
	COUNT = #list,
}

-- 레벨(1~20)로. 범위 밖·소수·NaN 이면 nil
function Dumbbells.get(level: number): Dumbbell?
	if type(level) ~= "number" or level ~= level or level % 1 ~= 0 then
		return nil
	end
	return list[level]
end

function Dumbbells.byId(id: string): Dumbbell?
	return byId[id]
end

return Dumbbells
