--!nocheck
--[[
	J 시리즈 — 사장님 2026-11-10 "마지막 등급 해커 글리치는 마지막 지역에서만 나오게" (처음 0.00012% → 곧바로 0.0001% = 0.000001 로 다시 정함) 구멍 찾기
	본부장이 바꾼 규칙:
	  - EggSpawn.BIOME_RARITY_WEIGHTS: 해커 글리치를 보통 둥지 추첨에서 뺌 (18 {개발자 40 · 울트라디바인 60} · 19 {40 · 60} ·
	      20 {25 · 75} · 21 {울트라디바인 100})
	  - EggSpawn.SPECIAL_ONLY_BIOME = { hacker_glitch = "rainbow_sky" } — 이 등급의 초기화 특별 추첨은 그 구역에서만
	  - EggRoll.rollSpecials: SPECIAL_ONLY_BIOME[등급] 이 있고 지금 구역이 아니면 그 등급 후보를 비움 (확률은 SPECIAL_CHANCE_PER_RESET.hacker_glitch = 0.000001 = 0.0001%)
	기준 값(해커 글리치 확률 · 다른 등급 확률 · 마지막 구역 id · 마지막 구역의 해커 글리치 식물 3종)은 코드를 보지 않고 이 파일에 따로 적음.

	  J1 21구역 전부 보통 추첨 33만 번 → 해커 글리치 0번 (구역마다 1만 5천 번, 천사&악마는 두 쪽 다)
	  J2 rollSpecials 를 모든 구역 · 모든 난수 경계로: 해커 글리치는 rainbow_sky 에서만, 난수 < 0.000001 일 때만 (그리고 3종이 다 나옴)
	  J3 SPECIAL_ONLY_BIOME 의 구역 = 진짜 마지막 구역 (Biomes · MapLayout) · 그 구역에 해커 글리치 식물이 있어 추첨이 실제로 가능
	  J4 다른 등급 특별 추첨 확률은 안 바뀜 (표 값 · 모든 구역 · 경계)
	  J5 18~20구역 해커 글리치 식물 6종은 풀에 그대로지만 어떤 추첨으로도 안 나옴 (확률 0, 특별 추첨 구역마다 5만 번)
]]

