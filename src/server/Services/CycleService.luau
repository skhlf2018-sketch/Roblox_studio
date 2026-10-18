--!strict
--[[
	CycleService — 낮 285초 → 밤 10초 → 대기 3초 반복 (서버 시계 기준)

	- 상태는 ReplicatedStorage.GameState 폴더의 Attribute 로 복제:
	    Phase, PhaseEndsAt(workspace:GetServerTimeNow() 기준), PhaseDuration, CycleNumber, HeavenSide
	  + PhaseChanged Remote 로도 알림 (소리·연출용)
	- 밤/대기에는 구역 입구 벽을 켭니다 (MapBuilder.setNightWalls).
	- 다른 서비스는 CycleService.changed:connect(function(phase, cycleNumber) ... end) 로 구독:
	    EggService  → "Intermission" 에서 모든 둥지 알 재생성 + 공지 + 희귀 알 추첨
	    BaseService → "Night" 에서 알 든 사람을 베이스로 텔레포트
	- 서버 시작 직후 대기(Intermission)부터 시작 → 첫 알이 같은 경로로 놓임.

	스튜디오 테스트: Workspace 에 숫자 Attribute "DebugDaySeconds" 를 넣으면 낮 길이를 바꿀 수 있음 (스튜디오에서만).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Biomes = require(Shared.Data.Biomes)
local Cycle = require(Shared.Cycle)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Signal = require(Server.Util.Signal)
local MapBuilder = require(script.Parent.MapBuilder)

type Phase = Types.Phase

local StateAttr = Tags.StateAttributes

local CycleService = {}

CycleService.changed = Signal.new()

local phase: Phase = "Intermission"
local cycleNumber = 1
local stateFolder: Folder? = nil
local skipRequested = false
local running = false

function CycleService.getPhase(): Phase
	return phase
end

function CycleService.getCycleNumber(): number
	return cycleNumber
end

function CycleService.isNight(): boolean
	return phase == "Night"
end

-- 천사&악마처럼 쪽이 있는 구역의 이번 주기 쪽
function CycleService.sideFor(biomeId: string): string?
	local biome = Biomes.get(biomeId)
	if not biome then
		return nil
	end
	return Biomes.sideForCycle(biome, cycleNumber)
end

-- 개발용: 지금 단계를 바로 끝냄 (DevCommands)
function CycleService.skip()
	skipRequested = true
end

local function durationOf(p: Phase): number
	if p == "Day" and RunService:IsStudio() then
		local debugSeconds = Workspace:GetAttribute("DebugDaySeconds")
		if typeof(debugSeconds) == "number" and debugSeconds > 0 then
			return debugSeconds
		end
	end
	return Cycle.duration(p)
end

local function applyPhase(p: Phase): number
	phase = p
	local duration = durationOf(p)
	local endsAt = Workspace:GetServerTimeNow() + duration
	local ad = Biomes.get("angels_demons")
	local heavenSide = if ad then Biomes.sideForCycle(ad, cycleNumber) else nil

	local folder = stateFolder
	if folder then
		folder:SetAttribute(StateAttr.Phase, p)
		folder:SetAttribute(StateAttr.PhaseEndsAt, endsAt)
		folder:SetAttribute(StateAttr.PhaseDuration, duration)
		folder:SetAttribute(StateAttr.CycleNumber, cycleNumber)
		folder:SetAttribute(StateAttr.HeavenSide, heavenSide or "")
	end

	MapBuilder.setNightWalls(p ~= "Day")
	Lighting.ClockTime = if p == "Day" then Config.DAY_CLOCK_TIME elseif p == "Night" then Config.NIGHT_CLOCK_TIME else 6

	Net.fireAll(Remotes.ToClient.PhaseChanged, {
		phase = p,
		endsAt = endsAt,
		duration = duration,
		cycleNumber = cycleNumber,
		heavenSide = heavenSide,
	})
	if p == "Night" then
		Net.fireAll(Remotes.ToClient.Announce, {
			kind = "night",
			text = "밤이 됐어요! 구역 입구가 닫혔어요. 알이 30배 빨리 자라요!",
		})
	elseif p == "Day" then
		Net.fireAll(Remotes.ToClient.Announce, { kind = "day", text = "아침이에요! 알을 훔치러 가요!" })
	end

	CycleService.changed:fire(p, cycleNumber)
	return duration
end

function CycleService.start()
	local folder = Instance.new("Folder")
	folder.Name = Tags.StateFolderName
	folder.Parent = ReplicatedStorage
	stateFolder = folder
end

-- 모든 서비스가 changed 를 구독한 뒤에 호출 (Main 에서 맨 마지막)
function CycleService.run()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while true do
			local duration = applyPhase(phase)
			local deadline = os.clock() + duration
			while os.clock() < deadline and not skipRequested do
				task.wait(0.2)
			end
			skipRequested = false
			local nextPhase = Cycle.nextPhase(phase)
			if nextPhase == "Intermission" then
				cycleNumber += 1
			end
			phase = nextPhase
		end
	end)
end

return CycleService
