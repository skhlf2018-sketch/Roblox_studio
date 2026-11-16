--!nocheck
--[[
	tune_numbers — 설계서 6장 규칙으로 숫자 표를 **만드는** 도구 (저장소 루트에서):
	  lune run games/boardbreak/tests/tune_numbers.luau
	SimPlayer (sim_progress 와 같은 플레이어) 를 돌리면서 아직 안 정한 숫자를 그때그때 정하고,
	끝나면 Data/Targets · Dumbbells · Belts 에 붙여 넣을 줄을 출력함. 붙여 넣은 뒤 sim_progress 로 검사.

	정하는 법 (사장님 2026-11-16 결정 9·10번):
	  물건: 값(reward)은 설계서 3장 그대로. minPower = 앞 물건 × RHO[월드] (이웃 5~10배), hp = minPower × HP_FACTOR (막 열리면 15번).
	  아령: powerPerRep 는 CATALOG (1 · 3 · 10 · 25 · 100 → ×2.5·×4 번갈아 → 뒤는 ×4·×5 번갈아).
	        가격: 3kg = 42 (사장님). 그 뒤는 "지금 아령으로 힘이 오르는 빠르기(1번 힘 × 초당 4번 × 들기 비율 / 지금 힘)" 가
	        KAPPA(t) 아래로 떨어지면 그때 가진 돈 (3자리 올림) — 뒤로 갈수록 KAPPA 가 작아져 노가다가 길어짐.
	  띠: 심사 띠 needPower = EXAM_AT 물건의 minPower (그 물건이 열릴 때 심사). 대결 띠 = 그 월드 마지막 물건이
	      편해지고 DUEL_DELAY[월드] 초 뒤 힘 (월드 3 은 우주가 열리고 그만큼 뒤).
]]

local Loader = require("./Loader")
local SimPlayer = require("./SimPlayer")

Loader.get("ReplicatedStorage/Shared/Data/Config")
local Targets = Loader.require("ReplicatedStorage/Shared/Data/Targets")
local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")
local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")
local Worlds = Loader.require("ReplicatedStorage/Shared/Data/Worlds")
local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
local Progression = Loader.require("ReplicatedStorage/Shared/Progression")
local ExamRules = Loader.require("ReplicatedStorage/Shared/ExamRules")
local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")

local HUGE = math.huge

-- 조절 손잡이 ------------------------------------------------------------
local HP_FACTOR = 14.2 -- hp = minPower × 14.2 → 막 열리면 15번, 4.73배 힘이면 3번
local RHO_MAX = 9.7 -- 이웃 추천 힘 배율 위 끝 (10 아래 — 3자리 올림 여유)
local GAP = { 150, 195, 185 } -- 월드별: 앞 물건이 편해지고 다음 물건이 열리기까지 바라는 초
local LAMBDA_START, LAMBDA_END, LAMBDA_TAU = 0.05, 0.00355, 300 -- 바라는 힘 오르는 빠르기 (ln/초): 처음 빠르게 → 뒤 0.0037 (머묾 ≈ 7분)
local BETA, BETA_UNTIL = 0.15, 6 * 3600 -- 중간 이후에도 조금씩 느려지게 (노가다가 점점 길어짐)
local SYNC = 1.8 -- 물건이 막 편해졌을 때는 빠르기가 kappa × 1.8 아래면 바로 삼 (다음 물건까지 틈이 고르게)
local MAX_WAIT = 430 -- 아령 하나에 이 초가 넘으면 가격을 정함 (8분 넘지 않게)
local EXAM_EASE = 1.8
local TRAIN_SHARE = 10 / 21 -- 들기 비율 (10초 들기 / 10초 치기 / 바꾸기 0.5×2)
local DUEL_AT = { 1.25, 1.25, 1.6 } -- 대결 준비: 월드 1·2 = 마지막 물건 편해진 힘 × 이만큼, 월드 3 = 우주 추천 힘 × 이만큼
local DUEL_EASE = 2 -- 대결 추천 힘 = 그때 힘 × 2 (추천 힘이면 송판 1장 3번 — 똑똑한 플레이어는 그 절반쯤에서 이김)
local EXAM_AT = { [2] = 6, [3] = 10, [5] = 17, [6] = 21, [7] = 25, [9] = 31, [10] = 34, [11] = 38 }

