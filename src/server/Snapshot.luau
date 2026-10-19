--!strict
--[[
	Snapshot — 클라이언트에 보내는 플레이어 상태 묶음

	Snapshot.send(player)              → Remote "Snapshot" (전체)
	Snapshot.section(player, "pets")   → Remote "DataUpdate" ("pets", payload)  (일부만)
	Snapshot.equipment(player)         → DataUpdate("pets", { equipped, penSlots, incomePerSecond }) — 장착만 바뀜 (pets 목록 생략)

	섹션 종류와 payload 모양은 docs/REMOTES.md 참고.
	돈·속도처럼 자주 바뀌는 값은 Player Attribute 로 복제 (Tags.PlayerAttributes).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Economy = require(Shared.Economy)
local QuestRules = require(Shared.QuestRules)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Net = require(script.Parent.Net)
local Sessions = require(script.Parent.Sessions)

local Snapshot = {}

-- "eggs" (2판 수정) = 알 가방 / "incubators" = 우리에 놓인 알. 알을 놓거나 다시 주우면 둘 다 보냄
export type Section = "pets" | "incubators" | "eggs" | "index" | "upgrades" | "tools" | "flags" | "special" | "quests"

function Snapshot.build(player: Player): Types.Snapshot?
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return nil
	end
	return {
		money = data.money,
		speed = data.speed,
		effectiveSpeed = session.effectiveSpeed,
		incomePerSecond = session.incomePerSecond,
		pets = data.pets,
		equipped = data.equipped,
		penLevel = data.penLevel,
		penSlots = Economy.penSlots(data.penLevel),
		treadmillLevel = data.treadmillLevel,
		trails = data.trails,
		equippedTrail = data.equippedTrail,
		trailMultiplier = Economy.trailMultiplier(data.equippedTrail),
		indexDiscovered = data.indexDiscovered,
		indexClaimed = data.indexClaimed,
		indexCompleteClaimed = data.indexCompleteClaimed,
		unlockedWeapons = data.weapons,
		tools = data.tools,
		incubators = data.incubators,
		eggs = data.eggs,
		eggInventoryMax = Config.EGG_INVENTORY_MAX,
		placedEggMax = Config.PLACED_EGG_MAX,
		freeRewardClaimed = data.freeRewardClaimed,
		plotIndex = session.plotIndex,
		saveEnabled = session.saveEnabled,
		sakuraCrystals = data.sakuraCrystals,
		sakuraUnlocked = data.sakuraUnlocked,
		shrineUsed = data.shrineUsed,
		quests = QuestRules.view(data.quests),
		questsDone = data.questsRewarded,
		petInventoryMax = Config.PET_INVENTORY_MAX,
	}
end

function Snapshot.send(player: Player)
	local snapshot = Snapshot.build(player)
	if snapshot then
		Net.fire(player, Remotes.ToClient.Snapshot, snapshot)
	end
end

function Snapshot.section(player: Player, section: Section)
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	local payload: { [string]: any }
	if section == "pets" then
		payload = {
			pets = data.pets,
			equipped = data.equipped,
			penSlots = Economy.penSlots(data.penLevel),
			incomePerSecond = session.incomePerSecond,
		}
	elseif section == "incubators" then
		payload = { incubators = data.incubators }
	elseif section == "eggs" then
		payload = { eggs = data.eggs }
	elseif section == "index" then
		payload = {
			indexDiscovered = data.indexDiscovered,
			indexClaimed = data.indexClaimed,
			indexCompleteClaimed = data.indexCompleteClaimed,
			unlockedWeapons = data.weapons,
		}
	elseif section == "upgrades" then
		payload = {
			penLevel = data.penLevel,
			penSlots = Economy.penSlots(data.penLevel),
			treadmillLevel = data.treadmillLevel,
			trails = data.trails,
			equippedTrail = data.equippedTrail,
			trailMultiplier = Economy.trailMultiplier(data.equippedTrail),
		}
	elseif section == "tools" then
		payload = { tools = data.tools }
	elseif section == "special" then
		payload = {
			sakuraCrystals = data.sakuraCrystals,
			sakuraUnlocked = data.sakuraUnlocked,
			shrineUsed = data.shrineUsed,
		}
	elseif section == "quests" then
		payload = { quests = QuestRules.view(data.quests), questsDone = data.questsRewarded }
	else
		payload = { freeRewardClaimed = data.freeRewardClaimed }
	end
	Net.fire(player, Remotes.ToClient.DataUpdate, section, payload)
end

-- 장착만 바뀌었을 때: pets 목록(최대 500마리)은 다시 보내지 않음. State 가 합쳐서 나머지는 그대로 둠.
function Snapshot.equipment(player: Player)
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	Net.fire(player, Remotes.ToClient.DataUpdate, "pets", {
		equipped = data.equipped,
		penSlots = Economy.penSlots(data.penLevel),
		incomePerSecond = session.incomePerSecond,
	})
end

return Snapshot
