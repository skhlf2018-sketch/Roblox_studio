--!strict
--[[
	MapLayout — 2판 맵 배치 (순수 데이터 + 함수, 로블록스 API 없음 → Lune 테스트 가능)

	서버 로직(구역 판정·배달·경비·러닝머신)과 선임 MapBuilder(맵 짓기)·클라(ZoneController)가
	모두 이 모듈 한 곳의 숫자를 씁니다. 좌표는 스터드, 위에서 본 x(좌우) / z(앞뒤).

	위에서 본 모습 (+z 가 "멀리", 복도 폭 220 = x -110 ~ 110, 양옆은 벽 WALL_HEIGHT):

	   z = 3600 ┌──────────── 15 유령 성 ────────────┐  (맵 끝 벽)
	            │                 ...                  │
	   z = 240  ├──────────── 1 숲 (0~240) ──────────┤
	   z = 0    ├═══════ 안전 구역 경계 (밤 벽) ═══════┤  SAFE_ZONE_Z
	            │ [1]  (허브: z -290 ~ 0)        [2]  │  ← 베이스 7개는 허브 양옆 벽에 붙어
	            │ [3]        중앙 스폰            [4]  │     복도 가운데(x=0)를 바라봄
	            │ [5]                             [6]  │
	            │ [7]                    [판매·트레일·포털] │
	   z = -290 └──────────── 허브 뒤 흰 벽 ───────────┘

	베이스(플롯) 하나 (왼쪽 베이스, 복도 쪽 = +x):
	   x=-110 (벽)        x=-64             x=-40 (복도 쪽 앞)
	     ┌──────────────────┬────────────────┐ z = 중심+30
	     │   펫 우리 (pen)   │   앞마당 (yard) │
	     │ petRect(뒤)       │ 러닝머신 v=-19  │
	     │ 알 8개(앞, 울타리쪽)│ 스폰 v=0       │
	     │                  │ 퓨전 v=+19     │
	     └──────────────────┴────────────────┘ z = 중심-30
	   - 깊이(d=70, x 방향) 중 뒤쪽 46 = 우리, 앞쪽 24 = 앞마당. 폭(w=60, z 방향).
	   - 오른쪽 베이스는 x 를 뒤집은 거울 모양 (z 방향 배치는 같음).

	규칙:
	  - z < SAFE_ZONE_Z(0) 이면 허브 = 안전 구역 (경비 추격 끝, 도구 사용 불가, 밤에도 있을 수 있음)
	  - 구역 판정은 z 범위만 봄: zoneAt(z). 구역 사이에 벽·문 없음.
	  - 배달 = 알을 든 채 isInPlot(자기 베이스) 안에 들어오면 자동.
]]

local Biomes = require(script.Parent.Biomes)

export type XZ = { x: number, z: number }
export type Rect = { xMin: number, xMax: number, zMin: number, zMax: number }
export type BiomeRange = {
	id: string,
	index: number,
	zMin: number,
	zMax: number,
	centerZ: number,
	name: string,
	nameEn: string,
}
export type PlotSigns = { owner: XZ, penUpgrade: XZ, treadmillUpgrade: XZ }
export type Plot = {
	index: number,
	side: string, -- "left"(x < 0) | "right"(x > 0)
	center: XZ,
	size: { w: number, d: number }, -- w = z 방향 폭, d = x 방향 깊이(벽 → 복도)
	facing: number, -- +1 = +x 를 바라봄(왼쪽 베이스), -1 = -x 를 바라봄(오른쪽 베이스)
	rect: Rect, -- 베이스 전체 (배달 판정 영역)
	penRect: Rect, -- 펫 우리 (뒤쪽 2/3, 울타리 안)
	yardRect: Rect, -- 앞마당 (복도 쪽 1/3)
	spawn: XZ,
	treadmill: XZ,
	fusion: XZ,
	sellStall: XZ,
	signs: PlotSigns,
}
export type Special = { biomeId: string, x: number, z: number }

