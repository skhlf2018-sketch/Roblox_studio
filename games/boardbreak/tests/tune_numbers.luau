--!nocheck
--[[
	tune_numbers — 설계서 6장 규칙으로 띠 · 아령 값을 **만드는** 도구 (저장소 루트에서):
	  lune run games/boardbreak/tests/tune_numbers.luau
	SimPlayer (sim_progress 와 같은 플레이어 — 진짜 걷기 32 × 몸 배율, 진짜 맵 거리) 를 돌려서 숫자를 정하고,
	Data/Belts · Dumbbells 에 붙여 넣을 줄을 출력함. 붙여 넣은 뒤 sim_progress 로 검사, numbers_doc 로 설계서 9장.

	고정 (사장님): 물건 41개 표 (reward · recommendPower · hp), 아령 힘/번 전부, 3kg 아령 42, 띠 순서·월드·대결 (결정 16번).

	정하는 법 (2026-11-16 sim 다시 맞추기 — 결정 13·14·16번 뒤):
	  띠 needPower (추천 힘):
	    심사 띠 = 그 심사를 보는 물건(EXAM_AT) 바로 앞 물건이 "편해지는 힘"(hp / 3) × EXAM_EASE 1.8
	              (똑똑한 플레이어는 그 0.57배쯤 — 앞 물건이 편해질 때 합격). 월드 안에서 물건 2개마다 한 번.
	    대결 띠 = 옛 표 그대로 (마지막 물건이 편해진 힘 × 1.25 의 2배 · 월드 3 은 우주 추천 힘 × 1.6 의 2배).
	  띠 배율: 옛 12개 표의 (추천 힘, 배율) 꺾은선을 로그-로그로 따라감 (같은 힘이면 옛날과 같은 배율 — 돈 버는 빠르기 그대로)
	           → 두 자리로 반올림 (순증가).
	  아령 값 (3kg 42 · 1kg 0 고정):
	    1) 지금 값으로 sim → 아령마다 사는 데 걸린 시간 took[n]
	    2) took 를 "줄지 않는 줄"로 고름 (이웃 평균 — pool adjacent violators: 합계 = 게임 길이는 그대로, 늘이지도 줄이지도 않음)
	    3) 그 시간 T[n] 이 지났을 때 가진 돈 (3자리 내림, 앞 아령 값의 1.05배 이상) = 값 — sim 을 돌리면서 그때그때 정함
	    (B-1: 앞 아령보다 사는 시간이 줄지 않음 · 한도 10분)
]]

local Loader = require("./Loader")
local SimPlayer = require("./SimPlayer")

Loader.get("ReplicatedStorage/Shared/Data/Config")
local Targets = Loader.require("ReplicatedStorage/Shared/Data/Targets")
local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")
local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")
local Worlds = Loader.require("ReplicatedStorage/Shared/Data/Worlds")
local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
local Progression = Loader.require("ReplicatedStorage/Shared/Progression")
local ExamRules = Loader.require("ReplicatedStorage/Shared/ExamRules")
local MapLayout = Loader.require("ReplicatedStorage/Shared/Data/MapLayout")
local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")

local HUGE = math.huge

-- 조절 손잡이 ------------------------------------------------------------
local EXAM_EASE = 1.8
-- 심사 띠 번호 → 그 심사를 보는 물건 번호 (월드 안에서 물건 2개마다). 대결 띠는 옛 값 (DUEL_NEED)
local EXAM_AT = {
	[2] = 4,
	[3] = 6,
	[4] = 8,
	[5] = 10,
	[6] = 12,
	[8] = 15,
	[9] = 17,
	[10] = 19,
	[11] = 21,
	[12] = 23,
	[13] = 25,
	[15] = 29,
	[16] = 31,
	[17] = 33,
	[18] = 35,
	[19] = 37,
	[20] = 39,
	[21] = 41,
}
local DUEL_NEED = { [7] = 3.1e13, [14] = 1.66e27, [22] = 1.97e40 }
-- 옛 12개 표 (추천 힘, 배율) — 배율 꺾은선. 맨 앞은 솜 추천 힘에서 배율 1
local OLD_CURVE = {
	{ 5, 1 },
	{ 3.99e5, 1.5 },
	{ 3.59e9, 2 },
	{ 3.1e13, 3 },
	{ 2.05e16, 5 },
	{ 1.56e20, 8 },
	{ 1.28e24, 12 },
	{ 1.66e27, 20 },
	{ 9.3e29, 35 },
	{ 7.26e32, 60 },
	{ 5.88e36, 100 },
	{ 1.97e40, 200 },
}

local function round3Up(x: number): number
	if x <= 0 then
		return 0
	end
	local e = math.floor(math.log10(x))
	local scale = 10 ^ (e - 2)
	local v = math.ceil(x / scale - 1e-9) * scale
	local clean = tonumber(string.format("%.3g", v))
	if clean < x then
		clean = tonumber(string.format("%.3g", v + scale))
	end
	return clean
end

