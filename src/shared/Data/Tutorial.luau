--!strict
--[[
	Tutorial — 처음 온 사람 튜토리얼 5단계 (6판 "씨앗을 훔치세요", 사장님 문장). 순수 데이터 — 규칙은 shared/TutorialRules.luau

	저장: data.tutorialStep = 지금 단계 번호 (1 ~ TOTAL), 다 끝나면 DONE (= TOTAL + 1)
	  1 숲에서 씨앗 훔치기                    ← 씨앗을 주움 (EggService.pickedUp)
	  2 안전 구역으로 돌아오기                ← 씨앗을 든 채 허브에 들어와 가방에 들어감 (BaseService.delivered)
	                                            (가는 길에 씨앗을 놓치면 → 1 로)
	  3 핫바에서 씨앗을 골라 정원에 심기      ← PlaceEgg 성공 (BaseService.placed)
	  4 성체가 될 때까지 기다리기             ← 심은 씨앗이 성체가 됨 (BaseService.grown). 강아지풀 씨앗은 1초 (7판: 표 3초 ÷ 성장 3배)
	                                            (심은 씨앗을 다시 가방으로 주워 정원에 자라는 씨앗이 없으면 → 3 으로)
	  5 열매 따서 팔기                        ← SellFruits 로 열매를 1개 이상 팜 (FruitService.sold)
	                                            (성체가 되는 순간 열매가 Config.FRUITS_ON_ADULT(1)개 달려 있어 바로 할 수 있음)
	  끝 → 보상 REWARD_MONEY (500 코인) + TutorialUpdate { done = true, reward = 500 }
	6판은 새 게임이라 옛 데이터를 가진 사람도 스키마 6 마이그레이션 때 1단계부터 (DataSchema).
]]

export type Step = {
	id: string,
	text: string, -- 화면 큰 글씨 (사장님 지시 문장 그대로)
	hint: string, -- 작은 설명
}

local steps: { Step } = {
	{
		id = "steal",
		text = "숲에서 씨앗 훔치기",
		hint = "둥지의 씨앗 가까이에서 E 를 눌러 훔쳐요 (모바일은 버튼)",
	},
	{
		id = "return",
		text = "안전 구역으로 돌아오기",
		hint = "식물 괴물을 피해 허브(안전 구역)까지 달려요! 들어오면 씨앗이 가방에 들어가요",
	},
	{
		id = "place",
		text = "핫바에서 씨앗을 골라 정원에 심기",
		hint = "씨앗을 고른 다음 내 정원 바닥을 눌러요",
	},
	{
		id = "grow",
		text = "성체가 될 때까지 기다리기",
		hint = "새싹 → 줄기 → 봉오리 → 성체! 강아지풀 씨앗은 1초면 돼요 (밤에는 30배 빨리 자라요)",
	},
	{
		id = "fruit",
		text = "열매 따서 팔기",
		hint = "성체에 달린 열매를 따서 판매 가판대에서 팔면 코인을 받아요!",
	},
}

local Tutorial = {
	steps = steps,
	TOTAL = #steps, -- 5
	DONE = #steps + 1, -- 6 = 다 끝남
	REWARD_MONEY = 500, -- 다 끝내면 받는 코인 (사장님 지시)
}

function Tutorial.get(step: number): Step?
	return steps[step]
end

return Tutorial
