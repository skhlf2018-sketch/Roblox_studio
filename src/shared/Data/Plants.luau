--!strict
--[[
	Plants — 식물 158종 (7판, docs/SEED_GAME_DESIGN.md 10장 표와 같아야 함 — tests/design_doc.spec)
	6판 134종(5판 Pets 자리) + 7판 새 구역 3개 × 8종. 이름·모양은 우리가 새로 지은 것 (유명 게임 이름·캐릭터 안 씀).

	- growSeconds: 씨앗을 심어서 성체가 될 때까지의 **표 시간** (낮 기준 초). 설계 3장 등급 기준(Rarities.baseGrowSeconds)에서
	    등급 안에서 ×0.8 / ×1 / ×1.25 정도로 조금씩 다름.
	    7판 성장 3배: 실제 시간 = 이 값 ÷ Config.GROWTH_SPEED_MULTIPLIER(3) — 나누기는 Economy.growSeconds 한 곳에서만
	    (표 숫자는 그대로). 밤에는 거기서 또 30배 빨리 자람 (Config.NIGHT_GROWTH_MULTIPLIER).
	    예외: 숲의 강아지풀 3초 (표 3초 → 실제 1초, 튜토리얼 4단계 "성체가 될 때까지 기다리기" 를 빨리 — 5판 개 알 자리)
	  hatchSeconds: growSeconds 와 같은 값 (5판 코드 호환용 별칭, 정리 예정)
	- fruitIntervalSeconds: 성체가 열매 1개를 맺는 간격(초). 등급이 높을수록 짧음 (일반 30초 → 해커 글리치 4초)
	- fruitValue: 열매 1개 값(코인, 크기·돌연변이 전). 등급이 높을수록 큼. 실제 값 = FruitRules.fruitValue
	- income: 열매로 환산한 초당 코인 = fruitValue / fruitIntervalSeconds (표시·밸런스 확인용. 6판은 자동 수입 없음)
	- source: 어디서 나오나
	    "nest"    = 둥지에서 훔침 (EggSpawn 구역별 등급 가중치)
	    "special" = 초기화 때 낮은 확률로만 나오는 공지 씨앗 (Data/EggSpawn.EXTRA_SPECIALS, 둥지 일반 추첨에는 안 나옴)
	    "sakura"  = 사쿠라 나무 뽑기로만 (벚꽃 씨앗 · 정령 벚꽃 씨앗, Config.SAKURA_SEEDS)
	- side: 천사 & 악마 구역에서 천국(light)/지옥(dark) 쪽 둥지 풀 (주기마다 바뀜)
	- seedName: 씨앗 이름이 "식물 이름 + 씨앗" 이 아닐 때만 (사쿠라 씨앗 2종)
]]

export type PlantSource = "nest" | "special" | "sakura"

export type Plant = {
	id: string,
	name: string,
	nameEn: string,
	biome: string,
	rarity: string,
	growSeconds: number,
	hatchSeconds: number, -- = growSeconds (5판 호환 별칭)
	fruitIntervalSeconds: number,
	fruitValue: number,
	income: number, -- = fruitValue / fruitIntervalSeconds (표시용)
	source: PlantSource,
	side: string?,
	seedName: string?,
	order: number,
}

type PlantOptions = {
	source: PlantSource?,
	side: string?,
	seedName: string?,
}

local K = 1e3
local M = 1e6
local B = 1e9
local T = 1e12
local Qa = 1e15

local function mins(m: number, s: number?): number
	return m * 60 + (s or 0)
end

local function hours(h: number, m: number?): number
	return h * 3600 + (m or 0) * 60
end

local function days(d: number): number
	return d * 86400
end

local list: { Plant } = {}
local currentBiome = ""
local biomeCounters: { [string]: number } = {}

local function biome(id: string)
	currentBiome = id
	biomeCounters[id] = biomeCounters[id] or 0
end

