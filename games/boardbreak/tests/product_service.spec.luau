--!nocheck
--[[
	product_service — 진짜 게임패스 12개 (2026-11-17 게시, universe 10777294360) 의 소유 확인 길. 진짜 서버 코드 + ServerHarness 가짜 MarketplaceService.
	  A 접속 때 소유 확인 (syncPasses): 가질 때만 · 순서를 건너뛴 패스 = boostFromOwnedPasses · 절대 낮추지 않음
	  B 구매 끝 신호 (PromptGamePassPurchaseFinished): 안 샀으면 없음 · 샀다는 신호여도 서버가 다시 확인 · 늦게 반영 · 한 번만
	  C 확인이 실패·시간 초과·이상한 답 → 안 주고 · 오류 없고 · 다음 접속 때 다시
	  D 이상한 id · 클라 Remote 로는 못 받음 · 영수증으로 패스 안 줌
	  E 효과: 힘 배수는 몸 크기와 상관없음 · 돈 2배는 한 번만 · 개발 명령 /buy · /unbuy (스튜디오만) · 게임 만든 사람 = 전부 가짐
]]
return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function setup()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local S = {
			Data = H.server("Services/DataService"),
			Product = H.server("Services/ProductService"),
			Train = H.server("Services/TrainService"),
			Break = H.server("Services/BreakService"),
			Shop = H.server("Services/ShopService"),
			World = H.server("Services/WorldService"),
			Exam = H.server("Services/ExamService"),
			Dev = H.server("Services/DevCommands"),
			Life = H.server("Services/PlayerLifecycle"),
			Size = H.server("Services/SizeService"),
			Sessions = H.server("Sessions"),
		}
		S.Data.start()
		S.Product.start()
		S.Train.start()
		S.Break.start()
		S.Shop.start()
		S.World.start()
		S.Exam.start()
		S.Life.start()
		H.S = S
		H.Products = H.shared("Data/Products")
		H.Targets = H.shared("Data/Targets")
		H.Belts = H.shared("Data/Belts")
		H.Remotes = H.shared("Remotes")
		-- 구매 확인 재시도 간격을 짧게 (가상 시간이라 상관없지만 시험이 빨리 끝나게)
		S.Product.PURCHASE_CONFIRM_SECONDS = 1
		return H
	end

	local function id(H, key)
		return H.Products.get(key).productId
	end

	-- 로그인만 (PlayerLifecycle 없이) + 캐릭터
	local function join(H, userId, overrides)
		local p = H.newPlayer(userId)
		local session, data = H.login(p, overrides)
		H.spawn(p, H.spawnSpot(1))
		H.S.Size.refresh(p)
		return p, session, data
	end

	-- 진짜 접속 (DataStore 불러오기 → PlayerLifecycle → ProductService.onPlayerReady → syncPasses)
	local function joinReal(H, userId)
		local p = H.newPlayer(userId)
		H.spawn(p, 0, 3, 0)
		H.run(function()
			H.S.Life.onPlayerAdded(p)
			return true
		end)
		H.advance(6) -- 접속 때 소유 확인 (실패하면 재시도 1초 × 2) 이 끝나게
		local session, data = H.S.Sessions.getLoaded(p)
		return p, session, data
	end

	local function own(H, p, keys)
		local set = {}
		for _, key in keys do
			set[id(H, key)] = true
		end
		H.market.owned[p.UserId] = set
	end

	local function sync(H, p)
		return H.run(function()
			return H.S.Product.syncPasses(p)
		end, 90)
	end

	-- 서버 쪽 구매 끝 신호 (로블록스가 서버에서 쏨 — ProductService.start 가 연결)
	local function finished(H, p, gamePassId, wasPurchased)
		H.run(function()
			H.market.PromptGamePassPurchaseFinished:Fire(p, gamePassId, wasPurchased)
			return true
		end, 90)
	end

	local function grants(H, p)
		return #H.sent(p, "ProductGranted")
	end

	local function allKeys(H)
		local list = {}
		for _, prod in H.Products.passes do
			table.insert(list, prod.key)
		end
		return list
	end

	------------------------------------------------------------------
	T.suite("product_service A: 접속 때 소유 확인 (syncPasses)")
	------------------------------------------------------------------

	T.test(
		"가질 때만: 아무것도 없으면 그대로 · power_2 → 2배 · money_2 → 돈 2배 · 12개 다 → 2048배 + 돈 2배 (Attribute 도)",
		function()
			local H = setup()
			local p1, _, d1 = join(H, 1)
			own(H, p1, {})
			T.truthy(sync(H, p1))
			T.eq(d1.powerBoost, 1)
			T.eq(d1.moneyPass, false)
			T.eq(H.market.calls, #H.Products.passes, "12개 다 확인")
			local p2, _, d2 = join(H, 2)
			own(H, p2, { "power_2" })
			sync(H, p2)
			T.eq(d2.powerBoost, 2)
			T.eq(p2:GetAttribute("PowerBoost"), 2)
			T.eq(d2.moneyPass, false)
			local p3, _, d3 = join(H, 3)
			own(H, p3, { "money_2" })
			sync(H, p3)
			T.eq(d3.moneyPass, true)
			T.eq(p3:GetAttribute("MoneyPass"), true)
			T.eq(d3.powerBoost, 1)
			local p4, s4, d4 = join(H, 4)
			own(H, p4, allKeys(H))
			sync(H, p4)
			T.eq(d4.powerBoost, 2048)
			T.eq(d4.moneyPass, true)
			for _, key in allKeys(H) do
				T.truthy(s4.ownedPasses[key], key .. " 세션에 기록")
			end
			-- 다른 사람의 소유가 섞이지 않음
			T.eq(d1.powerBoost, 1)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"순서를 건너뛰어 산 패스 = Products.boostFromOwnedPasses (낸 값만큼): 2048 만 → 1024 · 4 만 → 2 · {2,8} → 4 · 11개 한 개씩 전부",
		function()
			local H = setup()
			local cases = {
				{ { "power_2048" }, 1024 },
				{ { "power_4" }, 2 },
				{ { "power_2", "power_8" }, 4 },
				{ { "power_2", "power_4", "power_8" }, 8 },
				{ { "power_16", "money_2" }, 8 },
			}
			for _, prod in H.Products.powerBoosts do
				table.insert(cases, { { prod.key }, H.Products.boostFromOwnedPasses({ prod.value }) })
			end
			for i, c in cases do
				local p, _, data = join(H, 100 + i)
				own(H, p, c[1])
				sync(H, p)
				T.eq(data.powerBoost, c[2], table.concat(c[1], "+"))
				local values = {}
				for _, key in c[1] do
					local prod = H.Products.get(key)
					if prod.kind == "powerBoost" then
						table.insert(values, prod.value)
					end
				end
				T.eq(
					data.powerBoost,
					H.Products.boostFromOwnedPasses(values),
					"모듈 규칙과 같음 " .. table.concat(c[1], "+")
				)
			end
			H.uninstall()
		end
	)

	T.test(
		"절대 낮추지 않음: 저장된 배수 · /buy 로 받은 것 · 돈 2배는 확인에 없어도 그대로",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { powerBoost = 64, moneyPass = true })
			own(H, p, { "power_2" })
			sync(H, p)
			T.eq(data.powerBoost, 64)
			T.eq(data.moneyPass, true)
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("product_service B: 구매 끝 신호 (PromptGamePassPurchaseFinished)")
	------------------------------------------------------------------

	T.test(
		"안 샀으면 (wasPurchased 거짓 · nil · 글자 'true' · 1) 아무것도 없음 — 소유 확인도 안 부름",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			own(H, p, allKeys(H)) -- 가졌어도 신호가 "안 샀음" 이면 이 길로는 안 줌
			for _, was in { false, nil, "true", 1, {} } do
				finished(H, p, id(H, "power_2"), was)
			end
			T.eq(H.market.calls, 0)
			T.eq(data.powerBoost, 1)
			T.eq(grants(H, p), 0)
			H.uninstall()
		end
	)

	T.test(
		"샀다는 신호여도 서버가 다시 확인: 안 가졌으면 (3번 다시 물어도) 안 줌 · 안내 글 · ProductGranted 없음",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			own(H, p, {})
			finished(H, p, id(H, "power_2"), true)
			T.eq(data.powerBoost, 1, "안 가졌으면 안 줌")
			T.eq(grants(H, p), 0)
			T.eq(
				H.market.calls,
				H.S.Product.PURCHASE_CONFIRM_TRIES,
				"반영이 늦을 수 있어 몇 번 더 물어봄"
			)
			T.truthy(H.hasNotify(p, "info", "구매 확인 중"))
			finished(H, p, id(H, "money_2"), true)
			T.eq(data.moneyPass, false)
			T.eq(grants(H, p), 0)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"샀고 가졌으면 바로 줌 (2배 · ProductGranted 1번 · 축하 글) · 같은 신호가 또 와도 한 번만 · 다른 패스도 다시 확인해 배수를 맞춤",
		function()
			local H = setup()
			local p, session, data = join(H, 1)
			own(H, p, { "power_2" })
			finished(H, p, id(H, "power_2"), true)
			T.eq(data.powerBoost, 2)
			T.eq(p:GetAttribute("PowerBoost"), 2)
			T.eq(grants(H, p), 1)
			T.eq(H.sent(p, "ProductGranted")[1][1].key, "power_2")
			T.truthy(H.hasNotify(p, "success", "힘 2배"))
			finished(H, p, id(H, "power_2"), true)
			T.eq(grants(H, p), 1, "같은 패스로 두 번 안 줌")
			-- 웹에서 4 · 8 도 샀다 → 8 을 산 신호 → 다시 확인해서 8배
			own(H, p, { "power_2", "power_4", "power_8" })
			finished(H, p, id(H, "power_8"), true)
			T.eq(data.powerBoost, 8)
			T.truthy(session.ownedPasses.power_8)
			T.eq(grants(H, p), 2)
			-- 돈 2배
			own(H, p, { "power_2", "power_4", "power_8", "money_2" })
			finished(H, p, id(H, "money_2"), true)
			T.eq(data.moneyPass, true)
			T.eq(p:GetAttribute("MoneyPass"), true)
			T.eq(grants(H, p), 3)
			H.uninstall()
		end
	)

	T.test(
		"소유 반영이 늦으면 (2번째 확인부터 가짐) 기다렸다가 줌 · 4번째에야 가지면 안 주고 다음 접속 때 맞춤",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			H.market.lateOwned[p.UserId] = { [id(H, "power_2")] = 2 }
			finished(H, p, id(H, "power_2"), true)
			T.eq(data.powerBoost, 2, "두 번째 확인에서 가짐 → 줌")
			T.eq(grants(H, p), 1)
			local q, _, dq = join(H, 2)
			H.market.lateOwned[q.UserId] = { [id(H, "power_2")] = H.S.Product.PURCHASE_CONFIRM_TRIES + 1 }
			finished(H, q, id(H, "power_2"), true)
			T.eq(dq.powerBoost, 1, "끝내 확인 안 됨 → 안 줌")
			T.eq(grants(H, q), 0)
			T.truthy(H.hasNotify(q, "info", "구매 확인 중"))
			sync(H, q) -- 다음 접속 (이제는 가짐)
			T.eq(dq.powerBoost, 2)
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("product_service C: 확인 실패 · 시간 초과 · 이상한 답")
	------------------------------------------------------------------

	T.test(
		"확인이 전부 오류 → 안 줌 · 오류로 안 멈춤 (warn 한 줄) · 다음 접속 때 다시 확인해서 줌 (진짜 DataStore 왕복)",
		function()
			local H = setup()
			H.store.data["player_77"] = { data = { version = 1, power = 50 } }
			H.market.owned[77] = {}
			for _, key in allKeys(H) do
				H.market.owned[77][id(H, key)] = true
			end
			H.market.failAlways = true
			local p, _, data = joinReal(H, 77)
			T.truthy(data, "불러옴")
			T.eq(data.powerBoost, 1, "확인 실패 → 안 줌")
			T.eq(data.moneyPass, false)
			T.eq(grants(H, p), 0)
			local warned = 0
			for _, w in H.warnings do
				if string.find(w, "소유 확인 실패", 1, true) then
					warned += 1
				end
			end
			T.eq(warned, 1, "warn 한 줄: " .. table.concat(H.warnings, " | "))
			H.leave(p)
			H.advance(5)
			H.market.failAlways = false
			local p2, _, data2 = joinReal(H, 77)
			T.eq(data2.powerBoost, 2048, "다음 접속 때 다시 확인 → 줌")
			T.eq(data2.moneyPass, true)
			T.eq(p2:GetAttribute("PowerBoost"), 2048)
			H.uninstall()
		end
	)

	T.test(
		"한 패스만 오류 → 나머지는 반영 · 그 패스는 다음 접속 때 · 처음 몇 번만 오류 → 재시도로 받음",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			own(H, p, { "power_2", "money_2" })
			H.market.failFor[id(H, "money_2")] = true
			sync(H, p)
			T.eq(data.powerBoost, 2)
			T.eq(data.moneyPass, false, "오류 난 패스는 안 줌")
			H.market.failFor = {}
			sync(H, p)
			T.eq(data.moneyPass, true, "다음 확인 때 줌")
			local q, _, dq = join(H, 2)
			own(H, q, { "power_2" })
			H.market.failNext = 2 -- 첫 두 번 오류 (재시도 PASS_CHECK_RETRIES 안)
			sync(H, q)
			T.eq(dq.powerBoost, 2, "재시도로 받음")
			H.uninstall()
		end
	)

	T.test(
		"답이 늦어도 (5초) 됨 · 끝내 안 오면 (시간 초과 30초) 안 주고 오류 없음 · boolean 이 아닌 답 ('yes' · 1) 은 답 없음으로",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			own(H, p, { "power_4", "power_2" })
			H.market.delaySeconds = 5
			T.truthy(sync(H, p))
			T.eq(data.powerBoost, 4)
			H.market.delaySeconds = 0
			local q, _, dq = join(H, 2)
			own(H, q, allKeys(H))
			H.market.hang = true
			T.falsy(sync(H, q), "시간 초과 → false")
			T.eq(dq.powerBoost, 1)
			T.eq(dq.moneyPass, false)
			H.market.hang = false
			for k, weird in { "yes", 1, {} } do
				local r, _, dr = join(H, 10 + k)
				own(H, r, allKeys(H))
				H.market.weird = weird
				sync(H, r)
				T.eq(dr.powerBoost, 1, "이상한 답 " .. tostring(weird))
				T.eq(dr.moneyPass, false)
			end
			H.market.weird = nil
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("product_service D: 이상한 id · 클라 Remote · 영수증")
	------------------------------------------------------------------

	T.test(
		"구매 끝 신호의 id 가 0 · 음수 · NaN · ±무한 · 소수 · 글자 · 표 · 모르는 id · 남의 게임 패스 id → 소유 확인도 안 하고 아무것도 없음",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			own(H, p, allKeys(H))
			local real = id(H, "power_2")
			for _, bad in
				{ 0, -1, -real, 0 / 0, math.huge, -math.huge, real + 0.5, tostring(real), {}, 12345, real + 1, 1e300 }
			do
				finished(H, p, bad, true)
			end
			T.eq(H.market.calls, 0)
			T.eq(data.powerBoost, 1)
			T.eq(data.moneyPass, false)
			T.eq(grants(H, p), 0)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"클라 → 서버 Remote 로는 패스를 못 받음: 이름에 사기·지급 뜻이 없음 · 모든 Remote 에 패스 id · key 를 보내도 그대로",
		function()
			local H = setup()
			for name in H.Remotes.ToServer do
				local lower = string.lower(name)
				for _, bad in { "buy", "pass", "grant", "product", "boost", "money", "purchase", "receipt" } do
					-- BuyDumbbell 은 게임 돈으로 아령 사기 (로벅스 아님)
					if not (name == "BuyDumbbell" and bad == "buy") then
						T.falsy(string.find(lower, bad, 1, true), "Remote " .. name .. " 에 " .. bad)
					end
				end
			end
			local p, _, data = join(H, 1, { money = 1e60 })
			local args =
				{ id(H, "power_2048"), "power_2048", "money_2", id(H, "money_2"), true, { key = "power_2048" } }
			for name in H.Remotes.ToServer do
				for _, a in args do
					H.client(p, name, a, true)
					H.client(p, name, a, a)
				end
				H.advance(2)
			end
			T.eq(data.powerBoost, 1)
			T.eq(data.moneyPass, false)
			T.eq(grants(H, p), 0)
			T.eq(H.market.calls, 0, "클라 신호로 소유 확인도 안 함")
			H.uninstall()
		end
	)

	T.test(
		"영수증(ProcessReceipt) 으로는 게임패스를 안 줌: 패스 id 로 온 영수증 = NotProcessedYet · 지급 없음",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			for i, key in { "power_2048", "money_2" } do
				local decision = H.run(function()
					return H.market.ProcessReceipt({ PlayerId = 1, ProductId = id(H, key), PurchaseId = "r" .. i })
				end)
				T.eq(decision, "ProductPurchaseDecision.NotProcessedYet", key)
			end
			T.eq(data.powerBoost, 1)
			T.eq(data.moneyPass, false)
			T.eq(#data.receipts, 0)
			T.eq(grants(H, p), 0)
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("product_service E: 효과 · 개발 명령 · 게임 만든 사람")
	------------------------------------------------------------------

	T.test(
		"힘 배수는 몸 크기와 상관없음: 12개 다 가져도 BodyScale · Muscle · 걷기 · 스폰 높이 그대로 (맨 힘으로만)",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = 1e20 })
			local before = {
				scale = p:GetAttribute("BodyScale"),
				muscle = p:GetAttribute("Muscle"),
				walk = p.Character.humanoid.WalkSpeed,
				lift = H.S.World.spawnLift(p, 1),
				slack = H.S.Break.slackFor(p, "cotton"),
			}
			own(H, p, allKeys(H))
			sync(H, p)
			T.eq(data.powerBoost, 2048)
			T.eq(p:GetAttribute("BodyScale"), before.scale)
			T.eq(p:GetAttribute("Muscle"), before.muscle)
			T.eq(p.Character.humanoid.WalkSpeed, before.walk)
			T.eq(H.S.World.spawnLift(p, 1), before.lift)
			T.eq(H.S.Break.slackFor(p, "cotton"), before.slack)
			H.uninstall()
		end
	)

	T.test(
		"돈 2배는 한 번만: 확인 5번 · 구매 신호 2번 · /buy 2번 뒤에도 깬 돈 = 값 × 띠 배율 × 2 (4배 안 됨)",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { power = 1e60, belt = 3 })
			own(H, p, { "money_2" })
			for _ = 1, 5 do
				sync(H, p)
			end
			finished(H, p, id(H, "money_2"), true)
			finished(H, p, id(H, "money_2"), true)
			H.S.Product.grant(p, "money_2", "dev")
			H.S.Product.grant(p, "money_2", "dev")
			T.eq(data.moneyPass, true)
			H.teleport(p, H.targetSpot("cotton"))
			H.client(p, "Hit", "cotton")
			local cotton = H.Targets.get("cotton")
			T.eq(data.money, cotton.reward * H.Belts.get(3).moneyMultiplier * 2)
			H.uninstall()
		end
	)

	T.test(
		"게임 만든 사람 (패스 전부 가짐) 도 스튜디오에서 새 플레이어로 시험: /unbuy → 배수 1 · 돈 2배 없음 · 이 접속 동안 확인을 쉼 (돌고 있던 확인 결과도 안 씀) · 진짜로 사면 풀림",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			own(H, p, allKeys(H)) -- 로블록스: 만든 사람은 자기 패스를 전부 가진 것으로 나옴
			sync(H, p)
			T.eq(data.powerBoost, 2048)
			T.truthy(H.S.Dev.handle(p, "/unbuy"))
			T.eq(data.powerBoost, 1)
			T.eq(data.moneyPass, false)
			T.eq(p:GetAttribute("PowerBoost"), 1)
			T.falsy(sync(H, p), "확인 쉼")
			T.eq(data.powerBoost, 1)
			-- 확인이 도는 사이에 /unbuy: 늦게 온 결과로 다시 올리지 않음
			local q, _, dq = join(H, 2)
			own(H, q, allKeys(H))
			H.market.delaySeconds = 3
			local result = nil
			local co = coroutine.create(function()
				result = H.S.Product.syncPasses(q)
			end)
			assert(coroutine.resume(co)) -- 확인이 가짜 시간 3초를 기다리는 동안 멈춤
			H.advance(1)
			H.S.Dev.handle(q, "/unbuy")
			H.advance(10)
			H.market.delaySeconds = 0
			T.eq(result, false, "돌던 확인은 버림")
			T.eq(dq.powerBoost, 1)
			T.eq(dq.moneyPass, false)
			-- 진짜로 사면 쉼이 풀리고 가진 패스가 다시 적용
			finished(H, p, id(H, "power_2"), true)
			T.eq(data.powerBoost, 2048, "산 뒤에는 가진 패스 전부 (만든 사람)")
			H.uninstall()
		end
	)

	T.test(
		"개발 명령 /buy · /unbuy: 스튜디오에서는 됨 (순서대로) · 실서버에서는 무시",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			T.truthy(H.S.Dev.handle(p, "/buy power_2"))
			T.eq(data.powerBoost, 2)
			T.truthy(H.S.Dev.handle(p, "/buy power_8"))
			T.eq(
				data.powerBoost,
				4,
				"2배에서 power_8 (8 R$) → 4배 (4 R$) 까지만 — 순서 건너뛰기 없음"
			)
			T.truthy(H.S.Dev.handle(p, "/buy money_2"))
			T.eq(data.moneyPass, true)
			T.truthy(H.S.Dev.handle(p, "/unbuy"))
			T.eq(data.powerBoost, 1)
			H.RunService.studio = false
			T.falsy(H.S.Dev.handle(p, "/buy power_2048"))
			T.falsy(H.S.Dev.handle(p, "/buy money_2"))
			T.falsy(H.S.Dev.handle(p, "/unbuy"))
			T.eq(data.powerBoost, 1)
			T.eq(data.moneyPass, false)
			H.uninstall()
		end
	)
end
