--!nocheck
-- 수입·부화 시간·러닝머신·트레일·오프라인 수입

return function(T, Loader)
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")

	T.suite("Economy")

	T.test("펫 수입 = 기본 × 3 × 크기 × 돌연변이", function()
		T.eq(Economy.petIncome("chicken", "normal", {}), 3)
		T.eq(Economy.petIncome("chicken", "big", { "golden" }), 1 * 3 * 1.5 * 2)
		T.eq(Economy.petIncome("brr_brr_patapim", "giant", {}), 1800 * 3 * 6)
		T.eq(Economy.petIncome("없는펫", "normal", {}), 0)
	end)

	T.test("돌연변이 중첩 곱 (균열 2.75 × 혼란 2.75 = 7.5625)", function()
		T.near(Economy.mutationMultiplier({ "fractured", "chaos" }), 7.5625, 1e-9)
		T.near(Economy.mutationMultiplier({ "rainbow", "spirit_bloom" }), 7.5, 1e-9)
		T.eq(Economy.mutationMultiplier({}), 1)
		T.eq(Economy.mutationMultiplier({ "모름" }), 1)
	end)

	T.test("돌연변이 조합 규칙: 자연 돌연변이 2개 불가, 자연+블룸 가능", function()
		T.falsy(Economy.isValidMutationSet({ "silver", "golden" }))
		T.truthy(Economy.isValidMutationSet({ "golden", "bloom" }))
		T.falsy(Economy.isValidMutationSet({ "bloom", "spirit_bloom" }))
		T.truthy(Economy.isValidMutationSet({ "fractured", "chaos", "parasite" }))
	end)

	T.test("장착된 펫만 합산, 중복 uid 는 한 번만", function()
		local pets = {
			{ uid = "p1", petId = "chicken", size = "normal", mutations = {} },
			{ uid = "p2", petId = "dog", size = "normal", mutations = {} },
			{ uid = "p3", petId = "bear", size = "normal", mutations = {} },
		}
		T.eq(Economy.totalIncome(pets, { "p1", "p2" }), 3 + 6)
		T.eq(Economy.totalIncome(pets, { "p1", "p1", "없음" }), 3)
		T.eq(Economy.totalIncome(pets, { "p3" }, 2), 240 * 3 * 2)
	end)

	T.test("Equip Best: 수입 높은 순으로 칸 수만큼", function()
		local pets = {
			{ uid = "p1", petId = "chicken", size = "normal", mutations = {} },
			{ uid = "p2", petId = "bear", size = "normal", mutations = {} },
			{ uid = "p3", petId = "chicken", size = "giant", mutations = { "rainbow" } }, -- 1*3*6*2.5 = 45
			{ uid = "p4", petId = "dog", size = "normal", mutations = {} },
		}
		local best = Economy.bestEquipSet(pets, 2)
		T.eq(#best, 2)
		T.eq(best[1], "p2")
		T.eq(best[2], "p3")
		T.eq(#Economy.bestEquipSet(pets, 10), 4)
	end)

	T.test("부화 시간 = 원본 ÷ 3", function()
		T.near(Economy.hatchSeconds("chicken"), 10 / 3, 1e-9)
		T.eq(Economy.hatchSeconds("ghost_king"), 86400 / 3)
		T.eq(Economy.hatchSeconds("king_snake"), 1800)
	end)

	T.test("성장 속도: 밤 30배, 게임패스 2배, 둘 다 60배", function()
		T.eq(Economy.growthRate(false, false), 1)
		T.eq(Economy.growthRate(true, false), 30)
		T.eq(Economy.growthRate(false, true), 2)
		T.eq(Economy.growthRate(true, true), 60)
	end)

	T.test("부화 진행: 밤 10초면 300초만큼 자람, 필요량에서 멈춤", function()
		local p, ready = Economy.advanceIncubation(0, 1800, 10, 30)
		T.eq(p, 300)
		T.falsy(ready)
		p, ready = Economy.advanceIncubation(1790, 1800, 1, 30)
		T.eq(p, 1800)
		T.truthy(ready)
		T.eq(Economy.remainingSeconds(900, 1800, 30), 30)
	end)

	T.test("우리 칸 / 다음 비용", function()
		T.eq(Economy.penSlots(1), 7)
		T.eq(Economy.penSlots(11), 18)
		T.eq(Economy.penSlots(99), 18)
		T.eq(Economy.nextPenCost(1), 1000)
		T.eq(Economy.nextPenCost(11), nil)
	end)

	T.test("러닝머신: 잠김 0, 1레벨 2×3=6/초, 10레벨 2000×3=6000/초", function()
		T.eq(Economy.treadmillGainPerSecond(0), 0)
		T.eq(Economy.treadmillGainPerSecond(1), 6)
		T.eq(Economy.treadmillGainPerSecond(10), 6000)
		T.eq(Economy.treadmillGainPerSecond(10, 2), 12000)
		T.eq(Economy.nextTreadmillCost(0), 1000)
		T.eq(Economy.nextTreadmillCost(10), nil)
	end)

	T.test("트레일: 가장 높은 배율 하나만 (중첩 아님)", function()
		T.eq(Economy.bestTrailMultiplier({}), 1)
		T.eq(Economy.bestTrailMultiplier({ "grey", "blue", "green" }), 2.5)
		T.eq(Economy.bestTrailMultiplier({ "모름" }), 1)
	end)

	T.test("오프라인 수입: 차이 × 초당 수입, 상한 24시간, 시계 역행 0", function()
		local amount, seconds = Economy.offlineIncome(100, 1000, 1000 + 3600)
		T.eq(amount, 360000)
		T.eq(seconds, 3600)
		amount, seconds = Economy.offlineIncome(100, 1000, 1000 + 10 * 86400)
		T.eq(seconds, 86400)
		T.eq(amount, 8640000)
		amount = Economy.offlineIncome(100, 5000, 1000)
		T.eq(amount, 0)
		amount = Economy.offlineIncome(100, 0, 1000) -- 첫 접속
		T.eq(amount, 0)
	end)
end
