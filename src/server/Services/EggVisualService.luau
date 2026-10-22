--!strict
--[[
	EggVisualService — 알 겉모습 (서버, 모두가 같은 모양을 봄). 선임 담당.

	알 파트 생성·줍기·용접은 EggService / BaseService(수석) 가 합니다.
	여기서는 그 파트(Egg / IncubatingEgg 태그)의 Attribute 를 읽어 겉모습만 "자식"으로 붙입니다.

	- 원래 파트는 투명하게 만들고(판정·ProximityPrompt·이름표는 그대로), 폴더 "EggVisual" 안에
	  원작처럼 "매끈한 타원 알" 껍데기("Shell": Ball + SpecialMesh Sphere, Scale y 1.25)를 WeldConstraint 로 붙임.
	  (4판 수정: 사장님 "케이크처럼 보임" → 블록 층 쌓기 없앰)
	- 4판: 등급(Rarities)별 색·무늬 (Visuals.eggLooks). 껍데기 = 등급 색 파스텔(일반은 크림색 진짜 달걀),
	  띠("Band", 얇은 Cylinder, 그 높이 껍데기 지름 × 1.02) = 등급 색, 점("Spot", 표면에 60% 묻힌 작은 Ball)은 펫 대표 색.
	  일반 점 2 / 고급 점 4 / 희귀 띠 2 + 점 / 에픽 둘레 점 4 / 전설 금띠 + 보석 4 / 신화 띠 + 불꽃 점 / 코스믹 별 점 5 /
	  비밀 검정 + 보라 빛 점 / 영원 흰 빛 점 / 신성 무지개 띠 3 + 빛 점. 자산 업로드 필요 없음. 알 하나 ≤ 8 파트.
	  껍데기는 파트 가운데에 맞춤 (EggService·BaseService 가 바닥 + 알 높이 절반에 놓으므로 바닥에 딱 붙음).
	  크기는 파트 크기(크기 등급) 그대로 따라감.
	- 희귀도: 희귀(rare) 이상은 등급 색 반짝이(RarityGlint), 전설 이상(Visuals.rarityEffects 에 있는 것)은 PointLight + 반짝이.
	- 돌연변이: 실버(은색 Foil) / 골든(금색 네온 + 반짝) / 레인보우(네온 + 클라가 색 순환: Shell 에 EggShell 태그 + Rainbow)
	  / 블룸·스피릿 블룸(꽃잎 파티클)
	- 특별 알(Special = true: 비밀/영원/신성): 하늘로 솟는 빛 기둥(Beam) + 어디서나 보이는 "비밀 알!" 이름표
	- 들고 있는 알(EggState == "Carried"): 알 위 BillboardGui "WeightTag" (자식 TextLabel "Gender" = ♂/♀, "Kg" = "4,740Kg").
	  무게 = 알 Attribute WeightKg (없으면 든 플레이어의 CarryWeightKg). 값이 없으면 숨김.
	- 부화 중 알: Ready 가 되면 반짝임. ("에그 1m 52s" 라벨·부화 프롬프트는 클라가 만듦)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Visuals = require(Shared.Data.Visuals)
local Tags = require(Shared.Tags)

local EggVisualService = {}
EggVisualService.started = false

local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- 타원 알: 높이 = 지름 × EGG_HEIGHT (EggService 의 EGG_HEIGHT_SCALE 1.25 와 같게 → 바닥에 딱 붙음)
local EGG_HEIGHT = 1.25

local function rgb(c: Visuals.Color): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function stringAttr(inst: Instance, name: string): string
	local v = inst:GetAttribute(name)
	return if typeof(v) == "string" then v else ""
end

local function split(text: string): { string }
	local result: { string } = {}
	for word in string.gmatch(text, "[^,%s]+") do
		table.insert(result, word)
	end
	return result
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

-- 껍데기·무늬 조각 (알 파트에 WeldConstraint 로 붙음, 매끈한 면)
local function piece(
	egg: BasePart,
	folder: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	mat: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = mat
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = egg.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = egg
	weld.Part1 = p
	weld.Parent = p
	p.Parent = folder
	return p
end

local function sparkle(parent: BasePart, color: Color3, rate: number, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "EggSparkle"
	e.Texture = SPARKLE_TEX
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(color)
	e.Parent = parent
	return e
end

local function rarityOf(egg: BasePart, petId: string): string
	local r = stringAttr(egg, "Rarity")
	if r ~= "" then
		return r
	end
	local pet = Pets.get(petId)
	return if pet then pet.rarity else ""
end

-- 등급 색 (Rarities) / 순서
local function rarityColor(rarity: string): Color3
	local r = Rarities.get(rarity :: any)
	return if r then rgb(r.color) else Color3.fromRGB(200, 200, 200)
end

local function rarityOrder(rarity: string): number
	local r = Rarities.get(rarity :: any)
	return if r then r.order else 1
end

local RAINBOW_BANDS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 225, 80),
	Color3.fromRGB(90, 170, 255),
}

-- 껍데기 위 점 (비율 좌표): az = 둘레 각도(라디안, 0 = 앞 -Z), el = -1(아래) ~ 1(위) 높이 비율
type Dot = { az: number, el: number }
local DOTS2: { Dot } = { { az = 0.5, el = 0.15 }, { az = 2.4, el = -0.2 } }
local DOTS4: { Dot } =
	{ { az = 0.3, el = 0.25 }, { az = 1.9, el = -0.15 }, { az = 3.5, el = 0.3 }, { az = 5.0, el = -0.25 } }
local EQUATOR4: { Dot } = { { az = 0, el = 0 }, { az = 1.571, el = 0 }, { az = 3.142, el = 0 }, { az = 4.712, el = 0 } }
local STARS5: { Dot } = {
	{ az = 0.2, el = 0.45 },
	{ az = 1.5, el = -0.1 },
	{ az = 2.7, el = 0.3 },
	{ az = 3.9, el = -0.35 },
	{ az = 5.2, el = 0.1 },
}

-- 매끈한 타원 알 껍데기 + 등급 무늬 (4판 수정: 층 쌓기 대신 Ball + SpecialMesh 타원 하나).
--   껍데기 = Ball(지름 d) + SpecialMesh(Sphere, Scale y EGG_HEIGHT) → 높이 d × 1.25, 가운데 = 파트 가운데
--   (EggService·BaseService 가 바닥 + 알 높이 절반에 놓으므로 바닥에 딱 붙음).
--   무늬 = 껍데기 표면에 60% 묻힌 작은 Ball, 띠 = 얇은 Cylinder(그 높이 껍데기 지름의 1.02배). 알 하나 ≤ 8 파트.
--   껍데기 = 등급 색 파스텔(Visuals.eggLooks), 무늬 조각 = 펫 대표 색, 돌연변이는 껍데기 색·재질을 덮어씀.
--   반환: { 껍데기 } (반짝이·빛은 껍데기에 붙음)
local function dress(egg: BasePart, petId: string, mutations: { string }, rarity: string): { Part }
	local old = egg:FindFirstChild("EggVisual")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "EggVisual"
	folder.Parent = egg

	local d = math.min(egg.Size.X, egg.Size.Z)
	local look: Visuals.EggLook = Visuals.eggLooks[rarity] or { pattern = "spots2" }
	local tint = rarityColor(rarity)
	local base = if look.shell then rgb(look.shell) else tint:Lerp(WHITE, 0.45)
	local stripe = if look.stripe then rgb(look.stripe) else tint
	-- 무늬 조각 색: 펫 대표 색 (껍데기와 같으면 둘째 색)
	local spot = if look.spot then rgb(look.spot) else rgb(Visuals.petColor(petId, 1))
	if not look.spot and spot == base then
		spot = rgb(Visuals.petColor(petId, 2))
	end
	local spotMat = if look.spotNeon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local mat = Enum.Material.SmoothPlastic
	local reflectance = 0
	local cycle = false
	local petals: Color3? = nil
	for _, id in mutations do
		local mlook = Visuals.mutationLooks[id]
		if mlook then
			if mlook.material or mlook.cycle or id == "silver" or id == "golden" then
				base = rgb(mlook.color)
				stripe = base:Lerp(WHITE, 0.45)
				spot = base:Lerp(BLACK, 0.25)
				mat = materialOf(mlook.material) or mat
				reflectance = mlook.reflectance or reflectance
				cycle = cycle or mlook.cycle == true
			end
			if mlook.petals then
				petals = rgb(mlook.petals)
			end
		end
	end

	-- 원래 파트는 투명하게 (판정/프롬프트/이름표는 그대로 남음)
	egg.Transparency = 1

	local r = d / 2
	local ry = r * EGG_HEIGHT
	local shell = piece(egg, folder, "Shell", Enum.PartType.Ball, Vector3.one * d, CFrame.new(), base, mat)
	shell.Reflectance = reflectance
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, EGG_HEIGHT, 1)
	mesh.Parent = shell
	CollectionService:AddTag(shell, Visuals.Tags.EggShell)
	if cycle then
		shell:SetAttribute("Rainbow", true)
	end

	-- 껍데기 표면 점 (지름 s, 60% 묻힘 → 가운데가 표면에서 0.1 s 안쪽)
	local count = 1
	local function dot(at: Dot, s: number, color: Color3, m: Enum.Material)
		local el = math.clamp(at.el, -0.9, 0.9)
		local y = el * ry
		local ring = r * math.sqrt(1 - el * el) -- 그 높이 껍데기 반지름
		local inward = s * 0.1
		local rr = math.max(0, ring - inward)
		local offset = Vector3.new(math.sin(at.az) * rr, y - el * inward, -math.cos(at.az) * rr)
		count += 1
		piece(egg, folder, "Spot" .. count, Enum.PartType.Ball, Vector3.one * s, CFrame.new(offset), color, m)
	end
	-- 띠 (세운 얇은 원기둥, 그 높이 껍데기 지름 × 1.02)
	local function band(el: number, thick: number, color: Color3, m: Enum.Material)
		local ring = r * math.sqrt(1 - el * el)
		local dia = ring * 2 * 1.02
		count += 1
		piece(
			egg,
			folder,
			"Band" .. count,
			Enum.PartType.Cylinder,
			Vector3.new(thick, dia, dia),
			CFrame.new(0, el * ry, 0) * CFrame.Angles(0, 0, math.pi / 2),
			color,
			m
		)
	end
	local pattern = look.pattern
	local s = d * 0.2
	if pattern == "spots4" then
		for _, p in DOTS4 do
			dot(p, s, spot, spotMat)
		end
	elseif pattern == "stripes" then
		band(0.38, d * 0.09, stripe, mat)
		band(-0.3, d * 0.09, stripe, mat)
		dot(DOTS2[1], s * 0.9, spot, spotMat)
		dot(DOTS2[2], s * 0.9, spot, spotMat)
	elseif pattern == "diamonds" then
		for _, p in EQUATOR4 do
			dot(p, s * 0.95, spot, spotMat)
		end
	elseif pattern == "crown" then
		-- 금띠 + 둘레 보석 4개
		band(0.42, d * 0.12, Color3.fromRGB(255, 205, 50), Enum.Material.Foil)
		local gems = { Color3.fromRGB(255, 60, 90), Color3.fromRGB(60, 160, 255), Color3.fromRGB(80, 230, 120), spot }
		for i, p in EQUATOR4 do
			dot(p, s * 0.8, gems[i], Enum.Material.Neon)
		end
	elseif pattern == "flames" then
		band(-0.55, d * 0.1, stripe, mat)
		for i, p in EQUATOR4 do
			dot(
				{ az = p.az + 0.4, el = -0.3 + (i % 2) * 0.15 },
				s * 0.85,
				Color3.fromRGB(255, 150, 40),
				Enum.Material.Neon
			)
		end
	elseif pattern == "stars" then
		for i, p in STARS5 do
			dot(p, s * (if i % 2 == 0 then 0.7 else 0.55), Color3.fromRGB(255, 245, 170), Enum.Material.Neon)
		end
	elseif pattern == "rainbow" then
		-- 신성: 무지개 띠 3 + 흰 빛 점 3
		for i, el in { 0.45, 0, -0.45 } do
			band(el, d * 0.1, RAINBOW_BANDS[i], Enum.Material.Neon)
		end
		for i = 1, 3 do
			dot({ az = i * 2.1, el = if i == 2 then 0.25 else -0.22 }, s * 0.6, WHITE, Enum.Material.Neon)
		end
	else
		-- spots2 (일반): 작은 점 2개
		for _, p in DOTS2 do
			dot(p, s, spot, spotMat)
		end
	end

	if mat == Enum.Material.Neon or reflectance > 0 then
		sparkle(shell, base:Lerp(WHITE, 0.4), 4, d * 0.25)
	end
	if petals then
		local e = sparkle(shell, petals, 6, d * 0.3)
		e.Name = "Petals"
		e.Acceleration = Vector3.new(0, -2, 0)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.LightEmission = 0.3
	end
	-- 희귀(rare) 이상: 등급 색 반짝이 (높을수록 많이)
	local order = rarityOrder(rarity)
	if order >= 3 then
		local glint = sparkle(shell, tint:Lerp(WHITE, 0.5), math.min(6, order - 1), d * 0.18)
		glint.Name = "RarityGlint"
	end
	-- 희귀도 빛 (전설 이상)
	local fx = Visuals.rarityEffects[rarity]
	if fx then
		local c = fx.light or fx.highlight
		if c and (c[1] + c[2] + c[3]) > 120 then
			local light = Instance.new("PointLight")
			light.Name = "RarityLight"
			light.Color = rgb(c)
			light.Range = math.max(6, d * 4)
			light.Brightness = 1.2
			light.Parent = shell
			local glow = sparkle(shell, rgb(fx.particleColor or c), 3, d * 0.22)
			glow.Name = "RarityGlow"
		end
	end
	return { shell }
end

------------------------------------------------------------------
-- 들고 있는 알 무게 이름표 ("♂ 4,740Kg")
------------------------------------------------------------------

local GENDER_MALE = Color3.fromRGB(90, 175, 255)
local GENDER_FEMALE = Color3.fromRGB(255, 120, 200)

-- 4740 → "4,740"
local function commas(n: number): string
	local text = tostring(math.floor(n + 0.5))
	local sign = ""
	if string.sub(text, 1, 1) == "-" then
		sign = "-"
		text = string.sub(text, 2)
	end
	-- 뒤에서부터 세 자리마다 쉼표
	local groups: { string } = {}
	local i = #text
	while i > 0 do
		table.insert(groups, 1, string.sub(text, math.max(1, i - 2), i))
		i -= 3
	end
	return sign .. table.concat(groups, ",")
end

-- EggUid 로 ♂/♀ 고정 (장식)
local function isMale(uid: string): boolean
	local sum = 0
	for i = 1, #uid do
		sum += string.byte(uid, i)
	end
	return sum % 2 == 0
end

local function carrierOf(uid: string): Player?
	if uid == "" then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(Tags.PlayerAttributes.CarryingEgg) == uid then
			return player
		end
	end
	return nil
end

local function weightOf(egg: BasePart): number?
	local own = egg:GetAttribute("WeightKg")
	if typeof(own) == "number" and own > 0 then
		return own
	end
	local carrier = carrierOf(stringAttr(egg, "EggUid"))
	if carrier then
		local w = carrier:GetAttribute(Tags.PlayerAttributes.CarryWeightKg)
		if typeof(w) == "number" and w > 0 then
			return w
		end
	end
	return nil
end

local function weightTag(egg: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "WeightTag"
	gui.Adornee = egg
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Size = UDim2.fromScale(4.5, 2.2)
	local d = math.min(egg.Size.X, egg.Size.Z)
	gui.StudsOffsetWorldSpace = Vector3.new(0, d * EGG_HEIGHT + 2.2, 0)
	gui.Enabled = false
	local male = isMale(stringAttr(egg, "EggUid"))
	local function line(name: string, y: number, h: number, color: Color3, text: string)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, y)
		label.Size = UDim2.fromScale(1, h)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = text
		local stroke = Instance.new("UIStroke")
		stroke.Color = BLACK
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
		label.Parent = gui
	end
	line("Gender", 0, 0.45, if male then GENDER_MALE else GENDER_FEMALE, if male then "♂" else "♀")
	line("Kg", 0.45, 0.55, Color3.fromRGB(235, 235, 240), "")
	gui.Parent = egg
	return gui
end

local weightTags: { [BasePart]: BillboardGui } = {}

local function updateWeight(egg: BasePart)
	local gui = weightTags[egg]
	if not gui then
		return
	end
	if egg.Parent == nil then
		weightTags[egg] = nil
		return
	end
	local weight = if egg:GetAttribute("EggState") == "Carried" then weightOf(egg) else nil
	if weight then
		local kg = gui:FindFirstChild("Kg")
		if kg and kg:IsA("TextLabel") then
			kg.Text = commas(weight) .. "Kg"
		end
		gui.Enabled = true
	else
		gui.Enabled = false
	end
end

------------------------------------------------------------------
-- 알 꾸미기
------------------------------------------------------------------

local function decorateEgg(egg: BasePart)
	local petId = stringAttr(egg, "PetId")
	if petId == "" then
		return
	end
	local mutations = split(stringAttr(egg, "Mutations"))
	local rarity = rarityOf(egg, petId)
	local layers = dress(egg, petId, mutations, rarity)

	if egg:GetAttribute("Special") == true then
		local spec = Visuals.specialEggs[rarity] or Visuals.specialEggs.secret
		local color = rgb(spec.color)
		-- 빛 기둥 (Beam: 알 안의 두 Attachment 사이, 알과 함께 움직임)
		local a0 = Instance.new("Attachment")
		a0.Name = "BeamBottom"
		a0.Parent = egg
		local a1 = Instance.new("Attachment")
		a1.Name = "BeamTop"
		a1.Position = Vector3.new(0, 250, 0)
		a1.Parent = egg
		local beam = Instance.new("Beam")
		beam.Name = "SpecialBeam"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 4
		beam.Width1 = 6
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Segments = 1
		beam.Color = if rarity == "divine"
			then ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 240, 90)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 110, 255)),
			})
			else ColorSequence.new(if rarity == "secret" then Color3.fromRGB(120, 120, 140) else color)
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = egg

		-- 멀리서도 보이는 이름표 (벽을 뚫고 보이므로 너무 멀면 내 머리 위에 붙은 것처럼 보여 500 스터드 안에서만)
		local gui = Instance.new("BillboardGui")
		gui.Name = "SpecialTag"
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 500
		gui.Size = UDim2.fromOffset(170, 54)
		gui.StudsOffsetWorldSpace = Vector3.new(0, egg.Size.Y + 5, 0)
		gui.Adornee = egg
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 0.62)
		label.BackgroundColor3 = color
		label.BackgroundTransparency = 0.1
		label.TextColor3 = rgb(spec.textColor)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = spec.text
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.4, 0)
		corner.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Color = WHITE
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = label
		local pet = Pets.get(petId)
		local sub = Instance.new("TextLabel")
		sub.Position = UDim2.fromScale(0, 0.64)
		sub.Size = UDim2.fromScale(1, 0.36)
		sub.BackgroundTransparency = 1
		sub.TextColor3 = WHITE
		sub.TextStrokeTransparency = 0
		sub.Font = Enum.Font.FredokaOne
		sub.TextScaled = true
		sub.Text = if pet then pet.name else ""
		sub.Parent = gui
		gui.Parent = egg

		sparkle(layers[#layers], color:Lerp(WHITE, 0.3), 10, egg.Size.X * 0.3)
	end

	-- 들고 있을 때 무게 이름표
	local old = egg:FindFirstChild("WeightTag")
	if old then
		old:Destroy()
	end
	weightTags[egg] = weightTag(egg)
	updateWeight(egg)
	egg:GetAttributeChangedSignal("EggState"):Connect(function()
		updateWeight(egg)
		-- EggService 가 플레이어 CarryingEgg 를 EggState 다음에 넣으므로 한 번 더
		task.defer(updateWeight, egg)
	end)
	egg:GetAttributeChangedSignal("WeightKg"):Connect(function()
		updateWeight(egg)
	end)
end

local function decorateIncubating(egg: BasePart)
	local petId = stringAttr(egg, "PetId")
	if petId == "" then
		return
	end
	local layers = dress(egg, petId, split(stringAttr(egg, "Mutations")), rarityOf(egg, petId))
	local glow = sparkle(layers[#layers], Color3.fromRGB(255, 255, 180), 12, egg.Size.X * 0.35)
	glow.Name = "ReadyGlow"
	local function refresh()
		glow.Enabled = egg:GetAttribute("Ready") == true
	end
	refresh()
	egg:GetAttributeChangedSignal("Ready"):Connect(refresh)
end

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
			warn("[EggVisualService] " .. tostring(err))
		end
	end)
end

function EggVisualService.start()
	if EggVisualService.started then
		return
	end
	EggVisualService.started = true
	for _, inst in CollectionService:GetTagged(Tags.Egg) do
		safe(decorateEgg, inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Egg):Connect(function(inst: Instance)
		safe(decorateEgg, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(Tags.Egg):Connect(function(inst: Instance)
		if inst:IsA("BasePart") then
			weightTags[inst] = nil
		end
	end)
	for _, inst in CollectionService:GetTagged(Tags.IncubatingEgg) do
		safe(decorateIncubating, inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.IncubatingEgg):Connect(function(inst: Instance)
		safe(decorateIncubating, inst)
	end)

	-- 든 알 무게 이름표: 플레이어 Attribute(CarryWeightKg) 가 늦게 바뀌어도 맞춰지게 0.5초마다 (든 알만)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for egg in weightTags do
				if egg.Parent == nil then
					weightTags[egg] = nil
				elseif egg:GetAttribute("EggState") == "Carried" or weightTags[egg].Enabled then
					updateWeight(egg)
				end
			end
		end
	end)
end

return EggVisualService
