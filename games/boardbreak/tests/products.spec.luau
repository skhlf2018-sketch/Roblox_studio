--!nocheck
-- Products: 힘 배수 순서대로 열림 (2배를 사야 4배) · 가진 패스로 배수 (boostFromOwnedPasses) · 이상한 id
return function(T, Loader)
	local Products = Loader.require("ReplicatedStorage/Shared/Data/Products")

	T.suite("products")

	T.test("nextPowerBoost · powerBoostState", function()
		T.eq(Products.nextPowerBoost(1).key, "power_2")
		T.eq(Products.nextPowerBoost(2).key, "power_4")
		T.eq(Products.nextPowerBoost(1024).key, "power_2048")
		T.eq(Products.nextPowerBoost(2048), nil)
		T.eq(Products.nextPowerBoost(0 / 0).key, "power_2", "NaN = 1")
		T.eq(Products.powerBoostState(4, 4), "active")
		T.eq(Products.powerBoostState(4, 2), "owned")
		T.eq(Products.powerBoostState(4, 8), "buy")
		T.eq(Products.powerBoostState(4, 16), "locked")
	end)

	T.test("powerBoostOutcome: 순서 맞으면 그 배수, 안 맞으면 그 로벅스만큼 차례로", function()
		local p = Products.get
		T.eq(Products.powerBoostOutcome(1, p("power_2")), 2)
		T.eq(Products.powerBoostOutcome(2, p("power_4")), 4)
		-- 1 에서 power_8 (8 R$): 2(2) + 4(4) = 6 까지 → 4배 (8배로 건너뛰지 않음)
		T.eq(Products.powerBoostOutcome(1, p("power_8")), 4)
		T.eq(Products.powerBoostOutcome(1, p("power_2048")), 1024, "2048 R$ 로 1~1024 까지")
		T.eq(Products.powerBoostOutcome(8, p("power_2")), 8, "가진 것보다 작은 것 = 그대로")
	end)

	T.test("boostFromOwnedPasses: 첫 게임과 같은 예", function()
		T.eq(Products.boostFromOwnedPasses({ 2, 4, 8 }), 8)
		T.eq(Products.boostFromOwnedPasses({ 2048 }), 1024)
		T.eq(Products.boostFromOwnedPasses({ 4 }), 2)
		T.eq(Products.boostFromOwnedPasses({}), 1)
		T.eq(Products.boostFromOwnedPasses({ 2, 8 }), 4)
		T.eq(Products.boostFromOwnedPasses({ 2, 2, 2 }), 2, "중복")
		T.eq(Products.boostFromOwnedPasses({ 0 / 0, 3, 2 }), 2, "NaN · 모르는 값")
		local all = {}
		for _, v in Products.BOOST_MULTIPLIERS do
			table.insert(all, v)
		end
		T.eq(Products.boostFromOwnedPasses(all), 2048, "다 가짐")
	end)

	T.test(
		"이상한 id (0 · 음수 · NaN · ±무한 · 소수 · 글자 · 모르는 id) 이면 byPassId / byProductId 는 nil (영수증으로 패스를 주지 않음)",
		function()
			T.eq(Products.byPassId(0), nil)
			T.eq(Products.byProductId(0), nil)
			T.eq(Products.byProductId(-1), nil)
			T.eq(Products.byPassId(0 / 0), nil)
			for _, id in { -1, math.huge, -math.huge, 1.5, 12345, "2092088488", {}, true } do
				T.eq(Products.byPassId(id), nil, "byPassId " .. tostring(id))
			end
			local real = Products.get("power_2").productId
			T.eq(Products.byPassId(real + 0.5), nil, "소수")
			T.eq(Products.byPassId(real + 1), nil, "남의 패스 id (한 칸 옆)")
			T.eq(Products.byProductId(real), nil, "패스 id 로 개발자 상품 영수증 안 됨")
			T.truthy(Products.isValidBoost(1))
			T.truthy(Products.isValidBoost(2048))
			T.falsy(Products.isValidBoost(3))
			T.eq(Products.get(nil), nil)
		end
	)
end
