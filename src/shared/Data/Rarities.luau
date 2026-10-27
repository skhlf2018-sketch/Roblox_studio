--!strict
--[[
	Rarities — 등급 11개 (6판 "씨앗을 훔치세요", docs/SEED_GAME_DESIGN.md 3장 — 사장님 순서)

	6판: 5판(계란 훔치기) 10등급 + 맨 위 "슈퍼 울트라디바인". id "eternal" → "eternity" 로 바꿈.
	color 는 RGB 0~255 숫자 배열 (Color3 를 쓰면 Lune 에서 못 읽으므로). 로블록스에서는 Color3.fromRGB(table.unpack(color)).
	glow: 특수 효과가 필요한 등급 (선임이 반짝임/무지개 효과 붙일 때 참고, 5판부터 있던 칸)
	aura: 씨앗·식물 둘레 아우라 종류 (6판, 설계 3장 "아우라" 칸) — 선임이 Visuals 에서 이 이름으로 효과를 고름
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
	  "sky_pillar"      무지개 + 번개 + 하늘로 솟는 빛기둥 — 맵 어디서나 보임 (슈퍼 울트라디바인)
	baseGrowSeconds: 성체까지 기준 시간 (낮 기준, 설계 3장 표). 식물마다 이 근처에서 조금씩 다름 (Data/Plants)
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
	| "super_ultradivine"

export type Rarity = {
	id: RarityId,
	order: number,
	name: string,
	nameEn: string,
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
		color = { 255, 120, 220 },
		textColor = { 255, 255, 255 },
		glow = "rainbow",
		aura = "rainbow_beam",
		baseGrowSeconds = 4 * DAY,
	},
	{
		id = "super_ultradivine",
		order = 11,
		name = "슈퍼 울트라디바인",
		nameEn = "Super Ultradivine",
		color = { 255, 245, 120 },
		textColor = { 60, 20, 90 },
		glow = "rainbow",
		aura = "sky_pillar",
		baseGrowSeconds = 7 * DAY,
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
}

function Rarities.get(id: string): Rarity?
	return byId[id]
end

function Rarities.order(id: string): number
	local rarity = byId[id]
	return if rarity then rarity.order else 0
end

return Rarities
