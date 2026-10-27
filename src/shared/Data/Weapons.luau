--!strict
--[[
	Weapons — 근접 무기 (설계문서 9-5, 10장). 기본 야구 방망이 + 구역 도감 완성 무기 7개.

	- id: 무기 id (Biomes.weapon.id 와 같음, 기본 방망이는 "baseball_bat")
	- toolKind: 서버가 Backpack 에 넣는 Tool 이름 = UseTool(kind) 인자 (Remotes.ToolKinds 에 있어야 함)
	- biome: 이 구역 도감을 완성하면 해금 (nil = 기본 지급)
	- range: 사거리(스터드, 서버가 대상 찾을 때)
	- knockback: 넉백 힘 배율 (Config.KNOCKBACK_SPEED 에 곱함)
	- cooldown: 쿨다운(초). 근접 무기는 쿨다운을 같이 씀 (바꿔 들기로 쿨다운 피하기 방지)
	- excludeSources: 해금 판정에서 빼는 식물 출처 (6판: 벚꽃은 사쿠라 나무 씨앗 2종 제외 → 둥지 식물 8종이면 완성)

	뒤 구역 무기일수록 사거리·넉백이 크고, 쿨다운은 조금씩 짧아짐 (방망이 1.2초 → 낫 0.8초) [본부장 결정]
]]

local Config = require(script.Parent.Config)

export type Weapon = {
	id: string,
	order: number,
	toolKind: string,
	name: string,
	nameEn: string,
	biome: string?,
	range: number,
	knockback: number,
	cooldown: number,
	tip: string,
	excludeSources: { [string]: boolean }?,
}

local list: { Weapon } = {
	{
		id = "baseball_bat",
		order = 0,
		toolKind = "Bat",
		name = "야구 방망이",
		nameEn = "Baseball Bat",
		biome = nil,
		range = Config.BAT_RANGE,
		knockback = 1,
		cooldown = Config.BAT_COOLDOWN_SECONDS,
		tip = "야구 방망이: 다른 플레이어를 날려 씨앗을 떨어뜨려요",
	},
	{
		id = "water_bat",
		order = 2,
		toolKind = "WaterBat",
		name = "물 방망이",
		nameEn = "Water Bat",
		biome = "lake",
		range = 10.5,
		knockback = 1.15,
		cooldown = 1.15,
		tip = "물 방망이: 방망이보다 조금 더 멀리 날려요",
	},
	{
		id = "katana",
		order = 10,
		toolKind = "Katana",
		name = "카타나",
		nameEn = "Katana",
		biome = "cherry_blossom",
		range = 12,
		knockback = 1.35,
		cooldown = 1.1,
		tip = "카타나: 벚꽃 구역 도감 완성 무기",
		excludeSources = { sakura = true },
	},
	{
		id = "axe",
		order = 11,
		toolKind = "Axe",
		name = "도끼",
		nameEn = "Axe",
		biome = "titan_temple",
		range = 13,
		knockback = 1.5,
		cooldown = 1.0,
		tip = "도끼: 타이탄 사원 도감 완성 무기",
	},
	{
		id = "angel_spear",
		order = 12,
		toolKind = "AngelSpear",
		name = "천사의 창",
		nameEn = "Angel Spear",
		biome = "angels_demons",
		range = 14.5,
		knockback = 1.65,
		cooldown = 0.95,
		tip = "천사의 창: 천사&악마 도감 완성 무기",
	},
	{
		id = "hammer",
		order = 13,
		toolKind = "Hammer",
		name = "망치",
		nameEn = "Hammer",
		biome = "enchanted_forest",
		range = 15.5,
		knockback = 1.85,
		cooldown = 0.9,
		tip = "망치: 마법의 숲 도감 완성 무기",
	},
	{
		id = "candy_cane",
		order = 14,
		toolKind = "CandyCane",
		name = "사탕 지팡이",
		nameEn = "Candy Cane",
		biome = "candy_kingdom",
		range = 16.5,
		knockback = 2.05,
		cooldown = 0.85,
		tip = "사탕 지팡이: 사탕 왕국 도감 완성 무기",
	},
	{
		id = "scythe",
		order = 15,
		toolKind = "Scythe",
		name = "낫",
		nameEn = "Scythe",
		biome = "haunted_castle",
		range = 18,
		knockback = 2.3,
		cooldown = 0.8,
		tip = "낫: 유령 성 도감 완성 무기",
	},
}

local byId: { [string]: Weapon } = {}
local byToolKind: { [string]: Weapon } = {}
local byBiome: { [string]: Weapon } = {}
for _, weapon in list do
	assert(byId[weapon.id] == nil, "Weapons: 중복 id " .. weapon.id)
	byId[weapon.id] = weapon
	byToolKind[weapon.toolKind] = weapon
	local biome = weapon.biome
	if biome then
		byBiome[biome] = weapon
	end
end

local Weapons = {
	list = list,
	byId = byId,
	DEFAULT = "baseball_bat",
}

function Weapons.get(id: string): Weapon?
	return byId[id]
end

function Weapons.byTool(toolKind: string): Weapon?
	return byToolKind[toolKind]
end

function Weapons.forBiome(biomeId: string): Weapon?
	return byBiome[biomeId]
end

return Weapons