local MapLayout = {}

------------------------------------------------------------------
-- 기본 숫자
------------------------------------------------------------------
MapLayout.CORRIDOR_WIDTH = 220 -- x: -110 ~ 110 (벽 안쪽 면)
MapLayout.HALF_WIDTH = 110
MapLayout.WALL_HEIGHT = 60
MapLayout.FLOOR_Y = 0 -- 바닥 윗면 높이 (서버는 레이캐스트로 바닥을 찾으므로 참고용)

-- 허브(안전 구역). 경계선 z = 0. [수석] 베이스 4개가 한쪽(폭 60 × 4 + 간격)에 들어가도록 zMin = -290
MapLayout.HUB = { zMin = -290, zMax = 0 }
MapLayout.SAFE_ZONE_Z = 0

MapLayout.BIOME_LENGTH = 240
MapLayout.BIOME_COUNT = #Biomes.list
MapLayout.MAP_END_Z = MapLayout.BIOME_LENGTH * MapLayout.BIOME_COUNT -- 3600 (맵 끝 벽)

-- 밤 벽: 허브 경계 z = 0 에 한 장 (선임이 NightWall 태그 파트로 만듦)
MapLayout.NIGHT_WALL = { z = 0, xMin = -110, xMax = 110, height = 60, thickness = 2 }

-- 베이스 크기·안쪽 배치 (u = 앞(복도 쪽) 가장자리에서 벽 쪽으로 깊이, v = z 방향 오프셋)
MapLayout.PLOT_SIZE = { w = 60, d = 70 }
MapLayout.PLOT_CENTER_X = 75 -- 왼쪽 -75 / 오른쪽 +75 (벽 -110 에 뒤가 붙음)
MapLayout.YARD_DEPTH = 24 -- 앞마당 깊이 (≈ 1/3)
MapLayout.PEN_DEPTH = 46 -- 우리 깊이 (≈ 2/3)
MapLayout.TREADMILL_PAD = { sizeX = 12, sizeZ = 8 } -- 러닝머신 벨트 (x 방향으로 달림)
MapLayout.EGG_AREA_DEPTH = 16 -- 우리 앞쪽(울타리 쪽) 이 깊이 = 부화 중 알 자리, 그 뒤 = 펫 자리

------------------------------------------------------------------
-- 구역 15개 (Biomes.list 순서: 숲 → … → 유령 성)
------------------------------------------------------------------
local biomes: { BiomeRange } = {}
local biomeById: { [string]: BiomeRange } = {}
for i, b in Biomes.list do
	local zMin = (i - 1) * MapLayout.BIOME_LENGTH
	local range: BiomeRange = {
		id = b.id,
		index = i,
		zMin = zMin,
		zMax = zMin + MapLayout.BIOME_LENGTH,
		centerZ = zMin + MapLayout.BIOME_LENGTH / 2,
		name = b.name,
		nameEn = b.nameEn,
	}
	biomes[i] = range
	biomeById[b.id] = range
end
MapLayout.biomes = biomes

function MapLayout.biome(biomeId: string): BiomeRange?
	return biomeById[biomeId]
end

-- 구역 중심 (x = 0)
function MapLayout.biomeCenter(biomeId: string): XZ?
	local b = biomeById[biomeId]
	if not b then
		return nil
	end
	return { x = 0, z = b.centerZ }
end

------------------------------------------------------------------
-- 사각형 도우미
------------------------------------------------------------------
local function rect(xMin: number, xMax: number, zMin: number, zMax: number): Rect
	return {
		xMin = math.min(xMin, xMax),
		xMax = math.max(xMin, xMax),
		zMin = math.min(zMin, zMax),
		zMax = math.max(zMin, zMax),
	}
end

