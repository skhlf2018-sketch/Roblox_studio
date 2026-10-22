--!nocheck
--[[
	5판 주임 검수 — 구멍 찾기 2: 랭킹판 · 쓰다듬기 · 퀘스트/선물 제거 · Remote 막 던지기
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
	T.suite("5판 구멍 찾기: 쓰다듬기 (PetPet → PetPetted) — 전부 조용히 무시")

	local function petWorld()
		local w = world()
		w.PetService.start()
		w.player, w.session, w.data = join(w, 1001, "Owner")
		w.session.plotIndex = 1
		w.PetService.addPet(w.player, { uid = "p1", petId = "chicken", size = "normal", mutations = {} })
		w.PetService.addPet(w.player, { uid = "p2", petId = "dog", size = "normal", mutations = {} }, false)
		w.rect = w.MapLayout.penRect(1)
		w.cx = (w.rect.xMin + w.rect.xMax) / 2
		w.cz = (w.rect.zMin + w.rect.zMax) / 2
		w.H.spawn(w.player, w.cx, 3, w.cz) -- 우리 안
		return w
	end

	local function petted(w)
		return w.H.remotes.PetPetted.firedAll
	end

	-- 알림이 하나도 없는지 (조용히 무시): 이 사람에게 간 Notify 개수
	local function quiet(w, player, before)
		T.eq(#w.H.sent(player, "Notify"), before, "알림 없음")
		T.eq(#w.H.remotes.PetPetted.fired, 0, "한 사람에게만 가는 PetPetted 도 없음")
	end

	T.test(
		"가짜 uid 잔치: 없는 uid·너무 긴 uid(49자)·특수문자·공백·대소문자 다름·타입이 다름·인자 없음 → 전부 무시, 알림·방송 없음",
		function()
			local w = petWorld()
			local notes = #w.H.sent(w.player, "Notify")
			local fakes = {
				"p999",
				"",
				"p1 ",
				" p1",
				"P1",
				"p1\n",
				"p1;",
				"p1/../p2",
				"p'1",
				string.rep("p", 49),
				string.rep("1", 200),
				"한글",
				"p１", -- 전각 숫자
				"__index",
				"nil",
				"true",
				"0",
			}
			for _, bad in fakes do
				w.H.client(w.player, "PetPet", bad)
				w.H.advance(1.1)
			end
			for _, bad in { 1, -1, 0.5, 0 / 0, math.huge, true, false, {}, { "p1" }, { uid = "p1" } } do
				w.H.client(w.player, "PetPet", bad)
				w.H.advance(1.1)
			end
			w.H.client(w.player, "PetPet") -- 인자 없음
			w.H.advance(1.1)
			w.H.client(w.player, "PetPet", "p1", "p2", "p3") -- 인자 여러 개: 첫 인자만 봄
			T.eq(#petted(w), 1, "마지막 정상 uid(p1)는 통과")
			quiet(w, w.player, notes)
			T.eq(#w.H.warnings, 0, "처리 중 오류(warn) 없음")
			w.H.uninstall()
		end
	)

	T.test(
		"남의 펫 uid: 다른 사람 보관함·장착 uid 를 보내도 무시, 같은 uid 이름(p1)이 겹쳐도 내 것만",
		function()
			local w = petWorld()
			local other, otherSession, otherData = join(w, 2002, "Other")
			otherSession.plotIndex = 2
			w.PetService.addPet(other, { uid = "p77", petId = "bear", size = "normal", mutations = {} })
			w.PetService.addPet(other, { uid = "p1", petId = "bear", size = "normal", mutations = {} }) -- 이름 겹침
			w.H.client(w.player, "PetPet", "p77")
			T.eq(#petted(w), 0, "남의 p77")
			-- 나는 p1 이 있으니 통과하지만 알림은 "내" UserId 로
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 1)
			T.eq(petted(w)[1][1], 1001, "알림의 주인은 보낸 사람(1001)")
			-- 남의 데이터가 안 바뀜
			T.eq(#otherData.pets, 2)
			w.H.uninstall()
		end
	)

	T.test(
		"장착 안 한 펫(보관함에만) · 장착을 풀면 바로 무시 · 다시 장착하면 됨",
		function()
			local w = petWorld()
			w.H.client(w.player, "PetPet", "p2")
			T.eq(#petted(w), 0, "보관함에만 있는 펫")
			w.H.client(w.player, "UnequipPet", "p1")
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 0, "장착 해제한 펫")
			w.H.client(w.player, "EquipPet", "p1")
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 1, "다시 장착하면 됨")
			w.H.uninstall()
		end
	)

	T.test(
		"거리: 우리 가장자리에서 19.9 는 되고 20.1 은 안 됨 — 앞·뒤·옆·대각선 모두 (대각선은 축별이 아니라 진짜 거리)",
		function()
			local w = petWorld()
			local r = w.rect
			local R = w.Config.PET_PET_RADIUS
			local function try(x, z)
				w.H.advance(1.1)
				w.H.teleport(w.player, x, 3, z)
				local before = #petted(w)
				w.H.client(w.player, "PetPet", "p1")
				return #petted(w) == before + 1
			end
			-- 네 방향 직선
			T.truthy(try(r.xMax + R - 0.1, w.cz), "앞(+x) 19.9")
			T.falsy(try(r.xMax + R + 0.1, w.cz), "앞(+x) 20.1")
			T.truthy(try(r.xMin - R + 0.1, w.cz), "뒤(-x) 19.9")
			T.falsy(try(r.xMin - R - 0.1, w.cz), "뒤(-x) 20.1")
			T.truthy(try(w.cx, r.zMax + R - 0.1), "옆(+z) 19.9")
			T.falsy(try(w.cx, r.zMax + R + 0.1), "옆(+z) 20.1")
			T.truthy(try(w.cx, r.zMin - R + 0.1), "옆(-z) 19.9")
			T.falsy(try(w.cx, r.zMin - R - 0.1), "옆(-z) 20.1")
			-- 대각선 모서리: 축마다 15 씩 = 21.2 > 20 (축별로만 보면 통과해 버리는 버그를 잡음), 14 씩 = 19.8 < 20
			T.falsy(try(r.xMax + 15, r.zMax + 15), "대각선 (15, 15) = 21.2")
			T.truthy(try(r.xMax + 14, r.zMax + 14), "대각선 (14, 14) = 19.8")
			T.falsy(try(r.xMin - 15, r.zMin - 15), "반대 모서리 (15, 15)")
			-- 아주 먼 곳, 다른 구역·허브 반대쪽
			T.falsy(try(0, 100000), "아주 멀리")
			T.falsy(try(r.xMax + 2000, w.cz), "2000 스터드 앞")
			w.H.uninstall()
		end
	)

	T.test(
		"쿨다운 1초: 정확히 0.99초 뒤는 안 되고 1.0초 뒤는 됨, 거부된 시도는 쿨다운을 쓰지 않음(가짜 uid 뒤에 바로 진짜가 통과), 사람마다 따로",
		function()
			local w = petWorld()
			w.H.client(w.player, "PetPet", "p1")
			w.H.advance(0.99)
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 1, "0.99초")
			w.H.advance(0.02)
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 2, "1.01초")
			-- 거부된 시도(가짜 uid)는 쿨다운을 소모하지 않음
			w.H.advance(1.1)
			w.H.client(w.player, "PetPet", "가짜")
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 3, "가짜 뒤 진짜가 바로 통과")
			-- 두 사람이 같은 순간에 각자 쓰다듬기
			w.H.advance(1.1)
			local other, otherSession = join(w, 2002, "Other")
			otherSession.plotIndex = 2
			w.PetService.addPet(other, { uid = "p1", petId = "bear", size = "normal", mutations = {} })
			local r2 = w.MapLayout.penRect(2)
			w.H.spawn(other, (r2.xMin + r2.xMax) / 2, 3, (r2.zMin + r2.zMax) / 2)
			w.H.client(w.player, "PetPet", "p1")
			w.H.client(other, "PetPet", "p1")
			T.eq(#petted(w), 5, "각자 한 번씩")
			T.eq(petted(w)[4][1], 1001)
			T.eq(petted(w)[5][1], 2002)
			w.H.uninstall()
		end
	)

	T.test(
		"살아 있는 캐릭터가 없을 때: 캐릭터 없음 · 죽음 · 세션 불러오기 전 · 베이스 없음 · 존재하지 않는 베이스 번호",
		function()
			local w = petWorld()
			local before = #w.H.sent(w.player, "Notify")
			w.player.Character = nil
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 0, "캐릭터 없음")
			w.H.advance(1.1)
			w.H.spawn(w.player, w.cx, 3, w.cz)
			w.player.Character.humanoid.Health = 0
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 0, "죽음")
			w.H.advance(1.1)
			w.player.Character.humanoid.Health = 100
			w.session.plotIndex = 99
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 0, "없는 베이스 번호(99)")
			w.H.advance(1.1)
			w.session.plotIndex = -1
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 0, "음수 베이스 번호")
			w.H.advance(1.1)
			w.session.plotIndex = 1
			w.session.loaded = false
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 0, "데이터 불러오기 전")
			w.H.advance(1.1)
			w.session.loaded = true
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 1, "되돌리면 됨")
			quiet(w, w.player, before)
			w.H.uninstall()
		end
	)

	T.test("저장 데이터가 어긋난 경우(장착 목록에 보관함에 없는 uid): 무시", function()
		local w = petWorld()
		table.insert(w.data.equipped, "ghost")
		w.H.client(w.player, "PetPet", "ghost")
		T.eq(#petted(w), 0, "장착 목록에만 있고 pets 에 없는 uid")
		w.H.uninstall()
	end)

	T.test(
		"정상이면 PetPetted(ownerUserId, uid) 가 서버 전체에 딱 한 번, 인자는 정확히 2개",
		function()
			local w = petWorld()
			w.H.client(w.player, "PetPet", "p1")
			local list = petted(w)
			T.eq(#list, 1)
			T.eq(list[1].n, 2)
			T.eq(list[1][1], 1001)
			T.eq(list[1][2], "p1")
			T.eq(#w.H.remotes.PetPetted.fired, 0)
			w.H.uninstall()
		end
	)

	T.test(
		"레이트 리밋: 같은 순간 100번 보내도 처리기는 burst(3) 번만 돌고, 1초 뒤 다시 허용",
		function()
			local w = petWorld()
			local calls = 0
			local real = w.PetService.petPet
			w.PetService.petPet = function(...)
				calls += 1
				return real(...)
			end
			for _ = 1, 100 do
				w.H.client(w.player, "PetPet", "p1")
			end
			T.eq(calls, 3)
			T.eq(#petted(w), 1)
			w.H.advance(1.5)
			w.H.client(w.player, "PetPet", "p1")
			T.eq(#petted(w), 2)
			w.PetService.petPet = real
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("5판 구멍 찾기: 퀘스트·선물 제거 — 찌꺼기 청소")

	local function lowerHas(text, words)
		text = string.gsub(string.lower(text), "request", "") -- RequestSnapshot 의 "quest" 는 봐줌
		for _, word in words do
			if string.find(text, word, 1, true) then
				return word
			end
		end
		return nil
	end
	local REMOVED = { "quest", "freereward", "claimfree", "questgate", "questonly" }

	T.test(
		"Remotes: QuestUpdate · ClaimFreeReward 가 이름·레이트 리밋 어디에도 없음, 실제 만들어진 RemoteEvent 에도 없음",
		function()
			local w = world()
			local Remotes = w.H.shared("Remotes")
			for _, group in { Remotes.ToClient, Remotes.ToServer, Remotes.RateLimits } do
				for key, value in group do
					T.eq(lowerHas(tostring(key), REMOVED), nil, "Remotes 에 남은 이름: " .. tostring(key))
					if typeof(value) == "string" then
						T.eq(lowerHas(value, REMOVED), nil, value)
					end
				end
			end
			T.eq(Remotes.ToClient.QuestUpdate, nil)
			T.eq(Remotes.ToServer.ClaimFreeReward, nil)
			T.eq(Remotes.RateLimits.ClaimFreeReward, nil)
			local made = 0
			for name, inst in w.H.remotes do
				made += 1
				T.eq(lowerHas(name, REMOVED), nil, "만들어진 Remote: " .. name)
				T.eq(inst.ClassName, "RemoteEvent")
			end
			local count = 0
			for _ in Remotes.ToClient do
				count += 1
			end
			for _ in Remotes.ToServer do
				count += 1
			end
			T.eq(made, count, "정의한 개수 = 만들어진 개수")
			-- 레이트 리밋은 클라 → 서버 Remote 만 (이름이 ToServer 에 있어야 함)
			for name in Remotes.RateLimits do
				T.truthy(Remotes.ToServer[name], "레이트 리밋만 남은 Remote: " .. name)
			end
			for name in Remotes.ToServer do
				T.truthy(Remotes.RateLimits[name], "레이트 리밋 없는 ToServer: " .. name)
			end
			w.H.uninstall()
		end
	)

	T.test(
		"마법의 숲 입구에 문·잠금 없음: MapLayout.specials.questGate 없음, MapLayout·Tags 어디에도 quest 찌꺼기 없음",
		function()
			local w = world()
			local MapLayout = w.H.shared("Data/MapLayout")
			local Tags = w.H.shared("Tags")
			T.eq(MapLayout.specials.questGate, nil)
			local function scan(tbl, path, depth)
				if depth > 4 then
					return
				end
				for key, value in tbl do
					T.eq(lowerHas(tostring(key), REMOVED), nil, path .. "." .. tostring(key))
					if typeof(value) == "string" then
						T.eq(lowerHas(value, REMOVED), nil, path .. "." .. tostring(key) .. " = " .. value)
					elseif typeof(value) == "table" then
						scan(value, path .. "." .. tostring(key), depth + 1)
					end
				end
			end
			scan(MapLayout.specials, "MapLayout.specials", 0)
			scan(Tags, "Tags", 0)
			T.eq(Tags.QuestGate, nil)
			T.eq(Tags.PlayerAttributes.QuestsDone, nil)
			-- 마법의 숲(퀘스트 문이 있던 곳)을 지나는 길에 세로 문처럼 가로막는 특수 장소가 없음
			local magic = MapLayout.biome("enchanted_forest")
			T.truthy(magic, "마법의 숲 구역")
			for name, spot in MapLayout.specials do
				if spot.biomeId == "enchanted_forest" then
					error("마법의 숲에 남은 특수 장소: " .. name)
				end
			end
			w.H.uninstall()
		end
	)

	T.test("저장 기본값·Snapshot 에 quests / questsRewarded / freeRewardClaimed / flags 없음", function()
		local w = world()
		local DataSchema = w.H.server("Logic/DataSchema")
		local Snapshot = w.H.server("Snapshot")
		local d = DataSchema.default(0)
		for _, key in { "quests", "questsRewarded", "freeRewardClaimed", "flags", "questsDone" } do
			T.eq(d[key], nil, "default." .. key)
		end
		local reconciled = DataSchema.reconcile({ version = 5, quests = { a = 1 }, freeRewardClaimed = true }, 0)
		T.eq(reconciled.quests, nil, "reconcile 도 quests 를 안 남김")
		T.eq(reconciled.freeRewardClaimed, nil)
		local p = join(w, 1, "Ann")
		local snap = Snapshot.build(p)
		for _, key in { "quests", "questsDone", "freeRewardClaimed", "flags" } do
			T.eq(snap[key], nil, "snapshot." .. key)
		end
		-- DataUpdate 구역 이름에도 quests/flags 없음
		for _, section in { "pets", "incubators", "eggs", "index", "upgrades", "tools", "special", "tutorial" } do
			Snapshot.section(p, section)
		end
		for _, args in w.H.sent(p, "DataUpdate") do
			T.eq(lowerHas(tostring(args[1]), REMOVED), nil, tostring(args[1]))
			T.truthy(args[1] ~= "flags")
		end
		w.H.uninstall()
	end)

	T.test(
		"없앤 개발 명령 /quests 는 아무 일도 안 하고 알림도 없음, /tutorial 만 동작",
		function()
			local w = world()
			w.H.server("Services/SakuraService")
			local DevCommands = w.H.server("Services/DevCommands")
			DevCommands.start()
			local p, _, data = join(w, 1001, "Dev")
			w.H.Players.PlayerAdded:Fire(p)
			local before = #w.H.sent(p, "Notify")
			p.Chatted:Fire("/quests")
			p.Chatted:Fire("/quests reset")
			p.Chatted:Fire("/gift")
			T.eq(#w.H.sent(p, "Notify"), before, "알림 없음")
			T.eq(data.quests, nil)
			p.Chatted:Fire("/tutorial reset")
			T.eq(data.tutorialStep, 1)
			w.H.uninstall()
		end
	)

	T.test(
		"둥지 알 어디에도 QuestOnly 가 없고, 60번 초기화한 모든 알을 새 사람(퀘스트 기록 없음)이 줍을 수 있음",
		function()
			local H = ServerHarness.install(Loader, T, { realEgg = true })
			H.startNet()
			local Sessions = H.server("Sessions")
			local EggService = H.server("Services/EggService")
			EggService.start()
			local p = H.newPlayer(1, "Fresh")
			local session = H.login(p)
			session.plotIndex = 1
			H.spawn(p, 0, 3, 0)
			H.setPhase("Intermission", 1)
			H.setPhase("Day", 1)
			for cycle = 2, 61 do
				H.setPhase("Intermission", cycle)
				H.setPhase("Day", cycle)
				for _, egg in H.map.folders.Eggs.children do
					T.eq(egg:GetAttribute("QuestOnly"), nil, "알 파트 QuestOnly")
					T.eq(egg.attributes.QuestOnly, nil)
				end
			end
			for _, args in H.remotes.Announce.firedAll do
				T.eq(args[1].questOnly, nil, "공지에 questOnly 없음")
			end
			-- 모든 구역에서 한 알씩 (마지막 초기화의 알) 새 사람이 줍기: 거부되는 알이 없어야 함
			local picked, eggs = 0, {}
			for _, egg in H.map.folders.Eggs.children do
				table.insert(eggs, egg)
			end
			for _, egg in eggs do
				if egg:GetAttribute("EggState") == "Nest" then
					p.attrs.CarryingEgg = ""
					EggService.dropCarried(p, "drop")
					session.carryingUid = nil
					H.teleport(p, egg.Position.X, egg.Position.Y, egg.Position.Z)
					EggService.tryPickup(p, egg:GetAttribute("EggUid"))
					if EggService.getCarried(p) then
						picked += 1
					end
				end
			end
			T.eq(picked, #eggs, "120개 모두 퀘스트 없이 주울 수 있음")
			_ = Sessions
			H.uninstall()
		end
	)

	T.test(
		"옛 퀘스트 알 2종(지터버그 · 영혼 세계 수호자): 여전히 EXTRA_SPECIALS 로 둥지에 나옴 — 400번 초기화에서 둘 다, 공지와 함께, 자기 구역에",
		function()
			local H = ServerHarness.install(Loader, T, { realEgg = true })
			H.startNet()
			local EggService = H.server("Services/EggService")
			local Pets = H.shared("Data/Pets")
			local EggSpawn = H.shared("Data/EggSpawn")
			EggService.start()
			H.setPhase("Intermission", 1)
			H.setPhase("Day", 1)
			local seen = { jitterbug = 0, spirit_world_guardian = 0 }
			for cycle = 2, 401 do
				H.setPhase("Intermission", cycle)
				for _, egg in H.map.folders.Eggs.children do
					local id = egg:GetAttribute("PetId")
					if seen[id] ~= nil then
						seen[id] += 1
						T.eq(egg:GetAttribute("BiomeId"), Pets.get(id).biome, id .. " 은 자기 구역 둥지에")
						T.eq(egg:GetAttribute("Special"), true, id .. " 은 공지 특별 알")
						T.eq(egg:GetAttribute("QuestOnly"), nil)
					end
				end
			end
			-- 확률: 지터버그 8% → 400번 중 약 32, 영혼 세계 수호자 1% → 약 4
			T.truthy(seen.jitterbug >= 12 and seen.jitterbug <= 70, "지터버그 " .. seen.jitterbug .. "번")
			T.truthy(seen.spirit_world_guardian >= 1, "영혼 세계 수호자 " .. seen.spirit_world_guardian .. "번")
			-- 둘 다 알 파트에서 직접 확인했으니, 데이터 표도 일치
			local listed = {}
			for _, entry in EggSpawn.EXTRA_SPECIALS do
				listed[entry.petId] = entry.chance
				T.eq(Pets.get(entry.petId).source, "special")
			end
			T.eq(listed.jitterbug, 0.08)
			T.eq(listed.spirit_world_guardian, 0.01)
			-- 공지도 그만큼 나갔는지
			local rareAnnounces = 0
			for _, args in H.remotes.Announce.firedAll do
				if
					args[1].kind == "rareEgg"
					and (args[1].petId == "jitterbug" or args[1].petId == "spirit_world_guardian")
				then
					rareAnnounces += 1
				end
			end
			T.truthy(rareAnnounces >= seen.jitterbug + seen.spirit_world_guardian - 2, "공지 " .. rareAnnounces)
			H.uninstall()
		end
	)

	T.test(
		"EggRoll.rollExtraSpecials: 난수 0 이면 둘 다, 난수 0.999 이면 아무것도 안 나옴, 모르는 펫 id 는 건너뜀",
		function()
			local EggRoll = Loader.require("ReplicatedStorage/Shared/EggRoll")
			local EggSpawn = Loader.require("ReplicatedStorage/Shared/Data/EggSpawn")
			local all = EggRoll.rollExtraSpecials(T.constant(0))
			T.eq(#all, 2)
			T.eq(#EggRoll.rollExtraSpecials(T.constant(0.999)), 0)
			-- 가장자리: 정확히 chance 이면 안 나옴(rand() < chance)
			T.eq(#EggRoll.rollExtraSpecials(T.constant(0.01)), 1, "0.01 → 지터버그(8%)만")
			-- 모르는 펫 id 가 섞이면 건너뜀
			table.insert(EggSpawn.EXTRA_SPECIALS, { petId = "no_such_pet", chance = 1 })
			local ok, list = pcall(EggRoll.rollExtraSpecials, T.constant(0))
			table.remove(EggSpawn.EXTRA_SPECIALS)
			T.truthy(ok, "모르는 펫 id 에 터짐")
			T.eq(#list, 2)
			-- 통계
			local rng = T.rng(99)
			local counts = { jitterbug = 0, spirit_world_guardian = 0 }
			local N = 20000
			for _ = 1, N do
				for _, pet in EggRoll.rollExtraSpecials(rng) do
					counts[pet.id] += 1
				end
			end
			T.near(counts.jitterbug / N, 0.08, 0.01)
			T.near(counts.spirit_world_guardian / N, 0.01, 0.004)
		end
	)
end
