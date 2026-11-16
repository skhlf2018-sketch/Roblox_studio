--!nocheck
-- 저장: DataSchema 보정 (이상한 값 막기) · DataService 저장/불러오기 왕복 · 세션 락 · 새 버전 보호
return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	T.suite("save_data: DataSchema")

	T.test("기본값 (스키마 1)", function()
		local H = ServerHarness.install(Loader, T)
		local DataSchema = H.server("Logic/DataSchema")
		local d = DataSchema.default(0)
		T.eq(d.version, 1)
		T.eq(d.power, 0)
		T.eq(d.money, 0)
		T.eq(d.dumbbellLevel, 1)
		T.eq(d.belt, 1)
		T.eq(d.world, 1)
		T.eq(d.powerBoost, 1)
		T.eq(d.moneyPass, false)
		T.eq(d.grandMaster, false)
		T.eq(d.settings.music, true)
		T.eq(d.stats.hits, 0)
		H.uninstall()
	end)

	T.test("reconcile: NaN · 무한 · 음수 · 글자 · 범위 밖 · 모르는 id 를 고침", function()
		local H = ServerHarness.install(Loader, T)
		local DataSchema = H.server("Logic/DataSchema")
		local d = DataSchema.reconcile({
			power = 0 / 0,
			money = math.huge,
			dumbbellLevel = 99,
			belt = -3,
			world = 3,
			broken = { cotton = 5, nope = 3, glass = -1, wood = 0 / 0, [1] = 4 },
			powerBoost = 3,
			moneyPass = "yes",
			grandMaster = true,
			receipts = { "a", "a", 5, string.rep("x", 65), "b" },
			stats = { hits = -5, breaks = 0 / 0, trains = 12 },
			settings = { music = false, sfx = "on", hack = true },
			junk = { 1, 2, 3 },
		}, 0)
		T.eq(d.power, 0, "NaN 힘")
		T.eq(d.money, 0, "무한 돈")
		T.eq(d.dumbbellLevel, H.shared("Data/Dumbbells").COUNT, "99 → 마지막 아령")
		T.eq(d.belt, 1, "음수 띠 → 1")
		T.eq(d.world, 1, "띠 1 이면 월드 3 못 감")
		T.eq(d.broken.cotton, 5)
		T.eq(d.broken.nope, nil)
		T.eq(d.broken.glass, nil)
		T.eq(d.broken.wood, nil)
		T.eq(d.powerBoost, 1, "표에 없는 배수")
		T.eq(d.moneyPass, false, "글자")
		T.eq(d.grandMaster, false, "마지막 띠가 아니면")
		T.eq(#d.receipts, 2, "중복·숫자·너무 긴 것 뺌")
		T.eq(d.stats.hits, 0)
		T.eq(d.stats.breaks, 0)
		T.eq(d.stats.trains, 12)
		T.eq(d.settings.music, false)
		T.eq(d.settings.sfx, true, "글자면 기본값")
		T.eq(d.settings.hack, nil)
		T.eq(d.junk, nil, "모르는 칸 버림")
		local Belts = H.shared("Data/Belts")
		local big =
			DataSchema.reconcile({ power = 1e70, money = 1e61, belt = Belts.COUNT, world = 3, grandMaster = true }, 0)
		T.eq(big.power, 1e60, "1e60 에서 자름")
		T.eq(big.money, 1e60)
		T.eq(big.world, 3)
		T.truthy(big.grandMaster)
		T.eq(DataSchema.reconcile("garbage", 0).belt, 1, "표가 아님")
		-- 띠 22개 (결정 16번): 띠 개수로 자르고, 월드는 띠에 맞춤 (띠 ≥ 8 → 월드 ≥ 2 · 띠 ≥ 15 → 월드 3)
		T.eq(DataSchema.reconcile({ belt = 99 }, 0).belt, Belts.COUNT, "99 → 마지막 띠")
		T.eq(DataSchema.reconcile({ belt = 99 }, 0).world, 3)
		T.eq(DataSchema.reconcile({ belt = 12, world = 3, grandMaster = true }, 0).world, 2, "9단 띠는 월드 2")
		T.eq(DataSchema.reconcile({ belt = 12, world = 3, grandMaster = true }, 0).grandMaster, false)
		T.eq(DataSchema.reconcile({ belt = 8, world = 1 }, 0).world, 2, "띠 8 인데 월드 1 → 2 로 맞춤")
		T.eq(DataSchema.reconcile({ belt = 15, world = 1 }, 0).world, 3, "띠 15 인데 월드 1 → 3")
		for belt = 1, Belts.COUNT do
			local d2 = DataSchema.reconcile({ belt = belt, world = 1 }, 0)
			T.eq(d2.belt, belt)
			T.eq(d2.world, Belts.get(belt).world + (if Belts.get(belt).duel and belt < Belts.COUNT then 1 else 0))
		end
		H.uninstall()
	end)

	T.test("isNewerVersion · migrate", function()
		local H = ServerHarness.install(Loader, T)
		local DataSchema = H.server("Logic/DataSchema")
		T.truthy(DataSchema.isNewerVersion({ version = 2 }))
		T.falsy(DataSchema.isNewerVersion({ version = 1 }))
		T.falsy(DataSchema.isNewerVersion(nil))
		T.eq(DataSchema.migrate({ version = 2 }).version, 2, "새 버전은 그대로")
		T.eq(DataSchema.migrate({}).version, 1)
		H.uninstall()
	end)

	T.suite("save_data: DataService 왕복")

	local function setup()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		H.Data = H.server("Services/DataService")
		H.Data.start()
		H.Sessions = H.server("Sessions")
		return H
	end

	local function load(H, player)
		local session = H.Sessions.create(player)
		local data, saveEnabled, newer = H.run(function()
			return H.Data.load(player)
		end)
		session.data = data
		session.saveEnabled = saveEnabled
		session.loaded = true
		return session, data, saveEnabled, newer
	end

	T.test(
		"저장 → 나감(락 해제) → 다시 불러오기: 값이 그대로 (BoardBreak_PlayerData, player_<id>)",
		function()
			local H = setup()
			local p = H.newPlayer(77)
			local _, data, saveEnabled = load(H, p)
			T.truthy(saveEnabled, "저장 켜짐")
			data.power = 1.23e45
			data.money = 4.56e20
			data.dumbbellLevel = 12
			data.belt = 16
			data.world = 3
			data.broken = { cotton = 99, moon = 1 }
			data.powerBoost = 64
			data.moneyPass = true
			data.receipts = { "r1" }
			data.settings.sfx = false
			local ok = H.run(function()
				return H.Data.save(p, true)
			end)
			T.truthy(ok, "저장 성공")
			local stored = H.store.data["player_77"]
			T.truthy(stored and stored.data, "키 player_77")
			T.eq(stored._lock, nil, "락 해제")
			H.Sessions.remove(p)
			local p2 = H.newPlayer(77)
			local _, again = load(H, p2)
			T.eq(again.power, 1.23e45)
			T.eq(again.money, 4.56e20)
			T.eq(again.dumbbellLevel, 12)
			T.eq(again.belt, 16)
			T.eq(again.world, 3)
			T.eq(again.broken.cotton, 99)
			T.eq(again.broken.moon, 1)
			T.eq(again.powerBoost, 64)
			T.eq(again.moneyPass, true)
			T.eq(again.receipts[1], "r1")
			T.eq(again.settings.sfx, false)
			H.uninstall()
		end
	)

	T.test("저장된 데이터가 망가져 있어도 불러올 때 고침 (NaN 힘 · 월드 > 띠)", function()
		local H = setup()
		H.store.data["player_5"] = { data = { version = 1, power = 0 / 0, belt = 2, world = 3, money = -1 } }
		local p = H.newPlayer(5)
		local _, data = load(H, p)
		T.eq(data.power, 0)
		T.eq(data.world, 1)
		T.eq(data.money, 0)
		H.uninstall()
	end)

	T.test("더 새 버전 데이터 → 이번 접속은 저장 안 함 (덮어쓰지 않음)", function()
		local H = setup()
		H.store.data["player_6"] = { data = { version = 2, power = 50 } }
		local p = H.newPlayer(6)
		local _, data, saveEnabled, newer = load(H, p)
		T.truthy(newer)
		T.falsy(saveEnabled)
		data.power = 1
		H.run(function()
			return H.Data.save(p, true)
		end)
		T.eq(H.store.data["player_6"].data.version, 2, "그대로")
		T.eq(H.store.data["player_6"].data.power, 50)
		H.uninstall()
	end)

	T.test(
		"다른 서버가 락을 잡고 있으면 기다렸다가 가져옴 · 저장 중 락을 뺏기면 저장 멈춤",
		function()
			local H = setup()
			H.store.data["player_8"] =
				{ data = { version = 1, power = 10 }, _lock = { jobId = "other", time = H.time() } }
			local p = H.newPlayer(8)
			local session, data, saveEnabled = load(H, p)
			T.truthy(saveEnabled, "기다린 뒤 가져옴")
			T.eq(data.power, 10)
			H.store.data["player_8"]._lock = { jobId = "other", time = H.time() }
			data.power = 999
			local ok = H.run(function()
				return H.Data.save(p, false)
			end)
			T.falsy(ok, "뺏김")
			T.falsy(session.saveEnabled, "저장 멈춤")
			T.eq(H.store.data["player_8"].data.power, 10, "덮어쓰지 않음")
			H.uninstall()
		end
	)

	T.test(
		"스튜디오에서 DataStore 가 막혀 있으면 메모리 모드 (기본 데이터, 저장 안 함)",
		function()
			local H = ServerHarness.install(Loader, T)
			H.startNet()
			H.DataStoreService.available = false
			local Data = H.server("Services/DataService")
			Data.start()
			T.truthy(Data.isMemoryMode())
			local p = H.newPlayer(9)
			local data, saveEnabled = H.run(function()
				return Data.load(p)
			end)
			T.falsy(saveEnabled)
			T.eq(data.belt, 1)
			H.uninstall()
		end
	)
end
