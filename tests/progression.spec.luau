--!nocheck
-- 도감 진행도, 구역 무기 해금, 미수령 보상 합계

return function(T, Loader)
	local Progression = Loader.require("ReplicatedStorage/Shared/Progression")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")

	T.suite("Progression")

	local function discoverBiome(biomeId)
		local discovered = {}
		for _, pet in Pets.inBiome(biomeId) do
			discovered[pet.id] = true
		end
		return discovered
	end

	T.test("구역 진행도", function()
		local found, total = Progression.biomeProgress({ chicken = true, dog = true }, "forest")
		T.eq(found, 2)
		T.eq(total, 8)
		T.falsy(Progression.isBiomeComplete({ chicken = true }, "forest"))
		T.truthy(Progression.isBiomeComplete(discoverBiome("forest"), "forest"))
	end)

	T.test("무기: 숲은 무기 없음, 호수 완성 → 물 방망이", function()
		T.eq(#Progression.unlockedWeapons(discoverBiome("forest")), 0)
		local weapons = Progression.unlockedWeapons(discoverBiome("lake"))
		T.eq(#weapons, 1)
		T.eq(weapons[1], "water_bat")
	end)

	T.test("천사&악마 무기는 합성·제단 펫까지 20종 전부 필요", function()
		local discovered = discoverBiome("angels_demons")
		discovered.aetheron = nil
		T.eq(#Progression.unlockedWeapons(discovered), 0)
		discovered.aetheron = true
		T.eq(Progression.unlockedWeapons(discovered)[1], "angel_spear")
	end)

	T.test("전체 도감 완성", function()
		local all = {}
		for _, pet in Pets.list do
			all[pet.id] = true
		end
		T.truthy(Progression.isIndexComplete(all))
		all.chicken = nil
		T.falsy(Progression.isIndexComplete(all))
	end)

	T.test("미수령 보상: 닭 + 라쿤 = 속도 1040, 돈 $4,600 (받은 건 제외)", function()
		local ids, speed, money = Progression.pendingRewards(
			{ chicken = true, raccoon = true, dog = true },
			{ dog = true }
		)
		T.eq(#ids, 2)
		T.eq(speed, 420 + 620)
		T.eq(money, 100 + 4500)
	end)
end
