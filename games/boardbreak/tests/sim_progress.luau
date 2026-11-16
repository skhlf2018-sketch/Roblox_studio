--!nocheck
--[[
	sim_progress — 송판 깨기 "열심히 하는 플레이어" 흉내 (설계서 6장 숫자 규칙 검사). 저장소 루트에서:
	  lune run games/boardbreak/tests/sim_progress.luau          (자세히: ... sim_progress.luau -v)
	진짜 숫자 표(Data/Targets · Dumbbells · Belts · Worlds)와 진짜 규칙(Economy · Progression · ExamRules)을 씀.

	플레이어 (로벅스 없음, 힘 배수 1):
	  10초 아령 들기 (초당 4번) → 2초 걷기 → 10초 치기 (초당 4번, 돈을 가장 빨리 버는 열린 물건) → 2초 걷기 → 반복.
	  살 수 있는 아령은 바로 삼. 승급 심사·대결을 볼 수 있으면 바로 봄 (2초 걷기 + 실제로 송판을 침, ExamRules 로 판정).
	  물건 체력은 물건마다 따로 남음 (BreakRules 처럼). 열심히 = 쉬지 않음.
	검사 (설계서 6장):
	  첫 솜 30초 안 · 처음 5분 안에 아령 2번 이상 · 물건 N 편해짐(3번 안에 깸) → 물건 N+1 열림(minPower) 1~4분 (N = 1~40)
	  · 월드 1 끝 40분 · 월드 2 끝 2시간 30분 · 월드 3 끝 6시간 (±30%, 처음부터 잰 시각) · 막 열렸을 때 15~30번
	  · 심사 송판 (needPower 로 20초 안) · 대결 (needPower 로 시험관보다 먼저)
	실패가 있으면 종료 코드 1.
]]

local process = require("@lune/process")
local Loader = require("./Loader")

Loader.get("ReplicatedStorage/Shared/Data/Config")
local Targets = Loader.require("ReplicatedStorage/Shared/Data/Targets")
local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")
local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")
local Worlds = Loader.require("ReplicatedStorage/Shared/Data/Worlds")
local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
local Progression = Loader.require("ReplicatedStorage/Shared/Progression")
local ExamRules = Loader.require("ReplicatedStorage/Shared/ExamRules")
local Format = Loader.require("ReplicatedStorage/Shared/Format")

local VERBOSE = false
for _, a in process.args do
	if a == "-v" then
		VERBOSE = true
	end
end

local SIM = {
	TICK = 0.25, -- 초당 4번
	TRAIN_BLOCK = 10,
	WALK = 2,
	HIT_BLOCK = 10,
	LIMIT = 40 * 3600,
}

-- 설계서 6장 기준 (분)
local RULES = {
	firstBreakSeconds = 30,
	earlyBuys = 2,
	earlyBuySeconds = 300,
	gapMin = 60,
	gapMax = 240,
	worldEnd = { 40, 150, 360 }, -- 분, 처음부터
	tolerance = 0.3,
	hitsAtOpen = { 15, 30 },
	comfortableHits = 3,
}

