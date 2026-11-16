--!strict
--[[
	TargetLooks — 물건 41개 겉모습 (선임). 파트만으로, 물건마다 3~14 파트 (+ 맞히는 상자·받침대는 MapBuilder).
	  local height = TargetLooks.build(id, model, base, r)
	    base = 물건 바닥 가운데 CFrame (앞(-Z, LookVector)이 길 쪽), r = 바닥 반지름 (MapLayout.targetRadius)
	    반환 = 물건 꼭대기 높이 (base 위로, 머리 위 글 자리)
	모든 파트는 CanQuery = true (마우스로 눌러서 치기 — 모델의 ClickDetector 가 받음).
	다른 게임 그림을 베끼지 않고 이름 그대로 알아보게: 솜 = 흰 뭉치, 유리 = 반투명 판, 블랙홀 = 검은 구 + 빛나는 원반 …
]]

local Build = require(script.Parent.Build)

local TargetLooks = {}

local M = Enum.Material
local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = c(250, 250, 250)
local BLACK = c(25, 25, 30)
local GRAY = c(150, 150, 158)
local DARK = c(70, 72, 80)
local WOOD = c(196, 148, 92)
local WATER = c(60, 140, 230)
local NEON_BLUE = c(90, 200, 255)

type Maker = (
	shape: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	ellipsoid: boolean?
) -> Part

