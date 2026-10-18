--!strict
--[[
	GuardianService — 구역마다 경비 NPC 1마리. 그 구역 알을 든 플레이어를 쫓아가 잡음 (서버 권한)

	2판 (설계 2판 B — 원작 관찰):
	  - 평소: 집(MapLayout.guardHome = 구역 중앙, 둥지들 사이)에서 잠잠 → State "Sleeping" (클라가 Z 표시)
	  - 누가 이 구역 알을 들면 깨어나 쫓아감 → State "Chase", TargetUserId
	  - 추격 포기 거리 없음: 알 든 사람이 허브(z < SAFE_ZONE_Z)에 들어가거나 / 잡히거나 / 알을 놓거나(DropEgg·배달) /
	    밤이 될 때까지 계속 쫓음 → 끝나면 State "Return" 으로 집에 걸어가서 다시 "Sleeping"
	  - 알의 구역 경비만 쫓음: 먼 구역 알을 들고 앞 구역들을 지나가도 그 구역 경비는 안 깨어남
	  - 추격 속도: SpeedMath.guardChaseSpeed = 플레이어 WalkSpeed × clamp(경비 속도/알 든 실효 속도 × 0.99, 0.85, 3.0)
	    (추천 속도 이상이면 0.85 ~ 0.99배라 못 잡음, 모자라면 최소 1.2배로 반드시 따라잡음)
	  - 잡힘 판정: 서버에서 경비 몸통과 플레이어 HumanoidRootPart 수평 거리 ≤ GUARD_CATCH_DISTANCE(6), 높이 차 ≤ 10
	    (둥지에서 줍고 GUARD_CATCH_GRACE_SECONDS 동안은 안 잡힘 — egg.graceUntil)
	  - 경비끼리 겹치지 않게: 서로 안 부딪히는 CollisionGroup + 가까우면 옆으로 비켜 감 (Logic/GuardLogic)

	모델: 단순 몸통 파트 + 머리 + Humanoid. 선임(PetVisualService)이 겉모습을 HumanoidRootPart 에 용접해 붙임.
	"Guardian" 태그 모델 안의 HumanoidRootPart / Humanoid 이름만 유지하면 됩니다.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Biomes = require(Shared.Data.Biomes)
local MapLayout = require(Shared.Data.MapLayout)
local SpeedMath = require(Shared.SpeedMath)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local GuardLogic = require(Server.Logic.GuardLogic)
local Character = require(Server.Util.Character)
local Gui = require(Server.Util.Gui)
local MapBuilder = require(script.Parent.MapBuilder)
local CycleService = require(script.Parent.CycleService)
local SpeedService = require(script.Parent.SpeedService)
local EggService = require(script.Parent.EggService)

type Guard = {
	biomeId: string,
	biome: Biomes.Biome,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	label: TextLabel,
	home: Vector3,
	target: Player?,
	lastMoveTarget: Vector3?,
	lastMoveAt: number,
}

export type GuardState = "Sleeping" | "Chase" | "Return"

local GuardianService = {}

local guards: { [string]: Guard } = {}
local bornAt: { [string]: number } = {}
local rapidDeaths: { [string]: number } = {}
local retryAt: { [string]: number } = {}

local RAPID_DEATH_SECONDS = 2 -- 이보다 빨리 죽으면 "생기자마자 죽음"
local RAPID_DEATH_LIMIT = 3 -- 연달아 이만큼이면
local RAPID_DEATH_BACKOFF = 5 -- 이 초 동안 다시 안 만듦
local ROOT_HEIGHT = 4.6 -- 바닥에서 HumanoidRootPart 가운데까지 (HipHeight 2.5 + 몸통 반 2 + 여유)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- 경비 집 (MapLayout.guardHome, 바닥 높이 FLOOR_Y)
local function homeOf(biomeId: string): Vector3?
	local spot = MapLayout.guardHome(biomeId)
	if not spot then
		return nil
	end
	return Vector3.new(spot.x, MapLayout.FLOOR_Y, spot.z)
end

local function setupCollisionGroup()
	local group = Config.GUARD_COLLISION_GROUP
	local ok, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(group)
		PhysicsService:CollisionGroupSetCollidable(group, group, false)
	end)
	if not ok then
		warn("[GuardianService] CollisionGroup 설정 실패: " .. tostring(err))
	end
end

local function buildGuard(biome: Biomes.Biome, home: Vector3): Guard
	local model = Instance.new("Model")
	model.Name = "Guard_" .. biome.id

	local color = rgb(biome.color):Lerp(Color3.new(0, 0, 0), 0.45)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(4, 4, 3)
	root.Color = color
	root.Material = Enum.Material.SmoothPlastic
	root.CFrame = CFrame.new(home + Vector3.new(0, ROOT_HEIGHT, 0))
	root.CollisionGroup = Config.GUARD_COLLISION_GROUP
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(3, 3, 3)
	head.Color = color:Lerp(Color3.new(1, 1, 1), 0.2)
	head.CFrame = root.CFrame * CFrame.new(0, 3.5, -0.5)
	head.CollisionGroup = Config.GUARD_COLLISION_GROUP
	head.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	-- 목 관절(Neck Motor6D) 없이 머리를 WeldConstraint 로 붙인 모델 → 이 두 줄이 없으면 생기자마자 죽을 수 있음
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HipHeight = 2.5
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = SpeedMath.guardBaseWalkSpeed(biome.guardSpeed)
	humanoid.Parent = model
	for _, state in
		{
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.Seated,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end

	model.PrimaryPart = root
	model:SetAttribute("BiomeId", biome.id)
	model:SetAttribute("GuardName", biome.guardName)
	model:SetAttribute("State", "Sleeping")
	model:SetAttribute("TargetUserId", 0)
	-- 선임이 붙이는 겉모습 파트도 같은 CollisionGroup (경비끼리 끼어 멈추지 않게)
	pcall(function()
		model.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = Config.GUARD_COLLISION_GROUP
			end
		end)
	end)
	CollectionService:AddTag(model, Tags.Guardian)
	model.Parent = MapBuilder.getFolder("Guardians")
	pcall(function()
		root:SetNetworkOwner(nil) -- 서버가 물리 담당 (클라가 경비를 조작 못 하게)
	end)

	local label = Gui.billboard(head, biome.guardName, 3, 120)
	return {
		biomeId = biome.id,
		biome = biome,
		model = model,
		root = root,
		humanoid = humanoid,
		label = label,
		home = home,
		target = nil,
		lastMoveTarget = nil,
		lastMoveAt = 0,
	}
end

local function ensureGuard(biome: Biomes.Biome): Guard?
	local existing = guards[biome.id]
	if existing and existing.model.Parent ~= nil and existing.humanoid.Health > 0 then
		return existing
	end
	local now = os.clock()
	if existing then
		existing.model:Destroy()
		guards[biome.id] = nil
		-- 태어나자마자 또 죽는 일이 반복되면(모델 문제) 0.1초마다 다시 만들지 않고 잠깐 쉼
		if now - (bornAt[biome.id] or 0) < RAPID_DEATH_SECONDS then
			rapidDeaths[biome.id] = (rapidDeaths[biome.id] or 0) + 1
		else
			rapidDeaths[biome.id] = 0
		end
		if (rapidDeaths[biome.id] or 0) >= RAPID_DEATH_LIMIT then
			retryAt[biome.id] = now + RAPID_DEATH_BACKOFF
			rapidDeaths[biome.id] = 0
			warn(
				"[GuardianService] "
					.. biome.id
					.. " 경비가 생기자마자 계속 죽음 — 잠시 뒤 다시 만듦"
			)
		end
	end
	if now < (retryAt[biome.id] or 0) then
		return nil
	end
	local home = homeOf(biome.id)
	if not home then
		return nil
	end
	local guard = buildGuard(biome, home)
	guards[biome.id] = guard
	bornAt[biome.id] = now
	return guard
end

local function setState(guard: Guard, state: GuardState)
	if guard.model:GetAttribute("State") ~= state then
		guard.model:SetAttribute("State", state)
	end
end

-- 대상 바꾸기. 놓친 사람에게는 ChaseEnded { biomeId, reason }
local function setTarget(guard: Guard, player: Player?, reason: string?)
	if guard.target == player then
		return
	end
	local previous = guard.target
	guard.target = player
	guard.model:SetAttribute("TargetUserId", if player then player.UserId else 0)
	setState(guard, if player then "Chase" else "Return")
	if previous and previous.Parent then
		Net.fire(previous, Remotes.ToClient.ChaseEnded, { biomeId = guard.biomeId, reason = reason or "other" })
	end
end

-- MoveTo 는 목표가 1스터드 이상 바뀌었거나 2초가 지났을 때만 다시 호출 (MoveTo 는 8초 뒤 저절로 멈춤)
local function moveTo(guard: Guard, position: Vector3)
	local now = os.clock()
	local last = guard.lastMoveTarget
	if last and (last - position).Magnitude < 1 and now - guard.lastMoveAt < 2 then
		return
	end
	guard.lastMoveTarget = position
	guard.lastMoveAt = now
	guard.humanoid:MoveTo(position)
end

-- 다른 경비와 겹치지 않게 목표를 옆으로 비킴
local function steer(guard: Guard, target: Vector3): Vector3
	local others: { GuardLogic.Point } = {}
	for _, other in guards do
		if other ~= guard and other.model.Parent ~= nil then
			local p = other.root.Position
			table.insert(others, { x = p.X, z = p.Z })
		end
	end
	local p = guard.root.Position
	local ox, oz = GuardLogic.separationOffset(p.X, p.Z, others, Config.GUARD_SEPARATION)
	if ox == 0 and oz == 0 then
		return target
	end
	return target + Vector3.new(ox, 0, oz)
end

-- 이 플레이어를 이 경비가 쫓을 수 있나 (2판: 거리 제한 없음, 허브에 들어가면 끝)
local function canChase(player: Player, root: BasePart): boolean
	local session = Sessions.get(player)
	if not session or Sessions.isStunned(session, os.clock()) then
		return false
	end
	if not Character.isAlive(player) then
		return false
	end
	return not MapLayout.isInHub(root.Position)
end

local function updateGuard(guard: Guard, carriers: { [Player]: EggService.Egg }, isDay: boolean)
	local now = os.clock()
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = math.huge
	if isDay then
		for player, egg in carriers do
			if egg.biomeId == guard.biomeId then
				local root = Character.getRoot(player)
				if root and canChase(player, root) then
					local d = (root.Position - guard.root.Position).Magnitude
					if d < bestDistance then
						best, bestRoot, bestDistance = player, root, d
					end
				end
			end
		end
	end
	local previous = guard.target
	if previous and previous ~= best then
		local egg = carriers[previous]
		local root = Character.getRoot(previous)
		local reason = GuardLogic.endReason(
			isDay,
			egg ~= nil and egg.biomeId == guard.biomeId,
			root ~= nil and MapLayout.isInHub(root.Position)
		)
		setTarget(guard, best, reason)
	else
		setTarget(guard, best)
	end

	if best and bestRoot then
		guard.humanoid.WalkSpeed = SpeedMath.guardChaseSpeed(
			guard.biome.guardSpeed,
			SpeedService.getCarrySpeed(best),
			SpeedService.getWalkSpeed(best)
		)
		moveTo(guard, steer(guard, bestRoot.Position))

		local egg = carriers[best]
		local flat =
			Vector3.new(bestRoot.Position.X - guard.root.Position.X, 0, bestRoot.Position.Z - guard.root.Position.Z)
		local dy = math.abs(bestRoot.Position.Y - guard.root.Position.Y)
		if egg and now >= egg.graceUntil and flat.Magnitude <= Config.GUARD_CATCH_DISTANCE and dy <= 10 then
			local name = guard.model:GetAttribute("GuardName")
			EggService.knockOut(best, guard.root.Position, "guard", if typeof(name) == "string" then name else "경비")
			setTarget(guard, nil, "caught")
		end
	else
		guard.humanoid.WalkSpeed = SpeedMath.guardBaseWalkSpeed(guard.biome.guardSpeed)
		local away = Vector3.new(guard.root.Position.X - guard.home.X, 0, guard.root.Position.Z - guard.home.Z)
		if away.Magnitude > Config.GUARD_HOME_TOLERANCE then
			setState(guard, "Return")
			moveTo(guard, steer(guard, guard.home))
		else
			setState(guard, "Sleeping")
		end
	end

	-- 맵 밖으로 떨어지면 집으로
	if guard.root.Position.Y < -30 then
		guard.root.AssemblyLinearVelocity = Vector3.zero
		guard.model:PivotTo(CFrame.new(guard.home + Vector3.new(0, ROOT_HEIGHT, 0)))
		guard.lastMoveTarget = nil
	end
end

-- 천사&악마: 이번 주기 쪽에 따라 경비 이름 바꾸기
local function refreshNames()
	for _, guard in guards do
		local name = Biomes.guardDisplayName(guard.biome, CycleService.sideFor(guard.biomeId))
		guard.model:SetAttribute("GuardName", name)
		guard.label.Text = name
	end
end

function GuardianService.getGuardModel(biomeId: string): Model?
	local guard = guards[biomeId]
	return if guard then guard.model else nil
end

-- 이 경비가 지금 쫓는 사람 (없으면 nil)
function GuardianService.getTarget(biomeId: string): Player?
	local guard = guards[biomeId]
	return if guard then guard.target else nil
end

function GuardianService.start()
	setupCollisionGroup()
	for _, biome in Biomes.list do
		ensureGuard(biome)
	end
	refreshNames()
	CycleService.changed:connect(function()
		refreshNames()
	end)

	task.spawn(function()
		while true do
			task.wait(Config.GUARD_TICK_SECONDS)
			local ok, err = pcall(function()
				local carriers = EggService.carriers()
				local isDay = CycleService.getPhase() == "Day"
				for _, biome in Biomes.list do
					local guard = ensureGuard(biome)
					if guard then
						updateGuard(guard, carriers, isDay)
					end
				end
			end)
			if not ok then
				warn("[GuardianService] tick 오류: " .. tostring(err))
			end
		end
	end)
end

return GuardianService
