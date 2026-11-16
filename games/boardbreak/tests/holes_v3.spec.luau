--!nocheck
--[[
	holes_v3 — 주임의 "구멍 찾기" (3판 검수 C 시리즈 — 결정 13~16번: 커지는 몸·월드 · 걷기 2배 · 포탈 바로 이동 · 띠 22개).
	진짜 서버 코드 + ServerHarness. src 는 고치지 않음 — 버그는 T.skip(이유, 본문) 으로 남김 (본문은 그대로 돌아서 실패 내용이 출력에 찍힘.
	고쳐지면 "FIXED?" 가 떠서 T.test 로 바꾸면 됨). 번호(C-n)는 docs/TEST_REPORT.md "3판 검수 (C 시리즈)" 와 같음.
	  A 크기·속도: 힘이 정하는 값과 다른 몸·걷기·점프가 되는 길 (원격 · 개발 명령 · 재접속 · 리스폰 · 월드 이동 · 지급 · 불러오기)
	  B 닿는 거리: 월드 배율 · 몸 여유 때문에 생긴 구멍 (남의 월드 · 높이 · NaN) 과 닿아야 하는데 안 닿는 곳
	  C 포탈·Travel: 연타 · 잠긴 월드 · 대결 중 · 쓰레기 인자 · 리스폰 · 도착 자리가 문 안인가
	  D 띠 22개: 순서 건너뛰기 · 월드 열림 · 옛 저장 · 이상한 띠 값 · 돈 배율
	  E 경제: 아령 값 순서 · 사는 속도 한도 · sim 을 흔들어도 목표 안 (지름길 · 걷기 없이 · 손가락 최대 속도)
	  F 데이터 하나에서 읽는지 (12띠 · 4개씩 · 2000 간격 · 걷기 16 같은 옛 가정 찾기)
]]
return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local SimPlayer = require("./SimPlayer")
	local fs = require("@lune/fs")

	local GAME_DIR = if fs.isFile("games/boardbreak/default.project.json") then "games/boardbreak" else "."

	local function setup()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local S = {
			Data = H.server("Services/DataService"),
			Size = H.server("Services/SizeService"),
			Train = H.server("Services/TrainService"),
			Break = H.server("Services/BreakService"),
			Shop = H.server("Services/ShopService"),
			World = H.server("Services/WorldService"),
			Exam = H.server("Services/ExamService"),
			Product = H.server("Services/ProductService"),
			Dev = H.server("Services/DevCommands"),
			Life = H.server("Services/PlayerLifecycle"),
			Wallet = H.server("Services/Wallet"),
			Sessions = H.server("Sessions"),
		}
		S.Data.start()
		S.Size.start()
		S.Train.start()
		S.Break.start()
		S.Shop.start()
		S.World.start()
		S.Exam.start()
		S.Life.start()
		H.S = S
		H.Sizes = H.shared("Data/Sizes")
		H.Targets = H.shared("Data/Targets")
		H.Belts = H.shared("Data/Belts")
		H.Worlds = H.shared("Data/Worlds")
		H.Dumbbells = H.shared("Data/Dumbbells")
		H.Products = H.shared("Data/Products")
		H.Config = H.shared("Data/Config")
		H.Remotes = H.shared("Remotes")
		H.Economy = H.shared("Economy")
		H.Progression = H.shared("Progression")
		H.BreakRules = H.shared("BreakRules")
		H.ExamRules = H.shared("ExamRules")
		H.DataSchema = H.server("Logic/DataSchema")
		return H
	end

	-- 로그인 + 캐릭터 (PlayerLifecycle 없이). 몸 크기는 Wallet.sync 로 한 번 맞춤 (접속 때 Attributes.sync 와 같음)
	local function join(H, userId, overrides, spot)
		local p = H.newPlayer(userId)
		local session, data = H.login(p, overrides)
		if spot then
			H.spawn(p, spot[1], spot[2], spot[3])
		else
			H.spawn(p, H.matSpot(session.currentWorld))
		end
		H.S.Wallet.sync(p)
		return p, session, data
	end

	-- 진짜 접속 길 (PlayerLifecycle.onPlayerAdded + DataStore). stored 가 있으면 저장소에 그 데이터를 먼저 넣음.
	-- options.late = true 면 불러온 뒤에 캐릭터가 생김 (보통은 캐릭터가 먼저)
	local function joinReal(H, userId, stored, options)
		if stored ~= nil then
			H.store.data["player_" .. userId] = { data = stored }
		end
		local p = H.newPlayer(userId)
		local late = options and options.late
		if not late then
			H.spawn(p, 0, 3, 0)
		end
		H.run(function()
			H.S.Life.onPlayerAdded(p)
			return true
		end)
		if late then
			H.spawn(p, 0, 3, 0)
		end
		H.advance(0.2)
		local session, data = H.S.Sessions.getLoaded(p)
		return p, session, data
	end

	-- 그 월드 물건 추천 힘의 로그 평균 (월드 배율을 정한 "그 월드 평균 힘")
	local function avgPower(H, world)
		local sum, list = 0, H.Targets.byWorld(world)
		for _, t in list do
			sum += math.log10(t.recommendPower)
		end
		return 10 ^ (sum / #list)
	end

	-- 몸 3가지: 작은 몸 (힘 0) · 그 월드에 어울리는 몸 (평균 힘) · 가장 큰 몸 (1e60)
	local KINDS = { "small", "natural", "giant" }
	local function powerOf(H, kind, world)
		if kind == "small" then
			return 0
		elseif kind == "natural" then
			return avgPower(H, world)
		end
		return 1e60
	end

	-- 서버가 정해야 하는 값 (맨 힘 data.power 에서)
	local function expectSize(H, power)
		local scale = H.Sizes.quantize(H.Sizes.playerScale(power))
		local steps = math.floor(H.Sizes.muscle(power) / 0.05 + 1e-9)
		return scale, math.clamp(steps * 0.05, 0, 1)
	end

	-- 서버 상태가 앞뒤가 맞는지 한 번에 검사: 문제가 있으면 글, 없으면 nil
	-- options.looseGrandMaster = true 면 "띠 22 인데 그랜드 마스터가 아님" 은 문제로 안 침 (이상한 저장 값 시험용 — C-2)
	local function problems(H, p, options)
		local session, data = H.S.Sessions.getLoaded(p)
		if not session or not data then
			return "세션 없음"
		end
		local scale, muscle = expectSize(H, data.power)
		if p:GetAttribute("BodyScale") ~= scale then
			return string.format(
				"BodyScale %s ≠ %s (힘 %s)",
				tostring(p:GetAttribute("BodyScale")),
				scale,
				data.power
			)
		end
		if math.abs((p:GetAttribute("Muscle") or -1) - muscle) > 1e-9 then
			return string.format("Muscle %s ≠ %s", tostring(p:GetAttribute("Muscle")), muscle)
		end
		local hum = p.Character and p.Character.humanoid
		if hum then
			if hum.WalkSpeed ~= H.Sizes.walkSpeed(scale) then
				return string.format("WalkSpeed %s ≠ %s", tostring(hum.WalkSpeed), H.Sizes.walkSpeed(scale))
			end
			if hum.JumpHeight ~= H.Sizes.jumpHeight(scale) then
				return string.format("JumpHeight %s ≠ %s", tostring(hum.JumpHeight), H.Sizes.jumpHeight(scale))
			end
			if hum.UseJumpPower ~= false then
				return "UseJumpPower 가 켜짐"
			end
		end
		if p:GetAttribute("Power") ~= data.power then
			return "Power Attribute ≠ data.power"
		end
		if not (data.power == data.power and data.power >= 0 and data.power <= 1e60) then
			return "힘이 범위 밖 " .. tostring(data.power)
		end
		if not (data.money == data.money and data.money >= 0 and data.money <= 1e60) then
			return "돈이 범위 밖 " .. tostring(data.money)
		end
		if data.world ~= H.Progression.worldsFromBelt(data.belt) then
			return string.format(
				"월드 %s ≠ 띠 %s 가 여는 월드 %s",
				data.world,
				data.belt,
				H.Progression.worldsFromBelt(data.belt)
			)
		end
		local loose = options and options.looseGrandMaster
		if
			data.grandMaster and data.belt ~= H.Belts.COUNT
			or (not loose and not data.grandMaster and data.belt == H.Belts.COUNT)
		then
			return string.format("그랜드 마스터 %s 인데 띠 %s", tostring(data.grandMaster), data.belt)
		end
		if session.currentWorld < 1 or session.currentWorld > data.world then
			return string.format("지금 월드 %s 가 열린 월드 %s 밖", session.currentWorld, data.world)
		end
		if p:GetAttribute("CurrentWorld") ~= session.currentWorld then
			return "CurrentWorld Attribute ≠ 세션"
		end
		if p:GetAttribute("Activity") ~= H.S.Sessions.activity(session) then
			return "Activity Attribute ≠ 세션"
		end
		if session.exam and session.duel and not session.exam.finished and not session.duel.finished then
			return "심사와 대결이 동시에"
		end
		if data.dumbbellLevel < 1 or data.dumbbellLevel > #H.Dumbbells.list or data.dumbbellLevel % 1 ~= 0 then
			return "아령 레벨 " .. tostring(data.dumbbellLevel)
		end
		return nil
	end

	-- 진짜 숫자 표·규칙 (서버 없이) — sim 용
	local function pure()
		Loader.clearFakes()
		local function sh(path)
			return Loader.require("ReplicatedStorage/Shared/" .. path)
		end
		return {
			Targets = sh("Data/Targets"),
			Dumbbells = sh("Data/Dumbbells"),
			Belts = sh("Data/Belts"),
			Worlds = sh("Data/Worlds"),
			Config = sh("Data/Config"),
			MapLayout = sh("Data/MapLayout"),
			Economy = sh("Economy"),
			Progression = sh("Progression"),
			ExamRules = sh("ExamRules"),
			Format = sh("Format"),
			Sizes = sh("Data/Sizes"),
		}
	end

	local function mmss(seconds)
		if not seconds then
			return "-"
		end
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end

	------------------------------------------------------------------
	T.suite(
		"holes_v3 A: 크기·속도 — 힘이 정하는 값과 다른 몸 · 걷기 · 점프가 되는 길 (무작위 퍼즈 + 길 하나하나)"
	)
	------------------------------------------------------------------

	-- 가능한 모든 길을 무작위로 섞어 밟고, 한 걸음마다 상태 전체(몸·근육·걷기·점프·월드·띠·활동)가 앞뒤가 맞는지 봄
	local DEV_COMMANDS = {
		"/power 0",
		"/power 1",
		"/power 5",
		"/power 1e9",
		"/power 1e20",
		"/power 3e33",
		"/power 6.14e39",
		"/power 1e60",
		"/power nan",
		"/power -5",
		"/power abc",
		"/power 1e999",
		"/money 1e60",
		"/money 0",
		"/belt 1",
		"/belt 7",
		"/belt 8",
		"/belt 14",
		"/belt 15",
		"/belt 21",
		"/belt 22",
		"/belt 23",
		"/belt 0",
		"/belt 1.5",
		"/world 1",
		"/world 2",
		"/world 3",
		"/world 4",
		"/dumbbell 1",
		"/dumbbell 30",
		"/dumbbell 60",
		"/dumbbell 61",
		"/buy power_2",
		"/buy power_4",
		"/buy power_2048",
		"/buy money_2",
		"/buy nope",
		"/unbuy",
		"/reset",
	}

	T.test(
		"[A-1] 무작위 퍼즈 3판 × 600걸음 (들기 · 치기 · 사기 · Travel · 심사 · 대결 · 개발 명령 · 죽음/리스폰 · 재접속): 걸음마다 BodyScale · Muscle · 걷기 · 점프 = 맨 힘이 정한 값, 월드 = 띠가 여는 월드, 그랜드 마스터 = 띠 22 (warn 0)",
		function()
			local tally = { steps = 0, promotions = 0, moves = 0, powerUps = 0, earned = 0, rejoins = 0, biggest = 1 }
			for _, seed in { 11, 22, 33 } do
				local H = setup()
				local ML = H.MapLayout
				local rng = T.rng(seed)
				local uid = 500 + seed
				local function pick(list)
					return list[1 + math.floor(rng() * #list)]
				end
				local p = joinReal(H, uid, { version = 1, power = 1e5, belt = 3, dumbbellLevel = 5, money = 1e6 })
				local function state()
					return H.S.Sessions.getLoaded(p)
				end
				local function height()
					return 3 * H.S.Size.bodyScale(p)
				end
				local function goTo(x, y, z)
					if p.Character then
						H.teleport(p, x, y + height(), z)
					end
				end
				local ops = {}
				local function op(name, weight, fn)
					for _ = 1, weight do
						table.insert(ops, { name = name, fn = fn })
					end
				end
				op("train", 6, function()
					local session = state()
					local mats = if rng() < 0.5
						then ML.trainMats(session.currentWorld)
						else ML.roadMats(session.currentWorld)
					local m = pick(mats)
					goTo(m.x, m.y, m.z)
					H.client(p, "Train")
				end)
				op("hit", 5, function()
					local session = state()
					local id = pick(ML.targetIds(session.currentWorld))
					local mp = ML.matPoint(id)
					goTo(mp.x, mp.y, mp.z)
					H.client(p, "Hit", id)
				end)
				op("hit-anywhere", 2, function()
					H.client(p, "Hit", pick(H.Targets.list).id)
				end)
				op("buy", 2, function()
					H.client(p, "BuyDumbbell")
				end)
				op("travel", 4, function()
					H.client(p, "Travel", pick({ 1, 2, 3, 3, 2, 0, 4, 1.5, 0 / 0, -1 }))
				end)
				op("exam", 3, function()
					local session = state()
					local pad = ML.examPad(session.currentWorld)
					goTo(pad.x, pad.y, pad.z)
					H.client(p, "StartExam")
					for _ = 1, math.floor(rng() * 14) do
						H.client(p, "Hit", "exam")
						H.advance(0.2)
					end
				end)
				op("duel", 3, function()
					local session = state()
					local arena = ML.duelArena(session.currentWorld)
					goTo(arena.player.x, arena.player.y, arena.player.z)
					H.client(p, "StartDuel")
					H.advance(3.1)
					for _ = 1, math.floor(rng() * 20) do
						H.client(p, "Hit", "duel")
						H.advance(0.2)
					end
				end)
				op("dev", 8, function()
					H.S.Dev.handle(p, pick(DEV_COMMANDS))
				end)
				op("die+respawn", 2, function()
					if p.Character then
						p.Character.humanoid.Health = 0
					end
					H.spawn(p, 0, 3, 0)
				end)
				op("respawn", 2, function()
					H.spawn(p, rng() * 100 - 50, 3, rng() * 100 - 50)
				end)
				op("rejoin", 1, function()
					H.leave(p)
					p = joinReal(H, uid, nil, { late = rng() < 0.5 })
				end)
				op("wait", 3, function()
					H.advance(rng() * 5)
				end)

				for step = 1, 600 do
					local o = pick(ops)
					local s0, d0 = state()
					local before =
						{ belt = d0.belt, world = s0.currentWorld, power = d0.power, money = d0.money, p = p }
					o.fn()
					H.advance(0.05 + rng() * 0.3)
					local s1, d1 = state()
					tally.steps += 1
					if d1 and before.p == p then
						tally.promotions += if d1.belt > before.belt then 1 else 0
						tally.moves += if s1.currentWorld ~= before.world then 1 else 0
						tally.powerUps += if d1.power > before.power then 1 else 0
						tally.earned += if d1.money > before.money then 1 else 0
						tally.biggest = math.max(tally.biggest, p:GetAttribute("BodyScale") or 1)
					elseif before.p ~= p then
						tally.rejoins += 1
					end
					local bad = problems(H, p)
					T.truthy(bad == nil, string.format("판 %d 걸음 %d (%s): %s", seed, step, o.name, tostring(bad)))
					-- 몸이 서 있는 월드 땅이 지금 월드와 같음 (옮기거나 리스폰한 뒤)
					local session = state()
					if p.Character and (o.name == "travel" or o.name == "die+respawn" or o.name == "respawn") then
						T.eq(
							ML.worldAt(p.Character.root.Position),
							session.currentWorld,
							string.format("판 %d 걸음 %d (%s) 서 있는 월드", seed, step, o.name)
						)
					end
				end
				T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
				H.uninstall()
			end
			print(
				string.format(
					"  (퍼즈 %d걸음: 띠 올라감 %d · 월드 옮김 %d · 힘 오름 %d · 돈 늘어남 %d · 다시 접속 %d · 가장 큰 몸 %.2f)",
					tally.steps,
					tally.promotions,
					tally.moves,
					tally.powerUps,
					tally.earned,
					tally.rejoins,
					tally.biggest
				)
			)
			-- 퍼즈가 아무것도 안 하고 지나간 게 아님 (모든 길이 실제로 밟힘)
			T.truthy(tally.promotions >= 3 and tally.moves >= 30 and tally.powerUps >= 30, "퍼즈가 너무 조용함")
			T.truthy(tally.earned >= 10 and tally.rejoins >= 5 and tally.biggest > 10, "퍼즈가 너무 조용함 (2)")
		end
	)

	T.test(
		"[A-2] 힘 배수 (2배 … 2048배) 가 몸으로 새지 않음: 같은 맨 힘이면 배수 1 · 2048 이 BodyScale · Muscle · 걷기 · 점프 · 치기 여유 · 스폰 높이 전부 같음. 패스를 하나씩 받는 동안에도 그대로",
		function()
			local H = setup()
			for _, power in { 0, 5, 1e5, 1e15, 1e25, 1e35, 6.14e39, 1e60 } do
				local a, _, da = join(H, 1000, { power = power, belt = 1 })
				local b, _, db = join(H, 1001, { power = power, belt = 1 })
				db.powerBoost = 2048
				H.S.Wallet.sync(b)
				H.S.Dev.handle(b, "/buy power_2048") -- 다시 받아도 그대로
				T.eq(db.powerBoost, 2048)
				for _, key in { "BodyScale", "Muscle" } do
					T.eq(a:GetAttribute(key), b:GetAttribute(key), key .. " @ 힘 " .. power)
				end
				T.eq(a.Character.humanoid.WalkSpeed, b.Character.humanoid.WalkSpeed, "걷기 @ 힘 " .. power)
				T.eq(a.Character.humanoid.JumpHeight, b.Character.humanoid.JumpHeight, "점프 @ 힘 " .. power)
				T.eq(H.S.Size.bodyExtra(a), H.S.Size.bodyExtra(b), "몸 여유")
				T.eq(H.S.Break.slackFor(a, "cotton"), H.S.Break.slackFor(b, "cotton"), "치기 여유")
				T.eq(H.S.World.spawnLift(a, 3), H.S.World.spawnLift(b, 3), "스폰 높이")
				T.eq(da.power, db.power, "맨 힘은 배수에 안 부풀음")
			end
			-- 패스를 순서대로 하나씩 받는 동안 (power_2 … power_2048) 몸이 한 번도 안 바뀜
			local p, _, data = join(H, 1002, { power = 3e20 })
			local before = p:GetAttribute("BodyScale")
			local walk = p.Character.humanoid.WalkSpeed
			local seen = 0
			for _, boost in H.Products.powerBoosts do
				T.truthy(H.S.Product.grant(p, boost.key, "test"), boost.key)
				seen += 1
				T.eq(data.powerBoost, boost.value, boost.key .. " 배수")
				T.eq(p:GetAttribute("BodyScale"), before, boost.key .. " 뒤 BodyScale")
				T.eq(p.Character.humanoid.WalkSpeed, walk, boost.key .. " 뒤 걷기")
				T.eq(data.power, 3e20, boost.key .. " 뒤 맨 힘")
			end
			T.eq(seen, 11, "힘 배수 패스 11개")
			-- 치는 힘만 배수가 곱해짐 (들 때 얻는 힘도): 같은 매트에서 한 번 들면 아령 × 배수만큼 힘이 오름 — 그래도 몸은 맨 힘으로만
			local q, _, qd = join(H, 1003, { power = 1e5 })
			for _, boost in H.Products.powerBoosts do
				H.S.Product.grant(q, boost.key, "test")
			end
			T.eq(qd.powerBoost, 2048)
			local mp = H.MapLayout.matPoint("cotton")
			H.teleport(q, mp.x, mp.y + 3 * H.S.Size.bodyScale(q), mp.z)
			local gain = H.S.Train.train(q)
			T.eq(gain, H.Economy.trainGain(qd.dumbbellLevel, 1) * 2048, "들기 한 번 = 아령 × 배수")
			T.eq(qd.power, 1e5 + gain)
			local expectedScale = H.S.Size.scaleFor(qd.power)
			T.eq(q:GetAttribute("BodyScale"), expectedScale, "몸은 올라간 맨 힘만큼만")
			T.truthy(H.S.Size.scaleFor(qd.power * 2048) > expectedScale, "(배수를 곱했다면 더 컸을 것)")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[A-3] 이상한 저장 힘 13가지 (NaN · ±무한 · 음수 · 1e308 · 1e61 · 글자 · 표 · true · 아주 작은 수 · 우주 추천 힘 딱): 진짜 불러오기 → 몸 1 ~ MAX · 근육 0 ~ 1 · 걷기 32 × 몸 · 힘 0 ~ 1e60 · 캐릭터가 먼저든 나중이든 · 다시 접속해도 같음",
		function()
			local H = setup()
			local junk = {
				0 / 0,
				math.huge,
				-math.huge,
				-5,
				1e308,
				1e61,
				"1e9",
				{ 1e9 },
				true,
				1e-300,
				0,
				6.14e39, -- 우주 추천 힘 안쪽
				1e60,
			}
			for i, v in junk do
				for _, late in { false, true } do
					local uid = 2000 + i * 2 + (if late then 1 else 0)
					local p, _, data = joinReal(
						H,
						uid,
						{ version = 1, power = v, belt = 2, money = v },
						{ late = late }
					)
					T.truthy(data ~= nil, "불러옴 " .. tostring(v))
					local bad = problems(H, p)
					T.truthy(
						bad == nil,
						"저장 힘 "
							.. tostring(v)
							.. (if late then " (캐릭터 나중)" else "")
							.. ": "
							.. tostring(bad)
					)
					local scale = p:GetAttribute("BodyScale")
					T.truthy(scale >= 1 and scale <= H.Sizes.MAX_SCALE, "몸 범위 " .. tostring(scale))
					local w = p.Character.humanoid.WalkSpeed
					T.truthy(w == w and w >= 32 and w <= 32 * H.Sizes.MAX_SCALE + 1e-9, "걷기 " .. tostring(w))
					-- 나갔다 다시 들어와도 같음 (저장 → 불러오기)
					local power = data.power
					H.leave(p)
					local q, _, again = joinReal(H, uid, nil)
					T.eq(again.power, power, "다시 접속한 힘")
					T.truthy(problems(H, q) == nil, "다시 접속 " .. tostring(problems(H, q)))
					T.eq(q:GetAttribute("BodyScale"), scale, "다시 접속한 몸")
				end
			end
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[A-4] 길 하나하나 뒤 바로 확인 — 새 몸(리스폰)의 기본 걷기 16 · 점프 50 이 남지 않음: 불러오기 전에 태어난 캐릭터 · 불러온 뒤 태어난 캐릭터 · 죽고 다시 태어남 · /reset · 월드 이동 · 지급",
		function()
			local H = setup()
			local p, session, data = joinReal(H, 3001, { version = 1, power = 1e30, belt = 8, dumbbellLevel = 30 })
			local scale = H.S.Size.scaleFor(1e30)
			T.truthy(scale > 5, "큰 몸 " .. scale)
			-- 새 캐릭터는 기본값 (16 · 점프 파워) 으로 생기지만 CharacterAdded 에서 바로 맞춰져야 함
			for i = 1, 20 do
				if p.Character then
					p.Character.humanoid.Health = 0
				end
				H.spawn(p, 0, 3, 0)
				T.eq(p.Character.humanoid.WalkSpeed, 32 * scale, "리스폰 " .. i .. " 바로 걷기")
				T.eq(p.Character.humanoid.JumpHeight, 7.2 * scale, "리스폰 " .. i .. " 바로 점프")
				T.eq(p.Character.humanoid.UseJumpPower, false)
			end
			-- 다른 CharacterAdded 처리가 한 프레임 뒤에 덮어써도 (미뤄서 한 번 더) 바로잡음
			p.Character.humanoid.WalkSpeed = 16
			H.advance(0.1)
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			-- /reset → 처음 몸 (1 · 근육 0 · 걷기 32 · 점프 7.2), 다시 태어나도 같음
			H.S.Dev.handle(p, "/reset")
			T.eq(p:GetAttribute("BodyScale"), 1)
			T.eq(p:GetAttribute("Muscle"), 0)
			T.eq(p.Character.humanoid.WalkSpeed, 32)
			T.eq(p.Character.humanoid.JumpHeight, 7.2)
			H.spawn(p, 0, 3, 0)
			T.eq(p.Character.humanoid.WalkSpeed, 32)
			T.eq(data.power, 0)
			T.eq(session.currentWorld, 1)
			-- 월드 이동 · 지급 뒤에도
			H.S.Dev.handle(p, "/power 1e25")
			H.S.Dev.handle(p, "/world 3")
			H.advance(2.5)
			H.client(p, "Travel", 1)
			H.client(p, "Travel", 2)
			H.S.Product.grant(p, "power_2")
			H.S.Product.grant(p, "money_2")
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			T.eq(p.Character.humanoid.WalkSpeed, 32 * H.S.Size.scaleFor(1e25))
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[A-5] 개발 명령 찌꺼기: 스튜디오가 아니면 (실서버) 개발 명령 8개가 전부 무시됨 · 힘·돈·띠·월드·아령·배수 그대로 / DEV_USER_IDS 가 있으면 그 사람만 / Remote 로 개발 명령이 올 길 없음",
		function()
			local H = setup()
			local Config = H.Config
			T.eq(#Config.DEV_USER_IDS, 0, "배포 설정: 개발자 userId 없음 (스튜디오에서만 켜짐)")
			local p, _, data = join(H, 1, { power = 77, money = 88, belt = 3, dumbbellLevel = 4 })
			H.RunService.studio = false -- 실서버
			for _, cmd in
				{
					"/power 1e60",
					"/money 1e60",
					"/belt 22",
					"/world 3",
					"/dumbbell 60",
					"/buy power_2048",
					"/buy money_2",
					"/unbuy",
					"/reset",
					"/POWER 1e60",
					"/power 1e60 ",
				}
			do
				T.falsy(H.S.Dev.handle(p, cmd), "실서버에서 " .. cmd)
			end
			T.eq(data.power, 77)
			T.eq(data.money, 88)
			T.eq(data.belt, 3)
			T.eq(data.dumbbellLevel, 4)
			T.eq(data.powerBoost, 1)
			T.eq(data.moneyPass, false)
			-- 채팅 글은 Remote 가 아님: 클라가 보낼 수 있는 Remote 이름에 개발 명령이 없음
			for name in H.Remotes.ToServer do
				local lower = string.lower(name)
				for _, bad in { "dev", "cheat", "admin", "debug", "command", "cmd", "give", "set" } do
					if bad ~= "set" then
						T.falsy(string.find(lower, bad, 1, true), "Remote " .. name .. " 에 " .. bad)
					end
				end
			end
			-- 스튜디오이면 누구나, DEV_USER_IDS 에 넣으면 그 사람만
			H.RunService.studio = true
			T.truthy(H.S.Dev.handle(p, "/power 5"))
			table.insert(Config.DEV_USER_IDS, 424242)
			T.falsy(H.S.Dev.handle(p, "/power 1e60"), "목록에 없는 사람은 스튜디오여도 안 됨")
			T.eq(data.power, 5)
			table.insert(Config.DEV_USER_IDS, p.UserId)
			T.truthy(H.S.Dev.handle(p, "/power 6"), "목록에 있는 사람")
			table.clear(Config.DEV_USER_IDS)
			H.uninstall()
		end
	)

	T.test(
		"[A-6] 걷기·점프를 쓰는 코드는 SizeService 하나뿐 (서버 · 클라 · 공유 전부 훑음) — 다른 곳이 WalkSpeed · JumpHeight · JumpPower 에 값을 쓰면 몸 크기와 어긋남",
		function()
			local offenders = {}
			local function scan(dir)
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						scan(path)
					elseif string.sub(name, -5) == ".luau" and name ~= "SizeService.luau" then
						local source = fs.readFile(path)
						for line in string.gmatch(source, "[^\n]+") do
							local code = string.gsub(line, "%-%-.*$", "")
							for _, prop in { "WalkSpeed", "JumpHeight", "JumpPower", "UseJumpPower" } do
								if
									string.find(code, "%." .. prop .. "%s*=[^=]")
									or string.find(code, '"' .. prop .. '"%s*[,%]]')
								then
									table.insert(offenders, name .. ": " .. line)
								end
							end
						end
					end
				end
			end
			scan(GAME_DIR .. "/src")
			T.eq(#offenders, 0, table.concat(offenders, " | "))
			-- 걷기·점프 값은 Sizes 가 정함 (SizeService 가 쓰는 식이 Sizes.walkSpeed / jumpHeight)
			local source = fs.readFile(GAME_DIR .. "/src/server/Services/SizeService.luau")
			T.truthy(string.find(source, "Sizes.walkSpeed(scale)", 1, true))
			T.truthy(string.find(source, "Sizes.jumpHeight(scale)", 1, true))
		end
	)

	T.test(
		"[A-7] 시험이 진짜로 잡는지 (망가뜨려 보기): 서버 SizeService.refresh 를 일부러 빼면 · 걷기를 안 맞추면 · 배수를 곱해 몸을 키우면 A-1 의 검사(problems)가 바로 알아챔",
		function()
			local H = setup()
			local p, _, data = joinReal(H, 7001, { version = 1, power = 0 })
			T.truthy(problems(H, p) == nil)
			-- (1) 힘이 바뀌어도 몸이 안 따라옴
			local realRefresh = H.S.Size.refresh
			H.S.Size.refresh = function()
				return 1
			end
			H.S.Wallet.set(p, 1e30, nil)
			T.truthy(problems(H, p) ~= nil, "refresh 를 뺐는데 못 알아챔")
			H.S.Size.refresh = realRefresh
			H.S.Wallet.sync(p)
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			-- (2) 걷기만 안 맞춤
			p.Character.humanoid.WalkSpeed = 16
			T.truthy(problems(H, p) ~= nil, "걷기 16 을 못 알아챔")
			H.S.Wallet.sync(p)
			T.truthy(problems(H, p) == nil)
			-- (3) 배수를 곱해 몸을 키움 (PowerBoost 누수) 흉내
			local realScaleFor = H.S.Size.scaleFor
			data.powerBoost = 2048
			H.S.Size.scaleFor = function(power)
				return realScaleFor(power * data.powerBoost)
			end
			H.S.Wallet.sync(p)
			T.truthy(problems(H, p) ~= nil, "배수가 몸에 새는 것을 못 알아챔")
			H.S.Size.scaleFor = realScaleFor
			H.S.Wallet.sync(p)
			T.truthy(problems(H, p) == nil)
			-- (4) 월드 ≠ 띠, 그랜드 마스터 ≠ 띠 22
			data.world = 2
			T.truthy(problems(H, p) ~= nil, "월드가 띠와 어긋난 것을 못 알아챔")
			data.world = 1
			data.grandMaster = true
			T.truthy(problems(H, p) ~= nil, "그랜드 마스터가 띠와 어긋난 것을 못 알아챔")
			data.grandMaster = false
			T.truthy(problems(H, p) == nil)
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite(
		"holes_v3 B: 닿는 거리 — 월드 배율 · 몸 여유가 만든 구멍 (남의 월드 · 높이 · 이상한 위치)과 닿아야 하는데 안 닿는 곳"
	)
	------------------------------------------------------------------

	-- 이 몸 종류 (작은 몸 · 그 월드 평균 힘 몸 · 가장 큰 몸) 의 플레이어. 열린 월드 3 · 띠 14 (월드 3 을 여는 띠) · 지금 월드 = world
	local function joinKind(H, userId, kind, world, overrides)
		local data = { power = powerOf(H, kind, world), world = 3, belt = 14, money = 0 }
		for k, v in overrides or {} do
			data[k] = v
		end
		local p, session, d = join(H, userId, data, { 0, 3, 0 })
		session.currentWorld = world
		return p, session, d
	end

	-- 몸 종류별 서 있는 뿌리 높이: 바닥에서 3 × 몸 배율 (월드 배율과 상관없이 — 몸은 월드와 함께 안 커짐)
	local function stand(H, p, x, floorY, z)
		H.teleport(p, x, floorY + 3 * H.S.Size.bodyScale(p), z)
	end

	T.test(
		"[B-1] 물건 41개 전부: 작은 몸 · 그 월드에 어울리는 몸 · 가장 큰 몸이 길가 매트 가운데에서 · 길 위 치는 자리(roadPoint)에서 침 (서버 판정). 월드 3 받침대(높이 33)도 포함",
		function()
			local H = setup()
			local ML = H.MapLayout
			local n, uid = 0, 100
			for _, kind in KINDS do
				for w = 1, 3 do
					uid += 1
					local p = joinKind(H, uid, kind, w)
					for _, t in H.Targets.byWorld(w) do
						local mp = ML.matPoint(t.id)
						stand(H, p, mp.x, mp.y, mp.z)
						T.truthy(
							H.S.Break.hit(p, t.id),
							string.format("%s 몸 · 매트 가운데에서 %s (월드 %d)", kind, t.id, w)
						)
						local rp = ML.roadPoint(t.id)
						stand(H, p, rp.x, rp.y, rp.z)
						T.truthy(
							H.S.Break.hit(p, t.id),
							string.format("%s 몸 · 길 위에서 %s (월드 %d)", kind, t.id, w)
						)
						n += 2
					end
				end
			end
			T.eq(n, 41 * 2 * 3)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[B-2] 들기: 도장 매트 6칸 + 길가 매트 41칸, 가운데 · 안쪽 네 모서리에서 작은 몸 · 어울리는 몸 · 가장 큰 몸 모두 들림 (월드 1·2·3) / 매트 가장자리 바로 밖과 매트 위 공중 (매트 위 10 × 월드 배율 넘게) 은 안 들림",
		function()
			local H = setup()
			local ML = H.MapLayout
			local trained, refused, uid = 0, 0, 200
			for _, kind in KINDS do
				for w = 1, 3 do
					uid += 1
					local p, session, data = joinKind(H, uid, kind, w)
					local ws = H.Sizes.worldScale(w)
					local mats = {}
					for _, m in ML.trainMats(w) do
						table.insert(mats, m)
					end
					for _, m in ML.roadMats(w) do
						table.insert(mats, m)
					end
					T.eq(#mats, 6 + #H.Targets.byWorld(w), "월드 " .. w .. " 매트 수")
					for i, m in mats do
						local hx, hz = m.sizeX / 2, m.sizeZ / 2
						for _, off in
							{
								{ 0, 0 },
								{ hx - 0.5, hz - 0.5 },
								{ -hx + 0.5, hz - 0.5 },
								{ hx - 0.5, -hz + 0.5 },
								{ -hx + 0.5, -hz + 0.5 },
							}
						do
							stand(H, p, m.x + off[1], m.y, m.z + off[2])
							-- (큰 힘에서는 1 을 더해도 부동소수로 흡수돼 오른 힘이 0 이라, 들기가 받아들여졌는지는 통계 횟수로 봄)
							local before = data.stats.trains
							H.S.Train.train(p)
							T.eq(
								data.stats.trains,
								before + 1,
								string.format(
									"%s 몸 월드 %d 매트 %d (%s) 들기",
									kind,
									w,
									i,
									tostring(m.targetId)
								)
							)
							trained += 1
						end
						-- 매트 바로 밖 (가장자리 여유 MAT_EDGE 1 을 넘어 +0.6)
						stand(H, p, m.x + hx + ML.MAT_EDGE + 0.6, m.y, m.z)
						T.eq(H.S.Train.train(p), 0, string.format("%s 몸 월드 %d 매트 %d 바로 밖", kind, w, i))
						-- 높이: 서 있는 뿌리 높이보다 10 × 월드 배율 넘게 위
						local bodyExtra = H.S.Size.bodyExtra(p)
						H.teleport(p, m.x, m.y + 3 * H.S.Size.bodyScale(p) + 10 * ws + 1, m.z)
						if ML.isOnTrainMat(p.Character.root.Position, w) or bodyExtra > 0 then
							-- 큰 몸은 몸 여유만큼 내려서 보므로 그만큼 더 올려야 함
							H.teleport(p, m.x, m.y + 3 * H.S.Size.bodyScale(p) + 10 * ws + 1 + bodyExtra, m.z)
						end
						T.eq(H.S.Train.train(p), 0, string.format("%s 몸 월드 %d 매트 %d 공중", kind, w, i))
						refused += 2
					end
					session.currentWorld = w
				end
			end
			print(string.format("  (들기 허용 %d번 · 거절 %d번)", trained, refused))
			T.eq(trained, 3 * 5 * (3 * 6 + 41), "들기 시험 횟수 = 몸 3 × 위치 5 × 매트 59칸")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	-- 몸 배율 s (1 … MAX) 가 되는 맨 힘 (Sizes.playerScale 의 거꾸로)
	local function powerForScale(H, scale)
		local maxScale = H.Sizes.MAX_SCALE
		if scale <= 1 then
			return 0
		end
		local progress = ((scale - 1) / (maxScale - 1)) ^ (1 / H.Sizes.CURVE)
		return 10 ^ (progress * math.log10(1 + H.Sizes.MAX_POWER)) - 1
	end

	T.test(
		"[B-2b] 몸 배율을 1 부터 가장 큰 몸까지 10% 단계로 훑어도 (27곳): 그 월드 길가 매트 가운데에서 그 월드 물건 · 도장 매트 · 심사대 · 대결장이 전부 닿음 · 매트 바로 밖은 안 닿음 (월드 1·2·3 전부)",
		function()
			local H = setup()
			local ML = H.MapLayout
			-- 거꾸로 계산이 맞는지 (몸 → 힘 → 몸)
			for _, s in { 1, 2, 5.5, 11, 13.9 } do
				T.truthy(math.abs(H.Sizes.playerScale(powerForScale(H, s)) - s) < 1e-6, "거꾸로 계산 " .. s)
			end
			local p, session, data = join(H, 900, { power = 0, world = 3, belt = 14 }, { 0, 3, 0 })
			local steps, ratio = 0, 1 + H.Sizes.STEP
			local s = 1
			while s < H.Sizes.MAX_SCALE do
				H.S.Wallet.set(p, powerForScale(H, s), nil)
				local scale = H.S.Size.bodyScale(p)
				T.truthy(scale >= 1 and scale <= s + 1e-9, "몸 " .. scale)
				steps += 1
				for w = 1, 3 do
					session.currentWorld = w
					-- 도장 매트 첫 칸 + 그 월드 첫·가운데·마지막 길가 매트
					local mats = { ML.trainMats(w)[1], ML.trainMats(w)[6] }
					local roads = ML.roadMats(w)
					for _, m in { roads[1], roads[math.ceil(#roads / 2)], roads[#roads] } do
						table.insert(mats, m)
					end
					for i, m in mats do
						stand(H, p, m.x, m.y, m.z)
						local trains = data.stats.trains
						H.S.Train.train(p)
						T.eq(
							data.stats.trains,
							trains + 1,
							string.format("몸 %.3f 월드 %d 매트 %d 들기", scale, w, i)
						)
						if m.targetId then
							T.truthy(
								H.S.Break.hit(p, m.targetId),
								string.format("몸 %.3f 월드 %d %s 치기", scale, w, m.targetId)
							)
						end
					end
					local pad = ML.examPad(w)
					stand(H, p, pad.x, pad.y, pad.z)
					data.belt = 1
					T.truthy(H.S.Exam.startExam(p), string.format("몸 %.3f 월드 %d 심사", scale, w))
					H.S.Exam.cancel(p)
					local arena = ML.duelArena(w)
					stand(H, p, arena.x, arena.y, arena.z)
					data.belt = 6
					T.truthy(H.S.Exam.startDuel(p), string.format("몸 %.3f 월드 %d 대결", scale, w))
					H.S.Exam.cancel(p)
					data.belt = 14
				end
				s *= ratio ^ 5 -- 5단계(약 10%)씩 (끝에서 한 번 더 MAX 로)
			end
			H.S.Wallet.set(p, 1e60, nil)
			T.eq(H.S.Size.bodyScale(p), H.Sizes.MAX_SCALE)
			print(
				string.format(
					"  (몸 배율 %d곳 × 월드 3 · 매트 5칸 · 치기 · 심사 · 대결 전부 통과)",
					steps + 1
				)
			)
			T.truthy(steps >= 25, "훑은 단계 " .. steps)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	-- 심사대·대결장의 서 있을 수 있는 자리들 (가운데 · 안쪽 네 모서리)
	local function padSpots(spot)
		local hx, hz = spot.sizeX / 2 - 0.5, spot.sizeZ / 2 - 0.5
		return {
			{ spot.x, spot.z },
			{ spot.x + hx, spot.z + hz },
			{ spot.x - hx, spot.z + hz },
			{ spot.x + hx, spot.z - hz },
			{ spot.x - hx, spot.z - hz },
		}
	end

	T.test(
		"[B-3] 심사·대결: 심사대 · 대결장 어디에 서든 (가운데 · 네 모서리 · 내 송판 자리 · 시험관 자리) 작은 몸 · 어울리는 몸 · 가장 큰 몸 모두 시작됨 (월드 1·2·3) / 도장·길가 매트 위에서는 안 시작 · 다른 월드 대결장 자리에서도 안 시작",
		function()
			local H = setup()
			local ML = H.MapLayout
			local started, uid = 0, 300
			for _, kind in KINDS do
				for w = 1, 3 do
					uid += 1
					local p, session, data = joinKind(H, uid, kind, w, { belt = 1 })
					-- 띠 1 → 다음 띠 2 = 심사 띠
					for _, xz in padSpots(ML.examPad(w)) do
						stand(H, p, xz[1], ML.examPad(w).y, xz[2])
						T.truthy(
							H.S.Exam.startExam(p),
							string.format("%s 몸 월드 %d 심사대 (%.1f, %.1f)", kind, w, xz[1], xz[2])
						)
						H.S.Exam.cancel(p)
						started += 1
					end
					-- 띠 6 → 다음 띠 7 = 대결 띠 (월드 1 대결 띠. 시험관 월드와 지금 있는 월드는 상관없음)
					data.belt = 6
					local arena = ML.duelArena(w)
					local spots = padSpots(arena)
					table.insert(spots, { arena.player.x, arena.player.z })
					table.insert(spots, { arena.examiner.x, arena.examiner.z })
					for _, xz in spots do
						stand(H, p, xz[1], arena.y, xz[2])
						T.truthy(
							H.S.Exam.startDuel(p),
							string.format("%s 몸 월드 %d 대결장 (%.1f, %.1f)", kind, w, xz[1], xz[2])
						)
						H.S.Exam.cancel(p)
						started += 1
					end
					-- 매트 위에서는 안 됨 (도장 6칸 · 길가 매트 전부)
					local mats = {}
					for _, m in ML.trainMats(w) do
						table.insert(mats, m)
					end
					for _, m in ML.roadMats(w) do
						table.insert(mats, m)
					end
					for i, m in mats do
						stand(H, p, m.x, m.y, m.z)
						data.belt = 6
						T.falsy(
							H.S.Exam.startDuel(p),
							string.format("%s 몸 월드 %d 매트 %d 에서 대결", kind, w, i)
						)
						data.belt = 1
						T.falsy(
							H.S.Exam.startExam(p),
							string.format("%s 몸 월드 %d 매트 %d 에서 심사", kind, w, i)
						)
					end
					T.eq(session.exam, nil)
					T.eq(session.duel, nil)
					-- 다른 월드 대결장 · 심사대 좌표에서는 (지금 월드는 w) 안 됨
					for other = 1, 3 do
						if other ~= w then
							local pad, ar = ML.examPad(other), ML.duelArena(other)
							data.belt = 1
							stand(H, p, pad.x, pad.y, pad.z)
							T.falsy(
								H.S.Exam.startExam(p),
								string.format("월드 %d 에서 월드 %d 심사대 좌표", w, other)
							)
							data.belt = 6
							stand(H, p, ar.x, ar.y, ar.z)
							T.falsy(
								H.S.Exam.startDuel(p),
								string.format("월드 %d 에서 월드 %d 대결장 좌표", w, other)
							)
						end
					end
				end
			end
			print(string.format("  (심사·대결 시작 허용 %d번)", started))
			T.truthy(started >= 9 * 12)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[B-3b] 심사대·대결장 거리 경계 ±0.5 (3가지 몸 × 월드 3개): 수평 반지름 = EXAM_RADIUS(20) · DUEL_RADIUS(24) × 월드 배율, 높이 차 = 같은 반지름 + 3 × (몸 − 1) — 안은 시작됨 · 밖은 거절 · 송판 치기도 같은 경계",
		function()
			local H = setup()
			local ML = H.MapLayout
			local uid = 350
			for _, kind in KINDS do
				for w = 1, 3 do
					uid += 1
					local p, session, data = joinKind(H, uid, kind, w, { belt = 1 })
					local ws = H.Sizes.worldScale(w)
					local extra = 3 * (H.S.Size.bodyScale(p) - 1)
					for _, c in
						{
							{ "심사", ML.examPad(w), H.Config.EXAM_RADIUS * ws, 1, "StartExam" },
							{ "대결", ML.duelArena(w), H.Config.DUEL_RADIUS * ws, 6, "StartDuel" },
						}
					do
						local label, spot, r, belt = c[1], c[2], c[3], c[4]
						local function start()
							data.belt = belt
							return if label == "심사" then H.S.Exam.startExam(p) else H.S.Exam.startDuel(p)
						end
						local function hereBoundary(x, y, z, expectStart, what)
							H.teleport(p, x, y, z)
							local ok = start()
							T.eq(ok, expectStart, string.format("%s 몸 월드 %d %s %s", kind, w, label, what))
							if ok then
								H.S.Exam.cancel(p)
							end
						end
						-- 수평 (심사대·대결장 앞쪽 +z 방향 — 수련 매트와 안 겹침)
						hereBoundary(spot.x, spot.y + 3, spot.z + r - 0.5, true, "수평 안")
						hereBoundary(spot.x, spot.y + 3, spot.z + r + 0.5, false, "수평 밖")
						-- 높이 (같은 반지름 + 몸 여유)
						hereBoundary(spot.x, spot.y + r + extra - 0.5, spot.z, true, "높이 안 (위)")
						hereBoundary(spot.x, spot.y + r + extra + 0.5, spot.z, false, "높이 밖 (위)")
						hereBoundary(spot.x, spot.y - r - extra - 0.5, spot.z, false, "높이 밖 (아래)")
						-- 송판 치기도 같은 경계: 안에서 시작한 뒤 경계 밖에서 치면 안 셈
						hereBoundary(spot.x, spot.y + 3, spot.z, true, "가운데")
						T.eq(session.exam, nil)
						T.eq(session.duel, nil)
					end
					-- 진짜 시작한 뒤 경계 밖에서 치기: 심사
					local pad = ML.examPad(w)
					data.belt = 1
					H.teleport(p, pad.x, pad.y + 3, pad.z)
					T.truthy(H.S.Exam.startExam(p))
					H.teleport(p, pad.x, pad.y + 3, pad.z + H.Config.EXAM_RADIUS * ws + 0.5)
					H.S.Exam.hit(p, "exam")
					T.eq(session.exam.broken, 0, "경계 밖 송판 치기 (심사)")
					H.teleport(p, pad.x, pad.y + 3, pad.z + H.Config.EXAM_RADIUS * ws - 0.5)
					H.S.Exam.hit(p, "exam")
					T.eq(session.exam.broken, if data.power > 0 then 1 else 0, "경계 안 송판 치기 (심사)")
					H.S.Exam.cancel(p)
					session.currentWorld = w
				end
			end
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[B-4] 남의 월드 좌표: 어느 월드 길가 매트에 서든 (3가지 몸) 다른 월드 물건은 못 침 · 다른 월드 도장 매트에서도 못 들음 · 월드마다 닿는 원이 다른 월드 땅(worldRect)과 안 겹침 (가장 큰 몸 여유까지)",
		function()
			local H = setup()
			local ML = H.MapLayout
			local uid = 400
			local tried = 0
			for _, kind in KINDS do
				uid += 1
				local p = joinKind(H, uid, kind, 1)
				for w = 1, 3 do
					for _, m in ML.roadMats(w) do
						stand(H, p, m.x, m.y, m.z)
						for _, t in H.Targets.list do
							if t.world ~= w then
								tried += 1
								T.eq(
									H.S.Break.hit(p, t.id),
									nil,
									string.format(
										"%s 몸 월드 %d 매트에서 월드 %d 물건 %s",
										kind,
										w,
										t.world,
										t.id
									)
								)
							end
						end
					end
				end
			end
			print(string.format("  (남의 월드 치기 %d번 전부 무시)", tried))
			T.truthy(tried >= 3 * 41 * 27)
			-- 닿는 원: 물건 가운데에서 reach + 6 × 월드 배율 + 가장 큰 몸 여유 (3 × (MAX − 1)) 안은 다른 월드 땅 밖
			local maxBody = 3 * (H.Sizes.MAX_SCALE - 1)
			local function distToRect(x, z, r)
				local dx = math.max(r.x0 - x, 0, x - r.x1)
				local dz = math.max(r.z0 - z, 0, z - r.z1)
				return math.sqrt(dx * dx + dz * dz)
			end
			for _, t in H.Targets.list do
				local pos = ML.targetPosition(t.id)
				local far = ML.targetReach(t.id) + 6 * H.Sizes.worldScale(t.world) + maxBody
				for other = 1, 3 do
					if other ~= t.world then
						local d = distToRect(pos.x, pos.z, ML.worldRect(other))
						T.truthy(
							d > far * 3,
							string.format("%s 닿는 원 %.0f 이 월드 %d 땅과 %.0f 거리", t.id, far, other, d)
						)
					end
				end
			end
			for w = 1, 3 do
				local far = math.max(H.Config.EXAM_RADIUS, H.Config.DUEL_RADIUS) * H.Sizes.worldScale(w) + maxBody
				for _, spot in { ML.examPad(w), ML.duelArena(w) } do
					for other = 1, 3 do
						if other ~= w then
							T.truthy(
								distToRect(spot.x, spot.z, ML.worldRect(other)) > far * 3,
								"심사대·대결장 원 월드 " .. w .. " → " .. other
							)
						end
					end
				end
			end
			-- 월드 땅끼리도 멀리 (5,000 스터드 넘게)
			for a = 1, 3 do
				for b = a + 1, 3 do
					local ra, rb = ML.worldRect(a), ML.worldRect(b)
					local gap = rb.x0 - ra.x1
					T.truthy(gap > 5000, string.format("월드 %d ~ %d 땅 사이 %.0f", a, b, gap))
				end
			end
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[B-5] 경계 ±0.5 (물건 41개 × 3가지 몸): 수평 = reach + 6 × 그 월드 배율 + 3 × (몸 − 1) 안은 침 · 0.5 밖은 무시 / 높이도 같은 식 + 20 × 월드 배율 (설계서 7장 그대로)",
		function()
			local H = setup()
			local ML = H.MapLayout
			local uid = 500
			for _, kind in KINDS do
				for w = 1, 3 do
					uid += 1
					local p = joinKind(H, uid, kind, w)
					local scale = H.S.Size.bodyScale(p)
					local ws = H.Sizes.worldScale(w)
					for _, t in H.Targets.byWorld(w) do
						local pos = ML.targetPosition(t.id)
						local r = ML.targetReach(t.id) + 6 * ws + 3 * (scale - 1)
						local label = string.format("%s 몸 %s", kind, t.id)
						H.teleport(p, pos.x + r - 0.5, pos.y, pos.z)
						T.truthy(H.S.Break.hit(p, t.id), label .. " 수평 안")
						H.teleport(p, pos.x + r + 0.5, pos.y, pos.z)
						T.eq(H.S.Break.hit(p, t.id), nil, label .. " 수평 밖")
						H.teleport(p, pos.x, pos.y + r + 20 * ws - 0.5, pos.z)
						T.truthy(H.S.Break.hit(p, t.id), label .. " 높이 안")
						H.teleport(p, pos.x, pos.y + r + 20 * ws + 0.5, pos.z)
						T.eq(H.S.Break.hit(p, t.id), nil, label .. " 높이 밖 (위)")
						H.teleport(p, pos.x, pos.y - r - 20 * ws - 0.5, pos.z)
						T.eq(H.S.Break.hit(p, t.id), nil, label .. " 높이 밖 (아래)")
					end
				end
			end
			H.uninstall()
		end
	)

	-- 클라가 뿌리 좌표를 망가뜨렸다고 가정 (좌표 하나만 이상해도): 치기 · 들기 · 심사 시작 · 대결 시작 · 진짜 자리에서 시작한 심사·대결 송판 치기
	local function weirdPositionCheck(values, what)
		local H = setup()
		local ML = H.MapLayout
		local mp = ML.matPoint("cotton")
		local pad = ML.examPad(1)
		local arena = ML.duelArena(1)
		for axis = 1, 3 do
			for _, bad in values do
				local function at(real)
					local c = { real[1], real[2], real[3] }
					c[axis] = bad
					return c
				end
				local label = string.format("축 %d = %s", axis, tostring(bad))
				local p, session, data = join(
					H,
					600 + axis,
					{ power = 1e60, belt = 1, world = 1 },
					{ mp.x, mp.y + 3, mp.z }
				)
				local c = at({ mp.x, mp.y + 3, mp.z })
				H.teleport(p, c[1], c[2], c[3])
				T.eq(H.S.Break.hit(p, "cotton"), nil, label .. " 치기")
				T.eq(data.stats.hits, 0, label .. " 친 횟수")
				if what.train then
					local trains = data.stats.trains
					H.S.Train.train(p)
					T.eq(data.stats.trains, trains, label .. " 들기")
				end
				if what.exam then
					local e = at({ pad.x, pad.y + 3, pad.z })
					H.teleport(p, e[1], e[2], e[3])
					T.falsy(H.S.Exam.startExam(p), label .. " 심사 시작")
					-- 진짜 자리에서 시작한 심사 · 대결 도중 좌표가 망가짐 → 송판 치기가 안 셈
					H.teleport(p, pad.x, pad.y + 3, pad.z)
					T.truthy(H.S.Exam.startExam(p), "진짜 자리에서는 시작")
					local before = session.exam.broken
					H.teleport(p, e[1], e[2], e[3])
					for _ = 1, 12 do
						H.S.Exam.hit(p, "exam")
					end
					T.eq(session.exam and session.exam.broken or before, before, label .. " 심사 송판 치기")
					H.S.Exam.cancel(p)
					data.belt = 6
					local d = at({ arena.player.x, arena.player.y + 3, arena.player.z })
					H.teleport(p, d[1], d[2], d[3])
					T.falsy(H.S.Exam.startDuel(p), label .. " 대결 시작")
					H.teleport(p, arena.player.x, arena.player.y + 3, arena.player.z)
					T.truthy(H.S.Exam.startDuel(p), "진짜 자리에서는 대결 시작")
					H.advance(3.2)
					H.teleport(p, d[1], d[2], d[3])
					for _ = 1, 20 do
						H.S.Exam.hit(p, "duel")
					end
					T.eq(session.duel and session.duel.mine or 0, 0, label .. " 대결 송판 치기")
					H.S.Exam.cancel(p)
				end
			end
		end
		T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
		H.uninstall()
	end

	T.test(
		"[B-6] 이상한 위치 ±무한 · ±1e308 (축 하나만): 치기 · 들기 · 심사 시작 · 대결 시작 · 심사·대결 송판 치기가 전부 안 됨 · NaN 은 치기만 안 됨 (NaN 의 들기·심사·대결은 B-6b)",
		function()
			weirdPositionCheck({ math.huge, -math.huge, 1e308, -1e308 }, { train = true, exam = true })
			weirdPositionCheck({ 0 / 0 }, {})
		end
	)

	T.test(
		"[B-6b] C-1 고침: 뿌리 좌표가 NaN 이면 (축 하나만) 심사 시작 · 대결 시작 · 심사·대결 송판 치기 전부 안 됨 — ExamService.near 가 NaN 을 거름",
		function()
			weirdPositionCheck({ 0 / 0 }, { exam = true })
		end
	)

	T.test(
		"[B-6c] C-1 고침: 뿌리 좌표가 NaN 이면 (높이 포함, 축 하나만) 들기 안 됨 — MapLayout.isOnTrainMat 높이 검사 · SizeService.isOnTrainMat 이 NaN 을 거름",
		function()
			weirdPositionCheck({ 0 / 0 }, { train = true })
		end
	)

	T.test(
		"[B-6d] C-1 고침 (같은 모양 전부): NaN 이 섞인 자리는 매트 · 문 · 물건 닿기 어디서도 '안' — MapLayout.isOnTrainMat · doorAt · BreakRules.inReach (월드 1·2·3, 큰 몸 포함)",
		function()
			local H = setup()
			local ML = H.MapLayout
			local BR = H.shared("BreakRules")
			local nan = 0 / 0
			for world = 1, 3 do
				local mat = ML.trainMats(world)[1]
				local door = ML.doors(world)[1]
				local target = ML.targetPosition(ML.targetIds(world)[1])
				for axis = 1, 3 do
					local function with(x, y, z)
						local c = { x, y, z }
						c[axis] = nan
						return { x = c[1], y = c[2], z = c[3] }
					end
					local label = string.format("월드 %d 축 %d", world, axis)
					T.falsy(ML.isOnTrainMat(with(mat.x, 3, mat.z), world), label .. " 매트")
					T.eq(ML.doorAt(with(door.x, door.y + 3, door.z), world, 1), nil, label .. " 문")
					T.eq(ML.doorAt(with(door.x, door.y + 3, door.z), world, 13.9), nil, label .. " 문 (거인)")
					T.falsy(BR.inReach(with(target.x, target.y + 3, target.z), target, 1e9, 1e9), label .. " 물건")
					-- 물건 자리 쪽이 NaN 이어도 멂
					T.falsy(
						BR.inReach(
							{ x = target.x, y = target.y, z = target.z },
							with(target.x, target.y, target.z),
							1e9,
							6
						),
						label .. " 물건 자리 NaN"
					)
				end
				-- 진짜 자리는 그대로 됨 (월드 1 결과 그대로)
				T.truthy(
					ML.isOnTrainMat({ x = mat.x, y = 3 * ML.worldScale(world), z = mat.z }, world),
					"월드 " .. world .. " 매트"
				)
				T.eq(
					ML.doorAt({ x = door.x, y = door.y + 3, z = door.z }, world, 1),
					door.world,
					"월드 " .. world .. " 문"
				)
			end
			H.uninstall()
		end
	)

	T.test(
		"[B-7] 한 자리에서 닿는 물건 수: 어울리는 몸은 어느 길가 매트에서도 1~2개 · 작은 몸은 자기 것 하나 · 도장(스폰 · 매트 6칸 · 심사대 · 대결장 가운데)에서는 어느 몸이든 월드마다 앞쪽 3개 안만 (거인 포함)",
		function()
			local H = setup()
			local ML = H.MapLayout
			local uid = 700
			local function reachable(p, w)
				local list = {}
				for _, u in H.Targets.byWorld(w) do
					local slack, vertical = H.S.Break.slackFor(p, u.id)
					if
						H.BreakRules.inReach(
							p.Character.root.Position,
							ML.targetPosition(u.id),
							ML.targetReach(u.id),
							slack,
							vertical
						)
					then
						table.insert(list, u)
					end
				end
				return list
			end
			local report = {}
			for _, kind in KINDS do
				for w = 1, 3 do
					uid += 1
					local p = joinKind(H, uid, kind, w)
					-- 길가 매트 (자기 물건이 든 칸)
					local most = 0
					for _, t in H.Targets.byWorld(w) do
						local mp = ML.matPoint(t.id)
						stand(H, p, mp.x, mp.y, mp.z)
						local list = reachable(p, w)
						T.truthy(
							#list >= 1,
							string.format("%s 몸 %s 매트에서 자기 물건도 안 닿음", kind, t.id)
						)
						most = math.max(most, #list)
						if kind == "small" then
							T.eq(#list, 1, string.format("작은 몸 %s 매트 (닿는 수 %d)", t.id, #list))
						elseif kind == "natural" then
							T.truthy(#list <= 2, string.format("어울리는 몸 %s 매트에서 %d 개", t.id, #list))
						end
					end
					-- 도장 (스폰 · 매트 6칸 · 심사대 · 대결장): 앞쪽 3개 (물건 줄 시작) 안
					local lobby = { ML.spawn(w), ML.examPad(w), ML.duelArena(w) }
					for _, m in ML.trainMats(w) do
						table.insert(lobby, m)
					end
					local lobbyMost = 0
					for _, spot in lobby do
						stand(H, p, spot.x, spot.y, spot.z)
						for _, u in reachable(p, w) do
							lobbyMost = math.max(lobbyMost, u.index - H.Worlds.get(w).firstTarget + 1)
						end
					end
					T.truthy(
						lobbyMost <= 3,
						string.format(
							"%s 몸 월드 %d 도장에서 닿는 가장 뒤 물건 = 앞에서 %d 번째",
							kind,
							w,
							lobbyMost
						)
					)
					table.insert(
						report,
						string.format("%s/월드%d 매트 최대 %d · 도장 %d번째", kind, w, most, lobbyMost)
					)
				end
			end
			print("  (" .. table.concat(report, " · ") .. ")")
			H.uninstall()
		end
	)

	T.test(
		"[B-8] 시험이 진짜로 잡는지 (망가뜨려 보기): 서버의 몸 여유를 0 으로 · 심사대 반지름에서 월드 배율을 빼면 B-5 · B-3b 의 경계 검사가 바로 알아챔 (원래 값에서는 안에서 침 · 시작됨)",
		function()
			local H = setup()
			local ML = H.MapLayout
			local p = joinKind(H, 7100, "giant", 1)
			local pos = ML.targetPosition("cotton")
			local scale = H.S.Size.bodyScale(p)
			local r = ML.targetReach("cotton") + 6 + 3 * (scale - 1)
			H.teleport(p, pos.x + r - 0.5, pos.y, pos.z)
			T.truthy(H.S.Break.hit(p, "cotton"), "원래는 거인이 닿음")
			local realExtra = H.S.Size.bodyExtra
			H.S.Size.bodyExtra = function()
				return 0
			end
			H.teleport(p, pos.x + r - 0.5, pos.y, pos.z)
			T.eq(H.S.Break.hit(p, "cotton"), nil, "몸 여유를 뺐는데 거인이 닿음 (B-5 가 잡아야 함)")
			H.S.Size.bodyExtra = realExtra
			-- 월드 3 심사대: 반지름 20 × 11 = 220 안 (219.5) 에서 시작되어야 함
			local q, qs, qd = joinKind(H, 7101, "small", 3, { belt = 1 })
			local pad = ML.examPad(3)
			H.teleport(q, pad.x, pad.y + 3, pad.z + 20 * H.Sizes.worldScale(3) - 0.5)
			T.truthy(H.S.Exam.startExam(q), "원래는 월드 3 심사대 반지름 안")
			H.S.Exam.cancel(q)
			local realRadius = H.S.Exam.radiusFor
			H.S.Exam.radiusFor = function(base)
				return base
			end
			H.teleport(q, pad.x, pad.y + 3, pad.z + 20 * H.Sizes.worldScale(3) - 0.5)
			T.falsy(H.S.Exam.startExam(q), "월드 배율을 뺐는데 시작됨 (B-3b 가 잡아야 함)")
			H.S.Exam.radiusFor = realRadius
			T.eq(qs.exam, nil)
			T.eq(qd.belt, 1)
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite(
		"holes_v3 C: 포탈·Travel — 연타 · 잠긴 월드 · 대결 중 · 쓰레기 인자 · 리스폰 · 도착 자리가 문 안인가"
	)
	------------------------------------------------------------------

	-- 순간이동 횟수를 세기 위해 캐릭터의 PivotTo 를 감쌈 (캐릭터가 새로 생기면 다시 감싸야 함)
	local function countMoves(p)
		local counter = { n = 0 }
		local character = p.Character
		local pivot = character.PivotTo
		character.PivotTo = function(self, cf)
			counter.n += 1
			return pivot(self, cf)
		end
		return counter
	end

	T.test(
		"[C-1] 월드를 번갈아 옮기는 연타 (0.05초마다 1 ↔ 2 ↔ 3 으로 30초): 순간이동은 속도 제한 (처음 2번 + 초당 1번) 이내 · 순간이동 1번에 Snapshot 1번 · 알림 도배 없음 · 끝 자리는 지금 월드 스폰 · warn 0",
		function()
			local H = setup()
			local p, session = joinReal(H, 800, { version = 1, power = 1e30, belt = 14 })
			local moves = countMoves(p)
			T.eq(session.currentWorld, 3, "접속은 열린 가장 높은 월드")
			H.clearSent()
			local order = { 1, 2, 3, 2, 1, 3 }
			for i = 1, 600 do
				H.client(p, "Travel", order[1 + i % #order])
				H.advance(0.05)
			end
			-- 30초 동안 허용 = 처음 2번 + 초당 1번 = 32번 이내
			print(
				string.format(
					"  (30초 번갈아 연타 600번: 순간이동 %d번 · Snapshot %d번 · 알림 %d개)",
					moves.n,
					#H.sent(p, "Snapshot"),
					#H.notifications(p)
				)
			)
			T.truthy(moves.n >= 15 and moves.n <= 33, "순간이동 " .. moves.n .. "번")
			T.eq(#H.sent(p, "Snapshot"), moves.n, "순간이동 1번에 Snapshot 1번")
			T.truthy(#H.notifications(p) <= 2, "알림 " .. #H.notifications(p) .. "개")
			H.advance(2.5)
			local w = session.currentWorld
			local spot = H.MapLayout.spawn(w)
			T.near(p.Character.root.Position.X, spot.x, 1e-6, "스폰 x")
			T.near(p.Character.root.Position.Z, spot.z, 1e-6, "스폰 z")
			T.eq(H.MapLayout.worldAt(p.Character.root.Position), w)
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			-- 다른 월드로의 연속 이동은 2초 규칙에 안 걸림 (2초 규칙은 방금 온 월드로 또 오는 것만) — 속도 제한만 지킴
			H.advance(5)
			local before = moves.n
			H.client(p, "Travel", 1)
			H.client(p, "Travel", 2)
			H.client(p, "Travel", 1)
			T.eq(moves.n - before, 2, "한꺼번에 3번 → 처음 2번만 (속도 제한 덤 2)")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[C-2] Travel 쓰레기 인자 (없음 · nil · 0 · -0 · -1 · 4 · 99 · 1.5 · 2.0000001 · NaN · ±무한 · 1e308 · 2^53 · '2' · 표 · true · 함수 · 인자 여러 개): 이동 없음 · 알림 없음 · 순간이동 0 · warn 0 / 서버 함수를 직접 불러도 false",
		function()
			local H = setup()
			local p, session = joinReal(H, 801, { version = 1, power = 1e30, belt = 14 })
			session.currentWorld = 1
			H.S.World.placeAtSpawn(p, 1)
			p:SetAttribute("CurrentWorld", 1)
			local moves = countMoves(p)
			H.clearSent()
			local junk = {
				{ n = 0 },
				table.pack(nil),
				table.pack(0),
				table.pack(-0),
				table.pack(-1),
				table.pack(4),
				table.pack(99),
				table.pack(1.5),
				table.pack(2.0000001),
				table.pack(0 / 0),
				table.pack(math.huge),
				table.pack(-math.huge),
				table.pack(1e308),
				table.pack(2 ^ 53),
				table.pack("2"),
				table.pack("world 2"),
				table.pack({ 2 }),
				table.pack(true),
				table.pack(function() end),
				table.pack(nil, 2), -- 맨 앞이 nil 이면 뒤의 2 는 무시
			}
			for i, args in junk do
				H.client(p, "Travel", table.unpack(args, 1, args.n))
				H.advance(1.1)
				T.eq(session.currentWorld, 1, "쓰레기 " .. i .. " 번 뒤 지금 월드")
				T.eq(H.S.World.travel(p, args[1]), false, "직접 부름 " .. i)
			end
			T.eq(moves.n, 0, "순간이동 0번")
			T.eq(#H.notifications(p), 0, "알림 없음: " .. #H.notifications(p))
			T.eq(#H.sent(p, "Snapshot"), 0, "Snapshot 없음")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			-- 쓰레기 뒤에도 진짜 Travel 은 됨
			H.client(p, "Travel", 2, 3, 4)
			T.eq(session.currentWorld, 2)
			T.eq(moves.n, 1)
			H.uninstall()
		end
	)

	T.test(
		"[C-3] 띠마다 (1 ~ 22) 어느 월드로 Travel 할 수 있나: 저장 보정(reconcile)이 준 월드 = 1 + 가진 대결 띠 수 — 열린 월드로는 가고 그 위 월드는 못 감 (서버 판정, 잠김 알림은 2초에 한 번)",
		function()
			local H = setup()
			local n = 0
			for belt = 1, H.Belts.COUNT do
				local p, session, data = joinReal(H, 900 + belt, { version = 1, power = 0, belt = belt, world = 1 })
				local open = H.Progression.worldsFromBelt(belt)
				T.eq(data.world, open, "띠 " .. belt .. " 열린 월드")
				for w = 1, 3 do
					H.advance(2.1)
					H.clearSent()
					local before = session.currentWorld
					H.client(p, "Travel", w)
					n += 1
					if w <= open then
						T.eq(session.currentWorld, w, string.format("띠 %d: 월드 %d 로 감", belt, w))
						T.eq(p:GetAttribute("CurrentWorld"), w)
						T.eq(H.MapLayout.worldAt(p.Character.root.Position), w, "땅")
					else
						T.eq(session.currentWorld, before, string.format("띠 %d: 월드 %d 는 잠김", belt, w))
						T.eq(H.MapLayout.worldAt(p.Character.root.Position), before, "그 자리 그대로")
						T.eq(#H.sent(p, "Snapshot"), 0)
					end
				end
			end
			T.eq(n, 66)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[C-4] 대결 · 심사 중 Travel: 카운트다운 · 진행 중 어느 월드로든 안 감 (자리 · 대결 상태 · 활동 그대로) · 이긴 뒤에는 새로 열린 월드로 감 · 진 뒤에도 감 · 심사 합격 직후도 감",
		function()
			local H = setup()
			local ML = H.MapLayout
			-- 월드 2 대결 띠 (14 무지개) 바로 앞 띠 13 · 월드 2 까지 열림
			local p, session, data = joinReal(H, 810, { version = 1, power = 1e60, belt = 13 })
			T.eq(session.currentWorld, 2)
			local a = ML.duelArena(2)
			H.teleport(p, a.player.x, a.player.y + 3, a.player.z)
			H.client(p, "StartDuel")
			T.eq(H.S.Sessions.activity(session), "duel", "대결 시작")
			local moves = countMoves(p)
			for _, w in { 1, 2, 3 } do
				H.client(p, "Travel", w)
				T.eq(moves.n, 0, "카운트다운 중 Travel " .. w)
			end
			H.advance(3.1)
			H.advance(1.2)
			for _, w in { 1, 3, 2 } do
				H.client(p, "Travel", w)
				T.eq(moves.n, 0, "진행 중 Travel " .. w)
			end
			T.eq(session.currentWorld, 2)
			T.eq(p:GetAttribute("Activity"), "duel")
			T.truthy(session.duel and not session.duel.finished, "대결 그대로")
			T.eq(H.MapLayout.worldAt(p.Character.root.Position), 2)
			-- 이김 (힘 1e60: 송판 한 번에 한 장)
			for _ = 1, 15 do
				H.client(p, "Hit", "duel")
				H.advance(0.25)
			end
			T.eq(data.belt, 14, "무지개 띠")
			T.eq(data.world, 3, "월드 3 열림")
			T.eq(H.S.Sessions.activity(session), "")
			H.advance(2.1)
			H.client(p, "Travel", 3)
			T.eq(session.currentWorld, 3, "이기고 나서 월드 3 으로")
			T.eq(moves.n, 1)
			-- 진 경우: 힘 0
			local q, qs, qd = joinReal(H, 811, { version = 1, power = 0, belt = 6 })
			local a1 = ML.duelArena(1)
			H.teleport(q, a1.player.x, a1.player.y + 3, a1.player.z)
			H.client(q, "StartDuel")
			T.eq(H.S.Sessions.activity(qs), "duel")
			H.advance(40) -- 시험관이 먼저 다 깸
			T.eq(H.S.Sessions.activity(qs), "", "졌음")
			T.eq(qd.belt, 6, "띠 그대로")
			T.eq(qd.world, 1, "월드 1 그대로 (월드 2 안 열림)")
			H.client(q, "Travel", 2)
			T.eq(qs.currentWorld, 1, "월드 2 는 아직 잠김")
			H.client(q, "Travel", 1)
			-- 심사 중 · 합격 직후
			local r, rs, rd = joinReal(H, 812, { version = 1, power = 1e60, belt = 1 })
			local pad = ML.examPad(1)
			H.teleport(r, pad.x, pad.y + 3, pad.z)
			H.client(r, "StartExam")
			T.eq(H.S.Sessions.activity(rs), "exam")
			H.advance(2.1)
			H.client(r, "Travel", 1)
			T.eq(rs.currentWorld, 1)
			T.truthy(rs.exam and not rs.exam.finished, "심사 그대로")
			for _ = 1, 10 do
				H.client(r, "Hit", "exam")
				H.advance(0.25)
			end
			T.eq(rd.belt, 2, "합격")
			T.eq(H.S.Sessions.activity(rs), "")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	-- Travel 으로 도착한 자리가 몸 크기 · 월드마다 문 안이 아님 (문 안이면 클라가 바로 다시 Travel 해서 핑퐁)
	T.test(
		"[C-5] 도착 자리와 문: 월드 1·2·3 × 몸 (힘 1 ~ 1e60 을 반 자리씩 · 80가지) 에서 진짜 Travel 로 도착한 자리가 어느 문 칸 안도 아님 (MapLayout.doorAt, 큰 몸은 몸 반지름 만큼 넓힌 칸) · 스폰 위치와 문 사이 거리 · 리스폰 자리도 같음",
		function()
			local H = setup()
			local ML = H.MapLayout
			local p, session = joinReal(H, 820, { version = 1, power = 0, belt = 22 })
			local checked = 0
			local minGap = math.huge
			local powers = { 0 }
			for k = 0, 80 do
				table.insert(powers, 10 ^ (k / 2))
			end
			for _, power in powers do
				H.S.Wallet.set(p, power, nil)
				local scale = H.S.Size.bodyScale(p)
				for w = 1, 3 do
					H.advance(2.1)
					H.client(p, "Travel", w)
					T.eq(session.currentWorld, w)
					local pos = p.Character.root.Position
					T.eq(
						ML.doorAt(pos, w, scale),
						nil,
						string.format("도착 자리가 문 안 (월드 %d · 몸 %.2f · 힘 %.1e)", w, scale, power)
					)
					checked += 1
					-- 문 칸 가장자리까지 남은 거리 (몸 반지름 넓힘 포함) — 가장 아슬아슬한 곳
					local ws = H.Sizes.worldScale(w)
					local pad = ML.BODY_RADIUS * scale
					for _, d in ML.doors(w) do
						local gapX = math.abs(pos.X - d.x) - (d.halfX + pad)
						local gapZ = (d.z + d.front + pad) - pos.Z -- 음수 = 문 칸보다 안쪽(+z) 으로 벗어남
						minGap = math.min(minGap, math.max(gapX, -gapZ))
					end
					-- 리스폰 (죽고 다시 태어남) 도 같은 자리
					p.Character.humanoid.Health = 0
					H.spawn(p, 0, 3, 0)
					H.advance(0.1)
					T.eq(ML.doorAt(p.Character.root.Position, w, scale), nil, "리스폰 자리가 문 안")
					T.eq(ws, ML.worldScale(w))
				end
			end
			print(
				string.format(
					"  (도착 %d곳 · 문 칸 가장자리까지 가장 아슬아슬한 거리 %.1f 스터드)",
					checked,
					minGap
				)
			)
			T.truthy(checked >= 240)
			T.truthy(minGap > 0)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[C-6] 문 칸: 도장에서 하는 일 (수련 매트 6칸 · 심사대 · 대결장 · 아령 가게 · 띠 표지판 · 스폰) 위에 서도 문에 안 걸림 (큰 몸 포함) · 문 가운데에 서면 그 문의 월드를 가리킴 · 문은 내 월드를 뺀 두 곳",
		function()
			local H = setup()
			local ML = H.MapLayout
			for w = 1, 3 do
				local doors = ML.doors(w)
				T.eq(#doors, 2, "월드 " .. w .. " 문 개수")
				local seen = {}
				for _, d in doors do
					T.truthy(d.world ~= w and d.world >= 1 and d.world <= 3, "문이 가는 월드")
					T.falsy(seen[d.world], "같은 월드로 가는 문이 둘")
					seen[d.world] = true
				end
				for _, scale in { 1, 2.5, H.Sizes.worldScale(w), 8, H.Sizes.MAX_SCALE } do
					local spots = { ML.spawn(w), ML.dumbbellShop(w), ML.beltBoard(w), ML.examPad(w), ML.duelArena(w) }
					for _, m in ML.trainMats(w) do
						table.insert(spots, m)
					end
					for _, spot in spots do
						-- 가장자리에서 1 스터드 안쪽 (아령 가게 모서리 (31, -39) 는 몸 13.7 배 넘는 거인의 문 칸과 0.2 스터드 겹쳐 닿음 — 가게는 메뉴로 열어서 거기 설 일은 없음, 보고서 참고)
						local hx, hz = spot.sizeX / 2 - 1, spot.sizeZ / 2 - 1
						for _, off in { { 0, 0 }, { hx, hz }, { -hx, hz }, { hx, -hz }, { -hx, -hz } } do
							T.eq(
								ML.doorAt(
									{ x = spot.x + off[1], y = spot.y + 3 * scale, z = spot.z + off[2] },
									w,
									scale
								),
								nil,
								string.format(
									"월드 %d 몸 %.2f 도장 (%.1f, %.1f)",
									w,
									scale,
									spot.x + off[1],
									spot.z + off[2]
								)
							)
						end
					end
					-- 문 가운데에 서면 그 문
					for _, d in doors do
						T.eq(
							ML.doorAt({ x = d.x, y = d.y + 3 * scale, z = d.z + d.front / 2 }, w, scale),
							d.world,
							string.format("월드 %d 문 → 월드 %d (몸 %.2f)", w, d.world, scale)
						)
					end
					-- 문 밖 한참 앞에서는 안 걸림
					T.eq(
						ML.doorAt(
							{ x = doors[1].x, y = 3 * scale, z = doors[1].z + 8 * ML.worldScale(w) + 3 * scale },
							w,
							scale
						),
						nil
					)
				end
			end
		end
	)

	T.test(
		"[C-7] 리스폰 · 캐릭터 없음 · 죽은 몸 중에 Travel: 캐릭터가 없어도 지금 월드가 바뀌고 새 캐릭터는 그 월드 스폰에 태어남 · 죽은 몸도 월드는 바뀜 · 옮기자마자(같은 순간) 리스폰해도 마지막 월드 스폰 · 몸 크기 그대로",
		function()
			local H = setup()
			local ML = H.MapLayout
			local p, session, data = joinReal(H, 830, { version = 1, power = 1e30, belt = 14 })
			local scale = H.S.Size.bodyScale(p)
			-- (1) 캐릭터가 없는 사이 (죽고 다시 태어나는 중)
			session.currentWorld = 1
			p.Character = nil
			H.advance(2.1)
			H.client(p, "Travel", 2)
			T.eq(session.currentWorld, 2, "캐릭터 없이도 월드는 바뀜")
			T.eq(p:GetAttribute("CurrentWorld"), 2)
			H.spawn(p, 0, 3, 0)
			H.advance(0.1)
			T.eq(ML.worldAt(p.Character.root.Position), 2, "새 캐릭터는 월드 2 스폰")
			T.near(
				p.Character.root.Position.Y,
				ML.spawn(2).y + 3 * math.max(scale, H.Sizes.worldScale(2)),
				1e-6,
				"스폰 높이"
			)
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			-- (2) 죽은 몸 (Health 0, 아직 안 지워짐)
			p.Character.humanoid.Health = 0
			H.advance(2.1)
			H.client(p, "Travel", 3)
			T.eq(session.currentWorld, 3)
			H.spawn(p, 0, 3, 0)
			H.advance(0.1)
			T.eq(ML.worldAt(p.Character.root.Position), 3)
			-- (3) 옮기자마자 같은 순간에 리스폰
			H.advance(2.1)
			H.client(p, "Travel", 1)
			H.spawn(p, 0, 3, 0)
			H.client(p, "Travel", 2) -- 속도 제한 덤 (2번째)
			H.spawn(p, 50, 3, 50)
			H.advance(0.1)
			T.eq(ML.worldAt(p.Character.root.Position), session.currentWorld, "마지막 월드 스폰")
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			-- (4) 접속 처리가 끝나기 전 Travel (아직 불러오는 중) 은 아무 일도 안 일어남
			local q = H.newPlayer(831)
			H.spawn(q, 0, 3, 0)
			H.client(q, "Travel", 2)
			T.eq(H.S.Sessions.getLoaded(q), nil)
			T.eq(data.belt, 14)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[C-8] 한 순간에 Travel 1,000번 (1 · 2 · 3 섞어서) 과 다른 Remote 섞어 호출: 속도 제한으로 이동 2번 이하 · 서버 터짐 없음 · 이동 뒤 힘·돈·띠 그대로",
		function()
			local H = setup()
			local p, _, data = joinReal(H, 840, { version = 1, power = 1e12, money = 777, belt = 14 })
			local moves = countMoves(p)
			local rng = T.rng(9)
			for _ = 1, 1000 do
				H.client(p, "Travel", 1 + math.floor(rng() * 3))
				if rng() < 0.3 then
					H.client(p, "ClientReady")
				end
			end
			T.truthy(moves.n <= 2, "순간이동 " .. moves.n)
			T.eq(data.power, 1e12)
			T.eq(data.money, 777)
			T.eq(data.belt, 14)
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite(
		"holes_v3 D: 띠 22개 — 순서 건너뛰기 · 월드 열림 · 옛 저장 · 이상한 띠 값 · 돈 배율 · sim 과 서버가 같은 말을 하나"
	)
	------------------------------------------------------------------

	T.test(
		"[D-1] 띠 표 (22개): 월드 7 · 7 · 8 · 대결 띠는 정확히 각 월드의 마지막 3개 (7 · 14 · 22) · 대결 띠만 월드를 엶 (worldsFromBelt) · 월드 W 의 띠는 W 가 열린 뒤에만 받을 수 있음 · 그랜드 마스터는 22 에서만 · 심사/대결 체력 칸이 띠 종류와 맞음",
		function()
			local H = setup()
			local Belts, Worlds, Progression = H.Belts, H.Worlds, H.Progression
			T.eq(Belts.COUNT, 22)
			T.eq(Worlds.COUNT, 3)
			T.eq(Belts.WORLD_COUNT, 3)
			T.eq(H.MapLayout.WORLD_COUNT, 3)
			T.eq(#Belts.ofWorld(1), 7)
			T.eq(#Belts.ofWorld(2), 7)
			T.eq(#Belts.ofWorld(3), 8)
			T.eq(#Belts.ofWorld(4), 0, "없는 월드는 빈 표")
			local duels = {}
			for _, b in Belts.list do
				if b.duel then
					table.insert(duels, b.index)
				end
			end
			T.eq(table.concat(duels, ","), "7,14,22", "대결 띠")
			for w = 1, 3 do
				local list = Belts.ofWorld(w)
				T.eq(Belts.duelOf(w), list[#list], "월드 " .. w .. " 대결 띠 = 그 월드 마지막 띠")
				T.eq(Worlds.get(w).duelBoardHp, list[#list].duelBoardHp, "월드 " .. w .. " 대결 송판")
				T.truthy(Worlds.get(w).duelBoardHp > 0)
			end
			T.eq(Progression.beltToOpen(1), 1)
			T.eq(Progression.beltToOpen(2), 7)
			T.eq(Progression.beltToOpen(3), 14)
			local lastWorldCount = 1
			local lastMult, lastNeed = 0, -1
			for i, b in Belts.list do
				T.eq(b.index, i)
				-- 월드는 대결 띠를 받는 순간에만 늘어남 (딱 1 씩)
				local opened = Progression.worldsFromBelt(i)
				T.truthy(
					opened == lastWorldCount or (b.duel and opened == lastWorldCount + 1 and opened <= 3),
					"띠 " .. i .. " 월드 " .. opened
				)
				if b.duel then
					T.eq(opened, math.min(3, b.world + 1), "대결 띠 " .. i .. " 가 여는 월드")
				else
					T.eq(opened, b.world, "일반 띠 " .. i .. " 은 월드를 안 엶")
				end
				lastWorldCount = opened
				-- 그 띠를 받으려면 그 띠의 월드가 이미 열려 있어야 함 (앞 띠까지 가졌을 때 열린 월드 ≥ 이 띠의 월드)
				if i >= 2 then
					T.truthy(
						Progression.worldsFromBelt(i - 1) >= b.world,
						"띠 " .. i .. " 은 월드 " .. b.world .. " 가 열린 뒤에만"
					)
				end
				T.eq(Progression.isGrandMaster(i), i == 22, "그랜드 마스터는 22 에서만 (" .. i .. ")")
				T.truthy(b.moneyMultiplier > lastMult, "돈 배율이 늘기만 함 " .. i)
				T.truthy(b.needPower >= lastNeed, "추천 힘이 줄지 않음 " .. i)
				lastMult, lastNeed = b.moneyMultiplier, b.needPower
				-- 체력 칸이 종류와 맞음
				if b.duel then
					T.eq(b.examBoardHp, 0)
					T.truthy(b.duelBoardHp > 0)
					T.truthy(H.ExamRules.startDuel(i, 0), "대결 상태 " .. i)
					T.eq(H.ExamRules.startExam(i, 0), nil, "대결 띠는 심사로 못 받음 " .. i)
					T.eq(H.ExamRules.startDuel(i, 0).world, b.world, "시험관 월드 " .. i)
					T.eq(H.ExamRules.startDuel(i, 0).examiner, Worlds.get(b.world).examiner)
				elseif i == 1 then
					T.eq(b.examBoardHp, 0)
					T.eq(H.ExamRules.startExam(i, 0), nil, "흰 띠는 시작 띠")
					T.eq(H.ExamRules.startDuel(i, 0), nil)
				else
					T.truthy(b.examBoardHp > 0 and b.duelBoardHp == 0)
					T.truthy(H.ExamRules.startExam(i, 0), "심사 상태 " .. i)
					T.eq(H.ExamRules.startDuel(i, 0), nil, "심사 띠는 대결로 못 받음 " .. i)
				end
			end
			T.eq(Progression.worldsFromBelt(22), 3)
			T.eq(Progression.nextBelt(22), nil)
			-- 범위 밖 띠 번호는 오류 없이 (가장 가까운 끝으로)
			for _, junk in { 0, -5, 23, 99, 1.5, 0 / 0, math.huge, -math.huge, "7", {}, true } do
				local ok, e = pcall(function()
					return Progression.worldsFromBelt(junk),
						Progression.nextBelt(junk),
						Progression.canExam(0, junk),
						Progression.canDuel(0, junk)
				end)
				T.truthy(ok, "오류 " .. tostring(junk) .. " " .. tostring(e))
			end
			T.eq(Belts.get(0), nil)
			T.eq(Belts.get(23), nil)
			T.eq(Belts.get(1.5), nil)
			T.eq(Belts.get(0 / 0), nil)
			T.eq(H.Economy.beltMultiplier(0), 1, "없는 띠 배율 = 1 (200 이 아님)")
			T.eq(H.Economy.beltMultiplier(23), 1)
			T.eq(H.Economy.beltMultiplier(0 / 0), 1)
			H.uninstall()
		end
	)

	T.test(
		"[D-2] 서버로 끝까지 (띠 1 → 22, 힘 1e60 · 배수 2048): 한 번에 딱 1 띠씩 · 월드는 대결 띠(7 · 14)에서만 하나씩 열림 · 심사 띠에 대결을, 대결 띠에 심사를 시작하면 거절 · 22 에서만 그랜드 마스터 · 끝 띠에서는 더 못 시작 · 매 띠마다 그 띠의 돈 배율로 돈이 들어옴",
		function()
			local H = setup()
			local ML = H.MapLayout
			local p, session, data =
				joinReal(H, 1000, { version = 1, power = 1e60, powerBoost = 2048, belt = 1, money = 0 })
			T.eq(data.powerBoost, 2048)
			local promoted, worldsOpened = 0, 0
			for k = 1, 21 do
				local nextBelt = H.Belts.get(k + 1)
				local wantDuel = nextBelt.duel
				-- 열린 가장 높은 월드로 가서 (그 월드의 심사대 · 대결장 사용)
				H.advance(2.1)
				H.client(p, "Travel", data.world)
				T.eq(session.currentWorld, data.world)
				local pad = ML.examPad(data.world)
				local arena = ML.duelArena(data.world)
				local at = if wantDuel then arena.player else pad
				H.teleport(p, at.x, at.y + 3 * H.S.Size.bodyScale(p), at.z)
				-- 다른 종류는 거절 (상태 그대로)
				H.client(p, if wantDuel then "StartExam" else "StartDuel")
				T.eq(session.exam, nil, "띠 " .. k .. " → 잘못된 종류 심사")
				T.eq(session.duel, nil, "띠 " .. k .. " → 잘못된 종류 대결")
				T.eq(data.belt, k)
				H.client(p, "Hit", if wantDuel then "duel" else "exam")
				T.eq(data.belt, k, "시작 안 했는데 송판 침")
				-- 맞는 종류 시작 → 끝까지
				H.client(p, if wantDuel then "StartDuel" else "StartExam")
				T.eq(H.S.Sessions.activity(session), if wantDuel then "duel" else "exam", "띠 " .. k .. " 시작")
				if wantDuel then
					H.advance(3.1)
				end
				for _ = 1, 40 do
					if H.S.Sessions.activity(session) == "" then
						break
					end
					H.client(p, "Hit", if wantDuel then "duel" else "exam")
					H.advance(0.25)
				end
				T.eq(data.belt, k + 1, "딱 1 띠 올라감 (" .. k .. " → " .. (k + 1) .. ")")
				-- 끝난 뒤에도 계속 송판을 쳐 봄 (끝난 심사·대결에 또 쳐서 한 번 더 올라가는 길 없음)
				for _ = 1, 8 do
					H.client(p, "Hit", "exam")
					H.client(p, "Hit", "duel")
					H.advance(0.2)
				end
				T.eq(data.belt, k + 1, "끝난 뒤 송판 치기로 또 올라감 (" .. (k + 1) .. ")")
				H.advance(1.2) -- (연타로 비운 치기 속도 제한 칸이 다시 참)
				promoted += 1
				local opened = H.Progression.worldsFromBelt(k + 1)
				T.eq(data.world, opened, "띠 " .. (k + 1) .. " 월드")
				T.eq(
					data.world > session.currentWorld,
					wantDuel and k + 1 < 22,
					"새 월드는 대결 띠에서만 열림 (띠 " .. (k + 1) .. ")"
				)
				if wantDuel and k + 1 < 22 then
					worldsOpened += 1
				end
				T.eq(data.grandMaster, k + 1 == 22, "그랜드 마스터는 22 에서만")
				T.eq(p:GetAttribute("Belt"), k + 1)
				T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
				-- 지금 띠의 돈 배율로 돈이 들어옴 (그 월드 첫 물건 · 한 번에 깨지는 힘)
				local first = H.Targets.byWorld(session.currentWorld)[1]
				local mp = ML.matPoint(first.id)
				H.teleport(p, mp.x, mp.y + 3 * H.S.Size.bodyScale(p), mp.z)
				local before = data.money
				H.client(p, "Hit", first.id)
				local gained = data.money - before
				local expected = first.reward * H.Belts.get(k + 1).moneyMultiplier
				T.truthy(
					math.abs(gained - expected) <= expected * 1e-9 + 1e-6,
					string.format("띠 %d 돈 %s ≠ %s", k + 1, gained, expected)
				)
			end
			T.eq(promoted, 21)
			T.eq(worldsOpened, 2, "월드는 정확히 2번 열림 (월드 2 · 월드 3)")
			T.eq(data.stats.examsPassed, 18, "심사 합격 18번 (띠 2~6 · 8~13 · 15~21)")
			T.eq(data.stats.duelsWon, 3, "대결 승리 3번 (띠 7 · 14 · 22)")
			T.eq(data.stats.examsFailed + data.stats.duelsLost, 0, "진 적 없음")
			T.eq(data.belt, 22)
			T.truthy(data.grandMaster)
			-- 끝 띠: 더 시작 못 함
			H.advance(2.1)
			local pad = ML.examPad(3)
			H.teleport(p, pad.x, pad.y + 3 * H.S.Size.bodyScale(p), pad.z)
			H.client(p, "StartExam")
			T.eq(session.exam, nil)
			local arena = ML.duelArena(3)
			H.teleport(p, arena.player.x, arena.player.y + 3 * H.S.Size.bodyScale(p), arena.player.z)
			H.client(p, "StartDuel")
			T.eq(session.duel, nil)
			T.eq(data.belt, 22)
			T.truthy(H.hasNotify(p, "error", "그랜드 마스터"), "끝 띠 안내 글")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	-- 12개 띠 시절 (월드마다 4개, 대결 4 · 8 · 12, 12 = 그랜드 마스터) 저장 모양과 이상한 띠 값
	local OLD_SAVES = {
		{ "옛 4번 (대결 빨강 — 월드 2 열림)", { belt = 4, world = 2 } },
		{ "옛 5번 (월드 2 첫 띠)", { belt = 5, world = 2 } },
		{ "옛 8번 (대결 검정 — 월드 3 열림)", { belt = 8, world = 3 } },
		{ "옛 9번 (월드 3 첫 띠)", { belt = 9, world = 3 } },
		{ "옛 12번 그랜드 마스터", { belt = 12, world = 3, grandMaster = true } },
	}
	local WEIRD_BELTS = {
		{ "띠 0", { belt = 0 } },
		{ "띠 -3", { belt = -3 } },
		{ "띠 7.9 (소수)", { belt = 7.9 } },
		{ "띠 22.9", { belt = 22.9 } },
		{ "띠 23", { belt = 23 } },
		{ "띠 글자 '7'", { belt = "7" } },
		{ "띠 표", { belt = {} } },
		{ "띠 NaN", { belt = 0 / 0 } },
		{ "띠 무한", { belt = math.huge } },
		{ "띠 1 인데 월드 3 · 그랜드 마스터", { belt = 1, world = 3, grandMaster = true } },
		{ "띠 22 인데 월드 1", { belt = 22, world = 1 } },
		{ "월드만 3 (띠 없음)", { world = 3 } },
		{ "월드 -1 · 띠 8", { world = -1, belt = 8 } },
	}

	T.test(
		"[D-3] 옛 12띠 저장 · 이상한 띠 값 18가지를 진짜 불러오기: 항상 띠 1~22 정수 · 월드 = 띠가 여는 월드 · 그랜드 마스터는 띠 22 일 때만 · 접속 자리는 열린 월드 안 · 몸 크기 · 걷기 정상 · warn 0 (결과 표는 출력)",
		function()
			local H = setup()
			local lines = {}
			local all = {}
			for _, c in OLD_SAVES do
				table.insert(all, c)
			end
			for _, c in WEIRD_BELTS do
				table.insert(all, c)
			end
			for i, c in all do
				local stored = { version = 1, power = 5e20, money = 1e9, dumbbellLevel = 12 }
				for k, v in c[2] do
					stored[k] = v
				end
				local p, session, data = joinReal(H, 1100 + i, stored)
				T.truthy(data ~= nil, c[1])
				local bad = problems(H, p, { looseGrandMaster = true })
				T.truthy(bad == nil, c[1] .. ": " .. tostring(bad))
				T.truthy(
					data.belt >= 1 and data.belt <= 22 and data.belt % 1 == 0,
					c[1] .. " 띠 " .. tostring(data.belt)
				)
				T.eq(session.currentWorld, data.world, c[1] .. " 접속 월드 = 열린 가장 높은 월드")
				T.eq(H.MapLayout.worldAt(p.Character.root.Position), data.world)
				-- 저장하고 다시 불러와도 같음 (한 번 고쳐지면 안정)
				H.leave(p)
				local _, _, again = joinReal(H, 1100 + i, nil)
				T.eq(again.belt, data.belt, c[1] .. " 다시 불러온 띠")
				T.eq(again.world, data.world)
				T.eq(again.grandMaster, data.grandMaster)
				table.insert(
					lines,
					string.format(
						"%s → 띠 %d 월드 %d%s",
						c[1],
						data.belt,
						data.world,
						if data.grandMaster then " GM" else ""
					)
				)
			end
			print("  (" .. table.concat(lines, " | ") .. ")")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[D-3b] C-2 고침: 터무니없이 큰 띠 값 (23 · 1e15 · 1e308) 은 최고 띠(22)로 올라가지 않고 1 로 (월드 1 · 배율 1) — 수석 DataSchema.integerOr",
		function()
			local H = setup()
			for i, belt in { 23, 1e15, 1e308 } do
				local _, _, data = joinReal(H, 1200 + i, { version = 1, power = 100, belt = belt })
				T.eq(
					data.belt,
					1,
					"터무니없는 띠 " .. tostring(belt) .. " → 띠 " .. data.belt .. " 월드 " .. data.world
				)
				T.eq(data.world, 1)
				T.eq(data.grandMaster, false)
			end
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[D-3c] C-2 고침: 그랜드 마스터는 띠에서 정함 — 저장된 띠가 22 면 표시가 없어도 참 · 22 가 아니면 표시가 있어도 거짓",
		function()
			local H = setup()
			local p, _, data = joinReal(H, 1210, { version = 1, power = 100, belt = 22 })
			T.truthy(data.grandMaster, "띠 22 인데 그랜드 마스터 아님")
			T.eq(p:GetAttribute("GrandMaster"), true, "Attribute 도")
			local _, _, d2 = joinReal(H, 1211, { version = 1, power = 100, belt = 21, grandMaster = true })
			T.eq(d2.grandMaster, false, "띠 21 + 표시 → 거짓")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.skip(
		"[D-4] 옛 12띠 저장 (version 1 그대로) 이 22띠 표에서 진행도가 줄어듦: 옛 그랜드 마스터 → 9단 띠 · 월드 2 (월드 3 · 칭호 사라짐) · 옛 대결 4번 → 파랑 띠 · 월드 1 (C-3)",
		"게시 전이라 일부러 안 고침 (C-3 — 지금 저장은 스튜디오 시험 데이터뿐, /reset 으로 지움). Config.SCHEMA_VERSION 이 1 그대로라 DataSchema.migrate 가 띠 번호를 안 옮김 — 게시한 뒤에 옛 저장이 생기면 version 2 + 번호 옮기기 (4→7 · 8→14 · 12→22) 가 필요",
		function()
			local H = setup()
			local _, _, data =
				joinReal(H, 1300, { version = 1, power = 1e36, belt = 12, world = 3, grandMaster = true })
			T.truthy(
				data.world >= 3 and data.grandMaster,
				string.format(
					"옛 그랜드 마스터 → 띠 %d 월드 %d 그랜드 마스터 %s",
					data.belt,
					data.world,
					tostring(data.grandMaster)
				)
			)
			local _, _, d2 = joinReal(H, 1301, { version = 1, power = 1e14, belt = 4, world = 2 })
			T.truthy(d2.world >= 2, string.format("옛 월드 2 (대결 4번) → 월드 %d", d2.world))
		end
	)

	T.test(
		"[D-5] 개발 명령 /belt · /world 이상한 값 (0 · 23 · 1.5 · -1 · NaN · inf · 글자 · 빈칸) 은 거절 · 띠 · 월드 · 그랜드 마스터 그대로 / 정상 값은 월드를 띠에 맞춤 (22 → 월드 3 · GM, 1 → 월드 1) · 끝나고 상태가 앞뒤가 맞음",
		function()
			local H = setup()
			local p, session, data = joinReal(H, 1400, { version = 1, power = 1e20, belt = 9 })
			local before = { belt = data.belt, world = data.world, gm = data.grandMaster }
			for _, arg in { "0", "23", "1.5", "-1", "nan", "inf", "abc", "", "1e999", "0x", "--7" } do
				H.S.Dev.handle(p, "/belt " .. arg)
				H.S.Dev.handle(p, "/world " .. arg)
				T.eq(data.belt, before.belt, "/belt " .. arg)
				T.eq(data.world, before.world, "/world " .. arg)
				T.eq(data.grandMaster, before.gm)
			end
			H.S.Dev.handle(p, "/belt 22")
			T.eq(data.world, 3)
			T.truthy(data.grandMaster)
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			H.S.Dev.handle(p, "/belt 1")
			T.eq(data.world, 1)
			T.eq(data.grandMaster, false)
			T.eq(session.currentWorld, 1, "열린 월드 밖에 있지 않음")
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			H.S.Dev.handle(p, "/world 3")
			T.eq(data.belt, 14, "월드 3 을 여는 띠 (무지개) 로 올림")
			T.eq(data.world, 3)
			T.truthy(problems(H, p) == nil, tostring(problems(H, p)))
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[D-6] 깬 돈 = 물건값 × 지금 띠 배율 × (돈 2배면 2): 띠 1~22 × 패스 있음/없음 44가지 · 서버 치기 · 띠가 바뀐 뒤 바로 다음 치기부터 새 배율 · 이상한 띠 값 (0 · 23 · NaN) 은 배율 1",
		function()
			local H = setup()
			local ML = H.MapLayout
			local mp = ML.matPoint("cotton")
			local cotton = H.Targets.get("cotton")
			for belt = 1, 22 do
				for _, pass in { false, true } do
					local p, _, data = join(
						H,
						1500 + belt * 2 + (if pass then 1 else 0),
						{ power = 1e60, belt = belt, moneyPass = pass, world = H.Progression.worldsFromBelt(belt) },
						{ mp.x, mp.y + 3, mp.z }
					)
					H.S.Break.hit(p, "cotton")
					local want = cotton.reward * H.Belts.get(belt).moneyMultiplier * (if pass then 2 else 1)
					T.truthy(
						math.abs(data.money - want) < want * 1e-9,
						string.format("띠 %d 패스 %s: %s ≠ %s", belt, tostring(pass), data.money, want)
					)
				end
			end
			for _, junk in { 0, 23, 99, 0 / 0, -1, 1.5 } do
				local p, _, data = join(H, 1600, { power = 1e60, world = 1 }, { mp.x, mp.y + 3, mp.z })
				data.belt = junk
				H.S.Break.hit(p, "cotton")
				T.eq(data.money, cotton.reward, "이상한 띠 " .. tostring(junk) .. " → 배율 1")
			end
			-- 띠가 바뀐 바로 다음 치기: 개발 명령 /belt 로 바꾸고 바로 침
			local p, _, data = join(H, 1700, { power = 1e60 }, { mp.x, mp.y + 3, mp.z })
			H.S.Break.hit(p, "cotton")
			local first = data.money
			H.S.Dev.handle(p, "/belt 22")
			H.teleport(p, mp.x, mp.y + 3 * H.S.Size.bodyScale(p), mp.z)
			H.S.Break.hit(p, "cotton")
			T.eq(data.money - first, cotton.reward * 200, "바뀐 띠 배율 ×200")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"[D-7] sim 과 서버가 같은 말을 함: sim 이 심사·대결을 이긴 21번의 힘을 그대로 가진 플레이어가 서버에서 (손 0.25초) 첫 도전에 이김 · 그 힘의 0.3배는 가장 빠른 손(0.2초)으로도 못 이김 · 힘 0 은 못 이김",
		function()
			-- sim 이 21번 이긴 때의 힘 (ExamRules 를 감싸서 이긴 상태의 피해를 적음)
			local m = pure()
			local seen = {}
			local real = m.ExamRules
			m.ExamRules = setmetatable({
				examHit = function(state, damage, now)
					local a, b = real.examHit(state, damage, now)
					if state.finished and state.phase == "pass" then
						seen[state.belt] = damage
					end
					return a, b
				end,
				duelHit = function(state, damage, now)
					local a, b = real.duelHit(state, damage, now)
					if state.finished and state.phase == "win" then
						seen[state.belt] = damage
					end
					return a, b
				end,
			}, { __index = real })
			SimPlayer.run(m)
			local H = setup()
			local ML = H.MapLayout
			local lines = {}
			local function attempt(belt, power, interval, uid)
				local data0 = { version = 1, power = power, belt = belt - 1 }
				local p, session, data = joinReal(H, uid, data0)
				local nextBelt = H.Belts.get(belt)
				local world = session.currentWorld
				local at
				if nextBelt.duel then
					local a = ML.duelArena(world)
					at = { a.player.x, a.player.y, a.player.z }
				else
					local a = ML.examPad(world)
					at = { a.x, a.y, a.z }
				end
				H.teleport(p, at[1], at[2] + 3 * H.S.Size.bodyScale(p), at[3])
				H.client(p, if nextBelt.duel then "StartDuel" else "StartExam")
				T.truthy(H.S.Sessions.activity(session) ~= "", "시작 못 함 띠 " .. belt)
				if nextBelt.duel then
					H.advance(3.05)
				end
				for _ = 1, 400 do
					if H.S.Sessions.activity(session) == "" then
						break
					end
					H.client(p, "Hit", if nextBelt.duel then "duel" else "exam")
					H.advance(interval)
				end
				return data.belt == belt
			end
			local uid = 2000
			for belt = 2, 22 do
				local power = seen[belt]
				T.truthy(power and power > 0, "sim 이 띠 " .. belt .. " 를 이긴 기록이 없음")
				uid += 3
				local won = attempt(belt, power, 0.25, uid)
				T.truthy(
					won,
					string.format(
						"띠 %d: sim 의 힘 %s 로 서버에서 못 이김",
						belt,
						H.shared("Format").number(power)
					)
				)
				T.falsy(attempt(belt, power * 0.3, 0.2, uid + 1), string.format("띠 %d: 힘 0.3배로 이김", belt))
				T.falsy(attempt(belt, 0, 0.2, uid + 2), string.format("띠 %d: 힘 0 으로 이김", belt))
				table.insert(
					lines,
					string.format(
						"%d:%s/%.2f",
						belt,
						H.shared("Format").number(power),
						power / H.Belts.get(belt).needPower
					)
				)
			end
			print("  (띠:sim 이 이긴 힘/추천 힘 비율 — " .. table.concat(lines, " ") .. ")")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite(
		"holes_v3 E: 경제 — 아령 값 순서 · 사는 속도 한도 · sim 을 흔들어도 목표 안 (손 최대 속도 · 걷기 없이 · 단계 길이)"
	)
	------------------------------------------------------------------

	T.test(
		"[E-1] 아령 60개: 값 · 힘/번 · 무게가 앞보다 늘기만 함 (싼 뒤 아령 없음) · 순서대로만 삼 · 사는 속도 한도 (한 순간 1000번 → 3개, 10초 연타 → 3 + 초당 2) · 돈 정확히 값만큼, 모자라면 안 삼 · 돈이 음수가 되는 길 없음",
		function()
			local H = setup()
			local D = H.Dumbbells
			T.eq(#D.list, 60)
			T.eq(D.list[1].price, 0, "1번은 처음부터")
			for i = 2, #D.list do
				T.truthy(
					D.list[i].price > D.list[i - 1].price,
					string.format("아령 %d 값이 앞보다 싸거나 같음", i)
				)
				T.truthy(D.list[i].powerPerRep > D.list[i - 1].powerPerRep, string.format("아령 %d 힘/번", i))
				T.truthy(D.list[i].weightKg > D.list[i - 1].weightKg, string.format("아령 %d 무게", i))
			end
			-- 사장님 숫자: 3kg 42 · 힘/번 1 · 3 · 10 · 25 · 100
			T.eq(D.list[2].price, 42)
			for i, want in { 1, 3, 10, 25, 100 } do
				T.eq(D.list[i].powerPerRep, want, "힘/번 " .. i)
			end
			-- 한 순간 1000번 (돈은 충분): 속도 제한 덤 3개만
			local p, _, data = join(H, 10, { money = 1e60 })
			for _ = 1, 1000 do
				H.client(p, "BuyDumbbell")
			end
			T.eq(data.dumbbellLevel, 4, "덤 3번 → 레벨 4")
			-- 10초 동안 0.05초마다: 3 + 초당 2 = 최대 23번 (이미 3번 썼으니 레벨 ≤ 4 + 20)
			for _ = 1, 200 do
				H.client(p, "BuyDumbbell")
				H.advance(0.05)
			end
			T.truthy(
				data.dumbbellLevel <= 4 + 21 and data.dumbbellLevel >= 4 + 15,
				"10초 연타 레벨 " .. data.dumbbellLevel
			)
			-- 값만큼만 빠짐: 돈이 딱 3개 값 → 3개 사고 돈 0 · 하나 모자라면 2개 사고 남은 돈 그대로
			local exact = D.list[2].price + D.list[3].price + D.list[4].price
			local q, _, qd = join(H, 11, { money = exact })
			for _ = 1, 20 do
				H.client(q, "BuyDumbbell")
				H.advance(0.6)
			end
			T.eq(qd.dumbbellLevel, 4)
			T.eq(qd.money, 0, "딱 값만큼 빠짐")
			local r, _, rd = join(H, 12, { money = exact - 1 })
			for _ = 1, 20 do
				H.client(r, "BuyDumbbell")
				H.advance(0.6)
			end
			T.eq(rd.dumbbellLevel, 3, "1 모자라면 마지막 하나는 못 삼")
			T.eq(rd.money, D.list[4].price - 1, "남은 돈")
			-- 순서: 레벨 1 에서 한 번에 한 칸 (돈이 60개 값 전부보다 많아도 3 칸 덤)
			T.truthy(H.hasNotify(r, "error", "돈 부족"))
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	-- SimPlayer.SIM 상수를 잠깐 바꿔 돌리고 되돌림. 월드 끝 3개 + 그랜드 마스터를 돌려줌
	local function runSim(m, changes, economy)
		local saved = {}
		for k, v in changes do
			saved[k] = SimPlayer.SIM[k]
			SimPlayer.SIM[k] = v
		end
		local model = m
		if economy then
			model = table.clone(m)
			model.Economy = economy
		end
		local ok, final, log = pcall(SimPlayer.run, model)
		for k, v in saved do
			SimPlayer.SIM[k] = v
		end
		assert(ok, final)
		return {
			ends = { log.worldOpen[2], log.worldOpen[3], log.belt[m.Belts.COUNT] },
			grand = m.Progression.isGrandMaster(final.belt),
			log = log,
		}
	end

	local baseCache = nil
	local function baseSim(m)
		if not baseCache then
			baseCache = runSim(m, {})
		end
		return baseCache
	end

	T.test(
		"[E-2] 틀린 전략 · 치트 9가지 (손 최대 속도 · 걷기 0초 · 바꾸는 시간 0 · 단계 길이 · 자동 클릭 매크로 · 합친 것) 가 sim 의 월드 끝 하한 (28분 · 1:21 · 2:27) 아래로 못 내려감 (순간이동 치트까지 합친 최악만 3% 안): 걷기 없이 한 자리에서 캠핑해도 · 순간이동 치트 (걷기 ×1,000,000) 도",
		function()
			local m = pure()
			local base = baseSim(m)
			T.truthy(base.grand)
			local bands = SimPlayer.WORLD_END
			local macro = { TICK = 0.203, TRAIN_BLOCK = 31, HIT_BLOCK = 33 } -- 서버 한도(0.2초)에 딱 붙은 자동 클릭 · 임의 탐색에서 가장 빨랐던 단계 길이
			local variants = {
				{ "손 0.2초 (서버 한도 초당 5번)", { TICK = 0.2 } },
				{ "걷기 0초 (순간이동 치트)", { WALK_FACTOR = 1e6 } },
				{ "걷기 3배 (속도 치트)", { WALK_FACTOR = 3 } },
				{ "바꾸는 시간 0", { SWITCH = 0 } },
				{ "단계 30초/30초", { TRAIN_BLOCK = 30, HIT_BLOCK = 30 } },
				{ "자동 클릭 매크로 (0.203초 · 31/33초 · 걷기 정상)", macro },
				{
					"전부 합침: 0.2초 · 걷기 0 · 바꾸기 0 · 30/30",
					{ TICK = 0.2, WALK_FACTOR = 1e6, SWITCH = 0, TRAIN_BLOCK = 30, HIT_BLOCK = 30 },
				},
				{
					"전부 합침: 0.23초 · 걷기 0 · 바꾸기 0 · 10/10",
					{ TICK = 0.23, WALK_FACTOR = 1e6, SWITCH = 0, TRAIN_BLOCK = 10, HIT_BLOCK = 10 },
				},
			}
			local fastest = { 1e9, 1e9, 1e9 }
			for _, v in variants do
				local r = runSim(m, v[2])
				T.truthy(r.grand, v[1] .. " 끝까지 못 감")
				print(
					string.format(
						"  (%s: 월드 끝 %s · %s · %s)",
						v[1],
						mmss(r.ends[1]),
						mmss(r.ends[2]),
						mmss(r.ends[3])
					)
				)
				for w = 1, 3 do
					T.truthy(
						r.ends[w] >= bands[w][1],
						string.format(
							"%s: 월드 %d 끝 %s 이 하한 %s 아래",
							v[1],
							w,
							mmss(r.ends[w]),
							mmss(bands[w][1])
						)
					)
					fastest[w] = math.min(fastest[w], r.ends[w])
				end
			end
			-- 여유: 가장 빠른 것이 하한에서 최소 2% 위 (여유가 더 얇아지면 알림) — 월드 2·3 은 자동 클릭 매크로 하나로 3.5% 까지 내려옴
			for w = 1, 3 do
				T.truthy(
					fastest[w] >= bands[w][1] * 1.02,
					string.format(
						"월드 %d: 가장 빠른 것 %s 가 하한 %s 의 2%% 안",
						w,
						mmss(fastest[w]),
						mmss(bands[w][1])
					)
				)
			end
			-- 최악 (자동 클릭 + 걷기 0 + 바꾸기 0): 하한을 살짝 (1% 안쪽) 밑돌 수 있음 — 3% 보다 많이 밑돌면 안 됨
			local worst = runSim(m, { TICK = 0.203, TRAIN_BLOCK = 31, HIT_BLOCK = 33, SWITCH = 0, WALK_FACTOR = 1e6 })
			print(
				string.format(
					"  (최악 — 자동 클릭 + 순간이동 + 바꾸기 0: %s · %s · %s)",
					mmss(worst.ends[1]),
					mmss(worst.ends[2]),
					mmss(worst.ends[3])
				)
			)
			for w = 1, 3 do
				T.truthy(
					worst.ends[w] >= bands[w][1] * 0.97,
					string.format(
						"최악 월드 %d 끝 %s 이 하한 %s 보다 3%% 넘게 아래",
						w,
						mmss(worst.ends[w]),
						mmss(bands[w][1])
					)
				)
			end
			print(
				string.format(
					"  (기준 %s · %s · %s / 가장 빠른 것 %s · %s · %s / 하한 %s · %s · %s)",
					mmss(base.ends[1]),
					mmss(base.ends[2]),
					mmss(base.ends[3]),
					mmss(fastest[1]),
					mmss(fastest[2]),
					mmss(fastest[3]),
					mmss(bands[1][1]),
					mmss(bands[2][1]),
					mmss(bands[3][1])
				)
			)
		end
	)

	T.test(
		"[E-3] 두 손가락 (들기 + 치기 동시, 서버 한도 각각 초당 5번 = sim 의 2.5배) 과 로벅스 힘 배수 (2배 · 2048배): 그래도 띠는 1 → 22 순서대로 · 월드 2·3 은 띠 7·14 뒤에만 · 두 손가락은 기준의 1/2.6 보다 안 빠름 (설계서가 허용한 쪽) · 출력: 패스가 게임을 얼마나 줄이나",
		function()
			local m = pure()
			local base = baseSim(m)
			local two = runSim(m, { TICK = 0.27 / 2.5 })
			print(
				string.format(
					"  (두 손가락 ×2.5: %s · %s · %s)",
					mmss(two.ends[1]),
					mmss(two.ends[2]),
					mmss(two.ends[3])
				)
			)
			T.truthy(two.grand)
			T.truthy(two.ends[3] >= base.ends[3] / 2.6, "두 손가락 월드 3 끝 " .. mmss(two.ends[3]))
			for _, boost in { 2, 2048 } do
				local boosted = {
					trainGain = function(level, _b)
						return m.Economy.trainGain(level, boost)
					end,
					hitDamage = function(power, _b)
						return m.Economy.hitDamage(power, boost)
					end,
				}
				local r = runSim(m, {}, setmetatable(boosted, { __index = m.Economy }))
				T.truthy(r.grand, "배수 " .. boost .. " 끝까지")
				print(
					string.format(
						"  (힘 배수 %d배: 월드 끝 %s · %s · %s — 기준 %s)",
						boost,
						mmss(r.ends[1]),
						mmss(r.ends[2]),
						mmss(r.ends[3]),
						mmss(base.ends[3])
					)
				)
				-- 순서: 띠는 1 칸씩 (log.belt 시각이 띠 순서대로 늘어남), 월드는 대결 띠 뒤에만
				local last = 0
				for b = 2, m.Belts.COUNT do
					T.truthy(
						r.log.belt[b] ~= nil and r.log.belt[b] > last,
						string.format("배수 %d: 띠 %d 가 앞 띠보다 먼저", boost, b)
					)
					last = r.log.belt[b]
				end
				T.eq(r.ends[1], r.log.belt[7], "월드 2 는 띠 7 에서")
				T.eq(r.ends[2], r.log.belt[14], "월드 3 은 띠 14 에서")
				T.truthy(r.ends[3] < base.ends[3], "배수가 게임을 줄임 (빨라질 뿐)")
			end
		end
	)

	------------------------------------------------------------------
	T.suite(
		"holes_v3 F: 옛 가정 찾기 — 12띠 · 월드마다 4개 · 2000 간격 · 걷기 16 이 코드·글에 남아 있나"
	)
	------------------------------------------------------------------

	-- src 의 모든 줄을 (파일 이름, 줄 번호, 줄 글) 로 훑음
	local function eachSourceLine(visit)
		local function scan(dir)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.sub(name, -5) == ".luau" then
					local n = 0
					for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
						n += 1
						visit(name, n, line)
					end
				end
			end
		end
		scan(GAME_DIR .. "/src")
	end

	T.test(
		"[F-1] 코드 (주석 빼고): 띠 개수 12 · 월드마다 4개 (index % 4 · / 4) · 월드 간격 2000 · 걷기 16 을 가정한 줄이 없음 — 월드 · 대결 여부는 Belts 표에서, 거리는 MapLayout 에서, 걷기는 Sizes 에서 읽음",
		function()
			-- 옛 가정을 알아보는 줄 (옛날 줄 표본으로 먼저 시험: 잡아야 할 것은 잡고, 지금 코드 모양은 안 잡음)
			local STALE_CODE = {
				"index%s*%%%s*4",
				"index%s*/%s*4",
				"math%.ceil%([%w_%.]+%s*/%s*4%)",
				"[Bb]elts%.COUNT%s*==%s*12",
				"COUNT%s*[<>=~]=?%s*12%f[%D]",
				"==%s*12%f[%D]",
				"%*%s*2000%f[%D]",
				"2000%s*%*",
				"WalkSpeed%s*=%s*16",
				"[Ww]alkSpeed%(%s*16",
			}
			local function staleCode(code)
				for _, pattern in STALE_CODE do
					if string.find(code, pattern) then
						return true
					end
				end
				return false
			end
			for _, bad in
				{
					"local duel = index % 4 == 0",
					"world = math.ceil(index / 4),",
					"if Belts.COUNT == 12 then",
					"if #list == 12 then",
					"local x = (world - 1) * 2000",
					"local x = 2000 * (world - 1)",
					"humanoid.WalkSpeed = 16",
					"local speed = Sizes.walkSpeed(16)",
				}
			do
				T.truthy(staleCode(bad), "옛 가정 표본을 못 알아봄: " .. bad)
			end
			for _, good in
				{
					"local duel = row.duel == true",
					"humanoid.WalkSpeed = Sizes.walkSpeed(scale)",
					"mult = 12,",
					"local x = MapLayout.ORIGIN_X[world]",
					"Ui.corner(12).Parent = top",
					"Build.PART_LIMIT = 2000",
					"if index == Belts.COUNT then",
				}
			do
				T.falsy(staleCode(good), "지금 코드 표본을 옛 가정으로 봄: " .. good)
			end
			local offenders = {}
			eachSourceLine(function(name, n, line)
				local code = string.gsub(line, "%-%-.*$", "")
				if string.find(code, "Raycast", 1, true) then
					return -- 화면 클릭 광선 길이 (월드 크기와 상관없음)
				end
				if staleCode(code) then
					table.insert(offenders, string.format("%s:%d %s", name, n, string.gsub(line, "^%s+", "")))
				end
			end)
			T.eq(#offenders, 0, table.concat(offenders, " | "))
			-- 월드 원점 간격 상수 WORLD_SPACING 은 안 쓰임 (원점은 ORIGIN_X 가 기준 — 월드 3 은 월드 2 에서 20000 떨어져 있어 한 간격 × 월드 번호로는 안 맞음)
			local users = {}
			eachSourceLine(function(name, n, line)
				if string.find(line, "WORLD_SPACING", 1, true) and name ~= "MapLayout.luau" then
					table.insert(users, name .. ":" .. n)
				end
			end)
			T.eq(#users, 0, "WORLD_SPACING 을 쓰는 곳: " .. table.concat(users, ", "))
			-- 월드 원점이 서로 월드 배율을 넣은 땅 크기보다 멀리 (Sizes 에서 읽음)
			local ML = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
			local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
			for w = 1, 2 do
				local a, b = ML.worldRect(w), ML.worldRect(w + 1)
				T.truthy(b.x0 - a.x1 > 5000, string.format("월드 %d ~ %d 땅 사이 %.0f", w, w + 1, b.x0 - a.x1))
				T.truthy(Sizes.worldScale(w + 1) > Sizes.worldScale(w))
			end
		end
	)

	T.test(
		"[F-2] C-4 고침: 옛 가정이 남은 글 (주석) 없음 — 12개 띠 · 월드의 4번째 띠 · 9단 띠 = 그랜드 마스터 · 옛 추천 힘 숫자 · 반복 0.25초 · 안 쓰는 WORLD_SPACING 상수도 지움",
		function()
			local ML = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
			T.eq(ML.WORLD_SPACING, nil, "WORLD_SPACING 지움 (원점은 ORIGIN_X)")
			local offenders = {}
			eachSourceLine(function(name, n, line)
				-- 일부러 옛날을 말하는 글 (옛 12개 표 · '4개씩 가정 없음') 은 통과
				if
					string.find(line, "옛 12", 1, true)
					or string.find(line, "가정 없음", 1, true)
					or string.find(line, "가정하지", 1, true)
				then
					return
				end
				for _, phrase in
					{
						"12개 띠",
						"띠 12개",
						"(1~12",
						"그 월드 4번째",
						"월드의 4번째",
						"4번째 띠",
						"월드마다 4개",
						"9단 띠(그랜드",
						"9단 띠면",
						"1.67e43",
						"3.68e38",
						"누르고 있으면 0.25초마다",
					}
				do
					if string.find(line, phrase, 1, true) then
						table.insert(offenders, string.format("%s:%d [%s]", name, n, phrase))
					end
				end
			end)
			T.eq(#offenders, 0, table.concat(offenders, " | "))
		end
	)
end
