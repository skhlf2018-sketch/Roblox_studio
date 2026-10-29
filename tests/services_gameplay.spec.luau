--!nocheck
--[[
	서비스 테스트 2 (6판): BaseService(배달 → 씨앗 가방·정원에 심기·성장 → 성체·건너뛰기), SakuraService(씨앗 버전)
	(6판: FusionService·AltarService 는 사장님 결정으로 없앰 — 열매는 tests/garden.spec)
	(5판: QuestService 는 없앰 — 튜토리얼은 tests/tutorial.spec, 랭킹판·쓰다듬기는 tests/social.spec)
	진짜 서비스 코드 + 진짜 shared 규칙을 ServerHarness 위에서 돌립니다 (가상 시간).
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function world()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.Pets = H.shared("Data/Pets")
		w.Economy = H.shared("Economy")
		w.EggPlacement = H.shared("EggPlacement")
		w.DataSchema = H.server("Logic/DataSchema")
		w.BaseService = H.server("Services/BaseService")
		w.PetService = H.server("Services/PetService")
		w.player = H.newPlayer(1001, "Tester")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		return w
	end

	local function playerWith(w, userId, name)
		local p = w.H.newPlayer(userId, name)
		local session, data = w.H.login(p)
		session.plotIndex = 1
		return p, session, data
	end

	-- 가방을 n 개 채움 (선물 알)
	local function fillBag(w, n, player)
		for _ = 1, n do
			w.BaseService.grantEgg(player or w.player, "sprout_daisy", "normal", {}, "sakura")
		end
	end

	-- 우리 로컬 (lx, lz) → 그 베이스 월드 x, z
	local function penWorld(w, lx, lz, plotIndex)
		local spot = w.H.MapLayout.toWorld(plotIndex or 1, lx, lz)
		return spot.x, spot.z
	end

	-- 가방에 선물 알을 받고 우리 빈 격자 자리에 놓음 (캐릭터가 없으면 내 베이스 앞마당에 세움) → 놓인 기록
	local function placeNew(w, petId, size, mutations, player, data)
		player = player or w.player
		data = data or w.data
		if not player.Character then
			local x, z = w.H.plotSpot(1)
			w.H.spawn(player, x, 3, z)
		end
		w.BaseService.grantEgg(player, petId, size or "normal", mutations or {}, "sakura")
		local egg = data.eggs[#data.eggs]
		local spots = {}
		for _, r in data.incubators do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		local l = w.EggPlacement.firstFreeGrid(egg.size, spots)
		local x, z = penWorld(w, l.x, l.z)
		assert(w.BaseService.placeEgg(player, egg.uid, x, z), "placeNew 실패")
		return data.incubators[#data.incubators]
	end

	local function countNotify(w, fragment)
		local n = 0
		for _, item in w.H.notifications(w.player) do
			if string.find(item.text, fragment, 1, true) then
				n += 1
			end
		end
		return n
	end

	------------------------------------------------------------------
	T.suite("서비스: BaseService 선물 알 (2판 수정: 알 가방으로, 대기 줄 없음)")

	T.test("선물 알은 가방으로 (최대 50), 가득 차면 거부, 모르는 펫 거부", function()
		local w = world()
		local B = w.BaseService
		T.eq(w.Config.EGG_INVENTORY_MAX, 50)
		T.eq(B.grantEgg(w.player, "rune_rose", "big", { "golden" }, "sakura"), "bag")
		T.eq(#w.data.eggs, 1)
		T.eq(#w.data.incubators, 0, "우리에 저절로 놓이지 않음")
		local first = w.data.eggs[1]
		T.eq(first.petId, "rune_rose")
		T.eq(first.size, "big")
		T.eq(first.mutations[1], "golden")
		T.eq(first.required, w.Economy.hatchSeconds("rune_rose"), "필요 시간 = 원작 그대로")
		T.eq(first.progress, 0)
		T.eq(first.uid, "i1")
		local granted = w.H.sent(w.player, "EggGranted")[1][1]
		T.eq(granted.egg.uid, "i1")
		T.eq(granted.queued, false)
		T.eq(granted.source, "sakura")
		local update = w.H.sent(w.player, "DataUpdate")
		T.eq(update[#update][1], "eggs")
		T.eq(#update[#update][2].eggs, 1)
		fillBag(w, w.Config.EGG_INVENTORY_MAX - 1)
		T.eq(#w.data.eggs, 50)
		T.eq(B.grantEgg(w.player, "dancing_mushroom", "normal", {}, "dev"), nil, "51번째는 자리 없음")
		T.falsy(B.canReceiveEgg(w.player))
		T.eq(#w.data.eggs, 50)
		T.eq(B.grantEgg(w.player, "없는펫", "normal", {}, "sakura"), nil)
		T.eq(w.data.eggQueue, nil, "대기 줄 없음")
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: BaseService 배달 (2판 수정: 알을 들고 허브에 들어오면 → 알 가방)")

	T.test(
		"배달하면 가방에 (우리에는 안 놓임), 통계·EggDelivered·DataUpdate(eggs)·신호",
		function()
			local w = world()
			local B = w.BaseService
			local signals = {}
			B.delivered:connect(function(_, record)
				table.insert(signals, record)
			end)
			w.H.carry(w.player, { petId = "sprout_daisy", biomeId = "forest", size = "huge", mutations = { "silver" } })
			B.deliver(w.player)
			T.eq(#w.data.eggs, 1)
			T.eq(#w.data.incubators, 0)
			local egg = w.data.eggs[1]
			T.eq(egg.petId, "sprout_daisy")
			T.eq(egg.size, "huge")
			T.eq(egg.mutations[1], "silver")
			T.eq(egg.biomeId, "forest")
			T.eq(egg.uid, "i1")
			T.eq(egg.progress, 0)
			T.eq(egg.required, w.Economy.hatchSeconds("sprout_daisy"))
			T.eq(egg.special, false)
			T.eq(egg.slot, nil)
			T.eq(w.data.stats.eggsDelivered, 1)
			T.eq(w.H.eggs.taken, 1)
			local delivered = w.H.sent(w.player, "EggDelivered")
			T.eq(#delivered, 1)
			T.eq(delivered[1][1].uid, "i1", '"에그를 훔쳤어요!" 토스트 = 가방에 들어간 알')
			local update = w.H.sent(w.player, "DataUpdate")
			T.eq(update[#update][1], "eggs")
			T.eq(#signals, 1, "퀘스트·사쿠라가 받는 신호")
			T.eq(signals[1].biomeId, "forest")
			-- 같은 알로 두 번 배달 불가 (이미 가져감)
			B.deliver(w.player)
			T.eq(#w.data.eggs, 1)
			-- 특별 알은 special 표시가 남음
			w.H.carry(w.player, { petId = "puppy_grass", biomeId = "forest", special = true })
			B.deliver(w.player)
			T.truthy(w.data.eggs[2].special)
			w.H.uninstall()
		end
	)

	T.test(
		"알 가방(50)이 가득 차면 배달 거부 (알은 그대로 손에), 안내는 3초에 한 번",
		function()
			local w = world()
			local B = w.BaseService
			fillBag(w, 50)
			w.H.carry(w.player, { petId = "puppy_grass", biomeId = "forest" })
			B.deliver(w.player)
			B.deliver(w.player)
			T.eq(w.H.eggs.taken, 0, "알을 안 가져감")
			T.truthy(w.H.eggs.carried[w.player], "알은 계속 들고 있음")
			T.eq(#w.data.eggs, 50)
			T.eq(countNotify(w, "씨앗 가방이 가득 찼어요"), 1, "3초 안에는 한 번만")
			w.H.advance(3.1)
			B.deliver(w.player)
			T.eq(countNotify(w, "씨앗 가방이 가득 찼어요"), 2)
			-- 가방을 하나 비우면 (우리에 놓기) 배달됨
			table.remove(w.data.eggs, 1)
			B.deliver(w.player)
			T.eq(w.H.eggs.taken, 1)
			T.eq(#w.data.eggs, 50)
			w.H.uninstall()
		end
	)

	T.test(
		"순간이동 의심: 주운 곳에서 너무 빨리 허브에 오면 배달 거부 + 알은 둥지로 + 경고",
		function()
			local w = world()
			local B = w.BaseService
			w.session.walkSpeed = 16
			-- 1000스터드 떨어진 곳에서 방금 주웠는데 벌써 배달 → 최소 49초 걸려야 함
			w.H.carry(w.player, {
				petId = "sprout_daisy",
				biomeId = "forest",
				pickedPosition = w.H.vec(0, 0, 1020),
				originAt = w.H.clock(),
			})
			B.deliver(w.player)
			T.eq(#w.data.eggs, 0)
			T.eq(w.H.eggs.confiscated, 1)
			T.eq(w.H.eggs.taken, 0)
			T.eq(w.player.attrs.MoveWarnings, 1, "치트 경고 1")
			T.truthy(w.H.hasNotify(w.player, "error", "비정상적인 움직임"))
			-- 충분히 시간이 지난 뒤면 정상 배달
			w.H.carry(w.player, {
				petId = "sprout_daisy",
				biomeId = "forest",
				pickedPosition = w.H.vec(0, 0, 1020),
				originAt = w.H.clock() - 60,
			})
			B.deliver(w.player)
			T.eq(#w.data.eggs, 1)
			w.H.uninstall()
		end
	)

	T.test(
		"2판 수정: 알을 든 채 허브(z < 0)에 들어오는 순간 자동 배달 — 경계 z = 0 은 아직 숲, 내 베이스가 아니어도·베이스가 없어도 됨",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			w.H.spawn(w.player, 30, 3, 10) -- 숲
			w.H.carry(w.player, { petId = "sprout_daisy", biomeId = "forest" })
			w.H.advance(1)
			T.eq(#w.data.eggs, 0, "구역 안")
			w.H.teleport(w.player, 30, 3, 0) -- 허브 경계선 위 = 숲 (z ≥ 0)
			w.H.advance(0.4)
			T.eq(#w.data.eggs, 0, "경계선 위는 아직 허브 아님")
			T.truthy(w.H.eggs.carried[w.player], "아직 들고 있음")
			w.H.teleport(w.player, 30, 3, -0.01)
			w.H.advance(0.2)
			T.eq(#w.data.eggs, 1, "허브에 발을 들이자마자")
			T.eq(#w.H.sent(w.player, "EggDelivered"), 1)
			T.eq(w.player.attrs.InSafeZone, true)
			-- 베이스가 없는 사람(8번째)도 허브에 들어오면 가방으로
			local late, lateSession, lateData = playerWith(w, 1099, "Late")
			lateSession.plotIndex = 0
			w.H.spawn(late, -30, 3, 5)
			w.H.carry(late, { petId = "puppy_grass", biomeId = "forest" })
			w.H.advance(0.4)
			T.eq(#lateData.eggs, 0)
			w.H.teleport(late, -30, 3, -5)
			w.H.advance(0.4)
			T.eq(#lateData.eggs, 1, "베이스 없어도 가방으로")
			T.eq(lateData.eggs[1].petId, "puppy_grass")
			w.H.uninstall()
		end
	)

	T.test("공중(바닥에서 20 이상)에서는 배달 안 됨", function()
		local w = world()
		local B = w.BaseService
		B.start()
		local hx, hz = w.H.hubSpot()
		w.H.spawn(w.player, hx, 30, hz)
		w.H.carry(w.player, { petId = "sprout_daisy", biomeId = "forest" })
		w.H.advance(1)
		T.eq(#w.data.eggs, 0)
		w.H.teleport(w.player, hx, 3, hz)
		w.H.advance(0.4)
		T.eq(#w.data.eggs, 1, "내려오면 배달")
		w.H.uninstall()
	end)

	T.test(
		"알 든 채 한 번에 너무 멀리 움직이면(순간이동) 그 자리에 알 떨어뜨림 + 경고 (허브로 순간이동해도 배달 안 됨)",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			w.H.spawn(w.player, 0, 3, 80) -- 숲
			w.H.carry(w.player, { petId = "sprout_daisy", biomeId = "forest" })
			w.H.advance(0.2) -- 위치 기록
			w.H.teleport(w.player, 0, 3, -5) -- 85스터드 순간이동 (0.2초 허용은 약 13)
			w.H.advance(0.2)
			T.eq(#w.data.eggs, 0, "배달 안 됨")
			T.eq(#w.H.eggs.droppedAt, 1, "마지막 정상 위치에 떨어짐")
			T.eq(w.H.eggs.droppedAt[1].Z, 80)
			T.eq(w.player.attrs.MoveWarnings, 1)
			w.H.uninstall()
		end
	)

	T.test(
		"밤이 되면 알 든 사람이 허브 밖이면 집으로 텔레포트 → 허브라 다음 틱에 가방으로 배달",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local zx, zz = w.H.zoneSpot("lake")
			w.H.spawn(w.player, zx, 3, zz)
			w.H.carry(w.player, { petId = "sprout_daisy", biomeId = "forest" })
			w.H.advance(0.2)
			w.H.setPhase("Night")
			local spawn = w.H.MapLayout.plot(1).spawn
			T.eq(w.player.Character.root.Position.X, spawn.x, "앞마당 스폰으로")
			T.eq(w.player.Character.root.Position.Z, spawn.z)
			T.near(w.player.Character.root.Position.Y, 4.2, 1e-9, "바닥(0.2) + 4")
			T.eq(w.player.Character.root.CFrame.LookVector.X, 1, "복도 가운데를 봄")
			w.H.advance(0.4)
			T.eq(#w.data.eggs, 1, "집(허브)에 오자마자 배달")
			T.eq(#w.H.eggs.droppedAt, 0, "서버 순간이동은 치트로 안 봄")
			-- 허브 안에서 알을 들고 있으면(가방이 가득 참) 그대로
			fillBag(w, 49)
			local hx, hz = w.H.hubSpot()
			w.H.teleport(w.player, hx, 3, hz)
			w.H.carry(w.player, { petId = "puppy_grass", biomeId = "forest" })
			w.H.setPhase("Day")
			w.H.setPhase("Night")
			T.eq(w.player.Character.root.Position.Z, hz, "허브 안이면 순간이동 안 함")
			w.H.uninstall()
		end
	)

	T.test(
		"밤이 되면 알이 없어도 허브 밖(z ≥ 0)에 있던 사람은 집으로 (밤 벽에 안 갇힘), 허브 안이면 그대로",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local zx, zz = w.H.zoneSpot("lake")
			w.H.spawn(w.player, zx + 10, 3, zz)
			w.H.setPhase("Night")
			local spawn = w.H.MapLayout.plot(1).spawn
			T.eq(w.player.Character.root.Position.X, spawn.x, "구역 → 베이스 앞마당")
			T.truthy(w.session.moveExemptUntil > w.H.clock(), "서버 순간이동 → 위치 검증 쉼")
			w.H.teleport(w.player, 0, 3, 0) -- 허브 경계선 위 = 숲 쪽(z ≥ 0)
			w.H.setPhase("Day")
			w.H.setPhase("Night")
			T.eq(w.player.Character.root.Position.X, spawn.x, "경계선 위도 밖")
			local hx, hz = w.H.hubSpot()
			w.H.teleport(w.player, hx, 3, hz)
			w.H.setPhase("Day")
			w.H.setPhase("Night")
			T.eq(w.player.Character.root.Position.Z, hz, "허브 안이면 그대로")
			-- 베이스가 없는 사람(8번째) → 허브 기본 스폰
			w.session.plotIndex = 0
			w.H.teleport(w.player, zx, 3, zz)
			w.H.setPhase("Day")
			w.H.setPhase("Night")
			T.eq(w.player.Character.root.Position.Z, w.H.MapLayout.hubSpots.mainSpawn.z, "허브 스폰")
			w.H.uninstall()
		end
	)

	T.test(
		"구역 표시: CurrentZone(구역 id / hub), InSafeZone(허브), 새 구역에 들어가면 ZoneEntered 1번씩",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local hx, hz = w.H.hubSpot()
			w.H.spawn(w.player, hx, 3, hz)
			w.H.advance(0.2)
			T.eq(w.player.attrs.CurrentZone, "hub")
			T.eq(w.player.attrs.InSafeZone, true)
			T.eq(#w.H.sent(w.player, "ZoneEntered"), 0, "허브는 배너 없음")
			w.H.teleport(w.player, 0, 3, 10)
			w.H.advance(0.4)
			T.eq(w.player.attrs.CurrentZone, "forest")
			T.eq(w.player.attrs.InSafeZone, false)
			w.H.teleport(w.player, 0, 3, 250)
			w.H.advance(0.4)
			w.H.teleport(w.player, 0, 3, 260)
			w.H.advance(0.4)
			local entered = w.H.sent(w.player, "ZoneEntered")
			T.eq(#entered, 2, "숲 1번, 호수 1번 (같은 구역 안에서 움직이면 안 보냄)")
			T.eq(entered[1][1].biomeId, "forest")
			T.eq(entered[2][1].biomeId, "lake")
			T.eq(entered[2][1].name, "호수")
			T.eq(entered[2][1].nameEn, "Lake")
			-- 맵 끝 너머는 ""
			w.H.teleport(w.player, 0, 3, 5000)
			w.H.advance(0.4)
			T.eq(w.player.attrs.CurrentZone, "")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: BaseService 우리에 알 놓기 (PlaceEgg) · 다시 줍기 (PickUpPlacedEgg)")

	local function placeWorld()
		local w = world()
		w.BaseService.start()
		local x, z = w.H.plotSpot(1)
		w.H.spawn(w.player, x, 3, z) -- 내 베이스 앞마당
		return w
	end

	T.test(
		"가방의 알을 우리 안 원하는 자리에 놓으면 그 자리에 IncubatingEgg + 부화 시작 (베이스 기준 좌표로 저장)",
		function()
			local w = placeWorld()
			local B = w.BaseService
			B.grantEgg(w.player, "sprout_daisy", "big", { "silver" }, "sakura")
			local uid = w.data.eggs[1].uid
			w.H.clearSent()
			local x, z = penWorld(w, -12.34, 5.06)
			w.H.client(w.player, "PlaceEgg", uid, x, z)
			T.eq(#w.data.eggs, 0, "가방에서 빠짐")
			T.eq(#w.data.incubators, 1)
			local record = w.data.incubators[1]
			T.eq(record.uid, uid, "같은 uid")
			T.eq(record.x, -12.3, "베이스 기준 좌표, 0.1 반올림")
			T.eq(record.z, 5.1)
			T.eq(record.size, "big")
			T.eq(record.mutations[1], "silver")
			T.eq(record.progress, 0)
			local sections = {}
			for _, args in w.H.sent(w.player, "DataUpdate") do
				sections[args[1]] = true
			end
			T.truthy(sections.eggs and sections.incubators, "가방·놓인 알 둘 다 알림")
			local parts = w.H.map.folders.Incubating.children
			T.eq(#parts, 1)
			local part = parts[1]
			local wx, wz = penWorld(w, -12.3, 5.1)
			T.near(part.Position.X, wx, 1e-9, "고른 자리")
			T.near(part.Position.Z, wz, 1e-9)
			T.truthy(w.H.MapLayout.isInPen(part.Position, 1), "우리 안")
			T.eq(part:GetAttribute("EggUid"), uid)
			T.eq(part:GetAttribute("OwnerUserId"), w.player.UserId)
			T.eq(part:GetAttribute("PlotIndex"), 1)
			T.eq(part:GetAttribute("Ready"), false)
			-- 놓인 알만 자람, 가방 속 알은 그대로
			B.grantEgg(w.player, "puppy_grass", "normal", {}, "sakura")
			w.H.advance(3)
			T.near(record.progress, 3, 1e-9, "놓인 알은 자람")
			T.eq(part:GetAttribute("Progress"), record.progress)
			T.eq(w.data.eggs[1].progress, 0, "가방 속 알은 안 자람")
			w.H.setPhase("Night")
			w.H.advance(1)
			T.eq(w.data.eggs[1].progress, 0, "밤에도 가방 속 알은 안 자람")
			-- 다른 베이스(오른쪽 2번)를 받아도 같은 로컬 자리 = 거울 자리
			local mirrored = w.H.MapLayout.toWorld(2, record.x, record.z)
			T.near(mirrored.x, -wx, 1e-9, "오른쪽 베이스는 x 거울")
			w.H.uninstall()
		end
	)

	T.test(
		"PlaceEgg 거부: 우리 밖(앞마당·울타리 2 안·남의 우리) / 다른 씨앗과 너무 가까움(큰 씨앗은 더 멀리) / 정원 칸 초과 / 멀리서 / 베이스 없음",
		function()
			local w = placeWorld()
			local B = w.BaseService
			fillBag(w, 12)
			local function try(lx, lz, uid, plotIndex)
				local x, z = penWorld(w, lx, lz, plotIndex)
				return B.placeEgg(w.player, uid or w.data.eggs[1].uid, x, z)
			end
			-- 우리 밖
			T.falsy(try(20, 0), "앞마당")
			T.truthy(w.H.hasNotify(w.player, "error", "정원(울타리) 안에만"))
			T.falsy(try(9.5, 0), "울타리에서 2 안쪽까지만 (우리 끝 11)")
			T.falsy(try(0, 28.5), "옆 울타리")
			T.falsy(try(0, 0, nil, 2), "남의 우리 (2번 베이스 자리)")
			T.eq(#w.data.incubators, 0)
			T.truthy(try(9, 28), "울타리에서 딱 2 안쪽은 됨")
			-- 간격: 보통 알끼리 4
			T.truthy(try(0, 0))
			T.falsy(try(0, 3.9), "4 안")
			T.truthy(w.H.hasNotify(w.player, "error", "너무 가까워요"))
			T.truthy(try(0, 4), "딱 4 는 됨")
			-- 큰 알: 초거대(지름 4.8)끼리는 4.8
			B.grantEgg(w.player, "pharaoh_palm", "giant", {}, "sakura")
			B.grantEgg(w.player, "pharaoh_palm", "giant", {}, "sakura")
			local g1, g2 = w.data.eggs[#w.data.eggs - 1].uid, w.data.eggs[#w.data.eggs].uid
			T.truthy(try(-20, 0, g1))
			T.falsy(try(-20, 4.5, g2), "초거대끼리 4.5 는 겹침")
			T.truthy(try(-20, 4.8, g2), "초거대끼리 4.8 은 됨")
			T.eq(#w.data.incubators, 5)
			-- 6판: 정원 칸 수(1레벨 7칸)까지
			T.truthy(try(-30, -20))
			T.truthy(try(-30, -10))
			T.eq(#w.data.incubators, w.H.shared("Economy").penSlots(1))
			T.falsy(try(-30, 10), "8번째")
			T.truthy(w.H.hasNotify(w.player, "error", "정원이 가득 찼어요"))
			-- 멀리서 (내 베이스 밖, 그 자리에서 14 넘게)
			table.remove(w.data.incubators, 1)
			w.H.teleport(w.player, 0, 3, 100)
			T.falsy(try(-30, 10), "구역에서 원격으로")
			T.truthy(w.H.hasNotify(w.player, "error", "가까이에서"))
			-- 베이스 밖이어도 그 자리 14 안이면 됨 (울타리 바로 바깥)
			local plot = w.H.MapLayout.plot(1)
			local sx, sz = penWorld(w, -30, 26)
			w.H.teleport(w.player, sx, 3, plot.center.z + 31)
			T.falsy(w.H.MapLayout.isInPlot(w.player.Character.root.Position, 1), "베이스 밖에 서 있음")
			T.truthy(B.placeEgg(w.player, w.data.eggs[1].uid, sx, sz), "14 안")
			-- 베이스가 없으면
			table.remove(w.data.incubators, 1)
			w.session.plotIndex = 0
			T.falsy(try(-30, -26))
			T.truthy(w.H.hasNotify(w.player, "error", "아직 내 베이스가 없어요"))
			w.H.uninstall()
		end
	)

	T.test(
		"PlaceEgg 이상한 요청: 가방에 없는 uid·남의 알·이상한 인자(NaN·inf·글자)는 아무 일 없음",
		function()
			local w = placeWorld()
			local other, _, otherData = playerWith(w, 1002, "Other")
			otherData.nextUid = 100
			w.BaseService.grantEgg(other, "sprout_daisy", "normal", {}, "sakura")
			local theirs = otherData.eggs[1].uid
			w.BaseService.grantEgg(w.player, "sprout_daisy", "normal", {}, "sakura")
			local mine = w.data.eggs[1].uid
			local x, z = penWorld(w, 0, 0)
			w.H.client(w.player, "PlaceEgg", theirs, x, z)
			T.eq(#w.data.incubators, 0)
			T.eq(#otherData.eggs, 1, "남의 가방 그대로")
			w.H.advance(2)
			for _, args in
				{
					{ mine, 0 / 0, z },
					{ mine, x, math.huge },
					{ mine, "1", z },
					{ mine },
					{ 5, x, z },
					{ "../x", x, z },
				}
			do
				w.H.client(w.player, "PlaceEgg", table.unpack(args, 1, 3))
				w.H.advance(1)
			end
			T.eq(#w.data.incubators, 0)
			T.eq(#w.data.eggs, 1)
			w.H.client(w.player, "PlaceEgg", mine, x, z)
			T.eq(#w.data.incubators, 1, "올바른 요청은 됨")
			-- 이미 놓은 알을 또 놓기 → 가방에 없음
			w.H.advance(1)
			local x2, z2 = penWorld(w, -10, -10)
			w.H.client(w.player, "PlaceEgg", mine, x2, z2)
			T.eq(#w.data.incubators, 1)
			T.eq(w.data.incubators[1].x, 0)
			w.H.uninstall()
		end
	)

	T.test(
		"PickUpPlacedEgg: 놓인 알 → 가방 (진행도 유지), 다시 놓으면 이어서 자람 / 가방이 차면 거부 / ALLOW_EGG_PICKUP 끄면 거부",
		function()
			local w = placeWorld()
			local B = w.BaseService
			local record = placeNew(w, "moon_ghost_tree")
			w.H.advance(5)
			T.near(record.progress, 5, 1e-9)
			w.H.client(w.player, "PickUpPlacedEgg", record.uid)
			T.eq(#w.data.incubators, 0)
			T.eq(#w.data.eggs, 1)
			local egg = w.data.eggs[1]
			T.eq(egg.uid, record.uid)
			T.near(egg.progress, 5, 1e-9, "진행도 유지")
			T.truthy(w.H.map.folders.Incubating.children[1] == nil, "우리에서 알 파트가 사라짐")
			w.H.advance(5)
			T.near(egg.progress, 5, 1e-9, "가방 속에서는 안 자람")
			local x, z = penWorld(w, -5, 5)
			T.truthy(B.placeEgg(w.player, egg.uid, x, z))
			w.H.advance(2)
			T.near(w.data.incubators[1].progress, 7, 1e-9, "이어서 자람")
			-- 남의 알 / 없는 uid
			T.falsy(B.pickUpEgg(w.player, "i999"))
			-- 가방이 가득 차면 거부
			fillBag(w, 50)
			T.falsy(B.pickUpEgg(w.player, w.data.incubators[1].uid))
			T.eq(#w.data.incubators, 1)
			T.truthy(w.H.hasNotify(w.player, "error", "씨앗 가방이 가득 찼어요"))
			-- 끄면 거부
			table.remove(w.data.eggs, 1)
			T.eq(w.Config.ALLOW_EGG_PICKUP, true)
			w.Config.ALLOW_EGG_PICKUP = false
			T.falsy(B.pickUpEgg(w.player, w.data.incubators[1].uid))
			w.Config.ALLOW_EGG_PICKUP = true
			T.truthy(B.pickUpEgg(w.player, w.data.incubators[1].uid))
			w.H.uninstall()
		end
	)
	------------------------------------------------------------------
	T.suite("서비스: BaseService 성장 → 성체 (6판: 부화 버튼 없음, 그 자리에서 성체)")

	local function seedPart(w, uid)
		for _, part in w.H.map.folders.Incubating.children do
			if part:GetAttribute("EggUid") == uid then
				return part
			end
		end
		return nil
	end
	local function plantPart(w, uid)
		for _, part in w.H.map.folders.Incubating.children do
			if part:GetAttribute("PlantUid") == uid then
				return part
			end
		end
		return nil
	end

	T.test(
		"다 자라면 그 자리·uid 그대로 성체 + 열매 1개, 도감 발견, PlantGrown·알림·신호, 씨앗 파트 → GardenPlant 파트",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local grown = {}
			B.grown:connect(function(_, plant)
				table.insert(grown, plant)
			end)
			local record = placeNew(w, "puppy_grass", "giant", { "golden" }) -- 표 3초 → 7판 성장 3배로 1초 (튜토리얼)
			T.eq(record.required, 1)
			T.truthy(seedPart(w, record.uid), "심은 씨앗 파트")
			w.H.clearSent()
			w.H.advance(3.1)
			T.eq(#w.data.incubators, 0)
			T.eq(#w.data.pets, 1)
			local plant = w.data.pets[1]
			T.eq(plant.uid, record.uid, "같은 uid")
			T.eq(plant.x, record.x, "같은 자리")
			T.eq(plant.z, record.z)
			T.eq(plant.size, "giant")
			T.eq(plant.mutations[1], "golden")
			T.eq(plant.fruits, w.Config.FRUITS_ON_ADULT)
			T.eq(plant.fruitProgress, 0)
			T.eq(w.data.stats.eggsHatched, 1)
			T.truthy(w.data.indexDiscovered.puppy_grass, "도감 발견")
			local result = w.H.sent(w.player, "PlantGrown")[1][1]
			T.eq(result.plant.uid, record.uid)
			T.truthy(result.isNew)
			T.eq(
				result.fruitValue,
				w.Pets.get("puppy_grass").fruitValue * 2 * 6 * 2,
				"초반 2배(일반) × 거대 6 × 황금 2"
			)
			T.eq(result.fruitInterval, w.Pets.get("puppy_grass").fruitIntervalSeconds / 1.8, "열매 1.8배 빨리")
			T.truthy(w.H.hasNotify(w.player, "success", "성체가 됐어요"))
			T.eq(#grown, 1)
			T.eq(seedPart(w, record.uid), nil, "씨앗 파트는 사라짐")
			local part = plantPart(w, record.uid)
			T.truthy(part, "GardenPlant 파트")
			T.eq(part:GetAttribute("Stage"), "adult")
			T.eq(part:GetAttribute("Fruits"), 1)
			T.eq(part:GetAttribute("FruitMax"), w.Config.FRUIT_MAX_PER_PLANT)
			T.eq(part:GetAttribute("OwnerUserId"), w.player.UserId)
			T.eq(w.H.remotes.HatchEgg, nil, "부화 Remote 는 없음")
			-- 한 번 더 지나도 또 성체가 되지 않음
			w.H.advance(3)
			T.eq(#w.H.sent(w.player, "PlantGrown"), 1)
			w.H.uninstall()
		end
	)

	T.test(
		"성장 단계: 씨앗 파트 Attribute Stage 가 새싹(0~25%) → 줄기(25~60%) → 봉오리(60~99%) → 성체",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local record = placeNew(w, "bell_mushroom") -- 표 60초 → 7판 20초
			local part = seedPart(w, record.uid)
			T.eq(part:GetAttribute("Stage"), "sprout")
			w.H.advance(6) -- 30%
			T.eq(part:GetAttribute("Stage"), "stem")
			w.H.advance(8) -- 70%
			T.eq(part:GetAttribute("Stage"), "bud")
			T.eq(part:GetAttribute("Ready"), false)
			w.H.advance(6.1)
			T.eq(#w.data.pets, 1, "100% = 성체")
			T.eq(w.H.shared("GardenRules").stage(5, 10), "stem")
			w.H.uninstall()
		end
	)

	T.test(
		"정원이 꽉 찬 채로 다 자라도 성체가 됨 (씨앗이 이미 칸을 차지), 남의 씨앗은 안 건드림",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local other, _, otherData = playerWith(w, 1002, "Other")
			local theirs = placeNew(w, "rune_rose", "normal", {}, other, otherData)
			for _ = 1, 7 do
				placeNew(w, "puppy_grass")
			end
			T.eq(#w.data.incubators, 7, "1레벨 정원 7칸")
			w.H.advance(3.1)
			T.eq(#w.data.incubators, 0)
			T.eq(#w.data.pets, 7)
			T.eq(#otherData.incubators, 1)
			T.eq(theirs.progress > 0, true)
			T.eq(#otherData.pets, 0)
			w.H.uninstall()
		end
	)

	T.test("낮에는 1초에 1초씩, 밤에는 30배, 다 자라면 성체 알림 한 번", function()
		local w = world()
		local B = w.BaseService
		B.start()
		local record = placeNew(w, "bell_mushroom") -- 표 60초 → 7판 20초
		T.eq(record.required, 20)
		w.H.advance(3)
		T.near(record.progress, 3, 1e-9)
		T.eq(countNotify(w, "성체가 됐어요"), 0, "아직 안 자라서 알림 없음")
		w.H.setPhase("Night")
		w.H.advance(2)
		T.eq(#w.data.pets, 1, "밤 2초 = 60초 성장 → 남은 17초를 넘어 성체")
		T.eq(countNotify(w, "성체가 됐어요"), 1)
		w.H.advance(5)
		T.eq(countNotify(w, "성체가 됐어요"), 1, "계속 알리지 않음")
		w.H.uninstall()
	end)

	T.test("성장 2배 게임패스 플래그 × 밤 = 60배", function()
		local w = world()
		local B = w.BaseService
		B.start()
		w.session.hasGrowthPass = true
		local record = placeNew(w, "moon_ghost_tree") -- 5일
		w.H.advance(10)
		T.near(record.progress, 20, 1e-9, "낮 2배")
		w.H.setPhase("Night")
		w.H.advance(10)
		T.near(record.progress, 20 + 600, 1e-9, "밤 60배")
		w.H.uninstall()
	end)

	T.test(
		"오프라인 동안 자란 만큼 (심은 씨앗만, 밤 가속 없음), 다 자란 것은 접속하자마자 성체 (알림 한 번에)",
		function()
			local w = world()
			local B = w.BaseService
			local record = placeNew(w, "moon_ghost_tree")
			B.grantEgg(w.player, "moon_ghost_tree", "normal", {}, "sakura")
			w.data.lastSaveTime = w.H.time() - 100
			B.onPlayerReady(w.player)
			T.near(record.progress, 100, 1e-9)
			T.eq(w.data.eggs[1].progress, 0, "가방 속 씨앗은 오프라인에도 안 자람")
			-- 짧은 씨앗 2개 + 한 달 비움 → 둘 다 성체, 알림은 "씨앗 2개" 한 번
			local w2 = world()
			placeNew(w2, "sprout_daisy")
			placeNew(w2, "puppy_grass")
			w2.data.lastSaveTime = w2.H.time() - 30 * 86400
			w2.H.clearSent()
			w2.BaseService.onPlayerReady(w2.player)
			T.eq(#w2.data.incubators, 0)
			T.eq(#w2.data.pets, 2)
			T.truthy(w2.H.hasNotify(w2.player, "success", "씨앗 2개가 성체가 됐어요"))
			T.eq(#w2.H.sent(w2.player, "PlantGrown"), 2)
			-- 첫 접속(lastSaveTime 0) 은 안 자람
			local w3 = world()
			local record3 = placeNew(w3, "moon_ghost_tree")
			w3.data.lastSaveTime = 0
			w3.BaseService.onPlayerReady(w3.player)
			T.eq(record3.progress, 0)
			w3.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: BaseService 건너뛰기 (SkipGrowth: 남은 1분당 10코인 × 등급 배수)")

	T.test(
		"전부(all): 부엉이 참나무(희귀 ×4, 표 4분 → 7판 실제 80초 = 2분으로 올림) = 80 코인 → 바로 성체 / 코인이 모자라면 거부",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local record = placeNew(w, "owl_oak") -- 표 240초 → 7판 80초
			T.eq(record.required, 80)
			local price = w.H.shared("GardenRules").skipCost("owl_oak", 0, 80, "all") -- 80 + 열매 값 × 10
			T.truthy(price > 80, "열매 값 부분이 더해짐")
			w.data.money = price - 1
			w.H.client(w.player, "SkipGrowth", record.uid, "all")
			T.eq(w.data.money, price - 1, "코인 안 빠짐")
			T.eq(record.progress, 0)
			T.truthy(w.H.hasNotify(w.player, "error", "코인이 부족해요"))
			T.truthy(w.H.hasNotify(w.player, "error", "코인 필요"))
			w.data.money = price
			w.H.client(w.player, "SkipGrowth", record.uid, "all")
			T.eq(w.data.money, 0, "딱 가격만큼 빠짐")
			T.eq(#w.data.incubators, 0)
			T.eq(#w.data.pets, 1, "바로 성체")
			T.eq(w.data.stats.skips, 1)
			T.eq(#w.H.sent(w.player, "PlantGrown"), 1)
			w.H.uninstall()
		end
	)

	T.test(
		"절반(half): 남은 시간의 절반만, 가격도 그만큼 (7판 부엉이 참나무 실제 80초 → 절반 40초 = 1분으로 올림 → 40 코인)",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local record = placeNew(w, "owl_oak")
			local priceHalf = w.H.shared("GardenRules").skipCost("owl_oak", 0, 80, "half") -- 40 + 열매 값 × 10 / 2
			w.data.money = 1e9
			w.H.client(w.player, "SkipGrowth", record.uid, "half")
			T.eq(w.data.money, 1e9 - priceHalf)
			T.near(record.progress, 40, 1e-9)
			T.eq(#w.data.pets, 0, "아직 성체 아님")
			T.truthy(w.H.hasNotify(w.player, "success", "절반"))
			-- 조금 자란 뒤 남은 시간의 절반 = 1분이 안 됨 → 1분으로 올림 → 40 코인
			w.H.advance(1)
			local before = w.data.money
			w.H.advance(1) -- 레이트 리밋 여유
			local expectHalf = w.H.shared("GardenRules").skipCost("owl_oak", record.progress, record.required, "half")
			w.H.client(w.player, "SkipGrowth", record.uid, "half")
			T.eq(before - w.data.money, expectHalf, "두 번째 절반도 공식대로")
			w.H.uninstall()
		end
	)

	T.test(
		"등급 배수: 비밀 룬 장미 1일어치 = 1440분 × 10 × 100 = 1,440,000 코인, 슈퍼 × 500, 해커 글리치 × 5000",
		function()
			local w = world()
			local GardenRules = w.H.shared("GardenRules")
			local Economy = w.H.shared("Economy")
			local Config = w.H.shared("Data/Config")
			local function fruitPart(id: string): number
				return Economy.fruitValue(id, "normal", {}) * Config.SKIP_FRUIT_FACTOR
			end
			T.eq(
				GardenRules.skipCost("rune_rose", 0, 86400, "all"),
				math.ceil(1440 * 10 * 100 + fruitPart("rune_rose"))
			)
			T.eq(
				GardenRules.skipCost("rainbow_thunder_tree", 0, 7 * 86400, "all"),
				math.ceil(7 * 1440 * 10 * 500 + fruitPart("rainbow_thunder_tree"))
			)
			T.eq(
				GardenRules.skipCost("static_world_tree", 0, 86400, "all"),
				math.ceil(1440 * 10 * 5000 + fruitPart("static_world_tree"))
			)
			T.eq(
				GardenRules.skipCost("rune_rose", 0, Economy.growSeconds("rune_rose"), "all"),
				math.ceil(480 * 10 * 100 + fruitPart("rune_rose")),
				"7판: 실제 Required(표 1일 ÷ 3 = 8시간) 기준 → 48만 코인"
			)
			T.eq(
				GardenRules.skipCost("sprout_daisy", 0, 10, "all"),
				math.ceil(10 + fruitPart("sprout_daisy")),
				"10초도 1분으로 올림 + 열매 값 × 10"
			)
			T.eq(GardenRules.skipCost("sprout_daisy", 10, 10, "all"), 0, "다 자랐으면 0")
			T.eq(GardenRules.skipCost("없는식물", 0, 10, "all"), nil)
			w.H.uninstall()
		end
	)

	T.test(
		"SkipGrowth 이상한 요청: 모드가 틀림 / 가방 속 씨앗 / 남의 씨앗 / 성체 uid / 이상한 인자는 아무 일 없음",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			w.data.money = 1e9
			local record = placeNew(w, "owl_oak")
			local other, _, otherData = playerWith(w, 1002, "Other")
			otherData.nextUid = 500 -- uid 는 사람마다 따로 매겨서 겹칠 수 있음 → 내 것과 다른 번호로
			local theirs = placeNew(w, "owl_oak", "normal", {}, other, otherData)
			B.grantEgg(w.player, "owl_oak", "normal", {}, "dev")
			local bagUid = w.data.eggs[#w.data.eggs].uid
			for _, args in
				{
					{ record.uid, "quarter" },
					{ record.uid },
					{ record.uid, 5 },
					{ bagUid, "all" },
					{ theirs.uid, "all" },
					{ 12, "all" },
					{ "", "all" },
				}
			do
				w.H.advance(1)
				w.H.client(w.player, "SkipGrowth", table.unpack(args))
			end
			T.eq(w.data.money, 1e9)
			T.eq(theirs.progress > 0 and theirs.progress < theirs.required, true)
			T.eq(#otherData.pets, 0)
			-- 성체가 된 식물 uid 로는 건너뛸 게 없음
			w.H.client(w.player, "SkipGrowth", record.uid, "all")
			local spent = 1e9 - w.data.money
			T.truthy(spent > 0)
			w.H.advance(1)
			w.H.client(w.player, "SkipGrowth", record.uid, "all")
			T.eq(1e9 - w.data.money, spent, "성체는 건너뛰기 없음")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: BaseService 베이스 배정")

	T.test(
		"베이스 7칸(MapLayout)을 순서대로 배정, 8번째는 0 → 누가 나가면 그 자리를 받고 집으로",
		function()
			local w = world()
			local B = w.BaseService
			w.session.plotIndex = 0
			T.eq(B.assignPlot(w.player), 1)
			T.eq(w.player.attrs.PlotIndex, 1)
			for i = 2, 7 do
				local p, s = playerWith(w, 1000 + i, "P" .. i)
				s.plotIndex = 0
				T.eq(B.assignPlot(p), i)
				T.eq(w.H.map.owners[i], p, "표지판 주인")
			end
			local late, lateSession = playerWith(w, 1099, "Late")
			lateSession.plotIndex = 0
			w.H.spawn(late, 0, 3, 500)
			T.eq(B.assignPlot(late), 0, "베이스 7개가 다 참")
			B.releasePlot(w.player)
			w.H.advance(0.1)
			T.eq(lateSession.plotIndex, 1, "빈 자리를 이어받음")
			T.truthy(w.H.hasNotify(late, "success", "내 베이스를 받았어요"))
			T.eq(late.Character.root.Position.X, w.H.MapLayout.plot(1).spawn.x, "집(앞마당)으로")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite(
		"서비스: SakuraService (6판 사쿠라 나무: 성체 바치기 → 크리스탈 → 특별 씨앗 뽑기)"
	)

	local function sakuraWorld()
		local w = world()
		w.SakuraService = w.H.server("Services/SakuraService")
		w.SakuraService.start()
		w.H.spawn(w.player, 0, 3, 0)
		w.H.landmarks.nearName = "SakuraIncubator"
		return w
	end

	-- 정원 빈자리에 성체 하나 (PetService.addPlant)
	local function addPlant(w, petId)
		local spots = {}
		for _, r in w.data.pets do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		local spot = w.EggPlacement.firstFreeGrid("normal", spots)
		local record = {
			uid = w.DataSchema.newUid(w.data, "p"),
			petId = petId,
			size = "normal",
			mutations = {},
			x = spot.x,
			z = spot.z,
			fruits = 0,
			fruitProgress = 0,
		}
		assert(w.PetService.addPlant(w.player, record))
		return record
	end

	T.test(
		"성체를 바치면 등급별 크리스탈 (멀면·성체가 아니면·이상한 인자면 거부), 정원 자리가 빔",
		function()
			local w = sakuraWorld()
			local daisy = addPlant(w, "sprout_daisy") -- 일반 1개
			local rose = addPlant(w, "rune_rose") -- 비밀 20개
			w.H.landmarks.nearName = nil
			w.H.client(w.player, "SakuraOffer", daisy.uid)
			T.eq(#w.data.pets, 2)
			T.truthy(w.H.hasNotify(w.player, "error", "사쿠라 나무 가까이"))
			w.H.landmarks.nearName = "SakuraIncubator"
			w.H.advance(3)
			w.H.client(w.player, "SakuraOffer", "p999") -- 없는 성체
			T.truthy(w.H.hasNotify(w.player, "error", "바칠 성체 식물"))
			w.H.advance(3)
			w.H.client(w.player, "SakuraOffer", 12345)
			w.H.client(w.player, "SakuraOffer")
			T.eq(#w.data.pets, 2)
			T.eq(w.data.sakuraCrystals, 0)
			w.H.advance(3)
			w.H.client(w.player, "SakuraOffer", rose.uid)
			T.eq(#w.data.pets, 1, "바친 성체만 사라짐")
			T.eq(w.data.pets[1].uid, daisy.uid)
			T.eq(w.data.sakuraCrystals, w.Config.SAKURA_OFFER_CRYSTALS.secret)
			T.eq(w.player.attrs.SakuraCrystals, 20)
			local result = w.H.sent(w.player, "SakuraResult")[1][1]
			T.eq(result.kind, "offered")
			T.eq(result.consumed, rose.uid)
			T.eq(result.gained, 20)
			T.eq(result.crystals, 20)
			T.eq(w.player.attrs.SakuraUnlocked, nil, "6판: 해금 없음")
			w.H.uninstall()
		end
	)

	T.test(
		"크리스탈 10개로 특별 씨앗 뽑기 → 씨앗 가방 (벚꽃 씨앗 / 정령 벚꽃 씨앗), 모자라면·가방이 차면 거부",
		function()
			local w = sakuraWorld()
			w.H.client(w.player, "SakuraDraw")
			T.truthy(w.H.hasNotify(w.player, "error", "크리스탈이 10개 필요"))
			T.eq(#w.data.eggs, 0)
			w.SakuraService.addCrystals(w.player, 25)
			w.H.clearSent()
			w.H.client(w.player, "SakuraDraw")
			T.eq(w.data.sakuraCrystals, 15)
			T.eq(#w.data.eggs, 1)
			local egg = w.data.eggs[1]
			T.truthy(egg.petId == "blossom_fairy" or egg.petId == "spirit_blossom", egg.petId)
			T.eq(egg.biomeId, "cherry_blossom")
			T.near(egg.required, w.Pets.get(egg.petId).growSeconds / 3, 1e-6, "7판 성장 3배")
			local granted = w.H.sent(w.player, "EggGranted")[1][1]
			T.eq(granted.source, "sakura")
			local result = w.H.sent(w.player, "SakuraResult")[1][1]
			T.eq(result.kind, "draw")
			T.eq(result.petId, egg.petId)
			T.eq(result.egg.uid, egg.uid)
			T.truthy(w.H.hasNotify(w.player, "success", "씨앗"))
			-- 멀면 거부
			w.H.landmarks.nearName = nil
			w.H.advance(3)
			w.H.client(w.player, "SakuraDraw")
			T.eq(w.data.sakuraCrystals, 15)
			-- 가방이 가득 차면 거부 (크리스탈 그대로)
			w.H.landmarks.nearName = "SakuraIncubator"
			fillBag(w, w.Config.EGG_INVENTORY_MAX - #w.data.eggs)
			w.H.advance(3)
			w.H.client(w.player, "SakuraDraw")
			T.eq(w.data.sakuraCrystals, 15, "가방이 차면 크리스탈 안 씀")
			T.truthy(w.H.hasNotify(w.player, "error", "씨앗 가방이 가득"))
			T.eq(w.H.remotes.SakuraApply, nil, "6판: 블룸 Remote 없음")
			w.H.uninstall()
		end
	)

	T.test("뽑기 확률: 1,000번에 정령 벚꽃 씨앗은 드묾 (2.5%)", function()
		local w = sakuraWorld()
		local spirit = 0
		for _ = 1, 1000 do
			w.data.sakuraCrystals = 10
			table.clear(w.data.eggs)
			if w.SakuraService.draw(w.player) == "spirit_blossom" then
				spirit += 1
			end
		end
		T.truthy(spirit < 70, "정령 벚꽃 " .. spirit .. "번")
		w.H.uninstall()
	end)

	T.test("벚꽃 구역 씨앗을 배달하면 크리스탈 +1 (다른 구역은 안 줌), 상한 999,999", function()
		local w = sakuraWorld()
		w.BaseService.delivered:fire(w.player, { biomeId = "forest", petId = "sprout_daisy" })
		T.eq(w.data.sakuraCrystals, 0)
		w.BaseService.delivered:fire(w.player, { biomeId = "cherry_blossom", petId = "koi_lotus" })
		T.eq(w.data.sakuraCrystals, 1)
		w.SakuraService.addCrystals(w.player, 5e9)
		T.eq(w.data.sakuraCrystals, 999999)
		w.SakuraService.addCrystals(w.player, 0)
		w.SakuraService.addCrystals(w.player, -5)
		T.eq(w.data.sakuraCrystals, 999999)
		w.H.uninstall()
	end)

	ServerHarness.install(Loader, T).uninstall()
end
