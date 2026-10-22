--!nocheck
--[[
	5판 주임 검수 — 구멍 찾기 3: 경비 고정 속도(4판) · 알 타이머 표시(4판) · 핫바 칸 계산(5판) · 개 알 · Remote 막 던지기
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	-- 디렉터리 목록을 미리 다 읽어 둠 (Loader 가 파일을 읽는 일이 require 메타메서드 안에서 일어나면 안 되므로)
	local function warm(node)
		local getChildren = node.GetChildren
		for _, child in getChildren(node) do
			warm(child)
		end
	end
	warm(Loader.get("ServerScriptService"))
	warm(Loader.get("ReplicatedStorage"))

	local SpeedMath = Loader.require("ReplicatedStorage/Shared/SpeedMath")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
	local Format = Loader.require("ReplicatedStorage/Shared/Format")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Layout = Loader.require("ReplicatedStorage/Client/UI/Layout")

	------------------------------------------------------------------
	T.suite("5판 구멍 찾기: 경비 고정 속도 (4판) — GuardianService")

	local function guardWorld()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local w = { H = H }
		w.Sessions = H.server("Sessions")
		w.SpeedService = H.server("Services/SpeedService")
		w.GuardianService = H.server("Services/GuardianService")
		w.GuardianService.start()
		w.player = H.newPlayer(1001, "Runner")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		H.spawn(w.player, 0, 3, 0)
		return w
	end

	local function guardOf(w, biomeId)
		for _, model in w.H.map.folders.Guardians.children do
			if model:GetAttribute("BiomeId") == biomeId and not model.destroyed then
				return model
			end
		end
		return nil
	end

	local function humanoidOf(model)
		for _, child in model.children do
			if child.ClassName == "Humanoid" then
				return child
			end
		end
		return nil
	end

	-- 그 구역 알을 든 상태로 만들기 (속도·알 무게는 SpeedService 에 반영)
	local function carry(w, player, biomeId, speed, penalty)
		local session = w.Sessions.get(player)
		session.data.speed = speed
		session.carryingUid = "e1"
		session.carryPenalty = penalty
		w.SpeedService.refresh(player)
		w.H.carry(player, { petId = "chicken", biomeId = biomeId, uid = "e1" })
	end

	local function standIn(w, player, biomeId, dx)
		local zone = w.H.map.zones[biomeId]
		w.H.teleport(player, zone.centerX + (dx or 30), 3, zone.centerZ)
	end

	T.test(
		"15구역 모두: 쫓는 WalkSpeed = toWalkSpeed(경비 속도 × 0.99) (상한 250) — 플레이어 속도 5 · 1천 · 1e15 · 1e30 · 알 무게 0 / 0.5 / 0.9 에도 같음",
		function()
			local w = guardWorld()
			for _, biome in Biomes.list do
				local want = SpeedMath.toWalkSpeed(biome.guardSpeed * Config.GUARD_CHASE_MARGIN)
				want = math.clamp(want, 1, Config.GUARD_MAX_WALKSPEED)
				T.near(SpeedMath.guardChaseSpeed(biome.guardSpeed), want, 1e-9, biome.id .. " 공식")
				for _, speed in { 5, 1000, 1e15, 1e30 } do
					for _, penalty in { 0, 0.5, 0.9 } do
						carry(w, w.player, biome.id, speed, penalty)
						standIn(w, w.player, biome.id)
						w.H.advance(0.3)
						local model = guardOf(w, biome.id)
						T.eq(model:GetAttribute("State"), "Chase", biome.id)
						T.near(
							humanoidOf(model).WalkSpeed,
							want,
							1e-9,
							string.format("%s 속도 %g 무게 %g", biome.id, speed, penalty)
						)
					end
				end
				w.H.eggs.carried[w.player] = nil
				w.H.advance(0.3)
			end
			w.H.uninstall()
		end
	)

	T.test(
		"추격 도중 플레이어 WalkSpeed 를 마구 바꿔도(속도 업·트레일·러닝머신·슬로 모드) 경비 속도는 한 번도 안 변함",
		function()
			local w = guardWorld()
			carry(w, w.player, "forest", 20, 0.1)
			standIn(w, w.player, "forest", 60)
			local model
			local seen = {}
			for step = 1, 40 do
				-- 플레이어 속도를 바꿈: 모은 속도, 장착 트레일, 직접 WalkSpeed(속도핵 흉내)
				w.data.speed = 20 * (3 ^ step)
				w.session.walkSpeed = 10 + step * 5
				w.player.Character.humanoid.WalkSpeed = 10 + step * 6
				w.SpeedService.refresh(w.player)
				w.H.advance(0.15)
				model = guardOf(w, "forest")
				T.eq(model:GetAttribute("State"), "Chase", "step " .. step)
				seen[string.format("%.6f", humanoidOf(model).WalkSpeed)] = true
			end
			local distinct = 0
			for _ in seen do
				distinct += 1
			end
			T.eq(distinct, 1, "추격 속도가 " .. distinct .. "가지로 바뀜")
			w.H.uninstall()
		end
	)

	T.test(
		"추격이 끝나면(알을 놓음) 경비는 평소 걷기 속도 toWalkSpeed(경비 속도)로 돌아가 집으로, 다시 잠듦",
		function()
			local w = guardWorld()
			local biome = Biomes.get("forest")
			carry(w, w.player, "forest", 5, 0.1)
			standIn(w, w.player, "forest", 40)
			w.H.advance(0.3)
			local model = guardOf(w, "forest")
			local human = humanoidOf(model)
			T.near(human.WalkSpeed, SpeedMath.guardChaseSpeed(biome.guardSpeed), 1e-9)
			w.H.eggs.carried[w.player] = nil
			w.H.advance(0.3)
			T.truthy(model:GetAttribute("State") ~= "Chase", "추격 끝")
			T.near(human.WalkSpeed, SpeedMath.guardBaseWalkSpeed(biome.guardSpeed), 1e-9, "돌아갈 때 속도")
			T.eq(model:GetAttribute("TargetUserId"), 0)
			w.H.uninstall()
		end
	)

	T.test(
		"같은 구역 알 든 사람이 둘이면 더 가까운 사람을 쫓고, 속도는 누구든 같음 · 다른 구역 알이면 안 깨움",
		function()
			local w = guardWorld()
			local other = w.H.newPlayer(1002, "Other")
			local otherSession = w.H.login(other)
			otherSession.plotIndex = 2
			w.H.spawn(other, 0, 3, 0)
			carry(w, w.player, "forest", 20, 0.1)
			carry(w, other, "forest", 1e12, 0.1)
			local zone = w.H.map.zones.forest
			local home = w.H.MapLayout.guardHome("forest")
			w.H.teleport(w.player, home.x + 80, 3, home.z)
			w.H.teleport(other, home.x - 20, 3, home.z)
			w.H.advance(0.3)
			local model = guardOf(w, "forest")
			T.eq(model:GetAttribute("TargetUserId"), 1002, "가까운 사람")
			local fixed = SpeedMath.guardChaseSpeed(Biomes.get("forest").guardSpeed)
			T.near(humanoidOf(model).WalkSpeed, fixed, 1e-9)
			-- 다른 구역(호수) 알을 들고 숲을 지나는 사람은 숲 경비를 안 깨움
			w.H.eggs.carried[w.player] = nil
			w.H.eggs.carried[other] = nil
			w.H.advance(0.3)
			carry(w, w.player, "lake", 20, 0.1)
			w.H.teleport(w.player, home.x + 5, 3, home.z)
			w.H.advance(0.3)
			T.truthy(
				guardOf(w, "forest"):GetAttribute("State") ~= "Chase",
				"호수 알 든 사람은 숲 경비가 안 쫓음"
			)
			_ = zone
			w.H.uninstall()
		end
	)

	T.test("밤에는 쫓지 않고(알을 훔칠 수도 없음), 밤이 되면 쫓던 경비도 멈춤", function()
		local w = guardWorld()
		carry(w, w.player, "forest", 5, 0.1)
		standIn(w, w.player, "forest", 40)
		w.H.advance(0.3)
		local model = guardOf(w, "forest")
		T.eq(model:GetAttribute("State"), "Chase")
		w.H.setPhase("Night")
		w.H.advance(0.3)
		T.truthy(model:GetAttribute("State") ~= "Chase", "밤: 추격 멈춤")
		w.H.uninstall()
	end)

	------------------------------------------------------------------
	T.suite("5판 구멍 찾기: 알 타이머 표시 (4판) — Economy.timerSeconds · 우리 알 이름표")

	T.test(
		"timerSeconds = 남은 '알 시간' 그대로: 낮밤 상관없이 같은 값, 0 아래로 안 내려감, 이상한 입력에도 안 터짐",
		function()
			for _, required in { 3, 10, 300, 5400, 86400, 72000 } do
				for _, progress in { 0, 1, required / 3, required - 1, required, required + 50 } do
					local expected = math.max(0, required - progress)
					T.eq(Economy.timerSeconds(progress, required), expected, required .. "/" .. progress)
					-- 낮 1초에 1씩, 밤 1초에 30씩 줄어드는 '진짜 남은 시간'과 다름을 확인: 표시는 rate 와 무관
					T.eq(Economy.remainingSeconds(progress, required, 1), expected, "낮")
					T.near(
						Economy.remainingSeconds(progress, required, 30),
						expected / 30,
						1e-9,
						"밤(진짜 남은 시간)"
					)
				end
			end
			T.eq(Economy.timerSeconds(0, 0), 0)
			T.eq(Economy.timerSeconds(5, 3), 0, "다 자란 알")
			T.truthy(Economy.timerSeconds(0 / 0, 10) ~= Economy.timerSeconds(0 / 0, 10) or true)
		end
	)

	T.test(
		"낮 1초는 1 줄고 밤 1초는 30 줆 — 낮↔밤을 오가도 숫자가 절대 늘거나 ÷30 으로 튀지 않음",
		function()
			local previous = Economy.timerSeconds(0, 600)
			local progress = 0
			local rates = { 1, 1, 30, 30, 30, 1, 30, 1 }
			for i, rate in rates do
				progress = Economy.advanceIncubation(progress, 600, 1, rate)
				local shown = Economy.timerSeconds(progress, 600)
				T.eq(previous - shown, rate, "tick " .. i)
				previous = shown
			end
			T.eq(previous, 600 - (1 + 1 + 30 + 30 + 30 + 1 + 30 + 1))
		end
	)

	-- BaseService 가 우리 알 위 이름표에 쓰는 글 (Util/Gui 를 가로채서 읽음)
	local function labelWorld()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local labels = {}
		Loader.mock("ServerScriptService/Server/Util/Gui", {
			billboard = function(_, text)
				local label = { Text = text }
				table.insert(labels, label)
				return label
			end,
			surface = function()
				return { Text = "" }
			end,
			sign = function()
				return { frame = {}, title = { Text = "" } }
			end,
			tag = function()
				return {}
			end,
		})
		local w = { H = H, labels = labels }
		w.MapLayout = H.MapLayout
		w.EggPlacement = H.shared("EggPlacement")
		w.BaseService = H.server("Services/BaseService")
		w.BaseService.start()
		w.player = H.newPlayer(1001, "Tester")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		local x, z = H.plotSpot(1)
		H.spawn(w.player, x, 3, z)
		return w
	end

	local function placeEggOf(w, petId)
		w.BaseService.grantEgg(w.player, petId, "normal", {}, "dev")
		local egg = w.data.eggs[#w.data.eggs]
		local spots = {}
		for _, r in w.data.incubators do
			table.insert(spots, { x = r.x, z = r.z, size = r.size })
		end
		local l = w.EggPlacement.firstFreeGrid(egg.size, spots)
		local spot = w.MapLayout.toWorld(1, l.x, l.z)
		w.H.client(w.player, "PlaceEgg", egg.uid, spot.x, spot.z)
		return w.data.incubators[#w.data.incubators]
	end

	T.test(
		"우리 알 이름표: 5분짜리 알은 낮 1초에 5m 0s → 4m 59s, 밤 1초에 4m 29s 로 (30 줄어듦) — 낮→밤 전환에서 '9s' 로 튀지 않음",
		function()
			local w = labelWorld()
			local petId
			for _, pet in Pets.list do
				if pet.hatchSeconds == 300 or (pet.hatchSeconds >= 300 and pet.hatchSeconds <= 900 and not petId) then
					petId = pet.id
				end
			end
			local pet = Pets.get(petId)
			local record = placeEggOf(w, petId)
			local label = w.labels[#w.labels]
			T.eq(label.Text, pet.name .. "\n" .. Format.duration(pet.hatchSeconds), "처음")
			local required = record.required
			w.H.advance(1.05)
			T.eq(label.Text, pet.name .. "\n" .. Format.duration(required - record.progress), "낮 1초")
			T.near(required - record.progress, required - 1, 0.1)
			local before = required - record.progress
			w.H.setPhase("Night")
			w.H.advance(1.05)
			local after = required - record.progress
			T.near(before - after, 30, 1.5, "밤 1초 = 30 줄어듦")
			T.eq(label.Text, pet.name .. "\n" .. Format.duration(after), "밤 1초 뒤 글")
			T.truthy(after > before / 30, "÷30 으로 튀지 않음")
			w.H.setPhase("Day")
			w.H.advance(1.05)
			local day2 = required - record.progress
			T.near(after - day2, 1, 0.1, "다시 낮 1초 = 1")
			T.eq(label.Text, pet.name .. "\n" .. Format.duration(day2))
			w.H.uninstall()
		end
	)

	T.test(
		"다 자라면 이름표 '부화 준비 완료!', 개 알(3초)은 낮 3초면 다 자람 · 밤이면 0.1초 만에",
		function()
			local w = labelWorld()
			local record = placeEggOf(w, "dog")
			local label = w.labels[#w.labels]
			T.eq(record.required, 3, "개 알 3초")
			T.eq(label.Text, "개\n3s")
			w.H.advance(1.05)
			T.eq(label.Text, "개\n2s")
			w.H.advance(2)
			T.truthy(record.progress >= record.required)
			T.eq(label.Text, "개\n부화 준비 완료!")
			w.H.uninstall()
			local n = labelWorld()
			n.H.setPhase("Night")
			local r2 = placeEggOf(n, "dog")
			n.H.advance(1.05)
			T.truthy(r2.progress >= r2.required, "밤: 첫 1초에 다 자람")
			n.H.uninstall()
		end
	)

	T.test(
		"개발 명령 /egg dog → 가방에 개 알(부화 3초), /grow 로 바로 다 자람, 알 번호는 중복 없음",
		function()
			local H = ServerHarness.install(Loader, T)
			H.startNet()
			H.server("Services/SakuraService")
			local BaseService = H.server("Services/BaseService")
			BaseService.start()
			local DevCommands = H.server("Services/DevCommands")
			DevCommands.start()
			local p = H.newPlayer(1001, "Dev")
			local session, data = H.login(p)
			session.plotIndex = 1
			H.Players.PlayerAdded:Fire(p)
			p.Chatted:Fire("/egg dog")
			p.Chatted:Fire("/egg dog")
			p.Chatted:Fire("/egg nosuchpet")
			T.eq(#data.eggs, 2)
			T.eq(data.eggs[1].petId, "dog")
			T.eq(data.eggs[1].required, 3)
			T.truthy(data.eggs[1].uid ~= data.eggs[2].uid)
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("5판 구멍 찾기: 핫바 알 칸 계산 (Layout.hotbarEggs / hotbarCapacity)")

	T.test("알 7개면 6칸 + '+1' (자리가 7칸 이상일 때), 6개면 6칸만, 0개면 없음", function()
		local shown, more = Layout.hotbarEggs(12, 3, 7)
		T.eq(shown, 6)
		T.truthy(more)
		T.eq(7 - shown, 1, "'+1'")
		shown, more = Layout.hotbarEggs(12, 3, 6)
		T.eq(shown, 6)
		T.falsy(more)
		shown, more = Layout.hotbarEggs(12, 3, 0)
		T.eq(shown, 0)
		T.falsy(more)
		-- 50개(가방 최대)도 6칸 + '+44'
		shown, more = Layout.hotbarEggs(12, 3, Config.EGG_INVENTORY_MAX)
		T.eq(shown, 6)
		T.truthy(more)
	end)

	T.test("모든 칸 수 조합(자리 1~16 × 고정 칸 0~12 × 알 0~60)에서 규칙이 지켜짐", function()
		for capacity = 1, 16 do
			for fixed = 0, 12 do
				local free = math.max(capacity - fixed, 1)
				for bag = 0, 60 do
					local shown, more = Layout.hotbarEggs(capacity, fixed, bag)
					local label = string.format(
						"자리 %d 고정 %d 알 %d → %d칸 %s",
						capacity,
						fixed,
						bag,
						shown,
						tostring(more)
					)
					T.truthy(shown >= 0 and shown <= Layout.HOTBAR_EGG_MAX, label)
					if bag == 0 then
						T.eq(shown, 0, label)
						T.falsy(more, label)
					else
						T.truthy(
							shown + (if more then 1 else 0) >= 1,
							"알이 있으면 칸이나 '+n' 중 하나는 보임: " .. label
						)
						T.truthy(shown + (if more then 1 else 0) <= free, "자리를 넘지 않음: " .. label)
						if more then
							T.truthy(shown < bag, "'+n' 은 못 보인 알이 있을 때만: " .. label)
						else
							T.eq(shown, bag, "'+n' 이 없으면 알이 전부 보임: " .. label)
						end
					end
				end
			end
		end
	end)

	T.test(
		"실제 화면 크기에서 자리: PC 1428×750 · 폰 844×390 · 폰 750×381 — 도구 2 + 든 알 1 + 알 6 + '+n' 이 들어가는지",
		function()
			local pc = Layout.hotbarCapacity({ X = 1428, Y = 750 }, false, 350, nil)
			T.truthy(pc >= 10, "PC 자리 " .. pc)
			local shown, more = Layout.hotbarEggs(pc, 3, 7)
			T.eq(shown, 6, "PC: 알 7개 → 6칸")
			T.truthy(more)
			-- 폰: 자리가 모자라면 알 칸을 줄이되, 알이 있으면 하나는 보임
			for _, size in { { 844, 390 }, { 750, 381 }, { 667, 375 } } do
				local area = { X = size[1], Y = size[2] }
				local cap = Layout.hotbarCapacity(area, true, 8, nil)
				T.truthy(cap >= 1, size[1] .. "×" .. size[2] .. " 자리 " .. cap)
				local s, m = Layout.hotbarEggs(cap, 2, 7)
				T.truthy(s + (if m then 1 else 0) >= 1, "폰에서도 알 칸이나 '+n' 보임")
				print(
					string.format(
						"      [정보] %d×%d 폰: 핫바 자리 %d칸 → 도구 2칸 + 알 7개 → 알 %d칸%s",
						size[1],
						size[2],
						cap,
						s,
						if m then " + '+n'" else ""
					)
				)
			end
		end
	)

	------------------------------------------------------------------
	T.suite("5판 구멍 찾기: 서버 Remote 막 던지기 (모든 ToServer 에 엉터리 인자)")

	local function fuzzWorld()
		local H = ServerHarness.install(Loader, T, { realEgg = true })
		H.startNet()
		local w = { H = H }
		w.Remotes = H.shared("Remotes")
		for _, name in
			{
				"EggService",
				"PetService",
				"IndexService",
				"BaseService",
				"TutorialService",
				"UpgradeService",
				"TreadmillService",
				"ToolService",
				"FusionService",
				"SakuraService",
				"AltarService",
			}
		do
			w[name] = H.server("Services/" .. name)
			w[name].start()
		end
		H.setPhase("Intermission", 1)
		H.setPhase("Day", 1)
		w.player = H.newPlayer(1001, "Fuzz")
		w.session, w.data = H.login(w.player, { tutorialStep = 3, money = 1234, speed = 777 })
		w.session.plotIndex = 1
		local x, z = H.plotSpot(1)
		H.spawn(w.player, x, 3, z)
		H.giveBackpack(w.player)
		w.PetService.addPet(w.player, { uid = "p1", petId = "chicken", size = "normal", mutations = {} })
		w.BaseService.grantEgg(w.player, "dog", "normal", {}, "dev")
		w.BaseService.grantEgg(w.player, "chicken", "normal", {}, "dev")
		return w
	end

	local function stateOf(w)
		local d = w.data
		return table.concat({
			d.money,
			d.speed,
			#d.pets,
			#d.equipped,
			#d.eggs,
			#d.incubators,
			d.tutorialStep,
			d.penLevel,
			d.treadmillLevel,
			#d.trails,
		}, "|")
	end

	T.test("모든 ToServer Remote 에 핸들러가 붙어 있음 (RequestSnapshot 은 PlayerLifecycle 몫)", function()
		local w = fuzzWorld()
		for name in w.Remotes.ToServer do
			local remote = w.H.remotes[name]
			T.truthy(remote, name .. " 가 만들어짐")
			if name ~= "RequestSnapshot" then
				T.truthy(#remote.OnServerEvent.handlers >= 1, name .. " 핸들러 없음 (누가 Net.on 안 함)")
			end
		end
		w.H.uninstall()
	end)

	T.test(
		"엉터리 인자(없음·nil·빈 글·거대한 글·숫자 NaN/inf/음수/1e308·표·불리언·SQL 같은 글·인자 많이)를 모든 Remote 에 던져도: 오류(warn) 0, 돈·속도·펫·알·단계 그대로",
		function()
			local w = fuzzWorld()
			local huge = string.rep("가", 70000)
			local cases = {
				{ n = 0 },
				{ n = 1 },
				{ "", n = 1 },
				{ " ", n = 1 },
				{ "x", n = 1 },
				{ huge, n = 1 },
				{ "i99", n = 1 },
				{ "../../etc", n = 1 },
				{ "'; DROP TABLE;--", n = 1 },
				{ -1, n = 1 },
				{ 0, n = 1 },
				{ 0.5, n = 1 },
				{ 0 / 0, n = 1 },
				{ math.huge, n = 1 },
				{ -math.huge, n = 1 },
				{ 1e308, n = 1 },
				{ true, n = 1 },
				{ false, n = 1 },
				{ {}, n = 1 },
				{ { 1, 2, 3 }, n = 1 },
				{ { uid = "i1" }, n = 1 },
				{ { { { {} } } }, n = 1 },
				{ "x", "y", n = 2 },
				{ "x", 0 / 0, math.huge, n = 3 },
				{ nil, nil, nil, n = 3 },
				{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, n = 10 },
				{ "zzz", 1e308, -1e308, n = 3 },
				{ "Bat", n = 1 },
				{ "Nope", n = 1 },
				{ "Trail", "nope", n = 2 },
			}
			local before = stateOf(w)
			local calls = 0
			for name in w.Remotes.ToServer do
				if name ~= "RequestSnapshot" then
					for _, args in cases do
						w.H.advance(4) -- 레이트 리밋 칸 채우기
						w.H.client(w.player, name, table.unpack(args, 1, args.n))
						calls += 1
					end
				end
			end
			T.truthy(calls > 500, "던진 횟수 " .. calls)
			T.eq(#w.H.warnings, 0, "처리 중 오류가 난 Remote 가 있음: " .. table.concat(w.H.warnings, " / "))
			T.eq(stateOf(w), before, "엉터리 인자로 게임 상태가 바뀜")
			w.H.uninstall()
		end
	)

	T.test(
		"PlaceEgg 좌표 구멍: 가방 알 uid 는 맞고 좌표가 NaN / inf / 1e308 / 음수 0 / 다른 베이스 / 허브 밖이면 놓이지 않고 오류도 없음",
		function()
			local w = fuzzWorld()
			local uid = w.data.eggs[1].uid
			local bad = {
				{ 0 / 0, 0 },
				{ 0, 0 / 0 },
				{ math.huge, 0 },
				{ 0, -math.huge },
				{ 1e308, 1e308 },
				{ -1e308, -1e308 },
				{ 0, 0 }, -- 허브 가운데 (내 우리 아님)
				{ 0, 5000 }, -- 아주 먼 구역
				{ -3.4e38, 1e-300 },
				{ 1e15, -1e15 },
			}
			for _, xz in bad do
				w.H.advance(4)
				w.H.client(w.player, "PlaceEgg", uid, xz[1], xz[2])
			end
			-- 다른 사람 베이스(2번) 한가운데
			local r2 = w.MapLayoutPen or w.H.MapLayout.penRect(2)
			w.H.advance(4)
			w.H.client(w.player, "PlaceEgg", uid, (r2.xMin + r2.xMax) / 2, (r2.zMin + r2.zMax) / 2)
			T.eq(#w.data.incubators, 0, "어느 것도 놓이면 안 됨")
			T.eq(#w.data.eggs, 2)
			T.eq(#w.H.warnings, 0, "오류 없음: " .. table.concat(w.H.warnings, " / "))
			w.H.uninstall()
		end
	)

	T.test(
		"남의 알 uid · 이미 놓은 알 uid 로 PlaceEgg / PickUpPlacedEgg / HatchEgg 해도 아무 일 없음",
		function()
			local w = fuzzWorld()
			local other = w.H.newPlayer(2002, "Victim")
			local otherSession, otherData = w.H.login(other)
			otherSession.plotIndex = 2
			w.BaseService.grantEgg(other, "dog", "normal", {}, "dev")
			local victimEgg = otherData.eggs[1].uid
			local mine = w.data.eggs[1].uid
			local x, z = w.H.plotSpot(1)
			-- 남이 가진 알 uid (우연히 내 번호와 같아도 내 데이터 기준으로만 찾음)
			w.H.advance(4)
			w.H.client(w.player, "PlaceEgg", "i9999", x, z)
			T.eq(#w.data.incubators, 0)
			-- 내 알을 놓고, 같은 uid 로 또 놓기 / 가방에서 다시 없는 uid 로 줍기
			local r = w.H.MapLayout.toWorld(1, -24, 0)
			w.H.advance(4)
			w.H.client(w.player, "PlaceEgg", mine, r.x, r.z)
			T.eq(#w.data.incubators, 1)
			w.H.advance(4)
			w.H.client(w.player, "PlaceEgg", mine, r.x + 10, r.z)
			T.eq(#w.data.incubators, 1, "같은 알을 두 번 놓을 수 없음")
			w.H.advance(4)
			w.H.client(w.player, "PickUpPlacedEgg", victimEgg)
			T.eq(#otherData.eggs, 1, "남의 알은 그대로")
			w.H.client(w.player, "HatchEgg", victimEgg)
			T.eq(#otherData.eggs, 1)
			T.eq(#w.H.warnings, 0)
			w.H.uninstall()
		end
	)
end
