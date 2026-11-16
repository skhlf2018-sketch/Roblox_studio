--!strict
--[[
	Dojo — 월드마다 로비(도장) 만들기 (선임). 자리는 전부 shared/Data/MapLayout.
	  Dojo.build(world, parent, theme) → Folder "Lobby"
	만드는 것 (태그는 shared/Tags, 전부 Model 에 태그 + Attr World + ClickDetector "Click"):
	  WorldSpawn (월드 1 은 진짜 SpawnLocation) · TrainMat 6칸 (각 매트 파트에 태그 — 위에 서면 들기)
	  · DumbbellShop (카운터 + 아령 20개 진열 + 간판) · BeltBoard (12개 띠 색·이름 판 — 클라가 내 띠를 반짝이게)
	  · ExamPad (단상 + 송판 10장 거치대 Board_1..10) · DuelArena (내 쪽 Mine_1..15 · 시험관 쪽 Theirs_1..15 + 시험관 NPC)
	  · WorldDoor (다른 월드 문 2개, Attr TargetWorld. 자물쇠 "Lock" 은 클라가 내 열린 월드에 맞춰 보이기/숨기기)
	표지판은 스폰·매트 위를 가리지 않게 벽 쪽에 (smoke_visuals 가 검사).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
local Belts = require(Shared.Data.Belts)
local Worlds = require(Shared.Data.Worlds)
local Dumbbells = require(Shared.Data.Dumbbells)
local Format = require(Shared.Format)
local Tags = require(Shared.Tags)
local Build = require(script.Parent.Build)

local Dojo = {}

export type Theme = {
	floor: Color3,
	floorMaterial: Enum.Material,
	wall: Color3,
	wallMaterial: Enum.Material,
	trim: Color3,
	mat: { Color3 },
	accent: Color3,
	name: string,
}

local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(12, 14, 26)
local WALL_H = 9
local PA = Tags.PartAttributes

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function v3(p: { x: number, y: number, z: number }, dy: number?): Vector3
	return Vector3.new(p.x, p.y + (dy or 0), p.z)
end

local function dirOf(yaw: number): Vector3
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

-- 앞(-Z, SurfaceGui Front)이 dir 를 보는 CFrame
local function facing(pos: Vector3, dir: Vector3): CFrame
	return CFrame.lookAt(pos, pos + dir)
end

local function tagModel(model: Model, tag: string, world: number, primary: BasePart?)
	model:SetAttribute(PA.World, world)
	if primary then
		model.PrimaryPart = primary
	end
	CollectionService:AddTag(model, tag)
end

-- 서 있는 표지판 (판 + 글). 반환 판
local function sign(
	parent: Instance,
	cf: CFrame,
	w: number,
	h: number,
	title: string,
	sub: string?,
	color: Color3,
	collide: boolean?
): Part
	local board = Build.part(parent, "Block", Vector3.new(w, h, 0.6), cf, color, M.SmoothPlastic, {
		collide = collide == true,
		query = true,
		name = "SignBoard",
	})
	local frame = Build.surfaceSign(board, color, 30)
	Build.text(
		frame,
		"Title",
		UDim2.fromScale(0.04, 0.06),
		UDim2.fromScale(0.92, if sub then 0.5 else 0.86),
		title,
		WHITE
	)
	if sub then
		Build.text(frame, "Sub", UDim2.fromScale(0.06, 0.58), UDim2.fromScale(0.88, 0.34), sub, c(255, 235, 120))
	end
	return board
end

------------------------------------------------------------------
-- 바닥 · 벽 · 정문
------------------------------------------------------------------

local function shell(world: number, parent: Instance, theme: Theme)
	local rect = MapLayout.lobbyRect(world)
	local cx = (rect.x0 + rect.x1) / 2
	local w = rect.x1 - rect.x0
	local d = rect.z1 - rect.z0
	Build.solid(parent, "DojoFloor", Vector3.new(w, 1, d), CFrame.new(cx, -0.5, 0), theme.floor, theme.floorMaterial)
	-- 가운데 통로 (스폰 → 정문) 옅은 줄
	Build.part(parent, "Block", Vector3.new(12, 0.05, d - 4), CFrame.new(cx, 0.03, 0), theme.trim, M.SmoothPlastic, {
		transparency = 0.5,
		name = "Aisle",
	})
	local wy = WALL_H / 2
	-- 왼쪽·오른쪽 벽
	Build.solid(
		parent,
		"WallL",
		Vector3.new(2, WALL_H, d),
		CFrame.new(rect.x0 - 1, wy, 0),
		theme.wall,
		theme.wallMaterial
	)
	Build.solid(
		parent,
		"WallR",
		Vector3.new(2, WALL_H, d),
		CFrame.new(rect.x1 + 1, wy, 0),
		theme.wall,
		theme.wallMaterial
	)
	-- 뒤 벽 (문 자리 두 곳은 문틀이 막음)
	Build.solid(
		parent,
		"WallB",
		Vector3.new(w + 4, WALL_H, 2),
		CFrame.new(cx, wy, rect.z0 - 1),
		theme.wall,
		theme.wallMaterial
	)
	-- 앞 벽: 가운데 정문 (x -10..10) 비움
	local gate = 10
	local side = (w - gate * 2) / 2
	Build.solid(
		parent,
		"WallF1",
		Vector3.new(side + 2, WALL_H, 2),
		CFrame.new(rect.x0 + side / 2 - 1, wy, rect.z1 + 1),
		theme.wall,
		theme.wallMaterial
	)
	Build.solid(
		parent,
		"WallF2",
		Vector3.new(side + 2, WALL_H, 2),
		CFrame.new(rect.x1 - side / 2 + 1, wy, rect.z1 + 1),
		theme.wall,
		theme.wallMaterial
	)
	-- 벽 위 띠 장식 (4면)
	for _, s in { { rect.x0 - 1, 0, 2.4, d }, { rect.x1 + 1, 0, 2.4, d }, { cx, rect.z0 - 1, w + 4, 2.4 } } do
		Build.part(parent, "Block", Vector3.new(s[3], 0.8, s[4]), CFrame.new(s[1], WALL_H + 0.4, s[2]), theme.trim)
	end
	-- 모서리 기둥 4개 + 등불
	for _, p in { { rect.x0, rect.z0 }, { rect.x1, rect.z0 }, { rect.x0, rect.z1 }, { rect.x1, rect.z1 } } do
		Build.solid(
			parent,
			"Pillar",
			Vector3.new(3.5, WALL_H + 3, 3.5),
			CFrame.new(p[1], (WALL_H + 3) / 2, p[2]),
			theme.trim,
			M.Wood
		)
		local lamp = Build.part(
			parent,
			"Ball",
			Vector3.one * 2.2,
			CFrame.new(p[1], WALL_H + 4.2, p[2]),
			c(255, 220, 140),
			M.Neon
		)
		Build.light(lamp, c(255, 220, 160), 30, 1.2)
	end
	-- 정문 기둥 2개 + 위 간판 (도장 이름)
	for _, sx in { -1, 1 } do
		Build.solid(
			parent,
			"GatePost",
			Vector3.new(2.5, 16, 2.5),
			CFrame.new(cx + sx * (gate + 1.2), 8, rect.z1 + 1),
			theme.trim,
			M.Wood
		)
	end
	local gateSign = sign(
		parent,
		facing(Vector3.new(cx, 15, rect.z1 + 1.2), Vector3.new(0, 0, -1)),
		gate * 2 + 5,
		4,
		theme.name,
		"물건 깨러 가요 →",
		theme.accent
	)
	gateSign.Name = "GateSign"
	-- 밖에서 보는 쪽 글 (뒷면)
	local back = sign(
		parent,
		facing(Vector3.new(cx, 15, rect.z1 + 1.6), Vector3.new(0, 0, 1)),
		gate * 2 + 5,
		4,
		theme.name,
		"← 도장 (아령·띠·심사)",
		theme.accent
	)
	back.Name = "GateSignBack"
end

------------------------------------------------------------------
-- 스폰 · 수련 매트
------------------------------------------------------------------

local function spawnPad(world: number, parent: Instance, theme: Theme)
	local s = MapLayout.spawn(world)
	local pos = v3(s, 0.25)
	local pad: BasePart
	if world == 1 then
		local sp = Instance.new("SpawnLocation")
		sp.Name = "WorldSpawn"
		sp.Anchored = true
		sp.Size = Vector3.new(s.sizeX, 0.5, s.sizeZ)
		sp.CFrame = CFrame.new(pos)
		sp.Color = theme.accent
		sp.Material = M.SmoothPlastic
		sp.Neutral = true
		sp.Duration = 0
		sp.TopSurface = Enum.SurfaceType.Smooth
		sp.Parent = parent
		pad = sp
	else
		pad = Build.solid(parent, "WorldSpawn", Vector3.new(s.sizeX, 0.5, s.sizeZ), CFrame.new(pos), theme.accent)
	end
	pad:SetAttribute(PA.World, world)
	CollectionService:AddTag(pad, Tags.WorldSpawn)
end

-- 작은 아령 (봉 + 원판 2개)
local function dumbbell(parent: Instance, cf: CFrame, len: number, d: number, color: Color3)
	Build.part(parent, "HCyl", Vector3.new(len, d * 0.25, d * 0.25), cf, c(190, 190, 200), M.Metal, { query = true })
	Build.part(
		parent,
		"HCyl",
		Vector3.new(len * 0.22, d, d),
		cf * CFrame.new(-len * 0.4, 0, 0),
		color,
		M.Metal,
		{ query = true }
	)
	Build.part(
		parent,
		"HCyl",
		Vector3.new(len * 0.22, d, d),
		cf * CFrame.new(len * 0.4, 0, 0),
		color,
		M.Metal,
		{ query = true }
	)
end

local function trainMats(world: number, parent: Instance, theme: Theme)
	local folder = Build.folder("TrainMats", parent)
	for i, m in MapLayout.trainMats(world) do
		local color = theme.mat[(i - 1) % #theme.mat + 1]
		local mat = Build.solid(
			folder,
			"TrainMat",
			Vector3.new(m.sizeX, MapLayout.MAT_HEIGHT, m.sizeZ),
			CFrame.new(m.x, MapLayout.MAT_HEIGHT / 2, m.z),
			color,
			M.Fabric,
			{ attributes = { [PA.World] = world, MatIndex = i } }
		)
		CollectionService:AddTag(mat, Tags.TrainMat)
		-- 테두리 (흰 줄)
		Build.part(folder, "Block", Vector3.new(m.sizeX + 0.6, 0.1, m.sizeZ + 0.6), CFrame.new(m.x, 0.05, m.z), WHITE)
		-- 매트 위 글 (윗면)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "MatLabel"
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		gui.MaxDistance = 120
		Build.text(
			gui,
			"Title",
			UDim2.fromScale(0.1, 0.36),
			UDim2.fromScale(0.8, 0.28),
			"💪 수련 매트",
			WHITE,
			INK
		)
		gui.Parent = mat
		-- 매트 구석 작은 아령 (장식)
		dumbbell(
			folder,
			CFrame.new(m.x - m.sizeX / 2 + 1.2, MapLayout.MAT_HEIGHT + 0.5, m.z - m.sizeZ / 2 + 1.6),
			2.4,
			1,
			c(80, 80, 90)
		)
	end
end

------------------------------------------------------------------
-- 아령 가게 (카운터 + 진열장 20개 + 간판)
------------------------------------------------------------------

local function dumbbellColor(level: number): Color3
	local t = (level - 1) / 19
	if level >= 20 then
		return c(30, 20, 40)
	end
	return Color3.fromHSV((0.6 - t * 0.9) % 1, 0.55 + t * 0.3, 0.95 - t * 0.2)
end

local function shop(world: number, parent: Instance, theme: Theme)
	local s = MapLayout.dumbbellShop(world)
	local model = Build.model("DumbbellShop", parent)
	local dir = dirOf(s.yaw) -- 앞 (-x, 통로 쪽)
	local center = v3(s)
	local cf = facing(center, dir)
	-- 카운터 (앞쪽)
	local counter = Build.part(
		model,
		"Block",
		Vector3.new(s.sizeZ, 3.6, 2.4),
		cf * CFrame.new(0, 1.8, -s.sizeX / 2 + 1.6),
		c(150, 100, 60),
		M.Wood,
		{
			collide = true,
			query = true,
			name = "Counter",
		}
	)
	Build.part(
		model,
		"Block",
		Vector3.new(s.sizeZ + 0.4, 0.4, 2.8),
		cf * CFrame.new(0, 3.8, -s.sizeX / 2 + 1.6),
		theme.accent,
		M.SmoothPlastic,
		{
			query = true,
			name = "CounterTop",
		}
	)
	-- 뒤 진열장 2단 + 아령 20개
	local shelfZ = s.sizeX / 2 - 1.2
	for row = 0, 1 do
		Build.part(
			model,
			"Block",
			Vector3.new(s.sizeZ - 1, 0.4, 1.8),
			cf * CFrame.new(0, 2.4 + row * 3, shelfZ),
			c(120, 80, 50),
			M.Wood,
			{
				collide = true,
				query = true,
				name = "Shelf",
			}
		)
	end
	Build.part(
		model,
		"Block",
		Vector3.new(s.sizeZ, 7.6, 0.6),
		cf * CFrame.new(0, 3.8, shelfZ + 1.1),
		c(110, 72, 45),
		M.WoodPlanks,
		{
			collide = true,
			query = true,
			name = "ShelfBack",
		}
	)
	for level = 1, math.min(20, #Dumbbells.list) do
		local row = if level <= 10 then 0 else 1
		local k = (level - 1) % 10
		local x = -s.sizeZ / 2 + 1.4 + k * ((s.sizeZ - 2.8) / 9)
		local size = 0.7 + level * 0.025
		dumbbell(model, cf * CFrame.new(x, 2.6 + row * 3 + size / 2, shelfZ), 1.4, size, dumbbellColor(level))
	end
	-- 간판 (카운터 위, 진열장보다 높게)
	local board = sign(
		model,
		cf * CFrame.new(0, 9.5, shelfZ + 0.6),
		s.sizeZ - 2,
		3,
		"🏋️ 아령 가게",
		"눌러서 다음 아령 사기",
		c(70, 150, 60)
	)
	board.Name = "ShopSign"
	Build.click(model, "Click", 32)
	tagModel(model, Tags.DumbbellShop, world, counter)
end

------------------------------------------------------------------
-- 띠 표지판 (12개 띠)
------------------------------------------------------------------

local function beltBoard(world: number, parent: Instance)
	local s = MapLayout.beltBoard(world)
	local model = Build.model("BeltBoard", parent)
	local dir = dirOf(s.yaw)
	local h = 11
	local board = Build.part(
		model,
		"Block",
		Vector3.new(s.sizeZ, h, 0.6),
		facing(v3(s, 1 + h / 2), dir),
		c(36, 40, 64),
		M.SmoothPlastic,
		{
			collide = true,
			query = true,
			name = "Board",
		}
	)
	local frame = Build.surfaceSign(board, c(36, 40, 64), 24)
	Build.text(
		frame,
		"Title",
		UDim2.fromScale(0.05, 0.02),
		UDim2.fromScale(0.9, 0.12),
		"🥋 띠 (눌러서 보기)",
		WHITE
	)
	local grid = Instance.new("Frame")
	grid.Name = "Belts"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromScale(0.03, 0.16)
	grid.Size = UDim2.fromScale(0.94, 0.82)
	grid.Parent = frame
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(0.32, 0.23)
	layout.CellPadding = UDim2.fromScale(0.015, 0.02)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for _, belt in Belts.list do
		local cell = Instance.new("Frame")
		cell.Name = "Belt_" .. tostring(belt.index)
		cell.LayoutOrder = belt.index
		cell.BackgroundColor3 = c(24, 26, 44)
		cell.BorderSizePixel = 0
		cell.Parent = grid
		local edge = Instance.new("UIStroke")
		edge.Name = "Edge"
		edge.Color = if belt.world == world then c(255, 220, 80) else c(70, 74, 100)
		edge.Thickness = if belt.world == world then 4 else 2
		edge.Parent = cell
		local stripe = Instance.new("Frame")
		stripe.Name = "Stripe"
		stripe.BackgroundColor3 = Color3.fromRGB(belt.color[1], belt.color[2], belt.color[3])
		stripe.BorderSizePixel = 0
		stripe.Position = UDim2.fromScale(0.05, 0.12)
		stripe.Size = UDim2.fromScale(0.9, 0.22)
		stripe.Parent = cell
		Build.text(cell, "Name", UDim2.fromScale(0.04, 0.38), UDim2.fromScale(0.92, 0.32), belt.name, WHITE)
		local need = if belt.duel
			then "⚔️ 시험관 대결"
			elseif belt.needPower <= 0 then "처음 띠"
			else "💪 " .. Format.number(belt.needPower)
		Build.text(cell, "Need", UDim2.fromScale(0.04, 0.7), UDim2.fromScale(0.92, 0.26), need, c(255, 225, 120))
	end
	Build.click(model, "Click", 40)
	tagModel(model, Tags.BeltBoard, world, board)
end

------------------------------------------------------------------
-- 승급 심사대 (단상 + 송판 10장 거치대)
------------------------------------------------------------------

local BOARD_COLOR = c(214, 170, 110)

local function boardRack(parent: Instance, cf: CFrame, count: number, prefix: string, spacing: number)
	local len = (count - 1) * spacing
	Build.part(parent, "Block", Vector3.new(len + 2, 0.5, 1.4), cf * CFrame.new(0, 0.25, 0), c(90, 60, 40), M.Wood, {
		collide = true,
		query = true,
		name = prefix .. "Rail",
	})
	for i = 1, count do
		local x = -len / 2 + (i - 1) * spacing
		Build.part(
			parent,
			"Block",
			Vector3.new(spacing * 0.8, 2.6, 0.35),
			cf * CFrame.new(x, 1.8, 0),
			BOARD_COLOR,
			M.WoodPlanks,
			{ query = true, name = prefix .. "_" .. tostring(i) }
		)
	end
end

local function examPad(world: number, parent: Instance, theme: Theme)
	local s = MapLayout.examPad(world)
	local model = Build.model("ExamPad", parent)
	local dir = dirOf(s.yaw)
	local cf = facing(v3(s), dir)
	local stage = Build.part(
		model,
		"Block",
		Vector3.new(s.sizeZ, 0.6, s.sizeX),
		cf * CFrame.new(0, 0.3, 0),
		c(230, 220, 200),
		M.SmoothPlastic,
		{
			collide = true,
			query = true,
			name = "Stage",
		}
	)
	Build.part(
		model,
		"Block",
		Vector3.new(s.sizeZ + 0.8, 0.2, s.sizeX + 0.8),
		cf * CFrame.new(0, 0.1, 0),
		theme.accent,
		M.Neon,
		{
			name = "Glow",
			transparency = 0.2,
		}
	)
	-- 거치대 (단상 뒤쪽, 통로를 봄)
	local rack = Build.folder("Rack", model)
	boardRack(rack, cf * CFrame.new(0, 0.6, s.sizeX / 2 - 2.5), MapLayout.EXAM_BOARDS, "Board", 1.3)
	local board = sign(
		model,
		cf * CFrame.new(0, 7.2, s.sizeX / 2 - 0.6),
		12,
		3.2,
		"🥋 승급 심사",
		"20초 안에 송판 10장!",
		c(200, 70, 60)
	)
	board.Name = "ExamSign"
	Build.click(model, "Click", 36)
	tagModel(model, Tags.ExamPad, world, stage)
end

------------------------------------------------------------------
-- 시험관 대결장 (송판 15장 × 2줄 + 시험관 NPC)
------------------------------------------------------------------

-- 시험관 NPC (도복 + 띠, 파트로만). base = 발 가운데, 앞(-Z) = 플레이어 쪽
local function examiner(parent: Instance, base: CFrame, beltColor: Color3, name: string)
	local npc = Build.model("Examiner", parent)
	local dobok = c(248, 248, 250)
	local skin = c(255, 214, 170)
	local torso = Build.part(npc, "Block", Vector3.new(2.2, 2.4, 1.2), base * CFrame.new(0, 3.6, 0), dobok, M.Fabric, {
		collide = true,
		query = true,
		name = "Torso",
	})
	Build.part(
		npc,
		"Ball",
		Vector3.one * 1.6,
		base * CFrame.new(0, 5.6, 0),
		skin,
		M.SmoothPlastic,
		{ query = true, name = "Head" }
	)
	Build.part(
		npc,
		"Block",
		Vector3.new(1.7, 0.45, 1.7),
		base * CFrame.new(0, 6.25, 0),
		c(40, 30, 25),
		M.SmoothPlastic,
		{
			query = true,
			name = "Hair",
		}
	)
	Build.part(
		npc,
		"Block",
		Vector3.new(0.9, 2.4, 1),
		base * CFrame.new(-1.6, 3.6, 0),
		dobok,
		M.Fabric,
		{ query = true, name = "LeftArm" }
	)
	Build.part(
		npc,
		"Block",
		Vector3.new(0.9, 2.4, 1),
		base * CFrame.new(1.6, 3.6, 0),
		dobok,
		M.Fabric,
		{ query = true, name = "RightArm" }
	)
	Build.part(
		npc,
		"Block",
		Vector3.new(1, 2.4, 1.1),
		base * CFrame.new(-0.55, 1.2, 0),
		dobok,
		M.Fabric,
		{ query = true, name = "LeftLeg" }
	)
	Build.part(
		npc,
		"Block",
		Vector3.new(1, 2.4, 1.1),
		base * CFrame.new(0.55, 1.2, 0),
		dobok,
		M.Fabric,
		{ query = true, name = "RightLeg" }
	)
	Build.part(
		npc,
		"Block",
		Vector3.new(2.3, 0.4, 1.3),
		base * CFrame.new(0, 2.7, 0),
		beltColor,
		M.Fabric,
		{ query = true, name = "Belt" }
	)
	Build.part(
		npc,
		"Block",
		Vector3.new(0.35, 0.9, 0.2),
		base * CFrame.new(0.4, 2.3, -0.7),
		beltColor,
		M.Fabric,
		{ query = true, name = "BeltTail" }
	)
	npc.PrimaryPart = torso
	local gui = Build.billboard(torso, "NameTag", UDim2.fromOffset(240, 50), 4.4, 90)
	local label =
		Build.text(gui, "Name", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), "👑 " .. name, c(255, 230, 120))
	label.TextScaled = true
end

local function duelArena(world: number, parent: Instance, _theme: Theme)
	local s = MapLayout.duelArena(world)
	local model = Build.model("DuelArena", parent)
	local dir = dirOf(s.yaw) -- +x (통로 쪽)
	local cf = facing(v3(s), dir)
	local floor = Build.part(
		model,
		"Block",
		Vector3.new(s.sizeZ, 0.6, s.sizeX),
		cf * CFrame.new(0, 0.3, 0),
		c(60, 120, 200),
		M.SmoothPlastic,
		{
			collide = true,
			query = true,
			name = "ArenaFloor",
		}
	)
	Build.part(
		model,
		"Block",
		Vector3.new(s.sizeZ + 1, 0.2, s.sizeX + 1),
		cf * CFrame.new(0, 0.1, 0),
		c(240, 60, 60),
		M.Neon,
		{
			name = "Ring",
			transparency = 0.2,
		}
	)
	-- 두 줄: 앞(통로 쪽 → 로컬 -Z)이 아니라 옆으로 나란히. 로컬 X = 대결장 깊이 방향
	local mineCf = CFrame.new(v3(s.player, 0.6)) * (cf - cf.Position) * CFrame.Angles(0, math.pi / 2, 0)
	local theirsCf = CFrame.new(v3(s.examiner, 0.6)) * (cf - cf.Position) * CFrame.Angles(0, math.pi / 2, 0)
	local mine = Build.folder("Mine", model)
	local theirs = Build.folder("Theirs", model)
	boardRack(mine, mineCf, MapLayout.DUEL_BOARDS, "Mine", 1.6)
	boardRack(theirs, theirsCf, MapLayout.DUEL_BOARDS, "Theirs", 1.6)
	-- 시험관: 시험관 줄 끝(벽 쪽)에 서서 통로를 봄
	local w = Worlds.get(world)
	local belt = Belts.get(world * 4)
	local beltColor = if belt then Color3.fromRGB(belt.color[1], belt.color[2], belt.color[3]) else c(30, 30, 30)
	local examinerPos = v3(s.examiner)
		- dir * (s.sizeX / 2 - 2.5)
		+ Vector3.new(0, 0.6, 0)
		+ (v3(s.examiner) - v3(s.player)).Unit * 2
	examiner(model, CFrame.lookAt(examinerPos, examinerPos + dir), beltColor, if w then w.examiner else "시험관")
	local board = sign(
		model,
		facing(v3(s, 7.5) - dir * (s.sizeX / 2 - 0.6), dir),
		14,
		3.2,
		"⚔️ 시험관과 대결",
		"먼저 송판 15장을 다 깨면 승리!",
		c(150, 50, 160)
	)
	board.Name = "DuelSign"
	Build.click(model, "Click", 44)
	tagModel(model, Tags.DuelArena, world, floor)
end

------------------------------------------------------------------
-- 월드 문
------------------------------------------------------------------

local function worldDoors(world: number, parent: Instance, theme: Theme)
	for _, d in MapLayout.doors(world) do
		local model = Build.model("WorldDoor_" .. tostring(d.world), parent)
		local target = Worlds.get(d.world)
		local tint = if target then Color3.fromRGB(target.color[1], target.color[2], target.color[3]) else theme.accent
		local dir = dirOf(d.yaw)
		local base = v3(d)
		local cf = facing(base, dir)
		Build.part(
			model,
			"Block",
			Vector3.new(1.4, 10, 1.4),
			cf * CFrame.new(-4.2, 5, 0),
			theme.trim,
			M.Wood,
			{ collide = true, query = true }
		)
		Build.part(
			model,
			"Block",
			Vector3.new(1.4, 10, 1.4),
			cf * CFrame.new(4.2, 5, 0),
			theme.trim,
			M.Wood,
			{ collide = true, query = true }
		)
		Build.part(
			model,
			"Block",
			Vector3.new(10, 1.4, 1.6),
			cf * CFrame.new(0, 10.4, 0),
			theme.trim,
			M.Wood,
			{ collide = true, query = true }
		)
		local portal =
			Build.part(model, "Block", Vector3.new(7, 9.2, 0.4), cf * CFrame.new(0, 4.8, 0.2), tint, M.Neon, {
				query = true,
				name = "Portal",
				transparency = 0.25,
			})
		-- 자물쇠 (클라가 내 열린 월드에 맞춰 보이기/숨기기 — 서버는 그냥 보이게 둠)
		local lock = Build.folder("Lock", model)
		Build.part(lock, "Block", Vector3.new(2.6, 2.2, 0.8), cf * CFrame.new(0, 4.4, -0.4), c(255, 200, 50), M.Metal, {
			query = true,
			name = "LockBody",
		})
		Build.part(
			lock,
			"HCyl",
			Vector3.new(0.6, 2.2, 2.2),
			cf * CFrame.new(0, 5.8, -0.4) * CFrame.Angles(0, math.pi / 2, 0),
			c(200, 200, 210),
			M.Metal,
			{
				query = true,
				name = "LockShackle",
			}
		)
		local title = string.format("🚪 월드 %d", d.world)
		local sub = if target then target.name else ""
		local board = sign(model, cf * CFrame.new(0, 12.6, -0.2), 9, 2.6, title, sub, c(40, 44, 70))
		board.Name = "DoorSign"
		model:SetAttribute(PA.TargetWorld, d.world)
		Build.click(model, "Click", 30)
		tagModel(model, Tags.WorldDoor, world, portal)
	end
end

------------------------------------------------------------------

function Dojo.build(world: number, parent: Instance, theme: Theme): Folder
	local lobby = Build.folder("Lobby", parent)
	shell(world, lobby, theme)
	spawnPad(world, lobby, theme)
	trainMats(world, lobby, theme)
	shop(world, lobby, theme)
	beltBoard(world, lobby)
	examPad(world, lobby, theme)
	duelArena(world, lobby, theme)
	worldDoors(world, lobby, theme)
	return lobby
end

return Dojo
