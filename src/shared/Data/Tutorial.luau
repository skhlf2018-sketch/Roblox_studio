--!strict
--[[
	Tutorial — 처음 온 사람 튜토리얼 5단계 (5판, 사장님 지시). 순수 데이터 — 규칙은 shared/TutorialRules.luau

	저장: data.tutorialStep = 지금 단계 번호 (1 ~ TOTAL), 다 끝나면 DONE (= TOTAL + 1)
	  1 숲에서 알 훔치기                ← 알을 주움 (EggService.pickedUp)
	  2 안전 구역으로 돌아오기          ← 알을 든 채 허브에 들어와 가방에 들어감 (BaseService.delivered)
	                                     (가는 길에 알을 놓치면 → 1 로)
	  3 핫바에서 알을 골라 우리에 놓기  ← PlaceEgg 성공 (BaseService.placed)
	  4 부화!                           ← HatchEgg 성공 (BaseService.hatched)
	                                     (놓은 알을 다시 가방으로 주워 우리가 비면 → 3 으로)
	  5 펫 장착                         ← EquipPet / EquipBest 성공, 장착 펫 1마리 이상 (PetService.equipChanged)
	  끝 → 보상 REWARD_MONEY ($500) + TutorialUpdate { done = true, reward = 500 }

	HOLD_AUTO_EQUIP [수석 결정]: 튜토리얼이 끝나기 전에는 부화한 펫을 자동 장착하지 않음
	  (원래는 빈 칸이 있으면 바로 장착 → 5단계 "펫 장착" 이 할 일이 없어짐). false 로 바꾸면 원래대로 자동 장착.
	이미 놀던 사람(스키마 4 이하 저장 데이터에 펫·알이 있음)은 마이그레이션 때 DONE (튜토리얼 안 뜸).
]]

export type Step = {
	id: string,
	text: string, -- 화면 큰 글씨 (사장님 지시 문장 그대로)
	hint: string, -- 작은 설명
}

local steps: { Step } = {
	{
		id = "steal",
		text = "숲에서 알 훔치기",
		hint = "둥지의 알 가까이에서 E 를 눌러 훔쳐요 (모바일은 버튼)",
	},
	{
		id = "return",
		text = "안전 구역으로 돌아오기",
		hint = "경비를 피해 허브(안전 구역)까지 달려요! 들어오면 알이 가방에 들어가요",
	},
	{
		id = "place",
		text = "핫바에서 알을 골라 우리에 놓기",
		hint = "알을 고른 다음 내 베이스 우리 바닥을 눌러요",
	},
	{
		id = "hatch",
		text = "부화!",
		hint = "알이 다 자라면 E 를 눌러 부화시켜요 (밤에는 30배 빨리 자라요)",
	},
	{
		id = "equip",
		text = "펫 장착",
		hint = "펫 창에서 펫을 장착해요. 장착한 펫이 매초 돈을 벌어요!",
	},
}

local Tutorial = {
	steps = steps,
	TOTAL = #steps, -- 5
	DONE = #steps + 1, -- 6 = 다 끝남
	REWARD_MONEY = 500, -- 다 끝내면 받는 돈 (사장님 지시)
	HOLD_AUTO_EQUIP = true,
}

function Tutorial.get(step: number): Step?
	return steps[step]
end

return Tutorial
