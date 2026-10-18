--!nocheck
-- 가중치 추첨, 크기/돌연변이 확률, 둥지 풀, 특별 알 추첨

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

	T.test("자연 돌연변이 ≈ 실버 5% / 골든 2% / 레인보우 0.5%", function()
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

	T.test("둥지 풀: 퀘스트/합성/제단 펫 제외, 천사&악마는 쪽별", function()
		T.eq(#EggRoll.nestPool("forest", nil), 8)
		T.eq(#EggRoll.nestPool("enchanted_forest", nil), 8)
		local light = EggRoll.nestPool("angels_demons", "light")
		T.eq(#light, 8)
		for _, p in light do
			T.eq(p.side, "light")
		end
		T.eq(#EggRoll.nestPool("angels_demons", "dark"), 8)
	end)

	T.test("일반 추첨에 비밀/영원/신성이 절대 안 나옴", function()
		local rand = T.rng(42)
		for _, b in Biomes.list do
			local side = Biomes.sideForCycle(b, 1)
			for _ = 1, 300 do
				local pet = EggRoll.rollNestPet(b.id, side, rand)
				T.truthy(pet, b.id .. " 추첨 결과")
				T.truthy(EggSpawn.NEST_RARITY_WEIGHTS[pet.rarity] > 0, b.id .. " " .. pet.id)
			end
		end
	end)

	T.test("숲 확률: 닭이 파타핌보다 자주, 합 1", function()
		local odds = EggRoll.nestOdds("forest", nil)
		T.truthy(odds.chicken > odds.brr_brr_patapim)
		local sum = 0
		for _, v in odds do
			sum += v
		end
		T.near(sum, 1, 1e-9)
	end)

	T.test("특별 추첨: 난수 0 이면 희귀한 것부터 최대 2개, 0.99 면 없음", function()
		local specials = EggRoll.rollSpecials("haunted_castle", nil, T.constant(0))
		T.eq(#specials, EggSpawn.MAX_SPECIALS_PER_BIOME)
		T.eq(specials[1].rarity, "divine")
		T.eq(specials[2].rarity, "eternal")
		T.eq(#EggRoll.rollSpecials("haunted_castle", nil, T.constant(0.99)), 0)
		-- 숲에는 비밀/영원/신성 펫이 없음
		T.eq(#EggRoll.rollSpecials("forest", nil, T.constant(0)), 0)
		-- 정글은 비밀(킹 스네이크)만
		local jungle = EggRoll.rollSpecials("jungle", nil, T.constant(0))
		T.eq(#jungle, 1)
		T.eq(jungle[1].id, "king_snake")
	end)

	T.test("특별 추첨 확률 ≈ 표 값 (정글 비밀 8%)", function()
		local rand = T.rng(7)
		local hits = 0
		local n = 100000
		for _ = 1, n do
			if #EggRoll.rollSpecials("jungle", nil, rand) > 0 then
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

	T.test("모든 둥지 펫 id 는 Pets 에 존재", function()
		for _, b in Biomes.list do
			for _, side in b.sides or { false } do
				for _, p in EggRoll.nestPool(b.id, side or nil) do
					T.truthy(Pets.get(p.id))
				end
			end
		end
	end)
end
