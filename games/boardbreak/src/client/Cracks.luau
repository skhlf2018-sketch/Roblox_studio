--!strict
--[[
	Cracks — 금 가는 연출 (선임, 내 화면에서만). 외부 이미지 없이 SurfaceGui 안의 회전한 가는 어두운 Frame(지그재그)으로 그림.
	  Cracks.stage(hp, hpMax) → 0~3 : 체력 75% 이하 1 · 50% 이하 2 · 25% 이하 3 (0 이하/가득이면 0)
	  Cracks.show(part, stage, seed, faces?) → 그 파트 앞(·뒤) 면에 stage 만큼 금 (단계가 그대로면 아무것도 안 함)
	      SurfaceGui 이름 "Crack_<면>", Attr CrackStage. 단계가 오르면 작은 조각이 떨어짐(chips=true 일 때).
	  Cracks.clear(part) · Cracks.stageOf(part)
	1단계 가는 금 3줄 · 2단계 굵은 금 9줄 · 3단계 더 굵은 금 18줄 (지그재그 한 줄 = Frame 3개).
]]

local Workspace = game:GetService("Workspace")

local Cracks = {}

Cracks.LINES = { 1, 2, 3 } -- 단계마다 금 줄 수 (× 3 마디)
local THICK = { 3, 6, 9 }
local INK = Color3.fromRGB(28, 20, 16)

function Cracks.stage(hp: number?, hpMax: number?): number
	local h, m = tonumber(hp) or 0, tonumber(hpMax) or 0
	if m <= 0 or h <= 0 or h >= m then
		return 0
	end
	local r = h / m
	if r <= 0.25 then
		return 3
	elseif r <= 0.5 then
		return 2
	elseif r <= 0.75 then
		return 1
	end
	return 0
end

function Cracks.stageOf(part: Instance): number
	local gui = part:FindFirstChild("Crack_Front")
	local s = gui and gui:GetAttribute("CrackStage")
	return if type(s) == "number" then s else 0
end

function Cracks.clear(part: Instance)
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceGui") and string.sub(child.Name, 1, 6) == "Crack_" then
			child:Destroy()
		end
	end
end

-- 작은 결정적 난수 (같은 물건은 늘 같은 금 모양)
local function rng(seed: number): () -> number
	local s = math.floor(seed) % 2147483647
	if s <= 0 then
		s = 12345
	end
	return function(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

local function seedOf(text: string): number
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483647
	end
	return h
end
Cracks.seedOf = seedOf

local function drawLines(holder: Frame, stage: number, seed: number)
	local rand = rng(seed)
	local lines = 0
	for s = 1, stage do
		lines += Cracks.LINES[s] * 3
	end
	for _ = 1, lines do
		-- 가운데 근처에서 시작해 바깥으로 3 마디 지그재그
		local x, y = 0.5 + (rand() - 0.5) * 0.3, 0.5 + (rand() - 0.5) * 0.3
		local angle = rand() * 360
		for seg = 1, 3 do
			local len = 0.12 + rand() * 0.14
			local a = angle + (rand() - 0.5) * 70
			local f = Instance.new("Frame")
			f.Name = "Line"
			f.BorderSizePixel = 0
			f.BackgroundColor3 = INK
			f.BackgroundTransparency = 0.05
			f.AnchorPoint = Vector2.new(0, 0.5)
			f.Position = UDim2.fromScale(x, y)
			f.Size = UDim2.new(len, 0, 0, THICK[math.clamp(stage, 1, 3)] - (seg - 1))
			f.Rotation = a
			f.Parent = holder
			local rad = math.rad(a)
			x = math.clamp(x + math.cos(rad) * len, 0.02, 0.98)
			y = math.clamp(y + math.sin(rad) * len, 0.02, 0.98)
		end
	end
end

local function chips(part: BasePart, count: number)
	for i = 1, count do
		local p = Instance.new("Part")
		p.Name = "Chip"
		p.Size = Vector3.one * math.clamp(part.Size.X * 0.06, 0.25, 1.5)
		p.Color = part.Color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Anchored = false
		p.CFrame = part.CFrame * CFrame.new((i - count / 2) * 0.4, part.Size.Y * 0.2, -part.Size.Z / 2 - 0.3)
		p.Parent = Workspace
		task.delay(0.9, function()
			p:Destroy()
		end)
	end
end

-- faces: 기본 { Front }. 단계가 바뀌었을 때만 다시 그림. 반환: 새 단계
function Cracks.show(
	part: BasePart,
	stage: number,
	seed: number,
	faces: { Enum.NormalId }?,
	withChips: boolean?
): number
	local before = Cracks.stageOf(part)
	if stage == before and (stage == 0 or part:FindFirstChild("Crack_Front")) then
		return stage
	end
	Cracks.clear(part)
	if stage <= 0 then
		return 0
	end
	local list: { Enum.NormalId } = faces or { Enum.NormalId.Front }
	for _, face in list do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Crack_" .. face.Name
		gui.Face = face
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 25
		gui.MaxDistance = 400
		gui:SetAttribute("CrackStage", stage)
		local holder = Instance.new("Frame")
		holder.Name = "Cracks"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(1, 1)
		holder.Parent = gui
		drawLines(holder, stage, seed)
		gui.Parent = part
	end
	if withChips ~= false and stage > before then
		chips(part, stage + 1)
	end
	return stage
end

return Cracks
