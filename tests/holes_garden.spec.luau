--!nocheck
--[[
	6판 주임 검수 (구멍 찾기): 새 Remote 11개를 아무 값이나 던져 보는 무작위 시험 (씨앗 고정이라 매번 같음)
	- 두 사람(나 A · 남 B)이 한 서버에. A 가 온갖 값(남의 uid, NaN, "all", 거대 숫자, 표, 아주 긴 글…)을 온갖 자리에서
	  PickFruit · SellFruits · FeedFruit · SkipGrowth · SellPlant · SakuraOffer · SakuraDraw · PlaceEgg ·
	  PickUpPlacedEgg · ClaimIndexReward 로 보내고, 낮/밤·시간이 흐름.
	- 매번 확인: 코인 유한·0 이상·상한 이하 / 열매 가방 ≤ 300 · 칸마다 개수 정수 · 값 유한 / 식물 열매 0~5 정수 /
	  정원 칸 수 안 넘음 / uid 겹침 없음 / 크리스탈 정수 / 서버 warn 없음 / 돈은 팔기·도감으로만 늘고, 건너뛰기는 정확히 가격만큼만 빠짐 /
	  B(남)의 코인·열매 가방·씨앗 가방·크리스탈·돌연변이는 A 가 못 바꿈
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function world()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.Plants = H.shared("Data/Plants")
		w.FruitRules = H.shared("FruitRules")
		w.GardenRules = H.shared("GardenRules")
		w.EggPlacement = H.shared("EggPlacement")
		w.DataSchema = H.server("Logic/DataSchema")
		w.BaseService = H.server("Services/BaseService")
		w.PetService = H.server("Services/PetService")
		w.FruitService = H.server("Services/FruitService")
		w.SakuraService = H.server("Services/SakuraService")
		w.IndexService = H.server("Services/IndexService")
		w.A = H.newPlayer(2001, "Fuzzer")
		w.sessionA, w.dataA = H.login(w.A)
		w.sessionA.plotIndex = 1
		w.B = H.newPlayer(2002, "Victim")
		w.sessionB, w.dataB = H.login(w.B)
		w.sessionB.plotIndex = 2
		w.dataA.penLevel = H.shared("Data/Upgrades").PEN_MAX_LEVEL -- 정원 18칸
		w.dataB.penLevel = w.dataA.penLevel
		w.dataB.nextUid = 700 -- uid 가 안 겹치게
		w.BaseService.start()
		w.PetService.start()
		w.FruitService.start()
		w.SakuraService.start()
		w.IndexService.start()
		return w
	end

	local function addPlant(w, player, data, petId, opts)
		opts = opts or {}
		local taken = {}
		for _, r in data.pets do
			table.insert(taken, { x = r.x, z = r.z, size = r.size })
		end
		for _, r in data.incubators do
			table.insert(taken, { x = r.x, z = r.z, size = r.size })
		end
		local size = opts.size or "normal"
		local spot = w.EggPlacement.firstFreeGrid(size, taken)
		local record = {
			uid = w.DataSchema.newUid(data, "p"),
			petId = petId,
			size = size,
			mutations = opts.mutations or {},
			x = spot.x,
			z = spot.z,
			fruits = opts.fruits or 0,
			fruitProgress = 0,
		}
		assert(w.PetService.addPlant(player, record), "addPlant 실패")
		return record
	end

	local function plantSeed(w, player, data, plotIndex, petId)
		local x, z = w.H.plotSpot(plotIndex)
		w.H.spawn(player, x, 3, z)
		w.BaseService.grantEgg(player, petId, "normal", {}, "sakura")
		local egg = data.eggs[#data.eggs]
		local spots = {}
		for _, r in data.incubators do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		for _, r in data.pets do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		local l = w.EggPlacement.firstFreeGrid(egg.size, spots)
		local spot = w.H.MapLayout.toWorld(plotIndex, l.x, l.z)
		assert(w.BaseService.placeEgg(player, egg.uid, spot.x, spot.z), "plantSeed 실패")
	end

	local function finite(n)
		return typeof(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
	end

	local function isInt(n)
		return finite(n) and n == math.floor(n)
	end

	-- B 의 "A 가 못 바꾸는" 것들을 글로 찍어 둠
	local function lockedOf(w)
		local d = w.dataB
		local parts = { tostring(d.money), tostring(d.sakuraCrystals), tostring(#d.eggs) }
		local names = {}
		for id, stack in d.fruits do
			table.insert(names, id .. ":" .. stack.count .. ":" .. stack.value)
		end
		table.sort(names)
		table.insert(parts, table.concat(names, ","))
		local muts = {}
		for _, r in d.pets do
			if w.bStart[r.uid] then -- 씨앗이 자라서 새로 성체가 된 것은 빼고 처음부터 있던 것만
				table.insert(muts, r.uid .. "=" .. table.concat(r.mutations, "+") .. "/" .. r.size)
			end
		end
		table.sort(muts)
		table.insert(parts, table.concat(muts, ","))
		return table.concat(parts, "|")
	end

	-- A 의 눈에 띄는 상태를 한 줄 글로 (거리 문 시험용)
	local function sigOf(w)
		local d = w.dataA
		local fruits = 0
		for _, r in d.pets do
			fruits += r.fruits
		end
		return table.concat({
			tostring(d.money),
			tostring(d.sakuraCrystals),
			#d.pets,
			#d.eggs,
			w.FruitRules.bagCount(d.fruits),
			fruits,
			tostring(w.FruitRules.bagValue(d.fruits)),
		}, "|")
	end

	local function checkInvariants(w, label)
		local Config = w.Config
		for who, data in { A = w.dataA, B = w.dataB } do
			local tag = who .. " " .. label
			T.truthy(
				finite(data.money) and data.money >= 0 and data.money <= Config.MONEY_MAX,
				tag .. ": 코인 " .. tostring(data.money)
			)
			T.truthy(finite(data.speed) and data.speed >= 0, tag .. ": 속도 " .. tostring(data.speed))
			local total = 0
			for id, stack in data.fruits do
				T.truthy(w.Plants.get(id) ~= nil, tag .. ": 모르는 열매 칸 " .. tostring(id))
				T.truthy(isInt(stack.count) and stack.count >= 1, tag .. ": 열매 개수 " .. tostring(stack.count))
				T.truthy(finite(stack.value) and stack.value >= 0, tag .. ": 열매 값 " .. tostring(stack.value))
				total += stack.count
			end
			T.truthy(total <= Config.FRUIT_BAG_MAX, tag .. ": 열매 가방 " .. total)
			T.truthy(#data.eggs <= Config.EGG_INVENTORY_MAX, tag .. ": 씨앗 가방 " .. #data.eggs)
			T.truthy(#data.pets + #data.incubators <= w.GardenRules.capacity(data.penLevel), tag .. ": 정원 칸")
			T.truthy(
				isInt(data.sakuraCrystals)
					and data.sakuraCrystals >= 0
					and data.sakuraCrystals <= Config.SAKURA_CRYSTAL_MAX,
				tag .. ": 크리스탈 " .. tostring(data.sakuraCrystals)
			)
			local seen = {}
			for _, r in data.pets do
				T.truthy(
					isInt(r.fruits) and r.fruits >= 0 and r.fruits <= Config.FRUIT_MAX_PER_PLANT,
					tag .. ": 식물 열매 " .. tostring(r.fruits)
				)
				T.truthy(
					finite(r.fruitProgress) and r.fruitProgress >= 0,
					tag .. ": 다음 열매 " .. tostring(r.fruitProgress)
				)
				T.truthy(not seen[r.uid], tag .. ": uid 겹침 " .. r.uid)
				seen[r.uid] = true
			end
			for _, r in data.incubators do
				T.truthy(
					finite(r.progress) and r.progress >= 0 and r.progress <= r.required,
					tag .. ": 진행도 " .. tostring(r.progress)
				)
				T.truthy(not seen[r.uid], tag .. ": uid 겹침 " .. r.uid)
				seen[r.uid] = true
			end
			for _, r in data.eggs do
				T.truthy(not seen[r.uid], tag .. ": uid 겹침 " .. r.uid)
				seen[r.uid] = true
			end
		end
		T.eq(#w.H.warnings, 0, label .. ": 서버 warn " .. tostring(w.H.warnings[1]))
	end

	T.suite("6판 주임 검수: 새 Remote 무작위 시험")

	T.test(
		"A 가 온갖 값을 던져도 코인·가방·정원이 안 깨지고 B 것은 그대로 (1500번)",
		function()
			local w = world()
			local H = w.H
			local rand = T.rng(60601)
			local function pick(list)
				return list[math.floor(rand() * #list) + 1]
			end

			-- A: 성체 6 (열매 달림) + 자라는 씨앗 4 + 씨앗 가방 + 열매 가방
			for _, id in { "sprout_daisy", "owl_oak", "crystal_snowdrop", "rune_rose", "puppy_grass", "pharaoh_palm" } do
				if w.Plants.get(id) then
					addPlant(w, w.A, w.dataA, id, { fruits = 3 })
				end
			end
			for _, id in { "sprout_daisy", "owl_oak", "yeti_cabbage", "whale_kelp" } do
				plantSeed(w, w.A, w.dataA, 1, id)
			end
			for _ = 1, 5 do
				w.BaseService.grantEgg(w.A, "sprout_daisy", "normal", {}, "sakura")
			end
			w.dataA.fruits.sprout_daisy = { count = 40, value = 400 }
			w.dataA.fruits.owl_oak = { count = 250, value = 45000 }
			w.dataA.fruits.crystal_snowdrop = { count = 5, value = 900 }
			w.dataA.money = 5000
			-- B: 성체 4 + 씨앗 3 + 열매 가방 + 코인 + 크리스탈
			for _, id in { "sprout_daisy", "owl_oak", "rune_rose", "crystal_snowdrop" } do
				addPlant(w, w.B, w.dataB, id, { fruits = 5 })
			end
			for _, id in { "sprout_daisy", "owl_oak", "whale_kelp" } do
				plantSeed(w, w.B, w.dataB, 2, id)
			end
			w.BaseService.grantEgg(w.B, "owl_oak", "normal", {}, "sakura")
			w.dataB.fruits.owl_oak = { count = 10, value = 1800 }
			w.dataB.money = 12345
			w.dataB.sakuraCrystals = 7
			H.clearSent()
			w.bStart = {}
			for _, r in w.dataB.pets do
				w.bStart[r.uid] = true
			end
			local lockedBefore = lockedOf(w)
			checkInvariants(w, "시작")

			local junk = {
				true,
				false,
				0,
				1,
				-1,
				0 / 0,
				math.huge,
				-math.huge,
				1e308,
				-1e308,
				2 ^ 53,
				0.5,
				"",
				"all",
				"half",
				"ALL",
				"all ",
				"p1",
				"i1",
				"e1",
				string.rep("x", 100),
				"__index",
				"../x",
				"한글",
				{},
				{ 1, 2 },
				{ all = true },
			}
			local function uidPool()
				local pool = {}
				for _, d in { w.dataA, w.dataB } do
					for _, r in d.pets do
						table.insert(pool, r.uid)
					end
					for _, r in d.incubators do
						table.insert(pool, r.uid)
					end
					for _, r in d.eggs do
						table.insert(pool, r.uid)
					end
				end
				return pool
			end
			local function arg(kind)
				local roll = rand()
				if kind == "mode" and roll < 0.75 then
					return pick({ "all", "half" })
				end
				if kind == "fruitId" and roll < 0.6 then
					return pick({ "sprout_daisy", "owl_oak", "crystal_snowdrop", "rune_rose", "chicken", "nope" })
				end
				if kind == "plantOrAll" and roll < 0.3 then
					return "all"
				end
				roll = rand()
				if roll < 0.55 then
					local pool = uidPool()
					if #pool > 0 then
						return pick(pool)
					end
				elseif roll < 0.62 then
					return nil
				end
				return pick(junk)
			end

			local remotes = {
				"PickFruit",
				"PickFruit",
				"SellFruits",
				"FeedFruit",
				"FeedFruit",
				"SkipGrowth",
				"SkipGrowth",
				"SellPlant",
				"SakuraOffer",
				"SakuraDraw",
				"PlaceEgg",
				"PickUpPlacedEgg",
				"ClaimIndexReward",
			}
			local penA = H.MapLayout.penRect(1)
			local stall = H.MapLayout.hubSpots.sellStall
			local forestX, forestZ = H.zoneSpot("forest")
			local spots = {
				{ (penA.xMin + penA.xMax) / 2, (penA.zMin + penA.zMax) / 2 },
				{ stall.x, stall.z },
				{ forestX, forestZ },
				{ penA.xMin - 15, penA.zMin }, -- 정원 가장자리 밖 15
			}
			local skips, sells = 0, 0
			for step = 1, 1500 do
				local at = pick(spots)
				H.spawn(w.A, at[1], 3, at[2])
				H.landmarks.nearName = if rand() < 0.5 then "SakuraIncubator" else nil
				if rand() < 0.08 then
					H.setPhase(if H.cycle.phase == "Night" then "Day" else "Night")
				end
				if rand() < 0.1 then
					w.dataA.money = pick({ 0, 5, 49, 50, 160, 1000, 100000, 1e12 })
				end
				if rand() < 0.05 then
					w.dataA.sakuraCrystals = pick({ 0, 9, 10, 19, 100 })
				end
				if step % 15 == 0 and #w.dataA.incubators < 4 and #w.dataA.pets + #w.dataA.incubators < 17 then
					if #w.dataA.eggs < 40 then
						plantSeed(
							w,
							w.A,
							w.dataA,
							1,
							pick({ "owl_oak", "rune_rose", "whale_kelp", "yeti_cabbage", "sprout_daisy" })
						)
						H.spawn(w.A, at[1], 3, at[2])
					end
				end
				H.advance(pick({ 0.3, 1, 2, 5, 15, 40, 90 }))
				local name = pick(remotes)
				local moneyBefore, bagBefore = w.dataA.money, w.FruitRules.bagValue(w.dataA.fruits)
				local expectCost = nil
				local expectSell = nil
				local a1, a2, a3
				if name == "PickFruit" then
					a1 = arg("plantOrAll")
				elseif name == "FeedFruit" then
					a1, a2 = arg("uid"), arg("fruitId")
				elseif name == "SkipGrowth" then
					a1, a2 = arg("uid"), arg("mode")
					if rand() < 0.7 and #w.dataA.incubators > 0 then
						a1 = pick(w.dataA.incubators).uid
						if rand() < 0.5 then
							w.dataA.money = pick({ 100, 5000, 1e7, 1e12 })
							moneyBefore = w.dataA.money
						end
					end
					for _, r in w.dataA.incubators do
						if r.uid == a1 and (a2 == "all" or a2 == "half") then
							expectCost = w.GardenRules.skipCost(r.petId, r.progress, r.required, a2)
						end
					end
				elseif name == "SellPlant" then
					a1 = arg("uid")
					for _, r in w.dataA.pets do
						if r.uid == a1 then
							expectSell = w.GardenRules.sellPrice(r)
						end
					end
				elseif name == "SakuraOffer" or name == "PickUpPlacedEgg" then
					a1 = arg("uid")
				elseif name == "PlaceEgg" then
					a1 = arg("uid")
					a2 = pick({ at[1], 0, 1e9, 0 / 0, "x", penA.xMin + 5 })
					a3 = pick({ at[2], 0, -1e9, penA.zMin + 5 })
				elseif name == "ClaimIndexReward" then
					a1 = arg("uid")
				end
				H.spawn(w.A, at[1], 3, at[2]) -- 밤이 되면 서버가 베이스로 옮기므로 부르기 직전에 다시 세움
				local sigBefore = sigOf(w)
				H.client(w.A, name, a1, a2, a3)
				-- 거리 문: 숲 한가운데에서는 정원·판매 가판대 일을 할 수 없고, 사쿠라 나무에서 멀면 바치기·뽑기를 할 수 없음
				local farFromGarden = at == spots[3]
				if farFromGarden and (name == "SellFruits" or name == "PickFruit" or name == "FeedFruit") then
					T.eq(sigOf(w), sigBefore, name .. " #" .. step .. ": 멀리서 됨")
				end
				if farFromGarden and name == "SellPlant" and H.landmarks.nearName == nil then
					T.eq(sigOf(w), sigBefore, name .. " #" .. step .. ": 멀리서 됨")
				end
				if H.landmarks.nearName == nil and (name == "SakuraOffer" or name == "SakuraDraw") then
					T.eq(sigOf(w), sigBefore, name .. " #" .. step .. ": 나무에서 멀리서 됨")
				end
				local label = name .. " #" .. step
				local delta = w.dataA.money - moneyBefore
				if name == "SellFruits" then
					T.truthy(
						delta <= bagBefore * 2 + 1e-6,
						label .. ": 열매 값보다 많이 받음 " .. delta .. " > " .. bagBefore
					)
					if delta > 0 then
						sells += 1
						T.eq(next(w.dataA.fruits), nil, label .. ": 팔았는데 가방에 열매가 남음")
					end
				elseif name == "SellPlant" then
					if delta > 0 then
						sells += 1
						T.truthy(
							expectSell ~= nil and (delta == expectSell or delta == expectSell * 2),
							label .. ": 성체 값이 다름 " .. delta .. " vs " .. tostring(expectSell)
						)
					else
						T.truthy(delta == 0, label .. ": 코인이 줄어듦")
					end
				elseif name == "ClaimIndexReward" then
					T.truthy(delta >= 0, label .. ": 코인이 줄어듦")
				elseif name == "SkipGrowth" then
					if delta ~= 0 then
						skips += 1
						T.truthy(
							expectCost ~= nil and -delta == expectCost,
							label .. ": 건너뛰기 값이 다름 " .. -delta .. " vs " .. tostring(expectCost)
						)
					end
				else
					T.truthy(delta == 0, label .. ": 돈이 바뀜 " .. delta)
				end
				checkInvariants(w, label)
				local lockedNow = lockedOf(w)
				if lockedNow ~= lockedBefore then
					-- B 의 정당한 변화(열매가 맺혀도 가방 칸은 안 변함 · 돌연변이도 안 변함) 외에는 없어야 함
					T.eq(
						lockedNow,
						lockedBefore,
						label
							.. ": B 의 것이 바뀜 (코인·열매 가방·씨앗 가방·크리스탈·돌연변이)"
					)
				end
			end
			T.truthy(sells > 5 and skips > 5, "시험이 너무 약함: 팔기 " .. sells .. " 건너뛰기 " .. skips)
			H.uninstall()
		end
	)

	T.test(
		"성장 시간 실측 (7판 성장 3배): 일반 표 10초 → 약 3.3초 · 비밀 표 24시간 → 낮 8시간 · 밤 30배면 16분 · 건너뛰기 가격 = 표",
		function()
			local w = world()
			local H = w.H
			local function lastSeed()
				return w.dataA.incubators[#w.dataA.incubators]
			end
			-- 낮: 일반 씨앗 표 10초 → 실제 약 3.3초 (서버 1초 틱)
			plantSeed(w, w.A, w.dataA, 1, "sprout_daisy")
			T.near(lastSeed().required, 10 / 3, 1e-9)
			H.advance(2.5)
			T.eq(#w.dataA.incubators, 1, "2초에는 아직 씨앗")
			H.advance(2)
			T.eq(#w.dataA.incubators, 0, "약 3.3초 뒤 성체 (4초 틱에)")
			T.eq(#w.dataA.pets, 1)
			-- 낮: 비밀 씨앗은 표 24시간 → 실제 8시간 (1시간 지나도 씨앗, 진행도는 정확히 3600)
			plantSeed(w, w.A, w.dataA, 1, "rune_rose")
			local secret = lastSeed()
			T.eq(secret.required, 28800)
			H.advance(3600)
			T.near(secret.progress, 3600, 2, "낮 1시간 = 성장 3600초")
			-- 건너뛰기 가격 = 남은 분 × 10 × 100 (남은 실제 480분 - 60분)
			local left = secret.required - secret.progress
			T.eq(
				w.GardenRules.skipCost("rune_rose", secret.progress, secret.required, "all"),
				math.ceil(left / 60 - 1e-9) * 10 * 100
			)
			T.eq(
				w.GardenRules.skipCost("rune_rose", secret.progress, secret.required, "all"),
				420 * 10 * 100,
				"7판: 남은 실제 420분"
			)
			-- 밤: 같은 비밀 씨앗이 30배 빨리 (남은 25,200초 → 840초 = 14분)
			H.setPhase("Night")
			T.eq(math.ceil(left / 30), 840)
			H.advance(math.ceil(left / 30) - 5)
			T.eq(#w.dataA.incubators, 1, "밤 14분에서 5초 모자라면 아직 씨앗")
			H.advance(10)
			T.eq(#w.dataA.incubators, 0, "밤 14분 + 몇 초 뒤 성체")
			T.eq(w.dataA.pets[#w.dataA.pets].petId, "rune_rose")
			T.eq(w.dataA.pets[#w.dataA.pets].fruits, w.Config.FRUITS_ON_ADULT)
			H.uninstall()
		end
	)
end
