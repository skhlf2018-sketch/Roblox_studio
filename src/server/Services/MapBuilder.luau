--!strict
--[[
	MapBuilder — 맵 만들기 (2판: 원작처럼 "한 줄 복도") + 맵 정보 색인. 선임 담당.

	배치 숫자는 전부 shared/Data/MapLayout.luau (수석) 한 곳에서 읽습니다. 위에서 본 모습 (+Z 가 "멀리"):

	  z = 3600 ─ 끝 벽 ─────────────────────────────
	           │ 15 유령 성 … 2 호수, 1 숲 (구역마다 240) │  ← 바닥 = 구역 색 스터드 판(체크무늬),
	  z = 0    ├─ "안전 구역" 글씨·빨간 점선 (밤 벽) ─┤     양옆 = 높이 60 스터드 담장(체크무늬, 구역 색),
	           │ [1]  허브 (안전 구역)          [2] │     구역 경계 = 베이지 모래띠
	           │ [3]      중앙 스폰             [4] │  ← 베이스 7개는 허브 양옆 벽에 붙어 복도 가운데를 봄
	           │ [5]                            [6] │
	           │ [7]           판매·트레일·포털      │
	  z = -290 ─ 허브 뒤 흰 벽 (구름 그림) ─────────

	- 구역("Zone" 태그) 파트 = 복도 한 칸(220 × 240)을 덮는 투명 판. 서버 로직이 위치·크기로 구역을 판정합니다.
	- 구역 테마(바닥·담장 색, 장식, 분위기 파티클)는 shared/Data/Visuals.luau 의 biomes 표.
	- 장식은 둥지·경비 길을 피해 담장 쪽(|x| ≥ 88)에만 놓습니다. 복도 가운데는 비움 (경비가 직선으로 쫓아옴).
	- 베이스: 나무 X자 울타리로 둘러싼 펫 우리(뒤 2/3) + 앞마당(스폰·러닝머신·퓨즈 머신·업그레이드 표지판).
	  러닝머신 모양은 주인의 TreadmillLevel(1~10)마다 바뀌고, 표지판 숫자는 PenLevel/TreadmillLevel + Upgrades 표로 갱신.
	- 이름이 "Map" 인 Instance 가 Workspace 에 이미 있으면 새로 만들지 않고 태그만 읽습니다.
	- 큰 파트는 전부 한 변 2048 스터드 이하(로블록스 한계). 구역마다 task.wait() 로 나눠 만듦. 전체 파트 1만 2천 이하.
	- 동물(부모 동물·우리 펫·경비)과 알 겉모습은 PetVisualService / EggVisualService 가 붙입니다.

	태그·Attribute 이름은 shared/Tags.luau 그대로 (서버 로직이 읽음). 배달 패드는 2판에서 없음
	(자기 베이스 영역에 들어가면 자동 배달).

	2단계 특수 장소 진짜 모델: 벚꽃 = 사쿠라 인큐베이터, 천사&악마 = 천국/지옥 제단 + 폭포 옆 비밀 통로,
	마법의 숲 = 퀘스트 문 + 비밀 정원 (자리 = MapLayout.specials). 태그 파트가 맵에 있으므로 서버 Util/Landmarks 는
	임시 파트를 안 만듦. 베이스 퓨즈 머신은 파란 기계 모델(Core = "?" 화면, Tube1~3 = 옆 표시등) — 클라 연출이 이 이름들을 찾음.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Biomes = require(Shared.Data.Biomes)
local MapLayout = require(Shared.Data.MapLayout)
local Economy = require(Shared.Economy)
local Visuals = require(Shared.Data.Visuals)
local Format = require(Shared.Format)
local Tags = require(Shared.Tags)
local EggRules = require(Shared.EggRules)
local Gui = require(script.Parent.Parent.Util.Gui)

type Zone = EggRules.Zone
type Color = Visuals.Color
type BiomeTheme = Visuals.BiomeTheme

export type PlotParts = {
	index: number,
	floor: BasePart,
	spawn: BasePart?,
	treadmill: BasePart?,
	pen: BasePart?,
	sign: BasePart?,
}

-- 맵 전용 숫자 (배치 좌표는 MapLayout)
local L = {
	HALF = MapLayout.HALF_WIDTH, -- 110: 담장 안쪽 면
	WALL_H = MapLayout.WALL_HEIGHT, -- 60
	WALL_T = 4, -- 담장 두께
	FLOOR_TILE = 20, -- 바닥 체크무늬 한 칸
	WALL_TILE = 30, -- 담장 체크무늬 한 칸
	BAND = 12, -- 구역 경계 모래띠 폭
	DECOR_MIN_X = 89, -- 장식은 |x| 이 이상 (담장 쪽 띠)
	NEST_CLEAR = 9, -- 둥지 둘레 장식 금지 반경
	MAX_PART = 2000, -- 2048 한계보다 조금 작게
	FENCE_H = 5.5,
	FENCE_GATE = 12, -- 우리 앞 울타리 가운데 출입구 폭
}

local MapBuilder = {}

local mapFolder: Instance? = nil
local dynamicFolders: { [string]: Folder } = {}
local zones: { [string]: Zone } = {}
local zoneParts: { [string]: BasePart } = {}
local nests: { [string]: { BasePart } } = {}
local guardSpawns: { [string]: BasePart } = {}
local nightWalls: { BasePart } = {}
local plots: { [number]: PlotParts } = {}

------------------------------------------------------------------
-- 만들기 도우미
------------------------------------------------------------------

local FLOOR_TOP = MapLayout.FLOOR_Y -- 바닥 윗면 (0)
local STUDS = Enum.SurfaceType.Studs

-- 파트 여섯 면을 전부 스터드로 (Plastic 재질에서 보임 — 원작 클래식 로블록스 느낌)
local function studify(p: BasePart)
	p.TopSurface = STUDS
	p.BottomSurface = STUDS
	p.FrontSurface = STUDS
	p.BackSurface = STUDS
	p.LeftSurface = STUDS
	p.RightSurface = STUDS
end

local function rgb(c: Color): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	parent: Instance,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
	shape: Enum.PartType?,
	tag: string?,
	attributes: { [string]: any }?,
	studs: boolean?, -- 모든 면 스터드
}

local function makePart(spec: PartSpec): Part
	local p = Instance.new("Part")
	p.Name = spec.name
	p.Anchored = true
	p.Size = spec.size
	p.CFrame = spec.cframe
	p.Color = spec.color or Color3.fromRGB(200, 200, 200)
	p.Material = spec.material or Enum.Material.SmoothPlastic
	p.Transparency = spec.transparency or 0
	p.CanCollide = if spec.canCollide == nil then true else spec.canCollide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if spec.studs then
		studify(p)
	end
	if spec.shape then
		p.Shape = spec.shape
	end
	if spec.attributes then
		for key, value in spec.attributes do
			p:SetAttribute(key, value)
		end
	end
	if spec.tag then
		CollectionService:AddTag(p, spec.tag)
	end
	p.Parent = spec.parent
	return p
end

-- 짧은 장식 파트: shape "Block" | "Ball" | "Cyl"(X 축이 길이) | "VCyl"(세운 원기둥) | "Wedge" | "Ell"(타원체)
local function P(
	parent: Instance,
	shape: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	mat: Enum.Material?,
	collide: boolean?,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Name = shape
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.CastShadow = collide == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * size.X
		p.CFrame = cframe
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.CFrame = cframe
	elseif shape == "VCyl" then
		-- size = (지름, 높이, 지름) 로 받아서 세운 원기둥으로
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(size.Y, size.X, size.X)
		p.CFrame = cframe * CFrame.Angles(0, 0, math.pi / 2)
	elseif shape == "Wedge" then
		p.Shape = Enum.PartType.Wedge
		p.Size = size
		p.CFrame = cframe
	elseif shape == "Ell" then
		p.Size = size
		p.CFrame = cframe
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	else
		p.Size = size
		p.CFrame = cframe
	end
	p.Parent = parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function light(parent: Instance, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = parent
end

-- 긴 파트를 MAX_PART 이하 조각으로 나눠 만들기 (Z 방향으로 긴 것)
local function longPartZ(
	name: string,
	x: number,
	width: number,
	y: number,
	height: number,
	z0: number,
	z1: number,
	parent: Instance,
	color: Color3,
	mat: Enum.Material,
	transparency: number?,
	collide: boolean?
)
	local length = z1 - z0
	local pieces = math.max(1, math.ceil(length / L.MAX_PART))
	local pieceLength = length / pieces
	for i = 1, pieces do
		local zc = z0 + (i - 0.5) * pieceLength
		makePart({
			name = name .. (if pieces > 1 then tostring(i) else ""),
			size = Vector3.new(width, height, pieceLength),
			cframe = CFrame.new(x, y, zc),
			parent = parent,
			color = color,
			material = mat,
			transparency = transparency,
			canCollide = if collide == nil then true else collide,
		})
	end
end

------------------------------------------------------------------
-- 장식 (구역 테마별)
------------------------------------------------------------------

type DecorFn = (parent: Instance, pos: Vector3, rng: Random, theme: BiomeTheme) -> ()

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(30, 30, 35)
local BROWN = Color3.fromRGB(120, 80, 45)
local DARKBROWN = Color3.fromRGB(80, 52, 32)
local M = Enum.Material

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function at(pos: Vector3, x: number, y: number, z: number): CFrame
	return CFrame.new(pos + Vector3.new(x, y, z))
end

local DECOR: { [string]: DecorFn } = {}

DECOR.tree = function(parent, pos, rng, theme)
	local h = rng:NextNumber(6, 9)
	P(parent, "VCyl", Vector3.new(1.6, h, 0), at(pos, 0, h / 2, 0), BROWN, M.Wood, true)
	local leaf = rgb(theme.accent)
	for i = 1, 3 do
		local a = i * 2.1
		local d = rng:NextNumber(4.5, 6.5)
		P(
			parent,
			"Ball",
			Vector3.new(d, 0, 0),
			at(pos, math.cos(a) * 1.6, h + rng:NextNumber(-0.5, 1.5), math.sin(a) * 1.6),
			leaf:Lerp(WHITE, i * 0.07),
			M.Grass
		)
	end
	if rng:NextNumber() < 0.4 then
		P(parent, "Ball", Vector3.new(0.9, 0, 0), at(pos, 2.2, h - 1, -1.5), rgb(theme.accent2), M.SmoothPlastic)
	end
end

DECOR.bush = function(parent, pos, rng, theme)
	local leaf = rgb(theme.accent):Lerp(BLACK, 0.1)
	for i = 1, 3 do
		local d = rng:NextNumber(2.5, 3.8)
		P(
			parent,
			"Ball",
			Vector3.new(d, 0, 0),
			at(pos, (i - 2) * 1.6, d * 0.3, rng:NextNumber(-0.6, 0.6)),
			leaf:Lerp(WHITE, i * 0.05),
			M.Grass
		)
	end
end

DECOR.mushroom = function(parent, pos, rng, theme)
	local h = rng:NextNumber(1.6, 2.6)
	P(parent, "VCyl", Vector3.new(0.9, h, 0), at(pos, 0, h / 2, 0), Color3.fromRGB(250, 240, 220))
	local capY = h + 0.3
	P(parent, "Ell", Vector3.new(3.2, 1.6, 3.2), at(pos, 0, capY, 0), rgb(theme.accent2))
	for i = 1, 4 do
		local a = i * 1.57 + 0.4
		P(parent, "Ball", Vector3.new(0.45, 0, 0), at(pos, math.cos(a) * 0.9, capY + 0.55, math.sin(a) * 0.9), WHITE)
	end
end

DECOR.flowers = function(parent, pos, rng, _theme)
	local colors = {
		Color3.fromRGB(255, 120, 150),
		Color3.fromRGB(255, 220, 80),
		Color3.fromRGB(180, 130, 255),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(110, 180, 255),
	}
	for _ = 1, 6 do
		local x, z = rng:NextNumber(-3, 3), rng:NextNumber(-3, 3)
		P(parent, "VCyl", Vector3.new(0.15, 0.8, 0), at(pos, x, 0.4, z), Color3.fromRGB(70, 160, 60))
		P(parent, "Ball", Vector3.new(0.7, 0, 0), at(pos, x, 0.9, z), pick(rng, colors))
	end
end

DECOR.rock = function(parent, pos, rng, _theme)
	local s = rng:NextNumber(2.5, 4.5)
	P(
		parent,
		"Ell",
		Vector3.new(s * 1.3, s * 0.8, s),
		at(pos, 0, s * 0.25, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Color3.fromRGB(140, 140, 145),
		M.Slate
	)
end

DECOR.pond = function(parent, pos, rng, _theme)
	local d = rng:NextNumber(16, 22)
	P(parent, "VCyl", Vector3.new(d + 3, 0.2, 0), at(pos, 0, 0.1, 0), Color3.fromRGB(235, 220, 170), M.Sand)
	P(parent, "VCyl", Vector3.new(d, 0.25, 0), at(pos, 0, 0.18, 0), Color3.fromRGB(80, 170, 240), M.Glass, false, 0.15)
	for i = 1, 3 do
		local a = i * 2
		P(
			parent,
			"VCyl",
			Vector3.new(2.6, 0.08, 0),
			at(pos, math.cos(a) * d * 0.3, 0.33, math.sin(a) * d * 0.3),
			Color3.fromRGB(70, 170, 70)
		)
	end
	P(
		parent,
		"Ball",
		Vector3.new(0.8, 0, 0),
		at(pos, math.cos(2) * d * 0.3, 0.6, math.sin(2) * d * 0.3),
		Color3.fromRGB(255, 150, 200)
	)
end

DECOR.lilypad = function(parent, pos, rng, theme)
	DECOR.pond(parent, pos, rng, theme)
end

DECOR.reeds = function(parent, pos, rng, _theme)
	for _ = 1, 5 do
		local h = rng:NextNumber(2.5, 4.5)
		local x, z = rng:NextNumber(-1.5, 1.5), rng:NextNumber(-1.5, 1.5)
		P(parent, "VCyl", Vector3.new(0.2, h, 0), at(pos, x, h / 2, z), Color3.fromRGB(90, 160, 70))
		P(parent, "Ell", Vector3.new(0.35, 0.9, 0.35), at(pos, x, h, z), Color3.fromRGB(120, 80, 45))
	end
end

DECOR.cactus = function(parent, pos, rng, _theme)
	local green = Color3.fromRGB(80, 165, 75)
	local h = rng:NextNumber(5, 8)
	P(parent, "VCyl", Vector3.new(1.6, h, 0), at(pos, 0, h / 2, 0), green, M.SmoothPlastic, true)
	P(parent, "Ball", Vector3.new(1.6, 0, 0), at(pos, 0, h, 0), green)
	for _, side in { -1, 1 } do
		local y = rng:NextNumber(h * 0.4, h * 0.7)
		P(parent, "Cyl", Vector3.new(1.4, 0.9, 0.9), at(pos, side * 1.2, y, 0), green)
		P(parent, "VCyl", Vector3.new(0.9, 2, 0), at(pos, side * 1.9, y + 1, 0), green)
		P(parent, "Ball", Vector3.new(0.9, 0, 0), at(pos, side * 1.9, y + 2, 0), green)
	end
	P(parent, "Ball", Vector3.new(0.8, 0, 0), at(pos, 0, h + 0.7, 0), Color3.fromRGB(255, 120, 170))
end

DECOR.pyramid = function(parent, pos, _rng, _theme)
	local sand = Color3.fromRGB(225, 190, 120)
	for i = 0, 4 do
		local s = 20 - i * 4
		P(
			parent,
			"Block",
			Vector3.new(s, 2.5, s),
			at(pos, 0, 1.25 + i * 2.5, 0),
			sand:Lerp(WHITE, i * 0.04),
			M.Sandstone,
			true
		)
	end
	P(parent, "Block", Vector3.new(2, 1.5, 2), at(pos, 0, 13.3, 0), Color3.fromRGB(255, 205, 60), M.Neon)
end

DECOR.bones = function(parent, pos, rng, _theme)
	local bone = Color3.fromRGB(240, 235, 215)
	P(parent, "Ball", Vector3.new(1.8, 0, 0), at(pos, 0, 0.8, 0), bone)
	P(parent, "Ball", Vector3.new(0.5, 0, 0), at(pos, -0.4, 1, -0.75), BLACK)
	P(parent, "Ball", Vector3.new(0.5, 0, 0), at(pos, 0.4, 1, -0.75), BLACK)
	for i = 1, 3 do
		P(
			parent,
			"Cyl",
			Vector3.new(2.4, 0.35, 0.35),
			at(pos, 0, 0.2, i * 1.1) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
			bone
		)
	end
end

DECOR.palm = function(parent, pos, rng, _theme)
	local trunk = Color3.fromRGB(160, 115, 70)
	local lean = rng:NextNumber(-0.25, 0.25)
	local top = pos
	for i = 0, 4 do
		local seg = at(pos, lean * i * 2.2, 1.2 + i * 2.2, 0) * CFrame.Angles(0, 0, -lean * 0.5)
		P(parent, "VCyl", Vector3.new(1.3 - i * 0.08, 2.4, 0), seg, trunk:Lerp(BLACK, (i % 2) * 0.12), M.Wood, i < 2)
		top = seg.Position
	end
	top += Vector3.new(0, 1.2, 0)
	for i = 1, 6 do
		local a = i * math.pi / 3
		P(
			parent,
			"Ell",
			Vector3.new(7, 0.35, 1.8),
			CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(3, -0.6, 0) * CFrame.Angles(0, 0, -0.35),
			Color3.fromRGB(60, 160, 60),
			M.Grass
		)
	end
	for i = 1, 3 do
		P(
			parent,
			"Ball",
			Vector3.new(0.8, 0, 0),
			CFrame.new(top + Vector3.new(math.cos(i * 2) * 0.7, -0.8, math.sin(i * 2) * 0.7)),
			DARKBROWN
		)
	end
end

DECOR.jungletree = function(parent, pos, rng, theme)
	local h = rng:NextNumber(11, 15)
	P(parent, "VCyl", Vector3.new(2.2, h, 0), at(pos, 0, h / 2, 0), DARKBROWN, M.Wood, true)
	P(parent, "Ell", Vector3.new(13, 4.5, 13), at(pos, 0, h + 1, 0), rgb(theme.accent), M.Grass)
	P(parent, "Ell", Vector3.new(9, 3.5, 9), at(pos, 1.5, h + 3, -1), rgb(theme.accent):Lerp(WHITE, 0.1), M.Grass)
	for i = 1, 4 do
		local a = i * 1.6
		local vh = rng:NextNumber(3, 6)
		P(
			parent,
			"VCyl",
			Vector3.new(0.25, vh, 0),
			at(pos, math.cos(a) * 5, h - vh / 2, math.sin(a) * 5),
			Color3.fromRGB(60, 140, 50)
		)
	end
end

DECOR.pine = function(parent, pos, rng, _theme)
	local s = rng:NextNumber(0.9, 1.3)
	P(parent, "VCyl", Vector3.new(1.2 * s, 3 * s, 0), at(pos, 0, 1.5 * s, 0), DARKBROWN, M.Wood, true)
	local green = Color3.fromRGB(40, 110, 70)
	for i = 0, 2 do
		local w = (7 - i * 2) * s
		local y = (3.5 + i * 2.6) * s
		P(parent, "Ell", Vector3.new(w, 3.2 * s, w), at(pos, 0, y, 0), green, M.Grass)
		P(parent, "Ell", Vector3.new(w * 0.6, 1.2 * s, w * 0.6), at(pos, 0, y + 1.3 * s, 0), WHITE, M.Snow)
	end
end

DECOR.snowman = function(parent, pos, rng, _theme)
	P(parent, "Ball", Vector3.new(4, 0, 0), at(pos, 0, 1.8, 0), WHITE, M.Snow, true)
	P(parent, "Ball", Vector3.new(3, 0, 0), at(pos, 0, 4.6, 0), WHITE, M.Snow)
	P(parent, "Ball", Vector3.new(2.2, 0, 0), at(pos, 0, 6.6, 0), WHITE, M.Snow)
	local face = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	P(parent, "Ell", Vector3.new(0.35, 0.35, 1.4), face * CFrame.new(0, 6.6, -1.4), Color3.fromRGB(255, 140, 40))
	P(parent, "Ball", Vector3.new(0.3, 0, 0), face * CFrame.new(-0.4, 7, -0.95), BLACK)
	P(parent, "Ball", Vector3.new(0.3, 0, 0), face * CFrame.new(0.4, 7, -0.95), BLACK)
	P(parent, "VCyl", Vector3.new(2.2, 0.15, 0), face * CFrame.new(0, 7.6, 0), BLACK)
	P(parent, "VCyl", Vector3.new(1.4, 1.2, 0), face * CFrame.new(0, 8.2, 0), BLACK)
	P(
		parent,
		"Cyl",
		Vector3.new(2.6, 0.5, 0.5),
		face * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, 0, 0.1),
		Color3.fromRGB(230, 50, 50)
	)
end

DECOR.icespike = function(parent, pos, rng, _theme)
	for _ = 1, 3 do
		local h = rng:NextNumber(4, 8)
		P(
			parent,
			"Ell",
			Vector3.new(1.6, h, 1.6),
			at(pos, rng:NextNumber(-1.5, 1.5), h * 0.4, rng:NextNumber(-1.5, 1.5))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)),
			Color3.fromRGB(180, 230, 255),
			M.Glass,
			false,
			0.2
		)
	end
end

DECOR.lavapool = function(parent, pos, rng, _theme)
	local d = rng:NextNumber(9, 14)
	P(parent, "VCyl", Vector3.new(d + 2, 0.3, 0), at(pos, 0, 0.12, 0), Color3.fromRGB(40, 30, 30), M.Basalt)
	local lava = P(parent, "VCyl", Vector3.new(d, 0.3, 0), at(pos, 0, 0.22, 0), Color3.fromRGB(255, 100, 20), M.Neon)
	light(lava, Color3.fromRGB(255, 120, 40), 16, 2)
	for i = 1, 4 do
		local a = i * 1.57 + rng:NextNumber(0, 1)
		P(
			parent,
			"Ell",
			Vector3.new(2, 1.2, 1.6),
			at(pos, math.cos(a) * (d / 2 + 0.8), 0.5, math.sin(a) * (d / 2 + 0.8)),
			Color3.fromRGB(50, 40, 40),
			M.Basalt
		)
	end
end

DECOR.lavarock = function(parent, pos, rng, _theme)
	local s = rng:NextNumber(2.5, 4)
	P(parent, "Ell", Vector3.new(s * 1.2, s, s), at(pos, 0, s * 0.35, 0), Color3.fromRGB(55, 40, 40), M.Basalt)
	P(
		parent,
		"Ell",
		Vector3.new(s * 0.5, s * 0.15, s * 1.05),
		at(pos, 0, s * 0.55, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), 0.5),
		Color3.fromRGB(255, 110, 30),
		M.Neon
	)
