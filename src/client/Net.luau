--!strict
--[[
	Net (클라) — 서버가 만든 ReplicatedStorage.Remotes 의 RemoteEvent 를 기다려 받아 씀
	  Net.on("Snapshot", function(snapshot) ... end)
	  Net.send("HatchEgg", eggUid)
	이름은 shared/Remotes.luau 의 Remotes.ToClient / Remotes.ToServer 를 쓰세요.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Net = {}

local folder: Instance? = nil
local cache: { [string]: RemoteEvent } = {}

local function getFolder(): Instance
	local f = folder
	if f then
		return f
	end
	local found = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	folder = found
	return found
end

function Net.get(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	local remote = getFolder():WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), "Net: RemoteEvent 가 아님 " .. name)
	cache[name] = remote
	return remote
end

function Net.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	return Net.get(name).OnClientEvent:Connect(handler)
end

function Net.send(name: string, ...: any)
	Net.get(name):FireServer(...)
end

return Net
