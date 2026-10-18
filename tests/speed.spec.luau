--!nocheck
-- 속도 → WalkSpeed 변환, 경비 추격 규칙

return function(T, Loader)
	local SpeedMath = Loader.require("ReplicatedStorage/Shared/SpeedMath")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")

	T.suite("SpeedMath")

	T.test("WalkSpeed: 0 → 16, 상한 120, 단조 증가", function()
		T.eq(SpeedMath.toWalkSpeed(0), 16)
		T.eq(SpeedMath.toWalkSpeed(-5), 16)
		T.near(SpeedMath.toWalkSpeed(1e13), 120, 1e-6)
		T.eq(SpeedMath.toWalkSpeed(1e30), 120)
		local prev = 0
		for _, s in { 0, 10, 900, 1e4, 4e4, 1.7e5, 7e5, 2.5e6, 1.8e7, 7e8, 2.5e9, 7e9, 2e10, 5e10, 1.5e11, 5e11 } do
			local ws = SpeedMath.toWalkSpeed(s)
			T.truthy(ws >= prev, "단조 " .. s)
			prev = ws
		end
		T.near(SpeedMath.toWalkSpeed(10), 24.33, 0.01)
		T.near(SpeedMath.toWalkSpeed(5e11), 109.59, 0.01)
	end)

	T.test("NaN 은 0 취급", function()
		T.eq(SpeedMath.toWalkSpeed(0 / 0), 16)
	end)

	T.test("알 들면 WalkSpeed 감소, 하한 적용", function()
		local free = SpeedMath.toWalkSpeed(1e4)
		local carry = SpeedMath.carryWalkSpeed(1e4, 0.5)
		T.near(carry, free * 0.5, 1e-9)
		T.eq(SpeedMath.carryWalkSpeed(0, 0.5), Config.CARRY_WALKSPEED_MIN)
		T.eq(SpeedMath.walkSpeedFor(1e4, 0), free)
	end)

	T.test("추천 속도면 보통 알을 들어도 경비가 못 잡음, 그보다 2% 모자라면 잡힘", function()
		local normal = Sizes.get("normal").speedPenalty
		for _, b in Biomes.list do
			T.truthy(SpeedMath.canEscape(b.guardSpeed, b.recommendedSpeed), b.id .. " 알 없이 같은 속도")
			T.truthy(
				SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(b.recommendedSpeed, normal)),
				b.id .. " 보통 알"
			)
			T.truthy(SpeedMath.canEscape(b.guardSpeed, b.recommendedSpeed * 2), b.id .. " 2배")
			T.falsy(
				SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(b.recommendedSpeed * 0.98, normal)),
				b.id .. " 98% + 보통 알"
			)
		end
	end)

	T.test("모자랄수록 경비가 더 빨라짐, 상한 적용", function()
		local g = 1e4
		local r90 = SpeedMath.guardChaseRatio(g, 9e3)
		local r50 = SpeedMath.guardChaseRatio(g, 5e3)
		T.truthy(r50 > r90 and r90 > 1, "순서")
		T.near(r50, 2 * Config.GUARD_CHASE_MARGIN, 1e-9)
		T.eq(SpeedMath.guardChaseRatio(g, 1), Config.GUARD_CHASE_MAX_RATIO)
		T.eq(SpeedMath.guardChaseRatio(g, 0), Config.GUARD_CHASE_MAX_RATIO)
		T.eq(SpeedMath.guardChaseRatio(g, 1e9), Config.GUARD_CHASE_MIN_RATIO)
		T.near(SpeedMath.guardChaseWalkSpeed(g, 5e3, 40), 40 * r50, 1e-9)
		T.eq(SpeedMath.guardChaseWalkSpeed(g, 1, 200), Config.GUARD_MAX_WALKSPEED)
	end)

	T.test(
		"2판 추격 공식: 플레이어 WalkSpeed × clamp(추천/실효 × 0.99, 0.85, 3.0), 모자라면 최소 1.2배",
		function()
			T.eq(Config.GUARD_CHASE_MIN_RATIO, 0.85)
			T.eq(Config.GUARD_CHASE_MAX_RATIO, 3.0)
			local g = SpeedMath.guardSpeedFor(1e4) -- 9000 (보통 알 기준)
			-- 추천 이상(보통 알 무게 포함 실효 9000 이상): 0.85 ~ 0.99배 → 못 잡음
			T.near(SpeedMath.guardChaseRatio(g, 9e3), 0.99, 1e-9, "딱 추천")
			T.near(SpeedMath.guardChaseRatio(g, 1e4), 0.891, 1e-9, "조금 빠름")
			T.eq(SpeedMath.guardChaseRatio(g, 2e4), 0.85, "훨씬 빠름 → 하한 0.85")
			-- 조금 모자람: 1.0 ~ 1.2 사이는 1.2 로 올림 (반드시 따라잡게)
			T.eq(SpeedMath.guardChaseRatio(g, 8.9e3), Config.GUARD_CHASE_SLOW_MIN_RATIO)
			T.eq(SpeedMath.guardChaseRatio(g, 8e3), Config.GUARD_CHASE_SLOW_MIN_RATIO)
			-- 많이 모자람: 비율 그대로, 상한 3
			T.near(SpeedMath.guardChaseRatio(g, 4.5e3), 1.98, 1e-9)
			T.eq(SpeedMath.guardChaseRatio(g, 1e3), 3.0)
			T.near(SpeedMath.guardChaseSpeed(g, 4.5e3, 40), 40 * 1.98, 1e-9, "WalkSpeed 곱")
			T.eq(SpeedMath.guardChaseSpeed, SpeedMath.guardChaseWalkSpeed, "1판 이름도 같은 함수")
		end
	)

	T.test("시작 속도로 숲에서 초거대 알을 들어도 닭은 못 잡음", function()
		local forest = Biomes.get("forest")
		local giant = Sizes.get("giant")
		local carrying = SpeedMath.carrySpeed(Config.STARTING_SPEED, giant.speedPenalty)
		T.truthy(SpeedMath.canEscape(forest.guardSpeed, carrying))
	end)

	T.test(
		"큰 알은 추천 속도보다 더 빨라야 안전 (requiredSpeed = 이 값보다 커야 안전)",
		function()
			local big = Sizes.get("big").speedPenalty
			local guard = SpeedMath.guardSpeedFor(1e4)
			T.near(guard, 9e3, 1e-6)
			local need = SpeedMath.requiredSpeed(1e4, big)
			T.near(need, 9e3 * Config.GUARD_CHASE_MARGIN / 0.8, 1e-6)
			T.truthy(SpeedMath.canEscape(guard, SpeedMath.carrySpeed(need * 1.0001, big)))
			T.falsy(SpeedMath.canEscape(guard, SpeedMath.carrySpeed(need * 0.9999, big)))
			T.falsy(SpeedMath.canEscape(guard, SpeedMath.carrySpeed(1e4, big)), "표지판 속도로는 큰 알 위험")
		end
	)

	T.test("평소 경비 WalkSpeed = 같은 로그 곡선", function()
		T.eq(SpeedMath.guardBaseWalkSpeed(900), SpeedMath.toWalkSpeed(900))
	end)
end
