--!strict
--[[
	IncomeService — 1초마다 장착 펫 수입을 돈에 더함 (플레이어별 합산 1회, 서버만)
	수입 합계는 PetService 가 장착이 바뀔 때 계산해 둔 session.incomePerSecond 사용.

	2판 IncomeTick (펫 머리 위 "+$34K" 초록 팝업용):
	  장착 펫마다 INCOME_POPUP_INTERVAL(3)초에 한 번 { petUid, amount = 그 펫 초당 수입 × 3 } 을 보냄.
	  펫들은 순서대로 엇갈려 보냄 (1초마다 1/3 씩) → 팝업이 한꺼번에 몰리지 않고 네트워크도 고르게.
	  돈 자체는 1초마다 합계로 들어감 (팝업은 표시용, 돈 계산과 별개).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Wallet = require(script.Parent.Wallet)

local IncomeService = {}

-- 이번 틱(tickCount)에 팝업을 보낼 장착 펫들
local function sendPopups(player: Player, session: Sessions.Session, tickCount: number)
	local data = session.data
	if not data or #data.equipped == 0 then
		return
	end
	local interval = math.max(1, Config.INCOME_POPUP_INTERVAL)
	local order: { [string]: number } = {}
	for i, uid in data.equipped do
		order[uid] = i
	end
	local multiplier = if session.hasMoneyPass then Config.GAMEPASS_MONEY_MULTIPLIER else 1
	for _, pet in data.pets do
		local i = order[pet.uid]
		if i and (i + tickCount) % interval == 0 then
			local amount = Economy.recordIncome(pet) * multiplier * interval
			if amount > 0 then
				Net.fire(player, Remotes.ToClient.IncomeTick, { petUid = pet.uid, amount = amount })
			end
		end
	end
end

function IncomeService.start()
	task.spawn(function()
		local last = os.clock()
		local tickCount = 0
		while true do
			task.wait(Config.INCOME_TICK_SECONDS)
			local now = os.clock()
			local dt = math.clamp(now - last, 0, 5) -- 서버가 잠깐 멈춰도 한 번에 너무 많이 주지 않음
			last = now
			tickCount += 1
			for player, session in Sessions.all() do
				if session.loaded and session.incomePerSecond > 0 then
					local amount = session.incomePerSecond * dt
					local ok, err = pcall(function(): ...any
						Wallet.addMoney(player, amount)
						sendPopups(player, session, tickCount)
					end)
					if not ok then
						warn("[IncomeService] " .. tostring(err))
					end
				end
			end
		end
	end)
end

return IncomeService