return function(T, Loader)
	local S = "ReplicatedStorage/Shared/"
	local Biomes = Loader.require(S .. "Data/Biomes")
	local Plants = Loader.require(S .. "Data/Plants")
	local EggSpawn = Loader.require(S .. "Data/EggSpawn")
	local MapLayout = Loader.require(S .. "Data/MapLayout")
	local EggRoll = Loader.require(S .. "EggRoll")

	-- 사장님 값 (코드와 따로)
	local GLITCH = "hacker_glitch"
	local LAST_BIOME = "rainbow_sky"
	local GLITCH_CHANCE = 0.000001 -- 0.0001% (사장님 2026-11-10, 옛 0.00012% 는 폐기)
	local LAST_GLITCH_PLANTS = { "thundercloud_mushroom", "rainbow_crown_tree", "final_boss_bloom" }
	local OLD_GLITCH_PLANTS = { -- 18~20구역 (둥지 풀에는 남아 있지만 아무 데서도 안 나옴)
		bug_dimension = { "glitch_hacker_bloom", "static_world_tree" },
		robot_factory = { "supercomputer_tree", "overclock_rose" },
		clock_tower = { "time_travel_tree", "frozen_clock_lotus" },
	}
	-- 7판 그대로인 나머지 등급 특별 추첨 확률 (표 값은 바뀌면 안 됨)
	local OTHER_CHANCE = {
		ultradivine = 0.01,
		developer = 0.01,
		original = 0.01,
		hacker = 0.01,
		super = 0.01,
		divine = 0.002,
		eternity = 0.02,
		secret = 0.08,
	}

	local function sidesOf(b)
		return b.sides or { "none" }
	end

	local function realSide(side)
		return if side == "none" then nil else side
	end

	------------------------------------------------------------------
	T.suite("J 시리즈: 해커 글리치 = 마지막 구역 특별 추첨만 (사장님 2026-11-10, 0.0001%)")

	T.test(
		"J1 보통 둥지 추첨 33만 번 (21구역 전부, 구역마다 1만 5천 번 · 천사&악마는 두 쪽 다): 해커 글리치 0번, 나온 식물은 전부 그 구역 풀 안",
		function()
			T.eq(#Biomes.list, 21)
			local total, perBiome = 0, 15000
			for bi, b in Biomes.list do
				for si, side in sidesOf(b) do
					local rand = T.rng(20261110 + bi * 101 + si)
					local pool = {}
					for _, p in EggRoll.nestPool(b.id, realSide(side)) do
						pool[p.id] = true
					end
					local glitch = 0
					for _ = 1, perBiome do
						local pet = EggRoll.rollNestPet(b.id, realSide(side), rand)
						T.truthy(pet ~= nil, b.id .. " 추첨 결과")
						T.truthy(pool[pet.id], b.id .. " 풀 밖 " .. pet.id)
						if pet.rarity == GLITCH then
							glitch += 1
						end
						total += 1
					end
					T.eq(glitch, 0, b.id .. " " .. side .. " 보통 추첨에서 해커 글리치 " .. glitch .. "번")
				end
			end
			T.truthy(total >= 300000, "추첨 " .. total .. "번")
			-- 표에도 없고 가중치도 0
			for _, b in Biomes.list do
				T.eq(EggSpawn.BIOME_RARITY_WEIGHTS[b.id][GLITCH], nil, b.id .. " 표에 해커 글리치 없음")
				T.eq(EggRoll.rarityWeight(b.id, GLITCH), 0, b.id .. " 가중치 0")
				for _, side in sidesOf(b) do
					for id, odds in EggRoll.nestOdds(b.id, realSide(side)) do
						if Plants.get(id).rarity == GLITCH then
							T.eq(odds, 0, id .. " 보통 추첨 확률 0")
						end
					end
				end
			end
		end
	)

	T.test(
		"J2 rollSpecials 를 모든 구역 × 모든 난수 경계로: 해커 글리치는 rainbow_sky 에서만, 난수 < 0.000001 일 때만 (경계 자체는 안 나옴) · 한 번 뽑히면 3종이 다 나올 수 있음",
		function()
			local values = {
				0,
				1e-15,
				GLITCH_CHANCE / 2,
				GLITCH_CHANCE - 1e-12, -- 경계 바로 아래
				GLITCH_CHANCE, -- 경계 (rand() < chance 라서 안 나옴)
				GLITCH_CHANCE + 1e-12,
				0.0000011,
				0.0001,
				0.001,
				0.0099,
				0.01,
				0.05,
				0.5,
				0.99,
				0.999999,
			}
			for _, b in Biomes.list do
				for _, side in sidesOf(b) do
					for _, v in values do
						-- (a) 모든 호출이 같은 값
						local specials = EggRoll.rollSpecials(b.id, realSide(side), T.constant(v))
						local hasGlitch = false
						for _, pet in specials do
							if pet.rarity == GLITCH then
								hasGlitch = true
							end
						end
						local expected = b.id == LAST_BIOME and v < GLITCH_CHANCE
						T.eq(hasGlitch, expected, b.id .. " 난수 " .. v .. " 해커 글리치")
						-- (b) 첫 난수만 v, 나머지는 0.99 (해커 글리치 확률 굴림이 맨 먼저라 첫 호출이 그것)
						local calls = 0
						local specials2 = EggRoll.rollSpecials(b.id, realSide(side), function()
							calls += 1
							return if calls == 1 then v else 0.99
						end)
						local first = specials2[1]
						T.eq(
							first ~= nil and first.rarity == GLITCH,
							expected,
							b.id .. " 첫 난수 " .. v .. " 해커 글리치가 맨 앞"
						)
						-- 마지막 구역이 아니면 첫 난수가 어떻든 해커 글리치 후보를 굴리지도 않음 (첫 호출은 다음 등급 몫)
						if b.id ~= LAST_BIOME then
							for _, pet in specials2 do
								T.truthy(pet.rarity ~= GLITCH, b.id .. " 해커 글리치")
							end
						end
					end
				end
			end
			-- 마지막 구역에서 뽑히면 3종 중 하나 (둘째 난수 = 식물 고르기), 3종이 다 나올 수 있음
			local seen = {}
			for _, pick in { 0, 0.34, 0.67, 0.9999999 } do
				local calls = 0
				local specials = EggRoll.rollSpecials(LAST_BIOME, nil, function()
					calls += 1
					if calls == 1 then
						return 0 -- 해커 글리치 확률 굴림: 나옴
					elseif calls == 2 then
						return pick -- 식물 고르기
					end
					return 0.99
				end)
				T.eq(#specials, 1, "해커 글리치 한 번")
				T.eq(specials[1].rarity, GLITCH)
				T.eq(specials[1].biome, LAST_BIOME)
				seen[specials[1].id] = true
			end
			for _, id in LAST_GLITCH_PLANTS do
				T.truthy(seen[id], id .. " 가 뽑힐 수 있음")
			end
			local n = 0
			for _ in seen do
				n += 1
			end
			T.eq(n, #LAST_GLITCH_PLANTS, "해커 글리치 후보는 3종뿐")
			-- 무작위 20만 번 (구역마다 1만 번 + rainbow_sky 20만 번): 마지막 구역이 아니면 한 번도 안 나옴
			local rand = T.rng(1110)
			for _, b in Biomes.list do
				if b.id ~= LAST_BIOME then
					for _ = 1, 10000 do
						for _, pet in EggRoll.rollSpecials(b.id, realSide(sidesOf(b)[1]), rand) do
							T.truthy(pet.rarity ~= GLITCH, b.id .. " 에서 해커 글리치")
						end
					end
				end
			end
		end
	)

	T.test(
		"J3 SPECIAL_ONLY_BIOME 의 구역 = 진짜 마지막 구역 (Biomes 마지막 · MapLayout 마지막 · 맵 끝 바로 앞 zoneAt) · 그 구역에 해커 글리치 식물 3종이 있어 추첨이 실제로 가능",
		function()
			local lastBiome = Biomes.list[#Biomes.list]
			T.eq(lastBiome.id, LAST_BIOME, "Biomes 마지막")
			T.eq(lastBiome.order, #Biomes.list)
			T.eq(lastBiome.order, MapLayout.BIOME_COUNT)
			T.eq(MapLayout.zoneAt(MapLayout.MAP_END_Z - 0.01), LAST_BIOME, "맵 끝 바로 앞 구역")
			T.eq(
				MapLayout.zoneAt(MapLayout.biomes[MapLayout.BIOME_COUNT].zMin),
				LAST_BIOME,
				"MapLayout 마지막 구역"
			)
			-- 표: 이 등급 하나뿐이고, 그 구역이 마지막 구역
			local count = 0
			for rarityId, biomeId in EggSpawn.SPECIAL_ONLY_BIOME do
				count += 1
				T.eq(biomeId, lastBiome.id, rarityId .. " 의 구역 = 마지막 구역")
				T.truthy(Biomes.get(biomeId) ~= nil, "진짜 있는 구역")
				T.truthy(
					table.find(EggSpawn.SPECIAL_RARITIES, rarityId) ~= nil,
					rarityId .. " 는 특별 추첨 등급"
				)
			end
			T.eq(count, 1, "구역이 정해진 등급은 해커 글리치 하나뿐")
			T.eq(EggSpawn.SPECIAL_ONLY_BIOME[GLITCH], lastBiome.id)
			-- 해커 글리치는 가장 높은 등급 (마지막 등급)
			local Rarities = Loader.require(S .. "Data/Rarities")
			T.eq(Rarities.TOP, GLITCH)
			T.eq(EggSpawn.SPECIAL_RARITIES[1], GLITCH, "가장 희귀한 것부터 굴림")
			-- 그 구역 풀에 해커 글리치 식물이 3종 (정확히 이 3종) → 특별 추첨이 실제로 돌 수 있음 (없으면 영영 안 나옴)
			local inPool = {}
			for _, p in EggRoll.nestPool(lastBiome.id, nil) do
				if p.rarity == GLITCH then
					inPool[p.id] = true
				end
			end
			for _, id in LAST_GLITCH_PLANTS do
				T.truthy(inPool[id], id .. " 가 마지막 구역 풀에 있음")
			end
			local n = 0
			for _ in inPool do
				n += 1
			end
			T.eq(n, 3)
			-- 확률 상수: 0.0001% + 하루 약 0.00029개 (서버 하나에서 약 9년에 한 번)
			T.eq(EggSpawn.SPECIAL_CHANCE_PER_RESET[GLITCH], GLITCH_CHANCE)
			local Config = Loader.require(S .. "Data/Config")
			local cycle = Config.DAY_SECONDS + Config.NIGHT_SECONDS + Config.INTERMISSION_SECONDS
			local perDay = 86400 / cycle * GLITCH_CHANCE
			T.near(perDay, 0.00029, 0.00002, "하루 " .. perDay)
			local years = 1 / perDay / 365
			T.truthy(years > 8 and years < 10.5, "약 9년에 한 번: " .. years)
		end
	)

	T.test(
		"J4 다른 등급 특별 추첨 확률은 안 바뀜: 표 값(울트라디바인·개발자·오리지널·해커·슈퍼 1% · 신성 0.2% · 영원 2% · 비밀 8%) + 모든 구역에서 경계(바로 아래 나옴 / 같으면 안 나옴)",
		function()
			for id, chance in OTHER_CHANCE do
				T.eq(EggSpawn.SPECIAL_CHANCE_PER_RESET[id], chance, id .. " 표 값")
			end
			-- 표에는 이 9개(해커 글리치 + 8)만
			local count = 0
			for _ in EggSpawn.SPECIAL_CHANCE_PER_RESET do
				count += 1
			end
			T.eq(count, 9)
			T.eq(#EggSpawn.SPECIAL_RARITIES, 9)
			T.eq(EggSpawn.MAX_SPECIALS_PER_BIOME, 2)
			-- 모든 구역: 그 구역에서 굴려지는 (후보가 있는) 등급의 순서를 따라, 그 등급 차례의 난수 하나만 바꿔서 경계 확인
			local checked = 0
			for _, b in Biomes.list do
				for _, side in sidesOf(b) do
					local pool = EggRoll.nestPool(b.id, realSide(side))
					local rolled = {} -- 이 구역에서 굴려지는 등급 (SPECIAL_RARITIES 순서)
					for _, rarityId in EggSpawn.SPECIAL_RARITIES do
						local has = false
						for _, p in pool do
							if p.rarity == rarityId then
								has = true
							end
						end
						local onlyBiome = EggSpawn.SPECIAL_ONLY_BIOME[rarityId]
						if has and (onlyBiome == nil or onlyBiome == b.id) then
							table.insert(rolled, rarityId)
						end
					end
					for k, rarityId in rolled do
						if rarityId ~= GLITCH then
							local chance = OTHER_CHANCE[rarityId]
							-- 앞 등급 차례는 0.99(안 나옴), k번째 호출만 v (나오면 식물 고르기 난수도 0.99 라서 후보 중 뒤쪽)
							local function rollWith(v)
								local calls = 0
								return EggRoll.rollSpecials(b.id, realSide(side), function()
									calls += 1
									return if calls == k then v else 0.99
								end)
							end
							local hit = rollWith(chance - 1e-9)
							T.eq(#hit, 1, b.id .. " " .. rarityId .. " 경계 아래: 1개")
							T.eq(hit[1].rarity, rarityId, b.id .. " " .. rarityId .. " 경계 아래")
							T.eq(#rollWith(chance), 0, b.id .. " " .. rarityId .. " 경계(같음)는 안 나옴")
							T.eq(#rollWith(chance + 1e-9), 0, b.id .. " " .. rarityId .. " 경계 위")
							T.eq(#rollWith(0.99), 0, b.id .. " " .. rarityId .. " 0.99")
							checked += 1
						end
					end
				end
			end
			T.truthy(checked >= 20, "경계 확인 " .. checked .. "곳")
			-- 해커 글리치가 빠진 구역에서도 다른 등급은 최대 2개 (난수 0)
			for _, b in Biomes.list do
				local specials = EggRoll.rollSpecials(b.id, realSide(sidesOf(b)[1]), T.constant(0))
				T.truthy(#specials <= EggSpawn.MAX_SPECIALS_PER_BIOME, b.id)
			end
			-- 통계: 다른 구역의 울트라디바인 1% (개발자의 방 20만 번)
			local rand = T.rng(5555)
			local hits, n = 0, 200000
			for _ = 1, n do
				for _, pet in EggRoll.rollSpecials("developer_room", nil, rand) do
					if pet.rarity == "ultradivine" then
						hits += 1
					end
				end
			end
			T.near(hits / n, 0.01, 0.002, "개발자의 방 울트라디바인 특별 추첨 1%")
		end
	)

	T.test(
		"J5 18~20구역 해커 글리치 식물 6종은 둥지 풀에 그대로 (구역마다 8종 유지) 하지만 보통 추첨 확률 0 · 특별 추첨 5만 번씩에도 0번 · 아무 구역 풀에서든 뽑는 길은 마지막 구역 3종뿐",
		function()
			local rand = T.rng(18192021)
			for biomeId, ids in OLD_GLITCH_PLANTS do
				local pool = EggRoll.nestPool(biomeId, nil)
				T.eq(#pool, 8, biomeId .. " 풀 8종 그대로")
				local odds = EggRoll.nestOdds(biomeId, nil)
				local sum = 0
				for _, p in pool do
					sum += odds[p.id]
				end
				T.near(sum, 1, 1e-9, biomeId .. " 확률 합 1")
				for _, id in ids do
					local plant = Plants.get(id)
					T.eq(plant.biome, biomeId, id)
					T.eq(plant.rarity, GLITCH, id)
					T.eq(plant.source, "nest", id)
					T.eq(odds[id], 0, id .. " 보통 추첨 확률 0")
					T.eq(EggRoll.nestWeight(plant, nil), 0, id .. " nestWeight 0")
				end
				local hits = 0
				for _ = 1, 50000 do
					for _, pet in EggRoll.rollSpecials(biomeId, nil, rand) do
						if pet.rarity == GLITCH then
							hits += 1
						end
					end
				end
				T.eq(hits, 0, biomeId .. " 특별 추첨 5만 번에서 해커 글리치 " .. hits)
			end
			-- 모든 식물 중 보통 추첨 확률이 0 보다 큰 해커 글리치 식물은 하나도 없음
			for _, p in Plants.list do
				if p.rarity == GLITCH then
					for _, side in { "light", "dark" } do
						T.eq(EggRoll.nestWeight(p, side), 0, p.id .. " nestWeight")
					end
				end
			end
			-- 해커 글리치 식물은 9종 (6 + 3), 전부 둥지 풀 식물 (사쿠라·공지 씨앗이 아님)
			local total = 0
			for _, p in Plants.list do
				if p.rarity == GLITCH then
					total += 1
					T.eq(p.source, "nest", p.id)
				end
			end
			T.eq(total, 9)
			-- 공지 씨앗(EXTRA_SPECIALS)과 사쿠라 뽑기(SAKURA_SEEDS)에 해커 글리치는 없음
			for _, entry in EggSpawn.EXTRA_SPECIALS do
				T.truthy(Plants.get(entry.petId).rarity ~= GLITCH, entry.petId .. " 공지 씨앗")
			end
			local Config = Loader.require(S .. "Data/Config")
			for _, entry in Config.SAKURA_SEEDS do
				T.truthy(Plants.get(entry.plantId).rarity ~= GLITCH, entry.plantId .. " 사쿠라 뽑기")
			end
		end
	)
end
