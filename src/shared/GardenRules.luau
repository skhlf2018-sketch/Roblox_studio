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
	- 8판 식물 크기 (plantScale = 등급 × 크기 등급 × 자람): rarityScale · sizeScale · stageScale · growthScale (Config 한 곳)
	  8판 추가 (2026-11-09): 모양용(plantScale) ↔ 간격용(spacingScale) 따로 — 거대 식물(isLobbyFill)만 다름. promptHeight(상한)
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

------------------------------------------------------------------
-- 8판 (사장님 2026-11-08) 식물 크기: 등급이 높을수록 성체가 크고, 자라면서 점점 커짐. 숫자는 Config 한 곳
--   (RARITY_PLANT_SCALE · PLANT_SIZE_SCALE · STAGE_SCALE). 모양 적용은 선임 PlantVisualService
-- 8판 추가 (사장님 2026-11-09): 곡선 일반 1 → 울트라디바인 6, 맨 위 등급(Config.LOBBY_FILL_RARITY)은 **모양만** 거대
--   (LOBBY_FILL_SCALE 16 — 베이스를 덮음). 그래서 배율이 두 가지:
--     모양용 rarityScale / plantScale  — 겉모습·이름표·VisualHeight·아우라 (PlantVisualService)
--     간격용 spacingRarityScale / spacingScale — 정원 간격·성체 폭 (EggPlacement.footprint), 표 값 그대로 (해커 글리치 6.16)
------------------------------------------------------------------

-- 이 등급이 베이스를 덮는 거대 식물 등급인가 (Config.LOBBY_FILL_RARITY)
function GardenRules.isLobbyFillRarity(rarityId: string?): boolean
	return rarityId ~= nil and rarityId == Config.LOBBY_FILL_RARITY
end

-- 이 식물이 거대 식물인가 (모르는 식물·nil 이면 false)
function GardenRules.isLobbyFill(petId: string?): boolean
	local plant = if petId then Plants.get(petId) else nil
	return plant ~= nil and GardenRules.isLobbyFillRarity(plant.rarity)
end

-- 등급 → 정원 간격용 배율 = Config.RARITY_PLANT_SCALE 표 값 그대로 (모르는 등급 1)
function GardenRules.spacingRarityScale(rarityId: string?): number
	return if rarityId then Config.RARITY_PLANT_SCALE[rarityId] or 1 else 1
end

-- 등급 → 성체 **모양** 크기 배율 (거대 식물 등급이면 LOBBY_FILL_SCALE, 아니면 표 값, 모르는 등급 1)
function GardenRules.rarityScale(rarityId: string?): number
	if GardenRules.isLobbyFillRarity(rarityId) then
		return Config.LOBBY_FILL_SCALE
	end
	return GardenRules.spacingRarityScale(rarityId)
end

-- 씨앗 크기 등급(normal/big/huge/giant) → 식물 크기 배율 (모르는 크기 1)
function GardenRules.sizeScale(sizeId: string?): number
	return if sizeId then Config.PLANT_SIZE_SCALE[sizeId] or 1 else 1
end

-- 성장 단계 → 크기 배율 (Config.STAGE_SCALE: 새싹 0.3 · 줄기 0.55 · 봉오리 0.8 · 성체 1, 모르는 단계 1)
function GardenRules.stageScale(stageId: string): number
	return Config.STAGE_SCALE[stageId] or 1
end

-- 자람 배율 (자라면서 **점점** 커지게): 단계 시작점 사이를 자란 비율로 이어 줌
--   0% 0.3 → 25% 0.55 → 60% 0.8 → 100% 1 (그 사이는 곧은 선). 이상한 값이면 새싹 크기
function GardenRules.growthScale(progress: number, required: number): number
	local f = if progress == progress and required == required then GardenRules.fraction(progress, required) else 0
	local stages = Config.GROWTH_STAGES
	for i = #stages - 1, 1, -1 do
		local a, b = stages[i], stages[i + 1]
		if f >= a.from then
			local sa, sb = GardenRules.stageScale(a.id), GardenRules.stageScale(b.id)
			local t = if b.from > a.from then math.clamp((f - a.from) / (b.from - a.from), 0, 1) else 1
			return sa + (sb - sa) * t
		end
	end
	return GardenRules.stageScale(stages[1].id)
end

-- 식물 하나의 보이는(모양) 크기 배율 = 모양 등급 배율 × 크기 등급 × 자람 (progress/required 를 안 주면 성체 = 자람 1)
--   거대 식물(해커 글리치)은 LOBBY_FILL_SCALE 16 × 크기 × 자람
function GardenRules.plantScale(petId: string, sizeId: string?, progress: number?, required: number?): number
	local plant = Plants.get(petId)
	local grow = if progress and required then GardenRules.growthScale(progress, required) else 1
	return GardenRules.rarityScale(if plant then plant.rarity else nil) * GardenRules.sizeScale(sizeId) * grow
end

-- 정원 간격용 성체 배율 = 표 등급 배율 × 크기 등급 (자람 없음 — 심을 때부터 다 자란 폭만큼 띄움). 거대 식물도 표 값(6.16)
--   → EggPlacement.footprint 가 이것 × PLANT_FOOTPRINT 로 간격을 정하고 PLANT_GAP_MAX 에 묶임. 거대 식물이 아니면 plantScale 성체와 같음
function GardenRules.spacingScale(petId: string?, sizeId: string?): number
	local plant = if petId then Plants.get(petId) else nil
	return GardenRules.spacingRarityScale(if plant then plant.rarity else nil) * GardenRules.sizeScale(sizeId)
end

-- 정원 프롬프트 높이 (식물 파트 바닥에서, 스터드) = 식물 키 × fraction, 단 Config.PLANT_PROMPT_MAX_HEIGHT 까지
--   (8판 추가: 키 67 거대 식물·키 24 울트라디바인도 손이 닿게). 이상한 값·0 이하면 0
function GardenRules.promptHeight(visualHeight: number, fraction: number): number
	local h = visualHeight * fraction
	if h ~= h or h <= 0 then
		return 0
	end
	return math.min(h, Config.PLANT_PROMPT_MAX_HEIGHT)
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
	local seconds = GardenRules.skipSeconds(progress, required, mode)
	local timePart = GardenRules.skipCostForSeconds(plant.rarity, seconds)
	if timePart <= 0 or required ~= required or required <= 0 or required == math.huge or seconds == math.huge then
		return timePart
	end
	-- 7판 (사장님 2026-10-29): + 건너뛸 비율 × 열매 1개 값(보통 크기, 돌연변이 없음) × SKIP_FRUIT_FACTOR(10)
	local fraction = math.clamp(seconds / required, 0, 1)
	local fruitPart = fraction * Economy.fruitValue(petId, "normal", {}) * Config.SKIP_FRUIT_FACTOR
	return math.ceil(timePart + fruitPart)
end

-- 성체 뽑아서 팔기 값 (코인) = 열매 1개 값 × 20
function GardenRules.sellPrice(record: { petId: string, size: string, mutations: { string } }): number
	return Economy.recordFruitValue(record) * Config.PLANT_SELL_FRUIT_MULTIPLIER
end

return GardenRules
