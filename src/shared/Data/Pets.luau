--!strict
--[[
	Pets — 일반 구역 펫 전체 (설계문서 5장)

	숫자는 전부 "원본" 값입니다.
	- income: 기본 수입/초 (원본). 실제 수입은 Economy.petIncome (× GROWTH_MULTIPLIER × 크기 × 돌연변이)
	- hatchSeconds: 부화 시간(원본, 초). 실제 시간은 Economy.hatchSeconds (÷ GROWTH_MULTIPLIER)
	- source: 어디서 나오나
	    "nest"   = 둥지에서 훔침
	    "altar"  = 천사&악마 제단 제물 (2단계 이후)
	    "fusion" = 비밀 통로 합성 (2단계 이후)
	    "quest"  = 마법의 숲 퀘스트 알 (2단계 이후)
	- side: 천사&악마 구역에서 천국(light)/지옥(dark) 쪽 둥지 풀
	- estimated: 설계문서에 숫자가 빠져 있어 수석이 정한 값 (링 가드·링로드 부화 시간)
]]

export type PetSource = "nest" | "altar" | "fusion" | "quest"

export type Pet = {
	id: string,
	name: string,
	nameEn: string,
	biome: string,
	rarity: string,
	income: number,
	hatchSeconds: number,
	source: PetSource,
	side: string?,
	order: number,
	estimated: boolean?,
}

type PetOptions = {
	source: PetSource?,
	side: string?,
	estimated: boolean?,
}

local K = 1e3
local M = 1e6
local B = 1e9

local function mins(m: number, s: number?): number
	return m * 60 + (s or 0)
end

local function hours(h: number, m: number?): number
	return h * 3600 + (m or 0) * 60
end

local list: { Pet } = {}
local currentBiome = ""
local biomeCounters: { [string]: number } = {}

local function biome(id: string)
	currentBiome = id
	biomeCounters[id] = biomeCounters[id] or 0
end

local function pet(
	id: string,
	name: string,
	nameEn: string,
	rarity: string,
	income: number,
	hatchSeconds: number,
	options: PetOptions?
)
	local count = (biomeCounters[currentBiome] or 0) + 1
	biomeCounters[currentBiome] = count
	table.insert(list, {
		id = id,
		name = name,
		nameEn = nameEn,
		biome = currentBiome,
		rarity = rarity,
		income = income,
		hatchSeconds = hatchSeconds,
		source = if options and options.source then options.source else "nest",
		side = if options then options.side else nil,
		order = count,
		estimated = if options then options.estimated else nil,
	})
end

-- 1. 숲 Forest
biome("forest")
pet("chicken", "닭", "Chicken", "common", 1, 10)
pet("dog", "개", "Dog", "common", 2, 15)
pet("bird", "새", "Bird", "uncommon", 8, 25)
pet("burrowing_owl", "굴 올빼미", "Burrowing Owl", "rare", 35, 40)
pet("raccoon", "라쿤", "Raccoon", "rare", 45, 50)
pet("bear", "곰", "Bear", "epic", 240, mins(1, 30))
pet("fox", "여우", "Fox", "epic", 180, mins(2))
pet("brr_brr_patapim", "브르 브르 파타핌", "Brr Brr Patapim", "legendary", 1.8 * K, mins(5))

-- 2. 호수 Lake
biome("lake")
pet("frog", "개구리", "Frog", "common", 3, 15)
pet("duckling", "아기오리", "Duckling", "common", 4, 20)
pet("catfish", "메기", "Catfish", "uncommon", 12, 30)
pet("turtle", "거북", "Turtle", "rare", 60, 50)
pet("trulimero_trulicina", "트룰리메로 트룰리치나", "Trulimero Trulicina", "epic", 260, mins(1, 30))
pet("swan", "백조", "Swan", "epic", 320, mins(2))
pet("axolotl", "아홀로틀", "Axolotl", "legendary", 2.8 * K, mins(5))
pet("leviathan", "레비아탄", "Leviathan", "cosmic", 220 * K, mins(25))

-- 3. 사막 Desert
biome("desert")
pet("jerboa", "날쥐", "Jerboa", "common", 6, 20)
pet("fennec", "사막여우", "Fennec", "uncommon", 18, 30)
pet("camel", "낙타", "Camel", "rare", 75, 45)
pet("tob_tobi_tob_tob", "톱 토비 톱 톱", "Tob Tobi Tob Tob", "epic", 325, mins(1, 15))
pet("snake", "뱀", "Snake", "legendary", 3.6 * K, mins(2, 30))
pet("scorpion", "전갈", "Scorpion", "mythic", 18.5 * K, mins(4))
pet("sand_spider", "모래 거미", "Sand Spider", "mythic", 16 * K, mins(5))
pet("royal_sphinx", "로얄 스핑크스", "Royal Sphinx", "cosmic", 280 * K, mins(30))

