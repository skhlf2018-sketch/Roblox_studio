--!strict
--[[
	PetVisualService — 동물 생김새 (서버가 만들어서 모두가 같은 모양을 봄). 선임 담당.

	- 모든 모양은 기본 도형(Block/Ball/Cylinder/Wedge + SpecialMesh 타원체)을 코드로 조합.
	- petId → shared/Data/Visuals.luau 의 체형 템플릿 + 색 3개 + 장식(features).
	- 만드는 것:
	    1) ReplicatedStorage.PetModels   134종 + 경비 전용 모양 (크기 1, 효과 없음) → 클라 UI 의 ViewportFrame 이 복제해서 씀
	    2) 둥지 옆 부모 동물 (ParentAnimalSpot 태그 자리, 큰 크기 + 희귀도 빛 + 이름표)
	    3) 우리(PenArea)에 장착 펫 진열 (최대 18마리, 원형 2줄, 머리 위 이름·초당 수입·크기/돌연변이)
	    4) 경비(Guardian 태그) 겉모습 — HumanoidRootPart 에 용접 (Humanoid·HumanoidRootPart 이름은 그대로)
	- 통통 튀는 애니메이션·희귀도 Highlight 개수 제한(31개)은 클라 WorldFxController 가 처리.

	모델 좌표: Root 파트가 "바닥 한가운데", 앞 = -Z (LookVector), 위 = +Y. 크기 1 일 때 키 약 2~3.5 스터드.
	시작: MapBuilder.start() 끝에서 start() (본부장이 나중에 Main.server.luau 에 정식 등록 예정).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Data.Pets)
local Biomes = require(Shared.Data.Biomes)
local Rarities = require(Shared.Data.Rarities)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local Visuals = require(Shared.Data.Visuals)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Sessions = require(Server.Sessions)
local Gui = require(Server.Util.Gui)

type Color = Visuals.Color

type Ctx = {
	model: Model,
	root: BasePart,
	s: number,
	c1: Color3,
	c2: Color3,
	c3: Color3,
	mat: Enum.Material,
	accentMat: Enum.Material,
	has: { [string]: boolean },
	body: BasePart?,
	bodyKind: string,
}

type Anchors = {
	head: CFrame,
	headSize: Vector3,
	body: CFrame,
	bodySize: Vector3,
	tail: CFrame,
	top: number,
	hand: CFrame?,
	segments: { CFrame }?,
	skipEyes: boolean?,
	upright: boolean?,
	kind: string?,
}

export type BuildOptions = {
	effects: boolean?, -- 희귀도 Highlight/파티클/빛
	rarity: string?, -- 펫 데이터에 없는 모양(경비 전용)일 때
}

local PetVisualService = {}
PetVisualService.started = false

------------------------------------------------------------------
-- 도우미
------------------------------------------------------------------

local NEON = Enum.Material.Neon
local FOIL = Enum.Material.Foil
local BLACK = Color3.fromRGB(25, 25, 32)
local WHITE = Color3.new(1, 1, 1)
local PINK = Color3.fromRGB(255, 165, 195)
local RED = Color3.fromRGB(235, 60, 60)
local GOLD = Color3.fromRGB(255, 205, 50)
local SILVER = Color3.fromRGB(212, 218, 228)
local BONE = Color3.fromRGB(242, 236, 216)
local YELLOW = Color3.fromRGB(255, 225, 70)
local GREEN = Color3.fromRGB(80, 175, 70)
local BLUE = Color3.fromRGB(60, 120, 255)
local PEACH = Color3.fromRGB(255, 210, 175)
local DARK = Color3.fromRGB(60, 58, 70)
local WOOD = Color3.fromRGB(90, 60, 40)
local SIDES = { -1, 1 }

local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

local function rgb(c: Color): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function rad(d: number): number
	return math.rad(d)
end

local function at(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end

local function materialOf(name: string?): Enum.Material
	if not name then
		return Enum.Material.SmoothPlastic
	end
	local ok, value = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value :: any
	end
	return Enum.Material.SmoothPlastic
end

-- 파트 하나 추가 (크기·위치는 크기 1 기준으로 받아서 ctx.s 배 함)
local function add(
	ctx: Ctx,
	kind: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	transparency: number?
): BasePart
	local s = ctx.s
	local p = Instance.new("Part")
	p.Name = "Piece"
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Material = mat or ctx.mat
	p.Transparency = transparency or 0
	local scaled = size * s
	if kind == "Ball" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * math.max(0.05, scaled.X)
	elseif kind == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = scaled
	elseif kind == "Wedge" then
		p.Shape = Enum.PartType.Wedge
		p.Size = scaled
	elseif kind == "Ell" then
		p.Size = scaled
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	else
		p.Size = scaled
	end
	p.CFrame = ctx.root.CFrame * CFrame.new(cf.Position * s) * cf.Rotation
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = ctx.model
	return p
end

local function ell(
	ctx: Ctx,
	x: number,
	y: number,
	z: number,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	tr: number?
): BasePart
	return add(ctx, "Ell", Vector3.new(x, y, z), cf, color, mat, tr)
end

local function ball(ctx: Ctx, d: number, cf: CFrame, color: Color3, mat: Enum.Material?, tr: number?): BasePart
	return add(ctx, "Ball", Vector3.new(d, d, d), cf, color, mat, tr)
end

local function blk(
	ctx: Ctx,
	x: number,
	y: number,
	z: number,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	tr: number?
): BasePart
	return add(ctx, "Block", Vector3.new(x, y, z), cf, color, mat, tr)
end

-- 세운 원기둥 (len = 높이)
local function vcyl(
	ctx: Ctx,
	len: number,
	d: number,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	tr: number?
): BasePart
	return add(ctx, "Cyl", Vector3.new(len, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, mat, tr)
end

-- 앞을 보는 원판 (축 = Z)
local function disc(ctx: Ctx, thick: number, d: number, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
	return add(ctx, "Cyl", Vector3.new(thick, d, d), cf * CFrame.Angles(0, math.pi / 2, 0), color, mat)
end

local function hf(a: Anchors, x: number, y: number, z: number): CFrame
	local hs = a.headSize
	return a.head * CFrame.new(x * hs.X, y * hs.Y, z * hs.Z)
end

local function eyesAt(ctx: Ctx, head: CFrame, hs: Vector3)
	local e = math.max(0.12, math.min(hs.X, hs.Y) * 0.22)
	local glow = ctx.has.eyes_glow == true
	for _, side in SIDES do
		local pos = head * CFrame.new(side * hs.X * 0.23, hs.Y * 0.1, -hs.Z * 0.42)
		if glow then
			ball(ctx, e * 1.05, pos, ctx.c3, NEON)
		else
			ball(ctx, e, pos, BLACK)
			ball(ctx, e * 0.38, pos * CFrame.new(side * e * 0.12, e * 0.18, -e * 0.38), WHITE)
		end
	end
end

local function eyeColor(ctx: Ctx): (Color3, Enum.Material)
	if ctx.has.eyes_glow then
		return ctx.c3, NEON
	end
	return BLACK, Enum.Material.SmoothPlastic
end

------------------------------------------------------------------
-- 체형 템플릿 (17종)
------------------------------------------------------------------

local TEMPLATES: { [string]: (Ctx) -> Anchors } = {}

TEMPLATES.quad = function(ctx: Ctx): Anchors
	local has = ctx.has
	local k = if has.trunk then 1.25 else 1
	local bodyCF = at(0, 1.4 * k, 0)
	local bs = Vector3.new(1.6, 1.2, 2.2) * k
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, bs.X * 0.75, bs.Y * 0.65, bs.Z * 0.78, bodyCF * CFrame.new(0, -bs.Y * 0.2, -0.05), ctx.c2)
	for _, x in SIDES do
		for _, z in SIDES do
			vcyl(ctx, 1.0 * k, 0.45 * k, at(x * 0.5 * k, 0.5 * k, z * 0.7 * k), ctx.c1)
			ell(ctx, 0.5 * k, 0.25 * k, 0.6 * k, at(x * 0.5 * k, 0.1, z * 0.7 * k - 0.08), ctx.c2)
		end
	end
	local head: CFrame
	local hs: Vector3
	if has.torso then
		ell(ctx, 0.9, 1.2, 0.7, at(0, 2.35, -0.95), ctx.c2)
		for _, side in SIDES do
			ell(ctx, 0.3, 1.0, 0.3, at(side * 0.6, 2.3, -0.95, 0, 0, side * 12), ctx.c2)
		end
		head = at(0, 3.3, -0.95)
		hs = Vector3.new(0.8, 0.8, 0.8)
		ball(ctx, 0.8, head, PEACH)
		ell(ctx, 0.86, 0.45, 0.86, head * CFrame.new(0, 0.25, 0.08), ctx.c3)
	elseif has.long_neck then
		ell(ctx, 0.55 * k, 1.7 * k, 0.55 * k, at(0, 2.4 * k, -1.15 * k, -28, 0, 0), ctx.c1)
		head = at(0, 3.25 * k, -1.6 * k)
		hs = Vector3.new(0.85, 0.8, 1.0) * k
		ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	else
		head = at(0, 2.15 * k, -1.3 * k)
		hs = Vector3.new(1.15, 1.05, 1.05) * k
		ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	end
	if not has.torso then
		ell(ctx, hs.X * 0.55, hs.Y * 0.45, hs.Z * 0.5, head * CFrame.new(0, -hs.Y * 0.2, -hs.Z * 0.42), ctx.c2)
		ball(ctx, hs.X * 0.18, head * CFrame.new(0, -hs.Y * 0.05, -hs.Z * 0.68), BLACK)
	end
	local tail = at(0, 1.75 * k, 1.1 * k)
	if not (has.tail_fluffy or has.nine_tails or has.club) then
		ell(ctx, 0.22, 0.22, 0.9, tail * CFrame.Angles(rad(-40), 0, 0) * CFrame.new(0, 0, 0.4), ctx.c1)
	end
	return { head = head, headSize = hs, body = bodyCF, bodySize = bs, tail = tail, top = head.Position.Y + hs.Y / 2 }
end

TEMPLATES.bird = function(ctx: Ctx): Anchors
	local has = ctx.has
	local bodyCF = at(0, 1.3, 0)
	local bs = Vector3.new(1.4, 1.5, 1.6)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, 1.05, 1.1, 0.9, at(0, 1.15, -0.4), ctx.c2)
	local head: CFrame
	local hs: Vector3
	if has.long_neck then
		ell(ctx, 0.36, 1.6, 0.36, at(0, 2.4, -0.55, -10, 0, 0), ctx.c1)
		head = at(0, 3.25, -0.75)
		hs = Vector3.new(0.75, 0.7, 0.8)
	else
		head = at(0, 2.3, -0.35)
		hs = Vector3.new(1, 1, 1)
	end
	ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	if not has.beak_big then
		ell(ctx, hs.X * 0.32, hs.Y * 0.22, hs.Z * 0.5, head * CFrame.new(0, -hs.Y * 0.1, -hs.Z * 0.55), ctx.c3)
	end
	if not has.bat_wings then
		for _, side in SIDES do
			ell(ctx, 0.25, 0.95, 1.15, at(side * 0.72, 1.4, 0.1, 0, 0, -side * 12), ctx.c1:Lerp(BLACK, 0.12))
		end
	end
	for _, side in SIDES do
		vcyl(ctx, 0.55, 0.14, at(side * 0.32, 0.33, 0.05), ctx.c3)
		ell(ctx, 0.35, 0.12, 0.45, at(side * 0.32, 0.06, -0.08), ctx.c3)
	end
	local tail = at(0, 1.35, 0.85)
	if not has.peacock_tail then
		ell(ctx, 0.7, 0.18, 0.8, tail * CFrame.Angles(rad(-25), 0, 0) * CFrame.new(0, 0, 0.25), ctx.c1)
	end
	return { head = head, headSize = hs, body = bodyCF, bodySize = bs, tail = tail, top = head.Position.Y + hs.Y / 2 }
end

TEMPLATES.fish = function(ctx: Ctx): Anchors
	local has = ctx.has
	local bodyCF = at(0, 1.5, 0)
	local bs = Vector3.new(0.9, 1.3, 2.2)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, 0.72, 0.8, 1.7, at(0, 1.25, -0.1), ctx.c2)
	ell(ctx, 0.12, 0.9, 0.75, at(0, 1.78, 1.35, -35, 0, 0), ctx.c3, ctx.accentMat)
	ell(ctx, 0.12, 0.9, 0.75, at(0, 1.22, 1.35, 35, 0, 0), ctx.c3, ctx.accentMat)
	if not has.fin_big then
		ell(ctx, 0.12, 0.6, 0.8, at(0, 2.15, 0.1, 20, 0, 0), ctx.c3, ctx.accentMat)
	end
	for _, side in SIDES do
		ell(ctx, 0.45, 0.08, 0.4, at(side * 0.5, 1.25, -0.25, 0, 0, -side * 25), ctx.c3, ctx.accentMat)
	end
	local head = at(0, 1.6, -0.75)
	local hs = Vector3.new(0.9, 1.0, 0.8)
	local ec, em = eyeColor(ctx)
	for _, side in SIDES do
		local p = at(side * 0.38, 1.7, -0.62)
		ball(ctx, 0.26, p, ec, em)
		if not has.eyes_glow then
			ball(ctx, 0.1, p * CFrame.new(side * 0.08, 0.05, -0.06), WHITE)
		end
	end
	return {
		head = head,
		headSize = hs,
		body = bodyCF,
		bodySize = bs,
		tail = at(0, 1.5, 1.1),
		top = 2.4,
		skipEyes = true,
	}
