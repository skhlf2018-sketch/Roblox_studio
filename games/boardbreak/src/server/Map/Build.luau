--!strict
--[[
	Build — 맵 부품 만드는 도우미 (선임). 첫 게임 MapBuilder 의 makePart / P 방식을 줄여서 가져옴.
	  Build.part(parent, shape, size, cframe, color, material?, opts?)  shape: "Block" | "Ball" | "VCyl" | "HCyl" | "Wedge"
	    VCyl = 세운 원기둥, size = (지름, 높이, 지름) / HCyl = 누운 원기둥 (X 축이 길이), size = (길이, 지름, 지름)
	  Build.folder · Build.model · Build.light · Build.click (ClickDetector) · Build.surfaceSign · Build.billboard
	외부 에셋·메시 없음 (Ball 을 납작하게 하고 싶으면 opts.ellipsoid → SpecialMesh Sphere).
	크기 (사장님 결정 13번):
	  Build.scaleTree(root, originX, s)  배율 1 로 지은 월드를 원점(originX, 0, 0) 기준으로 통째로 s 배 (자리·크기·글 거리·
	                                     클릭 거리·빛 범위(최대 60)·Attachment·SurfaceGui 픽셀 밀도 · Attr Height/Radius/RoofBottom).
	                                     사람 몸(Humanoid 가 있는 Model)은 Model:ScaleTo (없으면 직접 — 관절 C0/C1·HipHeight 까지)
	  Build.tile(part, size, cf)          키운 크기가 한 축 2,000 을 넘는 네모 판 → 숫자로 조각을 나눠 빈틈없이 덮음 (scaleTree 가 부름 —
	                                     엔진은 Part.Size 를 넣는 순간 2048 로 자르므로 큰 크기는 절대 넣지 않음. Build.setSize = 엔진처럼 자르고 셈)
	  Build.splitLarge(root)             (예비) 이미 2,000 넘는 네모 판을 조각으로
	  Build.maxAxis(root)                가장 긴 파트 축 (스모크 검사용)
	  Build.PASS_GROUP · PLAYER_GROUP    지붕·윗벽·문 위 들보 = PASS_GROUP: 플레이어 몸(PLAYER_GROUP)과 안 부딪힘
	                                     (문·천장보다 큰 거인이 월드 1 로 돌아와도 안 끼임. 카메라는 그대로 천장에서 멈춤)
]]

local CollectionService = game:GetService("CollectionService")

local Groups = require(script.Parent.Groups)

local Build = {}

Build.PART_LIMIT = 2000 -- 로블록스 한 축 최대 2048 (여유)
Build.ENGINE_MAX_AXIS = 2048 -- 엔진이 Part.Size 를 넣는 순간 이 값으로 자름 (본부장 2026-11-16 스튜디오에서 확인)
Build.clamped = 0 -- setSize 가 엔진처럼 자른 횟수 (0 이어야 함 — 스모크 검사)

-- 파트 크기 넣기: 엔진과 똑같이 한 축 2048 로 자름 (Lune 가짜는 안 잘라서 버그가 숨었음) + 자른 횟수 셈.
--   큰 판은 이 함수를 부르기 전에 숫자로 조각을 나눠야 함 (Build.scaleTree)
function Build.setSize(part: BasePart, size: Vector3)
	local m = Build.ENGINE_MAX_AXIS
	if size.X > m or size.Y > m or size.Z > m then
		Build.clamped += 1
		size = Vector3.new(math.min(size.X, m), math.min(size.Y, m), math.min(size.Z, m))
	end
	part.Size = size
end
Build.LIGHT_RANGE_MAX = Groups.LIGHT_RANGE_MAX -- PointLight/SpotLight/SurfaceLight Range 최대
Build.PASS_GROUP = Groups.PASS
Build.PLAYER_GROUP = Groups.PLAYER
-- 월드를 키울 때 같이 곱하는 Attribute (길이)
Build.LENGTH_ATTRIBUTES = { "Height", "Radius", "RoofBottom" }

