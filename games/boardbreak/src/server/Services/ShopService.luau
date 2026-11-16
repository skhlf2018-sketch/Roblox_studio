--!strict
--[[
	ShopService — 아령 사기 (Remote BuyDumbbell()) — 서버 판정
	  - 순서대로만: 다음 아령 = 지금 + 1 (Progression.canBuyDumbbell). 돈 ≥ price 면 빼고 아령 레벨 +1
	  - 화면 왼쪽 메뉴의 아령 가게에서 삼 (자리 확인 없음 — 가게 표지판 DumbbellShop 은 창을 여는 곳)
	  → Notify + DataUpdate "stats" · "progress" + Attr DumbbellLevel · Money
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Economy = require(Shared.Economy)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Attributes = require(Server.Attributes)
local Wallet = require(script.Parent.Wallet)

local ShopService = {}

-- 샀으면 true
function ShopService.buyDumbbell(player: Player): boolean
	local _, data = Sessions.getLoaded(player)
	if not data then
		return false
	end
	local ok, reason, nextDumbbell = Progression.canBuyDumbbell(data.dumbbellLevel, data.money)
	if not ok or not nextDumbbell then
		if reason == "max" then
			Net.notify(player, "info", "가장 좋은 아령을 이미 갖고 있어요!")
		elseif nextDumbbell then
			Net.notify(
				player,
				"error",
				string.format(
					"%s 은 %s 돈이 필요해요 (지금 %s)",
					nextDumbbell.name,
					Format.number(nextDumbbell.price),
					Format.number(data.money)
				)
			)
		end
		return false
	end
	if not Wallet.trySpend(player, nextDumbbell.price) then
		return false
	end
	data.dumbbellLevel = nextDumbbell.level
	Attributes.sync(player)
	Net.notify(
		player,
		"success",
		string.format(
			"%s! 한 번 들 때 힘 +%s",
			nextDumbbell.name,
			Format.number(Economy.trainGain(nextDumbbell.level, data.powerBoost))
		)
	)
	Snapshot.section(player, "stats")
	Snapshot.section(player, "progress")
	return true
end

function ShopService.start()
	Net.on(Remotes.ToServer.BuyDumbbell, function(player: Player)
		ShopService.buyDumbbell(player)
	end)
end

return ShopService
