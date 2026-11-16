--!strict
--[[
	DumbbellLook — 진짜 아령 모양 (선임). 손에 드는 아령(클라)과 가게 진열 아령(서버)이 같은 규칙.
	  가운데 손잡이 봉 + 양쪽 원판 (무거울수록 원판이 크고 여러 장) + 바깥 고정 링.
	  DumbbellLook.spec(level) → { t, plates, diameter, color, glow, ... }
	    t = 표 안에서 몇 번째인지 0~1 (아령 개수는 Dumbbells.list 길이를 그대로 읽음 — 고정 숫자 없음)
	    무게(weightKg 가 있으면, 없으면 이름의 "NNkg", 그것도 없으면 순번)로 크기를 정하되 상한이 있음:
	    원판 지름 0.55 ~ 1.5 (scale 1 기준) · 원판 1 ~ 4장. 상한을 넘는 무거운 아령은 크기 대신
	    빛(Neon + PointLight) · 단계 색으로 표현 (화면을 가리지 않게).
	  DumbbellLook.build(parent, level, scale, anchored) → Model "Dumbbell" (PrimaryPart = Bar, 봉은 X 축)
	    anchored=false 면 Massless·안 부딪힘·Weld 로 봉에 붙음 (손에 붙일 때).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dumbbells = require(ReplicatedStorage.Shared.Data.Dumbbells)

local DumbbellLook = {}

DumbbellLook.MAX_DIAMETER = 1.6
DumbbellLook.MIN_DIAMETER = 0.75
DumbbellLook.MAX_PLATES = 4
DumbbellLook.GLOW_FROM = 0.55 -- t 가 이것 이상이면 원판이 빛남
DumbbellLook.TWO_HANDS_FROM = 0.5 -- t 가 이것 이상이면 두 손으로 (양손에 하나씩)

export type Spec = {
	level: number,
	t: number,
	plates: number,
	diameter: number,
	thickness: number,
	handle: number,
	color: Color3,
	glow: boolean,
	twoHands: boolean,
	aura: number, -- 덤벨 아우라 0~5 (표 길이를 6구간으로): 1 원판 테두리 Neon · 2 빛 · 3 작은 파티클 · 4 큰 파티클 · 5 번개 Beam
}

DumbbellLook.AURA_STEPS = 6
-- 1번 아령 = 크리에이터 상점 무료 모델 "Dumbell" 과 같은 치수 (원기둥 5개, 에셋은 안 불러오고 코드로)
--   손잡이 1.60 × 지름 0.33 (205,205,205) · 안쪽 원판 두께 0.62 지름 1.09 ±0.75 · 바깥 원판 두께 0.41 지름 1.42 ±0.76 (17,17,17)
--   전체 길이 2.12 · 지름 1.42. 손·진열에서는 CLASSIC_SCALE 배로 줄임 (비율 그대로)
DumbbellLook.CLASSIC_SCALE = 0.5

-- 단계 색 (가벼운 → 무거운): 회색 쇠 · 파랑 · 초록 · 빨강 · 강철 · 금 · 다이아 · 용암 · 보라 · 무지개 끝
local TIER_COLORS: { Color3 } = {
	Color3.fromRGB(70, 74, 84),
	Color3.fromRGB(40, 110, 220),
	Color3.fromRGB(40, 170, 80),
	Color3.fromRGB(220, 60, 50),
	Color3.fromRGB(160, 170, 185),
	Color3.fromRGB(240, 190, 40),
	Color3.fromRGB(110, 230, 255),
	Color3.fromRGB(255, 110, 30),
	Color3.fromRGB(170, 80, 255),
	Color3.fromRGB(255, 80, 200),
	Color3.fromRGB(255, 250, 220),
}

local function count(): number
	return math.max(1, #Dumbbells.list)
end

DumbbellLook.count = count

local function kgOf(level: number): number?
	local d: any = Dumbbells.get(level)
	if not d then
		return nil
	end
	if type(d.weightKg) == "number" and d.weightKg > 0 then
		return d.weightKg
	end
	if type(d.name) == "string" then
		local n = tonumber(string.match(d.name, "^(%d+%.?%d*)%s*kg"))
		if n and n > 0 then
			return n
		end
	end
	return nil
end

function DumbbellLook.spec(level: number): Spec
	local n = count()
	local lv = math.clamp(math.floor(tonumber(level) or 1), 1, n)
	local rank = if n > 1 then (lv - 1) / (n - 1) else 0
	-- 무게가 있으면 1kg → 0 · 200kg 이상 → 1 (로그). 순번과 큰 쪽
	local kg = kgOf(lv)
	local byKg = if kg then math.clamp(math.log10(kg) / math.log10(200), 0, 1) else 0
	local t = math.max(rank, byKg)
	local grow = math.clamp(t / DumbbellLook.GLOW_FROM, 0, 1) -- 크기는 GLOW_FROM 에서 상한
	local tier = math.clamp(math.floor(rank * (#TIER_COLORS - 1) + 0.5) + 1, 1, #TIER_COLORS)
	return {
		level = lv,
		t = t,
		plates = math.clamp(1 + math.floor(grow * (DumbbellLook.MAX_PLATES - 1) + 0.5), 1, DumbbellLook.MAX_PLATES),
		diameter = DumbbellLook.MIN_DIAMETER + (DumbbellLook.MAX_DIAMETER - DumbbellLook.MIN_DIAMETER) * grow,
		thickness = 0.16,
		handle = 0.9,
		color = TIER_COLORS[tier],
		glow = t >= DumbbellLook.GLOW_FROM,
		twoHands = t >= DumbbellLook.TWO_HANDS_FROM,
		aura = math.clamp(math.floor(rank * DumbbellLook.AURA_STEPS), 0, DumbbellLook.AURA_STEPS - 1),
	}
end

local BAR_COLOR = Color3.fromRGB(185, 188, 196)

-- 봉(X 축) 위 원판 자리: 손잡이 끝에서 바깥으로 plates 장, 안쪽 원판이 가장 큼
function DumbbellLook.build(parent: Instance?, level: number, scale: number?, anchored: boolean?, cf: CFrame?): Model
	local s = DumbbellLook.spec(level)
	local k = scale or 1
	local model = Instance.new("Model")
	model.Name = "Dumbbell"
	model:SetAttribute("Level", s.level)
	model:SetAttribute("Plates", s.plates)
	local base = cf or CFrame.new()
	local plateSpan = s.plates * s.thickness * k
	local barLen = (s.handle * k) + 2 * (plateSpan + 0.12 * k)
	local function piece(name: string, size: Vector3, offsetX: number, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Anchored = anchored == true
		p.CanQuery = anchored == true
		p.Massless = true
		p.CFrame = base * CFrame.new(offsetX, 0, 0)
		p.Parent = model
		return p
	end
	local bar: Part
	if s.level == 1 then
		-- 1번 아령: 무료 모델 "Dumbell" 치수 그대로 (CLASSIC_SCALE 배)
		local q = k * DumbbellLook.CLASSIC_SCALE
		local black = Color3.fromRGB(17, 17, 17)
		bar = piece(
			"Bar",
			Vector3.new(1.6 * q, 0.33 * q, 0.33 * q),
			0,
			Color3.fromRGB(205, 205, 205),
			Enum.Material.Plastic
		)
		for _, side in { -1, 1 } do
			piece("Plate", Vector3.new(0.62 * q, 1.09 * q, 1.09 * q), side * 0.75 * q, black, Enum.Material.Plastic)
			piece(
				"PlateOuter",
				Vector3.new(0.41 * q, 1.42 * q, 1.42 * q),
				side * 0.76 * q,
				black,
				Enum.Material.Plastic
			)
		end
		model:SetAttribute("Classic", true)
	else
		bar = piece("Bar", Vector3.new(barLen, 0.22 * k, 0.22 * k), 0, BAR_COLOR, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			for i = 1, s.plates do
				-- 안쪽(i=1)이 가장 크고 바깥으로 조금씩 작아짐
				local d = s.diameter * k * (1 - (i - 1) * 0.12)
				local x = side * (s.handle * k / 2 + (i - 0.5) * s.thickness * k)
				local glowPlate = s.glow and i == 1
				piece(
					"Plate",
					Vector3.new(s.thickness * k * 0.92, d, d),
					x,
					s.color,
					if glowPlate then Enum.Material.Neon else Enum.Material.Metal
				)
			end
			-- 바깥 고정 링 (덤벨 아우라 1단계부터 Neon 테두리)
			piece(
				"Collar",
				Vector3.new(0.12 * k, 0.36 * k, 0.36 * k),
				side * (s.handle * k / 2 + plateSpan + 0.06 * k),
				if s.aura >= 1 then s.color else BAR_COLOR,
				if s.aura >= 1 then Enum.Material.Neon else Enum.Material.Metal
			)
		end
	end
	model.PrimaryPart = bar
	model:SetAttribute("Aura", s.aura)
	if s.glow or s.aura >= 2 then
		local light = Instance.new("PointLight")
		light.Name = "DumbbellLight"
		light.Color = s.color
		light.Range = 6 + 8 * s.t
		light.Brightness = 1 + 2 * s.t
		light.Shadows = false
		light.Parent = bar
	end
	-- 손에 든 아령만: 파티클(3단계~) · 번개 Beam(5단계). 진열 아령(anchored)은 가볍게 빛만
	if anchored ~= true and s.aura >= 3 then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "DumbbellSparks"
		sparks.Rate = if s.aura >= 4 then 10 else 6
		sparks.Lifetime = NumberRange.new(0.3, 0.6)
		sparks.Speed = NumberRange.new(1, 2)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.LightEmission = 1
		sparks.LightInfluence = 0
		sparks.Color = ColorSequence.new(s.color)
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, if s.aura >= 4 then 0.25 else 0.15),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparks.Parent = bar
		if s.aura >= 5 then
			local a0 = Instance.new("Attachment")
			a0.Name = "BeamA"
			a0.Position = Vector3.new(-barLen / 2, 0, 0)
			a0.Parent = bar
			local a1 = Instance.new("Attachment")
			a1.Name = "BeamB"
			a1.Position = Vector3.new(barLen / 2, 0, 0)
			a1.Parent = bar
			local beam = Instance.new("Beam")
			beam.Name = "Lightning"
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Color = ColorSequence.new(s.color, Color3.new(1, 1, 1))
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Width0 = 0.15
			beam.Width1 = 0.15
			beam.CurveSize0 = 1.2
			beam.CurveSize1 = -1.2
			beam.Segments = 6
			beam.FaceCamera = true
			beam.Parent = bar
		end
	end
	if anchored ~= true then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p ~= bar then
				local w = Instance.new("Weld")
				w.Name = "BarWeld"
				w.Part0 = bar
				w.Part1 = p
				w.C0 = bar.CFrame:ToObjectSpace(p.CFrame)
				w.Parent = p
			end
		end
	end
	if parent then
		model.Parent = parent
	end
	return model
end

-- 실제 가장 큰 지름 (scale 1)
function DumbbellLook.diameterOf(level: number): number
	local s = DumbbellLook.spec(level)
	return if s.level == 1 then 1.42 * DumbbellLook.CLASSIC_SCALE else s.diameter
end

-- 파트 수 (진열 상한 계산용)
function DumbbellLook.partCount(level: number): number
	if level == 1 then
		return 5
	end
	return 1 + DumbbellLook.spec(level).plates * 2 + 2
end

return DumbbellLook
