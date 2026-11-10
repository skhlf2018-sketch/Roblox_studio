--!nocheck
--[[
	9판 버그 수정 (사장님 2026-11-10): "씨앗을 든 채 밤이 되면 그 씨앗이 가방에 들어옴"
	원인: 밤 귀가(BaseService 가 허브 밖 사람을 베이스로 순간이동) → 베이스는 허브 안 → 다음 0.2초 틱에 "허브에 들어옴 = 배달".
	고침: 서버 순간이동(밤 귀가 · 늦게 받은 베이스 · 개발 명령 /zone) 전에 든 씨앗을 둥지로 돌려보냄
	      (EggService.returnCarriedToNest, BaseService.returnCarriedBeforeTeleport). 스스로 걸어서 허브에 들어온 배달은 그대로.
	진짜 EggService + 진짜 BaseService (+ DevCommands) 를 ServerHarness 위에서 (가상 시간).
]]

return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function world()
		local H = ServerHarness.install(Loader, T, { realEgg = true })
		H.startNet()
		local w = { H = H }
		w.Sessions = H.server("Sessions")
		w.EggService = H.server("Services/EggService")
		w.BaseService = H.server("Services/BaseService")
		w.EggService.start()
		w.BaseService.start()
		w.player = H.newPlayer(9101, "Runner")
		w.session, w.data = H.login(w.player)
		w.session.plotIndex = 1
		local x, z = H.plotSpot(1)
		H.spawn(w.player, x, 3, z)
		H.setPhase("Intermission", 1) -- 첫 초기화: 둥지에 씨앗
		H.setPhase("Day", 1)
		return w
	end

	-- 그 구역 둥지 씨앗을 주움 → 씨앗 파트
	local function steal(w, biomeId, player)
		local who = player or w.player
		for _, egg in w.H.map.folders.Eggs.children do
			if egg:GetAttribute("BiomeId") == biomeId and egg:GetAttribute("EggState") == "Nest" then
				w.H.teleport(who, egg.Position.X, egg.Position.Y, egg.Position.Z)
				egg:FindFirstChild("StealPrompt").Triggered:Fire(who)
				if w.EggService.getCarried(who) then
					return egg
				end
			end
		end
		error("주울 씨앗이 없음 " .. biomeId)
	end

	-- 스스로 걸어서 허브로 (순간이동 검사 쉼 + 충분한 시간)
	local function walkIntoHub(w, player)
		local who = player or w.player
		w.H.advance(20)
		w.Sessions.exemptMovement(w.Sessions.get(who), 5)
		local x, z = w.H.hubSpot()
		w.H.teleport(who, x, 3, z)
		w.H.advance(0.6)
	end

	T.suite(
		"9판 버그: 씨앗을 든 채 밤이 되면 가방에 들어오던 것 (서버 순간이동 = 배달 아님)"
	)

	T.test(
		"재현: 씨앗을 든 채 낮 → 밤 — 베이스로 순간이동은 되지만 가방 0, 씨앗은 원래 둥지로, 안내 '밤이 되어 씨앗이 둥지로 돌아갔어요'",
		function()
			local w = world()
			local egg = steal(w, "lake")
			local nestIndex = egg:GetAttribute("NestIndex")
			w.H.advance(1)
			T.eq(egg:GetAttribute("EggState"), "Carried")
			w.H.setPhase("Night")
			local spawn = w.H.MapLayout.plot(1).spawn
			T.eq(
				w.player.Character.root.Position.X,
				spawn.x,
				"베이스 앞마당으로 순간이동 (밤 벽에 안 갇힘)"
			)
			T.eq(w.player.Character.root.Position.Z, spawn.z)
			w.H.advance(1) -- 배달 틱(0.2초) 여러 번
			T.eq(#w.data.eggs, 0, "가방에 안 들어옴")
			T.eq(w.data.stats.eggsDelivered, nil, "배달 횟수도 안 늘어남")
			T.eq(#w.H.sent(w.player, "EggDelivered"), 0)
			T.eq(w.EggService.getCarried(w.player), nil)
			T.eq(w.player.attrs.CarryingEgg, "", "머리 위 씨앗 없음")
			T.eq(egg:GetAttribute("EggState"), "Nest", "씨앗은 둥지로")
			if nestIndex then
				T.eq(egg:GetAttribute("NestIndex"), nestIndex, "원래 둥지")
			end
			T.truthy(w.H.hasNotify(w.player, "info", "밤이 되어 씨앗이 둥지로 돌아갔어요"))
			T.eq(#w.H.warnings, 0)
			w.H.uninstall()
		end
	)

	T.test(
		"정상 배달은 그대로: 낮에 씨앗을 들고 스스로 걸어서 허브에 들어오면 가방으로 (EggDelivered)",
		function()
			local w = world()
			steal(w, "forest")
			walkIntoHub(w)
			T.eq(#w.data.eggs, 1, "걸어서 들어온 배달")
			T.eq(#w.H.sent(w.player, "EggDelivered"), 1)
			T.eq(w.EggService.getCarried(w.player), nil)
			-- 밤에도 허브 안(가방이 가득 차 손에 들고 있음)이면 순간이동도, 둥지로 보내기도 안 함
			w.H.uninstall()
		end
	)

	T.test(
		"씨앗 없이 밤이 되면 순간이동만 (안내 없음) · 허브 안에서 씨앗을 들고 있으면(가방 가득) 그대로",
		function()
			local w = world()
			local zx, zz = w.H.zoneSpot("desert")
			w.H.teleport(w.player, zx, 3, zz)
			w.H.setPhase("Night")
			T.truthy(w.H.MapLayout.isInHub(w.player.Character.root.Position), "허브(베이스)로")
			T.falsy(w.H.hasNotify(w.player, nil, "둥지로 돌아갔어요"))
			w.H.setPhase("Day")
			-- 가방 가득 → 허브에서 씨앗을 손에 든 채
			w.H.setPhase("Intermission", 2)
			w.H.setPhase("Day", 2)
			for _ = 1, 50 do
				w.BaseService.grantEgg(w.player, "sprout_daisy", "normal", {}, "dev")
			end
			local egg = steal(w, "forest")
			walkIntoHub(w)
			T.eq(#w.data.eggs, 50)
			T.eq(egg:GetAttribute("EggState"), "Carried", "가방이 가득 차 손에 그대로")
			local before = w.player.Character.root.Position
			w.H.setPhase("Night")
			T.eq(w.player.Character.root.Position, before, "허브 안이면 순간이동 안 함")
			T.eq(egg:GetAttribute("EggState"), "Carried", "순간이동이 아니라서 그대로")
			w.H.uninstall()
		end
	)

	T.test(
		"다른 서버 순간이동도 같은 구멍 없음: 늦게 받은 베이스(집으로 순간이동) · 개발 명령 /zone hub — 씨앗은 둥지로, 가방 0",
		function()
			local w = world()
			-- ① 베이스 없이(8번째 사람) 씨앗을 들고 복도에 있다가 누가 나가서 베이스를 받음 → 집으로 순간이동
			local late = w.H.newPlayer(9102, "Eighth")
			local lateSession, lateData = w.H.login(late)
			lateSession.plotIndex = 0
			w.H.spawn(late, 0, 3, 100)
			local egg = steal(w, "forest", late)
			w.H.advance(1)
			local owner = w.H.newPlayer(9103, "Leaver")
			local _, _ = w.H.login(owner)
			T.truthy(w.BaseService.assignPlot(owner) > 0)
			w.BaseService.releasePlot(owner) -- 나감 → 8번째 사람에게 배정 + 집으로
			w.H.advance(1)
			T.truthy(lateSession.plotIndex > 0, "베이스를 받음")
			T.truthy(w.H.MapLayout.isInHub(late.Character.root.Position), "집(허브 안)으로 순간이동")
			T.eq(#lateData.eggs, 0, "순간이동으로 배달 안 됨")
			T.eq(egg:GetAttribute("EggState"), "Nest")
			T.truthy(
				w.H.hasNotify(late, "info", "순간이동해서 들고 있던 씨앗이 둥지로 돌아갔어요")
			)
			-- ② 개발 명령 /zone hub
			local DevCommands = w.H.server("Services/DevCommands")
			DevCommands.start()
			local egg2 = steal(w, "forest")
			w.H.advance(1)
			w.player.Chatted:Fire("/zone hub")
			T.truthy(w.H.MapLayout.isInHub(w.player.Character.root.Position), "/zone hub 로 허브")
			w.H.advance(1)
			T.eq(#w.data.eggs, 0, "/zone hub 로 배달 안 됨")
			T.eq(egg2:GetAttribute("EggState"), "Nest")
			-- /zone 다른 구역도 씨앗을 들고 갈 수 없음
			local egg3 = steal(w, "forest")
			w.player.Chatted:Fire("/zone lake")
			T.eq(w.EggService.getCarried(w.player), nil)
			T.eq(egg3:GetAttribute("EggState"), "Nest")
			w.H.uninstall()
		end
	)
end
