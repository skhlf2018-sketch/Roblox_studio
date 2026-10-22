--!nocheck
--[[
	5판 사회 기능 (사장님 지시): 랭킹판(LeaderboardService) · 펫 쓰다듬기(PetService PetPet)
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
	T.suite("5판 쓰다듬기: PetPet → PetPetted")

	local function petWorld()
		local w = world()
		w.PetService.start()
		w.player, w.session, w.data = join(w, 1001, "Owner")
		w.session.plotIndex = 1
		w.PetService.addPet(w.player, { uid = "p1", petId = "chicken", size = "normal", mutations = {} })
		w.PetService.addPet(w.player, { uid = "p2", petId = "dog", size = "normal", mutations = {} }, false)
		local rect = w.MapLayout.penRect(1)
		w.rect = rect
		w.penZ = (rect.zMin + rect.zMax) / 2
		w.H.spawn(w.player, (rect.xMin + rect.xMax) / 2, 3, w.penZ) -- 우리 안
		return w
	end

	local function petted(w)
		return w.H.remotes.PetPetted.firedAll
	end

	T.test("우리 안에서 장착 펫을 쓰다듬으면 PetPetted(내 UserId, petUid) 를 모두에게", function()
		local w = petWorld()
		T.truthy(table.find(w.data.equipped, "p1"))
		w.H.client(w.player, "PetPet", "p1")
		local list = petted(w)
		T.eq(#list, 1)
		T.eq(list[1][1], 1001)
		T.eq(list[1][2], "p1")
		T.eq(list[1].n, 2, "인자 2개 (ownerUserId, petUid)")
		w.H.uninstall()
	end)

	T.test("쿨다운 1초: 바로 또 누르면 무시, 1초 지나면 다시", function()
		local w = petWorld()
		w.H.client(w.player, "PetPet", "p1")
		w.H.client(w.player, "PetPet", "p1")
		T.eq(#petted(w), 1)
		w.H.advance(0.9)
		w.H.client(w.player, "PetPet", "p1")
		T.eq(#petted(w), 1, "0.9초는 아직")
		w.H.advance(0.2)
		w.H.client(w.player, "PetPet", "p1")
		T.eq(#petted(w), 2)
		w.H.uninstall()
	end)

	T.test(
		"거부: 장착 안 한 펫 · 남의 펫 · 없는 uid · 이상한 인자 · 베이스 없음 · 죽음",
		function()
			local w = petWorld()
			w.H.client(w.player, "PetPet", "p2") -- 보관함에만 있음 (우리에 없음)
			w.H.advance(1.1)
			local other, otherSession = join(w, 2002, "Other")
			otherSession.plotIndex = 2
			w.PetService.addPet(other, { uid = "p9", petId = "bear", size = "normal", mutations = {} })
			w.H.client(w.player, "PetPet", "p9") -- 남의 펫 uid
			w.H.advance(1.1)
			for _, bad in { "없는펫", 5, nil, { "p1" }, "../p1", string.rep("p", 60) } do
				w.H.client(w.player, "PetPet", bad)
				w.H.advance(1.1)
			end
			T.eq(#petted(w), 0)
			w.session.plotIndex = 0
			w.H.client(w.player, "PetPet", "p1")
			w.H.advance(1.1)
			T.eq(#petted(w), 0, "베이스가 없으면 안 됨")
			w.session.plotIndex = 1
			w.player.Character.humanoid.Health = 0
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 0, "죽어 있으면 안 됨")
			w.H.uninstall()
		end
	)

	T.test(
		"거리: 우리(울타리 사각형)에서 20 안이면 되고, 20 넘으면 안 됨 · 다른 사람 우리 앞에서는 안 됨",
		function()
			local w = petWorld()
			local r = w.rect
			-- 우리 앞(복도 쪽) 앞마당 방향으로: 1번 베이스는 왼쪽(x < 0), 우리는 벽 쪽이라 xMax 바깥이 앞마당
			w.H.teleport(w.player, r.xMax + 19.9, 3, w.penZ)
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 1, "19.9 는 됨")
			w.H.advance(1.1)
			w.H.teleport(w.player, r.xMax + 20.5, 3, w.penZ)
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 1, "20.5 는 안 됨")
			w.H.advance(1.1)
			-- 다른 베이스(2번) 우리 안
			local r2 = w.MapLayout.penRect(2)
			w.H.teleport(w.player, (r2.xMin + r2.xMax) / 2, 3, (r2.zMin + r2.zMax) / 2)
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 1, "남의 우리에서는 내 펫을 못 쓰다듬음")
			w.H.uninstall()
		end
	)

	T.test("레이트 리밋 (burst 3): 한 번에 몰아 보내도 처리기는 3번까지만 돎", function()
		local w = petWorld()
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
		T.eq(#petted(w), 1, "쿨다운 때문에 실제 알림은 1번")
		w.PetService.petPet = real
		w.H.uninstall()
	end)
end
