--!strict
--[[
	RewardService — 오프라인 수입

	오프라인 수입: (접속 시각 - 마지막 저장 시각) × 지금 장착 펫 초당 수입, 상한 24시간
	  → 접속 때 지급하고 OfflineIncome Remote 로 팝업 정보 전송 ("You earn $16M/Day offline!")
	5판: 무료 보상(선물, ClaimFreeReward +10,000 속도)은 사장님 지시로 없앰. 도감 보상은 IndexService 그대로.
	Remote 를 받지 않아서 start() 가 없음 (PlayerLifecycle 이 onPlayerReady 만 부름).
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

return RewardService
