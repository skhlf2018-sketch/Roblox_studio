--!strict
--[[
	ExamRules — 승급 심사 · 시험관 대결 상태 기계 (순수 로직, Lune 테스트 대상). 설계서 4장. 시각(now)은 밖에서 넣음.

	승급 심사 (심사 띠: 흰 띠·대결 띠를 뺀 나머지 — 지금 2~6 / 8~13 / 15~21):
	  startExam(belt, now) → { phase "start", total 10, endsAt = now + 20초, boardHp = Belts.examBoardHp }
	  examHit(state, damage, now)  송판 1장 체력을 깎음 → 0 이하면 깬 수 +1, 다음 송판 가득 (넘친 피해는 버림 — 한 번에 1장).
	                               10장 다 깨면 "pass". 시간이 지난 뒤 친 것은 "fail" (치기 전에 시간 확인)
	  examTick(state, now)         시간이 다 됐는데 덜 깼으면 "fail"
	시험관 대결 (각 월드 마지막 띠 Belts.duelOf(w): 지금 7 · 14 · 22):
	  startDuel(world, belt, now) → { phase "start", total 15, startsAt = now + 카운트다운, endsAt = startsAt + DUEL_MAX_SECONDS }
	  시험관은 startsAt 부터 examinerSecondsPerBoard 초마다 1장 (플레이어 힘과 상관없음) → theirsAt(state, now)
	  duelHit(state, damage, now)  카운트다운 중이면 무시. 먼저 시험관 진행을 now 까지 반영 → 시험관이 다 깼으면 "lose".
	                               내 송판을 깎고 15장 다 깨면 "win" (같은 순간이면 시험관 승 — 먼저 다 깨야 이김)
	  duelTick(state, now)         시험관 진행 반영 · 시험관이 다 깼거나 시간 초과면 "lose"
	서버(ExamService)가 판정. 클라가 "이겼다"고 보내는 Remote 는 없음.
	phase: 심사 "start" → "progress" → "pass" | "fail" · 대결 "start" → "progress" → "win" | "lose". finished = 끝남
]]

local Config = require(script.Parent.Data.Config)
local Belts = require(script.Parent.Data.Belts)
local Worlds = require(script.Parent.Data.Worlds)
local Economy = require(script.Parent.Economy)

local ExamRules = {}

export type Exam = {
	kind: "exam",
	belt: number, -- 합격하면 이 띠
	phase: string,
	total: number,
	broken: number,
	boardHp: number,
	boardHpMax: number,
	startedAt: number,
	endsAt: number,
	finished: boolean,
}

export type Duel = {
	kind: "duel",
	belt: number, -- 이기면 이 띠
	world: number, -- 시험관의 월드
	phase: string,
	total: number,
	mine: number,
	theirs: number,
	boardHp: number,
	boardHpMax: number,
	startsAt: number, -- 카운트다운이 끝나는 시각 (이때부터 치기·시험관 시작)
	endsAt: number,
	secondsPerBoard: number,
	examiner: string,
	finished: boolean,
}

local function validNow(now: number): number
	return if type(now) == "number" and now == now then now else 0
end

------------------------------------------------------------------
-- 승급 심사
------------------------------------------------------------------

-- 심사 띠 하나 (대결 띠·첫 띠·없는 띠면 nil)
function ExamRules.startExam(belt: number, now: number): Exam?
	local b = Belts.get(belt)
	if not b or b.duel or b.examBoardHp <= 0 then
		return nil
	end
	local t = validNow(now)
	return {
		kind = "exam",
		belt = b.index,
		phase = "start",
		total = Config.EXAM_BOARDS,
		broken = 0,
		boardHp = b.examBoardHp,
		boardHpMax = b.examBoardHp,
		startedAt = t,
		endsAt = t + Config.EXAM_SECONDS,
		finished = false,
	}
end

function ExamRules.secondsLeft(state: Exam | Duel, now: number): number
	return math.max(0, state.endsAt - validNow(now))
end

local function finishExam(state: Exam, phase: string)
	state.phase = phase
	state.finished = true
