--!strict
--[[
	Visuals — 생김새 데이터 (색·체형·장식·구역 테마). 순수 데이터 (로블록스 API 없음).

	선임 담당. 서버 PetVisualService / EggVisualService / MapBuilder 와 클라 연출이 읽습니다.
	색은 RGB 0~255 배열. Material 은 Enum.Material 이름(문자열).

	펫 체형(body) 템플릿 17종:
	  bird(새) quad(네발짐승) fish(물고기) snake(뱀) bug(곤충) spider(거미) dragon(드래곤) ghost(유령)
	  humanoid(사람형) frog(개구리) turtle(거북) whale(고래) jelly(해파리/문어) lizard(도마뱀)
	  blob(동글이) dino(공룡) penguin(펭귄)
	장식(features): 쉼표로 여러 개. PetVisualService 의 FEATURES 표에 있는 이름만 사용.
]]

export type Color = { number }

export type PetVisual = {
	body: string,
	colors: { Color }, -- [1] 몸 [2] 배/무늬 [3] 포인트
	features: { string },
	material: string?, -- 몸 재질 (기본 SmoothPlastic)
	ghostly: boolean?, -- 반투명
	glow: boolean?, -- 포인트 색을 네온으로
}

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
	PenPet = "PenPet", -- 우리에 진열된 펫 모델 (클라가 통통 튀기기)
	ParentAnimal = "ParentAnimal", -- 둥지 옆 부모 동물 모델
	GuardVisual = "GuardVisual", -- 경비 겉모습 모델
	RarityHighlight = "RarityHighlight", -- 희귀도 테두리 Highlight (클라가 가까운 것만 켬, 31개 한계)
	EggShell = "EggShell", -- 알 껍데기 비주얼 파트 (레인보우 색 순환)
	Ambient = "AmbientEmitter", -- 구역 분위기 파티클
	UpgradeSign = "UpgradeSign", -- 베이스 업그레이드 표지판 (Attr Kind = "Pen"|"Treadmill", PlotIndex) — 클라가 "업그레이드" 프롬프트
}

------------------------------------------------------------------
-- 펫 생김새 (134종 전부)
------------------------------------------------------------------

local pets: { [string]: PetVisual } = {}

type PetOpts = { material: string?, ghostly: boolean?, glow: boolean? }

local function split(text: string): { string }
	local result: { string } = {}
	for word in string.gmatch(text, "[^,%s]+") do
		table.insert(result, word)
	end
	return result
end

local function pet(id: string, body: string, c1: string, c2: string, c3: string, features: string, opts: PetOpts?)
	pets[id] = {
		body = body,
		colors = { C[c1] or C.white, C[c2] or C.white, C[c3] or C.white },
		features = split(features),
		material = if opts then opts.material else nil,
		ghostly = if opts then opts.ghostly else nil,
		glow = if opts then opts.glow else nil,
	}
end

local GLOW: PetOpts = { glow = true }
local GHOST: PetOpts = { ghostly = true, glow = true }

-- 1. 숲
pet("chicken", "bird", "white", "cream", "yellow", "comb")
pet("dog", "quad", "tan", "cream", "dbrown", "ears_floppy")
pet("bird", "bird", "blue", "sky", "yellow", "crest")
pet("burrowing_owl", "bird", "brown", "tan", "yellow", "owl_eyes")
pet("raccoon", "quad", "gray", "white", "black", "ears_pointy,mask,stripes")
pet("bear", "quad", "brown", "tan", "dbrown", "ears_round")
pet("fox", "quad", "orange", "white", "dark", "ears_pointy,tail_fluffy")
pet("brr_brr_patapim", "humanoid", "brown", "tan", "dgreen", "leaves")

