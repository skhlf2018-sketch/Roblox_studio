--!strict
--[[
	UpgradeService — 우리(Pen) / 러닝머신(Treadmill) / 트레일(Trail) 구매

	Remote: PurchaseUpgrade(kind: "Pen" | "Treadmill" | "Trail", trailId: string?)
	  - 가격·효과는 shared/Data/Upgrades.luau (설계문서 9장 표)
	  - 러닝머신 0레벨 = 잠김, 1레벨 구매($1K) = 해금
	  - 트레일은 순서 상관없이 아무거나 살 수 있음, 가진 것 중 최고 배율 하나만 적용

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
	Net.notify(player, "error", "돈이 부족해요! (" .. Format.money(cost) .. " 필요)")
end

function UpgradeService.purchase(player: Player, kind: string, trailId: string?)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	if kind == Remotes.UpgradeKinds.Pen then
		local cost = Economy.nextPenCost(data.penLevel)
		if not cost then
			Net.notify(player, "info", "우리가 이미 최대 레벨이에요.")
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
			string.format("우리 %d레벨! 장착 칸 %d개", data.penLevel, Economy.penSlots(data.penLevel))
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
		Wallet.syncSpeed(player)
		Net.notify(
			player,
			"success",
			string.format("%s 트레일! 속도 ×%s", trail.name, tostring(trail.multiplier))
		)
	else
		return
	end
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
end

function UpgradeService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	if data then
		player:SetAttribute(Attr.TreadmillLevel, data.treadmillLevel)
	end
end

return UpgradeService
