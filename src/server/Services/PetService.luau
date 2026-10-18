--!strict
--[[
	PetService — 펫 보관함(상한 PET_INVENTORY_MAX) + 우리 장착 칸(레벨별) + 초당 수입 계산

	장착 펫 수입 = 기본(원본) × GROWTH_MULTIPLIER × 크기 × 돌연변이(곱) — Economy.petIncome
	초당 수입 합은 장착이 바뀔 때만 다시 계산해서 session.incomePerSecond 에 캐시 (IncomeService 가 1초마다 사용)

	보관함 상한: 펫이 PET_INVENTORY_MAX(500) 를 넘으면 장착 안 된 펫 중 수입이 가장 낮은 펫을
	  자동 판매 (돈 = 그 펫 초당 수입 × PET_AUTO_SELL_SECONDS) + PetsSold 알림. (DataStore 4MB·네트워크 보호)
	네트워크: 장착만 바뀔 때는 DataUpdate("pets") 에 pets 목록을 빼고 보냄 (Snapshot.equipment)

	Remote: EquipPet(petUid), UnequipPet(petUid), EquipBest()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)
local Wallet = require(script.Parent.Wallet)

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

local function indexOf(data: Types.PlayerData, uid: string): number?
	for i, pet in data.pets do
		if pet.uid == uid then
			return i
		end
	end
	return nil
end

function PetService.findPet(player: Player, uid: string): PetRecord?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	local i = indexOf(data, uid)
	return if i then data.pets[i] else nil
end

-- 보관함이 넘치면 싼 펫부터 판매. 팔린 펫 목록
local function enforceCap(player: Player, data: Types.PlayerData): { PetRecord }
	local sold: { PetRecord } = {}
	while #data.pets > Config.PET_INVENTORY_MAX do
		local uid = Economy.cheapestUnequipped(data.pets, data.equipped)
		local i = if uid then indexOf(data, uid) else nil
		if not i then
			break -- 전부 장착 중 (칸 수 < 상한이라 실제로는 안 생김)
		end
		table.insert(sold, table.remove(data.pets, i) :: PetRecord)
	end
	if #sold > 0 then
		local money = 0
		local names: { string } = {}
		for _, record in sold do
			money += Economy.recordIncome(record) * Config.PET_AUTO_SELL_SECONDS
			local pet = Pets.get(record.petId)
			table.insert(names, if pet then pet.name else record.petId)
		end
		Wallet.addMoney(player, money)
		Net.fire(player, Remotes.ToClient.PetsSold, { pets = sold, money = money })
		Net.notify(
			player,
			"info",
			string.format(
				"보관함이 가득 차서(%d마리) %s 을(를) 팔았어요 (+%s)",
				Config.PET_INVENTORY_MAX,
				table.concat(names, ", "),
				Format.money(money)
			)
		)
	end
	return sold
end

-- 새 펫 추가 (빈 칸이 있으면 자동 장착). 보관함에 남았으면 true (넘쳐서 바로 팔렸으면 false)
function PetService.addPet(player: Player, record: PetRecord): boolean
	local _, data = Sessions.getLoaded(player)
	if not data then
		return false
	end
	table.insert(data.pets, record)
	if #data.equipped < Economy.penSlots(data.penLevel) then
		table.insert(data.equipped, record.uid)
	end
	local kept = true
	for _, sold in enforceCap(player, data) do
		if sold.uid == record.uid then
			kept = false
		end
	end
	PetService.recalc(player)
	Snapshot.section(player, "pets")
	return kept
end

-- 펫 여러 마리 없애기 (퓨전·제단·합성 재료). 장착 중이면 자동 해제. 전부 있어야 함 (하나라도 없으면 아무것도 안 함)
function PetService.removePets(player: Player, uids: { string }): { PetRecord }?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	for _, uid in uids do
		if not indexOf(data, uid) then
			return nil
		end
	end
	local removed: { PetRecord } = {}
	for _, uid in uids do
		local i = indexOf(data, uid)
		if i then
			table.insert(removed, table.remove(data.pets, i) :: PetRecord)
		end
		local e = table.find(data.equipped, uid)
		if e then
			table.remove(data.equipped, e)
		end
	end
	PetService.recalc(player)
	Snapshot.section(player, "pets")
	return removed
end

-- 펫 돌연변이 등 속성이 바뀐 뒤 (사쿠라 블룸)
function PetService.changed(player: Player)
	PetService.recalc(player)
	Snapshot.section(player, "pets")
end

function PetService.equip(player: Player, uid: string): boolean
	local _, data = Sessions.getLoaded(player)
	if not data or not indexOf(data, uid) then
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
	Snapshot.equipment(player)
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
	Snapshot.equipment(player)
	return true
end

function PetService.equipBest(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	data.equipped = Economy.bestEquipSet(data.pets, Economy.penSlots(data.penLevel))
	PetService.recalc(player)
	Snapshot.equipment(player)
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