export type Opts = {
	collide: boolean?,
	query: boolean?, -- 마우스·ClickDetector 가 맞힐 수 있나 (기본: collide 와 같음)
	transparency: number?,
	name: string?,
	tag: string?,
	attributes: { [string]: any }?,
	reflectance: number?,
	ellipsoid: boolean?,
	shadow: boolean?,
}

Build.M = Enum.Material

function Build.part(
	parent: Instance,
	shape: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	opts: Opts?
): Part
	local o: Opts = opts or {}
	local p = Instance.new("Part")
	p.Name = o.name or shape
	p.Anchored = true
	local collide = o.collide == true
	p.CanCollide = collide
	p.CanQuery = if o.query == nil then collide else o.query
	p.CanTouch = false
	p.CastShadow = if o.shadow == nil then collide else o.shadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = o.transparency or 0
	p.Reflectance = o.reflectance or 0
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * size.X
		p.CFrame = cframe
	elseif shape == "VCyl" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(size.Y, size.X, size.X)
		p.CFrame = cframe * CFrame.Angles(0, 0, math.pi / 2)
	elseif shape == "HCyl" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.CFrame = cframe
	elseif shape == "Wedge" then
		p.Shape = Enum.PartType.Wedge
		p.Size = size
		p.CFrame = cframe
	else
		p.Size = size
		p.CFrame = cframe
	end
	if o.ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	if o.attributes then
		for key, value in o.attributes do
			p:SetAttribute(key, value)
		end
	end
	if o.tag then
		CollectionService:AddTag(p, o.tag)
	end
	p.Parent = parent
	return p
end

-- 바닥·벽처럼 밟고 부딪히는 큰 판
function Build.solid(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	opts: Opts?
): Part
	local o: Opts = opts or {}
	o.collide = true
	o.name = name
	return Build.part(parent, "Block", size, cframe, color, material, o)
end