end

DECOR.volcanocone = function(parent, pos, _rng, _theme)
	local rock = Color3.fromRGB(80, 55, 50)
	for i = 0, 4 do
		local d = 26 - i * 5
		P(parent, "VCyl", Vector3.new(d, 3, 0), at(pos, 0, 1.5 + i * 3, 0), rock:Lerp(BLACK, i * 0.06), M.Basalt, true)
	end
	local crater = P(parent, "VCyl", Vector3.new(5, 0.4, 0), at(pos, 0, 15.1, 0), Color3.fromRGB(255, 110, 30), M.Neon)
	light(crater, Color3.fromRGB(255, 120, 40), 30, 3)
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(80, 70, 70)
	smoke.Size = 6
	smoke.RiseVelocity = 6
	smoke.Opacity = 0.2
	smoke.Parent = crater
end

DECOR.deadtree = function(parent, pos, rng, _theme)
	local wood = Color3.fromRGB(70, 55, 50)
	local h = rng:NextNumber(6, 9)
	P(parent, "VCyl", Vector3.new(1.2, h, 0), at(pos, 0, h / 2, 0), wood, M.Wood, true)
	for i = 1, 3 do
		local a = i * 2.1 + rng:NextNumber(0, 0.5)
		P(
			parent,
			"Cyl",
			Vector3.new(3.5, 0.45, 0.45),
			at(pos, 0, h * (0.5 + i * 0.12), 0) * CFrame.Angles(0, a, 0.6) * CFrame.new(1.6, 0, 0),
			wood,
			M.Wood
		)
	end
end

DECOR.coral = function(parent, pos, rng, _theme)
	local colors = {
		Color3.fromRGB(255, 120, 150),
		Color3.fromRGB(255, 160, 80),
		Color3.fromRGB(190, 110, 255),
		Color3.fromRGB(255, 230, 120),
	}
	local color = pick(rng, colors)
	for _ = 1, 5 do
		local h = rng:NextNumber(1.5, 4)
		local x, z = rng:NextNumber(-1.4, 1.4), rng:NextNumber(-1.4, 1.4)
		local cf = at(pos, x, h / 2, z) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4))
		P(parent, "VCyl", Vector3.new(0.6, h, 0), cf, color)
		P(parent, "Ball", Vector3.new(0.9, 0, 0), cf * CFrame.new(0, h / 2, 0), color:Lerp(WHITE, 0.3))
	end
end

DECOR.seaweed = function(parent, pos, rng, _theme)
	for _ = 1, 3 do
		local h = rng:NextNumber(4, 8)
		P(
			parent,
			"Ell",
			Vector3.new(0.7, h, 0.35),
			at(pos, rng:NextNumber(-1, 1), h * 0.45, rng:NextNumber(-1, 1))
				* CFrame.Angles(0, rng:NextNumber(0, 3), rng:NextNumber(-0.2, 0.2)),
			Color3.fromRGB(50, 170, 90),
			M.Grass
		)
	end
end

DECOR.shell = function(parent, pos, rng, _theme)
	local c = Color3.fromRGB(255, 200, 190)
	local cf = at(pos, 0, 0.4, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	P(parent, "Ell", Vector3.new(2.4, 0.8, 2), cf, c)
	for i = -1, 1 do
		P(
			parent,
			"Ell",
			Vector3.new(0.3, 0.85, 2.05),
			cf * CFrame.new(i * 0.6, 0.05, 0),
			c:Lerp(Color3.fromRGB(255, 120, 140), 0.4)
		)
	end
end

DECOR.fern = function(parent, pos, rng, _theme)
	for i = 1, 6 do
		local a = i * 1.05 + rng:NextNumber(0, 0.3)
		P(
			parent,
			"Ell",
			Vector3.new(0.6, 0.2, 3.5),
			CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.7, -1.5) * CFrame.Angles(0.5, 0, 0),
			Color3.fromRGB(70, 150, 60),
			M.Grass
		)
	end
end

DECOR.dinobones = function(parent, pos, rng, _theme)
	local bone = Color3.fromRGB(240, 235, 215)
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	P(parent, "Cyl", Vector3.new(10, 0.6, 0.6), base * CFrame.new(0, 3.2, 0), bone)
	for i = -2, 2 do
		local x = i * 1.8
		local h = 3.2 - math.abs(i) * 0.3
		for _, side in { -1, 1 } do
			P(
				parent,
				"Cyl",
				Vector3.new(h + 0.4, 0.4, 0.4),
				base * CFrame.new(x, h / 2, side * 1.1) * CFrame.Angles(side * 0.35, 0, math.pi / 2),
				bone
			)
		end
	end
	P(parent, "Ell", Vector3.new(3, 2, 2), base * CFrame.new(6, 2.6, 0), bone)
	P(parent, "Ball", Vector3.new(0.6, 0, 0), base * CFrame.new(6.6, 3, -0.8), BLACK)
end

DECOR.stars = function(parent, pos, rng, _theme)
	local c = if rng:NextNumber() < 0.5 then Color3.fromRGB(255, 255, 200) else Color3.fromRGB(200, 180, 255)
	P(parent, "VCyl", Vector3.new(rng:NextNumber(0.6, 1.3), 0.06, 0), at(pos, 0, 0.03, 0), c, M.Neon)
end

DECOR.planet = function(parent, pos, rng, _theme)
	local colors = { Color3.fromRGB(255, 160, 90), Color3.fromRGB(120, 200, 255), Color3.fromRGB(230, 120, 255) }
	local d = rng:NextNumber(7, 11)
	local y = rng:NextNumber(22, 32)
	P(parent, "Ball", Vector3.new(d, 0, 0), at(pos, 0, y, 0), pick(rng, colors))
	P(
		parent,
		"VCyl",
		Vector3.new(d * 1.8, 0.15, 0),
		at(pos, 0, y, 0) * CFrame.Angles(0.35, 0, 0.2),
		Color3.fromRGB(255, 240, 200),
		M.Neon,
		false,
		0.4
	)
end

DECOR.spacerock = function(parent, pos, rng, theme)
	local s = rng:NextNumber(2, 4)
	P(parent, "Ell", Vector3.new(s * 1.3, s, s * 1.1), at(pos, 0, s * 0.3, 0), Color3.fromRGB(90, 80, 120), M.Slate)
	P(
		parent,
		"Ell",
		Vector3.new(0.6, 1.6, 0.6),
		at(pos, 0.4, s * 0.7, 0) * CFrame.Angles(0, 0, 0.3),
		rgb(theme.accent),
		M.Neon
	)
end

DECOR.crystal = function(parent, pos, rng, theme)
	local c = rgb(if rng:NextNumber() < 0.5 then theme.accent else theme.accent2)
	local main: Part? = nil
	for i = 1, 3 do
		local h = rng:NextNumber(2.5, 5.5)
		main = P(
			parent,
			"Ell",
			Vector3.new(1.2, h, 1.2),
			at(pos, (i - 2) * 0.8, h * 0.4, rng:NextNumber(-0.5, 0.5))
				* CFrame.Angles(rng:NextNumber(-0.35, 0.35), 0, (i - 2) * 0.35),
			c,
			M.Neon,
			false,
			0.15
		)
	end
	if main and rng:NextNumber() < 0.5 then
		light(main, c, 12, 1)
	end
end

DECOR.cherrytree = function(parent, pos, rng, theme)
	local h = rng:NextNumber(5, 7)
	P(parent, "VCyl", Vector3.new(1.3, h, 0), at(pos, 0, h / 2, 0), Color3.fromRGB(90, 55, 45), M.Wood, true)
	P(
		parent,
		"Cyl",
		Vector3.new(3, 0.6, 0.6),
		at(pos, 0.9, h * 0.75, 0) * CFrame.Angles(0, 0, 0.7),
		Color3.fromRGB(90, 55, 45),
		M.Wood
	)
	local pink = rgb(theme.accent)
	for i = 1, 5 do
		local a = i * 1.25
		P(
			parent,
			"Ball",
			Vector3.new(rng:NextNumber(3.5, 5), 0, 0),
			at(pos, math.cos(a) * 2.2, h + rng:NextNumber(0, 2), math.sin(a) * 2.2),
			pink:Lerp(WHITE, rng:NextNumber(0, 0.35)),
			M.SmoothPlastic
		)
	end
end

DECOR.lantern = function(parent, pos, _rng, theme)
	P(parent, "VCyl", Vector3.new(0.5, 4, 0), at(pos, 0, 2, 0), Color3.fromRGB(60, 40, 35), M.Wood)
	local lamp = P(parent, "VCyl", Vector3.new(1.4, 1.6, 0), at(pos, 0, 4.6, 0), rgb(theme.accent2), M.Neon)
	P(parent, "VCyl", Vector3.new(1.6, 0.25, 0), at(pos, 0, 5.5, 0), BLACK)
	light(lamp, Color3.fromRGB(255, 150, 120), 14, 1.2)
end

DECOR.torii = function(parent, pos, _rng, theme)
	local red = rgb(theme.accent2)
	for _, side in { -1, 1 } do
		P(parent, "VCyl", Vector3.new(1.6, 14, 0), at(pos, side * 7, 7, 0), red, M.SmoothPlastic, true)
	end
	P(parent, "Block", Vector3.new(19, 1.2, 1.8), at(pos, 0, 14.2, 0), BLACK)
	P(parent, "Block", Vector3.new(17, 1, 1.4), at(pos, 0, 11.5, 0), red)
end

DECOR.pillar = function(parent, pos, rng, theme)
	local h = rng:NextNumber(12, 16)
	local stone = rgb(theme.accent)
	P(parent, "Block", Vector3.new(4.5, 1, 4.5), at(pos, 0, 0.5, 0), stone:Lerp(BLACK, 0.1), M.Slate, true)
	P(parent, "VCyl", Vector3.new(3, h, 0), at(pos, 0, h / 2 + 1, 0), stone, M.Marble, true)
	P(parent, "Block", Vector3.new(4.5, 1.2, 4.5), at(pos, 0, h + 1.6, 0), rgb(theme.accent2), M.Slate)
end

DECOR.brokenpillar = function(parent, pos, rng, theme)
	local stone = rgb(theme.accent)
	P(parent, "VCyl", Vector3.new(3, 5, 0), at(pos, 0, 2.5, 0), stone, M.Marble, true)
	P(
		parent,
		"Cyl",
		Vector3.new(7, 3, 3),
		at(pos, 4, 1.5, 1) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
		stone,
		M.Marble,
		true
	)
end

DECOR.statue = function(parent, pos, _rng, theme)
	P(parent, "Block", Vector3.new(5, 3, 5), at(pos, 0, 1.5, 0), rgb(theme.accent):Lerp(BLACK, 0.15), M.Slate, true)
	local gold = rgb(theme.accent2)
	P(parent, "Ell", Vector3.new(2.6, 3.6, 2), at(pos, 0, 5, 0), gold, M.Foil)
	P(parent, "Ball", Vector3.new(2, 0, 0), at(pos, 0, 7.6, 0), gold, M.Foil)
	P(parent, "Ball", Vector3.new(0.8, 0, 0), at(pos, -0.7, 8.4, 0), gold, M.Foil)
	P(parent, "Ball", Vector3.new(0.8, 0, 0), at(pos, 0.7, 8.4, 0), gold, M.Foil)
end

DECOR.cloud = function(parent, pos, rng, _theme)
	local y = rng:NextNumber(1.5, 4)
	for i = 1, 4 do
		P(
			parent,
			"Ball",
			Vector3.new(rng:NextNumber(2.5, 4), 0, 0),
			at(pos, (i - 2.5) * 1.6, y + rng:NextNumber(-0.4, 0.6), rng:NextNumber(-0.8, 0.8)),
			WHITE,
			M.SmoothPlastic,
			false,
			0.05
		)
	end
end

DECOR.goldpillar = function(parent, pos, rng, _theme)
	local h = rng:NextNumber(8, 12)
	local gold = Color3.fromRGB(255, 205, 60)
	P(parent, "VCyl", Vector3.new(3.4, 0.8, 0), at(pos, 0, 0.4, 0), gold, M.Foil, true)
	P(parent, "VCyl", Vector3.new(2.4, h, 0), at(pos, 0, h / 2 + 0.8, 0), WHITE, M.Marble, true)
	P(parent, "VCyl", Vector3.new(3.4, 0.8, 0), at(pos, 0, h + 1.2, 0), gold, M.Foil)
	P(parent, "Ball", Vector3.new(1.4, 0, 0), at(pos, 0, h + 2.3, 0), Color3.fromRGB(255, 240, 160), M.Neon)
end

DECOR.firepit = function(parent, pos, _rng, _theme)
	P(parent, "VCyl", Vector3.new(4, 0.8, 0), at(pos, 0, 0.4, 0), Color3.fromRGB(40, 30, 30), M.Basalt, true)
	local coal = P(parent, "VCyl", Vector3.new(3, 0.3, 0), at(pos, 0, 0.85, 0), Color3.fromRGB(255, 70, 30), M.Neon)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 9
	fire.Color = Color3.fromRGB(255, 80, 30)
	fire.SecondaryColor = Color3.fromRGB(255, 200, 60)
	fire.Parent = coal
	light(coal, Color3.fromRGB(255, 90, 40), 14, 2)
end

DECOR.darkspike = function(parent, pos, rng, _theme)
	for _ = 1, 2 do
		local h = rng:NextNumber(3.5, 6)
		local cf = at(pos, rng:NextNumber(-1, 1), h * 0.4, rng:NextNumber(-1, 1))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3))
		P(parent, "Ell", Vector3.new(1.3, h, 1.3), cf, Color3.fromRGB(35, 25, 30), M.Basalt)
		P(
			parent,
			"Ell",
			Vector3.new(0.5, h * 0.3, 0.5),
			cf * CFrame.new(0, h * 0.35, 0),
			Color3.fromRGB(230, 30, 30),
			M.Neon
		)
	end
end

DECOR.glowshroom = function(parent, pos, rng, theme)
	local h = rng:NextNumber(1.5, 4)
	P(parent, "VCyl", Vector3.new(0.7, h, 0), at(pos, 0, h / 2, 0), Color3.fromRGB(230, 230, 255))
	local c = rgb(if rng:NextNumber() < 0.5 then theme.accent else theme.accent2)
	local cap = P(
		parent,
		"Ell",
		Vector3.new(h * 1.2 + 1, h * 0.5 + 0.5, h * 1.2 + 1),
		at(pos, 0, h + 0.2, 0),
		c,
		M.Neon,
		false,
		0.1
	)
	if rng:NextNumber() < 0.35 then
		light(cap, c, 10, 1)
	end
end

DECOR.magictree = function(parent, pos, rng, theme)
	local h = rng:NextNumber(7, 10)
	local wood = Color3.fromRGB(70, 50, 90)
	P(parent, "VCyl", Vector3.new(1.5, h, 0), at(pos, 0, h / 2, 0) * CFrame.Angles(0, 0, 0.08), wood, M.Wood, true)
	for i = 1, 4 do
		local a = i * 1.6
		local c = rgb(if i % 2 == 0 then theme.accent else theme.accent2)
		P(
			parent,
			"Ball",
			Vector3.new(rng:NextNumber(3, 4.5), 0, 0),
			at(pos, math.cos(a) * 2, h + rng:NextNumber(-1, 1.5), math.sin(a) * 2),
			c,
			M.Neon,
			false,
			0.35
		)
	end
end

DECOR.fairylights = function(parent, pos, rng, theme)
	for _ = 1, 4 do
		P(
			parent,
			"Ball",
			Vector3.new(0.45, 0, 0),
			at(pos, rng:NextNumber(-3, 3), rng:NextNumber(2, 6), rng:NextNumber(-3, 3)),
			rgb(theme.accent2),
			M.Neon
		)
	end
end

DECOR.lollipop = function(parent, pos, rng, _theme)
	local colors = {
		Color3.fromRGB(255, 90, 160),
		Color3.fromRGB(110, 200, 255),
		Color3.fromRGB(255, 210, 70),
		Color3.fromRGB(150, 230, 120),
	}
	local h = rng:NextNumber(5, 8)
	P(parent, "VCyl", Vector3.new(0.5, h, 0), at(pos, 0, h / 2, 0), WHITE, M.SmoothPlastic, true)
	local face = at(pos, 0, h + 1.6, 0)
		* CFrame.Angles(0, rng:NextNumber(0, 3.14), 0)
		* CFrame.Angles(0, math.pi / 2, 0)
	local c = pick(rng, colors)
	P(parent, "Cyl", Vector3.new(0.7, 4.2, 4.2), face, c)
	P(parent, "Cyl", Vector3.new(0.75, 2.8, 2.8), face, WHITE)
	P(parent, "Cyl", Vector3.new(0.8, 1.5, 1.5), face, c)
end

DECOR.candycane = function(parent, pos, rng, _theme)
	local red = Color3.fromRGB(235, 50, 60)
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	for i = 0, 4 do
		P(
			parent,
			"VCyl",
			Vector3.new(0.9, 1.5, 0),
			base * CFrame.new(0, 0.75 + i * 1.5, 0),
			if i % 2 == 0 then red else WHITE,
			M.SmoothPlastic,
			i == 0
		)
	end
	P(parent, "Cyl", Vector3.new(1.6, 0.9, 0.9), base * CFrame.new(0.6, 7.8, 0) * CFrame.Angles(0, 0, -0.5), WHITE)
	P(parent, "Cyl", Vector3.new(1.4, 0.9, 0.9), base * CFrame.new(1.7, 8, 0) * CFrame.Angles(0, 0, 0.4), red)
	P(parent, "VCyl", Vector3.new(0.9, 1.2, 0), base * CFrame.new(2.3, 7.3, 0), WHITE)
