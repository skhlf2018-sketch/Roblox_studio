--!nocheck
--[[
	sim_progress — 송판 깨기 "열심히 하는 플레이어" 흉내로 설계서 6장 숫자 규칙 검사. 저장소 루트에서:
	  lune run games/boardbreak/tests/sim_progress.luau          (자세히: ... sim_progress.luau -v)
	진짜 숫자 표(Data/Targets · Dumbbells · Belts · Worlds)와 진짜 규칙(Economy · Progression · ExamRules · MapLayout)을 씀.
	플레이어는 tests/SimPlayer.luau (길가 매트에서 10초 들기 ↔ 10초 치기, 0.27초마다, 돈이 가장 빨리 모이는 물건을 침 —
	힘 문턱이 없으니 열린 월드의 물건 전부 중에서 고름 · 심사/대결은 이길 수 있을 때 바로).
	"열림" = 추천 힘(recommendPower)에 닿음 (15번에 깸) · "편해짐" = 3번 안에 깸 · 머묾 = 열림 → 편해짐.
	검사 (설계서 6장 · 사장님 결정 9·10·11번):
	  첫 솜 30초 안 · 처음 5분 안에 아령 2번 이상
	  이웃 물건 reward · 추천 힘 · hp 배율 5~10, hp 배율 ≥ reward 배율 · 추천 힘이면 15~30번
	  어떤 물건도 9분 넘게 머물지 않음 · 편해짐 → 다음 열림 4분 안 (처음 10분 뒤부터는 20초~4분 — 결정 12번 뒤 1분 → 20초)
	  아령마다 사는 데 걸린 시간 10분 안 · 앞 아령의 95% 아래로 안 줄어듦 (점점 늘어남, B-1) · 뒤 1/3 평균 > 가운데 1/3 > 앞 1/3
	  월드 1 끝 30~56분 · 월드 2 끝 1:26~2:40 · 월드 3 끝 2:36~4:50 (처음부터, 대결에서 이긴 시각 — 결정 12번 뒤 결과 ±30%)
	  어느 힘에서든 돈이 가장 빨리 모이는 물건 = 지금 힘에 맞는 물건 (15번 넘게 걸리는 뒤 물건이 이득이 아님 — 지름길 없음)
	  심사 송판 (추천 힘이면 20초 안) · 대결 (추천 힘이면 시험관보다 넉넉히 먼저) · 똑똑한 플레이어의 심사/대결은 전부 이김
	실패가 있으면 종료 코드 1.
]]

local process = require("@lune/process")
local Loader = require("./Loader")
local SimPlayer = require("./SimPlayer")

Loader.get("ReplicatedStorage/Shared/Data/Config")
local Targets = Loader.require("ReplicatedStorage/Shared/Data/Targets")
local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")
local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")
local Worlds = Loader.require("ReplicatedStorage/Shared/Data/Worlds")
local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
local Progression = Loader.require("ReplicatedStorage/Shared/Progression")
local ExamRules = Loader.require("ReplicatedStorage/Shared/ExamRules")
local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
local Format = Loader.require("ReplicatedStorage/Shared/Format")

local VERBOSE = false
for _, a in process.args do
	if a == "-v" then
		VERBOSE = true
	end
end

local SIM = SimPlayer.SIM

-- 설계서 6장 기준
local RULES = {
	firstBreakSeconds = 30,
	earlyBuys = 2,
	earlyBuySeconds = 300,
	maxStay = 540, -- 9분 (B-1·B-2 때 8 → 9분)
	gapMin = 20, -- 결정 12번 (돈 2~4배) 뒤 힘이 빨리 올라 가장 짧은 틈 28초 → 아래 끝 20초 (옛 60초)
	gapMax = 240,
	earlySeconds = 600, -- 처음 10분은 물건이 빨리 바뀜 (힘이 빨리 오르는 때 — 틈 1분 아래 허용)
	maxBuySeconds = 600, -- 10분 (B-1: 사장님 "노가다가 점점 늘어남")
	buyNoDip = 0.95, -- 아령 N 사는 시간 ≥ 아령 N−1 × 0.95
	worldEnd = { { 30 * 60, 56 * 60 }, { 86 * 60, 160 * 60 }, { 156 * 60, 290 * 60 } }, -- 결정 12번 뒤 결과 ±30% (42:51 · 2:02:46 · 3:43:09)
	neighbor = { 5, 10 },
	hitsAtOpen = { 15, 30 },
	shortcutMax = 1.0, -- 두 칸 넘게 뒤 물건을 오래 쳐서 버는 돈이 지금 힘에 맞는 물건보다 많으면 안 됨
}

