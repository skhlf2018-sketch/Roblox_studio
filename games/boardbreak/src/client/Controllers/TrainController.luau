--!strict
--[[
	TrainController — 아령 들기 (선임)
	  - 수련 매트(MapLayout.isOnTrainMat) 위에 서면 화면 아래 큰 "들기" 버튼 (터치: 오른쪽 점프 버튼 위). 매트 밖이면 숨김.
	  - 누르는 순간 Train() 한 번 + 누르고 있으면 0.25초마다 (초당 4번). 매트 위에서 화면(빈 곳)을 눌러도 한 번.
	  - 손에 지금 아령(내 화면에만 보이는 파트, 오른손에 붙임)이 생기고, 들 때마다 위로 번쩍 올렸다 내림.
	  - TrainResult { gain, power } → 머리 위 "+N 💪" 숫자가 떠오름.
	서버가 매트 위인지·속도를 다시 검사 (클라는 요청만).
	공개: TrainController.onMat() · button (테스트) · check() (지금 바로 매트 판정)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
local Dumbbells = require(Shared.Data.Dumbbells)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Walk = require(Client.Walk)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local ActionButton = require(Client.UI.ActionButton)

local TrainController = {}
TrainController.button = nil :: ActionButton.Handle?

local C = Theme.Colors
local onMat = false
local held: Model? = nil
local heldWeld: Weld? = nil
local heldLevel = 0
local lifting = false

function TrainController.onMat(): boolean
	return onMat
end

local function sendTrain()
	if onMat then
		Net.send(Remotes.ToServer.Train)
	end
end

-- 손에 든 아령 (내 화면에만 — 클라가 만든 파트는 복제 안 됨)
local function dumbbellColor(level: number): Color3
	local t = (level - 1) / 19
	if level >= 20 then
		return Color3.fromRGB(30, 20, 40)
	end
	return Color3.fromHSV((0.6 - t * 0.9) % 1, 0.55 + t * 0.3, 0.95 - t * 0.2)
end

local function dropHeld()
	local m = held
	if m then
		m:Destroy()
	end
	held = nil
	heldWeld = nil
	heldLevel = 0
end

local function makeHeld(level: number)
	dropHeld()
	local character = Players.LocalPlayer.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local model = Instance.new("Model")
	model.Name = "HeldDumbbell"
	local size = 0.6 + level * 0.03
	local function piece(name: string, s: Vector3, offset: CFrame, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = s
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Color = color
		p.Material = Enum.Material.Metal
		p.CFrame = hand.CFrame * offset
		p.Parent = model
		return p
	end
	local bar =
		piece("Bar", Vector3.new(1.6, 0.25, 0.25), CFrame.new(0, -0.9, 0) * CFrame.Angles(0, math.rad(90), 0), C.gray)
	piece(
		"PlateA",
		Vector3.new(0.35, size * 1.6, size * 1.6),
		bar.CFrame * CFrame.new(-0.7, 0, 0),
		dumbbellColor(level)
	)
	piece("PlateB", Vector3.new(0.35, size * 1.6, size * 1.6), bar.CFrame * CFrame.new(0.7, 0, 0), dumbbellColor(level))
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= bar then
			local w = Instance.new("WeldConstraint")
			w.Part0 = bar
			w.Part1 = p
			w.Parent = p
		end
	end
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = bar
	weld.C0 = CFrame.new(0, -0.9, 0) * CFrame.Angles(0, math.rad(90), 0)
	weld.Parent = bar
	model.PrimaryPart = bar
	model.Parent = character
	held = model
	heldWeld = weld
	heldLevel = level
end

-- 번쩍 들기 (아령을 머리 위쪽으로 0.12초 올렸다 내림)
local function liftAnimation()
	local weld = heldWeld
	if not weld or lifting then
		return
	end
	lifting = true
	local base = CFrame.new(0, -0.9, 0) * CFrame.Angles(0, math.rad(90), 0)
	weld.C0 = base * CFrame.new(0, 0, 0) + Vector3.new(0, 1.6, 0)
	task.delay(0.12, function()
		local w = heldWeld
		if w then
			w.C0 = base
		end
		lifting = false
	end)
end

-- 머리 위 "+N 💪"
function TrainController.popGain(gain: number)
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "GainPopup"
	gui.Size = UDim2.fromOffset(160, 44)
	gui.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2.4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = head
	local label = Ui.label("+" .. Format.number(gain) .. " 💪", UDim2.fromScale(1, 1), 30, C.power, {
		Name = "Text",
		TextScaled = true,
		Parent = gui,
	})
	gui.Parent = Players.LocalPlayer:FindFirstChild("PlayerGui") or Workspace
	Ui.tween(gui, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { StudsOffset = gui.StudsOffset + Vector3.new(0, 2.5, 0) })
	Ui.tween(label, TweenInfo.new(0.7), { TextTransparency = 1 })
	task.delay(0.75, function()
		gui:Destroy()
	end)
end

function TrainController.check()
	local root = Walk.root()
	local now = root ~= nil and MapLayout.isOnTrainMat(root.CFrame.Position, State.currentWorld())
	if now ~= onMat then
		onMat = now
		local b = TrainController.button
		if b then
			b.setVisible(now)
		end
	end
	if onMat then
		local level = State.dumbbell()
		if level ~= heldLevel or not (held and held.Parent) then
			makeHeld(level)
		end
		local b = TrainController.button
		local d = Dumbbells.get(level)
		if b and d then
			b.setText("들기", d.name)
		end
	elseif held then
		dropHeld()
	end
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
			liftAnimation()
		end
	end)

	-- 매트 위에서 화면(버튼이 아닌 곳)을 누르면 한 번 들기
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not onMat then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			sendTrain()
		end
	end)

	Players.LocalPlayer.CharacterAdded:Connect(function()
		heldLevel = 0
		held = nil
		heldWeld = nil
	end)

	-- 0.15초마다 매트 판정
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 0.15 then
			acc = 0
			TrainController.check()
		end
	end)
	TrainController.check()
end

return TrainController