end

-- 시간 확인 (끝났으면 "fail"). 바뀌었으면 true
function ExamRules.examTick(state: Exam, now: number): boolean
	if state.finished then
		return false
	end
	if validNow(now) >= state.endsAt then
		finishExam(state, "fail")
		return true
	end
	return false
end

-- 한 번 치기. 깬 송판이 늘었으면 true 를 두 번째로 돌려줌: (바뀜, 송판 깸)
function ExamRules.examHit(state: Exam, damage: number, now: number): (boolean, boolean)
	if state.finished then
		return false, false
	end
	if ExamRules.examTick(state, now) then
		return true, false
	end
	local d = Economy.clampPower(damage)
	if d <= 0 then
		return false, false
	end
	state.phase = "progress"
	local left = state.boardHp - d
	if left <= 0 then
		state.broken += 1
		state.boardHp = state.boardHpMax
		if state.broken >= state.total then
			finishExam(state, "pass")
		end
		return true, true
	end
	state.boardHp = left
	return true, false
end

------------------------------------------------------------------
-- 시험관 대결
------------------------------------------------------------------

-- belt = 대결 띠 (각 월드 마지막 띠). 시험관은 그 띠의 월드. 대결 띠가 아니면 nil
function ExamRules.startDuel(belt: number, now: number): Duel?
	local b = Belts.get(belt)
	if not b or not b.duel then
		return nil
	end
	local world = Worlds.get(b.world)
	if not world then
		return nil
	end
	local t = validNow(now)
	local startsAt = t + Config.DUEL_COUNTDOWN_SECONDS
	return {
		kind = "duel",
		belt = b.index,
		world = world.index,
		phase = "start",
		total = Config.DUEL_BOARDS,
		mine = 0,
		theirs = 0,
		boardHp = world.duelBoardHp,
		boardHpMax = world.duelBoardHp,
		startsAt = startsAt,
		endsAt = startsAt + Config.DUEL_MAX_SECONDS,
		secondsPerBoard = world.examinerSecondsPerBoard,
		examiner = world.examiner,
		finished = false,
	}
end

-- 시험관이 now 까지 깬 송판 수
function ExamRules.theirsAt(state: Duel, now: number): number
	local elapsed = validNow(now) - state.startsAt
	if elapsed <= 0 then
		return 0
	end
	return math.min(state.total, math.floor(elapsed / state.secondsPerBoard + 1e-9))
end

-- 시험관이 마지막 송판을 깨는 시각
function ExamRules.examinerFinishAt(state: Duel): number
	return state.startsAt + state.total * state.secondsPerBoard
end

local function finishDuel(state: Duel, phase: string)
	state.phase = phase
	state.finished = true
end

-- 시험관 진행 · 시간 확인. 바뀌었으면 true
function ExamRules.duelTick(state: Duel, now: number): boolean
	if state.finished then
		return false
	end
	local t = validNow(now)
	local before = state.theirs
	state.theirs = math.max(state.theirs, ExamRules.theirsAt(state, t))
	if state.theirs >= state.total or t >= state.endsAt then
		finishDuel(state, "lose")
		return true
	end
	if t >= state.startsAt and state.phase == "start" then
		state.phase = "progress"
		return true
	end
	return state.theirs ~= before
end

-- 한 번 치기: (바뀜, 송판 깸)
function ExamRules.duelHit(state: Duel, damage: number, now: number): (boolean, boolean)
	if state.finished then
		return false, false
	end
	local t = validNow(now)
	if t < state.startsAt then
		return false, false -- 카운트다운 중
	end
	local changed = ExamRules.duelTick(state, t)
	if state.finished then
		return true, false
	end
	local d = Economy.clampPower(damage)
	if d <= 0 then
		return changed, false
	end
	state.phase = "progress"
	local left = state.boardHp - d
	if left <= 0 then
		state.mine += 1
		state.boardHp = state.boardHpMax
		if state.mine >= state.total then
			finishDuel(state, "win")
		end
		return true, true
	end
	state.boardHp = left
	return true, false
end

return ExamRules