local function simulate()
	local s = { t = 0, power = 0, money = 0, db = 1, belt = 1, world = 1, hp = {} }
	local log = { open = {}, comf = {}, buy = {}, belt = {}, worldOpen = { [1] = 0 }, firstBreak = nil, exams = {} }

	local function record()
		for _, target in Targets.list do
			local i = target.index
			if target.world <= s.world then
				if not log.open[i] and Economy.hitDamage(s.power, 1) >= target.minPower then
					log.open[i] = s.t
				end
				if
					not log.comf[i]
					and Economy.hitsToBreak(target.hp, Economy.hitDamage(s.power, 1)) <= RULES.comfortableHits
				then
					log.comf[i] = s.t
				end
			end
		end
	end

	local function tryBuy()
		while true do
			local ok, _, nextDumbbell = Progression.canBuyDumbbell(s.db, s.money)
			if not ok or not nextDumbbell then
				return
			end
			s.money -= nextDumbbell.price
			s.db = nextDumbbell.level
			log.buy[s.db] = s.t
		end
	end

	-- 심사·대결을 진짜 ExamRules 로 (2초 걷기 + 초당 4번 치기)
	local function examOrDuel(): boolean
		local okExam = Progression.canExam(s.power, s.belt)
		local okDuel = Progression.canDuel(s.power, s.belt)
		if not okExam and not okDuel then
			return false
		end
		s.t += SIM.WALK
		local damage = Economy.hitDamage(s.power, 1)
		if okExam then
			local state = ExamRules.startExam(s.belt + 1, s.t)
			while not state.finished do
				s.t += SIM.TICK
				ExamRules.examHit(state, damage, s.t)
			end
			table.insert(log.exams, { belt = state.belt, phase = state.phase, t = s.t })
			if state.phase ~= "pass" then
				return true -- 떨어짐 (다음에 다시)
			end
			s.belt = state.belt
		else
			local state = ExamRules.startDuel(s.belt + 1, s.t)
			s.t = state.startsAt - SIM.TICK
			while not state.finished do
				s.t += SIM.TICK
				ExamRules.duelHit(state, damage, s.t)
			end
			table.insert(log.exams, { belt = state.belt, phase = state.phase, t = s.t })
			if state.phase ~= "win" then
				return true
			end
			s.belt = state.belt
			s.world = Progression.worldsFromBelt(s.belt)
			log.worldOpen[state.world + 1] = s.t
		end
		log.belt[s.belt] = s.t
		return true
	end

	local function bestTarget()
		local best, bestRate = nil, 0
		local damage = Economy.hitDamage(s.power, 1)
		for _, target in Targets.list do
			if target.world <= s.world and damage >= target.minPower then
				local rate = target.reward / Economy.hitsToBreak(target.hp, damage)
				if rate >= bestRate then
					best, bestRate = target, rate
				end
			end
		end
		return best
	end

	local mode, left = "train", SIM.TRAIN_BLOCK
	while s.t < SIM.LIMIT do
		tryBuy()
		record()
		if Progression.isGrandMaster(s.belt) then
			break
		end
		if examOrDuel() then
			record()
			mode, left = "walk2", SIM.WALK
		end
		if mode == "train" then
			s.power = Economy.addPower(s.power, Economy.trainGain(s.db, 1))
			s.t += SIM.TICK
			left -= SIM.TICK
			if left <= 0 then
				mode, left = "walk1", SIM.WALK
			end
		elseif mode == "walk1" or mode == "walk2" then
			s.t += SIM.TICK
			left -= SIM.TICK
			if left <= 0 then
				if mode == "walk1" then
					mode, left = "hit", SIM.HIT_BLOCK
				else
					mode, left = "train", SIM.TRAIN_BLOCK
				end
			end
		else
			local target = bestTarget()
			if target then
				local hp = (s.hp[target.id] or target.hp) - Economy.hitDamage(s.power, 1)
				if hp <= 0 then
					s.hp[target.id] = nil
					s.money = Economy.addMoney(s.money, Economy.breakReward(target.reward, s.belt, false))
					log.firstBreak = log.firstBreak or s.t
				else
					s.hp[target.id] = hp
				end
			else
				s.power = Economy.addPower(s.power, Economy.trainGain(s.db, 1)) -- 칠 것이 없으면 계속 듦
			end
			s.t += SIM.TICK
			left -= SIM.TICK
			if left <= 0 then
				mode, left = "walk2", SIM.WALK
			end
		end
	end
	return s, log
end

local function mmss(seconds: number?): string
	if not seconds then
		return "-"
	end
	return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local failures = {}
local function check(ok: boolean, text: string)
	if not ok then
		table.insert(failures, text)
	end
end

local final, log = simulate()

