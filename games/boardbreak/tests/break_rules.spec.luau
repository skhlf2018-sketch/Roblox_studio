--!nocheck
-- BreakRules: 없는 id · 닫힌 월드 · 거리 · 힘 부족 · 플레이어별 체력 · 깨지면 다시 가득
return function(T, Loader)
	local BreakRules = Loader.require("ReplicatedStorage/Shared/BreakRules")
	local Targets = Loader.require("ReplicatedStorage/Shared/Data/Targets")

	local cotton = Targets.get("cotton")
	local here = { x = 0, y = 0, z = 0 }

	T.suite("break_rules")

	T.test("check: 없는 id · 숫자 id · 닫힌 월드 · 먼 거리", function()
		local _, r1 = BreakRules.check("nope", 3, here, here, 10, 6)
		T.eq(r1, "unknown", "없는 id")
		local _, r2 = BreakRules.check(12, 3, here, here, 10, 6)
		T.eq(r2, "unknown", "숫자")
		local _, r3 = BreakRules.check("mall", 1, here, here, 10, 6)
		T.eq(r3, "closed", "월드 2 물건을 월드 1 만 연 사람이")
		local _, r4 = BreakRules.check("cotton", 1, { x = 100, y = 0, z = 0 }, here, 10, 6)
		T.eq(r4, "far", "먼 거리")
		local t, r5 = BreakRules.check("cotton", 1, { x = 15, y = 3, z = 0 }, here, 10, 6)
		T.eq(t, cotton, "닿는 거리 (10 + 6 안)")
		T.eq(r5, nil)
		local _, r6 = BreakRules.check("cotton", 1, here, nil, 10, 6)
		T.eq(r6, "far", "자리 없음")
	end)

	T.test("inReach: Vector3 모양(X/Y/Z)도 · NaN 위치 · 높이 차", function()
		T.truthy(BreakRules.inReach({ X = 3, Y = 3, Z = 4 }, here, 5, 0), "X/Y/Z")
		T.falsy(BreakRules.inReach({ x = 0 / 0, y = 0, z = 0 }, here, 10, 6), "NaN")
		T.falsy(BreakRules.inReach({ x = 0, y = 500, z = 0 }, here, 10, 6), "너무 높음")
		T.falsy(BreakRules.inReach(here, here, 0, 0), "닿는 거리 0")
	end)

	T.test(
		"힘 문턱 없음 (사장님 결정 11번): 힘 1 로도 피해 1 · 우주에도 · 힘 0·NaN 이면 피해 0",
		function()
			local hp = {}
			local out = BreakRules.hit(hp, cotton, 1)
			T.eq(out.damage, 1)
			T.eq(out.reason, nil, "weak 없음")
			T.eq(out.hp, cotton.hp - 1)
			T.eq(hp.cotton, cotton.hp - 1, "깎인 만큼 남음")
			local universe = Targets.get("universe")
			local far = BreakRules.hit(hp, universe, 1)
			T.eq(far.damage, 1, "추천 힘 " .. universe.recommendPower .. " 보다 훨씬 약해도 깎임")
			T.eq(hp.universe, universe.hp - 1)
			for _, bad in { 0, -5, 0 / 0, math.huge } do
				local none = BreakRules.hit(hp, cotton, bad)
				T.eq(none.damage, 0, "피해 0: " .. tostring(bad))
				T.eq(none.broken, false)
			end
			T.eq(hp.cotton, cotton.hp - 1, "0·NaN 은 체력을 안 바꿈")
		end
	)

	T.test("한 번씩 깎이고 0 이하면 깨짐 → 다시 가득 (넘친 피해는 버림)", function()
		local hp = {}
		local hits = 0
		local broken = false
		while not broken do
			local out = BreakRules.hit(hp, cotton, cotton.recommendPower)
			hits += 1
			broken = out.broken
			if broken then
				T.eq(out.hp, cotton.hp, "깨지면 가득")
			end
		end
		T.eq(hits, 15, "추천 힘이면 15번")
		T.eq(hp.cotton, nil, "깨진 뒤 표에서 지움")
		local big = BreakRules.hit(hp, cotton, 1e50)
		T.truthy(big.broken, "한 방")
		T.eq(big.damage, cotton.hp, "넘친 피해는 버림 (깎인 만큼만)")
	end)

	T.test("플레이어마다 따로 (표가 다르면 서로 영향 없음)", function()
		local a, b = {}, {}
		BreakRules.hit(a, cotton, cotton.recommendPower)
		T.eq(a.cotton, cotton.hp - cotton.recommendPower, "A 깎임")
		T.eq(BreakRules.currentHp(b, cotton), cotton.hp, "B 그대로")
	end)

	T.test("체력 표가 망가졌으면 가득으로 (NaN · 음수 · 최대보다 큼)", function()
		T.eq(BreakRules.currentHp({ cotton = 0 / 0 }, cotton), cotton.hp)
		T.eq(BreakRules.currentHp({ cotton = -3 }, cotton), cotton.hp)
		T.eq(BreakRules.currentHp({ cotton = 1e9 }, cotton), cotton.hp)
	end)
end
