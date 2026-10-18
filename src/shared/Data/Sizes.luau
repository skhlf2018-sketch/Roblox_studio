--!strict
--[[
	Sizes — 알 크기 등급 (설계문서 7장, [추정] 우리 버전)
	- chance: 둥지에 놓일 때 등장 확률(%)
	- incomeMultiplier: 펫 수입 배율
	- speedPenalty: 알을 들었을 때 속도 감소 비율 (0.10 = -10%)
	- eggScale: 알 겉모습 크기 배율 (Config.EGG_BASE_DIAMETER 에 곱함)
	- carryKg: 들고 있을 때 머리 위에 보이는 무게(kg) — 표시용 (플레이어 Attr CarryWeightKg) [추정]
]]

export type SizeId = "normal" | "big" | "huge" | "giant"

export type Size = {
	id: SizeId,
	order: number,
	name: string,
	nameEn: string,
	chance: number,
	incomeMultiplier: number,
	speedPenalty: number,
	eggScale: number,
	carryKg: number,
}

local list: { Size } = {
	{
		id = "normal",
		order = 1,
		name = "보통",
		nameEn = "Normal",
		chance = 70,
		incomeMultiplier = 1,
		speedPenalty = 0.10,
		eggScale = 1,
		carryKg = 50,
	},
	{
		id = "big",
		order = 2,
		name = "큼",
		nameEn = "Big",
		chance = 20,
		incomeMultiplier = 1.5,
		speedPenalty = 0.20,
		eggScale = 1.35,
		carryKg = 120,
	},
	{
		id = "huge",
		order = 3,
		name = "거대",
		nameEn = "Huge",
		chance = 8,
		incomeMultiplier = 3,
		speedPenalty = 0.35,
		eggScale = 1.8,
		carryKg = 400,
	},
	{
		id = "giant",
		order = 4,
		name = "초거대",
		nameEn = "Giant",
		chance = 2,
		incomeMultiplier = 6,
		speedPenalty = 0.50,
		eggScale = 2.4,
		carryKg = 1200,
	},
}

local byId: { [string]: Size } = {}
for _, size in list do
	byId[size.id] = size
end

local Sizes = {
	list = list,
	byId = byId,
	DEFAULT = "normal" :: SizeId,
}

function Sizes.get(id: string): Size?
	return byId[id]
end

return Sizes