local failures = {}
local function check(ok: boolean, text: string)
	if not ok then
		table.insert(failures, text)
	end
end

local function mmss(seconds: number?): string
	if not seconds then
		return "-"
	end
	return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

local final, log = SimPlayer.run({
	Targets = Targets,
	Dumbbells = Dumbbells,
	Belts = Belts,
	Worlds = Worlds,
	Economy = Economy,
	Progression = Progression,
	ExamRules = ExamRules,
	MapLayout = MapLayout,
})

------------------------------------------------------------------
-- 물건 표
------------------------------------------------------------------
print(
	"== 송판 깨기 진행 시뮬레이션 (열심히 하는 플레이어: 들기·치기 0.27초마다 · 로벅스 없음)"
)
if VERBOSE then
	print(
		"   #  물건          열림       머묾    →다음   추천 힘    hp         값        배율(값/힘)"
	)
end
local stays = {}
local minReward, maxReward = math.huge, 0
for _, target in Targets.list do
	local i = target.index
	local hitsAtOpen = Economy.hitsToBreak(target.hp, target.recommendPower)
	check(
		hitsAtOpen >= RULES.hitsAtOpen[1] and hitsAtOpen <= RULES.hitsAtOpen[2],
		string.format("%s 추천 힘이면 %d번 (15~30)", target.id, hitsAtOpen)
	)
	local rewardRatio, powerRatio = nil, nil
	if i < Targets.COUNT then
		local nxt = Targets.list[i + 1]
		rewardRatio = nxt.reward / target.reward
		powerRatio = nxt.recommendPower / target.recommendPower
		local hpRatio = nxt.hp / target.hp
		minReward, maxReward = math.min(minReward, rewardRatio), math.max(maxReward, rewardRatio)
		for name, r in { reward = rewardRatio, recommendPower = powerRatio, hp = hpRatio } do
			check(
				r >= RULES.neighbor[1] and r <= RULES.neighbor[2],
				string.format("%s → %s %s 배율 %.2f (5~10)", target.id, nxt.id, name, r)
			)
		end
		check(
			hpRatio >= rewardRatio,
			string.format(
				"%s → %s hp 배율 %.2f < reward 배율 %.2f (뒤 물건이 지름길)",
				target.id,
				nxt.id,
				hpRatio,
				rewardRatio
			)
		)
	end
	check(log.open[i] ~= nil, target.id .. " 이 열리지 않음")
	local stay = if log.open[i] and log.comf[i] then log.comf[i] - log.open[i] else nil
	local gap = if i < Targets.COUNT and log.comf[i] and log.open[i + 1] then log.open[i + 1] - log.comf[i] else nil
	if i < Targets.COUNT then
		check(
			stay ~= nil and stay <= RULES.maxStay,
			string.format("%s 머묾 %s (9분 안)", target.id, if stay then mmss(stay) else "편해지지 않음")
		)
		local early = log.open[i] ~= nil and log.open[i] <= RULES.earlySeconds
		check(
			gap ~= nil and gap <= RULES.gapMax and (early or gap >= RULES.gapMin),
			string.format(
				"%s 편해짐 → %s 열림 %s초 (%s)",
				target.id,
				Targets.list[i + 1].id,
				tostring(gap and math.floor(gap)),
				if early then "0~240" else "20~240"
			)
		)
		if stay then
			table.insert(stays, { id = target.id, name = target.name, stay = stay })
		end
	end
	if VERBOSE then
		print(
			string.format(
				"  %2d  %-12s %9s %7s %7s   %-9s  %-9s  %-8s  %s",
				i,
				target.id,
				mmss(log.open[i]),
				if stay then string.format("%ds", math.floor(stay)) else "-",
				if gap then string.format("%ds", math.floor(gap)) else "-",
				Format.number(target.recommendPower),
				Format.number(target.hp),
				Format.number(target.reward),
				if rewardRatio then string.format("%.2f / %.2f", rewardRatio, powerRatio) else ""
			)
		)
	end
end

