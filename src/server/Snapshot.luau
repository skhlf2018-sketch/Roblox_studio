--!strict
--[[
	Snapshot — 클라이언트에 보내는 플레이어 상태 묶음 (6판 "씨앗을 훔치세요")

	Snapshot.send(player)              → Remote "Snapshot" (전체)
	Snapshot.section(player, "pets")   → Remote "DataUpdate" ("pets", payload)  (일부만)

	6판 섹션: "pets"(정원의 성체 식물) · "incubators"(정원에 심어 자라는 씨앗) · "eggs"(씨앗 가방) · "fruits"(열매 가방) ·
	  "index" · "upgrades" · "tools" · "special"(사쿠라 크리스탈) · "tutorial"
	  (없앤 것: 장착만 보내던 Snapshot.equipment, payload 의 equipped·incomePerSecond·sakuraUnlocked·shrineUsed)
	섹션 종류와 payload 모양은 docs/REMOTES.md 참고.
	코인·속도처럼 자주 바뀌는 값은 Player Attribute 로 복제 (Tags.PlayerAttributes).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Economy = require(Shared.Economy)
local TutorialRules = require(Shared.TutorialRules)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Net = require(script.Parent.Net)
local Sessions = require(script.Parent.Sessions)

local Snapshot = {}

export type Section = "pets" | "incubators" | "eggs" | "fruits" | "index" | "upgrades" | "tools" | "special" | "tutorial"

function Snapshot.build(player: Player): Types.Snapshot?
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return nil
	end
	local slots = Economy.penSlots(data.penLevel)
	return {
		money = data.money,
		speed = data.speed,
		effectiveSpeed = session.effectiveSpeed,
		pets = data.pets,
		penLevel = data.penLevel,
		penSlots = slots,
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
		placedEggMax = slots,
		fruits = data.fruits,
		fruitBagMax = Config.FRUIT_BAG_MAX,
		plotIndex = session.plotIndex,
		saveEnabled = session.saveEnabled,
		sakuraCrystals = data.sakuraCrystals,
		tutorial = TutorialRules.view(data.tutorialStep),
	}
end

function Snapshot.send(player: Player)
	local snapshot = Snapshot.build(player)
	if snapshot then
		Net.fire(player, Remotes.ToClient.Snapshot, snapshot)
	end
end

function Snapshot.section(player: Player, section: Section)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	local payload: { [string]: any }
	if section == "pets" then
		payload = {
			pets = data.pets,
			penSlots = Economy.penSlots(data.penLevel),
		}
	elseif section == "incubators" then
		payload = { incubators = data.incubators }
	elseif section == "eggs" then
		payload = { eggs = data.eggs }
	elseif section == "fruits" then
		payload = { fruits = data.fruits }
	elseif section == "index" then
		payload = {
			indexDiscovered = data.indexDiscovered,
			indexClaimed = data.indexClaimed,
			indexCompleteClaimed = data.indexCompleteClaimed,
			unlockedWeapons = data.weapons,
		}
	elseif section == "upgrades" then
		local slots = Economy.penSlots(data.penLevel)
		payload = {
			penLevel = data.penLevel,
			penSlots = slots,
			placedEggMax = slots,
			treadmillLevel = data.treadmillLevel,
			trails = data.trails,
			equippedTrail = data.equippedTrail,
			trailMultiplier = Economy.trailMultiplier(data.equippedTrail),
		}
	elseif section == "tools" then
		payload = { tools = data.tools }
	elseif section == "special" then
		payload = { sakuraCrystals = data.sakuraCrystals }
	else -- "tutorial"
		payload = { tutorial = TutorialRules.view(data.tutorialStep) }
	end
	Net.fire(player, Remotes.ToClient.DataUpdate, section, payload)
end

return Snapshot
