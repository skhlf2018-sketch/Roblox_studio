--!strict
--[[
	FruitRules — 열매 규칙 (6판 "씨앗을 훔치세요" 사장님 결정 1, 순수 로직, 서버·클라·Lune 공용)

	- 맺기: 성체 식물마다 fruitIntervalSeconds(Data/Plants)마다 열매 +1, 최대 Config.FRUIT_MAX_PER_PLANT(5)개.
	    가득 차 있으면 다음 열매까지의 시간이 쌓이지 않음 (따면 그때부터 다시 셈). 밤에도 빠르기 그대로.
	- 열매 1개 값 = Economy.fruitValue (식물 열매 값 × 크기 × 돌연변이) — 딸 때 정해져서 가방에 들어감
	- 열매 가방 (data.fruits): 식물 id 마다 { count, value(합) } 한 칸. 열매 합 최대 Config.FRUIT_BAG_MAX
	- 열매는 **팔기만** (판매 가판대 SellFruits). 9판(사장님 2026-11-10): 열매 먹이기(FeedFruit → 확률로 돌연변이)를
	    완전히 없앰 — feedOptions·feedChance·rollFeed·canGain·rarityBonus·applyMutation·takeOne 삭제.
	    옛 먹이기로 붙은 원소 돌연변이(얼음·불·번개)는 저장된 식물에 그대로 남아 열매 값에 곱해짐 (Economy.fruitValue)
]]

local Data = script.Parent.Data
local Config = require(Data.Config)
local Economy = require(script.Parent.Economy)
local Types = require(script.Parent.Types)

type FruitBag = Types.FruitBag

local FruitRules = {}

------------------------------------------------------------------
-- 맺기
------------------------------------------------------------------

-- dt 초 지난 뒤 (열매 수, 다음 열매까지 쌓인 초). interval 이 math.huge 면 안 맺음
function FruitRules.produce(fruits: number, progress: number, dt: number, interval: number): (number, number)
	local max = Config.FRUIT_MAX_PER_PLANT
	if fruits >= max then
		return max, 0
	end
	if interval == math.huge or interval <= 0 or dt ~= dt then
		return fruits, progress
	end
	local p = math.max(0, progress) + math.max(0, dt)
	local f = fruits
	if p >= interval then
		local made = math.floor(p / interval)
		f = math.min(max, f + made)
		p -= made * interval
	end
	if f >= max then
		return max, 0
	end
	return f, p
end

------------------------------------------------------------------
-- 열매 가방
------------------------------------------------------------------

-- 가방 속 열매 수 합
function FruitRules.bagCount(bag: FruitBag): number
	local total = 0
	for _, stack in bag do
		total += stack.count
	end
	return total
end

-- 가방 속 열매 값 합 (코인)
function FruitRules.bagValue(bag: FruitBag): number
	local total = 0
	for _, stack in bag do
		total += stack.value
	end
	return total
end

-- 가방 남은 자리
function FruitRules.bagRoom(bag: FruitBag): number
	return math.max(0, Config.FRUIT_BAG_MAX - FruitRules.bagCount(bag))
end

-- 열매 count 개(1개 값 valueEach)를 가방에 넣음 → 실제로 넣은 개수 (자리만큼만). 표를 그 자리에서 고침
function FruitRules.addToBag(bag: FruitBag, plantId: string, count: number, valueEach: number): number
	local n = math.min(math.max(0, math.floor(count)), FruitRules.bagRoom(bag))
	if n <= 0 then
		return 0
	end
	local stack = bag[plantId]
	if not stack then
		stack = { count = 0, value = 0 }
		bag[plantId] = stack
	end
	stack.count += n
	stack.value += n * math.max(0, valueEach)
	return n
end

-- 열매 1개 값 (코인) — Economy.fruitValue 와 같음 (서버·클라 미리보기용 이름)
function FruitRules.fruitValue(record: { petId: string, size: string, mutations: { string } }): number
	return Economy.recordFruitValue(record)
end

return FruitRules
