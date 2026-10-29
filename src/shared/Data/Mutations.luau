--!strict
--[[
	Mutations — 돌연변이 (6판 "씨앗을 훔치세요", docs/SEED_GAME_DESIGN.md 5장·13장)

	- multiplier: 열매 값 배율 (5판: 펫 수입 배율). 여러 개면 전부 곱함 (예: 황금 2 × 불 1.5 = 3배)
	- group: 같은 group 안에서는 1개만 가질 수 있음
	    "natural" = 실버/황금/무지개 중 최대 1개 (둥지 씨앗에 자연 등장, 열매 먹이기로도 더 좋은 것으로 바뀜)
	    "element" = 얼음/불/번개 중 최대 1개 (열매 먹이기로만)
	- naturalChance: 둥지에 씨앗이 놓일 때 자연 등장 확률 (0~1). natural 그룹만 사용.
	- feedChance: 6판 열매 먹이기(FeedFruit) 한 번에 이 돌연변이가 붙을 기본 확률 (0~1, 없으면 먹이기로 안 나옴)
	- feedBiomes: 이 구역 식물의 열매를 먹이면 확률 × Mutations.FEED_BIOME_BONUS (얼음 ← 눈 구역 열매 등)
	  실제 확률 계산·적용은 shared/FruitRules.luau (등급 높은 열매일수록 확률 ↑, 합 상한 FEED_MAX_CHANCE)
	- color: 씨앗 껍데기·식물 빛 색 (RGB 0~255)
	6판에서 없앤 것: 블룸·스피릿 블룸(→ 사쿠라 나무 특별 씨앗), 균열·기생·혼란(원작 상점·이벤트 돌연변이)
]]

export type Mutation = {
	id: string,
	order: number,
	name: string,
	nameEn: string,
	multiplier: number,
	group: string,
	source: string,
	naturalChance: number,
	feedChance: number?,
	feedBiomes: { string }?,
	color: { number },
}

local list: { Mutation } = {
	{
		id = "silver",
		order = 1,
		name = "실버",
		nameEn = "Silver",
		multiplier = 1.25,
		group = "natural",
		source = "nest",
		naturalChance = 0.05,
		color = { 200, 205, 215 },
	},
	{
		id = "golden",
		order = 2,
		name = "황금",
		nameEn = "Golden",
		multiplier = 2,
		group = "natural",
		source = "nest",
		naturalChance = 0.02,
		feedChance = 0.04,
		feedBiomes = { "titan_temple", "angels_demons", "developer_room" }, -- 7판: + 개발자의 방
		color = { 255, 200, 50 },
	},
	{
		id = "rainbow",
		order = 3,
		name = "무지개",
		nameEn = "Rainbow",
		multiplier = 2.5,
		group = "natural",
		source = "nest",
		naturalChance = 0.005,
		feedChance = 0.01,
		feedBiomes = { "enchanted_forest", "candy_kingdom", "haunted_castle", "bug_dimension" }, -- 7판: + 버그 차원
		color = { 255, 90, 200 },
	},
	{
		id = "frozen",
		order = 4,
		name = "얼음",
		nameEn = "Frozen",
		multiplier = 1.5,
		group = "element",
		source = "fruit",
		naturalChance = 0,
		feedChance = 0.05,
		feedBiomes = { "snow", "lake", "abyss_ocean" },
		color = { 170, 230, 255 },
	},
	{
		id = "burning",
		order = 5,
		name = "불",
		nameEn = "Burning",
		multiplier = 1.5,
		group = "element",
		source = "fruit",
		naturalChance = 0,
		feedChance = 0.05,
		feedBiomes = { "volcano", "desert", "prehistoric" },
		color = { 255, 110, 40 },
	},
	{
		id = "shocked",
		order = 6,
		name = "번개",
		nameEn = "Shocked",
		multiplier = 2,
		group = "element",
		source = "fruit",
		naturalChance = 0,
		feedChance = 0.03,
		feedBiomes = { "jungle", "cosmic", "cherry_blossom", "hacker_lab" }, -- 7판: + 해커 연구소
		color = { 255, 240, 90 },
	},
}

local byId: { [string]: Mutation } = {}
local natural: { Mutation } = {}
local feed: { Mutation } = {}
for _, mutation in list do
	byId[mutation.id] = mutation
	if mutation.group == "natural" then
		table.insert(natural, mutation)
	end
	if (mutation.feedChance or 0) > 0 then
		table.insert(feed, mutation)
	end
end
-- 희귀한 것부터 굴리도록 확률 오름차순 정렬
table.sort(natural, function(a: Mutation, b: Mutation): boolean
	return a.naturalChance < b.naturalChance
end)

local Mutations = {
	list = list,
	byId = byId,
	natural = natural,
	-- 6판: 열매 먹이기로 얻을 수 있는 돌연변이 (Data 순서)
	feed = feed,
	FEED_BIOME_BONUS = 3, -- 그 돌연변이의 feedBiomes 구역 식물 열매면 확률 × 3
	-- 열매 등급 보너스: 확률 × (1 + (등급 순서 - 1) × 이 값) → 일반 ×1 … 신성 ×1.9 … 해커 글리치 ×2.5 (7판 등급 16개)
	FEED_RARITY_BONUS_PER_ORDER = 0.1,
	FEED_MAX_CHANCE = 0.9, -- 한 번 먹일 때 무언가 붙을 확률 상한
}

function Mutations.get(id: string): Mutation?
	return byId[id]
end

return Mutations
