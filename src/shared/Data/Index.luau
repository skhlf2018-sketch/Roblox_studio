--!strict
--[[
	Index — 도감 보상 규칙 (설계문서 9-5)

	처음 부화한 펫마다 속도 + 돈 보상 (Claim All 로 수령).
	설계문서 예시와 정확히 맞도록 만든 공식:
	  돈   = 기본 수입(원본) × MONEY_PER_INCOME
	  속도 = RARITY_SPEED[희귀도] × max(1, 구역 추천 속도 / SPEED_BIOME_REFERENCE) ^ SPEED_BIOME_EXPONENT
	검산 (숲 추천 속도 10 → 배율 1):
	  닭(일반, $1)           → +420 속도, +$100
	  라쿤(희귀, $45)        → +620 속도, +$4,500
	  브르 브르 파타핌(전설, $1.8K) → +1,000 속도, +$180,000
	뒤 구역일수록 속도 보상이 커지지만 추천 속도보다는 느리게 커짐 [추정]
	  (예: 눈 170K → 47.2^0.8 = 21.8배, 선사시대 18M → 5000^0.8 ≈ 911배)
	2단계 밸런스 결정(본부장): 지수 1 → 0.8. 지수 1 이면 펫 몇 마리만 발견해도 다음 구역이 열려
	9~15구역이 1시간 안에 연달아 열렸음. 0.8 이면 tests/sim_progress.luau 기준 13구역 ≈ 27시간, 15구역 ≈ 58시간.

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
	SPEED_BIOME_EXPONENT = 0.8,
	-- 곰덫 보상 (설계문서 10장 "곰덫 — 도감 보상") [추정 수치: 본부장 지시]
	TRAPS_MIN_RARITY = "rare", -- 이 희귀도 이상 펫을 처음 발견할 때마다
	TRAPS_PER_DISCOVERY = 1,
	TRAPS_PER_BIOME_COMPLETE = 5, -- 한 구역 펫을 전부 발견했을 때 (구역마다 한 번)
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
	local biomeScale = math.max(1, biomeRecommendedSpeed / Index.SPEED_BIOME_REFERENCE) ^ Index.SPEED_BIOME_EXPONENT
	return {
		speed = math.floor(baseSpeed * biomeScale + 0.5),
		money = math.floor(baseIncome * Index.MONEY_PER_INCOME + 0.5),
	}
end

return Index
