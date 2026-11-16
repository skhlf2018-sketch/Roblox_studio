--!strict
--[[
	Attributes — 플레이어 Attribute 를 저장 데이터·세션에 맞추는 한 곳 (설계서 7장 이름 = Tags.PlayerAttributes)
	  Power · Money (Wallet.sync) · DumbbellLevel · Belt · World · CurrentWorld · PowerBoost · MoneyPass · Activity · GrandMaster
	DataLoaded · SaveEnabled 는 PlayerLifecycle 이 접속 때 정함.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tags = require(ReplicatedStorage.Shared.Tags)
local Sessions = require(script.Parent.Sessions)
local Wallet = require(script.Parent.Services.Wallet)

local Attr = Tags.PlayerAttributes

local Attributes = {}

function Attributes.sync(player: Player)
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	Wallet.sync(player)
	player:SetAttribute(Attr.DumbbellLevel, data.dumbbellLevel)
	player:SetAttribute(Attr.Belt, data.belt)
	player:SetAttribute(Attr.World, data.world)
	player:SetAttribute(Attr.CurrentWorld, session.currentWorld)
	player:SetAttribute(Attr.PowerBoost, data.powerBoost)
	player:SetAttribute(Attr.MoneyPass, data.moneyPass)
	player:SetAttribute(Attr.GrandMaster, data.grandMaster)
	player:SetAttribute(Attr.Activity, Sessions.activity(session))
end

function Attributes.setActivity(player: Player)
	local session = Sessions.get(player)
	if session then
		player:SetAttribute(Attr.Activity, Sessions.activity(session))
	end
end

return Attributes
