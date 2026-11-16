--!nocheck
--[[
	size_service — 수석 SizeService (결정 13·14번) + 크기에 맞춘 서버 거리 판정 + 문 Travel 연타 (결정 15번). 진짜 서버 코드 + ServerHarness.
	  A 힘이 바뀌는 모든 길에서 BodyScale · Muscle · WalkSpeed · JumpHeight 가 따라옴 (들기 · /power · /reset · 불러오기 · 새 캐릭터)
	  B 바뀔 때만 씀 (들기 초당 5번) · 맨 힘만 (PowerBoost 안 곱함)
	  C 보안 (holes 방식): 클라가 몸 크기를 바꿀 길 없음 · 이상한 힘에도 범위 안 · Attribute 를 누가 바꿔도 서버 판정은 data 로
	  D 거리 판정 × 월드 배율 · 큰 몸 (치기 여유 · 심사대 · 매트 · 스폰 높이)
	  E Travel 을 빨리 여러 번 (문에 닿을 때마다 클라가 보냄): 두 번 순간이동 없음 · 알림 도배 없음 · warn 0
]]
return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
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
		H.Dumbbells = H.shared("Data/Dumbbells")
		H.Config = H.shared("Data/Config")
		H.Remotes = H.shared("Remotes")
		return H
	end

	local function at(x, y, z)
		return { x, y, z }
	end

	-- 로그인 + 캐릭터 (PlayerLifecycle 없이 — 서비스 테스트처럼). 몸 크기는 Wallet.sync 로 한 번 맞춤 (접속 때 Attributes.sync 와 같음)
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

	-- 서버가 정해야 하는 값 (맨 힘 data.power 에서)
	local function expected(H, power)
		local scale = H.Sizes.quantize(H.Sizes.playerScale(power))
		local muscle = math.floor(H.Sizes.muscle(power) / 0.05 + 1e-9) * 0.05
		return scale, muscle
	end

	local function assertSize(H, p, data, label)
		local scale, muscle = expected(H, data.power)
		T.eq(p:GetAttribute("BodyScale"), scale, label .. " BodyScale")
		T.near(p:GetAttribute("Muscle"), muscle, 1e-9, label .. " Muscle")
		local hum = p.Character and p.Character.humanoid
		if hum then
			T.eq(hum.WalkSpeed, H.Sizes.walkSpeed(scale), label .. " WalkSpeed")
			T.eq(hum.JumpHeight, H.Sizes.jumpHeight(scale), label .. " JumpHeight")
			T.eq(hum.UseJumpPower, false, label .. " UseJumpPower")
		end
	end

	-- 플레이어 Attribute 쓰기 횟수 세기
	local function countAttrWrites(p)
		local counts = {}
		local original = p.SetAttribute
		p.SetAttribute = function(self, key, value)
			counts[key] = (counts[key] or 0) + 1
			return original(self, key, value)
		end
		return counts
	end

	-- Humanoid 칸 쓰기 횟수 세기 (같은 표에 메타테이블을 걸어 WalkSpeed · JumpHeight · UseJumpPower 를 가로챔)
	local function countHumanoidWrites(p)
		local hum = p.Character.humanoid
		local backing = {}
		local counts = { WalkSpeed = 0, JumpHeight = 0, UseJumpPower = 0 }
		for key in counts do
			backing[key] = rawget(hum, key)
			rawset(hum, key, nil)
		end
		setmetatable(hum, {
			__index = backing,
			__newindex = function(_, key, value)
				if counts[key] ~= nil then
					counts[key] += 1
					backing[key] = value
				else
					rawset(hum, key, value)
				end
			end,
		})
		return counts
	end

	------------------------------------------------------------------
	T.suite("size_service A: 힘이 바뀌는 모든 길 → BodyScale · Muscle · 걷기 · 점프")
	------------------------------------------------------------------

	T.test(
		"들기 (Remote Train · TrainService.train): 힘이 오를 때마다 몸 크기가 맨 힘을 따라감",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = 0, dumbbellLevel = 30 })
			assertSize(H, p, data, "시작 (힘 0)")
			T.eq(p:GetAttribute("BodyScale"), 1)
			T.eq(p.Character.humanoid.WalkSpeed, 32, "걷기 32 (지금 16 의 2배)")
			local seen = {}
			for i = 1, 40 do
				H.client(p, "Train")
				H.advance(0.25)
				assertSize(H, p, data, "들기 " .. i)
				seen[p:GetAttribute("BodyScale")] = true
			end
			T.truthy(data.power > 0)
			T.truthy(p:GetAttribute("BodyScale") > 1, "몸이 커짐 " .. p:GetAttribute("BodyScale"))
			T.truthy(H.S.Train.train(p) > 0)
			assertSize(H, p, data, "TrainService.train")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test("개발 명령 /power · /reset · Wallet.set · Wallet.addPower: 몸 크기가 바로 따라감", function()
		local H = setup()
		local p, _, data = join(H, 1, { power = 0 })
		for _, n in { "1e9", "1e20", "6.14e39", "1e60", "5", "0" } do
			T.truthy(H.S.Dev.handle(p, "/power " .. n), n)
			assertSize(H, p, data, "/power " .. n)
		end
		H.S.Dev.handle(p, "/power 1e30")
		T.truthy(p:GetAttribute("BodyScale") > 5)
		T.truthy(H.S.Dev.handle(p, "/reset"))
		T.eq(data.power, 0)
		assertSize(H, p, data, "/reset")
		T.eq(p:GetAttribute("BodyScale"), 1, "/reset → 몸 1")
		T.eq(p:GetAttribute("Muscle"), 0)
		H.S.Wallet.set(p, 1e25, nil)
		assertSize(H, p, data, "Wallet.set")
		H.S.Wallet.addPower(p, 1e35)
		assertSize(H, p, data, "Wallet.addPower")
		H.S.Wallet.set(p, 0 / 0, nil) -- NaN → 0 (Economy.clampPower)
		assertSize(H, p, data, "Wallet.set NaN")
		T.eq(p:GetAttribute("BodyScale"), 1)
		T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
		H.uninstall()
	end)

	T.test(
		"불러오기 (PlayerLifecycle.onPlayerAdded + DataStore): 저장된 힘으로 BodyScale · Muscle · 걷기 · 스폰 높이 · 다시 태어나도 그대로",
		function()
			local H = setup()
			local power = 3e33
			H.store.data["player_7"] = { data = { version = 1, power = power, belt = 16, world = 3 } }
			local p = H.newPlayer(7)
			H.spawn(p, 0, 3, 0) -- 불러오기 전에 캐릭터가 먼저 생김 (보통)
			T.eq(p.Character.humanoid.WalkSpeed, 16, "아직 연결 전 (기본 16)")
			H.run(function()
				H.S.Life.onPlayerAdded(p)
				return true
			end)
			H.advance(0.5)
			local _, data = H.S.Sessions.getLoaded(p)
			T.truthy(data, "불러옴")
			T.eq(data.power, power)
			assertSize(H, p, data, "불러오기")
			local scale = p:GetAttribute("BodyScale")
			T.truthy(scale > 8, "큰 몸 " .. scale)
			-- 스폰 높이: 뿌리 = 스폰 바닥 + 3 × max(몸, 월드 배율)
			local spot = H.MapLayout.spawn(3)
			local lift = 3 * math.max(scale, H.Sizes.worldScale(3))
			T.near(p.Character.root.Position.Y, spot.y + lift, 1e-6, "스폰 높이")
			-- 죽었다 다시 태어남: 새 Humanoid 는 기본값(16) → CharacterAdded 로 바로 맞춤
			H.spawn(p, 0, 3, 0)
			assertSize(H, p, data, "새 캐릭터 (바로)")
			p.Character.humanoid.WalkSpeed = 16 -- 다른 CharacterAdded 처리가 덮어썼다고 가정
			H.advance(0.1)
			assertSize(H, p, data, "새 캐릭터 (미룬 한 번 더)")
			T.near(p.Character.root.Position.Y, spot.y + lift, 1e-6, "다시 태어나도 스폰 높이")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"힘을 바꾸는 서버 코드는 Wallet(과 저장 보정 DataSchema)뿐 — 다른 파일이 data.power 를 직접 쓰면 몸 크기가 안 따라옴",
		function()
			local offenders = {}
			local function scan(dir)
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						scan(path)
					elseif string.sub(name, -5) == ".luau" then
						local source = fs.readFile(path)
						for line in string.gmatch(source, "[^\n]+") do
							local code = string.gsub(line, "%-%-.*$", "")
							if
								string.find(code, "%.power%s*=[^=]")
								or string.find(code, "%.power%s*[%+%-%*/]=")
								or string.find(code, '%[%s*"power"%s*%]%s*=[^=]')
							then
								if name ~= "Wallet.luau" and name ~= "DataSchema.luau" then
									table.insert(offenders, name .. ": " .. line)
								end
							end
						end
					end
				end
			end
			scan(GAME_DIR .. "/src/server")
			T.eq(#offenders, 0, table.concat(offenders, " | "))
			-- Wallet 의 모든 길이 sync 를 부르고, sync 가 SizeService.refresh 를 부름
			local wallet = fs.readFile(GAME_DIR .. "/src/server/Services/Wallet.luau")
			T.truthy(string.find(wallet, "SizeService.refresh(player)", 1, true), "Wallet.sync → SizeService.refresh")
		end
	)

	------------------------------------------------------------------
	T.suite("size_service B: 바뀔 때만 씀 · 맨 힘만")
	------------------------------------------------------------------

	T.test(
		"같은 단계 안에서 들기 300번 · 치기 300번: BodyScale · Muscle · Humanoid 쓰기 0번 · 단계를 넘으면 1번씩",
		function()
			local H = setup()
			local mp = H.MapLayout.matPoint("cotton")
			local p, _, data = join(H, 1, { power = 1e20, dumbbellLevel = 1 }, at(mp.x, mp.y + 3, mp.z))
			assertSize(H, p, data, "시작")
			local attrs = countAttrWrites(p)
			local hum = countHumanoidWrites(p)
			for _ = 1, 300 do
				H.client(p, "Train") -- +1 힘 (1e20 에서는 몸이 안 바뀜)
				H.client(p, "Hit", "cotton")
				H.advance(0.2)
			end
			T.truthy(data.money > 0, "치기도 됨")
			T.eq(attrs.BodyScale or 0, 0, "BodyScale 다시 안 씀")
			T.eq(attrs.Muscle or 0, 0, "Muscle 다시 안 씀")
			T.eq(hum.WalkSpeed, 0, "WalkSpeed 다시 안 씀")
			T.eq(hum.JumpHeight, 0)
			T.eq(hum.UseJumpPower, 0)
			T.truthy((attrs.Power or 0) > 0, "Power 는 씀 (Wallet)")
			-- 단계를 넘으면 한 번씩
			H.S.Wallet.set(p, 1e30, nil)
			T.eq(attrs.BodyScale, 1)
			T.eq(hum.WalkSpeed, 1)
			T.eq(hum.JumpHeight, 1)
			T.eq(hum.UseJumpPower, 0, "UseJumpPower 는 이미 false")
			assertSize(H, p, data, "1e30")
			H.uninstall()
		end
	)

	T.test(
		"몸 크기는 맨 힘으로만 — 2048배 패스를 사도 몸은 그대로 (치는 힘만 2048배)",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = 1e10 })
			local before = p:GetAttribute("BodyScale")
			H.S.Product.grant(p, "power_2")
			data.powerBoost = 2048
			H.S.Wallet.sync(p)
			T.eq(p:GetAttribute("BodyScale"), before, "PowerBoost 가 몸을 안 키움")
			T.eq(p:GetAttribute("BodyScale"), expected(H, data.power))
			T.truthy(expected(H, data.power * 2048) > before, "(곱했다면 더 컸을 것)")
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("size_service C: 보안 — 몸 크기는 서버만")
	------------------------------------------------------------------

	T.test(
		"클라 → 서버 Remote 에 몸 크기를 바꾸는 것이 없음 (이름) · 모든 Remote 에 쓰레기 2,000번 → BodyScale · Muscle · 걷기 그대로",
		function()
			local H = setup()
			for name in H.Remotes.ToServer do
				local lower = string.lower(name)
				for _, bad in { "size", "scale", "muscle", "body", "speed", "walk", "jump" } do
					T.falsy(string.find(lower, bad, 1, true), "Remote " .. name .. " 에 " .. bad)
				end
			end
			local p, _, data =
				join(H, 1, { power = 1e15, money = 1e60, world = 3, belt = H.Belts.COUNT }, at(H.spawnSpot(1)))
			local scale0, muscle0 = p:GetAttribute("BodyScale"), p:GetAttribute("Muscle")
			local walk0 = p.Character.humanoid.WalkSpeed
			local rng = T.rng(31)
			local junk = {
				"BodyScale",
				"Muscle",
				99,
				-1,
				0 / 0,
				math.huge,
				{ BodyScale = 99 },
				{ Muscle = 1 },
				true,
				"WalkSpeed",
				1e308,
			}
			local names = {}
			for name in H.Remotes.ToServer do
				if name ~= "Train" and name ~= "BuyDumbbell" then -- (스폰은 매트 밖 — 들기는 0. 아령 사기는 힘을 안 바꿈)
					table.insert(names, name)
				end
			end
			table.insert(names, "Train")
			for i = 1, 2000 do
				local name = names[1 + math.floor(rng() * #names)]
				H.client(p, name, junk[1 + math.floor(rng() * #junk)], junk[1 + math.floor(rng() * #junk)])
				if i % 50 == 0 then
					H.advance(1)
					H.teleport(p, H.spawnSpot(1)) -- Travel 이 옮겨도 다시 스폰(매트 밖)으로
				end
			end
			T.eq(data.power, 1e15, "힘 그대로 (매트 밖)")
			T.eq(p:GetAttribute("BodyScale"), scale0)
			T.eq(p:GetAttribute("Muscle"), muscle0)
			T.eq(p.Character.humanoid.WalkSpeed, walk0)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"BodyScale Attribute 가 망가져도 (999 · NaN · 글자) 서버 판정은 data.power 로 · 다음 Wallet.sync 에 바로 고침",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = 0 }, at(H.targetSpot("cotton")))
			local slack0 = H.S.Break.slackFor(p, "cotton")
			for _, bad in { 999, 0 / 0, "big", -5, 1e308 } do
				p:SetAttribute("BodyScale", bad)
				p:SetAttribute("Muscle", bad)
				T.eq(H.S.Size.bodyScale(p), 1, "서버 몸 배율은 data 에서")
				T.eq(H.S.Break.slackFor(p, "cotton"), slack0, "치기 여유가 안 늘어남")
				T.eq(H.S.World.spawnLift(p, 1), 3, "스폰 높이도 그대로")
				H.S.Wallet.sync(p)
				assertSize(H, p, data, "고침 " .. tostring(bad))
			end
			H.uninstall()
		end
	)

	T.test(
		"SizeService 밖의 서버 코드는 BodyScale · Muscle 을 안 씀 (선임 PlayerVisualService 는 읽기만)",
		function()
			local writers = {}
			local function scan(dir)
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						scan(path)
					elseif string.sub(name, -5) == ".luau" and name ~= "SizeService.luau" then
						local source = fs.readFile(path)
						for line in string.gmatch(source, "[^\n]+") do
							-- 플레이어 Attribute 이름 그대로 ("BodyScale" · Attr.BodyScale · Tags.PlayerAttributes.Muscle …).
							-- 캐릭터에 다른 이름(예: "VisualMuscle")으로 쓰는 것은 겉모습용이라 괜찮음
							local hit = false
							for _, key in { "BodyScale", "Muscle" } do
								if
									string.find(line, 'SetAttribute%(%s*"' .. key .. '"%s*,')
									or string.find(line, "SetAttribute%(%s*[%w_%.]*%." .. key .. "%s*,")
								then
									hit = true
								end
							end
							if hit then
								table.insert(writers, name .. ": " .. line)
							end
						end
					end
				end
			end
			scan(GAME_DIR .. "/src/server")
			T.eq(#writers, 0, table.concat(writers, " | "))
		end
	)

	T.test(
		"이상한 힘 (NaN · ±무한 · 음수 · 1e308 · 1e60): BodyScale 1 ~ MAX · Muscle 0 ~ 1 · 걷기 유한 · warn 0",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = 0 })
			for _, v in { 0 / 0, math.huge, -math.huge, -1, 1e308, 1e60, 1e-300, 0 } do
				data.power = v -- 저장 데이터가 망가졌다고 가정 (보통은 Economy 가 막음)
				local ok, err = pcall(H.S.Wallet.sync, p)
				T.truthy(ok, tostring(err))
				local s, m = p:GetAttribute("BodyScale"), p:GetAttribute("Muscle")
				T.truthy(
					s == s and s >= 1 and s <= H.Sizes.MAX_SCALE,
					"BodyScale " .. tostring(s) .. " @ " .. tostring(v)
				)
				T.truthy(m == m and m >= 0 and m <= 1, "Muscle " .. tostring(m))
				local w = p.Character.humanoid.WalkSpeed
				T.truthy(w == w and w >= 32 and w <= 32 * H.Sizes.MAX_SCALE, "걷기 " .. tostring(w))
				local extra = H.S.Size.bodyExtra(p)
				T.truthy(extra == extra and extra >= 0 and extra < 50, "몸 여유 " .. tostring(extra))
			end
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("size_service D: 거리 판정 × 월드 배율 · 큰 몸")
	------------------------------------------------------------------

	T.test(
		"치기 여유 = 6 × 그 물건 월드 worldScale (+ 몸 여유) · 높이 여유 20 × worldScale",
		function()
			local H = setup()
			local p = join(H, 1, { power = 0, world = 3, belt = H.Belts.COUNT })
			for _, t in H.Targets.list do
				local slack, vertical = H.S.Break.slackFor(p, t.id)
				local ws = H.Sizes.worldScale(t.world)
				T.near(slack, H.Config.HIT_REACH_SLACK * ws, 1e-9, t.id .. " 여유")
				T.near(vertical, 20 * ws, 1e-9, t.id .. " 높이 여유")
			end
			H.S.Wallet.set(p, 1e60, nil)
			local slack = H.S.Break.slackFor(p, "cotton")
			T.near(slack, 6 + 3 * (H.Sizes.MAX_SCALE - 1), 1e-9, "가장 큰 몸은 팔 길이만큼 더")
			T.near(H.S.Exam.radiusFor(H.Config.EXAM_RADIUS, 2), 20 * H.Sizes.worldScale(2), 1e-9)
			T.near(H.S.Exam.radiusFor(H.Config.DUEL_RADIUS, 3), 24 * H.Sizes.worldScale(3), 1e-9)
			T.eq(H.S.Exam.radiusFor(H.Config.EXAM_RADIUS, 1), 20, "월드 1 은 그대로")
			H.uninstall()
		end
	)

	T.test(
		"월드 2 물건: 보통 몸으로 reach + 6 × worldScale − 0.5 에서 깨짐 · + 0.5 밖은 무시",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = 1e60, world = 3, belt = H.Belts.COUNT })
			data.power = 1e60
			local mall = H.MapLayout.targetPosition("mall")
			local reach = H.MapLayout.targetReach("mall")
			local ws = H.Sizes.worldScale(2)
			local slack = H.S.Break.slackFor(p, "mall")
			T.truthy(slack >= 6 * ws, "여유가 월드 배율만큼")
			H.teleport(p, mall.x + reach + slack - 0.5, mall.y + 3, mall.z)
			H.client(p, "Hit", "mall")
			H.advance(0.3)
			T.eq(data.broken.mall, 1, "안쪽")
			H.teleport(p, mall.x + reach + slack + 0.5, mall.y + 3, mall.z)
			H.client(p, "Hit", "mall")
			H.advance(0.3)
			T.eq(data.broken.mall, 1, "바깥쪽")
			H.uninstall()
		end
	)

	T.test(
		"큰 몸 (힘 1e39, 뿌리 높이 3 × 몸 배율) 이 월드 1 에서: 매트 위에서 듦 · 솜을 침 · 심사 시작됨 · 보통 몸이 그 높이 공중이면 안 됨",
		function()
			local H = setup()
			local p, session, data = join(H, 1, { power = 1e39, world = 3, belt = 1, dumbbellLevel = 60 })
			session.currentWorld = 1
			local scale = p:GetAttribute("BodyScale")
			T.truthy(scale > 12, "거인 " .. scale)
			local rootY = 3 * scale -- 몸이 s 배면 뿌리가 바닥 위 약 3s
			local mat = H.MapLayout.trainMats(1)[1]
			H.teleport(p, mat.x, rootY, mat.z)
			T.truthy(H.S.Train.train(p) > 0, "거인도 매트 위에서 듦")
			local cotton = H.MapLayout.targetPosition("cotton")
			H.teleport(p, cotton.x, cotton.y + rootY, cotton.z)
			T.truthy(H.S.Break.hit(p, "cotton"), "거인도 솜을 침")
			local pad = H.MapLayout.examPad(1)
			H.teleport(p, pad.x, pad.y + rootY, pad.z)
			T.truthy(H.S.Exam.startExam(p), "거인도 심사대에서 시작")
			H.S.Exam.cancel(p)
			-- 보통 몸(힘 0)이 같은 높이 공중이면 안 됨
			local q, qs = join(H, 2, { power = 0 })
			qs.currentWorld = 1
			H.teleport(q, mat.x, rootY, mat.z)
			T.eq(H.S.Train.train(q), 0, "보통 몸이 공중에서는 못 듦")
			H.teleport(q, pad.x, pad.y + rootY, pad.z)
			T.falsy(H.S.Exam.startExam(q), "보통 몸이 공중에서는 심사 못 함")
			-- 거인이어도 매트 위에서는 심사 시작 안 됨 (A-2 그대로)
			H.teleport(p, mat.x, rootY, mat.z)
			T.falsy(H.S.Exam.startExam(p), "거인도 매트 위에서는 심사 안 됨")
			T.truthy(data.power > 1e39)
			H.uninstall()
		end
	)

	T.test(
		"스폰·순간이동 높이 = 3 × max(몸 배율, 월드 배율): 보통 몸 월드 1 = 3 · 월드 3 = 3 × worldScale(3) · 가장 큰 몸 = 3 × MAX",
		function()
			local H = setup()
			local p, session, data = join(H, 1, { power = 0, world = 3, belt = H.Belts.COUNT })
			local function rootAbove(world)
				return p.Character.root.Position.Y - H.MapLayout.spawn(world).y
			end
			H.client(p, "Travel", 3)
			T.eq(session.currentWorld, 3)
			T.near(rootAbove(3), 3 * H.Sizes.worldScale(3), 1e-9, "보통 몸 · 월드 3")
			H.advance(2)
			H.client(p, "Travel", 1)
			T.near(rootAbove(1), 3, 1e-9, "보통 몸 · 월드 1")
			H.S.Dev.handle(p, "/power 1e60")
			H.advance(2)
			H.client(p, "Travel", 2)
			T.near(rootAbove(2), 3 * H.Sizes.MAX_SCALE, 1e-9, "가장 큰 몸 · 월드 2")
			H.S.Dev.handle(p, "/reset")
			T.eq(data.power, 0)
			T.near(rootAbove(1), 3, 1e-9, "/reset → 월드 1 보통 높이")
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("size_service E: 문에 닿을 때마다 Travel (결정 15번) — 빨리 여러 번 와도 안전")
	------------------------------------------------------------------

	T.test(
		"같은 순간 Travel(2) 20번 → 순간이동 1번 · Snapshot 1번 · 2초 안에 또 와도 무시 · warn 0",
		function()
			local H = setup()
			local p, session = join(H, 1, { world = 3, belt = H.Belts.COUNT }, at(H.spawnSpot(1)))
			local moves = 0
			local character = p.Character
			local pivot = character.PivotTo
			character.PivotTo = function(self, cf)
				moves += 1
				return pivot(self, cf)
			end
			for _ = 1, 20 do
				H.client(p, "Travel", 2)
			end
			T.eq(session.currentWorld, 2)
			T.eq(moves, 1, "순간이동 한 번")
			T.eq(#H.sent(p, "Snapshot"), 1, "Snapshot 한 번")
			H.advance(1)
			for _ = 1, 5 do
				H.client(p, "Travel", 2)
				H.advance(0.2)
			end
			T.eq(moves, 1, "도착 직후 2초 안에는 또 안 옮김")
			H.advance(3)
			H.client(p, "Travel", 1)
			T.eq(session.currentWorld, 1, "다른 월드 문은 됨")
			T.eq(moves, 2)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"잠긴 월드 문에 10초 동안 0.1초마다 닿음 → 이동 없음 · 잠김 알림 2초에 한 번 (≤ 6) · 심사 중 이동 알림도 2초에 한 번",
		function()
			local H = setup()
			local p, session = join(H, 1, { world = 1, belt = 1, power = 0 }, at(H.spawnSpot(1)))
			for _ = 1, 100 do
				H.client(p, "Travel", 3)
				H.advance(0.1)
			end
			T.eq(session.currentWorld, 1)
			local locked = 0
			for _, n in H.notifications(p) do
				if string.find(n.text, "잠김", 1, true) then
					locked += 1
				end
			end
			T.truthy(locked >= 1 and locked <= 6, "잠김 알림 " .. locked .. "번")
			-- 심사 중
			H.clearSent()
			H.teleport(p, H.examSpot(1))
			H.advance(3)
			H.client(p, "StartExam")
			T.truthy(session.exam, "심사 시작")
			for _ = 1, 50 do
				H.client(p, "Travel", 1)
				H.advance(0.1)
			end
			local busy = 0
			for _, n in H.notifications(p) do
				if string.find(n.text, "이동 불가", 1, true) then
					busy += 1
				end
			end
			T.truthy(busy >= 1 and busy <= 3, "심사 중 알림 " .. busy .. "번")
			T.truthy(session.exam, "Travel 이 심사를 못 끊음")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"월드 1 ↔ 2 ↔ 3 을 무작위로 1,000번 (0~0.3초 간격): 지금 월드 = 마지막으로 옮겨진 월드 · 스폰 자리 · warn 0",
		function()
			local H = setup()
			local p, session = join(H, 1, { world = 3, belt = H.Belts.COUNT }, at(H.spawnSpot(1)))
			local rng = T.rng(5)
			for _ = 1, 1000 do
				local to = 1 + math.floor(rng() * 3)
				H.client(p, "Travel", if rng() < 0.1 then 0 / 0 else to)
				H.advance(rng() * 0.3)
				T.eq(p:GetAttribute("CurrentWorld"), session.currentWorld)
			end
			H.advance(3)
			local w = session.currentWorld
			local spot = H.MapLayout.spawn(w)
			T.near(p.Character.root.Position.X, spot.x, 1e-6, "스폰 x")
			T.near(p.Character.root.Position.Z, spot.z, 1e-6, "스폰 z")
			T.eq(H.MapLayout.worldAt(p.Character.root.Position), w, "그 월드 땅")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)
end
