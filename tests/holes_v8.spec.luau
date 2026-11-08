--!nocheck
--[[
	8판 (수석 2026-11-08, 사장님 지시 2026-11-08 8가지) — 새 규칙 테스트
	  1 떨어뜨린 씨앗: 그 구역 안 = 그대로 / 밖 = 5초 뒤 둥지로 (EggRules.groundFate, 진짜 EggService)
	  2 튜토리얼 보상 1,000 코인
	  3 러닝머신 가격 전부 ÷ 2 (해금 500)
	  4 러닝머신 터치 신호 (TreadmillTouched · Attr TreadmillTouching, 0레벨도)
	  5 둥지 무리 (구역마다 5개, 끝 오른쪽 귀퉁이, 경비 바로 옆) — 자세한 모양은 maplayout.spec
	  6 구역 21개 (19 로봇 공장 · 20 시간의 탑 · 21 무지개 하늘섬)
	  7 식물 크기 배율 (Config.RARITY_PLANT_SCALE · STAGE_SCALE) · 정원 간격 (EggPlacement, 18칸이 다 들어감)
	  8 경비 잡힘 시간 (SpeedMath.catchSeconds, 진짜 GuardianService + 진짜 EggService)
	설계: docs/SEED_GAME_DESIGN.md 9장 33~44번
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local S = "ReplicatedStorage/Shared/"
	local Config = Loader.require(S .. "Data/Config")
	local Biomes = Loader.require(S .. "Data/Biomes")
	local Plants = Loader.require(S .. "Data/Plants")
	local Rarities = Loader.require(S .. "Data/Rarities")
	local EggSpawn = Loader.require(S .. "Data/EggSpawn")
	local Upgrades = Loader.require(S .. "Data/Upgrades")
	local Tutorial = Loader.require(S .. "Data/Tutorial")
	local MapLayout = Loader.require(S .. "Data/MapLayout")
	local Visuals = Loader.require(S .. "Data/Visuals")
	local Sounds = Loader.require(S .. "Data/Sounds")
	local Mutations = Loader.require(S .. "Data/Mutations")
	local EggRules = Loader.require(S .. "EggRules")
	local SpeedMath = Loader.require(S .. "SpeedMath")
	local GardenRules = Loader.require(S .. "GardenRules")
	local EggPlacement = Loader.require(S .. "EggPlacement")
	local Economy = Loader.require(S .. "Economy")

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

	------------------------------------------------------------------
	T.suite("8판: 1 떨어뜨린 씨앗 · 2 튜토리얼 1,000 · 3 러닝머신 ÷2")

	T.test(
		"groundFate: 그 씨앗 구역 안이면 그대로(Stay), 밖(앞·뒤 구역·허브·맵 밖·모름)이면 둥지로(Return)",
		function()
			T.eq(EggRules.groundFate("lake", "lake"), "Stay")
			T.eq(EggRules.groundFate("lake", MapLayout.zoneAt(240)), "Stay", "구역 시작선")
			T.eq(EggRules.groundFate("lake", MapLayout.zoneAt(479.9)), "Stay", "구역 끝 바로 앞")
			T.eq(EggRules.groundFate("lake", "forest"), "Return", "앞 구역")
			T.eq(EggRules.groundFate("lake", "desert"), "Return", "뒤 구역")
			T.eq(EggRules.groundFate("lake", "hub"), "Return")
			T.eq(EggRules.groundFate("lake", nil), "Return", "맵 밖")
			T.eq(EggRules.groundFate(nil, "lake"), "Return", "구역을 모르는 씨앗")
			T.eq(Config.DROPPED_EGG_RETURN_SECONDS, 5, "사장님: 돌아가는 시간 5초")
			T.eq(Config.DROPPED_EGG_LIFETIME, nil, "7판 60초 사라짐 없앰")
			-- 잡힘 결과(dropOutcome)는 7판 그대로
			T.eq(EggRules.dropOutcome("guard", "lake", "lake"), "ReturnToNest")
			T.eq(EggRules.dropOutcome("drop", "lake", "lake"), "DropHere")
		end
	)

	T.test(
		"진짜 EggService: 방망이(player)·DropEgg 로 구역 안에 떨어진 씨앗은 다음 초기화까지 그대로, 구역 밖 DropEgg 는 5초 카운트다운 뒤 원래 둥지로",
		function()
			inWorld({ realEgg = true }, function(H)
				local EggService = H.server("Services/EggService")
				EggService.start()
				local p = H.newPlayer(8101, "Dropper")
				local session = H.login(p)
				session.plotIndex = 1
				H.spawn(p, 0, 3, 0)
				H.setPhase("Intermission", 1)
				H.setPhase("Day", 1)
				local function nestEgg(biomeId)
					for _, part in H.map.folders.Eggs.children do
						if part:GetAttribute("BiomeId") == biomeId and part:GetAttribute("EggState") == "Nest" then
							return part
						end
					end
					return nil
				end
				local function pick(egg)
					H.teleport(p, egg.Position.X, egg.Position.Y, egg.Position.Z)
					egg:FindFirstChild("StealPrompt").Triggered:Fire(p)
				end
				-- 방망이에 맞아 구역 안에 떨어짐 → 그대로 (5분 가까이)
				local egg = nestEgg("desert")
				pick(egg)
				local x, z = H.zoneSpot("desert")
				H.teleport(p, x, 3, z)
				EggService.knockOut(p, H.vec(x + 3, 3, z), "player", "Bob", 1)
				T.eq(egg:GetAttribute("EggState"), "Dropped")
				T.eq(egg:GetAttribute("ExpiresAt"), nil, "카운트다운 없음")
				H.advance(280)
				T.eq(egg:GetAttribute("EggState"), "Dropped", "280초 뒤에도 그대로")
				T.eq(egg.Position.X, x)
				-- 다음 초기화에 사라지고 둥지는 새 씨앗
				H.setPhase("Intermission", 2)
				T.truthy(egg.destroyed)
				H.setPhase("Day", 2)
				-- 구역 밖(허브 바로 앞 숲)에 내려놓으면 5초 카운트다운 → 원래 둥지
				H.advance(3)
				local egg2 = nestEgg("desert")
				local home = egg2.Position
				pick(egg2)
				session.moveExemptUntil = H.clock() + 5
				H.teleport(p, 10, 3, 100) -- 숲
				H.advance(0.4)
				H.client(p, "DropEgg")
				local now = H.clock()
				T.eq(egg2:GetAttribute("EggState"), "Dropped")
				T.near(egg2:GetAttribute("ExpiresAt") - now, 5, 1e-9, "화면 타이머 = 5초")
				T.eq(egg2:GetAttribute("ReturnsToNest"), true)
				H.advance(4.9)
				T.eq(egg2:GetAttribute("EggState"), "Dropped")
				H.advance(0.3)
				T.eq(egg2:GetAttribute("EggState"), "Nest", "5초 뒤 둥지로")
				T.eq(egg2.Position.X, home.X)
				T.eq(egg2.Position.Z, home.Z)
			end)
		end
	)

	T.test("튜토리얼 끝 보상 1,000 코인 (6·7판 500)", function()
		T.eq(Tutorial.REWARD_MONEY, 1000)
		local TutorialRules = Loader.require(S .. "TutorialRules")
		local view = TutorialRules.view(Tutorial.DONE, Tutorial.REWARD_MONEY)
		T.eq(view.reward, 1000)
		T.truthy(string.find(view.text, "1K 코인", 1, true), view.text)
	end)

	T.test(
		"러닝머신 가격 20레벨 전부 7판의 정확히 절반 (해금 1,000 → 500), 걸음당 속도·1초 1M 은 그대로",
		function()
			local V7 = {
				1e3,
				15e3,
				250e3,
				5e6,
				120e6,
				3e9,
				75e9,
				2e12,
				50e12,
				1e15,
				3e15,
				9e15,
				27e15,
				80e15,
				240e15,
				720e15,
				2.2e18,
				6.5e18,
				20e18,
				60e18,
			}
			T.eq(#Upgrades.Treadmill, #V7)
			for i, cost in V7 do
				T.near(Upgrades.Treadmill[i].cost, cost / 2, cost * 1e-12, i .. "레벨")
			end
			T.eq(Economy.nextTreadmillCost(0), 500, "해금 500")
			T.eq(Economy.treadmillGainPerSecond(20), 1000000)
			T.eq(Upgrades.Treadmill[1].perStep, 2)
		end
	)

	------------------------------------------------------------------
	T.suite("8판: 4 러닝머신 터치 신호 (TreadmillTouched · TreadmillTouching)")

	local function treadWorld(H, level)
		local TreadmillService = H.server("Services/TreadmillService")
		TreadmillService.start()
		local p = H.newPlayer(8201, "Runner")
		local session, data = H.login(p)
		session.plotIndex = 1
		data.treadmillLevel = level
		local plot = MapLayout.plot(1)
		H.spawn(p, plot.spawn.x, 3, plot.spawn.z)
		H.advance(0.4)
		return TreadmillService, p, session, data, plot
	end

	T.test(
		"0레벨: 올라선 순간 TreadmillTouched {level 0, nextCost 500, maxed false} 1번 + Attr true, 안 탐, 안내 글 없음 → 사면 내려오지 않아도 바로 탐",
		function()
			inWorld(nil, function(H)
				local _, p, session, data, plot = treadWorld(H, 0)
				T.eq(p.attrs.TreadmillTouching or false, false, "벨트 밖")
				T.eq(#H.sent(p, "TreadmillTouched"), 0)
				H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z)
				H.advance(2)
				local sent = H.sent(p, "TreadmillTouched")
				T.eq(#sent, 1, "올라선 순간 1번 (2초 서 있어도)")
				local info = sent[1][1]
				T.eq(info.level, 0)
				T.eq(info.nextLevel, 1)
				T.eq(info.nextCost, 500)
				T.eq(info.maxed, false)
				T.eq(info.gainPerSecond, 0)
				T.eq(info.nextGainPerSecond, 8)
				T.eq(p.attrs.TreadmillTouching, true)
				T.falsy(p.attrs.OnTreadmill, "0레벨이라 안 탐")
				for _, n in H.notifications(p) do
					T.falsy(string.find(n.text, "잠겨 있어요", 1, true), "회색 안내 없음: " .. n.text)
				end
				-- 창에서 사기 (PurchaseUpgrade 와 같은 함수)
				data.money = 600
				H.server("Services/UpgradeService").purchase(p, "Treadmill")
				T.eq(data.treadmillLevel, 1)
				T.eq(data.money, 100, "500 코인")
				H.advance(0.4)
				T.eq(p.attrs.OnTreadmill, true, "내려왔다 올라올 필요 없이 바로 탐")
				T.eq(#H.sent(p, "TreadmillTouched"), 1, "서 있는 동안 또 안 보냄")
				-- 내려오면 Attr false, 다시 올라서면 또 1번
				H.client(p, "TreadmillLeave")
				H.advance(0.4)
				T.eq(p.attrs.TreadmillTouching, false, "내려오면 창 닫기")
				H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z)
				H.advance(0.4)
				local again = H.sent(p, "TreadmillTouched")
				T.eq(#again, 2)
				T.eq(again[2][1].level, 1)
				T.eq(again[2][1].nextCost, Upgrades.Treadmill[2].cost)
				T.eq(session.treadmillTouching, true)
			end)
		end
	)

	T.test(
		"벨트 위에서 점프해도(높이 뜸) 창 신호는 그대로 · 20레벨이면 maxed · 남의 러닝머신·씨앗을 들면 신호 없음",
		function()
			inWorld(nil, function(H)
				local TreadmillService, p, session, data, plot = treadWorld(H, 20)
				H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z)
				H.advance(0.4)
				local sent = H.sent(p, "TreadmillTouched")
				T.eq(#sent, 1)
				T.eq(sent[1][1].maxed, true)
				T.eq(sent[1][1].nextCost, nil)
				T.eq(sent[1][1].gainPerSecond, 1000000)
				H.teleport(p, plot.treadmill.x, 20, plot.treadmill.z) -- 점프
				H.advance(0.4)
				H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z) -- 착지
				H.advance(0.4)
				T.eq(#H.sent(p, "TreadmillTouched"), 1, "점프로 깜빡이지 않음")
				T.eq(p.attrs.TreadmillTouching, true)
				-- 남의 베이스(2번) 러닝머신
				local other = MapLayout.plot(2).treadmill
				H.teleport(p, other.x, 3, other.z)
				H.advance(0.4)
				T.eq(p.attrs.TreadmillTouching, false)
				T.eq(#H.sent(p, "TreadmillTouched"), 1)
				-- 씨앗을 든 채면 신호 없음
				session.carryingUid = "e1"
				H.teleport(p, plot.treadmill.x, 3, plot.treadmill.z)
				H.advance(0.4)
				T.eq(#H.sent(p, "TreadmillTouched"), 1)
				session.carryingUid = nil
				local info = TreadmillService.touchInfo(3)
				T.eq(info.nextLevel, 4)
				T.eq(info.nextCost, Upgrades.Treadmill[4].cost)
				_ = data
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("8판: 5 둥지 무리 · 6 구역 21개")

	T.test(
		"맵 둥지 21 × 5 = 105, 경비 집이 둥지 무리 옆, 경비 집·둥지·표지판이 다 그 구역 안",
		function()
			local total = 0
			for _, b in MapLayout.biomes do
				local cluster = MapLayout.nestCluster(b.id)
				total += #cluster.nests
				for _, spot in { cluster.guard, cluster.sign, cluster.center, cluster.decor[1], cluster.decor[2] } do
					T.eq(MapLayout.zoneAt(spot.z), b.id, b.id)
					T.truthy(math.abs(spot.x) <= MapLayout.HALF_WIDTH - 6, b.id .. " 복도 안")
				end
			end
			T.eq(total, 105)
			T.eq(Config.NESTS_PER_BIOME, 5)
		end
	)

	local NEW = {
		{
			"robot_factory",
			19,
			"로봇 공장",
			"Robot Factory",
			1.22e12,
			"톱니 해바라기 로봇",
			"Bgm_robot_factory",
		},
		{ "clock_tower", 20, "시간의 탑", "Clock Tower", 1.24e12, "태엽 장미 기사", "Bgm_clock_tower" },
		{
			"rainbow_sky",
			21,
			"무지개 하늘섬",
			"Rainbow Sky Islands",
			1.26e12,
			"무지개 용 덩굴",
			"Bgm_rainbow_sky",
		},
	}

	T.test(
		"새 구역 3개: 순서·이름·추천 속도·경비, 경비 추격 WalkSpeed 는 계속 오르되 230 안, 맵 끝 5040, 도감 무기 없음, Visuals·Sounds 자리",
		function()
			T.eq(#Biomes.list, 21)
			T.eq(MapLayout.MAP_END_Z, 5040)
			local prevChase = SpeedMath.guardChaseSpeed(Biomes.get("bug_dimension").guardSpeed)
			for _, row in NEW do
				local b = Biomes.get(row[1])
				T.truthy(b, row[1])
				T.eq(b.order, row[2])
				T.eq(b.name, row[3])
				T.eq(b.nameEn, row[4])
				T.near(b.recommendedSpeed, row[5], row[5] * 1e-12)
				T.eq(b.guardName, row[6])
				T.eq(b.weapon, nil, row[1] .. " 도감 무기 없음")
				T.eq(b.nests, 5)
				local chase = SpeedMath.guardChaseSpeed(b.guardSpeed)
				T.truthy(chase > prevChase, row[1] .. " 추격 속도가 앞 구역보다 빠름 " .. chase)
				T.truthy(chase < Config.SPEED_WALK_MAX, row[1] .. " 추격 속도 230 안: " .. chase)
				prevChase = chase
				-- 추천 속도면 보통 씨앗으로 도망, 조금이라도 모자라면 잡힘
				T.truthy(SpeedMath.canEscape(b.guardSpeed, b.recommendedSpeed * 0.9))
				T.falsy(SpeedMath.canEscape(b.guardSpeed, b.recommendedSpeed * 0.88))
				T.truthy(Visuals.guards[row[1]] ~= nil, row[1] .. " 경비 모양 자리")
				T.truthy(Visuals.biomes[row[1]] ~= nil, row[1] .. " 구역 테마 자리")
				T.truthy(Visuals.plantThemes[row[1]] ~= nil, row[1] .. " 식물 색 자리")
				T.eq(Visuals.biomes[row[1]].music, row[7])
				T.truthy(Sounds[row[7]] ~= nil, row[7])
				T.truthy(b.recommendedSpeed > Biomes.list[row[2] - 1].recommendedSpeed, "앞 구역보다 어려움")
			end
			T.truthy(
				SpeedMath.toWalkSpeed(1.267e12 * 0.891) >= 230 - 0.01,
				"1.267T 를 넘으면 230 에 붙음 (상한 메모)"
			)
		end
	)

	T.test(
		"새 구역 식물 8종씩: 맨 위 등급 쪽(개발자·울트라디바인·해커 글리치)만, 등급이 안 내려감, 숫자는 7판 등급 범위 안, 가중치 합 100 · 풀에 그 등급 식물이 있음",
		function()
			local RANGE = {
				developer = { 6, 7, 18e12, 27e12 },
				ultradivine = { 5, 6, 220e12, 330e12 },
				hacker_glitch = { 4, 5, 2.7e15, 3.3e15 },
			}
			local EggRoll = Loader.require(S .. "EggRoll")
			for _, row in NEW do
				local list = Plants.inBiome(row[1])
				T.eq(#list, 8, row[1])
				local prev = 0
				for _, p in list do
					local r = RANGE[p.rarity]
					T.truthy(r ~= nil, p.id .. " 등급 " .. p.rarity)
					T.eq(p.source, "nest")
					T.truthy(Rarities.order(p.rarity) >= prev, p.id .. " 등급 순서")
					prev = Rarities.order(p.rarity)
					T.truthy(
						p.fruitIntervalSeconds >= r[1] and p.fruitIntervalSeconds <= r[2],
						p.id .. " 열매 간격"
					)
					T.truthy(p.fruitValue >= r[3] and p.fruitValue <= r[4], p.id .. " 열매 값")
					local ratio = p.growSeconds / Rarities.get(p.rarity).baseGrowSeconds
					T.truthy(ratio >= 0.75 and ratio <= 1.25, p.id .. " 성장 시간 비율 " .. ratio)
				end
				local weights = EggSpawn.BIOME_RARITY_WEIGHTS[row[1]]
				local sum = 0
				for id, wgt in weights do
					sum += wgt
					T.truthy(EggRoll.rarityWeight(row[1], id) > 0)
				end
				T.eq(sum, 100, row[1])
				T.truthy((weights.hacker_glitch or 0) > 0, row[1] .. " 해커 글리치가 나옴")
			end
			T.eq(Plants.count, 182)
			-- 먹이기 ×3 구역에 하나씩
			local found = {}
			for _, m in Mutations.list do
				for _, id in m.feedBiomes or {} do
					found[id] = m.id
				end
			end
			T.eq(found.robot_factory, "shocked")
			T.eq(found.clock_tower, "golden")
			T.eq(found.rainbow_sky, "rainbow")
		end
	)

	------------------------------------------------------------------
	T.suite("8판: 7 식물 크기 · 정원 간격")

	T.test(
		"RARITY_PLANT_SCALE 16칸: 일반 1 → 해커 글리치 4~5, 등급마다 커짐 · STAGE_SCALE 0.3 / 0.55 / 0.8 / 1",
		function()
			local prev = 0
			local count = 0
			for _, r in Rarities.list do
				local s = Config.RARITY_PLANT_SCALE[r.id]
				T.truthy(s ~= nil, r.id)
				T.truthy(s > prev, r.id .. " 등급이 높을수록 큼")
				prev = s
				count += 1
			end
			T.eq(count, 16)
			T.eq(Config.RARITY_PLANT_SCALE.common, 1)
			T.truthy(Config.RARITY_PLANT_SCALE.hacker_glitch >= 4 and Config.RARITY_PLANT_SCALE.hacker_glitch <= 5)
			T.eq(Config.STAGE_SCALE.sprout, 0.3)
			T.eq(Config.STAGE_SCALE.stem, 0.55)
			T.eq(Config.STAGE_SCALE.bud, 0.8)
			T.eq(Config.STAGE_SCALE.adult, 1)
			for _, def in Config.GROWTH_STAGES do
				T.truthy(Config.STAGE_SCALE[def.id] ~= nil, def.id .. " 단계 배율")
			end
			T.eq(GardenRules.rarityScale("nope"), 1)
			T.eq(GardenRules.sizeScale("giant"), 1.5)
			T.eq(GardenRules.sizeScale(nil), 1)
		end
	)

	T.test(
		"growthScale: 자라면서 점점 커짐 (단계 시작점은 STAGE_SCALE 그대로, 사이는 이어짐, 줄어들지 않음, 이상한 값 안전)",
		function()
			T.near(GardenRules.growthScale(0, 100), 0.3, 1e-9)
			T.near(GardenRules.growthScale(25, 100), 0.55, 1e-9)
			T.near(GardenRules.growthScale(60, 100), 0.8, 1e-9)
			T.near(GardenRules.growthScale(100, 100), 1, 1e-9)
			T.near(GardenRules.growthScale(80, 100), 0.9, 1e-9, "봉오리 ~ 성체 가운데")
			local prev = 0
			for i = 0, 1000 do
				local s = GardenRules.growthScale(i, 1000)
				T.truthy(s >= prev - 1e-12, "줄어들지 않음 " .. i)
				T.truthy(math.abs(s - prev) < 0.01 or i == 0, "뚝 끊기지 않음 " .. i)
				prev = s
			end
			T.near(GardenRules.growthScale(500, 100), 1, 1e-9, "다 자란 뒤")
			T.near(GardenRules.growthScale(0 / 0, 100), 0.3, 1e-9)
			T.near(GardenRules.growthScale(5, 0), 1, 1e-9, "required 0 = 다 자람")
			-- plantScale = 등급 × 크기 × 자람
			T.near(GardenRules.plantScale("static_world_tree", "giant"), 4.5 * 1.5, 1e-9)
			T.near(GardenRules.plantScale("sprout_daisy", "normal", 0, 10), 0.3, 1e-9)
			T.near(GardenRules.plantScale("final_boss_bloom", "big", 60, 100), 4.5 * 1.15 * 0.8, 1e-9)
			T.eq(GardenRules.plantScale("nope", nil), 1)
		end
	)

	T.test(
		"정원 간격 = 다 자란 폭 평균 (일반끼리 7판 그대로 4, 큰 등급은 더 넓게, 상한 14)",
		function()
			T.eq(EggPlacement.gap("normal", "normal"), 4, "petId 없으면 7판과 같음")
			T.eq(EggPlacement.gap("normal", "normal", "sprout_daisy", "sprout_daisy"), 4)
			T.near(EggPlacement.footprint("static_world_tree", "normal"), 2.6 * 4.5, 1e-9)
			T.near(EggPlacement.gap("normal", "normal", "static_world_tree", "static_world_tree"), 11.7, 1e-9)
			T.near(
				EggPlacement.gap("normal", "normal", "static_world_tree", "sprout_daisy"),
				(11.7 + 2.6) / 2,
				1e-9,
				"큰 것과 작은 것은 평균"
			)
			T.eq(EggPlacement.gap("giant", "giant", "static_world_tree", "static_world_tree"), Config.PLANT_GAP_MAX)
			T.eq(Config.PLANT_GAP_MAX, 14)
			local spots = { { x = 0, z = 0, size = "normal", petId = "static_world_tree" } }
			T.falsy(EggPlacement.check(0, 11.6, "normal", spots, nil, "static_world_tree"), "11.6 은 겹침")
			T.truthy(EggPlacement.check(0, 11.71, "normal", spots, nil, "static_world_tree"))
			T.truthy(
				EggPlacement.check(
					0,
					4,
					"normal",
					{ { x = 0, z = 0, size = "normal", petId = "sprout_daisy" } },
					nil,
					"puppy_grass"
				)
			)
			-- pets 목록도 같은 간격
			T.falsy(EggPlacement.check(0, 8, "normal", {}, spots, "static_world_tree"))
		end
	)

	T.test(
		"정원 칸 최대 18 이 맨 위 등급(보통·초거대)으로도 다 들어감 · 섞어 심어도 18칸",
		function()
			local cases = {
				{ "static_world_tree", "normal" },
				{ "static_world_tree", "giant" },
				{ "final_boss_bloom", "huge" },
			}
			for _, case in cases do
				local placed = {}
				for i = 1, Upgrades.Pen[#Upgrades.Pen].slots do
					local spot = EggPlacement.firstFreeGrid(case[2], placed, case[1])
					T.truthy(spot ~= nil, case[1] .. " " .. case[2] .. " " .. i .. "번째 자리")
					if not spot then
						break
					end
					T.truthy(EggPlacement.check(spot.x, spot.z, case[2], placed, nil, case[1]))
					table.insert(placed, { x = spot.x, z = spot.z, size = case[2], petId = case[1] })
				end
				T.eq(#placed, 18, case[1] .. " " .. case[2])
			end
			-- 섞기: 등급 순서대로 큰 것부터 한 그루씩
			local placed = {}
			local ids = {
				"static_world_tree",
				"error_rose",
				"studio_tree",
				"mainframe_tree",
				"pixel_rose",
				"sky_pillar_flower",
			}
			for i = 1, 18 do
				local id = ids[(i - 1) % #ids + 1]
				local spot = EggPlacement.firstFreeGrid("big", placed, id)
				T.truthy(spot ~= nil, "섞어 심기 " .. i)
				table.insert(placed, { x = spot.x, z = spot.z, size = "big", petId = id })
			end
		end
	)

	T.test(
		"서버 PlaceEgg 도 큰 식물 간격 (해커 글리치끼리 6 은 거부, 11.7 은 됨) · 저장된 옛 정원(7판 간격)은 불러와도 식물이 안 팔림",
		function()
			inWorld(nil, function(H)
				local BaseService = H.server("Services/BaseService")
				BaseService.start()
				local p = H.newPlayer(8301, "Gardener")
				local session, data = H.login(p)
				session.plotIndex = 1
				local plot = MapLayout.plot(1)
				H.spawn(p, plot.spawn.x, 3, plot.spawn.z)
				data.penLevel = 11
				local function try(lx, lz)
					BaseService.grantEgg(p, "static_world_tree", "normal", {}, "dev")
					local egg = data.eggs[#data.eggs]
					local w = MapLayout.toWorld(1, lx, lz)
					return BaseService.placeEgg(p, egg.uid, w.x, w.z)
				end
				T.truthy(try(-20, -20))
				T.falsy(try(-20, -14), "6 은 거부")
				T.truthy(H.hasNotify(p, "error", "너무 가까워요"))
				T.truthy(try(-20, -8.2), "11.8 은 됨 (간격 11.7)")
				-- 저장된 옛 자리 (7판에 4 간격으로 심어 둔 해커 글리치 3그루) → 그대로, 안 팔림
				local DataSchema = H.server("Logic/DataSchema")
				local raw = DataSchema.default(0)
				raw.penLevel = 11
				raw.pets = {}
				for i = 1, 3 do
					table.insert(raw.pets, {
						uid = "p" .. i,
						petId = "static_world_tree",
						size = "normal",
						mutations = {},
						x = -20,
						z = -20 + (i - 1) * 4,
						fruits = 1,
						fruitProgress = 0,
					})
				end
				local fixed = DataSchema.reconcile(raw, 0)
				T.eq(#fixed.pets, 3, "옛 정원 식물 3그루 그대로")
				for i, r in fixed.pets do
					T.eq(r.x, -20)
					T.eq(r.z, -20 + (i - 1) * 4, "자리 그대로")
				end
				T.eq(fixed.money, raw.money, "팔려서 코인으로 바뀌지 않음")
			end)
		end
	)

	------------------------------------------------------------------
	T.suite("8판: 8 경비 잡힘 시간")

	T.test(
		"catchSeconds: 도망칠 수 있으면 nil, 추격 기준의 70% 이상이면 2.5초, 그보다 느리면 1초 (경계 포함)",
		function()
			local guard = Biomes.get("lake").guardSpeed -- 810
			local threshold = guard * Config.GUARD_CHASE_MARGIN
			T.eq(SpeedMath.catchSeconds(guard, threshold * 1.0001), nil, "기준보다 빠름 = 자유")
			T.eq(SpeedMath.catchSeconds(guard, threshold), 2.5, "딱 기준 = 못 도망 (canEscape 는 > )")
			T.eq(SpeedMath.catchSeconds(guard, threshold * 0.7), 2.5, "딱 70%")
			T.eq(SpeedMath.catchSeconds(guard, threshold * 0.6999), 1, "70% 밑")
			T.eq(SpeedMath.catchSeconds(guard, 0), 1)
			T.eq(SpeedMath.catchSeconds(guard, 0 / 0), 1, "NaN 속도는 못 도망")
			T.eq(SpeedMath.catchSeconds(0, 0), 2.5, "경비 속도 0 = 기준 0 → 0 은 못 넘음, 비율 무한")
			T.near(SpeedMath.escapeRatio(guard, threshold * 0.5), 0.5, 1e-9)
			T.eq(SpeedMath.escapeRatio(guard, 0 / 0), 0)
			-- 추격 WalkSpeed 공식은 그대로
			T.near(SpeedMath.guardChaseSpeed(guard), SpeedMath.toWalkSpeed(threshold), 1e-9)
		end
	)

	T.test(
		"진짜 GuardianService + 진짜 EggService: 느린 사람(1초)은 둥지에서 주운 뒤 약 1초에 잡혀 씨앗이 둥지로 · 다음 구역 경계를 넘으면 즉시 둥지로 · 추천 속도면 계속 자유",
		function()
			inWorld({ realEgg = true }, function(H)
				local EggService = H.server("Services/EggService")
				EggService.start()
				H.server("Services/GuardianService").start()
				local p = H.newPlayer(8401, "Slow")
				local session, data = H.login(p)
				session.plotIndex = 1
				H.spawn(p, 0, 3, 0)
				H.setPhase("Intermission", 1)
				H.setPhase("Day", 1)
				local function nestEgg(biomeId)
					for _, part in H.map.folders.Eggs.children do
						if part:GetAttribute("BiomeId") == biomeId and part:GetAttribute("EggState") == "Nest" then
							return part
						end
					end
					return nil
				end
				local function pick(egg)
					H.teleport(p, egg.Position.X, egg.Position.Y, egg.Position.Z)
					egg:FindFirstChild("StealPrompt").Triggered:Fire(p)
				end
				-- 호수(추천 900)를 속도 20 으로 → 많이 모자람 → 1초
				data.speed = 20
				local egg = nestEgg("lake")
				local home = egg.Position
				pick(egg)
				T.eq(egg:GetAttribute("EggState"), "Carried")
				H.advance(0.8)
				T.eq(egg:GetAttribute("EggState"), "Carried", "0.8초: 아직")
				H.advance(0.5)
				T.eq(egg:GetAttribute("EggState"), "Nest", "약 1초: 잡혀서 둥지로 (구역 안)")
				T.eq(egg.Position.X, home.X)
				local caught = H.sent(p, "Caught")
				T.eq(caught[#caught][1].cause, "guard")
				T.eq(caught[#caught][1].eggOutcome, "ReturnToNest")
				-- 기절이 풀린 뒤, 다음 구역(사막) 경계를 넘으면 즉시
				H.advance(Config.RAGDOLL_SECONDS + 0.5)
				local lake = MapLayout.biome("lake")
				local egg2 = nestEgg("lake")
				pick(egg2)
				session.moveExemptUntil = H.clock() + 5
				H.teleport(p, -60, 3, lake.zMax + 1)
				H.advance(0.15)
				T.eq(egg2:GetAttribute("EggState"), "Nest", "경계를 넘자마자 씨앗은 둥지로")
				caught = H.sent(p, "Caught")
				T.eq(caught[#caught][1].eggOutcome, "ReturnToNest")
				-- 추천 속도면 다음 구역까지 가도 안 잡힘
				H.advance(Config.RAGDOLL_SECONDS + 0.5)
				data.speed = 1000
				local before = #H.sent(p, "Caught")
				local egg3 = nestEgg("lake")
				pick(egg3)
				H.advance(3)
				session.moveExemptUntil = H.clock() + 5
				H.teleport(p, -60, 3, lake.zMax + 30)
				H.advance(3)
				T.eq(#H.sent(p, "Caught"), before, "도망칠 수 있으면 자유")
				T.eq(egg3:GetAttribute("EggState"), "Carried")
			end)
		end
	)
end
