--!nocheck
-- 잡혔을 때 알 처리 규칙 (구역 안 → 둥지, 밖 → 그 자리)

return function(T, Loader)
	local EggRules = Loader.require("ReplicatedStorage/Shared/EggRules")

	T.suite("EggRules")

	local zone = { centerX = 100, centerZ = 200, halfX = 85, halfZ = 85 }

	T.test("구역 안/밖 판정 (경계 포함)", function()
		T.truthy(EggRules.isInsideZone(zone, 100, 200))
		T.truthy(EggRules.isInsideZone(zone, 185, 285))
		T.falsy(EggRules.isInsideZone(zone, 185.1, 200))
		T.falsy(EggRules.isInsideZone(zone, 100, 114.9))
	end)

	T.test("경비한테 구역 안에서 잡힘 → 둥지로", function()
		T.eq(EggRules.dropOutcome("guard", zone, 150, 250), "ReturnToNest")
	end)

	T.test("경비한테 구역 밖에서 잡힘 → 그 자리", function()
		T.eq(EggRules.dropOutcome("guard", zone, 300, 250), "DropHere")
	end)

	T.test("다른 플레이어(방망이/곰덫)한테 당함 → 구역 안이라도 그 자리", function()
		T.eq(EggRules.dropOutcome("player", zone, 150, 250), "DropHere")
	end)

	T.test("죽거나 나가면 경비와 같은 규칙", function()
		T.eq(EggRules.dropOutcome("death", zone, 150, 250), "ReturnToNest")
		T.eq(EggRules.dropOutcome("leave", zone, 999, 999), "DropHere")
	end)

	T.test("구역 정보가 없으면 그 자리", function()
		T.eq(EggRules.dropOutcome("guard", nil, 150, 250), "DropHere")
	end)

	T.test("추격 포기 반경 = halfSize × 2 × persistence", function()
		T.eq(EggRules.leashRadius(zone, 2), 170)
		T.eq(EggRules.leashRadius(zone, 2, 1.5), 255)
		T.truthy(EggRules.withinLeash(zone, 100 + 169, 200, 2))
		T.falsy(EggRules.withinLeash(zone, 100 + 171, 200, 2))
	end)

	T.test("원 반경 판정 (안전 구역)", function()
		T.truthy(EggRules.isWithinRadius(0, 0, 10, 6, 8))
		T.falsy(EggRules.isWithinRadius(0, 0, 10, 7, 8))
	end)
end
