--!strict
--[[
	MapLayout — 송판 깨기 맵 자리 (선임, 순수 데이터 · 서버 수석 코드도 읽음). 단위 = 스터드, 바닥 윗면 y = 0.

	크기 (사장님 결정 13번, shared/Data/Sizes): 월드 w 는 월드 1 배치를 통째로 Sizes.worldScale(w) 배 (월드 1 = 1 · 2 ≈ 5.5 · 3 ≈ 11).
	  아래 상수(LOBBY_HALF · ROAD_HALF · MAT_SIZE · REACH_MARGIN …)는 배율 1 (월드 1) 값. 함수가 돌려주는 자리·크기·거리는 전부
	  그 월드 배율을 곱한 진짜 값 (원점 기준 거리 × 배율, 높이 × 배율, 크기 × 배율, targetReach 여유까지).
	  MapLayout.worldScale(world) → 그 배율 · MapLayout.scaled(world, n) → n × 배율
	  MapLayout.base → 같은 함수들의 "배율 1" 판 (원점은 같음). 맵 짓는 쪽(MapBuilder)은 base 로 지은 뒤 월드를 통째로 키움.

	월드 원점: 월드 w 의 원점 = (ORIGIN_X[w], 0, 0). 큰 월드끼리 안 겹치고 서로 안 보이게 x 로 멀리 띄움 (smoke_visuals 가 검사).
	월드마다 (원점 기준, 배율 1 숫자):
	  로비(도장) x -50..50, z -50..50 — 스폰 (0, -36) · 수련 매트 6칸(왼쪽) · 아령 가게(오른쪽 뒤) · 띠 표지판(오른쪽 벽)
	            · 심사대(오른쪽 앞) · 대결장(왼쪽 앞) · 뒤쪽 벽에 다른 월드로 가는 문 2개 · 앞쪽 벽(z = 50) 가운데 정문
	  물건 줄 z 66 부터 +z 로: 가운데 길(x -7..7) 양옆에 번갈아 (홀수 번째 왼쪽, 짝수 번째 오른쪽).
	            뒤 물건일수록 크고(반지름 r) 로비에서 멀어짐.

	수석이 쓰는 함수 (이름 고정, 설계서 7장):
	  MapLayout.targetPosition(id) → {x, y, z}?   물건 바닥 가운데 (월드 3 은 떠 있는 받침대 윗면)
	  MapLayout.targetReach(id)    → number       이 수평 거리 안이면 칠 수 있음 ((반지름 × FOOTPRINT 1.35 + 여유 8) × 배율)
	  MapLayout.isOnTrainMat(pos, world) → boolean  pos 는 Vector3 또는 {x,y,z} (캐릭터 HumanoidRootPart 위치면 됨)
	                                                 도장 매트 6칸 + 길가 매트(물건마다 1칸) 모두 인정.
	                                                 높이 창 = 바닥 -3·배율 ~ +10·배율 (큰 몸은 수석 SizeService 가 뿌리 높이를 내려서 다시 물음)
	  MapLayout.matPoint(id) → {x, y, z}?          그 물건 옆 길가 매트 가운데
	  MapLayout.matWalkDistance(id) → number       매트 가운데 → 칠 수 있는 가장 가까운 자리 (수평, 바로 치면 0)
	  MapLayout.spawn(world) / examPad(world) / duelArena(world) → Spot (x, y, z + 크기·방향)
	그 밖: worldOrigin · worldAt · worldScale · scaled · targetIds · targetRadius · targetWorld · trainMats · roadMats · dumbbellShop
	      · beltBoard · doors · doorAt · lobbyRect · targetArea · worldRect · roadPoint
]]

local Sizes = require(script.Parent.Sizes)

local MapLayout = {}

export type XYZ = { x: number, y: number, z: number }
-- yaw: 앞면이 보는 방향 (라디안, 0 = +z, π/2 = +x). sizeX/sizeZ = 바닥 넓이
export type Spot = { x: number, y: number, z: number, sizeX: number, sizeZ: number, yaw: number }
export type DuelSpot = {
	x: number,
	y: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	yaw: number,
	player: XYZ, -- 내 송판 줄 가운데
	examiner: XYZ, -- 시험관 송판 줄 가운데
	boards: number, -- 줄마다 송판 수 (15)
}
-- 문: 자리 + 들어가면 바로 이동하는 칸 (사장님 결정 15번). 칸 = 문 가운데에서 x ±halfX, z = z + front ~ z + back (front < 0 = 벽 쪽)
export type Door = {
	world: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	halfX: number,
	front: number,
	back: number,
}
export type Rect = { x0: number, x1: number, z0: number, z1: number }
export type RoadMat = Spot & { targetId: string }

