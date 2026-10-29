--!nocheck
--[[
	7판 주임 검수 (구멍 찾기): 등급 16개 · 구역 18개 · 성장 3배 · 저장 스키마 7 · 무작위 요청 시험
	- 등급 표는 코드가 아니라 docs/SEED_GAME_DESIGN.md 11·12장 숫자를 이 파일에 따로 적어 두고 대조함
	- 15구역까지의 좌표는 6판(커밋 e07de8f) 코드로 뽑은 글 모양(해시 1089747796)과 같아야 함
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local fs = require("@lune/fs")
	local S = "ReplicatedStorage/Shared/"
	local Rarities = Loader.require(S .. "Data/Rarities")
	local Plants = Loader.require(S .. "Data/Plants")
	local Biomes = Loader.require(S .. "Data/Biomes")
	local Config = Loader.require(S .. "Data/Config")
	local EggSpawn = Loader.require(S .. "Data/EggSpawn")
	local Index = Loader.require(S .. "Data/Index")
	local MapLayout = Loader.require(S .. "Data/MapLayout")
	local Upgrades = Loader.require(S .. "Data/Upgrades")
	local Visuals = Loader.require(S .. "Data/Visuals")
	local Economy = Loader.require(S .. "Economy")
	local EggRoll = Loader.require(S .. "EggRoll")
	local SpeedMath = Loader.require(S .. "SpeedMath")
	local GardenRules = Loader.require(S .. "GardenRules")
	local Progression = Loader.require(S .. "Progression")
	local DataSchema = Loader.require("ServerScriptService/Server/Logic/DataSchema")

	-- SEED 11장 표: id, 화면 이름, 표 성장 시간(초), 건너뛰기 배수, 크리스탈, 도감 속도, 식물 수, 열매 간격 범위, 열매 값 범위
	local DAY = 86400
	local SEED_RARITIES = {
		{ "common", "Common", 10, 1, 1, 420, 6, 29, 31, 8, 13 },
		{ "uncommon", "Uncommon", 60, 2, 1, 520, 12, 27, 29, 36, 53 },
		{ "rare", "Rare", 300, 4, 2, 620, 16, 25, 27, 180, 260 },
		{ "epic", "Epic", 1200, 8, 3, 800, 16, 23, 25, 1100, 1600 },
		{ "legendary", "Legendary", 3600, 15, 5, 1000, 16, 21, 23, 7200, 11000 },
		{ "mythic", "Mythic", 10800, 30, 8, 1300, 19, 19, 21, 54e3, 79e3 },
		{ "cosmic", "Cosmic", 28800, 60, 12, 1700, 17, 17, 19, 450e3, 660e3 },
		{ "secret", "Secret", DAY, 100, 20, 2200, 13, 15, 17, 4.5e6, 6.6e6 },
		{ "eternity", "Eternity", 2 * DAY, 180, 30, 2800, 10, 13, 15, 45e6, 66e6 },
		{ "divine", "Divine", 4 * DAY, 300, 50, 3600, 7, 11, 13, 540e6, 790e6 },
		{ "super", "Super", 8 * DAY, 500, 100, 4600, 5, 9, 10, 10e9, 15e9 },
		{ "hacker", "Hacker", 14 * DAY, 800, 150, 5800, 4, 8, 9, 120e9, 180e9 },
		{ "original", "Original", 20 * DAY, 1200, 220, 7200, 4, 7, 8, 1.5e12, 2.2e12 },
		{ "developer", "Developer", 30 * DAY, 2000, 320, 9000, 6, 6, 7, 18e12, 27e12 },
		{ "ultradivine", "Ultradivine", 45 * DAY, 3000, 480, 11000, 5, 5, 6, 220e12, 330e12 },
		{ "hacker_glitch", "H?a.(cke_r!#", 60 * DAY, 5000, 700, 14000, 2, 4, 5, 2.7e15, 3.3e15 },
	}
	local SKIP_MULT = {}
	for _, r in SEED_RARITIES do
		SKIP_MULT[r[1]] = r[4]
	end

	-- SEED 12장 표: 구역 id, 추천 속도, 경비 이름, 등급 가중치
	local SEED_ZONES = {
		{ "forest", 10, "덥석 파리지옥", { common = 60, uncommon = 35, rare = 5 } },
		{ "lake", 900, "연꽃 개구리풀", { common = 45, uncommon = 45, rare = 10 } },
		{ "desert", 10e3, "가시 선인장 대장", { uncommon = 60, rare = 35, epic = 5 } },
		{ "jungle", 40e3, "덩굴 호랑이꽃", { uncommon = 45, rare = 45, epic = 10 } },
		{ "snow", 170e3, "서리 가시나무", { rare = 60, epic = 35, legendary = 5 } },
		{ "volcano", 700e3, "용암 머리꽃", { rare = 45, epic = 45, legendary = 10 } },
		{ "abyss_ocean", 2.5e6, "심해 해초 괴물", { epic = 60, legendary = 35, mythic = 5 } },
		{ "prehistoric", 18e6, "공룡 고사리", { epic = 45, legendary = 45, mythic = 10 } },
		{ "cosmic", 700e6, "우주 버섯 거인", { legendary = 60, mythic = 35, cosmic = 5 } },
		{ "cherry_blossom", 2.5e9, "벚꽃 여우나무", { legendary = 45, mythic = 45, cosmic = 10 } },
		{ "titan_temple", 7e9, "돌 거인 나무", { mythic = 60, cosmic = 35, secret = 5 } },
		{ "angels_demons", 20e9, "천사 백합/악마 장미", { mythic = 45, cosmic = 45, secret = 10 } },
		{ "enchanted_forest", 50e9, "정령 버섯", { cosmic = 55, secret = 40, eternity = 5 } },
		{ "candy_kingdom", 150e9, "사탕수수 거인", { secret = 55, eternity = 40, divine = 5 } },
		{ "haunted_castle", 500e9, "호박 머리 덩굴", { eternity = 55, divine = 40, super = 5 } },
		{ "hacker_lab", 700e9, "바이러스 덩굴", { super = 55, hacker = 40, original = 5 } },
		{ "developer_room", 900e9, "디버그 선인장", { original = 55, developer = 40, ultradivine = 5 } },
		{ "bug_dimension", 1.2e12, "글리치 장미 괴물", { developer = 40, ultradivine = 55, hacker_glitch = 5 } },
	}

	local function withWorld(fn)
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
		w.UpgradeService = H.server("Services/UpgradeService")
		w.A = H.newPlayer(3001, "Fuzzer7")
		w.sessionA, w.dataA = H.login(w.A)
		w.sessionA.plotIndex = 1
		w.B = H.newPlayer(3002, "Victim7")
		w.sessionB, w.dataB = H.login(w.B)
		w.sessionB.plotIndex = 2
		w.dataA.penLevel = Upgrades.PEN_MAX_LEVEL - 2
		w.dataB.penLevel = Upgrades.PEN_MAX_LEVEL
		w.dataB.nextUid = 700
		w.BaseService.start()
		w.PetService.start()
		w.FruitService.start()
		w.SakuraService.start()
		w.IndexService.start()
		w.UpgradeService.start()
		local ok, err = pcall(fn, w)
		H.uninstall()
		if not ok then
			error(err, 0)
		end
	end

	local function taken(data)
		local list = {}
		for _, r in data.pets do
			table.insert(list, { x = r.x, z = r.z, size = r.size })
		end
		for _, r in data.incubators do
			table.insert(list, { x = r.x, z = r.z, size = r.size })
		end
		return list
	end

	local function addPlant(w, player, data, petId, fruits)
		local spot = w.EggPlacement.firstFreeGrid("normal", taken(data))
		local record = {
			uid = w.DataSchema.newUid(data, "p"),
			petId = petId,
			size = "normal",
			mutations = {},
			x = spot.x,
			z = spot.z,
			fruits = fruits or 0,
			fruitProgress = 0,
		}
		assert(w.PetService.addPlant(player, record), "addPlant 실패")
		return record
	end

	-- 씨앗을 가방에 받고 정원에 심음 → 심은 씨앗 기록
	local function plantSeed(w, player, data, plotIndex, petId)
		local x, z = w.H.plotSpot(plotIndex)
		w.H.spawn(player, x, 3, z)
		assert(w.BaseService.grantEgg(player, petId, "normal", {}, "sakura"), "grantEgg 실패")
		local egg = data.eggs[#data.eggs]
		local l = w.EggPlacement.firstFreeGrid(egg.size, taken(data))
		local spot = w.H.MapLayout.toWorld(plotIndex, l.x, l.z)
		assert(w.BaseService.placeEgg(player, egg.uid, spot.x, spot.z), "plantSeed 실패")
		return data.incubators[#data.incubators], egg
	end

	local function finite(n)
		return typeof(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
	end

	local function isInt(n)
		return finite(n) and n == math.floor(n)
	end

	------------------------------------------------------------------
	T.suite("7판 주임 검수: 등급 16개 무결성")

	T.test(
		"순서·id·화면 이름·성장 기준·건너뛰기·크리스탈·도감 속도가 SEED 11장 표와 같고 단조 증가",
		function()
			T.eq(#Rarities.list, 16)
			T.eq(Rarities.count, 16)
			T.eq(Rarities.TOP, "hacker_glitch")
			local prev = nil
			for i, row in SEED_RARITIES do
				local r = Rarities.list[i]
				T.eq(r.id, row[1], "순서 " .. i)
				T.eq(r.order, i)
				T.eq(r.displayName, row[2], row[1] .. " 화면 이름")
				T.eq(Rarities.displayName(row[1]), row[2])
				T.eq(r.baseGrowSeconds, row[3], row[1] .. " 성장 기준")
				T.eq(Config.SKIP_RARITY_MULTIPLIER[row[1]], row[4], row[1] .. " 건너뛰기")
				T.eq(Config.SAKURA_OFFER_CRYSTALS[row[1]], row[5], row[1] .. " 크리스탈")
				T.eq(Index.RARITY_SPEED[row[1]], row[6], row[1] .. " 도감 속도")
				if prev then
					T.truthy(
						r.baseGrowSeconds > prev.baseGrowSeconds,
						row[1] .. " 성장 시간이 앞 등급보다 커야 함"
					)
					T.truthy(
						Config.SKIP_RARITY_MULTIPLIER[row[1]] > Config.SKIP_RARITY_MULTIPLIER[prev.id],
						row[1] .. " 건너뛰기 증가"
					)
					T.truthy(
						Index.RARITY_SPEED[row[1]] > Index.RARITY_SPEED[prev.id],
						row[1] .. " 도감 속도 증가"
					)
					T.truthy(
						Config.SAKURA_OFFER_CRYSTALS[row[1]] >= Config.SAKURA_OFFER_CRYSTALS[prev.id],
						row[1] .. " 크리스탈 증가"
					)
				end
				prev = r
			end
			-- 16번 글자는 글자 그대로 (12바이트), 모르는 id 는 id 그대로
			local glitch = Rarities.get("hacker_glitch")
			T.eq(glitch.displayName, "H?a.(cke_r!#")
			T.eq(#glitch.displayName, 12)
			T.eq(Rarities.displayName("nope"), "nope")
			-- 등급 id 를 키로 쓰는 표에 모르는 id 가 없고 16개가 다 있음
			local count = 0
			for id in Config.SKIP_RARITY_MULTIPLIER do
				T.truthy(Rarities.get(id) ~= nil, "건너뛰기 표의 모르는 등급 " .. id)
				count += 1
			end
			T.eq(count, 16)
			count = 0
			for id in Config.SAKURA_OFFER_CRYSTALS do
				T.truthy(Rarities.get(id) ~= nil, "크리스탈 표의 모르는 등급 " .. id)
				count += 1
			end
			T.eq(count, 16)
			for _, r in Rarities.list do
				T.truthy(Visuals.auras[r.aura] ~= nil, r.id .. " 아우라 모양")
				T.truthy(Visuals.eggLooks[r.id] ~= nil, r.id .. " 씨앗 껍데기")
			end
			for _, id in EggSpawn.SPECIAL_RARITIES do
				T.truthy(Visuals.specialEggs[id] ~= nil, id .. " 공지 씨앗 글자")
			end
		end
	)

	T.test(
		"식물 158종: 등급이 16개 중 하나, 등급별 수·열매 간격·열매 값 범위가 SEED 11장과 같고 성장 시간은 기준 ×0.75~1.25",
		function()
			T.eq(#Plants.list, 158)
			local stats = {}
			local ids = {}
			for _, p in Plants.list do
				T.truthy(Rarities.get(p.rarity) ~= nil, p.id .. " 등급 " .. tostring(p.rarity))
				T.falsy(ids[p.id], "식물 id 겹침 " .. p.id)
				ids[p.id] = true
				local s = stats[p.rarity] or { n = 0 }
				stats[p.rarity] = s
				s.n += 1
				s.fiMin = math.min(s.fiMin or 1e9, p.fruitIntervalSeconds)
				s.fiMax = math.max(s.fiMax or 0, p.fruitIntervalSeconds)
				s.fvMin = math.min(s.fvMin or 1e30, p.fruitValue)
				s.fvMax = math.max(s.fvMax or 0, p.fruitValue)
				local ratio = p.growSeconds / Rarities.get(p.rarity).baseGrowSeconds
				if p.id ~= "puppy_grass" then -- 튜토리얼용 강아지풀(표 3초)만 예외
					T.truthy(ratio >= 0.75 and ratio <= 1.25, p.id .. " 성장 시간 비율 " .. ratio)
				end
			end
			local prevMax = 0
			for _, row in SEED_RARITIES do
				local s = stats[row[1]]
				T.eq(s.n, row[7], row[1] .. " 식물 수")
				T.eq(s.fiMin, row[8], row[1] .. " 간격 최소")
				T.eq(s.fiMax, row[9], row[1] .. " 간격 최대")
				T.near(s.fvMin / row[10], 1, 1e-9, row[1] .. " 열매 값 최소")
				T.near(s.fvMax / row[11], 1, 1e-9, row[1] .. " 열매 값 최대")
				T.truthy(s.fvMin > prevMax, row[1] .. " 열매 값이 앞 등급과 안 겹침")
				prevMax = s.fvMax
			end
		end
	)

	T.test(
		"super_ultradivine 은 등급 표·코드 어디에도 없고 트레일 id 한 곳에만 남음 (src 코드, 주석 뺀 줄)",
		function()
			T.eq(Rarities.get("super_ultradivine"), nil)
			local hits = {}
			local function scan(dir)
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						scan(path)
					elseif string.sub(name, -5) == ".luau" then
						local n = 0
						local text = string.gsub(fs.readFile(path), "%-%-%[%[.-%]%]", "")
						for line in string.gmatch(text, "[^\n]+") do
							local code = string.gsub(line, "%-%-.*$", "")
							if string.find(code, "super_ultradivine", 1, true) then
								n += 1
							end
						end
						if n > 0 then
							hits[path] = n
						end
					end
				end
			end
			scan("src")
			local files = {}
			for path, n in hits do
				table.insert(files, path .. ":" .. n)
			end
			T.eq(#files, 1, "남은 곳: " .. table.concat(files, ", "))
			T.eq(hits["src/shared/Data/Upgrades.luau"], 1, "트레일 16번 id 한 곳")
		end
	)

	------------------------------------------------------------------
	T.suite("7판 주임 검수: 구역 18개")

	T.test(
		"18구역: id·추천 속도·경비 이름·가중치 합 100 = SEED 12장, zMin 간격 240, 맵 끝 4320, 둥지 식물 8종",
		function()
			T.eq(#Biomes.list, 18)
			T.eq(#MapLayout.biomes, 18)
			T.eq(MapLayout.MAP_END_Z, 4320)
			for i, row in SEED_ZONES do
				local b = Biomes.list[i]
				T.eq(b.id, row[1], "순서 " .. i)
				T.eq(b.order, i)
				T.near(b.recommendedSpeed, row[2], row[2] * 1e-9, row[1] .. " 추천 속도")
				T.eq(b.guardName, row[3], row[1] .. " 경비")
				local weights = EggSpawn.BIOME_RARITY_WEIGHTS[row[1]]
				local sum = 0
				for id, w in row[4] do
					T.eq(weights[id], w, row[1] .. " 가중치 " .. id)
				end
				for id, w in weights do
					T.truthy(row[4][id] ~= nil, row[1] .. " 표에 없는 등급 " .. id)
					sum += w
				end
				T.eq(sum, 100, row[1] .. " 가중치 합")
				local range = MapLayout.biomes[i]
				T.eq(range.zMin, (i - 1) * 240)
				T.eq(range.zMax, i * 240)
				T.eq(MapLayout.zoneAt(range.zMin), row[1])
				T.eq(MapLayout.zoneAt(range.zMax - 0.01), row[1])
				-- 둥지 8개: 구역 앞뒤 20 이상, 벽 20 이상, 경비 집 60 이상 떨어짐
				local nests = MapLayout.nestsFor(row[1])
				T.eq(#nests, 8)
				local home = MapLayout.guardHome(row[1])
				for _, n in nests do
					T.truthy(n.z >= range.zMin + 20 and n.z <= range.zMax - 20, row[1] .. " 둥지 z")
					T.truthy(math.abs(n.x) <= 90, row[1] .. " 둥지 x")
					T.truthy(
						math.sqrt((n.x - home.x) ^ 2 + (n.z - home.z) ^ 2) >= 60,
						row[1] .. " 경비 집과 가까움"
					)
				end
				-- 둥지 식물: 구역마다 8종(천사&악마는 쪽마다 8종), 가중치 있는 등급은 전부 식물이 있음
				for _, side in { "light", "dark" } do
					local pool = EggRoll.nestPool(row[1], side)
					if row[1] ~= "angels_demons" then
						T.eq(#pool, 8, row[1] .. " 둥지 식물 수")
					else
						T.eq(#pool, 8, row[1] .. " " .. side)
					end
					local have = {}
					for _, p in pool do
						have[p.rarity] = true
					end
					for id in weights do
						T.truthy(have[id], row[1] .. " " .. side .. " 에 " .. id .. " 식물이 없음")
					end
				end
			end
			T.eq(MapLayout.zoneAt(4320), nil)
			T.eq(MapLayout.zoneAt(4319.99), "bug_dimension")
			T.falsy(MapLayout.isInHub({ X = 0, Z = 4200 }))
			T.truthy(MapLayout.isInHub({ X = 0, Z = -0.01 }))
			T.eq(MapLayout.NIGHT_WALL.z, 0, "밤 벽은 허브 경계 한 장 (맵 길이와 무관)")
		end
	)

	T.test(
		"1~15구역 좌표·추천 속도·경비 속도·둥지는 6판 코드로 뽑은 값과 같음 (해시 1089747796)",
		function()
			local parts = {}
			local function f(n)
				return string.format("%.6g", n)
			end
			for i = 1, 15 do
				local b = MapLayout.biomes[i]
				local bio = Biomes.list[i]
				local s = {
					b.id,
					i,
					f(b.zMin),
					f(b.zMax),
					f(b.centerZ),
					f(bio.recommendedSpeed),
					f(bio.guardSpeed),
					bio.guardName,
					bio.nests,
				}
				for _, n in MapLayout.nestsFor(b.id) do
					table.insert(s, f(n.x) .. "," .. f(n.z))
				end
				local g = MapLayout.guardHome(b.id)
				table.insert(s, "g" .. f(g.x) .. "," .. f(g.z))
				table.insert(parts, table.concat(s, ";"))
			end
			local text = table.concat(parts, "\n")
			local h = 5381
			for i = 1, #text do
				h = (h * 33 + string.byte(text, i)) % 4294967296
			end
			T.eq(#text, 2034)
			T.eq(h, 1089747796)
		end
	)

	T.test(
		"추천 속도·경비 속도·추격 속도가 구역마다 단조 증가, 추격 속도는 상한(230) 안, 추천 속도면 도망 / 모자라면 잡힘",
		function()
			local prevRec, prevGuard, prevChase = 0, 0, 0
			local sizes = { 0.10, 0.2, 0.27, 0.35 }
			for i, b in Biomes.list do
				T.truthy(b.recommendedSpeed > prevRec, b.id .. " 추천 속도 증가")
				T.near(b.guardSpeed, b.recommendedSpeed * Config.GUARD_SPEED_RATIO * 0.9, b.guardSpeed * 1e-9)
				T.truthy(b.guardSpeed > prevGuard)
				local chase = SpeedMath.guardChaseSpeed(b.guardSpeed)
				T.truthy(chase > prevChase, b.id .. " 추격 속도 증가 " .. chase)
				T.truthy(chase <= Config.SPEED_WALK_MAX and chase <= Config.GUARD_MAX_WALKSPEED, b.id .. " 상한")
				if i >= 2 then
					-- 보통 알(-10%)을 들고 추천 속도: 경비보다 빠름 / 추천 속도의 98%: 경비보다 느림 (잡힘)
					T.truthy(
						SpeedMath.canEscape(b.guardSpeed, SpeedMath.carrySpeed(b.recommendedSpeed, 0.10)),
						b.id .. " 도망"
					)
					T.truthy(SpeedMath.carryWalkSpeed(b.recommendedSpeed, 0.10) >= chase, b.id .. " 걷기 도망")
					T.truthy(
						SpeedMath.carryWalkSpeed(b.recommendedSpeed * 0.98, 0.10) < chase,
						b.id .. " 걷기 잡힘"
					)
					for _, pen in sizes do
						local need = SpeedMath.requiredSpeed(b.recommendedSpeed, pen)
						T.truthy(SpeedMath.carryWalkSpeed(need * 1.01, pen) >= chase, b.id .. " 큰 알 도망 " .. pen)
						T.truthy(SpeedMath.carryWalkSpeed(need * 0.98, pen) < chase, b.id .. " 큰 알 잡힘 " .. pen)
					end
				end
				prevRec, prevGuard, prevChase = b.recommendedSpeed, b.guardSpeed, chase
			end
			T.truthy(SpeedMath.guardChaseSpeed(Biomes.byId.bug_dimension.guardSpeed) < Config.SPEED_WALK_MAX - 0.2)
		end
	)

	T.test(
		"둥지 추첨 분포(구역마다 3만 번)가 가중치와 ±1.5%p 안이고 새 구역은 새 등급을 뽑음 / 특별 추첨 해커 글리치는 버그 차원에서만 약 0.5%",
		function()
			local rand = T.rng(7070)
			local seen = {}
			for _, row in SEED_ZONES do
				for _, side in { "light", "dark" } do
					if side == "light" or row[1] == "angels_demons" then
						local counts = {}
						local n = 30000
						for _ = 1, n do
							local pet = EggRoll.rollNestPet(row[1], side, rand)
							T.truthy(pet ~= nil, row[1] .. " 추첨 실패")
							counts[pet.rarity] = (counts[pet.rarity] or 0) + 1
							seen[pet.rarity] = true
						end
						for id, w in row[4] do
							T.near((counts[id] or 0) / n * 100, w, 1.5, row[1] .. " " .. id)
						end
						for id in counts do
							T.truthy(row[4][id] ~= nil, row[1] .. " 에서 나오면 안 되는 등급 " .. id)
						end
					end
				end
			end
			for _, r in Rarities.list do
				T.truthy(seen[r.id], r.id .. " 는 어느 구역에서도 안 뽑힘")
			end
			local glitchHits, resets = 0, 200000
			for _ = 1, resets do
				for _, b in Biomes.list do
					if b.id ~= "bug_dimension" then
						break
					end
				end
			end
			for _ = 1, resets do
				for _, pet in EggRoll.rollSpecials("bug_dimension", nil, rand) do
					if pet.rarity == "hacker_glitch" then
						glitchHits += 1
					end
				end
				for _, other in { "hacker_lab", "developer_room", "haunted_castle" } do
					for _, pet in EggRoll.rollSpecials(other, nil, rand) do
						T.truthy(pet.rarity ~= "hacker_glitch", other .. " 에서 해커 글리치 특별 씨앗")
					end
				end
				if _ > 20000 then
					break
				end
			end
			T.truthy(
				glitchHits > 40 and glitchHits < 180,
				"해커 글리치 특별 씨앗 20,000번 중 " .. glitchHits .. " (기대 100)"
			)
		end
	)

	T.test(
		"도감 보상 전부(158종): 속도·코인이 유한하고 상한 안, 큰 숫자 표시가 깨지지 않음",
		function()
			local discovered = {}
			for _, p in Plants.list do
				discovered[p.id] = true
			end
			local ids, speed, money = Progression.pendingRewards(discovered, {})
			T.eq(#ids, 158)
			T.truthy(finite(speed) and speed < Config.SPEED_MAX, "도감 속도 합 " .. tostring(speed))
			T.truthy(finite(money) and money < Config.MONEY_MAX, "도감 코인 합 " .. tostring(money))
			local Format = Loader.require(S .. "Format")
			T.eq(Format.number(3.3e15), "3.3Qa")
			T.eq(Format.number(1.2e12 * 6), "7.2T")
		end
	)

	------------------------------------------------------------------
	T.suite("7판 주임 검수: 성장 3배")

	T.test(
		"무작위 식물 30종: 씨앗 Required·Attr·건너뛰기 가격이 전부 표 ÷ 3 기준, 단계 비율은 그대로",
		function()
			withWorld(function(w)
				local rand = T.rng(7007)
				local ids = { "puppy_grass", "sprout_daisy", "rune_rose", "static_world_tree" }
				for _ = 1, 26 do
					table.insert(ids, Plants.list[math.floor(rand() * #Plants.list) + 1].id)
				end
				for _, id in ids do
					local plant = Plants.get(id)
					local tableSeconds = plant.growSeconds
					T.near(Economy.growSeconds(id), tableSeconds / 3, 1e-9, id)
					T.near(Economy.hatchSeconds(id), tableSeconds / 3, 1e-9, id)
					local record, bagEgg = plantSeed(w, w.A, w.dataA, 1, id)
					T.near(bagEgg.required, tableSeconds / 3, 1e-9, id .. " 가방 Required")
					T.near(record.required, tableSeconds / 3, 1e-9, id .. " 심은 씨앗 Required")
					T.eq(record.progress, 0)
					local part
					for _, child in w.H.map.folders.Incubating.children do
						if child:GetAttribute("EggUid") == record.uid then
							part = child
						end
					end
					T.truthy(part ~= nil, id .. " 씨앗 파트")
					T.near(part:GetAttribute("Required"), tableSeconds / 3, 1e-9, id .. " Attr Required")
					T.eq(part:GetAttribute("Stage"), "sprout")
					-- 건너뛰기: 남은 실제 시간(분 올림) × 10 × SEED 배수
					local minutes = math.max(1, math.ceil(tableSeconds / 3 / 60 - 1e-9))
					T.eq(
						GardenRules.skipCost(id, 0, record.required, "all"),
						math.ceil(
							minutes * 10 * SKIP_MULT[plant.rarity]
								+ w.H.shared("Economy").fruitValue(id, "normal", {}) * w.Config.SKIP_FRUIT_FACTOR
						),
						id .. " 건너뛰기 가격"
					)
					T.eq(Economy.timerSeconds(0, record.required), record.required)
					-- 단계 비율 (진행도/Required)
					T.eq(GardenRules.stage(0.2499 * record.required, record.required), "sprout")
					T.eq(GardenRules.stage(0.25 * record.required, record.required), "stem")
					T.eq(GardenRules.stage(0.5999 * record.required, record.required), "stem")
					T.eq(GardenRules.stage(0.6 * record.required, record.required), "bud")
					T.eq(GardenRules.stage(record.required, record.required), "adult")
					-- 다시 가방으로 (정원 자리 비우기)
					T.truthy(w.BaseService.pickUpEgg(w.A, record.uid), id .. " 다시 줍기")
					T.near(w.dataA.eggs[#w.dataA.eggs].required, tableSeconds / 3, 1e-9)
				end
				T.eq(#w.H.warnings, 0)
			end)
		end
	)

	T.test(
		"밤 30배와 곱: 비밀(표 24시간) → 낮 8시간 → 밤이면 16분(성장 게임패스까지 있으면 8분) 뒤 성체",
		function()
			for _, pass in { false, true } do
				withWorld(function(w)
					w.sessionA.hasGrowthPass = pass
					w.H.setPhase("Night")
					local record = plantSeed(w, w.A, w.dataA, 1, "rune_rose")
					T.eq(record.required, 28800)
					local seconds = if pass then 480 else 960
					w.H.advance(seconds - 5)
					T.eq(#w.dataA.incubators, 1, "5초 모자라면 아직 씨앗")
					w.H.advance(10)
					T.eq(#w.dataA.incubators, 0, "성체")
					T.eq(w.dataA.pets[#w.dataA.pets].petId, "rune_rose")
					T.eq(#w.H.warnings, 0)
				end)
			end
		end
	)

	T.test(
		"오프라인 성장은 ÷3 값 기준 (24시간 상한): 비밀·영원은 성체가 되고 신성(1일 8시간)은 아직 씨앗",
		function()
			withWorld(function(w)
				local secret = plantSeed(w, w.A, w.dataA, 1, "rune_rose")
				local divineId
				for _, p in Plants.list do
					if p.rarity == "divine" then
						divineId = p.id
					end
				end
				local divine = plantSeed(w, w.A, w.dataA, 1, divineId)
				T.near(divine.required, Plants.get(divineId).growSeconds / 3, 1e-9)
				w.dataA.lastSaveTime = w.H.time() - 7200
				w.BaseService.onPlayerReady(w.A)
				T.near(secret.progress, 7200, 1e-6, "2시간 오프라인")
				T.near(divine.progress, 7200, 1e-6)
				w.dataA.lastSaveTime = w.H.time() - 10 * 86400
				w.BaseService.onPlayerReady(w.A)
				T.near(divine.progress, 7200 + 86400, 1e-6, "24시간 상한")
				T.truthy(divine.progress < divine.required, "신성은 아직")
				T.eq(#w.dataA.pets, 1, "비밀 성체 1그루")
				T.eq(w.dataA.pets[1].petId, "rune_rose")
				T.eq(#w.H.warnings, 0)
			end)
		end
	)

	T.test(
		"Config.GROWTH_SPEED_MULTIPLIER 가 이상한 값(NaN·0·음수·inf·글자·nil)이어도 성장 시간이 유한한 양수",
		function()
			local original = Config.GROWTH_SPEED_MULTIPLIER
			local ok, err = pcall(function()
				for _, bad in { 0 / 0, 0, -3, math.huge, "x", false } do
					Config.GROWTH_SPEED_MULTIPLIER = bad
					for _, id in { "puppy_grass", "rune_rose", "static_world_tree", "no_such_plant" } do
						local g = Economy.growSeconds(id)
						assert(finite(g) and g > 0, "growSeconds " .. id .. " = " .. tostring(g))
					end
				end
				Config.GROWTH_SPEED_MULTIPLIER = nil
				T.eq(Economy.growSeconds("rune_rose"), 86400)
			end)
			Config.GROWTH_SPEED_MULTIPLIER = original
			if not ok then
				error(err, 0)
			end
			T.eq(Economy.growSeconds("rune_rose"), 28800)
		end
	)

	T.test(
		"이상한 진행도·required 에서도 GardenRules/Economy 가 안 터지고 NaN 이 안 나옴",
		function()
			-- (NaN·inf 진행도는 reconcile 이 걸러서 실제로는 들어오지 않음 — 그래도 던져서 "안 터지는지" 만 봄. 결과가 NaN 인 칸은 보고서 D-3)
			local weird = { 0 / 0, -5, 0, math.huge, -math.huge, 1e308 }
			for _, p in weird do
				for _, r in weird do
					local stage = GardenRules.stage(p, r)
					T.truthy(stage == "sprout" or stage == "stem" or stage == "bud" or stage == "adult")
					local cost = GardenRules.skipCost("rune_rose", p, r, "all")
					T.truthy(typeof(cost) == "number" and cost >= 0, "skipCost " .. tostring(cost))
					T.truthy(typeof(Economy.timerSeconds(p, r)) == "number")
				end
			end
			-- 정상 범위에서는 항상 0~1 유한
			for _, p in { 0, 0.5, 1, 10, 1e6 } do
				for _, r in { 0, -1, 1, 10, 1e6 } do
					local fraction = GardenRules.fraction(p, r)
					T.truthy(finite(fraction) and fraction >= 0 and fraction <= 1, "fraction " .. p .. "/" .. r)
				end
			end
		end
	)

	------------------------------------------------------------------
	T.suite("7판 주임 검수: 저장 스키마 6 → 7")

	local function v6Save(entries, eggs)
		return {
			version = 6,
			money = 1234,
			speed = 77,
			tutorialStep = 12,
			penLevel = 3,
			incubators = entries,
			eggs = eggs or {},
		}
	end

	T.test("6→7: 진행도 비율을 지키고 required 는 표 ÷ 3, required 를 넘지 않음", function()
		local ratios = { 0, 0.1, 0.25, 0.3333, 0.34, 0.5, 0.99, 1, 1.5 }
		local entries = {}
		local plantsUsed = {
			"rune_rose",
			"sprout_daisy",
			"static_world_tree",
			"puppy_grass",
			"owl_oak",
			"upside_down_tree",
			"rune_rose",
			"sprout_daisy",
			"owl_oak",
		}
		for i, ratio in ratios do
			local plant = Plants.get(plantsUsed[i])
			table.insert(entries, {
				uid = "i" .. i,
				petId = plant.id,
				size = "normal",
				mutations = {},
				x = 0 / 0, -- 자리가 깨져도 빈 격자 자리로
				z = 0,
				progress = ratio * plant.growSeconds,
				required = plant.growSeconds,
			})
		end
		local eggs = {
			{ uid = "g1", petId = "rune_rose", size = "normal", mutations = {}, progress = 43200, required = 86400 },
			{ uid = "g2", petId = "sprout_daisy", size = "big", mutations = {}, progress = 5 }, -- required 칸 없음 → 표 시간 기준
		}
		local data = DataSchema.reconcile(DataSchema.migrate(v6Save(entries, eggs)), 1000)
		T.eq(data.version, 7)
		T.eq(#data.incubators, 9)
		for i, ratio in ratios do
			local rec = data.incubators[i]
			T.eq(rec.uid, "i" .. i)
			local required = Plants.get(rec.petId).growSeconds / 3
			T.near(rec.required, required, 1e-9)
			T.truthy(rec.progress <= rec.required, "required 를 넘음 " .. i)
			T.near(rec.progress / rec.required, math.min(1, ratio), 1e-9, "비율 " .. ratio)
		end
		T.truthy(
			data.incubators[5].progress < data.incubators[5].required,
			"1/3 을 넘게 자란 씨앗이 바로 성체가 되면 안 됨"
		)
		T.near(data.eggs[1].progress, 14400, 1e-9)
		T.eq(data.eggs[1].required, 28800)
		T.near(data.eggs[2].progress, 5 / 10 * (10 / 3), 1e-9)
	end)

	T.test(
		"6→7: 이상한 값(NaN·음수·required 0·글자·없는 식물)에서도 안 터지고 결과가 올바른 모양",
		function()
			local entries = {}
			local weird = { 0 / 0, -5, "x", true, {}, math.huge }
			for i, v in weird do
				table.insert(entries, { uid = "w" .. i, petId = "rune_rose", progress = v, required = 86400 })
				table.insert(entries, { uid = "r" .. i, petId = "rune_rose", progress = 100, required = v })
			end
			table.insert(entries, { uid = "z0", petId = "rune_rose", progress = 100, required = 0 })
			table.insert(entries, { uid = "nope", petId = "no_such_plant", progress = 1, required = 1 })
			table.insert(entries, "문자열")
			local raw = v6Save(entries)
			local ok, data = pcall(function()
				return DataSchema.reconcile(DataSchema.migrate(raw), 1000)
			end)
			T.truthy(ok, tostring(data))
			for _, rec in data.incubators do
				T.truthy(
					finite(rec.progress) and rec.progress >= 0 and rec.progress <= rec.required,
					"진행도 " .. tostring(rec.progress)
				)
				T.eq(rec.required, 28800)
			end
			T.eq(DataSchema.rescaleProgress("문자열"), false)
			T.eq(DataSchema.rescaleProgress({ petId = "rune_rose", progress = 0 / 0 }), false)
			T.eq(DataSchema.rescaleProgress({ petId = "rune_rose", progress = -1 }), false)
			T.eq(DataSchema.rescaleProgress({ petId = "nope", progress = 1 }), false)
		end
	)

	T.test(
		"rescaleProgress 무작위 2000번: 비율 보존, 7판 저장은 다시 안 줄임 (두 번 불러도 같음)",
		function()
			local rand = T.rng(6767)
			for _ = 1, 2000 do
				local plant = Plants.list[math.floor(rand() * #Plants.list) + 1]
				local fraction = rand()
				local entry =
					{ petId = plant.id, progress = fraction * plant.growSeconds, required = plant.growSeconds }
				T.truthy(DataSchema.rescaleProgress(entry))
				T.near(entry.progress / entry.required, fraction, 1e-9, plant.id)
				T.near(entry.required, plant.growSeconds / 3, 1e-9)
			end
			local save = v6Save({
				{
					uid = "a1",
					petId = "rune_rose",
					size = "normal",
					mutations = {},
					x = 0,
					z = 0,
					progress = 43200,
					required = 86400,
				},
			})
			local once = DataSchema.reconcile(DataSchema.migrate(save), 1000)
			T.near(once.incubators[1].progress, 14400, 1e-9)
			-- 저장했다 다시 불러옴 (version 7) → 또 줄지 않음
			local twice = DataSchema.reconcile(DataSchema.migrate(once), 1000)
			T.near(twice.incubators[1].progress, 14400, 1e-9)
			T.eq(twice.incubators[1].required, 28800)
		end
	)

	------------------------------------------------------------------
	T.suite("7판 주임 검수: 개발 명령·알림 (구역 16~18)")

	T.test(
		"/zone 16 17 18 은 구역 입구로, 이상한 값은 무시, 새 구역에 들어가면 ZoneEntered",
		function()
			local H = ServerHarness.install(Loader, T)
			local ok, err = pcall(function()
				H.startNet()
				H.server("Services/SakuraService")
				local BaseService = H.server("Services/BaseService")
				BaseService.start()
				H.RunService.studio = true
				local DevCommands = H.server("Services/DevCommands")
				DevCommands.start()
				local p = H.newPlayer(3101, "Dev7")
				local session = H.login(p)
				session.plotIndex = 1
				H.Players.PlayerAdded:Fire(p)
				H.spawn(p, 0, 3, 0)
				for n = 16, 18 do
					p.Chatted:Fire("/zone " .. n)
					T.eq(p.Character.root.Position.Z, (n - 1) * 240 + 12, "/zone " .. n)
					H.advance(0.3)
					T.eq(session.currentZone, Biomes.list[n].id)
				end
				local z = p.Character.root.Position.Z
				for _, bad in { "/zone 19", "/zone 0", "/zone -1", "/zone nan", "/zone 1e999", "/zone abc", "/zone" } do
					p.Chatted:Fire(bad)
					T.eq(p.Character.root.Position.Z, z, bad .. " 은 무시")
				end
				T.truthy(#H.sent(p, "ZoneEntered") >= 3)
				for _, text in H.warnings do
					T.truthy(string.find(text, "TextChatCommand", 1, true) ~= nil, "뜻밖의 warn: " .. tostring(text)) -- 가짜 세상엔 TextChatService 가 없어서 나는 안내만 허용
				end
			end)
			H.uninstall()
			if not ok then
				error(err, 0)
			end
		end
	)

	T.test("밤이 되면 맨 끝 구역(버그 차원)에 있던 사람도 베이스(허브)로 돌아옴", function()
		withWorld(function(w)
			w.H.spawn(w.A, 0, 3, 4200)
			w.H.setPhase("Night")
			T.truthy(
				w.H.MapLayout.isInHub(w.A.Character.root.Position),
				"허브로 돌아옴 z=" .. w.A.Character.root.Position.Z
			)
		end)
	end)

	local function inWorld(options, fn)
		local H = ServerHarness.install(Loader, T, options)
		local ok, err = pcall(function()
			H.startNet()
			fn(H)
		end)
		H.uninstall()
		if not ok then
			error(err, 0)
		end
	end

	T.test(
		"진짜 GuardianService: 18구역 경비 모두 알 든 느린 사람을 쫓고, 쫓는 속도 = 구역 고정 추격 속도 (230 이하)",
		function()
			inWorld(nil, function(H)
				local SpeedService = H.server("Services/SpeedService")
				H.server("Services/GuardianService").start()
				local p = H.newPlayer(3201, "Runner7")
				local session, data = H.login(p)
				session.plotIndex = 1
				H.spawn(p, 0, 3, 0)
				T.eq(#H.map.folders.Guardians.children, 18)
				for _, b in Biomes.list do
					data.speed = b.recommendedSpeed * 0.5
					session.carryingUid = "e1"
					session.carryPenalty = 0.10
					SpeedService.refresh(p)
					H.carry(p, { petId = "sprout_daisy", biomeId = b.id, uid = "e1" })
					local zone = H.map.zones[b.id]
					H.teleport(p, zone.centerX + 30, 3, zone.centerZ)
					H.advance(0.2)
					local model, humanoid
					for _, m in H.map.folders.Guardians.children do
						if m:GetAttribute("BiomeId") == b.id and not m.destroyed then
							model = m
						end
					end
					T.truthy(model ~= nil, b.id .. " 경비")
					for _, child in model.children do
						if child.ClassName == "Humanoid" then
							humanoid = child
						end
					end
					T.eq(model:GetAttribute("State"), "Chase", b.id)
					T.near(humanoid.WalkSpeed, SpeedMath.guardChaseSpeed(b.guardSpeed), 1e-9, b.id)
					T.truthy(humanoid.WalkSpeed <= Config.SPEED_WALK_MAX, b.id .. " 추격 속도 상한")
					H.eggs.carried[p] = nil
					H.teleport(p, 0, 3, -60)
					H.advance(0.5)
				end
				T.eq(#H.warnings, 0, tostring(H.warnings[1]))
			end)
		end
	)

	T.test(
		"진짜 EggService: 버그 차원 해커 글리치 공지 씨앗 → 공지·줍기·배달, 가방 씨앗 Required 는 표 60일 ÷ 3 = 20일",
		function()
			inWorld({ realEgg = true }, function(H)
				local EggService = H.server("Services/EggService")
				EggService.start()
				H.server("Services/BaseService").start()
				local p = H.newPlayer(3301, "Thief7")
				local session, data = H.login(p)
				session.plotIndex = 1
				H.spawn(p, 0, 3, 0)
				H.setPhase("Intermission", 1)
				H.setPhase("Day", 1)
				H.clearSent()
				local uid = EggService.spawnSpecialEgg("bug_dimension", "static_world_tree", { announce = true })
				T.truthy(uid ~= nil, "특별 씨앗이 놓임")
				local egg
				for _, part in H.map.folders.Eggs.children do
					if part:GetAttribute("EggUid") == uid then
						egg = part
					end
				end
				T.truthy(egg ~= nil)
				T.eq(egg:GetAttribute("Rarity"), "hacker_glitch")
				local announce = H.remotes.Announce.firedAll
				local last = announce[#announce][1]
				T.eq(last.kind, "rareEgg")
				T.eq(last.rarity, "hacker_glitch")
				T.eq(last.biomeId, "bug_dimension")
				H.teleport(p, egg.Position.X, egg.Position.Y, egg.Position.Z)
				egg:FindFirstChild("StealPrompt").Triggered:Fire(p)
				local carried = EggService.getCarried(p)
				T.truthy(carried ~= nil and carried.petId == "static_world_tree", "씨앗을 듦")
				carried.originAt -= 1000 -- 한참 걸려서 온 것으로 (너무 빠른 배달 검사 통과)
				H.advance(1)
				H.server("Sessions").exemptMovement(session, 5) -- 서버가 옮긴 것처럼 (아니면 4,000 스터드 순간이동으로 걸려 씨앗을 뺏김: 정상)
				H.teleport(p, 0, 3, -60)
				H.advance(1)
				T.eq(EggService.getCarried(p), nil, "배달됨")
				T.eq(
					#data.eggs,
					1,
					"배달 안 됨: "
						.. tostring(H.warnings[1])
						.. " / "
						.. tostring((H.lastNotify(p) or {}).text)
						.. " / z="
						.. tostring(p.Character.root.Position.Z)
				)
				T.eq(data.eggs[1].petId, "static_world_tree")
				T.eq(data.eggs[1].biomeId, "bug_dimension")
				T.eq(data.eggs[1].required, 60 * 86400 / 3)
				T.eq(data.eggs[1].progress, 0)
			end)
		end
	)

	------------------------------------------------------------------
	T.suite(
		"7판 주임 검수: 무작위 요청 시험 (두 사람, 새 구역 식물, 업그레이드·트레일 포함)"
	)

	T.test(
		"A 가 온갖 값으로 10가지 Remote 를 1000번 던져도 코인·가방·정원이 안 깨지고 B 것은 그대로",
		function()
			withWorld(function(w)
				local H = w.H
				local rand = T.rng(70701)
				local function pick(list)
					return list[math.floor(rand() * #list) + 1]
				end
				local newPlants = {
					"static_world_tree",
					"glitch_hacker_bloom",
					"upside_down_tree",
					"mainframe_tree",
					"circuit_sprout",
					"bug_catcher_bloom",
				}
				local oldPlants = { "sprout_daisy", "owl_oak", "rune_rose", "puppy_grass", "crystal_snowdrop" }
				local seedPool = {
					"static_world_tree",
					"upside_down_tree",
					"rune_rose",
					"owl_oak",
					"sprout_daisy",
					"puppy_grass",
					"yeti_cabbage",
				}
				for _, id in newPlants do
					addPlant(w, w.A, w.dataA, id, 3)
				end
				for _, id in oldPlants do
					addPlant(w, w.A, w.dataA, id, 2)
				end
				for i = 1, 3 do
					plantSeed(w, w.A, w.dataA, 1, seedPool[i])
				end
				for _ = 1, 5 do
					w.BaseService.grantEgg(w.A, "static_world_tree", "normal", {}, "sakura")
				end
				w.dataA.fruits.static_world_tree = { count = 30, value = 30 * 3.3e15 }
				w.dataA.fruits.owl_oak = { count = 250, value = 250 * 180 }
				w.dataA.fruits.sprout_daisy = { count = 10, value = 100 }
				w.dataA.money = 5000
				for _, id in { "sprout_daisy", "owl_oak", "glitch_hacker_bloom" } do
					addPlant(w, w.B, w.dataB, id, 5)
				end
				plantSeed(w, w.B, w.dataB, 2, "rune_rose")
				w.dataB.fruits.owl_oak = { count = 10, value = 1800 }
				w.dataB.money = 12345
				w.dataB.sakuraCrystals = 7
				table.insert(w.dataB.trails, "grey")
				w.dataB.equippedTrail = "grey"
				w.dataB.treadmillLevel = 2
				H.clearSent()
				local bStart = {}
				for _, r in w.dataB.pets do
					bStart[r.uid] = r.uid .. "=" .. table.concat(r.mutations, "+") .. "/" .. r.size
				end
				local function lockedB()
					local d = w.dataB
					local fr = {}
					for id, st in d.fruits do
						table.insert(fr, id .. ":" .. st.count .. ":" .. st.value)
					end
					table.sort(fr)
					local muts = {}
					for _, r in d.pets do
						if bStart[r.uid] then
							table.insert(muts, r.uid .. "=" .. table.concat(r.mutations, "+") .. "/" .. r.size)
						end
					end
					table.sort(muts)
					return table.concat({
						tostring(d.money),
						tostring(d.sakuraCrystals),
						#d.eggs,
						d.penLevel,
						d.treadmillLevel,
						table.concat(d.trails, ","),
						d.equippedTrail,
						table.concat(fr, ","),
						table.concat(muts, ","),
					}, "|")
				end
				local lockedBefore = lockedB()

				local function check(label)
					for who, data in { A = w.dataA, B = w.dataB } do
						local tag = who .. " " .. label
						T.truthy(
							finite(data.money) and data.money >= 0 and data.money <= w.Config.MONEY_MAX,
							tag .. ": 코인 " .. tostring(data.money)
						)
						local total = 0
						for id, stack in data.fruits do
							T.truthy(Plants.get(id) ~= nil, tag .. ": 모르는 열매 칸")
							T.truthy(isInt(stack.count) and stack.count >= 1, tag .. ": 열매 개수")
							T.truthy(finite(stack.value) and stack.value >= 0, tag .. ": 열매 값")
							total += stack.count
						end
						T.truthy(total <= w.Config.FRUIT_BAG_MAX, tag .. ": 열매 가방 " .. total)
						T.truthy(#data.eggs <= w.Config.EGG_INVENTORY_MAX, tag .. ": 씨앗 가방")
						T.truthy(
							#data.pets + #data.incubators <= w.GardenRules.capacity(data.penLevel),
							tag .. ": 정원 칸"
						)
						T.truthy(
							isInt(data.penLevel) and data.penLevel >= 1 and data.penLevel <= Upgrades.PEN_MAX_LEVEL,
							tag .. ": 정원 레벨"
						)
						T.truthy(
							isInt(data.treadmillLevel)
								and data.treadmillLevel >= 0
								and data.treadmillLevel <= Upgrades.TREADMILL_MAX_LEVEL,
							tag .. ": 러닝머신 레벨"
						)
						T.truthy(isInt(data.sakuraCrystals) and data.sakuraCrystals >= 0, tag .. ": 크리스탈")
						local owned = {}
						for _, id in data.trails do
							T.truthy(
								Upgrades.getTrail(id) ~= nil and not owned[id],
								tag .. ": 트레일 " .. tostring(id)
							)
							owned[id] = true
						end
						T.truthy(
							data.equippedTrail == Upgrades.NO_TRAIL or owned[data.equippedTrail],
							tag .. ": 안 가진 트레일 장착"
						)
						local seen = {}
						for _, r in data.pets do
							T.truthy(
								isInt(r.fruits) and r.fruits >= 0 and r.fruits <= w.Config.FRUIT_MAX_PER_PLANT,
								tag .. ": 식물 열매"
							)
							T.truthy(not seen[r.uid], tag .. ": uid 겹침")
							seen[r.uid] = true
						end
						for _, r in data.incubators do
							T.truthy(
								finite(r.progress) and r.progress >= 0 and r.progress <= r.required,
								tag .. ": 진행도"
							)
							T.truthy(not seen[r.uid], tag .. ": uid 겹침")
							seen[r.uid] = true
						end
						for _, r in data.eggs do
							T.truthy(not seen[r.uid], tag .. ": uid 겹침")
							seen[r.uid] = true
						end
					end
					T.eq(#H.warnings, 0, label .. ": 서버 warn " .. tostring(H.warnings[1]))
				end
				check("시작")

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
					"",
					"all",
					"half",
					"Pen",
					"Trail",
					"none",
					"grey",
					string.rep("x", 100),
					"../x",
					"한글",
					{},
					{ 1 },
				}
				local function uidPool()
					local pool = {}
					for _, d in { w.dataA, w.dataB } do
						for _, list in { d.pets, d.incubators, d.eggs } do
							for _, r in list do
								table.insert(pool, r.uid)
							end
						end
					end
					return pool
				end
				local function uidArg()
					local roll = rand()
					if roll < 0.6 then
						local pool = uidPool()
						if #pool > 0 then
							return pick(pool)
						end
					elseif roll < 0.67 then
						return nil
					end
					return pick(junk)
				end
				local trailIds = {}
				for _, t in Upgrades.Trails do
					table.insert(trailIds, t.id)
				end
				local remotes = {
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
					"PurchaseUpgrade",
					"PurchaseUpgrade",
					"EquipTrail",
				}
				local penA = H.MapLayout.penRect(1)
				local stall = H.MapLayout.hubSpots.sellStall
				local fx, fz = H.zoneSpot("bug_dimension")
				local spots = {
					{ (penA.xMin + penA.xMax) / 2, (penA.zMin + penA.zMax) / 2 },
					{ stall.x, stall.z },
					{ fx, fz },
					{ penA.xMin - 15, penA.zMin },
				}
				local did = { sell = 0, skip = 0, buy = 0, equip = 0 }
				for step = 1, 1000 do
					local at = pick(spots)
					H.spawn(w.A, at[1], 3, at[2])
					H.landmarks.nearName = if rand() < 0.5 then "SakuraIncubator" else nil
					if rand() < 0.08 then
						H.setPhase(if H.cycle.phase == "Night" then "Day" else "Night")
					end
					if rand() < 0.12 then
						w.dataA.money =
							pick({ 0, 5, 49, 160, 1000, 1e6, 1e12, 1e18, w.Config.MONEY_MAX - 1, w.Config.MONEY_MAX })
					end
					if rand() < 0.05 then
						w.dataA.sakuraCrystals = pick({ 0, 9, 10, 19, 100 })
					end
					if
						step % 20 == 0
						and #w.dataA.incubators < 3
						and #w.dataA.pets + #w.dataA.incubators < 12
						and #w.dataA.eggs < 40
					then
						plantSeed(w, w.A, w.dataA, 1, pick(seedPool))
					end
					H.advance(pick({ 0.3, 1, 2, 5, 15, 40, 90 }))
					H.spawn(w.A, at[1], 3, at[2])
					local name = pick(remotes)
					local label = name .. " #" .. step
					local moneyBefore = w.dataA.money
					local expectCost, expectSell
					local a1, a2, a3
					if name == "PickFruit" then
						a1 = if rand() < 0.3 then "all" else uidArg()
					elseif name == "FeedFruit" then
						a1 = uidArg()
						a2 = if rand() < 0.6
							then pick({ "static_world_tree", "owl_oak", "sprout_daisy", "nope" })
							else pick(junk)
					elseif name == "SkipGrowth" then
						a1, a2 = uidArg(), if rand() < 0.75 then pick({ "all", "half" }) else pick(junk)
						if rand() < 0.7 and #w.dataA.incubators > 0 then
							a1 = pick(w.dataA.incubators).uid
							if rand() < 0.5 then
								w.dataA.money = pick({ 100, 5000, 1e7, 1e12, 1e15 })
								moneyBefore = w.dataA.money
							end
						end
						for _, r in w.dataA.incubators do
							if r.uid == a1 and (a2 == "all" or a2 == "half") then
								local remaining = r.required - r.progress
								if a2 == "half" then
									remaining /= 2
								end
								if remaining > 0 then
									local timePart = math.max(1, math.ceil(remaining / 60 - 1e-9))
										* 10
										* SKIP_MULT[Plants.get(r.petId).rarity]
									-- 7판(사장님 2026-10-29): + 건너뛸 비율 × 열매 1개 값 × SKIP_FRUIT_FACTOR
									local fruitPart = (remaining / r.required)
										* w.H.shared("Economy").fruitValue(r.petId, "normal", {})
										* w.Config.SKIP_FRUIT_FACTOR
									expectCost = math.ceil(timePart + fruitPart)
								end
							end
						end
					elseif name == "SellPlant" then
						a1 = uidArg()
						for _, r in w.dataA.pets do
							if r.uid == a1 then
								expectSell = w.GardenRules.sellPrice(r)
							end
						end
					elseif name == "SakuraOffer" or name == "PickUpPlacedEgg" then
						a1 = uidArg()
					elseif name == "PlaceEgg" then
						a1 = uidArg()
						a2 = pick({ at[1], 0, 1e9, 0 / 0, "x", penA.xMin + 5 })
						a3 = pick({ at[2], 0, -1e9, penA.zMin + 5 })
					elseif name == "PurchaseUpgrade" then
						a1 = if rand() < 0.85 then pick({ "Pen", "Treadmill", "Trail", "Trail" }) else pick(junk)
						a2 = if rand() < 0.8 then pick(trailIds) else pick(junk)
						if a1 == "Pen" then
							local nextLevel = Upgrades.Pen[w.dataA.penLevel + 1]
							expectCost = if nextLevel then nextLevel.cost else nil
						elseif a1 == "Treadmill" then
							local nextLevel = Upgrades.Treadmill[w.dataA.treadmillLevel + 1]
							expectCost = if nextLevel then nextLevel.cost else nil
						elseif a1 == "Trail" then
							local trail = Upgrades.getTrail(tostring(a2))
							if trail and not table.find(w.dataA.trails, trail.id) then
								expectCost = trail.cost
							end
						end
						if rand() < 0.4 then
							w.dataA.money = pick({ 1e3, 1e9, 1e15, 1e21, 1e24 })
							moneyBefore = w.dataA.money
						end
					elseif name == "EquipTrail" then
						a1 = if rand() < 0.8 then pick({ "none", table.unpack(trailIds) }) else pick(junk)
					end
					local trailsBefore = #w.dataA.trails
					local equippedBefore = w.dataA.equippedTrail
					local fruitsBefore = w.FruitRules.bagValue(w.dataA.fruits)
					H.client(w.A, name, a1, a2, a3)
					local delta = w.dataA.money - moneyBefore
					if name == "SellFruits" then
						local slack = moneyBefore * 1e-14 + 1e-6
						T.truthy(
							delta >= -slack
								and (delta <= fruitsBefore * (1 + 1e-12) + slack or w.dataA.money == w.Config.MONEY_MAX),
							label .. ": 열매 값보다 많이 받음"
						)
						if delta > 0 then
							did.sell += 1
						end
					elseif name == "SellPlant" then
						if delta > 0 then
							did.sell += 1
							T.truthy(
								expectSell ~= nil
									and (
										math.abs(delta - expectSell) <= moneyBefore * 1e-14 + 1e-6
										or w.dataA.money == w.Config.MONEY_MAX
									),
								label .. ": 성체 값이 다름 " .. delta .. " vs " .. tostring(expectSell)
							)
						else
							T.truthy(delta == 0, label .. ": 코인이 줄어듦")
						end
					elseif name == "SkipGrowth" then
						if delta ~= 0 then
							did.skip += 1
							T.truthy(
								expectCost ~= nil and math.abs(-delta - expectCost) <= moneyBefore * 1e-14 + 1e-6,
								label .. ": 건너뛰기 값이 다름 " .. -delta .. " vs " .. tostring(expectCost)
							)
						end
					elseif name == "PurchaseUpgrade" then
						if delta ~= 0 then
							did.buy += 1
							T.truthy(
								expectCost ~= nil and math.abs(-delta - expectCost) <= moneyBefore * 1e-14 + 1e-6,
								label .. ": 구매 값이 다름 " .. -delta .. " vs " .. tostring(expectCost)
							)
						end
						T.truthy(#w.dataA.trails >= trailsBefore, label .. ": 트레일이 줄어듦")
					elseif name == "EquipTrail" then
						T.truthy(delta == 0, label .. ": 장착으로 돈이 바뀜")
						if w.dataA.equippedTrail ~= equippedBefore then
							did.equip += 1
						end
					else
						T.truthy(delta == 0, label .. ": 돈이 바뀜 " .. delta)
					end
					check(label)
					T.eq(
						lockedB(),
						lockedBefore,
						label
							.. ": B 의 것이 바뀜 (코인·크리스탈·가방·업그레이드·트레일·돌연변이)"
					)
				end
				T.truthy(
					did.sell > 5 and did.skip > 5 and did.buy > 5 and did.equip > 5,
					string.format(
						"시험이 너무 약함: 팔기 %d 건너뛰기 %d 구매 %d 장착 %d",
						did.sell,
						did.skip,
						did.buy,
						did.equip
					)
				)
			end)
		end
	)
end
