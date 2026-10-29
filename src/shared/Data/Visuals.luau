--!strict
--[[
	Visuals — 생김새 데이터 (색·체형·장식·구역 테마). 순수 데이터 (로블록스 API 없음).

	선임 담당. 서버 PetVisualService / EggVisualService / MapBuilder 와 클라 연출이 읽습니다.

	6판 "씨앗을 훔치세요" (선임):
	  - 식물 134종 생김새 = 구역 테마(plantThemes) + 이름 낱말(FORM_WORDS) + id 해시 → Visuals.plantLook(id)
	    (PlantVisualService 가 모양 16종 PLANT_FORMS 로 만듦). 대표 색 Visuals.petColor(id, 1~3) = 꽃잎·잎·열매.
	  - 경비 15종(+ 어두운 쪽 1) = 식물 괴물 (Visuals.monsters + Visuals.guards, PetVisualService.buildMonster).
	  - 등급 아우라 11종 (Visuals.auras, 이름 = Rarities.aura), 돌연변이 겉모습 (mutationLooks, 원소 3종 effect).
	7판 (수석 임시, `[7판 수석 임시]` 주석): 등급 16개·구역 18개가 안 깨지게 새 칸만 채워 둠 — 아우라 5개(code_rain ·
	  first_light · build_grid · ultra_halo · glitch_static)·씨앗 껍데기·특별 씨앗 글자·새 구역 테마 3개·식물 색 3개·
	  새 경비 3마리(옛 괴물 모양을 빌림). 진짜 모양은 선임 (docs/REMOTES.md 8장 7판 체크리스트).
	  - 씨앗 껍데기 (eggLooks, EggVisualService: 아몬드 모양 + 등급 줄무늬).
	색은 RGB 0~255 배열. Material 은 Enum.Material 이름(문자열).

	4판 비주얼: 구역 테마에 바닥 무늬(pattern)·가운데 길(path)·가운데 작은 장식(scatter)·담장 면 장식(wallDecor)·
	입구 아치(arch)·담장 기둥 색(pilaster), 알 등급별 모양(eggLooks). 장식 개수는 MapBuilder 파트 상한
	(구역 ≤ 400, 맵 ≤ 7,000) 안에서 정함 — 늘리면 lune run tests/smoke_visuals.luau 로 상한 확인.
]]

local Plants = require(script.Parent.Plants)

export type Color = { number }

export type DecorSpec = { kind: string, count: number }

export type BiomeTheme = {
	floor: Color,
	floorMaterial: string,
	trim: Color,
	accent: Color,
	accent2: Color,
	decor: { DecorSpec },
	ambient: string?, -- 구역 위 떠다니는 파티클 종류
	atmosphere: { color: Color, decay: Color, density: number, haze: number }?,
	music: string, -- Sounds 이름
	-- 2판 복도 (원작 스터드 체크무늬): 바닥 둘째 색(없으면 floor 를 조금 어둡게), 양옆 담장 색, 담장 위 잔디 띠, 담장 네온 줄
	floor2: Color?,
	wall: Color,
	wallCap: Color?,
	wallGlow: Color?,
	rightSide: { floor: Color, floor2: Color, wall: Color, wallGlow: Color? }?, -- 오른쪽(x > 0) 절반만 다른 색 (천사&악마)
	label: string, -- 구역 배너 이모지 (원작 "Jungle 😬")
	-- 4판 비주얼 (MapBuilder): 바닥 무늬 · 가운데 길 · 가운데 작은 장식 · 벽 장식 · 입구 아치 · 담장 기둥 색
	pattern: string?, -- "stripes" | "checker" | "tiles" | "dunes" | "ice" | "cracks" | "caustics" | "grid" | "patches"
	floorTile: Color?, -- 무늬 색 (없으면 floor2)
	path: { color: Color, kind: string, glow: boolean? }?, -- kind "road"(흙길·돌길) | "stones"(징검돌)
	scatter: { DecorSpec }?, -- 복도 가운데에 흩어 놓는 작은 장식 (안 부딪힘, 경비 길을 막지 않음)
	wallDecor: string?, -- 담장 면 장식 "vines" | "hiero" | "icicles" | "portholes" | "torches" | "lanterns" | "crystals" | "candystripes" | "windows"
	arch: string?, -- 구역 입구 아치 모양 "wood" | "sandstone" | "ice" | "basalt" | "coral" | "bone" | "space" | "torii" | "marble" | "crystal" | "candy" | "gothic"
	pilaster: Color?, -- 담장 기둥 색 (없으면 trim)
}

-- 팔레트
local C: { [string]: Color } = {
	white = { 255, 255, 255 },
	cream = { 255, 240, 210 },
	black = { 35, 35, 40 },
	gray = { 150, 150, 158 },
	dark = { 65, 62, 75 },
	brown = { 145, 95, 55 },
	dbrown = { 95, 60, 35 },
	tan = { 215, 175, 125 },
	orange = { 255, 150, 50 },
	red = { 235, 65, 65 },
	dred = { 150, 25, 30 },
	pink = { 255, 170, 205 },
	hotpink = { 255, 90, 180 },
	yellow = { 255, 225, 70 },
	gold = { 255, 200, 40 },
	green = { 95, 205, 95 },
	dgreen = { 45, 135, 65 },
	lime = { 170, 235, 85 },
	olive = { 130, 140, 70 },
	teal = { 40, 200, 190 },
	cyan = { 90, 235, 255 },
	blue = { 70, 135, 255 },
	navy = { 35, 50, 125 },
	purple = { 150, 80, 220 },
	violet = { 195, 130, 255 },
	lava = { 255, 95, 25 },
	ice = { 195, 238, 255 },
	bone = { 238, 232, 212 },
	choco = { 115, 65, 35 },
	mint = { 165, 255, 215 },
	sky = { 150, 210, 255 },
	silver = { 205, 210, 220 },
	ginger = { 195, 125, 65 },
	zombie = { 135, 170, 110 },
}

local Visuals = {}

Visuals.palette = C

-- 맵/연출 전용 태그 (shared/Tags.luau 는 수석 파일이라 따로 둠)
Visuals.Tags = {
	PenPet = "PenPet", -- [5판 우리 펫 — 6판 서버는 안 만듦] 이름만 남김 (옛 클라 코드 호환)
	ParentAnimal = "ParentAnimal", -- 둥지 옆 장식 식물 모델 (6판: 그 구역 식물, 5판 부모 동물 자리)
	AuraFx = "AuraFx", -- 6판: 등급 아우라·돌연변이 파티클/빛을 담은 파트 (서버는 Enabled = false, 클라가 100 스터드 안만 켬)
	GuardVisual = "GuardVisual", -- 경비 겉모습 모델
	RarityHighlight = "RarityHighlight", -- 희귀도 테두리 Highlight (클라가 가까운 것만 켬, 31개 한계)
	EggShell = "EggShell", -- 씨앗 껍데기·무지개 돌연변이 식물 파트 (Attr Rainbow = true 면 클라가 색 순환)
	Ambient = "AmbientEmitter", -- 구역 분위기 파티클
	UpgradeSign = "UpgradeSign", -- 베이스 업그레이드 표지판 (Attr Kind = "Pen"|"Treadmill", PlotIndex) — 클라가 "업그레이드" 프롬프트
	LeaderboardBoard = "LeaderboardBoard", -- 5판: 허브 스폰 광장 랭킹판 (판 파트만, Front 면 글은 클라 LeaderboardController 가 채움)
}

