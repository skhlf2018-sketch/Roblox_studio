--!strict
--[[
	PlantVisualService — 6판 "씨앗을 훔치세요" 식물 겉모습 (서버가 만들어서 모두가 같은 모양을 봄). 선임 담당.

	정원 파트(자리·판정·이름표)는 BaseService(수석) 가 만듭니다. 여기서는 그 파트의 Attribute 를 읽어
	겉모습 모델만 "자식"으로 붙입니다 (원래 공 파트는 투명하게, 판정·이름표 Label 은 그대로).

	1) 자라는 씨앗 (태그 IncubatingEgg): 모델 "SeedVisual" — 단계 4 모양
	     씨앗(땅에 반쯤 묻힘, 처음 10%) → 새싹(떡잎 2장) → 줄기(잎 4장) → 봉오리(등급 색)
	     Attr Stage("sprout"/"stem"/"bud") + Progress/Required 로 고르고, 모양이 바뀔 때만 다시 만듦.
	2) 성체 식물 (태그 GardenPlant): 모델 "PlantVisual" — 절차적 식물 (Visuals.plantLook: 구역 테마 + 이름 낱말 + id 해시)
	     모양 19종(PLANT_FORMS, 7판 circuit·blocky·glitch 추가) · 등급별 크기·받침 고리 색 · 크기 등급(Size) · 돌연변이 색(Visuals.mutationLooks)
	     열매 파트 Fruit1~FruitMax 를 미리 만들고 Attr Fruits 개수만큼만 보임 (바뀌면 Transparency 만 바꿈).
	3) 둥지 옆 장식 식물 (태그 ParentAnimalSpot 자리 → 모델 태그 ParentAnimal): 그 구역 식물 작게 + 이름표.
	4) ReplicatedStorage.PetModels: 식물 158종 (7판) 모델 (크기 1, 아우라 없음, 열매 3개) → 클라 UI 뷰포트 (PetViewport)

	모델 구조: PrimaryPart "Root"(Anchored, 바닥 가운데) + 나머지 파트는 Root 에 WeldConstraint (Anchored = false).
	  CanCollide/CanTouch/CanQuery = false. 모델 Attr Sway = true (클라가 가까운 식물만 Root 를 살짝 흔듦),
	  Height = 꼭대기 높이(스터드). 정원 파트에는 Attr VisualHeight (파트 바닥 기준 모델 꼭대기 높이) — 클라 팝업·프롬프트용.
	아우라 (addAura, Visuals.auras = Rarities.aura 16종, 7판 — code_rain · first_light · build_grid · ultra_halo · glitch_static 새로):
	  파티클·빛은 희귀(rare) 이상만 (원소 돌연변이 파티클은 등급 상관없이). 서버는 Enabled = false 로 만들고
	  그 파트에 태그 Visuals.Tags.AuraFx → 클라가 100 스터드 안 것만 켬. 고리(ring)는 고정 네온 파트,
	  beam 아우라(sky_pillar 슈퍼 · 7판 ultra_halo · glitch_static) 하늘 빛기둥(Beam "SkyPillar")은 항상 켜짐 (AuraFx 대상 아님).
	서버에서 매 프레임 루프 없음. 연결은 파트가 없어질 때 같이 끊김 (상태 표도 Destroying 때 지움).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Plants = require(Shared.Data.Plants)
local Biomes = require(Shared.Data.Biomes)
local Rarities = require(Shared.Data.Rarities)
local Visuals = require(Shared.Data.Visuals)
local Tags = require(Shared.Tags)

local PlantVisualService = {}
PlantVisualService.started = false

local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local FIRE_TEX = "rbxasset://textures/particles/fire_main.dds"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local DIRT = Color3.fromRGB(110, 78, 52)
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local FRUIT_MAX = 5

-- 등급 순서(1~16, 7판) → 크기. 11번 위로는 정원 칸을 넘지 않게 조금씩만 커짐
local RARITY_SCALE = { 1, 1.08, 1.16, 1.25, 1.35, 1.45, 1.55, 1.65, 1.75, 1.85, 2, 2.04, 2.08, 2.12, 2.16, 2.2 }
local SIZE_SCALE: { [string]: number } = { normal = 1, big = 1.15, huge = 1.3, giant = 1.5 }
local NATURAL: { [string]: boolean } = { silver = true, golden = true, rainbow = true }

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 180, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 255, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(90, 230, 120)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 110, 255)),
})
-- 7판 해커 글리치 (glitch_static): 분홍·초록이 뚝 끊기는 빛기둥·파티클 색
local GLITCH = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 200)),
	ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 0, 200)),
	ColorSequenceKeypoint.new(0.31, Color3.fromRGB(0, 255, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 255, 90)),
	ColorSequenceKeypoint.new(0.61, Color3.fromRGB(240, 240, 255)),
	ColorSequenceKeypoint.new(0.7, Color3.fromRGB(240, 240, 255)),
	ColorSequenceKeypoint.new(0.71, Color3.fromRGB(255, 0, 200)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 90)),
})
local GLITCH_PIXELS = {
	Color3.fromRGB(255, 0, 200),
	Color3.fromRGB(0, 255, 90),
	Color3.fromRGB(240, 240, 255),
	Color3.fromRGB(20, 12, 30),
}

local function rgb(c: Visuals.Color): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function rad(d: number): number
	return math.rad(d)
end

local function materialOf(name: string?): Enum.Material?
	if not name then
		return nil
	end
	local ok, value = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value :: any
	end
	return nil
end

local function split(text: string): { string }
	local result: { string } = {}
	for word in string.gmatch(text, "[^,%s]+") do
		table.insert(result, word)
	end
	return result
end

local function rarityOf(plantId: string): string
	local plant = Plants.get(plantId)
	return if plant then plant.rarity else "common"
end

local function rarityOrder(rarityId: string): number
	local r = Rarities.get(rarityId :: any)
	return if r then r.order else 1
end

local function rarityColor(rarityId: string): Color3
	local r = Rarities.get(rarityId :: any)
	return if r then rgb(r.color) else Color3.fromRGB(200, 200, 200)
end

local function auraIdOf(rarityId: string): string
	local r = Rarities.get(rarityId :: any)
	return if r then r.aura else "none"
end

------------------------------------------------------------------
-- 파트 만들기 (크기·자리는 크기 1 기준 → b.s 배)
------------------------------------------------------------------

type Builder = { model: Model, root: BasePart, s: number }

local function newBuilder(name: string, scale: number): Builder
	local model = Instance.new("Model")
	model.Name = name
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
	return { model = model, root = root, s = scale }
end

-- shape: "Ball" | "Block" | "Ell"(타원: Block + Sphere 메시) | "Cyl"(세운 원기둥, size = (지름, 높이, 지름)) | "Wedge"
local function piece(
	b: Builder,
	shape: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	name: string?
): Part
	local s = b.s
	local p = Instance.new("Part")
	p.Name = name or "Piece"
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Material = mat or SMOOTH
	local world = b.root.CFrame * CFrame.new(cf.Position * s) * cf.Rotation
	local sz = size * s
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * math.max(0.05, sz.X)
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(math.max(0.05, sz.Y), math.max(0.05, sz.X), math.max(0.05, sz.Z))
		world = world * CFrame.Angles(0, 0, math.pi / 2)
	elseif shape == "Wedge" then
		p.Shape = Enum.PartType.Wedge
		p.Size = Vector3.new(math.max(0.05, sz.X), math.max(0.05, sz.Y), math.max(0.05, sz.Z))
	else
		p.Size = Vector3.new(math.max(0.05, sz.X), math.max(0.05, sz.Y), math.max(0.05, sz.Z))
		if shape == "Ell" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
	end
	p.CFrame = world
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = b.root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = b.model
	return p
end

-- 고리 (작은 네온 막대 n 개를 둥글게): 가로(halo) 또는 세움(clock)
local function ring(b: Builder, center: CFrame, radius: number, color: Color3, n: number, name: string)
	for i = 1, n do
		local a = (i - 0.5) / n * math.pi * 2
		local seg = 2 * radius * math.sin(math.pi / n) * 1.08
		piece(
			b,
			"Block",
			Vector3.new(seg, 0.07, 0.07),
			center * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius),
			color,
			NEON,
			name
		)
	end
end

------------------------------------------------------------------
-- 아우라 (파티클·빛은 꺼진 채 + AuraFx 태그 → 클라가 가까운 것만 켬)
------------------------------------------------------------------

