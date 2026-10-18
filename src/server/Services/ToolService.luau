--!strict
--[[
	ToolService — 다른 플레이어 방해 도구 (설계문서 10장). 서버 검증만 있고 모양/연출은 선임 몫.

	도구는 서버가 Backpack 에 Tool 로 넣어 줌 (RequiresHandle = false, 이름 = 종류).
	클라는 Tool.Activated 때 UseTool(kind) 만 보냄. 대상·위치는 클라가 정하지 않고 서버가 찾음.

	- Bat(야구 방망이, 기본 지급): 쿨다운 BAT_COOLDOWN_SECONDS, 사거리 BAT_RANGE,
	  내 앞쪽(내적 ≥ BAT_FACING_DOT)의 가장 가까운 플레이어를 래그돌 + 알 떨어뜨림(그 자리).
	- BearTrap(곰덫, 개수 제한 data.tools.bearTrap): 발밑에 설치, 다른 사람이 밟으면
	  BEAR_TRAP_STUN_SECONDS(5초) 묶임 + 알 떨어뜨림. 한 사람당 동시에 BEAR_TRAP_MAX_ACTIVE 개.
	- 안전 구역(아무 베이스 반경 안)에서는 쓰지도, 맞지도 않음.
	- 구역 도감 무기(물 방망이·카타나…)는 3단계 (사거리·힘 표를 만들어 Bat 처리에 연결 예정).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Character = require(Server.Util.Character)
local Validate = require(Server.Logic.Validate)
local MapBuilder = require(script.Parent.MapBuilder)
local SpeedService = require(script.Parent.SpeedService)
local EggService = require(script.Parent.EggService)

type Trap = {
	part: BasePart,
	owner: Player,
	placedAt: number,
}

local ToolKinds = Remotes.ToolKinds

local ToolService = {}

local traps: { Trap } = {}

------------------------------------------------------------------
-- Tool 인스턴스 지급
------------------------------------------------------------------

local function makeTool(kind: string, tip: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = kind
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = tip
	tool:SetAttribute("ToolKind", kind)
	return tool
end

local function toolIn(container: Instance?, kind: string): Tool?
	if not container then
		return nil
	end
	local tool = container:FindFirstChild(kind)
	if tool and tool:IsA("Tool") then
		return tool
	end
	return nil
end

-- 손에 든 것(캐릭터 안) 또는 가방(Backpack) 안
local function findTool(player: Player, kind: string): Tool?
	return toolIn(player.Character, kind) or toolIn(player:FindFirstChildOfClass("Backpack"), kind)
end

local function isEquipped(player: Player, kind: string): boolean
	return toolIn(player.Character, kind) ~= nil
end

function ToolService.refreshTools(player: Player)
	local _, data = Sessions.getLoaded(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not backpack then
		return
	end
	if not findTool(player, ToolKinds.Bat) then
		makeTool(ToolKinds.Bat, "야구 방망이: 다른 플레이어를 날려 알을 떨어뜨려요").Parent =
			backpack
	end
	local trapCount = data.tools.bearTrap or 0
	local trapTool = findTool(player, ToolKinds.BearTrap)
	if trapCount > 0 then
		if not trapTool then
			trapTool = makeTool(ToolKinds.BearTrap, "곰덫: 밟은 사람이 5초 동안 못 움직여요")
			trapTool.Parent = backpack
		end
		trapTool:SetAttribute("Count", trapCount)
	elseif trapTool then
		trapTool:Destroy()
	end
end

------------------------------------------------------------------
-- 방망이
------------------------------------------------------------------

local function useBat(player: Player)
	local session = Sessions.get(player)
	local root = Character.getRoot(player)
	if not session or not root or not Character.isAlive(player) then
		return
	end
	local now = os.clock()
	if Sessions.isStunned(session, now) or not isEquipped(player, ToolKinds.Bat) then
		return
	end
	if not Sessions.useCooldown(session, ToolKinds.Bat, Config.BAT_COOLDOWN_SECONDS, now) then
		return
	end
	if MapBuilder.isInSafeZone(root.Position) then
		Net.notify(player, "error", "안전 구역에서는 도구를 쓸 수 없어요!")
		return
	end
	local look = root.CFrame.LookVector
	local best: Player? = nil
	local bestDistance = math.huge
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherSession = Sessions.get(other)
			local otherRoot = Character.getRoot(other)
			if
				otherSession
				and otherRoot
				and Character.isAlive(other)
				and not Sessions.isStunned(otherSession, now)
			then
				local offset = otherRoot.Position - root.Position
				local distance = offset.Magnitude
				if distance <= Config.BAT_RANGE and distance < bestDistance then
					local flat = Vector3.new(offset.X, 0, offset.Z)
					local facing = if flat.Magnitude > 0.01 then look:Dot(flat.Unit) else 1
					if facing >= Config.BAT_FACING_DOT and not MapBuilder.isInSafeZone(otherRoot.Position) then
						best, bestDistance = other, distance
					end
				end
			end
		end
	end
	if best then
		EggService.knockOut(best, root.Position, "player", player.DisplayName)
	end
end

------------------------------------------------------------------
-- 곰덫
------------------------------------------------------------------

local function activeTrapCount(player: Player): number
	local n = 0
	for _, trap in traps do
		if trap.owner == player then
			n += 1
		end
	end
	return n
end

local function placeTrap(player: Player)
	local session, data = Sessions.getLoaded(player)
	local character = player.Character
	local root = Character.getRoot(player)
	if not session or not data or not character or not root or not Character.isAlive(player) then
		return
	end
	local now = os.clock()
	if Sessions.isStunned(session, now) or not isEquipped(player, ToolKinds.BearTrap) then
		return
	end
	if not Sessions.useCooldown(session, ToolKinds.BearTrap, 1, now) then
		return
	end
	if (data.tools.bearTrap or 0) <= 0 then
		return
	end
	if MapBuilder.isInSafeZone(root.Position) then
		Net.notify(player, "error", "안전 구역에서는 도구를 쓸 수 없어요!")
		return
	end
	if activeTrapCount(player) >= Config.BEAR_TRAP_MAX_ACTIVE then
		Net.notify(
			player,
			"error",
			"곰덫은 동시에 " .. Config.BEAR_TRAP_MAX_ACTIVE .. "개까지만 설치할 수 있어요."
		)
		return
	end
	data.tools.bearTrap -= 1

	local y = MapBuilder.groundY(root.Position, { character })
	local part = Instance.new("Part")
	part.Name = "BearTrap"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.4, 4, 4)
	part.CFrame = CFrame.new(root.Position.X, y + 0.2, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Color = Color3.fromRGB(70, 70, 70)
	part.Material = Enum.Material.Metal
	part:SetAttribute("OwnerUserId", player.UserId)
	CollectionService:AddTag(part, Tags.BearTrap)
	part.Parent = MapBuilder.getFolder("Traps")
	table.insert(traps, { part = part, owner = player, placedAt = now })

	ToolService.refreshTools(player)
	Snapshot.section(player, "tools")
end

local function trapTick()
	local now = os.clock()
	for i = #traps, 1, -1 do
		local trap = traps[i]
		local triggered = false
		if now - trap.placedAt > Config.BEAR_TRAP_LIFETIME or trap.part.Parent == nil then
			triggered = true -- 수명 끝
		else
			local p = trap.part.Position
			for _, other in Players:GetPlayers() do
				if other ~= trap.owner then
					local session = Sessions.get(other)
					local root = Character.getRoot(other)
					if session and root and Character.isAlive(other) and not Sessions.isStunned(session, now) then
						local dx, dz = root.Position.X - p.X, root.Position.Z - p.Z
						local dy = math.abs(root.Position.Y - p.Y)
						if
							dx * dx + dz * dz <= Config.BEAR_TRAP_TRIGGER_RADIUS * Config.BEAR_TRAP_TRIGGER_RADIUS
							and dy < 5
							and not MapBuilder.isInSafeZone(root.Position)
						then
							EggService.dropCarried(other, "player")
							SpeedService.freeze(other, Config.BEAR_TRAP_STUN_SECONDS)
							Net.fire(other, Remotes.ToClient.Caught, {
								cause = "trap",
								by = trap.owner.DisplayName,
								eggOutcome = "DropHere",
								ragdollSeconds = 0,
								stunSeconds = Config.BEAR_TRAP_STUN_SECONDS,
							})
							triggered = true
							break
						end
					end
				end
			end
		end
		if triggered then
			trap.part:Destroy()
			table.remove(traps, i)
		end
	end
end

------------------------------------------------------------------
-- 시작 / 플레이어 이벤트
------------------------------------------------------------------

function ToolService.onCharacterAdded(player: Player, _character: Model)
	task.wait() -- Backpack 이 새로 만들어진 뒤
	ToolService.refreshTools(player)
end

function ToolService.onPlayerReady(player: Player)
	ToolService.refreshTools(player)
end

function ToolService.onPlayerLeaving(player: Player)
	for i = #traps, 1, -1 do
		if traps[i].owner == player then
			traps[i].part:Destroy()
			table.remove(traps, i)
		end
	end
end

function ToolService.start()
	Net.on(Remotes.ToServer.UseTool, function(player: Player, kind: unknown)
		local k = Validate.oneOf(kind, ToolKinds)
		if k == ToolKinds.Bat then
			useBat(player)
		elseif k == ToolKinds.BearTrap then
			placeTrap(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			local ok, err = pcall(trapTick)
			if not ok then
				warn("[ToolService] trap 오류: " .. tostring(err))
			end
		end
	end)
end

return ToolService
