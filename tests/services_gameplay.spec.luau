--!nocheck
--[[
	서비스 테스트 2: BaseService(배달·부화 슬롯·부화·성장), FusionService, AltarService, QuestService, SakuraService
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

	local function fillSlots(w, n)
		for _ = 1, n do
			w.BaseService.grantEgg(w.player, "chicken", "normal", {}, "altar")
		end
	end

	------------------------------------------------------------------
	T.suite("서비스: BaseService 선물 알 (빈 슬롯 → 대기 줄 → 거부)")

	T.test("빈 슬롯에 바로, 8칸이 차면 대기 줄(최대 20), 그 이상은 거부", function()
		local w = world()
		local B = w.BaseService
		for i = 1, w.Config.INCUBATOR_SLOTS do
			T.eq(B.grantEgg(w.player, "ring_guard", "big", { "golden" }, "altar"), "slot", "슬롯 " .. i)
		end
		T.eq(#w.data.incubators, 8)
		local first = w.data.incubators[1]
		T.eq(first.petId, "ring_guard")
		T.eq(first.size, "big")
		T.eq(first.mutations[1], "golden")
		T.eq(first.required, w.Economy.hatchSeconds("ring_guard"), "필요 시간 = 원본 ÷ 3")
		T.eq(first.progress, 0)
		for i = 1, w.Config.EGG_QUEUE_MAX do
			T.eq(B.grantEgg(w.player, "jitterbug", "normal", {}, "quest"), "queued", "대기 " .. i)
		end
		T.eq(#w.data.eggQueue, 20)
		T.eq(B.grantEgg(w.player, "jitterbug", "normal", {}, "quest"), nil, "21번째는 자리 없음")
		T.falsy(B.canReceiveEgg(w.player))
		T.eq(B.grantEgg(w.player, "없는펫", "normal", {}, "altar"), nil)
		-- 슬롯 번호는 겹치지 않음
		local used = {}
		for _, record in w.data.incubators do
			T.falsy(used[record.slot], "슬롯 중복")
			used[record.slot] = true
		end
		T.truthy(w.H.hasNotify(w.player, "info", "선물 알이 기다리고 있어요"))
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: BaseService 배달 (알 → 부화 슬롯)")

	T.test("알을 들고 배달하면 슬롯 1번에 등록, 통계·알림·신호", function()
		local w = world()
		local B = w.BaseService
		local signals = {}
		B.delivered:connect(function(_, record)
			table.insert(signals, record)
		end)
		w.H.carry(w.player, { petId = "chicken", biomeId = "forest", size = "huge", mutations = { "silver" } })
		B.deliver(w.player)
		T.eq(#w.data.incubators, 1)
		local record = w.data.incubators[1]
		T.eq(record.petId, "chicken")
		T.eq(record.size, "huge")
		T.eq(record.mutations[1], "silver")
		T.eq(record.slot, 1)
		T.eq(record.biomeId, "forest")
		T.eq(record.uid, "i1")
		T.eq(w.data.stats.eggsDelivered, 1)
		T.eq(w.H.eggs.taken, 1)
		T.eq(#w.H.sent(w.player, "EggDelivered"), 1)
		T.eq(#signals, 1, "퀘스트·사쿠라가 받는 신호")
		-- 같은 알로 두 번 배달 불가 (이미 가져감)
		B.deliver(w.player)
		T.eq(#w.data.incubators, 1)
		w.H.uninstall()
	end)

	T.test(
		"부화 슬롯 8칸이 다 차면 배달 거부 (알은 그대로 손에), 안내는 3초에 한 번",
		function()
			local w = world()
			local B = w.BaseService
			fillSlots(w, 8)
			w.H.carry(w.player, { petId = "dog", biomeId = "forest" })
			B.deliver(w.player)
			B.deliver(w.player)
			T.eq(w.H.eggs.taken, 0, "알을 안 가져감")
			T.truthy(w.H.eggs.carried[w.player], "알은 계속 들고 있음")
			T.eq(#w.data.incubators, 8)
			local errors = 0
			for _, n in w.H.notifications(w.player) do
				if n.kind == "error" and string.find(n.text, "부화 슬롯이 가득 찼어요", 1, true) then
					errors += 1
				end
			end
			T.eq(errors, 1, "3초 안에는 한 번만")
			w.H.advance(3.1)
			B.deliver(w.player)
			errors = 0
			for _, n in w.H.notifications(w.player) do
				if n.kind == "error" and string.find(n.text, "부화 슬롯이 가득 찼어요", 1, true) then
					errors += 1
				end
			end
			T.eq(errors, 2)
			w.H.uninstall()
		end
	)

	T.test(
		"순간이동 의심: 주운 곳에서 너무 빨리 패드에 오면 배달 거부 + 알은 둥지로 + 경고",
		function()
			local w = world()
			local B = w.BaseService
			w.session.walkSpeed = 16
			-- 1000스터드 떨어진 곳에서 방금 주웠는데 벌써 배달 → 최소 47초 걸려야 함
			w.H.carry(w.player, {
				petId = "chicken",
				biomeId = "forest",
				pickedPosition = w.H.vec(0, 0, 1020),
				originAt = w.H.clock(),
			})
			B.deliver(w.player)
			T.eq(#w.data.incubators, 0)
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
			T.eq(#w.data.incubators, 1)
			w.H.uninstall()
		end
	)

	T.test("배달 패드 반경 9: 걸어 들어오면 자동 배달 (경계 포함), 밖이면 안 됨", function()
		local w = world()
		local B = w.BaseService
		B.start()
		-- 패드 중심 (0, 0.5, 20). 반경 9.01 밖
		w.H.spawn(w.player, 0, 3, 20 + 9.01)
		w.H.carry(w.player, { petId = "chicken", biomeId = "forest" })
		w.H.advance(1)
		T.eq(#w.data.incubators, 0, "반경 밖")
		w.H.teleport(w.player, 0, 3, 20 + 9) -- 정확히 9 → 안
		w.H.advance(0.5)
		T.eq(#w.data.incubators, 1)
		w.H.uninstall()
	end)

	T.test("공중(높이 10 이상 차이)에서는 배달 안 됨", function()
		local w = world()
		local B = w.BaseService
		B.start()
		w.H.spawn(w.player, 0, 30, 20)
		w.H.carry(w.player, { petId = "chicken", biomeId = "forest" })
		w.H.advance(1)
		T.eq(#w.data.incubators, 0)
		w.H.uninstall()
	end)

	T.test(
		"알 든 채 한 번에 너무 멀리 움직이면(순간이동) 그 자리에 알 떨어뜨림 + 경고",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			w.H.spawn(w.player, 0, 3, 100)
			w.H.carry(w.player, { petId = "chicken", biomeId = "forest" })
			w.H.advance(0.2) -- 위치 기록
			w.H.teleport(w.player, 0, 3, 20) -- 80스터드 순간이동 (0.2초 허용은 약 13)
			w.H.advance(0.2)
			T.eq(#w.data.incubators, 0, "배달 안 됨")
			T.eq(#w.H.eggs.droppedAt, 1, "마지막 정상 위치에 떨어짐")
			T.eq(w.H.eggs.droppedAt[1].Z, 100)
			T.eq(w.player.attrs.MoveWarnings, 1)
			w.H.uninstall()
		end
	)

	T.test("밤이 되면 알 든 사람이 베이스 밖에 있을 때만 집으로 텔레포트", function()
		local w = world()
		local B = w.BaseService
		B.start()
		w.H.spawn(w.player, 500, 3, 500)
		w.H.carry(w.player, { petId = "chicken", biomeId = "forest" })
		w.H.map.inPlot = false
		w.H.setPhase("Night")
		T.eq(w.player.Character.root.Position.X, 0, "베이스 바닥 위로 이동")
		T.eq(w.player.Character.root.Position.Y, 4)
		-- 베이스 안에 있으면 그대로
		w.H.teleport(w.player, 7, 3, 7)
		w.H.map.inPlot = true
		w.H.setPhase("Night")
		T.eq(w.player.Character.root.Position.X, 7)
		w.H.uninstall()
	end)

	T.test(
		"밤이 되면 알이 없어도 구역 안에 있던 사람은 집으로 (밤 벽에 안 갇힘), 길에 있으면 그대로",
		function()
			local w = world()
			local B = w.BaseService
			B.start()
			local forest = w.H.map.zones.forest
			w.H.spawn(w.player, forest.centerX + 10, 3, forest.centerZ)
			w.H.map.inPlot = false
			w.H.setPhase("Night")
			T.eq(w.player.Character.root.Position.X, 0, "구역 안 → 베이스 바닥 위")
			T.eq(w.player.Character.root.Position.Y, 4)
			T.truthy(w.session.moveExemptUntil > w.H.clock(), "서버 순간이동 → 위치 검증 쉼")
			w.H.teleport(w.player, 0, 3, 60) -- 길 (구역 밖)
			w.H.setPhase("Day")
			w.H.setPhase("Night")
			T.eq(w.player.Character.root.Position.Z, 60, "구역 밖이면 그대로")
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
			w.H.carry(w.player, { petId = "brr_brr_patapim", biomeId = "forest", size = "giant" })
			B.deliver(w.player)
			local record = w.data.incubators[1]
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
			-- 같은 알을 또 부화하려 해도 없음
			B.hatch(w.player, record.uid)
			T.eq(#w.data.pets, 1)
			w.H.uninstall()
		end
	)

	T.test("남의 알 uid / 이상한 uid 로 부화 요청해도 아무 일 없음 (Remote)", function()
		local w = world()
		local B = w.BaseService
		B.start()
		local other, _, otherData = playerWith(w, 1002, "Other")
		w.BaseService.grantEgg(other, "jitterbug", "normal", {}, "quest")
		local theirs = otherData.incubators[1]
		theirs.progress = theirs.required
		w.H.client(w.player, "HatchEgg", theirs.uid) -- 내 데이터에는 없는 uid
		T.eq(#otherData.incubators, 1)
		T.eq(#otherData.pets, 0)
		for _, bad in { 5, "", "../x", string.rep("z", 49), {} } do
			w.H.client(w.player, "HatchEgg", bad)
		end
		T.eq(#w.data.pets, 0)
		-- 주인이 부화하면 정상
		w.H.client(other, "HatchEgg", theirs.uid)
		T.eq(#otherData.pets, 1)
		w.H.uninstall()
	end)

	T.test("부화하면 대기 줄 알이 빈 슬롯으로 자동 이동", function()
		local w = world()
		local B = w.BaseService
		fillSlots(w, 8)
		B.grantEgg(w.player, "jitterbug", "normal", {}, "quest")
		T.eq(#w.data.eggQueue, 1)
		local record = w.data.incubators[3]
		record.progress = record.required
		B.hatch(w.player, record.uid)
		T.eq(#w.data.eggQueue, 0)
		T.eq(#w.data.incubators, 8, "다시 8칸")
		local queuedEgg
		for _, r in w.data.incubators do
			if r.petId == "jitterbug" then
				queuedEgg = r
			end
		end
		T.truthy(queuedEgg)
		T.eq(queuedEgg.slot, 3, "비워진 3번 칸으로")
		w.H.uninstall()
	end)

	T.test("보관함이 가득 찬 상태에서 제일 싼 펫이 부화되면 sold=true, 돈으로 바뀜", function()
		local w = world()
		local B = w.BaseService
		for _ = 1, 500 do
			addPet(w, "bear")
		end
		T.eq(#w.data.pets, 500)
		B.grantEgg(w.player, "chicken", "normal", {}, "altar")
		local record = w.data.incubators[1]
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
	T.suite("서비스: BaseService 알 자라기 (밤 30배, 오프라인)")

	T.test("낮에는 1초에 1초씩, 밤에는 30배, 다 자라면 한 번만 알림", function()
		local w = world()
		local B = w.BaseService
		B.start()
		B.grantEgg(w.player, "jitterbug", "normal", {}, "quest") -- 20초 ÷ 3 = 6.67초
		local record = w.data.incubators[1]
		T.near(record.required, 20 / 3, 1e-9)
		w.H.advance(3)
		T.near(record.progress, 3, 1e-9)
		T.eq(#w.H.notifications(w.player), 0, "아직 안 자라서 알림 없음")
		w.H.setPhase("Night")
		w.H.advance(1)
		T.eq(record.progress, record.required, "밤 1초 = 30초 → 다 자람")
		local ready = 0
		for _, n in w.H.notifications(w.player) do
			if string.find(n.text, "다 자랐어요", 1, true) then
				ready += 1
			end
		end
		T.eq(ready, 1)
		w.H.advance(5)
		ready = 0
		for _, n in w.H.notifications(w.player) do
			if string.find(n.text, "다 자랐어요", 1, true) then
				ready += 1
			end
		end
		T.eq(ready, 1, "다 자란 뒤 계속 알리지 않음")
		w.H.uninstall()
	end)

	T.test("성장 2배 게임패스 플래그 × 밤 = 60배", function()
		local w = world()
		local B = w.BaseService
		B.start()
		w.session.hasGrowthPass = true
		B.grantEgg(w.player, "ghost_king", "normal", {}, "altar") -- 86400 ÷ 3 = 28800초
		local record = w.data.incubators[1]
		w.H.advance(10)
		T.near(record.progress, 20, 1e-9, "낮 2배")
		w.H.setPhase("Night")
		w.H.advance(10)
		T.near(record.progress, 20 + 600, 1e-9, "밤 60배")
		w.H.uninstall()
	end)

	T.test(
		"오프라인 동안 자란 만큼 (밤 가속 없음), 아주 오래 비워도 필요량에서 멈춤",
		function()
			local w = world()
			local B = w.BaseService
			B.grantEgg(w.player, "ghost_king", "normal", {}, "altar")
			local record = w.data.incubators[1]
			w.data.lastSaveTime = w.H.time() - 100
			B.onPlayerReady(w.player)
			T.near(record.progress, 100, 1e-9)
			w.data.lastSaveTime = w.H.time() - 30 * 86400
			B.onPlayerReady(w.player)
			T.eq(record.progress, record.required, "한 달 비웠으면 다 자람 (넘치지는 않음)")
			-- 첫 접속(lastSaveTime 0) 은 안 자람
			local w2 = world()
			w2.BaseService.grantEgg(w2.player, "ghost_king", "normal", {}, "altar")
			w2.data.lastSaveTime = 0
			w2.BaseService.onPlayerReady(w2.player)
			T.eq(w2.data.incubators[1].progress, 0)
			w2.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: BaseService 베이스 배정")

	T.test("베이스가 없는 사람은 누가 나가면 그 자리를 받음", function()
		local w = world()
		local B = w.BaseService
		w.session.plotIndex = 0
		T.eq(B.assignPlot(w.player), 1)
		T.eq(w.player.attrs.PlotIndex, 1)
		local late, lateSession = playerWith(w, 1002, "Late")
		lateSession.plotIndex = 0
		T.eq(B.assignPlot(late), 0, "맵에 베이스가 1개뿐이라 자리 없음")
		B.releasePlot(w.player)
		T.eq(lateSession.plotIndex, 1, "빈 자리를 이어받음")
		T.truthy(w.H.hasNotify(late, "success", "내 베이스를 받았어요"))
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: FusionService (퓨전 머신)")

	local function fuseWorld()
		local w = world()
		w.FusionService = w.H.server("Services/FusionService")
		w.FusionService.start()
		w.H.spawn(w.player, 0, 3, 0)
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
		w.H.map.inPlot = false
		w.H.client(w.player, "FuseRequest", a.uid, b.uid, c.uid)
		T.eq(#w.data.pets, 3)
		T.truthy(w.H.hasNotify(w.player, "error", "퓨전 머신 가까이"))
		w.H.advance(4)
		w.H.map.inPlot = true
		w.player.Character = nil
		w.H.client(w.player, "FuseRequest", a.uid, b.uid, c.uid)
		T.eq(#w.data.pets, 3)
		w.H.advance(4)
		w.H.spawn(w.player, 0, 3, 0)
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
			T.eq(#w.da.incubators, 1)
			T.eq(#w.db.incubators, 1)
			T.truthy(w.da.incubators[1].petId == "ring_guard" or w.da.incubators[1].petId == "ringlord")
			T.truthy(w.db.incubators[1].petId == "ring_guard" or w.db.incubators[1].petId == "ringlord")
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
		T.eq(#w.da.incubators, 0)
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
			T.eq(#w.db.incubators, 0)
			w.H.uninstall()
		end
	)

	T.test("알 받을 자리가 없으면 제물을 못 바침", function()
		local w = altarWorld()
		w.player = w.A
		local dove = addPet(w, "light_dove", "normal", {}, w.A, w.da)
		for _ = 1, 8 + 20 do
			w.BaseService.grantEgg(w.A, "chicken", "normal", {}, "altar")
		end
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
		T.eq(#w.da.incubators, 1)
		T.eq(w.da.incubators[1].petId, "equinox")
		T.eq(w.da.incubators[1].size, "big", "두 펫 중 작은 크기")
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
		w.H.spawn(w.player, 0, 3, 0)
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
			for _, record in w.data.incubators do
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
		"크리스탈 1개로 블룸: 펫/부화 중 알에 붙고, 이미 블룸이 있으면 거부(크리스탈 안 씀)",
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
			-- 부화 중 알
			w.BaseService.grantEgg(w.player, "dog", "normal", { "golden" }, "altar")
			local egg = w.data.incubators[1]
			w.H.advance(3)
			w.H.client(w.player, "SakuraApply", egg.uid)
			T.eq(w.data.sakuraCrystals, 1)
			T.eq(#egg.mutations, 2, "골든 위에 블룸 중첩")
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