-- 아령 목록 (id, 이름, weightKg) — powerPerRep 는 아래에서
local CATALOG = {
	{ "db_1kg", "1kg 아령", 1 },
	{ "db_3kg", "3kg 아령", 3 },
	{ "db_5kg", "5kg 아령", 5 },
	{ "db_10kg", "10kg 아령", 10 },
	{ "db_25kg", "25kg 아령", 25 },
	{ "db_50kg", "50kg 아령", 50 },
	{ "db_100kg", "100kg 아령", 100 },
	{ "db_250kg", "250kg 아령", 250 },
	{ "db_500kg", "500kg 아령", 500 },
	{ "db_1t", "1t 아령", 1000 },
	{ "db_2_5t", "2.5t 아령", 2500 },
	{ "db_5t", "5t 아령", 5000 },
	{ "db_10t", "10t 아령", 10000 },
	{ "db_car", "자동차 아령" },
	{ "db_truck", "트럭 아령" },
	{ "db_elephant", "코끼리 아령" },
	{ "db_bus", "버스 아령" },
	{ "db_tank", "탱크 아령" },
	{ "db_whale", "고래 아령" },
	{ "db_train", "기차 아령" },
	{ "db_airplane", "비행기 아령" },
	{ "db_cruise", "유람선 아령" },
	{ "db_rocket", "로켓 아령" },
	{ "db_lighthouse", "등대 아령" },
	{ "db_building", "빌딩 아령" },
	{ "db_castle", "성 아령" },
	{ "db_tower", "탑 아령" },
	{ "db_bridge", "다리 아령" },
	{ "db_pyramid", "피라미드 아령" },
	{ "db_hill", "언덕 아령" },
	{ "db_mountain", "산 아령" },
	{ "db_volcano", "화산 아령" },
	{ "db_iceberg", "빙산 아령" },
	{ "db_island", "섬 아령" },
	{ "db_desert", "사막 아령" },
	{ "db_continent", "대륙 아령" },
	{ "db_ocean", "바다 아령" },
	{ "db_earth", "지구 아령" },
	{ "db_asteroid", "소행성 아령" },
	{ "db_comet", "혜성 아령" },
	{ "db_moon", "달 아령" },
	{ "db_planet", "행성 아령" },
	{ "db_ringed", "고리 행성 아령" },
	{ "db_giant", "거대 행성 아령" },
	{ "db_sun", "태양 아령" },
	{ "db_redstar", "붉은 별 아령" },
	{ "db_bluestar", "푸른 별 아령" },
	{ "db_twinstar", "쌍둥이별 아령" },
	{ "db_neutron", "중성자별 아령" },
	{ "db_supernova", "초신성 아령" },
	{ "db_nebula", "성운 아령" },
	{ "db_cluster", "성단 아령" },
	{ "db_galaxy", "은하 아령" },
	{ "db_supercluster", "초은하단 아령" },
	{ "db_quasar", "퀘이사 아령" },
	{ "db_blackhole", "블랙홀 아령" },
	{ "db_giant_blackhole", "거대 블랙홀 아령" },
	{ "db_universe", "우주 아령" },
	{ "db_multiverse", "다중 우주 아령" },
	{ "db_infinity", "무한 아령" },
	{ "db_legend", "전설 아령" },
	{ "db_myth", "신화 아령" },
	{ "db_light", "빛의 아령" },
	{ "db_star_king", "별의 왕 아령" },
	{ "db_cosmos_king", "우주 왕 아령" },
}
local SWITCH_AT = 12 -- 이 레벨부터 ×4·×5·×5 (그 전 ×2.5·×4 — 2.5t 아령 1e5 까지 본부장 제안 그대로)

local function round3Up(x: number): number
	if x <= 0 then
		return 0
	end
	local e = math.floor(math.log10(x))
	local scale = 10 ^ (e - 2)
	local v = math.ceil(x / scale - 1e-9) * scale
	local clean = tonumber(string.format("%.3g", v))
	if clean < x then
		clean = tonumber(string.format("%.3g", v + scale))
	end
	return clean
end

-- 아령 표 만들기 (가격은 아직 HUGE)
local ppr = { 1, 3, 10, 25, 100 }
for level = 6, #CATALOG do
	local prev = ppr[level - 1]
	local r
	if level < SWITCH_AT then
		r = if level % 2 == 0 then 2.5 else 4
	else
		local k = (level - SWITCH_AT) % 3
		r = if k == 0 then 4 else 5 -- ×4 · ×5 · ×5 (세 칸마다 100배: 1 → 4 → 20 → 100)
	end
	ppr[level] = tonumber(string.format("%.3g", prev * r))