function Build.folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Build.model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Build.light(parent: Instance, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = parent
end

-- 눌러서 동작 (회색 E 프롬프트 대신). 서버는 클릭을 안 듣고 클라 컨트롤러가 Remote 를 보냄 (서버가 다시 검사)
function Build.click(parent: Instance, name: string, distance: number): ClickDetector
	local c = Instance.new("ClickDetector")
	c.Name = name
	c.MaxActivationDistance = distance
	c.Parent = parent
	return c
end

local function text(
	parent: Instance,
	name: string,
	pos: UDim2,
	size: UDim2,
	value: string,
	color: Color3,
	strokeColor: Color3?
): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = value
	t.Parent = parent
	local s = Instance.new("UIStroke")
	s.Color = strokeColor or Color3.fromRGB(10, 10, 20)
	s.Thickness = 3
	s.Parent = t
	return t
end
Build.text = text

-- 판 앞면 글 (SurfaceGui). 반환: 바탕 Frame (거기에 Build.text 로 글을 더함)
function Build.surfaceSign(board: BasePart, background: Color3, pixelsPerStud: number?): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 40
	gui.LightInfluence = 0
	gui.MaxDistance = 200
	local frame = Instance.new("Frame")
	frame.Name = "Board"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = background
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.Color = Color3.fromRGB(12, 14, 26)
	stroke.Thickness = 8
	stroke.Parent = frame
	gui.Parent = board
	return frame
end

-- 머리 위 글 (BillboardGui). 반환: BillboardGui
function Build.billboard(
	adornee: BasePart,
	name: string,
	size: UDim2,
	offsetY: number,
	maxDistance: number
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance
	gui.ResetOnSpawn = false
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

------------------------------------------------------------------
-- 월드 통째로 키우기
------------------------------------------------------------------

local function scaleAttributes(inst: Instance, s: number)
	for _, key in Build.LENGTH_ATTRIBUTES do
		local v = inst:GetAttribute(key)
		if type(v) == "number" then
			inst:SetAttribute(key, v * s)
		end
	end
end

local function scaleJoint(j: Instance, s: number)
	if j:IsA("JointInstance") then
		j.C0 = (j.C0 - j.C0.Position) + j.C0.Position * s
		j.C1 = (j.C1 - j.C1.Position) + j.C1.Position * s
	end
end

-- 파트가 아닌 것 하나 (글·빛·클릭·Attachment)
local function scaleOther(d: Instance, s: number)
	if d:IsA("Attachment") then
		d.Position *= s
	elseif d:IsA("BillboardGui") then
		d.StudsOffsetWorldSpace *= s
		d.StudsOffset *= s
		d.MaxDistance *= s
	elseif d:IsA("SurfaceGui") then
		-- 판이 s 배 커져도 글 픽셀 수는 그대로 (글자·테두리 두께가 월드 1 과 똑같이 보임, 그림 메모리도 그대로)
		d.PixelsPerStud = d.PixelsPerStud / s
		d.MaxDistance *= s
	elseif d:IsA("ClickDetector") then
		d.MaxActivationDistance *= s
	elseif d:IsA("Light") then
		local light = d :: any -- PointLight · SpotLight · SurfaceLight 모두 Range 가 있음
		light.Range = math.min(Build.LIGHT_RANGE_MAX, light.Range * s)
	elseif d:IsA("Humanoid") then
		d.HipHeight *= s
	end
	scaleJoint(d, s)
	scaleAttributes(d, s)
end

local function moveAbout(cf: CFrame, origin: Vector3, s: number): CFrame
	return CFrame.new(origin + (cf.Position - origin) * s) * cf.Rotation
end

-- 사람 몸 (사범님 R15): Model:ScaleTo 로 키우고 자리만 옮김. ScaleTo 가 없으면(테스트 환경) 직접
local function scaleRig(rig: Model, origin: Vector3, s: number)
	local pivot = rig:GetPivot()
	local ok = pcall(function()
		(rig :: any):ScaleTo((rig :: any):GetScale() * s)
	end)
	if ok then
		rig:PivotTo(moveAbout(pivot, origin, s))
		-- 머리 위 이름표 (글은 ScaleTo 가 안 키움 — 스튜디오 확인 필요)
		for _, d in rig:GetDescendants() do
			if d:IsA("BillboardGui") then
				d.StudsOffsetWorldSpace *= s
				d.StudsOffset *= s
				d.MaxDistance *= s
			end
		end
		scaleAttributes(rig, s)
		return
	end
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			Build.setSize(d, d.Size * s)
			d.CFrame = moveAbout(cf, origin, s)
		else
			scaleOther(d, s)
		end
		scaleAttributes(d, s)
	end
	scaleAttributes(rig, s)
end

function Build.scaleTree(root: Instance, originX: number, s: number)
	if s == 1 then
		return
	end
	local origin = Vector3.new(originX, 0, 0)
	local rigs: { Model } = {}
	local function inRig(d: Instance): boolean
		for _, rig in rigs do
			if d:IsDescendantOf(rig) then
				return true
			end
		end
		return false
	end
	for _, d in root:GetDescendants() do
		if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") then
			table.insert(rigs, d)
		end
	end
	-- 키운 크기가 한 축 PART_LIMIT 를 넘는 파트는 크기를 넣지 않고 따로 모아 둠 (엔진이 2048 로 잘라 버림 — 본부장
	--   2026-11-16 스튜디오: 잘린 크기로 나눠서 월드 2·3 바닥·길이 엉뚱한 자리·크기 → 월드 3 에서 허공으로 떨어짐)
	type Big = { part: BasePart, size: Vector3, cf: CFrame }
	local big: { Big } = {}
	for _, d in root:GetDescendants() do
		if not inRig(d) then
			if d:IsA("BasePart") then
				local cf = d.CFrame
				local size = d.Size * s
				local newCf = moveAbout(cf, origin, s)
				scaleAttributes(d, s)
				local lim = Build.PART_LIMIT
				if size.X > lim or size.Y > lim or size.Z > lim then
					table.insert(big, { part = d, size = size, cf = newCf })
				else
					Build.setSize(d, size)
					d.CFrame = newCf
				end
			else
				scaleOther(d, s)
			end
		end
	end
	-- 큰 파트: 숫자로 조각을 나눠 만듦 (자식 글 등은 위에서 이미 키워 둠 → 복제에 그대로 들어감)
	for _, b in big do
		Build.tile(b.part, b.size, b.cf)
	end
	for _, rig in rigs do
		scaleRig(rig, origin, s)
	end
	scaleAttributes(root, s)
end

-- part 를 "크기 size · 자리 cf" 인 판으로 보고, 한 축 PART_LIMIT 이하 같은 크기 조각으로 빈틈없이 덮음 (복제 — 태그·
--   Attribute·자식 같이). 원래 파트는 지움. 네모 판(Block)만 나눌 수 있음 — 다른 모양은 경고 + Attr TooBig (스모크가 잡음).
--   반환: 만든 조각 수
function Build.tile(part: BasePart, size: Vector3, cf: CFrame): number
	local lim = Build.PART_LIMIT
	local isBlock = part:IsA("Part") and part.Shape == Enum.PartType.Block
	if not isBlock then
		warn("[Build] 2,048 넘는 둥근 파트는 나눌 수 없음: " .. part:GetFullName())
		part:SetAttribute("TooBig", true)
		Build.setSize(part, size)
		part.CFrame = cf
		return 1
	end
	local nx, ny, nz = math.ceil(size.X / lim), math.ceil(size.Y / lim), math.ceil(size.Z / lim)
	local piece = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
	local made = 0
	for ix = 1, nx do
		for iy = 1, ny do
			for iz = 1, nz do
				local c = part:Clone()
				Build.setSize(c, piece)
				c.CFrame = cf
					* CFrame.new(
						-size.X / 2 + (ix - 0.5) * piece.X,
						-size.Y / 2 + (iy - 0.5) * piece.Y,
						-size.Z / 2 + (iz - 0.5) * piece.Z
					)
				c.Parent = part.Parent
				made += 1
			end
		end
	end
	part:Destroy()
	return made
end

-- 한 축이 limit 를 넘는 네모 판을 같은 크기 조각으로 나눔 (복제 — 태그·Attribute·자식도 같이). 나눈 조각 수 합 반환
function Build.splitLarge(root: Instance, limit: number?): number
	local max = limit or Build.PART_LIMIT
	local made = 0
	local list: { BasePart } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Part") and d.Shape == Enum.PartType.Block then
			local s = d.Size
			if s.X > max or s.Y > max or s.Z > max then
				table.insert(list, d)
			end
		end
	end
	for _, p in list do
		made += Build.tile(p, p.Size, p.CFrame)
	end
	return made
end

-- 가장 긴 파트 축 (root 아래 전부) → 길이, 그 파트
function Build.maxAxis(root: Instance): (number, BasePart?)
	local best, which = 0, nil
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local s = d.Size
			local m = math.max(s.X, s.Y, s.Z)
			if m > best then
				best, which = m, d
			end
		end
	end
	return best, which
end

-- 거인이 지나가는 파트 (지붕·윗벽·들보): 플레이어 몸과 안 부딪힘. 충돌 그룹이 없으면(테스트) Attribute 만
function Build.giantPass(part: BasePart)
	part:SetAttribute("GiantPass", true)
	pcall(function()
		part.CollisionGroup = Build.PASS_GROUP
	end)
end

-- 충돌 그룹 등록 (서버 시작 때 한 번). PASS_GROUP ↔ PLAYER_GROUP 안 부딪힘
Build.registerGroups = Groups.register

-- inst 아래 BasePart 개수 (inst 자신이 파트면 포함)
function Build.countParts(inst: Instance): number
	local n = if inst:IsA("BasePart") then 1 else 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return Build
