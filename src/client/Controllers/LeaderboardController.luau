--!strict
--[[
	LeaderboardController — 랭킹판 (5판, 사장님 지시). 데이터는 서버 LeaderboardService.

	LeaderboardUpdate { money = { {name, value, userId} … }, speed = { … } } — 10초마다 서버 전체 (큰 값부터 최대 10줄),
	새로 들어오면 준비되자마자 한 번.

	화면 (오른쪽 위, UI/Layout.leaderboard):
	  - 제목 줄 "🏆 랭킹" + 접기/펴기 버튼 (PC 는 펼친 채 시작, 폰은 접힌 채 시작 — 화면이 좁아서)
	  - 탭 2개: 돈 / 속도 (Format.money / Format.number), 최대 10줄 "1 이름 값"
	  - 내 줄(userId == 나) 노란 바탕으로 강조. 1·2·3등은 금·은·동 순위 글자.
	  - 펼쳐서 오른쪽 알·발바닥 버튼에 닿으면 그 왼쪽으로 비킴. 폰에서는 시간 아래, 튜토리얼 패널과 안 겹침.
	  로블록스 기본 플레이어 목록(오른쪽 위)은 이 판과 겹쳐서 끔.
	허브 스폰 광장 3D 판 (MapBuilder 가 세운 LeaderboardBoard 태그 파트): Front 면에 SurfaceGui — 돈 · 속도 두 칸, 각 10줄.
	공개: LeaderboardController.apply(board) / setExpanded(on) / setTab(name) / isExpanded() (테스트도 씀)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Visuals = require(Shared.Data.Visuals)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Layout = require(Client.UI.Layout)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)

local LeaderboardController = {}

local C = Theme.Colors
local GOLD = Color3.fromRGB(255, 205, 50)
local RANK_COLORS = { GOLD, Color3.fromRGB(215, 222, 235), Color3.fromRGB(225, 145, 85) }
local MAX_ROWS = 10
local ME_BACK = Color3.fromRGB(150, 120, 20)

local data: Types.Leaderboard = { money = {}, speed = {} }
local tab = "money"
local expanded = true
local frame: Frame? = nil
local list: Frame? = nil
local toggleButton: TextButton? = nil
local tabMoney: TextButton? = nil
local tabSpeed: TextButton? = nil
local boardRows: { [string]: { TextLabel } } = {}

local function entries(kind: string): { Types.LeaderboardEntry }
	local raw = if kind == "speed" then data.speed else data.money
	return if typeof(raw) == "table" then raw else {}
end

local function valueText(kind: string, value: number): string
	return if kind == "speed" then Format.number(value) else Format.money(value)
end

local function rowCount(): number
	return math.clamp(math.max(#entries("money"), #entries("speed"), 1), 1, MAX_ROWS)
end

------------------------------------------------------------------
-- 화면 (오른쪽 위)
------------------------------------------------------------------

local function relayout()
	local f = frame
	if not f then
		return
	end
	local touch = Ui.isTouch()
	local rows = if expanded then rowCount() else 0
	local rect = Layout.leaderboard(Ui.area(), Ui.scale(), touch, rows)
	local baseW = if touch then Layout.BOARD_W_TOUCH else Layout.BOARD_W
	local s = math.max(Ui.scale(), 0.01)
	f.Size = UDim2.fromOffset(baseW, rect.h / s)
	f.AnchorPoint = Vector2.new(0, 0)
	f.Position = UDim2.fromOffset(rect.x, rect.y)
end

local function renderRows()
	local holder = list
	if not holder then
		return
	end
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local me = Players.LocalPlayer.UserId
	for i, e in entries(tab) do
		if i > MAX_ROWS then
			break
		end
		local mine = e.userId == me
		local row: Frame = Ui.new("Frame", {
			Name = "Row" .. i,
			Size = UDim2.new(1, 0, 0, Layout.BOARD_ROW - 2),
			BackgroundColor3 = if mine then ME_BACK else C.winDark,
			BackgroundTransparency = if mine then 0.05 else 0.35,
			LayoutOrder = i,
			Parent = holder,
		})
		row:SetAttribute("Mine", mine)
		Ui.corner(4).Parent = row
		Ui.label(tostring(i), UDim2.new(0, 22, 1, 0), 15, RANK_COLORS[i] or C.white, {
			Name = "Rank",
			TextScaled = true,
			Parent = row,
		})
		Ui.label(tostring(e.name), UDim2.new(0.58, -24, 1, 0), 15, if mine then C.yellow else C.white, {
			Name = "PlayerName",
			Position = UDim2.fromOffset(24, 0),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		Ui.label(
			valueText(tab, tonumber(e.value) or 0),
			UDim2.new(0.42, -4, 1, 0),
			15,
			if tab == "speed" then C.speedRed else C.moneyGreen,
			{
				Name = "Value",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, 0),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = row,
			}
		)
	end
	if #entries(tab) == 0 then
		Ui.label("아직 기록이 없어요", UDim2.new(1, 0, 0, Layout.BOARD_ROW), 14, C.gray, {
			Name = "Empty",
			TextScaled = true,
			Parent = holder,
		})
	end
end

local function refreshTabs()
	local m, s = tabMoney, tabSpeed
	if m then
		Ui.setButton(m, nil, if tab == "money" then C.shopGreen else C.gray)
	end
	if s then
		Ui.setButton(s, nil, if tab == "speed" then C.speedRed else C.gray)
	end
	local holder = list
	if holder then
		holder.Visible = expanded
	end
	if m then
		m.Visible = expanded
	end
	if s then
		s.Visible = expanded
	end
	local t = toggleButton
	if t then
		t.Text = if expanded then "−" else "+"
	end
end

function LeaderboardController.setTab(name: string)
	tab = if name == "speed" then "speed" else "money"
	refreshTabs()
	renderRows()
end

function LeaderboardController.setExpanded(on: boolean)
	expanded = on
	refreshTabs()
	relayout()
end

function LeaderboardController.isExpanded(): boolean
	return expanded
end

------------------------------------------------------------------
-- 허브 3D 판 (SurfaceGui, 판마다 한 번 만들고 글만 바꿈)
------------------------------------------------------------------

local function column(parent: Instance, kind: string, title: string, color: Color3, x: number): { TextLabel }
	local col = Instance.new("Frame")
	col.Name = "Column_" .. kind
	col.BackgroundColor3 = Color3.fromRGB(26, 28, 38)
	col.BackgroundTransparency = 0.1
	col.Position = UDim2.new(x, 8, 0, 74)
	col.Size = UDim2.new(0.5, -12, 1, -82)
	col.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = col
	local head = Instance.new("TextLabel")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Size = UDim2.fromScale(1, 0.09)
	head.Font = Enum.Font.FredokaOne
	head.TextScaled = true
	head.TextColor3 = color
	head.TextStrokeTransparency = 0
	head.Text = title
	head.Parent = col
	local labels: { TextLabel } = {}
	for i = 1, MAX_ROWS do
		local l = Instance.new("TextLabel")
		l.Name = "Line" .. i
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.03, 0.1 + (i - 1) * 0.089)
		l.Size = UDim2.fromScale(0.94, 0.085)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = RANK_COLORS[i] or Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0
		l.Text = ""
		l.Parent = col
		table.insert(labels, l)
	end
	return labels
end

local function buildBoard(board: BasePart): SurfaceGui
	local existing = board:FindFirstChild("LeaderboardGui")
	if existing and existing:IsA("SurfaceGui") then
		return existing
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(40, 42, 58)
	back.Parent = gui
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 6)
	title.Size = UDim2.new(1, 0, 0, 64)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = GOLD
	title.TextStrokeTransparency = 0
	title.Text = "🏆 랭킹 TOP 10"
	title.Parent = back
	boardRows.money = column(back, "money", "💵 돈", C.moneyGreen, 0)
	boardRows.speed = column(back, "speed", "👟 속도", C.speedRed, 0.5)
	gui.Parent = board
	return gui
end

local function renderBoards()
	local boards = CollectionService:GetTagged(Visuals.Tags.LeaderboardBoard)
	for _, inst in boards do
		if inst:IsA("BasePart") then
			buildBoard(inst)
		end
	end
	for kind, labels in boardRows do
		local list0 = entries(kind)
		for i, label in labels do
			local e = list0[i]
			label.Text = if e
				then string.format("%d. %s  %s", i, tostring(e.name), valueText(kind, tonumber(e.value) or 0))
				else ""
		end
	end
end

------------------------------------------------------------------
-- 받기
------------------------------------------------------------------

function LeaderboardController.apply(board: any)
	if typeof(board) ~= "table" then
		return
	end
	data = {
		money = if typeof(board.money) == "table" then board.money else {},
		speed = if typeof(board.speed) == "table" then board.speed else {},
	}
	renderRows()
	relayout()
	renderBoards()
end

function LeaderboardController.start()
	-- 로블록스 기본 플레이어 목록은 같은 자리(오른쪽 위)라 끔
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	expanded = not Ui.isTouch()

	local f: Frame = Ui.new("Frame", {
		Name = "Leaderboard",
		Size = UDim2.fromOffset(Layout.BOARD_W, Layout.BOARD_HEADER),
		BackgroundColor3 = C.win,
		BackgroundTransparency = 0.15,
		Parent = Ui.layer("Hud"),
	})
	Ui.scaled(f)
	Ui.corner(10).Parent = f
	Ui.stroke(C.winEdge, 3).Parent = f
	Ui.label("🏆 랭킹", UDim2.new(1, -44, 0, Layout.BOARD_HEADER - 6), 20, GOLD, {
		Name = "Title",
		Position = UDim2.fromOffset(8, 3),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = f,
	})
	local toggle = Ui.button("−", C.winDark, UDim2.fromOffset(32, 28), function()
		LeaderboardController.setExpanded(not expanded)
	end, { anchor = Vector2.new(1, 0), position = UDim2.new(1, -4, 0, 3), textSize = 22, parent = f })
	toggle.Name = "LbToggle"
	toggleButton = toggle
	local tabY = Layout.BOARD_HEADER
	local m = Ui.button("돈", C.shopGreen, UDim2.new(0.5, -6, 0, Layout.BOARD_TABS - 4), function()
		LeaderboardController.setTab("money")
	end, { position = UDim2.fromOffset(4, tabY), textSize = 16, parent = f })
	m.Name = "LbTab_money"
	local s = Ui.button("속도", C.gray, UDim2.new(0.5, -6, 0, Layout.BOARD_TABS - 4), function()
		LeaderboardController.setTab("speed")
	end, { anchor = Vector2.new(1, 0), position = UDim2.new(1, -4, 0, tabY), textSize = 16, parent = f })
	s.Name = "LbTab_speed"
	tabMoney, tabSpeed = m, s
	local holder: Frame = Ui.new("Frame", {
		Name = "Rows",
		Position = UDim2.fromOffset(4, tabY + Layout.BOARD_TABS),
		Size = UDim2.new(1, -8, 0, MAX_ROWS * Layout.BOARD_ROW),
		BackgroundTransparency = 1,
		Parent = f,
	})
	Ui.list(Enum.FillDirection.Vertical, 2).Parent = holder
	list = holder
	frame = f

	refreshTabs()
	renderRows()
	relayout()
	Ui.onLayout(relayout)

	Net.on(Remotes.ToClient.LeaderboardUpdate, function(board: any)
		LeaderboardController.apply(board)
	end)
	CollectionService:GetInstanceAddedSignal(Visuals.Tags.LeaderboardBoard):Connect(function()
		task.defer(renderBoards)
	end)
	renderBoards()
end

return LeaderboardController
