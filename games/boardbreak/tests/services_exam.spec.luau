--!nocheck
-- 승급 심사 · 시험관 대결 (진짜 ExamService + BreakService + 하네스): 시작 조건 · Hit("exam"/"duel") · 서버 판정 · 속도 제한
return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function setup()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		H.Exam = H.server("Services/ExamService")
		H.Break = H.server("Services/BreakService")
		H.World = H.server("Services/WorldService")
		H.Exam.start()
		H.Break.start()
		H.World.start()
		H.Belts = H.shared("Data/Belts")
		H.Worlds = H.shared("Data/Worlds")
		return H
	end

	local function join(H, overrides)
		local p = H.newPlayer(1)
		local session, data = H.login(p, overrides)
		H.spawn(p, H.examSpot(session.currentWorld))
		return p, session, data
	end

	local function last(H, p, name)
		local list = H.sent(p, name)
		return list[#list] and list[#list][1]
	end

	-- 초당 4번 치기 (가상 시간 0.25초씩)
	local function hitFor(H, p, kind, seconds)
		local steps = math.floor(seconds / 0.25)
		for _ = 1, steps do
			H.client(p, "Hit", kind)
			H.advance(0.25)
		end
	end

	T.suite("services_exam: 승급 심사")

	T.test(
		"시작 조건: 힘 0 이어도 시작은 됨 (사장님 결정 11번) 하지만 합격은 못 함 · 심사대 밖 · 다음 띠가 대결 띠 → 시작 안 됨 (알림)",
		function()
			local H = setup()
			local need = H.Belts.get(2).needPower
			local p, session, data = join(H, { power = 0 })
			H.client(p, "StartExam")
			T.truthy(session.exam, "힘 0 으로도 도전")
			T.falsy(H.hasNotify(p, "error", "필요해요"), "힘 부족 알림 없음")
			hitFor(H, p, "exam", 21)
			T.eq(last(H, p, "ExamState").phase, "fail", "힘 0 → 송판이 안 깨져 떨어짐")
			T.eq(data.belt, 1, "띠 그대로")
			data.power = need
			H.teleport(p, H.spawnSpot(1))
			H.advance(3)
			H.client(p, "StartExam")
			T.eq(session.exam, nil, "심사대 밖")
			data.belt = 3
			data.power = 1e60
			H.teleport(p, H.examSpot(1))
			H.advance(3)
			H.client(p, "StartExam")
			T.eq(session.exam, nil, "띠 4 는 대결로만")
			T.truthy(H.hasNotify(p, "error", "대결"))
			H.uninstall()
		end
	)

	T.test("needPower 로 초당 4번 치면 합격 → 띠 +1 · ExamState start/progress/pass · Activity", function()
		local H = setup()
		local belt = H.Belts.get(2)
		local p, session, data = join(H, { power = belt.needPower })
		H.client(p, "StartExam")
		T.truthy(session.exam, "시작")
		T.eq(p:GetAttribute("Activity"), "exam")
		T.eq(H.sent(p, "ExamState")[1][1].phase, "start")
		T.eq(H.sent(p, "ExamState")[1][1].total, 10)
		hitFor(H, p, "exam", 12)
		T.eq(data.belt, 2, "노랑 띠")
		T.eq(session.exam, nil)
		T.eq(last(H, p, "ExamState").phase, "pass")
		T.eq(p:GetAttribute("Belt"), 2)
		T.eq(p:GetAttribute("Activity"), "")
		T.eq(data.stats.examsPassed, 1)
		T.truthy(H.hasNotify(p, "success", "합격"))
		H.uninstall()
	end)

	T.test("20초가 지나면 fail (진행 틱) · 벌칙 없음 · 바로 다시 가능", function()
		local H = setup()
		local belt = H.Belts.get(2)
		local p, session, data = join(H, { power = belt.needPower })
		H.client(p, "StartExam")
		hitFor(H, p, "exam", 2) -- 조금만 침
		H.advance(20)
		T.eq(last(H, p, "ExamState").phase, "fail")
		T.eq(session.exam, nil)
		T.eq(data.belt, 1)
		T.eq(data.power, belt.needPower, "벌칙 없음")
		T.eq(data.stats.examsFailed, 1)
		H.advance(3)
		H.client(p, "StartExam")
		T.truthy(session.exam, "다시 시작")
		H.uninstall()
	end)

	T.test("심사 중 치기도 초당 5번 제한 (한꺼번에 50번 → 5번만 셈)", function()
		local H = setup()
		local belt = H.Belts.get(2)
		local p, session = join(H, { power = belt.needPower * 1e6 }) -- 한 번에 1장
		H.client(p, "StartExam")
		for _ = 1, 50 do
			H.client(p, "Hit", "exam")
		end
		T.eq(session.exam.broken, 5)
		H.uninstall()
	end)

	T.test("심사 중이 아닌데 Hit('exam') · 심사대 밖에서 치기 = 무시", function()
		local H = setup()
		local belt = H.Belts.get(2)
		local p, session, data = join(H, { power = belt.needPower * 1e6 })
		H.client(p, "Hit", "exam")
		H.client(p, "Hit", "duel")
		T.eq(#H.sent(p, "ExamState"), 0)
		T.eq(#H.sent(p, "DuelState"), 0)
		H.advance(1)
		H.client(p, "StartExam")
		H.teleport(p, H.spawnSpot(1))
		H.client(p, "Hit", "exam")
		T.eq(session.exam.broken, 0, "심사대 밖")
		T.eq(data.belt, 1)
		H.uninstall()
	end)

	T.test("심사·대결 중에는 월드 이동 안 됨", function()
		local H = setup()
		local p, session = join(H, { power = H.Belts.get(2).needPower, belt = 1, world = 1 })
		H.client(p, "StartExam")
		H.client(p, "Travel", 1)
		T.truthy(H.hasNotify(p, "error", "이동할 수 없어요"))
		T.truthy(session.exam)
		H.uninstall()
	end)

	T.suite("services_exam: 시험관 대결 (서버 판정)")

	local function duelJoin(H, belt, world, powerScale)
		local p = H.newPlayer(1)
		local need = H.Belts.get(belt + 1).needPower
		local session, data = H.login(p, { belt = belt, world = world, power = need * (powerScale or 1) })
		session.currentWorld = world
		H.spawn(p, H.duelSpot(world))
		return p, session, data
	end

	T.test("대결 띠가 아니면 · 대결장 밖이면 시작 안 됨", function()
		local H = setup()
		local p, session = duelJoin(H, 2, 1)
		H.client(p, "StartDuel")
		T.eq(session.duel, nil, "띠 3 은 심사")
		T.truthy(H.hasNotify(p, "error", "심사"))
		local _, data = H.server("Sessions").getLoaded(p)
		data.belt = 3
		H.teleport(p, H.spawnSpot(1))
		H.advance(3)
		H.client(p, "StartDuel")
		T.eq(session.duel, nil, "대결장 밖")
		H.uninstall()
	end)

	T.test("needPower 로 초당 4번 → 이김 → 띠 4 · 월드 2 열림 · DuelState win", function()
		local H = setup()
		local p, session, data = duelJoin(H, 3, 1)
		H.client(p, "StartDuel")
		T.truthy(session.duel)
		T.eq(p:GetAttribute("Activity"), "duel")
		local start = H.sent(p, "DuelState")[1][1]
		T.eq(start.phase, "start")
		T.eq(start.total, 15)
		T.eq(start.examiner, H.Worlds.get(1).examiner)
		H.advance(3) -- 카운트다운
		hitFor(H, p, "duel", 15)
		T.eq(last(H, p, "DuelState").phase, "win")
		T.eq(data.belt, 4)
		T.eq(data.world, 2, "월드 2 열림")
		T.eq(p:GetAttribute("World"), 2)
		T.eq(session.duel, nil)
		T.eq(data.stats.duelsWon, 1)
		H.uninstall()
	end)

	T.test("느리게 치면 시험관이 먼저 → 짐 (띠·월드 그대로)", function()
		local H = setup()
		local p, session, data = duelJoin(H, 3, 1)
		H.client(p, "StartDuel")
		H.advance(3)
		for _ = 1, 30 do
			H.client(p, "Hit", "duel")
			H.advance(1) -- 초당 1번
		end
		T.eq(last(H, p, "DuelState").phase, "lose")
		T.eq(data.belt, 3)
		T.eq(data.world, 1)
		T.eq(session.duel, nil)
		T.eq(data.stats.duelsLost, 1)
		H.uninstall()
	end)

	T.test(
		"힘 0 으로도 대결은 시작됨 (사장님 결정 11번) — 하지만 송판이 안 깨져 짐 · 띠·월드 그대로",
		function()
			local H = setup()
			local p, session, data = duelJoin(H, 3, 1, 0)
			H.client(p, "StartDuel")
			T.truthy(session.duel, "힘 0 으로도 도전")
			H.advance(3)
			hitFor(H, p, "duel", 30)
			T.eq(last(H, p, "DuelState").phase, "lose")
			T.eq(data.belt, 3)
			T.eq(data.world, 1, "월드 2 는 여전히 잠김")
			H.uninstall()
		end
	)

	T.test("카운트다운 중 친 것은 무시 (미리 연타해도 이득 없음)", function()
		local H = setup()
		local p, session = duelJoin(H, 3, 1, 1e9) -- 한 번에 1장
		H.client(p, "StartDuel")
		for _ = 1, 5 do
			H.client(p, "Hit", "duel")
		end
		T.eq(session.duel.mine, 0)
		H.uninstall()
	end)

	T.test("월드 3 마지막 시험관을 이기면 그랜드 마스터 (띠 12)", function()
		local H = setup()
		local p, _, data = duelJoin(H, 11, 3)
		H.client(p, "StartDuel")
		H.advance(3)
		hitFor(H, p, "duel", 15)
		T.eq(data.belt, 12)
		T.truthy(data.grandMaster)
		T.eq(p:GetAttribute("GrandMaster"), true)
		T.truthy(H.hasNotify(p, "success", "그랜드 마스터"))
		H.uninstall()
	end)

	T.test("클라가 '이겼다'고 보낼 Remote 가 없음 (클라 → 서버 Remote 목록)", function()
		local Remotes = Loader.require("ReplicatedStorage/Shared/Remotes")
		for name in Remotes.ToServer do
			local lower = string.lower(name)
			T.falsy(string.find(lower, "win") or string.find(lower, "pass") or string.find(lower, "belt"), name)
		end
		T.eq(Remotes.RateLimits.Hit.perSecond, 5)
		T.eq(Remotes.RateLimits.Train.perSecond, 5)
	end)
end
