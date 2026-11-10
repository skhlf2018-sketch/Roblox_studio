--!nocheck
--[[
	K 시리즈 — 슈퍼 씨앗(seed_super, 개발자 상품 5999 R$) · 경비 깨어남(GUARD_WAKE_SECONDS) 구멍 찾기 (주임, 2026-11-10)
	L 시리즈 — 66번: 훔치면 바로 경비 머리 위 빨간 느낌표 (State "Alert") → WAKE(0.3초) 뒤 쫓아옴/잡힘
	이미 있는 시험(products.spec 64번 · services_world 65번 · holes_touch_catch)과 겹치지 않게 "돈이 걸린 길 · 무한 이득 · 시간으로 잡히는 길" 위주.

	슈퍼 씨앗 (ProductService.grant → rollSeed → BaseService.grantEgg(bought = true)):
	  산 씨앗(BagEgg.bought)은 가방 상한 50 을 넘어도 들어가고, 저장에서 안 잘림 (DataSchema 스키마 9)
	  K1 무작위 300번: 5종 전부 · 슈퍼 등급 둥지 식물만 · 전부 bought · 같은 uid 없음
	  K2 산 씨앗으로 할 수 있는 일 = 보통 씨앗과 같음 (심기 → 성장 → 팔기, 넘친 가방에서 심으면 줄어듦, 다시 가방으로 뽑기는 49개 이하일 때만)
	  K3 가방 넘침(52/50): 훔친 씨앗 배달 · 사쿠라 뽑기 · /seed 는 막힘 (공짜 씨앗이 무한히 쌓이지 않음) — 50 미만이 되면 다시 됨
	  K4 bought 위조 길 없음: 모든 ToServer Remote 에 쓰레기 인자 퍼징 · 저장 데이터 bought 9999개 불러오기
	  K5 영수증: 같은 PurchaseId 5번 → 1개 · 서로 다른 3장 → 3개 · 저장 실패 중 재전송 · 지급 직후 나감
	  K6 스키마 8 → 9 (옛 씨앗은 보통 · 50개 초과 옛 데이터는 예전처럼 잘림, 진짜 DataService 저장·불러오기)
	  K7 가방 씨앗은 밤·낮에도 · 남의 Remote 로도 안 뺏김

	경비 깨어남 (GuardLogic.isWaking · Egg.stolenAt · GuardianService) — 시간은 전부 Config.GUARD_WAKE_SECONDS(WAKE)·GUARD_TICK_SECONDS 에서 계산:
	  K8 21구역 × 속도 3종: 둥지에서 집고 경비 몸 위에 서도 WAKE 전까지 안 잡히고 안 쫓음 (State Alert) · WAKE 뒤 첫 틱에 잡힘
	  K9 WAKE 뒤 안 닿으면 60초가 지나도 안 잡힘 (시간으로 잡히는 길 없음)
	  K10 바닥에서 다시 줍기 = 지연 없음 · 둥지로 돌아간 씨앗을 다시 집으면 새 WAKE · 세 사람이 겹치게 훔침 = 각자 자기 WAKE
	  K11 지연 중 경계(zMax) 넘기 = 즉시 잡힘 · 밤 · 허브 (느낌표 없음)
	  K12 GuardLogic.isWaking 경계 (NaN · nil · 미래 시각)
	66번 느낌표 (State "Alert"):
	  L1 21구역 × (멀리 · 닿음): 훔친 첫 틱에 Alert · 그동안 경비 제자리(MoveTo 안 부름)·대상 0·안 잡힘 · WAKE 뒤 멀리 = Chase (그 사람이 대상) / 닿음 = 잡힘
	  (다른 사람을 쫓는 중 Chase 그대로 · 바닥 씨앗 = 느낌표 없음 은 services_world 65·66번, 허브·밤 = 느낌표 없음 은 K11)
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local S = "ReplicatedStorage/Shared/"
	local V = "ServerScriptService/Server/"
	local Config = Loader.require(S .. "Data/Config")
	local Biomes = Loader.require(S .. "Data/Biomes")
	local MapLayout = Loader.require(S .. "Data/MapLayout")
	local Plants = Loader.require(S .. "Data/Plants")
	local Remotes = Loader.require(S .. "Remotes")
	local GardenRules = Loader.require(S .. "GardenRules")
	local DataSchema = Loader.require(V .. "Logic/DataSchema")
	local GuardLogic = Loader.require(V .. "Logic/GuardLogic")

	local GRANTED = "ProductPurchaseDecision.PurchaseGranted"
	local NOT_YET = "ProductPurchaseDecision.NotProcessedYet"
	local WAKE = Config.GUARD_WAKE_SECONDS
	local TICK = Config.GUARD_TICK_SECONDS
	local ALERT_BY = TICK + 0.02 -- 훔친 뒤 이 시간이 지나면 (첫 경비 틱이 한 번은 돌았으므로) State 는 Alert
	local MAX = Config.EGG_INVENTORY_MAX
	local SUPER_SEEDS =
		{ "rainbow_thunder_tree", "sky_pillar_flower", "circuit_sprout", "password_fern", "wifi_sunflower" }

	local function inWorld(options, fn)
		local H = ServerHarness.install(Loader, T, options)
		local ok, err = pcall(function()
			H.startNet()
			fn(H)
		end)
		H.uninstall()
		if not ok then
			error(err, 0)
		end
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
	-- 상점 세상: 진짜 ProductService · BaseService · PetService · DataService (가짜 DataStore)
	------------------------------------------------------------------
	local function shopWorld(H, userId)
		local w = { H = H }
		w.Products = H.shared("Data/Products")
		w.Sessions = H.server("Sessions")
		w.DataService = H.server("Services/DataService")
		w.ProductService = H.server("Services/ProductService")
		w.PetService = H.server("Services/PetService")
		w.BaseService = H.server("Services/BaseService")
		w.EggPlacement = H.shared("EggPlacement")
		w.fakeIds, w.byId = {}, {}
		for i, product in w.Products.list do
			if not product.isPass then
				w.fakeIds[product.key] = 100000 + i
				w.byId[100000 + i] = product
			end
		end
		w.Products.byProductId = function(id)
			return w.byId[id]
		end
		w.player = H.newPlayer(userId or 9701, "Buyer")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		w.data.penLevel = H.shared("Data/Upgrades").PEN_MAX_LEVEL
		local x, z = H.plotSpot(1)
		H.spawn(w.player, x, 3, z)
		return w
	end

	local function receipt(w, key, purchaseId, player)
		return {
			PlayerId = (player or w.player).UserId,
			ProductId = w.fakeIds[key],
			PurchaseId = purchaseId,
			CurrencySpent = 1,
		}
	end

	local function process(w, r, maxSeconds)
		return w.H.run(function()
			return w.ProductService.processReceipt(r)
		end, maxSeconds or 30)
	end

	local function countBought(data)
		local bought, normal = 0, 0
		for _, egg in data.eggs do
			if egg.bought then
				bought += 1
			else
				normal += 1
			end
		end
		return bought, normal
	end

	local function fillBag(w, n)
		for _ = 1, n do
			T.truthy(w.BaseService.grantEgg(w.player, "sprout_daisy", "normal", {}, "dev"), "보통 씨앗 넣기")
		end
	end

	local function gardenSpots(data)
		local spots = {}
		for _, r in data.incubators do
			table.insert(spots, { x = r.x, z = r.z, size = r.size, petId = r.petId })
		end
		for _, r in data.pets do
			table.insert(spots, { x = r.x, z = r.z, size = r.size, petId = r.petId })
		end
		return spots
	end

	-- 가방의 씨앗(uid)을 내 정원 빈 자리에 심음 → true/false
	local function plant(w, uid)
		local egg
		for _, e in w.data.eggs do
			if e.uid == uid then
				egg = e
			end
		end
		local l = w.EggPlacement.firstFreeGrid(egg.size, gardenSpots(w.data), egg.petId)
		local spot = w.H.MapLayout.toWorld(1, l.x, l.z)
		local x, z = w.H.plotSpot(1)
		w.H.spawn(w.player, x, 3, z)
		return w.BaseService.placeEgg(w.player, uid, spot.x, spot.z)
	end

	local function enableSaving(w)
		w.DataService.start()
		w.session.saveEnabled = true
	end

	local function stored(w, userId)
		local entry = w.H.store.data["player_" .. (userId or w.player.UserId)]
		return entry and entry.data
	end

	------------------------------------------------------------------
	T.suite("K1 슈퍼 씨앗 무작위 300번: 5종 전부 · 슈퍼 등급 둥지 식물만 · 전부 산 씨앗")

	T.test(
		"서버 난수로 300번 지급 → 후보 5종이 전부 나오고 (각 25번 이상) 그 5종 밖은 0 · 전부 슈퍼 등급 + 둥지 식물 · bought = true · 보통 크기 · 돌연변이 0 · uid 안 겹침 · 가방이 300개여도 안 터짐 (상한 50 무시) · 구매 횟수 300 · 서버 warn 0",
		function()
			inWorld(nil, function(H)
				local w = shopWorld(H)
				for _ = 1, 300 do
					T.truthy(w.ProductService.grant(w.player, "seed_super", "purchase"))
				end
				T.eq(#w.data.eggs, 300, "상한 50 을 넘어 300개")
				local counts, uids = {}, {}
				for _, egg in w.data.eggs do
					local plant = Plants.get(egg.petId)
					T.truthy(
						plant ~= nil and plant.rarity == "super" and plant.source == "nest",
						"슈퍼 등급 둥지 식물만: " .. tostring(egg.petId)
					)
					T.truthy(table.find(SUPER_SEEDS, egg.petId), "후보 5종: " .. tostring(egg.petId))
					T.eq(egg.bought, true)
					T.eq(egg.size, "normal")
					T.eq(#egg.mutations, 0)
					T.eq(egg.progress, 0)
					T.eq(uids[egg.uid], nil, "uid 겹침 " .. egg.uid)
					uids[egg.uid] = true
					counts[egg.petId] = (counts[egg.petId] or 0) + 1
				end
				for _, id in SUPER_SEEDS do
					T.truthy(
						(counts[id] or 0) >= 25,
						id .. " 300번 중 " .. tostring(counts[id]) .. "번 (5종 전부 고르게 나와야 함)"
					)
				end
				T.eq(w.data.stats.productsBought, 300)
				-- 영수증 길(processReceipt)도 같은 지급
				enableSaving(w)
				for i = 1, 20 do
					T.eq(process(w, receipt(w, "seed_super", "rnd-" .. i)), GRANTED)
				end
				T.eq(#w.data.eggs, 320)
				T.eq(#w.H.warnings, 0, "서버 warn " .. tostring(w.H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("K2 산 씨앗으로 할 수 있는 일 = 보통 씨앗과 같음 (심기 → 성장 → 팔기)")

	T.test(
		"가방 52/50 (보통 50 + 산 2) 에서: 같은 식물의 산 씨앗과 보통 씨앗을 심으면 정원 기록이 uid 말고 똑같고 (bought 칸 없음) → 코인으로 성장 건너뛰기(값 같음) → 성체 → 팔기 값 같음 · 심으면 가방이 줄어듦 (심을 때 상한 검사는 없음) · 정원에서 다시 가방으로 뽑기는 가방이 49개 이하일 때만 · 뽑은 씨앗에는 bought 가 안 붙음",
		function()
			inWorld(nil, function(H)
				local w = shopWorld(H)
				w.BaseService.start()
				w.PetService.start()
				w.data.money = 1e12
				fillBag(w, MAX)
				T.truthy(
					w.BaseService.grantEgg(w.player, "circuit_sprout", "normal", {}, "purchase", true),
					"산 씨앗 1"
				)
				T.truthy(
					w.BaseService.grantEgg(w.player, "circuit_sprout", "normal", {}, "purchase", true),
					"산 씨앗 2"
				)
				T.eq(#w.data.eggs, MAX + 2)
				local boughtUid, normalUid
				for _, egg in w.data.eggs do
					if egg.bought and not boughtUid then
						boughtUid = egg.uid
					end
				end
				-- 같은 식물의 보통 씨앗 한 개 (가방 맨 앞의 보통 씨앗을 같은 식물로 바꿔 끼움 — 선물 길은 가방이 가득이라 못 받음)
				for _, egg in w.data.eggs do
					if not egg.bought then
						egg.petId = "circuit_sprout"
						egg.biomeId = Plants.get("circuit_sprout").biome
						normalUid = egg.uid
						break
					end
				end
				T.truthy(plant(w, boughtUid), "산 씨앗 심기 (가방이 넘친 상태에서도 심을 수 있음)")
				T.eq(#w.data.eggs, MAX + 1, "심으면 가방이 줄어듦")
				T.truthy(plant(w, normalUid), "보통 씨앗 심기")
				T.eq(#w.data.eggs, MAX, "보통 50 이 아니라 49 + 산 1")
				T.eq(#w.data.incubators, 2)
				local a, b = w.data.incubators[1], w.data.incubators[2]
				T.eq(a.petId, b.petId)
				T.eq(a.size, b.size)
				T.eq(a.required, b.required, "자라는 시간 같음")
				T.eq(a.progress, b.progress)
				T.eq(#a.mutations, #b.mutations)
				T.eq(a.bought, nil, "정원 기록에 bought 칸이 새지 않음")
				T.eq(b.bought, nil)
				-- 건너뛰기 값이 같음 (같은 식물 · 같은 진행)
				local costA = GardenRules.skipCost(a.petId, a.progress, a.required, "all")
				local costB = GardenRules.skipCost(b.petId, b.progress, b.required, "all")
				T.eq(costA, costB)
				local m0 = w.data.money
				H.client(w.player, "SkipGrowth", a.uid, "all")
				H.client(w.player, "SkipGrowth", b.uid, "all")
				T.eq(m0 - w.data.money, costA + costB, "두 번 건너뛴 값")
				H.advance(3) -- 성장 틱
				T.eq(#w.data.incubators, 0, "둘 다 성체가 됨")
				T.eq(#w.data.pets, 2)
				local p1, p2 = w.data.pets[1], w.data.pets[2]
				T.eq(p1.petId, p2.petId)
				T.eq(p1.bought, nil)
				T.eq(GardenRules.sellPrice(p1), GardenRules.sellPrice(p2), "팔 값 같음")
				-- 팔기 (SellPlant — 내 정원 가까이)
				local x, z = H.plotSpot(1)
				H.spawn(w.player, x, 3, z)
				local money = w.data.money
				H.client(w.player, "SellPlant", p1.uid)
				H.client(w.player, "SellPlant", p2.uid)
				T.eq(#w.data.pets, 0, "둘 다 팔림")
				T.truthy(w.data.money > money, "코인을 받음")
				-- 넘친 가방 시나리오 이어서: 49 + 산 1 = 50. 산 씨앗을 하나 더 사서 51 → 정원 씨앗 뽑기는 막힘
				T.truthy(w.BaseService.grantEgg(w.player, "wifi_sunflower", "normal", {}, "purchase", true))
				T.eq(#w.data.eggs, MAX + 1)
				local spare
				for _, egg in w.data.eggs do
					if not egg.bought then
						spare = egg.uid
						break
					end
				end
				T.truthy(plant(w, spare), "보통 씨앗 심음 → 가방 50")
				T.eq(#w.data.eggs, MAX)
				local planted = w.data.incubators[1].uid
				H.client(w.player, "PickUpPlacedEgg", planted)
				T.eq(#w.data.incubators, 1, "가방 50 이면 정원에서 다시 가방으로는 안 됨")
				T.eq(#w.data.eggs, MAX)
				for _, egg in w.data.eggs do
					if egg.bought then
						T.truthy(plant(w, egg.uid), "산 씨앗 심음")
						break
					end
				end
				T.eq(#w.data.eggs, MAX - 1, "가방 49")
				H.client(w.player, "PickUpPlacedEgg", planted)
				T.eq(
					#w.data.incubators,
					1,
					"방금 심은 산 씨앗 1 (뽑은 것 하나 줄고) — 심은 것 둘 중 하나가 가방으로"
				)
				T.eq(#w.data.eggs, MAX, "49 → 50")
				-- 가방으로 돌아온 씨앗은 bought 가 아님 (돈으로 산 표시는 한 번 심으면 사라짐: 그래도 가방 총수는 50 이하로만 늘어남)
				local last = w.data.eggs[#w.data.eggs]
				T.eq(last.bought, nil, "정원에서 뽑은 씨앗은 보통 씨앗")
				T.eq(#w.H.warnings, 0, "서버 warn " .. tostring(w.H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite(
		"K3 가방이 넘쳐도(52/50) 공짜 씨앗은 안 쌓임: 훔친 씨앗 배달 · 사쿠라 뽑기 · /seed"
	)

	T.test(
		"가방 52 (보통 50 + 산 2): 훔친 씨앗을 들고 허브로 와도 배달 안 됨 (손에 그대로) · 사쿠라 뽑기 거부 + 크리스탈 안 줄어듦 · /seed 거부 · 일부러 20번씩 반복해도 가방 52 그대로 — 산 씨앗 3개를 심어 49 가 되면 그때 한 개씩만 다시 됨 (50 에서 다시 막힘)",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = shopWorld(H)
				w.EggService = H.server("Services/EggService")
				w.SakuraService = H.server("Services/SakuraService")
				w.EggService.start()
				w.BaseService.start()
				w.PetService.start()
				w.SakuraService.start()
				local DevCommands = H.server("Services/DevCommands")
				DevCommands.start()
				H.setPhase("Intermission", 1)
				H.setPhase("Day", 1)
				w.data.sakuraCrystals = 100
				w.data.money = 1e12
				fillBag(w, MAX)
				for _ = 1, 3 do
					T.truthy(w.BaseService.grantEgg(w.player, "password_fern", "normal", {}, "purchase", true))
				end
				T.eq(#w.data.eggs, MAX + 3)
				local function steal(biomeId)
					for _, part in H.map.folders.Eggs.children do
						if part:GetAttribute("BiomeId") == biomeId and part:GetAttribute("EggState") == "Nest" then
							H.teleport(w.player, part.Position.X, part.Position.Y, part.Position.Z)
							part:FindFirstChild("StealPrompt").Triggered:Fire(w.player)
							if w.EggService.getCarried(w.player) then
								return part
							end
						end
					end
					error("주울 씨앗이 없음")
				end
				local function walkIntoHub()
					H.advance(20)
					w.Sessions.exemptMovement(w.session, 5)
					local x, z = H.hubSpot()
					H.teleport(w.player, x, 3, z)
					H.advance(0.6)
				end
				-- 씨앗을 훔쳐 허브로 걸어 들어와 배달을 시도 → 배달이 됐나 (그 뒤 씨앗은 둥지로 되돌림)
				local function stealAndTryDeliver(biomeId)
					local part = steal(biomeId)
					walkIntoHub()
					local delivered = #H.sent(w.player, "EggDelivered")
					local carried = w.EggService.getCarried(w.player) ~= nil
					if carried then
						w.EggService.confiscate(w.player)
					end
					return delivered, carried, part
				end
				local function drawSakura(times)
					H.landmarks.nearName = "SakuraIncubator"
					for _ = 1, times do
						H.client(w.player, "SakuraDraw")
						H.advance(0.6)
					end
				end
				local function boughtUids()
					local list = {}
					for _, egg in w.data.eggs do
						if egg.bought then
							table.insert(list, egg.uid)
						end
					end
					return list
				end
				-- (1) 52: 배달 · 뽑기 · /seed 전부 거부
				local deliveredBefore = #H.sent(w.player, "EggDelivered")
				for _, biome in { "forest", "desert", "lake" } do
					local delivered, carried = stealAndTryDeliver(biome)
					T.eq(delivered, deliveredBefore, "가방이 넘쳤으면 배달 안 됨 " .. biome)
					T.truthy(carried, "씨앗은 손에 그대로 " .. biome)
					T.eq(#w.data.eggs, MAX + 3)
				end
				drawSakura(20)
				T.eq(#w.data.eggs, MAX + 3, "사쿠라 20번 시도해도 그대로")
				T.eq(w.data.sakuraCrystals, 100, "크리스탈 안 줄어듦 (뽑지 못했으면 돈도 안 받음)")
				for _ = 1, 20 do
					w.player.Chatted:Fire("/seed sprout_daisy")
				end
				T.eq(#w.data.eggs, MAX + 3, "/seed 20번도 그대로")
				-- (2) 산 씨앗 2개를 심어 가방 51 → 50 : 아직 막힘 (50 이상이면 배달 안 됨)
				local ids = boughtUids()
				T.truthy(plant(w, ids[1]))
				T.eq(#w.data.eggs, MAX + 2)
				T.truthy(plant(w, ids[2]))
				T.eq(#w.data.eggs, MAX + 1)
				T.truthy(plant(w, ids[3]))
				T.eq(#w.data.eggs, MAX, "50")
				local delivered, carried = stealAndTryDeliver("forest")
				T.eq(delivered, deliveredBefore, "50: 아직 배달 안 됨")
				T.truthy(carried)
				drawSakura(5)
				T.eq(#w.data.eggs, MAX, "50: 사쿠라 안 됨")
				w.player.Chatted:Fire("/seed sprout_daisy")
				T.eq(#w.data.eggs, MAX, "50: /seed 안 됨")
				-- (3) 보통 씨앗 1개 심음 → 49: 배달 됨 (50 으로 한 번만) · 바로 다시 막힘
				local normalUid
				for _, egg in w.data.eggs do
					if not egg.bought then
						normalUid = egg.uid
						break
					end
				end
				T.truthy(plant(w, normalUid))
				T.eq(#w.data.eggs, MAX - 1, "49")
				stealAndTryDeliver("forest")
				T.eq(#w.data.eggs, MAX, "49 → 배달돼서 50")
				T.eq(#H.sent(w.player, "EggDelivered"), deliveredBefore + 1, "배달 1번")
				local _, carriedAgain = stealAndTryDeliver("desert")
				T.eq(#w.data.eggs, MAX, "50 에서 또 막힘")
				T.truthy(carriedAgain)
				-- 사쿠라: 49 로 만들면 한 번 됨 (크리스탈 정확히 한 번 값)
				T.truthy(plant(w, w.data.eggs[1].uid))
				T.eq(#w.data.eggs, MAX - 1)
				local crystals = w.data.sakuraCrystals
				drawSakura(1)
				T.eq(#w.data.eggs, MAX, "49 → 뽑기 한 번 → 50")
				T.eq(w.data.sakuraCrystals, crystals - Config.SAKURA_DRAW_COST)
				drawSakura(3)
				T.eq(#w.data.eggs, MAX, "50 에서 막힘")
				T.eq(w.data.sakuraCrystals, crystals - Config.SAKURA_DRAW_COST, "크리스탈 그대로")
				-- /seed: 49 에서 한 번만
				T.truthy(plant(w, w.data.eggs[1].uid))
				w.player.Chatted:Fire("/seed sprout_daisy")
				w.player.Chatted:Fire("/seed sprout_daisy")
				T.eq(#w.data.eggs, MAX, "/seed 도 50 까지만")
				-- (하네스에는 TextChatService 가 없어 DevCommands 가 "TextChatCommand 등록 실패" 경고 1개를 냄 — 그것만 빼고 0)
				local others = 0
				for _, text in H.warnings do
					if not string.find(tostring(text), "DevCommands", 1, true) then
						others += 1
					end
				end
				T.eq(others, 0, "서버 warn " .. tostring(H.warnings[2] or H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("K4 bought 위조 길이 없음 · 저장 데이터 9999개")

	T.test(
		"모든 ToServer Remote 에 쓰레기 인자 3,000번 (bought = true 표 · 가방/정원 uid · NaN · 큰 수 · 글자): 산 씨앗(3개)이 더 생기지 않음 — bought 인 가방 씨앗은 처음 3개의 uid 뿐 · 보통 씨앗/정원 기록/성체에 bought 없음 · 씨앗 + 정원 합계는 늘지 않음 · 서버 오류 0",
		function()
			inWorld(nil, function(H)
				local w = shopWorld(H)
				w.BaseService.start()
				w.PetService.start()
				local FruitService = H.server("Services/FruitService")
				FruitService.start()
				local SakuraService = H.server("Services/SakuraService")
				SakuraService.start()
				H.server("Services/IndexService").start()
				w.data.money = 1e9
				w.data.sakuraCrystals = 50
				fillBag(w, 10)
				local original = {}
				for _ = 1, 3 do
					T.truthy(w.BaseService.grantEgg(w.player, "circuit_sprout", "normal", {}, "purchase", true))
				end
				for _, egg in w.data.eggs do
					if egg.bought then
						original[egg.uid] = true
					end
				end
				local totalAtStart = #w.data.eggs + #w.data.incubators + #w.data.pets
				local rand = T.rng(4242)
				local function pick(list)
					return list[math.floor(rand() * #list) + 1]
				end
				local junk = {
					0,
					-1,
					1,
					1e300,
					0 / 0,
					math.huge,
					-math.huge,
					"",
					"x",
					"all",
					"half",
					"Bat",
					true,
					false,
					{},
					{ bought = true },
					{ uid = "i1", bought = true },
					{ eggs = { { bought = true } } },
					{ 1, 2, 3 },
				}
				local names = {}
				for _, name in Remotes.ToServer do
					table.insert(names, name)
				end
				table.sort(names)
				local function uidPool()
					local pool = {}
					for _, e in w.data.eggs do
						table.insert(pool, e.uid)
					end
					for _, e in w.data.incubators do
						table.insert(pool, e.uid)
					end
					for _, e in w.data.pets do
						table.insert(pool, e.uid)
					end
					return pool
				end
				local function arg()
					local roll = rand()
					if roll < 0.5 then
						local pool = uidPool()
						if #pool > 0 then
							return pick(pool)
						end
					elseif roll < 0.58 then
						return nil
					end
					return pick(junk)
				end
				local px, pz = H.plotSpot(1)
				for step = 1, 3000 do
					H.spawn(w.player, px, 3, pz)
					if step % 7 == 0 then
						H.landmarks.nearName = if rand() < 0.5 then "SakuraIncubator" else nil
						w.data.money = 1e9
						w.data.sakuraCrystals = 50
					end
					local name = pick(names)
					H.client(w.player, name, arg(), arg(), arg())
					if step % 3 == 0 then
						H.advance(pick({ 0.3, 1, 5 }))
					end
					if step % 250 == 0 then
						local boughtNow = 0
						for _, e in w.data.eggs do
							if e.bought then
								boughtNow += 1
								T.truthy(original[e.uid], "새로 생긴 산 씨앗 " .. e.uid)
							end
						end
						T.truthy(boughtNow <= 3)
					end
				end
				for _, e in w.data.eggs do
					T.truthy(e.bought == nil or e.bought == true, "bought 는 true/없음 뿐")
					if e.bought then
						T.truthy(original[e.uid], "처음 3개 말고 산 씨앗 " .. e.uid)
					end
				end
				for _, r in w.data.incubators do
					T.eq(r.bought, nil, "정원 기록에 bought")
				end
				for _, r in w.data.pets do
					T.eq(r.bought, nil, "성체에 bought")
				end
				T.truthy(
					#w.data.eggs + #w.data.incubators + #w.data.pets <= totalAtStart,
					"씨앗·식물 수가 늘어남"
				)
				-- 서버가 보낸 DataUpdate(eggs) 에도 산 씨앗이 처음 3개를 넘지 않음
				for _, args in H.sent(w.player, "DataUpdate") do
					if args[1] == "eggs" then
						local n = 0
						for _, e in args[2].eggs do
							if e.bought then
								n += 1
							end
						end
						T.truthy(n <= 3, "Snapshot 에 산 씨앗 " .. n)
					end
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	T.test(
		"저장 데이터에 bought 씨앗 9,999개 + 보통 씨앗 100개 (서버만 쓰는 저장이라 위협은 아님): 불러올 때 안 터지고, 정해진 규칙대로 — 산 씨앗은 전부 남고 보통 씨앗은 50개까지 · uid 겹침은 하나만 · 두 번 보정해도 같음 · 정원 씨앗 넘침은 보통 칸만큼 · 다음 uid 가 겹치지 않음 · (크기 평가) 한 개 약 150바이트 → 9,999개 약 1.5MB 로 DataStore 4MB 안 (이 상한은 코드에 없음 — 약 28,000개부터 넘음)",
		function()
			local eggs = {}
			for i = 1, 9999 do
				table.insert(eggs, {
					uid = "i" .. i,
					petId = SUPER_SEEDS[(i % 5) + 1],
					size = "normal",
					mutations = {},
					progress = 0,
					bought = true,
				})
			end
			for i = 10000, 10099 do
				table.insert(
					eggs,
					{ uid = "i" .. i, petId = "sprout_daisy", size = "normal", mutations = {}, progress = 0 }
				)
			end
			-- 같은 uid 두 개 (겹침)
			table.insert(
				eggs,
				{ uid = "i1", petId = "sprout_daisy", size = "normal", mutations = {}, progress = 0, bought = true }
			)
			local raw = { version = 9, eggs = eggs, nextUid = 1 }
			local t0 = os.clock()
			local d = DataSchema.reconcile(DataSchema.migrate(raw), 0)
			local elapsed = os.clock() - t0
			local bought, normal = countBought(d)
			T.eq(bought, 9999, "산 씨앗 9,999개 전부 남음 (uid i1 겹침 하나는 이미 있어서 빠짐)")
			T.eq(normal, MAX, "보통 씨앗은 50개까지")
			T.eq(#d.eggs, 9999 + MAX)
			T.truthy(elapsed < 5, "불러오는 시간 " .. elapsed)
			local seen = {}
			for _, egg in d.eggs do
				T.eq(seen[egg.uid], nil, "uid 겹침 " .. egg.uid)
				seen[egg.uid] = true
			end
			local newUid = DataSchema.newUid(d, "i")
			T.eq(seen[newUid], nil, "새 uid 가 기존 uid 와 안 겹침 " .. newUid)
			local twice = DataSchema.reconcile(DataSchema.migrate(deepCopy(d)), 0)
			T.eq(#twice.eggs, #d.eggs, "두 번 보정해도 같음")
			-- 크기 어림: 씨앗 하나를 글자로 펼친 길이
			local sample =
				'{"uid":"i9999","petId":"rainbow_thunder_tree","size":"normal","mutations":[],"biomeId":"ghost_castle","special":false,"progress":0,"required":123456,"bought":true}'
			local megabytes = #sample * #d.eggs / 1048576
			T.truthy(megabytes < 4, "저장 크기 어림 " .. megabytes .. "MB")
			-- 큰 가방이 Snapshot 으로 나가는 크기: 개수 = 저장된 만큼 (상한 없음) — 평가용으로만 기록
			T.truthy(
				#d.eggs > Config.EGG_INVENTORY_MAX,
				"산 씨앗 상한이 없음 (평가: 사려면 5,999 R$ 씩이라 현실적이지 않음)"
			)
		end
	)

	------------------------------------------------------------------
	T.suite("K5 영수증: 중복 · 서로 다른 장 · 저장 실패 · 나감")

	T.test(
		"같은 PurchaseId 5번 → 슈퍼 씨앗 1개 · ProductGranted 1번 · 영수증 1개 · 서로 다른 PurchaseId 3장 → 3개 더 (4개) · 3장을 또 섞어 두 번씩 보내도 4개 · 저장소에도 산 씨앗 4개 (bought 그대로)",
		function()
			inWorld(nil, function(H)
				local w = shopWorld(H)
				enableSaving(w)
				local r = receipt(w, "seed_super", "dup-1")
				for i = 1, 5 do
					T.eq(process(w, r), GRANTED, "같은 영수증 " .. i .. "번째")
				end
				T.eq(#w.data.eggs, 1, "5번 와도 1개")
				T.eq(#w.data.receipts, 1)
				T.eq(#H.sent(w.player, "ProductGranted"), 1)
				for _, id in { "dup-2", "dup-3", "dup-4" } do
					T.eq(process(w, receipt(w, "seed_super", id)), GRANTED)
				end
				T.eq(#w.data.eggs, 4, "서로 다른 3장 → 3개 더")
				for _, id in { "dup-3", "dup-1", "dup-4", "dup-2", "dup-3" } do
					T.eq(process(w, receipt(w, "seed_super", id)), GRANTED)
				end
				T.eq(#w.data.eggs, 4, "섞어서 다시 보내도 4개")
				local bought = countBought(w.data)
				T.eq(bought, 4)
				T.eq(w.data.stats.productsBought, 4)
				local s = stored(w)
				T.eq(#s.eggs, 4, "저장소에도 4개")
				for _, egg in s.eggs do
					T.eq(egg.bought, true, "저장된 씨앗도 bought")
				end
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"저장이 계속 실패하는 중에 같은 영수증을 로블록스가 3번 재전송: 모두 NotProcessedYet · 가방엔 씨앗 1개뿐 (중복 지급 없음) · 저장소는 비어 있음 → 저장소가 살아나면 PurchaseGranted · 저장소에 씨앗 정확히 1개 (bought) · 이어서 또 보내도 1개",
		function()
			inWorld(nil, function(H)
				local w = shopWorld(H)
				enableSaving(w)
				H.store.failNext = 1000
				local r = receipt(w, "seed_super", "fail-seed")
				for i = 1, 3 do
					T.eq(process(w, r, 120), NOT_YET, "저장 실패 " .. i)
				end
				T.eq(#w.data.eggs, 1, "메모리에도 1개 (재전송이 또 주지 않음)")
				T.eq(stored(w), nil, "저장소엔 없음")
				H.store.failNext = 0
				T.eq(process(w, r), GRANTED)
				T.eq(#w.data.eggs, 1)
				local s = stored(w)
				T.truthy(
					s ~= nil and #s.eggs == 1 and s.eggs[1].bought == true,
					"저장소에 산 씨앗 정확히 1개"
				)
				T.eq(process(w, r), GRANTED)
				T.eq(#w.data.eggs, 1)
			end)
		end
	)

	T.test(
		"지급 직후(저장이 진행 중) 플레이어가 나감: 저장이 끝나 PurchaseGranted · 저장소에 산 씨앗 1개 + 영수증 — 다시 접속해서 같은 영수증을 또 받아도 1개 · 불러온 씨앗도 bought 그대로",
		function()
			local leftStore
			inWorld(nil, function(H)
				local w = shopWorld(H)
				enableSaving(w)
				local store = H.store
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
				local box = {}
				box.co = coroutine.create(function()
					box.value = w.ProductService.processReceipt(receipt(w, "seed_super", "leave-seed"))
				end)
				assert(coroutine.resume(box.co))
				T.eq(#w.data.eggs, 1, "지급은 이미 됨")
				H.leave(w.player)
				store.slow = false
				for _ = 1, 30 do
					H.advance(0.2)
					while #parked > 0 do
						coroutine.resume(table.remove(parked, 1))
					end
				end
				T.eq(box.value, GRANTED, "저장이 끝났으니 확인")
				local s = stored(w)
				T.truthy(s ~= nil and #s.eggs == 1 and s.eggs[1].bought == true, "나가도 저장됨")
				T.eq(s.receipts[1], "leave-seed")
				leftStore = deepCopy(H.store.data)
			end)
			inWorld(nil, function(H)
				local w = shopWorld(H)
				H.store.data = deepCopy(leftStore)
				w.DataService.start()
				local data, saveEnabled = H.run(function()
					return w.DataService.load(w.player)
				end)
				w.session.data, w.session.loaded, w.session.saveEnabled = data, true, saveEnabled
				T.eq(#data.eggs, 1, "다시 접속하면 씨앗 1개")
				T.eq(data.eggs[1].bought, true)
				T.eq(process(w, receipt(w, "seed_super", "leave-seed")), GRANTED)
				T.eq(#data.eggs, 1, "같은 영수증 또 와도 1개")
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("K6 스키마 8 → 9 (진짜 DataService 저장·불러오기)")

	T.test(
		"스키마 8 저장 데이터 (bought 칸 없음): 옛 씨앗은 전부 보통 씨앗으로 그대로 (정원·열매·코인도) · 8 이 50개 넘게 든 옛 데이터는 예전처럼 50개에서 잘림 (공짜로 산 씨앗이 되지 않음) · 불러오면 version 9 · 9 로 저장 → 다시 불러도 같음",
		function()
			inWorld(nil, function(H)
				local w = shopWorld(H)
				w.DataService.start()
				local function egg(i, petId)
					return { uid = "i" .. i, petId = petId, size = "normal", mutations = {}, progress = 0 }
				end
				local few, many = {}, {}
				for i = 1, 5 do
					table.insert(few, egg(i, "owl_oak"))
				end
				for i = 1, MAX + 7 do
					table.insert(many, egg(i, "sprout_daisy"))
				end
				H.store.data["player_9801"] =
					{ data = { version = 8, money = 777, speed = 12, eggs = few, nextUid = 6 } }
				H.store.data["player_9802"] = { data = { version = 8, money = 5, eggs = many, nextUid = 100 } }
				local pa = H.newPlayer(9801, "Old1")
				local pb = H.newPlayer(9802, "Old2")
				local da = H.run(function()
					return w.DataService.load(pa)
				end, 60)
				local db = H.run(function()
					return w.DataService.load(pb)
				end, 60)
				T.eq(da.version, 9)
				T.eq(#da.eggs, 5, "옛 씨앗 5개 그대로")
				T.eq(countBought(da), 0, "옛 씨앗은 보통 (bought 없음)")
				T.eq(da.money, 777)
				T.eq(db.version, 9)
				T.eq(#db.eggs, MAX, "50개 넘는 옛 데이터는 50에서 잘림")
				T.eq(countBought(db), 0, "잘린 데이터가 산 씨앗으로 둔갑하지 않음")
				-- 저장 → 다시 불러오기: 같음
				local sb = w.Sessions.create(pb)
				sb.data, sb.loaded, sb.saveEnabled = db, true, true
				local ok = H.run(function()
					return w.DataService.save(pb, true)
				end)
				T.truthy(ok)
				T.eq(#H.store.data["player_9802"].data.eggs, MAX)
				T.eq(H.store.data["player_9802"].data.version, 9)
				H.leave(pb)
				local pb2 = H.newPlayer(9802, "Old2")
				local db2 = H.run(function()
					return w.DataService.load(pb2)
				end, 60)
				T.eq(#db2.eggs, MAX)
				T.eq(countBought(db2), 0)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("K7 가방 씨앗은 밤 · 낮에도 남의 Remote 로도 안 뺏김")

	T.test(
		"산 씨앗·보통 씨앗이 가방에 있는 채로 낮 → 밤 → 낮 5번 돌려도 그대로 (bought 도 그대로) · 다른 사람이 내 uid 로 PlaceEgg/PickUpPlacedEgg/SkipGrowth/SakuraOffer 를 보내도 내 가방·정원·코인 불변이고 그 사람의 가방엔 아무것도 안 생김",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = shopWorld(H)
				w.EggService = H.server("Services/EggService")
				w.EggService.start()
				w.BaseService.start()
				w.PetService.start()
				H.server("Services/SakuraService").start()
				fillBag(w, 3)
				for _ = 1, 2 do
					T.truthy(w.BaseService.grantEgg(w.player, "wifi_sunflower", "normal", {}, "purchase", true))
				end
				-- 심은 씨앗 1개 (정원)
				local spare
				for _, egg in w.data.eggs do
					if not egg.bought then
						spare = egg.uid
						break
					end
				end
				T.truthy(plant(w, spare))
				local before = {}
				for _, egg in w.data.eggs do
					table.insert(before, egg.uid .. ":" .. tostring(egg.bought))
				end
				table.sort(before)
				local function sig()
					local list = {}
					for _, egg in w.data.eggs do
						table.insert(list, egg.uid .. ":" .. tostring(egg.bought))
					end
					table.sort(list)
					-- 정원 식물은 자라서 성체가 될 수 있으니 (씨앗 + 성체) 합계로
					return table.concat(list, ",") .. "|" .. (#w.data.incubators + #w.data.pets) .. "|" .. w.data.money
				end
				local start = sig()
				H.setPhase("Intermission", 1)
				H.setPhase("Day", 1)
				for cycle = 1, 5 do
					H.setPhase("Night", cycle)
					H.advance(2)
					H.setPhase("Intermission", cycle + 1)
					H.setPhase("Day", cycle + 1)
					H.advance(2)
				end
				T.eq(sig(), start, "밤 · 낮 5번 뒤에도 가방 그대로")
				-- 도둑이 내 uid 로
				local thief = H.newPlayer(9702, "Thief")
				local tsession, tdata = H.login(thief)
				tsession.plotIndex = 2
				tdata.money = 1e9
				tdata.sakuraCrystals = 50
				local x, z = H.plotSpot(2)
				H.spawn(thief, x, 3, z)
				local victimUids = {}
				for _, egg in w.data.eggs do
					table.insert(victimUids, egg.uid)
				end
				table.insert(victimUids, (w.data.incubators[1] or w.data.pets[1]).uid)
				H.landmarks.nearName = "SakuraIncubator"
				for _, uid in victimUids do
					H.client(thief, "PlaceEgg", uid, x, z)
					H.client(thief, "PickUpPlacedEgg", uid)
					H.client(thief, "SkipGrowth", uid, "all")
					H.client(thief, "SakuraOffer", uid)
					H.client(thief, "SellPlant", uid)
					H.advance(0.6)
				end
				T.eq(sig(), start, "남이 내 uid 로 보내도 내 것은 그대로")
				T.eq(#tdata.eggs, 0, "도둑의 가방에 아무것도 안 생김")
				T.eq(#tdata.incubators, 0)
				T.eq(#tdata.pets, 0)
				T.eq(tdata.money, 1e9, "도둑의 코인 그대로")
				-- 산 씨앗 표시가 그대로
				local bought = countBought(w.data)
				T.eq(bought, 2)
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	-- 경비 세상 (진짜 EggService + 진짜 GuardianService — 경비 몸은 가짜 Humanoid 라 스스로 안 걸음)
	------------------------------------------------------------------
	local ALL_ZONES = {}
	for _, b in Biomes.list do
		table.insert(ALL_ZONES, b.id)
	end

	local function guardWorld(H)
		local w = { H = H }
		w.EggService = H.server("Services/EggService")
		w.EggService.start()
		w.GuardianService = H.server("Services/GuardianService")
		w.GuardianService.start()
		w.SpeedService = H.server("Services/SpeedService")
		H.setPhase("Intermission", 1)
		H.setPhase("Day", 1)
		H.advance(0.3)
		return w
	end

	local function newRunner(H, userId, name)
		local p = H.newPlayer(userId, name)
		local session, data = H.login(p)
		session.plotIndex = 1
		session.moveExemptUntil = H.clock() + 1e7
		H.spawn(p, 0, 3, 0)
		return p, session, data
	end

	local function nestEgg(H, biomeId, skip)
		local n = 0
		for _, part in H.map.folders.Eggs.children do
			if part:GetAttribute("BiomeId") == biomeId and part:GetAttribute("EggState") == "Nest" then
				n += 1
				if n > (skip or 0) then
					return part
				end
			end
		end
		return nil
	end

	local function pickUpRaw(H, p, part)
		H.teleport(p, part.Position.X, part.Position.Y + 1, part.Position.Z)
		part:FindFirstChild("StealPrompt").Triggered:Fire(p)
	end

	local function guardModel(H, biomeId)
		for _, model in H.map.folders.Guardians.children do
			if model:GetAttribute("BiomeId") == biomeId and not model.destroyed then
				return model
			end
		end
		return nil
	end

	local function humanoidOf(model)
		for _, child in model.children do
			if child.ClassName == "Humanoid" then
				return child
			end
		end
		return nil
	end

	local function threshold(biomeId)
		return Biomes.get(biomeId).guardSpeed * Config.GUARD_CHASE_MARGIN
	end

	local function setCarrySpeed(w, p, session, data, target)
		data.speed = target / (1 - session.carryPenalty)
		w.SpeedService.refresh(p)
	end

	local function nearGuard(H, p, id, dx, dz)
		local home = MapLayout.guardHome(id)
		H.teleport(p, home.x + dx, 3, home.z + (dz or 0))
	end

	local settle = Config.RAGDOLL_SECONDS + 3

	------------------------------------------------------------------
	T.suite("K8 둥지에서 집고 경비 몸 위에 서도 WAKE 전까지 안 잡힘 · WAKE 뒤 첫 틱에 잡힘")

	T.test(
		"21구역 × 속도 3종 (느림 · 빠름 · 0): 둥지에서 집자마자 경비 몸 위(거리 0)로 가도 WAKE 전까지는 Caught 0 · State 가 Chase 로 안 바뀜(첫 틱 뒤로는 Alert) · TargetUserId 0 · WAKE 가 지난 첫 틱(WAKE ~ WAKE + 한 틱)에 한 번 잡힘 · 구역 안이니 씨앗은 둥지로 · 서버 warn 0",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9901, "Wake")
				for _, id in ALL_ZONES do
					local model = guardModel(H, id)
					local thr = threshold(id)
					for _, class in { { "느림", thr * 0.4 }, { "빠름", thr * 1.05 }, { "0", 0 } } do
						local tag = id .. " " .. class[1]
						local part = nestEgg(H, id)
						pickUpRaw(H, p, part)
						setCarrySpeed(w, p, session, data, class[2])
						nearGuard(H, p, id, 0, 0)
						local t0 = H.clock()
						local before = #H.sent(p, "Caught")
						local caughtAt
						while H.clock() - t0 < WAKE + 0.2 do
							H.advance(0.01)
							local elapsed = H.clock() - t0
							if not caughtAt and #H.sent(p, "Caught") > before then
								caughtAt = elapsed
							end
							if elapsed < WAKE - 0.005 then
								T.eq(#H.sent(p, "Caught"), before, tag .. string.format(": %.2f초에 잡힘", elapsed))
								T.truthy(
									model:GetAttribute("State") ~= "Chase",
									tag .. ": 느낌표 동안 State Chase"
								)
								T.eq(model:GetAttribute("TargetUserId"), 0, tag .. ": 느낌표 동안 대상 없음")
								if elapsed >= ALERT_BY then
									T.eq(
										model:GetAttribute("State"),
										"Alert",
										tag .. string.format(": %.2f초에 State", elapsed)
									)
								end
							end
						end
						T.truthy(
							caughtAt ~= nil and caughtAt >= WAKE - 1e-6 and caughtAt <= WAKE + TICK + 0.02,
							tag .. ": WAKE 뒤 첫 틱에 잡힘 " .. tostring(caughtAt)
						)
						T.eq(#H.sent(p, "Caught"), before + 1, tag .. ": 한 번만")
						T.eq(part:GetAttribute("EggState"), "Nest", tag .. ": 구역 안 = 둥지로")
						H.advance(settle)
						T.eq(#H.sent(p, "Caught"), before + 1, tag .. ": 또 안 잡힘")
						T.eq(humanoidOf(model).WalkSpeed ~= nil, true)
					end
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("K9 시간으로 잡히는 길이 다시 생기지 않음")

	T.test(
		"21구역 × (도망 못 침 · 도망 침): WAKE 가 지난 뒤 잡힘 거리 + 0.3 밖에서 60초가 지나도 Caught 0 · 씨앗 계속 Carried · 경비 WalkSpeed 는 구역 고정 추격 속도 그대로(느려지지도 빨라지지도 않음) · 도망 못 치는 사람이 대상이 되어 쫓기는 중 · 거리 안으로 들어가야만 그 틱에 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9911, "Slow")
				local SpeedMath = Loader.require(S .. "SpeedMath")
				for _, id in ALL_ZONES do
					local model = guardModel(H, id)
					local reach = model:GetAttribute("CatchDistance")
					local humanoid = humanoidOf(model)
					local chase = SpeedMath.guardChaseSpeed(Biomes.get(id).guardSpeed)
					for _, class in
						{ { "도망 못 침", threshold(id) * 0.4 }, { "도망 침", threshold(id) * 1.05 } }
					do
						local tag = id .. " " .. class[1]
						local part = nestEgg(H, id)
						pickUpRaw(H, p, part)
						setCarrySpeed(w, p, session, data, class[2])
						nearGuard(H, p, id, reach + 0.3, 0)
						local before = #H.sent(p, "Caught")
						H.advance(WAKE + 0.3) -- 깨어남이 끝남
						local minWs, maxWs = math.huge, 0
						for _ = 1, 240 do -- 60초
							H.advance(0.25)
							minWs = math.min(minWs, humanoid.WalkSpeed)
							maxWs = math.max(maxWs, humanoid.WalkSpeed)
						end
						T.eq(#H.sent(p, "Caught"), before, tag .. ": 60초가 지나도 안 닿았으면 안 잡힘")
						T.eq(part:GetAttribute("EggState"), "Carried", tag)
						T.eq(model:GetAttribute("TargetUserId"), p.UserId, tag .. ": 계속 쫓음")
						T.near(minWs, chase, 1e-9, tag .. ": 한 번도 느려지지 않음")
						T.near(maxWs, chase, 1e-9, tag .. ": 한 번도 빨라지지 않음 (돌진 없음)")
						nearGuard(H, p, id, reach - 0.3, 0)
						H.advance(0.2)
						T.eq(#H.sent(p, "Caught"), before + 1, tag .. ": 닿으면 그 틱에 잡힘")
						T.eq(part:GetAttribute("EggState"), "Nest", tag)
						H.advance(settle)
					end
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("K10 지연이 다시 생기지 않음 · 각자 자기 WAKE")

	T.test(
		"바닥에서 주우면 지연 없음: 숲 씨앗을 집어 (둥지) 구역 밖(허브)으로 나가 WAKE 가 지난 뒤 내려놓고(바닥, 5초 뒤 둥지로) → 바로 다시 줍고 경비 위에 서면 첫 틱(0.12초)에 잡힘 (느낌표 없음) · 집은 지 0.1초 만에 내려놓았다 다시 주워도 새 WAKE 가 안 생김 · 남이 떨어뜨린 것을 B 가 주워도 지연 없음 · 구역 안에서 내려놓아 둥지로 돌아간 씨앗을 다시 집으면 새 WAKE (정상 규칙)",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local a, sa, da = newRunner(H, 9921, "A")
				local b, sb, db = newRunner(H, 9922, "B")
				local id = "forest"
				local model = guardModel(H, id)
				local hubX, hubZ = H.hubSpot()
				local function snapshotCaught(p)
					return #H.sent(p, "Caught")
				end
				-- (1) A: 집고 → 구역 밖(허브)으로 → WAKE + 0.2초 뒤 내려놓음 → 다시 주움 → 경비 위
				local part = nestEgg(H, id)
				pickUpRaw(H, a, part)
				setCarrySpeed(w, a, sa, da, threshold(id) * 0.4)
				T.truthy(w.EggService.getCarried(a).stolenAt ~= nil, "둥지에서 집음 → 지연 시각")
				H.teleport(a, hubX, 3, hubZ)
				H.advance(WAKE + 0.2)
				w.EggService.dropEgg(a)
				T.eq(part:GetAttribute("EggState"), "Dropped", "구역 밖: 바닥")
				H.advance(1)
				pickUpRaw(H, a, part)
				T.eq(w.EggService.getCarried(a).stolenAt, nil, "바닥에서 주움 = 지연 없음")
				nearGuard(H, a, id, 0, 0)
				local before = snapshotCaught(a)
				H.advance(0.15)
				T.eq(snapshotCaught(a), before + 1, "첫 틱에 잡힘 (WAKE 안 기다림)")
				H.advance(settle)
				-- (2) 집은 지 0.1초 만에 허브에서 내려놓고 0.1초 뒤 다시 주워도 새 지연 없음
				part = nestEgg(H, id)
				pickUpRaw(H, a, part)
				local t0 = H.clock() -- 처음 집은 때
				setCarrySpeed(w, a, sa, da, threshold(id) * 0.4)
				H.advance(0.05)
				H.teleport(a, hubX, 3, hubZ)
				w.EggService.dropEgg(a)
				T.eq(part:GetAttribute("EggState"), "Dropped")
				H.advance(0.05)
				pickUpRaw(H, a, part)
				T.eq(w.EggService.getCarried(a).stolenAt, nil)
				nearGuard(H, a, id, 0, 0)
				before = snapshotCaught(a)
				H.advance(TICK + 0.01)
				T.eq(snapshotCaught(a), before + 1, "한 틱 만에 잡힘 (새 WAKE 없음)")
				T.truthy(
					H.clock() - t0 < WAKE,
					"처음 집은 뒤 WAKE 가 안 지났는데 잡힘 " .. (H.clock() - t0)
				)
				H.advance(settle)
				-- (3) A 가 허브에서 떨어뜨린 씨앗을 B 가 주움
				part = nestEgg(H, id)
				pickUpRaw(H, a, part)
				H.teleport(a, hubX, 3, hubZ)
				w.EggService.dropEgg(a)
				T.eq(part:GetAttribute("EggState"), "Dropped")
				pickUpRaw(H, b, part)
				T.eq(w.EggService.getCarried(b).stolenAt, nil, "남이 떨어뜨린 것을 주움 = 지연 없음")
				setCarrySpeed(w, b, sb, db, threshold(id) * 0.4)
				nearGuard(H, b, id, 0, 0)
				before = snapshotCaught(b)
				H.advance(0.15)
				T.eq(snapshotCaught(b), before + 1, "B 도 첫 틱에 잡힘")
				H.advance(settle)
				-- (4) 정상 규칙: 구역 안에서 내려놓아 둥지로 돌아간 씨앗을 다시 집으면 새 WAKE
				part = nestEgg(H, id)
				pickUpRaw(H, a, part)
				setCarrySpeed(w, a, sa, da, threshold(id) * 0.4)
				H.advance(WAKE * 0.6) -- 깨어나기 전에 (닿는 둥지에서 안 잡히게) 내려놓음
				w.EggService.dropEgg(a)
				T.eq(part:GetAttribute("EggState"), "Nest", "구역 안: 바로 둥지")
				pickUpRaw(H, a, part)
				local again = w.EggService.getCarried(a)
				T.truthy(again ~= nil and again.stolenAt ~= nil, "둥지에서 다시 집음 = 새 지연")
				T.near(again.stolenAt, H.clock(), 1e-6)
				nearGuard(H, a, id, 0, 0)
				before = snapshotCaught(a)
				H.advance(WAKE - 0.01)
				T.eq(snapshotCaught(a), before, "새 WAKE 안에는 안 잡힘")
				T.eq(model:GetAttribute("State"), "Alert", "다시 집으면 다시 느낌표")
				H.advance(TICK + 0.05)
				T.eq(snapshotCaught(a), before + 1, "WAKE 뒤 잡힘")
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
				T.eq(model:GetAttribute("TargetUserId"), 0)
			end)
		end
	)

	T.test(
		"세 사람이 WAKE 의 0.4배 간격으로 겹치게 훔침 (21구역): 각자 자기 둥지 집은 시각 + WAKE 에 잡힘 (A · B · C 차례로) · A 가 잡힐 때 B·C 는 아직 안 잡힘 · 순서가 뒤바뀌지 않음",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local people = {}
				local gapSteps = math.max(1, math.floor(WAKE * 40 + 0.5)) -- WAKE × 0.4 초 (0.01 단위)
				for i = 1, 3 do
					local p, session, data = newRunner(H, 9930 + i, "P" .. i)
					people[i] = { p = p, session = session, data = data }
				end
				for _, id in ALL_ZONES do
					local thr = threshold(id)
					local caughtAt = {}
					local pickedAt = {}
					local t0 = H.clock()
					local function note()
						for i, who in people do
							if not caughtAt[i] and #H.sent(who.p, "Caught") > who.before then
								caughtAt[i] = H.clock()
							end
						end
					end
					for _, who in people do
						who.before = #H.sent(who.p, "Caught")
					end
					for i, who in people do
						local part = nestEgg(H, id)
						pickUpRaw(H, who.p, part)
						pickedAt[i] = H.clock()
						setCarrySpeed(w, who.p, who.session, who.data, thr * 0.4)
						nearGuard(H, who.p, id, 0, 0)
						-- 다음 사람이 훔치기 전까지 GAP (WAKE 의 0.4배 — 세 사람의 느낌표가 겹침. 그동안 감시)
						if i < 3 then
							for _ = 1, gapSteps do
								H.advance(0.01)
								note()
							end
						end
					end
					while H.clock() - t0 < 2 * gapSteps * 0.01 + WAKE + 0.5 do
						H.advance(0.01)
						note()
					end
					for i = 1, 3 do
						local tag = id .. " P" .. i
						T.truthy(caughtAt[i] ~= nil, tag .. ": 잡힘")
						local wait = caughtAt[i] - pickedAt[i]
						T.truthy(
							wait >= WAKE - 1e-6 and wait <= WAKE + TICK + 0.02,
							tag .. string.format(": 집은 뒤 %.2f초에 잡힘", wait)
						)
						if i > 1 then
							T.truthy(caughtAt[i] > caughtAt[i - 1], tag .. ": 앞 사람보다 늦게 잡힘")
						end
					end
					H.advance(settle)
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("K11 지연 중에도 경계(zMax) 즉시 잡힘 그대로 · 밤 · 허브")

	T.test(
		"21구역: 도망 못 치는 사람이 둥지에서 방금 훔치고 (WAKE 안에) 다음 구역 경계(zMax)를 넘으면 0.25초 안에 잡힘 (씨앗은 둥지로) · 도망 칠 수 있는 사람은 넘어도 안 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9941, "Border")
				for _, id in ALL_ZONES do
					local range = MapLayout.biome(id)
					local thr = threshold(id)
					-- 도망 못 침
					local part = nestEgg(H, id)
					pickUpRaw(H, p, part)
					setCarrySpeed(w, p, session, data, thr * 0.4)
					local before = #H.sent(p, "Caught")
					local t0 = H.clock()
					H.teleport(p, 0, 3, range.zMax + 1)
					H.advance(TICK + 0.05)
					T.eq(#H.sent(p, "Caught"), before + 1, id .. ": 경계를 넘자 바로 잡힘")
					T.truthy(H.clock() - t0 < WAKE, id .. ": WAKE 안에 " .. (H.clock() - t0))
					T.eq(part:GetAttribute("EggState"), "Nest", id .. ": 씨앗은 둥지로")
					H.advance(settle)
					-- 도망 침
					part = nestEgg(H, id)
					pickUpRaw(H, p, part)
					setCarrySpeed(w, p, session, data, thr * 1.5)
					before = #H.sent(p, "Caught")
					H.teleport(p, 0, 3, range.zMax + 1)
					H.advance(0.5)
					T.eq(#H.sent(p, "Caught"), before, id .. ": 도망 칠 수 있으면 넘어도 안 잡힘")
					T.eq(part:GetAttribute("EggState"), "Carried")
					w.EggService.dropEgg(p)
					H.advance(settle)
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	T.test(
		"지연 중 허브로 들어가거나 밤이 됨: 허브에선 안 쫓고 WAKE 가 지나도 안 잡힘 (경비 Sleeping — 느낌표 없음 · 대상 0) → 구역으로 돌아와 닿으면 (지연은 집은 때부터 세므로 이미 끝남) 그 틱에 잡힘 · 지연이 끝나기 전에 돌아오면 남은 시간만 기다림 (다시 Alert) · 밤에는 안 잡힘 (느낌표도 없음) · 밤이 지나 새 낮에 다시 훔치면 새 WAKE · 서버 warn 0",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9951, "Hubber")
				local id = "forest"
				local model = guardModel(H, id)
				local hubX, hubZ = H.hubSpot()
				-- (1) 허브로 갔다가 WAKE 가 지난 뒤 돌아옴
				local part = nestEgg(H, id)
				pickUpRaw(H, p, part)
				setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
				H.teleport(p, hubX, 3, hubZ)
				H.advance(WAKE + 0.5)
				T.eq(model:GetAttribute("TargetUserId"), 0)
				H.advance(1.5)
				T.eq(#H.sent(p, "Caught"), 0, "허브에서는 안 잡힘")
				T.eq(model:GetAttribute("State"), "Sleeping", "허브에서는 느낌표도 없음")
				nearGuard(H, p, id, 0, 0)
				H.advance(0.15)
				T.eq(#H.sent(p, "Caught"), 1, "돌아와 닿자 바로 잡힘 (지연은 이미 끝)")
				H.advance(settle)
				-- (2) 지연 중에 허브로 갔다가 지연이 끝나기 전에 돌아옴 (허브 한 틱 + 돌아와서 한 틱 = 2 × (TICK + 0.01) < WAKE)
				T.truthy(
					2 * (TICK + 0.01) < WAKE - 0.05,
					"시험 전제: 허브 한 틱 + 돌아와 한 틱이 WAKE 안에 들어감"
				)
				part = nestEgg(H, id)
				pickUpRaw(H, p, part)
				setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
				local t0 = H.clock()
				H.teleport(p, hubX, 3, hubZ)
				H.advance(TICK + 0.01)
				T.eq(model:GetAttribute("State"), "Sleeping", "허브에 있는 동안은 느낌표 없음")
				nearGuard(H, p, id, 0, 0)
				H.advance(TICK + 0.01)
				T.eq(#H.sent(p, "Caught"), 1, "돌아왔지만 아직 WAKE 전 — 안 잡힘")
				T.eq(model:GetAttribute("State"), "Alert", "돌아오면 남은 시간 동안 다시 느낌표")
				while H.clock() - t0 < WAKE - 0.02 do
					H.advance(0.01)
				end
				T.eq(#H.sent(p, "Caught"), 1)
				H.advance(TICK + 0.1)
				T.eq(#H.sent(p, "Caught"), 2, "WAKE 가 지난 첫 틱에 잡힘")
				H.advance(settle)
				-- (3) 지연 중 밤이 됨
				part = nestEgg(H, id)
				pickUpRaw(H, p, part)
				setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
				nearGuard(H, p, id, 0, 0)
				H.advance(WAKE * 0.4)
				T.eq(model:GetAttribute("State"), "Alert", "밤 직전: 느낌표 중")
				H.setPhase("Night", 1)
				H.advance(5)
				T.eq(#H.sent(p, "Caught"), 2, "밤에는 경비가 안 잡음")
				T.truthy(model:GetAttribute("State") ~= "Chase")
				T.eq(model:GetAttribute("State"), "Sleeping", "밤에는 느낌표도 없음")
				T.eq(model:GetAttribute("TargetUserId"), 0)
				-- 밤이 지나고 새 낮: 씨앗이 어디 있든 새로 훔치면 새 WAKE
				H.setPhase("Intermission", 2)
				H.setPhase("Day", 2)
				H.advance(0.5)
				if w.EggService.getCarried(p) then
					w.EggService.dropEgg(p)
				end
				H.advance(settle)
				part = nestEgg(H, id)
				T.truthy(part ~= nil, "새 낮에 둥지 씨앗이 있음")
				pickUpRaw(H, p, part)
				setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
				nearGuard(H, p, id, 0, 0)
				local before = #H.sent(p, "Caught")
				H.advance(WAKE - 0.01)
				T.eq(#H.sent(p, "Caught"), before, "새 낮에도 WAKE 지연")
				H.advance(TICK + 0.05)
				T.eq(#H.sent(p, "Caught"), before + 1)
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("K12 GuardLogic.isWaking 경계 (NaN · nil · 미래 시각)")

	T.test(
		"순수 함수 경계: nil · NaN 은 바로 깸(false) · WAKE − 0.01 느낌표 중 / WAKE · WAKE + 0.01 · WAKE + 한 틱 · 100 깸 · -inf 는 깸 · now 나 wakeSeconds 가 NaN 이면 깸 · wakeSeconds 0 · 음수 = 안 잠 · now 가 inf 면 깸",
		function()
			local nan = 0 / 0
			local t = 1000
			T.falsy(GuardLogic.isWaking(nil, t, WAKE), "nil")
			T.falsy(GuardLogic.isWaking(nan, t, WAKE), "NaN 집은 시각")
			T.falsy(GuardLogic.isWaking(t, nan, WAKE), "NaN 지금")
			T.falsy(GuardLogic.isWaking(t, t + 1, nan), "NaN wake")
			T.truthy(GuardLogic.isWaking(t, t, WAKE), "0초: 느낌표 중")
			T.truthy(GuardLogic.isWaking(t, t + WAKE - 0.01, WAKE), "WAKE − 0.01")
			T.truthy(GuardLogic.isWaking(t, t + WAKE - 0.001, WAKE), "WAKE − 0.001")
			T.falsy(GuardLogic.isWaking(t, t + WAKE, WAKE), "WAKE")
			T.falsy(GuardLogic.isWaking(t, t + WAKE + 0.01, WAKE), "WAKE + 0.01")
			T.falsy(GuardLogic.isWaking(t, t + WAKE + TICK, WAKE), "WAKE + 한 틱")
			T.falsy(GuardLogic.isWaking(t, t + 100, WAKE), "100")
			T.falsy(GuardLogic.isWaking(-math.huge, t, WAKE), "-inf")
			T.falsy(GuardLogic.isWaking(t, math.huge, WAKE), "now inf")
			T.falsy(GuardLogic.isWaking(t, t + 1, 0), "wake 0")
			T.falsy(GuardLogic.isWaking(t, t + 1, -5), "wake 음수")
			T.falsy(GuardLogic.isWaking(0, 1e9, WAKE), "아주 큰 now")
		end
	)

	-- 미래 시각 = 영원히 자는 중 (stolenAt = 서버 os.clock 만 씀 — 클라가 닿을 길은 없지만 순수 함수는 방어하지 않음)
	T.test(
		"[K-1] stolenAt 이 미래 시각 · +inf 이면 영원히 안 깸 (isWaking 이 경과가 음수일 때를 안 거름)",
		function()
			local t = 1000
			T.falsy(
				GuardLogic.isWaking(t + 1e9, t + 100, WAKE),
				"미래 stolenAt 1e9 뒤 — 100초 지나도 자는 중이면 안 됨"
			)
			T.falsy(GuardLogic.isWaking(math.huge, t + 100, WAKE), "+inf")
			T.falsy(GuardLogic.isWaking(t + 5, t + 100, WAKE), "미래 5초")
		end
	)

	T.test(
		"[K-1 통합] 진짜 경비: 둥지 씨앗 egg.stolenAt 을 미래(+1e9)로 바꾸면 60초가 지나도 경비 몸 위에서 안 잡힘 (영원히 무적)",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9961, "Future")
				local id = "forest"
				local part = nestEgg(H, id)
				pickUpRaw(H, p, part)
				w.EggService.getCarried(p).stolenAt = H.clock() + 1e9
				setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
				nearGuard(H, p, id, 0, 0)
				local before = #H.sent(p, "Caught")
				H.advance(60)
				T.eq(#H.sent(p, "Caught"), before + 1, "60초 안에 잡혀야 함")
			end)
		end
	)

	T.test(
		"집은 시각이 NaN 이거나 nil 인 씨앗 (진짜 경비): 바로 평소 규칙 — 경비 몸 위에서 한 틱(0.12초) 안에 잡힘 (NaN 때문에 영원히 무적이 되지 않음) · 과거(아주 오래전) 시각도 바로 평소 규칙",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9971, "Nan")
				local id = "forest"
				for _, bad in { 0 / 0, -math.huge, -1e9, 0 } do
					local part = nestEgg(H, id)
					pickUpRaw(H, p, part)
					w.EggService.getCarried(p).stolenAt = bad
					setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
					nearGuard(H, p, id, 0, 0)
					local before = #H.sent(p, "Caught")
					H.advance(0.15)
					T.eq(#H.sent(p, "Caught"), before + 1, "stolenAt " .. tostring(bad) .. ": 바로 잡힘")
					H.advance(settle)
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite(
		"L 66번: 훔치면 바로 빨간 느낌표(State Alert) → WAKE 뒤 쫓아옴/잡힘 (사장님 2026-11-10)"
	)

	-- 느낌표 동안 (훔친 지 WAKE − 0.01 까지) 0.01초씩 지켜보며: State · 대상 · 잡힘 · 경비 걸음 명령(moves) 을 확인
	--   mode "멀리" = 경비 몸에서 잡힘 거리 + 0.3 (안 닿음) · "닿음" = 경비 몸 위
	local function stealAndWatchAlert(H, w, p, session, data, id, mode, tag)
		local model = guardModel(H, id)
		local humanoid = humanoidOf(model)
		local reach = model:GetAttribute("CatchDistance")
		local part = nestEgg(H, id)
		pickUpRaw(H, p, part)
		setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
		nearGuard(H, p, id, if mode == "닿음" then 0 else reach + 0.3, 0)
		local pos0 = model.PrimaryPart.Position
		local moves0 = humanoid.moves
		local before = #H.sent(p, "Caught")
		local t0 = H.clock()
		local alertAt
		while H.clock() - t0 < WAKE - 0.01 do
			H.advance(0.01)
			local elapsed = H.clock() - t0
			local state = model:GetAttribute("State")
			if state == "Alert" and not alertAt then
				alertAt = elapsed
			end
			if elapsed >= ALERT_BY then
				T.eq(state, "Alert", tag .. string.format(": %.2f초에 State", elapsed))
			end
			T.eq(model:GetAttribute("TargetUserId"), 0, tag .. ": 느낌표 동안 대상 없음")
			T.eq(
				#H.sent(p, "Caught"),
				before,
				tag .. string.format(": %.2f초에 잡힘 (느낌표 동안 안 잡힘)", elapsed)
			)
		end
		T.truthy(alertAt ~= nil and alertAt <= TICK + 0.011, tag .. ": 훔친 첫 틱에 Alert " .. tostring(alertAt))
		T.eq(humanoid.moves, moves0, tag .. ": 느낌표 동안 경비는 걸으라는 명령을 안 받음")
		local pos1 = model.PrimaryPart.Position
		T.eq(pos1.X, pos0.X, tag .. ": 경비 x 제자리")
		T.eq(pos1.Z, pos0.Z, tag .. ": 경비 z 제자리")
		return part, model, humanoid, moves0, before
	end

	T.test(
		"21구역 × (멀리 서 있음 · 경비 몸에 닿음): 둥지에서 훔친 첫 틱(한 틱 안)에 State Alert (대상 0 · 안 잡힘 · 경비 제자리 — MoveTo 안 부름) → WAKE 가 지나면 멀리 있는 사람은 Chase (그 사람이 대상 · 경비가 걷기 시작 · 안 잡힘) · 닿아 있는 사람은 그 틱에 한 번 잡힘 (씨앗은 둥지로) · 서버 warn 0",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9981, "Alert")
				for _, id in ALL_ZONES do
					for _, mode in { "멀리", "닿음" } do
						local tag = id .. " " .. mode
						local part, model, humanoid, moves0, before =
							stealAndWatchAlert(H, w, p, session, data, id, mode, tag)
						H.advance(TICK + 0.05) -- WAKE 를 지나 한 틱
						if mode == "멀리" then
							T.eq(model:GetAttribute("State"), "Chase", tag .. ": WAKE 뒤 쫓음")
							T.eq(model:GetAttribute("TargetUserId"), p.UserId, tag .. ": 그 사람이 대상")
							T.truthy(humanoid.moves > moves0, tag .. ": WAKE 뒤에는 걸으라는 명령을 받음")
							T.eq(#H.sent(p, "Caught"), before, tag .. ": 안 닿으면 안 잡힘")
							T.eq(part:GetAttribute("EggState"), "Carried", tag)
							w.EggService.dropEgg(p) -- 구역 안: 바로 둥지
						else
							T.eq(
								#H.sent(p, "Caught"),
								before + 1,
								tag .. ": WAKE 뒤 닿아 있으면 잡힘 (한 번)"
							)
							T.eq(part:GetAttribute("EggState"), "Nest", tag .. ": 구역 안 = 둥지로")
						end
						H.advance(settle)
					end
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)
end