-- 2. 호수
pet("frog", "frog", "green", "lime", "yellow", "")
pet("duckling", "bird", "yellow", "cream", "orange", "")
pet("catfish", "fish", "gray", "tan", "dark", "whiskers")
pet("turtle", "turtle", "green", "brown", "lime", "")
pet("trulimero_trulicina", "fish", "sky", "white", "gray", "cat_ears,legs_short")
pet("swan", "bird", "white", "cream", "orange", "long_neck")
pet("axolotl", "lizard", "pink", "white", "hotpink", "gills")
pet("leviathan", "snake", "navy", "teal", "cyan", "fins,spikes", GLOW)

-- 3. 사막
pet("jerboa", "quad", "tan", "cream", "pink", "ears_long")
pet("fennec", "quad", "cream", "white", "orange", "ears_big,tail_fluffy")
pet("camel", "quad", "tan", "cream", "brown", "hump,long_neck")
pet("tob_tobi_tob_tob", "blob", "tan", "cream", "red", "hat")
pet("snake", "snake", "green", "yellow", "dgreen", "")
pet("scorpion", "bug", "brown", "tan", "red", "claws,stinger")
pet("sand_spider", "spider", "tan", "brown", "red", "")
pet("royal_sphinx", "quad", "gold", "navy", "cyan", "pharaoh", GLOW)

-- 4. 정글
pet("toucan", "bird", "black", "white", "orange", "beak_big")
pet("chimpanzee", "humanoid", "dbrown", "tan", "black", "ears_round")
pet("crocodile", "lizard", "dgreen", "lime", "yellow", "spikes,teeth")
pet("gorilla", "humanoid", "dark", "gray", "black", "brow")
pet("orangutini_ananassini", "humanoid", "orange", "yellow", "green", "pineapple")
pet("spider", "spider", "black", "red", "purple", "")
pet("tiger", "quad", "orange", "white", "black", "ears_round,stripes")
pet("king_snake", "snake", "red", "black", "gold", "crown,stripes")

-- 5. 눈
pet("penguin", "penguin", "black", "white", "orange", "")
pet("walrus", "blob", "brown", "tan", "white", "tusks,whiskers")
pet("polar_bear", "quad", "white", "cream", "black", "ears_round")
pet("sabertooth_tiger", "quad", "tan", "cream", "white", "fangs,ears_round")
pet("mammoth", "quad", "brown", "dbrown", "cream", "tusks,trunk,ears_big")
pet("king_mammoth", "quad", "ice", "sky", "gold", "tusks,trunk,crown", GLOW)
pet("yeti", "humanoid", "white", "sky", "dark", "horns")
pet("ice_dragon", "dragon", "ice", "white", "cyan", "crystals,horns", GLOW)

-- 6. 화산
pet("lava_gecko", "lizard", "red", "orange", "lava", "lava_spots")
pet("lava_frog", "frog", "dark", "lava", "lava", "lava_spots")
pet("flaming_bull", "quad", "dred", "red", "gold", "horns,flame")
pet("lava_iguana", "lizard", "orange", "red", "black", "spikes")
pet("chillin_chili", "blob", "red", "red", "green", "stem,sunglasses")
pet("cerberus", "quad", "dark", "red", "lava", "three_heads,eyes_glow")
pet("phoenix", "bird", "lava", "gold", "red", "flame,crest", GLOW)
pet("lava_dragon", "dragon", "dark", "lava", "gold", "flame,horns", GLOW)

-- 7. 심연의 바다
pet("parrotfish", "fish", "teal", "pink", "yellow", "")
pet("swordfish", "fish", "navy", "sky", "white", "sword_nose")
pet("shark", "fish", "gray", "white", "dark", "fin_big,teeth")
pet("orca", "whale", "black", "white", "gray", "fin_big")
pet("whale_shark", "whale", "navy", "white", "sky", "spots")
pet("beluga_whale", "whale", "white", "ice", "gray", "")
pet("kraken", "jelly", "purple", "red", "pink", "eyes_glow,tentacles_thick")
pet("el_maja", "fish", "gold", "teal", "white", "crown,fin_big", GLOW)

