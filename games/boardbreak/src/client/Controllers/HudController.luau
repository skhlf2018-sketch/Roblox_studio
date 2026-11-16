--!strict
--[[
	HudController — 늘 보이는 화면 (선임, 첫 게임 HudController 를 줄여 복사)

	  왼쪽 아래 (PC) / 위 왼쪽 한 줄 (터치): 💪 힘 (빨강 큰 글씨) + "×8" 힘 배수 배지 · 💰 돈 (금색) · 지금 띠 (색 띠 + 이름)
	  왼쪽 가운데: 메뉴 버튼 (다른 컨트롤러가 HudController.addMenuButton 으로 더함)
	      아령 가게(1) · 도감(2) · 힘 배수(3) · 띠·심사(4) · 설정(5)
	  숫자는 Format.number (K M B T Qa Qi Sx Sp …). 값은 플레이어 Attribute (Power · Money · Belt · PowerBoost) → 없으면 Snapshot.

	반응형: 메뉴는 UI/Layout.menu (손가락 46px 이상, 터치면 조이스틱 위·힘 줄 아래), 화면이 바뀌면 Ui.onLayout 으로 다시 배치.
	공개: addMenuButton · menuButton(kind) · menuPlan() · statsFrame() · refresh()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Belts = require(Shared.Data.Belts)
local Format = require(Shared.Format)
local Client = script.Parent.Parent
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Layout = require(Client.UI.Layout)
local Ui = require(Client.UI.Ui)

local HudController = {}

local C = Theme.Colors

type MenuEntry = { button: TextButton, kind: string, caption: TextLabel, icon: Frame }
type Pending = { kind: string, caption: string, order: number, onClick: () -> () }

local ICONS: { [string]: string } = {
	shop = "dumbbell",
	index = "book",
	boost = "bolt",
	belt = "belt",
	settings = "gear",
}

local menuFrame: Frame? = nil
local menuScale: UIScale? = nil
local menuPlan: Layout.MenuPlan? = nil
local entries: { MenuEntry } = {}
local pending: { Pending } = {}
local stats: Frame? = nil
local refreshFn: (() -> ())? = nil

local BASE = Layout.MENU_BASE

local function menuButton(kind: string, caption: string, order: number, parent: Instance, onClick: () -> ()): TextButton
	local color = (Theme.Menu :: { [string]: Color3 })[kind] or C.mint
	local b = Ui.button("", color, UDim2.fromOffset(BASE, BASE), onClick, { layoutOrder = order, sound = "Click" })
	b.Name = kind
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = C.winEdge
	end
	b.Parent = parent
	local icon = Icons.draw(ICONS[kind] or "star", b, 36, UDim2.fromScale(0.5, 0.4))
	local label = Ui.label(caption, UDim2.new(1, 0, 0, 20), 16, C.white, {
		Name = "Caption",
		Position = UDim2.new(0, 0, 1, -22),
		TextScaled = true,
		Parent = b,
	})
	table.insert(entries, { button = b, kind = kind, caption = label, icon = icon })
	return b
end

local function layoutMenu()
	local menu = menuFrame
	local scale = menuScale
	if not menu or not scale then
		return
	end
	local visible: { MenuEntry } = {}
	for _, e in entries do
		if e.button.Visible then
			table.insert(visible, e)
		end
	end
	table.sort(visible, function(a: MenuEntry, b: MenuEntry): boolean
		return a.button.LayoutOrder < b.button.LayoutOrder
	end)
	local area = Ui.area()
	local touch = Ui.isTouch()
	local s = Layout.statsRect(area, Ui.scale(), touch)
	local topLimit = if touch then math.ceil(s.y + s.h + 10) else nil
	local bottom = if touch then nil else math.floor(s.y - 12)
	local plan = Layout.menu(area, #visible, Ui.scale(), touch, nil, topLimit, bottom)
	scale.Scale = plan.scale
	local gap = plan.gap / plan.scale
	menu.Position = UDim2.fromOffset(plan.x, plan.y)
	menu.Size = UDim2.fromOffset(plan.cols * BASE + (plan.cols - 1) * gap, plan.rows * BASE + (plan.rows - 1) * gap)
	for i, e in visible do
		local col, row = Layout.menuCell(plan, i - 1)
		e.button.Size = UDim2.fromOffset(BASE, BASE)
		e.button.Position = UDim2.fromOffset(col * (BASE + gap), row * (BASE + gap))
	end
	menuPlan = plan
end

function HudController.addMenuButton(kind: string, caption: string, order: number, onClick: () -> ())
	local menu = menuFrame
	if menu then
		menuButton(kind, caption, order, menu, onClick)
		layoutMenu()
	else
		table.insert(pending, { kind = kind, caption = caption, order = order, onClick = onClick })
	end
end

function HudController.menuButton(kind: string): TextButton?
	for _, e in entries do
		if e.kind == kind then
			return e.button
		end
	end
	return nil
end

function HudController.menuPlan(): Layout.MenuPlan?
	return menuPlan
end

function HudController.statsFrame(): Frame?
	return stats
end

function HudController.refresh()
	local fn = refreshFn
	if fn then
		fn()
	end
end

-- 굵은 외곽선 큰 글씨
local function bigText(text: string, size: number, color: Color3, props: { [string]: any }): TextLabel
	local label = Ui.label(text, UDim2.fromOffset(240, size + 6), size, color, props)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = false
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = C.winEdge
		stroke.Thickness = math.max(2.5, size / 11)
	end
	return label
end

function HudController.start()
	local hud = Ui.layer("Hud")

	------------------------------------------------------------------
	-- 힘 · 돈 · 띠
	------------------------------------------------------------------
	local frame: Frame = Ui.new("Frame", {
		Name = "Stats",
		Size = UDim2.fromOffset(Layout.STATS_W, Layout.STATS_H),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	Ui.scaled(frame)
	stats = frame
	local function row(name: string): Frame
		return Ui.new(
			"Frame",
			{ Name = name, Size = UDim2.fromOffset(Layout.STATS_W, 48), BackgroundTransparency = 1, Parent = frame }
		)
	end
	local powerRow = row("PowerRow")
	Icons.draw("power", powerRow, 44, UDim2.fromOffset(24, 24))
	local powerLabel =
		bigText("0", 40, C.power, { Name = "Power", Position = UDim2.fromOffset(52, 0), Parent = powerRow })
	local boostBadge: TextLabel = Ui.new("TextLabel", {
		Name = "BoostBadge",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(64, 30),
		BackgroundColor3 = Theme.Menu.boost,
		TextColor3 = C.white,
		TextSize = 22,
		Text = "×2",
		Visible = false,
		Parent = powerRow,
	})
	Ui.corner(8).Parent = boostBadge
	Ui.stroke(C.winEdge, 2).Parent = boostBadge
	Ui.textStroke(2).Parent = boostBadge

	local moneyRow = row("MoneyRow")
	Icons.draw("coin", moneyRow, 44, UDim2.fromOffset(24, 24))
	local moneyLabel =
		bigText("0", 40, C.moneyGreen, { Name = "Money", Position = UDim2.fromOffset(52, 0), Parent = moneyRow })

	local beltRow = row("BeltRow")
	local beltStripe: Frame = Ui.new("Frame", {
		Name = "Stripe",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(42, 16),
		BackgroundColor3 = C.white,
		Parent = beltRow,
	})
	Ui.corner(4).Parent = beltStripe
	Ui.stroke(C.winEdge, 2).Parent = beltStripe
	local beltLabel =
		bigText("흰 띠", 28, C.white, { Name = "BeltName", Position = UDim2.fromOffset(52, 6), Parent = beltRow })

	local lastMoney = 0
	local function refresh()
		local power = State.power()
		local money = State.money()
		local boost = State.boost()
		powerLabel.Text = Format.number(power)
		moneyLabel.Text = Format.number(money)
		if money > lastMoney * 1.5 + 50 then
			Ui.pop(moneyLabel, 1.2)
		end
		lastMoney = money
		boostBadge.Visible = boost > 1
		boostBadge.Text = "×" .. Format.number(boost)
		local textW = math.min(170, 22 * #powerLabel.Text + 10)
		boostBadge.Position = UDim2.new(0, 52 + textW, 0.5, 0)
		local belt = Belts.get(State.belt())
		beltStripe.BackgroundColor3 = Theme.beltColor(State.belt())
		beltLabel.Text = if belt then belt.name else "흰 띠"
	end
	refreshFn = refresh

	-- PC: 왼쪽 아래 3줄 / 터치: 위 왼쪽 한 줄 (조이스틱을 피함)
	local function layoutStats()
		local touch = Ui.isTouch()
		if touch then
			frame.AnchorPoint = Vector2.new(0, 0)
			frame.Position = UDim2.fromOffset(10, 4)
			frame.Size = UDim2.fromOffset(Layout.STATS_TOUCH_W, Layout.STATS_TOUCH_H)
			powerRow.Size = UDim2.fromOffset(230, 48)
			powerRow.Position = UDim2.fromOffset(0, 0)
			moneyRow.Size = UDim2.fromOffset(200, 48)
			moneyRow.Position = UDim2.fromOffset(230, 0)
			beltRow.Size = UDim2.fromOffset(170, 48)
			beltRow.Position = UDim2.fromOffset(430, 0)
		else
			frame.AnchorPoint = Vector2.new(0, 1)
			frame.Position = UDim2.new(0, 10, 1, -8)
			frame.Size = UDim2.fromOffset(Layout.STATS_W, Layout.STATS_H)
			for i, r in { powerRow, moneyRow, beltRow } do
				r.Size = UDim2.fromOffset(Layout.STATS_W, 48)
				r.Position = UDim2.fromOffset(0, (i - 1) * 50)
			end
		end
	end

	------------------------------------------------------------------
	-- 왼쪽 메뉴
	------------------------------------------------------------------
	local menu: Frame = Ui.new("Frame", {
		Name = "Menu",
		Size = UDim2.fromOffset(BASE, BASE),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	local scale = Instance.new("UIScale")
	scale.Name = "MenuScale"
	scale.Parent = menu
	menuFrame = menu
	menuScale = scale
	for _, p in pending do
		menuButton(p.kind, p.caption, p.order, menu, p.onClick)
	end
	table.clear(pending)

	Ui.onLayout(function()
		layoutStats()
		layoutMenu()
	end)
	layoutStats()
	layoutMenu()
	refresh()
	State.onChanged(function()
		refresh()
	end)
end

return HudController
