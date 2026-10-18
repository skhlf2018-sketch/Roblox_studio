--!strict
--[[
	FusionRules — 퓨전 머신 규칙 (설계문서 9-4, 순수 로직, Lune 테스트 대상)

	같은 펫(petId) 3마리 → 더 강한 펫 1마리. 즉시, 비용 없음, 되돌릴 수 없음.
	1) 결과 펫: 같은 구역에서 희귀도가 한 단계 높은 "둥지" 펫 중 하나를 고르게 추첨
	     - 천사&악마처럼 쪽(side)이 있으면 같은 쪽 펫을 먼저 (없으면 아무 쪽)
	     - 퀘스트·합성·제단 펫은 결과로 안 나옴 (그 펫들은 각자 얻는 방법이 따로 있음)
	   한 단계 높은 펫이 없으면 → 같은 펫, 크기 한 단계 업 (셋 중 가장 큰 크기 기준)
	2) 돌연변이: 셋의 돌연변이 묶음이 전부 같으면 유지, 아니면 전부 사라짐
	3) 크기 보정: 결과 수입이 3마리 수입 합보다 작으면 크기를 올려 합 이상이 되게 함
	     - 한 단계 높은 펫 중 초거대로도 합에 못 미치는 펫은 후보에서 빠짐
	     - 같은 펫 크기 업도 초거대로 모자라면 합성 거부 ("weaker") — "수입은 3마리 합 이상" 약속을 지키려고
	4) 보너스: 10% 확률로 실버/골든/레인보우(가중치 5 : 2 : 0.5) 중 하나 새로 부여
	     - 크기 보정이 끝난 뒤에 붙음 (순수 보너스)
	     - 이미 자연 돌연변이가 있으면 더 좋은 쪽만 남김

	난수 rand() 는 밖에서 주입 ([0, 1) 숫자). 호출 순서: 후보 고르기 1번(후보가 2개 이상일 때) → 보너스 확률 1번 → (당첨 시) 종류 1번
]]

local Data = script.Parent.Data
local Config = require(Data.Config)
local Pets = require(Data.Pets)
local Rarities = require(Data.Rarities)
local Sizes = require(Data.Sizes)
local Mutations = require(Data.Mutations)
local Economy = require(script.Parent.Economy)
local EggRoll = require(script.Parent.EggRoll)
local Types = require(script.Parent.Types)

type Pet = Pets.Pet
type PetRecord = Types.PetRecord
type RandomFn = EggRoll.RandomFn

export type FusionError = "count" | "duplicate" | "mismatch" | "unknown" | "weaker"

export type FusionResult = {
	petId: string,
	size: string,
	mutations: { string },
	upgraded: boolean, -- true = 희귀도 한 단계 위 펫, false = 같은 펫 크기 업
	bonusMutation: string?, -- 보너스로 새로 붙은 자연 돌연변이 (없으면 nil)
	inputIncome: number, -- 3마리 수입 합 (초당)
	resultIncome: number, -- 결과 수입 (초당)
}

type Option = { petId: string, size: string }

local FusionRules = {}

FusionRules.INPUT_COUNT = 3

local ERROR_TEXT: { [string]: string } = {
	count = "같은 펫 3마리를 골라 주세요.",
	duplicate = "같은 펫을 두 번 넣을 수 없어요.",
	mismatch = "똑같은 종류의 펫 3마리만 합칠 수 있어요.",
	unknown = "가지고 있지 않은 펫이에요.",
	weaker = "이 펫은 더 강해질 수 없어서 합칠 수 없어요.",
}

function FusionRules.errorText(err: string): string
	return ERROR_TEXT[err] or "합칠 수 없어요."
end

-- 입력 검사: 3마리, uid 서로 다름, petId 전부 같고 존재
function FusionRules.validate(inputs: { PetRecord }): (boolean, FusionError?)
	if #inputs ~= FusionRules.INPUT_COUNT then
		return false, "count"
	end
	local seen: { [string]: boolean } = {}
	local petId = inputs[1].petId
	for _, record in inputs do
		if seen[record.uid] then
			return false, "duplicate"
		end
		seen[record.uid] = true
		if record.petId ~= petId then
			return false, "mismatch"
		end
	end
	if not Pets.get(petId) then
		return false, "unknown"
	end
	return true, nil
end

-- 결과 후보: 같은 구역, 희귀도 +1, 둥지 펫 (같은 쪽 우선)
function FusionRules.candidates(petId: string): { Pet }
	local pet = Pets.get(petId)
	if not pet then
		return {}
	end
	local targetOrder = Rarities.order(pet.rarity) + 1
	local all: { Pet } = {}
	local sameSide: { Pet } = {}
	for _, other in Pets.inBiome(pet.biome) do
		if other.source == "nest" and Rarities.order(other.rarity) == targetOrder then
			table.insert(all, other)
			if pet.side ~= nil and other.side == pet.side then
				table.insert(sameSide, other)
			end
		end
	end
	return if #sameSide > 0 then sameSide else all
