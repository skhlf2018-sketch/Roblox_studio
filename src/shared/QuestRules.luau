--!strict
--[[
	QuestRules — 마법의 숲 퀘스트 진행 규칙 (순수 로직, Lune 테스트 대상). 퀘스트 목록은 Data/Quests.
]]

local Data = script.Parent.Data
local Quests = require(Data.Quests)
local Types = require(script.Parent.Types)

type Quest = Quests.Quest

export type QuestEvent = {
	kind: string, -- "deliver" | "fuse"
	biome: string?,
	rarity: string?,
}

local QuestRules = {}

function QuestRules.matches(quest: Quest, event: QuestEvent): boolean
	if quest.kind ~= event.kind then
		return false
	end
	if quest.biome and quest.biome ~= event.biome then
		return false
	end
	if quest.rarity and quest.rarity ~= event.rarity then
		return false
	end
	return true
end

function QuestRules.isDone(progress: { [string]: number }, quest: Quest): boolean
	return (progress[quest.id] or 0) >= quest.target
end

function QuestRules.allDone(progress: { [string]: number }): boolean
	for _, quest in Quests.list do
		if not QuestRules.isDone(progress, quest) then
			return false
		end
	end
	return true
end

-- 일 하나 반영. 진행도가 바뀐 퀘스트 id 목록 (끝난 퀘스트는 더 안 올라감)
function QuestRules.apply(progress: { [string]: number }, event: QuestEvent): { string }
	local changed: { string } = {}
	for _, quest in Quests.list do
		if not QuestRules.isDone(progress, quest) and QuestRules.matches(quest, event) then
			progress[quest.id] = math.min(quest.target, (progress[quest.id] or 0) + 1)
			table.insert(changed, quest.id)
		end
	end
	return changed
end

-- 클라에 보낼 모양
function QuestRules.view(progress: { [string]: number }): { Types.QuestView }
	local result: { Types.QuestView } = {}
	for _, quest in Quests.list do
		local value = math.min(progress[quest.id] or 0, quest.target)
		table.insert(result, {
			id = quest.id,
			name = quest.name,
			progress = value,
			target = quest.target,
			done = value >= quest.target,
		})
	end
	return result
end

return QuestRules
