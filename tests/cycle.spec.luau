--!nocheck
-- 낮/밤/대기 주기

return function(T, Loader)
	local Cycle = Loader.require("ReplicatedStorage/Shared/Cycle")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")

	T.suite("Cycle")

	T.test("낮 285 → 밤 10 → 대기 3 → 낮", function()
		T.eq(Cycle.duration("Day"), 285)
		T.eq(Cycle.duration("Night"), 10)
		T.eq(Cycle.duration("Intermission"), 3)
		T.eq(Cycle.nextPhase("Day"), "Night")
		T.eq(Cycle.nextPhase("Night"), "Intermission")
		T.eq(Cycle.nextPhase("Intermission"), "Day")
		T.eq(Cycle.totalLength(), 298)
	end)

	T.test("경과 시간으로 상태 계산", function()
		local phase, left = Cycle.phaseAt(0)
		T.eq(phase, "Day")
		T.eq(left, 285)
		phase, left = Cycle.phaseAt(285)
		T.eq(phase, "Night")
		T.eq(left, 10)
		phase, left = Cycle.phaseAt(296)
		T.eq(phase, "Intermission")
		T.eq(left, 2)
		phase = Cycle.phaseAt(298 + 1)
		T.eq(phase, "Day")
	end)

	T.test("알 훔치기는 낮에만", function()
		T.truthy(Cycle.canStealEggs("Day"))
		T.falsy(Cycle.canStealEggs("Night"))
		T.falsy(Cycle.canStealEggs("Intermission"))
	end)

	T.test("천사&악마: 주기마다 천국/지옥 번갈아", function()
		local ad = Biomes.get("angels_demons")
		T.eq(Biomes.sideForCycle(ad, 1), "light")
		T.eq(Biomes.sideForCycle(ad, 2), "dark")
		T.eq(Biomes.sideForCycle(ad, 3), "light")
		T.eq(Biomes.sideForCycle(Biomes.get("forest"), 1), nil)
		T.eq(Biomes.guardDisplayName(ad, "dark"), "악마 장미") -- 6판: 식물 괴물
		T.eq(Biomes.guardDisplayName(Biomes.get("forest"), nil), "덥석 파리지옥")
	end)
end
