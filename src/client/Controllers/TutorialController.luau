--!strict
--[[
	TutorialController — 처음 온 사람 튜토리얼 화면 (5판, 사장님 지시). 판정·진행은 서버 TutorialService.

	데이터: TutorialUpdate(TutorialView) 또는 State.get().tutorial (Snapshot·DataUpdate("tutorial"))
	  TutorialView = { step 1~5 (끝나면 6), total 5, text 큰 글씨, hint 작은 설명, done, reward? (끝내는 순간만 500) }

	화면:
	  - 위 가운데 패널 "TutorialPanel": [n/5] + 큰 글씨(text) + 작은 설명(hint). done 이면 숨김.
	    PC 는 맨 위, 터치는 위 한 줄 속도·돈 아래 (UI/Layout.tutorialPanel — 폰 750×381 에서도 안 겹침).
	    패널이 보이는 동안 위 가운데에 뜨는 것들(달리기!! 배너·구역 배너·공지 배너·알 놓기 안내 줄)을 패널 아래로 내림.
	  - 단계마다 가리키기 (내 화면에만):
	      1 숲에서 알 훔치기    → 3D 노란 빔 + "▼ 숲으로!" 표시 (허브면 숲 입구, 숲이면 가장 가까운 둥지 알) + 화면 밖이면 가장자리 화살표
	      2 안전 구역으로       → 허브(안전 구역 z < 0) 쪽 빔·표시 "안전 구역"
	      3 핫바에서 알 놓기    → 핫바의 알 칸(HotbarController.eggButtons) 노란 테두리 반짝 + 내 우리 표시 "우리에 놓기"
	      4 부화!               → 내 우리에 놓인 알 노란 Highlight + 머리 위 "부화!" (아직 자라는 중이면 "자라는 중…")
	      5 펫 장착             → 오른쪽 발바닥(펫) 버튼 반짝, 펫 창이 열려 있으면 "장착" 버튼들 반짝
	  - 끝(reward): 색종이 + 팡파레(TutorialDone) + "튜토리얼 끝! / $500 받았어요!" (3.6초)
	공개: TutorialController.view() / update() / celebrate(reward) / panelRect() (테스트도 씀)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local MapLayout = require(Shared.Data.MapLayout)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Fx = require(Client.UI.Fx)
local Layout = require(Client.UI.Layout)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local HudController = require(script.Parent.HudController)
local HotbarController = require(script.Parent.HotbarController)
local SoundController = require(script.Parent.SoundController)

local TutorialController = {}

local C = Theme.Colors
local GUIDE = Color3.fromRGB(255, 225, 60)
local FOREST_ENTRANCE = Vector3.new(0, 0, 14)
local BEAM_MIN = 12 -- 목표가 이보다 가까우면 빔은 숨김 (표시만)

-- 위 가운데에 뜨는 것들: 튜토리얼 패널이 보이면 이만큼 아래로 (원래 y 는 처음 볼 때 기억)
local PUSH: { { layer: string, name: string } } = {
	{ layer = "Alerts", name = "RunBanner" },
	{ layer = "Alerts", name = "ZoneBanner" },
	{ layer = "Alerts", name = "BannerHolder" },
	{ layer = "Panels", name = "PlaceBar" },
}
local PUSH_TOP = 14 -- 그중 가장 위에 있는 것(달리기!! 배너)의 원래 y

local current: Types.TutorialView? = nil
local lastStep = 0

local panel: Frame? = nil
local stepLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local arrow: TextLabel? = nil

local guideFolder: Folder? = nil
local marker: BasePart? = nil
local markerGui: BillboardGui? = nil
local markerText: TextLabel? = nil
local beam: Beam? = nil
local highlight: Highlight? = nil
local target: Vector3? = nil
local targetPart: BasePart? = nil

local glows: { Frame } = {} -- 지금 반짝이는 테두리들
local glowTick = 0

local function myRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function myPlot(): number
	local index = Players.LocalPlayer:GetAttribute(Tags.PlayerAttributes.PlotIndex)
	if typeof(index) == "number" and index > 0 then
		return index
	end
	local snap = State.get()
	local fromSnap = if snap then snap.plotIndex else 0
	return if typeof(fromSnap) == "number" then fromSnap else 0
end

local function validView(v: any): boolean
	return typeof(v) == "table" and typeof(v.step) == "number"
end

function TutorialController.view(): Types.TutorialView?
	return current
end

local function active(): boolean
	local v = current
	return v ~= nil and not v.done
end

------------------------------------------------------------------
-- 반짝 테두리 (GuiObject 위에 겹친 노란 테두리 Frame — 원래 UIStroke 는 그대로)
------------------------------------------------------------------

local function setGlows(list: { GuiObject })
	glowTick += 1
	for _, obj in list do
		if obj.Parent ~= nil then
			local found = obj:FindFirstChild("TutorialGlow")
			local f: Frame
			if found and found:IsA("Frame") then
				f = found
			else
				f = Ui.new("Frame", {
					Name = "TutorialGlow",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(1, 10, 1, 10),
					BackgroundTransparency = 1,
					ZIndex = 8,
					Parent = obj,
				})
				Ui.corner(12).Parent = f
				Ui.stroke(GUIDE, 4).Parent = f
				table.insert(glows, f)
			end
			f:SetAttribute("GlowTick", glowTick)
		end
	end
	-- 이번에 안 고른 것은 지움
	for i = #glows, 1, -1 do
		local f = glows[i]
		if f.Parent == nil or f:GetAttribute("GlowTick") ~= glowTick then
			f:Destroy()
			table.remove(glows, i)
		end
	end
end

------------------------------------------------------------------
-- 3D 가리키기 (빔 + 표시 + Highlight) — 내 화면에만 (Workspace.TutorialGuide)
------------------------------------------------------------------

local function ensureGuide(): (Folder, BasePart)
	local folder = guideFolder
	local part = marker
	if folder and folder.Parent and part then
		return folder, part
	end
	local f = Instance.new("Folder")
	f.Name = "TutorialGuide"
	local p = Instance.new("Part")
	p.Name = "TutorialTarget"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.4
	p.Parent = f
	local attach = Instance.new("Attachment")
	attach.Name = "BeamEnd"
	attach.Parent = p
	local gui = Instance.new("BillboardGui")
	gui.Name = "TutorialMarker"
	gui.Size = UDim2.fromOffset(170, 96)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 2000
	gui.Adornee = p
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 0, 40)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = GUIDE
	text.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
	text.TextStrokeTransparency = 0
	text.Text = ""
	text.Parent = gui
	local down = Instance.new("TextLabel")
	down.Name = "Arrow"
	down.BackgroundTransparency = 1
	down.Position = UDim2.fromOffset(0, 40)
	down.Size = UDim2.new(1, 0, 0, 56)
	down.Font = Enum.Font.FredokaOne
	down.TextScaled = true
	down.TextColor3 = GUIDE
	down.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
	down.TextStrokeTransparency = 0
	down.Text = "▼"
	down.Parent = gui
	gui.Parent = p
	local b = Instance.new("Beam")
	b.Name = "TutorialBeam"
	b.Attachment1 = attach
	b.Color = ColorSequence.new(GUIDE)
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.15, 0.25),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	b.Width0 = 0.5
	b.Width1 = 1.4
	b.FaceCamera = true
	b.Segments = 12
	b.Enabled = false
	b.Parent = p
	f.Parent = Workspace
	guideFolder = f
	marker = p
	markerGui = gui
	markerText = text
	beam = b
	return f, p
