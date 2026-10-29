--!nocheck
-- 6판 Economy: 열매 값·성장 시간·정원 칸·러닝머신·트레일·오프라인 성장 (자동 수입·장착·오프라인 수입은 없어짐)

return function(T, Loader)
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
	local Plants = Loader.require("ReplicatedStorage/Shared/Data/Plants")
	local Upgrades = Loader.require("ReplicatedStorage/Shared/Data/Upgrades")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")

	T.suite("Economy (6판)")

	T.test("열매 1개 값 = 식물 열매 값 × 크기 × 돌연변이 (5판 ×3 없음)", function()
		local daisy = Plants.get("sprout_daisy").fruitValue * 2 -- 10 × 초반 2배(일반, 사장님 2026-10-28)
		T.eq(Config.EARLY_COIN_MULTIPLIER.common, 2)
		T.eq(Config.EARLY_COIN_MULTIPLIER.uncommon, 2)
		T.eq(Economy.earlyCoinMultiplier("rare"), 1, "희귀부터는 그대로")
		T.eq(
			Economy.fruitValue("firefly_lily", "normal", {}),
			Plants.get("firefly_lily").fruitValue * Economy.earlyCoinMultiplier(Plants.get("firefly_lily").rarity)
		)
		T.eq(Economy.fruitValue("sprout_daisy", "normal", {}), daisy)
		T.eq(Economy.fruitValue("sprout_daisy", "big", { "golden" }), daisy * 1.5 * 2)
		T.eq(Economy.fruitValue("sprout_daisy", "giant", { "rainbow", "burning" }), daisy * 6 * 2.5 * 1.5)
		T.eq(Economy.fruitValue("없는식물", "normal", {}), 0)
		T.eq(Economy.recordFruitValue({ petId = "owl_oak", size = "huge", mutations = {} }), 180 * 3)
		T.eq(Economy.petIncome, nil, "5판 펫 수입 함수는 없어짐")
		T.eq(Economy.totalIncome, nil)
		T.eq(Economy.offlineIncome, nil)
	end)

	T.test(
		"열매 간격 = 표 간격 ÷ FRUIT_SPEED_MULTIPLIER(1.8) · 초당 코인 환산(표시용) = 열매 값 ÷ 간격",
		function()
			local p = Plants.get("firefly_lily")
			T.eq(Config.FRUIT_SPEED_MULTIPLIER, 1.8, "사장님 2026-10-28: 열매 1.8배 빨리")
			T.eq(Economy.fruitInterval("firefly_lily"), p.fruitIntervalSeconds / 1.8)
			T.eq(Economy.fruitInterval("없음"), math.huge)
			T.near(
				Economy.recordIncome({ petId = "firefly_lily", size = "normal", mutations = {} }),
				Economy.fruitValue("firefly_lily", "normal", {}) / Economy.fruitInterval("firefly_lily"),
				1e-12
			)
			T.eq(Economy.recordIncome({ petId = "없음", size = "normal", mutations = {} }), 0)
		end
	)

	T.test("돌연변이 중첩 곱 (황금 2 × 불 1.5 = 3, 무지개 2.5 × 번개 2 = 5)", function()
		T.near(Economy.mutationMultiplier({ "golden", "burning" }), 3, 1e-9)
		T.near(Economy.mutationMultiplier({ "rainbow", "shocked" }), 5, 1e-9)
		T.eq(Economy.mutationMultiplier({}), 1)
		T.eq(Economy.mutationMultiplier({ "모름" }), 1)
	end)

	T.test("돌연변이 조합 규칙: 자연 2개 불가, 원소 2개 불가, 자연 + 원소 가능", function()
		T.falsy(Economy.isValidMutationSet({ "silver", "golden" }))
		T.falsy(Economy.isValidMutationSet({ "frozen", "burning" }))
		T.truthy(Economy.isValidMutationSet({ "golden", "frozen" }))
		T.falsy(Economy.isValidMutationSet({ "bloom" }), "6판에 없는 돌연변이")
	end)

	T.test(
		"7판 성장 3배: 성장 시간 = Plants.growSeconds(표) ÷ 3 (hatchSeconds 는 별칭), 낮 1초 = 1, 밤 30배",
		function()
			T.eq(Config.GROWTH_SPEED_MULTIPLIER, 3)
			T.eq(Economy.growthSpeedMultiplier(), 3)
			T.eq(Economy.growSeconds("puppy_grass"), 1, "강아지풀 표 3초 → 1초")
			T.near(Economy.growSeconds("sprout_daisy"), 10 / 3, 1e-9)
			T.eq(Economy.growSeconds("crystal_snowdrop"), 1200, "전설 표 1시간 → 20분")
			T.eq(Economy.growSeconds("rune_rose"), 28800, "비밀 표 1일 → 8시간")
			T.near(Economy.growSeconds("rainbow_thunder_tree"), 7 * 86400 / 3, 1e-6, "슈퍼 표 7일")
			T.eq(Economy.growSeconds("static_world_tree"), 20 * 86400, "해커 글리치 표 60일 → 20일")
			T.eq(Economy.tableGrowSeconds("puppy_grass"), 3, "표 숫자는 그대로")
			T.eq(Economy.tableGrowSeconds("없는식물"), nil)
			T.near(Economy.hatchSeconds("sprout_daisy"), 10 / 3, 1e-9)
			T.eq(Economy.growSeconds("없는식물"), 1)
			for _, plant in Plants.list do
				T.near(Economy.growSeconds(plant.id) * 3, plant.growSeconds, 1e-6, plant.id .. " ÷3")
			end
			T.eq(Economy.remainingSeconds(0, 10, Economy.growthRate(false, false)), 10)
			T.near(Economy.remainingSeconds(0, 10, Economy.growthRate(true, false)), 1 / 3, 1e-9)
			T.eq(
				Economy.remainingSeconds(0, 300, Economy.growthRate(true, false)),
				10,
				"희귀 5분은 밤 10초 내내"
			)
		end
	)

	T.test(
		"7판 성장 3배는 밤 30배와 곱: 비밀 룬 장미(표 1일) = 낮 8시간 · 밤 16분, 타이머·건너뛰기 값도 ÷3 시간 기준, 열매는 그대로",
		function()
			local GardenRules = Loader.require("ReplicatedStorage/Shared/GardenRules")
			local required = Economy.growSeconds("rune_rose")
			T.eq(required, 8 * 3600)
			T.eq(Economy.remainingSeconds(0, required, Economy.growthRate(false, false)), 8 * 3600)
			T.eq(Economy.remainingSeconds(0, required, Economy.growthRate(true, false)), 16 * 60)
			T.near(
				Economy.remainingSeconds(0, required, Economy.growthRate(true, false)) * 90,
				86400,
				1e-6,
				"밤이면 표 시간의 1/90"
			)
			T.eq(Economy.timerSeconds(0, required), 8 * 3600, "타이머 = ÷3 된 남은 시간")
			T.eq(GardenRules.skipCost("rune_rose", 0, required, "all"), 480 * 10 * 100, "남은 실제 480분")
			T.eq(GardenRules.skipCost("rune_rose", 0, required, "half"), 240 * 10 * 100)
			T.eq(GardenRules.stage(required * 0.3, required), "stem", "단계(%)도 ÷3 된 Required 기준")
			T.near(Economy.fruitInterval("rune_rose"), 16 / 1.8, 1e-9, "열매 간격은 3배와 상관없음")
			T.eq(Economy.fruitValue("rune_rose", "normal", {}), 5e6, "열매 값도 그대로")
		end
	)

	T.test("성장 속도: 밤 30배, 게임패스 2배, 둘 다 60배", function()
		T.eq(Economy.growthRate(false, false), 1)
		T.eq(Economy.growthRate(true, false), 30)
		T.eq(Economy.growthRate(false, true), 2)
		T.eq(Economy.growthRate(true, true), 60)
	end)

	T.test("성장 진행: 밤 10초면 300초만큼 자람, 필요량에서 멈춤 (= 성체)", function()
		local p, ready = Economy.advanceIncubation(0, 1800, 10, 30)
		T.eq(p, 300)
		T.falsy(ready)
		p, ready = Economy.advanceIncubation(1790, 1800, 1, 30)
		T.eq(p, 1800)
		T.truthy(ready)
		T.eq(Economy.remainingSeconds(900, 1800, 30), 30)
		T.eq(Economy.timerSeconds(1700, 1800), 100)
	end)

	T.test("정원 칸 (5판 우리 칸 숫자 그대로) / 다음 비용", function()
		T.eq(Economy.penSlots(1), 7)
		T.eq(Economy.penSlots(11), 18)
		T.eq(Economy.penSlots(99), 18)
		T.eq(Economy.nextPenCost(1), 1000)
		T.eq(Economy.nextPenCost(11), nil)
	end)

	T.test(
		"러닝머신: 잠김 0, 걸음당 속도 × 러닝머신 배율(4) × 초당 걸음, 최대 20레벨 = 정확히 1초 1,000,000",
		function()
			local k = Config.TREADMILL_MULTIPLIER * Config.TREADMILL_STEPS_PER_SECOND
			T.eq(Config.TREADMILL_MULTIPLIER, 4)
			T.eq(Economy.treadmillGainPerSecond(0), 0)
			T.eq(Economy.treadmillGainPerSecond(1), 8, "1레벨 8/초 (5판 6/초 근처)")
			T.eq(Economy.treadmillGainPerSecond(1), 2 * k)
			T.eq(Economy.treadmillGainPerSecond(10), 2000 * k)
			T.eq(Economy.treadmillGainPerSecond(20), 1000000, "부동소수 오차 없이 1M")
			T.eq(Economy.treadmillGainPerSecond(99), 1000000, "최대 레벨 위로는 그대로")
			T.eq(Economy.treadmillGainPerSecond(10, 2), 4000 * k)
			T.eq(Economy.nextTreadmillCost(0), 1000)
			T.eq(Economy.nextTreadmillCost(10), 3e15)
			T.eq(Economy.nextTreadmillCost(19), 60e18)
			T.eq(Economy.nextTreadmillCost(20), nil)
			local Format = Loader.require("ReplicatedStorage/Shared/Format")
			T.eq(Format.number(60e18), "60Qi", "Qi 단위 표시")
			T.eq(Format.number(2.2e18), "2.2Qi")
			T.eq(Format.number(1e21), "1Sx")
		end
	)

	T.test("트레일: 가장 높은 배율 하나만 (중첩 아님)", function()
		T.eq(Economy.bestTrailMultiplier({}), 1)
		T.eq(Economy.bestTrailMultiplier({ "grey", "blue", "green" }), 2.5)
		T.eq(Economy.bestTrailMultiplier({ "모름" }), 1)
	end)

	T.test("트레일: 장착한 것의 배율만 (none·모름 = 1), 최고 트레일 id", function()
		T.eq(Economy.trailMultiplier("blue"), 2.5)
		T.eq(Economy.trailMultiplier("moonbloom"), 20)
		T.eq(Economy.trailMultiplier("super_ultradivine"), 100, "사장님 2026-10-28: 트레일 16개")
		T.eq(#Upgrades.Trails, 16)
		T.eq(
			Economy.treadmillGainPerSecond(20, Economy.trailMultiplier("moonbloom")),
			20e6,
			"러닝머신 이득 × 트레일 배율"
		)
		T.eq(Economy.trailMultiplier("none"), 1)
		T.eq(Economy.trailMultiplier("모름"), 1)
		T.eq(Economy.trailMultiplier(nil), 1)
		T.eq(Economy.bestTrailId({}), "none")
		T.eq(Economy.bestTrailId({ "grey", "blue", "green" }), "blue")
		T.eq(Economy.bestTrailId({ "모름", "grey" }), "grey")
		T.eq(Economy.bestTrailId({ "모름" }), "none")
	end)

	T.test("오프라인 성장 시간: 차이, 상한 24시간, 시계 역행·첫 접속 0", function()
		T.eq(Economy.offlineGrowthSeconds(1000, 1000 + 3600), 3600)
		T.eq(Economy.offlineGrowthSeconds(1000, 1000 + 10 * 86400), 86400)
		T.eq(Economy.offlineGrowthSeconds(5000, 1000), 0)
		T.eq(Economy.offlineGrowthSeconds(0, 1000), 0)
		T.eq(Config.OFFLINE_GROWTH_CAP_SECONDS, 86400)
	end)
end
