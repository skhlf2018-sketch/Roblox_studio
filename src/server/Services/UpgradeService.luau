--!strict
--[[
	UpgradeService — 정원(Pen, 5판 우리) / 러닝머신(Treadmill) / 트레일(Trail) 구매 (6판: 코인으로)
	정원 업그레이드 = 정원 칸 수 (자라는 씨앗 + 성체 식물이 이만큼까지, Upgrades.Pen 7 → 18칸)

	Remote: PurchaseUpgrade(kind: "Pen" | "Treadmill" | "Trail", trailId: string?)
	  - 가격·효과는 shared/Data/Upgrades.luau (설계문서 9장 표)
	  - 러닝머신 0레벨 = 잠김, 1레벨 구매(1K 코인) = 해금
	  - 트레일은 순서 상관없이 아무거나 살 수 있음, **장착한 트레일 하나**만 적용 (사면 바로 장착)

	Remote: EquipTrail(trailId | "none") — 가진 트레일로 바꿔 끼기, "none" 이면 해제 (data.equippedTrail)

	러닝머신 타기·걸음(속도 증가)은 2판부터 Services/TreadmillService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Upgrades = require(Shared.Data.Upgrades)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)
local Wallet = require(script.Parent.Wallet)
local PetService = require(script.Parent.PetService)

local Attr = Tags.PlayerAttributes

local UpgradeService = {}

local function notEnough(player: Player, cost: number)
	Net.notify(player, "error", "코인이 부족해요! (" .. Format.number(cost) .. " 코인 필요)")
end

function UpgradeService.purchase(player: Player, kind: string, trailId: string?)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	if kind == Remotes.UpgradeKinds.Pen then
		local cost = Economy.nextPenCost(data.penLevel)
		if not cost then
			Net.notify(player, "info", "정원이 이미 최대 레벨이에요.")
			return
		end
		if not Wallet.trySpend(player, cost) then
			notEnough(player, cost)
			return
		end
		data.penLevel += 1
		PetService.recalc(player)
		Net.notify(
			player,
			"success",
			string.format("정원 %d레벨! 정원 칸 %d개", data.penLevel, Economy.penSlots(data.penLevel))
		)
	elseif kind == Remotes.UpgradeKinds.Treadmill then
		local cost = Economy.nextTreadmillCost(data.treadmillLevel)
		if not cost then
			Net.notify(player, "info", "러닝머신이 이미 최대 레벨이에요.")
			return
		end
		if not Wallet.trySpend(player, cost) then
			notEnough(player, cost)
			return
		end
		data.treadmillLevel += 1
		player:SetAttribute(Attr.TreadmillLevel, data.treadmillLevel)
		Net.notify(
			player,
			"success",
			string.format(
				"러닝머신 %d레벨! 1초에 +%s 속도",
				data.treadmillLevel,
				Format.number(Economy.treadmillGainPerSecond(data.treadmillLevel))
			)
		)
	elseif kind == Remotes.UpgradeKinds.Trail then
		local trail = if trailId then Upgrades.getTrail(trailId) else nil
		if not trail then
			return
		end
		if table.find(data.trails, trail.id) then
			Net.notify(player, "info", "이미 가진 트레일이에요.")
			return
		end
		if not Wallet.trySpend(player, trail.cost) then
			notEnough(player, trail.cost)
			return
		end
		table.insert(data.trails, trail.id)
		data.equippedTrail = trail.id -- 사면 바로 장착
		Wallet.syncSpeed(player)
		Net.notify(
			player,
			"success",
			string.format("%s 트레일 장착! 속도 ×%s", trail.name, tostring(trail.multiplier))
		)
	else
		return
	end
	Snapshot.section(player, "upgrades")
end

-- 트레일 장착 (가진 것만) / Upgrades.NO_TRAIL("none") 이면 해제
function UpgradeService.equipTrail(player: Player, trailId: string)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	if trailId == data.equippedTrail then
		return
	end
	local message: string
	if trailId == Upgrades.NO_TRAIL then
		data.equippedTrail = Upgrades.NO_TRAIL
		message = "트레일을 뺐어요."
	else
		local trail = Upgrades.getTrail(trailId)
		if not trail or not table.find(data.trails, trail.id) then
			Net.notify(player, "error", "아직 없는 트레일이에요.")
			return
		end
		data.equippedTrail = trail.id
		message = string.format("%s 트레일 장착! 속도 ×%s", trail.name, tostring(trail.multiplier))
	end
	Wallet.syncSpeed(player)
	Net.notify(player, "success", message)
	Snapshot.section(player, "upgrades")
end

function UpgradeService.start()
	local trailIds: { [string]: boolean } = {}
	for _, trail in Upgrades.Trails do
		trailIds[trail.id] = true
	end
	Net.on(Remotes.ToServer.PurchaseUpgrade, function(player: Player, kind: unknown, trailId: unknown)
		local k = Validate.oneOf(kind, Remotes.UpgradeKinds)
		if not k then
			return
		end
		local id = if k == Remotes.UpgradeKinds.Trail then Validate.idIn(trailId, trailIds) else nil
		UpgradeService.purchase(player, k, id)
	end)
	local equipIds: { [string]: boolean } = table.clone(trailIds)
	equipIds[Upgrades.NO_TRAIL] = true
	Net.on(Remotes.ToServer.EquipTrail, function(player: Player, trailId: unknown)
		local id = Validate.idIn(trailId, equipIds)
		if id then
			UpgradeService.equipTrail(player, id)
		end
	end)
end

function UpgradeService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	if data then
		player:SetAttribute(Attr.TreadmillLevel, data.treadmillLevel)
	end
end

return UpgradeService
