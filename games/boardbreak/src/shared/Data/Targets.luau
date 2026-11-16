--!strict
--[[
	Targets — 깰 물건 41개 (설계서 3장 표 + 9장 숫자 표). 순수 데이터.
	  { id, index, name, world, reward, hp, recommendPower, minPower }
	  reward         = 한 번 깼을 때 받는 돈 (띠 배율 · 돈 2배 패스 전). 솜 3 에서 시작해 이웃끼리 5~10배 (사장님 결정 10번)
	  hp             = 물건 체력 (한 번 칠 때 내 힘(× 힘 배수)만큼 깎임, 플레이어마다 따로 · 세션 동안 남음)
	  recommendPower = 추천 힘 (화면 표시용만 — 힘 문턱은 없음, 사장님 결정 11번). 이 힘이면 15번에 깸
	  minPower       = recommendPower 의 옛 이름 (선임 화면이 recommendPower 로 바꾸면 지움). 판정에는 안 씀
	숫자 규칙 (설계서 6장): hp = 추천 힘 × 14.2 (추천 힘이면 15번) · 이웃 물건의 추천 힘·hp 는 5~10배,
	그리고 이웃 hp 배율 ≥ 이웃 reward 배율 (약한 힘으로 뒤 물건을 오래 치는 것이 지름길이 안 되게).
]]

export type Target = {
	id: string,
	index: number,
	name: string,
	world: number,
	reward: number,
	hp: number,
	recommendPower: number,
	minPower: number,
}

-- { id, 이름, 월드, 값, 추천 힘, hp } — 추천 힘·hp 는 tests/tune_numbers.luau 로 만들고 sim_progress 로 검사 (설계서 9장)
local ROWS: { { any } } = {
	{ "cotton", "솜", 1, 3, 5, 71 },
	{ "glass", "유리", 1, 20, 49, 696 },
	{ "plastic", "플라스틱", 1, 150, 482, 6850 },
	{ "wood", "나무 송판", 1, 1000, 4740, 6.74e4 },
	{ "iron", "철", 1, 8000, 4.68e4, 6.65e5 },
	{ "steel", "강철", 1, 5e4, 4.56e5, 6.48e6 },
	{ "rubber", "고무", 1, 4e5, 4.44e6, 6.31e7 },
	{ "computer", "컴퓨터", 1, 3e6, 4.33e7, 6.15e8 },
	{ "phone", "핸드폰", 1, 2e7, 4.21e8, 5.98e9 },
	{ "overpass", "육교", 1, 1.5e8, 4.09e9, 5.81e10 },
	{ "apartment", "아파트", 1, 1e9, 3.09e10, 4.39e11 },
	{ "school", "학교", 1, 8e9, 3e11, 4.26e12 },
	{ "stadium", "경기장", 1, 5e10, 2.6e12, 3.7e13 },
	{ "mall", "백화점", 2, 4e11, 2.53e13, 3.6e14 },
	{ "skyscraper", "고층 빌딩", 2, 3e12, 2.46e14, 3.5e15 },
	{ "bridge", "대교", 2, 2e13, 2.4e15, 3.41e16 },
	{ "dam", "댐", 2, 1.5e14, 2.34e16, 3.33e17 },
	{ "airplane", "비행기", 2, 1e15, 2.27e17, 3.23e18 },
	{ "carrier", "항공모함", 2, 8e15, 2.21e18, 3.14e19 },
	{ "tower", "전망탑", 2, 5e16, 1.82e19, 2.59e20 },
	{ "pyramid", "피라미드", 2, 4e17, 1.77e20, 2.52e21 },
	{ "mountain", "산", 2, 3e18, 1.58e21, 2.25e22 },
	{ "volcano", "화산", 2, 2e19, 1.54e22, 2.19e23 },
	{ "glacier", "빙하", 2, 1.5e20, 1.5e23, 2.13e24 },
	{ "island", "섬", 2, 1e21, 1.46e24, 2.08e25 },
	{ "continent", "대륙", 2, 8e21, 1.42e25, 2.02e26 },
	{ "ocean", "바다", 2, 5e22, 1.39e26, 1.98e27 },
	{ "moon", "달", 3, 4e23, 1.15e27, 1.64e28 },
	{ "mercury", "수성", 3, 3e24, 1.12e28, 1.6e29 },
	{ "mars", "화성", 3, 2e25, 1.09e29, 1.55e30 },
	{ "venus", "금성", 3, 1.5e26, 1.06e30, 1.51e31 },
	{ "earth", "지구", 3, 1e27, 1.03e31, 1.47e32 },
	{ "neptune", "해왕성", 3, 8e27, 8.49e31, 1.21e33 },
	{ "uranus", "천왕성", 3, 5e28, 8.26e32, 1.18e34 },
	{ "saturn", "토성", 3, 4e29, 7.39e33, 1.05e35 },
	{ "jupiter", "목성", 3, 3e30, 7.19e34, 1.03e36 },
	{ "sun", "태양", 3, 2e31, 6.89e35, 9.79e36 },
	{ "solar_system", "태양계", 3, 1.5e32, 6.69e36, 9.5e37 },
	{ "galaxy", "은하", 3, 1e33, 6.5e37, 9.23e38 },
	{ "black_hole", "블랙홀", 3, 8e33, 6.32e38, 8.98e39 },
	{ "universe", "우주", 3, 5e34, 6.14e39, 8.72e40 },
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
		recommendPower = row[5],
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
