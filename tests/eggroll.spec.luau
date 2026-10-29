--!nocheck
-- 가중치 추첨, 크기/돌연변이 확률, 둥지 풀(6판: 구역 등급표), 특별 씨앗 추첨

return function(T, Loader)
	local EggRoll = Loader.require("ReplicatedStorage/Shared/EggRoll")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local EggSpawn = Loader.require("ReplicatedStorage/Shared/Data/EggSpawn")

	T.suite("EggRoll")

	T.test("weightedIndex: 경계값", function()
		T.eq(EggRoll.weightedIndex({ 1, 1 }, T.constant(0)), 1)
		T.eq(EggRoll.weightedIndex({ 1, 1 }, T.constant(0.4999)), 1)
		T.eq(EggRoll.weightedIndex({ 1, 1 }, T.constant(0.5)), 2)
		T.eq(EggRoll.weightedIndex({ 0, 5, 0 }, T.constant(0.99)), 2)
		T.eq(EggRoll.weightedIndex({ 0, 0 }, T.constant(0.3)), nil)
		T.eq(EggRoll.weightedIndex({}, T.constant(0.3)), nil)
		T.eq(EggRoll.weightedIndex({ 3, 1 }, T.constant(0.999999999)), 2)
	end)

	T.test("크기 분포 ≈ 70/20/8/2 (20만 회)", function()
		local rand = T.rng(12345)
		local counts = { normal = 0, big = 0, huge = 0, giant = 0 }
		local n = 200000
		for _ = 1, n do
			local s = EggRoll.rollSize(rand)
			counts[s] += 1
		end
		T.near(counts.normal / n, 0.70, 0.005, "normal")
		T.near(counts.big / n, 0.20, 0.005, "big")
		T.near(counts.huge / n, 0.08, 0.004, "huge")
		T.near(counts.giant / n, 0.02, 0.002, "giant")
	end)

	T.test("자연 돌연변이 ≈ 실버 5% / 황금 2% / 무지개 0.5%", function()
		local rand = T.rng(999)
		local counts = { silver = 0, golden = 0, rainbow = 0, none = 0 }
		local n = 400000
		for _ = 1, n do
			local m = EggRoll.rollNaturalMutation(rand)
			counts[m or "none"] += 1
		end
		T.near(counts.silver / n, 0.05, 0.002, "silver")
		T.near(counts.golden / n, 0.02, 0.0015, "golden")
		T.near(counts.rainbow / n, 0.005, 0.0007, "rainbow")
	end)

	T.test("둥지 풀: 공지 씨앗·사쿠라 씨앗 제외, 천사&악마는 쪽별", function()
		T.eq(#EggRoll.nestPool("forest", nil), 8)
		T.eq(#EggRoll.nestPool("enchanted_forest", nil), 8)
		local light = EggRoll.nestPool("angels_demons", "light")
		T.eq(#light, 8)
		for _, p in light do
			T.eq(p.side, "light")
		end
		T.eq(#EggRoll.nestPool("angels_demons", "dark"), 8)
	end)

	T.test(
		"6판 구역 등급 가중치: 등급을 표대로 고르고 그 등급 안에서 고르게 (식물 가중치 = 등급 가중치 ÷ 같은 등급 수)",
		function()
			T.eq(EggRoll.centerRarity, nil, "5판 중심 희귀도 방식은 없앰")
			-- 숲: 일반 60 (3종) / 고급 35 (3종) / 희귀 5 (2종)
			local odds = EggRoll.nestOdds("forest", nil)
			T.near(odds.sprout_daisy, 0.60 / 3, 1e-9)
			T.near(odds.puppy_grass, 0.60 / 3, 1e-9)
			T.near(odds.mossy_fern, 0.35 / 3, 1e-9)
			T.near(odds.owl_oak, 0.05 / 2, 1e-9)
			T.eq(EggRoll.rarityWeight("forest", "epic"), 0)
			T.eq(EggRoll.rarityWeight("없는구역", "common"), 0)
			-- 천사&악마: 쪽마다 같은 확률표 (신화 45 / 코스믹 45 / 비밀 10)
			local light = EggRoll.nestOdds("angels_demons", "light")
			local dark = EggRoll.nestOdds("angels_demons", "dark")
			T.near(light.halo_daisy, 0.45 / 3, 1e-9)
			T.near(dark.horn_thistle, 0.45 / 3, 1e-9)
			T.near(light.heaven_tree, 0.10 / 2, 1e-9)
			T.eq(light.horn_thistle, nil, "지옥 쪽 식물은 천국 주기에 안 나옴")
		end
	)

	T.test(
		"일반 추첨: 구역 둥지 풀 안에서만, 구역 표에 없는 등급은 안 나옴 (7판: 유령 성 슈퍼 2종은 일반 추첨 5%)",
		function()
			local rand = T.rng(42)
			for _, b in Biomes.list do
				local side = Biomes.sideForCycle(b, 1)
				local pool = {}
				for _, p in EggRoll.nestPool(b.id, side) do
					pool[p.id] = true
				end
				for _ = 1, 300 do
					local pet = EggRoll.rollNestPet(b.id, side, rand)
					T.truthy(pet, b.id .. " 추첨 결과")
					T.truthy(pool[pet.id], b.id .. " 풀 밖 " .. pet.id)
					T.truthy(EggRoll.rarityWeight(b.id, pet.rarity) > 0, b.id .. " 표 밖 등급 " .. pet.rarity)
				end
			end
			local castle = EggRoll.nestOdds("haunted_castle", nil)
			T.near(castle.rainbow_thunder_tree, 0.025, 1e-9, "슈퍼 5% ÷ 2종")
			T.near(castle.sky_pillar_flower, 0.025, 1e-9)
			local bug = EggRoll.nestOdds("bug_dimension", nil)
			T.near(bug.glitch_hacker_bloom, 0.025, 1e-9, "해커 글리치 5% ÷ 2종")
			T.near(bug.static_world_tree, 0.025, 1e-9)
		end
	)

	T.test(
		"등급 비율 (10만 번): 숲 일반 ≈ 60% · 고급 ≈ 35% · 희귀 ≈ 5%, 유령 성 영원 ≈ 55% · 신성 ≈ 45%",
		function()
			local function shares(biomeId)
				local rand = T.rng(2026)
				local counts = {}
				local n = 100000
				for _ = 1, n do
					local pet = EggRoll.rollNestPet(biomeId, nil, rand)
					counts[pet.rarity] = (counts[pet.rarity] or 0) + 1
				end
				for k, v in counts do
					counts[k] = v / n
				end
				return counts
			end
			local forest = shares("forest")
			T.near(forest.common, 0.60, 0.01)
			T.near(forest.uncommon, 0.35, 0.01)
			T.near(forest.rare, 0.05, 0.005)
			T.eq(forest.epic, nil)
			local castle = shares("haunted_castle")
			T.near(castle.eternity, 0.55, 0.01)
			T.near(castle.divine, 0.40, 0.01)
			T.near(castle.super, 0.05, 0.005, "7판: 유령 성 가끔 슈퍼")
			-- 7판 새 구역
			local lab = shares("hacker_lab")
			T.near(lab.super, 0.55, 0.01)
			T.near(lab.hacker, 0.40, 0.01)
			T.near(lab.original, 0.05, 0.005)
			local room = shares("developer_room")
			T.near(room.original, 0.55, 0.01)
			T.near(room.developer, 0.40, 0.01)
			T.near(room.ultradivine, 0.05, 0.005)
			local bug = shares("bug_dimension")
			T.near(bug.developer, 0.40, 0.01)
			T.near(bug.ultradivine, 0.55, 0.01)
			T.near(bug.hacker_glitch, 0.05, 0.005)
			T.eq(bug.super, nil)
		end
	)

	T.test("숲 확률표 합 1, 아기 데이지가 부엉이 참나무보다 자주", function()
		local odds = EggRoll.nestOdds("forest", nil)
		T.truthy(odds.sprout_daisy > odds.owl_oak)
		local sum = 0
		for _, v in odds do
			sum += v
		end
		T.near(sum, 1, 1e-9)
	end)

	T.test(
		"특별 추첨: 난수 0 이면 희귀한 것부터 최대 2개, 0.99 면 없음 (7판: 해커 글리치는 버그 차원에서만)",
		function()
			local specials = EggRoll.rollSpecials("haunted_castle", nil, T.constant(0))
			T.eq(#specials, EggSpawn.MAX_SPECIALS_PER_BIOME)
			T.eq(specials[1].rarity, "super")
			T.eq(specials[2].rarity, "divine")
			local bug = EggRoll.rollSpecials("bug_dimension", nil, T.constant(0))
			T.eq(#bug, 2)
			T.eq(bug[1].rarity, "hacker_glitch")
			T.eq(bug[2].rarity, "ultradivine")
			local lab = EggRoll.rollSpecials("hacker_lab", nil, T.constant(0))
			T.eq(lab[1].rarity, "original")
			T.eq(lab[2].rarity, "hacker")
			for _, b in Biomes.list do
				for _, pet in EggRoll.rollSpecials(b.id, Biomes.sideForCycle(b, 1), T.constant(0)) do
					if pet.rarity == "hacker_glitch" then
						T.eq(b.id, "bug_dimension", "해커 글리치 공지는 버그 차원에서만")
					end
				end
			end
			T.eq(#EggRoll.rollSpecials("haunted_castle", nil, T.constant(0.99)), 0)
			-- 숲에는 비밀 이상 식물이 없음
			T.eq(#EggRoll.rollSpecials("forest", nil, T.constant(0)), 0)
			-- 타이탄 사원(신화·코스믹·비밀)은 비밀만
			local titan = EggRoll.rollSpecials("titan_temple", nil, T.constant(0))
			T.eq(#titan, 1)
			T.eq(titan[1].rarity, "secret")
		end
	)

	T.test("특별 추첨 확률 ≈ 표 값 (타이탄 사원 비밀 8%)", function()
		local rand = T.rng(7)
		local hits = 0
		local n = 100000
		for _ = 1, n do
			if #EggRoll.rollSpecials("titan_temple", nil, rand) > 0 then
				hits += 1
			end
		end
		T.near(hits / n, EggSpawn.SPECIAL_CHANCE_PER_RESET.secret, 0.003)
	end)

	T.test("pickDistinct: 서로 다른 칸", function()
		local rand = T.rng(3)
		for _ = 1, 50 do
			local picks = EggRoll.pickDistinct(8, 3, rand)
			T.eq(#picks, 3)
			local seen = {}
			for _, i in picks do
				T.falsy(seen[i], "중복")
				T.truthy(i >= 1 and i <= 8, "범위")
				seen[i] = true
			end
		end
		T.eq(#EggRoll.pickDistinct(2, 5, rand), 2)
	end)

	T.test("rollTraits: 크기 + 자연 돌연변이 최대 1개", function()
		local rand = T.rng(77)
		for _ = 1, 1000 do
			local traits = EggRoll.rollTraits(rand)
			T.truthy(#traits.mutations <= 1)
			T.truthy(traits.size ~= nil)
		end
	end)

	T.test("모든 둥지 식물 id 는 Plants 에 존재", function()
		for _, b in Biomes.list do
			for _, side in b.sides or { false } do
				for _, p in EggRoll.nestPool(b.id, side or nil) do
					T.truthy(Pets.get(p.id))
				end
			end
		end
	end)
end
