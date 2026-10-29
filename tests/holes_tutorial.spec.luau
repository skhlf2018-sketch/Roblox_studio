--!nocheck
--[[
	5판 주임 검수 — 구멍 찾기 1: 튜토리얼 (6판 "씨앗을 훔치세요" 단계로 고침: 심기 → 성체 → 열매 따서 팔기)
	  앞서 tutorial.spec 은 "가짜 EggService 신호"로 돌렸습니다. 여기서는 구멍을 찾으려고
	  1) 진짜 EggService(줍기·놓치기 전부)로 끝까지, 2) 진짜 DataService(저장·다시 접속)로 단계 유지,
	  3) 스키마 5 이하 → 6 초기화를 저장소를 거쳐서, 4) 신호 연결이 새지 않는지 봅니다.
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	-- 디렉터리 목록을 미리 다 읽어 둠 (Loader 가 파일을 읽는 일이 require 메타메서드 안에서 일어나면 안 되므로)
	local function warm(node)
		local getChildren = node.GetChildren
		for _, child in getChildren(node) do
			warm(child)
		end
	end
	warm(Loader.get("ServerScriptService"))
	warm(Loader.get("ReplicatedStorage"))

	local Tutorial = Loader.require("ReplicatedStorage/Shared/Data/Tutorial")
	local TutorialRules = Loader.require("ReplicatedStorage/Shared/TutorialRules")

	------------------------------------------------------------------
	-- 세상: 진짜 EggService + BaseService + PetService + FruitService + TutorialService + DataService
	------------------------------------------------------------------
	local function world()
		local H = ServerHarness.install(Loader, T, { realEgg = true })
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.MapLayout = H.MapLayout
		w.EggPlacement = H.shared("EggPlacement")
		w.Sessions = H.server("Sessions")
		w.Snapshot = H.server("Snapshot")
		w.DataSchema = H.server("Logic/DataSchema")
		w.DataService = H.server("Services/DataService")
		w.EggService = H.server("Services/EggService")
		w.BaseService = H.server("Services/BaseService")
		w.PetService = H.server("Services/PetService")
		w.FruitService = H.server("Services/FruitService")
		w.TutorialService = H.server("Services/TutorialService")
		w.DataService.start()
		w.EggService.start()
		w.BaseService.start()
		w.PetService.start()
		w.FruitService.start()
		w.TutorialService.start()
		H.setPhase("Intermission", 1) -- 첫 초기화: 둥지에 알
		H.setPhase("Day", 1)
		return w
	end

	-- PlayerLifecycle.onPlayerAdded 가 하는 일 중 튜토리얼에 필요한 만큼 (진짜 DataService.load 를 거침)
	local function join(w, userId, name)
		local player = w.H.newPlayer(userId, name or ("P" .. userId))
		local session = w.Sessions.create(player)
		local data, saveEnabled = w.H.run(function()
			return w.DataService.load(player)
		end)
		session.data = data
		session.saveEnabled = saveEnabled
		session.loaded = true
		session.plotIndex = 1
		local x, z = w.H.plotSpot(1)
		w.H.spawn(player, x, 3, z)
		w.PetService.onPlayerReady(player)
		w.FruitService.onPlayerReady(player)
		w.BaseService.onPlayerReady(player)
		w.TutorialService.onPlayerReady(player)
		w.Snapshot.send(player)
		return player, session, data
	end

	-- PlayerLifecycle.onPlayerRemoving: 든 알 놓기 → 베이스 비우기 → 저장 + 락 해제 → 세션 삭제
	local function leave(w, player)
		w.EggService.onPlayerLeaving(player)
		w.BaseService.onPlayerLeaving(player)
		local saved = w.H.run(function()
			return w.DataService.save(player, true)
		end)
		w.Sessions.remove(player)
		w.H.leave(player)
		return saved
	end

	local function updates(w, player)
		return w.H.sent(player, "TutorialUpdate")
	end

	local function lastView(w, player)
		local list = updates(w, player)
		return if #list > 0 then list[#list][1] else nil
	end

	local function steps(w, player)
		local out = {}
		for _, args in updates(w, player) do
			table.insert(out, args[1].step)
		end
		return out
	end

	-- 숲 둥지 알 하나를 E 키로 줍기 (프롬프트)
	local function steal(w, player)
		for _, egg in w.H.map.folders.Eggs.children do
			if egg:GetAttribute("BiomeId") == "forest" and egg:GetAttribute("EggState") == "Nest" then
				w.H.teleport(player, egg.Position.X, egg.Position.Y, egg.Position.Z)
				egg:FindFirstChild("StealPrompt").Triggered:Fire(player)
				if w.EggService.getCarried(player) then
					return egg
				end
			end
		end
		error("줍을 수 있는 숲 알이 없음")
	end

	-- 허브로 들어가 배달 (순간이동 검사를 쉬게 하고 충분히 시간이 흐른 뒤)
	local function walkIntoHub(w, player, session)
		w.H.advance(20)
		w.Sessions.exemptMovement(session, 5)
		local x, z = w.H.hubSpot()
		w.H.teleport(player, x, 3, z)
		w.H.advance(0.6) -- BaseService baseTick (0.2초마다) 가 배달
	end

	-- 가방 맨 뒤 씨앗을 정원 첫 빈자리에 심음
	local function placeLast(w, player, data)
		local egg = data.eggs[#data.eggs]
		local spots = {}
		for _, r in data.incubators do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		for _, r in data.pets do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		local l = w.EggPlacement.firstFreeGrid(egg.size, spots)
		local spot = w.MapLayout.toWorld(1, l.x, l.z)
		local x, z = w.H.plotSpot(1)
		w.H.teleport(player, x, 3, z)
		w.H.client(player, "PlaceEgg", egg.uid, spot.x, spot.z)
		return egg.uid
	end

	-- 6판: 심은 씨앗을 전부 다 자라게 하고 (개발 명령 /grow 처럼) 다음 1초 틱에 성체로
	local function growAll(w, data)
		for _, r in data.incubators do
			r.progress = r.required
		end
		w.H.advance(1.1)
	end

	-- 6판: 정원에서 열매를 전부 따고 → 허브 판매 가판대에서 팔기
	local function pickAndSell(w, player)
		local pen = w.MapLayout.penRect(1)
		w.H.teleport(player, (pen.xMin + pen.xMax) / 2, 3, (pen.zMin + pen.zMax) / 2)
		w.H.client(player, "PickFruit", "all")
		local stall = w.MapLayout.hubSpots.sellStall
		w.H.teleport(player, stall.x, 3, stall.z)
		w.H.client(player, "SellFruits")
	end

	------------------------------------------------------------------
	T.suite("6판 구멍 찾기: 튜토리얼 — 진짜 EggService 로 끝까지")

	T.test(
		"접속(1단계) → 줍기 2 → 허브 배달 3 → 심기 4 → 성체 5 → 열매 따서 팔기 끝 500 코인 (진짜 줍기·배달·성장·열매 코드)",
		function()
			local w = world()
			local player, session, data = join(w, 1001, "Newbie")
			T.eq(data.tutorialStep, 1, "새 사람은 1단계")
			T.eq(steps(w, player)[1], 1, "접속하자마자 TutorialUpdate 1단계")
			T.eq(w.Snapshot.build(player).tutorial.step, 1)
			steal(w, player)
			T.eq(data.tutorialStep, 2, "씨앗 줍기 → 2")
			walkIntoHub(w, player, session)
			T.eq(#data.eggs, 1, "허브에 들어오면 씨앗이 가방에")
			T.eq(data.tutorialStep, 3, "배달 → 3")
			placeLast(w, player, data)
			T.eq(#data.incubators, 1)
			T.eq(data.tutorialStep, 4, "심기 → 4")
			growAll(w, data)
			T.eq(#data.incubators, 0)
			T.eq(#data.pets, 1, "그 자리에서 성체")
			T.eq(data.tutorialStep, 5, "성체 → 5")
			T.eq(data.money, 0, "끝나기 전엔 보상 없음")
			local value = data.pets[1].fruits * w.H.shared("FruitRules").fruitValue(data.pets[1])
			pickAndSell(w, player)
			T.eq(data.tutorialStep, 6, "팔기 → 끝")
			T.near(data.money, value + Tutorial.REWARD_MONEY, 1e-9, "열매 값 + 500 코인")
			T.near(player.attrs.Money, data.money, 1e-9, "Money Attribute 도 같이")
			T.eq(table.concat(steps(w, player), ","), "1,2,3,4,5,6")
			local done = lastView(w, player)
			T.truthy(done.done)
			T.eq(done.reward, 500)
			w.H.uninstall()
		end
	)

	T.test(
		"든 알을 놓치는 모든 길(잡힘·방망이/곰덫 knockOut·드롭 버튼·죽음·치트 압수·순간이동 의심·나감)에서 2 → 1",
		function()
			local causes = {
				{
					"guard 잡힘",
					function(w, p)
						w.EggService.knockOut(p, w.H.vec(0, 0, 0), "guard", "덥석 파리지옥")
					end,
				},
				{
					"bat 맞음",
					function(w, p)
						w.EggService.knockOut(p, w.H.vec(0, 0, 0), "bat", "Bob")
					end,
				},
				{
					"trap 밟음",
					function(w, p)
						w.EggService.knockOut(p, nil, "trap", "곰덫")
					end,
				},
				{
					"드롭 버튼(Remote)",
					function(w, p)
						w.H.client(p, "DropEgg")
					end,
				},
				{
					"죽음",
					function(w, p)
						w.EggService.dropCarried(p, "death")
					end,
				},
				{
					"치트 의심 압수",
					function(w, p)
						w.EggService.confiscate(p)
					end,
				},
				{
					"순간이동 의심",
					function(w, p)
						w.EggService.dropCarriedAt(p, w.H.vec(0, 3, 50))
					end,
				},
				{
					"나감",
					function(w, p)
						w.EggService.onPlayerLeaving(p)
					end,
				},
			}
			for _, case in causes do
				local w = world()
				local player, _, data = join(w, 1001, "Newbie")
				steal(w, player)
				T.eq(data.tutorialStep, 2, case[1] .. ": 줍고 2")
				case[2](w, player)
				T.eq(w.EggService.getCarried(player), nil, case[1] .. ": 알을 놓침")
				T.eq(data.tutorialStep, 1, case[1] .. ": 다시 1단계")
				T.eq(lastView(w, player).step, 1, case[1] .. ": 화면에도 1단계")
				-- 놓쳤다 다시 주워도 정상 진행
				w.H.advance(3)
				steal(w, player)
				T.eq(data.tutorialStep, 2, case[1] .. ": 다시 주우면 2")
				w.H.uninstall()
			end
		end
	)

	T.test(
		"알을 든 채(2단계) 밤이 되면 서버가 베이스로 옮기고 → 가방에 들어가 3단계 (밤에도 튜토리얼이 안 막힘)",
		function()
			local w = world()
			local player, _, data = join(w, 1001, "Night")
			steal(w, player)
			T.eq(data.tutorialStep, 2)
			w.H.advance(20)
			w.H.setPhase("Night")
			w.H.advance(1)
			T.eq(#data.eggs, 1, "밤 귀가로 배달됨")
			T.eq(data.tutorialStep, 3)
			-- 밤에는 훔칠 수 없으니 3단계(놓기)로만 진행 가능: 놓기는 밤에도 됨
			w.H.uninstall()
		end
	)

	T.test(
		"3단계 이후에 알을 놓쳐도(두 번째 알) 단계는 그대로, 놓친 적 없는 1단계에서도 그대로",
		function()
			local w = world()
			local player, session, data = join(w, 1001, "Newbie")
			-- 1단계에서 알 없이 DropEgg / 죽음: 아무 일 없음
			w.H.client(player, "DropEgg")
			w.EggService.dropCarried(player, "death")
			T.eq(data.tutorialStep, 1)
			T.eq(#steps(w, player), 1, "TutorialUpdate 는 접속 때 한 번뿐")
			steal(w, player)
			walkIntoHub(w, player, session)
			T.eq(data.tutorialStep, 3)
			-- 3단계에서 두 번째 알을 줍고 놓쳐도 3
			w.H.advance(5)
			steal(w, player)
			T.eq(data.tutorialStep, 3, "3단계에서 또 줍기: 그대로")
			w.EggService.knockOut(player, w.H.vec(0, 0, 0), "guard", "덥석 파리지옥")
			T.eq(data.tutorialStep, 3, "3단계에서 놓치기: 그대로")
			w.H.uninstall()
		end
	)

	T.test(
		"끝난 뒤(6단계)에는 줍기·놓치기·배달·심기·성체·팔기를 해도 TutorialUpdate·보상 없음 (보상 한 번뿐)",
		function()
			local w = world()
			local player, session, data = join(w, 1001, "Veteran")
			data.tutorialStep = Tutorial.DONE
			local before = #updates(w, player)
			steal(w, player)
			w.EggService.dropCarried(player, "drop")
			w.H.advance(3)
			steal(w, player)
			walkIntoHub(w, player, session)
			T.eq(#data.eggs, 1)
			placeLast(w, player, data)
			growAll(w, data)
			T.eq(#data.pets, 1)
			local value = data.pets[1].fruits * w.H.shared("FruitRules").fruitValue(data.pets[1])
			pickAndSell(w, player)
			T.eq(#updates(w, player), before, "TutorialUpdate 없음")
			T.near(data.money, value, 1e-9, "열매 값만 (튜토리얼 보상 없음)")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("6판 구멍 찾기: 튜토리얼 — 진짜 DataService 로 저장·다시 접속")

	T.test(
		"단계마다 저장되고 다시 접속해도 같은 단계 (1·3·4·5·끝), 접속 때 그 단계를 다시 보냄",
		function()
			local w = world()
			local player = join(w, 2001, "Returner")
			-- 1단계에서 나갔다 옴
			T.truthy(leave(w, player))
			local p2, _, d2 = join(w, 2001, "Returner")
			T.eq(d2.tutorialStep, 1, "1단계 유지")
			T.eq(steps(w, p2)[1], 1)
			-- 3단계(가방에 씨앗)로 만들고 나갔다 옴
			steal(w, p2)
			local s2 = w.Sessions.get(p2)
			walkIntoHub(w, p2, s2)
			T.eq(d2.tutorialStep, 3)
			leave(w, p2)
			local p3, _, d3 = join(w, 2001, "Returner")
			T.eq(d3.tutorialStep, 3, "3단계 유지")
			T.eq(#d3.eggs, 1, "가방 씨앗도 유지")
			T.eq(lastView(w, p3).step, 3)
			-- 4단계(정원에 씨앗) — 오래 걸리는 씨앗이 되게 필요 시간을 늘림 (다시 접속하는 동안 성체가 되지 않게)
			placeLast(w, p3, d3)
			T.eq(d3.tutorialStep, 4)
			d3.incubators[1].petId = "rune_rose"
			d3.incubators[1].required = 86400
			leave(w, p3)
			local p4, _, d4 = join(w, 2001, "Returner")
			T.eq(d4.tutorialStep, 4, "4단계 유지")
			T.eq(#d4.incubators, 1)
			-- 5단계(성체가 됐지만 아직 안 팔았음)
			growAll(w, d4)
			T.eq(d4.tutorialStep, 5)
			leave(w, p4)
			local p5, _, d5 = join(w, 2001, "Returner")
			T.eq(d5.tutorialStep, 5, "5단계 유지")
			T.eq(#d5.pets, 1)
			-- 열매 따서 팔면 끝 → 나갔다 와도 끝이고, 다시 보상 없음
			pickAndSell(w, p5)
			T.eq(d5.tutorialStep, 6)
			local money = d5.money
			T.truthy(money >= 500)
			leave(w, p5)
			local p6, _, d6 = join(w, 2001, "Returner")
			T.eq(d6.tutorialStep, 6, "끝 유지")
			T.eq(d6.money, money, "보상은 한 번뿐 (다시 접속해도 안 늘어남)")
			T.eq(#updates(w, p6), 0, "끝난 사람은 접속해도 TutorialUpdate 없음")
			T.truthy(w.Snapshot.build(p6).tutorial.done)
			w.H.uninstall()
		end
	)

	T.test(
		"알을 든 채(2단계) 나가면 알은 사라지고 저장된 단계는 1, 돌아오면 1단계",
		function()
			local w = world()
			local player, _, data = join(w, 2002, "Runner")
			steal(w, player)
			T.eq(data.tutorialStep, 2)
			leave(w, player)
			local stored = w.H.store.data["player_2002"]
			T.eq(stored.data.tutorialStep, 1, "나갈 때 놓친 알 → 1단계로 저장")
			local p2, _, d2 = join(w, 2002, "Runner")
			T.eq(d2.tutorialStep, 1)
			T.eq(lastView(w, p2).step, 1)
			w.H.uninstall()
		end
	)

	T.test(
		"저장된 단계가 지금 상태와 안 맞으면 접속 때 맞춤: 3 → 씨앗 없음이면 1, 4 → 정원 비고 가방 있으면 3, 5 → 성체·열매 없음이면 1",
		function()
			local w = world()
			w.H.store.data["player_2003"] = {
				data = { version = 6, tutorialStep = 3, money = 12 },
			}
			local p, _, d = join(w, 2003, "Odd")
			T.eq(d.tutorialStep, 1, "3단계인데 가방 씨앗이 없음 → 1")
			T.eq(lastView(w, p).step, 1)
			w.H.store.data["player_2004"] = {
				data = {
					version = 6,
					tutorialStep = 4,
					eggs = {
						{ uid = "i1", petId = "puppy_grass", size = "normal", mutations = {}, biomeId = "forest" },
					},
				},
			}
			local p2, _, d2 = join(w, 2004, "Odd2")
			T.eq(d2.tutorialStep, 3, "4단계인데 정원이 비고 가방에 씨앗 → 3")
			T.eq(lastView(w, p2).step, 3)
			w.H.store.data["player_2005"] = { data = { version = 6, tutorialStep = 5 } }
			local p3, _, d3 = join(w, 2005, "Odd3")
			T.eq(d3.tutorialStep, 1, "5단계인데 성체도 열매도 씨앗도 없음 → 1")
			T.eq(lastView(w, p3).step, 1)
			w.H.store.data["player_2006"] = {
				data = { version = 6, tutorialStep = 5, fruits = { sprout_daisy = { count = 2, value = 20 } } },
			}
			local _, _, d4 = join(w, 2006, "Odd4")
			T.eq(d4.tutorialStep, 5, "열매만 있어도 5단계 그대로 (팔 수 있음)")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("6판 구멍 찾기: 튜토리얼 — 스키마 5 이하 → 6 (저장소를 거쳐서)")

	local function v5(extra)
		local raw = {
			version = 5,
			money = 777,
			speed = 10020,
			trails = { "grey" },
			equippedTrail = "grey",
			treadmillLevel = 3,
			pets = { { uid = "p1", petId = "chicken", size = "normal", mutations = {} } },
			equipped = { "p1" },
			tutorialStep = 6, -- 5판에서는 튜토리얼을 끝낸 사람
			stats = { eggsStolen = 50, eggsHatched = 20 },
		}
		for k, v in extra or {} do
			raw[k] = v
		end
		return raw
	end

	T.test(
		"5판에서 튜토리얼을 끝낸 사람도 6판은 새 게임 → 1단계부터, 속도·트레일·러닝머신은 그대로, 저장하면 7판(스키마 7) 모양",
		function()
			local w = world()
			w.H.store.data["player_3001"] = { data = v5() }
			local p, _, d = join(w, 3001, "Old")
			T.eq(d.version, 7)
			T.eq(d.tutorialStep, 1, "6판 튜토리얼 1단계부터")
			T.eq(lastView(w, p).step, 1, "TutorialUpdate 1단계")
			T.eq(d.speed, 10020, "속도 그대로")
			T.eq(d.treadmillLevel, 3, "러닝머신 그대로")
			T.eq(d.equippedTrail, "grey", "트레일 그대로")
			T.eq(d.money, 0, "코인은 처음부터")
			T.eq(#d.pets, 0, "5판 펫은 없어짐")
			T.eq(d.stats.eggsStolen, 0)
			leave(w, p)
			local stored = w.H.store.data["player_3001"].data
			T.eq(stored.version, 7)
			T.eq(stored.tutorialStep, 1)
			T.eq(stored.equipped, nil, "저장된 모양에도 장착 칸 없음")
			T.eq(stored.resetFromVersion, nil)
			T.eq(stored.speed, 10020)
			T.truthy(stored.fruits ~= nil, "열매 가방 칸")
			-- 다시 접속하면 그대로 (또 초기화하지 않음)
			local _, _, d2 = join(w, 3001, "Old")
			T.eq(d2.tutorialStep, 1)
			T.eq(d2.speed, 10020)
			w.H.uninstall()
		end
	)

	T.test(
		"6판 tutorialStep 값 경계: 없거나 이상하면 끝(튜토리얼 안 띄움), 음수는 1, 큰 값은 끝, 소수는 내림",
		function()
			local DataSchema = Loader.require("ServerScriptService/Server/Logic/DataSchema")
			T.eq(DataSchema.reconcile({ version = 6, money = 1 }, 0).tutorialStep, Tutorial.DONE)
			T.eq(DataSchema.reconcile({ version = 6, tutorialStep = "x" }, 0).tutorialStep, Tutorial.DONE)
			T.eq(DataSchema.reconcile({ version = 6, tutorialStep = 0 / 0 }, 0).tutorialStep, Tutorial.DONE)
			T.eq(DataSchema.reconcile({ version = 6, tutorialStep = -4 }, 0).tutorialStep, 1, "음수는 1")
			T.eq(
				DataSchema.reconcile({ version = 6, tutorialStep = 99 }, 0).tutorialStep,
				Tutorial.DONE,
				"큰 값은 끝"
			)
			T.eq(DataSchema.reconcile({ version = 6, tutorialStep = 2.9 }, 0).tutorialStep, 2, "소수는 내림")
			-- 5판 데이터의 가짜 tutorialStep 은 무시하고 1 (초기화)
			T.eq(DataSchema.reconcile(DataSchema.migrate(v5({ tutorialStep = 3 })), 0).tutorialStep, 1)
			-- 원본 표를 두 번 마이그레이션해도 같음
			local a = DataSchema.reconcile(DataSchema.migrate(v5()), 0)
			local b = DataSchema.reconcile(DataSchema.migrate(DataSchema.reconcile(DataSchema.migrate(v5()), 0)), 0)
			T.eq(a.tutorialStep, b.tutorialStep)
			T.eq(a.speed, b.speed)
		end
	)

	------------------------------------------------------------------
	T.suite("6판 구멍 찾기: 튜토리얼 — 신호 연결·정리")

	T.test(
		"TutorialService.start 는 7개 신호에 한 번씩만 연결, 사람이 오가도 연결이 늘지 않음 (사람별 연결 없음)",
		function()
			local w = world()
			local signals = {
				w.EggService.pickedUp,
				w.EggService.lost,
				w.BaseService.delivered,
				w.BaseService.placed,
				w.BaseService.unplaced,
				w.BaseService.grown,
				w.FruitService.sold,
			}
			local counts = {}
			for i, signal in signals do
				counts[i] = #signal.handlers
				T.truthy(counts[i] >= 1, "신호 #" .. i .. " 에 연결됨")
			end
			for i = 1, 12 do
				local player, session, data = join(w, 4000 + i, "Q" .. i)
				steal(w, player)
				if i % 2 == 0 then
					walkIntoHub(w, player, session)
					placeLast(w, player, data)
				end
				leave(w, player)
			end
			for i, signal in signals do
				T.eq(#signal.handlers, counts[i], "신호 #" .. i .. " 연결 수 그대로")
			end
			T.eq(w.BaseService.hatched, nil, "5판 부화 신호는 없음")
			T.eq(w.PetService.equipChanged, nil, "5판 장착 신호는 없음")
			w.H.uninstall()
		end
	)

	T.test(
		"start 를 두 번 불러도 단계가 두 번 오르거나 보상이 두 번 나가지 않음 (setStep 이 같은 단계면 무시)",
		function()
			local w = world()
			w.TutorialService.start() -- 실수로 한 번 더
			local player, _, data = join(w, 5001, "Twice")
			data.tutorialStep = 5
			data.fruits.sprout_daisy = { count = 1, value = 10 }
			local stall = w.MapLayout.hubSpots.sellStall
			w.H.teleport(player, stall.x, 3, stall.z)
			w.H.client(player, "SellFruits")
			T.eq(data.tutorialStep, 6)
			T.eq(data.money, 10 + 500, "보상은 한 번")
			w.H.uninstall()
		end
	)

	T.test("5단계: 성체가 생겨도(개발 명령 /plant 처럼) 팔기 전에는 안 끝남", function()
		local w = world()
		local player, _, data = join(w, 5009, "Auto")
		data.tutorialStep = 5
		w.PetService.addPlant(player, {
			uid = "p9",
			petId = "sprout_daisy",
			size = "normal",
			mutations = {},
			x = -20,
			z = 0,
			fruits = 1,
			fruitProgress = 0,
		})
		T.eq(data.tutorialStep, 5)
		T.eq(data.money, 0)
		w.H.uninstall()
	end)

	T.test(
		"튜토리얼 중 SellFruits 가 거부돼도(판매 가판대에서 멂·빈 가방) 단계는 안 오름",
		function()
			local w = world()
			local player, _, data = join(w, 5002, "Stuck")
			data.tutorialStep = 5
			data.fruits.sprout_daisy = { count = 1, value = 10 }
			w.H.teleport(player, 0, 3, 500) -- 구역 안 (가판대에서 멂)
			w.H.client(player, "SellFruits")
			T.eq(data.tutorialStep, 5)
			T.eq(data.money, 0)
			data.fruits.sprout_daisy = nil
			local stall = w.MapLayout.hubSpots.sellStall
			w.H.advance(2)
			w.H.teleport(player, stall.x, 3, stall.z)
			w.H.client(player, "SellFruits") -- 빈 가방
			T.eq(data.tutorialStep, 5)
			T.eq(data.money, 0)
			w.H.uninstall()
		end
	)

	T.test(
		"리셋(/tutorial reset) 후 놓친 씨앗·이미 있는 성체가 있어도 순서대로 다시 (같은 단계 두 번 안 보냄)",
		function()
			local w = world()
			local player, session, data = join(w, 5003, "Again")
			data.tutorialStep = Tutorial.DONE
			w.TutorialService.reset(player)
			T.eq(data.tutorialStep, 1)
			T.eq(lastView(w, player).step, 1)
			steal(w, player)
			walkIntoHub(w, player, session)
			placeLast(w, player, data)
			growAll(w, data)
			T.eq(data.tutorialStep, 5)
			pickAndSell(w, player)
			T.eq(data.tutorialStep, 6)
			T.truthy(data.money >= 500, "다시 끝내면 다시 받음 (개발 명령 한정)")
			w.H.uninstall()
		end
	)

	T.test(
		"순수 규칙 구멍: advance 는 모르는 사건·모르는 단계에도 안 터지고 같은 값",
		function()
			local c = { carrying = false, bagEggs = 0, placedEggs = 0, plants = 0, fruits = 0 }
			T.eq(TutorialRules.advance(3, "wat", c), 3)
			T.eq(TutorialRules.advance(0, "steal", c), 0, "0단계(이상한 값)는 steal 에 안 올라감")
			T.eq(TutorialRules.advance(99, "steal", c), 99)
			for step = 1, 6 do
				for _, event in { "steal", "lost", "deliver", "place", "unplace", "grown", "sell" } do
					local out = TutorialRules.advance(step, event, c)
					T.truthy(out >= step - 1 and out <= Tutorial.DONE, step .. "/" .. event .. " → " .. out)
					-- 한 번에 두 단계 이상 뛰지 않음 (deliver 1 → 3, grown 3 → 5 만 예외)
					if event ~= "deliver" and event ~= "grown" then
						T.truthy(out - step <= 1, step .. "/" .. event .. " 두 단계 이상 뜀")
					end
				end
			end
		end
	)
end