-- 4. 정글 Jungle
biome("jungle")
pet("toucan", "큰부리새", "Toucan", "rare", 110, 40)
pet("chimpanzee", "침팬지", "Chimpanzee", "rare", 90, 30)
pet("crocodile", "악어", "Crocodile", "epic", 420, mins(1))
pet("gorilla", "고릴라", "Gorilla", "legendary", 4.8 * K, mins(2))
pet("orangutini_ananassini", "오랑구티니 아나나시니", "Orangutini Ananassini", "legendary", 5.5 * K, mins(2, 30))
pet("spider", "거미", "Spider", "mythic", 22 * K, mins(4, 30))
pet("tiger", "호랑이", "Tiger", "mythic", 28 * K, mins(6))
pet("king_snake", "킹 스네이크", "King Snake", "secret", 3.5 * M, hours(1, 30))

-- 5. 눈 Snow
biome("snow")
pet("penguin", "펭귄", "Penguin", "rare", 140, 45)
pet("walrus", "바다코끼리", "Walrus", "epic", 600, mins(1))
pet("polar_bear", "북극곰", "Polar Bear", "legendary", 7 * K, mins(2))
pet("sabertooth_tiger", "검치호", "Sabertooth Tiger", "mythic", 35 * K, mins(4))
pet("mammoth", "매머드", "Mammoth", "mythic", 42 * K, mins(5))
pet("king_mammoth", "킹 매머드", "King Mammoth", "cosmic", 400 * K, mins(15))
pet("yeti", "예티", "Yeti", "secret", 5 * M, hours(1, 45))
pet("ice_dragon", "아이스 드래곤", "Ice Dragon", "eternal", 65 * M, hours(4))

-- 6. 화산 Volcano
biome("volcano")
pet("lava_gecko", "용암 도마뱀", "Lava Gecko", "rare", 180, mins(1))
pet("lava_frog", "용암 개구리", "Lava Frog", "epic", 850, mins(1, 30))
pet("flaming_bull", "불타는 황소", "Flaming Bull", "legendary", 9.5 * K, mins(3))
pet("lava_iguana", "용암 이구아나", "Lava Iguana", "legendary", 11 * K, mins(4))
pet("chillin_chili", "칠린 칠리", "Chillin Chili", "mythic", 55 * K, mins(7))
pet("cerberus", "케르베로스", "Cerberus", "secret", 8 * M, hours(2))
pet("phoenix", "불사조", "Phoenix", "eternal", 85 * M, hours(4, 30))
pet("lava_dragon", "라바 드래곤", "Lava Dragon", "eternal", 100 * M, hours(5))

-- 7. 심연의 바다 Abyss Ocean
biome("abyss_ocean")
pet("parrotfish", "앵무고기", "Parrotfish", "rare", 220, mins(1, 15))
pet("swordfish", "청새치", "Swordfish", "epic", 1.1 * K, mins(2))
pet("shark", "상어", "Shark", "legendary", 15 * K, mins(4))
pet("orca", "범고래", "Orca", "mythic", 80 * K, mins(6))
pet("whale_shark", "고래상어", "Whale Shark", "cosmic", 700 * K, mins(10))
pet("beluga_whale", "벨루가 고래", "Beluga Whale", "cosmic", 850 * K, mins(12))
pet("kraken", "크라켄", "Kraken", "secret", 15 * M, hours(2, 15))
pet("el_maja", "엘 마하", "El Maja", "eternal", 130 * M, hours(5, 30))

-- 8. 선사시대 Prehistoric
biome("prehistoric")
pet("dodo", "도도새", "Dodo", "rare", 280, mins(1, 30))
pet("pterodactyl", "프테로닥틸", "Pterodactyl", "legendary", 22 * K, mins(3))
pet("ankylosaurus", "안킬로사우루스", "Ankylosaurus", "mythic", 120 * K, mins(5))
pet("triceratops", "트리케라톱스", "Triceratops", "cosmic", 1.2 * M, mins(8))
pet("bronto", "브론토", "Bronto", "cosmic", 1.5 * M, mins(11))
pet("tralaledon", "트랄랄레돈", "Tralaledon", "secret", 32 * M, hours(2, 30))
pet("t_rex", "티렉스", "T-Rex", "secret", 25 * M, hours(3))
pet("mosasaurus", "모사사우루스", "Mosasaurus", "eternal", 180 * M, hours(6))

