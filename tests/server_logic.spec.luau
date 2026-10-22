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

	T.suite("DataSchema")

	T.test("기본값", function()
		local d = DataSchema.default(0)
		T.eq(d.version, Config.SCHEMA_VERSION)
		T.eq(d.money, Config.STARTING_MONEY)
		T.eq(d.speed, Config.STARTING_SPEED)
		T.eq(d.penLevel, 1)
		T.eq(d.treadmillLevel, 0)
		T.eq(d.tools.bearTrap, Config.STARTING_BEAR_TRAPS)
		T.eq(#d.pets, 0)
	end)

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

	T.test("펫: 모르는 id·중복 uid 버림, 돌연변이 정리, 장착은 칸 수까지", function()
		local pets = {}
		local equipped = {}
		for i = 1, 10 do
			table.insert(pets, { uid = "p" .. i, petId = "chicken", size = "big", mutations = { "silver", "golden" } })
			table.insert(equipped, "p" .. i)
		end
		table.insert(pets, { uid = "p1", petId = "dog", size = "normal", mutations = {} }) -- 중복 uid
		table.insert(pets, { uid = "p99", petId = "없는펫", size = "normal", mutations = {} })
		table.insert(pets, { uid = "p50", petId = "dog", size = "엄청큼", mutations = { "모름", "bloom" } })
		table.insert(equipped, "p1")
		table.insert(equipped, "없음")
		local d = DataSchema.reconcile({ pets = pets, equipped = equipped, penLevel = 1, nextUid = 3 }, 0)
		T.eq(#d.pets, 11)
		T.eq(#d.pets[1].mutations, 1, "자연 돌연변이 1개만")
		T.eq(d.pets[1].mutations[1], "silver")
		T.eq(d.pets[11].size, "normal", "모르는 크기 → 보통")
		T.eq(d.pets[11].mutations[1], "bloom")
		T.eq(#d.equipped, 7, "우리 1레벨 = 7칸")
		T.eq(d.nextUid, 51, "uid 카운터가 기존 uid 보다 큼")
	end)

	T.test("도감: 발견 안 한 펫은 수령 목록에서 제거", function()
		local d = DataSchema.reconcile({
			indexDiscovered = { chicken = true, dog = false, ["가짜"] = true },
			indexClaimed = { chicken = true, bear = true },
		}, 0)
		T.eq(d.indexDiscovered.chicken, true)
		T.eq(d.indexDiscovered.dog, nil)
		T.eq(d.indexDiscovered["가짜"], nil)
		T.eq(d.indexClaimed.chicken, true)
		T.eq(d.indexClaimed.bear, nil)
	end)

	T.test(
		"2판 수정 놓인 알: 필요 시간 다시 계산, 자리가 깨지거나 겹치면 빈 격자 자리로, 8개 넘으면 가방으로",
		function()
			local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
			local grid1 = MapLayout.eggGridLocal(1)
			local d = DataSchema.reconcile({
				version = 4,
				incubators = {
					{
						uid = "i1",
						petId = "king_snake",
						size = "normal",
						mutations = {},
						x = grid1.x,
						z = grid1.z,
						progress = 99999,
						required = 5,
					},
					-- 같은 자리(겹침) → 빈 격자 자리(2번)로
					{ uid = "i2", petId = "chicken", size = "normal", mutations = {}, x = grid1.x, z = grid1.z },
					-- 우리 밖(앞마당) → 빈 격자 자리로
					{ uid = "i3", petId = "chicken", size = "normal", mutations = {}, x = 30, z = 0 },
					-- 위치 없음 / NaN → 빈 격자 자리로
					{ uid = "i4", petId = "dog", size = "normal", mutations = {}, progress = 2 },
					{ uid = "i5", petId = "dog", size = "normal", mutations = {}, x = 0 / 0, z = 3 },
					-- 우리 안 아무 자리 (격자 아님) 는 그대로
					{ uid = "i6", petId = "dog", size = "big", mutations = {}, x = -20.5, z = 11.3, special = true },
					{ uid = "i7", petId = "dog", size = "normal", mutations = {} },
					{ uid = "i8", petId = "dog", size = "normal", mutations = {} },
					-- 9, 10번째 → 놓을 수 있는 수(8) 초과 → 가방으로 (진행도 그대로)
					{ uid = "i9", petId = "bear", size = "normal", mutations = {}, progress = 4 },
					{ uid = "i10", petId = "bear", size = "huge", mutations = {} },
					{ uid = "i11", petId = "없는펫", size = "normal", mutations = {} },
				},
			}, 0)
			T.eq(#d.incubators, Config.PLACED_EGG_MAX)
			T.eq(d.incubators[1].required, 5400, "원작 그대로 (2판 수정: ÷3 없음)")
			T.eq(d.incubators[1].progress, 5400, "필요량 넘지 않음")
			T.eq(d.incubators[1].biomeId, "jungle")
			T.eq(d.incubators[1].x, grid1.x)
			local grid2 = MapLayout.eggGridLocal(2)
			T.eq(d.incubators[2].x, grid2.x, "겹치면 다음 빈 격자")
			T.eq(d.incubators[2].z, grid2.z)
			T.eq(d.incubators[6].x, -20.5, "우리 안 아무 자리는 그대로")
			T.eq(d.incubators[6].z, 11.3)
			T.truthy(d.incubators[6].special)
			T.falsy(d.incubators[2].special)
			for _, record in d.incubators do
				T.eq(record.slot, nil, "슬롯 번호 없음")
				T.truthy(MapLayout.isInPenLocal(record.x, record.z, Config.EGG_PLACE_FENCE_MARGIN), record.uid)
			end
			T.eq(#d.eggs, 2, "넘친 알 2개는 가방으로 (모르는 펫은 버림)")
			T.eq(d.eggs[1].uid, "i9")
			T.eq(d.eggs[1].progress, 4, "진행도 그대로")
			T.eq(d.eggs[2].size, "huge")
		end
	)

	T.test("newUid 는 증가", function()
		local d = DataSchema.default(0)
		T.eq(DataSchema.newUid(d, "p"), "p1")
		T.eq(DataSchema.newUid(d, "i"), "i2")
		T.eq(d.nextUid, 3)
	end)

	T.suite("DataSchema v2")

	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local function discoverAll(biomeId, except)
		local discovered = {}
		for _, pet in Pets.inBiome(biomeId) do
			if not (except and except[pet.id]) then
				discovered[pet.id] = true
			end
		end
		return discovered
	end

	T.test(
		"버전 5 기본값 (2단계 필드 + 장착 트레일 none + 빈 알 가방 + 튜토리얼 1단계, 퀘스트·무료 보상 칸 없음)",
		function()
			T.eq(Config.SCHEMA_VERSION, 5)
			local d = DataSchema.default(0)
			T.eq(d.version, 5)
			T.eq(d.sakuraCrystals, 0)
			T.falsy(d.sakuraUnlocked)
			T.eq(d.questsRewarded, nil, "5판: 퀘스트 칸 없앰")
			T.eq(d.freeRewardClaimed, nil, "5판: 무료 보상 칸 없앰")
			T.eq(d.tutorialStep, 1, "5판: 새 사람은 튜토리얼 1단계")
			T.eq(#d.weapons, 0)
			T.eq(#d.eggs, 0)
			T.eq(d.eggQueue, nil, "2판 수정: 대기 줄 없앰")
			T.eq(next(d.shrineUsed), nil)
			T.eq(d.quests, nil)
			T.eq(d.equippedTrail, "none")
		end
	)

	T.test("마이그레이션 1 → 2: 도감 기록으로 무기 채움 (천사&악마 18종 규칙)", function()
		local v1 = {
			version = 1,
			money = 500,
			indexDiscovered = discoverAll("angels_demons", { equinox = true, aetheron = true }),
		}
		local migrated = DataSchema.migrate(v1)
		T.eq(migrated.version, 5)
		T.eq(migrated.weapons[1], "angel_spear")
		local d = DataSchema.reconcile(migrated, 0)
		T.eq(d.version, 5)
		T.eq(d.money, 500)
		T.eq(d.weapons[1], "angel_spear")
		T.eq(d.sakuraCrystals, 0)
		-- version 이 없던 아주 옛 데이터도 1 로 보고 변환
		T.eq(DataSchema.migrate({ money = 1 }).version, 5)
	end)

	T.test("새 버전 서버가 저장한 데이터는 표시만 하고 버전을 내리지 않음", function()
		T.truthy(DataSchema.isNewerVersion({ version = 6 }))
		T.falsy(DataSchema.isNewerVersion({ version = 5 }))
		T.falsy(DataSchema.isNewerVersion({ version = 4 }))
		T.falsy(DataSchema.isNewerVersion({ version = 3 }))
		T.falsy(DataSchema.isNewerVersion({ version = 2 }))
		T.falsy(DataSchema.isNewerVersion({ version = 1 }))
		T.falsy(DataSchema.isNewerVersion(nil))
		T.eq(DataSchema.migrate({ version = 6 }).version, 6)
		T.eq(DataSchema.migrate({ version = 6 }).equippedTrail, nil, "새 버전 데이터는 안 건드림")
		T.eq(DataSchema.migrate({ version = 6 }).tutorialStep, nil, "새 버전 데이터는 안 건드림")
	end)

	T.test(
		"마이그레이션 3 → 4: 부화 슬롯 n번 알 → 우리 안 격자 자리 n (옛 자리 그대로), 대기 줄 → 가방",
		function()
			local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
			local v3 = {
				version = 3,
				nextUid = 10,
				incubators = {
					{ uid = "i3", petId = "bear", size = "normal", mutations = {}, slot = 3, progress = 5 },
					{ uid = "i4", petId = "dog", size = "big", mutations = { "golden" }, slot = 8, progress = 0 },
					{ uid = "i5", petId = "dog", size = "normal", mutations = {}, slot = 2.5, progress = 0 },
				},
				eggQueue = {
					{ petId = "ring_guard", size = "big", mutations = { "golden" }, source = "altar" },
					{ petId = "없는펫", size = "big", mutations = {}, source = "altar" },
					{ petId = "jitterbug", size = "이상함", mutations = {}, source = "quest" }, -- 옛 퀘스트 선물 알도 가방으로
				},
			}
			local migrated = DataSchema.migrate(v3)
			T.eq(migrated.version, 5)
			local s3, s8 = MapLayout.eggGridLocal(3), MapLayout.eggGridLocal(8)
			T.eq(migrated.incubators[1].x, s3.x)
			T.eq(migrated.incubators[1].z, s3.z)
			T.eq(migrated.incubators[1].slot, nil)
			T.eq(
				migrated.incubators[3].x,
				nil,
				"이상한 슬롯 번호는 자리 없음 → reconcile 이 빈 자리로"
			)
			local d = DataSchema.reconcile(migrated, 0)
			T.eq(#d.incubators, 3, "알은 하나도 안 사라짐")
			T.eq(d.incubators[1].x, s3.x)
			T.eq(d.incubators[1].progress, 5)
			T.eq(d.incubators[2].x, s8.x)
			T.eq(d.incubators[2].z, s8.z)
			T.eq(d.incubators[2].mutations[1], "golden")
			local g1 = MapLayout.eggGridLocal(1)
			T.eq(d.incubators[3].x, g1.x, "빈 격자 1번 자리")
			T.eq(d.incubators[3].z, g1.z)
			-- 옛 슬롯 n 자리 = 옛 MapLayout.incubatorSpots 의 n 번째 (월드) 자리
			for plot = 1, MapLayout.PLOT_COUNT do
				local world = MapLayout.toWorld(plot, s3.x, s3.z)
				T.eq(world.x, MapLayout.incubatorSpots(plot)[3].x)
				T.eq(world.z, MapLayout.incubatorSpots(plot)[3].z)
			end
			-- 대기 줄 → 가방 (새 uid, 모르는 펫은 버림)
			T.eq(d.eggQueue, nil)
			T.eq(#d.eggs, 2)
			T.eq(d.eggs[1].petId, "ring_guard")
			T.eq(d.eggs[1].size, "big")
			T.eq(d.eggs[1].mutations[1], "golden")
			T.eq(d.eggs[1].uid, "i10", "uid 카운터에서 새 uid")
			T.eq(d.eggs[2].petId, "jitterbug")
			T.eq(d.eggs[2].size, "normal")
			T.eq(d.eggs[2].progress, 0)
			T.eq(d.eggs[2].required, Loader.require("ReplicatedStorage/Shared/Economy").hatchSeconds("jitterbug"))
			T.eq(d.nextUid, 12)
		end
	)

	T.test(
		"마이그레이션 2 → 3: 가진 트레일 중 가장 높은 배율을 장착 (전에 자동 적용되던 것 → 속도 그대로)",
		function()
			local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
			local migrated = DataSchema.migrate({ version = 2, trails = { "grey", "purple", "blue", "가짜", 7 } })
			T.eq(migrated.version, 5)
			T.eq(migrated.equippedTrail, "purple")
			local d = DataSchema.reconcile(migrated, 0)
			T.eq(d.equippedTrail, "purple")
			T.eq(Economy.trailMultiplier(d.equippedTrail), Economy.bestTrailMultiplier(d.trails))
			-- 트레일이 없으면 none
			T.eq(DataSchema.migrate({ version = 2 }).equippedTrail, "none")
			T.eq(DataSchema.migrate({ version = 2, trails = "엉터리" }).equippedTrail, "none")
			T.eq(DataSchema.reconcile(DataSchema.migrate({ version = 2, trails = {} }), 0).equippedTrail, "none")
			-- 이미 3 이면 사용자가 고른 장착(해제 포함)을 바꾸지 않음
			local keep = DataSchema.migrate({ version = 3, trails = { "grey", "red" }, equippedTrail = "grey" })
			T.eq(keep.equippedTrail, "grey")
			local off = DataSchema.migrate({ version = 3, trails = { "red" }, equippedTrail = "none" })
			T.eq(DataSchema.reconcile(off, 0).equippedTrail, "none")
		end
	)

	T.test("v3 equippedTrail 보정: 가진 트레일만, 아니면 none", function()
		local function eq(raw)
			return DataSchema.reconcile(raw, 0).equippedTrail
		end
		T.eq(eq({ version = 3, trails = { "grey", "red" }, equippedTrail = "red" }), "red")
		T.eq(eq({ version = 3, trails = { "grey" }, equippedTrail = "red" }), "none", "안 가진 트레일")
		T.eq(eq({ version = 3, trails = { "grey" }, equippedTrail = "가짜" }), "none")
		T.eq(
			eq({ version = 3, trails = { "가짜" }, equippedTrail = "가짜" }),
			"none",
			"모르는 트레일은 목록에서도 빠짐"
		)
		T.eq(eq({ version = 3, trails = { "grey" }, equippedTrail = 5 }), "none")
		T.eq(eq({ version = 3, trails = { "grey" } }), "none")
		T.eq(eq({ version = 3, trails = { "grey" }, equippedTrail = "none" }), "none")
	end)

	T.test("v2 필드 보정: 잘못된 값 버리기 (옛 대기 줄은 가방으로, 가방 상한까지)", function()
		local queue = {}
		for i = 1, Config.EGG_INVENTORY_MAX + 5 do
			table.insert(queue, { petId = "ring_guard", size = "big", mutations = { "golden" }, source = "altar" })
			if i == 2 then
				table.insert(queue, { petId = "없는펫", size = "big", mutations = {}, source = "altar" })
			end
		end
		table.insert(queue, 1, { petId = "jitterbug", size = "이상함", mutations = {}, source = "해킹" })
		local d = DataSchema.reconcile({
			version = 2,
			sakuraCrystals = -3,
			sakuraUnlocked = "yes",
			shrineUsed = { equinox = true, chicken = true },
			quests = { deliver_eggs = 999, fuse_once = 0.5, ["가짜"] = 3 }, -- 5판: 옛 퀘스트 칸은 버려짐
			questsRewarded = true,
			weapons = { "katana", "baseball_bat", "가짜무기", "katana" },
			eggQueue = queue,
		}, 0)
		T.eq(d.sakuraCrystals, 0)
		T.falsy(d.sakuraUnlocked)
		T.truthy(d.shrineUsed.equinox)
		T.eq(d.shrineUsed.chicken, nil)
		T.eq(d.quests, nil, "5판: 퀘스트 칸은 reconcile 결과에 없음")
		T.eq(d.questsRewarded, nil)
		T.eq(#d.weapons, 1)
		T.eq(d.weapons[1], "katana")
		T.eq(#d.eggs, Config.EGG_INVENTORY_MAX)
		T.eq(d.eggs[1].petId, "jitterbug")
		T.eq(d.eggs[1].size, "normal")
		T.eq(d.eggs[2].mutations[1], "golden")
		T.eq(d.eggQueue, nil)
	end)

	T.test("돈·속도 상한, 넘친 펫은 팔아서 돈으로 (장착 펫은 안 팖)", function()
		local d = DataSchema.reconcile({ money = 1e300, speed = 1e300 }, 0)
		T.eq(d.money, Config.MONEY_MAX)
		T.eq(d.speed, Config.SPEED_MAX)
		local pets = {}
		for i = 1, Config.PET_INVENTORY_MAX + 3 do
			table.insert(pets, { uid = "p" .. i, petId = "chicken", size = "normal", mutations = {} })
		end
		pets[1].petId = "dog" -- 장착 펫 (수입 6)
		local loaded = DataSchema.reconcile({ pets = pets, equipped = { "p2" }, money = 0 }, 0)
		T.eq(#loaded.pets, Config.PET_INVENTORY_MAX)
		T.eq(loaded.equipped[1], "p2")
		local kept = {}
		for _, p in loaded.pets do
			kept[p.uid] = true
		end
		T.truthy(kept.p1 and kept.p2, "비싼 펫·장착 펫은 남음")
		T.eq(loaded.money, 3 * 3 * Config.PET_AUTO_SELL_SECONDS, "닭 3마리 × $3 × 60초")
	end)

	T.test("무기: 저장된 무기 ∪ 도감으로 해금되는 무기", function()
		local d = DataSchema.reconcile({ weapons = { "scythe" }, indexDiscovered = discoverAll("lake") }, 0)
		T.eq(#d.weapons, 2)
		T.eq(d.weapons[1], "water_bat", "구역 순서")
		T.eq(d.weapons[2], "scythe")
	end)
end
