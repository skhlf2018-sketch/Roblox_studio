--!strict
--[[
	Gui — 월드 표지판/이름표 (서버에서 만들어 모두에게 보임). 선임 담당.

	  Gui.billboard(adornee, text, offsetY, maxDistance?) -> TextLabel   (기존 그대로: EggService/BaseService/GuardianService 사용)
	  Gui.surface(part, face, text, color?) -> TextLabel                 (기존 그대로)
	  Gui.sign(part, face, opts) -> { frame, title, subtitle? }           큰 제목 + 작은 부제 표지판
	  Gui.tag(adornee, offsetY, maxDistance, lines) -> { TextLabel }      여러 줄 머리 위 이름표 (펫 이름·수입 등)
]]

local Gui = {}

local FONT = Enum.Font.FredokaOne

function Gui.billboard(adornee: BasePart, text: string, offsetY: number, maxDistance: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 80
	gui.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = FONT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(40, 30, 60)
	label.Text = text
	label.Parent = gui
	gui.Parent = adornee
	return label
end

function Gui.surface(part: BasePart, face: Enum.NormalId, text: string, color: Color3?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = FONT
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = part
	return label
end

export type SignOptions = {
	title: string,
	subtitle: string?,
	badge: string?, -- 왼쪽 위 동그란 숫자 (구역 번호 등)
	corner: string?, -- 오른쪽 위 리본 ("NEW!")
	background: Color3?,
	titleColor: Color3?,
}

export type SignParts = {
	frame: Frame,
	title: TextLabel,
	subtitle: TextLabel?,
}

local function corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function textStroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
end

-- 큰 제목 + 작은 부제 (구역 입구 표지판: 이름 크게, 추천 속도 작게)
function Gui.sign(part: BasePart, face: Enum.NormalId, opts: SignOptions): SignParts
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.MaxDistance = 400

	local bg = opts.background or Color3.fromRGB(255, 150, 80)
	local frame = Instance.new("Frame")
	frame.Name = "Board"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.96, 0.9)
	frame.BackgroundColor3 = bg
	frame.Parent = gui
	corner(frame, 0.12)
	stroke(frame, Color3.new(1, 1, 1), 6)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(bg:Lerp(Color3.new(1, 1, 1), 0.25), bg:Lerp(Color3.new(0, 0, 0), 0.15))
	gradient.Parent = frame

	local hasSub = opts.subtitle ~= nil and opts.subtitle ~= ""
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, if hasSub then 0.08 else 0.15)
	title.Size = UDim2.fromScale(0.78, if hasSub then 0.6 else 0.7)
	title.Font = FONT
	title.TextScaled = true
	title.TextColor3 = opts.titleColor or Color3.new(1, 1, 1)
	title.Text = opts.title
	title.Parent = frame
	textStroke(title, Color3.fromRGB(40, 30, 60), 4)

	local subtitle: TextLabel? = nil
	if hasSub then
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.BackgroundTransparency = 1
		sub.AnchorPoint = Vector2.new(0.5, 1)
		sub.Position = UDim2.fromScale(0.5, 0.92)
		sub.Size = UDim2.fromScale(0.8, 0.2)
		sub.Font = FONT
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(255, 250, 220)
		sub.Text = opts.subtitle or ""
		sub.Parent = frame
		textStroke(sub, Color3.fromRGB(40, 30, 60), 2)
		subtitle = sub
	end

	if opts.badge then
		local badge = Instance.new("TextLabel")
		badge.Name = "Badge"
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(0.08, 0.2)
		badge.Size = UDim2.fromScale(0.16, 0.36)
		badge.BackgroundColor3 = Color3.new(1, 1, 1)
		badge.Font = FONT
		badge.TextScaled = true
		badge.TextColor3 = bg:Lerp(Color3.new(0, 0, 0), 0.35)
		badge.Text = opts.badge
		badge.Parent = frame
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = badge
		corner(badge, 0.5)
	end

	if opts.corner then
		local ribbon = Instance.new("TextLabel")
		ribbon.Name = "Ribbon"
		ribbon.AnchorPoint = Vector2.new(1, 0)
		ribbon.Position = UDim2.fromScale(1.02, -0.06)
		ribbon.Size = UDim2.fromScale(0.26, 0.24)
		ribbon.BackgroundColor3 = Color3.fromRGB(255, 60, 90)
		ribbon.Rotation = 8
		ribbon.Font = FONT
		ribbon.TextScaled = true
		ribbon.TextColor3 = Color3.new(1, 1, 1)
		ribbon.Text = opts.corner or ""
		ribbon.Parent = frame
		corner(ribbon, 0.3)
		stroke(ribbon, Color3.new(1, 1, 1), 3)
	end

	gui.Parent = part
	return { frame = frame, title = title, subtitle = subtitle }
end

export type TagLine = {
	text: string,
	color: Color3?,
	weight: number?, -- 줄 높이 비율 (기본 1)
}

-- 여러 줄 머리 위 이름표 (크기는 스터드 단위라 멀어지면 작아짐)
function Gui.tag(
	adornee: BasePart,
	offsetY: number,
	maxDistance: number,
	lines: { TagLine },
	widthStuds: number?
): { TextLabel }
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	local total = 0
	for _, line in lines do
		total += line.weight or 1
	end
	local width = widthStuds or 6
	gui.Size = UDim2.fromScale(width, total * 0.75)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance
	gui.Adornee = adornee
	local labels: { TextLabel } = {}
	local y = 0
	for i, line in lines do
		local h = (line.weight or 1) / total
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, y)
		label.Size = UDim2.fromScale(1, h)
		label.Font = FONT
		label.TextScaled = true
		label.TextColor3 = line.color or Color3.new(1, 1, 1)
		label.Text = line.text
		label.Parent = gui
		textStroke(label, Color3.fromRGB(30, 20, 45), 2)
		table.insert(labels, label)
		y += h
	end
	gui.Parent = adornee
	return labels
end

return Gui
