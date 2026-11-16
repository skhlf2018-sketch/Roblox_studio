--!strict
--[[
	MapLayout — 송판 깨기 맵 자리 (선임, 순수 데이터 · 서버 수석 코드도 읽음). 단위 = 스터드, 바닥 윗면 y = 0.

	월드 3개를 x 로 2,000 스터드씩 떨어뜨림: 월드 w 의 원점 = (2000·(w-1), 0, 0).
	월드마다 (원점 기준):
	  로비(도장) x -50..50, z -50..50 — 스폰 (0, -36) · 수련 매트 6칸(왼쪽) · 아령 가게(오른쪽 뒤) · 띠 표지판(오른쪽 벽)
	            · 심사대(오른쪽 앞) · 대결장(왼쪽 앞) · 뒤쪽 벽에 다른 월드로 가는 문 2개 · 앞쪽 벽(z = 50) 가운데 정문
	  물건 줄 z 66 부터 +z 로: 가운데 길(x -7..7) 양옆에 번갈아 (홀수 번째 왼쪽, 짝수 번째 오른쪽).
	            뒤 물건일수록 크고(반지름 r) 로비에서 멀어짐.

	수석이 쓰는 함수 (이름 고정, 설계서 7장):
	  MapLayout.targetPosition(id) → {x, y, z}?   물건 바닥 가운데 (월드 3 은 떠 있는 받침대 윗면)
	  MapLayout.targetReach(id)    → number       이 수평 거리 안이면 칠 수 있음 (반지름 × FOOTPRINT 1.35 + 여유 8)
	  MapLayout.isOnTrainMat(pos, world) → boolean  pos 는 Vector3 또는 {x,y,z} (캐릭터 HumanoidRootPart 위치면 됨)
	  MapLayout.spawn(world) / examPad(world) / duelArena(world) → Spot (x, y, z + 크기·방향)
	그 밖: worldOrigin · worldAt · targetIds · targetRadius · targetWorld · trainMats · dumbbellShop · beltBoard · doors
	      · lobbyRect · targetArea · roadPoint
]]

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
export type Door = { world: number, x: number, y: number, z: number, yaw: number }
export type Rect = { x0: number, x1: number, z0: number, z1: number }

MapLayout.WORLD_COUNT = 3
MapLayout.WORLD_SPACING = 2000
MapLayout.FLOOR_Y = 0
MapLayout.LOBBY_HALF = 50 -- 로비 x·z 반 너비
MapLayout.ROAD_HALF = 7 -- 물건 줄 가운데 길 반 너비
MapLayout.ROAD_GAP = 3 -- 길 끝 ~ 물건 가장자리
MapLayout.TARGET_START_Z = 66
MapLayout.SAME_SIDE_GAP = 10 -- 같은 쪽 물건 사이 여유
MapLayout.REACH_MARGIN = 8 -- targetReach = 반지름 × FOOTPRINT + 이것
MapLayout.FOOTPRINT = 1.35 -- 네모난 물건(피라미드·댐…)의 모서리까지: 반지름 × 이것 (자리 간격·길 여유·reach 에 씀)
MapLayout.MAT_SIZE = 10
MapLayout.MAT_HEIGHT = 0.6
MapLayout.PEDESTAL_TOP = 3 -- 월드 3 떠 있는 받침대 윗면 높이
MapLayout.DUEL_BOARDS = 15
MapLayout.EXAM_BOARDS = 10

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

-- 월드별 물건 반지름 (첫 물건 → 마지막 물건, 그 사이는 고르게)
local RADIUS: { { number } } = {
	{ 2.5, 16 },
	{ 8, 24 },
	{ 6, 30 },
}

type TargetSpot = { id: string, world: number, order: number, side: number, r: number, pos: XYZ }

local spots: { [string]: TargetSpot } = {}
local order: { [number]: { TargetSpot } } = {}

