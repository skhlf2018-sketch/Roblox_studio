--!strict
--[[
	HotbarController — 오른쪽 아래 도구 핫바 (방망이 · 곰덫 개수 · 구역 무기)
	- 서버가 Backpack 에 넣어 준 Tool(이름 = Remotes.ToolKinds) 을 칸으로 보여 줌. 기본 Roblox 가방 UI 는 끔.
	- 칸 누르기(또는 숫자키 1~9): 손에 들기 ↔ 내려놓기. 든 상태에서 한 번 더 누르면 사용(UseTool).
	  손에 든 채 화면을 클릭/터치해도 ToolController 가 UseTool 을 보냄.
	- 터치 기기에서는 점프 버튼과 안 겹치게 조금 위로.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)

local HotbarController = {}

local C = Theme.Colors

local NAMES: { [string]: string } = {
	Bat = "방망이",
	BearTrap = "곰덫",
	WaterBat = "물 방망이",
	Katana = "카타나",
	Axe = "도끼",
	AngelSpear = "천사의 창",
	Hammer = "망치",
	CandyCane = "사탕 지팡이",
	Scythe = "낫",
}

local COLORS: { [string]: Color3 } = {
	Bat = Color3.fromRGB(205, 140, 80),
	BearTrap = Color3.fromRGB(140, 140, 150),
	WaterBat = Color3.fromRGB(80, 170, 255),
	Katana = Color3.fromRGB(255, 130, 170),
	Axe = Color3.fromRGB(190, 170, 120),
	AngelSpear = Color3.fromRGB(255, 220, 90),
	Hammer = Color3.fromRGB(110, 230, 200),
	CandyCane = Color3.fromRGB(255, 90, 110),
	Scythe = Color3.fromRGB(150, 100, 220),
}

local KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

local function isKind(name: string): boolean
	for _, kind in Remotes.ToolKinds do
		if kind == name then
			return true
		end
	end
	return false
end

-- 도구 그림 (기본 도형)
local function drawTool(kind: string, parent: Instance)
	local color = COLORS[kind] or C.gray
	if kind == "BearTrap" then
		local ring: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromOffset(46, 46),
			BackgroundColor3 = color,
			Parent = parent,
		})
		Ui.corner(1).Parent = ring
		Ui.stroke(C.ink, 3).Parent = ring
		for i = 1, 6 do
			Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + math.cos(i) * 0.3, 0.5 + math.sin(i) * 0.3),
				Size = UDim2.fromOffset(8, 8),
				Rotation = 45,
				BackgroundColor3 = C.white,
				Parent = ring,
			})
		end
	else
		local stick: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromOffset(14, 54),
			Rotation = 35,
			BackgroundColor3 = color,
			Parent = parent,
		})
		Ui.corner(1).Parent = stick
		Ui.stroke(C.ink, 3).Parent = stick
	end
end

function HotbarController.start()
	local player = Players.LocalPlayer
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local bar: Frame = Ui.new("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(1, 1),
		Position = if touch then UDim2.new(1, -12, 1, -175) else UDim2.new(1, -14, 1, -14),
		Size = UDim2.fromOffset(400, 96),
		BackgroundTransparency = 1,
		Parent = Ui.layer("Hud"),
	})
	Ui.scaled(bar)
	Ui.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom).Parent =
		bar

	local slots: { [Tool]: TextButton } = {}
	local order: { Tool } = {}

	local function humanoid(): Humanoid?
		local character = player.Character
		return if character then character:FindFirstChildOfClass("Humanoid") else nil
	end

	local function equipped(tool: Tool): boolean
		return player.Character ~= nil and tool.Parent == player.Character
	end

	local function press(tool: Tool)
		local hum = humanoid()
		if not hum then
			return
		end
		if equipped(tool) then
			Net.send(Remotes.ToServer.UseTool, tool.Name)
		else
			hum:EquipTool(tool)
		end
	end

	local function refresh()
		local list: { Tool } = {}
		local seen: { [Tool]: boolean } = {}
		for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
			if container then
				for _, child in container:GetChildren() do
					if child:IsA("Tool") and isKind(child.Name) then
						table.insert(list, child)
						seen[child] = true
					end
				end
			end
		end
		table.sort(list, function(a: Tool, b: Tool): boolean
			if a.Name == "Bat" then
				return b.Name ~= "Bat"
			elseif b.Name == "Bat" then
				return false
			end
			return a.Name < b.Name
		end)
		for tool, slot in slots do
			if not seen[tool] then
				slot:Destroy()
				slots[tool] = nil
			end
		end
		order = list
		for i, tool in list do
			local slot = slots[tool]
			if not slot then
				local t = tool
				slot = Ui.button("", COLORS[t.Name] or C.gray, UDim2.fromOffset(88, 88), function()
					press(t)
				end, { parent = bar })
				drawTool(t.Name, slot)
				Ui.label(NAMES[t.Name] or t.Name, UDim2.new(1, -6, 0, 24), 18, C.white, {
					Name = "Caption",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -2),
					TextScaled = true,
					Parent = slot,
				})
				Ui.label(tostring(i), UDim2.fromOffset(24, 24), 18, C.white, {
					Name = "Key",
					Position = UDim2.fromOffset(4, 2),
					Visible = not touch,
					Parent = slot,
				})
				slots[t] = slot
			end
			local s = slot :: TextButton
			s.LayoutOrder = i
			local key = s:FindFirstChild("Key")
			if key and key:IsA("TextLabel") then
				key.Text = tostring(i)
			end
			local caption = s:FindFirstChild("Caption")
			if caption and caption:IsA("TextLabel") then
				local count = tool:GetAttribute("Count")
				caption.Text = (NAMES[tool.Name] or tool.Name)
					.. (if typeof(count) == "number" then " x" .. count else "")
			end
			local stroke = s:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if equipped(tool) then C.yellow else Theme.darker(COLORS[tool.Name] or C.gray, 0.35)
				stroke.Thickness = if equipped(tool) then 6 else 3
			end
		end
	end

	local function watch(container: Instance?)
		if not container then
			return
		end
		container.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") then
				child:GetAttributeChangedSignal("Count"):Connect(refresh)
			end
			task.defer(refresh)
		end)
		container.ChildRemoved:Connect(function()
			task.defer(refresh)
		end)
		for _, child in container:GetChildren() do
			if child:IsA("Tool") then
				child:GetAttributeChangedSignal("Count"):Connect(refresh)
			end
		end
	end

	watch(player:FindFirstChildOfClass("Backpack"))
	watch(player.Character)
	player.CharacterAdded:Connect(function(character: Model)
		watch(character)
		task.wait(0.2)
		watch(player:FindFirstChildOfClass("Backpack"))
		refresh()
	end)
	player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			watch(child)
			task.defer(refresh)
		end
	end)
	refresh()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		for i, key in KEYS do
			if input.KeyCode == key then
				local tool = order[i]
				local hum = humanoid()
				if tool and hum then
					if equipped(tool) then
						hum:UnequipTools()
					else
						hum:EquipTool(tool)
					end
				end
				return
			end
		end
	end)
end

return HotbarController
