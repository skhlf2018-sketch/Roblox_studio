--!strict
--[[
	EggSpawn — 둥지에 어떤 씨앗이 놓일지 정하는 가중치 표 (6판 "씨앗을 훔치세요", docs/SEED_GAME_DESIGN.md 4장 표 그대로)
	(파일 이름은 5판 그대로 — 알 → 씨앗)

	1) 일반 추첨 (매 초기화 + 낮 동안 빈 둥지 다시 채울 때): EggRoll.rollNestPet
	   구역 둥지 풀(source = "nest", 천사&악마는 이번 주기 쪽만)에서
	     ① 등급을 BIOME_RARITY_WEIGHTS[구역] 가중치로 고르고 (뒤 구역일수록 높은 등급)
	     ② 그 등급 식물 중 하나를 똑같은 확률로 고름
	   = 식물 하나의 가중치 = (그 등급 가중치) ÷ (풀 안 그 등급 식물 수)  (EggRoll.nestWeight)
	   구역 1~2 일반·고급(가끔 희귀) → … → 14 비밀·영원(가끔 신성) → 15 영원·신성.
	   슈퍼 울트라디바인은 일반 추첨에 안 나옴 (가중치 0) → 2) 의 공지 씨앗으로만 (하루 1~2개)

	2) 특별 추첨 (초기화 때만):
	   구역마다, 그 구역 풀에 해당 등급 식물이 있으면 SPECIAL_CHANCE_PER_RESET 확률로
	   그 등급 식물 1개를 무작위 둥지 하나에 놓고 서버 전체에 공지 ("희귀 씨앗 레이스").
	   슈퍼 울트라디바인 0.5%: 주기 하나 = 낮 285 + 밤 10 + 대기 3 = 298초 → 하루 약 290번 초기화 × 0.005 ≈ 1.45개/일

	3) 공지 씨앗 (초기화 때만): EXTRA_SPECIALS — 둥지 풀에 없는 식물(source = "special")을 이 확률로
	   그 식물 구역의 무작위 둥지에 놓고 공지 (누구나 훔침). 5판 특별 알(지터버그·영혼 세계 수호자)과 제단 펫 자리.
]]

local EggSpawn = {
	-- 구역별 등급 가중치 (합 100 — 이 구역 둥지 씨앗이 그 등급일 확률 %). 설계 4장 "주로 나오는 등급 / 가끔"
	BIOME_RARITY_WEIGHTS = {
		forest = { common = 60, uncommon = 35, rare = 5 },
		lake = { common = 45, uncommon = 45, rare = 10 },
		desert = { uncommon = 60, rare = 35, epic = 5 },
		jungle = { uncommon = 45, rare = 45, epic = 10 },
		snow = { rare = 60, epic = 35, legendary = 5 },
		volcano = { rare = 45, epic = 45, legendary = 10 },
		abyss_ocean = { epic = 60, legendary = 35, mythic = 5 },
		prehistoric = { epic = 45, legendary = 45, mythic = 10 },
		cosmic = { legendary = 60, mythic = 35, cosmic = 5 },
		cherry_blossom = { legendary = 45, mythic = 45, cosmic = 10 },
		titan_temple = { mythic = 60, cosmic = 35, secret = 5 },
		angels_demons = { mythic = 45, cosmic = 45, secret = 10 },
		enchanted_forest = { cosmic = 55, secret = 40, eternity = 5 },
		candy_kingdom = { secret = 55, eternity = 40, divine = 5 },
		haunted_castle = { eternity = 55, divine = 45, super_ultradivine = 0 },
	} :: { [string]: { [string]: number } },

	-- 초기화 때만 등장 + 공지되는 등급 (희귀한 것부터)
	SPECIAL_RARITIES = { "super_ultradivine", "divine", "eternity", "secret" },

	SPECIAL_CHANCE_PER_RESET = {
		super_ultradivine = 0.005, -- 하루 약 1.45개 (설계 4장 "하루 1~2개, 전체 공지")
		divine = 0.002, -- 5판 설계 "약 0.2%" 그대로
		eternity = 0.02, -- [추정]
		secret = 0.08, -- [추정]
	} :: { [string]: number },

	-- 한 구역에 한 번의 초기화로 놓일 수 있는 특별 씨앗 최대 개수
	MAX_SPECIALS_PER_BIOME = 2,

	-- 둥지 풀 밖의 공지 씨앗 (source = "special"). 초기화마다 따로 굴림 (MAX_SPECIALS_PER_BIOME 과 별개)
	EXTRA_SPECIALS = {
		{ petId = "dancing_mushroom", chance = 0.08 }, -- 마법의 숲 (5판 지터버그 8% 자리)
		{ petId = "world_tree", chance = 0.01 }, -- 마법의 숲 (5판 영혼 세계 수호자 1% 자리)
		{ petId = "twilight_bloom", chance = 0.05 }, -- [수석] 천사 & 악마 (5판 제단 펫 자리)
		{ petId = "balance_tree", chance = 0.01 }, -- [수석] 천사 & 악마 (5판 비밀 통로 합성 펫 자리)
	} :: { { petId: string, chance: number } },
}

return EggSpawn