-- 8. 선사시대
pet("dodo", "bird", "gray", "white", "yellow", "beak_big")
pet("pterodactyl", "bird", "tan", "brown", "orange", "crest,bat_wings")
pet("ankylosaurus", "quad", "olive", "tan", "brown", "spikes,club")
pet("triceratops", "quad", "green", "tan", "cream", "frill")
pet("bronto", "quad", "lime", "green", "tan", "long_neck")
pet("tralaledon", "fish", "sky", "white", "blue", "legs_short,sneakers,teeth")
pet("t_rex", "dino", "dgreen", "lime", "white", "teeth")
pet("mosasaurus", "fish", "navy", "teal", "white", "teeth,fin_big", GLOW)

-- 9. 코스믹
pet("centapede", "snake", "purple", "violet", "cyan", "legs_many,eyes_glow")
pet("cosmic_lizard", "lizard", "navy", "violet", "cyan", "stars", GLOW)
pet("cosmic_gorilla", "humanoid", "navy", "purple", "cyan", "stars,brow", GLOW)
pet("la_vacca_saturno_saturnita", "quad", "white", "black", "violet", "planet_ring,spots,horns")
pet("cosmic_dragon", "dragon", "navy", "violet", "cyan", "stars,horns", GLOW)
pet("cosmic_skeleton_boss", "humanoid", "bone", "purple", "cyan", "skull,crown", GLOW)
pet("eternal_luna_dragon", "dragon", "silver", "sky", "gold", "moon,horns", GLOW)
pet("unicorn", "quad", "white", "pink", "gold", "horn,mane", GLOW)

-- 10. 벚꽃
pet("crane", "bird", "white", "black", "red", "long_neck,comb")
pet("salamander", "lizard", "orange", "black", "yellow", "spots")
pet("red_panda", "quad", "orange", "white", "dbrown", "ears_pointy,tail_fluffy")
pet("snowy_owl", "bird", "white", "gray", "yellow", "owl_eyes")
pet("koi", "fish", "white", "orange", "red", "spots,whiskers")
pet("stag", "quad", "brown", "cream", "tan", "antlers")
pet("oni_tiger", "quad", "red", "black", "gold", "horns,stripes,eyes_glow", GLOW)
pet("kitsune", "quad", "white", "red", "pink", "ears_pointy,nine_tails", GLOW)

-- 11. 타이탄 사원
pet("crustacia", "bug", "red", "orange", "cream", "claws")
pet("spideron", "spider", "gray", "gold", "red", "armor")
pet("bladehide", "quad", "gray", "silver", "red", "blades")
pet("mantaris", "bug", "lime", "dgreen", "gold", "scythe_arms,wings")
pet("rhinotaur", "humanoid", "gray", "tan", "gold", "horn,armor")
pet("mutant_shark", "fish", "lime", "purple", "gray", "fin_big,eyes_glow,teeth")
pet("gorilla_king", "humanoid", "dark", "gold", "red", "crown,brow", GLOW)
pet("nightflame", "dragon", "black", "violet", "purple", "flame,horns", GLOW)

-- 12. 천사 & 악마 — 천국
pet("light_dove", "bird", "white", "cream", "gold", "halo")
pet("winged_lamb", "quad", "white", "cream", "gold", "wool,wings")
pet("sacred_moth", "bug", "cream", "gold", "white", "wings")
pet("holy_peacock", "bird", "teal", "gold", "white", "peacock_tail,crest")
pet("pure_jellyfish", "jelly", "white", "sky", "gold", "halo", GLOW)
pet("centaur", "quad", "tan", "white", "gold", "torso")
pet("pegasus", "quad", "white", "sky", "gold", "wings,mane", GLOW)
pet("archangel", "humanoid", "white", "gold", "sky", "wings,halo", GLOW)
-- 12. 천사 & 악마 — 지옥
pet("flame_sprite", "ghost", "lava", "orange", "yellow", "flame", GLOW)
pet("toro", "quad", "dark", "red", "gold", "horns")
pet("imp", "humanoid", "red", "dark", "yellow", "horns,tail_devil")
pet("demon_hound", "quad", "dark", "red", "lava", "horns,eyes_glow")
pet("gargoyle", "humanoid", "gray", "dark", "red", "bat_wings,horns")
pet("razorfang", "quad", "dark", "silver", "red", "fangs,blades")
pet("skeleton_horse", "quad", "bone", "dark", "cyan", "skull,mane", GLOW)
pet("world_burner", "dragon", "dark", "lava", "red", "flame,horns,eyes_glow", GLOW)
-- 12. 천사 & 악마 — 중립/합성
pet("ring_guard", "humanoid", "silver", "gold", "sky", "ring,helmet")
pet("ringlord", "humanoid", "gold", "purple", "white", "ring,crown", GLOW)
pet("equinox", "quad", "white", "dark", "gold", "wings,horn,mane", GLOW)
pet("aetheron", "dragon", "white", "gold", "violet", "halo,horns", GLOW)

