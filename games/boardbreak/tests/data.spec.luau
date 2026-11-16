--!nocheck
-- 데이터 표 무결성: 물건 41 · 아령 (Dumbbells.COUNT) · 띠 12 · 월드 3 · 게임패스 12 (설계서 3·4·5·6장)
return function(T, Loader)
	local Targets = Loader.require("ReplicatedStorage/Shared/Data/Targets")
	local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")
	local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")
	local Worlds = Loader.require("ReplicatedStorage/Shared/Data/Worlds")
	local Products = Loader.require("ReplicatedStorage/Shared/Data/Products")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")

	T.suite("data: 물건 41개")

	T.test("41개 · 월드 1 = 13 · 월드 2 = 14 · 월드 3 = 14 · index 1~41 순서", function()
		T.eq(Targets.COUNT, 41, "물건 수")
		T.eq(#Targets.byWorld(1), 13, "월드 1")
		T.eq(#Targets.byWorld(2), 14, "월드 2")
		T.eq(#Targets.byWorld(3), 14, "월드 3")
		T.eq(#Targets.byWorld(4), 0, "없는 월드")
		for i, t in Targets.list do
			T.eq(t.index, i, t.id .. " index")
			T.eq(Targets.get(t.id), t, t.id .. " get")
			local world = if i <= 13 then 1 elseif i <= 27 then 2 else 3
			T.eq(t.world, world, t.id .. " 월드")
		end
		T.eq(Targets.get("nope"), nil, "없는 id")
		T.eq(Targets.get(nil :: any), nil, "nil id")
	end)

	T.test("물건값 = 사장님 새 표 (2026-11-16 다시 정함: 솜 3 에서 이웃 5~10배)", function()
		-- 3 → 20 → 150 → 1,000 → 8,000 → 50,000 → 400,000 → 다시 3M … (설계서 3장)
		local pattern = { 3, 20, 150, 1000, 8000, 50000, 400000 }
		for i, t in Targets.list do
			local k = (i - 1) % 7
			local expected = pattern[k + 1] * 1e6 ^ ((i - 1) // 7)
			T.truthy(math.abs(t.reward - expected) <= expected * 1e-9, t.id .. " 값 " .. t.reward)
		end
		T.eq(Targets.get("cotton").reward, 3, "솜 3")
		T.eq(Targets.get("glass").reward, 20, "유리 20")
		T.eq(Targets.get("apartment").reward, 1e9, "아파트 1B")
		T.eq(Targets.get("universe").reward, 5e34, "우주 = 50Dc")
		for i = 2, Targets.COUNT do
			local r = Targets.list[i].reward / Targets.list[i - 1].reward
			T.truthy(r >= 5 and r <= 10, Targets.list[i].id .. " 이웃 reward 배율 " .. r)
		end
	end)

	T.test("추천 힘·hp: 이웃 5~10배 · hp 배율 ≥ reward 배율 (뒤 물건 지름길 없음)", function()
		for i = 2, Targets.COUNT do
			local a, b = Targets.list[i - 1], Targets.list[i]
			local rp, rh, rr = b.recommendPower / a.recommendPower, b.hp / a.hp, b.reward / a.reward
			T.truthy(rp >= 5 and rp <= 10, b.id .. " 추천 힘 배율 " .. rp)
			T.truthy(rh >= 5 and rh <= 10, b.id .. " hp 배율 " .. rh)
			T.truthy(rh >= rr, b.id .. " hp 배율 ≥ reward 배율")
		end
		for _, t in Targets.list do
			T.eq(t.minPower, nil, t.id .. " 옛 이름 minPower 없음")
		end
	end)

	T.test("값·추천 힘·hp 모두 단조 증가, 유한한 양수", function()
		for i, t in Targets.list do
			for _, key in { "reward", "recommendPower", "hp" } do
				local v = t[key]
				T.truthy(type(v) == "number" and v == v and v > 0 and v < math.huge, t.id .. " " .. key)
			end
			if i > 1 then
				local prev = Targets.list[i - 1]
				T.truthy(t.reward > prev.reward, t.id .. " reward 증가")
				T.truthy(t.recommendPower > prev.recommendPower, t.id .. " 추천 힘 증가")
				T.truthy(t.hp > prev.hp, t.id .. " hp 증가")
			end
		end
	end)

	T.test("추천 힘이면 15~30번 · 편해진 힘(3번) < 다음 물건 추천 힘", function()
		for i, t in Targets.list do
			local hits = Economy.hitsToBreak(t.hp, t.recommendPower)
			T.truthy(hits >= 15 and hits <= 30, t.id .. " 처음 타격 " .. hits)
			if i < Targets.COUNT then
				T.truthy(t.hp / 3 < Targets.list[i + 1].recommendPower, t.id .. " 편해진 뒤에 다음이 열림")
			end
		end
	end)

	T.suite("data: 아령 (사장님 결정 9번)")

	T.test(
		"#list 개 · 1번은 공짜 · 사장님 숫자 (1kg 1 · 3kg 3 · 5kg 10 · 10kg 25 · 25kg 100, 3kg 42) · 힘/번·값·weightKg 단조 증가",
		function()
			T.eq(Dumbbells.COUNT, #Dumbbells.list, "아령 수 = 표 길이")
			T.truthy(Dumbbells.COUNT >= 40 and Dumbbells.COUNT <= 80, "아령 수 " .. Dumbbells.COUNT)
			T.eq(Dumbbells.list[1].price, 0, "1kg 아령 공짜")
			T.eq(Dumbbells.list[1].powerPerRep, 1, "1kg 아령 1")
			local boss = {
				{ "1kg 아령", 1 },
				{ "3kg 아령", 3 },
				{ "5kg 아령", 10 },
				{ "10kg 아령", 25 },
				{ "25kg 아령", 100 },
			}
			for i, b in boss do
				T.eq(Dumbbells.list[i].name, b[1], "이름 " .. i)
				T.eq(Dumbbells.list[i].powerPerRep, b[2], b[1] .. " 힘")
			end
			T.eq(Dumbbells.list[2].price, 42, "3kg 아령 42")
			for i, d in Dumbbells.list do
				T.truthy(type(d.name) == "string" and #d.name > 0, "이름 " .. i)
				T.truthy(type(d.weightKg) == "number" and d.weightKg > 0, d.id .. " weightKg")
				if i > 1 then
					T.truthy(d.weightKg > Dumbbells.list[i - 1].weightKg, d.id .. " weightKg 증가")
					local r = d.powerPerRep / Dumbbells.list[i - 1].powerPerRep
					T.truthy(r >= 2 and r <= 5 + 1e-9, d.id .. " 힘/번 배율 완만 " .. r)
				end
			end
			for i, d in Dumbbells.list do
				T.eq(d.level, i, d.id .. " level")
				T.eq(Dumbbells.get(i), d, "get")
				T.eq(Dumbbells.byId(d.id), d, "byId")
				if i > 1 then
					T.truthy(d.powerPerRep > Dumbbells.list[i - 1].powerPerRep, d.id .. " 힘 증가")
					T.truthy(d.price > Dumbbells.list[i - 1].price, d.id .. " 값 증가")
				end
			end
			T.eq(Dumbbells.get(0), nil, "0")
			T.eq(Dumbbells.get(Dumbbells.COUNT + 1), nil, "끝 다음")
			T.eq(Dumbbells.get(1.5), nil, "소수")
			T.eq(Dumbbells.get(0 / 0), nil, "NaN")
		end
	)

	T.suite("data: 띠 12개 · 월드 3개")

	T.test("12개 · 월드마다 4개 · 4·8·12 = 대결 · 배율·needPower 증가", function()
		T.eq(Belts.COUNT, 12, "띠 수")
		local names = {
			"흰",
			"노랑",
			"초록",
			"파랑",
			"보라",
			"갈색",
			"빨강",
			"검정",
			"1단",
			"3단",
			"6단",
			"9단",
		}
		for i, b in Belts.list do
			T.eq(b.index, i, "index")
			T.eq(b.world, math.ceil(i / 4), b.id .. " 월드")
			T.eq(b.duel, i % 4 == 0, b.id .. " 대결")
			T.truthy(string.find(b.name, names[i], 1, true) ~= nil, b.id .. " 이름 " .. b.name)
			if i > 1 then
				T.truthy(b.moneyMultiplier > Belts.list[i - 1].moneyMultiplier, b.id .. " 배율 증가")
				T.truthy(b.needPower > Belts.list[i - 1].needPower, b.id .. " needPower 증가")
			end
			if b.duel then
				T.eq(b.examBoardHp, 0, "대결 띠 심사 송판 없음")
				T.eq(b.duelBoardHp, b.needPower * Belts.DUEL_HITS_AT_NEED, "대결 송판")
			elseif i > 1 then
				T.eq(b.examBoardHp, b.needPower * Belts.EXAM_HITS_AT_NEED, "심사 송판")
			end
		end
		T.eq(Belts.list[1].needPower, 0, "흰 띠는 처음부터")
		T.eq(Belts.list[1].moneyMultiplier, 1, "흰 띠 배율 1")
	end)

	T.test("월드 3개: 물건 범위·시험관·대결 송판", function()
		T.eq(Worlds.COUNT, 3, "월드 수")
		local ranges = { { 1, 13 }, { 14, 27 }, { 28, 41 } }
		for i, w in Worlds.list do
			T.eq(w.index, i, "index")
			T.eq(w.firstTarget, ranges[i][1], "첫 물건")
			T.eq(w.lastTarget, ranges[i][2], "마지막 물건")
			T.truthy(type(w.examiner) == "string" and #w.examiner > 0, "시험관 이름")
			T.truthy(w.examinerSecondsPerBoard > 0, "시험관 속도")
			T.eq(w.duelBoardHp, Belts.get(i * 4).duelBoardHp, "대결 송판 = 대결 띠")
			T.eq(#w.color, 3, "테마색")
		end
		T.eq(Worlds.get(4), nil, "없는 월드")
		T.eq(Worlds.get(0 / 0), nil, "NaN 월드")
	end)

	T.test(
		"대결 띠 추천 힘 ≥ 그 월드 마지막 물건 추천 힘 (시험관을 넉넉히 이길 힘 = 마지막 물건을 깨는 힘)",
		function()
			for _, w in Worlds.list do
				T.truthy(
					Belts.get(w.index * 4).needPower >= Targets.list[w.lastTarget].recommendPower,
					"월드 " .. w.index
				)
			end
		end
	)

	T.suite("data: 게임패스 12개 · Config")

	T.test("power_2 … power_2048 (11) + money_2 = 12, 전부 게임패스, id 0", function()
		T.eq(#Products.passes, 12, "패스 수")
		T.eq(#Products.list, 12, "상품 수")
		local m = 2
		for i, p in Products.powerBoosts do
			T.eq(p.key, "power_" .. m, "key " .. i)
			T.eq(p.value, m, "배수")
			T.eq(p.robux, m, "가격 = 배수")
			T.eq(p.kind, "powerBoost", "kind")
			m *= 2
		end
		T.eq(#Products.powerBoosts, 11, "힘 배수 11개")
		local money = Products.get("money_2")
		T.eq(money.robux, 199, "돈 2배 199")
		T.eq(money.kind, "moneyPass", "kind")
		for _, p in Products.list do
			T.eq(p.isPass, true, p.key .. " 게임패스")
			T.eq(p.productId, 0, p.key .. " id 0")
			T.eq(Products.isConfigured(p), false, p.key .. " 준비 중")
		end
	end)

	T.test("Config: 상한 1e60 · 심사 10장 20초 · 대결 15장 · DataStore 이름", function()
		T.eq(Config.POWER_MAX, 1e60, "힘 상한")
		T.eq(Config.MONEY_MAX, 1e60, "돈 상한")
		T.eq(Config.EXAM_BOARDS, 10, "심사 송판")
		T.eq(Config.EXAM_SECONDS, 20, "심사 시간")
		T.eq(Config.DUEL_BOARDS, 15, "대결 송판")
		T.eq(Config.DATASTORE_NAME, "BoardBreak_PlayerData", "DataStore 이름")
		T.eq(Config.SCHEMA_VERSION, 1, "스키마 1")
		T.truthy(Config.AUTO_REPEAT_SECONDS >= 0.2, "자동 반복이 서버 한도(초당 5번)보다 느림")
	end)

	T.test(
		"MapLayout: 물건 41개 모두 자리·닿는 거리가 있음 (선임 MapLayout 과 Targets id 가 같음)",
		function()
			local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
			for _, t in Targets.list do
				local p = MapLayout.targetPosition(t.id)
				T.truthy(p ~= nil and type(p.x) == "number", t.id .. " 자리")
				T.truthy(MapLayout.targetReach(t.id) > 0, t.id .. " 닿는 거리")
			end
			T.eq(MapLayout.targetPosition("nope"), nil, "없는 id")
			for w = 1, 3 do
				T.truthy(MapLayout.spawn(w) ~= nil, "스폰 " .. w)
				T.truthy(MapLayout.examPad(w) ~= nil, "심사대 " .. w)
				T.truthy(MapLayout.duelArena(w) ~= nil, "대결장 " .. w)
			end
		end
	)
end
