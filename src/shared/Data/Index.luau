--!strict
--[[
	Index — 도감 보상 규칙 (6판 "씨앗을 훔치세요": 성체 도감. 5판 설계문서 9-5 공식 그대로, 돈 칸만 열매 값 기준)

	처음 성체가 된 식물마다 속도 + 코인 보상 (Claim All 로 수령).
	  코인 = 그 식물 열매 1개 값(Data/Plants.fruitValue) × MONEY_PER_FRUIT
	  속도 = RARITY_SPEED[등급] × max(1, 구역 추천 속도 / SPEED_BIOME_REFERENCE) ^ SPEED_BIOME_EXPONENT
	검산 (숲 추천 속도 10 → 배율 1):
	  아기 데이지(일반, 열매 10)   → +420 속도, +100 코인
	  부엉이 참나무(희귀, 열매 180) → +620 속도, +1.8K 코인
	뒤 구역일수록 속도 보상이 커지지만 추천 속도보다는 느리게 커짐 [추정]
	  (예: 눈 170K → 47.2^0.8 = 21.8배, 선사시대 18M → 5000^0.8 ≈ 911배)
	2단계 밸런스 결정(본부장): 지수 1 → 0.8.

	구역 하나의 식물을 전부 발견하면 그 구역 무기(Biomes.weapon) 해금 (Weapons.excludeSources 출처는 빼고).
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
		eternity = 2800,
		divine = 3600,
		super_ultradivine = 4600, -- [수석] 6판 새 등급
	} :: { [string]: number },
	MONEY_PER_FRUIT = 10, -- [수석] 6판: 도감 코인 = 열매 1개 값 × 10
	SPEED_BIOME_REFERENCE = 3600,
	SPEED_BIOME_EXPONENT = 0.8,
	-- 곰덫 보상 (5판 설계문서 10장 "곰덫 — 도감 보상") [추정 수치: 본부장 지시]
	TRAPS_MIN_RARITY = "rare", -- 이 등급 이상 식물을 처음 발견할 때마다
	TRAPS_PER_DISCOVERY = 1,
	TRAPS_PER_BIOME_COMPLETE = 5, -- 한 구역 식물을 전부 발견했을 때 (구역마다 한 번)
	FULL_COMPLETION = {
		speed = 1e12,
		money = 1e15,
	},
}

export type Reward = {
	speed: number,
	money: number, -- 코인
}

-- 순수 함수: 등급·열매 1개 값·구역 추천 속도로 보상 계산
function Index.reward(rarityId: string, fruitValue: number, biomeRecommendedSpeed: number): Reward
	local baseSpeed = Index.RARITY_SPEED[rarityId] or 0
	local biomeScale = math.max(1, biomeRecommendedSpeed / Index.SPEED_BIOME_REFERENCE) ^ Index.SPEED_BIOME_EXPONENT
	return {
		speed = math.floor(baseSpeed * biomeScale + 0.5),
		money = math.floor(fruitValue * Index.MONEY_PER_FRUIT + 0.5),
	}
end

return Index
