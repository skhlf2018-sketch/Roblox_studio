--!strict
--[[
	Mutations — 돌연변이 (설계문서 8장)

	- multiplier: 수입 배율. 여러 개면 전부 곱함 (예: 균열 2.75 × 혼란 2.75 = 7.56배)
	- group: 같은 group 안에서는 1개만 가질 수 있음
	    "natural" = 둥지에서 자연 등장 (실버/골든/레인보우 중 최대 1개)
	    "bloom"   = 사쿠라 인큐베이터 (블룸/스피릿 블룸 중 최대 1개)
	    그 밖의 group 은 각자 1개씩 (서로 중첩 가능)
	- naturalChance: 둥지에 알이 놓일 때 자연 등장 확률 (0~1). natural 그룹만 사용.
	- sourceChance: 해당 획득 방법(인큐베이터·상점·이벤트)에서의 확률 (2단계 이후 시스템용)
	- color: 알 껍데기 색 (RGB 0~255)
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
	sourceChance: number?,
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
		name = "골든",
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
		name = "레인보우",
		nameEn = "Rainbow",
		multiplier = 2.5,
		group = "natural",
		source = "nest",
		naturalChance = 0.005,
		color = { 255, 90, 200 },
	},
	{
		id = "bloom",
		order = 4,
		name = "블룸",
		nameEn = "Bloom",
		multiplier = 1.5,
		group = "bloom",
		source = "sakura_incubator",
		naturalChance = 0,
		sourceChance = 0.975,
		color = { 255, 170, 200 },
	},
	{
		id = "spirit_bloom",
		order = 5,
		name = "스피릿 블룸",
		nameEn = "Spirit Bloom",
		multiplier = 3,
		group = "bloom",
		source = "sakura_incubator",
		naturalChance = 0,
		sourceChance = 0.025,
		color = { 180, 120, 255 },
	},
	{
		id = "fractured",
		order = 6,
		name = "균열",
		nameEn = "Fractured",
		multiplier = 2.75,
		group = "fractured",
		source = "rift_shop",
		naturalChance = 0,
		sourceChance = 0.10,
		color = { 120, 60, 200 },
	},
	{
		id = "parasite",
		order = 7,
		name = "기생",
		nameEn = "Parasite",
		multiplier = 3,
		group = "parasite",
		source = "hungry_monster_event",
		naturalChance = 0,
		sourceChance = 0.015,
		color = { 110, 160, 40 },
	},
	{
		id = "chaos",
		order = 8,
		name = "혼란",
		nameEn = "Chaos",
		multiplier = 2.75,
		group = "chaos",
		source = "lab_shop",
		naturalChance = 0,
		sourceChance = 0.10,
		color = { 230, 60, 60 },
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
