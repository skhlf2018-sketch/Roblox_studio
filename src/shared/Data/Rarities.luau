--!strict
--[[
	Rarities — 희귀도 10등급 (설계문서 3장)
	color 는 RGB 0~255 숫자 배열 (Color3 를 쓰면 Lune 에서 못 읽으므로). 로블록스에서는 Color3.fromRGB(table.unpack(color)).
	glow: 특수 효과가 필요한 등급(선임이 반짝임/무지개 효과 붙일 때 참고)
]]

export type RarityId =
	"common"
	| "uncommon"
	| "rare"
	| "epic"
	| "legendary"
	| "mythic"
	| "cosmic"
	| "secret"
	| "eternal"
	| "divine"

export type Rarity = {
	id: RarityId,
	order: number,
	name: string,
	nameEn: string,
	color: { number },
	textColor: { number },
	glow: string?,
}

local list: { Rarity } = {
	{
		id = "common",
		order = 1,
		name = "일반",
		nameEn = "Common",
		color = { 160, 160, 160 },
		textColor = { 255, 255, 255 },
	},
	{
		id = "uncommon",
		order = 2,
		name = "고급",
		nameEn = "Uncommon",
		color = { 85, 200, 85 },
		textColor = { 255, 255, 255 },
	},
	{
		id = "rare",
		order = 3,
		name = "희귀",
		nameEn = "Rare",
		color = { 60, 130, 255 },
		textColor = { 255, 255, 255 },
	},
	{
		id = "epic",
		order = 4,
		name = "에픽",
		nameEn = "Epic",
		color = { 165, 80, 230 },
		textColor = { 255, 255, 255 },
	},
	{
		id = "legendary",
		order = 5,
		name = "전설",
		nameEn = "Legendary",
		color = { 255, 200, 40 },
		textColor = { 40, 30, 0 },
	},
	{
		id = "mythic",
		order = 6,
		name = "신화",
		nameEn = "Mythic",
		color = { 230, 50, 50 },
		textColor = { 255, 255, 255 },
	},
	{
		id = "cosmic",
		order = 7,
		name = "코스믹",
		nameEn = "Cosmic",
		color = { 110, 70, 230 },
		textColor = { 200, 230, 255 },
		glow = "galaxy",
	},
	{
		id = "secret",
		order = 8,
		name = "비밀",
		nameEn = "Secret",
		color = { 15, 15, 15 },
		textColor = { 255, 255, 255 },
		glow = "dark",
	},
	{
		id = "eternal",
		order = 9,
		name = "영원",
		nameEn = "Eternal",
		color = { 40, 220, 210 },
		textColor = { 0, 40, 40 },
		glow = "cyan",
	},
	{
		id = "divine",
		order = 10,
		name = "신성",
		nameEn = "Divine",
		color = { 255, 120, 220 },
		textColor = { 255, 255, 255 },
		glow = "rainbow",
	},
}

local byId: { [string]: Rarity } = {}
for _, rarity in list do
	byId[rarity.id] = rarity
end

local Rarities = {
	list = list,
	byId = byId,
	count = #list,
}

function Rarities.get(id: string): Rarity?
	return byId[id]
end

function Rarities.order(id: string): number
	local rarity = byId[id]
	return if rarity then rarity.order else 0
end

return Rarities
