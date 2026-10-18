--!strict
--[[
	IndexService — 도감: 처음 부화한 펫 발견 기록 + 보상 수령 (Claim / Claim All)

	보상 공식은 shared/Data/Index.luau (닭 +420/$100, 라쿤 +620/$4,500, 파타핌 +1,000/$180,000 과 일치)
	구역 펫을 전부 발견하면 그 구역 무기 해금 (Progression.unlockedWeapons, 천사&악마는 합성 펫 제외 18종)
	  → data.weapons 에 저장 + IndexService.weaponsChanged:fire(player, 새 무기 id 목록) → ToolService 가 도구 지급
	전체 완성 보너스는 한 번만 (indexCompleteClaimed).

	Remote: ClaimIndexReward("all" | petId)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Data.Pets)
local Index = require(Shared.Data.Index)
local Weapons = require(Shared.Data.Weapons)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Signal = require(Server.Util.Signal)
local Validate = require(Server.Logic.Validate)
local Wallet = require(script.Parent.Wallet)

local IndexService = {}

-- 새 무기 해금 (player, { weaponId })
IndexService.weaponsChanged = Signal.new()

-- 처음 본 펫이면 true
function IndexService.discover(player: Player, petId: string): boolean
	local _, data = Sessions.getLoaded(player)
	if not data or not Pets.get(petId) then
		return false
	end
	if data.indexDiscovered[petId] then
		return false
	end
	data.indexDiscovered[petId] = true
	local newWeapons: { string } = {}
	for _, id in Progression.unlockedWeapons(data.indexDiscovered) do
		if not table.find(data.weapons, id) then
			table.insert(data.weapons, id)
			table.insert(newWeapons, id)
		end
	end
	for _, id in newWeapons do
		local weapon = Weapons.get(id)
		Net.notify(
			player,
			"success",
			"구역 도감 완성! 새 무기 " .. (if weapon then weapon.name else id) .. " 을(를) 얻었어요!"
		)
	end
	if #newWeapons > 0 then
		IndexService.weaponsChanged:fire(player, newWeapons)
	end
	Snapshot.section(player, "index")
	return true
end

function IndexService.claim(player: Player, which: string)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	local claimedIds: { string } = {}
	local speed, money = 0, 0
	if which == "all" then
		claimedIds, speed, money = Progression.pendingRewards(data.indexDiscovered, data.indexClaimed)
	else
		local pet = Pets.get(which)
		if not pet or not data.indexDiscovered[which] or data.indexClaimed[which] then
			return
		end
		local ids, s, m = Progression.pendingRewards({ [which] = true }, data.indexClaimed)
		claimedIds, speed, money = ids, s, m
	end

	for _, id in claimedIds do
		data.indexClaimed[id] = true
	end

	-- 전체 완성 보너스 (한 번)
	local completeBonus = false
	if not data.indexCompleteClaimed and Progression.isIndexComplete(data.indexDiscovered) then
		data.indexCompleteClaimed = true
		speed += Index.FULL_COMPLETION.speed
		money += Index.FULL_COMPLETION.money
		completeBonus = true
	end

	if #claimedIds == 0 and not completeBonus then
		return
	end
	if speed > 0 then
		Wallet.addSpeed(player, speed)
	end
	if money > 0 then
		Wallet.addMoney(player, money)
	end
	Net.fire(player, Remotes.ToClient.IndexRewarded, {
		petIds = claimedIds,
		speed = speed,
		money = money,
		completeBonus = completeBonus,
	})
	Snapshot.section(player, "index")
end

function IndexService.start()
	local allowed: { [string]: boolean } = { all = true }
	for _, pet in Pets.list do
		allowed[pet.id] = true
	end
	Net.on(Remotes.ToServer.ClaimIndexReward, function(player: Player, which: unknown)
		local id = Validate.idIn(which, allowed)
		if id then
			IndexService.claim(player, id)
		end
	end)
end

return IndexService