end
local weight = 10000
table.clear(Dumbbells.list)
for level, row in CATALOG do
	if not row[3] then
		weight *= 2
	end
	local d = {
		level = level,
		id = row[1],
		name = row[2],
		weightKg = row[3] or weight,
		powerPerRep = ppr[level],
		price = if level == 1 then 0 elseif level == 2 then 42 else HUGE,
	}
	Dumbbells.list[level] = d
end
Dumbbells.COUNT = #Dumbbells.list

-- 띠 (심사 띠는 앞 물건이 정해질 때, 대결 띠는 돌리면서)
local function setBelt(index: number, needPower: number)
	local b = Belts.list[index]
	b.needPower = needPower
	b.examBoardHp = if b.duel then 0 else needPower * Belts.EXAM_HITS_AT_NEED
	b.duelBoardHp = if b.duel then needPower * Belts.DUEL_HITS_AT_NEED else 0
	if b.duel then
		Worlds.list[b.world].duelBoardHp = b.duelBoardHp
	end
end
for index = 2, Belts.COUNT do
	setBelt(index, HUGE)
end

-- 물건: 솜만 미리. 나머지는 돌리면서 — 앞 물건이 편해지고 GAP 초 뒤 그때 힘 (이웃 배율 lowRatio ~ RHO_MAX 안에서)
local function defineTarget(i: number, power: number)
	local t = Targets.list[i]
	t.recommendPower = round3Up(power)
	t.minPower = t.recommendPower
	t.hp = round3Up(t.recommendPower * HP_FACTOR)
	-- 다음 물건에서 심사: 심사 띠 추천 힘 = 이 물건이 편해지는 힘 × EXAM_EASE (똑똑한 플레이어는 그 0.57배에서 합격)
	for belt, at in EXAM_AT do
		if at == i + 1 then
			setBelt(belt, round3Up(t.hp / 3 * EXAM_EASE))
		end
	end
end
for i, t in Targets.list do
	t.recommendPower = HUGE
	t.minPower = HUGE
	t.hp = 1e59 -- 아직 안 정함 (HUGE 는 Economy 가 0 으로 바꿔 버림)
	if i == 1 then
		defineTarget(1, 5)
	end
end
-- 물건 i → i+1 추천 힘 배율의 아래 끝: 5.2 와 (reward 배율 × 1.03) 중 큰 것 (hp 배율 ≥ reward 배율 — 뒤 물건 지름길 막기)
local function lowRatio(i: number): number
	return math.max(5.2, Targets.list[i + 1].reward / Targets.list[i].reward * 1.03)
end

-- 바라는 힘 오르는 빠르기 λ(t): 처음 빠르게 → 점점 느리게 (뒤로 갈수록 아령 노가다가 조금씩 길어짐)
local function lambdaAt(t: number): number
	return LAMBDA_END * (1 + BETA * math.max(0, 1 - t / BETA_UNTIL))
		+ (LAMBDA_START - LAMBDA_END) * math.exp(-t / LAMBDA_TAU)
end
-- 다음 아령을 살 때: "지금 빠르기" 가 kappa 아래로. 사고 나면 빠르기가 r 배로 뛰었다가 줄어듦 → 평균 = kappa × r ln r / (r - 1)
local function kappa(t: number, r: number): number
	return lambdaAt(t) * (r - 1) / (r * math.log(r))
end

local m = {
	Targets = Targets,
	Dumbbells = Dumbbells,
	Belts = Belts,
	Worlds = Worlds,
	Economy = Economy,
	Progression = Progression,
	ExamRules = ExamRules,
	MapLayout = MapLayout,
}

