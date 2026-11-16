--!strict
--[[
	Cracks — 금 가는 연출 (선임, 내 화면에서만). 외부 이미지 없이 SurfaceGui 안의 회전한 가는 어두운 Frame(지그재그)으로 그림.
	  Cracks.stage(hp, hpMax) → 0~3 : 체력 75% 이하 1 · 50% 이하 2 · 25% 이하 3 (0 이하/가득이면 0)
	  Cracks.show(part, stage, seed, faces?) → 그 파트 앞(·뒤) 면에 stage 만큼 금 (단계가 그대로면 아무것도 안 함)
	      SurfaceGui 이름 "Crack_<면>", Attr CrackStage. 단계가 오르면 작은 조각이 떨어짐(chips=true 일 때).
	  Cracks.showModel(model, stage, seed, chips?) → 물건 모델의 "보이는 파트 겉면"에 붙는 금 (치는 물건용)
	      보이지 않는 맞히는 상자(Hitbox)·받침(Pedestal) 은 빼고, 보이는 파트만 레이캐스트해서 겉면 점·법선을 구하고
	      얇은 어두운 파트(마디)를 겉면에 0.03 스터드 띄워 붙임. 금 한 줄 = 마디 3~5개, 마디마다 다시 레이캐스트해서
	      굴곡(구면)을 따라감. 끝점이 겉면을 벗어나면 그 마디는 버림. 길이·굵기는 물건 크기에 비례.
	      75% → 3줄 · 50% → 6줄 · 25% → 11줄(굵게), 물건 하나 최대 40 마디. 모델 안 Folder "CrackMarks"(Attr CrackStage).
	      (레이캐스트는 단계가 바뀔 때만. 마디는 Anchored · 충돌/질의/그림자 없음, 모델 안이라 PivotTo 흔들림을 같이 따라감)
	  Cracks.clear(partOrModel) · Cracks.stageOf(partOrModel)
	송판(심사·대결)은 송판 파트 자체 면에 SurfaceGui (Cracks.show) — 송판 겉면 그대로라 그대로 둠.
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

Cracks.MODEL_LINES = { 3, 6, 11 } -- showModel: 단계별 금 줄 수
Cracks.MAX_SEGMENTS = 40 -- 물건 하나의 금 마디 상한 (성능)
Cracks.LIFT = 0.03 -- 겉면에서 띄우는 거리
Cracks.FOLDER = "CrackMarks"
local SKIP_NAMES = { Hitbox = true, Pedestal = true, PedestalGlow = true }

function Cracks.stageOf(part: Instance): number
	local holder = part:FindFirstChild(Cracks.FOLDER) or part:FindFirstChild("Crack_Front")
	local s = holder and holder:GetAttribute("CrackStage")
	return if type(s) == "number" then s else 0
end

function Cracks.clear(part: Instance)
	for _, child in part:GetChildren() do
		if
			(child:IsA("SurfaceGui") and string.sub(child.Name, 1, 6) == "Crack_")
			or (child:IsA("Folder") and child.Name == Cracks.FOLDER)
		then
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

------------------------------------------------------------------
-- 물건 겉면에 붙는 금 (showModel)
------------------------------------------------------------------

-- 금을 붙일 보이는 파트 (맞히는 상자·받침·금 자신 제외)
function Cracks.visibleParts(model: Instance): { BasePart }
	local out: { BasePart } = {}
	local marks = model:FindFirstChild(Cracks.FOLDER)
	for _, d in model:GetDescendants() do
		if
			d:IsA("BasePart")
			and d.Transparency < 1
			and not SKIP_NAMES[d.Name]
			and not (marks and d:IsDescendantOf(marks))
		then
			table.insert(out, d)
		end
	end
	return out
end

type Hit = { pos: Vector3, normal: Vector3 }

-- 레이를 쏠 방향 (모델 기준, 앞 = -Z = 길·플레이어 쪽). 앞면 위주 + 윗면 + 앞 대각선 + 옆
local DIRS = {
	Vector3.new(0, 0, -1),
	Vector3.new(0, 0, -1),
	Vector3.new(-0.7, 0, -0.7),
	Vector3.new(0.7, 0, -0.7),
	Vector3.new(0, 1, 0),
	Vector3.new(0, 0.7, -0.7),
	Vector3.new(-1, 0, 0),
	Vector3.new(1, 0, 0),
}
local SEG_THICK = { 0.012, 0.018, 0.026 } -- 물건 크기 × 이 값 = 금 굵기

local function boundsOf(parts: { BasePart }, frame: CFrame): (Vector3, Vector3)
	local lx, ly, lz = math.huge, math.huge, math.huge
	local hx, hy, hz = -math.huge, -math.huge, -math.huge
	for _, p in parts do
		local h = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c =
						frame:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)))
					lx, ly, lz = math.min(lx, c.X), math.min(ly, c.Y), math.min(lz, c.Z)
					hx, hy, hz = math.max(hx, c.X), math.max(hy, c.Y), math.max(hz, c.Z)
				end
			end
		end
	end
	return Vector3.new(lx, ly, lz), Vector3.new(hx, hy, hz)
