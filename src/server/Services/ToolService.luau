--!strict
--[[
	ToolService — 다른 플레이어 방해 도구 (설계문서 10장). 서버 검증만 있고 모양/연출은 선임 몫.

	도구는 서버가 Backpack 에 Tool 로 넣어 줌 (RequiresHandle = false, 이름 = 종류).
	클라는 Tool.Activated 때 UseTool(kind) 만 보냄. 대상·위치는 클라가 정하지 않고 서버가 찾음.

	- 근접 무기 (shared/Data/Weapons.luau): Bat(야구 방망이, 기본 지급) + 구역 도감 완성 무기 7개
	  (WaterBat 물 방망이, Katana 카타나, Axe 도끼, AngelSpear 천사의 창, Hammer 망치, CandyCane 사탕 지팡이, Scythe 낫)
	  무기마다 사거리·넉백·쿨다운이 다르고(뒤 구역일수록 큼), 쿨다운은 모든 근접 무기가 같이 씀 ("melee").
	  내 앞쪽(내적 ≥ BAT_FACING_DOT)의 사거리 안 가장 가까운 플레이어를 래그돌 + 알 떨어뜨림(그 자리).
	  구역 무기는 data.weapons(저장)에 있는 것만 지급·사용 가능 (IndexService.weaponsChanged 때 바로 지급).
	- BearTrap(곰덫, 개수 제한 data.tools.bearTrap): 발밑에 설치, 다른 사람이 밟으면
	  BEAR_TRAP_STUN_SECONDS(5초) 묶임 + 알 떨어뜨림. 한 사람당 동시에 BEAR_TRAP_MAX_ACTIVE 개.
	- 안전 구역(2판: 허브 = MapLayout.isInHub, z < 0)에서는 쓰지도, 맞지도 않음.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Weapons = require(Shared.Data.Weapons)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local MapLayout = require(Shared.Data.MapLayout)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Character = require(Server.Util.Character)
local Validate = require(Server.Logic.Validate)
local MapBuilder = require(script.Parent.MapBuilder)
local SpeedService = require(script.Parent.SpeedService)
local EggService = require(script.Parent.EggService)
local IndexService = require(script.Parent.IndexService)

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

-- 이 무기를 쓸 수 있나 (기본 방망이 또는 해금한 구역 무기)
local function ownsWeapon(data: Types.PlayerData, weapon: Weapons.Weapon): boolean
	return weapon.biome == nil or table.find(data.weapons, weapon.id) ~= nil
end

-- 있으면 그 Tool, 없으면 새로 만들어 가방에 넣음
local function ensureTool(player: Player, backpack: Instance, kind: string, tip: string): Tool
	local existing = findTool(player, kind)
	if existing then
		return existing
	end
	local tool = makeTool(kind, tip)
	tool.Parent = backpack
	return tool
end

function ToolService.refreshTools(player: Player)
	local _, data = Sessions.getLoaded(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not backpack then
		return
	end
	for _, weapon in Weapons.list do
		if ownsWeapon(data, weapon) then
			local tool = ensureTool(player, backpack, weapon.toolKind, weapon.tip)
			tool:SetAttribute("WeaponId", weapon.id)
			tool:SetAttribute("Range", weapon.range)
		else
			local stale = findTool(player, weapon.toolKind)
			if stale then
				stale:Destroy()
			end
		end
	end
	local trapCount = data.tools.bearTrap or 0
	if trapCount > 0 then
		local trapTool =
			ensureTool(player, backpack, ToolKinds.BearTrap, "곰덫: 밟은 사람이 5초 동안 못 움직여요")
		trapTool:SetAttribute("Count", trapCount)
	else
		local stale = findTool(player, ToolKinds.BearTrap)
		if stale then
			stale:Destroy()
		end
	end
end

-- 휘두르기/설치가 실제로 일어났을 때 Tool 에 표시 → 다른 사람 화면에서도 휘두르는 모습 (선임 WeaponController)
local function markSwing(player: Player, kind: string)
	local tool = toolIn(player.Character, kind)
	if tool then
		tool:SetAttribute("SwingTick", os.clock())
	end
end

------------------------------------------------------------------
-- 근접 무기 (방망이 + 구역 무기)
------------------------------------------------------------------

local function useMelee(player: Player, weapon: Weapons.Weapon)
	local session, data = Sessions.getLoaded(player)
	local root = Character.getRoot(player)
	if not session or not data or not root or not Character.isAlive(player) then
		return
	end
	local now = os.clock()
	if Sessions.isStunned(session, now) or not isEquipped(player, weapon.toolKind) then
		return
	end
	if not ownsWeapon(data, weapon) then
		return -- 해금 안 한 무기 (Tool 은 서버만 주므로 정상이라면 안 생김)
	end
	if not Sessions.useCooldown(session, "melee", weapon.cooldown, now) then
		return
	end
	if MapLayout.isInHub(root.Position) then
		Net.notify(player, "error", "안전 구역에서는 도구를 쓸 수 없어요!")
		return
	end
	markSwing(player, weapon.toolKind)
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
				if distance <= weapon.range and distance < bestDistance then
					local flat = Vector3.new(offset.X, 0, offset.Z)
					local facing = if flat.Magnitude > 0.01 then look:Dot(flat.Unit) else 1
					if facing >= Config.BAT_FACING_DOT and not MapLayout.isInHub(otherRoot.Position) then
						best, bestDistance = other, distance
					end
				end
			end
		end
	end
	if best then
		EggService.knockOut(best, root.Position, "player", player.DisplayName, weapon.knockback)
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
	if MapLayout.isInHub(root.Position) then
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
	markSwing(player, ToolKinds.BearTrap)

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
	local trap: Trap = { part = part :: BasePart, owner = player, placedAt = now }
	table.insert(traps, trap)

	ToolService.refreshTools(player)
	Snapshot.section(player, "tools")
end

local function trapTick(): ...any
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
							and not MapLayout.isInHub(root.Position)
						then
							local outcome = EggService.dropCarried(other, "player")
							SpeedService.freeze(other, Config.BEAR_TRAP_STUN_SECONDS)
							Net.fire(other, Remotes.ToClient.Caught, {
								cause = "trap",
								by = trap.owner.DisplayName,
								eggOutcome = outcome or "None",
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
		if not k then
			return
		end
		if k == ToolKinds.BearTrap then
			placeTrap(player)
			return
		end
		local weapon = Weapons.byTool(k)
		if weapon then
			useMelee(player, weapon)
		end
	end)
	IndexService.weaponsChanged:connect(function(player: Player)
		ToolService.refreshTools(player)
	end)
	IndexService.toolsChanged:connect(function(player: Player)
		ToolService.refreshTools(player)
		Snapshot.section(player, "tools")
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
