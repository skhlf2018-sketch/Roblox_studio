--!strict
--[[
	EggSpawn — 둥지에 어떤 알이 놓일지 정하는 가중치 표 (설계문서 2장)

	1) 일반 추첨 (매 초기화 + 낮 동안 빈 둥지 다시 채울 때):
	   구역 둥지 풀(source = "nest", 천사&악마는 이번 주기 쪽만)에서
	   NEST_RARITY_WEIGHTS 가중치로 1마리 추첨. 비밀/영원/신성은 가중치 0 → 일반 추첨에 안 나옴.

	2) 특별 추첨 (초기화 때만):
	   구역마다, 그 구역 풀에 해당 희귀도 펫이 있으면 SPECIAL_CHANCE_PER_RESET 확률로
	   그 희귀도 펫 1마리를 무작위 둥지 하나에 놓고 서버 전체에 공지 ("희귀 알 레이스").
	   신성 0.2% 는 설계문서 3장 값.
]]

local EggSpawn = {
	NEST_RARITY_WEIGHTS = {
		common = 100,
		uncommon = 70,
		rare = 45,
		epic = 28,
		legendary = 16,
		mythic = 9,
		cosmic = 4,
		secret = 0,
		eternal = 0,
		divine = 0,
	} :: { [string]: number },

	-- 초기화 때만 등장 + 공지되는 희귀도 (희귀한 것부터)
	SPECIAL_RARITIES = { "divine", "eternal", "secret" },

	SPECIAL_CHANCE_PER_RESET = {
		secret = 0.08, -- [추정]
		eternal = 0.02, -- [추정]
		divine = 0.002, -- 설계문서 3장 "약 0.2%"
	} :: { [string]: number },

	-- 한 구역에 한 번의 초기화로 놓일 수 있는 특별 알 최대 개수
	MAX_SPECIALS_PER_BIOME = 2,
}

return EggSpawn