MapLayout.WORLD_COUNT = 3
-- 월드 원점 x. 월드 3 (배율 ≈ 11) 은 x 로 약 ±2,400 · z 로 약 -1,000 ~ 6,000 까지 → 이웃 월드와 5,000 스터드 넘게 떨어지게
MapLayout.ORIGIN_X = { 0, 10000, 30000 }
MapLayout.WORLD_SPACING = 10000 -- (옛 이름 — 원점 사이 간격은 ORIGIN_X 가 기준)
MapLayout.FLOOR_Y = 0
MapLayout.LOBBY_HALF = 50 -- 로비 x·z 반 너비 (배율 1)
MapLayout.ROAD_HALF = 7 -- 물건 줄 가운데 길 반 너비 (배율 1)
MapLayout.ROAD_GAP = 3 -- 길 끝 ~ 물건 가장자리
MapLayout.TARGET_START_Z = 66
MapLayout.SAME_SIDE_GAP = 10 -- 같은 쪽 물건 사이 여유
MapLayout.REACH_MARGIN = 8 -- targetReach = (반지름 × FOOTPRINT + 이것) × 배율
MapLayout.FOOTPRINT = 1.35 -- 네모난 물건(피라미드·댐…)의 모서리까지: 반지름 × 이것 (자리 간격·길 여유·reach 에 씀)
MapLayout.MAT_SIZE = 10
MapLayout.MAT_HEIGHT = 0.6
MapLayout.PEDESTAL_TOP = 3 -- 월드 3 떠 있는 받침대 윗면 높이 (배율 1)
MapLayout.DUEL_BOARDS = 15
MapLayout.EXAM_BOARDS = 10
-- 매트 가장자리 여유 (스터드, 배율 없음 — 뿌리 파트가 매트 밖으로 조금 나가도 인정)
MapLayout.MAT_EDGE = 1

-- 설계서 3장 순서 그대로 (Targets 표와 1:1 — smoke_visuals 가 검사)
MapLayout.TARGET_IDS = {
	{
		"cotton",
		"glass",
		"plastic",
		"wood",
		"iron",
		"steel",
		"rubber",
		"computer",
		"phone",
		"overpass",
		"apartment",
		"school",
		"stadium",
	},
	{
		"mall",
		"skyscraper",
		"bridge",
		"dam",
		"airplane",
		"carrier",
		"tower",
		"pyramid",
		"mountain",
		"volcano",
		"glacier",
		"island",
		"continent",
		"ocean",
	},
	{
		"moon",
		"mercury",
		"mars",
		"venus",
		"earth",
		"neptune",
		"uranus",
		"saturn",
		"jupiter",
		"sun",
		"solar_system",
		"galaxy",
		"black_hole",
		"universe",
	},
} :: { { string } }

-- 월드별 물건 반지름 (배율 1, 첫 물건 → 마지막 물건, 그 사이는 고르게)
local RADIUS: { { number } } = {
	{ 2.5, 16 },
	{ 8, 24 },
	{ 6, 30 },
}

local function clampWorld(world: number): number
	return math.clamp(math.floor(tonumber(world) or 1), 1, MapLayout.WORLD_COUNT)
end

------------------------------------------------------------------
-- 배율 1 (월드 원점 기준 "로컬" 숫자) 표 — 모듈을 불러올 때 한 번
------------------------------------------------------------------

-- lx/lz: 원점 기준 로컬 자리 (배율 1), r: 배율 1 반지름, ly: 배율 1 높이
type LocalTarget = {
	id: string,
	world: number,
	order: number,
	side: number,
	r: number,
	lx: number,
	ly: number,
	lz: number,
}

local localSpots: { [string]: LocalTarget } = {}
local localOrder: { [number]: { LocalTarget } } = {}