end

-- 빔 시작점: 내 캐릭터 HumanoidRootPart 의 Attachment (없으면 만듦)
local function beamStart(): Attachment?
	local root = myRoot()
	if not root then
		return nil
	end
	local a = root:FindFirstChild("TutorialAttach")
	if a and a:IsA("Attachment") then
		return a
	end
	local made = Instance.new("Attachment")
	made.Name = "TutorialAttach"
	made.Parent = root
	return made
end

local function clearWorld()
	target = nil
	targetPart = nil
	local gui = markerGui
	if gui then
		gui.Enabled = false
	end
	local b = beam
	if b then
		b.Enabled = false
	end
	local h = highlight
	if h then
		h:Destroy()
		highlight = nil
	end
end

local function pointAt(pos: Vector3, text: string, part: BasePart?)
	local _, p = ensureGuide()
	target = pos
	targetPart = part
	p.CFrame = CFrame.new(pos)
	local gui = markerGui
	if gui then
		gui.Enabled = true
	end
	local label = markerText
	if label then
		label.Text = text
	end
	local b = beam
	local root = myRoot()
	if b then
		local start = beamStart()
		b.Attachment0 = start
		local far = root ~= nil and (root.Position - pos).Magnitude > BEAM_MIN
		b.Enabled = start ~= nil and far
	end
	-- 놓인 알 같은 물건은 노란 테두리
	if part then
		local h = highlight
		if not h or h.Adornee ~= part then
			if h then
				h:Destroy()
			end
			local made = Instance.new("Highlight")
			made.Name = "TutorialHighlight"
			made.FillColor = GUIDE
			made.FillTransparency = 0.6
			made.OutlineColor = GUIDE
			made.OutlineTransparency = 0
			made.Adornee = part
			made.Parent = guideFolder
			highlight = made
		end
	else
		local h = highlight
		if h then
			h:Destroy()
			highlight = nil
		end
	end
