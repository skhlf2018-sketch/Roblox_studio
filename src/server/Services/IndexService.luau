--!strict
--[[
	IndexService — 도감: 처음 성체가 된 식물 발견 기록 + 보상 수령 (Claim / Claim All)
	6판 "씨앗을 훔치세요": 성체 도감 (등급 11개). 씨앗이 정원에서 성체가 되는 순간 BaseService 가 discover.

	보상 공식은 shared/Data/Index.luau (속도 + 코인 = 열매 1개 값 × 10. 아기 데이지 +420 속도 / +100 코인)
	구역 식물을 전부 발견하면 그 구역 무기 해금 (Progression.unlockedWeapons, 벚꽃은 사쿠라 씨앗 2종 제외)
	  → data.weapons 에 저장 + IndexService.weaponsChanged:fire(player, 새 무기 id 목록) → ToolService 가 도구 지급
	곰덫 보상 (5판 설계문서 10장): 희귀(Rare) 이상 식물 첫 발견마다 +1, 구역 식물 전부 발견 때 +5 (Progression.trapsForDiscovery)
	  → 발견 즉시 data.tools.bearTrap 에 더함 + IndexService.toolsChanged:fire(player)
	전체 완성 보너스는 한 번만 (indexCompleteClaimed).

	Remote: ClaimIndexReward("all" | 식물 id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Plants)
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
-- 곰덫 개수가 늘어남 (player) → ToolService 가 도구·DataUpdate("tools") 갱신
IndexService.toolsChanged = Signal.new()

-- 처음 본 식물이면 true
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
	-- 곰덫 보상 (희귀 이상 첫 발견 +1, 구역 완성 +5, 최대 BEAR_TRAP_MAX_OWNED)
	local traps = Progression.trapsForDiscovery(data.indexDiscovered, petId)
	if traps > 0 then
		local before = data.tools.bearTrap or 0
		data.tools.bearTrap = math.min(Config.BEAR_TRAP_MAX_OWNED, (data.tools.bearTrap or 0) + traps)
		local gained = data.tools.bearTrap - before
		if gained > 0 then
			Net.notify(
				player,
				"success",
				string.format("도감 보상: 곰덫 +%d (지금 %d개)", gained, data.tools.bearTrap)
			)
			IndexService.toolsChanged:fire(player)
		end
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