------------------------------------------------------------------
-- 지름길 점검: 어느 힘에서든 돈이 가장 빨리 모이는 물건 (열린 월드 상관없이 전부) 이 15번 안에 깨지는 물건
------------------------------------------------------------------
do
	-- 먼 뒤 물건 (열린 물건 = 추천 힘에 닿은 가장 뒤 물건, 그 다음 물건보다 더 뒤) 이 "지금 힘에 맞는 물건"(열린 물건까지 + 바로 다음) 보다 이득이면 지름길
	local worst, worstAt, worstId = 0, 0, ""
	local d = 1
	while d < Targets.list[Targets.COUNT].hp * 10 do
		local lastOpen = 1
		for _, target in Targets.list do
			if d >= target.recommendPower then
				lastOpen = target.index
			end
		end
		local bestOpen, bestFar, farTarget = 0, 0, nil
		for _, target in Targets.list do
			local rate = target.reward / Economy.hitsToBreak(target.hp, d)
			if target.index <= lastOpen + 1 then
				bestOpen = math.max(bestOpen, rate)
			elseif rate > bestFar then
				bestFar, farTarget = rate, target
			end
		end
		if bestOpen > 0 and farTarget and bestFar / bestOpen > worst then -- (1 보다 작으면 먼 물건이 손해)
			worst, worstAt, worstId = bestFar / bestOpen, d, farTarget.id
		end
		d *= 1.03
	end
	check(
		worst <= RULES.shortcutMax,
		string.format(
			"지름길: 힘 %s 에서 먼 뒤 물건 %s 가 지금 힘에 맞는 물건의 %.2f배 (%.2f배까지)",
			Format.number(worstAt),
			worstId,
			worst,
			RULES.shortcutMax
		)
	)
	print(
		string.format(
			"지름길 점검: 두 칸 넘게 뒤 물건을 오래 쳐도 지금 힘에 맞는 물건의 최대 %.2f배 (힘 %s · %s) — %.2f배까지 허용",
			worst,
			Format.number(worstAt),
			worstId,
			RULES.shortcutMax
		)
	)
end

