--!strict
--[[
	GardenRules — 정원 규칙 (6판 "씨앗을 훔치세요", 순수 로직, 서버·클라·Lune 공용)

	- 성장 단계: 자란 비율 = progress / required → Config.GROWTH_STAGES
	    새싹 sprout (0 ~ 25%) → 줄기 stem (25 ~ 60%) → 봉오리 bud (60 ~ 99%) → 성체 adult (100%)
	    서버는 심은 씨앗 파트(IncubatingEgg)의 Attribute "Stage" 로 내보냄 → 선임이 단계별 모양
	- 정원 칸 수 = 정원 업그레이드 칸 수 (Economy.penSlots). 자라는 씨앗 + 성체 식물이 이만큼까지
	- 건너뛰기 (SkipGrowth): 가격 = ceil(건너뛸 시간(분)) × Config.SKIP_COINS_PER_MINUTE(10) × 등급 배수
	    (일반 1 … 슈퍼 500 … 해커 글리치 5000, Config.SKIP_RARITY_MULTIPLIER — 7판 등급 16개). "all" = 남은 시간 전부, "half" = 절반
	    남은 시간 = required - progress ("성장 시간" — 밤에 30배 빨리 줄어드는 그 숫자, 씨앗 위 타이머와 같음)
	- 성체 뽑아서 팔기 (SellPlant): 값 = 그 식물 열매 1개 값 × Config.PLANT_SELL_FRUIT_MULTIPLIER(20)
]]

local Data = script.Parent.Data
local Config = require(Data.Config)
local Plants = require(Data.Plants)
local Economy = require(script.Parent.Economy)

export type StageId = "sprout" | "stem" | "bud" | "adult"
export type SkipMode = "all" | "half"

local GardenRules = {}

GardenRules.SKIP_MODES = { all = "all", half = "half" } :: { [string]: string }

-- 자란 비율 0 ~ 1 (required 가 0 이하면 1)
function GardenRules.fraction(progress: number, required: number): number
	if required <= 0 then
		return 1
	end
	return math.clamp(progress / required, 0, 1)
end

-- 성장 단계 id
function GardenRules.stage(progress: number, required: number): StageId
	local f = GardenRules.fraction(progress, required)
	local current: StageId = "sprout"
	for _, def in Config.GROWTH_STAGES do
		if f >= def.from then
			current = def.id :: StageId
		end
	end
	return current
end

-- 단계 한국어 이름 ("새싹" ...). 모르는 id 면 id 그대로
function GardenRules.stageName(id: string): string
	for _, def in Config.GROWTH_STAGES do
		if def.id == id then
			return def.name
		end
	end
	return id
end

-- 정원 칸 수 (정원 레벨)
function GardenRules.capacity(penLevel: number): number
	return Economy.penSlots(penLevel)
end

-- 정원에 하나 더 심을 자리가 있나 (자라는 씨앗 수 + 성체 수 < 칸 수)
function GardenRules.hasRoom(growingCount: number, plantCount: number, penLevel: number): boolean
	return growingCount + plantCount < GardenRules.capacity(penLevel)
end

-- 건너뛸 성장 시간(초): "all" = 남은 시간 전부, "half" = 절반 (남은 게 없으면 0)
function GardenRules.skipSeconds(progress: number, required: number, mode: SkipMode): number
	local remaining = math.max(0, required - progress)
	if mode == "half" then
		return remaining / 2
	end
	return remaining
end

-- 등급 배수 (모르는 등급이면 1)
function GardenRules.skipMultiplier(rarityId: string): number
	return Config.SKIP_RARITY_MULTIPLIER[rarityId] or 1
end

-- seconds 만큼 건너뛰는 값(코인) = ceil(분) × 10 × 등급 배수. 0 초 이하면 0
function GardenRules.skipCostForSeconds(rarityId: string, seconds: number): number
	if seconds ~= seconds or seconds <= 0 then
		return 0
	end
	local minutes = math.ceil(seconds / 60 - 1e-9)
	return math.max(1, minutes) * Config.SKIP_COINS_PER_MINUTE * GardenRules.skipMultiplier(rarityId)
end

-- 씨앗 하나 건너뛰기 값 (식물 id · 지금 진행도 · 모드). 모르는 식물이면 nil
function GardenRules.skipCost(petId: string, progress: number, required: number, mode: SkipMode): number?
	local plant = Plants.get(petId)
	if not plant then
		return nil
	end
	return GardenRules.skipCostForSeconds(plant.rarity, GardenRules.skipSeconds(progress, required, mode))
end

-- 성체 뽑아서 팔기 값 (코인) = 열매 1개 값 × 20
function GardenRules.sellPrice(record: { petId: string, size: string, mutations: { string } }): number
	return Economy.recordFruitValue(record) * Config.PLANT_SELL_FRUIT_MULTIPLIER
end

return GardenRules
