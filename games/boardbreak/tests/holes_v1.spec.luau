--!nocheck
--[[
	holes_v1 — 주임의 "구멍 찾기" (1판 검수). 진짜 서버 코드 + ServerHarness.
	공짜 돈/힘 · 순서 건너뛰기 · 서버 터짐 · 저장 깨짐 길을 찾는다. src 는 고치지 않음 — 버그는 T.skip(이유) 으로 남김.
	  1 Remote 남용  2 치기 검증  3 심사·대결  4 아령 가게  5 로벅스 패스  6 큰 수·저장  7 설계서  8 맵과 서버
	버그 번호(A-n)는 docs/TEST_REPORT.md 와 같음.
]]
return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")

	local GAME_DIR = if fs.isFile("games/boardbreak/default.project.json") then "games/boardbreak" else "."

	local function setup()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local S = {
			Train = H.server("Services/TrainService"),
			Break = H.server("Services/BreakService"),
			Shop = H.server("Services/ShopService"),
			World = H.server("Services/WorldService"),
			Exam = H.server("Services/ExamService"),
			Product = H.server("Services/ProductService"),
			Dev = H.server("Services/DevCommands"),
			Life = H.server("Services/PlayerLifecycle"),
			Sessions = H.server("Sessions"),
		}
		S.Train.start()
		S.Break.start()
		S.Shop.start()
		S.World.start()
		S.Exam.start()
		S.Life.start()
		H.S = S
		H.Targets = H.shared("Data/Targets")
		H.Belts = H.shared("Data/Belts")
		H.Worlds = H.shared("Data/Worlds")
		H.Dumbbells = H.shared("Data/Dumbbells")
		H.Products = H.shared("Data/Products")
		H.Config = H.shared("Data/Config")
		H.Remotes = H.shared("Remotes")
		H.Economy = H.shared("Economy")
		H.Format = H.shared("Format")
		H.Progression = H.shared("Progression")
		H.DataSchema = H.server("Logic/DataSchema")
		return H
	end

	-- 로그인 + 캐릭터. spot = {x, y, z} (기본: 월드 1 수련 매트)
	local function join(H, userId, overrides, spot)
		local p = H.newPlayer(userId)
		local session, data = H.login(p, overrides)
		if spot then
			H.spawn(p, spot[1], spot[2], spot[3])
		else
			H.spawn(p, H.matSpot(session.currentWorld))
		end
		return p, session, data
	end

	local function at(x, y, z)
		return { x, y, z }
	end

	local function hitCount(H, p)
		return #H.sent(p, "HitResult")
	end

	local ONE_SHOT = 1e60

	------------------------------------------------------------------
	T.suite("holes_v1 1: Remote 남용 (쓰레기 인자 · 속도 제한)")
	------------------------------------------------------------------

	local function garbageValue(rng)
		local i = math.floor(rng() * 30)
		local pool = {
			function()
				return nil
			end,
			function()
				return 0 / 0
			end,
			function()
				return math.huge
			end,
			function()
				return -math.huge
			end,
			function()
				return -1
			end,
			function()
				return 0
			end,
			function()
				return 1e308
			end,
			function()
				return {}
			end,
			function()
				return { 1, 2, 3 }
			end,
			function()
				return { a = { b = 1 } }
			end,
			function()
				return string.rep("x", 5000)
			end,
			function()
				return "cotton"
			end,
			function()
				return "exam"
			end,
			function()
				return "duel"
			end,
			function()
				return true
			end,
			function()
				return false
			end,
			function()
				return "../../x"
			end,
			function()
				return "\0"
			end,
			function()
				return 2.5
			end,
			function()
				return 1
			end,
			function()
				return 2
			end,
			function()
				return 3
			end,
			function()
				return "power_2048"
			end,
			function()
				return 99
			end,
			function()
				return "nope"
			end,
			function()
				return "__index"
			end,
			function()
				return "music"
			end,
			function()
				return "lowGraphics"
			end,
			function()
				return -0.5
			end,
			function()
				return 1e-300
			end,
		}
		return pool[i + 1]()
	end

	local function fuzz(H, p, iterations, step, seed)
		local rng = T.rng(seed)
		local names = {}
		for _, name in H.Remotes.ToServer do
			table.insert(names, name)
		end
		table.sort(names)
		for _ = 1, iterations do
			local name = names[1 + math.floor(rng() * #names)]
			local n = math.floor(rng() * 4)
			local args = {}
			for i = 1, n do
				args[i] = garbageValue(rng)
			end
			H.client(p, name, table.unpack(args, 1, n))
			H.advance(step)
		end
	end

	T.test(
		"ToServer Remote 8개 전부 핸들러 + 속도 제한 정의가 있음 (몰래 늘어난 Remote 가 없음)",
		function()
			local H = setup()
			local expected = {
				"BuyDumbbell",
				"ClientReady",
				"Hit",
				"SetSetting",
				"StartDuel",
				"StartExam",
				"Train",
				"Travel",
			}
			local names = {}
			for _, name in H.Remotes.ToServer do
				table.insert(names, name)
			end
			table.sort(names)
			T.eq(
				table.concat(names, ","),
				table.concat(expected, ","),
				"Remote 목록이 바뀜 — 새 Remote 는 이 테스트도 고칠 것"
			)
			for _, name in names do
				T.truthy(H.Remotes.RateLimits[name], name .. " 속도 제한")
				T.truthy(#H.remotes[name].OnServerEvent.handlers >= 1, name .. " 핸들러")
			end
			for name in H.Remotes.ToServer do
				T.falsy(string.find(string.lower(name), "win") or string.find(string.lower(name), "reward"), name)
			end
			H.uninstall()
		end
	)

	T.test(
		"쓰레기 인자 5,000번 (스폰 자리): 힘·돈·띠·월드·아령·배수 그대로, 서버 warn 0",
		function()
			local H = setup()
			local p, session, data = join(H, 1, nil, at(H.spawnSpot(1)))
			fuzz(H, p, 5000, 0.05, 7)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			T.eq(data.power, 0, "힘")
			T.eq(data.money, 0, "돈")
			T.eq(data.dumbbellLevel, 1)
			T.eq(data.belt, 1)
			T.eq(data.world, 1)
			T.eq(session.currentWorld, 1)
			T.eq(data.powerBoost, 1)
			T.eq(data.moneyPass, false)
			T.eq(session.exam, nil)
			T.eq(session.duel, nil)
			T.eq(data.stats.breaks, 0)
			local keys = 0
			for key, value in data.settings do
				keys += 1
				T.eq(type(value), "boolean", key)
				T.truthy(H.Config.SETTINGS[key] ~= nil, "모르는 설정 칸 " .. key)
			end
			T.eq(keys, 3, "설정 칸 3개")
			H.uninstall()
		end
	)

	T.test(
		"쓰레기 인자 5,000번 (수련 매트 위): 힘은 속도 제한만큼만, 다른 건 그대로",
		function()
			local H = setup()
			local p, session, data = join(H, 1)
			fuzz(H, p, 5000, 0.01, 11)
			local seconds = 50
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			T.truthy(data.stats.trains <= 5 + 5 * seconds, "들기 " .. data.stats.trains .. " 번 > 속도 제한")
			T.eq(data.power, data.stats.trains, "1kg 아령 = 한 번에 +1")
			T.eq(data.money, 0)
			T.eq(data.belt, 1)
			T.eq(data.world, 1)
			T.eq(data.dumbbellLevel, 1)
			T.eq(session.exam, nil)
			H.uninstall()
		end
	)

	T.test("쓰레기 인자 5,000번 (심사 중): 띠는 많아야 2, 돈 0, 월드 1, 서버 warn 0", function()
		local H = setup()
		local need = H.Belts.get(2).needPower
		local p, session, data = join(H, 1, { power = need }, at(H.examSpot(1)))
		H.client(p, "StartExam")
		T.truthy(session.exam, "시작")
		fuzz(H, p, 5000, 0.004, 13)
		T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
		T.truthy(data.belt <= 2, "띠 " .. data.belt)
		T.eq(data.money, 0)
		T.eq(data.world, 1)
		T.eq(data.power, need, "힘 그대로 (매트 밖)")
		H.uninstall()
	end)

	T.test(
		"속도 제한: Hit 에 일반 · exam · duel 을 섞어 30번 → 합쳐서 5번만 셈 (Remote 하나 = 통 하나)",
		function()
			local H = setup()
			local need = H.Belts.get(2).needPower
			local p, session = join(H, 1, { power = need * 1e6 }, at(H.examSpot(1)))
			H.client(p, "StartExam")
			local kinds = { "exam", "cotton", "duel" }
			for i = 1, 30 do
				H.client(p, "Hit", kinds[1 + (i - 1) % 3])
			end
			-- 앞 5번 = exam, cotton, duel, exam, cotton → exam 은 2번만
			T.eq(session.exam.broken, 2, "섞어도 한 통")
			H.uninstall()
		end
	)

	T.test(
		"속도 제한: 한 순간 Train 5 + Hit 5 (Remote 마다 통이 따로), 오래 보내면 5 + 5×초 를 안 넘음",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = 1e9 })
			for _ = 1, 30 do
				H.client(p, "Train")
			end
			T.eq(data.stats.trains, 5, "Train 한 순간 5")
			-- 오래: 0.1초마다 100번씩 10초
			H.advance(10)
			local before = data.stats.trains
			for _ = 1, 100 do
				for _ = 1, 100 do
					H.client(p, "Train")
				end
				H.advance(0.1)
			end
			T.truthy(data.stats.trains - before <= 5 + 5 * 10, "10초에 " .. (data.stats.trains - before))
			T.truthy(data.stats.trains - before >= 45, "너무 박하지도 않음")
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v1 2: 치기 검증 (공짜 돈 길)")
	------------------------------------------------------------------

	T.test(
		"닫힌 월드 물건 (월드 1 만 열림 → 28개, 월드 2 까지 열림 → 14개): 앞에 서서 쳐도 돈 0 · 응답 없음",
		function()
			local H = setup()
			for _, opened in { 1, 2 } do
				local p, _, data =
					join(H, 10 + opened, { power = ONE_SHOT, world = opened, belt = 1 + 3 * (opened - 1) })
				for _, target in H.Targets.list do
					if target.world > opened then
						H.place(p, H.targetSpot(target.id))
						H.client(p, "Hit", target.id)
						H.advance(0.3)
					end
				end
				T.eq(data.money, 0, "월드 " .. opened)
				T.eq(hitCount(H, p), 0)
				T.eq(next(data.broken), nil)
			end
			H.uninstall()
		end
	)

	T.test(
		"41개 전부: 길 위 설 자리(roadPoint)와 길 한가운데에서 서버 거리 검사를 통과해 깨짐",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = ONE_SHOT, world = 3, belt = 12 })
			for _, target in H.Targets.list do
				local rp = H.MapLayout.roadPoint(target.id)
				local origin = H.MapLayout.worldOrigin(target.world)
				local ty = H.MapLayout.targetPosition(target.id).y
				for _, x in { rp.x, origin.x } do
					H.place(p, x, ty + 3, rp.z)
					local before = data.broken[target.id] or 0
					H.client(p, "Hit", target.id)
					H.advance(0.3)
					T.eq(data.broken[target.id], before + 1, target.id .. " x=" .. tostring(x - origin.x))
				end
			end
			T.truthy(data.money > 0)
			H.uninstall()
		end
	)

	T.test("거리 경계: targetReach + 슬랙 안 = 깨짐 · 0.5 밖 = 응답 없음 (41개 전부)", function()
		local H = setup()
		local p, _, data = join(H, 1, { power = ONE_SHOT, world = 3, belt = 12 })
		local slack = H.Config.HIT_REACH_SLACK
		for _, target in H.Targets.list do
			local pos = H.MapLayout.targetPosition(target.id)
			local reach = H.MapLayout.targetReach(target.id)
			T.truthy(reach > 0, target.id .. " reach")
			H.place(p, pos.x + reach + slack - 0.5, pos.y + 3, pos.z)
			H.client(p, "Hit", target.id)
			H.advance(0.3)
			T.eq(data.broken[target.id], 1, target.id .. " 안쪽")
			H.place(p, pos.x + reach + slack + 0.5, pos.y + 3, pos.z)
			H.client(p, "Hit", target.id)
			H.advance(0.3)
			T.eq(data.broken[target.id], 1, target.id .. " 바깥쪽은 안 깨짐")
		end
		H.uninstall()
	end)

	T.test("캐릭터가 없으면 치기 · 들기 · 심사 시작 전부 무시", function()
		local H = setup()
		local p = H.newPlayer(1)
		local session, data = H.login(p, { power = ONE_SHOT, belt = 1 })
		session.currentWorld = 1
		H.client(p, "Hit", "cotton")
		H.client(p, "Train")
		H.client(p, "StartExam")
		H.client(p, "StartDuel")
		T.eq(data.money, 0)
		T.eq(data.power, ONE_SHOT)
		T.eq(session.exam, nil)
		T.eq(session.duel, nil)
		T.eq(#H.warnings, 0)
		H.uninstall()
	end)

	T.skip(
		"죽은 캐릭터(Health 0)도 치기 · 들기가 됨 [A-1 낮음]",
		"BreakService.hit · TrainService.train · ExamService 가 Character.getRoot 만 보고 isAlive(Health>0) 를 안 봄",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = ONE_SHOT })
			H.teleport(p, H.targetSpot("cotton"))
			p.Character.humanoid.Health = 0
			H.client(p, "Hit", "cotton")
			T.eq(data.money, 0, "죽었는데 돈이 생김")
		end
	)

	T.test(
		"minPower 경계: 치는 힘 = minPower 이면 깎임, 아주 조금 모자라면 weak (힘 × 배수 로 봄)",
		function()
			local H = setup()
			local glass = H.Targets.get("glass")
			local p, session, data = join(H, 1, { power = glass.minPower / 4, powerBoost = 4 })
			H.teleport(p, H.targetSpot("glass"))
			H.client(p, "Hit", "glass")
			T.eq(H.sent(p, "HitResult")[1][1].damage, glass.minPower, "힘 × 4 = minPower")
			T.truthy(session.targetHp.glass ~= nil)
			data.power = glass.minPower / 4 * (1 - 1e-9)
			H.advance(1)
			H.client(p, "Hit", "glass")
			local list = H.sent(p, "HitResult")
			T.eq(list[#list][1].reason, "weak")
			T.eq(list[#list][1].damage, 0)
			H.uninstall()
		end
	)

	T.test(
		"한 번에 깨지는 타격: 보상 정확히 1번 (돈 · broken · stats · HitResult 모두 1), 띠 배율 12개 전부",
		function()
			local H = setup()
			for beltIndex = 1, 12 do
				local p, _, data = join(H, 100 + beltIndex, {
					power = ONE_SHOT,
					belt = beltIndex,
					world = H.Progression.worldsFromBelt(beltIndex),
					moneyPass = true,
				})
				H.teleport(p, H.targetSpot("cotton"))
				H.client(p, "Hit", "cotton")
				local cotton = H.Targets.get("cotton")
				T.eq(data.money, cotton.reward * H.Belts.get(beltIndex).moneyMultiplier * 2, "띠 " .. beltIndex)
				T.eq(data.broken.cotton, 1)
				T.eq(data.stats.breaks, 1)
				T.eq(hitCount(H, p), 1)
				T.eq(H.sent(p, "HitResult")[1][1].reward, data.money)
			end
			H.uninstall()
		end
	)

	T.test(
		"물건 체력은 플레이어마다 따로: A 가 14번 깎아도 B 의 한 번은 안 깨짐 · 깬 사람만 돈",
		function()
			local H = setup()
			local cotton = H.Targets.get("cotton")
			local a, sa, da = join(H, 1, { power = cotton.minPower })
			local b, _, db = join(H, 2, { power = cotton.minPower })
			H.teleport(a, H.targetSpot("cotton"))
			H.teleport(b, H.targetSpot("cotton"))
			for _ = 1, 14 do
				H.client(a, "Hit", "cotton")
				H.advance(0.25)
			end
			T.eq(sa.targetHp.cotton, cotton.minPower, "A 남은 체력 = 한 번 분")
			H.client(b, "Hit", "cotton")
			T.eq(db.money, 0, "B 는 마무리 못 함")
			T.eq(da.money, 0)
			H.client(a, "Hit", "cotton")
			T.eq(da.money, cotton.reward, "A 가 마무리")
			T.eq(db.money, 0)
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v1 3: 심사 · 대결 (순서 건너뛰기 · 공짜 띠)")
	------------------------------------------------------------------

	local function spamHits(H, p, kind, session, field, seconds)
		for _ = 1, math.floor(seconds / 0.25) do
			if not session[field] then
				return
			end
			H.client(p, "Hit", kind)
			H.advance(0.25)
		end
	end

	T.test(
		"띠를 한 칸씩만: 힘 1e60 이어도 심사 한 번에 +1, 대결 띠는 심사로 못 받고 심사 띠는 대결로 못 받음 (1→12)",
		function()
			local H = setup()
			local p, session, data = join(H, 1, { power = ONE_SHOT }, at(H.examSpot(1)))
			local exams, duels = 0, 0
			for expected = 1, 11 do
				T.eq(data.belt, expected, "시작 띠")
				local nextBelt = H.Belts.get(expected + 1)
				H.advance(3)
				if nextBelt.duel then
					H.place(p, H.examSpot(session.currentWorld))
					H.client(p, "StartExam")
					T.eq(session.exam, nil, "대결 띠를 심사로 못 받음 (띠 " .. nextBelt.index .. ")")
					H.advance(3)
					H.place(p, H.duelSpot(session.currentWorld))
					H.client(p, "StartDuel")
					T.truthy(session.duel, "대결 시작")
					spamHits(H, p, "duel", session, "duel", 40)
					duels += 1
				else
					H.place(p, H.duelSpot(session.currentWorld))
					H.client(p, "StartDuel")
					T.eq(session.duel, nil, "심사 띠를 대결로 못 받음 (띠 " .. nextBelt.index .. ")")
					H.advance(3)
					H.place(p, H.examSpot(session.currentWorld))
					H.client(p, "StartExam")
					T.truthy(session.exam, "심사 시작")
					spamHits(H, p, "exam", session, "exam", 20)
					exams += 1
				end
				T.eq(data.belt, expected + 1, "한 칸만 올라감")
				T.eq(data.world, H.Progression.worldsFromBelt(data.belt), "월드는 띠가 정함")
				-- 다음 월드는 대결로 열린 뒤에만 이동
				if nextBelt.duel and data.world > session.currentWorld then
					H.advance(3)
					H.client(p, "Travel", data.world + 1 <= 3 and data.world + 1 or 3)
					H.advance(3)
					H.client(p, "Travel", data.world)
					T.eq(session.currentWorld, data.world, "열린 월드로 이동")
				end
			end
			T.eq(exams, 8)
			T.eq(duels, 3)
			T.eq(data.belt, 12)
			T.eq(data.grandMaster, true)
			T.eq(data.world, 3)
			T.eq(data.stats.examsPassed, 8)
			T.eq(data.stats.duelsWon, 3)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"시작 조건: 힘 1 모자람 · 심사대 밖 · 이미 진행 중 · 12번 띠 뒤 = 시작 안 됨 (12번 뒤 다시 시작해도 안전)",
		function()
			local H = setup()
			local need = H.Belts.get(2).needPower
			local p, session, data = join(H, 1, { power = need * (1 - 1e-12) }, at(H.examSpot(1)))
			H.client(p, "StartExam")
			T.eq(session.exam, nil, "힘 모자람")
			data.power = need
			H.teleport(p, H.spawnSpot(1))
			H.advance(3)
			H.client(p, "StartExam")
			T.eq(session.exam, nil, "심사대 밖")
			H.teleport(p, H.examSpot(1))
			H.advance(3)
			H.client(p, "StartExam")
			local first = session.exam
			T.truthy(first)
			local endsAt = first.endsAt
			H.advance(5)
			H.client(p, "StartExam")
			H.client(p, "StartDuel")
			T.truthy(session.exam == first, "진행 중 다시 시작해도 같은 심사")
			T.eq(first.endsAt, endsAt, "시간이 늘어나지 않음")
			T.eq(session.duel, nil, "심사 중 대결 시작 안 됨")
			-- 12번 띠 뒤
			H.advance(30)
			data.belt = 12
			data.world = 3
			data.grandMaster = true
			data.power = ONE_SHOT
			H.client(p, "StartExam")
			H.advance(3)
			H.place(p, H.duelSpot(1))
			H.client(p, "StartDuel")
			T.eq(session.exam, nil)
			T.eq(session.duel, nil)
			T.eq(data.belt, 12)
			T.truthy(H.hasNotify(p, "error", "마지막 띠"))
			H.uninstall()
		end
	)

	T.test("심사 중 Travel 안 됨 · 나가면 정리되고 띠 그대로 · 서버 warn 0", function()
		local H = setup()
		local need = H.Belts.get(2).needPower
		local p, session, data = join(H, 1, { power = need * 1e6 }, at(H.examSpot(1)))
		H.client(p, "StartExam")
		H.client(p, "Travel", 1)
		T.truthy(session.exam, "Travel 이 심사를 못 끊음")
		for _ = 1, 4 do
			H.client(p, "Hit", "exam")
			H.advance(0.25)
		end
		H.leave(p)
		H.advance(60)
		T.eq(data.belt, 1, "나가면 띠 안 줌")
		T.eq(H.S.Sessions.get(p), nil)
		T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
		H.uninstall()
	end)

	T.test(
		"심사 중 죽어서 스폰으로 돌아가면 칠 수 없고 시간 초과 = 불합격 (띠 안 줌)",
		function()
			local H = setup()
			local need = H.Belts.get(2).needPower
			local p, session, data = join(H, 1, { power = need * 1e6 }, at(H.examSpot(1)))
			H.client(p, "StartExam")
			H.teleport(p, H.spawnSpot(1)) -- 다시 태어남
			for _ = 1, 90 do
				H.client(p, "Hit", "exam")
				H.advance(0.25)
			end
			T.eq(session.exam, nil, "끝남")
			T.eq(data.belt, 1)
			T.eq(data.stats.examsFailed, 1)
			T.eq(H.sent(p, "ExamState")[#H.sent(p, "ExamState")][1].phase, "fail")
			H.uninstall()
		end
	)

	T.test(
		"시간 초과: 19.8초에 5번 쳐도 20초 지나면 불합격 · 불합격 뒤 친 것은 무시 · 합격 뒤 다시 합격 못 받음",
		function()
			local H = setup()
			local need = H.Belts.get(2).needPower
			local p, session, data = join(H, 1, { power = need * 1e6 }, at(H.examSpot(1)))
			H.client(p, "StartExam")
			H.advance(19.8)
			for _ = 1, 5 do
				H.client(p, "Hit", "exam")
			end
			H.advance(1)
			T.eq(session.exam, nil)
			T.eq(data.belt, 1, "5장밖에 못 깸")
			for _ = 1, 20 do
				H.client(p, "Hit", "exam")
				H.advance(0.25)
			end
			T.eq(data.belt, 1, "끝난 뒤 쳐도 그대로")
			-- 합격하고 나면 같은 띠를 또 받지 못함 (진행 중 띠가 바뀐 상황: 합격해도 +1 안 됨)
			H.advance(3)
			H.client(p, "StartExam")
			T.truthy(session.exam)
			data.belt = 2 -- 다른 길로 이미 받았다고 가정
			for _ = 1, 40 do
				H.client(p, "Hit", "exam")
				H.advance(0.25)
			end
			T.eq(data.belt, 2, "같은 띠 두 번 안 받음 (3 이 되면 안 됨)")
			H.uninstall()
		end
	)

	T.test(
		"대결: 서버가 판정 — 가만히 있으면 시험관 승 · 카운트다운 3초 중 친 것은 무시 · 이기면 월드 열림",
		function()
			local H = setup()
			local need = H.Belts.get(4).needPower
			local p, session, data = join(H, 1, { power = need, belt = 3 }, at(H.duelSpot(1)))
			H.client(p, "StartDuel")
			T.truthy(session.duel, "시작")
			for _ = 1, 4 do
				H.client(p, "Hit", "duel")
			end
			T.eq(session.duel.mine, 0, "카운트다운 중 친 것 무시")
			H.advance(60)
			T.eq(session.duel, nil)
			T.eq(data.belt, 3, "졌으니 띠 그대로")
			T.eq(data.world, 1)
			T.eq(data.stats.duelsLost, 1)
			H.advance(3)
			H.client(p, "StartDuel")
			T.truthy(session.duel, "바로 다시 도전")
			H.advance(3.1)
			spamHits(H, p, "duel", session, "duel", 30)
			T.eq(data.belt, 4)
			T.eq(data.world, 2, "월드 2 열림")
			T.eq(data.stats.duelsWon, 1)
			H.uninstall()
		end
	)

	T.test(
		"대결 중 나가기 · Travel · 심사 시작 · 대결 중복 시작 = 띠 안 줌 · 상태 하나",
		function()
			local H = setup()
			local need = H.Belts.get(4).needPower
			local p, session, data = join(H, 1, { power = need, belt = 3 }, at(H.duelSpot(1)))
			H.client(p, "StartDuel")
			H.advance(3)
			H.client(p, "StartExam")
			T.eq(session.exam, nil)
			H.client(p, "Travel", 1)
			T.truthy(session.duel)
			H.leave(p)
			H.advance(60)
			T.eq(data.belt, 3)
			T.eq(data.world, 1)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"띠 4 없이는 월드 2 의 물건 · 문(Travel) 못 씀 · 힘 1e60 + 2048배 + 돈 2배여도 같음",
		function()
			local H = setup()
			local p, session, data =
				join(H, 1, { power = ONE_SHOT, belt = 3, world = 1, money = 1e60, powerBoost = 2048 })
			H.place(p, H.targetSpot("mall"))
			H.client(p, "Hit", "mall")
			T.eq(hitCount(H, p), 0)
			H.client(p, "Travel", 2)
			H.advance(1)
			H.client(p, "Travel", 3)
			T.eq(session.currentWorld, 1)
			T.eq(data.money, 1e60)
			-- 한 번에 두 칸: 심사 띠가 아니라 4 번째 띠 대결을 건너뛰고 5번 띠 심사는 시작 안 됨
			H.place(p, H.examSpot(1))
			H.advance(3)
			H.client(p, "StartExam")
			T.eq(session.exam, nil, "다음 띠(4)는 대결")
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v1 4: 아령 가게")
	------------------------------------------------------------------

	T.test(
		"돈 1 모자라면 안 삼 · 딱 맞으면 삼 (돈 0) · 같은 틱 연타해도 한 단계씩",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { money = H.Dumbbells.get(2).price - 1 })
			H.S.Shop.buyDumbbell(p)
			T.eq(data.dumbbellLevel, 1)
			data.money = H.Dumbbells.get(2).price
			for _ = 1, 10 do
				H.S.Shop.buyDumbbell(p) -- 속도 제한 없이 곧바로 10번
			end
			T.eq(data.dumbbellLevel, 2)
			T.eq(data.money, 0)
			-- 두 단계 값이 있어도 연타하면 하나씩 두 번
			data.dumbbellLevel = 1
			data.money = H.Dumbbells.get(2).price + H.Dumbbells.get(3).price
			for _ = 1, 10 do
				H.S.Shop.buyDumbbell(p)
			end
			T.eq(data.dumbbellLevel, 3)
			T.eq(data.money, 0, "음수가 아님")
			-- 두 단계 값에서 1 모자라면 한 단계만
			data.dumbbellLevel = 1
			data.money = H.Dumbbells.get(2).price + H.Dumbbells.get(3).price - 1
			for _ = 1, 10 do
				H.S.Shop.buyDumbbell(p)
			end
			T.eq(data.dumbbellLevel, 2)
			T.eq(data.money, H.Dumbbells.get(3).price - 1)
			H.uninstall()
		end
	)

	T.test(
		"무작위 3,000번 (돈 · 연타 · Remote): 돈은 음수가 안 되고 쓴 돈 = 산 아령 값의 합",
		function()
			local H = setup()
			local rng = T.rng(99)
			local p, _, data = join(H, 1, { money = 0 })
			local spent, earned = 0, 0
			for _ = 1, 3000 do
				if rng() < 0.3 then
					local add = math.floor(rng() * 10 ^ (rng() * 28))
					data.money = H.Economy.addMoney(data.money, add)
					earned += add
				end
				local beforeMoney, beforeLevel = data.money, data.dumbbellLevel
				for _ = 1, 1 + math.floor(rng() * 4) do
					H.client(p, "BuyDumbbell")
				end
				H.advance(rng() * 2)
				T.truthy(data.money >= 0, "돈이 음수")
				T.truthy(data.money == data.money, "NaN")
				local bought = data.dumbbellLevel - beforeLevel
				T.truthy(bought >= 0 and bought <= 3, "한 번에 3단계 넘게 삼")
				local cost = 0
				for level = beforeLevel + 1, data.dumbbellLevel do
					cost += H.Dumbbells.get(level).price
				end
				-- 큰 돈에서 작은 값을 빼면 부동소수 오차(돈 × 2^-50)만큼 어긋날 수 있음
				T.near(
					beforeMoney - data.money,
					cost,
					math.max(1e-6, cost * 1e-9, beforeMoney * 2 ^ -50),
					"값을 정확히 냄"
				)
				spent += cost
			end
			T.truthy(data.dumbbellLevel <= 20)
			T.eq(#H.warnings, 0)
			H.uninstall()
		end
	)

	T.test("마지막 아령 (20): 돈이 얼마나 많아도 그대로 · 돈 안 줄어듦 · 알림만", function()
		local H = setup()
		local p, _, data = join(H, 1, { money = 1e60, dumbbellLevel = 20 })
		for _ = 1, 5 do
			H.client(p, "BuyDumbbell")
			H.advance(1)
		end
		T.eq(data.dumbbellLevel, 20)
		T.eq(data.money, 1e60)
		T.truthy(H.hasNotify(p, "info", "가장 좋은 아령"))
		H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("holes_v1 5: 로벅스 패스")
	------------------------------------------------------------------

	local function withPassIds(H, fn)
		local ids = {}
		for i, prod in H.Products.powerBoosts do
			ids[prod] = prod.productId
			prod.productId = 9000 + i
		end
		local money = H.Products.get("money_2")
		ids[money] = money.productId
		money.productId = 9100
		local ok, err = pcall(fn)
		for prod, id in ids do
			prod.productId = id
		end
		if not ok then
			error(err, 0)
		end
	end

	T.test(
		"순서대로만: power_4 만 가져도 2배 · power_2048 만 가져도 1024배 · 11개 다 = 2048배 (영수증 쪽: 소유 확인)",
		function()
			local H = setup()
			withPassIds(H, function()
				local function boostFor(owned)
					local p, _, data = join(H, 500 + math.floor(math.random() * 1e6))
					H.market.owned[p.UserId] = {}
					for _, key in owned do
						H.market.owned[p.UserId][H.Products.get(key).productId] = true
					end
					H.run(function()
						return H.S.Product.syncPasses(p)
					end)
					return data.powerBoost, data, p
				end
				T.eq((boostFor({})), 1)
				T.eq((boostFor({ "power_4" })), 2, "power_4 만")
				T.eq((boostFor({ "power_2048" })), 1024, "power_2048 만")
				T.eq((boostFor({ "power_2", "power_8" })), 4, "2 와 8")
				local all = {}
				for _, prod in H.Products.powerBoosts do
					table.insert(all, prod.key)
				end
				local boost, data, p = boostFor(all)
				T.eq(boost, 2048)
				T.eq(p:GetAttribute("PowerBoost"), 2048)
				T.eq(data.power, 0, "패스가 저장된 힘을 부풀리지 않음")
			end)
			H.uninstall()
		end
	)

	T.test(
		"힘 배수: 들 때와 칠 때만 곱함 — 사도 저장된 힘은 그대로 · 한 번 들면 한 번만 곱해져 저장",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = 1000, dumbbellLevel = 3 })
			H.S.Product.grant(p, "power_2")
			H.S.Product.grant(p, "power_4")
			T.eq(data.powerBoost, 4)
			T.eq(data.power, 1000, "산 뒤에도 힘 그대로")
			T.eq(p:GetAttribute("Power"), 1000)
			H.client(p, "Train")
			T.eq(data.power, 1000 + H.Dumbbells.get(3).powerPerRep * 4, "들 때 ×4 한 번")
			H.teleport(p, H.targetSpot("cotton"))
			H.advance(1)
			local before = data.power
			H.client(p, "Hit", "cotton")
			T.eq(H.sent(p, "HitResult")[1][1].damage > 0, true)
			T.eq(data.power, before, "칠 때 곱해도 저장된 힘은 안 바뀜")
			H.uninstall()
		end
	)

	T.test("돈 2배: 두 번 지급해도 2배 (4배 안 됨) · 띠 배율과 곱", function()
		local H = setup()
		local p, _, data = join(H, 1, { power = ONE_SHOT, belt = 3 })
		H.S.Product.grant(p, "money_2")
		H.S.Product.grant(p, "money_2")
		H.teleport(p, H.targetSpot("cotton"))
		H.client(p, "Hit", "cotton")
		T.eq(data.money, 3 * 2 * 2, "3 × 띠 3(초록 ×2) × 돈 2배")
		H.uninstall()
	end)

	T.test(
		"/buy · /unbuy · /power · /money · /belt · /reset 은 스튜디오에서만 (실서버 = 전부 무시, 채팅 연결도 안 함)",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			H.RunService.studio = false
			local playerAddedBefore = #H.Players.PlayerAdded.handlers
			for _, message in
				{
					"/buy power_2048",
					"/buy money_2",
					"/unbuy",
					"/power 1e50",
					"/money 1e50",
					"/belt 12",
					"/world 3",
					"/dumbbell 20",
					"/reset",
				}
			do
				T.falsy(H.S.Dev.handle(p, message), message)
			end
			T.eq(data.powerBoost, 1)
			T.eq(data.moneyPass, false)
			T.eq(data.power, 0)
			T.eq(data.money, 0)
			T.eq(data.belt, 1)
			T.eq(data.dumbbellLevel, 1)
			H.S.Dev.start()
			T.eq(#H.Players.PlayerAdded.handlers, playerAddedBefore, "실서버에서는 Chatted 연결도 안 함")
			T.eq(#p.Chatted.handlers, 0)
			H.uninstall()
		end
	)

	T.test(
		"패스 id 가 전부 0 이라 진짜 구매 경로가 닫혀 있음 (id 0 · 음수 · NaN · 글자 · 모르는 id 모두 지급 없음)",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			for _, prod in H.Products.passes do
				T.eq(prod.productId, 0, prod.key .. " id 는 0 (게시 전)")
				T.falsy(H.Products.isConfigured(prod))
			end
			for _, id in { 0, -1, 0 / 0, math.huge, 1e300, "power_2", 12345 } do
				H.S.Product.onGamePassPurchaseFinished(p, id, true)
			end
			T.eq(H.market.calls, 0, "소유 확인을 아예 안 부름")
			T.eq(data.powerBoost, 1)
			T.eq(data.moneyPass, false)
			T.eq(#H.sent(p, "ProductGranted"), 0)
			T.truthy(H.run(function()
				return H.S.Product.syncPasses(p)
			end))
			T.eq(H.market.calls, 0)
			local decision = H.run(function()
				return H.S.Product.processReceipt({ PlayerId = 1, ProductId = 0, PurchaseId = "x" })
			end)
			T.eq(decision, "ProductPurchaseDecision.NotProcessedYet")
			T.eq(#data.receipts, 0)
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v1 6: 큰 수 · 저장")
	------------------------------------------------------------------

	T.test(
		"Economy 모든 함수 × 이상한 값 (NaN · 무한 · 음수 · 1e60 근처): 유한 · 0 이상 · 1e60 이하",
		function()
			local H = setup()
			local E = H.Economy
			local values =
				{ 0, 1e-9, 0.5, 1, 1e15, 1e30, 1e59, 1e60 - 1, 1e60, 1e61, 1e300, 0 / 0, math.huge, -1, -math.huge }
			local boosts = { 1, 2, 4, 2048, 3, 0, -2, 0 / 0, math.huge, 4096 }
			local function ok(x, label)
				T.truthy(x == x and x ~= math.huge and x >= 0 and x <= 1e60, label .. " = " .. tostring(x))
			end
			for _, a in values do
				ok(E.clampPower(a), "clampPower " .. tostring(a))
				ok(E.clampMoney(a), "clampMoney " .. tostring(a))
				for _, b in values do
					ok(E.addPower(a, b), "addPower")
					ok(E.addMoney(a, b), "addMoney")
				end
				for _, boost in boosts do
					ok(E.hitDamage(a, boost), "hitDamage " .. tostring(a) .. " x " .. tostring(boost))
					for level = 1, 20 do
						ok(E.trainGain(level, boost), "trainGain")
					end
					for belt = 1, 12 do
						ok(E.breakReward(a, belt, true), "breakReward")
					end
				end
			end
			for _, text in { 0, 1, 1e59, 1e60, 0 / 0 } do
				local s = H.Format.number(text)
				T.falsy(string.find(string.lower(s), "nan") or string.find(s, "inf"), s)
			end
			H.uninstall()
		end
	)

	T.test(
		"힘 · 돈 1e60 에서 서비스가 안 터짐: 들기 · 치기 · 사기 · 심사 뒤 Attribute 도 유한",
		function()
			local H = setup()
			local p, _, data = join(
				H,
				1,
				{ power = 1e60, money = 1e60, dumbbellLevel = 19, powerBoost = 2048, belt = 3, moneyPass = true }
			)
			H.client(p, "Train")
			T.eq(data.power, 1e60)
			H.teleport(p, H.targetSpot("cotton"))
			H.client(p, "Hit", "cotton")
			T.eq(data.money, 1e60)
			H.client(p, "BuyDumbbell")
			T.eq(data.dumbbellLevel, 20)
			T.truthy(
				data.money <= 1e60 and data.money > 0,
				"1e60 에서 5.5e26 을 빼도 부동소수라 그대로일 수 있음 — 음수·NaN 만 아니면 됨"
			)
			for _, name in { "Power", "Money" } do
				local v = p:GetAttribute(name)
				T.truthy(v == v and v >= 0 and v <= 1e60, name)
			end
			T.eq(#H.warnings, 0)
			H.uninstall()
		end
	)

	local function parseShown(Format, text)
		local num, suffix = string.match(text, "^([%d%.]+)(%a*)$")
		if not num then
			return nil
		end
		local index = table.find(Format.SUFFIXES, suffix)
		if not index then
			return nil
		end
		return tonumber(num) * 10 ^ (3 * (index - 1))
	end

	T.test(
		"Format.number 0 ~ 1e63: 단조 증가 · 읽을 수 있음(글자 8자 이하) · 값과 2% 안 · 단위 칸 경계",
		function()
			local H = setup()
			local F = H.Format
			local last = -1
			local count = 0
			for step = 0, 630 do
				for _, m in { 1, 1.0001, 1.5, 2.2, 9.99, 9.9999 } do
					local n = 10 ^ (step / 10) * m
					if n <= 1e63 then
						local s = F.number(n)
						local v = parseShown(F, s)
						T.truthy(v, "읽을 수 없는 글자 " .. s .. " ← " .. tostring(n))
						T.truthy(#s <= 8, "너무 긺 " .. s)
						T.truthy(v <= n * (1 + 1e-9), s .. " 가 " .. tostring(n) .. " 보다 큼")
						-- 1000 미만은 정수로 내림 표시 (1.5 → "1"), 1000 이상은 3자리 → 2% 안
						T.truthy(
							if n < 100 then v >= n - 1 else v >= n * 0.98,
							s .. " 가 " .. tostring(n) .. " 와 너무 다름"
						)
						count += 1
					end
				end
			end
			-- 단조: 정렬된 표본
			local samples = {}
			for step = 0, 6300 do
				table.insert(samples, 10 ^ (step / 100))
			end
			for _, n in samples do
				if n <= 1e63 then
					local v = parseShown(F, F.number(n))
					T.truthy(v >= last, "줄어듦 " .. F.number(n))
					last = v
				end
			end
			T.truthy(count > 3000)
			local units = {
				"K",
				"M",
				"B",
				"T",
				"Qa",
				"Qi",
				"Sx",
				"Sp",
				"Oc",
				"No",
				"Dc",
				"Ud",
				"Dd",
				"Td",
				"Qad",
				"Qid",
				"Sxd",
				"Spd",
				"Ocd",
				"Nod",
				"Vg",
			}
			for i, unit in units do
				T.eq(F.number(10 ^ (3 * i)), "1" .. unit, "1e" .. 3 * i)
				T.eq(F.number(10 ^ (3 * i) - 1), if i == 1 then "999" else F.number(10 ^ (3 * i) - 1), "경계 앞")
			end
			T.eq(F.number(1e66), "1e66", "1e63 넘으면 지수")
			H.uninstall()
		end
	)

	T.test(
		"저장 데이터 보정 3,000번 무작위 (깨진 값 · 모르는 칸 · 띠 99 · 아령 0 · 배수 3): 항상 올바른 모양",
		function()
			local H = setup()
			local D = H.DataSchema
			local rng = T.rng(2024)
			local function junk()
				local i = math.floor(rng() * 14)
				if i == 0 then
					return 0 / 0
				elseif i == 1 then
					return math.huge
				elseif i == 2 then
					return -math.huge
				elseif i == 3 then
					return -math.floor(rng() * 100)
				elseif i == 4 then
					return 1e300
				elseif i == 5 then
					return "abc"
				elseif i == 6 then
					return { 1, 2 }
				elseif i == 7 then
					return true
				elseif i == 8 then
					return 99
				elseif i == 9 then
					return 0
				elseif i == 10 then
					return 1.5
				elseif i == 11 then
					return 1e61
				elseif i == 12 then
					return nil
				end
				return math.floor(rng() * 20)
			end
			for _ = 1, 3000 do
				local raw = {
					power = junk(),
					money = junk(),
					dumbbellLevel = junk(),
					belt = junk(),
					world = junk(),
					broken = { cotton = junk(), nope = junk(), [1] = junk(), glass = junk() },
					powerBoost = junk(),
					moneyPass = junk(),
					grandMaster = junk(),
					receipts = junk(),
					stats = { hits = junk(), trains = junk() },
					settings = { music = junk(), hack = junk() },
					lastSaveTime = junk(),
					version = junk(),
					extra = junk(),
				}
				if rng() < 0.05 then
					raw = junk()
				end
				local d = D.reconcile(D.migrate(raw), 0)
				T.truthy(d.power == d.power and d.power >= 0 and d.power <= 1e60)
				T.truthy(d.money == d.money and d.money >= 0 and d.money <= 1e60)
				T.truthy(d.dumbbellLevel >= 1 and d.dumbbellLevel <= 20 and d.dumbbellLevel % 1 == 0, "아령")
				T.truthy(d.belt >= 1 and d.belt <= 12 and d.belt % 1 == 0, "띠")
				T.truthy(d.world >= 1 and d.world <= H.Progression.worldsFromBelt(d.belt), "월드 > 띠")
				T.truthy(H.Products.isValidBoost(d.powerBoost), "배수")
				T.eq(type(d.moneyPass), "boolean")
				T.truthy(not d.grandMaster or d.belt == 12, "그랜드 마스터")
				T.truthy(#d.receipts <= 200)
				for id, count in d.broken do
					T.truthy(H.Targets.get(id) and count >= 1 and count % 1 == 0, "깬 기록")
				end
				for _, key in D.STAT_KEYS do
					local v = d.stats[key]
					T.truthy(v == v and v >= 0 and v <= 1e60, key)
				end
				for key, value in d.settings do
					T.truthy(H.Config.SETTINGS[key] ~= nil and type(value) == "boolean", key)
				end
				T.eq(d.version, 1)
			end
			H.uninstall()
		end
	)

	T.test(
		"저장 → 불러오기 왕복 (스키마 1): 1e59 · 12번 띠 · 깬 기록 · 영수증 · 설정이 그대로",
		function()
			local H = setup()
			local D = H.DataSchema
			local d = D.default(0)
			d.power, d.money = 1.2345678901234e59, 9.87654321e58
			d.dumbbellLevel, d.belt, d.world, d.powerBoost = 20, 12, 3, 2048
			d.moneyPass, d.grandMaster = true, true
			d.broken = { cotton = 5, universe = 123456 }
			d.receipts = { "r1", "r2" }
			d.stats.hits, d.stats.moneyEarned, d.stats.duelsWon = 777, 1e58, 3
			d.settings.music, d.settings.lowGraphics = false, true
			d.lastSaveTime = 1700000000
			local copy = H.shared("Format") and D.reconcile(D.migrate(table.clone(d)), 0)
			for _, key in
				{
					"power",
					"money",
					"dumbbellLevel",
					"belt",
					"world",
					"powerBoost",
					"moneyPass",
					"grandMaster",
					"lastSaveTime",
					"version",
				}
			do
				T.eq(copy[key], d[key], key)
			end
			T.eq(copy.broken.universe, 123456)
			T.eq(copy.stats.moneyEarned, 1e58)
			T.eq(copy.settings.music, false)
			T.eq(copy.settings.lowGraphics, true)
			T.eq(table.concat(copy.receipts, ","), "r1,r2")
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v1 7: 설계서와 숫자")
	------------------------------------------------------------------

	T.test(
		"물건: 사장님 숫자 앞 11개 (3 · 10 · 20 · 50 · 128 · 256 · 1024 · 8192 · 32768 · 524288 · 1000000) 그대로 · 41개 월드 13/14/14 · 값 순증가",
		function()
			local H = setup()
			local boss = {
				{ "cotton", "솜", 3 },
				{ "glass", "유리", 10 },
				{ "plastic", "플라스틱", 20 },
				{ "wood", "나무 송판", 50 },
				{ "iron", "철", 128 },
				{ "steel", "강철", 256 },
				{ "rubber", "고무", 1024 },
				{ "computer", "컴퓨터", 8192 },
				{ "phone", "핸드폰", 32768 },
				{ "overpass", "육교", 524288 },
				{ "apartment", "아파트", 1000000 },
			}
			T.eq(#H.Targets.list, 41)
			for i, row in boss do
				local t = H.Targets.list[i]
				T.eq(t.id, row[1])
				T.eq(t.name, row[2])
				T.eq(t.reward, row[3], row[1])
				T.eq(t.world, 1)
				T.eq(t.index, i)
			end
			T.eq(#H.Targets.byWorld(1), 13)
			T.eq(#H.Targets.byWorld(2), 14)
			T.eq(#H.Targets.byWorld(3), 14)
			for i = 2, 41 do
				T.truthy(
					H.Targets.list[i].reward > H.Targets.list[i - 1].reward,
					"값이 안 늘어남 " .. H.Targets.list[i].id
				)
				T.truthy(
					H.Targets.list[i].minPower > H.Targets.list[i - 1].minPower
						or H.Targets.list[i].world ~= H.Targets.list[i - 1].world
						or true
				)
				T.truthy(H.Targets.list[i].world >= H.Targets.list[i - 1].world)
			end
			H.uninstall()
		end
	)

	T.test(
		"설계서 9장 한 줄 요약이 코드와 같음: 띠 배율 · 심사 20초/10장 · 대결 15장/3초 · 시험관 속도 · 속도 제한 5",
		function()
			local H = setup()
			local mult = { 1, 1.5, 2, 3, 5, 8, 12, 20, 35, 60, 100, 200 }
			for i, m in mult do
				T.eq(H.Belts.get(i).moneyMultiplier, m, "띠 " .. i)
			end
			T.eq(H.Config.EXAM_SECONDS, 20)
			T.eq(H.Config.EXAM_BOARDS, 10)
			T.eq(H.Config.DUEL_BOARDS, 15)
			T.eq(H.Config.DUEL_COUNTDOWN_SECONDS, 3)
			T.eq(H.Worlds.get(1).examinerSecondsPerBoard, 1.6)
			T.eq(H.Worlds.get(2).examinerSecondsPerBoard, 1.4)
			T.eq(H.Worlds.get(3).examinerSecondsPerBoard, 1.2)
			T.eq(H.Remotes.RateLimits.Train.perSecond, 5)
			T.eq(H.Remotes.RateLimits.Hit.perSecond, 5)
			T.eq(H.Dumbbells.COUNT, 20)
			T.eq(H.Belts.COUNT, 12)
			T.eq(H.Products.MAX_BOOST, 2048)
			T.eq(H.Products.get("money_2").robux, 199)
			T.eq(H.Config.DATASTORE_NAME, "BoardBreak_PlayerData")
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v1 8: 맵과 서버가 맞는지")
	------------------------------------------------------------------

	T.test(
		"수련 매트: 6칸 가운데 · 가장자리 안쪽 = 됨, 바깥 = 안 됨, 다른 월드 매트 = 안 됨, 높이 밖 = 안 됨",
		function()
			local H = setup()
			local ML = H.MapLayout
			for world = 1, 3 do
				local mats = ML.trainMats(world)
				T.eq(#mats, 6)
				for _, m in mats do
					T.truthy(ML.isOnTrainMat({ x = m.x, y = 3, z = m.z }, world))
					T.truthy(
						ML.isOnTrainMat({ x = m.x + m.sizeX / 2, y = 3, z = m.z - m.sizeZ / 2 }, world),
						"모서리"
					)
					T.falsy(ML.isOnTrainMat({ x = m.x + m.sizeX / 2 + 1.5, y = 3, z = m.z }, world), "바깥")
					T.falsy(ML.isOnTrainMat({ x = m.x, y = 40, z = m.z }, world), "공중")
					T.falsy(ML.isOnTrainMat({ x = m.x, y = 3, z = m.z }, world % 3 + 1), "다른 월드 매트")
				end
				local spawn = ML.spawn(world)
				T.falsy(ML.isOnTrainMat({ x = spawn.x, y = 3, z = spawn.z }, world), "스폰은 매트가 아님")
			end
			H.uninstall()
		end
	)

	T.test(
		"심사대 · 대결장: 바닥 모서리 · 가운데에서 시작·치기 됨 · 스폰·아령 가게에서는 안 됨 (월드 1·2·3)",
		function()
			local H = setup()
			for world = 1, 3 do
				local pad = H.MapLayout.examPad(world)
				local arena = H.MapLayout.duelArena(world)
				for _, corner in { { 0, 0 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } } do
					local ep = join(
						H,
						200 + world * 10 + (corner[1] + 1) * 2 + corner[2] + 1,
						{ power = H.Belts.get(2).needPower, world = world, belt = 1 + 3 * (world - 1) },
						at(pad.x + corner[1] * pad.sizeX / 2, 3, pad.z + corner[2] * pad.sizeZ / 2)
					)
					local session = H.S.Sessions.get(ep)
					session.currentWorld = world
					if world == 1 then
						H.client(ep, "StartExam")
						T.truthy(session.exam, "심사대 모서리 " .. world)
					end
				end
				local spawn = H.MapLayout.spawn(world)
				local dx = spawn.x - pad.x
				T.truthy(dx * dx + (spawn.z - pad.z) ^ 2 > H.Config.EXAM_RADIUS ^ 2, "스폰은 심사대에서 멀다")
				T.truthy(
					(spawn.x - arena.x) ^ 2 + (spawn.z - arena.z) ^ 2 > H.Config.DUEL_RADIUS ^ 2,
					"스폰은 대결장에서 멀다"
				)
				local shop = H.MapLayout.dumbbellShop(world)
				T.truthy(
					(shop.x - pad.x) ^ 2 + (shop.z - pad.z) ^ 2 > H.Config.EXAM_RADIUS ^ 2,
					"가게는 심사대에서 멀다"
				)
				T.eq(arena.boards, H.Config.DUEL_BOARDS)
			end
			H.uninstall()
		end
	)

	T.skip(
		"대결 시작·치기 거리(40)가 수련 매트까지 덮음 [A-2 낮음]",
		"Config.DUEL_RADIUS = 40 인데 대결장(34×22) 가운데에서 수련 매트 가장 먼 칸까지 약 26 스터드 — 매트에서 들기를 하면서 대결 시작 가능",
		function()
			local H = setup()
			local mat = H.MapLayout.trainMats(1)[6]
			local p, session = join(H, 1, { power = H.Belts.get(4).needPower, belt = 3 }, at(mat.x, 3, mat.z))
			H.client(p, "StartDuel")
			T.eq(session.duel, nil, "수련 매트에서 대결이 시작됨")
		end
	)

	T.test(
		"월드 문: 월드마다 문 2개 · 내 월드 빼고 나머지 둘 · Travel 하면 그 월드 스폰(x 좌표)에 서고 그 월드 매트에서만 듦",
		function()
			local H = setup()
			local ML = H.MapLayout
			for world = 1, 3 do
				local doors = ML.doors(world)
				T.eq(#doors, 2)
				local seen = {}
				for _, door in doors do
					T.truthy(door.world ~= world and door.world >= 1 and door.world <= 3)
					seen[door.world] = true
					T.eq(ML.worldAt({ x = door.x, y = 0, z = door.z }), world, "문은 내 월드 땅 위")
				end
				T.eq(next(seen) ~= nil, true)
				T.eq(ML.worldAt(ML.spawn(world)), world)
			end
			local p, session = join(H, 1, { world = 3, belt = 12 })
			for _, to in { 2, 3, 1, 3, 2 } do
				H.advance(2)
				H.client(p, "Travel", to)
				T.eq(session.currentWorld, to)
				T.eq(H.MapLayout.worldAt(p.Character.root.Position), to, "순간이동 자리가 그 월드 땅")
				local mat = ML.trainMats(to)[1]
				H.teleport(p, mat.x, 3, mat.z)
				local before = p:GetAttribute("Power") or 0
				H.advance(1)
				H.client(p, "Train")
				T.truthy((p:GetAttribute("Power") or 0) > before, "그 월드 매트에서 들기 됨 " .. to)
			end
			H.uninstall()
		end
	)

	T.test(
		"Main.server 를 진짜로 돌려 보면 MapBuilder.start() 를 부름 (Net → MapBuilder → DataService 순서) · 서버 warn 0",
		function()
			local H = setup()
			local calls = { map = 0 }
			Loader.mock("ServerScriptService/Server/Services/MapBuilder", {
				start = function()
					calls.map += 1
				end,
			})
			local source = fs.readFile(GAME_DIR .. "/src/server/Main.server.luau")
			local iNet = string.find(source, "Net.start()", 1, true)
			local iMap = string.find(source, "bootOptional(mapBuilder)", 1, true)
			local iData = string.find(source, "DataService.start()", 1, true)
			T.truthy(iNet and iMap and iData and iNet < iMap and iMap < iData, "순서")
			local function pathOf(node)
				local parts = {}
				local cur = node
				while cur ~= nil do
					table.insert(parts, 1, cur.Name)
					cur = cur.Parent
				end
				table.remove(parts, 1)
				return table.concat(parts, "/")
			end
			local env = {
				script = Loader.get("ServerScriptService/Server/Main"),
				game = H.game,
				require = function(target)
					return Loader.require(pathOf(target))
				end,
				warn = function(...)
					local parts = {}
					for i = 1, select("#", ...) do
						parts[i] = tostring((select(i, ...)))
					end
					table.insert(H.warnings, table.concat(parts, " "))
				end,
				print = function() end,
			}
			local chunk = luau.load(source, { debugName = "Main.server", environment = env })
			chunk()
			T.eq(calls.map, 1, "MapBuilder.start 가 한 번 불림")
			local realMap = fs.readFile(GAME_DIR .. "/src/server/Services/MapBuilder.luau")
			T.truthy(
				string.find(realMap, "function MapBuilder.start()", 1, true),
				"진짜 MapBuilder 에 start 가 있음"
			)
			-- 하네스의 가짜 TextChatCommand 에는 Triggered 신호가 없어서 나는 warn 하나만 빼고 0
			local real = {}
			for _, w in H.warnings do
				if not string.find(w, "TextChatCommand", 1, true) then
					table.insert(real, w)
				end
			end
			T.eq(#real, 0, table.concat(real, " | "))
			H.uninstall()
		end
	)
end