end

-- 1단계: 허브면 숲 입구, 숲에 있으면 가장 가까운 둥지(또는 떨어진) 알
local function forestTarget(root: BasePart): (Vector3, string)
	local pos = root.Position
	if pos.Z < MapLayout.SAFE_ZONE_Z then
		return FOREST_ENTRANCE, "숲으로!"
	end
	local best: Vector3? = nil
	local bestD = math.huge
	for _, inst in CollectionService:GetTagged(Tags.Egg) do
		if inst:IsA("BasePart") then
			local state = inst:GetAttribute("EggState")
			local p = inst.Position
			if (state == "Nest" or state == "Dropped") and MapLayout.zoneAt(p.Z) == "forest" then
				local d = (p - pos).Magnitude
				if d < bestD then
					best, bestD = p, d
				end
			end
		end
	end
	if not best then
		for _, spot in MapLayout.nestsFor("forest") do
			local p = Vector3.new(spot.x, 1, spot.z)
			local d = (p - pos).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best or FOREST_ENTRANCE, "알 훔치기!"
end

-- 4단계: 내 우리에 놓인 알 (다 자란 알 먼저)
local function myPlacedEgg(): (BasePart?, boolean)
	local me = Players.LocalPlayer.UserId
	local found: BasePart? = nil
	for _, inst in CollectionService:GetTagged(Tags.IncubatingEgg) do
		if inst:IsA("BasePart") and inst:GetAttribute("OwnerUserId") == me then
			local p, r = inst:GetAttribute("Progress"), inst:GetAttribute("Required")
			local ready = inst:GetAttribute("Ready") == true
				or (typeof(p) == "number" and typeof(r) == "number" and p >= r)
			if ready then
				return inst, true
			end
			found = found or inst
		end
	end
	return found, false
end

local function equipButtons(): { GuiObject }
	local list: { GuiObject } = {}
	if not Windows.isOpen("Pets") then
		return list
	end
	local win = Ui.layer("Windows"):FindFirstChild("Pets")
	if win then
		for _, d in win:GetDescendants() do
			if d:IsA("TextButton") and d.Name == "Equip" and d.Visible then
				table.insert(list, d)
			end
		end
	end
	return list
end

------------------------------------------------------------------
-- 자리 (패널 + 위 가운데 것들 내리기)
------------------------------------------------------------------

function TutorialController.panelRect(): Layout.Rect
	return Layout.tutorialPanel(Ui.area(), Ui.scale(), Ui.isTouch())
end

local function pushOthers(shift: number)
	for _, spec in PUSH do
		local obj = Ui.layer(spec.layer):FindFirstChild(spec.name)
		if obj and obj:IsA("GuiObject") then
			-- 원래 y 는 그 물건의 Attribute 에 기억 (한 번만)
			local saved = obj:GetAttribute("TutorialBaseY")
			local y: number = if typeof(saved) == "number" then saved else obj.Position.Y.Offset
			if typeof(saved) ~= "number" then
				obj:SetAttribute("TutorialBaseY", y)
			end
			local pos = obj.Position
			local want = y + shift
			if pos.Y.Offset ~= want then
				obj.Position = UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, want)
			end
		end
	end
end

local function layoutPanel()
	local p = panel
	if not p then
		return
	end
	local rect = TutorialController.panelRect()
	p.Position = UDim2.new(0.5, 0, 0, rect.y)
	if p.Visible then
		pushOthers(math.max(0, math.ceil(rect.y + rect.h + 6 - PUSH_TOP)))
	else
		pushOthers(0)
	end
end

------------------------------------------------------------------
-- 갱신
------------------------------------------------------------------

