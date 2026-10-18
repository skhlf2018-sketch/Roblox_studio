--!nocheck
--[[
	sim_progress — 밸런스 1차 시뮬레이션 (테스트가 아니라 리포트 출력)
	  lune run tests/sim_progress.luau            기본 리포트 (구역별 추천 속도 도달 시간)
	  lune run tests/sim_progress.luau sweep      러닝머신 배율을 바꿔 가며 8·13·15구역 도달 시간 비교
	  lune run tests/sim_progress.luau whatif     (참고) 도감 속도 보상 공식의 지수를 바꾸면? — 게임 코드는 안 바뀜

	2단계 결과 요약 (러닝머신 배율 3):
	  도감 속도 보상이 추천 속도에 정비례(지수 1)일 때는 한 구역 펫 몇 마리만 발견해도 다음 구역이 열려서
	  9~15구역이 1시간 안에 연달아 열렸음 (15구역 ≈ 7시간). 러닝머신 배율은 1~48 어디로 바꿔도 이 모양은 안 바뀜.
	  → 본부장 결정: 지수 0.8 (Index.SPEED_BIOME_EXPONENT), 러닝머신 배율 3 유지.
	  whatif 모드는 이 실행 안에서만 Index.SPEED_BIOME_EXPONENT 를 바꿔 봄 (파일은 안 바뀜).

	게임 코드(Config·Economy·Upgrades·Pets·EggRoll·Index ...)를 Loader 로 그대로 불러 씁니다.
	→ Config 숫자를 바꾸면 이 리포트도 바로 바뀜.

	플레이어 모델 ("러닝머신 위에서 쉬지 않고, 돈은 전부 업그레이드에" 반방치 플레이어):
	  - 시간의 100% 를 러닝머신 위에서 보냄 (1초마다 Economy.treadmillGainPerSecond)
	  - 매 낮/밤 주기(298초)마다 알을 TRIPS_PER_CYCLE 개만 훔쳐 옴 (왕복 시간은 무시 = 러닝머신 손실 없음)
	      어느 구역: 보통 알(-10%)을 들고도 경비보다 빠른 가장 뒤 구역
	      어떤 알: 그 구역 둥지 8개(일반 추첨 + 초기화 특별 알) 중 들고 도망칠 수 있는 알,
	              도감에 없는 펫 우선 → 수입이 가장 높은 알
	  - 부화 슬롯 8칸, 부화 시간 ÷3, 밤 30배. 다 자라면 바로 부화 → 장착 칸만큼 수입 높은 펫 장착
	  - 도감 보상은 발견 즉시 받음 (속도 + 돈). 무료 보상 +10,000 속도는 시작할 때 받음.
	  - 돈이 생기면 살 수 있는 업그레이드(러닝머신 다음 레벨 / 다음 트레일 / 우리 다음 레벨) 중 가장 싼 것부터 계속 삼
	  - 퓨전·제단·사쿠라·다른 플레이어 방해는 넣지 않음
	"도달" = 실효 속도(모은 속도 × 트레일) ≥ 구역 추천 속도
	두 번째 열 "러닝머신만" = 같은 플레이어인데 도감 속도 보상을 빼고 (러닝머신 + 트레일만으로 속도를 모을 때)
]]

local process = require("@lune/process")
local Loader = require("./Loader")

local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
local Upgrades = Loader.require("ReplicatedStorage/Shared/Data/Upgrades")
local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
local Index = Loader.require("ReplicatedStorage/Shared/Data/Index")
local EggRoll = Loader.require("ReplicatedStorage/Shared/EggRoll")
local Cycle = Loader.require("ReplicatedStorage/Shared/Cycle")
local Format = Loader.require("ReplicatedStorage/Shared/Format")

local HOURS = 100
local SEEDS = 9
local TRIPS_PER_CYCLE = 1
local KEEP_PETS = 40 -- 장착 후보로 기억할 펫 수 (수입 상위)

