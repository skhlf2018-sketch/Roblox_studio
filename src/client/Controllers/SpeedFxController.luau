--!strict
--[[
	SpeedFxController — 속도 체감 (4판, 사장님: "체감 속도 더 빠르게")
	  달리는 동안 WalkSpeed 가 빠를수록 카메라 시야(FOV)를 70 → 95 로 넓혀 더 빨라 보이게 함.
	  멈추면 다시 70. 카메라가 Scriptable(연출 중)이면 손대지 않음.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Data.Config)

local FOV_MIN = 70
local FOV_MAX = 95
local LERP_PER_SECOND = 4

local SpeedFxController = {}

function SpeedFxController.targetFov(walkSpeed: number, moving: boolean): number
	if not moving then
		return FOV_MIN
	end
	local span = math.max(1, Config.SPEED_WALK_MAX - Config.SPEED_LOG_BASE)
	local t = math.clamp((walkSpeed - Config.SPEED_LOG_BASE) / span, 0, 1)
	return FOV_MIN + (FOV_MAX - FOV_MIN) * t
end

function SpeedFxController.start()
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
