--!strict
--[[
	Fx — 내 화면에서만 보이는 월드 연출 모음 (2단계 특수 장소용)
	  Fx.burst(pos, color, count, size, speed?)     반짝이 한 번 터뜨리기 (바깥으로)
	  Fx.gather(pos, color, seconds, radius?)       빛 모으기: 둘레에서 가운데로 빨려 들어가는 빛 + 빛 구슬
	  Fx.pillar(pos, color, height, seconds)        하늘로 솟는 빛기둥 (잠깐)
	  Fx.flash(pos, color, range, seconds)          잠깐 번쩍이는 불빛
	  Fx.petals(pos, color, count)                  꽃잎 흩날리기
	판정과 상관없음. 만든 것은 seconds 뒤 저절로 지워짐.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Fx = {}

local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"

local function holder(position: Vector3, size: number?): Part
	local p = Instance.new("Part")
	p.Name = "Fx"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * (size or 0.2)
	p.CFrame = CFrame.new(position)
	p.Parent = Workspace
	return p
end

local function emitter(parent: Instance, color: Color3, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE_TEX
	e.Enabled = false
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = parent
	return e
end

function Fx.burst(position: Vector3, color: Color3, count: number, size: number, speed: number?)
	local h = holder(position)
	local e = emitter(h, color, size)
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new((speed or 12) * 0.5, speed or 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -10, 0)
	e:Emit(count)
	task.delay(2, function()
		h:Destroy()
	end)
end

-- 빛 모으기: 공 표면에서 안쪽으로 (ParticleEmitter Shape = Sphere, Inward) + 빛 구슬 8개가 가운데로
function Fx.gather(position: Vector3, color: Color3, seconds: number, radius: number?)
	local r = radius or 7
	local shell = holder(position, r * 2)
	shell.Shape = Enum.PartType.Ball
	local e = emitter(shell, color, 0.7)
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	e.Lifetime = NumberRange.new(0.55, 0.65)
	e.Speed = NumberRange.new(r / 0.6)
	e.Rate = 120
	e.Enabled = true
	local orbs: { Part } = {}
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local orb = holder(position + Vector3.new(math.cos(a) * r, (i % 2) * 2 - 1, math.sin(a) * r), 0.8)
		orb.Shape = Enum.PartType.Ball
		orb.Material = Enum.Material.Neon
		orb.Color = color
		orb.Transparency = 0
		table.insert(orbs, orb)
		TweenService:Create(
			orb,
			TweenInfo.new(seconds * 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = position, Size = Vector3.one * 0.2 }
		):Play()
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 4
	light.Brightness = 1
	light.Parent = shell
	TweenService:Create(light, TweenInfo.new(seconds), { Range = 20, Brightness = 4 }):Play()
	task.delay(seconds, function()
		e.Enabled = false
		for _, orb in orbs do
			orb:Destroy()
		end
		Fx.burst(position, color, 60, 1.2, 18)
		Fx.burst(position, Color3.new(1, 1, 1), 25, 0.9, 10)
		task.delay(0.8, function()
			shell:Destroy()
		end)
	end)
end

-- 빛기둥 (Beam 이 아니라 반투명 네온 원기둥: 어디서 봐도 같은 굵기)
function Fx.pillar(position: Vector3, color: Color3, height: number, seconds: number)
	local p = holder(position + Vector3.new(0, height / 2, 0))
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, 0.5, 0.5)
	p.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.25
	TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = Vector3.new(height, 6, 6) }):Play()
	task.delay(math.max(0.4, seconds - 0.6), function()
		TweenService:Create(p, TweenInfo.new(0.6), { Size = Vector3.new(height, 0.2, 0.2), Transparency = 1 }):Play()
	end)
	task.delay(seconds + 0.1, function()
		p:Destroy()
	end)
end

function Fx.flash(position: Vector3, color: Color3, range: number, seconds: number)
	local h = holder(position)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 6
	light.Parent = h
	TweenService:Create(light, TweenInfo.new(seconds), { Brightness = 0 }):Play()
	task.delay(seconds + 0.1, function()
		h:Destroy()
	end)
end

function Fx.petals(position: Vector3, color: Color3, count: number)
	local h = holder(position, 6)
	local e = emitter(h, color, 0.6)
	e.Lifetime = NumberRange.new(1.5, 2.5)
	e.Speed = NumberRange.new(4, 10)
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(1, -4, 0.5)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.LightEmission = 0.4
	e.Size = NumberSequence.new(0.6)
	e:Emit(count)
	task.delay(3, function()
		h:Destroy()
	end)
end

return Fx
