--!nocheck
--[[
	H 시리즈 — "닿아야만 잡힘" · "구역 안에서 놓치면 바로 둥지" 구멍 찾기 (사장님 2026-11-10)
	  "무조건 잡혀야 날아가지 안 잡혔는데 왜 몇 초 뒤 확정 날아감" · "초 지나면 잡힌다고!" · "자기 구역 안에서 떨어뜨리면 바로 둥지로"
	규칙 (GuardianService.updateGuard · EggRules):
	  - 잡힘(EggService.knockOut) = 경비가 쫓는 사람(낮 · 이 구역 씨앗 · canChase)이 수평 거리 ≤ catchDistance(경비 키) 일 때만.
	    시간(egg.chaseSeconds 2.5초/1초)은 쌓이기만 하고 아무 효과 없음 — 잡힘도, 경비 WalkSpeed(돌진)도 안 바뀜.
	  - 도망칠 수 있는 빠른 사람도 닿으면 잡힘. 도망 못 치는 채로 다음 구역 경계(zMax)를 넘으면 즉시 잡힘은 그대로.
	  - EggRules.dropOutcome: 그 씨앗 구역 안이면 원인과 상관없이 ReturnToNest, 밖이면 DropHere.
	    EggRules.groundFate 는 언제나 Return (구역 밖 바닥 씨앗은 5초 뒤 둥지, 주우면 취소 — Stay 없음).
	진짜 EggService + 진짜 GuardianService (경비 몸은 가짜 Humanoid 라 스스로 안 걸음 → 사람을 경비 집 옆에 놓아 "닿음"을 만듦).
65·66번 (2026-11-10): 둥지에서 집으면 경비는 빨간 느낌표(State Alert)를 띄우고 GUARD_WAKE_SECONDS 뒤에 쫓아옴 — 아래 pickUp 은
  "이미 깨어난 뒤"로 치고 (H1~H5 는 깨어난 뒤 규칙), 그 시간 동안 안 잡히는 것은 "둥지 105개 전부" 시험(pickUpRaw)과 services_world 에서 봄.

	  H1 시간이 지나도 멀리 있으면 안 잡힘 · WalkSpeed 불변 (21구역 × 느림/빠름)
	  H2 닿으면 느린·빠른 사람 모두 그 틱에 1번만 잡힘 (21구역) · 잡힘 거리 경계 ±0.3 · 높이 무시
	  H3 안 잡히는 조건 (밤 · 허브 · 기절 · 죽음 · 씨앗 없음 · 다른 구역 씨앗) — 닿아도, 조건이 풀리면 바로 잡힘
	  H4 놓친 씨앗: 구역 안 = 바로 둥지 (바닥 0) / 구역 밖 = 바닥 → 5초 뒤 둥지 · 주우면 취소 · 치트 의심 위치도 Stay 없음
	  H5 경계 즉시 잡힘은 그대로 · 한 틱에 한 명씩
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local S = "ReplicatedStorage/Shared/"
	local Config = Loader.require(S .. "Data/Config")
	local Biomes = Loader.require(S .. "Data/Biomes")
	local MapLayout = Loader.require(S .. "Data/MapLayout")
	local EggRules = Loader.require(S .. "EggRules")
	local SpeedMath = Loader.require(S .. "SpeedMath")

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

	local ALL_ZONES = {}
	for _, b in Biomes.list do
		table.insert(ALL_ZONES, b.id)
	end

	-- 진짜 EggService + 진짜 GuardianService 세상
	local function guardWorld(H)
		local w = { H = H }
		w.EggService = H.server("Services/EggService")
		w.EggService.start()
		w.GuardianService = H.server("Services/GuardianService")
		w.GuardianService.start()
		w.SpeedService = H.server("Services/SpeedService")
		H.setPhase("Intermission", 1)
		H.setPhase("Day", 1)
		H.advance(0.3) -- 경비 키(CatchDistance) Attr 가 채워지는 틱
		return w
	end

	local function newRunner(H, userId, name)
		local p = H.newPlayer(userId, name)
		local session, data = H.login(p)
		session.plotIndex = 1
		session.moveExemptUntil = H.clock() + 1e7
		H.spawn(p, 0, 3, 0)
		return p, session, data
	end

	local function nestEgg(H, biomeId)
		for _, part in H.map.folders.Eggs.children do
			if part:GetAttribute("BiomeId") == biomeId and part:GetAttribute("EggState") == "Nest" then
				return part
			end
		end
		return nil
	end

	-- 진짜로 집기만 (65·66번: 둥지에서 집으면 경비는 느낌표를 띄우고 GUARD_WAKE_SECONDS 뒤에 깨어남)
	local function pickUpRaw(H, p, part)
		H.teleport(p, part.Position.X, part.Position.Y + 1, part.Position.Z)
		part:FindFirstChild("StealPrompt").Triggered:Fire(p)
	end

	-- 집고 "경비가 이미 깨어난 뒤"로 침 (집은 시각을 GUARD_WAKE_SECONDS 앞으로) — 이 파일 H1~H5 는 깨어난 뒤의 닿음 규칙.
	-- 깨어나는 시간 동안 안 잡히는 것은 아래 "둥지 105개 전부" 시험과 services_world 에서 봄
	local function pickUp(H, p, part)
		pickUpRaw(H, p, part)
		local carried = H.server("Services/EggService").getCarried(p)
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

	local function threshold(biomeId)
		return Biomes.get(biomeId).guardSpeed * Config.GUARD_CHASE_MARGIN
	end

	-- 들고 있는 씨앗의 실효 속도를 target 으로 맞춤
	local function setCarrySpeed(w, p, session, data, target)
		data.speed = target / (1 - session.carryPenalty)
		w.SpeedService.refresh(p)
		T.near(session.carrySpeed, target, target * 1e-9 + 1e-9, "들고 있는 속도 맞춤")
	end

	-- 지금부터 limit 초 안에 Caught 가 오면 걸린 시간, 아니면 nil
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

	local function countNestEggs(H)
		local n = 0
		for _, part in H.map.folders.Eggs.children do
			if part:GetAttribute("EggState") == "Nest" then
				n += 1
			end
		end
		return n
	end

	local function floorCount(H)
		local n = 0
		for _, part in H.map.folders.Eggs.children do
			if part:GetAttribute("EggState") == "Dropped" then
				n += 1
			end
		end
		return n
	end

	-- 경비 집에서 (dx, dz) 만큼 떨어진 곳 (경비 몸은 집에 그대로 있음)
	local function nearGuard(H, p, id, dx, dz)
		local home = MapLayout.guardHome(id)
		H.teleport(p, home.x + dx, 3, home.z + (dz or 0))
	end

	local settle = Config.RAGDOLL_SECONDS + 3

	------------------------------------------------------------------
	T.suite("H1 시간이 지나도 멀리 있으면 절대 안 잡힘 (21구역 · 경비 속도도 안 변함)")

	T.test(
		"21구역 전부 × (조금 모자람 2.5초 · 많이 모자람 1초 · 도망 가능): 잡힘 거리 + 0.3 밖에 6초(2.5초의 두 배 넘게) 있어도 안 잡히고 경비 WalkSpeed 는 구역 고정 추격 속도 그대로 · 쌓인 추격 시간은 아무 효과 없음 · 잡힘 거리 - 0.3 안으로 들어가면 그 틱에 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9201, "Waiter")
				for _, id in ALL_ZONES do
					local biome = Biomes.get(id)
					local model = guardModel(H, id)
					local reach = model:GetAttribute("CatchDistance")
					T.truthy(reach ~= nil and reach >= 6 and reach <= 16, id .. ": 잡힘 거리 " .. tostring(reach))
					local chase = SpeedMath.guardChaseSpeed(biome.guardSpeed)
					local humanoid = humanoidOf(model)
					local thr = threshold(id)
					for _, class in
						{
							{ "조금 모자람", thr * 0.85, 2.5 },
							{ "많이 모자람", thr * 0.4, 1 },
							{ "도망 가능", thr * 1.05, nil },
						}
					do
						local tag = id .. " " .. class[1]
						local egg = nestEgg(H, id)
						pickUp(H, p, egg)
						setCarrySpeed(w, p, session, data, class[2])
						T.eq(SpeedMath.catchSeconds(biome.guardSpeed, session.carrySpeed), class[3], tag)
						local eggObj = w.EggService.getCarried(p)
						nearGuard(H, p, id, reach + 0.3, 0) -- 잡힘 거리 바로 밖
						local before = #H.sent(p, "Caught")
						local minWs, maxWs = math.huge, 0
						for step = 1, 120 do -- 6초
							H.advance(0.05)
							if step > 5 then -- 첫 틱(0.1초) 전에는 아직 자는 속도 (원래 속도가 추격 속도보다 약간 빠를 수 있음)
								minWs = math.min(minWs, humanoid.WalkSpeed)
								maxWs = math.max(maxWs, humanoid.WalkSpeed)
							end
						end
						T.near(minWs, chase, 1e-9, tag .. ": 6초 동안 한 번도 느려지지 않음")
						T.eq(#H.sent(p, "Caught"), before, tag .. ": 6초가 지나도 안 닿았으면 안 잡힘")
						T.eq(egg:GetAttribute("EggState"), "Carried", tag)
						T.eq(model:GetAttribute("TargetUserId"), p.UserId, tag .. ": 계속 쫓음")
						T.near(humanoid.WalkSpeed, chase, 1e-9, tag .. ": 경비 속도 = 구역 고정 추격 속도")
						T.near(
							maxWs,
							chase,
							1e-9,
							tag .. ": 6초 동안 한 번도 빨라지지 않음 (돌진 없음)"
						)
						if class[3] then
							T.truthy(
								eggObj.chaseSeconds >= class[3] + 1,
								tag
									.. ": 추격 시간은 쌓임 "
									.. tostring(eggObj.chaseSeconds)
									.. " (그래도 효과 없음)"
							)
						end
						-- 잡힘 거리 바로 안: 그 틱에 잡힘
						nearGuard(H, p, id, reach - 0.3, 0)
						local t = timeToCatch(H, p, 0.4)
						T.truthy(t ~= nil and t <= 0.3, tag .. ": 닿으면 그 틱에 잡힘 " .. tostring(t))
						T.eq(#H.sent(p, "Caught"), before + 1, tag .. ": 한 번")
						T.eq(egg:GetAttribute("EggState"), "Nest", tag .. ": 구역 안 잡힘 = 둥지로")
						H.advance(settle)
					end
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("H2 닿으면 느린 사람도 빠른 사람도 그 틱에 한 번만 잡힘")

	T.test(
		"21구역 전부 × (느림 · 빠름 · 아주 느림 0 · 아주 빠름 1e24): 주운 직후 경비에 닿으면 0.3초 안에 한 번만 잡히고 (knockOut = Caught 알림 1번, 씨앗 둥지로) 그 뒤 몇 초가 지나도 또 안 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9211, "Toucher")
				for _, id in ALL_ZONES do
					local thr = threshold(id)
					local model = guardModel(H, id)
					for _, speed in { thr * 0.4, 0, thr * 0.85, thr * 1.05, 1e24 } do
						local tag = id .. " 속도 " .. string.format("%g", speed)
						local egg = nestEgg(H, id)
						pickUp(H, p, egg)
						setCarrySpeed(w, p, session, data, speed)
						nearGuard(H, p, id, 0, 0) -- 경비 몸에 겹침
						local before = #H.sent(p, "Caught")
						local endedBefore = #H.sent(p, "ChaseEnded")
						local t = timeToCatch(H, p, 0.4)
						T.truthy(t ~= nil and t <= 0.3, tag .. ": 그 틱에 잡힘 " .. tostring(t))
						local list = H.sent(p, "Caught")
						T.eq(#list, before + 1, tag .. ": 한 번")
						T.eq(list[#list][1].cause, "guard")
						T.eq(list[#list][1].eggOutcome, "ReturnToNest", tag .. ": 구역 안 = 둥지로")
						T.eq(egg:GetAttribute("EggState"), "Nest", tag)
						T.eq(w.EggService.getCarried(p), nil, tag .. ": 씨앗 놓음")
						-- 닿은 채로 주워서 경비가 쫓기 시작하기도 전에 잡힘: 쫓은 적이 없으니 ChaseEnded 도 없음 (아래 H5 에서 쫓기던 사람은 caught 1번)
						T.eq(#H.sent(p, "ChaseEnded"), endedBefore, tag .. ": 쫓은 적 없음 = ChaseEnded 없음")
						T.eq(model:GetAttribute("TargetUserId"), 0, tag .. ": 경비 대상 없음")
						H.advance(settle)
						T.eq(#H.sent(p, "Caught"), before + 1, tag .. ": 몇 초가 지나도 또 안 잡힘")
					end
				end
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	T.test(
		"잡힘 거리는 수평 거리만 (경비 키 28 → 13): 14 떨어지면 안 닿고 12.9 면 닿음 · 높이가 달라도(머리 위 50 스터드) 수평으로 겹치면 잡힘 · 대각선도 같음",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9221, "Level")
				local id = "forest"
				local model = guardModel(H, id)
				local reach = model:GetAttribute("CatchDistance")
				T.eq(reach, 13, "숲 경비 키 28 → 6 + 7 = 13")
				local home = MapLayout.guardHome(id)
				local function attempt(label, x, y, z, shouldCatch)
					local egg = nestEgg(H, id)
					pickUp(H, p, egg)
					setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
					H.teleport(p, x, y, z)
					local before = #H.sent(p, "Caught")
					local t = timeToCatch(H, p, 0.6)
					if shouldCatch then
						T.truthy(t ~= nil and t <= 0.3, label .. ": 닿음 " .. tostring(t))
						T.eq(#H.sent(p, "Caught"), before + 1)
						H.advance(settle)
					else
						T.eq(t, nil, label .. ": 안 닿음")
						T.eq(egg:GetAttribute("EggState"), "Carried")
						w.EggService.dropEgg(p) -- 구역 안: 바로 둥지로
						H.advance(0.5)
					end
				end
				attempt("x 로 14", home.x + 14, 3, home.z, false)
				attempt("x 로 12.9", home.x + 12.9, 3, home.z, true)
				attempt("z 로 14", home.x, 3, home.z - 14, false)
				attempt("z 로 12.9", home.x, 3, home.z - 12.9, true)
				attempt("대각선 (10, 10) = 14.14", home.x + 10, 3, home.z + 10, false)
				attempt("대각선 (9, 9) = 12.73", home.x + 9, 3, home.z + 9, true)
				attempt("머리 위 50 스터드 (수평 겹침)", home.x + 1, 53, home.z, true)
				attempt("머리 위 50 스터드 + 수평 14", home.x + 14, 53, home.z, false)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	------------------------------------------------------------------
	T.suite(
		"H3 닿아도 안 잡히는 조건 (밤 · 허브 · 기절 · 죽음 · 씨앗 없음 · 다른 구역 씨앗)"
	)

	T.test(
		"경비에 닿은 채로 1.5초 있어도 안 잡힘: 밤 · 기절 중 · 죽음 · 씨앗을 안 든 사람 · 다른 구역 씨앗을 든 사람 · 허브(안전 구역) — 조건이 풀리면 그 틱에 잡힘 (조건 때문에 안 잡혔다는 증거)",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9231, "Safe")
				local id = "forest"
				local model = guardModel(H, id)
				local rootY = model.PrimaryPart.Position.Y
				local home = MapLayout.guardHome(id)
				local function carryAndTouch()
					local egg = nestEgg(H, id)
					pickUp(H, p, egg)
					setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
					nearGuard(H, p, id, 2, 0)
					return egg
				end
				local function expectSafe(label, egg)
					local before = #H.sent(p, "Caught")
					H.advance(1.5)
					T.eq(#H.sent(p, "Caught"), before, label .. ": 닿아도 안 잡힘")
					T.eq(model:GetAttribute("TargetUserId"), 0, label .. ": 경비가 안 쫓음")
					if egg then
						T.eq(egg:GetAttribute("EggState"), "Carried", label .. ": 씨앗 그대로")
					end
				end
				local function expectCaughtNow(label, egg)
					local before = #H.sent(p, "Caught")
					local t = timeToCatch(H, p, 0.4)
					T.truthy(t ~= nil and t <= 0.3, label .. ": 조건이 풀리자 그 틱에 잡힘 " .. tostring(t))
					T.eq(#H.sent(p, "Caught"), before + 1, label)
					T.eq(egg:GetAttribute("EggState"), "Nest", label)
					H.advance(settle)
				end
				-- 밤
				local egg = carryAndTouch()
				H.setPhase("Night")
				expectSafe("밤", egg)
				H.setPhase("Day", 1)
				expectCaughtNow("밤 → 낮", egg)
				-- 기절 중
				egg = carryAndTouch()
				session.stunnedUntil = H.clock() + 5
				expectSafe("기절", egg)
				session.stunnedUntil = 0
				expectCaughtNow("기절 풀림", egg)
				-- 죽음 (체력 0 = 죽는 중): 경비는 안 쫓고, 씨앗은 죽음으로 둥지로 돌아감
				egg = carryAndTouch()
				p.Character.humanoid.Health = 0
				local before = #H.sent(p, "Caught")
				H.advance(1.5)
				T.eq(#H.sent(p, "Caught"), before, "죽음: 잡힘 알림 없음 (죽음은 잡힘이 아님)")
				T.eq(egg:GetAttribute("EggState"), "Nest", "죽음: 구역 안 = 바로 둥지")
				T.eq(model:GetAttribute("TargetUserId"), 0)
				p.Character.humanoid.Health = 100
				H.advance(settle)
				-- 씨앗을 안 든 사람
				nearGuard(H, p, id, 0, 0)
				T.eq(w.EggService.getCarried(p), nil)
				expectSafe("씨앗 없음", nil)
				-- 다른 구역(호수) 씨앗을 들고 숲 경비에 닿음
				local lakeEgg = nestEgg(H, "lake")
				pickUp(H, p, lakeEgg)
				setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
				nearGuard(H, p, id, 0, 0)
				expectSafe("다른 구역 씨앗", lakeEgg)
				w.EggService.dropCarried(p, "drop") -- 호수 씨앗은 호수 밖에서 놓음: 그 자리 → 5초 뒤 둥지로
				H.advance(6)
				T.eq(lakeEgg:GetAttribute("EggState"), "Nest")
				-- 허브(안전 구역): 경비 몸이 허브 안으로 나와 있다고 쳐도 허브 안 사람은 안 잡힘
				egg = nestEgg(H, id)
				pickUp(H, p, egg)
				setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
				model.PrimaryPart.CFrame = { Position = H.vec(0, rootY, -30) }
				H.teleport(p, 1, 3, -30)
				expectSafe("허브", egg)
				model.PrimaryPart.CFrame = { Position = H.vec(home.x, rootY, home.z) }
				w.EggService.dropCarried(p, "drop") -- 허브 = 숲 씨앗의 구역 밖: 그 자리 → 5초 뒤 둥지로
				H.advance(6)
				T.eq(egg:GetAttribute("EggState"), "Nest")
				T.eq(#H.warnings, 0)
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("H4 놓친 씨앗: 구역 안 = 바로 둥지 · 구역 밖 = 바닥 → 5초 뒤 둥지")

	T.test(
		"EggRules (순수): dropOutcome 은 원인 5개 × 구역 안/밖 전부, groundFate 는 언제나 Return",
		function()
			local zones = {}
			for _, b in Biomes.list do
				table.insert(zones, b.id)
			end
			for _, cause in { "guard", "drop", "player", "death", "leave" } do
				for _, eggZone in zones do
					for _, here in { "hub", nil, eggZone, zones[1], zones[#zones] } do
						local want = if here ~= nil and here == eggZone then "ReturnToNest" else "DropHere"
						T.eq(
							EggRules.dropOutcome(cause, eggZone, here),
							want,
							cause .. " 씨앗 " .. eggZone .. " 놓은 곳 " .. tostring(here)
						)
						T.eq(
							EggRules.groundFate(eggZone, here),
							"Return",
							"groundFate " .. eggZone .. "/" .. tostring(here)
						)
					end
				end
				T.eq(EggRules.dropOutcome(cause, nil, "forest"), "DropHere", cause .. " 구역 모르는 씨앗")
				T.eq(EggRules.dropOutcome(cause, "forest", nil), "DropHere", cause .. " 맵 밖")
			end
		end
	)

	T.test(
		"구역 안에서 놓치면 (21구역 × DropEgg · 방망이 · 곰덫 · 경비 잡힘 · 죽음 · 나감) 바로 둥지: 씨앗은 원래 둥지 자리, 바닥 씨앗 0, 씨앗 파트 105 그대로, 바닥 표시(DroppedAt·ExpiresAt) 없음",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local causes = {
					{
						"DropEgg",
						function(p, id)
							H.client(p, "DropEgg")
						end,
					},
					{
						"방망이",
						function(p, id)
							local pos = p.Character.root.Position
							w.EggService.knockOut(p, H.vec(pos.X + 3, 3, pos.Z), "player", "Bob", 1)
						end,
					},
					{
						"곰덫",
						function(p, id)
							w.EggService.dropCarried(p, "player")
						end,
					},
					{
						"경비 잡힘",
						function(p, id)
							nearGuard(H, p, id, 1, 0)
							H.advance(0.4)
						end,
					},
					{
						"죽음",
						function(p, id)
							p.Character.humanoid.Health = 0
							H.advance(0.5)
						end,
					},
				}
				local runner, session, data = newRunner(H, 9241, "Dropper")
				local n = 0
				for _, id in ALL_ZONES do
					local range = MapLayout.biome(id)
					for _, cause in causes do
						n += 1
						local tag = id .. " " .. cause[1]
						local egg = nestEgg(H, id)
						local home = egg.Position
						pickUp(H, runner, egg)
						setCarrySpeed(w, runner, session, data, threshold(id) * 0.4)
						H.teleport(runner, 20, 3, range.centerZ) -- 구역 안 (경비에게선 멂)
						H.advance(0.3)
						cause[2](runner, id)
						T.eq(egg:GetAttribute("EggState"), "Nest", tag .. ": 구역 안 = 바로 둥지")
						T.eq(egg.Position.X, home.X, tag .. ": 원래 둥지 자리")
						T.eq(egg.Position.Z, home.Z, tag)
						T.eq(egg:GetAttribute("DroppedAt"), nil, tag .. ": 바닥 표시 없음")
						T.eq(egg:GetAttribute("ExpiresAt"), nil, tag)
						T.eq(egg:GetAttribute("ReturnsToNest"), nil, tag)
						T.eq(floorCount(H), 0, tag .. ": 바닥 씨앗 0")
						T.eq(#H.map.folders.Eggs.children, 105, tag .. ": 씨앗 파트 수 그대로")
						T.eq(countNestEggs(H), 105, tag .. ": 둥지 105개 전부 참")
						T.eq(runner.attrs.CarryingEgg, "", tag .. ": 안 들고 있음")
						if cause[1] == "죽음" then
							runner.Character.humanoid.Health = 100
						end
						H.advance(settle)
					end
				end
				T.eq(n, 21 * #causes)
				-- 나감 (구역 안)
				local leaver, sl, dl = newRunner(H, 9242, "Leaver")
				local egg = nestEgg(H, "lake")
				local home = egg.Position
				pickUp(H, leaver, egg)
				setCarrySpeed(w, leaver, sl, dl, threshold("lake") * 1.5)
				H.teleport(leaver, 20, 3, MapLayout.biome("lake").centerZ)
				H.advance(0.3)
				w.EggService.onPlayerLeaving(leaver)
				H.leave(leaver)
				T.eq(egg:GetAttribute("EggState"), "Nest", "나감 (구역 안): 바로 둥지")
				T.eq(egg.Position.X, home.X)
				T.eq(floorCount(H), 0)
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	T.test(
		"구역 밖에서 놓치면 (앞 구역 · 뒤 구역 · 허브 / DropEgg · 방망이 · 곰덫 · 나감): 그 자리 바닥(ExpiresAt = DroppedAt + 5, ReturnsToNest true) → 4.8초엔 바닥, 5.2초엔 원래 둥지 · 5초 안에 줍으면 취소 (5초가 지나도 안 돌아감) · 초기화에 정리",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local lake = MapLayout.biome("lake")
				local places = {
					{ "앞 구역(숲)", 20, 100 },
					{ "뒤 구역(사막)", -20, lake.zMax + 60 },
					{ "허브", 0, -10 },
				}
				local causes = {
					{
						"DropEgg",
						function(p)
							H.client(p, "DropEgg")
						end,
					},
					{
						"방망이",
						function(p)
							local pos = p.Character.root.Position
							w.EggService.knockOut(p, H.vec(pos.X + 3, 3, pos.Z), "player", "Bob", 1)
						end,
					},
					{
						"곰덫",
						function(p)
							w.EggService.dropCarried(p, "player")
						end,
					},
				}
				local id = 9250
				for _, place in places do
					for _, cause in causes do
						id += 1
						local tag = place[1] .. " " .. cause[1]
						local p, session, data = newRunner(H, id, "Out" .. id)
						local egg = nestEgg(H, "lake")
						local home = egg.Position
						pickUp(H, p, egg)
						setCarrySpeed(w, p, session, data, threshold("lake") * 1.5) -- 도망 가능: 경비에 안 닿으면 안 잡힘
						H.teleport(p, place[2], 3, place[3])
						H.advance(0.45) -- 둥지 예약이 풀리는 틱
						cause[2](p)
						T.eq(egg:GetAttribute("EggState"), "Dropped", tag .. ": 구역 밖 = 그 자리 바닥")
						T.eq(egg.Position.Z, place[3], tag)
						T.eq(egg:GetAttribute("ReturnsToNest"), true, tag)
						T.near(
							egg:GetAttribute("ExpiresAt") - egg:GetAttribute("DroppedAt"),
							Config.DROPPED_EGG_RETURN_SECONDS,
							1e-9,
							tag .. ": 5초 카운트다운"
						)
						H.advance(4.8)
						T.eq(egg:GetAttribute("EggState"), "Dropped", tag .. ": 4.8초엔 아직 바닥")
						H.advance(0.4)
						T.eq(egg:GetAttribute("EggState"), "Nest", tag .. ": 5.2초엔 둥지")
						T.eq(egg.Position.X, home.X, tag)
						T.eq(egg.Position.Z, home.Z, tag)
						T.eq(egg:GetAttribute("DroppedAt"), nil, tag .. ": 표시 정리")
						T.eq(egg:GetAttribute("ExpiresAt"), nil, tag)
						T.eq(floorCount(H), 0, tag)
					end
				end
				-- 5초 안에 줍기 → 카운트다운 취소
				local a, sa, da = newRunner(H, 9290, "Dropper")
				local b = newRunner(H, 9291, "Picker")
				local egg = nestEgg(H, "lake")
				pickUp(H, a, egg)
				setCarrySpeed(w, a, sa, da, threshold("lake") * 1.5)
				H.teleport(a, 20, 3, 100)
				H.advance(0.45)
				H.client(a, "DropEgg")
				T.eq(egg:GetAttribute("EggState"), "Dropped")
				H.advance(4.5)
				pickUp(H, b, egg)
				T.eq(egg:GetAttribute("EggState"), "Carried", "5초 직전에 줍기")
				T.eq(egg:GetAttribute("ExpiresAt"), nil, "카운트다운 취소")
				T.eq(egg:GetAttribute("ReturnsToNest"), nil)
				H.advance(8)
				T.eq(egg:GetAttribute("EggState"), "Carried", "5초가 지나도 든 씨앗은 안 돌아감")
				T.eq(#H.map.folders.Eggs.children, 105)
				-- (들고 있는 씨앗은 초기화에도 남는 게 설계라서) 줍은 사람이 구역 밖에서 내려놓고 둥지로 돌아간 뒤에 초기화를 봄
				H.client(b, "DropEgg")
				H.advance(5.5)
				T.eq(egg:GetAttribute("EggState"), "Nest")
				-- 초기화: 바닥에 있는 씨앗도 지워지고 둥지 105개가 새로 채워짐
				local c, sc, dc = newRunner(H, 9292, "Late")
				local egg2 = nestEgg(H, "lake")
				pickUp(H, c, egg2)
				setCarrySpeed(w, c, sc, dc, threshold("lake") * 1.5)
				H.teleport(c, 20, 3, 100)
				H.advance(0.45)
				H.client(c, "DropEgg")
				H.advance(2)
				H.setPhase("Intermission", 2)
				T.truthy(egg2.destroyed, "카운트다운 중인 씨앗도 초기화에 지워짐")
				T.eq(countNestEggs(H), 105)
				T.eq(floorCount(H), 0)
				H.setPhase("Day", 2)
				H.advance(10)
				T.eq(
					#H.map.folders.Eggs.children,
					105,
					"지워진 씨앗의 카운트다운이 뒤늦게 터져도 안 늘어남"
				)
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	T.test(
		"경비가 구역 밖까지 나와 닿아 잡으면 (경비 몸을 숲 쪽으로 옮겨 둠) 그 자리 바닥 → 5초 뒤 둥지 · 치트 의심 위치(dropCarriedAt)는 구역 안이어도 바닥이지만 Stay 없이 5초 뒤 둥지 · 돌아갈 둥지가 없으면 5초 뒤 사라짐 (씨앗 수가 안 늘어남)",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local id = "lake"
				local model = guardModel(H, id)
				local rootY = model.PrimaryPart.Position.Y
				local home0 = MapLayout.guardHome(id)
				local p, session, data = newRunner(H, 9301, "Chased")
				-- (1) 경비가 구역 밖(숲 z=100)에서 닿음
				local egg = nestEgg(H, id)
				local nestHome = egg.Position
				pickUp(H, p, egg)
				setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
				H.teleport(p, 0, 3, 100)
				model.PrimaryPart.CFrame = { Position = H.vec(0, rootY, 100) }
				local t = timeToCatch(H, p, 0.5)
				T.truthy(
					t ~= nil and t <= 0.3,
					"경비가 닿으면 구역 밖에서도 그 틱에 잡힘 " .. tostring(t)
				)
				local caught = H.sent(p, "Caught")
				T.eq(caught[#caught][1].eggOutcome, "DropHere", "구역 밖 = 그 자리")
				T.eq(egg:GetAttribute("EggState"), "Dropped")
				T.eq(egg.Position.Z, 100)
				T.eq(egg:GetAttribute("ReturnsToNest"), true)
				H.advance(5.4)
				T.eq(egg:GetAttribute("EggState"), "Nest", "5초 뒤 둥지")
				T.eq(egg.Position.Z, nestHome.Z)
				model.PrimaryPart.CFrame = { Position = H.vec(home0.x, rootY, home0.z) }
				H.advance(settle)
				-- (2) 치트 의심 위치: 구역 안이어도 바닥에 놓임 (Stay 는 없음) → 5초 뒤 둥지
				local egg2 = nestEgg(H, id)
				local home2 = egg2.Position
				pickUp(H, p, egg2)
				local range = MapLayout.biome(id)
				w.EggService.dropCarriedAt(p, H.vec(20, 3, range.centerZ))
				T.eq(egg2:GetAttribute("EggState"), "Dropped", "치트 의심 위치 = 구역 안 바닥")
				T.eq(MapLayout.zoneAt(egg2.Position.Z), id, "구역 안")
				T.eq(egg2:GetAttribute("ReturnsToNest"), true, "Stay 없음: 카운트다운")
				T.near(egg2:GetAttribute("ExpiresAt") - egg2:GetAttribute("DroppedAt"), 5, 1e-9)
				H.advance(4.8)
				T.eq(egg2:GetAttribute("EggState"), "Dropped")
				H.advance(0.4)
				T.eq(egg2:GetAttribute("EggState"), "Nest", "5초 뒤 둥지")
				T.eq(egg2.Position.X, home2.X)
				-- (3) 둥지가 다시 채워져 돌아갈 곳이 없을 때: 구역 안에서 잡히면 그 자리 바닥 → 5초 뒤 사라짐
				local egg3 = nestEgg(H, id)
				pickUp(H, p, egg3)
				setCarrySpeed(w, p, session, data, threshold(id) * 1.5)
				H.teleport(p, 0, 3, range.zMax + 40) -- 구역 밖: 둥지 예약이 풀림
				H.advance(31)
				T.eq(countNestEggs(H), 105, "빈 둥지가 다시 채워짐")
				setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
				nearGuard(H, p, id, 2, 0) -- 구역 안에서 경비에 닿음
				t = timeToCatch(H, p, 0.5)
				T.truthy(t ~= nil)
				caught = H.sent(p, "Caught")
				T.eq(caught[#caught][1].eggOutcome, "DropHere", "돌아갈 둥지가 없어 그 자리")
				T.eq(egg3:GetAttribute("EggState"), "Dropped")
				T.eq(egg3:GetAttribute("ReturnsToNest"), true)
				H.advance(5.5)
				T.truthy(egg3.destroyed, "갈 곳이 없으면 5초 뒤 사라짐")
				T.truthy(#H.map.folders.Eggs.children <= 105, "씨앗 수가 늘지 않음")
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	T.test(
		"둥지 105개 전부 (65번 — 경비는 무리의 벽 쪽에서 잠, 가장 벽 쪽 둥지는 21구역 모두 잡힘 거리 안): 둥지에서 느리게 집고 그 자리에 서 있어도 WAKE 동안은 안 잡히고 안 쫓음(State Alert — 첫 틱 뒤로는 계속 · TargetUserId 0) → WAKE 가 지나면 닿아 있는 둥지 자리는 그 틱에 잡힘(WAKE ~ WAKE + 한 틱), 안 닿는 둥지 자리는 쫓기만 하고 안 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local WAKE = Config.GUARD_WAKE_SECONDS
				local TICK = Config.GUARD_TICK_SECONDS
				local STEP = 0.01
				T.truthy(
					WAKE >= TICK,
					"깨어나는 시간 = 경비 한 틱 이상 (느낌표가 한 틱은 보여야 함)"
				)
				local caughtNests, chasedNests, total = 0, 0, 0
				local userId = 9600
				for _, id in ALL_ZONES do
					local model = guardModel(H, id)
					local reach = model:GetAttribute("CatchDistance")
					local home = MapLayout.guardHome(id)
					local nearest = math.huge
					for _, nest in MapLayout.nestsFor(id) do
						nearest = math.min(nearest, math.sqrt((nest.x - home.x) ^ 2 + (nest.z - home.z) ^ 2))
					end
					T.truthy(
						nearest < reach,
						string.format(
							"%s: 가장 벽 쪽 둥지 %.2f 는 잡힘 거리 %.2f 안 (그래서 깨어나는 시간이 필요)",
							id,
							nearest,
							reach
						)
					)
					for _, part in table.clone(H.map.folders.Eggs.children) do
						if part:GetAttribute("BiomeId") == id and part:GetAttribute("EggState") == "Nest" then
							total += 1
							userId += 1
							local p, session, data = newRunner(H, userId, "Thief" .. userId)
							local tag = string.format("%s 둥지 %s", id, tostring(part:GetAttribute("EggUid")))
							local d = math.sqrt((part.Position.X - home.x) ^ 2 + (part.Position.Z - home.z) ^ 2)
							pickUpRaw(H, p, part)
							setCarrySpeed(w, p, session, data, threshold(id) * 0.4)
							local t0 = H.clock()
							local caughtAt, chasedAt = nil, nil
							local alertUntilWake, firstAlertAt = true, nil
							while H.clock() - t0 < WAKE + 0.3 do
								H.advance(STEP)
								local elapsed = H.clock() - t0
								if not caughtAt and #H.sent(p, "Caught") > 0 then
									caughtAt = elapsed
								end
								if not chasedAt and model:GetAttribute("TargetUserId") == p.UserId then
									chasedAt = elapsed
								end
								local state = model:GetAttribute("State")
								if state == "Alert" and not firstAlertAt then
									firstAlertAt = elapsed
								end
								-- 훔친 뒤 첫 경비 틱이 지나면 (TICK + 0.02) WAKE 전까지는 계속 Alert (Sleeping · Chase · Return 아님)
								if elapsed < WAKE - 1e-6 and elapsed >= TICK + 0.02 and state ~= "Alert" then
									alertUntilWake = false
								end
							end
							T.truthy(alertUntilWake, tag .. ": WAKE 전에는 State Alert 그대로")
							T.truthy(
								firstAlertAt ~= nil and firstAlertAt <= TICK + STEP + 1e-6,
								tag .. ": 훔친 첫 틱에 Alert " .. tostring(firstAlertAt)
							)
							if d <= reach then
								caughtNests += 1
								T.truthy(
									caughtAt ~= nil
										and caughtAt >= WAKE - 1e-6
										and caughtAt <= WAKE + TICK + STEP + 1e-6,
									tag
										.. string.format(
											" (거리 %.2f ≤ %.2f): WAKE 뒤 첫 틱에 잡힘 ",
											d,
											reach
										)
										.. tostring(caughtAt)
								)
								T.eq(#H.sent(p, "Caught"), 1, tag .. ": 한 번")
								T.eq(part:GetAttribute("EggState"), "Nest", tag .. ": 구역 안 = 바로 둥지")
							else
								chasedNests += 1
								T.eq(
									caughtAt,
									nil,
									tag .. string.format(" (거리 %.2f > %.2f): 안 닿으면 안 잡힘", d, reach)
								)
								T.truthy(
									chasedAt ~= nil
										and chasedAt >= WAKE - 1e-6
										and chasedAt <= WAKE + TICK + STEP + 1e-6,
									tag .. ": WAKE 뒤 첫 틱부터 쫓음 " .. tostring(chasedAt)
								)
								T.eq(model:GetAttribute("State"), "Chase", tag)
								w.EggService.dropEgg(p) -- 구역 안: 바로 둥지
								H.advance(0.2)
							end
							H.leave(p)
							H.advance(0.2)
						end
					end
				end
				T.eq(total, 105, "둥지 105개 전부")
				T.truthy(
					caughtNests >= 21,
					"구역마다 적어도 가장 벽 쪽 둥지는 잡힘 거리 안: " .. caughtNests
				)
				T.truthy(chasedNests >= 21, "닿지 않는 둥지 자리도 있음: " .. chasedNests)
				print(
					string.format(
						"      (참고) 둥지 자리에서 WAKE 뒤 잡힘 %d곳 · 쫓기만 %d곳 (경비 잡힘 거리 안/밖)",
						caughtNests,
						chasedNests
					)
				)
				T.eq(#H.warnings, 0, "서버 warn " .. tostring(H.warnings[1]))
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("H5 경계 즉시 잡힘은 그대로 · 한 틱에 한 명씩")

	T.test(
		"도망 못 치는 채로 다음 구역 경계(zMax)를 넘으면 (경비에게 닿지 않았어도) 0.25초 안에 잡혀 씨앗이 둥지로 — 21구역 중 20곳 · 도망 칠 수 있으면 넘어가도 자유 · 마지막 구역은 맵 끝이라 안 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local p, session, data = newRunner(H, 9401, "Border")
				for _, id in ALL_ZONES do
					local range = MapLayout.biome(id)
					if range.index < MapLayout.BIOME_COUNT then
						local thr = threshold(id)
						for _, class in { { "조금 모자람", 0.85 }, { "많이 모자람", 0.4 }, { "0", 0 } } do
							local tag = id .. " " .. class[1]
							local egg = nestEgg(H, id)
							pickUp(H, p, egg)
							setCarrySpeed(w, p, session, data, thr * class[2])
							H.teleport(p, -50, 3, range.zMax - 0.5) -- 경계 바로 앞 (경비 집에서도 멂: 65번 x -100 에서 50, z 36)
							H.advance(0.1)
							local before = #H.sent(p, "Caught")
							H.teleport(p, -50, 3, range.zMax + 0.5)
							local t = timeToCatch(H, p, 0.5)
							T.truthy(t ~= nil and t <= 0.25, tag .. ": 경계를 넘으면 즉시 " .. tostring(t))
							T.eq(#H.sent(p, "Caught"), before + 1, tag)
							local list = H.sent(p, "Caught")
							T.eq(list[#list][1].eggOutcome, "ReturnToNest", tag .. ": 씨앗은 둥지로")
							T.eq(egg:GetAttribute("EggState"), "Nest", tag)
							H.advance(settle)
						end
						-- 도망 칠 수 있으면 다음 구역에 가도 자유 (경비에 닿지 않는 한)
						local egg = nestEgg(H, id)
						pickUp(H, p, egg)
						setCarrySpeed(w, p, session, data, thr * 1.05)
						H.teleport(p, -50, 3, range.zMax + 20)
						local before = #H.sent(p, "Caught")
						H.advance(4)
						T.eq(#H.sent(p, "Caught"), before, id .. ": 도망 가능하면 다음 구역에서도 자유")
						w.EggService.dropEgg(p) -- 다음 구역 = 이 씨앗의 구역 밖: 그 자리 → 5초 뒤 둥지
						H.advance(6)
						T.eq(egg:GetAttribute("EggState"), "Nest", id)
					end
				end
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"여러 명이 동시에 닿으면 (2026-11-10 H-1 고침) 쫓는 대상이 아니어도 빠른 사람도 한 틱에 모두 잡히고 각자 정확히 한 번만 · 아무도 안 빠짐",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local id = "snow"
				local thr = threshold(id)
				local runners = {}
				-- 가까운 순서: A(0) < B(3) < C(6, 빠른 사람) 모두 잡힘 거리 안
				local plan = { { "A", 0, thr * 0.4 }, { "B", 3, thr * 0.85 }, { "C", 6, thr * 1.1 } }
				for i, spec in plan do
					local p, session, data = newRunner(H, 9500 + i, spec[1])
					local egg = nestEgg(H, id)
					pickUp(H, p, egg)
					setCarrySpeed(w, p, session, data, spec[3])
					runners[i] = { p = p, egg = egg, dx = spec[2] }
				end
				for _, r in runners do
					nearGuard(H, r.p, id, r.dx, 0)
				end
				-- 경비 틱(0.1초): 닿은 사람은 쫓는 대상이 아니어도 그 틱에 전부 잡힘 (A·B·C 같은 틱)
				local caughtAt = {}
				local t0 = H.clock()
				for _ = 1, 40 do
					H.advance(0.02)
					for i, r in runners do
						if not caughtAt[i] and #H.sent(r.p, "Caught") > 0 then
							caughtAt[i] = H.clock() - t0
						end
					end
				end
				T.truthy(caughtAt[1] and caughtAt[2] and caughtAt[3], "0.8초 안에 셋 다 잡힘")
				T.truthy(caughtAt[1] <= 0.15, "첫 틱에 잡힘 " .. caughtAt[1])
				T.near(caughtAt[2], caughtAt[1], 1e-9, "B 도 같은 틱")
				T.near(
					caughtAt[3],
					caughtAt[1],
					1e-9,
					"도망 가능한 C 도 같은 틱 (쫓는 한 명만 판정하던 구멍 H-1 고침)"
				)
				H.advance(settle)
				for i, r in runners do
					T.eq(#H.sent(r.p, "Caught"), 1, plan[i][1] .. ": 각자 한 번만")
					T.eq(r.egg:GetAttribute("EggState"), "Nest", plan[i][1])
				end
				T.eq(countNestEggs(H), 105)
				T.eq(floorCount(H), 0)
				T.eq(#H.warnings, 0)
			end)
		end
	)

	T.test(
		"H-1 고침: 경비가 멀리 있는 느린 사람을 쫓는 동안 경비 몸에 겹친 빠른 사람은 그 틱에 잡히고 (쫓는 대상은 그대로 느린 사람, 안 잡힘) · 쫓기던 사람이 닿으면 ChaseEnded caught 1번 · 닿은 사람이 하나도 없으면 아무도 안 잡힘",
		function()
			inWorld({ realEgg = true }, function(H)
				local w = guardWorld(H)
				local id = "forest"
				local thr = threshold(id)
				local model = guardModel(H, id)
				local range = MapLayout.biome(id)
				local slow, ss, ds = newRunner(H, 9701, "Slow")
				local fast, sf, df = newRunner(H, 9702, "Fast")
				local eggS, eggF = nestEgg(H, id), nil
				pickUp(H, slow, eggS)
				setCarrySpeed(w, slow, ss, ds, thr * 0.4)
				H.teleport(slow, 40, 3, range.zMin + 30) -- 멀리: 경비가 쫓음
				H.advance(0.4)
				T.eq(model:GetAttribute("TargetUserId"), slow.UserId, "경비가 느린 사람을 쫓음")
				-- 안 닿은 사람만 있으면 시간이 지나도 아무도 안 잡힘
				H.advance(3)
				T.eq(#H.sent(slow, "Caught"), 0)
				-- 빠른 사람이 경비 몸 위에 서서 씨앗을 집음 → 쫓는 대상이 따로 있어도 그 틱에 잡힘
				for _, part in H.map.folders.Eggs.children do
					if
						part ~= eggS
						and part:GetAttribute("BiomeId") == id
						and part:GetAttribute("EggState") == "Nest"
					then
						eggF = part
						break
					end
				end
				pickUp(H, fast, eggF)
				setCarrySpeed(w, fast, sf, df, thr * 1.5)
				nearGuard(H, fast, id, 0, 0)
				local t = timeToCatch(H, fast, 0.4)
				T.truthy(t ~= nil and t <= 0.3, "닿은 빠른 사람이 그 틱에 잡힘 " .. tostring(t))
				T.eq(#H.sent(fast, "Caught"), 1, "한 번")
				T.eq(eggF:GetAttribute("EggState"), "Nest")
				T.eq(#H.sent(slow, "Caught"), 0, "멀리 있는 느린 사람은 안 잡힘")
				T.eq(model:GetAttribute("TargetUserId"), slow.UserId, "경비는 계속 느린 사람을 쫓음")
				T.eq(#H.sent(slow, "ChaseEnded"), 0)
				H.advance(settle)
				T.eq(#H.sent(fast, "Caught"), 1, "또 안 잡힘")
				-- 쫓기던 사람이 닿음 → ChaseEnded caught 정확히 1번, 한 번만 잡힘
				nearGuard(H, slow, id, 3, 0)
				t = timeToCatch(H, slow, 0.4)
				T.truthy(t ~= nil and t <= 0.3, "쫓기던 사람이 닿으면 그 틱에 잡힘 " .. tostring(t))
				local ended = H.sent(slow, "ChaseEnded")
				T.eq(#ended, 1, "ChaseEnded 한 번")
				T.eq(ended[1][1].reason, "caught")
				T.eq(model:GetAttribute("TargetUserId"), 0)
				H.advance(settle)
				T.eq(#H.sent(slow, "Caught"), 1)
				T.eq(#H.sent(slow, "ChaseEnded"), 1)
				T.eq(countNestEggs(H), 105)
				T.eq(#H.warnings, 0)
			end)
		end
	)
end
