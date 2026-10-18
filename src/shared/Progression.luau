--!strict
--[[
	Progression — 도감 진행도·구역 무기 해금 판정 (순수 로직, 서버/클라 공용)
	구역의 펫(Pets.inBiome, 퀘스트·합성 포함)을 전부 발견하면 그 구역 무기 해금.
]]

local Data = script.Parent.Data
local Pets = require(Data.Pets)
local Biomes = require(Data.Biomes)
local Index = require(Data.Index)

local Progression = {}

-- (발견 수, 전체 수)
function Progression.biomeProgress(discovered: { [string]: boolean }, biomeId: string): (number, number)
	local found, total = 0, 0
	for _, pet in Pets.inBiome(biomeId) do
		total += 1
		if discovered[pet.id] then
			found += 1
		end
	end
	return found, total
end

function Progression.isBiomeComplete(discovered: { [string]: boolean }, biomeId: string): boolean
	local found, total = Progression.biomeProgress(discovered, biomeId)
	return total > 0 and found >= total
end

function Progression.unlockedWeapons(discovered: { [string]: boolean }): { string }
	local result: { string } = {}
	for _, biome in Biomes.list do
		local weapon = biome.weapon
		if weapon and Progression.isBiomeComplete(discovered, biome.id) then
			table.insert(result, weapon.id)
		end
	end
	return result
end

function Progression.isIndexComplete(discovered: { [string]: boolean }): boolean
	for _, pet in Pets.list do
		if not discovered[pet.id] then
			return false
		end
	end
	return true
end

-- 아직 안 받은 도감 보상 목록과 합계
function Progression.pendingRewards(
	discovered: { [string]: boolean },
	claimed: { [string]: boolean }
): ({ string }, number, number)
	local ids: { string } = {}
	local speed, money = 0, 0
	for _, pet in Pets.list do
		if discovered[pet.id] and not claimed[pet.id] then
			local biome = Biomes.get(pet.biome)
			local reward = Index.reward(pet.rarity, pet.income, if biome then biome.recommendedSpeed else 0)
			table.insert(ids, pet.id)
			speed += reward.speed
			money += reward.money
		end
	end
	return ids, speed, money
end

return Progression