end

TEMPLATES.snake = function(ctx: Ctx): Anchors
	local segs: { CFrame } = {}
	local n = 7
	for i = 1, n do
		local t = (i - 1) / (n - 1)
		local d = 0.85 - t * 0.45
		local c = at(math.sin(t * math.pi * 1.5) * 0.45, d * 0.45, -0.2 + t * 2.7)
		local part = ball(ctx, d, c, if i % 2 == 0 then ctx.c2 else ctx.c1)
		if i == 1 then
			ctx.body = part
		end
		table.insert(segs, c)
	end
	ball(ctx, 0.75, at(0, 0.75, -0.55), ctx.c1)
	ball(ctx, 0.68, at(0, 1.1, -0.78), ctx.c2)
	local head = at(0, 1.45, -0.95)
	local hs = Vector3.new(0.85, 0.6, 1.0)
	ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	blk(ctx, 0.06, 0.03, 0.45, head * CFrame.new(0, -0.15, -0.65), RED)
	return {
		head = head,
		headSize = hs,
		body = at(0, 0.5, 0.6),
		bodySize = Vector3.new(0.9, 0.8, 2.6),
		tail = segs[n],
		top = 1.8,
		segments = segs,
	}
end

TEMPLATES.bug = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 0.8, 0.25)
	local bs = Vector3.new(1.3, 0.8, 1.8)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	for _, side in SIDES do
		ell(ctx, 0.68, 0.5, 1.6, at(side * 0.32, 0.95, 0.3), ctx.c2)
	end
	local head = at(0, 0.8, -0.8)
	local hs = Vector3.new(0.75, 0.65, 0.7)
	ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1:Lerp(BLACK, 0.2))
	for _, side in SIDES do
		for _, z in { -0.35, 0.25, 0.85 } do
			blk(ctx, 0.9, 0.1, 0.1, at(side * 0.8, 0.45, z, 0, 0, -side * 30), ctx.c1:Lerp(BLACK, 0.3))
		end
		local ant = head * CFrame.new(side * 0.18, 0.3, -0.25) * CFrame.Angles(rad(35), side * 0.3, 0)
		blk(ctx, 0.06, 0.06, 0.7, ant * CFrame.new(0, 0, -0.35), BLACK)
		ball(ctx, 0.14, ant * CFrame.new(0, 0, -0.7), ctx.c3, ctx.accentMat)
	end
	return { head = head, headSize = hs, body = bodyCF, bodySize = bs, tail = at(0, 0.8, 1.1), top = 1.3 }
end

TEMPLATES.spider = function(ctx: Ctx): Anchors
	local abdomen = at(0, 1.1, 0.55)
	ctx.body = ball(ctx, 1.35, abdomen, ctx.c1)
	if not ctx.has.pumpkin then
		ball(ctx, 0.55, at(0, 1.72, 0.62), ctx.c2)
	end
	local ceph = at(0, 0.95, -0.35)
	ball(ctx, 0.85, ceph, ctx.c1:Lerp(BLACK, 0.1))
	local legColor = ctx.c1:Lerp(BLACK, 0.25)
	for _, side in SIDES do
		for _, z in { -0.6, -0.3, 0.0, 0.3 } do
			local yaw = CFrame.Angles(0, -side * z * 0.8, 0)
			blk(
				ctx,
				1.2,
				0.12,
				0.12,
				at(0, 1.0, z) * yaw * CFrame.new(side * 0.75, 0.2, 0) * CFrame.Angles(0, 0, rad(side * 25)),
				legColor
			)
			blk(
				ctx,
				1.3,
				0.12,
				0.12,
				at(0, 1.0, z) * yaw * CFrame.new(side * 1.55, -0.3, 0) * CFrame.Angles(0, 0, rad(-side * 60)),
				legColor
			)
		end
	end
	local ec, em = eyeColor(ctx)
	for _, side in SIDES do
		ball(ctx, 0.22, ceph * CFrame.new(side * 0.15, 0.12, -0.36), ec, em)
		ball(ctx, 0.13, ceph * CFrame.new(side * 0.3, 0.24, -0.28), ec, em)
	end
	return {
		head = ceph,
		headSize = Vector3.new(0.85, 0.85, 0.85),
		body = abdomen,
		bodySize = Vector3.new(1.35, 1.35, 1.35),
		tail = at(0, 1.1, 1.2),
		top = 1.8,
		skipEyes = true,
	}
end

TEMPLATES.dragon = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 1.6, 0.1)
	local bs = Vector3.new(1.6, 1.4, 2.4)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, 1.15, 1.0, 2.0, at(0, 1.35, 0), ctx.c2)
	ell(ctx, 0.65, 1.2, 0.65, at(0, 2.45, -1.0, -35, 0, 0), ctx.c1)
	local head = at(0, 3.0, -1.55)
	local hs = Vector3.new(0.95, 0.8, 1.3)
	ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	ell(ctx, 0.7, 0.45, 0.7, head * CFrame.new(0, -0.12, -0.55), ctx.c2)
	for _, side in SIDES do
		ball(ctx, 0.1, head * CFrame.new(side * 0.15, -0.02, -0.9), BLACK)
	end
	for _, x in SIDES do
		for _, z in SIDES do
			vcyl(ctx, 1.0, 0.5, at(x * 0.6, 0.5, z * 0.8), ctx.c1)
			ell(ctx, 0.55, 0.22, 0.65, at(x * 0.6, 0.1, z * 0.8 - 0.1), ctx.c3, ctx.accentMat)
		end
	end
	ell(ctx, 0.8, 0.7, 1.4, at(0, 1.4, 1.55, -10, 0, 0), ctx.c1)
	ell(ctx, 0.55, 0.5, 1.2, at(0, 1.15, 2.35), ctx.c1)
	ell(ctx, 0.35, 0.35, 1.0, at(0, 0.95, 3.05), ctx.c1)
	ell(ctx, 0.55, 0.12, 0.65, at(0, 0.95, 3.6), ctx.c3, ctx.accentMat)
	for _, side in SIDES do
		local root = at(side * 0.6, 2.2, 0.1) * CFrame.Angles(0, 0, rad(side * 25))
		blk(ctx, 2.2, 0.08, 1.5, root * CFrame.new(side * 1.1, 0, 0.1), ctx.c3, ctx.accentMat, 0.05)
		add(ctx, "Cyl", Vector3.new(2.3, 0.16, 0.16), root * CFrame.new(side * 1.1, 0.04, -0.65), ctx.c1)
	end
	return { head = head, headSize = hs, body = bodyCF, bodySize = bs, tail = at(0, 0.95, 3.0), top = 3.4 }
end

TEMPLATES.ghost = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 2.0, 0)
	ctx.body = ball(ctx, 1.7, bodyCF, ctx.c1)
	vcyl(ctx, 1.0, 1.7, at(0, 1.35, 0), ctx.c1)
	for i = 1, 6 do
		local t = i / 6 * math.pi * 2
		ball(ctx, 0.55, at(math.cos(t) * 0.62, 0.85, math.sin(t) * 0.62), ctx.c1)
	end
	for _, side in SIDES do
		ell(ctx, 0.4, 0.75, 0.4, at(side * 0.95, 1.8, -0.1, 0, 0, side * 40), ctx.c1)
		ball(ctx, 0.25, at(side * 0.42, 1.85, -0.76), PINK)
	end
	return {
		head = bodyCF,
		headSize = Vector3.new(1.55, 1.55, 1.55),
		body = bodyCF,
		bodySize = Vector3.new(1.7, 1.7, 1.7),
		tail = at(0, 1.2, 0.8),
		top = 2.85,
		upright = true,
	}
