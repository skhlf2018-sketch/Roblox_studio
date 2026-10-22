--!nocheck
--[[
	5판 주임 검수 — 구멍 찾기 1: 튜토리얼
	  앞서 tutorial.spec 은 "가짜 EggService 신호"로 돌렸습니다. 여기서는 구멍을 찾으려고
	  1) 진짜 EggService(줍기·놓치기 전부)로 끝까지, 2) 진짜 DataService(저장·다시 접속)로 단계 유지,
	  3) 스키마 4 → 5 마이그레이션을 저장소를 거쳐서, 4) 신호 연결이 새지 않는지 봅니다.
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
	-- 세상: 진짜 EggService + BaseService + PetService + TutorialService + DataService
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
		w.TutorialService = H.server("Services/TutorialService")
		w.DataService.start()
		w.EggService.start()
		w.BaseService.start()
		w.PetService.start()
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

	-- 가방 맨 뒤 알을 우리 첫 빈자리에 놓음
	local function placeLast(w, player, data)
		local egg = data.eggs[#data.eggs]
		local spots = {}
		for _, r in data.incubators do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		local l = w.EggPlacement.firstFreeGrid(egg.size, spots)
		local spot = w.MapLayout.toWorld(1, l.x, l.z)
		local x, z = w.H.plotSpot(1)
		w.H.teleport(player, x, 3, z)
		w.H.client(player, "PlaceEgg", egg.uid, spot.x, spot.z)
		return egg.uid
	end

	------------------------------------------------------------------
	T.suite("5판 구멍 찾기: 튜토리얼 — 진짜 EggService 로 끝까지")

	T.test(
		"접속(1단계) → 줍기 2 → 허브 배달 3 → 놓기 4 → 부화 5 → 장착 끝 $500 (진짜 줍기·배달·부화 코드)",
		function()
			local w = world()
			local player, session, data = join(w, 1001, "Newbie")
			T.eq(data.tutorialStep, 1, "새 사람은 1단계")
			T.eq(steps(w, player)[1], 1, "접속하자마자 TutorialUpdate 1단계")
			T.eq(w.Snapshot.build(player).tutorial.step, 1)
			steal(w, player)
			T.eq(data.tutorialStep, 2, "알 줍기 → 2")
			walkIntoHub(w, player, session)
			T.eq(#data.eggs, 1, "허브에 들어오면 알이 가방에")
			T.eq(data.tutorialStep, 3, "배달 → 3")
			placeLast(w, player, data)
			T.eq(#data.incubators, 1)
			T.eq(data.tutorialStep, 4, "놓기 → 4")
			local record = data.incubators[1]
			record.progress = record.required -- /grow
			w.H.client(player, "HatchEgg", record.uid)
			T.eq(#data.pets, 1)
			T.eq(#data.equipped, 0, "튜토리얼 중엔 자동 장착 안 함")
			T.eq(data.tutorialStep, 5, "부화 → 5")
			T.eq(data.money, 0, "끝나기 전엔 보상 없음")
			w.H.client(player, "EquipPet", data.pets[1].uid)
			T.eq(data.tutorialStep, 6, "장착 → 끝")
			T.eq(data.money, Tutorial.REWARD_MONEY, "$500")
			T.eq(player.attrs.Money, Tutorial.REWARD_MONEY, "Money Attribute 도 같이")
			-- 단계 알림 순서: 1(접속) 2 3 4 5 6(끝)
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
						w.EggService.knockOut(p, w.H.vec(0, 0, 0), "guard", "닭")
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
			w.EggService.knockOut(player, w.H.vec(0, 0, 0), "guard", "닭")
			T.eq(data.tutorialStep, 3, "3단계에서 놓치기: 그대로")
			w.H.uninstall()
		end
	)

	T.test(
		"끝난 뒤(6단계)에는 줍기·놓치기·배달·부화·장착을 해도 TutorialUpdate·돈 변화 없음 (보상 한 번뿐)",
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
			data.incubators[1].progress = data.incubators[1].required
			w.H.client(player, "HatchEgg", data.incubators[1].uid)
			T.eq(#data.equipped, 1, "끝난 사람은 자동 장착")
			w.H.client(player, "EquipBest")
			w.H.client(player, "UnequipPet", data.pets[1].uid)
			w.H.client(player, "EquipPet", data.pets[1].uid)
			T.eq(#updates(w, player), before, "TutorialUpdate 없음")
			T.eq(data.money, 0, "돈 변화 없음")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("5판 구멍 찾기: 튜토리얼 — 진짜 DataService 로 저장·다시 접속")

	T.test(
		"단계마다 저장되고 다시 접속해도 같은 단계 (1·3·4·5·끝), 접속 때 그 단계를 다시 보냄",
		function()
			local w = world()
			local player, session, data = join(w, 2001, "Returner")
			-- 1단계에서 나갔다 옴
			T.truthy(leave(w, player))
			local p2, _, d2 = join(w, 2001, "Returner")
			T.eq(d2.tutorialStep, 1, "1단계 유지")
			T.eq(steps(w, p2)[1], 1)
			-- 3단계(가방에 알)로 만들고 나갔다 옴
			steal(w, p2)
			local s2 = w.Sessions.get(p2)
			walkIntoHub(w, p2, s2)
			T.eq(d2.tutorialStep, 3)
			leave(w, p2)
			local p3, _, d3 = join(w, 2001, "Returner")
			T.eq(d3.tutorialStep, 3, "3단계 유지")
			T.eq(#d3.eggs, 1, "가방 알도 유지")
			T.eq(lastView(w, p3).step, 3)
			-- 4단계(우리에 알)
			placeLast(w, p3, d3)
			T.eq(d3.tutorialStep, 4)
			leave(w, p3)
			local p4, _, d4 = join(w, 2001, "Returner")
			T.eq(d4.tutorialStep, 4, "4단계 유지")
			T.eq(#d4.incubators, 1)
			-- 5단계(펫을 부화했지만 장착 안 함)
			d4.incubators[1].progress = d4.incubators[1].required
			w.H.client(p4, "HatchEgg", d4.incubators[1].uid)
			T.eq(d4.tutorialStep, 5)
			leave(w, p4)
			local p5, _, d5 = join(w, 2001, "Returner")
			T.eq(d5.tutorialStep, 5, "5단계 유지")
			T.eq(#d5.pets, 1)
			T.eq(#d5.equipped, 0)
			-- 장착해서 끝 → 나갔다 와도 끝이고, 다시 보상 없음
			w.H.client(p5, "EquipPet", d5.pets[1].uid)
			T.eq(d5.tutorialStep, 6)
			T.eq(d5.money, 500)
			leave(w, p5)
			local p6, _, d6 = join(w, 2001, "Returner")
			T.eq(d6.tutorialStep, 6, "끝 유지")
			T.eq(d6.money, 500, "보상은 한 번뿐 (다시 접속해도 안 늘어남)")
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
		"저장된 단계가 지금 상태와 안 맞으면 접속 때 맞춤 (옛 저장·강제 종료로 알이 사라진 경우): 3 → 알 없음이면 1, 4 → 우리 비면 가방 있으면 3",
		function()
			local w = world()
			-- 3단계인데 가방이 비어 있음 (저장 직전 알을 놓고 단계는 아직 못 올린 경우 등)
			w.H.store.data["player_2003"] = {
				data = { version = 5, tutorialStep = 3, money = 12 },
			}
			local p, _, d = join(w, 2003, "Odd")
			T.eq(d.tutorialStep, 1, "3단계인데 가방 알이 없음 → 1")
			T.eq(lastView(w, p).step, 1)
			-- 4단계인데 우리는 비고 가방에 알이 있음
			w.H.store.data["player_2004"] = {
				data = {
					version = 5,
					tutorialStep = 4,
					eggs = { { uid = "i1", petId = "dog", size = "normal", mutations = {}, biomeId = "forest" } },
				},
			}
			local p2, _, d2 = join(w, 2004, "Odd2")
			T.eq(d2.tutorialStep, 3, "4단계인데 우리가 비고 가방에 알 → 3")
			T.eq(lastView(w, p2).step, 3)
			-- 5단계인데 펫이 하나도 없음
			w.H.store.data["player_2005"] = { data = { version = 5, tutorialStep = 5 } }
			local p3, _, d3 = join(w, 2005, "Odd3")
			T.eq(d3.tutorialStep, 1, "5단계인데 펫도 알도 없음 → 1")
			T.eq(lastView(w, p3).step, 1)
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("5판 구멍 찾기: 튜토리얼 — 스키마 4 → 5 (저장소를 거쳐서)")

	local function v4(extra)
		local raw = {
			version = 4,
			money = 777,
			speed = 10020, -- 무료 보상 +10,000 을 받았던 사람
			freeRewardClaimed = true,
			quests = { deliver_eggs = 20, fuse_once = 1, deliver_eternal = 1 },
			questsRewarded = true,
			stats = { eggsStolen = 0, eggsHatched = 0 },
		}
		for k, v in extra or {} do
			raw[k] = v
		end
		return raw
	end

	T.test(
		"펫 있는 4판 저장 → 접속하면 끝 상태(튜토리얼 안 뜸), quests·questsRewarded·freeRewardClaimed 칸 삭제, 저장하면 5판 모양",
		function()
			local w = world()
			w.H.store.data["player_3001"] = {
				data = v4({
					pets = { { uid = "p1", petId = "chicken", size = "normal", mutations = {} } },
					nextUid = 2,
				}),
			}
			local p, _, d = join(w, 3001, "Old")
			T.eq(d.version, 5)
			T.eq(d.tutorialStep, Tutorial.DONE, "펫이 있는 사람은 끝")
			T.eq(d.quests, nil)
			T.eq(d.questsRewarded, nil)
			T.eq(d.freeRewardClaimed, nil)
			T.eq(d.speed, 10020, "무료 보상으로 받은 속도는 그대로")
			T.eq(d.money, 777)
			T.eq(#updates(w, p), 0, "튜토리얼 안 뜸")
			T.truthy(w.Snapshot.build(p).tutorial.done)
			leave(w, p)
			local stored = w.H.store.data["player_3001"].data
			T.eq(stored.version, 5)
			T.eq(stored.tutorialStep, Tutorial.DONE)
			T.eq(stored.quests, nil, "저장된 모양에도 quests 없음")
			T.eq(stored.questsRewarded, nil)
			T.eq(stored.freeRewardClaimed, nil)
			w.H.uninstall()
		end
	)

	T.test(
		"아무것도 안 한 4판 저장 → 새 사람처럼 1단계, TutorialUpdate 1단계, 받은 속도·돈은 그대로",
		function()
			local w = world()
			w.H.store.data["player_3002"] = { data = v4() }
			local p, _, d = join(w, 3002, "Fresh")
			T.eq(d.tutorialStep, 1)
			T.eq(lastView(w, p).step, 1)
			T.eq(d.quests, nil)
			T.eq(d.speed, 10020)
			T.eq(d.money, 777)
			w.H.uninstall()
		end
	)

	T.test(
		"놀던 흔적 6가지(펫·놓인 알·가방 알·훔침·배달·부화 기록) 중 하나만 있어도 끝, 빈 표·글자 숫자는 '안 놀았음'",
		function()
			local played = {
				{ pets = { { uid = "p1", petId = "chicken", size = "normal", mutations = {} } } },
				{ incubators = { { uid = "i1", petId = "dog", size = "normal", mutations = {}, x = -20, z = 0 } } },
				{ eggs = { { uid = "i2", petId = "dog", size = "normal", mutations = {} } } },
				{ stats = { eggsStolen = 1 } },
				{ stats = { eggsDelivered = 1 } },
				{ stats = { eggsHatched = 1 } },
			}
			local w = world()
			for i, extra in played do
				w.H.store.data["player_" .. (3100 + i)] = { data = v4(extra) }
				local _, _, d = join(w, 3100 + i, "Played" .. i)
				T.eq(d.tutorialStep, Tutorial.DONE, "놀던 사람 #" .. i)
			end
			local notPlayed = {
				{ pets = {}, eggs = {}, incubators = {} },
				{ stats = { eggsStolen = 0, eggsDelivered = 0, eggsHatched = 0 } },
				{ stats = { eggsStolen = "9" } },
				{ stats = { eggsStolen = -3 } },
				{ pets = "x", eggs = 5 },
			}
			for i, extra in notPlayed do
				w.H.store.data["player_" .. (3200 + i)] = { data = v4(extra) }
				local _, _, d = join(w, 3200 + i, "Idle" .. i)
				T.eq(d.tutorialStep, 1, "안 놀았음 #" .. i)
			end
			w.H.uninstall()
		end
	)

	T.test(
		"마이그레이션은 두 번 해도 같고(멱등), 이미 5판인 단계는 건드리지 않고, 원본 표를 안 망가뜨림",
		function()
			local DataSchema = Loader.require("ServerScriptService/Server/Logic/DataSchema")
			local base = v4({ pets = { { uid = "p1", petId = "chicken", size = "normal", mutations = {} } } })
			local a = DataSchema.reconcile(DataSchema.migrate(base), 0)
			local b = DataSchema.reconcile(
				DataSchema.migrate(DataSchema.reconcile(
					DataSchema.migrate(v4({
						pets = { { uid = "p1", petId = "chicken", size = "normal", mutations = {} } },
					})),
					0
				)),
				0
			)
			T.eq(a.tutorialStep, b.tutorialStep)
			T.eq(a.version, 5)
			-- 5판 3단계 데이터는 3 그대로
			local v5 = DataSchema.reconcile(DataSchema.migrate(v4()), 0)
			v5.tutorialStep = 3
			T.eq(DataSchema.reconcile(DataSchema.migrate(v5), 0).tutorialStep, 3)
			-- 4판에 tutorialStep 칸이 억지로 들어 있어도(조작) 4 → 5 에서는 "놀았나"로 다시 정함
			local tampered = DataSchema.migrate(v4({ tutorialStep = 6 }))
			T.eq(tampered.tutorialStep, 1, "아무것도 안 한 4판 저장의 가짜 tutorialStep=6 은 무시")
			-- 5판인데 tutorialStep 이 없거나 이상하면 튜토리얼 안 띄움(끝으로)
			T.eq(DataSchema.reconcile({ version = 5, money = 1 }, 0).tutorialStep, Tutorial.DONE)
			T.eq(DataSchema.reconcile({ version = 5, tutorialStep = "x" }, 0).tutorialStep, Tutorial.DONE)
			T.eq(DataSchema.reconcile({ version = 5, tutorialStep = 0 / 0 }, 0).tutorialStep, Tutorial.DONE)
			T.eq(DataSchema.reconcile({ version = 5, tutorialStep = -4 }, 0).tutorialStep, 1, "음수는 1")
			T.eq(
				DataSchema.reconcile({ version = 5, tutorialStep = 99 }, 0).tutorialStep,
				Tutorial.DONE,
				"큰 값은 끝"
			)
			T.eq(DataSchema.reconcile({ version = 5, tutorialStep = 2.9 }, 0).tutorialStep, 2, "소수는 내림")
		end
	)

	------------------------------------------------------------------
	T.suite("5판 구멍 찾기: 튜토리얼 — 신호 연결·정리")

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
				w.BaseService.hatched,
				w.PetService.equipChanged,
			}
			local counts = {}
			for i, signal in signals do
				counts[i] = #signal.handlers
				T.truthy(counts[i] >= 1, "신호 #" .. i .. " 에 연결됨")
			end
			-- 사람 12명이 접속해서 튜토리얼을 하고 나감
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
			w.PetService.addPet(player, { uid = "p1", petId = "chicken", size = "normal", mutations = {} }, false)
			w.H.client(player, "EquipPet", "p1")
			T.eq(data.tutorialStep, 6)
			T.eq(data.money, 500, "보상은 한 번")
			w.H.uninstall()
		end
	)

	-- 알려진 약점 (Low): PetService.addPet 이 빈 칸에 펫을 "자동 장착"해도 equipChanged 신호는 EquipPet / EquipBest 때만 나감.
	-- 그래서 5단계에서 퓨전(FusionService)·개발 명령 /pet 으로 펫이 자동 장착되면 장착 펫이 있는데도 튜토리얼이 안 끝남
	-- (펫 창에서 한 번 해제했다 다시 장착하거나 '모두 장착'을 눌러야 끝남). 고치는 법: addPet 이 자동 장착했으면 equipChanged:fire.
	T.skip(
		"5단계에서 펫이 자동 장착되면(퓨전·/pet) 바로 튜토리얼 끝 ($500)",
		"PetService.addPet 의 자동 장착은 equipChanged 를 안 내서 5단계가 안 끝남",
		function()
			local w = world()
			local player, _, data = join(w, 5009, "Auto")
			data.tutorialStep = 5
			w.PetService.addPet(player, { uid = "p9", petId = "chicken", size = "normal", mutations = {} }) -- 자동 장착
			w.H.uninstall()
			T.eq(#data.equipped, 1, "자동 장착은 됨")
			T.eq(data.tutorialStep, 6, "장착 펫이 있는데 아직 " .. data.tutorialStep .. "단계")
		end
	)

	T.test("튜토리얼 중 EquipPet 이 거부돼도(우리 가득·없는 펫) 단계는 안 오름", function()
		local w = world()
		local player, _, data = join(w, 5002, "Stuck")
		data.tutorialStep = 5
		w.PetService.addPet(player, { uid = "p1", petId = "chicken", size = "normal", mutations = {} }, false)
		w.H.client(player, "EquipPet", "nope")
		w.H.client(player, "EquipPet", "p1;drop")
		w.H.client(player, "EquipPet", 5)
		T.eq(data.tutorialStep, 5)
		T.eq(data.money, 0)
		w.H.uninstall()
	end)

	T.test(
		"리셋(/tutorial reset) 후 놓친 알·이미 있는 펫이 있어도 순서대로 다시 (같은 단계 두 번 안 보냄)",
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
			data.incubators[1].progress = data.incubators[1].required
			w.H.client(player, "HatchEgg", data.incubators[1].uid)
			T.eq(data.tutorialStep, 5)
			T.eq(#data.equipped, 0, "리셋한 사람도 튜토리얼 중엔 자동 장착 안 함")
			w.H.client(player, "EquipPet", data.pets[1].uid)
			T.eq(data.tutorialStep, 6)
			T.eq(data.money, 500, "다시 끝내면 다시 받음 (개발 명령 한정)")
			w.H.uninstall()
		end
	)

	T.test(
		"순수 규칙 구멍: advance 는 모르는 사건·모르는 단계에도 안 터지고 같은 값",
		function()
			local c = { carrying = false, bagEggs = 0, placedEggs = 0, pets = 0, equipped = 0 }
			T.eq(TutorialRules.advance(3, "wat", c), 3)
			T.eq(TutorialRules.advance(0, "steal", c), 0, "0단계(이상한 값)는 steal 에 안 올라감")
			T.eq(TutorialRules.advance(99, "steal", c), 99)
			for step = 1, 6 do
				for _, event in { "steal", "lost", "deliver", "place", "unplace", "hatch", "equip" } do
					local out = TutorialRules.advance(step, event, c)
					T.truthy(out >= step - 1 and out <= Tutorial.DONE, step .. "/" .. event .. " → " .. out)
					-- 한 번에 두 단계 이상 뛰지 않음 (deliver 1 → 3, hatch 3 → 5 만 예외)
					if event ~= "deliver" and event ~= "hatch" then
						T.truthy(out - step <= 1, step .. "/" .. event .. " 두 단계 이상 뜀")
					end
				end
			end
		end
	)
end