type Look = (mk: Maker, r: number) -> number

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end
local function rot(x: number, y: number, z: number, rx: number, ry: number, rz: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
end

local LOOKS: { [string]: Look } = {}

------------------------------------------------------------------
-- 월드 1 태권도장 마을
------------------------------------------------------------------

-- 솜: 낮은 나무 받침 위 흰 뭉치 5개
LOOKS.cotton = function(mk, r)
	mk("Block", Vector3.new(r * 1.6, 0.6, r * 1.6), at(0, 0.3, 0), WOOD, M.Wood)
	local d = r * 0.9
	mk("Ball", Vector3.one * d * 1.2, at(0, 0.6 + d * 0.6, 0), WHITE, M.Fabric)
	mk("Ball", Vector3.one * d, at(-r * 0.45, 0.6 + d * 0.45, r * 0.2), WHITE, M.Fabric)
	mk("Ball", Vector3.one * d, at(r * 0.45, 0.6 + d * 0.45, -r * 0.15), WHITE, M.Fabric)
	mk("Ball", Vector3.one * d * 0.9, at(0.1, 0.6 + d * 1.15, r * 0.1), c(255, 248, 252), M.Fabric)
	mk("Ball", Vector3.one * d * 0.8, at(-r * 0.2, 0.6 + d * 0.35, -r * 0.45), WHITE, M.Fabric)
	return 0.6 + d * 1.6
end

-- 유리: 나무 틀에 끼운 반투명 하늘색 판 + 받침 다리 2개
LOOKS.glass = function(mk, r)
	local w, h = r * 1.5, r * 1.4
	local y0 = 1
	mk("Block", Vector3.new(w, h, 0.3), at(0, y0 + h / 2, 0), c(170, 225, 255), M.Glass, 0.45)
	mk("Block", Vector3.new(w + 0.6, 0.4, 0.6), at(0, y0 + h + 0.2, 0), WOOD, M.Wood)
	mk("Block", Vector3.new(w + 0.6, 0.4, 0.6), at(0, y0 - 0.2, 0), WOOD, M.Wood)
	mk("Block", Vector3.new(0.4, h, 0.6), at(-w / 2 - 0.1, y0 + h / 2, 0), WOOD, M.Wood)
	mk("Block", Vector3.new(0.4, h, 0.6), at(w / 2 + 0.1, y0 + h / 2, 0), WOOD, M.Wood)
	mk("Block", Vector3.new(0.8, 1, r * 1.2), at(-w / 2, 0.5, 0), WOOD, M.Wood)
	mk("Block", Vector3.new(0.8, 1, r * 1.2), at(w / 2, 0.5, 0), WOOD, M.Wood)
	mk("Block", Vector3.new(w * 0.25, h * 0.08, 0.1), rot(-w * 0.2, y0 + h * 0.75, -0.2, 0, 0, 35), WHITE, M.Neon, 0.3)
	return y0 + h + 0.4
end

-- 플라스틱: 회색 벽돌 2개 위에 알록달록 플라스틱 판 3장
LOOKS.plastic = function(mk, r)
	local w = r * 1.7
	mk("Block", Vector3.new(r * 0.5, 1.6, r * 1.2), at(-w * 0.38, 0.8, 0), GRAY, M.Concrete)
	mk("Block", Vector3.new(r * 0.5, 1.6, r * 1.2), at(w * 0.38, 0.8, 0), GRAY, M.Concrete)
	local colors = { c(255, 90, 160), c(80, 210, 240), c(255, 220, 60) }
	for i, col in colors do
		local p = mk("Block", Vector3.new(w, 0.45, r * 1.1), at(0, 1.6 + 0.25 + (i - 1) * 0.5, 0), col, M.SmoothPlastic)
		p.Reflectance = 0.15
	end
	return 3.4
end

-- 나무 송판: 두 기둥 + 가로대 사이에 세운 나무판 (가운데 깨질 금)
LOOKS.wood = function(mk, r)
	local w, h = r * 1.4, r * 1.2
	local y0 = 1.5
	mk("Block", Vector3.new(0.8, y0 + h + 0.8, 0.8), at(-w / 2 - 0.5, (y0 + h + 0.8) / 2, 0), c(120, 70, 40), M.Wood)
	mk("Block", Vector3.new(0.8, y0 + h + 0.8, 0.8), at(w / 2 + 0.5, (y0 + h + 0.8) / 2, 0), c(120, 70, 40), M.Wood)
	mk("Block", Vector3.new(w + 1.8, 0.6, 0.8), at(0, y0 + h + 0.5, 0), c(120, 70, 40), M.Wood)
	mk("Block", Vector3.new(w, h, 0.6), at(0, y0 + h / 2, 0), WOOD, M.WoodPlanks)
	mk("Block", Vector3.new(0.12, h * 0.8, 0.1), at(0, y0 + h / 2, -0.32), c(110, 70, 35), M.Wood)
	mk("Block", Vector3.new(w + 2.6, 0.5, r * 1.1), at(0, 0.25, 0), c(120, 70, 40), M.Wood)
	return y0 + h + 0.8
end

-- 철: 짙은 회색 철판 + 테두리 + 볼트 4개
LOOKS.iron = function(mk, r)
	local w, h = r * 1.4, r * 1.25
	local y0 = 1.2
	mk("Block", Vector3.new(w, h, 0.5), at(0, y0 + h / 2, 0), c(95, 98, 108), M.DiamondPlate)
	mk("Block", Vector3.new(w + 0.8, 0.5, 0.8), at(0, y0 + h, 0), DARK, M.Metal)
	mk("Block", Vector3.new(w + 0.8, 0.5, 0.8), at(0, y0, 0), DARK, M.Metal)
	mk("Block", Vector3.new(0.5, h, 0.8), at(-w / 2 - 0.15, y0 + h / 2, 0), DARK, M.Metal)
	mk("Block", Vector3.new(0.5, h, 0.8), at(w / 2 + 0.15, y0 + h / 2, 0), DARK, M.Metal)
	for _, p in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		mk(
			"Ball",
			Vector3.one * 0.5,
			at(p[1] * w * 0.38, y0 + h / 2 + p[2] * h * 0.36, -0.3),
			c(200, 200, 210),
			M.Metal
		)
	end
	mk("Block", Vector3.new(w + 1.6, y0, r * 1.1), at(0, y0 / 2, 0), DARK, M.Metal)
	return y0 + h + 0.3
end

-- 강철: 반짝이는 H 빔 3개를 쌓음
LOOKS.steel = function(mk, r)
	local len = r * 1.8
	local steel = c(200, 206, 216)
	for i = 0, 2 do
		local y = 0.4 + i * 1.5
		local z = (i - 1) * 0.15
		local top = mk("Block", Vector3.new(len, 0.25, 1.3), at(0, y + 1.1, z), steel, M.Metal)
		top.Reflectance = 0.25
		mk("Block", Vector3.new(len, 0.9, 0.25), at(0, y + 0.55, z), c(170, 176, 188), M.Metal)
		local bottom = mk("Block", Vector3.new(len, 0.25, 1.3), at(0, y, z), steel, M.Metal)
		bottom.Reflectance = 0.25
	end
	return 4.8
end

-- 고무: 세워 둔 커다란 타이어 + 휠 + 받침
LOOKS.rubber = function(mk, r)
	local d = r * 1.7
	mk("HCyl", Vector3.new(r * 0.9, d, d), rot(0, d / 2 + 0.3, 0, 0, 90, 0), BLACK, M.Rubber)
	mk("HCyl", Vector3.new(r * 0.95, d * 0.55, d * 0.55), rot(0, d / 2 + 0.3, 0, 0, 90, 0), c(170, 172, 180), M.Metal)
	mk(
		"HCyl",
		Vector3.new(r * 1, d * 0.18, d * 0.18),
		rot(0, d / 2 + 0.3, 0, 0, 90, 0),
		c(230, 70, 60),
		M.SmoothPlastic
	)
	mk("Block", Vector3.new(d * 0.8, 0.6, r * 1.2), at(0, 0.3, 0), c(60, 60, 66), M.Concrete)
	return d + 0.3
end

-- 컴퓨터: 모니터(파란 화면) + 받침 + 키보드 + 본체
LOOKS.computer = function(mk, r)
	local w = r * 1.3
	local h = w * 0.68
	local y0 = 2.6
	mk("Block", Vector3.new(r * 1.9, 1.4, r * 1.4), at(0, 0.7, 0), c(150, 110, 70), M.Wood)
	mk("Block", Vector3.new(1.2, 1.2, 0.8), at(0, 1.4 + 0.6, r * 0.3), DARK)
	mk("Block", Vector3.new(w, h, 0.6), at(0, y0 + h / 2, r * 0.3), BLACK)
	mk("Block", Vector3.new(w * 0.88, h * 0.82, 0.1), at(0, y0 + h / 2, r * 0.3 - 0.33), NEON_BLUE, M.Neon)
	mk("Block", Vector3.new(w * 0.7, 0.3, 1.6), at(0, 1.55, -r * 0.35), c(225, 225, 230))
	mk(
		"Block",
		Vector3.new(r * 0.45, h * 1.1, r * 0.9),
		at(r * 0.85 - r * 0.22, 1.4 + h * 0.55, r * 0.1),
		c(55, 58, 66)
	)
	mk("Block", Vector3.new(0.2, 0.2, 0.1), at(r * 0.63, 1.4 + h * 0.9, r * 0.1 - r * 0.45), c(80, 255, 120), M.Neon)
	return y0 + h
end

-- 핸드폰: 서 있는 커다란 스마트폰 (검은 몸 + 빛나는 화면 + 앱 아이콘 4개 + 카메라)
LOOKS.phone = function(mk, r)
	local w, h = r * 1.1, r * 2
	local y0 = 0.8
	mk("Block", Vector3.new(r * 1.4, 0.8, r * 1.1), at(0, 0.4, 0), DARK, M.Metal)
	mk("Block", Vector3.new(w, h, 0.8), rot(0, y0 + h / 2, 0.4, -8, 0, 0), BLACK)
	local screen = rot(0, y0 + h / 2, 0.4, -8, 0, 0) * at(0, 0, -0.42)
	mk("Block", Vector3.new(w * 0.86, h * 0.84, 0.05), screen, c(120, 90, 255), M.Neon)
	local icons = { c(255, 90, 90), c(80, 220, 120), c(255, 210, 60), c(80, 170, 255) }
	for i, col in icons do
		local ix = (if i % 2 == 1 then -1 else 1) * w * 0.2
		local iy = (if i <= 2 then 1 else 0) * h * 0.18 + h * 0.12
		mk("Block", Vector3.new(w * 0.24, w * 0.24, 0.06), screen * at(ix, iy, -0.05), col, M.SmoothPlastic)
	end
	mk("Ball", Vector3.one * w * 0.1, screen * at(0, h * 0.46, -0.02), c(30, 30, 40))
	return y0 + h
end

-- 육교: 기둥 2개 + 다리 바닥 + 난간 2줄 + 양쪽 계단(쐐기)
LOOKS.overpass = function(mk, r)
	local len = r * 1.9
	local h = r * 0.55
	local deck = c(110, 160, 210)
	mk("Block", Vector3.new(1.6, h, 2.6), at(-len * 0.3, h / 2, 0), GRAY, M.Concrete)
	mk("Block", Vector3.new(1.6, h, 2.6), at(len * 0.3, h / 2, 0), GRAY, M.Concrete)
	mk("Block", Vector3.new(len * 0.8, 0.8, r * 0.5), at(0, h + 0.4, 0), deck, M.Concrete)
	mk("Block", Vector3.new(len * 0.8, 1.6, 0.25), at(0, h + 1.6, -r * 0.25), c(240, 200, 60), M.Metal)
	mk("Block", Vector3.new(len * 0.8, 1.6, 0.25), at(0, h + 1.6, r * 0.25), c(240, 200, 60), M.Metal)
	mk("Wedge", Vector3.new(r * 0.5, h + 0.8, len * 0.2), rot(-len * 0.5, (h + 0.8) / 2, 0, 0, 90, 0), deck, M.Concrete)
	mk("Wedge", Vector3.new(r * 0.5, h + 0.8, len * 0.2), rot(len * 0.5, (h + 0.8) / 2, 0, 0, -90, 0), deck, M.Concrete)
	mk("Block", Vector3.new(len * 0.55, 0.1, r * 0.9), at(0, 0.05, 0), c(60, 60, 64), M.Asphalt)
	return h + 2.4
end

-- 줄줄이 창문 건물 (아파트·학교·백화점·고층 빌딩이 같이 씀)
local function building(
	mk: Maker,
	w: number,
	d: number,
	h: number,
	wall: Color3,
	window: Color3,
	rows: number,
	material: Enum.Material?
)
	mk("Block", Vector3.new(w, h, d), at(0, h / 2, 0), wall, material or M.Concrete)
	for i = 1, rows do
		local y = h * (i - 0.4) / rows
		mk("Block", Vector3.new(w * 0.84, h / rows * 0.4, 0.15), at(0, y, -d / 2 - 0.05), window, M.Glass, 0.15)
	end
end

-- 아파트: 높은 건물 + 창문 줄 6 + 옥상 물탱크 + 숫자 판
LOOKS.apartment = function(mk, r)
	local w, d, h = r * 1.3, r * 0.9, r * 2.4
	building(mk, w, d, h, c(235, 225, 205), c(120, 190, 240), 6)
	mk("Block", Vector3.new(w + 0.8, 0.6, d + 0.8), at(0, h + 0.3, 0), c(180, 80, 70))
	mk("VCyl", Vector3.new(r * 0.35, r * 0.3, 0), at(w * 0.25, h + 0.6 + r * 0.15, 0), c(90, 150, 220), M.Metal)
	mk("Block", Vector3.new(w * 0.3, h * 0.08, 0.2), at(-w * 0.3, h * 0.93, -d / 2 - 0.1), c(40, 90, 200))
	return h + 0.6 + r * 0.3
end

-- 학교: 넓은 2층 건물 + 가운데 시계탑 + 시계 + 깃대
LOOKS.school = function(mk, r)
	local w, d, h = r * 1.9, r * 0.9, r * 0.75
	building(mk, w, d, h, c(220, 120, 90), c(250, 240, 200), 2, M.Brick)
	mk("Block", Vector3.new(r * 0.5, h * 0.9, r * 0.5), at(0, h + h * 0.45, 0), c(220, 120, 90), M.Brick)
	mk(
		"Wedge",
		Vector3.new(r * 0.55, r * 0.3, r * 0.28),
		rot(0, h * 1.9 + r * 0.15, -r * 0.13, 0, 0, 0),
		c(80, 90, 120)
	)
	mk(
		"Wedge",
		Vector3.new(r * 0.55, r * 0.3, r * 0.28),
		rot(0, h * 1.9 + r * 0.15, r * 0.13, 0, 180, 0),
		c(80, 90, 120)
	)
	mk("HCyl", Vector3.new(0.3, r * 0.35, r * 0.35), rot(0, h * 1.5, -r * 0.26, 0, 90, 0), WHITE)
	mk("Block", Vector3.new(0.25, r * 0.12, 0.1), rot(0, h * 1.5 + r * 0.04, -r * 0.43, 0, 0, 0), BLACK)
	mk("VCyl", Vector3.new(0.3, h * 2.2, 0), at(w * 0.45, h * 1.1, -d * 0.7), c(200, 200, 205), M.Metal)
	mk("Block", Vector3.new(r * 0.3, r * 0.18, 0.1), at(w * 0.45 - r * 0.15, h * 2.1, -d * 0.7), c(60, 140, 255))
	return h * 1.9 + r * 0.3
end

-- 경기장: 둥근 관중석 + 초록 잔디 + 조명탑 4개
LOOKS.stadium = function(mk, r)
	local d = r * 1.9
	mk("VCyl", Vector3.new(d, r * 0.4, 0), at(0, r * 0.2, 0), c(200, 205, 215), M.Concrete)
	mk("VCyl", Vector3.new(d * 0.97, r * 0.06, 0), at(0, r * 0.4, 0), c(230, 70, 80))
	mk("VCyl", Vector3.new(d * 0.7, r * 0.42, 0), at(0, r * 0.215, 0), c(80, 190, 80), M.Grass)
	mk("Block", Vector3.new(d * 0.4, 0.1, 0.25), at(0, r * 0.44, 0), WHITE)
	mk("VCyl", Vector3.new(d * 0.14, 0.12, 0), at(0, r * 0.44, 0), WHITE, nil, 0.3)
	for _, s in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x, z = s[1] * d * 0.36, s[2] * d * 0.36
		mk("VCyl", Vector3.new(0.5, r * 0.9, 0), at(x, r * 0.45, z), GRAY, M.Metal)
		mk("Block", Vector3.new(1.6, 1, 0.4), at(x, r * 0.9, z), c(255, 250, 200), M.Neon)
	end
	return r * 0.9 + 0.5
end

------------------------------------------------------------------
-- 월드 2 지구 한 바퀴
------------------------------------------------------------------

-- 백화점: 넓은 건물 + 유리 앞면 + 알록달록 간판 띠 + 입구 차양
LOOKS.mall = function(mk, r)
	local w, d, h = r * 1.9, r * 1, r * 0.9
	mk("Block", Vector3.new(w, h, d), at(0, h / 2, 0), c(245, 240, 230), M.Concrete)
	mk("Block", Vector3.new(w * 0.9, h * 0.55, 0.2), at(0, h * 0.35, -d / 2 - 0.05), c(150, 210, 245), M.Glass, 0.2)
	mk("Block", Vector3.new(w * 0.95, h * 0.16, 0.4), at(0, h * 0.82, -d / 2 - 0.15), c(255, 80, 140))
	mk("Block", Vector3.new(w * 0.3, h * 0.1, 0.1), at(0, h * 0.82, -d / 2 - 0.4), c(255, 240, 120), M.Neon)
	mk("Wedge", Vector3.new(w * 0.35, 0.8, r * 0.35), rot(0, h * 0.62, -d / 2 - r * 0.17, 0, 180, 0), c(255, 170, 60))
	mk("Block", Vector3.new(w * 0.5, h * 0.25, d * 0.5), at(w * 0.15, h + h * 0.125, 0), c(225, 220, 210), M.Concrete)
	mk("VCyl", Vector3.new(r * 0.3, 0.4, 0), at(-w * 0.3, h + 0.2, 0), c(80, 200, 255), M.Glass, 0.3)
	return h * 1.25
end

-- 고층 빌딩: 아주 높은 유리 탑 + 위로 갈수록 좁아짐 + 뾰족 안테나 + 빨간 불
LOOKS.skyscraper = function(mk, r)
	local w, h = r * 1.1, r * 3.4
	local glass = c(90, 160, 215)
	local p = mk("Block", Vector3.new(w, h * 0.6, w), at(0, h * 0.3, 0), glass, M.Glass, 0.05)
	p.Reflectance = 0.2
	mk("Block", Vector3.new(w * 0.8, h * 0.3, w * 0.8), at(0, h * 0.75, 0), c(110, 180, 225), M.Glass, 0.05)
	mk("Block", Vector3.new(w * 0.55, h * 0.1, w * 0.55), at(0, h * 0.95, 0), c(130, 195, 235), M.Glass)
	for i = 1, 4 do
		mk("Block", Vector3.new(w + 0.2, 0.3, w + 0.2), at(0, h * 0.6 * i / 5, 0), c(220, 225, 235), M.Metal)
	end
	mk("VCyl", Vector3.new(0.5, r * 0.6, 0), at(0, h + r * 0.3, 0), c(200, 200, 210), M.Metal)
	mk("Ball", Vector3.one * 0.9, at(0, h + r * 0.6, 0), c(255, 40, 40), M.Neon)
	return h + r * 0.6
end

-- 대교: 물 위 긴 다리 + 높은 탑 2개 + 비스듬한 줄 4개
LOOKS.bridge = function(mk, r)
	local len = r * 1.95
	local h = r * 0.35
	local red = c(210, 60, 50)
	mk("Block", Vector3.new(len, 0.3, r * 0.9), at(0, 0.15, 0), WATER, M.Glass, 0.2)
	mk("Block", Vector3.new(len, 0.9, r * 0.35), at(0, h, 0), c(90, 95, 105), M.Concrete)
	for _, sx in { -1, 1 } do
		local tx = sx * len * 0.27
		mk("Block", Vector3.new(1.4, r * 1.2, 1.4), at(tx, r * 0.6, 0), red, M.Metal)
		local cx = tx + sx * len * 0.12
		local length = math.sqrt((len * 0.24) ^ 2 + (r * 1.1 - h) ^ 2)
		local angle = math.deg(math.atan2(r * 1.1 - h, len * 0.24))
		mk("Block", Vector3.new(length, 0.25, 0.25), rot(cx, (r * 1.1 + h) / 2, 0, 0, 0, -sx * angle), WHITE, M.Metal)
		mk(
			"Block",
			Vector3.new(length, 0.25, 0.25),
			rot(tx - sx * len * 0.12, (r * 1.1 + h) / 2, 0, 0, 0, sx * angle),
			WHITE,
			M.Metal
		)
	end
	mk("Block", Vector3.new(len, 0.4, 0.3), at(0, h + 0.7, -r * 0.17), c(240, 200, 60))
	return r * 1.2
end

-- 댐: 두꺼운 콘크리트 벽(앞은 비스듬) + 뒤쪽 물 + 하얀 물보라 3줄
LOOKS.dam = function(mk, r)
	local w, h = r * 1.9, r * 1.1
	mk("Block", Vector3.new(w, h, r * 0.35), at(0, h / 2, r * 0.1), c(185, 185, 180), M.Concrete)
	mk("Wedge", Vector3.new(w, h, r * 0.45), rot(0, h / 2, -r * 0.3, 0, 180, 0), c(170, 170, 165), M.Concrete)
	mk("Block", Vector3.new(w, h * 0.85, r * 0.6), at(0, h * 0.425, r * 0.6), WATER, M.Glass, 0.25)
	for i = -1, 1 do
		mk(
			"Block",
			Vector3.new(r * 0.18, h * 0.9, 0.3),
			rot(i * w * 0.25, h * 0.5, -r * 0.5, -24, 0, 0),
			WHITE,
			M.Neon,
			0.35
		)
	end
	mk("Block", Vector3.new(w + 0.4, 0.6, r * 0.45), at(0, h + 0.3, r * 0.1), c(150, 150, 150), M.Concrete)
	return h + 0.6
end

-- 비행기: 흰 몸통 + 둥근 코 + 날개 + 꼬리 날개 + 엔진 2개 + 창문 줄
LOOKS.airplane = function(mk, r)
	local len = r * 1.8
	local d = r * 0.32
	local y = d / 2 + 1.5
	mk("HCyl", Vector3.new(len, d, d), at(0, y, 0), WHITE)
	mk("Ball", Vector3.one * d, at(len / 2, y, 0), WHITE)
	mk("Block", Vector3.new(r * 0.45, 0.4, len * 0.95), at(0, y - d * 0.15, 0), c(220, 225, 235))
	mk("Wedge", Vector3.new(0.4, d * 1.4, r * 0.4), rot(-len / 2 + r * 0.2, y + d * 0.9, 0, 0, 90, 0), c(40, 110, 220))
	mk("Block", Vector3.new(r * 0.25, 0.3, r * 0.6), at(-len / 2 + r * 0.12, y + 0.2, 0), c(220, 225, 235))
	mk("HCyl", Vector3.new(r * 0.3, d * 0.45, d * 0.45), at(0, y - d * 0.5, -len * 0.22), GRAY, M.Metal)
	mk("HCyl", Vector3.new(r * 0.3, d * 0.45, d * 0.45), at(0, y - d * 0.5, len * 0.22), GRAY, M.Metal)
	mk(
		"Block",
		Vector3.new(len * 0.7, d * 0.12, d * 1.02),
		at(len * 0.05, y + d * 0.15, 0),
		c(60, 120, 200),
		M.Glass,
		0.1
	)
	mk("Block", Vector3.new(0.6, 1.5, 0.6), at(len * 0.25, 0.75, 0), BLACK, M.Rubber)
	mk("Block", Vector3.new(0.6, 1.5, 0.6), at(-len * 0.1, 0.75, 0), BLACK, M.Rubber)
	return y + d * 1.6
end

-- 항공모함: 회색 배 + 뾰족한 뱃머리 + 짙은 갑판 + 지휘탑 + 갑판 선 + 작은 비행기
LOOKS.carrier = function(mk, r)
	local len = r * 1.7
	local w = r * 0.55
	local h = r * 0.3
	mk("Block", Vector3.new(len, h, w), at(-r * 0.1, h / 2, 0), c(120, 125, 135), M.Metal)
	mk("Wedge", Vector3.new(w, h, r * 0.35), rot(len / 2 + r * 0.07, h / 2, 0, 0, -90, 0), c(120, 125, 135), M.Metal)
	mk("Block", Vector3.new(len + r * 0.2, 0.3, w * 1.25), at(0, h + 0.15, 0), c(70, 74, 82), M.Asphalt)
	mk("Block", Vector3.new(len * 0.9, 0.05, 0.3), at(0, h + 0.32, 0), WHITE, M.Neon, 0.2)
	mk(
		"Block",
		Vector3.new(r * 0.25, r * 0.4, w * 0.25),
		at(-r * 0.1, h + r * 0.2, w * 0.45),
		c(150, 155, 165),
		M.Metal
	)
	mk("VCyl", Vector3.new(0.3, r * 0.25, 0), at(-r * 0.1, h + r * 0.5, w * 0.45), c(200, 200, 210), M.Metal)
	mk("Block", Vector3.new(r * 0.2, 0.25, r * 0.22), at(r * 0.35, h + 0.45, -w * 0.15), c(200, 205, 215))
	mk("Block", Vector3.new(len + r * 0.3, 0.3, w * 1.6), at(0, 0.15, 0), WATER, M.Glass, 0.3)
	return h + r * 0.6
end

-- 전망탑: 세운 기둥 + 둥근 전망대 + 위 공 + 안테나 + 받침
LOOKS.tower = function(mk, r)
	local h = r * 3.2
	local white = c(240, 240, 245)
	mk("VCyl", Vector3.new(r * 0.9, r * 0.4, 0), at(0, r * 0.2, 0), c(180, 180, 190), M.Concrete)
	mk("VCyl", Vector3.new(r * 0.3, h * 0.7, 0), at(0, h * 0.35, 0), white, M.Concrete)
	mk("VCyl", Vector3.new(r * 1.0, r * 0.3, 0), at(0, h * 0.7, 0), c(255, 120, 80))
	mk("VCyl", Vector3.new(r * 0.95, r * 0.12, 0), at(0, h * 0.7 + r * 0.05, 0), c(140, 210, 250), M.Glass, 0.2)
	mk("Ball", Vector3.one * r * 0.5, at(0, h * 0.82, 0), white)
	mk("VCyl", Vector3.new(0.4, h * 0.2, 0), at(0, h * 0.92, 0), c(200, 200, 210), M.Metal)
	mk("Ball", Vector3.one * 0.8, at(0, h * 1.02, 0), c(255, 50, 50), M.Neon)
	return h * 1.02
end

-- 피라미드: 모래색 계단 5단 + 금빛 꼭대기
LOOKS.pyramid = function(mk, r)
	local step = r * 0.32
	local sand = c(222, 190, 120)
	for i = 0, 4 do
		local s = r * 1.85 * (1 - i * 0.18)
		mk(
			"Block",
			Vector3.new(s, step, s),
			at(0, step * (i + 0.5), 0),
			sand:Lerp(c(255, 230, 170), i * 0.05),
			M.Sandstone
		)
	end
	mk("Block", Vector3.new(r * 0.3, step, r * 0.3), at(0, step * 5.5, 0), c(255, 210, 60), M.Neon)
	mk("Block", Vector3.new(r * 0.25, r * 0.35, 0.2), at(0, r * 0.18, -r * 0.93), c(90, 60, 30))
	return step * 6
end

-- 산: 회색 바위 봉우리 3개 (쐐기 2개씩) + 흰 눈 모자 + 초록 아래쪽
local function peak(mk: Maker, x: number, z: number, w: number, h: number, rock: Color3, snow: boolean)
	mk("Wedge", Vector3.new(w, h, w / 2), rot(x, h / 2, z - w / 4, 0, 180, 0), rock, M.Slate)
	mk("Wedge", Vector3.new(w, h, w / 2), rot(x, h / 2, z + w / 4, 0, 0, 0), rock, M.Slate)
	if snow then
		local sh = h * 0.28
		mk("Wedge", Vector3.new(w * 0.3, sh, w * 0.15), rot(x, h - sh / 2, z - w * 0.075, 0, 180, 0), WHITE, M.Snow)
		mk("Wedge", Vector3.new(w * 0.3, sh, w * 0.15), rot(x, h - sh / 2, z + w * 0.075, 0, 0, 0), WHITE, M.Snow)
	end
end

LOOKS.mountain = function(mk, r)
	local h = r * 1.5
	peak(mk, 0, 0, r * 1.5, h, c(130, 130, 135), true)
	peak(mk, -r * 0.5, r * 0.3, r * 1.0, h * 0.65, c(115, 118, 120), true)
	peak(mk, r * 0.55, r * 0.25, r * 0.9, h * 0.55, c(120, 125, 118), false)
	mk("VCyl", Vector3.new(r * 1.9, 0.6, 0), at(0, 0.3, 0), c(90, 160, 80), M.Grass)
	return h
end

-- 화산: 갈색 산 + 빨갛게 빛나는 분화구 + 흘러내리는 용암 + 연기 구름
LOOKS.volcano = function(mk, r)
	local h = r * 1.3
	peak(mk, 0, 0, r * 1.8, h, c(110, 70, 50), false)
	mk("Block", Vector3.new(r * 0.45, 0.6, r * 0.35), at(0, h * 0.86, 0), c(255, 90, 30), M.Neon)
	mk("Block", Vector3.new(r * 0.12, h * 0.62, 0.3), rot(0, h * 0.5, -r * 0.26, 41, 0, 0), c(255, 120, 30), M.Neon)
	mk("Ball", Vector3.one * r * 0.45, at(0, h + r * 0.3, 0), c(110, 110, 115), M.SmoothPlastic, 0.2)
	mk("Ball", Vector3.one * r * 0.35, at(r * 0.25, h + r * 0.55, 0), c(140, 140, 145), M.SmoothPlastic, 0.3)
	mk("Ball", Vector3.one * r * 0.3, at(-r * 0.2, h + r * 0.7, 0), c(160, 160, 165), M.SmoothPlastic, 0.4)
	mk("VCyl", Vector3.new(r * 1.95, 0.5, 0), at(0, 0.25, 0), c(60, 40, 35), M.Basalt)
	return h + r * 0.9
end

-- 빙하: 물 위에 비스듬히 솟은 얼음 덩어리 5개
LOOKS.glacier = function(mk, r)
	mk("VCyl", Vector3.new(r * 1.95, 0.5, 0), at(0, 0.25, 0), c(60, 120, 200), M.Glass, 0.25)
	local ice = c(190, 230, 255)
	mk("Block", Vector3.new(r * 0.9, r * 1.2, r * 0.8), rot(0, r * 0.6, 0, 0, 15, 8), ice, M.Ice, 0.1)
	mk(
		"Block",
		Vector3.new(r * 0.6, r * 0.8, r * 0.6),
		rot(-r * 0.55, r * 0.4, r * 0.2, 0, -20, -10),
		c(170, 220, 250),
		M.Ice,
		0.1
	)
	mk(
		"Block",
		Vector3.new(r * 0.5, r * 0.6, r * 0.5),
		rot(r * 0.55, r * 0.3, -r * 0.2, 6, 30, 12),
		c(210, 240, 255),
		M.Ice,
		0.1
	)
	mk("Wedge", Vector3.new(r * 0.7, r * 0.5, r * 0.6), rot(r * 0.1, r * 1.4, 0, 0, 15, 0), WHITE, M.Snow)
	mk("Block", Vector3.new(r * 0.4, r * 0.35, r * 0.4), rot(-r * 0.1, r * 0.17, -r * 0.6, 0, 40, 0), ice, M.Ice, 0.15)
	return r * 1.65
end

-- 섬: 파란 바다 원판 + 모래 섬 + 풀 + 야자나무(줄기 + 잎 4장 + 코코넛)
LOOKS.island = function(mk, r)
	mk("VCyl", Vector3.new(r * 1.95, 0.4, 0), at(0, 0.2, 0), WATER, M.Glass, 0.2)
	mk("VCyl", Vector3.new(r * 1.2, 0.8, 0), at(0, 0.6, 0), c(240, 215, 150), M.Sand)
	mk("VCyl", Vector3.new(r * 0.7, 0.9, 0), at(r * 0.1, 0.75, 0), c(90, 190, 80), M.Grass)
	local h = r * 0.9
	mk("Block", Vector3.new(0.9, h, 0.9), rot(-r * 0.05, 1 + h / 2, 0, 0, 0, -8), c(140, 95, 55), M.Wood)
	local top = 1 + h
	for i = 0, 3 do
		local a = i * 90
		mk(
			"Block",
			Vector3.new(r * 0.55, 0.25, r * 0.18),
			rot(-r * 0.12, top, 0, 0, a, -20) * at(r * 0.24, 0, 0),
			c(60, 170, 70),
			M.Grass
		)
	end
	mk("Ball", Vector3.one * 0.9, at(-r * 0.12, top - 0.6, 0.4), c(110, 70, 40))
	return top + 1
end

-- 대륙: 바다 위 크고 울퉁불퉁한 땅 (초록·갈색 판을 비스듬히 겹침) + 작은 산
LOOKS.continent = function(mk, r)
	mk("VCyl", Vector3.new(r * 1.95, 0.4, 0), at(0, 0.2, 0), WATER, M.Glass, 0.2)
	local green = c(90, 175, 80)
	mk("Block", Vector3.new(r * 1.1, 1.2, r * 0.7), rot(-r * 0.1, 0.8, -r * 0.1, 0, 20, 0), green, M.Grass)
	mk("Block", Vector3.new(r * 0.7, 1.1, r * 0.6), rot(r * 0.35, 0.75, r * 0.3, 0, -35, 0), c(110, 185, 85), M.Grass)
	mk(
		"Block",
		Vector3.new(r * 0.6, 1.0, r * 0.45),
		rot(-r * 0.45, 0.7, r * 0.35, 0, 60, 0),
		c(190, 160, 100),
		M.Ground
	)
	mk("Block", Vector3.new(r * 0.45, 1.0, r * 0.5), rot(r * 0.2, 0.7, -r * 0.5, 0, 10, 0), c(200, 175, 110), M.Sand)
	peak(mk, -r * 0.1, -r * 0.05, r * 0.5, r * 0.45, c(120, 110, 100), true)
	return r * 0.45
end

-- 바다: 큰 파란 물 원판 + 하얀 물결 3줄 + 고래(몸 + 꼬리) + 물기둥
LOOKS.ocean = function(mk, r)
	mk("VCyl", Vector3.new(r * 1.95, 1, 0), at(0, 0.5, 0), c(40, 110, 210), M.Glass, 0.15)
	for i = -1, 1 do
		mk(
			"Block",
			Vector3.new(r * 1.1, 0.25, 0.6),
			rot(i * r * 0.2, 1.05, i * r * 0.5, 0, 10, 0),
			WHITE,
			M.SmoothPlastic,
			0.2
		)
	end
	mk("Ball", Vector3.new(r * 0.9, r * 0.45, r * 0.45), at(0, 1, 0), c(60, 80, 140), M.SmoothPlastic, nil, true)
	mk("Wedge", Vector3.new(0.6, r * 0.3, r * 0.4), rot(-r * 0.55, 1 + r * 0.15, 0, 0, 90, 0), c(60, 80, 140))
	mk("VCyl", Vector3.new(0.6, r * 0.35, 0), at(r * 0.2, 1 + r * 0.35, 0), c(200, 230, 255), M.Neon, 0.4)
	return 1 + r * 0.55
end

------------------------------------------------------------------
-- 월드 3 우주 (MapBuilder 가 떠 있는 받침대를 따로 놓음)
------------------------------------------------------------------

local function planet(mk: Maker, r: number, scale: number, color: Color3, material: Enum.Material?): (number, number)
	local d = r * 1.8 * scale
	local cy = d / 2 + 0.3
	mk("Ball", Vector3.one * d, at(0, cy, 0), color, material or M.SmoothPlastic)
	return d, cy
end

LOOKS.moon = function(mk, r)
	local d, cy = planet(mk, r, 1, c(200, 200, 205), M.Slate)
	mk("Ball", Vector3.one * d * 0.22, at(-d * 0.2, cy + d * 0.15, -d * 0.4), c(150, 150, 158), M.Slate)
	mk("Ball", Vector3.one * d * 0.16, at(d * 0.25, cy - d * 0.1, -d * 0.41), c(160, 160, 168), M.Slate)
	mk("Ball", Vector3.one * d * 0.12, at(0, cy + d * 0.38, -d * 0.22), c(155, 155, 160), M.Slate)
	return cy + d / 2
end

LOOKS.mercury = function(mk, r)
	local d, cy = planet(mk, r, 0.8, c(160, 140, 120), M.Slate)
	mk("Ball", Vector3.one * d * 0.2, at(d * 0.18, cy + d * 0.1, -d * 0.42), c(120, 105, 92), M.Slate)
	mk("Ball", Vector3.one * d * 0.14, at(-d * 0.22, cy - d * 0.2, -d * 0.4), c(130, 112, 98), M.Slate)
	return cy + d / 2
end

LOOKS.mars = function(mk, r)
	local d, cy = planet(mk, r, 0.9, c(210, 90, 50), M.Sandstone)
	mk("Ball", Vector3.one * d * 0.35, at(0, cy + d * 0.38, 0), WHITE, M.Snow)
	mk("Ball", Vector3.one * d * 0.22, at(-d * 0.2, cy, -d * 0.4), c(170, 70, 40), M.Sandstone)
	return cy + d / 2
end

LOOKS.venus = function(mk, r)
	local d, cy = planet(mk, r, 0.95, c(235, 190, 110))
	mk("VCyl", Vector3.new(d * 1.02, d * 0.14, 0), at(0, cy + d * 0.12, 0), c(250, 220, 160), M.SmoothPlastic, 0.2)
	mk("VCyl", Vector3.new(d * 1.02, d * 0.1, 0), at(0, cy - d * 0.18, 0), c(215, 165, 90), M.SmoothPlastic, 0.2)
	return cy + d / 2
end

LOOKS.earth = function(mk, r)
	local d, cy = planet(mk, r, 1, c(50, 120, 230))
	mk(
		"Ball",
		Vector3.new(d * 0.5, d * 0.35, d * 0.2),
		rot(-d * 0.15, cy + d * 0.1, -d * 0.4, 0, 20, 0),
		c(80, 180, 80),
		M.Grass,
		nil,
		true
	)
	mk(
		"Ball",
		Vector3.new(d * 0.35, d * 0.45, d * 0.2),
		rot(d * 0.25, cy - d * 0.12, -d * 0.36, 0, -30, 0),
		c(90, 170, 70),
		M.Grass,
		nil,
		true
	)
	mk("Ball", Vector3.new(d * 0.6, d * 0.12, d * 0.6), at(0, cy + d * 0.44, 0), WHITE, M.Snow, nil, true)
	mk("Ball", Vector3.one * d * 1.06, at(0, cy, 0), c(200, 230, 255), M.SmoothPlastic, 0.8)
	return cy + d / 2
end

LOOKS.neptune = function(mk, r)
	local d, cy = planet(mk, r, 1.05, c(40, 70, 200))
	mk(
		"Ball",
		Vector3.new(d * 0.3, d * 0.18, d * 0.15),
		at(d * 0.1, cy + d * 0.1, -d * 0.45),
		c(20, 40, 120),
		nil,
		nil,
		true
	)
	mk("VCyl", Vector3.new(d * 1.01, d * 0.06, 0), at(0, cy - d * 0.15, 0), c(90, 130, 240), M.SmoothPlastic, 0.3)
	return cy + d / 2
end

LOOKS.uranus = function(mk, r)
	local d, cy = planet(mk, r, 0.55, c(140, 220, 230))
	-- 옆으로 누운 고리 (천왕성은 세로 고리)
	mk("HCyl", Vector3.new(0.2, d * 1.7, d * 1.7), rot(0, cy, 0, 0, 0, 0), c(200, 240, 245), M.Neon, 0.6)
	mk("HCyl", Vector3.new(0.25, d * 1.35, d * 1.35), rot(0, cy, 0, 0, 0, 0), c(160, 220, 230), M.SmoothPlastic, 0.5)
	return cy + d * 0.85
end

LOOKS.saturn = function(mk, r)
	local d, cy = planet(mk, r, 0.5, c(225, 195, 130))
	mk("VCyl", Vector3.new(d * 2.1, 0.25, 0), rot(0, cy, 0, 12, 0, 0), c(210, 180, 120), M.SmoothPlastic, 0.25)
	mk("VCyl", Vector3.new(d * 1.6, 0.3, 0), rot(0, cy, 0, 12, 0, 0), c(240, 220, 170), M.SmoothPlastic, 0.1)
	mk("VCyl", Vector3.new(d * 1.01, d * 0.1, 0), at(0, cy + d * 0.25, 0), c(200, 165, 105))
	return cy + d / 2
end

LOOKS.jupiter = function(mk, r)
	local d, cy = planet(mk, r, 1.05, c(220, 160, 110))
	mk("VCyl", Vector3.new(d * 1.01, d * 0.12, 0), at(0, cy + d * 0.22, 0), c(180, 110, 70))
	mk("VCyl", Vector3.new(d * 1.01, d * 0.1, 0), at(0, cy - d * 0.05, 0), c(240, 210, 170))
	mk("VCyl", Vector3.new(d * 1.01, d * 0.12, 0), at(0, cy - d * 0.28, 0), c(170, 100, 60))
	mk(
		"Ball",
		Vector3.new(d * 0.24, d * 0.14, d * 0.12),
		at(d * 0.15, cy - d * 0.16, -d * 0.45),
		c(200, 60, 40),
		nil,
		nil,
		true
	)
	return cy + d / 2
end

LOOKS.sun = function(mk, r)
	local d, cy = planet(mk, r, 0.85, c(255, 210, 50), M.Neon)
	mk("Ball", Vector3.one * d * 1.25, at(0, cy, 0), c(255, 140, 30), M.Neon, 0.7)
	local core = mk("Ball", Vector3.one * d * 0.5, at(0, cy, -d * 0.3), c(255, 250, 200), M.Neon, 0.4)
	Build.light(core, c(255, 220, 120), r * 3, 3)
	return cy + d * 0.62
end

-- 태양계: 가운데 작은 태양 + 궤도 고리 3개 + 행성 4개
LOOKS.solar_system = function(mk, r)
	local cy = r * 0.6
	mk("Ball", Vector3.one * r * 0.4, at(0, cy, 0), c(255, 210, 50), M.Neon)
	local planets = { c(160, 140, 120), c(50, 120, 230), c(210, 90, 50), c(225, 195, 130) }
	for i = 1, 3 do
		mk("VCyl", Vector3.new(r * (0.6 + i * 0.4), 0.12, 0), at(0, cy, 0), c(180, 190, 255), M.Neon, 0.75)
	end
	for i, col in planets do
		local orbit = r * (0.3 + math.min(i, 3) * 0.2)
		local a = math.rad(i * 95)
		mk("Ball", Vector3.one * r * (0.12 + i * 0.03), at(math.cos(a) * orbit, cy, math.sin(a) * orbit), col)
	end
	mk("VCyl", Vector3.new(r * 0.65, 0.2, 0), at(r * 0.0, cy, 0), c(255, 170, 60), M.Neon, 0.7)
	return cy + r * 0.3
end

-- 은하: 보라색 반투명 원판 + 빛나는 가운데 + 휘어진 팔 6개
LOOKS.galaxy = function(mk, r)
	local cy = r * 0.5
	local tilt = CFrame.new(0, cy, 0) * CFrame.Angles(math.rad(-18), 0, 0)
	local disc = mk("VCyl", Vector3.new(r * 1.9, 0.3, 0), tilt, c(110, 60, 200), M.Neon, 0.75)
	disc.Name = "Disc"
	mk("Ball", Vector3.new(r * 0.5, r * 0.25, r * 0.5), tilt, c(255, 240, 200), M.Neon, nil, true)
	for i = 0, 5 do
		local a = i * 60
		local arm = tilt
			* CFrame.Angles(0, math.rad(a), 0)
			* CFrame.new(r * 0.45, 0, r * 0.12)
			* CFrame.Angles(0, math.rad(-35), 0)
		local col = if i % 2 == 0 then c(200, 150, 255) else c(140, 200, 255)
		mk("Block", Vector3.new(r * 0.6, 0.35, r * 0.1), arm, col, M.Neon, 0.25)
	end
	return cy + r * 0.45
end

-- 블랙홀: 새까만 구 + 주황으로 빛나는 원반 + 바깥 보라 고리
LOOKS.black_hole = function(mk, r)
	local d = r * 1.0
	local cy = r * 0.7
	local tilt = CFrame.new(0, cy, 0) * CFrame.Angles(math.rad(15), 0, math.rad(8))
	mk("VCyl", Vector3.new(r * 1.9, 0.35, 0), tilt, c(170, 80, 255), M.Neon, 0.55)
	mk("VCyl", Vector3.new(r * 1.5, 0.45, 0), tilt, c(255, 140, 40), M.Neon, 0.1)
	mk("VCyl", Vector3.new(d * 1.15, 0.6, 0), tilt, c(255, 230, 150), M.Neon)
	mk("Ball", Vector3.one * d, at(0, cy, 0), c(5, 5, 8), M.SmoothPlastic)
	return cy + d * 0.7
end

-- 우주: 커다란 반투명 남색 구 안에 작은 은하·별 공들
LOOKS.universe = function(mk, r)
	local d = r * 1.85
	local cy = d / 2 + 0.3
	mk("Ball", Vector3.one * d, at(0, cy, 0), c(30, 20, 90), M.Glass, 0.55)
	local inner: { { p: Vector3, color: Color3 } } = {
		{ p = Vector3.new(0.2, 0.15, -0.1), color = c(255, 120, 200) },
		{ p = Vector3.new(-0.25, -0.1, 0.15), color = c(120, 200, 255) },
		{ p = Vector3.new(0.05, -0.25, -0.2), color = c(255, 230, 120) },
		{ p = Vector3.new(-0.1, 0.28, 0.2), color = c(180, 120, 255) },
		{ p = Vector3.new(0.28, -0.05, 0.22), color = c(120, 255, 180) },
		{ p = Vector3.new(-0.3, 0.1, -0.25), color = c(255, 160, 90) },
	}
	for _, s in inner do
		mk("Ball", Vector3.one * r * 0.18, at(s.p.X * d, cy + s.p.Y * d, s.p.Z * d), s.color, M.Neon, 0.1)
	end
	mk("VCyl", Vector3.new(d * 0.45, 0.2, 0), rot(0, cy, 0, 20, 0, 10), c(220, 180, 255), M.Neon, 0.4)
	mk("Ball", Vector3.one * d * 1.08, at(0, cy, 0), c(150, 120, 255), M.ForceField, 0.3)
	return cy + d / 2
end

------------------------------------------------------------------

function TargetLooks.has(id: string): boolean
	return LOOKS[id] ~= nil
end

-- 물건 모양을 model 안에 만들고 꼭대기 높이를 돌려줌 (모르는 id 는 물음표 상자)
function TargetLooks.build(id: string, model: Model, base: CFrame, r: number): number
	local mk: Maker = function(shape, size, cf, color, material, transparency, ellipsoid)
		return Build.part(model, shape, size, base * cf, color, material, {
			collide = true,
			query = true,
			transparency = transparency,
			ellipsoid = ellipsoid,
			name = "Look",
		})
	end
	local look = LOOKS[id]
	if look then
		return look(mk, r)
	end
	mk("Block", Vector3.new(r, r, r), at(0, r / 2, 0), c(255, 200, 60))
	return r
end

return TargetLooks
