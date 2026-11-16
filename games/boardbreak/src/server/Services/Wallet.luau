--!strict
--[[
	Wallet — 힘·돈 숫자를 바꾸는 유일한 통로 (서버 전용, 첫 게임 Wallet 을 송판 깨기에 맞춤)
	바꾸면 Attribute(Power · Money)와 플레이어 목록(leaderstats "힘" · "돈", 글자 = "1.5K")도 같이 갱신.
	클라에는 힘·돈을 바꾸는 Remote 가 없습니다. 상한 1e60 (Economy.clampPower / clampMoney — NaN·무한·음수 막음)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Sessions = require(Server.Sessions)

local Attr = Tags.PlayerAttributes

local LEADER_POWER = "힘"
local LEADER_MONEY = "돈"

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
	local power = Instance.new("StringValue")
	power.Name = LEADER_POWER
	power.Parent = folder
	local money = Instance.new("StringValue")
	money.Name = LEADER_MONEY
	money.Parent = folder
	folder.Parent = player
	Wallet.sync(player)
end

-- Attribute · leaderstats 를 저장 데이터에 맞춤
function Wallet.sync(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	player:SetAttribute(Attr.Power, data.power)
	player:SetAttribute(Attr.Money, data.money)
	local power = leaderValue(player, LEADER_POWER)
	if power then
		power.Value = Format.number(data.power)
	end
	local money = leaderValue(player, LEADER_MONEY)
	if money then
		money.Value = Format.number(data.money)
	end
end

function Wallet.addMoney(player: Player, amount: number): number
	local _, data = Sessions.getLoaded(player)
	if not data then
		return 0
	end
	local before = data.money
	data.money = Economy.addMoney(data.money, amount)
	Wallet.sync(player)
	return data.money - before
end

-- 돈이 충분하면 빼고 true
function Wallet.trySpend(player: Player, cost: number): boolean
	local _, data = Sessions.getLoaded(player)
	if not data or type(cost) ~= "number" or cost ~= cost or cost < 0 or cost == math.huge then
		return false
	end
	if data.money < cost then
		return false
	end
	data.money = Economy.clampMoney(data.money - cost)
	Wallet.sync(player)
	return true
end

function Wallet.addPower(player: Player, amount: number): number
	local _, data = Sessions.getLoaded(player)
	if not data then
		return 0
	end
	local before = data.power
	data.power = Economy.addPower(data.power, amount)
	Wallet.sync(player)
	return data.power - before
end

-- 개발 명령·불러오기용: 그대로 정함 (범위만 맞춤)
function Wallet.set(player: Player, power: number?, money: number?)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	if power ~= nil then
		data.power = Economy.clampPower(power)
	end
	if money ~= nil then
		data.money = Economy.clampMoney(money)
	end
	Wallet.sync(player)
end

return Wallet