end

DECOR.gumdrop = function(parent, pos, rng, _theme)
	local colors = {
		Color3.fromRGB(255, 90, 120),
		Color3.fromRGB(120, 230, 130),
		Color3.fromRGB(255, 200, 70),
		Color3.fromRGB(170, 120, 255),
	}
	local d = rng:NextNumber(2.5, 4)
	P(parent, "Ell", Vector3.new(d, d * 0.9, d), at(pos, 0, d * 0.2, 0), pick(rng, colors), M.Glass, false, 0.1)
end

DECOR.gingerhouse = function(parent, pos, rng, _theme)
	local ginger = Color3.fromRGB(190, 120, 65)
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextInteger(0, 3) * math.pi / 2, 0)
	P(parent, "Block", Vector3.new(11, 7, 9), base * CFrame.new(0, 3.5, 0), ginger, M.SmoothPlastic, true)
	for _, side in { -1, 1 } do
		P(
			parent,
			"Wedge",
			Vector3.new(11.6, 4, 5),
			base * CFrame.new(0, 9, side * 2.5) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
			WHITE,
			M.SmoothPlastic,
			true
		)
	end
	P(parent, "Block", Vector3.new(2.6, 4, 0.3), base * CFrame.new(0, 2, -4.55), Color3.fromRGB(100, 55, 30))
	for _, x in { -3.5, 3.5 } do
		P(
			parent,
			"Block",
			Vector3.new(2, 2, 0.3),
			base * CFrame.new(x, 4.5, -4.55),
			Color3.fromRGB(255, 220, 90),
			M.Neon
		)
	end
	for i = 1, 5 do
		P(
			parent,
			"Ball",
			Vector3.new(0.6, 0, 0),
			base * CFrame.new(-4.5 + i * 1.5, 7.1, -4.6),
			if i % 2 == 0 then Color3.fromRGB(255, 80, 120) else Color3.fromRGB(110, 200, 255)
		)
	end
end

DECOR.gravestone = function(parent, pos, rng, _theme)
	local stone = Color3.fromRGB(130, 125, 140)
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.1, 0.1))
	if rng:NextNumber() < 0.3 then
		P(parent, "Block", Vector3.new(0.6, 3.6, 0.6), base * CFrame.new(0, 1.8, 0), stone, M.Slate, true)
		P(parent, "Block", Vector3.new(2.2, 0.6, 0.6), base * CFrame.new(0, 2.6, 0), stone, M.Slate)
	else
		P(parent, "Block", Vector3.new(2.4, 2.6, 0.7), base * CFrame.new(0, 1.3, 0), stone, M.Slate, true)
		P(
			parent,
			"Cyl",
			Vector3.new(0.7, 2.4, 2.4),
			base * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.pi / 2, 0),
			stone,
			M.Slate
		)
	end
	P(parent, "Ell", Vector3.new(2.2, 0.3, 3), base * CFrame.new(0, 0.1, -1.6), Color3.fromRGB(70, 60, 55), M.Ground)
end

DECOR.jackolantern = function(parent, pos, rng, _theme)
	local d = rng:NextNumber(2, 3)
	local face = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	local pumpkin =
		P(parent, "Ell", Vector3.new(d * 1.2, d, d * 1.2), face * CFrame.new(0, d / 2, 0), Color3.fromRGB(255, 140, 30))
	P(parent, "VCyl", Vector3.new(0.3, 0.6, 0), face * CFrame.new(0, d + 0.2, 0), Color3.fromRGB(70, 120, 40))
	local glow = Color3.fromRGB(255, 230, 90)
	P(parent, "Block", Vector3.new(0.4, 0.4, 0.2), face * CFrame.new(-0.4 * d, d * 0.6, -0.58 * d), glow, M.Neon)
	P(parent, "Block", Vector3.new(0.4, 0.4, 0.2), face * CFrame.new(0.4 * d, d * 0.6, -0.58 * d), glow, M.Neon)
	P(parent, "Block", Vector3.new(0.9 * d, 0.25, 0.2), face * CFrame.new(0, d * 0.32, -0.56 * d), glow, M.Neon)
	light(pumpkin, Color3.fromRGB(255, 150, 50), 10, 1)
end

------------------------------------------------------------------
-- 분위기 파티클 (구역 위 큰 투명 상자에서 나옴. 클라가 내가 있는 구역 것만 켬)
------------------------------------------------------------------

local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

local function ambientEmitter(kind: string, center: Vector3, size: number, parent: Instance, biomeId: string)
	local low = kind == "bubbles" or kind == "mist" or kind == "fireflies" or kind == "embers"
	local box = makePart({
		name = "Ambient",
		size = Vector3.new(size, if low then 2 else 1, size),
		cframe = CFrame.new(center.X, if low then FLOOR_TOP + 1.5 else 28, center.Z),
		parent = parent,
		transparency = 1,
		canCollide = false,
	})
	box.CanQuery = false
	box.CanTouch = false
	local e = Instance.new("ParticleEmitter")
	e.Name = "Ambient"
	e.Enabled = false -- 클라 WorldFxController 가 켬
	e.Texture = SPARKLE_TEX
	e.LightInfluence = 0.6
	e.Rate = 25
	e.Lifetime = NumberRange.new(6, 9)
	e.Speed = NumberRange.new(1, 2)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Size = NumberSequence.new(0.5)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.2),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Acceleration = Vector3.new(0, -1.5, 0)
	if kind == "snow" then
		e.Color = ColorSequence.new(Color3.new(1, 1, 1))
		e.Size = NumberSequence.new(0.6)
		e.Rate = 50
	elseif kind == "petals" or kind == "leaves" then
		e.Color =
			ColorSequence.new(if kind == "petals" then Color3.fromRGB(255, 170, 205) else Color3.fromRGB(110, 190, 80))
		e.Size = NumberSequence.new(0.7)
		e.Acceleration = Vector3.new(1, -1.2, 0.5)
	elseif kind == "bubbles" then
		e.Color = ColorSequence.new(Color3.fromRGB(190, 230, 255))
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, 1.5, 0)
		e.Size = NumberSequence.new(0.6)
	elseif kind == "embers" then
		e.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40))
		e.LightEmission = 1
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, 2, 0)
		e.Size = NumberSequence.new(0.35)
		e.Rate = 35
	elseif kind == "stars" or kind == "sparkle" then
		e.Color =
			ColorSequence.new(if kind == "stars" then Color3.fromRGB(255, 255, 220) else Color3.fromRGB(255, 220, 120))
		e.LightEmission = 1
		e.Speed = NumberRange.new(0, 0.5)
		e.Acceleration = Vector3.zero
		e.Lifetime = NumberRange.new(2, 4)
		e.Rate = 40
	elseif kind == "fireflies" then
		e.Color = ColorSequence.new(Color3.fromRGB(220, 255, 120))
		e.LightEmission = 1
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, 0.2, 0)
		e.Size = NumberSequence.new(0.3)
		e.Speed = NumberRange.new(0.5, 1.5)
	elseif kind == "dust" then
		e.Texture = SMOKE_TEX
		e.Color = ColorSequence.new(Color3.fromRGB(230, 210, 170))
		e.Size = NumberSequence.new(3)
		e.Transparency = NumberSequence.new(0.85)
		e.Rate = 10
		e.Acceleration = Vector3.new(2, -0.2, 0)
	elseif kind == "sprinkles" then
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 160)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 210, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 230, 90)),
		})
		e.Size = NumberSequence.new(0.4)
	elseif kind == "mist" then
		e.Texture = SMOKE_TEX
		e.Color = ColorSequence.new(Color3.fromRGB(170, 130, 220))
		e.Size = NumberSequence.new(8)
		e.Transparency = NumberSequence.new(0.8)
		e.Rate = 12
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0.5, 0.1, 0)
	end
	e.Parent = box
	box:SetAttribute("BiomeId", biomeId)
	CollectionService:AddTag(box, Visuals.Tags.Ambient)
end

------------------------------------------------------------------
-- 구역
------------------------------------------------------------------
type Hole = { x: number, z: number, r: number } -- 장식을 놓지 않을 원 (월드 x, z 또는 특수 장소 기준)

------------------------------------------------------------------
-- 2단계 특수 장소 진짜 모델 — 서버 Landmarks 가 같은 태그 파트를 찾으면 임시 파트를 안 만듦
--   태그는 "기준 파트" 하나에만 (서버 거리 판정 = 그 파트 상자 표면). 나머지는 같은 Model 안의 장식.
--   돌려주는 Hole 목록 = 그 자리에 구역 장식이 안 놓이게 비워 둘 곳 (center 기준 x, z)
------------------------------------------------------------------

-- 두 점 사이 원기둥 (관·파이프)
local function between(parent: Instance, a: Vector3, b: Vector3, d: number, color: Color3, mat: Enum.Material?): Part
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	return P(
		parent,
		"Cyl",
		Vector3.new(length, d, d),
		CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0),
		color,
		mat
	)
end

-- 세운 원기둥 기준 파트 (태그·Attribute 포함, 서버가 찾음)
local function anchorCylinder(
	name: string,
	diameter: number,
	height: number,
	pos: Vector3,
	parent: Instance,
	color: Color3,
	mat: Enum.Material,
	tag: string,
	attributes: { [string]: any }?
): Part
	return makePart({
		name = name,
		size = Vector3.new(height, diameter, diameter),
		cframe = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		parent = parent,
		color = color,
		material = mat,
		shape = Enum.PartType.Cylinder,
		tag = tag,
		attributes = attributes,
	})
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- 퓨전 머신: 보라 기계 몸통(태그) + 위에 유리통 3개(Tube1~3, 빛나는 액체) + 관 → 가운데 유리 돔(Core) + 네온 띠
local function buildSakura(center: Vector3, toward: number, parent: Instance): { Hole }
	local m = model("SakuraIncubatorModel", parent)
	local back = -toward
	-- 경비 길(중심~부모 동물 원) 밖, 길 반대쪽 모서리 (도리이 옆)
	local lx, lz = 64, 46
	local pos = Vector3.new(center.X + back * lx, FLOOR_TOP, center.Z + lz)
	local wood = Color3.fromRGB(95, 58, 45)
	local pink = Color3.fromRGB(255, 175, 205)
	-- 나무 (받침 뒤)
	local trunkPos = pos + Vector3.new(back * 5.5, 0, 0)
	P(m, "VCyl", Vector3.new(3.2, 10, 0), CFrame.new(trunkPos + Vector3.new(0, 5, 0)), wood, M.Wood, true)
	P(
		m,
		"Ell",
		Vector3.new(11, 2.2, 11),
		CFrame.new(pos + Vector3.new(back * 2, 0.4, 0)),
		wood:Lerp(Color3.new(0, 0, 0), 0.15),
		M.Wood
	)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local tipPos = trunkPos + Vector3.new(math.cos(a) * 6, 0.2, math.sin(a) * 6)
		between(m, trunkPos + Vector3.new(0, 1.6, 0), tipPos, 1.1, wood, M.Wood)
	end
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		P(
			m,
			"Ball",
			Vector3.new(6 + (i % 3), 0, 0),
			CFrame.new(trunkPos + Vector3.new(math.cos(a) * 3.6, 11 + (i % 2) * 1.5, math.sin(a) * 3.6)),
			pink:Lerp(Color3.new(1, 1, 1), (i % 3) * 0.12),
			M.SmoothPlastic
		)
	end
	-- 받침 (태그 SakuraIncubator)
	local pedestal = anchorCylinder(
		"SakuraIncubator",
		7,
		1.6,
		pos + Vector3.new(0, 1.4, 0),
		m,
		Color3.fromRGB(200, 90, 130),
		Enum.Material.WoodPlanks,
		Tags.SakuraIncubator
	)
	m.PrimaryPart = pedestal
	P(
		m,
		"VCyl",
		Vector3.new(7.6, 0.3, 0),
		CFrame.new(pos + Vector3.new(0, 2.25, 0)),
		Color3.fromRGB(255, 210, 90),
		M.Foil
	)
	P(m, "Ell", Vector3.new(6.2, 2.2, 6.2), CFrame.new(pos + Vector3.new(0, 2.8, 0)), pink, M.Glass, false, 0.35)
	local egg = P(
		m,
		"Ell",
		Vector3.new(2.8, 3.6, 2.8),
		CFrame.new(pos + Vector3.new(0, 4.4, 0)),
		Color3.fromRGB(255, 150, 200),
		M.SmoothPlastic
	)
	egg.Name = "SakuraEgg"
	for i = 1, 4 do
		local a = i * 1.57 + 0.5
		P(
			m,
			"Ball",
			Vector3.new(0.6, 0, 0),
			CFrame.new(pos + Vector3.new(math.cos(a) * 1.15, 4.4 + (i % 2) * 0.8 - 0.4, math.sin(a) * 1.15)),
			Color3.new(1, 1, 1),
			M.Neon
		)
	end
	light(egg, Color3.fromRGB(255, 140, 200), 18, 1.6)
	-- 등불 4개
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local lp = pos + Vector3.new(math.cos(a) * 6, 0, math.sin(a) * 6)
		P(m, "VCyl", Vector3.new(0.4, 3, 0), CFrame.new(lp + Vector3.new(0, 1.5, 0)), wood, M.Wood)
		P(
			m,
			"Ball",
			Vector3.new(1.1, 0, 0),
			CFrame.new(lp + Vector3.new(0, 3.3, 0)),
			Color3.fromRGB(255, 170, 200),
			M.Neon
		)
	end
	-- 꽃잎 (모두에게, 적게)
	local petalBox = P(
		m,
		"Block",
		Vector3.new(12, 0.5, 12),
		CFrame.new(trunkPos + Vector3.new(0, 12, 0)),
		pink,
		M.SmoothPlastic,
		false,
		1
	)
	petalBox.Name = "PetalEmitter"
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE_TEX
	e.Rate = 8
	e.Lifetime = NumberRange.new(4, 6)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Acceleration = Vector3.new(0.6, -1.2, 0.4)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Rotation = NumberRange.new(0, 360)
	e.Color = ColorSequence.new(Color3.fromRGB(255, 170, 205))
	e.Size = NumberSequence.new(0.5)
	e.LightInfluence = 0.5
	e.Parent = petalBox
	Gui.billboard(pedestal, "사쿠라 인큐베이터", 12, 120).TextColor3 = Color3.fromRGB(255, 220, 235)
	return { { x = back * lx, z = lz, r = 11 }, { x = back * (lx + 5.5), z = lz, r = 9 } }
end

-- 천국 제단 (흰 대리석 + 금, 빛기둥) / 지옥 제단 (검은 현무암 + 빨강 네온, 불꽃)
local function buildAltar(side: string, pos: Vector3, parent: Instance)
	local light_ = side == "light"
	local m = model(if light_ then "AltarLightModel" else "AltarDarkModel", parent)
	local stone = if light_ then Color3.fromRGB(250, 248, 240) else Color3.fromRGB(40, 30, 35)
	local trim = if light_ then Color3.fromRGB(255, 205, 60) else Color3.fromRGB(230, 30, 30)
	local mat = if light_ then M.Marble else M.Basalt
	P(m, "VCyl", Vector3.new(13, 0.6, 0), CFrame.new(pos + Vector3.new(0, 0.3, 0)), stone, mat, true)
	P(m, "VCyl", Vector3.new(13.4, 0.25, 0), CFrame.new(pos + Vector3.new(0, 0.25, 0)), trim, M.Neon)
	P(m, "VCyl", Vector3.new(9.5, 0.6, 0), CFrame.new(pos + Vector3.new(0, 0.9, 0)), stone, mat, true)
	local altar = makePart({
		name = if light_ then "AltarLight" else "AltarDark",
		size = Vector3.new(6, 3, 4),
		cframe = CFrame.new(pos + Vector3.new(0, 2.7, 0)),
		parent = m,
		color = stone,
		material = mat,
		tag = Tags.Altar,
		attributes = { Side = side, PendingCount = 0 },
	})
	m.PrimaryPart = altar
	P(
		m,
		"Block",
		Vector3.new(6.8, 0.45, 4.8),
		CFrame.new(pos + Vector3.new(0, 4.4, 0)),
		trim,
		if light_ then M.Foil else M.Neon
	)
	for _, dz in { -2.05, 2.05 } do
		P(m, "Block", Vector3.new(6.1, 0.3, 0.12), CFrame.new(pos + Vector3.new(0, 2.2, dz)), trim, M.Neon)
	end
	if light_ then
		-- 금 기둥 2개 + 빛 구슬
		for _, dx in { -4.6, 4.6 } do
			P(m, "VCyl", Vector3.new(1.4, 8, 0), CFrame.new(pos + Vector3.new(dx, 5.2, 0)), stone, M.Marble, true)
			P(m, "VCyl", Vector3.new(2, 0.5, 0), CFrame.new(pos + Vector3.new(dx, 9.3, 0)), trim, M.Foil)
			local orb = P(
				m,
				"Ball",
				Vector3.new(1.4, 0, 0),
				CFrame.new(pos + Vector3.new(dx, 10.3, 0)),
				Color3.fromRGB(255, 245, 190),
				M.Neon
			)
			light(orb, Color3.fromRGB(255, 235, 170), 14, 1.2)
		end
		-- 떠 있는 후광
		for i = 1, 10 do
			local a = i / 10 * math.pi * 2
			P(
				m,
				"Ball",
				Vector3.new(0.5, 0, 0),
				CFrame.new(pos + Vector3.new(math.cos(a) * 2.3, 8.5, math.sin(a) * 2.3)),
				trim,
				M.Neon
			)
		end
		-- 하늘로 솟는 빛기둥 (Beam)
		local a0 = Instance.new("Attachment")
		a0.Name = "BeamBottom"
		a0.Position = Vector3.new(0, 1.8, 0)
		a0.Parent = altar
		local a1 = Instance.new("Attachment")
		a1.Name = "BeamTop"
		a1.Position = Vector3.new(0, 70, 0)
		a1.Parent = altar
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 3
		beam.Width1 = 6
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200))
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = altar
	else
		-- 불 화로 2개 + 검은 가시
		for _, dx in { -4.6, 4.6 } do
			P(m, "VCyl", Vector3.new(2.2, 3.4, 0), CFrame.new(pos + Vector3.new(dx, 2.9, 0)), stone, M.Basalt, true)
			local coal = P(
				m,
				"VCyl",
				Vector3.new(1.8, 0.3, 0),
				CFrame.new(pos + Vector3.new(dx, 4.7, 0)),
				Color3.fromRGB(255, 70, 30),
				M.Neon
			)
			local fire = Instance.new("Fire")
			fire.Size = 4
			fire.Heat = 10
			fire.Color = Color3.fromRGB(255, 70, 30)
			fire.SecondaryColor = Color3.fromRGB(255, 190, 60)
			fire.Parent = coal
			light(coal, Color3.fromRGB(255, 80, 40), 16, 2)
		end
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + math.pi / 4
			local sp = pos + Vector3.new(math.cos(a) * 5.6, 0, math.sin(a) * 5.6)
			P(
				m,
				"Ell",
				Vector3.new(1.2, 4.5, 1.2),
				CFrame.new(sp + Vector3.new(0, 2, 0)) * CFrame.Angles(math.cos(a) * 0.25, 0, -math.sin(a) * 0.25),
				stone,
				M.Basalt
			)
			P(m, "Ell", Vector3.new(0.5, 1.4, 0.5), CFrame.new(sp + Vector3.new(0, 3.9, 0)), trim, M.Neon)
		end
		local top = P(
			m,
			"VCyl",
			Vector3.new(2.4, 0.2, 0),
			CFrame.new(pos + Vector3.new(0, 4.7, 0)),
			Color3.fromRGB(255, 60, 30),
			M.Neon
		)
		local fire = Instance.new("Fire")
		fire.Size = 6
		fire.Heat = 12
		fire.Color = Color3.fromRGB(220, 40, 30)
		fire.SecondaryColor = Color3.fromRGB(255, 160, 40)
		fire.Parent = top
	end
	Gui.billboard(altar, if light_ then "천국 제단" else "지옥 제단", 12, 120).TextColor3 = if light_
		then Color3.fromRGB(255, 235, 150)
		else Color3.fromRGB(255, 120, 110)
