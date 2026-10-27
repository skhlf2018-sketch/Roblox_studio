--!nocheck
--[[
	저장 데이터 안전성 (6판 "씨앗을 훔치세요", 스키마 6):
	  - 5판 이하(계란 훔치기) 데이터 → 6: 속도·트레일·러닝머신 레벨만 남기고 초기화 (사장님 지시: 새 게임, 새 사람처럼)
	  - 엉터리 데이터(nil, 문자열, 음수, 거대 수, NaN, inf, 이상한 표 ...)를 넣어도 터지지 않고 올바른 기본값/보정값이 나오는지
	  - 무작위 쓰레기 데이터(퍼징)로 수천 번 돌려도 항상 "올바른 PlayerData" 규칙을 지키는지, 두 번 보정해도 그대로인지
]]

return function(T, Loader)
	local DataSchema = Loader.require("ServerScriptService/Server/Logic/DataSchema")
	local Validate = Loader.require("ServerScriptService/Server/Logic/Validate")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Plants = Loader.require("ReplicatedStorage/Shared/Data/Plants")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Upgrades = Loader.require("ReplicatedStorage/Shared/Data/Upgrades")
	local Weapons = Loader.require("ReplicatedStorage/Shared/Data/Weapons")
	local Tutorial = Loader.require("ReplicatedStorage/Shared/Data/Tutorial")
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
	local EggPlacement = Loader.require("ReplicatedStorage/Shared/EggPlacement")
	local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")

	local NAN = 0 / 0

	------------------------------------------------------------------
	-- "올바른 PlayerData" 규칙 (reconcile 결과는 항상 이걸 지켜야 함). 어긴 게 있으면 설명 글을, 없으면 nil.
	------------------------------------------------------------------
	local function finiteNonNegative(v)
		return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v >= 0
	end

	local function isInt(v, lo, hi)
		return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
	end

	local function checkValid(d)
		if type(d) ~= "table" then
			return "표가 아님"
		end
		if d.version ~= Config.SCHEMA_VERSION then
			return "version " .. tostring(d.version)
		end
		for _, key in { "money", "speed", "lastSaveTime", "sakuraCrystals" } do
			if not finiteNonNegative(d[key]) then
				return key .. " 이 이상함: " .. tostring(d[key])
			end
		end
		if not isInt(d.penLevel, 1, Upgrades.PEN_MAX_LEVEL) then
			return "penLevel " .. tostring(d.penLevel)
		end
		if not isInt(d.treadmillLevel, 0, Upgrades.TREADMILL_MAX_LEVEL) then
			return "treadmillLevel " .. tostring(d.treadmillLevel)
		end
		if type(d.indexCompleteClaimed) ~= "boolean" then
			return "indexCompleteClaimed 이 boolean 이 아님"
		end
		-- 없앤 칸 (5판 퀘스트·무료 보상, 6판 장착·사쿠라 해금·비밀 통로·대기 줄)은 없어야 함
		for _, key in
			{
				"quests",
				"questsRewarded",
				"freeRewardClaimed",
				"equipped",
				"sakuraUnlocked",
				"shrineUsed",
				"eggQueue",
				"resetFromVersion",
			}
		do
			if d[key] ~= nil then
				return "없앤 칸 " .. key .. " 이 남음"
			end
		end
		if not isInt(d.tutorialStep, 1, Tutorial.DONE) then
			return "tutorialStep " .. tostring(d.tutorialStep)
		end
		local uids = {}
		local maxNumber = 0
		local function noteUid(uid, where)
			if type(uid) ~= "string" or #uid == 0 or #uid > 48 then
				return where .. " uid 이상함"
			end
			if uids[uid] then
				return where .. " uid 중복 " .. uid
			end
			uids[uid] = true
			maxNumber = math.max(maxNumber, tonumber(string.match(uid, "(%d+)$")) or 0)
			return nil
		end
		-- 정원: 성체 + 자라는 씨앗 ≤ 정원 칸 수, 자리는 정원 안·서로 간격
		local taken = {}
		local function checkSpot(e, where)
			local ok = type(e.x) == "number" and type(e.z) == "number" and EggPlacement.check(e.x, e.z, e.size, taken)
			if not ok then
				return where .. " 자리 " .. tostring(e.x) .. ", " .. tostring(e.z)
			end
			table.insert(taken, { x = e.x, z = e.z, size = e.size })
			return nil
		end
		for i, p in d.pets do
			local where = "pets[" .. i .. "]"
			local err = noteUid(p.uid, where)
			if err then
				return err
			end
			if not Plants.get(p.petId) then
				return "모르는 식물 " .. tostring(p.petId)
			end
			if not Sizes.get(p.size) then
				return "모르는 size " .. tostring(p.size)
			end
			if not Economy.isValidMutationSet(p.mutations) then
				return "돌연변이 조합 " .. table.concat(p.mutations, ",")
			end
			if not isInt(p.fruits, 0, Config.FRUIT_MAX_PER_PLANT) then
				return where .. " fruits " .. tostring(p.fruits)
			end
			if not finiteNonNegative(p.fruitProgress) or p.fruitProgress > Economy.fruitInterval(p.petId) then
				return where .. " fruitProgress " .. tostring(p.fruitProgress)
			end
			err = checkSpot(p, where)
			if err then
				return err
			end
		end
		local trails = {}
		for _, id in d.trails do
			if not Upgrades.getTrail(id) or trails[id] then
				return "트레일 " .. tostring(id)
			end
			trails[id] = true
		end
		if d.equippedTrail ~= Upgrades.NO_TRAIL and not trails[d.equippedTrail] then
			return "장착 트레일이 보관 목록에 없음 " .. tostring(d.equippedTrail)
		end
		for id in d.indexDiscovered do
			if not Plants.get(id) then
				return "도감 발견에 모르는 식물 " .. tostring(id)
			end
		end
		for id in d.indexClaimed do
			if not d.indexDiscovered[id] then
				return "받은 도감 보상이 발견 안 한 식물 " .. tostring(id)
			end
		end
		if not isInt(d.tools.bearTrap, 0, 999) then
			return "곰덫 개수 " .. tostring(d.tools.bearTrap)
		end
		-- 씨앗 공통 (심은 씨앗·가방 씨앗)
		local function checkEgg(e, where)
			local err = noteUid(e.uid, where)
			if err then
				return err
			end
			local plant = Plants.get(e.petId)
			if not plant then
				return where .. " 모르는 식물"
			end
			if e.biomeId ~= plant.biome then
				return where .. " biomeId"
			end
			if type(e.special) ~= "boolean" then
				return where .. " special"
			end
			if not finiteNonNegative(e.progress) or e.progress > e.required + 1e-9 then
				return where .. " progress " .. tostring(e.progress)
			end
			if e.required ~= Economy.growSeconds(e.petId) then
				return where .. " required 가 지금 성장 시간과 다름"
			end
			if not Sizes.get(e.size) or not Economy.isValidMutationSet(e.mutations) then
				return where .. " 크기/돌연변이"
			end
			return nil
		end
		for i, e in d.incubators do
			local where = "incubators[" .. i .. "]"
			local err = checkEgg(e, where) or checkSpot(e, where)
			if err then
				return err
			end
			if e.slot ~= nil then
				return where .. " 옛 슬롯 번호가 남음"
			end
		end
		if #d.pets + #d.incubators > Economy.penSlots(d.penLevel) then
			return "정원 칸 수 초과"
		end
		if type(d.eggs) ~= "table" or #d.eggs > Config.EGG_INVENTORY_MAX then
			return "씨앗 가방 초과"
		end
		for i, e in d.eggs do
			local err = checkEgg(e, "eggs[" .. i .. "]")
			if err then
				return err
			end
			if e.x ~= nil or e.slot ~= nil then
				return "가방 씨앗에 자리가 있음"
			end
		end
		-- 열매 가방
		if type(d.fruits) ~= "table" then
			return "fruits 가 표가 아님"
		end
		local fruitTotal = 0
		for id, stack in d.fruits do
			if not Plants.get(id) then
				return "열매 가방에 모르는 식물 " .. tostring(id)
			end
			if not isInt(stack.count, 1, Config.FRUIT_BAG_MAX) or not finiteNonNegative(stack.value) then
				return "열매 칸 " .. tostring(id)
			end
			fruitTotal += stack.count
		end
		if fruitTotal > Config.FRUIT_BAG_MAX then
			return "열매 가방 초과 " .. fruitTotal
		end
		if type(d.nextUid) ~= "number" or d.nextUid ~= d.nextUid or d.nextUid <= maxNumber then
			return "nextUid " .. tostring(d.nextUid) .. " ≤ 기존 uid 번호 " .. maxNumber
		end
		for key, value in d.stats do
			if type(key) ~= "string" or not finiteNonNegative(value) then
				return "stats " .. tostring(key)
			end
		end
		for _, id in d.weapons do
			local weapon = Weapons.get(id)
			if not weapon or not weapon.biome then
				return "무기 " .. tostring(id)
			end
		end
		return nil
	end

	-- 정렬된 글자로 바꿔 두 표가 똑같은지 비교
	local function canonical(v)
		if type(v) ~= "table" then
			if type(v) == "string" then
				return string.format("%q", v)
			end
			return tostring(v)
		end
		local keys = {}
		for k in v do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, k in keys do
			table.insert(parts, tostring(k) .. "=" .. canonical(v[k]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end

	------------------------------------------------------------------
	T.suite("저장 데이터: 5판 이하 → 6 (새 게임 초기화, 속도·트레일·러닝머신만 남김)")

	-- 5판 계란 훔치기의 다 큰 저장 데이터
	local function v5Save()
		return {
			version = 5,
			money = 1e15,
			speed = 987654321,
			pets = {
				{ uid = "p1", petId = "chicken", size = "big", mutations = { "silver" } },
				{ uid = "p2", petId = "ghost_king", size = "giant", mutations = { "golden", "bloom" } },
			},
			equipped = { "p2", "p1" },
			penLevel = 9,
			treadmillLevel = 7,
			trails = { "grey", "blue", "moonbloom" },
			equippedTrail = "blue",
			indexDiscovered = { chicken = true, ghost_king = true },
			indexClaimed = { chicken = true },
			indexCompleteClaimed = true,
			tools = { bearTrap = 77 },
			incubators = {
				{
					uid = "i3",
					petId = "dog",
					size = "normal",
					mutations = {},
					x = -20,
					z = 0,
					progress = 2,
					required = 3,
				},
			},
			eggs = { { uid = "i4", petId = "axolotl", size = "huge", mutations = {}, progress = 0, required = 300 } },
			lastSaveTime = 1700000000,
			nextUid = 50,
			stats = { eggsStolen = 400, eggsHatched = 300, eggsDelivered = 350 },
			weapons = { "water_bat", "katana", "scythe" },
			sakuraCrystals = 999,
			sakuraUnlocked = true,
			shrineUsed = { equinox = true },
			tutorialStep = 6,
		}
	end

	T.test(
		"5판 데이터: 속도·트레일·장착 트레일·러닝머신만 남고 나머지는 새 사람처럼 (튜토리얼 1단계)",
		function()
			local migrated = DataSchema.migrate(v5Save())
			T.eq(migrated.version, 6)
			local d = DataSchema.reconcile(migrated, 1700001000)
			T.eq(checkValid(d), nil)
			T.eq(d.speed, 987654321, "속도")
			T.eq(#d.trails, 3, "트레일")
			T.eq(d.equippedTrail, "blue", "장착 트레일")
			T.eq(d.treadmillLevel, 7, "러닝머신")
			T.eq(d.money, Config.STARTING_MONEY, "코인은 처음부터")
			T.eq(d.penLevel, 1)
			T.eq(#d.pets, 0)
			T.eq(#d.incubators, 0)
			T.eq(#d.eggs, 0)
			T.eq(next(d.fruits), nil)
			T.eq(next(d.indexDiscovered), nil)
			T.eq(next(d.indexClaimed), nil)
			T.falsy(d.indexCompleteClaimed)
			T.eq(d.tools.bearTrap, Config.STARTING_BEAR_TRAPS)
			T.eq(#d.weapons, 0)
			T.eq(d.sakuraCrystals, 0)
			T.eq(d.stats.eggsStolen, 0)
			T.eq(d.lastSaveTime, 0)
			T.eq(d.tutorialStep, 1)
			T.eq(d.nextUid, 1)
		end
	)

	T.test(
		"버전 1·2·3·4·5 모두 6 으로 한 번에, 3 이전(장착 트레일 칸 없음)은 가진 것 중 최고 배율을 장착",
		function()
			for _, version in { 1, 2, 3, 4, 5 } do
				local raw = v5Save()
				raw.version = version
				if version < 3 then
					raw.equippedTrail = nil
				end
				local d = DataSchema.reconcile(DataSchema.migrate(raw), 0)
				T.eq(checkValid(d), nil, "버전 " .. version)
				T.eq(d.speed, 987654321)
				T.eq(d.treadmillLevel, 7)
				T.eq(d.equippedTrail, if version < 3 then "moonbloom" else "blue", "버전 " .. version)
				T.eq(d.money, 0)
			end
			-- version 이 없으면 1 로 봄
			local nov = DataSchema.reconcile(DataSchema.migrate({ speed = 55, trails = { "green" } }), 0)
			T.eq(nov.speed, 55)
			T.eq(nov.equippedTrail, "green")
			T.eq(checkValid(nov), nil)
		end
	)

	T.test("6 데이터는 초기화하지 않음, 마이그레이션을 두 번 돌려도 같음", function()
		local six = DataSchema.default(0)
		six.money = 777
		six.penLevel = 2
		table.insert(six.pets, {
			uid = "p1",
			petId = "owl_oak",
			size = "normal",
			mutations = { "frozen" },
			x = -20,
			z = 0,
			fruits = 3,
			fruitProgress = 4,
		})
		six.fruits.owl_oak = { count = 2, value = 360 }
		six.nextUid = 2
		local d = DataSchema.reconcile(DataSchema.migrate(six), 0)
		T.eq(checkValid(d), nil)
		T.eq(d.money, 777)
		T.eq(d.pets[1].mutations[1], "frozen")
		T.eq(d.pets[1].fruits, 3)
		T.eq(d.fruits.owl_oak.value, 360)
		local once = DataSchema.reconcile(DataSchema.migrate(v5Save()), 5)
		local twice = DataSchema.reconcile(DataSchema.migrate(DataSchema.reconcile(DataSchema.migrate(v5Save()), 5)), 5)
		T.eq(canonical(once), canonical(twice))
	end)

	T.test("더 새 버전(7, 6.5, 1e9)은 새 버전으로 인식 — 변환하지 않음", function()
		for _, v in { 7, 6.5, 1e9 } do
			T.truthy(DataSchema.isNewerVersion({ version = v }), tostring(v))
			local raw = { version = v, money = 5, pets = { "미래 모양" } }
			local migrated = DataSchema.migrate(raw)
			T.eq(migrated.version, v)
			T.eq(migrated.money, 5)
		end
		T.falsy(DataSchema.isNewerVersion({ version = 6 }))
		T.falsy(DataSchema.isNewerVersion({ version = 5 }))
	end)

	------------------------------------------------------------------
	T.suite("저장 데이터: 엉터리 입력")

	T.test(
		"통째로 엉터리 (nil, 숫자, 문자열, 불리언, 빈 표, 배열, NaN, inf) → 항상 올바른 기본값",
		function()
			for i, garbage in { 5, "x", "한글", true, false, {}, { 1, 2, 3 }, NAN, math.huge, -math.huge, { { {} } } } do
				local ok, d = pcall(DataSchema.reconcile, garbage, 0)
				T.truthy(ok, "터짐 #" .. i .. ": " .. tostring(d))
				T.eq(checkValid(d), nil, "#" .. i)
				T.eq(d.money, Config.STARTING_MONEY)
				T.eq(d.speed, Config.STARTING_SPEED)
			end
			T.eq(checkValid(DataSchema.reconcile(nil, 0)), nil)
			for _, garbage in { 5, "x", true, {}, NAN } do
				T.truthy(pcall(DataSchema.migrate, garbage))
			end
		end
	)

	T.test("숫자 칸마다 쓰레기: 음수·NaN·inf·문자열·표·불리언 → 기본값", function()
		local garbage = { -1, -1e300, NAN, math.huge, -math.huge, "123", "abc", {}, { 1 }, true, false }
		for _, key in
			{
				"money",
				"speed",
				"lastSaveTime",
				"penLevel",
				"treadmillLevel",
				"nextUid",
				"sakuraCrystals",
				"tutorialStep",
			}
		do
			for _, bad in garbage do
				local ok, d = pcall(DataSchema.reconcile, { version = 6, [key] = bad }, 0)
				T.truthy(ok, key .. " = " .. tostring(bad) .. " 에서 터짐")
				T.eq(checkValid(d), nil, key .. " = " .. tostring(bad))
			end
		end
		local d = DataSchema.reconcile({ money = -5, speed = NAN, penLevel = "3", treadmillLevel = {} }, 0)
		T.eq(d.money, Config.STARTING_MONEY)
		T.eq(d.speed, Config.STARTING_SPEED)
		T.eq(d.penLevel, 1)
		T.eq(d.treadmillLevel, 0)
	end)

	T.test(
		"아주 큰 유한 수(1e300)는 상한까지, 소수 레벨은 내림, 범위 밖은 끝값으로",
		function()
			local d = DataSchema.reconcile(
				{ money = 1e300, speed = 1e300, penLevel = 3.9, treadmillLevel = 99, sakuraCrystals = 5e9 },
				0
			)
			T.eq(d.money, Config.MONEY_MAX)
			T.eq(d.speed, Config.SPEED_MAX)
			T.eq(d.penLevel, 3)
			T.eq(d.treadmillLevel, Upgrades.TREADMILL_MAX_LEVEL)
			T.eq(d.sakuraCrystals, Config.SAKURA_CRYSTAL_MAX)
			T.eq(checkValid(d), nil)
		end
	)

	T.test(
		"표 칸마다 쓰레기 (pets/trails/incubators/eggs/fruits/... 에 숫자·문자열·불리언·NaN)",
		function()
			local keys = {
				"pets",
				"equipped",
				"trails",
				"indexDiscovered",
				"indexClaimed",
				"tools",
				"incubators",
				"stats",
				"weapons",
				"shrineUsed",
				"quests",
				"tutorialStep",
				"eggQueue",
				"eggs",
				"fruits",
				"equippedTrail",
			}
			local garbage = { 5, "x", true, false, NAN, math.huge, { "a", "b" }, { a = 1 }, { {} }, { [1] = NAN } }
			for _, key in keys do
				for i, bad in garbage do
					local ok, d = pcall(DataSchema.reconcile, { version = 6, [key] = bad }, 0)
					T.truthy(ok, key .. " #" .. i .. " 에서 터짐: " .. tostring(d))
					T.eq(checkValid(d), nil, key .. " #" .. i)
				end
			end
		end
	)

	T.test(
		"성체 항목이 엉터리: 필드 빠짐·타입 틀림·모르는 id·중복 uid·너무 긴 uid → 그 항목만 버림",
		function()
			local d = DataSchema.reconcile({
				version = 6,
				pets = {
					{ uid = "ok1", petId = "sprout_daisy", size = "normal", mutations = {} },
					{ uid = "ok1", petId = "puppy_grass", size = "normal", mutations = {} },
					{ uid = "", petId = "puppy_grass" },
					{ uid = string.rep("x", 49), petId = "puppy_grass" },
					{ uid = 7, petId = "puppy_grass" },
					{ uid = "n1", petId = 5 },
					{ uid = "n2" },
					{ petId = "puppy_grass" },
					"문자열",
					5,
					true,
					{},
					{
						uid = "ok2",
						petId = "puppy_grass",
						size = {},
						mutations = "x",
						fruits = "많이",
						fruitProgress = NAN,
					},
					{
						uid = "ok3",
						petId = "owl_oak",
						size = "giant",
						mutations = { 5, {}, "silver", "silver", "golden", "frozen", "burning", "bloom" },
						x = math.huge,
						z = 0,
					},
				},
			}, 0)
			T.eq(checkValid(d), nil)
			T.eq(#d.pets, 3, "ok1, ok2, ok3 만 남음")
			T.eq(d.pets[1].petId, "sprout_daisy", "먼저 나온 중복 uid 가 이김")
			T.eq(d.pets[2].size, "normal", "이상한 크기는 보통")
			T.eq(#d.pets[2].mutations, 0)
			T.eq(d.pets[2].fruits, 0)
			T.eq(d.pets[2].fruitProgress, 0)
			T.eq(#d.pets[3].mutations, 2, "자연 하나 + 원소 하나만")
		end
	)

	T.test(
		"uid 가 정원(성체·씨앗)·가방 사이에서도 겹치지 않음, 위치 쓰레기는 빈 격자 자리로",
		function()
			local d = DataSchema.reconcile({
				version = 6,
				pets = { { uid = "x1", petId = "sprout_daisy", size = "normal", mutations = {}, x = 0, z = 0 } },
				incubators = {
					{ uid = "x1", petId = "puppy_grass", size = "normal", mutations = {}, x = 0, z = 0, progress = 0 },
					{
						uid = "x2",
						petId = "puppy_grass",
						size = "normal",
						mutations = {},
						x = 0,
						z = 0,
						progress = NAN,
					},
					{
						uid = "x3",
						petId = "puppy_grass",
						size = "normal",
						mutations = {},
						x = "1",
						z = {},
						progress = 0,
					},
					{ uid = "x4", petId = "puppy_grass", size = "normal", mutations = {}, x = math.huge, z = 0 },
					{ uid = "x5", petId = "puppy_grass", size = "normal", mutations = {}, x = -20, z = 10 },
				},
				eggs = {
					{ uid = "x2", petId = "puppy_grass", size = "normal", mutations = {} },
					{ uid = "x6", petId = "puppy_grass", size = "normal", mutations = {}, progress = -3, x = 5 },
					{ uid = "x6", petId = "owl_oak" },
					"쓰레기",
					{ uid = "x7", petId = "없는식물" },
				},
			}, 0)
			T.eq(checkValid(d), nil)
			T.eq(#d.pets, 1)
			T.eq(d.pets[1].x, 0, "성체는 제자리")
			T.eq(#d.incubators, 4)
			T.eq(d.incubators[1].uid, "x2")
			T.truthy(d.incubators[1].x ~= 0 or d.incubators[1].z ~= 0, "성체와 겹친 씨앗은 다른 자리로")
			T.eq(d.incubators[1].progress, 0, "NaN 진행도는 0")
			T.eq(d.incubators[4].x, -20, "멀쩡한 자리는 그대로")
			T.eq(#d.eggs, 1)
			T.eq(d.eggs[1].uid, "x6")
			T.eq(d.eggs[1].progress, 0)
			T.eq(d.eggs[1].x, nil, "가방 씨앗에는 자리가 없음")
		end
	)

	T.test(
		"nextUid 는 기존 uid 번호보다 항상 큼 (겹치는 새 uid 가 안 나옴), 반복해도 겹침 없음",
		function()
			local d = DataSchema.reconcile({
				version = 6,
				pets = { { uid = "p500", petId = "sprout_daisy", size = "normal", mutations = {} } },
				incubators = { { uid = "i900", petId = "puppy_grass", size = "normal", mutations = {}, progress = 0 } },
				eggs = { { uid = "i950", petId = "puppy_grass", size = "normal", mutations = {} } },
				nextUid = 3,
			}, 0)
			T.truthy(d.nextUid > 950)
			local seen = { p500 = true, i900 = true, i950 = true }
			for _ = 1, 2000 do
				local uid = DataSchema.newUid(d, "p")
				T.falsy(seen[uid], "uid 겹침 " .. uid)
				seen[uid] = true
				T.truthy(Validate.uid(uid) ~= nil, "새 uid 는 Remote 검사를 통과해야 함: " .. uid)
			end
		end
	)

	T.test(
		"성체 5,000그루 + 씨앗 5,000개 + 가방 5,000개 + 열매 칸 134개짜리 큰 데이터도 1초 안에, 넘치는 건 정리",
		function()
			local pets, incubators, eggs, fruits = {}, {}, {}, {}
			for i = 1, 5000 do
				table.insert(
					pets,
					{ uid = "p" .. i, petId = "sprout_daisy", size = "normal", mutations = {}, x = 0, z = 0 }
				)
				table.insert(
					incubators,
					{ uid = "i" .. i, petId = "puppy_grass", size = "normal", mutations = {}, x = 0, z = 0 }
				)
				table.insert(eggs, { uid = "e" .. i, petId = "puppy_grass", size = "normal", mutations = {} })
			end
			for _, plant in Plants.list do
				fruits[plant.id] = { count = 99, value = 1 }
			end
			local started = os.clock()
			local d = DataSchema.reconcile(
				{ version = 6, penLevel = 11, pets = pets, incubators = incubators, eggs = eggs, fruits = fruits },
				0
			)
			T.truthy(os.clock() - started < 1, "느림")
			T.eq(#d.pets, 18, "11레벨 정원 18칸")
			T.eq(#d.incubators, 0, "성체가 칸을 다 차지 → 씨앗은 가방으로")
			T.eq(#d.eggs, Config.EGG_INVENTORY_MAX)
			T.truthy(d.money > 0, "넘친 성체는 코인으로")
			T.eq(checkValid(d), nil)
		end
	)

	------------------------------------------------------------------
	T.suite("저장 데이터: 무작위 퍼징 (쓰레기 5,000개)")

	T.test(
		"아무 쓰레기를 넣어도 안 터지고 결과는 항상 올바른 PlayerData, 한 번 더 보정해도 그대로",
		function()
			local rand = T.rng(2026)
			local function pick(list)
				return list[math.floor(rand() * #list) + 1]
			end
			local scalars = {
				0,
				1,
				-1,
				0.5,
				3,
				7,
				20,
				1e9,
				1e300,
				-1e300,
				math.huge,
				-math.huge,
				NAN,
				true,
				false,
				"",
				"p1",
				"x",
				"sprout_daisy",
				"owl_oak",
				"silver",
				"grey",
				"forest",
				"katana",
				"한글",
				string.rep("z", 60),
			}
			local plantIds = {
				"sprout_daisy",
				"puppy_grass",
				"owl_oak",
				"rune_rose",
				"sky_pillar_flower",
				"blossom_fairy",
				"world_tree",
				"chicken",
				"없는식물",
			}
			local sizes = { "normal", "big", "huge", "giant", "엄청큼" }
			local muts = { "silver", "golden", "rainbow", "frozen", "burning", "shocked", "bloom", "모름" }
			local function garbage(depth)
				local roll = rand()
				if roll < 0.55 or depth > 2 then
					return pick(scalars)
				elseif roll < 0.8 then
					local t = {}
					for _ = 1, math.floor(rand() * 4) do
						table.insert(t, garbage(depth + 1))
					end
					return t
				else
					local t = {}
					for _ = 1, math.floor(rand() * 4) do
						local key = pick(scalars)
						if key == key then -- NaN 은 표 열쇠가 될 수 없음
							t[key] = garbage(depth + 1)
						end
					end
					return t
				end
			end
			local function maybe(good)
				if rand() < 0.5 then
					return good()
				end
				return garbage(0)
			end
			local function entry()
				return {
					uid = maybe(function()
						return "p" .. math.floor(rand() * 30)
					end),
					petId = maybe(function()
						return pick(plantIds)
					end),
					size = maybe(function()
						return pick(sizes)
					end),
					mutations = maybe(function()
						local list = {}
						for _ = 1, math.floor(rand() * 4) do
							table.insert(list, pick(muts))
						end
						return list
					end),
					x = maybe(function()
						return math.floor(rand() * 60) - 40
					end),
					z = maybe(function()
						return math.floor(rand() * 70) - 35
					end),
				}
			end
			local function listOf(make)
				return function()
					local list = {}
					for _ = 1, math.floor(rand() * 12) do
						table.insert(list, make())
					end
					return list
				end
			end
			for i = 1, 5000 do
				local raw = {
					version = maybe(function()
						return pick({ 1, 2, 3, 4, 5, 6, 6, 6 })
					end),
					tutorialStep = maybe(function()
						return pick({ 0, 1, 2, 3, 4, 5, 6, 7, 2.5, -1, "3", true })
					end),
					money = maybe(function()
						return rand() * 1e12
					end),
					speed = maybe(function()
						return rand() * 1e6
					end),
					penLevel = maybe(function()
						return math.floor(rand() * 14) - 1
					end),
					treadmillLevel = maybe(function()
						return math.floor(rand() * 14) - 1
					end),
					pets = maybe(listOf(function()
						local e = entry()
						e.fruits = maybe(function()
							return math.floor(rand() * 9) - 2
						end)
						e.fruitProgress = maybe(function()
							return rand() * 60
						end)
						return e
					end)),
					trails = maybe(listOf(function()
						return pick({ "grey", "green", "blue", "moonbloom", "가짜" })
					end)),
					equippedTrail = maybe(function()
						return pick({ "grey", "blue", "moonbloom", "none", "가짜", 7 })
					end),
					indexDiscovered = maybe(function()
						local t = {}
						for _ = 1, 6 do
							t[pick(plantIds)] = pick({ true, false, 1, "x" })
						end
						return t
					end),
					indexClaimed = maybe(function()
						local t = {}
						for _ = 1, 6 do
							t[pick(plantIds)] = pick({ true, false })
						end
						return t
					end),
					incubators = maybe(listOf(function()
						local e = entry()
						e.slot = maybe(function()
							return math.floor(rand() * 10)
						end)
						e.progress = maybe(function()
							return rand() * 1e5
						end)
						e.special = maybe(function()
							return rand() < 0.5
						end)
						return e
					end)),
					eggs = maybe(listOf(function()
						local e = entry()
						e.progress = maybe(function()
							return rand() * 1e5
						end)
						return e
					end)),
					fruits = maybe(function()
						local t = {}
						for _ = 1, 5 do
							t[pick(plantIds)] = maybe(function()
								return { count = math.floor(rand() * 200) - 20, value = rand() * 1e6 - 10 }
							end)
						end
						return t
					end),
					tools = maybe(function()
						return { bearTrap = maybe(function()
							return math.floor(rand() * 2000) - 5
						end) }
					end),
					stats = maybe(function()
						return { eggsStolen = maybe(function()
							return rand() * 50
						end) }
					end),
					weapons = maybe(listOf(function()
						return pick({ "katana", "scythe", "baseball_bat", "water_bat", "가짜" })
					end)),
					sakuraCrystals = maybe(function()
						return math.floor(rand() * 1e7)
					end),
					equipped = maybe(listOf(function()
						return "p" .. math.floor(rand() * 30)
					end)),
					nextUid = maybe(function()
						return math.floor(rand() * 100)
					end),
				}
				local ok, d = pcall(DataSchema.reconcile, DataSchema.migrate(raw), 0)
				T.truthy(ok, "퍼징 #" .. i .. " 에서 터짐: " .. tostring(d))
				local problem = checkValid(d)
				T.eq(problem, nil, "퍼징 #" .. i .. " 결과가 규칙 위반")
				-- 보정 결과를 다시 보정해도 그대로여야 함 (멱등)
				local again = DataSchema.reconcile(DataSchema.migrate(table.clone(d)), 0)
				if canonical(again) ~= canonical(d) then
					T.eq(canonical(again), canonical(d), "퍼징 #" .. i .. " 두 번 보정하면 달라짐")
				end
			end
			T.truthy(
				MapLayout.EGG_GRID_COUNT >= 18,
				"정원 칸 18칸 > 격자 자리 수면 넘친 칸은 코인으로"
			)
		end
	)
end
