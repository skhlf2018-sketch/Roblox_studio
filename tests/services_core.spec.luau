--!nocheck
--[[
	서비스 테스트 1: Net, PetService, IncomeService, IndexService, UpgradeService(+러닝머신), RewardService
	진짜 서비스 코드를 ServerHarness(가짜 엔진 + 가상 시간) 위에서 돌립니다.
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	-- 테스트마다 새 세계 (모듈 캐시를 비우고 다시 불러옴)
	local function world()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.Pets = H.shared("Data/Pets")
		w.Economy = H.shared("Economy")
		w.Remotes = H.shared("Remotes")
		w.DataSchema = H.server("Logic/DataSchema")
		w.Sessions = H.server("Sessions")
		w.player = H.newPlayer(1001, "Tester")
		w.session, w.data = H.login(w.player)
		return w
	end

	local function addPet(w, petId, size, mutations)
		local PetService = w.H.server("Services/PetService")
		local record = {
			uid = w.DataSchema.newUid(w.data, "p"),
			petId = petId,
			size = size or "normal",
			mutations = mutations or {},
		}
		local kept = PetService.addPet(w.player, record)
		return record, kept
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

	T.test("레이트 리밋: HatchEgg 는 10번까지 통과, 11번째는 막힘, 0.25초 뒤 1개 회복", function()
		local w = world()
		local Net = w.H.server("Net")
		local calls = 0
		Net.on(w.Remotes.ToServer.HatchEgg, function()
			calls += 1
		end)
		for _ = 1, 12 do
			w.H.client(w.player, "HatchEgg", "i1")
		end
		T.eq(calls, 10, "burst 10")
		w.H.advance(0.26) -- perSecond 4 → 0.25초에 1개
		w.H.client(w.player, "HatchEgg", "i1")
		w.H.client(w.player, "HatchEgg", "i1")
		T.eq(calls, 11, "회복된 1개만 통과")
		-- 다른 플레이어는 따로 센다
		local other = w.H.newPlayer(1002, "Other")
		w.H.client(other, "HatchEgg", "i1")
		T.eq(calls, 12)
		w.H.uninstall()
	end)

	T.test("핸들러가 오류를 내도 서버는 안 멈추고 warn 만 남김", function()
		local w = world()
		local Net = w.H.server("Net")
		local second = 0
		Net.on(w.Remotes.ToServer.EquipBest, function()
			error("일부러 낸 오류")
		end)
		Net.on(w.Remotes.ToServer.EquipBest, function()
			second += 1
		end)
		w.H.client(w.player, "EquipBest")
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
	T.suite("서비스: PetService (보관함 500 상한·자동 판매·장착)")

	T.test("처음 7마리는 자동 장착, 8번째부터는 보관함만", function()
		local w = world()
		local PetService = w.H.server("Services/PetService")
		for _ = 1, 8 do
			addPet(w, "chicken")
		end
		T.eq(#w.data.pets, 8)
		T.eq(#w.data.equipped, 7)
		T.eq(w.player.attrs.PenSlots, 7)
		T.eq(w.player.attrs.IncomePerSecond, 7 * 3, "닭 7마리 × $3")
		-- 우리가 가득 차면 장착 거부 + 안내
		T.falsy(PetService.equip(w.player, w.data.pets[8].uid))
		T.truthy(w.H.hasNotify(w.player, "error", "우리가 가득 찼어요"))
		w.H.uninstall()
	end)

	T.test(
		"보관함 500 넘으면 장착 안 된 펫 중 제일 싼 펫이 자동 판매 (돈 = 수입 × 60초)",
		function()
			local w = world()
			w.H.server("Services/PetService").start()
			for _ = 1, 7 do
				addPet(w, "bear") -- 장착됨 (7칸)
			end
			for _ = 1, 492 do
				addPet(w, "brr_brr_patapim") -- 보관함 (비싼 펫)
			end
			addPet(w, "chicken") -- 500번째, 수입 3
			T.eq(#w.data.pets, 500)
			T.eq(w.data.money, 0, "아직 안 팔림")
			w.H.clearSent()

			local _, kept = addPet(w, "dog") -- 501번째 → 닭(3)이 팔림
			T.truthy(kept)
			T.eq(#w.data.pets, 500)
			T.eq(w.data.money, 3 * 60, "닭 수입 3 × 60초")
			local sold = w.H.sent(w.player, "PetsSold")
			T.eq(#sold, 1)
			T.eq(sold[1][1].pets[1].petId, "chicken")
			T.eq(sold[1][1].money, 180)
			T.truthy(w.H.hasNotify(w.player, "info", "보관함이 가득 차서(500마리)"))

			-- 새로 부화한 펫이 제일 싸면 그 펫이 바로 팔림 (addPet 이 false)
			local newest, keptNew = addPet(w, "chicken")
			T.falsy(keptNew)
			T.eq(#w.data.pets, 500)
			for _, record in w.data.pets do
				T.truthy(record.uid ~= newest.uid)
			end
			T.eq(w.data.money, 360)
			w.H.uninstall()
		end
	)

	T.test("장착한 펫은 아무리 싸도 안 팔림", function()
		local w = world()
		for _ = 1, 7 do
			addPet(w, "chicken") -- 장착됨, 제일 싼 펫
		end
		for _ = 1, 493 do
			addPet(w, "bear")
		end
		T.eq(#w.data.pets, 500)
		addPet(w, "bear") -- 501
		T.eq(#w.data.pets, 500)
		local equippedCount = 0
		for _, uid in w.data.equipped do
			for _, record in w.data.pets do
				if record.uid == uid then
					equippedCount += 1
					T.eq(record.petId, "chicken")
				end
			end
		end
		T.eq(equippedCount, 7, "닭 7마리는 그대로")
		w.H.uninstall()
	end)

	T.test("EquipPet / UnequipPet / EquipBest 요청 (Remote) — 이상한 인자는 무시", function()
		local w = world()
		w.H.server("Services/PetService").start()
		local records = {}
		for _, id in { "chicken", "dog", "bear", "fox", "bird", "raccoon", "burrowing_owl", "brr_brr_patapim" } do
			table.insert(records, (addPet(w, id)))
		end
		-- 처음 7마리 자동 장착 → 파타핌(8번째)은 보관함
		local patapim = records[8]
		for _, bad in { 12345, "", "../../x", string.rep("a", 60), true, {} } do
			w.H.client(w.player, "EquipPet", bad)
			w.H.client(w.player, "UnequipPet", bad)
		end
		w.H.client(w.player, "EquipPet")
		T.eq(#w.data.equipped, 7)
		-- 해제 후 장착
		w.H.client(w.player, "UnequipPet", records[1].uid)
		T.eq(#w.data.equipped, 6)
		w.H.client(w.player, "EquipPet", patapim.uid)
		T.eq(#w.data.equipped, 7)
		-- 이미 장착한 걸 또 장착해도 중복 없음
		w.H.client(w.player, "EquipPet", patapim.uid)
		T.eq(#w.data.equipped, 7)
		-- Equip Best: 수입 높은 순 7마리 (닭이 빠짐)
		w.H.client(w.player, "EquipBest")
		T.eq(#w.data.equipped, 7)
		T.eq(table.find(w.data.equipped, records[1].uid), nil, "제일 약한 닭 제외")
		T.truthy(table.find(w.data.equipped, patapim.uid))
		T.eq(w.data.equipped[1], patapim.uid, "수입 1등이 맨 앞")
		w.H.uninstall()
	end)

	T.test("removePets: 하나라도 없으면 아무것도 안 지움, 있으면 장착도 같이 해제", function()
		local w = world()
		local PetService = w.H.server("Services/PetService")
		local a = addPet(w, "chicken")
		local b = addPet(w, "dog")
		T.eq(PetService.removePets(w.player, { a.uid, "없는uid" }), nil)
		T.eq(#w.data.pets, 2)
		T.eq(#w.data.equipped, 2)
		local removed = PetService.removePets(w.player, { a.uid, b.uid })
		T.eq(#removed, 2)
		T.eq(#w.data.pets, 0)
		T.eq(#w.data.equipped, 0, "장착 목록에도 안 남음")
		T.eq(w.player.attrs.IncomePerSecond, 0)
		w.H.uninstall()
	end)

	T.test("돈 2배 게임패스 플래그가 켜지면 초당 수입 2배 (1차 버전은 꺼 둠)", function()
		local w = world()
		local PetService = w.H.server("Services/PetService")
		addPet(w, "bear")
		T.eq(w.session.incomePerSecond, 720)
		w.session.hasMoneyPass = true
		PetService.recalc(w.player)
		T.eq(w.session.incomePerSecond, 1440)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: IncomeService (1초마다 수입)")

	T.test("10초 지나면 초당 수입 × 10 이 돈에 쌓임, 수입 0 이면 그대로", function()
		local w = world()
		local IncomeService = w.H.server("Services/IncomeService")
		IncomeService.start()
		w.H.advance(5)
		T.eq(w.data.money, 0, "펫이 없으면 0")
		addPet(w, "bear") -- 720/초
		w.H.advance(10)
		T.near(w.data.money, 7200, 1e-6)
		T.eq(w.player.attrs.Money, w.data.money, "Attribute 로도 복제")
		w.H.uninstall()
	end)

	T.test("데이터가 아직 안 불러와진 플레이어에게는 안 줌", function()
		local w = world()
		local IncomeService = w.H.server("Services/IncomeService")
		IncomeService.start()
		w.session.loaded = false
		w.session.incomePerSecond = 1000
		w.H.advance(3)
		T.eq(w.data.money, 0)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: IndexService (도감 발견·보상·구역 무기)")

	T.test("첫 발견만 true, 모르는 펫 id 는 false", function()
		local w = world()
		local IndexService = w.H.server("Services/IndexService")
		T.truthy(IndexService.discover(w.player, "chicken"))
		T.falsy(IndexService.discover(w.player, "chicken"))
		T.falsy(IndexService.discover(w.player, "없는펫"))
		T.eq(w.data.indexDiscovered.chicken, true)
		w.H.uninstall()
	end)

	T.test("호수 8마리를 다 발견하면 물 방망이 해금 + 알림 + 신호", function()
		local w = world()
		local IndexService = w.H.server("Services/IndexService")
		local unlocked = {}
		IndexService.weaponsChanged:connect(function(_, ids)
			for _, id in ids do
				table.insert(unlocked, id)
			end
		end)
		for _, pet in w.Pets.inBiome("lake") do
			IndexService.discover(w.player, pet.id)
		end
		T.eq(#w.data.weapons, 1)
		T.eq(w.data.weapons[1], "water_bat")
		T.eq(unlocked[1], "water_bat")
		T.truthy(w.H.hasNotify(w.player, "success", "물 방망이"))
		-- 이미 얻은 무기는 다시 안 알림
		w.H.clearSent()
		IndexService.discover(w.player, "chicken")
		T.eq(#w.data.weapons, 1)
		w.H.uninstall()
	end)

	T.test(
		"보상 받기: 한 마리씩 / 모두 받기 / 두 번 받기 불가 (설계문서 예시 숫자)",
		function()
			local w = world()
			local IndexService = w.H.server("Services/IndexService")
			IndexService.start()
			for _, id in { "chicken", "raccoon", "brr_brr_patapim" } do
				IndexService.discover(w.player, id)
			end
			-- 닭 +420 속도 +$100
			w.H.client(w.player, "ClaimIndexReward", "chicken")
			T.eq(w.data.money, 100)
			T.eq(w.data.speed, w.Config.STARTING_SPEED + 420)
			T.eq(w.player.attrs.Speed, w.Config.STARTING_SPEED + 420, "실효 속도 Attribute")
			-- 같은 펫 또 받기 → 변화 없음
			w.H.client(w.player, "ClaimIndexReward", "chicken")
			T.eq(w.data.money, 100)
			-- 모두 받기: 라쿤 +620/$4,500 + 파타핌 +1,000/$180,000
			w.H.client(w.player, "ClaimIndexReward", "all")
			T.eq(w.data.money, 100 + 4500 + 180000)
			T.eq(w.data.speed, w.Config.STARTING_SPEED + 420 + 620 + 1000)
			local rewarded = w.H.sent(w.player, "IndexRewarded")
			T.eq(#rewarded, 2)
			T.eq(#rewarded[2][1].petIds, 2)
			-- 한 번 더 모두 받기 → 아무것도 안 일어남
			w.H.client(w.player, "ClaimIndexReward", "all")
			T.eq(#w.H.sent(w.player, "IndexRewarded"), 2)
			-- 발견 안 한 펫을 받으려 하기 / 이상한 값
			w.H.client(w.player, "ClaimIndexReward", "ghost_king")
			w.H.client(w.player, "ClaimIndexReward", "해킹")
			w.H.client(w.player, "ClaimIndexReward", 5)
			T.eq(#w.H.sent(w.player, "IndexRewarded"), 2)
			T.eq(w.data.indexClaimed.ghost_king, nil)
			w.H.uninstall()
		end
	)

	T.test("전체 완성 보너스(속도 1T + 돈 1Qa)는 딱 한 번", function()
		local w = world()
		local IndexService = w.H.server("Services/IndexService")
		for _, pet in w.Pets.list do
			IndexService.discover(w.player, pet.id)
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
	T.suite("서비스: UpgradeService (우리·러닝머신·트레일 구매)")

	T.test(
		"우리 구매: 돈 부족이면 거부, 충분하면 정확히 차감 + 칸 수 증가, 최대면 안내",
		function()
			local w = world()
			local UpgradeService = w.H.server("Services/UpgradeService")
			UpgradeService.start()
			w.data.money = 999
			w.H.client(w.player, "PurchaseUpgrade", "Pen")
			T.eq(w.data.penLevel, 1)
			T.eq(w.data.money, 999, "돈 안 빠짐")
			T.truthy(w.H.hasNotify(w.player, "error", "돈이 부족해요"))
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

	T.test("러닝머신: 해금 $1K, 레벨마다 정해진 가격, 최대 10레벨", function()
		local w = world()
		local UpgradeService = w.H.server("Services/UpgradeService")
		local Upgrades = w.H.shared("Data/Upgrades")
		w.data.money = 1e18
		for level = 1, 10 do
			UpgradeService.purchase(w.player, "Treadmill")
			T.eq(w.data.treadmillLevel, level)
		end
		local expected = 1e18
		for _, row in Upgrades.Treadmill do
			expected -= row.cost
		end
		T.eq(w.data.money, expected, "가격표 합계만큼만 빠짐")
		UpgradeService.purchase(w.player, "Treadmill")
		T.eq(w.data.treadmillLevel, 10)
		w.H.uninstall()
	end)

	T.test(
		"트레일: 가진 것 중 가장 높은 배율 하나만 적용, 중복 구매 불가, 모르는 id 무시",
		function()
			local w = world()
			local UpgradeService = w.H.server("Services/UpgradeService")
			UpgradeService.start()
			w.data.money = 1e9
			w.H.client(w.player, "PurchaseUpgrade", "Trail", "blue") -- ×2.5, $75K
			T.eq(w.player.attrs.Speed, w.Config.STARTING_SPEED * 2.5)
			w.H.client(w.player, "PurchaseUpgrade", "Trail", "grey") -- ×1.5 (낮은 배율을 나중에 사도 높은 게 유지)
			T.eq(w.player.attrs.Speed, w.Config.STARTING_SPEED * 2.5)
			T.eq(#w.data.trails, 2)
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
			w.H.uninstall()
		end
	)

	T.test("러닝머신 패드 반경(5) 안에서만 속도가 오름 — 경계 포함", function()
		local w = world()
		local UpgradeService = w.H.server("Services/UpgradeService")
		UpgradeService.start()
		w.session.plotIndex = 1
		w.data.treadmillLevel = 1 -- 걸음당 2 × 러닝머신 배율 3 = 초당 6
		local startSpeed = w.data.speed
		w.H.spawn(w.player, 35, 3, 0) -- 패드 중심(30)에서 정확히 5 → 안
		w.H.advance(10)
		T.near(w.data.speed - startSpeed, 60, 1e-9)
		-- 반경을 살짝 벗어나면 안 오름
		w.H.teleport(w.player, 35.01, 3, 0)
		w.H.advance(10)
		T.near(w.data.speed - startSpeed, 60, 1e-9)
		-- 잠긴 러닝머신(0레벨)은 안 오름
		w.H.teleport(w.player, 30, 3, 0)
		w.data.treadmillLevel = 0
		w.H.advance(10)
		T.near(w.data.speed - startSpeed, 60, 1e-9)
		-- 높이가 8 이상 차이나면(공중) 안 오름
		w.data.treadmillLevel = 1
		w.H.teleport(w.player, 30, 20, 0)
		w.H.advance(5)
		T.near(w.data.speed - startSpeed, 60, 1e-9)
		-- 속도는 WalkSpeed 에도 반영
		w.H.teleport(w.player, 30, 3, 0)
		w.H.advance(1)
		T.truthy(w.player.Character.humanoid.WalkSpeed > 16)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: RewardService (오프라인 수입·무료 보상)")

	T.test("오프라인 수입: 비운 시간 × 초당 수입, 60초 이상이면 팝업", function()
		local w = world()
		local PetService = w.H.server("Services/PetService")
		local RewardService = w.H.server("Services/RewardService")
		addPet(w, "bear") -- 초당 720
		w.data.lastSaveTime = w.H.time() - 3600
		RewardService.onPlayerReady(w.player)
		T.eq(w.data.money, 720 * 3600)
		local popup = w.H.sent(w.player, "OfflineIncome")
		T.eq(#popup, 1)
		T.eq(popup[1][1].amount, 720 * 3600)
		T.eq(popup[1][1].perDay, 720 * 86400)
		T.truthy(PetService.getIncome(w.player) == 720)
		w.H.uninstall()
	end)

	T.test(
		"오프라인 수입 상한 24시간, 30초 비웠으면 돈은 주되 팝업 없음, 처음 접속은 0",
		function()
			local w = world()
			local RewardService = w.H.server("Services/RewardService")
			addPet(w, "bear")
			w.data.lastSaveTime = w.H.time() - 10 * 86400
			RewardService.onPlayerReady(w.player)
			T.eq(w.data.money, 720 * 86400, "10일 비웠어도 24시간치만")

			local w2 = world()
			local R2 = w2.H.server("Services/RewardService")
			addPet(w2, "bear")
			w2.data.lastSaveTime = w2.H.time() - 30
			R2.onPlayerReady(w2.player)
			T.eq(w2.data.money, 720 * 30)
			T.eq(#w2.H.sent(w2.player, "OfflineIncome"), 0, "60초 미만은 팝업 없음")

			local w3 = world()
			local R3 = w3.H.server("Services/RewardService")
			addPet(w3, "bear")
			w3.data.lastSaveTime = 0 -- 첫 접속
			R3.onPlayerReady(w3.player)
			T.eq(w3.data.money, 0)
			w3.H.uninstall()
		end
	)

	T.test("무료 보상: 계정당 한 번 +10,000 속도", function()
		local w = world()
		local RewardService = w.H.server("Services/RewardService")
		RewardService.start()
		w.H.client(w.player, "ClaimFreeReward")
		T.eq(w.data.speed, w.Config.STARTING_SPEED + w.Config.FREE_REWARD_SPEED)
		T.truthy(w.data.freeRewardClaimed)
		w.H.client(w.player, "ClaimFreeReward")
		T.eq(w.data.speed, w.Config.STARTING_SPEED + w.Config.FREE_REWARD_SPEED, "두 번째는 무시")
		w.H.uninstall()
	end)

	T.test("무료 보상: 그룹 ID 를 켜면 그룹 가입자만 (가입 안 했으면 안내)", function()
		local w = world()
		local RewardService = w.H.server("Services/RewardService")
		w.Config.FREE_REWARD_GROUP_ID = 12345
		RewardService.claimFree(w.player)
		T.falsy(w.data.freeRewardClaimed)
		T.truthy(w.H.hasNotify(w.player, "error", "그룹에 가입"))
		w.player.groups[12345] = true
		RewardService.claimFree(w.player)
		T.truthy(w.data.freeRewardClaimed)
		w.Config.FREE_REWARD_GROUP_ID = 0
		w.H.uninstall()
	end)

	ServerHarness.install(Loader, T).uninstall()
end