------------------------------------------------------------------
-- 6판: 식물 생김새 (134종) — 손으로 하나씩 만들지 않고 "구역 테마 + 이름 낱말 + id 해시" 로 정함
--   PlantVisualService 가 이 표로 모델을 만듦 (모양 form · 색 · 잎/꽃잎 수 · 열매 모양).
--   form: 이름 낱말이 먼저 (버섯 → mushroom, 선인장 → cactus …), 없으면 구역 테마 forms 중 해시로 고름.
--   색: 구역 팔레트에서 해시로 고르고 살짝 흔듦(서로 조금씩 다르게). 등급 색은 PlantVisualService 가 받침 고리·크기로.
------------------------------------------------------------------

export type PlantTheme = {
	forms: { string },
	leaf: Color,
	stem: Color,
	petals: { Color },
	fruits: { Color },
	glow: boolean?, -- 꽃 가운데·열매를 네온으로 (밤 구역·바다·코스믹)
	petalMaterial: string?,
}

-- PlantVisualService 가 아는 모양 (crossrefs.spec 이 서버 코드와 대조)
Visuals.PLANT_FORMS = {
	"flower",
	"cup",
	"rose",
	"tree",
	"pine",
	"palm",
	"cactus",
	"mushroom",
	"lotus",
	"reed",
	"vine",
	"fern",
	"gourd",
	"coral",
	"crystal",
	"candy",
}

Visuals.plantThemes = {
	forest = {
		forms = { "flower", "tree" },
		leaf = { 80, 175, 70 },
		stem = { 70, 130, 55 },
		petals = { { 255, 255, 255 }, { 255, 220, 90 }, { 255, 150, 190 } },
		fruits = { { 230, 60, 60 }, { 255, 170, 60 }, { 150, 90, 200 } },
	},
	lake = {
		forms = { "lotus", "reed" },
		leaf = { 70, 180, 120 },
		stem = { 60, 140, 100 },
		petals = { { 170, 200, 255 }, { 255, 190, 220 }, { 255, 255, 255 } },
		fruits = { { 90, 150, 255 }, { 120, 220, 255 }, { 200, 140, 255 } },
	},
	desert = {
		forms = { "cactus", "palm" },
		leaf = { 120, 170, 80 },
		stem = { 150, 120, 70 },
		petals = { { 255, 120, 140 }, { 255, 200, 80 }, { 255, 150, 60 } },
		fruits = { { 255, 90, 120 }, { 255, 200, 60 }, { 230, 120, 50 } },
	},
	jungle = {
		forms = { "vine", "fern" },
		leaf = { 40, 160, 60 },
		stem = { 90, 110, 40 },
		petals = { { 255, 90, 60 }, { 255, 200, 40 }, { 200, 60, 200 } },
		fruits = { { 255, 220, 50 }, { 255, 130, 40 }, { 120, 220, 80 } },
	},
	snow = {
		forms = { "pine", "cup" },
		leaf = { 120, 190, 170 },
		stem = { 90, 120, 140 },
		petals = { { 220, 240, 255 }, { 170, 220, 255 }, { 255, 255, 255 } },
		fruits = { { 150, 220, 255 }, { 230, 245, 255 }, { 120, 170, 255 } },
		petalMaterial = "Ice",
	},
	volcano = {
		forms = { "flower", "cactus" },
		leaf = { 90, 70, 60 },
		stem = { 50, 40, 40 },
		petals = { { 255, 110, 30 }, { 255, 60, 40 }, { 255, 200, 60 } },
		fruits = { { 255, 90, 30 }, { 255, 180, 40 }, { 200, 30, 30 } },
		glow = true,
	},
	abyss_ocean = {
		forms = { "coral", "reed" },
		leaf = { 40, 120, 130 },
		stem = { 30, 90, 110 },
		petals = { { 90, 230, 255 }, { 255, 120, 200 }, { 160, 120, 255 } },
		fruits = { { 120, 255, 240 }, { 255, 150, 220 }, { 120, 160, 255 } },
		glow = true,
	},
	prehistoric = {
		forms = { "fern", "tree" },
		leaf = { 90, 140, 50 },
		stem = { 110, 85, 50 },
		petals = { { 220, 170, 70 }, { 180, 110, 60 }, { 240, 220, 120 } },
		fruits = { { 230, 150, 40 }, { 200, 90, 50 }, { 160, 200, 70 } },
	},
	cosmic = {
		forms = { "mushroom", "crystal" },
		leaf = { 90, 70, 170 },
		stem = { 60, 50, 110 },
		petals = { { 150, 90, 255 }, { 90, 200, 255 }, { 255, 120, 230 } },
		fruits = { { 255, 240, 140 }, { 160, 120, 255 }, { 120, 230, 255 } },
		glow = true,
	},
	cherry_blossom = {
		forms = { "tree", "flower" },
		leaf = { 110, 160, 90 },
		stem = { 110, 70, 60 },
		petals = { { 255, 180, 210 }, { 255, 220, 235 }, { 240, 130, 170 } },
		fruits = { { 255, 110, 150 }, { 200, 60, 90 }, { 255, 200, 220 } },
	},
	titan_temple = {
		forms = { "crystal", "tree" },
		leaf = { 100, 140, 80 },
		stem = { 140, 135, 125 },
		petals = { { 255, 210, 90 }, { 230, 230, 220 }, { 200, 170, 110 } },
		fruits = { { 255, 200, 50 }, { 240, 240, 230 }, { 180, 140, 80 } },
	},
	angels_demons = {
		forms = { "cup", "rose" },
		leaf = { 150, 200, 140 },
		stem = { 170, 160, 130 },
		petals = { { 255, 255, 255 }, { 255, 230, 140 }, { 200, 40, 50 } },
		fruits = { { 255, 240, 170 }, { 230, 60, 60 }, { 255, 255, 255 } },
	},
	enchanted_forest = {
		forms = { "mushroom", "flower" },
		leaf = { 60, 170, 120 },
		stem = { 80, 110, 80 },
		petals = { { 170, 255, 220 }, { 200, 150, 255 }, { 255, 190, 240 } },
		fruits = { { 150, 255, 200 }, { 210, 160, 255 }, { 255, 230, 120 } },
		glow = true,
	},
	candy_kingdom = {
		forms = { "candy", "flower" },
		leaf = { 120, 220, 150 },
		stem = { 255, 235, 240 },
		petals = { { 255, 130, 190 }, { 150, 220, 255 }, { 255, 240, 120 } },
		fruits = { { 255, 90, 150 }, { 120, 200, 255 }, { 255, 220, 80 } },
	},
	haunted_castle = {
		forms = { "gourd", "mushroom" },
		leaf = { 70, 90, 60 },
		stem = { 50, 45, 55 },
		petals = { { 170, 120, 220 }, { 240, 240, 255 }, { 255, 140, 40 } },
		fruits = { { 255, 140, 30 }, { 150, 255, 140 }, { 180, 110, 230 } },
		glow = true,
	},
	-- [7판 수석 임시] 새 구역 3개 식물 색 (선임이 다시 꾸밈)
	hacker_lab = {
		forms = { "crystal", "vine" },
		leaf = { 40, 200, 90 },
		stem = { 40, 50, 45 },
		petals = { { 60, 255, 110 }, { 30, 30, 36 }, { 120, 255, 200 } },
		fruits = { { 60, 255, 110 }, { 200, 255, 120 }, { 40, 200, 255 } },
		glow = true,
	},
	developer_room = {
		forms = { "cup", "tree" },
		leaf = { 80, 150, 230 },
		stem = { 120, 110, 100 },
		petals = { { 40, 110, 230 }, { 255, 255, 255 }, { 225, 130, 50 } },
		fruits = { { 40, 110, 230 }, { 255, 200, 60 }, { 230, 230, 240 } },
	},
	bug_dimension = {
		forms = { "rose", "crystal" },
		leaf = { 120, 40, 160 },
		stem = { 30, 20, 40 },
		petals = { { 255, 0, 200 }, { 0, 255, 90 }, { 255, 255, 255 } },
		fruits = { { 255, 0, 200 }, { 0, 255, 90 }, { 60, 160, 255 } },
		glow = true,
	},
} :: { [string]: PlantTheme }

