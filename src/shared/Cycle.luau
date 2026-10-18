--!strict
--[[
	Cycle — 낮/밤/대기 상태 기계 (순수 로직, 서버/클라 공용)
	  낮 285초 → 밤 10초 → 대기 3초 → 낮 ... (설계문서 2장)
]]

local Config = require(script.Parent.Data.Config)
local Types = require(script.Parent.Types)

type Phase = Types.Phase

local Cycle = {}

Cycle.ORDER = { "Day", "Night", "Intermission" } :: { Phase }

export type Durations = {
	Day: number,
	Night: number,
	Intermission: number,
}

function Cycle.defaultDurations(): Durations
	return {
		Day = Config.DAY_SECONDS,
		Night = Config.NIGHT_SECONDS,
		Intermission = Config.INTERMISSION_SECONDS,
	}
end

function Cycle.duration(phase: Phase, durations: Durations?): number
	local d = durations or Cycle.defaultDurations()
	if phase == "Day" then
		return d.Day
	elseif phase == "Night" then
		return d.Night
	end
	return d.Intermission
end

function Cycle.nextPhase(phase: Phase): Phase
	if phase == "Day" then
		return "Night"
	elseif phase == "Night" then
		return "Intermission"
	end
	return "Day"
end

function Cycle.totalLength(durations: Durations?): number
	local d = durations or Cycle.defaultDurations()
	return d.Day + d.Night + d.Intermission
end

-- 경과 시간으로 지금 상태 계산 (cycleStart 기준 elapsed 초). (phase, 남은 초)
function Cycle.phaseAt(elapsed: number, durations: Durations?): (Phase, number)
	local d = durations or Cycle.defaultDurations()
	local t = elapsed % Cycle.totalLength(d)
	if t < d.Day then
		return "Day", d.Day - t
	end
	t -= d.Day
	if t < d.Night then
		return "Night", d.Night - t
	end
	t -= d.Night
	return "Intermission", d.Intermission - t
end

function Cycle.canStealEggs(phase: Phase): boolean
	return phase == "Day"
end

function Cycle.isNight(phase: Phase): boolean
	return phase == "Night"
end

return Cycle