local TARGETS = {
	{ order = 8, low = 3, high = 5 },
	{ order = 13, low = 20, high = 30 },
	{ order = 15, low = 40, high = 60 },
}

local function makeRng(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

local NORMAL_PENALTY = Sizes.get("normal").speedPenalty

-- 도감 보상은 게임 코드 Index.reward 그대로 (whatif 모드는 Index.SPEED_BIOME_EXPONENT 를 잠깐 바꿔 봄)
local function indexReward(pet, biome)
	return Index.reward(pet.rarity, pet.income, biome.recommendedSpeed)
end

local function simulate(seed, indexSpeed)
	local rand = makeRng(seed)
	local money = Config.STARTING_MONEY
	local base = Config.STARTING_SPEED + Config.FREE_REWARD_SPEED
	local tread = 0
	local trailIndex = 0
	local trailMult = 1
	local pen = 1
	local pets = {} -- { income }
	local income = 0
	local incubators = {}
	local discovered = {}
	local reach = {}
	local nextZone = 1
	local cycleLen = Cycle.totalLength()
	local dayLen = Config.DAY_SECONDS
	local nightEnd = dayLen + Config.NIGHT_SECONDS
	local cycleNumber = 0
	local tripTimes = {}
	for k = 1, TRIPS_PER_CYCLE do
		tripTimes[math.floor(k * dayLen / (TRIPS_PER_CYCLE + 1))] = true
	end
	local cheapest = math.huge

	local function effective()
		return base * trailMult
	end

	local function recalc()
		table.sort(pets, function(a, b)
			return a > b
		end)
		while #pets > KEEP_PETS do
			table.remove(pets)
		end
		local slots = Economy.penSlots(pen)
		income = 0
		for i = 1, math.min(slots, #pets) do
			income += pets[i]
		end
	end

	local function nextCosts()
		local t = Economy.nextTreadmillCost(tread)
		local trail = Upgrades.Trails[trailIndex + 1]
		local p = Economy.nextPenCost(pen)
		return t, if trail then trail.cost else nil, p
	end

	local function refreshCheapest()
		local a, b, c = nextCosts()
		cheapest = math.min(a or math.huge, b or math.huge, c or math.huge)
	end

	local function buy()
		while true do
			local t, tr, p = nextCosts()
			local best, kind = math.huge, nil
			if t and t < best then
				best, kind = t, "t"
			end
			if tr and tr < best then
				best, kind = tr, "tr"
			end
			if p and p < best then
				best, kind = p, "p"
			end
			if not kind or best > money then
				break
			end
			money -= best
			if kind == "t" then
				tread += 1
			elseif kind == "tr" then
				trailIndex += 1
				trailMult = math.max(trailMult, Upgrades.Trails[trailIndex].multiplier)
			else
				pen += 1
				recalc()
			end
		end
		refreshCheapest()
	end

	local function zoneFor()
		local zone = Biomes.list[1]
		for _, biome in Biomes.list do
			if effective() * (1 - NORMAL_PENALTY) >= biome.recommendedSpeed then
				zone = biome
			end
		end
		return zone
	end

	local function trip()
		if #incubators >= Config.INCUBATOR_SLOTS then
			return
		end
		local biome = zoneFor()
		local side = Biomes.sideForCycle(biome, cycleNumber)
		local eggs = {}
		for _ = 1, biome.nests do
			local pet = EggRoll.rollNestPet(biome.id, side, rand)
			if pet then
				table.insert(eggs, { pet = pet, traits = EggRoll.rollTraits(rand) })
			end
		end
		for _, pet in EggRoll.rollSpecials(biome.id, side, rand) do
			table.insert(eggs, { pet = pet, traits = EggRoll.rollTraits(rand) })
		end
		local best, bestNew, bestValue = nil, false, -1
		for _, egg in eggs do
			local size = Sizes.get(egg.traits.size)
			if effective() * (1 - size.speedPenalty) >= biome.recommendedSpeed then
				local value = Economy.petIncome(egg.pet.id, egg.traits.size, egg.traits.mutations)
				local isNew = not discovered[egg.pet.id]
				if (isNew and not bestNew) or (isNew == bestNew and value > bestValue) then
					best, bestNew, bestValue = egg, isNew, value
				end
			end
		end
		if best then
			table.insert(incubators, {
				pet = best.pet,
				income = Economy.petIncome(best.pet.id, best.traits.size, best.traits.mutations),
				progress = 0,
				required = Economy.hatchSeconds(best.pet.id),
			})
		end
	end

	local function hatch(egg)
		table.insert(pets, egg.income)
		recalc()
		if not discovered[egg.pet.id] then
			discovered[egg.pet.id] = true
			local reward = indexReward(egg.pet, Biomes.get(egg.pet.biome))
			if indexSpeed then
				base += reward.speed
			end
			money += reward.money
		end
	end

	refreshCheapest()
	local total = HOURS * 3600
	for t = 0, total - 1 do
		local phaseT = t % cycleLen
		if phaseT == 0 then
			cycleNumber += 1
		end
		if tripTimes[phaseT] then
			trip()
		end
		if tread >= 1 then
			base += Economy.treadmillGainPerSecond(tread)
		end
		money += income
		if #incubators > 0 then
			local rate = if phaseT >= dayLen and phaseT < nightEnd then Config.NIGHT_GROWTH_MULTIPLIER else 1
			for i = #incubators, 1, -1 do
				local egg = incubators[i]
				egg.progress += rate
				if egg.progress >= egg.required then
					table.remove(incubators, i)
					hatch(egg)
				end
			end
		end
		if money >= cheapest then
			buy()
		end
		while nextZone <= #Biomes.list and effective() >= Biomes.list[nextZone].recommendedSpeed do
			reach[nextZone] = t
			nextZone += 1
		end
		if nextZone > #Biomes.list then
			break
		end
	end
	return reach, { tread = tread, trail = trailMult, pen = pen, speed = effective(), income = income }
end

local function median(values)
	local sorted = table.clone(values)
	table.sort(sorted)
	local n = #sorted
	if n == 0 then
		return nil
	end
	if n % 2 == 1 then
		return sorted[(n + 1) / 2]
	end
	return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

local function runMany(indexSpeed, seeds)
	local perZone = {}
	local finals = {}
	for s = 1, seeds do
		local reach, final = simulate(1000 + s * 7919, indexSpeed)
		table.insert(finals, final)
		for order = 1, #Biomes.list do
			perZone[order] = perZone[order] or {}
			table.insert(perZone[order], reach[order] or math.huge)
		end
	end
	return perZone, finals
end

local function hours(seconds)
	if seconds == nil or seconds == math.huge then
		return string.format(">%dh", HOURS)
	end
	return string.format("%.1fh", seconds / 3600)
end

local function pad(s, n)
	s = tostring(s)
	local len = utf8.len(s) or #s
	return s .. string.rep(" ", math.max(0, n - len))
end

local mode = process.args[1]

if mode == "whatif" then
	-- 참고용: 러닝머신 배율 × 도감 속도 보상 지수 조합 (이 실행 안에서만 값을 바꿔 봄, 파일은 안 바뀜)
	print(
		"도감 속도 보상 지수 what-if (속도 보상 = 희귀도 기본 × (추천 속도/3600)^지수, 시드 5개 중앙값)"
	)
	print(pad("러닝머신", 9) .. pad("지수", 7) .. pad("8구역", 10) .. pad("13구역", 10) .. "15구역")
	for _, combo in
		{
			{ 3, 1 },
			{ 3, 0.9 },
			{ 3, 0.85 },
			{ 3, 0.8 },
			{ 3, 0.75 },
			{ 6, 0.8 },
			{ 6, 0.75 },
			{ 12, 0.75 },
			{ 12, 0.7 },
			{ 24, 0.7 },
		}
	do
		Config.TREADMILL_MULTIPLIER = combo[1]
		Index.SPEED_BIOME_EXPONENT = combo[2]
		local r = runMany(true, 5)
		print(
			pad(combo[1], 9)
				.. pad(combo[2], 7)
				.. pad(hours(median(r[8])), 10)
				.. pad(hours(median(r[13])), 10)
				.. hours(median(r[15]))
		)
	end
	return
end

if mode == "sweep" then
	print(
		string.format(
			"러닝머신 배율 스윕 (TREADMILL_STEPS_PER_SECOND = %s, 시드 %d개 중앙값)",
			tostring(Config.TREADMILL_STEPS_PER_SECOND),
			5
		)
	)
	print(
		pad("배율", 8)
			.. pad("8구역", 12)
			.. pad("13구역", 12)
			.. pad("15구역", 12)
			.. "| 러닝머신만 8 / 13 / 15"
	)
	for _, mult in { 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48 } do
		Config.TREADMILL_MULTIPLIER = mult
		local withIndex = runMany(true, 5)
		local treadOnly = runMany(false, 5)
		print(
			pad(mult, 8)
				.. pad(hours(median(withIndex[8])), 12)
				.. pad(hours(median(withIndex[13])), 12)
				.. pad(hours(median(withIndex[15])), 12)
				.. "| "
				.. hours(median(treadOnly[8]))
				.. " / "
				.. hours(median(treadOnly[13]))
				.. " / "
				.. hours(median(treadOnly[15]))
		)
	end
	return
end

print("== 밸런스 1차: 구역 추천 속도 도달 시간 ==")
print(
	string.format(
		"러닝머신 배율 %s × 초당 걸음 %s, 성장 배율 G = %s, 주기당 알 %d개, 시드 %d개, 최대 %d시간",
		tostring(Config.TREADMILL_MULTIPLIER),
		tostring(Config.TREADMILL_STEPS_PER_SECOND),
		tostring(Config.GROWTH_MULTIPLIER),
		TRIPS_PER_CYCLE,
		SEEDS,
		HOURS
	)
)
local withIndex, finals = runMany(true, SEEDS)
local treadOnly = runMany(false, SEEDS)
print("")
print(
	pad("구역", 18)
		.. pad("추천 속도", 10)
		.. pad("중앙값", 9)
		.. pad("최소~최대", 16)
		.. "러닝머신만(도감 속도 보상 제외)"
)
for order, biome in Biomes.list do
	local values = withIndex[order]
	local lo, hi = math.huge, 0
	for _, v in values do
		lo = math.min(lo, v)
		hi = math.max(hi, v)
	end
	print(
		pad(order .. ". " .. biome.name, 18)
			.. pad(Format.number(biome.recommendedSpeed), 10)
			.. pad(hours(median(values)), 9)
			.. pad(hours(lo) .. "~" .. hours(hi), 16)
			.. hours(median(treadOnly[order]))
	)
end
print("")
for _, target in TARGETS do
	local m = median(withIndex[target.order])
	local h = if m and m ~= math.huge then m / 3600 else math.huge
	local ok = h >= target.low and h <= target.high
	print(
		string.format(
			"목표 %d구역 %d~%d시간 → %s %s",
			target.order,
			target.low,
			target.high,
			hours(m),
			if ok then "OK" else "벗어남"
		)
	)
end
local f = finals[1]
print(
	string.format(
		"\n(시드 1 마지막 상태: 러닝머신 %d레벨, 트레일 ×%s, 우리 %d레벨, 실효 속도 %s, 초당 수입 %s)",
		f.tread,
		tostring(f.trail),
		f.pen,
		Format.number(f.speed),
		Format.money(f.income)
	)
)
