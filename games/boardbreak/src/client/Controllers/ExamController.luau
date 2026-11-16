--!strict
--[[
	ExamController — 승급 심사 · 시험관 대결 화면 (선임). 판정은 전부 서버 (클라는 보여 주기만).
	  ExamState { phase "start"|"progress"|"pass"|"fail", broken, total, secondsLeft, belt, boardHp?, boardHpMax? }
	  DuelState { phase "start"|"progress"|"win"|"lose", mine, theirs, total, world, secondsLeft?, boardHp?, examiner? }
	위 가운데 패널 "ExamPanel":
	  심사: 제목 "🥋 노랑 띠 승급 심사" · 막대 1 = 깬 송판 (3 / 10) · 막대 2 = 남은 시간 (12초) · 지금 송판 체력
	  대결: 제목 "⚔️ 호랑이 사범님과 대결" · 막대 1 = 나 (5 / 15) · 막대 2 = 시험관 (4 / 15) · 남은 시간
	시작하면 가운데 큰 "준비… 시작!" (대결은 3·2·1), 끝나면 큰 글 "합격! 🎉 노랑 띠" / "아쉬워요… 다시 도전!" / "승리!" / "졌어요…"
	도장 심사대 송판(Board_1..10) · 대결장 송판(Mine_ · Theirs_)을 깬 만큼 내 화면에서 사라지게 (끝나면 다시).
	치기는 BreakController 의 큰 "치기" 버튼 (Activity 동안 Hit("exam"/"duel")).
	공개: onExam(s) · onDuel(s) · panel · mode()
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Belts = require(Shared.Data.Belts)
local Config = require(Shared.Data.Config)
local Worlds = require(Shared.Data.Worlds)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Layout = require(Client.UI.Layout)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local NotifyController = require(script.Parent.NotifyController)
local Cracks = require(Client.Cracks)
local Lift = require(Client.Lift)

local ExamController = {}
ExamController.panel = nil :: Frame?
ExamController.PANEL = Vector2.new(520, 150)

local C = Theme.Colors
local mode: string? = nil -- "exam" | "duel" | nil
local bigHolder: Frame? = nil

function ExamController.mode(): string?
	return mode
end

type Bar = { frame: Frame, fill: Frame, text: TextLabel, caption: TextLabel }

local function makeBar(parent: Instance, name: string, y: number, color: Color3): Bar
	local frame: Frame = Ui.new("Frame", {
		Name = name,
		Position = UDim2.fromOffset(120, y),
		Size = UDim2.new(1, -134, 0, 30),
		BackgroundColor3 = C.winDark,
		Parent = parent,
	})
	Ui.corner(8).Parent = frame
	Ui.stroke(C.winEdge, 3).Parent = frame
	local fill: Frame =
		Ui.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, Parent = frame })
	Ui.corner(8).Parent = fill
	local text = Ui.label("", UDim2.fromScale(1, 1), 20, C.white, { Name = "Text", ZIndex = 2, Parent = frame })
	local caption = Ui.label("", UDim2.fromOffset(104, 30), 20, C.white, {
		Name = name .. "Caption",
		Position = UDim2.fromOffset(10, y),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Parent = parent,
	})
	return { frame = frame, fill = fill, text = text, caption = caption }
end

local function setBar(bar: Bar, value: number, total: number, text: string)
	local ratio = if total > 0 then math.clamp(value / total, 0, 1) else 0
	bar.fill.Size = UDim2.fromScale(ratio, 1)
	bar.text.Text = text
end

