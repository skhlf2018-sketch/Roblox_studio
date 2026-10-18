--!strict
--[[
	Biomes — 구역 15개 (설계문서 4장). 모든 구역 처음부터 열림(해금 비용 없음).

	- recommendedSpeed: 입구 표지판에 적는 추천 속도 (원본 숫자)
	- guardSpeed: 경비 속도 = recommendedSpeed × Config.GUARD_SPEED_RATIO (아래에서 자동 계산)
	  → "실효 속도 ≥ 추천 속도면 못 잡고, 모자라면 잡힘" (SpeedMath.guardChaseRatio 참고)
	- guardPersistence: 뒤 구역일수록 더 끈질김(추격 포기 거리 배율) [추정]
	- weapon: 구역 도감 완성 시 받는 무기 (nil = 없음)
	- sides: 천사&악마처럼 주기마다 둥지 풀이 바뀌는 구역 ("light"/"dark")
	- nests: 둥지 수 (설계문서: 각 구역 8개)
]]

local Config = require(script.Parent.Config)

export type BiomeId = string

export type Weapon = {
	id: string,
	name: string,
	nameEn: string,
}

export type Biome = {
	id: BiomeId,
	order: number,
	name: string,
	nameEn: string,
	recommendedSpeed: number,
	guardName: string,
	guardNameEn: string,
	sideGuardNames: { [string]: string }?,
	guardSpeed: number,
	guardPersistence: number,
	weapon: Weapon?,
	sides: { string }?,
	nests: number,
	color: { number },
	isNew: boolean?,
}

local K = 1e3
local M = 1e6
local B = 1e9