local function round3Down(x: number): number
	if x <= 0 then
		return 0
	end
	local e = math.floor(math.log10(x))
	local scale = 10 ^ (e - 2)
	local v = math.floor(x / scale + 1e-9) * scale
	local clean = tonumber(string.format("%.3g", v))
	if clean > x then
		clean = tonumber(string.format("%.3g", v - scale))
	end
	return clean
end

-- 두 자리 (배율): 1.27 → 1.3, 23.4 → 23, 179 → 180
local function round2(x: number): number
	local e = math.floor(math.log10(x))
	local scale = 10 ^ (e - 1)
	return tonumber(string.format("%.2g", math.floor(x / scale + 0.5) * scale))
end

local function multiplierAt(need: number): number
	local L = math.log10(need)
	for i = 1, #OLD_CURVE - 1 do
		local a, b = OLD_CURVE[i], OLD_CURVE[i + 1]
		local la, lb = math.log10(a[1]), math.log10(b[1])
		if L <= lb + 1e-9 then
			local t = math.clamp((L - la) / (lb - la), 0, 1)
			return 10 ^ (math.log10(a[2]) + t * (math.log10(b[2]) - math.log10(a[2])))
		end
	end
	return OLD_CURVE[#OLD_CURVE][2]
end

------------------------------------------------------------------
-- 1) 띠 (sim 없이)
------------------------------------------------------------------
local function setBelt(b, needPower: number, mult: number)
	b.needPower = needPower
	b.moneyMultiplier = mult
	b.examBoardHp = if b.duel or b.index == 1 then 0 else needPower * Belts.EXAM_HITS_AT_NEED
	b.duelBoardHp = if b.duel then needPower * Belts.DUEL_HITS_AT_NEED else 0
	if b.duel then
		Worlds.list[b.world].duelBoardHp = b.duelBoardHp
	end
end
local lastMult = 1
for _, b in Belts.list do
	if b.index > 1 then
		local need
		if b.duel then
			need = assert(DUEL_NEED[b.index], "대결 띠 " .. b.id)
		else
			local at = assert(EXAM_AT[b.index], "심사 띠 자리 " .. b.id)
			need = round3Up(Targets.list[at - 1].hp / 3 * EXAM_EASE)
		end
		local mult = round2(multiplierAt(need))
		if b.index == Belts.COUNT then
			mult = math.max(mult, 200)
		end
		if mult <= lastMult then
			mult = lastMult + (if lastMult < 10 then 0.1 else 1)
		end
		lastMult = mult
		setBelt(b, need, mult)
	end
end

------------------------------------------------------------------
-- 2) 아령 값
------------------------------------------------------------------
local m = {
	Targets = Targets,
	Dumbbells = Dumbbells,
	Belts = Belts,
	Worlds = Worlds,
	Economy = Economy,
	Progression = Progression,
	ExamRules = ExamRules,
	MapLayout = MapLayout,
	Sizes = Sizes,
}

local function took(log): { number }
	local list = {}
	for level = 2, Dumbbells.COUNT do
		list[level] = if log.buy[level] and log.buy[level - 1] then log.buy[level] - log.buy[level - 1] else nil
	end
	return list
end

-- 줄지 않는 줄 (pool adjacent violators — 합계는 그대로)
local function nonDecreasing(values: { number }, from: number, to: number): { number }
	local blocks = {}
	for i = from, to do
		table.insert(blocks, { sum = values[i], n = 1 })
		while #blocks >= 2 do
			local b, a = blocks[#blocks], blocks[#blocks - 1]
			if a.sum / a.n <= b.sum / b.n then
				break
			end
			a.sum += b.sum
			a.n += b.n
			table.remove(blocks)
		end
	end
	local out = table.clone(values)
	local i = from
	for _, b in blocks do
		for _ = 1, b.n do
			out[i] = b.sum / b.n
			i += 1
		end
	end
	return out
end

-- 줄지 않는 줄을 부드러운 오르막으로: T[n] = T[2] + B · x^p (x = (n-2)/(개수-2)) — 합계(게임 길이)는 그대로,
--   p 는 "아령을 산 시각"(누적 합)이 줄지 않는 줄과 가장 가깝게 (월드 끝 시각이 안 바뀌게)
local function smoothRamp(values: { number }, from: number, to: number): ({ number }, number)
	local base = values[from - 1]
	local total, cum = 0, {}
	for i = from, to do
		total += values[i]
		cum[i] = total
	end
	local span = to - (from - 1)
	local best, bestP, bestErr = nil, 1, HUGE
	for step = 10, 300 do
		local p = step / 100
		local sumX = 0
		for i = from, to do
			sumX += ((i - (from - 1)) / span) ^ p
		end
		local B = (total - base * (to - from + 1)) / sumX
		local out, run, err = table.clone(values), 0, 0
		for i = from, to do
			out[i] = base + B * ((i - (from - 1)) / span) ^ p
			run += out[i]
			err += (run - cum[i]) ^ 2
		end
		if B > 0 and err < bestErr then
			best, bestP, bestErr = out, p, err
		end
	end
	return best, bestP
end

local process = require("@lune/process")
local REPAIR_ONLY = table.find(process.args, "repair") ~= nil -- 3) 만 (지금 값에서 줄어드는 칸만 올림)

