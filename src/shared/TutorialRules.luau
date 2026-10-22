--!strict
--[[
	TutorialRules — 튜토리얼 단계 진행 규칙 (순수 로직, Lune 테스트 대상). 단계 목록·보상은 Data/Tutorial.

	advance(step, event, ctx): 일 하나가 일어난 뒤의 단계 (안 바뀌면 그대로)
	  "steal"   알을 주움            1 → 2
	  "lost"    든 알을 놓침         2 → 1   (잡힘·방망이·곰덫·DropEgg·죽음·치트 의심)
	  "deliver" 알이 가방에 들어감   1, 2 → 3
	  "place"   알을 우리에 놓음     3 → 4
	  "unplace" 놓은 알을 다시 가방으로  4 → 3 (우리에 놓인 알이 하나도 안 남았을 때만)
	  "hatch"   부화                 3, 4 → 5
	  "equip"   장착 (EquipPet/EquipBest) 5 → DONE (장착 펫이 1마리 이상일 때만)
	  한 단계씩만 나아감: 앞 단계 일을 건너뛰고 뒤 단계 일을 해도 그 단계가 되기 전에는 안 셈
	  (예: 1단계인데 가방에 있던 알을 놓아도 그대로 1단계) — "/tutorial reset" 으로 처음부터 시험할 때도 순서대로.
	normalize(step, ctx): 접속 때 저장된 단계를 지금 상태에 맞춤 (알을 든 채 나갔다 오면 2 → 1 등)
	migratedStep(raw): 스키마 4 → 5 마이그레이션 — 이미 놀던 사람(펫·알·통계가 있음)은 DONE, 아니면 1
]]

local Data = script.Parent.Data
local Tutorial = require(Data.Tutorial)
local Format = require(script.Parent.Format)
local Types = require(script.Parent.Types)

export type Event = "steal" | "lost" | "deliver" | "place" | "unplace" | "hatch" | "equip"

-- 판정에 필요한 지금 상태 (서버가 채움)
export type Context = {
	carrying: boolean, -- 지금 알을 들고 있나
	bagEggs: number, -- 가방 속 알 수
	placedEggs: number, -- 우리에 놓인 알 수
	pets: number, -- 보관함 펫 수
	equipped: number, -- 장착 펫 수
}

local TutorialRules = {}

TutorialRules.TOTAL = Tutorial.TOTAL
TutorialRules.DONE = Tutorial.DONE

function TutorialRules.isDone(step: number): boolean
	return step >= Tutorial.DONE
end

-- 튜토리얼 중 + 부화한 펫 자동 장착을 멈추는가 (Data/Tutorial.HOLD_AUTO_EQUIP)
function TutorialRules.holdsAutoEquip(step: number): boolean
	return Tutorial.HOLD_AUTO_EQUIP and not TutorialRules.isDone(step)
end

-- 저장된 값 → 올바른 단계 (1 ~ DONE 정수, 이상하면 fallback)
function TutorialRules.clean(value: unknown, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	local n = value :: number
	if n ~= n then
		return fallback
	end
	return math.clamp(math.floor(n), 1, Tutorial.DONE)
end

function TutorialRules.advance(step: number, event: Event, ctx: Context): number
	if TutorialRules.isDone(step) then
		return step
	end
	if event == "steal" then
		return if step == 1 then 2 else step
	elseif event == "lost" then
		return if step == 2 and not ctx.carrying then 1 else step
	elseif event == "deliver" then
		return if step <= 2 then 3 else step
	elseif event == "place" then
		return if step == 3 then 4 else step
	elseif event == "unplace" then
		return if step == 4 and ctx.placedEggs == 0 then 3 else step
	elseif event == "hatch" then
		return if step == 3 or step == 4 then 5 else step
	elseif event == "equip" then
		return if step == 5 and ctx.equipped > 0 then Tutorial.DONE else step
	end
	return step
end

-- 접속 때: 저장된 단계가 지금 상태로는 할 수 없는 단계면 할 수 있는 단계로
function TutorialRules.normalize(step: number, ctx: Context): number
	if TutorialRules.isDone(step) then
		return step
	end
	-- 지금 상태로 "어디까지 와 있나"
	local function fromState(): number
		if ctx.pets > 0 then
			return 5
		elseif ctx.placedEggs > 0 then
			return 4
		elseif ctx.bagEggs > 0 then
			return 3
		elseif ctx.carrying then
			return 2
		end
		return 1
	end
	if step == 2 and not ctx.carrying then
		return if ctx.bagEggs > 0 then 3 else 1
	elseif step == 3 and ctx.bagEggs == 0 then
		return fromState()
	elseif step == 4 and ctx.placedEggs == 0 then
		return fromState()
	elseif step == 5 and ctx.pets == 0 then
		return fromState()
	end
	return step
end

-- 클라에 보낼 모양 (TutorialUpdate / Snapshot.tutorial). reward 는 끝내는 순간에만
function TutorialRules.view(step: number, reward: number?): Types.TutorialView
	if TutorialRules.isDone(step) then
		return {
			step = Tutorial.DONE,
			total = Tutorial.TOTAL,
			text = "튜토리얼 끝! 보상 " .. Format.money(Tutorial.REWARD_MONEY),
			hint = "",
			done = true,
			reward = reward,
		}
	end
	local def = Tutorial.get(step) or Tutorial.steps[1]
	return {
		step = step,
		total = Tutorial.TOTAL,
		text = def.text,
		hint = def.hint,
		done = false,
		reward = nil,
	}
end

-- 스키마 4 → 5: 이미 놀던 사람(펫·놓인 알·가방 알이 있거나 알을 훔친 적 있음)은 튜토리얼 끝, 아니면 1단계부터
function TutorialRules.migratedStep(raw: { [string]: unknown }): number
	local function count(key: string): number
		local value = raw[key]
		if typeof(value) ~= "table" then
			return 0
		end
		return if next(value :: { [unknown]: unknown }) ~= nil then 1 else 0
	end
	if count("pets") + count("incubators") + count("eggs") > 0 then
		return Tutorial.DONE
	end
	local stats = raw.stats
	if typeof(stats) == "table" then
		for _, key in { "eggsStolen", "eggsDelivered", "eggsHatched" } do
			local n = (stats :: { [string]: unknown })[key]
			if typeof(n) == "number" and (n :: number) > 0 then
				return Tutorial.DONE
			end
		end
	end
	return 1
end

return TutorialRules
