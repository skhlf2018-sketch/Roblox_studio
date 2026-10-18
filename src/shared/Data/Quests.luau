--!strict
--[[
	Quests — 마법의 숲 퀘스트 3개 (설계문서 4장 "알 20개 훔치기 / 동물 합성 / 영원 알 훔치기")

	- kind: 어떤 일이 진행도를 올리나
	    "deliver" = 알을 내 베이스 배달 패드에 배달 (선물 알·제단 알은 안 셈)
	    "fuse"    = 퓨전 머신으로 합성 성공
	- biome / rarity: 있으면 그 구역 / 그 희귀도 알만 셈 (nil = 아무거나)
	- target: 목표 횟수

	[추정] "알 20개" 는 마법의 숲 알만 셈 (아무 알이나 세면 마법의 숲에 오기 전에 이미 끝나 있어서).
	       "영원 알" 은 아무 구역 영원 알 (마법의 숲 영원 알만 세면 초기화당 2% 라 너무 오래 걸림).
	전부 끝내면: 퀘스트 문(Tag QuestGate) 통과 + 지터버그 알 즉시 지급,
	이후 그 사람이 서버에 있으면 초기화 때 마법의 숲 둥지에 영혼 세계 수호자 알이
	Config.QUEST_SECRET_EGG_CHANCE(1%) 로 등장 (퀘스트를 끝낸 사람만 주울 수 있음).
]]

export type Quest = {
	id: string,
	order: number,
	name: string,
	kind: "deliver" | "fuse",
	target: number,
	biome: string?,
	rarity: string?,
}

local list: { Quest } = {
	{
		id = "deliver_eggs",
		order = 1,
		name = "마법의 숲 알 20개 배달하기",
		kind = "deliver",
		target = 20,
		biome = "enchanted_forest",
	},
	{
		id = "fuse_once",
		order = 2,
		name = "퓨전 머신으로 동물 합성하기",
		kind = "fuse",
		target = 1,
	},
	{
		id = "deliver_eternal",
		order = 3,
		name = "영원 알 1개 배달하기",
		kind = "deliver",
		target = 1,
		rarity = "eternal",
	},
}

local byId: { [string]: Quest } = {}
for _, quest in list do
	byId[quest.id] = quest
end

local Quests = {
	list = list,
	byId = byId,
	BIOME = "enchanted_forest",
	REWARD_EGG = "jitterbug", -- 다 끝내면 바로 받는 알
	SECRET_EGG = "spirit_world_guardian", -- 그 뒤 둥지에 낮은 확률로 등장
}

function Quests.get(id: string): Quest?
	return byId[id]
end

return Quests
