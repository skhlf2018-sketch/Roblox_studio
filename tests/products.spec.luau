--!nocheck
--[[
	9판 로벅스 상품 (사장님 2026-11-10): shared/Data/Products 표 · 서버 ProductService (grant · ProcessReceipt) ·
	러닝머신 부스트 · 코인 2배 · 저장 스키마 8 · 개발 명령 /buy
	진짜 서비스 코드를 ServerHarness 위에서 (가상 시간). MarketplaceService 는 가짜 (ProcessReceipt 콜백만 받음).
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
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

	-- 가짜 세상: 진짜 Net · Sessions · Snapshot · Wallet · DataService · ProductService (+ 필요하면 더)
	local function world()
		local H = ServerHarness.install(Loader, T)
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

	-- 상품 id 를 가짜로 붙임 (Products.IDS 는 아직 전부 0 이라서): byProductId 만 바꿔 끼움
	local function fakeConfigure(w)
		w.fakeIds = {}
		local byId = {}
		for i, product in w.Products.list do
			w.fakeIds[product.key] = 100000 + i
			byId[100000 + i] = product
		end
		w.Products.byProductId = function(id)
			return byId[id]
		end
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
		end
	)

	T.test(
		"상품 id 는 Products.IDS 한 곳 (36칸, 지금은 전부 0 = 미설정): isConfigured false · byProductId 는 0·음수·모름이면 nil",
		function()
			local count = 0
			for key, id in Products.IDS do
				count += 1
				T.truthy(Products.byKey[key], "IDS 의 모르는 키 " .. key)
				T.eq(id, 0, key .. " 는 아직 0 (아빠가 Creator Dashboard 에서 만든 뒤 붙임)")
			end
			T.eq(count, #Products.list, "IDS 칸 수 = 상품 수")
			for _, p in Products.list do
				T.eq(p.productId, Products.IDS[p.key])
				T.falsy(Products.isConfigured(p), p.key)
			end
			T.truthy(Products.isConfigured({ key = "x", kind = "coins", name = "x", robux = 1, productId = 42 }))
			for _, bad in { 0, -1, 123456, 0 / 0, "5" } do
				T.eq(Products.byProductId(bad), nil, tostring(bad))
			end
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
		"러닝머신 부스트: 산 것 중 가장 큰 배수 (곱 아님) · 작은 것을 또 사면 그대로(안내) · Attr TreadmillBoost · ProductGranted · DataUpdate(upgrades)",
		function()
			local w = world()
			local PS = w.ProductService
			T.eq(w.data.treadmillBoost, 1)
			T.truthy(PS.grant(w.player, "boost_8", "purchase"))
			T.eq(w.data.treadmillBoost, 8)
			T.eq(w.player.attrs.TreadmillBoost, 8)
			local g = granted(w)
			T.eq(g[1].key, "boost_8")
			T.eq(g[1].kind, "treadmillBoost")
			T.eq(lastSection(w, "upgrades").treadmillBoost, 8)
			T.truthy(PS.grant(w.player, "boost_4"))
			T.eq(w.data.treadmillBoost, 8, "더 작은 것은 그대로 (8 × 4 = 32 가 아님)")
			T.truthy(w.H.hasNotify(w.player, "info", "가장 큰 것 하나만"))
			T.eq(#granted(w), 2, "그래도 소비 처리 (환불 없음) — ProductGranted 는 감")
			T.truthy(PS.grant(w.player, "boost_8"))
			T.eq(w.data.treadmillBoost, 8)
			T.truthy(PS.grant(w.player, "boost_2048"))
			T.eq(w.data.treadmillBoost, 2048)
			T.eq(w.data.stats.productsBought, 4)
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
			w.ProductService.grant(w.player, "boost_8") -- ×8
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
		"러닝머신 레벨 올리기: 레벨이 N-1 이면 N (코인 안 듦) · 안 맞으면 다음 1칸 · 최대면 속도 보상 — 돈을 받았으니 언제나 뭔가 줌",
		function()
			local w = world()
			local PS = w.ProductService
			w.data.money = 777
			T.truthy(PS.grant(w.player, "tskip_1"))
			T.eq(w.data.treadmillLevel, 1, "0 → 1 (해금)")
			T.eq(w.player.attrs.TreadmillLevel, 1)
			T.eq(lastSection(w, "upgrades").treadmillLevel, 1)
			T.truthy(PS.grant(w.player, "tskip_2"))
			T.eq(w.data.treadmillLevel, 2)
			T.eq(w.data.money, 777, "코인 안 듦")
			-- 안 맞음 (아래): 2레벨인데 10레벨 상품 → 다음 1칸 (3)
			T.truthy(PS.grant(w.player, "tskip_10"))
			T.eq(w.data.treadmillLevel, 3)
			-- 안 맞음 (위·두 번 누름): 3레벨인데 3레벨 상품 → 4
			T.truthy(PS.grant(w.player, "tskip_3"))
			T.eq(w.data.treadmillLevel, 4)
			w.data.treadmillLevel = 19
			T.truthy(PS.grant(w.player, "tskip_20"))
			T.eq(w.data.treadmillLevel, 20)
			-- 최대에서 또: 속도 보상 (최대 1초 속도 × 600 = 600M)
			local speed = w.data.speed
			T.truthy(PS.grant(w.player, "tskip_20"))
			T.eq(w.data.treadmillLevel, 20, "최대 그대로")
			T.eq(w.data.speed, speed + 1000000 * Config.PRODUCT_MAXED_SKIP_SECONDS)
			T.eq(Config.PRODUCT_MAXED_SKIP_SECONDS, 600)
			T.truthy(w.H.hasNotify(w.player, "success", "최대 레벨이라 대신 속도"))
			T.eq(#granted(w), 6, "6번 다 ProductGranted")
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

	T.test("start(): MarketplaceService.ProcessReceipt 에 콜백을 하나 붙임", function()
		local w = world()
		local market = {}
		Loader.service("MarketplaceService", market)
		w.ProductService.start()
		T.eq(market.ProcessReceipt, w.ProductService.processReceipt)
		w.H.uninstall()
	end)

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
		"영수증 기록은 최근 100개 고리 (오래된 것부터 빠짐) · 지급 실패한 영수증은 안 남음",
		function()
			local w = world()
			fakeConfigure(w)
			w.DataService.start()
			w.session.saveEnabled = true
			for i = 1, 105 do
				T.eq(process(w, receipt(w, "coins_1m", "r" .. i)), GRANTED)
			end
			T.eq(#w.data.receipts, Config.RECEIPT_HISTORY_MAX)
			T.eq(Config.RECEIPT_HISTORY_MAX, 100)
			T.eq(w.data.receipts[1], "r6")
			T.eq(w.data.receipts[100], "r105")
			T.eq(w.data.money, 105e6)
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
			for i = 1, 120 do
				table.insert(receipts, "n" .. i)
			end
			local cleaned = DataSchema.cleanReceipts(receipts)
			T.eq(#cleaned, 100, "최근 100개")
			T.eq(cleaned[100], "n120")
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
			w.player.Chatted:Fire("/buy boost_16")
			T.eq(w.data.treadmillBoost, 16)
			T.eq(#w.data.receipts, 0, "영수증 기록 없음")
			T.eq(w.data.stats.productsBought, nil, "개발 지급은 구매 횟수에 안 셈")
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
end
