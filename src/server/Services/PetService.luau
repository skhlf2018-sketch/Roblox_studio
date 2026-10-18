--!strict
--[[
	PetService — 펫 보관함(무제한) + 우리 장착 칸(레벨별) + 초당 수입 계산

	장착 펫 수입 = 기본(원본) × GROWTH_MULTIPLIER × 크기 × 돌연변이(곱) — Economy.petIncome
	초당 수입 합은 장착이 바뀔 때만 다시 계산해서 session.incomePerSecond 에 캐시 (IncomeService 가 1초마다 사용)

	Remote: EquipPet(petUid), UnequipPet(petUid), EquipBest()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)

type PetRecord = Types.PetRecord

local Attr = Tags.PlayerAttributes

local PetService = {}

function PetService.recalc(player: Player)
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	local moneyMultiplier = if session.hasMoneyPass then Config.GAMEPASS_MONEY_MULTIPLIER else 1
	session.incomePerSecond = Economy.totalIncome(data.pets, data.equipped, moneyMultiplier)
	player:SetAttribute(Attr.IncomePerSecond, session.incomePerSecond)
	player:SetAttribute(Attr.PenLevel, data.penLevel)
	player:SetAttribute(Attr.PenSlots, Economy.penSlots(data.penLevel))
end

function PetService.getIncome(player: Player): number
	local session = Sessions.get(player)
	return if session then session.incomePerSecond else 0
end

local function findPet(data: Types.PlayerData, uid: string): PetRecord?
	for _, pet in data.pets do
		if pet.uid == uid then
			return pet
		end
	end
	return nil
end

-- 새 펫 추가 (빈 칸이 있으면 자동 장착)
function PetService.addPet(player: Player, record: PetRecord)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	table.insert(data.pets, record)
	if #data.equipped < Economy.penSlots(data.penLevel) then
		table.insert(data.equipped, record.uid)
	end
	PetService.recalc(player)
	Snapshot.section(player, "pets")
end

function PetService.equip(player: Player, uid: string): boolean
	local _, data = Sessions.getLoaded(player)
	if not data or not findPet(data, uid) then
		return false
	end
	if table.find(data.equipped, uid) then
		return false
	end
	if #data.equipped >= Economy.penSlots(data.penLevel) then
		Net.notify(player, "error", "우리가 가득 찼어요! 우리를 업그레이드하세요.")
		return false
	end
	table.insert(data.equipped, uid)
	PetService.recalc(player)
	Snapshot.section(player, "pets")
	return true
end

function PetService.unequip(player: Player, uid: string): boolean
	local _, data = Sessions.getLoaded(player)
	if not data then
		return false
	end
	local index = table.find(data.equipped, uid)
	if not index then
		return false
	end
	table.remove(data.equipped, index)
	PetService.recalc(player)
	Snapshot.section(player, "pets")
	return true
end

function PetService.equipBest(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	data.equipped = Economy.bestEquipSet(data.pets, Economy.penSlots(data.penLevel))
	PetService.recalc(player)
	Snapshot.section(player, "pets")
end

function PetService.onPlayerReady(player: Player)
	PetService.recalc(player)
end

function PetService.start()
	Net.on(Remotes.ToServer.EquipPet, function(player: Player, uid: unknown)
		local petUid = Validate.uid(uid)
		if petUid then
			PetService.equip(player, petUid)
		end
	end)
	Net.on(Remotes.ToServer.UnequipPet, function(player: Player, uid: unknown)
		local petUid = Validate.uid(uid)
		if petUid then
			PetService.unequip(player, petUid)
		end
	end)
	Net.on(Remotes.ToServer.EquipBest, function(player: Player)
		PetService.equipBest(player)
	end)
end

return PetService