-- plant(id, 이름, 영어 이름, 등급, 성체까지 초, 열매 간격 초, 열매 값, 옵션)
local function plant(
	id: string,
	name: string,
	nameEn: string,
	rarity: string,
	growSeconds: number,
	fruitIntervalSeconds: number,
	fruitValue: number,
	options: PlantOptions?
)
	local count = (biomeCounters[currentBiome] or 0) + 1
	biomeCounters[currentBiome] = count
	table.insert(list, {
		id = id,
		name = name,
		nameEn = nameEn,
		biome = currentBiome,
		rarity = rarity,
		growSeconds = growSeconds,
		hatchSeconds = growSeconds,
		fruitIntervalSeconds = fruitIntervalSeconds,
		fruitValue = fruitValue,
		income = fruitValue / fruitIntervalSeconds,
		source = if options and options.source then options.source else "nest",
		side = if options then options.side else nil,
		seedName = if options then options.seedName else nil,
		order = count,
	})
end

-- 1. 숲 Forest — 일반·고급, 가끔 희귀
biome("forest")
plant("sprout_daisy", "아기 데이지", "Baby Daisy", "common", 10, 30, 10)
plant("puppy_grass", "강아지풀", "Puppy Grass", "common", 3, 30, 8) -- 튜토리얼용 3초 (5판 개 알 자리)
plant("acorn_sprout", "도토리 새싹", "Acorn Sprout", "common", 12, 29, 12)
plant("mossy_fern", "이끼 고사리", "Mossy Fern", "uncommon", 50, 29, 36)
plant("bell_mushroom", "종소리 버섯", "Bell Mushroom", "uncommon", 60, 28, 40)
plant("honey_tulip", "꿀 튤립", "Honey Tulip", "uncommon", 75, 27, 48)
plant("owl_oak", "부엉이 참나무", "Owl Oak", "rare", mins(4), 27, 180)
plant("firefly_lily", "반딧불 백합", "Firefly Lily", "rare", mins(5), 26, 200)

-- 2. 호수 Lake — 일반·고급, 가끔 희귀
biome("lake")
plant("water_clover", "물 클로버", "Water Clover", "common", 8, 31, 10)
plant("ripple_reed", "물결 갈대", "Ripple Reed", "common", 10, 30, 11)
plant("bubble_cress", "방울 물냉이", "Bubble Cress", "common", 12, 29, 13)
plant("lotus_pad", "연잎 방석", "Lotus Pad", "uncommon", 50, 29, 40)
plant("dewdrop_iris", "이슬 붓꽃", "Dewdrop Iris", "uncommon", 60, 28, 44)
plant("frog_lily", "개구리 수련", "Frog Lily", "uncommon", 75, 27, 53)
plant("moon_lotus", "달빛 연꽃", "Moon Lotus", "rare", mins(5), 26, 220)
plant("rain_willow", "비 버드나무", "Rain Willow", "rare", mins(6, 15), 25, 260)

-- 3. 사막 Desert — 고급·희귀, 가끔 에픽
biome("desert")
plant("sand_sprout", "모래 새싹", "Sand Sprout", "uncommon", 50, 29, 36)
plant("pebble_cactus", "조약돌 선인장", "Pebble Cactus", "uncommon", 60, 28, 40)
plant("dune_grass", "모래언덕 풀", "Dune Grass", "uncommon", 75, 27, 48)
plant("sun_aloe", "햇볕 알로에", "Sun Aloe", "rare", mins(4), 27, 180)
plant("camel_thorn", "낙타 가시풀", "Camel Thorn", "rare", mins(5), 26, 200)
plant("mirage_rose", "신기루 장미", "Mirage Rose", "rare", mins(6, 15), 25, 240)
plant("pharaoh_palm", "파라오 야자", "Pharaoh Palm", "epic", mins(16), 25, 1.1 * K)
plant("scorpion_cactus", "전갈 선인장", "Scorpion Cactus", "epic", mins(20), 24, 1.2 * K)

