--!strict
--[[
	LeaderboardService — 랭킹판 (5판, 사장님 지시)

	LEADERBOARD_INTERVAL(10)초마다 접속 중인 플레이어(데이터를 불러온 사람만)의
	  돈(data.money) · 속도(실효 속도 = Attr Speed, session.effectiveSpeed) 상위 LEADERBOARD_SIZE(10)명을
	  LeaderboardUpdate { money = { {name, value, userId} ... }, speed = { ... } } 로 서버 전체에 (fireAll).
	  정렬: 값이 큰 사람부터, 같으면 이름 → userId 순 (화면이 매번 뒤섞이지 않게).
	새로 들어온 사람에게는 준비되자마자 그 사람에게만 한 번 보냄 (10초를 안 기다리게).
	클라 화면(오른쪽 위 랭킹·허브 판)은 선임 몫 — 모양은 docs/REMOTES.md 1절.
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

type Entry = Types.LeaderboardEntry

local LeaderboardService = {}

local function displayName(player: Player): string
	local name = player.DisplayName
	return if typeof(name) == "string" and name ~= "" then name else player.Name
end

-- 큰 값부터 (같으면 이름, 그다음 userId) 최대 size 줄
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

-- 지금 랭킹판 만들기
function LeaderboardService.build(): Types.Leaderboard
	local money: { Entry } = {}
	local speed: { Entry } = {}
	for _, player in Players:GetPlayers() do
		local session, data = Sessions.getLoaded(player)
		if session and data then
			local name = displayName(player)
			table.insert(money, { name = name, value = data.money, userId = player.UserId })
			table.insert(speed, { name = name, value = session.effectiveSpeed, userId = player.UserId })
		end
	end
	return {
		money = top(money, Config.LEADERBOARD_SIZE),
		speed = top(speed, Config.LEADERBOARD_SIZE),
	}
end

-- 서버 전체에 보내기
function LeaderboardService.broadcast()
	Net.fireAll(Remotes.ToClient.LeaderboardUpdate, LeaderboardService.build())
end

-- 막 준비된 사람에게만 지금 판을 한 번
function LeaderboardService.onPlayerReady(player: Player)
	Net.fire(player, Remotes.ToClient.LeaderboardUpdate, LeaderboardService.build())
end

-- 10초 틱 (pcall 로 감쌈: 오류가 나도 다음 틱은 돔)
local function tick(): ...any
	LeaderboardService.broadcast()
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			task.wait(Config.LEADERBOARD_INTERVAL)
			local ok, err = pcall(tick)
			if not ok then
				warn("[LeaderboardService] 랭킹 오류: " .. tostring(err))
			end
		end
	end)
end

return LeaderboardService
