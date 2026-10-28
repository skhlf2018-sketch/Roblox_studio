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
end
