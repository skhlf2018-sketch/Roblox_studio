--!nocheck
--[[
	sizes — shared/Data/Sizes (사장님 결정 13·14번: 힘이 셀수록 몸·월드·아령이 커짐 · 걷기 2배) 순수 계산 검사
	  몸 배율 1 (힘 0) … MAX_SCALE (우주 추천 힘 이상), 줄어드는 곳 없음 · 월드 배율 · quantize · 아령 배율 · 마지막 아령 = 아파트 2배
	  · 걷기·점프 · 이상한 입력(NaN · ±무한 · 음수 · 글자 · nil · 표)에도 오류 없음
]]
return function(T, Loader)
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Targets = Loader.require("ReplicatedStorage/Shared/Data/Targets")
	local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")

	local function rel(a, b)
		return math.abs(a - b) / math.max(math.abs(b), 1e-300)
	end

	-- 힘 0 … 1e60 을 1% 씩 (그리고 0 근처 작은 수)
	local function powers()
		local list = { 0, 1e-9, 0.001, 0.5, 1 }
		local p = 1
		while p < 1e60 do
			p *= 1.01
			table.insert(list, p)
		end
		table.insert(list, Sizes.MAX_POWER)
		table.insert(list, 1e60)
		table.sort(list)
		return list
	end

	T.suite("sizes: 몸 배율 (playerScale · muscle)")

	T.test("힘 0 이면 몸 1 · 근육 0 · 음수 · NaN 도 1 · 0", function()
		T.eq(Sizes.playerScale(0), 1)
		T.eq(Sizes.muscle(0), 0)
		T.eq(Sizes.playerScale(-5), 1)
		T.eq(Sizes.playerScale(0 / 0), 1)
		T.eq(Sizes.muscle(0 / 0), 0)
	end)

	T.test(
		"힘 0 ~ 1e60 (1% 씩) 몸 배율 · 근육이 줄어드는 곳 없음 · 1 ~ MAX_SCALE 안 · 근육 0 ~ 1 안",
		function()
			local lastScale, lastMuscle = 0, -1
			local n = 0
			for _, p in powers() do
				local s, m = Sizes.playerScale(p), Sizes.muscle(p)
				T.truthy(s >= lastScale, "몸이 줄어듦 @ 힘 " .. p)
				T.truthy(m >= lastMuscle, "근육이 줄어듦 @ 힘 " .. p)
				T.truthy(s >= 1 and s <= Sizes.MAX_SCALE + 1e-9, "몸 범위 " .. s)
				T.truthy(m >= 0 and m <= 1, "근육 범위 " .. m)
				lastScale, lastMuscle = s, m
				n += 1
			end
			T.truthy(n > 10000, "검사한 힘 " .. n .. "개")
		end
	)

	T.test("마지막 물건(우주) 추천 힘 이상이면 몸 = MAX_SCALE · 근육 = 1", function()
		T.eq(Sizes.MAX_POWER, Targets.list[#Targets.list].recommendPower)
		T.truthy(rel(Sizes.playerScale(Sizes.MAX_POWER), Sizes.MAX_SCALE) < 1e-12, "우주 추천 힘")
		for _, p in { Sizes.MAX_POWER * 1.0001, Sizes.MAX_POWER * 10, 1e45, 1e60, 1e308, math.huge } do
			T.eq(Sizes.playerScale(p), Sizes.MAX_SCALE, "힘 " .. p)
			T.eq(Sizes.muscle(p), 1, "근육 " .. p)
		end
		T.truthy(Sizes.playerScale(Sizes.MAX_POWER * 0.5) < Sizes.MAX_SCALE, "그 아래는 아직 덜 큼")
	end)

	T.test("MAX_SCALE × 아바타 키 = 아파트 높이 × 2 (본부장 몸 최대 ≈ 13.97, 키 ≈ 75)", function()
		T.truthy(rel(Sizes.MAX_SCALE * Sizes.AVATAR_HEIGHT, 2 * Sizes.APARTMENT_HEIGHT) < 1e-12)
		T.truthy(Sizes.MAX_SCALE > 13.9 and Sizes.MAX_SCALE < 14, "≈ 13.97 " .. Sizes.MAX_SCALE)
	end)

	T.suite("sizes: 월드 배율 (worldScale)")

	T.test("월드 1 = 1 < 월드 2 < 월드 3 < MAX_SCALE · 0.1 단위", function()
		local w1, w2, w3 = Sizes.worldScale(1), Sizes.worldScale(2), Sizes.worldScale(3)
		print(string.format("  (월드 배율: %s · %s · %s)", w1, w2, w3))
		T.eq(w1, 1)
		T.truthy(w1 < w2 and w2 < w3 and w3 < Sizes.MAX_SCALE, "순서")
		for _, w in { w2, w3 } do
			T.truthy(math.abs(w * 10 - math.floor(w * 10 + 0.5)) < 1e-9, "0.1 단위 " .. w)
		end
	end)

	T.test(
		"월드 2·3 배율 = 그 월드 물건 추천 힘의 로그 평균인 플레이어 몸 배율 (0.1 반올림)",
		function()
			for w = 2, 3 do
				local list = Targets.byWorld(w)
				T.truthy(#list > 0)
				local sum = 0
				for _, t in list do
					sum += math.log10(t.recommendPower)
				end
				local avg = 10 ^ (sum / #list)
				local expect = math.floor(Sizes.playerScale(avg) * 10 + 0.5) / 10
				T.eq(Sizes.worldScale(w), expect, "월드 " .. w)
			end
		end
	)

	T.test(
		"월드 번호가 이상해도 오류 없이 1 (0 · 음수 · NaN · ±무한 · 글자 · 없는 월드 4)",
		function()
			for _, w in { 0, -3, 0 / 0, math.huge, -math.huge, "abc", nil, {}, true, 4, 99 } do
				local ok, s = pcall(Sizes.worldScale, w)
				T.truthy(ok, "오류: " .. tostring(s) .. " (" .. tostring(w) .. ")")
				T.eq(s, 1, "월드 " .. tostring(w))
			end
			T.eq(Sizes.worldScale(2.7), Sizes.worldScale(2), "소수는 내림")
			T.eq(Sizes.worldScale("3"), Sizes.worldScale(3), "글자 숫자")
		end
	)

	T.suite("sizes: quantize (서버가 몸을 다시 키우는 단계)")

	T.test(
		"1 ~ MAX_SCALE 를 0.01% 씩: 결과 ≤ 입력 · 입력과 한 STEP 안 · 1 이상 · 줄어드는 곳 없음",
		function()
			local s = 1
			local last = 0
			local n = 0
			local ratio = 1 + Sizes.STEP
			while s <= Sizes.MAX_SCALE do
				local q = Sizes.quantize(s)
				T.truthy(q <= s, "입력보다 큼: " .. s .. " → " .. q)
				T.truthy(s / q < ratio * (1 + 1e-12), "한 STEP 넘게 내림: " .. s .. " → " .. q)
				T.truthy(q >= 1, "1 아래")
				T.truthy(q >= last, "줄어듦 @ " .. s)
				last = q
				s *= 1.0001
				n += 1
			end
			T.truthy(n > 20000, "검사 " .. n)
		end
	)

	T.test(
		"단계는 1.02 의 거듭제곱 (2% 씩) · 맨 위는 정확히 MAX_SCALE · 1 아래 입력은 1",
		function()
			local ratio = 1 + Sizes.STEP
			for _, s in { 1, 1.01, 1.5, 2, 3.7, 5.5, 11, 13.9 } do
				local q = Sizes.quantize(s)
				local k = math.log(q) / math.log(ratio)
				T.truthy(math.abs(k - math.floor(k + 0.5)) < 1e-6, s .. " → " .. q .. " 은 1.02^k")
			end
			T.eq(Sizes.quantize(Sizes.MAX_SCALE), Sizes.MAX_SCALE, "가장 큰 몸 = MAX_SCALE 그대로")
			T.eq(Sizes.quantize(Sizes.playerScale(1e60)), Sizes.MAX_SCALE)
			T.eq(Sizes.quantize(1e9), Sizes.MAX_SCALE, "MAX 넘으면 MAX")
			T.eq(Sizes.quantize(1), 1)
			T.eq(Sizes.quantize(0.5), 1, "1 아래 → 1")
			T.eq(Sizes.quantize(Sizes.playerScale(0)), 1)
			-- 2% 안 바뀌면 같은 값 (들 때마다 다시 키우지 않음)
			T.eq(Sizes.quantize(2.0), Sizes.quantize(2.0 * 1.0001))
		end
	)

	T.suite("sizes: 아령 배율 · 마지막 아령 = 아파트 2배 (결정 13번 고쳐 말함)")

	T.test("dumbbellScale: 1단계 1 · 마지막 DUMBBELL_MAX · 단계마다 늘어남 (고르게)", function()
		local count = #Dumbbells.list
		T.eq(Sizes.dumbbellScale(1), 1)
		T.truthy(rel(Sizes.dumbbellScale(count), Sizes.DUMBBELL_MAX) < 1e-12)
		local step = (Sizes.DUMBBELL_MAX - 1) / (count - 1)
		for level = 2, count do
			local d = Sizes.dumbbellScale(level) - Sizes.dumbbellScale(level - 1)
			T.truthy(d > 0, "레벨 " .. level .. " 커짐")
			T.truthy(math.abs(d - step) < 1e-9, "고르게 " .. level)
		end
		T.eq(Sizes.dumbbellScale(count + 5), Sizes.DUMBBELL_MAX, "끝 넘으면 최대")
		T.eq(Sizes.dumbbellScale(0), 1, "0 → 1")
	end)

	T.test(
		"마지막 아령: LAST_DUMBBELL_LENGTH × MAX_SCALE × dumbbellScale(마지막) = 아파트 × 2 (0.1% 안) · DUMBBELL_MAX ≈ 2.23",
		function()
			T.eq(Sizes.FINAL_DUMBBELL_LENGTH, 2 * Sizes.APARTMENT_HEIGHT)
			T.eq(Sizes.LAST_DUMBBELL_LENGTH, 2.42, "손잡이 0.9 + 2 × (원판 4장 × 0.16 + 0.12)")
			local length = Sizes.LAST_DUMBBELL_LENGTH * Sizes.MAX_SCALE * Sizes.dumbbellScale(#Dumbbells.list)
			print(
				string.format(
					"  (마지막 아령 길이 %.3f 스터드 · 아파트 %.3f × 2)",
					length,
					Sizes.APARTMENT_HEIGHT
				)
			)
			T.truthy(rel(length, 2 * Sizes.APARTMENT_HEIGHT) < 0.001, "길이 " .. length)
			-- 서버가 실제로 주는 몸(quantize)으로 들어도 같음 (맨 위는 MAX_SCALE 그대로)
			local held = Sizes.LAST_DUMBBELL_LENGTH
				* Sizes.quantize(Sizes.playerScale(1e60))
				* Sizes.dumbbellScale(#Dumbbells.list)
			T.truthy(rel(held, 2 * Sizes.APARTMENT_HEIGHT) < 0.001, "BodyScale 로 들면 " .. held)
			T.truthy(Sizes.DUMBBELL_MAX > 2.2 and Sizes.DUMBBELL_MAX < 2.25, "DUMBBELL_MAX " .. Sizes.DUMBBELL_MAX)
		end
	)

	T.suite("sizes: 걷기 · 점프 (결정 14번)")

	T.test(
		"걷기 32 × 몸 배율 (지금 16 의 2배) · 점프 높이 7.2 × 몸 배율 · 1 아래는 1 · MAX 위는 MAX",
		function()
			T.eq(Sizes.BASE_WALK_SPEED, 32)
			T.eq(Sizes.walkSpeed(1), 32)
			T.eq(Sizes.walkSpeed(2), 64)
			T.eq(Sizes.jumpHeight(1), 7.2)
			T.near(Sizes.jumpHeight(3), 21.6, 1e-9)
			T.eq(Sizes.walkSpeed(0.5), 32, "1 아래 → 1")
			T.eq(Sizes.walkSpeed(Sizes.MAX_SCALE), 32 * Sizes.MAX_SCALE)
			T.eq(Sizes.walkSpeed(1e9), 32 * Sizes.MAX_SCALE, "MAX 위 → MAX")
			T.eq(Sizes.jumpHeight(1e9), 7.2 * Sizes.MAX_SCALE)
		end
	)

	T.suite("sizes: 이상한 입력에도 오류 없음")

	T.test(
		"모든 함수 × (nil · NaN · ±무한 · 음수 · 0 · 1e308 · 글자 · 표 · true): 오류 없이 범위 안 숫자",
		function()
			local junk =
				{ nil, 0 / 0, math.huge, -math.huge, -1, -1e300, 0, 1e308, "abc", "12", "", {}, true, false, 1.5 }
			local checks = {
				{ "playerScale", 1, Sizes.MAX_SCALE },
				{ "muscle", 0, 1 },
				{ "worldScale", 1, Sizes.MAX_SCALE },
				{ "dumbbellScale", 1, Sizes.DUMBBELL_MAX },
				{ "walkSpeed", Sizes.BASE_WALK_SPEED, Sizes.BASE_WALK_SPEED * Sizes.MAX_SCALE },
				{ "jumpHeight", Sizes.BASE_JUMP_HEIGHT, Sizes.BASE_JUMP_HEIGHT * Sizes.MAX_SCALE },
				{ "quantize", 1, Sizes.MAX_SCALE },
			}
			for _, c in checks do
				for i = 1, 15 do
					local v = junk[i]
					local ok, r = pcall(Sizes[c[1]], v)
					T.truthy(ok, c[1] .. "(" .. tostring(v) .. ") 오류: " .. tostring(r))
					T.truthy(
						type(r) == "number" and r == r and r >= c[2] - 1e-9 and r <= c[3] + 1e-9,
						c[1] .. "(" .. tostring(v) .. ") = " .. tostring(r)
					)
				end
			end
		end
	)
end
