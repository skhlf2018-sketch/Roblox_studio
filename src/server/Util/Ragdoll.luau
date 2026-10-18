--!strict
--[[
	Ragdoll — 잡혔을 때 몸이 풀려 붕 날아가는 효과 (서버)

	- Humanoid.PlatformStand = true (몸이 굳어 넘어짐) 를 RAGDOLL_SECONDS 동안
	- HumanoidRootPart 에 LinearVelocity 를 잠깐 붙여 날려 보냄
	  (캐릭터 물리는 클라 소유라 속도를 직접 넣으면 무시될 수 있음 → 제약(Constraint) 인스턴스를 복제시키는 방식)
	- 클라는 Caught Remote 를 받아 로컬에서도 같은 상태를 맞춤 (src/client/Controllers/RagdollController)
	- 진짜 관절 래그돌(BallSocket)은 선임이 연출할 때 바꿔도 됨: session.stunnedUntil 규칙만 유지
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Data.Config)
local Tags = require(ReplicatedStorage.Shared.Tags)
local Sessions = require(script.Parent.Parent.Sessions)
local Character = require(script.Parent.Character)

local Ragdoll = {}

-- 날려 보낼 방향 속도 (fromPosition 에서 멀어지는 쪽 + 위로). power = 무기 넉백 배율 (기본 1)
--   수평 × power, 위쪽 × √power (센 무기도 하늘 끝까지 날아가진 않게)
function Ragdoll.knockbackVelocity(rootPosition: Vector3, fromPosition: Vector3?, power: number?): Vector3
	local p = math.clamp(power or 1, 0.1, 5)
	local away = Vector3.new(0, 0, 0)
	if fromPosition then
		local flat = Vector3.new(rootPosition.X - fromPosition.X, 0, rootPosition.Z - fromPosition.Z)
		if flat.Magnitude > 0.01 then
			away = flat.Unit
		end
	end
	if away.Magnitude < 0.5 then
		away = Vector3.new(0, 0, -1)
	end
	return away * Config.KNOCKBACK_SPEED * p + Vector3.new(0, Config.KNOCKBACK_UP_SPEED * math.sqrt(p), 0)
end

-- (날려 보낸 속도) 를 돌려줌. 캐릭터가 없으면 nil.
function Ragdoll.apply(player: Player, fromPosition: Vector3?, seconds: number?, power: number?): Vector3?
	local session = Sessions.get(player)
	local _, humanoid, root = Character.get(player)
	if not session or not humanoid or not root then
		return nil
	end
	local duration = seconds or Config.RAGDOLL_SECONDS
	local now = os.clock()
	session.stunnedUntil = math.max(session.stunnedUntil, now + duration)
	-- 날아가는 동안 + 끝난 뒤 잠깐은 위치 검증 쉼 (AntiCheatService)
	Sessions.exemptMovement(session, duration + Config.MOVE_CHECK_EXEMPT_AFTER_RAGDOLL)
	player:SetAttribute(Tags.PlayerAttributes.Stunned, true)

	humanoid.PlatformStand = true

	local velocity = Ragdoll.knockbackVelocity(root.Position, fromPosition, power)
	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackAttachment"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "Knockback"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.VectorVelocity = velocity
	mover.MaxForce = 1e6
	mover.Parent = root
	Debris:AddItem(mover, Config.KNOCKBACK_SECONDS)
	Debris:AddItem(attachment, Config.KNOCKBACK_SECONDS)

	task.delay(duration, function()
		local current = Sessions.get(player)
		if not current or os.clock() + 0.02 < current.stunnedUntil then
			return -- 그 사이 또 잡혀서 더 길어졌으면 나중 타이머가 처리
		end
		if humanoid.Parent then
			humanoid.PlatformStand = false
		end
		if os.clock() >= current.frozenUntil then
			player:SetAttribute(Tags.PlayerAttributes.Stunned, false)
		end
	end)
	return velocity
end

return Ragdoll
