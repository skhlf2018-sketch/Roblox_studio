--!nocheck
--[[
	규칙 경계 테스트: "딱 그 값일 때" 어떻게 되는지. (6판 "씨앗을 훔치세요")
	  - 추천 속도와 정확히 같을 때 경비가 못 잡나, 씨앗 무게(-10~-50%)가 반영되면 얼마부터 안전한가
	  - 씨앗 무게 감소 후 WalkSpeed, 밤 30배, 오프라인 24시간 상한(이상한 값 포함)
	  - 레이트 리밋: 모든 Remote 의 burst / 회복 속도
	  - 6판 정원: 성장 단계 경계(25% · 60% · 100%), 건너뛰기 가격 경계(분 올림), 열매 최대 5·가방 상한, 먹이기 확률 상한
	  - 튜토리얼·치트 경고의 순수 규칙 경계 (6판: 퓨전·제단 경계는 기능과 함께 없앰)
	서비스 연결(실제로 코인이 빠지는지 등)은 services_*.spec / garden.spec 에서 따로 봅니다.
]]

return function(T, Loader)
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Remotes = Loader.require("ReplicatedStorage/Shared/Remotes")
	local SpeedMath = Loader.require("ReplicatedStorage/Shared/SpeedMath")
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
	local GardenRules = Loader.require("ReplicatedStorage/Shared/GardenRules")
	local FruitRules = Loader.require("ReplicatedStorage/Shared/FruitRules")
	local TutorialRules = Loader.require("ReplicatedStorage/Shared/TutorialRules")
	local EggRules = Loader.require("ReplicatedStorage/Shared/EggRules")
	local EggRoll = Loader.require("ReplicatedStorage/Shared/EggRoll")
	local Cycle = Loader.require("ReplicatedStorage/Shared/Cycle")
	local RateLimiter = Loader.require("ServerScriptService/Server/Logic/RateLimiter")
	local MoveCheck = Loader.require("ServerScriptService/Server/Logic/MoveCheck")

	local MARGIN = Config.GUARD_CHASE_MARGIN

	------------------------------------------------------------------
	T.suite("경계: 추천 속도와 경비 (씨앗 무게 포함)")

	T.test("알 없이 속도가 추천 속도와 정확히 같으면 경비가 못 잡음 (모든 구역)", function()
		for _, b in Biomes.list do
			T.truthy(SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(b.recommendedSpeed, 0)), b.id)
			T.truthy(SpeedMath.guardChaseRatio(b.guardSpeed, b.recommendedSpeed) < 1, b.id)
		end
	end)

	T.test(
		"보통 알(-10%)을 들어도 표지판 추천 속도면 안전 (2단계 B4), 1.5% 모자라면 잡힘",
		function()
			local normal = Sizes.get("normal").speedPenalty
			for _, b in Biomes.list do
				local carryNormal = SpeedMath.carrySpeed(b.recommendedSpeed, normal)
				T.truthy(SpeedMath.canEscape(b.guardSpeed, carryNormal), b.id .. " 표지판 속도면 안전")
				local carryShort = SpeedMath.carrySpeed(b.recommendedSpeed * 0.985, normal)
				T.falsy(SpeedMath.canEscape(b.guardSpeed, carryShort), b.id .. " 1.5% 모자라면 잡힘")
			end
		end
	)

	T.test(
		"크기별 안전선: 딱 경계는 안전, 경계보다 0.1% 모자라면 잡힘 (4크기 × 18구역)",
		function()
			for _, b in Biomes.list do
				for _, size in Sizes.list do
					-- 알을 들고 실효 속도 s 일 때 carrySpeed = s × (1 - 감소). 안전 ⇔ carrySpeed > guardSpeed × MARGIN
					local safeBase = b.guardSpeed * MARGIN / (1 - size.speedPenalty)
					T.truthy(
						SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(safeBase * 1.001, size.speedPenalty)),
						b.id .. " " .. size.id .. " 안전"
					)
					T.falsy(
						SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(safeBase * 0.999, size.speedPenalty)),
						b.id .. " " .. size.id .. " 위험"
					)
				end
			end
		end
	)

	T.test(
		"큰 알일수록 필요한 속도가 커짐: 표지판 속도 대비 보통 0.99배, 큼 1.11배, 거대 1.37배, 초거대 1.78배",
		function()
			-- 경비 속도 = 추천 × 0.9 (보통 알 무게 감소 포함), 안전선 = 경비 × MARGIN ÷ (1 - 감소)
			local expected = { normal = 0.99, big = 1.11375, huge = 1.37077, giant = 1.782 }
			for _, size in Sizes.list do
				T.near(SpeedMath.requiredSpeed(1, size.speedPenalty), expected[size.id], 0.001, size.id)
				T.near(0.9 * MARGIN / (1 - size.speedPenalty), expected[size.id], 0.001, size.id .. " (식 그대로)")
			end
			-- 본부장 결정(2단계 B4): 보통 알은 표지판 속도면 안전, 큼 약 +12%, 거대 약 +38%, 초거대 약 +80%
			T.truthy(SpeedMath.requiredSpeed(1, Sizes.get("normal").speedPenalty) < 1)
			T.truthy(SpeedMath.requiredSpeed(1, Sizes.get("big").speedPenalty) > 1.1)
		end
	)

	T.test(
		"경비는 안전한 사람보다 느리고 위험한 사람보다 빠르게 쫓음 (WalkSpeed 기준)",
		function()
			for _, b in Biomes.list do
				local chase = SpeedMath.guardChaseSpeed(b.guardSpeed) -- 4판: 구역 고정
				local walk = SpeedMath.toWalkSpeed(b.recommendedSpeed * 1.2)
				T.truthy(chase < walk, b.id .. " 안전한 사람보다 느림")
				local riskyWalk = SpeedMath.toWalkSpeed(b.recommendedSpeed * 0.5)
				-- 숲(추천 10)은 곡선 바닥이라 둘 다 최소 20 → 같을 수 있음
				T.truthy(
					chase > riskyWalk or riskyWalk <= Config.SPEED_LOG_BASE,
					b.id .. " 위험한 사람보다 빠름"
				)
			end
		end
	)

	T.test("속도가 0·NaN·음수여도 경비 계산이 터지지 않음", function()
		for _, bad in { 0, -5, 0 / 0, 1e-300 } do
			local ratio = SpeedMath.guardChaseRatio(1000, bad)
			T.truthy(
				ratio == ratio and ratio >= Config.GUARD_CHASE_MIN_RATIO and ratio <= Config.GUARD_CHASE_MAX_RATIO
					or ratio ~= ratio,
				"ratio " .. tostring(bad)
			)
			local ws = SpeedMath.guardChaseSpeed(bad)
			T.truthy(ws >= 1 and ws == ws, "경비 속도가 이상해도 추격 WalkSpeed 는 1 이상 유한")
			T.falsy(SpeedMath.canEscape(1000, bad))
		end
		T.eq(SpeedMath.guardChaseRatio(1000, 0), Config.GUARD_CHASE_MAX_RATIO)
	end)

	T.test("시작 속도(20)로: 숲은 초거대 알도 안전, 호수(900)는 보통 알도 위험", function()
		local forest, lake = Biomes.get("forest"), Biomes.get("lake")
		T.truthy(
			SpeedMath.canEscape(
				forest.guardSpeed,
				SpeedMath.carrySpeed(Config.STARTING_SPEED, Sizes.get("giant").speedPenalty)
			)
		)
		T.falsy(
			SpeedMath.canEscape(
				lake.guardSpeed,
				SpeedMath.carrySpeed(Config.STARTING_SPEED, Sizes.get("normal").speedPenalty)
			)
		)
	end)

	------------------------------------------------------------------
	T.suite("경계: 씨앗 무게 감소 후 속도")

	T.test("알을 들면 WalkSpeed 가 크기 감소율만큼 줄고 하한 8 밑으로는 안 내려감", function()
		for _, speed in { 0, 20, 900, 1e5, 1e9, 5e11 } do
			local free = SpeedMath.toWalkSpeed(speed)
			for _, size in Sizes.list do
				local carried = SpeedMath.carryWalkSpeed(speed, size.speedPenalty)
				T.truthy(carried <= free, "알 들면 더 빨라지진 않음")
				T.near(
					carried,
					math.max(Config.CARRY_WALKSPEED_MIN, SpeedMath.toWalkSpeed(speed * (1 - size.speedPenalty))),
					1e-9,
					size.id .. " " .. speed
				)
				-- 속도 숫자가 곡선 바닥(10) 이하면 들어도 안 들어도 최소 20 이라 같을 수 있음
				T.truthy(carried < free or speed * (1 - size.speedPenalty) <= Config.SPEED_LOG_FLOOR)
				T.truthy(carried >= Config.CARRY_WALKSPEED_MIN)
			end
		end
	end)

	T.test(
		"walkSpeedFor: 알 없으면(감소 0) 원래 속도, 감소가 있으면 느려짐, 감소율 1 이상도 터지지 않음",
		function()
			T.eq(SpeedMath.walkSpeedFor(1e4, 0), SpeedMath.toWalkSpeed(1e4))
			T.truthy(SpeedMath.walkSpeedFor(1e4, 0.2) < SpeedMath.toWalkSpeed(1e4))
			T.truthy(SpeedMath.walkSpeedFor(1e4, 5) >= Config.CARRY_WALKSPEED_MIN)
			T.near(SpeedMath.carrySpeed(1000, 5), 1000 * 0.05, 1e-9, "감소율은 95% 까지만")
			T.eq(SpeedMath.carrySpeed(1000, -1), 1000, "음수 감소는 0 취급")
		end
	)

	T.test("트레일 배율은 실효 속도에 곱해지고 1 미만은 1 로", function()
		T.eq(SpeedMath.effectiveSpeed(100, 1.5), 150)
		T.eq(SpeedMath.effectiveSpeed(100, 0.1), 100)
		T.eq(SpeedMath.effectiveSpeed(-100, 2), 0)
	end)

	------------------------------------------------------------------
	T.suite("경계: 밤 30배, 오프라인 24시간")

	T.test("낮 285초 + 밤 10초(×30) + 대기 3초 = 한 바퀴에 씨앗이 자라는 양", function()
		local perCycle = Config.DAY_SECONDS * Economy.growthRate(false, false)
			+ Config.NIGHT_SECONDS * Economy.growthRate(true, false)
			+ Config.INTERMISSION_SECONDS * Economy.growthRate(false, false)
		T.eq(perCycle, 285 + 300 + 3)
		T.eq(Cycle.totalLength(), 298)
		local p = Economy.advanceIncubation(0, 1e9, Config.NIGHT_SECONDS, 30)
		T.eq(p, 300)
	end)

	T.test(
		"성장 시간이 가장 긴 씨앗(7판 지지직 세계수: 표 60일 → 성장 3배로 실제 20일)은 몇 바퀴 만에 성체가 되나",
		function()
			local longest, id = 0, nil
			for _, plant in Loader.require("ReplicatedStorage/Shared/Data/Plants").list do
				local seconds = Economy.growSeconds(plant.id)
				if seconds > longest then
					longest, id = seconds, plant.id
				end
			end
			T.eq(id, "static_world_tree")
			T.eq(longest, 20 * 86400)
			-- 한 바퀴(298초)에 자라는 양 = 588초 → 약 2939바퀴 = 접속한 채로 약 10일 (밤 30배 덕분에 절반쯤)
			local cycles = longest / (285 + 300 + 3)
			T.truthy(cycles > 2930 and cycles < 2945, "실제 " .. cycles)
			local days = cycles * 298 / 86400
			T.truthy(days > 10 and days < 10.3, "약 10일: " .. days)
		end
	)

	T.test("성장 진행: 시간이 거꾸로(dt<0)여도 줄지 않고, 필요량에서 멈춤", function()
		local p, ready = Economy.advanceIncubation(10, 100, -5, 30)
		T.eq(p, 10)
		T.falsy(ready)
		p, ready = Economy.advanceIncubation(99.9, 100, 1000, 60)
		T.eq(p, 100)
		T.truthy(ready)
		T.eq(Economy.remainingSeconds(0, 100, 0), math.huge, "성장 속도 0 이면 끝없이")
	end)

	T.test(
		"오프라인 성장: 정확히 24시간은 전부, 1초 넘으면 상한, 첫 접속(0)·거꾸로 가는 시계는 0",
		function()
			local cap = Config.OFFLINE_GROWTH_CAP_SECONDS
			T.eq(cap, 86400)
			T.eq(Economy.offlineGrowthSeconds(1000, 1000 + cap), cap)
			T.eq(Economy.offlineGrowthSeconds(1000, 1000 + cap + 1), cap)
			T.eq(Economy.offlineGrowthSeconds(1000, 1000 + 100), 100)
			T.eq(Economy.offlineGrowthSeconds(0, 5000), 0)
			T.eq(Economy.offlineGrowthSeconds(5000, 1000), 0)
			T.eq(Economy.offlineGrowthSeconds(-100, 1000), 0, "저장 시각이 음수")
		end
	)

	------------------------------------------------------------------
	T.suite("경계: 레이트 리밋 (모든 Remote)")

	T.test(
		"Remote 마다 정확히 burst 번 통과 후 막힘, 다시 1개 회복하는 데 1/초당 회복 초",
		function()
			for name, limit in Remotes.RateLimits do
				local now = 0
				local limiter = RateLimiter.new(function()
					return now
				end)
				for i = 1, limit.burst do
					T.truthy(limiter:allow(1, name, limit.burst, limit.perSecond), name .. " " .. i .. "번째")
				end
				T.falsy(limiter:allow(1, name, limit.burst, limit.perSecond), name .. " burst 다음")
				now += (1 / limit.perSecond) * 0.99
				T.falsy(limiter:allow(1, name, limit.burst, limit.perSecond), name .. " 회복 직전")
				now += (1 / limit.perSecond) * 0.02
				T.truthy(limiter:allow(1, name, limit.burst, limit.perSecond), name .. " 회복 직후")
			end
		end
	)

	T.test(
		"모든 Remote 의 한도가 말이 됨: burst ≥ 1, 초당 회복 > 0, 열매 따기·팔기 같은 UI 버튼은 burst ≥ 2",
		function()
			for name, limit in Remotes.RateLimits do
				T.truthy(limit.burst >= 1 and limit.perSecond > 0, name)
				T.truthy(limit.burst <= 20, name .. " burst 가 너무 큼")
			end
			for _, name in { "PickFruit", "SellPlant", "SkipGrowth", "FeedFruit", "PurchaseUpgrade", "UseTool" } do
				T.truthy(Remotes.RateLimits[name].burst >= 2, name)
			end
		end
	)

	T.test("오래 쉬어도 토큰이 burst 를 넘게 쌓이지 않음, 시간이 거꾸로 가도 안전", function()
		local now = 1000
		local limiter = RateLimiter.new(function()
			return now
		end)
		T.truthy(limiter:allow(1, "X", 2, 1))
		now = 1e9
		T.truthy(limiter:allow(1, "X", 2, 1))
		T.truthy(limiter:allow(1, "X", 2, 1))
		T.falsy(limiter:allow(1, "X", 2, 1))
		now = 5 -- 시계가 뒤로
		T.falsy(limiter:allow(1, "X", 2, 1))
	end)

	------------------------------------------------------------------
	T.suite("경계: 6판 정원 (성장 단계·건너뛰기·열매·먹이기)")

	T.test(
		"성장 단계 경계: 24.99% 새싹 / 25% 줄기 / 59.99% 줄기 / 60% 봉오리 / 99.99% 봉오리 / 100% 성체",
		function()
			T.eq(GardenRules.stage(0, 100), "sprout")
			T.eq(GardenRules.stage(24.99, 100), "sprout")
			T.eq(GardenRules.stage(25, 100), "stem")
			T.eq(GardenRules.stage(59.99, 100), "stem")
			T.eq(GardenRules.stage(60, 100), "bud")
			T.eq(GardenRules.stage(99.99, 100), "bud")
			T.eq(GardenRules.stage(100, 100), "adult")
			T.eq(GardenRules.stage(500, 100), "adult", "넘쳐도 성체")
			T.eq(GardenRules.stage(-5, 100), "sprout", "음수도 새싹")
			T.eq(GardenRules.stage(0, 0), "adult", "필요 시간 0 이면 바로 성체")
			T.eq(GardenRules.stageName("bud"), "봉오리")
			T.eq(GardenRules.stageName("모름"), "모름")
		end
	)

	T.test(
		"건너뛰기 가격: 분은 올림 (60초 = 1분, 60.01초 = 2분), 0초 이하·NaN 은 0, 모르는 등급은 배수 1",
		function()
			T.eq(GardenRules.skipCostForSeconds("common", 60), 10)
			T.eq(GardenRules.skipCostForSeconds("common", 60.01), 20)
			T.eq(GardenRules.skipCostForSeconds("common", 0.001), 10, "1초 미만도 1분")
			T.eq(GardenRules.skipCostForSeconds("common", 0), 0)
			T.eq(GardenRules.skipCostForSeconds("common", -5), 0)
			T.eq(GardenRules.skipCostForSeconds("common", 0 / 0), 0)
			T.eq(GardenRules.skipCostForSeconds("mythic", 120), 2 * 10 * 30)
			T.eq(GardenRules.skipCostForSeconds("모름", 60), 10)
			T.eq(GardenRules.skipSeconds(30, 100, "half"), 35)
			T.eq(GardenRules.skipSeconds(30, 100, "all"), 70)
			T.eq(GardenRules.skipSeconds(130, 100, "all"), 0)
		end
	)

	T.test("정원 칸 경계: 자라는 씨앗 + 성체 = 칸 수 - 1 이면 하나 더, 칸 수면 가득", function()
		T.truthy(GardenRules.hasRoom(3, 3, 1), "6/7")
		T.falsy(GardenRules.hasRoom(4, 3, 1), "7/7")
		T.falsy(GardenRules.hasRoom(0, 7, 1))
		T.truthy(GardenRules.hasRoom(0, 17, 11), "11레벨 18칸")
		T.falsy(GardenRules.hasRoom(10, 8, 11))
	end)

	T.test(
		"열매 맺기 경계: 간격 딱 되면 +1, 최대 5에서 멈추고 시간도 안 쌓임, dt 가 커도 한 번에 5까지만",
		function()
			local f, p = FruitRules.produce(0, 0, 29.99, 30)
			T.eq(f, 0)
			T.near(p, 29.99, 1e-9)
			f, p = FruitRules.produce(0, 0, 30, 30)
			T.eq(f, 1)
			T.eq(p, 0)
			f, p = FruitRules.produce(3, 10, 1e9, 30)
			T.eq(f, 5)
			T.eq(p, 0, "가득 차면 다음 열매 시간이 안 쌓임")
			f, p = FruitRules.produce(5, 0, 100, 30)
			T.eq(f, 5)
			T.eq(p, 0)
			f, p = FruitRules.produce(2, 5, -10, 30)
			T.eq(f, 2, "거꾸로 가는 시간은 무시")
			T.eq(p, 5)
			f = FruitRules.produce(2, 5, 100, math.huge)
			T.eq(f, 2, "모르는 식물(간격 inf)은 안 맺음")
			f = FruitRules.produce(2, 5, 0 / 0, 30)
			T.eq(f, 2, "NaN dt")
		end
	)

	T.test(
		"열매 가방 경계: 자리만큼만 넣고, 1개 꺼내면 평균 값이 빠지고, 다 꺼내면 칸이 사라짐",
		function()
			local bag = {}
			T.eq(FruitRules.addToBag(bag, "sprout_daisy", Config.FRUIT_BAG_MAX - 1, 10), Config.FRUIT_BAG_MAX - 1)
			T.eq(FruitRules.addToBag(bag, "owl_oak", 5, 180), 1, "1자리만 남음")
			T.eq(FruitRules.bagRoom(bag), 0)
			T.eq(FruitRules.addToBag(bag, "owl_oak", 5, 180), 0)
			T.eq(FruitRules.bagCount(bag), Config.FRUIT_BAG_MAX)
			T.eq(FruitRules.takeOne(bag, "owl_oak"), 180)
			T.eq(bag.owl_oak, nil, "다 꺼내면 칸이 사라짐")
			T.eq(FruitRules.takeOne(bag, "owl_oak"), nil)
			T.eq(FruitRules.addToBag({}, "x", -3, 10), 0)
			T.eq(FruitRules.addToBag({}, "x", 2.7, 10), 2, "소수는 내림")
		end
	)

	T.test(
		"먹이기 확률 경계: 합은 0.9 를 넘지 않음, 더 붙을 것이 없으면 0, 무지개 가진 식물은 자연 돌연변이가 더 안 붙음",
		function()
			for _, plant in Loader.require("ReplicatedStorage/Shared/Data/Plants").list do
				local chance = FruitRules.feedChance(plant.id, {})
				T.truthy(chance > 0 and chance <= 0.9 + 1e-12, plant.id .. " " .. chance)
			end
			T.eq(FruitRules.feedChance("sprout_daisy", { "rainbow", "frozen" }), 0)
			T.eq(#FruitRules.feedOptions("없는식물", {}), 0)
			for _, option in FruitRules.feedOptions("ghost_lily", { "rainbow" }) do
				T.truthy(option.id ~= "golden" and option.id ~= "rainbow", option.id)
			end
			T.falsy(FruitRules.canGain({ "golden" }, "silver"), "황금 → 실버는 내려감")
			T.truthy(FruitRules.canGain({ "silver" }, "golden"))
			T.falsy(FruitRules.canGain({ "burning" }, "frozen"), "원소는 하나만")
			T.falsy(FruitRules.canGain({}, "모름"))
		end
	)

	------------------------------------------------------------------
	T.suite("경계: 튜토리얼·치트 경고 (순수 규칙)")

	T.test(
		"튜토리얼: 저장된 단계 값 경계 (0·7·2.9·NaN·글자 → 1~6 정수, 없으면 fallback)",
		function()
			T.eq(TutorialRules.clean(0, 6), 1)
			T.eq(TutorialRules.clean(-3, 6), 1)
			T.eq(TutorialRules.clean(7, 1), 6)
			T.eq(TutorialRules.clean(2.9, 1), 2)
			T.eq(TutorialRules.clean(0 / 0, 4), 4)
			T.eq(TutorialRules.clean("3", 6), 6)
			T.eq(TutorialRules.clean(nil, 6), 6)
			T.eq(TutorialRules.clean(math.huge, 1), 6)
		end
	)

	T.test("튜토리얼: 5단계는 팔아야 끝남, 끝난 뒤에는 어떤 일도 단계를 안 바꿈", function()
		local ctx = { carrying = false, bagEggs = 0, placedEggs = 0, plants = 1, fruits = 0 }
		T.eq(TutorialRules.advance(5, "grown", ctx), 5)
		T.eq(TutorialRules.advance(5, "sell", ctx), 6)
		for _, event in { "steal", "lost", "deliver", "place", "unplace", "grown", "sell" } do
			T.eq(TutorialRules.advance(6, event, ctx), 6, event)
			T.eq(TutorialRules.advance(99, event, ctx), 99, event)
		end
		T.eq(TutorialRules.advance(3, "해킹" :: any, ctx), 3, "모르는 일은 무시")
		T.eq(TutorialRules.advance(5, "equip" :: any, ctx), 5, "5판 장착 일은 무시")
	end)

	T.test(
		"치트 경고: 정확히 5번째에 Kick, 120초에 하나씩 줄고 줄어든 뒤에는 처음부터",
		function()
			local w = MoveCheck.newWarnings(0)
			local kicks = {}
			for i = 1, 5 do
				local count, kick = MoveCheck.addWarning(w, i)
				kicks[i] = kick
				T.eq(count, i)
			end
			T.eq(table.concat({ tostring(kicks[1]), tostring(kicks[4]), tostring(kicks[5]) }, ","), "false,false,true")
			-- 119초: 아직 안 줄음, 121초: 1개 줄음
			local d = MoveCheck.newWarnings(0)
			MoveCheck.addWarning(d, 0)
			MoveCheck.addWarning(d, 0)
			MoveCheck.decay(d, 119)
			T.eq(d.count, 2)
			MoveCheck.decay(d, 121)
			T.eq(d.count, 1)
			-- 줄어든 시각 기준으로 다음 120초 (240초 때 0)
			MoveCheck.decay(d, 239)
			T.eq(d.count, 1)
			MoveCheck.decay(d, 241)
			T.eq(d.count, 0)
		end
	)

	T.test("치트 이동 허용 거리: 1초 54(WalkSpeed 16), 최대 150 이면 255 — 경계 포함", function()
		T.falsy(MoveCheck.isViolation(54, 16, 1))
		T.truthy(MoveCheck.isViolation(54.0001, 16, 1))
		T.falsy(MoveCheck.isViolation(255, 150, 1), "2판 수정 최대 걷기 150 → 255")
		T.truthy(MoveCheck.isViolation(255.01, 150, 1))
		T.falsy(MoveCheck.isViolation(0, 0, 0))
	end)

	------------------------------------------------------------------
	T.suite("경계: 구역 판정·낮밤")

	T.test("구역 경계 ±0.001 (2판 z 범위): 앞 구역/뒤 구역, 허브 경계 z = 0, 맵 끝", function()
		local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
		for i, b in Biomes.list do
			local zMin = (i - 1) * MapLayout.BIOME_LENGTH
			T.eq(MapLayout.zoneAt(zMin), b.id, b.id .. " 시작선은 이 구역")
			T.eq(MapLayout.zoneAt(zMin + 0.001), b.id)
			T.eq(MapLayout.zoneAt(zMin - 0.001), if i == 1 then "hub" else Biomes.list[i - 1].id, b.id .. " 바로 앞")
			-- 잡힘 규칙: 경계 바로 앞(앞 구역)에서 잡히면 그 자리, 경계 안이면 둥지로
			T.eq(EggRules.dropOutcome("guard", b.id, MapLayout.zoneAt(zMin)), "ReturnToNest")
			T.eq(EggRules.dropOutcome("guard", b.id, MapLayout.zoneAt(zMin - 0.001)), "DropHere")
		end
		T.truthy(MapLayout.isInHub({ X = 0, Z = -0.001 }))
		T.falsy(MapLayout.isInHub({ X = 0, Z = 0 }))
		T.eq(MapLayout.zoneAt(MapLayout.MAP_END_Z - 0.001), "bug_dimension", "7판: 맨 끝 = 18 버그 차원")
		T.eq(MapLayout.MAP_END_Z, 4320)
		T.eq(MapLayout.zoneAt(3600 - 0.001), "haunted_castle", "15 유령 성 자리는 그대로")
		T.eq(MapLayout.zoneAt(3600), "hacker_lab")
		T.eq(MapLayout.zoneAt(MapLayout.MAP_END_Z), nil)
	end)

	T.test("낮 경계: 285초 딱 되면 밤, 295초 딱 되면 대기, 298초면 다음 낮", function()
		T.eq((Cycle.phaseAt(284.999)), "Day")
		T.eq((Cycle.phaseAt(285)), "Night")
		T.eq((Cycle.phaseAt(294.999)), "Night")
		T.eq((Cycle.phaseAt(295)), "Intermission")
		T.eq((Cycle.phaseAt(297.999)), "Intermission")
		T.eq((Cycle.phaseAt(298)), "Day")
		T.truthy(Cycle.canStealEggs("Day"))
		T.falsy(Cycle.canStealEggs("Night"))
		T.falsy(Cycle.canStealEggs("Intermission"))
	end)

	T.test("둥지 알 추첨: 크기 확률 70/20/8/2 의 누적 경계에서 정확히 바뀜", function()
		T.eq(EggRoll.rollSize(T.constant(0.0)), "normal")
		T.eq(EggRoll.rollSize(T.constant(0.6999)), "normal")
		T.eq(EggRoll.rollSize(T.constant(0.70)), "big")
		T.eq(EggRoll.rollSize(T.constant(0.8999)), "big")
		T.eq(EggRoll.rollSize(T.constant(0.90)), "huge")
		T.eq(EggRoll.rollSize(T.constant(0.9799)), "huge")
		T.eq(EggRoll.rollSize(T.constant(0.98)), "giant")
		T.eq(EggRoll.rollSize(T.constant(0.999999)), "giant")
	end)
end
