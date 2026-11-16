--!strict
--[[
	Build — 맵 부품 만드는 도우미 (선임). 첫 게임 MapBuilder 의 makePart / P 방식을 줄여서 가져옴.
	  Build.part(parent, shape, size, cframe, color, material?, opts?)  shape: "Block" | "Ball" | "VCyl" | "HCyl" | "Wedge"
	    VCyl = 세운 원기둥, size = (지름, 높이, 지름) / HCyl = 누운 원기둥 (X 축이 길이), size = (길이, 지름, 지름)
	  Build.folder · Build.model · Build.light · Build.click (ClickDetector) · Build.surfaceSign · Build.billboard
	외부 에셋·메시 없음 (Ball 을 납작하게 하고 싶으면 opts.ellipsoid → SpecialMesh Sphere).
]]

local CollectionService = game:GetService("CollectionService")

local Build = {}

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
