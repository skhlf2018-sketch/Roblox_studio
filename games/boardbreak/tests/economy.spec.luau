--!nocheck
-- Economy: 들 때 힘 · 칠 때 피해 · 깬 돈 · 1e60 상한 · NaN/음수/무한 방어
return function(T, Loader)
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
	local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")
	local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")

	T.suite("economy")

	T.test("들 때 힘 = powerPerRep × PowerBoost", function()
		T.eq(Economy.trainGain(1, 1), 1)
		T.eq(Economy.trainGain(2, 1), Dumbbells.get(2).powerPerRep)
		T.eq(Economy.trainGain(2, 8), Dumbbells.get(2).powerPerRep * 8)
		T.eq(Economy.trainGain(20, 2048), Dumbbells.get(20).powerPerRep * 2048)
	end)

	T.test("이상한 아령·배수는 기본값 (아령 1 · 배수 1)", function()
		T.eq(Economy.trainGain(0, 1), 1, "아령 0")
		T.eq(Economy.trainGain(99, 1), 1, "아령 99")
		T.eq(Economy.trainGain(0 / 0, 1), 1, "아령 NaN")
		T.eq(Economy.trainGain(1, 3), 1, "배수 3 (표에 없음)")
		T.eq(Economy.trainGain(1, 0 / 0), 1, "배수 NaN")
		T.eq(Economy.trainGain(1, math.huge), 1, "배수 무한")
		T.eq(Economy.trainGain(1, -2), 1, "배수 음수")
		T.eq(Economy.boost(4096), 1, "4096 은 없음")
		T.eq(Economy.boost(2048), 2048, "2048")
	end)

	T.test("칠 때 피해 = 힘 × PowerBoost (들 때와 칠 때 둘 다 곱함)", function()
		T.eq(Economy.hitDamage(100, 1), 100)
		T.eq(Economy.hitDamage(100, 4), 400)
		T.eq(Economy.hitDamage(0 / 0, 4), 0, "NaN 힘")
		T.eq(Economy.hitDamage(-5, 4), 0, "음수 힘")
		T.eq(Economy.hitDamage(math.huge, 2), 0, "무한 힘")
		T.eq(Economy.hitDamage(1e59, 2048), 1e60, "1e60 에서 멈춤")
	end)

	T.test("깬 돈 = reward × 띠 배율 × (돈 2배면 2)", function()
		T.eq(Economy.breakReward(3, 1, false), 3, "솜 흰 띠")
		T.eq(Economy.breakReward(3, 1, true), 6, "돈 2배")
		T.eq(Economy.breakReward(100, 2, false), 100 * Belts.get(2).moneyMultiplier, "노랑 띠")
		T.eq(
			Economy.breakReward(100, Belts.COUNT, true),
			100 * Belts.get(Belts.COUNT).moneyMultiplier * 2,
			"그랜드 마스터 + 돈 2배"
		)
		T.eq(Economy.breakReward(100, 99, false), 100, "모르는 띠 = 배율 1")
		T.eq(Economy.breakReward(0 / 0, 1, false), 0, "NaN 값")
		T.eq(Economy.breakReward(1e60, Belts.COUNT, true), 1e60, "상한")
	end)

	T.test("더하기는 1e60 에서 멈춤, 이상한 값은 0 으로", function()
		T.eq(Economy.addPower(1e60, 1e60), 1e60)
		T.eq(Economy.addPower(5, 0 / 0), 5)
		T.eq(Economy.addPower(0 / 0, 5), 5)
		T.eq(Economy.addMoney(1e60, 1), 1e60)
		T.eq(Economy.addMoney(10, -5), 10, "음수 더하기 = 0")
		T.eq(Economy.addMoney(10, math.huge), 10, "무한 더하기 = 0")
		T.eq(Economy.clampPower("12"), 0, "글자")
		T.eq(Economy.sanitize(math.huge, 1e60), 0, "무한 → 0 (상한으로 바꾸지 않음)")
	end)

	T.test("hitsToBreak", function()
		T.eq(Economy.hitsToBreak(75, 5), 15)
		T.eq(Economy.hitsToBreak(75, 25), 3)
		T.eq(Economy.hitsToBreak(75, 1e9), 1)
		T.eq(Economy.hitsToBreak(75, 0), math.huge)
		T.eq(Economy.hitsToBreak(75, 0 / 0), math.huge)
	end)
end