-- 13. 마법의 숲
pet("prism_gecko", "lizard", "cyan", "pink", "violet", "crystals", GLOW)
pet("petal_beetle", "bug", "pink", "green", "white", "flower")
pet("enchanted_bluejay", "bird", "blue", "white", "cyan", "crest", GLOW)
pet("astral_jackalope", "quad", "violet", "white", "cyan", "ears_long,antlers", GLOW)
pet("spirit_panda", "quad", "white", "black", "mint", "ears_round,eyes_glow", GLOW)
pet("starry_fox", "quad", "navy", "violet", "yellow", "ears_pointy,tail_fluffy,stars", GLOW)
pet("celestial_sunlion", "quad", "gold", "orange", "white", "mane,halo", GLOW)
pet("royal_skywhale", "whale", "sky", "white", "gold", "crown,wings", GLOW)
pet("jitterbug", "bug", "lime", "yellow", "cyan", "wings,eyes_glow", GLOW)
pet("spirit_world_guardian", "humanoid", "mint", "white", "cyan", "antlers,halo", GHOST)

-- 14. 사탕 왕국
pet("gummy_bear", "humanoid", "red", "pink", "white", "ears_round", { material = "Glass", glow = false })
pet("lollipop_bunny", "quad", "pink", "white", "hotpink", "ears_long,lollipop")
pet("cotton_candy_sheep", "quad", "pink", "sky", "white", "wool")
pet("donut_turtle", "turtle", "tan", "pink", "yellow", "icing,sprinkles")
pet("candy_unicorn", "quad", "pink", "sky", "white", "horn,mane,sprinkles", GLOW)
pet("marshmallow_golem", "humanoid", "white", "pink", "cream", "buttons")
pet("choco_dragon", "dragon", "choco", "cream", "pink", "sprinkles,horns", GLOW)
pet("candy_king", "humanoid", "pink", "gold", "sky", "crown,lollipop", GLOW)

-- 15. 유령 성
pet("ghost_cat", "quad", "white", "violet", "cyan", "ears_pointy,eyes_glow", GHOST)
pet("pumpkin_spider", "spider", "orange", "dgreen", "black", "pumpkin")
pet("vampire_bat", "bird", "dark", "purple", "red", "bat_wings,fangs,ears_pointy")
pet("skeleton_wolf", "quad", "bone", "dark", "cyan", "skull,ears_pointy", GLOW)
pet("mummy_tiger", "quad", "cream", "tan", "orange", "bandages,ears_round,eyes_glow")
pet("zombie_bear", "quad", "zombie", "dgreen", "red", "stitches,ears_round")
pet("phantom_knight", "humanoid", "silver", "violet", "cyan", "helmet,sword", GHOST)
pet("ghost_king", "ghost", "white", "violet", "gold", "crown", GHOST)

