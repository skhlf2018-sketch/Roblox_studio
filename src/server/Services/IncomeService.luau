--!strict
--[[
	IncomeService — 1초마다 장착 펫 수입을 돈에 더함 (플레이어별 합산 1회, 서버만)
	수입 합계는 PetService 가 장착이 바뀔 때 계산해 둔 session.incomePerSecond 사용.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Data.Config)
local Sessions = require(script.Parent.Parent.Sessions)
local Wallet = require(script.Parent.Wallet)

local IncomeService = {}

function IncomeService.start()
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.INCOME_TICK_SECONDS)
			local now = os.clock()
			local dt = math.clamp(now - last, 0, 5) -- 서버가 잠깐 멈춰도 한 번에 너무 많이 주지 않음
			last = now
			for player, session in Sessions.all() do
				if session.loaded and session.incomePerSecond > 0 then
					local ok, err = pcall(Wallet.addMoney, player, session.incomePerSecond * dt)
					if not ok then
						warn("[IncomeService] " .. tostring(err))
					end
				end
			end
		end
	end)
end

return IncomeService
