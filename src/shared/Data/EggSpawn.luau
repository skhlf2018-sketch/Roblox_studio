--!strict
--[[
	EggSpawn — 둥지에 어떤 알이 놓일지 정하는 가중치 표 (설계문서 2장, 2판 수정)

	1) 일반 추첨 (매 초기화 + 낮 동안 빈 둥지 다시 채울 때): EggRoll.rollNestPet
	   구역 둥지 풀(source = "nest", 천사&악마는 이번 주기 쪽만, 구역마다 원작 8종 그대로)에서 가중치로 1마리.
	   2판 수정 (사장님 "1번 구역은 일반~고급, 뒤로 갈수록 올라가 맨 끝은 비밀~신성"):
	     구역 i(1~15)의 중심 희귀도 = round(1 + (i - 1) × (10 - 1) / (구역 수 - 1))   (EggRoll.centerRarity)
	       → 숲 1(일반) · 호수/사막 2 · 정글 3 · 눈/화산 4 · 심연 5 · 선사/코스믹 6 · 벚꽃/타이탄 7 · 천사&악마 8
	         · 마법의 숲/사탕 9 · 유령 성 10(신성)
	     펫 가중치 = 그 펫 희귀도 순서(Rarities.order)와 중심의 차이 d 로:
	       d = 0 → 1.0 / 1 → 0.5 / 2 → 0.2 / 그 밖 → 0.05   (DISTANCE_WEIGHTS, FAR_WEIGHT)
	       단 비밀·영원·신성은 중심 ±2 안일 때만 일반 추첨에 나옴 (그 밖은 0 = 초기화 특별 알로만, SPECIAL_FAR_WEIGHT)
	     → 숲: 일반·고급 약 82%, 전설 약 1.6% / 유령 성: 비밀 이상 약 90% (보통 둥지에도 나옴, 공지 없음)

	2) 특별 추첨 (초기화 때만, 그대로):
	   구역마다, 그 구역 풀에 해당 희귀도 펫이 있으면 SPECIAL_CHANCE_PER_RESET 확률로
	   그 희귀도 펫 1마리를 무작위 둥지 하나에 놓고 서버 전체에 공지 ("희귀 알 레이스").
	   신성 0.2% 는 설계문서 3장 값.

	3) 5판 추가 특별 알 (초기화 때만): EXTRA_SPECIALS — 둥지 풀에 없는 펫(source = "special")을 이 확률로
	   그 펫 구역의 무작위 둥지에 놓고 공지 (누구나 훔침). 옛 마법의 숲 퀘스트 알 2종:
	     지터버그(비밀) = 비밀 특별 알과 같은 8% [추정], 영혼 세계 수호자(신성) = 옛 퀘스트 비밀 알 확률 1% 그대로
	   (퀘스트를 없애도 마법의 숲 도감 10종·망치 무기를 모을 수 있게)
]]

local EggSpawn = {
	-- 구역 중심 희귀도 범위 (Rarities.order: 1 일반 ~ 10 신성)
	CENTER_RARITY_FIRST = 1, -- 첫 구역(숲)
	CENTER_RARITY_LAST = 10, -- 마지막 구역(유령 성)

	-- 중심과의 차이 d → 가중치 (DISTANCE_WEIGHTS[d + 1]), 그보다 멀면 FAR_WEIGHT
	DISTANCE_WEIGHTS = { 1.0, 0.5, 0.2 } :: { number },
	FAR_WEIGHT = 0.05,
	SPECIAL_FAR_WEIGHT = 0, -- 비밀·영원·신성이 중심에서 멀 때 (앞 구역은 특별 알로만)

	-- 초기화 때만 등장 + 공지되는 희귀도 (희귀한 것부터)
	SPECIAL_RARITIES = { "divine", "eternal", "secret" },

	SPECIAL_CHANCE_PER_RESET = {
		secret = 0.08, -- [추정]
		eternal = 0.02, -- [추정]
		divine = 0.002, -- 설계문서 3장 "약 0.2%"
	} :: { [string]: number },

	-- 한 구역에 한 번의 초기화로 놓일 수 있는 특별 알 최대 개수
	MAX_SPECIALS_PER_BIOME = 2,

	-- 5판: 둥지 풀 밖의 특별 알 (옛 퀘스트 알). 초기화마다 따로 굴림 (MAX_SPECIALS_PER_BIOME 과 별개)
	EXTRA_SPECIALS = {
		{ petId = "jitterbug", chance = 0.08 }, -- [추정] 비밀 특별 알과 같은 확률
		{ petId = "spirit_world_guardian", chance = 0.01 }, -- 옛 Config.QUEST_SECRET_EGG_CHANCE 그대로
	} :: { { petId: string, chance: number } },
}

return EggSpawn