function MapLayout.inRect(r: Rect, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	return x >= r.xMin - m and x <= r.xMax + m and z >= r.zMin - m and z <= r.zMax + m
end

function MapLayout.rectCenter(r: Rect): XZ
	return { x = (r.xMin + r.xMax) / 2, z = (r.zMin + r.zMax) / 2 }
end

function MapLayout.rectSize(r: Rect): (number, number)
	return r.xMax - r.xMin, r.zMax - r.zMin
end

-- Vector3(X/Z) 또는 {x=, z=} 둘 다 받음
local function xz(pos: any): (number, number)
	local x = pos.X
	if x == nil then
		x = pos.x
	end
	local z = pos.Z
	if z == nil then
		z = pos.z
	end
	return x :: number, z :: number
end
MapLayout.xz = xz

------------------------------------------------------------------
-- 베이스 7개
--   1 왼쪽 z-40 / 2 오른쪽 z-40 / 3 왼쪽 z-110 / 4 오른쪽 z-110 / 5 왼쪽 z-180 / 6 오른쪽 z-180 / 7 왼쪽 z-250
--   (먼저 들어온 사람이 복도 출구에 가까운 베이스를 받음. 오른쪽 z-250 자리는 허브 가게)
------------------------------------------------------------------
local PLOT_SLOTS: { { side: string, z: number } } = {
	{ side = "left", z = -40 },
	{ side = "right", z = -40 },
	{ side = "left", z = -110 },
	{ side = "right", z = -110 },
	{ side = "left", z = -180 },
	{ side = "right", z = -180 },
	{ side = "left", z = -250 },
}

local function buildPlot(index: number, side: string, cz: number): Plot
	local w, d = MapLayout.PLOT_SIZE.w, MapLayout.PLOT_SIZE.d
	local facing = if side == "left" then 1 else -1
	local cx = -facing * MapLayout.PLOT_CENTER_X
	local frontX = cx + facing * d / 2 -- 복도 쪽 가장자리 (왼쪽 -40 / 오른쪽 40)
	-- (u, v) → 월드 xz. u = 앞 가장자리에서 벽 쪽 깊이, v = z 오프셋
	local function at(u: number, v: number): XZ
		return { x = frontX - facing * u, z = cz + v }
	end
	local yardU = MapLayout.YARD_DEPTH
	local midYard = yardU / 2
	return {
		index = index,
		side = side,
		center = { x = cx, z = cz },
		size = { w = w, d = d },
		facing = facing,
		rect = rect(frontX, frontX - facing * d, cz - w / 2, cz + w / 2),
		penRect = rect(frontX - facing * yardU, frontX - facing * d, cz - w / 2, cz + w / 2),
		yardRect = rect(frontX, frontX - facing * yardU, cz - w / 2, cz + w / 2),
		spawn = at(midYard, 0),
		treadmill = at(midYard, -19),
		fusion = at(midYard, 19),
		sellStall = at(5, 9),
		signs = {
			owner = at(1, 0), -- 앞 가장자리 가운데 (주인 이름)
			penUpgrade = at(yardU - 2, -8), -- 우리 울타리 바로 앞 "펫 우리 업그레이드"
			treadmillUpgrade = at(midYard - 9, -19), -- 러닝머신 앞(복도 쪽) "업그레이드 레벨 n > n+1"
		},
	}
end

local plots: { Plot } = {}
for i, slot in PLOT_SLOTS do
	plots[i] = buildPlot(i, slot.side, slot.z)
end
MapLayout.plots = plots
MapLayout.PLOT_COUNT = #plots

function MapLayout.plot(plotIndex: number): Plot?
	return plots[plotIndex]
end

function MapLayout.penRect(plotIndex: number): Rect?
	local p = plots[plotIndex]
	return if p then p.penRect else nil
end

-- 펫이 서 있는 자리 = 우리에서 앞쪽 알 자리(EGG_AREA_DEPTH)를 뺀 뒤쪽, 가장자리 3 여유
function MapLayout.petRect(plotIndex: number): Rect?
	local p = plots[plotIndex]
	if not p then
		return nil
	end
	local f = p.facing
	local frontX = p.center.x + f * p.size.d / 2
	local u0 = MapLayout.YARD_DEPTH + MapLayout.EGG_AREA_DEPTH
	local u1 = p.size.d - 3
	return rect(frontX - f * u0, frontX - f * u1, p.center.z - p.size.w / 2 + 3, p.center.z + p.size.w / 2 - 3)
end

-- 부화 중 알 자리 8개 (우리 앞쪽, 울타리 바로 뒤 2줄 × 4칸). 슬롯 번호 1~8 순서
function MapLayout.incubatorSpots(plotIndex: number): { XZ }
	local p = plots[plotIndex]
	if not p then
		return {}
	end
	local f = p.facing
	local frontX = p.center.x + f * p.size.d / 2
	local spots: { XZ } = {}
	for row = 1, 2 do
		local u = MapLayout.YARD_DEPTH + 4 + (row - 1) * 7 -- 28, 35
		for col = 1, 4 do
			local v = -21 + (col - 1) * 14 -- -21, -7, 7, 21
			table.insert(spots, { x = frontX - f * u, z = p.center.z + v })
		end
	end
	return spots
end

------------------------------------------------------------------
-- 허브 시설 (판매 가게·트레일 상점·이벤트 포털: 오른쪽 z -250 빈 자리) + 중앙 스폰
------------------------------------------------------------------
MapLayout.hubSpots = {
	mainSpawn = { x = 0, z = -140 } :: XZ, -- 베이스가 없는 8번째 사람 / 기본 스폰
	sellStall = { x = 60, z = -232 } :: XZ, -- "판매" 가게 (판매 = SellPet, 14 스터드 안)
	trailShop = { x = 60, z = -268 } :: XZ, -- 트레일 상점 (빨강·흰 줄무늬 천막)
	eventPortal = { x = 92, z = -250 } :: XZ, -- 이벤트 포털 (장식)
	safeLine = { x = 0, z = 0 } :: XZ, -- "안전 구역" 글씨·점선 (z = 0)
}

------------------------------------------------------------------
-- 둥지·경비 (구역마다 8개 둥지, 경비 집 = 구역 중앙)
--   둥지는 벽(x ±110)에서 20 이상, 구역 앞뒤 경계에서도 20 이상, 경비 집에서 60 이상.
------------------------------------------------------------------
local NEST_PATTERN: { { number } } = {
	{ -80, -78 },
	{ -32, -92 },
	{ 30, -70 },
	{ 82, -88 },
	{ -84, 74 },
	{ -30, 90 },
	{ 34, 72 },
	{ 80, 92 },
}

-- 구역마다 살짝 다르게 (짝수 구역은 좌우 뒤집고, z 를 조금 흔듦) — 결정적(랜덤 아님)
function MapLayout.nestsFor(biomeId: string): { XZ }
	local b = biomeById[biomeId]
	if not b then
		return {}
	end
	local mirror = if b.index % 2 == 0 then -1 else 1
	local result: { XZ } = {}
	for i, offset in NEST_PATTERN do
		local wobble = ((b.index * 7 + i * 3) % 5 - 2) * 2 -- -4 ~ 4
		table.insert(result, { x = offset[1] * mirror, z = b.centerZ + offset[2] + wobble })
	end
	return result
end

function MapLayout.guardHome(biomeId: string): XZ?
	local b = biomeById[biomeId]
	if not b then
		return nil
	end
	return { x = 0, z = b.centerZ }
end

------------------------------------------------------------------
-- 구역 특수 장소 (2단계 기능). 선임이 같은 자리에 진짜 모델(같은 Tag)을 지으면 서버 임시 파트는 안 생김
------------------------------------------------------------------
local function special(biomeId: string, x: number, dz: number): Special
	local b = biomeById[biomeId] :: BiomeRange
	return { biomeId = biomeId, x = x, z = b.centerZ + dz }
end

MapLayout.specials = {
	sakuraIncubator = special("cherry_blossom", -62, 0), -- Tag SakuraIncubator
	altarLight = special("angels_demons", -55, 0), -- Tag Altar, Side = "light"
	altarDark = special("angels_demons", 55, 0), -- Tag Altar, Side = "dark"
	shrine = special("angels_demons", -96, 30), -- Tag Shrine (폭포 옆 비밀 통로, 왼쪽 벽 가까이)
	questGate = special("enchanted_forest", -62, 0), -- Tag QuestGate (문 뒤 = 비밀 정원, 왼쪽 벽 쪽)
}

------------------------------------------------------------------
-- 판정 함수
------------------------------------------------------------------

-- z → 구역 id | "hub" | nil (허브 뒤 벽 너머, 맵 끝 너머)
function MapLayout.zoneAt(z: number): string?
	if z ~= z then
		return nil
	end
	if z < MapLayout.SAFE_ZONE_Z then
		if z >= MapLayout.HUB.zMin then
			return "hub"
		end
		return nil
	end
	local index = math.floor(z / MapLayout.BIOME_LENGTH) + 1
	local b = biomes[index]
	return if b then b.id else nil
end

-- 위치 → 구역 id | "hub" | nil
function MapLayout.zoneAtPos(pos: any): string?
	local _, z = xz(pos)
	return MapLayout.zoneAt(z)
end

-- 허브(안전 구역) 안인가 — z < SAFE_ZONE_Z (복도 폭 안)
function MapLayout.isInHub(pos: any): boolean
	local x, z = xz(pos)
	return z < MapLayout.SAFE_ZONE_Z and z >= MapLayout.HUB.zMin - 10 and math.abs(x) <= MapLayout.HALF_WIDTH + 10
end

-- 이 베이스 영역(울타리 포함 전체) 안인가 → 배달 판정
function MapLayout.isInPlot(pos: any, plotIndex: number): boolean
	local p = plots[plotIndex]
	if not p then
		return false
	end
	local x, z = xz(pos)
	return MapLayout.inRect(p.rect, x, z)
end

function MapLayout.isInPen(pos: any, plotIndex: number): boolean
	local p = plots[plotIndex]
	if not p then
		return false
	end
	local x, z = xz(pos)
	return MapLayout.inRect(p.penRect, x, z)
end

-- 러닝머신 벨트 사각형 (plot.treadmill 중심, TREADMILL_PAD 크기)
function MapLayout.treadmillRect(plotIndex: number): Rect?
	local p = plots[plotIndex]
	if not p then
		return nil
	end
	local hx, hz = MapLayout.TREADMILL_PAD.sizeX / 2, MapLayout.TREADMILL_PAD.sizeZ / 2
	return rect(p.treadmill.x - hx, p.treadmill.x + hx, p.treadmill.z - hz, p.treadmill.z + hz)
end

-- 이 베이스 러닝머신 벨트 위인가 (수평만, margin 만큼 바깥까지 인정)
function MapLayout.isOnTreadmill(pos: any, plotIndex: number, margin: number?): boolean
	local r = MapLayout.treadmillRect(plotIndex)
	if not r then
		return false
	end
	local x, z = xz(pos)
	return MapLayout.inRect(r, x, z, margin)
end

-- 판매 가게 자리 전부 (허브 1곳 + 베이스마다 1곳)
function MapLayout.sellSpots(): { XZ }
	local spots: { XZ } = { MapLayout.hubSpots.sellStall }
	for _, p in plots do
		table.insert(spots, p.sellStall)
	end
	return spots
end

-- 위치가 들어 있는 베이스 번호 (없으면 nil)
function MapLayout.plotAt(pos: any): number?
	local x, z = xz(pos)
	for i, p in plots do
		if MapLayout.inRect(p.rect, x, z) then
			return i
		end
	end
	return nil
end

return MapLayout
