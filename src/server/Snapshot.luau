--!strict
--[[
	Snapshot — 클라이언트에 보내는 플레이어 상태 묶음

	Snapshot.send(player)              → Remote "Snapshot" (전체)
	Snapshot.section(player, "pets")   → Remote "DataUpdate" ("pets", payload)  (일부만)

	섹션 종류와 payload 모양은 docs/REMOTES.md 참고.
	돈·속도처럼 자주 바뀌는 값은 Player Attribute 로 복제 (Tags.PlayerAttributes).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Economy)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Net = require(script.Parent.Net)
local Sessions = require(script.Parent.Sessions)

local Snapshot = {}

export type Section = "pets" | "incubators" | "index" | "upgrades" | "tools" | "flags"

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
		trailMultiplier = Economy.bestTrailMultiplier(data.trails),
		indexDiscovered = data.indexDiscovered,
		indexClaimed = data.indexClaimed,
		indexCompleteClaimed = data.indexCompleteClaimed,
		unlockedWeapons = Progression.unlockedWeapons(data.indexDiscovered),
		tools = data.tools,
		incubators = data.incubators,
		freeRewardClaimed = data.freeRewardClaimed,
		plotIndex = session.plotIndex,
		saveEnabled = session.saveEnabled,
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
	elseif section == "index" then
		payload = {
			indexDiscovered = data.indexDiscovered,
			indexClaimed = data.indexClaimed,
			indexCompleteClaimed = data.indexCompleteClaimed,
			unlockedWeapons = Progression.unlockedWeapons(data.indexDiscovered),
		}
	elseif section == "upgrades" then
		payload = {
			penLevel = data.penLevel,
			penSlots = Economy.penSlots(data.penLevel),
			treadmillLevel = data.treadmillLevel,
			trails = data.trails,
			trailMultiplier = Economy.bestTrailMultiplier(data.trails),
		}
	elseif section == "tools" then
		payload = { tools = data.tools }
	else
		payload = { freeRewardClaimed = data.freeRewardClaimed }
	end
	Net.fire(player, Remotes.ToClient.DataUpdate, section, payload)
end

return Snapshot
