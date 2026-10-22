--!strict
--[[
	PetService — 펫 보관함(상한 PET_INVENTORY_MAX) + 우리 장착 칸(레벨별) + 초당 수입 계산

	장착 펫 수입 = 기본(원본) × GROWTH_MULTIPLIER × 크기 × 돌연변이(곱) — Economy.petIncome
	초당 수입 합은 장착이 바뀔 때만 다시 계산해서 session.incomePerSecond 에 캐시 (IncomeService 가 1초마다 사용)

	보관함 상한: 펫이 PET_INVENTORY_MAX(500) 를 넘으면 장착 안 된 펫 중 수입이 가장 낮은 펫을
	  자동 판매 (돈 = 그 펫 초당 수입 × PET_AUTO_SELL_SECONDS) + PetsSold 알림. (DataStore 4MB·네트워크 보호)
	네트워크: 장착만 바뀔 때는 DataUpdate("pets") 에 pets 목록을 빼고 보냄 (Snapshot.equipment)

	Remote: EquipPet(petUid), UnequipPet(petUid), EquipBest()
	2판 Remote: SellPet(petUid) — 판매 가게(SellStall 태그 파트, 없으면 MapLayout.sellSpots 자리) SELL_RADIUS(14) 안에서만.
	  장착 중이면 해제 후 판매. 가격 = 그 펫 초당 수입(Economy.recordIncome) × PET_SELL_SECONDS(60). 결과는 Notify.

	5판:
	  - addPet(player, record, autoEquip?) — autoEquip = false 면 빈 칸이 있어도 장착 안 함 (튜토리얼 중 부화)
	  - 신호 equipChanged(player): EquipPet 성공 / EquipBest → TutorialService (5단계 "펫 장착")
	  - Remote PetPet(petUid): 내 우리의 장착 펫 쓰다듬기. 검증 = uid 형식 · 내 펫이고 장착 중 · 내 베이스가 있음 ·
	      내 캐릭터가 내 우리(MapLayout.penRect) 에서 PET_PET_RADIUS(20) 안 · 사람마다 PET_PET_COOLDOWN(1초).
	      통과하면 PetPetted(ownerUserId, petUid) 를 서버 전체에 (하트·소리 연출은 클라)
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
local MapLayout = require(Shared.Data.MapLayout)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)
local Character = require(Server.Util.Character)
local Landmarks = require(Server.Util.Landmarks)
local Signal = require(Server.Util.Signal)
local Wallet = require(script.Parent.Wallet)

type PetRecord = Types.PetRecord

local Attr = Tags.PlayerAttributes

local PetService = {}

-- 5판: 장착이 바뀜 (player) — EquipPet 성공 / EquipBest (튜토리얼 5단계)
PetService.equipChanged = Signal.new()

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

-- 새 펫 추가 (빈 칸이 있으면 자동 장착, autoEquip = false 면 안 함). 보관함에 남았으면 true (넘쳐서 바로 팔렸으면 false)
function PetService.addPet(player: Player, record: PetRecord, autoEquip: boolean?): boolean
	local _, data = Sessions.getLoaded(player)
	if not data then
		return false
	end
	table.insert(data.pets, record)
	if autoEquip ~= false and #data.equipped < Economy.penSlots(data.penLevel) then
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
	PetService.equipChanged:fire(player)
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
	PetService.equipChanged:fire(player)
end

-- 판매 가게 근처인가: 맵의 SellStall 태그 파트 표면 또는 MapLayout 판매 자리(허브 + 베이스마다)에서 SELL_RADIUS 안
function PetService.isNearSellStall(player: Player): boolean
	local root = Character.getRoot(player)
	if not root or not Character.isAlive(player) then
		return false
	end
	if Landmarks.nearest(player, Landmarks.tagged(Tags.SellStall), Config.SELL_RADIUS) then
		return true
	end
	local p = root.Position
	for _, spot in MapLayout.sellSpots() do
		local dx, dz = p.X - spot.x, p.Z - spot.z
		if dx * dx + dz * dz <= Config.SELL_RADIUS * Config.SELL_RADIUS then
			return true
		end
	end
	return false
end

-- 펫 팔기 (장착 중이면 해제 후). 판 값 (못 팔면 nil)
function PetService.sell(player: Player, uid: string): number?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	if not PetService.isNearSellStall(player) then
		Net.notify(player, "error", "판매 가게 가까이에서 팔 수 있어요!")
		return nil
	end
	local record = PetService.findPet(player, uid)
	if not record then
		return nil
	end
	local price = Economy.recordIncome(record) * Config.PET_SELL_SECONDS
	local removed = PetService.removePets(player, { uid })
	if not removed then
		return nil
	end
	Wallet.addMoney(player, price)
	local pet = Pets.get(record.petId)
	Net.notify(
		player,
		"success",
		string.format("%s 을(를) %s 에 팔았어요!", if pet then pet.name else record.petId, Format.money(price))
	)
	return price
end

-- 5판: 내 캐릭터가 내 우리(울타리 사각형) 에서 radius 안인가 (수평 거리, 우리 안이면 0)
function PetService.isNearOwnPen(player: Player, radius: number): boolean
	local session = Sessions.get(player)
	local root = Character.getRoot(player)
	if not session or session.plotIndex == 0 or not root or not Character.isAlive(player) then
		return false
	end
	local rect = MapLayout.penRect(session.plotIndex)
	if not rect then
		return false
	end
	local p = root.Position
	local dx = math.max(rect.xMin - p.X, 0, p.X - rect.xMax)
	local dz = math.max(rect.zMin - p.Z, 0, p.Z - rect.zMax)
	return dx * dx + dz * dz <= radius * radius
end

-- 5판 PetPet: 내 우리의 장착 펫 쓰다듬기 → PetPetted(ownerUserId, petUid) 서버 전체. 성공하면 true
function PetService.petPet(player: Player, uid: string): boolean
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return false
	end
	if not indexOf(data, uid) or not table.find(data.equipped, uid) then
		return false -- 내 펫이 아니거나 우리에 없는(장착 안 된) 펫
	end
	if not PetService.isNearOwnPen(player, Config.PET_PET_RADIUS) then
		return false
	end
	if not Sessions.useCooldown(session, "petPet", Config.PET_PET_COOLDOWN, os.clock()) then
		return false
	end
	Net.fireAll(Remotes.ToClient.PetPetted, player.UserId, uid)
	return true
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
	Net.on(Remotes.ToServer.SellPet, function(player: Player, uid: unknown)
		local petUid = Validate.uid(uid)
		if petUid then
			PetService.sell(player, petUid)
		end
	end)
	Net.on(Remotes.ToServer.PetPet, function(player: Player, uid: unknown)
		local petUid = Validate.uid(uid)
		if petUid then
			PetService.petPet(player, petUid)
		end
	end)
end

return PetService
