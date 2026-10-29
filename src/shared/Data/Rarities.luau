--!strict
--[[
	Rarities — 등급 16개 (7판, docs/SEED_GAME_DESIGN.md 3·11장 — 사장님 순서, 2026-10-28 확정)

	7판: 6판 11개 중 맨 위 "슈퍼 울트라디바인"(super_ultradivine)을 없애고, 신성(divine) 위에 6개를 새로 둠:
	  super · hacker · original · developer · ultradivine · hacker_glitch. 옛 슈퍼 울트라디바인 식물 2종(유령 성)은 super 로.
	  (저장 데이터에는 등급 id 가 없음 — 식물 id 로만 저장 — 라서 옛 id 를 보정할 곳은 없음. SEED 9장 21번)
	6판: 5판(계란 훔치기) 10등급 + 맨 위 등급. id "eternal" → "eternity".
	name = 한국어 (문서·로그·서버 안내 글), displayName = **화면에 보이는 영어 이름** (사장님 7판 지시: "Common" …
	  "Ultradivine", 16번 hacker_glitch 는 글자 그대로 "H?a.(cke_r!#"). nameEn = 영어 이름 (문서·검색용, 보통 displayName 과 같음).
	color 는 RGB 0~255 숫자 배열 (Color3 를 쓰면 Lune 에서 못 읽으므로). 로블록스에서는 Color3.fromRGB(table.unpack(color)).
	glow: 특수 효과가 필요한 등급 (선임이 반짝임/무지개 효과 붙일 때 참고, 5판부터 있던 칸)
	aura: 씨앗·식물 둘레 아우라 종류 (6판, 설계 3장 "아우라" 칸) — 선임이 Visuals.auras 에서 이 이름으로 효과를 고름
	  "none"            없음 (일반)
	  "lime_glow"       연두 빛 (고급)
	  "blue_sparkle"    파란 반짝 (희귀)
	  "purple_flame"    보라 불꽃 (에픽)
	  "gold_ring"       금빛 링 (전설)
	  "red_lightning"   빨간 번개 (신화)
	  "stardust_swirl"  별가루 소용돌이 (코스믹)
	  "black_mist"      검은 안개 + 보라 눈 (비밀)
	  "white_clock"     흰 시계 링 (영원)
	  "rainbow_beam"    무지개 광선 (신성)
	  "sky_pillar"      무지개 + 번개 + 하늘로 솟는 빛기둥 — 맵 어디서나 보임 (슈퍼, 6판 슈퍼 울트라디바인 아우라 그대로)
	  "code_rain"       초록 코드 글자가 비처럼 흘러내림 (해커) — 7판
	  "first_light"     태초의 금빛 햇살 고리 + 오래된 별 (오리지널) — 7판
	  "build_grid"      파란 빛 격자 상자가 식물을 감쌌다 풀림 (개발자) — 7판
	  "ultra_halo"      무지개 후광 두 겹 + 빛기둥 (울트라디바인) — 7판
	  "glitch_static"   지지직 노이즈·깨진 픽셀·색이 마구 바뀜 (해커 글리치) — 7판
	baseGrowSeconds: 성체까지 기준 시간 (표 기준 = 성장 3배 적용 **전**, 설계 3장 표). 식물마다 이 근처에서 조금씩 다름
	  (Data/Plants). 실제로 걸리는 시간 = 이 값 ÷ Config.GROWTH_SPEED_MULTIPLIER(3) (Economy.growSeconds, 7판)
]]

export type RarityId =
	"common"
	| "uncommon"
	| "rare"
	| "epic"
	| "legendary"
	| "mythic"
	| "cosmic"
	| "secret"
	| "eternity"
	| "divine"
	| "super"
	| "hacker"
	| "original"
	| "developer"
	| "ultradivine"
	| "hacker_glitch"

export type Rarity = {
	id: RarityId,
	order: number,
	name: string,
	nameEn: string,
	displayName: string,
	color: { number },
	textColor: { number },
	glow: string?,
	aura: string,
	baseGrowSeconds: number,
}

local MIN = 60
local HOUR = 3600
local DAY = 86400

