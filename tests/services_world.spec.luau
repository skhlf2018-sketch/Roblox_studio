--!nocheck
--[[
	서비스 테스트 5: EggService(알 놓기·줍기·들기·놓치기·둥지 예약) + GuardianService(경비 추격·잡힘)
	게임의 심장인 "알 훔치기 ↔ 경비" 규칙을 진짜 서비스 코드로 돌립니다 (가짜 Part/Humanoid, 가상 시간).
	경비가 실제로 걸어서 쫓아가는 물리는 로블록스 엔진 몫이라 여기서는 안 봅니다 (스튜디오 체크리스트에서 확인):
	이 테스트는 "누구를 쫓나 / 얼마나 빠르게 / 언제 잡히나 / 잡히면 알이 어떻게 되나" 의 판단만 봅니다.
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function eggParts(H)
		local folder = H.map.folders.Eggs
		return if folder then folder.children else {}
	end

	local function findEgg(H, uid)
		for _, part in eggParts(H) do
			if part:GetAttribute("EggUid") == uid then
				return part
			end
		end
		return nil
	end

	local function nestEgg(H, biomeId)
		for _, part in eggParts(H) do
			if part:GetAttribute("BiomeId") == biomeId and part:GetAttribute("EggState") == "Nest" then
				return part
			end
		end
		return nil
	end

	local function announces(H, kind)
		local list = {}
		for _, args in H.remotes.Announce.firedAll do
			if args[1].kind == kind then
				table.insert(list, args[1])
			end
		end
		return list
	end

	local function eggWorld()
		local H = ServerHarness.install(Loader, T, { realEgg = true })
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.Biomes = H.shared("Data/Biomes")
		w.Pets = H.shared("Data/Pets")
		w.Sizes = H.shared("Data/Sizes")
		w.SpeedMath = H.shared("SpeedMath")
		w.Sessions = H.server("Sessions")
		w.EggService = H.server("Services/EggService")
		w.EggService.start()
		w.player = H.newPlayer(1001, "Tester")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		H.spawn(w.player, 0, 3, 0)
		H.setPhase("Intermission", 1) -- 첫 초기화: 모든 둥지에 알이 놓임
		H.setPhase("Day", 1)
		return w
	end

	-- 그 구역 첫 둥지 알 옆으로 가서 E 키(ProximityPrompt)를 누름
	local function pressE(w, egg, player)
		local who = player or w.player
		w.H.teleport(who, egg.Position.X, egg.Position.Y, egg.Position.Z)
		egg:FindFirstChild("StealPrompt").Triggered:Fire(who)
	end

	local function zoneCenter(w, biomeId)
		local zone = w.H.map.zones[biomeId]
		return zone.centerX, zone.centerZ
	end

	------------------------------------------------------------------
	T.suite("서비스: EggService 초기화·알 놓기")

	T.test(
		"초기화마다 15구역 × 둥지 8개 = 알 120개, 'ALL EGG RESET!' 공지, 알은 둥지 위에 놓임",
		function()
			local w = eggWorld()
			local all = eggParts(w.H)
			T.eq(#all, 120)
			local perBiome = {}
			for _, egg in all do
				local biomeId = egg:GetAttribute("BiomeId")
				perBiome[biomeId] = (perBiome[biomeId] or 0) + 1
				T.eq(egg:GetAttribute("EggState"), "Nest")
				T.truthy(egg.Position.Y > 1.4, "둥지(윗면 1.4) 위에 놓임")
				T.truthy(egg:FindFirstChild("StealPrompt"), "줍기 프롬프트")
			end
			for _, biome in w.Biomes.list do
				T.eq(perBiome[biome.id], 8, biome.id)
			end
			T.eq(#announces(w.H, "reset"), 1)
			w.H.uninstall()
		end
	)

	T.test(
		"알의 펫은 그 구역 둥지 펫 풀에서만, 특별 알이 아니면 앞 구역엔 비밀·영원·신성 없음(2판 수정: 뒤 구역은 일반 스폰도 됨), 천사&악마는 이번 주기 쪽 펫만",
		function()
			local w = eggWorld()
			local EggRoll = w.H.shared("EggRoll")
			local function check(cycle)
				for _, egg in eggParts(w.H) do
					local pet = w.Pets.get(egg:GetAttribute("PetId"))
					T.eq(pet.biome, egg:GetAttribute("BiomeId"))
					-- 5판: 둥지 풀 밖 특별 알(옛 퀘스트 알, source = special)은 초기화 특별 알로만
					T.truthy(
						pet.source == "nest" or (pet.source == "special" and egg:GetAttribute("Special") == true),
						pet.id
					)
					if not egg:GetAttribute("Special") then
						-- 일반 스폰은 가중치가 있는 펫만 (비밀 이상은 그 구역 중심 ±2 안일 때만)
						T.truthy(EggRoll.nestWeight(pet) > 0, pet.id)
					else
						T.truthy(
							pet.rarity == "secret"
								or pet.rarity == "eternity"
								or pet.rarity == "divine"
								or pet.rarity == "super_ultradivine",
							pet.id
						)
					end
					if pet.biome == "angels_demons" then
						T.eq(pet.side, if cycle % 2 == 1 then "light" else "dark", pet.id .. " 주기 " .. cycle)
					end
					T.truthy(w.Sizes.get(egg:GetAttribute("Size")), "크기")
				end
			end
			check(1)
			w.H.setPhase("Intermission", 2)
			check(2)
			w.H.uninstall()
		end
	)

	T.test(
		"초기화를 60번 반복해도 알이 새지 않고(항상 120개) 희귀 알 공지가 가끔 나옴 (비밀 8%·영원 2%·신성 0.2%)",
		function()
			local w = eggWorld()
			local seen = #announces(w.H, "rareEgg") -- 첫 초기화(주기 1)에서 이미 나온 것은 제외
			local firstSeen = seen
			for cycle = 2, 61 do
				w.H.setPhase("Intermission", cycle)
				T.eq(#eggParts(w.H), 120, "주기 " .. cycle)
				-- 공지한 알은 그 초기화 직후에는 진짜 있어야 함 (다음 초기화 때 지워짐)
				local rare = announces(w.H, "rareEgg")
				for i = seen + 1, #rare do
					local a = rare[i]
					T.truthy(
						a.rarity == "secret"
							or a.rarity == "eternity"
							or a.rarity == "divine"
							or a.rarity == "super_ultradivine",
						a.rarity
					)
					T.truthy(
						string.find(a.text, "구역에", 1, true) and string.find(a.text, "씨앗 등장!", 1, true),
						a.text
					)
					local egg = findEgg(w.H, a.eggUid)
					T.truthy(egg, "공지한 알이 실제로 있음")
					T.eq(egg:GetAttribute("Special"), true)
					T.eq(egg:GetAttribute("PetId"), a.petId)
				end
				seen = #rare
			end
			T.truthy(
				seen - firstSeen >= 10,
				"희귀 알 공지 " .. (seen - firstSeen) .. "번 (60주기 × 15구역 = 900번 추첨)"
			)
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: EggService 줍기 (E 키) — 성공과 거부")

	T.test(
		"낮에 둥지 알 옆에서 E: 머리 위로 듦 + RUN!! 알림(경비 이름·속도) + 속도 느려짐 + 통계",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			local penalty = w.Sizes.get(egg:GetAttribute("Size")).speedPenalty
			local freeWalk = w.player.Character.humanoid.WalkSpeed
			pressE(w, egg)
			T.eq(egg:GetAttribute("EggState"), "Carried")
			T.eq(w.player.attrs.CarryingEgg, egg:GetAttribute("EggUid"))
			T.eq(w.player.attrs.CarryingBiome, "forest")
			T.eq(egg:FindFirstChild("StealPrompt").Enabled, false)
			T.truthy(egg:FindFirstChild("CarryWeld"), "머리에 용접")
			T.eq(w.data.stats.eggsStolen, 1)
			local alert = w.H.sent(w.player, "RunAlert")[1][1]
			T.eq(alert.egg.biomeId, "forest")
			T.eq(alert.guardName, "덥석 파리지옥")
			T.near(alert.guardSpeed, 9, 1e-9, "숲 추천 10 × (1 - 보통 알 0.1)")
			T.near(alert.yourSpeed, w.Config.STARTING_SPEED * (1 - penalty), 1e-9)
			T.near(
				w.player.Character.humanoid.WalkSpeed,
				w.SpeedMath.carryWalkSpeed(w.Config.STARTING_SPEED, penalty),
				1e-9,
				"알 무게만큼 느려짐"
			)
			T.truthy(w.player.Character.humanoid.WalkSpeed < w.SpeedMath.toWalkSpeed(w.Config.STARTING_SPEED))
			_ = freeWalk
			w.H.uninstall()
		end
	)

	T.test(
		"거부: 밤 / 이미 알을 들고 있음 / 남이 든 알 / 기절 / 죽음 / 없는 알 번호",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			w.H.setPhase("Night")
			pressE(w, egg)
			T.eq(egg:GetAttribute("EggState"), "Nest")
			T.truthy(w.H.hasNotify(w.player, "error", "밤에는 씨앗을 훔칠 수 없어요"))
			w.H.setPhase("Day")
			-- 기절
			w.session.stunnedUntil = w.H.clock() + 3
			pressE(w, egg)
			T.eq(egg:GetAttribute("EggState"), "Nest", "기절 중")
			w.H.advance(3.1)
			-- 죽음
			w.player.Character.humanoid.Health = 0
			pressE(w, egg)
			T.eq(egg:GetAttribute("EggState"), "Nest", "죽음")
			w.player.Character.humanoid.Health = 100
			-- 정상 줍기 후 두 번째 알은 못 줍고, 다른 사람은 이미 든 알을 못 뺏음
			pressE(w, egg)
			T.eq(egg:GetAttribute("EggState"), "Carried")
			local second = nestEgg(w.H, "forest")
			pressE(w, second)
			T.eq(second:GetAttribute("EggState"), "Nest")
			T.truthy(w.H.hasNotify(w.player, "error", "이미 씨앗을 들고 있어요"))
			local thief = w.H.newPlayer(1002, "Thief")
			w.H.login(thief)
			w.H.spawn(thief, egg.Position.X, egg.Position.Y, egg.Position.Z)
			w.EggService.tryPickup(thief, egg:GetAttribute("EggUid"))
			T.eq(thief.attrs.CarryingEgg, nil)
			w.EggService.tryPickup(thief, "e99999")
			w.EggService.tryPickup(thief, "")
			w.H.uninstall()
		end
	)

	T.test(
		"줍기 거리 경계: 12 + 알 반지름 이내는 되고 0.1 더 멀면 안 됨 (서버가 거리를 직접 확인)",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			local limit = w.Config.PICKUP_DISTANCE + egg.Size.X / 2
			w.H.teleport(w.player, egg.Position.X + limit + 0.1, egg.Position.Y, egg.Position.Z)
			w.EggService.tryPickup(w.player, egg:GetAttribute("EggUid"))
			T.eq(egg:GetAttribute("EggState"), "Nest", "0.1 멀면 거부")
			w.H.teleport(w.player, egg.Position.X + limit, egg.Position.Y, egg.Position.Z)
			w.EggService.tryPickup(w.player, egg:GetAttribute("EggUid"))
			T.eq(egg:GetAttribute("EggState"), "Carried", "경계는 허용")
			w.H.uninstall()
		end
	)

	T.test(
		"6판: 공지 씨앗(세계수)도 공지 특별 씨앗으로 놓이고, 퀘스트 없이 누구나 바로 주움",
		function()
			local w = eggWorld()
			local uid = w.EggService.spawnSpecialEgg("enchanted_forest", "world_tree", { announce = true })
			local egg = findEgg(w.H, uid)
			T.truthy(egg and egg:GetAttribute("Special"))
			T.eq(egg:GetAttribute("QuestOnly"), nil, "퀘스트 전용 표시 없음")
			T.eq(egg:GetAttribute("BiomeId"), "enchanted_forest")
			local rare = announces(w.H, "rareEgg")
			T.eq(rare[#rare].petId, "world_tree")
			T.eq(rare[#rare].eggUid, uid)
			T.eq(rare[#rare].questOnly, nil)
			T.falsy(string.find(rare[#rare].text, "퀘스트", 1, true))
			pressE(w, egg)
			T.eq(egg:GetAttribute("EggState"), "Carried")
			w.H.uninstall()
		end
	)

	T.test(
		"5판: 초기화 100번 — EXTRA_SPECIALS(춤추는 버섯 8%)가 마법의 숲에 공지되며 놓이고, 같은 초기화의 다른 특별 알을 안 지움",
		function()
			local w = eggWorld()
			local seen = #announces(w.H, "rareEgg")
			local jitter = 0
			for cycle = 2, 101 do
				w.H.setPhase("Intermission", cycle)
				local rare = announces(w.H, "rareEgg")
				for i = seen + 1, #rare do
					local a = rare[i]
					local egg = findEgg(w.H, a.eggUid)
					T.truthy(egg and egg:GetAttribute("Special"), "공지한 알이 그대로 있음 " .. a.petId)
					if a.petId == "dancing_mushroom" or a.petId == "world_tree" then
						T.eq(a.biomeId, "enchanted_forest")
						T.eq(egg:GetAttribute("BiomeId"), "enchanted_forest")
						if a.petId == "dancing_mushroom" then
							jitter += 1
						end
					end
				end
				seen = #rare
				T.eq(#eggParts(w.H), 120, "알 수는 그대로 " .. cycle)
			end
			T.truthy(jitter >= 2 and jitter <= 20, "춤추는 버섯 공지 " .. jitter .. "번 (100번 × 8% ≈ 8)")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: EggService 놓치기 (잡힘 규칙: 구역 안 → 둥지로, 밖 → 그 자리)")

	T.test(
		"경비한테 알의 구역 안에서 잡히면 알이 원래 둥지로 돌아가고, 몸은 날아가 2.5초 기절",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			local home = egg.Position
			pressE(w, egg)
			local cx, cz = zoneCenter(w, "forest")
			w.H.teleport(w.player, cx, 3, cz)
			w.EggService.knockOut(w.player, w.H.vec(cx + 5, 3, cz), "guard", "닭")
			T.eq(egg:GetAttribute("EggState"), "Nest")
			T.eq(egg.Position.X, home.X, "원래 둥지 자리")
			T.eq(egg.Position.Z, home.Z)
			T.eq(egg:FindFirstChild("StealPrompt").Enabled, true)
			T.eq(w.player.attrs.CarryingEgg, "")
			local caught = w.H.sent(w.player, "Caught")[1][1]
			T.eq(caught.cause, "guard")
			T.eq(caught.by, "닭")
			T.eq(caught.eggOutcome, "ReturnToNest")
			T.eq(caught.ragdollSeconds, w.Config.RAGDOLL_SECONDS)
			T.truthy(caught.knockback ~= nil)
			T.eq(w.player.attrs.Stunned, true)
			T.truthy(w.player.Character.humanoid.PlatformStand)
			T.truthy(w.session.stunnedUntil > w.H.clock())
			w.H.advance(w.Config.RAGDOLL_SECONDS + 0.2)
			T.falsy(w.player.Character.humanoid.PlatformStand)
			T.eq(w.player.attrs.Stunned, false)
			w.H.uninstall()
		end
	)

	T.test(
		"구역 밖에서 잡히면 알이 그 자리에 떨어지고(누구나 줍기), 60초 뒤 사라짐 (2판 수정 120 → 60)",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			pressE(w, egg)
			w.H.teleport(w.player, 0, 3, -60) -- 숲 구역(z 0~240) 밖 = 허브
			w.EggService.knockOut(w.player, w.H.vec(5, 3, -60), "guard", "닭")
			T.eq(egg:GetAttribute("EggState"), "Dropped")
			T.eq(egg.Position.X, 0)
			T.eq(egg.Position.Z, -60)
			T.eq(w.H.sent(w.player, "Caught")[1][1].eggOutcome, "DropHere")
			-- 다른 사람이 주울 수 있음
			local other = w.H.newPlayer(1002, "Other")
			w.H.login(other)
			w.H.spawn(other, 0, 3, -60)
			egg:FindFirstChild("StealPrompt").Triggered:Fire(other)
			T.eq(egg:GetAttribute("EggState"), "Carried")
			T.eq(other.attrs.CarryingEgg, egg:GetAttribute("EggUid"))
			-- 이번엔 아무도 안 주우면 60초 뒤 사라짐
			T.eq(w.Config.DROPPED_EGG_LIFETIME, 60)
			local egg2 = nestEgg(w.H, "lake")
			w.H.advance(w.Config.RAGDOLL_SECONDS + 0.1) -- 방금 잡혀서 기절 중이었음
			pressE(w, egg2)
			T.eq(egg2:GetAttribute("EggState"), "Carried")
			w.H.teleport(w.player, 0, 3, 0)
			w.EggService.dropCarried(w.player, "guard")
			T.eq(egg2:GetAttribute("EggState"), "Dropped")
			w.H.advance(59)
			T.falsy(egg2.destroyed, "59초")
			w.H.advance(2)
			T.truthy(egg2.destroyed, "60초가 넘으면 사라짐")
			w.H.uninstall()
		end
	)

	T.test("다른 사람(방망이·곰덫)에게 당하면 구역 안이어도 그 자리에 떨어짐", function()
		local w = eggWorld()
		local egg = nestEgg(w.H, "forest")
		pressE(w, egg)
		local cx, cz = zoneCenter(w, "forest")
		w.H.teleport(w.player, cx + 10, 3, cz)
		w.EggService.knockOut(w.player, w.H.vec(cx, 3, cz), "player", "Bob", 1.5)
		T.eq(egg:GetAttribute("EggState"), "Dropped")
		T.eq(egg.Position.X, cx + 10)
		T.eq(w.H.sent(w.player, "Caught")[1][1].cause, "player")
		w.H.uninstall()
	end)

	T.test(
		"죽으면 구역 규칙(안 → 둥지), 나가면(leave) 구역 밖이면 그 자리 / 알이 없으면 eggOutcome = None",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			pressE(w, egg)
			local cx, cz = zoneCenter(w, "forest")
			w.H.teleport(w.player, cx, 3, cz)
			T.eq(w.EggService.dropCarried(w.player, "death"), "ReturnToNest")
			local egg2 = nestEgg(w.H, "lake")
			pressE(w, egg2)
			w.H.teleport(w.player, 0, 3, 0)
			T.eq(w.EggService.dropCarried(w.player, "leave"), "DropHere")
			T.eq(egg2:GetAttribute("EggState"), "Dropped")
			T.eq(w.EggService.dropCarried(w.player, "death"), nil, "들고 있는 알이 없음")
			w.EggService.knockOut(w.player, w.H.vec(1, 3, 1), "guard", "닭")
			local caught = w.H.sent(w.player, "Caught")
			T.eq(caught[#caught][1].eggOutcome, "None")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: EggService 둥지 예약·다시 채우기")

	T.test(
		"알을 든 채 구역 안에 있는 동안은 둥지가 비어 있고, 구역을 벗어나 30초 뒤에야 새 알이 놓임 (낮에만)",
		function()
			local w = eggWorld()
			local before = #eggParts(w.H)
			local egg = nestEgg(w.H, "forest")
			local nestX, nestZ = egg.Position.X, egg.Position.Z
			pressE(w, egg)
			local cx, cz = zoneCenter(w, "forest")
			w.H.teleport(w.player, cx, 3, cz)
			w.H.advance(120)
			T.eq(#eggParts(w.H), before, "구역 안에서는 다시 안 채움")
			-- 구역 밖(z < 0 허브)으로 → 0.2초 틱에서 예약 해제 → 30초 뒤 새 알
			w.H.teleport(w.player, 0, 3, -60)
			w.H.advance(1)
			w.H.advance(28)
			T.eq(#eggParts(w.H), before, "예약 해제 후 30초가 안 지남")
			w.H.advance(3)
			T.eq(#eggParts(w.H), before + 1, "새 알이 놓임")
			local refilled = false
			for _, part in eggParts(w.H) do
				if
					part ~= egg
					and part:GetAttribute("EggState") == "Nest"
					and part.Position.X == nestX
					and part.Position.Z == nestZ
				then
					refilled = true
				end
			end
			T.truthy(refilled, "같은 둥지에")
			w.H.uninstall()
		end
	)

	T.test(
		"2판 수정 드롭한 알: 그 자리에 남고 DroppedAt/ExpiresAt(서버 시각) 카운트다운, 사라지기 전엔 그 둥지 안 채움 → 사라지고 30초 뒤 채움, 다시 주우면 카운트다운 지움",
		function()
			local w = eggWorld()
			local before = #eggParts(w.H)
			local egg = nestEgg(w.H, "forest")
			local nestX, nestZ = egg.Position.X, egg.Position.Z
			pressE(w, egg)
			local x, z = w.H.zoneSpot("forest")
			w.H.teleport(w.player, x + 7, 3, z) -- 알의 구역 안
			local t0 = w.H.clock() -- 가짜 workspace:GetServerTimeNow() = 가상 시계
			w.H.client(w.player, "DropEgg")
			T.eq(egg:GetAttribute("EggState"), "Dropped")
			T.eq(egg.Position.X, x + 7, "둥지로 안 가고 그 자리")
			T.eq(egg:GetAttribute("DroppedAt"), t0)
			T.eq(
				egg:GetAttribute("ExpiresAt"),
				t0 + w.Config.DROPPED_EGG_LIFETIME,
				"남은 시간 = ExpiresAt - 지금"
			)
			-- 다시 주우면 카운트다운 지움, 다시 버리면 새로 60초
			w.H.advance(10)
			pressE(w, egg)
			T.eq(egg:GetAttribute("ExpiresAt"), nil, "들고 있는 동안은 카운트다운 없음")
			T.eq(egg:GetAttribute("DroppedAt"), nil)
			w.H.teleport(w.player, x + 7, 3, z)
			w.EggService.dropEgg(w.player)
			local t1 = w.H.clock()
			T.eq(egg:GetAttribute("ExpiresAt"), t1 + 60)
			-- 바닥에 있는 동안(60초)은 그 둥지가 비어 있음 (낮 30초 다시 채우기 안 함)
			w.H.advance(59)
			T.falsy(egg.destroyed)
			T.eq(#eggParts(w.H), before, "떨어진 알이 있는 동안은 둥지를 안 채움")
			w.H.advance(1.5)
			T.truthy(egg.destroyed, "60초 지나면 사라짐")
			T.eq(#eggParts(w.H), before - 1)
			w.H.advance(29)
			T.eq(#eggParts(w.H), before - 1, "사라지고 30초가 안 지남")
			w.H.advance(2)
			T.eq(#eggParts(w.H), before, "사라진 뒤 30초 → 그 둥지에 새 알")
			local refilled = false
			for _, part in eggParts(w.H) do
				if
					part:GetAttribute("EggState") == "Nest"
					and part.Position.X == nestX
					and part.Position.Z == nestZ
				then
					refilled = true
				end
			end
			T.truthy(refilled, "같은 둥지")
			-- 떨어진 알을 다시 주워 그 구역 안에서 경비에게 잡히면 둥지로 (둥지 복귀는 이때만)
			local egg3 = nestEgg(w.H, "lake")
			pressE(w, egg3)
			local lx, lz = w.H.zoneSpot("lake")
			w.H.teleport(w.player, lx, 3, lz)
			w.EggService.dropEgg(w.player)
			pressE(w, egg3)
			T.eq(w.EggService.dropCarried(w.player, "guard"), "ReturnToNest")
			T.eq(egg3:GetAttribute("EggState"), "Nest")
			T.eq(egg3:GetAttribute("ExpiresAt"), nil)
			-- 초기화(대기)가 오면 떨어진 알은 지워지고 모든 둥지가 새로 채워짐
			local egg4 = nestEgg(w.H, "snow")
			pressE(w, egg4)
			w.EggService.dropEgg(w.player)
			w.H.setPhase("Intermission", 2)
			T.truthy(egg4.destroyed)
			T.eq(#eggParts(w.H), 120, "둥지 120개 전부 새 알")
			w.H.uninstall()
		end
	)

	T.test("밤에는 둥지 다시 채우기가 멈춤", function()
		local w = eggWorld()
		local egg = nestEgg(w.H, "forest")
		pressE(w, egg)
		w.H.teleport(w.player, 0, 3, -60)
		w.H.advance(1)
		local count = #eggParts(w.H)
		w.H.setPhase("Night")
		w.H.advance(60)
		T.eq(#eggParts(w.H), count, "밤")
		w.H.setPhase("Day")
		w.H.advance(1)
		T.eq(#eggParts(w.H), count + 1, "아침이 되자 채움")
		w.H.uninstall()
	end)

	T.test(
		"초기화(대기)가 와도 든 알은 안 지워지고, 둥지 120개는 새 알로 전부 채워짐 (들고 있는 알 + 120 = 121)",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			pressE(w, egg)
			w.H.setPhase("Intermission", 2)
			T.eq(egg:GetAttribute("EggState"), "Carried")
			T.falsy(egg.destroyed)
			T.eq(#eggParts(w.H), 121)
			-- 든 알은 예약이 풀려서, 이제 구역 안에서 잡혀도 빈 둥지가 없어 그 자리에 떨어짐 (설계상 허용되는 모서리 경우)
			local cx, cz = zoneCenter(w, "forest")
			w.H.teleport(w.player, cx, 3, cz)
			T.eq(w.EggService.dropCarried(w.player, "guard"), "DropHere")
			w.H.uninstall()
		end
	)

	T.test(
		"takeCarried(배달): 알이 세상에서 사라지고 데이터만 돌려줌 / confiscate: 둥지로 돌아감 / dropCarriedAt: 지정 위치",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			local uid = egg:GetAttribute("EggUid")
			local petId = egg:GetAttribute("PetId")
			pressE(w, egg)
			local delivered = w.EggService.takeCarried(w.player)
			T.eq(delivered.petId, petId)
			T.eq(delivered.biomeId, "forest")
			T.truthy(egg.destroyed)
			T.eq(w.player.attrs.CarryingEgg, "")
			T.eq(w.session.carryPenalty, 0)
			T.eq(w.EggService.takeCarried(w.player), nil)
			T.eq(w.EggService.getCarried(w.player), nil)
			T.falsy(findEgg(w.H, uid))

			local egg2 = nestEgg(w.H, "forest")
			pressE(w, egg2)
			w.EggService.confiscate(w.player)
			T.eq(egg2:GetAttribute("EggState"), "Nest")

			local egg3 = nestEgg(w.H, "forest")
			pressE(w, egg3)
			w.EggService.dropCarriedAt(w.player, w.H.vec(50, 0, 60))
			T.eq(egg3:GetAttribute("EggState"), "Dropped")
			T.eq(egg3.Position.X, 50)
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: EggService 2판 (DropEgg · 무게 · 유예 · z 범위 구역)")

	T.test(
		"알 무게: 들면 CarryWeightKg = 크기별 kg(보통 50 / 큼 120 / 거대 400 / 초거대 1200), 알 파트 WeightKg, RunAlert.weightKg, 놓으면 0",
		function()
			local w = eggWorld()
			local expected = { normal = 50, big = 120, huge = 400, giant = 1200 }
			for id, kg in expected do
				T.eq(w.Sizes.get(id).carryKg, kg, id)
			end
			local egg = nestEgg(w.H, "forest")
			local kg = expected[egg:GetAttribute("Size")]
			T.eq(egg:GetAttribute("WeightKg"), kg)
			pressE(w, egg)
			T.eq(w.player.attrs.CarryWeightKg, kg)
			T.eq(w.H.sent(w.player, "RunAlert")[1][1].weightKg, kg)
			w.EggService.dropCarried(w.player, "guard")
			T.eq(w.player.attrs.CarryWeightKg, 0)
			w.H.uninstall()
		end
	)

	T.test(
		"DropEgg: 알의 구역 안이어도 그 자리에 떨어짐(둥지로 안 감) + 안내, 알이 없으면 아무 일 없음, 레이트 리밋",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			pressE(w, egg)
			local x, z = w.H.zoneSpot("forest")
			w.H.teleport(w.player, x + 7, 3, z)
			w.H.client(w.player, "DropEgg")
			T.eq(egg:GetAttribute("EggState"), "Dropped")
			T.eq(egg.Position.X, x + 7, "그 자리")
			T.eq(egg.Position.Z, z)
			T.eq(w.player.attrs.CarryingEgg, "")
			T.eq(w.player.attrs.CarryWeightKg, 0)
			T.truthy(w.H.hasNotify(w.player, "info", "씨앗을 내려놓았어요"))
			local before = #w.H.notifications(w.player)
			w.H.client(w.player, "DropEgg") -- 알 없음
			T.eq(#w.H.notifications(w.player), before)
			w.H.uninstall()
		end
	)

	T.test(
		"경비 유예(1.5초)는 둥지에서 주울 때만 — 버린 알을 다시 주우면 유예 없음 (버렸다 줍기로 못 버팀)",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "forest")
			pressE(w, egg)
			local carried = w.EggService.getCarried(w.player)
			T.near(carried.graceUntil, carried.pickedAt + w.Config.GUARD_CATCH_GRACE_SECONDS, 1e-9, "둥지")
			w.EggService.dropEgg(w.player)
			w.H.advance(0.5)
			pressE(w, egg)
			carried = w.EggService.getCarried(w.player)
			T.eq(carried.graceUntil, carried.pickedAt, "바닥 알은 유예 없음")
			w.H.uninstall()
		end
	)

	T.test(
		"구역 = z 범위: 호수 알을 들고 앞 구역(숲, z < 240)으로 넘어가면 둥지 예약이 풀리고, 거기서 잡히면 그 자리",
		function()
			local w = eggWorld()
			local egg = nestEgg(w.H, "lake")
			pressE(w, egg)
			w.H.teleport(w.player, 0, 3, 240) -- 호수 시작선 = 아직 호수
			w.H.advance(0.4)
			local carried = w.EggService.getCarried(w.player)
			T.eq(carried.nestBiome, "lake", "호수 안: 예약 유지")
			T.eq(w.EggService.dropCarried(w.player, "guard"), "ReturnToNest")
			pressE(w, egg)
			w.H.teleport(w.player, 0, 3, 239.9) -- 숲
			w.H.advance(0.4)
			carried = w.EggService.getCarried(w.player)
			T.eq(carried.nestBiome, nil, "숲으로 넘어가자 예약 해제")
			T.eq(w.EggService.dropCarried(w.player, "guard"), "DropHere")
			w.H.uninstall()
		end
	)

	T.test("둥지 자리 = MapLayout.nestsFor (구역마다 8개, 그 구역 z 범위 안)", function()
		local w = eggWorld()
		local MapLayout = w.H.MapLayout
		for _, b in MapLayout.biomes do
			local positions = w.EggService.nestPositions(b.id)
			T.eq(#positions, 8, b.id)
			for i, p in positions do
				T.eq(MapLayout.zoneAt(p.Z), b.id)
				T.eq(p.X, MapLayout.nestsFor(b.id)[i].x)
			end
		end
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: GuardianService (경비 추격 판단·잡힘)")

	local function guardWorld()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.Biomes = H.shared("Data/Biomes")
		w.SpeedMath = H.shared("SpeedMath")
		w.Sessions = H.server("Sessions")
		w.SpeedService = H.server("Services/SpeedService")
		w.GuardianService = H.server("Services/GuardianService")
		w.GuardianService.start()
		w.player = H.newPlayer(1001, "Runner")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		H.spawn(w.player, 0, 3, 0)
		return w
	end

	local function guardOf(w, biomeId)
		for _, model in w.H.map.folders.Guardians.children do
			if model:GetAttribute("BiomeId") == biomeId and not model.destroyed then
				return model
			end
		end
		return nil
	end

	local function guardRoot(model)
		return model.PrimaryPart
	end

	local function humanoidOf(model)
		for _, child in model.children do
			if child.ClassName == "Humanoid" then
				return child
			end
		end
		return nil
	end

	-- 숲 알을 든 상태로 만들기: 속도·알 무게를 SpeedService 에 반영
	local function carryForest(w, player, speed, penalty, extra)
		local session = w.Sessions.get(player)
		local data = session.data
		data.speed = speed
		session.carryingUid = "e1"
		session.carryPenalty = penalty
		w.SpeedService.refresh(player)
		local egg = { petId = "sprout_daisy", biomeId = "forest", uid = "e1" }
		for k, v in extra or {} do
			egg[k] = v
		end
		w.H.carry(player, egg)
		return egg
	end

	local function place(w, player, dx, dz, y)
		local cx, cz = w.H.map.zones.forest.centerX, w.H.map.zones.forest.centerZ
		w.H.teleport(player, cx + dx, y or 3, cz + dz)
	end

	T.test(
		"시작하면 15구역에 경비가 1마리씩 자고 있음 (집 = MapLayout.guardHome 구역 가운데, 상태 Sleeping, 대상 없음)",
		function()
			local w = guardWorld()
			local count = 0
			for _, biome in w.Biomes.list do
				local model = guardOf(w, biome.id)
				T.truthy(model, biome.id)
				count += 1
				T.eq(model:GetAttribute("State"), "Sleeping")
				T.eq(model:GetAttribute("TargetUserId"), 0)
				T.eq(
					model:GetAttribute("GuardName"),
					if biome.id == "angels_demons" then "천사 백합" else biome.guardName
				)
				local root = guardRoot(model)
				local home = w.H.MapLayout.guardHome(biome.id)
				T.eq(root.Position.X, home.x)
				T.eq(root.Position.Z, home.z)
				T.eq(w.H.MapLayout.zoneAt(root.Position.Z), biome.id)
			end
			T.eq(count, 15)
			w.H.uninstall()
		end
	)

	T.test(
		"알 든 사람을 쫓음: 상태 Chase, 대상 UserId, 쫓는 속도 = SpeedMath, 목표 = 그 사람 위치",
		function()
			local w = guardWorld()
			carryForest(w, w.player, 900, 0.10)
			place(w, w.player, 30, 0)
			w.H.advance(0.2)
			local model = guardOf(w, "forest")
			T.eq(model:GetAttribute("State"), "Chase")
			T.eq(model:GetAttribute("TargetUserId"), w.player.UserId)
			local humanoid
			for _, child in model.children do
				if child.ClassName == "Humanoid" then
					humanoid = child
				end
			end
			local expected = w.SpeedMath.guardChaseSpeed(10)
			T.near(humanoid.WalkSpeed, expected, 1e-9)
			T.eq(humanoid.moveTarget.X, w.player.Character.root.Position.X)
			T.truthy(humanoid.moves >= 1)
			w.H.uninstall()
		end
	)

	T.test(
		"4판: 경비 추격 속도는 구역 고정 — 빠른 플레이어든 느린 플레이어든 같은 WalkSpeed, 빠른 플레이어보다는 느림",
		function()
			local w = guardWorld()
			carryForest(w, w.player, 100, 0.10) -- 숲 경비 10 보다 훨씬 빠름
			place(w, w.player, 30, 0)
			w.H.advance(0.2)
			local model = guardOf(w, "forest")
			local humanoid
			for _, child in model.children do
				if child.ClassName == "Humanoid" then
					humanoid = child
				end
			end
			local fixed = w.SpeedMath.guardChaseSpeed(10)
			T.near(humanoid.WalkSpeed, fixed, 1e-9)
			T.truthy(humanoid.WalkSpeed < w.session.walkSpeed, "빠른 플레이어보다 느림")
			carryForest(w, w.player, 5, 0.10) -- 느린 플레이어
			w.H.advance(0.2)
			T.near(humanoid.WalkSpeed, fixed, 1e-9, "플레이어가 느려져도 경비 속도는 그대로")
			w.H.uninstall()
		end
	)

	T.test(
		"잡힘 판정: 수평 6 + 경비 키 × 0.25 이내(숲 닭 키 28 → 13) + 높이 10 이내 + 줍고 1.5초 지난 뒤 — 경계 포함, 잡히면 knockOut(guard) + 대상 해제",
		function()
			local w = guardWorld()
			local egg = carryForest(w, w.player, 5, 0.10, { pickedAt = w.H.clock() })
			place(w, w.player, 3, 0)
			w.H.advance(1.4)
			T.eq(#w.H.eggs.knockouts, 0, "줍고 1.4초: 유예 중")
			w.H.advance(0.2)
			T.eq(#w.H.eggs.knockouts, 1, "1.6초: 잡힘")
			local k = w.H.eggs.knockouts[1]
			T.eq(k.player, w.player)
			T.eq(k.cause, "guard")
			T.eq(k.by, "덥석 파리지옥")
			T.eq(guardOf(w, "forest"):GetAttribute("TargetUserId"), 0)
			T.eq(#w.H.sent(w.player, "ChaseEnded"), 1)
			_ = egg
			-- 거리 경계 (겉모습 Height 가 없으면 Visuals.guards.forest.height = 28 → 6 + 7 = 13)
			T.eq(guardOf(w, "forest"):GetAttribute("CatchDistance"), 13)
			for _, case in { { 13.0, 3, true }, { 13.1, 3, false }, { 3, 14.6, true }, { 3, 14.7, false } } do
				table.clear(w.H.eggs.knockouts)
				carryForest(w, w.player, 5, 0.10)
				if case[2] == 3 then
					place(w, w.player, case[1], 0)
				else
					place(w, w.player, case[1], 0, case[2])
				end
				w.H.advance(0.2)
				T.eq(#w.H.eggs.knockouts, if case[3] then 1 else 0, "수평 " .. case[1] .. " 높이 " .. case[2])
				w.H.eggs.carried[w.player] = nil
				w.H.advance(0.3)
			end
			w.H.uninstall()
		end
	)

	T.test(
		"거대 경비 계산(GuardLogic): 잡힘 거리 6 + 키 × 0.25 (최대 16) · 이름표 = 겉모습 꼭대기 + 3",
		function()
			local GuardLogic = Loader.require("ServerScriptService/Server/Logic/GuardLogic")
			local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
			local function reach(h)
				return GuardLogic.catchDistance(
					h,
					Config.GUARD_CATCH_DISTANCE,
					Config.GUARD_CATCH_HEIGHT_FACTOR,
					Config.GUARD_CATCH_DISTANCE_MAX
				)
			end
			T.eq(Config.GUARD_CATCH_DISTANCE, 6)
			T.eq(reach(0), 6)
			T.eq(reach(8), 8, "기본 키 8")
			T.eq(reach(28), 13)
			T.eq(reach(40), 16, "딱 상한")
			T.eq(reach(100), 16, "상한 16")
			T.eq(reach(-5), 6, "음수 키는 0")
			T.eq(reach(0 / 0), 6, "NaN 키는 0")
			T.eq(reach(math.huge), 16)
			-- 이름표: 머리 가운데(바닥 + 8.1) 기준, 꼭대기 + 3
			T.near(GuardLogic.labelOffset(28, 8.1, 3), 22.9, 1e-9)
			T.eq(GuardLogic.labelOffset(8, 8.1, 3), 3, "작은 경비는 머리 위 3")
			T.eq(GuardLogic.labelOffset(0 / 0, 8.1, 3), 3)
			T.eq(GuardLogic.labelOffset(-10, 8.1, 3), 3)
		end
	)

	T.test(
		"경비 키 = 겉모습 모델(선임) Height Attribute → 없으면 Visuals.guards.height → 잡힘 거리(CatchDistance)가 따라 바뀜",
		function()
			local w = guardWorld()
			local model = guardOf(w, "forest")
			w.H.advance(0.2)
			T.eq(model:GetAttribute("CatchDistance"), 13, "Visuals 키 28")
			-- 선임 PetVisualService 처럼 겉모습 모델(이름 = Visuals.guards.forest.model "chicken")에 Height 40
			local height = 40
			local visual = {
				Name = "chicken",
				IsA = function(_, className)
					return className == "Model"
				end,
				GetAttribute = function(_, key)
					return if key == "Height" then height else nil
				end,
			}
			table.insert(model.children, visual)
			w.H.advance(0.2)
			T.eq(model:GetAttribute("CatchDistance"), 16, "키 40 → 6 + 10 = 16")
			-- 15 떨어져도 잡힘 (키 28 이면 13 이라 안 잡힘)
			carryForest(w, w.player, 5, 0.10)
			place(w, w.player, 15, 0)
			w.H.advance(0.2)
			T.eq(#w.H.eggs.knockouts, 1, "거대 경비는 15 에서도 잡음")
			w.H.eggs.carried[w.player] = nil
			w.H.advance(0.3)
			-- 겉모습이 작으면 (키 8) 8 까지만
			height = 8
			w.H.advance(0.2)
			T.eq(model:GetAttribute("CatchDistance"), 8)
			table.clear(w.H.eggs.knockouts)
			carryForest(w, w.player, 5, 0.10)
			place(w, w.player, 9, 0)
			w.H.advance(0.2)
			T.eq(#w.H.eggs.knockouts, 0, "키 8 경비는 9 에서 못 잡음")
			-- 이상한 Height 는 무시 → Visuals 키
			height = 0 / 0
			w.H.advance(0.2)
			T.eq(model:GetAttribute("CatchDistance"), 13)
			w.H.uninstall()
		end
	)

	T.test(
		"2판 추격 포기 없음: 앞 구역을 지나 허브 경계 바로 앞(z = 0.1)까지 계속 쫓고, 허브(z < 0)에 들어가야 포기(reason safe) → 집으로 Return → 도착하면 Sleeping",
		function()
			local w = guardWorld()
			carryForest(w, w.player, 5, 0.10)
			local model = guardOf(w, "lake")
			local home = guardRoot(model).Position
			-- 호수 알을 들고 숲(앞 구역)을 지나 허브 경계까지
			w.H.eggs.carried[w.player].biomeId = "lake"
			for _, z in { 400, 200, 50, 0.1 } do
				w.H.teleport(w.player, 30, 3, z)
				w.H.advance(0.2)
				T.eq(model:GetAttribute("State"), "Chase", "z = " .. z)
				T.eq(model:GetAttribute("TargetUserId"), w.player.UserId)
			end
			T.eq(
				guardOf(w, "forest"):GetAttribute("State"),
				"Sleeping",
				"지나가는 구역(숲) 경비는 안 깨어남"
			)
			-- 경비가 쫓아 나와 있다고 치고 (가짜 Humanoid 는 스스로 걷지 않음)
			guardRoot(model).CFrame = { Position = w.H.vec(home.X + 30, home.Y, home.Z - 100) }
			w.H.teleport(w.player, 30, 3, -0.1)
			w.H.advance(0.2)
			T.eq(model:GetAttribute("State"), "Return")
			T.eq(model:GetAttribute("TargetUserId"), 0)
			local ended = w.H.sent(w.player, "ChaseEnded")
			T.eq(#ended, 1)
			T.eq(ended[1][1].biomeId, "lake")
			T.eq(ended[1][1].reason, "safe")
			local humanoid = humanoidOf(model)
			T.eq(humanoid.moveTarget.X, home.X, "집 쪽으로 걸어감")
			T.eq(humanoid.moveTarget.Z, home.Z)
			T.near(
				humanoid.WalkSpeed,
				w.SpeedMath.guardBaseWalkSpeed(w.SpeedMath.guardSpeedFor(900)),
				1e-9,
				"돌아갈 때는 평소 속도"
			)
			-- 집에 도착하면 다시 잠
			guardRoot(model).CFrame = { Position = home }
			w.H.advance(0.2)
			T.eq(model:GetAttribute("State"), "Sleeping")
			w.H.uninstall()
		end
	)

	T.test("추격 끝 이유(ChaseEnded.reason): 알을 놓음 dropped / 밤 night / 잡음 caught", function()
		local w = guardWorld()
		carryForest(w, w.player, 5, 0.10)
		place(w, w.player, 30, 0)
		w.H.advance(0.2)
		w.H.eggs.carried[w.player] = nil -- DropEgg·배달
		w.H.advance(0.2)
		carryForest(w, w.player, 5, 0.10)
		w.H.advance(0.2)
		w.H.setPhase("Night")
		w.H.advance(0.2)
		local ended = w.H.sent(w.player, "ChaseEnded")
		T.eq(ended[1][1].reason, "dropped")
		T.eq(ended[2][1].reason, "night")
		w.H.setPhase("Day")
		place(w, w.player, 3, 0)
		w.H.advance(0.2)
		ended = w.H.sent(w.player, "ChaseEnded")
		T.eq(ended[#ended][1].reason, "caught")
		w.H.uninstall()
	end)

	T.test(
		"경비끼리 겹치지 않게: 다른 경비가 30 안에 있으면 쫓는 목표를 옆으로 비킴 (CollisionGroup Guardians)",
		function()
			local w = guardWorld()
			carryForest(w, w.player, 5, 0.10)
			place(w, w.player, 40, 0)
			local forest = guardOf(w, "forest")
			local lake = guardOf(w, "lake")
			T.eq(guardRoot(forest).CollisionGroup, w.Config.GUARD_COLLISION_GROUP)
			w.H.advance(0.2)
			local humanoid = humanoidOf(forest)
			local target = w.player.Character.root.Position
			T.eq(humanoid.moveTarget.X, target.X, "주변에 다른 경비가 없으면 그대로")
			-- 호수 경비가 숲 경비 바로 옆(+x 10)에 있다고 치면 → 목표가 -x 쪽으로 20 비킴
			local p = guardRoot(forest).Position
			guardRoot(lake).CFrame = { Position = w.H.vec(p.X + 10, p.Y, p.Z) }
			w.H.advance(2.1) -- MoveTo 다시 부르는 주기
			T.near(humanoid.moveTarget.X, target.X - 20, 1e-9, "옆으로 비킴")
			w.H.uninstall()
		end
	)

	T.test(
		"안 쫓는 경우: 밤·대기 / 허브(안전 구역) / 기절 / 죽음 / 다른 구역 알 / 알 안 든 사람",
		function()
			local w = guardWorld()
			carryForest(w, w.player, 5, 0.10)
			place(w, w.player, 30, 0)
			local model = guardOf(w, "forest")
			w.H.setPhase("Night")
			w.H.advance(0.3)
			T.eq(model:GetAttribute("TargetUserId"), 0, "밤")
			w.H.setPhase("Intermission")
			w.H.advance(0.3)
			T.eq(model:GetAttribute("TargetUserId"), 0, "대기")
			w.H.setPhase("Day")
			w.H.teleport(w.player, 0, 3, -30)
			w.H.advance(0.3)
			T.eq(model:GetAttribute("TargetUserId"), 0, "허브")
			place(w, w.player, 30, 0)
			w.session.stunnedUntil = w.H.clock() + 5
			w.H.advance(0.3)
			T.eq(model:GetAttribute("TargetUserId"), 0, "기절")
			w.session.stunnedUntil = 0
			w.player.Character.humanoid.Health = 0
			w.H.advance(0.3)
			T.eq(model:GetAttribute("TargetUserId"), 0, "죽음")
			w.player.Character.humanoid.Health = 100
			w.H.eggs.carried[w.player].biomeId = "lake" -- 호수 알을 들고 숲에 있음
			w.H.advance(0.3)
			T.eq(model:GetAttribute("TargetUserId"), 0, "다른 구역 알")
			w.H.eggs.carried[w.player].biomeId = "forest"
			w.H.advance(0.3)
			T.eq(model:GetAttribute("TargetUserId"), w.player.UserId, "조건이 맞으면 쫓음")
			w.H.eggs.carried[w.player] = nil
			w.H.advance(0.3)
			T.eq(model:GetAttribute("TargetUserId"), 0, "알을 내려놓음")
			w.H.uninstall()
		end
	)

	T.test("여러 명이 알을 들면 경비에게 제일 가까운 사람을 쫓음", function()
		local w = guardWorld()
		local second = w.H.newPlayer(1002, "Second")
		w.H.login(second)
		w.H.spawn(second, 0, 3, 0)
		carryForest(w, w.player, 5, 0.10)
		carryForest(w, second, 5, 0.10)
		place(w, w.player, 40, 0)
		place(w, second, 20, 0)
		w.H.advance(0.2)
		T.eq(guardOf(w, "forest"):GetAttribute("TargetUserId"), second.UserId)
		place(w, second, 90, 0)
		w.H.advance(0.2)
		T.eq(guardOf(w, "forest"):GetAttribute("TargetUserId"), w.player.UserId, "대상이 바뀜")
		w.H.uninstall()
	end)

	T.test(
		"죽은 경비는 다시 만들어지고, 맵 밖으로 떨어진 경비는 집으로 순간이동",
		function()
			local w = guardWorld()
			local model = guardOf(w, "forest")
			for _, child in model.children do
				if child.ClassName == "Humanoid" then
					child.Health = 0
				end
			end
			w.H.advance(0.2)
			local fresh = guardOf(w, "forest")
			T.truthy(fresh and fresh ~= model, "새 경비")
			T.truthy(model.destroyed, "죽은 경비는 치워짐")
			local count = 0
			for _ in w.H.map.folders.Guardians.children do
				count += 1
			end
			T.eq(count, 15)
			local root = guardRoot(fresh)
			root.CFrame = { Position = w.H.vec(root.Position.X, -50, root.Position.Z) }
			w.H.advance(0.2)
			T.truthy(guardRoot(fresh).Position.Y > 0, "집으로 돌아옴")
			w.H.uninstall()
		end
	)

	T.test("천사&악마 경비 이름은 이번 주기 쪽에 따라 천사/악마로 바뀜", function()
		local w = guardWorld()
		T.eq(guardOf(w, "angels_demons"):GetAttribute("GuardName"), "천사 백합")
		w.H.setPhase("Day", 2)
		T.eq(guardOf(w, "angels_demons"):GetAttribute("GuardName"), "악마 장미")
		w.H.uninstall()
	end)

	ServerHarness.install(Loader, T).uninstall()
end
