--!strict
--[[
	TutorialRules — 튜토리얼 단계 진행 규칙 (6판, 순수 로직, Lune 테스트 대상). 단계 목록·보상은 Data/Tutorial.

	advance(step, event, ctx): 일 하나가 일어난 뒤의 단계 (안 바뀌면 그대로)
	  "steal"   씨앗을 주움              1 → 2
	  "lost"    든 씨앗을 놓침           2 → 1   (잡힘·방망이·곰덫·DropEgg·죽음·치트 의심)
	  "deliver" 씨앗이 가방에 들어감     1, 2 → 3
	  "place"   씨앗을 정원에 심음       3 → 4
	  "unplace" 심은 씨앗을 다시 가방으로  4 → 3 (정원에 자라는 씨앗이 하나도 안 남았을 때만)
	  "grown"   심은 씨앗이 성체가 됨    3, 4 → 5
	  "sell"    열매를 팜 (SellFruits)   5 → DONE
	  한 단계씩만 나아감: 앞 단계 일을 건너뛰고 뒤 단계 일을 해도 그 단계가 되기 전에는 안 셈
	  (예: 1단계인데 가방에 있던 씨앗을 심어도 그대로 1단계) — "/tutorial reset" 으로 처음부터 시험할 때도 순서대로.
	normalize(step, ctx): 접속 때 저장된 단계를 지금 상태에 맞춤 (씨앗을 든 채 나갔다 오면 2 → 1 등)
	(5판 migratedStep 은 없앰 — 6판은 새 게임이라 스키마 6 마이그레이션 때 모두 1단계부터)
]]

local Data = script.Parent.Data
local Tutorial = require(Data.Tutorial)
local Format = require(script.Parent.Format)
local Types = require(script.Parent.Types)

export type Event = "steal" | "lost" | "deliver" | "place" | "unplace" | "grown" | "sell"

-- 판정에 필요한 지금 상태 (서버가 채움)
export type Context = {
	carrying: boolean, -- 지금 씨앗을 들고 있나
	bagEggs: number, -- 가방 속 씨앗 수
	placedEggs: number, -- 정원에 심어 자라는 씨앗 수
	plants: number, -- 정원의 성체 식물 수
	fruits: number, -- 열매 가방 속 열매 수
}

local TutorialRules = {}

TutorialRules.TOTAL = Tutorial.TOTAL
TutorialRules.DONE = Tutorial.DONE

function TutorialRules.isDone(step: number): boolean
	return step >= Tutorial.DONE
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
		return if step == 4 and ctx.placedEggs == 0 and ctx.plants == 0 then 3 else step
	elseif event == "grown" then
		return if step == 3 or step == 4 then 5 else step
	elseif event == "sell" then
		return if step == 5 then Tutorial.DONE else step
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
		if ctx.plants > 0 or ctx.fruits > 0 then
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
	elseif step == 5 and ctx.plants == 0 and ctx.fruits == 0 then
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
			text = "튜토리얼 끝! 보상 " .. Format.number(Tutorial.REWARD_MONEY) .. " 코인",
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

return TutorialRules
