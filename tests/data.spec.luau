--!nocheck
-- 데이터 표 무결성 검사 (6판 "씨앗을 훔치세요"): 등급 11개, 식물 134종, 구역마다 둥지 식물 8종, id 참조가 전부 맞는지

return function(T, Loader)
	local Plants = Loader.require("ReplicatedStorage/Shared/Data/Plants")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Rarities = Loader.require("ReplicatedStorage/Shared/Data/Rarities")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Mutations = Loader.require("ReplicatedStorage/Shared/Data/Mutations")
	local Upgrades = Loader.require("ReplicatedStorage/Shared/Data/Upgrades")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local EggSpawn = Loader.require("ReplicatedStorage/Shared/Data/EggSpawn")
	local Index = Loader.require("ReplicatedStorage/Shared/Data/Index")

	T.suite("데이터 표 (6판)")

	T.test("Pets.luau 는 Plants 호환 파일 (같은 표), 5판 GROWTH_MULTIPLIER 는 없어짐", function()
		T.eq(Pets, Plants)
		T.eq(Pets.get("puppy_grass"), Plants.get("puppy_grass"))
		T.eq(Config.GROWTH_MULTIPLIER, nil)
		T.eq(Config.PASSIVE_INCOME_PER_SECOND, 0, "자동 수입 0")
	end)

	T.test("등급 11개 (사장님 순서), id 그대로 영어, eternal → eternity, 아우라 칸", function()
		local ids = {
			"common",
			"uncommon",
			"rare",
			"epic",
			"legendary",
			"mythic",
			"cosmic",
			"secret",
			"eternity",
			"divine",
			"super_ultradivine",
		}
		T.eq(#Rarities.list, 11)
		for i, r in Rarities.list do
			T.eq(r.id, ids[i])
			T.eq(r.order, i, r.id)
			T.eq(#r.color, 3, r.id .. " color")
			T.truthy(typeof(r.aura) == "string" and #r.aura > 0, r.id .. " aura")
			T.truthy(r.baseGrowSeconds > 0, r.id)
		end
		T.eq(Rarities.get("eternal"), nil)
		T.eq(Rarities.get("eternity").name, "영원")
		T.eq(Rarities.get("super_ultradivine").name, "슈퍼 울트라디바인")
		T.eq(Rarities.get("common").aura, "none")
		T.eq(Rarities.get("super_ultradivine").aura, "sky_pillar")
	end)

	T.test(
		"등급 기준 성장 시간 = 설계 3장 표 (10초 · 1분 · 5분 · 20분 · 1시간 · 3시간 · 8시간 · 1일 · 2일 · 4일 · 7일)",
		function()
			local expect = { 10, 60, 300, 1200, 3600, 10800, 28800, 86400, 172800, 345600, 604800 }
			for i, r in Rarities.list do
				T.eq(r.baseGrowSeconds, expect[i], r.id)
			end
		end
	)

	T.test(
		"구역 15개, 순서·추천 속도 오름차순, 경비 속도 = 추천 속도 × (1 - 보통 무게 감소), 경비는 식물 괴물 이름",
		function()
			local SpeedMath = Loader.require("ReplicatedStorage/Shared/SpeedMath")
			T.eq(#Biomes.list, 15)
			local prev = 0
			for i, b in Biomes.list do
				T.eq(b.order, i, b.id .. " order")
				T.truthy(b.recommendedSpeed > prev, b.id .. " 추천 속도 증가")
				prev = b.recommendedSpeed
				T.near(
					b.guardSpeed,
					b.recommendedSpeed * Config.GUARD_SPEED_RATIO * (1 - Sizes.get("normal").speedPenalty),
					b.recommendedSpeed * 1e-12,
					b.id .. " guardSpeed"
				)
				T.near(b.guardSpeed, SpeedMath.guardSpeedFor(b.recommendedSpeed), b.recommendedSpeed * 1e-12, b.id)
				T.eq(b.nests, 8, b.id .. " 둥지 8개")
				T.truthy(#b.guardName > 0 and #b.guardNameEn > 0, b.id .. " 경비 이름")
			end
			T.eq(Biomes.get("candy_kingdom").recommendedSpeed, 150e9)
			T.eq(Biomes.get("haunted_castle").recommendedSpeed, 500e9)
			T.eq(Biomes.get("forest").guardName, "덥석 파리지옥")
			T.eq(Biomes.get("haunted_castle").guardName, "호박 머리 덩굴")
			T.eq(Biomes.guardDisplayName(Biomes.get("angels_demons"), "dark"), "악마 장미")
			for _, b in Biomes.list do
				T.falsy(string.find(b.guardName, "닭", 1, true), "5판 경비 이름이 남음: " .. b.guardName)
			end
		end
	)

	T.test("식물 134종 (구역 12개 × 8 + 벚꽃 10 + 천사&악마 18 + 마법의 숲 10)", function()
		T.eq(Plants.count, 134)
		T.eq(#Plants.list, 134)
		T.eq(#Plants.inBiome("cherry_blossom"), 10)
		T.eq(#Plants.inBiome("angels_demons"), 18)
		T.eq(#Plants.inBiome("enchanted_forest"), 10)
		local seen = {}
		for _, p in Plants.list do
			T.falsy(seen[p.id], "중복 " .. p.id)
			seen[p.id] = true
			T.truthy(string.match(p.id, "^[a-z_]+$"), p.id)
		end
	end)

	T.test(
		"모든 식물: 구역·등급 id 가 있고, 성장 시간·열매 간격·열매 값이 양수, hatchSeconds = growSeconds",
		function()
			for _, p in Plants.list do
				T.truthy(Biomes.get(p.biome), p.id .. " biome")
				T.truthy(Rarities.get(p.rarity), p.id .. " rarity")
				T.truthy(p.growSeconds > 0, p.id .. " grow")
				T.eq(p.hatchSeconds, p.growSeconds, p.id .. " 별칭")
				T.truthy(p.fruitIntervalSeconds > 0, p.id .. " interval")
				T.truthy(p.fruitValue > 0, p.id .. " value")
				T.near(p.income, p.fruitValue / p.fruitIntervalSeconds, 1e-9, p.id .. " income")
				T.truthy(#p.name > 0 and #p.nameEn > 0, p.id .. " names")
				T.truthy(p.source == "nest" or p.source == "special" or p.source == "sakura", p.id .. " source")
			end
		end
	)

	T.test("성장 시간은 등급 기준의 ×0.75 ~ ×1.25 (강아지풀 3초는 튜토리얼 예외)", function()
		for _, p in Plants.list do
			local base = Rarities.get(p.rarity).baseGrowSeconds
			if p.id ~= "puppy_grass" then
				T.truthy(
					p.growSeconds >= base * 0.75 and p.growSeconds <= base * 1.25,
					p.id .. " " .. p.growSeconds .. " / 기준 " .. base
				)
			end
		end
		T.eq(Plants.get("puppy_grass").growSeconds, 3)
		T.eq(Plants.get("puppy_grass").biome, "forest")
	end)

	T.test(
		"등급이 높을수록 열매 간격은 짧고(평균) 값은 큼 (등급끼리 겹치지 않음)",
		function()
			local prevMaxValue, prevAvgInterval = 0, math.huge
			for _, r in Rarities.list do
				local minValue, maxValue, sumInterval, n = math.huge, 0, 0, 0
				for _, p in Plants.list do
					if p.rarity == r.id then
						minValue = math.min(minValue, p.fruitValue)
						maxValue = math.max(maxValue, p.fruitValue)
						sumInterval += p.fruitIntervalSeconds
						n += 1
					end
				end
				T.truthy(n > 0, r.id .. " 식물이 있어야 함")
				T.truthy(minValue > prevMaxValue, r.id .. " 열매 값이 아래 등급보다 큼")
				local avg = sumInterval / n
				T.truthy(avg < prevAvgInterval, r.id .. " 평균 열매 간격이 짧아짐")
				prevMaxValue, prevAvgInterval = maxValue, avg
			end
		end
	)

	T.test(
		"구역마다 둥지 식물 8종 (천사&악마는 쪽마다 8종), 둥지 식물 등급은 그 구역 등급 표 안에만",
		function()
			for _, b in Biomes.list do
				local weights = EggSpawn.BIOME_RARITY_WEIGHTS[b.id]
				T.truthy(weights, b.id .. " 등급 표")
				local sides = b.sides or { "none" }
				for _, side in sides do
					local n = 0
					for _, p in Plants.inBiome(b.id) do
						if p.source == "nest" and (b.sides == nil or p.side == side) then
							n += 1
							T.truthy(
								weights[p.rarity] ~= nil,
								p.id .. " 등급 " .. p.rarity .. " 이 " .. b.id .. " 표에 없음"
							)
						end
					end
					T.eq(n, 8, b.id .. " " .. side)
				end
			end
		end
	)

	T.test(
		"구역 등급 표 합 100, 뒤 구역일수록 높은 등급 (설계 4장: 1~2 일반·고급 … 15 영원·신성)",
		function()
			local prevTop = 0
			for _, b in Biomes.list do
				local sum, top = 0, 0
				for rarityId, w in EggSpawn.BIOME_RARITY_WEIGHTS[b.id] do
					sum += w
					T.truthy(Rarities.get(rarityId), rarityId)
					if w > 0 then
						top = math.max(top, Rarities.order(rarityId))
					end
				end
				T.eq(sum, 100, b.id)
				T.truthy(top >= prevTop, b.id .. " 가장 높은 등급이 내려가지 않음")
				prevTop = top
			end
			T.eq(EggSpawn.BIOME_RARITY_WEIGHTS.forest.common, 60)
			T.eq(
				EggSpawn.BIOME_RARITY_WEIGHTS.haunted_castle.super_ultradivine,
				0,
				"슈퍼 울트라디바인은 공지 씨앗으로만"
			)
		end
	)

	T.test("특별 씨앗: 공지 씨앗 4종은 둥지 풀 밖, 사쿠라 씨앗 2종은 벚꽃 구역", function()
		for _, entry in EggSpawn.EXTRA_SPECIALS do
			local p = Plants.get(entry.petId)
			T.truthy(p, entry.petId)
			T.eq(p.source, "special", entry.petId)
			T.truthy(entry.chance > 0 and entry.chance < 1, entry.petId)
		end
		T.eq(#EggSpawn.EXTRA_SPECIALS, 4)
		local chanceSum = 0
		for _, entry in Config.SAKURA_SEEDS do
			local p = Plants.get(entry.plantId)
			T.truthy(p, entry.plantId)
			T.eq(p.source, "sakura")
			T.eq(p.biome, "cherry_blossom")
			chanceSum += entry.chance
		end
		T.near(chanceSum, 1, 1e-12)
		T.eq(Plants.seedName("blossom_fairy"), "벚꽃 씨앗")
		T.eq(Plants.seedName("spirit_blossom"), "정령 벚꽃 씨앗")
		T.eq(Plants.seedName("puppy_grass"), "강아지풀 씨앗")
		T.eq(Plants.seedName("없는것"), "씨앗")
	end)

	T.test("슈퍼 울트라디바인: 유령 성에만, 특별 추첨 0.5% (하루 약 1~2개)", function()
		local n = 0
		for _, p in Plants.list do
			if p.rarity == "super_ultradivine" then
				n += 1
				T.eq(p.biome, "haunted_castle", p.id)
			end
		end
		T.eq(n, 2)
		local chance = EggSpawn.SPECIAL_CHANCE_PER_RESET.super_ultradivine
		local cycle = Config.DAY_SECONDS + Config.NIGHT_SECONDS + Config.INTERMISSION_SECONDS
		local perDay = 86400 / cycle * chance
		T.truthy(perDay >= 1 and perDay <= 2, "하루 " .. perDay .. "개")
	end)

	T.test("크기 확률 합 100, 돌연변이 6종 (자연 3 + 먹이기 원소 3)", function()
		local sum = 0
		for _, s in Sizes.list do
			sum += s.chance
		end
		T.eq(sum, 100)
		T.eq(#Mutations.list, 6)
		T.eq(Mutations.get("silver").naturalChance, 0.05)
		T.eq(Mutations.get("golden").naturalChance, 0.02)
		T.eq(Mutations.get("rainbow").naturalChance, 0.005)
		T.eq(Mutations.get("golden").name, "황금")
		T.eq(Mutations.get("rainbow").name, "무지개")
		T.eq(Mutations.get("frozen").name, "얼음")
		T.eq(Mutations.get("burning").name, "불")
		T.eq(Mutations.get("bloom"), nil, "블룸은 6판에서 없앰 (사쿠라 씨앗으로)")
		T.eq(#Mutations.feed, 5, "먹이기로 얻는 것: 황금·무지개·얼음·불·번개")
	end)

	T.test("업그레이드 표: 정원 11, 러닝머신 20 (6판: 최대 1초 1M), 트레일 11", function()
		T.eq(#Upgrades.Pen, 11)
		T.eq(Upgrades.Pen[1].slots, 7)
		T.eq(Upgrades.Pen[11].slots, 18)
		T.eq(Upgrades.Pen[11].cost, 5e15)
		T.eq(#Upgrades.Treadmill, 20)
		T.eq(Upgrades.TREADMILL_MAX_LEVEL, 20)
		T.eq(Upgrades.Treadmill[10].perStep, 2000)
		T.eq(Upgrades.Treadmill[20].perStep, 250000)
		T.eq(Upgrades.Treadmill[1].cost, 1000)
		for i = 2, #Upgrades.Treadmill do
			T.truthy(Upgrades.Treadmill[i].cost > Upgrades.Treadmill[i - 1].cost, "러닝머신 비용 증가 " .. i)
			T.truthy(Upgrades.Treadmill[i].perStep > Upgrades.Treadmill[i - 1].perStep, "걸음당 속도 증가 " .. i)
			T.eq(Upgrades.Treadmill[i].level, i)
		end
		T.eq(#Upgrades.Trails, 11)
		T.eq(Upgrades.getTrail("moonbloom").multiplier, 20)
		for i = 2, #Upgrades.Pen do
			T.truthy(Upgrades.Pen[i].cost > Upgrades.Pen[i - 1].cost, "pen cost 증가 " .. i)
		end
	end)

	T.test(
		"Config 6판: 성장 단계 4개(0·25·60·100%), 열매 최대 5, 건너뛰기 10코인/분 × 등급 배수 1…500",
		function()
			local stages = Config.GROWTH_STAGES
			T.eq(#stages, 4)
			T.eq(stages[1].id, "sprout")
			T.eq(stages[2].from, 0.25)
			T.eq(stages[3].from, 0.60)
			T.eq(stages[4].id, "adult")
			T.eq(stages[4].from, 1)
			T.eq(Config.FRUIT_MAX_PER_PLANT, 5)
			T.eq(Config.SKIP_COINS_PER_MINUTE, 10)
			T.eq(Config.SKIP_RARITY_MULTIPLIER.common, 1)
			T.eq(Config.SKIP_RARITY_MULTIPLIER.super_ultradivine, 500)
			local prev = 0
			for _, r in Rarities.list do
				local m = Config.SKIP_RARITY_MULTIPLIER[r.id]
				T.truthy(m and m > prev, r.id .. " 배수 증가")
				prev = m
				T.truthy(Config.SAKURA_OFFER_CRYSTALS[r.id] ~= nil, r.id .. " 크리스탈")
			end
			T.eq(Config.NIGHT_GROWTH_MULTIPLIER, 30)
			T.eq(Config.PLANT_SELL_FRUIT_MULTIPLIER, 20)
			T.eq(Config.SCHEMA_VERSION, 6)
		end
	)

	T.test("도감 보상: 코인 = 열매 값 × 10, 속도는 등급표 (숲 배율 1)", function()
		local forest = Biomes.get("forest").recommendedSpeed
		local daisy = Plants.get("sprout_daisy")
		local r = Index.reward(daisy.rarity, daisy.fruitValue, forest)
		T.eq(r.speed, 420)
		T.eq(r.money, 100)
		local oak = Plants.get("owl_oak")
		local r2 = Index.reward(oak.rarity, oak.fruitValue, forest)
		T.eq(r2.speed, 620)
		T.eq(r2.money, 1800)
		for _, rarity in Rarities.list do
			T.truthy(Index.RARITY_SPEED[rarity.id] ~= nil, rarity.id)
		end
	end)

	T.test("도감 속도 보상: 뒤 구역은 (추천 속도/3600)^0.8 배 (정비례보다 느리게)", function()
		T.eq(Index.SPEED_BIOME_EXPONENT, 0.8)
		local prehistoric = Biomes.get("prehistoric").recommendedSpeed -- 18M → 배율 5000
		local fern = Plants.get("fossil_fern")
		local reward = Index.reward(fern.rarity, fern.fruitValue, prehistoric)
		T.eq(reward.speed, math.floor(800 * 5000 ^ 0.8 + 0.5))
		T.eq(reward.money, fern.fruitValue * 10, "코인 보상은 구역과 상관없음")
		T.eq(Index.reward("epic", 320, Biomes.get("lake").recommendedSpeed).speed, 800)
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
