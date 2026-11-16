--!nocheck
-- ExamRules: 승급 심사 (20초 안 10장) · 시험관 대결 (15장, 시험관 정해진 속도) 상태 기계
return function(T, Loader)
	local ExamRules = Loader.require("ReplicatedStorage/Shared/ExamRules")
	local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")
	local Worlds = Loader.require("ReplicatedStorage/Shared/Data/Worlds")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")

	T.suite("exam_rules: 승급 심사")

	T.test("심사 띠만 시작 (1 · 4 · 8 · 12 · 13 · NaN 은 nil)", function()
		for _, b in { 1, 4, 8, 12, 13, 0, 0 / 0 } do
			T.eq(ExamRules.startExam(b, 0), nil, "띠 " .. tostring(b))
		end
		local s = ExamRules.startExam(2, 100)
		T.eq(s.phase, "start")
		T.eq(s.total, 10)
		T.eq(s.endsAt, 120)
		T.eq(s.boardHp, Belts.get(2).examBoardHp)
	end)

	T.test("needPower 로 초당 4번 치면 20초 안에 합격", function()
		local belt = Belts.get(3)
		local s = ExamRules.startExam(3, 0)
		local t = 0
		while not s.finished do
			t += 0.25
			ExamRules.examHit(s, belt.needPower, t)
		end
		T.eq(s.phase, "pass")
		T.eq(s.broken, 10)
		T.truthy(t <= 10.01, "10초 안 (" .. t .. ")")
	end)

	T.test("한 번에 송판 1장만 (넘친 피해는 다음 송판에 안 감)", function()
		local s = ExamRules.startExam(2, 0)
		local changed, brokeBoard = ExamRules.examHit(s, 1e50, 1)
		T.truthy(changed and brokeBoard)
		T.eq(s.broken, 1)
		T.eq(s.boardHp, s.boardHpMax)
	end)

	T.test("시간이 다 되면 fail (틱으로도 · 늦게 친 것으로도)", function()
		local a = ExamRules.startExam(2, 0)
		T.falsy(ExamRules.examTick(a, 19.9), "아직")
		T.truthy(ExamRules.examTick(a, 20), "끝")
		T.eq(a.phase, "fail")
		local b = ExamRules.startExam(2, 0)
		ExamRules.examHit(b, 1e50, 25)
		T.eq(b.phase, "fail", "시간 지나서 친 것은 안 셈")
		T.eq(b.broken, 0)
		-- 끝난 뒤에는 아무것도 안 바뀜
		local changed = ExamRules.examHit(a, 1e50, 21)
		T.falsy(changed)
	end)

	T.test("피해 0 · NaN 은 안 셈", function()
		local s = ExamRules.startExam(2, 0)
		ExamRules.examHit(s, 0, 1)
		ExamRules.examHit(s, 0 / 0, 1)
		T.eq(s.boardHp, s.boardHpMax)
		T.eq(s.phase, "start")
	end)

	T.suite("exam_rules: 시험관 대결")

	T.test("대결 띠만 (4 · 8 · 12), 시험관 = 그 띠의 월드", function()
		T.eq(ExamRules.startDuel(3, 0), nil)
		T.eq(ExamRules.startDuel(13, 0), nil)
		for w = 1, 3 do
			local d = ExamRules.startDuel(w * 4, 10)
			T.eq(d.world, w)
			T.eq(d.examiner, Worlds.get(w).examiner)
			T.eq(d.secondsPerBoard, Worlds.get(w).examinerSecondsPerBoard)
			T.eq(d.startsAt, 10 + Config.DUEL_COUNTDOWN_SECONDS)
			T.eq(d.total, 15)
		end
	end)

	T.test("카운트다운 중 친 것은 무시 · 시험관도 그 뒤에 시작", function()
		local d = ExamRules.startDuel(4, 0)
		local changed = ExamRules.duelHit(d, 1e50, 1)
		T.falsy(changed)
		T.eq(d.mine, 0)
		T.eq(ExamRules.theirsAt(d, 2.9), 0)
		T.eq(ExamRules.theirsAt(d, d.startsAt + d.secondsPerBoard), 1)
	end)

	T.test("needPower 로 초당 4번이면 시험관보다 먼저 15장 → win", function()
		local belt = Belts.get(4)
		local d = ExamRules.startDuel(4, 0)
		local t = d.startsAt
		while not d.finished do
			ExamRules.duelHit(d, belt.needPower, t)
			t += 0.25
		end
		T.eq(d.phase, "win")
		T.eq(d.mine, 15)
		T.truthy(d.theirs < 15, "시험관은 덜 깸 " .. d.theirs)
	end)

	T.test("느리면 시험관이 먼저 → lose (같은 순간이면 시험관 승)", function()
		local d = ExamRules.startDuel(8, 0)
		local finish = ExamRules.examinerFinishAt(d)
		T.truthy(ExamRules.duelTick(d, finish - 0.01) or true)
		T.falsy(d.finished, "아직")
		ExamRules.duelTick(d, finish)
		T.eq(d.phase, "lose")
		-- 같은 순간에 마지막 송판: 시험관 승
		local e = ExamRules.startDuel(4, 0)
		e.mine = 14
		e.boardHp = 1
		ExamRules.duelHit(e, 1e50, ExamRules.examinerFinishAt(e))
		T.eq(e.phase, "lose")
	end)

	T.test("시간 초과 lose · 끝난 뒤 치기 무시", function()
		local d = ExamRules.startDuel(12, 0)
		d.secondsPerBoard = 1e9 -- 시험관이 아주 느려도
		ExamRules.duelTick(d, d.endsAt)
		T.eq(d.phase, "lose")
		local changed = ExamRules.duelHit(d, 1e50, d.endsAt + 1)
		T.falsy(changed)
	end)
end