-- 9. 코스믹 Cosmic
biome("cosmic")
pet("centapede", "지네", "Centapede", "epic", 1.5 * K, mins(2))
pet("cosmic_lizard", "코스믹 도마뱀", "Cosmic Lizard", "legendary", 30 * K, mins(4))
pet("cosmic_gorilla", "코스믹 고릴라", "Cosmic Gorilla", "mythic", 180 * K, mins(7))
pet("la_vacca_saturno_saturnita", "라 바카 사투르노 사투르니타", "La Vacca Saturno Saturnita", "cosmic", 2.2 * M, mins(13))
pet("cosmic_dragon", "코스믹 드래곤", "Cosmic Dragon", "secret", 60 * M, hours(3))
pet("cosmic_skeleton_boss", "코스믹 스켈레톤 보스", "Cosmic Skeleton Boss", "secret", 45 * M, hours(2, 30))
pet("eternal_luna_dragon", "이터널 루나 드래곤", "Eternal Luna Dragon", "eternal", 250 * M, hours(7))
pet("unicorn", "유니콘", "Unicorn", "divine", 1 * B, hours(12))

-- 10. 벚꽃 Cherry Blossom
biome("cherry_blossom")
pet("crane", "학", "Crane", "epic", 4 * K, mins(3))
pet("salamander", "도롱뇽", "Salamander", "legendary", 74 * K, mins(5))
pet("red_panda", "레서판다", "Red Panda", "mythic", 450 * K, mins(8))
pet("snowy_owl", "흰올빼미", "Snowy Owl", "cosmic", 7.5 * M, mins(15))
pet("koi", "코이", "Koi", "cosmic", 12 * M, mins(25))
pet("stag", "사슴", "Stag", "secret", 145 * M, hours(3))
pet("oni_tiger", "오니 타이거", "Oni Tiger", "eternal", 600 * M, hours(8))
pet("kitsune", "키츠네", "Kitsune", "divine", 1.8 * B, hours(14))

-- 11. 타이탄 사원 Titan Temple
biome("titan_temple")
pet("crustacia", "크러스타시아", "Crustacia", "legendary", 130 * K, mins(4))
pet("spideron", "스파이더론", "Spideron", "legendary", 95 * K, mins(6))
pet("bladehide", "블레이드하이드", "Bladehide", "mythic", 750 * K, mins(9))
pet("mantaris", "만타리스", "Mantaris", "cosmic", 11 * M, mins(17))
pet("rhinotaur", "라이노타우르", "Rhinotaur", "cosmic", 17.5 * M, mins(29))
pet("mutant_shark", "돌연변이 상어", "Mutant Shark", "secret", 215 * M, hours(3))
pet("gorilla_king", "고릴라 왕", "Gorilla King", "eternal", 880 * M, hours(9))
pet("nightflame", "나이트플레임", "Nightflame", "divine", 3 * B, hours(16))

-- 12. 천사 & 악마 Angels & Demons — 천국 쪽 (Light)
biome("angels_demons")
local LIGHT: PetOptions = { side = "light" }
local DARK: PetOptions = { side = "dark" }
pet("light_dove", "빛의 비둘기", "Light Dove", "legendary", 225 * K, mins(7), LIGHT)
pet("winged_lamb", "날개 양", "Winged Lamb", "mythic", 1.25 * M, mins(10), LIGHT)
pet("sacred_moth", "성스러운 나방", "Sacred Moth", "cosmic", 16 * M, mins(19), LIGHT)
pet("holy_peacock", "신성한 공작", "Holy Peacock", "cosmic", 25 * M, mins(33), LIGHT)
pet("pure_jellyfish", "순수한 해파리", "Pure Jellyfish", "secret", 225 * M, hours(3), LIGHT)
pet("centaur", "켄타우로스", "Centaur", "secret", 350 * M, hours(3), LIGHT)
pet("pegasus", "페가수스", "Pegasus", "eternal", 1.3 * B, hours(10), LIGHT)
pet("archangel", "대천사", "ArchAngel", "divine", 5 * B, hours(18), LIGHT)
-- 12. 천사 & 악마 — 지옥 쪽 (Dark)
pet("flame_sprite", "불꽃 정령", "Flame Sprite", "legendary", 225 * K, mins(7), DARK)
pet("toro", "토로", "Toro", "mythic", 1.25 * M, mins(10), DARK)
pet("imp", "임프", "Imp", "cosmic", 16 * M, mins(19), DARK)
pet("demon_hound", "악마 사냥개", "Demon Hound", "cosmic", 25 * M, mins(33), DARK)
pet("gargoyle", "가고일", "Gargoyle", "secret", 225 * M, hours(3), DARK)
pet("razorfang", "레이저팽", "RazorFang", "secret", 350 * M, hours(3), DARK)
pet("skeleton_horse", "스켈레톤 말", "Skeleton Horse", "eternal", 1.3 * B, hours(10), DARK)
pet("world_burner", "세계를 불태우는 자", "World Burner", "divine", 5 * B, hours(18), DARK)
-- 12. 천사 & 악마 — 중립 / 합성
pet("ring_guard", "링 가드", "Ring Guard", "secret", 15 * M, hours(2), { source = "altar", estimated = true })
pet("ringlord", "링로드", "Ringlord", "secret", 825 * M, hours(3), { source = "altar", estimated = true })
pet("equinox", "에퀴녹스", "Equinox", "eternal", 1.8 * B, hours(10), { source = "fusion" })
pet("aetheron", "에테론", "Aetheron", "divine", 6.9 * B, hours(18), { source = "fusion" })

