--!strict
--[[
	SakuraRules — 사쿠라 나무 규칙 (6판 "씨앗을 훔치세요" 씨앗 버전, 사장님 결정 4, 순수 로직, Lune 테스트 대상)

	- 바치기 (SakuraOffer): 정원의 성체 식물 1그루를 바치면 사쿠라 크리스탈 (등급이 높을수록 많이, Config.SAKURA_OFFER_CRYSTALS)
	- 뽑기 (SakuraDraw): 크리스탈 Config.SAKURA_DRAW_COST 개로 특별 씨앗 1개 → 씨앗 가방으로
	    벚꽃 씨앗(벚꽃 요정 나무) 97.5% / 정령 벚꽃 씨앗(정령 벚꽃 나무) 2.5% (Config.SAKURA_SEEDS — 5판 블룸 확률 그대로)
	- 5판의 "학 바쳐서 해금"·"블룸 돌연변이 붙이기"는 없앰
]]

local Data = script.Parent.Data
local Config = require(Data.Config)
local Plants = require(Data.Plants)
local EggRoll = require(script.Parent.EggRoll)

type RandomFn = EggRoll.RandomFn

local SakuraRules = {}

-- 성체 1그루를 바치면 받는 크리스탈 (모르는 식물이면 0)
function SakuraRules.crystalsFor(petId: string): number
	local plant = Plants.get(petId)
	if not plant then
		return 0
	end
	return Config.SAKURA_OFFER_CRYSTALS[plant.rarity] or 1
end

function SakuraRules.canAfford(crystals: number): boolean
	return crystals >= Config.SAKURA_DRAW_COST
end

-- 뽑기 한 번 → 식물 id (벚꽃 요정 나무 97.5% / 정령 벚꽃 나무 2.5%)
function SakuraRules.roll(rand: RandomFn): string
	local pick = EggRoll.weightedPick(Config.SAKURA_SEEDS, function(entry: { plantId: string, chance: number }): number
		return entry.chance
	end, rand)
	return if pick then pick.plantId else Config.SAKURA_SEEDS[1].plantId
end

-- 뽑기로 나올 수 있는 식물 id 목록 (확률 순서)
function SakuraRules.seedIds(): { string }
	local ids: { string } = {}
	for _, entry in Config.SAKURA_SEEDS do
		table.insert(ids, entry.plantId)
	end
	return ids
end

return SakuraRules
