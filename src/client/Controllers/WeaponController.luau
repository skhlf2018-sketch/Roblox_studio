--!strict
--[[
	WeaponController — 손에 든 무기 모양 + 휘두르기 애니메이션 (보기만, 판정은 서버 ToolService)

	- 서버 Tool 은 RequiresHandle = false 라 손에 아무것도 안 보임 → 클라가 오른손(RightHand / Right Arm)에
	  기본 도형 무기 모델을 용접해서 붙임. 모든 플레이어 캐릭터에 붙이므로 다른 사람 무기도 보임.
	  (Tool 이 캐릭터 안에 있음 = 들고 있음. Backpack 으로 돌아가면 모델 지움)
	- 모양: 방망이(나무 원기둥) · 물 방망이(파랑 + 물방울) · 카타나(납작 칼날) · 도끼 · 천사의 창 · 망치 · 사탕 지팡이(빨강/흰 줄무늬) · 낫 · 곰덫
	- 휘두르기: 용접 C0 를 TweenService 로 뒤로 젖혔다가 앞으로 내려침 + 끝에 Trail.
	  내 휘두르기 = Tool.Activated 또는 핫바 버튼(HotbarController 가 WeaponController.swing 호출).
	  쿨다운(Weapons.cooldown) 안에는 다시 휘두르지 않음 (서버와 같은 숫자).
	  다른 사람 휘두르기는 Tool Attribute "SwingTick" 이 바뀌면 재생 (서버가 써 주면 동작 — 수석 요청 사항).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Weapons = require(Shared.Data.Weapons)
local SoundController = require(script.Parent.SoundController)

local WeaponController = {}

type Style = "chop" | "slash" | "thrust"
type Built = { root: BasePart, tip: BasePart, style: Style }

local WOOD = Color3.fromRGB(190, 130, 75)
local DARK = Color3.fromRGB(50, 40, 40)
local STEEL = Color3.fromRGB(205, 210, 220)
local WHITE = Color3.new(1, 1, 1)

-- 들고 있는 자세: 손에서 앞쪽 위로 비스듬히 (무기 모델은 +Y 가 손잡이 → 끝)
local REST = CFrame.new(0, -0.9, -0.2) * CFrame.Angles(math.rad(-60), 0, 0)
local WINDUP: { [Style]: CFrame } = {
	chop = CFrame.new(0, -0.9, -0.2) * CFrame.Angles(math.rad(20), 0, 0),
	slash = CFrame.new(0, -0.9, -0.2) * CFrame.Angles(math.rad(-80), math.rad(70), 0),
	thrust = CFrame.new(0, -0.9, 0.6) * CFrame.Angles(math.rad(-85), 0, 0),
}
local STRIKE: { [Style]: CFrame } = {
	chop = CFrame.new(0, -0.9, -0.4) * CFrame.Angles(math.rad(-150), 0, 0),
	slash = CFrame.new(0, -0.9, -0.4) * CFrame.Angles(math.rad(-80), math.rad(-80), 0),
	thrust = CFrame.new(0, -0.9, -2.4) * CFrame.Angles(math.rad(-90), 0, 0),
}

------------------------------------------------------------------
-- 모델 만들기 (기본 도형)
------------------------------------------------------------------

local function part(
	model: Model,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("Offset", offset)
	p.Parent = model
	return p
end

-- 세운 원기둥 (Y 축이 길이): Cylinder 는 X 축이 길이라 Z 로 90도 돌림
local function rod(
	model: Model,
	name: string,
	diameter: number,
	length: number,
	y: number,
	color: Color3,
	mat: Enum.Material?
): Part
	return part(
		model,
		name,
		Enum.PartType.Cylinder,
		Vector3.new(length, diameter, diameter),
		CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		mat
	)
end

local function block(
	model: Model,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	mat: Enum.Material?
): Part
	return part(model, name, Enum.PartType.Block, size, offset, color, mat)
end

local function ball(model: Model, name: string, d: number, offset: CFrame, color: Color3, mat: Enum.Material?): Part
	return part(model, name, Enum.PartType.Ball, Vector3.one * d, offset, color, mat)
end

-- kind → (모델, 끝 파트 이름, 휘두르기 모양)
local function buildModel(kind: string): (Model?, string, Style)
	local model = Instance.new("Model")
	model.Name = "WeaponVisual"
	if kind == "Bat" or kind == "WaterBat" then
		local color = if kind == "WaterBat" then Color3.fromRGB(70, 160, 255) else WOOD
		local mat = if kind == "WaterBat" then Enum.Material.Glass else Enum.Material.Wood
		rod(model, "Grip", 0.35, 1.2, 0.3, DARK)
		rod(model, "Body", 0.5, 2.4, 2.0, color, mat)
		rod(model, "Tip", 0.62, 1.0, 3.5, color, mat)
		if kind == "WaterBat" then
			for i = 1, 3 do
				ball(
					model,
					"Drop" .. i,
					0.3,
					CFrame.new(0.3 * math.cos(i * 2), 1.4 + i * 0.7, 0.3 * math.sin(i * 2)),
					Color3.fromRGB(180, 230, 255),
					Enum.Material.Neon
				)
			end
		end
		return model, "Tip", "chop"
	elseif kind == "Katana" then
		rod(model, "Grip", 0.3, 1.4, 0.4, Color3.fromRGB(150, 30, 50))
		block(
			model,
			"Guard",
			Vector3.new(0.9, 0.12, 0.9),
			CFrame.new(0, 1.15, 0),
			Color3.fromRGB(230, 190, 70),
			Enum.Material.Metal
		)
		block(model, "Blade", Vector3.new(0.12, 3.6, 0.4), CFrame.new(0, 3.0, 0), STEEL, Enum.Material.Metal)
		block(model, "Tip", Vector3.new(0.12, 0.5, 0.25), CFrame.new(0, 5.0, 0.05), STEEL, Enum.Material.Metal)
		return model, "Tip", "slash"
	elseif kind == "Axe" then
		rod(model, "Handle", 0.35, 3.4, 1.5, WOOD, Enum.Material.Wood)
		block(model, "Head", Vector3.new(0.3, 1.0, 1.4), CFrame.new(0, 3.0, -0.6), STEEL, Enum.Material.Metal)
		block(
			model,
			"Tip",
			Vector3.new(0.32, 1.3, 0.3),
			CFrame.new(0, 3.0, -1.35),
			Color3.fromRGB(235, 240, 245),
			Enum.Material.Metal
		)
		return model, "Tip", "chop"
	elseif kind == "AngelSpear" then
		rod(model, "Shaft", 0.28, 5.0, 2.2, WHITE, Enum.Material.Marble)
		block(
			model,
			"Wing",
			Vector3.new(1.4, 0.2, 0.2),
			CFrame.new(0, 4.6, 0),
			Color3.fromRGB(255, 210, 80),
			Enum.Material.Foil
		)
		local tip = block(
			model,
			"Tip",
			Vector3.new(0.25, 1.2, 0.5),
			CFrame.new(0, 5.4, 0),
			Color3.fromRGB(255, 230, 120),
			Enum.Material.Neon
		)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 230, 150)
		light.Range = 8
		light.Brightness = 1
		light.Parent = tip
		return model, "Tip", "thrust"
	elseif kind == "Hammer" then
		rod(model, "Handle", 0.4, 3.0, 1.3, Color3.fromRGB(80, 60, 110), Enum.Material.Wood)
		part(
			model,
			"Head",
			Enum.PartType.Cylinder,
			Vector3.new(1.8, 1.2, 1.2),
			CFrame.new(0, 3.1, 0),
			Color3.fromRGB(110, 230, 200),
			Enum.Material.Neon
		)
		block(
			model,
			"Tip",
			Vector3.new(0.4, 0.4, 0.4),
			CFrame.new(0, 3.1, 0),
			Color3.fromRGB(230, 255, 245),
			Enum.Material.Neon
		)
		return model, "Tip", "chop"
	elseif kind == "CandyCane" then
		local red = Color3.fromRGB(235, 50, 60)
		for i = 0, 5 do
			rod(model, "Stripe" .. i, 0.45, 0.6, 0.3 + i * 0.6, if i % 2 == 0 then red else WHITE)
		end
		part(
			model,
			"Hook1",
			Enum.PartType.Cylinder,
			Vector3.new(0.8, 0.45, 0.45),
			CFrame.new(0, 3.85, -0.25) * CFrame.Angles(0, math.pi / 2, math.rad(40)),
			WHITE
		)
		part(
			model,
			"Hook2",
			Enum.PartType.Cylinder,
			Vector3.new(0.8, 0.45, 0.45),
			CFrame.new(0, 4.05, -0.85) * CFrame.Angles(0, math.pi / 2, math.rad(-20)),
			red
		)
		block(model, "Tip", Vector3.new(0.45, 0.6, 0.45), CFrame.new(0, 3.75, -1.3), WHITE)
		return model, "Tip", "chop"
	elseif kind == "Scythe" then
		rod(model, "Shaft", 0.3, 5.0, 2.0, Color3.fromRGB(60, 45, 50), Enum.Material.Wood)
		block(
			model,
			"Blade1",
			Vector3.new(0.1, 0.5, 1.6),
			CFrame.new(0, 4.3, -0.8) * CFrame.Angles(math.rad(-10), 0, 0),
			Color3.fromRGB(170, 120, 230),
			Enum.Material.Metal
		)
		block(
			model,
			"Blade2",
			Vector3.new(0.1, 0.4, 1.3),
			CFrame.new(0, 3.9, -2.0) * CFrame.Angles(math.rad(-45), 0, 0),
			Color3.fromRGB(170, 120, 230),
			Enum.Material.Metal
		)
		block(
			model,
			"Tip",
			Vector3.new(0.1, 0.3, 0.5),
			CFrame.new(0, 3.3, -2.5) * CFrame.Angles(math.rad(-70), 0, 0),
			Color3.fromRGB(220, 180, 255),
			Enum.Material.Neon
		)
		return model, "Tip", "slash"
	elseif kind == "BearTrap" then
		part(
			model,
			"Ring",
			Enum.PartType.Cylinder,
			Vector3.new(0.3, 1.6, 1.6),
			CFrame.new(0, 0.4, -0.6),
			Color3.fromRGB(110, 110, 120),
			Enum.Material.Metal
		)
		block(
			model,
			"Tip",
			Vector3.new(1.2, 0.2, 0.2),
			CFrame.new(0, 0.6, -0.6),
			Color3.fromRGB(200, 200, 210),
			Enum.Material.Metal
		)
		return model, "Tip", "thrust"
	end
	model:Destroy()
	return nil, "", "chop"
end

------------------------------------------------------------------
-- 붙이기 / 떼기
------------------------------------------------------------------

type Attached = { model: Model, weld: Weld, trail: Trail?, style: Style, swinging: boolean }

local attached: { [Model]: Attached } = {} -- 캐릭터 → 붙은 무기
local lastSwing: { [string]: number } = {}
local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function handOf(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

local function detach(character: Model)
	local current = attached[character]
	if current then
		current.model:Destroy()
		attached[character] = nil
	end
end

local function attach(character: Model, tool: Tool)
	detach(character)
	local hand = handOf(character)
	if not hand then
		return
	end
	local model, tipName, style = buildModel(tool.Name)
	if not model then
		return
	end
	-- 모델 안 파트를 "Root"(손잡이 원점)에 용접
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Parent = model
	model.PrimaryPart = root
	root.CFrame = hand.CFrame * REST
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			local offset = child:GetAttribute("Offset")
			child.CFrame = root.CFrame * (if typeof(offset) == "CFrame" then offset else CFrame.new())
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = child
			w.Parent = child
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "GripWeld"
	weld.Part0 = hand
	weld.Part1 = root
	weld.C0 = REST
	weld.Parent = root
	-- 휘두를 때 끝에 꼬리
	local trail: Trail? = nil
	local tip = model:FindFirstChild(tipName)
	if tip and tip:IsA("BasePart") then
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailBase"
		a0.Position = Vector3.new(0, -0.6, 0)
		a0.Parent = tip
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailTip"
		a1.Position = Vector3.new(0, 0.4, 0)
		a1.Parent = tip
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Lifetime = 0.18
		t.LightEmission = 0.6
		t.Color = ColorSequence.new(Color3.new(1, 1, 1))
		t.Transparency = NumberSequence.new(0.3, 1)
		t.Enabled = false
		t.Parent = tip
		trail = t
	end
	model.Parent = character
	attached[character] = { model = model, weld = weld, trail = trail, style = style :: Style, swinging = false }
end

local function playSwing(character: Model)
	local current = attached[character]
	if not current or current.swinging then
		return
	end
	current.swinging = true
	local weld = current.weld
	local trail = current.trail
	local windup = TweenService:Create(
		weld,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ C0 = WINDUP[current.style] }
	)
	local strike = TweenService:Create(
		weld,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ C0 = STRIKE[current.style] }
	)
	local back =
		TweenService:Create(weld, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = REST })
	windup.Completed:Connect(function()
		if trail then
			trail.Enabled = true
		end
		strike:Play()
	end)
	strike.Completed:Connect(function()
		if trail then
			trail.Enabled = false
		end
		back:Play()
	end)
	back.Completed:Connect(function()
		current.swinging = false
	end)
	windup:Play()
	-- 혹시 Tween 이 끊겨도 다시 휘두를 수 있게
	task.delay(0.7, function()
		current.swinging = false
	end)
