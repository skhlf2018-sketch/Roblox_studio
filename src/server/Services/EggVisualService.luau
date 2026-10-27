--!strict
--[[
	EggVisualService — 씨앗 겉모습 (서버, 모두가 같은 모양을 봄). 선임 담당. (이름은 5판 "알" 그대로)

	씨앗 파트 생성·줍기·용접은 EggService(수석) 가 합니다. 여기서는 그 파트(Egg 태그 — 둥지·들고 있는·떨어진 씨앗)의
	Attribute 를 읽어 겉모습만 "자식"으로 붙입니다. (정원에서 자라는 씨앗 IncubatingEgg 는 PlantVisualService)

	- 원래 파트는 투명하게 만들고(판정·ProximityPrompt·이름표는 그대로), 폴더 "EggVisual" 안에
	  6판 씨앗 껍데기("Shell": Ball + SpecialMesh Sphere, Scale (0.82, 1.25, 1) = 아몬드 모양) + 뾰족한 끝("Tip")
	  + 세로 줄무늬("Stripe1~4") + 별·보석 점("Spot") 을 WeldConstraint 로 붙임. 씨앗 하나 ≤ 8 파트.
	  색·줄무늬 수 = Visuals.eggLooks (등급별), 줄무늬에 식물 대표 색을 살짝 섞음.
	  껍데기는 파트 가운데에 맞춤 (EggService 가 바닥 + 높이 절반에 놓으므로 바닥에 딱 붙음). 크기는 파트 크기 그대로.
	- 등급 아우라: PlantVisualService.addAura (희귀 이상 파티클·빛, 꺼진 채 + Shell 에 AuraFx 태그 → 클라가 100 스터드 안만 켬).
	- 돌연변이: 실버(은색 Foil) / 골든(금색 네온) / 레인보우(네온 + 클라가 색 순환: Shell 에 EggShell 태그 + Rainbow)
	- 특별 씨앗(Special = true: 비밀/영원/신성/슈퍼 울트라디바인): 하늘로 솟는 빛 기둥(Beam) + 어디서나 보이는 "비밀 씨앗!" 이름표
	- 들고 있는 씨앗(EggState == "Carried"): 위 BillboardGui "WeightTag" (자식 TextLabel "Gender" = ♂/♀, "Kg" = "4,740Kg").
	  무게 = 파트 Attribute WeightKg (없으면 든 플레이어의 CarryWeightKg). 값이 없으면 숨김.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Visuals = require(Shared.Data.Visuals)
local Tags = require(Shared.Tags)
local PlantVisualService = require(script.Parent.PlantVisualService)

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

local RAINBOW_STRIPES = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 225, 80),
	Color3.fromRGB(90, 220, 120),
	Color3.fromRGB(90, 170, 255),
}

-- 씨앗 껍데기 비율: 지름 d 에 대해 폭 X = d × SEED_WIDTH, 깊이 Z = d, 높이 = d × EGG_HEIGHT (판정 파트에 맞춤)
local SEED_WIDTH = 0.82

