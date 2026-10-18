--!nocheck
--[[
	설계문서 일치 검사: docs/GAME_DESIGN.md 의 표·숫자를 읽어서 데이터 파일(src/shared/Data/*)과 같은지 비교합니다.
	문서가 바뀌었는데 코드를 안 고쳤거나, 코드만 바꾸고 문서를 안 고쳤으면 여기서 걸립니다.
	(문서를 직접 파싱 — 표를 테스트에 옮겨 적은 게 아니라서 문서가 "진짜 기준"입니다.)
]]

local fs = require("@lune/fs")

return function(T, Loader)
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Rarities = Loader.require("ReplicatedStorage/Shared/Data/Rarities")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Mutations = Loader.require("ReplicatedStorage/Shared/Data/Mutations")
	local Upgrades = Loader.require("ReplicatedStorage/Shared/Data/Upgrades")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local EggSpawn = Loader.require("ReplicatedStorage/Shared/Data/EggSpawn")
	local Index = Loader.require("ReplicatedStorage/Shared/Data/Index")
	local FusionRules = Loader.require("ReplicatedStorage/Shared/FusionRules")

	------------------------------------------------------------------
	-- 문서 읽기 도우미
	------------------------------------------------------------------
	local DOC = fs.readFile("docs/GAME_DESIGN.md")
	local sections = {} -- "4" → 줄 목록 ("## 4." 장 하나)
	do
		local current = nil
		for line in string.gmatch(DOC .. "\n", "(.-)\r?\n") do
			local number = string.match(line, "^## (%d+)%.")
			if number then
				current = number
				sections[current] = {}
			elseif current then
				table.insert(sections[current], line)
			end
		end
	end

	-- 장 안의 "### 9-2" 소제목 하나 (다음 "### " 전까지)
	local function subsection(sectionNumber, id)
		local result = {}
		local inside = false
		for _, line in sections[sectionNumber] do
			if string.sub(line, 1, 4) == "### " then
				inside = string.find(line, id, 1, true) ~= nil
			elseif inside then
				table.insert(result, line)
			end
		end
		return result
	end

	local UNITS = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, Qa = 1e15 }

	-- "$1.8K" "1,000" "5Qa" "**150B**" "+420" → 숫자
	local function parseNumber(text)
		local cleaned = string.gsub(text, "[%*%$,%+]", "")
		cleaned = string.gsub(cleaned, "^%s+", "")
		local digits, unit = string.match(cleaned, "^([%d%.]+)%s*(%a*)")
		assert(digits, "숫자를 못 읽음: " .. text)
		local value = tonumber(digits)
		if unit ~= "" then
			assert(UNITS[unit], "모르는 단위 " .. unit .. " (" .. text .. ")")
			value = value * UNITS[unit]
		end
		return value
	end

	-- "1분 30초" "4시간" "20초" → 초
	local function parseDuration(text)
		local h = tonumber(string.match(text, "(%d+)시간")) or 0
		local m = tonumber(string.match(text, "(%d+)분")) or 0
		local s = tonumber(string.match(text, "(%d+)초")) or 0
		return h * 3600 + m * 60 + s
	end

	local function trim(text)
		return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
	end

	local function splitCells(line)
		local inner = string.match(line, "^|(.*)|%s*$")
		if not inner then
			return nil
		end
		local cells = {}
		for cell in string.gmatch(inner .. "|", "(.-)|") do
			table.insert(cells, trim(cell))
		end
		return cells
	end

	-- 표 줄 중 첫 칸이 패턴에 맞는 것 (** 는 벗겨서 돌려줌)
	local function tableRows(lines, firstCellPattern)
		local rows = {}
		for _, line in lines do
			local cells = splitCells(line)
			if cells and cells[1] then
				local first = string.gsub(cells[1], "%*", "")
				if string.match(first, firstCellPattern) then
					cells[1] = first
					table.insert(rows, cells)
				end
			end
		end
		return rows
	end

	local function splitDash(text)
		local parts = {}
		local start = 1
		while true do
			local i, j = string.find(text, " — ", start, true)
			if not i then
				table.insert(parts, string.sub(text, start))
				break
			end
			table.insert(parts, string.sub(text, start, i - 1))
			start = j + 1
		end
		return parts
	end

	local function startsWith(text, prefix)
		return string.sub(text, 1, #prefix) == prefix
	end

	local function escapePattern(text)
		return (string.gsub(text, "%p", "%%%0"))
	end

	------------------------------------------------------------------
	T.suite("설계문서 ↔ 데이터: 파서 자체 점검")

	T.test("숫자·시간 읽기 (K/M/B/T/Qa, 쉼표, +, 시·분·초)", function()
		T.eq(parseNumber("$1.8K"), 1800)
		T.eq(parseNumber("1,000"), 1000)
		T.eq(parseNumber("**150B**"), 150e9)
		T.eq(parseNumber("$5Qa"), 5e15)
		T.eq(parseNumber("2,000 (최대)"), 2000)
		T.eq(parseNumber("+$4,500"), 4500)
		T.eq(parseNumber("10 (시작 구역, 튜토리얼)"), 10)
		T.eq(parseDuration("1분 30초"), 90)
		T.eq(parseDuration("1시간 30분"), 5400)
		T.eq(parseDuration("4시간"), 14400)
		T.eq(parseDuration("20초"), 20)
	end)

	T.test("문서에 필요한 장이 다 있음", function()
		for _, n in { "2", "3", "4", "5", "7", "8", "9", "10", "14" } do
			T.truthy(sections[n] and #sections[n] > 3, n .. "장")
		end
	end)

	------------------------------------------------------------------
	T.suite("설계문서 4장 ↔ Biomes (구역 15개)")

	T.test("구역 15개: 순서·이름·추천 속도·경비·도감 무기가 문서 표와 같음", function()
		local rows = tableRows(sections["4"], "^%d+$")
		T.eq(#rows, 15, "표 줄 수")
		T.eq(#Biomes.list, 15)
		for i, row in rows do
			local biome = Biomes.list[i]
			T.eq(tonumber(row[1]), biome.order, i .. "번 순서")
			local name = string.gsub(row[2], "%*", "")
			T.truthy(startsWith(name, biome.name), i .. "번 이름 " .. name .. " ≠ " .. biome.name)
			T.truthy(string.find(name, biome.nameEn, 1, true), i .. "번 영어 이름 " .. biome.nameEn)
			T.eq(parseNumber(row[3]), biome.recommendedSpeed, biome.id .. " 추천 속도")
			local guard = string.gsub(row[4], "%*", "")
			T.truthy(startsWith(guard, biome.guardName), biome.id .. " 경비 " .. guard .. " ≠ " .. biome.guardName)
			local weapon = string.gsub(row[5], "%*", "")
			if weapon == "-" then
				T.eq(biome.weapon, nil, biome.id .. " 무기 없음")
			else
				T.truthy(biome.weapon ~= nil, biome.id .. " 무기 있어야 함 (" .. weapon .. ")")
				T.eq(biome.weapon.name, weapon, biome.id .. " 무기 이름")
			end
		end
	end)

	T.test("추천 속도는 문서 표에서도 계속 커짐 (뒤 구역일수록 어려움)", function()
		local prev = 0
		for _, row in tableRows(sections["4"], "^%d+$") do
			local speed = parseNumber(row[3])
			T.truthy(speed > prev, row[2])
			prev = speed
		end
	end)

	------------------------------------------------------------------
	T.suite("설계문서 5장 ↔ Pets (펫 134종의 희귀도·수입·부화 시간)")

	-- 5장 전체를 훑어서 { name, rarity, income, hatch?, biomeN, kind, tag } 목록으로
	local docPets = {}
	do
		local biomeN, kind = nil, nil
		for _, line in sections["5"] do
			local heading = string.match(line, "^%*%*(.-)%*%*%s*$")
			if heading then
				biomeN = tonumber(string.match(heading, "^(%d+)%."))
				kind = if string.find(heading, "Light", 1, true)
					then "light"
					elseif string.find(heading, "Dark", 1, true) then "dark"
					elseif biomeN == 12 then "neutral"
					else nil
			end
			local bullet = string.match(line, "^%- (.+)$")
			if bullet and biomeN and string.find(bullet, " — ", 1, true) then
				local parts = splitDash(bullet)
				local rawName = parts[1]
				local tag = nil
				if startsWith(rawName, "(퀘스트) ") then
					rawName = string.sub(rawName, #"(퀘스트) " + 1)
					tag = "quest"
				end
				if string.find(rawName, "(합성)", 1, true) then
					tag = "fusion"
				end
				table.insert(docPets, {
					name = rawName,
					rarity = parts[2],
					income = parseNumber(parts[3]),
					hatch = if parts[4] then parseDuration(parts[4]) else nil,
					biomeN = biomeN,
					kind = kind,
					tag = tag,
				})
			end
		end
	end

	local rarityIdByName = {}
	for _, r in Rarities.list do
		rarityIdByName[r.name] = r.id
	end

	T.test("문서 5장 펫 줄 수 = 코드 펫 수 (134)", function()
		T.eq(#docPets, Pets.count)
		T.eq(#docPets, 134)
	end)

	T.test(
		"모든 펫: 문서 순서대로 이름·희귀도·초당 수입(원본)·부화 시간(원본)이 코드와 같음",
		function()
			for i, doc in docPets do
				local pet = Pets.list[i]
				T.truthy(pet ~= nil, i .. "번 펫이 코드에 없음")
				T.truthy(
					startsWith(doc.name, pet.name),
					i .. "번 이름: 문서 '" .. doc.name .. "' / 코드 '" .. pet.name .. "'"
				)
				T.eq(rarityIdByName[doc.rarity], pet.rarity, pet.id .. " 희귀도 (문서 " .. doc.rarity .. ")")
				T.near(pet.income, doc.income, doc.income * 1e-12, pet.id .. " 수입")
				if doc.hatch then
					T.eq(pet.hatchSeconds, doc.hatch, pet.id .. " 부화 시간")
				else
					T.truthy(pet.estimated, pet.id .. " 문서에 부화 시간이 없으면 estimated 표시")
				end
			end
		end
	)

	T.test(
		"모든 펫: 문서 소제목의 구역·쪽(천국/지옥)·출처(퀘스트/합성)가 코드와 같음",
		function()
			for i, doc in docPets do
				local pet = Pets.list[i]
				T.eq(pet.biome, Biomes.list[doc.biomeN].id, pet.id .. " 구역")
				if doc.kind == "light" or doc.kind == "dark" then
					T.eq(pet.side, doc.kind, pet.id .. " 쪽")
				else
					T.eq(pet.side, nil, pet.id .. " 쪽 없음")
				end
				if doc.tag == "quest" then
					T.eq(pet.source, "quest", pet.id)
				elseif doc.tag == "fusion" then
					T.eq(pet.source, "fusion", pet.id)
				end
			end
		end
	)

	T.test(
		"같은 구역 둥지 펫은 문서 순서대로 희귀도가 내려가지 않음 (오타로 순서 뒤집힌 곳 찾기)",
		function()
			for _, biome in Biomes.list do
				local prev = 0
				for _, pet in Pets.inBiome(biome.id) do
					if pet.source == "nest" and (pet.side == nil or pet.side == "light") then
						local order = Rarities.order(pet.rarity)
						T.truthy(order >= prev, biome.id .. " " .. pet.id .. " 희귀도 순서")
						prev = order
					end
				end
			end
		end
	)

	T.test(
		"3장 희귀도 표: 이름·영어·순서, 가장 싼 펫 수입이 표의 최소값과 일치, 1~11번 구역 펫은 표 범위 안",
		function()
			local rows = tableRows(sections["3"], "^%d+$")
			T.eq(#rows, 10)
			for i, row in rows do
				local rarity = Rarities.list[i]
				T.eq(tonumber(row[1]), rarity.order)
				T.eq(row[2], rarity.name)
				T.eq(row[3], rarity.nameEn)
				local lo, hi = string.match(row[5], "^(%S+) ~ (%S+)$")
				T.truthy(lo and hi, "범위 형식 " .. row[5])
				local docLow, docHigh = parseNumber(lo), parseNumber(hi)
				local minIncome = math.huge
				for _, pet in Pets.list do
					if pet.rarity == rarity.id then
						minIncome = math.min(minIncome, pet.income)
						if Biomes.get(pet.biome).order <= 11 then
							T.truthy(
								pet.income >= docLow and pet.income <= docHigh,
								pet.id .. " 수입이 3장 범위 밖: " .. row[5]
							)
						end
					end
				end
				T.eq(minIncome, docLow, rarity.id .. " 최소 수입")
			end
		end
	)

	------------------------------------------------------------------
	T.suite("설계문서 7·8장 ↔ Sizes, Mutations")

	T.test("7장 크기 표: 등장 확률·수입 배율·속도 감소가 같고 확률 합은 100%", function()
		local rows = {}
		for _, line in sections["7"] do
			local cells = splitCells(line)
			if cells and cells[2] and string.match(cells[2], "^[%d%.]+%%$") then
				table.insert(rows, cells)
			end
		end
		T.eq(#rows, 4)
		local total = 0
		for i, cells in rows do
			local size = Sizes.list[i]
			T.truthy(startsWith(cells[1], size.name), size.id .. " 이름")
			local chance = tonumber(string.match(cells[2], "([%d%.]+)%%"))
			T.eq(chance, size.chance, size.id .. " 확률")
			total += chance
			T.eq(tonumber(string.match(cells[3], "×([%d%.]+)")), size.incomeMultiplier, size.id .. " 수입 배율")
			T.near(
				tonumber(string.match(cells[4], "%-(%d+)%%")) / 100,
				size.speedPenalty,
				1e-12,
				size.id .. " 속도 감소"
			)
		end
		T.eq(total, 100)
	end)

	T.test(
		"8장 돌연변이 표: 배율이 같고, 자연 확률(5%/2%/0.5%)·획득 확률(97.5%/2.5%/10%/1.5%) 일치",
		function()
			local checked = 0
			for _, line in sections["8"] do
				local cells = splitCells(line)
				if cells and cells[2] and string.find(cells[2], "×", 1, true) then
					local mutation = nil
					for _, m in Mutations.list do
						if startsWith(cells[1], m.name) and (mutation == nil or #m.name > #mutation.name) then
							mutation = m
						end
					end
					T.truthy(mutation, "모르는 돌연변이 " .. cells[1])
					T.eq(tonumber(string.match(cells[2], "×([%d%.]+)")), mutation.multiplier, mutation.id .. " 배율")
					local percent = tonumber(string.match(cells[3], "([%d%.]+)%%"))
					if percent then
						if mutation.group == "natural" then
							T.near(mutation.naturalChance, percent / 100, 1e-12, mutation.id .. " 자연 확률")
						elseif mutation.sourceChance then
							T.near(mutation.sourceChance, percent / 100, 1e-12, mutation.id .. " 획득 확률")
						end
					end
					checked += 1
				end
			end
			T.eq(checked, #Mutations.list, "문서의 돌연변이 8종 전부 확인")
		end
	)

	T.test("8장: 중첩 예시 균열 2.75 × 혼란 2.75 = 7.56배", function()
		T.near(Mutations.get("fractured").multiplier * Mutations.get("chaos").multiplier, 7.5625, 1e-9)
		T.truthy(string.find(DOC, "7.56배", 1, true))
	end)

	------------------------------------------------------------------
	T.suite("설계문서 9장 ↔ Upgrades (우리·러닝머신·트레일 가격표)")

	T.test("9-1 우리: 11단계 비용·칸 수가 같음 (1단계는 무료 7칸)", function()
		local rows = tableRows(subsection("9", "9-1"), "^%d+$")
		T.eq(#rows, 11, "우리 표 줄 수")
		for i, cells in rows do
			local level = Upgrades.Pen[i]
			T.eq(tonumber(cells[1]), level.level)
			T.eq(if cells[2] == "무료" then 0 else parseNumber(cells[2]), level.cost, i .. "레벨 비용")
			T.eq(tonumber(string.match(cells[3], "^(%d+)")), level.slots, i .. "레벨 칸 수")
		end
	end)

	T.test("9-2 러닝머신: 10단계 비용·걸음당 속도(원본)가 같음 (1단계 = 해금 $1,000)", function()
		local rows = tableRows(subsection("9", "9-2"), "^%d+$")
		T.eq(#rows, 10)
		for i, cells in rows do
			local level = Upgrades.Treadmill[i]
			T.eq(tonumber(cells[1]), level.level)
			T.eq(parseNumber(string.match(cells[2], "%$[%w%.,]+")), level.cost, i .. "레벨 비용")
			T.eq(parseNumber(cells[3]), level.perStep, i .. "레벨 걸음당 속도")
		end
		T.truthy(string.find(DOC, "정원 업그레이드 **$1,000** 으로 러닝머신 해금", 1, true))
	end)

	T.test("9-3 트레일: 11개 이름·배율·가격이 같음", function()
		local rows = {}
		for _, line in subsection("9", "9-3") do
			local cells = splitCells(line)
			if cells and cells[2] and string.find(cells[2], "×", 1, true) then
				table.insert(rows, cells)
			end
		end
		T.eq(#rows, 11)
		for i, cells in rows do
			local trail = Upgrades.Trails[i]
			T.truthy(startsWith(cells[1], trail.name), trail.id .. " 이름")
			T.truthy(string.find(cells[1], trail.nameEn, 1, true), trail.id .. " 영어 이름")
			T.eq(tonumber(string.match(cells[2], "×([%d%.]+)")), trail.multiplier, trail.id .. " 배율")
			T.eq(parseNumber(cells[3]), trail.cost, trail.id .. " 가격")
		end
	end)

	T.test("9-5 도감 보상 예시(닭·라쿤·파타핌)가 Index.reward 와 같음", function()
		local forest = Biomes.get("forest").recommendedSpeed
		local examples = {
			{ "닭", "chicken", "+420", "+$100" },
			{ "라쿤", "raccoon", "+620", "+$4,500" },
			{ "브르 브르 파타핌", "brr_brr_patapim", "+1,000", "+$180,000" },
		}
		for _, e in examples do
			local pattern = escapePattern(e[1]) .. " " .. escapePattern(e[3]) .. " 속도 " .. escapePattern(e[4])
			T.truthy(string.find(DOC, pattern), "문서 예시 못 찾음: " .. e[1])
			local pet = Pets.get(e[2])
			local reward = Index.reward(pet.rarity, pet.income, forest)
			T.eq(reward.speed, parseNumber(e[3]), e[2] .. " 속도 보상")
			T.eq(reward.money, parseNumber(e[4]), e[2] .. " 돈 보상")
		end
	end)

	------------------------------------------------------------------
	T.suite("설계문서 1·2·3·10·11·14장 흩어진 숫자 ↔ Config")

	T.test("2장 낮/밤/대기 시간, 밤 30배", function()
		local seconds = {}
		for _, line in sections["2"] do
			local cells = splitCells(line)
			if cells and (cells[1] == "낮" or cells[1] == "밤" or cells[1] == "대기") then
				seconds[cells[1]] = parseDuration(cells[2])
			end
		end
		T.eq(seconds["낮"], Config.DAY_SECONDS)
		T.eq(seconds["밤"], Config.NIGHT_SECONDS)
		T.eq(seconds["대기"], Config.INTERMISSION_SECONDS)
		T.truthy(string.find(DOC, "알이 **30배** 빨리 자랍니다", 1, true))
		T.eq(Config.NIGHT_GROWTH_MULTIPLIER, 30)
	end)

	T.test("서버 7명, 곰덫 5초, 성장 3배, 무료 보상 +10,000 속도, 퓨전 3마리", function()
		T.truthy(string.find(DOC, "서버당 최대 **7명**", 1, true))
		T.eq(Config.MAX_PLAYERS, 7)
		T.eq(Config.PLOT_COUNT, 7)
		T.truthy(string.find(DOC, "**5초** 묶임", 1, true))
		T.eq(Config.BEAR_TRAP_STUN_SECONDS, 5)
		T.truthy(string.find(DOC, "**G = 3**", 1, true))
		T.eq(Config.GROWTH_MULTIPLIER, 3)
		T.truthy(string.find(DOC, "+10,000 속도", 1, true))
		T.eq(Config.FREE_REWARD_SPEED, 10000)
		T.truthy(string.find(DOC, "같은 펫 3마리", 1, true))
		T.eq(FusionRules.INPUT_COUNT, 3)
	end)

	T.test("3장: 신성 등장 확률 약 0.2%", function()
		T.truthy(string.find(DOC, "약 **0.2%**", 1, true))
		T.eq(EggSpawn.SPECIAL_CHANCE_PER_RESET.divine, 0.002)
	end)

	T.test("4장: 구역마다 둥지 8개", function()
		T.truthy(string.find(DOC, "둥지 8개", 1, true))
		T.eq(Config.NESTS_PER_BIOME, 8)
		for _, biome in Biomes.list do
			T.eq(biome.nests, 8, biome.id)
		end
	end)
end
