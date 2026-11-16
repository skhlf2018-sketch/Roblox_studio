--!nocheck
--[[
	holes_v2 — 주임의 "구멍 찾기" (2판 검수 — 사장님 결정 9·10·11번이 들어온 뒤 바뀐 것만). 진짜 서버 코드 + ServerHarness.
	src 는 고치지 않음 — 버그는 T.skip(이유) 으로 남김. 번호(B-n)는 docs/TEST_REPORT.md "2판 검수 (B 시리즈)" 와 같음.
	  A 지름길 (문턱 없는 월드에서 먼 물건만 치기 · 두 손가락)   B 물건 체력 기억 (세션 표)
	  C 힘 0 으로 심사·대결 무한 반복                           D 아령 60개 (구매 · 값 표 · 사는 시간)
	  E 아우라 서비스 (진짜 @lune/roblox 인스턴스)               F 아슬아슬한 숫자 (sim 흔들어 보기 · 합격선)
	  G 1판 A-1 ~ A-4 다시 확인 + 길가 매트 41칸
]]
return function(T, Loader)
	local ServerHarness = require("./ServerHarness")
	local SimPlayer = require("./SimPlayer")
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox")

	local GAME_DIR = if fs.isFile("games/boardbreak/default.project.json") then "games/boardbreak" else "."

	local function setup()
		local H = ServerHarness.install(Loader, T)
		H.startNet()
		local S = {
			Train = H.server("Services/TrainService"),
			Break = H.server("Services/BreakService"),
			Shop = H.server("Services/ShopService"),
			World = H.server("Services/WorldService"),
			Exam = H.server("Services/ExamService"),
			Life = H.server("Services/PlayerLifecycle"),
			Sessions = H.server("Sessions"),
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
		H.Config = H.shared("Data/Config")
		H.Economy = H.shared("Economy")
		return H
	end

	local function at(x, y, z)
		return { x, y, z }
	end

	-- 로그인 + 캐릭터 (spot 기본: 월드 매트)
	local function join(H, userId, overrides, spot)
		local p = H.newPlayer(userId)
		local session, data = H.login(p, overrides)
		if spot then
			H.spawn(p, spot[1], spot[2], spot[3])
		else
			H.spawn(p, H.matSpot(session.currentWorld))
		end
		return p, session, data
	end

	local function countKeys(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	-- 진짜 숫자 표·규칙 (서버 없이)
	local function pure()
		Loader.clearFakes()
		local function sh(path)
			return Loader.require("ReplicatedStorage/Shared/" .. path)
		end
		return {
			Targets = sh("Data/Targets"),
			Dumbbells = sh("Data/Dumbbells"),
			Belts = sh("Data/Belts"),
			Worlds = sh("Data/Worlds"),
			Config = sh("Data/Config"),
			MapLayout = sh("Data/MapLayout"),
			Economy = sh("Economy"),
			Progression = sh("Progression"),
			ExamRules = sh("ExamRules"),
			Format = sh("Format"),
		}
	end

	local function mmss(seconds)
		if not seconds then
			return "-"
		end
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end

	------------------------------------------------------------------
	T.suite("holes_v2 A: 지름길 (문턱 없는 월드에서 먼 물건만 치기 · 두 손가락)")
	------------------------------------------------------------------

	-- 이 힘(d)으로 칠 때 "지금 힘에 맞는 물건"(추천 힘 ≤ d 중 가장 뒤, 열린 월드 안) 대비
	--   바로 다음 물건 · 두 칸 이상 뒤 물건의 (돈/타격수) 배율 최대. 맞는 물건이 없으면 nil
	local function laterRatios(m, d, world)
		local fit = nil
		for _, t in m.Targets.list do
			if t.world <= world and d >= t.recommendPower then
				fit = t
			end
		end
		if not fit then
			return nil
		end
		local fitRate = fit.reward / m.Economy.hitsToBreak(fit.hp, d)
		local nextRatio, farRatio, farId = 0, 0, ""
		for _, t in m.Targets.list do
			if t.world <= world and t.index > fit.index then
				local r = (t.reward / m.Economy.hitsToBreak(t.hp, d)) / fitRate
				if t.index == fit.index + 1 then
					nextRatio = math.max(nextRatio, r)
				elseif r > farRatio then
					farRatio, farId = r, t.id
				end
			end
		end
		return nextRatio, farRatio, fit, farId
	end

	local SHORTCUT_NEXT_MAX = 1.5 -- 바로 다음 물건: 추천 힘의 0.7~1배일 때 더 좋은 것은 정상 진행 (지금 1.41)
	local SHORTCUT_FAR_MAX = 1.3 -- 두 칸 이상 뒤: 1.3배 넘으면 지름길 (지금 1.10)

	T.test(
		"대표 시점 24곳 (sim 이 띠 승급·아령 5의 배수를 산 때): 뒤 물건이 지금 힘에 맞는 물건의 1.3배를 못 넘음",
		function()
			local m = pure()
			local snaps, lastBelt, lastDb = {}, 1, 0
			SimPlayer.run(m, {
				onStep = function(s)
					local mark = nil
					if s.belt ~= lastBelt then
						mark = "띠" .. s.belt
						lastBelt = s.belt
					end
					if s.db ~= lastDb and (s.db % 5 == 0 or s.db == 1) then
						mark = (mark or "") .. " 아령" .. s.db
					end
					lastDb = s.db
					if mark then
						table.insert(snaps, { mark = mark, power = s.power, world = s.world })
					end
				end,
			})
			T.truthy(#snaps >= 20, "대표 시점이 20곳 이상 (" .. #snaps .. ")")
			local worstNext, worstFar, worstMark = 0, 0, ""
			local usable = 0
			for _, sn in snaps do
				local nextRatio, farRatio, _, farId = laterRatios(m, m.Economy.hitDamage(sn.power, 1), sn.world)
				if nextRatio then
					usable += 1
					worstNext = math.max(worstNext, nextRatio)
					if farRatio > worstFar then
						worstFar, worstMark = farRatio, sn.mark .. " " .. farId
					end
				end
			end
			T.truthy(usable >= 20, "힘이 있는 시점 20곳 이상 (" .. usable .. ")")
			print(
				string.format(
					"  (시점 %d곳: 바로 다음 물건 최대 %.2f배 · 두 칸 넘게 뒤 최대 %.2f배 %s)",
					usable,
					worstNext,
					worstFar,
					worstMark
				)
			)
			T.truthy(worstNext <= SHORTCUT_NEXT_MAX, "바로 다음 물건 " .. worstNext)
			T.truthy(worstFar <= SHORTCUT_FAR_MAX, "두 칸 넘게 뒤 " .. worstFar .. " @ " .. worstMark)
		end
	)

	T.test(
		"힘 1 ~ 1e41 을 0.3% 씩 훑어도 (월드 상관없이 41개 전부): 두 칸 넘게 뒤 ≤ 1.3배 · 바로 다음 ≤ 1.5배",
		function()
			local m = pure()
			local worstNext, worstFar, atNext, atFar, idFar = 0, 0, 0, 0, ""
			local d = 1
			while d < 1e41 do
				local nextRatio, farRatio, _, farId = laterRatios(m, d, 3)
				if nextRatio then
					if nextRatio > worstNext then
						worstNext, atNext = nextRatio, d
					end
					if farRatio > worstFar then
						worstFar, atFar, idFar = farRatio, d, farId
					end
				end
				d *= 1.003
			end
			print(
				string.format(
					"  (바로 다음 물건 최대 %.2f배 @ 힘 %s · 두 칸 넘게 뒤 최대 %.2f배 @ 힘 %s %s)",
					worstNext,
					m.Format.number(atNext),
					worstFar,
					m.Format.number(atFar),
					idFar
				)
			)
			T.truthy(worstFar <= SHORTCUT_FAR_MAX, "두 칸 넘게 뒤 " .. worstFar)
			T.truthy(worstNext <= SHORTCUT_NEXT_MAX, "바로 다음 " .. worstNext)
		end
	)

	T.test(
		"sim 플레이어는 열린 월드의 물건 전부 중 돈이 가장 빠른 것을 침 = 지름길이 있었다면 이미 탔고, 그래도 월드 끝 시간이 목표 안",
		function()
			local m = pure()
			local _, log = SimPlayer.run(m)
			local ends = { log.worldOpen[2], log.worldOpen[3], log.belt[m.Belts.COUNT] }
			local bands = SimPlayer.WORLD_END -- sim_progress RULES.worldEnd (결정 13·14·16번 뒤 ±30%)
			for w = 1, 3 do
				T.truthy(ends[w] ~= nil, "월드 " .. w .. " 끝 있음")
				T.truthy(ends[w] >= bands[w][1] and ends[w] <= bands[w][2], "월드 " .. w .. " 끝 " .. mmss(ends[w]))
			end
			-- 아래쪽 한도(월드 3 끝 하한)까지 얼마나 남았나 — 지름길이 있으면 이 여유가 줄어듦
			T.truthy(
				ends[3] - bands[3][1] >= 600,
				"월드 3 끝이 하한 " .. mmss(bands[3][1]) .. " 에서 10분 이상 위 (" .. mmss(ends[3]) .. ")"
			)
		end
	)

	T.test(
		"길가 매트에서 들기와 치기를 동시에 (두 손가락): 서버 한도로 각각 초당 5번 — 한 손가락의 딱 2배, sim(초당 2+2)의 2.5배",
		function()
			local H = setup()
			local ML = H.MapLayout
			local mp = ML.matPoint("glass")
			local p, _, data = join(H, 1, { power = 1000 }, at(mp.x, mp.y + 3, mp.z))
			local trains, hits = 0, 0
			for _ = 1, 300 do -- 60초, 0.2초마다 두 Remote 를 같이
				H.client(p, "Train")
				H.client(p, "Hit", "glass")
				H.advance(0.2)
			end
			trains, hits = #H.sent(p, "TrainResult"), #H.sent(p, "HitResult")
			print(
				string.format(
					"  (60초: 들기 %d번 · 치기 %d번 — sim 은 60초에 들기 120 + 치기 120 → 들기 %.2f배 · 치기 %.2f배)",
					trains,
					hits,
					trains / 120,
					hits / 120
				)
			)
			T.truthy(trains >= 290 and trains <= 306, "들기 5+5T = 305 안쪽 " .. trains)
			T.truthy(hits >= 290 and hits <= 306, "치기 5+5T = 305 안쪽 " .. hits)
			T.truthy(data.power > 1000, "매트 위에서 힘도 오름")
			T.truthy(data.money > 0, "같은 매트에서 치기도 됨 (돈 " .. data.money .. ")")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v2 B: 물건 체력 기억 (세션 표 targetHp)")
	------------------------------------------------------------------

	T.test(
		"표는 최대 41칸: 쓰레기 id 5,000번 + 41개 전부 한 번씩 친 뒤에도 키는 Targets id 만 · 0 < 체력 ≤ 가득",
		function()
			local H = setup()
			local rng = T.rng(7)
			local p, session = join(H, 1, { power = 2, world = 3 }, at(H.targetSpot("cotton")))
			local junk = { "", "exam", "duel", "x", "../a", string.rep("a", 49), "cotton ", "COTTON", "glass\0", "t-1" }
			for i = 1, 5000 do
				local id = if i % 3 == 0 then junk[1 + math.floor(rng() * #junk)] else "obj" .. math.floor(rng() * 1e6)
				H.S.Break.hit(p, id)
			end
			T.eq(countKeys(session.targetHp), 0, "쓰레기 id 로는 표가 안 늘어남")
			for _, t in H.Targets.list do
				H.teleport(p, H.targetSpot(t.id))
				T.truthy(H.S.Break.hit(p, t.id), t.id .. " 침")
			end
			T.eq(countKeys(session.targetHp), 41, "정확히 41칸")
			for id, hp in session.targetHp do
				local target = H.Targets.get(id)
				T.truthy(target, "표의 키가 물건 id: " .. tostring(id))
				T.truthy(type(hp) == "number" and hp > 0 and hp <= target.hp, id .. " 체력 범위 " .. tostring(hp))
			end
			for _ = 1, 3000 do
				H.S.Break.hit(p, "obj1")
				H.S.Break.hit(p, "exam") -- 심사 중이 아님
				H.S.Break.hit(p, "duel")
			end
			T.eq(countKeys(session.targetHp), 41, "심사·대결 치기가 표에 안 들어감")
			T.eq(#H.warnings, 0)
			H.uninstall()
		end
	)

	T.test(
		"깎인 체력은 월드 이동 · 죽음(새 캐릭터) · 심사 시작 · 설정 연타 뒤에도 그대로, 이어서 치면 남은 만큼만 더 침",
		function()
			local H = setup()
			local p, session, data = join(H, 1, { power = 20, world = 2 }, at(H.targetSpot("cotton")))
			local hp0 = H.Targets.get("cotton").hp -- 71
			H.S.Break.hit(p, "cotton")
			H.S.Break.hit(p, "cotton")
			T.eq(session.targetHp.cotton, hp0 - 40)
			H.client(p, "Travel", 2)
			T.eq(session.currentWorld, 2)
			T.eq(session.targetHp.cotton, hp0 - 40, "월드 2 에 가도")
			H.advance(2)
			H.client(p, "Travel", 1)
			T.eq(session.currentWorld, 1)
			T.eq(session.targetHp.cotton, hp0 - 40, "다시 월드 1")
			H.advance(1)
			H.spawn(p, H.spawnSpot(1)) -- 죽었다 다시 태어남 (새 캐릭터)
			H.advance(1)
			T.eq(session.targetHp.cotton, hp0 - 40, "새 캐릭터")
			H.teleport(p, H.examSpot(1))
			H.client(p, "StartExam")
			T.truthy(session.exam, "심사 시작됨")
			T.eq(session.targetHp.cotton, hp0 - 40, "심사 시작")
			H.advance(25) -- 힘 20 으로는 불합격
			T.eq(session.exam, nil)
			T.eq(session.targetHp.cotton, hp0 - 40, "심사가 끝나도")
			T.eq(data.belt, 1)
			H.teleport(p, H.targetSpot("cotton"))
			local r3 = H.S.Break.hit(p, "cotton")
			T.eq(r3.hp, 11)
			T.falsy(r3.broken)
			local r4 = H.S.Break.hit(p, "cotton")
			T.truthy(r4.broken, "남은 11 만 필요 → 네 번째에 깨짐")
			T.eq(r4.damage, 11, "넘친 피해는 버림 — 11 만 깎음")
			T.eq(r4.reward, H.Targets.get("cotton").reward)
			T.eq(data.money, H.Targets.get("cotton").reward)
			T.eq(session.targetHp.cotton, nil, "깨지면 다시 가득")
			T.eq(#H.warnings, 0)
			H.uninstall()
		end
	)

	T.test(
		"다른 플레이어 것과 안 섞임: 내가 깎아도 남은 그대로 · 남이 깨도 내 체력·돈·도감은 그대로 · 결과는 친 사람에게만",
		function()
			local H = setup()
			local p1, s1, d1 = join(H, 1, { power = 20 }, at(H.targetSpot("cotton")))
			local p2, s2, d2 = join(H, 2, { power = 20 }, at(H.targetSpot("cotton")))
			H.S.Break.hit(p1, "cotton")
			H.S.Break.hit(p1, "cotton")
			T.eq(s1.targetHp.cotton, 31)
			T.eq(s2.targetHp.cotton, nil, "남은 안 깎임")
			T.truthy(s1.targetHp ~= s2.targetHp, "표가 따로")
			for _ = 1, 4 do
				H.S.Break.hit(p2, "cotton")
			end
			T.eq(d2.money, H.Targets.get("cotton").reward, "p2 만 돈을 받음")
			T.eq(d1.money, 0, "p1 은 그대로")
			T.eq(s1.targetHp.cotton, 31, "p2 가 깨도 p1 체력 그대로")
			T.eq(d1.broken.cotton, nil)
			T.eq(#H.sent(p1, "HitResult"), 2)
			T.eq(#H.sent(p2, "HitResult"), 4)
			-- 같은 userId 를 두 번 로그인하는 일은 없음(세션 락) — 그래도 새 세션은 새 표
			H.leave(p1)
			local p1b, s1b = join(H, 1, { power = 20 }, at(H.targetSpot("cotton")))
			T.eq(s1b.targetHp.cotton, nil, "다시 들어오면 가득 (세션 동안만 기억)")
			T.truthy(p1b ~= nil)
			H.uninstall()
		end
	)

	T.test(
		"깬 직후 한 번 더 온 타격은 새 물건에 정상 적용: 보상은 깨질 때마다 한 번뿐 · 깬 횟수와 돈이 맞음",
		function()
			local H = setup()
			local cotton = H.Targets.get("cotton")
			-- 힘 = 체력의 0.6 → 두 번째에 깨지고 세 번째는 새 물건을 0.6 깎음
			local p, session, data = join(H, 1, { power = cotton.hp * 0.6 }, at(H.targetSpot("cotton")))
			for _ = 1, 3 do
				H.client(p, "Hit", "cotton") -- 같은 순간 연타 (속도 제한 burst 5 안)
			end
			local results = H.sent(p, "HitResult")
			T.eq(#results, 3)
			T.falsy(results[1][1].broken)
			T.truthy(results[2][1].broken)
			T.eq(results[2][1].reward, cotton.reward)
			T.falsy(results[3][1].broken, "세 번째는 새 물건")
			T.eq(results[3][1].reward, nil, "보상 중복 없음")
			T.near(results[3][1].hp, cotton.hp * 0.4, 1e-9, "새 물건이 0.6 깎임")
			T.eq(data.money, H.Targets.get("cotton").reward)
			T.eq(data.broken.cotton, 1)
			T.eq(data.stats.breaks, 1)
			T.eq(data.stats.hits, 3)
			-- 한 방에 깨는 힘이면 칠 때마다 깨지고 칠 때마다 돈 (진짜로 새 물건을 깬 것)
			data.power = 1e6
			H.advance(10)
			for _ = 1, 4 do
				H.S.Break.hit(p, "cotton")
			end
			T.eq(data.money, cotton.reward + 4 * cotton.reward)
			T.eq(data.broken.cotton, 5)
			T.eq(session.targetHp.cotton, nil)
			T.eq(#H.warnings, 0)
			H.uninstall()
		end
	)

	T.test(
		"체력 표가 깨지지 않음: 힘이 0 · 음수 · NaN · inf · 1e308 · 아주 작은 수여도 체력은 (0, 가득] 안 · 돈은 유한 · warn 0",
		function()
			local H = setup()
			local rng = T.rng(11)
			local pool = { 0, 0 / 0, -5, math.huge, -math.huge, 1e308, 1e-300, 1, 5, 70.9, 71, 1e60, 3.3 }
			local p, session, data = join(H, 1, { world = 3 }, at(H.targetSpot("cotton")))
			local ids = { "cotton", "glass", "universe", "mall" }
			for i = 1, 3000 do
				local id = ids[1 + math.floor(rng() * #ids)]
				H.teleport(p, H.targetSpot(id))
				data.power = pool[1 + math.floor(rng() * #pool)]
				H.S.Break.hit(p, id)
				if i % 100 == 0 then
					H.advance(1)
				end
				for key, hp in session.targetHp do
					local target = H.Targets.get(key)
					T.truthy(
						type(hp) == "number" and hp == hp and hp > 0 and hp <= target.hp,
						key .. " 체력 " .. tostring(hp)
					)
				end
				T.truthy(
					data.money == data.money and data.money >= 0 and data.money <= 1e60,
					"돈 " .. tostring(data.money)
				)
			end
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"닫힌 월드 · 먼 거리 치기는 표에 흔적도 안 남김 · 열린 월드 안이면 힘 1 이어도 침 (문턱 없음)",
		function()
			local H = setup()
			local p, session = join(H, 1, { power = 1 }, at(H.targetSpot("mall")))
			for _ = 1, 20 do
				H.S.Break.hit(p, "mall") -- 월드 2 물건 · 월드 1 만 열림
			end
			T.eq(countKeys(session.targetHp), 0, "닫힌 월드")
			H.teleport(p, H.targetSpot("cotton"))
			H.S.Break.hit(p, "glass") -- 먼 거리
			T.eq(countKeys(session.targetHp), 0, "먼 거리")
			local r = H.S.Break.hit(p, "cotton")
			T.truthy(r and not r.broken and r.hp == 70, "힘 1 로도 침 (체력 71 → 70)")
			T.eq(countKeys(session.targetHp), 1)
			H.uninstall()
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v2 C: 힘 0 으로 심사 · 대결 무한 반복 (공짜 띠 · 서버 상태 누수)")
	------------------------------------------------------------------

	T.test(
		"힘 0 심사 150번 반복: 띠 · 돈 · 힘 · 월드 그대로 · 불합격 150 · 끝나면 상태·활동 비움 · 끝난 뒤 틱 메시지 0 · warn 0",
		function()
			local H = setup()
			local p, session, data = join(H, 1, { power = 0, money = 0 }, at(H.examSpot(1)))
			for i = 1, 150 do
				H.client(p, "StartExam")
				T.truthy(session.exam, "시작 " .. i)
				for _ = 1, 8 do
					H.client(p, "Hit", "exam") -- 힘 0 = 피해 0
					H.advance(0.25)
				end
				H.advance(20.5)
				T.eq(session.exam, nil, "끝남 " .. i)
				T.eq(p.attrs.Activity, "", "활동 비움")
			end
			T.eq(data.belt, 1)
			T.eq(data.world, 1)
			T.eq(data.power, 0)
			T.eq(data.money, 0)
			T.eq(data.stats.examsFailed, 150)
			T.eq(data.stats.examsPassed, 0)
			local sent = #H.sent(p, "ExamState")
			T.truthy(sent <= 150 * 50, "ExamState 총 " .. sent .. " (회당 시작 1 + 틱 ≤ 41 + 끝 1)")
			H.advance(120) -- 끝난 뒤 틱이 쌓여 있지 않음
			T.eq(#H.sent(p, "ExamState"), sent, "끝난 뒤 ExamState 없음")
			T.eq(#H.sent(p, "DuelState"), 0)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"힘 0 대결 100번 반복 (월드 1 대결 띠 바로 앞 → 대결 띠): 시험관이 이김 · 띠 · 월드 1 그대로 · 끝나면 상태 비움 · 끝난 뒤 DuelState 없음",
		function()
			local H = setup()
			local beforeDuel = H.Belts.duelOf(1).index - 1
			local p, session, data = join(H, 1, { power = 0, belt = beforeDuel }, at(H.duelSpot(1)))
			for i = 1, 100 do
				H.client(p, "StartDuel")
				T.truthy(session.duel, "시작 " .. i)
				for _ = 1, 20 do
					H.client(p, "Hit", "duel")
					H.advance(0.25)
				end
				H.advance(30)
				T.eq(session.duel, nil, "끝남 " .. i)
			end
			T.eq(data.belt, beforeDuel)
			T.eq(data.world, 1)
			T.eq(data.stats.duelsLost, 100)
			T.eq(data.stats.duelsWon, 0)
			T.eq(p.attrs.Activity, "")
			local sent = #H.sent(p, "DuelState")
			H.advance(120)
			T.eq(#H.sent(p, "DuelState"), sent, "끝난 뒤 DuelState 없음")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"시작 직후: 나감 → 세션 비워짐 · 죽음 → 쳐도 안 됨 · Travel 막힘 · 두 번째 시작은 같은 상태 그대로 · 띠 그대로",
		function()
			local H = setup()
			-- 나감
			local p1, s1, d1 = join(H, 1, { power = 0 }, at(H.examSpot(1)))
			H.client(p1, "StartExam")
			T.truthy(s1.exam)
			H.leave(p1)
			T.eq(H.S.Sessions.get(p1), nil, "세션 삭제")
			H.advance(60)
			T.eq(d1.belt, 1)
			-- 죽음
			local p2, s2, d2 = join(H, 2, { power = 1e60, world = 2 }, at(H.examSpot(2)))
			H.client(p2, "StartExam")
			local state = s2.exam
			T.truthy(state)
			H.client(p2, "StartExam")
			T.truthy(s2.exam == state, "시작을 또 눌러도 같은 심사 (새로 안 만듦)")
			H.client(p2, "StartDuel")
			T.eq(s2.duel, nil, "심사 중에는 대결을 못 시작")
			H.client(p2, "Travel", 1)
			T.eq(s2.currentWorld, 2, "Travel 막힘")
			p2.Character.humanoid.Health = 0
			for _ = 1, 20 do
				H.client(p2, "Hit", "exam")
				H.advance(0.25)
			end
			T.eq(state.broken, 0, "죽은 채로 친 것은 안 셈")
			H.advance(25)
			T.eq(s2.exam, nil)
			T.eq(d2.belt, 1, "죽은 채로는 못 깸 (힘 1e60 이어도)")
			T.eq(d2.stats.examsFailed, 1)
			-- 대결 시작 직후 죽음 → 시험관이 이김
			p2.Character.humanoid.Health = 100
			H.teleport(p2, H.duelSpot(2))
			local beforeDuel2 = H.Belts.duelOf(2).index - 1 -- 지금 월드 2 → 월드 2 대결
			d2.belt = beforeDuel2
			H.advance(5)
			H.client(p2, "StartDuel")
			T.truthy(s2.duel)
			p2.Character.humanoid.Health = 0
			for _ = 1, 40 do
				H.client(p2, "Hit", "duel")
				H.advance(0.25)
			end
			H.advance(30)
			T.eq(s2.duel, nil)
			T.eq(d2.belt, beforeDuel2, "죽어서 못 이김")
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"힘 0 · 돈 0 무작위 행동 퍼즈 (3 판 × 500 걸음 · 심사대/대결장/스폰 사이 순간이동): 띠 1 · 월드 1 · 힘 0 · 돈 0 · 아령 1 · warn 0",
		function()
			for seed = 1, 3 do
				local H = setup()
				local rng = T.rng(seed * 101)
				local p, session, data = join(H, seed, { power = 0, money = 0 }, at(H.examSpot(1)))
				local spots = { { H.examSpot(1) }, { H.duelSpot(1) }, { H.spawnSpot(1) } }
				local actions = {
					function()
						H.client(p, "StartExam")
					end,
					function()
						H.client(p, "StartDuel")
					end,
					function()
						H.client(p, "Hit", "exam")
					end,
					function()
						H.client(p, "Hit", "duel")
					end,
					function()
						H.client(p, "Hit", "cotton")
					end,
					function()
						H.client(p, "Train")
					end,
					function()
						H.client(p, "BuyDumbbell")
					end,
					function()
						H.client(p, "Travel", 1 + math.floor(rng() * 3))
					end,
					function()
						local s = spots[1 + math.floor(rng() * #spots)]
						H.teleport(p, s[1], s[2], s[3])
					end,
					function()
						p.Character.humanoid.Health = if rng() < 0.5 then 0 else 100
					end,
				}
				for _ = 1, 500 do
					actions[1 + math.floor(rng() * #actions)]()
					H.advance(rng() * 3)
					T.truthy(not (session.exam and session.duel), "심사와 대결이 동시에 없음")
				end
				H.advance(100)
				T.eq(data.belt, 1, "seed " .. seed)
				T.eq(data.world, 1)
				T.eq(data.power, 0)
				T.eq(data.money, 0)
				T.eq(data.dumbbellLevel, 1)
				T.eq(session.exam, nil)
				T.eq(session.duel, nil)
				T.eq(p.attrs.Activity, "")
				T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
				H.uninstall()
			end
		end
	)

	T.test(
		"합격선 표 (ExamRules 진짜): 모든 띠에서 추천 힘이면 이김 · 서버 한도(초당 5번) 로 두들겨도 추천 힘의 30% 아래로는 못 이김",
		function()
			local m = pure()
			local function passes(belt, d, interval)
				local b = m.Belts.get(belt)
				if b.duel then
					local state = m.ExamRules.startDuel(belt, 0)
					local t = state.startsAt - interval
					while not state.finished do
						t += interval
						m.ExamRules.duelHit(state, d, t)
					end
					return state.phase == "win"
				end
				local state = m.ExamRules.startExam(belt, 0)
				local t = 0
				while not state.finished do
					t += interval
					m.ExamRules.examHit(state, d, t)
				end
				return state.phase == "pass"
			end
			local function threshold(belt, interval) -- 이기는 가장 작은 힘 / 추천 힘
				local need = m.Belts.get(belt).needPower
				local lo, hi = 0, need * 3
				for _ = 1, 60 do
					local mid = (lo + hi) / 2
					if passes(belt, mid, interval) then
						hi = mid
					else
						lo = mid
					end
				end
				return hi / need
			end
			local lines = {}
			local worst25, best20, worst30 = 0, math.huge, 0
			for belt = 2, m.Belts.COUNT do
				local r25, r20, r30 = threshold(belt, 0.25), threshold(belt, 0.2), threshold(belt, 0.3)
				worst25, best20, worst30 = math.max(worst25, r25), math.min(best20, r20), math.max(worst30, r30)
				table.insert(lines, string.format("띠%d %.2f/%.2f/%.2f", belt, r25, r20, r30))
			end
			print(
				"  (이기는 최소 힘 ÷ 추천 힘 — 간격 0.25 / 0.2 / 0.3: "
					.. table.concat(lines, " · ")
					.. ")"
			)
			T.truthy(worst25 <= 1.0, "초당 4번이면 추천 힘에 이김 (최악 " .. worst25 .. ")")
			T.truthy(worst30 <= 1.0, "초당 3.3번이어도 추천 힘에 이김 (최악 " .. worst30 .. ")")
			T.truthy(
				best20 >= 0.3,
				"초당 5번 두들겨도 추천 힘의 0.3배 위에서만 이김 (최소 " .. best20 .. ")"
			)
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v2 D: 아령 60개 (구매 · 값 표 · 사는 데 걸리는 시간)")
	------------------------------------------------------------------

	T.test(
		"표: 60개 · 1번 값 0 · 값·힘/번·무게 모두 순서대로 커짐 · id·이름 안 겹침",
		function()
			local m = pure()
			local list = m.Dumbbells.list
			T.eq(#list, 60)
			T.eq(list[1].price, 0)
			local ids, names = {}, {}
			for i, d in list do
				T.eq(d.level, i)
				T.falsy(ids[d.id], "id 겹침 " .. d.id)
				T.falsy(names[d.name], "이름 겹침 " .. d.name)
				ids[d.id], names[d.name] = true, true
				T.truthy(d.price == d.price and d.price >= 0 and d.price < 1e60, d.id .. " 값 범위")
				if i >= 2 then
					T.truthy(d.price > list[i - 1].price, d.id .. " 값이 앞 아령보다 큼")
					T.truthy(d.powerPerRep > list[i - 1].powerPerRep, d.id .. " 힘/번이 커짐")
					T.truthy(d.weightKg > list[i - 1].weightKg, d.id .. " 무게가 커짐")
				end
			end
			T.eq(list[2].price, 42, "3kg 42 (사장님)")
			T.eq(list[2].powerPerRep, 3)
			T.eq(list[3].powerPerRep, 10)
			T.eq(list[4].powerPerRep, 25)
			T.eq(list[5].powerPerRep, 100)
		end
	)

	T.test(
		"60개 구매: 돈이 정확히 그 값만 줄고 한 번에 한 칸 · 1 모자라면 안 삼 · 60번 뒤 구매 불가 (돈 안 줄어듦)",
		function()
			local H = setup()
			local p, _, data = join(H, 1, { money = 0 })
			for level = 1, 59 do
				local nextD = H.Dumbbells.get(level + 1)
				data.money = nextD.price * 2 + 1 -- 두 칸 값이 넉넉해도 한 칸만
				if level == 1 then
					data.money = nextD.price - 1
					T.falsy(H.S.Shop.buyDumbbell(p), "1 모자람")
					T.eq(data.dumbbellLevel, 1)
					T.eq(data.money, nextD.price - 1)
					data.money = nextD.price * 2 + 1
				end
				T.truthy(H.S.Shop.buyDumbbell(p), "레벨 " .. level + 1 .. " 삼")
				T.eq(data.dumbbellLevel, level + 1, "한 칸만")
				T.near(
					data.money,
					nextD.price + 1,
					math.max(1, nextD.price * 1e-12),
					"남은 돈 (두 배 값 + 1 − 값)"
				)
				T.eq(p.attrs.DumbbellLevel, level + 1, "Attribute")
			end
			T.eq(data.dumbbellLevel, 60)
			data.money = 1e60
			local before = #H.notifications(p)
			T.falsy(H.S.Shop.buyDumbbell(p), "61번째 없음")
			T.eq(data.dumbbellLevel, 60)
			T.eq(data.money, 1e60, "돈 그대로")
			T.truthy(#H.notifications(p) == before + 1 and H.lastNotify(p).kind == "info", "안내 한 줄")
			-- Remote 로 연타: 속도 제한 burst 3 안쪽만
			data.dumbbellLevel = 10
			data.money = 1e60
			for _ = 1, 20 do
				H.client(p, "BuyDumbbell")
			end
			T.truthy(
				data.dumbbellLevel >= 11 and data.dumbbellLevel <= 13,
				"같은 순간 연타는 최대 3칸 " .. data.dumbbellLevel
			)
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	-- sim 으로 아령마다 산 시각 · 그때 힘·띠를 잼
	local function dumbbellSim(m)
		local at, lastDb = {}, 1
		local _, log = SimPlayer.run(m, {
			onStep = function(s)
				if s.db ~= lastDb then
					lastDb = s.db
					at[s.db] = { power = s.power, belt = s.belt }
				end
			end,
		})
		local took = {}
		for level = 2, m.Dumbbells.COUNT do
			took[level] = log.buy[level] - log.buy[level - 1]
		end
		return at, took, log
	end

	T.test(
		"값 평가: 아령 값 ÷ 그때 깨는 물건 한 번 돈(지금 힘에 맞는 물건 × 띠 배율) = 2 ~ 250 번 안 (터무니없이 싸거나 비싸지 않음 — 노가다 한도가 10분이라 150 → 250, B-1)",
		function()
			local m = pure()
			local at = dumbbellSim(m)
			local lo, hi, loId, hiId = math.huge, 0, "", ""
			local lines = {}
			for level = 2, m.Dumbbells.COUNT do
				local a = at[level]
				local d = m.Dumbbells.list[level]
				local dmg = m.Economy.hitDamage(a.power, 1)
				local fit = m.Targets.list[1]
				for _, t in m.Targets.list do
					if dmg >= t.recommendPower then
						fit = t
					end
				end
				local breaks = d.price / (fit.reward * m.Belts.list[a.belt].moneyMultiplier)
				if breaks < lo then
					lo, loId = breaks, d.id
				end
				if breaks > hi then
					hi, hiId = breaks, d.id
				end
				if level <= 13 or level % 8 == 0 then
					table.insert(lines, string.format("%d:%.0f", level, breaks))
				end
			end
			print(
				string.format(
					"  (값 ÷ 맞는 물건 한 번 돈: 최소 %.1f(%s) 최대 %.1f(%s) — 레벨:번 %s)",
					lo,
					loId,
					hi,
					hiId,
					table.concat(lines, " ")
				)
			)
			T.truthy(lo >= 2, "너무 쌈 " .. loId .. " " .. lo)
			T.truthy(hi <= 250, "너무 비쌈 " .. hiId .. " " .. hi)
		end
	)

	T.test(
		"사는 데 걸리는 시간: 10분 안 · 앞/가운데/뒤 1/3 평균이 커짐 · 뒤 40개 평균은 3분 10초 ~ 10분 (결정 12번 뒤)",
		function()
			local m = pure()
			local _, took = dumbbellSim(m)
			local list = {}
			for level = 2, 60 do
				T.truthy(took[level] <= 600, "아령 " .. level .. " " .. took[level] .. "초")
				table.insert(list, took[level])
			end
			local function avg(a, b)
				local s = 0
				for i = a, b do
					s += list[i]
				end
				return s / (b - a + 1)
			end
			local n = #list
			local a1, a2, a3 = avg(1, 19), avg(20, 39), avg(40, n)
			print(string.format("  (앞 %.0f · 가운데 %.0f · 뒤 %.0f초)", a1, a2, a3))
			T.truthy(a3 > a2 and a2 > a1, "점점 늘어남")
			T.truthy(avg(21, n) >= 190 and avg(21, n) <= 600, "아령 22~60 평균 " .. avg(21, n))
		end
	)

	T.test(
		"B-1 고침: 사는 시간이 앞 아령의 95% 아래로 줄어드는 아령이 없음 (사장님: 점점 더 늘어남) · 처음 15~30초 → 마지막까지 늘어남",
		function()
			local m = pure()
			local _, took = dumbbellSim(m)
			-- 3kg 42 (사장님 고정) — 걷기가 2배 빨라져서 (결정 14번, 스폰 → 첫 매트) 20초 → 17초쯤. 아래 끝 15초
			T.truthy(took[2] >= 15 and took[2] <= 30, "3kg 아령 " .. took[2] .. "초")
			T.truthy(took[60] > took[40] and took[40] > took[20], "20 · 40 · 60번이 늘어남")
			local dips = {}
			for level = 3, 60 do
				if took[level] < took[level - 1] * 0.95 then
					table.insert(
						dips,
						string.format("%s %ds←%ds", m.Dumbbells.list[level].name, took[level], took[level - 1])
					)
				end
			end
			T.eq(#dips, 0, #dips .. "개 줄어듦: " .. table.concat(dips, ", "))
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v2 E: 아우라 서비스 PlayerVisualService (진짜 @lune/roblox 인스턴스)")
	------------------------------------------------------------------

	local function newSignal()
		local list = {}
		local signal = {}
		function signal:Connect(fn)
			local c = { fn = fn, connected = true }
			table.insert(list, c)
			return {
				Disconnect = function()
					c.connected = false
				end,
			}
		end
		function signal:Fire(...)
			for _, c in table.clone(list) do
				if c.connected then
					c.fn(...)
				end
			end
		end
		function signal:Active()
			local n = 0
			for _, c in list do
				if c.connected then
					n += 1
				end
			end
			return n
		end
		return signal
	end

	local function auraSetup()
		Loader.clearFakes()
		Loader.globals({
			Instance = roblox.Instance,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			NumberRange = roblox.NumberRange,
		})
		pcall(roblox.implementMethod, "Model", "WaitForChild", function(self, name)
			return self:FindFirstChild(name)
		end)
		Loader.reset()
		local players = { list = {}, PlayerAdded = newSignal(), PlayerRemoving = newSignal() }
		function players:GetPlayers()
			return table.clone(self.list)
		end
		Loader.service("Players", players)
		return {
			PVS = Loader.require("ServerScriptService/Server/Services/PlayerVisualService"),
			Visuals = Loader.require("ReplicatedStorage/Shared/Data/Visuals"),
			players = players,
		}
	end

	local function realChar()
		local ch = roblox.Instance.new("Model")
		local rp = roblox.Instance.new("Part")
		rp.Name = "HumanoidRootPart"
		rp.Size = roblox.Vector3.new(2, 2, 1)
		rp.Parent = ch
		local hm = roblox.Instance.new("Humanoid")
		hm.Parent = ch
		return ch
	end

	local function particleRate(ch)
		local sum = 0
		for _, d in ch:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				sum += d.Rate
			end
		end
		return sum
	end

	T.test(
		"같은 단계 안에서 Power 가 1,000번 바뀌어도 인스턴스를 다시 만들지 않음 (표시 붙인 것들이 그대로)",
		function()
			local E = auraSetup()
			local ch = realChar()
			T.eq(E.PVS.apply(ch, 1.0e7), 3)
			local root = ch.HumanoidRootPart
			local marked =
				{ root:FindFirstChild("AuraAttach"), root:FindFirstChild("AuraLight"), ch:FindFirstChild("AuraRing") }
			T.eq(#marked, 3)
			for _, inst in marked do
				inst:SetAttribute("Mark", 1)
			end
			local sparks = root.AuraAttach:FindFirstChild("AuraSparks")
			sparks:SetAttribute("Mark", 1)
			local before = #ch:GetDescendants()
			for i = 1, 1000 do
				T.eq(E.PVS.apply(ch, 1e7 + i * 9.9e6), 3)
			end
			T.eq(#ch:GetDescendants(), before, "인스턴스 수 그대로")
			for _, inst in marked do
				T.eq(inst:GetAttribute("Mark"), 1, inst.Name .. " 다시 안 만듦")
			end
			T.eq(root.AuraAttach:FindFirstChild("AuraSparks"):GetAttribute("Mark"), 1)
		end
	)

	T.test(
		"단계를 500번 오르내려도 (1e4 ↔ 1e7 ↔ 1e39) 아우라 인스턴스는 늘지 않음 · 고리 1개 · 파티클 Rate 합 ≤ 상한",
		function()
			local E = auraSetup()
			local ch = realChar()
			local counts = {}
			for i = 1, 500 do
				local power = ({ 1e4, 1e7, 1e39, 99, 100 })[1 + i % 5]
				local tier = E.PVS.apply(ch, power)
				local n = #ch:GetDescendants()
				counts[tier] = counts[tier] or n
				T.eq(n, counts[tier], "단계 " .. tier .. " 의 인스턴스 수가 매번 같음")
				local rings = 0
				for _, c in ch:GetChildren() do
					if c.Name == "AuraRing" then
						rings += 1
					end
				end
				T.truthy(rings <= 1, "고리 " .. rings)
				T.truthy(particleRate(ch) <= E.Visuals.AURA_RATE_CAP, "Rate 합 " .. particleRate(ch))
			end
			for tier, a in E.Visuals.AURA do
				local c2 = realChar()
				E.PVS.apply(c2, a.power)
				local r = particleRate(c2)
				T.truthy(r >= 8 and r <= E.Visuals.AURA_RATE_CAP, "단계 " .. tier .. " Rate " .. r)
			end
		end
	)

	T.test(
		"힘이 NaN · 음수 · ±inf · 1e308 · 1e60 · 글자 · nil · 표 · true 여도 에러 없고 단계는 0 ~ 끝 · 아우라 한 벌만",
		function()
			local E = auraSetup()
			local ch = realChar()
			local weird = { 0 / 0, -1, -math.huge, math.huge, 1e308, 1e60, "abc", "1e9", "", nil, {}, true, 0, -0.0 }
			for round = 1, 3 do
				for i = 1, 14 do
					local ok, tier = pcall(E.PVS.apply, ch, weird[i])
					T.truthy(ok, "에러: " .. tostring(tier) .. " (값 " .. tostring(weird[i]) .. ")")
					T.truthy(
						type(tier) == "number" and tier >= 0 and tier <= #E.Visuals.AURA,
						"단계 " .. tostring(tier)
					)
					T.truthy(
						#ch.HumanoidRootPart:GetChildren() <= 3,
						"뿌리 아래 아우라 한 벌 (round " .. round .. ")"
					)
				end
			end
			T.eq(E.PVS.apply(ch, 0 / 0), 0, "NaN = 단계 0")
			T.falsy(ch.HumanoidRootPart:FindFirstChild("AuraAttach"), "단계 0 이면 아우라가 사라짐")
			T.eq(E.PVS.apply(ch, 1e60), #E.Visuals.AURA)
			T.eq(E.PVS.apply(ch, "1e9"), 3, "글자 힘도 숫자로 (Attribute 는 실제론 숫자)")
		end
	)

	T.test(
		"캐릭터 없음 · 뿌리 없음 · 월드에서 빠진 캐릭터 (Parent nil) → 에러 없음, 없으면 0",
		function()
			local E = auraSetup()
			T.eq(E.PVS.apply(nil, 1e20), 0)
			local noRoot = roblox.Instance.new("Model")
			T.eq(E.PVS.apply(noRoot, 1e20), 0)
			local ch = realChar()
			T.eq(E.PVS.apply(ch, 1e20), 6)
			ch.Parent = nil
			local ok, err = pcall(E.PVS.apply, ch, 1e30)
			T.truthy(ok, "빠진 캐릭터에도 에러 없음: " .. tostring(err))
			-- (엔진이 Destroy 한 캐릭터에 부르면 Lune 은 "Instance has been destroyed" 를 던짐 — 실제 로블록스는 던지지 않음)
		end
	)

	T.test(
		"start(): Power Attribute 가 바뀔 때마다 갱신 · 리스폰 100번 해도 연결은 플레이어당 2개 그대로 · 새 몸에도 붙음",
		function()
			local E = auraSetup()
			local pl = { Character = nil, CharacterAdded = newSignal(), attrs = {}, sigs = {} }
			function pl:SetAttribute(k, v)
				self.attrs[k] = v
				if self.sigs[k] then
					self.sigs[k]:Fire()
				end
			end
			function pl:GetAttribute(k)
				return self.attrs[k]
			end
			function pl:GetAttributeChangedSignal(k)
				self.sigs[k] = self.sigs[k] or newSignal()
				return self.sigs[k]
			end
			E.PVS.start()
			table.insert(E.players.list, pl)
			E.players.PlayerAdded:Fire(pl)
			local ch = realChar()
			pl.Character = ch
			pl.CharacterAdded:Fire(ch)
			T.eq(ch:GetAttribute("AuraTier"), 0)
			pl:SetAttribute("Power", 5e7)
			T.eq(ch:GetAttribute("AuraTier"), 3)
			ch.HumanoidRootPart.AuraAttach:SetAttribute("Mark", 1)
			for i = 1, 500 do
				pl:SetAttribute("Power", 5e7 + i * 1e3)
			end
			T.eq(ch.HumanoidRootPart.AuraAttach:GetAttribute("Mark"), 1, "틱마다 바뀌어도 그대로")
			for _ = 1, 100 do
				local nc = realChar()
				pl.Character = nc
				pl.CharacterAdded:Fire(nc)
				T.eq(nc:GetAttribute("AuraTier"), 3, "새 몸에도 붙음")
				T.truthy(nc.HumanoidRootPart:FindFirstChild("AuraAttach"))
			end
			T.eq(pl.CharacterAdded:Active(), 1, "CharacterAdded 연결 1개")
			T.eq(pl.sigs.Power:Active(), 1, "Power 연결 1개")
			-- 힘 NaN · 1e60 · 음수
			for _, v in { 0 / 0, 1e60, -5, "x" } do
				local ok, err = pcall(pl.SetAttribute, pl, "Power", v)
				T.truthy(ok, tostring(err))
			end
			-- 캐릭터가 없는 사이 (리스폰 중)
			pl.Character = nil
			local ok, err = pcall(pl.SetAttribute, pl, "Power", 1e20)
			T.truthy(ok, tostring(err))
		end
	)

	T.test(
		"플레이어 한 명이 낼 수 있는 파티클 Rate 총합 (아우라 최대 + 손에 든 아령 60단계 × 두 손) ≤ 상한 60",
		function()
			local E = auraSetup()
			local Look = Loader.require("ReplicatedStorage/Shared/DumbbellLook")
			local maxAura = 0
			for _, a in E.Visuals.AURA do
				maxAura = math.max(maxAura, math.min(a.rate, E.Visuals.AURA_RATE_CAP))
			end
			local worst, worstLevel = 0, 0
			for level = 1, 60 do
				local model = Look.build(nil, level, 1, false, roblox.CFrame.new())
				local rate = particleRate(model)
				local hands = if Look.spec(level).twoHands then 2 else 1
				if rate * hands > worst then
					worst, worstLevel = rate * hands, level
				end
			end
			print(
				string.format(
					"  (아우라 최대 %d + 손에 든 아령 최대 %d (아령 %d) = %d / 상한 %d)",
					maxAura,
					worst,
					worstLevel,
					maxAura + worst,
					E.Visuals.AURA_RATE_CAP
				)
			)
			T.truthy(maxAura + worst <= E.Visuals.AURA_RATE_CAP, "총합 " .. maxAura + worst)
		end
	)

	T.test("B-5 고침: 플레이어가 나가면 (PlayerRemoving) PlayerVisualService 가 연결을 끊음", function()
		local E = auraSetup()
		local pl = { Character = nil, CharacterAdded = newSignal(), attrs = {}, sigs = {} }
		function pl:SetAttribute(k, v)
			self.attrs[k] = v
			if self.sigs[k] then
				self.sigs[k]:Fire()
			end
		end
		function pl:GetAttribute(k)
			return self.attrs[k]
		end
		function pl:GetAttributeChangedSignal(k)
			self.sigs[k] = self.sigs[k] or newSignal()
			return self.sigs[k]
		end
		E.PVS.start()
		table.insert(E.players.list, pl)
		E.players.PlayerAdded:Fire(pl)
		-- 나감: 목록에서 빠짐 (엔진이 Player 를 파괴하지 않는 경우를 가정)
		T.eq(pl.sigs.Power:Active() + pl.CharacterAdded:Active(), 2, "들어오면 연결 2개")
		table.remove(E.players.list, 1)
		E.players.PlayerRemoving:Fire(pl)
		T.eq(pl.sigs.Power:Active() + pl.CharacterAdded:Active(), 0, "나간 뒤 연결이 남아 있음")
	end)

	------------------------------------------------------------------
	T.suite("holes_v2 F: 아슬아슬한 숫자 (sim 을 흔들어 6장 규칙이 얼마나 버티나)")
	------------------------------------------------------------------

	-- sim 을 한 번 돌려 6장 규칙을 한 줄로: 월드 끝 · 가장 긴 머묾 · 가장 긴 아령 · 규칙 어긴 곳
	local function evalSim(m)
		local final, log = SimPlayer.run(m)
		local maxStay, maxStayId, over9 = 0, "", 0
		for i = 1, 40 do
			local t = m.Targets.list[i]
			if log.open[i] and log.comf[i] then
				local stay = log.comf[i] - log.open[i]
				if stay > maxStay then
					maxStay, maxStayId = stay, t.id
				end
				if stay > 540 then
					over9 += 1
				end
			end
		end
		local maxBuy, maxBuyLevel = 0, 0
		for level = 2, 60 do
			if log.buy[level] and log.buy[level - 1] and log.buy[level] - log.buy[level - 1] > maxBuy then
				maxBuy, maxBuyLevel = log.buy[level] - log.buy[level - 1], level
			end
		end
		local ends = { log.worldOpen[2], log.worldOpen[3], log.belt[m.Belts.COUNT] }
		local bands = SimPlayer.WORLD_END -- sim_progress RULES.worldEnd (결정 13·14·16번 뒤 ±30%)
		local inBand = true
		for w = 1, 3 do
			if not (ends[w] and ends[w] >= bands[w][1] and ends[w] <= bands[w][2]) then
				inBand = false
			end
		end
		return {
			ends = ends,
			inBand = inBand,
			maxStay = maxStay,
			maxStayId = maxStayId,
			over9 = over9,
			maxBuy = maxBuy,
			maxBuyLevel = maxBuyLevel,
			grand = m.Progression.isGrandMaster(final.belt),
			line = string.format(
				"월드 끝 %s · %s · %s | 가장 긴 머묾 %s(%s) 9분 넘음 %d개 | 가장 긴 아령 %d초(#%d)",
				mmss(ends[1]),
				mmss(ends[2]),
				mmss(ends[3]),
				mmss(maxStay),
				maxStayId,
				over9,
				maxBuy,
				maxBuyLevel
			),
		}
	end

	-- SimPlayer.SIM 상수를 잠깐 바꿔 돌리고 되돌림
	local function withSim(changes, fn)
		local saved = {}
		for k, v in changes do
			saved[k] = SimPlayer.SIM[k]
			SimPlayer.SIM[k] = v
		end
		local ok, result = pcall(fn)
		for k, v in saved do
			SimPlayer.SIM[k] = v
		end
		assert(ok, result)
		return result
	end

	local function examScaled(m, scale) -- 심사·대결에서 내 힘이 scale 배로만 먹히는 플레이어 (= 1/scale 배 힘이 되어야 합격)
		local copy = table.clone(m)
		copy.ExamRules = setmetatable({
			examHit = function(state, d, now)
				return m.ExamRules.examHit(state, d * scale, now)
			end,
			duelHit = function(state, d, now)
				return m.ExamRules.duelHit(state, d * scale, now)
			end,
		}, { __index = m.ExamRules })
		return copy
	end

	T.test(
		"기준: 월드 끝 3개 목표 안 · 머묾 9분 안 · 아령 10분 안 — 그리고 여유 (월드 1 끝은 53분 한도에서 몇 %)",
		function()
			local m = pure()
			local r = evalSim(m)
			print("  (" .. r.line .. ")")
			T.truthy(r.inBand and r.grand)
			T.truthy(r.over9 == 0 and r.maxStay <= 540, "머묾 " .. r.maxStay)
			T.truthy(r.maxBuy <= 600, "아령 " .. r.maxBuy)
			local margin1 = (SimPlayer.WORLD_END[1][2] - r.ends[1]) / SimPlayer.WORLD_END[1][2]
			local margin3 = (r.ends[3] - SimPlayer.WORLD_END[3][1]) / SimPlayer.WORLD_END[3][1]
			local marginStay = (540 - r.maxStay) / 540
			local marginBuy = (600 - r.maxBuy) / 600
			print(
				string.format(
					"  (여유: 월드 1 상한 %.1f%% · 월드 3 하한 %.1f%% · 머묾 %.1f%% · 아령 %.1f%%)",
					margin1 * 100,
					margin3 * 100,
					marginStay * 100,
					marginBuy * 100
				)
			)
			T.truthy(margin1 > 0 and margin3 > 0 and marginStay > 0 and marginBuy > 0)
		end
	)

	T.test(
		"맵 거리: 걷기가 2배 느려지거나(진짜 빠르기 × 0.5) 1.25배 빨라져도 (거리 = 시간) 월드 끝 3개 목표 안 · 머묾 9분 + 10초 안 — 길가 매트 덕에 거리는 안 중요",
		function()
			local m = pure()
			for _, factor in { 0.5, 0.8, 1.25 } do
				local r = withSim({ WALK_FACTOR = factor }, function()
					return evalSim(m)
				end)
				print(string.format("  (걷기 × %s: %s)", factor, r.line))
				T.truthy(r.inBand and r.grand, "걷기 × " .. factor .. " 월드 끝 " .. mmss(r.ends[3]))
				T.truthy(r.maxStay <= 550, "걷기 × " .. factor .. " 머묾 " .. r.maxStay)
			end
		end
	)

	T.test(
		"심사·대결을 합격선(0.57배 힘)이 아니라 추천 힘(1배)에서 보는 플레이어 (효과 ×0.8 · ×0.57): 월드 끝 목표 안 · 머묾 9분 안",
		function()
			local m = pure()
			for _, scale in { 0.8, 0.57 } do
				local r = evalSim(examScaled(m, scale))
				print(string.format("  (심사·대결 효과 ×%s: %s)", scale, r.line))
				T.truthy(r.inBand and r.grand, "×" .. scale)
				T.truthy(r.maxStay <= 540, "×" .. scale .. " 머묾 " .. r.maxStay)
			end
		end
	)

	T.test(
		"손가락이 느린 쪽 (반복 간격 0.28초 = 초당 3.6번 — sim 기준 0.27 보다 느림): 월드 끝 목표 안 · 머묾 9분 + 10초 안",
		function()
			local m = pure()
			local r = withSim({ TICK = 0.28 }, function()
				return evalSim(m)
			end)
			print("  (간격 0.28: " .. r.line .. ")")
			T.truthy(r.inBand and r.grand)
			T.truthy(r.maxStay <= 550, "머묾 " .. r.maxStay)
		end
	)

	T.test(
		"B-2 고침: 클라 반복 0.22초 (서버 한도 0.2초보다 10% 느림) · sim 은 프레임 올림을 감안한 느린 쪽 0.27초 · 실제 빠르기(0.233)에서도 머묾 9분 · 아령 10분 안",
		function()
			local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
			local Remotes = Loader.require("ReplicatedStorage/Shared/Remotes")
			T.truthy(
				Config.AUTO_REPEAT_SECONDS >= 1.1 / Remotes.RateLimits.Train.perSecond - 1e-9,
				"들기 한도 여유 10%"
			)
			T.truthy(
				Config.AUTO_REPEAT_SECONDS >= 1.1 / Remotes.RateLimits.Hit.perSecond - 1e-9,
				"치기 한도 여유 10%"
			)
			T.truthy(SimPlayer.SIM.TICK >= Config.AUTO_REPEAT_SECONDS * 1.2, "sim 이 실제보다 느린 쪽")
			local m = pure()
			local base = evalSim(m)
			T.truthy(base.inBand and base.over9 == 0 and base.maxBuy <= 600, "0.27: " .. base.line)
			local fast = withSim({ TICK = 0.2333 }, function()
				return evalSim(m)
			end)
			print("  (간격 0.233: " .. fast.line .. ")")
			T.truthy(fast.over9 == 0 and fast.maxBuy <= 600 and fast.grand, "0.233: " .. fast.line)
		end
	)

	T.test(
		"B-3 고침: 심사·대결을 추천 힘에서 보는 플레이어(×0.57)도 아령 한 개 사는 데 10분 안",
		function()
			local m = pure()
			local r = evalSim(examScaled(m, 0.57))
			print("  (×0.57: " .. r.line .. ")")
			T.truthy(r.maxBuy <= 600, r.line)
		end
	)

	------------------------------------------------------------------
	T.suite("holes_v2 G: 1판 A-1 ~ A-4 다시 확인 + 길가 매트 41칸")
	------------------------------------------------------------------

	T.test(
		"A-1 고침: 죽은 캐릭터(Health 0)는 치기 · 들기 · 심사 · 대결 시작 · 송판 치기 전부 안 됨",
		function()
			local H = setup()
			local mp = H.MapLayout.matPoint("cotton")
			local p, session, data = join(H, 1, { power = 1e6 }, at(mp.x, mp.y + 3, mp.z))
			p.Character.humanoid.Health = 0
			T.eq(H.S.Break.hit(p, "cotton"), nil)
			T.eq(H.S.Train.train(p), 0)
			T.eq(data.money, 0)
			T.eq(data.power, 1e6)
			H.teleport(p, H.examSpot(1))
			T.falsy(H.S.Exam.startExam(p))
			data.belt = H.Belts.duelOf(1).index - 1
			H.teleport(p, H.duelSpot(1))
			T.falsy(H.S.Exam.startDuel(p))
			T.eq(session.exam, nil)
			T.eq(session.duel, nil)
			p.Character.humanoid.Health = 100
			T.truthy(H.S.Exam.startDuel(p), "살아나면 됨")
			p.Character.humanoid.Health = 0
			H.advance(3.5)
			T.falsy(H.S.Exam.hit(p, "duel"), "죽은 채로 송판 못 침")
			T.eq(#H.warnings, 0)
			H.uninstall()
		end
	)

	T.test(
		"A-2 고침: 심사·대결은 수련 매트(도장 6칸 + 길가 41칸) 위 어디서도 시작 안 됨 · 판 위에서는 됨 (월드 1·2·3)",
		function()
			local H = setup()
			local ML = H.MapLayout
			for world = 1, 3 do
				-- 다음 띠가 대결 띠 (duelBelt) / 심사 띠 (examBelt) 인 띠 — 띠 표에서 읽음
				local duelBelt, examBelt = H.Belts.duelOf(world).index - 1, H.Belts.ofWorld(world)[1].index
				local p, _, data = join(H, world, { world = 3, belt = duelBelt }, at(H.examSpot(world)))
				local session = H.S.Sessions.get(p)
				session.currentWorld = world
				local mats = {}
				for _, m in ML.trainMats(world) do
					table.insert(mats, m)
				end
				for _, m in ML.roadMats(world) do
					table.insert(mats, m)
				end
				for _, m in mats do
					for _, c in { { 0, 0 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } } do
						H.teleport(p, m.x + c[1] * m.sizeX / 2, 3, m.z + c[2] * m.sizeZ / 2)
						T.falsy(H.S.Exam.startDuel(p), "대결 시작됨 (매트 " .. m.x .. "," .. m.z .. ")")
						data.belt = examBelt
						T.falsy(H.S.Exam.startExam(p), "심사 시작됨 (매트 " .. m.x .. "," .. m.z .. ")")
						data.belt = duelBelt
					end
				end
				H.teleport(p, H.duelSpot(world))
				T.truthy(H.S.Exam.startDuel(p), "대결장 가운데에서는 시작됨")
				H.S.Exam.cancel(p)
				data.belt = examBelt
				H.teleport(p, H.examSpot(world))
				T.truthy(H.S.Exam.startExam(p), "심사대 가운데에서는 시작됨")
				H.S.Exam.cancel(p)
			end
			T.eq(#H.warnings, 0)
			H.uninstall()
		end
	)

	T.test(
		"A-3 고침: sim 의 걷기 = 진짜 길가 매트 거리 — 물건 41개 전부 매트 가운데에 서면 걷지 않고 침 (matWalkDistance 0) · 매트 가운데는 매트 위",
		function()
			local H = setup()
			local ML = H.MapLayout
			local maxWalk = 0
			for _, t in H.Targets.list do
				maxWalk = math.max(maxWalk, ML.matWalkDistance(t.id))
				local mp = ML.matPoint(t.id)
				T.truthy(mp, t.id .. " 매트")
				T.truthy(
					ML.isOnTrainMat({ x = mp.x, y = 3, z = mp.z }, t.world),
					t.id .. " 매트 가운데가 매트 위"
				)
			end
			T.eq(maxWalk, 0, "41개 모두 걷지 않고 침")
			local source = fs.readFile(GAME_DIR .. "/tests/SimPlayer.luau")
			T.truthy(string.find(source, "matPoint", 1, true), "sim 이 진짜 매트 자리를 씀")
			T.truthy(string.find(source, "matWalkDistance", 1, true), "sim 이 진짜 매트 거리를 씀")
			H.uninstall()
		end
	)

	T.test(
		"길가 매트 41칸: 가운데 + 네 모서리에서 들기도 되고 치기도 됨 (서버 판정) · 매트 바로 밖에서는 안 들림",
		function()
			local H = setup()
			local ML = H.MapLayout
			local p, _, data = join(H, 1, { power = 1, world = 3 })
			for _, t in H.Targets.list do
				local m = ML.roadMats(t.world)
				local mat = nil
				for _, rm in m do
					if rm.targetId == t.id then
						mat = rm
					end
				end
				T.truthy(mat, t.id .. " 길가 매트")
				local session = H.S.Sessions.get(p)
				session.currentWorld = t.world
				for _, c in { { 0, 0 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } } do
					H.teleport(p, mat.x + c[1] * (mat.sizeX / 2 - 0.2), 3, mat.z + c[2] * (mat.sizeZ / 2 - 0.2))
					local before = data.power
					T.truthy(H.S.Train.train(p) > 0, t.id .. " 매트 (" .. c[1] .. "," .. c[2] .. ") 들기")
					T.truthy(data.power > before)
					T.truthy(H.S.Break.hit(p, t.id), t.id .. " 매트 (" .. c[1] .. "," .. c[2] .. ") 치기")
				end
				H.teleport(p, mat.x, 3, mat.z + mat.sizeZ / 2 + 3)
				T.eq(H.S.Train.train(p), 0, t.id .. " 매트 바로 밖(길 앞쪽)에서는 못 듦")
				H.advance(4)
			end
			T.eq(#H.warnings, 0, table.concat(H.warnings, " | "))
			H.uninstall()
		end
	)

	T.test(
		"A-4 (설계서에 적음): 치기·들기 속도 제한 = 처음 5번 덤 + 초당 5번 — 첫 1초 10번 · 이후 초당 5번 · 설계서 6장에 그 말이 있음",
		function()
			local H = setup()
			local mp = H.MapLayout.matPoint("cotton")
			local p = join(H, 1, { power = 1 }, at(mp.x, mp.y + 3, mp.z))
			for _ = 1, 40 do
				H.client(p, "Train")
			end
			T.eq(#H.sent(p, "TrainResult"), 5, "같은 순간엔 덤 5번만")
			H.advance(1)
			for _ = 1, 40 do
				H.client(p, "Train")
			end
			T.eq(#H.sent(p, "TrainResult"), 10, "1초 뒤 +5")
			H.advance(10)
			for _ = 1, 40 do
				H.client(p, "Train")
			end
			T.eq(#H.sent(p, "TrainResult"), 15, "덤은 5번까지만 쌓임 (오래 쉬어도 +5)")
			local design = fs.readFile(GAME_DIR .. "/docs/DESIGN.md")
			T.truthy(
				string.find(design, "처음 5번 덤", 1, true),
				"설계서에 '처음 5번 덤' 이 적혀 있음"
			)
			H.uninstall()
		end
	)
end
