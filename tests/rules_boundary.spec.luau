--!nocheck
--[[
	규칙 경계 테스트: "딱 그 값일 때" 어떻게 되는지.
	  - 추천 속도와 정확히 같을 때 경비가 못 잡나, 알 무게(-10~-50%)가 반영되면 얼마부터 안전한가
	  - 알 무게 감소 후 WalkSpeed, 밤 30배, 오프라인 24시간 상한(이상한 값 포함)
	  - 레이트 리밋: 모든 Remote 의 burst / 회복 속도
	  - 퓨전이 거부되는 조건, 선택 확률, 제단·퀘스트·치트 경고의 순수 규칙 경계
	서비스 연결(실제로 돈이 빠지는지 등)은 services_*.spec 에서 따로 봅니다.
]]

return function(T, Loader)
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Remotes = Loader.require("ReplicatedStorage/Shared/Remotes")
	local SpeedMath = Loader.require("ReplicatedStorage/Shared/SpeedMath")
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
	local FusionRules = Loader.require("ReplicatedStorage/Shared/FusionRules")
	local AltarRules = Loader.require("ReplicatedStorage/Shared/AltarRules")
	local QuestRules = Loader.require("ReplicatedStorage/Shared/QuestRules")
	local EggRules = Loader.require("ReplicatedStorage/Shared/EggRules")
	local EggRoll = Loader.require("ReplicatedStorage/Shared/EggRoll")
	local Cycle = Loader.require("ReplicatedStorage/Shared/Cycle")
	local RateLimiter = Loader.require("ServerScriptService/Server/Logic/RateLimiter")
	local MoveCheck = Loader.require("ServerScriptService/Server/Logic/MoveCheck")

	local MARGIN = Config.GUARD_CHASE_MARGIN

	------------------------------------------------------------------
	T.suite("경계: 추천 속도와 경비 (알 무게 포함)")

	T.test("알 없이 속도가 추천 속도와 정확히 같으면 경비가 못 잡음 (모든 구역)", function()
		for _, b in Biomes.list do
			T.truthy(SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(b.recommendedSpeed, 0)), b.id)
			T.truthy(SpeedMath.guardChaseRatio(b.guardSpeed, b.recommendedSpeed) < 1, b.id)
		end
	end)

	T.test(
		"보통 알(-10%)을 들어도 표지판 추천 속도면 안전 (2단계 B4), 1.5% 모자라면 잡힘",
		function()
			local normal = Sizes.get("normal").speedPenalty
			for _, b in Biomes.list do
				local carryNormal = SpeedMath.carrySpeed(b.recommendedSpeed, normal)
				T.truthy(SpeedMath.canEscape(b.guardSpeed, carryNormal), b.id .. " 표지판 속도면 안전")
				local carryShort = SpeedMath.carrySpeed(b.recommendedSpeed * 0.985, normal)
				T.falsy(SpeedMath.canEscape(b.guardSpeed, carryShort), b.id .. " 1.5% 모자라면 잡힘")
			end
		end
	)

	T.test(
		"크기별 안전선: 딱 경계는 안전, 경계보다 0.1% 모자라면 잡힘 (4크기 × 15구역)",
		function()
			for _, b in Biomes.list do
				for _, size in Sizes.list do
					-- 알을 들고 실효 속도 s 일 때 carrySpeed = s × (1 - 감소). 안전 ⇔ carrySpeed > guardSpeed × MARGIN
					local safeBase = b.guardSpeed * MARGIN / (1 - size.speedPenalty)
					T.truthy(
						SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(safeBase * 1.001, size.speedPenalty)),
						b.id .. " " .. size.id .. " 안전"
					)
					T.falsy(
						SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(safeBase * 0.999, size.speedPenalty)),
						b.id .. " " .. size.id .. " 위험"
					)
				end
			end
		end
	)

	T.test(
		"큰 알일수록 필요한 속도가 커짐: 표지판 속도 대비 보통 0.99배, 큼 1.11배, 거대 1.37배, 초거대 1.78배",
		function()
			-- 경비 속도 = 추천 × 0.9 (보통 알 무게 감소 포함), 안전선 = 경비 × MARGIN ÷ (1 - 감소)
			local expected = { normal = 0.99, big = 1.11375, huge = 1.37077, giant = 1.782 }
			for _, size in Sizes.list do
				T.near(SpeedMath.requiredSpeed(1, size.speedPenalty), expected[size.id], 0.001, size.id)
				T.near(0.9 * MARGIN / (1 - size.speedPenalty), expected[size.id], 0.001, size.id .. " (식 그대로)")
			end
			-- 본부장 결정(2단계 B4): 보통 알은 표지판 속도면 안전, 큼 약 +12%, 거대 약 +38%, 초거대 약 +80%
			T.truthy(SpeedMath.requiredSpeed(1, Sizes.get("normal").speedPenalty) < 1)
			T.truthy(SpeedMath.requiredSpeed(1, Sizes.get("big").speedPenalty) > 1.1)
		end
	)

	T.test(
		"경비는 안전한 사람보다 느리고 위험한 사람보다 빠르게 쫓음 (WalkSpeed 기준)",
		function()
			for _, b in Biomes.list do
				local walk = SpeedMath.toWalkSpeed(b.recommendedSpeed * 1.2)
				local safeChase = SpeedMath.guardChaseWalkSpeed(b.guardSpeed, b.recommendedSpeed * 1.2, walk)
				T.truthy(safeChase < walk, b.id .. " 안전한 사람보다 느림")
				local riskyWalk = SpeedMath.toWalkSpeed(b.recommendedSpeed * 0.5)
				local riskyChase = SpeedMath.guardChaseWalkSpeed(b.guardSpeed, b.recommendedSpeed * 0.5, riskyWalk)
				T.truthy(riskyChase > riskyWalk, b.id .. " 위험한 사람보다 빠름")
			end
		end
	)

	T.test("속도가 0·NaN·음수여도 경비 계산이 터지지 않음", function()
		for _, bad in { 0, -5, 0 / 0, 1e-300 } do
			local ratio = SpeedMath.guardChaseRatio(1000, bad)
			T.truthy(
				ratio == ratio and ratio >= Config.GUARD_CHASE_MIN_RATIO and ratio <= Config.GUARD_CHASE_MAX_RATIO
					or ratio ~= ratio,
				"ratio " .. tostring(bad)
			)
			local ws = SpeedMath.guardChaseWalkSpeed(1000, bad, 20)
			T.truthy(ws >= 1 or ws ~= ws)
		end
		T.eq(SpeedMath.guardChaseRatio(1000, 0), Config.GUARD_CHASE_MAX_RATIO)
	end)

	T.test("시작 속도(20)로: 숲은 초거대 알도 안전, 호수(900)는 보통 알도 위험", function()
		local forest, lake = Biomes.get("forest"), Biomes.get("lake")
		T.truthy(
			SpeedMath.canEscape(
				forest.guardSpeed,
				SpeedMath.carrySpeed(Config.STARTING_SPEED, Sizes.get("giant").speedPenalty)
			)
		)
		T.falsy(
			SpeedMath.canEscape(
				lake.guardSpeed,
				SpeedMath.carrySpeed(Config.STARTING_SPEED, Sizes.get("normal").speedPenalty)
			)
		)
	end)

	------------------------------------------------------------------
	T.suite("경계: 알 무게 감소 후 속도")

	T.test("알을 들면 WalkSpeed 가 크기 감소율만큼 줄고 하한 8 밑으로는 안 내려감", function()
		for _, speed in { 0, 20, 900, 1e5, 1e9, 5e11 } do
			local free = SpeedMath.toWalkSpeed(speed)
			for _, size in Sizes.list do
				local carried = SpeedMath.carryWalkSpeed(speed, size.speedPenalty)
				T.near(
					carried,
					math.max(Config.CARRY_WALKSPEED_MIN, free * (1 - size.speedPenalty)),
					1e-9,
					size.id .. " " .. speed
				)
				T.truthy(carried < free or free * (1 - size.speedPenalty) < Config.CARRY_WALKSPEED_MIN)
				T.truthy(carried >= Config.CARRY_WALKSPEED_MIN)
			end
		end
	end)

	T.test(
		"walkSpeedFor: 알 없으면(감소 0) 원래 속도, 감소가 있으면 느려짐, 감소율 1 이상도 터지지 않음",
		function()
			T.eq(SpeedMath.walkSpeedFor(1e4, 0), SpeedMath.toWalkSpeed(1e4))
			T.truthy(SpeedMath.walkSpeedFor(1e4, 0.2) < SpeedMath.toWalkSpeed(1e4))
			T.truthy(SpeedMath.walkSpeedFor(1e4, 5) >= Config.CARRY_WALKSPEED_MIN)
			T.near(SpeedMath.carrySpeed(1000, 5), 1000 * 0.05, 1e-9, "감소율은 95% 까지만")
			T.eq(SpeedMath.carrySpeed(1000, -1), 1000, "음수 감소는 0 취급")
		end
	)

	T.test("트레일 배율은 실효 속도에 곱해지고 1 미만은 1 로", function()
		T.eq(SpeedMath.effectiveSpeed(100, 1.5), 150)
		T.eq(SpeedMath.effectiveSpeed(100, 0.1), 100)
		T.eq(SpeedMath.effectiveSpeed(-100, 2), 0)
	end)

	------------------------------------------------------------------
	T.suite("경계: 밤 30배, 오프라인 24시간")

	T.test("낮 285초 + 밤 10초(×30) + 대기 3초 = 한 바퀴에 알이 자라는 양", function()
		local perCycle = Config.DAY_SECONDS * Economy.growthRate(false, false)
			+ Config.NIGHT_SECONDS * Economy.growthRate(true, false)
			+ Config.INTERMISSION_SECONDS * Economy.growthRate(false, false)
		T.eq(perCycle, 285 + 300 + 3)
		T.eq(Cycle.totalLength(), 298)
		-- 밤에만 자란 알은 한 바퀴 안에서 밤 한 번에 300초만큼
		local p = Economy.advanceIncubation(0, 1e9, Config.NIGHT_SECONDS, 30)
		T.eq(p, 300)
	end)

	T.test(
		"부화 시간이 가장 긴 알(유령 왕 24시간, 2판 수정: ÷3 없음)은 몇 바퀴 만에 부화하나",
		function()
			local required = Economy.hatchSeconds("ghost_king")
			T.eq(required, 24 * 3600)
			-- 한 바퀴(낮 285 + 밤 10 + 대기 3 = 298초)에 자라는 양 = 285 + 10 × 30 + 3 = 588초
			local cycles = required / (285 + 300 + 3)
			T.truthy(cycles > 146 and cycles < 148, "약 147바퀴 = 약 12시간 (실제 " .. cycles .. ")")
		end
	)

	T.test("부화 진행: 시간이 거꾸로(dt<0)여도 줄지 않고, 필요량에서 멈춤", function()
		local p, ready = Economy.advanceIncubation(10, 100, -5, 30)
		T.eq(p, 10)
		T.falsy(ready)
		p, ready = Economy.advanceIncubation(99.9, 100, 1000, 60)
		T.eq(p, 100)
		T.truthy(ready)
		T.eq(Economy.remainingSeconds(0, 100, 0), math.huge, "성장 속도 0 이면 끝없이")
	end)

	T.test(
		"오프라인 수입: 정확히 24시간은 전부, 24시간 1초 초과는 상한, 이상한 시각은 0",
		function()
			local cap = Config.OFFLINE_INCOME_CAP_SECONDS
			T.eq(cap, 86400)
			local amount, seconds = Economy.offlineIncome(10, 1000, 1000 + cap)
			T.eq(seconds, cap)
			T.eq(amount, 10 * cap)
			amount, seconds = Economy.offlineIncome(10, 1000, 1000 + cap + 1)
			T.eq(seconds, cap)
			T.eq(amount, 10 * cap)
			amount = Economy.offlineIncome(10, 1000, 1000)
			T.eq(amount, 0)
			amount = Economy.offlineIncome(0, 1000, 5000)
			T.eq(amount, 0, "수입 0")
			amount = Economy.offlineIncome(-5, 1000, 5000)
			T.eq(amount, 0, "수입이 음수")
			amount = Economy.offlineIncome(10, 5000, 1000)
			T.eq(amount, 0, "시계가 거꾸로")
			amount = Economy.offlineIncome(10, -100, 1000)
			T.eq(amount, 0, "저장 시각이 음수")
		end
	)

	T.test("오프라인 성장: 상한 24시간, 첫 접속(0)은 안 자람", function()
		T.eq(Economy.offlineGrowthSeconds(1000, 1000 + 100), 100)
		T.eq(Economy.offlineGrowthSeconds(1000, 1000 + 10 * 86400), 86400)
		T.eq(Economy.offlineGrowthSeconds(0, 5000), 0)
		T.eq(Economy.offlineGrowthSeconds(5000, 1000), 0)
	end)

	------------------------------------------------------------------
	T.suite("경계: 레이트 리밋 (모든 Remote)")

	T.test(
		"Remote 마다 정확히 burst 번 통과 후 막힘, 다시 1개 회복하는 데 1/초당 회복 초",
		function()
			for name, limit in Remotes.RateLimits do
				local now = 0
				local limiter = RateLimiter.new(function()
					return now
				end)
				for i = 1, limit.burst do
					T.truthy(limiter:allow(1, name, limit.burst, limit.perSecond), name .. " " .. i .. "번째")
				end
				T.falsy(limiter:allow(1, name, limit.burst, limit.perSecond), name .. " burst 다음")
				now += (1 / limit.perSecond) * 0.99
				T.falsy(limiter:allow(1, name, limit.burst, limit.perSecond), name .. " 회복 직전")
				now += (1 / limit.perSecond) * 0.02
				T.truthy(limiter:allow(1, name, limit.burst, limit.perSecond), name .. " 회복 직후")
			end
		end
	)

	T.test(
		"모든 Remote 의 한도가 말이 됨: burst ≥ 1, 초당 회복 > 0, 부화·장착 같은 UI 버튼은 burst ≥ 2",
		function()
			for name, limit in Remotes.RateLimits do
				T.truthy(limit.burst >= 1 and limit.perSecond > 0, name)
				T.truthy(limit.burst <= 20, name .. " burst 가 너무 큼")
			end
			for _, name in { "HatchEgg", "EquipPet", "UnequipPet", "PurchaseUpgrade", "UseTool" } do
				T.truthy(Remotes.RateLimits[name].burst >= 2, name)
			end
		end
	)

	T.test("오래 쉬어도 토큰이 burst 를 넘게 쌓이지 않음, 시간이 거꾸로 가도 안전", function()
		local now = 1000
		local limiter = RateLimiter.new(function()
			return now
		end)
		T.truthy(limiter:allow(1, "X", 2, 1))
		now = 1e9
		T.truthy(limiter:allow(1, "X", 2, 1))
		T.truthy(limiter:allow(1, "X", 2, 1))
		T.falsy(limiter:allow(1, "X", 2, 1))
		now = 5 -- 시계가 뒤로
		T.falsy(limiter:allow(1, "X", 2, 1))
	end)

	------------------------------------------------------------------
	T.suite("경계: 퓨전 거부·선택")

	local function three(petId, size, mutations)
		local list = {}
		for i = 1, 3 do
			list[i] = { uid = "p" .. i, petId = petId, size = size or "normal", mutations = mutations or {} }
		end
		return list
	end

	T.test(
		"초거대 3마리는 더 강해질 수 없는 펫(신성·위가 없는 희귀도)에서 거부, 위가 있으면 허용",
		function()
			local refused, allowed = 0, 0
			for _, pet in Pets.list do
				local result, err = FusionRules.fuse(three(pet.id, "giant"), T.constant(0.5))
				local candidates = FusionRules.candidates(pet.id)
				if result then
					allowed += 1
					T.truthy(result.resultIncome >= result.inputIncome * (1 - 1e-9), pet.id)
				else
					T.eq(err, "weaker", pet.id)
					refused += 1
				end
				if #candidates == 0 then
					T.eq(result, nil, pet.id .. " 위가 없는 초거대는 항상 거부")
				end
			end
			T.truthy(refused > 0 and allowed > 0)
		end
	)

	T.test("정확히 3마리가 아니면 거부 (0, 1, 2, 4마리)", function()
		for n = 0, 4 do
			local list = {}
			for i = 1, n do
				list[i] = { uid = "p" .. i, petId = "chicken", size = "normal", mutations = {} }
			end
			if n ~= 3 then
				local result, err = FusionRules.fuse(list, T.constant(0.5))
				T.eq(result, nil, n .. "마리")
				T.eq(err, "count")
			end
		end
	end)

	T.test(
		"결과 후보가 2개면 약 50:50 으로 고름 (링 가드 3마리 → 영원 둥지 펫 2종)",
		function()
			local counts = {}
			local rand = T.rng(77)
			for _ = 1, 20000 do
				local result = FusionRules.fuse(three("ring_guard"), rand)
				counts[result.petId] = (counts[result.petId] or 0) + 1
			end
			local ids = {}
			for id in counts do
				table.insert(ids, id)
			end
			T.eq(#ids, 2)
			T.near(counts[ids[1]] / 20000, 0.5, 0.02)
		end
	)

	T.test(
		"돌연변이: 셋 다 같을 때만 유지 (순서 달라도), 하나라도 다르면 전부 사라짐",
		function()
			local same = three("chicken", "normal", { "silver" })
			T.eq(FusionRules.commonMutations(same)[1], "silver")
			same[2].mutations = { "golden" }
			T.eq(#FusionRules.commonMutations(same), 0)
			same[2].mutations = { "silver" }
			same[3].mutations = {}
			T.eq(#FusionRules.commonMutations(same), 0)
		end
	)

	------------------------------------------------------------------
	T.suite("경계: 제단·퀘스트·치트 경고 (순수 규칙)")

	T.test(
		"제단: 같은 사람이 두 번 불가 (같은 쪽에도, 반대쪽에도), 다른 사람은 가능",
		function()
			local state = AltarRules.new(1)
			local offer = function(userId, petId, side)
				return { userId = userId, petId = petId, side = side, petUid = "p" .. userId }
			end
			T.truthy(AltarRules.add(state, offer(1, "light_dove", "light"), 1))
			T.falsy(AltarRules.add(state, offer(1, "winged_lamb", "light"), 1))
			T.falsy(AltarRules.add(state, offer(1, "toro", "dark"), 1))
			T.truthy(AltarRules.add(state, offer(2, "winged_lamb", "light"), 1))
			-- 같은 쪽에 두 사람이 줄 서도 짝은 반대쪽이 있어야 맺어짐
			local a, b = AltarRules.tryPair(state, function()
				return true
			end)
			T.eq(a, nil)
			T.eq(b, nil)
			T.eq(AltarRules.pendingCount(state, "light"), 2)
		end
	)

	T.test("제단: 줄 맨 앞 두 사람이 같은 사람이면 짝을 안 맺음", function()
		local state = AltarRules.new(1)
		table.insert(state.queues.light, { userId = 5, petUid = "p1", petId = "light_dove", side = "light" })
		table.insert(state.queues.dark, { userId = 5, petUid = "p2", petId = "imp", side = "dark" })
		local a = AltarRules.tryPair(state, function()
			return true
		end)
		T.eq(a, nil)
	end)

	T.test(
		"퀘스트: 마법의 숲 알 20개 — 정확히 19개/20개 경계, 영원 알은 희귀도만 봄",
		function()
			local progress = {}
			for _ = 1, 19 do
				QuestRules.apply(progress, { kind = "deliver", biome = "enchanted_forest", rarity = "rare" })
			end
			T.eq(progress.deliver_eggs, 19)
			T.falsy(QuestRules.isDone(progress, { id = "deliver_eggs", target = 20 }))
			QuestRules.apply(progress, { kind = "deliver", biome = "enchanted_forest", rarity = "rare" })
			T.eq(progress.deliver_eggs, 20)
			T.eq(progress.deliver_eternal, nil)
			QuestRules.apply(progress, { kind = "deliver", biome = "volcano", rarity = "eternal" })
			T.eq(progress.deliver_eternal, 1)
			T.falsy(QuestRules.allDone(progress), "합성이 남음")
			QuestRules.apply(progress, { kind = "fuse" })
			T.truthy(QuestRules.allDone(progress))
		end
	)

	T.test("퀘스트: 구역/희귀도가 없는 이벤트·모르는 종류는 무시", function()
		local progress = {}
		T.eq(#QuestRules.apply(progress, { kind = "deliver" }), 0)
		T.eq(#QuestRules.apply(progress, { kind = "해킹", biome = "enchanted_forest" }), 0)
		T.eq(next(progress), nil)
	end)

	T.test(
		"치트 경고: 정확히 5번째에 Kick, 120초에 하나씩 줄고 줄어든 뒤에는 처음부터",
		function()
			local w = MoveCheck.newWarnings(0)
			local kicks = {}
			for i = 1, 5 do
				local count, kick = MoveCheck.addWarning(w, i)
				kicks[i] = kick
				T.eq(count, i)
			end
			T.eq(table.concat({ tostring(kicks[1]), tostring(kicks[4]), tostring(kicks[5]) }, ","), "false,false,true")
			-- 119초: 아직 안 줄음, 121초: 1개 줄음
			local d = MoveCheck.newWarnings(0)
			MoveCheck.addWarning(d, 0)
			MoveCheck.addWarning(d, 0)
			MoveCheck.decay(d, 119)
			T.eq(d.count, 2)
			MoveCheck.decay(d, 121)
			T.eq(d.count, 1)
			-- 줄어든 시각 기준으로 다음 120초 (240초 때 0)
			MoveCheck.decay(d, 239)
			T.eq(d.count, 1)
			MoveCheck.decay(d, 241)
			T.eq(d.count, 0)
		end
	)

	T.test("치트 이동 허용 거리: 1초 54(WalkSpeed 16), 최대 150 이면 255 — 경계 포함", function()
		T.falsy(MoveCheck.isViolation(54, 16, 1))
		T.truthy(MoveCheck.isViolation(54.0001, 16, 1))
		T.falsy(MoveCheck.isViolation(255, 150, 1), "2판 수정 최대 걷기 150 → 255")
		T.truthy(MoveCheck.isViolation(255.01, 150, 1))
		T.falsy(MoveCheck.isViolation(0, 0, 0))
	end)

	------------------------------------------------------------------
	T.suite("경계: 구역 판정·낮밤")

	T.test("구역 경계 ±0.001 (2판 z 범위): 앞 구역/뒤 구역, 허브 경계 z = 0, 맵 끝", function()
		local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
		for i, b in Biomes.list do
			local zMin = (i - 1) * MapLayout.BIOME_LENGTH
			T.eq(MapLayout.zoneAt(zMin), b.id, b.id .. " 시작선은 이 구역")
			T.eq(MapLayout.zoneAt(zMin + 0.001), b.id)
			T.eq(MapLayout.zoneAt(zMin - 0.001), if i == 1 then "hub" else Biomes.list[i - 1].id, b.id .. " 바로 앞")
			-- 잡힘 규칙: 경계 바로 앞(앞 구역)에서 잡히면 그 자리, 경계 안이면 둥지로
			T.eq(EggRules.dropOutcome("guard", b.id, MapLayout.zoneAt(zMin)), "ReturnToNest")
			T.eq(EggRules.dropOutcome("guard", b.id, MapLayout.zoneAt(zMin - 0.001)), "DropHere")
		end
		T.truthy(MapLayout.isInHub({ X = 0, Z = -0.001 }))
		T.falsy(MapLayout.isInHub({ X = 0, Z = 0 }))
		T.eq(MapLayout.zoneAt(MapLayout.MAP_END_Z - 0.001), "haunted_castle")
		T.eq(MapLayout.zoneAt(MapLayout.MAP_END_Z), nil)
	end)

	T.test("낮 경계: 285초 딱 되면 밤, 295초 딱 되면 대기, 298초면 다음 낮", function()
		T.eq((Cycle.phaseAt(284.999)), "Day")
		T.eq((Cycle.phaseAt(285)), "Night")
		T.eq((Cycle.phaseAt(294.999)), "Night")
		T.eq((Cycle.phaseAt(295)), "Intermission")
		T.eq((Cycle.phaseAt(297.999)), "Intermission")
		T.eq((Cycle.phaseAt(298)), "Day")
		T.truthy(Cycle.canStealEggs("Day"))
		T.falsy(Cycle.canStealEggs("Night"))
		T.falsy(Cycle.canStealEggs("Intermission"))
	end)

	T.test("둥지 알 추첨: 크기 확률 70/20/8/2 의 누적 경계에서 정확히 바뀜", function()
		T.eq(EggRoll.rollSize(T.constant(0.0)), "normal")
		T.eq(EggRoll.rollSize(T.constant(0.6999)), "normal")
		T.eq(EggRoll.rollSize(T.constant(0.70)), "big")
		T.eq(EggRoll.rollSize(T.constant(0.8999)), "big")
		T.eq(EggRoll.rollSize(T.constant(0.90)), "huge")
		T.eq(EggRoll.rollSize(T.constant(0.9799)), "huge")
		T.eq(EggRoll.rollSize(T.constant(0.98)), "giant")
		T.eq(EggRoll.rollSize(T.constant(0.999999)), "giant")
	end)
end
