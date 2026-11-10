--!nocheck
--[[
	9판 로벅스 상품 (사장님 2026-11-10): shared/Data/Products 표 · 서버 ProductService (grant · ProcessReceipt) ·
	러닝머신 부스트 · 코인 2배 · 저장 스키마 8 · 개발 명령 /buy
	진짜 서비스 코드를 ServerHarness 위에서 (가상 시간). MarketplaceService 는 가짜 (ProcessReceipt 콜백만 받음).
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local ProductsPatch = require("./ProductsPatch")
	local S = "ReplicatedStorage/Shared/"
	local Products = Loader.require(S .. "Data/Products")
	local Config = Loader.require(S .. "Data/Config")
	local Upgrades = Loader.require(S .. "Data/Upgrades")
	local Economy = Loader.require(S .. "Economy")

	local GRANTED = "ProductPurchaseDecision.PurchaseGranted"
	local NOT_YET = "ProductPurchaseDecision.NotProcessedYet"

	local SKIP_ROBUX = {
		3,
		10,
		30,
		50,
		100,
		399,
		599,
		799,
		1099,
		1599,
		1999,
		2599,
		3900,
		5000,
		6000,
		8000,
		10000,
		12000,
		15000,
		20000,
	}
	local SHOP = {
		{ "money_pass", "moneyPass", 199, 2 },
		{ "coins_1m", "coins", 99, 1e6 },
		{ "coins_1b", "coins", 199, 1e9 },
		{ "speed_10m", "speed", 199, 1e7 },
		{ "speed_100m", "speed", 259, 1e8 },
	}

	-- 진짜 Products 파일에서 id 칸만 바꾼 모듈 (holes_v9 와 같은 방법). 진짜 파일에 붙은 진짜 id 가 무엇이든 상관없게
	-- **36칸을 전부 0 으로 만든 뒤** replacements 의 칸만 채움: patchedProducts({}) = 전부 0 (아직 아무것도 안 만든 상태)
	local function patchedProducts(replacements)
		return ProductsPatch.load(replacements, Config)
	end

	-- 가짜 세상: 진짜 Net · Sessions · Snapshot · Wallet · DataService · ProductService (+ 필요하면 더)
	--   ids = { key = 숫자 } 를 주면 Products 를 36칸 전부 0 + 그 칸만 가짜 id 인 사본으로 (ProductService 도 그 사본을 씀). 안 주면 진짜 파일
	local function world(ids)
		local H = ServerHarness.install(Loader, T)
		if ids then
			Loader.mock(S .. "Data/Products", patchedProducts(ids))
		end
		H.startNet()
		local w = { H = H }
		w.Products = H.shared("Data/Products")
		w.Sessions = H.server("Sessions")
		w.DataService = H.server("Services/DataService")
		w.ProductService = H.server("Services/ProductService")
		w.PetService = H.server("Services/PetService")
		w.player = H.newPlayer(9001, "Buyer")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		return w
	end

	local function granted(w, player)
		local list = {}
		for _, args in w.H.sent(player or w.player, "ProductGranted") do
			table.insert(list, args[1])
		end
		return list
	end

	local function lastSection(w, section, player)
		local found = nil
		for _, args in w.H.sent(player or w.player, "DataUpdate") do
			if args[1] == section then
				found = args[2]
			end
		end
		return found
	end

	local function receipt(w, productKey, purchaseId, player)
		return {
			PlayerId = (player or w.player).UserId,
			ProductId = w.fakeIds[productKey],
			PurchaseId = purchaseId,
			CurrencySpent = 1,
		}
	end

	-- 상품 id 를 가짜로 붙임 (진짜 id 에 기대지 않으려고): byProductId 만 바꿔 끼움 — 개발자 상품만 (62번: 패스는 영수증 없음)
	local function fakeConfigure(w)
		w.fakeIds = {}
		local byId = {}
		for i, product in w.Products.list do
			if not product.isPass then
				w.fakeIds[product.key] = 100000 + i
				byId[100000 + i] = product
			end
		end
		w.Products.byProductId = function(id)
			return byId[id]
		end
	end

	-- 게임패스 id 를 가짜로 붙임: 패스 product.productId = 200000 + i (isConfigured 가 true) + byPassId 를 바꿔 끼움
	local function fakeConfigurePasses(w)
		w.passIds = {}
		local byPass = {}
		for i, product in w.Products.passes do
			product.productId = 200000 + i
			w.passIds[product.key] = product.productId
			byPass[product.productId] = product
		end
		w.Products.byPassId = function(id)
			return byPass[id]
		end
	end

	-- 가짜 MarketplaceService: owned[gamePassId] = true 면 가짐. failFirst = 패스마다 처음 몇 번 실패할지 (math.huge = 늘 실패)
	local function fakeMarket(w)
		local market = { owned = {}, calls = 0, failFirst = 0, tries = {}, handlers = {} }
		function market:UserOwnsGamePassAsync(userId, passId)
			market.calls += 1
			market.tries[passId] = (market.tries[passId] or 0) + 1
			if market.tries[passId] <= market.failFirst then
				error("가짜 HTTP 실패")
			end
			return userId == w.player.UserId and market.owned[passId] == true
		end
		market.PromptGamePassPurchaseFinished = {
			Connect = function(_, fn)
				table.insert(market.handlers, fn)
				return { Disconnect = function() end }
			end,
		}
		Loader.service("MarketplaceService", market)
		return market
	end

	local function own(w, market, ...)
		for _, key in { ... } do
			market.owned[w.passIds[key]] = true
		end
	end

	local function sync(w, player)
		return w.H.run(function()
			return w.ProductService.syncPasses(player or w.player)
		end)
	end

	local function passFinished(w, key, wasPurchased, player)
		local id = if type(key) == "number" then key else w.passIds[key]
		w.H.run(function()
			w.ProductService.onGamePassPurchaseFinished(player or w.player, id, wasPurchased)
		end)
	end

	local function process(w, r, maxSeconds)
		return w.H.run(function()
			return w.ProductService.processReceipt(r)
		end, maxSeconds or 30)
	end

	------------------------------------------------------------------
	T.suite("9판 로벅스 상품 표 (Data/Products)")

	T.test(
		"표 36개 = 러닝머신 부스트 11 + 러닝머신 레벨 20 + 상점 5 — 키·종류·가격·값이 사장님 표 그대로, 키는 겹치지 않음",
		function()
			T.eq(#Products.treadmillBoosts, 11)
			T.eq(#Products.treadmillSkips, 20)
			T.eq(#Products.treadmillSkips, Upgrades.TREADMILL_MAX_LEVEL, "러닝머신 레벨 수와 같음")
			T.eq(#Products.shop, 5)
			T.eq(
				#Products.list,
				36,
				"11 + 20 + 5 (본부장 지시문의 '39개'는 셈 실수 — 계약 표는 36개)"
			)
			local seen = {}
			for _, p in Products.list do
				T.falsy(seen[p.key], "키 겹침 " .. p.key)
				seen[p.key] = true
				T.eq(Products.byKey[p.key], p)
				T.eq(Products.get(p.key), p)
				T.truthy(type(p.name) == "string" and #p.name > 0, p.key .. " 이름")
				T.truthy(Products.Kinds[p.kind] == p.kind, p.key .. " 종류 " .. tostring(p.kind))
				T.truthy(p.robux > 0 and p.robux == math.floor(p.robux), p.key .. " 가격")
			end
			-- 부스트: boost_2 … boost_2048, 값 = 배수 = 가격
			for i, p in Products.treadmillBoosts do
				local m = 2 ^ i
				T.eq(p.key, "boost_" .. m)
				T.eq(p.kind, "treadmillBoost")
				T.eq(p.value, m)
				T.eq(p.robux, m, p.key .. " 가격 = 배수")
			end
			-- 러닝머신 레벨: tskip_1 … tskip_20, 값 = 그 레벨, 가격 표 (18~20 은 [추정])
			for n, p in Products.treadmillSkips do
				T.eq(p.key, "tskip_" .. n)
				T.eq(p.kind, "treadmillSkip")
				T.eq(p.value, n)
				T.eq(p.robux, SKIP_ROBUX[n], p.key .. " 가격")
				if n > 1 then
					T.truthy(p.robux > Products.treadmillSkips[n - 1].robux, p.key .. " 가격이 오르기만 함")
				end
			end
			T.eq(table.concat(Products.ESTIMATED_SKIP_LEVELS, ","), "18,19,20")
			-- 상점 5개
			for i, row in SHOP do
				local p = Products.shop[i]
				T.eq(p.key, row[1])
				T.eq(p.kind, row[2])
				T.eq(p.robux, row[3], p.key .. " 가격")
				T.eq(p.value, row[4], p.key .. " 값")
			end
			T.eq(Products.get("money_pass").value, Config.MONEY_PASS_MULTIPLIER)
			T.eq(Products.get("없는상품"), nil)
			-- 62번: 영구 = 게임패스 12개 (부스트 11 + money_pass), 소모품 = 개발자 상품 24개
			local passKeys, devCount = {}, 0
			for _, p in Products.list do
				T.eq(type(p.isPass), "boolean", p.key .. " isPass")
				local permanent = p.kind == "treadmillBoost" or p.kind == "moneyPass"
				T.eq(p.isPass, permanent, p.key .. " 영구면 패스")
				if p.isPass then
					table.insert(passKeys, p.key)
				else
					devCount += 1
				end
			end
			T.eq(#passKeys, 12)
			T.eq(devCount, 24)
			T.eq(#Products.passes, 12)
			for i, p in Products.passes do
				T.eq(p.key, passKeys[i], "Products.passes 는 표 순서")
				T.truthy(p.isPass)
			end
			T.eq(Products.passes[12].key, "money_pass")
		end
	)

	-- [I-1] 진짜 파일의 id 규칙 (진짜 숫자 값에는 기대지 않음 — 누가 id 를 고쳐 붙여도 규칙만 지키면 통과)
	T.test(
		"[I-1] 상품 id 는 Products.IDS 한 곳 (36칸): 모두 0(미설정) 이거나 0 보다 큰 정수 · 0 이 아닌 id 는 패스·상품 통틀어 안 겹침 · 부스트 패스는 2배부터 빈칸 없이 이어서 붙음 · 패스 id 는 byPassId 로만, 상품 id 는 byProductId 로만 찾아짐",
		function()
			local count = 0
			local used = {}
			for key, id in Products.IDS do
				count += 1
				T.truthy(Products.byKey[key], "IDS 의 모르는 키 " .. key)
				-- ① 0 (아직 안 만듦) 이거나 0 보다 큰 정수
				T.truthy(
					id == 0 or (type(id) == "number" and id > 0 and id < math.huge and id == math.floor(id)),
					key .. " id 는 0 이거나 0 보다 큰 정수: " .. tostring(id)
				)
				-- ② 0 이 아닌 id 는 서로 겹치지 않음 (패스·상품 통틀어)
				if id ~= 0 then
					T.falsy(
						used[id],
						key
							.. " 와 "
							.. tostring(used[id])
							.. " 가 같은 id "
							.. tostring(id)
							.. " — 한 id 를 두 군데 붙임"
					)
					used[id] = key
				end
			end
			T.eq(count, #Products.list, "IDS 칸 수 = 상품 수")
			for _, p in Products.list do
				T.eq(p.productId, Products.IDS[p.key], p.key .. " productId = IDS 칸")
				T.eq(Products.isConfigured(p), p.productId > 0, p.key .. " isConfigured = 0 보다 큼")
			end
			-- ③ 부스트 패스는 2배부터 차례로 빈칸 없이 (앞이 0 인데 뒤가 붙어 있으면 실패)
			local firstEmpty = nil
			for _, p in Products.treadmillBoosts do
				if p.productId == 0 then
					firstEmpty = firstEmpty or p.key
				else
					T.falsy(
						firstEmpty,
						p.key
							.. " 는 id 가 붙어 있는데 앞의 "
							.. tostring(firstEmpty)
							.. " 가 0 — 2배부터 빈칸 없이 이어서 붙일 것"
					)
				end
			end
			-- ④ 패스 id 는 byPassId 로만, 개발자 상품 id 는 byProductId 로만
			for _, p in Products.list do
				if p.productId > 0 then
					if p.isPass then
						T.eq(Products.byPassId(p.productId), p, p.key .. " 는 패스 — byPassId 로 찾아짐")
						T.eq(
							Products.byProductId(p.productId),
							nil,
							p.key .. " 는 패스 — byProductId 로는 안 찾아짐"
						)
					else
						T.eq(
							Products.byProductId(p.productId),
							p,
							p.key .. " 는 개발자 상품 — byProductId 로 찾아짐"
						)
						T.eq(
							Products.byPassId(p.productId),
							nil,
							p.key .. " 는 개발자 상품 — byPassId 로는 안 찾아짐"
						)
					end
				end
			end
			-- 이상한 값은 어느 표에서도 안 찾아짐 (123456 은 진짜 id 가 아님)
			T.truthy(Products.isConfigured({ key = "x", kind = "coins", name = "x", robux = 1, productId = 42 }))
			for _, bad in { 0, -1, 123456, 0 / 0, "5" } do
				T.eq(Products.byProductId(bad), nil, tostring(bad))
				T.eq(Products.byPassId(bad), nil, tostring(bad))
			end
		end
	)

	-- [I-2] 지금 진짜 파일은 36칸 전부 설정됨 — 누가 실수로 0 으로 되돌리면 여기서 잡힘 (값은 안 봄, 붙어 있는지만)
	T.test(
		"[I-2] 지금 진짜 Products 파일은 36칸 전부 id 가 붙어 있음 (isConfigured 36개 모두 true — 0 으로 되돌아가면 실패)",
		function()
			local configured, empty = 0, {}
			for _, p in Products.list do
				if Products.isConfigured(p) then
					configured += 1
				else
					table.insert(empty, p.key)
				end
			end
			T.eq(#Products.list, 36)
			T.eq(configured, 36, "id 가 0 인 칸: " .. table.concat(empty, ","))
			T.eq(#empty, 0)
			-- 패스 12개 · 개발자 상품 24개가 각각 그 표에서 찾아짐 (진짜 id 로 영수증/소유 확인이 연결됨)
			local passHits, productHits = 0, 0
			for _, p in Products.list do
				if p.isPass and Products.byPassId(p.productId) == p then
					passHits += 1
				elseif not p.isPass and Products.byProductId(p.productId) == p then
					productHits += 1
				end
			end
			T.eq(passHits, 12, "byPassId 로 찾아지는 패스")
			T.eq(productHits, 24, "byProductId 로 찾아지는 개발자 상품")
		end
	)

	-- [I-3] id 가 전부 0 인 표 (아직 아무것도 안 만든 상태 = 전부 "준비 중") — 이제는 진짜 파일이 아니라 0 으로 만든 사본으로 봄
	T.test(
		"[I-3] id 를 전부 0 으로 만든 사본: 36칸 전부 isConfigured false · byProductId · byPassId 는 어떤 숫자로 물어도 nil · 사본이 진짜 모듈과 섞이지 않음",
		function()
			local P = patchedProducts({})
			T.eq(#P.list, 36)
			local n = 0
			for key, id in P.IDS do
				n += 1
				T.eq(id, 0, key)
			end
			T.eq(n, 36)
			for _, p in P.list do
				T.eq(p.productId, 0, p.key)
				T.falsy(P.isConfigured(p), p.key)
			end
			-- 진짜 파일에 붙어 있는 진짜 id 로 물어도 안 찾아짐 (사본에는 없으므로)
			for _, p in Products.list do
				T.eq(P.byProductId(p.productId), nil, p.key)
				T.eq(P.byPassId(p.productId), nil, p.key)
			end
			for _, bad in { 0, -1, 999, 0 / 0, "5" } do
				T.eq(P.byProductId(bad), nil, tostring(bad))
				T.eq(P.byPassId(bad), nil, tostring(bad))
			end
			-- 사본을 만들어도 진짜 모듈은 그대로 (글자 바꾸기는 사본만)
			T.truthy(Products.isConfigured(Products.get("boost_2")), "진짜 모듈은 그대로")
			-- 한 칸만 채우면 그 칸만 붙음 (다른 칸은 0 그대로)
			local one = patchedProducts({ coins_1m = 31 })
			T.eq(one.byProductId(31).key, "coins_1m")
			T.truthy(one.isConfigured(one.get("coins_1m")))
			T.falsy(one.isConfigured(one.get("coins_1b")))
			T.falsy(one.isConfigured(one.get("boost_2")))
		end
	)

	T.test(
		"nextTreadmillSkip: 지금 레벨의 다음 레벨 상품 (0 → tskip_1 … 19 → tskip_20, 20 이상이면 nil)",
		function()
			T.eq(Products.nextTreadmillSkip(0).key, "tskip_1")
			T.eq(Products.nextTreadmillSkip(1).key, "tskip_2")
			T.eq(Products.nextTreadmillSkip(19).key, "tskip_20")
			T.eq(Products.nextTreadmillSkip(20), nil)
			T.eq(Products.nextTreadmillSkip(25), nil)
			T.eq(Products.nextTreadmillSkip(-3).key, "tskip_1")
			T.eq(Products.nextTreadmillSkip(4.7).key, "tskip_5", "소수는 내림")
		end
	)

	T.test("서버로 '사 줘' Remote 는 없음 (위조 방지) · 지급 알림 ProductGranted 만", function()
		local Remotes = Loader.require(S .. "Remotes")
		T.truthy(Remotes.ToClient.ProductGranted)
		for name in Remotes.ToServer do
			local lower = string.lower(name)
			T.falsy(string.find(lower, "product") or string.find(lower, "robux") or string.find(lower, "buy"), name)
		end
	end)

	------------------------------------------------------------------
	T.suite("9판 ProductService.grant (종류마다 지급)")

	T.test(
		"러닝머신 부스트: 순서대로만 열림 (2→4→…) · 순서대로 사면 그 배수 (곱 아님) · 가진 것·건너뛴 것은 산 R$ 만큼만 (남은 값은 속도) · Attr TreadmillBoost · ProductGranted · DataUpdate(upgrades)",
		function()
			local w = world()
			local PS = w.ProductService
			local RATE = Config.PRODUCT_SPEED_PER_ROBUX
			T.eq(w.data.treadmillBoost, 1)
			local speed = w.data.speed
			T.truthy(PS.grant(w.player, "boost_2", "purchase"))
			T.eq(w.data.treadmillBoost, 2, "1 → 2 는 순서대로")
			T.eq(w.player.attrs.TreadmillBoost, 2)
			T.eq(w.data.speed, speed, "순서대로면 속도는 안 늘어남")
			local g = granted(w)
			T.eq(g[1].key, "boost_2")
			T.eq(g[1].kind, "treadmillBoost")
			T.eq(lastSection(w, "upgrades").treadmillBoost, 2)
			T.truthy(w.H.hasNotify(w.player, "success", "러닝머신 부스트 x2"))
			T.truthy(PS.grant(w.player, "boost_4"))
			T.eq(w.data.treadmillBoost, 4, "2 → 4 (2 × 4 = 8 이 아님, 곱 아님)")
			-- 가진 것을 또 삼 (두 번 누름): 배수 그대로, 산 값 4 R$ 는 속도로
			speed = w.data.speed
			T.truthy(PS.grant(w.player, "boost_4"))
			T.eq(w.data.treadmillBoost, 4, "그대로")
			T.eq(w.data.speed, speed + 4 * RATE, "산 값만큼 속도")
			T.truthy(w.H.hasNotify(w.player, "success", "산 값(R$ 4)만큼"))
			T.eq(#granted(w), 3, "그래도 소비 처리 (환불 없음) — ProductGranted 는 감")
			-- 건너뛰기 (잠긴 것을 위조로 삼): 4 에서 boost_64 (64 R$) → 8(8)+16(16)+32(32) = 56 까지, 남은 8 R$ 는 속도
			speed = w.data.speed
			T.truthy(PS.grant(w.player, "boost_64"))
			T.eq(w.data.treadmillBoost, 32, "64 가 아니라 32 (56 R$ 어치만)")
			T.eq(w.player.attrs.TreadmillBoost, 32, "Attr 도 같음")
			T.eq(w.data.speed, speed + 8 * RATE, "남은 8 R$ 는 속도")
			T.eq(lastSection(w, "upgrades").treadmillBoost, 32, "DataUpdate 도 같음")
			-- 끝까지 순서대로: 64 … 2048
			for _, key in { "boost_64", "boost_128", "boost_256", "boost_512", "boost_1024", "boost_2048" } do
				T.truthy(PS.grant(w.player, key))
				T.eq(w.data.treadmillBoost, w.Products.get(key).value, key .. " 순서대로")
			end
			T.eq(w.data.treadmillBoost, 2048)
			T.eq(
				w.data.stats.productsBought,
				10,
				"모든 지급이 구매 횟수에 셈 (2·4·4·64·64·128·256·512·1024·2048)"
			)
			w.H.uninstall()
		end
	)

	T.test(
		"러닝머신 1초 이득 = 레벨 이득 × 트레일 배율 × 부스트 (Economy + 진짜 TreadmillService 걸음) — 걷는 속도에는 안 곱함",
		function()
			T.eq(Economy.treadmillGainPerSecond(10), 8000)
			T.eq(Economy.treadmillGainPerSecond(10, 2), 16000)
			T.eq(Economy.treadmillGainPerSecond(10, 2, 8), 128000)
			T.eq(Economy.treadmillGainPerSecond(10, nil, 2048), 8000 * 2048)
			T.eq(Economy.treadmillGainPerSecond(20, 1, 1), 1000000, "부스트 없으면 20레벨 1M 그대로")
			T.eq(Economy.treadmillGainPerSecond(10, 0 / 0, -5), 8000, "이상한 배율은 1")
			T.eq(Economy.treadmillGainPerSecond(0, 5, 2048), 0, "0레벨은 0")
			local w = world()
			local TS = w.H.server("Services/TreadmillService")
			local SpeedService = w.H.server("Services/SpeedService")
			TS.start()
			w.data.treadmillLevel = 5 -- 걸음당 80 → 320/초
			w.data.trails = { "green" }
			w.data.equippedTrail = "green" -- ×2
			w.data.treadmillBoost = 8 -- ×8 (순서대로 사는 것은 위 테스트가 검사 — 여기서는 곱셈만)
			w.ProductService.onPlayerReady(w.player)
			local plot = w.H.MapLayout.plot(1)
			w.H.spawn(w.player, plot.treadmill.x, 3, plot.treadmill.z)
			w.H.advance(0.5)
			T.eq(w.player.attrs.OnTreadmill, true)
			local before = w.data.speed
			w.H.advance(3)
			local perSecond = 80 * Config.TREADMILL_MULTIPLIER * 2 * 8
			T.eq(perSecond, 5120)
			T.eq((w.data.speed - before) % perSecond, 0, "걸음마다 5120 씩")
			T.truthy(w.data.speed - before >= perSecond * 2, "3초에 2~3걸음")
			local steps = w.H.sent(w.player, "TreadmillStep")
			T.eq(steps[#steps][1].amount, perSecond)
			-- 부스트는 걷는 속도(실효 속도 = 모은 속도 × 트레일)에는 안 곱함
			SpeedService.refresh(w.player)
			T.eq(
				w.session.effectiveSpeed,
				w.data.speed * 2,
				"실효 속도 = 모은 속도 × 트레일 (부스트 없음)"
			)
			w.H.uninstall()
		end
	)

	T.test(
		"러닝머신 레벨 올리기: 레벨이 N-1 이면 N (코인 안 듦) · 안 맞으면 산 로벅스만큼만 (살 수 있는 레벨 + 남은 R$ → 속도) · 최대면 전부 속도 — 주임 F-3",
		function()
			local w = world()
			local PS = w.ProductService
			local RATE = Config.PRODUCT_SPEED_PER_ROBUX
			T.truthy(RATE <= 1e8 / 259, "환산율이 속도 100M 상품(259 R$)보다 유리하지 않음")
			w.data.money = 777
			T.truthy(PS.grant(w.player, "tskip_1"))
			T.eq(w.data.treadmillLevel, 1, "0 → 1 (해금)")
			T.eq(w.player.attrs.TreadmillLevel, 1)
			T.eq(lastSection(w, "upgrades").treadmillLevel, 1)
			T.truthy(PS.grant(w.player, "tskip_2"))
			T.eq(w.data.treadmillLevel, 2)
			T.eq(w.data.money, 777, "코인 안 듦")
			-- 안 맞음 (아래): 2레벨에서 10레벨 상품(1599 R$) → 3~7레벨 (30+50+100+399+599 = 1178) 까지, 남은 421 R$ 는 속도
			local speed = w.data.speed
			T.truthy(PS.grant(w.player, "tskip_10"))
			T.eq(w.data.treadmillLevel, 7)
			T.eq(w.player.attrs.TreadmillLevel, 7)
			T.eq(w.data.speed, speed + 421 * RATE)
			T.truthy(w.H.hasNotify(w.player, "success", "산 값(R$ 1599)만큼"))
			-- 안 맞음 (위·두 번 누름): 7레벨에서 3레벨 상품(30 R$) → 8레벨(799)은 못 삼, 30 R$ 는 속도
			speed = w.data.speed
			T.truthy(PS.grant(w.player, "tskip_3"))
			T.eq(w.data.treadmillLevel, 7, "싼 상품으로 비싼 레벨을 못 얻음")
			T.eq(w.data.speed, speed + 30 * RATE, "대신 산 값만큼 속도 (0 지급 없음)")
			w.data.treadmillLevel = 19
			T.truthy(PS.grant(w.player, "tskip_20"))
			T.eq(w.data.treadmillLevel, 20)
			-- 최대에서 또: 전부 속도 (20000 R$ × 환산율)
			speed = w.data.speed
			T.truthy(PS.grant(w.player, "tskip_20"))
			T.eq(w.data.treadmillLevel, 20, "최대 그대로")
			T.eq(w.data.speed, speed + 20000 * RATE)
			T.eq(Config.PRODUCT_MAXED_SKIP_SECONDS, nil, "8판식 600M 고정 보상 없앰")
			T.eq(#granted(w), 6, "6번 다 ProductGranted")
			-- 순수 규칙 (Products.treadmillSkipOutcome)
			local P = w.Products
			local function outcome(level, key)
				return { P.treadmillSkipOutcome(level, P.get(key)) }
			end
			T.eq(table.concat(outcome(0, "tskip_1"), ","), "1,0")
			T.eq(table.concat(outcome(4, "tskip_5"), ","), "5,0")
			T.eq(table.concat(outcome(1, "tskip_1"), ","), "1,3", "3 R$ 로 2레벨(10) 못 삼")
			T.eq(table.concat(outcome(0, "tskip_2"), ","), "1,7", "0레벨에서 2레벨 상품: 1레벨(3) + 7 R$")
			T.eq(table.concat(outcome(20, "tskip_1"), ","), "20,3")
			T.eq(table.concat(outcome(0, "tskip_20"), ","), "14,1814", "20000 R$ 로 1~14레벨 (18186) + 1814 남음")
			w.H.uninstall()
		end
	)

	T.test(
		"코인 1M·1B / 속도 10M·100M: Wallet 로 더함 (MONEY_MAX·SPEED_MAX 에서 자름), Attr 도 바뀜",
		function()
			local w = world()
			local PS = w.ProductService
			local Wallet = w.H.server("Services/Wallet")
			Wallet.setupLeaderstats(w.player)
			w.data.money = 5
			T.truthy(PS.grant(w.player, "coins_1m"))
			T.eq(w.data.money, 5 + 1e6)
			T.truthy(PS.grant(w.player, "coins_1b"))
			T.eq(w.data.money, 5 + 1e6 + 1e9)
			T.eq(w.player.attrs.Money, w.data.money)
			local speed = w.data.speed
			T.truthy(PS.grant(w.player, "speed_10m"))
			T.truthy(PS.grant(w.player, "speed_100m"))
			T.eq(w.data.speed, speed + 1e7 + 1e8)
			T.eq(w.player.attrs.BaseSpeed, w.data.speed)
			w.data.money = Config.MONEY_MAX - 5
			T.truthy(PS.grant(w.player, "coins_1b"))
			T.eq(w.data.money, Config.MONEY_MAX, "MONEY_MAX 를 안 넘음")
			w.data.speed = Config.SPEED_MAX - 1
			T.truthy(PS.grant(w.player, "speed_100m"))
			T.eq(w.data.speed, Config.SPEED_MAX)
			T.eq(granted(w)[1].kind, "coins")
			T.eq(granted(w)[3].kind, "speed")
			w.H.uninstall()
		end
	)

	T.test(
		"코인 2배 (money_pass): 영원히 data.moneyPass · Attr MoneyPass · 열매 판매·성체 팔기 × 2 · 또 사도 그대로(안내)",
		function()
			local w = world()
			local PS = w.ProductService
			local FruitService = w.H.server("Services/FruitService")
			T.eq(w.PetService.coinMultiplier(w.player), 1)
			T.truthy(PS.grant(w.player, "money_pass"))
			T.eq(w.data.moneyPass, true)
			T.eq(w.player.attrs.MoneyPass, true)
			T.eq(lastSection(w, "upgrades").moneyPass, true)
			T.eq(w.PetService.coinMultiplier(w.player), 2)
			-- 열매 팔기 × 2
			local stall = w.H.MapLayout.hubSpots.sellStall
			w.H.spawn(w.player, stall.x, 3, stall.z)
			w.data.fruits.sprout_daisy = { count = 3, value = 30 }
			T.eq(FruitService.sellAll(w.player), 60)
			T.eq(w.data.money, 60)
			-- 또 사면 그대로 (소비 처리)
			T.truthy(PS.grant(w.player, "money_pass"))
			T.eq(w.data.moneyPass, true)
			T.truthy(w.H.hasNotify(w.player, "info", "이미 코인 2배"))
			-- 저장 → 불러오기에도 남음
			local DataSchema = w.H.server("Logic/DataSchema")
			T.eq(DataSchema.reconcile(w.data, 0).moneyPass, true)
			w.H.uninstall()
		end
	)

	T.test(
		"모르는 키 · 데이터 미로드 · 없는 사람이면 지급 안 함 (false, ProductGranted 없음)",
		function()
			local w = world()
			local PS = w.ProductService
			T.falsy(PS.grant(w.player, "없는상품"))
			T.falsy(PS.grant(w.player, ""))
			local stranger = w.H.newPlayer(9002, "Loading")
			w.Sessions.create(stranger)
			T.falsy(PS.grant(stranger, "coins_1m"))
			T.eq(#granted(w), 0)
			T.eq(#granted(w, stranger), 0)
			T.eq(w.data.money, 0)
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("9판 ProductService.processReceipt (MarketplaceService.ProcessReceipt)")

	T.test(
		"start(): MarketplaceService.ProcessReceipt 에 콜백을 하나 붙임 + PromptGamePassPurchaseFinished 연결 (62번)",
		function()
			local w = world()
			local market = fakeMarket(w)
			w.ProductService.start()
			T.eq(market.ProcessReceipt, w.ProductService.processReceipt)
			T.eq(#market.handlers, 1, "게임패스 구매 이벤트에 하나")
			T.eq(#w.H.warnings, 0)
			w.H.uninstall()
		end
	)

	T.test(
		"지급 + 저장 성공 → PurchaseGranted, 저장소(DataStore)에 영수증·코인이 들어감 · 같은 PurchaseId 가 또 와도 한 번만",
		function()
			local w = world()
			fakeConfigure(w)
			w.DataService.start()
			w.session.saveEnabled = true
			local r = receipt(w, "coins_1m", "purchase-A")
			T.eq(process(w, r), GRANTED)
			T.eq(w.data.money, 1e6)
			T.eq(table.concat(w.data.receipts, ","), "purchase-A")
			local stored = w.H.store.data["player_9001"].data
			T.eq(stored.money, 1e6, "저장됨")
			T.eq(stored.receipts[1], "purchase-A")
			-- 같은 영수증 다시 (로블록스 재시도)
			T.eq(process(w, r), GRANTED)
			T.eq(process(w, r), GRANTED)
			T.eq(w.data.money, 1e6, "한 번만 지급")
			T.eq(#w.data.receipts, 1)
			T.eq(#granted(w), 1)
			-- 다른 영수증은 또 지급
			T.eq(process(w, receipt(w, "coins_1m", "purchase-B")), GRANTED)
			T.eq(w.data.money, 2e6)
			T.eq(w.data.stats.productsBought, 2)
			w.H.uninstall()
		end
	)

	T.test(
		"플레이어 없음 → NotProcessedYet · 데이터 미로드면 기다렸다가(15초) NotProcessedYet · 기다리는 사이 불러와지면 지급",
		function()
			local w = world()
			fakeConfigure(w)
			w.DataService.start()
			-- 없는 사람
			local r = receipt(w, "coins_1m", "x1")
			r.PlayerId = 424242
			T.eq(process(w, r), NOT_YET)
			-- 이상한 영수증
			T.eq(process(w, { PlayerId = "9001", ProductId = 1, PurchaseId = "y" }), NOT_YET)
			T.eq(process(w, { PlayerId = 9001, ProductId = w.fakeIds.coins_1m }), NOT_YET, "PurchaseId 없음")
			-- 불러오는 중인 사람
			local late = w.H.newPlayer(9003, "Late")
			local session = w.Sessions.create(late)
			local started = w.H.clock()
			T.eq(process(w, receipt(w, "coins_1b", "late-1", late), 40), NOT_YET)
			T.truthy(w.H.clock() - started >= w.ProductService.LOAD_WAIT_SECONDS, "15초 기다림")
			-- 기다리는 사이 불러와짐
			local result = nil
			local co = coroutine.create(function()
				result = w.ProductService.processReceipt(receipt(w, "coins_1b", "late-2", late))
			end)
			coroutine.resume(co) -- 가짜 task.wait 에서 멈춤 (불러오기 기다림)
			w.H.advance(2)
			T.eq(result, nil, "아직 기다리는 중")
			w.H.login(late)
			session.saveEnabled = true
			w.H.advance(2)
			T.eq(result, GRANTED)
			T.eq(w.Sessions.get(late).data.money, 1e9)
			T.eq(w.data.money, 0, "다른 사람 것은 그대로")
			w.H.uninstall()
		end
	)

	T.test(
		"모르는 상품 id → NotProcessedYet (지급·영수증 기록 없음, 경고) · 저장 실패 → NotProcessedYet 이지만 다시 와도 두 번 안 줌",
		function()
			local w = world()
			fakeConfigure(w)
			w.DataService.start()
			local r = receipt(w, "coins_1m", "unknown-1")
			r.ProductId = 999
			T.eq(process(w, r), NOT_YET)
			T.eq(w.data.money, 0)
			T.eq(#w.data.receipts, 0)
			T.truthy(string.find(w.H.warnings[#w.H.warnings], "모르는 상품 id", 1, true))
			-- 저장이 꺼진 세션 (불러오기 실패 등): 지급은 하지만 NotProcessedYet → 로블록스가 나중에 다시 부름
			w.session.saveEnabled = false
			local r2 = receipt(w, "speed_10m", "nosave-1")
			local speed = w.data.speed
			T.eq(process(w, r2), NOT_YET)
			T.eq(w.data.speed, speed + 1e7)
			-- (주임 9판 F-1) 저장이 안 된 지급은 다시 와도 PurchaseGranted 로 확인하지 않음 (저장이 돼야 확인) — 두 번 지급은 없음
			T.eq(
				process(w, r2),
				NOT_YET,
				"저장이 안 된 채로는 확인하지 않음 (영수증은 있어서 두 번 안 줌)"
			)
			T.eq(w.data.speed, speed + 1e7, "두 번 안 줌")
			w.session.saveEnabled = true
			T.eq(process(w, r2), GRANTED, "저장이 되는 세션이 되면 저장하고 확인")
			T.eq(w.data.speed, speed + 1e7, "그래도 한 번만")
			w.H.uninstall()
		end
	)

	T.test(
		"영수증 기록은 최근 500개 고리 (주임 F-2: 100 → 500, 오래된 것부터 빠짐) · 지급 실패한 영수증은 안 남음",
		function()
			local w = world()
			fakeConfigure(w)
			w.DataService.start()
			w.session.saveEnabled = true
			for i = 1, 505 do
				T.eq(process(w, receipt(w, "coins_1m", "r" .. i)), GRANTED)
			end
			T.eq(#w.data.receipts, Config.RECEIPT_HISTORY_MAX)
			T.eq(Config.RECEIPT_HISTORY_MAX, 500)
			T.eq(w.data.receipts[1], "r6")
			T.eq(w.data.receipts[500], "r505")
			T.eq(w.data.money, 505e6)
			-- 지급 실패(상품 표에서 사라짐)는 기록하지 않음
			local real = w.Products.get
			w.Products.get = function()
				return nil
			end
			T.eq(process(w, receipt(w, "coins_1m", "gone-1")), NOT_YET)
			w.Products.get = real
			T.falsy(table.find(w.data.receipts, "gone-1"))
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("9판 저장 스키마 8 · Snapshot · 개발 명령 /buy")

	T.test(
		"스키마 8: 기본값(부스트 1 · 코인 2배 false · 영수증 {}) · 7 → 8 은 칸만 추가 · 이상한 값 보정",
		function()
			local DataSchema = Loader.require("ServerScriptService/Server/Logic/DataSchema")
			local d = DataSchema.default(0)
			T.eq(d.version, 8)
			T.eq(d.treadmillBoost, 1)
			T.eq(d.moneyPass, false)
			T.eq(#d.receipts, 0)
			local old = DataSchema.reconcile(DataSchema.migrate({ version = 7, money = 50, treadmillLevel = 3 }), 0)
			T.eq(old.version, 8)
			T.eq(old.money, 50)
			T.eq(old.treadmillLevel, 3)
			T.eq(old.treadmillBoost, 1)
			T.eq(old.moneyPass, false)
			T.eq(#old.receipts, 0)
			for raw, want in { [8] = 8, [9] = 8, [2048] = 2048, [1e9] = 2048, [1] = 1, [1.5] = 1, [0] = 1, [-4] = 1 } do
				T.eq(DataSchema.cleanTreadmillBoost(raw), want, "부스트 " .. tostring(raw))
			end
			for _, bad in { "8", true, {}, 0 / 0 } do
				T.eq(DataSchema.cleanTreadmillBoost(bad), 1, tostring(bad))
			end
			T.eq(DataSchema.reconcile({ version = 8, moneyPass = "yes" }, 0).moneyPass, false, "true 만 인정")
			T.eq(DataSchema.reconcile({ version = 8, moneyPass = true }, 0).moneyPass, true)
			local receipts = { "a", "a", 5, "", string.rep("x", 65), "b" }
			for i = 1, 520 do
				table.insert(receipts, "n" .. i)
			end
			local cleaned = DataSchema.cleanReceipts(receipts)
			T.eq(#cleaned, 500, "최근 500개")
			T.eq(cleaned[500], "n520")
			T.falsy(table.find(cleaned, "a"), "오래된 것은 빠짐")
			T.eq(
				#DataSchema.cleanReceipts({ "a", "a", 5, "", string.rep("x", 65), "b" }),
				2,
				"글자 1~64자, 중복 없이"
			)
			T.eq(#DataSchema.cleanReceipts("엉터리"), 0)
		end
	)

	T.test("Snapshot 전체·DataUpdate(upgrades) 에 treadmillBoost · moneyPass", function()
		local w = world()
		local Snapshot = w.H.server("Snapshot")
		w.data.treadmillBoost = 64
		w.data.moneyPass = true
		local snap = Snapshot.build(w.player)
		T.eq(snap.treadmillBoost, 64)
		T.eq(snap.moneyPass, true)
		Snapshot.section(w.player, "upgrades")
		local payload = lastSection(w, "upgrades")
		T.eq(payload.treadmillBoost, 64)
		T.eq(payload.moneyPass, true)
		w.ProductService.onPlayerReady(w.player)
		T.eq(w.player.attrs.TreadmillBoost, 64)
		T.eq(w.player.attrs.MoneyPass, true)
		w.H.uninstall()
	end)

	T.test(
		"개발 명령 /buy <key> (스튜디오): 영수증 없이 무료 지급, 모르는 키는 안내, 실서버에서는 꺼짐",
		function()
			local w = world()
			local DevCommands = w.H.server("Services/DevCommands")
			DevCommands.start()
			w.player.Chatted:Fire("/buy boost_2")
			T.eq(w.data.treadmillBoost, 2, "순서대로 (1 → 2)")
			T.eq(#w.data.receipts, 0, "영수증 기록 없음")
			T.eq(w.data.stats.productsBought, nil, "개발 지급은 구매 횟수에 안 셈")
			w.H.advance(2)
			-- /buy 도 같은 grant: 처음에 /buy boost_16 을 치면 ×8 + 남은 2 R$ 속도 (순서대로 열림)
			local speed = w.data.speed
			w.player.Chatted:Fire("/buy boost_16")
			T.eq(w.data.treadmillBoost, 8, "2 에서 boost_16 → 4(4)+8(8) = 12 R$ 어치만 ×8")
			T.eq(w.data.speed, speed + 4 * Config.PRODUCT_SPEED_PER_ROBUX, "남은 4 R$ 는 속도")
			w.H.advance(2)
			w.player.Chatted:Fire("/buy boost_16")
			T.eq(w.data.treadmillBoost, 16, "이제 바로 다음 배수라 그대로 16")
			w.H.advance(2)
			w.player.Chatted:Fire("/buy tskip_1")
			T.eq(w.data.treadmillLevel, 1)
			w.H.advance(2)
			w.player.Chatted:Fire("/buy 없는거")
			T.truthy(w.H.hasNotify(w.player, "error", "모르는 상품"))
			w.H.uninstall()
			-- 실서버(스튜디오 아님, DEV_USER_IDS 비어 있음): 명령이 연결되지 않음
			local w2 = world()
			w2.H.RunService.studio = false
			w2.H.server("Services/DevCommands").start()
			w2.player.Chatted:Fire("/buy coins_1b")
			T.eq(w2.data.money, 0)
			w2.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite(
		"62번 게임패스 (영구 = 패스 12개 · 소모품 = 개발자 상품 24개) — 소유 확인으로만 반영"
	)

	T.test(
		"boostFromOwnedPasses: 예산 = 가진 패스 가격 합, 2배부터 차례로 — {2,4,8}→8 · {2048}→1024 · {4}→2 · {}→1 · {2,8}→4 · 중복·모르는 값·NaN 무시",
		function()
			local function b(list)
				return Products.boostFromOwnedPasses(list)
			end
			T.eq(b({ 2, 4, 8 }), 8)
			T.eq(b({ 2048 }), 1024, "웹에서 2048 만: 2~1024 (2046 R$) 까지")
			T.eq(b({ 4 }), 2)
			T.eq(b({}), 1)
			T.eq(b({ 2, 8 }), 4, "예산 10: 2+4, 남 4 < 8")
			T.eq(b({ 8, 2 }), 4, "순서 상관 없음")
			T.eq(b({ 2, 2, 2 }), 2, "중복은 한 번만")
			T.eq(b({ 2, 4, 4, 4 }), 4)
			T.eq(b({ 3, 0 / 0, -2, 1e9, math.huge }), 1, "모르는 값·NaN 무시")
			T.eq(b({ "4", true, {} }), 1, "숫자가 아니면 무시")
			T.eq(b(nil), 1, "목록이 없으면 1")
			local all = {}
			for _, m in Products.BOOST_MULTIPLIERS do
				table.insert(all, m)
			end
			T.eq(b(all), 2048, "11개 다 가짐")
			table.remove(all, 1)
			T.eq(b(all), 1024, "2배만 빠짐: 예산 4092 → 1024 (2048 은 순서대로)")
			-- 순서대로 사면 언제나 마지막 배수 (treadmillBoostOutcome 과 같음)
			local owned, boost = {}, 1
			for _, p in Products.treadmillBoosts do
				table.insert(owned, p.value)
				boost = Products.treadmillBoostOutcome(boost, p)
				T.eq(b(owned), p.value)
				T.eq(boost, p.value)
			end
		end
	)

	T.test(
		"byProductId 는 개발자 상품만 · byPassId 는 패스만 (진짜 Products 파일에 id 를 붙여서) — 패스 id 로 영수증 지급은 없음",
		function()
			local P = patchedProducts({ boost_2 = 11, money_pass = 12, tskip_1 = 13, coins_1m = 14, boost_2048 = 15 })
			T.eq(P.byProductId(11), nil, "boost_2 는 패스")
			T.eq(P.byProductId(12), nil, "money_pass 는 패스")
			T.eq(P.byProductId(15), nil)
			T.eq(P.byPassId(11).key, "boost_2")
			T.eq(P.byPassId(12).key, "money_pass")
			T.eq(P.byPassId(15).key, "boost_2048")
			T.eq(P.byProductId(13).key, "tskip_1")
			T.eq(P.byProductId(14).key, "coins_1m")
			T.eq(P.byPassId(13), nil, "tskip_1 은 개발자 상품")
			T.eq(P.byPassId(14), nil)
			T.truthy(P.isConfigured(P.get("boost_2")) and P.isConfigured(P.get("money_pass")))
			T.falsy(P.isConfigured(P.get("boost_4")))
			T.eq(P.get("boost_2").productId, 11, "패스도 productId 칸 (= gamePassId)")
		end
	)

	T.test(
		"syncPasses: 가진 패스 → 배수·코인 2배 (+ Attr · DataUpdate) · 안 가짐 → 그대로 · ProductGranted 는 안 보냄 · id 없는 패스는 확인 안 함 · 데이터 미로드면 아무것도 안 함",
		function()
			local w = world({}) -- 36칸 전부 0 인 사본 (진짜 파일에는 진짜 id 가 붙어 있음)
			local market = fakeMarket(w)
			-- id 를 하나도 안 붙임 (전부 0 인 표): 확인 호출 없음
			T.truthy(sync(w))
			T.eq(market.calls, 0, "id 없는 패스는 확인 안 함")
			fakeConfigurePasses(w)
			-- 안 가짐
			T.truthy(sync(w))
			T.eq(market.calls, 12, "id 붙은 패스 12개를 확인")
			T.eq(w.data.treadmillBoost, 1)
			T.eq(w.data.moneyPass, false)
			T.eq(lastSection(w, "upgrades"), nil, "안 바뀌면 DataUpdate 없음")
			-- 2·4배 + 코인 2배를 가짐
			own(w, market, "boost_2", "boost_4", "money_pass")
			T.truthy(sync(w))
			T.eq(w.data.treadmillBoost, 4)
			T.eq(w.data.moneyPass, true)
			T.eq(w.player.attrs.TreadmillBoost, 4)
			T.eq(w.player.attrs.MoneyPass, true)
			T.eq(lastSection(w, "upgrades").treadmillBoost, 4)
			T.eq(#granted(w), 0, "접속 때 맞추는 것은 구매 알림이 아님")
			T.eq(w.data.stats.productsBought, nil)
			-- 데이터 미로드 사람
			local loading = w.H.newPlayer(9002, "Loading")
			w.Sessions.create(loading)
			local before = market.calls
			T.falsy(sync(w, loading))
			T.eq(market.calls, before, "불러오기 전에는 확인도 안 함")
			w.H.uninstall()
			-- onPlayerReady 가 따로(task.spawn) 맞춤
			local w2 = world()
			local market2 = fakeMarket(w2)
			fakeConfigurePasses(w2)
			own(w2, market2, "boost_2", "boost_4", "boost_8")
			w2.ProductService.onPlayerReady(w2.player)
			w2.H.advance(1)
			T.eq(w2.data.treadmillBoost, 8)
			T.eq(w2.player.attrs.TreadmillBoost, 8)
			w2.H.uninstall()
		end
	)

	T.test(
		"[I-4] 진짜 id 가 붙은 파일: syncPasses 는 패스 12개의 id 만 소유 확인 (개발자 상품 id 는 안 물어봄) · 진짜 id 로 가진 패스는 그대로 반영",
		function()
			local w = world() -- 진짜 파일 그대로 (id 값은 안 봄)
			local market = fakeMarket(w)
			local P = w.Products
			local passIds = {}
			for _, p in P.passes do
				T.truthy(P.isConfigured(p), p.key .. " 진짜 id 가 붙어 있음")
				passIds[p.productId] = p.key
			end
			market.owned[P.get("boost_2").productId] = true
			market.owned[P.get("boost_4").productId] = true
			market.owned[P.get("money_pass").productId] = true
			T.truthy(sync(w))
			T.eq(market.calls, 12, "패스 12개를 한 번씩 확인")
			for _, p in P.passes do
				T.eq(market.tries[p.productId], 1, p.key .. " 소유 확인 1번")
			end
			for id in market.tries do
				T.truthy(passIds[id], "물어본 id " .. tostring(id) .. " 는 패스 id")
			end
			for _, p in P.list do
				if not p.isPass then
					T.eq(market.tries[p.productId], nil, p.key .. " 는 개발자 상품 — 소유 확인 안 함")
				end
			end
			T.eq(w.data.treadmillBoost, 4)
			T.eq(w.data.moneyPass, true)
			T.eq(w.player.attrs.TreadmillBoost, 4)
			T.eq(#granted(w), 0, "접속 때 맞추는 것은 구매 알림이 아님")
			w.H.uninstall()
		end
	)

	T.test(
		"syncPasses: 확인이 실패하면 2번 더 (사이 1초) · 전부 실패하면 데이터 그대로 false · 절대 안 낮춤 (저장값·/buy 로 받은 것 유지)",
		function()
			local w = world()
			local market = fakeMarket(w)
			fakeConfigurePasses(w)
			own(w, market, "boost_2", "money_pass")
			-- 처음 2번 실패, 3번째 성공 → 반영
			market.failFirst = 2
			local started = w.H.clock()
			T.truthy(sync(w))
			T.eq(market.calls, 36, "패스 12개 × 3번")
			T.truthy(w.H.clock() - started >= 2 * w.ProductService.PASS_RETRY_SECONDS, "사이 1초씩 기다림")
			T.eq(w.data.treadmillBoost, 2)
			T.eq(w.data.moneyPass, true)
			w.H.uninstall()
			-- 늘 실패 → false, 그대로
			local w2 = world()
			local m2 = fakeMarket(w2)
			fakeConfigurePasses(w2)
			own(w2, m2, "boost_2", "boost_4", "money_pass")
			m2.failFirst = math.huge
			w2.data.treadmillBoost = 1
			T.falsy(sync(w2))
			T.eq(m2.calls, 12 * (1 + w2.ProductService.PASS_CHECK_RETRIES), "3번씩 해 봄")
			T.eq(w2.data.treadmillBoost, 1, "데이터 그대로")
			T.eq(w2.data.moneyPass, false)
			T.truthy(string.find(w2.H.warnings[#w2.H.warnings], "소유 확인 실패", 1, true))
			w2.H.uninstall()
			-- 절대 안 낮춤: 저장값 64 · 코인 2배 true, 패스는 2배만 → 64 그대로
			local w3 = world()
			local m3 = fakeMarket(w3)
			fakeConfigurePasses(w3)
			own(w3, m3, "boost_2")
			w3.data.treadmillBoost = 64
			w3.data.moneyPass = true
			T.truthy(sync(w3))
			T.eq(w3.data.treadmillBoost, 64)
			T.eq(w3.data.moneyPass, true)
			T.eq(w3.player.attrs.TreadmillBoost, 64)
			w3.H.uninstall()
		end
	)

	T.test(
		"PromptGamePassPurchaseFinished: wasPurchased false·모르는 id·개발자 상품 id 무시 · 소유 확인 false 면 미지급(안내) · 확인되면 지급 + ProductGranted · 두 번 와도 ProductGranted 1번",
		function()
			local w = world()
			local market = fakeMarket(w)
			fakeConfigure(w)
			fakeConfigurePasses(w)
			w.ProductService.start()
			T.eq(#market.handlers, 1)
			local fire = function(id, wasPurchased)
				w.H.run(function()
					market.handlers[1](w.player, id, wasPurchased)
				end)
			end
			-- 안 삼 / 모르는 id / 개발자 상품 id
			own(w, market, "boost_2")
			fire(w.passIds.boost_2, false)
			fire(424242, true)
			fire(w.fakeIds.coins_1m, true)
			T.eq(market.calls, 0, "확인 호출도 없음")
			T.eq(#granted(w), 0)
			T.eq(w.data.treadmillBoost, 1)
			-- 샀다는데 로블록스 소유 확인은 false → 지급 안 함 + 안내
			fire(w.passIds.boost_4, true)
			T.eq(w.data.treadmillBoost, 1)
			T.eq(#granted(w), 0)
			T.truthy(w.H.hasNotify(w.player, "info", "구매를 확인하는 중이에요"))
			-- 진짜 삼 (2배)
			fire(w.passIds.boost_2, true)
			T.eq(w.data.treadmillBoost, 2)
			T.eq(w.player.attrs.TreadmillBoost, 2)
			T.eq(lastSection(w, "upgrades").treadmillBoost, 2)
			local g = granted(w)
			T.eq(#g, 1)
			T.eq(g[1].key, "boost_2")
			T.eq(g[1].kind, "treadmillBoost")
			T.truthy(w.H.hasNotify(w.player, "success", "러닝머신 부스트 x2"))
			T.eq(w.data.stats.productsBought, 1)
			-- 같은 이벤트가 또 옴 → ProductGranted 1번 그대로
			fire(w.passIds.boost_2, true)
			T.eq(#granted(w), 1, "두 번 와도 한 번만")
			T.eq(w.data.stats.productsBought, 1)
			-- 동시에 두 번 (첫 확인이 실패해서 1초 기다리는 사이 또 옴) → 한 번만
			own(w, market, "money_pass")
			market.tries = {}
			market.failFirst = 1
			local done = 0
			for _ = 1, 2 do
				coroutine.resume(coroutine.create(function()
					w.ProductService.onGamePassPurchaseFinished(w.player, w.passIds.money_pass, true)
					done += 1
				end))
			end
			T.eq(done, 1, "두 번째는 바로 끝남 (확인 중인 패스)")
			w.H.advance(5)
			T.eq(done, 2)
			T.eq(w.data.moneyPass, true)
			T.eq(w.player.attrs.MoneyPass, true)
			local moneyGrants = 0
			for _, item in granted(w) do
				if item.key == "money_pass" then
					moneyGrants += 1
				end
			end
			T.eq(moneyGrants, 1)
			T.truthy(w.H.hasNotify(w.player, "success", "코인 2배!"))
			-- 패스는 영수증으로는 안 옴: 패스 id 로 영수증이 와도 모르는 상품
			T.eq(
				process(w, { PlayerId = w.player.UserId, ProductId = w.passIds.boost_8, PurchaseId = "fake-pass" }),
				NOT_YET
			)
			T.eq(w.data.treadmillBoost, 2)
			w.H.uninstall()
		end
	)

	T.test(
		"건너뛴 패스 (위조 클라·웹): 4배 패스만 사면 ×2 + '순서대로 열려요' 안내 (ProductGranted 는 감) · 그다음 2배를 사면 ×4 · 저장 시도",
		function()
			local w = world()
			local market = fakeMarket(w)
			fakeConfigurePasses(w)
			w.DataService.start()
			w.session.saveEnabled = true
			own(w, market, "boost_4")
			passFinished(w, "boost_4", true)
			T.eq(w.data.treadmillBoost, 2, "낸 4 R$ 만큼만: 2배 (남 2)")
			T.truthy(w.H.hasNotify(w.player, "success", "스피드 배수는 순서대로 열려요. 지금 x2"))
			T.eq(granted(w)[1].key, "boost_4")
			T.eq(w.H.store.data["player_9001"].data.treadmillBoost, 2, "저장됨")
			own(w, market, "boost_2")
			passFinished(w, "boost_2", true)
			T.eq(w.data.treadmillBoost, 4, "2·4배 다 가짐 → 4")
			T.truthy(w.H.hasNotify(w.player, "success", "러닝머신 부스트 x4"))
			T.eq(#granted(w), 2)
			T.eq(w.data.stats.productsBought, 2)
			T.eq(w.H.store.data["player_9001"].data.treadmillBoost, 4)
			w.H.uninstall()
		end
	)
end
