--!strict
--[[
	SakuraRules — 사쿠라 인큐베이터 규칙 (설계문서 4장·8장, 순수 로직, Lune 테스트 대상)

	- 해금: 학(Crane) 펫 1마리를 바침 (Config.SAKURA_UNLOCK_PET)
	- 사쿠라 크리스탈 Config.SAKURA_APPLY_COST 개로 부화 중인 알 또는 보관 펫 하나에
	    블룸(×1.5) 97.5% / 스피릿 블룸(×3) 2.5% (Mutations.sourceChance)
	- 블룸은 자연 돌연변이(실버/골든/레인보우) 위에 중첩 가능, 블룸끼리는 불가 (같은 group "bloom")
]]

local Data = script.Parent.Data
local Config = require(Data.Config)
local Mutations = require(Data.Mutations)
local EggRoll = require(script.Parent.EggRoll)
local Types = require(script.Parent.Types)

type RandomFn = EggRoll.RandomFn

local SakuraRules = {}

SakuraRules.GROUP = "bloom"

-- 블룸 계열 돌연변이 (확률 순서대로)
function SakuraRules.bloomMutations(): { Mutations.Mutation }
	local result: { Mutations.Mutation } = {}
	for _, mutation in Mutations.list do
		if mutation.group == SakuraRules.GROUP then
			table.insert(result, mutation)
		end
	end
	return result
end

function SakuraRules.hasBloom(mutations: { string }): boolean
	for _, id in mutations do
		local mutation = Mutations.get(id)
		if mutation and mutation.group == SakuraRules.GROUP then
			return true
		end
	end
	return false
end

-- (가능?, 안 되는 이유 문구)
function SakuraRules.canApply(mutations: { string }): (boolean, string?)
	if SakuraRules.hasBloom(mutations) then
		return false, "이미 블룸이 붙어 있어요! (블룸끼리는 겹칠 수 없어요)"
	end
	return true, nil
end

function SakuraRules.canAfford(crystals: number): boolean
	return crystals >= Config.SAKURA_APPLY_COST
end

-- 블룸 97.5% / 스피릿 블룸 2.5%
function SakuraRules.roll(rand: RandomFn): string
	local blooms = SakuraRules.bloomMutations()
	local pick = EggRoll.weightedPick(blooms, function(m: Mutations.Mutation): number
		return m.sourceChance or 0
	end, rand)
	return if pick then pick.id else "bloom"
end

-- 새 돌연변이 목록 (원본은 안 바꿈). 이미 블룸이 있으면 그대로 돌려줌.
function SakuraRules.apply(mutations: { string }, bloomId: string): { string }
	local result = table.clone(mutations)
	if not SakuraRules.hasBloom(result) then
		table.insert(result, bloomId)
	end
	return result
end

-- 해금 제물로 바칠 학 고르기: uid 를 주면 그 펫(학이어야 함), 없으면 수입이 가장 낮은 학
function SakuraRules.pickOffering(
	records: { Types.PetRecord },
	incomeOf: (number) -> number,
	requestedUid: string?
): number?
	local bestIndex: number? = nil
	local bestIncome = math.huge
	for i, record in records do
		if record.petId == Config.SAKURA_UNLOCK_PET then
			if requestedUid then
				if record.uid == requestedUid then
					return i
				end
			else
				local income = incomeOf(i)
				if income < bestIncome then
					bestIndex, bestIncome = i, income
				end
			end
		end
	end
	return bestIndex
end

return SakuraRules
