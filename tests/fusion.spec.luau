--!nocheck
-- 퓨전 머신 규칙 (shared/FusionRules)

return function(T, Loader)
	local FusionRules = Loader.require("ReplicatedStorage/Shared/FusionRules")
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Rarities = Loader.require("ReplicatedStorage/Shared/Data/Rarities")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Mutations = Loader.require("ReplicatedStorage/Shared/Data/Mutations")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")

	T.suite("FusionRules")

	local function three(petId, size, m1, m2, m3)
		return {
			{ uid = "p1", petId = petId, size = size or "normal", mutations = m1 or {} },
			{ uid = "p2", petId = petId, size = size or "normal", mutations = m2 or m1 or {} },
			{ uid = "p3", petId = petId, size = size or "normal", mutations = m3 or m1 or {} },
		}
	end

	local NO_BONUS = T.constant(0.5) -- 후보 고르기 중간, 보너스 0.5 ≥ 0.1 → 없음

	T.test("입력 검사: 3마리, uid 다름, 같은 petId", function()
		local ok, err = FusionRules.validate({})
		T.falsy(ok)
		T.eq(err, "count")
		local inputs = three("chicken")
		inputs[3].uid = "p1"
		ok, err = FusionRules.validate(inputs)
		T.eq(err, "duplicate")
		inputs = three("chicken")
		inputs[2].petId = "dog"
		ok, err = FusionRules.validate(inputs)
		T.eq(err, "mismatch")
		ok, err = FusionRules.validate(three("없는펫"))
		T.eq(err, "unknown")
		T.truthy(FusionRules.validate(three("chicken")))
	end)

	T.test("후보: 같은 구역 희귀도 +1 둥지 펫, 천사&악마는 같은 쪽 우선", function()
		local c = FusionRules.candidates("chicken")
		T.eq(#c, 1)
		T.eq(c[1].id, "bird")
		c = FusionRules.candidates("pegasus") -- 천국 영원 → 천국 신성 (에테론은 합성 펫이라 제외)
		T.eq(#c, 1)
		T.eq(c[1].id, "archangel")
		c = FusionRules.candidates("skeleton_horse")
		T.eq(c[1].id, "world_burner")
		c = FusionRules.candidates("ring_guard") -- 쪽이 없는 펫 → 양쪽 영원 둥지 펫
		T.eq(#c, 2)
		T.eq(#FusionRules.candidates("brr_brr_patapim"), 0, "숲에는 신화가 없음")
		T.eq(#FusionRules.candidates("ghost_king"), 0, "신성 위는 없음")
	end)

	T.test("돌연변이: 셋이 같으면(순서 무관) 유지, 아니면 사라짐", function()
		local same =
			FusionRules.commonMutations(three("chicken", "normal", { "golden", "bloom" }, { "bloom", "golden" }))
		T.eq(#same, 2)
		local mixed = FusionRules.commonMutations(three("chicken", "normal", { "golden" }, { "golden" }, { "silver" }))
		T.eq(#mixed, 0)
		local none = FusionRules.commonMutations(three("chicken", "normal", {}, {}, { "silver" }))
		T.eq(#none, 0)
	end)

	T.test("닭 3마리 → 새 (희귀도 업, 보통 크기면 충분)", function()
		local result, err = FusionRules.fuse(three("chicken"), NO_BONUS)
		T.eq(err, nil)
		T.eq(result.petId, "bird")
		T.eq(result.size, "normal")
		T.truthy(result.upgraded)
		T.eq(result.bonusMutation, nil)
		T.eq(result.inputIncome, 9)
		T.eq(result.resultIncome, 24)
	end)

	T.test("크기 보정: 초거대 골든 닭 3마리(합 108) → 거대 골든 새(144)", function()
		local result = FusionRules.fuse(three("chicken", "giant", { "golden" }), NO_BONUS)
		T.eq(result.petId, "bird")
		T.eq(result.size, "huge")
		T.eq(result.mutations[1], "golden")
		T.eq(result.inputIncome, 108)
		T.eq(result.resultIncome, 144)
	end)

	T.test("돌연변이가 다르면 사라지고 크기로 보정", function()
		local result = FusionRules.fuse(three("chicken", "giant", { "golden" }, { "golden" }, { "silver" }), NO_BONUS)
		T.eq(#result.mutations, 0)
		-- 합 = 36 + 36 + 22.5 = 94.5 → 새 보통 24, 큼 36, 거대 72, 초거대 144
		T.eq(result.size, "giant")
		T.truthy(result.resultIncome >= result.inputIncome)
	end)

	T.test("위 희귀도가 없으면 같은 펫 크기 업 (가장 큰 입력 크기 + 1부터)", function()
		local result = FusionRules.fuse(three("brr_brr_patapim"), NO_BONUS)
		T.eq(result.petId, "brr_brr_patapim")
		T.falsy(result.upgraded)
		T.eq(result.size, "huge", "큼(×1.5)으론 합(×3)에 못 미쳐 거대")
		result = FusionRules.fuse(three("ghost_king", "big"), NO_BONUS)
		T.eq(result.size, "giant", "큼 3마리(×4.5) → 초거대(×6)")
	end)

	T.test("합보다 약해질 수밖에 없으면 거부 (거대 파타핌 3마리)", function()
		local result, err = FusionRules.fuse(three("brr_brr_patapim", "huge"), NO_BONUS)
		T.eq(result, nil)
		T.eq(err, "weaker")
		T.truthy(#FusionRules.errorText("weaker") > 0)
	end)

	T.test(
		"보너스 돌연변이: 난수 0 → 실버, 이미 더 좋은 자연 돌연변이가 있으면 유지",
		function()
			local result = FusionRules.fuse(three("chicken"), T.constant(0))
			T.eq(result.bonusMutation, "silver")
			T.eq(result.mutations[1], "silver")
			local kept, applied = FusionRules.applyBonus({ "golden" }, "silver")
			T.eq(kept[1], "golden")
			T.eq(applied, nil)
			local replaced, applied2 = FusionRules.applyBonus({ "silver", "bloom" }, "rainbow")
			T.eq(replaced[1], "rainbow")
			T.eq(replaced[2], "bloom")
			T.eq(applied2, "rainbow")
			local added = FusionRules.applyBonus({ "bloom" }, "golden")
			T.eq(#added, 2)
		end
	)

	T.test("보너스 확률 ≈ 10%, 실버:골든:레인보우 ≈ 5:2:0.5 (40만 회)", function()
		local rand = T.rng(2024)
		local counts = { silver = 0, golden = 0, rainbow = 0 }
		local n = 400000
		local hits = 0
		for _ = 1, n do
			local id = FusionRules.rollBonusMutation(rand)
			if id then
				hits += 1
				counts[id] += 1
			end
		end
		T.near(hits / n, Config.FUSION_BONUS_MUTATION_CHANCE, 0.003, "보너스 확률")
		T.near(counts.silver / hits, 5 / 7.5, 0.01, "silver")
		T.near(counts.golden / hits, 2 / 7.5, 0.01, "golden")
		T.near(counts.rainbow / hits, 0.5 / 7.5, 0.005, "rainbow")
	end)

	T.test(
		"모든 펫·크기: 성공하면 결과 수입 ≥ 3마리 합, 결과는 같은 구역 둥지 펫 또는 같은 펫",
		function()
			local rand = T.rng(99)
			local naturals = { {}, { "silver" }, { "golden" }, { "rainbow" }, { "golden", "spirit_bloom" } }
			local successes, refusals = 0, 0
			for _, pet in Pets.list do
				for _, size in Sizes.list do
					for _, muts in naturals do
						local result, err = FusionRules.fuse(three(pet.id, size.id, muts), rand)
						if result then
							successes += 1
							T.truthy(result.resultIncome >= result.inputIncome * (1 - 1e-9), pet.id .. " " .. size.id)
							local out = Pets.get(result.petId)
							T.eq(out.biome, pet.biome, pet.id .. " 구역")
							if result.upgraded then
								T.eq(out.source, "nest", pet.id .. " → 둥지 펫만")
								T.eq(
									Rarities.order(out.rarity),
									Rarities.order(pet.rarity) + 1,
									pet.id .. " 희귀도 +1"
								)
							else
								T.eq(out.id, pet.id)
							end
							T.truthy(Economy.isValidMutationSet(result.mutations), pet.id .. " 돌연변이 조합")
						else
							T.eq(err, "weaker")
							refusals += 1
						end
					end
				end
			end
			T.truthy(successes > 0 and refusals > 0)
			T.truthy(#Mutations.list > 0)
		end
	)
end
