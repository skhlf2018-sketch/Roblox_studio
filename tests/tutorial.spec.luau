--!nocheck
--[[
	6판 튜토리얼 (사장님 지시): 숲에서 씨앗 훔치기 → 안전 구역으로 돌아오기 → 핫바에서 씨앗을 골라 정원에 심기
	  → 성체가 될 때까지 기다리기(강아지풀 씨앗 3초) → 열매 따서 팔기 → 500 코인
	  1) 순수 규칙 shared/TutorialRules (advance / normalize / view / clean)
	  2) 진짜 TutorialService + BaseService + PetService + FruitService 를 ServerHarness 위에서 (가짜 EggService 신호)
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local TutorialRules = Loader.require("ReplicatedStorage/Shared/TutorialRules")
	local Tutorial = Loader.require("ReplicatedStorage/Shared/Data/Tutorial")

	local function ctx(over)
		local c = { carrying = false, bagEggs = 0, placedEggs = 0, plants = 0, fruits = 0 }
		for k, v in over or {} do
			c[k] = v
		end
		return c
	end

	------------------------------------------------------------------
	T.suite("6판 튜토리얼: 규칙 (TutorialRules)")

	T.test("단계 5개 + 끝(6), 보상 500 코인, 사장님 지시 문장 그대로", function()
		T.eq(Tutorial.TOTAL, 5)
		T.eq(Tutorial.DONE, 6)
		T.eq(Tutorial.REWARD_MONEY, 500)
		local texts = {}
		for i, step in Tutorial.steps do
			texts[i] = step.text
			T.truthy(#step.hint > 0, step.id .. " 설명")
		end
		T.eq(texts[1], "숲에서 씨앗 훔치기")
		T.eq(texts[2], "안전 구역으로 돌아오기")
		T.eq(texts[3], "핫바에서 씨앗을 골라 정원에 심기")
		T.eq(texts[4], "성체가 될 때까지 기다리기")
		T.eq(texts[5], "열매 따서 팔기")
		T.truthy(
			string.find(Tutorial.steps[4].hint, "1초", 1, true),
			"강아지풀 씨앗 1초 안내 (7판: 표 3초 ÷ 성장 3배)"
		)
		T.falsy(string.find(Tutorial.steps[4].hint, "3초", 1, true), "옛 3초 안내가 남지 않음")
		T.eq(Tutorial.HOLD_AUTO_EQUIP, nil, "6판: 장착 없음")
		T.eq(TutorialRules.holdsAutoEquip, nil)
		T.eq(TutorialRules.migratedStep, nil, "6판: 4 → 5 마이그레이션 규칙 없앰 (6 으로 초기화)")
	end)

	T.test(
		"한 단계씩 순서대로: 훔침 1→2, 배달 →3, 심기 3→4, 성체 →5, 팔기 5→끝",
		function()
			local step = 1
			step = TutorialRules.advance(step, "steal", ctx({ carrying = true }))
			T.eq(step, 2)
			step = TutorialRules.advance(step, "deliver", ctx({ bagEggs = 1 }))
			T.eq(step, 3)
			step = TutorialRules.advance(step, "place", ctx({ placedEggs = 1 }))
			T.eq(step, 4)
			step = TutorialRules.advance(step, "grown", ctx({ plants = 1 }))
			T.eq(step, 5)
			step = TutorialRules.advance(step, "sell", ctx({ plants = 1 }))
			T.eq(step, Tutorial.DONE)
			T.truthy(TutorialRules.isDone(step))
		end
	)

	T.test(
		"되돌아가기: 들고 가다 놓치면 2→1, 심은 씨앗을 다 주우면 4→3 (하나라도 남으면 그대로)",
		function()
			T.eq(TutorialRules.advance(2, "lost", ctx()), 1)
			T.eq(TutorialRules.advance(3, "lost", ctx()), 3, "3단계에선 무시")
			T.eq(TutorialRules.advance(4, "unplace", ctx({ placedEggs = 0, bagEggs = 1 })), 3)
			T.eq(TutorialRules.advance(4, "unplace", ctx({ placedEggs = 1, bagEggs = 1 })), 4)
			T.eq(
				TutorialRules.advance(4, "unplace", ctx({ placedEggs = 0, plants = 1 })),
				4,
				"성체가 있으면 그대로"
			)
		end
	)

	T.test(
		"건너뛰기 없음: 1단계에서 심기·성체·팔기를 해도 그대로, 3단계에서 훔쳐도 그대로",
		function()
			T.eq(TutorialRules.advance(1, "place", ctx({ placedEggs = 1 })), 1)
			T.eq(TutorialRules.advance(1, "grown", ctx({ plants = 1 })), 1)
			T.eq(TutorialRules.advance(1, "sell", ctx({ plants = 1 })), 1)
			T.eq(TutorialRules.advance(3, "steal", ctx({ carrying = true })), 3)
			T.eq(TutorialRules.advance(4, "place", ctx({ placedEggs = 2 })), 4)
			T.eq(TutorialRules.advance(4, "sell", ctx({ plants = 1 })), 4, "성체가 되기 전 팔기는 안 셈")
			-- 배달은 1단계에서도 (밤 귀가로 바로 배달된 경우) 3으로
			T.eq(TutorialRules.advance(1, "deliver", ctx({ bagEggs = 1 })), 3)
			-- 성체는 3단계(씨앗을 하나 더 심어 둔 경우)에서도 5로
			T.eq(TutorialRules.advance(3, "grown", ctx({ plants = 1 })), 5)
		end
	)

	T.test(
		"접속 때 맞추기(normalize): 씨앗 든 채 나감 2→1, 빈 가방 3→상태대로, 성체·열매 있으면 5, 끝은 그대로",
		function()
			T.eq(TutorialRules.normalize(2, ctx()), 1)
			T.eq(TutorialRules.normalize(2, ctx({ bagEggs = 1 })), 3)
			T.eq(TutorialRules.normalize(3, ctx({ bagEggs = 2 })), 3)
			T.eq(TutorialRules.normalize(3, ctx({ placedEggs = 1 })), 4)
			T.eq(TutorialRules.normalize(3, ctx()), 1)
			T.eq(TutorialRules.normalize(4, ctx({ placedEggs = 1 })), 4)
			T.eq(TutorialRules.normalize(4, ctx({ plants = 1 })), 5, "성체가 된 직후 꺼진 경우")
			T.eq(TutorialRules.normalize(4, ctx({ bagEggs = 1 })), 3)
			T.eq(TutorialRules.normalize(5, ctx({ plants = 2 })), 5)
			T.eq(TutorialRules.normalize(5, ctx({ fruits = 3 })), 5, "열매만 들고 있어도 팔 수 있음")
			T.eq(TutorialRules.normalize(5, ctx({ bagEggs = 1 })), 3, "성체를 다 팔았으면 다시 심기부터")
			T.eq(
				TutorialRules.normalize(1, ctx({ plants = 3 })),
				1,
				"1단계는 그대로 (reset 으로 처음부터 시험)"
			)
			T.eq(TutorialRules.normalize(6, ctx()), 6)
		end
	)

	T.test(
		"화면용 view: 단계·전체·글·설명, 끝나면 done + (끝내는 순간만) reward, 코인 글",
		function()
			local v = TutorialRules.view(3)
			T.eq(v.step, 3)
			T.eq(v.total, 5)
			T.eq(v.text, "핫바에서 씨앗을 골라 정원에 심기")
			T.truthy(#v.hint > 0)
			T.falsy(v.done)
			T.eq(v.reward, nil)
			local done = TutorialRules.view(6, 500)
			T.truthy(done.done)
			T.eq(done.step, 6)
			T.eq(done.reward, 500)
			T.truthy(string.find(done.text, "500 코인", 1, true), done.text)
			T.falsy(string.find(done.text, "$", 1, true), done.text)
			T.eq(TutorialRules.view(6).reward, nil)
			T.eq(TutorialRules.view(99).step, 6, "이상한 큰 값은 끝으로")
		end
	)

	------------------------------------------------------------------
	T.suite("6판 튜토리얼: 서비스 (TutorialService + BaseService + PetService + FruitService)")

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
		w.FruitService = H.server("Services/FruitService")
		w.TutorialService = H.server("Services/TutorialService")
		w.PetService.start()
		w.FruitService.start()
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

	-- 가방 맨 뒤 씨앗을 정원 빈 격자 자리에 심음
	local function placeLast(w)
		local egg = w.data.eggs[#w.data.eggs]
		local spots = {}
		for _, r in w.data.incubators do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		for _, r in w.data.pets do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		local l = w.EggPlacement.firstFreeGrid(egg.size, spots)
		local spot = w.MapLayout.toWorld(1, l.x, l.z)
		w.H.client(w.player, "PlaceEgg", egg.uid, spot.x, spot.z)
		return egg.uid
	end

	local function goToGarden(w)
		local pen = w.MapLayout.penRect(1)
		w.H.teleport(w.player, (pen.xMin + pen.xMax) / 2, 3, (pen.zMin + pen.zMax) / 2)
	end

	local function goToStall(w)
		local stall = w.MapLayout.hubSpots.sellStall
		w.H.teleport(w.player, stall.x, 3, stall.z)
	end

	T.test(
		"처음부터 끝까지: 훔치기 → (잡혀서 1로) → 다시 → 배달 → 심기 → (다시 주워 3으로) → 심기 → 1초 뒤 성체(7판) → 열매 따서 팔기 → 500 코인",
		function()
			local w = world(1)
			w.BaseService.start()
			T.eq(w.data.tutorialStep, 1)
			-- 1 → 2: 씨앗을 주움 (EggService.pickedUp)
			w.H.carry(w.player, { petId = "puppy_grass", biomeId = "forest" })
			T.eq(w.data.tutorialStep, 2)
			local u = lastUpdate(w)
			T.eq(u.step, 2)
			T.eq(u.total, 5)
			T.eq(u.text, "안전 구역으로 돌아오기")
			-- 2 → 1: 경비에게 잡혀 씨앗을 놓침 (EggService.lost)
			w.H.server("Services/EggService").dropCarried(w.player, "guard")
			T.eq(w.data.tutorialStep, 1)
			T.eq(lastUpdate(w).text, "숲에서 씨앗 훔치기")
			-- 다시 훔쳐서 허브로 배달 → 3
			w.H.carry(w.player, { petId = "puppy_grass", biomeId = "forest" })
			T.eq(w.data.tutorialStep, 2)
			w.BaseService.deliver(w.player)
			T.eq(#w.data.eggs, 1)
			T.eq(w.data.tutorialStep, 3)
			T.eq(lastUpdate(w).text, "핫바에서 씨앗을 골라 정원에 심기")
			-- 3 → 4: 정원에 심음 (PlaceEgg Remote → BaseService.placed)
			local uid = placeLast(w)
			T.eq(#w.data.incubators, 1)
			T.eq(w.data.tutorialStep, 4)
			T.eq(lastUpdate(w).text, "성체가 될 때까지 기다리기")
			-- 다시 주우면 정원이 비어 → 3, 다시 심으면 → 4
			w.H.client(w.player, "PickUpPlacedEgg", uid)
			T.eq(#w.data.incubators, 0)
			T.eq(w.data.tutorialStep, 3)
			placeLast(w)
			T.eq(w.data.tutorialStep, 4)
			-- 강아지풀 씨앗 (7판 1초) → 그 자리에서 성체 (부화 버튼 없음) → 5
			T.eq(w.data.incubators[1].required, 1)
			w.H.advance(3.1)
			T.eq(#w.data.incubators, 0)
			T.eq(#w.data.pets, 1)
			T.eq(w.data.tutorialStep, 5)
			T.eq(lastUpdate(w).text, "열매 따서 팔기")
			T.eq(w.data.pets[1].fruits, 1, "성체는 열매 1개를 달고 나옴")
			-- 열매 따기 (정원 근처) → 가방, 아직 안 끝남
			goToGarden(w)
			w.H.client(w.player, "PickFruit", w.data.pets[1].uid)
			T.eq(w.data.fruits.puppy_grass.count, 1)
			T.eq(w.data.tutorialStep, 5, "따기만 하면 아직")
			local moneyBefore = w.data.money
			-- 5 → 끝: 판매 가판대에서 팔기 → 열매 값 + 500 코인
			goToStall(w)
			w.H.client(w.player, "SellFruits")
			T.eq(w.data.tutorialStep, 6)
			T.eq(w.data.money, moneyBefore + 8 * 2 + 500, "강아지풀 열매 8 × 초반 2배 + 보상 500")
			local done, count = lastUpdate(w)
			T.truthy(done.done)
			T.eq(done.reward, 500)
			T.truthy(w.H.hasNotify(w.player, "success", "튜토리얼 끝"))
			T.truthy(w.H.hasNotify(w.player, "success", "500 코인"))
			-- 끝난 뒤에는 아무 일에도 더 안 보내고 코인도 다시 안 줌
			w.H.advance(1)
			w.data.fruits.puppy_grass = { count = 1, value = 8 }
			w.H.client(w.player, "SellFruits")
			w.H.carry(w.player, { petId = "sprout_daisy", biomeId = "forest" })
			w.BaseService.deliver(w.player)
			local _, after = lastUpdate(w)
			T.eq(after, count, "끝난 뒤 TutorialUpdate 없음")
			T.eq(w.data.money, moneyBefore + 8 * 2 + 500 + 8, "열매 8 × 초반 2배 + 보상 500 + 배달 8")
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

	T.test("5단계: 팔 열매가 없으면(빈 가방으로 SellFruits) 끝나지 않음", function()
		local w = world(5)
		goToStall(w)
		w.H.client(w.player, "SellFruits")
		T.eq(w.data.tutorialStep, 5)
		T.eq(w.data.money, 0)
		T.truthy(w.H.hasNotify(w.player, "info", "팔 열매가 없어요"))
		w.H.uninstall()
	end)

	T.test("튜토리얼을 끝낸 사람(기본)·불러오기 전 사람에게는 아무것도 안 보냄", function()
		local w = world(6)
		w.H.carry(w.player, { petId = "puppy_grass", biomeId = "forest" })
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
			local w = world(2) -- 씨앗을 든 채 나갔던 사람 (씨앗은 사라짐)
			w.TutorialService.onPlayerReady(w.player)
			T.eq(w.data.tutorialStep, 1)
			local u = lastUpdate(w)
			T.eq(u.step, 1)
			T.falsy(u.done)
			local snap = w.Snapshot.build(w.player)
			T.eq(snap.tutorial.step, 1)
			T.eq(snap.tutorial.total, 5)
			T.eq(snap.tutorial.text, "숲에서 씨앗 훔치기")
			w.H.uninstall()
			-- 4단계였는데 정원이 비고 가방에 씨앗 → 3
			local w2 = world(4)
			w2.BaseService.grantEgg(w2.player, "puppy_grass", "normal", {}, "dev")
			w2.TutorialService.onPlayerReady(w2.player)
			T.eq(w2.data.tutorialStep, 3)
			w2.H.uninstall()
		end
	)

	T.test("/tutorial reset 뒤 다시 끝내면 보상을 다시 받음 (개발 명령 시험용)", function()
		local w = world(5)
		w.data.fruits.sprout_daisy = { count = 2, value = 20 }
		goToStall(w)
		w.H.client(w.player, "SellFruits")
		T.eq(w.data.money, 20 + 500)
		w.TutorialService.reset(w.player)
		T.eq(w.data.tutorialStep, 1)
		T.eq(lastUpdate(w).step, 1)
		-- 순서대로 다시 (이미 열매가 있어도 1단계부터)
		w.data.fruits.sprout_daisy = { count = 1, value = 10 }
		w.H.advance(1)
		w.H.client(w.player, "SellFruits")
		T.eq(w.data.tutorialStep, 1, "건너뛰기 없음")
		w.H.carry(w.player, { petId = "puppy_grass", biomeId = "forest" })
		w.BaseService.deliver(w.player)
		T.eq(w.data.tutorialStep, 3)
		w.H.uninstall()
	end)

	T.test(
		"강아지풀 씨앗: 표 3초 → 7판 성장 3배로 1초 (밤이면 30배 → 1/30초), 숲 둥지에 나옴",
		function()
			local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
			local EggRoll = Loader.require("ReplicatedStorage/Shared/EggRoll")
			T.eq(Economy.growSeconds("puppy_grass"), 1)
			T.near(Economy.growSeconds("sprout_daisy"), 10 / 3, 1e-9, "아기 데이지는 표 10초 → 약 3.3초")
			T.truthy(EggRoll.nestOdds("forest", nil).puppy_grass > 0.1, "숲에서 자주 나옴")
		end
	)
end
