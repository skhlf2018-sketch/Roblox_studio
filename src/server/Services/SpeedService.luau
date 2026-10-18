--!strict
--[[
	SpeedService — 플레이어 속도 숫자 → 실제 WalkSpeed (서버가 정함)

	실효 속도 = 모은 속도(data.speed) × 가진 트레일 중 최고 배율
	WalkSpeed = SpeedMath.walkSpeedFor(실효 속도, 알 무게 감소)
	곰덫에 걸리면(frozenUntil) WalkSpeed 0, 점프 0.
	러닝머신 위(session.onTreadmill, 2판)면 WalkSpeed 0 (점프는 그대로 → 클라가 점프하면 TreadmillLeave).

	주의: WalkSpeed 는 클라가 몰래 바꿀 수 있습니다(익스플로잇). 경비 잡힘 판정은
	서버가 계산한 숫자(session.carrySpeed)로 하므로 규칙 자체는 안전합니다.
	속도핵 감지(이동 거리 검사)는 아직 없음 → 2단계 과제.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Economy)
local SpeedMath = require(Shared.SpeedMath)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Sessions = require(Server.Sessions)
local Character = require(Server.Util.Character)

local Attr = Tags.PlayerAttributes

local DEFAULT_JUMP_HEIGHT = 7.2
local DEFAULT_JUMP_POWER = 50

local SpeedService = {}

function SpeedService.refresh(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	local data = session.data
	local baseSpeed = if data then data.speed else 0
	local trailMultiplier = if data then Economy.bestTrailMultiplier(data.trails) else 1
	local effective = SpeedMath.effectiveSpeed(baseSpeed, trailMultiplier)
	local penalty = if session.carryingUid then session.carryPenalty else 0
	local walkSpeed = SpeedMath.walkSpeedFor(effective, penalty)
	local frozen = os.clock() < session.frozenUntil
	if frozen or session.onTreadmill then
		walkSpeed = 0 -- 곰덫: 못 움직임 / 러닝머신: 제자리에서 달림 (점프는 됨 → 점프하면 내림)
	end

	session.effectiveSpeed = effective
	session.carrySpeed = SpeedMath.carrySpeed(effective, penalty)
	session.walkSpeed = walkSpeed

	player:SetAttribute(Attr.Speed, effective)
	player:SetAttribute(Attr.BaseSpeed, baseSpeed)
	player:SetAttribute(Attr.TrailMultiplier, trailMultiplier)
	player:SetAttribute(Attr.WalkSpeed, walkSpeed)

	local humanoid = Character.getHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = walkSpeed
		if frozen then
			humanoid.JumpHeight = 0
			humanoid.JumpPower = 0
		else
			humanoid.JumpHeight = DEFAULT_JUMP_HEIGHT
			humanoid.JumpPower = DEFAULT_JUMP_POWER
		end
	end
end

-- 경비 비교용: 알 무게까지 반영한 실효 속도
function SpeedService.getCarrySpeed(player: Player): number
	local session = Sessions.get(player)
	return if session then session.carrySpeed else 0
end

function SpeedService.getWalkSpeed(player: Player): number
	local session = Sessions.get(player)
	return if session then session.walkSpeed else 16
end

-- 곰덫: seconds 동안 못 움직임
function SpeedService.freeze(player: Player, seconds: number)
	local session = Sessions.get(player)
	if not session then
		return
	end
	session.frozenUntil = math.max(session.frozenUntil, os.clock() + seconds)
	player:SetAttribute(Attr.Stunned, true)
	SpeedService.refresh(player)
	task.delay(seconds + 0.05, function()
		local current = Sessions.get(player)
		if current and os.clock() >= current.frozenUntil then
			if os.clock() >= current.stunnedUntil then
				player:SetAttribute(Attr.Stunned, false)
			end
			SpeedService.refresh(player)
		end
	end)
end

function SpeedService.onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		SpeedService.refresh(player)
	end
end

function SpeedService.start() end

return SpeedService