end

TEMPLATES.humanoid = function(ctx: Ctx): Anchors
	for _, side in SIDES do
		vcyl(ctx, 0.9, 0.55, at(side * 0.35, 0.45, 0), ctx.c2)
		ell(ctx, 0.6, 0.25, 0.75, at(side * 0.35, 0.1, -0.1), ctx.c2:Lerp(BLACK, 0.2))
	end
	local bodyCF = at(0, 1.55, 0)
	local bs = Vector3.new(1.45, 1.5, 1.05)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, 1.0, 1.0, 0.6, at(0, 1.45, -0.25), ctx.c2)
	for _, side in SIDES do
		ell(ctx, 0.45, 1.25, 0.45, at(side * 0.92, 1.5, 0, 0, 0, side * 10), ctx.c1)
		ball(ctx, 0.45, at(side * 1.02, 0.88, 0), ctx.c2)
	end
	local head = at(0, 2.75, 0)
	local hs = Vector3.new(1.1, 1.1, 1.05)
	ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	ell(ctx, 0.75, 0.6, 0.35, head * CFrame.new(0, -0.12, -0.38), ctx.c2)
	return {
		head = head,
		headSize = hs,
		body = bodyCF,
		bodySize = bs,
		tail = at(0, 1.2, 0.5),
		top = 3.3,
		hand = at(1.05, 0.9, -0.1),
		upright = true,
	}
end

TEMPLATES.frog = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 0.7, 0)
	local bs = Vector3.new(1.6, 1.0, 1.6)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, 1.3, 0.7, 1.2, at(0, 0.55, -0.25), ctx.c2)
	local ec, em = eyeColor(ctx)
	for _, side in SIDES do
		ball(ctx, 0.55, at(side * 0.42, 1.22, -0.42), ctx.c1)
		ball(ctx, 0.32, at(side * 0.44, 1.28, -0.62), ec, em)
		if not ctx.has.eyes_glow then
			ball(ctx, 0.11, at(side * 0.47, 1.36, -0.76), WHITE)
		end
		ell(ctx, 0.55, 0.4, 0.95, at(side * 0.75, 0.3, 0.35), ctx.c1)
		ell(ctx, 0.6, 0.12, 0.6, at(side * 0.85, 0.06, 0.0), ctx.c3)
		vcyl(ctx, 0.5, 0.25, at(side * 0.5, 0.3, -0.55), ctx.c1)
		ball(ctx, 0.25, at(side * 0.55, 0.62, -0.7), PINK)
	end
	blk(ctx, 0.9, 0.05, 0.05, at(0, 0.66, -0.8), BLACK)
	return {
		head = at(0, 0.95, -0.4),
		headSize = Vector3.new(1.2, 0.8, 0.8),
		body = bodyCF,
		bodySize = bs,
		tail = at(0, 0.7, 0.8),
		top = 1.5,
		skipEyes = true,
	}
end

TEMPLATES.turtle = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 0.95, 0)
	local bs = Vector3.new(1.8, 1.1, 2.0)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c2)
	vcyl(ctx, 0.2, 1.95, at(0, 0.55, 0), ctx.c3)
	if not ctx.has.icing then
		for _, p in { { 0, 0 }, { 0.45, 0.4 }, { -0.45, 0.4 }, { 0.45, -0.4 }, { -0.45, -0.4 } } do
			local y = math.sqrt(math.max(0.05, 1 - (p[1] / 0.9) ^ 2 - (p[2] / 1.0) ^ 2)) * 0.55
			ball(ctx, 0.5, at(p[1], 0.95 + y * 0.92, p[2]), ctx.c3)
		end
	end
	local head = at(0, 0.85, -1.2)
	local hs = Vector3.new(0.75, 0.7, 0.8)
	ell(ctx, 0.5, 0.45, 0.6, at(0, 0.7, -0.85), ctx.c1)
	ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	for _, x in SIDES do
		for _, z in SIDES do
			ell(ctx, 0.5, 0.35, 0.55, at(x * 0.72, 0.25, z * 0.62), ctx.c1)
		end
	end
	ell(ctx, 0.2, 0.2, 0.4, at(0, 0.5, 1.05), ctx.c1)
	return { head = head, headSize = hs, body = bodyCF, bodySize = bs, tail = at(0, 0.5, 1.1), top = 1.5 }
end

TEMPLATES.whale = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 1.5, 0)
	local bs = Vector3.new(1.8, 1.6, 3.0)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, 1.5, 1.0, 2.6, at(0, 1.15, -0.1), ctx.c2)
	ell(ctx, 0.6, 0.6, 1.0, at(0, 1.6, 1.65, -15, 0, 0), ctx.c1)
	ell(ctx, 1.7, 0.12, 0.6, at(0, 1.85, 2.15), ctx.c1)
	local ec, em = eyeColor(ctx)
	for _, side in SIDES do
		ell(ctx, 0.75, 0.1, 0.42, at(side * 0.95, 1.15, -0.4, 0, 0, side * 25), ctx.c1)
		ball(ctx, 0.22, at(side * 0.78, 1.55, -0.9), ec, em)
	end
	blk(ctx, 1.0, 0.05, 0.05, at(0, 1.25, -1.47), DARK)
	return {
		head = at(0, 1.65, -1.05),
		headSize = Vector3.new(1.6, 1.4, 0.9),
		body = bodyCF,
		bodySize = bs,
		tail = at(0, 1.6, 1.4),
		top = 2.3,
		skipEyes = true,
	}
end

TEMPLATES.jelly = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 2.2, 0)
	local bs = Vector3.new(1.7, 1.2, 1.7)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1, nil, 0.15)
	ell(ctx, 1.0, 0.6, 1.0, at(0, 2.1, 0), ctx.c2, ctx.accentMat)
	vcyl(ctx, 0.15, 1.6, at(0, 1.65, 0), ctx.c2, nil, 0.2)
	if ctx.has.tentacles_thick then
		for i = 1, 8 do
			local t = i / 8 * math.pi * 2
			local cf = at(math.cos(t) * 0.6, 1.0, math.sin(t) * 0.6)
				* CFrame.Angles(0, -t, 0)
				* CFrame.Angles(0, 0, rad(-15))
			ell(ctx, 0.35, 1.7, 0.35, cf, ctx.c1)
			ball(ctx, 0.16, cf * CFrame.new(0.15, -0.3, 0), ctx.c3)
		end
	else
		for i = 1, 7 do
			local t = i / 7 * math.pi * 2
			vcyl(ctx, 1.5, 0.12, at(math.cos(t) * 0.5, 0.95, math.sin(t) * 0.5), ctx.c3, nil, 0.25)
		end
	end
	return {
		head = bodyCF,
		headSize = bs,
		body = bodyCF,
		bodySize = bs,
		tail = at(0, 1, 0.6),
		top = 2.8,
		upright = true,
	}
end

TEMPLATES.lizard = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 0.65, 0)
	local bs = Vector3.new(1.0, 0.6, 2.0)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, 0.6, 0.35, 1.7, at(0, 0.83, 0), ctx.c2)
	local head = at(0, 0.78, -1.3)
	local hs = Vector3.new(0.85, 0.5, 0.95)
	ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	for _, side in SIDES do
		for _, z in { -0.6, 0.55 } do
			ell(ctx, 0.75, 0.18, 0.25, at(side * 0.6, 0.3, z, 0, 0, -side * 20), ctx.c1)
		end
	end
	ell(ctx, 0.45, 0.32, 1.1, at(0, 0.5, 1.4), ctx.c1)
	ell(ctx, 0.25, 0.2, 0.9, at(0, 0.4, 2.2), ctx.c1)
	return { head = head, headSize = hs, body = bodyCF, bodySize = bs, tail = at(0, 0.45, 2.5), top = 1.05 }
end

TEMPLATES.blob = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 1.0, 0)
	local bs = Vector3.new(1.6, 1.8, 1.6)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	for _, side in SIDES do
		ball(ctx, 0.3, at(side * 0.5, 0.95, -0.66), PINK)
		ell(ctx, 0.55, 0.25, 0.65, at(side * 0.4, 0.1, -0.2), ctx.c3)
		ell(ctx, 0.35, 0.6, 0.35, at(side * 0.82, 0.9, 0, 0, 0, side * 35), ctx.c1)
	end
	blk(ctx, 0.4, 0.05, 0.05, at(0, 0.85, -0.8), BLACK)
	return {
		head = at(0, 1.3, 0),
		headSize = Vector3.new(1.5, 1.1, 1.5),
		body = bodyCF,
		bodySize = bs,
		tail = at(0, 0.8, 0.8),
		top = 1.9,
		upright = true,
	}
end

TEMPLATES.dino = function(ctx: Ctx): Anchors
	for _, side in SIDES do
		ell(ctx, 0.6, 1.1, 0.85, at(side * 0.45, 1.05, 0.25), ctx.c1)
		ell(ctx, 0.55, 0.25, 0.9, at(side * 0.45, 0.12, 0.0), ctx.c1)
		ell(ctx, 0.2, 0.2, 0.55, at(side * 0.45, 1.95, -0.75, 30, 0, 0), ctx.c1)
	end
	local bodyCF = at(0, 1.95, 0.25)
	local bs = Vector3.new(1.45, 1.45, 2.0)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, 1.0, 1.0, 1.6, at(0, 1.75, 0), ctx.c2)
	ell(ctx, 0.75, 0.65, 2.2, at(0, 1.65, 1.8, -8, 0, 0), ctx.c1)
	ell(ctx, 0.4, 0.35, 1.2, at(0, 1.4, 2.9), ctx.c1)
	local head = at(0, 2.95, -0.95)
	local hs = Vector3.new(1.05, 0.9, 1.5)
	ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	ell(ctx, 0.9, 0.35, 1.25, head * CFrame.new(0, -0.38, -0.1), ctx.c2)
	return { head = head, headSize = hs, body = bodyCF, bodySize = bs, tail = at(0, 1.4, 3.2), top = 3.4 }
end

