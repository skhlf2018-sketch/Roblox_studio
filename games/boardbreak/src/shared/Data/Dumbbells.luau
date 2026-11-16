--!strict
--[[
	Dumbbells — 아령 (설계서 4장 + 9장 숫자 표). 순수 데이터. 순서대로만 산다 (BuyDumbbell = 다음 아령). 개수 = #list (지금 60).
	  { level, id, name, weightKg (겉모습 크기용 — 큰 아령일수록 큰 수), powerPerRep (한 번 들 때 오르는 힘, 힘 배수 전), price (돈) }
	1번(1kg 아령)은 처음부터 가짐 (price 0).
	사장님 결정 9번 (2026-11-16): 힘은 무게와 함께 완만하게 — 1kg 1 · 3kg 3 · 5kg 10 · 10kg 25 · 25kg 100 (사장님 숫자),
	  그 뒤 ×2.5·×4 번갈아 (두 칸마다 10배, 2.5t 아령 100,000 까지) → 그 뒤 ×4·×5·×5 (세 칸마다 100배).
	  가격은 3kg 아령 42 (1판의 1/10, 사장님) 부터, "다음 아령을 사기까지 걸리는 시간" 이 앞 아령보다 줄지 않고 (95% 이상, 주임 B-1)
	  17초 → 마지막 약 5분 까지 꾸준히 늘게 (한도 10분 — 설계서 9장, sim_progress 로 검사).
	  2026-11-16 sim 다시 맞추기 (결정 13·14·16번 — 걷기 32 × 몸 배율 · 띠 22개): tests/tune_numbers.luau 가 지금 사는 시간을
	  "줄지 않는 부드러운 오르막"(합계 = 게임 길이 그대로)으로 고른 뒤 그 시간이 지났을 때 가진 돈으로 값을 정하고,
	  심사·대결이 끼어 줄어드는 칸만 다시 올림.
]]

export type Dumbbell = {
	level: number,
	id: string,
	name: string,
	weightKg: number,
	powerPerRep: number,
	price: number,
}

