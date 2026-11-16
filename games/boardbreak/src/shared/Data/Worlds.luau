--!strict
--[[
	Worlds — 월드 3개 (설계서 3장·4장). 순수 데이터.
	  { index, id, name, color (RGB 0~255), examiner (시험관 이름), examinerSecondsPerBoard (시험관이 송판 1장 깨는 초),
	    duelBoardHp (대결 송판 1장 체력 = 그 월드 대결 띠의 Belts.duelBoardHp), firstTarget, lastTarget (Targets index 범위) }
	시험관 속도는 플레이어 힘과 상관없음. 대결을 시작할 수 있는 힘 (대결 띠 needPower ≈ 그 월드 마지막 물건을 편하게 깨는 힘)이면
	송판 1장 = 3번 → 15장 = 45번 ≈ 11초 (초당 4번) + 카운트다운 3초. 시험관은 15장 × 1.6 / 1.4 / 1.2초 = 24 / 21 / 18초 → 넉넉히 이김.
]]

export type World = {
	index: number,
	id: string,
	name: string,
	color: { number },
	examiner: string,
	examinerSecondsPerBoard: number,
	duelBoardHp: number,
	firstTarget: number,
	lastTarget: number,
}

local list: { World } = {
	{
		index = 1,
		id = "village",
		name = "태권도장 마을",
		color = { 255, 196, 92 },
		examiner = "호랑이 사범님",
		examinerSecondsPerBoard = 1.6,
		duelBoardHp = 0, -- 아래에서 Belts 로 채움
		firstTarget = 1,
		lastTarget = 13,
	},
	{
		index = 2,
		id = "earth",
		name = "지구 한 바퀴",
		color = { 92, 196, 255 },
		examiner = "번개 관장님",
		examinerSecondsPerBoard = 1.4,
		duelBoardHp = 0,
		firstTarget = 14,
		lastTarget = 27,
	},
	{
		index = 3,
		id = "space",
		name = "우주",
		color = { 170, 120, 255 },
		examiner = "별빛 그랜드 마스터",
		examinerSecondsPerBoard = 1.2,
		duelBoardHp = 0,
		firstTarget = 28,
		lastTarget = 41,
	},
}

local Worlds = {
	list = list,
	COUNT = #list,
}

function Worlds.get(index: number): World?
	if type(index) ~= "number" or index ~= index then
		return nil
	end
	return list[index]
end

-- 대결 송판 체력 = 그 월드 대결 띠 (4·8·12) 의 duelBoardHp (Belts 가 Worlds 를 require 하지 않게 여기서 한 번)
do
	local Belts = require(script.Parent.Belts)
	for _, world in list do
		local belt = Belts.get(world.index * 4)
		world.duelBoardHp = if belt then belt.duelBoardHp else 0
	end
end

return Worlds