------------------------------------------------------------------
-- 아령 (사는 데 걸린 시간)
------------------------------------------------------------------
local tooks = {}
for level = 2, Dumbbells.COUNT do
	local d = Dumbbells.list[level]
	local took = if log.buy[level] and log.buy[level - 1] then log.buy[level] - log.buy[level - 1] else nil
	check(took ~= nil, d.id .. " 을 그랜드 마스터 전에 못 삼")
	if took then
		table.insert(tooks, took)
		check(took <= RULES.maxBuySeconds, string.format("%s 사는 데 %ds (10분 안)", d.id, math.floor(took)))
		local prevTook = tooks[#tooks - 1]
		check(
			prevTook == nil or took >= prevTook * RULES.buyNoDip,
			string.format(
				"%s 사는 데 %ds — 앞 아령 %ds 의 95%% 아래 (점점 늘어야)",
				d.id,
				math.floor(took),
				math.floor(prevTook or 0)
			)
		)
	end
	check(type(d.weightKg) == "number" and d.weightKg > Dumbbells.list[level - 1].weightKg, d.id .. " weightKg 증가")
	if VERBOSE then
		print(
			string.format(
				"  아령 %2d %-16s 힘/번 %-8s 값 %-8s 산 시각 %s (걸린 시간 %s초)",
				level,
				d.name,
				Format.number(d.powerPerRep),
				Format.number(d.price),
				mmss(log.buy[level]),
				if took then tostring(math.floor(took)) else "-"
			)
		)
	end
end
local thirds = { 0, 0, 0 }
do
	local n = #tooks
	local size = math.floor(n / 3)
	local ranges = { { 1, size }, { size + 1, 2 * size }, { 2 * size + 1, n } }
	for k, r in ranges do
		local sum = 0
		for i = r[1], r[2] do
			sum += tooks[i]
		end
		thirds[k] = sum / math.max(1, r[2] - r[1] + 1)
	end
	check(
		thirds[3] > thirds[2] and thirds[2] > thirds[1],
		string.format(
			"아령 노가다 평균 앞 %.0f · 가운데 %.0f · 뒤 %.0f초 (점점 늘어야)",
			thirds[1],
			thirds[2],
			thirds[3]
		)
	)
end

if VERBOSE then
	for index = 2, Belts.COUNT do
		local b = Belts.list[index]
		print(
			string.format(
				"  띠 %2d %-14s 추천 힘 %-8s ×%s  받은 시각 %s",
				index,
				b.name,
				Format.number(b.needPower),
				tostring(b.moneyMultiplier),
				mmss(log.belt[index])
			)
		)
	end
end

------------------------------------------------------------------
-- 처음 · 월드 끝
------------------------------------------------------------------
check(
	log.firstBreak ~= nil and log.firstBreak <= RULES.firstBreakSeconds,
	"첫 솜 " .. tostring(log.firstBreak) .. "초 (30초 안)"
)
local earlyBuys = 0
for level = 2, Dumbbells.COUNT do
	if log.buy[level] and log.buy[level] <= RULES.earlyBuySeconds then
		earlyBuys += 1
	end
end
check(earlyBuys >= RULES.earlyBuys, "처음 5분 안에 아령 " .. earlyBuys .. "번 (2번 이상)")

local worldEnds = { log.worldOpen[2], log.worldOpen[3], log.belt[Belts.COUNT] }
for w = 1, 3 do
	local range = RULES.worldEnd[w]
	local at = worldEnds[w]
	check(
		at ~= nil and at >= range[1] and at <= range[2],
		string.format("월드 %d 끝 %s (목표 %s ~ %s)", w, mmss(at), mmss(range[1]), mmss(range[2]))
	)
end

------------------------------------------------------------------
-- 심사·대결 (추천 힘으로 넉넉한가 · 똑똑한 플레이어는 다 이김)
------------------------------------------------------------------
for _, belt in Belts.list do
	if belt.index > 1 and not belt.duel then
		local seconds = Config.EXAM_BOARDS * Economy.hitsToBreak(belt.examBoardHp, belt.needPower * 1.0001) * SIM.TICK -- (부동소수 여유)
		check(
			seconds < Config.EXAM_SECONDS,
			string.format("%s 심사 %.1f초 (추천 힘이면 20초 안)", belt.id, seconds)
		)
	elseif belt.duel then
		local world = Worlds.get(belt.world)
		local mine = Config.DUEL_BOARDS * Economy.hitsToBreak(belt.duelBoardHp, belt.needPower * 1.0001) * SIM.TICK
		local theirs = Config.DUEL_BOARDS * world.examinerSecondsPerBoard
		check(
			mine * 1.4 < theirs,
			string.format(
				"%s 대결 내 %.1f초 vs 시험관 %.1f초 (추천 힘이면 1.4배 넉넉히 — sim 0.27초 기준)",
				belt.id,
				mine,
				theirs
			)
		)
	end
end
for _, exam in log.exams do
	check(exam.phase == "pass" or exam.phase == "win", string.format("띠 %d 심사/대결 %s", exam.belt, exam.phase))
end
check(Progression.isGrandMaster(final.belt), "그랜드 마스터가 못 됨")

------------------------------------------------------------------
-- 요약
------------------------------------------------------------------
table.sort(stays, function(a, b)
	return a.stay > b.stay
end)
local top = {}
for k = 1, math.min(3, #stays) do
	table.insert(top, stays[k].name .. " " .. mmss(stays[k].stay))
end
print(
	string.format(
		"\n첫 솜 %.1f초 · 5분 안 아령 %d번 · 월드 1 끝 %s · 월드 2 끝 %s · 월드 3 끝 %s · 마지막 힘 %s",
		log.firstBreak or -1,
		earlyBuys,
		mmss(worldEnds[1]),
		mmss(worldEnds[2]),
		mmss(worldEnds[3]),
		Format.number(final.power)
	)
)
print(
	string.format(
		"가장 오래 머문 물건: %s · 이웃 reward 배율 %.2f~%.2f · 아령 %d개 (노가다 평균 앞 %.0f · 가운데 %.0f · 뒤 %.0f초) · 걷기 %s",
		table.concat(top, " · "),
		minReward,
		maxReward,
		Dumbbells.COUNT,
		thirds[1],
		thirds[2],
		thirds[3],
		mmss(log.walkSeconds)
	)
)
if #failures > 0 then
	print("\n실패 " .. #failures .. "개:")
	for _, f in failures do
		print("  - " .. f)
	end
	process.exit(1)
end
print("sim_progress: 전부 통과")
process.exit(0)
