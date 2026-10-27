--!strict
--[[
	HotbarController — 아래 가운데 도구 핫바 (2판 원작: 작은 어두운 칸 · 1 방망이 · 2 곰덫 x3 · 3 씨앗(들고 있을 때만)) — 6판 "씨앗을 훔치세요"
	- 서버가 Backpack 에 넣어 준 Tool(이름 = Remotes.ToolKinds) 을 칸으로 보여 줌. 기본 Roblox 가방 UI 는 끔.
	- 칸 누르기(또는 숫자키 1~9): 손에 들기 ↔ 내려놓기. 든 상태에서 한 번 더 누르면 사용(UseTool).
	  손에 든 채 화면을 클릭/터치해도 ToolController 가 UseTool 을 보냄.
	- 씨앗을 들고 있으면(플레이어 Attribute CarryingEgg) 도구 다음 칸에 씨앗 그림 칸 "EggSlot" (보기용, 누를 수 없음)
	- 5판 (사장님 지시 "얻은 씨앗은 핫바에 바로"): 가방 씨앗(State.get().eggs)이 도구 뒤에 칸으로 바로 보임 ("BagEgg_<uid>")
	    · 새로 얻은 씨앗이 맨 앞 (가장 최근 것부터), 최대 Layout.HOTBAR_EGG_MAX(6)칸 + 나머지는 "…n" 칸("MoreEggs" → 씨앗 창 가방 탭)
	    · 씨앗 칸을 누르면(클릭·톡·숫자키) 바로 씨앗 심기 모드 (IncubatorController.beginPlace: 초록/빨강 미리보기 → 클릭/톡으로 PlaceEgg)
	      같은 칸을 한 번 더 누르면 심기 취소. 심는 중인 씨앗 칸은 흰 테두리.
	    · 정원에 심은(자라는) 씨앗은 가방에서 빠지므로 핫바에도 안 보임 (성장 중 확인은 오른쪽 씨앗 버튼 창)
	    · 칸 테두리 = 등급 색, 씨앗 그림 = 식물 대표 색, 특별 씨앗 ★
	- PC 는 아래 가운데. 터치 기기에서는 점프 버튼(오른쪽 아래) 왼쪽으로 비켜서, 조이스틱(왼쪽 아래)과도 안 겹치게.
	  칸이 많아 자리가 모자라면 배율을 줄이고(칸 44px 까지), 그래도 모자라면 씨앗 칸 수를 줄임. 규칙은 UI/Layout.luau.
	공개: HotbarController.eggButtons() (튜토리얼 3단계가 반짝이게 함), HotbarController.refresh()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Data.Pets)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Visuals = require(Shared.Data.Visuals)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Layout = require(Client.UI.Layout)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Tags = require(Shared.Tags)
local Ui = require(Client.UI.Ui)
local WeaponController = require(script.Parent.WeaponController)
local IncubatorController = require(script.Parent.IncubatorController)

local HotbarController = {}
HotbarController.refresh = nil :: (() -> ())?

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

-- 핫바 한 칸이 하는 일 (숫자키 순서)
type Entry = {
	kind: string, -- "tool" | "carry" | "egg" | "more"
	tool: Tool?,
	uid: string?,
}

local eggButtonList: { GuiObject } = {}

-- 지금 보이는 가방 씨앗 칸 + "…n" 칸 (튜토리얼 3단계 강조용)
function HotbarController.eggButtons(): { GuiObject }
	return table.clone(eggButtonList)
end

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

-- 씨앗 그림 (식물 대표 색으로 칠함 — IncubatorController 씨앗 창과 같은 모양)
local function eggIcon(parent: GuiObject, petId: string, size: number): Frame
	local icon = Icons.draw("egg", parent, size)
	local ec = Visuals.petColor(petId, 1)
	for _, d in icon:GetDescendants() do
		if d:IsA("Frame") and d.BackgroundTransparency < 0.5 then
			d.BackgroundColor3 = Color3.fromRGB(ec[1], ec[2], ec[3])
			break
		end
	end
	return icon
end

local function rarityOf(petId: string): string
	local pet = Pets.get(petId)
	return if pet then pet.rarity else "common"
end

-- 씨앗 이름 ("아기 데이지 씨앗", 사쿠라 씨앗 2종은 seedName)
local function seedName(petId: string): string
	local pet = Pets.get(petId)
	if not pet then
		return petId .. " 씨앗"
	end
	return pet.seedName or (pet.name .. " 씨앗")
end

-- 가방 씨앗: 가장 최근에 얻은 씨앗부터 (새 씨앗이 바로 맨 앞 씨앗 칸에 보이게)
local function bagEggs(): { Types.BagEgg }
	local snap = State.get()
	local eggs = if snap then snap.eggs or {} else {}
	local list: { Types.BagEgg } = {}
	for i = #eggs, 1, -1 do
		table.insert(list, eggs[i])
	end
	return list
end

-- 마우스를 올리면 이름 (원작 핫바처럼 평소엔 그림만)
local function addTip(button: TextButton, text: string)
	local tip = Ui.label(text, UDim2.fromOffset(150, 24), 18, C.white, {
		Name = "ToolName",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Visible = false,
		Parent = button,
	})
	button.MouseEnter:Connect(function()
		tip.Visible = true
	end)
	button.MouseLeave:Connect(function()
		tip.Visible = false
	end)
end

local function keyLabel(parent: Instance, visible: boolean)
	Ui.label("", UDim2.fromOffset(18, 18), 14, C.white, {
		Name = "Key",
		Position = UDim2.fromOffset(3, 1),
		Visible = visible,
		Parent = parent,
	})
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
	local eggSlots: { [string]: TextButton } = {}
	local entries: { Entry } = {}
	local touch = Ui.isTouch()
	local slotCount = 0
	local knownEggs: { [string]: boolean }? = nil -- 처음 그린 뒤부터 새 씨앗 칸을 통통

	-- 든 씨앗 칸 (보기용)
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
	keyLabel(eggSlot, true)

	-- "…n" 칸: 핫바에 다 못 보인 가방 씨앗 → 씨앗 창 가방 탭
	local function openBag()
		local setTab = IncubatorController.setTab
		local panel = IncubatorController.panel
		local toggle = IncubatorController.toggle
		if panel and not panel.Visible and toggle then
			toggle()
		end
		if setTab then
			setTab("bag")
		end
	end
	local more = Ui.button("", SLOT_COLOR, UDim2.fromOffset(Layout.SLOT, Layout.SLOT), openBag, { parent = bar })
	more.Name = "MoreEggs"
	more.BackgroundTransparency = 0.25
	more.Visible = false
	Icons.draw("egg", more, 30, UDim2.fromScale(0.5, 0.36))
	Ui.label("…", UDim2.new(1, -6, 0, 26), 22, C.white, {
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Parent = more,
	})
	keyLabel(more, not touch)
	addTip(more, "씨앗 더 보기 (가방)")

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

	-- 지금 화면에서 핫바가 피해야 할 곳: 터치 = 점프 버튼 / PC = 왼쪽 아래 속도·돈 묶음
	local function bounds(): (Vector2, Layout.Rect?, number)
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
		local leftLimit = 8
		if not touch then
			local stats = Layout.statsRect(area, Ui.scale(), false)
			leftLimit = math.ceil(stats.x + stats.w + 8)
		end
		return area, jump, leftLimit
	end

	local function layout()
		local area, jump, leftLimit = bounds()
		local plan = Layout.hotbar(area, math.max(slotCount, 1), Ui.scale(), touch, leftLimit, jump)
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
		for _, child in bar:GetChildren() do
			local key = child:FindFirstChild("Key")
			if key and key:IsA("GuiObject") then
				key.Visible = not touch
			end
		end
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

	-- 씨앗 칸 누르기: 놓기 모드 시작 (같은 씨앗이면 취소)
	local function pressEgg(uid: string)
		if IncubatorController.placingUid() == uid then
			IncubatorController.cancelPlace()
			return
		end
		-- 손에 든 도구는 내려놓음 (클릭이 방망이 휘두르기로 가지 않게)
		local hum = humanoid()
		if hum then
			hum:UnequipTools()
		end
		IncubatorController.beginPlace(uid)
	end

	local function makeEggSlot(egg: Types.BagEgg): TextButton
		local uid = egg.uid
		local rid = rarityOf(egg.petId)
		local made = Ui.button("", SLOT_COLOR, UDim2.fromOffset(Layout.SLOT, Layout.SLOT), function()
			pressEgg(uid)
		end, { parent = bar })
		made.Name = "BagEgg_" .. uid
		made.BackgroundTransparency = 0.25
		made:SetAttribute("EggUid", uid)
		local stroke = made:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Theme.rarityColor(rid)
			stroke.Thickness = 3
		end
		eggIcon(made, egg.petId, 42)
		if egg.special then
			Ui.label("★", UDim2.fromOffset(20, 20), 18, C.yellow, {
				Name = "Special",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -2, 0, 1),
				Parent = made,
			})
		end
		keyLabel(made, not touch)
		addTip(made, seedName(egg.petId) .. " · 눌러서 정원에 심기")
		return made
	end

	local function refresh()
		-- 도구
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
		local newEntries: { Entry } = {}
		for _, tool in list do
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
				keyLabel(made, not touch)
				addTip(made, NAMES[t.Name] or t.Name)
				slots[t] = made
				slot = made
			end
			local s = slot :: TextButton
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
			table.insert(newEntries, { kind = "tool", tool = tool })
		end

		-- 든 씨앗 칸 (들고 있을 때만)
		local carry = player:GetAttribute(Tags.PlayerAttributes.CarryingEgg)
		local carrying = typeof(carry) == "string" and carry ~= ""
		eggSlot.Visible = carrying
		if carrying then
			table.insert(newEntries, { kind = "carry" })
		end

		-- 가방 씨앗 칸 (자리에 맞춰 최대 6칸 + "…n")
		local eggs = bagEggs()
		local area, jump, leftLimit = bounds()
		local capacity = Layout.hotbarCapacity(area, touch, leftLimit, jump)
		local shown, hasMore = Layout.hotbarEggs(capacity, #newEntries, #eggs)
		local placingUid = IncubatorController.placingUid()
		local want: { [string]: boolean } = {}
		local firstBuild = knownEggs == nil
		local known: { [string]: boolean } = knownEggs or {}
		table.clear(eggButtonList)
		for i = 1, shown do
			local egg = eggs[i]
			want[egg.uid] = true
			local slot = eggSlots[egg.uid]
			if not slot then
				slot = makeEggSlot(egg)
				eggSlots[egg.uid] = slot
			end
			local s = slot :: TextButton
			local stroke = s:FindFirstChildOfClass("UIStroke")
			if stroke then
				local active = placingUid == egg.uid
				stroke.Color = if active then C.white else Theme.rarityColor(rarityOf(egg.petId))
				stroke.Thickness = if active then 5 else 3
			end
			table.insert(newEntries, { kind = "egg", uid = egg.uid })
			table.insert(eggButtonList, s)
			if not firstBuild and not known[egg.uid] then
				Ui.pop(s, 1.35) -- 방금 얻은 씨앗
			end
		end
		for uid, slot in eggSlots do
			if not want[uid] then
				slot:Destroy()
				eggSlots[uid] = nil
			end
		end
		local nextKnown: { [string]: boolean } = {}
		for _, egg in eggs do
			nextKnown[egg.uid] = true
		end
		if State.get() ~= nil then
			knownEggs = nextKnown -- 첫 Snapshot 의 씨앗들은 통통 안 함 (그 뒤 새로 들어온 씨앗만)
		end
		more.Visible = hasMore
		if hasMore then
			local count = more:FindFirstChild("Count")
			if count and count:IsA("TextLabel") then
				count.Text = "+" .. tostring(#eggs - shown)
			end
			table.insert(newEntries, { kind = "more" })
			table.insert(eggButtonList, more)
		end

		-- 순서·번호 (숫자키 1~9 = 이 순서)
		entries = newEntries
		for i, entry in newEntries do
			local frame: GuiObject? = nil
			if entry.kind == "tool" and entry.tool then
				frame = slots[entry.tool]
			elseif entry.kind == "carry" then
				frame = eggSlot
			elseif entry.kind == "egg" and entry.uid then
				frame = eggSlots[entry.uid]
			elseif entry.kind == "more" then
				frame = more
			end
			if frame then
				frame.LayoutOrder = i
				local key = frame:FindFirstChild("Key")
				if key and key:IsA("TextLabel") then
					key.Text = if i <= #KEYS then tostring(i) else ""
					key.Visible = not touch
				end
			end
		end
		slotCount = #newEntries
		layout() -- 칸 수가 바뀌면 너비·배율 다시
	end
	HotbarController.refresh = refresh
	Ui.onLayout(refresh) -- 화면 크기가 바뀌면 들어가는 씨앗 칸 수도 다시
	-- 로블록스 터치 조작 화면(TouchGui)이 늦게 생기면 그 점프 버튼 자리에 맞춰 다시
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui.ChildAdded:Connect(function(gui: Instance)
			if gui.Name == "TouchGui" then
				task.delay(0.5, refresh) -- 점프 버튼 크기·자리가 정해진 뒤
			end
		end)
	end

	-- B-3: 도구마다 Count 연결은 한 번만 (가방 ↔ 손을 오가도 안 늘어남), 도구가 내 가방·손을 떠나면 끊음.
	-- 가방·캐릭터도 한 번만 지켜봄 (같은 가방을 두 곳에서 watch 해도 연결이 2배가 되지 않게)
	-- (몇 개 안 돼서 목록 + == 로 찾음. 인스턴스를 표 열쇠로 쓰지 않아 Lune 테스트에서도 같은 도구로 알아봄)
	type Tracked = { inst: Instance, conns: { RBXScriptConnection } }
	local tools: { Tracked } = {}
	local watched: { Tracked } = {}

	local function find(list: { Tracked }, inst: Instance): number?
		for i, t in list do
			if t.inst == inst then
				return i
			end
		end
		return nil
	end
	local function mine(tool: Tool): boolean
		local parent = tool.Parent
		return parent ~= nil and (parent:IsA("Backpack") or parent == player.Character)
	end
	local function track(tool: Tool)
		if find(tools, tool) == nil then
			table.insert(
				tools,
				{ inst = tool :: Instance, conns = { tool:GetAttributeChangedSignal("Count"):Connect(refresh) } }
			)
		end
	end
	local function untrack(tool: Tool)
		local i = find(tools, tool)
		if i and not mine(tool) then
			for _, c in tools[i].conns do
				c:Disconnect()
			end
			table.remove(tools, i)
		end
	end

	local function watch(container: Instance?)
		if not container or find(watched, container) then
			return
		end
		local conns: { RBXScriptConnection } = {}
		local entry: Tracked = { inst = container, conns = conns }
		table.insert(watched, entry)
		table.insert(
			conns,
			container.ChildAdded:Connect(function(child: Instance)
				if child:IsA("Tool") then
					track(child)
				end
				task.defer(refresh)
			end)
		)
		table.insert(
			conns,
			container.ChildRemoved:Connect(function(child: Instance)
				if child:IsA("Tool") then
					-- 옮겨 가는 중이면(가방 → 손) 새 부모가 정해진 뒤에 확인
					task.defer(untrack, child)
				end
				task.defer(refresh)
			end)
		)
		-- 가방·캐릭터가 없어지면(죽어서 다시 생김) 그 연결도 끊음
		table.insert(
			conns,
			container.Destroying:Connect(function()
				for _, c in conns do
					c:Disconnect()
				end
				local i = table.find(watched, entry)
				if i then
					table.remove(watched, i)
				end
				for _, child in container:GetChildren() do
					if child:IsA("Tool") then
						task.defer(untrack, child)
					end
				end
			end)
		)
		for _, child in container:GetChildren() do
			if child:IsA("Tool") then
				track(child)
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
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.CarryingEgg):Connect(refresh)
	-- 가방 씨앗이 바뀌면 (배달·선물 씨앗·놓기·다시 줍기) 씨앗 칸 다시
	State.onChanged(function(section: string)
		if section == "snapshot" or section == "eggs" then
			refresh()
		end
	end)
	IncubatorController.onPlaceChanged(refresh)
	refresh()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		for i, key in KEYS do
			if input.KeyCode == key then
				local entry = entries[i]
				if not entry then
					return
				end
				if entry.kind == "tool" and entry.tool then
					local tool = entry.tool
					local hum = humanoid()
					if hum then
						if equipped(tool) then
							hum:UnequipTools()
						else
							hum:EquipTool(tool)
						end
					end
				elseif entry.kind == "egg" and entry.uid then
					pressEgg(entry.uid)
				elseif entry.kind == "more" then
					openBag()
				end
				return
			end
		end
	end)
end

return HotbarController