local DEFAULT_THEME: PlantTheme = Visuals.plantThemes.forest

-- 이름 낱말 → 모양 (위에서부터 먼저 맞는 것)
local FORM_WORDS: { { string } } = {
	{ "mushroom", "mushroom", "toadstool", "candle" },
	{ "cactus", "cactus", "aloe", "thistle", "thorn" },
	{ "palm", "palm" },
	{ "pine", "pine", "bonsai" },
	{ "tree", "tree", "oak", "willow", "ginkgo", "cycad", "plum", "acorn" },
	{ "lotus", "lotus", "pad", "clover" },
	{ "reed", "reed", "grass", "horsetail", "bamboo", "kelp" },
	{ "vine", "vine", "ivy", "wisteria" },
	{ "fern", "fern", "leaf", "feather", "moss" },
	{ "gourd", "gourd", "pumpkin", "cabbage", "eggplant", "pepper", "nightshade", "cotton", "cress", "fruit" },
	{ "coral", "coral", "anemone" },
	{ "candy", "lollipop", "candy" },
	{ "crystal", "crystal", "relic", "gong", "pillar" },
	{
		"cup",
		"tulip",
		"bell",
		"snowdrop",
		"trumpet",
		"harp",
		"lantern",
		"lily",
		"iris",
		"orchid",
		"pitcher",
		"shell",
	},
	{ "rose", "rose", "peony", "camellia", "bloom", "blossom" },
	{ "flower", "daisy", "sunflower", "dandelion", "flower", "sprout", "crown" },
}

local FRUIT_SHAPES = { "round", "oval", "long", "berry" }

-- 문자열 해시 (같은 id = 늘 같은 값)
function Visuals.hash(text: string): number
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483647
	end
	return h
end

local function jitter(c: Color, h: number, amount: number): Color
	local result: Color = {}
	for i = 1, 3 do
		local d = ((math.floor(h / (7 ^ i)) % 9) - 4) / 4 * amount
		result[i] = math.clamp(math.floor(c[i] + d + 0.5), 0, 255)
	end
	return result
end

export type PlantLook = {
	form: string,
	leaf: Color,
	stem: Color,
	petal: Color,
	center: Color,
	fruit: Color,
	fruitShape: string,
	petals: number, -- 꽃잎·가지 수 (5~8)
	leaves: number, -- 잎 수 (2~4)
	tall: number, -- 키 배율 (0.85~1.15)
	twist: number, -- 돌린 각도(도), 정원마다 같은 방향을 안 보게
	glow: boolean,
	petalMaterial: string?,
}

local lookCache: { [string]: PlantLook } = {}