-- 펫이 아닌 경비 전용 모양
local extra: { [string]: PetVisual } = {}
do
	local saved = pets
	pets = extra
	pet("spirit", "ghost", "mint", "cyan", "white", "antlers", GHOST)
	pet("gingerbread_giant", "humanoid", "ginger", "white", "red", "buttons,icing")
	pet("grim_reaper", "ghost", "black", "dark", "violet", "hood,scythe,eyes_glow", { glow = true })
	pet("angel", "humanoid", "white", "gold", "sky", "wings,halo", GLOW)
	pet("demon", "humanoid", "dred", "dark", "lava", "bat_wings,horns,tail_devil", GLOW)
	pets = saved
end

Visuals.pets = pets
Visuals.extra = extra

local FALLBACK: PetVisual = {
	body = "blob",
	colors = { C.white, C.cream, C.pink },
	features = {},
}

function Visuals.pet(id: string): PetVisual
	return pets[id] or extra[id] or FALLBACK
end

-- 펫 대표 색 (알 껍데기 등)
function Visuals.petColor(id: string, index: number?): Color
	local v = Visuals.pet(id)
	return v.colors[index or 1] or C.white
end

------------------------------------------------------------------
-- 경비 모양 (구역 id → 펫/extra id, 키)
--   원작처럼 거대함 (캐릭터 5~10배). height = 겉모습 키(스터드, 25~40) — PetVisualService 가 모델 키에 맞춰
--   크기 배율을 자동 계산. scale = 대략의 배율 (height 를 쓰므로 참고용)
------------------------------------------------------------------

Visuals.guards = {
	forest = { model = "chicken", scale = 10, height = 28 },
	lake = { model = "swan", scale = 8.3, height = 30 },
	desert = { model = "scorpion", scale = 18.5, height = 25 },
	jungle = { model = "tiger", scale = 11.2, height = 30 },
	snow = { model = "yeti", scale = 10.9, height = 36 },
	volcano = { model = "cerberus", scale = 12, height = 32 },
	abyss_ocean = { model = "beluga_whale", scale = 11.3, height = 26 },
	prehistoric = { model = "t_rex", scale = 11.8, height = 40 },
	cosmic = { model = "cosmic_skeleton_boss", scale = 11.5, height = 38 },
	cherry_blossom = { model = "oni_tiger", scale = 12, height = 32 },
	titan_temple = { model = "gorilla_king", scale = 11.5, height = 38 },
	angels_demons = { model = "angel", darkModel = "demon", scale = 10.9, height = 36 },
	enchanted_forest = { model = "spirit", scale = 11.2, height = 32 },
	candy_kingdom = { model = "gingerbread_giant", scale = 10.9, height = 36 },
	haunted_castle = { model = "grim_reaper", scale = 13.3, height = 38 },
} :: { [string]: { model: string, darkModel: string?, scale: number, height: number? } }

------------------------------------------------------------------
-- 희귀도 효과 / 돌연변이 효과
------------------------------------------------------------------

Visuals.rarityEffects = {
	-- 전설 이상: 외곽 빛(Highlight) + 반짝이 파티클. 알 껍데기도 이 표를 보고 빛남(light 없으면 highlight 색)
	legendary = { highlight = C.gold, particle = "sparkle", particleColor = C.gold },
	mythic = { highlight = C.red, particle = "sparkle", particleColor = C.red },
	cosmic = { highlight = C.violet, particle = "sparkle", particleColor = C.violet, light = C.violet },
	secret = { highlight = C.black, particle = "smoke", particleColor = C.black },
	eternal = { highlight = C.cyan, particle = "sparkle", particleColor = C.cyan, light = C.cyan },
	divine = { highlight = C.white, particle = "rainbow", light = C.pink },
} :: { [string]: { highlight: Color?, particle: string?, particleColor: Color?, light: Color? } }

