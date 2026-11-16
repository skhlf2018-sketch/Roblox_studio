--!nocheck
-- Progression: 띠 승급 조건 · 월드 열림 · 아령 구매 · 2048배여도 순서는 못 건너뜀
-- 띠 번호는 표에서 읽음 (사장님 결정 16번: 띠 22개, 월드 7/7/8 — "4개씩" 가정 없음)
return function(T, Loader)
	local Progression = Loader.require("ReplicatedStorage/Shared/Progression")
	local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")
	local Worlds = Loader.require("ReplicatedStorage/Shared/Data/Worlds")
	local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")

	local DUEL1, DUEL2, DUEL3 = Belts.duelOf(1).index, Belts.duelOf(2).index, Belts.duelOf(3).index

	T.suite("progression")

	T.test(
		"띠로 열리는 월드 = 1 + 가진 대결 띠 수 (지금 1~6 → 1 · 7~13 → 2 · 14~22 → 3)",
		function()
			T.eq(DUEL1, 7, "빨강 띠")
			T.eq(DUEL2, 14, "무지개 띠")
			T.eq(DUEL3, Belts.COUNT, "천상 띠")
			for b = 1, Belts.COUNT do
				local expect = if b >= DUEL2 then 3 elseif b >= DUEL1 then 2 else 1
				T.eq(Progression.worldsFromBelt(b), expect, "띠 " .. b)
			end
			T.eq(Progression.worldsFromBelt(8), 2, "띠 8 이상 → 월드 2 이상 (본부장)")
			T.eq(Progression.worldsFromBelt(15), 3, "띠 15 이상 → 월드 3")
			T.eq(Progression.worldsFromBelt(0 / 0), 1, "NaN")
			T.eq(Progression.worldsFromBelt(99), 3, "99")
			T.eq(Progression.worldsFromBelt(-5), 1, "음수")
		end
	)

	T.test("beltToOpen: 그 월드를 여는 띠 = 앞 월드 대결 띠 (월드 1 = 1)", function()
		T.eq(Progression.beltToOpen(1), 1)
		T.eq(Progression.beltToOpen(2), DUEL1)
		T.eq(Progression.beltToOpen(3), DUEL2)
		for w = 1, Worlds.COUNT do
			T.eq(Progression.worldsFromBelt(Progression.beltToOpen(w)), w, "그 띠면 그 월드가 열림")
			if w > 1 then
				T.eq(Progression.worldsFromBelt(Progression.beltToOpen(w) - 1), w - 1, "한 칸 아래면 안 열림")
			end
		end
		T.eq(Progression.beltToOpen(0 / 0), 1, "NaN")
		T.eq(Progression.beltToOpen(9), DUEL2, "범위 밖 → 마지막 월드")
	end)

	T.test(
		"canExam: 다음 띠가 심사 띠면 힘 0 이어도 도전 가능 (사장님 결정 11번 — 힘은 안 봄)",
		function()
			local ok, reason, first = Progression.canExam(0, 1)
			T.truthy(ok, "힘 0 으로도 도전")
			T.eq(reason, nil)
			T.eq(first.index, 2)
			local ok2, _, nextBelt = Progression.canExam(Belts.get(2).needPower, 1)
			T.truthy(ok2)
			T.eq(nextBelt.index, 2)
			local ok3, reason3 = Progression.canExam(1e60, DUEL1 - 1)
			T.falsy(ok3)
			T.eq(reason3, "duel", "월드 1 마지막 띠는 대결로만")
			local ok4, reason4 = Progression.canExam(1e60, Belts.COUNT)
			T.falsy(ok4)
			T.eq(reason4, "max")
			local ok5, _, nan = Progression.canExam(0 / 0, 1)
			T.truthy(ok5, "NaN 힘이어도 도전은 됨 (치는 힘은 0 → 합격은 못 함)")
			T.eq(nan.index, 2, "그래도 다음 띠만")
			-- 심사 띠 = 흰 띠·대결 띠를 뺀 전부
			for b = 1, Belts.COUNT - 1 do
				local okB = Progression.canExam(0, b)
				T.eq(okB, not Belts.get(b + 1).duel, "띠 " .. b .. " → " .. b + 1)
			end
		end
	)

	T.test("canDuel: 다음 띠가 대결 띠면 힘과 상관없이 도전 가능", function()
		local ok, reason = Progression.canDuel(1e60, 1)
		T.falsy(ok)
		T.eq(reason, "exam", "띠 2 는 심사로")
		T.truthy(Progression.canDuel(Belts.duelOf(1).needPower, DUEL1 - 1))
		local ok2, reason2, nextBelt = Progression.canDuel(0, DUEL2 - 1)
		T.truthy(ok2, "힘 0 으로도 대결 시작")
		T.eq(reason2, nil)
		T.eq(nextBelt.index, DUEL2)
		T.truthy(Progression.canDuel(1e60, DUEL3 - 1), "마지막 띠")
		local ok3, reason3 = Progression.canDuel(1e60, Belts.COUNT)
		T.falsy(ok3)
		T.eq(reason3, "max")
		local duels = 0
		for b = 1, Belts.COUNT - 1 do
			if Progression.canDuel(0, b) then
				duels += 1
			end
		end
		T.eq(duels, Worlds.COUNT, "대결은 월드마다 한 번")
	end)

	T.test("2048배·힘 1e60 이어도 띠는 1칸씩, 월드는 대결로만 (건너뛰기 없음)", function()
		local _, _, nextBelt = Progression.canExam(1e60, 1)
		T.eq(nextBelt.index, 2, "띠 1 → 2 만")
		T.eq(Progression.worldsFromBelt(1), 1, "띠 1 이면 월드 1 만")
		T.falsy(
			Progression.isWorldOpen(2, Progression.worldsFromBelt(DUEL1 - 1)),
			"월드 1 대결 띠 전이면 월드 2 닫힘"
		)
	end)

	T.test("isWorldOpen: 정수 1~열린 월드만", function()
		T.truthy(Progression.isWorldOpen(1, 1))
		T.falsy(Progression.isWorldOpen(2, 1))
		T.truthy(Progression.isWorldOpen(2, 3))
		T.falsy(Progression.isWorldOpen(4, 3))
		T.falsy(Progression.isWorldOpen(0, 3))
		T.falsy(Progression.isWorldOpen(1.5, 3))
		T.falsy(Progression.isWorldOpen(0 / 0, 3))
		T.falsy(Progression.isGrandMaster(Belts.COUNT - 1))
		T.falsy(Progression.isGrandMaster(12), "9단 띠는 그랜드 마스터가 아님")
		T.truthy(Progression.isGrandMaster(Belts.COUNT))
	end)

	T.test("canBuyDumbbell: 순서대로 · 돈 · 끝", function()
		local ok, reason, d = Progression.canBuyDumbbell(1, 0)
		T.falsy(ok)
		T.eq(reason, "money")
		T.eq(d.level, 2)
		T.truthy(Progression.canBuyDumbbell(1, Dumbbells.get(2).price))
		local ok2, _, d2 = Progression.canBuyDumbbell(5, 1e60)
		T.truthy(ok2)
		T.eq(d2.level, 6, "다음 하나만")
		local ok3, reason3 = Progression.canBuyDumbbell(Dumbbells.COUNT, 1e60)
		T.falsy(ok3)
		T.eq(reason3, "max")
		T.falsy(Progression.canBuyDumbbell(1, 0 / 0), "NaN 돈")
	end)
end
