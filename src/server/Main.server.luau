--!strict
--[[
	서버 진입점 (ServerScriptService.Server.Main — Script, RunContext = Server)
	팀 표준: 진입점은 이것 하나. 나머지는 전부 ModuleScript + start().
	시작 순서가 중요합니다 (위에서 아래로). CycleService.run() 은 모두가 구독한 뒤 맨 마지막.
]]

local Server = script.Parent
local Services = Server.Services

local Net = require(Server.Net)
local MapBuilder = require(Services.MapBuilder)
local DataService = require(Services.DataService)
local SpeedService = require(Services.SpeedService)
local CycleService = require(Services.CycleService)
local EggService = require(Services.EggService)
local GuardianService = require(Services.GuardianService)
local PetService = require(Services.PetService)
local IndexService = require(Services.IndexService)
local BaseService = require(Services.BaseService)
local IncomeService = require(Services.IncomeService)
local UpgradeService = require(Services.UpgradeService)
local ToolService = require(Services.ToolService)
local RewardService = require(Services.RewardService)
local DevCommands = require(Services.DevCommands)
local PlayerLifecycle = require(Services.PlayerLifecycle)

Net.start()
MapBuilder.start()
DataService.start()
SpeedService.start()
CycleService.start()
EggService.start()
GuardianService.start()
PetService.start()
IndexService.start()
BaseService.start()
IncomeService.start()
UpgradeService.start()
ToolService.start()
RewardService.start()
DevCommands.start()
PlayerLifecycle.start()
CycleService.run()

print("[StealAnEgg] 서버 시작 완료")
