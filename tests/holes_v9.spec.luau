--!nocheck
--[[
	9판 주임 검수 (구멍 찾기) — 수석 0ab9c70 (로벅스 상품 36개 · 열매 먹이기 삭제 · 밤 귀가 배달 버그) + 선임 d74a3ff
	products.spec / night_carry.spec(수석이 쓴 기본 시험)과 겹치지 않게 "돈이 걸린 길의 구멍·경계·반복·무작위" 위주.
	  A 구매 지급 안전성 (ProcessReceipt: 중복 · 동시 · 저장 실패 · 나감 · 500개 고리(F-2) · 모르는 id · 다른 사람 · Remote 로 닿는 길)
	  B 효과 정확성 (부스트 최댓값 · 러닝머신 이득 · 레벨 상품 20개 × 상황 · 코인 2배 · 상한 · 스키마 7 → 8 · Snapshot/Attr)
	  C 열매 먹이기 잔재 (코드 안 남았나 · 원소 돌연변이 legacy · 열매 가방/판매)
	  D 밤 귀가 버그 (정상 배달 보존 · 두 명 · 쓰러진 상태 · 튜토리얼)
	  E 상품 켜기 시나리오 (아빠가 id 를 붙여 넣은 뒤: 진짜 Products 파일을 바꿔 끼워서)
	  F 보안 회귀 (두 사람 무작위 요청 1,000번 + 무작위 영수증 섞기)
	표 숫자는 코드가 아니라 docs/SEED_GAME_DESIGN.md 9장 52~57번 · docs/ROBUX_SETUP.md 를 이 파일에 따로 적어 대조함.
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local S = "ReplicatedStorage/Shared/"
	local V = "ServerScriptService/Server/"
	local Config = Loader.require(S .. "Data/Config")
	local Upgrades = Loader.require(S .. "Data/Upgrades")
	local Plants = Loader.require(S .. "Data/Plants")
	local Mutations = Loader.require(S .. "Data/Mutations")
	local Economy = Loader.require(S .. "Economy")
	local EggRoll = Loader.require(S .. "EggRoll")
	local FruitRules = Loader.require(S .. "FruitRules")
	local GardenRules = Loader.require(S .. "GardenRules")
	local EggPlacement = Loader.require(S .. "EggPlacement")
	local MapLayout = Loader.require(S .. "Data/MapLayout")
	local Remotes = Loader.require(S .. "Remotes")

	local GRANTED = "ProductPurchaseDecision.PurchaseGranted"
	local NOT_YET = "ProductPurchaseDecision.NotProcessedYet"

	-- 사장님 가격표 (docs/ROBUX_SETUP.md 3장) — 코드와 따로 적어 대조
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

	-- 주임 F-3 수정 규칙의 기준 계산 (서버 코드와 따로): 레벨 상품 tskip_n 을 level 에서 샀을 때 (새 레벨, 속도로 받을 R$)
	--   맞으면(level = n-1) n · 안 맞으면 예산 = 그 상품 R$ 로 다음 레벨 가격부터 차례로 빼며 살 수 있는 만큼, 남은 R$ 는 속도
	local function skipExpect(level, n)
		if level == n - 1 then
			return n, 0
		end
		local budget, current = SKIP_ROBUX[n], level
		while current < 20 and SKIP_ROBUX[current + 1] <= budget do
			budget -= SKIP_ROBUX[current + 1]
			current += 1
		end
		return current, budget
	end

	-- 사장님 2026-11-10 "스피드 배수는 2배를 사야 4배가 열리는 식" 규칙의 기준 계산 (서버·Products 코드와 따로):
	--   부스트 상품 boost_v (값 = 가격 = v R$) 를 지금 배수 current (1, 2, 4 … 2048) 에서 샀을 때 (새 배수, 속도로 받을 R$)
	--   바로 다음 배수(current × 2)면 v · 아니면 예산 = v R$ 로 current × 2 부터 차례로 빼며 살 수 있는 만큼, 남은 R$ 는 속도
	local function boostExpect(current, v)
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

	-- 소스에서 주석(--[[ ... ]] 블록과 -- 줄 주석)을 뺀 코드 글자
	local function stripComments(text)
		text = string.gsub(text, "%-%-%[%[.-%]%]", "")
		text = string.gsub(text, "%-%-[^\n]*", "")
		return text
	end

	local function finite(n)
		return typeof(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
	end

	local function deepCopy(value)
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in value do
			out[k] = deepCopy(v)
		end
		return out
	end

	------------------------------------------------------------------
	-- 진짜 Products 파일에서 id 칸만 바꾼 모듈 (아빠가 Creator Dashboard id 를 붙여 넣은 뒤를 흉내)
	------------------------------------------------------------------
	local function patchedProducts(replacements)
		local source = fs.readFile("src/shared/Data/Products.luau")
		for key, id in replacements do
			local pattern = "\n\t" .. key .. " = 0,"
			local from, to = string.find(source, pattern, 1, true)
			assert(from, "Products.luau 에 '" .. key .. " = 0,' 칸이 없음")
			source = string.sub(source, 1, from - 1)
				.. "\n\t"
				.. key
				.. " = "
				.. tostring(id)
				.. ","
				.. string.sub(source, to + 1)
		end
		local ConfigNow = Loader.require(S .. "Data/Config")
		local chunk = luau.load(source, {
			debugName = "Products(patched)",
			environment = {
				script = { Parent = { Config = "CONFIG" } },
				require = function()
					return ConfigNow
				end,
			},
		})
		return chunk()
	end

	------------------------------------------------------------------
	-- 세상: 진짜 Net · Sessions · Snapshot · Wallet · DataService · ProductService · PetService
	--   opts.ids = { key = 숫자 } 이면 진짜 Products 파일의 id 칸을 바꿔 끼움 (아니면 byProductId 를 가짜로 — fakeConfigure)
	------------------------------------------------------------------
	local function newWorld(opts)
		opts = opts or {}
		local H = ServerHarness.install(Loader, T, opts.harness)
		local w = { H = H }
		if opts.ids then
			w.Products = patchedProducts(opts.ids)
			Loader.mock(S .. "Data/Products", w.Products)
		end
		H.startNet()
		w.Products = w.Products or H.shared("Data/Products")
		w.Sessions = H.server("Sessions")
		w.DataService = H.server("Services/DataService")
		w.ProductService = H.server("Services/ProductService")
		w.PetService = H.server("Services/PetService")
		w.player = H.newPlayer(9501, "Buyer")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		return w
	end

	local function inWorld(opts, fn)
		local w = newWorld(opts)
		local ok, err = pcall(fn, w)
		w.H.uninstall()
		if not ok then
			error(err, 0)
		end
	end

	-- 상품 id 를 가짜로 붙임 (Products.IDS 는 아직 전부 0): byProductId 만 바꿔 끼움
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

	local function receipt(w, productKey, purchaseId, player)
		return {
			PlayerId = (player or w.player).UserId,
			ProductId = w.fakeIds[productKey],
			PurchaseId = purchaseId,
			CurrencySpent = 1,
		}
	end

	local function process(w, r, maxSeconds)
		return w.H.run(function()
			return w.ProductService.processReceipt(r)
		end, maxSeconds or 30)
	end

	-- 저장 켜기: 진짜 DataService (가짜 DataStore) + 저장 가능 세션
	local function enableSaving(w)
		w.DataService.start()
		w.session.saveEnabled = true
	end

	local function grantedList(w, player)
		local list = {}
		for _, args in w.H.sent(player or w.player, "ProductGranted") do
			table.insert(list, args[1])
		end
		return list
	end

	local function grantedCount(w, key, player)
		local n = 0
		for _, g in grantedList(w, player) do
			if g.key == key then
				n += 1
			end
		end
		return n
	end

	local function stored(w, player)
		local entry = w.H.store.data["player_" .. (player or w.player).UserId]
		return entry and entry.data
	end

	-- 저장이 느린 가짜 DataStore: slow = true 인 동안 UpdateAsync 가 멈춰 서 있음 (parked 코루틴), pump 로 풀어 줌
	local function slowStore(w)
		local store = w.H.store
		local original = store.UpdateAsync
		local parked = {}
		store.slow = true
		function store:UpdateAsync(key, transform)
			if self.slow then
				table.insert(parked, coroutine.running())
				coroutine.yield()
			end
			return original(self, key, transform)
		end
		return parked
	end

	local function pump(w, parked, rounds)
		for _ = 1, rounds or 20 do
			w.H.advance(0.2)
			while #parked > 0 do
				coroutine.resume(table.remove(parked, 1))
			end
		end
	end

	-- 코루틴으로 processReceipt 시작 (yield 하면 멈춰 있음). 결과는 box.value
	local function start(w, r)
		local box = {}
		box.co = coroutine.create(function()
			box.value = w.ProductService.processReceipt(r)
		end)
		local ok, err = coroutine.resume(box.co)
		assert(ok, tostring(err))
		return box
	end

	------------------------------------------------------------------
	T.suite(
		"9판 주임 검수 A: 구매 지급 안전성 (ProcessReceipt — 중복 · 동시 · 저장 실패 · 나감)"
	)

	T.test(
		"같은 PurchaseId 가 순서대로 3번 와도 종류마다(코인·속도·부스트·레벨·코인 2배) 정확히 1번만 지급 · ProductGranted 1번 · 영수증 1개",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				local speed0 = w.data.speed
				-- boost_2 → boost_8 : 8 은 바로 다음이 아니라서 (2 → 4 → 8 순서) ×4 + 남은 4 R$ 속도 — 그 속도도 영수증이 또 와도 한 번만
				for _, key in { "coins_1b", "speed_10m", "boost_2", "boost_8", "tskip_1", "money_pass" } do
					local r = receipt(w, key, "once-" .. key)
					T.eq(process(w, r), GRANTED, key .. " 첫 영수증")
					local money, speed, boost, level, pass =
						w.data.money, w.data.speed, w.data.treadmillBoost, w.data.treadmillLevel, w.data.moneyPass
					T.eq(process(w, r), GRANTED, key .. " 두 번째")
					T.eq(process(w, r), GRANTED, key .. " 세 번째")
					T.eq(w.data.money, money, key .. ": 코인 또 안 줌")
					T.eq(w.data.speed, speed, key .. ": 속도 또 안 줌")
					T.eq(w.data.treadmillBoost, boost)
					T.eq(w.data.treadmillLevel, level, key .. ": 레벨 또 안 올림")
					T.eq(w.data.moneyPass, pass)
					T.eq(grantedCount(w, key), 1, key .. ": ProductGranted 1번")
				end
				T.eq(#w.data.receipts, 6)
				T.eq(w.data.stats.productsBought, 6)
				T.eq(w.data.money, 1e9)
				T.eq(
					w.data.speed,
					speed0 + 1e7 + 4 * Config.PRODUCT_SPEED_PER_ROBUX,
					"속도: 상품 + 건너뛴 부스트의 남은 4 R$ (한 번씩만)"
				)
				T.eq(w.data.treadmillBoost, 4, "boost_2 → 2, boost_8 은 순서가 안 맞아 ×4")
				T.eq(w.data.treadmillLevel, 1)
				T.eq(w.data.moneyPass, true)
				local s = stored(w)
				T.eq(#s.receipts, 6, "저장소에도 6개")
				T.eq(s.money, 1e9)
				T.eq(s.treadmillBoost, 4)
				T.eq(s.moneyPass, true)
			end)
		end
	)

	T.test(
		"[F-1] 저장이 안 된 영수증은 다시 와도 PurchaseGranted 로 확인하지 않음 (저장 실패 → NotProcessedYet → 또 와도 NotProcessedYet, 코인은 한 번만) — 저장되면 그때 PurchaseGranted",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				w.H.store.failNext = 1000 -- DataStore 계속 실패
				local r = receipt(w, "coins_1m", "fail-1")
				T.eq(process(w, r, 120), NOT_YET, "저장 실패면 로블록스가 나중에 다시 부르게")
				T.eq(w.data.money, 1e6, "메모리에는 지급됨")
				T.eq(stored(w), nil, "저장소에는 아무것도 없음")
				-- 로블록스가 같은 영수증을 또 보냄 (저장소는 아직 고장)
				T.eq(
					process(w, r, 120),
					NOT_YET,
					"저장 안 된 지급을 'PurchaseGranted' 라고 확인하면 안 됨 (서버가 꺼지면 돈만 받고 상품이 사라짐)"
				)
				T.eq(w.data.money, 1e6, "두 번 안 줌")
				T.eq(#w.data.receipts, 1)
				T.eq(grantedCount(w, "coins_1m"), 1)
				-- 저장소 복구 → 다시 오면 저장하고 PurchaseGranted
				w.H.store.failNext = 0
				T.eq(process(w, r), GRANTED)
				T.eq(w.data.money, 1e6, "그래도 한 번만")
				local s = stored(w)
				T.truthy(
					s ~= nil and s.money == 1e6 and s.receipts[1] == "fail-1",
					"이제 저장소에 코인과 영수증이 같이 있음"
				)
				T.eq(process(w, r), GRANTED, "저장된 뒤에는 바로 확인")
				T.eq(w.data.money, 1e6)
			end)
		end
	)

	T.test(
		"[F-1] 저장을 끈 세션(불러오기 실패 · 남의 서버가 락을 가져감 · 새 버전 데이터)도 같음: 지급은 메모리에만, 영수증이 몇 번 와도 NotProcessedYet · 코인 한 번",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				w.session.saveEnabled = false
				local r = receipt(w, "speed_100m", "nosave-9")
				local speed = w.data.speed
				for i = 1, 3 do
					T.eq(process(w, r), NOT_YET, i .. "번째")
				end
				T.eq(w.data.speed, speed + 1e8, "한 번만")
				T.eq(grantedCount(w, "speed_100m"), 1)
				-- 나중에 저장이 되는 세션이 되면 (예: 다시 접속) 저장하고 확인
				w.session.saveEnabled = true
				T.eq(process(w, r), GRANTED)
				T.eq(w.data.speed, speed + 1e8)
				T.eq(stored(w).receipts[1], "nosave-9")
			end)
		end
	)

	T.test(
		"[F-1] 같은 영수증이 동시에 두 번 와도(첫째가 저장하는 중) 둘째는 저장이 끝난 뒤에야 확인 · 한 번만 지급 · 저장도 성공",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				local parked = slowStore(w)
				local r = receipt(w, "coins_1b", "twin-1")
				local first = start(w, r)
				T.eq(first.value, nil, "첫째: 저장 기다리는 중")
				T.eq(w.data.money, 1e9, "지급은 바로 됨")
				T.eq(#parked, 1)
				local second = start(w, r)
				w.H.advance(1)
				T.eq(
					second.value,
					nil,
					"둘째는 첫째의 저장이 끝나기 전에 PurchaseGranted 를 돌려주면 안 됨 (저장이 실패하면 돈만 받은 셈)"
				)
				T.eq(w.data.money, 1e9, "한 번만")
				w.H.store.slow = false
				pump(w, parked, 30)
				T.eq(first.value, GRANTED)
				T.eq(second.value, GRANTED)
				T.eq(w.data.money, 1e9)
				T.eq(#w.data.receipts, 1)
				T.eq(grantedCount(w, "coins_1b"), 1)
				T.eq(stored(w).money, 1e9)
			end)
		end
	)

	T.test(
		"동시에 서로 다른 영수증 두 개 (저장이 느림): 둘 다 지급 · 둘 다 저장 뒤 PurchaseGranted · 레벨 상품 둘은 레벨이 2칸 오름",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				local parked = slowStore(w)
				local a = start(w, receipt(w, "tskip_1", "pair-a"))
				local b = start(w, receipt(w, "tskip_2", "pair-b"))
				T.eq(w.data.treadmillLevel, 2, "tskip_1 → 1, tskip_2 → 2")
				w.H.store.slow = false
				pump(w, parked, 40)
				T.eq(a.value, GRANTED)
				T.eq(b.value, GRANTED)
				T.eq(w.data.treadmillLevel, 2)
				T.eq(#w.data.receipts, 2)
				T.eq(stored(w).treadmillLevel, 2)
			end)
		end
	)

	T.test(
		"지급 도중 서버 오류(알림 보내기에서 오류)가 나도: 효과는 이미 한 번 적용 · 로블록스가 다시 부르면 저장하고 PurchaseGranted · 또 지급 안 함",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				local Net = w.H.server("Net")
				local realFire = Net.fire
				Net.fire = function(player, name, ...)
					if name == "ProductGranted" then
						error("가짜 오류")
					end
					return realFire(player, name, ...)
				end
				local r = receipt(w, "coins_1m", "boom-1")
				local ok = w.H.run(function()
					return (pcall(w.ProductService.processReceipt, r))
				end)
				T.eq(ok, false, "오류 → 로블록스는 NotProcessedYet 로 봄")
				T.eq(w.data.money, 1e6, "효과는 오류 전에 한 번 적용")
				T.eq(#w.data.receipts, 1)
				Net.fire = realFire
				T.eq(process(w, r), GRANTED, "다시 오면 저장하고 확인")
				T.eq(w.data.money, 1e6, "또 지급 안 함")
				T.eq(stored(w).money, 1e6, "저장됨")
				T.eq(stored(w).receipts[1], "boom-1")
				T.eq(w.data.stats.productsBought, 1)
			end)
		end
	)

	T.test(
		"저장소를 못 쓰는 서버(메모리 모드): 스튜디오는 저장할 게 없어서 PurchaseGranted, 실서버는 NotProcessedYet (저장이 안 되니 확인하면 안 됨) · 어느 쪽도 한 번만 지급",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				w.H.DataStoreService.available = false
				w.DataService.start()
				T.truthy(w.DataService.isMemoryMode(), "GetDataStore 실패 → 메모리 모드")
				w.session.saveEnabled = true
				-- 스튜디오 (기본)
				T.eq(process(w, receipt(w, "coins_1m", "mm-1")), GRANTED)
				T.eq(w.data.money, 1e6)
				-- 실서버
				w.H.RunService.studio = false
				local r = receipt(w, "coins_1m", "mm-2")
				T.eq(process(w, r), NOT_YET, "실서버 메모리 모드는 저장이 안 됨")
				T.eq(w.data.money, 2e6)
				T.eq(process(w, r), NOT_YET, "다시 와도 확인하지 않음")
				T.eq(w.data.money, 2e6, "한 번만")
			end)
		end
	)

	T.test(
		"영수증 기록 500개 고리 (주임 F-2: 100 → 500): 최근 500개 안의 PurchaseId 는 몇 번 와도 한 번만 (경계 500번째까지)",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				T.eq(Config.RECEIPT_HISTORY_MAX, 500)
				for i = 1, 500 do
					T.eq(process(w, receipt(w, "coins_1m", "ring-" .. i)), GRANTED)
				end
				T.eq(w.data.money, 500e6)
				-- 가장 오래된 것(1번)도 아직 기록 안에 있음 → 다시 와도 안 줌
				T.eq(process(w, receipt(w, "coins_1m", "ring-1")), GRANTED)
				T.eq(process(w, receipt(w, "coins_1m", "ring-500")), GRANTED)
				T.eq(w.data.money, 500e6, "고리 안에서는 두 번 안 줌")
				T.eq(#w.data.receipts, 500)
			end)
		end
	)

	T.test(
		"[F-2 수정] 영수증 101번째가 와도 1번째 기록이 남아 있음 (고리 500) — 옛 PurchaseId 가 다시 와도 또 지급 안 됨 · 501번째부터는 가장 오래된 것이 빠짐 (로블록스는 PurchaseGranted 한 영수증은 다시 안 보내므로 실제로는 거의 안 일어남)",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				for i = 1, 101 do
					T.eq(process(w, receipt(w, "coins_1m", "evict-" .. i)), GRANTED)
				end
				T.eq(w.data.money, 101e6)
				T.eq(process(w, receipt(w, "coins_1m", "evict-1")), GRANTED)
				T.eq(w.data.money, 101e6, "101장째에도 1번째 영수증은 기록 안 — 또 지급 안 함")
				T.eq(#w.data.receipts, 101)
				for i = 102, 501 do
					process(w, receipt(w, "coins_1m", "evict-" .. i))
				end
				T.eq(#w.data.receipts, Config.RECEIPT_HISTORY_MAX, "501장째부터 고리 크기 그대로")
				T.eq(w.data.receipts[1], "evict-2", "가장 오래된 1번째만 빠짐")
			end)
		end
	)

	T.test(
		"PurchaseId 이상한 값: 빈 글자 · 아주 긴 글자 · 숫자 · 표는 안전하게 (빈 글자는 지급 안 함 / 긴 글자는 64자로 잘라 기록해서 저장·불러오기에도 중복 방지가 유지)",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				local DataSchema = w.H.server("Logic/DataSchema")
				T.eq(process(w, receipt(w, "coins_1m", "")), NOT_YET, "빈 PurchaseId")
				T.eq(w.data.money, 0)
				T.eq(#w.data.receipts, 0)
				local long = string.rep("x", 200)
				T.eq(process(w, receipt(w, "coins_1m", long)), GRANTED)
				T.eq(process(w, receipt(w, "coins_1m", long)), GRANTED)
				T.eq(w.data.money, 1e6, "긴 PurchaseId 도 한 번만")
				T.eq(#w.data.receipts[1], 64, "64자로 기록 (저장 데이터 정리 규칙과 같게)")
				local reloaded = DataSchema.reconcile(deepCopy(stored(w)), 0)
				T.eq(#reloaded.receipts, 1, "불러와도 기록이 안 사라짐")
				T.eq(process(w, receipt(w, "coins_1m", 12345)), GRANTED, "숫자 PurchaseId")
				T.eq(process(w, receipt(w, "coins_1m", 12345)), GRANTED)
				T.eq(w.data.money, 2e6)
				T.eq(
					process(w, { PlayerId = w.player.UserId, ProductId = w.fakeIds.coins_1m, PurchaseId = {} }),
					GRANTED
				)
				T.eq(
					w.data.money,
					3e6,
					"표 PurchaseId 는 글자로 바뀌어 일단 한 번 지급 (로블록스는 항상 글자를 줌)"
				)
				T.eq(w.data.treadmillBoost, 1)
			end)
		end
	)

	T.test(
		"서버가 꺼졌다 켜져도(저장소 복사 → 새 세상 → 다시 불러옴) 지급한 영수증은 다시 와도 안 줌 · 저장 못 한 영수증은 새로 지급",
		function()
			local savedStore
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				T.eq(process(w, receipt(w, "coins_1b", "boot-1")), GRANTED)
				w.H.store.failNext = 1000
				T.eq(process(w, receipt(w, "speed_10m", "boot-2"), 120), NOT_YET, "저장 못 함")
				savedStore = deepCopy(w.H.store.data)
			end)
			inWorld(nil, function(w)
				fakeConfigure(w)
				w.H.store.data = deepCopy(savedStore)
				w.DataService.start()
				local data, saveEnabled = w.H.run(function()
					return w.DataService.load(w.player)
				end)
				w.session.data, w.session.loaded, w.session.saveEnabled = data, true, saveEnabled
				w.data = data
				local speed0 = data.speed
				T.truthy(saveEnabled)
				T.eq(data.money, 1e9, "저장된 지급은 그대로")
				T.truthy(speed0 < 1e7, "저장 못 한 지급(속도 10M)은 없음 → 로블록스가 다시 부름")
				T.eq(process(w, receipt(w, "coins_1b", "boot-1")), GRANTED)
				T.eq(data.money, 1e9, "이미 지급한 영수증 — 두 번 안 줌")
				T.eq(process(w, receipt(w, "speed_10m", "boot-2")), GRANTED)
				T.eq(data.speed, speed0 + 1e7, "저장 못 했던 영수증은 이제 지급")
				T.eq(#data.receipts, 2)
			end)
		end
	)

	T.test(
		"지급 도중 플레이어가 나감: 저장하던 중이면 저장이 끝나면 PurchaseGranted (영수증+지급이 같이 저장), 이미 나갔으면 NotProcessedYet · 지급 안 함 · 나중에 새 접속에서 한 번만",
		function()
			local leftStore
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				local parked = slowStore(w)
				local r = receipt(w, "coins_1b", "leave-1")
				local box = start(w, r) -- 저장 기다리는 중
				T.eq(w.data.money, 1e9)
				-- 플레이어가 나가 버림 (PlayerLifecycle.onPlayerRemoving 과 같은 순서)
				w.H.leave(w.player)
				w.H.store.slow = false
				pump(w, parked, 30)
				T.eq(box.value, GRANTED, "이미 저장 중이던 것은 저장이 끝났으니 확인")
				T.eq(stored(w).money, 1e9)
				T.eq(stored(w).receipts[1], "leave-1")
				-- 이미 나간 뒤에 온 영수증
				w.Sessions.remove(w.player)
				T.eq(process(w, receipt(w, "coins_1m", "leave-2")), NOT_YET)
				T.eq(stored(w).money, 1e9, "저장소 그대로")
				leftStore = deepCopy(w.H.store.data)
			end)
			inWorld(nil, function(w)
				fakeConfigure(w)
				w.H.store.data = deepCopy(leftStore)
				w.DataService.start()
				local data, saveEnabled = w.H.run(function()
					return w.DataService.load(w.player)
				end)
				w.session.data, w.session.loaded, w.session.saveEnabled = data, true, saveEnabled
				T.eq(process(w, receipt(w, "coins_1b", "leave-1")), GRANTED)
				T.eq(data.money, 1e9, "다시 접속해서 같은 영수증 — 두 번 안 줌")
				T.eq(process(w, receipt(w, "coins_1m", "leave-2")), GRANTED)
				T.eq(data.money, 1e9 + 1e6, "나가서 못 받은 영수증은 이제 한 번 지급")
			end)
		end
	)

	T.test(
		"모르는 · 이상한 ProductId (999 · 0 · -1 · NaN · 소수 · 큰 수 · 글자 · 없음) → NotProcessedYet · 지급·영수증 기록 없음 (진짜 Products 표는 id 가 전부 0 이라 ProductId 0 영수증이 아무 상품과도 안 맞음)",
		function()
			inWorld(nil, function(w)
				enableSaving(w)
				local speed0 = w.data.speed
				-- fakeConfigure 안 함: 진짜 표 (id 전부 0 = 아직 아무것도 안 켬)
				for _, p in w.Products.list do
					T.eq(w.Products.byProductId(0), nil)
					T.eq(p.productId, 0)
				end
				for i, bad in { 999, 0, -1, 0 / 0, 1.5, 1e300, math.huge, "123", false, true, {} } do
					local r = { PlayerId = w.player.UserId, ProductId = bad, PurchaseId = "bad-" .. i }
					T.eq(process(w, r), NOT_YET, "ProductId " .. tostring(bad))
				end
				T.eq(process(w, { PlayerId = w.player.UserId, PurchaseId = "bad-nil" }), NOT_YET, "ProductId 없음")
				T.eq(w.data.money, 0)
				T.eq(w.data.speed, speed0)
				T.eq(w.data.treadmillBoost, 1)
				T.eq(w.data.treadmillLevel, 0)
				T.eq(w.data.moneyPass, false)
				T.eq(
					#w.data.receipts,
					0,
					"처리 못 한 영수증은 기록 안 함 (나중에 진짜 id 를 붙인 뒤 다시 오면 지급)"
				)
				T.eq(#grantedList(w), 0)
			end)
		end
	)

	T.test(
		"receipt.PlayerId: 다른 사람 것이면 그 사람에게만 지급 (내 데이터 불변) · 서버에 없는 사람 · 글자/소수/NaN/표 PlayerId → NotProcessedYet",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				local other = w.H.newPlayer(9502, "Friend")
				local otherSession, otherData = w.H.login(other)
				otherSession.plotIndex = 2
				otherSession.saveEnabled = true
				T.eq(process(w, receipt(w, "coins_1b", "friend-1", other)), GRANTED)
				T.eq(otherData.money, 1e9, "친구에게 지급")
				T.eq(w.data.money, 0, "내 것은 그대로")
				T.eq(#w.data.receipts, 0)
				T.eq(#otherData.receipts, 1)
				T.eq(grantedCount(w, "coins_1b", w.player), 0)
				T.eq(grantedCount(w, "coins_1b", other), 1)
				for _, badId in { 424242, "9501", 9501.5, 0 / 0, math.huge, {}, false } do
					local r = receipt(w, "coins_1b", "badpid")
					r.PlayerId = badId
					T.eq(process(w, r), NOT_YET, "PlayerId " .. tostring(badId))
				end
				T.eq(w.data.money, 0)
				T.eq(otherData.money, 1e9)
				T.eq(process(w, { ProductId = w.fakeIds.coins_1m, PurchaseId = "nopid" }), NOT_YET, "PlayerId 없음")
			end)
		end
	)

	T.test(
		"클라가 grant 에 닿는 길이 없음: ProductGranted 는 서버 → 클라 전용 · 모든 클라→서버 Remote 에 상품 키·id·영수증을 던져도 부스트·코인 2배·코인·속도·레벨이 안 바뀜 · /buy 는 스튜디오·DEV 만",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				local Cfg = w.H.shared("Data/Config")
				for _, name in { "ProductGranted" } do
					T.eq(#w.H.remotes[name].OnServerEvent.handlers, 0, name .. " 은 서버가 안 들음")
				end
				-- 서버가 듣는 Remote 전부에 상품 관련 값을 던짐
				for _, svc in
					{ "PetService", "FruitService", "UpgradeService", "BaseService", "IndexService", "SakuraService" }
				do
					w.H.server("Services/" .. svc).start()
				end
				w.H.server("Services/TreadmillService").start()
				w.H.server("Services/ToolService").start()
				local junk = {}
				for _, p in w.Products.list do
					table.insert(junk, p.key)
					table.insert(junk, p.productId)
					table.insert(junk, w.fakeIds[p.key])
					table.insert(junk, { key = p.key, kind = p.kind, productId = w.fakeIds[p.key] })
					table.insert(
						junk,
						{ PlayerId = w.player.UserId, ProductId = w.fakeIds[p.key], PurchaseId = "forged" }
					)
				end
				local snapshot = function()
					return table.concat({
						tostring(w.data.money),
						tostring(w.data.speed),
						w.data.treadmillBoost,
						tostring(w.data.moneyPass),
						w.data.treadmillLevel,
						#w.data.receipts,
					}, "|")
				end
				local before = snapshot()
				local names = {}
				for name in Remotes.ToServer do
					table.insert(names, name)
				end
				for _, name in names do
					for i = 1, #junk, 7 do
						w.H.client(w.player, name, junk[i], junk[i + 1], junk[i + 2])
					end
					w.H.client(w.player, name, "money_pass", "boost_2048", "tskip_20")
					w.H.client(w.player, name, { "money_pass" }, 2048, 20)
				end
				-- 서버→클라 이름으로 위조
				for name in Remotes.ToClient do
					w.H.client(w.player, name, "boost_2048", 2048)
					w.H.client(w.player, name, { key = "money_pass", kind = "moneyPass" })
				end
				T.eq(snapshot(), before, "Remote 로는 상품 효과가 하나도 안 생김")
				T.eq(w.data.stats.productsBought, nil)
				-- /buy: 스튜디오에서 연결해 둔 뒤 실서버처럼 바뀌어도 (안전망) 명령을 한 번 더 확인해서 무시함
				local Dev = w.H.server("Services/DevCommands")
				Dev.start() -- 스튜디오 (DEV_USER_IDS 비어 있음) → 연결됨
				w.H.RunService.studio = false
				w.player.Chatted:Fire("/buy money_pass")
				w.player.Chatted:Fire("/buy boost_2048")
				T.eq(snapshot(), before, "스튜디오가 아니면 /buy 무시 (연결돼 있어도)")
				-- DEV_USER_IDS 에 남의 번호만 있으면 나는 못 씀 / 내 번호가 있으면 됨
				table.insert(Cfg.DEV_USER_IDS, 111)
				w.player.Chatted:Fire("/buy money_pass")
				T.eq(snapshot(), before, "DEV 목록에 없는 사람은 /buy 못 씀")
				table.insert(Cfg.DEV_USER_IDS, w.player.UserId)
				w.player.Chatted:Fire("/buy boost_2")
				T.eq(w.data.treadmillBoost, 2, "DEV 목록에 있는 사람만 됨 (개발자)")
				T.eq(#w.data.receipts, 0, "개발 지급은 영수증 기록 없음")
			end)
		end
	)

	T.test(
		"소스 점검: 상품 지급 함수 grant 를 부르는 곳은 ProductService 안과 DevCommands(/buy) 뿐 · MarketplaceService.ProcessReceipt 를 정하는 곳은 ProductService 한 곳",
		function()
			local callers = {}
			local assigners = {}
			local function walk(dir)
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						walk(path)
					elseif string.match(name, "%.luau?$") then
						local joined = stripComments(fs.readFile(path))
						if string.find(joined, "ProductService.grant(", 1, true) then
							table.insert(callers, path)
						end
						if string.find(joined, "ProcessReceipt", 1, true) then
							table.insert(assigners, path)
						end
					end
				end
			end
			walk("src")
			table.sort(callers)
			table.sort(assigners)
			T.eq(
				table.concat(callers, ","),
				"src/server/Services/DevCommands.luau,src/server/Services/ProductService.luau"
			)
			T.eq(table.concat(assigners, ","), "src/server/Services/ProductService.luau")
		end
	)

	------------------------------------------------------------------
	T.suite(
		"9판 주임 검수 E: 상품 켜기 시나리오 (아빠가 id 를 붙여 넣은 뒤 — 진짜 Products 파일의 id 칸만 바꿔 끼움)"
	)

	T.test(
		"id 몇 개만 붙인 파일: 붙인 것만 isConfigured · 개발자 상품은 byProductId, 게임패스는 byPassId 로만 찾아짐 (62번) · 나머지는 준비 중 · 진짜 ProcessReceipt 로 상품만 지급 (패스 id 로 온 영수증·안 붙인 것의 id 는 안 지급) · 패스는 소유 확인(syncPasses)으로",
		function()
			inWorld(
				{ ids = { boost_2 = 5001, boost_2048 = 5002, tskip_1 = 5003, money_pass = 5004, coins_1m = 5005 } },
				function(w)
					enableSaving(w)
					local P = w.Products
					local configured = {}
					for _, p in P.list do
						if P.isConfigured(p) then
							table.insert(configured, p.key)
						end
					end
					table.sort(configured)
					T.eq(table.concat(configured, ","), "boost_2,boost_2048,coins_1m,money_pass,tskip_1")
					T.eq(P.byProductId(5002), nil, "boost_2048 은 게임패스 — 영수증 표에 없음")
					T.eq(P.byPassId(5002).key, "boost_2048")
					T.eq(P.byPassId(5004).key, "money_pass")
					T.eq(P.byProductId(5005).key, "coins_1m")
					T.eq(P.byPassId(5005), nil, "coins_1m 은 개발자 상품 — 패스 표에 없음")
					T.eq(P.byProductId(0), nil, "0 은 여전히 아무것도 아님")
					T.eq(P.byProductId(5006), nil)
					T.eq(P.get("boost_4").productId, 0, "안 붙인 것은 0")
					local function r(productId, purchaseId)
						return { PlayerId = w.player.UserId, ProductId = productId, PurchaseId = purchaseId }
					end
					-- 패스 id 로 영수증이 와도 (로블록스는 안 보내지만) 지급 안 함 — 모르는 상품 경로
					T.eq(process(w, r(5001, "p1")), NOT_YET)
					T.eq(process(w, r(5004, "p2")), NOT_YET)
					T.eq(w.data.treadmillBoost, 1)
					T.eq(w.data.moneyPass, false)
					T.eq(process(w, r(5003, "p4")), GRANTED)
					T.eq(w.data.treadmillLevel, 1)
					T.eq(process(w, r(5005, "p6")), GRANTED)
					T.eq(w.data.money, 1e6)
					-- 안 붙인 상품 (boost_4 는 id 0): 로블록스가 보낼 수 없지만, 만약 ProductId 0 이나 다른 id 가 오면 지급 안 함
					T.eq(process(w, r(0, "p7")), NOT_YET)
					T.eq(process(w, r(5009, "p8")), NOT_YET)
					T.eq(w.data.money, 1e6)
					T.eq(#w.data.receipts, 2)
					-- 패스는 소유 확인으로: 웹에서 2배·2048배 패스와 코인 2배를 가짐 → 예산 2050 → 1024 (2048 은 순서대로 열려야 함)
					local asked = {}
					Loader.service("MarketplaceService", {
						UserOwnsGamePassAsync = function(_, userId, passId)
							table.insert(asked, passId)
							return userId == w.player.UserId and (passId == 5001 or passId == 5002 or passId == 5004)
						end,
					})
					T.truthy(w.H.run(function()
						return w.ProductService.syncPasses(w.player)
					end))
					table.sort(asked)
					T.eq(table.concat(asked, ","), "5001,5002,5004", "id 붙은 패스 3개만 확인")
					T.eq(w.data.treadmillBoost, 1024)
					T.eq(w.data.moneyPass, true)
					T.eq(w.player.attrs.TreadmillBoost, 1024)
					T.eq(w.player.attrs.MoneyPass, true)
				end
			)
		end
	)

	T.test(
		"아빠용 안내(docs/ROBUX_SETUP.md 3장 표)의 36개 key·가격이 코드(Data/Products)와 똑같음 — 안내대로 Creator Dashboard 에 만들면 게임 버튼의 가격과 같음",
		function()
			local P = Loader.require(S .. "Data/Products")
			local doc = fs.readFile("docs/ROBUX_SETUP.md")
			local rows, count = {}, 0
			for line in string.gmatch(doc .. "\n", "([^\n]*)\n") do
				local key = string.match(line, "^|%s*`([%w_]+)`%s*|")
				if key then
					local cells = {}
					for cell in string.gmatch(line, "|([^|]*)") do
						table.insert(cells, cell)
					end
					local price = tonumber(string.match(cells[3] or "", "(%d+)"))
					T.falsy(rows[key], "안내에 " .. key .. " 가 두 번")
					rows[key] = price
					count += 1
				end
			end
			T.eq(count, 36, "안내 표의 상품 수")
			for _, p in P.list do
				T.eq(rows[p.key], p.robux, "안내 표의 " .. p.key .. " 가격 (코드 " .. p.robux .. ")")
			end
			-- 사장님 표(위 SKIP_ROBUX · 부스트 = 배수 · 상점 5개)와도 같음
			for n, robux in SKIP_ROBUX do
				T.eq(rows["tskip_" .. n], robux)
			end
			for _, m in { 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048 } do
				T.eq(rows["boost_" .. m], m)
			end
			T.eq(rows.money_pass, 199)
			T.eq(rows.coins_1m, 99)
			T.eq(rows.coins_1b, 199)
			T.eq(rows.speed_10m, 199)
			T.eq(rows.speed_100m, 259)
		end
	)

	T.test(
		"[F-4] 같은 id 를 두 상품에 붙여 넣은 실수는 시험이 잡는다: 붙인 id 들은 서로 겹치면 안 되고 0 보다 큰 정수 (지금 파일은 전부 0 이라 통과)",
		function()
			-- 진짜 파일의 규칙 점검 (아빠가 숫자를 붙인 뒤 `lune run tests/run.luau` 로 확인)
			local P = Loader.require(S .. "Data/Products")
			local used = {}
			for key, id in P.IDS do
				T.truthy(
					type(id) == "number" and id == id and id >= 0 and id == math.floor(id),
					key .. " id 는 0 이상 정수"
				)
				if id > 0 then
					T.falsy(
						used[id],
						key
							.. " 와 "
							.. tostring(used[id])
							.. " 가 같은 id "
							.. id
							.. " — 한 상품 id 를 두 군데 붙임"
					)
					used[id] = key
				end
			end
			-- 같은 id 를 두 상품에 붙이면 byProductId 가 한 쪽만 돌려줌 (지급이 엉뚱한 상품으로 가는 것을 보여 줌)
			inWorld({ ids = { tskip_1 = 777, coins_1b = 777, boost_2 = 778, boost_2048 = 778 } }, function(w)
				local hit = w.Products.byProductId(777)
				T.truthy(hit ~= nil)
				local twins = 0
				for _, p in w.Products.list do
					if p.productId == 777 then
						twins += 1
					end
				end
				T.eq(twins, 2, "같은 id 를 두 상품에 붙인 파일")
				T.truthy(
					hit.key == "tskip_1" or hit.key == "coins_1b",
					"겹치면 한쪽만 지급됨 — 겹치게 붙이지 말 것"
				)
				-- 게임패스도 같음 (62번: byPassId)
				local passHit = w.Products.byPassId(778)
				T.truthy(passHit and (passHit.key == "boost_2" or passHit.key == "boost_2048"))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite(
		"9판 주임 검수 B: 효과 정확성 (부스트 · 러닝머신 이득 · 레벨 상품 20개 · 코인 2배 · 상한 · 스키마 8 · Snapshot/Attr)"
	)

	T.test(
		"부스트는 순서대로만 열림 (곱 아님): 11개를 무작위 순서로 60번 사도 treadmillBoostOutcome 모델과 정확히 같고 · 낸 R$ 합보다 많이 받지 못함 (배수 값 + 속도로 받은 R$ = 낸 R$) · 2048 이 된 뒤 2 를 사도 2048 · Attr 도 같이",
		function()
			inWorld(nil, function(w)
				local PS = w.ProductService
				local E = w.H.shared("Economy")
				local RATE = Config.PRODUCT_SPEED_PER_ROBUX
				local rand = T.rng(2048)
				local list = w.Products.treadmillBoosts
				local boost, paid, bought = 1, 0, 0
				local speed0 = w.data.speed
				local function buy(p, label)
					local before = boost
					local speed = w.data.speed
					T.truthy(PS.grant(w.player, p.key, "purchase"), label)
					bought += 1
					paid += p.robux
					local want, leftover = boostExpect(before, p.value)
					-- 진짜 순수 함수도 같은 답
					local pureBoost, pureLeft = w.Products.treadmillBoostOutcome(before, p)
					T.eq(pureBoost, want, label .. ": treadmillBoostOutcome 배수")
					T.eq(pureLeft, leftover, label .. ": treadmillBoostOutcome 남은 R$")
					boost = want
					T.eq(w.data.treadmillBoost, boost, label)
					T.eq(w.player.attrs.TreadmillBoost, boost, label .. ": Attr")
					T.eq(w.data.speed, speed + leftover * RATE, label .. ": 속도")
					T.truthy(boost >= before, label .. ": 배수는 내려가지 않음")
					-- 보존: (배수 값 2N-2 = 2·4·…·N 가격 합) + 속도로 받은 R$ = 낸 R$
					T.eq(
						2 * boost - 2 + (w.data.speed - speed0) / RATE,
						paid,
						label .. ": 낸 R$ = 배수 값 + 속도 값"
					)
				end
				for i = 1, 60 do
					local p = list[math.floor(rand() * #list) + 1]
					buy(p, i .. "번째 " .. p.key)
				end
				-- 끝까지 가 봄: 2048 상품만 계속 사도 순서대로 (1024 → 2048) 에서 멈추고 더는 안 오름
				local guard = 0
				while boost < 2048 and guard < 20 do
					guard += 1
					buy(w.Products.get("boost_2048"), "2048 향해 " .. guard)
				end
				T.eq(boost, 2048, "결국 2048")
				buy(w.Products.get("boost_2"), "2048 뒤 boost_2")
				T.eq(w.data.treadmillBoost, 2048)
				T.eq(E.treadmillGainPerSecond(20, 1, w.data.treadmillBoost), 1e6 * 2048)
				T.eq(
					w.data.stats.productsBought,
					bought,
					"전부 구매로 셈 (남은 R$ 만 받은 것도 돈은 받았음)"
				)
			end)
		end
	)

	T.test(
		"러닝머신 틱 이득 = 레벨 × 트레일 × 부스트 (진짜 TreadmillService, 20레벨 · 가장 센 트레일 · ×2048) — 걸음마다 정확히, SPEED_MAX 직전에는 SPEED_MAX 에서 멈추고 NaN·무한 없음",
		function()
			inWorld(nil, function(w)
				local TS = w.H.server("Services/TreadmillService")
				local SpeedService = w.H.server("Services/SpeedService")
				local Cfg = w.H.shared("Data/Config")
				local Up = w.H.shared("Data/Upgrades")
				TS.start()
				local bestTrail = Up.Trails[1]
				for _, t in Up.Trails do
					if t.multiplier > bestTrail.multiplier then
						bestTrail = t
					end
				end
				w.data.treadmillLevel = 20
				w.data.trails = { bestTrail.id }
				w.data.equippedTrail = bestTrail.id
				w.data.treadmillBoost = 2048 -- 순서대로 사서 2048 이 되는 길은 위 테스트와 holes_boost_order 가 검사 — 여기서는 곱셈만
				w.ProductService.grant(w.player, "boost_8") -- 가진 것을 또 삼: 배수 그대로 (남은 값은 속도 — 아래 before 는 이 뒤에 잼)
				local plot = w.H.MapLayout.plot(1)
				w.H.spawn(w.player, plot.treadmill.x, 3, plot.treadmill.z)
				w.H.advance(0.5)
				T.eq(w.player.attrs.OnTreadmill, true)
				local perSecond = 1e6 * bestTrail.multiplier * 2048
				local before = w.data.speed
				w.H.clearSent()
				w.H.advance(3)
				local steps = w.H.sent(w.player, "TreadmillStep")
				T.truthy(#steps >= 2)
				local sum = 0
				for _, args in steps do
					T.eq(args[1].amount, perSecond, "걸음마다 레벨 20 × 트레일 × 2048")
					sum += args[1].amount
				end
				T.eq(
					w.data.speed - before,
					sum,
					"속도가 걸음 합계만큼 (부스트가 두 번 곱해지지 않음)"
				)
				-- 상한 직전
				w.data.speed = Cfg.SPEED_MAX - 5
				w.H.advance(1.2)
				T.eq(w.data.speed, Cfg.SPEED_MAX, "SPEED_MAX 에서 멈춤")
				SpeedService.refresh(w.player)
				T.truthy(finite(w.session.effectiveSpeed), "실효 속도 유한")
				T.truthy(finite(w.player.attrs.BaseSpeed) and w.player.attrs.BaseSpeed <= Cfg.SPEED_MAX)
				w.H.advance(2)
				T.eq(w.data.speed, Cfg.SPEED_MAX, "계속 타도 안 넘음")
			end)
		end
	)

	T.test(
		"레벨 상품 20개 × 상황(레벨 맞음 N-1 · 낮음 · 높음 · 19 · 최대 20): 맞으면 N, 안 맞으면 산 R$ 만큼만 (살 수 있는 레벨 + 남은 R$ × 환산율 속도, 주임 F-3 수정) — 코인은 절대 안 듦 · 20 을 넘지 않음 · 언제나 뭔가 줌 · Attr·ProductGranted 맞음",
		function()
			inWorld(nil, function(w)
				local PS = w.ProductService
				local RATE = Config.PRODUCT_SPEED_PER_ROBUX
				w.data.money = 4242
				local cases = 0
				for n = 1, 20 do
					local levels, seen = {}, {}
					for _, level in { 0, n - 2, n - 1, n, 19, 20 } do
						if level >= 0 and level <= 20 and not seen[level] then
							seen[level] = true
							table.insert(levels, level)
						end
					end
					for _, level in levels do
						w.data.treadmillLevel = level
						local speed = w.data.speed
						local count = #grantedList(w)
						T.truthy(PS.grant(w.player, "tskip_" .. n), "tskip_" .. n .. " @" .. level)
						local want, leftover = skipExpect(level, n)
						T.eq(w.data.treadmillLevel, want, "tskip_" .. n .. " 레벨 " .. level .. " → ")
						T.eq(w.player.attrs.TreadmillLevel, want)
						T.eq(w.data.speed, speed + leftover * RATE, "tskip_" .. n .. " @" .. level .. " 속도")
						T.truthy(
							want > level or w.data.speed > speed,
							"tskip_" .. n .. " @" .. level .. ": 0 지급 없음"
						)
						-- 받은 레벨 값 + 속도로 받은 R$ = 산 값 (안 맞을 때 더 주지 않음)
						if level ~= n - 1 then
							local spent = 0
							for k = level + 1, want do
								spent += SKIP_ROBUX[k]
							end
							T.eq(spent + leftover, SKIP_ROBUX[n], "tskip_" .. n .. " @" .. level .. ": 산 값만큼")
						end
						T.eq(w.data.money, 4242, "코인 안 듦")
						T.eq(#grantedList(w), count + 1)
						T.truthy(w.data.treadmillLevel <= 20 and w.data.treadmillLevel >= 0)
						cases += 1
					end
				end
				T.truthy(cases >= 100, "경우의 수 " .. cases)
				T.eq(Config.PRODUCT_MAXED_SKIP_SECONDS, nil, "8판식 최대 레벨 600M 고정 보상 없앰")
			end)
		end
	)

	T.test(
		"[F-3 수정] 가장 싼 tskip_1 (3 R$) 을 계속 사도 레벨이 안 오름 (속도만 R$ 만큼) · 최대 레벨에서도 3 R$ 는 속도 3 × 환산율 — 환산율은 속도 100M 상품(259 R$)보다 유리하지 않음",
		function()
			inWorld(nil, function(w)
				local PS = w.ProductService
				T.truthy(Config.PRODUCT_SPEED_PER_ROBUX <= 1e8 / 259, "환산율 ≤ 속도 100M 상품 R$ 당 속도")
				w.data.treadmillLevel = 1
				local paid = 0
				local speed0 = w.data.speed
				for _ = 1, 19 do
					PS.grant(w.player, "tskip_1") -- 레벨이 1 이상이면 안 맞는 상품
					paid += 3
				end
				-- 정상 가격으로 2 ~ 20레벨을 사려면 10+30+...+20000 R$ (표 합계)
				local honest = 0
				for n = 2, 20 do
					honest += SKIP_ROBUX[n]
				end
				T.truthy(
					w.data.treadmillLevel < 20 or paid >= honest,
					"3 R$ × 19 = " .. paid .. " R$ 로 20레벨 (정상 " .. honest .. " R$)"
				)
				T.eq(w.data.treadmillLevel, 1, "3 R$ 로는 2레벨(10 R$)도 못 삼")
				T.eq(w.data.speed, speed0 + paid * Config.PRODUCT_SPEED_PER_ROBUX, "대신 낸 R$ 만큼 속도")
				-- 싼 상품 여러 장을 모아도 비싼 레벨은 안 됨 (한 장씩 따로 계산)
				w.data.treadmillLevel = 5
				for _ = 1, 200 do
					PS.grant(w.player, "tskip_2")
				end
				T.eq(w.data.treadmillLevel, 5, "10 R$ × 200 장으로도 6레벨(399 R$) 못 얻음")
				w.data.treadmillLevel = 20
				local speed = w.data.speed
				PS.grant(w.player, "tskip_1")
				local gain = w.data.speed - speed
				T.truthy(gain > 0, "최대 레벨에서도 0 지급 없음")
				T.truthy(
					gain / 3 <= 1e8 / 259,
					"3 R$ 로 속도 " .. gain .. " (속도 상품은 R$ 당 " .. 1e8 / 259 .. ")"
				)
			end)
		end
	)

	T.test(
		"코인 2배(money_pass): 열매 판매 · 성체 팔기 둘 다 × 2, 두 번 사도 × 2 (× 4 아님) · 진짜 영수증 두 장으로 사도 × 2 · 안 사면 × 1 · 옛 게임패스 플래그(hasMoneyPass) 없음",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				local FruitService = w.H.server("Services/FruitService")
				local GR = w.H.shared("GardenRules")
				local EP = w.H.shared("EggPlacement")
				local DataSchema = w.H.server("Logic/DataSchema")
				local stall = w.H.MapLayout.hubSpots.sellStall
				w.H.spawn(w.player, stall.x, 3, stall.z)
				T.eq(w.session.hasMoneyPass, nil, "9판: 세션 플래그 없음")
				T.eq(
					w.H.shared("Data/Config").GAMEPASS_MONEY_MULTIPLIER,
					nil,
					"9판: 옛 게임패스 배율 상수 없음"
				)
				local function plant(petId)
					local taken = {}
					for _, r in w.data.pets do
						table.insert(taken, { x = r.x, z = r.z, size = r.size })
					end
					local spot = EP.firstFreeGrid("normal", taken)
					local record = {
						uid = DataSchema.newUid(w.data, "p"),
						petId = petId,
						size = "normal",
						mutations = { "golden", "frozen" },
						x = spot.x,
						z = spot.z,
						fruits = 0,
						fruitProgress = 0,
					}
					assert(w.PetService.addPlant(w.player, record))
					return record
				end
				-- 안 샀을 때 (× 1)
				w.data.fruits.sprout_daisy = { count = 4, value = 100 }
				T.eq(FruitService.sellAll(w.player), 100)
				local p1 = plant("owl_oak")
				local price1 = GR.sellPrice(p1)
				T.eq(w.PetService.sellPlant(w.player, p1.uid), price1)
				T.eq(w.data.money, 100 + price1)
				-- 영수증으로 사기 (진짜 processReceipt)
				w.data.money = 0
				T.eq(process(w, receipt(w, "money_pass", "mp-1")), GRANTED)
				T.eq(w.data.moneyPass, true)
				T.eq(process(w, receipt(w, "money_pass", "mp-2")), GRANTED, "두 번째 구매 (돈은 받았음)")
				T.truthy(w.H.hasNotify(w.player, "info", "이미 코인 2배"))
				T.eq(w.PetService.coinMultiplier(w.player), 2, "× 4 가 아님")
				w.data.fruits.sprout_daisy = { count = 4, value = 100 }
				w.data.fruits.owl_oak = { count = 2, value = 50 }
				T.eq(FruitService.sellAll(w.player), 300, "열매 (100 + 50) × 2")
				local p2 = plant("owl_oak")
				T.eq(w.PetService.sellPlant(w.player, p2.uid), price1 * 2, "성체 팔기 × 2")
				T.eq(w.data.money, 300 + price1 * 2)
				-- 또 팔 것이 없으면 아무것도 안 생김
				T.eq(FruitService.sellAll(w.player), nil)
				T.eq(w.data.money, 300 + price1 * 2)
				T.eq(stored(w).moneyPass, true, "저장됨")
			end)
		end
	)

	T.test(
		"코인·속도 지급이 상한(MONEY_MAX 1e30 · SPEED_MAX 1e24)에 걸려도 영수증은 정상 처리 (PurchaseGranted · 기록 1개 · 상한에서 자름 · NaN 없음) — 상한에 이미 닿았으면 더할 것이 없어도 한 번 처리",
		function()
			inWorld(nil, function(w)
				fakeConfigure(w)
				enableSaving(w)
				local Cfg = w.H.shared("Data/Config")
				w.data.money = Cfg.MONEY_MAX - 5
				T.eq(process(w, receipt(w, "coins_1b", "cap-1")), GRANTED)
				T.eq(w.data.money, Cfg.MONEY_MAX)
				T.eq(
					process(w, receipt(w, "coins_1m", "cap-2")),
					GRANTED,
					"이미 상한이어도 처리됨 (1e30 은 실제로 안 닿음)"
				)
				T.eq(w.data.money, Cfg.MONEY_MAX)
				w.data.speed = Cfg.SPEED_MAX - 1
				T.eq(process(w, receipt(w, "speed_100m", "cap-3")), GRANTED)
				T.eq(w.data.speed, Cfg.SPEED_MAX)
				T.eq(process(w, receipt(w, "speed_10m", "cap-4")), GRANTED)
				T.eq(w.data.speed, Cfg.SPEED_MAX)
				T.eq(#w.data.receipts, 4)
				T.truthy(finite(w.data.money) and finite(w.data.speed))
				-- 최대 레벨 + 속도 상한: 레벨 상품도 처리
				w.data.treadmillLevel = 20
				T.eq(process(w, receipt(w, "tskip_20", "cap-5")), GRANTED)
				T.eq(w.data.speed, Cfg.SPEED_MAX)
				T.eq(stored(w).speed, Cfg.SPEED_MAX, "저장도 상한")
			end)
		end
	)

	T.test(
		"스키마 7 → 8 · 8 보정: 옛 칸(hasMoneyPass 등)은 인정 안 함 · 부스트는 파는 배수 중 저장값 이하 최댓값 · 코인 2배는 true 만 · 영수증은 1~64자 · 두 번 reconcile 해도 같음 · 더 새 버전은 감지",
		function()
			local DataSchema = Loader.require(V .. "Logic/DataSchema")
			local P = Loader.require(S .. "Data/Products")
			-- 7판 저장 데이터 (옛 게임패스 칸이 섞여 있어도)
			local old = DataSchema.reconcile(
				DataSchema.migrate({
					version = 7,
					money = 50,
					hasMoneyPass = true,
					moneyPassOwned = true,
					gamepasses = { money = true },
				}),
				0
			)
			T.eq(old.version, 8)
			T.eq(old.moneyPass, false, "옛 게임패스 칸은 인정 안 함")
			T.eq(old.treadmillBoost, 1)
			T.eq(#old.receipts, 0)
			T.eq(old.hasMoneyPass, nil, "알 수 없는 칸은 버림")
			for _, multiplier in P.BOOST_MULTIPLIERS do
				T.eq(DataSchema.cleanTreadmillBoost(multiplier), multiplier)
				T.eq(DataSchema.cleanTreadmillBoost(multiplier + 0.5), multiplier, "소수는 내림")
				if multiplier > 2 then
					T.eq(DataSchema.cleanTreadmillBoost(multiplier - 1), multiplier / 2, "파는 배수 아래")
				end
			end
			T.eq(DataSchema.cleanTreadmillBoost(2 ^ 53), 2048)
			T.eq(DataSchema.cleanTreadmillBoost(math.huge), 2048)
			T.eq(DataSchema.cleanTreadmillBoost(-math.huge), 1)
			T.eq(DataSchema.cleanTreadmillBoost(1.9999), 1)
			for _, bad in { 1, "true", "yes", {}, 0, -1, 0 / 0, 2 } do
				T.eq(DataSchema.reconcile({ version = 8, moneyPass = bad }, 0).moneyPass, false, tostring(bad))
			end
			-- 영수증 정리: 1000개 + 이상한 것
			local raw = {
				version = 8,
				treadmillBoost = 2048,
				moneyPass = true,
				receipts = { "a", "a", 7, "", false, {}, string.rep("y", 65) },
			}
			for i = 1, 1000 do
				table.insert(raw.receipts, "id-" .. i)
			end
			local r1 = DataSchema.reconcile(raw, 0)
			T.eq(#r1.receipts, 500)
			T.eq(r1.receipts[500], "id-1000")
			T.eq(r1.receipts[1], "id-501")
			for _, id in r1.receipts do
				T.truthy(type(id) == "string" and #id >= 1 and #id <= 64)
			end
			local r2 = DataSchema.reconcile(r1, 0)
			T.eq(r2.treadmillBoost, 2048)
			T.eq(r2.moneyPass, true)
			T.eq(table.concat(r2.receipts, ","), table.concat(r1.receipts, ","), "두 번 reconcile 해도 같음")
			T.eq(DataSchema.reconcile("엉터리", 0).version, 8)
			T.truthy(DataSchema.isNewerVersion({ version = 9 }))
			T.falsy(DataSchema.isNewerVersion({ version = 8 }))
			T.falsy(DataSchema.isNewerVersion({ version = 7 }))
		end
	)

	T.test(
		"Snapshot · Attr 가 상품 지급 뒤 데이터와 같음 (모든 종류) · 다시 접속(onPlayerReady) 해도 같음",
		function()
			inWorld(nil, function(w)
				local PS = w.ProductService
				local Snapshot = w.H.server("Snapshot")
				-- 부스트는 순서대로 2 · 4 · … · 64 (건너뛰면 64 가 안 됨)
				for _, key in
					{
						"boost_2",
						"boost_4",
						"boost_8",
						"boost_16",
						"boost_32",
						"boost_64",
						"tskip_1",
						"tskip_2",
						"money_pass",
						"coins_1m",
						"speed_10m",
					}
				do
					T.truthy(PS.grant(w.player, key))
				end
				local function check()
					local snap = Snapshot.build(w.player)
					T.eq(snap.treadmillBoost, 64)
					T.eq(snap.moneyPass, true)
					T.eq(snap.treadmillLevel, 2)
					T.eq(w.player.attrs.TreadmillBoost, 64)
					T.eq(w.player.attrs.MoneyPass, true)
					T.eq(w.player.attrs.TreadmillLevel, 2)
				end
				check()
				w.player.attrs.TreadmillBoost = nil
				w.player.attrs.MoneyPass = nil
				PS.onPlayerReady(w.player)
				check()
				local last
				for _, args in w.H.sent(w.player, "DataUpdate") do
					if args[1] == "upgrades" then
						last = args[2]
					end
				end
				T.eq(last.treadmillBoost, 64)
				T.eq(last.moneyPass, true)
				T.eq(last.treadmillLevel, 2)
			end)
		end
	)

	------------------------------------------------------------------
	T.suite(
		"9판 주임 검수 C: 열매 먹이기 잔재 (코드 · 원소 돌연변이 legacy · 열매 가방/판매)"
	)

	T.test(
		"소스(src) 코드 줄(주석 뺀)에 먹이기 흔적이 없음: feed 계열 이름 · FEED_ 상수 · FeedFruit/FeedResult · '먹이' 글자 · 먹이기 소리 이름",
		function()
			local hits = {}
			local function walk(dir)
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						walk(path)
					elseif string.match(name, "%.luau?$") then
						local code = stripComments(fs.readFile(path))
						local lower = string.lower(code)
						for _, needle in
							{ "feed", "먹이", "nyam", "냠냠", "takeone", "rollfeed", "cangain", "raritybonus" }
						do
							if string.find(lower, needle, 1, true) then
								table.insert(hits, path .. " : " .. needle)
							end
						end
					end
				end
			end
			walk("src")
			T.eq(table.concat(hits, "\n"), "", "먹이기 흔적이 남은 코드")
			-- 데이터 표에도 없음
			local Sounds = Loader.require(S .. "Data/Sounds")
			for key in Sounds do
				T.falsy(string.find(string.lower(tostring(key)), "feed", 1, true), "소리 " .. tostring(key))
			end
			for _, m in Mutations.list do
				T.eq(m.feedChance, nil)
				T.eq(m.feedBiomes, nil)
			end
			for _, name in
				{ "feed", "feedChance", "FEED_MAX_CHANCE", "FEED_BIOME_BONUS", "FEED_RARITY_BONUS_PER_ORDER" }
			do
				T.eq(Mutations[name], nil, "Mutations." .. name)
			end
			for _, name in
				{ "feedOptions", "feedChance", "rollFeed", "canGain", "rarityBonus", "applyMutation", "takeOne" }
			do
				T.eq(FruitRules[name], nil, "FruitRules." .. name)
			end
			T.eq(Remotes.ToServer.FeedFruit, nil)
			T.eq(Remotes.ToClient.FeedResult, nil)
			T.eq(Remotes.RateLimits.FeedFruit, nil)
		end
	)

	T.test(
		"원소 돌연변이(얼음·불·번개)는 새로 안 붙음: 자연 굴림 20,000번에 실버·황금·무지개만 · 옛 저장 식물에 붙은 것은 값에 그대로 곱함 (황금 × 얼음 = × 3) · 저장 불러오기에도 남음",
		function()
			local rand = T.rng(31337)
			local counts = { silver = 0, golden = 0, rainbow = 0 }
			for _ = 1, 20000 do
				local traits = EggRoll.rollTraits(rand)
				T.truthy(#traits.mutations <= 1)
				for _, id in traits.mutations do
					T.truthy(counts[id] ~= nil, "새 씨앗에 자연 돌연변이가 아닌 것 " .. tostring(id))
					counts[id] += 1
				end
			end
			T.truthy(counts.silver > 0 and counts.golden > 0 and counts.rainbow > 0, "세 가지 다 나옴")
			T.near(counts.silver / 20000, 0.05, 0.01)
			T.near(counts.golden / 20000, 0.02, 0.008)
			for _, id in { "frozen", "burning", "shocked" } do
				local m = Mutations.get(id)
				T.eq(m.source, "legacy")
				T.eq(m.naturalChance, 0)
				for _, nat in Mutations.natural do
					T.truthy(nat.id ~= id)
				end
			end
			-- 값 계산: 옛 저장 식물의 원소는 그대로 곱함
			local base = Economy.fruitValue("owl_oak", "normal", {})
			T.eq(Economy.fruitValue("owl_oak", "normal", { "golden", "frozen" }), base * 2 * 1.5)
			T.eq(Economy.fruitValue("owl_oak", "normal", { "frozen" }), base * 1.5)
			T.eq(Economy.fruitValue("owl_oak", "normal", { "shocked" }), base * 2)
			T.eq(Economy.fruitValue("owl_oak", "normal", { "burning", "rainbow" }), base * 1.5 * 2.5)
			-- 저장 불러오기에도 남음 (알려진 돌연변이만 남김)
			local DataSchema = Loader.require(V .. "Logic/DataSchema")
			local loaded = DataSchema.reconcile({
				version = 8,
				pets = {
					{
						uid = "p1",
						petId = "owl_oak",
						size = "normal",
						mutations = { "golden", "frozen", "fed_by_hand" },
						x = 0,
						z = 0,
						fruits = 1,
						fruitProgress = 0,
					},
				},
			}, 0)
			T.eq(#loaded.pets, 1, "옛 식물이 불러올 때 사라지지 않음")
			local ms = table.concat(loaded.pets[1].mutations, ",")
			T.truthy(
				string.find(ms, "frozen", 1, true) and string.find(ms, "golden", 1, true),
				"옛 원소 그대로: " .. ms
			)
			T.falsy(string.find(ms, "fed_by_hand", 1, true), "모르는 돌연변이는 버림")
		end
	)

	T.test(
		"열매 가방·판매 불변식 (진짜 FruitService · PetService): 따기 = 식물 열매 감소 = 가방 증가(보존) · 가방 300 상한(가득 차면 식물에 그대로) · 판매 = 가방 값 × 배수 정확히, 팔고 나면 가방 0 · 또 팔아도 코인 안 늘고 · 멀리서는 못 팔고 · 코인 2배도 정확히 한 번",
		function()
			inWorld(nil, function(w)
				local FruitService = w.H.server("Services/FruitService")
				local DataSchema = w.H.server("Logic/DataSchema")
				local EP = w.H.shared("EggPlacement")
				local Cfg = w.H.shared("Data/Config")
				local Wallet = w.H.server("Services/Wallet")
				Wallet.setupLeaderstats(w.player)
				local pen = w.H.MapLayout.penRect(1)
				local stall = w.H.MapLayout.hubSpots.sellStall
				local function plant(petId, fruits)
					local taken = {}
					for _, r in w.data.pets do
						table.insert(taken, { x = r.x, z = r.z, size = r.size })
					end
					local spot = EP.firstFreeGrid("normal", taken)
					local record = {
						uid = DataSchema.newUid(w.data, "p"),
						petId = petId,
						size = "normal",
						mutations = {},
						x = spot.x,
						z = spot.z,
						fruits = fruits,
						fruitProgress = 0,
					}
					assert(w.PetService.addPlant(w.player, record))
					return record
				end
				local a = plant("sprout_daisy", 5)
				local b = plant("owl_oak", 5)
				w.H.spawn(w.player, (pen.xMin + pen.xMax) / 2, 3, (pen.zMin + pen.zMax) / 2)
				local function bagCount()
					return FruitRules.bagCount(w.data.fruits)
				end
				-- 따기: 보존
				T.eq(FruitService.pick(w.player, a.uid), 5)
				T.eq(a.fruits, 0)
				T.eq(bagCount(), 5)
				T.eq(FruitService.pick(w.player, a.uid), 0, "또 따도 없음")
				-- 가방 상한: 296 로 채우고 b 의 5개를 따면 4개만
				w.data.fruits.puppy_grass = { count = Cfg.FRUIT_BAG_MAX - 5 - 4, value = 10 }
				T.eq(FruitService.pick(w.player, b.uid), 4, "자리가 4칸만 남음")
				T.eq(bagCount(), Cfg.FRUIT_BAG_MAX)
				T.eq(b.fruits, 1, "못 딴 열매는 식물에 그대로")
				T.eq(FruitService.pick(w.player, b.uid), 0, "가방이 가득이면 0")
				T.eq(b.fruits, 1)
				-- 멀리서는 못 팖
				local x, z = w.H.zoneSpot("forest")
				w.H.spawn(w.player, x, 3, z)
				local moneyBefore = w.data.money
				T.eq(FruitService.sellAll(w.player), nil)
				T.eq(w.data.money, moneyBefore)
				T.eq(bagCount(), Cfg.FRUIT_BAG_MAX)
				-- 가판대에서 팖: 값 × 1
				w.H.spawn(w.player, stall.x, 3, stall.z)
				local value = FruitRules.bagValue(w.data.fruits)
				T.eq(FruitService.sellAll(w.player), value)
				T.eq(w.data.money, moneyBefore + value)
				T.eq(bagCount(), 0)
				T.eq(next(w.data.fruits), nil, "가방 완전히 빔")
				T.eq(FruitService.sellAll(w.player), nil, "또 팔아도 아무것도 없음")
				T.eq(w.data.money, moneyBefore + value)
				T.eq(#w.H.sent(w.player, "FruitsSold"), 1)
				-- 코인 2배
				w.ProductService.grant(w.player, "money_pass")
				w.data.fruits.owl_oak = { count = 3, value = 120 }
				local money = w.data.money
				T.eq(FruitService.sellAll(w.player), 240)
				T.eq(w.data.money, money + 240)
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("9판 주임 검수 D: 밤 귀가 버그 (진짜 EggService · BaseService · TutorialService)")

	local function nightWorld(opts)
		opts = opts or {}
		local H = ServerHarness.install(Loader, T, { realEgg = true })
		H.startNet()
		local w = { H = H }
		w.Sessions = H.server("Sessions")
		w.EggService = H.server("Services/EggService")
		w.BaseService = H.server("Services/BaseService")
		w.TutorialService = H.server("Services/TutorialService")
		w.EggService.start()
		w.BaseService.start()
		w.TutorialService.start()
		w.players = {}
		for i = 1, opts.players or 1 do
			local p = H.newPlayer(9600 + i, "Night" .. i)
			local session, data = H.login(p, opts.login)
			session.plotIndex = i
			local x, z = H.plotSpot(i)
			H.spawn(p, x, 3, z)
			w.players[i] = { player = p, session = session, data = data }
		end
		w.player, w.session, w.data = w.players[1].player, w.players[1].session, w.players[1].data
		H.setPhase("Intermission", 1)
		H.setPhase("Day", 1)
		return w
	end

	local function inNight(opts, fn)
		local w = nightWorld(opts)
		local ok, err = pcall(fn, w)
		w.H.uninstall()
		if not ok then
			error(err, 0)
		end
	end

	local function steal(w, biomeId, who)
		who = who or w.player
		for _, egg in w.H.map.folders.Eggs.children do
			if egg:GetAttribute("BiomeId") == biomeId and egg:GetAttribute("EggState") == "Nest" then
				w.H.teleport(who, egg.Position.X, egg.Position.Y, egg.Position.Z)
				egg:FindFirstChild("StealPrompt").Triggered:Fire(who)
				if w.EggService.getCarried(who) then
					return egg
				end
			end
		end
		error("주울 씨앗이 없음 " .. biomeId)
	end

	local function nightNotices(w, who)
		local n = 0
		for _, note in w.H.notifications(who or w.player) do
			if string.find(note.text, "둥지로 돌아갔어요", 1, true) then
				n += 1
			end
		end
		return n
	end

	T.test(
		"튜토리얼 2단계(씨앗 든 상태)에서 밤이 되면: 가방 0 · 둥지 복귀 · 안내 정확히 1번 · 튜토리얼 1단계로 (다시 훔치기) · 밤이 또 와도(낮밤 반복) 안내가 새로 안 쌓임",
		function()
			inNight({ login = { tutorialStep = 1 } }, function(w)
				local egg = steal(w, "forest")
				T.eq(w.data.tutorialStep, 2, "씨앗을 주워서 2단계")
				w.H.advance(1)
				w.H.setPhase("Night")
				T.eq(w.data.tutorialStep, 1, "씨앗을 놓쳤으니 1단계")
				T.eq(#w.data.eggs, 0)
				T.eq(egg:GetAttribute("EggState"), "Nest")
				T.eq(nightNotices(w), 1, "안내 1번")
				w.H.advance(2)
				w.H.setPhase("Day")
				w.H.setPhase("Night")
				w.H.advance(1)
				T.eq(nightNotices(w), 1, "씨앗이 없는데 밤이 또 와도 안내 안 늘어남")
				T.eq(#w.H.sent(w.player, "EggDelivered"), 0)
				T.eq(#w.H.warnings, 0)
			end)
		end
	)

	T.test(
		"밤이 되는 순간: 이미 허브 안에 걸어 들어온 사람은 정상 배달 (밤이 와도 순간이동 안 함, 다음 틱에 EggDelivered) · 허브 밖(바로 앞)이면 둥지로 돌아가고 가방에 안 들어옴",
		function()
			inNight(nil, function(w)
				-- (a) 허브에 막 걸어 들어온 순간(배달 틱 전)에 밤
				steal(w, "forest")
				w.H.advance(20) -- 충분히 걸린 시간 (너무 빠른 배달 아님)
				w.Sessions.exemptMovement(w.session, 5)
				local hx, hz = w.H.hubSpot()
				w.H.teleport(w.player, hx, 3, hz) -- 허브 안
				w.H.setPhase("Night") -- 같은 순간: 배달 틱이 아직 안 돔
				T.truthy(w.H.MapLayout.isInHub(w.player.Character.root.Position), "허브 안")
				T.eq(w.player.Character.root.Position.Z, hz, "순간이동 안 함")
				T.eq(nightNotices(w), 0, "둥지로 안 돌려보냄")
				w.H.advance(0.6)
				T.eq(#w.data.eggs, 1, "스스로 걸어서 들어왔으니 정상 배달")
				T.eq(#w.H.sent(w.player, "EggDelivered"), 1)
				T.eq(w.EggService.getCarried(w.player), nil)
				w.H.setPhase("Day")
				w.H.setPhase("Intermission", 2)
				w.H.setPhase("Day", 2)
				-- (b) 허브 바로 밖 (z = +0.5)
				local egg = steal(w, "lake")
				w.H.advance(20)
				w.Sessions.exemptMovement(w.session, 5)
				w.H.teleport(w.player, hx, 3, 0.5)
				T.falsy(w.H.MapLayout.isInHub(w.player.Character.root.Position))
				w.H.setPhase("Night")
				T.truthy(w.H.MapLayout.isInHub(w.player.Character.root.Position), "밤이라 베이스로")
				w.H.advance(1)
				T.eq(#w.data.eggs, 1, "두 번째 씨앗은 가방에 안 들어옴 (그대로 1개)")
				T.eq(egg:GetAttribute("EggState"), "Nest")
				T.eq(nightNotices(w), 1)
				T.eq(#w.H.warnings, 0)
			end)
		end
	)

	T.test(
		"세 명이 동시에 밤 (둘은 구역에서 씨앗을 든 채, 한 명은 허브 안에서 든 채 — 가방 가득): 각자 자기 씨앗만 자기 둥지로, 안내는 각자 1번, 가방 0, 허브 안 사람은 그대로 들고 있음",
		function()
			inNight({ players = 3 }, function(w)
				local a, b, c = w.players[1], w.players[2], w.players[3]
				for _ = 1, 50 do
					w.BaseService.grantEgg(c.player, "sprout_daisy", "normal", {}, "dev")
				end
				local eggA = steal(w, "forest", a.player)
				local eggB = steal(w, "lake", b.player)
				local eggC = steal(w, "forest", c.player)
				T.truthy(eggA ~= eggC)
				w.H.advance(20)
				w.Sessions.exemptMovement(c.session, 5)
				local hx, hz = w.H.hubSpot()
				w.H.teleport(c.player, hx, 3, hz) -- C 는 허브 안으로 (가방이 가득이라 손에 그대로)
				w.H.advance(0.6)
				T.truthy(w.EggService.getCarried(c.player) ~= nil, "C: 가방 가득 → 손에 그대로")
				w.H.setPhase("Night")
				w.H.advance(1)
				T.eq(w.EggService.getCarried(a.player), nil)
				T.eq(w.EggService.getCarried(b.player), nil)
				T.eq(eggA:GetAttribute("EggState"), "Nest")
				T.eq(eggB:GetAttribute("EggState"), "Nest")
				T.eq(eggC:GetAttribute("EggState"), "Carried", "허브 안에 있던 C 는 건드리지 않음")
				T.eq(#a.data.eggs, 0)
				T.eq(#b.data.eggs, 0)
				T.eq(#c.data.eggs, 50)
				T.eq(nightNotices(w, a.player), 1)
				T.eq(nightNotices(w, b.player), 1)
				T.eq(nightNotices(w, c.player), 0)
				T.eq(eggA:GetAttribute("BiomeId"), "forest")
				T.eq(eggB:GetAttribute("BiomeId"), "lake")
				T.truthy(w.H.MapLayout.isInHub(a.player.Character.root.Position))
				T.truthy(w.H.MapLayout.isInHub(b.player.Character.root.Position))
				T.eq(#w.H.warnings, 0)
			end)
		end
	)

	T.test(
		"쓰러진·죽은 상태에서 밤: 씨앗을 이미 놓친 사람(기절 중) → 안내 없음·가방 0 · 캐릭터가 없는 사람(리스폰 중)은 건너뜀 · 체력 0 인데 아직 든 채 밤 → 둥지로, 그 뒤 Died 처리도 두 번 돌려보내지 않음 · 서버 오류 없음",
		function()
			inNight({ players = 3 }, function(w)
				local a, b, c = w.players[1], w.players[2], w.players[3]
				-- A: 씨앗을 놓치고(맞아서) 기절 중 → 밤
				local eggA = steal(w, "forest", a.player)
				w.H.advance(1)
				w.EggService.dropCarried(a.player, "guard")
				a.session.stunnedUntil = w.H.clock() + 10
				T.eq(w.EggService.getCarried(a.player), nil)
				local stateA = eggA:GetAttribute("EggState")
				T.truthy(stateA == "Nest" or stateA == "Dropped")
				-- B: 캐릭터 없음 (리스폰 중)
				b.player.Character = nil
				-- C: 체력 0 (죽는 순간) 인데 아직 씨앗을 든 채
				local eggC = steal(w, "lake", c.player)
				w.H.advance(1)
				c.player.Character.humanoid.Health = 0
				w.H.setPhase("Night")
				w.H.advance(1)
				T.eq(nightNotices(w, a.player), 0, "A: 안내 없음 (씨앗 없음)")
				T.eq(#a.data.eggs, 0)
				T.eq(#b.data.eggs, 0)
				T.eq(nightNotices(w, c.player), 1, "C: 든 채였으니 둥지로 + 안내")
				T.eq(eggC:GetAttribute("EggState"), "Nest")
				T.eq(#c.data.eggs, 0)
				-- Died 가 뒤늦게 와도 (EggService.dropCarried "death") 아무 일 없음
				T.eq(w.EggService.dropCarried(c.player, "death"), nil)
				T.eq(eggC:GetAttribute("EggState"), "Nest", "두 번 돌려보내지 않음")
				T.eq(#w.H.warnings, 0)
			end)
		end
	)

	T.test(
		"밤 순간이동 목적지는 베이스 앞마당 전부 허브 안 (안 그러면 밤 벽 밖에 갇힘) · 베이스 없는 사람은 밤에 허브 기본 스폰으로, 씨앗은 둥지로 (안내 1번)",
		function()
			inNight({ players = 2 }, function(w)
				for i = 1, w.H.MapLayout.PLOT_COUNT do
					local spawn = w.H.MapLayout.plot(i).spawn
					T.truthy(
						w.H.MapLayout.isInHub(w.H.vec(spawn.x, 3, spawn.z)),
						"베이스 " .. i .. " 앞마당이 허브 안"
					)
				end
				local late = w.players[2]
				late.session.plotIndex = 0 -- 8번째 사람 (베이스 없음)
				local zx, zz = w.H.zoneSpot("lake")
				w.H.teleport(late.player, zx, 3, zz)
				w.H.setPhase("Night")
				w.H.advance(0.5)
				T.truthy(w.H.MapLayout.isInHub(late.player.Character.root.Position), "베이스 없어도 허브 안")
				T.eq(nightNotices(w, late.player), 0, "씨앗 없으면 안내 없음")
				-- 씨앗을 든 8번째 사람
				w.H.setPhase("Day")
				w.H.setPhase("Intermission", 2)
				w.H.setPhase("Day", 2)
				local egg = steal(w, "lake", late.player)
				w.H.advance(1)
				w.H.setPhase("Night")
				w.H.advance(1)
				T.eq(#late.data.eggs, 0)
				T.eq(egg:GetAttribute("EggState"), "Nest")
				T.eq(nightNotices(w, late.player), 1)
			end)
		end
	)

	------------------------------------------------------------------
	T.suite(
		"9판 주임 검수 F: 무작위 요청 + 무작위 영수증 시험 (두 사람, 진짜 서비스들 + 진짜 DataService)"
	)

	T.test(
		"A 가 온갖 Remote 를 1000번 던지고 낮밤·순간이동 사이에 진짜/가짜/중복 영수증(저장소 고장 포함)을 섞어도: 코인·속도·부스트·코인 2배·레벨·영수증·가방·정원 불변식 유지, 영수증마다 효과는 정확히 한 번(ProductGranted 도), 가짜는 아무 효과 없음, B 는 A 때문에 안 바뀜, 서버 warn 없음",
		function()
			local H = ServerHarness.install(Loader, T, { realEgg = true })
			local ok, err = pcall(function()
				H.startNet()
				local w = { H = H }
				w.Products = H.shared("Data/Products")
				w.DataSchema = H.server("Logic/DataSchema")
				w.Sessions = H.server("Sessions")
				w.DataService = H.server("Services/DataService")
				w.ProductService = H.server("Services/ProductService")
				w.BaseService = H.server("Services/BaseService")
				w.PetService = H.server("Services/PetService")
				w.FruitService = H.server("Services/FruitService")
				w.SakuraService = H.server("Services/SakuraService")
				w.IndexService = H.server("Services/IndexService")
				w.UpgradeService = H.server("Services/UpgradeService")
				w.EggService = H.server("Services/EggService")
				w.GuardianService = H.server("Services/GuardianService")
				w.TreadmillService = H.server("Services/TreadmillService")
				w.SpeedService = H.server("Services/SpeedService")
				local Cfg = H.shared("Data/Config")
				local Up = H.shared("Data/Upgrades")
				local EP = H.shared("EggPlacement")
				local GR = H.shared("GardenRules")
				fakeConfigure(w)
				w.DataService.start()
				local A = H.newPlayer(9701, "FuzzA")
				local sessionA, dataA = H.login(A)
				sessionA.plotIndex = 1
				sessionA.saveEnabled = true
				local B = H.newPlayer(9702, "VictimB")
				local sessionB, dataB = H.login(B)
				sessionB.plotIndex = 2
				sessionB.saveEnabled = true
				w.player = A
				do
					local ax, az = H.plotSpot(1)
					H.spawn(A, ax, 3, az)
					local bx, bz = H.plotSpot(2)
					H.spawn(B, bx, 3, bz)
				end
				sessionA.moveExemptUntil = H.clock() + 1e7
				sessionB.moveExemptUntil = H.clock() + 1e7
				w.BaseService.start()
				w.PetService.start()
				w.FruitService.start()
				w.SakuraService.start()
				w.IndexService.start()
				w.UpgradeService.start()
				w.EggService.start()
				w.GuardianService.start()
				w.TreadmillService.start()
				H.setPhase("Intermission", 1)
				H.setPhase("Day", 1)
				local cycle = 1

				local function taken(data)
					local list = {}
					for _, r in data.pets do
						table.insert(list, { x = r.x, z = r.z, size = r.size, petId = r.petId })
					end
					for _, r in data.incubators do
						table.insert(list, { x = r.x, z = r.z, size = r.size, petId = r.petId })
					end
					return list
				end
				local function addPlant(player, data, petId, fruits)
					local spot = EP.firstFreeGrid("normal", taken(data), petId)
					local record = {
						uid = w.DataSchema.newUid(data, "p"),
						petId = petId,
						size = "normal",
						mutations = {},
						x = spot.x,
						z = spot.z,
						fruits = fruits or 0,
						fruitProgress = 0,
					}
					assert(w.PetService.addPlant(player, record), "addPlant 실패")
				end
				for _, id in { "sprout_daisy", "owl_oak", "puppy_grass", "static_world_tree" } do
					addPlant(A, dataA, id, 3)
				end
				for _ = 1, 3 do
					w.BaseService.grantEgg(A, "owl_oak", "normal", {}, "sakura")
				end
				dataA.fruits.owl_oak = { count = 200, value = 200 * 180 }
				dataA.money = 5000
				dataA.penLevel = Up.PEN_MAX_LEVEL - 2
				for _, id in { "sprout_daisy", "owl_oak", "static_world_tree" } do
					addPlant(B, dataB, id, 5)
				end
				dataB.fruits.owl_oak = { count = 10, value = 1800 }
				dataB.money = 12345
				dataB.sakuraCrystals = 7
				dataB.treadmillLevel = 2
				dataB.treadmillBoost = 4
				dataB.moneyPass = true
				dataB.speed = 777
				dataB.receipts = { "b-old-1", "b-old-2" }
				dataB.nextUid = 700
				w.SpeedService.refresh(B)
				local bStart = {}
				for _, r in dataB.pets do
					bStart[r.uid] = true
				end
				local function lockedB()
					local fr = {}
					for id, st in dataB.fruits do
						table.insert(fr, id .. ":" .. st.count .. ":" .. st.value)
					end
					table.sort(fr)
					local muts = {}
					for _, r in dataB.pets do
						if bStart[r.uid] then
							table.insert(muts, r.uid .. "=" .. table.concat(r.mutations, "+") .. "/" .. r.size)
						end
					end
					table.sort(muts)
					return table.concat({
						tostring(dataB.money),
						tostring(dataB.sakuraCrystals),
						#dataB.eggs,
						dataB.penLevel,
						dataB.treadmillLevel,
						tostring(dataB.speed),
						dataB.treadmillBoost,
						tostring(dataB.moneyPass),
						table.concat(dataB.receipts, ","),
						tostring(dataB.stats.productsBought),
						table.concat(fr, ","),
						table.concat(muts, ","),
					}, "|")
				end
				local lockedBefore = lockedB()

				local rand = T.rng(90909)
				local function pick(list)
					return list[math.floor(rand() * #list) + 1]
				end
				local junk = {
					true,
					false,
					0,
					1,
					-1,
					0 / 0,
					math.huge,
					-math.huge,
					1e308,
					"",
					"all",
					"half",
					"Pen",
					"Treadmill",
					"Trail",
					"none",
					"money_pass",
					"boost_2048",
					"tskip_20",
					string.rep("x", 100),
					"한글",
					{},
					{ 1 },
					{ key = "money_pass", kind = "moneyPass" },
				}
				local function uidPool()
					local pool = {}
					for _, d in { dataA, dataB } do
						for _, list in { d.pets, d.incubators, d.eggs } do
							for _, r in list do
								table.insert(pool, r.uid)
							end
						end
					end
					for _, part in H.map.folders.Eggs.children do
						table.insert(pool, tostring(part:GetAttribute("EggUid")))
					end
					return pool
				end
				local function arg()
					local roll = rand()
					if roll < 0.45 then
						local pool = uidPool()
						if #pool > 0 then
							return pick(pool)
						end
					elseif roll < 0.5 then
						return nil
					end
					return pick(junk)
				end
				local serverNames = {}
				for name in Remotes.ToServer do
					table.insert(serverNames, name)
				end
				table.sort(serverNames)
				local clientNames = {}
				for name in Remotes.ToClient do
					table.insert(clientNames, name)
					T.eq(#H.remotes[name].OnServerEvent.handlers, 0, name .. " 은 서버 → 클라 전용")
				end
				local penA = H.MapLayout.penRect(1)
				local stall = H.MapLayout.hubSpots.sellStall
				local plot = H.MapLayout.plot(1)

				-- A 의 기대값 (영수증으로만 바뀌는 칸)
				local expect = { boost = 1, pass = false, bought = 0 }
				local genuine = {} -- { id, key, result }
				local nextId = 0
				local did =
					{ remote = 0, genuine = 0, dup = 0, fake = 0, notYet = 0, forB = 0, failures = 0, night = 0 }

				local function snapA()
					return {
						money = dataA.money,
						speed = dataA.speed,
						boost = dataA.treadmillBoost,
						pass = dataA.moneyPass,
						level = dataA.treadmillLevel,
						receipts = table.concat(dataA.receipts, ","),
						bought = dataA.stats.productsBought or 0,
					}
				end
				local function sameA(before, after, label, allowSpeed)
					T.eq(after.money, before.money, label .. ": 코인")
					if not allowSpeed then
						T.eq(after.speed, before.speed, label .. ": 속도")
					end
					T.eq(after.boost, before.boost, label .. ": 부스트")
					T.eq(after.pass, before.pass, label .. ": 코인 2배")
					T.eq(after.level, before.level, label .. ": 레벨")
					T.eq(after.receipts, before.receipts, label .. ": 영수증 기록")
					T.eq(after.bought, before.bought, label .. ": 구매 횟수")
				end

				local function genuineReceipt(label)
					nextId += 1
					local product = pick(w.Products.list)
					local pid = "fz-" .. nextId
					if rand() < 0.12 then
						H.store.failNext = pick({ 1, 2, 5, 1000 })
						did.failures += 1
					end
					local before = snapA()
					local onTreadmill = A.attrs.OnTreadmill == true
					local result = process(w, receipt(w, product.key, pid, A), 400)
					local after = snapA()
					T.truthy(result == GRANTED or result == NOT_YET, label .. ": 결과 " .. tostring(result))
					if result == NOT_YET then
						did.notYet += 1
					else
						-- PurchaseGranted 라고 했으면 저장소에 영수증이 이미 있어야 함 (아니면 서버가 꺼질 때 돈만 받고 상품이 사라짐)
						local s = stored(w, A)
						T.truthy(
							s ~= nil and table.find(s.receipts, pid) ~= nil,
							label .. ": 저장 안 된 영수증을 확인함 " .. pid
						)
					end
					T.eq(after.bought, before.bought + 1, label .. ": 영수증 1장 = 효과 1번")
					expect.bought += 1
					T.eq(after.receipts == before.receipts, false, label .. ": 영수증 기록됨")
					local value = product.value
					if product.kind == "treadmillBoost" then
						-- 2026-11-10 순서대로만 열림: 기준 모델 (boostExpect) 과 똑같아야 하고, 남은 R$ 는 속도
						local leftover
						expect.boost, leftover = boostExpect(expect.boost, value)
						T.eq(after.boost, expect.boost, label .. ": 부스트 (순서대로만 열림)")
						if leftover > 0 then
							local wantSpeed =
								math.min(Cfg.SPEED_MAX, before.speed + leftover * Cfg.PRODUCT_SPEED_PER_ROBUX)
							T.truthy(after.speed >= wantSpeed, label .. ": 남은 R$ 만큼 속도")
						elseif not (onTreadmill or A.attrs.OnTreadmill) then
							T.eq(
								after.speed,
								before.speed,
								label .. ": 순서대로 산 부스트는 속도 안 늘어남"
							)
						end
					elseif product.kind == "moneyPass" then
						expect.pass = true
						T.eq(after.pass, true)
					elseif product.kind == "coins" then
						T.eq(after.money, math.min(Cfg.MONEY_MAX, before.money + value), label .. ": 코인 +" .. value)
					elseif product.kind == "speed" then
						local want = math.min(Cfg.SPEED_MAX, before.speed + value)
						if onTreadmill or A.attrs.OnTreadmill then
							T.truthy(after.speed >= want, label .. ": 속도 +" .. value)
						else
							T.eq(after.speed, want, label .. ": 속도 +" .. value)
						end
					elseif product.kind == "treadmillSkip" then
						local level = before.level
						-- 주임 F-3 수정: 안 맞으면 산 R$ 만큼만 (skipExpect), 남은 R$ 는 속도
						local want, leftover = skipExpect(level, value)
						T.eq(after.level, want, label .. ": " .. product.key .. " @" .. level)
						if leftover > 0 then
							local wantSpeed =
								math.min(Cfg.SPEED_MAX, before.speed + leftover * Cfg.PRODUCT_SPEED_PER_ROBUX)
							T.truthy(after.speed >= wantSpeed, label .. ": 남은 R$ 만큼 속도")
						end
					end
					if product.kind ~= "coins" then
						T.eq(after.money, before.money, label .. ": 코인 상품이 아니면 코인 그대로")
					end
					table.insert(genuine, { id = pid, key = product.key, result = result })
					did.genuine += 1
				end

				local function dupReceipt(label)
					if #genuine == 0 then
						return
					end
					-- 기록 고리(500개) 안쪽만: 최근 50장 중에서
					local g = genuine[#genuine - math.floor(rand() * math.min(#genuine, 50))]
					local before = snapA()
					local onTreadmill = A.attrs.OnTreadmill == true
					local result = process(w, receipt(w, g.key, g.id, A), 400)
					local after = snapA()
					sameA(before, after, label .. " 중복 " .. g.id, onTreadmill or A.attrs.OnTreadmill == true)
					if g.result == GRANTED then
						T.eq(result, GRANTED, label .. ": 이미 저장된 영수증은 계속 확인")
					else
						T.truthy(result == GRANTED or result == NOT_YET)
						if result == GRANTED then
							g.result = GRANTED
							local s = stored(w, A)
							T.truthy(
								s ~= nil and table.find(s.receipts, g.id) ~= nil,
								label .. ": 저장 안 된 영수증을 확인함 " .. g.id
							)
						end
					end
					did.dup += 1
				end

				local function fakeReceipt(label)
					local good = pick(w.Products.list)
					local r = receipt(w, good.key, "fake-" .. nextId .. "-" .. did.fake, A)
					local roll = rand()
					if roll < 0.15 then
						r.ProductId = pick({ 0, -1, 999, 1e300, 0 / 0, "x", true, 5.5 })
					elseif roll < 0.3 then
						r.PlayerId = pick({ 777777, 0, -5, "9701", 0 / 0, true, {} })
					elseif roll < 0.4 then
						r.PurchaseId = nil
					elseif roll < 0.5 then
						r.PurchaseId = ""
					elseif roll < 0.6 then
						r.ProductId = nil
					elseif roll < 0.7 then
						r.PlayerId = nil
					elseif roll < 0.85 then
						r.ProductId = 424242 -- 안 붙인 id
					else
						r = {}
					end
					local before = snapA()
					local result = process(w, r, 400)
					T.eq(result, NOT_YET, label .. ": 가짜 영수증은 NotProcessedYet")
					sameA(before, snapA(), label .. " 가짜")
					did.fake += 1
				end

				local function receiptForB(label)
					nextId += 1
					local product = pick(w.Products.list)
					local before = snapA()
					local boughtB = dataB.stats.productsBought or 0
					local result = process(w, receipt(w, product.key, "fb-" .. nextId, B), 400)
					T.eq(result, GRANTED, label .. ": B 의 영수증") -- B 는 저장 가능, 저장소 정상일 때만 섞음
					sameA(before, snapA(), label .. " B 영수증 → A", A.attrs.OnTreadmill == true)
					T.eq(dataB.stats.productsBought, boughtB + 1)
					T.eq(dataB.treadmillLevel <= 20 and dataB.treadmillLevel >= 0, true)
					lockedBefore = lockedB()
					did.forB += 1
				end

				local VALID_STATE = { Nest = true, Carried = true, Dropped = true }
				local function checkPlayer(data, who, label)
					local tag = who .. " " .. label
					T.truthy(
						finite(data.money) and data.money >= 0 and data.money <= Cfg.MONEY_MAX,
						tag .. ": 코인 " .. tostring(data.money)
					)
					T.truthy(
						finite(data.speed) and data.speed >= 0 and data.speed <= Cfg.SPEED_MAX,
						tag .. ": 속도 " .. tostring(data.speed)
					)
					local boosts = { [1] = true }
					for _, m in w.Products.BOOST_MULTIPLIERS do
						boosts[m] = true
					end
					T.truthy(boosts[data.treadmillBoost], tag .. ": 부스트 " .. tostring(data.treadmillBoost))
					T.truthy(type(data.moneyPass) == "boolean", tag .. ": 코인 2배 칸")
					T.truthy(
						data.treadmillLevel >= 0
							and data.treadmillLevel <= Up.TREADMILL_MAX_LEVEL
							and data.treadmillLevel == math.floor(data.treadmillLevel),
						tag .. ": 러닝머신 레벨"
					)
					T.truthy(#data.receipts <= Cfg.RECEIPT_HISTORY_MAX, tag .. ": 영수증 기록 " .. #data.receipts)
					local seen = {}
					for _, id in data.receipts do
						T.truthy(type(id) == "string" and #id >= 1 and #id <= 64, tag .. ": 영수증 글자")
						T.falsy(seen[id], tag .. ": 영수증 겹침 " .. id)
						seen[id] = true
					end
					local total = 0
					for id, stack in data.fruits do
						T.truthy(Plants.get(id) ~= nil, tag .. ": 모르는 열매 칸")
						T.truthy(
							finite(stack.count) and stack.count == math.floor(stack.count) and stack.count >= 1,
							tag .. ": 열매 개수"
						)
						T.truthy(finite(stack.value) and stack.value >= 0, tag .. ": 열매 값")
						total += stack.count
					end
					T.truthy(total <= Cfg.FRUIT_BAG_MAX, tag .. ": 열매 가방 " .. total)
					T.truthy(#data.eggs <= Cfg.EGG_INVENTORY_MAX, tag .. ": 씨앗 가방")
					T.truthy(#data.pets + #data.incubators <= GR.capacity(data.penLevel), tag .. ": 정원 칸")
					local ids = {}
					for _, list in { data.pets, data.incubators, data.eggs } do
						for _, r in list do
							T.truthy(not ids[r.uid], tag .. ": uid 겹침")
							ids[r.uid] = true
						end
					end
				end
				local function checkAll(label)
					checkPlayer(dataA, "A", label)
					checkPlayer(dataB, "B", label)
					T.eq(dataA.treadmillBoost, expect.boost, label .. ": A 부스트는 영수증으로만")
					T.eq(dataA.moneyPass, expect.pass, label .. ": A 코인 2배는 영수증으로만")
					T.eq(dataA.stats.productsBought or 0, expect.bought, label .. ": 구매 횟수 = 영수증 수")
					T.eq(#grantedList(w, A), expect.bought, label .. ": ProductGranted = 영수증 수")
					T.eq(#grantedList(w, B), dataB.stats.productsBought or 0, label .. ": B ProductGranted")
					for _, part in H.map.folders.Eggs.children do
						T.truthy(VALID_STATE[part:GetAttribute("EggState")], label .. ": 씨앗 상태")
					end
					for player, egg in w.EggService.carriers() do
						T.eq(egg.state, "Carried")
						T.truthy(player.attrs.CarryingEgg ~= "", label .. ": CarryingEgg")
					end
					for _, text in H.warnings do
						local known = string.sub(text, 1, 11) == "[AntiCheat]"
							or string.sub(text, 1, 16) == "[ProductService]"
							or string.sub(text, 1, 13) == "[DataService]"
						T.truthy(known, label .. ": 뜻밖의 서버 warn " .. tostring(text))
					end
					T.eq(lockedB(), lockedBefore, label .. ": B 의 것이 A 때문에 바뀜")
				end

				for step = 1, 1000 do
					local label = "#" .. step
					local roll = rand()
					if rand() < 0.08 then
						H.setPhase(if H.cycle.phase == "Night" then "Day" else "Night")
						did.night += 1
					end
					if rand() < 0.02 then
						cycle += 1
						H.setPhase("Intermission", cycle)
						H.setPhase("Day", cycle)
					end
					if rand() < 0.1 then
						dataA.money = pick({ 0, 5, 499, 500, 7500, 1e6, 1e12, 1e18, Cfg.MONEY_MAX - 1, Cfg.MONEY_MAX })
					end
					if rand() < 0.1 then
						dataA.speed =
							pick({ 10, 50, 900, 1e4, 1e8, 1e11, 1e15, 1e20, Cfg.SPEED_MAX - 1, Cfg.SPEED_MAX })
						w.SpeedService.refresh(A)
					end
					if rand() < 0.06 then
						dataA.treadmillLevel = pick({ 0, 1, 2, 5, 19, 20 })
					end
					if roll < 0.3 then
						-- 영수증 섞기
						local r = rand()
						if r < 0.42 then
							genuineReceipt(label)
						elseif r < 0.68 then
							dupReceipt(label)
						elseif r < 0.88 then
							fakeReceipt(label)
						else
							-- B 영수증은 저장소가 정상일 때만 (B 의 결과를 단순하게)
							H.store.failNext = 0
							receiptForB(label)
						end
						if rand() < 0.5 then
							H.store.failNext = 0 -- 저장소 복구
						end
					elseif roll < 0.42 then
						-- 걷기·순간이동 (구역·허브·러닝머신)
						if rand() < 0.4 then
							H.teleport(A, plot.treadmill.x, 3, plot.treadmill.z)
						else
							H.teleport(
								A,
								pick({ -90, -58, 0, 70 }),
								pick({ 3, 3, 14 }),
								pick({ -100, -1, 0.5, 100, 600, 2000, 5039 })
							)
						end
					else
						-- Remote 던지기
						local at = pick({
							{ (penA.xMin + penA.xMax) / 2, (penA.zMin + penA.zMax) / 2 },
							{ stall.x, stall.z },
							{ plot.treadmill.x, plot.treadmill.z },
							{ 0, 5 },
						})
						if rand() < 0.6 then
							H.teleport(A, at[1], 3, at[2])
						end
						H.landmarks.nearName = if rand() < 0.5 then "SakuraIncubator" else nil
						local name = pick(serverNames)
						H.client(A, name, arg(), arg(), arg())
						did.remote += 1
					end
					-- 서버 → 클라 이름으로 위조
					if rand() < 0.1 then
						H.client(A, pick(clientNames), pick(junk), pick(junk))
					end
					H.advance(pick({ 0.2, 0.5, 1, 2, 5, if rand() < 0.05 then 40 else 3 }))
					checkAll(label)
				end

				-- 끝: 저장소를 고치고 못 끝낸 영수증을 다시 → 전부 PurchaseGranted, 효과 그대로, 저장소와 메모리가 같음
				H.store.failNext = 0
				local before = snapA()
				for _, g in genuine do
					if g.result == NOT_YET then
						T.eq(process(w, receipt(w, g.key, g.id, A), 400), GRANTED, "마무리: " .. g.id)
					end
				end
				T.eq(
					H.run(function()
						return w.DataService.save(A, false)
					end, 400),
					true
				)
				local after = snapA()
				T.eq(after.bought, before.bought, "마무리 재전송이 효과를 또 내지 않음")
				T.eq(after.boost, before.boost)
				T.eq(after.receipts, before.receipts)
				local s = stored(w, A)
				T.eq(s.treadmillBoost, dataA.treadmillBoost)
				T.eq(s.moneyPass, dataA.moneyPass)
				T.eq(s.treadmillLevel, dataA.treadmillLevel)
				T.eq(#s.receipts, #dataA.receipts)
				T.eq(s.receipts[#s.receipts], dataA.receipts[#dataA.receipts])
				print(
					string.format(
						"      (참고) 시험 범위: Remote %d · 진짜 영수증 %d (NotProcessedYet %d, 저장소 고장 %d번) · 중복 %d · 가짜 %d · B 영수증 %d · 밤 %d번 / 부스트 %d · 코인 2배 %s · 구매 %d",
						did.remote,
						did.genuine,
						did.notYet,
						did.failures,
						did.dup,
						did.fake,
						did.forB,
						did.night,
						dataA.treadmillBoost,
						tostring(dataA.moneyPass),
						expect.bought
					)
				)
				T.truthy(
					did.remote > 300 and did.genuine >= 60 and did.dup >= 30 and did.fake >= 25,
					"시험이 너무 약함"
				)
				T.truthy(did.notYet >= 3, "저장 실패 경우를 못 봄")
				T.truthy(did.forB >= 5)
			end)
			H.uninstall()
			if not ok then
				error(err, 0)
			end
		end
	)
end
