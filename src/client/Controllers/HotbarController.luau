--!strict
--[[
	HotbarController — 아래 가운데 도구 핫바 (2판 원작: 작은 어두운 칸 · 1 방망이 · 2 곰덫 x3 · 3 알(들고 있을 때만))
	- 서버가 Backpack 에 넣어 준 Tool(이름 = Remotes.ToolKinds) 을 칸으로 보여 줌. 기본 Roblox 가방 UI 는 끔.
	- 칸 누르기(또는 숫자키 1~9): 손에 들기 ↔ 내려놓기. 든 상태에서 한 번 더 누르면 사용(UseTool).
	  손에 든 채 화면을 클릭/터치해도 ToolController 가 UseTool 을 보냄.
	- 알을 들고 있으면(플레이어 Attribute CarryingEgg) 마지막 칸에 알 그림 칸 (보기용, 누를 수 없음)
	- PC 는 아래 가운데. 터치 기기에서는 점프 버튼(오른쪽 아래) 왼쪽으로 비켜서, 조이스틱(왼쪽 아래)과도 안 겹치게.
	  칸이 많아 자리가 모자라면 배율을 줄임(칸 44px 까지). 규칙은 UI/Layout.luau.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Layout = require(Client.UI.Layout)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Tags = require(Shared.Tags)
local Ui = require(Client.UI.Ui)
local WeaponController = require(script.Parent.WeaponController)

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

local SLOT_COLOR = Color3.fromRGB(44, 46, 58)

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
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = color,
			Parent = parent,
		})
		Ui.corner(1).Parent = ring
		Ui.stroke(C.ink, 3).Parent = ring
		for i = 1, 6 do
			Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + math.cos(i) * 0.3, 0.5 + math.sin(i) * 0.3),
				Size = UDim2.fromOffset(6, 6),
				Rotation = 45,
				BackgroundColor3 = C.white,
				Parent = ring,
			})
		end
	else
		local stick: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(9, 44),
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

	local hud = Ui.layer("Hud")
	local bar: Frame = Ui.new("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Layout.HOTBAR_MARGIN, 1, -Layout.HOTBAR_MARGIN),
		Size = UDim2.fromOffset(Layout.SLOT, Layout.HOTBAR_HEIGHT),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	local barScale = Instance.new("UIScale")
	barScale.Name = "HotbarScale"
	barScale.Parent = bar
	Ui.list(
		Enum.FillDirection.Horizontal,
		Layout.SLOT_GAP,
		Enum.HorizontalAlignment.Right,
		Enum.VerticalAlignment.Bottom
	).Parent =
		bar

	local slots: { [Tool]: TextButton } = {}
	local order: { Tool } = {}
	local touch = Ui.isTouch()
	local slotCount = 0
	-- 알 칸 (보기용)
	local eggSlot: Frame = Ui.new("Frame", {
		Name = "EggSlot",
		Size = UDim2.fromOffset(Layout.SLOT, Layout.SLOT),
		BackgroundColor3 = SLOT_COLOR,
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = bar,
	})
	Ui.corner(10).Parent = eggSlot
	Ui.stroke(C.yellow, 3).Parent = eggSlot
	Icons.draw("egg", eggSlot, 44)
	Ui.label("", UDim2.fromOffset(18, 18), 14, C.white, {
		Name = "Key",
		Position = UDim2.fromOffset(3, 1),
		Parent = eggSlot,
	})

	-- 실제 점프 버튼(PlayerGui.TouchGui, 로블록스 PlayerModule 이 만듦)이 보이면 그 자리, 아니면 규칙대로
	local function realJump(): Layout.Rect?
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		if not (jump and jump:IsA("GuiObject") and jump.Visible) then
			return nil
		end
		local size = jump.AbsoluteSize
		if size.X < 1 then
			return nil
		end
		local origin = hud.AbsolutePosition
		return {
			x = jump.AbsolutePosition.X - origin.X,
			y = jump.AbsolutePosition.Y - origin.Y,
			w = size.X,
			h = size.Y,
		}
	end

	local function layout()
		touch = Ui.isTouch()
		local area = Ui.area()
		local jump: Layout.Rect? = nil
		if touch then
			local ok, found = pcall(realJump)
			if ok and found then
				-- 규칙 자리와 실제 자리 중 더 왼쪽까지 비움
				local rule = Layout.jumpZone(area)
				jump = if found.x < rule.x then found else rule
			end
		end
		local plan = Layout.hotbar(area, math.max(slotCount, #order), Ui.scale(), touch, 8, jump)
		barScale.Scale = plan.scale
		if touch then
			bar.AnchorPoint = Vector2.new(1, 1)
			bar.Position = UDim2.new(1, -plan.right, 1, -plan.bottom)
		else
			-- PC: 원작처럼 아래 가운데
			bar.AnchorPoint = Vector2.new(0.5, 1)
			bar.Position = UDim2.new(0.5, 0, 1, -plan.bottom)
		end
		bar.Size = UDim2.fromOffset(plan.baseWidth, Layout.HOTBAR_HEIGHT)
		for _, slot in slots do
			local key = slot:FindFirstChild("Key")
			if key and key:IsA("GuiObject") then
				key.Visible = not touch
			end
		end
	end
	Ui.onLayout(layout)
	-- 로블록스 터치 조작 화면(TouchGui)이 늦게 생기면 그 점프 버튼 자리에 맞춰 다시
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui.ChildAdded:Connect(function(gui: Instance)
			if gui.Name == "TouchGui" then
				task.delay(0.5, layout) -- 점프 버튼 크기·자리가 정해진 뒤
			end
		end)
	end

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
			WeaponController.swing(tool.Name) -- 손 모양 휘두르기 (보기만)
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
				local made = Ui.button("", SLOT_COLOR, UDim2.fromOffset(Layout.SLOT, Layout.SLOT), function()
					press(t)
				end, { parent = bar })
				made.BackgroundTransparency = 0.25
				drawTool(t.Name, made)
				Ui.label("", UDim2.new(1, -6, 0, 20), 16, C.white, {
					Name = "Caption",
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -3, 1, -2),
					TextXAlignment = Enum.TextXAlignment.Right,
					Parent = made,
				})
				Ui.label(tostring(i), UDim2.fromOffset(18, 18), 14, C.white, {
					Name = "Key",
					Position = UDim2.fromOffset(3, 1),
					Visible = not touch,
					Parent = made,
				})
				-- 마우스를 올리면 도구 이름 (원작 핫바처럼 평소엔 그림만)
				local tip = Ui.label(NAMES[t.Name] or t.Name, UDim2.fromOffset(120, 24), 18, C.white, {
					Name = "ToolName",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 0, -4),
					Visible = false,
					Parent = made,
				})
				made.MouseEnter:Connect(function()
					tip.Visible = true
				end)
				made.MouseLeave:Connect(function()
					tip.Visible = false
				end)
				slots[t] = made
				slot = made
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
				caption.Text = if typeof(count) == "number" then "x" .. count else ""
			end
			local stroke = s:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if equipped(tool) then C.white else C.winEdge
				stroke.Thickness = if equipped(tool) then 4 else 2
			end
		end
		-- 알 칸 (들고 있을 때만, 마지막 번호)
		local carry = player:GetAttribute(Tags.PlayerAttributes.CarryingEgg)
		local carrying = typeof(carry) == "string" and carry ~= ""
		eggSlot.Visible = carrying
		eggSlot.LayoutOrder = #list + 1
		local eggKey = eggSlot:FindFirstChild("Key")
		if eggKey and eggKey:IsA("TextLabel") then
			eggKey.Text = tostring(#list + 1)
			eggKey.Visible = not touch
		end
		slotCount = #list + (if carrying then 1 else 0)
		layout() -- 칸 수가 바뀌면 너비·배율 다시
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
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.CarryingEgg):Connect(refresh)

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
