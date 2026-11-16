--!strict
--[[
	BeltController — 띠 창 "Belts" (선임)
	  열기: 왼쪽 메뉴 "띠·심사" · 도장의 띠 표지판(BeltBoard) · 심사대(ExamPad) · 대결장(DuelArena) 을 누르거나 탭.
	  위: 12개 띠 (색 띠 + 이름 + 💪 필요한 힘 / ⚔️ 시험관 대결 + 돈 ×배율). 지금 띠는 노란 테두리 "지금 내 띠".
	  아래: 다음 띠 조건 ("노랑 띠 — 💪 200K 필요 (지금 12K)") + 버튼
	      심사 띠 → "🥋 심사 보기" → StartExam()   /  각 월드 네 번째 띠 → "⚔️ 시험관과 대결" → StartDuel()
	      심사대·대결장에서 멀면 그쪽으로 걸어간 뒤 보냄 (서버가 거리·힘을 다시 검사).
	      힘 조건 없이 늘 누를 수 있음 (추천 힘보다 약하면 "추천 힘 N — 지금은 어려울 수 있어요"). 9단 띠면 "그랜드 마스터!"
	  도장 띠 표지판(SurfaceGui Belt_1..12)에도 지금 내 띠를 초록 테두리로 (내 화면에서만).
	공개: NAME · render() · nextBelt() · startNext()
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Belts = require(Shared.Data.Belts)
local Config = require(Shared.Data.Config)
local MapLayout = require(Shared.Data.MapLayout)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Walk = require(Client.Walk)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local HudController = require(script.Parent.HudController)
local NotifyController = require(script.Parent.NotifyController)

local BeltController = {}
local NAME = "Belts"
BeltController.NAME = NAME

local C = Theme.Colors
local SIZE = Vector2.new(820, 580)

function BeltController.nextBelt(): Belts.Belt?
	return Belts.get(State.belt() + 1)
end

local function grandMaster(): boolean
	local snap = State.get()
	return State.belt() >= Belts.COUNT or (snap ~= nil and snap.grandMaster == true)
end

-- 다음 띠 심사·대결 시작 (멀면 걸어가서). 보냈거나 걷기 시작했으면 true
function BeltController.startNext(): boolean
	local nxt = BeltController.nextBelt()
	if not nxt then
		return false
	end
	if State.activity() ~= "" then
		return false
	end
	-- 힘 조건 없음 (needPower = 추천 힘). 약하면 오래 걸릴 뿐 — 서버는 띠 순서·위치만 검사
	local world = State.currentWorld()
	local remote = if nxt.duel then Remotes.ToServer.StartDuel else Remotes.ToServer.StartExam
	local spot = if nxt.duel then MapLayout.duelArena(world) else MapLayout.examPad(world)
	local radius = if nxt.duel then Config.DUEL_RADIUS else Config.EXAM_RADIUS
	local pos = Vector3.new(spot.x, spot.y, spot.z)
	Windows.close(NAME)
	if Walk.flatDistance(pos) > radius - 4 then
		NotifyController.toast(if nxt.duel then "대결장으로 이동" else "심사대로 이동", "info")
	end
	Walk.to(pos, radius - 6, function()
		Net.send(remote)
	end)
	return true
end

local renderFn: (() -> ())? = nil
function BeltController.render()
	local fn = renderFn
	if fn then
		fn()
	end
end

-- 도장 띠 표지판에 지금 내 띠 표시 (내 화면에서만)
local function paintBoards()
	local mine = State.belt()
	for _, model in CollectionService:GetTagged(Tags.BeltBoard) do
		local board = if model:IsA("Model") then model.PrimaryPart else nil
		local sign = board and board:FindFirstChild("Sign")
		local frame = sign and sign:FindFirstChild("Board")
		local grid = frame and frame:FindFirstChild("Belts")
		if grid then
			for _, cell in grid:GetChildren() do
				if cell:IsA("Frame") then
					local index = tonumber(string.match(cell.Name, "^Belt_(%d+)$"))
					local edge = cell:FindFirstChild("Edge")
					if index and edge and edge:IsA("UIStroke") then
						local base = edge:GetAttribute("Base")
						if typeof(base) ~= "Color3" then
							base = edge.Color
							edge:SetAttribute("Base", base)
						end
						if index == mine then
							edge.Color = Color3.fromRGB(90, 255, 120)
							edge.Thickness = 6
						else
							edge.Color = base :: Color3
							edge.Thickness = 3
						end
					end
				end
			end
		end
	end
end
BeltController.paintBoards = paintBoards

function BeltController.start()
	local window = Ui.window(NAME, "🥋 띠 · 승급 심사", Theme.Menu.belt, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content
	local scroll = Ui.scroll(UDim2.new(1, 0, 1, -150), UDim2.new(), content)
	local grid = Ui.grid(Vector2.new(186, 96), 8)
	grid.Parent = scroll
	Ui.padding(4).Parent = scroll
	type Row = { card: Frame, state: TextLabel }
	local rows: { [number]: Row } = {}
	for _, belt in Belts.list do
		local card = Ui.card(UDim2.fromOffset(186, 96), C.winDark, C.winEdge)
		card.Name = "Belt_" .. tostring(belt.index)
		card.LayoutOrder = belt.index
		card.Parent = scroll
		local stripe: Frame = Ui.new("Frame", {
			Name = "Stripe",
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 14),
			BackgroundColor3 = Theme.beltColor(belt.index),
			Parent = card,
		})
		Ui.corner(4).Parent = stripe
		Ui.stroke(C.winEdge, 2).Parent = stripe
		Ui.label(belt.name, UDim2.new(1, -10, 0, 26), 22, C.white, {
			Name = "Name",
			Position = UDim2.fromOffset(5, 24),
			TextScaled = true,
			Parent = card,
		})
		local need = if belt.duel
			then "⚔️ 시험관 대결"
			elseif belt.needPower <= 0 then "처음 띠"
			else "💪 " .. Format.number(belt.needPower)
		Ui.label(need .. " · 💰×" .. tostring(belt.moneyMultiplier), UDim2.new(1, -10, 0, 20), 16, C.yellow, {
			Name = "Need",
			Position = UDim2.fromOffset(5, 52),
			TextScaled = true,
			Parent = card,
		})
		local state = Ui.label("", UDim2.new(1, -10, 0, 18), 16, C.green, {
			Name = "State",
			Position = UDim2.fromOffset(5, 74),
			TextScaled = true,
			Parent = card,
		})
		rows[belt.index] = { card = card, state = state }
	end

	local bottom: Frame = Ui.new("Frame", {
		Name = "Next",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 140),
		BackgroundColor3 = C.winDark,
		Parent = content,
	})
	Ui.corner(12).Parent = bottom
	local nextLabel = Ui.label("", UDim2.new(1, -20, 0, 34), 26, C.white, {
		Name = "Condition",
		Position = UDim2.fromOffset(10, 6),
		TextScaled = true,
		Parent = bottom,
	})
	local hint = Ui.label("", UDim2.new(1, -20, 0, 22), 18, C.yellow, {
		Name = "Hint",
		Position = UDim2.fromOffset(10, 40),
		TextScaled = true,
		Parent = bottom,
	})
	local action = Ui.button("심사 보기", C.shopGreen, UDim2.new(1, -24, 0, 60), function()
		BeltController.startNext()
	end, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -8),
		textSize = 28,
		parent = bottom,
	})
	action.Name = "ActionButton"

	local function render()
		local mine = State.belt()
		for index, row in rows do
			if index == mine then
				row.state.Text = "지금 내 띠 ✔"
				row.state.TextColor3 = C.green
				row.card.BackgroundColor3 = Color3.fromRGB(40, 70, 45)
			elseif index < mine then
				row.state.Text = "획득"
				row.state.TextColor3 = C.gray
				row.card.BackgroundColor3 = Color3.fromRGB(50, 52, 62)
			elseif index == mine + 1 then
				row.state.Text = "다음 띠!"
				row.state.TextColor3 = C.yellow
				row.card.BackgroundColor3 = Color3.fromRGB(70, 60, 40)
			else
				row.state.Text = "🔒"
				row.state.TextColor3 = C.gray
				row.card.BackgroundColor3 = C.winDark
			end
		end
		action.Size = UDim2.new(1, -24, 0, Ui.touch(60, SIZE))
		local nxt = BeltController.nextBelt()
		if grandMaster() or not nxt then
			nextLabel.Text = "👑 그랜드 마스터! 모든 띠 획득"
			hint.Text = "물건 격파로 도감 채우기"
			Ui.setButton(action, "최고 띠", C.gray, false)
			return
		end
		local power = State.power()
		local what = if nxt.duel then "⚔️ 시험관과 대결" else "🥋 승급 심사"
		nextLabel.Text = string.format("다음: %s — %s", nxt.name, what)
		local hard = power < nxt.needPower
		hint.Text = (
			if hard
				then string.format("💪 추천 힘 %s · 아직 어려움", Format.number(nxt.needPower))
				else string.format(
					"💪 추천 힘 %s (지금 %s)",
					Format.number(nxt.needPower),
					Format.number(power)
				)
		)
			.. (
				if nxt.duel
					then " · 송판 15장 먼저 격파 시 승리 → 다음 월드"
					else " · 20초 안에 송판 10장!"
			)
		if State.activity() ~= "" then
			Ui.setButton(action, "진행 중", C.gray, false)
		else
			Ui.setButton(
				action,
				if nxt.duel then "⚔️ 시험관과 대결" else "🥋 심사 보기",
				if nxt.duel then C.purple else C.shopGreen,
				true
			)
		end
	end
	renderFn = render
	Windows.register(NAME, window, render)
	render()
	State.onChanged(function()
		if Windows.isOpen(NAME) then
			render()
		end
		paintBoards()
	end)
	paintBoards()

	HudController.addMenuButton("belt", "띠·심사", 4, function()
		Windows.toggle(NAME)
	end)

	for _, tag in { Tags.BeltBoard, Tags.ExamPad, Tags.DuelArena } do
		local function hook(inst: Instance)
			local click = inst:FindFirstChild("Click")
			if click and click:IsA("ClickDetector") then
				click.MouseClick:Connect(function()
					if State.activity() == "" then
						Windows.open(NAME)
					end
				end)
			end
		end
		for _, inst in CollectionService:GetTagged(tag) do
			hook(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(hook)
	end
end

return BeltController
