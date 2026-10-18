--!nocheck
-- 데이터 표 무결성 검사: 펫 수, 구역마다 둥지 펫 8종, id 참조가 전부 맞는지

return function(T, Loader)
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Rarities = Loader.require("ReplicatedStorage/Shared/Data/Rarities")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Mutations = Loader.require("ReplicatedStorage/Shared/Data/Mutations")
	local Upgrades = Loader.require("ReplicatedStorage/Shared/Data/Upgrades")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local EggSpawn = Loader.require("ReplicatedStorage/Shared/Data/EggSpawn")
	local Index = Loader.require("ReplicatedStorage/Shared/Data/Index")

	T.suite("데이터 표")

	T.test("성장 배율 3", function()
		T.eq(Config.GROWTH_MULTIPLIER, 3)
	end)

	T.test("희귀도 10등급, 순서 1~10", function()
		T.eq(#Rarities.list, 10)
		for i, r in Rarities.list do
			T.eq(r.order, i, r.id)
			T.eq(#r.color, 3, r.id .. " color")
		end
	end)

	T.test("구역 15개, 순서·추천 속도 오름차순, 경비 속도 = 추천 속도", function()
		T.eq(#Biomes.list, 15)
		local prev = 0
		for i, b in Biomes.list do
			T.eq(b.order, i, b.id .. " order")
			T.truthy(b.recommendedSpeed > prev, b.id .. " 추천 속도 증가")
			prev = b.recommendedSpeed
			T.eq(b.guardSpeed, b.recommendedSpeed * Config.GUARD_SPEED_RATIO, b.id .. " guardSpeed")
			T.eq(b.nests, 8, b.id .. " 둥지 8개")
		end
		T.eq(Biomes.get("candy_kingdom").recommendedSpeed, 150e9)
		T.eq(Biomes.get("haunted_castle").recommendedSpeed, 500e9)
	end)

	T.test("펫 134종 (설계문서 5장 목록 그대로)", function()
		-- 11개 구역 × 8 = 88, 천사&악마 20, 마법의 숲 10, 사탕 왕국 8, 유령 성 8
		T.eq(Pets.count, 134)
		T.eq(#Pets.inBiome("angels_demons"), 20)
		T.eq(#Pets.inBiome("enchanted_forest"), 10)
	end)

	T.test("모든 펫: 구역·희귀도 id 가 존재, 수입·부화 시간 양수", function()
		for _, p in Pets.list do
			T.truthy(Biomes.get(p.biome), p.id .. " biome")
			T.truthy(Rarities.get(p.rarity), p.id .. " rarity")
			T.truthy(p.income > 0, p.id .. " income")
			T.truthy(p.hatchSeconds > 0, p.id .. " hatch")
			T.truthy(#p.name > 0 and #p.nameEn > 0, p.id .. " names")
		end
	end)

	T.test("구역마다 둥지 펫 8종 (천사&악마는 쪽마다 8종)", function()
		for _, b in Biomes.list do
			if b.sides then
				for _, side in b.sides do
					local n = 0
					for _, p in Pets.inBiome(b.id) do
						if p.source == "nest" and p.side == side then
							n += 1
						end
					end
					T.eq(n, 8, b.id .. " " .. side)
				end
			else
				local n = 0
				for _, p in Pets.inBiome(b.id) do
					if p.source == "nest" then
						n += 1
					end
				end
				T.eq(n, 8, b.id)
			end
		end
	end)

	T.test("원본 숫자 표본 확인", function()
		T.eq(Pets.get("chicken").income, 1)
		T.eq(Pets.get("chicken").hatchSeconds, 10)
		T.eq(Pets.get("brr_brr_patapim").income, 1800)
		T.eq(Pets.get("king_snake").hatchSeconds, 5400)
		T.eq(Pets.get("yeti").hatchSeconds, 6300)
		T.eq(Pets.get("ghost_king").income, 30e9)
		T.eq(Pets.get("ghost_king").hatchSeconds, 86400)
		T.eq(Pets.get("aetheron").source, "fusion")
		T.eq(Pets.get("jitterbug").hatchSeconds, 20)
		T.eq(Pets.get("spirit_world_guardian").income, 26e9)
	end)

	T.test("크기 확률 합 100, 돌연변이 8종", function()
		local sum = 0
		for _, s in Sizes.list do
			sum += s.chance
		end
		T.eq(sum, 100)
		T.eq(#Mutations.list, 8)
		T.eq(Mutations.get("silver").naturalChance, 0.05)
		T.eq(Mutations.get("golden").naturalChance, 0.02)
		T.eq(Mutations.get("rainbow").naturalChance, 0.005)
	end)

	T.test("업그레이드 표: 우리 11, 러닝머신 10, 트레일 11", function()
		T.eq(#Upgrades.Pen, 11)
		T.eq(Upgrades.Pen[11].slots, 18)
		T.eq(Upgrades.Pen[11].cost, 5e15)
		T.eq(#Upgrades.Treadmill, 10)
		T.eq(Upgrades.Treadmill[10].perStep, 2000)
		T.eq(Upgrades.Treadmill[1].cost, 1000)
		T.eq(#Upgrades.Trails, 11)
		T.eq(Upgrades.getTrail("moonbloom").multiplier, 20)
		for i = 2, #Upgrades.Pen do
			T.truthy(Upgrades.Pen[i].cost > Upgrades.Pen[i - 1].cost, "pen cost 증가 " .. i)
		end
	end)

	T.test("둥지 가중치: 비밀/영원/신성은 0 (초기화 특별 추첨으로만)", function()
		for _, id in EggSpawn.SPECIAL_RARITIES do
			T.eq(EggSpawn.NEST_RARITY_WEIGHTS[id], 0, id)
			T.truthy(EggSpawn.SPECIAL_CHANCE_PER_RESET[id] > 0, id)
		end
		T.eq(EggSpawn.SPECIAL_CHANCE_PER_RESET.divine, 0.002)
	end)

	T.test("도감 보상: 설계문서 예시와 일치", function()
		local forest = Biomes.get("forest").recommendedSpeed
		local chicken = Index.reward("common", Pets.get("chicken").income, forest)
		T.eq(chicken.speed, 420)
		T.eq(chicken.money, 100)
		local raccoon = Index.reward("rare", Pets.get("raccoon").income, forest)
		T.eq(raccoon.speed, 620)
		T.eq(raccoon.money, 4500)
		local patapim = Index.reward("legendary", Pets.get("brr_brr_patapim").income, forest)
		T.eq(patapim.speed, 1000)
		T.eq(patapim.money, 180000)
		-- 모든 희귀도에 속도 보상이 정의되어 있음
		for _, r in Rarities.list do
			T.truthy(Index.RARITY_SPEED[r.id] ~= nil, r.id)
		end
	end)

	T.test("도감 속도 보상: 뒤 구역은 (추천 속도/3600)^0.8 배 (정비례보다 느리게)", function()
		T.eq(Index.SPEED_BIOME_EXPONENT, 0.8)
		local prehistoric = Biomes.get("prehistoric").recommendedSpeed -- 18M → 배율 5000
		local dodo = Index.reward("rare", Pets.get("dodo").income, prehistoric)
		T.eq(dodo.speed, math.floor(620 * 5000 ^ 0.8 + 0.5))
		T.truthy(dodo.speed > 620 * 900 and dodo.speed < 620 * 920, "5000^0.8 ≈ 911")
		T.eq(dodo.money, 28000, "돈 보상은 그대로")
		-- 추천 속도가 3600 이하(숲·호수)면 배율 1
		T.eq(Index.reward("epic", 320, Biomes.get("lake").recommendedSpeed).speed, 800)
		-- 뒤 구역일수록 보상이 커짐, 하지만 추천 속도 대비 비율은 줄어듦
		local prevSpeed, prevRatio = 0, math.huge
		for _, b in Biomes.list do
			if b.recommendedSpeed > Index.SPEED_BIOME_REFERENCE then
				local s = Index.reward("cosmic", 1, b.recommendedSpeed).speed
				T.truthy(s > prevSpeed, b.id .. " 증가")
				T.truthy(s / b.recommendedSpeed < prevRatio, b.id .. " 비율 감소")
				prevSpeed, prevRatio = s, s / b.recommendedSpeed
			end
		end
	end)
end
