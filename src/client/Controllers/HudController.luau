--!strict
--[[
	HudController — 항상 보이는 화면
	- 상단: 돈($, K/M/B/T/Qa), 속도, 낮/밤 타이머 (GameState 기준 남은 초). 밤이면 빨갛게 + "밤! 알이 30배 빨리 자라요"
	- 상단 아래: 지금 있는 구역 / 안전 구역 표시
	- 왼쪽 세로 버튼: 도감 · 선물 · 상점 · 펫 · 설정 (각 창을 엶, 받을 보상이 있으면 빨간 배지)
	  + 다른 컨트롤러가 HudController.addMenuButton 으로 더하는 버튼 (6번 퀘스트 = QuestController)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Biomes = require(Shared.Data.Biomes)
local Format = require(Shared.Format)
local Progression = require(Shared.Progression)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local ZoneController = require(script.Parent.ZoneController)

local HudController = {}

local C = Theme.Colors
local Attr = Tags.PlayerAttributes

local function pill(width: number, color: Color3, parent: Instance, order: number): (Frame, TextLabel, Frame)
	local f: Frame = Ui.new("Frame", {
		Name = "Pill",
		Size = UDim2.fromOffset(width, 58),
		BackgroundColor3 = Theme.darker(color, 0.55),
		BackgroundTransparency = 0.15,
		LayoutOrder = order,
		Parent = parent,
	})
	Ui.corner(1).Parent = f
	Ui.stroke(C.white, 3).Parent = f
	local icon: Frame = Ui.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, 0),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = color,
		Parent = f,
	})
	Ui.corner(1).Parent = icon
	Ui.stroke(C.white, 2).Parent = icon
	local label = Ui.label("", UDim2.new(1, -66, 1, 0), 30, color, {
		Name = "Value",
		Position = UDim2.fromOffset(60, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Parent = f,
	})
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 32
	limit.Parent = label
	return f, label, icon
end

local function iconText(icon: Frame, text: string, size: number)
	Ui.label(text, UDim2.fromScale(1, 1), size, C.white, { Parent = icon })
end

-- 메뉴 버튼 그림 (기본 도형으로)
local function drawIcon(kind: string, parent: Instance)
	local holder: Frame = Ui.new("Frame", {
		Name = "Drawing",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(44, 40),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local shrink = Instance.new("UIScale")
	shrink.Scale = 0.85
	shrink.Parent = holder
	local function box(pos: UDim2, size: UDim2, color: Color3, round: number?): Frame
		local b: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = size,
			BackgroundColor3 = color,
			Parent = holder,
		})
		Ui.corner(round or 6).Parent = b
		Ui.stroke(C.ink, 2).Parent = b
		return b
	end
	if kind == "index" then
		box(UDim2.fromScale(0.3, 0.5), UDim2.fromOffset(20, 32), C.white, 4)
		box(UDim2.fromScale(0.7, 0.5), UDim2.fromOffset(20, 32), C.white, 4)
		box(UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(4, 34), C.red, 2)
	elseif kind == "gift" then
		box(UDim2.fromScale(0.5, 0.6), UDim2.fromOffset(34, 26), C.red, 4)
		box(UDim2.fromScale(0.5, 0.6), UDim2.fromOffset(7, 26), C.yellow, 2)
		box(UDim2.fromScale(0.5, 0.25), UDim2.fromOffset(38, 9), C.red, 3)
		box(UDim2.fromScale(0.35, 0.1), UDim2.fromOffset(12, 10), C.yellow, 1)
		box(UDim2.fromScale(0.65, 0.1), UDim2.fromOffset(12, 10), C.yellow, 1)
	elseif kind == "shop" then
		local coin = box(UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(36, 36), C.yellow, 1)
		Ui.label("$", UDim2.fromScale(1, 1), 26, C.white, { Parent = coin })
	elseif kind == "quest" then
		-- 두루마리
		box(UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(28, 34), Color3.fromRGB(255, 240, 200), 4)
		box(UDim2.fromScale(0.5, 0.12), UDim2.fromOffset(36, 8), Color3.fromRGB(190, 130, 70), 3)
		box(UDim2.fromScale(0.5, 0.88), UDim2.fromOffset(36, 8), Color3.fromRGB(190, 130, 70), 3)
		box(UDim2.fromScale(0.5, 0.42), UDim2.fromOffset(18, 3), C.mint, 1)
		box(UDim2.fromScale(0.5, 0.6), UDim2.fromOffset(18, 3), C.mint, 1)
	elseif kind == "pets" then
		box(UDim2.fromScale(0.5, 0.65), UDim2.fromOffset(24, 20), C.pink, 1)
		box(UDim2.fromScale(0.18, 0.35), UDim2.fromOffset(11, 13), C.pink, 1)
		box(UDim2.fromScale(0.4, 0.12), UDim2.fromOffset(11, 13), C.pink, 1)
		box(UDim2.fromScale(0.62, 0.12), UDim2.fromOffset(11, 13), C.pink, 1)
		box(UDim2.fromScale(0.84, 0.35), UDim2.fromOffset(11, 13), C.pink, 1)
	else
		local gear = box(UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(34, 34), C.gray, 1)
		gear.Rotation = 20
		box(UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(14, 14), C.white, 1)
	end
end

local function menuButton(kind: string, caption: string, order: number, parent: Instance, onClick: () -> ()): TextButton
	local color = (Theme.Menu :: { [string]: Color3 })[kind] or C.mint
	-- 6칸: 72px × HUD 최소 배율 0.7 = 50px (폰에서도 44px 이상), 세로 합 472 → 폰 330px
	local b = Ui.button(
		"",
		color,
		UDim2.fromOffset(72, 72),
		onClick,
		{ layoutOrder = order, parent = parent, sound = "Click" }
	)
	b.Name = kind
	drawIcon(kind, b)
	Ui.label(caption, UDim2.new(1, 0, 0, 22), 18, C.white, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Parent = b,
	})
	return b