-- { id, 이름, weightKg, powerPerRep, price } — 힘/번은 tests/tune_numbers.luau, 가격은 설계서 9장 방법 (B-1: 노가다가 줄지 않게)
local ROWS: { { any } } = {
	{ "db_1kg", "1kg 아령", 1, 1, 0 },
	{ "db_3kg", "3kg 아령", 3, 3, 42 },
	{ "db_5kg", "5kg 아령", 5, 10, 1140 },
	{ "db_10kg", "10kg 아령", 10, 25, 6400 },
	{ "db_25kg", "25kg 아령", 25, 100, 1.11e4 },
	{ "db_50kg", "50kg 아령", 50, 250, 1.07e5 },
	{ "db_100kg", "100kg 아령", 100, 1000, 2.89e5 },
	{ "db_250kg", "250kg 아령", 250, 2500, 1.05e6 },
	{ "db_500kg", "500kg 아령", 500, 1e4, 5.05e6 },
	{ "db_1t", "1t 아령", 1000, 2.5e4, 1.4e7 },
	{ "db_2_5t", "2.5t 아령", 2500, 1e5, 4.03e7 },
	{ "db_5t", "5t 아령", 5000, 4e5, 6.76e7 },
	{ "db_10t", "10t 아령", 1e4, 2e6, 4.04e8 },
	{ "db_car", "자동차 아령", 2e4, 1e7, 1.47e9 },
	{ "db_truck", "트럭 아령", 4e4, 4e7, 5.47e9 },
	{ "db_elephant", "코끼리 아령", 8e4, 2e8, 3.23e10 },
	{ "db_bus", "버스 아령", 1.6e5, 1e9, 1.4e11 },
	{ "db_tank", "탱크 아령", 3.2e5, 4e9, 5.24e11 },
	{ "db_whale", "고래 아령", 6.4e5, 2e10, 2.78e12 },
	{ "db_train", "기차 아령", 1.28e6, 1e11, 1.3e13 },
	{ "db_airplane", "비행기 아령", 2.56e6, 4e11, 4.39e13 },
	{ "db_cruise", "유람선 아령", 5.12e6, 2e12, 1.54e14 },
	{ "db_rocket", "로켓 아령", 1.02e7, 1e13, 1.21e15 },
	{ "db_lighthouse", "등대 아령", 2.05e7, 4e13, 4.89e15 },
	{ "db_building", "빌딩 아령", 4.1e7, 2e14, 1.56e16 },
	{ "db_castle", "성 아령", 8.19e7, 1e15, 1.03e17 },
	{ "db_tower", "탑 아령", 1.64e8, 4e15, 4.61e17 },
	{ "db_bridge", "다리 아령", 3.28e8, 2e16, 1.47e18 },
	{ "db_pyramid", "피라미드 아령", 6.55e8, 1e17, 7.66e18 },
	{ "db_hill", "언덕 아령", 1.31e9, 4e17, 3.71e19 },
	{ "db_mountain", "산 아령", 2.62e9, 2e18, 1.43e20 },
	{ "db_volcano", "화산 아령", 5.24e9, 1e19, 6.11e20 },
	{ "db_iceberg", "빙산 아령", 1.05e10, 4e19, 3.18e21 },
	{ "db_island", "섬 아령", 2.1e10, 2e20, 1.05e22 },
	{ "db_desert", "사막 아령", 4.19e10, 1e21, 4.61e22 },
	{ "db_continent", "대륙 아령", 8.39e10, 4e21, 2.19e23 },
	{ "db_ocean", "바다 아령", 1.68e11, 2e22, 7.99e23 },
	{ "db_earth", "지구 아령", 3.36e11, 1e23, 3.73e24 },
	{ "db_asteroid", "소행성 아령", 6.71e11, 4e23, 1.58e25 },
	{ "db_comet", "혜성 아령", 1.34e12, 2e24, 6.07e25 },
	{ "db_moon", "달 아령", 2.68e12, 1e25, 2.03e26 },
	{ "db_planet", "행성 아령", 5.37e12, 4e25, 1.43e27 },
	{ "db_ringed", "고리 행성 아령", 1.07e13, 2e26, 7.13e27 },
	{ "db_giant", "거대 행성 아령", 2.15e13, 1e27, 3.22e28 },
	{ "db_sun", "태양 아령", 4.29e13, 4e27, 9.56e28 },
	{ "db_redstar", "붉은 별 아령", 8.59e13, 2e28, 6.6e29 },
	{ "db_bluestar", "푸른 별 아령", 1.72e14, 1e29, 2.61e30 },
	{ "db_twinstar", "쌍둥이별 아령", 3.44e14, 4e29, 9.92e30 },
	{ "db_neutron", "중성자별 아령", 6.87e14, 2e30, 6.27e31 },
	{ "db_supernova", "초신성 아령", 1.37e15, 1e31, 2.42e32 },
	{ "db_nebula", "성운 아령", 2.75e15, 4e31, 9.4e32 },
	{ "db_cluster", "성단 아령", 5.5e15, 2e32, 5.12e33 },
	{ "db_galaxy", "은하 아령", 1.1e16, 1e33, 2.11e34 },
	{ "db_supercluster", "초은하단 아령", 2.2e16, 4e33, 8.97e34 },
	{ "db_quasar", "퀘이사 아령", 4.4e16, 2e34, 3.22e35 },
	{ "db_blackhole", "블랙홀 아령", 8.8e16, 1e35, 1.56e36 },
	{ "db_giant_blackhole", "거대 블랙홀 아령", 1.76e17, 4e35, 6.6e36 },
	{ "db_universe", "우주 아령", 3.52e17, 2e36, 3.28e37 },
	{ "db_multiverse", "다중 우주 아령", 7.04e17, 1e37, 1.29e38 },
	{ "db_infinity", "무한 아령", 1.41e18, 4e37, 5.09e38 },
}

local list: { Dumbbell } = {}
local byId: { [string]: Dumbbell } = {}

for level, row in ROWS do
	local dumbbell: Dumbbell = {
		level = level,
		id = row[1],
		name = row[2],
		weightKg = row[3],
		powerPerRep = row[4],
		price = row[5],
	}
	table.insert(list, dumbbell)
	byId[dumbbell.id] = dumbbell
end

local Dumbbells = {
	list = list,
	COUNT = #list,
}

-- 레벨(1~COUNT)로. 범위 밖·소수·NaN 이면 nil
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
