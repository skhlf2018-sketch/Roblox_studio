--!strict
--[[
	AltarRules — 천사&악마 제단·비밀 통로 합성 규칙 (설계문서 4장, 순수 로직, Lune 테스트 대상)

	제단 (천국 = "light", 지옥 = "dark"):
	  - 천국 제단에는 천국 쪽 펫, 지옥 제단에는 지옥 쪽 펫을 바침 (Pets.side)
	  - 같은 낮/밤 주기 안에 천국 제단과 지옥 제단에 서로 다른 두 사람이 바치면
	    두 사람 모두 링 가드(80%) / 링로드(20%) 알을 받음 (각자 따로 추첨)
	  - 한 사람은 한 주기에 제물 하나만 걸어 둘 수 있음 (혼자 양쪽에 바치기 불가)
	  - 기다리는 동안 펫은 보관함에 그대로 있고, 짝이 맞는 순간 사라짐.
	    주기가 바뀌면 기다리던 제물은 취소 (펫은 그대로 남아 있음)
	  - 상태는 서버 메모리에만 (저장 안 함)

	비밀 통로 합성 (계정당 레시피마다 1번, 결과는 알로 부화 슬롯에):
	  페가수스 + 스켈레톤 말 → 에퀴녹스
	  대천사 + 세계를 불태우는 자 → 에테론
]]

local Data = script.Parent.Data
local Config = require(Data.Config)
local Pets = require(Data.Pets)
local Sizes = require(Data.Sizes)
local EggRoll = require(script.Parent.EggRoll)

type RandomFn = EggRoll.RandomFn

export type Side = string -- "light" | "dark"

export type Offer = {
	userId: number,
	petUid: string,
	petId: string,
	side: Side,
}

export type AltarState = {
	cycle: number,
	queues: { [Side]: { Offer } },
}

export type Recipe = { a: string, b: string, result: string }

local AltarRules = {}

AltarRules.BIOME = "angels_demons"
AltarRules.SIDES = { "light", "dark" }
AltarRules.RING_GUARD = "ring_guard"
AltarRules.RINGLORD = "ringlord"

AltarRules.RECIPES = {
	{ a = "pegasus", b = "skeleton_horse", result = "equinox" },
	{ a = "archangel", b = "world_burner", result = "aetheron" },
} :: { Recipe }

function AltarRules.new(cycle: number): AltarState
	return { cycle = cycle, queues = { light = {}, dark = {} } }
end

-- 이 펫이 바칠 수 있는 쪽 (천사&악마 둥지 펫만, 아니면 nil)
function AltarRules.sideOfPet(petId: string): Side?
	local pet = Pets.get(petId)
	if not pet or pet.biome ~= AltarRules.BIOME then
		return nil
	end
	return pet.side
end

-- 주기가 바뀌었으면 비움. 비워진 제물 목록을 돌려줌 (알림용)
function AltarRules.rollover(state: AltarState, cycle: number): { Offer }
	if state.cycle == cycle then
		return {}
	end
	local expired: { Offer } = {}
	for _, side in AltarRules.SIDES do
		for _, offer in state.queues[side] or {} do
			table.insert(expired, offer)
		end
		state.queues[side] = {}
	end
	state.cycle = cycle
	return expired
end

function AltarRules.findOffer(state: AltarState, userId: number): Offer?
	for _, side in AltarRules.SIDES do
		for _, offer in state.queues[side] or {} do
			if offer.userId == userId then
				return offer
			end
		end
	end
	return nil
end

-- 제물 걸기. (성공?, 실패 이유: "side" = 그 쪽 펫이 아님 | "already" = 이번 주기에 이미 걸어 둠)
function AltarRules.add(state: AltarState, offer: Offer, cycle: number): (boolean, string?)
	AltarRules.rollover(state, cycle)
	if AltarRules.sideOfPet(offer.petId) ~= offer.side then
		return false, "side"
	end
	if AltarRules.findOffer(state, offer.userId) then
		return false, "already"
	end
	table.insert(state.queues[offer.side], offer)
	return true, nil
end

-- 한 사람의 제물 취소 (나감 등). 취소했으면 true
function AltarRules.cancel(state: AltarState, userId: number): boolean
	for _, side in AltarRules.SIDES do
		local queue = state.queues[side]
		for i = #queue, 1, -1 do
			if queue[i].userId == userId then
				table.remove(queue, i)
				return true
			end
		end
	end
	return false
end

-- 짝 맞추기: 양쪽 맨 앞 제물이 둘 다 유효하고 서로 다른 사람이면 꺼내서 돌려줌.
-- isValid 가 false 인 제물(나간 사람, 펫이 없어짐)은 버리고 다음 제물로.
function AltarRules.tryPair(state: AltarState, isValid: (Offer) -> boolean): (Offer?, Offer?)
	local light, dark = state.queues.light, state.queues.dark
	while light[1] and not isValid(light[1]) do
		table.remove(light, 1)
	end
	while dark[1] and not isValid(dark[1]) do
		table.remove(dark, 1)
	end
	local a, b = light[1], dark[1]
	if not a or not b or a.userId == b.userId then
		return nil, nil
	end
	table.remove(light, 1)
	table.remove(dark, 1)
	return a, b
end

function AltarRules.pendingCount(state: AltarState, side: Side): number
	return #(state.queues[side] or {})
end

-- 링 가드 80% / 링로드 20%
function AltarRules.rollRingEgg(rand: RandomFn): string
	return if rand() < Config.ALTAR_RINGLORD_CHANCE then AltarRules.RINGLORD else AltarRules.RING_GUARD
end

-- 비밀 통로 레시피 (순서 상관없음). 없으면 nil
function AltarRules.recipeFor(petIdA: string, petIdB: string): Recipe?
	for _, recipe in AltarRules.RECIPES do
		if (recipe.a == petIdA and recipe.b == petIdB) or (recipe.a == petIdB and recipe.b == petIdA) then
			return recipe
		end
	end
	return nil
end

-- 합성 알 크기 [추정]: 두 펫 중 작은 크기 (둘 다 커야 큰 알)
function AltarRules.shrineSize(sizeA: string, sizeB: string): string
	local a, b = Sizes.get(sizeA), Sizes.get(sizeB)
	if not a or not b then
		return Sizes.DEFAULT
	end
	return if a.order <= b.order then a.id else b.id
end

return AltarRules
