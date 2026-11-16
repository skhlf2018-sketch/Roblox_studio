--!strict
--[[
	SizeService — 몸 크기 · 걷기 빠르기 (사장님 결정 13·14번, 규칙은 shared/Data/Sizes) — 서버만 정함
	  플레이어 Attribute  BodyScale = Sizes.quantize(Sizes.playerScale(맨 힘 data.power))   (힘 배수 PowerBoost 는 안 곱함)
	                      Muscle    = Sizes.muscle(맨 힘) 을 0.05 단위로 내림
	  Humanoid            WalkSpeed = Sizes.walkSpeed(BodyScale) · UseJumpPower = false · JumpHeight = Sizes.jumpHeight(BodyScale)
	언제:
	  - Wallet.sync 끝에서 refresh — 힘이 바뀌는 길은 전부 Wallet.sync 를 지남 (들기 Wallet.addPower · 개발 명령 /power Wallet.set ·
	    /reset 과 불러오기 Attributes.sync → Wallet.sync). 치기·돈도 Wallet.sync 를 부르지만 값이 그대로면 아무것도 안 씀.
	  - 캐릭터가 새로 생길 때 (PlayerLifecycle → onCharacterAdded: 바로 + 한 번 미뤄서 — 다른 CharacterAdded 처리가 끝난 뒤)
	값이 실제로 바뀔 때만 씀 (들기는 초당 5번까지 옴). 불러오기 전에는 Attribute 를 안 쓰고 Humanoid 만 배율 1 로.
	겉모습(몸·근육·아령·아우라 크기)은 선임 PlayerVisualService 가 BodyScale · Muscle 을 읽어서 바꿈 — 여기서는 안 건드림.
	클라가 BodyScale · Muscle 을 바꾸는 Remote 는 없음 (클라가 Attribute 를 바꿔도 서버에는 안 옴 — 서버 값은 data.power 에서만).

	거리 판정 도우미 (서버 서비스가 씀):
	  bodyScale(player)   지금 몸 배율 (불러온 data.power 에서 — Attribute 보다 먼저 맞음). 불러오기 전 1
	  bodyExtra(player)   몸이 커진 만큼 늘어나는 높이·팔 길이 = BODY_STUDS × (몸 배율 − 1)
	                      (보통 몸은 HumanoidRootPart 가 바닥 위 약 3 스터드 — 몸이 s 배면 약 3s)
	  isOnTrainMat(player, pos, world)  MapLayout.isOnTrainMat 을 그대로 + 큰 몸이면 "보통 몸이면 뿌리가 있을 높이" 로 내려서도 봄
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Sizes = require(Shared.Data.Sizes)
local MapLayout = require(Shared.Data.MapLayout)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Sessions = require(Server.Sessions)
local Character = require(Server.Util.Character)

local Attr = Tags.PlayerAttributes

local SizeService = {}

SizeService.MUSCLE_STEP = 0.05
SizeService.BODY_STUDS = 3 -- 몸 배율 1 늘 때마다 뿌리 높이(≈ 팔 길이)가 이만큼

-- 맨 힘 → 몸 배율 (BodyScale 값)
function SizeService.scaleFor(power: number): number
	return Sizes.quantize(Sizes.playerScale(power))
end

-- 맨 힘 → 근육 (0 … 1, 0.05 단위로 내림)
function SizeService.muscleFor(power: number): number
	local m = Sizes.muscle(power)
	local steps = math.floor(m / SizeService.MUSCLE_STEP + 1e-9)
	return math.clamp(steps * SizeService.MUSCLE_STEP, 0, 1)
end

-- 지금 몸 배율 (불러오기 전 1)
function SizeService.bodyScale(player: Player): number
	local _, data = Sessions.getLoaded(player)
	if not data then
		return 1
	end
	return SizeService.scaleFor(data.power)
end

-- 몸이 커진 만큼 더 주는 거리 (스터드, 보통 몸 0)
function SizeService.bodyExtra(player: Player): number
	return SizeService.BODY_STUDS * (SizeService.bodyScale(player) - 1)
end

-- 수련 매트 위인가 (큰 몸은 뿌리가 높이 있어서 "보통 몸이면 뿌리가 있을 높이" 로도 봄 — 겉모습이 아직 안 커졌어도 됨)
-- 좌표가 NaN 이면 아님 (C-1)
function SizeService.isOnTrainMat(player: Player, position: Vector3, world: number): boolean
	if position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z then
		return false
	end
	if MapLayout.isOnTrainMat(position, world) then
		return true
	end
	local extra = SizeService.bodyExtra(player)
	if extra <= 0 then
		return false
	end
	return MapLayout.isOnTrainMat({ x = position.X, y = position.Y - extra, z = position.Z }, world)
end

-- Humanoid 에 걷기·점프 (바뀐 칸만 씀)
local function applyHumanoid(player: Player, scale: number)
	local humanoid = Character.getHumanoid(player)
	if not humanoid then
		return
	end
	local walk = Sizes.walkSpeed(scale)
	local jump = Sizes.jumpHeight(scale)
	if humanoid.UseJumpPower ~= false then
		humanoid.UseJumpPower = false
	end
	if humanoid.WalkSpeed ~= walk then
		humanoid.WalkSpeed = walk
	end
	if humanoid.JumpHeight ~= jump then
		humanoid.JumpHeight = jump
	end
end

-- 힘 → BodyScale · Muscle · Humanoid (바뀐 것만). 몸 배율을 돌려줌
function SizeService.refresh(player: Player): number
	local _, data = Sessions.getLoaded(player)
	if not data then
		applyHumanoid(player, 1)
		return 1
	end
	local scale = SizeService.scaleFor(data.power)
	local muscle = SizeService.muscleFor(data.power)
	if player:GetAttribute(Attr.BodyScale) ~= scale then
		player:SetAttribute(Attr.BodyScale, scale)
	end
	if player:GetAttribute(Attr.Muscle) ~= muscle then
		player:SetAttribute(Attr.Muscle, muscle)
	end
	applyHumanoid(player, scale)
	return scale
end

-- 캐릭터가 새로 생김 (PlayerLifecycle 이 부름): 바로 한 번 + 다른 CharacterAdded 처리(겉모습 등)가 끝난 뒤 한 번 더
function SizeService.onCharacterAdded(player: Player)
	SizeService.refresh(player)
	task.defer(function()
		if player.Parent ~= nil then
			SizeService.refresh(player)
		end
	end)
end

-- 시작: 이미 불러온 플레이어가 있으면 맞춤 (보통은 없음 — 접속 처리는 PlayerLifecycle 이 나중에 켬)
function SizeService.start()
	for player, session in Sessions.all() do
		if session.loaded then
			SizeService.refresh(player)
		end
	end
end

return SizeService