function Visuals.plantLook(id: string): PlantLook
	local cached = lookCache[id]
	if cached then
		return cached
	end
	local plant = Plants.get(id)
	local theme = (if plant then Visuals.plantThemes[plant.biome] else nil) or DEFAULT_THEME
	local h = Visuals.hash(id)
	local form: string? = nil
	for _, row in FORM_WORDS do
		for i = 2, #row do
			if string.find(id, row[i], 1, true) then
				form = row[1]
				break
			end
		end
		if form then
			break
		end
	end
	local chosen = form or theme.forms[h % #theme.forms + 1]
	local petal = theme.petals[math.floor(h / 3) % #theme.petals + 1]
	local fruit = theme.fruits[math.floor(h / 11) % #theme.fruits + 1]
	local look: PlantLook = {
		form = chosen,
		leaf = jitter(theme.leaf, h, 22),
		stem = jitter(theme.stem, math.floor(h / 5), 14),
		petal = jitter(petal, math.floor(h / 13), 26),
		center = jitter(theme.fruits[math.floor(h / 17) % #theme.fruits + 1], h, 20),
		fruit = jitter(fruit, math.floor(h / 19), 24),
		fruitShape = FRUIT_SHAPES[math.floor(h / 23) % #FRUIT_SHAPES + 1],
		petals = 5 + math.floor(h / 29) % 4,
		leaves = 2 + math.floor(h / 31) % 3,
		tall = 0.85 + (math.floor(h / 37) % 7) * 0.05,
		twist = (math.floor(h / 41) % 12) * 30,
		glow = theme.glow == true,
		petalMaterial = theme.petalMaterial,
	}
	lookCache[id] = look
	return look
end

-- 식물 대표 색 (씨앗 껍데기·UI 동그라미): 1 = 꽃잎, 2 = 잎, 3 = 열매
function Visuals.petColor(id: string, index: number?): Color
	local look = Visuals.plantLook(id)
	local i = index or 1
	return if i == 2 then look.leaf elseif i == 3 then look.fruit else look.petal
end

------------------------------------------------------------------
-- 경비 = 식물 괴물 (6판, 이름 Biomes.guardName). PetVisualService.buildMonster 가 만듦.
--   body: "stalk"(줄기) | "trunk"(나무 몸통) | "blob"(동글 몸) | "column"(기둥 몸) | "kelp"(해초 다발)
--   head: "jaws"(파리지옥 턱) | "flower"(꽃 머리) | "cap"(버섯 갓) | "canopy"(나뭇잎 머리) | "pumpkin" | "lotus" |
--         "rose" | "lily" | "none"(몸에 얼굴)
--   colors: [1] 몸 [2] 머리/꽃 [3] 포인트. extras: 쉼표로 (PetVisualService MONSTER_EXTRAS)
------------------------------------------------------------------

export type MonsterLook = {
	body: string,
	head: string,
	colors: { Color },
	extras: { string },
	glowEyes: boolean?,
	ghostly: boolean?,
}

local function monster(
	body: string,
	head: string,
	colors: { Color },
	extras: string,
	opts: { [string]: boolean }?
): MonsterLook
	local list: { string } = {}
	for word in string.gmatch(extras, "[^,%s]+") do
		table.insert(list, word)
	end
	return {
		body = body,
		head = head,
		colors = colors,
		extras = list,
		glowEyes = if opts then opts.glowEyes else nil,
		ghostly = if opts then opts.ghostly else nil,
	}
end

Visuals.monsters = {
	flytrap_monster = monster("stalk", "jaws", { { 70, 150, 60 }, { 130, 200, 80 }, { 220, 60, 70 } }, "teeth,leaves"),
	lotus_frog = monster("blob", "lotus", { { 90, 180, 110 }, { 255, 170, 205 }, { 255, 240, 150 } }, "leaves,bubbles"),
	cactus_captain = monster(
		"column",
		"none",
		{ { 90, 160, 80 }, { 255, 120, 150 }, { 240, 230, 180 } },
		"spines,arms,flower_top"
	),
	tiger_flower = monster("stalk", "flower", { { 60, 140, 50 }, { 255, 140, 30 }, { 30, 30, 30 } }, "stripes,leaves"),
	frost_thorn_tree = monster(
		"trunk",
		"canopy",
		{ { 150, 180, 200 }, { 210, 240, 255 }, { 120, 200, 255 } },
		"thorns,arms,snow"
	),
	lava_head_flower = monster(
		"stalk",
		"flower",
		{ { 55, 45, 45 }, { 255, 100, 30 }, { 255, 220, 80 } },
		"embers,leaves",
		{ glowEyes = true }
	),
	seaweed_monster = monster(
		"kelp",
		"none",
		{ { 40, 130, 110 }, { 70, 200, 170 }, { 120, 255, 240 } },
		"bubbles,glowbulbs",
		{ glowEyes = true }
	),
	dino_fern = monster("stalk", "jaws", { { 90, 140, 50 }, { 140, 190, 70 }, { 240, 230, 200 } }, "fronds,teeth"),
	space_mushroom_giant = monster(
		"column",
		"cap",
		{ { 230, 220, 255 }, { 120, 70, 220 }, { 255, 240, 140 } },
		"glowspots,arms,stars"
	),
	sakura_fox_tree = monster(
		"trunk",
		"canopy",
		{ { 110, 70, 60 }, { 255, 180, 210 }, { 255, 140, 60 } },
		"ears,arms,petals"
	),
	stone_giant_tree = monster(
		"trunk",
		"canopy",
		{ { 140, 135, 125 }, { 100, 150, 80 }, { 255, 200, 60 } },
		"arms,crown"
	),
	angel_lily = monster(
		"stalk",
		"lily",
		{ { 150, 210, 140 }, { 255, 255, 255 }, { 255, 215, 80 } },
		"halo,wings,leaves"
	),
	devil_rose = monster(
		"stalk",
		"rose",
		{ { 60, 40, 40 }, { 200, 30, 40 }, { 255, 90, 30 } },
		"horns,thorns,embers",
		{ glowEyes = true }
	),
	spirit_mushroom = monster(
		"column",
		"cap",
		{ { 200, 255, 235 }, { 120, 255, 200 }, { 255, 255, 255 } },
		"glowspots,arms,orbs",
		{ ghostly = true }
	),
	candy_cane_giant = monster(
		"column",
		"none",
		{ { 255, 255, 255 }, { 230, 40, 60 }, { 120, 220, 150 } },
		"stripes,arms,candy_top"
	),
	pumpkin_vine_monster = monster(
		"stalk",
		"pumpkin",
		{ { 60, 90, 50 }, { 255, 140, 30 }, { 255, 230, 90 } },
		"leaves,mist",
		{ glowEyes = true }
	),
} :: { [string]: MonsterLook }

------------------------------------------------------------------
-- 경비 모양 (구역 id → Visuals.monsters id, 키)
--   원작처럼 거대함 (캐릭터 5~10배). height = 겉모습 키(스터드, 25~40) — PetVisualService 가 모델 키에 맞춰
--   크기 배율을 자동 계산 (GuardianService 잡힘 거리도 이 키). scale = 대략의 배율 (height 를 쓰므로 참고용)
------------------------------------------------------------------

Visuals.guards = {
	forest = { model = "flytrap_monster", scale = 10, height = 28 },
	lake = { model = "lotus_frog", scale = 8.3, height = 30 },
	desert = { model = "cactus_captain", scale = 18.5, height = 25 },
	jungle = { model = "tiger_flower", scale = 11.2, height = 30 },
	snow = { model = "frost_thorn_tree", scale = 10.9, height = 36 },
	volcano = { model = "lava_head_flower", scale = 12, height = 32 },
	abyss_ocean = { model = "seaweed_monster", scale = 11.3, height = 26 },
	prehistoric = { model = "dino_fern", scale = 11.8, height = 40 },
	cosmic = { model = "space_mushroom_giant", scale = 11.5, height = 38 },
	cherry_blossom = { model = "sakura_fox_tree", scale = 12, height = 32 },
	titan_temple = { model = "stone_giant_tree", scale = 11.5, height = 38 },
	angels_demons = { model = "angel_lily", darkModel = "devil_rose", scale = 10.9, height = 36 },
	enchanted_forest = { model = "spirit_mushroom", scale = 11.2, height = 32 },
	candy_kingdom = { model = "candy_cane_giant", scale = 10.9, height = 36 },
	haunted_castle = { model = "pumpkin_vine_monster", scale = 13.3, height = 38 },
	-- [7판 수석 임시] 새 구역 경비 3마리는 지금 있는 괴물 모양을 빌려 씀 (이름은 Biomes.guardName). 진짜 모양은 선임
	hacker_lab = { model = "seaweed_monster", scale = 12, height = 38 }, -- 바이러스 덩굴
	developer_room = { model = "cactus_captain", scale = 14, height = 38 }, -- 디버그 선인장
	bug_dimension = { model = "devil_rose", scale = 13, height = 40 }, -- 글리치 장미 괴물
} :: { [string]: { model: string, darkModel: string?, scale: number, height: number? } }

------------------------------------------------------------------
-- 희귀도 효과 / 아우라 / 돌연변이 효과
------------------------------------------------------------------

-- 전설 이상: 빛 색(씨앗 껍데기 PointLight) — 6판은 아래 auras 가 본 효과, 이 표는 빛 색만 씀
Visuals.rarityEffects = {
	legendary = { highlight = C.gold, particle = "sparkle", particleColor = C.gold },
	mythic = { highlight = C.red, particle = "sparkle", particleColor = C.red },
	cosmic = { highlight = C.violet, particle = "sparkle", particleColor = C.violet, light = C.violet },
	secret = { highlight = C.black, particle = "smoke", particleColor = C.black },
	eternity = { highlight = C.white, particle = "sparkle", particleColor = C.white, light = C.white },
	divine = { highlight = C.white, particle = "rainbow", light = C.pink },
	-- [7판 수석 임시] 새 등급 6개 (super = 6판 슈퍼 울트라디바인 그대로) — 선임이 다시 고름
	super = { highlight = C.gold, particle = "rainbow", light = C.yellow },
	hacker = { highlight = C.green, particle = "spark", particleColor = C.green, light = C.green },
	original = { highlight = C.orange, particle = "sparkle", particleColor = C.gold, light = C.orange },
	developer = { highlight = C.blue, particle = "sparkle", particleColor = C.cyan, light = C.blue },
	ultradivine = { highlight = C.white, particle = "rainbow", light = C.white },
	hacker_glitch = { highlight = C.hotpink, particle = "spark", particleColor = C.hotpink, light = C.lime },
} :: { [string]: { highlight: Color?, particle: string?, particleColor: Color?, light: Color? } }

--[[
	등급 아우라 (Rarities.aura 이름 11개, 설계 3장). PlantVisualService.addAura 가 씨앗·자라는 씨앗·성체에 붙임.
	  particle: "sparkle" | "flame" | "spark" | "stars" | "smoke" | "rainbow" (없으면 파티클 없음)
	  ring: 고정 고리 파트 (네온) — "ground"(바닥) | "halo"(가운데 높이 가로) | "clock"(뒤에 세운 고리)
	  beam: 하늘로 솟는 빛기둥 (항상 켜짐, 맵 어디서나)
	파티클·빛은 희귀(rare) 이상만, 서버는 꺼진 채(Enabled = false) 만들고 AuraFx 태그 → 클라가 100 스터드 안만 켬.
]]
export type AuraLook = {
	particle: string?,
	color: Color?,
	rate: number?,
	light: Color?,
	ring: string?,
	ringColor: Color?,
	beam: boolean?,
}
Visuals.auras = {
	none = {},
	lime_glow = { ring = "ground", ringColor = { 170, 255, 90 } },
	blue_sparkle = { particle = "sparkle", color = { 90, 170, 255 }, rate = 3 },
	purple_flame = { particle = "flame", color = { 180, 90, 255 }, rate = 4 },
	gold_ring = {
		particle = "sparkle",
		color = { 255, 210, 60 },
		rate = 3,
		ring = "halo",
		ringColor = { 255, 205, 50 },
	},
	red_lightning = { particle = "spark", color = { 255, 60, 60 }, rate = 5, light = { 255, 70, 70 } },
	stardust_swirl = { particle = "stars", color = { 190, 140, 255 }, rate = 5, light = { 170, 110, 255 } },
	black_mist = { particle = "smoke", color = { 30, 25, 40 }, rate = 4, light = { 150, 80, 255 } },
	white_clock = {
		particle = "sparkle",
		color = { 255, 255, 255 },
		rate = 3,
		light = { 240, 245, 255 },
		ring = "clock",
		ringColor = { 255, 255, 255 },
	},
	rainbow_beam = {
		particle = "rainbow",
		rate = 6,
		light = { 255, 170, 220 },
		ring = "halo",
		ringColor = { 255, 255, 255 },
	},
	sky_pillar = {
		particle = "rainbow",
		rate = 8,
		light = { 255, 230, 120 },
		ring = "halo",
		ringColor = { 255, 215, 60 },
		beam = true,
	},
	-- [7판 수석 임시] 새 아우라 5개 (Rarities.aura) — 지금 있는 파티클·고리만으로 임시 모양. 진짜 모양은 선임
	--   (code_rain 초록 코드 비 · first_light 태초의 금빛 햇살 · build_grid 파란 빛 격자 · ultra_halo 무지개 후광 두 겹 + 빛기둥 ·
	--    glitch_static 지지직 깨진 픽셀)
	code_rain = {
		particle = "spark",
		color = { 60, 255, 110 },
		rate = 7,
		light = { 60, 255, 110 },
		ring = "ground",
		ringColor = { 40, 230, 90 },
	},
	first_light = {
		particle = "sparkle",
		color = { 255, 200, 120 },
		rate = 7,
		light = { 255, 190, 110 },
		ring = "halo",
		ringColor = { 255, 170, 70 },
	},
	build_grid = {
		particle = "stars",
		color = { 120, 190, 255 },
		rate = 7,
		light = { 90, 160, 255 },
		ring = "ground",
		ringColor = { 60, 140, 255 },
	},
	ultra_halo = {
		particle = "rainbow",
		rate = 9,
		light = { 255, 255, 255 },
		ring = "halo",
		ringColor = { 255, 255, 255 },
		beam = true,
	},
	glitch_static = {
		particle = "spark",
		color = { 255, 0, 200 },
		rate = 10,
		light = { 0, 255, 90 },
		ring = "clock",
		ringColor = { 255, 0, 200 },
		beam = true,
	},
} :: { [string]: AuraLook }

-- 돌연변이 겉모습: color·material 이 꽃잎/열매/씨앗 껍데기 색을 덮어씀. cycle = 클라가 무지개로 색 순환.
--   effect = 원소 돌연변이 파티클 (AuraFx 와 같이 가까울 때만): "snow" | "fire" | "spark"
Visuals.mutationLooks = {
	silver = { color = { 205, 210, 222 }, material = "Foil", reflectance = 0.35 },
	golden = { color = { 255, 200, 45 }, material = "Neon" },
	rainbow = { color = { 255, 90, 200 }, material = "Neon", cycle = true },
	bloom = { color = { 255, 170, 205 }, petals = { 255, 150, 200 } },
	spirit_bloom = { color = { 190, 130, 255 }, petals = { 180, 120, 255 } },
	fractured = { color = { 120, 60, 200 }, material = "Glass" },
	parasite = { color = { 110, 160, 40 } },
	chaos = { color = { 230, 60, 60 }, material = "Neon" },
	frozen = { color = { 170, 230, 255 }, material = "Ice", effect = "snow" },
	burning = { color = { 255, 110, 40 }, material = "Neon", effect = "fire" },
	shocked = { color = { 255, 240, 90 }, material = "Neon", effect = "spark" },
} :: {
	[string]: {
		color: Color,
		material: string?,
		reflectance: number?,
		cycle: boolean?,
		petals: Color?,
		effect: string?,
	},
}

-- 6판: 씨앗 껍데기 등급별 모양 (EggVisualService). 아몬드(물방울) 모양 껍데기 + 뾰족한 끝 + 세로 줄무늬.
--   shell = 껍데기 색 (없으면 등급 색을 파스텔로), stripe = 줄무늬 색 (없으면 등급 색), stripes = 줄무늬 수(0~4),
--   tip = 끝 색 (없으면 껍데기를 조금 어둡게), neon = 줄무늬 네온, dots = "stars"(별 점 2) | "gems"(보석 2) | nil,
--   rainbow = 줄무늬를 무지개 색으로. 씨앗 하나 ≤ 8 파트. 파티클·빛은 등급 아우라(Visuals.auras)
export type EggLook = {
	stripes: number,
	shell: Color?,
	stripe: Color?,
	tip: Color?,
	neon: boolean?,
	dots: string?,
	rainbow: boolean?,
}
Visuals.eggLooks = {
	common = { stripes = 2, shell = { 236, 222, 188 }, stripe = { 120, 95, 70 } },
	uncommon = { stripes = 2 },
	rare = { stripes = 3 },
	epic = { stripes = 3, dots = "gems" },
	legendary = { stripes = 4, tip = { 255, 205, 50 } },
	mythic = { stripes = 4, stripe = { 150, 20, 30 }, dots = "gems" },
	cosmic = { stripes = 3, shell = { 70, 45, 160 }, stripe = { 140, 100, 255 }, neon = true, dots = "stars" },
	secret = { stripes = 3, shell = { 30, 30, 36 }, stripe = { 170, 100, 255 }, neon = true },
	eternity = { stripes = 4, shell = { 235, 250, 255 }, stripe = { 255, 255, 255 }, neon = true },
	divine = { stripes = 3, shell = { 255, 255, 255 }, rainbow = true, dots = "stars" },
	super = { -- 7판: 6판 슈퍼 울트라디바인 모양 그대로
		stripes = 4,
		shell = { 255, 245, 160 },
		tip = { 255, 200, 40 },
		rainbow = true,
		dots = "stars",
	},
	-- [7판 수석 임시] 새 등급 5개 껍데기 (선임이 다시 꾸밈)
	hacker = { stripes = 4, shell = { 20, 30, 24 }, stripe = { 60, 255, 110 }, neon = true, dots = "gems" },
	original = {
		stripes = 3,
		shell = { 250, 225, 180 },
		stripe = { 225, 130, 50 },
		tip = { 255, 200, 60 },
		dots = "stars",
	},
	developer = { stripes = 4, shell = { 220, 235, 255 }, stripe = { 30, 100, 230 }, neon = true, dots = "gems" },
	ultradivine = { stripes = 4, shell = { 255, 255, 255 }, tip = { 255, 240, 160 }, rainbow = true, dots = "stars" },
	hacker_glitch = {
		stripes = 4,
		shell = { 15, 10, 25 },
		stripe = { 255, 0, 200 },
		tip = { 0, 255, 90 },
		neon = true,
		rainbow = true,
		dots = "gems",
	},
} :: { [string]: EggLook }

-- 특별 씨앗(EggSpawn.SPECIAL_RARITIES: 비밀 이상 9등급, 7판) 빔 색과 글자
--   [7판 수석 임시] 새 등급 6개는 화면 영어 이름(Rarities.displayName) + " 씨앗!" — 선임이 옛 4개도 영어로 맞춤
Visuals.specialEggs = {
	secret = { text = "비밀 씨앗!", color = { 40, 40, 40 }, textColor = C.white },
	eternity = { text = "영원 씨앗!", color = C.cyan, textColor = { 0, 50, 50 } },
	divine = { text = "신성 씨앗!", color = C.pink, textColor = C.white },
	super = { text = "Super 씨앗!", color = C.gold, textColor = { 60, 20, 90 } },
	hacker = { text = "Hacker 씨앗!", color = { 40, 230, 90 }, textColor = { 0, 30, 10 } },
	original = { text = "Original 씨앗!", color = { 225, 130, 50 }, textColor = C.white },
	developer = { text = "Developer 씨앗!", color = { 30, 100, 230 }, textColor = C.white },
	ultradivine = { text = "Ultradivine 씨앗!", color = C.white, textColor = { 120, 40, 160 } },
	hacker_glitch = { text = "H?a.(cke_r!# 씨앗!", color = { 255, 0, 200 }, textColor = { 0, 255, 90 } },
} :: { [string]: { text: string, color: Color, textColor: Color } }

------------------------------------------------------------------
-- 베이스 색 (1~7번) = 우리 울타리 가로대·X 보강재 색 (원작: 나무 갈색 / 흰색 / 노랑 …, 기둥은 모두 검정)
------------------------------------------------------------------

Visuals.plotColors = {
	{ 196, 104, 48 }, -- 나무 갈색
	{ 238, 238, 242 }, -- 흰색
	{ 246, 190, 58 }, -- 노랑
	{ 120, 190, 255 }, -- 하늘
	{ 255, 150, 190 }, -- 분홍
	{ 150, 220, 90 }, -- 연두
	{ 175, 125, 235 }, -- 보라
} :: { Color }

------------------------------------------------------------------
-- 구역 테마 (설계문서 4장 순서)
------------------------------------------------------------------

-- 구역 장식 개수 배율 (한 곳에서 조절). 폰이 끊기면 0.5 처럼 줄이면 모든 구역 장식(decor count)이 같이 줄어듦.
-- (heavenhell·chocoriver·castlewall·torii 같은 고정 구조물과 2단계 특수 장소 모델은 배율과 상관없이 그대로)
Visuals.decorScale = 1

local function decor(list: { { any } }): { DecorSpec }
	local result: { DecorSpec } = {}
	for _, item in list do
		table.insert(result, { kind = item[1] :: string, count = item[2] :: number })
	end
	return result
end

Visuals.biomes = {
	forest = {
		floor = { 75, 190, 55 },
		floor2 = { 66, 174, 48 },
		floorMaterial = "Plastic",
		wall = { 214, 150, 92 },
		wallCap = { 85, 185, 55 },
		trim = { 150, 105, 60 },
		accent = { 60, 165, 55 },
		accent2 = { 255, 120, 120 },
		pattern = "stripes",
		path = { color = { 176, 124, 72 }, kind = "road" },
		arch = "wood",
		wallDecor = "vines",
		pilaster = { 168, 112, 62 },
		decor = decor({
			{ "blockytree", 11 },
			{ "bushblock", 8 },
			{ "chick", 3 },
			{ "duck", 2 },
			{ "stump", 3 },
			{ "rock", 3 },
		}),
		scatter = decor({ { "flowerpatch", 9 }, { "grasstuft", 12 }, { "minishroom", 5 }, { "pebbles", 3 } }),
		ambient = "leaves",
		music = "Bgm_forest",
		label = "🙂",
	},
	lake = {
		floor = { 80, 185, 70 },
		floor2 = { 70, 168, 62 },
		floorMaterial = "Plastic",
		wall = { 206, 146, 90 },
		wallCap = { 80, 180, 60 },
		trim = { 230, 215, 160 },
		accent = { 70, 160, 230 },
		accent2 = { 255, 255, 255 },
		pattern = "stripes",
		path = { color = { 232, 214, 160 }, kind = "road" },
		arch = "wood",
		wallDecor = "vines",
		pilaster = { 176, 122, 72 },
		decor = decor({
			{ "lakewater", 1 },
			{ "reeds", 8 },
			{ "swan", 3 },
			{ "duck", 3 },
			{ "blockytree", 6 },
			{ "rock", 4 },
		}),
		scatter = decor({ { "flowerpatch", 6 }, { "grasstuft", 10 }, { "puddle", 6 }, { "pebbles", 6 } }),
		ambient = "bubbles",
		music = "Bgm_lake",
		label = "😐",
	},
	desert = {
		floor = { 234, 202, 112 },
		floor2 = { 222, 188, 100 },
		floorMaterial = "Plastic",
		wall = { 222, 186, 105 },
		wallCap = { 120, 190, 70 },
		trim = { 200, 160, 95 },
		accent = { 90, 170, 80 },
		accent2 = { 210, 120, 70 },
		pattern = "dunes",
		arch = "sandstone",
		wallDecor = "hiero",
		pilaster = { 200, 158, 88 },
		decor = decor({
			{ "cactusblock", 16 },
			{ "pyramid", 2 },
			{ "urn", 5 },
			{ "tumbleweed", 5 },
			{ "rock", 6 },
			{ "bones", 3 },
		}),
		scatter = decor({ { "pebbles", 10 }, { "bonebits", 6 }, { "drygrass", 10 } }),
		ambient = "dust",
		atmosphere = { color = { 255, 230, 180 }, decay = { 230, 190, 130 }, density = 0.22, haze = 1 },
		music = "Bgm_desert",
		label = "😕",
	},
	jungle = {
		floor = { 42, 168, 45 },
		floor2 = { 36, 152, 40 },
		floorMaterial = "Plastic",
		wall = { 205, 140, 85 },
		wallCap = { 45, 160, 50 },
		trim = { 95, 65, 40 },
		accent = { 30, 120, 40 },
		accent2 = { 255, 90, 160 },
		pattern = "checker",
		path = { color = { 120, 82, 50 }, kind = "road" },
		arch = "wood",
		wallDecor = "vines",
		pilaster = { 110, 76, 44 },
		decor = decor({ { "blockypalm", 6 }, { "jungletree", 5 }, { "bushblock", 8 }, { "fern", 4 } }),
		scatter = decor({ { "flowerpatch", 6 }, { "grasstuft", 14 }, { "puddle", 4 } }),
		ambient = "fireflies",
		atmosphere = { color = { 200, 240, 200 }, decay = { 90, 140, 90 }, density = 0.22, haze = 0.8 },
		music = "Bgm_jungle",
		label = "😬",
	},
	snow = {
		floor = { 238, 242, 248 },
		floor2 = { 222, 230, 240 },
		floorMaterial = "Plastic",
		wall = { 200, 140, 85 },
		wallCap = { 240, 246, 255 },
		trim = { 170, 210, 240 },
		accent = { 150, 210, 255 },
		accent2 = { 255, 140, 40 },
		pattern = "ice",
		path = { color = { 206, 224, 244 }, kind = "road" },
		arch = "ice",
		wallDecor = "icicles",
		pilaster = { 176, 122, 72 },
		decor = decor({ { "icecrystal", 5 }, { "pine", 10 }, { "snowman", 2 }, { "snowpile", 8 } }),
		scatter = decor({ { "snowpile", 6 }, { "icechunk", 10 }, { "pebbles", 4 } }),
		ambient = "snow",
		atmosphere = { color = { 230, 240, 255 }, decay = { 200, 220, 245 }, density = 0.25, haze = 1.2 },
		music = "Bgm_snow",
		label = "😨",
	},
	volcano = {
		floor = { 52, 50, 56 },
		floor2 = { 44, 42, 48 },
		floorMaterial = "Plastic",
		wall = { 30, 28, 34 },
		wallGlow = { 255, 110, 30 },
		trim = { 255, 110, 30 },
		accent = { 255, 100, 20 },
		accent2 = { 40, 30, 30 },
		pattern = "cracks",
		arch = "basalt",
		pilaster = { 48, 40, 44 },
		decor = decor({
			{ "lavawall", 1 },
			{ "lavapool", 6 },
			{ "lavarock", 14 },
			{ "volcanocone", 2 },
			{ "deadtree", 5 },
			{ "darkspike", 4 },
		}),
		scatter = decor({ { "ember", 16 }, { "pebbles", 8 } }),
		ambient = "embers",
		atmosphere = { color = { 255, 170, 120 }, decay = { 170, 70, 40 }, density = 0.28, haze = 1.5 },
		music = "Bgm_volcano",
		label = "😰",
	},
	abyss_ocean = {
		floor = { 36, 72, 212 },
		floor2 = { 30, 62, 192 },
		floorMaterial = "Plastic",
		wall = { 40, 72, 140 },
		trim = { 30, 50, 110 },
		accent = { 255, 120, 160 },
		accent2 = { 60, 200, 160 },
		pattern = "caustics",
		path = { color = { 222, 196, 135 }, kind = "road" },
		arch = "coral",
		wallDecor = "portholes",
		pilaster = { 34, 58, 118 },
		decor = decor({
			{ "sandedge", 1 },
			{ "coralblock", 6 },
			{ "coral", 3 },
			{ "seaweed", 9 },
			{ "shell", 4 },
		}),
		scatter = decor({ { "starfish", 10 }, { "seagrass", 10 }, { "pebbles", 4 } }),
		ambient = "bubbles",
		atmosphere = { color = { 120, 180, 255 }, decay = { 30, 70, 150 }, density = 0.3, haze = 1.5 },
		music = "Bgm_abyss_ocean",
		label = "😱",
	},
	prehistoric = {
		floor = { 224, 190, 100 },
		floor2 = { 212, 176, 90 },
		floorMaterial = "Plastic",
		wall = { 150, 105, 60 },
		wallCap = { 90, 160, 60 },
		trim = { 110, 80, 50 },
		accent = { 80, 140, 60 },
		accent2 = { 240, 235, 215 },
		pattern = "patches",
		path = { color = { 160, 112, 66 }, kind = "road" },
		arch = "bone",
		wallDecor = "torches",
		pilaster = { 120, 82, 46 },
		decor = decor({
			{ "fern", 12 },
			{ "bigbone", 4 },
			{ "dinobones", 2 },
			{ "rock", 6 },
			{ "stump", 3 },
			{ "volcanocone", 1 },
		}),
		scatter = decor({ { "grasstuft", 12 }, { "bonebits", 8 }, { "puddle", 4 } }),
		ambient = "dust",
		atmosphere = { color = { 240, 220, 170 }, decay = { 170, 140, 90 }, density = 0.2, haze = 1 },
		music = "Bgm_prehistoric",
		label = "🤯",
	},
	cosmic = {
		floor = { 38, 42, 58 },
		floor2 = { 32, 36, 50 },
		floorMaterial = "Plastic",
		wall = { 20, 22, 34 },
		wallGlow = { 255, 255, 255 },
		trim = { 160, 90, 255 },
		accent = { 190, 120, 255 },
		accent2 = { 255, 255, 180 },
		pattern = "grid",
		arch = "space",
		pilaster = { 44, 40, 80 },
		decor = decor({
			{ "wallstars", 1 },
			{ "planet", 5 },
			{ "spacerock", 14 },
			{ "crystal", 10 },
			{ "satellite", 3 },
		}),
		scatter = decor({ { "stars", 40 }, { "glowmoss", 10 } }),
		ambient = "stars",
		atmosphere = { color = { 140, 100, 220 }, decay = { 40, 20, 90 }, density = 0.28, haze = 1.5 },
		music = "Bgm_cosmic",
		label = "😵",
	},
	cherry_blossom = {
		floor = { 255, 184, 210 },
		floor2 = { 248, 170, 200 },
		floorMaterial = "Plastic",
		wall = { 245, 215, 225 },
		wallCap = { 255, 150, 190 },
		trim = { 200, 60, 60 },
		accent = { 255, 175, 205 },
		accent2 = { 220, 50, 50 },
		pattern = "stripes",
		path = { color = { 170, 165, 175 }, kind = "stones" },
		arch = "torii",
		wallDecor = "lanterns",
		pilaster = { 200, 60, 60 },
		decor = decor({ { "cherrytree", 10 }, { "lantern", 7 }, { "torii", 1 }, { "rock", 3 }, { "bushblock", 4 } }),
		scatter = decor({ { "petals", 12 }, { "grasstuft", 6 } }),
		ambient = "petals",
		atmosphere = { color = { 255, 220, 235 }, decay = { 255, 190, 215 }, density = 0.2, haze = 1 },
		music = "Bgm_cherry_blossom",
		label = "🌸",
	},
	titan_temple = {
		floor = { 180, 172, 150 },
		floor2 = { 166, 158, 138 },
		floorMaterial = "Plastic",
		wall = { 150, 140, 120 },
		wallCap = { 205, 170, 70 },
		trim = { 205, 170, 70 },
		accent = { 205, 195, 165 },
		accent2 = { 210, 170, 60 },
		pattern = "tiles",
		path = { color = { 200, 160, 70 }, kind = "road" },
		arch = "sandstone",
		wallDecor = "hiero",
		pilaster = { 196, 160, 66 },
		decor = decor({
			{ "pillar", 12 },
			{ "brokenpillar", 5 },
			{ "statue", 4 },
			{ "urn", 7 },
			{ "jungletree", 3 },
		}),
		scatter = decor({ { "goldcoin", 12 }, { "pebbles", 6 }, { "grasstuft", 6 } }),
		ambient = "dust",
		music = "Bgm_titan_temple",
		label = "💀",
	},
	angels_demons = {
		floor = { 250, 246, 232 },
		floor2 = { 238, 232, 214 },
		floorMaterial = "Plastic",
		wall = { 250, 246, 236 },
		wallGlow = { 255, 205, 60 },
		-- 오른쪽(x > 0) 절반 = 지옥 (검붉은 바닥·담장)
		rightSide = {
			floor = { 52, 24, 30 },
			floor2 = { 42, 20, 26 },
			wall = { 45, 20, 26 },
			wallGlow = { 230, 40, 30 },
		},
		trim = { 255, 205, 60 },
		accent = { 255, 255, 255 },
		accent2 = { 200, 30, 30 },
		arch = "marble",
		pilaster = { 255, 205, 60 },
		decor = decor({
			{ "heavenhell", 1 },
			{ "cloud", 9 },
			{ "goldpillar", 6 },
			{ "firepit", 6 },
			{ "darkspike", 7 },
		}),
		scatter = decor({ { "stars", 14 } }),
		ambient = "sparkle",
		music = "Bgm_angels_demons",
		label = "😇",
	},
	enchanted_forest = {
		floor = { 62, 142, 116 },
		floor2 = { 54, 128, 104 },
		floorMaterial = "Plastic",
		wall = { 82, 56, 126 },
		wallGlow = { 150, 255, 220 },
		trim = { 160, 90, 255 },
		accent = { 190, 110, 255 },
		accent2 = { 90, 255, 220 },
		pattern = "patches",
		path = { color = { 120, 230, 210 }, kind = "stones", glow = true },
		arch = "crystal",
		wallDecor = "crystals",
		pilaster = { 64, 42, 100 },
		decor = decor({ { "glowshroom", 16 }, { "magictree", 6 }, { "crystal", 6 }, { "fairylights", 6 } }),
		scatter = decor({ { "glowmoss", 12 }, { "minishroom", 12 } }),
		ambient = "fireflies",
		atmosphere = { color = { 180, 140, 255 }, decay = { 80, 60, 140 }, density = 0.25, haze = 1.2 },
		music = "Bgm_enchanted_forest",
		label = "🔮",
	},
	candy_kingdom = {
		floor = { 255, 186, 220 },
		floor2 = { 248, 170, 208 },
		floorMaterial = "Plastic",
		wall = { 160, 215, 255 },
		wallCap = { 255, 255, 255 },
		trim = { 140, 210, 255 },
		accent = { 150, 215, 255 },
		accent2 = { 255, 110, 180 },
		pattern = "checker",
		floorTile = { 255, 236, 190 }, -- 체크무늬 둘째 색 (쿠키 바닥)
		arch = "candy",
		wallDecor = "candystripes",
		pilaster = { 255, 255, 255 },
		decor = decor({
			{ "chocoriver", 1 },
			{ "lollipop", 12 },
			{ "candycane", 6 },
			{ "gumdrop", 14 },
			{ "gingerhouse", 2 },
		}),
		scatter = decor({ { "candybits", 18 }, { "gumdrop", 6 } }),
		ambient = "sprinkles",
		atmosphere = { color = { 255, 220, 240 }, decay = { 200, 230, 255 }, density = 0.2, haze = 0.8 },
		music = "Bgm_candy_kingdom",
		label = "🍭",
	},
	haunted_castle = {
		floor = { 74, 64, 88 },
		floor2 = { 64, 55, 78 },
		floorMaterial = "Plastic",
		wall = { 48, 42, 58 },
		wallGlow = { 255, 140, 30 },
		trim = { 120, 70, 160 },
		accent = { 130, 120, 140 },
		accent2 = { 255, 140, 30 },
		pattern = "tiles",
		path = { color = { 108, 100, 116 }, kind = "stones" },
		arch = "gothic",
		wallDecor = "windows",
		pilaster = { 62, 54, 74 },
		decor = decor({
			{ "castlewall", 1 },
			{ "gravestone", 14 },
			{ "deadtree", 6 },
			{ "jackolantern", 6 },
		}),
		scatter = decor({ { "skull", 8 }, { "leafpile", 10 }, { "bonebits", 4 } }),
		ambient = "mist",
		atmosphere = { color = { 150, 110, 200 }, decay = { 70, 40, 100 }, density = 0.32, haze = 2 },
		music = "Bgm_haunted_castle",
		label = "👻",
	},
	-- [7판 수석 임시] 새 구역 3개 테마: 지금 MapBuilder 가 아는 무늬·아치·장식·배경음만 빌려 씀 (진짜 모양은 선임).
	--   장식 수는 맵 파트 상한(MapBuilder.PART_BUDGET)을 넘지 않게 적게
	hacker_lab = {
		floor = { 24, 30, 28 },
		floor2 = { 20, 26, 24 },
		floorMaterial = "Plastic",
		wall = { 18, 24, 22 },
		wallGlow = { 60, 255, 110 },
		trim = { 40, 230, 90 },
		accent = { 60, 255, 110 },
		accent2 = { 40, 200, 255 },
		pattern = "grid",
		arch = "space",
		wallDecor = "crystals",
		pilaster = { 30, 60, 40 },
		decor = decor({ { "crystal", 10 }, { "satellite", 3 }, { "spacerock", 6 }, { "pillar", 4 } }),
		scatter = decor({ { "glowmoss", 10 }, { "pebbles", 4 } }),
		ambient = "sparkle",
		atmosphere = { color = { 120, 255, 160 }, decay = { 20, 80, 40 }, density = 0.25, haze = 1.2 },
		music = "Bgm_hacker_lab",
		label = "💻",
	},
	developer_room = {
		floor = { 70, 110, 190 },
		floor2 = { 62, 100, 176 },
		floorMaterial = "Plastic",
		wall = { 230, 232, 240 },
		wallCap = { 60, 110, 220 },
		trim = { 60, 110, 220 },
		accent = { 255, 255, 255 },
		accent2 = { 225, 130, 50 },
		pattern = "checker",
		floorTile = { 86, 128, 206 },
		arch = "marble",
		wallDecor = "windows",
		pilaster = { 60, 110, 220 },
		decor = decor({ { "pillar", 6 }, { "statue", 3 }, { "urn", 4 }, { "crystal", 4 } }),
		scatter = decor({ { "goldcoin", 8 }, { "pebbles", 6 } }),
		ambient = "dust",
		music = "Bgm_developer_room",
		label = "🛠️",
	},
	bug_dimension = {
		floor = { 40, 20, 60 },
		floor2 = { 34, 16, 52 },
		floorMaterial = "Plastic",
		wall = { 20, 10, 30 },
		wallGlow = { 255, 0, 200 },
		trim = { 255, 0, 200 },
		accent = { 0, 255, 90 },
		accent2 = { 255, 0, 200 },
		pattern = "cracks",
		arch = "crystal",
		wallDecor = "crystals",
		pilaster = { 50, 20, 70 },
		decor = decor({ { "crystal", 10 }, { "spacerock", 8 }, { "darkspike", 5 }, { "planet", 2 } }),
		scatter = decor({ { "stars", 16 }, { "glowmoss", 6 } }),
		ambient = "stars",
		atmosphere = { color = { 255, 120, 230 }, decay = { 60, 0, 90 }, density = 0.3, haze = 1.8 },
		music = "Bgm_bug_dimension",
		label = "👾",
	},
} :: { [string]: BiomeTheme }

-- 베이스·허브(구역 밖) 분위기
Visuals.hubAtmosphere = { color = { 220, 235, 255 }, decay = { 160, 190, 230 }, density = 0.25, haze = 0.5 }

return Visuals