TEMPLATES.penguin = function(ctx: Ctx): Anchors
	local bodyCF = at(0, 1.0, 0)
	local bs = Vector3.new(1.2, 1.7, 1.1)
	ctx.body = ell(ctx, bs.X, bs.Y, bs.Z, bodyCF, ctx.c1)
	ell(ctx, 0.9, 1.3, 0.6, at(0, 0.9, -0.32), ctx.c2)
	local head = at(0, 2.05, 0)
	local hs = Vector3.new(0.95, 0.9, 0.9)
	ell(ctx, hs.X, hs.Y, hs.Z, head, ctx.c1)
	ell(ctx, 0.7, 0.55, 0.4, head * CFrame.new(0, -0.05, -0.3), ctx.c2)
	ell(ctx, 0.3, 0.15, 0.4, head * CFrame.new(0, -0.14, -0.52), ctx.c3)
	for _, side in SIDES do
		ell(ctx, 0.18, 0.9, 0.45, at(side * 0.62, 1.05, 0, 0, 0, side * 15), ctx.c1)
		ell(ctx, 0.4, 0.12, 0.5, at(side * 0.25, 0.05, -0.2), ctx.c3)
	end
	return {
		head = head,
		headSize = hs,
		body = bodyCF,
		bodySize = bs,
		tail = at(0, 0.5, 0.55),
		top = 2.5,
		upright = true,
	}
end

------------------------------------------------------------------
-- 장식 (features)
------------------------------------------------------------------

local F: { [string]: (Ctx, Anchors) -> () } = {}

local function noop(_ctx: Ctx, _a: Anchors) end

-- 몸통 표면 위의 점 (fx, fz 는 -1~1 비율)
local function onBody(a: Anchors, fx: number, fz: number, lift: number?): CFrame
	local bs = a.bodySize
	local y = math.sqrt(math.max(0.05, 1 - fx * fx - fz * fz)) * bs.Y / 2 * (lift or 0.95)
	return a.body * CFrame.new(fx * bs.X / 2, y, fz * bs.Z / 2)
end

-- 몸통을 두르는 띠 (가로 몸: Z 방향으로 자름, 선 몸: Y 방향으로 자름)
local function bands(ctx: Ctx, a: Anchors, positions: { number }, color: Color3, thickness: number)
	local bs = a.bodySize
	for _, f in positions do
		local k = math.sqrt(math.max(0.05, 1 - f * f)) * 1.04
		if a.upright then
			ell(ctx, bs.X * k, thickness, bs.Z * k, a.body * CFrame.new(0, f * bs.Y / 2, 0), color)
		else
			ell(ctx, bs.X * k, bs.Y * k, thickness, a.body * CFrame.new(0, 0, f * bs.Z / 2), color)
		end
	end
end

F.long_neck = noop
F.torso = noop
F.sneakers = noop
F.tentacles_thick = noop
F.eyes_glow = noop -- eyesAt / 템플릿이 ctx.has.eyes_glow 를 보고 처리

F.crest = function(ctx, a)
	for i = -1, 1 do
		ell(
			ctx,
			0.12,
			0.6,
			0.3,
			hf(a, i * 0.12, 0.45, 0.15) * CFrame.Angles(rad(35), 0, rad(i * 15)) * CFrame.new(0, 0.25, 0),
			if i == 0 then ctx.c3 else ctx.c2,
			ctx.accentMat
		)
	end
end

F.comb = function(ctx, a)
	for i = -1, 1 do
		ball(ctx, a.headSize.X * 0.26, hf(a, 0, 0.5, i * 0.17), RED)
	end
end

F.ears_floppy = function(ctx, a)
	for _, side in SIDES do
		ell(ctx, 0.22, 0.65, 0.4, hf(a, side * 0.5, 0.05, 0.05) * CFrame.Angles(0, 0, rad(side * 18)), ctx.c3)
	end
end

F.ears_pointy = function(ctx, a)
	for _, side in SIDES do
		local base = hf(a, side * 0.3, 0.42, 0.05) * CFrame.Angles(0, 0, rad(-side * 15))
		ell(ctx, 0.3, 0.6, 0.14, base * CFrame.new(0, 0.15, 0), ctx.c1)
		ell(ctx, 0.16, 0.38, 0.06, base * CFrame.new(0, 0.12, -0.06), PINK)
	end
end
F.cat_ears = F.ears_pointy

F.ears_round = function(ctx, a)
	for _, side in SIDES do
		ball(ctx, a.headSize.X * 0.36, hf(a, side * 0.36, 0.4, 0.05), ctx.c1)
		ball(ctx, a.headSize.X * 0.2, hf(a, side * 0.36, 0.4, -0.12), ctx.c2)
	end
end

F.ears_long = function(ctx, a)
	for _, side in SIDES do
		local base = hf(a, side * 0.2, 0.45, 0.1) * CFrame.Angles(0, 0, rad(-side * 10))
		ell(ctx, 0.26, 1.1, 0.14, base * CFrame.new(0, 0.45, 0), ctx.c1)
		ell(ctx, 0.14, 0.8, 0.06, base * CFrame.new(0, 0.45, -0.07), PINK)
	end
end

F.ears_big = function(ctx, a)
	for _, side in SIDES do
		local base = hf(a, side * 0.4, 0.4, 0.05) * CFrame.Angles(0, 0, rad(-side * 30))
		ell(ctx, 0.55, 0.85, 0.14, base * CFrame.new(0, 0.3, 0), ctx.c1)
		ell(ctx, 0.35, 0.6, 0.06, base * CFrame.new(0, 0.3, -0.07), ctx.c3)
	end
end

F.owl_eyes = function(ctx, a)
	a.skipEyes = true
	local hx = a.headSize.X
	for _, side in SIDES do
		local p = hf(a, side * 0.22, 0.08, -0.42)
		ball(ctx, hx * 0.38, p, WHITE)
		ball(ctx, hx * 0.28, p * CFrame.new(0, 0, -0.08), ctx.c3)
		ball(ctx, hx * 0.17, p * CFrame.new(0, 0, -0.16), BLACK)
	end
end

F.mask = function(ctx, a)
	local hs = a.headSize
	ell(ctx, hs.X * 1.03, hs.Y * 0.32, hs.Z * 0.75, hf(a, 0, 0.1, -0.15), Color3.fromRGB(70, 70, 80))
end

F.stripes = function(ctx, a)
	if a.kind == "snake" then
		return
	end
	bands(ctx, a, { -0.5, -0.1, 0.3, 0.65 }, ctx.c3, 0.16)
end

F.bandages = function(ctx, a)
	bands(ctx, a, { -0.7, -0.35, 0, 0.35, 0.7 }, ctx.c2, 0.09)
end

F.tail_fluffy = function(ctx, a)
	local base = a.tail * CFrame.Angles(rad(-45), 0, 0)
	ell(ctx, 0.6, 0.6, 1.4, base * CFrame.new(0, 0, 0.6), ctx.c1)
	ball(ctx, 0.55, base * CFrame.new(0, 0, 1.25), ctx.c2)
end

F.nine_tails = function(ctx, a)
	for i = -2, 2 do
		local base = a.tail * CFrame.Angles(0, rad(i * 22), 0) * CFrame.Angles(rad(-50 + math.abs(i) * 8), 0, 0)
		ell(ctx, 0.42, 0.42, 1.4, base * CFrame.new(0, 0, 0.65), ctx.c1)
		ball(ctx, 0.42, base * CFrame.new(0, 0, 1.3), ctx.c3, ctx.accentMat)
	end
end

F.leaves = function(ctx, a)
	for i = 1, 5 do
		local t = i / 5 * math.pi * 2
		ball(ctx, 0.7, hf(a, math.cos(t) * 0.32, 0.5, math.sin(t) * 0.32), ctx.c3:Lerp(WHITE, i * 0.04))
	end
	ball(ctx, 0.85, hf(a, 0, 0.75, 0), ctx.c3)
end

F.whiskers = function(ctx, a)
	for _, side in SIDES do
		for _, k in SIDES do
			blk(
				ctx,
				0.7,
				0.03,
				0.03,
				hf(a, side * 0.45, -0.15 + k * 0.07, -0.45) * CFrame.Angles(0, 0, rad(side * k * 12)),
				DARK
			)
		end
	end
end

F.legs_short = function(ctx, a)
	local bs = a.bodySize
	local sneakers = ctx.has.sneakers == true
	for _, side in SIDES do
		vcyl(ctx, 0.9, 0.28, a.body * CFrame.new(side * 0.25, -bs.Y / 2 - 0.3, 0.1), ctx.c1)
		local foot = a.body * CFrame.new(side * 0.25, -bs.Y / 2 - 0.72, -0.05)
		ell(ctx, 0.42, 0.26, 0.65, foot, if sneakers then BLUE else ctx.c1)
		if sneakers then
			blk(ctx, 0.42, 0.06, 0.62, foot * CFrame.new(0, -0.1, 0), WHITE)
		end
	end
end

F.gills = function(ctx, a)
	for _, side in SIDES do
		for k = -1, 1 do
			ell(
				ctx,
				0.08,
				0.5,
				0.18,
				hf(a, side * 0.5, 0.15, 0.2) * CFrame.Angles(0, 0, rad(-side * (40 + k * 30))) * CFrame.new(0, 0.25, 0),
				ctx.c3
			)
		end
	end
end

F.fins = function(ctx, a)
	for _, side in SIDES do
		ell(
			ctx,
			0.1,
			0.7,
			0.55,
			hf(a, side * 0.5, 0.1, 0.2) * CFrame.Angles(0, 0, rad(-side * 50)) * CFrame.new(0, 0.3, 0),
			ctx.c3,
			ctx.accentMat
		)
	end
end

F.spikes = function(ctx, a)
	local segs = a.segments
	if segs then
		for i, seg in segs do
			if i < #segs then
				ell(ctx, 0.12, 0.45, 0.25, seg * CFrame.new(0, 0.38 - i * 0.03, 0), ctx.c3, ctx.accentMat)
			end
		end
		return
	end
	local bs = a.bodySize
	for i = 0, 3 do
		ell(
			ctx,
			0.16,
			0.55,
			0.35,
			a.body * CFrame.new(0, bs.Y * 0.45, (i - 1.5) * bs.Z * 0.22) * CFrame.Angles(rad(15), 0, 0),
			ctx.c3,
			ctx.accentMat
		)
	end
end

F.hump = function(ctx, a)
	ell(ctx, 0.9, 0.8, 0.95, a.body * CFrame.new(0, a.bodySize.Y * 0.45, 0.15), ctx.c1)