local hooks = {
	onStep = function(s, log)
		local damage = Economy.hitDamage(s.power, 1)
		-- 다음 물건
		for i = 2, Targets.COUNT do
			local t = Targets.list[i]
			if t.recommendPower == HUGE then
				local prev = Targets.list[i - 1]
				local comf = log.comf[i - 1]
				if comf then
					local ratio = damage / prev.recommendPower
					local due = s.t >= comf + GAP[t.world]
					if ratio >= RHO_MAX or (due and ratio >= lowRatio(i - 1)) then
						defineTarget(i, damage)
					end
				end
				break
			end
		end
		-- 다음 아령 가격
		local nextLevel = s.db + 1
		local nextDumbbell = Dumbbells.list[nextLevel]
		if nextDumbbell and nextDumbbell.price == HUGE and s.power > 0 then
			local speed = Dumbbells.list[s.db].powerPerRep * 4 * TRAIN_SHARE / s.power
			local limit = kappa(s.t, nextDumbbell.powerPerRep / Dumbbells.list[s.db].powerPerRep)
			local justComfortable = false
			for _, at in log.comf do
				if s.t - at < 2 then
					justComfortable = true
				end
			end
			if speed <= limit or (justComfortable and speed <= limit * SYNC) or s.t - log.buy[s.db] >= MAX_WAIT then
				local prevPrice = Dumbbells.list[s.db].price
				nextDumbbell.price = math.max(round3Up(math.max(s.money, 1)), round3Up(prevPrice * 1.05))
			end
		end
		-- 대결 띠
		for w = 1, 3 do
			local belt = Belts.list[w * 4]
			if belt.needPower == HUGE then
				local lastTarget = Targets.list[Worlds.list[w].lastTarget]
				local base = if w < 3 then lastTarget.hp / 3 else lastTarget.recommendPower
				if s.power >= base * DUEL_AT[w] then
					setBelt(w * 4, math.max(round3Up(s.power * DUEL_EASE), lastTarget.recommendPower))
				end
			end
		end
	end,
}
local final, log = SimPlayer.run(m, hooks)

local function mmss(seconds: number?): string
	if not seconds then
		return "-"
	end
	return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end
local function e(n: number): string
	if n == 0 then
		return "0"
	end
	if n < 1e4 and n % 1 == 0 then
		return tostring(n)
	end
	local str = string.format("%.3g", n)
	str = string.gsub(str, "e%+0*", "e")
	return str
end

print("== 물건 (열림 · 머문 시간 · 다음까지)")
local maxStay, minGap, maxGap = 0, HUGE, 0
for i, t in Targets.list do
	local stay = if log.open[i] and log.comf[i] then log.comf[i] - log.open[i] else nil
	local gap = if log.comf[i] and log.open[i + 1] then log.open[i + 1] - log.comf[i] else nil
	if stay and i < Targets.COUNT then
		maxStay = math.max(maxStay, stay)
	end
	if gap then
		if log.open[i] and log.open[i] > 600 then
			minGap = math.min(minGap, gap)
		end
		maxGap = math.max(maxGap, gap)
	end
	print(
		string.format(
			"%2d %-12s open %s stay %5.0f gap %5.0f  minPower %s hp %s",
			i,
			t.id,
			mmss(log.open[i]),
			stay or -1,
			gap or -1,
			e(t.recommendPower),
			e(t.hp)
		)
	)
end
print("== 아령 (산 시각 · 걸린 시간)")
local last = 1
for level = 2, Dumbbells.COUNT do
	if log.buy[level] then
		last = level
		print(
			string.format(
				"%2d %-14s ppr %-8s price %-8s at %s took %4.0f",
				level,
				Dumbbells.list[level].name,
				e(Dumbbells.list[level].powerPerRep),
				e(Dumbbells.list[level].price),
				mmss(log.buy[level]),
				log.buy[level] - log.buy[level - 1]
			)
		)
	end
end
print(
	string.format(
		"월드 끝 %s · %s · %s | 가장 긴 머묾 %.0f초 · 틈 %.0f~%.0f초 (10분 뒤) · 아령 %d개 · 마지막 힘 %s",
		mmss(log.worldOpen[2]),
		mmss(log.worldOpen[3]),
		mmss(log.belt[12]),
		maxStay,
		minGap,
		maxGap,
		last,
		e(final.power)
	)
)

print("\n-- Targets ROWS (minPower, hp)")
for _, t in Targets.list do
	print(
		string.format(
			'\t{ "%s", "%s", %d, %s, %s, %s },',
			t.id,
			t.name,
			t.world,
			e(t.reward),
			e(t.recommendPower),
			e(t.hp)
		)
	)
end
print("\n-- Dumbbells ROWS")
for level = 1, last do
	local d = Dumbbells.list[level]
	print(string.format('\t{ "%s", "%s", %s, %s, %s },', d.id, d.name, e(d.weightKg), e(d.powerPerRep), e(d.price)))
end
print("\n-- Belts needPower")
for _, b in Belts.list do
	print(b.id, e(b.needPower))
end
