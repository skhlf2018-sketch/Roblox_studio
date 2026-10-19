--!nocheck
--[[
	서비스 테스트 2: BaseService(배달 → 알 가방·우리에 알 놓기·부화·성장), FusionService, AltarService, QuestService, SakuraService
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

	local function addPet(w, petId, size, mutations, player, data)
		local record = {
			uid = w.DataSchema.newUid(data or w.data, "p"),
			petId = petId,
			size = size or "normal",
			mutations = mutations or {},
		}
		w.PetService.addPet(player or w.player, record)
		return record
	end

	-- 가방을 n 개 채움 (선물 알)
	local function fillBag(w, n, player)
		for _ = 1, n do
			w.BaseService.grantEgg(player or w.player, "chicken", "normal", {}, "altar")
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
		w.BaseService.grantEgg(player, petId, size or "normal", mutations or {}, "altar")
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
		T.eq(B.grantEgg(w.player, "ring_guard", "big", { "golden" }, "altar"), "bag")
		T.eq(#w.data.eggs, 1)
		T.eq(#w.data.incubators, 0, "우리에 저절로 놓이지 않음")
		local first = w.data.eggs[1]
		T.eq(first.petId, "ring_guard")
		T.eq(first.size, "big")
		T.eq(first.mutations[1], "golden")
		T.eq(first.required, w.Economy.hatchSeconds("ring_guard"), "필요 시간 = 원작 그대로")
		T.eq(first.progress, 0)
		T.eq(first.uid, "i1")
		local granted = w.H.sent(w.player, "EggGranted")[1][1]
		T.eq(granted.egg.uid, "i1")
		T.eq(granted.queued, false)
		T.eq(granted.source, "altar")
		local update = w.H.sent(w.player, "DataUpdate")
		T.eq(update[#update][1], "eggs")
		T.eq(#update[#update][2].eggs, 1)
		fillBag(w, w.Config.EGG_INVENTORY_MAX - 1)
		T.eq(#w.data.eggs, 50)
		T.eq(B.grantEgg(w.player, "jitterbug", "normal", {}, "quest"), nil, "51번째는 자리 없음")
		T.falsy(B.canReceiveEgg(w.player))
		T.eq(#w.data.eggs, 50)
		T.eq(B.grantEgg(w.player, "없는펫", "normal", {}, "altar"), nil)
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
			w.H.carry(w.player, { petId = "chicken", biomeId = "forest", size = "huge", mutations = { "silver" } })
			B.deliver(w.player)
			T.eq(#w.data.eggs, 1)
			T.eq(#w.data.incubators, 0)
			local egg = w.data.eggs[1]
			T.eq(egg.petId, "chicken")
			T.eq(egg.size, "huge")
			T.eq(egg.mutations[1], "silver")
			T.eq(egg.biomeId, "forest")
			T.eq(egg.uid, "i1")
			T.eq(egg.progress, 0)
			T.eq(egg.required, w.Economy.hatchSeconds("chicken"))
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
			w.H.carry(w.player, { petId = "dog", biomeId = "forest", special = true })
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
			w.H.carry(w.player, { petId = "dog", biomeId = "forest" })
			B.deliver(w.player)
			B.deliver(w.player)
			T.eq(w.H.eggs.taken, 0, "알을 안 가져감")
			T.truthy(w.H.eggs.carried[w.player], "알은 계속 들고 있음")
			T.eq(#w.data.eggs, 50)
			T.eq(countNotify(w, "알 가방이 가득 찼어요"), 1, "3초 안에는 한 번만")
			w.H.advance(3.1)
			B.deliver(w.player)
			T.eq(countNotify(w, "알 가방이 가득 찼어요"), 2)
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
				petId = "chicken",
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
				petId = "chicken",
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
			w.H.carry(w.player, { petId = "chicken", biomeId = "forest" })
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
			w.H.carry(late, { petId = "dog", biomeId = "forest" })
			w.H.advance(0.4)
			T.eq(#lateData.eggs, 0)
			w.H.teleport(late, -30, 3, -5)
			w.H.advance(0.4)
			T.eq(#lateData.eggs, 1, "베이스 없어도 가방으로")
			T.eq(lateData.eggs[1].petId, "dog")
			w.H.uninstall()
		end
	)

	T.test("공중(바닥에서 20 이상)에서는 배달 안 됨", function()
		local w = world()
		local B = w.BaseService
		B.start()
		local hx, hz = w.H.hubSpot()
		w.H.spawn(w.player, hx, 30, hz)
		w.H.carry(w.player, { petId = "chicken", biomeId = "forest" })
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
			w.H.carry(w.player, { petId = "chicken", biomeId = "forest" })
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
			w.H.carry(w.player, { petId = "chicken", biomeId = "forest" })
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
			w.H.carry(w.player, { petId = "dog", biomeId = "forest" })
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
			B.grantEgg(w.player, "chicken", "big", { "silver" }, "altar")
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
			B.grantEgg(w.player, "dog", "normal", {}, "altar")
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
		"PlaceEgg 거부: 우리 밖(앞마당·울타리 2 안·남의 우리) / 다른 알과 너무 가까움(큰 알은 더 멀리) / 8개 초과 / 멀리서 / 베이스 없음",
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
			T.truthy(w.H.hasNotify(w.player, "error", "우리(울타리) 안에만"))
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
			B.grantEgg(w.player, "bear", "giant", {}, "altar")
			B.grantEgg(w.player, "bear", "giant", {}, "altar")
			local g1, g2 = w.data.eggs[#w.data.eggs - 1].uid, w.data.eggs[#w.data.eggs].uid
			T.truthy(try(-20, 0, g1))
			T.falsy(try(-20, 4.5, g2), "초거대끼리 4.5 는 겹침")
			T.truthy(try(-20, 4.8, g2), "초거대끼리 4.8 은 됨")
			T.eq(#w.data.incubators, 5)
			-- 8개까지
			T.truthy(try(-30, -20))
			T.truthy(try(-30, -10))
			T.truthy(try(-30, 0))
			T.eq(#w.data.incubators, w.Config.PLACED_EGG_MAX)
			T.falsy(try(-30, 10), "9번째")
			T.truthy(w.H.hasNotify(w.player, "error", "8개까지"))
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
			w.BaseService.grantEgg(other, "chicken", "normal", {}, "altar")
			local theirs = otherData.eggs[1].uid
			w.BaseService.grantEgg(w.player, "chicken", "normal", {}, "altar")
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
			local record = placeNew(w, "ghost_king")
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
			T.truthy(w.H.hasNotify(w.player, "error", "알 가방이 가득 찼어요"))
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
	T.suite("서비스: BaseService 부화")

	T.test(
		"다 자라기 전에는 부화 거부, 다 자라면 펫이 보관함·우리에 들어가고 도감 발견",
		function()
			local w = world()
			local B = w.BaseService
			local record = placeNew(w, "brr_brr_patapim", "giant")
			B.hatch(w.player, record.uid)
			T.eq(#w.data.incubators, 1, "아직 안 자람")
			T.eq(#w.data.pets, 0)
			T.truthy(w.H.hasNotify(w.player, "error", "아직 다 자라지 않았어요"))

			record.progress = record.required
			w.H.clearSent()
			B.hatch(w.player, record.uid)
			T.eq(#w.data.incubators, 0)
			T.eq(#w.data.pets, 1)
			local pet = w.data.pets[1]
			T.eq(pet.petId, "brr_brr_patapim")
			T.eq(pet.size, "giant")
			T.eq(pet.uid, "p2", "uid 카운터는 알(i1) 다음")
			T.eq(w.data.equipped[1], pet.uid)
			T.eq(w.data.stats.eggsHatched, 1)
			T.truthy(w.data.indexDiscovered.brr_brr_patapim)
			local result = w.H.sent(w.player, "HatchResult")[1][1]
			T.truthy(result.isNew)
			T.truthy(result.equipped)
			T.falsy(result.sold)
			T.eq(result.income, 1800 * 3 * 6)
			T.eq(#w.H.map.folders.Incubating.children, 0, "우리에서 알 파트가 사라짐")
			-- 같은 알을 또 부화하려 해도 없음
			B.hatch(w.player, record.uid)
			T.eq(#w.data.pets, 1)
			w.H.uninstall()
		end
	)

	T.test(
		"남의 알 uid / 가방 속 알 / 이상한 uid 로 부화 요청해도 아무 일 없음 (Remote)",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local other, _, otherData = playerWith(w, 1002, "Other")
			local theirs = placeNew(w, "jitterbug", "normal", {}, other, otherData)
			theirs.progress = theirs.required
			w.H.client(w.player, "HatchEgg", theirs.uid) -- 내 데이터에는 없는 uid
			T.eq(#otherData.incubators, 1)
			T.eq(#otherData.pets, 0)
			for _, bad in { 5, "", "../x", string.rep("z", 49), {} } do
				w.H.client(w.player, "HatchEgg", bad)
			end
			T.eq(#w.data.pets, 0)
			-- 가방 속 알은 다 자랐어도 부화 안 됨 (우리에 놓아야 함)
			w.H.advance(3)
			B.grantEgg(w.player, "jitterbug", "normal", {}, "quest")
			w.data.eggs[1].progress = w.data.eggs[1].required
			w.H.client(w.player, "HatchEgg", w.data.eggs[1].uid)
			T.eq(#w.data.pets, 0)
			T.eq(#w.data.eggs, 1)
			-- 주인이 부화하면 정상
			w.H.client(other, "HatchEgg", theirs.uid)
			T.eq(#otherData.pets, 1)
			w.H.uninstall()
		end
	)

	T.test("보관함이 가득 찬 상태에서 제일 싼 펫이 부화되면 sold=true, 돈으로 바뀜", function()
		local w = world()
		local B = w.BaseService
		for _ = 1, 500 do
			addPet(w, "bear")
		end
		T.eq(#w.data.pets, 500)
		local record = placeNew(w, "chicken")
		record.progress = record.required
		w.H.clearSent()
		B.hatch(w.player, record.uid)
		T.eq(#w.data.pets, 500)
		local result = w.H.sent(w.player, "HatchResult")[1][1]
		T.truthy(result.sold)
		T.falsy(result.equipped)
		T.eq(w.data.money, 3 * 60)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: BaseService 알 자라기 (우리에 놓인 알만, 밤 30배, 오프라인)")

	T.test("낮에는 1초에 1초씩, 밤에는 30배, 다 자라면 한 번만 알림", function()
		local w = world()
		local B = w.BaseService
		B.start()
		local record = placeNew(w, "jitterbug") -- 20초 (2판 수정: 원작 그대로)
		T.eq(record.required, 20)
		w.H.advance(3)
		T.near(record.progress, 3, 1e-9)
		T.eq(countNotify(w, "다 자랐어요"), 0, "아직 안 자라서 알림 없음")
		w.H.setPhase("Night")
		w.H.advance(1)
		T.eq(record.progress, record.required, "밤 1초 = 30초 → 다 자람")
		T.eq(countNotify(w, "다 자랐어요"), 1)
		w.H.advance(5)
		T.eq(countNotify(w, "다 자랐어요"), 1, "다 자란 뒤 계속 알리지 않음")
		w.H.uninstall()
	end)

	T.test("성장 2배 게임패스 플래그 × 밤 = 60배", function()
		local w = world()
		local B = w.BaseService
		B.start()
		w.session.hasGrowthPass = true
		local record = placeNew(w, "ghost_king") -- 86400초
		w.H.advance(10)
		T.near(record.progress, 20, 1e-9, "낮 2배")
		w.H.setPhase("Night")
		w.H.advance(10)
		T.near(record.progress, 20 + 600, 1e-9, "밤 60배")
		w.H.uninstall()
	end)

	T.test(
		"오프라인 동안 자란 만큼 (놓인 알만, 밤 가속 없음), 아주 오래 비워도 필요량에서 멈춤",
		function()
			local w = world()
			local B = w.BaseService
			local record = placeNew(w, "ghost_king")
			B.grantEgg(w.player, "ghost_king", "normal", {}, "altar")
			w.data.lastSaveTime = w.H.time() - 100
			B.onPlayerReady(w.player)
			T.near(record.progress, 100, 1e-9)
			T.eq(w.data.eggs[1].progress, 0, "가방 속 알은 오프라인에도 안 자람")
			w.data.lastSaveTime = w.H.time() - 30 * 86400
			B.onPlayerReady(w.player)
			T.eq(record.progress, record.required, "한 달 비웠으면 다 자람 (넘치지는 않음)")
			-- 첫 접속(lastSaveTime 0) 은 안 자람
			local w2 = world()
			local record2 = placeNew(w2, "ghost_king")
			w2.data.lastSaveTime = 0
			w2.BaseService.onPlayerReady(w2.player)
			T.eq(record2.progress, 0)
			w2.H.uninstall()
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
	T.suite("서비스: FusionService (퓨전 머신)")

	local function fuseWorld()
		local w = world()
		w.FusionService = w.H.server("Services/FusionService")
		w.FusionService.start()
		local x, z = w.H.plotSpot(1) -- 내 베이스 앞마당 (퓨전 머신 파트가 없으면 "내 베이스 안" 이면 됨)
		w.H.spawn(w.player, x, 3, z)
		return w
	end

	T.test(
		"닭 3마리 → 새: 재료는 사라지고 결과는 보관함·우리에, 결과 알림·도감",
		function()
			local w = fuseWorld()
			local a, b, c = addPet(w, "chicken"), addPet(w, "chicken"), addPet(w, "chicken")
			local fused = {}
			w.FusionService.fused:connect(function(_, pet)
				table.insert(fused, pet)
			end)
			w.H.client(w.player, "FuseRequest", a.uid, b.uid, c.uid)
			T.eq(#w.data.pets, 1)
			local pet = w.data.pets[1]
			T.eq(pet.petId, "bird")
			T.eq(w.data.equipped[1], pet.uid, "빈 칸이라 자동 장착")
			T.eq(#w.data.equipped, 1, "재료의 장착은 풀림")
			T.truthy(w.data.indexDiscovered.bird)
			T.eq(w.data.stats.fusions, 1)
			T.eq(#fused, 1)
			local result = w.H.sent(w.player, "FusionResult")[1][1]
			T.eq(#result.consumed, 3)
			T.truthy(result.upgraded)
			T.truthy(result.isNew)
			T.truthy(result.income >= result.inputIncome)
			T.truthy(w.H.hasNotify(w.player, "success", "합성 성공"))
			w.H.uninstall()
		end
	)

	T.test("거부: 종류가 다름 / 같은 펫 두 번 / 없는 펫 / 남의 펫 — 재료는 그대로", function()
		local w = fuseWorld()
		local a, b = addPet(w, "chicken"), addPet(w, "chicken")
		local d = addPet(w, "dog")
		w.H.client(w.player, "FuseRequest", a.uid, b.uid, d.uid)
		T.truthy(w.H.hasNotify(w.player, "error", "똑같은 종류"))
		w.H.advance(4) -- 레이트 리밋(burst 3) 회복
		w.H.client(w.player, "FuseRequest", a.uid, a.uid, b.uid)
		T.truthy(w.H.hasNotify(w.player, "error", "두 번 넣을 수 없어요"))
		w.H.advance(4)
		w.H.client(w.player, "FuseRequest", a.uid, b.uid, "p999")
		T.truthy(w.H.hasNotify(w.player, "error", "가지고 있지 않은 펫"))
		T.eq(#w.data.pets, 3)
		-- 남의 펫 (uid 가 내 것과 안 겹치게 번호를 크게)
		local other, _, otherData = playerWith(w, 1002, "Other")
		otherData.nextUid = 100
		w.H.spawn(other, 0, 3, 0)
		local x = addPet(w, "chicken", "normal", {}, other, otherData)
		local y = addPet(w, "chicken", "normal", {}, other, otherData)
		local z = addPet(w, "chicken", "normal", {}, other, otherData)
		w.H.advance(4)
		w.H.clearSent()
		w.H.client(w.player, "FuseRequest", x.uid, y.uid, z.uid)
		T.eq(#otherData.pets, 3, "남의 펫은 못 씀")
		T.eq(#w.data.pets, 3)
		T.truthy(w.H.hasNotify(w.player, "error", "가지고 있지 않은 펫"), "요청이 실제로 처리됐는지")
		-- 이상한 인자
		w.H.advance(4)
		w.H.client(w.player, "FuseRequest", 1, 2, 3)
		w.H.client(w.player, "FuseRequest", a.uid)
		T.eq(#w.data.pets, 3)
		w.H.uninstall()
	end)

	T.test("거부: 퓨전 머신(내 베이스)에서 멀면 / 캐릭터가 없으면", function()
		local w = fuseWorld()
		local a, b, c = addPet(w, "chicken"), addPet(w, "chicken"), addPet(w, "chicken")
		w.H.teleport(w.player, 0, 3, 0) -- 베이스 밖 (복도)
		w.H.client(w.player, "FuseRequest", a.uid, b.uid, c.uid)
		T.eq(#w.data.pets, 3)
		T.truthy(w.H.hasNotify(w.player, "error", "퓨전 머신 가까이"))
		w.H.advance(4)
		w.player.Character = nil
		w.H.client(w.player, "FuseRequest", a.uid, b.uid, c.uid)
		T.eq(#w.data.pets, 3)
		w.H.advance(4)
		local px, pz = w.H.plotSpot(1)
		w.H.spawn(w.player, px, 3, pz)
		w.session.plotIndex = 0 -- 베이스 없는 사람
		w.H.client(w.player, "FuseRequest", a.uid, b.uid, c.uid)
		T.eq(#w.data.pets, 3)
		w.H.advance(4)
		w.session.plotIndex = 1 -- 되돌리면 정상 (위 거부가 진짜 그 이유 때문이었는지 확인)
		w.H.client(w.player, "FuseRequest", a.uid, b.uid, c.uid)
		T.eq(#w.data.pets, 1)
		w.H.uninstall()
	end)

	T.test("거부: 더 강해질 수 없는 펫 (거대 파타핌 3마리) — 재료 그대로", function()
		local w = fuseWorld()
		local a = addPet(w, "brr_brr_patapim", "huge")
		local b = addPet(w, "brr_brr_patapim", "huge")
		local c = addPet(w, "brr_brr_patapim", "huge")
		w.H.client(w.player, "FuseRequest", a.uid, b.uid, c.uid)
		T.eq(#w.data.pets, 3)
		T.truthy(w.H.hasNotify(w.player, "error", "더 강해질 수 없어서"))
		w.H.uninstall()
	end)

	T.test("퓨전은 레이트 리밋 (burst 3)", function()
		local w = fuseWorld()
		local a = addPet(w, "chicken")
		for _ = 1, 10 do
			w.H.client(w.player, "FuseRequest", a.uid, "p500", "p501")
		end
		T.eq(#w.H.notifications(w.player), 3, "3번까지만 처리")
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: AltarService (제단 짝 맞추기·비밀 통로 합성)")

	local function altarWorld()
		local w = world()
		w.AltarService = w.H.server("Services/AltarService")
		w.AltarService.start()
		w.A, w.sa, w.da = w.player, w.session, w.data
		w.B, w.sb, w.db = playerWith(w, 1002, "Bee")
		w.H.spawn(w.A, 0, 3, 0)
		w.H.spawn(w.B, 0, 3, 0)
		return w
	end

	local function offer(w, player, uid, altarName)
		w.H.landmarks.nearName = altarName
		w.H.client(player, "AltarOffer", uid)
		w.H.advance(1.1) -- 레이트 리밋 회복
	end

	T.test(
		"서로 다른 두 사람이 같은 주기에 양쪽 제단에 바치면 둘 다 링 가드/링로드 알",
		function()
			local w = altarWorld()
			local dove = addPet(w, "light_dove", "normal", {}, w.A, w.da)
			local sprite = addPet(w, "flame_sprite", "normal", {}, w.B, w.db)
			offer(w, w.A, dove.uid, "AltarLight")
			T.eq(#w.da.pets, 1, "짝을 기다리는 동안 펫은 그대로")
			T.eq(w.H.landmarks.parts.AltarLight:GetAttribute("PendingCount"), 1)
			T.eq(w.H.sent(w.A, "AltarUpdate")[1][1].status, "pending")
			offer(w, w.B, sprite.uid, "AltarDark")
			T.eq(#w.da.pets, 0)
			T.eq(#w.db.pets, 0)
			T.eq(#w.da.eggs, 1)
			T.eq(#w.db.eggs, 1)
			T.truthy(w.da.eggs[1].petId == "ring_guard" or w.da.eggs[1].petId == "ringlord")
			T.truthy(w.db.eggs[1].petId == "ring_guard" or w.db.eggs[1].petId == "ringlord")
			T.eq(w.H.landmarks.parts.AltarLight:GetAttribute("PendingCount"), 0)
			local paired = w.H.sent(w.A, "AltarUpdate")
			T.eq(paired[#paired][1].status, "paired")
			T.eq(paired[#paired][1].partner, "Bee")
			w.H.uninstall()
		end
	)

	T.test("같은 사람이 양쪽 제단에 두 번 바치는 건 불가 (한 주기에 한 번)", function()
		local w = altarWorld()
		local dove = addPet(w, "light_dove", "normal", {}, w.A, w.da)
		local imp = addPet(w, "imp", "normal", {}, w.A, w.da)
		offer(w, w.A, dove.uid, "AltarLight")
		offer(w, w.A, imp.uid, "AltarDark")
		T.eq(#w.da.pets, 2, "아무것도 안 사라짐")
		T.truthy(w.H.hasNotify(w.A, "error", "이미 제물을 바쳤어요"))
		T.eq(#w.da.eggs, 0)
		w.H.uninstall()
	end)

	T.test("틀린 쪽 펫 / 제단에서 멀리 / 일반 펫은 거부", function()
		local w = altarWorld()
		local sprite = addPet(w, "flame_sprite", "normal", {}, w.A, w.da)
		local chicken = addPet(w, "chicken", "normal", {}, w.A, w.da)
		offer(w, w.A, sprite.uid, "AltarLight")
		T.truthy(w.H.hasNotify(w.A, "error", "천국 제단에는 천국 쪽 펫만"))
		offer(w, w.A, chicken.uid, "AltarLight")
		offer(w, w.A, sprite.uid, nil) -- 제단에서 멀리
		T.truthy(w.H.hasNotify(w.A, "error", "제단 가까이에서"))
		T.eq(w.H.landmarks.parts.AltarLight:GetAttribute("PendingCount"), 0)
		T.eq(#w.da.pets, 2)
		w.H.uninstall()
	end)

	T.test(
		"주기가 바뀌면 기다리던 제물 취소 (펫은 남고 알림), 나간 사람 제물도 취소",
		function()
			local w = altarWorld()
			local dove = addPet(w, "light_dove", "normal", {}, w.A, w.da)
			offer(w, w.A, dove.uid, "AltarLight")
			w.H.setPhase("Day", 2)
			local updates = w.H.sent(w.A, "AltarUpdate")
			T.eq(updates[#updates][1].status, "expired")
			T.eq(#w.da.pets, 1)
			T.eq(w.H.landmarks.parts.AltarLight:GetAttribute("PendingCount"), 0)
			-- 새 주기에서 다시 바칠 수 있음
			offer(w, w.A, dove.uid, "AltarLight")
			T.eq(w.H.landmarks.parts.AltarLight:GetAttribute("PendingCount"), 1)
			w.AltarService.onPlayerLeaving(w.A)
			T.eq(w.H.landmarks.parts.AltarLight:GetAttribute("PendingCount"), 0)
			w.H.uninstall()
		end
	)

	T.test(
		"기다리는 사이 제물 펫이 없어졌으면 그 제물은 건너뛰고 새 사람은 계속 기다림",
		function()
			local w = altarWorld()
			local dove = addPet(w, "light_dove", "normal", {}, w.A, w.da)
			local sprite = addPet(w, "flame_sprite", "normal", {}, w.B, w.db)
			offer(w, w.A, dove.uid, "AltarLight")
			w.PetService.removePets(w.A, { dove.uid }) -- 몰래 팔았다고 치자
			offer(w, w.B, sprite.uid, "AltarDark")
			T.eq(#w.db.pets, 1, "짝이 없으니 B 의 펫은 그대로")
			T.eq(#w.db.eggs, 0)
			w.H.uninstall()
		end
	)

	T.test("알 받을 자리(알 가방 50)가 없으면 제물을 못 바침", function()
		local w = altarWorld()
		w.player = w.A
		local dove = addPet(w, "light_dove", "normal", {}, w.A, w.da)
		fillBag(w, w.Config.EGG_INVENTORY_MAX, w.A)
		offer(w, w.A, dove.uid, "AltarLight")
		T.truthy(w.H.hasNotify(w.A, "error", "알을 받을 자리가 없어요"))
		T.eq(w.H.landmarks.parts.AltarLight:GetAttribute("PendingCount"), 0)
		w.H.uninstall()
	end)

	T.test("비밀 통로 합성: 페가수스 + 스켈레톤 말 → 에퀴녹스 알, 계정당 한 번", function()
		local w = altarWorld()
		local p1 = addPet(w, "pegasus", "big", {}, w.A, w.da)
		local p2 = addPet(w, "skeleton_horse", "huge", {}, w.A, w.da)
		w.H.landmarks.nearName = nil
		w.H.client(w.A, "ShrineFuse", p1.uid, p2.uid)
		T.eq(#w.da.pets, 2, "비밀 통로에서 멀면 거부")
		w.H.advance(3)
		w.H.landmarks.nearName = "SecretShrine"
		w.H.client(w.A, "ShrineFuse", p1.uid, p2.uid)
		T.eq(#w.da.pets, 0)
		T.eq(#w.da.eggs, 1)
		T.eq(w.da.eggs[1].petId, "equinox")
		T.eq(w.da.eggs[1].size, "big", "두 펫 중 작은 크기")
		T.truthy(w.da.shrineUsed.equinox)
		-- 두 번째 시도
		local q1 = addPet(w, "pegasus", "normal", {}, w.A, w.da)
		local q2 = addPet(w, "skeleton_horse", "normal", {}, w.A, w.da)
		w.H.advance(5)
		w.H.client(w.A, "ShrineFuse", q1.uid, q2.uid)
		T.eq(#w.da.pets, 2, "계정당 한 번")
		T.truthy(w.H.hasNotify(w.A, "error", "계정당 한 번만"))
		-- 틀린 조합
		local chicken = addPet(w, "chicken", "normal", {}, w.A, w.da)
		w.H.advance(5)
		w.H.client(w.A, "ShrineFuse", q1.uid, chicken.uid)
		T.truthy(w.H.hasNotify(w.A, "error", "합성할 수 없어요"))
		w.H.advance(5)
		w.H.client(w.A, "ShrineFuse", q1.uid, q1.uid)
		T.eq(#w.da.pets, 3)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: QuestService (마법의 숲 퀘스트 3개)")

	local function questWorld()
		local w = world()
		w.FusionService = w.H.server("Services/FusionService")
		w.QuestService = w.H.server("Services/QuestService")
		w.FusionService.start()
		w.QuestService.start()
		local x, z = w.H.plotSpot(1) -- 퓨전은 내 베이스에서
		w.H.spawn(w.player, x, 3, z)
		return w
	end

	local function deliverEvent(w, biomeId, petId)
		w.BaseService.delivered:fire(w.player, { biomeId = biomeId, petId = petId })
	end

	T.test("마법의 숲 알만 20개 센다 (다른 구역 알은 안 셈), 19개까지는 완료 아님", function()
		local w = questWorld()
		for _ = 1, 30 do
			deliverEvent(w, "forest", "chicken")
		end
		T.eq(w.data.quests.deliver_eggs, nil, "다른 구역은 안 셈")
		for _ = 1, 19 do
			deliverEvent(w, "enchanted_forest", "prism_gecko")
		end
		T.eq(w.data.quests.deliver_eggs, 19)
		T.falsy(w.data.questsRewarded)
		deliverEvent(w, "enchanted_forest", "prism_gecko")
		T.eq(w.data.quests.deliver_eggs, 20)
		for _ = 1, 5 do
			deliverEvent(w, "enchanted_forest", "prism_gecko")
		end
		T.eq(w.data.quests.deliver_eggs, 20, "목표에서 멈춤")
		w.H.uninstall()
	end)

	T.test("영원 알은 아무 구역이나 1개, 일반 알은 안 셈", function()
		local w = questWorld()
		deliverEvent(w, "snow", "yeti") -- 비밀
		T.eq(w.data.quests.deliver_eternal, nil)
		deliverEvent(w, "snow", "ice_dragon") -- 영원
		T.eq(w.data.quests.deliver_eternal, 1)
		w.H.uninstall()
	end)

	T.test(
		"진짜 퓨전 1번이 퀘스트 '합성'을 올림, 3개 다 끝나면 문 열림 + 지터버그 알",
		function()
			local w = questWorld()
			for _ = 1, 20 do
				deliverEvent(w, "enchanted_forest", "prism_gecko")
			end
			deliverEvent(w, "cosmic", "unicorn")
			deliverEvent(w, "snow", "ice_dragon")
			T.eq(w.data.quests.deliver_eternal, 1)
			T.falsy(w.data.questsRewarded, "퓨전이 아직")
			local a, b, c = addPet(w, "chicken"), addPet(w, "chicken"), addPet(w, "chicken")
			w.H.client(w.player, "FuseRequest", a.uid, b.uid, c.uid)
			T.eq(w.data.quests.fuse_once, 1)
			T.truthy(w.data.questsRewarded)
			T.truthy(w.player.attrs.QuestsDone)
			local gotEgg = false
			for _, record in w.data.eggs do
				if record.petId == "jitterbug" then
					gotEgg = true
				end
			end
			T.truthy(gotEgg, "지터버그 알 지급")
			local updates = w.H.sent(w.player, "QuestUpdate")
			local last = updates[#updates][1]
			T.truthy(last.allDone and last.gateOpen)
			-- 끝난 뒤에는 더 안 올라감
			deliverEvent(w, "enchanted_forest", "prism_gecko")
			T.eq(w.data.quests.deliver_eggs, 20)
			w.H.uninstall()
		end
	)

	T.test(
		"영혼 세계 수호자 알: 퀘스트 끝낸 사람이 없으면 절대 안 나옴, 있으면 초기화마다 약 1%",
		function()
			local w = questWorld()
			local EggService = w.H.server("Services/EggService")
			for _ = 1, 2000 do
				EggService.resetDone:fire(1)
			end
			T.eq(#w.H.eggs.specials, 0)
			w.data.questsRewarded = true
			for _ = 1, 3000 do
				EggService.resetDone:fire(1)
			end
			local n = #w.H.eggs.specials
			T.truthy(n >= 10 and n <= 60, "3000번 중 약 30번 (실제 " .. n .. ")")
			T.eq(w.H.eggs.specials[1].petId, "spirit_world_guardian")
			T.eq(w.H.eggs.specials[1].biomeId, "enchanted_forest")
			T.truthy(w.H.eggs.specials[1].options.questOnly)
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: SakuraService (사쿠라 인큐베이터·크리스탈)")

	local function sakuraWorld()
		local w = world()
		w.SakuraService = w.H.server("Services/SakuraService")
		w.SakuraService.start()
		w.H.spawn(w.player, 0, 3, 0)
		w.H.landmarks.nearName = "SakuraIncubator"
		return w
	end

	T.test("학을 바치면 인큐베이터 해금 (학 없으면/멀면/이미 열었으면 거부)", function()
		local w = sakuraWorld()
		w.H.client(w.player, "SakuraOffer")
		T.truthy(w.H.hasNotify(w.player, "error", "학 펫이 있어야"))
		addPet(w, "crane")
		local chicken = addPet(w, "chicken")
		w.H.landmarks.nearName = nil
		w.H.advance(3)
		w.H.client(w.player, "SakuraOffer")
		T.falsy(w.data.sakuraUnlocked)
		T.truthy(w.H.hasNotify(w.player, "error", "사쿠라 인큐베이터 가까이"))
		w.H.landmarks.nearName = "SakuraIncubator"
		w.H.advance(3)
		w.H.client(w.player, "SakuraOffer", chicken.uid) -- 학이 아닌 펫
		T.falsy(w.data.sakuraUnlocked)
		w.H.advance(3)
		w.H.client(w.player, "SakuraOffer", 12345) -- 이상한 인자는 무시
		T.falsy(w.data.sakuraUnlocked)
		w.H.advance(3)
		w.H.client(w.player, "SakuraOffer")
		T.truthy(w.data.sakuraUnlocked)
		T.eq(#w.data.pets, 1, "학만 사라짐")
		T.eq(w.data.pets[1].petId, "chicken")
		T.truthy(w.player.attrs.SakuraUnlocked)
		T.eq(w.H.sent(w.player, "SakuraResult")[1][1].kind, "unlocked")
		w.H.uninstall()
	end)

	T.test(
		"크리스탈 1개로 블룸: 펫·가방 속 알·우리에 놓인 알에 붙고, 이미 블룸이 있으면 거부(크리스탈 안 씀)",
		function()
			local w = sakuraWorld()
			w.data.sakuraUnlocked = true
			local pet = addPet(w, "chicken")
			w.H.client(w.player, "SakuraApply", pet.uid)
			T.truthy(w.H.hasNotify(w.player, "error", "크리스탈이"), "크리스탈 없음")
			T.eq(#pet.mutations, 0)
			w.SakuraService.addCrystals(w.player, 3)
			T.eq(w.player.attrs.SakuraCrystals, 3)
			w.H.advance(3)
			w.H.client(w.player, "SakuraApply", pet.uid)
			T.eq(w.data.sakuraCrystals, 2)
			T.eq(#pet.mutations, 1)
			T.truthy(pet.mutations[1] == "bloom" or pet.mutations[1] == "spirit_bloom")
			w.H.advance(3)
			w.H.client(w.player, "SakuraApply", pet.uid) -- 이미 블룸
			T.eq(w.data.sakuraCrystals, 2, "거부되면 크리스탈 안 씀")
			T.truthy(w.H.hasNotify(w.player, "error", "이미 블룸"))
			-- 가방 속 알 (2판 수정)
			w.BaseService.grantEgg(w.player, "dog", "normal", { "golden" }, "altar")
			local egg = w.data.eggs[1]
			w.H.advance(3)
			w.H.clearSent()
			w.H.client(w.player, "SakuraApply", egg.uid)
			T.eq(w.data.sakuraCrystals, 1)
			T.eq(#egg.mutations, 2, "골든 위에 블룸 중첩")
			T.eq(w.H.sent(w.player, "SakuraResult")[1][1].target, "egg")
			local sentEggs = false
			for _, args in w.H.sent(w.player, "DataUpdate") do
				sentEggs = sentEggs or args[1] == "eggs"
			end
			T.truthy(sentEggs, "가방 다시 보냄")
			-- 우리에 놓인 알 (내 베이스에서 놓고 인큐베이터로 돌아옴)
			local x, z = w.H.plotSpot(1)
			w.H.teleport(w.player, x, 3, z)
			local placed = placeNew(w, "bear", "normal", {})
			w.H.teleport(w.player, 0, 3, 0)
			w.SakuraService.addCrystals(w.player, 1)
			w.H.advance(3)
			w.H.client(w.player, "SakuraApply", placed.uid)
			T.eq(w.data.sakuraCrystals, 1)
			T.eq(#placed.mutations, 1)
			local part = w.H.map.folders.Incubating.children[1]
			T.eq(part:GetAttribute("Mutations"), placed.mutations[1], "놓인 알 겉모습도 바뀜")
			-- 해금 안 했으면 거부
			w.data.sakuraUnlocked = false
			w.H.advance(3)
			w.H.client(w.player, "SakuraApply", pet.uid)
			T.eq(w.data.sakuraCrystals, 1)
			w.H.uninstall()
		end
	)

	T.test("벚꽃 구역 알을 배달하면 크리스탈 +1 (다른 구역은 안 줌), 상한 999,999", function()
		local w = sakuraWorld()
		w.BaseService.delivered:fire(w.player, { biomeId = "forest", petId = "chicken" })
		T.eq(w.data.sakuraCrystals, 0)
		w.BaseService.delivered:fire(w.player, { biomeId = "cherry_blossom", petId = "crane" })
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
