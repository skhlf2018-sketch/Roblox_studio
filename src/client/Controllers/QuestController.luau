--!strict
--[[
	QuestController — 마법의 숲 퀘스트 패널 + 퀘스트 문 연출
	- 왼쪽 메뉴 "퀘스트" 버튼(HudController.addMenuButton)으로 패널 열고 닫기
	- 마법의 숲 구역에 들어가면 패널이 저절로 보이고, 나가면 (직접 연 게 아니면) 숨김
	- 진행도 막대 3개: State.quests / QuestUpdate { quests, allDone, gateOpen }
	- 퀘스트 문(Tag QuestGate): 문 앞 룬 돌 3개(Rune1~3)가 끝낸 퀘스트만큼 빛남 (내 화면)
	  Attr QuestsDone 이 true 가 되는 순간 → 문이 열리는 연출(빛기둥·반짝·문이 투명해짐). 이미 끝낸 사람은 처음부터 반투명.
	  실제로 지나갈 수 있는지는 서버 CollisionGroup 이 정함 (클라는 보기만).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Quests = require(Shared.Data.Quests)
local Pets = require(Shared.Data.Pets)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Fx = require(Client.UI.Fx)
local SoundController = require(script.Parent.SoundController)
local NotifyController = require(script.Parent.NotifyController)
local ZoneController = require(script.Parent.ZoneController)
local HudController = require(script.Parent.HudController)

local QuestController = {}

local C = Theme.Colors
local GLOW = Color3.fromRGB(110, 255, 220)
local RUNE_OFF = Color3.fromRGB(70, 60, 90)

type Row = { bar: Frame, count: TextLabel, check: TextLabel, frame: Frame }

local function questsDone(): boolean
	return Players.LocalPlayer:GetAttribute(Tags.PlayerAttributes.QuestsDone) == true
end

-- 퀘스트 목록 (서버가 보낸 것이 없으면 데이터 표로 0 진행)
local function currentViews(): { Types.QuestView }
	local snap = State.get()
	local views = if snap then snap.quests else nil
	if typeof(views) == "table" and #views > 0 then
		return views
	end
	local list: { Types.QuestView } = {}
	for _, quest in Quests.list do
		table.insert(list, { id = quest.id, name = quest.name, progress = 0, target = quest.target, done = false })
	end
	return list
end

local function gateParts(): { BasePart }
	local list: { BasePart } = {}
	for _, inst in CollectionService:GetTagged(Tags.QuestGate) do
		if inst:IsA("BasePart") then
			table.insert(list, inst)
		end
	end
	return list
end

-- 룬 돌 색 + 문 투명도 (내 화면만)
local function paintGates(views: { Types.QuestView }, opened: boolean)
	local doneCount = 0
	for _, view in views do
		if view.done then
			doneCount += 1
		end
	end
	for _, door in gateParts() do
		local model = door.Parent
		if model and model:IsA("Model") then
			for i = 1, 3 do
				local rune = model:FindFirstChild("Rune" .. i)
				if rune and rune:IsA("BasePart") then
					local lit = opened or i <= doneCount
					rune.Color = if lit then GLOW else RUNE_OFF
					rune.Material = if lit then Enum.Material.Neon else Enum.Material.Slate
				end
			end
		end
		if opened then
			door.LocalTransparencyModifier = 0.7
		end
	end
end

local function openGateFx()
	SoundController.play("GateOpen")
	NotifyController.banner("퀘스트 문이 열렸어요! 숲 속 정원으로!", C.mint)
	for _, door in gateParts() do
		Fx.pillar(door.Position - Vector3.new(0, door.Size.Y / 2, 0), GLOW, 80, 3)
		Fx.burst(door.Position, GLOW, 80, 1.3, 18)
		Fx.flash(door.Position, GLOW, 50, 2)
		door.LocalTransparencyModifier = 0
		local value = Instance.new("NumberValue")
		value.Value = 0
		value.Changed:Connect(function(v: number)
			door.LocalTransparencyModifier = v
		end)
		local tween = TweenService:Create(value, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { Value = 0.7 })
		tween.Completed:Connect(function()
			value:Destroy()
		end)
		tween:Play()
	end
end

function QuestController.start()
	------------------------------------------------------------------
	-- 패널
	------------------------------------------------------------------
	local panel: Frame = Ui.new("Frame", {
		Name = "QuestPanel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, HudController.menuRight() + 8, 0.5, 0), -- 메뉴 옆 (메뉴가 2열이 되면 따라감)
		Size = UDim2.fromOffset(340, 60),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = Ui.layer("Panels"),
	})
	Ui.scaled(panel)
	Ui.onLayout(function()
		panel.Position = UDim2.new(0, HudController.menuRight() + 8, 0.5, 0)
	end)
	Ui.corner(20).Parent = panel
	Ui.stroke(C.mint, 4).Parent = panel
	Ui.padding(10).Parent = panel
	Ui.list(Enum.FillDirection.Vertical, 6).Parent = panel

	local header: Frame = Ui.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = C.mint,
		LayoutOrder = 0,
		Parent = panel,
	})
	Ui.corner(14).Parent = header
	Ui.label("마법의 숲 퀘스트", UDim2.new(1, -76, 1, 0), 24, C.white, {
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	local openedByUser = false
	local closeButton = Ui.button("X", C.red, UDim2.fromOffset(60, 60), nil, {
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -2, 0.5, 0),
		textSize = 26,
		parent = header,
		sound = "Close",
	})

	local rows: { [string]: Row } = {}
	local function makeRow(view: Types.QuestView, order: number): Row
		local f: Frame = Ui.new("Frame", {
			Name = view.id,
			Size = UDim2.new(1, 0, 0, 62),
			BackgroundColor3 = C.white,
			LayoutOrder = order,
			Parent = panel,
		})
		Ui.corner(12).Parent = f
		Ui.stroke(Theme.darker(C.mint, 0.2), 2).Parent = f
		Ui.label(view.name, UDim2.new(1, -60, 0, 26), 18, C.ink, {
			Position = UDim2.fromOffset(10, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
			Parent = f,
		})
		local back: Frame = Ui.new("Frame", {
			Position = UDim2.fromOffset(10, 36),
			Size = UDim2.new(1, -110, 0, 16),
			BackgroundColor3 = Color3.fromRGB(225, 220, 210),
			Parent = f,
		})
		Ui.corner(1).Parent = back
		local bar: Frame = Ui.new("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.mint,
			Parent = back,
		})
		Ui.corner(1).Parent = bar
		local count = Ui.label("", UDim2.fromOffset(80, 24), 18, C.ink, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 32),
			Parent = f,
		})
		local check: TextLabel = Ui.new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 4),
			Size = UDim2.fromOffset(40, 26),
			BackgroundColor3 = C.green,
			TextColor3 = C.white,
			TextSize = 18,
			Text = "완료",
			Visible = false,
			Parent = f,
		})
		Ui.corner(1).Parent = check
		return { bar = bar, count = count, check = check, frame = f }
	end
	local footer = Ui.label("", UDim2.new(1, 0, 0, 44), 17, C.ink, {
		Name = "Footer",
		LayoutOrder = 10,
		TextScaled = true,
		Parent = panel,
	})

	local lastDone: { [string]: boolean } = {}
	local menuBadge: TextLabel? = nil

	local function render(views: { Types.QuestView }, gateOpen: boolean, announce: boolean?)
		for i, view in views do
			local row = rows[view.id]
			if not row then
				row = makeRow(view, i)
				rows[view.id] = row
			end
			local r = row :: Row
			local target = math.max(1, view.target)
			local progress = math.min(view.progress, target)
			Ui.tween(r.bar, Theme.Tween.fast, { Size = UDim2.fromScale(progress / target, 1) })
			r.bar.BackgroundColor3 = if view.done then C.green else C.mint
			r.count.Text = string.format("%d/%d", progress, target)
			r.check.Visible = view.done
			if announce and view.done and not lastDone[view.id] then
				SoundController.play("QuestStep")
				NotifyController.toast("퀘스트 완료: " .. view.name, "success")
				Ui.pop(r.frame, 1.12)
				local badge = menuBadge
				if badge and not panel.Visible then
					badge.Visible = true
				end
			end
			lastDone[view.id] = view.done
		end
		local secret = Pets.get(Quests.SECRET_EGG)
		local reward = Pets.get(Quests.REWARD_EGG)
		footer.Text = if gateOpen
			then "문이 열렸어요! 가끔 "
				.. (if secret then secret.name else "영혼 세계 수호자")
				.. " 알이 나타나요 (나만 주울 수 있음)"
			else "3개를 다 끝내면 문이 열리고 "
				.. (if reward then reward.name else "지터버그")
				.. " 알을 받아요!"
		footer.TextColor3 = if gateOpen then Theme.darker(C.green, 0.2) else C.ink
		paintGates(views, gateOpen)
	end

	local function setVisible(on: boolean)
		if panel.Visible == on then
			return
		end
		panel.Visible = on
		if on then
			Ui.pop(panel, 1.1)
			local badge = menuBadge
			if badge then
				badge.Visible = false
			end
		end
	end

	closeButton.Activated:Connect(function()
		openedByUser = false
		setVisible(false)
	end)

	HudController.addMenuButton("quest", "퀘스트", 6, function()
		openedByUser = not panel.Visible
		setVisible(not panel.Visible)
	end, function(button: TextButton)
		menuBadge = Ui.badge(button)
	end)

	-- 마법의 숲 근처(구역 안)에서 자동 표시
	ZoneController.changed(function(zone: string?)
		if zone == Quests.BIOME then
			setVisible(true)
		elseif not openedByUser then
			setVisible(false)
		end
	end)

	State.onChanged(function(section: string)
		if section == "quests" or section == "snapshot" then
			render(currentViews(), questsDone())
		end
	end)
	Net.on(Remotes.ToClient.QuestUpdate, function(payload: any)
		if typeof(payload) == "table" and typeof(payload.quests) == "table" then
			render(payload.quests, payload.gateOpen == true or questsDone(), true)
		end
	end)

	-- 문 열림 순간
	local wasDone = questsDone()
	Players.LocalPlayer:GetAttributeChangedSignal(Tags.PlayerAttributes.QuestsDone):Connect(function()
		local now = questsDone()
		if now and not wasDone then
			openGateFx()
		end
		wasDone = now
		render(currentViews(), now)
	end)
	CollectionService:GetInstanceAddedSignal(Tags.QuestGate):Connect(function()
		task.defer(function()
			paintGates(currentViews(), questsDone())
		end)
	end)
	render(currentViews(), questsDone())
end

return QuestController