print(
	"== 송판 깨기 진행 시뮬레이션 (열심히 하는 플레이어: 들기 초당 4번 · 치기 초당 4번 · 로벅스 없음)"
)
print(
	"   #  물건          열림     편해짐   머문 시간  →다음 열림   minPower   hp        처음 타격"
)
for _, target in Targets.list do
	local i = target.index
	local hitsAtOpen = Economy.hitsToBreak(target.hp, target.minPower)
	check(
		hitsAtOpen >= RULES.hitsAtOpen[1] and hitsAtOpen <= RULES.hitsAtOpen[2],
		string.format("%s 막 열렸을 때 %d번 (15~30)", target.id, hitsAtOpen)
	)
	local gap = nil
	if i < Targets.COUNT and log.comf[i] and log.open[i + 1] then
		gap = log.open[i + 1] - log.comf[i]
	end
	if i < Targets.COUNT then
		check(
			gap ~= nil and gap >= RULES.gapMin and gap <= RULES.gapMax,
			string.format("%s 편해짐 → %s 열림 %s초 (60~240)", target.id, Targets.list[i + 1].id, tostring(gap))
		)
	end
	check(log.open[i] ~= nil, target.id .. " 이 열리지 않음")
	if VERBOSE or (gap and (gap < RULES.gapMin or gap > RULES.gapMax)) then
		local stay = if log.open[i] and log.comf[i] then log.comf[i] - log.open[i] else nil
		print(
			string.format(
				"  %2d  %-12s %8s %8s %8s %8s   %-9s  %-9s %d",
				i,
				target.id,
				mmss(log.open[i]),
				mmss(log.comf[i]),
				mmss(stay),
				if gap then string.format("%ds", math.floor(gap)) else "-",
				Format.number(target.minPower),
				Format.number(target.hp),
				hitsAtOpen
			)
		)
	end
end

if VERBOSE then
	for level = 2, Dumbbells.COUNT do
		local d = Dumbbells.list[level]
		print(
			string.format(
				"  아령 %2d %-10s 힘/번 %-8s 값 %-8s 산 시각 %s",
				level,
				d.name,
				Format.number(d.powerPerRep),
				Format.number(d.price),
				mmss(log.buy[level])
			)
		)
	end
	for index = 2, Belts.COUNT do
		local b = Belts.list[index]
		print(
			string.format(
				"  띠 %2d %-14s need %-8s ×%s  받은 시각 %s",
				index,
				b.name,
				Format.number(b.needPower),
				tostring(b.moneyMultiplier),
				mmss(log.belt[index])
			)
		)
	end
end

-- 처음
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

-- 월드 끝 (대결에서 이긴 시각: 월드 1·2 = 다음 월드 열림, 월드 3 = 그랜드 마스터)
local worldEnds = { log.worldOpen[2], log.worldOpen[3], log.belt[Belts.COUNT] }
for w = 1, 3 do
	local goal = RULES.worldEnd[w] * 60
	local at = worldEnds[w]
	check(
		at ~= nil and at >= goal * (1 - RULES.tolerance) and at <= goal * (1 + RULES.tolerance),
		string.format("월드 %d 끝 %s (목표 %s ±30%%)", w, mmss(at), mmss(goal))
	)
end

-- 심사·대결 (needPower 로)
for _, belt in Belts.list do
	if belt.index > 1 and not belt.duel then
		local seconds = Config.EXAM_BOARDS * Economy.hitsToBreak(belt.examBoardHp, belt.needPower) * SIM.TICK
		check(seconds < Config.EXAM_SECONDS, string.format("%s 심사 %.1f초 (20초 안)", belt.id, seconds))
	elseif belt.duel then
		local world = Worlds.get(belt.world)
		local mine = Config.DUEL_BOARDS * Economy.hitsToBreak(belt.duelBoardHp, belt.needPower) * SIM.TICK
		local theirs = Config.DUEL_BOARDS * world.examinerSecondsPerBoard
		check(
			mine * 1.5 < theirs,
			string.format("%s 대결 내 %.1f초 vs 시험관 %.1f초 (넉넉히)", belt.id, mine, theirs)
		)
	end
end
for _, exam in log.exams do
	check(exam.phase == "pass" or exam.phase == "win", string.format("띠 %d 심사/대결 %s", exam.belt, exam.phase))
end

-- 가장 오래 머문 물건 (보고용)
local longest, longestId = 0, ""
for _, target in Targets.list do
	local i = target.index
	if i < Targets.COUNT and log.open[i] and log.comf[i] and log.comf[i] - log.open[i] > longest then
		longest, longestId = log.comf[i] - log.open[i], target.id
	end
end

print(
	string.format(
		"\n첫 솜 %.1f초 · 5분 안 아령 %d번 · 월드 1 끝 %s · 월드 2 끝 %s · 월드 3 끝 %s · 마지막 힘 %s · 가장 오래 머문 물건 %s %s",
		log.firstBreak or -1,
		earlyBuys,
		mmss(worldEnds[1]),
		mmss(worldEnds[2]),
		mmss(worldEnds[3]),
		Format.number(final.power),
		longestId,
		mmss(longest)
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