local function emitter(
	host: BasePart,
	kind: string,
	color: Color3?,
	rate: number,
	scale: number,
	name: string
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Texture = SPARKLE_TEX
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = rate
	e.Lifetime = NumberRange.new(1, 1.6)
	e.Speed = NumberRange.new(0.4, 1)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 * scale), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(color or WHITE)
	if kind == "flame" or kind == "fire" then
		e.Texture = FIRE_TEX
		e.LightEmission = 0.8
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(25, 25)
		e.Speed = NumberRange.new(0.6, 1.4)
		e.Acceleration = Vector3.new(0, 1.5 * scale, 0)
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55 * scale), NumberSequenceKeypoint.new(1, 0) })
	elseif kind == "spark" then
		e.Lifetime = NumberRange.new(0.15, 0.35)
		e.Speed = NumberRange.new(4 * scale, 7 * scale)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25 * scale), NumberSequenceKeypoint.new(1, 0) })
	elseif kind == "stars" then
		e.Lifetime = NumberRange.new(2, 3)
		e.Speed = NumberRange.new(0.2, 0.5)
		e.RotSpeed = NumberRange.new(-120, 120)
		e.Rotation = NumberRange.new(0, 360)
	elseif kind == "smoke" then
		e.Texture = SMOKE_TEX
		e.LightEmission = 0
		e.Lifetime = NumberRange.new(1.5, 2.5)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8 * scale),
			NumberSequenceKeypoint.new(1, 1.6 * scale),
		})
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Acceleration = Vector3.new(0, 0.6, 0)
	elseif kind == "rainbow" then
		e.Color = RAINBOW
	elseif kind == "snow" then
		e.LightEmission = 0.4
		e.Acceleration = Vector3.new(0, -1.2 * scale, 0)
		e.Lifetime = NumberRange.new(1.5, 2.2)
	elseif kind == "code" then
		-- 7판 해커 code_rain: 위로 살짝 튀었다가 길쭉한 초록 줄로 주르륵 떨어짐 (Squash = 세로로 늘임)
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(40, 40)
		e.Speed = NumberRange.new(1.5 * scale, 2.5 * scale)
		e.Acceleration = Vector3.new(0, -7 * scale, 0)
		e.Lifetime = NumberRange.new(0.8, 1.1)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2 * scale),
			NumberSequenceKeypoint.new(1, 0.08 * scale),
		})
		e.Squash = NumberSequence.new(2.5)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
	elseif kind == "motes" then
		-- 7판 오리지널 first_light: 태초의 금빛 먼지가 천천히 떠오름
		e.Lifetime = NumberRange.new(2.5, 3.5)
		e.Speed = NumberRange.new(0.1, 0.3)
		e.Acceleration = Vector3.new(0, 0.5 * scale, 0)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.28 * scale),
			NumberSequenceKeypoint.new(1, 0),
		})
	elseif kind == "grid" then
		-- 7판 개발자 build_grid: 제자리에서 반짝 켜졌다 꺼지는 파란 점 (움직이지 않음)
		e.Speed = NumberRange.new(0, 0)
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Rotation = NumberRange.new(45, 45)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3 * scale),
			NumberSequenceKeypoint.new(0.8, 0.3 * scale),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.SpreadAngle = Vector2.new(0, 0)
	elseif kind == "glitch" then
		-- 7판 해커 글리치 glitch_static: 아주 짧게 튀는 깨진 조각 (색이 분홍·초록으로 뚝 끊김, 모양도 찌그러짐)
		e.Color = GLITCH
		e.Lifetime = NumberRange.new(0.08, 0.22)
		e.Speed = NumberRange.new(3 * scale, 6 * scale)
		e.Size = NumberSequence.new(0.35 * scale)
		e.Squash = NumberSequence.new({
			NumberSequenceKeypoint.new(0, -1.5),
			NumberSequenceKeypoint.new(0.5, 2),
			NumberSequenceKeypoint.new(1, -1),
		})
	end
	e.Parent = host
	return e
end

export type AuraOptions = { mutations: { string }?, noBeam: boolean?, height: number? }

--[[
	host 파트에 등급 아우라 파티클·빛 (+ 원소 돌연변이 파티클)을 붙임. 만든 게 있으면 host 에 AuraFx 태그.
	  파티클/빛 = 희귀(rare) 이상만, 모두 Enabled = false (클라가 켬). beam 아우라 빛기둥은 Enabled = true.
	반환: 붙인 효과 수
]]
function PlantVisualService.addAura(host: BasePart, rarityId: string, scale: number, opts: AuraOptions?): number
	local o: AuraOptions = opts or {}
	local added = 0
	local look = Visuals.auras[auraIdOf(rarityId)]
	if look and rarityOrder(rarityId) >= 3 then
		local particle = look.particle
		if particle then
			emitter(host, particle, if look.color then rgb(look.color) else nil, look.rate or 3, scale, "Aura")
			added += 1
		end
		local lightColor = look.light
		if lightColor then
			local l = Instance.new("PointLight")
			l.Name = "AuraLight"
			l.Enabled = false
			l.Color = rgb(lightColor)
			l.Range = math.max(6, 8 * scale)
			l.Brightness = 1.1
			l.Parent = host
			added += 1
		end
		if look.beam and not o.noBeam then
			local a0 = Instance.new("Attachment")
			a0.Name = "PillarBottom"
			a0.Parent = host
			local a1 = Instance.new("Attachment")
			a1.Name = "PillarTop"
			a1.Position = Vector3.new(0, 300, 0)
			a1.Parent = host
			local beam = Instance.new("Beam")
			beam.Name = "SkyPillar"
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0 = math.max(2, 2.5 * scale)
			beam.Width1 = math.max(3, 4 * scale)
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Segments = 1
			beam.Color = if look.beamStyle == "glitch" then GLITCH else RAINBOW
			beam.Transparency =
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
			beam.Enabled = true
			beam.Parent = host
		end
	end
	local muts: { string } = o.mutations or {}
	for _, id in muts do
		local m = Visuals.mutationLooks[id]
		local effect = if m then m.effect else nil
		if m and effect then
			emitter(host, effect, rgb(m.color), 4, scale, "Mutation_" .. id)
			added += 1
		end
	end
	if added > 0 then
		CollectionService:AddTag(host, Visuals.Tags.AuraFx)
	end
	return added
end

