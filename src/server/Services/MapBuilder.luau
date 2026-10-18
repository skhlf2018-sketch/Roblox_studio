--!strict
--[[
	MapBuilder — 임시 지형 (데이터 기반 블록 맵) + 맵 정보 색인

	- Workspace.Map 이 없으면 코드로 만듭니다: 15개 구역(좌우 번갈아 길 옆에 배치), 둥지 8개,
	  부모 동물 자리, 경비 집, 밤 벽, 베이스 7개(배달 패드·부화 슬롯·우리·러닝머신·퓨전·도감·트레일 자리), 스폰.
	- Workspace.Map 이 이미 있으면(선임이 스튜디오에서 만든 맵) 새로 만들지 않고 태그만 읽습니다.
	  → 선임은 shared/Tags.luau 의 태그와 Attribute 만 맞춰 주면 됩니다.

	구역 판정은 "Zone" 태그 파트의 위치·크기(축 정렬 직사각형, 회전 무시)로 합니다.
	좌표계: 베이스는 Z < 0, 길은 +Z 방향, 뒤 구역일수록 멀리.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Biomes = require(Shared.Data.Biomes)
local Format = require(Shared.Format)
local Tags = require(Shared.Tags)
local EggRules = require(Shared.EggRules)
local Gui = require(script.Parent.Parent.Util.Gui)

type Zone = EggRules.Zone

export type PlotParts = {
	index: number,
	floor: BasePart,
	spawn: BasePart?,
	deliveryPad: BasePart?,
	treadmill: BasePart?,
	pen: BasePart?,
	sign: BasePart?,
	incubatorSlots: { [number]: BasePart },
}

local MAP = Config.MAP

local MapBuilder = {}

local mapFolder: Folder? = nil
local dynamicFolders: { [string]: Folder } = {}
local zones: { [string]: Zone } = {}
local zoneParts: { [string]: BasePart } = {}
local nests: { [string]: { BasePart } } = {}
local guardSpawns: { [string]: BasePart } = {}
local nightWalls: { BasePart } = {}
local plots: { [number]: PlotParts } = {}
local plotSignLabels: { [number]: TextLabel } = {}

------------------------------------------------------------------
-- 만들기 도우미
------------------------------------------------------------------

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	parent: Instance,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
	shape: Enum.PartType?,
	tag: string?,
	attributes: { [string]: any }?,
}

local function makePart(spec: PartSpec): Part
	local p = Instance.new("Part")
	p.Name = spec.name
	p.Anchored = true
	p.Size = spec.size
	p.CFrame = spec.cframe
	p.Color = spec.color or Color3.fromRGB(200, 200, 200)
	p.Material = spec.material or Enum.Material.SmoothPlastic
	p.Transparency = spec.transparency or 0
	p.CanCollide = if spec.canCollide == nil then true else spec.canCollide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if spec.shape then
		p.Shape = spec.shape
	end
	if spec.attributes then
		for key, value in spec.attributes do
			p:SetAttribute(key, value)
		end
	end
	if spec.tag then
		CollectionService:AddTag(p, spec.tag)
	end
	p.Parent = spec.parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- 세운 원판(둥지) 만들기: Cylinder 는 X 축이 높이라 Z 축으로 90도 돌림
local function disc(name: string, center: Vector3, height: number, diameter: number, parent: Instance): PartSpec
	return {
		name = name,
		size = Vector3.new(height, diameter, diameter),
		cframe = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		parent = parent,
		shape = Enum.PartType.Cylinder,
	}
end

------------------------------------------------------------------
-- 구역
------------------------------------------------------------------

local GROUND_TOP = 0
local FLOOR_TOP = 0.2

local function zoneCenter(order: number): Vector3
	local side = if order % 2 == 1 then -1 else 1
	return Vector3.new(side * MAP.ZONE_SIDE_X, FLOOR_TOP, MAP.ZONE_FIRST_Z + (order - 1) * MAP.ZONE_STEP_Z)
end

local function buildZone(biome: Biomes.Biome, parent: Instance)
	local zoneFolder = folder(biome.id, parent)
	local center = zoneCenter(biome.order)
	local size = MAP.ZONE_SIZE
	local half = size / 2
	local color = rgb(biome.color)

	makePart({
		name = "Floor",
		size = Vector3.new(size, 1, size),
		cframe = CFrame.new(center.X, FLOOR_TOP - 0.5, center.Z),
		parent = zoneFolder,
		color = color,
		material = Enum.Material.Grass,
		tag = Tags.Zone,
		attributes = {
			BiomeId = biome.id,
			Order = biome.order,
			RecommendedSpeed = biome.recommendedSpeed,
		},
	})

	-- 입구 표지판 (길 쪽 가장자리)
	local towardRoad = if center.X < 0 then 1 else -1
	local signPos = Vector3.new(center.X + towardRoad * (half + 2), 8, center.Z)
	local sign = makePart({
		name = "Sign",
		size = Vector3.new(16, 8, 1),
		cframe = CFrame.lookAt(signPos, signPos + Vector3.new(towardRoad, 0, 0)),
		parent = zoneFolder,
		color = Color3.fromRGB(60, 45, 30),
		material = Enum.Material.Wood,
		tag = Tags.ZoneSign,
		attributes = { BiomeId = biome.id },
	})
	local newMark = if biome.isNew then " (NEW)" else ""
	local signText = string.format(
		"%d. %s%s\n%s\n추천 속도 %s",
		biome.order,
		biome.name,
		newMark,
		biome.nameEn,
		Format.number(biome.recommendedSpeed)
	)
	Gui.surface(sign, Enum.NormalId.Front, signText)

	-- 경비 집 (구역 중심)
	makePart({
		name = "GuardSpawn",
		size = Vector3.new(4, 0.2, 4),
		cframe = CFrame.new(center.X, FLOOR_TOP + 0.1, center.Z),
		parent = zoneFolder,
		transparency = 1,
		canCollide = false,
		tag = Tags.GuardSpawn,
		attributes = { BiomeId = biome.id },
	})

	-- 둥지 8개 + 부모 동물 자리
	for i = 1, biome.nests do
		local angle = (i - 1) / biome.nests * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local nestPos = Vector3.new(center.X, FLOOR_TOP + 0.5, center.Z) + dir * MAP.NEST_RING_RADIUS
		local spec = disc("Nest" .. i, nestPos, 1, 6, zoneFolder)
		spec.color = Color3.fromRGB(150, 110, 60)
		spec.material = Enum.Material.WoodPlanks
		spec.tag = Tags.Nest
		spec.attributes = { BiomeId = biome.id, NestIndex = i }
		makePart(spec)

		local spotPos = Vector3.new(center.X, FLOOR_TOP + 1.5, center.Z) + dir * (MAP.NEST_RING_RADIUS + 6)
		makePart({
			name = "ParentAnimal" .. i,
			size = Vector3.new(3, 3, 3),
			cframe = CFrame.lookAt(spotPos, Vector3.new(nestPos.X, spotPos.Y, nestPos.Z)),
			parent = zoneFolder,
			color = color:Lerp(Color3.new(0, 0, 0), 0.3),
			transparency = 0.5,
			canCollide = false,
			tag = Tags.ParentAnimalSpot,
			attributes = { BiomeId = biome.id, NestIndex = i },
		})
	end

	-- 밤 벽 4개 (낮에는 투명 + 통과)
	local h = MAP.NIGHT_WALL_HEIGHT
	local wallY = FLOOR_TOP + h / 2
	local walls = {
		{ Vector3.new(size + 2, h, 2), Vector3.new(center.X, wallY, center.Z + half + 1) },
		{ Vector3.new(size + 2, h, 2), Vector3.new(center.X, wallY, center.Z - half - 1) },
		{ Vector3.new(2, h, size + 2), Vector3.new(center.X + half + 1, wallY, center.Z) },
		{ Vector3.new(2, h, size + 2), Vector3.new(center.X - half - 1, wallY, center.Z) },
	}
	for i, w in walls do
		makePart({
			name = "NightWall" .. i,
			size = w[1],
			cframe = CFrame.new(w[2]),
			parent = zoneFolder,
			color = Color3.fromRGB(200, 40, 40),
			material = Enum.Material.ForceField,
			transparency = 1,
			canCollide = false,
			tag = Tags.NightWall,
			attributes = { BiomeId = biome.id, NightTransparency = 0.4 },
		})
	end
end

------------------------------------------------------------------
-- 베이스
------------------------------------------------------------------

local function plotCenter(index: number): Vector3
	return Vector3.new((index - (Config.PLOT_COUNT + 1) / 2) * MAP.PLOT_SPACING, FLOOR_TOP, MAP.PLOT_Z)
end

local function buildPlot(index: number, parent: Instance)
	local plotFolder = folder("Plot" .. index, parent)
	local c = plotCenter(index)
	local s = MAP.PLOT_SIZE
	local half = s / 2
	local attrs = { PlotIndex = index }

	makePart({
		name = "Floor",
		size = Vector3.new(s, 1, s),
		cframe = CFrame.new(c.X, FLOOR_TOP - 0.5, c.Z),
		parent = plotFolder,
		color = Color3.fromRGB(190, 190, 180),
		material = Enum.Material.Concrete,
		tag = Tags.Plot,
		attributes = { PlotIndex = index, OwnerUserId = 0 },
	})
	makePart({
		name = "Spawn",
		size = Vector3.new(6, 0.2, 6),
		cframe = CFrame.new(c.X, FLOOR_TOP + 0.1, c.Z + 22),
		parent = plotFolder,
		color = Color3.fromRGB(120, 200, 255),
		transparency = 0.5,
		canCollide = false,
		tag = Tags.PlotSpawn,
		attributes = attrs,
	})
	makePart({
		name = "DeliveryPad",
		size = Vector3.new(10, 0.3, 10),
		cframe = CFrame.new(c.X, FLOOR_TOP + 0.15, c.Z + 35),
		parent = plotFolder,
		color = Color3.fromRGB(80, 230, 120),
		material = Enum.Material.Neon,
		tag = Tags.DeliveryPad,
		attributes = attrs,
	})
	for slot = 1, Config.INCUBATOR_SLOTS do
		local x = c.X - (Config.INCUBATOR_SLOTS - 1) * 4.5 + (slot - 1) * 9
		makePart({
			name = "Incubator" .. slot,
			size = Vector3.new(5, 1, 5),
			cframe = CFrame.new(x, FLOOR_TOP + 0.5, c.Z + 5),
			parent = plotFolder,
			color = Color3.fromRGB(255, 240, 200),
			material = Enum.Material.SmoothPlastic,
			tag = Tags.IncubatorSlot,
			attributes = { PlotIndex = index, SlotIndex = slot },
		})
	end
	makePart({
		name = "Pen",
		size = Vector3.new(60, 0.2, 28),
		cframe = CFrame.new(c.X, FLOOR_TOP + 0.1, c.Z - 22),
		parent = plotFolder,
		color = Color3.fromRGB(150, 210, 120),
		material = Enum.Material.Grass,
		tag = Tags.PenArea,
		attributes = attrs,
	})
	makePart({
		name = "Treadmill",
		size = Vector3.new(8, 0.4, 12),
		cframe = CFrame.new(c.X + 33, FLOOR_TOP + 0.2, c.Z + 30),
		parent = plotFolder,
		color = Color3.fromRGB(40, 40, 40),
		material = Enum.Material.Rubber,
		tag = Tags.Treadmill,
		attributes = attrs,
	})
	makePart({
		name = "FusionMachine",
		size = Vector3.new(6, 4, 6),
		cframe = CFrame.new(c.X - 35, FLOOR_TOP + 2, c.Z + 30),
		parent = plotFolder,
		color = Color3.fromRGB(150, 90, 220),
		transparency = 0.3,
		tag = Tags.FusionMachine,
		attributes = attrs,
	})
	makePart({
		name = "IndexBoard",
		size = Vector3.new(12, 8, 1),
		cframe = CFrame.new(c.X - 30, FLOOR_TOP + 5, c.Z - half + 2),
		parent = plotFolder,
		color = Color3.fromRGB(70, 50, 30),
		tag = Tags.IndexBoard,
		attributes = attrs,
	})
	makePart({
		name = "TrailShop",
		size = Vector3.new(6, 4, 6),
		cframe = CFrame.new(c.X + 35, FLOOR_TOP + 2, c.Z - 38),
		parent = plotFolder,
		color = Color3.fromRGB(255, 180, 60),
		transparency = 0.3,
		tag = Tags.TrailShop,
		attributes = attrs,
	})
	local signPos = Vector3.new(c.X, FLOOR_TOP + 9, c.Z + half)
	makePart({
		name = "OwnerSign",
		size = Vector3.new(18, 4, 1),
		cframe = CFrame.lookAt(signPos, signPos + Vector3.new(0, 0, 1)),
		parent = plotFolder,
		color = Color3.fromRGB(40, 40, 60),
		tag = Tags.PlotSign,
		attributes = attrs,
	})
end

local function buildMap(): Folder
	local map = Instance.new("Folder")
	map.Name = "Map"

	makePart({
		name = "Ground",
		size = Vector3.new(1000, 2, 2400),
		cframe = CFrame.new(0, GROUND_TOP - 1, 900),
		parent = map,
		color = Color3.fromRGB(110, 160, 90),
		material = Enum.Material.Grass,
	})
	local roadStart = MAP.SPAWN_Z + 10
	local roadEnd = MAP.ZONE_FIRST_Z + (Biomes.count - 1) * MAP.ZONE_STEP_Z + MAP.ZONE_SIZE / 2
	makePart({
		name = "Road",
		size = Vector3.new(MAP.ROAD_WIDTH, 0.1, roadEnd - roadStart),
		cframe = CFrame.new(0, GROUND_TOP + 0.05, (roadStart + roadEnd) / 2),
		parent = map,
		color = Color3.fromRGB(120, 110, 100),
		material = Enum.Material.Slate,
	})

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "MainSpawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = CFrame.new(0, FLOOR_TOP - 0.3, MAP.SPAWN_Z)
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Color = Color3.fromRGB(255, 255, 255)
	CollectionService:AddTag(spawnLocation, Tags.SpawnLocation)
	spawnLocation.Parent = map

	local zonesFolder = folder("Zones", map)
	for _, biome in Biomes.list do
		buildZone(biome, zonesFolder)
	end
	local plotsFolder = folder("Plots", map)
	for i = 1, Config.PLOT_COUNT do
		buildPlot(i, plotsFolder)
	end

	map.Parent = Workspace
	return map
end

------------------------------------------------------------------
-- 색인 (태그 읽기)
------------------------------------------------------------------

local function taggedParts(tag: string): { BasePart }
	local result: { BasePart } = {}
	local map = mapFolder
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") and (map == nil or inst:IsDescendantOf(map)) then
			table.insert(result, inst)
		end
	end
	return result
end

local function stringAttr(inst: Instance, name: string): string?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "string" then v else nil
end

local function numberAttr(inst: Instance, name: string): number?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" then v else nil
end

local function indexMap()
	for _, p in taggedParts(Tags.Zone) do
		local biomeId = stringAttr(p, "BiomeId")
		if biomeId then
			zoneParts[biomeId] = p
			zones[biomeId] = {
				centerX = p.Position.X,
				centerZ = p.Position.Z,
				halfX = p.Size.X / 2,
				halfZ = p.Size.Z / 2,
			}
		end
	end
	for _, p in taggedParts(Tags.Nest) do
		local biomeId = stringAttr(p, "BiomeId")
		if biomeId then
			local list = nests[biomeId]
			if not list then
				list = {}
				nests[biomeId] = list
			end
			table.insert(list, p)
		end
	end
	for _, list in nests do
		table.sort(list, function(a: BasePart, b: BasePart): boolean
			return (numberAttr(a, "NestIndex") or 0) < (numberAttr(b, "NestIndex") or 0)
		end)
	end
	for _, p in taggedParts(Tags.GuardSpawn) do
		local biomeId = stringAttr(p, "BiomeId")
		if biomeId then
			guardSpawns[biomeId] = p
		end
	end
	nightWalls = taggedParts(Tags.NightWall)

	for _, p in taggedParts(Tags.Plot) do
		local index = numberAttr(p, "PlotIndex")
		if index then
			plots[index] = { index = index, floor = p, incubatorSlots = {} }
		end
	end
	local function attach(tag: string, apply: (PlotParts, BasePart) -> ())
		for _, p in taggedParts(tag) do
			local index = numberAttr(p, "PlotIndex")
			local plot = if index then plots[index] else nil
			if plot then
				apply(plot, p)
			end
		end
	end
	attach(Tags.PlotSpawn, function(plot, p)
		plot.spawn = p
	end)
	attach(Tags.DeliveryPad, function(plot, p)
		plot.deliveryPad = p
	end)
	attach(Tags.Treadmill, function(plot, p)
		plot.treadmill = p
	end)
	attach(Tags.PenArea, function(plot, p)
		plot.pen = p
	end)
	attach(Tags.PlotSign, function(plot, p)
		plot.sign = p
	end)
	attach(Tags.IncubatorSlot, function(plot, p)
		local slot = numberAttr(p, "SlotIndex")
		if slot then
			plot.incubatorSlots[slot] = p
		end
	end)

	for _, biome in Biomes.list do
		if not zones[biome.id] then
			warn("[MapBuilder] Zone 태그가 없는 구역: " .. biome.id)
		end
		if not nests[biome.id] or #nests[biome.id] == 0 then
			warn("[MapBuilder] 둥지가 없는 구역: " .. biome.id)
		end
	end
end

------------------------------------------------------------------
-- 공개 함수
------------------------------------------------------------------

function MapBuilder.start()
	local existing = Workspace:FindFirstChild("Map")
	if existing and existing:IsA("Folder") then
		mapFolder = existing
	else
		mapFolder = buildMap()
	end
	local map = mapFolder :: Folder
	for _, name in { "Eggs", "Guardians", "Traps", "Incubating" } do
		local f = map:FindFirstChild(name)
		if f and f:IsA("Folder") then
			dynamicFolders[name] = f
		else
			dynamicFolders[name] = folder(name, map)
		end
	end
	indexMap()
	MapBuilder.setNightWalls(false)
end

function MapBuilder.getFolder(name: string): Folder
	local f = dynamicFolders[name]
	assert(f, "MapBuilder: 동적 폴더 없음 " .. name)
	return f
end

function MapBuilder.getZone(biomeId: string): Zone?
	return zones[biomeId]
end

function MapBuilder.getZonePart(biomeId: string): BasePart?
	return zoneParts[biomeId]
end

function MapBuilder.getNests(biomeId: string): { BasePart }
	return nests[biomeId] or {}
end

function MapBuilder.getGuardSpawn(biomeId: string): BasePart?
	return guardSpawns[biomeId]
end

function MapBuilder.getPlot(index: number): PlotParts?
	return plots[index]
end

function MapBuilder.plotCount(): number
	local n = 0
	for index in plots do
		n = math.max(n, index)
	end
	return n
end

-- 이 위치가 어느 구역인지 (없으면 nil)
function MapBuilder.findBiomeAt(position: Vector3): string?
	for biomeId, zone in zones do
		if EggRules.isInsideZone(zone, position.X, position.Z) then
			return biomeId
		end
	end
	return nil
end

-- 안전 구역 = 아무 베이스 중심에서 SAFE_ZONE_RADIUS 안
function MapBuilder.isInSafeZone(position: Vector3): boolean
	for _, plot in plots do
		local c = plot.floor.Position
		if EggRules.isWithinRadius(c.X, c.Z, Config.SAFE_ZONE_RADIUS, position.X, position.Z) then
			return true
		end
	end
	return false
end

function MapBuilder.isInPlot(index: number, position: Vector3): boolean
	local plot = plots[index]
	if not plot then
		return false
	end
	local c = plot.floor.Position
	return EggRules.isWithinRadius(c.X, c.Z, Config.SAFE_ZONE_RADIUS, position.X, position.Z)
end

-- 바닥 높이 (아래로 레이캐스트, 캐릭터·알 제외)
function MapBuilder.groundY(position: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = table.clone(ignore)
	for _, name in { "Eggs", "Guardians", "Traps", "Incubating" } do
		local f = dynamicFolders[name]
		if f then
			table.insert(exclude, f)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local result = Workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -100, 0), params)
	if result then
		return result.Position.Y
	end
	return FLOOR_TOP
end

function MapBuilder.setNightWalls(on: boolean)
	for _, wall in nightWalls do
		local nightTransparency = numberAttr(wall, "NightTransparency") or 0.4
		wall.CanCollide = on
		wall.Transparency = if on then nightTransparency else 1
	end
end

function MapBuilder.setPlotOwner(index: number, player: Player?)
	local plot = plots[index]
	if not plot then
		return
	end
	plot.floor:SetAttribute("OwnerUserId", if player then player.UserId else 0)
	local sign = plot.sign
	if not sign then
		return
	end
	local label = plotSignLabels[index]
	if not label then
		label = Gui.surface(sign, Enum.NormalId.Front, "")
		plotSignLabels[index] = label
	end
	label.Text = if player then player.DisplayName .. "의 베이스" else "빈 베이스"
end

return MapBuilder
