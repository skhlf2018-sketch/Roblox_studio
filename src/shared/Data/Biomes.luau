--!strict
--[[
	Biomes — 구역 15개 (설계문서 4장). 모든 구역 처음부터 열림(해금 비용 없음).

	6판 "씨앗을 훔치세요": 구역 이름·추천 속도·경비 속도는 그대로, 경비는 구역 테마 **식물 괴물** (이름만 여기 —
	  모양은 선임 Visuals.guards / PetVisualService). 둥지에는 씨앗이 놓임 (등급 가중치는 Data/EggSpawn).
	- recommendedSpeed: 입구 표지판에 적는 추천 속도 (원본 숫자)
	- guardSpeed: 경비 속도 = recommendedSpeed × Config.GUARD_SPEED_RATIO × (1 - 보통 알 무게 감소) (아래에서 자동 계산,
	  SpeedMath.guardSpeedFor 와 같은 식) → "추천 속도면 보통 알은 안전, 큰 알일수록 더 필요"
	- (2판) 경비는 추격 포기 거리 없이 허브까지 쫓아옴 → 1판 guardPersistence(포기 거리 배율) 삭제
	- weapon: 구역 도감 완성 시 받는 무기 (nil = 없음)
	- sides: 천사&악마처럼 주기마다 둥지 풀이 바뀌는 구역 ("light"/"dark")
	- nests: 둥지 수 (설계문서: 각 구역 8개)
]]

local Config = require(script.Parent.Config)
local Sizes = require(script.Parent.Sizes)

local NORMAL_PENALTY = (Sizes.get(Sizes.DEFAULT) :: Sizes.Size).speedPenalty

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
		guardName = "덥석 파리지옥",
		guardNameEn = "Snapjaw Flytrap",
		guardSpeed = 0,
		nests = 8,
		color = { 90, 170, 70 },
	},
	{
		id = "lake",
		order = 2,
		name = "호수",
		nameEn = "Lake",
		recommendedSpeed = 900,
		guardName = "연꽃 개구리풀",
		guardNameEn = "Lotus Frogweed",
		guardSpeed = 0,
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
		guardName = "가시 선인장 대장",
		guardNameEn = "Spiky Cactus Boss",
		guardSpeed = 0,
		nests = 8,
		color = { 225, 195, 120 },
	},
	{
		id = "jungle",
		order = 4,
		name = "정글",
		nameEn = "Jungle",
		recommendedSpeed = 40 * K,
		guardName = "덩굴 호랑이꽃",
		guardNameEn = "Vine Tigerbloom",
		guardSpeed = 0,
		nests = 8,
		color = { 40, 120, 50 },
	},
	{
		id = "snow",
		order = 5,
		name = "눈",
		nameEn = "Snow",
		recommendedSpeed = 170 * K,
		guardName = "서리 가시나무",
		guardNameEn = "Frost Thornbush",
		guardSpeed = 0,
		nests = 8,
		color = { 235, 245, 255 },
	},
	{
		id = "volcano",
		order = 6,
		name = "화산",
		nameEn = "Volcano",
		recommendedSpeed = 700 * K,
		guardName = "용암 머리꽃",
		guardNameEn = "Magma Bloomhead",
		guardSpeed = 0,
		nests = 8,
		color = { 120, 40, 30 },
	},
	{
		id = "abyss_ocean",
		order = 7,
		name = "심연의 바다",
		nameEn = "Abyss Ocean",
		recommendedSpeed = 2.5 * M,
		guardName = "심해 해초 괴물",
		guardNameEn = "Deep Kelp Monster",
		guardSpeed = 0,
		nests = 8,
		color = { 20, 40, 110 },
	},
	{
		id = "prehistoric",
		order = 8,
		name = "선사시대",
		nameEn = "Prehistoric",
		recommendedSpeed = 18 * M,
		guardName = "공룡 고사리",
		guardNameEn = "Dino Fern",
		guardSpeed = 0,
		nests = 8,
		color = { 140, 100, 60 },
	},
	{
		id = "cosmic",
		order = 9,
		name = "코스믹",
		nameEn = "Cosmic",
		recommendedSpeed = 700 * M,
		guardName = "우주 버섯 거인",
		guardNameEn = "Cosmic Mushroom Giant",
		guardSpeed = 0,
		nests = 8,
		color = { 60, 30, 110 },
	},
	{
		id = "cherry_blossom",
		order = 10,
		name = "벚꽃",
		nameEn = "Cherry Blossom",
		recommendedSpeed = 2.5 * B,
		guardName = "벚꽃 여우나무",
		guardNameEn = "Blossom Fox Tree",
		guardSpeed = 0,
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
		guardName = "돌 거인 나무",
		guardNameEn = "Stone Giant Tree",
		guardSpeed = 0,
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
		guardName = "천사 백합/악마 장미",
		guardNameEn = "Angel Lily/Demon Rose",
		sideGuardNames = { light = "천사 백합", dark = "악마 장미" },
		guardSpeed = 0,
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
		guardName = "정령 버섯",
		guardNameEn = "Spirit Shroom",
		guardSpeed = 0,
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
		guardName = "사탕수수 거인",
		guardNameEn = "Sugarcane Giant",
		guardSpeed = 0,
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
		guardName = "호박 머리 덩굴",
		guardNameEn = "Pumpkinhead Vine",
		guardSpeed = 0,
		weapon = { id = "scythe", name = "낫", nameEn = "Scythe" },
		nests = 8,
		color = { 80, 50, 100 },
		isNew = true,
	},
}

local byId: { [string]: Biome } = {}
for _, biome in list do
	-- 경비 속도는 추천 속도와 연동 (데이터에 따로 적지 않음). 보통 알 무게 감소를 기준에 포함.
	biome.guardSpeed = biome.recommendedSpeed * Config.GUARD_SPEED_RATIO * (1 - NORMAL_PENALTY)
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