-- 식물 모델 안 아우라: 보이지 않는 "Aura" 파트(가운데 높이) + 고정 고리
local function auraParts(b: Builder, rarityId: string, height: number, mutations: { string }, fx: boolean)
	local look: Visuals.AuraLook = Visuals.auras[auraIdOf(rarityId)] or {}
	local kind = look.ring
	local color = if look.ringColor then rgb(look.ringColor) else WHITE
	if kind == "ground" then
		piece(b, "Cyl", Vector3.new(1.75, 0.05, 1.75), CFrame.new(0, 0.02, 0), color, NEON, "AuraRing")
	elseif kind == "halo" then
		ring(b, CFrame.new(0, height * 0.55, 0), 1.0, color, 6, "AuraRing")
	elseif kind == "clock" then
		local c = CFrame.new(0, height * 0.6, 0.55) * CFrame.Angles(math.pi / 2, 0, 0)
		ring(b, c, 0.8, color, 6, "AuraRing")
		piece(
			b,
			"Block",
			Vector3.new(0.06, 0.55, 0.06),
			CFrame.new(0, height * 0.6 + 0.25, 0.55),
			color,
			NEON,
			"ClockHand"
		)
		piece(b, "Block", Vector3.new(0.38, 0.06, 0.06), CFrame.new(0.17, height * 0.6, 0.55), color, NEON, "ClockHand")
	elseif kind == "code" then
		-- 7판 해커: 식물 둘레에 세로로 흐르는 초록 코드 줄 6개 (길이·높이가 조금씩 다름, 반투명)
		for i = 1, 6 do
			local a = rad(i * 60 + 15)
			local len = height * (0.3 + (i % 3) * 0.12)
			local y = height * (0.25 + ((i * 7) % 5) * 0.08) + len / 2
			local bar = piece(
				b,
				"Block",
				Vector3.new(0.07, len, 0.07),
				CFrame.new(math.sin(a) * 1.0, y, math.cos(a) * 1.0),
				color,
				NEON,
				"AuraRing"
			)
			bar.Transparency = 0.35
		end
	elseif kind == "sun" then
		-- 7판 오리지널: 뒤에 세운 햇살 원판 + 빛살 6개 (태초의 금빛 햇살)
		local c = CFrame.new(0, height * 0.62, 0.6)
		local disc = piece(
			b,
			"Cyl",
			Vector3.new(1.3, 0.05, 1.3),
			c * CFrame.Angles(math.pi / 2, 0, 0),
			color:Lerp(WHITE, 0.3),
			NEON,
			"AuraRing"
		)
		disc.Transparency = 0.45
		for i = 1, 6 do
			local ray = piece(
				b,
				"Block",
				Vector3.new(0.08, 0.7, 0.04),
				c * CFrame.Angles(0, 0, rad(i * 60)) * CFrame.new(0, 0.95, 0),
				color,
				NEON,
				"AuraRing"
			)
			ray.Transparency = 0.2
		end
	elseif kind == "grid" then
		-- 7판 개발자: 파란 빛 격자 상자 (기둥 4 + 윗변 4, 반투명) — 스튜디오에서 고른 파트의 선택 상자처럼
		local w, h = 0.95, height * 1.02
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local post = piece(
					b,
					"Block",
					Vector3.new(0.06, h, 0.06),
					CFrame.new(sx * w, h / 2, sz * w),
					color,
					NEON,
					"AuraRing"
				)
				post.Transparency = 0.3
			end
		end
		for i = 0, 3 do
			local edge = piece(
				b,
				"Block",
				Vector3.new(w * 2, 0.06, 0.06),
				CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, h, w),
				color,
				NEON,
				"AuraRing"
			)
			edge.Transparency = 0.3
		end
	elseif kind == "double" then
		-- 7판 울트라디바인: 흰 후광 + 위에 무지개 후광 (두 겹)
		ring(b, CFrame.new(0, height * 0.55, 0), 1.0, color, 6, "AuraRing")
		local hues = {
			{ 255, 90, 90 },
			{ 255, 200, 70 },
			{ 120, 235, 110 },
			{ 80, 190, 255 },
			{ 170, 110, 255 },
			{ 255, 120, 220 },
		}
		for i = 1, 6 do
			local a = (i - 0.5) / 6 * math.pi * 2
			local r = 1.3
			piece(
				b,
				"Block",
				Vector3.new(2 * r * math.sin(math.pi / 6) * 1.08, 0.07, 0.07),
				CFrame.new(0, height * 0.82, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r),
				rgb(hues[i]),
				NEON,
				"AuraRing"
			)
		end
	elseif kind == "pixels" then
		-- 7판 해커 글리치: 둘레에 떠 있는 깨진 픽셀 6개 (Attr Glitch + EggShell 태그 → 클라가 색을 뚝뚝 바꿈)
		for i = 1, 6 do
			local a = rad(i * 60 + (i % 2) * 25)
			local r = 0.8 + (i % 3) * 0.25
			local px = piece(
				b,
				"Block",
				Vector3.one * (0.16 + (i % 2) * 0.08),
				CFrame.new(math.sin(a) * r, height * (0.2 + ((i * 3) % 5) * 0.17), math.cos(a) * r),
				GLITCH_PIXELS[(i - 1) % #GLITCH_PIXELS + 1],
				NEON,
				"AuraRing"
			)
			px:SetAttribute("Glitch", true)
			CollectionService:AddTag(px, Visuals.Tags.EggShell)
		end
	end
	if not fx then
		return
	end
	local host = piece(b, "Block", Vector3.one * 0.2, CFrame.new(0, height * 0.55, 0), WHITE, SMOOTH, "Aura")
	host.Transparency = 1
	if PlantVisualService.addAura(host, rarityId, b.s, { mutations = mutations }) == 0 then
		host:Destroy()
	end
end

------------------------------------------------------------------
-- 식물 모양 19종 (7판: 맨 아래 circuit·blocky·glitch) (크기 1: 키 약 3 × tall). 각 함수가 열매 자리(최대 5개)를 돌려줌
------------------------------------------------------------------

type Paint = {
	leaf: Color3,
	stem: Color3,
	petal: Color3,
	center: Color3,
	petalMat: Enum.Material,
	centerMat: Enum.Material,
	look: Visuals.PlantLook,
	H: number,
	petalParts: { BasePart },
}

type Form = (b: Builder, p: Paint) -> ({ CFrame }, number)

local function petal(b: Builder, p: Paint, shape: string, size: Vector3, cf: CFrame): BasePart
	local part = piece(b, shape, size, cf, p.petal, p.petalMat, "Petal")
	table.insert(p.petalParts, part)
	return part
end

local function stem(b: Builder, p: Paint, d: number, len: number, y0: number)
	piece(b, "Cyl", Vector3.new(d, len, d), CFrame.new(0, y0 + len / 2, 0), p.stem, SMOOTH, "Stem")
end

local function leaves(b: Builder, p: Paint, n: number, y0: number, y1: number, len: number)
	for i = 1, n do
		local t = if n > 1 then (i - 1) / (n - 1) else 0.5
		local a = i * 137.5 + p.look.twist
		local y = y0 + (y1 - y0) * t
		piece(
			b,
			"Ell",
			Vector3.new(len * 0.42, 0.08, len),
			CFrame.Angles(0, rad(a), 0) * CFrame.new(0, y, -len * 0.45) * CFrame.Angles(rad(22), 0, 0),
			p.leaf,
			SMOOTH,
			"Leaf"
		)
	end
end

-- 줄기 둘레 열매 자리 (높이 y0~y1, 반지름 r)
local function aroundSpots(y0: number, y1: number, r: number, twist: number): { CFrame }
	local spots: { CFrame } = {}
	for k = 1, FRUIT_MAX do
		local a = rad(twist + k * 72)
		local y = y0 + (y1 - y0) * ((k - 1) / (FRUIT_MAX - 1))
		table.insert(spots, CFrame.new(math.sin(a) * r, y, math.cos(a) * r))
	end
	return spots
end

local FORMS: { [string]: Form } = {}

FORMS.flower = function(b, p)
	local H = p.H
	stem(b, p, 0.16, H * 0.72, 0)
	leaves(b, p, p.look.leaves, H * 0.15, H * 0.4, 0.8)
	local head = CFrame.new(0, H * 0.75, 0) * CFrame.Angles(rad(-35), 0, 0)
	piece(b, "Ell", Vector3.new(0.55, 0.22, 0.55), head, p.center, p.centerMat, "Center")
	local n = p.look.petals
	for i = 1, n do
		petal(
			b,
			p,
			"Ell",
			Vector3.new(0.32, 0.09, 0.62),
			head * CFrame.Angles(0, (i / n) * math.pi * 2, 0) * CFrame.new(0, 0, -0.42)
		)
	end
	return aroundSpots(H * 0.3, H * 0.58, 0.42, p.look.twist), H * 0.75 + 0.45
end

FORMS.cup = function(b, p)
	local H = p.H
	stem(b, p, 0.14, H * 0.7, 0)
	leaves(b, p, p.look.leaves, H * 0.12, H * 0.35, 0.9)
	local y = H * 0.78
	local n = math.max(3, p.look.petals - 3)
	for i = 1, n do
		local a = i / n * math.pi * 2
		petal(
			b,
			p,
			"Ell",
			Vector3.new(0.34, 0.75, 0.2),
			CFrame.new(0, y, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.15) * CFrame.Angles(rad(-14), 0, 0)
		)
	end
	piece(b, "Ball", Vector3.one * 0.2, CFrame.new(0, y + 0.1, 0), p.center, p.centerMat, "Center")
	return aroundSpots(H * 0.28, H * 0.55, 0.38, p.look.twist), y + 0.4
end

FORMS.rose = function(b, p)
	local H = p.H
	stem(b, p, 0.14, H * 0.72, 0)
	leaves(b, p, p.look.leaves, H * 0.15, H * 0.45, 0.7)
	local y = H * 0.8
	piece(b, "Ball", Vector3.one * 0.5, CFrame.new(0, y, 0), p.petal:Lerp(BLACK, 0.12), p.petalMat, "Center")
	local n = p.look.petals
	for i = 1, n do
		local a = i / n * math.pi * 2
		petal(
			b,
			p,
			"Ell",
			Vector3.new(0.45, 0.42, 0.18),
			CFrame.new(0, y - 0.04, 0)
				* CFrame.Angles(0, a, 0)
				* CFrame.new(0, 0, -0.25)
				* CFrame.Angles(rad(-20), 0, 0)
		)
	end
	return aroundSpots(H * 0.3, H * 0.6, 0.38, p.look.twist), y + 0.35
end

FORMS.tree = function(b, p)
	local H = p.H
	piece(b, "Cyl", Vector3.new(0.42, H * 0.6, 0.42), CFrame.new(0, H * 0.3, 0), p.stem, Enum.Material.Wood, "Trunk")
	local cy = H * 0.78
	piece(b, "Ball", Vector3.one * 1.6, CFrame.new(0, cy, 0), p.leaf, SMOOTH, "Canopy")
	piece(b, "Ball", Vector3.one * 1.1, CFrame.new(0.7, cy - 0.25, 0.2), p.leaf:Lerp(BLACK, 0.08), SMOOTH, "Canopy")
	piece(b, "Ball", Vector3.one * 1.05, CFrame.new(-0.65, cy - 0.2, -0.25), p.leaf:Lerp(WHITE, 0.06), SMOOTH, "Canopy")
	for i = 1, 3 do
		local a = rad(p.look.twist + i * 120)
		petal(b, p, "Ball", Vector3.one * 0.32, CFrame.new(math.sin(a) * 0.7, cy + 0.45, math.cos(a) * 0.7))
	end
	local spots: { CFrame } = {}
	for k = 1, FRUIT_MAX do
		local a = rad(p.look.twist + 40 + k * 72)
		table.insert(spots, CFrame.new(math.sin(a) * 0.85, cy - 0.45 + (k % 2) * 0.3, math.cos(a) * 0.85))
	end
	return spots, cy + 0.85
end

FORMS.pine = function(b, p)
	local H = p.H
	piece(b, "Cyl", Vector3.new(0.3, H * 0.4, 0.3), CFrame.new(0, H * 0.2, 0), p.stem, Enum.Material.Wood, "Trunk")
	local tiers = { { 1.7, 0.42 }, { 1.3, 0.62 }, { 0.85, 0.8 } }
	for _, t in tiers do
		piece(b, "Ell", Vector3.new(t[1], 0.75, t[1]), CFrame.new(0, H * t[2], 0), p.leaf, SMOOTH, "Tier")
	end
	petal(b, p, "Ball", Vector3.one * 0.35, CFrame.new(0, H * 0.8 + 0.42, 0))
	local spots: { CFrame } = {}
	for k = 1, FRUIT_MAX do
		local a = rad(p.look.twist + k * 72)
		local t = tiers[(k - 1) % 2 + 1]
		table.insert(spots, CFrame.new(math.sin(a) * t[1] * 0.42, H * t[2] - 0.2, math.cos(a) * t[1] * 0.42))
	end
	return spots, H * 0.8 + 0.6
end

FORMS.palm = function(b, p)
	local H = p.H
	for i = 0, 2 do
		piece(
			b,
			"Cyl",
			Vector3.new(0.32 - i * 0.04, H * 0.27, 0.32 - i * 0.04),
			CFrame.new(i * 0.08, H * (0.13 + i * 0.26), 0) * CFrame.Angles(0, 0, rad(-6)),
			p.stem,
			Enum.Material.Wood,
			"Trunk"
		)
	end
	local top = H * 0.8
	local n = p.look.petals
	for i = 1, n do
		piece(
			b,
			"Ell",
			Vector3.new(0.35, 0.07, 1.5),
			CFrame.new(0.24, top, 0)
				* CFrame.Angles(0, i / n * math.pi * 2, 0)
				* CFrame.new(0, -0.15, -0.7)
				* CFrame.Angles(rad(-18), 0, 0),
			p.leaf,
			SMOOTH,
			"Frond"
		)
	end
	petal(b, p, "Ball", Vector3.one * 0.3, CFrame.new(0.24, top + 0.12, 0))
	local spots: { CFrame } = {}
	for k = 1, FRUIT_MAX do
		local a = rad(p.look.twist + k * 72)
		table.insert(spots, CFrame.new(0.24 + math.sin(a) * 0.3, top - 0.25, math.cos(a) * 0.3))
	end
	return spots, top + 0.3
end

FORMS.cactus = function(b, p)
	local H = p.H
	local h = H * 0.75
	piece(b, "Cyl", Vector3.new(0.7, h, 0.7), CFrame.new(0, h / 2, 0), p.leaf, SMOOTH, "Body")
	piece(b, "Ball", Vector3.one * 0.7, CFrame.new(0, h, 0), p.leaf, SMOOTH, "Body")
	for _, side in { -1, 1 } do
		local y = h * (if side < 0 then 0.45 else 0.6)
		piece(
			b,
			"Cyl",
			Vector3.new(0.3, 0.55, 0.3),
			CFrame.new(side * 0.5, y, 0) * CFrame.Angles(0, 0, rad(90)),
			p.leaf,
			SMOOTH,
			"Arm"
		)
		piece(b, "Cyl", Vector3.new(0.3, 0.6, 0.3), CFrame.new(side * 0.75, y + 0.3, 0), p.leaf, SMOOTH, "Arm")
		piece(b, "Ball", Vector3.one * 0.3, CFrame.new(side * 0.75, y + 0.6, 0), p.leaf, SMOOTH, "Arm")
	end
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + rad(p.look.twist)
		petal(
			b,
			p,
			"Ell",
			Vector3.new(0.18, 0.1, 0.32),
			CFrame.new(0, h + 0.33, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.14)
		)
	end
	piece(b, "Ball", Vector3.one * 0.16, CFrame.new(0, h + 0.38, 0), p.center, p.centerMat, "Center")
	local spots: { CFrame } = {}
	for k = 1, FRUIT_MAX do
		local a = rad(p.look.twist + k * 72)
		table.insert(spots, CFrame.new(math.sin(a) * 0.38, h * (0.35 + 0.12 * (k % 3)), math.cos(a) * 0.38))
	end
	return spots, h + 0.45
end

FORMS.mushroom = function(b, p)
	local H = p.H
	local h = H * 0.5
	piece(b, "Cyl", Vector3.new(0.45, h, 0.45), CFrame.new(0, h / 2, 0), p.stem:Lerp(WHITE, 0.55), SMOOTH, "Stem")
	petal(b, p, "Ell", Vector3.new(1.8, 0.8, 1.8), CFrame.new(0, h + 0.12, 0))
	for i = 1, 3 do
		local a = rad(p.look.twist + i * 120)
		piece(
			b,
			"Ball",
			Vector3.one * 0.28,
			CFrame.new(math.sin(a) * 0.5, h + 0.42, math.cos(a) * 0.5),
			p.center,
			p.centerMat,
			"Spot"
		)
	end
	-- 옆 작은 버섯
	piece(b, "Cyl", Vector3.new(0.2, 0.4, 0.2), CFrame.new(0.65, 0.2, 0.3), p.stem:Lerp(WHITE, 0.55), SMOOTH, "Stem")
	petal(b, p, "Ell", Vector3.new(0.6, 0.3, 0.6), CFrame.new(0.65, 0.42, 0.3))
	local spots: { CFrame } = {}
	for k = 1, FRUIT_MAX do
		local a = rad(p.look.twist + 20 + k * 72)
		table.insert(spots, CFrame.new(math.sin(a) * 0.78, h - 0.15, math.cos(a) * 0.78))
	end
	return spots, h + 0.55
end

FORMS.lotus = function(b, p)
	piece(b, "Cyl", Vector3.new(1.9, 0.06, 1.9), CFrame.new(0, 0.12, 0), p.leaf, SMOOTH, "Pad")
	piece(b, "Cyl", Vector3.new(0.9, 0.06, 0.9), CFrame.new(0.95, 0.1, 0.55), p.leaf:Lerp(WHITE, 0.1), SMOOTH, "Pad")
	stem(b, p, 0.12, p.H * 0.25, 0.12)
	local y = p.H * 0.25 + 0.25
	local n = p.look.petals
	for i = 1, n do
		local a = i / n * math.pi * 2
		petal(
			b,
			p,
			"Ell",
			Vector3.new(0.32, 0.6, 0.16),
			CFrame.new(0, y, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.25) * CFrame.Angles(rad(-28), 0, 0)
		)
	end
	piece(b, "Ball", Vector3.one * 0.3, CFrame.new(0, y, 0), p.center, p.centerMat, "Center")
	local spots: { CFrame } = {}
	for k = 1, FRUIT_MAX do
		local a = rad(p.look.twist + k * 72)
		table.insert(spots, CFrame.new(math.sin(a) * 0.65, 0.3, math.cos(a) * 0.65))
	end
	return spots, y + 0.45
end

FORMS.reed = function(b, p)
	local H = p.H
	local n = math.max(4, p.look.petals - 2)
	for i = 1, n do
		local a = rad(p.look.twist + i * (360 / n))
		local h = H * (0.65 + 0.07 * (i % 3))
		piece(
			b,
			"Ell",
			Vector3.new(0.14, h, 0.22),
			CFrame.new(math.sin(a) * 0.2, h / 2, math.cos(a) * 0.2)
				* CFrame.Angles(math.cos(a) * rad(10), 0, -math.sin(a) * rad(10)),
			p.leaf,
			SMOOTH,
			"Blade"
		)
	end
	petal(b, p, "Ell", Vector3.new(0.2, 0.55, 0.2), CFrame.new(0.05, H * 0.85, 0.05))
	petal(b, p, "Ell", Vector3.new(0.18, 0.45, 0.18), CFrame.new(-0.25, H * 0.72, -0.1))
	return aroundSpots(H * 0.3, H * 0.55, 0.3, p.look.twist), H * 0.85 + 0.3
end

FORMS.vine = function(b, p)
	local H = p.H
	stem(b, p, 0.1, H * 0.9, 0)
	local n = 6
	for i = 1, n do
		local t = i / n
		local a = rad(p.look.twist + i * 70)
		piece(
			b,
			"Ell",
			Vector3.new(0.4, 0.08, 0.55),
			CFrame.new(math.sin(a) * 0.28, H * 0.9 * t, math.cos(a) * 0.28) * CFrame.Angles(0, a, rad(20)),
			p.leaf,
			SMOOTH,
			"Leaf"
		)
	end
	for i = 1, 2 do
		local a = rad(p.look.twist + i * 160)
		petal(b, p, "Ball", Vector3.one * 0.38, CFrame.new(math.sin(a) * 0.35, H * (0.5 + 0.3 * i), math.cos(a) * 0.35))
	end
	return aroundSpots(H * 0.25, H * 0.7, 0.42, p.look.twist + 30), H * 0.9 + 0.2
end

FORMS.fern = function(b, p)
	local H = p.H
	local n = p.look.petals
	for i = 1, n do
		local a = i / n * math.pi * 2 + rad(p.look.twist)
		piece(
			b,
			"Ell",
			Vector3.new(0.32, 0.07, H * 0.5),
			CFrame.Angles(0, a, 0) * CFrame.new(0, H * 0.18, -H * 0.2) * CFrame.Angles(rad(38), 0, 0),
			p.leaf,
			SMOOTH,
			"Frond"
		)
	end
	petal(b, p, "Ball", Vector3.one * 0.32, CFrame.new(0, H * 0.4, 0))
	piece(b, "Cyl", Vector3.new(0.12, H * 0.4, 0.12), CFrame.new(0, H * 0.2, 0), p.stem, SMOOTH, "Stem")
	return aroundSpots(H * 0.2, H * 0.4, 0.5, p.look.twist), H * 0.5
end

FORMS.gourd = function(b, p)
	for i = 1, 3 do
		local a = rad(p.look.twist + i * 120)
		piece(
			b,
			"Ell",
			Vector3.new(0.9, 0.1, 1.0),
			CFrame.Angles(0, a, 0) * CFrame.new(0, 0.18, -0.45) * CFrame.Angles(rad(12), 0, 0),
			p.leaf,
			SMOOTH,
			"Leaf"
		)
	end
	stem(b, p, 0.14, p.H * 0.45, 0)
	piece(
		b,
		"Ell",
		Vector3.new(0.7, 0.08, 0.7),
		CFrame.new(0, p.H * 0.45, 0) * CFrame.Angles(rad(-15), 0, 0),
		p.leaf,
		SMOOTH,
		"Leaf"
	)
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		petal(
			b,
			p,
			"Ell",
			Vector3.new(0.2, 0.08, 0.36),
			CFrame.new(0, p.H * 0.5, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.18)
		)
	end
	local spots: { CFrame } = {}
	for k = 1, FRUIT_MAX do
		local a = rad(p.look.twist + 60 + k * 72)
		table.insert(spots, CFrame.new(math.sin(a) * 0.75, 0.28, math.cos(a) * 0.75))
	end
	return spots, p.H * 0.5 + 0.15
end

FORMS.coral = function(b, p)
	local H = p.H
	local n = math.max(4, p.look.petals - 2)
	for i = 1, n do
		local a = rad(p.look.twist + i * (360 / n))
		local h = H * (0.5 + 0.08 * (i % 3))
		local cf = CFrame.Angles(0, a, 0) * CFrame.new(0, h / 2, -0.15) * CFrame.Angles(rad(-18), 0, 0)
		petal(b, p, "Cyl", Vector3.new(0.22, h, 0.22), cf)
		piece(b, "Ball", Vector3.one * 0.3, cf * CFrame.new(0, h / 2, 0), p.center, p.centerMat, "Tip")
	end
	return aroundSpots(H * 0.2, H * 0.45, 0.45, p.look.twist + 36), H * 0.62
end

FORMS.crystal = function(b, p)
	local H = p.H
	piece(
		b,
		"Ell",
		Vector3.new(1.2, 0.4, 1.2),
		CFrame.new(0, 0.15, 0),
		Color3.fromRGB(120, 115, 125),
		Enum.Material.Slate,
		"Rock"
	)
	local n = math.max(4, p.look.petals - 2)
	for i = 1, n do
		local a = rad(p.look.twist + i * (360 / n))
		local h = if i == 1 then H * 0.75 else H * (0.35 + 0.08 * (i % 3))
		local cf = if i == 1
			then CFrame.new(0, h / 2, 0)
			else CFrame.Angles(0, a, 0) * CFrame.new(0, h / 2, -0.25) * CFrame.Angles(rad(-22), 0, 0)
		local c = petal(b, p, "Block", Vector3.new(0.32, h, 0.32), cf * CFrame.Angles(0, rad(45), 0))
		c.Material = if p.petalMat == SMOOTH then Enum.Material.Glass else p.petalMat
		c.Transparency = if c.Material == Enum.Material.Glass then 0.2 else 0
	end
	return aroundSpots(H * 0.2, H * 0.45, 0.6, p.look.twist), H * 0.75 + 0.05
end

FORMS.candy = function(b, p)
	local H = p.H
	piece(b, "Cyl", Vector3.new(0.12, H * 0.7, 0.12), CFrame.new(0, H * 0.35, 0), WHITE, SMOOTH, "Stick")
	leaves(b, p, 2, H * 0.15, H * 0.25, 0.7)
	local y = H * 0.78
	petal(b, p, "Cyl", Vector3.new(1.15, 0.18, 1.15), CFrame.new(0, y, 0) * CFrame.Angles(math.pi / 2, 0, 0))
	piece(
		b,
		"Cyl",
		Vector3.new(0.75, 0.2, 0.75),
		CFrame.new(0, y, -0.01) * CFrame.Angles(math.pi / 2, 0, 0),
		WHITE,
		SMOOTH,
		"Swirl"
	)
	piece(
		b,
		"Cyl",
		Vector3.new(0.38, 0.22, 0.38),
		CFrame.new(0, y, -0.02) * CFrame.Angles(math.pi / 2, 0, 0),
		p.center,
		p.centerMat,
		"Center"
	)
	return aroundSpots(H * 0.25, H * 0.5, 0.42, p.look.twist), y + 0.6
end

-- 7판 해커 연구소: 회로 식물 — 네모 줄기 + 빛나는 회로 줄 + 네모 칩 잎 + 꼭대기 칩(가운데 네온) + 핀(꽃잎)
FORMS.circuit = function(b, p)
	local H = p.H
	piece(b, "Block", Vector3.new(0.22, H * 0.74, 0.22), CFrame.new(0, H * 0.37, 0), p.stem, SMOOTH, "Stem")
	piece(b, "Block", Vector3.new(0.05, H * 0.6, 0.24), CFrame.new(0, H * 0.33, 0), p.center, NEON, "Trace")
	for i = 1, p.look.leaves do
		local a = rad(p.look.twist + i * 125)
		local y = H * (0.2 + i * 0.13)
		local chip = CFrame.Angles(0, a, 0) * CFrame.new(0, y, -0.42) * CFrame.Angles(rad(12), 0, 0)
		piece(b, "Block", Vector3.new(0.5, 0.06, 0.5), chip, p.leaf, SMOOTH, "Leaf")
		piece(b, "Block", Vector3.new(0.3, 0.07, 0.06), chip * CFrame.new(0, 0.01, 0.1), p.center, NEON, "Trace")
	end
	local y = H * 0.78
	piece(b, "Block", Vector3.new(0.72, 0.2, 0.72), CFrame.new(0, y, 0), p.stem:Lerp(BLACK, 0.3), SMOOTH, "Chip")
	piece(b, "Block", Vector3.new(0.34, 0.22, 0.34), CFrame.new(0, y + 0.01, 0), p.center, NEON, "Center")
	local n = p.look.petals
	for i = 1, n do
		local a = i / n * math.pi * 2
		petal(
			b,
			p,
			"Block",
			Vector3.new(0.09, 0.09, 0.28),
			CFrame.new(0, y, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.48)
		)
	end
	return aroundSpots(H * 0.28, H * 0.58, 0.45, p.look.twist), y + 0.3
end

-- 7판 개발자의 방: 블록 식물 — 스터드 박힌 블록을 쌓은 줄기 + 네모 잎 + 꼭대기 큰 블록 + 둘레 작은 블록(꽃잎)
FORMS.blocky = function(b, p)
	local H = p.H
	local function studs(part: BasePart)
		part.TopSurface = Enum.SurfaceType.Studs
		part.BottomSurface = Enum.SurfaceType.Inlet
		part.Material = Enum.Material.Plastic
	end
	local seg = H * 0.24
	for i = 0, 2 do
		local c = if i % 2 == 0 then p.stem else p.stem:Lerp(WHITE, 0.15)
		studs(piece(b, "Block", Vector3.new(0.42, seg, 0.42), CFrame.new(0, seg * (i + 0.5), 0), c, SMOOTH, "Stem"))
	end
	for i = 1, p.look.leaves do
		local a = rad(p.look.twist + i * 140)
		local y = H * (0.18 + i * 0.14)
		studs(
			piece(
				b,
				"Block",
				Vector3.new(0.3, 0.16, 0.62),
				CFrame.Angles(0, a, 0) * CFrame.new(0, y, -0.45),
				p.leaf,
				SMOOTH,
				"Leaf"
			)
		)
	end
	local y = H * 0.72 + 0.3
	studs(piece(b, "Block", Vector3.new(0.62, 0.62, 0.62), CFrame.new(0, y, 0), p.center, SMOOTH, "Center"))
	local n = math.min(5, p.look.petals - 2)
	for i = 1, n do
		local a = i / n * math.pi * 2 + rad(p.look.twist)
		local cube = petal(
			b,
			p,
			"Block",
			Vector3.one * 0.34,
			CFrame.new(0, y - 0.05, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.48)
		)
		studs(cube)
	end
	return aroundSpots(H * 0.22, H * 0.55, 0.42, p.look.twist), y + 0.42
end

-- 7판 버그 차원: 거꾸로 깨진 식물 — 잎 덩어리가 바닥에, 줄기가 위로, 뿌리가 하늘로 + 둘레에 떠 있는 깨진 픽셀(꽃잎).
--   꽃잎 픽셀은 Attr Glitch + EggShell 태그 → 클라가 색을 뚝뚝 바꿈 (실버·황금·무지개 돌연변이면 build 가 Glitch 를 지움)
FORMS.glitch = function(b, p)
	local H = p.H
	piece(b, "Ball", Vector3.one * 1.15, CFrame.new(0, H * 0.22, 0), p.leaf, SMOOTH, "Canopy")
	piece(b, "Ball", Vector3.one * 0.75, CFrame.new(0.45, H * 0.16, 0.25), p.leaf:Lerp(BLACK, 0.15), SMOOTH, "Canopy")
	piece(b, "Cyl", Vector3.new(0.26, H * 0.5, 0.26), CFrame.new(0, H * 0.55, 0), p.stem, SMOOTH, "Trunk")
	for i = 1, 3 do
		local a = rad(p.look.twist + i * 120)
		piece(
			b,
			"Cyl",
			Vector3.new(0.1, 0.6, 0.1),
			CFrame.new(0, H * 0.82, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(rad(35), 0, 0) * CFrame.new(0, 0.28, 0),
			p.stem,
			SMOOTH,
			"Root"
		)
	end
	-- 줄기 한가운데가 옆으로 밀린 "깨진" 조각 (화면이 찢어진 것처럼)
	piece(b, "Block", Vector3.new(0.34, 0.16, 0.34), CFrame.new(0.14, H * 0.6, 0), p.center, NEON, "Center")
	local n = p.look.petals
	for i = 1, n do
		local a = rad(p.look.twist + i * (360 / n))
		local r = 0.55 + (i % 3) * 0.18
		local px = petal(
			b,
			p,
			"Block",
			Vector3.one * (0.16 + (i % 2) * 0.1),
			CFrame.new(math.sin(a) * r, H * (0.3 + ((i * 5) % 7) * 0.08), math.cos(a) * r)
		)
		px.Material = NEON
		px:SetAttribute("Glitch", true)
		CollectionService:AddTag(px, Visuals.Tags.EggShell)
	end
	return aroundSpots(H * 0.12, H * 0.32, 0.7, p.look.twist), H * 0.82 + 0.55
end

------------------------------------------------------------------
-- 성체 식물 모델
------------------------------------------------------------------

export type BuildOptions = {
	size: string?, -- 크기 등급 id (보통·큼·거대·초거대)
	mutations: { string }?,
	fx: boolean?, -- 아우라 파티클·빛 (기본 true)
	fruits: number?, -- 처음에 보이는 열매 수 (기본 0)
	scale: number?, -- 전체 배율 (기본 1)
}

local function fruitPiece(
	b: Builder,
	shape: string,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material,
	size: number,
	i: number
): Part
	local name = "Fruit" .. i
	if shape == "oval" then
		return piece(b, "Ell", Vector3.new(0.28, 0.38, 0.28) * size, cf, color, mat, name)
	elseif shape == "long" then
		return piece(b, "Ell", Vector3.new(0.18, 0.5, 0.18) * size, cf, color, mat, name)
	elseif shape == "berry" then
		return piece(b, "Ball", Vector3.one * 0.24 * size, cf, color, mat, name)
	end
	return piece(b, "Ball", Vector3.one * 0.32 * size, cf, color, mat, name)
end

-- 보이는 열매 수 (Fruit1..n 만 보임)
function PlantVisualService.setFruits(model: Model, count: number)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 5) == "Fruit" then
			local i = tonumber(string.sub(d.Name, 6))
			if i then
				d.Transparency = if i <= count then 0 else 1
			end
		end
	end
	model:SetAttribute("Fruits", count)
end

function PlantVisualService.build(plantId: string, opts: BuildOptions?): Model
	local o: BuildOptions = opts or {}
	local look = Visuals.plantLook(plantId)
	local rarity = rarityOf(plantId)
	local order = rarityOrder(rarity)
	local scale = (o.scale or 1) * (RARITY_SCALE[order] or 1) * (SIZE_SCALE[o.size or "normal"] or 1)
	local b = newBuilder(plantId, scale)
	local mutations: { string } = o.mutations or {}

	local petalColor = rgb(look.petal)
	local petalMat = materialOf(look.petalMaterial) or SMOOTH
	local centerColor = rgb(look.center)
	local centerMat = if look.glow or order >= 6 then NEON else SMOOTH
	local fruitColor = rgb(look.fruit)
	local fruitMat = if look.glow then NEON else SMOOTH
	local rainbow = false
	local elemental = false
	local natural = false
	for _, id in mutations do
		local m = Visuals.mutationLooks[id]
		if m then
			local mat = materialOf(m.material) or SMOOTH
			if NATURAL[id] then
				petalColor, petalMat = rgb(m.color), mat
				natural = true
				centerColor = rgb(m.color):Lerp(WHITE, 0.35)
				rainbow = rainbow or m.cycle == true
			else
				fruitColor, fruitMat = rgb(m.color), mat
				if not elemental then
					petalColor = petalColor:Lerp(rgb(m.color), 0.45)
				end
				elemental = true
			end
		end
	end

	local paint: Paint = {
		leaf = rgb(look.leaf),
		stem = rgb(look.stem),
		petal = petalColor,
		center = centerColor,
		petalMat = petalMat,
		centerMat = centerMat,
		look = look,
		H = 3 * look.tall,
		petalParts = {},
	}
	-- 흙 둔덕 + 등급 색 받침 고리
	piece(b, "Ell", Vector3.new(1.3, 0.32, 1.3), CFrame.new(0, 0.05, 0), DIRT, Enum.Material.Ground, "Mound")
	piece(b, "Cyl", Vector3.new(1.5, 0.08, 1.5), CFrame.new(0, 0.03, 0), rarityColor(rarity), SMOOTH, "RarityRing")

	local form = FORMS[look.form] or FORMS.flower
	local spots, top = form(b, paint)
	local fruitSize = if look.form == "gourd" then 1.7 elseif look.form == "tree" then 1.1 else 1
	for i, cf in spots do
		local f = fruitPiece(b, look.fruitShape, cf, fruitColor, fruitMat, fruitSize, i)
		f.Transparency = 1
		if rainbow then
			CollectionService:AddTag(f, Visuals.Tags.EggShell)
			f:SetAttribute("Rainbow", true)
		end
	end
	if natural then
		for _, part in paint.petalParts do
			part:SetAttribute("Glitch", nil) -- 돌연변이 색이 보이게 (깨진 픽셀 깜빡임 끔)
		end
	end
	if rainbow then
		for _, part in paint.petalParts do
			CollectionService:AddTag(part, Visuals.Tags.EggShell)
			part:SetAttribute("Rainbow", true)
		end
	end
	if mutations[1] == "silver" then
		for _, part in paint.petalParts do
			part.Reflectance = 0.35
		end
	end
	auraParts(b, rarity, top, mutations, o.fx ~= false)
	PlantVisualService.setFruits(b.model, o.fruits or 0)
	b.model:SetAttribute("PetId", plantId)
	b.model:SetAttribute("Form", look.form)
	b.model:SetAttribute("Height", top * scale)
	b.model:SetAttribute("Sway", true)
	return b.model
end

------------------------------------------------------------------
-- 자라는 씨앗 단계 모양 ("seed" 씨앗 묻힘 · "sprout" 새싹 · "stem" 줄기 · "bud" 봉오리)
------------------------------------------------------------------

PlantVisualService.SEED_ONLY_FRACTION = 0.1 -- 새싹 단계 처음 10% 는 씨앗만 (땅에 반쯤 묻힘)

function PlantVisualService.visualStage(stage: string?, progress: number?, required: number?): string
	if stage == "bud" or stage == "stem" then
		return stage
	end
	local p = progress or 0
	local r = required or 1
	if r > 0 and p / r < PlantVisualService.SEED_ONLY_FRACTION then
		return "seed"
	end
	return "sprout"
end

function PlantVisualService.buildStage(plantId: string, stage: string, opts: BuildOptions?): Model
	local o: BuildOptions = opts or {}
	local look = Visuals.plantLook(plantId)
	local rarity = rarityOf(plantId)
	local b = newBuilder("SeedVisual", o.scale or 1)
	local tint = rarityColor(rarity)
	local leaf = rgb(look.leaf)
	local stemColor = leaf:Lerp(rgb(look.stem), 0.4)
	local shell = tint:Lerp(WHITE, 0.45)
	local stageMuts: { string } = o.mutations or {}
	for _, id in stageMuts do
		local m = Visuals.mutationLooks[id]
		if m and NATURAL[id] then
			shell = rgb(m.color)
		end
	end
	piece(b, "Ell", Vector3.new(1.5, 0.36, 1.5), CFrame.new(0, 0.06, 0), DIRT, Enum.Material.Ground, "Mound")
	piece(b, "Cyl", Vector3.new(1.65, 0.07, 1.65), CFrame.new(0, 0.03, 0), tint, SMOOTH, "RarityRing")
	local top = 0.3
	if stage == "seed" then
		piece(
			b,
			"Ell",
			Vector3.new(0.42, 0.6, 0.34),
			CFrame.new(0, 0.26, 0) * CFrame.Angles(0, 0, rad(30)),
			shell,
			SMOOTH,
			"Seed"
		)
		piece(
			b,
			"Ell",
			Vector3.new(0.08, 0.5, 0.36),
			CFrame.new(0.02, 0.27, 0) * CFrame.Angles(0, 0, rad(30)),
			tint,
			SMOOTH,
			"SeedStripe"
		)
		top = 0.52
	elseif stage == "sprout" then
		piece(
			b,
			"Ell",
			Vector3.new(0.3, 0.42, 0.26),
			CFrame.new(0.28, 0.2, 0.1) * CFrame.Angles(0, 0, rad(60)),
			shell,
			SMOOTH,
			"Seed"
		)
		piece(b, "Cyl", Vector3.new(0.08, 0.5, 0.08), CFrame.new(0, 0.4, 0), stemColor, SMOOTH, "Stem")
		for _, side in { -1, 1 } do
			piece(
				b,
				"Ell",
				Vector3.new(0.34, 0.06, 0.18),
				CFrame.new(side * 0.16, 0.66, 0) * CFrame.Angles(0, 0, rad(side * 22)),
				leaf,
				SMOOTH,
				"Leaf"
			)
		end
		top = 0.72
	elseif stage == "stem" then
		piece(b, "Cyl", Vector3.new(0.1, 1.1, 0.1), CFrame.new(0, 0.6, 0), stemColor, SMOOTH, "Stem")
		for i = 1, 4 do
			local a = rad(look.twist + i * 100)
			local y = 0.45 + (i % 2) * 0.4
			piece(
				b,
				"Ell",
				Vector3.new(0.22, 0.06, 0.5),
				CFrame.Angles(0, a, 0) * CFrame.new(0, y, -0.22) * CFrame.Angles(rad(25), 0, 0),
				leaf,
				SMOOTH,
				"Leaf"
			)
		end
		piece(b, "Ball", Vector3.one * 0.16, CFrame.new(0, 1.18, 0), leaf:Lerp(WHITE, 0.2), SMOOTH, "Tip")
		top = 1.26
	else -- bud
		piece(b, "Cyl", Vector3.new(0.12, 1.5, 0.12), CFrame.new(0, 0.8, 0), stemColor, SMOOTH, "Stem")
		for i = 1, 4 do
			local a = rad(look.twist + i * 90)
			local y = 0.4 + (i % 2) * 0.45
			piece(
				b,
				"Ell",
				Vector3.new(0.26, 0.06, 0.6),
				CFrame.Angles(0, a, 0) * CFrame.new(0, y, -0.26) * CFrame.Angles(rad(25), 0, 0),
				leaf,
				SMOOTH,
				"Leaf"
			)
		end
		local budColor = rgb(look.petal):Lerp(tint, 0.5)
		piece(b, "Ell", Vector3.new(0.34, 0.52, 0.34), CFrame.new(0, 1.75, 0), budColor, SMOOTH, "Bud")
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			piece(
				b,
				"Ell",
				Vector3.new(0.12, 0.3, 0.06),
				CFrame.new(0, 1.6, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.14) * CFrame.Angles(rad(-20), 0, 0),
				leaf,
				SMOOTH,
				"Sepal"
			)
		end
		top = 2.02
	end
	if o.fx ~= false then
		local host = piece(b, "Block", Vector3.one * 0.2, CFrame.new(0, top * 0.6, 0), WHITE, SMOOTH, "Aura")
		host.Transparency = 1
		if PlantVisualService.addAura(host, rarity, b.s, { mutations = o.mutations }) == 0 then
			host:Destroy()
		end
	end
	b.model:SetAttribute("PetId", plantId)
	b.model:SetAttribute("Stage", stage)
	b.model:SetAttribute("Height", top * b.s)
	b.model:SetAttribute("Sway", stage ~= "seed")
	return b.model
end

------------------------------------------------------------------
-- 정원 파트에 붙이기
------------------------------------------------------------------

local function stringAttr(inst: Instance, name: string): string
	local v = inst:GetAttribute(name)
	return if typeof(v) == "string" then v else ""
end

local function numberAttr(inst: Instance, name: string): number?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" then v else nil
end

-- 공 파트의 바닥 높이 (BaseService gardenBall: 메시 Scale.Y 만큼 키를 늘려 바닥에 붙임)
local function floorOf(part: BasePart): number
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	local hs = if mesh then mesh.Scale.Y else 1
	return part.CFrame.Position.Y - part.Size.Y * hs / 2
end

local function yawOf(uid: string): number
	return rad(Visuals.hash(uid) % 360)
end

-- 모델을 파트 바닥에 놓고, 파트 투명 + VisualHeight + 이름표(Label) 높이를 모델 위로
local function mount(part: BasePart, model: Model, uid: string)
	local floor = floorOf(part)
	local pos = part.CFrame.Position
	model:PivotTo(CFrame.new(pos.X, floor, pos.Z) * CFrame.Angles(0, yawOf(uid), 0))
	part.Transparency = 1
	local h = model:GetAttribute("Height")
	local height = if typeof(h) == "number" then h else 2
	part:SetAttribute("VisualHeight", height)
	local label = part:FindFirstChild("Label")
	if label and label:IsA("BillboardGui") then
		label.StudsOffsetWorldSpace = Vector3.new(0, floor + height + 1.4 - pos.Y, 0)
	end
	model.Parent = part
end

type SeedState = { key: string, model: Model? }
local seeds: { [BasePart]: SeedState } = {}

local function refreshSeed(part: BasePart)
	local state = seeds[part]
	if not state or part.Parent == nil then
		return
	end
	local petId = stringAttr(part, "PetId")
	if petId == "" then
		return
	end
	local stage = PlantVisualService.visualStage(
		stringAttr(part, "Stage"),
		numberAttr(part, "Progress"),
		numberAttr(part, "Required")
	)
	local mutations = stringAttr(part, "Mutations")
	local key = stage .. "|" .. mutations
	if state.key == key and state.model and state.model.Parent then
		return
	end
	if state.model then
		state.model:Destroy()
	end
	local d = math.min(part.Size.X, part.Size.Z)
	local model = PlantVisualService.buildStage(petId, stage, {
		scale = 2.4 * (d / 2) ^ 0.65,
		mutations = split(mutations),
		fx = true,
	})
	mount(part, model, stringAttr(part, "EggUid"))
	state.key = key
	state.model = model
end

local function onSeed(part: BasePart)
	if seeds[part] then
		return
	end
	seeds[part] = { key = "" }
	refreshSeed(part)
	local function refresh()
		refreshSeed(part)
	end
	part:GetAttributeChangedSignal("Stage"):Connect(refresh)
	part:GetAttributeChangedSignal("Progress"):Connect(refresh)
	part:GetAttributeChangedSignal("Mutations"):Connect(refresh)
	part.Destroying:Connect(function()
		seeds[part] = nil
	end)
end

type PlantState = { key: string, model: Model? }
local adults: { [BasePart]: PlantState } = {}

-- 정원 성체 크기: 공 파트 지름(크기 등급 반영) 기준
local GARDEN_SCALE = 1.35 -- 보통 크기 성체 배율 (공 지름 3.2). 큰 크기 등급은 (지름 / 3.2)^0.65 배 (초거대 약 1.8배)

local function refreshPlant(part: BasePart)
	local state = adults[part]
	if not state or part.Parent == nil then
		return
	end
	local petId = stringAttr(part, "PetId")
	if petId == "" then
		return
	end
	local mutations = stringAttr(part, "Mutations")
	local fruits = numberAttr(part, "Fruits") or 0
	if state.key == mutations and state.model and state.model.Parent then
		PlantVisualService.setFruits(state.model, fruits)
		return
	end
	if state.model then
		state.model:Destroy()
	end
	local d = math.min(part.Size.X, part.Size.Z)
	local model = PlantVisualService.build(petId, {
		scale = GARDEN_SCALE * (d / 3.2) ^ 0.65,
		mutations = split(mutations),
		fx = true,
		fruits = fruits,
	})
	mount(part, model, stringAttr(part, "PlantUid"))
	state.key = mutations
	state.model = model
end

local function onPlant(part: BasePart)
	if adults[part] then
		return
	end
	adults[part] = { key = "\0" }
	refreshPlant(part)
	local function refresh()
		refreshPlant(part)
	end
	part:GetAttributeChangedSignal("Fruits"):Connect(refresh)
	part:GetAttributeChangedSignal("Mutations"):Connect(refresh)
	part.Destroying:Connect(function()
		adults[part] = nil
	end)
end

-- 테스트·즉시 갱신용
PlantVisualService.refreshSeed = refreshSeed
PlantVisualService.refreshPlant = refreshPlant
PlantVisualService.attachSeed = onSeed
PlantVisualService.attachPlant = onPlant

------------------------------------------------------------------
-- 둥지 옆 장식 식물 (5판 부모 동물 자리)
------------------------------------------------------------------

local NEST_SCALE = 1.1
local nestModels: { [BasePart]: Model } = {}

local function currentSide(): string
	local state = ReplicatedStorage:FindFirstChild(Tags.StateFolderName)
	local side = if state then state:GetAttribute(Tags.StateAttributes.HeavenSide) else nil
	return if typeof(side) == "string" and side ~= "" then side else "light"
end

local function nestPlants(biomeId: string, side: string?): { Plants.Plant }
	local list: { Plants.Plant } = {}
	for _, p in Plants.inBiome(biomeId) do
		if p.source == "nest" and (p.side == nil or side == nil or p.side == side) then
			table.insert(list, p)
		end
	end
	return list
end

local function nameTag(adornee: BasePart, height: number, plant: Plants.Plant)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PetTag"
	gui.Size = UDim2.fromScale(4, 1.4)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1.1, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	gui.Adornee = adornee
	local r = Rarities.get(plant.rarity :: any)
	local function line(name: string, y: number, text: string, color: Color3)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, y)
		label.Size = UDim2.fromScale(1, 0.5)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeColor3 = BLACK
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = gui
	end
	line("Rarity", 0, if r then r.displayName else plant.rarity, rarityColor(plant.rarity))
	line("PetName", 0.5, plant.name, WHITE)
	gui.Parent = adornee
