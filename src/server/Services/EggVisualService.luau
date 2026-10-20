--!strict
--[[
	EggVisualService — 알 겉모습 (서버, 모두가 같은 모양을 봄). 선임 담당.

	알 파트 생성·줍기·용접은 EggService / BaseService(수석) 가 합니다.
	여기서는 그 파트(Egg / IncubatingEgg 태그)의 Attribute 를 읽어 겉모습만 "자식"으로 붙입니다.

	- 원래 파트는 투명하게 만들고(판정·ProximityPrompt·이름표는 그대로), 폴더 "EggVisual" 안에
	  원작처럼 "계단형 블록 달걀"(층 6개 "Layer": 아래 넓고 위로 좁아짐, 윗면 스터드)을 WeldConstraint 로 붙임.
	- 색 = 펫 대표 색(Visuals), 줄무늬 층 = 펫 둘째 색. 크기는 파트 크기(크기 등급) 그대로 따라감.
	- 희귀도: 전설 이상(Visuals.rarityEffects 에 있는 것)은 PointLight + 반짝이.
	- 돌연변이: 실버(은색 Foil) / 골든(금색 네온 + 반짝) / 레인보우(네온 + 클라가 색 순환: Layer 에 EggShell 태그 + Rainbow)
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
local Visuals = require(Shared.Data.Visuals)
local Tags = require(Shared.Tags)

local EggVisualService = {}
EggVisualService.started = false

local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- 계단형 달걀: 아래에서 위로 층별 폭(지름 비율). 줄무늬 층 = STRIPES
local LAYERS = { 0.74, 0.96, 1.0, 0.9, 0.72, 0.46 }
local STRIPES: { [number]: boolean } = { [2] = true, [4] = true }
local EGG_HEIGHT = 1.2 -- 전체 높이 = 지름 × 이 값

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

local function block(
	egg: BasePart,
	folder: Instance,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	mat: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = if mat == Enum.Material.Neon then Enum.SurfaceType.Smooth else Enum.SurfaceType.Studs
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

-- 계단형 달걀 껍데기 붙이기. 반환: 층 파트 목록 (아래 → 위)
local function dress(egg: BasePart, petId: string, mutations: { string }, rarity: string): { Part }
	local old = egg:FindFirstChild("EggVisual")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "EggVisual"
	folder.Parent = egg

	local d = math.min(egg.Size.X, egg.Size.Z)
	local base = rgb(Visuals.petColor(petId, 1))
	local stripe = rgb(Visuals.petColor(petId, 2))
	if stripe == base then
		stripe = rgb(Visuals.petColor(petId, 3))
	end
	if stripe == base then
		stripe = base:Lerp(BLACK, 0.2)
	end
	local mat = Enum.Material.Plastic
	local reflectance = 0
	local cycle = false
	local petals: Color3? = nil
	for _, id in mutations do
		local look = Visuals.mutationLooks[id]
		if look then
			if look.material or look.cycle or id == "silver" or id == "golden" then
				base = rgb(look.color)
				stripe = base:Lerp(WHITE, 0.45)
				mat = materialOf(look.material) or mat
				reflectance = look.reflectance or reflectance
				cycle = cycle or look.cycle == true
			end
			if look.petals then
				petals = rgb(look.petals)
			end
		end
	end

	-- 원래 파트는 투명하게 (판정/프롬프트/이름표는 그대로 남음)
	egg.Transparency = 1

	local total = d * EGG_HEIGHT
	local h = total / #LAYERS
	local bottom = -egg.Size.Y / 2
	local layers: { Part } = {}
	for i, frac in LAYERS do
		local w = d * frac
		local y = bottom + (i - 0.5) * h
		local color = if STRIPES[i] then stripe else base
		local p = block(egg, folder, "Layer", Vector3.new(w, h, w), CFrame.new(0, y, 0), color, mat)
		p.Reflectance = reflectance
		CollectionService:AddTag(p, Visuals.Tags.EggShell)
		if cycle then
			p:SetAttribute("Rainbow", true)
		end
		table.insert(layers, p)
	end
	-- 넓은 층에 작은 네모 점 2개 (줄무늬 색)
	local wide = d * LAYERS[3]
	local y3 = bottom + 2.5 * h
	for i, offset in { CFrame.new(wide * 0.18, y3, -wide / 2), CFrame.new(wide / 2, y3, wide * 0.12) } do
		local size = if i == 1 then Vector3.new(d * 0.2, h * 0.6, d * 0.04) else Vector3.new(d * 0.04, h * 0.6, d * 0.2)
		block(egg, folder, "Spot" .. i, size, offset, stripe, mat)
	end

	local top = layers[#layers]
	if mat == Enum.Material.Neon or reflectance > 0 then
		sparkle(top, base:Lerp(WHITE, 0.4), 4, d * 0.25)
	end
	if petals then
		local e = sparkle(top, petals, 6, d * 0.3)
		e.Name = "Petals"
		e.Acceleration = Vector3.new(0, -2, 0)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.LightEmission = 0.3
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
			light.Parent = layers[3]
			local glow = sparkle(layers[3], rgb(fx.particleColor or c), 3, d * 0.22)
			glow.Name = "RarityGlow"
		end
	end
	return layers
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
