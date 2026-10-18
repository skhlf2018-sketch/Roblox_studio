--!strict
--[[
	DevCommands — 스튜디오 테스트 전용 채팅 명령 (실서버에서는 아예 연결 안 됨: RunService:IsStudio())
	주임·선임이 뒤 구역을 바로 시험해 볼 수 있게.

	  /money 1e9        돈 더하기
	  /speed 1e9        속도 더하기
	  /skip             지금 낮/밤/대기 단계를 바로 끝냄
	  /grow             내 부화 슬롯 알을 전부 다 자란 상태로
	  /trap 5           곰덫 개수 더하기
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Server = script.Parent.Parent
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)
local Net = require(Server.Net)
local Wallet = require(script.Parent.Wallet)
local CycleService = require(script.Parent.CycleService)
local ToolService = require(script.Parent.ToolService)

local DevCommands = {}

local function handle(player: Player, message: string)
	local command, arg = string.match(message, "^/(%a+)%s*(%S*)")
	if not command then
		return
	end
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	local amount = Validate.finiteNumber(tonumber(arg)) or 0
	if command == "money" and amount > 0 then
		Wallet.addMoney(player, amount)
	elseif command == "speed" and amount > 0 then
		Wallet.addSpeed(player, amount)
	elseif command == "skip" then
		CycleService.skip()
	elseif command == "grow" then
		for _, record in data.incubators do
			record.progress = record.required
		end
		Snapshot.section(player, "incubators")
	elseif command == "trap" and amount > 0 then
		data.tools.bearTrap = (data.tools.bearTrap or 0) + math.floor(amount)
		ToolService.refreshTools(player)
		Snapshot.section(player, "tools")
	else
		return
	end
	Net.notify(player, "info", "[개발] " .. message)
end

function DevCommands.start()
	if not RunService:IsStudio() then
		return
	end
	local function hook(player: Player)
		player.Chatted:Connect(function(message: string)
			handle(player, message)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	print("[DevCommands] 스튜디오 개발 명령 켜짐: /money /speed /skip /grow /trap")
end

return DevCommands
