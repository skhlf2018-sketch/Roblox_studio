--!strict
--[[
	Mutations — 돌연변이 (6판 "씨앗을 훔치세요", docs/SEED_GAME_DESIGN.md 5장·13장)

	- multiplier: 열매 값 배율 (5판: 펫 수입 배율). 여러 개면 전부 곱함 (예: 황금 2 × 불 1.5 = 3배)
	- group: 같은 group 안에서는 1개만 가질 수 있음
	    "natural" = 실버/황금/무지개 중 최대 1개 (둥지 씨앗에 자연 등장)
	    "element" = 얼음/불/번개 중 최대 1개 — 9판(사장님 2026-11-10): 열매 먹이기를 **완전히 없앰** → 새로 안 생김.
	      이미 저장된 식물(옛 먹이기로 붙은 것)에는 그대로 남고 열매 값 계산에도 그대로 곱함 (그래서 표에 남겨 둠)
	- naturalChance: 둥지에 씨앗이 놓일 때 자연 등장 확률 (0~1). natural 그룹만 사용.
	- source: "nest" = 둥지 씨앗에 자연 등장 · "legacy" = 옛 열매 먹이기(9판에서 없앰)로만 붙던 것
	- color: 씨앗 껍데기·식물 빛 색 (RGB 0~255)
	6판에서 없앤 것: 블룸·스피릿 블룸(→ 사쿠라 나무 특별 씨앗), 균열·기생·혼란(원작 상점·이벤트 돌연변이)
	9판에서 없앤 것: feedChance·feedBiomes 칸, Mutations.feed 목록, FEED_BIOME_BONUS·FEED_RARITY_BONUS_PER_ORDER·FEED_MAX_CHANCE
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
		color = { 255, 90, 200 },
	},
	-- 9판: 아래 원소 3개는 새로 안 생김 (옛 저장 식물 값 계산용으로만 남김)
	{
		id = "frozen",
		order = 4,
		name = "얼음",
		nameEn = "Frozen",
		multiplier = 1.5,
		group = "element",
		source = "legacy",
		naturalChance = 0,
		color = { 170, 230, 255 },
	},
	{
		id = "burning",
		order = 5,
		name = "불",
		nameEn = "Burning",
		multiplier = 1.5,
		group = "element",
		source = "legacy",
		naturalChance = 0,
		color = { 255, 110, 40 },
	},
	{
		id = "shocked",
		order = 6,
		name = "번개",
		nameEn = "Shocked",
		multiplier = 2,
		group = "element",
		source = "legacy",
		naturalChance = 0,
		color = { 255, 240, 90 },
	},
}

local byId: { [string]: Mutation } = {}
local natural: { Mutation } = {}
for _, mutation in list do
	byId[mutation.id] = mutation
	if mutation.group == "natural" then
		table.insert(natural, mutation)
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
}

function Mutations.get(id: string): Mutation?
	return byId[id]
end

return Mutations
