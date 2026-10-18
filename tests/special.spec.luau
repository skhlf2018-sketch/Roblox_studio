--!nocheck
-- 구역 특수 요소: 사쿠라 인큐베이터, 천사&악마 제단·비밀 통로, 마법의 숲 퀘스트, 무기 표

return function(T, Loader)
	local SakuraRules = Loader.require("ReplicatedStorage/Shared/SakuraRules")
	local AltarRules = Loader.require("ReplicatedStorage/Shared/AltarRules")
	local QuestRules = Loader.require("ReplicatedStorage/Shared/QuestRules")
	local Quests = Loader.require("ReplicatedStorage/Shared/Data/Quests")
	local Weapons = Loader.require("ReplicatedStorage/Shared/Data/Weapons")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Remotes = Loader.require("ReplicatedStorage/Shared/Remotes")
	local Tags = Loader.require("ReplicatedStorage/Shared/Tags")

	------------------------------------------------------------------
	T.suite("SakuraRules")

	T.test("블룸끼리는 불가, 자연 돌연변이 위에는 가능", function()
		T.truthy(SakuraRules.canApply({}))
		T.truthy(SakuraRules.canApply({ "golden" }))
		local ok, reason = SakuraRules.canApply({ "silver", "bloom" })
		T.falsy(ok)
		T.truthy(#reason > 0)
		T.falsy(SakuraRules.canApply({ "spirit_bloom" }))
		local after = SakuraRules.apply({ "rainbow" }, "spirit_bloom")
		T.eq(#after, 2)
		T.eq(after[2], "spirit_bloom")
		T.eq(#SakuraRules.apply({ "bloom" }, "spirit_bloom"), 1, "이미 블룸이면 그대로")
	end)

	T.test("블룸 97.5% / 스피릿 블룸 2.5% (20만 회)", function()
		local rand = T.rng(31)
		local spirit = 0
		local n = 200000
		for _ = 1, n do
			if SakuraRules.roll(rand) == "spirit_bloom" then
				spirit += 1
			end
		end
		T.near(spirit / n, 0.025, 0.002)
		T.eq(SakuraRules.roll(T.constant(0)), "bloom")
		T.eq(SakuraRules.roll(T.constant(0.999)), "spirit_bloom")
	end)

	T.test("해금 제물: uid 없으면 수입이 가장 낮은 학, 학이 없으면 nil", function()
		local pets = {
			{ uid = "p1", petId = "crane", size = "giant", mutations = {} },
			{ uid = "p2", petId = "chicken", size = "normal", mutations = {} },
			{ uid = "p3", petId = "crane", size = "normal", mutations = {} },
		}
		local incomes = { 100, 1, 10 }
		local function incomeOf(i)
			return incomes[i]
		end
		T.eq(SakuraRules.pickOffering(pets, incomeOf, nil), 3)
		T.eq(SakuraRules.pickOffering(pets, incomeOf, "p1"), 1)
		T.eq(SakuraRules.pickOffering(pets, incomeOf, "p2"), nil, "학이 아닌 펫은 못 바침")
		T.eq(SakuraRules.pickOffering({ pets[2] }, incomeOf, nil), nil)
		T.truthy(SakuraRules.canAfford(Config.SAKURA_APPLY_COST))
		T.falsy(SakuraRules.canAfford(Config.SAKURA_APPLY_COST - 1))
	end)

	------------------------------------------------------------------
	T.suite("AltarRules")

	local function offer(userId, petId, side, uid)
		return { userId = userId, petId = petId, side = side, petUid = uid or ("p" .. userId) }
	end
	local function always()
		return true
	end

	T.test("제물 쪽: 천국/지옥 둥지 펫만", function()
		T.eq(AltarRules.sideOfPet("pegasus"), "light")
		T.eq(AltarRules.sideOfPet("toro"), "dark")
		T.eq(AltarRules.sideOfPet("chicken"), nil)
		T.eq(AltarRules.sideOfPet("ring_guard"), nil)
		T.eq(AltarRules.sideOfPet("equinox"), nil)
	end)

	T.test("같은 주기, 서로 다른 두 사람이 양쪽에 바치면 짝", function()
		local state = AltarRules.new(5)
		T.falsy(AltarRules.add(state, offer(1, "toro", "light"), 5), "쪽이 다른 펫")
		T.truthy(AltarRules.add(state, offer(1, "light_dove", "light"), 5))
		local ok, reason = AltarRules.add(state, offer(1, "toro", "dark"), 5)
		T.falsy(ok, "혼자 양쪽 불가")
		T.eq(reason, "already")
		local a, b = AltarRules.tryPair(state, always)
		T.eq(a, nil, "아직 지옥 쪽 없음")
		T.truthy(AltarRules.add(state, offer(2, "toro", "dark"), 5))
		a, b = AltarRules.tryPair(state, always)
		T.eq(a.userId, 1)
		T.eq(b.userId, 2)
		T.eq(AltarRules.pendingCount(state, "light"), 0)
		T.eq(AltarRules.pendingCount(state, "dark"), 0)
	end)

	T.test("주기가 바뀌면 기다리던 제물 취소, 유효하지 않은 제물은 건너뜀", function()
		local state = AltarRules.new(1)
		AltarRules.add(state, offer(1, "light_dove", "light"), 1)
		local expired = AltarRules.rollover(state, 2)
		T.eq(#expired, 1)
		T.eq(AltarRules.pendingCount(state, "light"), 0)
		AltarRules.add(state, offer(3, "light_dove", "light"), 2)
		AltarRules.add(state, offer(4, "winged_lamb", "light"), 2)
		AltarRules.add(state, offer(5, "imp", "dark"), 2)
		local a, b = AltarRules.tryPair(state, function(o)
			return o.userId ~= 3 -- 3번은 나감
		end)
		T.eq(a.userId, 4)
		T.eq(b.userId, 5)
		T.truthy(AltarRules.add(state, offer(6, "imp", "dark"), 2))
		T.truthy(AltarRules.cancel(state, 6))
		T.falsy(AltarRules.cancel(state, 6))
		T.eq(#AltarRules.rollover(state, 2), 0, "같은 주기면 그대로")
	end)

	T.test("링 가드 80% / 링로드 20%", function()
		local rand = T.rng(8)
		local lord = 0
		local n = 100000
		for _ = 1, n do
			if AltarRules.rollRingEgg(rand) == "ringlord" then
				lord += 1
			end
		end
		T.near(lord / n, 0.2, 0.005)
		T.truthy(Pets.get(AltarRules.RING_GUARD) and Pets.get(AltarRules.RINGLORD))
	end)

	T.test("비밀 통로 레시피 (순서 무관), 크기는 작은 쪽", function()
		T.eq(AltarRules.recipeFor("pegasus", "skeleton_horse").result, "equinox")
		T.eq(AltarRules.recipeFor("skeleton_horse", "pegasus").result, "equinox")
		T.eq(AltarRules.recipeFor("world_burner", "archangel").result, "aetheron")
		T.eq(AltarRules.recipeFor("pegasus", "archangel"), nil)
		T.eq(AltarRules.recipeFor("pegasus", "pegasus"), nil)
		T.eq(AltarRules.shrineSize("giant", "big"), "big")
		T.eq(AltarRules.shrineSize("normal", "huge"), "normal")
		for _, recipe in AltarRules.RECIPES do
			T.eq(Pets.get(recipe.result).source, "fusion", recipe.result)
		end
	end)

	------------------------------------------------------------------
	T.suite("QuestRules")

	T.test("퀘스트 3개, 목표·보상 알이 데이터와 맞음", function()
		T.eq(#Quests.list, 3)
		T.eq(Quests.get("deliver_eggs").target, 20)
		T.eq(Pets.get(Quests.REWARD_EGG).source, "quest")
		T.eq(Pets.get(Quests.SECRET_EGG).source, "quest")
	end)

	T.test("마법의 숲 알만 20개, 영원 알은 아무 구역, 합성 1회", function()
		local progress = {}
		T.eq(#QuestRules.apply(progress, { kind = "deliver", biome = "forest", rarity = "common" }), 0)
		for _ = 1, 25 do
			QuestRules.apply(progress, { kind = "deliver", biome = "enchanted_forest", rarity = "legendary" })
		end
		T.eq(progress.deliver_eggs, 20, "목표에서 멈춤")
		T.falsy(QuestRules.allDone(progress))
		local changed = QuestRules.apply(progress, { kind = "deliver", biome = "snow", rarity = "eternal" })
		T.eq(#changed, 1)
		T.eq(progress.deliver_eternal, 1)
		QuestRules.apply(progress, { kind = "fuse" })
		T.truthy(QuestRules.allDone(progress))
		local view = QuestRules.view(progress)
		T.eq(#view, 3)
		for _, q in view do
			T.truthy(q.done, q.id)
		end
		T.eq(#QuestRules.apply(progress, { kind = "fuse" }), 0, "끝난 뒤에는 안 바뀜")
	end)

	T.test("마법의 숲 영원 알 하나는 두 퀘스트를 같이 올림", function()
		local progress = {}
		local changed = QuestRules.apply(progress, { kind = "deliver", biome = "enchanted_forest", rarity = "eternal" })
		T.eq(#changed, 2)
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
		T.eq(Remotes.ToServer.FuseRequest, "FuseRequest")
		T.eq(Remotes.ToClient.QuestUpdate, "QuestUpdate")
		T.eq(Tags.Altar, "Altar")
		T.eq(Tags.QuestGate, "QuestGate")
		T.eq(Tags.SakuraIncubator, "SakuraIncubator")
	end)
end