for w, ids in MapLayout.TARGET_IDS do
	local list: { LocalTarget } = {}
	local r0, r1 = RADIUS[w][1], RADIUS[w][2]
	local cursor: { [number]: number } = { [-1] = MapLayout.TARGET_START_Z, [1] = MapLayout.TARGET_START_Z }
	local lastZ = MapLayout.TARGET_START_Z - 8
	for i, id in ids do
		local t = if #ids > 1 then (i - 1) / (#ids - 1) else 0
		local r = r0 + (r1 - r0) * t
		local side = if i % 2 == 1 then -1 else 1
		local foot = r * MapLayout.FOOTPRINT
		local z = math.max(cursor[side] + foot, lastZ + 8)
		cursor[side] = z + foot + MapLayout.SAME_SIDE_GAP
		lastZ = z
		local spot: LocalTarget = {
			id = id,
			world = w,
			order = i,
			side = side,
			r = r,
			lx = side * (MapLayout.ROAD_HALF + MapLayout.ROAD_GAP + foot),
			ly = if w == 3 then MapLayout.PEDESTAL_TOP else 0,
			lz = z,
		}
		localSpots[id] = spot
		table.insert(list, spot)
	end
	localOrder[w] = list
end

local FACE_LEFT = -math.pi / 2 -- 앞면이 -x (가운데 통로) 를 봄
local FACE_RIGHT = math.pi / 2

-- 도장 매트 6칸 (로컬 x, z)
local MATS: { { number } } = { { -40, -24 }, { -26, -24 }, { -40, -9 }, { -26, -9 }, { -40, 6 }, { -26, 6 } }

------------------------------------------------------------------
-- 길가 수련 매트 (물건 41개마다 1칸): 그 물건 쪽 길 절반 위, 물건과 같은 z (= 치는 자리 바로 그곳)
--   x: 길 가운데에서 ROAD_MAT_CENTER (가운데 4 스터드는 비워 둠, 길 가장자리 줄과도 안 겹침)
--   매트 가운데에 서면 그 물건이 targetReach 안 → 걷지 않고 들기·치기 둘 다 (matWalkDistance 0)
--   얇은 판(안 부딪힘)이라 길을 막지 않음
------------------------------------------------------------------

MapLayout.ROAD_MAT_X = 4.5 -- 길 가로 방향 크기 (배율 1)
MapLayout.ROAD_MAT_Z = 6 -- 길 따라 크기
MapLayout.ROAD_MAT_CENTER = 4.2 -- 길 가운데 ~ 매트 가운데

-- 다른 월드로 가는 문 (뒤쪽 벽 z = -50 안쪽). 들어가면 바로 이동하는 칸 (배율 1): 문틀 안쪽 폭 ±3.5, 문 면 앞 0.8 ~ 벽 쪽 2
MapLayout.DOOR_HALF_X = 3.5
MapLayout.DOOR_FRONT = 0.8 -- 문 자리(z)에서 방 안쪽(+z)으로
MapLayout.DOOR_BACK = 2 -- 문 자리에서 벽 쪽(-z)으로
-- 몸 반지름 어림 (뿌리 가운데 ~ 몸 앞면): 배율 1 몸 = 0.6 스터드. 큰 몸은 × BodyScale
MapLayout.BODY_RADIUS = 0.6

local function readXYZ(pos: any): (number, number, number)
	if type(pos) == "table" then
		local x = tonumber(pos.x or pos.X) or 0
		local y = tonumber(pos.y or pos.Y) or 0
		local z = tonumber(pos.z or pos.Z) or 0
		return x, y, z
	end
	return pos.X, pos.Y, pos.Z
end

------------------------------------------------------------------
-- 함수 묶음 만들기: scaleOf(world) 로 배율을 정함 (진짜 = Sizes.worldScale · base = 1)
------------------------------------------------------------------

