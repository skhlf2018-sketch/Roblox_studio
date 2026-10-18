--!strict
--[[
	Landmarks — 태그 붙은 특수 장소 찾기 + "근처인가" 서버 검사 + 맵에 없을 때 임시 파트 만들기

	- 퓨전 머신(FusionMachine), 사쿠라 인큐베이터, 제단, 비밀 통로, 퀘스트 문 같은 "가서 쓰는" 물건은
	  전부 서버가 플레이어 HumanoidRootPart 와 파트 사이 거리를 직접 재서 확인합니다 (클라 말은 안 믿음).
	- 거리 = 파트 상자 표면까지의 거리 (큰 모델도 공정하게)
	- 선임이 Workspace.Map 에 같은 태그·Attribute 로 파트를 두면 그걸 씀.
	  없으면 ensure() 가 Workspace.Map.Specials 에 단순한 임시 파트를 만들어 둠 (나중에 진짜 모델로 바꾸면 됨).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Character = require(script.Parent.Character)
local Gui = require(script.Parent.Gui)

local Landmarks = {}

local specialsFolder: Folder? = nil

function Landmarks.folder(): Folder
	local existing = specialsFolder
	if existing and existing.Parent ~= nil then
		return existing
	end
	local map = Workspace:FindFirstChild("Map")
	local parent: Instance = if map then map else Workspace
	local found = parent:FindFirstChild("Specials")
	if found and found:IsA("Folder") then
		specialsFolder = found
		return found
	end
	local f = Instance.new("Folder")
	f.Name = "Specials"
	f.Parent = parent
	specialsFolder = f
	return f
end

-- Workspace 안의 태그 붙은 BasePart (모델에 태그를 붙였으면 PrimaryPart 또는 첫 BasePart)
function Landmarks.tagged(tag: string): { BasePart }
	local result: { BasePart } = {}
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsDescendantOf(Workspace) then
			if inst:IsA("BasePart") then
				table.insert(result, inst)
			elseif inst:IsA("Model") then
				local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
				if part then
					table.insert(result, part)
				end
			end
		end
	end
	return result
end

local function attrOf(part: BasePart, name: string): any
	local value = part:GetAttribute(name)
	if value == nil and part.Parent and part.Parent:IsA("Model") then
		value = part.Parent:GetAttribute(name)
	end
	return value
end

-- 태그 + (선택) Attribute 값이 맞는 파트들
function Landmarks.find(tag: string, attrName: string?, attrValue: any?): { BasePart }
	local result: { BasePart } = {}
	for _, part in Landmarks.tagged(tag) do
		if attrName == nil or attrOf(part, attrName) == attrValue then
			table.insert(result, part)
		end
	end
	return result
end

-- 베이스 물건 (PlotIndex Attribute)
function Landmarks.plotPart(tag: string, plotIndex: number): BasePart?
	if plotIndex <= 0 then
		return nil
	end
	return Landmarks.find(tag, "PlotIndex", plotIndex)[1]
end

-- 점 → 파트 상자 표면까지 거리 (안에 있으면 0)
function Landmarks.distanceToPart(part: BasePart, position: Vector3): number
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	return (localPos - clamped).Magnitude
end

-- 살아 있는 플레이어가 파트 표면에서 radius 안에 있나
function Landmarks.isPlayerNear(player: Player, part: BasePart?, radius: number): boolean
	if not part or not Character.isAlive(player) then
		return false
	end
	local root = Character.getRoot(player)
	return root ~= nil and Landmarks.distanceToPart(part, root.Position) <= radius
end

-- parts 중 플레이어와 가장 가까운 것 (radius 안에 있는 것만)
function Landmarks.nearest(player: Player, parts: { BasePart }, radius: number): BasePart?
	local root = Character.getRoot(player)
	if not root or not Character.isAlive(player) then
		return nil
	end
	local best: BasePart? = nil
	local bestDistance = radius
	for _, part in parts do
		local d = Landmarks.distanceToPart(part, root.Position)
		if d <= bestDistance then
			best, bestDistance = part, d
		end
	end
	return best
end

export type PlaceholderSpec = {
	tag: string,
	name: string,
	label: string,
	position: Vector3,
	size: Vector3,
	color: Color3,
	attributes: { [string]: any }?,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
}

-- 임시 파트 하나 만들기 (태그·Attribute·이름표 포함)
function Landmarks.placeholder(spec: PlaceholderSpec): BasePart
	local part = Instance.new("Part")
	part.Name = spec.name
	part.Anchored = true
	part.Size = spec.size
	part.CFrame = CFrame.new(spec.position)
	part.Color = spec.color
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Transparency = spec.transparency or 0
	part.CanCollide = if spec.canCollide == nil then true else spec.canCollide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("Placeholder", true)
	if spec.attributes then
		for key, value in spec.attributes do
			part:SetAttribute(key, value)
		end
	end
	CollectionService:AddTag(part, spec.tag)
	part.Parent = Landmarks.folder()
	Gui.billboard(part, spec.label, spec.size.Y / 2 + 2, 90)
	return part
end

-- 태그(+Attribute) 파트가 맵에 하나도 없으면 임시 파트를 만들고, 있는 파트 목록을 돌려줌
function Landmarks.ensure(spec: PlaceholderSpec, attrName: string?, attrValue: any?): { BasePart }
	local existing = Landmarks.find(spec.tag, attrName, attrValue)
	if #existing > 0 then
		return existing
	end
	return { Landmarks.placeholder(spec) }
end

return Landmarks
