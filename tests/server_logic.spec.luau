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

	T.test("부화 슬롯: 필요 시간 다시 계산, 슬롯 중복·범위 밖 제거", function()
		local d = DataSchema.reconcile({
			incubators = {
				{ uid = "i1", petId = "king_snake", size = "normal", mutations = {}, slot = 1, progress = 99999, required = 5 },
				{ uid = "i2", petId = "chicken", size = "normal", mutations = {}, slot = 1, progress = 0 },
				{ uid = "i3", petId = "chicken", size = "normal", mutations = {}, slot = 99, progress = 0 },
				{ uid = "i4", petId = "dog", size = "normal", mutations = {}, slot = 2, progress = 2 },
			},
		}, 0)
		T.eq(#d.incubators, 2)
		T.eq(d.incubators[1].required, 1800, "5400 ÷ 3")
		T.eq(d.incubators[1].progress, 1800, "필요량 넘지 않음")
		T.eq(d.incubators[1].biomeId, "jungle")
		T.eq(d.incubators[2].uid, "i4")
	end)

	T.test("newUid 는 증가", function()
		local d = DataSchema.default(0)
		T.eq(DataSchema.newUid(d, "p"), "p1")
		T.eq(DataSchema.newUid(d, "i"), "i2")
		T.eq(d.nextUid, 3)
	end)
end
