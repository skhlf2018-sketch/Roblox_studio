--!strict
--[[
	EggVisualService — 알 겉모습 (서버, 모두가 같은 모양을 봄). 선임 담당.

	알 파트 생성·줍기·용접은 EggService / BaseService(수석) 가 합니다.
	여기서는 그 파트(Egg / IncubatingEgg 태그)의 Attribute 를 읽어 겉모습만 "자식"으로 붙입니다.

	- 원래 파트(Shape = Ball)는 투명하게 만들고(판정·ProximityPrompt·이름표는 그대로),
	  타원체 껍데기 2개(SpecialMesh Sphere: 아래 넓은 것 + 위 좁은 것 = 달걀 모양)를 WeldConstraint 로 붙임.
	- 색 = 펫 대표 색(Visuals), 점무늬 = 펫 둘째 색. 크기는 파트 크기(크기 등급) 그대로 따라감.
	- 돌연변이: 실버(은색 Foil) / 골든(금색 네온 + 반짝) / 레인보우(네온 + 클라가 색 순환) / 블룸·스피릿 블룸(꽃잎 파티클)
	- 특별 알(Special = true: 비밀/영원/신성): 하늘로 솟는 빛 기둥(Beam) + 어디서나 보이는 "비밀 알!" 이름표
	- 부화 중 알: Ready 가 되면 반짝임.
	시작: MapBuilder.start() 끝에서 start() (본부장이 나중에 Main.server.luau 에 정식 등록 예정).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Data.Pets)
local Visuals = require(Shared.Data.Visuals)
local Tags = require(Shared.Tags)

local EggVisualService = {}
EggVisualService.started = false

local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"

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

local function piece(
	egg: BasePart,
	folder: Instance,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	mat: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = "Shell"
	p.Size = size
	p.Color = color
	p.Material = mat
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = egg.CFrame * offset
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
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

-- 달걀 껍데기 붙이기. 반환: 껍데기 파트 목록
local function dress(egg: BasePart, petId: string, mutations: { string }): { Part }
	local old = egg:FindFirstChild("EggVisual")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "EggVisual"
	folder.Parent = egg

	local d = math.min(egg.Size.X, egg.Size.Z)
	local base = rgb(Visuals.petColor(petId, 1))
	local spotColor = rgb(Visuals.petColor(petId, 2))
	if spotColor == base then
		spotColor = rgb(Visuals.petColor(petId, 3))
	end
	local mat = Enum.Material.SmoothPlastic
	local reflectance = 0
	local cycle = false
	local petals: Color3? = nil
	for _, id in mutations do
		local look = Visuals.mutationLooks[id]
		if look then
			if look.material or look.cycle or id == "silver" or id == "golden" then
				base = rgb(look.color)
				spotColor = base:Lerp(Color3.new(1, 1, 1), 0.45)
				mat = materialOf(look.material) or mat
				reflectance = look.reflectance or reflectance
				cycle = cycle or look.cycle == true
			end
			if look.petals then
				petals = rgb(look.petals)
			end
		end
	end

	-- 원래 공 모양 파트는 투명하게 (판정/프롬프트/이름표는 그대로 남음)
	egg.Transparency = 1

	local bottom = piece(egg, folder, Vector3.new(d, d * 0.9, d), CFrame.new(0, -d * 0.2, 0), base, mat)
	local top = piece(egg, folder, Vector3.new(d * 0.8, d * 1.0, d * 0.8), CFrame.new(0, d * 0.12, 0), base, mat)
	local shells = { bottom, top }
	for _, p in shells do
		p.Reflectance = reflectance
		CollectionService:AddTag(p, Visuals.Tags.EggShell)
		if cycle then
			p:SetAttribute("Rainbow", true)
		end
	end
	-- 점무늬 3개 (타원 표면 위)
	for i, spec in { { 0.6, 25 }, { 2.7, -5 }, { 4.6, 40 } } do
		local theta, phi = spec[1], math.rad(spec[2])
		local rx, ry = d * 0.5, d * 0.45
		local pos = Vector3.new(
			rx * math.cos(phi) * math.cos(theta),
			-d * 0.2 + ry * math.sin(phi),
			rx * math.cos(phi) * math.sin(theta)
		) * 0.96
		local dot = piece(egg, folder, Vector3.new(d * 0.24, d * 0.2, d * 0.24), CFrame.new(pos), spotColor, mat)
		dot.Name = "Spot" .. i
	end

	if mat == Enum.Material.Neon or reflectance > 0 then
		sparkle(top, base:Lerp(Color3.new(1, 1, 1), 0.4), 4, d * 0.25)
	end
	if petals then
		local e = sparkle(top, petals, 6, d * 0.3)
		e.Name = "Petals"
		e.Acceleration = Vector3.new(0, -2, 0)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.LightEmission = 0.3
	end
	return shells
end

local function decorateEgg(egg: BasePart)
	local petId = stringAttr(egg, "PetId")
	if petId == "" then
		return
	end
	local mutations = split(stringAttr(egg, "Mutations"))
	local shells = dress(egg, petId, mutations)

	if egg:GetAttribute("Special") == true then
		local rarity = stringAttr(egg, "Rarity")
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

		-- 지도 어디서나 보이는 이름표
		local gui = Instance.new("BillboardGui")
		gui.Name = "SpecialTag"
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 100000
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
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = label
		local pet = Pets.get(stringAttr(egg, "PetId"))
		local sub = Instance.new("TextLabel")
		sub.Position = UDim2.fromScale(0, 0.64)
		sub.Size = UDim2.fromScale(1, 0.36)
		sub.BackgroundTransparency = 1
		sub.TextColor3 = Color3.new(1, 1, 1)
		sub.TextStrokeTransparency = 0
		sub.Font = Enum.Font.FredokaOne
		sub.TextScaled = true
		sub.Text = if pet then pet.name else ""
		sub.Parent = gui
		gui.Parent = egg

		sparkle(shells[2], color:Lerp(Color3.new(1, 1, 1), 0.3), 10, egg.Size.X * 0.3)
	end
end

local function decorateIncubating(egg: BasePart)
	local petId = stringAttr(egg, "PetId")
	if petId == "" then
		return
	end
	local shells = dress(egg, petId, split(stringAttr(egg, "Mutations")))
	local glow = sparkle(shells[2], Color3.fromRGB(255, 255, 180), 12, egg.Size.X * 0.35)
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
	for _, inst in CollectionService:GetTagged(Tags.IncubatingEgg) do
		safe(decorateIncubating, inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.IncubatingEgg):Connect(function(inst: Instance)
		safe(decorateIncubating, inst)
	end)
end

return EggVisualService