local function makeView(scaleOf: (number) -> number)
	local L = {}

	local function S(world: number): number
		return scaleOf(clampWorld(world))
	end

	local function ox(world: number): number
		return MapLayout.ORIGIN_X[clampWorld(world)]
	end

	-- 로컬 (배율 1) → 월드 좌표 (배율 곱함)
	local function at(world: number, lx: number, ly: number, lz: number): XYZ
		local s = S(world)
		return { x = ox(world) + lx * s, y = MapLayout.FLOOR_Y + ly * s, z = lz * s }
	end

	function L.worldScale(world: number): number
		return S(world)
	end

	function L.scaled(world: number, n: number): number
		return n * S(world)
	end

	function L.worldOrigin(world: number): XYZ
		return { x = ox(world), y = MapLayout.FLOOR_Y, z = 0 }
	end

	-- 이 위치는 몇 번 월드 땅인가 (x 로만. 이웃 원점 사이 한가운데에서 나뉨)
	function L.worldAt(pos: any): number
		local ok, x = pcall(readXYZ, pos)
		if not ok or type(x) ~= "number" or x ~= x then
			return 1
		end
		local o = MapLayout.ORIGIN_X
		for w = 1, MapLayout.WORLD_COUNT - 1 do
			if x < (o[w] + o[w + 1]) / 2 then
				return w
			end
		end
		return MapLayout.WORLD_COUNT
	end

	--------------------------------------------------------------
	-- 물건
	--------------------------------------------------------------

	function L.targetIds(world: number): { string }
		return table.clone(MapLayout.TARGET_IDS[clampWorld(world)])
	end

	function L.targetPosition(id: string): XYZ?
		local s = localSpots[id]
		if not s then
			return nil
		end
		return at(s.world, s.lx, s.ly, s.lz)
	end

	-- 물건 크기 (바닥에서 차지하는 반지름, 배율 곱함). 모르는 id 는 0
	function L.targetRadius(id: string): number
		local s = localSpots[id]
		return if s then s.r * S(s.world) else 0
	end

	-- 칠 수 있는 수평 거리 (물건 가운데에서). 모르는 id 는 0 (= 못 침)
	function L.targetReach(id: string): number
		local s = localSpots[id]
		return if s then (s.r * MapLayout.FOOTPRINT + MapLayout.REACH_MARGIN) * S(s.world) else 0
	end

	function L.targetWorld(id: string): number?
		local s = localSpots[id]
		return if s then s.world else nil
	end

	-- 물건이 길의 어느 쪽인가 (-1 왼쪽, 1 오른쪽). 표지판·글이 길 쪽을 보게
	function L.targetSide(id: string): number
		local s = localSpots[id]
		return if s then s.side else 1
	end

	-- 그 물건 앞 길 위 설 자리 (치기 좋은 곳)
	function L.roadPoint(id: string): XYZ?
		local s = localSpots[id]
		if not s then
			return nil
		end
		return at(s.world, s.side * (MapLayout.ROAD_HALF - 2), 0, s.lz)
	end

	--------------------------------------------------------------
	-- 로비 (도장)
	--------------------------------------------------------------

	local function spot(world: number, lx: number, lz: number, sizeX: number, sizeZ: number, yaw: number): Spot
		local s = S(world)
		local p = at(world, lx, 0, lz)
		return { x = p.x, y = p.y, z = p.z, sizeX = sizeX * s, sizeZ = sizeZ * s, yaw = yaw }
	end

	function L.spawn(world: number): Spot
		return spot(world, 0, -36, 10, 10, 0)
	end

	function L.trainMats(world: number): { Spot }
		local list: { Spot } = {}
		for _, m in MATS do
			table.insert(list, spot(world, m[1], m[2], MapLayout.MAT_SIZE, MapLayout.MAT_SIZE, FACE_RIGHT))
		end
		return list
	end

	local function roadMatOf(s: LocalTarget): RoadMat
		local m = spot(
			s.world,
			s.side * MapLayout.ROAD_MAT_CENTER,
			s.lz,
			MapLayout.ROAD_MAT_X,
			MapLayout.ROAD_MAT_Z,
			if s.side < 0 then FACE_LEFT else FACE_RIGHT
		)
		return {
			x = m.x,
			y = m.y,
			z = m.z,
			sizeX = m.sizeX,
			sizeZ = m.sizeZ,
			yaw = m.yaw,
			targetId = s.id,
		}
	end

	-- 월드의 길가 매트 (물건 순서대로)
	function L.roadMats(world: number): { RoadMat }
		local list: { RoadMat } = {}
		for _, s in localOrder[clampWorld(world)] do
			table.insert(list, roadMatOf(s))
		end
		return list
	end

	-- 그 물건 옆 매트 가운데 (모르는 id 는 nil)
	function L.matPoint(targetId: string): XYZ?
		local s = localSpots[targetId]
		if not s then
			return nil
		end
		local m = roadMatOf(s)
		return { x = m.x, y = m.y, z = m.z }
	end

	-- 매트 가운데 → 그 물건을 칠 수 있는 가장 가까운 자리까지 수평 거리 (매트에서 바로 치면 0, 모르는 id 는 math.huge)
	function L.matWalkDistance(targetId: string): number
		local s = localSpots[targetId]
		if not s then
			return math.huge
		end
		local m = roadMatOf(s)
		local p = at(s.world, s.lx, s.ly, s.lz)
		local d = math.sqrt((m.x - p.x) ^ 2 + (m.z - p.z) ^ 2)
		return math.max(0, d - L.targetReach(targetId))
	end

	local function onSpot(x: number, z: number, m: Spot): boolean
		return math.abs(x - m.x) <= m.sizeX / 2 + MapLayout.MAT_EDGE
			and math.abs(z - m.z) <= m.sizeZ / 2 + MapLayout.MAT_EDGE
	end

	-- 수련 매트 위인가 — 도장 매트 + 길가 매트 (가장자리 1 스터드 여유).
	--   높이: 바닥 -3·배율 ~ +10·배율 (캐릭터 몸 가운데까지. 큰 몸은 SizeService.isOnTrainMat · 클라 TrainController 가 뿌리를 내려서 물음)
	function L.isOnTrainMat(pos: any, world: number): boolean
		if pos == nil then
			return false
		end
		local ok, x, y, z = pcall(readXYZ, pos)
		if not ok then
			return false
		end
		local s = S(world)
		if y < MapLayout.FLOOR_Y - 3 * s or y > MapLayout.FLOOR_Y + 10 * s then
			return false
		end
		for _, m in L.trainMats(world) do
			if onSpot(x, z, m) then
				return true
			end
		end
		for _, s2 in localOrder[clampWorld(world)] do
			if onSpot(x, z, roadMatOf(s2)) then
				return true
			end
		end
		return false
	end

	function L.dumbbellShop(world: number): Spot
		return spot(world, 36, -30, 10, 18, FACE_LEFT)
	end

	function L.beltBoard(world: number): Spot
		return spot(world, 47, -2, 2, 24, FACE_LEFT)
	end

	function L.examPad(world: number): Spot
		return spot(world, 30, 30, 16, 14, FACE_LEFT)
	end

	function L.duelArena(world: number): DuelSpot
		local base = spot(world, -30, 32, 34, 22, FACE_RIGHT)
		local s = S(world)
		return {
			x = base.x,
			y = base.y,
			z = base.z,
			sizeX = base.sizeX,
			sizeZ = base.sizeZ,
			yaw = base.yaw,
			player = { x = base.x, y = base.y, z = base.z - 5 * s },
			examiner = { x = base.x, y = base.y, z = base.z + 5 * s },
			boards = MapLayout.DUEL_BOARDS,
		}
	end

	-- 다른 월드로 가는 문 (뒤쪽 벽 z = -50 안쪽). 내 월드를 뺀 나머지를 번호 순으로 왼쪽(-24) · 오른쪽(24)
	function L.doors(world: number): { Door }
		local w = clampWorld(world)
		local s = S(w)
		local list: { Door } = {}
		local xs = { -24, 24 }
		local k = 0
		for other = 1, MapLayout.WORLD_COUNT do
			if other ~= w then
				k += 1
				local p = at(w, xs[k] or 0, 0, -48)
				table.insert(list, {
					world = other,
					x = p.x,
					y = p.y,
					z = p.z,
					yaw = 0,
					halfX = MapLayout.DOOR_HALF_X * s,
					front = MapLayout.DOOR_FRONT * s,
					back = -MapLayout.DOOR_BACK * s,
				})
			end
		end
		return list
	end

	-- 이 자리(뿌리 파트)가 어느 문 안인가 → 가는 월드 번호 (아니면 nil). 사장님 결정 15번: 문에 들어가면 바로 이동.
	--   몸이 크면 몸 반지름(BODY_RADIUS × bodyScale)만큼 칸을 넓힘 (문보다 큰 거인도 몸이 문에 닿으면 들어감)
	--   높이: 바닥 -3·배율 ~ 문 높이(10.4·배율) + 몸 높이 (뿌리가 문 위로 솟은 거인도)
	function L.doorAt(pos: any, world: number, bodyScale: number?): number?
		if pos == nil then
			return nil
		end
		local ok, x, y, z = pcall(readXYZ, pos)
		if not ok then
			return nil
		end
		local s = S(world)
		local body = math.max(1, tonumber(bodyScale) or 1)
		local pad = MapLayout.BODY_RADIUS * body
		if y < MapLayout.FLOOR_Y - 3 * s or y > MapLayout.FLOOR_Y + 10.4 * s + 6 * body then
			return nil
		end
		for _, d in L.doors(world) do
			if math.abs(x - d.x) <= d.halfX + pad and z >= d.z + d.back - pad and z <= d.z + d.front + pad then
				return d.world
			end
		end
		return nil
	end

	-- 로비 바닥 (월드 좌표)
	function L.lobbyRect(world: number): Rect
		local h = MapLayout.LOBBY_HALF * S(world)
		local o = ox(world)
		return { x0 = o - h, x1 = o + h, z0 = -h, z1 = h }
	end

	-- 물건 줄 바닥 (월드 좌표): 가장 큰 물건 + 여유까지
	function L.targetArea(world: number): Rect
		local w = clampWorld(world)
		local s = S(w)
		local maxX, maxZ = MapLayout.LOBBY_HALF, MapLayout.TARGET_START_Z
		for _, t in localOrder[w] do
			maxX = math.max(maxX, math.abs(t.lx) + t.r * MapLayout.FOOTPRINT + 12)
			maxZ = math.max(maxZ, t.lz + t.r * MapLayout.FOOTPRINT + 20)
		end
		local o = ox(w)
		return { x0 = o - maxX * s, x1 = o + maxX * s, z0 = MapLayout.LOBBY_HALF * s, z1 = maxZ * s }
	end

	-- 월드 땅 전체 (로비 + 물건 줄 + 둘레 40) — 바닥 판 · 장식 범위
	function L.worldRect(world: number): Rect
		local s = S(world)
		local area = L.targetArea(world)
		local lobby = L.lobbyRect(world)
		return {
			x0 = math.min(area.x0, lobby.x0) - 40 * s,
			x1 = math.max(area.x1, lobby.x1) + 40 * s,
			z0 = lobby.z0 - 40 * s,
			z1 = area.z1 + 30 * s,
		}
	end

	return L
