--!strict
--[[
	클라 진입점 (ReplicatedStorage.Client.Main — Script, RunContext = Client)
	팀 표준: 진입점은 이것 하나. 나머지는 ModuleScript + start().
	UI 는 선임이 Controllers 에 추가합니다 (State.onChanged / Net.on 사용, docs/REMOTES.md 참고).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Client = script.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Controllers = Client.Controllers
local DebugController = require(Controllers.DebugController)
local AnnounceController = require(Controllers.AnnounceController)
local RagdollController = require(Controllers.RagdollController)
local ToolController = require(Controllers.ToolController)

State.start()
DebugController.start()
AnnounceController.start()
RagdollController.start()
task.spawn(ToolController.start)

-- 접속 직후 서버가 보낸 Snapshot 을 놓쳤을 수 있으니 한 번 요청
Net.send(Remotes.ToServer.RequestSnapshot)

print("[StealAnEgg] 클라이언트 시작 완료")