-- 4. 정글 Jungle — 고급·희귀, 가끔 에픽
biome("jungle")
plant("banana_leaf", "바나나 잎", "Banana Leaf", "uncommon", 50, 29, 40)
plant("vine_twist", "꼬불 덩굴", "Twisty Vine", "uncommon", 60, 28, 44)
plant("parrot_flower", "앵무새 꽃", "Parrot Flower", "uncommon", 75, 27, 53)
plant("drum_gourd", "북 박", "Drum Gourd", "rare", mins(4), 27, 200)
plant("monkey_fruit", "원숭이 열매나무", "Monkey Fruit Tree", "rare", mins(5), 26, 220)
plant("jungle_pitcher", "항아리 풀", "Pitcher Plant", "rare", mins(6, 15), 25, 260)
plant("tiger_orchid", "호랑이 난초", "Tiger Orchid", "epic", mins(20), 24, 1.3 * K)
plant("thunder_bamboo", "천둥 대나무", "Thunder Bamboo", "epic", mins(25), 23, 1.6 * K)

-- 5. 눈 Snow — 희귀·에픽, 가끔 전설
biome("snow")
plant("snow_bell", "눈방울꽃", "Snowbell", "rare", mins(4), 27, 180)
plant("frost_pine", "서리 소나무", "Frost Pine", "rare", mins(5), 26, 200)
plant("ice_cactus", "얼음 선인장", "Ice Cactus", "rare", mins(6, 15), 25, 240)
plant("penguin_tulip", "펭귄 튤립", "Penguin Tulip", "epic", mins(16), 25, 1.1 * K)
plant("aurora_fern", "오로라 고사리", "Aurora Fern", "epic", mins(20), 24, 1.2 * K)
plant("icicle_rose", "고드름 장미", "Icicle Rose", "epic", mins(25), 23, 1.45 * K)
plant("yeti_cabbage", "설인 배추", "Yeti Cabbage", "legendary", mins(48), 23, 7.2 * K)
plant("crystal_snowdrop", "수정 설강화", "Crystal Snowdrop", "legendary", hours(1), 22, 8 * K)

-- 6. 화산 Volcano — 희귀·에픽, 가끔 전설
biome("volcano")
plant("ember_sprout", "불씨 새싹", "Ember Sprout", "rare", mins(4), 27, 200)
plant("lava_moss", "용암 이끼", "Lava Moss", "rare", mins(5), 26, 220)
plant("ash_pepper", "잿빛 고추", "Ash Pepper", "rare", mins(6, 15), 25, 260)
plant("flame_sunflower", "불꽃 해바라기", "Flame Sunflower", "epic", mins(16), 25, 1.2 * K)
plant("magma_cactus", "마그마 선인장", "Magma Cactus", "epic", mins(20), 24, 1.3 * K)
plant("smoke_tulip", "연기 튤립", "Smoke Tulip", "epic", mins(25), 23, 1.6 * K)
plant("phoenix_lily", "불사조 백합", "Phoenix Lily", "legendary", hours(1), 22, 8.8 * K)
plant("volcano_rose", "화산 장미", "Volcano Rose", "legendary", hours(1, 15), 21, 11 * K)

-- 7. 심연의 바다 Abyss Ocean — 에픽·전설, 가끔 신화
biome("abyss_ocean")
plant("coral_bloom", "산호 꽃", "Coral Bloom", "epic", mins(16), 25, 1.1 * K)
plant("kelp_tower", "다시마 탑", "Kelp Tower", "epic", mins(20), 24, 1.2 * K)
plant("glow_anemone", "빛 말미잘꽃", "Glow Anemone", "epic", mins(25), 23, 1.45 * K)
plant("pearl_shell_flower", "진주 조개꽃", "Pearl Shell Flower", "legendary", mins(48), 23, 7.2 * K)
plant("jelly_tulip", "해파리 튤립", "Jelly Tulip", "legendary", hours(1), 22, 8 * K)
plant("deep_lantern", "심해 등불꽃", "Deep Lantern Flower", "legendary", hours(1, 15), 21, 9.6 * K)
plant("whale_kelp", "고래 해초", "Whale Kelp", "mythic", hours(2, 24), 21, 54 * K)
plant("abyss_orchid", "심연 난초", "Abyss Orchid", "mythic", hours(3), 20, 60 * K)