local _, firstLog = SimPlayer.run(m)
local before = took(firstLog)
local fixedPrice = {}
for level, d in Dumbbells.list do
	fixedPrice[level] = d.price
end

if not REPAIR_ONLY then
	local want, rampP = smoothRamp(nonDecreasing(before, 3, Dumbbells.COUNT), 3, Dumbbells.COUNT)
	print(string.format("사는 시간 오르막: T[n] = %.0f + B · x^%.2f", before[2], rampP))
	for level, d in Dumbbells.list do
		if level >= 3 then
			d.price = HUGE
		end
	end
	SimPlayer.run(m, {
		onStep = function(s, log)
			local nextLevel = s.db + 1
			local d = Dumbbells.list[nextLevel]
			-- 바라는 시간, 단 앞 아령이 (심사·대결과 겹쳐) 늦게 사졌으면 그 97% 아래로는 안 내려감 (B-1)
			local prevTook = if s.db >= 2 then log.buy[s.db] - log.buy[s.db - 1] else 0
			local wantNow = if want[nextLevel] then math.max(want[nextLevel], prevTook * 0.97) else HUGE
			if d and d.price == HUGE and s.t - log.buy[s.db] >= wantNow then
				local prevPrice = Dumbbells.list[s.db].price
				d.price = math.max(round3Down(s.money), round3Up(prevPrice * 1.05))
			end
		end,
	})
end

-- 3) 값을 고정한 채로 돌려서 "앞 아령의 95.5% 아래로 줄어드는" 첫 칸을 찾아, 앞 아령 시간의 97% 가 지났을 때 가진 돈으로
--    값을 올림 (3자리 올림) — 줄어드는 칸이 없을 때까지 (심사·대결이 아령 사이에 끼면 그 아령만 길어져서 생기는 굴곡)
local REPAIR_AT, REPAIR_TO = 0.955, 0.97
local repairs = {}
for _ = 1, 150 do
	local _, lg = SimPlayer.run(m)
	local tk = took(lg)
	local bad = nil
	for n = 3, Dumbbells.COUNT do
		if tk[n] and tk[n - 1] and tk[n] < tk[n - 1] * REPAIR_AT then
			bad = n
			break
		end
	end
	if not bad then
		break
	end
	local d = Dumbbells.list[bad]
	local old = d.price
	local due = tk[bad - 1] * REPAIR_TO
	d.price = HUGE
	pcall(SimPlayer.run, m, {
		onStep = function(s, log)
			if s.db == bad - 1 and s.t - log.buy[bad - 1] >= due then
				d.price = math.max(old, round3Up(s.money))
				error("정함", 0) -- 이 아령 값만 정하면 됨 (나머지는 안 돌림)
			end
		end,
	})
	if d.price == HUGE then
		d.price = old
		break
	end
	table.insert(repairs, string.format("%s ×%.2f", d.id, d.price / old))
end
print("줄어드는 칸 고침 " .. #repairs .. "번: " .. table.concat(repairs, ", "))

local final, log = SimPlayer.run(m)
local after = took(log)

local function mmss(seconds: number?): string
	if not seconds then
		return "-"
	end
	return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end
local function e(n: number): string
	if n == 0 then
		return "0"
	end
	if n < 1e4 and n % 1 == 0 then
		return tostring(n)
	end
	local str = string.format("%.3g", n)
	str = string.gsub(str, "e%+0*", "e")
	return str
end

print("== 아령 (전 값 → 새 값 · 사는 시간 전 → 새)")
for level = 2, Dumbbells.COUNT do
	local d = Dumbbells.list[level]
	print(
		string.format(
			"%2d %-16s %-9s → %-9s (×%.2f)  %4.0f → %4.0f초",
			level,
			d.name,
			e(fixedPrice[level]),
			e(d.price),
			d.price / math.max(fixedPrice[level], 1),
			before[level] or -1,
			after[level] or -1
		)
	)
end
print(
	string.format(
		"전: 월드 끝 %s · %s · %s  →  새: %s · %s · %s · 걷기 %s · 마지막 힘 %s",
		mmss(firstLog.worldOpen[2]),
		mmss(firstLog.worldOpen[3]),
		mmss(firstLog.belt[Belts.COUNT]),
		mmss(log.worldOpen[2]),
		mmss(log.worldOpen[3]),
		mmss(log.belt[Belts.COUNT]),
		mmss(log.walkSeconds),
		e(final.power)
	)
)

print("\n-- Belts ROWS (need · mult)")
for _, b in Belts.list do
	print(
		string.format(
			"\t%-10s need = %s, mult = %s,  (받은 시각 %s)",
			b.id,
			e(b.needPower),
			tostring(b.moneyMultiplier),
			mmss(log.belt[b.index])
		)
	)
end
print("\n-- Dumbbells ROWS")
for level, d in Dumbbells.list do
	print(string.format('\t{ "%s", "%s", %s, %s, %s },', d.id, d.name, e(d.weightKg), e(d.powerPerRep), e(d.price)))
end