end

F.hat = function(ctx, a)
	local hx = a.headSize.X
	local top = hf(a, 0, 0.45, 0)
	vcyl(ctx, 0.08, hx * 1.3, top, ctx.c3)
	vcyl(ctx, 0.5, hx * 0.72, top * CFrame.new(0, 0.28, 0), ctx.c3)
	vcyl(ctx, 0.12, hx * 0.74, top * CFrame.new(0, 0.1, 0), ctx.c2)
end

F.claws = function(ctx, a)
	local bs = a.bodySize
	for _, side in SIDES do
		local arm = a.body * CFrame.new(side * bs.X * 0.4, 0, -bs.Z * 0.45) * CFrame.Angles(0, rad(side * 25), 0)
		ell(ctx, 0.25, 0.25, 0.9, arm * CFrame.new(0, 0, -0.4), ctx.c1)
		local claw = arm * CFrame.new(0, 0.05, -1.0)
		ell(ctx, 0.5, 0.32, 0.6, claw, ctx.c3)
		ell(ctx, 0.18, 0.18, 0.5, claw * CFrame.new(side * 0.15, 0, -0.4), ctx.c3)
	end
end

F.stinger = function(ctx, a)
	local R = 0.8
	local center = a.tail * CFrame.new(0, R * 0.9, -0.1)
	local sizes = { 0.45, 0.42, 0.38, 0.34, 0.3 }
	for i, deg in { 30, 70, 110, 150, 190 } do
		local t = rad(deg)
		ball(ctx, sizes[i], center * CFrame.new(0, -R * math.cos(t), R * math.sin(t)), ctx.c1)
	end
	local tipT = rad(228)
	ell(
		ctx,
		0.2,
		0.2,
		0.55,
		center * CFrame.new(0, -R * math.cos(tipT), R * math.sin(tipT)) * CFrame.Angles(rad(-30), 0, 0),
		ctx.c3,
		ctx.accentMat
	)
end

F.pharaoh = function(ctx, a)
	local hs = a.headSize
	ell(ctx, hs.X * 1.18, hs.Y * 0.62, hs.Z * 1.05, hf(a, 0, 0.25, 0.1), ctx.c2)
	for _, side in SIDES do
		ell(ctx, 0.28, 0.95, 0.55, hf(a, side * 0.52, -0.3, 0.15), ctx.c2)
		vcyl(ctx, 0.1, 0.3, hf(a, side * 0.52, -0.1, 0.15), ctx.c1)
	end
	vcyl(ctx, 0.12, hs.X * 1.2, hf(a, 0, 0.12, 0.05), ctx.c1, FOIL)
	ball(ctx, 0.2, hf(a, 0, 0.5, -0.45), ctx.c1, FOIL)
end

F.beak_big = function(ctx, a)
	local hs = a.headSize
	ell(ctx, hs.X * 0.5, hs.Y * 0.55, 1.15, hf(a, 0, -0.1, -0.5) * CFrame.new(0, 0, -0.5), ctx.c3)
	ball(ctx, hs.X * 0.22, hf(a, 0, -0.05, -0.5) * CFrame.new(0, 0, -1.05), BLACK)
end

F.teeth = function(ctx, a)
	for i = -2, 2 do
		blk(ctx, 0.08, 0.16, 0.08, hf(a, i * 0.1, -0.32, -0.47), WHITE)
	end
end

F.brow = function(ctx, a)
	local hs = a.headSize
	ell(ctx, hs.X * 0.92, hs.Y * 0.22, hs.Z * 0.45, hf(a, 0, 0.3, -0.28), ctx.c3)
end

F.pineapple = function(ctx, a)
	local top = hf(a, 0, 0.5, 0)
	ell(ctx, 0.75, 0.95, 0.75, top * CFrame.new(0, 0.4, 0), YELLOW)
	for i = 1, 5 do
		ell(
			ctx,
			0.12,
			0.65,
			0.28,
			top * CFrame.new(0, 0.9, 0) * CFrame.Angles(0, i * 1.25, rad(20)) * CFrame.new(0, 0.3, 0),
			GREEN
		)
	end
end

F.crown = function(ctx, a)
	local hx = a.headSize.X
	local top = hf(a, 0, 0.48, 0)
	vcyl(ctx, 0.35, hx * 0.62, top * CFrame.new(0, 0.15, 0), GOLD, FOIL)
	for i = 1, 5 do
		local t = i / 5 * math.pi * 2
		ball(ctx, 0.16, top * CFrame.new(math.cos(t) * hx * 0.29, 0.38, math.sin(t) * hx * 0.29), GOLD, FOIL)
	end
	ball(ctx, 0.14, top * CFrame.new(0, 0.17, -hx * 0.31), RED, NEON)
end

F.tusks = function(ctx, a)
	for _, side in SIDES do
		ell(
			ctx,
			0.14,
			0.14,
			0.95,
			hf(a, side * 0.3, -0.38, -0.4) * CFrame.Angles(rad(30), 0, 0) * CFrame.new(0, 0, -0.35),
			BONE
		)
	end
end

F.fangs = function(ctx, a)
	for _, side in SIDES do
		ell(ctx, 0.1, 0.32, 0.1, hf(a, side * 0.14, -0.4, -0.42), WHITE)
	end
end

F.trunk = function(ctx, a)
	ell(ctx, 0.32, 1.15, 0.32, hf(a, 0, -0.45, -0.55) * CFrame.Angles(rad(15), 0, 0) * CFrame.new(0, -0.25, 0), ctx.c1)
end

F.horns = function(ctx, a)
	for _, side in SIDES do
		ell(
			ctx,
			0.17,
			0.62,
			0.17,
			hf(a, side * 0.3, 0.42, 0) * CFrame.Angles(0, 0, rad(-side * 25)) * CFrame.new(0, 0.22, 0),
			ctx.c3,
			ctx.accentMat
		)
	end
end

F.horn = function(ctx, a)
	ell(
		ctx,
		0.18,
		0.85,
		0.18,
		hf(a, 0, 0.42, -0.25) * CFrame.Angles(rad(-30), 0, 0) * CFrame.new(0, 0.32, 0),
		ctx.c3,
		ctx.accentMat
	)
end

F.antlers = function(ctx, a)
	for _, side in SIDES do
		local base = hf(a, side * 0.25, 0.45, 0) * CFrame.Angles(0, 0, rad(-side * 28))
		ell(ctx, 0.12, 1.0, 0.12, base * CFrame.new(0, 0.45, 0), ctx.c3, ctx.accentMat)
		for k = 1, 2 do
			ell(
				ctx,
				0.1,
				0.5,
				0.1,
				base
					* CFrame.new(0, 0.3 + k * 0.25, 0)
					* CFrame.Angles(rad(-20), 0, rad(-side * 45))
					* CFrame.new(0, 0.22, 0),
				ctx.c3,
				ctx.accentMat
			)
		end
	end
end

F.crystals = function(ctx, a)
	local bs = a.bodySize
	for _, spec in { { -0.25, 0.1, -10, 15 }, { 0.25, -0.15, 10, -20 }, { 0, 0.3, 20, 0 }, { 0, -0.35, -20, 5 } } do
		ell(
			ctx,
			0.25,
			0.75,
			0.25,
			a.body
				* CFrame.new(spec[1] * bs.X, bs.Y * 0.42, spec[2] * bs.Z)
				* CFrame.Angles(rad(spec[3]), 0, rad(spec[4]))
				* CFrame.new(0, 0.25, 0),
			ctx.c3,
			NEON,
			0.1
		)
	end
end

local SPOTS = { { 0.3, 0.3 }, { -0.35, -0.1 }, { 0.15, -0.45 }, { -0.2, 0.45 }, { 0.45, -0.05 }, { -0.05, 0.05 } }

local function spots(ctx: Ctx, a: Anchors, mat: Enum.Material)
	local d = math.min(a.bodySize.X, a.bodySize.Z) * 0.22
	for _, p in SPOTS do
		ball(ctx, d, onBody(a, p[1], p[2], 0.93), ctx.c3, mat)
	end
end

F.spots = function(ctx, a)
	spots(ctx, a, ctx.accentMat)
end

F.lava_spots = function(ctx, a)
	spots(ctx, a, NEON)
end

F.flame = function(ctx, _a)
	local body = ctx.body
	if not body then
		return
	end
	local fire = Instance.new("Fire")
	fire.Size = math.clamp(2.5 * ctx.s, 2, 30)
	fire.Heat = 6
	fire.Color = ctx.c3
	fire.SecondaryColor = YELLOW
	fire.Parent = body
	local light = Instance.new("PointLight")
	light.Color = ctx.c3
	light.Range = 8 * ctx.s
	light.Brightness = 1.2
	light.Parent = body
end

F.stem = function(ctx, a)
	local top = at(0, a.top, 0)
	vcyl(ctx, 0.5, 0.22, top * CFrame.new(0, 0.2, 0), ctx.c3)
	ell(ctx, 0.5, 0.1, 0.3, top * CFrame.new(0.25, 0.3, 0) * CFrame.Angles(0, 0, rad(-20)), ctx.c3)
end

F.sunglasses = function(ctx, a)
	a.skipEyes = true
	local hs = a.headSize
	local p = hf(a, 0, 0.12, -0.46)
	for _, side in SIDES do
		blk(ctx, hs.X * 0.32, hs.Y * 0.2, 0.08, p * CFrame.new(side * hs.X * 0.2, 0, 0), BLACK)
	end
	blk(ctx, hs.X * 0.15, 0.05, 0.06, p, BLACK)
	blk(ctx, hs.X * 0.08, hs.Y * 0.05, 0.02, p * CFrame.new(-hs.X * 0.27, hs.Y * 0.05, -0.05), WHITE)
end

F.three_heads = function(ctx, a)
	local hs = a.headSize
	for _, side in SIDES do
		local h2 = a.head * CFrame.new(side * hs.X * 0.85, -hs.Y * 0.12, hs.Z * 0.25)
		local s2 = hs * 0.85
		ell(ctx, s2.X, s2.Y, s2.Z, h2, ctx.c1)
		ell(ctx, s2.X * 0.55, s2.Y * 0.45, s2.Z * 0.5, h2 * CFrame.new(0, -s2.Y * 0.2, -s2.Z * 0.42), ctx.c2)
		eyesAt(ctx, h2, s2)
	end
end

