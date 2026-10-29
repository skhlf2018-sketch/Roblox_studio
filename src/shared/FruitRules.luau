--!strict
--[[
	FruitRules — 열매 규칙 (6판 "씨앗을 훔치세요" 사장님 결정 1, 순수 로직, 서버·클라·Lune 공용)

	- 맺기: 성체 식물마다 fruitIntervalSeconds(Data/Plants)마다 열매 +1, 최대 Config.FRUIT_MAX_PER_PLANT(5)개.
	    가득 차 있으면 다음 열매까지의 시간이 쌓이지 않음 (따면 그때부터 다시 셈). 밤에도 빠르기 그대로.
	- 열매 1개 값 = Economy.fruitValue (식물 열매 값 × 크기 × 돌연변이) — 딸 때 정해져서 가방에 들어감
	- 열매 가방 (data.fruits): 식물 id 마다 { count, value(합) } 한 칸. 열매 합 최대 Config.FRUIT_BAG_MAX
	- 먹이기 (FeedFruit): 가방의 열매 1개를 정원의 성체에게 → 확률로 돌연변이 (Data/Mutations.feed)
	    붙을 수 있는 것만 고름: 자연(실버·황금·무지개)은 지금 것보다 좋은 것으로만 바뀜, 원소(얼음·불·번개)는 없을 때만
	    확률 = 기본 feedChance × (그 돌연변이의 구역 열매면 ×3) × 열매 등급 보너스(일반 ×1 … 해커 글리치 ×2.5),
	    합이 FEED_MAX_CHANCE(0.9) 를 넘으면 비율대로 줄임. 안 붙어도 열매는 없어짐.
]]

local Data = script.Parent.Data
local Config = require(Data.Config)
local Plants = require(Data.Plants)
local Mutations = require(Data.Mutations)
local Rarities = require(Data.Rarities)
local Economy = require(script.Parent.Economy)
local Types = require(script.Parent.Types)

type FruitBag = Types.FruitBag
export type RandomFn = () -> number

export type FeedOption = {
	id: string, -- 돌연변이 id
	chance: number, -- 이번 먹이기에서 이것이 붙을 확률 (0~1)
}

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

-- 가방에서 그 식물 열매 1개를 꺼냄 → 그 열매 값(칸 평균), 없으면 nil. 표를 그 자리에서 고침
function FruitRules.takeOne(bag: FruitBag, plantId: string): number?
	local stack = bag[plantId]
	if not stack or stack.count < 1 then
		return nil
	end
	local each = stack.value / stack.count
	stack.count -= 1
	stack.value = math.max(0, stack.value - each)
	if stack.count <= 0 then
		bag[plantId] = nil
	end
	return each
end

------------------------------------------------------------------
-- 먹이기 (돌연변이)
------------------------------------------------------------------

-- 지금 돌연변이 목록에서 같은 group 의 것
local function currentInGroup(mutations: { string }, group: string): Mutations.Mutation?
	for _, id in mutations do
		local m = Mutations.get(id)
		if m and m.group == group then
			return m
		end
	end
	return nil
end

-- 이 돌연변이가 지금 식물에 새로 붙을 수 있나 (자연: 더 좋은 것으로만 / 그 밖: 같은 group 이 없을 때만)
function FruitRules.canGain(mutations: { string }, mutationId: string): boolean
	local m = Mutations.get(mutationId)
	if not m then
		return false
	end
	local have = currentInGroup(mutations, m.group)
	if not have then
		return true
	end
	if m.group == "natural" then
		return m.order > have.order
	end
	return false
end

-- 열매 등급 보너스 (일반 ×1 … 11등급 ×2)
function FruitRules.rarityBonus(rarityId: string): number
	local order = math.max(1, Rarities.order(rarityId))
	return 1 + (order - 1) * Mutations.FEED_RARITY_BONUS_PER_ORDER
end

-- 그 식물 열매를 이 돌연변이 목록의 식물에 먹일 때 붙을 수 있는 것과 확률 (Data 순서). 모르는 열매면 빈 목록
function FruitRules.feedOptions(fruitPlantId: string, mutations: { string }): { FeedOption }
	local fruit = Plants.get(fruitPlantId)
	local result: { FeedOption } = {}
	if not fruit then
		return result
	end
	local bonus = FruitRules.rarityBonus(fruit.rarity)
	local total = 0
	for _, m in Mutations.feed do
		if FruitRules.canGain(mutations, m.id) then
			local chance = (m.feedChance or 0) * bonus
			if m.feedBiomes and table.find(m.feedBiomes, fruit.biome) then
				chance *= Mutations.FEED_BIOME_BONUS
			end
			if chance > 0 then
				table.insert(result, { id = m.id, chance = chance })
				total += chance
			end
		end
	end
	if total > Mutations.FEED_MAX_CHANCE then
		local scale = Mutations.FEED_MAX_CHANCE / total
		for _, option in result do
			option.chance *= scale
		end
	end
	return result
end

-- 무언가 붙을 확률 합
function FruitRules.feedChance(fruitPlantId: string, mutations: { string }): number
	local total = 0
	for _, option in FruitRules.feedOptions(fruitPlantId, mutations) do
		total += option.chance
	end
	return total
end

-- 먹이기 한 번 굴리기 → 붙을 돌연변이 id, 안 붙으면 nil
function FruitRules.rollFeed(fruitPlantId: string, mutations: { string }, rand: RandomFn): string?
	local roll = rand()
	local acc = 0
	for _, option in FruitRules.feedOptions(fruitPlantId, mutations) do
		acc += option.chance
		if roll < acc then
			return option.id
		end
	end
	return nil
end

-- 돌연변이를 붙인 새 목록 (같은 group 의 옛 것은 빠짐, 원본은 안 바꿈)
function FruitRules.applyMutation(mutations: { string }, mutationId: string): { string }
	local m = Mutations.get(mutationId)
	if not m then
		return table.clone(mutations)
	end
	local result: { string } = {}
	for _, id in mutations do
		local other = Mutations.get(id)
		if not other or other.group ~= m.group then
			table.insert(result, id)
		end
	end
	table.insert(result, m.id)
	return result
end

-- 열매 1개 값 (코인) — Economy.fruitValue 와 같음 (서버·클라 미리보기용 이름)
function FruitRules.fruitValue(record: { petId: string, size: string, mutations: { string } }): number
	return Economy.recordFruitValue(record)
end

return FruitRules
