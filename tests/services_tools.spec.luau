--!nocheck
--[[
	서비스 테스트 4: ToolService (방망이·구역 무기·곰덫) — 사거리·방향·쿨다운·안전 구역·곰덫 5초
	진짜 ToolService + 진짜 규칙을 ServerHarness(가짜 Tool/Part/가방, 가상 시간) 위에서 돌립니다.
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function world()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Config = H.shared("Data/Config")
		w.Pets = H.shared("Data/Pets")
		w.Weapons = H.shared("Data/Weapons")
		w.Sessions = H.server("Sessions")
		w.ToolService = H.server("Services/ToolService")
		w.IndexService = H.server("Services/IndexService")
		w.ToolService.start()
		-- A = 공격하는 사람 (원점, -Z 쪽을 봄), B = 맞는 사람
		w.A = H.newPlayer(1001, "Alice")
		w.sa, w.da = H.login(w.A)
		w.sa.plotIndex = 1
		H.spawn(w.A, 0, 3, 0)
		H.giveBackpack(w.A)
		w.B = H.newPlayer(1002, "Bob")
		w.sb, w.db = H.login(w.B)
		w.sb.plotIndex = 2
		H.spawn(w.B, 0, 3, -5)
		H.giveBackpack(w.B)
		w.ToolService.onPlayerReady(w.A)
		w.ToolService.onPlayerReady(w.B)
		return w
	end

	local function names(container)
		local list = {}
		for _, child in container.children do
			table.insert(list, child.Name)
		end
		table.sort(list)
		return table.concat(list, ",")
	end

	local function use(w, kind, player)
		w.H.client(player or w.A, "UseTool", kind)
	end

	------------------------------------------------------------------
	T.suite("서비스: ToolService 도구 지급")

	T.test("처음에는 야구 방망이 + 곰덫(3개)만, 구역 무기는 도감을 완성해야 생김", function()
		local w = world()
		T.eq(names(w.A.backpack), "Bat,BearTrap")
		local trap = w.A.backpack:FindFirstChild("BearTrap")
		T.eq(trap:GetAttribute("Count"), w.Config.STARTING_BEAR_TRAPS)
		local bat = w.A.backpack:FindFirstChild("Bat")
		T.eq(bat:GetAttribute("WeaponId"), "baseball_bat")
		T.eq(bat:GetAttribute("Range"), w.Config.BAT_RANGE)
		T.eq(bat.RequiresHandle, false)
		-- 호수 도감 완성 → 물 방망이가 가방에 (바로)
		for _, pet in w.Pets.inBiome("lake") do
			w.IndexService.discover(w.A, pet.id)
		end
		T.eq(names(w.A.backpack), "Bat,BearTrap,WaterBat")
		-- 다시 갱신해도 중복 안 생김
		w.ToolService.refreshTools(w.A)
		T.eq(names(w.A.backpack), "Bat,BearTrap,WaterBat")
		w.H.uninstall()
	end)

	T.test(
		"모든 구역 무기 7개를 해금하면 Tool 이름이 Remotes.ToolKinds 와 같은 9개(방망이·곰덫 포함)",
		function()
			local w = world()
			for _, pet in w.Pets.list do
				w.IndexService.discover(w.A, pet.id)
			end
			local Remotes = w.H.shared("Remotes")
			local expected = {}
			for _, kind in Remotes.ToolKinds do
				table.insert(expected, kind)
			end
			table.sort(expected)
			T.eq(names(w.A.backpack), table.concat(expected, ","))
			w.H.uninstall()
		end
	)

	T.test("곰덫이 0개가 되면 곰덫 도구가 가방에서 사라짐", function()
		local w = world()
		w.da.tools.bearTrap = 0
		w.ToolService.refreshTools(w.A)
		T.eq(names(w.A.backpack), "Bat")
		w.da.tools.bearTrap = 2
		w.ToolService.refreshTools(w.A)
		T.eq(w.A.backpack:FindFirstChild("BearTrap"):GetAttribute("Count"), 2)
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("서비스: ToolService 근접 무기 (사거리·방향·쿨다운·안전 구역)")

	local function hits(w)
		return #w.H.eggs.knockouts
	end

	T.test(
		"손에 든 방망이로 앞 사거리(9) 안의 사람을 때림 — 안 들었으면 안 맞음",
		function()
			local w = world()
			use(w, "Bat") -- 가방에만 있음
			T.eq(hits(w), 0)
			w.H.equip(w.A, "Bat")
			w.H.advance(1)
			use(w, "Bat")
			T.eq(hits(w), 1)
			local k = w.H.eggs.knockouts[1]
			T.eq(k.player, w.B)
			T.eq(k.cause, "player")
			T.eq(k.by, "Alice")
			T.eq(k.power, 1, "방망이 넉백 배율")
			T.eq(k.from.Z, 0, "때린 사람 위치에서 날아감")
			w.H.uninstall()
		end
	)

	T.test(
		"사거리 경계: 9.0 은 맞고 9.1 은 안 맞음 / 뒤·옆은 안 맞고 방향 경계(내적 0.2)는 맞음",
		function()
			local w = world()
			w.H.equip(w.A, "Bat")
			w.H.teleport(w.B, 0, 3, -9)
			use(w, "Bat")
			T.eq(hits(w), 1, "정확히 9")
			w.H.advance(1.3)
			w.H.teleport(w.B, 0, 3, -9.1)
			use(w, "Bat")
			T.eq(hits(w), 1, "9.1 은 밖")
			w.H.advance(1.3)
			w.H.teleport(w.B, 0, 3, 5) -- 등 뒤
			use(w, "Bat")
			T.eq(hits(w), 1)
			w.H.advance(1.3)
			w.H.teleport(w.B, 5, 3, 0) -- 옆 (내적 0)
			use(w, "Bat")
			T.eq(hits(w), 1)
			w.H.advance(1.3)
			w.H.teleport(w.B, 4.8, 3, -1) -- 내적 1/4.9 = 0.204 (경계 바로 안쪽)
			use(w, "Bat")
			T.eq(hits(w), 2)
			w.H.uninstall()
		end
	)

	T.test("쿨다운 1.2초: 1.19초는 막고 1.21초는 통과, 무기를 바꿔도 같은 쿨다운", function()
		local w = world()
		for _, pet in w.Pets.inBiome("lake") do
			w.IndexService.discover(w.A, pet.id)
		end
		w.H.equip(w.A, "Bat")
		use(w, "Bat")
		T.eq(hits(w), 1)
		w.H.advance(1.19)
		use(w, "Bat")
		T.eq(hits(w), 1, "1.19초")
		w.H.advance(0.02)
		use(w, "Bat")
		T.eq(hits(w), 2, "1.21초")
		-- 물 방망이로 바꿔 들고 바로 치기 (쿨다운 공유)
		w.H.unequip(w.A, "Bat")
		w.H.equip(w.A, "WaterBat")
		w.H.advance(0.3)
		use(w, "WaterBat")
		T.eq(hits(w), 2, "무기를 바꿔도 쿨다운은 그대로")
		w.H.advance(1)
		use(w, "WaterBat")
		T.eq(hits(w), 3)
		T.near(w.H.eggs.knockouts[3].power, 1.15, 1e-9, "물 방망이 넉백")
		w.H.uninstall()
	end)

	T.test("구역 무기는 사거리가 더 김: 카타나 12 는 맞고 12.1 은 안 맞음", function()
		local w = world()
		for _, pet in w.Pets.inBiome("cherry_blossom") do
			w.IndexService.discover(w.A, pet.id)
		end
		w.H.equip(w.A, "Katana")
		w.H.teleport(w.B, 0, 3, -12)
		use(w, "Katana")
		T.eq(hits(w), 1)
		w.H.advance(2)
		w.H.teleport(w.B, 0, 3, -12.1)
		use(w, "Katana")
		T.eq(hits(w), 1)
		T.near(w.H.eggs.knockouts[1].power, 1.35, 1e-9)
		w.H.uninstall()
	end)

	T.test("안 가진 구역 무기를 요청해도 무시 (도구가 없음)", function()
		local w = world()
		use(w, "Scythe")
		w.H.equip(w.A, "Bat")
		use(w, "Scythe")
		T.eq(hits(w), 0)
		w.H.uninstall()
	end)

	T.test("가장 가까운 한 명만 맞음", function()
		local w = world()
		local C = w.H.newPlayer(1003, "Cara")
		w.H.login(C)
		w.H.spawn(C, 0, 3, -2)
		w.H.equip(w.A, "Bat")
		use(w, "Bat")
		T.eq(hits(w), 1)
		T.eq(w.H.eggs.knockouts[1].player, C)
		w.H.uninstall()
	end)

	T.test(
		"안전 구역: 내가 안에 있으면 못 쓰고(안내), 맞는 사람이 안에 있으면 안 맞음",
		function()
			local w = world()
			w.H.equip(w.A, "Bat")
			w.H.map.safeZone = true
			use(w, "Bat")
			T.eq(hits(w), 0)
			T.truthy(w.H.hasNotify(w.A, "error", "안전 구역에서는 도구를 쓸 수 없어요"))
			-- 맞는 사람만 안전 구역: isInSafeZone 이 위치별로 답하게
			w.H.map.safeZone = false
			local Map = w.H.server("Services/MapBuilder")
			local original = Map.isInSafeZone
			Map.isInSafeZone = function(position)
				return position.Z < -3
			end
			w.H.advance(2)
			use(w, "Bat")
			T.eq(hits(w), 0, "B 는 Z=-5 라 안전 구역")
			Map.isInSafeZone = original
			w.H.uninstall()
		end
	)

	T.test(
		"기절한 사람은 못 때리고 기절한 사람도 안 맞음, 죽은 사람도 안 맞음, 이상한 kind 는 무시",
		function()
			local w = world()
			w.H.equip(w.A, "Bat")
			w.sa.stunnedUntil = w.H.clock() + 3
			use(w, "Bat")
			T.eq(hits(w), 0, "내가 기절")
			w.H.advance(3.1)
			w.sb.stunnedUntil = w.H.clock() + 3
			use(w, "Bat")
			T.eq(hits(w), 0, "상대가 기절")
			w.H.advance(3.1)
			w.B.Character.humanoid.Health = 0
			use(w, "Bat")
			T.eq(hits(w), 0, "상대가 죽음")
			w.B.Character.humanoid.Health = 100
			w.H.advance(1.3)
			for _, bad in { "Hack", "bat", 5, true, {}, "" } do
				w.H.client(w.A, "UseTool", bad)
			end
			w.H.client(w.A, "UseTool")
			T.eq(hits(w), 0)
			w.H.advance(5) -- 레이트 리밋(burst 4) 회복
			use(w, "Bat")
			T.eq(hits(w), 1, "정상 요청은 통과")
			w.H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: ToolService 곰덫 (설치·5초 묶임·수명)")

	local function trapWorld()
		local w = world()
		w.da.tools.bearTrap = 10
		w.ToolService.refreshTools(w.A)
		w.H.equip(w.A, "BearTrap")
		w.H.teleport(w.B, 30, 3, 30) -- 멀리
		return w
	end

	T.test("설치하면 개수 -1 + 도구 개수 표시 갱신, 1초 쿨다운, 동시에 3개까지", function()
		local w = trapWorld()
		use(w, "BearTrap")
		T.eq(w.da.tools.bearTrap, 9)
		T.eq(w.A.Character:FindFirstChild("BearTrap"):GetAttribute("Count"), 9, "도구에 남은 개수 표시")
		w.H.advance(0.5)
		use(w, "BearTrap")
		T.eq(w.da.tools.bearTrap, 9, "1초 쿨다운 안")
		w.H.advance(0.6)
		use(w, "BearTrap")
		w.H.advance(1.1)
		use(w, "BearTrap")
		T.eq(w.da.tools.bearTrap, 7, "3개 설치")
		w.H.advance(1.1)
		use(w, "BearTrap")
		T.eq(w.da.tools.bearTrap, 7, "4번째는 거부")
		T.truthy(w.H.hasNotify(w.A, "error", "동시에 3개까지"))
		w.H.uninstall()
	end)

	T.test(
		"다른 사람이 반경 3 안에 들어오면 5초 묶임 + 알 떨어뜨림 + Caught(trap) 알림, 경계 3.01 은 안 걸림",
		function()
			local w = trapWorld()
			use(w, "BearTrap")
			T.eq(w.da.tools.bearTrap, 9)
			w.H.teleport(w.B, 3.01, 3, 0)
			w.H.advance(1)
			T.eq(#w.H.sent(w.B, "Caught"), 0, "3.01 은 밖")
			w.H.carry(w.B, { petId = "chicken", biomeId = "forest" })
			w.H.teleport(w.B, 3, 3, 0)
			w.H.advance(0.3)
			local caught = w.H.sent(w.B, "Caught")
			T.eq(#caught, 1)
			T.eq(caught[1][1].cause, "trap")
			T.eq(caught[1][1].by, "Alice")
			T.eq(caught[1][1].stunSeconds, 5)
			T.eq(caught[1][1].eggOutcome, "DropHere")
			T.falsy(w.H.eggs.carried[w.B], "알을 떨어뜨림")
			T.eq(w.B.attrs.Stunned, true)
			T.eq(w.B.Character.humanoid.WalkSpeed, 0, "못 움직임")
			T.eq(w.B.Character.humanoid.JumpHeight, 0)
			-- 4.9초 뒤에도 묶임, 5.2초 뒤에는 풀림
			w.H.advance(4.5)
			T.eq(w.B.Character.humanoid.WalkSpeed, 0)
			w.H.advance(0.8)
			T.truthy(w.B.Character.humanoid.WalkSpeed > 0, "풀림")
			T.eq(w.B.attrs.Stunned, false)
			-- 덫은 한 번 쓰면 사라짐 (다시 걸리지 않음)
			w.H.clearSent()
			w.H.teleport(w.B, 0, 3, 1)
			w.H.advance(1)
			T.eq(#w.H.sent(w.B, "Caught"), 0)
			w.H.uninstall()
		end
	)

	T.test(
		"자기 덫은 자기가 안 밟힘, 안전 구역의 사람은 안 걸림, 90초 지나면 저절로 사라짐",
		function()
			local w = trapWorld()
			use(w, "BearTrap")
			w.H.advance(2) -- A 는 덫 위에 서 있음
			T.eq(#w.H.sent(w.A, "Caught"), 0)
			w.H.map.safeZone = true
			w.H.teleport(w.B, 0, 3, 1)
			w.H.advance(1)
			T.eq(#w.H.sent(w.B, "Caught"), 0, "안전 구역")
			w.H.map.safeZone = false
			w.H.teleport(w.B, 30, 3, 30)
			w.H.advance(91)
			w.H.teleport(w.B, 0, 3, 1)
			w.H.advance(1)
			T.eq(#w.H.sent(w.B, "Caught"), 0, "수명 90초가 지나 사라짐")
			w.H.uninstall()
		end
	)

	T.test(
		"안전 구역에서는 설치 불가(안내), 설치한 사람이 나가면 그 덫도 사라짐",
		function()
			local w = trapWorld()
			w.H.map.safeZone = true
			use(w, "BearTrap")
			T.eq(w.da.tools.bearTrap, 10)
			T.truthy(w.H.hasNotify(w.A, "error", "안전 구역에서는 도구를 쓸 수 없어요"))
			w.H.map.safeZone = false
			w.H.advance(1.1)
			use(w, "BearTrap")
			T.eq(w.da.tools.bearTrap, 9)
			w.ToolService.onPlayerLeaving(w.A)
			w.H.teleport(w.B, 0, 3, 1)
			w.H.advance(1)
			T.eq(#w.H.sent(w.B, "Caught"), 0)
			w.H.uninstall()
		end
	)

	T.test(
		"곰덫을 얻을 방법: 시작 지급 3개 말고는 도감·퀘스트 어디서도 늘어나지 않음 — [설계 구멍] 다 쓰면 끝",
		function()
			-- 이 테스트는 "개발 명령(/trap) 말고 곰덫 개수를 늘리는 서버 코드가 있나"를 글자로 확인합니다.
			local fs = require("@lune/fs")
			local gains = 0
			for _, dir in { "src/server/Services", "src/server/Logic", "src/server/Util" } do
				for _, name in fs.readDir(dir) do
					if name ~= "DevCommands.luau" and string.sub(name, -5) == ".luau" then
						local text = fs.readFile(dir .. "/" .. name)
						for _ in string.gmatch(text, "bearTrap%s*=%s*[^\n]-%+") do
							gains += 1
						end
						for _ in string.gmatch(text, "bearTrap%s*%+=") do
							gains += 1
						end
					end
				end
			end
			T.truthy(gains >= 1, "곰덫을 늘리는 코드가 없음 (설계문서 10장: 곰덫 = 도감 보상)")
		end
	)

	------------------------------------------------------------------
	T.suite("서비스: ToolService 2단계 보충 (SwingTick · 곰덫 도감 보상)")

	T.test(
		"휘두르기가 실제로 처리되면 손에 든 Tool 에 SwingTick, 쿨다운 중에는 안 바뀜",
		function()
			local w = world()
			local bat = w.A.backpack:FindFirstChild("Bat")
			w.H.equip(w.A, "Bat")
			w.H.advance(1)
			T.eq(bat:GetAttribute("SwingTick"), nil)
			use(w, "Bat")
			local first = bat:GetAttribute("SwingTick")
			T.truthy(type(first) == "number", "휘두름 표시")
			w.H.advance(0.5)
			use(w, "Bat") -- 쿨다운 중
			T.eq(bat:GetAttribute("SwingTick"), first)
			w.H.advance(1.3)
			use(w, "Bat")
			T.truthy(bat:GetAttribute("SwingTick") > first)
			w.H.uninstall()
		end
	)

	T.test(
		"곰덫 도감 보상: 희귀 이상 첫 발견 +1, 구역 완성 +5, 일반·고급은 0, 가방 Count 갱신",
		function()
			local w = world()
			local start = w.da.tools.bearTrap
			w.IndexService.discover(w.A, "chicken") -- 일반
			w.IndexService.discover(w.A, "bird") -- 고급
			T.eq(w.da.tools.bearTrap, start)
			w.IndexService.discover(w.A, "raccoon") -- 희귀
			T.eq(w.da.tools.bearTrap, start + 1)
			w.IndexService.discover(w.A, "raccoon") -- 두 번째는 아무것도 없음
			T.eq(w.da.tools.bearTrap, start + 1)
			-- 숲 나머지: 개(일반), 굴 올빼미(희귀), 곰·여우(에픽), 파타핌(전설) → +4, 마지막에 구역 완성 +5
			for _, id in { "dog", "burrowing_owl", "bear", "fox", "brr_brr_patapim" } do
				w.IndexService.discover(w.A, id)
			end
			T.eq(w.da.tools.bearTrap, start + 1 + 4 + 5)
			w.H.advance(0.1)
			T.eq(w.A.backpack:FindFirstChild("BearTrap"):GetAttribute("Count"), w.da.tools.bearTrap)
			T.truthy(w.H.hasNotify(w.A, "success", "곰덫 +"))
			-- 최대치에서 멈춤
			w.da.tools.bearTrap = w.Config.BEAR_TRAP_MAX_OWNED
			w.IndexService.discover(w.A, "turtle")
			T.eq(w.da.tools.bearTrap, w.Config.BEAR_TRAP_MAX_OWNED)
			w.H.uninstall()
		end
	)

	ServerHarness.install(Loader, T).uninstall()
end
