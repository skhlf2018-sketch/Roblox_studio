--!nocheck
-- 도감(6판: 성체 도감) 진행도, 구역 무기 해금, 미수령 보상 합계

return function(T, Loader)
	local Progression = Loader.require("ReplicatedStorage/Shared/Progression")
	local Plants = Loader.require("ReplicatedStorage/Shared/Data/Plants")

	T.suite("Progression (6판)")

	local function discoverBiome(biomeId)
		local discovered = {}
		for _, plant in Plants.inBiome(biomeId) do
			discovered[plant.id] = true
		end
		return discovered
	end

	T.test("구역 진행도", function()
		local found, total = Progression.biomeProgress({ sprout_daisy = true, puppy_grass = true }, "forest")
		T.eq(found, 2)
		T.eq(total, 8)
		T.falsy(Progression.isBiomeComplete({ sprout_daisy = true }, "forest"))
		T.truthy(Progression.isBiomeComplete(discoverBiome("forest"), "forest"))
	end)

	T.test("무기: 숲은 무기 없음, 호수 완성 → 물 방망이", function()
		T.eq(#Progression.unlockedWeapons(discoverBiome("forest")), 0)
		local weapons = Progression.unlockedWeapons(discoverBiome("lake"))
		T.eq(#weapons, 1)
		T.eq(weapons[1], "water_bat")
	end)

	T.test(
		"벚꽃 무기(카타나)는 사쿠라 씨앗 2종 제외 8종이면 해금, 도감 진행도는 10종",
		function()
			local discovered = discoverBiome("cherry_blossom")
			discovered.blossom_fairy = nil
			discovered.spirit_blossom = nil
			local found, total = Progression.weaponProgress(discovered, "cherry_blossom")
			T.eq(total, 8)
			T.eq(found, 8)
			T.eq(Progression.unlockedWeapons(discovered)[1], "katana")
			discovered.moon_plum = nil -- 둥지 식물은 빠지면 안 됨
			T.eq(#Progression.unlockedWeapons(discovered), 0)
			local _, all = Progression.biomeProgress(discovered, "cherry_blossom")
			T.eq(all, 10)
		end
	)

	T.test("천사&악마 무기는 양쪽 둥지 16종 + 공지 씨앗 2종 = 18종 필요", function()
		local discovered = discoverBiome("angels_demons")
		local found, total = Progression.weaponProgress(discovered, "angels_demons")
		T.eq(total, 18)
		T.eq(found, 18)
		T.eq(Progression.unlockedWeapons(discovered)[1], "angel_spear")
		discovered.balance_tree = nil
		T.eq(#Progression.unlockedWeapons(discovered), 0)
	end)

	T.test("마법의 숲 무기는 공지 씨앗까지 10종 필요", function()
		local discovered = discoverBiome("enchanted_forest")
		T.eq(Progression.unlockedWeapons(discovered)[1], "hammer")
		discovered.world_tree = nil
		T.eq(#Progression.unlockedWeapons(discovered), 0)
		local _, total = Progression.weaponProgress(discovered, "enchanted_forest")
		T.eq(total, 10)
	end)

	T.test("무기 없는 구역은 요구 목록이 비어 있음", function()
		T.eq(#Progression.weaponRequirement("forest"), 0)
		T.falsy(Progression.isWeaponUnlocked(discoverBiome("forest"), "forest"))
	end)

	T.test("곰덫 도감 보상: 희귀 이상 +1, 그 발견으로 구역 완성이면 +5 더", function()
		T.eq(Progression.trapsForDiscovery({ sprout_daisy = true }, "sprout_daisy"), 0, "일반")
		T.eq(Progression.trapsForDiscovery({ owl_oak = true }, "owl_oak"), 1, "희귀")
		T.eq(Progression.trapsForDiscovery({}, "owl_oak"), 0, "발견 표에 없으면 0")
		local forest = discoverBiome("forest")
		T.eq(Progression.trapsForDiscovery(forest, "sprout_daisy"), 5, "마지막이 일반이어도 구역 완성 +5")
		T.eq(Progression.trapsForDiscovery(forest, "firefly_lily"), 6)
		T.eq(Progression.trapsForDiscovery({ x = true }, "없는식물"), 0)
	end)

	T.test("전체 도감 완성 (134종)", function()
		local all = {}
		for _, plant in Plants.list do
			all[plant.id] = true
		end
		T.truthy(Progression.isIndexComplete(all))
		all.sky_pillar_flower = nil
		T.falsy(Progression.isIndexComplete(all))
	end)

	T.test(
		"미수령 보상: 아기 데이지 + 부엉이 참나무 = 속도 1040, 코인 1,900 (받은 건 제외)",
		function()
			local ids, speed, money = Progression.pendingRewards(
				{ sprout_daisy = true, owl_oak = true, puppy_grass = true },
				{ puppy_grass = true }
			)
			T.eq(#ids, 2)
			T.eq(speed, 420 + 620)
			T.eq(money, 100 + 1800)
		end
	)
end
