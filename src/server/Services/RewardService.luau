--!strict
--[[
	RewardService — 오프라인 수입 + 무료 보상 (+10,000 속도)

	오프라인 수입: (접속 시각 - 마지막 저장 시각) × 지금 장착 펫 초당 수입, 상한 24시간
	  → 접속 때 지급하고 OfflineIncome Remote 로 팝업 정보 전송 ("You earn $16M/Day offline!")
	무료 보상: 게임 좋아요 + 즐겨찾기 + 그룹 가입 → +10,000 속도 (계정당 1번)
	  좋아요/즐겨찾기는 서버가 확인할 방법이 없어서 확인하지 않음.
	  Config.FREE_REWARD_GROUP_ID 를 넣으면 그룹 가입은 서버가 확인함 (player:IsInGroup).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Wallet = require(script.Parent.Wallet)
local PetService = require(script.Parent.PetService)

local RewardService = {}

-- PetService.onPlayerReady 다음에 호출해야 함 (수입이 계산된 뒤)
function RewardService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	local income = PetService.getIncome(player)
	local amount, seconds = Economy.offlineIncome(income, data.lastSaveTime, os.time())
	if amount > 0 then
		Wallet.addMoney(player, amount)
	end
	if amount > 0 and seconds >= Config.OFFLINE_POPUP_MIN_SECONDS then
		Net.fire(player, Remotes.ToClient.OfflineIncome, {
			amount = amount,
			seconds = seconds,
			perDay = income * 86400,
			text = "오프라인 동안 " .. Format.money(amount) .. " 벌었어요!",
		})
	end
end

function RewardService.claimFree(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data or data.freeRewardClaimed then
		return
	end
	local groupId = Config.FREE_REWARD_GROUP_ID
	if groupId > 0 then
		local ok, inGroup = pcall(function(): boolean
			return player:IsInGroup(groupId)
		end)
		if not ok or not inGroup then
			Net.notify(player, "error", "그룹에 가입한 뒤 다시 눌러 주세요!")
			return
		end
	end
	data.freeRewardClaimed = true
	Wallet.addSpeed(player, Config.FREE_REWARD_SPEED)
	Net.notify(player, "success", "무료 보상! 속도 +" .. Format.number(Config.FREE_REWARD_SPEED))
	Snapshot.section(player, "flags")
end

function RewardService.start()
	Net.on(Remotes.ToServer.ClaimFreeReward, function(player: Player)
		RewardService.claimFree(player)
	end)
end

return RewardService
