--!strict
--[[
	WorldService — 월드 이동 (Remote Travel(worldIndex)) · 캐릭터 스폰 자리 — 서버 판정
	  - 열린 월드만 (Progression.isWorldOpen(world, data.world)). 정수 1~3 만 (NaN·소수·글자 → 무시)
	  - 심사·대결 중에는 못 감
	  - 서버가 순간이동: 캐릭터를 MapLayout.spawn(world) 위로 (PivotTo). session.currentWorld · Attr CurrentWorld
	  - 캐릭터가 새로 생기면 (처음 접속·리셋) 지금 월드 스폰으로 옮김. 접속하면 지금 월드 = 열린 가장 높은 월드
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
local Worlds = require(Shared.Data.Worlds)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Attributes = require(Server.Attributes)
local Character = require(Server.Util.Character)

local WorldService = {}

WorldService.SPAWN_LIFT = 3 -- 스폰 바닥 위로 이만큼 띄워서 놓음

-- 캐릭터를 그 월드 스폰으로 (캐릭터가 없으면 false)
function WorldService.placeAtSpawn(player: Player, world: number): boolean
	local character = player.Character
	if not character or not Character.getRoot(player) then
		return false
	end
	local spot = MapLayout.spawn(world)
	character:PivotTo(CFrame.new(spot.x, spot.y + WorldService.SPAWN_LIFT, spot.z))
	return true
end

-- 이동했으면 true
function WorldService.travel(player: Player, rawWorld: unknown): boolean
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return false
	end
	if typeof(rawWorld) ~= "number" then
		return false
	end
	local world = rawWorld :: number
	if world ~= world or world % 1 ~= 0 or not Worlds.get(world) then
		return false
	end
	if not Progression.isWorldOpen(world, data.world) then
		local info = Worlds.get(world)
		Net.notify(
			player,
			"error",
			string.format("%s 잠김 · 시험관 승리 시 열림", if info then info.name else "그 월드")
		)
		return false
	end
	if Sessions.activity(session) ~= "" then
		Net.notify(player, "error", "심사·대결 중 이동 불가")
		return false
	end
	session.currentWorld = world
	WorldService.placeAtSpawn(player, world)
	Attributes.sync(player)
	Snapshot.send(player)
	return true
end

-- 접속 준비: 지금 월드 = 열린 가장 높은 월드
function WorldService.onPlayerReady(player: Player)
	local session, data = Sessions.getLoaded(player)
	if session and data then
		session.currentWorld = data.world
		WorldService.placeAtSpawn(player, session.currentWorld)
	end
end

function WorldService.onCharacterAdded(player: Player)
	local session = Sessions.getLoaded(player)
	if session then
		task.defer(function()
			if player.Parent ~= nil then
				WorldService.placeAtSpawn(player, session.currentWorld)
			end
		end)
	end
end

function WorldService.start()
	Net.on(Remotes.ToServer.Travel, function(player: Player, world: unknown)
		WorldService.travel(player, world)
	end)
end

return WorldService