function TutorialController.update()
	local p = panel
	local v = current
	if not p then
		return
	end
	if not v or v.done then
		p.Visible = false
		setGlows({})
		clearWorld()
		layoutPanel()
		return
	end
	p.Visible = true
	local total = if typeof(v.total) == "number" and v.total > 0 then v.total else 5
	local step = math.clamp(math.floor(v.step), 1, total)
	local sl, tl, hl = stepLabel, titleLabel, hintLabel
	if sl then
		sl.Text = string.format("%d/%d", step, total)
	end
	if tl then
		tl.Text = tostring(v.text or "")
	end
	if hl then
		hl.Text = tostring(v.hint or "")
	end
	layoutPanel()

	local root = myRoot()
	local glowList: { GuiObject } = {}
	if step == 1 then
		if root then
			local pos, text = forestTarget(root)
			pointAt(pos, text, nil)
		else
			clearWorld()
		end
	elseif step == 2 then
		if root then
			local x = math.clamp(root.Position.X, -60, 60)
			pointAt(Vector3.new(x, 0, MapLayout.SAFE_ZONE_Z - 14), "안전 구역", nil)
		else
			clearWorld()
		end
	elseif step == 3 then
		glowList = HotbarController.eggButtons()
		if #glowList == 0 then
			local egg = HudController.eggButton
			if egg then
				table.insert(glowList, egg)
			end
		end
		local rect = MapLayout.penRect(myPlot())
		if rect then
			local c = MapLayout.rectCenter(rect)
			pointAt(Vector3.new(c.x, 0, c.z), "우리에 놓기", nil)
		else
			clearWorld()
		end
	elseif step == 4 then
		local part, ready = myPlacedEgg()
		if part then
			pointAt(part.Position, if ready then "부화!" else "자라는 중…", part)
		else
			clearWorld()
		end
	else
		clearWorld()
		local pets = HudController.petsButton
		if pets then
			table.insert(glowList, pets)
		end
		for _, b in equipButtons() do
			table.insert(glowList, b)
		end
	end
	setGlows(glowList)
end

local function setView(v: any, fromRemote: boolean)
	if not validView(v) then
		return
	end
	local view = v :: Types.TutorialView
	local prev = current
	current = view
	local step = if view.done then (view.total or 5) + 1 else view.step
	if prev and not view.done and step ~= lastStep then
		SoundController.play("TutorialStep")
		local p = panel
		if p then
			Ui.pop(p, 1.12)
		end
	end
	lastStep = step
	TutorialController.update()
	local reward = view.reward
	if fromRemote and view.done and typeof(reward) == "number" and reward > 0 then
		TutorialController.celebrate(reward)
	end
end

------------------------------------------------------------------
-- 끝! 축하 (색종이 + 팡파레 + "$500 받았어요!")
------------------------------------------------------------------

local CONFETTI = {
	Color3.fromRGB(255, 90, 110),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(90, 220, 110),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 150, 60),
}

function TutorialController.celebrate(reward: number)
	SoundController.play("TutorialDone")
	local layer = Ui.layer("Popups")
	local old = layer:FindFirstChild("TutorialDone")
	if old then
		old:Destroy()
	end
	local holder: Frame = Ui.new("Frame", {
		Name = "TutorialDone",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	local card: Frame = Ui.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(520, 160),
		BackgroundColor3 = C.win,
		BackgroundTransparency = 0.1,
		ZIndex = 5,
		Parent = holder,
	})
	Ui.scaled(card, Vector2.new(520, 160))
	Ui.corner(16).Parent = card
	Ui.stroke(GUIDE, 5).Parent = card
	Ui.label("튜토리얼 끝!", UDim2.new(1, -20, 0, 64), 52, GUIDE, {
		Name = "Title",
		Position = UDim2.fromOffset(10, 8),
		ZIndex = 6,
		Parent = card,
	})
	Ui.label(Format.money(reward) .. " 받았어요!", UDim2.new(1, -20, 0, 60), 46, C.moneyGreen, {
		Name = "Reward",
		Position = UDim2.fromOffset(10, 82),
		ZIndex = 6,
		Parent = card,
	})
	Ui.pop(card, 0.5)
	-- 색종이: 화면 위에서 아래로 빙글빙글
	local rng = Random.new()
	for i = 1, 42 do
		local size = rng:NextNumber(10, 18)
		local startX = rng:NextNumber(0.02, 0.98)
		local piece: Frame = Ui.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(startX, 0, 0, -20 - rng:NextNumber(0, 120)),
			Size = UDim2.fromOffset(size, size * 0.55),
			Rotation = rng:NextNumber(0, 360),
			BackgroundColor3 = CONFETTI[(i - 1) % #CONFETTI + 1],
			ZIndex = 4,
			Parent = holder,
		})
		Ui.tween(piece, TweenInfo.new(rng:NextNumber(1.8, 3), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(startX + rng:NextNumber(-0.12, 0.12), 0, 1, 30),
			Rotation = piece.Rotation + rng:NextNumber(240, 720),
		})
	end
	-- 내 캐릭터 둘레 반짝
	local root = myRoot()
	if root then
		for k, color in { CONFETTI[1], CONFETTI[2], CONFETTI[4] } do
			Fx.burst(root.Position + Vector3.new(0, 2 + k, 0), color, 16, 0.8, 14)
		end
	end
	task.delay(3.6, function()
		holder:Destroy()
	end)
