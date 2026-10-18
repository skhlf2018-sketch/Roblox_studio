--!strict
--[[
	Index — 도감 보상 규칙 (설계문서 9-5)

	처음 부화한 펫마다 속도 + 돈 보상 (Claim All 로 수령).
	설계문서 예시와 정확히 맞도록 만든 공식:
	  돈   = 기본 수입(원본) × MONEY_PER_INCOME
	  속도 = RARITY_SPEED[희귀도] × max(1, 구역 추천 속도 / SPEED_BIOME_REFERENCE)
	검산 (숲 추천 속도 10 → 배율 1):
	  닭(일반, $1)           → +420 속도, +$100
	  라쿤(희귀, $45)        → +620 속도, +$4,500
	  브르 브르 파타핌(전설, $1.8K) → +1,000 속도, +$180,000
	뒤 구역은 추천 속도에 비례해 속도 보상이 커짐 (예: 눈 170K → 배율 47.2) [추정]

	구역 하나의 펫을 전부 발견하면 그 구역 무기(Biomes.weapon) 해금.
	전체 완성 보너스 FULL_COMPLETION [추정].
]]

local Index = {
	RARITY_SPEED = {
		common = 420,
		uncommon = 520,
		rare = 620,
		epic = 800,
		legendary = 1000,
		mythic = 1300,
		cosmic = 1700,
		secret = 2200,
		eternal = 2800,
		divine = 3600,
	} :: { [string]: number },
	MONEY_PER_INCOME = 100,
	SPEED_BIOME_REFERENCE = 3600,
	FULL_COMPLETION = {
		speed = 1e12,
		money = 1e15,
	},
}

export type Reward = {
	speed: number,
	money: number,
}

-- 순수 함수: 희귀도·기본 수입(원본)·구역 추천 속도로 보상 계산
function Index.reward(rarityId: string, baseIncome: number, biomeRecommendedSpeed: number): Reward
	local baseSpeed = Index.RARITY_SPEED[rarityId] or 0
	local biomeScale = math.max(1, biomeRecommendedSpeed / Index.SPEED_BIOME_REFERENCE)
	return {
		speed = math.floor(baseSpeed * biomeScale + 0.5),
		money = math.floor(baseIncome * Index.MONEY_PER_INCOME + 0.5),
	}
end

return Index