end

local real = makeView(function(world: number): number
	return Sizes.worldScale(world)
end)

-- 진짜 (배율 곱한) 함수들 — 이름 고정 (설계서 7장)
MapLayout.worldScale = real.worldScale
MapLayout.scaled = real.scaled
MapLayout.worldOrigin = real.worldOrigin
MapLayout.worldAt = real.worldAt
MapLayout.targetIds = real.targetIds
MapLayout.targetPosition = real.targetPosition
MapLayout.targetRadius = real.targetRadius
MapLayout.targetReach = real.targetReach
MapLayout.targetWorld = real.targetWorld
MapLayout.targetSide = real.targetSide
MapLayout.roadPoint = real.roadPoint
MapLayout.spawn = real.spawn
MapLayout.trainMats = real.trainMats
MapLayout.roadMats = real.roadMats
MapLayout.matPoint = real.matPoint
MapLayout.matWalkDistance = real.matWalkDistance
MapLayout.isOnTrainMat = real.isOnTrainMat
MapLayout.dumbbellShop = real.dumbbellShop
MapLayout.beltBoard = real.beltBoard
MapLayout.examPad = real.examPad
MapLayout.duelArena = real.duelArena
MapLayout.doors = real.doors
MapLayout.doorAt = real.doorAt
MapLayout.lobbyRect = real.lobbyRect
MapLayout.targetArea = real.targetArea
MapLayout.worldRect = real.worldRect

-- 배율 1 판 (원점은 같음, 함수 이름도 같음). 맵 짓기용 — 서버 판정·화면은 MapLayout 그대로 씀
MapLayout.base = makeView(function(_world: number): number
	return 1
end)

return MapLayout