F.sword_nose = function(ctx, a)
	ell(ctx, 0.12, 0.12, 1.5, hf(a, 0, 0, -0.5) * CFrame.new(0, 0, -0.7), ctx.c3)
end

F.fin_big = function(ctx, a)
	local bs = a.bodySize
	ell(
		ctx,
		0.14,
		1.15,
		1.0,
		a.body * CFrame.new(0, bs.Y * 0.5 + 0.25, 0.1) * CFrame.Angles(rad(25), 0, 0),
		ctx.c1:Lerp(BLACK, 0.1)
	)
end

F.bat_wings = function(ctx, a)
	local bs = a.bodySize
	for _, side in SIDES do
		local root = a.body
			* CFrame.new(side * bs.X * 0.4, bs.Y * 0.25, if a.upright then bs.Z * 0.3 else 0)
			* CFrame.Angles(0, 0, rad(side * 20))
		blk(ctx, 1.7, 0.07, 1.0, root * CFrame.new(side * 0.85, 0, 0), ctx.c2, nil, 0.05)
		add(ctx, "Cyl", Vector3.new(1.8, 0.12, 0.12), root * CFrame.new(side * 0.9, 0.02, -0.5), ctx.c1)
		ell(ctx, 0.55, 0.07, 0.6, root * CFrame.new(side * 1.5, 0, 0.45), ctx.c2)
	end
end

F.club = function(ctx, a)
	ell(ctx, 0.3, 0.3, 1.0, a.tail * CFrame.new(0, -0.1, 0.45), ctx.c1)
	ball(ctx, 0.7, a.tail * CFrame.new(0, -0.15, 1.0), ctx.c3)
end

F.frill = function(ctx, a)
	local hs = a.headSize
	disc(ctx, 0.12, hs.X * 2, hf(a, 0, 0.35, 0.45) * CFrame.Angles(rad(-20), 0, 0), ctx.c2)
	for _, side in SIDES do
		ell(
			ctx,
			0.14,
			0.14,
			0.9,
			hf(a, side * 0.28, 0.35, -0.3) * CFrame.Angles(rad(25), 0, 0) * CFrame.new(0, 0, -0.35),
			ctx.c3
		)
	end
	ell(ctx, 0.14, 0.14, 0.45, hf(a, 0, -0.05, -0.55) * CFrame.Angles(rad(40), 0, 0) * CFrame.new(0, 0, -0.2), ctx.c3)
end

F.legs_many = function(ctx, a)
	local segs = a.segments
	if not segs then
		return
	end
	for i, seg in segs do
		if i > 1 then
			for _, side in SIDES do
				blk(
					ctx,
					0.7,
					0.08,
					0.08,
					seg * CFrame.new(side * 0.4, -0.15, 0) * CFrame.Angles(0, 0, rad(-side * 35)),
					ctx.c3
				)
			end
		end
	end
end

F.stars = function(ctx, a)
	for i = 1, 6 do
		local t = i / 6 * math.pi * 2
		ball(
			ctx,
			0.22,
			at(math.cos(t) * 1.3, a.top * 0.6 + math.sin(t * 2) * 0.3, math.sin(t) * 1.3),
			if i % 2 == 0 then YELLOW else WHITE,
			NEON
		)
	end
end

F.planet_ring = function(ctx, a)
	local d = math.max(a.bodySize.X, a.bodySize.Z) * 1.5
	vcyl(ctx, 0.06, d, a.body * CFrame.Angles(rad(12), 0, 0), ctx.c3, NEON, 0.35)
end

F.skull = function(ctx, a)
	a.skipEyes = true
	local hx = a.headSize.X
	for _, side in SIDES do
		local p = hf(a, side * 0.24, 0.08, -0.38)
		ball(ctx, hx * 0.32, p, BLACK)
		ball(ctx, hx * 0.12, p * CFrame.new(0, 0, -hx * 0.12), ctx.c3, NEON)
	end
	ball(ctx, hx * 0.12, hf(a, 0, -0.18, -0.46), BLACK)
	bands(ctx, a, { -0.35, 0, 0.35 }, DARK, 0.1)
end

F.moon = function(ctx, a)
	local m = ball(ctx, 0.6, at(0.6, a.top + 0.7, 0), Color3.fromRGB(255, 245, 190), NEON)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 220, 255)
	light.Range = 6 * ctx.s
	light.Parent = m
end

F.mane = function(ctx, a)
	local hs = a.headSize
	for i = 0, 6 do
		local t = math.pi * (i / 6)
		ball(
			ctx,
			hs.X * 0.42,
			a.head * CFrame.new(math.cos(t) * hs.X * 0.5, math.sin(t) * hs.Y * 0.5 + 0.05, hs.Z * 0.2),
			ctx.c2,
			ctx.accentMat
		)
	end
	ball(ctx, hs.X * 0.5, a.head * CFrame.new(0, -0.1, hs.Z * 0.55), ctx.c2, ctx.accentMat)
end

F.armor = function(ctx, a)
	local bs = a.bodySize
	ell(ctx, bs.X * 1.06, bs.Y * 0.62, bs.Z * 0.92, a.body * CFrame.new(0, bs.Y * 0.2, 0), SILVER, FOIL)
end

F.blades = function(ctx, a)
	local bs = a.bodySize
	for i = 0, 2 do
		ell(
			ctx,
			0.1,
			0.8,
			0.55,
			a.body
				* CFrame.new(0, bs.Y * 0.48, (i - 1) * bs.Z * 0.3)
				* CFrame.Angles(rad(30), 0, 0)
				* CFrame.new(0, 0.25, 0),
			SILVER,
			FOIL
		)
	end
end

F.scythe_arms = function(ctx, a)
	for _, side in SIDES do
		local base = a.head * CFrame.new(side * 0.35, -0.4, 0.2)
		ell(ctx, 0.15, 0.15, 0.9, base * CFrame.Angles(rad(-35), 0, 0) * CFrame.new(0, 0, -0.4), ctx.c1)
		ell(
			ctx,
			0.08,
			0.55,
			0.18,
			base * CFrame.new(0, 0.3, -0.75) * CFrame.Angles(rad(-20), 0, 0),
			ctx.c3,
			ctx.accentMat
		)
	end
end

F.wings = function(ctx, a)
	local bs = a.bodySize
	local insect = ctx.bodyKind == "bug"
	local color = if insect then ctx.c2 else WHITE
	local tr = if insect then 0.3 else 0
	for _, side in SIDES do
		local root = a.body
			* CFrame.new(side * bs.X * 0.42, bs.Y * 0.35, if a.upright then bs.Z * 0.45 else 0.15)
			* CFrame.Angles(0, 0, rad(-side * 40))
		ell(ctx, 0.14, 1.3, 1.1, root * CFrame.new(0, 0.6, 0), color, nil, tr)
		ell(
			ctx,
			0.12,
			0.9,
			0.8,
			root * CFrame.new(side * 0.1, 0.45, 0.35) * CFrame.Angles(rad(20), 0, 0),
			color:Lerp(ctx.c3, 0.15),
			nil,
			tr
		)
	end
end

F.halo = function(ctx, a)
	local hp = a.head.Position
	local r = a.headSize.X * 0.38
	for i = 1, 10 do
		local t = i / 10 * math.pi * 2
		ball(
			ctx,
			0.14,
			at(hp.X + math.cos(t) * r, a.top + 0.35, hp.Z + math.sin(t) * r),
			Color3.fromRGB(255, 235, 120),
			NEON
		)
	end
end

local WOOL = {
	{ 0, 0.7, 0 },
	{ 0.55, 0.4, 0.4 },
	{ -0.55, 0.4, 0.4 },
	{ 0.55, 0.4, -0.4 },
	{ -0.55, 0.4, -0.4 },
	{ 0, 0.6, 0.7 },
	{ 0, 0.6, -0.7 },
	{ 0, 0.2, 0.85 },
}

F.wool = function(ctx, a)
	local bs = a.bodySize
	local d = math.min(bs.X, bs.Y) * 0.55
	for i, p in WOOL do
		ball(
			ctx,
			d,
			a.body * CFrame.new(p[1] * bs.X / 2, p[2] * bs.Y / 2, p[3] * bs.Z / 2),
			if i % 2 == 0 then ctx.c2 else ctx.c1
		)
	end
end

F.peacock_tail = function(ctx, a)
	for i = -3, 3 do
		local base = a.tail * CFrame.Angles(0, 0, rad(i * 22))
		ell(ctx, 0.4, 1.7, 0.08, base * CFrame.new(0, 0.85, 0.1), ctx.c1)
		ball(ctx, 0.32, base * CFrame.new(0, 1.55, 0.05), ctx.c2, ctx.accentMat)
		ball(ctx, 0.16, base * CFrame.new(0, 1.55, 0), BLUE)
	end
end

F.tail_devil = function(ctx, a)
	local base = a.tail * CFrame.Angles(rad(-20), 0, 0)
	ell(ctx, 0.1, 0.1, 1.3, base * CFrame.new(0, 0, 0.6), ctx.c1)
	ball(ctx, 0.28, base * CFrame.new(0, 0, 1.3), ctx.c3, ctx.accentMat)
end

F.ring = function(ctx, a)
	local bs = a.bodySize
	for i = 1, 12 do
		local t = i / 12 * math.pi * 2
		ball(ctx, 0.16, a.body * CFrame.new(math.cos(t) * bs.X * 0.85, 0, math.sin(t) * bs.Z * 0.85), GOLD, NEON)
	end
end

F.helmet = function(ctx, a)
	a.skipEyes = true
	local hs = a.headSize
	ell(ctx, hs.X * 1.1, hs.Y * 0.75, hs.Z * 1.1, hf(a, 0, 0.15, 0), SILVER, FOIL)
	blk(ctx, hs.X * 0.7, 0.1, 0.06, hf(a, 0, 0.08, -0.55), ctx.c3, NEON)
	ell(ctx, 0.15, 0.5, 0.8, hf(a, 0, 0.6, 0.1), ctx.c3)
end

F.flower = function(ctx, a)
	local center = a.body * CFrame.new(0, a.bodySize.Y * 0.5, 0)
	for i = 1, 5 do
		local t = i / 5 * math.pi * 2
		ball(ctx, 0.35, center * CFrame.new(math.cos(t) * 0.3, 0.05, math.sin(t) * 0.3), ctx.c3)
	end
	ball(ctx, 0.28, center * CFrame.new(0, 0.1, 0), YELLOW)
end