local list: { Biome } = {
	{
		id = "forest",
		order = 1,
		name = "숲",
		nameEn = "Forest",
		recommendedSpeed = 10,
		guardName = "닭",
		guardNameEn = "Chicken",
		guardSpeed = 0,
		guardPersistence = 1,
		nests = 8,
		color = { 90, 170, 70 },
	},
	{
		id = "lake",
		order = 2,
		name = "호수",
		nameEn = "Lake",
		recommendedSpeed = 900,
		guardName = "백조",
		guardNameEn = "Swan",
		guardSpeed = 0,
		guardPersistence = 1.05,
		weapon = { id = "water_bat", name = "물 방망이", nameEn = "Water Bat" },
		nests = 8,
		color = { 70, 150, 220 },
	},
	{
		id = "desert",
		order = 3,
		name = "사막",
		nameEn = "Desert",
		recommendedSpeed = 10 * K,
		guardName = "전갈",
		guardNameEn = "Scorpion",
		guardSpeed = 0,
		guardPersistence = 1.1,
		nests = 8,
		color = { 225, 195, 120 },
	},
	{
		id = "jungle",
		order = 4,
		name = "정글",
		nameEn = "Jungle",
		recommendedSpeed = 40 * K,
		guardName = "호랑이",
		guardNameEn = "Tiger",
		guardSpeed = 0,
		guardPersistence = 1.15,
		nests = 8,
		color = { 40, 120, 50 },
	},
	{
		id = "snow",
		order = 5,
		name = "눈",
		nameEn = "Snow",
		recommendedSpeed = 170 * K,
		guardName = "예티",
		guardNameEn = "Yeti",
		guardSpeed = 0,
		guardPersistence = 1.2,
		nests = 8,
		color = { 235, 245, 255 },
	},
	{
		id = "volcano",
		order = 6,
		name = "화산",
		nameEn = "Volcano",
		recommendedSpeed = 700 * K,
		guardName = "케르베로스",
		guardNameEn = "Cerberus",
		guardSpeed = 0,
		guardPersistence = 1.25,
		nests = 8,
		color = { 120, 40, 30 },
	},
	{
		id = "abyss_ocean",
		order = 7,
		name = "심연의 바다",
		nameEn = "Abyss Ocean",
		recommendedSpeed = 2.5 * M,
		guardName = "벨루가 고래",
		guardNameEn = "Beluga Whale",
		guardSpeed = 0,
		guardPersistence = 1.3,
		nests = 8,
		color = { 20, 40, 110 },
	},
	{
		id = "prehistoric",
		order = 8,
		name = "선사시대",
		nameEn = "Prehistoric",
		recommendedSpeed = 18 * M,
		guardName = "티렉스",
		guardNameEn = "T-Rex",
		guardSpeed = 0,
		guardPersistence = 1.35,
		nests = 8,
		color = { 140, 100, 60 },
	},
	{
		id = "cosmic",
		order = 9,
		name = "코스믹",
		nameEn = "Cosmic",
		recommendedSpeed = 700 * M,
		guardName = "코스믹 스켈레톤 보스",
		guardNameEn = "Cosmic Skeleton Boss",
		guardSpeed = 0,
		guardPersistence = 1.4,
		nests = 8,
		color = { 60, 30, 110 },
	},
	{
		id = "cherry_blossom",
		order = 10,
		name = "벚꽃",
		nameEn = "Cherry Blossom",
		recommendedSpeed = 2.5 * B,
		guardName = "구미호(오니 타이거)",
		guardNameEn = "Kumiho (Oni Tiger)",
		guardSpeed = 0,
		guardPersistence = 1.45,
		weapon = { id = "katana", name = "카타나", nameEn = "Katana" },
		nests = 8,
		color = { 255, 180, 210 },
	},
	{
		id = "titan_temple",
		order = 11,
		name = "타이탄 사원",
		nameEn = "Titan Temple",
		recommendedSpeed = 7 * B,
		guardName = "고릴라 왕",
		guardNameEn = "Gorilla King",
		guardSpeed = 0,
		guardPersistence = 1.5,
		weapon = { id = "axe", name = "도끼", nameEn = "Axe" },
		nests = 8,
		color = { 150, 140, 110 },
	},
	{
		id = "angels_demons",
		order = 12,
		name = "천사 & 악마",
		nameEn = "Angels & Demons",
		recommendedSpeed = 20 * B,
		guardName = "천사/악마",
		guardNameEn = "Angel/Demon",
		sideGuardNames = { light = "천사", dark = "악마" },
		guardSpeed = 0,
		guardPersistence = 1.55,
		weapon = { id = "angel_spear", name = "천사의 창", nameEn = "Angel Spear" },
		sides = { "light", "dark" },
		nests = 8,
		color = { 245, 235, 200 },
	},
	{
		id = "enchanted_forest",
		order = 13,
		name = "마법의 숲",
		nameEn = "Enchanted Forest",
		recommendedSpeed = 50 * B,
		guardName = "정령",
		guardNameEn = "Spirit",
		guardSpeed = 0,
		guardPersistence = 1.6,
		weapon = { id = "hammer", name = "망치", nameEn = "Hammer" },
		nests = 8,
		color = { 60, 200, 170 },
	},
	{
		id = "candy_kingdom",
		order = 14,
		name = "사탕 왕국",
		nameEn = "Candy Kingdom",
		recommendedSpeed = 150 * B,
		guardName = "생강빵 거인",
		guardNameEn = "Gingerbread Giant",
		guardSpeed = 0,
		guardPersistence = 1.65,
		weapon = { id = "candy_cane", name = "사탕 지팡이", nameEn = "Candy Cane" },
		nests = 8,
		color = { 255, 150, 200 },
		isNew = true,
	},
	{
		id = "haunted_castle",
		order = 15,
		name = "유령 성",
		nameEn = "Haunted Castle",
		recommendedSpeed = 500 * B,
		guardName = "사신",
		guardNameEn = "Grim Reaper",
		guardSpeed = 0,
		guardPersistence = 1.7,
		weapon = { id = "scythe", name = "낫", nameEn = "Scythe" },
		nests = 8,
		color = { 80, 50, 100 },
		isNew = true,
	},
}

local byId: { [string]: Biome } = {}
for _, biome in list do
	-- 경비 속도는 추천 속도와 연동 (데이터에 따로 적지 않음)
	biome.guardSpeed = biome.recommendedSpeed * Config.GUARD_SPEED_RATIO
	byId[biome.id] = biome
end

local Biomes = {
	list = list,
	byId = byId,
	count = #list,
}

function Biomes.get(id: string): Biome?
	return byId[id]
end

-- 천사&악마처럼 sides 가 있는 구역에서 이번 주기의 쪽(light/dark). sides 가 없으면 nil.
function Biomes.sideForCycle(biome: Biome, cycleNumber: number): string?
	local sides = biome.sides
	if not sides or #sides == 0 then
		return nil
	end
	return sides[((cycleNumber - 1) % #sides) + 1]
end

function Biomes.guardDisplayName(biome: Biome, side: string?): string
	local names = biome.sideGuardNames
	if names and side and names[side] then
		return names[side]
	end
	return biome.guardName
end

return Biomes