end

-- 다른 컨트롤러가 왼쪽 메뉴에 버튼을 더함 (퀘스트 등). HUD 가 아직 안 만들어졌으면 만들어질 때 붙임.
type PendingButton = { kind: string, caption: string, order: number, onClick: () -> (), done: (TextButton) -> () }
local menuFrame: Frame? = nil
local pendingButtons: { PendingButton } = {}

function HudController.addMenuButton(
	kind: string,
	caption: string,
	order: number,
	onClick: () -> (),
	done: ((TextButton) -> ())?
)
	local entry: PendingButton = {
		kind = kind,
		caption = caption,
		order = order,
		onClick = onClick,
		done = done or function() end,
	}
	local menu = menuFrame
	if menu then
		entry.done(menuButton(kind, caption, order, menu, onClick))
	else
		table.insert(pendingButtons, entry)
	end
end

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

function HudController.start()
	local player = Players.LocalPlayer
	local hud = Ui.layer("Hud")

	------------------------------------------------------------------
	-- 상단 바
	------------------------------------------------------------------
	local top: Frame = Ui.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(780, 64),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	Ui.scaled(top)
	Ui.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent =
		top

	local _, moneyLabel, moneyIcon = pill(270, C.money, top, 1)
	iconText(moneyIcon, "$", 30)
	local _, speedLabel, speedIcon = pill(220, C.speed, top, 2)
	iconText(speedIcon, ">>", 22)
	local timerPill, timerLabel, timerIcon = pill(250, C.day, top, 3)
	local sunText = Ui.label("낮", UDim2.fromScale(1, 1), 22, C.white, { Parent = timerIcon })

	-- 밤 안내 띠
	local nightBanner: TextLabel = Ui.new("TextLabel", {
		Name = "NightBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.fromOffset(520, 44),
		BackgroundColor3 = C.night,
		TextColor3 = C.white,
		TextSize = 26,
		Text = "밤! 알이 30배 빨리 자라요",
		Visible = false,
		Parent = hud,
	})
	Ui.scaled(nightBanner)
	Ui.corner(1).Parent = nightBanner
	Ui.stroke(C.white, 3).Parent = nightBanner
	Ui.textStroke(2).Parent = nightBanner

	-- 구역 / 안전 구역 표시
	local zonePill: TextLabel = Ui.new("TextLabel", {
		Name = "ZonePill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.fromOffset(360, 38),
		BackgroundColor3 = C.green,
		BackgroundTransparency = 0.1,
		TextColor3 = C.white,
		TextSize = 22,
		Text = "",
		Visible = false,
		Parent = hud,
	})
	Ui.scaled(zonePill)
	Ui.corner(1).Parent = zonePill
	Ui.stroke(C.white, 2).Parent = zonePill
	Ui.textStroke(2).Parent = zonePill

	-- 돈: 숫자가 올라가는 애니메이션
	local shownMoney = Instance.new("NumberValue")
	shownMoney.Value = 0
	shownMoney.Changed:Connect(function(v: number)
		moneyLabel.Text = Format.money(v)
	end)
	local function refreshMoney()
		local m = player:GetAttribute(Attr.Money)
		local target = if typeof(m) == "number" then m else 0
		local old = shownMoney.Value
		if target > old * 1.5 + 100 then
			Ui.pop(moneyLabel, 1.25)
		end
		Ui.tween(shownMoney, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Value = target })
	end
	local function refreshSpeed()
		local s = player:GetAttribute(Attr.Speed)
		speedLabel.Text = "속도 " .. Format.number(if typeof(s) == "number" then s else 0)
	end
	player:GetAttributeChangedSignal(Attr.Money):Connect(refreshMoney)
	player:GetAttributeChangedSignal(Attr.Speed):Connect(function()
		refreshSpeed()
		Ui.pop(speedLabel, 1.12)
	end)
	refreshMoney()
	refreshSpeed()
	moneyLabel.Text = Format.money(shownMoney.Value)

	-- 타이머
	local zoneText = ""
	local function showZonePill()
		local night = nightBanner.Visible
		zonePill.Visible = zoneText ~= "" and not night
	end
	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild(Tags.StateFolderName, 60)
		while state do
			local phase = state:GetAttribute(Tags.StateAttributes.Phase)
			local endsAt = state:GetAttribute(Tags.StateAttributes.PhaseEndsAt)
			local left = if typeof(endsAt) == "number" then endsAt - Workspace:GetServerTimeNow() else 0
			local wasNight = nightBanner.Visible
			if phase == "Night" then
				timerLabel.Text = "밤 " .. clock(left)
				timerLabel.TextColor3 = C.white
				timerPill.BackgroundColor3 = Theme.darker(C.night, 0.1)
				timerIcon.BackgroundColor3 = Color3.fromRGB(60, 60, 120)
				sunText.Text = "밤"
				nightBanner.Visible = true
				nightBanner.Text = "밤! 알이 30배 빨리 자라요  " .. clock(left)
			elseif phase == "Intermission" then
				timerLabel.Text = "알 초기화! " .. clock(left)
				timerLabel.TextColor3 = C.yellow
				timerPill.BackgroundColor3 = Theme.darker(C.purple, 0.5)
				timerIcon.BackgroundColor3 = C.purple
				sunText.Text = "새벽"
				nightBanner.Visible = false
			else
				timerLabel.Text = "낮 " .. clock(left)
				timerLabel.TextColor3 = C.day
				timerPill.BackgroundColor3 = Theme.darker(C.day, 0.55)
				timerIcon.BackgroundColor3 = C.day
				sunText.Text = "낮"
				nightBanner.Visible = false
			end
			if nightBanner.Visible and not wasNight then
				Ui.pop(nightBanner, 1.3)
			end
			showZonePill()
			task.wait(0.25)
		end
	end)

	local function refreshZone(zone: string?)
		if zone == "base" then
			zoneText = if player:GetAttribute(Attr.InSafeZone) == true then "안전 구역 (베이스)" else "광장"
			zonePill.BackgroundColor3 = C.green
		elseif zone then
			local biome = Biomes.get(zone)
			zoneText = if biome
				then string.format(
					"%d. %s  ·  추천 속도 %s",
					biome.order,
					biome.name,
					Format.number(biome.recommendedSpeed)
				)
				else zone
			zonePill.BackgroundColor3 = C.orange
		else
			zoneText = if player:GetAttribute(Attr.InSafeZone) == true then "안전 구역 (베이스)" else ""
			zonePill.BackgroundColor3 = C.green
		end
		zonePill.Text = zoneText
		showZonePill()
	end
	ZoneController.changed(refreshZone)
	player:GetAttributeChangedSignal(Attr.InSafeZone):Connect(function()
		refreshZone(ZoneController.current())
	end)

	------------------------------------------------------------------
	-- 왼쪽 메뉴
	------------------------------------------------------------------
	local menu: Frame = Ui.new("Frame", {
		Name = "LeftMenu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(80, 480),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	Ui.scaled(menu)
	Ui.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent =
		menu

	local indexButton = menuButton("index", "도감", 1, menu, function()
		Windows.toggle("Index")
	end)
	local giftButton = menuButton("gift", "선물", 2, menu, function()
		Windows.toggle("Gift")
	end)
	menuButton("shop", "상점", 3, menu, function()
		Windows.toggle("Shop")
	end)
	menuButton("pets", "펫", 4, menu, function()
		Windows.toggle("Pets")
	end)
	menuButton("settings", "설정", 5, menu, function()
		Windows.toggle("Settings")
	end)
	local indexBadge = Ui.badge(indexButton)
	local giftBadge = Ui.badge(giftButton)
	menuFrame = menu
	for _, entry in pendingButtons do
		entry.done(menuButton(entry.kind, entry.caption, entry.order, menu, entry.onClick))
	end
	table.clear(pendingButtons)

	local function refreshBadges()
		local snap = State.get()
		if not snap then
			return
		end
		local ids = Progression.pendingRewards(snap.indexDiscovered or {}, snap.indexClaimed or {})
		indexBadge.Visible = #ids > 0
		indexBadge.Text = if #ids > 99 then "99+" else tostring(#ids)
		giftBadge.Visible = snap.freeRewardClaimed ~= true
		giftBadge.Text = "!"
	end
	State.onChanged(function(section: string)
		if section == "snapshot" or section == "index" or section == "flags" then
			refreshBadges()
		end
	end)
	refreshBadges()
	-- 배지 살짝 통통
	task.spawn(function()
		while true do
			task.wait(2)
			if indexBadge.Visible then
				Ui.pop(indexBadge, 1.3)
			end
			if giftBadge.Visible then
				Ui.pop(giftBadge, 1.3)
			end
		end
	end)
end

return HudController