local list: { Rarity } = {
	{
		id = "common",
		order = 1,
		name = "일반",
		nameEn = "Common",
		displayName = "Common",
		color = { 160, 160, 160 },
		textColor = { 255, 255, 255 },
		aura = "none",
		baseGrowSeconds = 10,
	},
	{
		id = "uncommon",
		order = 2,
		name = "고급",
		nameEn = "Uncommon",
		displayName = "Uncommon",
		color = { 85, 200, 85 },
		textColor = { 255, 255, 255 },
		aura = "lime_glow",
		baseGrowSeconds = 1 * MIN,
	},
	{
		id = "rare",
		order = 3,
		name = "희귀",
		nameEn = "Rare",
		displayName = "Rare",
		color = { 60, 130, 255 },
		textColor = { 255, 255, 255 },
		aura = "blue_sparkle",
		baseGrowSeconds = 5 * MIN,
	},
	{
		id = "epic",
		order = 4,
		name = "에픽",
		nameEn = "Epic",
		displayName = "Epic",
		color = { 165, 80, 230 },
		textColor = { 255, 255, 255 },
		aura = "purple_flame",
		baseGrowSeconds = 20 * MIN,
	},
	{
		id = "legendary",
		order = 5,
		name = "전설",
		nameEn = "Legendary",
		displayName = "Legendary",
		color = { 255, 200, 40 },
		textColor = { 40, 30, 0 },
		aura = "gold_ring",
		baseGrowSeconds = 1 * HOUR,
	},
	{
		id = "mythic",
		order = 6,
		name = "신화",
		nameEn = "Mythic",
		displayName = "Mythic",
		color = { 230, 50, 50 },
		textColor = { 255, 255, 255 },
		aura = "red_lightning",
		baseGrowSeconds = 3 * HOUR,
	},
	{
		id = "cosmic",
		order = 7,
		name = "코스믹",
		nameEn = "Cosmic",
		displayName = "Cosmic",
		color = { 110, 70, 230 },
		textColor = { 200, 230, 255 },
		glow = "galaxy",
		aura = "stardust_swirl",
		baseGrowSeconds = 8 * HOUR,
	},
	{
		id = "secret",
		order = 8,
		name = "비밀",
		nameEn = "Secret",
		displayName = "Secret",
		color = { 15, 15, 15 },
		textColor = { 255, 255, 255 },
		glow = "dark",
		aura = "black_mist",
		baseGrowSeconds = 1 * DAY,
	},
	{
		id = "eternity",
		order = 9,
		name = "영원",
		nameEn = "Eternity",
		displayName = "Eternity",
		color = { 40, 220, 210 },
		textColor = { 0, 40, 40 },
		glow = "cyan",
		aura = "white_clock",
		baseGrowSeconds = 2 * DAY,
	},
	{
		id = "divine",
		order = 10,
		name = "신성",
		nameEn = "Divine",
		displayName = "Divine",
		color = { 255, 120, 220 },
		textColor = { 255, 255, 255 },
		glow = "rainbow",
		aura = "rainbow_beam",
		baseGrowSeconds = 4 * DAY,
	},
	-- 7판 새 등급 6개 (super 는 6판 슈퍼 울트라디바인 자리 — 색·아우라를 물려받음)
	{
		id = "super",
		order = 11,
		name = "슈퍼",
		nameEn = "Super",
		displayName = "Super",
		color = { 255, 245, 120 },
		textColor = { 60, 20, 90 },
		glow = "rainbow",
		aura = "sky_pillar",
		-- [수석] 본부장 예시 10일 → 8일: 유령 성 2종(7일·8일, 표 숫자 그대로)이 등급 기준 ×0.75 ~ ×1.25 안에 들게 (SEED 9장 24번)
		baseGrowSeconds = 8 * DAY,
	},
	{
		id = "hacker",
		order = 12,
		name = "해커",
		nameEn = "Hacker",
		displayName = "Hacker",
		color = { 40, 230, 90 },
		textColor = { 0, 30, 10 },
		glow = "code",
		aura = "code_rain",
		baseGrowSeconds = 14 * DAY,
	},
	{
		id = "original",
		order = 13,
		name = "오리지널",
		nameEn = "Original",
		displayName = "Original",
		color = { 225, 130, 50 },
		textColor = { 255, 250, 235 },
		glow = "gold",
		aura = "first_light",
		baseGrowSeconds = 20 * DAY,
	},
	{
		id = "developer",
		order = 14,
		name = "개발자",
		nameEn = "Developer",
		displayName = "Developer",
		color = { 30, 100, 230 },
		textColor = { 225, 240, 255 },
		glow = "blue",
		aura = "build_grid",
		baseGrowSeconds = 30 * DAY,
	},
	{
		id = "ultradivine",
		order = 15,
		name = "울트라디바인",
		nameEn = "Ultradivine",
		displayName = "Ultradivine",
		color = { 255, 255, 255 },
		textColor = { 120, 40, 160 },
		glow = "rainbow",
		aura = "ultra_halo",
		baseGrowSeconds = 45 * DAY,
	},
	{
		id = "hacker_glitch",
		order = 16,
		name = "해커 글리치",
		nameEn = "Hacker Glitch",
		displayName = "H?a.(cke_r!#", -- 사장님 지시: 글자 그대로 (깨진 글자처럼 보이는 것이 이 등급의 멋)
		color = { 255, 0, 200 },
		textColor = { 0, 255, 90 },
		glow = "glitch",
		aura = "glitch_static",
		baseGrowSeconds = 60 * DAY,
	},
}

local byId: { [string]: Rarity } = {}
for _, rarity in list do
	byId[rarity.id] = rarity
end

local Rarities = {
	list = list,
	byId = byId,
	count = #list,
	TOP = list[#list].id, -- 가장 높은 등급 (7판: hacker_glitch)
}

function Rarities.get(id: string): Rarity?
	return byId[id]
end

function Rarities.order(id: string): number
	local rarity = byId[id]
	return if rarity then rarity.order else 0
end

-- 화면에 보일 영어 등급 이름 (7판 사장님 지시). 모르는 id 면 id 그대로
function Rarities.displayName(id: string): string
	local rarity = byId[id]
	return if rarity then rarity.displayName else id
end

return Rarities