local function clampWorld(world: number): number
	return math.clamp(math.floor(tonumber(world) or 1), 1, MapLayout.WORLD_COUNT)
end

function MapLayout.worldOrigin(world: number): XYZ
	local w = clampWorld(world)
	return { x = (w - 1) * MapLayout.WORLD_SPACING, y = MapLayout.FLOOR_Y, z = 0 }
end

local function ox(world: number): number
	return MapLayout.worldOrigin(world).x
end

-- 표 만들기 (모듈을 불러올 때 한 번)
for w, ids in MapLayout.TARGET_IDS do
	local list: { TargetSpot } = {}
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
		local x = side * (MapLayout.ROAD_HALF + MapLayout.ROAD_GAP + foot)
		local y = if w == 3 then MapLayout.PEDESTAL_TOP else MapLayout.FLOOR_Y
		local spot: TargetSpot = {
			id = id,
			world = w,
			order = i,
			side = side,
			r = r,
			pos = { x = ox(w) + x, y = y, z = z },
		}
		spots[id] = spot
		table.insert(list, spot)
	end
	order[w] = list
end

------------------------------------------------------------------
-- 물건
------------------------------------------------------------------

function MapLayout.targetIds(world: number): { string }
	return table.clone(MapLayout.TARGET_IDS[clampWorld(world)])
end

function MapLayout.targetPosition(id: string): XYZ?
	local s = spots[id]
	if not s then
		return nil
	end
	return { x = s.pos.x, y = s.pos.y, z = s.pos.z }
end

-- 물건 크기 (바닥에서 차지하는 반지름). 모르는 id 는 0
function MapLayout.targetRadius(id: string): number
	local s = spots[id]
	return if s then s.r else 0
end

-- 칠 수 있는 수평 거리 (물건 가운데에서). 모르는 id 는 0 (= 못 침)
function MapLayout.targetReach(id: string): number
	local s = spots[id]
	return if s then s.r * MapLayout.FOOTPRINT + MapLayout.REACH_MARGIN else 0
end

function MapLayout.targetWorld(id: string): number?
	local s = spots[id]
	return if s then s.world else nil
end

-- 물건이 길의 어느 쪽인가 (-1 왼쪽, 1 오른쪽). 표지판·글이 길 쪽을 보게
function MapLayout.targetSide(id: string): number
	local s = spots[id]
	return if s then s.side else 1
end

-- 그 물건 앞 길 위 설 자리 (치기 좋은 곳)
function MapLayout.roadPoint(id: string): XYZ?
	local s = spots[id]
	if not s then
		return nil
	end
	return { x = ox(s.world) + s.side * (MapLayout.ROAD_HALF - 2), y = MapLayout.FLOOR_Y, z = s.pos.z }
end

------------------------------------------------------------------
-- 로비 (도장)
------------------------------------------------------------------

local function spot(world: number, x: number, z: number, sizeX: number, sizeZ: number, yaw: number): Spot
	return { x = ox(world) + x, y = MapLayout.FLOOR_Y, z = z, sizeX = sizeX, sizeZ = sizeZ, yaw = yaw }
end

local FACE_LEFT = -math.pi / 2 -- 앞면이 -x (가운데 통로) 를 봄
local FACE_RIGHT = math.pi / 2

function MapLayout.spawn(world: number): Spot
	return spot(world, 0, -36, 10, 10, 0)
end

local MATS: { { number } } = { { -40, -24 }, { -26, -24 }, { -40, -9 }, { -26, -9 }, { -40, 6 }, { -26, 6 } }

function MapLayout.trainMats(world: number): { Spot }
	local list: { Spot } = {}
	for _, m in MATS do
		table.insert(list, spot(world, m[1], m[2], MapLayout.MAT_SIZE, MapLayout.MAT_SIZE, FACE_RIGHT))
	end
	return list
end

