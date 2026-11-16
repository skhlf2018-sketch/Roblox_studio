--!nocheck
--[[
	SimPlayer — 송판 깨기 "열심히 하는 플레이어" 흉내 (sim_progress 검사 · tune_numbers 숫자 만들기가 같이 씀)

	플레이어 (로벅스 없음, 힘 배수 1, 한 번에 하나만 — 들기 또는 치기):
	  물건 옆 길가 수련 매트에서 10초 들기 (0.27초마다 — 실제 버튼 0.22초보다 느린 쪽, B-2) → 들기↔치기 바꾸기 (matWalkDistance / 16 + 0.5초)
	  → 10초 치기 (0.27초마다, 그 매트 옆 물건) → 바꾸기 → 반복.
	  치기 블록을 시작할 때 돈을 가장 빨리 버는 열린 물건이 바뀌었으면 그 물건 매트로 걸어감 (매트 사이 거리 / 16,
	  다른 월드면 문 → 그 월드 스폰 → 매트).
	  살 수 있는 아령은 바로 삼 (메뉴에서). 승급 심사·대결을 볼 수 있으면 바로 봄
	  (매트 → 심사대/대결장 걸어가서 실제로 송판을 침 (ExamRules 로 판정) → 다시 매트로).
	  물건 체력은 물건마다 따로 남음 (BreakRules 처럼). 열심히 = 쉬지 않음.
	  (폰에서 두 손가락으로 들기·치기를 같이 누르면 최대 2.5배 빨라질 수 있음 (서버 한도 초당 5번씩) — 그건 흉내 내지 않음, 설계서 6장)

	SimPlayer.run(m, hooks?) → (s, log)
	  m = { Targets, Dumbbells, Belts, Worlds, Economy, Progression, ExamRules, MapLayout }
	  hooks.onStep(s, log) — 매 걸음 맨 앞 (tune_numbers 가 아직 안 정한 숫자를 그때그때 정할 때)
	  log.open[i] · log.comf[i] (3번 안에 깸) · log.buy[level] · log.belt[index] · log.worldOpen[w] · log.firstBreak · log.exams
]]

local SimPlayer = {}

SimPlayer.SIM = {
	TICK = 0.27, -- 누르고 있으면 0.22초마다 (ActionButton) — 프레임 올림·느린 손가락을 감안한 느린 쪽 0.27초 (B-2)
	TRAIN_BLOCK = 10,
	HIT_BLOCK = 10,
	SWITCH = 0.5, -- 들기 ↔ 치기 바꾸는 데 (방향 바꾸기)
	WALK_SPEED = 16, -- 서버가 WalkSpeed 를 안 바꿈 (로블록스 기본)
	DEFAULT_MAT_WALK = 4, -- MapLayout.matWalkDistance 가 없을 때
	LIMIT = 12 * 3600,
	COMFORTABLE_HITS = 3,
}

local function dist(a, b): number
	if not a or not b then
		return 0
	end
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

