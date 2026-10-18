--!strict
--[[
	ToolController — 서버가 준 도구(Tool, 이름 = 종류)를 쓰면 UseTool(종류) 요청만 보냄
	대상 찾기·판정은 전부 서버 (ToolService). 모바일 버튼을 따로 만들 때도 Net.send("UseTool", kind) 만 부르면 됨.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Net = require(script.Parent.Parent.Net)

local ToolController = {}

local hooked: { [Tool]: boolean } = {}

local function isKnownKind(name: string): boolean
	for _, kind in Remotes.ToolKinds do
		if kind == name then
			return true
		end
	end
	return false
end

local function hook(instance: Instance)
	if not instance:IsA("Tool") or hooked[instance] or not isKnownKind(instance.Name) then
		return
	end
	local tool = instance
	hooked[tool] = true
	tool.Activated:Connect(function()
		Net.send(Remotes.ToServer.UseTool, tool.Name)
	end)
	tool.Destroying:Connect(function()
		hooked[tool] = nil
	end)
end

local function watch(container: Instance)
	for _, child in container:GetChildren() do
		hook(child)
	end
	container.ChildAdded:Connect(hook)
end

function ToolController.start()
	local player = Players.LocalPlayer
	local backpack = player:WaitForChild("Backpack")
	watch(backpack)
	player.CharacterAdded:Connect(function(character: Model)
		watch(character)
		local newBackpack = player:WaitForChild("Backpack")
		if newBackpack ~= backpack then
			backpack = newBackpack
			watch(newBackpack)
		end
	end)
	if player.Character then
		watch(player.Character)
	end
end

return ToolController