Visuals.mutationLooks =
	{
		silver = { color = { 205, 210, 222 }, material = "Foil", reflectance = 0.35 },
		golden = { color = { 255, 200, 45 }, material = "Neon" },
		rainbow = { color = { 255, 90, 200 }, material = "Neon", cycle = true },
		bloom = { color = { 255, 170, 205 }, petals = { 255, 150, 200 } },
		spirit_bloom = { color = { 190, 130, 255 }, petals = { 180, 120, 255 } },
		fractured = { color = { 120, 60, 200 }, material = "Glass" },
		parasite = { color = { 110, 160, 40 } },
		chaos = { color = { 230, 60, 60 }, material = "Neon" },
	} :: { [string]: { color: Color, material: string?, reflectance: number?, cycle: boolean?, petals: Color? } }

-- 특별 알(비밀/영원/신성) 빔 색과 글자
Visuals.specialEggs = {
	secret = { text = "비밀 알!", color = { 40, 40, 40 }, textColor = C.white },
	eternal = { text = "영원 알!", color = C.cyan, textColor = { 0, 50, 50 } },
	divine = { text = "신성 알!", color = C.pink, textColor = C.white },
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
		decor = decor({
			{ "blockytree", 12 },
			{ "bushblock", 8 },
			{ "chick", 5 },
			{ "duck", 3 },
			{ "flowers", 6 },
			{ "rock", 3 },
		}),
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
		decor = decor({
			{ "lakewater", 1 },
			{ "reeds", 10 },
			{ "swan", 4 },
			{ "duck", 4 },
			{ "blockytree", 6 },
			{ "rock", 4 },
		}),
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
		decor = decor({ { "cactusblock", 12 }, { "pyramid", 2 }, { "rock", 6 }, { "bones", 3 } }),
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
		decor = decor({ { "blockypalm", 10 }, { "jungletree", 5 }, { "bushblock", 8 }, { "flowers", 5 } }),
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
		decor = decor({ { "icecrystal", 10 }, { "pine", 8 }, { "snowman", 3 }, { "rock", 3 } }),
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
		decor = decor({
			{ "lavawall", 1 },
			{ "lavapool", 6 },
			{ "lavarock", 8 },
			{ "volcanocone", 2 },
			{ "deadtree", 3 },
		}),
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
		decor = decor({
			{ "sandedge", 1 },
			{ "coralblock", 8 },
			{ "coral", 6 },
			{ "seaweed", 10 },
			{ "shell", 5 },
		}),
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
		decor = decor({ { "fern", 10 }, { "bigbone", 4 }, { "dinobones", 3 }, { "rock", 6 }, { "volcanocone", 1 } }),
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
		decor = decor({ { "wallstars", 1 }, { "planet", 3 }, { "spacerock", 8 }, { "crystal", 5 }, { "stars", 20 } }),
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
		decor = decor({ { "cherrytree", 10 }, { "lantern", 6 }, { "torii", 1 }, { "rock", 3 } }),
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
		decor = decor({ { "pillar", 12 }, { "brokenpillar", 5 }, { "statue", 3 }, { "jungletree", 3 } }),
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
		decor = decor({
			{ "heavenhell", 1 },
			{ "cloud", 8 },
			{ "goldpillar", 5 },
			{ "firepit", 5 },
			{ "darkspike", 6 },
		}),
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
		decor = decor({ { "glowshroom", 12 }, { "magictree", 6 }, { "crystal", 6 }, { "fairylights", 8 } }),
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
		decor = decor({
			{ "chocoriver", 1 },
			{ "lollipop", 10 },
			{ "candycane", 6 },
			{ "gumdrop", 8 },
			{ "gingerhouse", 2 },
		}),
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
		decor = decor({
			{ "castlewall", 1 },
			{ "gravestone", 12 },
			{ "deadtree", 6 },
			{ "jackolantern", 6 },
		}),
		ambient = "mist",
		atmosphere = { color = { 150, 110, 200 }, decay = { 70, 40, 100 }, density = 0.32, haze = 2 },
		music = "Bgm_haunted_castle",
		label = "👻",
	},
} :: { [string]: BiomeTheme }

-- 베이스·허브(구역 밖) 분위기
Visuals.hubAtmosphere = { color = { 220, 235, 255 }, decay = { 160, 190, 230 }, density = 0.25, haze = 0.5 }

return Visuals
