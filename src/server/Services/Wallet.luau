--!strict
--[[
	Wallet — 코인(돈)/속도 숫자를 바꾸는 유일한 통로 (서버 전용)
	6판: 돈 = 코인. 저장 칸·Attribute 이름은 Money 그대로, 플레이어 목록(leaderstats) 칸 이름은 "코인" (글자 = 숫자만, "1.5K")
	돈·속도를 바꾸면 Attribute 와 leaderstats 도 같이 갱신됩니다.
	클라에는 돈/속도를 바꾸는 Remote 가 없습니다.
	상한: 돈 Config.MONEY_MAX, 속도 Config.SPEED_MAX (넘치지 않게 자름)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Format = require(Shared.Format)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Sessions = require(Server.Sessions)
local SpeedService = require(script.Parent.SpeedService)

local Attr = Tags.PlayerAttributes

local LEADER_COINS = "코인" -- 6판: leaderstats 칸 이름 (플레이어 목록에 보임)

local Wallet = {}

local function leaderValue(player: Player, name: string): StringValue?
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return nil
	end
	local value = stats:FindFirstChild(name)
	if value and value:IsA("StringValue") then
		return value
	end
	return nil
end

function Wallet.setupLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local money = Instance.new("StringValue")
	money.Name = LEADER_COINS
	money.Parent = folder
	local speed = Instance.new("StringValue")
	speed.Name = "Speed"
	speed.Parent = folder
	folder.Parent = player
	Wallet.syncMoney(player)
	Wallet.syncSpeed(player)
end

function Wallet.syncMoney(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	player:SetAttribute(Attr.Money, data.money)
	local value = leaderValue(player, LEADER_COINS)
	if value then
		value.Value = Format.number(data.money)
	end
end

function Wallet.syncSpeed(player: Player)
	SpeedService.refresh(player)
	local session = Sessions.get(player)
	local value = leaderValue(player, "Speed")
	if value and session then
		value.Value = Format.number(session.effectiveSpeed)
	end
end

function Wallet.addMoney(player: Player, amount: number)
	local _, data = Sessions.getLoaded(player)
	if not data or amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	data.money = math.min(Config.MONEY_MAX, data.money + amount)
	Wallet.syncMoney(player)
end

-- 돈이 충분하면 빼고 true
function Wallet.trySpend(player: Player, cost: number): boolean
	local _, data = Sessions.getLoaded(player)
	if not data or cost ~= cost or cost < 0 then
		return false
	end
	if data.money < cost then
		return false
	end
	data.money -= cost
	Wallet.syncMoney(player)
	return true
end

function Wallet.addSpeed(player: Player, amount: number)
	local _, data = Sessions.getLoaded(player)
	if not data or amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	data.speed = math.min(Config.SPEED_MAX, data.speed + amount)
	Wallet.syncSpeed(player)
end

return Wallet