end

-- 비밀 통로 (천사&악마 구역 뒤쪽 가장자리): 바위 절벽 + 폭포 + 그 옆 동굴 입구 안의 합성 제단(태그 Shrine)
local function buildShrine(center: Vector3, toward: number, parent: Instance): { Hole }
	local m = model("SecretShrineModel", parent)
	local back = -toward
	local function at2(d: number, y: number, z: number): Vector3
		return Vector3.new(center.X + back * d, FLOOR_TOP + y, center.Z + z)
	end
	local rock = Color3.fromRGB(120, 115, 125)
	local rockDark = Color3.fromRGB(85, 80, 92)
	-- 절벽 (가운데 z -5~5 는 입구)
	P(m, "Block", Vector3.new(8, 22, 11), CFrame.new(at2(76, 11, -10.5)), rock, M.Slate, true)
	P(m, "Block", Vector3.new(8, 22, 11), CFrame.new(at2(76, 11, 10.5)), rock, M.Slate, true)
	P(m, "Block", Vector3.new(8, 12, 10), CFrame.new(at2(76, 16, 0)), rockDark, M.Slate, true)
	P(m, "Block", Vector3.new(1, 10, 10), CFrame.new(at2(79.5, 5, 0)), Color3.fromRGB(45, 35, 60), M.Slate, true)
	for i, z in { -15, -8, 9, 14 } do
		P(m, "Ell", Vector3.new(5 + i % 2, 4, 5), CFrame.new(at2(71.5, 1.2, z)), rockDark, M.Slate)
	end
	-- 폭포 (오른쪽 바위 앞면) + 웅덩이 + 물보라
	local fall = P(
		m,
		"Block",
		Vector3.new(0.6, 21, 6),
		CFrame.new(at2(71.6, 10.6, 10.5)),
		Color3.fromRGB(130, 200, 255),
		M.Glass,
		false,
		0.35
	)
	fall.Name = "Waterfall"
	P(
		m,
		"Block",
		Vector3.new(0.3, 21, 1),
		CFrame.new(at2(71.2, 10.6, 9)),
		Color3.fromRGB(230, 245, 255),
		M.Neon,
		false,
		0.4
	)
	P(
		m,
		"Block",
		Vector3.new(0.3, 21, 1),
		CFrame.new(at2(71.2, 10.6, 12)),
		Color3.fromRGB(230, 245, 255),
		M.Neon,
		false,
		0.5
	)
	P(m, "VCyl", Vector3.new(13, 0.3, 0), CFrame.new(at2(66.5, 0.12, 10.5)), Color3.fromRGB(150, 145, 155), M.Slate)
	local pool = P(
		m,
		"VCyl",
		Vector3.new(11.5, 0.35, 0),
		CFrame.new(at2(66.5, 0.2, 10.5)),
		Color3.fromRGB(80, 170, 240),
		M.Glass,
		false,
		0.2
	)
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Rate = 6
	mist.Lifetime = NumberRange.new(1.5, 2.5)
	mist.Speed = NumberRange.new(1, 3)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Size = NumberSequence.new(3)
	mist.Transparency = NumberSequence.new(0.7, 1)
	mist.Color = ColorSequence.new(Color3.new(1, 1, 1))
	mist.Parent = pool
	-- 합성 제단 (동굴 안, 왼쪽은 천국 흰색 / 오른쪽은 지옥 검정)
	P(
		m,
		"VCyl",
		Vector3.new(8, 0.12, 0),
		CFrame.new(at2(74.5, 0.08, 0)),
		Color3.fromRGB(180, 130, 255),
		M.Neon,
		false,
		0.4
	)
	P(m, "Block", Vector3.new(5, 1, 5), CFrame.new(at2(76, 0.5, 0)), rockDark, M.Slate, true)
	local shrine = makePart({
		name = "SecretShrine",
		size = Vector3.new(3.4, 3, 3.4),
		cframe = CFrame.new(at2(76, 2.5, 0)),
		parent = m,
		color = Color3.fromRGB(205, 185, 255),
		material = Enum.Material.Marble,
		tag = Tags.Shrine,
	})
	m.PrimaryPart = shrine
	P(m, "VCyl", Vector3.new(1.2, 6, 0), CFrame.new(at2(77, 3, -3.6)), Color3.fromRGB(250, 248, 240), M.Marble, true)
	P(m, "VCyl", Vector3.new(1.2, 6, 0), CFrame.new(at2(77, 3, 3.6)), Color3.fromRGB(40, 30, 35), M.Basalt, true)
	P(m, "Ball", Vector3.new(1, 0, 0), CFrame.new(at2(77, 6.4, -3.6)), Color3.fromRGB(255, 220, 90), M.Neon)
	P(m, "Ball", Vector3.new(1, 0, 0), CFrame.new(at2(77, 6.4, 3.6)), Color3.fromRGB(230, 40, 40), M.Neon)
	local gem = P(
		m,
		"Ell",
		Vector3.new(1.3, 2.4, 1.3),
		CFrame.new(at2(76, 5.4, 0)),
		Color3.fromRGB(190, 130, 255),
		M.Neon,
		false,
		0.1
	)
	light(gem, Color3.fromRGB(190, 140, 255), 18, 2)
	Gui.billboard(shrine, "비밀 통로", 10, 100).TextColor3 = Color3.fromRGB(220, 200, 255)
	return { { x = back * 72, z = 0, r = 17 }, { x = back * 66, z = 10.5, r = 8 } }
end

-- 퀘스트 문 (마법의 숲 뒤쪽): 덤불 울타리로 둘러싼 비밀 정원 + 문틀 + 문(태그 QuestGate) + 룬 돌 3개(Rune1~3)
local function buildQuestGate(center: Vector3, toward: number, parent: Instance): { Hole }
	local m = model("QuestGateModel", parent)
	local back = -toward
	local function at2(d: number, y: number, z: number): Vector3
		return Vector3.new(center.X + back * d, FLOOR_TOP + y, center.Z + z)
	end
	local hedge = Color3.fromRGB(40, 110, 80)
	local stone = Color3.fromRGB(95, 80, 130)
	local glow = Color3.fromRGB(110, 255, 220)
	-- 덤불 울타리 (높이 10: 점프로 못 넘음)
	P(m, "Block", Vector3.new(2, 10, 28), CFrame.new(at2(79, 5, 0)), hedge, M.LeafyGrass, true)
	for _, z in { -13, 13 } do
		P(m, "Block", Vector3.new(19, 10, 2), CFrame.new(at2(69.5, 5, z)), hedge, M.LeafyGrass, true)
	end
	for _, z in { -9.5, 9.5 } do
		P(m, "Block", Vector3.new(2, 10, 7), CFrame.new(at2(60, 5, z)), hedge, M.LeafyGrass, true)
	end
	-- 문틀
	for _, z in { -6, 6 } do
		P(m, "Block", Vector3.new(2.4, 13, 2), CFrame.new(at2(60, 6.5, z)), stone, M.Slate, true)
		P(m, "Ball", Vector3.new(1.6, 0, 0), CFrame.new(at2(60, 13.6, z)), glow, M.Neon)
	end
	P(m, "Block", Vector3.new(2.6, 2, 14), CFrame.new(at2(60, 13.5, 0)), stone, M.Slate, true)
	local crown = P(
		m,
		"Ell",
		Vector3.new(1.6, 3, 1.6),
		CFrame.new(at2(60, 15.8, 0)),
		Color3.fromRGB(190, 110, 255),
		M.Neon,
		false,
		0.1
	)
	light(crown, Color3.fromRGB(190, 120, 255), 16, 1.5)
	-- 문 (태그 QuestGate, CanCollide true. 서버가 CollisionGroup 을 바꿈)
	local door = makePart({
		name = "Door",
		size = Vector3.new(1, 12, 10),
		cframe = CFrame.new(at2(60, 6, 0)),
		parent = m,
		color = Color3.fromRGB(80, 220, 180),
		material = Enum.Material.ForceField,
		transparency = 0.15,
		canCollide = true,
		tag = Tags.QuestGate,
	})
	m.PrimaryPart = door
	Gui.billboard(door, "퀘스트 문\n(퀘스트 3개를 끝내면 열려요)", 9, 100).TextColor3 =
		Color3.fromRGB(200, 255, 240)
	-- 룬 돌 3개 (끝낸 퀘스트만큼 클라에서 빛남)
	for i, z in { -4, 0, 4 } do
		P(m, "Block", Vector3.new(1.6, 0.6, 1.6), CFrame.new(at2(55, 0.3, z)), stone, M.Slate, true)
		local rune = P(
			m,
			"Block",
			Vector3.new(0.6, 2.4, 1.4),
			CFrame.new(at2(55, 1.8, z)),
			Color3.fromRGB(70, 60, 90),
			M.Slate,
			true
		)
		rune.Name = "Rune" .. i
	end
	-- 정원 안: 요정 샘 + 크리스탈
	P(m, "VCyl", Vector3.new(7, 1, 0), CFrame.new(at2(70, 0.5, 0)), stone, M.Slate, true)
	local water = P(m, "VCyl", Vector3.new(5.8, 0.3, 0), CFrame.new(at2(70, 1.05, 0)), glow, M.Neon, false, 0.2)
	light(water, glow, 20, 1.5)
	P(m, "Ell", Vector3.new(1.4, 4, 1.4), CFrame.new(at2(70, 3, 0)), Color3.fromRGB(190, 120, 255), M.Neon, false, 0.15)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = SPARKLE_TEX
	sparkle.Rate = 10
	sparkle.Lifetime = NumberRange.new(1.5, 3)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.SpreadAngle = Vector2.new(40, 40)
	sparkle.EmissionDirection = Enum.NormalId.Top
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(glow)
	sparkle.Size = NumberSequence.new(0.4)
	sparkle.Parent = water
	for i, z in { -9, -5, 6, 9 } do
		local h = 1.5 + (i % 2)
		P(m, "VCyl", Vector3.new(0.6, h, 0), CFrame.new(at2(64 + i * 3, h / 2, z)), Color3.fromRGB(230, 230, 255))
		P(
			m,
			"Ell",
			Vector3.new(2.4, 1.1, 2.4),
			CFrame.new(at2(64 + i * 3, h + 0.2, z)),
			if i % 2 == 0 then glow else Color3.fromRGB(190, 110, 255),
			M.Neon,
			false,
			0.1
		)
	end
	return { { x = back * 68, z = 0, r = 17 }, { x = back * 55, z = 0, r = 6 } }
end

------------------------------------------------------------------
-- 2판 블록 장식 (원작: 각진 블록 + 스터드). 구역 장식 표(Visuals.biomes[..].decor)에서 이름으로 씀
------------------------------------------------------------------

-- 스터드 블록 (Plastic 재질 + 여섯 면 스터드)
local function B(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	collide: boolean?,
	mat: Enum.Material?,
	transparency: number?
): Part
	local p = P(parent, "Block", size, cf, color, mat or M.Plastic, collide, transparency)
	studify(p)
	return p
end

local function yawAt(pos: Vector3, rng: Random): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
end

DECOR.blockytree = function(parent, pos, rng, theme)
	local h = rng:NextNumber(7, 10)
	local base = yawAt(pos, rng)
	B(parent, Vector3.new(2.2, h, 2.2), base * CFrame.new(0, h / 2, 0), Color3.fromRGB(122, 80, 46), true)
	local leaf = rgb(theme.accent)
	local w = rng:NextNumber(8, 10.5)
	B(parent, Vector3.new(w, 3.4, w), base * CFrame.new(0, h + 1.2, 0), leaf, true)
	B(parent, Vector3.new(w * 0.74, 2.8, w * 0.74), base * CFrame.new(0, h + 4.2, 0), leaf:Lerp(WHITE, 0.08))
	B(parent, Vector3.new(w * 0.42, 2.2, w * 0.42), base * CFrame.new(0, h + 6.6, 0), leaf:Lerp(WHITE, 0.16))
	-- 처진 잎 덩어리 2개
	B(
		parent,
		Vector3.new(w * 0.32, 2.4, w * 0.32),
		base * CFrame.new(w * 0.32, h - 1.2, -w * 0.18),
		leaf:Lerp(BLACK, 0.12)
	)
	B(
		parent,
		Vector3.new(w * 0.26, 1.8, w * 0.26),
		base * CFrame.new(-w * 0.3, h - 0.8, w * 0.26),
		leaf:Lerp(BLACK, 0.12)
	)
	if rng:NextNumber() < 0.35 then
		B(parent, Vector3.new(1, 1, 1), base * CFrame.new(w * 0.2, h + 3.2, -w * 0.38), rgb(theme.accent2))
	end
end

DECOR.bushblock = function(parent, pos, rng, theme)
	local base = yawAt(pos, rng)
	local leaf = rgb(theme.accent):Lerp(BLACK, 0.08)
	local w = rng:NextNumber(3.5, 5)
	B(parent, Vector3.new(w, w * 0.6, w), base * CFrame.new(0, w * 0.3, 0), leaf)
	B(
		parent,
		Vector3.new(w * 0.7, w * 0.5, w * 0.7),
		base * CFrame.new(w * 0.35, w * 0.25, w * 0.2),
		leaf:Lerp(WHITE, 0.08)
	)
	B(parent, Vector3.new(w * 0.55, w * 0.4, w * 0.55), base * CFrame.new(0, w * 0.75, 0), leaf:Lerp(WHITE, 0.14))
end

-- 작은 새 (닭/오리/백조): 흰 블록 몸 + 머리 + 부리 + 다리
local function blockBird(
	parent: Instance,
	pos: Vector3,
	rng: Random,
	body: Color3,
	head: Color3,
	beak: Color3,
	neck: number
): CFrame
	local base = yawAt(pos, rng)
	B(parent, Vector3.new(2, 1.7, 2.6), base * CFrame.new(0, 1.55, 0.2), body, true)
	B(parent, Vector3.new(1.6, 0.9, 0.8), base * CFrame.new(0, 2.15, 1.55), body:Lerp(BLACK, 0.06)) -- 꼬리
	if neck > 0 then
		B(parent, Vector3.new(0.7, neck, 0.7), base * CFrame.new(0, 2.3 + neck / 2, -1.05), body)
	end
	local hy = 2.7 + neck
	B(parent, Vector3.new(1.3, 1.3, 1.3), base * CFrame.new(0, hy, -1.2), head)
	B(parent, Vector3.new(0.6, 0.35, 0.6), base * CFrame.new(0, hy - 0.15, -2.05), beak)
	for _, side in { -1, 1 } do
		B(parent, Vector3.new(0.22, 0.22, 0.22), base * CFrame.new(side * 0.4, hy + 0.2, -1.86), BLACK)
		B(parent, Vector3.new(0.3, 0.75, 0.3), base * CFrame.new(side * 0.45, 0.38, 0.2), Color3.fromRGB(255, 170, 40))
	end
	return base * CFrame.new(0, hy, -1.2)
end

DECOR.chick = function(parent, pos, rng, _theme)
	local head = blockBird(parent, pos, rng, WHITE, WHITE, Color3.fromRGB(255, 190, 40), 0)
	-- 빨간 볏
	B(parent, Vector3.new(0.3, 0.55, 0.9), head * CFrame.new(0, 0.9, 0.05), Color3.fromRGB(230, 50, 50))
end

DECOR.duck = function(parent, pos, rng, _theme)
	blockBird(
		parent,
		pos,
		rng,
		Color3.fromRGB(250, 250, 245),
		Color3.fromRGB(250, 250, 245),
		Color3.fromRGB(255, 150, 40),
		0
	)
end

DECOR.swan = function(parent, pos, rng, _theme)
	blockBird(parent, pos, rng, WHITE, WHITE, Color3.fromRGB(255, 120, 40), 1.6)
end

DECOR.cactusblock = function(parent, pos, rng, _theme)
	local base = yawAt(pos, rng)
	local green = Color3.fromRGB(70, 160, 70)
	local h = rng:NextNumber(7, 12)
	B(parent, Vector3.new(1.8, h, 1.8), base * CFrame.new(0, h / 2, 0), green, true)
	for i, side in { -1, 1 } do
		if i == 1 or rng:NextNumber() < 0.6 then
			local y = h * rng:NextNumber(0.35, 0.6)
			B(parent, Vector3.new(1.6, 1.2, 1.2), base * CFrame.new(side * 1.6, y, 0), green:Lerp(BLACK, 0.08))
			B(parent, Vector3.new(1.2, 3, 1.2), base * CFrame.new(side * 2.3, y + 1.9, 0), green:Lerp(BLACK, 0.08))
		end
	end
	if rng:NextNumber() < 0.4 then
		B(parent, Vector3.new(0.8, 0.6, 0.8), base * CFrame.new(0, h + 0.3, 0), Color3.fromRGB(255, 120, 170))
	end
end

DECOR.blockypalm = function(parent, pos, rng, _theme)
	local base = yawAt(pos, rng)
	local trunk = Color3.fromRGB(150, 105, 60)
	local lean = rng:NextNumber(0.25, 0.5)
	local top = Vector3.zero
	for i = 0, 4 do
		local p = Vector3.new(i * lean, 1.2 + i * 2.2, 0)
		B(
			parent,
			Vector3.new(1.8, 2.2, 1.8),
			base * CFrame.new(p),
			if i % 2 == 0 then trunk else trunk:Lerp(BLACK, 0.12),
			i < 2
		)
		top = p
	end
	local leaf = Color3.fromRGB(45, 165, 60)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		local cf = base
			* CFrame.new(top + Vector3.new(0, 1.4, 0))
			* CFrame.Angles(0, a, 0)
			* CFrame.Angles(math.rad(-22), 0, 0)
			* CFrame.new(0, 0, -3.2)
		B(parent, Vector3.new(1.8, 0.45, 6.5), cf, if k % 2 == 0 then leaf else leaf:Lerp(WHITE, 0.1))
	end
	for _, dx in { -0.7, 0.7 } do
		B(
			parent,
			Vector3.new(0.9, 0.9, 0.9),
			base * CFrame.new(top + Vector3.new(dx, 0.4, 0.6)),
			Color3.fromRGB(110, 70, 35)
		)
	end
end

-- 얼음 결정 (원작 눈 구역: 하늘색 블록이 비스듬히 쌓인 덩어리)
DECOR.icecrystal = function(parent, pos, rng, _theme)
	local base = yawAt(pos, rng)
	local ice = Color3.fromRGB(165, 220, 255)
	B(parent, Vector3.new(6, 1, 6), base * CFrame.new(0, 0.5, 0), Color3.fromRGB(235, 245, 255))
	for k = 1, 4 do
		local a = k / 4 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local tilt = rng:NextNumber(0.25, 0.45)
		local n = rng:NextInteger(2, 4)
		local s = rng:NextNumber(1.6, 2.4)
		for j = 0, n - 1 do
			local r = 0.8 + j * s * tilt
			local cf = base
				* CFrame.new(math.cos(a) * r, 1 + s / 2 + j * s * 0.95, math.sin(a) * r)
				* CFrame.Angles(0, -a, tilt * 0.6)
			B(
				parent,
				Vector3.new(s, s, s),
				cf,
				if j == n - 1 then ice:Lerp(WHITE, 0.45) else ice:Lerp(WHITE, j * 0.1),
				j == 0,
				M.Plastic,
				0.08
			)
		end
	end
end

DECOR.bigbone = function(parent, pos, rng, _theme)
	local base = yawAt(pos, rng) * CFrame.new(0, 0.9, 0)
	local bone = Color3.fromRGB(242, 236, 214)
	local len = rng:NextNumber(8, 12)
	P(parent, "Cyl", Vector3.new(len, 1.6, 1.6), base, bone, M.SmoothPlastic, true)
	for _, sx in { -1, 1 } do
		for _, sz in { -0.75, 0.75 } do
			P(parent, "Ball", Vector3.new(2.3, 0, 0), base * CFrame.new(sx * len / 2, 0.2, sz), bone)
		end
	end
end

