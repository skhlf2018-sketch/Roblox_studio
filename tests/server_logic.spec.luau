--!nocheck
-- 서버 순수 로직: 레이트 리밋, 인자 검사, 저장 데이터 보정

return function(T, Loader)
	local RateLimiter = Loader.require("ServerScriptService/Server/Logic/RateLimiter")
	local Validate = Loader.require("ServerScriptService/Server/Logic/Validate")
	local DataSchema = Loader.require("ServerScriptService/Server/Logic/DataSchema")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")

	T.suite("RateLimiter")

	T.test("burst 만큼 허용 후 막고, 시간이 지나면 회복", function()
		local now = 0
		local limiter = RateLimiter.new(function()
			return now
		end)
		for i = 1, 3 do
			T.truthy(limiter:allow(1, "X", 3, 1), "허용 " .. i)
		end
		T.falsy(limiter:allow(1, "X", 3, 1), "4번째 막힘")
		T.truthy(limiter:allow(2, "X", 3, 1), "다른 플레이어는 따로")
		T.truthy(limiter:allow(1, "Y", 3, 1), "다른 Remote 는 따로")
		now = 1
		T.truthy(limiter:allow(1, "X", 3, 1), "1초 후 1개 회복")
		T.falsy(limiter:allow(1, "X", 3, 1))
		now = 100
		for _ = 1, 3 do
			T.truthy(limiter:allow(1, "X", 3, 1))
		end
		T.falsy(limiter:allow(1, "X", 3, 1), "burst 이상 쌓이지 않음")
		limiter:forget(1)
		T.eq(limiter.buckets[1], nil)
	end)

	T.suite("Validate")

	T.test("uid", function()
		T.eq(Validate.uid("p12"), "p12")
		T.eq(Validate.uid("e-3_x"), "e-3_x")
		T.eq(Validate.uid(""), nil)
		T.eq(Validate.uid(12), nil)
		T.eq(Validate.uid(nil), nil)
		T.eq(Validate.uid({}), nil)
		T.eq(Validate.uid("a b"), nil)
		T.eq(Validate.uid(string.rep("a", 49)), nil)
		T.eq(Validate.uid("../../x"), nil)
	end)

	T.test("oneOf / idIn / finiteNumber", function()
		local kinds = { Pen = "Pen", Trail = "Trail" }
		T.eq(Validate.oneOf("Pen", kinds), "Pen")
		T.eq(Validate.oneOf("pen", kinds), nil)
		T.eq(Validate.oneOf(1, kinds), nil)
		T.eq(Validate.idIn("grey", { grey = true }), "grey")
		T.eq(Validate.idIn("gold", { grey = true }), nil)
		T.eq(Validate.finiteNumber(3), 3)
		T.eq(Validate.finiteNumber(0 / 0), nil)
		T.eq(Validate.finiteNumber(math.huge), nil)
		T.eq(Validate.finiteNumber("3"), nil)
	end)

	T.suite("DataSchema (6판 스키마 6)")

	local Plants = Loader.require("ReplicatedStorage/Shared/Data/Plants")
	local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
	local GardenRules = Loader.require("ReplicatedStorage/Shared/GardenRules")
	local function discoverAll(biomeId, except)
		local discovered = {}
		for _, plant in Plants.inBiome(biomeId) do
			if not (except and except[plant.id]) then
				discovered[plant.id] = true
			end
		end
		return discovered
	end

	T.test(
		"기본값 (6판): 버전 6, 빈 정원·씨앗 가방·열매 가방, 튜토리얼 1단계, 옛 칸 없음",
		function()
			local d = DataSchema.default(0)
			T.eq(Config.SCHEMA_VERSION, 6)
			T.eq(d.version, 6)
			T.eq(d.money, Config.STARTING_MONEY)
			T.eq(d.speed, Config.STARTING_SPEED)
			T.eq(d.penLevel, 1)
			T.eq(d.treadmillLevel, 0)
			T.eq(d.tools.bearTrap, Config.STARTING_BEAR_TRAPS)
			T.eq(#d.pets, 0)
			T.eq(#d.incubators, 0)
			T.eq(#d.eggs, 0)
			T.eq(next(d.fruits), nil)
			T.eq(d.tutorialStep, 1)
			T.eq(d.sakuraCrystals, 0)
			T.eq(d.equippedTrail, "none")
			T.eq(d.equipped, nil, "6판: 장착 없음")
			T.eq(d.sakuraUnlocked, nil, "6판: 사쿠라 해금 없음")
			T.eq(d.shrineUsed, nil, "6판: 비밀 통로 없음")
		end
	)

	T.test("엉터리 값은 기본값으로", function()
		for _, garbage in { nil, 5, "x", true } do
			local d = DataSchema.reconcile(garbage, 0)
			T.eq(d.money, Config.STARTING_MONEY)
		end
		local d = DataSchema.reconcile({
			money = 0 / 0,
			speed = -5,
			penLevel = 999,
			treadmillLevel = -3,
			trails = { "grey", "grey", "가짜" },
		}, 0)
		T.eq(d.money, Config.STARTING_MONEY)
		T.eq(d.speed, Config.STARTING_SPEED)
		T.eq(d.penLevel, 11)
		T.eq(d.treadmillLevel, 0)
		T.eq(#d.trails, 1)
	end)

	T.test(
		"성체 식물: 모르는 id·중복 uid 버림, 돌연변이 정리, 열매 0~5, 자리 보정, 정원 칸 넘치면 코인으로",
		function()
			local grid1 = MapLayout.eggGridLocal(1)
			local pets = {
				{
					uid = "p1",
					petId = "sprout_daisy",
					size = "big",
					mutations = { "silver", "golden" },
					x = grid1.x,
					z = grid1.z,
					fruits = 9,
					fruitProgress = 999,
				},
				{ uid = "p1", petId = "owl_oak", size = "normal", mutations = {} }, -- 중복 uid
				{ uid = "p99", petId = "없는식물", size = "normal", mutations = {} },
				-- 같은 자리 겹침 → 빈 격자 자리로, 모르는 크기 → 보통, 모르는 돌연변이 버림
				{
					uid = "p50",
					petId = "owl_oak",
					size = "엄청큼",
					mutations = { "모름", "frozen" },
					x = grid1.x,
					z = grid1.z,
					fruits = -3,
				},
			}
			local d = DataSchema.reconcile({ pets = pets, penLevel = 1, nextUid = 3 }, 0)
			T.eq(#d.pets, 2)
			local a, b = d.pets[1], d.pets[2]
			T.eq(#a.mutations, 1, "자연 돌연변이 1개만")
			T.eq(a.mutations[1], "silver")
			T.eq(a.fruits, Config.FRUIT_MAX_PER_PLANT, "열매는 최대 5")
			T.eq(
				a.fruitProgress,
				Plants.get("sprout_daisy").fruitIntervalSeconds,
				"다음 열매 시간은 간격까지"
			)
			T.eq(a.x, grid1.x)
			T.eq(b.size, "normal")
			T.eq(b.mutations[1], "frozen")
			T.eq(b.fruits, 0)
			T.falsy(b.x == grid1.x and b.z == grid1.z, "겹치면 다른 자리")
			T.truthy(MapLayout.isInPenLocal(b.x, b.z, Config.EGG_PLACE_FENCE_MARGIN))
			T.eq(d.nextUid, 51, "uid 카운터가 기존 uid 보다 큼")
			-- 정원 칸(1레벨 7칸)을 넘는 성체는 코인으로 (뽑아서 팔기 값)
			local many = {}
			for i = 1, 9 do
				table.insert(many, { uid = "p" .. i, petId = "sprout_daisy", size = "normal", mutations = {} })
			end
			local full = DataSchema.reconcile({ pets = many, money = 0 }, 0)
			T.eq(#full.pets, 7)
			T.eq(full.money, 2 * GardenRules.sellPrice({ petId = "sprout_daisy", size = "normal", mutations = {} }))
		end
	)

	T.test("도감: 발견 안 한 식물은 수령 목록에서 제거", function()
		local d = DataSchema.reconcile({
			indexDiscovered = { sprout_daisy = true, puppy_grass = false, ["가짜"] = true, chicken = true },
			indexClaimed = { sprout_daisy = true, owl_oak = true },
		}, 0)
		T.eq(d.indexDiscovered.sprout_daisy, true)
		T.eq(d.indexDiscovered.puppy_grass, nil)
		T.eq(d.indexDiscovered["가짜"], nil)
		T.eq(d.indexDiscovered.chicken, nil, "5판 펫 id 는 6판에 없음")
		T.eq(d.indexClaimed.sprout_daisy, true)
		T.eq(d.indexClaimed.owl_oak, nil)
	end)

	T.test(
		"심은 씨앗: 필요 시간 다시 계산, 자리가 깨지거나 겹치면 빈 격자로, 정원 칸(성체 포함) 넘치면 가방으로",
		function()
			local grid1 = MapLayout.eggGridLocal(1)
			local d = DataSchema.reconcile({
				penLevel = 1, -- 7칸
				pets = {
					{ uid = "p1", petId = "sprout_daisy", size = "normal", mutations = {}, x = grid1.x, z = grid1.z },
				},
				incubators = {
					-- 성체와 같은 자리 → 빈 격자로
					{
						uid = "i1",
						petId = "rune_rose",
						size = "normal",
						mutations = {},
						x = grid1.x,
						z = grid1.z,
						progress = 999999,
						required = 5,
					},
					{ uid = "i2", petId = "sprout_daisy", size = "normal", mutations = {}, x = 30, z = 0 }, -- 정원 밖
					{ uid = "i3", petId = "puppy_grass", size = "normal", mutations = {}, progress = 2 }, -- 자리 없음
					{
						uid = "i4",
						petId = "puppy_grass",
						size = "big",
						mutations = {},
						x = -20.5,
						z = 11.3,
						special = true,
					},
					{ uid = "i5", petId = "puppy_grass", size = "normal", mutations = {} },
					{ uid = "i6", petId = "puppy_grass", size = "normal", mutations = {} },
					-- 7번째(성체 1 + 씨앗 6 = 7칸) 넘으면 가방으로 (자란 만큼 그대로)
					{ uid = "i7", petId = "owl_oak", size = "normal", mutations = {}, progress = 4 },
					{ uid = "i8", petId = "owl_oak", size = "huge", mutations = {} },
					{ uid = "i9", petId = "없는식물", size = "normal", mutations = {} },
				},
			}, 0)
			T.eq(#d.incubators, 6)
			T.eq(d.incubators[1].required, 86400, "비밀 1일 (Plants.growSeconds)")
			T.eq(d.incubators[1].progress, 86400, "필요량 넘지 않음")
			T.eq(d.incubators[1].biomeId, "enchanted_forest")
			T.falsy(d.incubators[1].x == grid1.x and d.incubators[1].z == grid1.z, "성체 자리와 안 겹침")
			T.eq(d.incubators[4].x, -20.5, "정원 안 아무 자리는 그대로")
			T.truthy(d.incubators[4].special)
			for _, record in d.incubators do
				T.truthy(MapLayout.isInPenLocal(record.x, record.z, Config.EGG_PLACE_FENCE_MARGIN), record.uid)
			end
			T.eq(#d.eggs, 2, "넘친 씨앗 2개는 가방으로 (모르는 식물은 버림)")
			T.eq(d.eggs[1].uid, "i7")
			T.eq(d.eggs[1].progress, 4, "자란 만큼 그대로")
			T.eq(d.eggs[2].size, "huge")
		end
	)

	T.test(
		"열매 가방: 모르는 식물 id 버림, 개수는 정수, 합은 FRUIT_BAG_MAX 까지, 값은 0 이상",
		function()
			local d = DataSchema.reconcile({
				fruits = {
					sprout_daisy = { count = 3.7, value = 30 },
					owl_oak = { count = Config.FRUIT_BAG_MAX, value = -5 },
					["가짜"] = { count = 5, value = 5 },
					puppy_grass = "엉터리",
					moon_lotus = { count = 0, value = 100 },
				},
			}, 0)
			local total = 0
			for id, stack in d.fruits do
				T.truthy(Plants.get(id), id)
				T.eq(stack.count, math.floor(stack.count))
				T.truthy(stack.count > 0)
				T.truthy(stack.value >= 0)
				total += stack.count
			end
			T.truthy(total <= Config.FRUIT_BAG_MAX, "합 " .. total)
			T.eq(d.fruits["가짜"], nil)
			T.eq(d.fruits.moon_lotus, nil, "0개 칸은 버림")
			T.eq(d.fruits.puppy_grass, nil)
		end
	)

	T.test("newUid 는 증가", function()
		local d = DataSchema.default(0)
		T.eq(DataSchema.newUid(d, "p"), "p1")
		T.eq(DataSchema.newUid(d, "i"), "i2")
		T.eq(d.nextUid, 3)
	end)

	T.test(
		"스키마 5 이하 → 6: 속도·트레일·러닝머신만 남기고 초기화 (새 사람처럼, 튜토리얼 1단계)",
		function()
			local v5 = {
				version = 5,
				money = 1e12,
				speed = 123456,
				trails = { "grey", "red" },
				equippedTrail = "grey",
				treadmillLevel = 4,
				penLevel = 9,
				pets = { { uid = "p1", petId = "chicken", size = "normal", mutations = {} } },
				equipped = { "p1" },
				eggs = { { uid = "i2", petId = "dog", size = "normal", mutations = {} } },
				incubators = { { uid = "i3", petId = "dog", size = "normal", mutations = {}, x = -20, z = 0 } },
				indexDiscovered = { chicken = true },
				indexClaimed = { chicken = true },
				weapons = { "katana" },
				sakuraCrystals = 50,
				sakuraUnlocked = true,
				shrineUsed = { equinox = true },
				tools = { bearTrap = 40 },
				stats = { eggsStolen = 99 },
				tutorialStep = 6,
				lastSaveTime = 1700000000,
				nextUid = 77,
			}
			local migrated = DataSchema.migrate(v5)
			T.eq(migrated.version, 6)
			T.eq(migrated.pets, nil)
			T.eq(migrated.money, nil)
			local d = DataSchema.reconcile(migrated, 0)
			T.eq(d.version, 6)
			T.eq(d.speed, 123456, "속도 남김")
			T.eq(#d.trails, 2, "트레일 남김")
			T.eq(d.equippedTrail, "grey", "장착 트레일 남김")
			T.eq(d.treadmillLevel, 4, "러닝머신 남김")
			T.eq(d.money, Config.STARTING_MONEY, "코인은 처음부터")
			T.eq(d.penLevel, 1, "정원(옛 우리) 레벨은 처음부터")
			T.eq(#d.pets, 0)
			T.eq(#d.eggs, 0)
			T.eq(#d.incubators, 0)
			T.eq(next(d.indexDiscovered), nil)
			T.eq(#d.weapons, 0)
			T.eq(d.sakuraCrystals, 0)
			T.eq(d.tools.bearTrap, Config.STARTING_BEAR_TRAPS)
			T.eq(d.stats.eggsStolen, 0)
			T.eq(d.tutorialStep, 1, "튜토리얼 다시 1단계")
			T.eq(d.lastSaveTime, 0, "오프라인 성장 없음")
			T.eq(d.resetFromVersion, nil, "기록용 칸은 저장 데이터에 안 남음")
			-- version 이 없던 아주 옛 데이터도 1 로 보고 초기화
			local v0 = DataSchema.reconcile(DataSchema.migrate({ money = 1, speed = 500 }), 0)
			T.eq(v0.version, 6)
			T.eq(v0.money, 0)
			T.eq(v0.speed, 500)
		end
	)

	T.test(
		"스키마 2 이하 → 6: 장착 트레일 칸이 없던 데이터는 가진 것 중 최고 배율을 장착 (속도 그대로)",
		function()
			local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
			local migrated = DataSchema.migrate({ version = 2, trails = { "grey", "purple", "blue", "가짜", 7 } })
			T.eq(migrated.version, 6)
			T.eq(migrated.equippedTrail, "purple")
			local d = DataSchema.reconcile(migrated, 0)
			T.eq(d.equippedTrail, "purple")
			T.eq(Economy.trailMultiplier(d.equippedTrail), Economy.bestTrailMultiplier(d.trails))
			T.eq(DataSchema.migrate({ version = 2 }).equippedTrail, "none")
			T.eq(DataSchema.migrate({ version = 2, trails = "엉터리" }).equippedTrail, "none")
			-- 3 이상이면 사용자가 고른 장착(해제 포함)을 바꾸지 않음
			local keep = DataSchema.migrate({ version = 3, trails = { "grey", "red" }, equippedTrail = "grey" })
			T.eq(keep.equippedTrail, "grey")
			local off = DataSchema.migrate({ version = 5, trails = { "red" }, equippedTrail = "none" })
			T.eq(DataSchema.reconcile(off, 0).equippedTrail, "none")
		end
	)

	T.test(
		"새 버전 서버가 저장한 데이터는 표시만 하고 버전을 내리지 않음, 6 은 그대로",
		function()
			T.truthy(DataSchema.isNewerVersion({ version = 7 }))
			T.falsy(DataSchema.isNewerVersion({ version = 6 }))
			T.falsy(DataSchema.isNewerVersion({ version = 5 }))
			T.falsy(DataSchema.isNewerVersion({ version = 1 }))
			T.falsy(DataSchema.isNewerVersion(nil))
			T.eq(DataSchema.migrate({ version = 7 }).version, 7)
			T.eq(DataSchema.migrate({ version = 7, money = 5 }).money, 5, "새 버전 데이터는 안 건드림")
			local six = DataSchema.migrate({ version = 6, money = 77, pets = {} })
			T.eq(six.money, 77, "6 은 초기화하지 않음")
			T.eq(six.tutorialStep, nil)
		end
	)

	T.test("equippedTrail 보정: 가진 트레일만, 아니면 none", function()
		local function eq(raw)
			return DataSchema.reconcile(raw, 0).equippedTrail
		end
		T.eq(eq({ version = 6, trails = { "grey", "red" }, equippedTrail = "red" }), "red")
		T.eq(eq({ version = 6, trails = { "grey" }, equippedTrail = "red" }), "none", "안 가진 트레일")
		T.eq(eq({ version = 6, trails = { "grey" }, equippedTrail = "가짜" }), "none")
		T.eq(eq({ version = 6, trails = { "가짜" }, equippedTrail = "가짜" }), "none")
		T.eq(eq({ version = 6, trails = { "grey" }, equippedTrail = 5 }), "none")
		T.eq(eq({ version = 6, trails = { "grey" } }), "none")
	end)

	T.test("코인·속도 상한, 크리스탈 음수 → 0, 무기는 아는 것만", function()
		local d = DataSchema.reconcile({
			money = 1e300,
			speed = 1e300,
			sakuraCrystals = -3,
			weapons = { "katana", "baseball_bat", "가짜무기", "katana" },
		}, 0)
		T.eq(d.money, Config.MONEY_MAX)
		T.eq(d.speed, Config.SPEED_MAX)
		T.eq(d.sakuraCrystals, 0)
		T.eq(#d.weapons, 1)
		T.eq(d.weapons[1], "katana")
	end)

	T.test("무기: 저장된 무기 ∪ 도감으로 해금되는 무기", function()
		local d = DataSchema.reconcile({ weapons = { "scythe" }, indexDiscovered = discoverAll("lake") }, 0)
		T.eq(#d.weapons, 2)
		T.eq(d.weapons[1], "water_bat", "구역 순서")
		T.eq(d.weapons[2], "scythe")
	end)
end