F.lollipop = function(ctx, a)
	local hand = a.hand
	local base = hand or at(a.bodySize.X / 2 + 0.35, 0, -0.2)
	local len = if hand then 1.5 else 2.2
	local drop = if hand then 0.3 else 0
	vcyl(ctx, len, 0.1, base * CFrame.new(0, len / 2 - drop, 0), WHITE)
	local face = base * CFrame.new(0, len - drop + 0.4, 0)
	disc(ctx, 0.15, 0.95, face, ctx.c3)
	disc(ctx, 0.17, 0.6, face, WHITE)
	disc(ctx, 0.19, 0.3, face, ctx.c3)
end

F.icing = function(ctx, a)
	local bs = a.bodySize
	ell(ctx, bs.X * 0.96, bs.Y * 0.5, bs.Z * 0.96, a.body * CFrame.new(0, bs.Y * 0.24, 0), ctx.c2)
end

F.sprinkles = function(ctx, a)
	local colors = { RED, YELLOW, BLUE, GREEN, WHITE }
	for i = 1, 10 do
		local fx = ((i * 0.37) % 1) * 1.2 - 0.6
		local fz = ((i * 0.61) % 1) * 1.2 - 0.6
		blk(ctx, 0.07, 0.07, 0.22, onBody(a, fx, fz, 1.0) * CFrame.Angles(0, i * 1.3, 0), colors[(i % 5) + 1])
	end
end

F.buttons = function(ctx, a)
	local bs = a.bodySize
	for k = -1, 1 do
		ball(ctx, 0.2, a.body * CFrame.new(0, k * bs.Y * 0.22, -bs.Z * 0.47), ctx.c3)
	end
end

F.pumpkin = function(ctx, a)
	local bs = a.bodySize
	for _, side in SIDES do
		ell(
			ctx,
			bs.X * 0.55,
			bs.Y * 0.98,
			bs.Z * 1.02,
			a.body * CFrame.new(side * bs.X * 0.22, 0, 0),
			ctx.c1:Lerp(BLACK, 0.12)
		)
	end
	vcyl(ctx, 0.35, 0.18, a.body * CFrame.new(0, bs.Y * 0.55, 0), ctx.c2)
	for _, side in SIDES do
		blk(ctx, 0.2, 0.2, 0.05, a.body * CFrame.new(side * 0.22, 0.15, bs.Z * 0.5), YELLOW, NEON)
	end
	blk(ctx, 0.5, 0.1, 0.05, a.body * CFrame.new(0, -0.15, bs.Z * 0.5), YELLOW, NEON)
end

F.stitches = function(ctx, a)
	for _, p in { { 0.35, 0.2 }, { -0.3, -0.25 }, { 0.05, 0.45 } } do
		local cf = onBody(a, p[1], p[2], 1.0)
		blk(ctx, 0.5, 0.05, 0.05, cf, BLACK)
		for k = -1, 1 do
			blk(ctx, 0.05, 0.05, 0.2, cf * CFrame.new(k * 0.15, 0, 0), BLACK)
		end
	end
end

F.sword = function(ctx, a)
	local base = a.hand or at(a.bodySize.X / 2 + 0.3, 1, -0.3)
	blk(ctx, 0.12, 1.7, 0.3, base * CFrame.new(0, 1.0, -0.1), SILVER, FOIL)
	blk(ctx, 0.6, 0.12, 0.15, base * CFrame.new(0, 0.15, -0.1), GOLD, FOIL)
	blk(ctx, 0.14, 0.4, 0.14, base * CFrame.new(0, -0.1, -0.1), WOOD)
end

F.hood = function(ctx, a)
	a.skipEyes = true
	local hs = a.headSize
	ell(ctx, hs.X * 1.3, hs.Y * 1.25, hs.Z * 1.3, hf(a, 0, 0.12, 0.12), ctx.c2)
	ell(ctx, hs.X * 0.8, hs.Y * 0.75, 0.2, hf(a, 0, 0, -0.55), BLACK)
	for _, side in SIDES do
		ball(ctx, hs.X * 0.12, hf(a, side * 0.18, 0.05, -0.62), ctx.c3, NEON)
	end
end

F.scythe = function(ctx, a)
	local base = a.hand or at(a.bodySize.X / 2 + 0.6, 0, -0.2)
	vcyl(ctx, 3.2, 0.13, base * CFrame.new(0, 1.6, 0), WOOD)
	ell(ctx, 0.08, 0.35, 1.7, base * CFrame.new(0, 3.1, -0.7) * CFrame.Angles(rad(-15), 0, 0), SILVER, FOIL)
end

------------------------------------------------------------------
-- 희귀도 효과
------------------------------------------------------------------

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 180, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 255, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(90, 230, 120)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 110, 255)),
})

local function emitter(parent: BasePart, kind: string, color: Color3?, scale: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Glow"
	e.Texture = SPARKLE_TEX
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 6
	e.Lifetime = NumberRange.new(1, 1.8)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * scale), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(color or WHITE)
	if kind == "smoke" then
		e.Texture = SMOKE_TEX
		e.LightEmission = 0
		e.Rate = 5
		e.Lifetime = NumberRange.new(1.5, 2.5)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8 * scale),
			NumberSequenceKeypoint.new(1, 1.6 * scale),
		})
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		e.Acceleration = Vector3.new(0, 1, 0)
	elseif kind == "rainbow" then
		e.Color = RAINBOW
		e.Rate = 10
	end
	e.Parent = parent
	return e
end

local function applyRarity(ctx: Ctx, rarityId: string)
	local fx = Visuals.rarityEffects[rarityId]
	if not fx then
		return
	end
	local highlight = fx.highlight
	if highlight then
		local h = Instance.new("Highlight")
		h.Name = "RarityGlow"
		h.FillTransparency = 1
		h.OutlineTransparency = 0.05
		h.OutlineColor = rgb(highlight)
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = ctx.model
		h.Parent = ctx.model
		CollectionService:AddTag(h, Visuals.Tags.RarityHighlight)
	end
	local body = ctx.body
	if body then
		local particle = fx.particle
		if particle then
			local pc = fx.particleColor
			emitter(body, particle, if pc then rgb(pc) else nil, ctx.s)
		end
		local lightColor = fx.light
		if lightColor then
			local l = Instance.new("PointLight")
			l.Color = rgb(lightColor)
			l.Range = 8 * ctx.s
			l.Brightness = 1.2
			l.Parent = body
		end
	end
end

------------------------------------------------------------------
-- 모델 만들기 (공개)
------------------------------------------------------------------

function PetVisualService.build(id: string, scale: number, opts: BuildOptions?): Model
	local v = Visuals.pet(id)
	local model = Instance.new("Model")
	model.Name = id
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local has: { [string]: boolean } = {}
	for _, f in v.features do
		has[f] = true
	end
	local ctx: Ctx = {
		model = model,
		root = root,
		s = scale,
		c1 = rgb(v.colors[1]),
		c2 = rgb(v.colors[2] or v.colors[1]),
		c3 = rgb(v.colors[3] or v.colors[1]),
		mat = materialOf(v.material),
		accentMat = if v.glow then NEON else Enum.Material.SmoothPlastic,
		has = has,
		body = nil,
		bodyKind = v.body,
	}
	local template = TEMPLATES[v.body] or TEMPLATES.blob
	local a = template(ctx)
	a.kind = v.body
	for _, f in v.features do
		local fn = F[f]
		if fn then
			fn(ctx, a)
		end
	end
	if not a.skipEyes then
		eyesAt(ctx, a.head, a.headSize)
	end
	if v.ghostly or v.material == "Glass" then
		local minimum = if v.ghostly then 0.35 else 0.2
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				d.Transparency = math.max(d.Transparency, minimum)
			end
		end
	end
	model:SetAttribute("PetId", id)
	model:SetAttribute("Height", a.top * scale)
	if opts and opts.effects then
		local pet = Pets.get(id)
		local rarity = if pet then pet.rarity else opts.rarity
		if rarity then
			applyRarity(ctx, rarity)
		end
	end
	return model
end

local function height(model: Model): number
	local h = model:GetAttribute("Height")
	return if typeof(h) == "number" then h else 3
end

------------------------------------------------------------------
-- 천사&악마 쪽
------------------------------------------------------------------

local function currentSide(): string
	local state = ReplicatedStorage:FindFirstChild(Tags.StateFolderName)
	local side = if state then state:GetAttribute(Tags.StateAttributes.HeavenSide) else nil
	return if typeof(side) == "string" and side ~= "" then side else "light"
end

------------------------------------------------------------------
-- 부모 동물 (둥지 옆, 큰 크기)
------------------------------------------------------------------

local PARENT_SCALE = 2.2
local parentModels: { [BasePart]: Model } = {}

local function nestPets(biomeId: string, side: string?): { Pets.Pet }
	local list: { Pets.Pet } = {}
	for _, p in Pets.inBiome(biomeId) do
		if p.source == "nest" and (p.side == nil or side == nil or p.side == side) then
			table.insert(list, p)
		end
	end
	return list
end

