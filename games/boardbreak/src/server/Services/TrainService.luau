--!strict
--[[
	TrainService — 아령 들기 (Remote Train) — 서버 판정
	  - 수련 매트 위에서만: MapLayout.isOnTrainMat(캐릭터 위치, 지금 있는 월드) (선임 MapLayout)
	  - 한 번에 오르는 힘 = 아령 powerPerRep × PowerBoost (Economy.trainGain) — 1e60 에서 멈춤
	  - 속도 제한: Remotes.RateLimits.Train (초당 5번, 넘으면 버림 — Net.on)
	  → TrainResult { gain, power } (나에게만) · Attr Power (Wallet)
	매트 밖이면 힘이 안 오르고, 가끔(3초에 한 번) "수련 매트 위에서 들어요" 알림.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Character = require(Server.Util.Character)
local Wallet = require(script.Parent.Wallet)

local TrainService = {}

TrainService.OFF_MAT_TEXT = "수련 매트 위에서 아령을 들어요!"

-- 한 번 들기 (Remote 와 테스트가 같이 씀). 올랐으면 오른 힘, 아니면 0
function TrainService.train(player: Player): number
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return 0
	end
	local root = Character.getRoot(player)
	if not root or not Character.isAlive(player) then
		return 0 -- 죽은 캐릭터(Health 0)는 못 듦 (A-1)
	end
	if not MapLayout.isOnTrainMat(root.Position, session.currentWorld) then
		if Sessions.useCooldown(session, "offMat", 3, os.clock()) then
			Net.notify(player, "info", TrainService.OFF_MAT_TEXT)
		end
		return 0
	end
	local gain = Wallet.addPower(player, Economy.trainGain(data.dumbbellLevel, data.powerBoost))
	data.stats.trains += 1
	Net.fire(player, Remotes.ToClient.TrainResult, { gain = gain, power = data.power } :: Types.TrainResult)
	return gain
end

function TrainService.start()
	Net.on(Remotes.ToServer.Train, function(player: Player)
		TrainService.train(player)
	end)
end

return TrainService
