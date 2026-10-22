--!nocheck
--[[
	5판 튜토리얼 (사장님 지시): 숲에서 알 훔치기 → 안전 구역으로 돌아오기 → 우리에 놓기 → 부화 → 펫 장착 → $500
	  1) 순수 규칙 shared/TutorialRules (advance / normalize / view / clean / migratedStep)
	  2) 진짜 TutorialService + BaseService + PetService 를 ServerHarness 위에서 (가짜 EggService 신호)
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local TutorialRules = Loader.require("ReplicatedStorage/Shared/TutorialRules")
	local Tutorial = Loader.require("ReplicatedStorage/Shared/Data/Tutorial")

	local function ctx(over)
		local c = { carrying = false, bagEggs = 0, placedEggs = 0, pets = 0, equipped = 0 }
		for k, v in over or {} do
			c[k] = v
		end
		return c
	end

	------------------------------------------------------------------
	T.suite("5판 튜토리얼: 규칙 (TutorialRules)")

	T.test("단계 5개 + 끝(6), 보상 $500, 사장님 지시 문장 그대로", function()
		T.eq(Tutorial.TOTAL, 5)
		T.eq(Tutorial.DONE, 6)
		T.eq(Tutorial.REWARD_MONEY, 500)
		local texts = {}
		for i, step in Tutorial.steps do
			texts[i] = step.text
			T.truthy(#step.hint > 0, step.id .. " 설명")
		end
		T.eq(texts[1], "숲에서 알 훔치기")
		T.eq(texts[2], "안전 구역으로 돌아오기")
		T.eq(texts[3], "핫바에서 알을 골라 우리에 놓기")
		T.eq(texts[4], "부화!")
		T.eq(texts[5], "펫 장착")
	end)

	T.test(
		"한 단계씩 순서대로: 훔침 1→2, 배달 →3, 놓기 3→4, 부화 →5, 장착 5→끝",
		function()
			local step = 1
			step = TutorialRules.advance(step, "steal", ctx({ carrying = true }))
			T.eq(step, 2)
			step = TutorialRules.advance(step, "deliver", ctx({ bagEggs = 1 }))
			T.eq(step, 3)
			step = TutorialRules.advance(step, "place", ctx({ placedEggs = 1 }))
			T.eq(step, 4)
			step = TutorialRules.advance(step, "hatch", ctx({ pets = 1 }))
			T.eq(step, 5)
			step = TutorialRules.advance(step, "equip", ctx({ pets = 1, equipped = 1 }))
			T.eq(step, Tutorial.DONE)
			T.truthy(TutorialRules.isDone(step))
		end
	)

	T.test(
		"되돌아가기: 들고 가다 놓치면 2→1, 놓은 알을 다 주우면 4→3 (하나라도 남으면 그대로)",
		function()
			T.eq(TutorialRules.advance(2, "lost", ctx()), 1)
			T.eq(TutorialRules.advance(3, "lost", ctx()), 3, "3단계에선 무시")
			T.eq(TutorialRules.advance(4, "unplace", ctx({ placedEggs = 0, bagEggs = 1 })), 3)
			T.eq(TutorialRules.advance(4, "unplace", ctx({ placedEggs = 1, bagEggs = 1 })), 4)
		end
	)

	T.test(
		"건너뛰기 없음: 1단계에서 놓기·부화·장착을 해도 그대로, 3단계에서 훔쳐도 그대로",
		function()
			T.eq(TutorialRules.advance(1, "place", ctx({ placedEggs = 1 })), 1)
			T.eq(TutorialRules.advance(1, "hatch", ctx({ pets = 1 })), 1)
			T.eq(TutorialRules.advance(1, "equip", ctx({ pets = 1, equipped = 1 })), 1)
			T.eq(TutorialRules.advance(3, "steal", ctx({ carrying = true })), 3)
			T.eq(TutorialRules.advance(4, "place", ctx({ placedEggs = 2 })), 4)
			-- 배달은 1단계에서도 (밤 귀가로 바로 배달된 경우) 3으로
			T.eq(TutorialRules.advance(1, "deliver", ctx({ bagEggs = 1 })), 3)
			-- 부화는 3단계(알을 하나 더 놓아 둔 경우)에서도 5로
			T.eq(TutorialRules.advance(3, "hatch", ctx({ pets = 1 })), 5)
		end
	)

	T.test(
		"접속 때 맞추기(normalize): 알 든 채 나감 2→1, 빈 가방 3→상태대로, 끝은 그대로",
		function()
			T.eq(TutorialRules.normalize(2, ctx()), 1)
			T.eq(TutorialRules.normalize(2, ctx({ bagEggs = 1 })), 3)
			T.eq(TutorialRules.normalize(3, ctx({ bagEggs = 2 })), 3)
			T.eq(TutorialRules.normalize(3, ctx({ placedEggs = 1 })), 4)
			T.eq(TutorialRules.normalize(3, ctx()), 1)
			T.eq(TutorialRules.normalize(4, ctx({ placedEggs = 1 })), 4)
			T.eq(TutorialRules.normalize(4, ctx({ pets = 1 })), 5, "부화 직후 꺼진 경우")
			T.eq(TutorialRules.normalize(4, ctx({ bagEggs = 1 })), 3)
			T.eq(TutorialRules.normalize(5, ctx({ pets = 2 })), 5)
			T.eq(TutorialRules.normalize(5, ctx({ bagEggs = 1 })), 3, "펫을 다 팔았으면 다시 놓기부터")
			T.eq(
				TutorialRules.normalize(1, ctx({ pets = 3 })),
				1,
				"1단계는 그대로 (reset 으로 처음부터 시험)"
			)
			T.eq(TutorialRules.normalize(6, ctx()), 6)
		end
	)

	T.test("화면용 view: 단계·전체·글·설명, 끝나면 done + (끝내는 순간만) reward", function()
		local v = TutorialRules.view(3)
		T.eq(v.step, 3)
		T.eq(v.total, 5)
		T.eq(v.text, "핫바에서 알을 골라 우리에 놓기")
		T.truthy(#v.hint > 0)
		T.falsy(v.done)
		T.eq(v.reward, nil)
		local done = TutorialRules.view(6, 500)
		T.truthy(done.done)
		T.eq(done.step, 6)
		T.eq(done.reward, 500)
		T.truthy(string.find(done.text, "$500", 1, true), done.text)
		T.eq(TutorialRules.view(6).reward, nil)
		T.eq(TutorialRules.view(99).step, 6, "이상한 큰 값은 끝으로")
	end)

	T.test("자동 장착 멈춤은 튜토리얼 중에만 (HOLD_AUTO_EQUIP)", function()
		T.truthy(Tutorial.HOLD_AUTO_EQUIP)
		for step = 1, 5 do
			T.truthy(TutorialRules.holdsAutoEquip(step), step)
		end
		T.falsy(TutorialRules.holdsAutoEquip(6))
	end)

	------------------------------------------------------------------
	T.suite("5판 튜토리얼: 서비스 (TutorialService + BaseService + PetService)")

	local function world(step)
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.MapLayout = H.MapLayout
		w.EggPlacement = H.shared("EggPlacement")
		w.Snapshot = H.server("Snapshot")
		w.BaseService = H.server("Services/BaseService")
		w.PetService = H.server("Services/PetService")
		w.TutorialService = H.server("Services/TutorialService")
		w.PetService.start()
		w.TutorialService.start()
		w.player = H.newPlayer(1001, "Newbie")
		w.session, w.data = H.login(w.player, { tutorialStep = step or 1 })
		w.session.plotIndex = 1
		local x, z = H.plotSpot(1)
		H.spawn(w.player, x, 3, z)
		return w
	end

	local function lastUpdate(w)
		local list = w.H.sent(w.player, "TutorialUpdate")
		local last = list[#list]
		return if last then last[1] else nil, #list
	end

	-- 가방 맨 뒤 알을 우리 빈 격자 자리에 놓음
	local function placeLast(w)
		local egg = w.data.eggs[#w.data.eggs]
		local spots = {}
		for _, r in w.data.incubators do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		local l = w.EggPlacement.firstFreeGrid(egg.size, spots)
		local spot = w.MapLayout.toWorld(1, l.x, l.z)
		w.H.client(w.player, "PlaceEgg", egg.uid, spot.x, spot.z)
		return egg.uid
	end

	T.test(
		"처음부터 끝까지: 훔치기 → (잡혀서 1로) → 다시 훔치기 → 배달 → 놓기 → (다시 주워 3으로) → 놓기 → 부화(자동 장착 안 됨) → 장착 → $500",
		function()
			local w = world(1)
			T.eq(w.data.tutorialStep, 1)
			-- 1 → 2: 알을 주움 (EggService.pickedUp)
			w.H.carry(w.player, { petId = "dog", biomeId = "forest" })
			T.eq(w.data.tutorialStep, 2)
			local u = lastUpdate(w)
			T.eq(u.step, 2)
			T.eq(u.total, 5)
			T.eq(u.text, "안전 구역으로 돌아오기")
			-- 2 → 1: 경비에게 잡혀 알을 놓침 (EggService.lost)
			w.H.server("Services/EggService").dropCarried(w.player, "guard")
			T.eq(w.data.tutorialStep, 1)
			T.eq(lastUpdate(w).text, "숲에서 알 훔치기")
			-- 다시 훔쳐서 허브로 배달 → 3
			w.H.carry(w.player, { petId = "dog", biomeId = "forest" })
			T.eq(w.data.tutorialStep, 2)
			w.BaseService.deliver(w.player)
			T.eq(#w.data.eggs, 1)
			T.eq(w.data.tutorialStep, 3)
			T.eq(lastUpdate(w).text, "핫바에서 알을 골라 우리에 놓기")
			-- 3 → 4: 우리에 놓음 (PlaceEgg Remote → BaseService.placed)
			w.BaseService.start()
			local uid = placeLast(w)
			T.eq(#w.data.incubators, 1)
			T.eq(w.data.tutorialStep, 4)
			T.eq(lastUpdate(w).text, "부화!")
			-- 다시 주우면 우리가 비어 → 3, 다시 놓으면 → 4
			w.H.client(w.player, "PickUpPlacedEgg", uid)
			T.eq(#w.data.incubators, 0)
			T.eq(w.data.tutorialStep, 3)
			placeLast(w)
			T.eq(w.data.tutorialStep, 4)
			-- 개 알 3초 (5판): 3초 뒤 다 자람 → 부화 → 5 (튜토리얼 중이라 자동 장착 안 됨)
			local record = w.data.incubators[1]
			T.eq(record.required, 3)
			w.H.advance(4)
			T.truthy(record.progress >= record.required, "3초면 다 자람")
			w.H.client(w.player, "HatchEgg", record.uid)
			T.eq(#w.data.pets, 1)
			T.eq(#w.data.equipped, 0, "튜토리얼 중엔 부화한 펫을 자동 장착 안 함")
			local hatch = w.H.sent(w.player, "HatchResult")
			T.falsy(hatch[#hatch][1].equipped)
			T.eq(w.data.tutorialStep, 5)
			T.eq(lastUpdate(w).text, "펫 장착")
			local moneyBefore = w.data.money
			-- 5 → 끝: 펫 장착 → $500 한 번
			w.H.client(w.player, "EquipPet", w.data.pets[1].uid)
			T.eq(#w.data.equipped, 1)
			T.eq(w.data.tutorialStep, 6)
			T.eq(w.data.money, moneyBefore + 500)
			local done, count = lastUpdate(w)
			T.truthy(done.done)
			T.eq(done.reward, 500)
			T.truthy(w.H.hasNotify(w.player, "success", "튜토리얼 끝"))
			-- 끝난 뒤에는 아무 일에도 더 안 보내고 돈도 다시 안 줌
			w.H.client(w.player, "UnequipPet", w.data.pets[1].uid)
			w.H.client(w.player, "EquipBest")
			w.H.carry(w.player, { petId = "chicken", biomeId = "forest" })
			w.BaseService.deliver(w.player)
			local _, after = lastUpdate(w)
			T.eq(after, count, "끝난 뒤 TutorialUpdate 없음")
			T.eq(w.data.money, moneyBefore + 500)
			-- DataUpdate("tutorial") 로 State 도 맞춰짐
			local sawSection = false
			for _, args in w.H.sent(w.player, "DataUpdate") do
				if args[1] == "tutorial" then
					sawSection = true
					T.truthy(args[2].tutorial ~= nil)
				end
			end
			T.truthy(sawSection, 'DataUpdate("tutorial")')
			w.H.uninstall()
		end
	)

	T.test(
		"튜토리얼이 끝난 뒤의 부화는 원래대로 자동 장착, EquipBest 로도 5단계가 끝남",
		function()
			local w = world(5)
			w.PetService.addPet(w.player, { uid = "p1", petId = "chicken", size = "normal", mutations = {} }, false)
			T.eq(#w.data.equipped, 0)
			w.H.client(w.player, "EquipBest")
			T.eq(w.data.tutorialStep, 6, "Equip Best 도 장착")
			T.eq(w.data.money, 500)
			-- 끝난 사람: 새 펫은 빈 칸에 자동 장착 (BaseService.hatch)
			w.BaseService.start()
			w.BaseService.grantEgg(w.player, "dog", "normal", {}, "dev")
			local egg = w.data.eggs[1]
			local spot = w.MapLayout.toWorld(
				1,
				w.EggPlacement.firstFreeGrid("normal", {}).x,
				w.EggPlacement.firstFreeGrid("normal", {}).z
			)
			w.H.client(w.player, "PlaceEgg", egg.uid, spot.x, spot.z)
			w.H.advance(4)
			w.H.client(w.player, "HatchEgg", egg.uid)
			T.eq(#w.data.pets, 2)
			T.eq(#w.data.equipped, 2, "끝난 사람은 자동 장착")
			w.H.uninstall()
		end
	)

	T.test("5단계: 장착 펫이 0마리면 끝나지 않음 (EquipBest 를 펫 없이 눌러도)", function()
		local w = world(5)
		w.H.client(w.player, "EquipBest")
		T.eq(w.data.tutorialStep, 5)
		T.eq(w.data.money, 0)
		w.H.uninstall()
	end)

	T.test("튜토리얼을 끝낸 사람(기본)·불러오기 전 사람에게는 아무것도 안 보냄", function()
		local w = world(6)
		w.H.carry(w.player, { petId = "dog", biomeId = "forest" })
		w.BaseService.deliver(w.player)
		T.eq(#w.H.sent(w.player, "TutorialUpdate"), 0)
		w.TutorialService.onPlayerReady(w.player)
		T.eq(#w.H.sent(w.player, "TutorialUpdate"), 0, "끝난 사람은 접속해도 안 보냄")
		local stranger = w.H.newPlayer(2002, "NotLoaded")
		w.TutorialService.record(stranger, "steal")
		w.TutorialService.onPlayerReady(stranger)
		T.eq(w.TutorialService.getStep(stranger), nil)
		w.H.uninstall()
	end)

	T.test(
		"접속 때(onPlayerReady): 저장된 단계를 맞추고 TutorialUpdate, Snapshot.tutorial 도 같은 단계",
		function()
			local w = world(2) -- 알을 든 채 나갔던 사람 (알은 사라짐)
			w.TutorialService.onPlayerReady(w.player)
			T.eq(w.data.tutorialStep, 1)
			local u = lastUpdate(w)
			T.eq(u.step, 1)
			T.falsy(u.done)
			local snap = w.Snapshot.build(w.player)
			T.eq(snap.tutorial.step, 1)
			T.eq(snap.tutorial.total, 5)
			T.eq(snap.tutorial.text, "숲에서 알 훔치기")
			T.eq(snap.quests, nil, "5판: Snapshot 에 퀘스트 없음")
			T.eq(snap.freeRewardClaimed, nil, "5판: Snapshot 에 무료 보상 없음")
			w.H.uninstall()
			-- 4단계였는데 우리가 비고 가방에 알 → 3
			local w2 = world(4)
			w2.BaseService.grantEgg(w2.player, "dog", "normal", {}, "dev")
			w2.TutorialService.onPlayerReady(w2.player)
			T.eq(w2.data.tutorialStep, 3)
			w2.H.uninstall()
		end
	)

	T.test("/tutorial reset 뒤 다시 끝내면 보상을 다시 받음 (개발 명령 시험용)", function()
		local w = world(5)
		w.PetService.addPet(w.player, { uid = "p1", petId = "chicken", size = "normal", mutations = {} }, false)
		w.H.client(w.player, "EquipPet", "p1")
		T.eq(w.data.money, 500)
		w.TutorialService.reset(w.player)
		T.eq(w.data.tutorialStep, 1)
		T.eq(lastUpdate(w).step, 1)
		-- 순서대로 다시 (이미 펫이 있어도 1단계부터)
		w.H.client(w.player, "EquipBest")
		T.eq(w.data.tutorialStep, 1, "건너뛰기 없음")
		w.H.carry(w.player, { petId = "dog", biomeId = "forest" })
		w.BaseService.deliver(w.player)
		T.eq(w.data.tutorialStep, 3)
		w.H.uninstall()
	end)

	T.test("5판 개 알: 부화 시간 3초 (밤이면 30배 → 0.1초)", function()
		local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
		T.eq(Economy.hatchSeconds("dog"), 3)
		T.eq(Economy.hatchSeconds("chicken"), 10, "닭은 그대로")
	end)
end
