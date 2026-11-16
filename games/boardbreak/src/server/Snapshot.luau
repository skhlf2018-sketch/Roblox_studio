--!strict
--[[
	Snapshot — 클라이언트에 보내는 플레이어 상태 묶음 (송판 깨기, 첫 게임과 같은 방식)

	Snapshot.send(player)              → Remote "Snapshot" (Types.Snapshot 전체)
	Snapshot.section(player, "stats")  → Remote "DataUpdate" (section, payload) (일부만)
	  "stats"    { power, money }
	  "progress" { dumbbellLevel, belt, world, broken, grandMaster }
	  "passes"   { powerBoost, moneyPass, ownedPasses }
	  "settings" { settings }
	자주 바뀌는 힘·돈은 Player Attribute 로도 복제 (Tags.PlayerAttributes — Wallet 이 맞춤).
	치기·들기마다 "stats" 를 보내지 않음 (Attribute 로 충분 — 네트워크 아낌). 사기·승급·지급·불러오기 때만.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Net = require(script.Parent.Net)
local Sessions = require(script.Parent.Sessions)

local Snapshot = {}

export type Section = "stats" | "progress" | "passes" | "settings"

local function ownedPassList(session: Sessions.Session): { string }
	local list: { string } = {}
	for key, owned in session.ownedPasses do
		if owned then
			table.insert(list, key)
		end
	end
	table.sort(list)
	return list
end

function Snapshot.build(player: Player): Types.Snapshot?
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return nil
	end
	return {
		power = data.power,
		money = data.money,
		dumbbellLevel = data.dumbbellLevel,
		belt = data.belt,
		world = data.world,
		currentWorld = session.currentWorld,
		broken = data.broken,
		powerBoost = data.powerBoost,
		moneyPass = data.moneyPass,
		ownedPasses = ownedPassList(session),
		grandMaster = data.grandMaster,
		settings = data.settings,
		saveEnabled = session.saveEnabled,
		activity = Sessions.activity(session),
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
	if section == "stats" then
		payload = { power = data.power, money = data.money }
	elseif section == "progress" then
		payload = {
			dumbbellLevel = data.dumbbellLevel,
			belt = data.belt,
			world = data.world,
			broken = data.broken,
			grandMaster = data.grandMaster,
		}
	elseif section == "passes" then
		payload = { powerBoost = data.powerBoost, moneyPass = data.moneyPass, ownedPasses = ownedPassList(session) }
	else -- "settings"
		payload = { settings = data.settings }
	end
	Net.fire(player, Remotes.ToClient.DataUpdate, section, payload)
end

return Snapshot
