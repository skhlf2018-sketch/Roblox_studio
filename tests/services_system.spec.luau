--!nocheck
--[[
	서비스 테스트 3: AntiCheatService(위치 검증·경고·Kick), DevCommands(채팅 명령), DataService(저장·세션 락·재시도)
	가짜 DataStore(UpdateAsync 취소/실패/재시도 흉내) 와 가상 시간 위에서 진짜 코드를 돌립니다.
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function world()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.DataSchema = H.server("Logic/DataSchema")
		w.PetService = H.server("Services/PetService")
		w.player = H.newPlayer(1001, "Tester")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		return w
	end

	------------------------------------------------------------------
	T.suite("서비스: AntiCheatService (속도핵·순간이동 감시)")

	local function cheatWorld()
		local w = world()
		w.AntiCheat = w.H.server("Services/AntiCheatService")
		w.AntiCheat.start()
		w.H.spawn(w.player, 0, 3, 0)
		w.H.advance(1) -- 첫 검사: 기준 위치 기록
		return w
	end

	local function moveBy(w, dx)
		local root = w.player.Character.root
		w.H.teleport(w.player, root.Position.X + dx, 3, 0)
		w.H.advance(1)
	end

	T.test(
		"걷는 속도(WalkSpeed × 1.5 + 30 이하)는 아무 일 없음, 정확히 경계 54 도 통과",
		function()
			local w = cheatWorld()
			for _ = 1, 10 do
				moveBy(w, 15)
			end
			moveBy(w, 54) -- 16 × 1.5 + 30 = 54 (경계 포함)
			T.eq(w.player.attrs.MoveWarnings, nil)
			T.eq(w.player.kicked, nil)
			w.H.uninstall()
		end
	)

	T.test("1초에 54.2 스터드 이동 → 제자리로 되돌리고 경고 1 + 알림", function()
		local w = cheatWorld()
		moveBy(w, 54.2)
		T.eq(w.player.attrs.MoveWarnings, 1)
		T.eq(w.player.Character.root.Position.X, 0, "마지막 정상 위치로 되돌림")
		T.truthy(w.H.hasNotify(w.player, "error", "(1/5)"))
		w.H.uninstall()
	end)

	T.test("경고가 5개 쌓이면 Kick (4개까지는 안 쫓겨남)", function()
		local w = cheatWorld()
		for i = 1, 4 do
			moveBy(w, 500)
			T.eq(w.player.attrs.MoveWarnings, i)
			T.eq(w.player.kicked, nil)
		end
		moveBy(w, 500)
		T.truthy(w.player.kicked, "5번째에 Kick")
		T.truthy(string.find(w.player.kicked, "비정상", 1, true))
		w.H.uninstall()
	end)

	T.test("경고는 120초마다 1개씩 줄어듦 (렉 오탐이 쌓이지 않게)", function()
		local w = cheatWorld()
		for _ = 1, 3 do
			moveBy(w, 500)
		end
		T.eq(w.player.attrs.MoveWarnings, 3)
		w.H.advance(125)
		T.eq(w.player.attrs.MoveWarnings, 2)
		w.H.advance(120)
		T.eq(w.player.attrs.MoveWarnings, 1)
		w.H.advance(120)
		T.eq(w.player.attrs.MoveWarnings, 0)
		w.H.uninstall()
	end)

	T.test("쉬는 경우: 래그돌·곰덫(기절), 서버 순간이동 직후, 앉음, 죽음", function()
		local w = cheatWorld()
		-- 기절 중
		w.session.stunnedUntil = w.H.clock() + 5
		moveBy(w, 500)
		T.eq(w.player.attrs.MoveWarnings, nil, "기절 중")
		w.H.advance(6)
		-- 서버가 순간이동시킨 직후
		local Sessions = w.H.server("Sessions")
		Sessions.exemptMovement(w.session, 3)
		moveBy(w, 500)
		T.eq(w.player.attrs.MoveWarnings, nil, "서버 순간이동 직후")
		w.H.advance(4)
		-- 앉음 / 죽음
		w.player.Character.humanoid.Sit = true
		moveBy(w, 500)
		w.player.Character.humanoid.Sit = false
		w.player.Character.humanoid.Health = 0
		moveBy(w, 500)
		w.player.Character.humanoid.Health = 100
		T.eq(w.player.attrs.MoveWarnings, nil)
		w.H.advance(2)
		-- 쉬는 게 끝나면 다시 감시
		moveBy(w, 500)
		T.eq(w.player.attrs.MoveWarnings, 1)
		w.H.uninstall()
	end)

	T.test("WalkSpeed 가 빠르면(러닝머신으로 속도 상승) 허용 거리도 커짐", function()
		local w = cheatWorld()
		w.session.walkSpeed = 100 -- 허용 100 × 1.5 + 30 = 180
		moveBy(w, 170)
		T.eq(w.player.attrs.MoveWarnings, nil)
		moveBy(w, 200)
		T.eq(w.player.attrs.MoveWarnings, 1)
		w.H.uninstall()
	end)

	T.test("나간 플레이어는 기록이 지워지고 오류 없음", function()
		local w = cheatWorld()
		moveBy(w, 500)
		w.H.leave(w.player)
		w.H.advance(3)
		T.truthy(true)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: DevCommands (스튜디오 채팅 명령 — 사장님 체크리스트에 나오는 것들)")

	local function devWorld(studio)
		local w = world()
		w.H.RunService.studio = studio ~= false
		w.H.server("Services/SakuraService")
		w.DevCommands = w.H.server("Services/DevCommands")
		w.DevCommands.start()
		w.H.spawn(w.player, 0, 3, 0)
		return w
	end

	local function chat(w, message, player)
		(player or w.player).Chatted:Fire(message)
	end

	T.test("/money /speed: 숫자(1e9 도 됨)만큼 더함, 이상한 값은 무시", function()
		local w = devWorld()
		chat(w, "/money 1e9")
		T.eq(w.data.money, 1e9)
		chat(w, "/money 500")
		T.eq(w.data.money, 1e9 + 500)
		chat(w, "/speed 1e6")
		T.eq(w.data.speed, w.Config.STARTING_SPEED + 1e6)
		for _, bad in
			{
				"/money",
				"/money abc",
				"/money -5",
				"/money 0",
				"/money 1e999",
				"/money nan",
				"/없는명령 5",
				"money 5",
				"안녕",
			}
		do
			chat(w, bad)
		end
		T.eq(w.data.money, 1e9 + 500)
		T.eq(w.data.speed, w.Config.STARTING_SPEED + 1e6)
		T.truthy(w.H.hasNotify(w.player, "info", "[개발] /money 1e9"))
		w.H.uninstall()
	end)

	T.test(
		"/zone lake · /zone 15 · /zone hub: 구역 입구·허브로 서버 순간이동 (위치 검증 쉼), 없는 구역은 무시",
		function()
			local w = devWorld()
			local MapLayout = w.H.shared("Data/MapLayout")
			chat(w, "/zone lake")
			T.eq(w.player.Character.root.Position.Z, MapLayout.biome("lake").zMin + 12)
			T.eq(MapLayout.zoneAt(w.player.Character.root.Position.Z), "lake")
			T.truthy(w.session.moveExemptUntil > w.H.clock(), "위치 검증 쉼")
			chat(w, "/zone 15")
			T.eq(MapLayout.zoneAt(w.player.Character.root.Position.Z), "haunted_castle")
			chat(w, "/zone hub")
			T.eq(w.player.Character.root.Position.Z, MapLayout.hubSpots.mainSpawn.z)
			chat(w, "/zone 99")
			chat(w, "/zone moon")
			T.eq(w.player.Character.root.Position.Z, MapLayout.hubSpots.mainSpawn.z, "그대로")
			w.H.uninstall()
		end
	)

	T.test("/skip: 낮/밤 단계를 넘김 요청, /grow: 부화 슬롯 알을 다 자란 상태로", function()
		local w = devWorld()
		chat(w, "/skip")
		T.eq(w.H.cycle.skipped, 1)
		w.PetService.recalc(w.player)
		local B = w.H.server("Services/BaseService")
		B.grantEgg(w.player, "ghost_king", "normal", {}, "altar")
		B.grantEgg(w.player, "yeti", "normal", {}, "altar")
		chat(w, "/grow")
		for _, record in w.data.incubators do
			T.eq(record.progress, record.required)
		end
		w.H.uninstall()
	end)

	T.test("/trap 5: 곰덫 +5 (처음 3개), /crystal 5: 사쿠라 크리스탈", function()
		local w = devWorld()
		T.eq(w.data.tools.bearTrap, w.Config.STARTING_BEAR_TRAPS)
		chat(w, "/trap 5")
		T.eq(w.data.tools.bearTrap, w.Config.STARTING_BEAR_TRAPS + 5)
		chat(w, "/trap 2.9")
		T.eq(w.data.tools.bearTrap, w.Config.STARTING_BEAR_TRAPS + 7, "소수는 내림")
		chat(w, "/crystal 5")
		T.eq(w.data.sakuraCrystals, 5)
		T.eq(w.player.attrs.SakuraCrystals, 5)
		w.H.uninstall()
	end)

	T.test(
		"/pet 이름 개수: 펫 바로 받기 (도감에도 기록), 최대 20마리, 없는 이름은 무시",
		function()
			local w = devWorld()
			chat(w, "/pet crane 3")
			T.eq(#w.data.pets, 3)
			T.eq(w.data.pets[1].petId, "crane")
			T.truthy(w.data.indexDiscovered.crane)
			chat(w, "/pet chicken")
			T.eq(#w.data.pets, 4, "개수를 안 쓰면 1마리")
			chat(w, "/pet dog 99")
			T.eq(#w.data.pets, 24, "한 번에 최대 20마리")
			chat(w, "/pet 없는펫 3")
			chat(w, "/pet")
			T.eq(#w.data.pets, 24)
			w.H.uninstall()
		end
	)

	T.test("/quests: 마법의 숲 퀘스트 3개를 한 번에 끝냄 (문 열림 + 지터버그 알)", function()
		local w = devWorld()
		chat(w, "/quests")
		T.truthy(w.data.questsRewarded)
		T.eq(w.data.quests.deliver_eggs, 20)
		T.eq(w.data.quests.fuse_once, 1)
		T.eq(w.data.quests.deliver_eternal, 1)
		local gotEgg = false
		for _, record in w.data.incubators do
			if record.petId == "jitterbug" then
				gotEgg = true
			end
		end
		T.truthy(gotEgg)
		w.H.uninstall()
	end)

	T.test("스튜디오가 아니면 (DEV_USER_IDS 도 비었으면) 명령이 아예 안 켜짐", function()
		local w = devWorld(false)
		chat(w, "/money 1e9")
		T.eq(w.data.money, 0)
		w.H.uninstall()
	end)

	T.test("DEV_USER_IDS 에 넣은 사람만 (실서버에서도), 다른 사람은 안 됨", function()
		local w = world()
		w.H.RunService.studio = false
		w.Config.DEV_USER_IDS = { 1001 }
		w.H.server("Services/SakuraService")
		local DevCommands = w.H.server("Services/DevCommands")
		DevCommands.start()
		local other = w.H.newPlayer(1002, "Other")
		local _, otherData = w.H.login(other)
		w.H.Players.PlayerAdded:Fire(other) -- 늦게 들어온 사람도 연결됨
		chat(w, "/money 100")
		chat(w, "/money 100", other)
		T.eq(w.data.money, 100)
		T.eq(otherData.money, 0)
		w.Config.DEV_USER_IDS = {}
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: DataService (저장·불러오기·세션 락·재시도)")

	local function dataWorld()
		local w = world()
		w.DataService = w.H.server("Services/DataService")
		w.DataService.start()
		w.Sessions = w.H.server("Sessions")
		return w
	end

	local function load(w, player, maxSeconds)
		return w.H.run(function()
			return w.DataService.load(player)
		end, maxSeconds or 60)
	end

	local function openSession(w, player, data)
		local session = w.Sessions.create(player)
		session.data = data
		session.loaded = true
		session.saveEnabled = true
		return session
	end

	T.test("새 플레이어: 기본 데이터로 시작 + 이 서버 이름으로 락이 걸림", function()
		local w = dataWorld()
		local p = w.H.newPlayer(7, "Newbie")
		local data, saveEnabled, newer = load(w, p)
		T.truthy(saveEnabled)
		T.falsy(newer)
		T.eq(data.version, 3)
		T.eq(data.money, w.Config.STARTING_MONEY)
		local stored = w.H.store.data["player_7"]
		T.eq(stored._lock.jobId, "job-A")
		w.H.uninstall()
	end)

	T.test("나갈 때 저장하면 락이 풀리고, 다시 접속하면 같은 데이터가 돌아옴", function()
		local w = dataWorld()
		local p = w.H.newPlayer(7, "Newbie")
		local data = load(w, p)
		local session = openSession(w, p, data)
		data.money = 12345
		data.speed = 777
		table.insert(data.pets, { uid = "p1", petId = "dog", size = "big", mutations = { "golden" } })
		data.nextUid = 2
		local saved = w.H.run(function()
			return w.DataService.save(p, true)
		end)
		T.truthy(saved)
		T.truthy(session.released)
		local stored = w.H.store.data["player_7"]
		T.eq(stored._lock, nil, "락 풀림")
		T.eq(stored.data.money, 12345)
		w.H.leave(p)
		-- 다시 접속
		local p2 = w.H.newPlayer(7, "Newbie")
		local again = load(w, p2)
		T.eq(again.money, 12345)
		T.eq(again.speed, 777)
		T.eq(again.pets[1].petId, "dog")
		T.eq(again.pets[1].mutations[1], "golden")
		w.H.uninstall()
	end)

	T.test(
		"다른 서버가 락을 쥐고 있으면 5초씩 3번 기다린 뒤 가져옴 (데이터는 안 잃음), 옛 서버는 저장이 막힘",
		function()
			-- 서버 A
			local w = dataWorld()
			local p = w.H.newPlayer(7, "Newbie")
			local dataA = load(w, p)
			local sessionA = openSession(w, p, dataA)
			dataA.money = 500
			T.truthy(w.H.run(function()
				return w.DataService.save(p, false)
			end))
			-- 서버 B (다른 JobId, 같은 DataStore)
			local DataServiceA = w.DataService
			w.H.game.JobId = "job-B"
			Loader.reset()
			local DataServiceB = w.H.server("Services/DataService")
			DataServiceB.start()
			local pB = w.H.newPlayer(7, "Newbie")
			local startedAt = w.H.clock()
			local dataB = w.H.run(function()
				return DataServiceB.load(pB)
			end, 60)
			local waited = w.H.clock() - startedAt
			T.truthy(waited >= 15 and waited < 20, "5초 × 3번 기다림 (실제 " .. waited .. ")")
			T.eq(dataB.money, 500, "A 가 저장한 데이터를 이어받음")
			local warned = false
			for _, text in w.H.warnings do
				if string.find(text, "오래된 세션 락을 가져옴", 1, true) then
					warned = true
				end
			end
			T.truthy(warned)
			T.eq(w.H.store.data["player_7"]._lock.jobId, "job-B")
			-- 옛 서버(A) 가 저장하려 하면 막힘 (데이터 롤백 방지) + 알림
			local savedByA = w.H.run(function()
				return DataServiceA.save(p, false)
			end)
			T.falsy(savedByA)
			T.falsy(sessionA.saveEnabled)
			T.eq(p.attrs.SaveEnabled, false)
			T.truthy(w.H.hasNotify(p, "error", "다른 곳에서 같은 계정으로 접속"))
			T.eq(w.H.store.data["player_7"].data.money, 500, "B 의 데이터를 덮어쓰지 않음")
			w.H.uninstall()
		end
	)

	T.test("락이 300초보다 오래됐으면 기다리지 않고 바로 가져옴", function()
		local w = dataWorld()
		w.H.store.data["player_9"] = {
			data = { version = 2, money = 42 },
			_lock = { jobId = "job-OLD", time = w.H.time() - 301 },
		}
		local p = w.H.newPlayer(9, "Nine")
		local t0 = w.H.clock()
		local data, saveEnabled = load(w, p)
		T.truthy(w.H.clock() - t0 < 1)
		T.eq(data.money, 42)
		T.truthy(saveEnabled)
		w.H.uninstall()
	end)

	T.test(
		"더 새 버전(4) 데이터: 저장 끔 + 락 바로 풀기 + 원본(모르는 필드 포함)은 그대로",
		function()
			local w = dataWorld()
			w.H.store.data["player_11"] = {
				data = { version = 4, money = 999, futureField = "중요" },
			}
			local p = w.H.newPlayer(11, "Future")
			local data, saveEnabled, newer = load(w, p)
			T.falsy(saveEnabled)
			T.truthy(newer)
			T.eq(data.money, 999)
			w.H.advance(2) -- releaseLockOnly 가 task.spawn 으로 돌아감
			local stored = w.H.store.data["player_11"]
			T.eq(stored._lock, nil)
			T.eq(stored.data.futureField, "중요")
			T.eq(stored.data.version, 4)
			-- 이 세션의 저장은 막혀 있음
			local session = openSession(w, p, data)
			session.saveEnabled = saveEnabled
			T.falsy(w.H.run(function()
				return w.DataService.save(p, true)
			end))
			T.eq(w.H.store.data["player_11"].data.version, 4, "저장 안 됨")
			w.H.uninstall()
		end
	)

	T.test(
		"스튜디오에서 DataStore 가 막혀 있으면 '메모리 모드' (기본 데이터, 저장 안 함, 게임은 계속)",
		function()
			local w = world()
			w.H.DataStoreService.available = false
			w.DataService = w.H.server("Services/DataService")
			w.DataService.start()
			T.truthy(w.DataService.isMemoryMode())
			local p = w.H.newPlayer(7, "Newbie")
			local data, saveEnabled = load(w, p)
			T.falsy(saveEnabled)
			T.eq(data.money, 0)
			T.falsy(w.H.run(function()
				return w.DataService.save(p, true)
			end))
			w.H.uninstall()

			-- DataStore 는 있는데 요청이 실패 (스튜디오): 첫 실패에 메모리 모드로
			local w2 = dataWorld()
			w2.H.store.failNext = 100
			local p2 = w2.H.newPlayer(8, "Eight")
			local _, saveEnabled2 = load(w2, p2)
			T.falsy(saveEnabled2)
			T.truthy(w2.DataService.isMemoryMode())
			w2.H.uninstall()
		end
	)

	T.test(
		"실서버에서 불러오기가 3번 실패하면 기본 데이터로 놀게 하되 저장은 끔 (원래 데이터 보호)",
		function()
			local w = dataWorld()
			w.H.RunService.studio = false
			w.H.store.data["player_5"] = { data = { version = 2, money = 888 } }
			w.H.store.failNext = 100
			local p = w.H.newPlayer(5, "Five")
			local t0 = w.H.clock()
			local data, saveEnabled, newer = load(w, p)
			T.falsy(saveEnabled)
			T.falsy(newer)
			T.eq(data.money, 0, "기본 데이터")
			T.truthy(w.H.clock() - t0 >= 6, "2초 + 4초 기다림")
			T.falsy(w.DataService.isMemoryMode())
			w.H.store.failNext = 0
			T.eq(w.H.store.data["player_5"].data.money, 888, "저장된 원본은 그대로")
			w.H.uninstall()
		end
	)

	T.test("저장이 두 번 실패해도 세 번째에 성공, 세 번 다 실패하면 false", function()
		local w = dataWorld()
		local p = w.H.newPlayer(7, "Newbie")
		local data = load(w, p)
		local session = openSession(w, p, data)
		data.money = 55
		w.H.store.failNext = 2
		T.truthy(w.H.run(function()
			return w.DataService.save(p, false)
		end))
		T.eq(w.H.store.data["player_7"].data.money, 55)
		data.money = 66
		w.H.store.failNext = 3
		T.falsy(w.H.run(function()
			return w.DataService.save(p, false)
		end))
		T.eq(w.H.store.data["player_7"].data.money, 55, "실패했으니 이전 저장 그대로")
		T.truthy(session.saveEnabled, "일시 실패로 저장을 끄지는 않음")
		w.H.store.failNext = 0
		w.H.uninstall()
	end)

	T.test(
		"나갈 때 저장이 끝내 실패 → 대기열 → 자동저장 주기에 다시 시도해 성공",
		function()
			local w = dataWorld()
			local p = w.H.newPlayer(7, "Newbie")
			local data = load(w, p)
			local session = openSession(w, p, data)
			data.money = 777
			w.H.store.failNext = 3
			T.falsy(w.H.run(function()
				return w.DataService.save(p, true)
			end))
			w.DataService.queueRelease(session)
			w.H.leave(p)
			-- 같은 서버에 곧바로 다시 들어오면 저장 못 한 최신 데이터를 이어서 씀
			local p2 = w.H.newPlayer(7, "Newbie")
			local data2 = w.H.run(function()
				return w.DataService.load(p2)
			end)
			T.eq(data2.money, 777)
			T.eq(data2, data, "같은 데이터 표를 이어받음")
			w.H.uninstall()

			-- 이어받지 않고 기다리면 자동 저장 주기에 다시 저장됨
			local w2 = dataWorld()
			local q = w2.H.newPlayer(8, "Eight")
			local d = load(w2, q)
			local s = openSession(w2, q, d)
			d.money = 4242
			w2.H.store.failNext = 3
			T.falsy(w2.H.run(function()
				return w2.DataService.save(q, true)
			end))
			w2.DataService.queueRelease(s)
			w2.H.advance(w2.Config.AUTOSAVE_SECONDS + 30)
			local stored = w2.H.store.data["player_8"]
			T.eq(stored.data.money, 4242)
			T.eq(stored._lock, nil, "락도 풀림")
			w2.H.uninstall()
		end
	)

	T.test("자동 저장(60초마다)과 서버 종료(BindToClose) 때 전부 저장", function()
		local w = dataWorld()
		local p1, p2 = w.H.newPlayer(21, "A"), w.H.newPlayer(22, "B")
		local d1, d2 = load(w, p1), load(w, p2)
		openSession(w, p1, d1)
		openSession(w, p2, d2)
		d1.money = 111
		w.H.advance(w.Config.AUTOSAVE_SECONDS + 5)
		T.eq(w.H.store.data["player_21"].data.money, 111, "자동 저장")
		T.eq(w.H.store.data["player_21"]._lock.jobId, "job-A", "자동 저장은 락을 유지")
		d1.money = 222
		d2.money = 333
		T.eq(#w.H.game.closeCallbacks, 1)
		w.H.run(function()
			w.H.game.closeCallbacks[1]()
		end)
		T.eq(w.H.store.data["player_21"].data.money, 222)
		T.eq(w.H.store.data["player_22"].data.money, 333)
		T.eq(w.H.store.data["player_21"]._lock, nil, "종료 때는 락도 풂")
		T.eq(w.H.store.data["player_22"]._lock, nil)
		w.H.uninstall()
	end)

	T.test(
		"불러오는 중에 나가면 데이터는 건드리지 않고 락만 풂 (오프라인 수입 보존)",
		function()
			local w = dataWorld()
			w.H.store.data["player_30"] = { data = { version = 2, money = 10, lastSaveTime = 555 } }
			local p = w.H.newPlayer(30, "Quick")
			local data, saveEnabled = load(w, p)
			T.eq(w.H.store.data["player_30"]._lock.jobId, "job-A")
			w.H.run(function()
				w.DataService.abandonLoad({ userId = 30 }, data, saveEnabled)
			end)
			local stored = w.H.store.data["player_30"]
			T.eq(stored._lock, nil)
			T.eq(stored.data.lastSaveTime, 555, "저장 시각을 새로 찍지 않음")
			T.eq(stored.data.money, 10)
			w.H.uninstall()
		end
	)

	ServerHarness.install(Loader, T).uninstall()
end
