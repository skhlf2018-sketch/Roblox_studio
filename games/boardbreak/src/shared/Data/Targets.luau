--!strict
--[[
	Targets — 깰 물건 41개 (설계서 3장 표 + 9장 숫자 표). 순수 데이터.
	  { id, index, name, world, reward, hp, minPower }
	  reward   = 한 번 깼을 때 받는 돈 (띠 배율 · 돈 2배 패스 전)
	  hp       = 물건 체력 (한 번 칠 때 내 힘(× 힘 배수)만큼 깎임, 플레이어마다 따로)
	  minPower = 깰 수 있는 힘 (치는 힘이 이보다 작으면 "힘이 부족해요" — 체력이 안 깎임)
	숫자 규칙 (설계서 6장): 막 열렸을 때 (힘 = minPower) 15~30번 → hp = minPower × 15~30.
]]

export type Target = {
	id: string,
	index: number,
	name: string,
	world: number,
	reward: number,
	hp: number,
	minPower: number,
}

-- { id, 이름, 월드, 값, minPower, hp } — 숫자는 tests/sim_progress.luau 로 맞춘 것 (설계서 9장)
local ROWS: { { any } } = {
	{ "cotton", "솜", 1, 3, 5, 75 },
	{ "glass", "유리", 1, 10, 161, 2420 },
	{ "plastic", "플라스틱", 1, 20, 1.23e4, 1.85e5 },
	{ "wood", "나무 송판", 1, 50, 1.22e6, 1.83e7 },
	{ "iron", "철", 1, 128, 7.22e6, 1.09e8 },
	{ "steel", "강철", 1, 256, 1.33e8, 2e9 },
	{ "rubber", "고무", 1, 1024, 7.74e8, 1.17e10 },
	{ "computer", "컴퓨터", 1, 8192, 1.36e10, 2.04e11 },
	{ "phone", "핸드폰", 1, 32768, 7.77e10, 1.17e12 },
	{ "overpass", "육교", 1, 524288, 1.36e12, 2.04e13 },
	{ "apartment", "아파트", 1, 1000000, 7.77e12, 1.17e14 },
	{ "school", "학교", 1, 4e6, 1.36e14, 2.04e15 },
	{ "stadium", "경기장", 1, 16e6, 7.77e14, 1.17e16 },
	{ "mall", "백화점", 2, 64e6, 1.7e16, 2.55e17 },
	{ "skyscraper", "고층 빌딩", 2, 256e6, 9.95e16, 1.5e18 },
	{ "bridge", "대교", 2, 1e9, 1.71e18, 2.57e19 },
	{ "dam", "댐", 2, 4e9, 1.01e19, 1.52e20 },
	{ "airplane", "비행기", 2, 16e9, 1.96e20, 2.94e21 },
	{ "carrier", "항공모함", 2, 64e9, 1.13e21, 1.7e22 },
	{ "tower", "전망탑", 2, 256e9, 2.02e22, 3.03e23 },
	{ "pyramid", "피라미드", 2, 1e12, 1.14e23, 1.71e24 },
	{ "mountain", "산", 2, 4e12, 2.02e24, 3.03e25 },
	{ "volcano", "화산", 2, 16e12, 1.14e25, 1.71e26 },
	{ "glacier", "빙하", 2, 64e12, 2.02e26, 3.03e27 },
	{ "island", "섬", 2, 256e12, 1.14e27, 1.71e28 },
	{ "continent", "대륙", 2, 1e15, 2.02e28, 3.03e29 },
	{ "ocean", "바다", 2, 4e15, 1.14e29, 1.71e30 },
	{ "moon", "달", 3, 16e15, 5.86e29, 1.06e31 },
	{ "mercury", "수성", 3, 64e15, 1.72e31, 3.1e32 },
	{ "mars", "화성", 3, 256e15, 1.18e32, 2.13e33 },
	{ "venus", "금성", 3, 1e18, 2.13e33, 3.84e34 },
	{ "earth", "지구", 3, 4e18, 1.42e34, 2.56e35 },
	{ "neptune", "해왕성", 3, 16e18, 2.22e35, 4e36 },
	{ "uranus", "천왕성", 3, 64e18, 1.47e36, 2.65e37 },
	{ "saturn", "토성", 3, 256e18, 2.26e37, 4.07e38 },
	{ "jupiter", "목성", 3, 1e21, 1.5e38, 2.7e39 },
	{ "sun", "태양", 3, 4e21, 9.14e38, 1.65e40 },
	{ "solar_system", "태양계", 3, 16e21, 2.1e40, 3.78e41 },
	{ "galaxy", "은하", 3, 64e21, 1.41e41, 2.54e42 },
	{ "black_hole", "블랙홀", 3, 256e21, 2.22e42, 4e43 },
	{ "universe", "우주", 3, 1e24, 1.47e43, 2.65e44 },
}

local list: { Target } = {}
local byId: { [string]: Target } = {}
local worldLists: { [number]: { Target } } = {}

for index, row in ROWS do
	local target: Target = {
		id = row[1],
		index = index,
		name = row[2],
		world = row[3],
		reward = row[4],
		minPower = row[5],
		hp = row[6],
	}
	table.insert(list, target)
	byId[target.id] = target
	local group = worldLists[target.world]
	if not group then
		group = {}
		worldLists[target.world] = group
	end
	table.insert(group, target)
end

local Targets = {
	list = list,
	COUNT = #list,
}

function Targets.get(id: string): Target?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

-- 그 월드 물건 (표 순서). 없는 월드면 빈 표
function Targets.byWorld(world: number): { Target }
	return worldLists[world] or {}
end

return Targets
