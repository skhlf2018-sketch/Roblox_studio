--!nocheck
--[[
	5판 주임 검수 — 구멍 찾기 2: 랭킹판 · 물 주기(6판, 5판 쓰다듬기 자리) · 퀘스트/선물 제거 · 공지 씨앗
	  social.spec 이 "정상 경로"를 봤다면, 여기서는 경계값·엉터리 입력·남은 찌꺼기를 찾습니다.
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
	T.suite("5판 구멍 찾기: 랭킹판 (LeaderboardService)")

	T.test(
		"정확히 10명 → 10줄, 11명 → 꼴찌 한 명만 빠짐 (이름이 앞서도 값이 작으면 빠짐)",
		function()
			local w = world()
			for i = 1, 10 do
				join(w, 100 + i, "Z" .. string.format("%02d", i), i * 100, i * 10)
			end
			local board = w.LeaderboardService.build()
			T.eq(#board.money, 10)
			T.eq(#board.speed, 10)
			-- 11번째: 이름은 "A…" 로 제일 앞이지만 돈·속도는 꼴찌
			join(w, 200, "Aaron", 1, 1)
			board = w.LeaderboardService.build()
			T.eq(#board.money, 10, "11명이어도 10줄")
			for _, entry in board.money do
				T.truthy(entry.name ~= "Aaron", "꼴찌는 이름이 앞서도 빠짐")
			end
			T.eq(board.money[10].name, "Z01")
			T.eq(board.money[10].value, 100)
			w.H.uninstall()
		end
	)

	T.test(
		"25명: 큰 값부터 정확히 10명, 자리 바꿔 가며 들어와도 같은 결과 (입력 순서와 무관)",
		function()
			local w = world()
			local order = {}
			for i = 1, 25 do
				order[i] = i
			end
			-- 고정 시드로 섞기
			local rng = T.rng(7)
			for i = #order, 2, -1 do
				local j = math.floor(rng() * i) + 1
				order[i], order[j] = order[j], order[i]
			end
			for _, i in order do
				join(w, 1000 + i, "P" .. string.format("%02d", i), i * 1000, (26 - i) * 7)
			end
			local board = w.LeaderboardService.build()
			T.eq(#board.money, 10)
			for rank = 1, 10 do
				T.eq(board.money[rank].value, (26 - rank) * 1000, "돈 " .. rank .. "등")
				T.eq(board.speed[rank].value, (26 - rank) * 7, "속도 " .. rank .. "등")
			end
			-- 돈 순위와 속도 순위는 따로 (돈 1등 ≠ 속도 1등)
			T.truthy(board.money[1].userId ~= board.speed[1].userId)
			w.H.uninstall()
		end
	)

	T.test(
		"같은 값: 이름 순 → 같은 이름이면 userId 순 (매번 같은 순서, 뒤죽박죽 안 됨)",
		function()
			local w = world()
			join(w, 9, "Same", 50, 5)
			join(w, 3, "Same", 50, 5)
			join(w, 5, "Beta", 50, 5)
			join(w, 7, "alpha", 50, 5) -- 소문자는 대문자 뒤
			join(w, 8, "Alpha", 50, 5)
			local want = { "Alpha", "Beta", "Same", "Same", "alpha" }
			for run = 1, 3 do
				local board = w.LeaderboardService.build()
				for i, name in want do
					T.eq(board.money[i].name, name, "돈 #" .. i .. " (" .. run .. "번째)")
					T.eq(board.speed[i].name, name, "속도 #" .. i)
				end
				T.eq(board.money[3].userId, 3, "Same 둘은 userId 작은 쪽 먼저")
				T.eq(board.money[4].userId, 9)
			end
			w.H.uninstall()
		end
	)

	T.test(
		"데이터 안 불러온 사람 제외: 세션만 만들고 loaded=false · 세션 없음 · 세션 data 가 nil · 나간 사람(세션이 남아 있어도)",
		function()
			local w = world()
			join(w, 1, "Ready", 10, 1)
			-- 세션은 있지만 아직 불러오는 중
			local loading = w.H.newPlayer(2, "Loading")
			w.Sessions.create(loading)
			-- 세션 자체가 없음
			w.H.newPlayer(3, "NoSession")
			-- loaded 인데 data 가 비어 있음 (비정상 상태)
			local broken = w.H.newPlayer(4, "Broken")
			local brokenSession = w.Sessions.create(broken)
			brokenSession.loaded = true
			brokenSession.data = nil
			-- 나감: Players 목록에서 빠졌지만 세션은 아직 저장 중
			local gone, _, goneData = join(w, 5, "Gone", 99999, 999)
			goneData.money = 99999
			w.H.leave(gone)
			local board = w.LeaderboardService.build()
			T.eq(#board.money, 1)
			T.eq(board.money[1].name, "Ready")
			T.eq(#board.speed, 1)
			w.H.uninstall()
		end
	)

	T.test(
		"나가면 다음 판에서 빠지고, 다시 들어오면 다시 나옴 (10초 방송에도 반영)",
		function()
			local w = world()
			local a = join(w, 1, "Ann", 500, 50)
			local b = join(w, 2, "Bob", 900, 90)
			w.LeaderboardService.start()
			w.H.advance(10.1)
			local all = w.H.remotes.LeaderboardUpdate.firedAll
			T.eq(#all[#all][1].money, 2)
			T.eq(all[#all][1].money[1].name, "Bob")
			w.H.leave(b)
			w.H.advance(10)
			all = w.H.remotes.LeaderboardUpdate.firedAll
			T.eq(#all[#all][1].money, 1, "Bob 이 나가서 한 줄")
			T.eq(all[#all][1].money[1].name, "Ann")
			T.eq(all[#all][1].speed[1].userId, 1)
			-- 다시 들어옴
			join(w, 2, "Bob", 900, 90)
			w.H.advance(10)
			all = w.H.remotes.LeaderboardUpdate.firedAll
			T.eq(#all[#all][1].money, 2)
			_ = a
			w.H.uninstall()
		end
	)

	T.test("아무도 없어도 터지지 않고 빈 표 두 개 (nil 아님), 방송은 계속 나감", function()
		local w = world()
		local board = w.LeaderboardService.build()
		T.eq(typeof(board.money), "table")
		T.eq(typeof(board.speed), "table")
		T.eq(#board.money, 0)
		w.LeaderboardService.start()
		w.H.advance(35)
		T.eq(#w.H.remotes.LeaderboardUpdate.firedAll, 3)
		T.eq(#w.H.warnings, 0, "경고 없음")
		w.H.uninstall()
	end)

	T.test(
		"방송은 100.5초에 정확히 10번 (두 번 겹쳐 돌지 않음), 매번 새 표 (앞 방송을 고쳐도 영향 없음)",
		function()
			local w = world()
			join(w, 1, "Ann", 500, 50)
			w.LeaderboardService.start()
			w.H.advance(100.5)
			local all = w.H.remotes.LeaderboardUpdate.firedAll
			T.eq(#all, 10)
			all[1][1].money[1].name = "CHANGED"
			w.H.advance(10)
			all = w.H.remotes.LeaderboardUpdate.firedAll
			T.eq(all[#all][1].money[1].name, "Ann", "앞 방송 표를 고쳐도 다음 방송은 그대로")
			w.H.uninstall()
		end
	)

	T.test(
		"표시 이름: 비어 있으면 계정 이름, 한글·이모지 그대로, 값은 숫자·userId 는 숫자",
		function()
			local w = world()
			local a = join(w, 1, "Ann", 5, 5)
			a.DisplayName = ""
			local b = join(w, 2, "Bob", 4, 4)
			b.DisplayName = "별명🐶"
			local board = w.LeaderboardService.build()
			T.eq(board.money[1].name, "Ann", "빈 DisplayName 은 Name")
			T.eq(board.money[2].name, "별명🐶")
			for _, entry in board.money do
				T.eq(typeof(entry.value), "number")
				T.eq(typeof(entry.userId), "number")
				T.eq(typeof(entry.name), "string")
			end
			w.H.uninstall()
		end
	)

	T.test(
		"이상한 값(NaN·inf·음수) 한 명이 섞여도 build() 가 터지지 않고, 무한 속도는 1등·음수는 꼴찌",
		function()
			local w = world()
			join(w, 1, "Ann", 500, 50)
			join(w, 2, "Bob", 900, 90)
			local _, _, nanData = join(w, 3, "Nan", 0, 0)
			join(w, 4, "Cat", 700, 70)
			local _, inf = join(w, 5, "Inf", 1, 1)
			local _, _, negData = join(w, 6, "Neg", -5, 1)
			nanData.money = 0 / 0
			inf.effectiveSpeed = math.huge
			negData.money = -5
			local ok, board = pcall(w.LeaderboardService.build)
			T.truthy(ok, "NaN 이 섞이면 build 가 터짐: " .. tostring(board))
			T.eq(#board.money, 6)
			-- NaN 을 빼고 나면: 무한 속도는 1등, 음수 돈은 꼴찌
			nanData.money = 0
			board = w.LeaderboardService.build()
			T.eq(board.speed[1].name, "Inf", "무한 속도는 1등")
			T.eq(board.money[1].name, "Bob")
			T.eq(board.money[6].name, "Neg", "음수 돈은 꼴찌")
			w.H.uninstall()
		end
	)

	-- 알려진 약점 (Low): 돈이 NaN 인 사람이 한 명 있으면 table.sort 비교 함수가 일관되지 않아 나머지 순서가 뒤죽박죽이 됨.
	-- 지금은 NaN 이 생길 길이 없음(Wallet 이 막고 DataSchema.reconcile 이 고침) → 방어용 수정 권고. 고쳐지면 T.skip → T.test.
	T.skip(
		"NaN 돈이 한 명 섞여도 나머지는 큰 값부터 (Bob 900 > Cat 700 > Ann 500)",
		"LeaderboardService.top 비교 함수에 NaN 처리 없음 (값이 NaN 이면 Bob 900 이 5등으로 밀림)",
		function()
			local w = world()
			join(w, 1, "Ann", 500, 50)
			join(w, 2, "Bob", 900, 90)
			local _, _, nanData = join(w, 3, "Nan", 0, 0)
			join(w, 4, "Cat", 700, 70)
			join(w, 5, "Dan", 100, 10)
			join(w, 6, "Eve", 800, 80)
			nanData.money = 0 / 0
			local board = w.LeaderboardService.build()
			local rank = {}
			for i, entry in board.money do
				rank[entry.name] = i
			end
			w.H.uninstall()
			T.truthy(
				rank.Bob < rank.Eve and rank.Eve < rank.Cat and rank.Cat < rank.Ann and rank.Ann < rank.Dan,
				"NaN 이 있으면 나머지 순서가 뒤섞임: Bob "
					.. rank.Bob
					.. " Eve "
					.. rank.Eve
					.. " Cat "
					.. rank.Cat
					.. " Ann "
					.. rank.Ann
					.. " Dan "
					.. rank.Dan
			)
		end
	)

	T.test(
		"준비된 사람 한 명에게만 보내는 판에는 방금 온 그 사람 자신도 들어 있음",
		function()
			local w = world()
			join(w, 1, "Ann", 500, 50)
			local b = join(w, 2, "Bob", 900, 90)
			w.LeaderboardService.onPlayerReady(b)
			local mine = w.H.sent(b, "LeaderboardUpdate")
			T.eq(#mine, 1)
			T.eq(#mine[1][1].money, 2)
			T.eq(mine[1][1].money[1].name, "Bob")
			T.eq(#w.H.remotes.LeaderboardUpdate.firedAll, 0, "전체 방송은 아님")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
end
