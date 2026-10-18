--!strict
--[[
	Net (서버) — Remote 생성 + 보내기 + 받기(레이트 리밋 + 에러 격리)

	Remote 이름은 shared/Remotes.luau 한 곳에서만 정의합니다.
	Net.on 으로 연결한 핸들러는:
	  1) 플레이어·Remote 별 토큰 버킷 레이트 리밋 통과해야 실행
	  2) pcall 로 감싸서 한 요청의 에러가 서버 전체를 멈추지 않음
	  3) 인자는 전부 unknown — 핸들러 안에서 Validate 로 검사할 것
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(script.Parent.Logic.RateLimiter)

local Net = {}

local events: { [string]: RemoteEvent } = {}
local limiter = RateLimiter.new(os.clock)
local started = false

local function create(folder: Folder, name: string)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	events[name] = remote
end

function Net.start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = Remotes.FOLDER_NAME
	for _, name in Remotes.ToClient do
		create(folder, name)
	end
	for _, name in Remotes.ToServer do
		create(folder, name)
	end
	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player: Player)
		limiter:forget(player.UserId)
	end)
end

local function get(name: string): RemoteEvent
	local remote = events[name]
	assert(remote, "Net: 알 수 없는 Remote " .. name)
	return remote
end

function Net.fire(player: Player, name: string, ...: any)
	if player.Parent == nil then
		return
	end
	get(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	get(name):FireAllClients(...)
end

-- 알림 한 줄 (kind: "info" | "success" | "error")
function Net.notify(player: Player, kind: string, text: string)
	Net.fire(player, Remotes.ToClient.Notify, { kind = kind, text = text })
end

function Net.on(name: string, handler: (Player, ...unknown) -> ())
	local limit = Remotes.RateLimits[name]
	assert(limit, "Net: 레이트 리밋 정의가 없음 " .. name)
	get(name).OnServerEvent:Connect(function(player: Player, ...: unknown)
		if not limiter:allow(player.UserId, name, limit.burst, limit.perSecond) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] %s 처리 중 오류 (%s): %s", name, player.Name, tostring(err)))
		end
	end)
end

return Net