-- 8. 선사시대 Prehistoric — 에픽·전설, 가끔 신화
biome("prehistoric")
plant("fossil_fern", "화석 고사리", "Fossil Fern", "epic", mins(16), 25, 1.2 * K)
plant("amber_moss", "호박석 이끼", "Amber Moss", "epic", mins(20), 24, 1.3 * K)
plant("giant_horsetail", "거대 쇠뜨기", "Giant Horsetail", "epic", mins(25), 23, 1.6 * K)
plant("dino_eggplant", "공룡알 가지", "Dino Eggplant", "legendary", mins(48), 23, 7.9 * K)
plant("tar_flower", "타르 꽃", "Tar Flower", "legendary", hours(1), 22, 8.8 * K)
plant("cycad_king", "소철 왕", "Cycad King", "legendary", hours(1, 15), 21, 11 * K)
plant("claw_vine", "발톱 덩굴", "Claw Vine", "mythic", hours(3), 20, 66 * K)
plant("mammoth_tree", "매머드 나무", "Mammoth Tree", "mythic", hours(3, 45), 19, 79 * K)

-- 9. 코스믹 Cosmic — 전설·신화, 가끔 코스믹
biome("cosmic")
plant("star_mushroom", "별 버섯", "Star Mushroom", "legendary", mins(48), 23, 7.2 * K)
plant("comet_tulip", "혜성 튤립", "Comet Tulip", "legendary", hours(1), 22, 8 * K)
plant("moon_cabbage", "달 양배추", "Moon Cabbage", "legendary", hours(1, 15), 21, 9.6 * K)
plant("nebula_rose", "성운 장미", "Nebula Rose", "mythic", hours(2, 24), 21, 54 * K)
plant("planet_pumpkin", "행성 호박", "Planet Pumpkin", "mythic", hours(3), 20, 60 * K)
plant("meteor_cactus", "유성 선인장", "Meteor Cactus", "mythic", hours(3, 45), 19, 72 * K)
plant("galaxy_tree", "은하수 나무", "Galaxy Tree", "cosmic", hours(6, 24), 19, 450 * K)
plant("blackhole_lily", "블랙홀 백합", "Black Hole Lily", "cosmic", hours(8), 18, 500 * K)

-- 10. 벚꽃 Cherry Blossom — 전설·신화, 가끔 코스믹 (+ 사쿠라 나무 뽑기 씨앗 2종)
biome("cherry_blossom")
plant("petal_sprout", "꽃잎 새싹", "Petal Sprout", "legendary", mins(48), 23, 7.9 * K)
plant("lantern_peony", "등불 모란", "Lantern Peony", "legendary", hours(1), 22, 8.8 * K)
plant("tea_camellia", "녹차 동백", "Tea Camellia", "legendary", hours(1, 15), 21, 11 * K)
plant("koi_lotus", "잉어 연꽃", "Koi Lotus", "mythic", hours(2, 24), 21, 59 * K)
plant("bonsai_pine", "분재 소나무", "Bonsai Pine", "mythic", hours(3), 20, 66 * K)
plant("fan_ginkgo", "부채 은행나무", "Fan Ginkgo", "mythic", hours(3, 45), 19, 79 * K)
plant("moon_plum", "달빛 매화", "Moon Plum", "cosmic", hours(8), 18, 550 * K)
plant("dragon_wisteria", "용 등나무", "Dragon Wisteria", "cosmic", hours(10), 17, 660 * K)
plant(
	"blossom_fairy",
	"벚꽃 요정 나무",
	"Blossom Fairy Tree",
	"cosmic",
	hours(8),
	18,
	600 * K,
	{ source = "sakura", seedName = "벚꽃 씨앗" }
)
plant(
	"spirit_blossom",
	"정령 벚꽃 나무",
	"Spirit Blossom Tree",
	"secret",
	hours(24),
	16,
	6 * M,
	{ source = "sakura", seedName = "정령 벚꽃 씨앗" }
)

