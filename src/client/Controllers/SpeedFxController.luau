--!strict
--[[
	SpeedFxController — 속도 체감 (4판, 사장님: "체감 속도 더 빠르게")
	  달리는 동안 WalkSpeed 가 빠를수록 카메라 시야(FOV)를 70 → 95 로 넓혀 더 빨라 보이게 함.
	  멈추면 다시 70. 카메라가 Scriptable(연출 중)이면 손대지 않음.

	8판 속도 획득 팝업 (원작 디테일, 사장님 2026-11-08): 속도가 오를 때 화면 위 가운데에 분홍 배지
	  [👟 +4B] 가 잠깐 톡 튀었다 사라짐. SpeedFxController.popGain(amount) 하나로 모음:
	    · 러닝머신 걸음 TreadmillStep (TreadmillController, 1초마다 — 같은 배지 숫자만 바뀜)
	    · 도감 보상 IndexRewarded.speed (NotifyController)
	  배지는 처음 한 번만 만들고(Alerts 층 "SpeedPop"), 팝업마다 글자·위치만 바꿈 (Instance 안 만듦).
	  구역 배너("ZoneBanner")가 떠 있으면 그 아래, 아니면 그 자리 (위 가운데에서 서로 안 겹침).
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Format = require(Shared.Format)
local Client = script.Parent.Parent
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Ui = require(Client.UI.Ui)

local FOV_MIN = 70
local FOV_MAX = 95
local LERP_PER_SECOND = 4

local SpeedFxController = {}

local C = Theme.Colors
local PINK = Color3.fromRGB(255, 90, 170) -- 원작 러닝머신 "+500" 분홍
SpeedFxController.POP_SIZE = Vector2.new(240, 60) -- 배지 기준 크기 (폰에서는 Ui.scaled 로 작아짐)
SpeedFxController.POP_SECONDS = 1.2 -- 마지막으로 오른 뒤 이만큼 보임

function SpeedFxController.targetFov(walkSpeed: number, moving: boolean): number
	if not moving then
		return FOV_MIN
	end
	local span = math.max(1, Config.SPEED_WALK_MAX - Config.SPEED_LOG_BASE)
	local t = math.clamp((walkSpeed - Config.SPEED_LOG_BASE) / span, 0, 1)
	return FOV_MIN + (FOV_MAX - FOV_MIN) * t
end

------------------------------------------------------------------
-- 속도 획득 배지
------------------------------------------------------------------

local pop: Frame? = nil
local popText: TextLabel? = nil
local popScale: UIScale? = nil
local popToken = 0
local POP_TOP = 52 -- 구역 배너와 같은 줄 (튜토리얼 패널이 밀면 구역 배너를 따라 내려감)

local function buildPop(): Frame
	local existing = pop
	if existing then
		return existing
	end
	local size = SpeedFxController.POP_SIZE
	local frame: Frame = Ui.new("Frame", {
		Name = "SpeedPop",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, POP_TOP),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = PINK,
		Visible = false,
		Parent = Ui.layer("Alerts"),
	})
	Ui.scaled(frame)
	popScale = frame:FindFirstChild("ScreenScale") :: UIScale?
	Ui.corner(30).Parent = frame
	Ui.stroke(C.winEdge, 4).Parent = frame
	Ui.gradient(Theme.lighter(PINK, 0.25), Theme.darker(PINK, 0.15)).Parent = frame
	Icons.draw("shoe", frame, 44, UDim2.new(0, 34, 0.5, 0))
	popText = Ui.label("", UDim2.new(1, -70, 1, 0), 40, C.white, {
		Name = "Amount",
		Position = UDim2.fromOffset(62, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Parent = frame,
	})
	pop = frame
	return frame
end

-- 지금 배지가 놓일 y (구역 배너가 보이면 그 바로 아래)
function SpeedFxController.popTop(): number
	local zone = Ui.layer("Alerts"):FindFirstChild("ZoneBanner")
	if zone and zone:IsA("GuiObject") then
		local top = zone.Position.Y.Offset
		if zone.Visible then
			local s = zone:FindFirstChild("ScreenScale")
			local k = if s and s:IsA("UIScale") then s.Scale else 1
			return math.floor(top + zone.Size.Y.Offset * k + 6)
		end
		return top
	end
	return POP_TOP
end

-- "+4B" 배지 (amount > 0 일 때만). 띄웠으면 true
function SpeedFxController.popGain(amount: number): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return false
	end
	local frame = buildPop()
	local label = popText
	if label then
		label.Text = "+" .. Format.number(amount)
	end
	frame.Position = UDim2.new(0.5, 0, 0, SpeedFxController.popTop())
	frame.Visible = true
	Ui.pop(frame, 1.25)
	popToken += 1
	local token = popToken
	task.delay(SpeedFxController.POP_SECONDS, function()
		if popToken == token then
			frame.Visible = false
		end
	end)
	return true
end

-- 배지 화면 상자 (테스트: 폰에서 다른 것과 안 겹치는지)
function SpeedFxController.popRect(area: Vector2): { x: number, y: number, w: number, h: number }
	local frame = buildPop()
	local s = popScale
	local k = if s then s.Scale else 1
	local w, h = frame.Size.X.Offset * k, frame.Size.Y.Offset * k
	return { x = area.X / 2 - w / 2, y = SpeedFxController.popTop(), w = w, h = h }
end

function SpeedFxController.start()
	buildPop()
	local player = Players.LocalPlayer
	local current = FOV_MIN
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera or camera.CameraType == Enum.CameraType.Scriptable then
			return
		end
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		-- "달리는 중" = 실제로 수평으로 움직이는 중 (MoveDirection 은 MoveTo 로 움직일 땐 0 이라 속도로 판단)
		local moving = false
		if root and root:IsA("BasePart") then
			local v = root.AssemblyLinearVelocity
			moving = Vector3.new(v.X, 0, v.Z).Magnitude > 2
		end
		local target = SpeedFxController.targetFov(if humanoid then humanoid.WalkSpeed else 0, moving)
		current += (target - current) * math.min(1, dt * LERP_PER_SECOND)
		camera.FieldOfView = current
	end)
end

return SpeedFxController
