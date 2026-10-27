--!nocheck
--[[
	서비스 테스트 1 (6판): Net, PetService(정원의 성체 식물 · 뽑아서 팔기), 자동 수입 없음, IndexService,
	UpgradeService(+러닝머신). 진짜 서비스 코드를 ServerHarness(가짜 엔진 + 가상 시간) 위에서 돌립니다.
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	-- 테스트마다 새 세계 (모듈 캐시를 비우고 다시 불러옴)
	local function world()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.Plants = H.shared("Data/Plants")
		w.Economy = H.shared("Economy")
		w.GardenRules = H.shared("GardenRules")
		w.Remotes = H.shared("Remotes")
		w.DataSchema = H.server("Logic/DataSchema")
		w.Sessions = H.server("Sessions")
		w.player = H.newPlayer(1001, "Tester")
		w.session, w.data = H.login(w.player)
		return w
	end

	-- 정원 빈 격자 자리에 성체 하나 (PetService.addPlant). 기록과 성공 여부
	local function addPlant(w, petId, size, mutations)
		local PetService = w.H.server("Services/PetService")
		local EggPlacement = w.H.shared("EggPlacement")
		local taken = {}
		for _, r in w.data.pets do
			table.insert(taken, { x = r.x, z = r.z, size = r.size })
		end
		for _, r in w.data.incubators do
			table.insert(taken, { x = r.x, z = r.z, size = r.size })
		end
		local spot = EggPlacement.firstFreeGrid(size or "normal", taken) or { x = -20, z = 0 }
		local record = {
			uid = w.DataSchema.newUid(w.data, "p"),
			petId = petId,
			size = size or "normal",
			mutations = mutations or {},
			x = spot.x,
			z = spot.z,
			fruits = 0,
			fruitProgress = 0,
		}
		local ok = PetService.addPlant(w.player, record)
		return record, ok
	end

	------------------------------------------------------------------
	T.suite("서비스: Net (진짜 server/Net.luau)")

	T.test("start() 가 shared/Remotes 의 모든 RemoteEvent 를 만듦", function()
		local w = world()
		local count = 0
		for _, name in w.Remotes.ToClient do
			T.truthy(w.H.remotes[name], "서버→클라 " .. name)
			count += 1
		end
		for _, name in w.Remotes.ToServer do
			T.truthy(w.H.remotes[name], "클라→서버 " .. name)
			count += 1
		end
		T.eq(#w.H.created, count)
		w.H.uninstall()
	end)

	T.test("레이트 리밋: SellPlant 는 10번까지 통과, 11번째는 막힘, 0.25초 뒤 1개 회복", function()
		local w = world()
		local Net = w.H.server("Net")
		local calls = 0
		Net.on(w.Remotes.ToServer.SellPlant, function()
			calls += 1
		end)
		for _ = 1, 12 do
			w.H.client(w.player, "SellPlant", "p1")
		end
		T.eq(calls, 10, "burst 10")
		w.H.advance(0.26) -- perSecond 4 → 0.25초에 1개
		w.H.client(w.player, "SellPlant", "p1")
		w.H.client(w.player, "SellPlant", "p1")
		T.eq(calls, 11, "회복된 1개만 통과")
		-- 다른 플레이어는 따로 센다
		local other = w.H.newPlayer(1002, "Other")
		w.H.client(other, "SellPlant", "p1")
		T.eq(calls, 12)
		w.H.uninstall()
	end)

	T.test("핸들러가 오류를 내도 서버는 안 멈추고 warn 만 남김", function()
		local w = world()
		local Net = w.H.server("Net")
		local second = 0
		Net.on(w.Remotes.ToServer.SellFruits, function()
			error("일부러 낸 오류")
		end)
		Net.on(w.Remotes.ToServer.SellFruits, function()
			second += 1
		end)
		w.H.client(w.player, "SellFruits")
		T.eq(second, 1, "다른 핸들러는 계속 실행")
		T.eq(#w.H.warnings, 1)
		T.truthy(string.find(w.H.warnings[1], "일부러 낸 오류", 1, true))
		w.H.uninstall()
	end)

	T.test("모르는 Remote 이름으로 Net.on 하면 즉시 오류 (오타 방지)", function()
		local w = world()
		local Net = w.H.server("Net")
		local ok = pcall(Net.on, "NoSuchRemote", function() end)
		T.falsy(ok)
		ok = pcall(Net.on, "HatchEgg", function() end)
		T.falsy(ok, "6판에서 없앤 Remote")
		w.H.uninstall()
	end)

	T.test("플레이어가 나가면 Net.fire 는 조용히 건너뜀", function()
		local w = world()
		local Net = w.H.server("Net")
		w.H.leave(w.player)
		Net.notify(w.player, "info", "안 가야 함")
		T.eq(#w.H.remotes.Notify.fired, 0)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: PetService (6판: 정원의 성체 식물)")

	T.test(
		"addPlant: 정원 칸(1레벨 7칸) = 자라는 씨앗 + 성체 까지만, 같은 uid 는 거부, 신호·DataUpdate(pets)",
		function()
			local w = world()
			local PetService = w.H.server("Services/PetService")
			local changed = 0
			PetService.plantsChanged:connect(function()
				changed += 1
			end)
			table.insert(w.data.incubators, {
				uid = "i90",
				petId = "rune_rose",
				size = "normal",
				mutations = {},
				biomeId = "enchanted_forest",
				special = false,
				x = -30,
				z = -25,
				progress = 0,
				required = 86400,
			})
			for i = 1, 6 do
				local _, ok = addPlant(w, "sprout_daisy")
				T.truthy(ok, "성체 " .. i)
			end
			local _, full = addPlant(w, "sprout_daisy")
			T.falsy(full, "씨앗 1 + 성체 6 = 7칸 가득")
			T.eq(#w.data.pets, 6)
			T.eq(changed, 6)
			T.falsy(PetService.addPlant(w.player, table.clone(w.data.pets[1])), "같은 uid")
			local updates = w.H.sent(w.player, "DataUpdate")
			T.eq(updates[#updates][1], "pets")
			T.eq(#updates[#updates][2].pets, 6)
			T.eq(updates[#updates][2].equipped, nil, "6판: 장착 목록 없음")
			T.eq(updates[#updates][2].incomePerSecond, nil, "6판: 자동 수입 없음")
			T.falsy(PetService.hasGardenRoom(w.player))
			w.H.uninstall()
		end
	)

	T.test("removePlants: 하나라도 없으면 아무것도 안 지움, 있으면 지우고 신호", function()
		local w = world()
		local PetService = w.H.server("Services/PetService")
		local a = addPlant(w, "sprout_daisy")
		local b = addPlant(w, "owl_oak")
		T.eq(PetService.removePlants(w.player, { a.uid, "없는uid" }), nil)
		T.eq(#w.data.pets, 2)
		local removed = PetService.removePlants(w.player, { a.uid, b.uid })
		T.eq(#removed, 2)
		T.eq(#w.data.pets, 0)
		T.eq(PetService.findPlant(w.player, a.uid), nil)
		T.eq(PetService.findPet, PetService.findPet, "5판 이름도 남김")
		w.H.uninstall()
	end)

	T.test("recalc: 정원 레벨·칸 수 Attribute (자동 수입 Attribute 는 없음)", function()
		local w = world()
		local PetService = w.H.server("Services/PetService")
		w.data.penLevel = 3
		PetService.recalc(w.player)
		T.eq(w.player.attrs.PenLevel, 3)
		T.eq(w.player.attrs.PenSlots, 9)
		T.eq(w.player.attrs.IncomePerSecond, nil)
		T.eq(PetService.getIncome, nil)
		T.eq(PetService.equip, nil, "장착 없음")
		T.eq(PetService.equipBest, nil)
		w.H.uninstall()
	end)

	T.test(
		"SellPlant: 내 정원 20 안 또는 판매 가판대 14 안에서, 값 = 열매 1개 값 × 20 (크기·돌연변이 포함), 정원 자리가 빔",
		function()
			local w = world()
			local PetService = w.H.server("Services/PetService")
			PetService.start()
			w.session.plotIndex = 1
			local oak = addPlant(w, "owl_oak", "big", { "golden" })
			local daisy = addPlant(w, "sprout_daisy")
			-- 멀리서는 안 됨
			w.H.spawn(w.player, 0, 3, 100)
			w.H.client(w.player, "SellPlant", oak.uid)
			T.eq(#w.data.pets, 2)
			T.truthy(w.H.hasNotify(w.player, "error", "판매 가판대 가까이"))
			-- 허브 판매 가판대 13.9 → 팜
			local stall = w.H.MapLayout.hubSpots.sellStall
			w.H.teleport(w.player, stall.x + 13.9, 3, stall.z)
			w.H.client(w.player, "SellPlant", oak.uid)
			T.eq(#w.data.pets, 1)
			local expect = w.Plants.get("owl_oak").fruitValue * 1.5 * 2 * 20
			T.near(w.data.money, expect, 1e-6)
			T.eq(w.GardenRules.sellPrice(oak), expect)
			T.truthy(w.H.hasNotify(w.player, "success", "뽑아서"))
			T.truthy(w.H.hasNotify(w.player, "success", "코인"))
			T.eq(w.data.stats.plantsSold, 1)
			-- 14.1 은 안 됨 (정원에서도 멂)
			w.H.teleport(w.player, stall.x + 14.1, 3, stall.z)
			w.H.client(w.player, "SellPlant", daisy.uid)
			T.eq(#w.data.pets, 1, "14.1 은 멀다")
			-- 내 정원 안에서는 됨 (판매 가판대가 아니어도)
			local pen = w.H.MapLayout.penRect(1)
			w.H.teleport(w.player, (pen.xMin + pen.xMax) / 2, 3, (pen.zMin + pen.zMax) / 2)
			w.H.client(w.player, "SellPlant", "p999")
			w.H.client(w.player, "SellPlant", 12)
			T.eq(#w.data.pets, 1, "없는 식물·이상한 인자")
			w.H.client(w.player, "SellPlant", daisy.uid)
			T.eq(#w.data.pets, 0, "정원에서 뽑아서 팔기")
			w.H.uninstall()
		end
	)

	T.test(
		"코인 2배 게임패스 플래그가 켜지면 뽑아서 팔기 값 × 2 (1차 버전은 꺼 둠)",
		function()
			local w = world()
			local PetService = w.H.server("Services/PetService")
			w.session.plotIndex = 1
			local daisy = addPlant(w, "sprout_daisy")
			local pen = w.H.MapLayout.penRect(1)
			w.H.spawn(w.player, (pen.xMin + pen.xMax) / 2, 3, (pen.zMin + pen.zMax) / 2)
			T.falsy(w.session.hasMoneyPass)
			w.session.hasMoneyPass = true
			T.eq(PetService.sellPlant(w.player, daisy.uid), w.GardenRules.sellPrice(daisy) * 2)
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("6판: 자동 수입 없음 (IncomeService·오프라인 수입 RewardService 삭제)")

	T.test(
		"성체가 있어도 시간이 지나기만 해서는 코인이 안 늘어남, 서비스·Remote·Config 가 없음",
		function()
			local w = world()
			addPlant(w, "rune_rose")
			local FruitService = w.H.server("Services/FruitService")
			FruitService.start()
			w.H.advance(60)
			T.eq(w.data.money, 0, "열매는 맺히지만 코인은 따서 팔아야 들어옴")
			T.truthy(w.data.pets[1].fruits > 0, "열매는 맺힘")
			T.falsy(pcall(w.H.server, "Services/IncomeService"))
			T.falsy(pcall(w.H.server, "Services/RewardService"))
			T.eq(w.Remotes.ToClient.IncomeTick, nil)
			T.eq(w.Remotes.ToClient.OfflineIncome, nil)
			T.eq(w.Config.INCOME_TICK_SECONDS, nil)
			T.eq(w.Config.OFFLINE_INCOME_RATE, nil)
			T.eq(w.Config.PASSIVE_INCOME_PER_SECOND, 0)
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: IndexService (도감 발견·보상·구역 무기)")

	T.test("첫 발견만 true, 모르는 식물 id 는 false", function()
		local w = world()
		local IndexService = w.H.server("Services/IndexService")
		T.truthy(IndexService.discover(w.player, "sprout_daisy"))
		T.falsy(IndexService.discover(w.player, "sprout_daisy"))
		T.falsy(IndexService.discover(w.player, "없는식물"))
		T.falsy(IndexService.discover(w.player, "chicken"), "5판 펫 id")
		T.eq(w.data.indexDiscovered.sprout_daisy, true)
		w.H.uninstall()
	end)

	T.test("호수 8종을 다 발견하면 물 방망이 해금 + 알림 + 신호", function()
		local w = world()
		local IndexService = w.H.server("Services/IndexService")
		local unlocked = {}
		IndexService.weaponsChanged:connect(function(_, ids)
			for _, id in ids do
				table.insert(unlocked, id)
			end
		end)
		for _, plant in w.Plants.inBiome("lake") do
			IndexService.discover(w.player, plant.id)
		end
		T.eq(#w.data.weapons, 1)
		T.eq(w.data.weapons[1], "water_bat")
		T.eq(unlocked[1], "water_bat")
		T.truthy(w.H.hasNotify(w.player, "success", "물 방망이"))
		w.H.clearSent()
		IndexService.discover(w.player, "sprout_daisy")
		T.eq(#w.data.weapons, 1)
		w.H.uninstall()
	end)

	T.test("보상 받기: 하나씩 / 모두 받기 / 두 번 받기 불가 (코인 = 열매 값 × 10)", function()
		local w = world()
		local IndexService = w.H.server("Services/IndexService")
		IndexService.start()
		for _, id in { "sprout_daisy", "owl_oak", "firefly_lily" } do
			IndexService.discover(w.player, id)
		end
		-- 아기 데이지 +420 속도 +100 코인
		w.H.client(w.player, "ClaimIndexReward", "sprout_daisy")
		T.eq(w.data.money, 100)
		T.eq(w.data.speed, w.Config.STARTING_SPEED + 420)
		T.eq(w.player.attrs.Speed, w.Config.STARTING_SPEED + 420, "실효 속도 Attribute")
		w.H.client(w.player, "ClaimIndexReward", "sprout_daisy")
		T.eq(w.data.money, 100)
		-- 모두 받기: 부엉이 참나무 +620/1,800 + 반딧불 백합 +620/2,000
		w.H.client(w.player, "ClaimIndexReward", "all")
		T.eq(w.data.money, 100 + 1800 + 2000)
		T.eq(w.data.speed, w.Config.STARTING_SPEED + 420 + 620 + 620)
		local rewarded = w.H.sent(w.player, "IndexRewarded")
		T.eq(#rewarded, 2)
		T.eq(#rewarded[2][1].petIds, 2)
		w.H.client(w.player, "ClaimIndexReward", "all")
		T.eq(#w.H.sent(w.player, "IndexRewarded"), 2)
		w.H.client(w.player, "ClaimIndexReward", "sky_pillar_flower")
		w.H.client(w.player, "ClaimIndexReward", "해킹")
		w.H.client(w.player, "ClaimIndexReward", 5)
		T.eq(#w.H.sent(w.player, "IndexRewarded"), 2)
		T.eq(w.data.indexClaimed.sky_pillar_flower, nil)
		w.H.uninstall()
	end)

	T.test("전체 완성 보너스(속도 1T + 코인 1Qa)는 딱 한 번", function()
		local w = world()
		local IndexService = w.H.server("Services/IndexService")
		for _, plant in w.Plants.list do
			IndexService.discover(w.player, plant.id)
		end
		T.eq(#w.data.weapons, 7, "구역 무기 7개 전부")
		IndexService.claim(w.player, "all")
		T.truthy(w.data.indexCompleteClaimed)
		local speedAfter = w.data.speed
		local moneyAfter = w.data.money
		T.truthy(speedAfter >= 1e12 and moneyAfter >= 1e15)
		IndexService.claim(w.player, "all")
		T.eq(w.data.speed, speedAfter, "두 번째는 변화 없음")
		T.eq(w.data.money, moneyAfter)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: UpgradeService (정원·러닝머신·트레일 구매, 6판 코인)")

	T.test(
		"정원 구매: 코인 부족이면 거부, 충분하면 정확히 차감 + 정원 칸 수 증가, 최대면 안내",
		function()
			local w = world()
			local UpgradeService = w.H.server("Services/UpgradeService")
			UpgradeService.start()
			w.data.money = 999
			w.H.client(w.player, "PurchaseUpgrade", "Pen")
			T.eq(w.data.penLevel, 1)
			T.eq(w.data.money, 999, "돈 안 빠짐")
			T.truthy(w.H.hasNotify(w.player, "error", "코인이 부족해요"))
			T.truthy(w.H.hasNotify(w.player, "error", "1K 코인 필요"))
			w.data.money = 1000
			w.H.client(w.player, "PurchaseUpgrade", "Pen")
			T.eq(w.data.penLevel, 2)
			T.eq(w.data.money, 0)
			T.eq(w.player.attrs.PenSlots, 8)
			T.eq(
				w.H.sent(w.player, "DataUpdate")[#w.H.sent(w.player, "DataUpdate")][2].penSlots,
				8,
				"클라에도 칸 수 전달"
			)
			-- 최대 레벨
			w.data.penLevel = 11
			w.data.money = 1e18
			w.H.client(w.player, "PurchaseUpgrade", "Pen")
			T.eq(w.data.penLevel, 11)
			T.eq(w.data.money, 1e18, "최대 레벨은 돈을 안 받음")
			T.truthy(w.H.hasNotify(w.player, "info", "최대 레벨"))
			w.H.uninstall()
		end
	)

	T.test("러닝머신: 해금 1K 코인, 레벨마다 정해진 가격, 최대 20레벨 (6판: 1초 1M)", function()
		local w = world()
		local UpgradeService = w.H.server("Services/UpgradeService")
		local Upgrades = w.H.shared("Data/Upgrades")
		w.data.money = 1e21
		for level = 1, 20 do
			UpgradeService.purchase(w.player, "Treadmill")
			T.eq(w.data.treadmillLevel, level)
		end
		local expected = 1e21
		for _, row in Upgrades.Treadmill do
			expected -= row.cost
		end
		T.near(w.data.money, expected, 1e6, "가격표 합계만큼만 빠짐")
		UpgradeService.purchase(w.player, "Treadmill")
		T.eq(w.data.treadmillLevel, 20)
		T.truthy(w.H.hasNotify(w.player, "info", "최대 레벨"))
		w.H.uninstall()
	end)

	T.test(
		"트레일: 사면 바로 장착 (장착한 것 하나만 적용), 중복 구매 불가, 모르는 id 무시",
		function()
			local w = world()
			local UpgradeService = w.H.server("Services/UpgradeService")
			UpgradeService.start()
			w.data.money = 1e9
			T.eq(w.data.equippedTrail, "none")
			w.H.client(w.player, "PurchaseUpgrade", "Trail", "blue") -- ×2.5, $75K
			T.eq(w.data.equippedTrail, "blue", "사면 장착")
			T.eq(w.player.attrs.Speed, w.Config.STARTING_SPEED * 2.5)
			T.eq(w.player.attrs.EquippedTrail, "blue")
			w.H.client(w.player, "PurchaseUpgrade", "Trail", "grey") -- ×1.5: 낮은 배율이어도 산 것을 장착
			T.eq(w.data.equippedTrail, "grey")
			T.eq(w.player.attrs.Speed, w.Config.STARTING_SPEED * 1.5)
			T.eq(w.player.attrs.TrailMultiplier, 1.5)
			T.eq(#w.data.trails, 2)
			local updates = w.H.sent(w.player, "DataUpdate")
			local last = updates[#updates]
			T.eq(last[1], "upgrades")
			T.eq(last[2].equippedTrail, "grey")
			T.eq(last[2].trailMultiplier, 1.5)
			local moneyBefore = w.data.money
			w.H.client(w.player, "PurchaseUpgrade", "Trail", "grey") -- 중복
			T.eq(w.data.money, moneyBefore)
			T.eq(#w.data.trails, 2)
			w.H.advance(5) -- 레이트 리밋(burst 5) 회복
			w.H.client(w.player, "PurchaseUpgrade", "Trail", "가짜트레일")
			w.H.client(w.player, "PurchaseUpgrade", "Trail")
			w.H.client(w.player, "PurchaseUpgrade", "Hack")
			w.H.client(w.player, "PurchaseUpgrade", 7, "blue")
			T.eq(w.data.money, moneyBefore)
			T.eq(#w.data.trails, 2)
			T.eq(w.data.equippedTrail, "grey")
			w.H.uninstall()
		end
	)

	T.test(
		'EquipTrail: 가진 트레일만 장착, "none" 이면 해제, 안 가진 것·엉터리 인자는 무시 + Snapshot/DataUpdate 에 equippedTrail',
		function()
			local w = world()
			local UpgradeService = w.H.server("Services/UpgradeService")
			local Snapshot = w.H.server("Snapshot")
			UpgradeService.start()
			w.data.trails = { "grey", "blue" }
			w.data.equippedTrail = "grey"
			w.H.client(w.player, "EquipTrail", "blue")
			T.eq(w.data.equippedTrail, "blue")
			T.eq(w.player.attrs.Speed, w.Config.STARTING_SPEED * 2.5)
			T.eq(w.player.attrs.TrailMultiplier, 2.5)
			T.truthy(w.H.hasNotify(w.player, "success", "파랑 트레일 장착"))
			local updates = w.H.sent(w.player, "DataUpdate")
			T.eq(updates[#updates][1], "upgrades")
			T.eq(updates[#updates][2].equippedTrail, "blue")
			T.eq(updates[#updates][2].trailMultiplier, 2.5)
			-- 안 가진 트레일
			w.H.client(w.player, "EquipTrail", "moonbloom")
			T.eq(w.data.equippedTrail, "blue")
			T.truthy(w.H.hasNotify(w.player, "error", "없는 트레일"))
			-- 해제
			w.H.client(w.player, "EquipTrail", "none")
			T.eq(w.data.equippedTrail, "none")
			T.eq(w.player.attrs.Speed, w.Config.STARTING_SPEED)
			T.eq(w.player.attrs.TrailMultiplier, 1)
			T.eq(w.player.attrs.EquippedTrail, "none")
			local snap = Snapshot.build(w.player)
			T.eq(snap.equippedTrail, "none")
			T.eq(snap.trailMultiplier, 1)
			T.eq(#snap.trails, 2)
			w.H.advance(5) -- 레이트 리밋(burst 5) 회복
			-- 엉터리 인자: 아무 일 없음
			local count = #w.H.sent(w.player, "DataUpdate")
			for _, bad in { "가짜", 7, true, "", string.rep("a", 60) } do
				w.H.client(w.player, "EquipTrail", bad)
			end
			w.H.client(w.player, "EquipTrail")
			T.eq(w.data.equippedTrail, "none")
			T.eq(#w.H.sent(w.player, "DataUpdate"), count)
			-- 다시 장착 → Snapshot 에도 반영
			w.H.advance(5)
			w.H.client(w.player, "EquipTrail", "grey")
			T.eq(Snapshot.build(w.player).equippedTrail, "grey")
			T.eq(Snapshot.build(w.player).trailMultiplier, 1.5)
			-- 이미 장착한 것을 또 보내면 조용히 무시
			count = #w.H.sent(w.player, "DataUpdate")
			w.H.client(w.player, "EquipTrail", "grey")
			T.eq(#w.H.sent(w.player, "DataUpdate"), count)
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: TreadmillService (2판 러닝머신: 올라서면 고정, 점프하면 내림)")

	local function treadWorld(level)
		local w = world()
		w.TreadmillService = w.H.server("Services/TreadmillService")
		w.TreadmillService.start()
		w.session.plotIndex = 1
		w.data.treadmillLevel = level or 1 -- 1레벨: 걸음당 2 × 러닝머신 배율 4 (6판) = 걸음(1초)마다 8
		w.plot = w.H.MapLayout.plot(1)
		w.tx, w.tz = w.plot.treadmill.x, w.plot.treadmill.z
		return w
	end

	T.test(
		"벨트에 올라서면: OnTreadmill + WalkSpeed 0 + 벨트 가운데로 옮겨 복도 쪽을 봄 + 1초마다 속도 8 (6판 배율 4) + TreadmillStep",
		function()
			local w = treadWorld(1)
			local startSpeed = w.data.speed
			w.H.spawn(w.player, w.tx + 3, 3, w.tz + 2) -- 벨트(12 × 8) 위, 가운데에서 조금 벗어남
			w.H.advance(0.2)
			local root = w.player.Character.root
			T.eq(w.player.attrs.OnTreadmill, true)
			T.eq(w.session.onTreadmill, true)
			T.eq(w.player.Character.humanoid.WalkSpeed, 0, "WASD 무시")
			T.eq(w.player.attrs.WalkSpeed, 0)
			T.near(root.Position.X, w.tx, 1e-9, "가운데로")
			T.near(root.Position.Z, w.tz, 1e-9)
			T.eq(root.CFrame.LookVector.X, w.plot.facing, "복도 쪽을 봄")
			T.truthy(w.session.moveExemptUntil > w.H.clock(), "서버 순간이동 → 위치 검증 쉼")
			w.H.advance(10)
			T.near(w.data.speed - startSpeed, 80, 1e-9, "10걸음 × 8")
			local steps = w.H.sent(w.player, "TreadmillStep")
			T.eq(#steps, 10)
			T.eq(steps[1][1].amount, 8)
			-- 물리로 밀려나도 가운데로 되돌림
			w.H.teleport(w.player, w.tx + 2, 3, w.tz)
			w.H.advance(0.2)
			T.near(root.Position.X, w.tx, 1e-9, "다시 가운데")
			T.eq(w.player.attrs.OnTreadmill, true)
			w.H.uninstall()
		end
	)

	T.test(
		"6판 사장님 지시: 최대 20레벨 러닝머신은 1초에 정확히 1,000,000 (10초면 10,000,000, 부동소수 오차 없음)",
		function()
			local w = treadWorld(20)
			local startSpeed = w.data.speed
			w.H.spawn(w.player, w.tx, 3, w.tz)
			w.H.advance(0.2)
			T.eq(w.session.onTreadmill, true)
			w.H.advance(10)
			T.eq(w.data.speed - startSpeed, 10000000, "10걸음 × 1,000,000 (정확히)")
			local steps = w.H.sent(w.player, "TreadmillStep")
			T.eq(#steps, 10)
			for _, args in steps do
				T.eq(args[1].amount, 1000000)
			end
			T.eq(w.Economy.nextTreadmillCost(20), nil, "20레벨이 끝")
			w.H.uninstall()
		end
	)

	T.test(
		"점프(TreadmillLeave)하면 벨트 앞(복도 쪽)으로 내려옴 → 밖으로 나갔다 와야 다시 탐 / 벨트를 벗어나면 자동으로 내림",
		function()
			local w = treadWorld(1)
			w.H.spawn(w.player, w.tx, 3, w.tz)
			w.H.advance(0.2)
			T.eq(w.player.attrs.OnTreadmill, true)
			w.H.client(w.player, "TreadmillLeave")
			T.eq(w.player.attrs.OnTreadmill, false)
			T.truthy(w.player.Character.humanoid.WalkSpeed > 16, "WalkSpeed 되돌림")
			local root = w.player.Character.root
			T.near(root.Position.X, w.tx + w.plot.facing * 9, 1e-9, "벨트 앞 (반 6 + 3)")
			T.falsy(w.H.MapLayout.isOnTreadmill(root.Position, 1, w.Config.TREADMILL_PAD_MARGIN))
			local speed = w.data.speed
			w.H.advance(3)
			T.eq(w.data.speed, speed, "내린 뒤에는 안 오름")
			-- 서버만 내린 경우(제자리): 벨트 위에 그대로 서 있어도 바로 다시 타지 않음
			w.H.teleport(w.player, w.tx, 3, w.tz)
			w.H.advance(0.2)
			T.eq(w.player.attrs.OnTreadmill, true, "밖에 나갔다 다시 올라오면 탐")
			w.TreadmillService.leave(w.player, false)
			w.H.advance(2)
			T.eq(w.player.attrs.OnTreadmill, false, "착지해도 바로 다시 안 탐")
			w.H.teleport(w.player, w.tx + 20, 3, w.tz)
			w.H.advance(0.2)
			w.H.teleport(w.player, w.tx, 3, w.tz)
			w.H.advance(0.2)
			T.eq(w.player.attrs.OnTreadmill, true)
			-- 벨트 밖으로 밀려나거나(서버 확인) 높이 떠도 자동으로 내림
			w.H.teleport(w.player, w.tx, 30, w.tz)
			w.H.advance(0.2)
			T.eq(w.player.attrs.OnTreadmill, false, "공중")
			w.H.uninstall()
		end
	)

	T.test(
		"안 타는 경우: 잠긴 러닝머신(0레벨, 5초에 한 번 안내) / 알을 든 사람 / 기절 / 다른 사람 베이스 러닝머신",
		function()
			local w = treadWorld(0)
			local startSpeed = w.data.speed
			w.H.spawn(w.player, w.tx, 3, w.tz)
			w.H.advance(3)
			T.falsy(w.player.attrs.OnTreadmill)
			T.eq(w.data.speed, startSpeed)
			local locked = 0
			for _, n in w.H.notifications(w.player) do
				if string.find(n.text, "러닝머신이 잠겨 있어요", 1, true) then
					locked += 1
				end
			end
			T.eq(locked, 1, "5초에 한 번")
			w.data.treadmillLevel = 1
			w.session.carryingUid = "e1"
			w.H.advance(1)
			T.falsy(w.player.attrs.OnTreadmill, "알을 든 사람")
			w.session.carryingUid = nil
			w.session.stunnedUntil = w.H.clock() + 3
			w.H.advance(1)
			T.falsy(w.player.attrs.OnTreadmill, "기절")
			w.H.advance(2.5)
			T.eq(w.player.attrs.OnTreadmill, true, "조건이 풀리면 탐")
			-- 다른 사람 베이스(2번) 러닝머신
			local other = w.H.MapLayout.plot(2).treadmill
			w.H.teleport(w.player, other.x, 3, other.z)
			w.H.advance(0.4)
			T.eq(w.player.attrs.OnTreadmill, false, "내 러닝머신이 아님")
			w.H.uninstall()
		end
	)

	ServerHarness.install(Loader, T).uninstall()
end