end

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------

function TutorialController.start()
	local p: Frame = Ui.new("Frame", {
		Name = "TutorialPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(Layout.TUTORIAL_W, Layout.TUTORIAL_H),
		BackgroundColor3 = C.win,
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = Ui.layer("Hud"),
	})
	Ui.scaled(p)
	Ui.corner(12).Parent = p
	Ui.stroke(GUIDE, 3).Parent = p
	local badge: Frame = Ui.new("Frame", {
		Name = "StepBadge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(62, Layout.TUTORIAL_H - 12),
		BackgroundColor3 = GUIDE,
		Parent = p,
	})
	Ui.corner(10).Parent = badge
	Ui.stroke(Color3.fromRGB(120, 80, 0), 2).Parent = badge
	stepLabel = Ui.label("1/5", UDim2.fromScale(1, 1), 26, C.white, {
		Name = "Step",
		TextScaled = true,
		Parent = badge,
	})
	titleLabel = Ui.label("", UDim2.new(1, -84, 0, 30), 26, C.white, {
		Name = "Title",
		Position = UDim2.fromOffset(76, 3),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = p,
	})
	hintLabel = Ui.label("", UDim2.new(1, -84, 0, 20), 15, Color3.fromRGB(230, 232, 240), {
		Name = "Hint",
		Position = UDim2.fromOffset(76, 33),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = p,
	})
	panel = p

	-- 화면 가장자리 화살표 (목표가 화면 밖일 때)
	arrow = Ui.label("➤", UDim2.fromOffset(56, 56), 48, GUIDE, {
		Name = "TutorialArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = Ui.layer("Hud"),
	})

	Ui.onLayout(layoutPanel)

	Net.on(Remotes.ToClient.TutorialUpdate, function(v: any)
		setView(v, true)
	end)
	State.onChanged(function(section: string)
		if section == "snapshot" or section == "tutorial" then
			local snap = State.get()
			if snap and validView(snap.tutorial) then
				setView(snap.tutorial, false)
			end
		end
	end)
	local snap = State.get()
	if snap and validView(snap.tutorial) then
		setView(snap.tutorial, false)
	end

	-- 매 프레임: 표시 통통 · 반짝 테두리 맥박 · 화면 가장자리 화살표
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local gui = markerGui
		if gui and gui.Enabled then
			gui.StudsOffset = Vector3.new(0, 7 + math.abs(math.sin(now * 3)) * 1.5, 0)
		end
		for _, f in glows do
			local stroke = f:FindFirstChildOfClass("UIStroke")
			local k = (math.sin(now * 6) + 1) / 2
			if stroke then
				stroke.Transparency = 0.6 * (1 - k)
				stroke.Thickness = 3 + k * 3
			end
			f.Size = UDim2.new(1, 8 + k * 8, 1, 8 + k * 8)
		end
		local a = arrow
		local camera = Workspace.CurrentCamera
		local goal = if targetPart and targetPart.Parent then targetPart.Position else target
		if not a then
			return
		end
		if not (active() and goal and camera) then
			a.Visible = false
			return
		end
		local ok, point, onScreen = pcall(function(): (Vector3, boolean)
			return camera:WorldToViewportPoint(goal :: Vector3)
		end)
		if not ok or (onScreen and point.Z > 0) then
			a.Visible = false
			return
		end
		local view = camera.ViewportSize
		local area = Ui.area()
		local inset = view.Y - area.Y
		local cx, cy = area.X / 2, area.Y / 2
		local dx, dy = point.X - cx, point.Y - inset - cy
		if point.Z < 0 then
			dx, dy = -dx, -dy
		end
		local len = math.sqrt(dx * dx + dy * dy)
		if len < 1 then
			a.Visible = false
			return
		end
		dx, dy = dx / len, dy / len
		local margin = 48
		local sx = if math.abs(dx) > 1e-3 then (cx - margin) / math.abs(dx) else math.huge
		local sy = if math.abs(dy) > 1e-3 then (cy - margin) / math.abs(dy) else math.huge
		local s = math.min(sx, sy)
		a.Position = UDim2.fromOffset(cx + dx * s, cy + dy * s)
		a.Rotation = math.deg(math.atan2(dy, dx))
		a.Visible = true
	end)

	-- 가리킬 곳은 0.25초마다 (내가 움직이거나 알이 생기고 없어짐)
	task.spawn(function()
		while true do
			local ok, err = pcall(function(): ...any
				TutorialController.update()
				return
			end)
			if not ok then
				warn("[TutorialController] " .. tostring(err))
			end
			task.wait(0.25)
		end
	end)
end

return TutorialController
