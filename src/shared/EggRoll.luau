--!strict
--[[
	EggRoll — 둥지 알 추첨 (순수 로직, Lune 테스트 대상)

	난수는 밖에서 주입합니다: rand() 는 [0, 1) 숫자를 돌려주는 함수.
	  서버: local rng = Random.new(); local rand = function() return rng:NextNumber() end
	  테스트: 고정 시드 난수로 결과 재현
]]

local Data = script.Parent.Data
local Pets = require(Data.Pets)
local Sizes = require(Data.Sizes)
local Mutations = require(Data.Mutations)
local EggSpawn = require(Data.EggSpawn)

type Pet = Pets.Pet

export type RandomFn = () -> number

export type EggTraits = {
	size: string,
	mutations: { string },
}

local EggRoll = {}

-- 가중치 배열에서 인덱스 하나 (가중치 합이 0 이하면 nil)
function EggRoll.weightedIndex(weights: { number }, rand: RandomFn): number?
	local total = 0
	for _, w in weights do
		if w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rand() * total
	local acc = 0
	local last: number? = nil
	for i, w in weights do
		if w > 0 then
			acc += w
			last = i
			if roll < acc then
				return i
			end
		end
	end
	return last -- 부동소수점 끝자락 보정
end

function EggRoll.weightedPick<T>(items: { T }, weightOf: (T) -> number, rand: RandomFn): T?
	local weights: { number } = table.create(#items)
	for i, item in items do
		weights[i] = weightOf(item)
	end
	local index = EggRoll.weightedIndex(weights, rand)
	return if index then items[index] else nil
end

-- 크기: 70 / 20 / 8 / 2 %
function EggRoll.rollSize(rand: RandomFn): string
	local size = EggRoll.weightedPick(Sizes.list, function(s: Sizes.Size): number
		return s.chance
	end, rand)
	return if size then size.id else Sizes.DEFAULT
end

-- 자연 돌연변이: 한 번 굴려서 레인보우 0.5% / 골든 2% / 실버 5% / 없음 92.5%
function EggRoll.rollNaturalMutation(rand: RandomFn): string?
	local roll = rand()
	local acc = 0
	for _, mutation in Mutations.natural do -- 확률 오름차순(희귀한 것 먼저)
		acc += mutation.naturalChance
		if roll < acc then
			return mutation.id
		end
	end
	return nil
end

function EggRoll.rollTraits(rand: RandomFn): EggTraits
	local mutations: { string } = {}
	local natural = EggRoll.rollNaturalMutation(rand)
	if natural then
		table.insert(mutations, natural)
	end
	return {
		size = EggRoll.rollSize(rand),
		mutations = mutations,
	}
end

-- 둥지에 나올 수 있는 펫 (source = "nest", sides 가 있는 구역은 이번 쪽만)
function EggRoll.nestPool(biomeId: string, side: string?): { Pet }
	local pool: { Pet } = {}
	for _, pet in Pets.inBiome(biomeId) do
		if pet.source == "nest" and (pet.side == nil or pet.side == side) then
			table.insert(pool, pet)
		end
	end
	return pool
end

function EggRoll.nestWeight(pet: Pet): number
	return EggSpawn.NEST_RARITY_WEIGHTS[pet.rarity] or 0
end

-- 일반 추첨 1마리 (비밀/영원/신성 제외)
function EggRoll.rollNestPet(biomeId: string, side: string?, rand: RandomFn): Pet?
	return EggRoll.weightedPick(EggRoll.nestPool(biomeId, side), EggRoll.nestWeight, rand)
end

-- 일반 추첨에서 각 펫이 나올 확률 (0~1) — 테스트·밸런스 확인용
function EggRoll.nestOdds(biomeId: string, side: string?): { [string]: number }
	local pool = EggRoll.nestPool(biomeId, side)
	local total = 0
	for _, pet in pool do
		total += EggRoll.nestWeight(pet)
	end
	local odds: { [string]: number } = {}
	for _, pet in pool do
		odds[pet.id] = if total > 0 then EggRoll.nestWeight(pet) / total else 0
	end
	return odds
end

-- 초기화 때 특별 추첨: 이번에 놓일 특별 알 펫 목록 (희귀한 것부터, 최대 MAX_SPECIALS_PER_BIOME)
function EggRoll.rollSpecials(biomeId: string, side: string?, rand: RandomFn): { Pet }
	local pool = EggRoll.nestPool(biomeId, side)
	local result: { Pet } = {}
	for _, rarityId in EggSpawn.SPECIAL_RARITIES do
		if #result >= EggSpawn.MAX_SPECIALS_PER_BIOME then
			break
		end
		local candidates: { Pet } = {}
		for _, pet in pool do
			if pet.rarity == rarityId then
				table.insert(candidates, pet)
			end
		end
		if #candidates > 0 then
			local chance = EggSpawn.SPECIAL_CHANCE_PER_RESET[rarityId] or 0
			if rand() < chance then
				local index = math.clamp(math.floor(rand() * #candidates) + 1, 1, #candidates)
				table.insert(result, candidates[index])
			end
		end
	end
	return result
end

-- 1..count 중 서로 다른 칸 n 개를 무작위로 (특별 알 둥지 위치 고르기)
function EggRoll.pickDistinct(count: number, n: number, rand: RandomFn): { number }
	local indices: { number } = table.create(count)
	for i = 1, count do
		indices[i] = i
	end
	for i = count, 2, -1 do
		local j = math.clamp(math.floor(rand() * i) + 1, 1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end
	local result: { number } = {}
	for i = 1, math.min(n, count) do
		table.insert(result, indices[i])
	end
	return result
end

return EggRoll