DECOR.coralblock = function(parent, pos, rng, _theme)
	local base = yawAt(pos, rng)
	local c = pick(rng, { Color3.fromRGB(200, 90, 210), Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 160, 80) })
	local h = rng:NextNumber(9, 14)
	B(parent, Vector3.new(1.4, h, 1.4), base * CFrame.new(0, h / 2, 0), c, true)
	for k = 1, 3 do
		local y = h * (0.35 + k * 0.17)
		local side = if k % 2 == 0 then -1 else 1
		B(parent, Vector3.new(3, 1, 1), base * CFrame.new(side * 1.8, y, 0), c:Lerp(WHITE, 0.1))
		B(parent, Vector3.new(1, 3.4, 1), base * CFrame.new(side * 3, y + 1.7, 0), c:Lerp(WHITE, 0.1))
		B(parent, Vector3.new(1.5, 1.5, 1.5), base * CFrame.new(side * 3, y + 3.8, 0), Color3.fromRGB(110, 220, 255))
	end
end

------------------------------------------------------------------
-- 테마 색
------------------------------------------------------------------

type SideColors = { floor: Color3, floor2: Color3, wall: Color3, wall2: Color3, glow: Color3? }

local function sideColors(theme: BiomeTheme, right: boolean): SideColors
	local rs = theme.rightSide
	if right and rs then
		local wall = rgb(rs.wall)
		return {
			floor = rgb(rs.floor),
			floor2 = rgb(rs.floor2),
			wall = wall,
			wall2 = wall:Lerp(BLACK, 0.1),
			glow = if rs.wallGlow then rgb(rs.wallGlow) else nil,
		}
	end
	local floor = rgb(theme.floor)
	local wall = rgb(theme.wall)
	return {
		floor = floor,
		floor2 = if theme.floor2 then rgb(theme.floor2) else floor:Lerp(BLACK, 0.08),
		wall = wall,
		wall2 = wall:Lerp(BLACK, 0.1),
		glow = if theme.wallGlow then rgb(theme.wallGlow) else nil,
	}
end

------------------------------------------------------------------
-- 복도 바닥·담장 (체크무늬 스터드 판)
------------------------------------------------------------------

-- 바닥: x0~x1, z0~z1 을 tile 크기 칸으로 나눠 두 색 번갈아. colorAt(x) 로 칸마다 색 고르기 가능
local function tiledFloor(
	parent: Instance,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	colorsAt: (number) -> (Color3, Color3)
)
	local nx = math.max(1, math.floor((x1 - x0) / L.FLOOR_TILE + 0.5))
	local nz = math.max(1, math.floor((z1 - z0) / L.FLOOR_TILE + 0.5))
	local w = (x1 - x0) / nx
	local d = (z1 - z0) / nz
	for i = 0, nx - 1 do
		local x = x0 + (i + 0.5) * w
		local c1, c2 = colorsAt(x)
		for j = 0, nz - 1 do
			makePart({
				name = "Floor",
				size = Vector3.new(w, 1, d),
				cframe = CFrame.new(x, FLOOR_TOP - 0.5, z0 + (j + 0.5) * d),
				parent = parent,
				color = if (i + j) % 2 == 0 then c1 else c2,
				material = Enum.Material.Plastic,
				studs = true,
			})
		end
	end
end

-- 담장 한 쪽: side = -1(왼쪽, x = -110) / 1(오른쪽). z0~z1. 아래위 2줄 체크무늬
local function tiledWall(parent: Instance, side: number, z0: number, z1: number, c1: Color3, c2: Color3, cap: Color3?)
	local n = math.max(1, math.floor((z1 - z0) / L.WALL_TILE + 0.5))
	local d = (z1 - z0) / n
	local x = side * (L.HALF + L.WALL_T / 2)
	local rows = 2
	local h = L.WALL_H / rows
	for j = 0, n - 1 do
		for r = 0, rows - 1 do
			makePart({
				name = "Wall",
				size = Vector3.new(L.WALL_T, h, d),
				cframe = CFrame.new(x, FLOOR_TOP + (r + 0.5) * h, z0 + (j + 0.5) * d),
				parent = parent,
				color = if (j + r) % 2 == 0 then c1 else c2,
				material = Enum.Material.Plastic,
				studs = true,
			})
		end
	end
	if cap then
		-- 담장 위 잔디/눈 띠 (원작: 숲·호수 담장 꼭대기 초록 줄)
		makePart({
			name = "WallCap",
			size = Vector3.new(L.WALL_T + 1, 2, z1 - z0),
			cframe = CFrame.new(x - side * 0.5, FLOOR_TOP + L.WALL_H + 1, (z0 + z1) / 2),
			parent = parent,
			color = cap,
			material = Enum.Material.Plastic,
			studs = true,
		})
	end
end

-- 담장 안쪽 면 위치 (side 쪽 담장 표면에서 d 만큼 복도 쪽)
local function wallFaceX(side: number, d: number): number
	return side * (L.HALF - d)
end

------------------------------------------------------------------
-- 둥지 (MapLayout.nestsFor 자리) — 건초 링 / 선사시대 통나무·뼈 / 코스믹 작은 둥근 둥지 / 눈 덮인 둥지
------------------------------------------------------------------

local NEST_STYLE: { [string]: string } = {
	prehistoric = "bones",
	cosmic = "pot",
	snow = "snow",
	abyss_ocean = "shell",
}

