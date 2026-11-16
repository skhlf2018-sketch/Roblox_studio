--!strict
--[[
	WorldService — 월드 이동 (Remote Travel(worldIndex)) · 캐릭터 스폰 자리 — 서버 판정
	  - 열린 월드만 (Progression.isWorldOpen(world, data.world)). 정수 1~3 만 (NaN·소수·글자 → 무시)
	  - 심사·대결 중에는 못 감
	  - 서버가 순간이동: 캐릭터를 MapLayout.spawn(world) 위로 (PivotTo). session.currentWorld · Attr CurrentWorld
	    띄우는 높이 = SPAWN_LIFT(3) × max(몸 배율, 그 월드 worldScale) — 키 75 스터드 몸이 땅에 박히지 않게
	  - 캐릭터가 새로 생기면 (처음 접속·리셋) 지금 월드 스폰으로 옮김. 접속하면 지금 월드 = 열린 가장 높은 월드
	  - 여러 번 빨리 와도 안전 (선임: 문에 들어서면 클라가 Travel 을 보냄 — 몸 부품마다 닿아서 여러 번 올 수 있음):
	    속도 제한 Remotes.RateLimits.Travel · 지금 있는 월드로 다시 오면 TRAVEL_REPEAT_SECONDS 안에는 무시 (두 번 순간이동 없음)
	    · 잠김/심사 중 알림은 NOTIFY_COOLDOWN 초에 한 번만
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
local Sizes = require(Shared.Data.Sizes)
local Worlds = require(Shared.Data.Worlds)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Attributes = require(Server.Attributes)
local Character = require(Server.Util.Character)
local SizeService = require(script.Parent.SizeService)

local WorldService = {}

WorldService.SPAWN_LIFT = 3 -- 스폰 바닥 위로 이만큼 × max(몸 배율, 월드 배율) 띄워서 놓음
WorldService.TRAVEL_REPEAT_SECONDS = 2 -- 막 옮긴 월드로 또 오면 이 시간 안에는 무시
WorldService.NOTIFY_COOLDOWN = 2 -- 잠김 · 심사 중 알림은 이 초에 한 번

-- 스폰에 놓을 때 바닥 위 높이 (HumanoidRootPart 가 놓이는 높이)
function WorldService.spawnLift(player: Player, world: number): number
	return WorldService.SPAWN_LIFT * math.max(SizeService.bodyScale(player), Sizes.worldScale(world))
end

-- 캐릭터를 그 월드 스폰으로 (캐릭터가 없으면 false)
function WorldService.placeAtSpawn(player: Player, world: number): boolean
	local character = player.Character
	if not character or not Character.getRoot(player) then
		return false
	end
	local spot = MapLayout.spawn(world)
	character:PivotTo(CFrame.new(spot.x, spot.y + WorldService.spawnLift(player, world), spot.z))
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
	local now = os.clock()
	if not Progression.isWorldOpen(world, data.world) then
		if Sessions.useCooldown(session, "travelLocked", WorldService.NOTIFY_COOLDOWN, now) then
			local info = Worlds.get(world)
			Net.notify(
				player,
				"error",
				string.format("%s 잠김 · 시험관 승리 시 열림", if info then info.name else "그 월드")
			)
		end
		return false
	end
	if Sessions.activity(session) ~= "" then
		if Sessions.useCooldown(session, "travelBusy", WorldService.NOTIFY_COOLDOWN, now) then
			Net.notify(player, "error", "심사·대결 중 이동 불가")
		end
		return false
	end
	local last = session.cooldowns.travel
	if world == session.currentWorld and last and now - last < WorldService.TRAVEL_REPEAT_SECONDS then
		return false -- 방금 이 월드로 왔음 (문에 여러 번 닿음) — 두 번 옮기지 않음
	end
	session.cooldowns.travel = now
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
