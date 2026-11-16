--!strict
--[[
	MapBuilder — 송판 깨기 맵 (선임). 서버가 시작할 때 한 번 파트로 조립 (메시·외부 에셋 없음).
	  MapBuilder.start()            Workspace.Map 을 만듦 (두 번 불러도 한 번만)
	  MapBuilder.getTarget(id)      물건 모델 (태그 BreakTarget)
	  MapBuilder.getWorld(world)    월드 폴더 (Map/World1 …)
	  MapBuilder.partCounts()       { worlds = {n1, n2, n3}, total } — 파트 수 상한 검사용
	  MapBuilder.PART_BUDGET        { map = 6000, world = 2200, target = 15 }

	자리는 전부 shared/Data/MapLayout (수석 서버도 같은 숫자로 거리·매트 판정).
	월드 테마: 1 태권도장 마을 (나무 바닥 도장 · 마을 길 · 나무·집) / 2 지구 한 바퀴 (도시 빌딩 · 바다 · 산)
	          / 3 우주 (검은 바닥 + 별 · 물건은 떠 있는 받침대 위)
	물건 41개: Model "Target_<id>" (태그 BreakTarget, Attr TargetId·World), 모양은 Map/TargetLooks,
	  보이지 않는 맞히는 상자 "Hitbox"(PrimaryPart) + 위 글 "TargetInfo"(이름 · 💰 값 · 💪 필요한 힘)
	  + ClickDetector "Click" (모델 아무 곳이나 눌러도 됨 → 클라 BreakController 가 Hit(targetId)).
	  체력 막대·깨짐은 플레이어마다 다르므로 클라가 자기 화면에서만 그림.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
local Targets = require(Shared.Data.Targets)
local Format = require(Shared.Format)
local Tags = require(Shared.Tags)
local MapFolder = script.Parent.Parent.Map
local Build = require(MapFolder.Build)
local Dojo = require(MapFolder.Dojo)
local TargetLooks = require(MapFolder.TargetLooks)

local MapBuilder = {}

MapBuilder.PART_BUDGET = {
	map = 6000, -- Workspace.Map 전체
	world = 2200, -- 월드 하나 (로비 + 물건 + 장식)
	target = 15, -- 물건 모델 하나 (모양 + 맞히는 상자 + 받침대)
}

local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local PA = Tags.PartAttributes

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type WorldTheme = {
	dojo: Dojo.Theme,
	ground: Color3,
	groundMaterial: Enum.Material,
	road: Color3,
	roadMaterial: Enum.Material,
	edge: Color3,
	edgeMaterial: Enum.Material,
}

MapBuilder.THEMES = {
	{
		dojo = {
			floor = c(205, 160, 105),
			floorMaterial = M.WoodPlanks,
			wall = c(245, 235, 215),
			wallMaterial = M.Plaster,
			trim = c(140, 50, 40),
			mat = { c(220, 60, 60), c(50, 110, 220) },
			accent = c(230, 70, 60),
			name = "🥋 태권도장",
		},
		ground = c(110, 190, 90),
		groundMaterial = M.Grass,
		road = c(225, 205, 160),
		roadMaterial = M.Sand,
		edge = c(150, 110, 70),
		edgeMaterial = M.Wood,
	},
	{
		dojo = {
			floor = c(200, 215, 230),
			floorMaterial = M.Marble,
			wall = c(235, 240, 248),
			wallMaterial = M.Concrete,
			trim = c(40, 90, 170),
			mat = { c(50, 150, 230), c(240, 170, 40) },
			accent = c(50, 140, 230),
			name = "🌏 지구 도장",
		},
		ground = c(95, 175, 85),
		groundMaterial = M.Grass,
		road = c(70, 72, 80),
		roadMaterial = M.Asphalt,
		edge = c(230, 230, 230),
		edgeMaterial = M.Concrete,
	},
	{
		dojo = {
			floor = c(30, 32, 48),
			floorMaterial = M.Metal,
			wall = c(50, 52, 80),
			wallMaterial = M.Metal,
			trim = c(150, 100, 255),
			mat = { c(140, 80, 230), c(60, 200, 230) },
			accent = c(170, 110, 255),
			name = "🚀 우주 도장",
		},
		ground = c(14, 14, 22),
		groundMaterial = M.Slate,
		road = c(40, 40, 70),
		roadMaterial = M.Glass,
		edge = c(120, 200, 255),
		edgeMaterial = M.Neon,
	},
} :: { WorldTheme }

local mapFolder: Folder? = nil
local worldFolders: { [number]: Folder } = {}
local targetModels: { [string]: Model } = {}

local function v3(p: { x: number, y: number, z: number }, dy: number?): Vector3
	return Vector3.new(p.x, p.y + (dy or 0), p.z)
end

------------------------------------------------------------------
-- 물건 줄 바닥 · 길
------------------------------------------------------------------

-- 큰 판을 2,048 이하 조각으로 (z 방향)
local function longFloor(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	y: number,
	h: number,
	color: Color3,
	mat: Enum.Material,
	opts: Build.Opts?
)
	local length = z1 - z0
	local pieces = math.max(1, math.ceil(length / 1000))
	local each = length / pieces
	for i = 1, pieces do
		local o: Build.Opts = if opts then table.clone(opts) else {}
		o.collide = true
		o.name = name
		Build.part(
			parent,
			"Block",
			Vector3.new(x1 - x0, h, each),
			CFrame.new((x0 + x1) / 2, y, z0 + (i - 0.5) * each),
			color,
			mat,
			o
		)
	end
end

local function ground(world: number, parent: Instance, theme: WorldTheme)
	local area = MapLayout.targetArea(world)
	local lobby = MapLayout.lobbyRect(world)
	local ox = MapLayout.worldOrigin(world).x
	local x0 = math.min(area.x0, lobby.x0) - 40
	local x1 = math.max(area.x1, lobby.x1) + 40
	-- 밖 땅 (로비 둘레 + 물건 줄)
	longFloor(parent, "Ground", x0, x1, lobby.z0 - 40, area.z1 + 30, -1.5, 2, theme.ground, theme.groundMaterial)
	-- 가운데 길
	local rh = MapLayout.ROAD_HALF
	longFloor(parent, "Road", ox - rh, ox + rh, lobby.z1, area.z1, -0.4, 1, theme.road, theme.roadMaterial, {
		transparency = if world == 3 then 0.2 else 0,
	})
	-- 길 가장자리 줄 2개
	for _, sx in { -1, 1 } do
		longFloor(
			parent,
			"RoadEdge",
			ox + sx * rh - 0.4,
			ox + sx * rh + 0.4,
			lobby.z1,
			area.z1,
			0.1,
			0.4,
			theme.edge,
			theme.edgeMaterial
		)
	end
	-- 길 끝 표지판
	local endPos = Vector3.new(ox, 0, area.z1 - 6)
	local post = Build.part(
		parent,
		"Block",
		Vector3.new(12, 3, 0.6),
		CFrame.lookAt(endPos + Vector3.new(0, 5, 0), endPos + Vector3.new(0, 5, -1)),
		c(40, 44, 70),
		M.SmoothPlastic,
		{
			collide = true,
			query = true,
			name = "RoadEndSign",
		}
	)
	local frame = Build.surfaceSign(post, c(40, 44, 70), 30)
	Build.text(
		frame,
		"Title",
		UDim2.fromScale(0.04, 0.1),
		UDim2.fromScale(0.92, 0.8),
		if world < 3 then "다음 월드는 도장 문으로!" else "🌌 우주 끝!",
		WHITE
	)
end

------------------------------------------------------------------
-- 장식 (월드 테마)
------------------------------------------------------------------

local function rng(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

-- 물건 줄 밖 장식 자리 (길·물건과 안 겹치게 바깥 가장자리)
local function outerSpots(world: number, count: number, margin: number): { Vector3 }
	local area = MapLayout.targetArea(world)
	local list: { Vector3 } = {}
	local rand = rng(world * 977)
	for i = 1, count do
		local side = if i % 2 == 0 then 1 else -1
		local x = if side < 0 then area.x0 - margin - rand() * 25 else area.x1 + margin + rand() * 25
		local z = area.z0 + 10 + (area.z1 - area.z0 - 20) * (i - 1) / math.max(1, count - 1)
		table.insert(list, Vector3.new(x, 0, z))
	end
	return list
end

local function decorVillage(parent: Instance)
	local folder = Build.folder("Decor", parent)
	local rand = rng(11)
	for i, p in outerSpots(1, 22, 6) do
		if i % 4 == 0 then
			-- 작은 집 (몸 + 지붕 쐐기 2개)
			local wall = c(240, 225, 200)
			local roof = if i % 8 == 0 then c(60, 110, 200) else c(200, 70, 60)
			Build.part(
				folder,
				"Block",
				Vector3.new(10, 7, 9),
				CFrame.new(p + Vector3.new(0, 3.5, 0)),
				wall,
				M.Plaster,
				{ collide = true }
			)
			Build.part(
				folder,
				"Wedge",
				Vector3.new(10.6, 3.5, 5),
				CFrame.new(p + Vector3.new(0, 8.75, -2.5)),
				roof,
				M.Slate
			)
			Build.part(
				folder,
				"Wedge",
				Vector3.new(10.6, 3.5, 5),
				CFrame.new(p + Vector3.new(0, 8.75, 2.5)) * CFrame.Angles(0, math.pi, 0),
				roof,
				M.Slate
			)
		else
			local h = 6 + rand() * 4
			Build.part(
				folder,
				"VCyl",
				Vector3.new(1.4, h, 0),
				CFrame.new(p + Vector3.new(0, h / 2, 0)),
				c(120, 80, 45),
				M.Wood,
				{ collide = true }
			)
			Build.part(
				folder,
				"Ball",
				Vector3.one * (5 + rand() * 2),
				CFrame.new(p + Vector3.new(0, h + 1.5, 0)),
				c(70, 170, 70),
				M.Grass
			)
			Build.part(
				folder,
				"Ball",
				Vector3.one * (3.5 + rand()),
				CFrame.new(p + Vector3.new(1.5, h + 3.4, 0.5)),
				c(90, 190, 80),
				M.Grass
			)
		end
	end
	return folder
end

local function decorEarth(parent: Instance)
	local folder = Build.folder("Decor", parent)
	local area = MapLayout.targetArea(2)
	local rand = rng(23)
	-- 왼쪽: 도시 빌딩
	for i, p in outerSpots(2, 24, 8) do
		if p.X < MapLayout.worldOrigin(2).x then
			local h = 20 + rand() * 50
			local w = 8 + rand() * 6
			local tint = c(150, 175, 205):Lerp(c(220, 220, 230), rand())
			Build.part(
				folder,
				"Block",
				Vector3.new(w, h, w),
				CFrame.new(p + Vector3.new(-10, h / 2, 0)),
				tint,
				M.Glass,
				{ collide = true, reflectance = 0.1 }
			)
			if i % 3 == 0 then
				Build.part(
					folder,
					"Block",
					Vector3.new(w * 0.5, 4, w * 0.5),
					CFrame.new(p + Vector3.new(-10, h + 2, 0)),
					c(200, 200, 210),
					M.Metal
				)
			end
		end
	end
	-- 오른쪽: 바다 + 물결
	local seaX = area.x1 + 70
	Build.part(
		folder,
		"Block",
		Vector3.new(100, 1, area.z1 - area.z0 + 60),
		CFrame.new(seaX, -0.6, (area.z0 + area.z1) / 2),
		c(50, 130, 220),
		M.Glass,
		{
			collide = true,
			transparency = 0.15,
			name = "Sea",
		}
	)
	for i = 1, 10 do
		local z = area.z0 + (area.z1 - area.z0) * i / 11
		Build.part(
			folder,
			"Block",
			Vector3.new(14, 0.3, 1),
			CFrame.new(seaX - 20 + rand() * 40, 0, z),
			WHITE,
			M.SmoothPlastic,
			{ transparency = 0.3 }
		)
	end
	-- 뒤: 산 (쐐기 2개씩) 4개
	for i = 1, 4 do
		local x = MapLayout.worldOrigin(2).x + (i - 2.5) * 70
		local z = area.z1 + 60
		local h = 40 + i * 8
		Build.part(
			folder,
			"Wedge",
			Vector3.new(60, h, 30),
			CFrame.new(x, h / 2, z - 15) * CFrame.Angles(0, math.pi, 0),
			c(120, 125, 120),
			M.Slate
		)
		Build.part(folder, "Wedge", Vector3.new(60, h, 30), CFrame.new(x, h / 2, z + 15), c(110, 115, 110), M.Slate)
	end
	return folder
end

local function decorSpace(parent: Instance)
	local folder = Build.folder("Decor", parent)
	local area = MapLayout.targetArea(3)
	local lobby = MapLayout.lobbyRect(3)
	local rand = rng(37)
	local x0, x1 = math.min(area.x0, lobby.x0) - 40, math.max(area.x1, lobby.x1) + 40
	local z0, z1 = lobby.z0 - 40, area.z1 + 30
	-- 바닥 별 (작게 빛나는 점) + 하늘 별
	for i = 1, 140 do
		local x = x0 + rand() * (x1 - x0)
		local z = z0 + rand() * (z1 - z0)
		local inRoad = math.abs(x - MapLayout.worldOrigin(3).x) < MapLayout.ROAD_HALF + 2
		local sky = i % 2 == 0
		if not (inRoad and not sky) then
			local y = if sky then 60 + rand() * 120 else -0.45
			local size = if sky then 0.8 + rand() * 1.6 else 0.4 + rand() * 0.5
			local tint = c(255, 255, 255):Lerp(c(170, 200, 255), rand())
			Build.part(folder, "Ball", Vector3.one * size, CFrame.new(x, y, z), tint, M.Neon)
		end
	end
	-- 멀리 떠 있는 큰 행성 2개 (장식, 물건 아님)
	Build.part(
		folder,
		"Ball",
		Vector3.one * 80,
		CFrame.new(x0 - 80, 90, (z0 + z1) / 2),
		c(90, 60, 170),
		M.SmoothPlastic
	)
	Build.part(
		folder,
		"VCyl",
		Vector3.new(150, 1, 0),
		CFrame.new(x0 - 80, 90, (z0 + z1) / 2) * CFrame.Angles(math.rad(20), 0, 0),
		c(200, 170, 255),
		M.Neon,
		{
			transparency = 0.5,
		}
	)
	Build.part(folder, "Ball", Vector3.one * 50, CFrame.new(x1 + 70, 120, z1 - 60), c(255, 140, 90), M.SmoothPlastic)
	return folder
end

------------------------------------------------------------------
-- 물건 41개
------------------------------------------------------------------

local function infoText(target: Targets.Target): (string, string)
	return "💰 " .. Format.number(target.reward), "💪 필요한 힘 " .. Format.number(target.minPower)
end

local function buildTarget(target: Targets.Target, parent: Instance): Model?
	local pos = MapLayout.targetPosition(target.id)
	if not pos then
		warn("[MapBuilder] 자리가 없는 물건: " .. target.id)
		return nil
	end
	local r = MapLayout.targetRadius(target.id)
	local model = Build.model("Target_" .. target.id, parent)
	local base = v3(pos)
	local road = MapLayout.roadPoint(target.id)
	local toward = if road then Vector3.new(road.x, base.Y, road.z) else base + Vector3.new(0, 0, -1)
	local baseCf = CFrame.lookAt(base, toward)
	if target.world == 3 then
		-- 떠 있는 받침대 (바닥 위 2 스터드, 아래 보라 빛)
		local top = MapLayout.PEDESTAL_TOP
		Build.part(
			model,
			"VCyl",
			Vector3.new(r * 2, 1, 0),
			CFrame.new(base.X, top - 0.5, base.Z),
			c(70, 70, 95),
			M.Slate,
			{
				collide = true,
				query = true,
				name = "Pedestal",
			}
		)
		Build.part(
			model,
			"VCyl",
			Vector3.new(r * 2 + 0.8, 0.3, 0),
			CFrame.new(base.X, top - 1.1, base.Z),
			c(170, 110, 255),
			M.Neon,
			{
				query = true,
				name = "PedestalGlow",
				transparency = 0.2,
			}
		)
	end
	local height = TargetLooks.build(target.id, model, baseCf, r)
	local hitbox = Build.part(
		model,
		"Block",
		Vector3.new(r * 2 + 1, height + 1, r * 2 + 1),
		baseCf * CFrame.new(0, (height + 1) / 2, 0),
		WHITE,
		M.SmoothPlastic,
		{ collide = false, query = true, transparency = 1, name = "Hitbox", shadow = false }
	)
	model.PrimaryPart = hitbox
	model:SetAttribute(PA.TargetId, target.id)
	model:SetAttribute(PA.World, target.world)
	model:SetAttribute("Height", height)
	model:SetAttribute("Radius", r)
	-- 머리 위 글: 이름 / 값 / 필요한 힘 (멀리서도 보이게 크기는 화면 픽셀 고정)
	local gui = Build.billboard(hitbox, "TargetInfo", UDim2.fromOffset(230, 96), (height + 1) / 2 + 3.5, 90 + r * 4)
	local frame = Instance.new("Frame")
	frame.Name = "Box"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local reward, need = infoText(target)
	Build.text(frame, "Name", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.4), target.name, WHITE)
	Build.text(frame, "Reward", UDim2.fromScale(0, 0.4), UDim2.fromScale(1, 0.3), reward, c(255, 215, 60))
	Build.text(frame, "Need", UDim2.fromScale(0, 0.7), UDim2.fromScale(1, 0.3), need, c(255, 140, 140))
	Build.click(model, "Click", MapLayout.targetReach(target.id) + 60)
	CollectionService:AddTag(model, Tags.BreakTarget)
	targetModels[target.id] = model
	return model
end

------------------------------------------------------------------
-- 월드 · 맵
------------------------------------------------------------------

local function buildWorld(world: number, parent: Instance): Folder
	local theme = MapBuilder.THEMES[world]
	local folder = Build.folder("World" .. tostring(world), parent)
	folder:SetAttribute(PA.World, world)
	Dojo.build(world, folder, theme.dojo)
	ground(world, folder, theme)
	local targets = Build.folder("Targets", folder)
	for _, target in Targets.byWorld(world) do
		buildTarget(target, targets)
	end
	if world == 1 then
		decorVillage(folder)
	elseif world == 2 then
		decorEarth(folder)
	else
		decorSpace(folder)
	end
	worldFolders[world] = folder
	return folder
end

local function buildMap(): Folder
	local map = Instance.new("Folder")
	map.Name = "Map"
	for world = 1, MapLayout.WORLD_COUNT do
		buildWorld(world, map)
	end
	map.Parent = Workspace
	local counts = MapBuilder.partCounts()
	if counts.total > MapBuilder.PART_BUDGET.map then
		warn(
			string.format(
				"[MapBuilder] 맵 파트 %d 개 — 상한 %d 초과",
				counts.total,
				MapBuilder.PART_BUDGET.map
			)
		)
	end
	return map
end

function MapBuilder.partCounts(): { worlds: { number }, total: number }
	local worlds: { number } = {}
	local total = 0
	for world = 1, MapLayout.WORLD_COUNT do
		local f = worldFolders[world]
		local n = if f then Build.countParts(f) else 0
		worlds[world] = n
		total += n
	end
	return { worlds = worlds, total = total }
end

function MapBuilder.start()
	if mapFolder then
		return
	end
	mapFolder = buildMap()
end

function MapBuilder.getTarget(id: string): Model?
	return targetModels[id]
end

function MapBuilder.getWorld(world: number): Folder?
	return worldFolders[world]
end

function MapBuilder.getMap(): Folder?
	return mapFolder
end

return MapBuilder
