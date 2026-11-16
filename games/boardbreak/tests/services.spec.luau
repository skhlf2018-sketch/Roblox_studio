--!nocheck
-- 서버 서비스 (진짜 코드 + ServerHarness): 들기 · 치기 · 아령 사기 · 월드 이동 · 설정 · 패스 · 개발 명령 · 순위
return function(T, Loader)
	local ServerHarness = require("./ServerHarness")

	local function setup()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local S = {
			Train = H.server("Services/TrainService"),
			Break = H.server("Services/BreakService"),
			Shop = H.server("Services/ShopService"),
			World = H.server("Services/WorldService"),
			Exam = H.server("Services/ExamService"),
			Product = H.server("Services/ProductService"),
			Dev = H.server("Services/DevCommands"),
			Leader = H.server("Services/LeaderboardService"),
			Life = H.server("Services/PlayerLifecycle"),
		}
		S.Train.start()
		S.Break.start()
		S.Shop.start()
		S.World.start()
		S.Exam.start()
		S.Life.start()
		H.S = S
		H.Targets = H.shared("Data/Targets")
		H.Belts = H.shared("Data/Belts")
		H.Dumbbells = H.shared("Data/Dumbbells")
		return H
	end

	-- 로그인 + 캐릭터 (기본: 월드 1 수련 매트 위)
	local function join(H, userId, overrides)
		local p = H.newPlayer(userId)
		local session, data = H.login(p, overrides)
		H.spawn(p, H.matSpot(session.currentWorld))
		return p, session, data
	end

	local function count(list)
		return #list
	end

	T.suite("services: 아령 들기 (Train)")

	T.test("수련 매트 위에서만 힘이 오름 · TrainResult · Attr Power", function()
		local H = setup()
		local p, _, data = join(H, 1)
		H.client(p, "Train")
		T.eq(data.power, 1, "1kg 아령 = +1")
		local sent = H.sent(p, "TrainResult")
		T.eq(count(sent), 1)
		T.eq(sent[1][1].gain, 1)
		T.eq(sent[1][1].power, 1)
		T.eq(p:GetAttribute("Power"), 1)
		H.advance(1)
		H.teleport(p, H.spawnSpot(1))
		H.client(p, "Train")
		T.eq(data.power, 1, "매트 밖 = 안 오름")
		T.truthy(H.hasNotify(p, "info", "수련 매트"), "알림")
		H.uninstall()
	end)

	T.test("들 때 PowerBoost 를 곱함 · 아령이 좋을수록 많이", function()
		local H = setup()
		local p, _, data = join(H, 1, { dumbbellLevel = 3, powerBoost = 8 })
		H.client(p, "Train")
		T.eq(data.power, H.Dumbbells.get(3).powerPerRep * 8)
		H.uninstall()
	end)

	T.test("속도 제한: 한꺼번에 20번 → 5번만, 1초 뒤 5번 더 (초당 5번)", function()
		local H = setup()
		local p, _, data = join(H, 1)
		for _ = 1, 20 do
			H.client(p, "Train")
		end
		T.eq(data.power, 5, "처음 5번")
		H.advance(1)
		for _ = 1, 20 do
			H.client(p, "Train")
		end
		T.eq(data.power, 10, "1초에 5번 더")
		H.uninstall()
	end)

	T.test("힘 1e60 에서 멈춤 (2048배 + 블랙홀 아령)", function()
		local H = setup()
		local p, _, data = join(H, 1, { power = 1e60 - 1, dumbbellLevel = 20, powerBoost = 2048 })
		H.client(p, "Train")
		T.eq(data.power, 1e60)
		H.uninstall()
	end)

	T.suite("services: 물건 치기 (Hit)")

	T.test("가까이서 치면 깎이고 깨지면 돈 + broken + HitResult", function()
		local H = setup()
		local cotton = H.Targets.get("cotton")
		local p, session, data = join(H, 1, { power = cotton.hp })
		H.teleport(p, H.targetSpot("cotton"))
		H.client(p, "Hit", "cotton")
		local r = H.sent(p, "HitResult")[1][1]
		T.eq(r.targetId, "cotton")
		T.eq(r.broken, true)
		T.eq(r.reward, cotton.reward)
		T.eq(data.money, cotton.reward)
		T.eq(data.broken.cotton, 1)
		T.eq(session.targetHp.cotton, nil, "다시 가득")
		T.eq(p:GetAttribute("Money"), cotton.reward)
		T.eq(count(H.sent(p, "DataUpdate")), 1, "처음 깬 물건 → progress")
		H.client(p, "Hit", "cotton")
		T.eq(data.broken.cotton, 2)
		T.eq(count(H.sent(p, "DataUpdate")), 1, "두 번째는 progress 안 보냄")
		H.uninstall()
	end)

	T.test("깬 돈 = 값 × 띠 배율 × 돈 2배, 피해 = 힘 × PowerBoost", function()
		local H = setup()
		local glass = H.Targets.get("glass")
		local p, _, data = join(H, 1, { power = glass.hp / 4, powerBoost = 4, belt = 3, moneyPass = true })
		H.teleport(p, H.targetSpot("glass"))
		H.client(p, "Hit", "glass")
		T.eq(data.money, glass.reward * H.Belts.get(3).moneyMultiplier * 2)
		H.uninstall()
	end)

	T.test(
		"힘 문턱 없음: 추천 힘보다 약해도 피해 = 치는 힘 · weak·알림 없음 · 깎인 체력은 떠났다 와도 남음",
		function()
			local H = setup()
			local glass = H.Targets.get("glass")
			local p, session, data = join(H, 1, { power = 1 })
			H.teleport(p, H.targetSpot("glass"))
			H.client(p, "Hit", "glass")
			local r = H.sent(p, "HitResult")[1][1]
			T.eq(r.damage, 1, "힘 1 → 피해 1")
			T.eq(r.reason, nil, "weak 없음")
			T.eq(r.hp, glass.hp - 1)
			T.eq(r.hpMax, glass.hp)
			T.eq(session.targetHp.glass, glass.hp - 1)
			T.eq(data.money, 0)
			T.falsy(H.hasNotify(p, "error", "힘 부족"), "힘 부족 알림 없음")
			-- 다른 물건을 치러 갔다가 돌아와도 그대로
			H.teleport(p, H.targetSpot("cotton"))
			H.advance(1)
			H.client(p, "Hit", "cotton")
			H.teleport(p, H.targetSpot("glass"))
			H.advance(1)
			H.client(p, "Hit", "glass")
			local list = H.sent(p, "HitResult")
			T.eq(list[#list][1].hp, glass.hp - 2, "떠났다 와도 깎인 만큼 남음")
			H.uninstall()
		end
	)

	T.test(
		"힘 1 로도 솜부터 우주까지 (열린 월드 안) 41개 전부 피해 1 · 닫힌 월드는 여전히 무시",
		function()
			local H = setup()
			local p, session = join(H, 1, { power = 1, belt = H.Belts.COUNT, world = 3 })
			for _, t in H.Targets.list do
				session.currentWorld = t.world
				H.teleport(p, H.targetSpot(t.id))
				H.advance(0.3)
				H.client(p, "Hit", t.id)
				local list = H.sent(p, "HitResult")
				local r = list[#list][1]
				T.eq(r.targetId, t.id, t.id)
				T.eq(r.damage, 1, t.id .. " 피해 1")
				T.eq(r.hp, t.hp - 1, t.id .. " 체력 1 깎임")
			end
			T.eq(#H.sent(p, "HitResult"), H.Targets.COUNT)
			local q = join(H, 2, { power = 1, belt = 3, world = 1 })
			H.teleport(q, H.targetSpot("mall"))
			H.client(q, "Hit", "mall")
			T.eq(#H.sent(q, "HitResult"), 0, "띠 3 이면 월드 2 물건은 못 침")
			H.uninstall()
		end
	)

	T.test("없는 id · 이상한 인자 · 먼 거리 · 닫힌 월드 = 무시 (아무것도 안 보냄)", function()
		local H = setup()
		local p, _, data = join(H, 1, { power = 1e50 })
		H.teleport(p, H.targetSpot("cotton"))
		for _, bad in { "nope", 12, nil, {}, string.rep("a", 100), "cotton\0" } do
			H.client(p, "Hit", bad)
			H.advance(0.3)
		end
		H.teleport(p, H.targetSpot("glass"))
		H.teleport(p, 9999, 3, 9999)
		H.client(p, "Hit", "cotton")
		H.advance(0.3)
		-- 월드 2 물건 (월드 1 만 열림): 그 물건 앞에 서 있어도 무시
		H.teleport(p, H.targetSpot("mall"))
		H.client(p, "Hit", "mall")
		T.eq(count(H.sent(p, "HitResult")), 0)
		T.eq(data.money, 0)
		H.uninstall()
	end)

	T.test("물건 체력은 플레이어마다 따로", function()
		local H = setup()
		local glass = H.Targets.get("glass")
		local a, sa = join(H, 1, { power = glass.recommendPower })
		local b, sb = join(H, 2, { power = glass.recommendPower })
		H.teleport(a, H.targetSpot("glass"))
		H.teleport(b, H.targetSpot("glass"))
		H.client(a, "Hit", "glass")
		H.client(a, "Hit", "glass")
		T.eq(sa.targetHp.glass, glass.hp - 2 * glass.recommendPower, "A")
		T.eq(sb.targetHp.glass, nil, "B 는 가득")
		H.client(b, "Hit", "glass")
		T.eq(H.sent(b, "HitResult")[1][1].hp, glass.hp - glass.recommendPower, "B 는 B 만큼")
		H.uninstall()
	end)

	T.test("치기 속도 제한 초당 5번 (한꺼번에 30번 → 5번만 판정)", function()
		local H = setup()
		local p, _, data = join(H, 1, { power = 1e9 })
		H.teleport(p, H.targetSpot("cotton"))
		for _ = 1, 30 do
			H.client(p, "Hit", "cotton")
		end
		T.eq(data.broken.cotton, 5)
		H.uninstall()
	end)

	T.test("돈 1e60 에서 멈춤 · NaN 힘이면 피해 0", function()
		local H = setup()
		local p, _, data = join(H, 1, { power = 1e50, money = 1e60, belt = H.Belts.COUNT, world = 3 })
		H.teleport(p, H.targetSpot("cotton"))
		H.client(p, "Hit", "cotton")
		T.eq(data.money, 1e60)
		data.power = 0 / 0
		H.advance(1)
		H.client(p, "Hit", "cotton")
		local list = H.sent(p, "HitResult")
		T.eq(list[#list][1].damage, 0, "NaN 힘 → 피해 0")
		T.eq(data.money, 1e60)
		H.uninstall()
	end)

	T.suite("services: 아령 사기 · 월드 이동 · 설정")

	T.test("BuyDumbbell: 순서대로 하나씩, 돈이 모자라면 안 됨", function()
		local H = setup()
		local p, _, data = join(H, 1, { money = 0 })
		H.client(p, "BuyDumbbell")
		T.eq(data.dumbbellLevel, 1, "돈 0")
		T.truthy(H.hasNotify(p, "error", "돈 부족"))
		data.money = 1e60
		H.advance(1)
		H.client(p, "BuyDumbbell")
		T.eq(data.dumbbellLevel, 2, "다음 하나만")
		T.eq(data.money, 1e60 - H.Dumbbells.get(2).price)
		T.eq(p:GetAttribute("DumbbellLevel"), 2)
		data.dumbbellLevel = H.Dumbbells.COUNT
		H.advance(1)
		H.client(p, "BuyDumbbell")
		T.eq(data.dumbbellLevel, H.Dumbbells.COUNT, "끝")
		H.uninstall()
	end)

	T.test("Travel: 열린 월드만 · 이상한 인자 무시 · 서버가 스폰으로 옮김", function()
		local H = setup()
		local p, session = join(H, 1, { belt = 3, world = 1 })
		H.client(p, "Travel", 2)
		T.eq(session.currentWorld, 1, "닫힌 월드")
		T.truthy(H.hasNotify(p, "error", "잠김"))
		for _, bad in { 0, 4, 1.5, 0 / 0, math.huge, "2", nil } do
			H.advance(1)
			H.client(p, "Travel", bad)
			T.eq(session.currentWorld, 1, "이상한 값 " .. tostring(bad))
		end
		local _, data = H.server("Sessions").getLoaded(p)
		data.belt = H.Belts.duelOf(1).index
		data.world = 2
		H.advance(1)
		H.client(p, "Travel", 2)
		T.eq(session.currentWorld, 2)
		T.eq(p:GetAttribute("CurrentWorld"), 2)
		local sx, _, sz = H.spawnSpot(2)
		T.eq(p.Character.root.Position.X, sx, "스폰 x")
		T.eq(p.Character.root.Position.Z, sz, "스폰 z")
		H.uninstall()
	end)

	T.test("월드 2 에 가면 월드 2 수련 매트에서만 듦 · 월드 2 물건도 침", function()
		local H = setup()
		local mall = H.Targets.get("mall")
		local p, session, data =
			join(H, 1, { belt = H.Belts.duelOf(1).index, world = 2, power = mall.hp, dumbbellLevel = 12 })
		H.client(p, "Travel", 2)
		H.teleport(p, H.matSpot(1))
		H.advance(1)
		H.client(p, "Train")
		T.eq(data.power, mall.hp, "월드 1 매트 = 안 됨 (지금 월드 2)")
		H.teleport(p, H.matSpot(2))
		H.client(p, "Train")
		T.truthy(data.power > mall.hp, "월드 2 매트")
		H.teleport(p, H.targetSpot("mall"))
		H.client(p, "Hit", "mall")
		T.eq(data.broken.mall, 1)
		T.eq(session.currentWorld, 2)
		H.uninstall()
	end)

	T.test("SetSetting: 아는 키 + boolean 만", function()
		local H = setup()
		local p, _, data = join(H, 1)
		H.client(p, "SetSetting", "music", false)
		T.eq(data.settings.music, false)
		H.client(p, "SetSetting", "music", "no")
		H.client(p, "SetSetting", "hack", true)
		H.client(p, "SetSetting", 5, true)
		T.eq(data.settings.music, false)
		T.eq(data.settings.hack, nil)
		H.uninstall()
	end)

	T.test("ClientReady → Snapshot (모양)", function()
		local H = setup()
		local p = join(H, 1, { power = 7, money = 9, belt = 4, world = 2 })
		H.client(p, "ClientReady")
		local snap = H.sent(p, "Snapshot")[1][1]
		T.eq(snap.power, 7)
		T.eq(snap.money, 9)
		T.eq(snap.belt, 4)
		T.eq(snap.world, 2)
		T.eq(snap.activity, "")
		T.eq(type(snap.broken), "table")
		T.eq(type(snap.ownedPasses), "table")
		H.uninstall()
	end)

	T.suite("services: 로벅스 게임패스 (ProductService)")

	T.test("/buy 순서: power_8 을 먼저 받아도 4배까지만 · 2 → 4 → 8 차례로", function()
		local H = setup()
		local p, _, data = join(H, 1)
		H.S.Product.grant(p, "power_8", "dev")
		T.eq(data.powerBoost, 4, "8 R$ 로 2·4 까지")
		H.S.Product.grant(p, "power_8", "dev")
		T.eq(data.powerBoost, 8)
		T.eq(p:GetAttribute("PowerBoost"), 8)
		T.eq(count(H.sent(p, "ProductGranted")), 2)
		H.S.Product.grant(p, "money_2", "dev")
		T.truthy(data.moneyPass)
		T.eq(p:GetAttribute("MoneyPass"), true)
		T.falsy(H.S.Product.grant(p, "nope", "dev"))
		H.uninstall()
	end)

	T.test(
		"syncPasses: id 가 붙으면 소유 확인으로 (웹에서 건너뛰어 산 것은 낸 값만큼, 절대 낮추지 않음)",
		function()
			local H = setup()
			local Products = H.shared("Data/Products")
			-- 시험용 id 붙이기 (진짜 표는 0)
			for i, prod in Products.powerBoosts do
				prod.productId = 9000 + i
			end
			local p, session, data = join(H, 1)
			H.market.owned[1] = { [9000 + 3] = true } -- power_8 만 (8 R$)
			H.run(function()
				return H.S.Product.syncPasses(p)
			end)
			T.eq(data.powerBoost, 4, "8 R$ → 4배")
			T.truthy(session.ownedPasses.power_8)
			H.market.owned[1] = {}
			H.run(function()
				return H.S.Product.syncPasses(p)
			end)
			T.eq(data.powerBoost, 4, "확인에 없어도 낮추지 않음")
			for _, prod in Products.powerBoosts do
				prod.productId = 0
			end
			H.uninstall()
		end
	)

	T.test(
		"ProcessReceipt: 개발자 상품이 없으니 모르는 상품 = NotProcessedYet (지급 없음)",
		function()
			local H = setup()
			local p, _, data = join(H, 1)
			local decision = H.run(function()
				return H.S.Product.processReceipt({ PlayerId = 1, ProductId = 123, PurchaseId = "r1" })
			end)
			T.eq(decision, "ProductPurchaseDecision.NotProcessedYet")
			T.eq(#data.receipts, 0)
			T.eq(data.powerBoost, 1)
			H.uninstall()
		end
	)

	T.suite("services: 개발 명령 · 순위")

	T.test("/power /money /belt /world /dumbbell /buy /unbuy /reset", function()
		local H = setup()
		local p, session, data = join(H, 1)
		T.truthy(H.S.Dev.handle(p, "/power 1e9"))
		T.eq(data.power, 1e9)
		H.S.Dev.handle(p, "/money 5e5")
		T.eq(data.money, 5e5)
		local D1, D2 = H.Belts.duelOf(1).index, H.Belts.duelOf(2).index
		H.S.Dev.handle(p, "/belt " .. D2)
		T.eq(data.belt, D2)
		T.eq(data.world, 3, "월드 2 대결 띠(무지개) → 월드 3 열림")
		H.S.Dev.handle(p, "/belt " .. D2 - 1)
		T.eq(data.world, 2, "한 칸 아래 → 월드 2")
		H.S.Dev.handle(p, "/belt 2")
		T.eq(data.world, 1, "띠를 내리면 월드도")
		H.S.Dev.handle(p, "/world 2")
		T.eq(data.belt, D1, "월드 2 를 여는 띠 (월드 1 대결 띠)")
		T.eq(data.world, 2)
		T.eq(session.currentWorld, 2)
		H.S.Dev.handle(p, "/dumbbell 20")
		T.eq(data.dumbbellLevel, 20)
		H.S.Dev.handle(p, "/buy power_2")
		T.eq(data.powerBoost, 2)
		H.S.Dev.handle(p, "/unbuy")
		T.eq(data.powerBoost, 1)
		H.S.Dev.handle(p, "/power nan")
		H.S.Dev.handle(p, "/belt " .. H.Belts.COUNT + 1)
		H.S.Dev.handle(p, "/world 0")
		T.eq(data.power, 1e9, "NaN 무시")
		T.eq(data.belt, D1, "마지막 띠 다음 번호 무시")
		T.truthy(H.hasNotify(p, "error", "/belt <1~" .. H.Belts.COUNT .. ">"), "도움말에 띠 개수")
		H.S.Dev.handle(p, "/reset")
		T.eq(data.power, 0)
		T.eq(data.belt, 1)
		T.eq(data.world, 1)
		T.eq(session.currentWorld, 1)
		H.RunService.studio = false
		T.falsy(H.S.Dev.handle(p, "/power 5"), "실서버(스튜디오 아님) = 안 됨")
		T.eq(data.power, 0)
		H.uninstall()
	end)

	T.test("순위: 힘·돈 큰 사람부터 상위 10명", function()
		local H = setup()
		for i = 1, 12 do
			join(H, i, { power = i * 10, money = 100 - i })
		end
		local board = H.S.Leader.build()
		T.eq(#board.power, 10)
		T.eq(board.power[1].value, 120)
		T.eq(board.money[1].value, 99)
		H.uninstall()
	end)
end
