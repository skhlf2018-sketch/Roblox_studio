--!nocheck
--[[
	6판 "씨앗을 훔치세요" 정원·열매 테스트: FruitService (열매 맺기 · PickFruit · SellFruits · FeedFruit · 오프라인 열매)
	+ 정원 파트(GardenPlant Attribute) · 물 주기로 열매가 빨라짐.
	진짜 서비스 코드(FruitService, PetService, BaseService, Wallet, Snapshot) + 진짜 shared 규칙을 ServerHarness 위에서 (가상 시간).
	순수 규칙 경계(FruitRules.produce·가방·먹이기 확률)는 tests/rules_boundary.spec, 팔기 가격은 services_core.
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function world()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.Plants = H.shared("Data/Plants")
		w.Mutations = H.shared("Data/Mutations")
		w.Economy = H.shared("Economy")
		w.FruitRules = H.shared("FruitRules")
		w.EggPlacement = H.shared("EggPlacement")
		w.DataSchema = H.server("Logic/DataSchema")
		w.PetService = H.server("Services/PetService")
		w.FruitService = H.server("Services/FruitService")
		w.player = H.newPlayer(1001, "Gardener")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		w.FruitService.start() -- PickFruit·SellFruits·FeedFruit 처리기 + 1초 열매 틱
		w.PetService.start() -- SellPlant·PetPet(물 주기) 처리기
		return w
	end

	-- 정원 빈 격자 자리에 성체 하나 (열매 fruits 개 달린 채)
	local function addPlant(w, petId, opts)
		opts = opts or {}
		local player = opts.player or w.player
		local data = opts.data or w.data
		local taken = {}
		for _, r in data.pets do
			table.insert(taken, { x = r.x, z = r.z, size = r.size })
		end
		for _, r in data.incubators do
			table.insert(taken, { x = r.x, z = r.z, size = r.size })
		end
		local size = opts.size or "normal"
		local spot = w.EggPlacement.firstFreeGrid(size, taken)
		local record = {
			uid = w.DataSchema.newUid(data, "p"),
			petId = petId,
			size = size,
			mutations = opts.mutations or {},
			x = spot.x,
			z = spot.z,
			fruits = opts.fruits or 0,
			fruitProgress = opts.progress or 0,
		}
		assert(w.PetService.addPlant(player, record), "addPlant 실패")
		return record
	end

	-- 내 정원 가운데에 서기 (열매 따기·먹이기 거리 20 안)
	local function standInGarden(w, player, plotIndex)
		local pen = w.H.MapLayout.penRect(plotIndex or 1)
		w.H.spawn(player or w.player, (pen.xMin + pen.xMax) / 2, 3, (pen.zMin + pen.zMax) / 2)
	end

	local function standAtHubStall(w, player)
		local stall = w.H.MapLayout.hubSpots.sellStall
		w.H.spawn(player or w.player, stall.x, 3, stall.z)
	end

	local function standFar(w, player)
		local x, z = w.H.zoneSpot("forest")
		w.H.spawn(player or w.player, x, 3, z)
	end

	-- 그 Remote 로 이 사람에게 보낸 첫 인자 목록
	local function payloads(w, remoteName, player)
		local list = {}
		for _, args in w.H.sent(player or w.player, remoteName) do
			table.insert(list, args[1])
		end
		return list
	end

	local function dataUpdates(w, section, player)
		local list = {}
		for _, args in w.H.sent(player or w.player, "DataUpdate") do
			if args[1] == section then
				table.insert(list, args[2])
			end
		end
		return list
	end

	------------------------------------------------------------------
	T.suite("6판 정원: 열매 맺기 (FruitService 1초 틱)")

	T.test(
		"아기 데이지(30초 간격): 29초 0개 → 30초 1개 → 최대 5개에서 멈추고 시간도 안 쌓임, 바뀔 때 DataUpdate(pets)",
		function()
			local w = world()
			local daisy = addPlant(w, "sprout_daisy")
			T.eq(w.Economy.fruitInterval("sprout_daisy"), 30)
			w.H.clearSent()
			w.H.advance(29)
			T.eq(daisy.fruits, 0)
			T.eq(#dataUpdates(w, "pets"), 0, "열매 수가 안 바뀌면 안 보냄")
			w.H.advance(1.5)
			T.eq(daisy.fruits, 1)
			T.truthy(#dataUpdates(w, "pets") >= 1, "열매가 생기면 DataUpdate(pets)")
			w.H.advance(30 * 10)
			T.eq(daisy.fruits, w.Config.FRUIT_MAX_PER_PLANT, "최대 5")
			T.eq(daisy.fruitProgress, 0, "가득 차면 다음 열매 시간이 안 쌓임")
			T.eq(w.data.money, 0, "열매는 맺히기만 하고 코인은 안 들어옴 (자동 수입 없음)")
			w.H.uninstall()
		end
	)

	T.test(
		"열매는 밤에도 빠르기 그대로 (밤 30배는 씨앗 성장만), 식물마다 자기 간격",
		function()
			local w = world()
			local daisy = addPlant(w, "sprout_daisy") -- 30초
			local owl = addPlant(w, "owl_oak") -- 27초
			w.H.setPhase("Night")
			w.H.advance(28)
			T.eq(daisy.fruits, 0, "밤이라도 30초 전에는 안 맺힘")
			T.eq(owl.fruits, 1, "부엉이 참나무 27초")
			w.H.advance(3)
			T.eq(daisy.fruits, 1)
			w.H.uninstall()
		end
	)

	T.test(
		"GardenPlant 파트 Attribute: PlantUid·OwnerUserId·Stage adult·Fruits·FruitMax·FruitValue·FruitInterval (1초마다 맞춤)",
		function()
			local w = world()
			w.H.server("Services/BaseService").start()
			local plant = addPlant(w, "owl_oak", { size = "big", mutations = { "golden" } })
			w.H.advance(1.1)
			local part = nil
			for _, child in w.H.map.folders.Incubating.children do
				if child:GetAttribute("PlantUid") == plant.uid then
					part = child
				end
			end
			T.truthy(part, "GardenPlant 파트")
			T.eq(part:GetAttribute("OwnerUserId"), w.player.UserId)
			T.eq(part:GetAttribute("Stage"), "adult")
			T.eq(part:GetAttribute("PetId"), "owl_oak")
			T.eq(part:GetAttribute("FruitMax"), w.Config.FRUIT_MAX_PER_PLANT)
			T.eq(part:GetAttribute("FruitInterval"), 27)
			T.eq(part:GetAttribute("FruitValue"), 180 * 1.5 * 2, "열매 1개 값 = 180 × 큼 1.5 × 황금 2")
			T.eq(part:GetAttribute("Fruits"), 0)
			w.H.advance(27)
			T.eq(part:GetAttribute("Fruits"), 1, "열매가 맺히면 파트도")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("6판 정원: PickFruit (열매 따기 → 열매 가방)")

	T.test(
		"내 정원 20 안에서 uid 하나: 열매 전부 가방으로, 값 = 크기·돌연변이 반영, FruitPicked·DataUpdate·Attribute",
		function()
			local w = world()
			local plant = addPlant(w, "sprout_daisy", { size = "big", mutations = { "golden" }, fruits = 3 })
			standInGarden(w)
			w.H.client(w.player, "PickFruit", plant.uid)
			T.eq(plant.fruits, 0)
			local stack = w.data.fruits.sprout_daisy
			T.truthy(stack, "가방 칸")
			T.eq(stack.count, 3)
			T.eq(stack.value, 3 * 10 * 1.5 * 2, "10 × 1.5 × 2 = 30 코인짜리 3개")
			local picked = payloads(w, "FruitPicked")
			T.eq(#picked, 1)
			T.eq(picked[1].plantUid, plant.uid)
			T.eq(picked[1].petId, "sprout_daisy")
			T.eq(picked[1].count, 3)
			T.eq(picked[1].value, 90)
			T.eq(#dataUpdates(w, "fruits"), 1)
			T.eq(dataUpdates(w, "fruits")[1].fruits, w.data.fruits)
			T.eq(w.player.attrs.FruitCount, 3)
			T.eq(w.player.attrs.FruitBagValue, 90)
			T.eq(w.data.stats.fruitsPicked, 3)
			T.eq(w.data.money, 0, "따기만 해서는 코인 없음")
			w.H.uninstall()
		end
	)

	T.test(
		'"all": 열매가 있는 성체마다 FruitPicked 한 번, 같은 식물끼리 한 칸 (값은 딸 때 값의 합)',
		function()
			local w = world()
			local a = addPlant(w, "sprout_daisy", { fruits = 2 })
			local b = addPlant(w, "sprout_daisy", { fruits = 1, mutations = { "rainbow" } })
			local c = addPlant(w, "owl_oak", { fruits = 0 })
			standInGarden(w)
			w.H.client(w.player, "PickFruit", "all")
			T.eq(a.fruits + b.fruits + c.fruits, 0)
			T.eq(#payloads(w, "FruitPicked"), 2, "열매 없는 부엉이 참나무는 안 보냄")
			T.eq(w.data.fruits.sprout_daisy.count, 3)
			T.eq(w.data.fruits.sprout_daisy.value, 2 * 10 + 10 * 2.5)
			T.eq(w.data.fruits.owl_oak, nil)
			T.eq(w.FruitRules.bagCount(w.data.fruits), 3)
			w.H.uninstall()
		end
	)

	T.test(
		"멀면 거부(알림), 열매 없으면 안내, 남의 식물·자라는 씨앗·이상한 인자는 조용히 무시",
		function()
			local w = world()
			local plant = addPlant(w, "sprout_daisy", { fruits = 2 })
			standFar(w)
			w.H.client(w.player, "PickFruit", plant.uid)
			T.eq(plant.fruits, 2, "구역 한가운데에서는 못 땀")
			T.truthy(w.H.hasNotify(w.player, "error", "정원 가까이"))
			w.H.client(w.player, "PickFruit", "all")
			T.eq(plant.fruits, 2)
			standInGarden(w)
			local other = w.H.newPlayer(1002, "Other")
			local otherSession, otherData = w.H.login(other)
			otherSession.plotIndex = 2
			otherData.nextUid = 500 -- uid 가 안 겹치게
			local theirs = addPlant(w, "owl_oak", { player = other, data = otherData, fruits = 4 })
			w.H.clearSent()
			for _, bad in { theirs.uid, "i1", "p999", 42, nil, {}, string.rep("x", 200), "../x" } do
				w.H.client(w.player, "PickFruit", bad)
			end
			T.eq(theirs.fruits, 4, "남의 식물 열매는 안 따짐")
			T.eq(#payloads(w, "FruitPicked"), 0)
			T.eq(w.FruitRules.bagCount(w.data.fruits), 0)
			w.H.advance(1) -- 레이트 리밋 회복 (10 / 5)
			plant.fruits = 0
			w.H.client(w.player, "PickFruit", plant.uid)
			T.truthy(w.H.hasNotify(w.player, "info", "아직 딸 열매가 없어요"))
			w.H.uninstall()
		end
	)

	T.test("열매 가방 300: 자리만큼만 따고 나머지는 식물에 남음, 가득 차면 알림", function()
		local w = world()
		local max = w.Config.FRUIT_BAG_MAX
		T.eq(max, 300)
		w.data.fruits.owl_oak = { count = max - 2, value = (max - 2) * 180 }
		local plant = addPlant(w, "sprout_daisy", { fruits = 5 })
		standInGarden(w)
		w.H.client(w.player, "PickFruit", plant.uid)
		T.eq(w.FruitRules.bagCount(w.data.fruits), max)
		T.eq(plant.fruits, 3, "2개만 들어감")
		T.eq(w.data.fruits.sprout_daisy.count, 2)
		w.H.client(w.player, "PickFruit", plant.uid)
		T.eq(plant.fruits, 3)
		T.truthy(w.H.hasNotify(w.player, "error", "열매 가방이 가득"))
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("6판 정원: SellFruits (판매 가판대에서 열매 가방 전부 팔기)")

	T.test(
		"허브 판매 가판대 14 안: 가방 값 그대로 코인, 가방 비움, FruitsSold·Notify·신호·Attribute",
		function()
			local w = world()
			local soldEvents = {}
			w.FruitService.sold:connect(function(player, count, coins)
				table.insert(soldEvents, { player = player, count = count, coins = coins })
			end)
			w.data.fruits.sprout_daisy = { count = 3, value = 90 }
			w.data.fruits.owl_oak = { count = 2, value = 360 }
			standAtHubStall(w)
			w.H.client(w.player, "SellFruits")
			T.eq(w.data.money, 450)
			T.eq(w.player.attrs.Money, 450)
			T.eq(next(w.data.fruits), nil, "가방이 빔")
			T.eq(w.player.attrs.FruitCount, 0)
			T.eq(w.player.attrs.FruitBagValue, 0)
			local sold = payloads(w, "FruitsSold")
			T.eq(#sold, 1)
			T.eq(sold[1].count, 5)
			T.eq(sold[1].coins, 450)
			T.truthy(w.H.hasNotify(w.player, "success", "열매 5개를 팔았어요"))
			T.eq(#soldEvents, 1)
			T.eq(soldEvents[1].coins, 450)
			T.eq(w.data.stats.fruitsSold, 5)
			w.H.uninstall()
		end
	)

	T.test("내 베이스 판매 가판대에서도 됨, 코인 2배 게임패스면 × 2", function()
		local w = world()
		local spot = w.H.MapLayout.plot(1).sellStall
		w.H.spawn(w.player, spot.x, 3, spot.z)
		w.session.hasMoneyPass = true
		w.data.fruits.sprout_daisy = { count = 1, value = 10 }
		w.H.client(w.player, "SellFruits")
		T.eq(w.data.money, 20)
		T.eq(payloads(w, "FruitsSold")[1].coins, 20)
		w.H.uninstall()
	end)

	T.test("가판대에서 멀면 거부(가방 그대로), 빈 가방이면 안내, 인자는 무시", function()
		local w = world()
		w.data.fruits.sprout_daisy = { count = 2, value = 20 }
		standInGarden(w)
		w.H.client(w.player, "SellFruits")
		T.eq(w.data.fruits.sprout_daisy.count, 2)
		T.eq(w.data.money, 0)
		T.truthy(w.H.hasNotify(w.player, "error", "판매 가판대 가까이"))
		standAtHubStall(w)
		w.H.client(w.player, "SellFruits", "가짜 인자", 1e30)
		T.eq(w.data.money, 20, "인자는 안 봄")
		w.H.advance(2) -- 레이트 리밋 회복
		w.H.client(w.player, "SellFruits")
		T.truthy(w.H.hasNotify(w.player, "info", "팔 열매가 없어요"))
		T.eq(#payloads(w, "FruitsSold"), 1)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("6판 정원: FeedFruit (열매 먹이기 → 확률로 돌연변이)")

	T.test(
		"먹이면 열매 1개가 줄고 FeedResult·Notify, 붙은 돌연변이는 식물 기록에 (조합 규칙 지킴)",
		function()
			local w = world()
			local plant = addPlant(w, "sprout_daisy")
			w.data.fruits.crystal_snowdrop = { count = 50, value = 50 * 8000 }
			standInGarden(w)
			local got = nil
			for _ = 1, 50 do
				local before = w.data.fruits.crystal_snowdrop.count
				w.H.client(w.player, "FeedFruit", plant.uid, "crystal_snowdrop")
				w.H.advance(1) -- 레이트 리밋 (5 / 2)
				T.eq(w.data.fruits.crystal_snowdrop.count, before - 1, "먹일 때마다 1개")
				local results = payloads(w, "FeedResult")
				local last = results[#results]
				T.eq(last.plantUid, plant.uid)
				T.eq(last.fruitId, "crystal_snowdrop")
				if last.mutation then
					got = last.mutation
					break
				end
			end
			T.truthy(got, "50번 안에 뭔가 붙음 (한 번 약 39%)")
			T.truthy(table.find(plant.mutations, got), "식물에 붙음")
			T.truthy(w.Economy.isValidMutationSet(plant.mutations))
			T.truthy(w.H.hasNotify(w.player, "success", "돌연변이가 생겼어요"))
			T.truthy(w.data.stats.fruitsFed >= 1)
			w.H.uninstall()
		end
	)

	T.test(
		"눈 구역 열매(수정 설강화)는 얼음이 다른 원소보다 훨씬 자주 (그 구역 열매 ×3)",
		function()
			local w = world()
			local plant = addPlant(w, "sprout_daisy")
			standInGarden(w)
			local counts = {}
			for _ = 1, 400 do
				plant.mutations = {}
				w.data.fruits.crystal_snowdrop = { count = 1, value = 8000 }
				w.FruitService.feed(w.player, plant.uid, "crystal_snowdrop")
				local id = plant.mutations[1]
				if id then
					counts[id] = (counts[id] or 0) + 1
				end
			end
			local frozen, burning = counts.frozen or 0, counts.burning or 0
			-- 기대: 얼음 0.05 × 3 × 1.4(전설 보너스) = 21% ≈ 84번, 불 7% ≈ 28번
			T.truthy(frozen > burning * 1.5, "얼음 " .. frozen .. " / 불 " .. burning)
			T.truthy(frozen > 50 and frozen < 130, "얼음 " .. frozen)
			T.eq(counts.silver, nil, "실버는 먹이기로 안 나옴")
			w.H.uninstall()
		end
	)

	T.test(
		"붙을 수 있는 것만: 황금은 무지개로만 바뀌고 실버로 안 내려감, 원소가 있으면 다른 원소 안 붙음",
		function()
			local w = world()
			local plant = addPlant(w, "sprout_daisy")
			standInGarden(w)
			for _ = 1, 300 do
				plant.mutations = { "golden", "frozen" }
				w.data.fruits.crystal_snowdrop = { count = 1, value = 8000 }
				w.FruitService.feed(w.player, plant.uid, "crystal_snowdrop")
				T.truthy(w.Economy.isValidMutationSet(plant.mutations), table.concat(plant.mutations, ","))
				T.falsy(table.find(plant.mutations, "silver"))
				T.falsy(table.find(plant.mutations, "burning"))
				T.falsy(table.find(plant.mutations, "shocked"))
				T.eq(#plant.mutations, 2)
			end
			w.H.uninstall()
		end
	)

	T.test(
		"더 붙을 게 없는 식물(무지개 + 원소)이면 거부 — 열매 그대로, FeedResult 없음",
		function()
			local w = world()
			local plant = addPlant(w, "sprout_daisy", { mutations = { "rainbow", "burning" } })
			w.data.fruits.crystal_snowdrop = { count = 3, value = 24000 }
			standInGarden(w)
			w.H.client(w.player, "FeedFruit", plant.uid, "crystal_snowdrop")
			T.eq(w.data.fruits.crystal_snowdrop.count, 3)
			T.eq(#payloads(w, "FeedResult"), 0)
			T.truthy(w.H.hasNotify(w.player, "error", "더 생길 돌연변이가 없어요"))
			w.H.uninstall()
		end
	)

	T.test(
		"멀면 거부, 가방에 없는 열매·모르는 열매·남의 식물·이상한 인자는 조용히 무시",
		function()
			local w = world()
			local plant = addPlant(w, "sprout_daisy")
			w.data.fruits.crystal_snowdrop = { count = 3, value = 24000 }
			standFar(w)
			w.H.client(w.player, "FeedFruit", plant.uid, "crystal_snowdrop")
			T.eq(w.data.fruits.crystal_snowdrop.count, 3)
			T.truthy(w.H.hasNotify(w.player, "error", "정원 가까이"))
			standInGarden(w)
			local other = w.H.newPlayer(1002, "Other")
			local otherSession, otherData = w.H.login(other)
			otherSession.plotIndex = 2
			otherData.nextUid = 500
			local theirs = addPlant(w, "owl_oak", { player = other, data = otherData })
			w.H.clearSent()
			local calls = {
				{ plant.uid, "owl_oak" }, -- 가방에 없음
				{ plant.uid, "chicken" }, -- 5판 펫 id
				{ plant.uid, "없는식물" },
				{ theirs.uid, "crystal_snowdrop" },
				{ "i1", "crystal_snowdrop" },
				{ plant.uid, 5 },
				{ nil, "crystal_snowdrop" },
				{ plant.uid },
			}
			for _, args in calls do
				w.H.advance(1)
				w.H.client(w.player, "FeedFruit", args[1], args[2])
			end
			T.eq(w.data.fruits.crystal_snowdrop.count, 3)
			T.eq(#payloads(w, "FeedResult"), 0)
			T.eq(#theirs.mutations, 0)
			T.eq(#w.H.notifications(w.player), 0, "조용히")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("6판 정원: 오프라인 열매 · 물 주기")

	T.test(
		"접속 때 오프라인 시간만큼 열매 (45초 → 1개 + 15초 쌓임, 1시간 → 최대 5), 처음 접속(0)은 없음",
		function()
			local w = world()
			local a = addPlant(w, "sprout_daisy")
			w.data.lastSaveTime = w.H.time() - 45
			w.FruitService.onPlayerReady(w.player)
			T.eq(a.fruits, 1)
			T.near(a.fruitProgress, 15, 1e-9)
			a.fruits, a.fruitProgress = 0, 0
			w.data.lastSaveTime = w.H.time() - 3600
			w.FruitService.onPlayerReady(w.player)
			T.eq(a.fruits, 5)
			a.fruits = 0
			w.data.lastSaveTime = 0
			w.FruitService.onPlayerReady(w.player)
			T.eq(a.fruits, 0, "lastSaveTime 0 = 처음")
			w.data.fruits.owl_oak = { count = 4, value = 720 }
			w.FruitService.onPlayerReady(w.player)
			T.eq(w.player.attrs.FruitCount, 4, "가방 Attribute 도 맞춤")
			T.eq(w.player.attrs.FruitBagValue, 720)
			w.H.uninstall()
		end
	)

	T.test(
		"물 주기(PetPet)는 성체의 다음 열매를 10초 당김, 같은 식물은 60초 뒤에 또, 열매 5개면 효과 없음",
		function()
			local w = world()
			local plant = addPlant(w, "sprout_daisy")
			standInGarden(w)
			w.H.advance(10)
			w.H.client(w.player, "PetPet", plant.uid)
			T.near(plant.fruitProgress, 20, 0.6, "10초 + 물 10초")
			w.H.advance(10.5)
			T.eq(plant.fruits, 1, "30초 간격인데 20초 만에")
			local before = plant.fruitProgress
			w.H.client(w.player, "PetPet", plant.uid)
			T.near(plant.fruitProgress, before, 1e-9, "60초 안에는 또 안 됨")
			T.truthy(w.H.hasNotify(w.player, "info", "뒤에 또 물을 줄 수 있어요"))
			plant.fruits = w.Config.FRUIT_MAX_PER_PLANT
			plant.fruitProgress = 0
			w.H.advance(61)
			w.H.client(w.player, "PetPet", plant.uid)
			T.eq(plant.fruitProgress, 0, "가득 차면 시간이 안 쌓임")
			T.eq(#w.H.remotes.PetPetted.firedAll, 2, "물을 준 두 번만 서버 전체에 PetPetted")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("6판 정원: Remote 계약")

	T.test("PickFruit·SellFruits·FeedFruit 는 레이트 리밋이 있고 Net.on 처리기가 하나씩", function()
		local w = world()
		local Remotes = w.H.shared("Remotes")
		for _, name in { "PickFruit", "SellFruits", "FeedFruit" } do
			T.truthy(Remotes.ToServer[name], name)
			T.truthy(Remotes.RateLimits[name], name .. " 레이트 리밋")
		end
		for _, name in { "PickFruit", "SellFruits", "FeedFruit" } do
			T.eq(#w.H.remotes[name].OnServerEvent.handlers, 1, name .. " 처리기 1개")
		end
		for _, name in { "FruitPicked", "FruitsSold", "FeedResult", "PlantGrown" } do
			T.truthy(Remotes.ToClient[name], name)
		end
		w.H.uninstall()
	end)

	T.test(
		"PickFruit 연타: 레이트 리밋(10 / 5)을 넘는 요청은 버려짐 (열매가 다시 맺혀도 1초에 5번까지만)",
		function()
			local w = world()
			local plant = addPlant(w, "sprout_daisy")
			standInGarden(w)
			local handled = 0
			for _ = 1, 30 do
				plant.fruits = 1
				w.H.client(w.player, "PickFruit", plant.uid)
				if plant.fruits == 0 then
					handled += 1
				end
			end
			T.eq(handled, 10, "한 번에 burst 10 까지만")
			w.H.uninstall()
		end
	)
end
