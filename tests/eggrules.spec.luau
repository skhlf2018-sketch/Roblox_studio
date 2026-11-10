--!nocheck
-- 잡혔을 때 알 처리 규칙 (2026-11-10 사장님: 그 씨앗의 구역 안에서 놓치면 원인과 상관없이 바로 둥지, 밖이면 그 자리 → 5초 뒤 둥지).
-- 2판: "구역 안" = MapLayout.zoneAt(z) 가 알의 구역

return function(T, Loader)
	local EggRules = Loader.require("ReplicatedStorage/Shared/EggRules")
	local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")

	T.suite("EggRules")

	local zone = { centerX = 100, centerZ = 200, halfX = 85, halfZ = 85 }

	T.test("구역 사각형 안/밖 판정 (경계 포함, 1판 도우미)", function()
		T.truthy(EggRules.isInsideZone(zone, 100, 200))
		T.truthy(EggRules.isInsideZone(zone, 185, 285))
		T.falsy(EggRules.isInsideZone(zone, 185.1, 200))
		T.falsy(EggRules.isInsideZone(zone, 100, 114.9))
	end)

	T.test("경비한테 알의 구역 안에서 잡힘 → 둥지로", function()
		T.eq(EggRules.dropOutcome("guard", "lake", "lake"), "ReturnToNest")
		T.eq(EggRules.dropOutcome("guard", "lake", MapLayout.zoneAt(300)), "ReturnToNest")
	end)

	T.test("경비한테 알의 구역 밖(앞 구역·허브·맵 밖)에서 잡힘 → 그 자리", function()
		T.eq(EggRules.dropOutcome("guard", "lake", "forest"), "DropHere", "바로 앞 구역이어도")
		T.eq(EggRules.dropOutcome("guard", "lake", "hub"), "DropHere")
		T.eq(EggRules.dropOutcome("guard", "lake", nil), "DropHere")
		T.eq(EggRules.dropOutcome("guard", "lake", MapLayout.zoneAt(239.9)), "DropHere", "경계 바로 앞")
	end)

	T.test(
		"다른 플레이어(방망이/곰덫)한테 당함 → 구역 안이면 바로 둥지, 밖이면 그 자리 (2026-11-10)",
		function()
			T.eq(EggRules.dropOutcome("player", "lake", "lake"), "ReturnToNest")
			T.eq(EggRules.dropOutcome("player", "lake", "forest"), "DropHere", "구역 밖")
			T.eq(EggRules.dropOutcome("player", "lake", "hub"), "DropHere")
			T.eq(EggRules.dropOutcome("player", "lake", nil), "DropHere")
		end
	)

	T.test("스스로 버림(DropEgg) → 구역 안이면 바로 둥지, 밖이면 그 자리 (2026-11-10)", function()
		T.eq(EggRules.dropOutcome("drop", "lake", "lake"), "ReturnToNest")
		T.eq(EggRules.dropOutcome("drop", "lake", "forest"), "DropHere", "구역 밖")
		T.eq(EggRules.dropOutcome("drop", "lake", "hub"), "DropHere")
	end)

	T.test(
		"죽거나 나가면 어떤 원인이든 같은 규칙 (구역 안 → 둥지, 밖 → 그 자리)",
		function()
			T.eq(EggRules.dropOutcome("death", "forest", "forest"), "ReturnToNest")
			T.eq(EggRules.dropOutcome("leave", "forest", "lake"), "DropHere")
		end
	)

	T.test("알의 구역 정보가 없으면 그 자리", function()
		T.eq(EggRules.dropOutcome("guard", nil, "forest"), "DropHere")
	end)

	T.test("원 반경 판정", function()
		T.truthy(EggRules.isWithinRadius(0, 0, 10, 6, 8))
		T.falsy(EggRules.isWithinRadius(0, 0, 10, 7, 8))
	end)
end
