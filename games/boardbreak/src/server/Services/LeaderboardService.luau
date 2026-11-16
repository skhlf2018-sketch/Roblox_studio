--!strict
--[[
	LeaderboardService — 힘·돈 순위 (첫 게임 LeaderboardService 와 같은 방식)
	LEADERBOARD_INTERVAL(10)초마다 데이터를 불러온 플레이어의 힘(data.power) · 돈(data.money) 상위 LEADERBOARD_SIZE(10)명을
	  LeaderboardUpdate { power = { {name, value, userId} ... }, money = { ... } } 로 서버 전체에 (fireAll).
	정렬: 값이 큰 사람부터, 같으면 이름 → userId. 새로 들어온 사람에게는 준비되자마자 그 사람에게만 한 번.
	(플레이어 목록 leaderstats "힘" · "돈" 은 Wallet 이 맞춤)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)

type Entry = Types.LeaderEntry

local LeaderboardService = {}

local function displayName(player: Player): string
	local name = player.DisplayName
	return if typeof(name) == "string" and name ~= "" then name else player.Name
end

local function top(entries: { Entry }, size: number): { Entry }
	table.sort(entries, function(a: Entry, b: Entry): boolean
		if a.value ~= b.value then
			return a.value > b.value
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.userId < b.userId
	end)
	local result: { Entry } = {}
	for i = 1, math.min(size, #entries) do
		table.insert(result, entries[i])
	end
	return result
end

function LeaderboardService.build(): Types.LeaderboardUpdate
	local power: { Entry } = {}
	local money: { Entry } = {}
	for _, player in Players:GetPlayers() do
		local _, data = Sessions.getLoaded(player)
		if data then
			local name = displayName(player)
			table.insert(power, { name = name, value = data.power, userId = player.UserId })
			table.insert(money, { name = name, value = data.money, userId = player.UserId })
		end
	end
	return {
		power = top(power, Config.LEADERBOARD_SIZE),
		money = top(money, Config.LEADERBOARD_SIZE),
	}
end

function LeaderboardService.broadcast()
	Net.fireAll(Remotes.ToClient.LeaderboardUpdate, LeaderboardService.build())
end

function LeaderboardService.onPlayerReady(player: Player)
	Net.fire(player, Remotes.ToClient.LeaderboardUpdate, LeaderboardService.build())
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			task.wait(Config.LEADERBOARD_INTERVAL)
			local ok, err = pcall(function(): ...any
				LeaderboardService.broadcast()
				return nil
			end)
			if not ok then
				warn("[LeaderboardService] 순위 오류: " .. tostring(err))
			end
		end
	end)
end

return LeaderboardService