local function buildNest(biomeId: string, index: number, pos: Vector3, parent: Instance)
	local style = NEST_STYLE[biomeId] or "hay"
	local big = style == "bones"
	local d = if big then 9 else 7
	local nest = makePart({
		name = "Nest" .. index,
		size = Vector3.new(1.2, d, d),
		cframe = CFrame.new(pos.X, FLOOR_TOP + 0.6, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		parent = parent,
		color = if style == "pot" then Color3.fromRGB(70, 50, 90) else Color3.fromRGB(150, 100, 55),
		material = Enum.Material.Plastic,
		shape = Enum.PartType.Cylinder,
		tag = Tags.Nest,
		attributes = { BiomeId = biomeId, NestIndex = index },
	})
	nest.CanQuery = true
	local rng = Random.new(index * 131 + #biomeId * 17)
	if style == "pot" then
		-- 코스믹: 작은 둥근 그릇 + 보라 네온 테두리
		P(
			parent,
			"VCyl",
			Vector3.new(d + 0.6, 1.6, 0),
			CFrame.new(pos.X, FLOOR_TOP + 0.8, pos.Z),
			Color3.fromRGB(95, 70, 120),
			M.Plastic
		)
		P(
			parent,
			"VCyl",
			Vector3.new(d + 1, 0.3, 0),
			CFrame.new(pos.X, FLOOR_TOP + 1.7, pos.Z),
			Color3.fromRGB(190, 120, 255),
			M.Neon
		)
		return
	end
	local count = if big then 12 else 10
	local radius = d * 0.5
	for i = 1, count do
		local a = i / count * math.pi * 2
		local cf = CFrame.new(
			pos.X + math.cos(a) * radius,
			FLOOR_TOP + 1.1 + (i % 2) * 0.35,
			pos.Z + math.sin(a) * radius
		) * CFrame.Angles(0, -a + rng:NextNumber(-0.35, 0.35), rng:NextNumber(-0.25, 0.25))
		if style == "bones" then
			if i % 3 == 0 then
				P(
					parent,
					"Cyl",
					Vector3.new(1.1, 4.4, 1.1),
					cf * CFrame.Angles(0, math.pi / 2, 0),
					Color3.fromRGB(242, 236, 214)
				)
			else
				B(parent, Vector3.new(1.5, 1.5, 4.8), cf, Color3.fromRGB(150, 95, 55):Lerp(BLACK, (i % 2) * 0.15))
			end
		elseif style == "shell" then
			B(parent, Vector3.new(1, 1, 3.4), cf, Color3.fromRGB(225, 200, 150):Lerp(WHITE, (i % 3) * 0.1))
		else
			local stick = Color3.fromRGB(165, 105, 55):Lerp(Color3.fromRGB(120, 72, 38), (i % 3) * 0.3)
			B(parent, Vector3.new(0.9, 0.9, 3.4), cf, stick)
			if style == "snow" and i % 2 == 0 then
				B(parent, Vector3.new(1.1, 0.4, 2.4), cf * CFrame.new(0, 0.6, 0), Color3.fromRGB(245, 250, 255))
			end
		end
	end
end

------------------------------------------------------------------
-- 구역 특수 장소 (자리 = MapLayout.specials) — 반환: 장식 금지 원(월드 좌표)
------------------------------------------------------------------

local function worldHoles(holes: { Hole }, center: Vector3): { Hole }
	local out: { Hole } = {}
	for _, h in holes do
		table.insert(out, { x = center.X + h.x, z = center.Z + h.z, r = h.r })
	end
	return out
end

-- 특수 장소 함수들은 "center + back * d" 로 자리를 잡음 → 원하는 기준 파트 자리(s)에서 center 를 거꾸로 계산
local function centerFor(s: MapLayout.Special, depth: number, dz: number): (Vector3, number)
	local back = if s.x < 0 then -1 else 1 -- 가까운 담장 쪽
	return Vector3.new(s.x - back * depth, FLOOR_TOP, s.z - dz), -back
end

local function buildSpecials(biomeId: string, parent: Instance): { Hole }
	local holes: { Hole } = {}
	local S = MapLayout.specials
	if biomeId == S.sakuraIncubator.biomeId then
		local center, toward = centerFor(S.sakuraIncubator, 64, 46)
		for _, h in worldHoles(buildSakura(center, toward, parent), center) do
			table.insert(holes, h)
		end
	end
	if biomeId == S.shrine.biomeId then
		local center, toward = centerFor(S.shrine, 76, 0)
		for _, h in worldHoles(buildShrine(center, toward, parent), center) do
			table.insert(holes, h)
		end
	end
	if biomeId == S.altarLight.biomeId then
		buildAltar("light", Vector3.new(S.altarLight.x, FLOOR_TOP, S.altarLight.z), parent)
		table.insert(holes, { x = S.altarLight.x, z = S.altarLight.z, r = 9 })
	end
	if biomeId == S.altarDark.biomeId then
		buildAltar("dark", Vector3.new(S.altarDark.x, FLOOR_TOP, S.altarDark.z), parent)
		table.insert(holes, { x = S.altarDark.x, z = S.altarDark.z, r = 9 })
	end
	if biomeId == S.questGate.biomeId then
		local center, toward = centerFor(S.questGate, 60, 0)
		for _, h in worldHoles(buildQuestGate(center, toward, parent), center) do
			table.insert(holes, h)
		end
	end
	return holes
end

------------------------------------------------------------------
-- 구역 장식 (담장 쪽 띠 |x| ≥ DECOR_MIN_X 에만, 둥지·특수 장소 피함)
------------------------------------------------------------------

local function buildDecor(range: MapLayout.BiomeRange, theme: BiomeTheme, parent: Instance, reserved: { Hole })
	local rng = Random.new(range.index * 7919)
	local placed: { Hole } = table.clone(reserved)
	local decorFolder = folder("Decor", parent)
	local z0, z1 = range.zMin, range.zMax
	local cz = range.centerZ

	local function free(x: number, z: number, r: number): boolean
		for _, h in placed do
			local dx, dz = x - h.x, z - h.z
			if dx * dx + dz * dz < (r + h.r) * (r + h.r) then
				return false
			end
		end
		return true
	end
	local function reserve(x: number, z: number, r: number)
		table.insert(placed, { x = x, z = z, r = r })
	end
	local function tryPlace(radius: number, side: number?): Vector3?
		for _ = 1, 60 do
			local s = side or (if rng:NextNumber() < 0.5 then -1 else 1)
			local maxX = L.HALF - 1.5 - radius
			local minX = math.min(maxX, math.max(L.DECOR_MIN_X, maxX - 12))
			local x = s * rng:NextNumber(minX, maxX)
			local z = rng:NextNumber(z0 + radius + 4, z1 - radius - 4)
			if free(x, z, radius) then
				reserve(x, z, radius)
				return Vector3.new(x, FLOOR_TOP, z)
			end
		end
		return nil
	end

	for _, spec in theme.decor do
		local kind = spec.kind
		if kind == "heavenhell" then
			-- 바닥은 이미 왼쪽 천국(흰 금) / 오른쪽 지옥(검붉) — 가운데 금빛 경계선 + 양쪽 금·빨강 금
			P(
				decorFolder,
				"Block",
				Vector3.new(1.2, 0.12, z1 - z0 - 2),
				CFrame.new(0, FLOOR_TOP + 0.06, cz),
				Color3.fromRGB(255, 205, 60),
				M.Neon
			)
			for _ = 1, 6 do
				P(
					decorFolder,
					"Block",
					Vector3.new(0.5, 0.12, rng:NextNumber(8, 20)),
					CFrame.new(rng:NextNumber(10, 100), FLOOR_TOP + 0.06, cz + rng:NextNumber(-110, 110))
						* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
					Color3.fromRGB(230, 40, 30),
					M.Neon
				)
				P(
					decorFolder,
					"Block",
					Vector3.new(0.4, 0.12, rng:NextNumber(8, 20)),
					CFrame.new(-rng:NextNumber(10, 100), FLOOR_TOP + 0.06, cz + rng:NextNumber(-110, 110))
						* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
					Color3.fromRGB(255, 215, 90),
					M.Neon
				)
			end
		elseif kind == "chocoriver" then
			-- 왼쪽 담장을 따라 흐르는 초콜릿 강
			local x = -L.HALF + 8
			P(
				decorFolder,
				"Block",
				Vector3.new(12, 0.15, z1 - z0 - 8),
				CFrame.new(x, FLOOR_TOP + 0.075, cz),
				Color3.fromRGB(105, 58, 30),
				M.SmoothPlastic
			)
			for _, dx in { -6.5, 6.5 } do
				B(
					decorFolder,
					Vector3.new(1, 0.6, z1 - z0 - 8),
					CFrame.new(x + dx, FLOOR_TOP + 0.3, cz),
					Color3.fromRGB(255, 240, 245)
				)
			end
			for i = 0, 11 do
				reserve(x, z0 + 10 + i * 20, 8)
			end
		elseif kind == "castlewall" then
			-- 오른쪽 담장 앞 성벽 + 탑 2개
			local x = L.HALF - 3
			local stone = Color3.fromRGB(95, 90, 105)
			B(decorFolder, Vector3.new(4, 18, z1 - z0 - 40), CFrame.new(x, FLOOR_TOP + 9, cz), stone, true, M.Plastic)
			for i = 0, 15 do
				B(decorFolder, Vector3.new(4.4, 2.4, 4), CFrame.new(x, FLOOR_TOP + 19.2, z0 + 24 + i * 12.5), stone)
			end
			for _, dz in { -1, 1 } do
				local tz = cz + dz * ((z1 - z0) / 2 - 16)
				B(
					decorFolder,
					Vector3.new(12, 26, 12),
					CFrame.new(x - 4, FLOOR_TOP + 13, tz),
					stone:Lerp(BLACK, 0.1),
					true
				)
				for t = 0, 2 do
					B(
						decorFolder,
						Vector3.new(13 - t * 4, 2.5, 13 - t * 4),
						CFrame.new(x - 4, FLOOR_TOP + 27.2 + t * 2.5, tz),
						Color3.fromRGB(110, 60, 150)
					)
				end
				local window = P(
					decorFolder,
					"Block",
					Vector3.new(0.4, 3.4, 1.8),
					CFrame.new(x - 10.2, FLOOR_TOP + 16, tz),
					Color3.fromRGB(255, 200, 80),
					M.Neon
				)
				light(window, Color3.fromRGB(255, 180, 80), 16, 1)
			end
			for i = 0, 23 do
				reserve(x - 3, z0 + 5 + i * 10, 7)
			end
		elseif kind == "torii" then
			local pos = tryPlace(10, -1)
			if pos then
				DECOR.torii(decorFolder, pos, rng, theme)
			end
		elseif kind == "lakewater" then
			-- 호수: 양쪽 담장 앞 큰 물 (가운데 길·둥지는 비움) + 연잎
			for i, side in { -1, 1 } do
				local x = side * (L.HALF - 12)
				local z = cz + (if i == 1 then -12 else 12)
				P(
					decorFolder,
					"Block",
					Vector3.new(20, 0.2, 78),
					CFrame.new(x, FLOOR_TOP + 0.1, z),
					Color3.fromRGB(225, 210, 160),
					M.Plastic
				)
				local water = P(
					decorFolder,
					"Block",
					Vector3.new(17, 0.3, 74),
					CFrame.new(x, FLOOR_TOP + 0.16, z),
					Color3.fromRGB(70, 160, 235),
					M.Glass,
					false,
					0.15
				)
				water.Name = "Water"
				for k = 1, 5 do
					P(
						decorFolder,
						"VCyl",
						Vector3.new(rng:NextNumber(2.2, 3.4), 0.15, 0),
						CFrame.new(x + rng:NextNumber(-5, 5), FLOOR_TOP + 0.35, z - 30 + k * 11),
						Color3.fromRGB(70, 170, 70),
						M.Plastic
					)
				end
				for k = 0, 7 do
					reserve(x, z - 35 + k * 10, 9)
				end
			end
		elseif kind == "sandedge" then
			-- 심연의 바다: 양쪽 담장을 따라 들쭉날쭉한 모래 테두리
			for _, side in { -1, 1 } do
				local z = z0 + 4
				while z < z1 - 4 do
					local len = math.min(rng:NextNumber(26, 46), z1 - 4 - z)
					local w = rng:NextNumber(14, 26)
					B(
						decorFolder,
						Vector3.new(w, 0.24, len),
						CFrame.new(side * (L.HALF - w / 2), FLOOR_TOP + 0.12, z + len / 2),
						Color3.fromRGB(222, 196, 135):Lerp(WHITE, rng:NextNumber(0, 0.08))
					)
					z += len
				end
			end
		elseif kind == "lavawall" then
			-- 화산: 담장에 세로 용암 줄 + 바닥 용암 띠
			for _, side in { -1, 1 } do
				for k = 0, 7 do
					local z = z0 + 15 + k * 30
					local stripe = P(
						decorFolder,
						"Block",
						Vector3.new(0.4, rng:NextNumber(30, 54), 1.2),
						CFrame.new(wallFaceX(side, 0.2), FLOOR_TOP + 28, z),
						Color3.fromRGB(255, 110, 30),
						M.Neon
					)
					stripe.Name = "LavaStripe"
				end
				P(
					decorFolder,
					"Block",
					Vector3.new(2, 0.14, z1 - z0 - 10),
					CFrame.new(side * (L.HALF - 4), FLOOR_TOP + 0.07, cz),
					Color3.fromRGB(255, 90, 20),
					M.Neon
				)
			end
		elseif kind == "wallstars" then
			-- 코스믹: 담장에 하얀 네온 별 (원작 사진)
			for _, side in { -1, 1 } do
				for _ = 1, 14 do
					local z = rng:NextNumber(z0 + 5, z1 - 5)
					local y = rng:NextNumber(12, 56)
					local s = rng:NextNumber(1.5, 3.2)
					local cf = CFrame.new(wallFaceX(side, 0.25), FLOOR_TOP + y, z)
					P(decorFolder, "Block", Vector3.new(0.3, s, s * 0.22), cf, WHITE, M.Neon)
					P(decorFolder, "Block", Vector3.new(0.3, s * 0.22, s), cf, WHITE, M.Neon)
				end
			end
		else
			local fn = DECOR[kind]
			if fn then
				local radius = if kind == "pyramid"
					then 11
					elseif kind == "volcanocone" then 13
					elseif kind == "pond" then 10
					elseif kind == "jungletree" or kind == "blockytree" or kind == "cherrytree" then 6
					elseif kind == "gingerhouse" or kind == "icecrystal" or kind == "blockypalm" then 7
					elseif kind == "stars" then 1
					else 3.5
				local side: number? = nil
				if kind == "cloud" or kind == "goldpillar" then
					side = -1
				elseif kind == "firepit" or kind == "darkspike" then
					side = 1
				end
				for _ = 1, math.max(0, math.floor(spec.count * Visuals.decorScale + 0.5)) do
					local pos = tryPlace(radius, side)
					if pos then
						fn(decorFolder, pos, rng, theme)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------
-- 구역 (복도 한 칸)
------------------------------------------------------------------

local function buildZone(biome: Biomes.Biome, parent: Instance)
	local range = MapLayout.biome(biome.id)
	assert(range, "MapLayout 에 구역 없음: " .. biome.id)
	local theme = Visuals.biomes[biome.id]
	assert(theme, "Visuals.biomes 에 테마 없음: " .. biome.id)
	local zoneFolder = folder(biome.id, parent)
	local z0, z1, cz = range.zMin, range.zMax, range.centerZ
	local first = range.index == 1
	local last = range.index == MapLayout.BIOME_COUNT
	local left, right = sideColors(theme, false), sideColors(theme, true)

	-- 구역 판정 파트 (투명, 밟히지 않음). 서버 MapBuilder.getZone / 경비 / 알 처리가 크기를 읽음
	local zonePart = makePart({
		name = "Zone",
		size = Vector3.new(L.HALF * 2, 1, z1 - z0),
		cframe = CFrame.new(0, FLOOR_TOP - 0.5, cz),
		parent = zoneFolder,
		transparency = 1,
		canCollide = false,
		tag = Tags.Zone,
		attributes = { BiomeId = biome.id, Order = biome.order, RecommendedSpeed = biome.recommendedSpeed },
	})
	zonePart.CanQuery = false
	zonePart.CanTouch = false

	-- 바닥 (경계 모래띠 자리는 비움)
	local fz0 = if first then z0 else z0 + L.BAND / 2
	local fz1 = if last then z1 else z1 - L.BAND / 2
	tiledFloor(zoneFolder, -L.HALF, L.HALF, fz0, fz1, function(x: number): (Color3, Color3)
		local c = if x > 0 then right else left
		return c.floor, c.floor2
	end)
	-- 다음 구역과의 경계: 베이지 모래띠 (가운데에 살짝 비스듬한 줄무늬)
	if not last then
		makePart({
			name = "Band",
			size = Vector3.new(L.HALF * 2, 1, L.BAND),
			cframe = CFrame.new(0, FLOOR_TOP - 0.5, z1),
			parent = zoneFolder,
			color = Color3.fromRGB(226, 208, 156),
			material = Enum.Material.Plastic,
			studs = true,
		})
		for k = -4, 4 do
			P(
				zoneFolder,
				"Block",
				Vector3.new(14, 0.08, 2.2),
				CFrame.new(k * 24, FLOOR_TOP + 0.04, z1) * CFrame.Angles(0, math.rad(18), 0),
				Color3.fromRGB(206, 186, 130),
				M.Plastic
			)
		end
	end

	-- 양옆 담장 (구역 색 체크무늬 + 위 띠)
	local cap = if theme.wallCap then rgb(theme.wallCap) else nil
	tiledWall(zoneFolder, -1, z0, z1, left.wall, left.wall2, cap)
	tiledWall(zoneFolder, 1, z0, z1, right.wall, right.wall2, cap)
	if left.glow or right.glow then
		-- 담장 아래 네온 띠 (화산 주황 / 코스믹 흰색 / 천사&악마 금·빨강 / 마법의 숲 청록 / 유령 성 주황)
		for _, side in { -1, 1 } do
			local c = if side > 0 then right.glow else left.glow
			if c then
				P(
					zoneFolder,
					"Block",
					Vector3.new(0.4, 1.2, z1 - z0),
					CFrame.new(wallFaceX(side, 0.2), FLOOR_TOP + 3, cz),
					c,
					M.Neon
				)
			end
		end
	end

	-- 담장 위 구역 이름판 (양쪽, 구역 시작 쪽) — 이름 + 추천 속도
	for _, side in { -1, 1 } do
		local pos = Vector3.new(wallFaceX(side, 0.35), FLOOR_TOP + 34, z0 + 26)
		local board = makePart({
			name = "ZoneSign",
			size = Vector3.new(30, 11, 0.6),
			cframe = CFrame.lookAt(pos, pos + Vector3.new(-side, 0, 0)),
			parent = zoneFolder,
			color = rgb(theme.accent),
			material = Enum.Material.SmoothPlastic,
			canCollide = false,
			tag = Tags.ZoneSign,
			attributes = { BiomeId = biome.id },
		})
		Gui.sign(board, Enum.NormalId.Front, {
			badge = tostring(biome.order),
			title = biome.name .. " " .. theme.label,
			subtitle = "추천 속도 " .. Format.number(biome.recommendedSpeed),
			corner = if biome.isNew then "NEW!" else nil,
			background = rgb(theme.accent):Lerp(BLACK, 0.15),
			titleColor = WHITE,
		})
	end

	-- 경비 집 (구역 가운데) — 서버는 MapLayout.guardHome 을 쓰지만 표시·호환용 파트
	local home = MapLayout.guardHome(biome.id)
	if home then
		makePart({
			name = "GuardSpawn",
			size = Vector3.new(4, 0.2, 4),
			cframe = CFrame.new(home.x, FLOOR_TOP + 0.1, home.z),
			parent = zoneFolder,
			transparency = 1,
			canCollide = false,
			tag = Tags.GuardSpawn,
			attributes = { BiomeId = biome.id },
		})
		-- 경비가 자는 자리 (살짝 어두운 둥근 자국)
		P(
			zoneFolder,
			"VCyl",
			Vector3.new(18, 0.06, 0),
			CFrame.new(home.x, FLOOR_TOP + 0.03, home.z),
			left.floor2:Lerp(BLACK, 0.12),
			M.Plastic
		)
	end

	-- 둥지 8개 + 부모 동물 자리 2개 (1번·8번 둥지 옆, 담장 쪽)
	local holes: { Hole } = {}
	local nestSpots = MapLayout.nestsFor(biome.id)
	for i, spot in nestSpots do
		buildNest(biome.id, i, Vector3.new(spot.x, FLOOR_TOP, spot.z), zoneFolder)
		table.insert(holes, { x = spot.x, z = spot.z, r = L.NEST_CLEAR })
	end
	for _, i in { 1, #nestSpots } do
		local spot = nestSpots[i]
		if spot then
			local side = if spot.x < 0 then -1 else 1
			local px = math.clamp(spot.x + side * 11, -(L.HALF - 6), L.HALF - 6)
			local spotPos = Vector3.new(px, FLOOR_TOP + 0.5, spot.z)
			makePart({
				name = "ParentAnimal" .. i,
				size = Vector3.new(1, 1, 1),
				cframe = CFrame.lookAt(spotPos, Vector3.new(spot.x, spotPos.Y, spot.z)),
				parent = zoneFolder,
				transparency = 1,
				canCollide = false,
				tag = Tags.ParentAnimalSpot,
				attributes = { BiomeId = biome.id, NestIndex = i },
			})
			table.insert(holes, { x = px, z = spot.z, r = 6 })
		end
	end

	for _, h in buildSpecials(biome.id, zoneFolder) do
		table.insert(holes, h)
	end
	buildDecor(range, theme, zoneFolder, holes)
	if theme.ambient then
		ambientEmitter(theme.ambient, Vector3.new(0, FLOOR_TOP, cz), L.HALF * 2 - 20, zoneFolder, biome.id)
	end
end

------------------------------------------------------------------
-- 베이스 (울타리 우리 + 앞마당)
------------------------------------------------------------------

local POST = Color3.fromRGB(58, 52, 58)

-- 원작 울타리 한 줄: 검은 기둥(최대 10 간격) + 위·아래 가로대 + X 보강재
local function fenceLine(parent: Instance, a: Vector3, b: Vector3, color: Color3)
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.5 then
		return
	end
	local n = math.max(1, math.ceil(length / 10))
	local dir = delta.Unit
	local h = L.FENCE_H
	for i = 0, n do
		local p = a + dir * (length * i / n)
		B(parent, Vector3.new(1.5, h + 0.8, 1.5), CFrame.new(p.X, FLOOR_TOP + (h + 0.8) / 2, p.Z), POST, true)
	end
	for i = 0, n - 1 do
		local p0 = a + dir * (length * i / n)
		local p1 = a + dir * (length * (i + 1) / n)
		local seg = (p1 - p0).Magnitude
		local mid = (p0 + p1) / 2
		local look = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(p1.X, 0, p1.Z))
		local yTop, yBot = FLOOR_TOP + h - 0.6, FLOOR_TOP + 1.1
		B(parent, Vector3.new(0.7, 0.8, seg), look + Vector3.new(0, yTop, 0), color, true)
		B(parent, Vector3.new(0.7, 0.8, seg), look + Vector3.new(0, yBot, 0), color, true)
		-- X 보강재
		local rise = yTop - yBot
		local diag = math.sqrt(seg * seg + rise * rise)
		local angle = math.atan2(rise, seg)
		for _, s in { -1, 1 } do
			B(
				parent,
				Vector3.new(0.5, 0.6, diag),
				look * CFrame.new(0, (yTop + yBot) / 2, 0) * CFrame.Angles(s * angle, 0, 0),
				color:Lerp(BLACK, 0.06)
			)
		end
	end
end

-- 업그레이드 표지판 (원작: 남색 판 + 흰 제목 + 초록 "레벨 5 > 레벨 6" + 빨간 가격 버튼)
type UpgradeSign = { board: BasePart, level: TextLabel, price: TextLabel }

local function upgradeSign(
	parent: Instance,
	pos: Vector3,
	facing: Vector3,
	title: string,
	kind: string,
	plotIndex: number
): UpgradeSign
	local navy = Color3.fromRGB(30, 36, 60)
	local boardPos = pos + Vector3.new(0, 4.2, 0)
	local cf = CFrame.lookAt(boardPos, boardPos + facing)
	B(parent, Vector3.new(1.2, 2.4, 1.2), cf * CFrame.new(-2.4, -3, 0.3), navy, true)
	B(parent, Vector3.new(1.2, 2.4, 1.2), cf * CFrame.new(2.4, -3, 0.3), navy, true)
	local board = makePart({
		name = "UpgradeSign",
		size = Vector3.new(8, 4.6, 0.8),
		cframe = cf,
		parent = parent,
		color = navy,
		material = Enum.Material.Plastic,
		studs = true,
		tag = Visuals.Tags.UpgradeSign,
		attributes = { Kind = kind, PlotIndex = plotIndex },
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = navy
	frame.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(12, 14, 26)
	stroke.Thickness = 8
	stroke.Parent = frame
	local function text(name: string, y: number, h: number, value: string, color: Color3): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.05, y)
		t.Size = UDim2.fromScale(0.9, h)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = value
		t.Parent = frame
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(10, 10, 20)
		s.Thickness = 3
		s.Parent = t
		return t
	end
	text("Title", 0.06, 0.26, title, WHITE)
	local level = text("Level", 0.33, 0.2, "레벨 1 > 레벨 2", Color3.fromRGB(120, 255, 120))
	local button = Instance.new("Frame")
	button.Name = "PriceButton"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.fromScale(0.5, 0.58)
	button.Size = UDim2.fromScale(0.78, 0.34)
	button.BackgroundColor3 = Color3.fromRGB(225, 30, 40)
	button.Parent = frame
	local bs = Instance.new("UIStroke")
	bs.Color = WHITE
	bs.Thickness = 4
	bs.Parent = button
	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.BackgroundTransparency = 1
	price.Size = UDim2.fromScale(1, 1)
	price.Font = Enum.Font.FredokaOne
	price.TextScaled = true
	price.TextColor3 = WHITE
	price.Text = "$1K"
	price.Parent = button
	local ps = Instance.new("UIStroke")
	ps.Color = Color3.fromRGB(60, 0, 0)
	ps.Thickness = 3
	ps.Parent = price
	gui.Parent = board
	return { board = board, level = level, price = price }
end

-- 머리 위 빌보드 두 줄 (퓨즈 머신 "퓨즈 머신 / 0/3", 판매 등)
local function twoLine(
	adornee: BasePart,
	offsetY: number,
	top: string,
	topColor: Color3,
	bottom: string?,
	name: string?
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name or "Title"
	gui.Size = UDim2.fromScale(14, if bottom then 6 else 3.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = adornee
	local function line(lineName: string, y: number, h: number, text: string, color: Color3)
		local t = Instance.new("TextLabel")
		t.Name = lineName
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0, y)
		t.Size = UDim2.fromScale(1, h)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = text
		t.Parent = gui
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(15, 15, 30)
		s.Thickness = 3
		s.Parent = t
	end
	if bottom then
		line("Top", 0, 0.55, top, topColor)
		line("Bottom", 0.55, 0.45, bottom, WHITE)
	else
		line("Top", 0, 1, top, topColor)
	end
	gui.Parent = adornee
	return gui
end

-- 바닥 청록 링 (기계 아래, 판매 가게 앞)
local function floorRing(parent: Instance, pos: Vector3, d: number, color: Color3)
	P(parent, "VCyl", Vector3.new(d, 0.08, 0), CFrame.new(pos.X, FLOOR_TOP + 0.04, pos.Z), color, M.Neon)
	P(
		parent,
		"VCyl",
		Vector3.new(d - 1.6, 0.1, 0),
		CFrame.new(pos.X, FLOOR_TOP + 0.05, pos.Z),
		Color3.fromRGB(80, 205, 70),
		M.Plastic
	)
end

-- 퓨즈 머신 (원작: 파란 기계 + "?" 화면 + 옆 별 패널, 위에 "퓨즈 머신 0/3"). 앞 = 복도 쪽
local function buildFusionMachine(parent: Instance, pos: Vector3, facing: number, plotIndex: number)
	local m = model("FusionMachineModel", parent)
	local blue = Color3.fromRGB(40, 95, 215)
	local dark = Color3.fromRGB(45, 50, 70)
	local cf0 = CFrame.lookAt(pos, pos + Vector3.new(facing, 0, 0))
	local function at3(x: number, y: number, z: number): CFrame
		return cf0 * CFrame.new(x, FLOOR_TOP + y, z)
	end
	floorRing(m, pos, 15, Color3.fromRGB(60, 235, 220))
	B(m, Vector3.new(10, 1, 7), at3(0, 0.5, 0), dark, true)
	local body = makePart({
		name = "FusionMachine",
		size = Vector3.new(8, 6, 5.5),
		cframe = at3(0, 4, 0.3),
		parent = m,
		color = blue,
		material = Enum.Material.Plastic,
		tag = Tags.FusionMachine,
		attributes = { PlotIndex = plotIndex },
		studs = true,
	})
	m.PrimaryPart = body
	-- "?" 화면 (Core: 클라가 퓨전 때 번쩍임)
	local core = P(m, "Block", Vector3.new(5, 4, 0.4), at3(0, 4.3, -2.6), Color3.fromRGB(210, 235, 255), M.Neon)
	core.Name = "Core"
	local q = Instance.new("SurfaceGui")
	q.Face = Enum.NormalId.Front
	q.LightInfluence = 0
	q.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	q.PixelsPerStud = 30
	local ql = Instance.new("TextLabel")
	ql.BackgroundTransparency = 1
	ql.Size = UDim2.fromScale(1, 1)
	ql.Font = Enum.Font.FredokaOne
	ql.TextScaled = true
	ql.Text = "?"
	ql.TextColor3 = Color3.fromRGB(30, 40, 90)
	ql.Parent = q
	q.Parent = core
	light(core, Color3.fromRGB(150, 200, 255), 14, 1.4)
	B(m, Vector3.new(5.8, 0.6, 0.8), at3(0, 6.6, -2.5), dark) -- 화면 위 테
	B(m, Vector3.new(5.8, 0.6, 0.8), at3(0, 2, -2.5), dark) -- 화면 아래 테
	-- 위 둥근 통 + 관
	P(m, "VCyl", Vector3.new(5, 2.2, 0), at3(0, 8.1, 0.6), dark, M.Plastic, true)
	P(m, "VCyl", Vector3.new(3.4, 0.6, 0), at3(0, 9.5, 0.6), Color3.fromRGB(120, 200, 255), M.Neon)
	between(m, (at3(-2.4, 8.4, 0.6)).Position, (at3(-5, 8.4, 0.6)).Position, 0.9, dark, M.Plastic)
	between(m, (at3(-5, 8.4, 0.6)).Position, (at3(-5, 1, 0.6)).Position, 0.9, dark, M.Plastic)
	-- 옆 별 패널 (원작 왼쪽 파란 별 화면)
	local panel = B(m, Vector3.new(1.2, 4, 4), at3(-5.2, 3, 0), blue:Lerp(BLACK, 0.2), true)
	panel.Name = "StarPanel"
	P(
		m,
		"Block",
		Vector3.new(0.3, 1.8, 0.4),
		at3(-5.9, 3.4, -0.6) * CFrame.Angles(0, 0, math.rad(20)),
		Color3.fromRGB(150, 220, 255),
		M.Neon
	)
	P(m, "Block", Vector3.new(0.3, 0.4, 1.8), at3(-5.9, 3.4, -0.6), Color3.fromRGB(150, 220, 255), M.Neon)
	-- 표시등 3개 (Tube1~3: 클라 퓨전 연출이 차례로 번쩍임)
	for i = 1, 3 do
		local tube =
			B(m, Vector3.new(0.9, 0.9, 0.5), at3(4.6, 2 + i * 1.2, -1.6), Color3.fromRGB(255, 70, 80), false, M.Neon)
		tube.Name = "Tube" .. i
	end
	B(m, Vector3.new(1.4, 4.6, 1.4), at3(4.6, 3.8, -0.6), dark, true)
	twoLine(body, 10.5, "퓨즈 머신", Color3.fromRGB(90, 220, 255), "0/3", "FuseLabel")
end

------------------------------------------------------------------
-- 러닝머신 (레벨 1~10 모양) — 벨트 파트(태그 Treadmill)는 그대로, 둘레 모양 모델만 바꿈
------------------------------------------------------------------

type TreadStyle = {
	name: string,
	belt: Color3,
	beltMat: Enum.Material,
	frame: Color3,
	trim: Color3,
	arrow: Color3,
	extra: string?,
}

local TREAD_STYLES: { TreadStyle } = {
	{
		name = "기본",
		belt = Color3.fromRGB(55, 55, 60),
		beltMat = M.Plastic,
		frame = Color3.fromRGB(175, 178, 188),
		trim = Color3.fromRGB(90, 92, 100),
		arrow = Color3.fromRGB(200, 200, 200),
	},
	{
		name = "사이파이",
		belt = Color3.fromRGB(30, 40, 70),
		beltMat = M.Plastic,
		frame = Color3.fromRGB(235, 240, 250),
		trim = Color3.fromRGB(60, 230, 255),
		arrow = Color3.fromRGB(60, 230, 255),
		extra = "scifi",
	},
	{
		name = "불꽃",
		belt = Color3.fromRGB(50, 25, 20),
		beltMat = M.Plastic,
		frame = Color3.fromRGB(150, 35, 25),
		trim = Color3.fromRGB(255, 130, 30),
		arrow = Color3.fromRGB(255, 160, 40),
		extra = "fire",
	},
	{
		name = "셀럽",
		belt = Color3.fromRGB(200, 25, 40),
		beltMat = M.Fabric,
		frame = Color3.fromRGB(240, 200, 70),
		trim = Color3.fromRGB(255, 230, 120),
		arrow = Color3.fromRGB(255, 230, 140),
		extra = "celeb",
	},
	{
		name = "황금",
		belt = Color3.fromRGB(230, 180, 40),
		beltMat = M.Plastic,
		frame = Color3.fromRGB(255, 205, 50),
		trim = Color3.fromRGB(255, 240, 150),
		arrow = Color3.fromRGB(255, 255, 200),
		extra = "gold",
	},
	{
		name = "얼음",
		belt = Color3.fromRGB(25, 45, 80),
		beltMat = M.Plastic,
		frame = Color3.fromRGB(80, 150, 230),
		trim = Color3.fromRGB(150, 225, 255),
		arrow = Color3.fromRGB(110, 240, 255),
		extra = "ice",
	},
	{
		name = "럭키블록",
		belt = Color3.fromRGB(70, 60, 30),
		beltMat = M.Plastic,
		frame = Color3.fromRGB(255, 200, 30),
		trim = Color3.fromRGB(255, 140, 20),
		arrow = Color3.fromRGB(255, 230, 80),
		extra = "lucky",
	},
	{
		name = "해커",
		belt = Color3.fromRGB(15, 18, 15),
		beltMat = M.Plastic,
		frame = Color3.fromRGB(30, 34, 30),
		trim = Color3.fromRGB(40, 255, 90),
		arrow = Color3.fromRGB(40, 255, 90),
		extra = "hacker",
	},
	{
		name = "악마",
		belt = Color3.fromRGB(35, 10, 12),
		beltMat = M.Plastic,
		frame = Color3.fromRGB(40, 20, 24),
		trim = Color3.fromRGB(230, 30, 30),
		arrow = Color3.fromRGB(255, 60, 40),
		extra = "demon",
	},
	{
		name = "천사",
		belt = Color3.fromRGB(245, 245, 250),
		beltMat = M.Plastic,
		frame = Color3.fromRGB(255, 255, 255),
		trim = Color3.fromRGB(255, 215, 80),
		arrow = Color3.fromRGB(255, 215, 90),
		extra = "angel",
	},
}

-- level 0(잠김)은 기본 모양을 반투명으로
local function buildTreadmillLook(parent: Instance, pad: BasePart, level: number): Model
	local m = Instance.new("Model")
	m.Name = "TreadmillLook"
	local style = TREAD_STYLES[math.clamp(level, 1, #TREAD_STYLES)]
	local locked = level <= 0
	pad.Color = style.belt
	pad.Material = style.beltMat
	pad.Transparency = if locked then 0.4 else 0
	-- 벨트 좌표: 로컬 -Z = 앞(복도 쪽), 벨트 길이 = pad.Size.Z
	local cf0 = pad.CFrame
	local len = pad.Size.Z
	local wid = pad.Size.X
	local top = pad.Size.Y / 2
	local function at3(x: number, y: number, z: number): CFrame
		return cf0 * CFrame.new(x, y, z)
	end
	-- 옆 틀 + 앞 콘솔 + 손잡이
	for _, s in { -1, 1 } do
		B(m, Vector3.new(1.2, 1.6, len + 1), at3(s * (wid / 2 + 0.6), 0.3, 0), style.frame, true)
		P(m, "Block", Vector3.new(0.3, 0.3, len + 1), at3(s * (wid / 2 + 0.6), 1.15, 0), style.trim, M.Neon)
		B(m, Vector3.new(0.6, 3.6, 0.6), at3(s * (wid / 2 + 0.4), top + 1.8, -len / 2 + 1), style.frame)
		B(m, Vector3.new(0.5, 0.5, 4), at3(s * (wid / 2 + 0.4), top + 3.4, -len / 2 + 3), style.frame)
	end
	B(m, Vector3.new(wid + 2, 5.4, 1.4), at3(0, top + 2.2, -len / 2 - 0.4), style.frame, true)
	local screen = P(m, "Block", Vector3.new(wid - 2, 1.8, 0.3), at3(0, top + 4, -len / 2 + 0.35), style.trim, M.Neon)
	screen.Name = "Screen"
	-- 벨트 위 화살표 (>>>)
	for k = 0, 2 do
		local z = -len / 2 + 3 + k * 3
		for _, s in { -1, 1 } do
			P(
				m,
				"Block",
				Vector3.new(2.6, 0.06, 0.45),
				at3(s * 0.9, top + 0.03, z) * CFrame.Angles(0, s * math.rad(35), 0),
				style.arrow,
				M.Neon
			)
		end
	end
	local extra = style.extra
	if extra == "scifi" then
		for _, s in { -1, 1 } do
			P(m, "Block", Vector3.new(0.4, 4, 0.4), at3(s * (wid / 2 + 1.4), top + 2, len / 2 - 1), style.trim, M.Neon)
			B(m, Vector3.new(1.4, 1, 3), at3(s * (wid / 2 + 1.4), top + 4.4, len / 2 - 1), style.frame)
		end
	elseif extra == "fire" then
		for _, s in { -1, 1 } do
			local brazier = B(m, Vector3.new(1.6, 2, 1.6), at3(s * (wid / 2 + 1.6), 1, len / 2 - 1), style.frame)
			local fire = Instance.new("Fire")
			fire.Size = 4
			fire.Heat = 8
			fire.Color = Color3.fromRGB(255, 120, 30)
			fire.SecondaryColor = Color3.fromRGB(255, 220, 80)
			fire.Parent = brazier
		end
	elseif extra == "celeb" then
		for _, s in { -1, 1 } do
			for k = 0, 2 do
				P(
					m,
					"VCyl",
					Vector3.new(0.5, 3.2, 0),
					at3(s * (wid / 2 + 2.4), 1.6, -len / 2 + 2 + k * 4),
					style.frame,
					M.Foil
				)
				P(
					m,
					"Ball",
					Vector3.new(0.8, 0, 0),
					at3(s * (wid / 2 + 2.4), 3.3, -len / 2 + 2 + k * 4),
					style.frame,
					M.Foil
				)
			end
			P(
				m,
				"Block",
				Vector3.new(0.35, 0.35, 8),
				at3(s * (wid / 2 + 2.4), 2.6, 0),
				Color3.fromRGB(180, 20, 40),
				M.Fabric
			)
		end
	elseif extra == "gold" then
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = Color3.fromRGB(255, 230, 120)
		sparkle.Parent = screen
	elseif extra == "ice" then
		for _, s in { -1, 1 } do
			for k = 0, 2 do
				local h = 2.2 + (k % 2) * 1.6
				B(
					m,
					Vector3.new(1.4, h, 1.4),
					at3(s * (wid / 2 + 1.5), 1.2 + h / 2, -len / 2 + 2 + k * 4) * CFrame.Angles(0, 0, s * math.rad(-18)),
					Color3.fromRGB(110, 190, 255),
					false,
					M.Plastic,
					0.05
				)
				B(
					m,
					Vector3.new(0.9, 1.2, 0.9),
					at3(s * (wid / 2 + 2.1), 1.6 + h, -len / 2 + 2 + k * 4) * CFrame.Angles(0, 0, s * math.rad(-28)),
					Color3.fromRGB(200, 240, 255)
				)
			end
		end
	elseif extra == "lucky" then
		for _, s in { -1, 1 } do
			for _, zz in { -len / 2 + 1, len / 2 - 1 } do
				local block =
					B(m, Vector3.new(2, 2, 2), at3(s * (wid / 2 + 1.8), 1, zz), Color3.fromRGB(255, 205, 40), true)
				local g = Instance.new("SurfaceGui")
				g.Face = Enum.NormalId.Front
				g.LightInfluence = 0
				local t = Instance.new("TextLabel")
				t.BackgroundTransparency = 1
				t.Size = UDim2.fromScale(1, 1)
				t.Font = Enum.Font.FredokaOne
				t.TextScaled = true
				t.Text = "?"
				t.TextColor3 = WHITE
				t.Parent = g
				g.Parent = block
			end
		end
	elseif extra == "hacker" then
		for _, s in { -1, 1 } do
			local mon = B(m, Vector3.new(0.4, 2.4, 3), at3(s * (wid / 2 + 1.6), 3.4, -len / 2 + 2.5), style.frame)
			P(
				m,
				"Block",
				Vector3.new(0.1, 2, 2.6),
				at3(s * (wid / 2 + 1.35), 3.4, -len / 2 + 2.5),
				style.trim,
				M.Neon,
				false,
				0.3
			)
			B(m, Vector3.new(0.5, 2.2, 0.5), at3(s * (wid / 2 + 1.6), 1.1, -len / 2 + 2.5), style.frame)
			mon.Name = "Monitor"
		end
	elseif extra == "demon" then
		for _, s in { -1, 1 } do
			local horn = P(
				m,
				"Wedge",
				Vector3.new(0.8, 3, 1.4),
				at3(s * (wid / 2 + 0.8), top + 6.2, -len / 2 - 0.4) * CFrame.Angles(0, 0, s * math.rad(-15)),
				Color3.fromRGB(25, 10, 12),
				M.Plastic
			)
			horn.Name = "Horn"
			local fire = Instance.new("Fire")
			fire.Size = 3
			fire.Color = Color3.fromRGB(230, 30, 20)
			fire.SecondaryColor = Color3.fromRGB(120, 0, 0)
			fire.Parent = horn
		end
	elseif extra == "angel" then
		for _, s in { -1, 1 } do
			for k = 0, 2 do
				B(
					m,
					Vector3.new(0.4, 2.4 - k * 0.5, 3.2 - k * 0.6),
					at3(s * (wid / 2 + 1.2 + k * 1.4), top + 4 + k * 0.6, -len / 2 + 0.6)
						* CFrame.Angles(0, 0, s * math.rad(-25)),
					WHITE
				)
			end
		end
		P(
			m,
			"Cyl",
			Vector3.new(0.3, 3.4, 3.4),
			at3(0, top + 7.2, -len / 2 - 0.4) * CFrame.Angles(0, 0, math.pi / 2),
			style.trim,
			M.Neon
		)
	end
	if locked then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = math.max(d.Transparency, 0.55)
			end
		end
	end
	m:SetAttribute("Level", level)
	m.Parent = parent
	return m
end

------------------------------------------------------------------
-- 베이스 만들기
------------------------------------------------------------------

-- 줄무늬 천막 가게 (판매 / 트레일 상점)
local function stall(
	parent: Instance,
	pos: Vector3,
	facing: Vector3,
	tag: string,
	title: string,
	titleColor: Color3,
	width: number?
): BasePart
	local m = model(tag .. "Model", parent)
	local cf0 = CFrame.lookAt(pos, pos + facing)
	local function at3(x: number, y: number, z: number): CFrame
		return cf0 * CFrame.new(x, FLOOR_TOP + y, z)
	end
	local wood = Color3.fromRGB(120, 110, 125)
	local w = width or 12
	local half = w / 2
	local counter = makePart({
		name = tag,
		size = Vector3.new(w, 3.4, 3),
		cframe = at3(0, 1.7, -1),
		parent = m,
		color = Color3.fromRGB(110, 70, 150),
		material = Enum.Material.Plastic,
		tag = tag,
		studs = true,
	})
	m.PrimaryPart = counter
	B(m, Vector3.new(w + 0.6, 0.6, 3.6), at3(0, 3.7, -1), Color3.fromRGB(235, 225, 210))
	for _, x in { -half, half } do
		for _, z in { -2.5, 3.5 } do
			B(m, Vector3.new(0.8, 9, 0.8), at3(x, 4.5, z), wood, true)
		end
	end
	-- 빨강·흰 줄무늬 천막 (앞으로 기울어짐)
	local stripes = math.max(3, math.floor((w + 0.6) / 1.8 + 0.5))
	for k = 0, stripes - 1 do
		local x = -(stripes * 1.8) / 2 + k * 1.8 + 0.9
		B(
			m,
			Vector3.new(1.8, 0.5, 8),
			at3(x, 9.6, 0.5) * CFrame.Angles(math.rad(-12), 0, 0),
			if k % 2 == 0 then Color3.fromRGB(225, 40, 50) else WHITE
		)
	end
	twoLine(counter, 11, title, titleColor, nil, "StallTitle")
	return counter
end

type PlotDyn = {
	index: number,
	folder: Instance,
	pad: BasePart?,
	look: Model?,
	lookLevel: number,
	penSign: UpgradeSign?,
	treadSign: UpgradeSign?,
	stepLabel: TextLabel?,
	ownerLabels: { TextLabel },
	conns: { RBXScriptConnection },
}
local plotDyn: { [number]: PlotDyn } = {}

local function buildPlot(index: number, parent: Instance)
	local p = MapLayout.plot(index)
	assert(p, "MapLayout 에 베이스 없음: " .. index)
	local plotFolder = folder("Plot" .. index, parent)
	local f = p.facing -- +1 = 복도가 +x 쪽 (왼쪽 베이스)
	local toFront = Vector3.new(f, 0, 0)
	local cz = p.center.z
	local w, d = p.size.w, p.size.d
	local fenceColor = rgb(Visuals.plotColors[index] or { 196, 104, 48 })
	local dyn: PlotDyn = {
		index = index,
		folder = plotFolder,
		lookLevel = -1,
		ownerLabels = {},
		conns = {},
	}
	plotDyn[index] = dyn

	-- 베이스 영역 (투명 바닥 판, 서버 판정·주인 Attribute)
	local floor = makePart({
		name = "PlotFloor",
		size = Vector3.new(d, 1, w),
		cframe = CFrame.new(p.center.x, FLOOR_TOP - 0.5, cz),
		parent = plotFolder,
		transparency = 1,
		canCollide = false,
		tag = Tags.Plot,
		attributes = { PlotIndex = index, OwnerUserId = 0 },
	})
	floor.CanQuery = false
	floor.CanTouch = false

	-- 우리 바닥 (펫 진열 자리: LookVector = 앞마당·복도 쪽)
	local pr = p.penRect
	local penCenter = Vector3.new((pr.xMin + pr.xMax) / 2, FLOOR_TOP - 0.1, (pr.zMin + pr.zMax) / 2)
	local pen = makePart({
		name = "PenArea",
		size = Vector3.new(pr.zMax - pr.zMin, 0.2, pr.xMax - pr.xMin),
		cframe = CFrame.lookAt(penCenter, penCenter + toFront),
		parent = plotFolder,
		transparency = 1,
		canCollide = false,
		tag = Tags.PenArea,
		attributes = { PlotIndex = index },
	})
	pen.CanQuery = false
	pen.CanTouch = false
	-- 우리 바닥 잔디 테두리 (살짝 진한 초록 띠)
	local penFrontX = if f > 0 then pr.xMax else pr.xMin
	B(
		plotFolder,
		Vector3.new(pr.xMax - pr.xMin, 0.1, w - 2),
		CFrame.new(penCenter.X, FLOOR_TOP + 0.05, cz),
		Color3.fromRGB(70, 178, 48)
	)

	-- 울타리: 우리 앞(가운데 출입구) + 양옆 (뒤는 담장)
	local backX = if f > 0 then pr.xMin else pr.xMax
	local zA, zB = cz - w / 2 + 0.75, cz + w / 2 - 0.75
	local gate = L.FENCE_GATE / 2
	fenceLine(plotFolder, Vector3.new(penFrontX, 0, zA), Vector3.new(penFrontX, 0, cz - gate), fenceColor)
	fenceLine(plotFolder, Vector3.new(penFrontX, 0, cz + gate), Vector3.new(penFrontX, 0, zB), fenceColor)
	fenceLine(plotFolder, Vector3.new(penFrontX, 0, zA), Vector3.new(backX - f * 0.5, 0, zA), fenceColor)
	fenceLine(plotFolder, Vector3.new(penFrontX, 0, zB), Vector3.new(backX - f * 0.5, 0, zB), fenceColor)

	-- 2판 수정: 부화 알 받침 없음 — 알은 우리 바닥 아무 데나 놓음 (PlaceEgg, IncubatorController 놓기 모드)

	-- 스폰 (앞마당 가운데) + 흰 원
	makePart({
		name = "PlotSpawn",
		size = Vector3.new(6, 0.2, 6),
		cframe = CFrame.new(p.spawn.x, FLOOR_TOP + 0.1, p.spawn.z),
		parent = plotFolder,
		transparency = 1,
		canCollide = false,
		tag = Tags.PlotSpawn,
		attributes = { PlotIndex = index },
	})
	P(
		plotFolder,
		"VCyl",
		Vector3.new(7, 0.06, 0),
		CFrame.new(p.spawn.x, FLOOR_TOP + 0.03, p.spawn.z),
		WHITE,
		M.SmoothPlastic,
		false,
		0.55
	)

	-- 러닝머신 (벨트 = 태그 파트, 길이 방향 = 복도 쪽)
	local tp = MapLayout.TREADMILL_PAD
	local padPos = Vector3.new(p.treadmill.x, FLOOR_TOP + 0.5, p.treadmill.z)
	local pad = makePart({
		name = "Treadmill",
		size = Vector3.new(tp.sizeZ, 1, tp.sizeX),
		cframe = CFrame.lookAt(padPos, padPos + toFront),
		parent = plotFolder,
		color = Color3.fromRGB(55, 55, 60),
		material = Enum.Material.Plastic,
		tag = Tags.Treadmill,
		attributes = { PlotIndex = index, Level = 0 },
	})
	dyn.pad = pad
	local stepGui = twoLine(pad, 9, "+0/스텝", Color3.fromRGB(255, 120, 200), nil, "StepLabel")
	local stepTop = stepGui:FindFirstChild("Top")
	dyn.stepLabel = if stepTop and stepTop:IsA("TextLabel") then stepTop else nil

	-- 퓨즈 머신
	buildFusionMachine(plotFolder, Vector3.new(p.fusion.x, FLOOR_TOP, p.fusion.z), f, index)

	-- 업그레이드 표지판 2개 (복도 쪽을 봄)
	local s = p.signs
	dyn.penSign = upgradeSign(
		plotFolder,
		Vector3.new(s.penUpgrade.x, FLOOR_TOP, s.penUpgrade.z),
		toFront,
		"펫 우리 업그레이드",
		"Pen",
		index
	)
	dyn.treadSign = upgradeSign(
		plotFolder,
		Vector3.new(s.treadmillUpgrade.x, FLOOR_TOP, s.treadmillUpgrade.z),
		toFront,
		"러닝머신 업그레이드",
		"Treadmill",
		index
	)

	-- 판매 가게 (앞마당 앞, 퓨즈 머신 옆 — 원작처럼 베이스마다)
	local sell = stall(
		plotFolder,
		Vector3.new(p.sellStall.x, FLOOR_TOP, p.sellStall.z),
		toFront,
		Tags.SellStall,
		"판매",
		Color3.fromRGB(240, 40, 50),
		7
	)
	sell:SetAttribute("PlotIndex", index)

	-- 주인 이름 간판 (앞마당 앞 가장자리, 높은 기둥 2개 사이 — 판매 가게 반대쪽으로 비켜서)
	local ownerZ = s.owner.z - 5
	local ownerPos = Vector3.new(s.owner.x, FLOOR_TOP + 11, ownerZ)
	for _, dz in { -5.5, 5.5 } do
		B(plotFolder, Vector3.new(1.2, 13, 1.2), CFrame.new(s.owner.x, FLOOR_TOP + 6.5, ownerZ + dz), POST, true)
	end
	local ownerBoard = makePart({
		name = "PlotSign",
		size = Vector3.new(11, 3.6, 0.8),
		cframe = CFrame.lookAt(ownerPos, ownerPos + toFront),
		parent = plotFolder,
		color = fenceColor,
		material = Enum.Material.Plastic,
		studs = true,
		tag = Tags.PlotSign,
		attributes = { PlotIndex = index },
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local parts = Gui.sign(
			ownerBoard,
			face,
			{ badge = tostring(index), title = "빈 베이스", background = fenceColor:Lerp(BLACK, 0.2) }
		)
		table.insert(dyn.ownerLabels, parts.title)
	end
end

------------------------------------------------------------------
-- 허브 (안전 구역): 바닥·담장·뒤 흰 벽(구름), "안전 구역" 글씨·점선, 판매·트레일 상점·이벤트 포털, 스폰
------------------------------------------------------------------

-- 흰 벽 위 구름+달 그림 (원작: 검은 테두리 회색 구름)
local function cloudArt(parent: Instance, cf: CFrame, scale: number)
	local function disc(x: number, y: number, dd: number, color: Color3, z: number)
		P(
			parent,
			"Cyl",
			Vector3.new(0.3, dd * scale, dd * scale),
			cf * CFrame.new(x * scale, y * scale, z) * CFrame.Angles(0, math.pi / 2, 0),
			color,
			M.SmoothPlastic
		)
	end
	local ink = Color3.fromRGB(25, 25, 30)
	local gray = Color3.fromRGB(60, 62, 72)
	-- 달 (흰 원 + 벽색 원으로 초승달)
	disc(-3, 7, 7.6, ink, -0.1)
	disc(-3, 7, 7, WHITE, -0.2)
	disc(-1.4, 8, 6.2, Color3.fromRGB(245, 245, 248), -0.3)
	-- 구름 (테두리 먼저, 그 위에 회색)
	for _, c in { { 0, 0, 7 }, { 4, 1.4, 6 }, { -4, -0.4, 5 }, { 7, -0.6, 4.4 } } do
		disc(c[1], c[2], c[3] + 0.8, ink, -0.4)
	end
	for _, c in { { 0, 0, 7 }, { 4, 1.4, 6 }, { -4, -0.4, 5 }, { 7, -0.6, 4.4 } } do
		disc(c[1], c[2], c[3], gray, -0.5)
	end
end

local function buildHub(map: Instance)
	local hub = folder("Hub", map)
	local hz0, hz1 = MapLayout.HUB.zMin, MapLayout.HUB.zMax
	local grass, grass2 = Color3.fromRGB(88, 200, 58), Color3.fromRGB(78, 186, 52)
	tiledFloor(hub, -L.HALF, L.HALF, hz0, hz1, function(_x: number): (Color3, Color3)
		return grass, grass2
	end)
	-- 양옆 담장 (숲과 같은 황토색) + 뒤 흰 벽
	local tan, tan2 = Color3.fromRGB(214, 150, 92), Color3.fromRGB(196, 136, 82)
	tiledWall(hub, -1, hz0 - L.WALL_T, hz1, tan, tan2, Color3.fromRGB(85, 185, 55))
	tiledWall(hub, 1, hz0 - L.WALL_T, hz1, tan, tan2, Color3.fromRGB(85, 185, 55))
	local backZ = hz0 - L.WALL_T / 2
	for r = 0, 1 do
		for k = 0, 7 do
			makePart({
				name = "BackWall",
				size = Vector3.new((L.HALF * 2 + L.WALL_T * 2) / 8, L.WALL_H / 2, L.WALL_T),
				cframe = CFrame.new(
					-L.HALF - L.WALL_T + (k + 0.5) * (L.HALF * 2 + L.WALL_T * 2) / 8,
					FLOOR_TOP + (r + 0.5) * L.WALL_H / 2,
					backZ
				),
				parent = hub,
				color = if (k + r) % 2 == 0 then Color3.fromRGB(246, 246, 250) else Color3.fromRGB(232, 232, 240),
				material = Enum.Material.Plastic,
				studs = true,
			})
		end
	end
	cloudArt(
		hub,
		CFrame.lookAt(Vector3.new(-40, FLOOR_TOP + 30, hz0 + 0.2), Vector3.new(-40, FLOOR_TOP + 30, hz0 + 10)),
		2.2
	)
	cloudArt(
		hub,
		CFrame.lookAt(Vector3.new(45, FLOOR_TOP + 34, hz0 + 0.2), Vector3.new(45, FLOOR_TOP + 34, hz0 + 10)),
		1.6
	)

	-- "안전 구역" 글씨 (바닥, 검은 글씨 + 흰 테두리) + 빨간 점선 (z = 0)
	local safe = MapLayout.hubSpots.safeLine
	local textPart = makePart({
		name = "SafeZoneText",
		size = Vector3.new(56, 0.1, 13),
		cframe = CFrame.new(safe.x, FLOOR_TOP + 0.05, safe.z - 11) * CFrame.Angles(0, math.pi, 0),
		parent = hub,
		transparency = 1,
		canCollide = false,
	})
	textPart.CanQuery = false
	local sg = Instance.new("SurfaceGui")
	sg.Name = "SafeZoneText"
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 0
	sg.MaxDistance = 300
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.Font = Enum.Font.FredokaOne
	tl.TextScaled = true
	tl.Text = "안전 구역"
	tl.TextColor3 = Color3.fromRGB(20, 20, 24)
	tl.Parent = sg
	local ts = Instance.new("UIStroke")
	ts.Color = WHITE
	ts.Thickness = 6
	ts.Parent = tl
	sg.Parent = textPart
	for k = 0, 21 do
		P(
			hub,
			"Block",
			Vector3.new(6, 0.1, 1.2),
			CFrame.new(-L.HALF + 5 + k * 10, FLOOR_TOP + 0.05, safe.z - 1.2),
			Color3.fromRGB(235, 60, 90),
			M.Neon
		)
	end
	-- 파란 반원 표시 2개 (원작 경계 옆 둥근 판)
	for _, x in { -40, 40 } do
		P(
			hub,
			"VCyl",
			Vector3.new(8, 0.08, 0),
			CFrame.new(x, FLOOR_TOP + 0.04, safe.z - 6),
			Color3.fromRGB(60, 150, 230),
			M.Plastic
		)
	end

	-- 밤 벽 (허브 경계 z = 0 한 장. 낮에는 투명·통과)
	local nw = MapLayout.NIGHT_WALL
	local night = makePart({
		name = "NightWall",
		size = Vector3.new(nw.xMax - nw.xMin, nw.height, nw.thickness),
		cframe = CFrame.new((nw.xMin + nw.xMax) / 2, FLOOR_TOP + nw.height / 2, nw.z + nw.thickness / 2),
		parent = hub,
		color = Color3.fromRGB(255, 40, 60),
		material = Enum.Material.Neon,
		transparency = 1,
		canCollide = false,
		tag = Tags.NightWall,
		attributes = { NightTransparency = 0.6 },
	})
	night.CastShadow = false

	-- 기본 스폰 (베이스가 없는 사람)
	local ms = MapLayout.hubSpots.mainSpawn
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "MainSpawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = CFrame.new(ms.x, FLOOR_TOP - 0.45, ms.z)
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Color = WHITE
	spawnLocation.Material = Enum.Material.Plastic
	studify(spawnLocation)
	CollectionService:AddTag(spawnLocation, Tags.SpawnLocation)
	spawnLocation.Parent = hub

	-- 판매 가게 / 트레일 상점 (허브 오른쪽 빈 자리, 복도 가운데를 봄)
	local sellPos = MapLayout.hubSpots.sellStall
	local trailPos = MapLayout.hubSpots.trailShop
	local sell = stall(
		hub,
		Vector3.new(sellPos.x, FLOOR_TOP, sellPos.z),
		Vector3.new(-1, 0, 0),
		Tags.SellStall,
		"판매",
		Color3.fromRGB(240, 40, 50)
	)
	floorRing(hub, Vector3.new(sellPos.x - 9, FLOOR_TOP, sellPos.z), 14, Color3.fromRGB(60, 235, 220))
	sell:SetAttribute("Kind", "Sell")
	stall(
		hub,
		Vector3.new(trailPos.x, FLOOR_TOP, trailPos.z),
		Vector3.new(-1, 0, 0),
		Tags.TrailShop,
		"트레일 상점",
		Color3.fromRGB(255, 220, 60)
	)

	-- 이벤트 포털 (장식): 검붉은 바위 아치 + 주황 소용돌이
	local pp = MapLayout.hubSpots.eventPortal
	local portal = model("EventPortal", hub)
	local pcf = CFrame.lookAt(Vector3.new(pp.x, FLOOR_TOP, pp.z), Vector3.new(pp.x - 1, FLOOR_TOP, pp.z))
	local rock = Color3.fromRGB(60, 30, 30)
	for _, s in { -1, 1 } do
		B(portal, Vector3.new(4, 16, 4), pcf * CFrame.new(s * 7, 8, 0), rock, true)
		B(portal, Vector3.new(3, 4, 3), pcf * CFrame.new(s * 8.5, 2, -1), rock:Lerp(BLACK, 0.2), true)
	end
	B(portal, Vector3.new(18, 4, 4), pcf * CFrame.new(0, 17, 0), rock, true)
	local swirl = P(
		portal,
		"Cyl",
		Vector3.new(0.6, 12, 12),
		pcf * CFrame.new(0, 8.5, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(255, 130, 30),
		M.Neon,
		false,
		0.1
	)
	swirl.Name = "Swirl"
	light(swirl, Color3.fromRGB(255, 140, 40), 24, 2)
	twoLine(swirl, 12, "HALLOWEEN DIMENSION", Color3.fromRGB(255, 200, 60), "오픈", "PortalTitle")

	-- 도감 보드 (허브 뒤 흰 벽 앞, 장식)
	local boardPos = Vector3.new(0, FLOOR_TOP + 9, hz0 + 1.2)
	local board = makePart({
		name = "IndexBoard",
		size = Vector3.new(24, 10, 0.8),
		cframe = CFrame.lookAt(boardPos, boardPos + Vector3.new(0, 0, 1)),
		parent = hub,
		color = Color3.fromRGB(60, 170, 235),
		material = Enum.Material.Plastic,
		tag = Tags.IndexBoard,
		studs = true,
	})
	Gui.sign(board, Enum.NormalId.Front, {
		title = "계란 훔치기",
		subtitle = "알을 훔쳐 베이스로 달려가요!",
		background = Color3.fromRGB(60, 170, 235),
	})
end

------------------------------------------------------------------
-- 맵 만들기
------------------------------------------------------------------

local function buildMap(): Folder
	local map = Instance.new("Folder")
	map.Name = "Map"
	buildHub(map)
	task.wait()
	local zonesFolder = folder("Zones", map)
	for _, biome in Biomes.list do
		buildZone(biome, zonesFolder)
		task.wait() -- 구역마다 한 프레임 쉬기 (서버 시작 때 한 번에 수천 개를 만들어 멈추지 않게)
	end
	-- 맵 끝 벽 (마지막 구역 담장 색)
	local lastTheme = Visuals.biomes[Biomes.list[#Biomes.list].id]
	local endWall = rgb(lastTheme.wall)
	for r = 0, 1 do
		for k = 0, 7 do
			makePart({
				name = "EndWall",
				size = Vector3.new((L.HALF * 2 + L.WALL_T * 2) / 8, L.WALL_H / 2, L.WALL_T),
				cframe = CFrame.new(
					-L.HALF - L.WALL_T + (k + 0.5) * (L.HALF * 2 + L.WALL_T * 2) / 8,
					FLOOR_TOP + (r + 0.5) * L.WALL_H / 2,
					MapLayout.MAP_END_Z + L.WALL_T / 2
				),
				parent = zonesFolder,
				color = if (k + r) % 2 == 0 then endWall else endWall:Lerp(BLACK, 0.1),
				material = Enum.Material.Plastic,
				studs = true,
			})
		end
	end
	-- 담장 위 투명 천장 벽 (높이 60 위로 넘어가지 못하게)
	for _, side in { -1, 1 } do
		longPartZ(
			"Boundary",
			side * (L.HALF + L.WALL_T + 1),
			2,
			FLOOR_TOP + L.WALL_H + 40,
			80,
			MapLayout.HUB.zMin - L.WALL_T,
			MapLayout.MAP_END_Z + L.WALL_T,
			map,
			WHITE,
			Enum.Material.SmoothPlastic,
			1
		)
	end
	local plotsFolder = folder("Plots", map)
	for i = 1, MapLayout.PLOT_COUNT do
		buildPlot(i, plotsFolder)
		task.wait()
	end
	map.Parent = Workspace
	return map
end

------------------------------------------------------------------
-- 색인 (태그 읽기)
------------------------------------------------------------------

local function taggedParts(tag: string): { BasePart }
	local result: { BasePart } = {}
	local map = mapFolder
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") and (map == nil or inst:IsDescendantOf(map)) then
			table.insert(result, inst)
		end
	end
	return result
end

local function stringAttr(inst: Instance, name: string): string?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "string" then v else nil
end

local function numberAttr(inst: Instance, name: string): number?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" then v else nil
end

local function indexMap()
	for _, p in taggedParts(Tags.Zone) do
		local biomeId = stringAttr(p, "BiomeId")
		if biomeId then
			zoneParts[biomeId] = p
			zones[biomeId] = {
				centerX = p.Position.X,
				centerZ = p.Position.Z,
				halfX = p.Size.X / 2,
				halfZ = p.Size.Z / 2,
			}
		end
	end
	for _, p in taggedParts(Tags.Nest) do
		local biomeId = stringAttr(p, "BiomeId")
		if biomeId then
			local list = nests[biomeId]
			if not list then
				list = {}
				nests[biomeId] = list
			end
			table.insert(list, p)
		end
	end
	for _, list in nests do
		table.sort(list, function(a: BasePart, b: BasePart): boolean
			return (numberAttr(a, "NestIndex") or 0) < (numberAttr(b, "NestIndex") or 0)
		end)
	end
	for _, p in taggedParts(Tags.GuardSpawn) do
		local biomeId = stringAttr(p, "BiomeId")
		if biomeId then
			guardSpawns[biomeId] = p
		end
	end
	nightWalls = taggedParts(Tags.NightWall)

	for _, p in taggedParts(Tags.Plot) do
		local index = numberAttr(p, "PlotIndex")
		if index then
			plots[index] = { index = index, floor = p }
		end
	end
	local function attach(tag: string, apply: (PlotParts, BasePart) -> ())
		for _, p in taggedParts(tag) do
			local index = numberAttr(p, "PlotIndex")
			local plot = if index then plots[index] else nil
			if plot then
				apply(plot, p)
			end
		end
	end
	attach(Tags.PlotSpawn, function(plot, p)
		plot.spawn = p
	end)
	attach(Tags.Treadmill, function(plot, p)
		plot.treadmill = p
	end)
	attach(Tags.PenArea, function(plot, p)
		plot.pen = p
	end)
	attach(Tags.PlotSign, function(plot, p)
		plot.sign = p
	end)

	for _, biome in Biomes.list do
		if not zones[biome.id] then
			warn("[MapBuilder] Zone 태그가 없는 구역: " .. biome.id)
		end
		if not nests[biome.id] or #nests[biome.id] == 0 then
			warn("[MapBuilder] 둥지가 없는 구역: " .. biome.id)
		end
	end
end

------------------------------------------------------------------
-- 베이스 주인 표시 (이름 간판·업그레이드 표지판·러닝머신 모양)
------------------------------------------------------------------

local function ownerOf(index: number): Player?
	local plot = plots[index]
	local owner = if plot then numberAttr(plot.floor, "OwnerUserId") or 0 else 0
	if owner == 0 then
		return nil
	end
	return Players:GetPlayerByUserId(owner)
end

local function playerNumber(player: Player?, name: string, default: number): number
	if not player then
		return default
	end
	local v = player:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

-- 표지판 숫자·러닝머신 모양을 주인 Attribute(PenLevel/TreadmillLevel)에 맞춤
local function refreshPlot(index: number)
	local dyn = plotDyn[index]
	local plot = plots[index]
	if not dyn or not plot then
		return
	end
	local owner = ownerOf(index)
	local ownerId = numberAttr(plot.floor, "OwnerUserId") or 0
	for _, label in dyn.ownerLabels do
		label.Text = if owner
			then owner.DisplayName .. "의 베이스"
			elseif ownerId ~= 0 then "???의 베이스"
			else "빈 베이스"
	end

	local penLevel = playerNumber(owner, Tags.PlayerAttributes.PenLevel, 1)
	local penSign = dyn.penSign
	if penSign then
		local cost = Economy.nextPenCost(penLevel)
		penSign.level.Text = if cost
			then string.format("레벨 %d > 레벨 %d", penLevel, penLevel + 1)
			else "최대 레벨!"
		penSign.price.Text = if cost then Format.money(cost) else "MAX"
	end

	local treadLevel = playerNumber(owner, Tags.PlayerAttributes.TreadmillLevel, 0)
	local treadSign = dyn.treadSign
	if treadSign then
		local cost = Economy.nextTreadmillCost(treadLevel)
		treadSign.level.Text = if treadLevel <= 0
			then "잠금 해제"
			elseif cost then string.format("레벨 %d > 레벨 %d", treadLevel, treadLevel + 1)
			else "최대 레벨!"
		treadSign.price.Text = if cost then Format.money(cost) else "MAX"
	end
	local step = dyn.stepLabel
	if step then
		step.Text = if treadLevel >= 1
			then "+" .. Format.number(Economy.treadmillPerStep(treadLevel)) .. "/스텝"
			else "잠김 (" .. Format.money(Economy.nextTreadmillCost(0) or 0) .. ")"
	end
	local pad = dyn.pad
	if pad and dyn.lookLevel ~= treadLevel then
		local old = dyn.look
		if old then
			old:Destroy()
		end
		dyn.look = buildTreadmillLook(dyn.folder, pad, treadLevel)
		dyn.lookLevel = treadLevel
		pad:SetAttribute("Level", treadLevel)
	end
end

local function watchOwner(index: number, player: Player?)
	local dyn = plotDyn[index]
	if not dyn then
		return
	end
	for _, c in dyn.conns do
		c:Disconnect()
	end
	table.clear(dyn.conns)
	if player then
		for _, name in { Tags.PlayerAttributes.PenLevel, Tags.PlayerAttributes.TreadmillLevel } do
			table.insert(
				dyn.conns,
				player:GetAttributeChangedSignal(name):Connect(function()
					refreshPlot(index)
				end)
			)
		end
	end
	refreshPlot(index)
end

------------------------------------------------------------------
-- 공개 함수
------------------------------------------------------------------

function MapBuilder.start()
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		mapFolder = existing -- Folder 든 Model 이든 "Map" 이면 그대로 씀
	else
		mapFolder = buildMap()
	end
	local map = mapFolder :: Instance
	for _, name in { "Eggs", "Guardians", "Traps", "Incubating" } do
		local f = map:FindFirstChild(name)
		if f and f:IsA("Folder") then
			dynamicFolders[name] = f
		else
			dynamicFolders[name] = folder(name, map)
		end
	end
	indexMap()
	MapBuilder.setNightWalls(false)
	for index, plot in plots do
		refreshPlot(index)
		plot.floor:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			refreshPlot(index)
		end)
	end
	-- 겉모습 서비스(PetVisualService·EggVisualService)는 Main.server.luau 에서 MapBuilder 다음에 시작합니다.
end

function MapBuilder.getFolder(name: string): Folder
	local f = dynamicFolders[name]
	assert(f, "MapBuilder: 동적 폴더 없음 " .. name)
	return f
end

function MapBuilder.getZone(biomeId: string): Zone?
	return zones[biomeId]
end

function MapBuilder.getZonePart(biomeId: string): BasePart?
	return zoneParts[biomeId]
end

function MapBuilder.getNests(biomeId: string): { BasePart }
	return nests[biomeId] or {}
end

function MapBuilder.getGuardSpawn(biomeId: string): BasePart?
	return guardSpawns[biomeId]
end

function MapBuilder.getPlot(index: number): PlotParts?
	return plots[index]
end

function MapBuilder.plotCount(): number
	local n = 0
	for index in plots do
		n = math.max(n, index)
	end
	return n
end

-- 이 위치가 어느 구역인지 (허브·맵 밖이면 nil) — 판정은 MapLayout(z 범위)
function MapBuilder.findBiomeAt(position: Vector3): string?
	local zone = MapLayout.zoneAt(position.Z)
	if zone == nil or zone == "hub" then
		return nil
	end
	if math.abs(position.X) > MapLayout.HALF_WIDTH + 10 then
		return nil
	end
	return zone
end

-- 안전 구역 = 허브 (z < 0)
function MapBuilder.isInSafeZone(position: Vector3): boolean
	return MapLayout.isInHub(position)
end

-- 이 베이스 영역(울타리 포함 전체) 안인가 → 배달 판정
function MapBuilder.isInPlot(index: number, position: Vector3): boolean
	return MapLayout.isInPlot(position, index)
end

-- 바닥 높이 (아래로 레이캐스트, 캐릭터·알 제외)
function MapBuilder.groundY(position: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = table.clone(ignore)
	for _, name in { "Eggs", "Guardians", "Traps", "Incubating" } do
		local f = dynamicFolders[name]
		if f then
			table.insert(exclude, f)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local result = Workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -100, 0), params)
	if result then
		return result.Position.Y
	end
	return FLOOR_TOP
end

function MapBuilder.setNightWalls(on: boolean)
	for _, wall in nightWalls do
		local nightTransparency = numberAttr(wall, "NightTransparency") or 0.6
		wall.CanCollide = on
		wall.Transparency = if on then nightTransparency else 1
	end
end

function MapBuilder.setPlotOwner(index: number, player: Player?)
	local plot = plots[index]
	if not plot then
		return
	end
	plot.floor:SetAttribute("OwnerUserId", if player then player.UserId else 0)
	watchOwner(index, player)
end

return MapBuilder