-- 가운데 큰 글 (잠깐)
function ExamController.big(text: string, color: Color3, seconds: number?)
	local holder = bigHolder
	if not holder then
		return
	end
	for _, old in holder:GetChildren() do
		if old:IsA("TextLabel") then
			old:Destroy()
		end
	end
	local label = Ui.label(text, UDim2.fromScale(1, 1), 64, color, { Name = "Big", TextScaled = true, Parent = holder })
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = C.winEdge
		stroke.Thickness = 5
	end
	Ui.pop(label, 1.6)
	task.delay(seconds or 1.6, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

-- 도장 송판을 깬 만큼 숨김 (내 화면에서만). prefix "Board"(심사대) · "Mine" · "Theirs"(대결장)
-- 지금 치는 송판(broken + 1)에는 hp/hpMax 로 금 (75·50·25%), 나머지 송판 금은 지움
local function paintBoards(tag: string, prefix: string, broken: number, total: number, hp: number?, hpMax: number?)
	local world = State.currentWorld()
	local stage = Cracks.stage(hp, hpMax)
	for _, model in CollectionService:GetTagged(tag) do
		if model:GetAttribute(Tags.PartAttributes.World) == world then
			for i = 1, total do
				local board = model:FindFirstChild(prefix .. "_" .. tostring(i), true)
				if board and board:IsA("BasePart") then
					board.LocalTransparencyModifier = if i <= broken then 1 else 0
					if i == broken + 1 and stage > 0 then
						Cracks.show(
							board,
							stage,
							Cracks.seedOf(prefix .. i),
							{ Enum.NormalId.Front, Enum.NormalId.Back }
						)
					else
						Cracks.clear(board)
					end
				end
			end
		end
	end
end

-- 사범님이 송판을 깰 때마다 오른팔 내리치기 (R15 몸일 때. 블록 대체 모델이면 그냥 넘어감)
local lastTheirs = 0
function ExamController.examinerChop(world: number): boolean
	for _, arena in CollectionService:GetTagged(Tags.DuelArena) do
		if arena:GetAttribute(Tags.PartAttributes.World) == world then
			local npc = arena:FindFirstChild("Examiner")
			if npc and npc:IsA("Model") then
				return Lift.play(npc, "chop")
			end
		end
	end
	return false
end
ExamController.paintBoards = paintBoards

local title: TextLabel? = nil
local bar1: Bar? = nil
local bar2: Bar? = nil
local boardHpLabel: TextLabel? = nil

local function show(on: boolean)
	local panel = ExamController.panel
	if panel then
		panel.Visible = on
	end
end

function ExamController.onExam(s: any)
	if type(s) ~= "table" then
		return
	end
	local phase = s.phase
	local total = tonumber(s.total) or Config.EXAM_BOARDS
	local broken = tonumber(s.broken) or 0
	local left = math.max(0, tonumber(s.secondsLeft) or 0)
	local belt = Belts.get(tonumber(s.belt) or (State.belt() + 1))
	local beltName = if belt then belt.name else "다음 띠"
	local t, b1, b2 = title, bar1, bar2
	if not (t and b1 and b2) then
		return
	end
	if phase == "start" or phase == "progress" then
		if phase == "start" then
			Windows.close()
			ExamController.big("준비… 시작! 🥋", C.yellow, 1.2)
		end
		mode = "exam"
		show(true)
		t.Text = "🥋 " .. beltName .. " 승급 심사"
		b1.caption.Text = "송판"
		b2.caption.Text = "시간"
		b1.fill.BackgroundColor3 = C.orange
		b2.fill.BackgroundColor3 = if left <= 5 then C.red else C.blue
		setBar(b1, broken, total, string.format("%d / %d 장", broken, total))
		setBar(b2, left, Config.EXAM_SECONDS, string.format("%d초", math.ceil(left)))
		local label = boardHpLabel
		if label then
			local hp, hpMax = tonumber(s.boardHp), tonumber(s.boardHpMax)
			label.Text = if hp and hpMax
				then "지금 송판 " .. Format.number(hp) .. " / " .. Format.number(hpMax)
				else ""
		end
		paintBoards(Tags.ExamPad, "Board", broken, total, tonumber(s.boardHp), tonumber(s.boardHpMax))
	elseif phase == "pass" then
		mode = nil
		show(false)
		paintBoards(Tags.ExamPad, "Board", 0, total)
		-- (서버가 "합격! ○○ 띠를 받았어요!" 토스트를 보냄 — 여기서는 가운데 큰 글만)
		ExamController.big("합격! 🎉 " .. beltName, C.green, 2.4)
	elseif phase == "fail" then
		mode = nil
		show(false)
		paintBoards(Tags.ExamPad, "Board", 0, total)
		ExamController.big("아쉬워요… 다시 도전!", C.red, 2)
	end
end

function ExamController.onDuel(s: any)
	if type(s) ~= "table" then
		return
	end
	local phase = s.phase
	local total = tonumber(s.total) or Config.DUEL_BOARDS
	local mine = tonumber(s.mine) or 0
	local theirs = tonumber(s.theirs) or 0
	local worldIndex = tonumber(s.world) or State.currentWorld()
	local w = Worlds.get(worldIndex)
	local examiner = if type(s.examiner) == "string" then s.examiner elseif w then w.examiner else "시험관"
	local t, b1, b2 = title, bar1, bar2
	if not (t and b1 and b2) then
		return
	end
	if phase == "start" or phase == "progress" then
		if phase == "start" then
			Windows.close()
			ExamController.big("⚔️ " .. examiner .. "과 대결!", C.yellow, 1)
			local n = Config.DUEL_COUNTDOWN_SECONDS
			for i = 1, n do
				task.delay(i, function()
					if mode == "duel" then
						ExamController.big(if i < n then tostring(n - i) else "시작!", C.yellow, 0.9)
					end
				end)
			end
		end
		mode = "duel"
		show(true)
		t.Text = "⚔️ " .. examiner .. "과 대결"
		b1.caption.Text = "나"
		b2.caption.Text = "시험관"
		b1.fill.BackgroundColor3 = C.green
		b2.fill.BackgroundColor3 = C.red
		setBar(b1, mine, total, string.format("%d / %d", mine, total))
		setBar(b2, theirs, total, string.format("%d / %d", theirs, total))
		local label = boardHpLabel
		if label then
			local left = tonumber(s.secondsLeft)
			label.Text = if left then string.format("남은 시간 %d초", math.ceil(left)) else ""
		end
		paintBoards(Tags.DuelArena, "Mine", mine, total, tonumber(s.boardHp), tonumber(s.boardHpMax))
		paintBoards(Tags.DuelArena, "Theirs", theirs, total)
		if phase == "start" then
			lastTheirs = 0
		end
		if theirs > lastTheirs then
			ExamController.examinerChop(worldIndex)
		end
		lastTheirs = theirs
	elseif phase == "win" or phase == "lose" then
		mode = nil
		show(false)
		paintBoards(Tags.DuelArena, "Mine", 0, total)
		paintBoards(Tags.DuelArena, "Theirs", 0, total)
		if phase == "win" then
			ExamController.big("승리! 🏆", C.green, 2.6)
			local nextWorld = Worlds.get(worldIndex + 1)
			if nextWorld then
				NotifyController.banner(
					"🚪 월드 " .. nextWorld.index .. " " .. nextWorld.name .. " 문이 열렸어요!",
					Theme.worldColor(nextWorld.index)
				)
			else
				NotifyController.banner("👑 그랜드 마스터가 되었어요!", C.yellow)
			end
		else
			ExamController.big("졌어요… 힘을 더 길러서 다시!", C.red, 2.2)
		end
	end
end

function ExamController.start()
	local base = ExamController.PANEL
	local panel: Frame = Ui.new("Frame", {
		Name = "ExamPanel",
		Size = UDim2.fromOffset(base.X, base.Y),
		BackgroundColor3 = C.win,
		Visible = false,
		Parent = Ui.layer("Panels"),
	})
	Ui.corner(14).Parent = panel
	Ui.stroke(C.winEdge, 5).Parent = panel
	local scale = Instance.new("UIScale")
	scale.Name = "PanelScale"
	scale.Parent = panel
	ExamController.panel = panel
	title = Ui.label("", UDim2.new(1, -20, 0, 36), 28, C.yellow, {
		Name = "Title",
		Position = UDim2.fromOffset(10, 6),
		TextScaled = true,
		Parent = panel,
	})
	bar1 = makeBar(panel, "Bar1", 48, C.orange)
	bar2 = makeBar(panel, "Bar2", 84, C.blue)
	boardHpLabel = Ui.label("", UDim2.new(1, -20, 0, 22), 18, C.white, {
		Name = "BoardHp",
		Position = UDim2.fromOffset(10, 120),
		TextScaled = true,
		Parent = panel,
	})
	local function place()
		local r = Layout.topPanel(Ui.area(), Ui.scale(), Ui.isTouch(), base.X, base.Y)
		panel.Position = UDim2.fromOffset(r.x, r.y)
		scale.Scale = Ui.scale()
	end
	Ui.onLayout(place)
	place()

	local holder: Frame = Ui.new("Frame", {
		Name = "ExamBig",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(700, 110),
		BackgroundTransparency = 1,
		Parent = Ui.layer("Popups"),
	})
	Ui.scaled(holder, Vector2.new(700, 110))
	bigHolder = holder

	Net.on(Remotes.ToClient.ExamState, ExamController.onExam)
	Net.on(Remotes.ToClient.DuelState, ExamController.onDuel)
	-- 다시 접속했는데 Activity 가 비었으면 패널을 닫음
	State.onChanged(function(section: string)
		if section == "attr:" .. Tags.PlayerAttributes.Activity and State.activity() == "" and mode ~= nil then
			mode = nil
			show(false)
		end
	end)
end

return ExamController
