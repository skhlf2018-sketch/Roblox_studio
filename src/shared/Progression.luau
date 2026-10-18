--!strict
--[[
	Progression — 도감 진행도·구역 무기 해금 판정 (순수 로직, 서버/클라 공용)

	- 도감 진행도(biomeProgress): 구역의 펫 전부(퀘스트·합성·제단 포함) — 도감 화면 표시용
	- 무기 해금(weaponProgress): 구역 펫 전부, 단 Weapons 의 excludeSources 출처는 뺌
	    천사&악마: 합성 펫(에퀴녹스·에테론) 제외 18종이면 천사의 창 해금
]]

local Data = script.Parent.Data
local Pets = require(Data.Pets)
local Biomes = require(Data.Biomes)
local Index = require(Data.Index)
local Weapons = require(Data.Weapons)

type Pet = Pets.Pet

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

-- 무기 해금에 필요한 펫 목록 (무기가 없는 구역은 빈 목록)
function Progression.weaponRequirement(biomeId: string): { Pet }
	local weapon = Weapons.forBiome(biomeId)
	local result: { Pet } = {}
	if not weapon then
		return result
	end
	local exclude = weapon.excludeSources or {}
	for _, pet in Pets.inBiome(biomeId) do
		if not exclude[pet.source] then
			table.insert(result, pet)
		end
	end
	return result
end

-- (발견 수, 필요 수) — 도감 화면의 "무기까지 n/18" 표시용
function Progression.weaponProgress(discovered: { [string]: boolean }, biomeId: string): (number, number)
	local found, total = 0, 0
	for _, pet in Progression.weaponRequirement(biomeId) do
		total += 1
		if discovered[pet.id] then
			found += 1
		end
	end
	return found, total
end

function Progression.isWeaponUnlocked(discovered: { [string]: boolean }, biomeId: string): boolean
	local found, total = Progression.weaponProgress(discovered, biomeId)
	return total > 0 and found >= total
end

-- 도감으로 해금되는 무기 id 목록 (구역 순서)
function Progression.unlockedWeapons(discovered: { [string]: boolean }): { string }
	local result: { string } = {}
	for _, biome in Biomes.list do
		local weapon = Weapons.forBiome(biome.id)
		if weapon and Progression.isWeaponUnlocked(discovered, biome.id) then
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
