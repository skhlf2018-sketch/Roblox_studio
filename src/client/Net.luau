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

-- 2판처럼 서버에 아직 없을 수도 있는 Remote: 기다리는 동안 부른 쪽을 멈추지 않음 (따로 기다렸다가 연결)
function Net.onLater(name: string, handler: (...any) -> ())
	task.spawn(function()
		local ok, err = pcall(function()
			Net.on(name, handler)
		end)
		if not ok then
			warn("[Net] " .. name .. " 연결 실패: " .. tostring(err))
		end
	end)
end

-- 있으면 보내고, 아직 없으면 조용히 버림 (버튼이 멈추지 않게). 보냈으면 true
function Net.trySend(name: string, ...: any): boolean
	local remote = cache[name]
	if not remote then
		local f = folder or ReplicatedStorage:FindFirstChild(Remotes.FOLDER_NAME)
		local found = if f then f:FindFirstChild(name) else nil
		if found and found:IsA("RemoteEvent") then
			cache[name] = found
			remote = found
		end
	end
	if remote then
		remote:FireServer(...)
		return true
	end
	warn("[Net] Remote 아직 없음: " .. name)
	return false
end

return Net
