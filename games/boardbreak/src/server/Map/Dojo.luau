--!strict
--[[
	Dojo — 월드마다 로비(도장) 만들기 (선임). 자리는 전부 shared/Data/MapLayout.
	  Dojo.build(world, parent, theme) → Folder "Lobby"
	만드는 것 (태그는 shared/Tags, 전부 Model 에 태그 + Attr World + ClickDetector "Click"):
	  WorldSpawn (월드 1 은 진짜 SpawnLocation) · TrainMat 6칸 (각 매트 파트에 태그 — 위에 서면 들기)
	  · DumbbellShop (카운터 + 아령 진열 + 간판) · BeltBoard (Belts.list 전부 — 월드별 세로 칸, 여러 색 띠는 그러데이션 · 클라가 내 띠를 반짝이게)
	  · ExamPad (단상 + 송판 10장 거치대 Board_1..10) · DuelArena (내 쪽 Mine_1..15 · 시험관 쪽 Theirs_1..15 + 시험관 NPC)
	  · WorldDoor (다른 월드 문 2개, Attr TargetWorld. 자물쇠 "Lock" 은 클라가 내 열린 월드에 맞춰 보이기/숨기기)
	표지판은 스폰·매트 위를 가리지 않게 벽 쪽에 (smoke_visuals 가 검사).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
-- 짓기는 배율 1 자리로 (MapBuilder 가 월드를 다 지은 뒤 통째로 worldScale 배 키움)
local Layout = MapLayout.base
local Belts = require(Shared.Data.Belts)
local Worlds = require(Shared.Data.Worlds)
local Dumbbells = require(Shared.Data.Dumbbells)
local Sizes = require(Shared.Data.Sizes)
local DumbbellLook = require(Shared.DumbbellLook)
local BeltLook = require(Shared.BeltLook)
local Format = require(Shared.Format)
local Tags = require(Shared.Tags)
local Build = require(script.Parent.Build)

local Dojo = {}

Dojo.SHOP_MAX = 60 -- 가게 진열 아령 상한 (표가 더 길면 앞 60개만)
-- 사범님 이름표가 보이는 거리 (배율 1 — 큰 월드는 × 배율). 90 이면 월드 3 에서 990 이라 길 위 물건 글(달 등)과 겹쳐 보였음
--   (본부장 2026-11-16 스튜디오: 화성 매트에서 "별빛 그랜드 마스터" 가 "달" 글 위에) → 큰 월드는 도장 안·정문 앞에서만
Dojo.NAME_TAG_DISTANCE = { 90, 50, 50 } -- 월드 1 은 그대로 90 · 큰 월드 50 × 배율 (월드 2 = 275 · 3 = 550)
local SHELF_Y0 = 1.4
local SHELF_GAP = 1.6
local SHOP_SCALE = 0.7

export type Theme = {
	floor: Color3,
	floorMaterial: Enum.Material,
	wall: Color3,
	wallMaterial: Enum.Material,
	trim: Color3,
	mat: { Color3 },
	accent: Color3,
	name: string,
	glow: boolean?, -- 벽 아래 네온 띠 (어두운 우주 도장 — 스스로 빛나서 방 모양이 보임)
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
	local rect = Layout.lobbyRect(world)
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
	-- 어두운 우주 도장: 안쪽 벽 아래·위에 네온 띠 (스스로 빛나서 방 모양이 보임 — 빛 범위 상한 60 과 상관없음)
	if theme.glow then
		local gate0 = 10
		local t = 0.4
		local runs = {
			{ rect.x0 + t / 2, 0, t, d }, -- 왼쪽
			{ rect.x1 - t / 2, 0, t, d }, -- 오른쪽
			{ cx, rect.z0 + t / 2, w, t }, -- 뒤
			{ (rect.x0 + cx - gate0) / 2, rect.z1 - t / 2, (cx - gate0) - rect.x0, t }, -- 앞 왼쪽 (정문 빼고)
			{ (rect.x1 + cx + gate0) / 2, rect.z1 - t / 2, rect.x1 - (cx + gate0), t }, -- 앞 오른쪽
		}
		for _, y in { 0.5, WALL_H - 0.6 } do
			for _, s in runs do
				Build.part(
					parent,
					"Block",
					Vector3.new(s[3], 0.6, s[4]),
					CFrame.new(s[1], y, s[2]),
					theme.accent,
					M.Neon,
					{ name = "GlowTrim", shadow = false }
				)
			end
		end
	end
	-- 모서리 기둥 4개 (천장까지 — 사장님 결정 17번) + 등불 (높이는 그대로, 기둥 바깥 모서리에 붙음)
	local pillarH = Dojo.roofY(world) + 1
	for _, p in { { rect.x0, rect.z0 }, { rect.x1, rect.z0 }, { rect.x0, rect.z1 }, { rect.x1, rect.z1 } } do
		Build.solid(
			parent,
			"Pillar",
			Vector3.new(3.5, pillarH, 3.5),
			CFrame.new(p[1], pillarH / 2, p[2]),
			theme.trim,
			M.Wood
		)
		local out = Vector3.new(if p[1] < cx then -1 else 1, 0, if p[2] < 0 then -1 else 1) * 2.4
		local lamp = Build.part(
			parent,
			"Ball",
			Vector3.one * 2.2,
			CFrame.new(Vector3.new(p[1], WALL_H + 4.2, p[2]) + out),
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
		"물건 깨러 가기 →",
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
-- 지붕·천장 (Lobby/Roof). 벽 위(WALL_H)부터 천장(roofY)까지 윗벽으로 메우고, 천장 판 + 월드 테마 지붕 + 천장 등.
--   정문(가운데 x ±10)은 높이 17 까지 비워 둠, 월드 문은 로비 안쪽에 있어 그대로.
--   사장님 결정 17번 ("도장을 뚫고 나왔으니까 천장만 겁나 높여"): 천장 아랫면(진짜 스터드, 월드 배율 곱한 값)이
--   가장 큰 몸 키(Sizes.MAX_SCALE × AVATAR_HEIGHT ≈ 75) × CLEAR(1.3) ≈ 98 이상. 바닥 넓이·자리·문·표지판·매트 높이는 그대로.
--   천장 등은 옛 천장 높이(LAMP_CEIL 20)에 매단 채 (끈으로 새 천장에) → 바닥 밝기는 예전과 같음.
--   새로 생긴 높은 윗벽: 나무 띠(BAND_GAP 마다) · 월드 1 은 태권도 정신 현수막 5장 + 위쪽 채광창 (빈 굴뚝처럼 안 보이게).
------------------------------------------------------------------

Dojo.ROOF_Y = 20 -- 옛 천장 높이 (배율 1). 천장 등은 이 높이에 매달림
Dojo.LAMP_CEIL = 20
Dojo.CLEAR = 1.3
-- 월드마다 천장 아랫면 (배율 1 숫자): 1 = 100 (진짜 100) · 2 = 24 (진짜 132 — 110 은 75 몸 옆에서 답답해 보여 조금 올림) · 3 = 20 (진짜 220)
Dojo.ROOF_Y_BY_WORLD = { 100, 24, 20 }
Dojo.BAND_GAP = 18
Dojo.GATE_CLEAR = 17 -- 정문 위 윗벽 아랫면

-- 그 월드 천장 아랫면 (배율 1 숫자). 표 값과 "가장 큰 몸 × CLEAR ÷ 월드 배율" 중 큰 것
function Dojo.roofY(world: number): number
	local w = math.clamp(math.floor(world), 1, #Dojo.ROOF_Y_BY_WORLD)
	local need = Dojo.CLEAR * Sizes.MAX_SCALE * Sizes.AVATAR_HEIGHT / MapLayout.worldScale(w)
	return math.max(Dojo.ROOF_Y_BY_WORLD[w], math.ceil(need))
end

-- 높아진 윗벽 안쪽 꾸밈 (윗벽이 20 스터드 넘게 높을 때만): 나무 띠 (BAND_GAP 마다, 우주 도장은 네온) ·
--   월드 1: 태권도 정신 현수막 (양옆 벽 4장 예의·염치·인내·극기 + 뒤 벽 태권도) · 위쪽 채광창 8개. 전부 안 부딪힘·그림자 없음
local TENETS = { "예\n의", "염\n치", "인\n내", "극\n기" }

function Dojo.upperDecor(world: number, folder: Instance, theme: Theme, rect: MapLayout.Rect, top: number)
	if top - WALL_H < 20 then
		return
	end
	local cx = (rect.x0 + rect.x1) / 2
	local cz = (rect.z0 + rect.z1) / 2
	local w = rect.x1 - rect.x0
	local d = rect.z1 - rect.z0
	local bandMat = if theme.glow then M.Neon else M.Wood
	local bandColor = if theme.glow then theme.accent else theme.trim
	local y = WALL_H + Dojo.BAND_GAP
	while y < top - 6 do
		for _, b in
			{
				{ rect.x0 + 0.3, cz, 0.6, d },
				{ rect.x1 - 0.3, cz, 0.6, d },
				{ cx, rect.z0 + 0.3, w, 0.6 },
				{ cx, rect.z1 - 0.3, w, 0.6 },
			}
		do
			Build.part(
				folder,
				"Block",
				Vector3.new(b[3], 1.2, b[4]),
				CFrame.new(b[1], y, b[2]),
				bandColor,
				bandMat,
				{ name = "WallBand", shadow = false }
			)
		end
		y += Dojo.BAND_GAP
	end
	if world ~= 1 then
		return
	end
	local red, blue = c(190, 40, 45), c(40, 70, 170)
	local bannerH = 34
	local by = WALL_H + 14 + bannerH / 2 -- 아래 끝 23 (문 간판·띠 표지판·가게 간판 위)
	local function banner(pos: Vector3, inward: Vector3, width: number, color: Color3, text: string)
		local board = Build.part(
			folder,
			"Block",
			Vector3.new(width, bannerH, 0.3),
			CFrame.lookAt(pos, pos + inward),
			color,
			M.Fabric,
			{ name = "Banner", shadow = false }
		)
		local frame = Build.surfaceSign(board, color, 10)
		Build.text(frame, "Word", UDim2.fromScale(0.1, 0.06), UDim2.fromScale(0.8, 0.88), text, WHITE)
	end
	local k = 0
	for _, side in { -1, 1 } do
		local x = if side < 0 then rect.x0 + 0.5 else rect.x1 - 0.5
		for _, z in { -20, 20 } do
			k += 1
			banner(
				Vector3.new(x, by, cz + z),
				Vector3.new(-side, 0, 0),
				10,
				if k % 2 == 1 then red else blue,
				TENETS[k]
			)
		end
	end
	banner(Vector3.new(cx, by, rect.z0 + 0.5), Vector3.new(0, 0, 1), 26, red, "🥋 태권도")
	-- 위쪽 채광창 (양옆 벽, 천장 아래)
	for _, side in { -1, 1 } do
		local x = if side < 0 then rect.x0 + 0.25 else rect.x1 - 0.25
		for _, z in { -36, -12, 12, 36 } do
			Build.part(
				folder,
				"Block",
				Vector3.new(0.4, 12, 14),
				CFrame.new(x, top - 10, cz + z),
				c(205, 225, 240),
				M.Glass,
				{ name = "ClerestoryWindow", transparency = 0.25, shadow = false }
			)
		end
	end
end

local function roof(world: number, parent: Instance, theme: Theme)
	local folder = Build.folder("Roof", parent)
	local rect = Layout.lobbyRect(world)
	local cx = (rect.x0 + rect.x1) / 2
	local cz = (rect.z0 + rect.z1) / 2
	local w = rect.x1 - rect.x0
	local d = rect.z1 - rect.z0
	local top = Dojo.roofY(world)
	local uh = top - WALL_H
	local uy = WALL_H + uh / 2
	-- 윗벽 (왼·오른·뒤 + 앞 양옆 + 정문 위 상인방)
	Build.solid(
		folder,
		"UpperWall",
		Vector3.new(2, uh, d + 4),
		CFrame.new(rect.x0 - 1, uy, cz),
		theme.wall,
		theme.wallMaterial
	)
	Build.solid(
		folder,
		"UpperWall",
		Vector3.new(2, uh, d + 4),
		CFrame.new(rect.x1 + 1, uy, cz),
		theme.wall,
		theme.wallMaterial
	)
	Build.solid(
		folder,
		"UpperWall",
		Vector3.new(w + 4, uh, 2),
		CFrame.new(cx, uy, rect.z0 - 1),
		theme.wall,
		theme.wallMaterial
	)
	local gate = 10
	local side = (w - gate * 2) / 2
	Build.solid(
		folder,
		"UpperWall",
		Vector3.new(side + 2, uh, 2),
		CFrame.new(rect.x0 + side / 2 - 1, uy, rect.z1 + 1),
		theme.wall,
		theme.wallMaterial
	)
	Build.solid(
		folder,
		"UpperWall",
		Vector3.new(side + 2, uh, 2),
		CFrame.new(rect.x1 - side / 2 + 1, uy, rect.z1 + 1),
		theme.wall,
		theme.wallMaterial
	)
	local lh = top - Dojo.GATE_CLEAR
	Build.solid(
		folder,
		"GateLintel",
		Vector3.new(gate * 2 + 2, lh, 2),
		CFrame.new(cx, Dojo.GATE_CLEAR + lh / 2, rect.z1 + 1),
		theme.trim,
		M.Wood
	)
	-- 천장 판 (벽 바깥까지 덮음)
	local ceilColor = if world == 1 then c(225, 205, 165) elseif world == 2 then c(190, 225, 245) else c(95, 98, 140)
	local ceilMat = if world == 1 then M.WoodPlanks elseif world == 2 then M.Glass else M.SmoothPlastic
	local ceiling = Build.solid(
		folder,
		"Ceiling",
		Vector3.new(w + 4, 1, d + 4),
		CFrame.new(cx, top + 0.5, cz),
		ceilColor,
		ceilMat,
		{ transparency = if world == 2 then 0.35 else 0 }
	)
	ceiling:SetAttribute("RoofBottom", top)
	-- 천장 들보 (안에서 보이는 줄)
	for i = -2, 2 do
		Build.part(
			folder,
			"Beam",
			Vector3.new(w + 2, 0.8, 1.2),
			CFrame.new(cx, top - 0.4, cz + i * (d / 5)),
			if world == 2 then c(200, 205, 215) else theme.trim,
			if world == 2 then M.Metal else M.Wood
		)
	end
	-- 천장 등 3 × 2 (안이 어둡지 않게) — 옛 천장 높이에 매닮 (빛 범위 상한 60 이라 높은 천장에 붙이면 바닥까지 못 닿음)
	local lampY = math.min(top, Dojo.LAMP_CEIL) - 1
	for _, lx in { -30, 0, 30 } do
		for _, lz in { -22, 18 } do
			local lamp = Build.part(
				folder,
				"CeilingLamp",
				Vector3.new(6, 0.4, 2.5),
				CFrame.new(cx + lx, lampY, cz + lz),
				if world == 3 then theme.accent else c(255, 245, 220),
				M.Neon
			)
			Build.light(lamp, if world == 3 then c(210, 190, 255) else c(255, 240, 215), 45, 1.4)
			if top - lampY > 2 then
				-- 매단 끈 (천장 → 등)
				local len = top - lampY - 0.2
				Build.part(
					folder,
					"LampCord",
					Vector3.new(0.25, len, 0),
					CFrame.new(cx + lx, lampY + 0.2 + len / 2, cz + lz),
					c(40, 36, 32),
					M.SmoothPlastic,
					{ shadow = false }
				)
			end
		end
	end
	-- 높아진 윗벽 꾸밈 (사장님 결정 17번)
	Dojo.upperDecor(world, folder, theme, rect, top)
	-- 월드 테마 지붕 (천장 위)
	if world == 1 then
		-- 기와지붕: 박공 쐐기 2개 + 처마 + 용마루
		local rh = 12
		local tile = c(64, 70, 86)
		Build.part(
			folder,
			"Wedge",
			Vector3.new(w + 10, rh, d / 2 + 5),
			CFrame.new(cx, top + 1 + rh / 2, cz - (d / 2 + 5) / 2),
			tile,
			M.Slate,
			{ name = "RoofTile" }
		)
		Build.part(
			folder,
			"Wedge",
			Vector3.new(w + 10, rh, d / 2 + 5),
			CFrame.new(cx, top + 1 + rh / 2, cz + (d / 2 + 5) / 2) * CFrame.Angles(0, math.pi, 0),
			tile,
			M.Slate,
			{ name = "RoofTile" }
		)
		Build.part(
			folder,
			"Block",
			Vector3.new(w + 12, 1.2, 2.2),
			CFrame.new(cx, top + 1 + rh + 0.4, cz),
			c(40, 44, 56),
			M.Slate,
			{ name = "RoofRidge" }
		)
		for _, sz in { -1, 1 } do
			Build.part(
				folder,
				"Block",
				Vector3.new(w + 12, 0.6, 3),
				CFrame.new(cx, top + 1.1, cz + sz * (d / 2 + 5)),
				theme.trim,
				M.Wood,
				{ name = "Eave" }
			)
		end
	else
		-- 2 유리 돔 체육관 / 3 우주선 돔: 층층이 줄어드는 원판 4장 + 꼭대기
		local glass = if world == 2 then c(150, 210, 245) else c(70, 50, 130)
		local ring = if world == 2 then c(220, 225, 235) else theme.accent
		local sizes = { 92, 74, 52, 28 }
		for i, dia in sizes do
			local y = top + 1 + (i - 0.5) * 3
			Build.part(
				folder,
				"VCyl",
				Vector3.new(dia, 3, 0),
				CFrame.new(cx, y, cz),
				glass,
				M.Glass,
				{ name = "Dome", transparency = 0.3 }
			)
			Build.part(
				folder,
				"VCyl",
				Vector3.new(dia + 1, 0.4, 0),
				CFrame.new(cx, y - 1.5, cz),
				ring,
				if world == 3 then M.Neon else M.Metal,
				{ name = "DomeRing" }
			)
		end
		if world == 3 then
			Build.part(
				folder,
				"VCyl",
				Vector3.new(0.6, 10, 0),
				CFrame.new(cx, top + 18, cz),
				c(200, 200, 220),
				M.Metal,
				{
					name = "Antenna",
				}
			)
			local tip =
				Build.part(folder, "Ball", Vector3.one * 1.6, CFrame.new(cx, top + 23.5, cz), c(255, 80, 80), M.Neon, {
					name = "AntennaTip",
				})
			Build.light(tip, c(255, 90, 90), 20, 2)
		end
	end
	-- 사장님 결정 13번: 몸이 천장보다 큰 거인이 작은 월드에 와도 안 끼게 — 지붕 전체는 플레이어 몸과 안 부딪힘
	--   (충돌 그룹 Build.PASS_GROUP. 카메라·다른 것과는 그대로 부딪혀서 보통 몸은 천장 아래에서 카메라가 멈춤)
	for _, piece in folder:GetDescendants() do
		if piece:IsA("BasePart") then
			Build.giantPass(piece)
		end
	end
	return folder
end
Dojo.roof = roof

------------------------------------------------------------------
-- 스폰 · 수련 매트
------------------------------------------------------------------

local function spawnPad(world: number, parent: Instance, theme: Theme)
	local s = Layout.spawn(world)
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

local function trainMats(world: number, parent: Instance, theme: Theme)
	local folder = Build.folder("TrainMats", parent)
	for i, m in Layout.trainMats(world) do
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
		-- 매트 구석 작은 아령 (장식, 가게와 같은 진짜 아령 모양)
		local deco = DumbbellLook.build(
			folder,
			1,
			1.2,
			true,
			CFrame.new(m.x - m.sizeX / 2 + 1.4, MapLayout.MAT_HEIGHT + 0.4, m.z - m.sizeZ / 2 + 1.6)
		)
		deco.Name = "MatDumbbell"
	end
end

------------------------------------------------------------------
-- 아령 가게 (카운터 + 진열장 20개 + 간판)
------------------------------------------------------------------

local function shop(world: number, parent: Instance, theme: Theme)
	local s = Layout.dumbbellShop(world)
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
	local shown = math.min(#Dumbbells.list, Dojo.SHOP_MAX)
	local rows = math.clamp(math.ceil(shown / 12), 1, 5)
	local perRow = math.max(1, math.ceil(shown / rows))
	for row = 0, rows - 1 do
		Build.part(
			model,
			"Block",
			Vector3.new(s.sizeZ - 1, 0.3, 1.8),
			cf * CFrame.new(0, SHELF_Y0 + row * SHELF_GAP, shelfZ),
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
		Vector3.new(s.sizeZ, SHELF_Y0 + rows * SHELF_GAP, 0.6),
		cf * CFrame.new(0, (SHELF_Y0 + rows * SHELF_GAP) / 2, shelfZ + 1.1),
		c(110, 72, 45),
		M.WoodPlanks,
		{
			collide = true,
			query = true,
			name = "ShelfBack",
		}
	)
	-- 진열 아령: Dumbbells 표 길이만큼 (상한 SHOP_MAX). 진짜 아령 모양(DumbbellLook) 0.7배, 봉이 진열장 안쪽을 봄
	local display = Build.folder("Display", model)
	for level = 1, shown do
		local row = (level - 1) // perRow
		local k = (level - 1) % perRow
		local x = -s.sizeZ / 2 + 1.4 + k * ((s.sizeZ - 2.8) / math.max(1, perRow - 1))
		local y = SHELF_Y0 + row * SHELF_GAP + 0.15 + DumbbellLook.diameterOf(level) * SHOP_SCALE / 2
		local one = DumbbellLook.build(
			display,
			level,
			SHOP_SCALE,
			true,
			cf * CFrame.new(x, y, shelfZ) * CFrame.Angles(0, math.pi / 2, 0)
		)
		one.Name = "Dumbbell_" .. tostring(level)
	end
	-- 간판 (카운터 위, 진열장보다 높게)
	local board = sign(
		model,
		cf * CFrame.new(0, SHELF_Y0 + rows * SHELF_GAP + 1.8, shelfZ + 0.6),
		s.sizeZ - 2,
		3,
		"🏋️ 아령 가게",
		"눌러서 다음 아령 구매",
		c(70, 150, 60)
	)
	board.Name = "ShopSign"
	Build.click(model, "Click", 32)
	tagModel(model, Tags.DumbbellShop, world, counter)
end

------------------------------------------------------------------
-- 띠 표지판 (Belts.list 전부 — 사장님 결정 16번: 22개). 월드마다 한 줄(세로 칸): 월드 1 · 2 · 3 을 왼쪽 → 오른쪽,
--   그 월드 띠를 위 → 아래 (개수는 belt.world 로 셈 — "4개씩" 가정 없음). 칸 = 띠 천(여러 색이면 그러데이션) + 이름 + 추천 힘/대결
------------------------------------------------------------------

Dojo.BELT_BOARD_H = 15 -- 표지판 높이 (위 끝 16 < 천장 20)
Dojo.BELT_HEADER = 0.17 -- 위 제목 + 월드 이름 줄 (비율)

-- 띠 칸 자리 (grid 안 비율): 월드 열 · 그 월드 안 순서 행. 반환 { [index] = { col, row, rows } }, 열 수
function Dojo.beltCells(): ({ [number]: { col: number, row: number, rows: number } }, number)
	local worlds: { number } = {}
	local count: { [number]: number } = {}
	for _, belt in Belts.list do
		if not count[belt.world] then
			count[belt.world] = 0
			table.insert(worlds, belt.world)
		end
		count[belt.world] += 1
	end
	table.sort(worlds)
	local rows = 1
	for _, n in count do
		rows = math.max(rows, n)
	end
	local colOf: { [number]: number } = {}
	for i, w in worlds do
		colOf[w] = i
	end
	local seen: { [number]: number } = {}
	local out: { [number]: { col: number, row: number, rows: number } } = {}
	for _, belt in Belts.list do
		seen[belt.world] = (seen[belt.world] or 0) + 1
		out[belt.index] = { col = colOf[belt.world], row = seen[belt.world], rows = rows }
	end
	return out, #worlds
end

local function beltBoard(world: number, parent: Instance)
	local s = Layout.beltBoard(world)
	local model = Build.model("BeltBoard", parent)
	local dir = dirOf(s.yaw)
	local h = Dojo.BELT_BOARD_H
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
	local frame = Build.surfaceSign(board, c(36, 40, 64), 30)
	Build.text(
		frame,
		"Title",
		UDim2.fromScale(0.05, 0.01),
		UDim2.fromScale(0.9, 0.08),
		"🥋 띠 (눌러서 보기)",
		WHITE
	)
	local grid = Instance.new("Frame")
	grid.Name = "Belts"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromScale(0.02, 0.1)
	grid.Size = UDim2.fromScale(0.96, 0.89)
	grid.Parent = frame
	local cells, cols = Dojo.beltCells()
	local colW = 1 / math.max(1, cols)
	local head = 0.07 -- 월드 이름 줄 (grid 안 비율)
	for col = 1, cols do
		local w = 0
		for _, belt in Belts.list do
			if cells[belt.index].col == col then
				w = belt.world
				break
			end
		end
		local wd = Worlds.get(w)
		local tint = if wd then Color3.fromRGB(wd.color[1], wd.color[2], wd.color[3]) else WHITE
		Build.text(
			grid,
			"World_" .. tostring(w),
			UDim2.fromScale((col - 1) * colW + 0.01, 0),
			UDim2.fromScale(colW - 0.02, head - 0.01),
			string.format("월드 %d", w),
			tint
		)
	end
	for _, belt in Belts.list do
		local at = cells[belt.index]
		local rowH = (1 - head) / at.rows
		local cell = Instance.new("Frame")
		cell.Name = "Belt_" .. tostring(belt.index)
		cell.LayoutOrder = belt.index
		cell.BackgroundColor3 = c(24, 26, 44)
		cell.BorderSizePixel = 0
		cell.Position = UDim2.fromScale((at.col - 1) * colW + 0.008, head + (at.row - 1) * rowH + rowH * 0.06)
		cell.Size = UDim2.fromScale(colW - 0.016, rowH * 0.88)
		cell.Parent = grid
		local edge = Instance.new("UIStroke")
		edge.Name = "Edge"
		edge.Color = if belt.world == world then c(255, 220, 80) else c(70, 74, 100)
		edge.Thickness = if belt.world == world then 3 else 2
		edge.Parent = cell
		local stripe = Instance.new("Frame")
		stripe.Name = "Stripe"
		stripe.BorderSizePixel = 0
		stripe.Position = UDim2.fromScale(0.03, 0.2)
		stripe.Size = UDim2.fromScale(0.26, 0.6)
		stripe.Parent = cell
		BeltLook.paint(stripe, belt)
		Build.text(cell, "Name", UDim2.fromScale(0.33, 0.02), UDim2.fromScale(0.65, 0.56), belt.name, WHITE)
		local need = if belt.duel
			then "⚔️ 시험관 대결"
			elseif belt.needPower <= 0 then "처음 띠"
			else "💪 " .. Format.number(belt.needPower)
		Build.text(cell, "Need", UDim2.fromScale(0.33, 0.58), UDim2.fromScale(0.65, 0.4), need, c(255, 225, 120))
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
	local s = Layout.examPad(world)
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
local function blockExaminer(parent: Instance, base: CFrame, beltColor: Color3, name: string, world: number): Model
	local npc = Build.model("Examiner", parent)
	local dobok = c(22, 22, 26) -- 사장님 2026-11-16: 검은 도복
	local skin = c(255, 214, 170)
	local torso = Build.part(npc, "Block", Vector3.new(2.2, 2.4, 1.2), base * CFrame.new(0, 3.6, 0), dobok, M.Fabric, {
		collide = false,
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
	local gui = Build.billboard(
		torso,
		"NameTag",
		UDim2.fromOffset(240, 50),
		4.4,
		Dojo.NAME_TAG_DISTANCE[math.clamp(world, 1, 3)]
	)
	local label =
		Build.text(gui, "Name", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), "🥋 " .. name, c(255, 230, 120))
	label.TextScaled = true
	npc:SetAttribute("Rig", "block")
	return npc
end

-- 사범님 (진짜 로블록스 R15 몸). 서버에서 기본 몸을 만들고 피부·흰 도복·깃·띠·머리카락·얼굴을 입힘 (외부 에셋 id 없음).
--   Dojo.createRig() 이 실패하면(테스트 환경 등) 블록 모델로 대체. 테스트는 Dojo.createRig 를 바꿔 끼울 수 있음.
local SKIN = c(234, 184, 146)
-- 사장님 2026-11-16: "사범님 도복 검정색" → 검은 도복. 띠·깃은 검정 위에서 보이게 밝은 색으로
local DOBOK = c(22, 22, 26)
-- 월드마다: 띠 색 · 깃/소매 줄 색 · 머리 색 (1 빨간 띠 + 흰 줄 · 2 금색 띠 + 빨강 줄 · 3 금색 띠 + 금색 줄)
local EXAMINER_STYLE = {
	{ belt = c(210, 30, 40), trim = c(240, 240, 240), hair = c(30, 24, 20) },
	{ belt = c(240, 190, 40), trim = c(210, 30, 40), hair = c(50, 36, 28) },
	{ belt = c(240, 190, 40), trim = c(240, 190, 40), hair = c(200, 200, 205) },
}

function Dojo.createRig(): Model?
	local Players = game:GetService("Players")
	local ok, rig = pcall(function(): Model
		local desc: any = Instance.new("HumanoidDescription")
		desc.HeadColor = SKIN
		desc.TorsoColor = DOBOK
		desc.LeftArmColor = DOBOK
		desc.RightArmColor = DOBOK
		desc.LeftLegColor = DOBOK
		desc.RightLegColor = DOBOK
		return (Players :: any):CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	return if ok and typeof(rig) == "Instance" and rig:IsA("Model") then rig else nil
end

local function weldTo(
	rig: Model,
	to: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	mat: Enum.Material?
)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or M.Fabric
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = to.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = rig
	return p
end

local function bodyPart(rig: Model, name: string): BasePart?
	local p = rig:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

-- 입히기 (진짜 몸이든 테스트 가짜 몸이든 부위 이름만 맞으면 됨)
function Dojo.dressExaminer(rig: Model, world: number, name: string)
	local style = EXAMINER_STYLE[math.clamp(world, 1, #EXAMINER_STYLE)]
	for _, d in rig:GetDescendants() do
		if d:IsA("BodyColors") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	for _, n in
		{
			"UpperTorso",
			"LowerTorso",
			"LeftUpperArm",
			"LeftLowerArm",
			"RightUpperArm",
			"RightLowerArm",
			"LeftUpperLeg",
			"LeftLowerLeg",
			"RightUpperLeg",
			"RightLowerLeg",
		}
	do
		local p = bodyPart(rig, n)
		if p then
			p.Color = DOBOK
			-- 사장님 2026-11-16: 검은 도복 (매끈한 재질 — Fabric 은 얼룩덜룩해 보임)
			p.Material = Enum.Material.SmoothPlastic
		end
	end
	for _, n in { "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot" } do
		local p = bodyPart(rig, n)
		if p then
			p.Color = SKIN
		end
	end
	local upper = bodyPart(rig, "UpperTorso")
	if upper then
		local s = upper.Size
		-- 도복 깃 (앞에서 V 자로 겹침)
		for _, sx in { -1, 1 } do
			weldTo(
				rig,
				upper,
				"Collar",
				Vector3.new(0.28, s.Y * 0.95, 0.06),
				CFrame.new(sx * 0.22, 0.02, -s.Z / 2 - 0.03) * CFrame.Angles(0, 0, sx * 0.42),
				style.trim
			)
		end
	end
	local lower = bodyPart(rig, "LowerTorso")
	if lower then
		local s = lower.Size
		local y = s.Y / 2 - 0.12
		weldTo(rig, lower, "Belt", Vector3.new(s.X + 0.1, 0.26, s.Z + 0.1), CFrame.new(0, y, 0), style.belt)
		weldTo(rig, lower, "BeltKnot", Vector3.new(0.36, 0.3, 0.14), CFrame.new(0, y, -s.Z / 2 - 0.1), style.belt)
		for _, sx in { -1, 1 } do
			weldTo(
				rig,
				lower,
				"BeltTail",
				Vector3.new(0.16, 0.8, 0.05),
				CFrame.new(sx * 0.12, y - 0.48, -s.Z / 2 - 0.12) * CFrame.Angles(0, 0, sx * 0.18),
				style.belt
			)
		end
	end
	-- 소매·바짓단 줄
	for _, n in { "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg" } do
		local p = bodyPart(rig, n)
		if p then
			local s = p.Size
			weldTo(
				rig,
				p,
				"Cuff",
				Vector3.new(s.X + 0.06, 0.14, s.Z + 0.06),
				CFrame.new(0, -s.Y / 2 + 0.12, 0),
				style.trim
			)
		end
	end
	local head = bodyPart(rig, "Head")
	if head then
		local s = head.Size
		weldTo(
			rig,
			head,
			"Hair",
			Vector3.new(s.X * 1.06, 0.32, s.Z * 1.06),
			CFrame.new(0, s.Y / 2 - 0.02, 0.02),
			style.hair
		)
		weldTo(
			rig,
			head,
			"HairBack",
			Vector3.new(s.X * 1.06, s.Y * 0.55, 0.22),
			CFrame.new(0, s.Y * 0.18, s.Z / 2 - 0.02),
			style.hair
		)
		-- 진지한 눈썹 (얼굴은 기본 얼굴 — 로블록스 안에 들어 있는 그림)
		for _, sx in { -1, 1 } do
			weldTo(
				rig,
				head,
				"Brow",
				Vector3.new(0.3, 0.07, 0.05),
				CFrame.new(sx * 0.22, s.Y * 0.16, -s.Z / 2 - 0.02) * CFrame.Angles(0, 0, sx * -0.2),
				style.hair,
				M.SmoothPlastic
			)
		end
		if not head:FindFirstChildOfClass("Decal") then
			local face = Instance.new("Decal")
			face.Name = "face"
			face.Face = Enum.NormalId.Front
			face.Texture = "rbxasset://textures/face.png"
			face.Parent = head
		end
		local gui = Build.billboard(
			head,
			"NameTag",
			UDim2.fromOffset(240, 50),
			2.2,
			Dojo.NAME_TAG_DISTANCE[math.clamp(world, 1, 3)]
		)
		local label =
			Build.text(gui, "Name", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), "🥋 " .. name, c(255, 230, 120))
		label.TextScaled = true
	end
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		pcall(function()
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end)
	end
end

local function examiner(world: number, parent: Instance, base: CFrame, name: string): Model
	local style = EXAMINER_STYLE[math.clamp(world, 1, #EXAMINER_STYLE)]
	local rig = Dojo.createRig()
	local root = rig and rig:FindFirstChild("HumanoidRootPart")
	if rig and root and root:IsA("BasePart") then
		rig.Name = "Examiner"
		rig.PrimaryPart = root
		Dojo.dressExaminer(rig, world, name)
		local hum = rig:FindFirstChildOfClass("Humanoid")
		local hip = if hum and hum.HipHeight > 0 then hum.HipHeight else 2
		-- 발이 바닥(base)에 닿게: 뿌리 파트 가운데 = 바닥 + 엉덩이 높이 + 뿌리 반 높이
		local target = base * CFrame.new(0, hip + root.Size.Y / 2, 0)
		local ok = pcall(function()
			rig:PivotTo(target)
		end)
		if not ok then
			root.CFrame = target
		end
		rig:SetAttribute("Rig", "R15")
		rig.Parent = parent
		return rig
	end
	if rig then
		rig:Destroy()
	end
	return blockExaminer(parent, base, style.belt, name, world)
end

local function duelArena(world: number, parent: Instance, _theme: Theme)
	local s = Layout.duelArena(world)
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
	local examinerPos = v3(s.examiner)
		- dir * (s.sizeX / 2 - 2.5)
		+ Vector3.new(0, 0.6, 0)
		+ (v3(s.examiner) - v3(s.player)).Unit * 2
	examiner(world, model, CFrame.lookAt(examinerPos, examinerPos + dir), if w then w.examiner else "사범님")
	local board = sign(
		model,
		facing(v3(s, 7.5) - dir * (s.sizeX / 2 - 0.6), dir),
		14,
		3.2,
		"⚔️ 시험관과 대결",
		"송판 15장 먼저 격파 시 승리",
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
	for _, d in Layout.doors(world) do
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
		local lintel = Build.part(
			model,
			"Block",
			Vector3.new(10, 1.4, 1.6),
			cf * CFrame.new(0, 10.4, 0),
			theme.trim,
			M.Wood,
			{ collide = true, query = true, name = "Lintel" }
		)
		-- 문보다 큰 거인도 문 위 들보에 안 끼임 (사장님 결정 13·15번 — 문 칸에 들어가면 바로 이동)
		Build.giantPass(lintel)
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
	roof(world, lobby, theme)
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
