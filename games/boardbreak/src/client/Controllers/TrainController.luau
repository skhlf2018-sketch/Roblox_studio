--!strict
--[[
	TrainController — 아령 들기 (선임)
	  - 수련 매트(MapLayout.isOnTrainMat) 위에 서면 화면 아래 큰 "들기" 버튼 (터치: 오른쪽 점프 버튼 위). 매트 밖이면 숨김.
	  - 누르는 순간 Train() 한 번 + 누르고 있으면 0.25초마다 (초당 4번).
	    매트 위에서 화면 "빈 곳"을 눌러도 한 번 — 물건·버튼·표지판(ClickDetector 가 있는 모델)을 누른 것이면 들기는 안 보냄
	    (물건 클릭은 BreakController 가 Hit 만 보냄).
	  - 손에 진짜 아령 (shared/DumbbellLook: 손잡이 봉 + 원판, 무거울수록 크고 여러 장 · 상한 넘으면 빛).
	    크기 = 몸 배율(캐릭터 Attr VisualScale — 서버 PlayerVisualService 가 몸을 키운 값) × Sizes.dumbbellScale(단계) (사장님 결정 13번).
	    몸 배율·손 크기가 바뀌면 같은 프레임에 새로 만들어 바꿔 끼움 (2% 단위). 아령이 카메라 → 내 머리 선을 가리면 반투명 (내 화면만).
	  - 매트 판정 = 서버 SizeService 와 같게: 그대로 또는 큰 몸이면 뿌리를 3 × (몸 배율 − 1) 내려서 (TrainController.matAt)
	    아령 Model 의 모든 부품은 손잡이(PrimaryPart "Bar")에 Weld, 손잡이는 손 파트(R15 RightHand / R6 Right Arm)에 Weld.
	    전부 Massless · 안 부딪힘 · 안 맞음 · Anchored 아님. 손 파트가 바뀌면(리스폰·아바타 늦게 로딩) 다시 붙임.
	    무거운 아령(DumbbellLook.twoHands)은 왼손에도 하나 더 → 두 손으로 듦.
	  - 들 때마다 Lift(팔 Motor6D C0) 로 아령을 가슴 → 머리 위로 들어 올렸다 내림 (0.25초 왕복, 누르고 있으면 반복).
	  - 다른 플레이어: 그 사람 Attr Power 가 오르고 매트 위면 내 화면에서도 그 사람 손에 아령 + 같은 팔 동작
	    (클라에서 바꾼 C0·만든 파트는 복제되지 않으므로 각 클라가 직접 그림).
	  - TrainResult { gain, power } → 머리 위 "+N 💪" 숫자가 떠오름.
	서버가 매트 위인지·속도를 다시 검사 (클라는 요청만).
	공개: TrainController.onMat() · button (테스트) · check() · attach(character, level) · pickAt(input) (테스트가 바꿀 수 있음)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
local Dumbbells = require(Shared.Data.Dumbbells)
local Sizes = require(Shared.Data.Sizes)
local DumbbellLook = require(Shared.DumbbellLook)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Walk = require(Client.Walk)
local Lift = require(Client.Lift)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local ActionButton = require(Client.UI.ActionButton)

local TrainController = {}
TrainController.button = nil :: ActionButton.Handle?

local C = Theme.Colors
local PAttr = Tags.PlayerAttributes
local onMat = false

-- key = 아령 크기를 정한 값 (단계 · 몸 배율 · 손 크기) — 하나라도 바뀌면 새로 만들어 붙임 (2% 단위라 드묾, 같은 프레임에 바꿔 끼워 깜빡임 없음)
type Hold = {
	level: number,
	scale: number,
	handY: number,
	fade: number?,
	right: Model?,
	left: Model?,
	rightHand: BasePart?,
	leftHand: BasePart?,
}
local holds: { [Model]: Hold } = {}

function TrainController.onMat(): boolean
	return onMat
end

------------------------------------------------------------------
-- 손에 든 아령
------------------------------------------------------------------

local function handOf(character: Model, right: boolean): BasePart?
	local names: { string } = if right then { "RightHand", "Right Arm" } else { "LeftHand", "Left Arm" }
	for _, name in names do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

-- 손바닥에 쥔 자리: 손 파트 아래쪽 가운데, 봉은 손의 X 축(옆)으로 — 팔을 앞으로 올려도 봉은 수평
local function grip(hand: BasePart): CFrame
	local r6 = hand.Name == "Right Arm" or hand.Name == "Left Arm"
	return CFrame.new(0, if r6 then -hand.Size.Y / 2 + 0.15 else -hand.Size.Y * 0.2, 0)
end

-- 손에 든 아령 배율 = 몸 배율 × 아령 단계 배율 (사장님 결정 13번: 가장 큰 몸 + 마지막 아령 = 아파트 높이 × 2)
function TrainController.heldScale(character: Model, level: number): number
	local raw = character:GetAttribute("VisualScale")
	local body = if type(raw) == "number" and raw > 0 then raw else 1
	if character == Players.LocalPlayer.Character and raw == nil then
		body = State.bodyScale()
	end
	return body * Sizes.dumbbellScale(level)
end

local function makeOne(character: Model, hand: BasePart, level: number, name: string, scale: number): Model
	local g = grip(hand)
	local model = DumbbellLook.build(nil, level, scale, false, hand.CFrame * g)
	model.Name = name
	local bar = model.PrimaryPart :: BasePart
	local weld = Instance.new("Weld")
	weld.Name = "HandWeld"
	weld.Part0 = hand
	weld.Part1 = bar
	weld.C0 = g
	weld.Parent = bar
	model.Parent = character
	return model
end

local function dropHold(character: Model)
	local h = holds[character]
	holds[character] = nil
	if h then
		if h.right then
			h.right:Destroy()
		end
		if h.left then
			h.left:Destroy()
		end
	end
	for _, name in { "HeldDumbbell", "HeldDumbbellL" } do
		local old = character:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

-- 아령이 아직 그 손에 제대로 붙어 있나 (손이 바뀌었거나 Weld 가 끊기면 false)
local function attached(model: Model?, hand: BasePart?, character: Model, right: boolean): boolean
	if not (model and hand and model.Parent == character and hand.Parent == character) then
		return false
	end
	if handOf(character, right) ~= hand then
		return false
	end
	local bar = model.PrimaryPart
	local weld = bar and bar:FindFirstChild("HandWeld")
	return weld ~= nil and weld:IsA("Weld") and weld.Part0 == hand and weld.Part1 == bar
end

-- 캐릭터 손에 level 아령 (이미 맞게 붙어 있으면 그대로). 손 파트가 없으면 아무것도 안 함 (오류 없음)
function TrainController.attach(character: Model?, level: number): Model?
	if not character then
		return nil
	end
	local spec = DumbbellLook.spec(level)
	local h = holds[character]
	local right = handOf(character, true)
	local left = if spec.twoHands then handOf(character, false) else nil
	local scale = TrainController.heldScale(character, spec.level)
	local handY = if right then right.Size.Y else 0
	if
		h
		and h.level == spec.level
		and math.abs(h.scale - scale) < 1e-3
		and math.abs(h.handY - handY) < 1e-3
		and attached(h.right, h.rightHand, character, true)
		and (not spec.twoHands or left == nil or attached(h.left, h.leftHand, character, false))
	then
		return h.right
	end
	dropHold(character)
	if not right then
		return nil
	end
	local made: Hold = { level = spec.level, scale = scale, handY = handY, rightHand = right, leftHand = left }
	made.right = makeOne(character, right, spec.level, "HeldDumbbell", scale)
	if left then
		made.left = makeOne(character, left, spec.level, "HeldDumbbellL", scale)
	end
	holds[character] = made
	return made.right
end

local function liftKind(level: number): string
	return if DumbbellLook.spec(level).twoHands then "two" else "one"
end

local function sendTrain()
	if onMat then
		Net.send(Remotes.ToServer.Train)
		Lift.play(Players.LocalPlayer.Character, liftKind(State.dumbbell()))
	end
end

------------------------------------------------------------------
-- 화면을 누른 곳이 물건·시설(ClickDetector)인가
------------------------------------------------------------------

-- 누른 화면 자리 아래 3D 파트 (없거나 알 수 없으면 nil). 테스트는 이 함수를 바꿔 끼움
function TrainController.pickAt(input: any): Instance?
	local camera = Workspace.CurrentCamera
	local pos = input and input.Position
	if not camera or typeof(pos) ~= "Vector3" then
		return nil
	end
	local ok, hit = pcall(function(): Instance?
		local ray = camera:ScreenPointToRay(pos.X, pos.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local mine = Players.LocalPlayer.Character
		params.FilterDescendantsInstances = if mine then { mine } else {}
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		return if result then result.Instance else nil
	end)
	return if ok then hit else nil
end

function TrainController.isClickable(inst: Instance?): boolean
	local node = inst
	while node and node ~= Workspace do
		if node:FindFirstChildOfClass("ClickDetector") then
			return true
		end
		node = node.Parent
	end
	return false
end

------------------------------------------------------------------
-- 머리 위 "+N 💪"
------------------------------------------------------------------

function TrainController.popGain(gain: number)
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "GainPopup"
	gui.Size = UDim2.fromOffset(160, 44)
	local k = State.bodyScale() -- 큰 몸이면 머리도 큼 → 그만큼 위에
	gui.StudsOffset = Vector3.new(math.random(-10, 10) / 10 * k, 2.4 * k, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = head
	local label = Ui.label("+" .. Format.number(gain) .. " 💪", UDim2.fromScale(1, 1), 30, C.power, {
		Name = "Text",
		TextScaled = true,
		Parent = gui,
	})
	gui.Parent = Players.LocalPlayer:FindFirstChild("PlayerGui") or Workspace
	Ui.tween(
		gui,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad),
		{ StudsOffset = gui.StudsOffset + Vector3.new(0, 2.5 * k, 0) }
	)
	Ui.tween(label, TweenInfo.new(0.7), { TextTransparency = 1 })
	task.delay(0.75, function()
		gui:Destroy()
	end)
end

------------------------------------------------------------------
-- 다른 플레이어 (내 화면에서 그 사람 손 아령 + 팔 동작)
------------------------------------------------------------------

-- 매트 위인가 — 서버 SizeService.isOnTrainMat 과 같은 규칙: 그대로 또는 (큰 몸이면) 뿌리를 3 × (몸 배율 − 1) 내려서
function TrainController.matAt(pos: Vector3, world: number, bodyScale: number): boolean
	if MapLayout.isOnTrainMat(pos, world) then
		return true
	end
	local extra = 3 * (math.max(1, bodyScale) - 1)
	return extra > 0 and MapLayout.isOnTrainMat(pos - Vector3.new(0, extra, 0), world)
end

local function otherOnMat(p: Player): (Model?, boolean)
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart")) then
		return character, false
	end
	local world = tonumber(p:GetAttribute(PAttr.CurrentWorld)) or 1
	local body = tonumber(p:GetAttribute(PAttr.BodyScale)) or 1
	return character, TrainController.matAt(root.CFrame.Position, world, body)
end

------------------------------------------------------------------
-- 큰 아령이 내 화면을 가리면 반투명 (내 화면에서만, LocalTransparencyModifier)
------------------------------------------------------------------

TrainController.FADE = 0.7

-- 점 p 에서 선분 a-b 까지 거리
local function pointSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (a + ab * t - p).Magnitude
end

-- 아령(봉 + 원판)이 카메라 → 머리 선을 가리나
function TrainController.blocksView(model: Model, camPos: Vector3, focus: Vector3): boolean
	local bar = model.PrimaryPart
	if not bar then
		return false
	end
	local radius = 0
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			radius = math.max(radius, d.Size.Y / 2)
		end
	end
	local half = bar.Size.X / 2
	local axis = bar.CFrame.RightVector
	local c = bar.CFrame.Position
	for i = 0, 8 do
		local p = c + axis * (-half + (i / 8) * 2 * half)
		if pointSegment(p, camPos, focus) <= radius then
			return true
		end
	end
	return false
end

local function fadeHeld(character: Model)
	local h = holds[character]
	if not h then
		return
	end
	local camera = Workspace.CurrentCamera
	local head = character:FindFirstChild("Head")
	if not camera or not (head and head:IsA("BasePart")) then
		return
	end
	local camPos = camera.CFrame.Position
	local focus = head.CFrame.Position
	local blocked = false
	for _, m in { h.right, h.left } do
		if m and TrainController.blocksView(m, camPos, focus) then
			blocked = true
		end
	end
	local alpha = if blocked then TrainController.FADE else 0
	if h.fade == alpha then
		return
	end
	h.fade = alpha
	for _, m in { h.right, h.left } do
		if m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = alpha
				end
			end
		end
	end
end

-- 테스트용: 지금 든 아령의 반투명 값 (없으면 nil)
function TrainController.fadeOf(character: Model): number?
	local h = holds[character]
	return if h then h.fade else nil
end

local watched: { [Player]: boolean } = {}

local function watchPlayer(p: Player)
	if p == Players.LocalPlayer or watched[p] then
		return
	end
	watched[p] = true
	local last = tonumber(p:GetAttribute(PAttr.Power)) or 0
	p:GetAttributeChangedSignal(PAttr.Power):Connect(function()
		local now = tonumber(p:GetAttribute(PAttr.Power)) or 0
		local up = now > last
		last = now
		local character, on = otherOnMat(p)
		if up and on and character then
			local level = tonumber(p:GetAttribute(PAttr.DumbbellLevel)) or 1
			TrainController.attach(character, level)
			Lift.play(character, liftKind(level))
		end
	end)
end

local function checkOthers()
	for _, p in Players:GetPlayers() do
		if p ~= Players.LocalPlayer then
			watchPlayer(p)
			local character, on = otherOnMat(p)
			if character then
				if on then
					TrainController.attach(character, tonumber(p:GetAttribute(PAttr.DumbbellLevel)) or 1)
				elseif holds[character] then
					dropHold(character)
				end
			end
		end
	end
	for character in holds do
		if not character.Parent then
			holds[character] = nil
		end
	end
end

------------------------------------------------------------------

function TrainController.check()
	local root = Walk.root()
	local now = root ~= nil and TrainController.matAt(root.CFrame.Position, State.currentWorld(), State.bodyScale())
	if now ~= onMat then
		onMat = now
		local b = TrainController.button
		if b then
			b.setVisible(now)
		end
	end
	local character = Players.LocalPlayer.Character
	if onMat then
		local level = State.dumbbell()
		TrainController.attach(character, level)
		local b = TrainController.button
		local d = Dumbbells.get(level)
		if b and d then
			b.setText("들기", d.name)
		end
		if character then
			fadeHeld(character)
		end
	elseif character and (holds[character] or character:FindFirstChild("HeldDumbbell")) then
		dropHold(character)
	end
end

local function onCharacter(character: Model)
	-- 리스폰: 새 몸. 손 파트가 늦게 생기거나 아바타 모양이 바뀌면 check() 가 다시 붙임
	task.spawn(function()
		local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
		if hand and onMat then
			TrainController.attach(character, State.dumbbell())
		end
	end)
end

function TrainController.start()
	local button = ActionButton.new("TrainButton", "들기", C.trainRed, 0, "dumbbell", sendTrain)
	TrainController.button = button

	Net.on(Remotes.ToClient.TrainResult, function(r: any)
		if type(r) ~= "table" then
			return
		end
		local gain = tonumber(r.gain) or 0
		if gain > 0 then
			TrainController.popGain(gain)
		end
	end)

	-- 매트 위에서 화면(버튼이 아닌 빈 곳)을 누르면 한 번 들기. 물건·시설을 누른 것이면 안 보냄 (그건 치기/열기)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not onMat then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if TrainController.isClickable(TrainController.pickAt(input)) then
				return
			end
			sendTrain()
		end
	end)

	local lp = Players.LocalPlayer
	lp.CharacterAdded:Connect(function(character: Model)
		local old = {}
		for ch in holds do
			if ch ~= character and ch.Parent == nil then
				table.insert(old, ch)
			end
		end
		for _, ch in old do
			holds[ch] = nil
		end
		onCharacter(character)
	end)
	pcall(function()
		(lp :: any).CharacterAppearanceLoaded:Connect(function(character: Model)
			-- 아바타 모양이 늦게 바뀌면 손 파트가 새로 생김 → 다시 붙이기
			dropHold(character)
			if onMat then
				TrainController.attach(character, State.dumbbell())
			end
		end)
	end)
	pcall(function()
		Players.PlayerAdded:Connect(watchPlayer)
	end)

	-- 팔 동작은 매 프레임, 매트 판정은 0.15초마다
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		Lift.step(dt)
		acc += dt
		if acc >= 0.15 then
			acc = 0
			TrainController.check()
			checkOthers()
		end
	end)
	TrainController.check()
end

return TrainController
