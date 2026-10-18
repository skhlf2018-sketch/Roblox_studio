--!strict
--[[
	State (클라) — 서버가 보낸 Snapshot + DataUpdate 를 합쳐 둔 "내 상태" (UI 가 읽는 곳)

	  local State = require(ReplicatedStorage.Client.State)
	  State.onChanged(function(section) ... end)   -- section: "snapshot" | "pets" | "incubators" | ...
	  local snap = State.get()                     -- Types.Snapshot? (아직 안 받았으면 nil)

	돈·속도처럼 자주 바뀌는 값은 Players.LocalPlayer:GetAttribute("Money") 등으로 읽으세요 (Tags.PlayerAttributes).
	이 모듈은 표시용 복사본일 뿐이고, 진짜 값은 항상 서버에 있습니다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(script.Parent.Net)

local State = {}

local snapshot: Types.Snapshot? = nil
local listeners: { (string) -> () } = {}

local function emit(section: string)
	for _, listener in table.clone(listeners) do
		task.spawn(listener, section)
	end
end

function State.get(): Types.Snapshot?
	return snapshot
end

function State.onChanged(listener: (string) -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

function State.start()
	Net.on(Remotes.ToClient.Snapshot, function(data: Types.Snapshot)
		snapshot = data
		emit("snapshot")
	end)
	Net.on(Remotes.ToClient.DataUpdate, function(section: string, payload: { [string]: any })
		local current = snapshot
		if current and typeof(payload) == "table" then
			local target = current :: any
			for key, value in payload do
				target[key] = value
			end
		end
		emit(section)
	end)
end

return State
