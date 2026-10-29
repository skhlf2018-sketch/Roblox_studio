--!nocheck
-- 속도 → WalkSpeed 변환 (2판 수정 곡선), 경비 추격 규칙

return function(T, Loader)
	local SpeedMath = Loader.require("ReplicatedStorage/Shared/SpeedMath")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")

	T.suite("SpeedMath")

	T.test(
		"2판 수정 WalkSpeed = clamp(16 × (1 + log10(max(속도, 10) / 10)), 16, 150) — 원작 관찰 기준점",
		function()
			T.eq(Config.SPEED_LOG_BASE, 20)
			T.eq(Config.SPEED_LOG_SLOPE, 0.95)
			T.eq(Config.SPEED_LOG_FLOOR, 10)
			T.eq(Config.SPEED_WALK_MAX, 230)
			T.eq(SpeedMath.toWalkSpeed(0), 20)
			T.eq(SpeedMath.toWalkSpeed(-5), 20)
			T.eq(SpeedMath.toWalkSpeed(10), 20, "10 이하 = 최소 20")
			-- 표 (보고서·GAME_DESIGN 2판 B 와 같은 숫자)
			T.near(SpeedMath.toWalkSpeed(20), 25.72, 0.01, "시작 속도 (4판: 기본 걷기보다 조금 빠르게)")
			T.near(SpeedMath.toWalkSpeed(200), 44.72, 0.01, "4판: 원작(35~40)보다 20% 빠르게")
			T.near(SpeedMath.toWalkSpeed(1e4), 77, 1e-9)
			T.near(SpeedMath.toWalkSpeed(6.4e4), 92.32, 0.01)
			T.near(SpeedMath.toWalkSpeed(1e6), 115, 1e-9)
			T.near(SpeedMath.toWalkSpeed(5.8e6), 129.51, 0.01, "4판: 원작 5.8M(105~110)보다 20% 빠르게")
			T.near(SpeedMath.toWalkSpeed(1e9), 172, 1e-9)
			T.near(SpeedMath.toWalkSpeed(1e10), 191, 1e-9)
			T.eq(SpeedMath.toWalkSpeed(2e12), 230, "상한")
			T.eq(SpeedMath.toWalkSpeed(1e30), 230)
			T.eq(SpeedMath.toWalkSpeed(math.huge), 230)
			-- 원작: 5.8M 이면 구역 하나(240)를 약 2초, 심연의 바다(z ≈ 1560)에서 허브까지 약 15초
			T.near(240 / SpeedMath.toWalkSpeed(5.8e6), 1.85, 0.05)
			T.near(1560 / SpeedMath.toWalkSpeed(5.8e6), 12.05, 0.2)
			local prev = 0
			for _, s in { 0, 10, 20, 900, 1e4, 4e4, 1.7e5, 7e5, 2.5e6, 1.8e7, 7e8, 2.5e9, 7e9, 2e10, 5e11 } do
				local ws = SpeedMath.toWalkSpeed(s)
				T.truthy(ws >= prev, "단조 " .. s)
				prev = ws
			end
		end
	)

	T.test(
		"7판 새 구역 16~18: 경비 추격 WalkSpeed 가 15구역(222.3)보다 계속 빠르고 상한 230 보다는 느림 (225.1 · 227.2 · 229.6)",
		function()
			local prev = 0
			for _, b in Biomes.list do
				local chase = SpeedMath.guardChaseSpeed(b.guardSpeed)
				T.truthy(chase >= prev, b.id .. " 경비 추격 속도가 줄지 않음")
				prev = chase
			end
			local function chaseOf(id)
				return SpeedMath.guardChaseSpeed(Biomes.get(id).guardSpeed)
			end
			T.near(chaseOf("haunted_castle"), 222.3, 0.05)
			T.near(chaseOf("hacker_lab"), 225.1, 0.05)
			T.near(chaseOf("developer_room"), 227.2, 0.05)
			T.near(chaseOf("bug_dimension"), 229.55, 0.01)
			T.truthy(chaseOf("hacker_lab") > chaseOf("haunted_castle"))
			T.truthy(chaseOf("bug_dimension") > chaseOf("developer_room"))
			-- 경비 추격 속도의 0.1% 위(= 추천 속도면 안전한 사람)도 상한 230 밑이어야 "안전/위험" 이 걷기로 갈림
			local last = Biomes.list[#Biomes.list]
			local safeWalk = SpeedMath.toWalkSpeed(last.guardSpeed * Config.GUARD_CHASE_MARGIN * 1.001)
			T.truthy(safeWalk > chaseOf(last.id), "18구역 안전한 사람이 경비보다 빠름")
			T.truthy(SpeedMath.toWalkSpeed(last.guardSpeed * Config.GUARD_CHASE_MARGIN * 1.001) < Config.SPEED_WALK_MAX)
		end
	)

	T.test("NaN 은 0 취급", function()
		T.eq(SpeedMath.toWalkSpeed(0 / 0), 20)
	end)

	T.test(
		"4판 고정 추격: 추천 속도 이상이면 경비가 플레이어보다 느리고(못 잡음), 모자라면 경비가 더 빠름 (18구역 × 4크기, WalkSpeed 기준 — 7판 18구역 1.2T 도 상한 230 안쪽)",
		function()
			-- 플레이어 상한(230)이 맨 끝 구역 경비 추격 속도보다 커야 빠른 사람은 추월 가능
			T.truthy(Config.SPEED_WALK_MAX > SpeedMath.guardChaseSpeed(SpeedMath.guardSpeedFor(500e9)))
			local last = Biomes.list[#Biomes.list]
			T.truthy(
				Config.SPEED_WALK_MAX > SpeedMath.guardChaseSpeed(last.guardSpeed),
				"맨 끝 구역 " .. last.id .. " 경비도 상한보다 느림"
			)
			T.truthy(Config.GUARD_MAX_WALKSPEED >= Config.SPEED_WALK_MAX)
			for _, b in Biomes.list do
				for _, size in Sizes.list do
					local need = SpeedMath.requiredSpeed(b.recommendedSpeed, size.speedPenalty)
					local chase = SpeedMath.guardChaseSpeed(b.guardSpeed)
					-- 숲(추천 10)은 곡선 바닥(속도 10 이하 = 20) 근처라 WalkSpeed 가 같을 수 있음 → 숫자 비교(canEscape)만 엄격히
					for _, k in { 1.001, 1.5, 10, 1e6 } do
						local walk = SpeedMath.carryWalkSpeed(need * k, size.speedPenalty)
						T.truthy(
							chase < walk or walk <= Config.SPEED_LOG_BASE,
							b.id .. " " .. size.id .. " ×" .. k .. " 안전: 경비가 느림"
						)
						T.truthy(SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(need * k, size.speedPenalty)))
					end
					for _, k in { 0.999, 0.9, 0.5, 1e-3 } do
						local walk = SpeedMath.carryWalkSpeed(need * k, size.speedPenalty)
						T.truthy(
							chase > walk or chase <= Config.SPEED_LOG_BASE,
							b.id .. " " .. size.id .. " ×" .. k .. " 위험: 경비가 더 빠름"
						)
						T.falsy(SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(need * k, size.speedPenalty)))
					end
				end
			end
		end
	)

	T.test(
		"150 스터드/초 추격 시뮬레이션 (틱 0.1초, MoveTo 는 목표에 닿으면 멈춤): 앞을 보고 쫓으면 1.2배는 잡고 0.99배는 못 잡음",
		function()
			local GuardLogic = Loader.require("ServerScriptService/Server/Logic/GuardLogic")
			local dt = Config.GUARD_TICK_SECONDS
			-- 플레이어는 -z 로 곧게 달림, 경비는 gap 뒤에서 시작. 잡히면 걸린 시간, 못 잡으면 nil
			local function simulate(playerWalk, ratio, reach, lead, segment)
				local guardWalk = playerWalk * ratio
				local pz, gz, gx = 0, 40, 3 -- 옆으로 3 비켜서 쫓아옴
				local prevP, prevRelX, prevRelZ = nil, nil, nil
				for tick = 1, 600 do
					-- 서버 틱: 지금 본 위치(+ 이동 속도 × lead)를 목표로 MoveTo
					local vz = if prevP then (pz - prevP) / dt else 0
					local aimX, aimZ = GuardLogic.leadPoint(0, pz, 0, vz, lead, playerWalk * 1.5)
					prevP = pz
					-- 다음 틱까지 0.1초: 플레이어는 달리고, 경비는 목표 쪽으로 갈 수 있는 만큼 (목표에 닿으면 멈춤)
					pz -= playerWalk * dt
					local dx, dz = aimX - gx, aimZ - gz
					local d = math.sqrt(dx * dx + dz * dz)
					local step = math.min(d, guardWalk * dt)
					if d > 0 then
						gx += dx / d * step
						gz += dz / d * step
					end
					local relX, relZ = 0 - gx, pz - gz
					local closest = if segment and prevRelX
						then GuardLogic.closestApproach(prevRelX, prevRelZ, relX, relZ)
						else math.sqrt(relX * relX + relZ * relZ)
					if closest <= reach then
						return tick * dt
					end
					prevRelX, prevRelZ = relX, relZ
				end
				return nil
			end
			local lead = Config.GUARD_LEAD_SECONDS
			for _, walk in { 16, 60, 108, 150 } do
				for _, reach in { 8, 13, 16 } do
					T.truthy(
						simulate(walk, 1.2, reach, lead, true),
						"1.2배 잡음 walk " .. walk .. " reach " .. reach
					)
					T.truthy(simulate(walk, 3, reach, lead, true), "3배 잡음")
					T.falsy(simulate(walk, 0.99, reach, lead, true), "0.99배 못 잡음 walk " .. walk)
					T.falsy(simulate(walk, 0.85, reach, lead, true), "0.85배 못 잡음")
				end
			end
			-- 1.2배면 40 스터드 뒤에서 몇 초 안에 따라잡음 (150 이어도 끊기지 않고 따라옴)
			local t = simulate(150, 1.2, 8, lead, true)
			T.truthy(t and t < 3, "150 에서 " .. tostring(t) .. "초")
			-- (고친 이유) 예전처럼 0.1초 전 자리를 목표로 + 틱 끝 거리만 보면: 150 으로 달리면 틱마다 15 씩 벌어져
			-- 작은 경비(잡힘 거리 8)는 1.2배여도 영영 못 잡았음
			T.falsy(simulate(150, 1.2, 8, 0, false), "앞을 안 보면 못 잡음")
		end
	)

	T.test("GuardLogic.leadPoint / closestApproach 경계", function()
		local GuardLogic = Loader.require("ServerScriptService/Server/Logic/GuardLogic")
		local x, z = GuardLogic.leadPoint(10, 20, 0, -100, 0.25, 1000)
		T.eq(x, 10)
		T.eq(z, -5)
		x, z = GuardLogic.leadPoint(10, 20, 0, -1e6, 0.25, 40) -- 순간이동 같은 튐 → 40 까지만
		T.eq(z, 10)
		x, z = GuardLogic.leadPoint(10, 20, 0 / 0, 5, 0.25, 40)
		T.eq(x, 10, "NaN 속도면 그 자리")
		T.eq(z, 20)
		T.near(GuardLogic.closestApproach(-10, 3, 10, 3), 3, 1e-9, "지나쳐도 가장 가까웠던 거리")
		T.near(GuardLogic.closestApproach(5, 0, 10, 0), 5, 1e-9, "멀어지는 중이면 지난 틱 거리")
		T.near(GuardLogic.closestApproach(3, 4, 3, 4), 5, 1e-9, "안 움직이면 그 거리")
		local nan = GuardLogic.closestApproach(0 / 0, 0, 1, 1)
		T.falsy(nan <= 16, "NaN 이면 안 잡음")
	end)

	T.test("알 들면 WalkSpeed 감소, 하한 적용", function()
		local free = SpeedMath.toWalkSpeed(1e4)
		local carry = SpeedMath.carryWalkSpeed(1e4, 0.5)
		T.near(carry, SpeedMath.toWalkSpeed(1e4 * 0.5), 1e-9, "4판: 무게는 속도 숫자에 적용한 뒤 곡선")
		T.truthy(carry < free)
		T.eq(
			SpeedMath.carryWalkSpeed(0, 0.5),
			Config.SPEED_LOG_BASE,
			"곡선 바닥 20 (하한 8 은 그 아래 보험)"
		)
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

	T.test(
		"(참고용 옛 비율) 모자랄수록 비율이 커짐, 상한 적용 — 게임 추격 속도는 이 비율을 안 씀",
		function()
			local g = 1e4
			local r90 = SpeedMath.guardChaseRatio(g, 9e3)
			local r50 = SpeedMath.guardChaseRatio(g, 5e3)
			T.truthy(r50 > r90 and r90 > 1, "순서")
			T.near(r50, 2 * Config.GUARD_CHASE_MARGIN, 1e-9)
			T.eq(SpeedMath.guardChaseRatio(g, 1), Config.GUARD_CHASE_MAX_RATIO)
			T.eq(SpeedMath.guardChaseRatio(g, 0), Config.GUARD_CHASE_MAX_RATIO)
			T.eq(SpeedMath.guardChaseRatio(g, 1e9), Config.GUARD_CHASE_MIN_RATIO)
		end
	)

	T.test(
		"4판 추격 속도: 구역마다 고정 = toWalkSpeed(경비 속도 × 0.99), 플레이어 속도와 무관, 상한 적용",
		function()
			local g = SpeedMath.guardSpeedFor(1e4) -- 9000
			T.near(SpeedMath.guardChaseSpeed(g), SpeedMath.toWalkSpeed(g * Config.GUARD_CHASE_MARGIN), 1e-9)
			T.truthy(
				SpeedMath.guardChaseSpeed(g) < SpeedMath.toWalkSpeed(9e3),
				"딱 경비 속도면 플레이어가 1% 빠름"
			)
			T.truthy(SpeedMath.guardChaseSpeed(g) > SpeedMath.toWalkSpeed(8e3), "모자라면 경비가 빠름")
			T.truthy(SpeedMath.guardChaseSpeed(1e30) <= Config.GUARD_MAX_WALKSPEED)
			T.eq(SpeedMath.guardChaseSpeed(0), SpeedMath.toWalkSpeed(0))
			T.truthy(SpeedMath.canEscape(g, 9e3) and not SpeedMath.canEscape(g, 8.9e3))
			T.falsy(SpeedMath.canEscape(g, 0 / 0), "NaN 은 못 도망")
		end
	)

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
			T.eq(
				SpeedMath.guardChaseWalkSpeed,
				nil,
				"옛 2판 이름은 없어짐 (추격 속도는 guardChaseSpeed(경비 속도) 하나)"
			)
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
