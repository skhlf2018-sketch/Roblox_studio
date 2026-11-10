--!nocheck
--[[
	8판 주임 검수 (구멍 찾기) — 수석 800aba5 (떨어진 씨앗 · 둥지 무리 · 구역 21 · 식물 크기/간격 · 러닝머신 · 경비 시간 잡기)
	holes_v8.spec(수석이 쓴 기본 시험)과 겹치지 않게 "진짜 서비스끼리 이어 붙여 본 것"과 "경계·반복·무작위" 위주.
	  A 경비 잡기 (진짜 GuardianService + 진짜 EggService, 21구역 전부) — 2026-11-10: 시간이 아니라 "닿아야만" 잡힘
	  B 떨어진 씨앗 규칙 (2026-11-10: 구역 안 = 바로 둥지 / 밖 5초 뒤 둥지 / 초기화 / 쌓임 상한)
	  C 둥지 무리 · 구역 19~21 · 1~18 좌표가 7판과 같은지
	  D 식물 크기 · 정원 간격 (16등급 × 4크기로 서버 PlaceEgg 18번)
	  E 러닝머신 (가격표 · 터치 신호)
	  F 보안 회귀 (두 사람 무작위 요청 1,000번)
	표 숫자는 코드가 아니라 docs/SEED_GAME_DESIGN.md 9장 33~44번 · 12장 · docs/GAME_DESIGN.md 9-2 를 이 파일에 따로 적어 대조함.
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local S = "ReplicatedStorage/Shared/"
	local V = "ServerScriptService/Server/"
	local Config = Loader.require(S .. "Data/Config")
	local Biomes = Loader.require(S .. "Data/Biomes")
	local Plants = Loader.require(S .. "Data/Plants")
	local Rarities = Loader.require(S .. "Data/Rarities")
	local EggSpawn = Loader.require(S .. "Data/EggSpawn")
	local Upgrades = Loader.require(S .. "Data/Upgrades")
	local Sizes = Loader.require(S .. "Data/Sizes")
	local MapLayout = Loader.require(S .. "Data/MapLayout")
	local EggRules = Loader.require(S .. "EggRules")
	local EggRoll = Loader.require(S .. "EggRoll")
	local SpeedMath = Loader.require(S .. "SpeedMath")
	local GardenRules = Loader.require(S .. "GardenRules")
	local EggPlacement = Loader.require(S .. "EggPlacement")
	local Economy = Loader.require(S .. "Economy")
	local GuardLogic = Loader.require(V .. "Logic/GuardLogic")

	local function inWorld(options, fn)
		local H = ServerHarness.install(Loader, T, options)
		local ok, err = pcall(function()
			H.startNet()
			fn(H)
		end)
		H.uninstall()
		if not ok then
			error(err, 0)
		end
	end

	local function finite(n)
		return typeof(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
	end

	------------------------------------------------------------------
	-- 진짜 EggService + 진짜 GuardianService 세상
	------------------------------------------------------------------
	local function guardWorld(H)
		local w = { H = H }
		w.EggService = H.server("Services/EggService")
		w.EggService.start()
		w.GuardianService = H.server("Services/GuardianService")
		w.GuardianService.start()
		w.SpeedService = H.server("Services/SpeedService")
		H.setPhase("Intermission", 1) -- 초기화: 둥지에 새 씨앗
		H.setPhase("Day", 1)
		return w
	end

	local function newRunner(H, userId, name)
		local p = H.newPlayer(userId, name)
		local session, data = H.login(p)
		session.plotIndex = 1
		H.spawn(p, 0, 3, 0)
		return p, session, data
	end

	-- 그 구역 둥지에 놓인 씨앗 파트 (skip 개 건너뜀)
	local function nestEgg(H, biomeId, skip)
		skip = skip or 0
		for _, part in H.map.folders.Eggs.children do
			if part:GetAttribute("BiomeId") == biomeId and part:GetAttribute("EggState") == "Nest" then
				if skip == 0 then
					return part
				end
				skip -= 1
			end
		end
		return nil
	end

	-- 65·66번 (2026-11-10): 둥지에서 집으면 경비는 빨간 느낌표(Alert)를 띄우고 GUARD_WAKE_SECONDS 뒤에 쫓아옴 — 그 규칙은 services_world 에서 따로 봄.
	-- 이 파일의 시험은 "경비가 깨어난 뒤" 규칙이라, 집자마자 깨어난 것으로 침 (집은 시각을 GUARD_WAKE_SECONDS 앞으로)
	local function pickUp(H, p, part)
		H.teleport(p, part.Position.X, part.Position.Y + 1, part.Position.Z)
		part:FindFirstChild("StealPrompt").Triggered:Fire(p)
		local EggService = H.server("Services/EggService")
		local carried = if EggService.getCarried then EggService.getCarried(p) else nil
		if carried and carried.stolenAt then
			carried.stolenAt -= Config.GUARD_WAKE_SECONDS
		end
	end

	local function guardModel(H, biomeId)
		for _, model in H.map.folders.Guardians.children do
			if model:GetAttribute("BiomeId") == biomeId and not model.destroyed then
				return model
			end
		end
		return nil
	end

	local function humanoidOf(model)
		for _, child in model.children do
			if child.ClassName == "Humanoid" then
				return child
			end
		end
		return nil
	end

	-- 들고 있는 씨앗의 실효 속도(알 무게 반영)를 target 으로 맞춤
	local function setCarrySpeed(w, p, session, data, target)
		data.speed = target / (1 - session.carryPenalty)
		w.SpeedService.refresh(p)
		T.near(session.carrySpeed, target, target * 1e-9 + 1e-9, "들고 있는 속도 맞춤")
	end

	-- 구역 경비 추격 기준 (= 이보다 빨라야 도망)
	local function threshold(biomeId)
		return Biomes.get(biomeId).guardSpeed * Config.GUARD_CHASE_MARGIN
	end

	-- 지금부터 limit 초 안에 Caught 가 오면 걸린 시간, 아니면 nil (0.05초 단위)
	local function timeToCatch(H, p, limit)
		local before = #H.sent(p, "Caught")
		local t = 0
		while t < limit - 1e-9 do
			H.advance(0.05)
			t += 0.05
			if #H.sent(p, "Caught") > before then
				return t
			end
		end
		return nil
	end

	local ALL_ZONES = {}
	for _, b in Biomes.list do
		table.insert(ALL_ZONES, b.id)
	end

	------------------------------------------------------------------
	T.suite("8판 주임 검수 A: 경비 시간 잡기 (진짜 GuardianService + 진짜 EggService)")

	T.test(
		"21구역 전부 (2026-11-10 닿아야 잡힘): 추격 시간(2.5초/1초)이 지나도 멀리 있으면 안 잡힘 · 경비에 닿으면 (도망칠 수 있는 빠른 사람도) 그 틱에 1번만 잡혀 씨앗이 둥지로 · 다음 구역 경계를 넘으면 즉시",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9001, "Timer")
				local settle = Config.RAGDOLL_SECONDS + 3
				for _, id in ALL_ZONES do
					local biome = Biomes.get(id)
					local range = MapLayout.biome(id)
					local thr = threshold(id)
					local home = MapLayout.guardHome(id)
					local function goFar()
						H.teleport(p, 60, 3, range.zMin + 5) -- 경비에게서 아주 먼 곳
					end
					local function touch()
						H.teleport(p, home.x, 3, home.z) -- 경비 바로 위 (거리 0) = 닿음
					end
					-- 닿으면 그 틱(0.3초 안)에 한 번만 잡혀 씨앗이 둥지로
					local function expectCaught(egg, label, caughtBefore)
						local t = timeToCatch(H, p, 0.4)
						T.truthy(
							t ~= nil and t <= 0.3,
							id .. " " .. label .. ": 닿으면 그 틱에 잡힘 " .. tostring(t)
						)
						T.eq(
							egg:GetAttribute("EggState"),
							"Nest",
							id .. " " .. label .. ": 구역 안 잡힘 = 둥지로"
						)
						local list = H.sent(p, "Caught")
						T.eq(#list, caughtBefore + 1, id .. " " .. label .. ": 한 번만")
						T.eq(list[#list][1].cause, "guard")
						T.eq(list[#list][1].eggOutcome, "ReturnToNest")
						H.advance(1)
						T.eq(#H.sent(p, "Caught"), caughtBefore + 1, id .. " " .. label .. ": 계속 한 번만")
					end
					-- (1) 도망칠 수 있음 (기준의 105%): 멀리서는 안 잡힘, 하지만 경비에 닿으면 잡힘
					local egg = nestEgg(H, id)
					T.truthy(egg ~= nil, id .. " 둥지 씨앗")
					pickUp(H, p, egg)
					T.eq(egg:GetAttribute("EggState"), "Carried", id)
					setCarrySpeed(w, p, session, data, thr * 1.05)
					T.eq(SpeedMath.catchSeconds(biome.guardSpeed, session.carrySpeed), nil, id .. " 도망 가능")
					goFar()
					local caughtBefore = #H.sent(p, "Caught")
					H.advance(6)
					T.eq(#H.sent(p, "Caught"), caughtBefore, id .. ": 멀리서는 안 잡힘")
					T.eq(egg:GetAttribute("EggState"), "Carried", id)
					T.eq(guardModel(H, id):GetAttribute("State"), "Chase", id)
					touch()
					expectCaught(egg, "빠른 사람", caughtBefore)
					H.advance(settle)
					-- (2) 조금 모자람 (기준의 85%): 2.5초가 지나도 멀리 있으면 안 잡힘
					egg = nestEgg(H, id)
					pickUp(H, p, egg)
					setCarrySpeed(w, p, session, data, thr * 0.85)
					T.eq(SpeedMath.catchSeconds(biome.guardSpeed, session.carrySpeed), 2.5, id)
					goFar()
					caughtBefore = #H.sent(p, "Caught")
					T.eq(timeToCatch(H, p, 3.2), nil, id .. ": 2.5초가 지나도 멀리 있으면 안 잡힘")
					T.eq(egg:GetAttribute("EggState"), "Carried", id)
					touch()
					expectCaught(egg, "조금 모자람", caughtBefore)
					H.advance(settle)
					-- (3) 많이 모자람 (기준의 40%): 1초가 지나도 멀리 있으면 안 잡힘
					egg = nestEgg(H, id)
					pickUp(H, p, egg)
					setCarrySpeed(w, p, session, data, thr * 0.4)
					T.eq(SpeedMath.catchSeconds(biome.guardSpeed, session.carrySpeed), 1, id)
					goFar()
					caughtBefore = #H.sent(p, "Caught")
					T.eq(timeToCatch(H, p, 1.6), nil, id .. ": 1초가 지나도 멀리 있으면 안 잡힘")
					T.eq(egg:GetAttribute("EggState"), "Carried", id)
					touch()
					expectCaught(egg, "많이 모자람", caughtBefore)
					H.advance(settle)
					-- (4) 다음 구역 경계: 닿는 즉시 (마지막 구역은 맵 끝이라 못 넘음) — 시간·닿음과 상관없이 그대로
					egg = nestEgg(H, id)
					pickUp(H, p, egg)
					setCarrySpeed(w, p, session, data, thr * 0.4)
					if range.index < MapLayout.BIOME_COUNT then
						H.teleport(p, -50, 3, range.zMax + 0.5)
						local t = timeToCatch(H, p, 0.5)
						T.truthy(t ~= nil and t <= 0.25, id .. ": 경계를 넘으면 즉시 " .. tostring(t))
						T.eq(egg:GetAttribute("EggState"), "Nest", id .. ": 둥지로")
						local last = H.sent(p, "Caught")
						T.eq(last[#last][1].eggOutcome, "ReturnToNest")
						H.advance(settle)
					else
						H.teleport(p, -50, 3, range.zMax - 0.5)
						H.advance(0.4)
						T.eq(egg:GetAttribute("EggState"), "Carried", id .. ": 맵 끝 바로 앞은 아직 안 잡힘")
						caughtBefore = #H.sent(p, "Caught")
						T.eq(timeToCatch(H, p, 1.6), nil, id .. ": 맵 끝 구역도 시간이 지났다고 안 잡힘")
						touch()
						expectCaught(egg, "맵 끝 구역", caughtBefore)
						H.advance(settle)
					end
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	T.test(
		"추격 시간은 씨앗에 쌓임 (2026-11-10: 쌓이기만 할 뿐 잡힘·속도와 상관없음): 1.5초 쫓기다 구역 밖에서 내려놓고 5초 안에 다시 주우면 이어서 쌓임 / 다른 사람이 주우면 0부터 / 둥지로 돌아간 씨앗(구역 안에서 내려놓기 포함)은 0부터",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local a, sa, da = newRunner(H, 9101, "Alpha")
				local b, sb, db = newRunner(H, 9102, "Bravo")
				sa.moveExemptUntil = H.clock() + 1000
				sb.moveExemptUntil = H.clock() + 1000
				local id = "desert"
				local thr = threshold(id)
				local range = MapLayout.biome(id)
				local home = MapLayout.guardHome(id)
				local chase = SpeedMath.guardChaseSpeed(Biomes.get(id).guardSpeed)
				local humanoid = humanoidOf(guardModel(H, id))
				local egg = nestEgg(H, id)
				T.eq(w.EggService.getCarried(a), nil)
				pickUp(H, a, egg)
				setCarrySpeed(w, a, sa, da, thr * 0.85) -- 2.5초 급
				H.teleport(a, 0, 3, range.centerZ)
				H.advance(1.55)
				T.eq(#H.sent(a, "Caught"), 0)
				local eggObj = w.EggService.getCarried(a)
				T.truthy(
					eggObj.chaseSeconds >= 1.3 and eggObj.chaseSeconds <= 1.6,
					"쌓인 시간 " .. eggObj.chaseSeconds
				)
				T.eq(eggObj.chaseBy, a)
				T.near(humanoid.WalkSpeed, chase, 1e-9, "구역 고정 추격 속도")
				-- 구역 밖(입구 쪽 앞 구역)에서 내려놓음 → 바닥 5초 카운트다운, 경비는 추격 끝, 쌓인 시간은 씨앗에 그대로
				H.teleport(a, 0, 3, range.zMin - 5)
				T.eq(w.EggService.dropEgg(a), true)
				T.eq(egg:GetAttribute("EggState"), "Dropped")
				T.eq(egg:GetAttribute("ReturnsToNest"), true, "구역 밖: 5초 카운트다운")
				H.advance(0.3)
				T.eq(guardModel(H, id):GetAttribute("TargetUserId"), 0)
				local ended = H.sent(a, "ChaseEnded")
				T.eq(ended[#ended][1].reason, "dropped")
				H.advance(2)
				T.eq(egg:GetAttribute("EggState"), "Dropped", "5초 전")
				T.truthy(eggObj.chaseSeconds >= 1.3, "내려놓은 동안 쌓인 시간은 그대로")
				-- (1) 같은 사람이 5초 안에 다시 주움 → 이어서 쌓임 (2.5초를 다시 채우지 않음). 멀면 시간이 지나도 안 잡히고 경비 속도도 그대로
				pickUp(H, a, egg)
				T.eq(egg:GetAttribute("EggState"), "Carried")
				setCarrySpeed(w, a, sa, da, thr * 0.85)
				H.teleport(a, 0, 3, range.centerZ)
				H.advance(1.0)
				T.truthy(
					eggObj.chaseSeconds >= 2.2 and eggObj.chaseSeconds <= 3.0,
					"이어서 쌓임 (버렸다 줍기로 못 버팀) " .. tostring(eggObj.chaseSeconds)
				)
				T.near(
					humanoid.WalkSpeed,
					chase,
					1e-9,
					"쌓인 시간이 2.5초를 넘어도 경비 속도는 그대로 (돌진 없음)"
				)
				T.eq(#H.sent(a, "Caught"), 0, "그래도 멀리 있으면 안 잡힘")
				H.teleport(a, home.x, 3, home.z)
				local t = timeToCatch(H, a, 0.4)
				T.truthy(t ~= nil and t <= 0.3, "닿으면 그 틱에 잡힘 " .. tostring(t))
				T.eq(egg:GetAttribute("EggState"), "Nest", "둥지로 돌아감")
				T.eq(eggObj.chaseSeconds, 0, "둥지로 돌아가면 0")
				T.eq(eggObj.chaseBy, nil)
				H.advance(Config.RAGDOLL_SECONDS + 3)
				-- (2) 둥지로 돌아갔으니 같은 사람이 다시 주워도 처음부터
				pickUp(H, a, egg)
				eggObj = w.EggService.getCarried(a)
				setCarrySpeed(w, a, sa, da, thr * 0.85)
				H.teleport(a, 0, 3, range.centerZ)
				H.advance(1.0)
				T.truthy(
					eggObj.chaseSeconds >= 0.7 and eggObj.chaseSeconds <= 1.2,
					"둥지로 돌아간 씨앗은 0부터 " .. tostring(eggObj.chaseSeconds)
				)
				T.near(humanoid.WalkSpeed, chase, 1e-9)
				-- 구역 안에서 내려놓으면 바로 둥지로 → 시간도 0 으로
				T.eq(w.EggService.dropEgg(a), true)
				T.eq(egg:GetAttribute("EggState"), "Nest", "구역 안 내려놓기 = 바로 둥지")
				T.eq(eggObj.chaseSeconds, 0, "구역 안에서 내려놓은 씨앗도 0부터")
				H.advance(0.5)
				-- (3) 다른 사람이 주우면 0부터: A 가 1.5초 쫓기다 구역 밖에 내려놓은 씨앗을 B 가 줍기
				pickUp(H, a, egg)
				setCarrySpeed(w, a, sa, da, thr * 0.85)
				H.teleport(a, 0, 3, range.centerZ)
				H.advance(1.55)
				H.teleport(a, 0, 3, range.zMin - 5)
				w.EggService.dropEgg(a)
				H.advance(0.5)
				T.eq(egg:GetAttribute("EggState"), "Dropped")
				pickUp(H, b, egg)
				setCarrySpeed(w, b, sb, db, thr * 0.85)
				H.teleport(b, 0, 3, range.centerZ)
				H.advance(1.0)
				eggObj = w.EggService.getCarried(b)
				T.eq(eggObj.chaseBy, b, "경비가 B 를 쫓음")
				T.truthy(
					eggObj.chaseSeconds >= 0.7 and eggObj.chaseSeconds <= 1.2,
					"다른 사람이 주우면 처음부터 " .. tostring(eggObj.chaseSeconds)
				)
				T.near(humanoid.WalkSpeed, chase, 1e-9)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"추격 중 죽거나 나가면 정리: 경비 대상 해제·집으로·원래 속도, 구역 안이면 씨앗은 둥지로, 구역 밖이면 5초 뒤 둥지로, 서버 warn 0",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local id = "lake"
				local thr = threshold(id)
				local biome = Biomes.get(id)
				local range = MapLayout.biome(id)
				-- (1) 구역 안에서 죽음
				local a, sa, da = newRunner(H, 9201, "Dies")
				local egg = nestEgg(H, id)
				pickUp(H, a, egg)
				setCarrySpeed(w, a, sa, da, thr * 0.4)
				H.teleport(a, 0, 3, range.centerZ)
				H.advance(0.45)
				T.eq(guardModel(H, id):GetAttribute("TargetUserId"), a.UserId)
				a.Character.humanoid.Health = 0
				H.advance(0.5)
				T.eq(guardModel(H, id):GetAttribute("TargetUserId"), 0, "죽으면 대상 해제")
				T.truthy(guardModel(H, id):GetAttribute("State") ~= "Chase")
				T.eq(egg:GetAttribute("EggState"), "Nest", "구역 안에서 죽음 = 둥지로")
				T.near(
					humanoidOf(guardModel(H, id)).WalkSpeed,
					SpeedMath.guardBaseWalkSpeed(biome.guardSpeed),
					1e-9,
					"집으로 돌아가는 속도"
				)
				T.eq(#H.sent(a, "Caught"), 0, "죽음은 잡힘 알림이 아님")
				-- (2) 구역 안에서 나감
				local b, sb, db = newRunner(H, 9202, "Leaves")
				local egg2 = nestEgg(H, id)
				pickUp(H, b, egg2)
				setCarrySpeed(w, b, sb, db, thr * 0.4)
				H.teleport(b, 0, 3, range.centerZ)
				H.advance(0.45)
				T.eq(guardModel(H, id):GetAttribute("TargetUserId"), b.UserId)
				w.EggService.onPlayerLeaving(b)
				H.leave(b)
				H.advance(0.5)
				T.eq(guardModel(H, id):GetAttribute("TargetUserId"), 0, "나가면 대상 해제")
				T.eq(egg2:GetAttribute("EggState"), "Nest", "구역 안에서 나감 = 둥지로")
				-- (3) 도망칠 수 있는 사람이 다음 구역(사막)까지 가서 나감 → 5초 뒤 둥지로
				local c, sc, dc = newRunner(H, 9203, "Far")
				local egg3 = nestEgg(H, id)
				local home = egg3.Position
				pickUp(H, c, egg3)
				setCarrySpeed(w, c, sc, dc, thr * 1.5)
				sc.moveExemptUntil = H.clock() + 10
				H.teleport(c, 0, 3, range.zMax + 40)
				H.advance(0.45)
				T.eq(egg3:GetAttribute("EggState"), "Carried", "도망 가능하면 다음 구역에서도 자유")
				T.eq(guardModel(H, id):GetAttribute("TargetUserId"), c.UserId)
				w.EggService.onPlayerLeaving(c)
				H.leave(c)
				H.advance(0.3)
				T.eq(egg3:GetAttribute("EggState"), "Dropped")
				T.eq(egg3:GetAttribute("ReturnsToNest"), true)
				T.eq(guardModel(H, id):GetAttribute("TargetUserId"), 0)
				H.advance(4.5)
				T.eq(egg3:GetAttribute("EggState"), "Dropped", "5초 전")
				H.advance(0.6)
				T.eq(egg3:GetAttribute("EggState"), "Nest", "5초 뒤 둥지로")
				T.eq(egg3.Position.X, home.X)
				T.eq(egg3.Position.Z, home.Z)
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	T.test(
		"경비 속도 (2026-11-10 돌진 없음): 추격 중 WalkSpeed 는 시간이 아무리 지나도 언제나 구역 고정 추격 속도 (21구역 전부, 230 안) — 멀리 있으면 안 잡히고, 닿으면 잡히고 나서 집으로 돌아가는 원래 속도로 복귀 / 바로 옆이면 첫 틱에 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9301, "Rush")
				for _, id in ALL_ZONES do
					local biome = Biomes.get(id)
					local range = MapLayout.biome(id)
					local chase = SpeedMath.guardChaseSpeed(biome.guardSpeed)
					local base = SpeedMath.guardBaseWalkSpeed(biome.guardSpeed)
					local home = MapLayout.guardHome(id)
					T.truthy(chase <= Config.SPEED_WALK_MAX, id .. " 추격 속도 230 안: " .. chase)
					local humanoid = humanoidOf(guardModel(H, id))
					T.near(humanoid.WalkSpeed, base, 1e-9, id .. " 잘 때는 원래 속도")
					-- 먼 곳에서 많이 모자람 (1초): 1초 · 2.5초 · 그 훨씬 뒤에도 속도가 안 변하고 안 잡힘
					local egg = nestEgg(H, id)
					pickUp(H, p, egg)
					setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
					H.teleport(p, 80, 3, range.zMin + 5)
					local maxSpeed, minSpeed = 0, math.huge
					local before = #H.sent(p, "Caught")
					local t = 0
					while t < 4 do
						H.advance(0.02)
						t += 0.02
						if t > 0.12 then -- 첫 틱 전에는 아직 자는 속도 (원래 속도가 추격 속도보다 약간 빠름)
							local ws = humanoid.WalkSpeed
							maxSpeed = math.max(maxSpeed, ws)
							minSpeed = math.min(minSpeed, ws)
						end
					end
					T.eq(#H.sent(p, "Caught"), before, id .. ": 시간이 지나도 멀리 있으면 안 잡힘")
					T.near(
						maxSpeed,
						chase,
						1e-9,
						id .. ": 4초 동안 WalkSpeed 최댓값 = 구역 고정 추격 속도"
					)
					T.near(
						minSpeed,
						chase,
						1e-9,
						id .. ": 4초 동안 WalkSpeed 최솟값 = 구역 고정 추격 속도"
					)
					T.truthy(maxSpeed <= Config.GUARD_CATCH_RUSH_MAX_WALKSPEED + 1e-9, id .. " 400 안")
					-- 닿으면 잡힘, 잡힌 뒤에는 집으로 돌아가는 원래 속도로 복귀
					H.teleport(p, home.x, 3, home.z)
					t = timeToCatch(H, p, 0.4)
					T.truthy(t ~= nil, id .. " 닿으면 잡힘")
					H.advance(0.4)
					T.near(humanoid.WalkSpeed, base, 1e-9, id .. ": 잡힌 뒤 원래 속도로 복귀")
					H.advance(Config.RAGDOLL_SECONDS + 3)
					-- 바로 옆: 첫 틱에 잡힘 (평소 추격 속도 그대로)
					egg = nestEgg(H, id)
					pickUp(H, p, egg)
					setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
					H.teleport(p, home.x + 2, 3, home.z)
					before = #H.sent(p, "Caught")
					t = 0
					while t < 1.6 and #H.sent(p, "Caught") == before do
						H.advance(0.02)
						t += 0.02
					end
					T.truthy(
						#H.sent(p, "Caught") > before and t <= 0.3,
						id .. ": 바로 옆이면 첫 틱에 잡힘 " .. t
					)
					-- 닿은 채로 주웠으면 쫓기도 전에 잡혀서 (쫓는 사람 없음) 경비는 바로 원래 속도
					T.near(humanoid.WalkSpeed, base, 1e-9, id .. ": 바로 잡히면 경비는 바로 원래 속도로")
					H.advance(Config.RAGDOLL_SECONDS + 3)
				end
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"GuardLogic.rushWalkSpeed: 어떤 이상한 값이 와도 [기본, 400] 안 (NaN·음수·0·무한·아주 큰 거리)",
		function()
			local base, max = 150, Config.GUARD_CATCH_RUSH_MAX_WALKSPEED
			local junk = { 0 / 0, -1, 0, 1e-12, 0.05, 0.3, 1, 1e3, 1e9, 1e300 }
			for _, distance in junk do
				for _, remaining in junk do
					local ws = GuardLogic.rushWalkSpeed(distance, remaining, base, max)
					T.truthy(
						finite(ws) and ws >= base and ws <= max,
						string.format("%s / %s → %s", distance, remaining, ws)
					)
				end
			end
			for _, distance in { -math.huge, 1e308 } do
				for _, remaining in { -math.huge, 1e-300 } do
					local ws = GuardLogic.rushWalkSpeed(distance, remaining, base, max)
					T.truthy(
						finite(ws) and ws >= base and ws <= max,
						string.format("%s / %s → %s", distance, remaining, ws)
					)
				end
			end
			T.eq(GuardLogic.rushWalkSpeed(1000, 0.3, 80, 400), 400, "필요한 속도가 400 보다 크면 400")
			T.eq(GuardLogic.rushWalkSpeed(3, 0.3, 80, 400), 80, "가까우면 기본 속도")
			T.near(GuardLogic.rushWalkSpeed(60, 0.3, 80, 400), 200, 1e-9, "남은 거리 ÷ 남은 시간")
			T.eq(GuardLogic.crossedForward(0 / 0, 240), false)
			T.eq(GuardLogic.crossedForward(239.999, 240), false)
			T.eq(GuardLogic.crossedForward(240, 240), true)
		end
	)

	T.test(
		"여러 명 (2026-11-10 닿아야 잡힘 · H-1 고침): 도망 못 치는 두 사람(가까운·먼)과 도망 가능한 한 사람 — 경비에 닿은 사람은 쫓는 대상이 아니어도(빠른 사람도) 그 틱에 잡힘 · 안 닿은 사람은 시간이 지나도 안 잡힘 · 못 치는 사람을 가까운 순서로 쫓고 닿는 대로 한 번씩만 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local id = "snow"
				local thr = threshold(id)
				local range = MapLayout.biome(id)
				local home = MapLayout.guardHome(id)
				local near, sn, dn = newRunner(H, 9401, "Near")
				local far, sf, df = newRunner(H, 9402, "Far")
				local free, sfr, dfr = newRunner(H, 9403, "Free")
				pickUp(H, free, nestEgg(H, id, 0))
				setCarrySpeed(w, free, sfr, dfr, thr * 1.1)
				pickUp(H, far, nestEgg(H, id, 0))
				setCarrySpeed(w, far, sf, df, thr * 0.85) -- 2.5초
				pickUp(H, near, nestEgg(H, id, 0))
				setCarrySpeed(w, near, sn, dn, thr * 0.4) -- 1초
				H.teleport(free, home.x + 1, 3, home.z) -- 가장 가까움 (경비 바로 옆, 닿은 채)
				H.teleport(near, home.x + 20, 3, home.z) -- 잡힘 거리 밖
				H.teleport(far, 0, 3, range.zMin + 30) -- 가장 멂
				H.advance(0.4)
				local model = guardModel(H, id)
				-- 2026-11-10 (주임 H-1 고침): 경비가 다른 사람을 쫓는 중이어도 경비에 닿은 사람은 그 틱에 잡힘
				T.eq(
					#H.sent(free, "Caught"),
					1,
					"닿은 채인 도망 가능한 사람도 첫 틱에 잡힘 (쫓는 사람이 따로 있어도)"
				)
				T.eq(#H.sent(near, "Caught"), 0)
				T.eq(#H.sent(far, "Caught"), 0)
				T.eq(
					model:GetAttribute("TargetUserId"),
					near.UserId,
					"남은 사람 중 도망 못 치는 가까운 쪽을 쫓음"
				)
				-- 시간이 지나도(1초 · 2.5초) 안 닿은 사람은 안 잡힘
				H.advance(4)
				T.eq(#H.sent(near, "Caught"), 0, "시간이 지나도 안 닿으면 안 잡힘")
				T.eq(#H.sent(far, "Caught"), 0)
				T.eq(#H.sent(free, "Caught"), 1)
				-- 가까운 사람이 경비에 닿음 → 그 사람만 한 번 잡힘
				H.teleport(near, home.x + 3, 3, home.z)
				H.advance(0.3)
				T.eq(#H.sent(near, "Caught"), 1, "닿은 사람이 잡힘")
				T.eq(#H.sent(far, "Caught"), 0)
				H.advance(0.3)
				T.eq(model:GetAttribute("TargetUserId"), far.UserId, "다음은 남은 도망 못 치는 사람")
				H.advance(3)
				T.eq(#H.sent(far, "Caught"), 0, "멀리 있으면 오래 지나도 안 잡힘")
				-- 먼 사람도 닿으면 잡힘
				H.teleport(far, home.x + 3, 3, home.z - 2)
				H.advance(0.3)
				T.eq(#H.sent(far, "Caught"), 1)
				H.advance(3)
				T.eq(#H.sent(near, "Caught"), 1)
				T.eq(#H.sent(far, "Caught"), 1)
				T.eq(#H.sent(free, "Caught"), 1, "각자 한 번만")
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"추격 속도 상한: 21구역 추격 WalkSpeed 는 구역이 뒤일수록 같거나 빠르고 전부 230 안(18구역 229.55 · 19~21 229.69/229.82/229.95), 추천 속도면 보통 씨앗은 도망·모자라면 잡힘, 큰 씨앗은 더 빨라야 도망",
		function()
			local prev = 0
			local expect =
				{ bug_dimension = 229.55, robot_factory = 229.69, clock_tower = 229.82, rainbow_sky = 229.95 }
			for _, b in Biomes.list do
				local chase = SpeedMath.guardChaseSpeed(b.guardSpeed)
				T.truthy(chase >= prev, b.id .. " 앞 구역보다 같거나 빠름")
				T.truthy(chase <= Config.SPEED_WALK_MAX, b.id .. " 230 안 " .. chase)
				T.truthy(chase <= Config.GUARD_MAX_WALKSPEED)
				prev = chase
				if expect[b.id] then
					T.near(chase, expect[b.id], 0.006, b.id)
				end
				-- 보통 씨앗(-10%): 추천 속도 이상이면 도망, 1% 모자라면 못 도망
				local normal = 1 - Sizes.get("normal").speedPenalty
				T.truthy(
					SpeedMath.canEscape(b.guardSpeed, b.recommendedSpeed * normal * 1.001),
					b.id .. " 추천 속도면 도망"
				)
				T.falsy(
					SpeedMath.canEscape(b.guardSpeed, b.recommendedSpeed * normal * 0.98),
					b.id .. " 모자라면 못 도망"
				)
				-- 큰 씨앗일수록 필요한 속도가 커짐 (requiredSpeed)
				local lastNeed = 0
				for _, size in Sizes.list do
					local need = SpeedMath.requiredSpeed(b.recommendedSpeed, size.speedPenalty)
					T.truthy(need > lastNeed, b.id .. " " .. size.id)
					lastNeed = need
					T.truthy(
						SpeedMath.canEscape(b.guardSpeed, need * (1 - size.speedPenalty) * 1.0001),
						b.id .. " " .. size.id
					)
				end
			end
			-- 1.267T 를 넘으면 플레이어도 경비도 230 에 붙음 (알려진 한계: 20 · 21구역은 아주 근소)
			T.truthy(Biomes.get("rainbow_sky").recommendedSpeed < 1.267e12)
		end
	)

	T.test(
		"경비가 영영 못 잡거나 아무 때나 잡는 일 없음 (2026-11-10): 어떤 속도 칸에서도 (도망 가능 1e15·1e24 포함) 멀리서는 시간이 지나도 안 잡히고, 경비에 닿으면 그 틱(0.3초 안)에 한 번 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9501, "Edge")
				local id = "rainbow_sky"
				local range = MapLayout.biome(id)
				local home = MapLayout.guardHome(id)
				local thr = threshold(id)
				local function touchAndExpect(label)
					local before = #H.sent(p, "Caught")
					H.teleport(p, home.x, 3, home.z)
					local t = timeToCatch(H, p, 0.4)
					T.truthy(t ~= nil and t <= 0.3, label .. ": 닿으면 그 틱에 잡힘 " .. tostring(t))
					T.eq(#H.sent(p, "Caught"), before + 1, label .. ": 한 번")
				end
				for _, factor in { 0, 0.001, 0.2, 0.6999, 0.7, 0.7001, 0.9, 0.999, 1.0 } do
					local egg = nestEgg(H, id)
					pickUp(H, p, egg)
					setCarrySpeed(w, p, session, data, thr * factor)
					H.teleport(p, 0, 3, range.centerZ)
					local want = if factor >= 0.7 then 2.5 else 1
					T.eq(SpeedMath.catchSeconds(Biomes.get(id).guardSpeed, session.carrySpeed), want, tostring(factor))
					T.eq(
						timeToCatch(H, p, want + 1.5),
						nil,
						"속도 " .. factor .. " 배: " .. want .. "초가 지나도 멀리서는 안 잡힘"
					)
					touchAndExpect("속도 " .. factor .. " 배")
					H.advance(Config.RAGDOLL_SECONDS + 3)
				end
				for _, speed in { thr * 1.0001, 1e15, Config.SPEED_MAX } do
					local egg = nestEgg(H, id)
					pickUp(H, p, egg)
					data.speed = speed / (1 - session.carryPenalty)
					w.SpeedService.refresh(p)
					H.teleport(p, 0, 3, range.centerZ)
					local before = #H.sent(p, "Caught")
					H.advance(5)
					T.eq(#H.sent(p, "Caught"), before, "속도 " .. speed .. ": 도망 가능, 멀리서는 안 잡힘")
					touchAndExpect("속도 " .. speed .. " (도망 가능)")
					H.advance(Config.RAGDOLL_SECONDS + 3)
				end
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.skip(
		"E-1 GuardLogic.rushWalkSpeed(무한, 무한) 은 NaN",
		"참고: 거리와 남은 시간이 둘 다 무한이면 inf/inf = NaN 이 clamp 를 통과함. 실제로는 유한한 값만 들어와서 닿지 않음 (한 줄 방어: needed ~= needed 면 base)",
		function()
			local ws = GuardLogic.rushWalkSpeed(math.huge, math.huge, 150, 400)
			T.truthy(finite(ws) and ws >= 150 and ws <= 400, tostring(ws))
		end
	)

	------------------------------------------------------------------
	T.suite("8판 주임 검수 B: 떨어진 씨앗 규칙 (진짜 EggService)")

	local function eggWorld(H)
		local w = { H = H }
		w.EggService = H.server("Services/EggService")
		w.EggService.start()
		w.SpeedService = H.server("Services/SpeedService")
		H.setPhase("Intermission", 1)
		H.setPhase("Day", 1)
		return w
	end

	local function countNestEggs(H)
		local n = 0
		for _, part in H.map.folders.Eggs.children do
			if part:GetAttribute("EggState") == "Nest" then
				n += 1
			end
		end
		return n
	end

	local function expectGround(egg, stay, label)
		T.eq(egg:GetAttribute("EggState"), "Dropped", label)
		T.truthy(typeof(egg:GetAttribute("DroppedAt")) == "number", label .. ": DroppedAt")
		if stay then
			T.eq(egg:GetAttribute("ExpiresAt"), nil, label .. ": 카운트다운 없음")
			T.eq(egg:GetAttribute("ReturnsToNest"), false, label)
		else
			T.eq(egg:GetAttribute("ReturnsToNest"), true, label)
			T.near(
				egg:GetAttribute("ExpiresAt") - egg:GetAttribute("DroppedAt"),
				Config.DROPPED_EGG_RETURN_SECONDS,
				1e-9,
				label .. ": ExpiresAt = DroppedAt + 5"
			)
		end
	end

	T.test(
		'구역 안에서 놓친 씨앗 (2026-11-10): DropEgg·방망이·곰덫 → 바로 둥지로 (바닥 씨앗 0) · 치트 의심 위치(dropCarriedAt)만 바닥에 놓이지만 "그대로(Stay)" 는 없이 5초 카운트다운 뒤 둥지로 · 주우면 카운트다운 취소 · 초기화(ALL SEED RESET)에 지워지고 둥지 105개가 새로 채워짐',
		function()
			inWorld({ realEgg = true }, function(H)
				local w = eggWorld(H)
				T.eq(countNestEggs(H), 105, "초기화 직후 둥지 21 × 5")
				local range = MapLayout.biome("jungle")
				local paths = {
					{
						"DropEgg 버튼",
						function(p)
							H.client(p, "DropEgg")
						end,
					},
					{
						"방망이(knockOut player)",
						function(p, x, z)
							w.EggService.knockOut(p, H.vec(x + 3, 3, z), "player", "Bob", 1)
						end,
					},
					{
						"곰덫(dropCarried player)",
						function(p)
							w.EggService.dropCarried(p, "player")
						end,
					},
					{
						"치트 의심(dropCarriedAt)",
						function(p, x, z)
							w.EggService.dropCarriedAt(p, H.vec(x, 3, z))
						end,
						true, -- 이 길만 구역 안 바닥에 놓임 (그래도 5초 뒤 둥지)
					},
				}
				local other, so = newRunner(H, 9601, "Other")
				so.plotIndex = 2
				local dropped = {}
				for i, path in paths do
					local p = newRunner(H, 9610 + i, "Dropper" .. i)
					local egg = nestEgg(H, "jungle")
					local home = egg.Position
					pickUp(H, p, egg)
					local x, z = 20 + i * 10, range.centerZ - 30 + i
					H.teleport(p, x, 3, z)
					H.advance(0.3)
					path[2](p, x, z)
					if path[3] then
						expectGround(egg, false, path[1])
						T.eq(egg.Position.X, x, path[1] .. ": 그 자리")
						T.eq(egg.Position.Z, z, path[1] .. ": 그 자리")
						T.eq(egg:FindFirstChild("StealPrompt").Enabled, true)
					else
						T.eq(egg:GetAttribute("EggState"), "Nest", path[1] .. ": 구역 안 = 바로 둥지")
						T.eq(egg.Position.X, home.X, path[1] .. ": 원래 둥지")
						T.eq(egg.Position.Z, home.Z, path[1] .. ": 원래 둥지")
						T.eq(egg:GetAttribute("DroppedAt"), nil, path[1] .. ": 바닥 표시 없음")
						T.eq(egg:GetAttribute("ExpiresAt"), nil)
						T.eq(egg:GetAttribute("ReturnsToNest"), nil)
					end
					table.insert(dropped, { egg = egg, x = x, z = z, home = home, label = path[1], ground = path[3] })
				end
				T.eq(countNestEggs(H), 104, "둥지 104개 + 바닥 1개 (치트 의심)")
				T.eq(#H.map.folders.Eggs.children, 105)
				-- 카운트다운 중 누가 줍기 → 취소 (5초가 지나도 안 돌아감) → 구역 안에서 내려놓으면 바로 둥지
				local ground = dropped[4].egg
				H.advance(3)
				pickUp(H, other, ground)
				T.eq(ground:GetAttribute("EggState"), "Carried")
				T.eq(ground:GetAttribute("DroppedAt"), nil)
				T.eq(ground:GetAttribute("ExpiresAt"), nil)
				T.eq(ground:GetAttribute("ReturnsToNest"), nil)
				H.advance(6)
				T.eq(ground:GetAttribute("EggState"), "Carried", "줍은 씨앗은 5초가 지나도 안 돌아감")
				H.teleport(other, 40, 3, range.centerZ)
				w.EggService.dropEgg(other)
				T.eq(ground:GetAttribute("EggState"), "Nest", "구역 안에서 내려놓으면 바로 둥지")
				T.eq(ground.Position.X, dropped[4].home.X)
				-- 600초가 지나도 전부 둥지에 그대로 (바닥 씨앗도 둥지 수도 안 변함)
				H.advance(600)
				for _, d in dropped do
					T.eq(d.egg:GetAttribute("EggState"), "Nest", d.label .. ": 600초 뒤에도 둥지")
					T.eq(d.egg.Position.X, d.home.X, d.label)
					T.eq(d.egg:GetAttribute("ExpiresAt"), nil)
				end
				T.eq(countNestEggs(H), 105, "둥지 105개 전부 참")
				T.eq(#H.map.folders.Eggs.children, 105, "씨앗 파트 수 그대로 (바닥 씨앗 0)")
				-- 초기화: 둥지가 새로 채워짐
				H.setPhase("Intermission", 2)
				T.eq(countNestEggs(H), 105, "초기화 뒤 둥지 105개")
				for _, part in H.map.folders.Eggs.children do
					T.truthy(part:GetAttribute("EggState") ~= "Dropped", "바닥 씨앗 없음")
				end
				T.eq(#H.map.folders.Eggs.children, 105, "씨앗 파트가 쌓이지 않음")
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"구역 밖에서 떨어진 씨앗(앞·뒤 구역·허브 쪽·맵 밖 / DropEgg·방망이·곰덫·죽음·나감·치트 의심): 5초 카운트다운(ExpiresAt = DroppedAt + 5, ReturnsToNest true), 5초 안엔 그대로, 5초 뒤 원래 둥지로 (속성 정리)",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = eggWorld(H)
				local lake = MapLayout.biome("lake")
				local places = {
					{ "앞 구역(숲)", 30, 120 },
					{ "뒤 구역(사막)", -30, lake.zMax + 100 },
					{ "허브", 0, -5 },
					{ "맵 밖", 0, MapLayout.MAP_END_Z + 50 },
				}
				local n = 0
				for _, place in places do
					n += 1
					local p, session = newRunner(H, 9700 + n, "Out" .. n)
					local egg = nestEgg(H, "lake")
					local home = egg.Position
					pickUp(H, p, egg)
					session.moveExemptUntil = H.clock() + 30
					H.teleport(p, place[2], 3, place[3])
					H.client(p, "DropEgg")
					expectGround(egg, false, place[1])
					T.eq(egg.Position.Z, place[3], place[1] .. ": 떨어진 자리")
					H.advance(4.8)
					T.eq(egg:GetAttribute("EggState"), "Dropped", place[1] .. ": 5초 전")
					H.advance(0.5)
					T.eq(egg:GetAttribute("EggState"), "Nest", place[1] .. ": 5초 뒤 둥지")
					T.eq(egg.Position.X, home.X, place[1])
					T.eq(egg.Position.Z, home.Z, place[1])
					T.eq(egg:GetAttribute("ExpiresAt"), nil, place[1] .. ": 속성 정리")
					T.eq(egg:GetAttribute("ReturnsToNest"), nil)
					T.eq(egg:GetAttribute("DroppedAt"), nil)
				end
				local desert = MapLayout.biome("desert")
				local x, z = 10, desert.centerZ
				local pathsOut = {
					{
						"방망이",
						function(p)
							w.EggService.knockOut(p, H.vec(x + 3, 3, z), "player", "Bob", 1)
						end,
					},
					{
						"곰덫",
						function(p)
							w.EggService.dropCarried(p, "player")
						end,
					},
					{
						"치트 의심",
						function(p)
							w.EggService.dropCarriedAt(p, H.vec(x, 3, z))
						end,
					},
					{
						"죽음",
						function(p)
							p.Character.humanoid.Health = 0
							H.advance(0.3)
						end,
					},
					{
						"나감",
						function(p)
							w.EggService.onPlayerLeaving(p)
							H.leave(p)
						end,
					},
				}
				for i, path in pathsOut do
					local p, session = newRunner(H, 9750 + i, "Out2_" .. i)
					local egg = nestEgg(H, "lake")
					local home = egg.Position
					pickUp(H, p, egg)
					session.moveExemptUntil = H.clock() + 30
					H.teleport(p, x, 3, z)
					H.advance(0.45) -- 둥지 예약이 풀리는 틱
					path[2](p)
					expectGround(egg, false, "사막 " .. path[1])
					T.eq(egg.Position.Z, z, path[1] .. ": 떨어진 자리")
					H.advance(4.5)
					T.eq(egg:GetAttribute("EggState"), "Dropped", path[1] .. ": 5초 전")
					H.advance(0.8)
					T.eq(egg:GetAttribute("EggState"), "Nest", path[1] .. ": 5초 뒤 둥지")
					T.eq(egg.Position.X, home.X, path[1] .. ": 원래 둥지")
					T.eq(egg.Position.Z, home.Z, path[1] .. ": 원래 둥지")
				end
				T.eq(countNestEggs(H), 105, "씨앗이 하나도 안 사라지고 안 늘어남")
				T.eq(#H.map.folders.Eggs.children, 105)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"구역 밖 5초 카운트다운 중 누가 주우면 취소(5초가 지나도 안 돌아감) · 초기화가 오면 카운트다운 중인 씨앗도 지워짐 · 둥지가 다 차면 사라지고 씨앗 수가 안 늘어남",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = eggWorld(H)
				local lake = MapLayout.biome("lake")
				local a, sa = newRunner(H, 9801, "A")
				local b = newRunner(H, 9802, "B")
				local egg = nestEgg(H, "lake")
				pickUp(H, a, egg)
				sa.moveExemptUntil = H.clock() + 30
				H.teleport(a, 0, 3, 100)
				w.EggService.dropEgg(a)
				H.advance(4.7)
				pickUp(H, b, egg) -- 거의 다 됐을 때 줍기
				T.eq(egg:GetAttribute("EggState"), "Carried")
				T.eq(egg:GetAttribute("ExpiresAt"), nil)
				H.advance(6)
				T.eq(egg:GetAttribute("EggState"), "Carried", "5초가 지나도 들고 있는 씨앗은 안 돌아감")
				-- 들고 구역 안으로 돌아와 내려놓으면 그대로
				H.teleport(b, 0, 3, lake.centerZ)
				w.EggService.dropEgg(b)
				T.eq(egg:GetAttribute("EggState"), "Nest", "구역 안 내려놓기 = 바로 둥지 (2026-11-10)")
				-- 카운트다운 중 초기화
				local c, sc = newRunner(H, 9803, "C")
				local egg2 = nestEgg(H, "lake")
				pickUp(H, c, egg2)
				sc.moveExemptUntil = H.clock() + 30
				H.teleport(c, 0, 3, 100)
				w.EggService.dropEgg(c)
				H.advance(2)
				expectGround(egg2, false, "카운트다운 중")
				H.setPhase("Intermission", 2)
				T.truthy(egg2.destroyed, "카운트다운 중인 씨앗도 초기화에 지워짐")
				T.truthy(egg.destroyed)
				T.eq(#H.map.folders.Eggs.children, 105)
				H.setPhase("Day", 2)
				H.advance(10) -- 지워진 씨앗의 카운트다운이 뒤늦게 터져 오류가 나지 않음
				T.eq(#H.map.folders.Eggs.children, 105)
				-- 둥지가 다 차서 돌아갈 곳이 없으면 사라짐 (예약 풀림 → 30초 뒤 새 씨앗이 이미 있는 경우)
				local d, sd = newRunner(H, 9804, "D")
				local egg3 = nestEgg(H, "lake")
				pickUp(H, d, egg3)
				sd.moveExemptUntil = H.clock() + 100
				H.teleport(d, 0, 3, 100)
				H.advance(0.5) -- 예약 풀림
				H.advance(31) -- 그 둥지에 새 씨앗이 다시 놓임
				T.eq(countNestEggs(H), 105, "빈 둥지가 다시 채워짐")
				w.EggService.dropEgg(d)
				H.advance(5.5)
				T.truthy(egg3.destroyed, "돌아갈 빈 둥지가 없으면 사라짐")
				T.eq(#H.map.folders.Eggs.children, 105, "씨앗이 늘어나지 않음")
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"바닥 씨앗이 쌓이는 상한 (2026-11-10): 구역 안에서 내려놓기를 반복해도 바닥 씨앗은 0 (바로 둥지로) · 구역 밖에서 내려놓기를 하루(낮 285초) 내내 반복해도 5초 뒤 돌아가서 그 구역 바닥 씨앗은 둥지 수 × (285 ÷ 30초 + 1) 이하, 초기화 때 전부 정리",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = eggWorld(H)
				local id = "volcano"
				local range = MapLayout.biome(id)
				local p, session = newRunner(H, 9901, "Griefer")
				session.moveExemptUntil = H.clock() + 10000
				local function floorCount()
					local floor = 0
					for _, part in H.map.folders.Eggs.children do
						if part:GetAttribute("BiomeId") == id and part:GetAttribute("EggState") == "Dropped" then
							floor += 1
						end
					end
					return floor
				end
				-- (1) 구역 안: 줍고 → 구역 안에서 내려놓기 반복 = 바닥 씨앗 0, 씨앗 수 그대로
				local t0 = H.clock()
				local inZoneLoops = 0
				while H.clock() - t0 < 60 do
					local egg = nestEgg(H, id)
					T.truthy(
						egg ~= nil,
						"구역 안 반복: 둥지 씨앗이 있음 (내려놓은 씨앗이 바로 돌아옴)"
					)
					pickUp(H, p, egg)
					H.teleport(p, 30, 3, range.centerZ)
					w.EggService.dropEgg(p)
					T.eq(egg:GetAttribute("EggState"), "Nest", "구역 안 내려놓기 = 바로 둥지")
					T.eq(floorCount(), 0, "바닥 씨앗 0")
					inZoneLoops += 1
					H.advance(0.3)
				end
				T.eq(#H.map.folders.Eggs.children, 105, "구역 안 반복에서는 씨앗이 안 늘어남")
				T.truthy(inZoneLoops > 50, "시험이 약함 " .. inZoneLoops)
				-- (2) 구역 밖: 줍고 → 구역 밖에 잠깐 가서(예약 풀림) 내려놓기 반복 = 5초 뒤 둥지로, 쌓이는 데 상한
				local DAY = 285
				t0 = H.clock()
				local maxParts, maxFloor, loops = 0, 0, 0
				while H.clock() - t0 < DAY do
					local egg = nestEgg(H, id)
					if egg then
						loops += 1
						pickUp(H, p, egg)
						H.teleport(p, 0, 3, range.zMax + 6) -- 구역 밖: 둥지 예약이 풀림
						H.advance(0.45)
						w.EggService.dropEgg(p) -- 구역 밖: 그 자리, 5초 뒤 둥지로
						H.advance(0.1)
					else
						H.advance(1)
					end
					local floor = floorCount()
					maxFloor = math.max(maxFloor, floor)
					maxParts = math.max(maxParts, #H.map.folders.Eggs.children)
				end
				local bound = Config.NESTS_PER_BIOME * (math.floor(DAY / Config.NEST_RESPAWN_SECONDS) + 1)
				print(
					string.format(
						"      (참고) 구역 밖 반복: 하루 동안 바닥 씨앗 최대 %d개 (상한 %d), 전체 씨앗 파트 최대 %d, 반복 %d번",
						maxFloor,
						bound,
						maxParts,
						loops
					)
				)
				T.truthy(maxFloor >= 1, "시험이 약함: 구역 밖에서 바닥 씨앗이 안 보임 " .. maxFloor)
				T.truthy(maxFloor <= bound, "바닥 씨앗 상한을 넘음 " .. maxFloor .. " > " .. bound)
				T.truthy(maxParts <= 105 + bound, "전체 씨앗 파트 " .. maxParts)
				H.setPhase("Intermission", 2)
				T.eq(#H.map.folders.Eggs.children, 105, "초기화에 전부 정리")
				T.eq(floorCount(), 0)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("8판 주임 검수 C: 둥지 무리 · 구역 19~21 · 1~18 좌표")

	local function dist(a, b)
		return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
	end

	T.test(
		"둥지 105개 전부: 구역 안·벽에서 20 이상·다음 구역 경계에서 29 이상·서로 8 이상(이웃 8~8.6)·경비 집/표지판/장식과 안 겹침, 모든 구역 같은 모양 (65번: 경비 집은 무리의 벽 쪽 x −100)",
		function()
			local c = MapLayout.NEST_CLUSTER
			T.eq(c.x, -82)
			T.eq(c.endGap, 36)
			T.eq(c.guardDx, -18, "65번: 무리의 오른쪽 = 벽 쪽")
			T.eq(c.sign.dx, 14, "65번: 표지판은 복도 쪽으로")
			T.eq(c.sign.dz, -14)
			local total = 0
			local firstShape
			for _, b in MapLayout.biomes do
				local cl = MapLayout.nestCluster(b.id)
				T.eq(#cl.nests, Config.NESTS_PER_BIOME, b.id)
				T.eq(#cl.decor, 2, b.id)
				-- 숫자 (SEED 9장 37번): 무리 가운데 (x -82, zMax - 36)
				T.eq(cl.center.x, -82)
				T.eq(cl.center.z, b.zMax - 36)
				T.eq(MapLayout.guardHome(b.id).x, cl.guard.x)
				T.eq(MapLayout.guardHome(b.id).z, cl.guard.z)
				T.eq(MapLayout.nestSign(b.id).z, cl.sign.z)
				T.eq(cl.guard.x, -100, "65번: 경비 집 = 가운데 + (-18, 0), 벽에서 10")
				T.eq(cl.guard.z, cl.center.z)
				T.eq(cl.sign.x, -68)
				T.eq(cl.sign.z, cl.center.z - 14)
				local shape = {}
				for i, n in cl.nests do
					total += 1
					T.eq(MapLayout.zoneAt(n.z), b.id, b.id .. " 둥지 " .. i .. " 구역 안")
					T.truthy(
						math.abs(n.x) <= MapLayout.HALF_WIDTH - 20 + 1e-9,
						b.id .. " 벽에서 20 이상: x " .. n.x
					)
					T.truthy(b.zMax - n.z >= 29 - 1e-9, b.id .. " 다음 구역 경계에서 29 이상")
					T.truthy(n.z - b.zMin >= 150, b.id .. " 입구에서 멂")
					T.truthy(n.x < 0, b.id .. " 오른쪽(x<0) 귀퉁이")
					table.insert(shape, string.format("%g,%g", n.x, n.z - b.zMax))
					for j = i + 1, #cl.nests do
						T.truthy(dist(n, cl.nests[j]) >= 8 - 1e-9, b.id .. " 둥지끼리 8 이상")
					end
				end
				local sorted = table.concat(shape, ";")
				if not firstShape then
					firstShape = sorted
				end
				T.eq(sorted, firstShape, b.id .. ": 모든 구역이 같은 모양")
				-- 이웃끼리 8 ~ 8.6 (가운데에서 네 둥지까지)
				for i = 2, #cl.nests do
					local d = dist(cl.center, cl.nests[i])
					T.truthy(
						d >= 8 - 1e-9 and d <= 8.6 + 1e-9 or i > 3,
						string.format("%s 가운데~둥지%d %.2f", b.id, i, d)
					)
				end
				-- 경비 집 · 표지판 · 장식 · 둥지가 서로 안 겹침
				for i, n in cl.nests do
					-- 65번: 경비는 모든 둥지보다 벽 쪽(-x) · 가장 가까운 둥지와도 둥지 파트·경비 몸(4)이 안 겹침 (8 이상)
					T.truthy(cl.guard.x < n.x, b.id .. " 경비 집이 둥지" .. i .. " 보다 벽 쪽")
					T.truthy(dist(n, cl.guard) >= 8, b.id .. " 경비 집~둥지" .. i .. " " .. dist(n, cl.guard))
					T.truthy(dist(n, cl.sign) >= 12, b.id .. " 표지판~둥지" .. i .. " " .. dist(n, cl.sign))
					for k, d in cl.decor do
						T.truthy(dist(n, d) >= 9, b.id .. " 장식" .. k .. "~둥지" .. i .. " " .. dist(n, d))
					end
				end
				T.truthy(
					dist(cl.guard, cl.sign) >= 30,
					b.id .. " 경비 집~표지판 (65번: 거대 경비 겉모습 밖)"
				)
				for k, d in cl.decor do
					T.truthy(
						dist(cl.guard, d) >= 25,
						b.id .. " 경비 집~장식" .. k .. " (65번: 거대 경비 겉모습 밖)"
					)
					T.truthy(dist(cl.sign, d) >= 20, b.id .. " 표지판~장식" .. k)
				end
				for k, spot in { cl.guard, cl.sign, cl.decor[1], cl.decor[2] } do
					T.eq(MapLayout.zoneAt(spot.z), b.id)
					-- 65번: 경비 집만 벽에서 10 (무리의 벽 쪽), 나머지는 12 이상
					T.truthy(
						math.abs(spot.x) <= MapLayout.HALF_WIDTH - (if k == 1 then 10 else 12),
						b.id .. " 벽 안쪽"
					)
					T.truthy(b.zMax - spot.z >= 20, b.id .. " 다음 구역 경계에서 20 이상")
				end
				-- 이웃 구역과도 안 겹침: 다음 구역 입구 아치(zMin + 10) 에서 멂
				if b.index < MapLayout.BIOME_COUNT then
					for _, n in cl.nests do
						T.truthy(MapLayout.biomes[b.index + 1].zMin + 10 - n.z >= 39 - 1e-9)
					end
				end
			end
			T.eq(total, 105)
			T.eq(MapLayout.nestCluster("nope"), nil)
			T.eq(#MapLayout.nestsFor("nope"), 0)
			T.eq(MapLayout.guardHome("nope"), nil)
			-- 벚꽃 구역 사쿠라 나무는 둥지 무리·경비 집과 멀리 떨어져 있음 (크리스탈은 둥지 둘레 5~9)
			local tree = MapLayout.specials.sakuraIncubator
			local cl = MapLayout.nestCluster(tree.biomeId)
			T.eq(MapLayout.zoneAt(tree.z), tree.biomeId)
			for _, n in cl.nests do
				T.truthy(dist(tree, n) >= 60, "사쿠라 나무~둥지")
			end
			for _, n in cl.nests do
				-- 크리스탈이 둥지 둘레 9 까지 떨어져도 복도 안·구역 안
				T.truthy(math.abs(n.x) + 9 <= MapLayout.HALF_WIDTH)
				T.truthy(MapLayout.zoneAt(n.z + 9) == tree.biomeId)
			end
		end
	)

	-- 1~18구역 좌표 · 추천/경비 속도 · 베이스 7개 · 허브 · 특수 장소가 7판(800aba5 의 부모) 코드와 같음.
	-- (8판에서 일부러 바뀐 둥지 자리·경비 집은 뺌) 7판 코드로 뽑은 글의 길이와 해시:
	local function serialize(v)
		local kind = type(v)
		if kind == "number" then
			return string.format("%.6g", v)
		elseif kind == "string" then
			return string.format("%q", v)
		elseif kind == "boolean" then
			return tostring(v)
		elseif kind == "table" then
			local keys = {}
			for k in v do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			local parts = {}
			for _, k in keys do
				if type(v[k]) ~= "function" then
					table.insert(parts, tostring(k) .. "=" .. serialize(v[k]))
				end
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return "nil"
	end

	T.test(
		"1~18구역 좌표·추천 속도·경비 속도·이름·등급 가중치와 베이스 7개·허브·사쿠라 나무·밤 벽이 7판과 한 글자도 안 다름 (21구역으로 늘어도)",
		function()
			local parts = {}
			for i = 1, 18 do
				local b = MapLayout.biomes[i]
				table.insert(parts, "Z" .. i .. serialize(b))
				local bi = Biomes.list[i]
				table.insert(parts, "B" .. i .. serialize({
					id = bi.id,
					order = bi.order,
					name = bi.name,
					nameEn = bi.nameEn,
					rec = bi.recommendedSpeed,
					guard = bi.guardName,
					guardSpeed = bi.guardSpeed,
					weapon = bi.weapon,
					sides = bi.sides,
					color = bi.color,
				}))
				local weights = EggSpawn.BIOME_RARITY_WEIGHTS[bi.id]
				if i == 18 then
					-- 2026-11-10 (사장님): 18구역의 해커 글리치 5% 를 보통 추첨에서 뺌 → 일부러 바뀜 (새 값은 data.spec 이 봄).
					--   해시는 7판 글자 그대로를 지키려고 7판 표를 직접 적음
					weights = { developer = 40, ultradivine = 55, hacker_glitch = 5 }
				end
				table.insert(parts, "W" .. i .. serialize(weights))
			end
			for i = 1, 7 do
				table.insert(parts, "P" .. i .. serialize(MapLayout.plot(i)))
			end
			table.insert(parts, "HS" .. serialize(MapLayout.hubSpots))
			table.insert(parts, "SP" .. serialize(MapLayout.specials))
			table.insert(parts, "HUB" .. serialize(MapLayout.HUB))
			table.insert(parts, "NW" .. serialize(MapLayout.NIGHT_WALL))
			table.insert(parts, "K" .. serialize({
				MapLayout.SAFE_ZONE_Z,
				MapLayout.HALF_WIDTH,
				MapLayout.WALL_HEIGHT,
				MapLayout.FLOOR_Y,
				MapLayout.BIOME_LENGTH,
				MapLayout.CORRIDOR_WIDTH,
				MapLayout.TREADMILL_PAD,
				MapLayout.PEN_LOCAL,
			}))
			local text = table.concat(parts, "|")
			local h = 5381
			for i = 1, #text do
				h = (h * 33 + string.byte(text, i)) % 4294967296
			end
			T.eq(#text, 8447, "7판(67945ab) 코드로 뽑은 글 길이")
			T.eq(h, 2981177035, "7판 코드로 뽑은 해시")
		end
	)

	T.test(
		"구역 19~21: 식물 8종씩·가중치 합 100·맵 끝 5040·zoneAt 경계·isInHub 범위(허브 -300~0)·마지막 구역 끝, 해커 글리치 특별 추첨은 마지막 구역(21)에서만 (2026-11-10, 0.0001%)",
		function()
			T.eq(MapLayout.MAP_END_Z, 5040)
			T.eq(MapLayout.BIOME_COUNT, 21)
			T.eq(MapLayout.zoneAt(0), "forest")
			T.eq(MapLayout.zoneAt(4320), "robot_factory")
			T.eq(MapLayout.zoneAt(4559.99), "robot_factory")
			T.eq(MapLayout.zoneAt(4560), "clock_tower")
			T.eq(MapLayout.zoneAt(4800), "rainbow_sky")
			T.eq(MapLayout.zoneAt(5039.99), "rainbow_sky")
			T.eq(MapLayout.zoneAt(5040), nil, "맵 끝")
			T.eq(MapLayout.zoneAt(math.huge), nil)
			T.eq(MapLayout.zoneAt(-math.huge), nil)
			T.eq(MapLayout.zoneAt(0 / 0), nil)
			T.eq(MapLayout.zoneAt(-0.001), "hub")
			-- 허브(안전 구역)는 z < 0 만 (구역 19~21 에서 isInHub 가 새지 않음)
			for _, z in { 0, 1, 100, 1000, 4320, 4800, 5039 } do
				T.falsy(MapLayout.isInHub({ x = 0, z = z }), "z=" .. z)
			end
			for _, z in { -0.001, -100, -290 } do
				T.truthy(MapLayout.isInHub({ x = 0, z = z }), "z=" .. z)
			end
			local rng = T.rng(8080)
			for _, id in { "robot_factory", "clock_tower", "rainbow_sky" } do
				local list = Plants.inBiome(id)
				T.eq(#list, 8, id)
				local weights = EggSpawn.BIOME_RARITY_WEIGHTS[id]
				local sum = 0
				for _, w in weights do
					sum += w
				end
				T.eq(sum, 100, id)
				-- 추첨: 가중치가 0 인 등급은 안 나오고, 나온 등급은 전부 풀에 있음
				local counts, n = {}, 20000
				for _ = 1, n do
					local pet = EggRoll.rollNestPet(id, nil, rng)
					T.truthy(pet ~= nil and pet.biome == id)
					counts[pet.rarity] = (counts[pet.rarity] or 0) + 1
				end
				for rarity, w in weights do
					T.near((counts[rarity] or 0) / n * 100, w, 1.5, id .. " " .. rarity)
				end
				for rarity in counts do
					T.truthy(weights[rarity] ~= nil, id .. " 에서 나오면 안 되는 등급 " .. rarity)
				end
			end
			-- 해커 글리치 특별 추첨 (구역마다 4만 번): 2026-11-10 마지막 구역(21 rainbow_sky) 만
			--   8판 추가 (사장님 2026-11-09): 0.5% → 0.0001% (2026-11-10) — 4만 번이면 기대 0.04번 (경계·1e7번은 eggroll.spec)
			for _, b in Biomes.list do
				local hits = 0
				for _ = 1, 40000 do
					local specials = EggRoll.rollSpecials(b.id, "light", rng)
					T.truthy(#specials <= EggSpawn.MAX_SPECIALS_PER_BIOME)
					for _, pet in specials do
						if pet.rarity == "hacker_glitch" then
							hits += 1
						end
					end
				end
				if b.id == "rainbow_sky" then
					T.truthy(hits <= 2, b.id .. " 해커 글리치 특별 씨앗 " .. hits .. " (기대 0.04)")
					local first = EggRoll.rollSpecials(b.id, "light", T.constant(0))[1]
					T.eq(first and first.rarity, "hacker_glitch", b.id .. " 난수 0 이면 해커 글리치")
				else
					T.eq(hits, 0, b.id .. " 에는 해커 글리치 특별 씨앗이 없음 (마지막 구역만)")
					for _, pet in EggRoll.rollSpecials(b.id, "light", T.constant(0)) do
						T.truthy(pet.rarity ~= "hacker_glitch", b.id .. " 난수 0 이어도 해커 글리치 아님")
					end
				end
			end
		end
	)

	T.test(
		"/zone 19 20 21 은 구역 입구로 순간이동 + ZoneEntered(새 구역 id·이름), 22·0·음수·글자는 무시 / 밤이 되면 맨 끝 구역(무지개 하늘섬 z=5030)에 있던 사람도 허브로 돌아옴",
		function()
			local H = ServerHarness.install(Loader, T)
			local ok, err = pcall(function()
				H.startNet()
				H.server("Services/SakuraService")
				local BaseService = H.server("Services/BaseService")
				BaseService.start()
				H.RunService.studio = true
				local DevCommands = H.server("Services/DevCommands")
				DevCommands.start()
				local p = H.newPlayer(9501, "Dev8")
				local session = H.login(p)
				session.plotIndex = 1
				H.Players.PlayerAdded:Fire(p)
				H.spawn(p, 0, 3, 0)
				local names = { [19] = "robot_factory", [20] = "clock_tower", [21] = "rainbow_sky" }
				for n = 19, 21 do
					p.Chatted:Fire("/zone " .. n)
					T.eq(p.Character.root.Position.Z, (n - 1) * 240 + 12, "/zone " .. n)
					H.advance(0.3)
					T.eq(session.currentZone, names[n])
				end
				local entered = H.sent(p, "ZoneEntered")
				T.eq(entered[#entered][1].biomeId, "rainbow_sky")
				T.eq(entered[#entered][1].name, "무지개 하늘섬")
				T.eq(entered[#entered][1].nameEn, "Rainbow Sky Islands")
				p.Chatted:Fire("/zone rainbow_sky")
				local z = p.Character.root.Position.Z
				for _, bad in { "/zone 22", "/zone 0", "/zone -1", "/zone nan", "/zone 1e999", "/zone abc", "/zone" } do
					p.Chatted:Fire(bad)
					T.eq(p.Character.root.Position.Z, z, bad .. " 은 무시")
				end
				-- 밤: 맨 끝 구역에서 허브로
				H.teleport(p, 0, 3, 5030)
				H.setPhase("Night")
				T.truthy(
					MapLayout.isInHub(p.Character.root.Position),
					"허브로 돌아옴 z=" .. p.Character.root.Position.Z
				)
				for _, text in H.warnings do
					T.truthy(string.find(text, "TextChatCommand", 1, true) ~= nil, "뜻밖의 warn: " .. tostring(text))
				end
			end)
			H.uninstall()
			if not ok then
				error(err, 0)
			end
		end
	)

	------------------------------------------------------------------
	T.suite("8판 주임 검수 D: 식물 크기 · 정원 간격")

	local SIZE_IDS = { "normal", "big", "huge", "giant" }
	local firstPlantOf = {} -- 등급 id → 그 등급 첫 식물 id
	for _, plant in Plants.list do
		if not firstPlantOf[plant.rarity] then
			firstPlantOf[plant.rarity] = plant.id
		end
	end

	T.test(
		"등급 16개 × 크기 4가지 전부: 서버 PlaceEgg 를 18번 해서 정원 18칸이 다 들어가고(8판 추가: 거대 식물은 1그루 + 둘째 거부, 나머지 17 은 울트라디바인), 나란히 심은 식물끼리 간격(gap) 이상 떨어져 있음, 18번째 다음은 '가득 참'",
		function()
			inWorld(nil, function(H)
				local BaseService = H.server("Services/BaseService")
				BaseService.start()
				local p = H.newPlayer(8801, "Planter")
				local session, data = H.login(p)
				session.plotIndex = 1
				local plot = MapLayout.plot(1)
				H.spawn(p, plot.spawn.x, 3, plot.spawn.z)
				data.penLevel = Upgrades.PEN_MAX_LEVEL
				T.eq(GardenRules.capacity(data.penLevel), 18)
				for _, rarity in Rarities.list do
					local petId = firstPlantOf[rarity.id]
					T.truthy(petId ~= nil, rarity.id)
					for _, size in SIZE_IDS do
						data.incubators = {}
						data.pets = {}
						data.eggs = {}
						local placed = {}
						-- 8판 추가 (2026-11-09): 거대 식물(해커 글리치)은 정원에 1그루 → 2번째부터는 울트라디바인(같은 크기)
						local lobby = GardenRules.isLobbyFill(petId)
						for i = 1, 18 do
							local thisPet = if lobby and i > 1 then firstPlantOf.ultradivine else petId
							T.truthy(
								BaseService.grantEgg(p, thisPet, size, {}, "dev") ~= nil,
								rarity.id .. " " .. size .. " 씨앗 받기"
							)
							local egg = data.eggs[#data.eggs]
							local spot = EggPlacement.firstFreeGrid(size, placed, thisPet)
							T.truthy(spot ~= nil, string.format("%s %s: %d번째 자리가 없음", rarity.id, size, i))
							if not spot then
								break
							end
							local w = MapLayout.toWorld(1, spot.x, spot.z)
							if lobby and i == 2 then
								BaseService.grantEgg(p, petId, size, {}, "dev")
								local second = data.eggs[#data.eggs]
								T.falsy(
									BaseService.placeEgg(p, second.uid, w.x, w.z),
									rarity.id .. " " .. size .. " 둘째 거대 식물"
								)
								T.truthy(H.hasNotify(p, "error", "거대 식물은 정원에 하나만"))
							end
							T.truthy(
								BaseService.placeEgg(p, egg.uid, w.x, w.z),
								string.format(
									"%s %s: 서버 PlaceEgg %d번째 거부 (%s)",
									rarity.id,
									size,
									i,
									tostring(H.lastNotify(p) and H.lastNotify(p).text)
								)
							)
							table.insert(placed, { x = spot.x, z = spot.z, size = size, petId = thisPet })
						end
						T.eq(#data.incubators, 18, rarity.id .. " " .. size)
						-- 19번째는 정원이 가득 차서 거부
						BaseService.grantEgg(p, petId, size, {}, "dev")
						local extra = data.eggs[#data.eggs]
						local w = MapLayout.toWorld(1, -33, -28)
						T.falsy(BaseService.placeEgg(p, extra.uid, w.x, w.z), "19번째")
						T.eq(#data.incubators, 18)
						-- 서로 간격(gap) 이상
						for i = 1, #placed do
							for j = i + 1, #placed do
								local gap = EggPlacement.gap(size, size, placed[i].petId, placed[j].petId)
								local d = math.sqrt((placed[i].x - placed[j].x) ^ 2 + (placed[i].z - placed[j].z) ^ 2)
								T.truthy(
									d >= gap - 1e-9,
									string.format("%s %s: %d~%d 간격 %.2f < %.2f", rarity.id, size, i, j, d, gap)
								)
							end
							T.truthy(
								MapLayout.isInPenLocal(placed[i].x, placed[i].z, Config.EGG_PLACE_FENCE_MARGIN),
								"정원 안"
							)
						end
					end
				end
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"섞어 심기: 무작위 등급·크기 18그루 시퀀스 60개를 firstFreeGrid 로 심으면 한 번도 자리가 모자라지 않음 (큰 것·작은 것 번갈아도)",
		function()
			local rng = T.rng(808)
			local rarityIds = {}
			for _, r in Rarities.list do
				table.insert(rarityIds, r.id)
			end
			local function runSequence(pickFn)
				local placed = {}
				for i = 1, 18 do
					local petId, size = pickFn(i)
					local spot = EggPlacement.firstFreeGrid(size, placed, petId)
					if not spot then
						return false, i
					end
					table.insert(placed, { x = spot.x, z = spot.z, size = size, petId = petId })
				end
				return true
			end
			for s = 1, 60 do
				local ok, at = runSequence(function()
					local rarity = rarityIds[math.floor(rng() * #rarityIds) + 1]
					return firstPlantOf[rarity], SIZE_IDS[math.floor(rng() * 4) + 1]
				end)
				T.truthy(ok, "무작위 시퀀스 " .. s .. ": " .. tostring(at) .. "번째 자리 없음")
			end
			-- 작은 것(일반)과 가장 큰 것(해커 글리치 초거대) 번갈아
			for _, order in { 0, 1 } do
				local ok, at = runSequence(function(i)
					if (i + order) % 2 == 0 then
						return firstPlantOf.common, "normal"
					end
					return firstPlantOf.hacker_glitch, "giant"
				end)
				T.truthy(ok, "번갈아 심기 " .. order .. ": " .. tostring(at) .. "번째")
			end
			-- 작은 것 17그루 뒤에 큰 것 하나 / 큰 것 17그루 뒤에 작은 것 하나
			T.truthy(runSequence(function(i)
				if i < 18 then
					return firstPlantOf.common, "normal"
				end
				return firstPlantOf.hacker_glitch, "giant"
			end))
			T.truthy(runSequence(function(i)
				if i < 18 then
					return firstPlantOf.hacker_glitch, "giant"
				end
				return firstPlantOf.common, "normal"
			end))
		end
	)

	T.test(
		"겹침: 두 식물이 안 겹치는 간격(gap ≥ 성체 폭 평균) — 겹칠 수 있는 건 성체 폭 평균이 상한 14 를 넘는 큰 등급 조합뿐 (8판 추가 곡선 1 → 6: 함께 심을 수 있는 조합 중 최대 겹침 = 울트라디바인 초거대 ↔ 해커 글리치 초거대 약 9.7, 일반 등급은 안 겹침)",
		function()
			local combos = {}
			for _, r in Rarities.list do
				for _, size in SIZE_IDS do
					table.insert(combos, { petId = firstPlantOf[r.id], size = size, rarity = r.id })
				end
			end
			T.eq(#combos, 64)
			local overlapping, worst = {}, 0
			for i, a in combos do
				local fa = EggPlacement.footprint(a.petId, a.size)
				-- 폭은 단조: 등급·크기가 크면 폭도 큼
				T.near(
					fa,
					Config.PLANT_FOOTPRINT * Config.RARITY_PLANT_SCALE[a.rarity] * Config.PLANT_SIZE_SCALE[a.size],
					1e-9
				)
				for j = i, #combos do
					local b = combos[j]
					local gap = EggPlacement.gap(a.size, b.size, a.petId, b.petId)
					local avg = (fa + EggPlacement.footprint(b.petId, b.size)) / 2
					T.truthy(gap >= 4 - 1e-9 and gap <= Config.PLANT_GAP_MAX + 1e-9, "gap 범위 " .. gap)
					T.near(
						gap,
						EggPlacement.gap(b.size, a.size, b.petId, a.petId),
						1e-9,
						"gap 은 순서와 상관없음"
					)
					if gap < avg - 1e-9 then
						-- 겹치는 조합: 폭 평균이 상한 14 를 넘어서 상한에 걸린 경우뿐이어야 함
						T.truthy(
							avg > Config.PLANT_GAP_MAX,
							string.format(
								"%s %s ↔ %s %s: gap %.2f < 폭 %.2f 인데 상한이 아님",
								a.rarity,
								a.size,
								b.rarity,
								b.size,
								gap,
								avg
							)
						)
						T.near(gap, Config.PLANT_GAP_MAX, 1e-9)
						-- 8판 추가: 거대 식물끼리는 한 정원에 같이 못 심음 (1그루) → 최대 겹침에서 뺌
						if not (GardenRules.isLobbyFill(a.petId) and GardenRules.isLobbyFill(b.petId)) then
							worst = math.max(worst, avg - gap)
						end
						overlapping[a.rarity .. ":" .. a.size] = true
						overlapping[b.rarity .. ":" .. b.size] = true
					end
				end
			end
			local names = {}
			for k in overlapping do
				table.insert(names, k)
			end
			table.sort(names)
			print(
				"      (참고) 겹칠 수 있는 크기 조합 "
					.. #names
					.. "개 (일반 등급 4개만 빼고) — 함께 심을 수 있는 것 중 최대 겹침 "
					.. string.format("%.2f 스터드 (모양만, CanCollide false)", worst)
			)
			local P, R, S = Config.PLANT_FOOTPRINT, Config.RARITY_PLANT_SCALE, Config.PLANT_SIZE_SCALE
			local expectWorst = (P * R.ultradivine * S.giant + P * R.hacker_glitch * S.giant) / 2 - Config.PLANT_GAP_MAX
			T.near(
				worst,
				expectWorst,
				1e-9,
				"최대 겹침 = 울트라디바인 초거대 ↔ 해커 글리치 초거대"
			)
			T.truthy(worst <= 10, "겹침 최대 " .. worst)
			for _, size in SIZE_IDS do
				T.falsy(overlapping["common:" .. size], "일반 " .. size .. " 은 누구와도 안 겹침")
			end
		end
	)

	T.test(
		"저장 불러오기: 새 간격으로 심은 18그루(해커 글리치 초거대)·7판 간격으로 빽빽이 심은 옛 정원 18그루는 불러와도 하나도 안 팔리고 코인도 그대로, 좌표가 깨진 식물 하나는 빈 자리를 찾음(또는 팔림)",
		function()
			inWorld(nil, function(H)
				local DataSchema = H.server("Logic/DataSchema")
				local function build(petId, size, spacingPetId)
					local raw = DataSchema.default(0)
					raw.penLevel = Upgrades.PEN_MAX_LEVEL
					raw.pets = {}
					local placed = {}
					for i = 1, 18 do
						local spot = EggPlacement.firstFreeGrid(size, placed, spacingPetId)
						table.insert(placed, { x = spot.x, z = spot.z, size = size, petId = spacingPetId })
						table.insert(raw.pets, {
							uid = "p" .. i,
							petId = petId,
							size = size,
							mutations = {},
							x = spot.x,
							z = spot.z,
							fruits = 1,
							fruitProgress = 0,
						})
					end
					return raw
				end
				local glitch = firstPlantOf.hacker_glitch
				-- (1) 새 간격으로 심은 18그루
				local raw = build(glitch, "giant", glitch)
				local before = raw.money
				local fixed = DataSchema.reconcile(raw, 0)
				T.eq(#fixed.pets, 18, "새 간격 18그루 그대로")
				T.eq(fixed.money, before, "팔려서 코인이 되지 않음")
				for i, r in fixed.pets do
					T.eq(r.x, raw.pets[i].x)
					T.eq(r.z, raw.pets[i].z)
				end
				-- (2) 7판 간격(식물 폭 무시)으로 빽빽한 옛 정원
				raw = build(glitch, "giant", nil)
				fixed = DataSchema.reconcile(raw, 0)
				T.eq(#fixed.pets, 18, "7판 간격 옛 정원 18그루 그대로")
				T.eq(fixed.money, raw.money)
				-- (3) 자라는 씨앗도 같음
				raw = DataSchema.default(0)
				raw.penLevel = Upgrades.PEN_MAX_LEVEL
				raw.incubators = {}
				local placed = {}
				for i = 1, 18 do
					local spot = EggPlacement.firstFreeGrid("giant", placed, nil)
					table.insert(placed, { x = spot.x, z = spot.z, size = "giant" })
					table.insert(raw.incubators, {
						uid = "i" .. i,
						petId = glitch,
						size = "giant",
						mutations = {},
						biomeId = "bug_dimension",
						special = false,
						x = spot.x,
						z = spot.z,
						progress = 10,
						required = Economy.growSeconds(glitch),
					})
				end
				fixed = DataSchema.reconcile(raw, 0)
				T.eq(#fixed.incubators, 18, "옛 자라는 씨앗 18개 그대로")
				T.eq(#fixed.eggs, 0, "가방으로 쫓겨나지 않음")
				-- (4) 좌표가 깨진 식물 하나: 옛 빽빽한 17그루 사이에서 새 간격으로 빈 자리를 찾음. 못 찾으면 팔림(참고)
				raw = build(glitch, "giant", nil)
				raw.pets[18].x = nil
				raw.pets[18].z = nil
				fixed = DataSchema.reconcile(raw, 0)
				print(
					string.format(
						"      (참고) 좌표 깨진 해커 글리치 초거대 1그루 + 옛 빽빽한 17그루: 남은 식물 %d, 팔린 코인 %s",
						#fixed.pets,
						tostring(fixed.money - raw.money)
					)
				)
				T.truthy(#fixed.pets >= 17, "깨진 한 그루 때문에 다른 식물이 팔리면 안 됨")
				T.truthy(fixed.money >= raw.money)
			end)
		end
	)

	T.test(
		"자라면서 점점 커짐: 182종 × 4크기 × 진행도 0~100%에서 plantScale 이 줄어들지 않고 0.3 × 등급 × 크기 → 등급 × 크기 로 이어짐, 필수 단계 값(0.3 · 0.55 · 0.8 · 1)에서 STAGE_SCALE 과 같음, 이상한 값에도 유한",
		function()
			for _, plant in Plants.list do
				for _, size in SIZE_IDS do
					local full = GardenRules.plantScale(plant.id, size)
					T.near(
						full,
						GardenRules.rarityScale(plant.rarity) * Config.PLANT_SIZE_SCALE[size], -- 8판 추가: 모양용 (거대 식물 = LOBBY_FILL_SCALE)
						1e-9,
						plant.id
					)
					local prev = 0
					for step = 0, 100 do
						local s = GardenRules.plantScale(plant.id, size, step, 100)
						T.truthy(s >= prev - 1e-12, plant.id .. " " .. size .. " 줄어듦 " .. step)
						T.truthy(
							s >= 0.3 * GardenRules.rarityScale(plant.rarity) * Config.PLANT_SIZE_SCALE[size] - 1e-9
						)
						T.truthy(s <= full + 1e-9)
						prev = s
					end
					T.near(GardenRules.plantScale(plant.id, size, 100, 100), full, 1e-9)
				end
			end
			for _, junk in { 0 / 0, math.huge, -math.huge, -5, 1e308 } do
				for _, req in { 0 / 0, 0, -1, math.huge, 100 } do
					local s = GardenRules.growthScale(junk, req)
					T.truthy(
						finite(s) and s >= 0.3 - 1e-12 and s <= 1 + 1e-12,
						string.format("growthScale(%s, %s) = %s", junk, req, tostring(s))
					)
				end
			end
		end
	)

	T.test(
		"참고: 사람이 손으로(아무 데나 눌러서) 가장 큰 보통 등급(울트라디바인 — 8판 추가: 해커 글리치는 1그루만) 보통/초거대를 심으면 18칸 중 몇 그루나 들어가나 (firstFreeGrid 자동 자리는 18칸 다 됨)",
		function()
			local rng = T.rng(4242)
			local penXMin = MapLayout.PEN_LOCAL.xMin + Config.EGG_PLACE_FENCE_MARGIN
			local penXMax = MapLayout.PEN_LOCAL.xMax - Config.EGG_PLACE_FENCE_MARGIN
			local penZMin = MapLayout.PEN_LOCAL.zMin + Config.EGG_PLACE_FENCE_MARGIN
			local penZMax = MapLayout.PEN_LOCAL.zMax - Config.EGG_PLACE_FENCE_MARGIN
			local glitch = firstPlantOf.ultradivine -- 8판 추가: 거대 식물은 정원에 1그루라 울트라디바인으로
			for _, size in { "normal", "giant" } do
				local total, best, worst = 0, 0, 99
				local trials = 100
				for _ = 1, trials do
					local placed = {}
					local misses = 0
					while #placed < 18 and misses < 40 do
						local x = EggPlacement.round(penXMin + rng() * (penXMax - penXMin))
						local z = EggPlacement.round(penZMin + rng() * (penZMax - penZMin))
						if EggPlacement.check(x, z, size, placed, nil, glitch) then
							table.insert(placed, { x = x, z = z, size = size, petId = glitch })
							misses = 0
						else
							misses += 1
						end
					end
					total += #placed
					best = math.max(best, #placed)
					worst = math.min(worst, #placed)
				end
				print(
					string.format(
						"      (참고) 울트라디바인 %s 를 아무 데나 눌러 심으면 평균 %.1f그루 (최소 %d · 최대 %d) / 18칸 — 자동 자리(firstFreeGrid)는 18",
						size,
						total / trials,
						worst,
						best
					)
				)
				T.truthy(total / trials >= 5, "너무 적게 들어감")
			end
		end
	)

	------------------------------------------------------------------
	T.suite("8판 주임 검수 E: 러닝머신 (가격표 · 터치 신호)")

	T.test(
		"러닝머신 가격표: docs/GAME_DESIGN.md 9-2 표의 20레벨 가격·걸음당 속도·1초 속도가 코드(Upgrades.Treadmill · Economy)와 같고, nextTreadmillCost/touchInfo 가 레벨 0~20 에서 맞음 (20이면 maxed)",
		function()
			local fs = require("@lune/fs")
			local text = fs.readFile("docs/GAME_DESIGN.md")
			local lines = string.split(text, "\n")
			local start
			for i, line in lines do
				if string.sub(line, 1, 8) == "### 9-2." then
					start = i
					break
				end
			end
			T.truthy(start ~= nil, "docs 에 9-2 표가 없음")
			local UNIT = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, Qa = 1e15, Qi = 1e18 }
			local rows = {}
			for i = start, math.min(start + 40, #lines) do
				local level, cost, step, perSecond = string.match(lines[i], "^| (%d+) | (.-) | (.-) | (.-) |")
				if level then
					local number, unit = string.match(cost, "%$([%d%.]+)(%a*)")
					local stepNumber = string.gsub(string.match(step, "[%d,]+"), ",", "")
					local perSecondNumber = string.gsub(string.match(perSecond, "[%d,]+"), ",", "")
					rows[tonumber(level)] = {
						cost = tonumber(number) * (if unit == "" then 1 else UNIT[unit]),
						step = tonumber(stepNumber),
						perSecond = tonumber(perSecondNumber),
					}
				end
			end
			T.eq(#rows, 20, "표에서 읽은 줄 수")
			for level = 1, 20 do
				local row = rows[level]
				local entry = Upgrades.Treadmill[level]
				T.near(entry.cost, row.cost, row.cost * 1e-12, level .. "레벨 가격")
				T.eq(entry.perStep, row.step, level .. "레벨 걸음당")
				T.eq(Economy.treadmillGainPerSecond(level), row.perSecond, level .. "레벨 1초 속도")
			end
			-- 레벨 0 ~ 20 의 업그레이드 창 정보
			local TreadmillService = nil
			inWorld(nil, function(H)
				TreadmillService = H.server("Services/TreadmillService")
				local prevGain = -1
				for level = 0, 20 do
					local info = TreadmillService.touchInfo(level)
					T.eq(info.level, level)
					T.eq(info.maxed, level == 20, "레벨 " .. level)
					T.eq(info.gainPerSecond, if level == 0 then 0 else rows[level].perSecond)
					T.truthy(info.gainPerSecond > prevGain, "1초 속도가 레벨마다 커짐")
					prevGain = info.gainPerSecond
					if level < 20 then
						T.eq(info.nextLevel, level + 1)
						T.near(info.nextCost, rows[level + 1].cost, rows[level + 1].cost * 1e-12)
						T.eq(info.nextCost, Economy.nextTreadmillCost(level))
						T.eq(info.nextGainPerSecond, rows[level + 1].perSecond)
					else
						T.eq(info.nextLevel, nil)
						T.eq(info.nextCost, nil)
						T.eq(info.nextGainPerSecond, nil)
						T.eq(info.gainPerSecond, 1000000)
					end
				end
				T.eq(Economy.nextTreadmillCost(20), nil)
				T.eq(Economy.nextTreadmillCost(25), nil)
				T.eq(Economy.nextTreadmillCost(0), 500)
			end)
			-- 가격은 레벨마다 오르기만 함 (싸지는 레벨 없음)
			for level = 2, 20 do
				T.truthy(Upgrades.Treadmill[level].cost > Upgrades.Treadmill[level - 1].cost, level .. "레벨")
			end
		end
	)

	local function treadmillWorld(H, level, money)
		local w = {}
		w.TreadmillService = H.server("Services/TreadmillService")
		w.TreadmillService.start()
		w.UpgradeService = H.server("Services/UpgradeService")
		w.UpgradeService.start()
		w.p = H.newPlayer(8601, "Tread")
		w.session, w.data = H.login(w.p)
		w.session.plotIndex = 1
		w.data.treadmillLevel = level
		w.data.money = money or 0
		w.plot = MapLayout.plot(1)
		H.spawn(w.p, w.plot.spawn.x, 3, w.plot.spawn.z)
		H.advance(0.4)
		return w
	end

	T.test(
		"올라설 때마다 TreadmillTouched 정확히 1번 (0레벨·중간·20레벨 모두), 내릴 때 Attr false, 10번 오르내리면 10번, 서 있는 동안·점프·착지에는 안 보냄",
		function()
			inWorld(nil, function(H)
				local w = treadmillWorld(H, 0)
				local p, plot = w.p, w.plot
				local function sample(seconds, label)
					-- Attr 가 깜빡이는지: 0.05초마다 읽어 바뀐 횟수를 셈
					local changes, last = 0, p.attrs.TreadmillTouching
					local t = 0
					while t < seconds - 1e-9 do
						H.advance(0.05)
						t += 0.05
						if p.attrs.TreadmillTouching ~= last then
							changes += 1
							last = p.attrs.TreadmillTouching
						end
					end
					return changes
				end
				for _, row in { { 0, 1 }, { 3, 2 }, { 20, 3 } } do
					local level, count = row[1], row[2]
					w.data.treadmillLevel = level
					for i = 1, 10 do
						H.teleport(p, plot.treadmill.x + plot.facing * 12, 3, plot.treadmill.z)
						H.advance(0.4)
						T.eq(p.attrs.TreadmillTouching or false, false, "벨트 밖")
						H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z)
						H.advance(0.4)
						T.eq(p.attrs.TreadmillTouching, true)
					end
					T.eq(
						#H.sent(p, "TreadmillTouched"),
						10 * count,
						"레벨 " .. level .. ": 오를 때마다 정확히 1번씩"
					)
					local list = H.sent(p, "TreadmillTouched")
					T.eq(list[#list][1].level, level)
					T.eq(list[#list][1].maxed, level == 20)
				end
				-- 벨트 위에서 5초 서 있기 + 점프 3번: Attr 가 한 번도 안 깜빡임
				w.data.treadmillLevel = 3
				H.teleport(p, plot.treadmill.x + plot.facing * 12, 3, plot.treadmill.z)
				H.advance(0.4)
				local sentBefore = #H.sent(p, "TreadmillTouched")
				H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z)
				H.advance(0.4)
				T.eq(#H.sent(p, "TreadmillTouched"), sentBefore + 1)
				local flicker = sample(1, "서 있기")
				for _ = 1, 3 do
					H.teleport(p, plot.treadmill.x, 14, plot.treadmill.z) -- 점프 (몸통이 8 보다 높이 뜸 → 서버가 내려 줌)
					flicker += sample(0.45, "점프")
					H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z) -- 착지
					flicker += sample(0.45, "착지")
				end
				T.eq(flicker, 0, "점프해도 TreadmillTouching 이 안 깜빡임")
				T.eq(#H.sent(p, "TreadmillTouched"), sentBefore + 1, "점프로 다시 보내지 않음")
				T.eq(p.attrs.TreadmillTouching, true)
				-- 클라 경로: 점프 입력 → TreadmillLeave → 서버가 벨트 옆으로 내려 줌 (Attr false, 2026-11-10: 앞은 표지판) → 다시 올라서면 TreadmillTouched 1번 + 바로 탐
				H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z)
				H.advance(0.4)
				T.eq(p.attrs.OnTreadmill, true)
				H.client(p, "TreadmillLeave")
				H.advance(0.4)
				T.eq(p.attrs.OnTreadmill, false, "TreadmillLeave 로 내림")
				T.eq(p.attrs.TreadmillTouching, false, "벨트 옆으로 내려서 창 닫기")
				H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z)
				H.advance(0.4)
				T.eq(p.attrs.OnTreadmill, true)
				T.eq(#H.sent(p, "TreadmillTouched"), sentBefore + 2)
				-- 죽으면 Attr false, 되살아나 다시 올라서면 또 1번
				p.Character.humanoid.Health = 0
				H.advance(0.4)
				T.eq(p.attrs.TreadmillTouching, false, "죽으면 창 닫기")
				p.Character.humanoid.Health = 100
				H.advance(0.4)
				T.eq(#H.sent(p, "TreadmillTouched"), sentBefore + 3, "살아나서 아직 벨트 위면 다시 1번")
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"0레벨에서 사기: 코인 499 면 거절(안 탐·창 신호 그대로), 500 이면 해금 → 내려오지 않아도 다음 틱에 바로 타고 1초 뒤 +8 속도, 벨트 밖에서 사도 되고 그 뒤 올라서면 바로 탐",
		function()
			inWorld(nil, function(H)
				local w = treadmillWorld(H, 0, 499)
				local p, plot, data = w.p, w.plot, w.data
				H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z)
				H.advance(0.4)
				T.eq(#H.sent(p, "TreadmillTouched"), 1)
				H.client(p, "PurchaseUpgrade", "Treadmill")
				T.eq(data.treadmillLevel, 0, "499 코인으로는 못 삼")
				T.eq(data.money, 499)
				H.advance(0.4)
				T.falsy(p.attrs.OnTreadmill)
				T.eq(p.attrs.TreadmillTouching, true)
				data.money = 500
				local speedBefore = data.speed
				H.advance(1) -- 레이트 리밋 (5/2초) 회복
				H.client(p, "PurchaseUpgrade", "Treadmill")
				T.eq(data.treadmillLevel, 1)
				T.eq(data.money, 0, "정확히 500 코인")
				H.advance(0.3)
				T.eq(p.attrs.OnTreadmill, true, "내려오지 않아도 바로 탐")
				T.eq(#H.sent(p, "TreadmillTouched"), 1, "서 있는 동안 또 안 보냄")
				H.advance(2)
				T.eq(data.speed, speedBefore + 8 * 2, "1초에 +8 (1레벨)")
				T.eq(data.money, 0, "러닝머신은 코인을 안 바꿈")
				-- 벨트 밖에서 사도 됨 (화면 버튼이라 거리 검사 없음) → 올라서면 바로 탐
				local other = MapLayout.plot(1)
				H.client(p, "TreadmillLeave")
				H.teleport(p, other.treadmill.x + other.facing * 14, 3, other.treadmill.z)
				H.advance(0.5)
				data.money = Upgrades.Treadmill[2].cost
				H.client(p, "PurchaseUpgrade", "Treadmill")
				T.eq(data.treadmillLevel, 2)
				H.teleport(p, other.treadmill.x, 3, other.treadmill.z)
				H.advance(0.5)
				T.eq(p.attrs.OnTreadmill, true)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"TreadmillTouched 는 서버 → 클라 전용: 서버에 받는 쪽(OnServerEvent)이 없고 Remotes.ToServer 에도 없어서, 클라가 가짜 TreadmillTouched 를 보내도 아무 일도 안 일어남 / TreadmillLeave 는 벨트 위가 아니면 무시",
		function()
			local Remotes = Loader.require(S .. "Remotes")
			T.eq(Remotes.ToServer.TreadmillTouched, nil)
			T.eq(Remotes.ToClient.TreadmillTouched, "TreadmillTouched")
			inWorld(nil, function(H)
				local w = treadmillWorld(H, 5, 1000)
				local p, data = w.p, w.data
				T.eq(#H.remotes.TreadmillTouched.OnServerEvent.handlers, 0, "서버가 안 듣는 이벤트")
				local before = {
					data.money,
					data.speed,
					data.treadmillLevel,
					#H.sent(p, "TreadmillTouched"),
					#H.sent(p, "Notify"),
				}
				for _, junk in { {}, { level = 99, maxed = true }, "x", 1, 0 / 0, true } do
					H.client(p, "TreadmillTouched", junk)
				end
				H.advance(0.5)
				T.eq(data.money, before[1])
				T.eq(data.speed, before[2])
				T.eq(data.treadmillLevel, before[3])
				T.eq(#H.sent(p, "TreadmillTouched"), before[4], "서버가 되받아 보내지도 않음")
				T.eq(#H.sent(p, "Notify"), before[5])
				-- 벨트 위가 아닐 때 TreadmillLeave 연타는 아무 일도 없음
				local pos = p.Character.root.Position
				for _ = 1, 20 do
					H.client(p, "TreadmillLeave")
				end
				T.eq(p.Character.root.Position.X, pos.X)
				T.eq(p.Character.root.Position.Z, pos.Z)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"참고: 벨트 가장자리(여유 1 스터드 경계)에서 0.2초마다 들락거리면 TreadmillTouched 가 틱마다 옴 (서버는 간격을 안 둠 — 창이 깜빡일 수 있음)",
		function()
			inWorld(nil, function(H)
				local w = treadmillWorld(H, 2)
				local p, plot = w.p, w.plot
				local pad = MapLayout.TREADMILL_PAD
				local edge = pad.sizeX / 2 + Config.TREADMILL_PAD_MARGIN -- 경계
				for i = 1, 10 do
					local dx = if i % 2 == 0 then edge - 0.1 else edge + 0.1
					H.teleport(p, plot.treadmill.x + plot.facing * dx, 3, plot.treadmill.z)
					H.advance(0.2)
				end
				local n = #H.sent(p, "TreadmillTouched")
				print("      (참고) 가장자리 들락거리기 10틱(2초) 동안 TreadmillTouched " .. n .. "번")
				T.truthy(n <= 5, "틱당 한 번 이하")
			end)
		end
	)

	T.skip(
		"E-2 러닝머신: 서버가 높이로 내려 준 뒤(클라가 TreadmillLeave 를 안 보냄) 같은 자리에 착지하면 바로 다시 안 탐",
		"참고(2판부터 있던 것): TreadmillService 머리말은 '내린 뒤에는 벨트 밖으로 한 번 나가야 다시 탐' 인데, 공중에 떠 있는 동안 positionTick 의 `elseif not on` 가 treadmillArmed 를 다시 true 로 바꿔서 착지하면 다시 탐. 정상 클라는 점프 때 TreadmillLeave 로 벨트 앞에 내려서 닿지 않음",
		function()
			inWorld(nil, function(H)
				local w = treadmillWorld(H, 3)
				H.teleport(w.p, w.plot.treadmill.x, 3, w.plot.treadmill.z)
				H.advance(0.4)
				T.eq(w.p.attrs.OnTreadmill, true)
				H.teleport(w.p, w.plot.treadmill.x, 14, w.plot.treadmill.z)
				H.advance(0.4)
				T.eq(w.p.attrs.OnTreadmill, false)
				H.teleport(w.p, w.plot.treadmill.x, 3, w.plot.treadmill.z)
				H.advance(0.4)
				T.eq(w.p.attrs.OnTreadmill, false, "착지해도 바로 안 탐")
			end)
		end
	)

	------------------------------------------------------------------
	T.suite(
		"8판 주임 검수 F: 무작위 요청 시험 (두 사람, 진짜 EggService · GuardianService · TreadmillService 포함)"
	)

	T.test(
		"A 가 온갖 Remote(새 TreadmillTouched·DropEgg·TreadmillLeave 포함)를 1000번 던지고 씨앗 줍기·내려놓기·경비 추격·러닝머신·초기화·밤낮까지 겪어도 코인·가방·정원·씨앗 불변식이 안 깨지고 B 것은 그대로, 서버 warn 0",
		function()
			local H = ServerHarness.install(Loader, T, { realEgg = true })
			local ok, err = pcall(function()
				H.startNet()
				local w = { H = H }
				w.DataSchema = H.server("Logic/DataSchema")
				w.FruitRules = H.shared("FruitRules")
				w.BaseService = H.server("Services/BaseService")
				w.PetService = H.server("Services/PetService")
				w.FruitService = H.server("Services/FruitService")
				w.SakuraService = H.server("Services/SakuraService")
				w.IndexService = H.server("Services/IndexService")
				w.UpgradeService = H.server("Services/UpgradeService")
				w.EggService = H.server("Services/EggService")
				w.GuardianService = H.server("Services/GuardianService")
				w.TreadmillService = H.server("Services/TreadmillService")
				w.SpeedService = H.server("Services/SpeedService")
				local A = H.newPlayer(8901, "Fuzzer8")
				local sessionA, dataA = H.login(A)
				sessionA.plotIndex = 1
				local B = H.newPlayer(8902, "Victim8")
				local sessionB, dataB = H.login(B)
				sessionB.plotIndex = 2
				dataA.penLevel = Upgrades.PEN_MAX_LEVEL - 2
				dataB.penLevel = Upgrades.PEN_MAX_LEVEL
				dataB.nextUid = 700
				sessionA.moveExemptUntil = H.clock() + 1e7
				sessionB.moveExemptUntil = H.clock() + 1e7
				w.BaseService.start()
				w.PetService.start()
				w.FruitService.start()
				w.SakuraService.start()
				w.IndexService.start()
				w.UpgradeService.start()
				w.EggService.start()
				w.GuardianService.start()
				w.TreadmillService.start()
				H.setPhase("Intermission", 1)
				H.setPhase("Day", 1)
				local cycle = 1

				local function taken(data)
					local list = {}
					for _, r in data.pets do
						table.insert(list, { x = r.x, z = r.z, size = r.size, petId = r.petId })
					end
					for _, r in data.incubators do
						table.insert(list, { x = r.x, z = r.z, size = r.size, petId = r.petId })
					end
					return list
				end
				local function addPlant(player, data, petId, fruits)
					local spot = EggPlacement.firstFreeGrid("normal", taken(data), petId)
					local record = {
						uid = w.DataSchema.newUid(data, "p"),
						petId = petId,
						size = "normal",
						mutations = {},
						x = spot.x,
						z = spot.z,
						fruits = fruits or 0,
						fruitProgress = 0,
					}
					assert(w.PetService.addPlant(player, record), "addPlant 실패")
				end
				local function plantSeed(player, data, plotIndex, petId)
					local px, pz = H.plotSpot(plotIndex)
					H.spawn(player, px, 3, pz)
					assert(w.BaseService.grantEgg(player, petId, "normal", {}, "sakura"), "grantEgg 실패")
					local egg = data.eggs[#data.eggs]
					local l = EggPlacement.firstFreeGrid(egg.size, taken(data), egg.petId)
					local spot = MapLayout.toWorld(plotIndex, l.x, l.z)
					assert(w.BaseService.placeEgg(player, egg.uid, spot.x, spot.z), "plantSeed 실패")
				end
				for _, id in { "static_world_tree", "glitch_hacker_bloom", "mainframe_tree" } do
					addPlant(A, dataA, id, 3)
				end
				for _, id in { "sprout_daisy", "owl_oak", "puppy_grass" } do
					addPlant(A, dataA, id, 2)
				end
				plantSeed(A, dataA, 1, "error_rose") -- 8판 추가: 거대 식물은 정원에 1그루 (이미 성체 2그루 = 옛 저장처럼)
				plantSeed(A, dataA, 1, "owl_oak")
				for _ = 1, 4 do
					w.BaseService.grantEgg(A, "static_world_tree", "normal", {}, "sakura")
				end
				dataA.fruits.static_world_tree = { count = 30, value = 30 * 3.3e15 }
				dataA.fruits.owl_oak = { count = 200, value = 200 * 180 }
				dataA.money = 5000
				for _, id in { "sprout_daisy", "owl_oak", "glitch_hacker_bloom" } do
					addPlant(B, dataB, id, 5)
				end
				plantSeed(B, dataB, 2, "rune_rose")
				dataB.fruits.owl_oak = { count = 10, value = 1800 }
				dataB.money = 12345
				dataB.sakuraCrystals = 7
				dataB.treadmillLevel = 2
				dataB.speed = 777
				w.SpeedService.refresh(B)
				local bStart = {}
				for _, r in dataB.pets do
					bStart[r.uid] = true
				end
				local function lockedB()
					local fr = {}
					for id, st in dataB.fruits do
						table.insert(fr, id .. ":" .. st.count .. ":" .. st.value)
					end
					table.sort(fr)
					local muts = {}
					for _, r in dataB.pets do
						if bStart[r.uid] then
							table.insert(muts, r.uid .. "=" .. table.concat(r.mutations, "+") .. "/" .. r.size)
						end
					end
					table.sort(muts)
					return table.concat({
						tostring(dataB.money),
						tostring(dataB.sakuraCrystals),
						#dataB.eggs,
						dataB.penLevel,
						dataB.treadmillLevel,
						tostring(dataB.speed),
						table.concat(fr, ","),
						table.concat(muts, ","),
					}, "|")
				end
				local lockedBefore = lockedB()

				-- 씨앗·경비 불변식
				local VALID_STATE = { Nest = true, Carried = true, Dropped = true }
				local VALID_GUARD = { Sleeping = true, Alert = true, Chase = true, Return = true } -- 66번: Alert = 훔친 직후 느낌표
				local seen = { stay = 0, ret = 0, carried = 0, nest = 0 }
				local function checkWorld(label)
					local carriedBy = {}
					local parts = H.map.folders.Eggs.children
					T.truthy(#parts <= 105 + 50 * 21, label .. ": 씨앗 파트 수 " .. #parts)
					for _, part in parts do
						local state = part:GetAttribute("EggState")
						T.truthy(VALID_STATE[state], label .. ": 씨앗 상태 " .. tostring(state))
						T.truthy(finite(part.Position.X) and finite(part.Position.Z), label .. ": 씨앗 위치")
						if state == "Dropped" then
							local at = part:GetAttribute("DroppedAt")
							T.truthy(typeof(at) == "number", label .. ": DroppedAt")
							-- 2026-11-10: 바닥 씨앗은 언제나 5초 카운트다운 (Stay 없음). 구역 안 바닥은 치트 의심 위치(dropCarriedAt)뿐
							local zone = MapLayout.zoneAt(part.Position.Z)
							local inZone = zone == part:GetAttribute("BiomeId")
							T.eq(
								part:GetAttribute("ReturnsToNest"),
								true,
								label .. ": 바닥 씨앗은 언제나 둥지로 돌아감 (Stay 없음)"
							)
							if inZone then
								seen.stay += 1
							else
								seen.ret += 1
							end
							T.near(part:GetAttribute("ExpiresAt") - at, 5, 1e-6, label .. ": ExpiresAt")
						else
							T.eq(part:GetAttribute("ExpiresAt"), nil, label .. ": " .. state .. " 인데 ExpiresAt")
							T.eq(part:GetAttribute("DroppedAt"), nil)
							if state == "Nest" then
								seen.nest += 1
							end
						end
					end
					for player, egg in w.EggService.carriers() do
						carriedBy[player] = (carriedBy[player] or 0) + 1
						seen.carried += 1
						T.eq(egg.state, "Carried")
						T.truthy(
							egg.chaseSeconds >= 0 and finite(egg.chaseSeconds),
							label .. ": 추격 시간 " .. tostring(egg.chaseSeconds)
						)
					end
					for player, n in carriedBy do
						T.eq(n, 1, label .. ": 한 사람이 씨앗 두 개")
						T.truthy(player.attrs.CarryingEgg ~= "", label .. ": CarryingEgg")
					end
					for _, model in H.map.folders.Guardians.children do
						local ws = humanoidOf(model).WalkSpeed
						T.truthy(
							finite(ws) and ws > 0 and ws <= Config.GUARD_CATCH_RUSH_MAX_WALKSPEED + 1e-9,
							label .. ": 경비 WalkSpeed " .. tostring(ws)
						)
						T.truthy(VALID_GUARD[model:GetAttribute("State")], label .. ": 경비 상태")
						local target = model:GetAttribute("TargetUserId")
						T.truthy(
							target == 0 or target == A.UserId or target == B.UserId,
							label .. ": 경비 대상 " .. tostring(target)
						)
					end
					T.truthy(
						finite(dataA.speed) and dataA.speed >= 0 and dataA.speed <= Config.SPEED_MAX,
						label .. ": A 속도 " .. tostring(dataA.speed)
					)
					if A.attrs.OnTreadmill then
						T.eq(
							A.attrs.TreadmillTouching,
							true,
							label .. ": 러닝머신 타는 중인데 창 신호 없음"
						)
					end
				end

				local function checkPlayer(label)
					for who, data in { A = dataA, B = dataB } do
						local tag = who .. " " .. label
						T.truthy(
							finite(data.money) and data.money >= 0 and data.money <= Config.MONEY_MAX,
							tag .. ": 코인 " .. tostring(data.money)
						)
						local total = 0
						for id, stack in data.fruits do
							T.truthy(Plants.get(id) ~= nil, tag .. ": 모르는 열매 칸")
							T.truthy(
								finite(stack.count) and stack.count == math.floor(stack.count) and stack.count >= 1,
								tag .. ": 열매 개수"
							)
							T.truthy(finite(stack.value) and stack.value >= 0, tag .. ": 열매 값")
							total += stack.count
						end
						T.truthy(total <= Config.FRUIT_BAG_MAX, tag .. ": 열매 가방 " .. total)
						T.truthy(#data.eggs <= Config.EGG_INVENTORY_MAX, tag .. ": 씨앗 가방")
						T.truthy(
							#data.pets + #data.incubators <= GardenRules.capacity(data.penLevel),
							tag .. ": 정원 칸"
						)
						T.truthy(
							data.penLevel >= 1 and data.penLevel <= Upgrades.PEN_MAX_LEVEL,
							tag .. ": 정원 레벨"
						)
						T.truthy(
							data.treadmillLevel >= 0 and data.treadmillLevel <= Upgrades.TREADMILL_MAX_LEVEL,
							tag .. ": 러닝머신 레벨"
						)
						local ids = {}
						for _, list in { data.pets, data.incubators, data.eggs } do
							for _, r in list do
								T.truthy(not ids[r.uid], tag .. ": uid 겹침")
								ids[r.uid] = true
							end
						end
						-- 정원 안 식물 자리: 정원 안 + 저장 간격(7판 이상) 지킴 (8판 새 간격으로 심은 것은 더 넓음)
						local spots = taken(data)
						for i, s in spots do
							T.truthy(MapLayout.isInPenLocal(s.x, s.z, 0), tag .. ": 정원 밖에 심김")
							for j = i + 1, #spots do
								local d = math.sqrt((s.x - spots[j].x) ^ 2 + (s.z - spots[j].z) ^ 2)
								T.truthy(d >= 4 - 1e-9, tag .. ": 식물이 4 이내로 겹침 " .. d)
							end
						end
					end
					-- 서버 warn 은 0 이어야 함. 단 시험이 일부러 하는 순간이동에 대한 [AntiCheat] 경고는 정상 동작이라 센다
					for _, text in H.warnings do
						T.truthy(
							string.sub(text, 1, 11) == "[AntiCheat]",
							label .. ": 뜻밖의 서버 warn " .. tostring(text)
						)
					end
				end

				local rand = T.rng(80808)
				local function pick(list)
					return list[math.floor(rand() * #list) + 1]
				end
				local junk = {
					true,
					false,
					0,
					1,
					-1,
					0 / 0,
					math.huge,
					-math.huge,
					1e308,
					"",
					"all",
					"half",
					"Pen",
					"Treadmill",
					"Trail",
					"none",
					"grey",
					string.rep("x", 100),
					"../x",
					"한글",
					{},
					{ 1 },
					{ level = 99, maxed = true },
				}
				local function uidPool()
					local pool = {}
					for _, d in { dataA, dataB } do
						for _, list in { d.pets, d.incubators, d.eggs } do
							for _, r in list do
								table.insert(pool, r.uid)
							end
						end
					end
					for _, part in H.map.folders.Eggs.children do
						table.insert(pool, tostring(part:GetAttribute("EggUid")))
					end
					return pool
				end
				local function uidArg()
					local roll = rand()
					if roll < 0.6 then
						local pool = uidPool()
						if #pool > 0 then
							return pick(pool)
						end
					elseif roll < 0.67 then
						return nil
					end
					return pick(junk)
				end
				local trailIds = {}
				for _, t in Upgrades.Trails do
					table.insert(trailIds, t.id)
				end
				local clientRemotes = {
					"PickFruit",
					"SellFruits",
					"SkipGrowth",
					"SellPlant",
					"SakuraOffer",
					"SakuraDraw",
					"PlaceEgg",
					"PickUpPlacedEgg",
					"PurchaseUpgrade",
					"PurchaseUpgrade",
					"PurchaseUpgrade",
					"EquipTrail",
					"DropEgg",
					"DropEgg",
					"TreadmillLeave",
					"TreadmillLeave",
					"ClaimIndexReward",
					"RequestSnapshot",
					"UseTool",
				}
				local toClientNames = {}
				for name in Loader.require(S .. "Remotes").ToClient do
					table.insert(toClientNames, name)
				end
				-- 서버가 안 듣는 이벤트(서버 → 클라) 전부: 받는 쪽이 없어야 함
				for _, name in toClientNames do
					T.eq(#H.remotes[name].OnServerEvent.handlers, 0, name .. " 은 서버 → 클라 전용")
				end
				local penA = MapLayout.penRect(1)
				local stall = MapLayout.hubSpots.sellStall
				local plot = MapLayout.plot(1)
				local did = {
					remote = 0,
					pick = 0,
					caught = 0,
					drop = 0,
					buy = 0,
					touched = 0,
					mounted = 0,
					reset = 0,
					teleport = 0,
				}
				local zoneIds = ALL_ZONES

				for step = 1, 1000 do
					local roll = rand()
					local label = "#" .. step
					local moneyBefore = dataA.money
					local expectCost
					if rand() < 0.08 then
						H.setPhase(if H.cycle.phase == "Night" then "Day" else "Night")
					end
					if rand() < 0.02 then
						cycle += 1
						H.setPhase("Intermission", cycle)
						H.setPhase("Day", cycle)
						did.reset += 1
					end
					if rand() < 0.1 then
						dataA.money =
							pick({ 0, 5, 499, 500, 7500, 1e6, 1e12, 1e18, Config.MONEY_MAX - 1, Config.MONEY_MAX })
						moneyBefore = dataA.money
					end
					if rand() < 0.1 then
						dataA.speed = pick({ 10, 50, 900, 1e4, 1e8, 1e11, 9e11, 1.2e12, 1.3e12, 1e15 })
						w.SpeedService.refresh(A)
					end
					if rand() < 0.06 then
						dataA.treadmillLevel = pick({ 0, 1, 2, 5, 19, 20 })
					end
					if roll < 0.18 then
						-- 씨앗 줍기: 아무 구역의 아무 씨앗 파트 (둥지·바닥), 아무 거리에서
						local parts = H.map.folders.Eggs.children
						if #parts > 0 then
							local part = pick(parts)
							local prompt = part:FindFirstChild("StealPrompt")
							if prompt then
								if rand() < 0.85 then
									H.teleport(A, part.Position.X, part.Position.Y + 1, part.Position.Z)
								end
								prompt.Triggered:Fire(A)
								did.pick += 1
								-- 주운 직후 절반은 그 자리에서 바로 내려놓음 (구역 안이면 그대로 / 구역 밖이면 5초 뒤 둥지)
								if rand() < 0.5 and w.EggService.getCarried(A) then
									H.client(A, "DropEgg")
								end
							end
						end
					elseif roll < 0.3 then
						-- 걸어 다니기 (순간이동): 구역 안·경계·허브·러닝머신·맵 끝
						local z = pick({ -100, -1, 0.5, 100, 239.9, 240.1, 600, 2000, 4000, 5039, 5100 })
						if rand() < 0.5 then
							local id = pick(zoneIds)
							local range = MapLayout.biome(id)
							z = pick({
								range.zMin + 1,
								range.centerZ,
								range.zMax - 40,
								range.zMax - 0.5,
								range.zMax + 0.5,
							})
						end
						H.teleport(A, pick({ -90, -58, 0, 70 }), pick({ 3, 3, 3, 14 }), z)
						did.teleport += 1
					elseif roll < 0.38 then
						if rand() < 0.5 then
							H.teleport(A, plot.treadmill.x, 3, plot.treadmill.z)
						else
							H.teleport(A, plot.treadmill.x + plot.facing * pick({ 5, 9, 12 }), 3, plot.treadmill.z)
						end
					else
						-- Remote 던지기
						local at = pick({
							{ (penA.xMin + penA.xMax) / 2, (penA.zMin + penA.zMax) / 2 },
							{ stall.x, stall.z },
							{ plot.treadmill.x, plot.treadmill.z },
							{ 0, 5 },
							{ 0, MapLayout.biome(pick(zoneIds)).centerZ },
						})
						if rand() < 0.6 then
							H.teleport(A, at[1], 3, at[2])
						end
						H.landmarks.nearName = if rand() < 0.5 then "SakuraIncubator" else nil
						local name = pick(clientRemotes)
						local a1, a2, a3
						if name == "PickFruit" then
							a1 = if rand() < 0.3 then "all" else uidArg()
						elseif name == "SkipGrowth" then
							a1, a2 = uidArg(), if rand() < 0.75 then pick({ "all", "half" }) else pick(junk)
						elseif name == "PlaceEgg" then
							a1 = uidArg()
							a2 = pick({ at[1], 0, 1e9, 0 / 0, "x", penA.xMin + 5 })
							a3 = pick({ at[2], 0, -1e9, penA.zMin + 5 })
						elseif name == "PurchaseUpgrade" then
							a1 = if rand() < 0.85
								then pick({ "Pen", "Treadmill", "Treadmill", "Trail" })
								else pick(junk)
							a2 = if rand() < 0.8 then pick(trailIds) else pick(junk)
							if a1 == "Pen" then
								local nextLevel = Upgrades.Pen[dataA.penLevel + 1]
								expectCost = if nextLevel then nextLevel.cost else nil
							elseif a1 == "Treadmill" then
								local nextLevel = Upgrades.Treadmill[dataA.treadmillLevel + 1]
								expectCost = if nextLevel then nextLevel.cost else nil
							elseif a1 == "Trail" then
								local trail = Upgrades.getTrail(tostring(a2))
								if trail and not table.find(dataA.trails, trail.id) then
									expectCost = trail.cost
								end
							end
							if rand() < 0.4 then
								dataA.money = pick({ 500, 1e3, 1e9, 1e15, 1e21, 1e24 })
								moneyBefore = dataA.money
							end
						elseif name == "EquipTrail" then
							a1 = if rand() < 0.8 then pick({ "none", table.unpack(trailIds) }) else pick(junk)
						elseif name == "UseTool" then
							a1 = pick({ "Bat", "BearTrap", "Katana", "nope", junk[3] })
						elseif name == "SakuraOffer" or name == "PickUpPlacedEgg" or name == "ClaimIndexReward" then
							a1 = uidArg()
						end
						local before = {
							trails = #dataA.trails,
							level = dataA.treadmillLevel,
							fruits = w.FruitRules.bagValue(dataA.fruits),
						}
						H.client(A, name, a1, a2, a3)
						did.remote += 1
						local delta = dataA.money - moneyBefore
						if name == "PurchaseUpgrade" then
							if delta ~= 0 then
								did.buy += 1
								T.truthy(
									expectCost ~= nil and math.abs(-delta - expectCost) <= moneyBefore * 1e-14 + 1e-6,
									label .. ": 구매 값이 다름 " .. -delta .. " vs " .. tostring(expectCost)
								)
							end
							T.truthy(#dataA.trails >= before.trails, label .. ": 트레일이 줄어듦")
						elseif
							name == "DropEgg"
							or name == "TreadmillLeave"
							or name == "RequestSnapshot"
							or name == "UseTool"
						then
							T.eq(delta, 0, label .. ": " .. name .. " 이 코인을 바꿈")
						end
					end
					-- 가짜 서버→클라 이벤트를 클라가 보내도 상태가 안 바뀜
					if rand() < 0.15 then
						local name = pick(toClientNames)
						local m1, s1 = dataA.money, dataA.speed
						H.client(A, name, pick(junk), pick(junk))
						T.eq(dataA.money, m1, name .. " 위조: 코인")
						T.eq(dataA.speed, s1, name .. " 위조: 속도")
					end
					H.advance(pick({ 0.2, 0.5, 1, 2, 5, rand() < 0.05 and 40 or 3 }))
					did.caught = #H.sent(A, "Caught")
					did.touched = #H.sent(A, "TreadmillTouched")
					if A.attrs.OnTreadmill then
						did.mounted += 1
					end
					checkPlayer(label)
					checkWorld(label)
					T.eq(
						lockedB(),
						lockedBefore,
						label
							.. ": B 의 것이 바뀜 (코인·크리스탈·속도·러닝머신·가방·돌연변이)"
					)
				end
				print(
					string.format(
						"      (참고) 시험 범위: Remote %d · 줍기 %d · 순간이동 %d · 잡힘 %d · 러닝머신 신호 %d · 타는 중 %d틱 · 구매 %d · 초기화 %d / 바닥 씨앗 확인 (구역 안 = 치트 의심만) %d · (구역 밖) %d",
						did.remote,
						did.pick,
						did.teleport,
						did.caught,
						did.touched,
						did.mounted,
						did.buy,
						did.reset,
						seen.stay,
						seen.ret
					)
				)
				T.truthy(did.remote > 300 and did.pick > 80 and did.buy > 5, "시험이 너무 약함")
				T.truthy(did.caught >= 2, "경비에게 잡힌 일이 거의 없음 " .. did.caught)
				T.truthy(did.touched >= 3, "러닝머신 신호가 거의 없음 " .. did.touched)
				T.truthy(
					seen.stay > 0 and seen.ret >= 0 and seen.carried > 0,
					"바닥 씨앗(구역 안)·든 씨앗을 한 번도 못 봄"
				)
			end)
			H.uninstall()
			if not ok then
				error(err, 0)
			end
		end
	)

	------------------------------------------------------------------
	T.suite(
		"8판 주임 검수 G: 방망이 · 곰덫 · 경비가 씨앗을 떨어뜨리는 길 (진짜 ToolService + 진짜 EggService + 진짜 GuardianService)"
	)

	T.test(
		"진짜 방망이·곰덫 (2026-11-10): 씨앗 든 사람을 구역 안에서 때리면 바로 둥지로(ReturnToNest), 다른 구역에서 때리면 그 자리 → 5초 뒤 원래 둥지로(DropHere)",
		function()
			inWorld({ realEgg = true }, function(H)
				local EggService = H.server("Services/EggService")
				EggService.start()
				local ToolService = H.server("Services/ToolService")
				ToolService.start()
				local a, sa, da = newRunner(H, 9201, "Alice")
				local b, sb = newRunner(H, 9202, "Bob")
				sb.plotIndex = 2
				H.giveBackpack(a)
				H.giveBackpack(b)
				ToolService.onPlayerReady(a)
				ToolService.onPlayerReady(b)
				H.setPhase("Intermission", 1)
				H.setPhase("Day", 1)
				da.tools.bearTrap = 10
				ToolService.refreshTools(a)
				local desert = MapLayout.biome("desert")
				local zc = desert.centerZ
				local function setup(eggBiome, victimX, victimZ)
					local egg = nestEgg(H, eggBiome)
					local home = egg.Position
					pickUp(H, b, egg)
					sb.moveExemptUntil = H.clock() + 100
					H.teleport(b, victimX, 3, victimZ)
					H.advance(0.45) -- 둥지 예약이 풀릴 틱 (다른 구역일 때)
					return egg, home
				end
				local function bat(attackerZ)
					H.teleport(a, 30, 3, attackerZ)
					H.equip(a, "Bat")
					H.advance(5) -- 레이트 리밋·쿨다운
					H.client(a, "UseTool", "Bat")
					H.unequip(a, "Bat")
				end
				-- (1) 방망이, 같은 구역(사막 씨앗을 사막에서)
				local egg1, home1 = setup("desert", 30, zc)
				bat(zc + 3)
				local caught = H.sent(b, "Caught")
				T.eq(#caught, 1, "방망이에 맞음")
				T.eq(caught[1][1].cause, "player")
				T.eq(caught[1][1].eggOutcome, "ReturnToNest", "구역 안: 바로 둥지로 (2026-11-10)")
				T.eq(egg1:GetAttribute("EggState"), "Nest", "방망이 구역 안 = 바로 둥지")
				T.eq(egg1.Position.X, home1.X)
				T.eq(egg1.Position.Z, home1.Z)
				H.advance(100)
				T.eq(egg1:GetAttribute("EggState"), "Nest", "둥지에 그대로")
				-- (2) 방망이, 다른 구역(호수 씨앗을 사막에서) → 5초 뒤 원래 둥지
				H.advance(Config.RAGDOLL_SECONDS + 3)
				local egg2, home2 = setup("lake", 30, zc)
				bat(zc + 3)
				expectGround(egg2, false, "방망이 구역 밖")
				H.advance(5.5)
				T.eq(egg2:GetAttribute("EggState"), "Nest", "5초 뒤 둥지")
				T.eq(egg2.Position.X, home2.X)
				T.eq(egg2.Position.Z, home2.Z)
				-- (3) 곰덫: A 가 설치(자기 자리), B 가 씨앗을 들고 밟음
				H.advance(Config.RAGDOLL_SECONDS + 3)
				H.teleport(a, 60, 3, zc + 20)
				H.equip(a, "BearTrap")
				H.advance(5)
				H.client(a, "UseTool", "BearTrap")
				H.unequip(a, "BearTrap")
				H.teleport(a, 0, 3, zc - 80)
				local egg3, home3 = setup("desert", 0, zc - 90) -- 사막 씨앗, 사막 안
				H.teleport(b, 60, 3, zc + 20) -- 곰덫 위
				H.advance(0.5)
				local list = H.sent(b, "Caught")
				T.eq(list[#list][1].cause, "trap")
				T.eq(list[#list][1].eggOutcome, "ReturnToNest", "구역 안: 바로 둥지로 (2026-11-10)")
				T.eq(egg3:GetAttribute("EggState"), "Nest", "곰덫 구역 안 = 바로 둥지")
				T.eq(egg3.Position.Z, home3.Z)
				T.eq(b.attrs.Stunned, true)
				H.advance(Config.BEAR_TRAP_STUN_SECONDS + 1)
				-- 곰덫 구역 밖 (호수 씨앗을 사막 곰덫에서)
				H.teleport(a, 60, 3, zc + 20)
				H.equip(a, "BearTrap")
				H.advance(5)
				H.client(a, "UseTool", "BearTrap")
				H.unequip(a, "BearTrap")
				H.teleport(a, 0, 3, zc - 80)
				local egg4, home4 = setup("lake", 0, zc - 90)
				H.teleport(b, 60, 3, zc + 20)
				H.advance(0.5)
				expectGround(egg4, false, "곰덫 구역 밖")
				H.advance(5.5)
				T.eq(egg4:GetAttribute("EggState"), "Nest")
				T.eq(egg4.Position.Z, home4.Z)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"경비에게 잡히는 길 3가지 (2026-11-10): ① 경비가 이 구역 밖으로 나와 닿아 잡힘 → 그 자리에 떨어져 5초 뒤 둥지로(DropHere) ② 둥지가 다시 채워진 뒤 구역 안에서 잡힘 → 돌아갈 둥지가 없어 그 자리에 떨어졌다가 5초 뒤 사라짐 (예전 Stay 는 없음) ③ 둥지가 다 차고 구역 밖에서 경계 잡힘 → 사라지고 씨앗 수 그대로",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local id = "lake"
				local range = MapLayout.biome(id)
				local home0 = MapLayout.guardHome(id)
				local thr = threshold(id)
				-- ① 호수 씨앗을 든 사람을 호수 경비가 구역 밖(숲 쪽 z=100)에서 잡음. 가짜 경비는 안 걸어서 경비 몸을 그곳으로 옮겨 둠
				--    (시간이 지나도 멀리선 안 잡히고, 닿아야만 잡힘 — 구역 밖이면 그 자리에 떨어짐)
				local p, s, d = newRunner(H, 9301, "Back")
				local egg = nestEgg(H, id)
				local home = egg.Position
				pickUp(H, p, egg)
				s.moveExemptUntil = H.clock() + 1000
				setCarrySpeed(w, p, s, d, thr * 0.4)
				H.teleport(p, 0, 3, 100)
				local model = guardModel(H, id)
				local t = timeToCatch(H, p, 2)
				T.eq(t, nil, "경비가 멀리 있으면 숲 쪽에서 시간이 지나도 안 잡힘")
				local rootY = model.PrimaryPart.Position.Y
				model.PrimaryPart.CFrame = { Position = H.vec(0, rootY, 100) } -- 경비가 쫓아 나와 닿음
				t = timeToCatch(H, p, 1)
				T.truthy(t ~= nil and t <= 0.35, "경비가 닿자 그 틱에 잡힘 " .. tostring(t))
				local caught = H.sent(p, "Caught")
				T.eq(caught[#caught][1].cause, "guard")
				T.eq(caught[#caught][1].eggOutcome, "DropHere", "구역 밖에서 잡힘 = 그 자리")
				expectGround(egg, false, "숲 쪽에서 잡힘")
				T.eq(egg.Position.Z, 100)
				H.advance(5.5)
				T.eq(egg:GetAttribute("EggState"), "Nest", "5초 뒤 둥지")
				T.eq(egg.Position.Z, home.Z)
				model.PrimaryPart.CFrame = { Position = H.vec(home0.x, rootY, home0.z) } -- 경비를 집으로
				H.advance(Config.RAGDOLL_SECONDS + 3)
				-- ② 둥지를 비우고(다음 구역에 31초) 돌아오면 그 둥지에 새 씨앗이 있음 → 구역 안에서 잡혀도 돌아갈 둥지가 없음
				local egg2 = nestEgg(H, id)
				pickUp(H, p, egg2)
				setCarrySpeed(w, p, s, d, thr * 1.5) -- 도망 가능
				H.teleport(p, 0, 3, range.zMax + 40)
				H.advance(31)
				T.eq(egg2:GetAttribute("EggState"), "Carried")
				T.eq(
					countNestEggs(H),
					105,
					"빈 둥지(방금 비운 곳)가 다시 채워져 둥지 위는 전부 참"
				)
				setCarrySpeed(w, p, s, d, thr * 0.4) -- 이제 못 도망
				H.teleport(p, home0.x, 3, home0.z) -- 구역 안에서 경비에 닿음
				t = timeToCatch(H, p, 1)
				T.truthy(t ~= nil, "구역 안에서 잡힘")
				caught = H.sent(p, "Caught")
				T.eq(caught[#caught][1].eggOutcome, "DropHere", "돌아갈 둥지가 없어 그 자리에")
				expectGround(egg2, false, "빈 둥지 없음")
				T.eq(egg2.Position.Z, home0.z)
				-- 2026-11-10: 예전엔 Stay (초기화까지 그대로) 였지만 이제 5초 뒤 둥지로 → 갈 둥지가 없으면 사라짐
				H.advance(4.5)
				T.eq(egg2:GetAttribute("EggState"), "Dropped", "5초 전")
				H.advance(1)
				T.truthy(egg2.destroyed, "5초 뒤 둥지도 없어 사라짐")
				T.truthy(#H.map.folders.Eggs.children <= 105, "씨앗 수가 늘지 않음")
				-- ③ 같은 상황에서 구역 밖(다음 구역)으로 가서 경계 잡힘: 둥지 없음 → 5초 뒤 사라짐, 씨앗 수 안 늘어남
				H.advance(Config.RAGDOLL_SECONDS + 3)
				local before = #H.map.folders.Eggs.children
				local egg3 = nestEgg(H, id, 0)
				pickUp(H, p, egg3)
				setCarrySpeed(w, p, s, d, thr * 1.5)
				H.teleport(p, 0, 3, range.zMax + 40)
				H.advance(31)
				setCarrySpeed(w, p, s, d, thr * 0.4)
				H.advance(0.6)
				caught = H.sent(p, "Caught")
				T.eq(caught[#caught][1].cause, "guard")
				T.eq(
					egg3:GetAttribute("EggState"),
					"Dropped",
					"빈 둥지가 없어 둥지로 못 돌아가고 바닥에"
				)
				expectGround(egg3, false, "다음 구역에서 잡힘")
				H.advance(5.5)
				T.truthy(egg3.destroyed, "5초 뒤에도 갈 곳이 없어 사라짐")
				T.eq(#H.map.folders.Eggs.children <= before + 1, true, "씨앗 수가 늘지 않음")
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"씨앗 상태기계 난장판: 4명이 2000번 아무 구역에서 줍고·내려놓고·죽고·맞고·순간이동하고 낮/밤/초기화가 섞여도 한 둥지에 씨앗 두 개·한 사람이 두 개 듦·사라진 씨앗·무한 증가·서버 warn 이 없음",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local players = {}
				for i = 1, 4 do
					local p, s, d = newRunner(H, 9950 + i, "Chaos" .. i)
					s.plotIndex = i
					s.moveExemptUntil = H.clock() + 1e7
					players[i] = { p = p, s = s, d = d }
				end
				local rand = T.rng(31337)
				local function pick(list)
					return list[math.floor(rand() * #list) + 1]
				end
				-- 둥지 자리 (x, z) → 있는지 보는 표
				local slotKey = {}
				for _, b in Biomes.list do
					for i, n in MapLayout.nestsFor(b.id) do
						slotKey[string.format("%s:%g:%g", b.id, n.x, n.z)] = true
					end
				end
				local cycle = 1
				local stats = { picks = 0, drops = 0, deaths = 0, knocks = 0, resets = 0, maxParts = 0, maxFloor = 0 }
				for step = 1, 2000 do
					local who = pick(players)
					local roll = rand()
					local label = "#" .. step
					if roll < 0.3 then
						local parts = H.map.folders.Eggs.children
						local part = pick(parts)
						local prompt = part and part:FindFirstChild("StealPrompt")
						if prompt then
							if rand() < 0.8 then
								H.teleport(who.p, part.Position.X, part.Position.Y + 1, part.Position.Z)
							end
							prompt.Triggered:Fire(who.p)
							stats.picks += 1
						end
					elseif roll < 0.42 then
						if w.EggService.dropEgg(who.p) then
							stats.drops += 1
						end
					elseif roll < 0.62 then
						local id = pick(ALL_ZONES)
						local range = MapLayout.biome(id)
						H.teleport(
							who.p,
							pick({ -90, -58, 0, 70 }),
							3,
							pick({
								range.zMin + 1,
								range.centerZ,
								range.zMax - 40,
								range.zMax - 0.5,
								range.zMax + 0.5,
								-20,
							})
						)
					elseif roll < 0.7 then
						who.d.speed = pick({ 10, 20, 900, 1e4, 1e8, 1e12, 1.3e12 })
						w.SpeedService.refresh(who.p)
					elseif roll < 0.78 then
						who.p.Character.humanoid.Health = 0
						stats.deaths += 1
					elseif roll < 0.84 then
						who.p.Character.humanoid.Health = 100
					elseif roll < 0.9 then
						w.EggService.knockOut(who.p, H.vec(0, 3, 0), "player", "Bat", 1)
						stats.knocks += 1
					elseif roll < 0.95 then
						H.setPhase(if H.cycle.phase == "Night" then "Day" else "Night")
					else
						cycle += 1
						H.setPhase("Intermission", cycle)
						H.setPhase("Day", cycle)
						stats.resets += 1
					end
					H.advance(pick({ 0.1, 0.2, 0.5, 1, 3, 6 }))
					-- 불변식
					local parts = H.map.folders.Eggs.children
					stats.maxParts = math.max(stats.maxParts, #parts)
					local nestSpots, carriedBy, floor = {}, {}, 0
					local uids = {}
					for _, part in parts do
						local uid = part:GetAttribute("EggUid")
						T.truthy(not uids[uid], label .. ": 씨앗 uid 겹침 " .. tostring(uid))
						uids[uid] = true
						local state = part:GetAttribute("EggState")
						if state == "Nest" then
							local key = string.format(
								"%s:%g:%g",
								part:GetAttribute("BiomeId"),
								part.Position.X,
								part.Position.Z
							)
							T.truthy(slotKey[key], label .. ": 둥지 자리가 아닌 곳의 Nest 씨앗 " .. key)
							T.truthy(not nestSpots[key], label .. ": 한 둥지에 씨앗 두 개 " .. key)
							nestSpots[key] = true
						elseif state == "Dropped" then
							floor += 1
						end
					end
					stats.maxFloor = math.max(stats.maxFloor, floor)
					for player, egg in w.EggService.carriers() do
						carriedBy[player] = (carriedBy[player] or 0) + 1
						T.truthy(egg.part:GetAttribute("EggState") == "Carried", label .. ": 든 씨앗 상태")
					end
					for _, entry in players do
						local n = carriedBy[entry.p] or 0
						T.truthy(n <= 1, label .. ": 두 개 듦")
						T.eq(entry.s.carryingUid ~= nil, n == 1, label .. ": session.carryingUid 와 실제가 다름")
						T.eq(
							entry.p.attrs.CarryingEgg ~= "" and entry.p.attrs.CarryingEgg ~= nil,
							n == 1,
							label .. ": Attr CarryingEgg"
						)
					end
					T.truthy(#parts <= 105 + 50 * 21, label .. ": 씨앗 파트 " .. #parts)
					for _, model in H.map.folders.Guardians.children do
						local target = model:GetAttribute("TargetUserId")
						if target ~= 0 then
							local holder
							for _, entry in players do
								if entry.p.UserId == target then
									holder = entry.p
								end
							end
							T.truthy(holder ~= nil, label .. ": 경비 대상이 모르는 사람")
						end
						local ws = humanoidOf(model).WalkSpeed
						T.truthy(
							finite(ws) and ws <= Config.GUARD_CATCH_RUSH_MAX_WALKSPEED + 1e-9,
							label .. ": 경비 속도 " .. tostring(ws)
						)
					end
					T.eq(#H.warnings, 0, label .. ": 서버 warn " .. tostring(H.warnings[1]))
				end
				print(
					string.format(
						"      (참고) 줍기 %d · 내려놓기 %d · 죽음 %d · 맞음 %d · 초기화 %d / 씨앗 파트 최대 %d · 바닥 씨앗 최대 %d",
						stats.picks,
						stats.drops,
						stats.deaths,
						stats.knocks,
						stats.resets,
						stats.maxParts,
						stats.maxFloor
					)
				)
				T.truthy(stats.picks > 400 and stats.drops > 10 and stats.resets >= 20, "시험이 너무 약함")
			end)
		end
	)

	T.test(
		'쌓인 추격 시간 (2026-11-10): 구역 밖에서 내려놓고 5초 안에 다시 주우면 이어짐 · 5초가 지나 둥지로 돌아가면 0부터 · 다른 사람이 주우면 처음부터 · 구역 안에서 내려놓으면 바로 둥지라 0부터 (예전 "3분 뒤에도 이어짐" 은 바닥에 3분 남는 Stay 가 없어져서 사라짐)',
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local a, sa, da = newRunner(H, 9971, "Stale")
				local b, sb, db = newRunner(H, 9972, "Fresh")
				sa.moveExemptUntil = H.clock() + 10000
				sb.moveExemptUntil = H.clock() + 10000
				local id = "desert"
				local thr = threshold(id)
				local range = MapLayout.biome(id)
				local egg = nestEgg(H, id)
				pickUp(H, a, egg)
				setCarrySpeed(w, a, sa, da, thr * 0.4) -- 1초 급
				H.teleport(a, 0, 3, range.centerZ)
				H.advance(0.85)
				T.eq(#H.sent(a, "Caught"), 0)
				local eggObj = w.EggService.getCarried(a)
				T.truthy(
					eggObj.chaseSeconds >= 0.6 and eggObj.chaseSeconds <= 0.9,
					"쌓인 시간 " .. eggObj.chaseSeconds
				)
				H.teleport(a, 0, 3, range.zMin - 5) -- 구역 밖에서 내려놓음
				w.EggService.dropEgg(a)
				T.eq(egg:GetAttribute("EggState"), "Dropped")
				H.advance(3)
				T.eq(egg:GetAttribute("EggState"), "Dropped", "3초 뒤에도 그 자리 (5초 전)")
				T.truthy(eggObj.chaseSeconds >= 0.6, "내려놓은 동안 쌓인 시간은 그대로")
				-- 5초 안에 다시 주움 → 이어서 쌓임
				pickUp(H, a, egg)
				setCarrySpeed(w, a, sa, da, thr * 0.4)
				H.teleport(a, 0, 3, range.centerZ)
				H.advance(0.6)
				T.truthy(
					eggObj.chaseSeconds >= 1.0,
					"이어서 쌓임 (0.85 + 0.6 쯤) " .. tostring(eggObj.chaseSeconds)
				)
				-- 구역 밖에 다시 내려놓고 5초가 지나면 둥지로 돌아가 0부터
				H.teleport(a, 0, 3, range.zMin - 5)
				w.EggService.dropEgg(a)
				H.advance(5.5)
				T.eq(egg:GetAttribute("EggState"), "Nest", "5초 뒤 둥지로")
				T.eq(eggObj.chaseSeconds, 0, "둥지로 돌아가면 0")
				-- 다른 사람은 처음부터: A 가 0.85초 쫓기다 구역 밖에 내려놓은 씨앗을 B 가 줍기
				local egg2 = nestEgg(H, id)
				pickUp(H, a, egg2)
				setCarrySpeed(w, a, sa, da, thr * 0.4)
				H.teleport(a, 0, 3, range.centerZ)
				H.advance(0.85)
				H.teleport(a, 0, 3, range.zMin - 5)
				w.EggService.dropEgg(a)
				H.advance(2)
				pickUp(H, b, egg2)
				setCarrySpeed(w, b, sb, db, thr * 0.4)
				H.teleport(b, 0, 3, range.centerZ)
				H.advance(0.5)
				local eggObj2 = w.EggService.getCarried(b)
				T.eq(eggObj2.chaseBy, b)
				T.truthy(
					eggObj2.chaseSeconds <= 0.6,
					"다른 사람은 처음부터 " .. tostring(eggObj2.chaseSeconds)
				)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"초기화 300번: 둥지는 매번 105개(공지 씨앗은 일반 씨앗을 갈아끼움 — 한 둥지에 둘 아님), 공지 씨앗은 그 구역 둥지 위에 실제로 있고 구역당 최대 2개, 해커 글리치 공지는 18~21구역에서만",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = eggWorld(H)
				local announces = 0
				local glitchZones = {}
				for cycle = 2, 301 do
					local remote = H.remotes.Announce
					table.clear(remote.firedAll)
					H.setPhase("Intermission", cycle)
					T.eq(countNestEggs(H), 105, "초기화 " .. cycle .. ": 둥지 105개")
					T.eq(#H.map.folders.Eggs.children, 105, "초기화 " .. cycle .. ": 씨앗 파트 105개")
					local perZone = {}
					for _, args in remote.firedAll do
						local info = args[1]
						if info.kind == "rareEgg" then
							announces += 1
							perZone[info.biomeId] = (perZone[info.biomeId] or 0) + 1
							local found
							for _, part in H.map.folders.Eggs.children do
								if part:GetAttribute("EggUid") == info.eggUid then
									found = part
								end
							end
							T.truthy(found ~= nil, "공지된 씨앗이 실제로 없음 " .. tostring(info.eggUid))
							T.eq(found:GetAttribute("EggState"), "Nest")
							T.eq(found:GetAttribute("Special"), true)
							T.eq(found:GetAttribute("PetId"), info.petId)
							T.eq(Plants.get(info.petId).rarity, info.rarity)
							if info.rarity == "hacker_glitch" then
								glitchZones[info.biomeId] = (glitchZones[info.biomeId] or 0) + 1
								T.truthy(
									Biomes.get(info.biomeId).order >= 18,
									"해커 글리치 공지는 18~21구역만: " .. info.biomeId
								)
							end
						end
					end
					for zone, n in perZone do
						T.truthy(n <= EggSpawn.MAX_SPECIALS_PER_BIOME + 2, zone .. " 공지 " .. n)
					end
					H.setPhase("Day", cycle)
				end
				print(
					"      (참고) 300번 초기화 중 공지 씨앗 "
						.. announces
						.. "번 · 해커 글리치 공지 구역별: "
						.. serialize(glitchZones)
				)
				T.truthy(announces > 5, "공지가 너무 적음 " .. announces)
				T.eq(#H.warnings, 0)
			end)
		end
	)
end