end

local function mutationKey(mutations: { string }): string
	local sorted = table.clone(mutations)
	table.sort(sorted)
	return table.concat(sorted, ",")
end

-- 셋의 돌연변이 묶음이 전부 같으면 그 묶음, 아니면 빈 목록
function FusionRules.commonMutations(inputs: { PetRecord }): { string }
	if #inputs == 0 then
		return {}
	end
	local key = mutationKey(inputs[1].mutations)
	for i = 2, #inputs do
		if mutationKey(inputs[i].mutations) ~= key then
			return {}
		end
	end
	return table.clone(inputs[1].mutations)
end

function FusionRules.totalIncome(inputs: { PetRecord }): number
	local total = 0
	for _, record in inputs do
		total += Economy.recordIncome(record)
	end
	return total
end

local function sizeOrder(sizeId: string): number
	local size = Sizes.get(sizeId)
	return if size then size.order else 1
end

-- startOrder 이상 크기 중 수입이 target 이상이 되는 가장 작은 크기 (없으면 nil)
function FusionRules.minimalSize(petId: string, mutations: { string }, target: number, startOrder: number): string?
	for order = math.max(1, startOrder), #Sizes.list do
		local size = Sizes.list[order]
		if Economy.petIncome(petId, size.id, mutations) >= target * (1 - 1e-9) then
			return size.id
		end
	end
	return nil
end

-- 보너스 돌연변이 추첨 (10% → 실버/골든/레인보우 5:2:0.5)
function FusionRules.rollBonusMutation(rand: RandomFn): string?
	if rand() >= Config.FUSION_BONUS_MUTATION_CHANCE then
		return nil
	end
	local ids: { string } = {}
	for _, mutation in Mutations.list do
		if Config.FUSION_BONUS_MUTATION_WEIGHTS[mutation.id] then
			table.insert(ids, mutation.id)
		end
	end
	return EggRoll.weightedPick(ids, function(id: string): number
		return Config.FUSION_BONUS_MUTATION_WEIGHTS[id] or 0
	end, rand)
end

-- 보너스 붙이기: 같은 group(자연) 돌연변이가 이미 있으면 배율이 더 높은 쪽만 남김.
-- (새 목록, 실제로 붙었으면 그 id)
function FusionRules.applyBonus(mutations: { string }, bonus: string?): ({ string }, string?)
	local result = table.clone(mutations)
	local mutation = if bonus then Mutations.get(bonus) else nil
	if not mutation then
		return result, nil
	end
	for i, id in result do
		local existing = Mutations.get(id)
		if existing and existing.group == mutation.group then
			if mutation.multiplier > existing.multiplier then
				result[i] = mutation.id
				return result, mutation.id
			end
			return result, nil
		end
	end
	table.insert(result, mutation.id)
	return result, mutation.id
end

-- 합성 1번. 성공하면 (결과, nil), 실패하면 (nil, 오류)
function FusionRules.fuse(inputs: { PetRecord }, rand: RandomFn): (FusionResult?, FusionError?)
	local ok: boolean, err: FusionError? = FusionRules.validate(inputs)
	if not ok then
		return nil, err
	end
	local petId = inputs[1].petId
	local inputIncome = FusionRules.totalIncome(inputs)
	local mutations = FusionRules.commonMutations(inputs)

	local options: { Option } = {}
	for _, candidate in FusionRules.candidates(petId) do
		local size = FusionRules.minimalSize(candidate.id, mutations, inputIncome, 1)
		if size then
			table.insert(options, { petId = candidate.id, size = size })
		end
	end

	local chosen: Option
	local upgraded: boolean
	if #options > 0 then
		local index = if #options == 1 then 1 else math.clamp(math.floor(rand() * #options) + 1, 1, #options)
		chosen = options[index]
		upgraded = true
	else
		local largest = 1
		for _, record in inputs do
			largest = math.max(largest, sizeOrder(record.size))
		end
		local size = FusionRules.minimalSize(petId, mutations, inputIncome, largest + 1)
		if not size then
			return nil, "weaker"
		end
		chosen = { petId = petId, size = size }
		upgraded = false
	end

	local finalMutations, bonus = FusionRules.applyBonus(mutations, FusionRules.rollBonusMutation(rand))
	return {
		petId = chosen.petId,
		size = chosen.size,
		mutations = finalMutations,
		upgraded = upgraded,
		bonusMutation = bonus,
		inputIncome = inputIncome,
		resultIncome = Economy.petIncome(chosen.petId, chosen.size, finalMutations),
	},
		nil
end

return FusionRules
