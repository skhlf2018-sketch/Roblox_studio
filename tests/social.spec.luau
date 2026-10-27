--!nocheck
--[[
	5판 사회 기능 (사장님 지시): 랭킹판(LeaderboardService) · 6판 물 주기(PetService PetPet, 5판 쓰다듬기 자리)
	진짜 서비스 코드 + 진짜 server/Net(레이트 리밋) 을 ServerHarness 위에서 (가상 시간).
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function world()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.MapLayout = H.MapLayout
		w.Sessions = H.server("Sessions")
		w.PetService = H.server("Services/PetService")
		w.LeaderboardService = H.server("Services/LeaderboardService")
		return w
	end

	local function join(w, userId, name, money, speed)
		local p = w.H.newPlayer(userId, name)
		local session, data = w.H.login(p)
		data.money = money or 0
		session.effectiveSpeed = speed or 0
		return p, session, data
	end

	------------------------------------------------------------------
	T.suite("5판 랭킹판: LeaderboardService")

	T.test(
		"돈·속도 각각 큰 사람부터 { name, value, userId }, 같으면 이름 순, 불러오기 전 사람은 빠짐",
		function()
			local w = world()
			join(w, 1, "Ann", 500, 30)
			join(w, 2, "Bob", 9000, 10)
			join(w, 3, "Cat", 500, 999)
			w.H.newPlayer(4, "Loading") -- 아직 데이터를 못 불러옴 (Sessions 없음)
			local board = w.LeaderboardService.build()
			T.eq(#board.money, 3)
			T.eq(board.money[1].name, "Bob")
			T.eq(board.money[1].value, 9000)
			T.eq(board.money[1].userId, 2)
			T.eq(board.money[2].name, "Ann", "같은 500 이면 이름 순")
			T.eq(board.money[3].name, "Cat")
			T.eq(#board.speed, 3)
			T.eq(board.speed[1].name, "Cat")
			T.eq(board.speed[1].value, 999)
			T.eq(board.speed[2].name, "Ann")
			T.eq(board.speed[3].name, "Bob")
			w.H.uninstall()
		end
	)

	T.test("상위 10명까지만, 표시 이름(DisplayName)을 씀", function()
		local w = world()
		for i = 1, 12 do
			local p = join(w, 100 + i, "P" .. string.format("%02d", i), i * 1000, i)
			p.DisplayName = "별명" .. i
		end
		local board = w.LeaderboardService.build()
		T.eq(#board.money, w.Config.LEADERBOARD_SIZE)
		T.eq(#board.speed, 10)
		T.eq(board.money[1].value, 12000)
		T.eq(board.money[1].name, "별명12")
		T.eq(board.money[10].value, 3000, "1·2등 아래 두 명은 빠짐")
		w.H.uninstall()
	end)

	T.test(
		"10초마다 서버 전체(fireAll)에 보냄, 새로 온 사람에게는 준비되자마자 그 사람에게만 한 번",
		function()
			local w = world()
			local a = join(w, 1, "Ann", 100, 20)
			w.LeaderboardService.start()
			w.H.advance(9.9)
			T.eq(#w.H.remotes.LeaderboardUpdate.firedAll, 0)
			w.H.advance(0.2)
			T.eq(#w.H.remotes.LeaderboardUpdate.firedAll, 1)
			w.H.advance(20)
			local all = w.H.remotes.LeaderboardUpdate.firedAll
			T.eq(#all, 3)
			T.eq(all[3][1].money[1].name, "Ann")
			-- 돈이 바뀌면 다음 판에 반영
			local b, _, bData = join(w, 2, "Bob", 0, 0)
			w.LeaderboardService.onPlayerReady(b)
			local mine = w.H.sent(b, "LeaderboardUpdate")
			T.eq(#mine, 1)
			T.eq(#mine[1][1].money, 2)
			T.eq(#w.H.sent(a, "LeaderboardUpdate"), 0, "다른 사람에게는 개별로 안 보냄")
			bData.money = 1e9
			w.H.advance(10)
			all = w.H.remotes.LeaderboardUpdate.firedAll
			T.eq(all[#all][1].money[1].name, "Bob")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("6판 물 주기: PetPet → PetPetted (5판 쓰다듬기 자리)")

	local function waterWorld()
		local w = world()
		w.PetService.start()
		w.player, w.session, w.data = join(w, 1001, "Owner")
		w.session.plotIndex = 1
		-- 성체 p1 (아기 데이지, 열매 간격 30초) + 자라는 씨앗 i2 (룬 장미 1일 중 0초)
		w.PetService.addPlant(w.player, {
			uid = "p1",
			petId = "sprout_daisy",
			size = "normal",
			mutations = {},
			x = -20,
			z = 0,
			fruits = 0,
			fruitProgress = 0,
		})
		table.insert(w.data.incubators, {
			uid = "i2",
			petId = "rune_rose",
			size = "normal",
			mutations = {},
			biomeId = "enchanted_forest",
			special = false,
			x = -20,
			z = 10,
			progress = 0,
			required = 86400,
		})
		local rect = w.MapLayout.penRect(1)
		w.rect = rect
		w.penZ = (rect.zMin + rect.zMax) / 2
		w.H.spawn(w.player, (rect.xMin + rect.xMax) / 2, 3, w.penZ) -- 정원 안
		return w
	end

	local function watered(w)
		return w.H.remotes.PetPetted.firedAll
	end

	T.test(
		"자라는 씨앗에 물: 성장 +10초, 성체에 물: 다음 열매까지 +10초 → PetPetted(내 UserId, uid) 를 모두에게",
		function()
			local w = waterWorld()
			w.H.client(w.player, "PetPet", "i2")
			T.eq(w.data.incubators[1].progress, w.Config.WATER_GROWTH_SECONDS)
			local list = watered(w)
			T.eq(#list, 1)
			T.eq(list[1][1], 1001)
			T.eq(list[1][2], "i2")
			T.eq(list[1].n, 2, "인자 2개 (ownerUserId, uid)")
			w.H.advance(1.1)
			w.H.client(w.player, "PetPet", "p1")
			T.eq(w.data.pets[1].fruitProgress, 10)
			T.eq(#watered(w), 2)
			T.eq(w.data.stats.watered, 2)
			w.H.uninstall()
		end
	)

	T.test("식물마다 60초 쿨다운 (아직이면 안내), 사람마다 1초 연타 막기", function()
		local w = waterWorld()
		w.H.client(w.player, "PetPet", "i2")
		w.H.client(w.player, "PetPet", "p1") -- 1초 연타 막기
		T.eq(#watered(w), 1)
		w.H.advance(1.1)
		w.H.client(w.player, "PetPet", "p1") -- 다른 식물은 됨
		T.eq(#watered(w), 2)
		w.H.advance(1.1)
		w.H.client(w.player, "PetPet", "i2") -- 같은 식물 60초 안
		T.eq(#watered(w), 2)
		T.eq(w.data.incubators[1].progress, 10, "그대로")
		T.truthy(w.H.hasNotify(w.player, "info", "또 물을 줄 수 있어요"))
		w.H.advance(60)
		w.H.client(w.player, "PetPet", "i2")
		T.eq(#watered(w), 3)
		T.eq(w.data.incubators[1].progress, 20)
		w.H.uninstall()
	end)

	T.test(
		"거부: 남의 식물 · 없는 uid · 이상한 인자 · 베이스 없음 · 죽음 (조용히)",
		function()
			local w = waterWorld()
			local other, otherSession, otherData = join(w, 2002, "Other")
			otherSession.plotIndex = 2
			otherData.nextUid = 900
			w.PetService.addPlant(other, {
				uid = "p9",
				petId = "owl_oak",
				size = "normal",
				mutations = {},
				x = -20,
				z = 0,
				fruits = 0,
				fruitProgress = 0,
			})
			w.H.client(w.player, "PetPet", "p9") -- 남의 식물 uid
			w.H.advance(1.1)
			for _, bad in { "없는식물", 5, nil, { "p1" }, "../p1", string.rep("p", 60) } do
				w.H.client(w.player, "PetPet", bad)
				w.H.advance(1.1)
			end
			T.eq(#watered(w), 0)
			w.session.plotIndex = 0
			w.H.client(w.player, "PetPet", "p1")
			w.H.advance(1.1)
			T.eq(#watered(w), 0, "베이스가 없으면 안 됨")
			w.session.plotIndex = 1
			w.player.Character.humanoid.Health = 0
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#watered(w), 0, "죽어 있으면 안 됨")
			w.H.uninstall()
		end
	)

	T.test(
		"거리: 정원(울타리 사각형)에서 20 안이면 되고, 20 넘으면 안 됨 · 다른 사람 정원 앞에서는 안 됨",
		function()
			local w = waterWorld()
			local r = w.rect
			w.H.teleport(w.player, r.xMax + 19.9, 3, w.penZ)
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#watered(w), 1, "19.9 는 됨")
			w.H.advance(1.1)
			w.H.teleport(w.player, r.xMax + 20.5, 3, w.penZ)
			w.H.client(w.player, "PetPet", "i2")
			T.eq(#watered(w), 1, "20.5 는 안 됨")
			w.H.advance(1.1)
			local r2 = w.MapLayout.penRect(2)
			w.H.teleport(w.player, (r2.xMin + r2.xMax) / 2, 3, (r2.zMin + r2.zMax) / 2)
			w.H.client(w.player, "PetPet", "i2")
			T.eq(#watered(w), 1, "남의 정원에서는 내 식물에 못 줌")
			w.H.uninstall()
		end
	)

	T.test("레이트 리밋 (burst 3): 한 번에 몰아 보내도 처리기는 3번까지만 돎", function()
		local w = waterWorld()
		local calls = 0
		local real = w.PetService.petPet
		w.PetService.petPet = function(...)
			calls += 1
			return real(...)
		end
		for _ = 1, 10 do
			w.H.client(w.player, "PetPet", "p1")
		end
		T.eq(calls, w.H.shared("Remotes").RateLimits.PetPet.burst)
		T.eq(#watered(w), 1, "쿨다운 때문에 실제 알림은 1번")
		w.PetService.petPet = real
		w.H.uninstall()
	end)
end