-- 11. 타이탄 사원 Titan Temple — 신화·코스믹, 가끔 비밀
biome("titan_temple")
plant("stone_lotus", "돌 연꽃", "Stone Lotus", "mythic", hours(2, 24), 21, 54 * K)
plant("pillar_cactus", "기둥 선인장", "Pillar Cactus", "mythic", hours(3), 20, 60 * K)
plant("titan_moss", "거인 이끼", "Titan Moss", "mythic", hours(3, 45), 19, 72 * K)
plant("golden_vine", "황금 덩굴", "Golden Vine", "cosmic", hours(6, 24), 19, 450 * K)
plant("relic_rose", "유물 장미", "Relic Rose", "cosmic", hours(8), 18, 500 * K)
plant("gong_flower", "징 꽃", "Gong Flower", "cosmic", hours(10), 17, 600 * K)
plant("colossus_tree", "거신 나무", "Colossus Tree", "secret", hours(19, 12), 17, 4.5 * M)
plant("temple_bloom", "신전 꽃", "Temple Bloom", "secret", hours(24), 16, 5 * M)

-- 12. 천사 & 악마 Angels & Demons — 신화·코스믹, 가끔 비밀. 천국 쪽 (Light)
biome("angels_demons")
local LIGHT: PlantOptions = { side = "light" }
local DARK: PlantOptions = { side = "dark" }
plant("halo_daisy", "후광 데이지", "Halo Daisy", "mythic", hours(2, 24), 21, 59 * K, LIGHT)
plant("feather_fern", "깃털 고사리", "Feather Fern", "mythic", hours(3), 20, 66 * K, LIGHT)
plant("cloud_cotton", "구름 목화", "Cloud Cotton", "mythic", hours(3, 45), 19, 79 * K, LIGHT)
plant("harp_lily", "하프 백합", "Harp Lily", "cosmic", hours(6, 24), 19, 500 * K, LIGHT)
plant("dawn_rose", "새벽 장미", "Dawn Rose", "cosmic", hours(8), 18, 550 * K, LIGHT)
plant("angel_trumpet", "천사 나팔꽃", "Angel Trumpet", "cosmic", hours(10), 17, 660 * K, LIGHT)
plant("heaven_tree", "천국 나무", "Heaven Tree", "secret", hours(24), 16, 5.5 * M, LIGHT)
plant("seraph_lotus", "날개 연꽃", "Winged Lotus", "secret", hours(30), 15, 6.6 * M, LIGHT)
-- 12. 천사 & 악마 — 지옥 쪽 (Dark)
plant("horn_thistle", "뿔 엉겅퀴", "Horn Thistle", "mythic", hours(2, 24), 21, 59 * K, DARK)
plant("bat_flower", "박쥐 꽃", "Bat Flower", "mythic", hours(3), 20, 66 * K, DARK)
plant("shadow_ivy", "그림자 담쟁이", "Shadow Ivy", "mythic", hours(3, 45), 19, 79 * K, DARK)
plant("trident_cactus", "삼지창 선인장", "Trident Cactus", "cosmic", hours(6, 24), 19, 500 * K, DARK)
plant("devil_pepper", "악마 고추", "Devil Pepper", "cosmic", hours(8), 18, 550 * K, DARK)
plant("lava_nightshade", "용암 가지꽃", "Lava Nightshade", "cosmic", hours(10), 17, 660 * K, DARK)
plant("inferno_tree", "지옥불 나무", "Inferno Tree", "secret", hours(24), 16, 5.5 * M, DARK)
plant("demon_rose", "악마 장미", "Demon Rose", "secret", hours(30), 15, 6.6 * M, DARK)
-- 12. 천사 & 악마 — 쪽 없음, 초기화 공지 씨앗 (5판 제단·합성 펫 자리)
plant("twilight_bloom", "황혼 꽃", "Twilight Bloom", "eternity", days(2), 14, 50 * M, { source = "special" })
plant("balance_tree", "균형의 나무", "Tree of Balance", "divine", days(4), 12, 600 * M, { source = "special" })

