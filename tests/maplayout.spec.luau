--!nocheck
-- 2판 맵 배치 (shared/Data/MapLayout): 일자 복도, 허브 양옆 베이스 7개, 구역 z 범위 판정

return function(T, Loader)
	local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")

	T.suite("MapLayout (2판 맵 배치)")

	T.test("약속한 숫자 그대로", function()
		T.eq(MapLayout.CORRIDOR_WIDTH, 220)
		T.eq(MapLayout.WALL_HEIGHT, 60)
		T.eq(MapLayout.HUB.zMax, 0)
		T.eq(MapLayout.SAFE_ZONE_Z, 0)
		T.eq(MapLayout.BIOME_LENGTH, 240)
		T.truthy(MapLayout.HUB.zMin < 0, "허브는 z < 0")
	end)

	T.test("구역 15개: Biomes 순서, 240씩 이어짐, 0 에서 시작", function()
		T.eq(#MapLayout.biomes, 15)
		for i, b in MapLayout.biomes do
			T.eq(b.id, Biomes.list[i].id, "순서 " .. i)
			T.eq(b.index, i)
			T.eq(b.zMin, (i - 1) * 240, b.id .. " zMin")
			T.eq(b.zMax, i * 240, b.id .. " zMax")
		end
		T.eq(MapLayout.biomes[1].id, "forest")
		T.eq(MapLayout.biomes[14].id, "candy_kingdom")
		T.eq(MapLayout.biomes[15].id, "haunted_castle")
		T.eq(MapLayout.MAP_END_Z, 3600)
	end)

	T.test("zoneAt: z 범위로 판정 (경계 z = 0 은 숲, 음수는 허브)", function()
		T.eq(MapLayout.zoneAt(-0.01), "hub")
		T.eq(MapLayout.zoneAt(-100), "hub")
		T.eq(MapLayout.zoneAt(MapLayout.HUB.zMin), "hub")
		T.eq(MapLayout.zoneAt(MapLayout.HUB.zMin - 1), nil)
		T.eq(MapLayout.zoneAt(0), "forest")
		T.eq(MapLayout.zoneAt(239.9), "forest")
		T.eq(MapLayout.zoneAt(240), "lake")
		T.eq(MapLayout.zoneAt(3599), "haunted_castle")
		T.eq(MapLayout.zoneAt(3600), nil)
		T.eq(MapLayout.zoneAt(0 / 0), nil)
		T.eq(MapLayout.zoneAtPos({ X = 50, Z = 500 }), "desert")
		T.eq(MapLayout.zoneAtPos({ x = 50, z = 500 }), "desert")
	end)

	T.test("isInHub: z < 0 이면 허브", function()
		T.truthy(MapLayout.isInHub({ X = 0, Z = -1 }))
		T.truthy(MapLayout.isInHub({ x = -100, z = -280 }))
		T.falsy(MapLayout.isInHub({ X = 0, Z = 0 }))
		T.falsy(MapLayout.isInHub({ X = 0, Z = 10 }))
	end)

	T.test("베이스 7개: 왼쪽 4 · 오른쪽 3, 허브 안, 서로 안 겹침, 복도 가운데를 봄", function()
		T.eq(#MapLayout.plots, 7)
		T.eq(MapLayout.PLOT_COUNT, Config.PLOT_COUNT)
		local left, right = 0, 0
		for i, p in MapLayout.plots do
			T.eq(p.index, i)
			if p.side == "left" then
				left += 1
				T.eq(p.center.x, -75)
				T.eq(p.facing, 1)
			else
				right += 1
				T.eq(p.side, "right")
				T.eq(p.center.x, 75)
				T.eq(p.facing, -1)
			end
			T.eq(p.size.w, 60)
			T.eq(p.size.d, 70)
			-- 허브 안 + 복도 벽 안
			T.truthy(p.rect.zMin >= MapLayout.HUB.zMin and p.rect.zMax <= MapLayout.HUB.zMax, "허브 안 " .. i)
			T.truthy(p.rect.xMin >= -110 and p.rect.xMax <= 110, "벽 안 " .. i)
			-- 우리 + 앞마당 = 전체, 앞마당이 복도 쪽
			local yardC = MapLayout.rectCenter(p.yardRect)
			local penC = MapLayout.rectCenter(p.penRect)
			T.truthy(math.abs(yardC.x) < math.abs(penC.x), "앞마당이 복도 쪽 " .. i)
			local px = MapLayout.rectSize(p.penRect)
			local yx = MapLayout.rectSize(p.yardRect)
			T.near(px + yx, 70, 1e-9)
			T.truthy(px > yx * 1.5, "우리가 약 2/3")
			-- 스폰·러닝머신·퓨전·판매대·표지판은 앞마당 안
			for name, spot in { spawn = p.spawn, treadmill = p.treadmill, fusion = p.fusion, sellStall = p.sellStall } do
				T.truthy(MapLayout.inRect(p.yardRect, spot.x, spot.z), name .. " 앞마당 안 " .. i)
			end
			for name, spot in p.signs do
				T.truthy(MapLayout.inRect(p.rect, spot.x, spot.z), name .. " 표지판 베이스 안 " .. i)
			end
			T.truthy(MapLayout.isInPlot(p.spawn, i))
			T.eq(MapLayout.plotAt(p.spawn), i)
			-- 다른 베이스와 안 겹침
			for j, q in MapLayout.plots do
				if j ~= i then
					local overlap = p.rect.xMin < q.rect.xMax
						and q.rect.xMin < p.rect.xMax
						and p.rect.zMin < q.rect.zMax
						and q.rect.zMin < p.rect.zMax
					T.falsy(overlap, "겹침 " .. i .. "-" .. j)
				end
			end
		end
		T.eq(left, 4)
		T.eq(right, 3)
		-- 복도 가운데(x=0)는 베이스가 아님
		T.eq(MapLayout.plotAt({ x = 0, z = -40 }), nil)
	end)

	T.test(
		"[옛 받침] incubatorSpots: 8칸, 우리 안, 서로 6 이상 떨어짐 / petRect 는 우리 안 뒤쪽",
		function()
			for i = 1, 7 do
				local spots = MapLayout.incubatorSpots(i)
				T.eq(#spots, 8)
				local pen = MapLayout.penRect(i)
				local pets = MapLayout.petRect(i)
				for a, s in spots do
					T.truthy(MapLayout.inRect(pen, s.x, s.z), "우리 안 " .. i .. "/" .. a)
					T.falsy(MapLayout.inRect(pets, s.x, s.z), "펫 자리와 안 겹침 " .. i .. "/" .. a)
					for b, t in spots do
						if a ~= b then
							T.truthy(math.sqrt((s.x - t.x) ^ 2 + (s.z - t.z) ^ 2) >= 6, "간격")
						end
					end
				end
				T.truthy(
					pets.xMin >= pen.xMin and pets.xMax <= pen.xMax and pets.zMin >= pen.zMin and pets.zMax <= pen.zMax
				)
				T.truthy(MapLayout.isInPen(MapLayout.rectCenter(pets), i))
			end
			T.eq(#MapLayout.incubatorSpots(99), 0)
		end
	)

	T.test(
		"2판 수정 베이스 기준 좌표: toLocal ↔ toWorld 왕복, 왼쪽·오른쪽 거울, PEN_LOCAL = 모든 베이스 penRect",
		function()
			local pen = MapLayout.PEN_LOCAL
			T.eq(pen.xMin, -35)
			T.eq(pen.xMax, 11)
			T.eq(pen.zMin, -30)
			T.eq(pen.zMax, 30)
			for i = 1, 7 do
				local p = MapLayout.plot(i)
				for _, l in { { -35, -30 }, { 11, 30 }, { -12.3, 5.1 }, { 0, 0 } } do
					local wpos = MapLayout.toWorld(i, l[1], l[2])
					local back = MapLayout.toLocal(i, wpos)
					T.near(back.x, l[1], 1e-9)
					T.near(back.z, l[2], 1e-9)
				end
				-- 로컬 우리 네 모서리 = 월드 penRect
				local a = MapLayout.toWorld(i, pen.xMin, pen.zMin)
				local b = MapLayout.toWorld(i, pen.xMax, pen.zMax)
				T.near(math.min(a.x, b.x), p.penRect.xMin, 1e-9)
				T.near(math.max(a.x, b.x), p.penRect.xMax, 1e-9)
				T.near(math.min(a.z, b.z), p.penRect.zMin, 1e-9)
				T.near(math.max(a.z, b.z), p.penRect.zMax, 1e-9)
				-- +lx = 복도 쪽
				local front = MapLayout.toWorld(i, 35, 0)
				T.near(math.abs(front.x), 40, 1e-9, "앞 가장자리 |x| = 40")
				T.truthy(MapLayout.isInPen(MapLayout.toWorld(i, 0, 0), i))
				T.falsy(MapLayout.isInPen(MapLayout.toWorld(i, 10, 0), i, 2), "울타리 2 안쪽만 (inset)")
			end
			T.eq(MapLayout.toLocal(99, { x = 0, z = 0 }), nil)
			T.eq(MapLayout.toWorld(0, 0, 0), nil)
			T.truthy(MapLayout.isInPenLocal(0, 0))
			T.falsy(MapLayout.isInPenLocal(0 / 0, 0))
			T.falsy(MapLayout.isInPenLocal(12, 0), "앞마당")
		end
	)

	T.test(
		"eggGridLocal: 20칸 전부 우리 안(울타리 2 안쪽), 서로 7 이상, 1~8 = 옛 부화 슬롯 자리",
		function()
			local seen = {}
			for i = 1, MapLayout.EGG_GRID_COUNT do
				local s = MapLayout.eggGridLocal(i)
				T.truthy(s, "칸 " .. i)
				T.truthy(MapLayout.isInPenLocal(s.x, s.z, Config.EGG_PLACE_FENCE_MARGIN), "우리 안 " .. i)
				for _, t in seen do
					T.truthy(math.sqrt((s.x - t.x) ^ 2 + (s.z - t.z) ^ 2) >= 7, "간격 " .. i)
				end
				table.insert(seen, s)
			end
			T.eq(MapLayout.eggGridLocal(0), nil)
			T.eq(MapLayout.eggGridLocal(MapLayout.EGG_GRID_COUNT + 1), nil)
			T.eq(MapLayout.eggGridLocal(2.5), nil)
			T.eq(MapLayout.eggGridLocal(0 / 0), nil)
			for i = 1, 8 do
				local s = MapLayout.eggGridLocal(i)
				local old = MapLayout.incubatorSpots(3)[i]
				local w = MapLayout.toWorld(3, s.x, s.z)
				T.near(w.x, old.x, 1e-9)
				T.near(w.z, old.z, 1e-9)
			end
		end
	)

	------------------------------------------------------------------
	T.suite("EggPlacement (2판 수정: 우리 안 원하는 자리에 알 놓기 규칙)")

	local EggPlacement = Loader.require("ReplicatedStorage/Shared/EggPlacement")

	T.test(
		"우리 안(울타리 2 안쪽)만, 다른 알과 4 이상(큰 알은 지름 평균), 펫과 4 이상",
		function()
			T.eq(Config.EGG_PLACE_SPACING, 4)
			T.eq(Config.EGG_PLACE_FENCE_MARGIN, 2)
			T.truthy(EggPlacement.check(0, 0, "normal", {}))
			T.truthy(EggPlacement.check(9, 28, "normal", {}), "모서리 딱 2 안쪽")
			T.truthy(EggPlacement.check(-33, -28, "normal", {}))
			local ok, reason = EggPlacement.check(9.01, 0, "normal", {})
			T.falsy(ok)
			T.eq(reason, "outside")
			T.falsy(EggPlacement.check(0, 28.01, "normal", {}))
			T.falsy(EggPlacement.check(20, 0, "normal", {}), "앞마당")
			T.falsy(EggPlacement.check(0 / 0, 0, "normal", {}))
			T.falsy(EggPlacement.check(math.huge, 0, "normal", {}))
			-- 알끼리
			local placed = { { x = 0, z = 0, size = "normal" } }
			ok, reason = EggPlacement.check(0, 3.99, "normal", placed)
			T.falsy(ok)
			T.eq(reason, "tooClose")
			T.truthy(EggPlacement.check(0, 4, "normal", placed), "딱 4")
			T.eq(EggPlacement.gap("normal", "normal"), 4)
			T.near(EggPlacement.gap("giant", "giant"), 4.8, 1e-9, "초거대 지름 4.8")
			T.near(EggPlacement.gap("giant", "normal"), 4, 1e-9, "(4.8 + 2) / 2 = 3.4 → 최소 4")
			T.near(EggPlacement.gap("huge", "giant"), 4.2, 1e-9)
			T.eq(EggPlacement.gap("모름", nil), 4)
			local giant = { { x = 0, z = 0, size = "giant" } }
			T.falsy(EggPlacement.check(0, 4.7, "giant", giant))
			T.truthy(EggPlacement.check(0, 4.8, "giant", giant))
			-- 펫 자리
			T.falsy(EggPlacement.check(-20, 0, "normal", {}, { { x = -20, z = 3 } }))
			T.truthy(EggPlacement.check(-20, 0, "normal", {}, { { x = -20, z = 4 } }))
			T.eq(EggPlacement.round(-12.34), -12.3)
			T.eq(EggPlacement.round(5.06), 5.1)
		end
	)

	T.test("firstFreeGrid: 빈 격자 첫 자리, 다 차면 nil / 안내 글", function()
		local placed = {}
		for i = 1, MapLayout.EGG_GRID_COUNT do
			local s = EggPlacement.firstFreeGrid("giant", placed)
			T.eq(s.x, MapLayout.eggGridLocal(i).x, "칸 " .. i)
			T.eq(s.z, MapLayout.eggGridLocal(i).z)
			table.insert(placed, { x = s.x, z = s.z, size = "giant" })
		end
		T.eq(EggPlacement.firstFreeGrid("normal", placed), nil)
		T.truthy(string.find(EggPlacement.message("full"), "8개까지", 1, true))
		T.truthy(string.find(EggPlacement.message("outside"), "우리", 1, true))
		T.truthy(string.find(EggPlacement.message("tooClose"), "가까워요", 1, true))
		T.truthy(#EggPlacement.message(nil) > 0)
	end)

	T.test(
		"nestsFor: 구역마다 8개, 구역 안, 벽·경계에서 20 이상, 서로 20 이상, 경비 집에서 60 이상",
		function()
			for _, b in MapLayout.biomes do
				local nests = MapLayout.nestsFor(b.id)
				T.eq(#nests, 8, b.id)
				local home = MapLayout.guardHome(b.id)
				T.eq(MapLayout.zoneAt(home.z), b.id)
				T.truthy(math.abs(home.z - b.centerZ) <= 30, "경비 집 중앙 근처")
				for a, n in nests do
					T.eq(MapLayout.zoneAt(n.z), b.id, b.id .. " 둥지 구역")
					T.truthy(110 - math.abs(n.x) >= 20, "벽에서 20 " .. b.id)
					T.truthy(n.z - b.zMin >= 20 and b.zMax - n.z >= 20, "경계에서 20 " .. b.id)
					T.truthy(math.sqrt((n.x - home.x) ^ 2 + (n.z - home.z) ^ 2) >= 60, "경비 집과 거리")
					for c, m in nests do
						if a ~= c then
							T.truthy(math.sqrt((n.x - m.x) ^ 2 + (n.z - m.z) ^ 2) >= 20, "둥지 간격")
						end
					end
				end
			end
			T.eq(#MapLayout.nestsFor("nope"), 0)
			T.eq(MapLayout.guardHome("nope"), nil)
		end
	)

	T.test("특수 장소·허브 시설: 자기 구역/허브 안", function()
		for name, s in MapLayout.specials do
			T.eq(MapLayout.zoneAt(s.z), s.biomeId, name)
			T.truthy(math.abs(s.x) < 110, name)
		end
		T.eq(MapLayout.specials.sakuraIncubator.biomeId, "cherry_blossom")
		T.eq(MapLayout.specials.questGate.biomeId, "enchanted_forest")
		for name, s in MapLayout.hubSpots do
			if name ~= "safeLine" then
				T.truthy(MapLayout.isInHub(s), name)
				T.eq(MapLayout.plotAt(s), nil, name .. " 베이스 밖")
			end
		end
	end)
end
