--!strict
--[[
	PlayerVisualService — 플레이어 아우라 (선임). 서버에서 붙여서 모두에게 보임. Main.server 가 "*VisualService" 를 자동으로 시작.
	  힘(Attr Power)이 바뀌어 아우라 단계(shared/Data/Visuals.auraTier)가 달라졌을 때만 갈아 끼움.
	  HumanoidRootPart 아래: Attachment "AuraAttach" + ParticleEmitter "AuraSparks"(기본 모양, 위로 올라가는 빛 알갱이)
	    + PointLight "AuraLight" · 발밑 고리 Part "AuraRing"(얇은 원판, 뿌리에 Weld, 안 부딪힘). 캐릭터 Attr AuraTier.
	  외부 텍스처 id 없음. 저사양 설정이면 클라(AuraController)가 남의 파티클을 자기 화면에서 끔.
	  PlayerVisualService.apply(character, power) → 붙인 단계 (테스트용 공개)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Visuals = require(Shared.Data.Visuals)
local Tags = require(Shared.Tags)

local PlayerVisualService = {}

local POWER = Tags.PlayerAttributes.Power

local function clearAura(root: BasePart)
	for _, name in { "AuraAttach", "AuraLight" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local character = root.Parent
	local ring = character and character:FindFirstChild("AuraRing")
	if ring then
		ring:Destroy()
	end
end

function PlayerVisualService.apply(character: Model?, power: number?): number
	if not character then
		return 0
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return 0
	end
	local tier = Visuals.auraTier(power)
	local had = character:GetAttribute("AuraTier")
	if had == tier and (tier == 0 or root:FindFirstChild("AuraAttach")) then
		return tier -- 단계가 그대로면 다시 만들지 않음
	end
	clearAura(root)
	character:SetAttribute("AuraTier", tier)
	local a = Visuals.aura(tier)
	if not a then
		return tier
	end
	local attach = Instance.new("Attachment")
	attach.Name = "AuraAttach"
	attach.Position = Vector3.new(0, -1.5, 0)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "AuraSparks"
	sparks.Rate = math.min(a.rate, Visuals.AURA_RATE_CAP)
	sparks.Lifetime = NumberRange.new(0.8, 1.4)
	sparks.Speed = NumberRange.new(2, 4 + tier * 0.4)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.Acceleration = Vector3.new(0, 2, 0)
	sparks.LightEmission = 0.8
	sparks.LightInfluence = 0
	sparks.Color = ColorSequence.new(a.color, a.color2)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, a.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Parent = attach
	attach.Parent = root
	if a.light > 0 then
		local light = Instance.new("PointLight")
		light.Name = "AuraLight"
		light.Color = a.color
		light.Range = 8 + tier
		light.Brightness = a.light
		light.Shadows = false
		light.Parent = root
	end
	-- 발밑 고리
	local hum = character:FindFirstChildOfClass("Humanoid")
	local hip = if hum and hum.HipHeight > 0 then hum.HipHeight else 2
	local ring = Instance.new("Part")
	ring.Name = "AuraRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, 4 + tier * 0.2, 4 + tier * 0.2)
	ring.Color = a.color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.6
	ring.Anchored = false
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Massless = true
	local offset = CFrame.new(0, -(hip + root.Size.Y / 2) + 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2)
	ring.CFrame = root.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = ring
	weld.C0 = offset
	weld.Parent = ring
	ring.Parent = character
	return tier
end

local function watch(player: Player)
	local function refresh()
		PlayerVisualService.apply(player.Character, player:GetAttribute(POWER) :: number?)
	end
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		character:SetAttribute("AuraTier", nil)
		refresh()
	end)
	player:GetAttributeChangedSignal(POWER):Connect(refresh)
	if player.Character then
		refresh()
	end
end

function PlayerVisualService.start()
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
end

return PlayerVisualService
