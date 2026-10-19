--!strict
--[[
	HudController — 항상 보이는 화면 (2판: 원작 Steal An Egg HUD 그대로)

	  왼쪽 가운데   : 상점(초록·카트) · 인덱스(하늘·책) · [다른 컨트롤러가 더한 버튼(퀘스트)] · 선물(받을 게 있을 때)
	                  · 슬로우 모드 토글(초록 네모) · 설정(톱니)
	  왼쪽 아래     : 신발 + 속도(빨강 큰 글씨) / 돈다발 + $돈(초록) / "친구 부스트: +10%"
	  오른쪽 가운데 : 주황 알 버튼(알 창 = 성장하는 달걀 패널, 배지 = 가방 알 + 부화 가능 수) · 주황 발바닥 버튼(펫 창)
	  오른쪽 아래   : 달/해 그림 + "3분 58초" (밤까지 / 낮까지 남은 시간)
	  위 가운데     : 구역 배너 "Jungle 😬" (ZoneEntered, 없으면 클라 구역 계산)

	반응형: PC 는 왼쪽 메뉴가 넓은 1열 버튼(글자 포함). 터치 기기는 정사각 아이콘 버튼(44px 이상)을 조이스틱 위에,
	속도·돈은 화면 위 왼쪽 한 줄로, 시간은 오른쪽 위로 옮김 (점프 버튼·조이스틱과 안 겹치게). 규칙 계산은 UI/Layout.luau.

	슬로우 모드: 켜면 내 캐릭터 Humanoid.WalkSpeed = 서버 WalkSpeed(플레이어 Attribute) ÷ 2 (내 화면에서만, 느려지기만 함).
	공개: HudController.addMenuButton / menuPlan / menuRight / toggleEggPanel 연결(IncubatorController 가 setEggPanelToggle)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Biomes = require(Shared.Data.Biomes)
local Format = require(Shared.Format)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Visuals = require(Shared.Data.Visuals)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Layout = require(Client.UI.Layout)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local ZoneController = require(script.Parent.ZoneController)
local SoundController = require(script.Parent.SoundController)

local HudController = {}
HudController.eggBadge = nil :: TextLabel? -- 알 버튼 배지 (IncubatorController 가 숫자를 씀)
HudController.showZoneBanner = nil :: ((string, string?) -> ())?

local C = Theme.Colors
local Attr = Tags.PlayerAttributes

-- 메뉴 버튼 (넓은 모드: 아이콘 + 글자 / 좁은 모드: 아이콘 + 작은 글자)
type MenuEntry = {
	button: TextButton,
	kind: string,
	caption: TextLabel,
	icon: Frame,
	toggle: Frame?,
}

local menuFrame: Frame? = nil
local menuScale: UIScale? = nil
local menuPlan: Layout.MenuPlan? = nil
local menuWide = true
local entries: { MenuEntry } = {}
type PendingButton = { kind: string, caption: string, order: number, onClick: () -> (), done: (TextButton) -> () }
local pendingButtons: { PendingButton } = {}
local eggPanelToggle: (() -> ())? = nil

local WIDE_W = 150 -- 넓은 버튼 기준 너비 (높이 = MENU_BASE * 0.72)
local ICONS: { [string]: string } = {
	shop = "cart",
	index = "book",
	quest = "scroll",
	gift = "gift",
	slow = "shoe",
	settings = "gear",
}

local function menuButton(kind: string, caption: string, order: number, parent: Instance, onClick: () -> ()): TextButton
	local color = (Theme.Menu :: { [string]: Color3 })[kind] or (if kind == "slow" then C.winDark else C.mint)
	local b = Ui.button("", color, UDim2.fromOffset(WIDE_W, Layout.MENU_BASE), onClick, {
		layoutOrder = order,
		anchor = Vector2.new(0, 0),
		sound = "Click",
	})
	b.Name = kind
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = C.winEdge
		stroke.Thickness = 3
	end
	b.Parent = parent
	local icon = Icons.draw(ICONS[kind] or "star", b, 34, UDim2.new(0, 26, 0.5, 0))
	local label = Ui.label(caption, UDim2.new(1, -52, 1, 0), 24, C.white, {
		Name = "Caption",
		Position = UDim2.fromOffset(50, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = b,
	})
	local entry: MenuEntry = { button = b, kind = kind, caption = label, icon = icon }
	if kind == "slow" then
		-- 원작: 어두운 알약 안 초록 네모 (켜지면 오른쪽으로)
		b.BackgroundTransparency = 0.25
		local track: Frame = Ui.new("Frame", {
			Name = "Toggle",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(40, 28),
			BackgroundColor3 = Color3.fromRGB(60, 62, 72),
			Parent = b,
		})
		Ui.corner(6).Parent = track
		Ui.stroke(C.winEdge, 2).Parent = track
		local knob: Frame = Ui.new("Frame", {
			Name = "Knob",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 2, 0.5, 0),
			Size = UDim2.fromOffset(18, 22),
			BackgroundColor3 = C.shopGreen,
			Parent = track,
		})
		Ui.corner(4).Parent = knob
		icon.Visible = false
		entry.toggle = track
	end
	table.insert(entries, entry)
	return b
end

-- 왼쪽 메뉴 다시 배치
local function layoutMenu()
	local menu = menuFrame
	local scale = menuScale
	if not menu or not scale then
		return
	end
	local visible: { MenuEntry } = {}
	for _, e in entries do
		if e.button.Parent == menu and e.button.Visible then
			table.insert(visible, e)
		end
	end
	table.sort(visible, function(a: MenuEntry, b: MenuEntry): boolean
		return a.button.LayoutOrder < b.button.LayoutOrder
	end)
	local area = Ui.area()
	local touch = Ui.isTouch()
	local small = math.min(area.X, area.Y) <= Layout.SMALL_SCREEN
	-- PC: 속도·돈 묶음(왼쪽 아래) 위까지 / 터치: 위쪽 한 줄 속도·돈 아래부터 조이스틱 위까지
	local statsH = (if touch then 48 else 150) * Ui.scale() -- 속도·돈 묶음 높이 (Ui.scaled 배율)
	local topLimit = if touch then math.ceil(statsH + 10) else nil
	local bottom = if touch then nil else area.Y - math.ceil(statsH) - 14
	local plan = Layout.menu(area, #visible, Ui.scale(), touch, nil, topLimit, bottom)
	local wide = not (touch and small) and plan.cols == 1
	menuWide = wide
	local base = Layout.MENU_BASE
	local h = if wide then math.floor(base * 0.72) else base
	local w = if wide then WIDE_W else base
	local gap = plan.gap / plan.scale
	scale.Scale = plan.scale
	-- 넓은 버튼은 높이가 낮으니 세로 가운데로 다시 맞춤
	local rows = plan.rows
	local totalH = (rows * h + (rows - 1) * gap) * plan.scale
	local y = plan.y
	if wide then
		local lo = if topLimit then topLimit else Layout.SAFE_TOP
		local hi = if bottom then bottom elseif touch then area.Y - Layout.joystickSize(area) - 4 else area.Y - 8
		y = math.max(lo, math.floor(lo + (hi - lo - totalH) * 0.42))
	end
	menu.Position = UDim2.fromOffset(plan.x, y)
	menu.Size = UDim2.fromOffset(plan.cols * w + (plan.cols - 1) * gap, rows * h + (rows - 1) * gap)
	for i, e in visible do
		local col, row = Layout.menuCell(plan, i - 1)
		e.button.Size = UDim2.fromOffset(w, h)
		e.button.Position = UDim2.fromOffset(col * (w + gap), row * (h + gap))
		e.caption.Visible = wide or e.kind == "slow"
		if wide then
			e.caption.Size = UDim2.new(1, -52, 1, 0)
			e.caption.Position = UDim2.fromOffset(50, 0)
			e.caption.TextSize = 24
			e.icon.Position = UDim2.new(0, 26, 0.5, 0)
		else
			e.caption.Size = UDim2.new(1, 0, 0, 20)
			e.caption.Position = UDim2.new(0, 0, 1, -22)
			e.caption.TextSize = 15
			e.icon.Position = UDim2.fromScale(0.5, 0.4)
		end
		local toggle = e.toggle
		if toggle then
			toggle.Position = if wide then UDim2.new(0, 8, 0.5, 0) else UDim2.new(0.5, -20, 0.36, 0)
			if not wide then
				e.caption.Text = "슬로우"
			else
				e.caption.Text = "슬로우 모드"
			end
			e.caption.Position = if wide then UDim2.fromOffset(52, 0) else e.caption.Position
		end
	end
	plan.size = math.floor(h * plan.scale + 0.5)
	menuPlan = plan
end

-- 지금 메뉴 배치 (테스트·다른 패널 자리 계산용)
function HudController.menuPlan(): Layout.MenuPlan?
	return menuPlan
end

function HudController.isMenuWide(): boolean
	return menuWide
end

-- 메뉴 오른쪽 끝 (화면 픽셀). 메뉴 옆에 붙는 패널(퀘스트 등)이 씀
function HudController.menuRight(): number
	local menu = menuFrame
	local plan = menuPlan
	if menu and plan then
		return plan.x + math.floor(menu.Size.X.Offset * plan.scale + 0.5)
	end
	local w = if menuWide then WIDE_W else Layout.MENU_BASE
	return Layout.SIDE + math.floor(w * Ui.scale())
end

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
		layoutMenu()
	else
		table.insert(pendingButtons, entry)
	end
end

-- IncubatorController 가 "성장하는 달걀" 패널 열고 닫기를 알려 줌
function HudController.setEggPanelToggle(fn: () -> ())
	eggPanelToggle = fn
end

-- 원작 시간 글자: "3분 58초" / "52초 안에"
local function koreanClock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local m = math.floor(s / 60)
	if m <= 0 then
		return string.format("%d초 안에", s)
	end
	return string.format("%d분 %d초", m, s % 60)
end
HudController.koreanClock = koreanClock

-- 굵은 외곽선 큰 글씨 (원작 HUD 숫자)
local function bigText(text: string, size: number, color: Color3, props: { [string]: any }): TextLabel
	local label = Ui.label(text, UDim2.fromOffset(260, size + 6), size, color, props)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = false
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = C.winEdge
		stroke.Thickness = math.max(2.5, size / 11)
	end
	return label
end

------------------------------------------------------------------
-- 슬로우 모드 (내 Humanoid.WalkSpeed 를 서버 값의 절반으로)
------------------------------------------------------------------

local slowOn = false
local function serverWalkSpeed(humanoid: Humanoid): number
	local v = Players.LocalPlayer:GetAttribute(Attr.WalkSpeed)
	if typeof(v) == "number" and v > 0 then
		return v
	end
	local base = humanoid:GetAttribute("BaseWalkSpeed")
	return if typeof(base) == "number" then base else humanoid.WalkSpeed
end

local applying = false
local function applySlow()
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or applying then
		return
	end
	applying = true
	local full = serverWalkSpeed(humanoid)
	local target = if slowOn then full / 2 else full
	if math.abs(humanoid.WalkSpeed - target) > 0.01 then
		humanoid.WalkSpeed = target
	end
	applying = false
end

function HudController.isSlow(): boolean
	return slowOn
end

function HudController.setSlow(on: boolean)
	slowOn = on
	applySlow()
end

local function hookSlow()
	local player = Players.LocalPlayer
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
				if slowOn and not applying then
					-- 서버가 속도를 다시 정하면(속도 업 등) 그 값의 절반으로 다시 맞춤
					local full = serverWalkSpeed(humanoid)
					if humanoid.WalkSpeed > full / 2 + 0.01 then
						applySlow()
					end
				end
			end)
			applySlow()
		end
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	player:GetAttributeChangedSignal(Attr.WalkSpeed):Connect(applySlow)
end

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------

function HudController.start()
	local player = Players.LocalPlayer
	local hud = Ui.layer("Hud")

	------------------------------------------------------------------
	-- 왼쪽 아래: 속도 / 돈 / 친구 부스트
	------------------------------------------------------------------
	local stats: Frame = Ui.new("Frame", {
		Name = "Stats",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -6),
		Size = UDim2.fromOffset(330, 150),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	Ui.scaled(stats)
	local speedRow: Frame = Ui.new("Frame", {
		Name = "SpeedRow",
		Size = UDim2.fromOffset(330, 48),
		BackgroundTransparency = 1,
		Parent = stats,
	})
	Icons.draw("shoe", speedRow, 46, UDim2.fromOffset(24, 24))
	local speedLabel =
		bigText("0", 40, C.speedRed, { Name = "Speed", Position = UDim2.fromOffset(54, 0), Parent = speedRow })
	local moneyRow: Frame = Ui.new("Frame", {
		Name = "MoneyRow",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.fromOffset(330, 48),
		BackgroundTransparency = 1,
		Parent = stats,
	})
	Icons.draw("money", moneyRow, 46, UDim2.fromOffset(24, 24))
	local moneyLabel =
		bigText("$0", 40, C.moneyGreen, { Name = "Money", Position = UDim2.fromOffset(54, 0), Parent = moneyRow })
	local boost = bigText(
		"친구 부스트: +10%",
		30,
		C.white,
		{ Name = "FriendBoost", Position = UDim2.fromOffset(2, 104), Parent = stats }
	)
	boost.Size = UDim2.fromOffset(330, 40)

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
			Ui.pop(moneyLabel, 1.2)
		end
		Ui.tween(shownMoney, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Value = target })
	end
	local function refreshSpeed()
		local s = player:GetAttribute(Attr.Speed)
		speedLabel.Text = Format.number(if typeof(s) == "number" then s else 0)
	end
	player:GetAttributeChangedSignal(Attr.Money):Connect(refreshMoney)
	player:GetAttributeChangedSignal(Attr.Speed):Connect(function()
		refreshSpeed()
		Ui.pop(speedLabel, 1.1)
	end)
	refreshMoney()
	refreshSpeed()
	moneyLabel.Text = Format.money(shownMoney.Value)

	------------------------------------------------------------------
	-- 오른쪽 아래: 낮/밤 남은 시간
	------------------------------------------------------------------
	local timer: Frame = Ui.new("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -8),
		Size = UDim2.fromOffset(250, 56),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	Ui.scaled(timer)
	local moon = Icons.draw("moon", timer, 46, UDim2.fromOffset(24, 28))
	local sun = Icons.draw("sun", timer, 44, UDim2.fromOffset(24, 28))
	local timerLabel =
		bigText("", 36, C.white, { Name = "TimeLeft", Position = UDim2.fromOffset(54, 8), Parent = timer })
	timerLabel.Size = UDim2.fromOffset(196, 42)

	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild(Tags.StateFolderName, 60)
		while state do
			local phase = state:GetAttribute(Tags.StateAttributes.Phase)
			local endsAt = state:GetAttribute(Tags.StateAttributes.PhaseEndsAt)
			local left = if typeof(endsAt) == "number" then endsAt - Workspace:GetServerTimeNow() else 0
			local night = phase == "Night"
			-- 낮이면 "밤까지" → 달 그림 / 밤이면 "낮까지" → 해 그림 (원작과 같음)
			moon.Visible = not night
			sun.Visible = night
			timerLabel.Text = koreanClock(left)
			timerLabel.TextColor3 = if phase == "Intermission"
				then C.yellow
				elseif night then Color3.fromRGB(255, 225, 120)
				else C.white
			task.wait(0.25)
		end
	end)

	------------------------------------------------------------------
	-- 오른쪽 가운데: 알 버튼 / 발바닥 버튼
	------------------------------------------------------------------
	local right: Frame = Ui.new("Frame", {
		Name = "RightButtons",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.46, 0),
		Size = UDim2.fromOffset(72, 156),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	Ui.scaled(right)
	local function squareButton(name: string, color: Color3, icon: string, y: number, onClick: () -> ()): TextButton
		local b = Ui.button(
			"",
			color,
			UDim2.fromOffset(70, 70),
			onClick,
			{ position = UDim2.fromOffset(1, y), parent = right }
		)
		b.Name = name
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = C.winEdge
			stroke.Thickness = 4
		end
		local corner = b:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, 6)
		end
		Icons.draw(icon, b, 50)
		return b
	end
	local eggButton = squareButton("EggButton", C.eggRed, "egg", 0, function()
		local fn = eggPanelToggle
		if fn then
			fn()
		end
	end)
	squareButton("PetsButton", C.pawOrange, "paw", 84, function()
		Windows.toggle("Pets")
	end)
	local eggBadge = Ui.badge(eggButton)
	eggBadge.BackgroundColor3 = C.shopGreen
	eggBadge.Position = UDim2.new(1, -4, 1, -4)
	HudController.eggBadge = eggBadge

	------------------------------------------------------------------
	-- 위 가운데: 구역 배너 ("Jungle 😬")
	------------------------------------------------------------------
	local zoneBanner = Ui.label("", UDim2.fromOffset(600, 70), 60, C.white, {
		Name = "ZoneBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Visible = false,
		Parent = Ui.layer("Alerts"),
	})
	Ui.scaled(zoneBanner)
	local zbStroke = zoneBanner:FindFirstChildOfClass("UIStroke")
	if zbStroke then
		zbStroke.Color = C.winEdge
		zbStroke.Thickness = 5
	end
	local bannerToken = 0
	local function showZone(nameEn: string, biomeId: string?)
		local theme = if biomeId then Visuals.biomes[biomeId] else nil
		local label = if theme then theme.label else ""
		local color = if theme then Color3.fromRGB(theme.accent[1], theme.accent[2], theme.accent[3]) else C.shopGreen
		zoneBanner.Text = nameEn .. " " .. label
		zoneBanner.TextColor3 = color:Lerp(C.white, 0.15)
		zoneBanner.Visible = true
		bannerToken += 1
		local token = bannerToken
		Ui.pop(zoneBanner, 1.35)
		SoundController.play("ZoneEnter")
		task.delay(2.6, function()
			if bannerToken == token then
				zoneBanner.Visible = false
			end
		end)
	end
	HudController.showZoneBanner = showZone
	local serverBanner = false
	Net.onLater(Remotes.ToClient.ZoneEntered, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		serverBanner = true
		local id = if typeof(payload.biomeId) == "string" then payload.biomeId else nil
		local biome = if id then Biomes.get(id) else nil
		local nameEn = tostring(payload.nameEn or (if biome then biome.nameEn else ""))
		if id == "hub" or nameEn == "" then
			return
		end
		showZone(nameEn, id)
	end)
	-- 서버 ZoneEntered 가 아직 안 오면(구 서버) 클라 구역 계산으로
	ZoneController.changed(function(zone: string?)
		if serverBanner or zone == nil or zone == "base" then
			return
		end
		local biome = Biomes.get(zone)
		if biome then
			showZone(biome.nameEn, zone)
		end
	end)

	------------------------------------------------------------------
	-- 왼쪽 메뉴
	------------------------------------------------------------------
	local menu: Frame = Ui.new("Frame", {
		Name = "LeftMenu",
		Position = UDim2.fromOffset(Layout.SIDE, Layout.SAFE_TOP),
		Size = UDim2.fromOffset(WIDE_W, Layout.MENU_BASE),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	local scale = Instance.new("UIScale")
	scale.Name = "MenuScale"
	scale.Parent = menu
	menuScale = scale

	menuButton("shop", "상점", 1, menu, function()
		Windows.toggle("Shop")
	end)
	local indexButton = menuButton("index", "인덱스", 2, menu, function()
		Windows.toggle("Index")
	end)
	local giftButton = menuButton("gift", "선물", 4, menu, function()
		Windows.toggle("Gift")
	end)
	local slowButton: TextButton
	slowButton = menuButton("slow", "슬로우 모드", 8, menu, function()
		HudController.setSlow(not slowOn)
		local track = slowButton:FindFirstChild("Toggle")
		local knob = track and track:FindFirstChild("Knob")
		if knob and knob:IsA("Frame") then
			Ui.tween(knob, Theme.Tween.fast, {
				Position = if slowOn then UDim2.new(1, -20, 0.5, 0) else UDim2.new(0, 2, 0.5, 0),
			})
		end
		if track and track:IsA("Frame") then
			track.BackgroundColor3 = if slowOn then Color3.fromRGB(40, 120, 40) else Color3.fromRGB(60, 62, 72)
		end
	end)
	menuButton("settings", "설정", 9, menu, function()
		Windows.toggle("Settings")
	end)
	local indexBadge = Ui.badge(indexButton)
	menuFrame = menu
	for _, entry in pendingButtons do
		entry.done(menuButton(entry.kind, entry.caption, entry.order, menu, entry.onClick))
	end
	table.clear(pendingButtons)

	-- 터치 기기: 속도·돈을 위쪽 한 줄로, 시간은 오른쪽 위로 (조이스틱·점프 버튼 자리 비움)
	local function layoutCorners()
		local touch = Ui.isTouch()
		local area = Ui.area()
		local small = math.min(area.X, area.Y) <= Layout.SMALL_SCREEN
		if touch then
			stats.AnchorPoint = Vector2.new(0, 0)
			stats.Position = UDim2.fromOffset(10, 4)
			stats.Size = UDim2.fromOffset(520, 48)
			moneyRow.Position = UDim2.fromOffset(250, 0)
			boost.Visible = false
			timer.AnchorPoint = Vector2.new(1, 0)
			timer.Position = UDim2.new(1, -12, 0, 4)
			right.Position = UDim2.new(1, -12, if small then 0.42 else 0.46, 0)
		else
			stats.AnchorPoint = Vector2.new(0, 1)
			stats.Position = UDim2.new(0, 10, 1, -6)
			stats.Size = UDim2.fromOffset(330, 150)
			moneyRow.Position = UDim2.fromOffset(0, 50)
			boost.Visible = true
			timer.AnchorPoint = Vector2.new(1, 1)
			timer.Position = UDim2.new(1, -12, 1, -8)
			right.Position = UDim2.new(1, -12, 0.46, 0)
		end
	end
	local function relayoutAll()
		layoutCorners()
		layoutMenu()
	end
	relayoutAll()
	Ui.onLayout(relayoutAll)

	local function refreshBadges()
		local snap = State.get()
		if not snap then
			return
		end
		local ids = Progression.pendingRewards(snap.indexDiscovered or {}, snap.indexClaimed or {})
		indexBadge.Visible = #ids > 0
		indexBadge.Text = if #ids > 99 then "99+" else tostring(#ids)
		local giftVisible = snap.freeRewardClaimed ~= true
		if giftButton.Visible ~= giftVisible then
			giftButton.Visible = giftVisible
			layoutMenu()
		end
	end
	State.onChanged(function(section: string)
		if section == "snapshot" or section == "index" or section == "flags" then
			refreshBadges()
		end
	end)
	refreshBadges()
	hookSlow()

	-- 배지 살짝 통통
	task.spawn(function()
		while true do
			task.wait(2)
			if indexBadge.Visible then
				Ui.pop(indexBadge, 1.3)
			end
			if eggBadge.Visible then
				Ui.pop(eggBadge, 1.3)
			end
		end
	end)
end

return HudController