end

-- v 를 법선 n 둘레로 a 라디안 돌림 (v 는 n 에 수직이라고 봄)
local function turn(v: Vector3, n: Vector3, a: number): Vector3
	return v * math.cos(a) + n:Cross(v) * math.sin(a)
end

local function tangentOf(v: Vector3, n: Vector3): Vector3
	local t = v - n * v:Dot(n)
	if t.Magnitude < 1e-3 then
		t = n:Cross(if math.abs(n.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0))
	end
	return t.Unit
end

function Cracks.showModel(model: Model, stage: number, seed: number, withChips: boolean?): number
	local before = Cracks.stageOf(model)
	if stage == before then
		return stage
	end
	Cracks.clear(model)
	if stage <= 0 then
		return 0
	end
	local parts = Cracks.visibleParts(model)
	local folder = Instance.new("Folder")
	folder.Name = Cracks.FOLDER
	folder:SetAttribute("CrackStage", stage)
	if #parts == 0 then
		folder.Parent = model
		return stage
	end
	local frame = model:GetPivot()
	local lo, hi = boundsOf(parts, frame)
	local size = hi - lo
	local big = math.max(size.X, size.Y, size.Z)
	local reach = size.Magnitude + 2
	local segLen = math.clamp(big * 0.09, 0.12, 6)
	local s = math.clamp(stage, 1, 3)
	local thick = math.clamp(big * SEG_THICK[s], 0.03, 0.8)
	local rand = rng(seed)

	-- 보이는 파트만 맞도록 (CanQuery 가 꺼진 겉모습 파트도 잠깐 켰다가 돌려놓음 — 내 화면에서만)
	local saved: { boolean } = {}
	local include: { Instance } = {}
	for i, p in parts do
		saved[i] = p.CanQuery
		p.CanQuery = true
		include[i] = p
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include

	local function cast(origin: Vector3, dir: Vector3): Hit?
		local r = Workspace:Raycast(origin, dir, params)
		if r then
			return { pos = r.Position, normal = r.Normal }
		end
		return nil
	end

	local function lerp(a: number, b: number, t: number): number
		return a + (b - a) * t
	end

	local function startHit(): Hit?
		for _ = 1, 6 do
			local d = DIRS[1 + math.floor(rand() * #DIRS) % #DIRS]
			local dirW = frame:VectorToWorldSpace(d.Unit)
			local inside = frame:PointToWorldSpace(
				Vector3.new(
					lerp(lo.X, hi.X, 0.15 + 0.7 * rand()),
					lerp(lo.Y, hi.Y, 0.2 + 0.65 * rand()),
					lerp(lo.Z, hi.Z, 0.15 + 0.7 * rand())
				)
			)
			local hit = cast(inside + dirW * reach, -dirW * reach * 2)
			if hit and hit.normal:Dot(dirW) > 0.15 then
				return hit
			end
		end
		return nil
	end

	-- 겉면을 따라 한 마디 앞으로: 끝점을 겉면에 다시 맞춤. 겉면을 벗어나면 방향을 틀어 다시, 그래도 안 되면 nil
	local function step(from: Hit, heading: Vector3): (Hit?, Vector3)
		local h = heading
		for _ = 1, 3 do
			local t = tangentOf(h, from.normal)
			local q = from.pos + t * segLen
			local hit = cast(q + from.normal * segLen, -from.normal * segLen * 2)
			if hit and (hit.pos - q).Magnitude <= segLen * 0.6 and hit.normal:Dot(from.normal) > 0.5 then
				return hit, t
			end
			h = turn(t, from.normal, (rand() - 0.5) * 3.5)
		end
		return nil, h
	end

	local count = 0
	local function place(a: Hit, b: Hit, seg: number): boolean
		local mid = (a.pos + b.pos) / 2
		local n = a.normal + b.normal
		n = if n.Magnitude > 1e-3 then n.Unit else a.normal
		local m = cast(mid + n * segLen, -n * segLen * 2)
		if not m or (m.pos - mid).Magnitude > segLen * 0.6 then
			return false -- 가운데가 겉면 밖 → 이 마디 버림
		end
		n = m.normal
		local along = b.pos - a.pos
		along -= n * along:Dot(n)
		if along.Magnitude < 1e-3 then
			return false
		end
		local w = thick * (1 - (seg - 1) * 0.12)
		local at = m.pos + n * (Cracks.LIFT + 0.01)
		local p = Instance.new("Part")
		p.Name = "Crack"
		p.Size = Vector3.new(math.max(w, 0.02), 0.02, along.Magnitude + w * 0.6)
		p.CFrame = CFrame.lookAt(at, at + along.Unit, n)
		p.Color = INK
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
		count += 1
		return true
	end

	local starts: { Hit } = {}
	local lines = Cracks.MODEL_LINES[s]
	local made, attempts = 0, 0
	while made < lines and count < Cracks.MAX_SEGMENTS and attempts < lines * 4 do
		attempts += 1
		local cur = startHit()
		if cur then
			local heading = frame:VectorToWorldSpace(Vector3.new(rand() - 0.5, rand() - 0.5, rand() - 0.5))
			local segs = 3 + math.floor(rand() * 3) -- 3~5 마디
			local any = false
			for seg = 1, segs do
				if count >= Cracks.MAX_SEGMENTS then
					break
				end
				local nxt, t = step(cur, heading)
				if not nxt then
					break
				end
				if place(cur, nxt, seg) then
					any = true
				end
				-- 지그재그: 다음 마디는 ±20~50° 꺾음
				local sign = if rand() < 0.5 then -1 else 1
				heading = turn(tangentOf(t, nxt.normal), nxt.normal, sign * (0.35 + rand() * 0.5))
				cur = nxt
			end
			if any then
				made += 1
				table.insert(starts, cur)
			end
		end
	end
	for i, p in parts do
		p.CanQuery = saved[i]
	end
	folder:SetAttribute("CrackLines", made)
	folder.Parent = model

	-- 단계가 오르면 금 자리에서 작은 조각이 떨어짐
	if withChips ~= false and stage > before then
		local color = parts[1].Color
		for i = 1, math.min(#starts, stage + 1) do
			local h = starts[i]
			local c = Instance.new("Part")
			c.Name = "Chip"
			c.Size = Vector3.one * math.clamp(big * 0.04, 0.15, 1.5)
			c.Color = color
			c.Material = Enum.Material.SmoothPlastic
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = false
			c.Anchored = false
			c.CFrame = CFrame.new(h.pos + h.normal * c.Size.X)
			c.Parent = Workspace
			task.delay(0.9, function()
				c:Destroy()
			end)
		end
	end
	return stage
end

return Cracks
