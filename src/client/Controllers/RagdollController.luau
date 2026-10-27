--!strict
--[[
	RagdollController — 잡혔을 때 내 캐릭터를 로컬에서도 넘어뜨리고 날려 보냄
	(캐릭터 물리는 내 컴퓨터가 계산하므로 여기서 속도를 넣어야 확실히 날아감. 판정·씨앗 처리는 이미 서버가 끝냄)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Net = require(script.Parent.Parent.Net)

local RagdollController = {}

function RagdollController.start()
	local player = Players.LocalPlayer
	Net.on(Remotes.ToClient.Caught, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local seconds = tonumber(payload.ragdollSeconds) or 0
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not humanoid or seconds <= 0 then
			return
		end
		humanoid.PlatformStand = true
		local knockback = payload.knockback
		if root and root:IsA("BasePart") and typeof(knockback) == "Vector3" then
			root.AssemblyLinearVelocity = knockback
		end
		task.delay(seconds, function()
			if humanoid.Parent then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end)
end

return RagdollController
