--!strict
--[[
	PetVisualService — 6판: 경비(Guardian) 겉모습 = 식물 괴물 (서버가 만들어서 모두가 같은 모양을 봄). 선임 담당.

	- 경비 15종(+ 천사&악마 어두운 쪽): Visuals.guards[구역].model → Visuals.monsters (몸 + 머리 + 소품).
	  파리지옥·연꽃 개구리풀·가시 선인장 대장·덩굴 호랑이꽃·서리 가시나무·용암 머리꽃·심해 해초 괴물·공룡 고사리·
	  우주 버섯 거인·벚꽃 여우나무·돌 거인 나무·천사 백합/악마 장미·정령 버섯·사탕수수 거인·호박 머리 덩굴 ·
	  7판: 바이러스 덩굴(몸 vines + 머리 virus) · 디버그 선인장(안경·돋보기) · 글리치 장미 괴물(어긋난 겹 머리·깨진 픽셀).
	- 키 25~40 스터드 (Visuals.guards[..].height 에 맞춰 배율 자동). 겉모습 모델 이름 = model id, Attr Height = 키
	  → GuardianService 잡힘 거리. HumanoidRootPart 에 Weld "GuardPose" (Humanoid·HumanoidRootPart 이름은 그대로)
	  State Idle/Sleeping → 자는 자세 + BillboardGui "SleepZ"(TextLabel Z1~Z3), Chase → 일어섬 + Highlight "GuardGlow"
	  얼굴: Chase 일 때만 눈 뜸(EyeOpen) + 화난 눈썹(Brow), 그 밖(Sleeping/Idle/Return)은 감은 눈(EyeClosed)·눈썹 없음.
	- 식물(정원·둥지 옆 장식·UI 모델 도서관 PetModels)은 PlantVisualService. (5판 동물 체형·우리 펫 걷기는 6판에 없앰)

	모델 좌표: Root 파트가 "바닥 한가운데", 앞 = -Z (LookVector), 위 = +Y.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Visuals = require(Shared.Data.Visuals)
local Tags = require(Shared.Tags)

type Color = Visuals.Color

-- 경비 눈 하나: 눈 파트들 + 자리(크기 1 기준) + 감은 눈 줄을 그릴지 (해골·두건의 빛 눈은 끄기만)
type EyeRec = { parts: { BasePart }, pos: CFrame, e: number, close: boolean }

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
	eyes: { EyeRec }?, -- 경비 겉모습일 때만: 만든 눈 기록 (자는 얼굴 ↔ 추격 얼굴 바꾸기)
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
	effects: boolean?, -- (옛 호환, 안 씀)
	guard: boolean?, -- (옛 호환, 안 씀 — 괴물은 늘 경비 얼굴·소품)
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
local GOLD = Color3.fromRGB(255, 205, 50)
local DARK = Color3.fromRGB(60, 58, 70)
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

local PLASTIC = Enum.Material.Plastic

--[[
	복셀(블록) 스타일 — 원작처럼 "스터드 박힌 각진 블록 덩어리".
	  · 큰 "Ell"/"Ball"/"Cyl"/"Block" → 모서리가 깎인 블록 = 서로 교차하는 직육면체 3개
	    (각 축으로 한 개씩 길고 나머지 두 축은 bevel 만큼 짧음. 겹치는 면은 셋째 블록이 덮어서 깜빡임 없음)
	  · 작은 것(눈·이빨·점 등) → 직육면체 하나
	  · 표면: 스터드 (큰 면만), 재질 Plastic
	  · 납작한 원판(Cyl, 두께 < 지름 × 0.4: 모자 챙·고리·사탕) 은 둥근 원기둥 그대로
]]
local CHAMFER_MIN = 0.4 -- (크기 1 기준) 가장 짧은 변이 이 이상이면 모서리 깎기
local STUD_MIN = 0.55 -- (실제 크기) 가장 짧은 변이 이 이상이면 스터드 표면
local STUDS = Enum.SurfaceType.Studs
local SMOOTH = Enum.SurfaceType.Smooth

local function minOf(v: Vector3): number
	return math.min(v.X, v.Y, v.Z)
end

local function rawPart(ctx: Ctx, size: Vector3, world: CFrame, color: Color3, mat: Enum.Material, tr: number): Part
	local p = Instance.new("Part")
	p.Name = "Piece"
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	local surface = if minOf(size) >= STUD_MIN and mat ~= NEON then STUDS else SMOOTH
	p.TopSurface = surface
	p.BottomSurface = surface
	p.LeftSurface = surface
	p.RightSurface = surface
	p.FrontSurface = surface
	p.BackSurface = surface
	p.Color = color
	p.Material = mat
	p.Transparency = tr
	p.Size = Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
	p.CFrame = world
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = ctx.model
	return p
end

-- 파트 추가 (크기·위치는 크기 1 기준으로 받아서 ctx.s 배 함). 반환: 가운데(가장 큰) 파트
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
	local m = mat or ctx.mat
	local tr = transparency or 0
	local world = ctx.root.CFrame * CFrame.new(cf.Position * s) * cf.Rotation
	if kind == "Ball" then
		size = Vector3.one * size.X
	end
	if kind == "Cyl" and size.X < math.min(size.Y, size.Z) * 0.4 then
		-- 납작한 원판은 둥글게
		local p = rawPart(ctx, size * s, world, color, m, tr)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	if kind == "Wedge" then
		local p = rawPart(ctx, size * s, world, color, m, tr)
		p.Shape = Enum.PartType.Wedge
		return p
	end
	if minOf(size) < CHAMFER_MIN then
		return rawPart(ctx, size * s, world, color, m, tr)
	end
	-- 모서리 깎인 블록 (3개)
	local b = minOf(size) * 0.2 * 2
	local x, y, z = size.X * s, size.Y * s, size.Z * s
	local bs = b * s
	local core = rawPart(ctx, Vector3.new(x, y - bs, z - bs), world, color, m, tr)
	rawPart(ctx, Vector3.new(x - bs, y, z - bs), world, color, m, tr)
	rawPart(ctx, Vector3.new(x - bs, y - bs, z), world, color, m, tr)
	return core
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

-- 네모 눈 한 쌍 (검은 네모 + 흰 하이라이트 네모). pos = 눈 가운데, 앞 = -Z
local function squareEye(ctx: Ctx, pos: CFrame, e: number, side: number)
	local parts: { BasePart }
	if ctx.has.eyes_glow then
		parts = { blk(ctx, e * 1.05, e * 1.05, 0.08, pos, ctx.c3, NEON) }
	else
		parts = {
			blk(ctx, e, e * 1.15, 0.08, pos, BLACK, PLASTIC),
			blk(ctx, e * 0.4, e * 0.4, 0.06, pos * CFrame.new(side * e * 0.18, e * 0.25, -0.03), WHITE, PLASTIC),
		}
	end
	local eyes = ctx.eyes
	if eyes then
		table.insert(eyes, { parts = parts, pos = pos, e = e, close = true })
	end
end

-- 머리(블록) 앞면에 눈 + 얼굴 아래쪽에 작은 입 선
local function eyesAt(ctx: Ctx, head: CFrame, hs: Vector3)
	local e = math.max(0.14, math.min(hs.X, hs.Y) * 0.22)
	for _, side in SIDES do
		squareEye(ctx, head * CFrame.new(side * hs.X * 0.24, hs.Y * 0.1, -hs.Z * 0.5), e, side)
	end
end

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

-- 화난 눈썹 (eyesAt 과 같은 눈 자리 바로 위, 안쪽이 내려간 비스듬한 막대)
local function angryBrows(ctx: Ctx, a: Anchors, color: Color3?)
	if a.skipEyes then
		return
	end
	local hs = a.headSize
	local e = math.max(0.14, math.min(hs.X, hs.Y) * 0.22)
	for _, side in SIDES do
		local brow = blk(
			ctx,
			e * 1.5,
			e * 0.32,
			0.1,
			a.head
				* CFrame.new(side * hs.X * 0.24, hs.Y * 0.1 + e * 0.95, -hs.Z * 0.5 - 0.03)
				* CFrame.Angles(0, 0, rad(side * 22)),
			color or BLACK,
			PLASTIC
		)
		brow.Name = "Brow" -- 추격(Chase) 때만 보임 (setGuardFace)
	end
end

-- 경비 얼굴 (사장님: 처음부터 화난 얼굴이면 안 됨)
--   깨어 쫓을 때(State = "Chase")만 눈을 뜨고(EyeOpen) 화난 눈썹(Brow)이 보임.
--   그 밖(Sleeping / Idle / Return)은 감은 눈 줄(EyeClosed)만 보임 (해골·두건의 빛 눈은 꺼짐).
--   보일 때 투명도 = 처음 만든 값(Attribute FaceShown, 유령 반투명 유지), 숨길 때 = 1
local FACE_AWAKE: { [string]: boolean } = { EyeOpen = true, Brow = true }
local FACE_ASLEEP: { [string]: boolean } = { EyeClosed = true }

local function setGuardFace(model: Model, awake: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (FACE_AWAKE[d.Name] or FACE_ASLEEP[d.Name]) then
			local shown = d:GetAttribute("FaceShown")
			local visible = if FACE_AWAKE[d.Name] then awake else not awake
			d.Transparency = if visible then (if typeof(shown) == "number" then shown else 0) else 1
		end
	end
end

-- build 끝에서: 기록한 눈에 이름 붙이고 감은 눈 줄을 만든 뒤 자는 얼굴로 시작
local function setupGuardFace(ctx: Ctx)
	local eyes: { EyeRec } = ctx.eyes or {}
	for _, rec in eyes do
		for _, p in rec.parts do
			p.Name = "EyeOpen"
		end
		if rec.close then
			local line =
				blk(ctx, rec.e * 1.3, rec.e * 0.22, 0.1, rec.pos * CFrame.new(0, -rec.e * 0.15, 0), BLACK, PLASTIC)
			line.Name = "EyeClosed"
		end
	end
	for _, d in ctx.model:GetDescendants() do
		if d:IsA("BasePart") and (FACE_AWAKE[d.Name] or FACE_ASLEEP[d.Name]) then
			d:SetAttribute("FaceShown", d.Transparency)
		end
	end
	setGuardFace(ctx.model, false)
end

------------------------------------------------------------------
-- 식물 괴물 (6판 경비 15종 + 천사&악마 어두운 쪽) — Visuals.monsters
--   크기 1 기준 키 약 3~4 스터드, 앞 = -Z. 몸(body) + 머리(head) + 소품(extras). 얼굴은 eyesAt (경비 얼굴 규칙 그대로)
------------------------------------------------------------------

local function sm(
	ctx: Ctx,
	shape: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	tr: number?
): BasePart
	local s = ctx.s
	local world = ctx.root.CFrame * CFrame.new(cf.Position * s) * cf.Rotation
	local sz = size * s
	if shape == "Cyl" then
		sz = Vector3.new(size.Y, size.X, size.Z) * s
		world = world * CFrame.Angles(0, 0, math.pi / 2)
	end
	local p = rawPart(ctx, sz, world, color, mat or Enum.Material.SmoothPlastic, tr or 0)
	for _, face in { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" } do
		(p :: any)[face] = Enum.SurfaceType.Smooth
	end
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * sz.X
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Wedge" then
		p.Shape = Enum.PartType.Wedge
	elseif shape == "Ell" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	return p
end

local function monsterEmitter(ctx: Ctx, host: BasePart, kind: string, color: Color3)
	local e = emitter(host, if kind == "mist" then "smoke" else "sparkle", color, ctx.s * 0.8)
	e.Name = "MonsterFx"
	e.Rate = 5
	if kind == "embers" then
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Lifetime = NumberRange.new(0.8, 1.4)
	elseif kind == "snow" or kind == "petals" then
		e.Acceleration = Vector3.new(0.4, -2, 0)
		e.Lifetime = NumberRange.new(2, 3)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.LightEmission = 0.3
	elseif kind == "bubbles" then
		e.Acceleration = Vector3.new(0, 2.5, 0)
		e.LightEmission = 0.4
	end
end

-- 몸: 머리 자리(hy)와 얼굴 기준(face, faceSize)을 정함
type Shape = {
	head: CFrame,
	headSize: Vector3,
	body: CFrame,
	bodySize: Vector3,
	top: number,
	hy: number,
	faceOnBody: boolean,
}

local function monsterBody(ctx: Ctx, kind: string): Shape
	local c1 = ctx.c1
	if kind == "trunk" then
		sm(ctx, "Cyl", Vector3.new(1.2, 2.3, 1.2), at(0, 1.15, 0), c1, Enum.Material.Wood)
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			sm(
				ctx,
				"Ell",
				Vector3.new(0.45, 0.4, 0.9),
				CFrame.Angles(0, a, 0) * at(0, 0.15, -0.65, 20),
				c1,
				Enum.Material.Wood
			)
		end
		ctx.body = ctx.model:FindFirstChildWhichIsA("BasePart")
		return {
			head = at(0, 1.55, 0),
			headSize = Vector3.new(0.95, 0.9, 1.25),
			body = at(0, 1.15, 0),
			bodySize = Vector3.new(1.2, 2.3, 1.2),
			top = 2.3,
			hy = 2.3,
			faceOnBody = true,
		}
	elseif kind == "blob" then
		local body = sm(ctx, "Ball", Vector3.one * 1.9, at(0, 0.95, 0), c1)
		ctx.body = body
		for _, side in SIDES do
			sm(ctx, "Ball", Vector3.one * 0.6, at(side * 0.5, 1.75, -0.35), c1) -- 눈두덩
			sm(ctx, "Ell", Vector3.new(0.5, 0.3, 0.8), at(side * 0.75, 0.15, -0.5), c1:Lerp(BLACK, 0.1)) -- 발
		end
		return {
			head = at(0, 1.35, 0),
			headSize = Vector3.new(1.2, 0.9, 1.75),
			body = at(0, 0.95, 0),
			bodySize = Vector3.new(1.9, 1.9, 1.9),
			top = 1.9,
			hy = 1.9,
			faceOnBody = true,
		}
	elseif kind == "column" then
		local body = sm(ctx, "Cyl", Vector3.new(1.05, 2.4, 1.05), at(0, 1.2, 0), c1)
		ctx.body = body
		sm(ctx, "Ball", Vector3.one * 1.05, at(0, 2.4, 0), c1)
		return {
			head = at(0, 1.95, 0),
			headSize = Vector3.new(0.85, 0.8, 1.08),
			body = at(0, 1.2, 0),
			bodySize = Vector3.new(1.05, 2.4, 1.05),
			top = 2.92,
			hy = 2.6,
			faceOnBody = true,
		}
	elseif kind == "vines" then
		-- 7판 바이러스 덩굴: 동그란 몸통을 꼬인 덩굴 3가닥이 감고 올라가고, 땅을 기는 덩굴 4가닥
		local body = sm(ctx, "Ball", Vector3.one * 1.45, at(0, 0.95, 0), c1)
		ctx.body = body
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			sm(
				ctx,
				"Cyl",
				Vector3.new(0.34, 2.5, 0.34),
				CFrame.Angles(0, a, 0) * at(0, 1.35, 0.3, 14),
				if i % 2 == 0 then ctx.c2 else c1:Lerp(BLACK, 0.12)
			)
		end
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + 0.4
			sm(
				ctx,
				"Cyl",
				Vector3.new(0.28, 1.7, 0.28),
				CFrame.Angles(0, a, 0) * at(0, 0.22, -1.0, 75),
				c1:Lerp(BLACK, 0.2)
			)
		end
		return {
			head = at(0, 2.6, 0),
			headSize = Vector3.new(1.1, 1.0, 1.4),
			body = at(0, 0.95, 0),
			bodySize = Vector3.new(1.45, 2.5, 1.45),
			top = 2.6,
			hy = 2.45,
			faceOnBody = false,
		}
	elseif kind == "kelp" then
		local body = sm(ctx, "Ball", Vector3.one * 1.5, at(0, 1.1, 0), c1)
		ctx.body = body
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			local h = 2.6 + (i % 3) * 0.35
			sm(
				ctx,
				"Ell",
				Vector3.new(0.4, h, 0.16),
				CFrame.Angles(0, a, 0) * at(0, h / 2, 0.55, -8),
				if i % 2 == 0 then ctx.c2 else c1
			)
		end
		return {
			head = at(0, 1.2, 0),
			headSize = Vector3.new(0.95, 0.9, 1.45),
			body = at(0, 1.1, 0),
			bodySize = Vector3.new(1.5, 1.5, 1.5),
			top = 3.3,
			hy = 1.8,
			faceOnBody = true,
		}
	end
	-- stalk (줄기)
	local body = sm(ctx, "Cyl", Vector3.new(0.45, 1.8, 0.45), at(0, 0.9, 0), c1)
	ctx.body = body
	sm(ctx, "Cyl", Vector3.new(0.4, 0.7, 0.4), at(0, 2.05, 0.05, 10), c1)
	return {
		head = at(0, 2.6, 0),
		headSize = Vector3.new(1, 0.9, 1.1),
		body = at(0, 1.2, 0),
		bodySize = Vector3.new(0.6, 2.4, 0.6),
		top = 2.6,
		hy = 2.6,
		faceOnBody = false,
	}
end

-- 머리: 얼굴 자리를 고쳐서 돌려줌
local function monsterHead(ctx: Ctx, kind: string, sh: Shape): Shape
	local c2, c3 = ctx.c2, ctx.c3
	local hy = sh.hy
	if kind == "jaws" then
		sm(ctx, "Ell", Vector3.new(1.7, 0.6, 1.5), at(0, hy + 0.3, -0.2, 14), c2)
		sm(ctx, "Ell", Vector3.new(1.6, 0.5, 1.4), at(0, hy - 0.3, -0.2, -12), c2)
		sm(ctx, "Ell", Vector3.new(1.3, 0.45, 1.1), at(0, hy, -0.15), c3, NEON)
		sh.head = at(0, hy + 0.48, -0.15)
		sh.headSize = Vector3.new(1.05, 0.5, 1.35)
		sh.top = hy + 0.75
	elseif kind == "flower" then
		local center = sm(ctx, "Ball", Vector3.one * 1.15, at(0, hy + 0.3, 0), c2:Lerp(WHITE, 0.35))
		ctx.body = center
		local n = 7
		for i = 1, n do
			local a = i / n * math.pi * 2
			sm(
				ctx,
				"Ell",
				Vector3.new(0.6, 1.0, 0.18),
				at(0, hy + 0.3, 0.2) * CFrame.Angles(0, 0, a) * at(0, 0.8, 0),
				c2
			)
		end
		sh.head = at(0, hy + 0.3, 0)
		sh.headSize = Vector3.new(0.9, 0.9, 1.12)
		sh.top = hy + 1.35
	elseif kind == "cap" then
		local cap = sm(ctx, "Ell", Vector3.new(2.8, 1.15, 2.8), at(0, sh.hy + 0.25, 0), c2)
		ctx.body = cap
		sh.top = sh.hy + 0.82
	elseif kind == "canopy" then
		sm(ctx, "Ball", Vector3.one * 2.5, at(0, hy + 0.85, 0.1), c2)
		sm(ctx, "Ball", Vector3.one * 1.6, at(1.05, hy + 0.5, 0.25), c2:Lerp(BLACK, 0.08))
		sm(ctx, "Ball", Vector3.one * 1.6, at(-1.05, hy + 0.55, 0.2), c2:Lerp(WHITE, 0.08))
		sh.top = hy + 2.1
	elseif kind == "pumpkin" then
		local head = sm(ctx, "Ell", Vector3.new(1.8, 1.45, 1.6), at(0, hy + 0.35, 0), c2)
		ctx.body = head
		sm(ctx, "Ell", Vector3.new(0.7, 1.4, 1.62), at(0, hy + 0.35, 0), c2:Lerp(BLACK, 0.15))
		sm(ctx, "Cyl", Vector3.new(0.18, 0.4, 0.18), at(0.05, hy + 1.15, 0, 0, 0, 12), ctx.c1)
		sh.head = at(0, hy + 0.4, 0)
		sh.headSize = Vector3.new(1.3, 1.0, 1.62)
		sh.top = hy + 1.35
	elseif kind == "lotus" then
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			sm(
				ctx,
				"Ell",
				Vector3.new(0.38, 0.75, 0.2),
				at(0, hy - 0.05, 0) * CFrame.Angles(0, a, 0) * at(0, 0, -0.42, -25),
				c2
			)
		end
		sm(ctx, "Ball", Vector3.one * 0.4, at(0, hy + 0.05, 0), c3, NEON)
		sh.top = hy + 0.4
	elseif kind == "rose" then
		local head = sm(ctx, "Ball", Vector3.one * 1.25, at(0, hy + 0.3, 0), c2:Lerp(BLACK, 0.1))
		ctx.body = head
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			sm(
				ctx,
				"Ell",
				Vector3.new(0.85, 0.75, 0.25),
				at(0, hy + 0.25, 0) * CFrame.Angles(0, a + 0.3, 0) * at(0, 0, 0.55, 15),
				c2
			)
		end
		sh.head = at(0, hy + 0.3, 0)
		sh.headSize = Vector3.new(0.95, 0.95, 1.25)
		sh.top = hy + 0.95
	elseif kind == "virus" then
		-- 7판 바이러스 덩굴 머리: 돌기(끝이 빛나는 공) 8개가 난 바이러스 공
		local cy = hy + 0.55
		local head = sm(ctx, "Ball", Vector3.one * 1.55, at(0, cy, 0), c2)
		ctx.body = head
		for i = 1, 8 do
			local tilt = if i % 2 == 0 then 48 else 128
			local turn = CFrame.Angles(0, rad(i * 45 + 22), 0) * CFrame.Angles(rad(tilt), 0, 0)
			sm(ctx, "Cyl", Vector3.new(0.13, 0.5, 0.13), at(0, cy, 0) * turn * at(0, 0.9, 0), c2:Lerp(BLACK, 0.25))
			sm(ctx, "Ball", Vector3.one * 0.28, at(0, cy, 0) * turn * at(0, 1.17, 0), c3, NEON)
		end
		sh.head = at(0, cy, 0)
		sh.headSize = Vector3.new(1.15, 1.1, 1.55)
		sh.top = cy + 1.25
	elseif kind == "lily" then
		local head = sm(ctx, "Ball", Vector3.one * 0.9, at(0, hy + 0.25, 0), c2)
		ctx.body = head
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			sm(
				ctx,
				"Ell",
				Vector3.new(0.42, 1.2, 0.16),
				at(0, hy + 0.25, 0.15) * CFrame.Angles(0, 0, a) * at(0, 0.62, 0, -15),
				c2
			)
		end
		sm(ctx, "Ball", Vector3.one * 0.25, at(0, hy + 0.85, -0.2), c3, NEON)
		sh.head = at(0, hy + 0.25, 0)
		sh.headSize = Vector3.new(0.75, 0.75, 0.92)
		sh.top = hy + 1.3
	end
	return sh
end

type MonsterExtra = (Ctx, Shape) -> ()
local MONSTER_EXTRAS: { [string]: MonsterExtra } = {}

MONSTER_EXTRAS.leaves = function(ctx, _sh)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + 0.4
		sm(
			ctx,
			"Ell",
			Vector3.new(0.6, 0.12, 1.6),
			CFrame.Angles(0, a, 0) * at(0, 0.25, -0.75, 18),
			ctx.c1:Lerp(WHITE, 0.15)
		)
	end
end
MONSTER_EXTRAS.teeth = function(ctx, sh)
	for i = 1, 6 do
		local x = (i - 3.5) * 0.24
		local up = i % 2 == 0
		sm(
			ctx,
			"Wedge",
			Vector3.new(0.12, 0.28, 0.14),
			at(x, sh.hy + (if up then 0.12 else -0.12), -0.85, if up then 180 else 0),
			WHITE
		)
	end
end
MONSTER_EXTRAS.spines = function(ctx, sh)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local r = sh.bodySize.X / 2
		sm(
			ctx,
			"Block",
			Vector3.new(0.06, 0.06, 0.3),
			CFrame.Angles(0, a, 0) * at(0, 0.5 + (i % 4) * 0.5, -r - 0.1),
			ctx.c3
		)
	end
end
MONSTER_EXTRAS.thorns = function(ctx, sh)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local r = sh.bodySize.X / 2
		sm(
			ctx,
			"Wedge",
			Vector3.new(0.12, 0.35, 0.3),
			CFrame.Angles(0, a, 0) * at(0, 0.6 + (i % 3) * 0.55, -r - 0.1, -90),
			ctx.c3
		)
	end
end
MONSTER_EXTRAS.arms = function(ctx, sh)
	local y = sh.bodySize.Y * 0.55
	local r = sh.bodySize.X / 2
	for _, side in SIDES do
		sm(ctx, "Cyl", Vector3.new(0.34, 1.0, 0.34), at(side * (r + 0.45), y, 0, 0, 0, 90), ctx.c1)
		sm(ctx, "Cyl", Vector3.new(0.32, 0.9, 0.32), at(side * (r + 0.95), y + 0.4, 0), ctx.c1)
		sm(ctx, "Ball", Vector3.one * 0.42, at(side * (r + 0.95), y + 0.85, 0), ctx.c1)
	end
end
MONSTER_EXTRAS.flower_top = function(ctx, sh)
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		sm(
			ctx,
			"Ell",
			Vector3.new(0.3, 0.12, 0.5),
			at(0, sh.top + 0.02, 0) * CFrame.Angles(0, a, 0) * at(0, 0, -0.2),
			ctx.c2
		)
	end
	sm(ctx, "Ball", Vector3.one * 0.25, at(0, sh.top + 0.08, 0), ctx.c3)
end
MONSTER_EXTRAS.stripes = function(ctx, sh)
	if ctx.bodyKind == "column" then
		for i = 1, 4 do
			sm(ctx, "Cyl", Vector3.new(1.08, 0.24, 1.08), at(0, i * 0.5, 0, 0, 0, 0), ctx.c2)
		end
	else
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + 0.4
			sm(
				ctx,
				"Block",
				Vector3.new(0.12, 0.6, 0.05),
				at(0, sh.hy + 0.3, 0.32) * CFrame.Angles(0, 0, a) * at(0, 0.85, 0),
				ctx.c3
			)
		end
	end
end
MONSTER_EXTRAS.snow = function(ctx, _sh)
	if ctx.body then
		monsterEmitter(ctx, ctx.body, "snow", Color3.fromRGB(235, 245, 255))
	end
end
MONSTER_EXTRAS.embers = function(ctx, _sh)
	if ctx.body then
		monsterEmitter(ctx, ctx.body, "embers", Color3.fromRGB(255, 140, 40))
	end
end
MONSTER_EXTRAS.bubbles = function(ctx, _sh)
	if ctx.body then
		monsterEmitter(ctx, ctx.body, "bubbles", Color3.fromRGB(190, 240, 255))
	end
end
MONSTER_EXTRAS.petals = function(ctx, _sh)
	if ctx.body then
		monsterEmitter(ctx, ctx.body, "petals", Color3.fromRGB(255, 180, 210))
	end
end
MONSTER_EXTRAS.mist = function(ctx, _sh)
	if ctx.body then
		monsterEmitter(ctx, ctx.body, "mist", Color3.fromRGB(150, 110, 200))
	end
end
MONSTER_EXTRAS.stars = function(ctx, _sh)
	if ctx.body then
		monsterEmitter(ctx, ctx.body, "stars", Color3.fromRGB(255, 240, 150))
	end
end
MONSTER_EXTRAS.glowbulbs = function(ctx, _sh)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + 0.5
		sm(ctx, "Ball", Vector3.one * 0.32, CFrame.Angles(0, a, 0) * at(0, 2.2 + i * 0.25, 0.6), ctx.c3, NEON)
	end
end
MONSTER_EXTRAS.fronds = function(ctx, sh)
	for i = 1, 4 do
		local x = (i - 2.5) * 0.3
		sm(ctx, "Ell", Vector3.new(0.35, 0.08, 1.7), at(x, sh.hy * 0.7 + i * 0.12, 0.7, -40, (i - 2.5) * 18, 0), ctx.c2)
	end
end
MONSTER_EXTRAS.glowspots = function(ctx, sh)
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		sm(ctx, "Ball", Vector3.one * 0.32, CFrame.Angles(0, a, 0) * at(0, sh.top - 0.25, -0.9), ctx.c3, NEON)
	end
end
MONSTER_EXTRAS.ears = function(ctx, sh)
	for _, side in SIDES do
		sm(ctx, "Wedge", Vector3.new(0.3, 0.9, 0.7), at(side * 0.6, sh.top + 0.25, 0, 0, 0, side * -12), ctx.c3)
	end
end
MONSTER_EXTRAS.crown = function(ctx, sh)
	sm(ctx, "Cyl", Vector3.new(1.0, 0.25, 1.0), at(0, sh.top + 0.05, 0), GOLD, FOIL)
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2
		sm(ctx, "Block", Vector3.new(0.18, 0.35, 0.18), CFrame.Angles(0, a, 0) * at(0, sh.top + 0.3, -0.42), GOLD, FOIL)
	end
end
MONSTER_EXTRAS.halo = function(ctx, sh)
	sm(ctx, "Cyl", Vector3.new(1.2, 0.08, 1.2), at(0, sh.top + 0.35, 0), GOLD, NEON, 0.2)
end
MONSTER_EXTRAS.wings = function(ctx, sh)
	for _, side in SIDES do
		sm(ctx, "Ell", Vector3.new(0.2, 1.4, 0.9), at(side * 0.55, sh.hy * 0.62, 0.45, 0, side * 35, side * -20), WHITE)
	end
end
MONSTER_EXTRAS.horns = function(ctx, sh)
	for _, side in SIDES do
		sm(ctx, "Wedge", Vector3.new(0.2, 0.7, 0.3), at(side * 0.4, sh.top - 0.05, 0, 0, 0, side * -18), DARK)
	end
end
MONSTER_EXTRAS.orbs = function(ctx, sh)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2
		sm(ctx, "Ball", Vector3.one * 0.35, CFrame.Angles(0, a, 0) * at(0, sh.hy * 0.7, -1.7), ctx.c3, NEON, 0.15)
	end
end
MONSTER_EXTRAS.candy_top = function(ctx, sh)
	sm(ctx, "Cyl", Vector3.new(1.3, 0.25, 1.3), at(0, sh.top + 0.55, 0, 90), ctx.c2)
	sm(ctx, "Cyl", Vector3.new(0.8, 0.27, 0.8), at(0, sh.top + 0.55, -0.01, 90), WHITE)
end
-- 7판 바이러스 덩굴: 몸 옆으로 굽어 올라가는 덩굴 손 2개 (끝에 빛나는 잎)
MONSTER_EXTRAS.tendrils = function(ctx, _sh)
	for _, side in SIDES do
		local base = at(side * 0.75, 0.9, 0.1)
		sm(ctx, "Cyl", Vector3.new(0.24, 1.3, 0.24), base * at(side * 0.25, 0.55, 0, 0, 0, side * -28), ctx.c1)
		sm(ctx, "Cyl", Vector3.new(0.2, 1.0, 0.2), base * at(side * 0.75, 1.45, -0.1, -20, 0, side * 22), ctx.c2)
		sm(ctx, "Ell", Vector3.new(0.5, 0.12, 0.8), base * at(side * 0.6, 2.0, -0.35, 30, 0, 0), ctx.c3, NEON)
	end
end
-- 7판 바이러스 덩굴: 둘레에 떠 있는 초록 코드 조각 4개 + 위로 흩날리는 빛 (가까울 때만 보이게 Rate 작게)
MONSTER_EXTRAS.codebits = function(ctx, sh)
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + 0.3
		sm(
			ctx,
			"Block",
			Vector3.new(0.12, 0.42, 0.12),
			CFrame.Angles(0, a, 0) * at(0, sh.hy * 0.5 + (i % 2) * 0.6, -1.45),
			ctx.c3,
			NEON,
			0.2
		)
	end
	if ctx.body then
		monsterEmitter(ctx, ctx.body, "embers", ctx.c3)
	end
end
-- 7판 디버그 선인장: 얼굴에 네모난 안경 (검은 테 + 파란 반투명 알 + 다리)
MONSTER_EXTRAS.glasses = function(ctx, sh)
	local hs = sh.headSize
	local e = math.max(0.14, math.min(hs.X, hs.Y) * 0.22)
	local w = e * 2.1
	local z = -hs.Z * 0.5 - 0.08
	for _, side in SIDES do
		local c = sh.head * CFrame.new(side * hs.X * 0.24, hs.Y * 0.1, z)
		sm(ctx, "Block", Vector3.new(w, w * 0.9, 0.03), c, ctx.c2, NEON, 0.6)
		sm(ctx, "Block", Vector3.new(w + 0.06, 0.06, 0.06), c * CFrame.new(0, w * 0.45 + 0.03, 0), BLACK)
		sm(ctx, "Block", Vector3.new(w + 0.06, 0.06, 0.06), c * CFrame.new(0, -w * 0.45 - 0.03, 0), BLACK)
		sm(
			ctx,
			"Block",
			Vector3.new(0.05, 0.05, hs.Z * 0.45),
			c * CFrame.new(side * w * 0.5, w * 0.3, hs.Z * 0.22),
			BLACK
		)
	end
	sm(
		ctx,
		"Block",
		Vector3.new(hs.X * 0.48 - w + 0.06, 0.05, 0.05),
		sh.head * CFrame.new(0, hs.Y * 0.1 + w * 0.2, z),
		BLACK
	)
end
-- 7판 디버그 선인장: 오른손에 돋보기 (버그 찾기)
MONSTER_EXTRAS.magnifier = function(ctx, sh)
	local r = sh.bodySize.X / 2
	local hand = at(r + 0.95, sh.bodySize.Y * 0.55 + 0.85, -0.1)
	sm(ctx, "Cyl", Vector3.new(0.14, 0.7, 0.14), hand * at(0, 0.3, 0), DARK)
	sm(ctx, "Cyl", Vector3.new(0.95, 0.1, 0.95), hand * at(0, 1.05, -0.05, 90), BLACK)
	sm(ctx, "Cyl", Vector3.new(0.78, 0.12, 0.78), hand * at(0, 1.05, -0.06, 90), ctx.c2, NEON, 0.55)
end
-- 7판 글리치 장미 괴물: 머리 둘레에 떠 있는 깨진 픽셀 6개 (Attr Glitch + EggShell 태그 → 클라가 색을 뚝뚝 바꿈)
MONSTER_EXTRAS.pixelshards = function(ctx, sh)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + (i % 2) * 0.4
		local px = sm(
			ctx,
			"Block",
			Vector3.one * (0.22 + (i % 3) * 0.08),
			CFrame.Angles(0, a, 0) * at(0, sh.hy - 0.6 + (i % 3) * 0.6, -1.3 - (i % 2) * 0.3),
			if i % 2 == 0 then ctx.c2 else ctx.c3,
			NEON
		)
		px:SetAttribute("Glitch", true)
		CollectionService:AddTag(px, Visuals.Tags.EggShell)
	end
end
-- 7판 글리치 장미 괴물: 머리가 분홍·초록으로 어긋나 겹쳐 보임 (화면이 깨진 것처럼, 반투명 2겹)
MONSTER_EXTRAS.ghostlayer = function(ctx, sh)
	for i, side in SIDES do
		sm(
			ctx,
			"Ball",
			Vector3.one * 1.3,
			sh.head * CFrame.new(side * 0.22, 0.05 * side, 0.12),
			if i == 1 then Color3.fromRGB(255, 0, 200) else Color3.fromRGB(0, 255, 90),
			NEON,
			0.7
		)
	end
end

-- 괴물 하나 만들기 (경비 겉모습). Height Attribute = 꼭대기 높이 × scale (GuardianService 잡힘 거리)
function PetVisualService.buildMonster(id: string, scale: number, _opts: BuildOptions?): Model
	local look = Visuals.monsters[id] or Visuals.monsters.flytrap_monster
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
	local ctx: Ctx = {
		model = model,
		root = root,
		s = scale,
		c1 = rgb(look.colors[1]),
		c2 = rgb(look.colors[2] or look.colors[1]),
		c3 = rgb(look.colors[3] or look.colors[1]),
		mat = Enum.Material.SmoothPlastic,
		accentMat = NEON,
		has = { eyes_glow = look.glowEyes == true },
		body = nil,
		bodyKind = look.body,
		eyes = {},
	}
	local sh = monsterBody(ctx, look.body)
	sh = monsterHead(ctx, look.head, sh)
	local a: Anchors = {
		head = sh.head,
		headSize = sh.headSize,
		body = sh.body,
		bodySize = sh.bodySize,
		tail = sh.body,
		top = sh.top,
	}
	eyesAt(ctx, a.head, a.headSize)
	angryBrows(ctx, a)
	for _, name in look.extras do
		local fn = MONSTER_EXTRAS[name]
		if fn then
			fn(ctx, sh)
		end
	end
	if look.ghostly then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				d.Transparency = math.max(d.Transparency, 0.3)
			end
		end
	end
	setupGuardFace(ctx)
	model:SetAttribute("PetId", id)
	model:SetAttribute("Height", sh.top * scale)
	return model
end

-- (호환) 경비 겉모습 만들기 = 식물 괴물
function PetVisualService.build(id: string, scale: number, opts: BuildOptions?): Model
	return PetVisualService.buildMonster(id, scale, opts)
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
-- 경비 겉모습 (거대함: 키 25~40 스터드)
--   HumanoidRootPart 에 Weld "GuardPose" 로 붙임 (C0 를 바꿔 서기/자기 자세 전환).
--   State == "Idle"/"Sleeping" → 자는 자세(낮추고 앞으로 살짝 엎드림) + 머리 위 파란 Z (BillboardGui "SleepZ")
--   State == "Chase" → 일어선 자세 + 빨간 테두리(Highlight "GuardGlow"). 그 밖("Return" 등) → 일어섬, 테두리 끔
------------------------------------------------------------------

local GUARD_HEIGHT = 32 -- Visuals.guards[..].height 가 없을 때
local Z_COLOR = Color3.fromRGB(110, 170, 255)
local Z_STROKE = Color3.fromRGB(25, 45, 120)

type GuardInfo = {
	visual: Model,
	pose: Weld,
	stand: CFrame,
	sleep: CFrame,
	z: BillboardGui,
	glow: Highlight,
}
local guardInfo: { [Model]: GuardInfo } = {}

-- 크기 1 일 때 키 (경비 크기 계산용, 한 번만 만들어 봄)
local baseHeights: { [string]: number } = {}
local function baseHeight(id: string): number
	local cached = baseHeights[id]
	if cached then
		return cached
	end
	local m = PetVisualService.build(id, 1, nil)
	local h = math.max(0.5, height(m))
	m:Destroy()
	baseHeights[id] = h
	return h
end

local function sleepZ(adornee: BasePart, h: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "SleepZ"
	gui.Adornee = adornee
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	local size = math.max(8, h * 0.4)
	gui.Size = UDim2.fromScale(size, size)
	gui.StudsOffsetWorldSpace = Vector3.new(h * 0.15, h + size * 0.3, 0)
	-- 작은 Z(아래 왼쪽) → 큰 Z(위 오른쪽). 클라가 Z1~Z3 을 둥실둥실 움직여도 됨
	for i, spec in { { 0.08, 0.62, 0.26 }, { 0.32, 0.32, 0.34 }, { 0.58, 0.0, 0.42 } } do
		local label = Instance.new("TextLabel")
		label.Name = "Z" .. i
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(spec[1], spec[2])
		label.Size = UDim2.fromScale(spec[3], spec[3])
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = "Z"
		label.TextColor3 = Z_COLOR
		label.Rotation = -12 + i * 6
		local stroke = Instance.new("UIStroke")
		stroke.Color = Z_STROKE
		stroke.Thickness = 3
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
		label.Parent = gui
	end
	gui.Parent = adornee
	return gui
end

local function isSleeping(state: any): boolean
	return state == nil or state == "Idle" or state == "Sleeping"
end

local function applyGuardState(guard: Model)
	local info = guardInfo[guard]
	if not info or info.visual.Parent ~= guard then
		return
	end
	local state = guard:GetAttribute("State")
	local sleeping = isSleeping(state)
	info.pose.C0 = if sleeping then info.sleep else info.stand
	info.z.Enabled = sleeping
	info.glow.Enabled = state == "Chase"
	setGuardFace(info.visual, state == "Chase") -- 쫓을 때만 눈 뜨고 화난 눈썹
end

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
	local old = guardInfo[guard]
	if old and old.visual.Parent then
		if old.visual.Name == modelId then
			applyGuardState(guard)
			return
		end
		old.visual:Destroy()
	end
	guardInfo[guard] = nil
	for _, child in guard:GetChildren() do
		if child:IsA("BasePart") then
			child.Transparency = 1
		end
	end
	local targetHeight = spec.height or GUARD_HEIGHT
	local scale = targetHeight / baseHeight(modelId)
	local visual = PetVisualService.build(modelId, scale, { effects = false, guard = true })
	visual.Name = modelId
	local h = height(visual)
	local humanoid = guard:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 2
	-- 서기: 발바닥(Root) = 루트 아래 HipHeight 만큼 (땅)
	local stand = CFrame.new(0, -root.Size.Y / 2 - hip, 0)
	-- 자기: 조금 가라앉고 앞으로 엎드리듯 기울임 + 살짝 옆으로
	local sleep = stand * CFrame.new(0, -h * 0.05, 0) * CFrame.Angles(rad(-7), 0, rad(4))
	visual:PivotTo(root.CFrame * stand)
	local vroot = visual.PrimaryPart :: BasePart
	vroot.Anchored = false
	local pose = Instance.new("Weld")
	pose.Name = "GuardPose"
	pose.Part0 = root
	pose.Part1 = vroot
	pose.C0 = stand
	pose.Parent = vroot

	local z = sleepZ(vroot, h)

	-- 쫓을 때만 빨간 테두리 (희귀도 Highlight 한계 관리 태그는 안 붙임: 추격 중인 경비만 켜짐)
	local glow = Instance.new("Highlight")
	glow.Name = "GuardGlow"
	glow.FillTransparency = 1
	glow.OutlineColor = Color3.fromRGB(255, 50, 50)
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Adornee = visual
	glow.Enabled = false
	glow.Parent = visual

	CollectionService:AddTag(visual, Visuals.Tags.GuardVisual)
	visual.Parent = guard
	guardInfo[guard] = { visual = visual, pose = pose, stand = stand, sleep = sleep, z = z, glow = glow }
	applyGuardState(guard)
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
	guard:GetAttributeChangedSignal("State"):Connect(function()
		applyGuardState(guard)
	end)
	guard.Destroying:Connect(function()
		guardInfo[guard] = nil
	end)
end

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------

-- 경비 자세(자기/서기)·Z·빨간 테두리를 State Attribute 에 맞춤 (State 가 바뀌면 자동. 테스트·즉시 갱신용)
PetVisualService.refreshGuard = applyGuardState

function PetVisualService.start()
	if PetVisualService.started then
		return
	end
	PetVisualService.started = true

	for _, guard in CollectionService:GetTagged(Tags.Guardian) do
		onGuard(guard)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Guardian):Connect(onGuard)

	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild(Tags.StateFolderName, 120)
		if state then
			state:GetAttributeChangedSignal(Tags.StateAttributes.HeavenSide):Connect(function()
				for guard in guardInfo do
					dressGuard(guard)
				end
			end)
		end
	end)
end

return PetVisualService
