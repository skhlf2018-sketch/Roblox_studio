--!strict
--[[
	MapBuilder — 맵 만들기 (데이터 기반, 기본 도형만 사용) + 맵 정보 색인

	배치 (위에서 본 모습, +Z 가 "멀리"):
	  Z ≈ -75   베이스 7개 (한 줄, 입구가 +Z 쪽)
	  Z ≈ 5     중앙 광장 + 스폰 + 분수
	  Z = 30~   큰 길 (폭 100). 길 양옆으로 구역 15개가 왼쪽/오른쪽 번갈아 놓임
	            1번 숲이 가장 가깝고 15번 유령 성이 가장 멂 (설계문서 4장 순서)

	- 구역 바닥("Zone" 태그)은 축 정렬 직사각형(회전 없음). 서버 로직이 위치·크기로 구역을 판정합니다.
	- 구역마다 테마(바닥 재질·색·장식·분위기 파티클)는 shared/Data/Visuals.luau 의 biomes 표.
	- 이름이 "Map" 인 Instance 가 Workspace 에 이미 있으면 새로 만들지 않고 태그만 읽습니다.
	- 바닥·벽 같은 큰 파트는 전부 한 변 2048 스터드 이하로 나눠 만듭니다(로블록스 한계).
	- 동물(부모 동물·우리 펫·경비)과 알 겉모습은 PetVisualService / EggVisualService 가 붙입니다
	  (start() 끝에서 시작. 본부장이 나중에 Main.server.luau 에 정식 등록 예정).

	태그·Attribute 이름은 shared/Tags.luau 그대로 (서버 로직이 읽음).

	2단계 특수 장소 진짜 모델 (SPECIALS 표): 벚꽃 = 사쿠라 인큐베이터, 천사&악마 = 천국/지옥 제단 + 폭포 옆 비밀 통로,
	마법의 숲 = 퀘스트 문 + 비밀 정원. 태그 파트가 맵에 있으므로 서버 Util/Landmarks 는 임시 파트를 안 만듦.
	베이스 퓨전 머신도 진짜 모델(유리통 3개 Tube1~3 + Core). 클라 연출이 이 이름들을 찾음.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Biomes = require(Shared.Data.Biomes)
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
	deliveryPad: BasePart?,
	treadmill: BasePart?,
	pen: BasePart?,
	sign: BasePart?,
	incubatorSlots: { [number]: BasePart },
}

-- 배치 숫자 (Config.MAP 대신 여기서 관리 — 선임 맵 전용)
local L = {
	ZONE_SIZE = 160,
	ZONE_X = 145, -- 길 중심에서 구역 중심까지
	ZONE_FIRST_Z = 160,
	ZONE_STEP_Z = 120,
	NEST_RADIUS = 46,
	PARENT_RADIUS = 56,
	WALL_HEIGHT = 40,
	PLOT_SIZE = 90,
	PLOT_SPACING = 105,
	PLOT_Z = -75,
	SPAWN_Z = 5,
	ROAD_HALF = 50,
	ROAD_START_Z = 28,
	MAP_HALF_X = 400,
	MAP_MIN_Z = -175,
	MAX_PART = 2000, -- 2048 한계보다 조금 작게
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
local plotSignLabels: { [number]: { TextLabel } } = {}

------------------------------------------------------------------
-- 만들기 도우미
------------------------------------------------------------------

local GROUND_TOP = 0
local FLOOR_TOP = 0.2

local function rgb(c: Color): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function material(name: string): Enum.Material
	local ok, value = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value :: any
	end
	return Enum.Material.SmoothPlastic
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

local function zoneCenter(order: number): Vector3
	local side = if order % 2 == 1 then -1 else 1
	return Vector3.new(side * L.ZONE_X, FLOOR_TOP, L.ZONE_FIRST_Z + (order - 1) * L.ZONE_STEP_Z)
end

-- 구역 입구 표지판 (구역 이름 크게 + 추천 속도 작게)
local function buildZoneSign(biome: Biomes.Biome, theme: BiomeTheme, center: Vector3, toward: number, parent: Instance)
	local x = center.X + toward * (L.ZONE_SIZE / 2 + 7)
	local pos = Vector3.new(x, FLOOR_TOP, center.Z + 28)
	local trim = rgb(theme.trim)
	for _, dz in { -10, 10 } do
		P(
			parent,
			"VCyl",
			Vector3.new(1.2, 13, 0),
			CFrame.new(pos + Vector3.new(0, 6.5, dz)),
			Color3.fromRGB(90, 60, 40),
			M.Wood,
			true
		)
	end
	local boardPos = pos + Vector3.new(0, 10, 0)
	local board = makePart({
		name = "Sign",
		size = Vector3.new(24, 10, 1),
		cframe = CFrame.lookAt(boardPos, boardPos + Vector3.new(toward, 0, 0)),
		parent = parent,
		color = trim,
		material = Enum.Material.SmoothPlastic,
		tag = Tags.ZoneSign,
		attributes = { BiomeId = biome.id },
	})
	Gui.sign(board, Enum.NormalId.Front, {
		badge = tostring(biome.order),
		title = biome.name,
		subtitle = "추천 속도 " .. Format.number(biome.recommendedSpeed),
		corner = if biome.isNew then "NEW!" else nil,
		background = rgb(theme.accent),
		titleColor = Color3.new(1, 1, 1),
	})
	Gui.sign(board, Enum.NormalId.Back, {
		badge = tostring(biome.order),
		title = biome.name,
		subtitle = biome.nameEn,
		background = rgb(theme.accent),
		titleColor = Color3.new(1, 1, 1),
	})
end

-- 둥지: 갈색 원기둥 + 지푸라기 테두리
local function buildNest(biome: Biomes.Biome, index: number, pos: Vector3, parent: Instance)
	local nest = makePart({
		name = "Nest" .. index,
		size = Vector3.new(1.2, 7, 7),
		cframe = CFrame.new(pos.X, FLOOR_TOP + 0.6, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		parent = parent,
		color = Color3.fromRGB(150, 105, 55),
		material = Enum.Material.WoodPlanks,
		shape = Enum.PartType.Cylinder,
		tag = Tags.Nest,
		attributes = { BiomeId = biome.id, NestIndex = index },
	})
	nest.CanQuery = true
	local straw = Color3.fromRGB(235, 200, 110)
	P(
		parent,
		"VCyl",
		Vector3.new(5.4, 0.12, 0),
		CFrame.new(pos.X, FLOOR_TOP + 1.25, pos.Z),
		Color3.fromRGB(215, 175, 90),
		M.Fabric
	)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		P(
			parent,
			"Ell",
			Vector3.new(1.5, 0.8, 3.0),
			CFrame.new(pos.X + math.cos(a) * 3.3, FLOOR_TOP + 1.3, pos.Z + math.sin(a) * 3.3)
				* CFrame.Angles(0, -a, 0.25),
			straw:Lerp(Color3.fromRGB(190, 140, 70), (i % 3) * 0.25),
			M.Fabric
		)
	end
end

type Hole = { x: number, z: number, r: number }

local function buildDecor(
	biome: Biomes.Biome,
	theme: BiomeTheme,
	center: Vector3,
	toward: number,
	parent: Instance,
	reserved: { Hole }?
)
	local rng = Random.new(biome.order * 7919)
	local half = L.ZONE_SIZE / 2 - 4
	local placed: { Hole } = table.clone(reserved or {})
	local function free(x: number, z: number, r: number): boolean
		for _, h in placed do
			local dx, dz = x - h.x, z - h.z
			if dx * dx + dz * dz < (r + h.r) * (r + h.r) then
				return false
			end
		end
		return true
	end
	local function tryPlace(radius: number, sideZ: number?): Vector3?
		for _ = 1, 50 do
			local x = rng:NextNumber(-half + radius, half - radius)
			local z = rng:NextNumber(-half + radius, half - radius)
			local r = math.sqrt(x * x + z * z)
			local okRing = (r > 20 + radius and r < 33 - radius) or r > 66 + radius
			-- 입구(길 쪽 가장자리 가운데)는 비워 둠
			local entrance = x * toward > half - 22 and math.abs(z) < 16
			local sideOk = sideZ == nil or z * sideZ > 4
			if okRing and not entrance and sideOk and free(x, z, radius) then
				table.insert(placed, { x = x, z = z, r = radius })
				return Vector3.new(center.X + x, FLOOR_TOP, center.Z + z)
			end
		end
		return nil
	end

	local decorFolder = folder("Decor", parent)
	for _, spec in theme.decor do
		local kind = spec.kind
		if kind == "heavenhell" then
			-- 천국(앞 -Z 쪽 절반) / 지옥(뒤 +Z 쪽 절반)
			local heaven = Color3.fromRGB(250, 246, 232)
			local hell = Color3.fromRGB(45, 22, 28)
			P(
				decorFolder,
				"Block",
				Vector3.new(L.ZONE_SIZE, 0.1, L.ZONE_SIZE / 2),
				CFrame.new(center.X, FLOOR_TOP + 0.05, center.Z - L.ZONE_SIZE / 4),
				heaven,
				M.Marble
			)
			P(
				decorFolder,
				"Block",
				Vector3.new(L.ZONE_SIZE, 0.1, L.ZONE_SIZE / 2),
				CFrame.new(center.X, FLOOR_TOP + 0.05, center.Z + L.ZONE_SIZE / 4),
				hell,
				M.Basalt
			)
			P(
				decorFolder,
				"Block",
				Vector3.new(L.ZONE_SIZE, 0.14, 1.2),
				CFrame.new(center.X, FLOOR_TOP + 0.07, center.Z),
				Color3.fromRGB(255, 205, 60),
				M.Neon
			)
			for _ = 1, 6 do
				P(
					decorFolder,
					"Block",
					Vector3.new(rng:NextNumber(8, 20), 0.12, 0.5),
					CFrame.new(center.X + rng:NextNumber(-70, 70), FLOOR_TOP + 0.07, center.Z + rng:NextNumber(10, 75))
						* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
					Color3.fromRGB(230, 40, 30),
					M.Neon
				)
				P(
					decorFolder,
					"Block",
					Vector3.new(rng:NextNumber(8, 20), 0.12, 0.4),
					CFrame.new(center.X + rng:NextNumber(-70, 70), FLOOR_TOP + 0.07, center.Z - rng:NextNumber(10, 75))
						* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
					Color3.fromRGB(255, 215, 90),
					M.Neon
				)
			end
		elseif kind == "chocoriver" then
			-- 구역 뒤쪽(길 반대편) 가장자리를 따라 흐르는 초콜릿 강
			local x = center.X - toward * (L.ZONE_SIZE / 2 - 9)
			P(
				decorFolder,
				"Block",
				Vector3.new(12, 0.15, L.ZONE_SIZE - 4),
				CFrame.new(x, FLOOR_TOP + 0.06, center.Z),
				Color3.fromRGB(105, 58, 30),
				M.SmoothPlastic
			)
			P(
				decorFolder,
				"Block",
				Vector3.new(1, 0.4, L.ZONE_SIZE - 4),
				CFrame.new(x + 6.5, FLOOR_TOP + 0.2, center.Z),
				Color3.fromRGB(255, 240, 245)
			)
			P(
				decorFolder,
				"Block",
				Vector3.new(1, 0.4, L.ZONE_SIZE - 4),
				CFrame.new(x - 6.5, FLOOR_TOP + 0.2, center.Z),
				Color3.fromRGB(255, 240, 245)
			)
			table.insert(placed, { x = -toward * (L.ZONE_SIZE / 2 - 9), z = 0, r = 7 })
			for i = 0, 7 do
				table.insert(placed, { x = -toward * (L.ZONE_SIZE / 2 - 9), z = -70 + i * 20, r = 7 })
			end
		elseif kind == "castlewall" then
			-- 구역 뒤쪽 성벽 + 탑 2개
			local x = center.X - toward * (L.ZONE_SIZE / 2 - 3)
			local stone = Color3.fromRGB(95, 90, 105)
			P(
				decorFolder,
				"Block",
				Vector3.new(4, 16, L.ZONE_SIZE - 16),
				CFrame.new(x, FLOOR_TOP + 8, center.Z),
				stone,
				M.Slate,
				true
			)
			for i = 0, 11 do
				P(
					decorFolder,
					"Block",
					Vector3.new(4.4, 2.4, 4),
					CFrame.new(x, FLOOR_TOP + 17.2, center.Z - 66 + i * 12),
					stone,
					M.Slate
				)
			end
			for _, dz in { -1, 1 } do
				local tz = center.Z + dz * (L.ZONE_SIZE / 2 - 8)
				P(
					decorFolder,
					"VCyl",
					Vector3.new(12, 24, 0),
					CFrame.new(x, FLOOR_TOP + 12, tz),
					stone:Lerp(BLACK, 0.1),
					M.Slate,
					true
				)
				for t = 0, 3 do
					P(
						decorFolder,
						"VCyl",
						Vector3.new(13 - t * 3.2, 2.5, 0),
						CFrame.new(x, FLOOR_TOP + 25 + t * 2.5, tz),
						Color3.fromRGB(110, 60, 150),
						M.Slate
					)
				end
				local window = P(
					decorFolder,
					"Block",
					Vector3.new(0.4, 3, 1.6),
					CFrame.new(x + toward * 6, FLOOR_TOP + 15, tz),
					Color3.fromRGB(255, 200, 80),
					M.Neon
				)
				light(window, Color3.fromRGB(255, 180, 80), 16, 1)
			end
			for i = 0, 14 do
				table.insert(placed, { x = -toward * (L.ZONE_SIZE / 2 - 3), z = -70 + i * 10, r = 6 })
			end
		elseif kind == "torii" then
			local pos = Vector3.new(center.X - toward * 70, FLOOR_TOP, center.Z)
			DECOR.torii(decorFolder, pos, rng, theme)
			table.insert(placed, { x = -toward * 70, z = 0, r = 10 })
		else
			local fn = DECOR[kind]
			if fn then
				local radius = if kind == "pyramid"
					then 11
					elseif kind == "volcanocone" then 14
					elseif kind == "pond" or kind == "lilypad" then 10
					elseif kind == "jungletree" then 6
					elseif kind == "gingerhouse" then 8
					elseif kind == "stars" then 1
					else 3.5
				local sideZ: number? = nil
				if kind == "cloud" or kind == "goldpillar" then
					sideZ = -1
				elseif kind == "firepit" or kind == "darkspike" then
					sideZ = 1
				end
				for _ = 1, spec.count do
					local pos = tryPlace(radius, sideZ)
					if pos then
						fn(decorFolder, pos, rng, theme)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------
-- 2단계 특수 장소 진짜 모델 (선임 2차) — 서버 Landmarks 가 같은 태그 파트를 찾으면 임시 파트를 안 만듦
--   태그는 "기준 파트" 하나에만 (서버 거리 판정 = 그 파트 상자 표면). 나머지는 같은 Model 안의 장식.
--   돌려주는 Hole 목록 = 그 자리에 구역 장식이 안 놓이게 비워 둘 곳 (구역 중심 기준 x, z)
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
local function buildFusionMachine(parent: Instance, pos: Vector3, plotIndex: number)
	local m = model("FusionMachineModel", parent)
	local purple = Color3.fromRGB(150, 90, 230)
	local dark = Color3.fromRGB(70, 45, 110)
	local metal = Color3.fromRGB(190, 190, 205)
	local glow = Color3.fromRGB(255, 120, 255)
	P(m, "VCyl", Vector3.new(11, 0.8, 0), CFrame.new(pos + Vector3.new(0, 0.4, 0)), dark, M.Metal, true)
	P(m, "VCyl", Vector3.new(11.6, 0.3, 0), CFrame.new(pos + Vector3.new(0, 0.3, 0)), glow, M.Neon)
	local body = makePart({
		name = "FusionMachine",
		size = Vector3.new(8, 4.5, 5),
		cframe = CFrame.new(pos + Vector3.new(0, 3.05, -0.5)),
		parent = m,
		color = purple,
		material = Enum.Material.SmoothPlastic,
		tag = Tags.FusionMachine,
		attributes = { PlotIndex = plotIndex },
	})
	m.PrimaryPart = body
	P(m, "Block", Vector3.new(8.3, 0.35, 5.3), CFrame.new(pos + Vector3.new(0, 1.15, -0.5)), glow, M.Neon)
	P(m, "Block", Vector3.new(8.6, 0.5, 5.6), CFrame.new(pos + Vector3.new(0, 5.5, -0.5)), dark, M.Metal, true)
	-- 옆 환기구
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			P(
				m,
				"Block",
				Vector3.new(0.2, 0.3, 3.4),
				CFrame.new(pos + Vector3.new(side * 4.05, 2.4 + k * 0.8, -0.5)),
				glow:Lerp(dark, 0.3),
				M.Neon
			)
		end
	end
	-- 앞 윗면 버튼 3개
	for i, c in { Color3.fromRGB(255, 80, 90), Color3.fromRGB(110, 255, 140), Color3.fromRGB(255, 220, 80) } do
		P(m, "Ball", Vector3.new(0.6, 0, 0), CFrame.new(pos + Vector3.new(-1.6 + (i - 1) * 1.6, 5.8, 1.9)), c, M.Neon)
	end
	-- 유리통 3개 + 관
	local corePos = pos + Vector3.new(0, 12.3, -0.8)
	local liquids = { Color3.fromRGB(255, 120, 220), Color3.fromRGB(190, 120, 255), Color3.fromRGB(110, 220, 255) }
	for i, dx in { -2.7, 0, 2.7 } do
		local base = pos + Vector3.new(dx, 0, -0.8)
		P(m, "VCyl", Vector3.new(2.3, 0.45, 0), CFrame.new(base + Vector3.new(0, 5.95, 0)), metal, M.Metal)
		P(
			m,
			"VCyl",
			Vector3.new(1.9, 3.4, 0),
			CFrame.new(base + Vector3.new(0, 7.85, 0)),
			Color3.fromRGB(220, 200, 255),
			M.Glass,
			false,
			0.6
		)
		local liquid =
			P(m, "VCyl", Vector3.new(1.4, 2.2, 0), CFrame.new(base + Vector3.new(0, 7.3, 0)), liquids[i], M.Neon)
		liquid.Name = "Tube" .. i
		P(m, "VCyl", Vector3.new(2.3, 0.45, 0), CFrame.new(base + Vector3.new(0, 9.75, 0)), metal, M.Metal)
		between(m, base + Vector3.new(0, 9.9, 0), corePos, 0.45, metal, M.Metal)
	end
	P(m, "Ball", Vector3.new(4.4, 0, 0), CFrame.new(corePos), Color3.fromRGB(210, 170, 255), M.Glass, false, 0.45)
	local core = P(m, "Ball", Vector3.new(1.9, 0, 0), CFrame.new(corePos), glow, M.Neon)
	core.Name = "Core"
	light(core, Color3.fromRGB(230, 130, 255), 16, 1.6)
	Gui.sign(body, Enum.NormalId.Back, {
		title = "퓨전 머신",
		subtitle = "같은 펫 3마리 → 더 강한 펫!",
		background = Color3.fromRGB(120, 60, 200),
	})
end

-- 사쿠라 인큐베이터 (벚꽃 구역): 큰 벚나무 뿌리 위 분홍 알 받침(태그) + 유리 그릇 + 분홍 알 + 꽃잎 파티클
local function buildSakura(center: Vector3, toward: number, parent: Instance): { Hole }
	local m = model("SakuraIncubatorModel", parent)
	local back = -toward
	local lx = 26 -- 구역 중심에서 길 반대쪽(도리이 쪽)으로
	local pos = Vector3.new(center.X + back * lx, FLOOR_TOP, center.Z)
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
	return { { x = back * lx, z = 0, r = 11 }, { x = back * (lx + 5.5), z = 0, r = 9 } }
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

local function buildAngelsDemons(center: Vector3, toward: number, parent: Instance): { Hole }
	local holes = buildShrine(center, toward, parent)
	-- 천국 = -Z 쪽 절반, 지옥 = +Z 쪽 절반 (heavenhell 바닥과 같음)
	buildAltar("light", Vector3.new(center.X, FLOOR_TOP, center.Z - 27), parent)
	buildAltar("dark", Vector3.new(center.X, FLOOR_TOP, center.Z + 27), parent)
	table.insert(holes, { x = 0, z = -27, r = 9 })
	table.insert(holes, { x = 0, z = 27, r = 9 })
	return holes
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

local SPECIALS: { [string]: (Vector3, number, Instance) -> { Hole } } = {
	cherry_blossom = buildSakura,
	angels_demons = buildAngelsDemons,
	enchanted_forest = buildQuestGate,
}

local function buildZone(biome: Biomes.Biome, parent: Instance)
	local zoneFolder = folder(biome.id, parent)
	local theme = Visuals.biomes[biome.id]
	assert(theme, "Visuals.biomes 에 테마 없음: " .. biome.id)
	local center = zoneCenter(biome.order)
	local size = L.ZONE_SIZE
	local half = size / 2
	local toward = if center.X < 0 then 1 else -1 -- 길 쪽 방향 (+1 = +X)

	local floor = makePart({
		name = "Floor",
		size = Vector3.new(size, 1, size),
		cframe = CFrame.new(center.X, FLOOR_TOP - 0.5, center.Z),
		parent = zoneFolder,
		color = rgb(theme.floor),
		material = material(theme.floorMaterial),
		tag = Tags.Zone,
		attributes = {
			BiomeId = biome.id,
			Order = biome.order,
			RecommendedSpeed = biome.recommendedSpeed,
		},
	})
	if theme.floorMaterial == "Neon" then
		floor.Material = Enum.Material.SmoothPlastic
		floor.Reflectance = 0.1
	end

	-- 테두리
	local trim = rgb(theme.trim)
	for _, e in
		{
			{ Vector3.new(size + 2, 1.2, 1.4), Vector3.new(0, 0, half) },
			{ Vector3.new(size + 2, 1.2, 1.4), Vector3.new(0, 0, -half) },
			{ Vector3.new(1.4, 1.2, size + 2), Vector3.new(half, 0, 0) },
			{ Vector3.new(1.4, 1.2, size + 2), Vector3.new(-half, 0, 0) },
		}
	do
		P(zoneFolder, "Block", e[1], CFrame.new(center + e[2] + Vector3.new(0, 0.1, 0)), trim, M.SmoothPlastic)
	end

	-- 길에서 들어오는 입구 길
	local pathX = center.X + toward * (half + 7.5)
	P(
		zoneFolder,
		"Block",
		Vector3.new(16, 0.2, 30),
		CFrame.new(pathX, FLOOR_TOP - 0.05, center.Z),
		trim:Lerp(Color3.new(1, 1, 1), 0.35),
		M.SmoothPlastic,
		true
	)

	buildZoneSign(biome, theme, center, toward, zoneFolder)

	-- 경비 집 (구역 중심)
	makePart({
		name = "GuardSpawn",
		size = Vector3.new(4, 0.2, 4),
		cframe = CFrame.new(center.X, FLOOR_TOP + 0.1, center.Z),
		parent = zoneFolder,
		transparency = 1,
		canCollide = false,
		tag = Tags.GuardSpawn,
		attributes = { BiomeId = biome.id },
	})
	P(
		zoneFolder,
		"VCyl",
		Vector3.new(16, 0.15, 0),
		CFrame.new(center.X, FLOOR_TOP + 0.04, center.Z),
		trim,
		M.SmoothPlastic
	)
	P(
		zoneFolder,
		"VCyl",
		Vector3.new(13, 0.17, 0),
		CFrame.new(center.X, FLOOR_TOP + 0.05, center.Z),
		rgb(theme.floor):Lerp(Color3.new(0, 0, 0), 0.15),
		material(theme.floorMaterial)
	)

	-- 둥지 8개 + 부모 동물 자리
	for i = 1, biome.nests do
		local angle = (i - 1) / biome.nests * math.pi * 2 + math.pi / biome.nests
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local nestPos = Vector3.new(center.X, FLOOR_TOP, center.Z) + dir * L.NEST_RADIUS
		buildNest(biome, i, nestPos, zoneFolder)

		local spotPos = Vector3.new(center.X, FLOOR_TOP + 0.5, center.Z) + dir * L.PARENT_RADIUS
		makePart({
			name = "ParentAnimal" .. i,
			size = Vector3.new(1, 1, 1),
			cframe = CFrame.lookAt(spotPos, Vector3.new(nestPos.X, spotPos.Y, nestPos.Z)),
			parent = zoneFolder,
			transparency = 1,
			canCollide = false,
			tag = Tags.ParentAnimalSpot,
			attributes = { BiomeId = biome.id, NestIndex = i },
		})
	end

	local builder = SPECIALS[biome.id]
	local reserved = if builder then builder(center, toward, zoneFolder) else nil
	buildDecor(biome, theme, center, toward, zoneFolder, reserved)
	if theme.ambient then
		ambientEmitter(theme.ambient, center, size - 10, zoneFolder, biome.id)
	end

	-- 밤 벽 4개 (낮에는 투명 + 통과). 반투명 빨간 네온.
	local h = L.WALL_HEIGHT
	local wallY = FLOOR_TOP + h / 2
	local walls = {
		{ Vector3.new(size + 2, h, 2), Vector3.new(center.X, wallY, center.Z + half + 1) },
		{ Vector3.new(size + 2, h, 2), Vector3.new(center.X, wallY, center.Z - half - 1) },
		{ Vector3.new(2, h, size + 2), Vector3.new(center.X + half + 1, wallY, center.Z) },
		{ Vector3.new(2, h, size + 2), Vector3.new(center.X - half - 1, wallY, center.Z) },
	}
	for i, w in walls do
		local wall = makePart({
			name = "NightWall" .. i,
			size = w[1],
			cframe = CFrame.new(w[2]),
			parent = zoneFolder,
			color = Color3.fromRGB(255, 40, 60),
			material = Enum.Material.Neon,
			transparency = 1,
			canCollide = false,
			tag = Tags.NightWall,
			attributes = { BiomeId = biome.id, NightTransparency = 0.6 },
		})
		wall.CastShadow = false
	end
end

------------------------------------------------------------------
-- 베이스 (입구 = +Z 쪽, 길을 바라봄)
------------------------------------------------------------------

local function plotCenter(index: number): Vector3
	return Vector3.new((index - (Config.PLOT_COUNT + 1) / 2) * L.PLOT_SPACING, FLOOR_TOP, L.PLOT_Z)
end

local function fenceLine(parent: Instance, from: Vector3, to: Vector3, color: Color3, collide: boolean)
	local length = (to - from).Magnitude
	local dir = (to - from).Unit
	local count = math.max(1, math.floor(length / 3))
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, mid + dir)
	P(parent, "Block", Vector3.new(0.4, 0.4, length), cf * CFrame.new(0, 1.6, 0), color, M.SmoothPlastic, collide)
	P(parent, "Block", Vector3.new(0.4, 0.4, length), cf * CFrame.new(0, 0.8, 0), color, M.SmoothPlastic, false)
	for i = 0, count do
		local p = from + dir * (length * i / count)
		P(
			parent,
			"Block",
			Vector3.new(0.6, 2.4, 0.6),
			CFrame.new(p + Vector3.new(0, 1.2, 0)),
			color,
			M.SmoothPlastic,
			collide
		)
	end
end

local function buildPlot(index: number, parent: Instance)
	local plotFolder = folder("Plot" .. index, parent)
	local c = plotCenter(index)
	local s = L.PLOT_SIZE
	local half = s / 2
	local attrs = { PlotIndex = index }
	local plotColor = rgb(Visuals.plotColors[index] or { 255, 255, 255 })
	local light1 = plotColor:Lerp(Color3.new(1, 1, 1), 0.7)

	makePart({
		name = "Floor",
		size = Vector3.new(s, 1, s),
		cframe = CFrame.new(c.X, FLOOR_TOP - 0.5, c.Z),
		parent = plotFolder,
		color = Color3.fromRGB(245, 240, 228),
		material = Enum.Material.SmoothPlastic,
		tag = Tags.Plot,
		attributes = { PlotIndex = index, OwnerUserId = 0 },
	})
	-- 테두리 색 띠
	for _, e in
		{
			{ Vector3.new(s, 0.3, 2), Vector3.new(0, 0, half - 1) },
			{ Vector3.new(s, 0.3, 2), Vector3.new(0, 0, -half + 1) },
			{ Vector3.new(2, 0.3, s), Vector3.new(half - 1, 0, 0) },
			{ Vector3.new(2, 0.3, s), Vector3.new(-half + 1, 0, 0) },
		}
	do
		P(plotFolder, "Block", e[1], CFrame.new(c + e[2] + Vector3.new(0, 0.1, 0)), plotColor, M.SmoothPlastic)
	end
	-- 울타리 (앞쪽 가운데 입구 24 비움)
	local y0 = FLOOR_TOP
	local fl, fr =
		Vector3.new(c.X - half + 0.5, y0, c.Z + half - 0.5), Vector3.new(c.X + half - 0.5, y0, c.Z + half - 0.5)
	local bl, br =
		Vector3.new(c.X - half + 0.5, y0, c.Z - half + 0.5), Vector3.new(c.X + half - 0.5, y0, c.Z - half + 0.5)
	fenceLine(plotFolder, bl, br, WHITE, true)
	fenceLine(plotFolder, bl, fl, WHITE, true)
	fenceLine(plotFolder, br, fr, WHITE, true)
	fenceLine(plotFolder, fl, Vector3.new(c.X - 12, y0, fl.Z), WHITE, true)
	fenceLine(plotFolder, Vector3.new(c.X + 12, y0, fr.Z), fr, WHITE, true)

	makePart({
		name = "Spawn",
		size = Vector3.new(6, 0.2, 6),
		cframe = CFrame.new(c.X, FLOOR_TOP + 0.1, c.Z + 20),
		parent = plotFolder,
		color = Color3.fromRGB(120, 200, 255),
		transparency = 0.6,
		canCollide = false,
		tag = Tags.PlotSpawn,
		attributes = attrs,
	})

	-- 배달 패드 (빛나는 원)
	local padPos = Vector3.new(c.X, FLOOR_TOP + 0.15, c.Z + 33)
	P(plotFolder, "VCyl", Vector3.new(14, 0.2, 0), CFrame.new(padPos - Vector3.new(0, 0.05, 0)), WHITE, M.SmoothPlastic)
	local pad = makePart({
		name = "DeliveryPad",
		size = Vector3.new(0.3, 12, 12),
		cframe = CFrame.new(padPos) * CFrame.Angles(0, 0, math.rad(90)),
		parent = plotFolder,
		color = Color3.fromRGB(80, 235, 130),
		material = Enum.Material.Neon,
		canCollide = false,
		shape = Enum.PartType.Cylinder,
		tag = Tags.DeliveryPad,
		attributes = attrs,
	})
	pad.CastShadow = false
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Idle"
	sparkle.Texture = SPARKLE_TEX
	sparkle.Rate = 5
	sparkle.Lifetime = NumberRange.new(1.5, 2.5)
	sparkle.Speed = NumberRange.new(2, 4)
	sparkle.EmissionDirection = Enum.NormalId.Right -- 원기둥을 돌렸으므로 Right(+X) = 위쪽
	sparkle.Size = NumberSequence.new(0.5)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(Color3.fromRGB(180, 255, 200))
	sparkle.Parent = pad
	Gui.billboard(pad, "알 배달!", 5, 90).TextColor3 = Color3.fromRGB(200, 255, 210)

	-- 부화 슬롯 8개 (작은 받침)
	for slot = 1, Config.INCUBATOR_SLOTS do
		local x = c.X - (Config.INCUBATOR_SLOTS - 1) * 4.5 + (slot - 1) * 9
		local z = c.Z + 8
		makePart({
			name = "Incubator" .. slot,
			size = Vector3.new(4, 1, 4),
			cframe = CFrame.new(x, FLOOR_TOP + 0.5, z),
			parent = plotFolder,
			color = Color3.fromRGB(255, 245, 215),
			material = Enum.Material.SmoothPlastic,
			tag = Tags.IncubatorSlot,
			attributes = { PlotIndex = index, SlotIndex = slot },
		})
		P(
			plotFolder,
			"VCyl",
			Vector3.new(5.4, 0.6, 0),
			CFrame.new(x, FLOOR_TOP + 0.3, z),
			plotColor,
			M.SmoothPlastic,
			true
		)
		P(
			plotFolder,
			"VCyl",
			Vector3.new(3.6, 0.15, 0),
			CFrame.new(x, FLOOR_TOP + 1.05, z),
			Color3.fromRGB(240, 210, 140),
			M.Fabric
		)
	end

	-- 우리 (울타리 영역)
	local penCenter = Vector3.new(c.X, FLOOR_TOP, c.Z - 17)
	makePart({
		name = "Pen",
		size = Vector3.new(56, 0.2, 26),
		cframe = CFrame.new(penCenter.X, FLOOR_TOP + 0.1, penCenter.Z),
		parent = plotFolder,
		color = Color3.fromRGB(140, 210, 110),
		material = Enum.Material.Grass,
		tag = Tags.PenArea,
		attributes = attrs,
	})
	local brown = Color3.fromRGB(170, 120, 70)
	local p1 = penCenter + Vector3.new(-28, 0, -13)
	local p2 = penCenter + Vector3.new(28, 0, -13)
	local p3 = penCenter + Vector3.new(28, 0, 13)
	local p4 = penCenter + Vector3.new(-28, 0, 13)
	fenceLine(plotFolder, p1, p2, brown, false)
	fenceLine(plotFolder, p2, p3, brown, false)
	fenceLine(plotFolder, p4, p1, brown, false)
	fenceLine(plotFolder, p3, penCenter + Vector3.new(4, 0, 13), brown, false)
	fenceLine(plotFolder, penCenter + Vector3.new(-4, 0, 13), p4, brown, false)

	-- 러닝머신
	local tmPos = Vector3.new(c.X + 32, FLOOR_TOP, c.Z + 30)
	makePart({
		name = "Treadmill",
		size = Vector3.new(8, 0.6, 12),
		cframe = CFrame.new(tmPos.X, FLOOR_TOP + 0.3, tmPos.Z),
		parent = plotFolder,
		color = Color3.fromRGB(45, 45, 50),
		material = Enum.Material.Rubber,
		tag = Tags.Treadmill,
		attributes = attrs,
	})
	for _, side in { -1, 1 } do
		P(
			plotFolder,
			"Block",
			Vector3.new(0.8, 1, 13),
			CFrame.new(tmPos + Vector3.new(side * 4.4, 0.5, 0)),
			plotColor,
			M.SmoothPlastic,
			true
		)
		P(
			plotFolder,
			"VCyl",
			Vector3.new(0.4, 3.6, 0),
			CFrame.new(tmPos + Vector3.new(side * 4.4, 2.4, -5.5)),
			Color3.fromRGB(200, 200, 210),
			M.Metal
		)
	end
	for i = -2, 2 do
		P(
			plotFolder,
			"Block",
			Vector3.new(7.6, 0.05, 0.3),
			CFrame.new(tmPos + Vector3.new(0, 0.62, i * 2.2)),
			Color3.fromRGB(90, 90, 100)
		)
	end
	local console = P(
		plotFolder,
		"Block",
		Vector3.new(9.6, 2.4, 1),
		CFrame.new(tmPos + Vector3.new(0, 4.6, -6.2)) * CFrame.Angles(math.rad(20), 0, 0),
		Color3.fromRGB(60, 60, 70),
		M.SmoothPlastic,
		true
	)
	Gui.sign(
		console,
		Enum.NormalId.Back,
		{ title = "러닝머신", subtitle = "위에 서 있으면 속도 UP!", background = plotColor }
	)

	-- 퓨전 머신 (기계 + 유리통 3개 + 네온, 태그는 몸통)
	buildFusionMachine(plotFolder, Vector3.new(c.X - 32, FLOOR_TOP, c.Z + 30), index)

	-- 도감 보드 (뒤쪽 왼편, +Z 를 바라봄)
	local board = makePart({
		name = "IndexBoard",
		size = Vector3.new(16, 10, 1),
		cframe = CFrame.new(c.X - 30, FLOOR_TOP + 7, c.Z - half + 3),
		parent = plotFolder,
		color = Color3.fromRGB(80, 55, 35),
		material = Enum.Material.Wood,
		tag = Tags.IndexBoard,
		attributes = attrs,
	})
	for _, dx in { -7, 7 } do
		P(
			plotFolder,
			"VCyl",
			Vector3.new(0.8, 7, 0),
			CFrame.new(c.X - 30 + dx, FLOOR_TOP + 3.5, c.Z - half + 3),
			Color3.fromRGB(80, 55, 35),
			M.Wood,
			true
		)
	end
	Gui.sign(board, Enum.NormalId.Back, {
		title = "도감",
		subtitle = "왼쪽 도감 버튼을 눌러 보상을 받아요!",
		background = Color3.fromRGB(255, 170, 50),
	})

	-- 트레일 상점 (뒤쪽 오른편)
	local tsPos = Vector3.new(c.X + 30, FLOOR_TOP, c.Z - 36)
	local shop = makePart({
		name = "TrailShop",
		size = Vector3.new(12, 3.5, 4),
		cframe = CFrame.new(tsPos.X, FLOOR_TOP + 1.75, tsPos.Z),
		parent = plotFolder,
		color = Color3.fromRGB(255, 190, 70),
		material = Enum.Material.Wood,
		tag = Tags.TrailShop,
		attributes = attrs,
	})
	for _, dx in { -5.6, 5.6 } do
		P(
			plotFolder,
			"VCyl",
			Vector3.new(0.6, 8, 0),
			CFrame.new(tsPos + Vector3.new(dx, 4, 1.5)),
			WHITE,
			M.SmoothPlastic,
			true
		)
	end
	for i = 0, 5 do
		local stripe = if i % 2 == 0 then Color3.fromRGB(255, 90, 120) else WHITE
		P(
			plotFolder,
			"Block",
			Vector3.new(2, 0.4, 5.5),
			CFrame.new(tsPos + Vector3.new(-5 + i * 2, 8.2, 1)) * CFrame.Angles(math.rad(-15), 0, 0),
			stripe
		)
	end
	local trailColors = {
		Color3.fromRGB(80, 200, 80),
		Color3.fromRGB(60, 120, 255),
		Color3.fromRGB(160, 80, 230),
		Color3.fromRGB(255, 200, 40),
	}
	for i, tc in trailColors do
		P(
			plotFolder,
			"Ball",
			Vector3.new(1.2, 0, 0),
			CFrame.new(tsPos + Vector3.new(-4.5 + (i - 1) * 3, 4.2, 0)),
			tc,
			M.Neon
		)
	end
	local shopSign = P(
		plotFolder,
		"Block",
		Vector3.new(11, 2.4, 0.4),
		CFrame.new(tsPos + Vector3.new(0, 9.8, 3.4)),
		Color3.fromRGB(255, 90, 120),
		M.SmoothPlastic
	)
	Gui.sign(shopSign, Enum.NormalId.Back, { title = "트레일 상점", background = Color3.fromRGB(255, 90, 120) })
	Gui.sign(
		shop,
		Enum.NormalId.Back,
		{ title = "트레일", subtitle = "상점 버튼에서 사요!", background = Color3.fromRGB(255, 190, 70) }
	)

	-- 주인 이름 표지판 (입구 아치)
	for _, dx in { -13, 13 } do
		P(
			plotFolder,
			"VCyl",
			Vector3.new(1.6, 13, 0),
			CFrame.new(c.X + dx, FLOOR_TOP + 6.5, c.Z + half - 0.5),
			plotColor,
			M.SmoothPlastic,
			true
		)
		P(
			plotFolder,
			"Ball",
			Vector3.new(2.2, 0, 0),
			CFrame.new(c.X + dx, FLOOR_TOP + 13.4, c.Z + half - 0.5),
			light1,
			M.Neon
		)
	end
	makePart({
		name = "OwnerSign",
		size = Vector3.new(26, 5, 1),
		cframe = CFrame.new(c.X, FLOOR_TOP + 11, c.Z + half - 0.5),
		parent = plotFolder,
		color = plotColor,
		tag = Tags.PlotSign,
		attributes = attrs,
	})
end

------------------------------------------------------------------
-- 중앙 광장 / 길
------------------------------------------------------------------

local function buildHub(map: Instance)
	local hub = folder("Hub", map)
	P(
		hub,
		"VCyl",
		Vector3.new(70, 0.2, 0),
		CFrame.new(0, GROUND_TOP + 0.1, L.SPAWN_Z),
		Color3.fromRGB(240, 225, 190),
		M.SmoothPlastic,
		true
	)
	P(
		hub,
		"VCyl",
		Vector3.new(60, 0.22, 0),
		CFrame.new(0, GROUND_TOP + 0.11, L.SPAWN_Z),
		Color3.fromRGB(255, 240, 210),
		M.SmoothPlastic,
		true
	)
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		local c = rgb(Visuals.plotColors[(i % 7) + 1])
		P(
			hub,
			"VCyl",
			Vector3.new(4, 0.24, 0),
			CFrame.new(math.cos(a) * 26, GROUND_TOP + 0.12, L.SPAWN_Z + math.sin(a) * 26),
			c,
			M.SmoothPlastic
		)
	end
	-- 입구 아치 "계란 훔치기"
	local archZ = L.ROAD_START_Z + 6
	for _, x in { -36, 36 } do
		P(
			hub,
			"VCyl",
			Vector3.new(4, 26, 0),
			CFrame.new(x, 13, archZ),
			Color3.fromRGB(255, 200, 80),
			M.SmoothPlastic,
			true
		)
		P(hub, "Ball", Vector3.new(5, 0, 0), CFrame.new(x, 27, archZ), Color3.fromRGB(255, 120, 160), M.SmoothPlastic)
	end
	local arch = P(
		hub,
		"Block",
		Vector3.new(64, 8, 2),
		CFrame.new(0, 23, archZ),
		Color3.fromRGB(255, 130, 170),
		M.SmoothPlastic,
		true
	)
	Gui.sign(arch, Enum.NormalId.Front, {
		title = "계란 훔치기",
		subtitle = "구역 1~15 · 멀리 갈수록 비싼 알!",
		background = Color3.fromRGB(255, 130, 170),
	})
	Gui.sign(arch, Enum.NormalId.Back, {
		title = "내 베이스",
		subtitle = "알을 배달 패드에 올려요!",
		background = Color3.fromRGB(255, 130, 170),
	})
	-- 길 가로등
	local roadEnd = L.ZONE_FIRST_Z + (Biomes.count - 1) * L.ZONE_STEP_Z + L.ZONE_SIZE / 2
	local z = L.ROAD_START_Z + 40
	while z < roadEnd do
		for _, x in { -L.ROAD_HALF + 2, L.ROAD_HALF - 2 } do
			P(hub, "VCyl", Vector3.new(0.8, 10, 0), CFrame.new(x, 5, z), Color3.fromRGB(70, 70, 80), M.Metal, true)
			local bulb =
				P(hub, "Ball", Vector3.new(2, 0, 0), CFrame.new(x, 10.6, z), Color3.fromRGB(255, 235, 170), M.Neon)
			light(bulb, Color3.fromRGB(255, 220, 160), 22, 1)
		end
		z += 90
	end
end

local function buildMap(): Folder
	local map = Instance.new("Folder")
	map.Name = "Map"

	local roadEnd = L.ZONE_FIRST_Z + (Biomes.count - 1) * L.ZONE_STEP_Z + L.ZONE_SIZE / 2 + 10
	local mapMaxZ = roadEnd + 50
	-- 바닥 (2048 한계 → 나눠서)
	longPartZ(
		"Ground",
		0,
		L.MAP_HALF_X * 2,
		GROUND_TOP - 1,
		2,
		L.MAP_MIN_Z,
		mapMaxZ,
		map,
		Color3.fromRGB(120, 195, 95),
		Enum.Material.Grass
	)
	longPartZ(
		"Road",
		0,
		L.ROAD_HALF * 2,
		GROUND_TOP + 0.05,
		0.1,
		L.ROAD_START_Z,
		roadEnd,
		map,
		Color3.fromRGB(230, 215, 180),
		Enum.Material.SmoothPlastic
	)
	for _, x in { -L.ROAD_HALF + 0.5, L.ROAD_HALF - 0.5 } do
		longPartZ(
			"RoadEdge",
			x,
			1,
			GROUND_TOP + 0.08,
			0.16,
			L.ROAD_START_Z,
			roadEnd,
			map,
			Color3.fromRGB(255, 255, 255),
			Enum.Material.SmoothPlastic,
			nil,
			false
		)
	end
	-- 바깥 투명 벽
	local wallH = 120
	for _, x in { -L.MAP_HALF_X, L.MAP_HALF_X } do
		longPartZ(
			"Boundary",
			x,
			2,
			wallH / 2,
			wallH,
			L.MAP_MIN_Z,
			mapMaxZ,
			map,
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			1
		)
	end
	for _, z in { L.MAP_MIN_Z, mapMaxZ } do
		makePart({
			name = "Boundary",
			size = Vector3.new(L.MAP_HALF_X * 2, wallH, 2),
			cframe = CFrame.new(0, wallH / 2, z),
			parent = map,
			transparency = 1,
		})
	end

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "MainSpawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = CFrame.new(0, FLOOR_TOP - 0.3, L.SPAWN_Z)
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Color = Color3.fromRGB(255, 255, 255)
	spawnLocation.Material = Enum.Material.SmoothPlastic
	CollectionService:AddTag(spawnLocation, Tags.SpawnLocation)
	spawnLocation.Parent = map

	buildHub(map)
	local zonesFolder = folder("Zones", map)
	for _, biome in Biomes.list do
		buildZone(biome, zonesFolder)
	end
	local plotsFolder = folder("Plots", map)
	for i = 1, Config.PLOT_COUNT do
		buildPlot(i, plotsFolder)
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
			plots[index] = { index = index, floor = p, incubatorSlots = {} }
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
	attach(Tags.DeliveryPad, function(plot, p)
		plot.deliveryPad = p
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
	attach(Tags.IncubatorSlot, function(plot, p)
		local slot = numberAttr(p, "SlotIndex")
		if slot then
			plot.incubatorSlots[slot] = p
		end
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
-- 주인 표지판
------------------------------------------------------------------

local function ownerText(userId: number): string
	if userId == 0 then
		return "빈 베이스"
	end
	local player = Players:GetPlayerByUserId(userId)
	return (if player then player.DisplayName else "???") .. "의 베이스"
end

local function signLabels(index: number): { TextLabel }
	local labels = plotSignLabels[index]
	if labels then
		return labels
	end
	labels = {}
	local plot = plots[index]
	local sign = if plot then plot.sign else nil
	if sign then
		for _, face in { Enum.NormalId.Back, Enum.NormalId.Front } do
			local parts =
				Gui.sign(sign, face, { badge = tostring(index), title = "빈 베이스", background = sign.Color })
			table.insert(labels, parts.title)
		end
	end
	plotSignLabels[index] = labels
	return labels
end

local function refreshSign(index: number)
	local plot = plots[index]
	if not plot then
		return
	end
	local owner = numberAttr(plot.floor, "OwnerUserId") or 0
	for _, label in signLabels(index) do
		label.Text = ownerText(owner)
	end
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
		refreshSign(index)
		plot.floor:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			refreshSign(index)
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

-- 이 위치가 어느 구역인지 (없으면 nil)
function MapBuilder.findBiomeAt(position: Vector3): string?
	for biomeId, zone in zones do
		if EggRules.isInsideZone(zone, position.X, position.Z) then
			return biomeId
		end
	end
	return nil
end

-- 안전 구역 = 아무 베이스 중심에서 SAFE_ZONE_RADIUS 안
function MapBuilder.isInSafeZone(position: Vector3): boolean
	for _, plot in plots do
		local c = plot.floor.Position
		if EggRules.isWithinRadius(c.X, c.Z, Config.SAFE_ZONE_RADIUS, position.X, position.Z) then
			return true
		end
	end
	return false
end

function MapBuilder.isInPlot(index: number, position: Vector3): boolean
	local plot = plots[index]
	if not plot then
		return false
	end
	local c = plot.floor.Position
	return EggRules.isWithinRadius(c.X, c.Z, Config.SAFE_ZONE_RADIUS, position.X, position.Z)
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
	refreshSign(index)
	if player then
		-- DisplayName 은 바로 있지만, 혹시 늦게 들어온 경우를 위해 한 번 더
		for _, label in signLabels(index) do
			label.Text = player.DisplayName .. "의 베이스"
		end
	end
end

return MapBuilder
