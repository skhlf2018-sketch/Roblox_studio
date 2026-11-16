--!strict
--[[
	ExamService — 승급 심사 (StartExam) · 시험관 대결 (StartDuel) — 서버 판정 (설계서 4장, 상태 기계는 shared/ExamRules)

	시작:
	  StartExam()  다음 띠가 심사 띠 · (힘 조건 없음 — 약하면 떨어질 뿐) · 심사대 MapLayout.examPad(지금 월드) 에서 EXAM_RADIUS 안 · 심사·대결 중 아님
	  StartDuel()  다음 띠가 대결 띠(4·8·12) · (힘 조건 없음 — 약하면 질 뿐) · 대결장 MapLayout.duelArena(지금 월드) 에서 DUEL_RADIUS 안
	치기: 클라는 일반 치기와 같은 Remote 로 Hit("exam") / Hit("duel") (BreakService 가 여기로 넘김 — 같은 속도 제한 초당 5번).
	  피해 = 힘 × PowerBoost (Economy.hitDamage). 심사대·대결장 근처에서만.
	진행 틱 (EXAM_TICK_SECONDS): 남은 시간·시험관 진행을 ExamState / DuelState "progress" 로, 끝나면 "pass"|"fail" / "win"|"lose".
	끝:
	  합격 → 띠 +1 · 대결 승리 → 띠 +1 · 다음 월드 열림 (Progression.worldsFromBelt) · 띠 12 = 그랜드 마스터
	  떨어지거나 지면 벌칙 없음 (바로 다시 가능). 이기고 지는 것은 서버만 정함 (클라가 "이겼다"고 보내는 Remote 없음).
	Attr Activity = "exam" | "duel" | "" · Snapshot "progress" (띠·월드가 바뀌면)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Belts = require(Shared.Data.Belts)
local Worlds = require(Shared.Data.Worlds)
local MapLayout = require(Shared.Data.MapLayout)
local Economy = require(Shared.Economy)
local ExamRules = require(Shared.ExamRules)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Attributes = require(Server.Attributes)
local Character = require(Server.Util.Character)

local ExamService = {}

-- 살아 있는 캐릭터가 spot 에서 radius 안, 그리고 수련 매트(도장·길가) 위가 아님
--   (죽은 캐릭터는 시작·치기 안 됨 — A-1 · 대결장 옆 도장 매트 가장자리가 대결장 가운데에서 20 스터드라
--    반경만으로는 못 막음 → 매트 위면 따로 막음 — A-2)
local function near(player: Player, spot: { x: number, y: number, z: number }?, radius: number, world: number): boolean
	local root = Character.getRoot(player)
	if not root or not spot or not Character.isAlive(player) then
		return false
	end
	local p = root.Position
	local dx, dz = p.X - spot.x, p.Z - spot.z
	if dx * dx + dz * dz > radius * radius or math.abs(p.Y - spot.y) > radius then
		return false
	end
	return not MapLayout.isOnTrainMat(p, world)
end

local function examSpot(session: Sessions.Session): { x: number, y: number, z: number }
	return MapLayout.examPad(session.currentWorld)
end

local function duelSpot(session: Sessions.Session): { x: number, y: number, z: number }
	return MapLayout.duelArena(session.currentWorld)
end

local function examState(state: ExamRules.Exam, now: number): Types.ExamState
	return {
		phase = state.phase :: any,
		broken = state.broken,
		total = state.total,
		secondsLeft = ExamRules.secondsLeft(state, now),
		belt = state.belt,
		boardHp = state.boardHp,
		boardHpMax = state.boardHpMax,
	}
end

local function duelState(state: ExamRules.Duel, now: number): Types.DuelState
	return {
		phase = state.phase :: any,
		mine = state.mine,
		theirs = state.theirs,
		total = state.total,
		world = state.world,
		secondsLeft = ExamRules.secondsLeft(state, now),
		boardHp = state.boardHp,
		boardHpMax = state.boardHpMax,
		examiner = state.examiner,
	}
end

-- 시작할 수 없는 이유 (힘은 이유가 아님 — 사장님 결정 11번: 힘이 약해도 도전은 됨)
local function reasonText(reason: string?): string
	if reason == "max" then
		return "이미 마지막 띠예요! 그랜드 마스터!"
	elseif reason == "duel" then
		return "다음 띠는 시험관과 대결해서 받아요. 대결장으로 가요!"
	elseif reason == "exam" then
		return "다음 띠는 승급 심사로 받아요. 심사대로 가요!"
	end
	return "지금은 할 수 없어요"
end

local function busy(session: Sessions.Session): boolean
	return Sessions.activity(session) ~= ""
end

------------------------------------------------------------------
-- 끝내기
------------------------------------------------------------------

local function finishExam(player: Player, session: Sessions.Session, data: Types.PlayerData, now: number)
	local state = session.exam
	if not state then
		return
	end
	session.exam = nil
	Net.fire(player, Remotes.ToClient.ExamState, examState(state, now))
	local belt = Belts.get(state.belt)
	if state.phase == "pass" and belt and data.belt == state.belt - 1 then
		data.belt = state.belt
		data.stats.examsPassed += 1
		Net.notify(
			player,
			"success",
			string.format("합격! %s 을 받았어요! (돈 ×%s)", belt.name, tostring(belt.moneyMultiplier))
		)
		Snapshot.section(player, "progress")
	else
		data.stats.examsFailed += 1
		Net.notify(player, "info", "아쉬워요! 힘을 더 길러서 다시 도전해요.")
	end
	Attributes.sync(player)
end

local function finishDuel(player: Player, session: Sessions.Session, data: Types.PlayerData, now: number)
	local state = session.duel
	if not state then
		return
	end
	session.duel = nil
	Net.fire(player, Remotes.ToClient.DuelState, duelState(state, now))
	local belt = Belts.get(state.belt)
	if state.phase == "win" and belt and data.belt == state.belt - 1 then
		data.belt = state.belt
		data.world = math.max(data.world, Progression.worldsFromBelt(data.belt))
		data.stats.duelsWon += 1
		if Progression.isGrandMaster(data.belt) then
			data.grandMaster = true
			Net.notify(
				player,
				"success",
				"그랜드 마스터! 모든 시험관을 이겼어요! (계속 깰 수 있어요)"
			)
		else
			local nextWorld = Worlds.get(data.world)
			Net.notify(
				player,
				"success",
				string.format(
					"%s 을 이겼어요! %s · %s 이 열렸어요!",
					state.examiner,
					belt.name,
					if nextWorld then nextWorld.name else "다음 월드"
				)
			)
		end
		Snapshot.section(player, "progress")
	else
		data.stats.duelsLost += 1
		Net.notify(player, "info", "시험관이 먼저 다 깼어요. 힘을 더 길러서 다시 도전해요!")
	end
	Attributes.sync(player)
end

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------

-- 시작했으면 true
function ExamService.startExam(player: Player, now: number?): boolean
	local session, data = Sessions.getLoaded(player)
	if not session or not data or busy(session) then
		return false
	end
	local ok, reason, nextBelt = Progression.canExam(data.power, data.belt)
	if not ok or not nextBelt then
		Net.notify(player, "error", reasonText(reason))
		return false
	end
	if not near(player, examSpot(session), Config.EXAM_RADIUS, session.currentWorld) then
		Net.notify(player, "error", "심사대 위에서 시작해요!")
		return false
	end
	local t = now or os.clock()
	local state = ExamRules.startExam(nextBelt.index, t)
	if not state then
		return false
	end
	session.exam = state
	Attributes.setActivity(player)
	Net.fire(player, Remotes.ToClient.ExamState, examState(state, t))
	return true
end

function ExamService.startDuel(player: Player, now: number?): boolean
	local session, data = Sessions.getLoaded(player)
	if not session or not data or busy(session) then
		return false
	end
	local ok, reason, nextBelt = Progression.canDuel(data.power, data.belt)
	if not ok or not nextBelt then
		Net.notify(player, "error", reasonText(reason))
		return false
	end
	if not near(player, duelSpot(session), Config.DUEL_RADIUS, session.currentWorld) then
		Net.notify(player, "error", "대결장 안에서 시작해요!")
		return false
	end
	local t = now or os.clock()
	local state = ExamRules.startDuel(nextBelt.index, t)
	if not state then
		return false
	end
	session.duel = state
	Attributes.setActivity(player)
	Net.fire(player, Remotes.ToClient.DuelState, duelState(state, t))
	return true
end

------------------------------------------------------------------
-- 치기 (BreakService 가 Hit("exam") / Hit("duel") 을 넘김)
------------------------------------------------------------------

function ExamService.hit(player: Player, kind: string, now: number?): boolean
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return false
	end
	local t = now or os.clock()
	local damage = Economy.hitDamage(data.power, data.powerBoost)
	if kind == Remotes.EXAM_TARGET then
		local state = session.exam
		if
			not state
			or state.finished
			or not near(player, examSpot(session), Config.EXAM_RADIUS, session.currentWorld)
		then
			return false
		end
		data.stats.hits += 1
		local changed = ExamRules.examHit(state, damage, t)
		if state.finished then
			finishExam(player, session, data, t)
		elseif changed then
			Net.fire(player, Remotes.ToClient.ExamState, examState(state, t))
		end
		return changed
	elseif kind == Remotes.DUEL_TARGET then
		local state = session.duel
		if
			not state
			or state.finished
			or not near(player, duelSpot(session), Config.DUEL_RADIUS, session.currentWorld)
		then
			return false
		end
		data.stats.hits += 1
		local changed = ExamRules.duelHit(state, damage, t)
		if state.finished then
			finishDuel(player, session, data, t)
		elseif changed then
			Net.fire(player, Remotes.ToClient.DuelState, duelState(state, t))
		end
		return changed
	end
	return false
end

------------------------------------------------------------------
-- 진행 틱
------------------------------------------------------------------

function ExamService.tick(now: number?)
	local t = now or os.clock()
	for player, session in Sessions.all() do
		local data = session.data
		if session.loaded and data then
			local exam = session.exam
			if exam then
				ExamRules.examTick(exam, t)
				if exam.finished then
					finishExam(player, session, data, t)
				else
					Net.fire(player, Remotes.ToClient.ExamState, examState(exam, t))
				end
			end
			local duel = session.duel
			if duel then
				ExamRules.duelTick(duel, t)
				if duel.finished then
					finishDuel(player, session, data, t)
				else
					Net.fire(player, Remotes.ToClient.DuelState, duelState(duel, t))
				end
			end
		end
	end
end

-- 심사·대결을 그만둠 (월드 이동·개발 명령·나감). 보내는 것 없음
function ExamService.cancel(player: Player)
	local session = Sessions.get(player)
	if session then
		session.exam = nil
		session.duel = nil
		Attributes.setActivity(player)
	end
end

function ExamService.start()
	Net.on(Remotes.ToServer.StartExam, function(player: Player)
		ExamService.startExam(player)
	end)
	Net.on(Remotes.ToServer.StartDuel, function(player: Player)
		ExamService.startDuel(player)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.EXAM_TICK_SECONDS)
			local ok, err = pcall(function(): ...any
				ExamService.tick()
				return nil
			end)
			if not ok then
				warn("[ExamService] 틱 오류: " .. tostring(err))
			end
		end
	end)
end

return ExamService
