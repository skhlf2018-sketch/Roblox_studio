--!nocheck
--[[
	G 시리즈 — 스피드 배수 "순서대로 열림" 구멍 찾기 (사장님 2026-11-10: "스피드 배수는 2배를 사야 4배가 열리는 식")
	본부장이 바꾼 규칙: Products.nextTreadmillBoost · treadmillBoostState · treadmillBoostOutcome, ProductService.grant(treadmillBoost)
	  - 바로 다음 배수를 사면 그 배수 (남는 것 0)
	  - 순서가 안 맞으면 (잠긴 것을 위조로 삼 · 가진 것을 또 삼 · 두 번 누름) 산 R$ 만큼만: 다음 배수 가격부터 차례로 빼며 살 수 있는 만큼 올리고,
	    남은 R$ 는 속도 (× Config.PRODUCT_SPEED_PER_ROBUX)
	기준 계산(boostModel · priceSum)은 서버·Products 코드를 보지 않고 사장님 표(배수 = 가격 = 2·4·…·2048 R$)로 따로 적음.

	  G1 순수 함수 표 (12개 현재 배수 × 상품 11개 · 이상한 현재 배수 · 카드 상태와 서버 규칙이 같은 말을 함)
	  G2 진짜 ProductService.grant (순서대로 2→…→2048 · 132 조합 · 무작위 순서 · 낸 R$ 보존 · 상한 · /buy)
	  G3 진짜 processReceipt (순서대로 · 건너뛰기 · 같은 PurchaseId 재전송 · 저장 실패 · 두 번 누름 · 무작위 영수증)
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local S = "ReplicatedStorage/Shared/"
	local Products = Loader.require(S .. "Data/Products")
	local Config = Loader.require(S .. "Data/Config")
	local RATE = Config.PRODUCT_SPEED_PER_ROBUX

	local GRANTED = "ProductPurchaseDecision.PurchaseGranted"
	local NOT_YET = "ProductPurchaseDecision.NotProcessedYet"

	-- 사장님 표 (코드와 따로): 배수 = 로벅스 가격
	local MULTS = { 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048 }
	local SOLD = {}
	for _, m in MULTS do
		SOLD[m] = true
	end
	local CURRENTS = { 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048 }

	-- (from, to] 에 있는 배수들의 가격 합 (= from 배수에서 to 배수까지 순서대로 사는 데 드는 R$)
	local function priceSum(from, to)
		local sum = 0
		for _, m in MULTS do
			if m > from and m <= to then
				sum += m
			end
		end
		return sum
	end

	-- 부스트 상품 boost_v (v R$) 를 지금 배수 current 에서 샀을 때 (새 배수, 속도로 받을 R$) — 기준 계산
	local function boostModel(current, v)
		if current < 2048 and v == current * 2 then
			return v, 0
		end
		local budget, now = v, current
		while now < 2048 and now * 2 <= budget do
			budget -= now * 2
			now *= 2
		end
		return now, budget
	end

	------------------------------------------------------------------
	-- 세상 (진짜 Net · Sessions · Snapshot · Wallet · DataService · ProductService)
	------------------------------------------------------------------
	local function world()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Products = H.shared("Data/Products")
		w.Sessions = H.server("Sessions")
		w.DataService = H.server("Services/DataService")
		w.ProductService = H.server("Services/ProductService")
		w.PetService = H.server("Services/PetService")
		w.player = H.newPlayer(9801, "OrderBuyer")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		return w
	end

	local function inWorld(fn)
		local w = world()
		local ok, err = pcall(fn, w)
		w.H.uninstall()
		if not ok then
			error(err, 0)
		end
	end

	local function granted(w)
		local list = {}
		for _, args in w.H.sent(w.player, "ProductGranted") do
			table.insert(list, args[1])
		end
		return list
	end

	-- 상품 id 를 가짜로 붙임 (진짜 id 에 기대지 않으려고): byProductId 만 바꿔 끼움
	local function fakeConfigure(w)
		w.fakeIds = {}
		local byId = {}
		for i, product in w.Products.list do
			w.fakeIds[product.key] = 300000 + i
			byId[300000 + i] = product
		end
		w.Products.byProductId = function(id)
			return byId[id]
		end
	end

	local function receipt(w, key, purchaseId)
		return {
			PlayerId = w.player.UserId,
			ProductId = w.fakeIds[key],
			PurchaseId = purchaseId,
			CurrencySpent = 1,
		}
	end

	local function process(w, r)
		return w.H.run(function()
			return w.ProductService.processReceipt(r)
		end, 60)
	end

	local function enableSaving(w)
		w.DataService.start()
		w.session.saveEnabled = true
	end

	local function stored(w)
		local entry = w.H.store.data["player_" .. w.player.UserId]
		return entry and entry.data
	end

	local function boostProduct(multiplier)
		return Products.get("boost_" .. multiplier)
	end

	------------------------------------------------------------------
	T.suite(
		"G1 스피드 배수 순서 열림 — 순수 함수 (Products.treadmillBoostOutcome · nextTreadmillBoost · treadmillBoostState)"
	)

	T.test(
		"treadmillBoostOutcome 표: 현재 배수 12개 × 상품 11개 = 132 조합 — ① 새 배수 ≥ 지금 ② 새 배수는 파는 배수거나 1 ③ 올린 배수들의 가격 합 + 남은 R$ = 낸 R$ ④ 남은 R$ ≥ 0 정수 · 기준 모델과 같음 · 바로 다음일 때만 남는 것 0",
		function()
			local combos = 0
			for _, current in CURRENTS do
				for _, p in Products.treadmillBoosts do
					combos += 1
					local tag = string.format("×%d 에서 %s", current, p.key)
					local new, left = Products.treadmillBoostOutcome(current, p)
					T.truthy(new >= current, tag .. ": ① 배수는 내려가지 않음 (" .. tostring(new) .. ")")
					T.truthy(
						new == 1 or SOLD[new] == true,
						tag .. ": ② 새 배수는 파는 배수 (" .. tostring(new) .. ")"
					)
					T.truthy(new <= 2048, tag .. ": 2048 을 넘지 않음")
					T.truthy(
						left >= 0 and left == math.floor(left) and left <= p.robux,
						tag .. ": ④ 남은 R$ 0 이상 정수 (" .. tostring(left) .. ")"
					)
					T.eq(
						priceSum(current, new) + left,
						p.robux,
						tag .. ": ③ 올린 배수 가격 합 + 남은 R$ = 낸 R$"
					)
					local wantNew, wantLeft = boostModel(current, p.value)
					T.eq(new, wantNew, tag .. ": 기준 모델과 같은 배수")
					T.eq(left, wantLeft, tag .. ": 기준 모델과 같은 남은 R$")
					local isNext = current < 2048 and p.value == current * 2
					T.eq(left == 0, isNext, tag .. ": 남는 것이 0 인 건 바로 다음 배수를 산 때만")
					if isNext then
						T.eq(new, p.value, tag .. ": 바로 다음이면 그 배수")
					end
					if new == current then
						T.eq(left, p.robux, tag .. ": 하나도 못 올렸으면 낸 R$ 전부가 속도")
					end
					T.truthy(new > current or left > 0, tag .. ": 돈을 받았으니 언제나 뭔가 줌")
					if new < 2048 then
						T.truthy(
							left < new * 2,
							tag
								.. ": 살 수 있는 만큼은 다 올림 (남은 R$ 가 다음 배수 가격보다 작음)"
						)
					end
					-- N배가 되려면 2…N 가격 합 이상을 냈어야 함 (한 번 사서 건너뛸 수 없음)
					T.truthy(
						priceSum(1, new) <= priceSum(1, current) + p.robux,
						tag .. ": 건너뛰기로 공짜 배수 없음"
					)
				end
			end
			T.eq(combos, 132)
			-- 본부장 지시문의 예
			local function pair(current, key)
				local a, b = Products.treadmillBoostOutcome(current, Products.get(key))
				return a .. "," .. b
			end
			T.eq(pair(1, "boost_8"), "4,2", "지금 1 에서 boost_8 → 2(2)+4(4) = ×4, 남은 2")
			T.eq(pair(8, "boost_4"), "8,4", "지금 8 에서 boost_4 를 또 사면 ×8 그대로, 남은 4")
			T.eq(
				pair(8, "boost_2048"),
				"1024,16",
				"지금 8 에서 boost_2048 → 16+…+512(=1008) 다음 1024 까지 ×1024, 남은 16"
			)
			T.eq(pair(1, "boost_2048"), "1024,2", "지금 1 에서 boost_2048 → ×1024 (2048 아님), 남은 2")
			T.eq(
				pair(1024, "boost_2048"),
				"2048,0",
				"지금 1024 에서 boost_2048 은 바로 다음 → ×2048, 남는 것 0"
			)
			T.eq(pair(2048, "boost_2048"), "2048,2048", "이미 2048 이면 전부 속도")
		end
	)

	T.test(
		"이상한 현재 배수 (NaN · 음수 · 0 · 소수 · 무한 · 아주 큼): 세 함수 다 안 터지고, NaN·1 미만은 1 로 보고, 남은 R$ 는 0 ~ 낸 R$, 배수는 안 내려감",
		function()
			local odd = {
				0 / 0,
				-1,
				-1e300,
				-math.huge,
				0,
				0.5,
				1.5,
				2.5,
				3,
				3.9,
				1000,
				2047.9,
				2048.1,
				4096,
				1e300,
				2 ^ 53,
				math.huge,
			}
			for _, c in odd do
				local tag = "현재 " .. tostring(c)
				local okNext, nextProduct = pcall(Products.nextTreadmillBoost, c)
				T.truthy(okNext, tag .. ": nextTreadmillBoost 안 터짐")
				if okNext and nextProduct ~= nil then
					T.truthy(
						nextProduct.value > (if c == c and c >= 1 then c else 1),
						tag .. ": 다음 상품은 지금보다 큰 배수"
					)
				end
				local buys = 0
				for _, p in Products.treadmillBoosts do
					local ok, new, left = pcall(Products.treadmillBoostOutcome, c, p)
					T.truthy(ok, tag .. " " .. p.key .. ": treadmillBoostOutcome 안 터짐 " .. tostring(new))
					if ok then
						T.truthy(
							type(new) == "number" and new == new,
							tag .. " " .. p.key .. ": 새 배수가 숫자(NaN 아님)"
						)
						T.truthy(
							type(left) == "number" and left == left and left >= 0 and left <= p.robux,
							tag .. " " .. p.key .. ": 남은 R$ 0 ~ 낸 R$ (" .. tostring(left) .. ")"
						)
						if c ~= c or c < 1 then
							local n1, l1 = Products.treadmillBoostOutcome(1, p)
							T.eq(new, n1, tag .. " " .. p.key .. ": NaN·1 미만은 1 로 봄")
							T.eq(left, l1)
						else
							T.truthy(new >= c, tag .. " " .. p.key .. ": 배수는 안 내려감")
						end
						-- 클라 카드(buy) 와 서버(남는 것 0) 가 같은 말
						local okS, state = pcall(Products.treadmillBoostState, c, p.value)
						T.truthy(
							okS and (state == "active" or state == "owned" or state == "buy" or state == "locked"),
							tag .. " " .. p.key .. ": treadmillBoostState 안 터짐 " .. tostring(state)
						)
						if okS then
							T.eq(
								state == "buy",
								left == 0,
								tag .. " " .. p.key .. ": 'buy' 카드 ⇔ 서버가 그대로 올려 줌"
							)
							if state == "buy" then
								buys += 1
							end
						end
					end
				end
				T.truthy(buys <= 1, tag .. ": 살 수 있는 카드는 많아야 1장 (" .. buys .. ")")
				if c ~= c or c < 2048 then
					T.eq(buys, 1, tag .. ": 2048 미만이면 정확히 1장")
				else
					T.eq(buys, 0, tag .. ": 2048 이상이면 0장")
				end
			end
			-- 무한은 "최대 넘음" 으로 봐서 전부 속도
			for _, p in Products.treadmillBoosts do
				local new, left = Products.treadmillBoostOutcome(math.huge, p)
				T.eq(left, p.robux, "∞ 에서 " .. p.key .. ": 전부 속도")
				T.eq(new, math.huge, "∞ 에서 " .. p.key .. ": 배수 그대로")
			end
		end
	)

	T.test(
		"nextTreadmillBoost 표 (1→boost_2 … 1024→boost_2048, 2048→nil, NaN→boost_2) · treadmillBoostState 12개 현재 배수 × 11장: buy 는 많아야 1장 · 2048 이면 0장 · active 는 1 초과일 때 정확히 1장 · 열·잠금 순서가 owned→active→buy→locked",
		function()
			for _, c in CURRENTS do
				local nextProduct = Products.nextTreadmillBoost(c)
				if c == 2048 then
					T.eq(nextProduct, nil, "2048 다음은 없음")
				else
					T.eq(nextProduct.key, "boost_" .. (c * 2), c .. " 다음")
				end
			end
			T.eq(Products.nextTreadmillBoost(0 / 0).key, "boost_2", "NaN 은 1 로 봄")
			T.eq(Products.nextTreadmillBoost(0).key, "boost_2")
			T.eq(Products.nextTreadmillBoost(-5).key, "boost_2")
			T.eq(Products.nextTreadmillBoost(3).key, "boost_4", "소수·중간값은 그다음 큰 배수")
			T.eq(Products.nextTreadmillBoost(4096), nil)
			local exponent = 0
			for _, c in CURRENTS do
				local counts = { active = 0, owned = 0, buy = 0, locked = 0 }
				local letters = ""
				for _, value in MULTS do
					local s = Products.treadmillBoostState(c, value)
					T.truthy(
						counts[s] ~= nil,
						"현재 " .. c .. " 카드 " .. value .. ": 모르는 상태 " .. tostring(s)
					)
					counts[s] += 1
					letters ..= string.sub(s, 1, 1)
					-- 서버와 같은 말: 'buy' 인 카드만 낸 R$ 가 전부 배수로 바뀜
					local new, left = Products.treadmillBoostOutcome(c, Products.get("boost_" .. value))
					T.eq(s == "buy", left == 0, "현재 " .. c .. " 카드 " .. value .. ": 'buy' ⇔ 남는 것 0")
					if s == "locked" then
						T.truthy(
							left > 0 and new < value,
							"현재 " .. c .. " 카드 " .. value .. ": 잠긴 것은 서버도 그 배수를 안 줌"
						)
					end
				end
				local tag = "현재 " .. c
				T.eq(counts.active + counts.owned + counts.buy + counts.locked, 11, tag .. ": 카드 11장")
				T.truthy(counts.buy <= 1, tag .. ": buy 는 많아야 1장 (" .. counts.buy .. ")")
				T.truthy(
					string.match(letters, "^o*a?b?l*$") ~= nil,
					tag .. ": 순서 owned→active→buy→locked (" .. letters .. ")"
				)
				if c == 2048 then
					T.eq(counts.buy, 0, tag .. ": 끝이라 살 수 있는 카드 0장")
					T.eq(counts.locked, 0, tag .. ": 잠긴 카드도 0장")
					T.eq(counts.owned, 10, tag .. ": 나머지 10장은 owned")
				else
					T.eq(counts.buy, 1, tag .. ": 살 수 있는 카드 정확히 1장")
				end
				if c > 1 then
					T.eq(counts.active, 1, tag .. ": active 정확히 1장")
					T.eq(counts.owned, exponent - 1 + 0, tag .. ": owned 는 지나온 배수 수")
				else
					T.eq(counts.active, 0, tag .. ": 배수 1 이면 active 없음")
					T.eq(counts.owned, 0)
					T.eq(counts.locked, 10, tag .. ": 2배만 열리고 10장 잠김")
				end
				exponent += 1
			end
			-- NaN 은 배수 1 과 같은 상태
			for _, value in MULTS do
				T.eq(
					Products.treadmillBoostState(0 / 0, value),
					Products.treadmillBoostState(1, value),
					"NaN 현재 · " .. value
				)
			end
		end
	)

	------------------------------------------------------------------
	T.suite("G2 스피드 배수 순서 열림 — 진짜 ProductService.grant")

	T.test(
		"순서대로 2→4→…→2048 을 사면 매번 정확히 그 배수 · 남는 것 0 (속도 안 늘어남) · Attr · Snapshot · ProductGranted 1번 · 합계 4094 R$ · 2048 에서 또 사면 전부 속도",
		function()
			inWorld(function(w)
				local PS = w.ProductService
				local Snapshot = w.H.server("Snapshot")
				local speed0 = w.data.speed
				local paid = 0
				for i, p in w.Products.treadmillBoosts do
					w.H.clearSent()
					T.truthy(PS.grant(w.player, p.key, "purchase"), p.key)
					paid += p.robux
					T.eq(w.data.treadmillBoost, p.value, p.key .. ": 순서대로면 정확히 그 배수")
					T.eq(w.data.speed, speed0, p.key .. ": 속도 안 늘어남")
					T.eq(w.player.attrs.TreadmillBoost, p.value, p.key .. ": Attr")
					T.eq(Snapshot.build(w.player).treadmillBoost, p.value, p.key .. ": Snapshot")
					T.eq(#granted(w), 1, p.key .. ": ProductGranted 1번")
					T.eq(granted(w)[1].key, p.key)
					T.truthy(w.H.hasNotify(w.player, "success", "러닝머신 부스트 x"), p.key .. ": 성공 안내")
					T.falsy(
						w.H.hasNotify(w.player, nil, "순서대로 열려요"),
						p.key .. ": 순서 안내는 안 뜸"
					)
					T.eq(w.data.stats.productsBought, i)
				end
				T.eq(paid, 4094, "2048배까지 순서대로 합계 4,094 R$")
				T.eq(w.data.treadmillBoost, 2048)
				-- 끝에서 또 삼: 배수 그대로 · 낸 R$ 전부 속도
				w.H.clearSent()
				T.truthy(PS.grant(w.player, "boost_2048", "purchase"))
				T.eq(w.data.treadmillBoost, 2048)
				T.eq(w.data.speed, speed0 + 2048 * RATE, "낸 2048 R$ 만큼 속도")
				T.truthy(w.H.hasNotify(w.player, "success", "순서대로 열려요"))
				T.eq(#granted(w), 1, "그래도 소비 처리 (ProductGranted)")
			end)
		end
	)

	T.test(
		"grant 132 조합 (현재 배수 12 × 상품 11, 진짜 서버 코드): 배수 = 기준 모델 · 속도 = 남은 R$ × 환산율 · Attr·Snapshot·DataUpdate 맞음 · 안내 종류 맞음 · ProductGranted 정확히 1번",
		function()
			inWorld(function(w)
				local PS = w.ProductService
				local Snapshot = w.H.server("Snapshot")
				for _, c in CURRENTS do
					for _, p in w.Products.treadmillBoosts do
						local tag = string.format("×%d 에서 %s", c, p.key)
						w.data.treadmillBoost = c
						w.data.speed = 0
						w.H.clearSent()
						T.truthy(PS.grant(w.player, p.key, "purchase"), tag)
						local want, left = boostModel(c, p.value)
						T.eq(w.data.treadmillBoost, want, tag .. ": 배수")
						T.eq(w.data.speed, left * RATE, tag .. ": 속도 = 남은 R$ × 환산율")
						T.eq(w.player.attrs.TreadmillBoost, want, tag .. ": Attr")
						T.eq(Snapshot.build(w.player).treadmillBoost, want, tag .. ": Snapshot")
						local update
						for _, args in w.H.sent(w.player, "DataUpdate") do
							if args[1] == "upgrades" then
								update = args[2]
							end
						end
						T.truthy(update ~= nil and update.treadmillBoost == want, tag .. ": DataUpdate(upgrades)")
						T.eq(#granted(w), 1, tag .. ": ProductGranted 1번")
						if left == 0 then
							T.truthy(
								w.H.hasNotify(w.player, "success", "러닝머신 부스트 x"),
								tag .. ": 순서대로 안내"
							)
							T.falsy(w.H.hasNotify(w.player, nil, "순서대로 열려요"), tag)
						else
							T.truthy(
								w.H.hasNotify(w.player, "success", "순서대로 열려요"),
								tag .. ": 건너뜀 안내"
							)
							T.truthy(
								w.H.hasNotify(w.player, "success", "산 값(R$ " .. p.robux .. ")만큼"),
								tag .. ": 산 값 안내"
							)
							T.falsy(
								w.H.hasNotify(w.player, "info", "가장 큰 것 하나만"),
								tag .. ": 옛 안내 없음"
							)
						end
					end
				end
			end)
		end
	)

	T.test(
		"어떤 순서로 무엇을 사도 N배가 되려면 2…N 가격 합 이상을 냈어야 함: 무작위 30판 × 40번 (진짜 grant) — 낸 R$ = 배수 값(2N-2) + 속도로 받은 R$ · 기준 모델과 같음 · 속도는 낸 R$ 의 환산율을 넘지 않음",
		function()
			inWorld(function(w)
				local PS = w.ProductService
				local list = w.Products.treadmillBoosts
				for seed = 1, 30 do
					local rand = T.rng(seed * 7919)
					w.data.treadmillBoost = 1
					w.data.speed = 0
					local paid, model = 0, 1
					for i = 1, 40 do
						local p = list[math.floor(rand() * #list) + 1]
						local tag = string.format("판 %d · %d번째 %s", seed, i, p.key)
						T.truthy(PS.grant(w.player, p.key, "purchase"), tag)
						paid += p.robux
						model = boostModel(model, p.value)
						local N = w.data.treadmillBoost
						T.eq(N, model, tag .. ": 기준 모델")
						T.truthy(SOLD[N] == true or N == 1, tag .. ": 파는 배수")
						T.truthy(
							paid >= priceSum(1, N),
							tag .. ": " .. N .. "배가 되려면 2…" .. N .. " 가격 합 이상을 냈어야 함"
						)
						T.eq(
							2 * N - 2 + w.data.speed / RATE,
							paid,
							tag .. ": 낸 R$ = 배수 값 + 속도로 받은 R$"
						)
						T.truthy(
							w.data.speed <= (paid - priceSum(1, N)) * RATE,
							tag .. ": 속도로 받은 건 남은 R$ 몫만"
						)
					end
				end
			end)
		end
	)

	T.test(
		"작정하고 건너뛰려는 구매 패턴: 2 만 50번 → ×2 · 4 만 → 2번에 ×4 · 8 만 → 첫 번에 ×4 · 큰 것부터 내림차순 → 4,094 R$ 를 내도 ×1024 · 2048 만 3번 → 첫 번 ×1024, 둘째 ×2048 · 한 번에 2048 R$ 로는 ×2048 못 감",
		function()
			inWorld(function(w)
				local PS = w.ProductService
				local function reset()
					w.data.treadmillBoost = 1
					w.data.speed = 0
				end
				local function buyAll(keys)
					local paid = 0
					for _, key in keys do
						PS.grant(w.player, key, "purchase")
						paid += Products.get(key).robux
					end
					return paid
				end
				reset()
				local keys = {}
				for _ = 1, 50 do
					table.insert(keys, "boost_2")
				end
				local paid = buyAll(keys)
				T.eq(w.data.treadmillBoost, 2, "boost_2 만 50번 → ×2")
				T.eq(w.data.speed, 49 * 2 * RATE, "나머지 49번은 전부 속도")
				T.eq(paid, 100)
				reset()
				buyAll({ "boost_4" })
				T.eq(w.data.treadmillBoost, 2, "boost_4 한 번 → 2 (2 R$) + 남은 2 R$")
				T.eq(w.data.speed, 2 * RATE)
				buyAll({ "boost_4" })
				T.eq(w.data.treadmillBoost, 4, "boost_4 두 번째는 바로 다음이라 ×4")
				T.eq(w.data.speed, 2 * RATE, "속도 더 안 늘어남")
				reset()
				buyAll({ "boost_8" })
				T.eq(w.data.treadmillBoost, 4, "boost_8 한 번 → ×4 (2+4) + 남은 2")
				T.eq(w.data.speed, 2 * RATE)
				reset()
				paid = buyAll({
					"boost_2048",
					"boost_1024",
					"boost_512",
					"boost_256",
					"boost_128",
					"boost_64",
					"boost_32",
					"boost_16",
					"boost_8",
					"boost_4",
					"boost_2",
				})
				T.eq(paid, 4094)
				T.eq(
					w.data.treadmillBoost,
					1024,
					"큰 것부터 4,094 R$ 를 내도 ×1024 (첫 2048 이 ×1024 가 되고 나머지는 전부 속도)"
				)
				T.truthy(w.data.speed > 0)
				T.eq(2 * 1024 - 2 + w.data.speed / RATE, paid, "낸 R$ 가 배수 값과 속도로 정확히 나뉨")
				reset()
				buyAll({ "boost_2048" })
				T.eq(w.data.treadmillBoost, 1024, "처음에 boost_2048 → ×1024 (2048 아님)")
				T.eq(w.data.speed, 2 * RATE)
				buyAll({ "boost_2048" })
				T.eq(w.data.treadmillBoost, 2048, "1024 가 되면 2048 이 바로 다음 → ×2048")
				T.eq(w.data.speed, 2 * RATE, "속도 더 안 늘어남")
				buyAll({ "boost_2048" })
				T.eq(w.data.treadmillBoost, 2048)
				T.eq(w.data.speed, 2 * RATE + 2048 * RATE, "끝에서 또 사면 전부 속도")
			end)
		end
	)

	T.test(
		"속도 상한: SPEED_MAX 직전에서 남은 R$ 를 속도로 받아도 SPEED_MAX 에서 멈춤 · NaN·무한 없음 · 배수는 그대로 정확",
		function()
			inWorld(function(w)
				local PS = w.ProductService
				local MAX = Config.SPEED_MAX
				for _, c in { 1, 2, 1024, 2048 } do
					w.data.treadmillBoost = c
					w.data.speed = MAX - 5
					T.truthy(PS.grant(w.player, "boost_2048", "purchase"), "×" .. c)
					local want = boostModel(c, 2048)
					T.eq(w.data.treadmillBoost, want, "×" .. c .. ": 배수")
					T.truthy(
						w.data.speed == w.data.speed and w.data.speed ~= math.huge and w.data.speed <= MAX,
						"×" .. c .. ": 속도 상한 (" .. tostring(w.data.speed) .. ")"
					)
					local _, left = boostModel(c, 2048)
					if left > 0 then
						T.eq(w.data.speed, MAX, "×" .. c .. ": 남은 R$ 가 상한에서 잘림")
					else
						T.eq(w.data.speed, MAX - 5, "×" .. c .. ": 남는 것 없으면 속도 그대로")
					end
				end
				-- 이미 상한이어도 영수증 하나는 정상 처리
				w.data.treadmillBoost = 2048
				w.data.speed = MAX
				T.truthy(PS.grant(w.player, "boost_2", "purchase"))
				T.eq(w.data.speed, MAX)
				T.eq(w.data.treadmillBoost, 2048)
			end)
		end
	)

	T.test(
		"개발 명령 /buy boost_N 도 같은 grant: 처음에 /buy boost_8 → ×4 + 남은 2 R$ 속도 · 순서대로 /buy boost_2 → boost_4 → ×4 · 영수증 기록·구매 횟수는 안 셈",
		function()
			inWorld(function(w)
				local Dev = w.H.server("Services/DevCommands")
				Dev.start()
				local speed0 = w.data.speed
				w.player.Chatted:Fire("/buy boost_8")
				T.eq(w.data.treadmillBoost, 4, "처음에 /buy boost_8 → ×4")
				T.eq(w.data.speed, speed0 + 2 * RATE, "+ 남은 2 R$ 속도")
				T.eq(#w.data.receipts, 0)
				T.eq(w.data.stats.productsBought, nil)
				w.H.advance(2)
				w.player.Chatted:Fire("/buy boost_8")
				T.eq(w.data.treadmillBoost, 8, "이제 바로 다음 → ×8")
				T.eq(w.data.speed, speed0 + 2 * RATE)
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("G3 스피드 배수 순서 열림 — 진짜 processReceipt (영수증 · 중복 · 저장 실패)")

	T.test(
		"processReceipt 로 순서대로 2→…→2048 영수증 11장: 매번 PurchaseGranted · 정확히 그 배수 · 속도 안 늘어남 · 저장소에도 같음 · 전부 다시(순서 섞어서 3번씩) 보내도 한 번씩만",
		function()
			inWorld(function(w)
				fakeConfigure(w)
				enableSaving(w)
				local speed0 = w.data.speed
				local ids = {}
				for i, p in w.Products.treadmillBoosts do
					local id = "ord-" .. p.key
					ids[i] = { id = id, key = p.key }
					T.eq(process(w, receipt(w, p.key, id)), GRANTED, p.key)
					T.eq(w.data.treadmillBoost, p.value, p.key .. ": 정확히 그 배수")
					T.eq(w.data.speed, speed0, p.key .. ": 속도 안 늘어남")
					T.eq(stored(w).treadmillBoost, p.value, p.key .. ": 저장소에도")
				end
				T.eq(#w.data.receipts, 11)
				T.eq(#granted(w), 11)
				-- 로블록스 재시도: 섞어서 3번씩
				local rand = T.rng(31337)
				for _ = 1, 3 do
					local order = {}
					for i = 1, 11 do
						table.insert(order, rand() * 100)
					end
					local indexes = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
					table.sort(indexes, function(a, b)
						return order[a] < order[b]
					end)
					for _, i in indexes do
						T.eq(process(w, receipt(w, ids[i].key, ids[i].id)), GRANTED, "재전송 " .. ids[i].id)
					end
				end
				T.eq(w.data.treadmillBoost, 2048, "재전송해도 그대로")
				T.eq(w.data.speed, speed0, "재전송해도 속도 안 늘어남")
				T.eq(#w.data.receipts, 11)
				T.eq(#granted(w), 11, "ProductGranted 도 11번 그대로")
				T.eq(w.data.stats.productsBought, 11)
				T.eq(stored(w).treadmillBoost, 2048)
			end)
		end
	)

	T.test(
		"건너뛰기 영수증: 1 에서 boost_2048 → 2048 이 아니고 1024, 남은 2 R$ 는 속도 · 같은 PurchaseId 를 3번 더 보내도 속도는 한 번만 · 다음 boost_2048 영수증은 바로 다음이라 ×2048",
		function()
			inWorld(function(w)
				fakeConfigure(w)
				enableSaving(w)
				local speed0 = w.data.speed
				local r = receipt(w, "boost_2048", "skip-1")
				T.eq(process(w, r), GRANTED)
				T.eq(w.data.treadmillBoost, 1024, "2048 이 아니라 1024")
				T.eq(w.player.attrs.TreadmillBoost, 1024)
				T.eq(w.data.speed, speed0 + 2 * RATE, "남은 2 R$ → 속도")
				T.truthy(w.H.hasNotify(w.player, "success", "순서대로 열려요"))
				for _ = 1, 3 do
					T.eq(process(w, r), GRANTED, "같은 영수증 재전송")
				end
				T.eq(w.data.treadmillBoost, 1024)
				T.eq(w.data.speed, speed0 + 2 * RATE, "속도는 한 번만")
				T.eq(#w.data.receipts, 1)
				T.eq(#granted(w), 1, "ProductGranted 1번")
				T.eq(stored(w).treadmillBoost, 1024, "저장소: 배수")
				T.eq(stored(w).speed, speed0 + 2 * RATE, "저장소: 속도")
				T.eq(#stored(w).receipts, 1)
				-- 다른 영수증 (새 PurchaseId): 이제 2048 이 바로 다음
				T.eq(process(w, receipt(w, "boost_2048", "skip-2")), GRANTED)
				T.eq(w.data.treadmillBoost, 2048)
				T.eq(w.data.speed, speed0 + 2 * RATE, "바로 다음이라 속도 안 늘어남")
				T.eq(w.data.stats.productsBought, 2)
			end)
		end
	)

	T.test(
		"두 번 누름: 같은 부스트 영수증이 서로 다른 PurchaseId 로 두 장 → 첫 장 ×2, 둘째 장은 배수 그대로 + 2 R$ 속도 (둘 다 PurchaseGranted, 각각 1번) · 가진 것(boost_2) 을 새 영수증으로 또 사도 같음",
		function()
			inWorld(function(w)
				fakeConfigure(w)
				enableSaving(w)
				local speed0 = w.data.speed
				T.eq(process(w, receipt(w, "boost_2", "dbl-1")), GRANTED)
				T.eq(w.data.treadmillBoost, 2)
				T.eq(w.data.speed, speed0)
				T.eq(process(w, receipt(w, "boost_2", "dbl-2")), GRANTED)
				T.eq(w.data.treadmillBoost, 2, "그대로")
				T.eq(w.data.speed, speed0 + 2 * RATE, "둘째 장은 2 R$ 만큼 속도")
				T.eq(process(w, receipt(w, "boost_2", "dbl-1")), GRANTED, "옛 영수증 재전송")
				T.eq(w.data.speed, speed0 + 2 * RATE, "옛 영수증은 또 안 줌")
				T.eq(#w.data.receipts, 2)
				T.eq(#granted(w), 2)
			end)
		end
	)

	T.test(
		"저장이 안 되는 동안 건너뛰기 영수증: 효과는 메모리에 한 번만 (배수 1024 · 속도 2 R$) · 몇 번 와도 NotProcessedYet 이고 두 번 안 줌 · 저장이 되면 그때 PurchaseGranted 이고 저장소에 같은 값",
		function()
			inWorld(function(w)
				fakeConfigure(w)
				enableSaving(w)
				local speed0 = w.data.speed
				w.H.store.failNext = 1000 -- DataStore 계속 실패
				local r = receipt(w, "boost_2048", "failskip-1")
				T.eq(process(w, r), NOT_YET, "저장 실패")
				T.eq(w.data.treadmillBoost, 1024)
				T.eq(w.data.speed, speed0 + 2 * RATE)
				T.eq(process(w, r), NOT_YET, "다시 와도 저장이 안 되니 확인 안 함")
				T.eq(process(w, r), NOT_YET)
				T.eq(w.data.treadmillBoost, 1024, "두 번 안 줌")
				T.eq(w.data.speed, speed0 + 2 * RATE, "속도 두 번 안 줌")
				T.eq(#w.data.receipts, 1)
				w.H.store.failNext = 0
				T.eq(process(w, r), GRANTED, "저장이 되면 확인")
				T.eq(w.data.treadmillBoost, 1024)
				T.eq(w.data.speed, speed0 + 2 * RATE)
				T.eq(stored(w).treadmillBoost, 1024, "저장소: 배수")
				T.eq(stored(w).speed, speed0 + 2 * RATE, "저장소: 속도")
				T.eq(process(w, r), GRANTED)
				T.eq(w.data.speed, speed0 + 2 * RATE)
				T.eq(#granted(w), 1, "ProductGranted 1번")
			end)
		end
	)

	T.test(
		"[G-1 알려진 한계] 영수증이 산 순서와 뒤바뀌어 오면 (2배 → 4배 순서로 샀는데 4배 영수증이 먼저 처리): 처리된 순서대로만 열려서 ×4 가 아니라 ×2 + 속도 4 R$ — 돈은 잃지 않지만 배수는 못 받음 (서버가 먼저 꺼져 두 영수증이 밀렸다가 다시 올 때만 가능)",
		function()
			inWorld(function(w)
				fakeConfigure(w)
				enableSaving(w)
				local speed0 = w.data.speed
				-- 샀을 때는 2배 → 4배 순서 (영수증 번호 A → B). 하지만 서버는 B 를 먼저 받음
				T.eq(process(w, receipt(w, "boost_4", "late-B")), GRANTED)
				T.eq(
					w.data.treadmillBoost,
					2,
					"B(4배 영수증) 를 먼저 받으면: 2배까지만 + 남은 2 R$ 속도"
				)
				T.eq(process(w, receipt(w, "boost_2", "late-A")), GRANTED)
				T.eq(w.data.treadmillBoost, 2, "A(2배 영수증) 는 이미 가진 것: 그대로 + 2 R$ 속도")
				T.eq(w.data.speed, speed0 + 4 * RATE, "낸 6 R$ 중 2 R$ 는 2배, 4 R$ 는 속도")
				T.eq(
					2 * 2 - 2 + (w.data.speed - speed0) / RATE,
					6,
					"낸 R$ 6 은 하나도 안 사라짐 (배수 값 + 속도)"
				)
			end)
		end
	)

	T.test(
		"무작위 영수증 (11개 부스트 중 무작위 · 가끔 같은 PurchaseId 재전송 · 가끔 저장 실패): 기준 모델과 같은 배수 · 낸 R$ = 배수 값 + 속도 R$ · 영수증 1장 = 효과 1번 · Attr/Snapshot 일치",
		function()
			inWorld(function(w)
				fakeConfigure(w)
				enableSaving(w)
				local speed0 = w.data.speed
				local Snapshot = w.H.server("Snapshot")
				local rand = T.rng(6361)
				local list = w.Products.treadmillBoosts
				local model, paid, count = 1, 0, 0
				local seenIds = {}
				for i = 1, 160 do
					local roll = rand()
					if roll < 0.25 and #seenIds > 0 then
						-- 재전송: 이미 지급한 영수증
						local old = seenIds[math.floor(rand() * #seenIds) + 1]
						local before = { w.data.treadmillBoost, w.data.speed, #w.data.receipts }
						local result = process(w, receipt(w, old.key, old.id))
						T.truthy(result == GRANTED or result == NOT_YET, "재전송 결과 " .. tostring(result))
						T.eq(w.data.treadmillBoost, before[1], i .. ": 재전송은 배수 안 바꿈")
						T.eq(w.data.speed, before[2], i .. ": 재전송은 속도 안 바꿈")
						T.eq(#w.data.receipts, before[3], i .. ": 재전송은 기록 안 늘림")
					else
						local p = list[math.floor(rand() * #list) + 1]
						local id = "rnd-" .. i
						if rand() < 0.1 then
							w.H.store.failNext = 2
						end
						local result = process(w, receipt(w, p.key, id))
						w.H.store.failNext = 0
						T.truthy(result == GRANTED or result == NOT_YET, i .. ": 결과 " .. tostring(result))
						table.insert(seenIds, { key = p.key, id = id })
						model = boostModel(model, p.value)
						paid += p.robux
						count += 1
						T.eq(w.data.treadmillBoost, model, i .. ": " .. p.key .. " 기준 모델")
						T.eq(
							2 * model - 2 + (w.data.speed - speed0) / RATE,
							paid,
							i .. ": 낸 R$ = 배수 값 + 속도 R$"
						)
						T.eq(w.player.attrs.TreadmillBoost, model, i .. ": Attr")
						T.eq(Snapshot.build(w.player).treadmillBoost, model, i .. ": Snapshot")
						T.eq(w.data.stats.productsBought, count, i .. ": 영수증 1장 = 효과 1번")
						T.eq(#granted(w), count, i .. ": ProductGranted 도 1번씩")
					end
				end
				-- 저장이 되는 상태로 모두 확인하면 저장소와 메모리가 같음
				for _, old in seenIds do
					T.eq(process(w, receipt(w, old.key, old.id)), GRANTED, "마지막 확인 " .. old.id)
				end
				T.eq(stored(w).treadmillBoost, w.data.treadmillBoost, "저장소 배수 = 메모리")
				T.eq(stored(w).speed, w.data.speed, "저장소 속도 = 메모리")
				T.eq(w.data.stats.productsBought, count)
			end)
		end
	)
end