end

local function buildNestPlant(spot: BasePart)
	local old = nestModels[spot]
	if old then
		old:Destroy()
		nestModels[spot] = nil
	end
	if spot.Parent == nil then
		return
	end
	local biomeId = spot:GetAttribute("BiomeId")
	if typeof(biomeId) ~= "string" then
		return
	end
	local nestIndex = spot:GetAttribute("NestIndex")
	local index = if typeof(nestIndex) == "number" then nestIndex else 1
	local biome = Biomes.get(biomeId)
	local side = if biome and biome.sides then currentSide() else nil
	local list = nestPlants(biomeId, side)
	if #list == 0 then
		return
	end
	local plant = list[((index - 1) % #list) + 1]
	local model = PlantVisualService.build(plant.id, { scale = NEST_SCALE, fx = false, fruits = 2 })
	local ground = spot.CFrame.Position - Vector3.new(0, spot.Size.Y / 2, 0)
	model:PivotTo(CFrame.new(ground) * spot.CFrame.Rotation)
	local root = model.PrimaryPart
	local h = model:GetAttribute("Height")
	if root then
		nameTag(root, if typeof(h) == "number" then h else 3, plant)
	end
	model:SetAttribute("BiomeId", biomeId)
	CollectionService:AddTag(model, Visuals.Tags.ParentAnimal)
	model.Parent = spot.Parent
	nestModels[spot] = model
end

local function rebuildSidedNests()
	for _, inst in CollectionService:GetTagged(Tags.ParentAnimalSpot) do
		if inst:IsA("BasePart") then
			local biomeId = inst:GetAttribute("BiomeId")
			local biome = if typeof(biomeId) == "string" then Biomes.get(biomeId) else nil
			if biome and biome.sides then
				buildNestPlant(inst)
			end
		end
	end
end

------------------------------------------------------------------
-- 모델 도서관 (클라 UI 뷰포트용)
------------------------------------------------------------------

function PlantVisualService.buildLibrary(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "PetModels"
	for i, plant in Plants.list do
		local ok, model = pcall(PlantVisualService.build, plant.id, { fx = false, fruits = 3 })
		if ok then
			model.Parent = folder
		else
			warn("[PlantVisualService] 모델 실패 " .. plant.id .. ": " .. tostring(model))
		end
		if i % 12 == 0 then
			task.wait()
		end
	end
	folder.Parent = ReplicatedStorage
	return folder
end

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------

local function safe(fn: (BasePart) -> (), inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	task.defer(function()
		if inst.Parent == nil then
			return
		end
		local ok, err = pcall(function(): ...any
			fn(inst)
			return
		end)
		if not ok then
			warn("[PlantVisualService] " .. tostring(err))
		end
	end)
end

function PlantVisualService.start()
	if PlantVisualService.started then
		return
	end
	PlantVisualService.started = true

	task.spawn(PlantVisualService.buildLibrary)

	for _, inst in CollectionService:GetTagged(Tags.IncubatingEgg) do
		safe(onSeed, inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.IncubatingEgg):Connect(function(inst: Instance)
		safe(onSeed, inst)
	end)
	for _, inst in CollectionService:GetTagged(Tags.GardenPlant) do
		safe(onPlant, inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.GardenPlant):Connect(function(inst: Instance)
		safe(onPlant, inst)
	end)

	for _, spot in CollectionService:GetTagged(Tags.ParentAnimalSpot) do
		safe(buildNestPlant, spot)
	end
	CollectionService:GetInstanceAddedSignal(Tags.ParentAnimalSpot):Connect(function(inst: Instance)
		safe(buildNestPlant, inst)
	end)
	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild(Tags.StateFolderName, 120)
		if state then
			state:GetAttributeChangedSignal(Tags.StateAttributes.HeavenSide):Connect(rebuildSidedNests)
			rebuildSidedNests()
		end
	end)
end

return PlantVisualService
