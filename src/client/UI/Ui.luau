--!strict
--[[
	Ui — 화면 만들기 도우미 (ScreenGui 하나 + 층(layer) + 귀여운 기본 위젯)

	  Ui.layer("Hud")                    → 화면 전체 크기 투명 Frame (층마다 ZIndex 다름)
	  Ui.new("Frame", { ...속성 }, { 자식 })  → 인스턴스 만들기
	  Ui.button("장착", Theme.Colors.green, UDim2.fromOffset(120, 50), function() ... end)
	  Ui.scaled(frame)                   → 화면 크기에 맞는 UIScale 붙이기 (기준 1100×720)
	  Ui.pop(guiObject)                  → 톡 튀는 강조 애니메이션

	크기는 기준 화면 픽셀(Offset)로 적고, 묶음(컨테이너)마다 Ui.scaled 로 화면 크기에 맞춤.
	HUD 최소 배율 0.7 (폰 가로 844×390 에서 64px 버튼 → 45px). 창·팝업은 화면 안에 다 들어오게 맞춤.

	반응형 HUD (왼쪽 메뉴·핫바): Ui.area() 화면 영역, Ui.isTouch() 터치 조작 중인지,
	  Ui.onLayout(fn) 화면 크기·조작 방식이 바뀌면 fn 다시 부름, Ui.relayout() 지금 바로 다시 배치.
	  자리 계산은 UI/Layout.luau (숫자만).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)

local Ui = {}

local C = Theme.Colors

------------------------------------------------------------------
-- 루트 / 층 / 배율
------------------------------------------------------------------

local screen: ScreenGui? = nil
local layers: { [string]: Frame } = {}
local LAYER_ORDER: { [string]: number } = {
	World = 1,
	Hud = 10,
	Panels = 20,
	Windows = 30,
	Alerts = 40,
	Popups = 50,
	Toasts = 60,
}

local currentScale = 1
type ScaleEntry = { scale: UIScale, fit: Vector2? }
local scales: { ScaleEntry } = {}
local layoutCallbacks: { () -> () } = {}

local function viewport(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1100, 720)
end

-- HUD 배율: 폰(높이 390)에서도 0.7 → 버튼 64px 이상이면 44px 넘음
local function computeScale(): number
	local size = viewport()
	return math.clamp(math.min(size.X / 1100, size.Y / 720), 0.7, 1.3)
end

-- 창·팝업 배율: 화면 안에 다 들어오게 (작은 폰에서는 HUD 보다 조금 작아질 수 있음)
local function fitScale(base: Vector2): number
	local size = viewport()
	local fit = math.min(size.X * 0.96 / base.X, (size.Y - 36) * 0.96 / base.Y)
	return math.clamp(math.min(fit, computeScale()), 0.45, 1.3)
end

local function scaleFor(entry: ScaleEntry): number
	local fit = entry.fit
	return if fit then fitScale(fit) else currentScale
end

local function applyScale()
	currentScale = computeScale()
	for i = #scales, 1, -1 do
		local entry = scales[i]
		if entry.scale.Parent == nil then
			table.remove(scales, i)
		else
			entry.scale.Scale = scaleFor(entry)
		end
	end
	for _, fn in layoutCallbacks do
		local ok, err = pcall(function(): string?
			fn()
			return nil
		end)
		if not ok then
			warn("[Ui] 다시 배치 오류: " .. tostring(err))
		end
	end
end

-- 터치 조작 중인지: 터치 화면 + (마우스 없음 또는 마지막 입력이 터치) = 로블록스 조이스틱·점프 버튼이 보이는 상황
local function touchMode(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	if not UserInputService.MouseEnabled then
		return true
	end
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	return ok and last == Enum.UserInputType.Touch
end

function Ui.screen(): ScreenGui
	local existing = screen
	if existing then
		return existing
	end
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "StealAnEggUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui

	-- 화면 영역(인셋 제외) 크기가 바뀌거나, 조작 방식(터치 ↔ 마우스)이 바뀌면 다시 배치
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyScale)
	local lastTouch = touchMode()
	UserInputService.LastInputTypeChanged:Connect(function()
		local now = touchMode()
		if now ~= lastTouch then
			lastTouch = now
			applyScale()
		end
	end)

	local function hookCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
		end
		applyScale()
	end
	hookCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
	return gui
end

function Ui.layer(name: string): Frame
	local existing = layers[name]
	if existing then
		return existing
	end
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.ZIndex = LAYER_ORDER[name] or 5
	f.Parent = Ui.screen()
	layers[name] = f
	return f
end

function Ui.scale(): number
	return currentScale
end

-- HUD 를 놓을 수 있는 화면 영역 크기 (위쪽 로블록스 메뉴 인셋 제외).
-- ScreenGui.AbsoluteSize 가 정답, 아직 없으면(테스트 등) 카메라 화면 - GuiService 인셋
function Ui.area(): Vector2
	local gui = screen
	if gui then
		local ok, size = pcall(function(): Vector2
			return gui.AbsoluteSize
		end)
		if ok and size.X > 1 and size.Y > 1 then
			return size
		end
	end
	local size = viewport()
	local ok, topLeft, bottomRight = pcall(function(): (Vector2, Vector2)
		return GuiService:GetGuiInset()
	end)
	if ok then
		return Vector2.new(
			math.max(1, size.X - topLeft.X - bottomRight.X),
			math.max(1, size.Y - topLeft.Y - bottomRight.Y)
		)
	end
	return size
end

-- 터치 조작 중인지 (로블록스 조이스틱·점프 버튼이 화면에 있는 상황)
function Ui.isTouch(): boolean
	return touchMode()
end

-- 화면 크기·조작 방식이 바뀔 때마다 fn 을 부름 (처음 한 번은 직접 부르세요)
function Ui.onLayout(fn: () -> ())
	table.insert(layoutCallbacks, fn)
end

-- 지금 바로 배율·배치 다시 계산 (테스트, 칸 수가 바뀔 때)
function Ui.relayout()
	applyScale()
end

-- 창·팝업(기준 크기 base)의 지금 화면 배율
function Ui.fitScale(base: Vector2): number
	return fitScale(base)
end

-- 손가락 버튼 크기: 화면에서 최소 minPx(기본 46) 픽셀이 되도록 기준 크기(Offset)를 키움
--   fit 을 주면 그 창 배율 기준, 없으면 HUD 배율 기준. 창을 열 때마다(render) 다시 계산하세요.
function Ui.touch(basePx: number, fit: Vector2?, minPx: number?): number
	local s = if fit then fitScale(fit) else computeScale()
	return math.max(basePx, math.ceil((minPx or 46) / math.max(s, 0.01)))
end

-- 컨테이너에 화면 배율 UIScale 붙이기. fit(기준 크기)을 주면 그 상자가 화면 안에 다 들어오게 맞춤 (창·팝업용)
function Ui.scaled<T>(obj: T, fit: Vector2?): T
	local s = Instance.new("UIScale")
	s.Name = "ScreenScale"
	local entry: ScaleEntry = { scale = s, fit = fit }
	s.Scale = scaleFor(entry)
	s.Parent = obj :: any
	table.insert(scales, entry)
	return obj
end

------------------------------------------------------------------
-- 만들기
------------------------------------------------------------------

function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst: any = Instance.new(className :: any)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				inst[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if inst:IsA("GuiObject") and (props == nil or props.BorderSizePixel == nil) then
		inst.BorderSizePixel = 0
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		if props == nil or props.Font == nil then
			inst.Font = Theme.Font
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(radius: number?): UICorner
	local c = Instance.new("UICorner")
	if radius and radius <= 1 then
		c.CornerRadius = UDim.new(radius, 0)
	else
		c.CornerRadius = UDim.new(0, radius or 14)
	end
	return c
end

function Ui.stroke(color: Color3?, thickness: number?, contextual: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or C.ink
	s.Thickness = thickness or 3
	s.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	return s
end

function Ui.textStroke(thickness: number?, color: Color3?): UIStroke
	return Ui.stroke(color or C.ink, thickness or 2.5, true)
end

function Ui.padding(px: number, top: number?): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, top or px)
	p.PaddingBottom = UDim.new(0, top or px)
	return p
end

function Ui.list(
	direction: Enum.FillDirection?,
	gap: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, gap or 8)
	l.HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center
	l.VerticalAlignment = vAlign or Enum.VerticalAlignment.Top
	l.SortOrder = Enum.SortOrder.LayoutOrder
	return l
end

function Ui.grid(cell: Vector2, gap: number?): UIGridLayout
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	g.CellPadding = UDim2.fromOffset(gap or 10, gap or 10)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center
	return g
end

function Ui.gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	return g
end

function Ui.label(text: string, size: UDim2, textSize: number, color: Color3?, props: { [string]: any }?): TextLabel
	local p: { [string]: any } = {
		Text = text,
		Size = size,
		BackgroundTransparency = 1,
		TextSize = textSize,
		TextColor3 = color or C.white,
		TextWrapped = true,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local label = Ui.new("TextLabel", p)
	Ui.textStroke(math.max(1.5, textSize / 12)).Parent = label
	return label
end

------------------------------------------------------------------
-- 애니메이션
------------------------------------------------------------------

function Ui.tween(inst: Instance, info: TweenInfo, props: { [string]: any }): Tween
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function popScale(obj: Instance): UIScale
	local s = obj:FindFirstChild("Pop")
	if s and s:IsA("UIScale") then
		return s
	end
	local n = Instance.new("UIScale")
	n.Name = "Pop"
	n.Parent = obj
	return n
end

-- 톡 튀기 (1.15배 → 1)
function Ui.pop(obj: GuiObject, amount: number?)
	local s = popScale(obj)
	s.Scale = amount or 1.18
	Ui.tween(s, Theme.Tween.pop, { Scale = 1 })
end

------------------------------------------------------------------
-- 버튼
------------------------------------------------------------------

export type ButtonOptions = {
	textSize: number?,
	textColor: Color3?,
	sound: string?,
	layoutOrder: number?,
	parent: any, -- Instance (Frame 등). 새 타입 검사기가 하위 클래스를 Instance? 칸에 못 넣어서 any
	position: UDim2?,
	anchor: Vector2?,
}

function Ui.button(text: string, color: Color3, size: UDim2, onClick: (() -> ())?, opts: ButtonOptions?): TextButton
	local o: ButtonOptions = opts or {}
	local button: TextButton = Ui.new("TextButton", {
		Name = "Button",
		Text = text,
		Size = size,
		Position = o.position or UDim2.new(),
		AnchorPoint = o.anchor or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		TextColor3 = o.textColor or C.white,
		TextSize = o.textSize or 24,
		TextWrapped = true,
		LayoutOrder = o.layoutOrder or 0,
	})
	Ui.corner(14).Parent = button
	Ui.stroke(Theme.darker(color, 0.35), 3).Parent = button
	Ui.gradient(Theme.lighter(color, 0.25), color).Parent = button
	Ui.textStroke(2).Parent = button
	local press = popScale(button)
	button.MouseButton1Down:Connect(function()
		Ui.tween(press, Theme.Tween.fast, { Scale = 0.92 })
	end)
	local function release()
		Ui.tween(press, Theme.Tween.pop, { Scale = 1 })
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		SoundController.play(o.sound or "Click")
		if onClick then
			onClick()
		end
	end)
	if o.parent then
		button.Parent = o.parent
	end
	return button
end

-- 버튼 색/글자 바꾸기 (구매 가능/불가 등)
function Ui.setButton(button: TextButton, text: string?, color: Color3?, enabled: boolean?)
	if text then
		button.Text = text
	end
	if color then
		button.BackgroundColor3 = color
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke and stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			stroke.Color = Theme.darker(color, 0.35)
		end
		local gradient = button:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(Theme.lighter(color, 0.25), color)
		end
	end
	if enabled ~= nil then
		button.Active = enabled
		button.AutoButtonColor = false
		button.BackgroundTransparency = if enabled then 0 else 0.35
	end
end

------------------------------------------------------------------
-- 창 (제목 + 닫기 X + 내용)
------------------------------------------------------------------

export type Window = {
	holder: Frame, -- 화면 배율이 붙은 바깥 상자 (보이기/숨기기)
	panel: Frame, -- 열기/닫기 애니메이션 대상
	content: Frame,
	header: Frame,
	title: TextLabel,
	close: TextButton,
}

function Ui.window(name: string, title: string, color: Color3, size: Vector2, onClose: () -> ()): Window
	local holder: Frame = Ui.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.layer("Windows"),
	})
	Ui.scaled(holder, size)
	local panel: Frame = Ui.new("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.panel,
		Parent = holder,
	})
	Ui.corner(26).Parent = panel
	Ui.stroke(C.white, 5).Parent = panel
	-- 닫기 X 는 폰에서도 46px 이상 (창 배율 기준) → 머리 높이도 그만큼
	local closeH = Ui.touch(66, size)
	local headerH = math.max(76, closeH + 8)
	local header: Frame = Ui.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, headerH),
		BackgroundColor3 = color,
		Parent = panel,
	})
	Ui.corner(24).Parent = header
	Ui.gradient(Theme.lighter(color, 0.3), color).Parent = header
	-- 헤더 아래쪽 둥근 모서리 가리기
	Ui.new("Frame", {
		Name = "HeaderFill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = color,
		Parent = header,
	})
	local titleLabel = Ui.label(title, UDim2.new(1, -(closeH + 74), 1, 0), 36, C.white, {
		Name = "Title",
		Position = UDim2.fromOffset(24, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = header,
	})
	local close = Ui.button("X", C.red, UDim2.fromOffset(closeH, closeH), onClose, {
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -8, 0.5, 0),
		textSize = 30,
		sound = "Close",
		parent = header,
	})
	close.ZIndex = 3
	local content: Frame = Ui.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, headerH),
		Size = UDim2.new(1, 0, 1, -headerH),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	Ui.padding(14).Parent = content
	popScale(panel)
	return { holder = holder, panel = panel, content = content, header = header, title = titleLabel, close = close }
end

-- 스크롤 목록 (자동 캔버스 크기)
function Ui.scroll(size: UDim2, position: UDim2?, parent: Instance?): ScrollingFrame
	local s: ScrollingFrame = Ui.new("ScrollingFrame", {
		Name = "Scroll",
		Size = size,
		Position = position or UDim2.new(),
		BackgroundTransparency = 1,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = C.ink,
		ScrollBarImageTransparency = 0.5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	return s
end

-- 둥근 카드
function Ui.card(size: UDim2, color: Color3?, strokeColor: Color3?): Frame
	local f: Frame = Ui.new("Frame", {
		Name = "Card",
		Size = size,
		BackgroundColor3 = color or C.white,
	})
	Ui.corner(16).Parent = f
	Ui.stroke(strokeColor or Theme.darker(C.panelDark, 0.1), 3).Parent = f
	return f
end

-- 빨간 동그라미 숫자 배지
function Ui.badge(parent: GuiObject): TextLabel
	local b: TextLabel = Ui.new("TextLabel", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.red,
		TextColor3 = C.white,
		TextSize = 18,
		Text = "!",
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	})
	Ui.corner(1).Parent = b
	Ui.stroke(C.white, 2).Parent = b
	return b
end

return Ui