-- 13. 마법의 숲 Enchanted Forest
biome("enchanted_forest")
pet("prism_gecko", "프리즘 도마뱀", "Prism Gecko", "legendary", 350 * K, mins(8))
pet("petal_beetle", "꽃잎 딱정벌레", "Petal Beetle", "mythic", 1.2 * M, mins(11))
pet("enchanted_bluejay", "마법 어치", "Enchanted Bluejay", "mythic", 2.5 * M, mins(13))
pet("astral_jackalope", "별빛 뿔토끼", "Astral Jackalope", "cosmic", 30 * M, mins(21))
pet("spirit_panda", "정령 판다", "Spirit Panda", "cosmic", 90 * M, mins(37))
pet("starry_fox", "별 여우", "Starry Fox", "secret", 750 * M, hours(3))
pet("celestial_sunlion", "천상의 사자", "Celestial Sunlion", "eternal", 2 * B, hours(11))
pet("royal_skywhale", "왕의 하늘고래", "Royal Skywhale", "divine", 8 * B, hours(20))
pet("jitterbug", "지터버그", "Jitterbug", "secret", 130 * M, 20, { source = "quest" })
pet("spirit_world_guardian", "영혼 세계 수호자", "Spirit World Guardian", "divine", 26 * B, hours(20), { source = "quest" })

-- 14. 사탕 왕국 Candy Kingdom (신규)
biome("candy_kingdom")
pet("gummy_bear", "젤리곰", "Gummy Bear", "legendary", 1 * M, mins(10))
pet("lollipop_bunny", "롤리팝 토끼", "Lollipop Bunny", "mythic", 5 * M, mins(14))
pet("cotton_candy_sheep", "솜사탕 양", "Cotton Candy Sheep", "cosmic", 60 * M, mins(25))
pet("donut_turtle", "도넛 거북", "Donut Turtle", "cosmic", 200 * M, mins(40))
pet("candy_unicorn", "캔디 유니콘", "Candy Unicorn", "secret", 1.5 * B, hours(3, 30))
pet("marshmallow_golem", "마시멜로 골렘", "Marshmallow Golem", "secret", 2.5 * B, hours(3, 30))
pet("choco_dragon", "초코 드래곤", "Choco Dragon", "eternal", 4 * B, hours(12))
pet("candy_king", "사탕 왕", "Candy King", "divine", 15 * B, hours(22))

-- 15. 유령 성 Haunted Castle (신규)
biome("haunted_castle")
pet("ghost_cat", "유령 고양이", "Ghost Cat", "legendary", 2.5 * M, mins(12))
pet("pumpkin_spider", "호박 거미", "Pumpkin Spider", "mythic", 12 * M, mins(16))
pet("vampire_bat", "뱀파이어 박쥐", "Vampire Bat", "cosmic", 150 * M, mins(30))
pet("skeleton_wolf", "해골 늑대", "Skeleton Wolf", "cosmic", 500 * M, mins(45))
pet("mummy_tiger", "미라 호랑이", "Mummy Tiger", "secret", 3.5 * B, hours(4))
pet("zombie_bear", "좀비 곰", "Zombie Bear", "secret", 6 * B, hours(4))
pet("phantom_knight", "유령 기사", "Phantom Knight", "eternal", 10 * B, hours(14))
pet("ghost_king", "유령 왕", "Ghost King", "divine", 30 * B, hours(24))

------------------------------------------------------------------
-- 색인
------------------------------------------------------------------
local byId: { [string]: Pet } = {}
local byBiome: { [string]: { Pet } } = {}
for _, entry in list do
	assert(byId[entry.id] == nil, "Pets: 중복 id " .. entry.id)
	byId[entry.id] = entry
	local bucket = byBiome[entry.biome]
	if not bucket then
		bucket = {}
		byBiome[entry.biome] = bucket
	end
	table.insert(bucket, entry)
end

local Pets = {
	list = list,
	byId = byId,
	byBiome = byBiome,
	count = #list,
}

function Pets.get(id: string): Pet?
	return byId[id]
end

function Pets.inBiome(biomeId: string): { Pet }
	return byBiome[biomeId] or {}
end

return Pets