function SimPlayer.run(m, hooks)
	local SIM = SimPlayer.SIM
	local Targets, Economy, Progression, ExamRules, MapLayout =
		m.Targets, m.Economy, m.Progression, m.ExamRules, m.MapLayout

	local s = { t = 0, power = 0, money = 0, db = 1, belt = 1, world = 1, hp = {}, home = nil }
	local log = {
		open = {},
		comf = {},
		buy = { [1] = 0 },
		belt = {},
		worldOpen = { [1] = 0 },
		firstBreak = nil,
		exams = {},
		walkSeconds = 0,
	}

	local function matOf(target)
		if target == nil then
			return MapLayout.spawn(1)
		end
		local p = if MapLayout.matPoint then MapLayout.matPoint(target.id) else nil
		return p or MapLayout.targetPosition(target.id)
	end

	-- 들기 ↔ 치기 바꾸는 시간 (매트 가운데 → 그 물건을 칠 수 있는 자리)
	local function switchSeconds(target): number
		local d = SIM.DEFAULT_MAT_WALK
		if target and MapLayout.matWalkDistance then
			local w = MapLayout.matWalkDistance(target.id)
			if w ~= math.huge then
				d = w
			end
		end
		return d / SIM.WALK_SPEED + SIM.SWITCH
	end

	local function walk(seconds: number)
		s.t += seconds
		log.walkSeconds += seconds
	end

	local function record()
		for _, target in Targets.list do
			local i = target.index
			if target.world <= s.world then
				local damage = Economy.hitDamage(s.power, 1)
				if not log.open[i] and damage >= target.recommendPower then
					log.open[i] = s.t
				end
				if not log.comf[i] and Economy.hitsToBreak(target.hp, damage) <= SIM.COMFORTABLE_HITS then
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

	local function bestTarget()
		local best, bestRate = nil, 0
		local damage = Economy.hitDamage(s.power, 1)
		if damage <= 0 then
			return nil
		end
		for _, target in Targets.list do
			if target.world <= s.world then -- 힘 문턱 없음: 열린 월드의 물건 전부 중 돈이 가장 빨리 모이는 것
				local rate = target.reward / Economy.hitsToBreak(target.hp, damage)
				if rate >= bestRate then
					best, bestRate = target, rate
				end
			end
		end
		return best
	end

	-- 지금 매트 → 다른 물건 매트로
	local function moveHome(nextHome)
		if nextHome == nil or nextHome == s.home then
			return
		end
		local here = s.home
		if here and here.world == nextHome.world then
			walk(dist(matOf(here), matOf(nextHome)) / SIM.WALK_SPEED)
		else
			local fromWorld = if here then here.world else 1
			local toSpawn = MapLayout.spawn(nextHome.world)
			walk(dist(matOf(here), MapLayout.spawn(fromWorld)) / SIM.WALK_SPEED)
			walk(dist(toSpawn, matOf(nextHome)) / SIM.WALK_SPEED)
		end
		s.home = nextHome
	end

	-- 지금 힘으로 심사/대결에 이기나 (진짜 ExamRules 를 시간 0 부터 미리 돌려 봄 — 시간은 안 씀)
	local function willPass(okExam: boolean, damage: number): boolean
		if okExam then
			local state = ExamRules.startExam(s.belt + 1, 0)
			if not state then
				return false
			end
			local t = 0
			while not state.finished do
				t += SIM.TICK
				ExamRules.examHit(state, damage, t)
			end
			return state.phase == "pass"
		end
		local state = ExamRules.startDuel(s.belt + 1, 0)
		if not state then
			return false
		end
		local t = state.startsAt - SIM.TICK
		while not state.finished do
			t += SIM.TICK
			ExamRules.duelHit(state, damage, t)
		end
		return state.phase == "win"
	end
	local failedAt = {} -- [띠] = 지는 것으로 확인한 가장 큰 힘 (1% 더 커지면 다시 봄)

	-- 심사·대결 (힘 조건 없이 언제든 시작할 수 있지만, 똑똑한 플레이어는 이길 수 있을 때만 감
	--   → 매트 → 심사대/대결장 → 진짜 ExamRules 로 초당 4번 치기 → 매트)
	local function examOrDuel(): boolean
		local okExam = Progression.canExam(s.power, s.belt)
		local okDuel = Progression.canDuel(s.power, s.belt)
		if not okExam and not okDuel then
			return false
		end
		local next = s.belt + 1
		local damageNow = Economy.hitDamage(s.power, 1)
		if failedAt[next] and damageNow < failedAt[next] * 1.01 then
			return false
		end
		if not willPass(okExam, damageNow) then
			failedAt[next] = damageNow
			return false
		end
		local here = if s.home then s.home.world else 1
		local spot = if okExam then MapLayout.examPad(here) else MapLayout.duelArena(here)
		local oneWay = dist(matOf(s.home), spot) / SIM.WALK_SPEED + SIM.SWITCH
		walk(oneWay)
		local damage = Economy.hitDamage(s.power, 1)
		local passed = false
		if okExam then
			local state = ExamRules.startExam(s.belt + 1, s.t)
			while not state.finished do
				s.t += SIM.TICK
				ExamRules.examHit(state, damage, s.t)
			end
			table.insert(log.exams, { belt = state.belt, phase = state.phase, t = s.t })
			if state.phase == "pass" then
				s.belt = state.belt
				passed = true
			end
		else
			local state = ExamRules.startDuel(s.belt + 1, s.t)
			s.t = state.startsAt - SIM.TICK
			while not state.finished do
				s.t += SIM.TICK
				ExamRules.duelHit(state, damage, s.t)
			end
			table.insert(log.exams, { belt = state.belt, phase = state.phase, t = s.t })
			if state.phase == "win" then
				s.belt = state.belt
				s.world = Progression.worldsFromBelt(s.belt)
				log.worldOpen[state.world + 1] = s.t
				passed = true
			end
		end
		if passed then
			log.belt[s.belt] = s.t
		end
		walk(oneWay)
		return true
	end

	-- 처음: 스폰 → 첫 물건 옆 매트
	moveHome(Targets.list[1])
	local mode, left = "train", SIM.TRAIN_BLOCK
	while s.t < SIM.LIMIT do
		if hooks and hooks.onStep then
			hooks.onStep(s, log)
		end
		tryBuy()
		record()
		if Progression.isGrandMaster(s.belt) then
			break
		end
		if examOrDuel() then
			record()
			mode, left = "train", SIM.TRAIN_BLOCK
		end
		if mode == "train" then
			s.power = Economy.addPower(s.power, Economy.trainGain(s.db, 1))
			s.t += SIM.TICK
			left -= SIM.TICK
			if left <= 0 then
				moveHome(bestTarget())
				walk(switchSeconds(s.home))
				mode, left = "hit", SIM.HIT_BLOCK
			end
		else
			local target = s.home
			local damage = Economy.hitDamage(s.power, 1)
			if target and damage > 0 and target.world <= s.world then
				local hp = (s.hp[target.id] or target.hp) - damage
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
				walk(switchSeconds(s.home))
				mode, left = "train", SIM.TRAIN_BLOCK
			end
		end
	end
	return s, log
end

return SimPlayer
