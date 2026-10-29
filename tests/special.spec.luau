--!nocheck
-- 구역 특수 요소 (6판): 사쿠라 나무(씨앗 버전), 공지 씨앗, 무기 표. 제단·비밀 통로·퓨전은 사장님 결정으로 없앰

return function(T, Loader)
	local SakuraRules = Loader.require("ReplicatedStorage/Shared/SakuraRules")
	local EggRoll = Loader.require("ReplicatedStorage/Shared/EggRoll")
	local EggSpawn = Loader.require("ReplicatedStorage/Shared/Data/EggSpawn")
	local Progression = Loader.require("ReplicatedStorage/Shared/Progression")
	local Weapons = Loader.require("ReplicatedStorage/Shared/Data/Weapons")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Plants = Loader.require("ReplicatedStorage/Shared/Data/Plants")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Remotes = Loader.require("ReplicatedStorage/Shared/Remotes")
	local Tags = Loader.require("ReplicatedStorage/Shared/Tags")
	local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")

	------------------------------------------------------------------
	T.suite("SakuraRules (6판 씨앗 버전)")

	T.test("바치기: 등급이 높을수록 크리스탈이 많음, 모르는 식물 0", function()
		T.eq(SakuraRules.crystalsFor("sprout_daisy"), Config.SAKURA_OFFER_CRYSTALS.common)
		T.eq(SakuraRules.crystalsFor("rainbow_thunder_tree"), Config.SAKURA_OFFER_CRYSTALS.super, "7판: 슈퍼 100")
		T.eq(SakuraRules.crystalsFor("rainbow_thunder_tree"), 100)
		T.eq(
			SakuraRules.crystalsFor("static_world_tree"),
			Config.SAKURA_OFFER_CRYSTALS.hacker_glitch,
			"해커 글리치 700"
		)
		T.truthy(SakuraRules.crystalsFor("static_world_tree") > SakuraRules.crystalsFor("rainbow_thunder_tree"))
		T.eq(SakuraRules.crystalsFor("없는식물"), 0)
		T.truthy(SakuraRules.crystalsFor("rune_rose") > SakuraRules.crystalsFor("owl_oak"))
	end)

	T.test("뽑기: 벚꽃 씨앗 97.5% / 정령 벚꽃 씨앗 2.5% (20만 회), 크리스탈 10개", function()
		local rand = T.rng(31)
		local spirit = 0
		local n = 200000
		for _ = 1, n do
			if SakuraRules.roll(rand) == "spirit_blossom" then
				spirit += 1
			end
		end
		T.near(spirit / n, 0.025, 0.002)
		T.eq(SakuraRules.roll(T.constant(0)), "blossom_fairy")
		T.eq(SakuraRules.roll(T.constant(0.999)), "spirit_blossom")
		T.eq(Config.SAKURA_DRAW_COST, 10)
		T.truthy(SakuraRules.canAfford(Config.SAKURA_DRAW_COST))
		T.falsy(SakuraRules.canAfford(Config.SAKURA_DRAW_COST - 1))
		T.eq(#SakuraRules.seedIds(), 2)
	end)

	T.test("5판 해금·블룸 규칙과 상수는 없음", function()
		T.eq(SakuraRules.pickOffering, nil)
		T.eq(SakuraRules.hasBloom, nil)
		T.eq(Config.SAKURA_UNLOCK_PET, nil)
		T.eq(Config.SAKURA_APPLY_COST, nil)
		T.eq(Remotes.ToServer.SakuraApply, nil)
		T.eq(Remotes.ToServer.SakuraDraw, "SakuraDraw")
	end)

	------------------------------------------------------------------
	T.suite("6판: 제단·비밀 통로·퓨전 없앰")

	T.test("모듈·Remote·태그·Config·맵 자리가 다 없음", function()
		for _, path in
			{
				"ReplicatedStorage/Shared/AltarRules",
				"ReplicatedStorage/Shared/FusionRules",
				"ServerScriptService/Server/Services/AltarService",
				"ServerScriptService/Server/Services/FusionService",
				"ServerScriptService/Server/Services/IncomeService",
				"ServerScriptService/Server/Services/RewardService",
			}
		do
			T.falsy(pcall(Loader.get, path), path .. " 가 남아 있음")
		end
		for _, name in
			{ "FuseRequest", "AltarOffer", "ShrineFuse", "HatchEgg", "EquipPet", "UnequipPet", "EquipBest", "SellPet" }
		do
			T.eq(Remotes.ToServer[name], nil, name)
		end
		for _, name in
			{ "FusionResult", "AltarUpdate", "ShrineResult", "PetsSold", "HatchResult", "OfflineIncome", "IncomeTick" }
		do
			T.eq(Remotes.ToClient[name], nil, name)
		end
		T.eq(Tags.Altar, nil)
		T.eq(Tags.Shrine, nil)
		T.eq(Tags.FusionMachine, nil)
		T.eq(Config.ALTAR_RADIUS, nil)
		T.eq(Config.FUSION_RADIUS, nil)
		T.eq(MapLayout.specials.altarLight, nil)
		T.eq(MapLayout.specials.shrine, nil)
		T.truthy(MapLayout.specials.sakuraIncubator)
		T.eq(MapLayout.plot(1).fusion, nil)
	end)

	------------------------------------------------------------------
	T.suite("공지 씨앗 (5판 특별 알·제단 펫 자리)")

	T.test("source = special 식물: 둥지 풀에는 없고, 전부 EXTRA_SPECIALS 에 있음", function()
		local chances = {}
		for _, entry in EggSpawn.EXTRA_SPECIALS do
			local plant = Plants.get(entry.petId)
			T.truthy(plant and plant.source == "special", entry.petId)
			T.truthy(entry.chance > 0 and entry.chance < 1, entry.petId)
			chances[entry.petId] = entry.chance
		end
		T.eq(chances.dancing_mushroom, 0.08)
		T.eq(chances.world_tree, 0.01)
		for _, plant in Plants.list do
			if plant.source == "special" then
				T.truthy(chances[plant.id], plant.id .. " 를 얻을 길이 없음")
			end
		end
		for _, biome in Biomes.list do
			for _, side in biome.sides or { false } do
				for _, plant in EggRoll.nestPool(biome.id, side or nil) do
					T.eq(plant.source, "nest", plant.id)
				end
			end
		end
	end)

	T.test("사쿠라 씨앗 2종은 사쿠라 나무 뽑기로만 (둥지·공지 씨앗에 없음)", function()
		for _, id in SakuraRules.seedIds() do
			T.eq(Plants.get(id).source, "sakura", id)
			for _, entry in EggSpawn.EXTRA_SPECIALS do
				T.truthy(entry.petId ~= id, id)
			end
		end
		T.eq(#Progression.weaponRequirement("cherry_blossom"), 8)
		T.eq(#Progression.weaponRequirement("enchanted_forest"), 10)
	end)

	------------------------------------------------------------------
	T.suite("Weapons")

	T.test("구역 무기 7개 = Biomes.weapon, 기본 방망이 = Config", function()
		local count = 0
		for _, biome in Biomes.list do
			local w = biome.weapon
			if w then
				count += 1
				local data = Weapons.get(w.id)
				T.truthy(data, w.id)
				T.eq(data.biome, biome.id, w.id)
				T.eq(Weapons.forBiome(biome.id).id, w.id)
			end
		end
		T.eq(count, 7)
		local bat = Weapons.get(Weapons.DEFAULT)
		T.eq(bat.biome, nil)
		T.eq(bat.range, Config.BAT_RANGE)
		T.eq(bat.cooldown, Config.BAT_COOLDOWN_SECONDS)
		T.eq(bat.toolKind, Remotes.ToolKinds.Bat)
	end)

	T.test("뒤 구역 무기일수록 사거리·넉백은 크고 쿨다운은 짧음 (1.2초 → 0.8초)", function()
		local prev = nil
		for _, w in Weapons.list do
			if prev then
				T.truthy(w.order > prev.order, w.id .. " order")
				T.truthy(w.range > prev.range, w.id .. " range")
				T.truthy(w.knockback > prev.knockback, w.id .. " knockback")
				T.truthy(w.cooldown < prev.cooldown, w.id .. " cooldown")
			end
			prev = w
		end
		T.eq(Weapons.list[1].cooldown, 1.2)
		T.eq(Weapons.list[#Weapons.list].cooldown, 0.8)
	end)

	T.test("모든 무기 Tool 이름이 Remotes.ToolKinds 에 있음 (+ 곰덫)", function()
		local kinds = {}
		for _, kind in Remotes.ToolKinds do
			kinds[kind] = true
		end
		for _, w in Weapons.list do
			T.truthy(kinds[w.toolKind], w.toolKind)
			T.eq(Weapons.byTool(w.toolKind).id, w.id)
		end
		T.truthy(kinds.BearTrap)
		T.eq(Weapons.byTool("BearTrap"), nil)
	end)

	T.test("새 Remote 는 전부 레이트 리밋이 있음, 새 태그 정의", function()
		for _, name in Remotes.ToServer do
			T.truthy(Remotes.RateLimits[name], name)
		end
		T.eq(Remotes.ToServer.PickFruit, "PickFruit")
		T.eq(Remotes.ToClient.QuestUpdate, nil, "5판: 퀘스트 Remote 없앰")
		T.eq(Remotes.ToServer.ClaimFreeReward, nil, "5판: 무료 보상 Remote 없앰")
		T.eq(Tags.GardenPlant, "GardenPlant")
		T.eq(Tags.QuestGate, nil, "5판: 퀘스트 문 태그 없앰")
		T.eq(Tags.SakuraIncubator, "SakuraIncubator")
	end)
end
