--!strict
--[[
	GuardianService — 구역마다 경비 NPC 1마리. 그 구역 씨앗을 든 플레이어를 쫓아가 잡음 (서버 권한)
	6판 "씨앗을 훔치세요": 경비 = 구역 테마 **식물 괴물** (이름은 Data/Biomes.guardName — 덥석 파리지옥 · 연꽃 개구리풀 …,
	  모양은 선임 PetVisualService/Visuals.guards). 로직·속도 숫자는 5판 그대로 (아래 "알" = 씨앗).

	8판 (사장님 2026-11-08) — **잡히는 규칙 = 시간** (물리 거리 판정 없앰, 추격 WalkSpeed 공식은 그대로):
	  - 집 = 둥지 무리 바로 옆 (MapLayout.guardHome — 구역 끝 오른쪽 귀퉁이)
	  - 내 실효 속도로 도망칠 수 없으면(SpeedMath.catchSeconds ≠ nil) 그 씨앗·그 사람의 추격 시간(egg.chaseSeconds,
	    이 경비가 쫓는 동안만 쌓임)이 2.5초(조금 모자람, 추격 기준의 70% 이상) / 1초(많이 모자람)가 되는 순간 잡힘.
	    마지막 GUARD_CATCH_RUSH_SECONDS(0.3초)는 남은 거리 ÷ 남은 시간으로 빠르게 다가감 (≤ RUSH_MAX_WALKSPEED).
	    가까우면 바로 뒤(잡힘 거리 절반)에 붙어 따라감. 씨앗은 놓친 규칙대로 (구역 안 → 둥지, 밖 → 그 자리).
	  - 도망칠 수 없는 채로 **다음 구역 경계(그 씨앗 구역 zMax)** 에 닿으면 그 즉시 잡힘 + 씨앗은 둥지로
	    (쫓기는 사람이 아니어도 — 이 구역 씨앗을 든 느린 사람은 다음 구역에 절대 못 감). 날려 보내는 방향 = 뒤(-z).
	  - 도망칠 수 있으면 자유: 경비는 쫓아오기만 하고 못 잡음.
	  - 여러 명이면 도망칠 수 없는 사람을 먼저 쫓음 (그중 가장 가까운 사람), 없으면 가장 가까운 사람.

	2판 (설계 2판 B — 원작 관찰):
	  - 평소: 집(MapLayout.guardHome — 8판: 둥지 무리 옆, 7판까지 구역 중앙)에서 잠잠 → State "Sleeping" (클라가 Z 표시)
	  - 누가 이 구역 알을 들면 깨어나 쫓아감 → State "Chase", TargetUserId
	  - 추격 포기 거리 없음: 알 든 사람이 허브(z < SAFE_ZONE_Z)에 들어가거나(= 배달, reason "safe") / 잡히거나 /
	    알을 놓거나(DropEgg) / 밤이 될 때까지 계속 쫓음 → 끝나면 State "Return" 으로 집에 걸어가서 다시 "Sleeping"
	  - 알의 구역 경비만 쫓음: 먼 구역 알을 들고 앞 구역들을 지나가도 그 구역 경비는 안 깨어남
	  - 추격 속도 (4판): SpeedMath.guardChaseSpeed(경비 속도) = 구역마다 고정, 플레이어 속도와 무관 (사장님 결정)
	    (추천 속도 이상이면 0.85 ~ 0.99배라 못 잡음, 모자라면 최소 1.2배로 반드시 따라잡음)
	  - 추격 목표 (2판 수정): 플레이어 위치 + 서버가 본 이동 속도 × GUARD_LEAD_SECONDS(0.25) (GuardLogic.leadPoint)
	    → 걷기 150 으로 도망가도 0.1초 전 자리에 먼저 도착해 멈추지 않고 계속 달림
	  - (7판까지 잡힘 판정: 수평 거리 ≤ 6 + 경비 키 × 0.25 (최대 16) + 줍기 유예 1.5초 → 8판: 위 "시간" 규칙.
	    거리는 경비가 따라붙어 멈추는 거리로만 씀 — 모델 Attribute "CatchDistance")
	  - 경비끼리 겹치지 않게: 서로 안 부딪히는 CollisionGroup + 가까우면 옆으로 비켜 감 (Logic/GuardLogic)

	모델: 단순 몸통 파트 + 머리 + Humanoid. 선임(PetVisualService)이 겉모습을 HumanoidRootPart 에 용접해 붙임.
	"Guardian" 태그 모델 안의 HumanoidRootPart / Humanoid 이름만 유지하면 됩니다.
	머리 위 이름표(BillboardGui)는 겉모습 키(겉모습 모델 Height Attribute → Visuals.guards.height → 8)의 꼭대기 + 3 높이.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Biomes = require(Shared.Data.Biomes)
local Visuals = require(Shared.Data.Visuals)
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

-- 지금 쫓는 사람의 지난 틱 위치 (이동 속도·틱 사이 가장 가까웠던 거리 계산용)
type ChaseTrack = {
	target: Player,
	px: number,
	pz: number,
	gx: number,
	gz: number,
	time: number,
}

type Guard = {
	biomeId: string,
	biome: Biomes.Biome,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	label: TextLabel,
	height: number, -- 겉모습 키 (guardHeight, 틱마다 갱신)
	labelOffset: number, -- 지금 이름표 StudsOffsetWorldSpace.Y
	home: Vector3,
	target: Player?,
	chase: ChaseTrack?,
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
local HEAD_OFFSET = 3.5 -- 루트 가운데 → 머리 가운데
local LABEL_MARGIN = 3 -- 이름표 = 겉모습 꼭대기 + 이만큼 (작은 경비는 머리 위 이만큼)

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
	head.CFrame = root.CFrame * CFrame.new(0, HEAD_OFFSET, -0.5)
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

	local label = Gui.billboard(head, biome.guardName, LABEL_MARGIN, 120)
	return {
		biomeId = biome.id,
		biome = biome,
		model = model,
		root = root,
		humanoid = humanoid,
		label = label,
		height = 0, -- 첫 틱에 refreshHeight 가 채움
		labelOffset = LABEL_MARGIN,
		home = home,
		target = nil,
		chase = nil,
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

-- 키 height 인 경비의 잡힘 판정 거리 (수평): GUARD_CATCH_DISTANCE(6) + 키 × 0.25, 최대 16
function GuardianService.catchDistance(height: number): number
	return GuardLogic.catchDistance(
		height,
		Config.GUARD_CATCH_DISTANCE,
		Config.GUARD_CATCH_HEIGHT_FACTOR,
		Config.GUARD_CATCH_DISTANCE_MAX
	)
end

-- 경비 겉모습 키 (스터드): 선임 PetVisualService 가 경비 모델 안에 붙인 겉모습 모델(이름 = Visuals.guards 의
-- model / darkModel)의 "Height" Attribute → 없으면 Visuals.guards[구역].height → 없으면 Config.GUARD_DEFAULT_HEIGHT
local function guardHeight(guard: Guard): number
	local spec = Visuals.guards[guard.biomeId]
	if spec then
		local names = { spec.model }
		if spec.darkModel then
			table.insert(names, spec.darkModel)
		end
		for _, name in names do
			local visual = guard.model:FindFirstChild(name)
			if visual and visual:IsA("Model") then
				local h = visual:GetAttribute("Height")
				if typeof(h) == "number" and h == h and h > 0 then
					return h
				end
			end
		end
		local h = spec.height
		if h and h > 0 then
			return h
		end
	end
	return Config.GUARD_DEFAULT_HEIGHT
end

-- 키가 바뀌면(겉모습이 늦게 붙거나 천사↔악마로 바뀜) 이름표 높이·잡힘 거리 다시 계산
local function refreshHeight(guard: Guard)
	local h = guardHeight(guard)
	if h == guard.height then
		return
	end
	guard.height = h
	guard.model:SetAttribute("CatchDistance", GuardianService.catchDistance(h))
	local offset = GuardLogic.labelOffset(h, ROOT_HEIGHT + HEAD_OFFSET, LABEL_MARGIN)
	guard.labelOffset = offset
	local gui = guard.label.Parent
	if gui and gui:IsA("BillboardGui") then
		gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
	end
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

-- 8판: 이 사람이 이 경비한테서 도망칠 수 없으면 잡히기까지 추격 시간(초), 도망칠 수 있으면 nil
function GuardianService.catchAfter(biomeId: string, player: Player): number?
	local biome = Biomes.get(biomeId)
	if not biome then
		return nil
	end
	return SpeedMath.catchSeconds(biome.guardSpeed, SpeedService.getCarrySpeed(player))
end

local function guardName(guard: Guard): string
	local name = guard.model:GetAttribute("GuardName")
	return if typeof(name) == "string" then name else "경비"
end

local function updateGuard(guard: Guard, carriers: { [Player]: EggService.Egg }, isDay: boolean)
	refreshHeight(guard)
	local now = os.clock()
	local range = MapLayout.biome(guard.biomeId)
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = math.huge
	local bestForced = false
	if isDay then
		for player, egg in carriers do
			if egg.biomeId == guard.biomeId then
				local root = Character.getRoot(player)
				if root and canChase(player, root) then
					local forced = GuardianService.catchAfter(guard.biomeId, player) ~= nil
					if forced and range and GuardLogic.crossedForward(root.Position.Z, range.zMax) then
						-- 8판: 도망칠 수 없는 채로 다음 구역 경계에 닿음 → 즉시 잡힘, 씨앗은 둥지로, 뒤(-z)로 날아감
						local p = root.Position
						EggService.knockOut(
							player,
							Vector3.new(p.X, p.Y, p.Z + 10),
							"guard",
							guardName(guard),
							nil,
							"ReturnToNest"
						)
						if guard.target == player then
							setTarget(guard, nil, "caught")
							guard.chase = nil
						end
					else
						-- 도망칠 수 없는 사람을 먼저 (그중 가장 가까운 사람), 없으면 가장 가까운 사람
						local d = (root.Position - guard.root.Position).Magnitude
						if (forced and not bestForced) or (forced == bestForced and d < bestDistance) then
							best, bestRoot, bestDistance, bestForced = player, root, d, forced
						end
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
		-- 4판: 추격 속도는 구역마다 고정 (플레이어 속도와 무관). 플레이어 WalkSpeed 는 앞 지점 예측에만 씀
		local walkSpeed = SpeedService.getWalkSpeed(best)
		local chaseSpeed = SpeedMath.guardChaseSpeed(guard.biome.guardSpeed)

		local p = bestRoot.Position
		local g = guard.root.Position
		local track = guard.chase
		local prev = if track and track.target == best then track else nil
		local egg = carriers[best]

		-- 8판: 추격 시간 (그 씨앗·그 사람, 도망칠 수 없는 동안 이 경비가 쫓은 시간만 쌓임)
		local after = GuardianService.catchAfter(guard.biomeId, best)
		local remaining: number? = nil
		if egg then
			if egg.chaseBy ~= best then
				egg.chaseBy = best
				egg.chaseSeconds = 0
			end
			if after then
				if prev and now > prev.time then
					egg.chaseSeconds = (egg.chaseSeconds or 0) + (now - prev.time)
				end
				remaining = after - (egg.chaseSeconds or 0)
			end
		end

		-- 서버가 본 플레이어 이동 속도 (지난 틱 → 이번 틱). 순간이동처럼 튀면 WalkSpeed × 1.5 까지만 앞을 봄
		local vx, vz = 0, 0
		if prev and now > prev.time then
			vx = (p.X - prev.px) / (now - prev.time)
			vz = (p.Z - prev.pz) / (now - prev.time)
		end
		local aimX, aimZ =
			GuardLogic.leadPoint(p.X, p.Z, vx, vz, Config.GUARD_LEAD_SECONDS, math.max(walkSpeed, 16) * 1.5)
		local reach = GuardianService.catchDistance(guard.height)
		local relX, relZ = p.X - g.X, p.Z - g.Z
		local distance = math.sqrt(relX * relX + relZ * relZ)
		if remaining and distance <= reach and distance > 1e-6 then
			-- 곧 잡힐 사람에게 바짝 붙음: 바로 뒤(잡힘 거리 절반)에서 따라감 (밀치지 않게)
			aimX = p.X - relX / distance * reach * 0.5
			aimZ = p.Z - relZ / distance * reach * 0.5
		end
		-- 마지막 0.3초는 남은 거리 ÷ 남은 시간으로 빠르게 다가감 (순간이동처럼 안 보이게)
		guard.humanoid.WalkSpeed = if remaining and remaining <= Config.GUARD_CATCH_RUSH_SECONDS
			then GuardLogic.rushWalkSpeed(
				distance - reach * 0.5,
				remaining,
				chaseSpeed,
				Config.GUARD_CATCH_RUSH_MAX_WALKSPEED
			)
			else chaseSpeed
		local wall = MapLayout.HALF_WIDTH - 2
		moveTo(guard, steer(guard, Vector3.new(math.clamp(aimX, -wall, wall), p.Y, aimZ)))
		guard.chase = { target = best, px = p.X, pz = p.Z, gx = g.X, gz = g.Z, time = now }

		-- 8판 잡힘: 도망칠 수 없는 사람의 추격 시간이 다 차면 (거리와 상관없이). 씨앗은 놓친 규칙대로
		if egg and remaining and remaining <= 1e-6 then
			EggService.knockOut(best, guard.root.Position, "guard", guardName(guard))
			setTarget(guard, nil, "caught")
			guard.chase = nil
		end
	else
		guard.chase = nil
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