--[[
	6판 씨앗 껍데기 (5판 매끈한 타원 알 → 아몬드·물방울 모양 씨앗).
	  껍데기 = Ball(지름 d) + SpecialMesh(Sphere, Scale (0.82, 1.25, 1)) → 높이 d × 1.25, 가운데 = 파트 가운데
	  (EggService·BaseService 가 바닥 + 높이 절반에 놓으므로 바닥에 딱 붙음). 위에 뾰족한 끝("Tip"),
	  세로 줄무늬("Stripe", 껍데기 표면에 붙은 가는 타원), 별·보석 점("Spot"). 씨앗 하나 ≤ 8 파트.
	  색 = Visuals.eggLooks (껍데기 = 등급 색 파스텔), 돌연변이(실버·황금·무지개)는 껍데기 색·재질을 덮어씀.
	  등급 아우라(희귀 이상 파티클·빛)는 PlantVisualService.addAura (꺼진 채 + AuraFx 태그 → 클라가 가까운 것만 켬).
	반환: { 껍데기 }
]]
local function dress(egg: BasePart, petId: string, mutations: { string }, rarity: string): { Part }
	local old = egg:FindFirstChild("EggVisual")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "EggVisual"
	folder.Parent = egg

	local d = math.min(egg.Size.X, egg.Size.Z)
	local look: Visuals.EggLook = Visuals.eggLooks[rarity] or { stripes = 2 }
	local tint = rarityColor(rarity)
	local base = if look.shell then rgb(look.shell) else tint:Lerp(WHITE, 0.45)
	local stripe = if look.stripe then rgb(look.stripe) else tint
	local tip = if look.tip then rgb(look.tip) else base:Lerp(BLACK, 0.2)
	local stripeMat = if look.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local mat = Enum.Material.SmoothPlastic
	local reflectance = 0
	local cycle = false
	for _, id in mutations do
		local mlook = Visuals.mutationLooks[id]
		if mlook and (id == "silver" or id == "golden" or id == "rainbow") then
			base = rgb(mlook.color)
			tip = base:Lerp(WHITE, 0.3)
			mat = materialOf(mlook.material) or mat
			reflectance = mlook.reflectance or reflectance
			cycle = cycle or mlook.cycle == true
		end
	end
	-- 식물 대표 색(꽃잎)을 줄무늬에 살짝 섞어 어떤 식물인지 힌트
	if not look.stripe and not look.rainbow then
		stripe = stripe:Lerp(rgb(Visuals.petColor(petId, 1)), 0.3)
	end

	-- 원래 파트는 투명하게 (판정/프롬프트/이름표는 그대로 남음)
	egg.Transparency = 1

	local r = d / 2
	local ry = r * EGG_HEIGHT
	local shell = piece(egg, folder, "Shell", Enum.PartType.Ball, Vector3.one * d, CFrame.new(), base, mat)
	shell.Reflectance = reflectance
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(SEED_WIDTH, EGG_HEIGHT, 1)
	mesh.Parent = shell
	CollectionService:AddTag(shell, Visuals.Tags.EggShell)
	if cycle then
		shell:SetAttribute("Rainbow", true)
	end
	-- 뾰족한 끝 (위)
	local tipPart =
		piece(egg, folder, "Tip", Enum.PartType.Ball, Vector3.one * d * 0.34, CFrame.new(0, ry * 0.86, 0), tip, mat)
	local tipMesh = Instance.new("SpecialMesh")
	tipMesh.MeshType = Enum.MeshType.Sphere
	tipMesh.Scale = Vector3.new(0.75, 1.5, 0.75)
	tipMesh.Parent = tipPart

	-- 세로 줄무늬 (껍데기 표면, 앞뒤·옆으로 고르게)
	local n = math.clamp(look.stripes, 0, 4)
	for i = 1, n do
		local az = (i - 1) / math.max(1, n) * math.pi * 2 + 0.35
		local rx = r * SEED_WIDTH * 0.93
		local rz = r * 0.93
		local offset = Vector3.new(math.sin(az) * rx, 0, -math.cos(az) * rz)
		local color = if look.rainbow then RAINBOW_STRIPES[(i - 1) % #RAINBOW_STRIPES + 1] else stripe
		local p = piece(
			egg,
			folder,
			"Stripe" .. i,
			Enum.PartType.Block,
			Vector3.new(d * 0.13, ry * 1.6, d * 0.13),
			CFrame.new(offset) * CFrame.Angles(0, -az, 0),
			color,
			if look.rainbow then Enum.Material.Neon else stripeMat
		)
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	-- 별·보석 점 (껍데기 앞쪽 표면)
	if look.dots == "stars" or look.dots == "gems" then
		local stars = look.dots == "stars"
		for i, at in { { 0.9, 0.25 }, { -0.8, -0.3 } } do
			local az = at[1]
			local el = at[2]
			local ring = r * math.sqrt(1 - el * el) * 0.95
			local offset = Vector3.new(math.sin(az) * ring * SEED_WIDTH, el * ry, -math.cos(az) * ring)
			piece(
				egg,
				folder,
				"Spot" .. i,
				Enum.PartType.Ball,
				Vector3.one * d * (if stars then 0.14 else 0.17),
				CFrame.new(offset),
				if stars then Color3.fromRGB(255, 245, 170) else Color3.fromRGB(255, 70, 110),
				Enum.Material.Neon
			)
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

		sparkle(layers[#layers], color:Lerp(WHITE, 0.3), 6, egg.Size.X * 0.3)
	end

	-- 등급 아우라 (희귀 이상). 껍데기의 파티클·빛은 전부 꺼진 채로 두고 AuraFx 태그 → 클라가 가까운 것만 켬
	local shell = layers[1]
	PlantVisualService.addAura(shell, rarity, math.max(0.6, egg.Size.X * 0.5), {
		mutations = mutations,
		noBeam = egg:GetAttribute("Special") == true, -- 특별 씨앗은 위 SpecialBeam 이 이미 있음
	})
	local hasFx = false
	for _, d in shell:GetChildren() do
		if d:IsA("ParticleEmitter") or d:IsA("PointLight") then
			(d :: any).Enabled = false
			hasFx = true
		end
	end
	if hasFx then
		CollectionService:AddTag(shell, Visuals.Tags.AuraFx)
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