-- 13. 마법의 숲 Enchanted Forest — 코스믹·비밀, 가끔 영원 (+ 초기화 공지 씨앗 2종, 5판 특별 알 자리)
biome("enchanted_forest")
plant("fairy_bell", "요정 종꽃", "Fairy Bell", "cosmic", hours(6, 24), 19, 450 * K)
plant("wish_dandelion", "소원 민들레", "Wish Dandelion", "cosmic", hours(8), 18, 500 * K)
plant("glow_toadstool", "빛 버섯", "Glow Toadstool", "cosmic", hours(10), 17, 600 * K)
plant("unicorn_ivy", "유니콘 덩굴", "Unicorn Ivy", "secret", hours(19, 12), 17, 4.5 * M)
plant("rune_rose", "룬 장미", "Rune Rose", "secret", hours(24), 16, 5 * M)
plant("spell_lily", "주문 백합", "Spell Lily", "secret", hours(30), 15, 6 * M)
plant("elder_tree", "할아버지 나무", "Elder Tree", "eternity", hours(38, 24), 15, 45 * M)
plant("crystal_willow", "수정 버드나무", "Crystal Willow", "eternity", days(2), 14, 50 * M)
plant(
	"dancing_mushroom",
	"춤추는 버섯",
	"Dancing Mushroom",
	"eternity",
	days(2),
	14,
	55 * M,
	{ source = "special" }
)
plant("world_tree", "세계수", "World Tree", "divine", days(4), 12, 700 * M, { source = "special" })

-- 14. 사탕 왕국 Candy Kingdom — 비밀·영원, 가끔 신성
biome("candy_kingdom")
plant("lollipop_flower", "막대사탕 꽃", "Lollipop Flower", "secret", hours(19, 12), 17, 4.5 * M)
plant("gummy_cactus", "젤리 선인장", "Gummy Cactus", "secret", hours(24), 16, 5 * M)
plant("cotton_candy_tree", "솜사탕 나무", "Cotton Candy Tree", "secret", hours(30), 15, 6 * M)
plant("chocolate_tulip", "초콜릿 튤립", "Chocolate Tulip", "eternity", hours(38, 24), 15, 45 * M)
plant("candy_cane_reed", "지팡이사탕 갈대", "Candy Cane Reed", "eternity", days(2), 14, 50 * M)
plant("donut_sunflower", "도넛 해바라기", "Donut Sunflower", "eternity", hours(60), 13, 60 * M)
plant("cake_rose", "케이크 장미", "Cake Rose", "divine", hours(76, 48), 13, 540 * M)
plant("sugar_crown", "설탕 왕관꽃", "Sugar Crown", "divine", days(4), 12, 600 * M)

-- 15. 유령 성 Haunted Castle — 영원·신성, 가끔 슈퍼 (7판: 6판 슈퍼 울트라디바인 2종 → 슈퍼, 숫자는 그대로)
biome("haunted_castle")
plant("ghost_lily", "유령 백합", "Ghost Lily", "eternity", hours(38, 24), 15, 50 * M)
plant("pumpkin_vine", "호박 덩굴", "Pumpkin Vine", "eternity", days(2), 14, 55 * M)
plant("bat_orchid", "박쥐 난초", "Bat Orchid", "eternity", hours(60), 13, 66 * M)
plant("candle_mushroom", "촛불 버섯", "Candle Mushroom", "divine", hours(76, 48), 13, 600 * M)
plant("skull_rose", "해골 장미", "Skull Rose", "divine", days(4), 12, 660 * M)
plant("moon_ghost_tree", "달빛 유령나무", "Moon Ghost Tree", "divine", days(5), 11, 790 * M)
plant("rainbow_thunder_tree", "무지개 번개나무", "Rainbow Thunder Tree", "super", days(7), 10, 10 * B)
plant("sky_pillar_flower", "하늘 기둥꽃", "Sky Pillar Flower", "super", days(8), 9, 12 * B)

-- 16. 해커 연구소 Hacker Lab — 슈퍼·해커, 가끔 오리지널 (7판)
biome("hacker_lab")
plant("circuit_sprout", "회로 새싹", "Circuit Sprout", "super", days(6) + hours(9, 36), 10, 11 * B)
plant("password_fern", "비밀번호 고사리", "Password Fern", "super", days(8), 10, 13 * B)
plant("wifi_sunflower", "와이파이 해바라기", "Wi-Fi Sunflower", "super", days(10), 9, 15 * B)
plant("firewall_cactus", "방화벽 선인장", "Firewall Cactus", "hacker", days(11) + hours(4, 48), 9, 120 * B)
plant("virus_mushroom", "바이러스 버섯", "Virus Mushroom", "hacker", days(14), 9, 150 * B)
plant("code_vine", "코드 덩굴", "Code Vine", "hacker", days(14), 8, 160 * B)
plant("pixel_rose", "픽셀 장미", "Pixel Rose", "hacker", days(17) + hours(12), 8, 180 * B)
plant("mainframe_tree", "메인프레임 나무", "Mainframe Tree", "original", days(16), 8, 1.5 * T)