local function readXYZ(pos: any): (number, number, number)
	if type(pos) == "table" then
		local x = tonumber(pos.x or pos.X) or 0
		local y = tonumber(pos.y or pos.Y) or 0
		local z = tonumber(pos.z or pos.Z) or 0
		return x, y, z
	end
	return pos.X, pos.Y, pos.Z
end

-- 수련 매트 위인가 (가장자리 1 스터드 여유, 높이는 바닥 -3 ~ +10: 캐릭터 몸 가운데까지)
function MapLayout.isOnTrainMat(pos: any, world: number): boolean
	if pos == nil then
		return false
	end
	local ok, x, y, z = pcall(readXYZ, pos)
	if not ok then
		return false
	end
	if y < MapLayout.FLOOR_Y - 3 or y > MapLayout.FLOOR_Y + 10 then
		return false
	end
	for _, m in MapLayout.trainMats(world) do
		if math.abs(x - m.x) <= m.sizeX / 2 + 1 and math.abs(z - m.z) <= m.sizeZ / 2 + 1 then
			return true
		end
	end
	return false
end

function MapLayout.dumbbellShop(world: number): Spot
	return spot(world, 36, -30, 10, 18, FACE_LEFT)
end

function MapLayout.beltBoard(world: number): Spot
	return spot(world, 47, -2, 2, 24, FACE_LEFT)
end

function MapLayout.examPad(world: number): Spot
	return spot(world, 30, 30, 16, 14, FACE_LEFT)
end

function MapLayout.duelArena(world: number): DuelSpot
	local base = spot(world, -30, 32, 34, 22, FACE_RIGHT)
	return {
		x = base.x,
		y = base.y,
		z = base.z,
		sizeX = base.sizeX,
		sizeZ = base.sizeZ,
		yaw = base.yaw,
		player = { x = base.x, y = base.y, z = base.z - 5 },
		examiner = { x = base.x, y = base.y, z = base.z + 5 },
		boards = MapLayout.DUEL_BOARDS,
	}
end

-- 다른 월드로 가는 문 (뒤쪽 벽 z = -50 안쪽). 내 월드를 뺀 나머지를 번호 순으로 왼쪽(-24) · 오른쪽(24)
function MapLayout.doors(world: number): { Door }
	local w = clampWorld(world)
	local list: { Door } = {}
	local xs = { -24, 24 }
	local k = 0
	for other = 1, MapLayout.WORLD_COUNT do
		if other ~= w then
			k += 1
			table.insert(list, { world = other, x = ox(w) + (xs[k] or 0), y = MapLayout.FLOOR_Y, z = -48, yaw = 0 })
		end
	end
	return list
end

-- 로비 바닥 (월드 좌표)
function MapLayout.lobbyRect(world: number): Rect
	local h = MapLayout.LOBBY_HALF
	return { x0 = ox(world) - h, x1 = ox(world) + h, z0 = -h, z1 = h }
end

-- 물건 줄 바닥 (월드 좌표): 가장 큰 물건 + 여유까지
function MapLayout.targetArea(world: number): Rect
	local w = clampWorld(world)
	local maxX, maxZ = MapLayout.LOBBY_HALF, MapLayout.TARGET_START_Z
	for _, s in order[w] do
		maxX = math.max(maxX, math.abs(s.pos.x - ox(w)) + s.r * MapLayout.FOOTPRINT + 12)
		maxZ = math.max(maxZ, s.pos.z + s.r * MapLayout.FOOTPRINT + 20)
	end
	return { x0 = ox(w) - maxX, x1 = ox(w) + maxX, z0 = MapLayout.LOBBY_HALF, z1 = maxZ }
end

-- 이 위치는 몇 번 월드 땅인가 (x 로만. 월드 사이 한가운데에서 나뉨)
function MapLayout.worldAt(pos: any): number
	local ok, x = pcall(readXYZ, pos)
	if not ok then
		return 1
	end
	return clampWorld(math.floor((x + MapLayout.WORLD_SPACING / 2) / MapLayout.WORLD_SPACING) + 1)
end

return MapLayout