local function buildParent(spot: BasePart)
	local old = parentModels[spot]
	if old then
		old:Destroy()
		parentModels[spot] = nil
	end
	if spot.Parent == nil then
		return
	end
	local biomeId = spot:GetAttribute("BiomeId")
	local nestIndex = spot:GetAttribute("NestIndex")
	if typeof(biomeId) ~= "string" or typeof(nestIndex) ~= "number" then
		return
	end
	local biome = Biomes.get(biomeId)
	local side = if biome and biome.sides then currentSide() else nil
	local list = nestPets(biomeId, side)
	if #list == 0 then
		return
	end
	local pet = list[((nestIndex - 1) % #list) + 1]
	local model = PetVisualService.build(pet.id, PARENT_SCALE, { effects = true })
	local ground = spot.Position - Vector3.new(0, spot.Size.Y / 2, 0)
	model:PivotTo(CFrame.new(ground) * spot.CFrame.Rotation)
	local rarity = Rarities.get(pet.rarity)
	local root = model.PrimaryPart
	if root then
		Gui.tag(root, height(model) + 1.5, 90, {
			{ text = pet.name, color = if rarity then rgb(rarity.color):Lerp(WHITE, 0.25) else WHITE },
			{
				text = if rarity then rarity.name else pet.rarity,
				weight = 0.65,
				color = if rarity then rgb(rarity.color) else WHITE,
			},
		}, 8)
	end
	model:SetAttribute("BiomeId", biomeId)
	CollectionService:AddTag(model, Visuals.Tags.ParentAnimal)
	model.Parent = spot.Parent
	parentModels[spot] = model
end

local function rebuildSidedParents()
	for _, inst in CollectionService:GetTagged(Tags.ParentAnimalSpot) do
		if inst:IsA("BasePart") then
			local biomeId = inst:GetAttribute("BiomeId")
			local biome = if typeof(biomeId) == "string" then Biomes.get(biomeId) else nil
			if biome and biome.sides then
				buildParent(inst)
			end
		end
	end
end

------------------------------------------------------------------
-- 우리 (장착 펫 진열)
------------------------------------------------------------------

local MAX_PEN = 18
local PEN_SCALE = 1.2
local SIZE_SCALE: { [string]: number } = { normal = 1, big = 1.15, huge = 1.3, giant = 1.5 }

type PenState = { signature: string, models: { Model } }
local pens: { [number]: PenState } = {}
local penParts: { [number]: BasePart } = {}

local function penPart(index: number): BasePart?
	local cached = penParts[index]
	if cached and cached.Parent then
		return cached
	end
	for _, inst in CollectionService:GetTagged(Tags.PenArea) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotIndex") == index then
			penParts[index] = inst
			return inst
		end
	end
	return nil
end

local function penRecords(data: Types.PlayerData): { Types.PetRecord }
	local byUid: { [string]: Types.PetRecord } = {}
	for _, r in data.pets do
		byUid[r.uid] = r
	end
	local list: { Types.PetRecord } = {}
	for _, uid in data.equipped do
		local r = byUid[uid]
		if r then
			table.insert(list, r)
			if #list >= MAX_PEN then
				break
			end
		end
	end
	return list
end

local function signatureOf(owner: number, records: { Types.PetRecord }): string
	local parts = { tostring(owner) }
	for _, r in records do
		table.insert(parts, r.uid .. ":" .. r.petId .. ":" .. r.size .. ":" .. table.concat(r.mutations, "+"))
	end
	return table.concat(parts, "|")
end

local function penSpots(pen: BasePart, n: number): { CFrame }
	local result: { CFrame } = {}
	local top = pen.Position.Y + pen.Size.Y / 2
	local outer = math.min(n, 10)
	local inner = n - outer
	local function ring(count: number, rx: number, rz: number, offset: number)
		for i = 1, count do
			local t = (i - 0.5) / count * math.pi * 2 + offset
			local x = pen.Position.X + math.cos(t) * rx
			local z = pen.Position.Z + math.sin(t) * rz
			-- 모두 +Z(베이스 입구 쪽)를 바라봄
			table.insert(result, CFrame.new(x, top, z) * CFrame.Angles(0, math.pi, 0))
		end
	end
	ring(outer, pen.Size.X * 0.38, pen.Size.Z * 0.32, 0)
	if inner > 0 then
		ring(inner, pen.Size.X * 0.18, pen.Size.Z * 0.12, 0.3)
	end
	return result
end

local function mutationText(record: Types.PetRecord): string
	local parts: { string } = {}
	local size = Sizes.get(record.size)
	if size and size.id ~= "normal" then
		table.insert(parts, size.name)
	end
	for _, id in record.mutations do
		local m = Mutations.get(id)
		if m then
			table.insert(parts, m.name)
		end
	end
	return table.concat(parts, " · ")
end

local function buildPenPet(record: Types.PetRecord, spot: CFrame, parent: Instance): Model
	local scale = PEN_SCALE * (SIZE_SCALE[record.size] or 1)
	local model = PetVisualService.build(record.petId, scale, { effects = true })
	model:PivotTo(spot)
	local pet = Pets.get(record.petId)
	local rarity = if pet then Rarities.get(pet.rarity) else nil
	local lines: { Gui.TagLine } = {
		{
			text = if pet then pet.name else record.petId,
			color = if rarity then rgb(rarity.color):Lerp(WHITE, 0.3) else WHITE,
		},
		{ text = Format.money(Economy.recordIncome(record)) .. "/초", color = Color3.fromRGB(120, 255, 120) },
	}
	local extra = mutationText(record)
	if extra ~= "" then
		table.insert(lines, { text = extra, color = Color3.fromRGB(255, 230, 120), weight = 0.75 })
	end
	local root = model.PrimaryPart
	if root then
		Gui.tag(root, height(model) + 1, 60, lines, 5)
		local first = record.mutations[1]
		local look = if first then Visuals.mutationLooks[first] else nil
		if look then
			-- 돌연변이 펫은 그 색으로 반짝임
			local body: BasePart? = nil
			for _, d in model:GetChildren() do
				if d:IsA("BasePart") and d ~= root then
					body = d
					break
				end
			end
			if body then
				local e =
					emitter(body, if look.cycle then "rainbow" else "sparkle", rgb(look.petals or look.color), scale)
				e.Rate = 4
			end
		end
	end
	model:SetAttribute("PetUid", record.uid)
	CollectionService:AddTag(model, Visuals.Tags.PenPet)
	model.Parent = parent
	return model
end

local function refreshPens()
	for _, floor in CollectionService:GetTagged(Tags.Plot) do
		local index = floor:GetAttribute("PlotIndex")
		if typeof(index) == "number" then
			local pen = penPart(index)
			if pen then
				local ownerAttr = floor:GetAttribute("OwnerUserId")
				local owner = if typeof(ownerAttr) == "number" then ownerAttr else 0
				local records: { Types.PetRecord } = {}
				if owner ~= 0 then
					local player = Players:GetPlayerByUserId(owner)
					if player then
						local _, data = Sessions.getLoaded(player)
						if data then
							records = penRecords(data)
						end
					end
				end
				local signature = signatureOf(owner, records)
				local state = pens[index]
				if not state or state.signature ~= signature then
					if state then
						for _, m in state.models do
							m:Destroy()
						end
					end
					local models: { Model } = {}
					local places = penSpots(pen, #records)
					local parent = pen.Parent or pen
					for i, record in records do
						table.insert(models, buildPenPet(record, places[i], parent))
					end
					pens[index] = { signature = signature, models = models }
				end
			end
		end
	end
end

------------------------------------------------------------------
-- 경비 겉모습
------------------------------------------------------------------

local guardVisuals: { [Model]: Model } = {}

local function dressGuard(guard: Model)
	if guard.Parent == nil then
		return
	end
	local biomeId = guard:GetAttribute("BiomeId")
	local spec = if typeof(biomeId) == "string" then Visuals.guards[biomeId] else nil
	if not spec then
		return
	end
	local root = guard:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local modelId = spec.model
	local dark = spec.darkModel
	if dark and currentSide() == "dark" then
		modelId = dark
	end
	local old = guardVisuals[guard]
	if old and old.Parent then
		if old.Name == modelId then
			return
		end
		old:Destroy()
	end
	for _, child in guard:GetChildren() do
		if child:IsA("BasePart") then
			child.Transparency = 1
		end
	end
	local visual = PetVisualService.build(modelId, spec.scale, { effects = false })
	visual.Name = modelId
	local humanoid = guard:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 2
	visual:PivotTo(root.CFrame * CFrame.new(0, -root.Size.Y / 2 - hip, 0))
	local vroot = visual.PrimaryPart
	if vroot then
		vroot.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = vroot
		weld.Parent = vroot
	end
	-- 경비는 무섭게 빨간 테두리
	local h = Instance.new("Highlight")
	h.Name = "GuardGlow"
	h.FillTransparency = 1
	h.OutlineColor = Color3.fromRGB(255, 60, 60)
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = visual
	h.Parent = visual
	CollectionService:AddTag(h, Visuals.Tags.RarityHighlight)
	CollectionService:AddTag(visual, Visuals.Tags.GuardVisual)
	visual.Parent = guard
	guardVisuals[guard] = visual
	pcall(function()
		root:SetNetworkOwner(nil) -- 용접으로 조립이 바뀌어도 서버가 계속 물리 담당
	end)
end

local function onGuard(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local guard = inst
	task.defer(dressGuard, guard)
	guard:GetAttributeChangedSignal("GuardName"):Connect(function()
		dressGuard(guard)
	end)
	guard.Destroying:Connect(function()
		guardVisuals[guard] = nil
	end)
end

------------------------------------------------------------------
-- 모델 도서관 (클라 UI 용)
------------------------------------------------------------------

local function buildLibrary()
	local folder = Instance.new("Folder")
	folder.Name = "PetModels"
	local count = 0
	local ids: { string } = {}
	for _, pet in Pets.list do
		table.insert(ids, pet.id)
	end
	for id in Visuals.extra do
		table.insert(ids, id)
	end
	for _, id in ids do
		local ok, model = pcall(PetVisualService.build, id, 1, nil)
		if ok then
			model.Parent = folder
		else
			warn("[PetVisualService] 모델 실패 " .. id .. ": " .. tostring(model))
		end
		count += 1
		if count % 12 == 0 then
			task.wait()
		end
	end
	folder.Parent = ReplicatedStorage
end

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------

-- 우리 진열을 지금 바로 다시 맞춤 (보통은 1초마다 자동. 다른 서비스가 즉시 갱신하고 싶을 때 호출 가능)
PetVisualService.refreshPens = refreshPens

function PetVisualService.start()
	if PetVisualService.started then
		return
	end
	PetVisualService.started = true

	task.spawn(buildLibrary)

	local function onSpot(inst: Instance)
		if inst:IsA("BasePart") then
			task.defer(function()
				local ok, err = pcall(buildParent, inst)
				if not ok then
					warn("[PetVisualService] 부모 동물 실패: " .. tostring(err))
				end
			end)
		end
	end
	for _, spot in CollectionService:GetTagged(Tags.ParentAnimalSpot) do
		onSpot(spot)
	end
	CollectionService:GetInstanceAddedSignal(Tags.ParentAnimalSpot):Connect(onSpot)

	for _, guard in CollectionService:GetTagged(Tags.Guardian) do
		onGuard(guard)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Guardian):Connect(onGuard)

	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild(Tags.StateFolderName, 120)
		if state then
			state:GetAttributeChangedSignal(Tags.StateAttributes.HeavenSide):Connect(function()
				rebuildSidedParents()
				for guard in guardVisuals do
					dressGuard(guard)
				end
			end)
			rebuildSidedParents()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(refreshPens)
			if not ok then
				warn("[PetVisualService] 우리 갱신 오류: " .. tostring(err))
			end
		end
	end)
end

return PetVisualService