-- 17. 개발자의 방 Developer's Room — 오리지널·개발자, 가끔 울트라디바인 (7판)
biome("developer_room")
plant("keyboard_tulip", "키보드 튤립", "Keyboard Tulip", "original", days(16), 8, 1.6 * T)
plant("coffee_bean_tree", "커피콩 나무", "Coffee Bean Tree", "original", days(20), 8, 1.8 * T)
plant("monitor_lily", "모니터 백합", "Monitor Lily", "original", days(25), 7, 2.2 * T)
plant("script_fern", "스크립트 고사리", "Script Fern", "developer", days(24), 7, 18 * T)
plant("bug_catcher_bloom", "버그 잡이 꽃", "Bug Catcher Bloom", "developer", days(30), 7, 22 * T)
plant("block_mushroom", "블록 버섯", "Block Mushroom", "developer", days(30), 6, 24 * T)
plant("studio_tree", "스튜디오 나무", "Studio Tree", "developer", days(37) + hours(12), 6, 27 * T)
plant(
	"update_rainbow_flower",
	"업데이트 무지개꽃",
	"Update Rainbow Flower",
	"ultradivine",
	days(36),
	6,
	220 * T
)

-- 18. 버그 차원 Bug Dimension — 개발자·울트라디바인, 아주 가끔 해커 글리치 (7판, 화면 등급 이름 "H?a.(cke_r!#")
biome("bug_dimension")
plant("broken_pixel_flower", "깨진 픽셀 꽃", "Broken Pixel Flower", "developer", days(24), 7, 20 * T)
plant("laggy_cactus", "렉 걸린 선인장", "Laggy Cactus", "developer", days(37) + hours(12), 6, 25 * T)
plant("infinite_loop_vine", "무한 루프 덩굴", "Infinite Loop Vine", "ultradivine", days(36), 6, 230 * T)
plant("upside_down_tree", "거꾸로 나무", "Upside-Down Tree", "ultradivine", days(45), 6, 270 * T)
plant("missing_lotus", "사라진 연꽃", "Missing Lotus", "ultradivine", days(45), 5, 300 * T)
plant("error_rose", "오류 장미", "Error Rose", "ultradivine", days(56) + hours(6), 5, 330 * T)
plant("glitch_hacker_bloom", "글리치 해커 꽃", "Glitch Hacker Bloom", "hacker_glitch", days(48), 5, 2.7 * Qa)
plant("static_world_tree", "지지직 세계수", "Static World Tree", "hacker_glitch", days(60), 4, 3.3 * Qa)

------------------------------------------------------------------
-- 색인
------------------------------------------------------------------
local byId: { [string]: Plant } = {}
local byBiome: { [string]: { Plant } } = {}
for _, entry in list do
	assert(byId[entry.id] == nil, "Plants: 중복 id " .. entry.id)
	byId[entry.id] = entry
	local bucket = byBiome[entry.biome]
	if not bucket then
		bucket = {}
		byBiome[entry.biome] = bucket
	end
	table.insert(bucket, entry)
end

local Plants = {
	list = list,
	byId = byId,
	byBiome = byBiome,
	count = #list,
}

function Plants.get(id: string): Plant?
	return byId[id]
end

function Plants.inBiome(biomeId: string): { Plant }
	return byBiome[biomeId] or {}
end

-- 씨앗 이름 ("강아지풀 씨앗", 사쿠라 씨앗은 "벚꽃 씨앗"). 모르는 id 면 "씨앗"
function Plants.seedName(id: string): string
	local entry = byId[id]
	if not entry then
		return "씨앗"
	end
	return entry.seedName or (entry.name .. " 씨앗")
end

return Plants
