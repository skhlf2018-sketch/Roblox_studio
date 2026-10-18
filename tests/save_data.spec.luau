--!nocheck
--[[
	저장 데이터 안전성:
	  - 버전 1 → 2 마이그레이션이 옛 데이터를 하나도 안 잃는지
	  - 엉터리 데이터(nil, 문자열, 음수, 거대 수, NaN, inf, 이상한 표 ...)를 넣어도 터지지 않고 올바른 기본값/보정값이 나오는지
	  - 무작위 쓰레기 데이터(퍼징)로 수천 번 돌려도 항상 "올바른 PlayerData" 규칙을 지키는지
]]

return function(T, Loader)
	local DataSchema = Loader.require("ServerScriptService/Server/Logic/DataSchema")
	local Validate = Loader.require("ServerScriptService/Server/Logic/Validate")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Upgrades = Loader.require("ReplicatedStorage/Shared/Data/Upgrades")
	local Weapons = Loader.require("ReplicatedStorage/Shared/Data/Weapons")
	local Quests = Loader.require("ReplicatedStorage/Shared/Data/Quests")
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
	local AltarRules = Loader.require("ReplicatedStorage/Shared/AltarRules")

	local NAN = 0 / 0

	------------------------------------------------------------------
	-- "올바른 PlayerData" 규칙 (reconcile 결과는 항상 이걸 지켜야 함). 어긴 게 있으면 설명 글을, 없으면 nil.
	------------------------------------------------------------------
	local function finiteNonNegative(v)
		return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v >= 0
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
		if
			type(d.penLevel) ~= "number"
			or d.penLevel % 1 ~= 0
			or d.penLevel < 1
			or d.penLevel > Upgrades.PEN_MAX_LEVEL
		then
			return "penLevel " .. tostring(d.penLevel)
		end
		if
			type(d.treadmillLevel) ~= "number"
			or d.treadmillLevel % 1 ~= 0
			or d.treadmillLevel < 0
			or d.treadmillLevel > Upgrades.TREADMILL_MAX_LEVEL
		then
			return "treadmillLevel " .. tostring(d.treadmillLevel)
		end
		for _, key in { "freeRewardClaimed", "indexCompleteClaimed", "sakuraUnlocked", "questsRewarded" } do
			if type(d[key]) ~= "boolean" then
				return key .. " 이 boolean 이 아님"
			end
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
		local petUids = {}
		for i, p in d.pets do
			local err = noteUid(p.uid, "pets[" .. i .. "]")
			if err then
				return err
			end
			petUids[p.uid] = true
			if not Pets.get(p.petId) then
				return "모르는 petId " .. tostring(p.petId)
			end
			if not Sizes.get(p.size) then
				return "모르는 size " .. tostring(p.size)
			end
			if not Economy.isValidMutationSet(p.mutations) then
				return "돌연변이 조합 " .. table.concat(p.mutations, ",")
			end
		end
		local slots = Economy.penSlots(d.penLevel)
		if #d.equipped > slots then
			return "장착이 칸 수 초과"
		end
		local seenEquipped = {}
		for _, uid in d.equipped do
			if not petUids[uid] then
				return "장착한 uid 가 보관함에 없음 " .. tostring(uid)
			end
			if seenEquipped[uid] then
				return "장착 중복"
			end
			seenEquipped[uid] = true
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
			if not Pets.get(id) then
				return "도감 발견에 모르는 펫 " .. tostring(id)
			end
		end
		for id in d.indexClaimed do
			if not d.indexDiscovered[id] then
				return "받은 도감 보상이 발견 안 한 펫 " .. tostring(id)
			end
		end
		if
			type(d.tools.bearTrap) ~= "number"
			or d.tools.bearTrap < 0
			or d.tools.bearTrap > 999
			or d.tools.bearTrap % 1 ~= 0
		then
			return "곰덫 개수 " .. tostring(d.tools.bearTrap)
		end
		local slotsUsed = {}
		for i, e in d.incubators do
			local err = noteUid(e.uid, "incubators[" .. i .. "]")
			if err then
				return err
			end
			if not Pets.get(e.petId) then
				return "부화 슬롯에 모르는 펫"
			end
			if
				type(e.slot) ~= "number"
				or e.slot % 1 ~= 0
				or e.slot < 1
				or e.slot > Config.INCUBATOR_SLOTS
				or slotsUsed[e.slot]
			then
				return "슬롯 번호 " .. tostring(e.slot)
			end
			slotsUsed[e.slot] = true
			if not finiteNonNegative(e.progress) or e.progress > e.required + 1e-9 then
				return "progress " .. tostring(e.progress)
			end
			if e.required ~= Economy.hatchSeconds(e.petId) then
				return "required 가 현재 성장 배율과 다름"
			end
			if not Sizes.get(e.size) or not Economy.isValidMutationSet(e.mutations) then
				return "부화 슬롯 알 크기/돌연변이"
			end
		end
		if #d.incubators > Config.INCUBATOR_SLOTS then
			return "부화 슬롯 초과"
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
		for id in d.shrineUsed do
			local ok = false
			for _, recipe in AltarRules.RECIPES do
				ok = ok or recipe.result == id
			end
			if not ok then
				return "shrineUsed " .. tostring(id)
			end
		end
		for id, value in d.quests do
			local quest = Quests.get(id)
			if not quest or type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > quest.target then
				return "quests " .. tostring(id)
			end
		end
		if #d.eggQueue > Config.EGG_QUEUE_MAX then
			return "대기 줄 초과"
		end
		for _, q in d.eggQueue do
			if not Pets.get(q.petId) or not Sizes.get(q.size) or not Economy.isValidMutationSet(q.mutations) then
				return "대기 줄 알"
			end
			if q.source ~= "altar" and q.source ~= "shrine" and q.source ~= "quest" then
				return "대기 줄 출처 " .. tostring(q.source)
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
	T.suite("저장 데이터: 버전 1 → 2 마이그레이션")

	local function v1Save()
		return {
			version = 1,
			money = 123456,
			speed = 9999,
			pets = {
				{ uid = "p1", petId = "chicken", size = "big", mutations = { "silver" } },
				{ uid = "p2", petId = "dog", size = "normal", mutations = {} },
				{ uid = "p3", petId = "king_snake", size = "giant", mutations = { "golden" } },
			},
			equipped = { "p3", "p1" },
			penLevel = 3,
			treadmillLevel = 2,
			trails = { "grey", "blue" },
			indexDiscovered = {
				chicken = true,
				dog = true,
				king_snake = true,
				frog = true,
				duckling = true,
				catfish = true,
				turtle = true,
				trulimero_trulicina = true,
				swan = true,
				axolotl = true,
				leviathan = true,
			},
			indexClaimed = { chicken = true, dog = true },
			indexCompleteClaimed = false,
			tools = { bearTrap = 7 },
			incubators = {
				{
					uid = "i4",
					petId = "bear",
					size = "huge",
					mutations = { "rainbow" },
					slot = 2,
					progress = 12.5,
					required = 30,
				},
			},
			lastSaveTime = 1700000000,
			freeRewardClaimed = true,
			nextUid = 5,
			stats = { eggsStolen = 40, eggsHatched = 3, eggsDelivered = 4 },
		}
	end

	T.test(
		"옛 데이터가 하나도 안 사라지고, 새 필드는 기본값, 호수 도감 완성이라 물 방망이가 자동 해금",
		function()
			local migrated = DataSchema.migrate(v1Save())
			T.eq(migrated.version, 3, "1 → 2 → 3 한 번에")
			T.eq(migrated.equippedTrail, "blue", "2 → 3: 가진 것(grey·blue) 중 최고 배율 장착")
			local d = DataSchema.reconcile(migrated, 1700001000)
			T.eq(checkValid(d), nil)
			T.eq(d.money, 123456)
			T.eq(d.speed, 9999)
			T.eq(#d.pets, 3)
			T.eq(d.pets[3].petId, "king_snake")
			T.eq(d.pets[3].size, "giant")
			T.eq(d.pets[3].mutations[1], "golden")
			T.eq(d.equipped[1], "p3")
			T.eq(d.equipped[2], "p1")
			T.eq(d.penLevel, 3)
			T.eq(d.treadmillLevel, 2)
			T.eq(#d.trails, 2)
			T.eq(d.equippedTrail, "blue")
			T.eq(d.indexClaimed.chicken, true)
			T.eq(d.indexClaimed.frog, nil)
			T.eq(d.tools.bearTrap, 7)
			T.eq(d.lastSaveTime, 1700000000)
			T.eq(d.freeRewardClaimed, true)
			T.eq(d.stats.eggsStolen, 40)
			T.eq(d.stats.eggsDelivered, 4)
			-- 부화 슬롯 알: 필요 시간은 지금 성장 배율로 다시 계산 (30 → 90 ÷ 3 = 30)
			T.eq(#d.incubators, 1)
			T.eq(d.incubators[1].required, Economy.hatchSeconds("bear"))
			T.eq(d.incubators[1].progress, 12.5)
			T.eq(d.incubators[1].mutations[1], "rainbow")
			-- 새 필드
			T.eq(d.sakuraCrystals, 0)
			T.falsy(d.sakuraUnlocked)
			T.eq(next(d.shrineUsed), nil)
			T.eq(next(d.quests), nil)
			T.falsy(d.questsRewarded)
			T.eq(#d.eggQueue, 0)
			T.eq(#d.weapons, 1)
			T.eq(d.weapons[1], "water_bat")
			-- uid 카운터는 기존 uid(p1~p3, i4) 보다 큼
			T.eq(d.nextUid, 5)
		end
	)

	T.test(
		"마이그레이션은 두 번 돌려도 같고, 이미 2 인 데이터는 새 필드를 지우지 않음",
		function()
			local once = DataSchema.reconcile(DataSchema.migrate(v1Save()), 5)
			local twice =
				DataSchema.reconcile(DataSchema.migrate(DataSchema.reconcile(DataSchema.migrate(v1Save()), 5)), 5)
			T.eq(canonical(once), canonical(twice))
			local v2 = DataSchema.default(0)
			v2.sakuraCrystals = 50
			v2.sakuraUnlocked = true
			v2.questsRewarded = true
			v2.quests = { fuse_once = 1 }
			v2.shrineUsed = { equinox = true }
			v2.eggQueue = { { petId = "ringlord", size = "big", mutations = {}, source = "altar" } }
			local kept = DataSchema.reconcile(DataSchema.migrate(v2), 0)
			T.eq(kept.sakuraCrystals, 50)
			T.truthy(kept.sakuraUnlocked)
			T.truthy(kept.questsRewarded)
			T.eq(kept.quests.fuse_once, 1)
			T.truthy(kept.shrineUsed.equinox)
			T.eq(#kept.eggQueue, 1)
		end
	)

	T.test(
		"버전 표시가 없거나 이상하면 1 로 보고 변환 (v2 필드는 비워짐 — 옛 데이터에는 원래 없던 필드)",
		function()
			T.eq(DataSchema.versionOf({}), 1)
			T.eq(DataSchema.versionOf({ version = "2" }), 1)
			T.eq(DataSchema.versionOf({ version = NAN }), 1)
			T.eq(DataSchema.versionOf(nil), 1)
			T.eq(DataSchema.versionOf(5), 1)
			T.eq(DataSchema.versionOf({ version = 2.5 }), 2.5)
			local migrated = DataSchema.migrate({ money = 5, sakuraCrystals = 99 })
			T.eq(migrated.sakuraCrystals, 0)
		end
	)

	T.test("더 새 버전(4, 4.5, 1e9)은 새 버전으로 인식 — 변환하지 않음", function()
		for _, v in { 4, 4.5, 1e9 } do
			T.truthy(DataSchema.isNewerVersion({ version = v }), tostring(v))
			T.eq(DataSchema.migrate({ version = v, money = 1 }).version, v)
		end
		T.falsy(DataSchema.isNewerVersion({ version = math.huge * 0 }))
		T.falsy(DataSchema.isNewerVersion("version=3"))
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
			local d = DataSchema.reconcile(nil, 0)
			T.eq(checkValid(d), nil)
			for _, garbage in { 5, "x", true, {}, NAN } do
				local ok = pcall(DataSchema.migrate, garbage)
				T.truthy(ok)
			end
		end
	)

	T.test(
		"숫자 칸마다 쓰레기: 음수·NaN·inf·문자열·표·불리언 → 기본값 (거대한 유한 수는 그대로)",
		function()
			local garbage = { -1, -1e300, NAN, math.huge, -math.huge, "123", "abc", {}, { 1 }, true, false }
			for _, key in
				{ "money", "speed", "lastSaveTime", "penLevel", "treadmillLevel", "nextUid", "sakuraCrystals" }
			do
				for _, bad in garbage do
					local ok, d = pcall(DataSchema.reconcile, { [key] = bad }, 0)
					T.truthy(ok, key .. " = " .. tostring(bad) .. " 에서 터짐")
					T.eq(checkValid(d), nil, key .. " = " .. tostring(bad))
				end
			end
			local d = DataSchema.reconcile({ money = -5, speed = NAN, penLevel = "3", treadmillLevel = {} }, 0)
			T.eq(d.money, Config.STARTING_MONEY)
			T.eq(d.speed, Config.STARTING_SPEED)
			T.eq(d.penLevel, 1)
			T.eq(d.treadmillLevel, 0)
		end
	)

	T.test(
		"아주 큰 유한 수(1e300)는 상한(MONEY_MAX·SPEED_MAX)까지, 소수 레벨은 내림, 범위 밖은 끝값으로",
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
		"표 칸마다 쓰레기 (pets/equipped/trails/incubators/... 에 숫자·문자열·불리언·NaN)",
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
				"eggQueue",
				"equippedTrail",
			}
			local garbage = { 5, "x", true, false, NAN, math.huge, { "a", "b" }, { a = 1 }, { {} }, { [1] = NAN } }
			for _, key in keys do
				for i, bad in garbage do
					local ok, d = pcall(DataSchema.reconcile, { [key] = bad }, 0)
					T.truthy(ok, key .. " #" .. i .. " 에서 터짐: " .. tostring(d))
					T.eq(checkValid(d), nil, key .. " #" .. i)
				end
			end
		end
	)

	T.test(
		"펫 항목이 엉터리: 필드 빠짐·타입 틀림·모르는 id·중복 uid·너무 긴 uid → 그 항목만 버림",
		function()
			local d = DataSchema.reconcile({
				pets = {
					{ uid = "ok1", petId = "chicken", size = "normal", mutations = {} },
					{ uid = "ok1", petId = "dog", size = "normal", mutations = {} },
					{ uid = "", petId = "dog" },
					{ uid = string.rep("x", 49), petId = "dog" },
					{ uid = 7, petId = "dog" },
					{ uid = "n1", petId = 5 },
					{ uid = "n2" },
					{ petId = "dog" },
					"문자열",
					5,
					true,
					{},
					{ uid = "ok2", petId = "dog", size = {}, mutations = "x" },
					{
						uid = "ok3",
						petId = "bear",
						size = "giant",
						mutations = { 5, {}, "silver", "silver", "golden", "bloom", "bloom", "spirit_bloom" },
					},
				},
				equipped = { "ok1", "ok1", "없는uid", 5, "ok3", {} },
			}, 0)
			T.eq(checkValid(d), nil)
			T.eq(#d.pets, 3, "ok1, ok2, ok3 만 남음")
			T.eq(d.pets[1].uid, "ok1")
			T.eq(d.pets[1].petId, "chicken", "먼저 나온 중복 uid 가 이김")
			T.eq(d.pets[2].size, "normal", "이상한 크기는 보통")
			T.eq(#d.pets[2].mutations, 0)
			T.eq(#d.pets[3].mutations, 2, "자연 하나 + 블룸 하나만")
			T.eq(#d.equipped, 2)
			T.eq(d.equipped[1], "ok1")
			T.eq(d.equipped[2], "ok3")
		end
	)

	T.test(
		"uid 가 보관함과 부화 슬롯 사이에서도 겹치지 않음 (겹치면 뒤쪽을 버림)",
		function()
			local d = DataSchema.reconcile({
				pets = { { uid = "x1", petId = "chicken", size = "normal", mutations = {} } },
				incubators = {
					{ uid = "x1", petId = "dog", size = "normal", mutations = {}, slot = 1, progress = 0 },
					{ uid = "x2", petId = "dog", size = "normal", mutations = {}, slot = 2.9, progress = NAN },
					{ uid = "x3", petId = "dog", size = "normal", mutations = {}, slot = 0, progress = 0 },
					{ uid = "x4", petId = "dog", size = "normal", mutations = {}, slot = 9, progress = 0 },
					{ uid = "x5", petId = "dog", size = "normal", mutations = {}, slot = NAN, progress = 0 },
					{ uid = "x6", petId = "dog", size = "normal", mutations = {}, slot = "1", progress = 0 },
				},
			}, 0)
			T.eq(checkValid(d), nil)
			T.eq(#d.incubators, 1)
			T.eq(d.incubators[1].uid, "x2")
			T.eq(d.incubators[1].slot, 2)
			T.eq(d.incubators[1].progress, 0, "NaN 진행도는 0")
		end
	)

	T.test(
		"nextUid 는 기존 uid 번호보다 항상 큼 (겹치는 새 uid 가 안 나옴), 반복해도 겹침 없음",
		function()
			local d = DataSchema.reconcile({
				pets = { { uid = "p500", petId = "chicken", size = "normal", mutations = {} } },
				incubators = {
					{ uid = "i900", petId = "dog", size = "normal", mutations = {}, slot = 1, progress = 0 },
				},
				nextUid = 3,
			}, 0)
			T.truthy(d.nextUid > 900)
			local seen = { p500 = true, i900 = true }
			for _ = 1, 2000 do
				local uid = DataSchema.newUid(d, "p")
				T.falsy(seen[uid], "uid 겹침 " .. uid)
				seen[uid] = true
				T.truthy(Validate.uid(uid) ~= nil, "새 uid 는 Remote 검사를 통과해야 함: " .. uid)
			end
		end
	)

	T.test("v2 필드 쓰레기: 퀘스트·제단·대기 줄·무기", function()
		local d = DataSchema.reconcile({
			quests = { deliver_eggs = -5, fuse_once = 2.7, deliver_eternal = "1", ["가짜"] = 3 },
			shrineUsed = { equinox = 1, aetheron = true, chicken = true },
			eggQueue = {
				5,
				"x",
				{ petId = "ring_guard" },
				{ petId = "ring_guard", size = 7, mutations = 3, source = 9 },
			},
			weapons = { 5, "katana", "baseball_bat", "scythe", "scythe" },
		}, 0)
		T.eq(checkValid(d), nil)
		T.eq(d.quests.deliver_eggs, nil)
		T.eq(d.quests.fuse_once, 1, "2.7 → 내림 2 → 목표 1 로 제한")
		T.eq(d.quests.deliver_eternal, nil)
		T.eq(d.shrineUsed.equinox, nil, "true 가 아니면 무시")
		T.truthy(d.shrineUsed.aetheron)
		T.eq(#d.eggQueue, 2)
		T.eq(d.eggQueue[1].source, "altar")
		T.eq(#d.weapons, 2, "katana, scythe 만 (기본 방망이·중복 제외)")
	end)

	T.test(
		"저장 데이터의 펫이 500마리가 넘으면 불러올 때 500마리까지만 남김 (REMOTES.md: Snapshot.pets 는 최대 500)",
		function()
			local pets = {}
			for i = 1, 800 do
				table.insert(pets, { uid = "p" .. i, petId = "chicken", size = "normal", mutations = {} })
			end
			local d = DataSchema.reconcile({ pets = pets }, 0)
			T.truthy(#d.pets <= Config.PET_INVENTORY_MAX, "펫 " .. #d.pets .. "마리가 그대로 로드됨")
		end
	)

	T.test("펫 5,000마리 + 부화 슬롯 5,000개짜리 큰 데이터도 1초 안에 처리", function()
		local pets, incubators = {}, {}
		for i = 1, 5000 do
			table.insert(pets, { uid = "p" .. i, petId = "chicken", size = "normal", mutations = {} })
			table.insert(
				incubators,
				{ uid = "i" .. i, petId = "dog", size = "normal", mutations = {}, slot = i, progress = 0 }
			)
		end
		local started = os.clock()
		local d = DataSchema.reconcile({ pets = pets, incubators = incubators }, 0)
		T.truthy(os.clock() - started < 1, "느림")
		T.eq(#d.incubators, Config.INCUBATOR_SLOTS)
	end)

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
				"chicken",
				"bear",
				"silver",
				"grey",
				"forest",
				"katana",
				"한글",
				string.rep("z", 60),
			}
			local petIds = {
				"chicken",
				"dog",
				"bear",
				"king_snake",
				"ghost_king",
				"crane",
				"pegasus",
				"없는펫",
				"ring_guard",
				"jitterbug",
			}
			local sizes = { "normal", "big", "huge", "giant", "엄청큼" }
			local muts =
				{ "silver", "golden", "rainbow", "bloom", "spirit_bloom", "fractured", "chaos", "parasite", "모름" }
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
				-- 반은 그럴듯한 값, 반은 쓰레기
				if rand() < 0.5 then
					return good()
				end
				return garbage(0)
			end
			local function petEntry()
				return {
					uid = maybe(function()
						return "p" .. math.floor(rand() * 30)
					end),
					petId = maybe(function()
						return pick(petIds)
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
				}
			end
			local function listOf(entry)
				return function()
					local list = {}
					for _ = 1, math.floor(rand() * 12) do
						table.insert(list, entry())
					end
					return list
				end
			end
			for i = 1, 5000 do
				local raw = {
					version = maybe(function()
						return pick({ 1, 2 })
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
					pets = maybe(listOf(petEntry)),
					equipped = maybe(listOf(function()
						return "p" .. math.floor(rand() * 30)
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
							t[pick(petIds)] = pick({ true, false, 1, "x" })
						end
						return t
					end),
					indexClaimed = maybe(function()
						local t = {}
						for _ = 1, 6 do
							t[pick(petIds)] = pick({ true, false })
						end
						return t
					end),
					incubators = maybe(listOf(function()
						local e = petEntry()
						e.slot = maybe(function()
							return math.floor(rand() * 10)
						end)
						e.progress = maybe(function()
							return rand() * 1e5
						end)
						return e
					end)),
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
					quests = maybe(function()
						return { deliver_eggs = maybe(function()
							return math.floor(rand() * 40)
						end) }
					end),
					eggQueue = maybe(listOf(function()
						local e = petEntry()
						e.source = pick({ "altar", "shrine", "quest", "해킹" })
						return e
					end)),
					nextUid = maybe(function()
						return math.floor(rand() * 100)
					end),
				}
				local ok, d = pcall(DataSchema.reconcile, raw, 0)
				T.truthy(ok, "퍼징 #" .. i .. " 에서 터짐: " .. tostring(d))
				local problem = checkValid(d)
				T.eq(problem, nil, "퍼징 #" .. i .. " 결과가 규칙 위반")
				-- 보정 결과를 다시 보정해도 그대로여야 함 (멱등)
				local again = DataSchema.reconcile(DataSchema.migrate(table.clone(d)), 0)
				if canonical(again) ~= canonical(d) then
					T.eq(canonical(again), canonical(d), "퍼징 #" .. i .. " 두 번 보정하면 달라짐")
				end
			end
		end
	)
end