end

-- 내 캐릭터 휘두르기 (핫바 버튼·Tool.Activated). 쿨다운 안이면 무시.
function WeaponController.swing(kind: string)
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	local weapon = Weapons.byTool(kind)
	if not weapon then
		return -- 곰덫 등은 휘두르지 않음
	end
	local now = os.clock()
	-- 근접 무기는 쿨다운을 같이 씀 (서버와 같음)
	local last = lastSwing.melee or 0
	if now - last < weapon.cooldown then
		return
	end
	lastSwing.melee = now
	SoundController.play("Swing")
	playSwing(character)
end

local function isKind(name: string): boolean
	for _, kind in Remotes.ToolKinds do
		if kind == name then
			return true
		end
	end
	return false
end

local function watchCharacter(player: Player, character: Model)
	local function onTool(child: Instance)
		if child:IsA("Tool") and isKind(child.Name) then
			local tool = child
			task.defer(function()
				if tool.Parent == character then
					attach(character, tool)
				end
			end)
			if hookedTools[tool] then
				return
			end
			hookedTools[tool] = true
			if player == Players.LocalPlayer then
				tool.Activated:Connect(function()
					WeaponController.swing(tool.Name)
				end)
			else
				tool:GetAttributeChangedSignal("SwingTick"):Connect(function()
					local holder = tool.Parent
					if holder and holder:IsA("Model") and attached[holder] then
						playSwing(holder)
					end
				end)
			end
		end
	end
	for _, child in character:GetChildren() do
		onTool(child)
	end
	character.ChildAdded:Connect(onTool)
	character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") then
			-- 다른 Tool 을 아직 들고 있으면 그걸로
			local other = character:FindFirstChildOfClass("Tool")
			if other and isKind(other.Name) then
				attach(character, other)
			else
				detach(character)
			end
		end
	end)
	character.AncestryChanged:Connect(function()
		if character.Parent == nil then
			attached[character] = nil
		end
	end)
end

local function watchPlayer(player: Player)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)
end

function WeaponController.start()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

return WeaponController
