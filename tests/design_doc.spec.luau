--!nocheck
--[[
	설계문서 일치 검사 (6판 "씨앗을 훔치세요"): 문서의 표·숫자를 읽어서 데이터 파일(src/shared/Data/*)과 같은지 비교합니다.
	문서가 바뀌었는데 코드를 안 고쳤거나, 코드만 바꾸고 문서를 안 고쳤으면 여기서 걸립니다.
	(문서를 직접 파싱 — 표를 테스트에 옮겨 적은 게 아니라서 문서가 "진짜 기준"입니다.)

	- docs/SEED_GAME_DESIGN.md 9~14장 ↔ Plants · Rarities · Biomes(식물 괴물 경비) · EggSpawn(구역 등급 가중치·공지 씨앗)
	  · Mutations · Config(정원·열매·건너뛰기·사쿠라 씨앗·러닝머신)
	- docs/GAME_DESIGN.md 2·4·7·9장 ↔ 시간 주기 · 구역 추천 속도·도감 무기 · Sizes · Upgrades(정원 칸·러닝머신·트레일) · 도감 보상
	  (GAME_DESIGN 3·5·8장은 5판 기록 — 6판에서 SEED 11·10·13장으로 바뀌어 대조하지 않음)
]]

local fs = require("@lune/fs")

return function(T, Loader)
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Plants = Loader.require("ReplicatedStorage/Shared/Data/Plants")
	local Rarities = Loader.require("ReplicatedStorage/Shared/Data/Rarities")
	local Sizes = Loader.require("ReplicatedStorage/Shared/Data/Sizes")
	local Mutations = Loader.require("ReplicatedStorage/Shared/Data/Mutations")
	local Upgrades = Loader.require("ReplicatedStorage/Shared/Data/Upgrades")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local EggSpawn = Loader.require("ReplicatedStorage/Shared/Data/EggSpawn")
	local Index = Loader.require("ReplicatedStorage/Shared/Data/Index")
	local Tutorial = Loader.require("ReplicatedStorage/Shared/Data/Tutorial")
	local Economy = Loader.require("ReplicatedStorage/Shared/Economy")
	local Format = Loader.require("ReplicatedStorage/Shared/Format")

	------------------------------------------------------------------
	-- 문서 읽기 도우미
	------------------------------------------------------------------
	-- "## 4." 장마다 줄 목록. 번호 없는 "## " 제목(참고 자료·판별 수정 기록)에서 장이 끝남
	local function readSections(path)
		local text = fs.readFile(path)
		local sections = {}
		local current = nil
		for line in string.gmatch(text .. "\n", "(.-)\r?\n") do
			local number = string.match(line, "^## (%d+)%.")
			if number then
				current = number
				sections[current] = {}
			elseif string.sub(line, 1, 3) == "## " then
				current = nil
			elseif current then
				table.insert(sections[current], line)
			end
		end
		return text, sections
	end

	local DOC, sections = readSections("docs/GAME_DESIGN.md")
	local SEED, seed = readSections("docs/SEED_GAME_DESIGN.md")

	-- 장 안의 "### 9-2" 소제목 하나 (다음 "### " 전까지)
	local function subsection(lines, id)
		local result = {}
		local inside = false
		for _, line in lines do
			if string.sub(line, 1, 4) == "### " then
				inside = string.find(line, id, 1, true) ~= nil
			elseif inside then
				table.insert(result, line)
			end
		end
		return result
	end

	local UNITS = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, Qa = 1e15, Qi = 1e18, Sx = 1e21 }

	-- "$1.8K" "1,000" "5Qa" "**150B**" "+420" "×30" → 숫자
	local function parseNumber(text)
		local cleaned = string.gsub(text, "[%*%$,%+]", "")
		cleaned = string.gsub(cleaned, "^×", "")
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

	-- "1일 14시간 24분" "1분 30초" "4시간" "20초" → 초
	local function parseDuration(text)
		local d = tonumber(string.match(text, "(%d+)일")) or 0
		local h = tonumber(string.match(text, "(%d+)시간")) or 0
		local m = tonumber(string.match(text, "(%d+)분")) or 0
		local s = tonumber(string.match(text, "(%d+)초")) or 0
		return d * 86400 + h * 3600 + m * 60 + s
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

	-- "a · b · c" → { "a", "b", "c" }
	local function splitDot(text)
		local parts = {}
		local start = 1
		while true do
			local i, j = string.find(text, " · ", start, true)
			if not i then
				table.insert(parts, trim(string.sub(text, start)))
				break
			end
			table.insert(parts, trim(string.sub(text, start, i - 1)))
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

	-- 0.975 → "97.5%" (부동소수 꼬리 없이)
	local function pct(x)
		return string.format("%g", x * 100) .. "%"
	end

	local function hasText(doc, text)
		return string.find(doc, text, 1, true) ~= nil
	end

	local rarityIdByName = {}
	for _, r in Rarities.list do
		rarityIdByName[r.name] = r.id
	end
	local biomeIdByName = {}
	for _, b in Biomes.list do
		biomeIdByName[b.name] = b.id
	end

	------------------------------------------------------------------
	T.suite("설계문서 ↔ 데이터: 파서 자체 점검")

	T.test("숫자·시간 읽기 (K~Sx, 쉼표, +, ×, 일·시·분·초)", function()
		T.eq(parseNumber("$1.8K"), 1800)
		T.eq(parseNumber("1,000"), 1000)
		T.eq(parseNumber("**150B**"), 150e9)
		T.eq(parseNumber("$5Qa"), 5e15)
		T.eq(parseNumber("$60Qi"), 60e18)
		T.eq(parseNumber("1Sx"), 1e21)
		T.eq(parseNumber("2,000 (최대)"), 2000)
		T.eq(parseNumber("+$4,500"), 4500)
		T.eq(parseNumber("×30 (그대로)"), 30)
		T.eq(parseNumber("10 (시작 구역, 튜토리얼)"), 10)
		T.eq(parseDuration("1분 30초"), 90)
		T.eq(parseDuration("1시간 30분"), 5400)
		T.eq(parseDuration("4시간"), 14400)
		T.eq(parseDuration("20초"), 20)
		T.eq(parseDuration("1일 14시간 24분"), 138240)
		T.eq(parseDuration("7일"), 7 * 86400)
		T.eq(table.concat(splitDot("일반 60 · 고급 35 · 희귀 5"), "/"), "일반 60/고급 35/희귀 5")
	end)

	T.test("두 문서에 필요한 장이 다 있음", function()
		for _, n in { "2", "4", "7", "9", "10", "14" } do
			T.truthy(sections[n] and #sections[n] > 3, "GAME_DESIGN " .. n .. "장")
		end
		for _, n in { "3", "4", "7", "9", "10", "11", "12", "13", "14", "15" } do
			T.truthy(seed[n] and #seed[n] > 3, "SEED_GAME_DESIGN " .. n .. "장")
		end
		T.truthy(hasText(DOC, "SEED_GAME_DESIGN.md"), "GAME_DESIGN 맨 위에 6판 안내")
	end)

	------------------------------------------------------------------
	T.suite("GAME_DESIGN 4장 · SEED 12장 ↔ Biomes · EggSpawn (구역 15개)")

	T.test(
		"GAME_DESIGN 4장: 순서·이름·추천 속도·경비(식물 괴물)·도감 무기가 문서 표와 같음",
		function()
			local rows = tableRows(sections["4"], "^%d+$")
			T.eq(#rows, 15, "표 줄 수")
			T.eq(#Biomes.list, 15)
			for i, row in rows do
				local biome = Biomes.list[i]
				T.eq(tonumber(row[1]), biome.order, i .. "번 순서")
				local name = string.gsub(row[2], "%*", "")
				T.truthy(startsWith(name, biome.name), i .. "번 이름 " .. name .. " ≠ " .. biome.name)
				T.truthy(hasText(name, biome.nameEn), i .. "번 영어 이름 " .. biome.nameEn)
				T.eq(parseNumber(row[3]), biome.recommendedSpeed, biome.id .. " 추천 속도")
				local guard = string.gsub(row[4], "%*", "")
				T.truthy(
					startsWith(guard, biome.guardName),
					biome.id .. " 경비 " .. guard .. " ≠ " .. biome.guardName
				)
				local weapon = string.gsub(row[5], "%*", "")
				if weapon == "-" then
					T.eq(biome.weapon, nil, biome.id .. " 무기 없음")
				else
					T.truthy(biome.weapon ~= nil, biome.id .. " 무기 있어야 함 (" .. weapon .. ")")
					T.eq(biome.weapon.name, weapon, biome.id .. " 무기 이름")
				end
			end
		end
	)

	T.test("추천 속도는 문서 표에서도 계속 커짐 (뒤 구역일수록 어려움)", function()
		local prev = 0
		for _, row in tableRows(sections["4"], "^%d+$") do
			local speed = parseNumber(row[3])
			T.truthy(speed > prev, row[2])
			prev = speed
		end
	end)

	T.test(
		"SEED 12장: 이름·추천 속도·경비 한국어/영어 이름·둥지 등급 가중치(%)가 같음",
		function()
			local rows = tableRows(seed["12"], "^%d+$")
			T.eq(#rows, 15, "표 줄 수")
			for i, row in rows do
				local biome = Biomes.list[i]
				T.eq(tonumber(row[1]), biome.order)
				T.eq(row[2], biome.name .. " (" .. biome.nameEn .. ")", i .. "번 이름")
				T.eq(parseNumber(row[3]), biome.recommendedSpeed, biome.id .. " 추천 속도")
				T.eq(row[4], biome.guardName, biome.id .. " 경비")
				T.eq(row[5], biome.guardNameEn, biome.id .. " 경비 영어")
				local weights = EggSpawn.BIOME_RARITY_WEIGHTS[biome.id]
				T.truthy(weights, biome.id .. " 가중치 표")
				local seen, total = 0, 0
				for _, part in splitDot(row[6]) do
					local rarityName, number = string.match(part, "^(.-)%s+([%d%.]+)$")
					T.truthy(rarityName, "가중치 형식 " .. part)
					local rarityId = rarityIdByName[rarityName]
					T.truthy(rarityId, "모르는 등급 " .. tostring(rarityName))
					T.eq(weights[rarityId], tonumber(number), biome.id .. " " .. rarityId .. " 가중치")
					seen += 1
					total += tonumber(number)
				end
				local count = 0
				for _ in weights do
					count += 1
				end
				T.eq(seen, count, biome.id .. " 문서와 코드의 등급 수")
				T.eq(total, 100, biome.id .. " 가중치 합 100")
			end
		end
	)

	T.test(
		"구역 등급 가중치는 뒤 구역일수록 높은 등급 쪽 (가장 높은 등급 순서가 줄지 않음)",
		function()
			local prev = 0
			for _, biome in Biomes.list do
				local top = 0
				for rarityId, weight in EggSpawn.BIOME_RARITY_WEIGHTS[biome.id] do
					if weight > 0 then
						top = math.max(top, Rarities.order(rarityId))
					end
				end
				T.truthy(top >= prev, biome.id)
				prev = top
			end
		end
	)

	------------------------------------------------------------------
	T.suite("SEED 10장 ↔ Plants (식물 134종의 이름·등급·출처·성장 시간·열매)")

	local SOURCES = {
		["둥지"] = { "nest", nil },
		["둥지 · 천국"] = { "nest", "light" },
		["둥지 · 지옥"] = { "nest", "dark" },
		["공지 씨앗"] = { "special", nil },
		["사쿠라 뽑기"] = { "sakura", nil },
	}
	local plantRows = tableRows(seed["10"], "^%d+$")

	T.test("문서 10장 식물 줄 수 = 코드 식물 수 (134), 번호가 1부터 차례대로", function()
		T.eq(#plantRows, Plants.count)
		T.eq(#plantRows, 134)
		for i, row in plantRows do
			T.eq(tonumber(row[1]), i, "번호")
		end
	end)

	T.test(
		"모든 식물: 문서 순서대로 구역·이름(씨앗 이름)·영어·등급·출처·쪽이 코드와 같음",
		function()
			for i, row in plantRows do
				local plant = Plants.list[i]
				T.truthy(plant ~= nil, i .. "번 식물이 코드에 없음")
				local biomeN, biomeName = string.match(row[2], "^(%d+) (.+)$")
				T.eq(Biomes.list[tonumber(biomeN)].id, plant.biome, plant.id .. " 구역")
				T.eq(biomeIdByName[biomeName], plant.biome, plant.id .. " 구역 이름 " .. biomeName)
				local name, seedName = string.match(row[3], "^(.-) %((.+)%)$")
				name = name or row[3]
				T.eq(name, plant.name, i .. "번 이름")
				if seedName then
					T.eq(plant.seedName, seedName, plant.id .. " 씨앗 이름")
					T.eq(Plants.seedName(plant.id), seedName)
				else
					T.eq(plant.seedName, nil, plant.id .. " 씨앗 이름은 '이름 씨앗'")
					T.eq(Plants.seedName(plant.id), plant.name .. " 씨앗")
				end
				T.eq(row[4], plant.nameEn, plant.id .. " 영어 이름")
				T.eq(rarityIdByName[row[5]], plant.rarity, plant.id .. " 등급 (문서 " .. row[5] .. ")")
				local source = SOURCES[row[6]]
				T.truthy(source, plant.id .. " 모르는 출처 " .. row[6])
				T.eq(plant.source, source[1], plant.id .. " 출처")
				T.eq(plant.side, source[2], plant.id .. " 쪽")
			end
		end
	)

	T.test(
		"모든 식물: 성체까지 시간·열매 간격·열매 값(표시 = Format.number)이 코드와 같음",
		function()
			for i, row in plantRows do
				local plant = Plants.list[i]
				T.eq(parseDuration(row[7]), plant.growSeconds, plant.id .. " 성체까지 (" .. row[7] .. ")")
				T.eq(plant.hatchSeconds, plant.growSeconds, plant.id .. " hatchSeconds 별칭")
				T.eq(parseDuration(row[8]), plant.fruitIntervalSeconds, plant.id .. " 열매 간격")
				T.eq(row[9], Format.number(plant.fruitValue), plant.id .. " 열매 값")
				T.near(parseNumber(row[9]), plant.fruitValue, plant.fruitValue * 0.05, plant.id .. " 열매 값 크기")
				T.near(plant.income, plant.fruitValue / plant.fruitIntervalSeconds, 1e-9, plant.id .. " 초당 환산")
			end
		end
	)

	T.test(
		"같은 구역 둥지 식물은 문서 순서대로 등급이 내려가지 않음 (오타로 순서 뒤집힌 곳 찾기)",
		function()
			for _, biome in Biomes.list do
				local prev = { light = 0, dark = 0, none = 0 }
				for _, plant in Plants.inBiome(biome.id) do
					if plant.source == "nest" then
						local key = plant.side or "none"
						local order = Rarities.order(plant.rarity)
						T.truthy(order >= prev[key], biome.id .. " " .. plant.id .. " 등급 순서")
						prev[key] = order
					end
				end
			end
		end
	)

	T.test(
		"구역마다 둥지 식물 8종 (천사 & 악마는 쪽마다 8종), 튜토리얼 강아지풀 3초",
		function()
			for _, biome in Biomes.list do
				local counts = { light = 0, dark = 0, none = 0 }
				for _, plant in Plants.inBiome(biome.id) do
					if plant.source == "nest" then
						local key = plant.side or "none"
						counts[key] += 1
					end
				end
				if biome.id == "angels_demons" then
					T.eq(counts.light, 8, "천국 8")
					T.eq(counts.dark, 8, "지옥 8")
				else
					T.eq(counts.none, 8, biome.id .. " 둥지 8")
				end
			end
			T.eq(Plants.get("puppy_grass").growSeconds, 3)
			T.eq(Plants.get("puppy_grass").biome, "forest")
		end
	)

	T.test(
		"공지 씨앗 = EggSpawn.EXTRA_SPECIALS, 사쿠라 뽑기 = Config.SAKURA_SEEDS (문서 9장 확률도 같음)",
		function()
			local specials, sakura = {}, {}
			for _, plant in Plants.list do
				if plant.source == "special" then
					specials[plant.id] = true
				elseif plant.source == "sakura" then
					sakura[plant.id] = true
				end
			end
			local n = 0
			for _, entry in EggSpawn.EXTRA_SPECIALS do
				T.truthy(specials[entry.petId], entry.petId .. " 는 공지 씨앗")
				local plant = Plants.get(entry.petId)
				local rarityName = Rarities.get(plant.rarity).name
				local text = plant.name .. "(" .. rarityName .. ") " .. pct(entry.chance)
				T.truthy(hasText(SEED, text), "SEED 9장에 '" .. text .. "'")
				n += 1
			end
			local specialCount = 0
			for _ in specials do
				specialCount += 1
			end
			T.eq(n, specialCount, "공지 씨앗 수")
			local total = 0
			for _, entry in Config.SAKURA_SEEDS do
				T.truthy(sakura[entry.plantId], entry.plantId .. " 는 사쿠라 뽑기")
				local plant = Plants.get(entry.plantId)
				local text = plant.seedName .. " " .. pct(entry.chance)
				T.truthy(hasText(SEED, text), "SEED 9장에 '" .. text .. "'")
				total += entry.chance
			end
			T.near(total, 1, 1e-12)
			T.truthy(hasText(SEED, "크리스탈 " .. Config.SAKURA_DRAW_COST .. "개 → 특별 씨앗 뽑기"))
			T.truthy(
				hasText(SEED, "초기화 특별 추첨 " .. pct(EggSpawn.SPECIAL_CHANCE_PER_RESET.super_ultradivine)),
				"슈퍼 울트라디바인 확률"
			)
		end
	)

	------------------------------------------------------------------
	T.suite("SEED 11장 ↔ Rarities (등급 11개)")

	T.test(
		"11개: 순서·id·한국어·아우라·기준 성장 시간·식물 수·열매 간격·열매 값 범위·건너뛰기 배수·크리스탈·도감 속도",
		function()
			local rows = tableRows(seed["11"], "^%d+$")
			T.eq(#rows, 11)
			T.eq(#Rarities.list, 11)
			T.eq(Rarities.get("eternal"), nil, "eternal → eternity 로 바뀜")
			for i, row in rows do
				local rarity = Rarities.list[i]
				T.eq(tonumber(row[1]), rarity.order)
				T.eq(row[2], rarity.id)
				T.eq(row[3], rarity.name)
				T.eq(row[4], rarity.aura, rarity.id .. " 아우라")
				T.eq(parseDuration(row[5]), rarity.baseGrowSeconds, rarity.id .. " 기준 성장 시간")
				local count, minI, maxI, minV, maxV = 0, math.huge, 0, math.huge, 0
				for _, plant in Plants.list do
					if plant.rarity == rarity.id then
						count += 1
						minI = math.min(minI, plant.fruitIntervalSeconds)
						maxI = math.max(maxI, plant.fruitIntervalSeconds)
						minV = math.min(minV, plant.fruitValue)
						maxV = math.max(maxV, plant.fruitValue)
					end
				end
				T.eq(tonumber(row[6]), count, rarity.id .. " 식물 수")
				local interval = if minI == maxI then minI .. "초" else minI .. "~" .. maxI .. "초"
				T.eq(row[7], interval, rarity.id .. " 열매 간격 범위")
				local value = if minV == maxV
					then Format.number(minV)
					else Format.number(minV) .. " ~ " .. Format.number(maxV)
				T.eq(row[8], value, rarity.id .. " 열매 값 범위")
				T.eq(row[9], "×" .. Config.SKIP_RARITY_MULTIPLIER[rarity.id], rarity.id .. " 건너뛰기 배수")
				T.eq(tonumber(row[10]), Config.SAKURA_OFFER_CRYSTALS[rarity.id], rarity.id .. " 크리스탈")
				T.eq(tonumber(row[11]), Index.RARITY_SPEED[rarity.id], rarity.id .. " 도감 속도")
			end
		end
	)

	T.test("등급이 높을수록 열매 값 ↑ · 열매 간격 ↓ (등급 사이 겹치지 않음)", function()
		local prevMax, prevMinInterval = 0, math.huge
		for _, rarity in Rarities.list do
			local minV, maxV, maxI, minI = math.huge, 0, 0, math.huge
			for _, plant in Plants.list do
				if plant.rarity == rarity.id then
					minV = math.min(minV, plant.fruitValue)
					maxV = math.max(maxV, plant.fruitValue)
					maxI = math.max(maxI, plant.fruitIntervalSeconds)
					minI = math.min(minI, plant.fruitIntervalSeconds)
				end
			end
			T.truthy(minV > prevMax, rarity.id .. " 열매 값이 아래 등급보다 큼")
			T.truthy(maxI <= prevMinInterval, rarity.id .. " 열매 간격이 아래 등급보다 길지 않음")
			prevMax, prevMinInterval = maxV, minI
		end
	end)

	------------------------------------------------------------------
	T.suite("SEED 13장 ↔ Mutations (자연 3 + 원소 3)")

	T.test(
		"6종: 이름(id)·열매 값 배율·묶음·자연 등장·먹이기 확률·먹이기 구역(×3)이 같음",
		function()
			local GROUPS = { ["자연"] = "natural", ["원소"] = "element" }
			local function percentOrZero(cell)
				if cell == "-" then
					return 0
				end
				return tonumber(string.match(cell, "^([%d%.]+)%%$")) / 100
			end
			local checked = 0
			for _, line in seed["13"] do
				local cells = splitCells(line)
				if cells and cells[2] and hasText(cells[2], "×") then
					local name, id = string.match(cells[1], "^(.-) %((%w+)%)$")
					local mutation = Mutations.get(id)
					T.truthy(mutation, "모르는 돌연변이 " .. cells[1])
					T.eq(mutation.name, name, id .. " 이름")
					T.eq(parseNumber(cells[2]), mutation.multiplier, id .. " 배율")
					T.eq(GROUPS[cells[3]], mutation.group, id .. " 묶음")
					T.near(percentOrZero(cells[4]), mutation.naturalChance, 1e-12, id .. " 자연 등장")
					T.near(percentOrZero(cells[5]), mutation.feedChance or 0, 1e-12, id .. " 먹이기 확률")
					local biomes = {}
					if cells[6] ~= "-" then
						for _, biomeName in splitDot(cells[6]) do
							T.truthy(biomeIdByName[biomeName], "모르는 구역 " .. biomeName)
							table.insert(biomes, biomeIdByName[biomeName])
						end
					end
					T.eq(
						table.concat(biomes, ","),
						table.concat(mutation.feedBiomes or {}, ","),
						id .. " 먹이기 구역"
					)
					checked += 1
				end
			end
			T.eq(checked, #Mutations.list, "문서의 돌연변이 6종 전부 확인")
			T.eq(#Mutations.list, 6)
		end
	)

	T.test("먹이기 보너스 숫자: 그 구역 열매 ×3, 등급 보너스 0.1, 상한 90%", function()
		T.eq(Mutations.FEED_BIOME_BONUS, 3)
		T.truthy(hasText(SEED, "이 구역 열매면 ×" .. Mutations.FEED_BIOME_BONUS))
		T.truthy(hasText(SEED, "(등급 순서 - 1) × " .. Mutations.FEED_RARITY_BONUS_PER_ORDER))
		T.truthy(hasText(SEED, "합 상한 " .. pct(Mutations.FEED_MAX_CHANCE)))
	end)

	------------------------------------------------------------------
	T.suite("SEED 14장 ↔ Config (정원·열매·건너뛰기·러닝머신)")

	local configRows = {}
	for _, line in seed["14"] do
		local cells = splitCells(line)
		if cells and #cells == 2 and cells[1] ~= "이름" and not startsWith(cells[1], "---") then
			configRows[cells[1]] = (string.gsub(cells[2], "%*", ""))
		end
	end

	T.test("성장 단계 새싹 0% · 줄기 25% · 봉오리 60% · 성체 100%", function()
		local parts = splitDot(configRows["성장 단계"])
		T.eq(#parts, #Config.GROWTH_STAGES)
		for i, part in parts do
			local name, percent = string.match(part, "^(.-) (%d+)%%$")
			T.eq(name, Config.GROWTH_STAGES[i].name, "단계 " .. i .. " 이름")
			T.near(tonumber(percent) / 100, Config.GROWTH_STAGES[i].from, 1e-12, "단계 " .. i .. " 시작")
		end
	end)

	T.test("열매·정원·건너뛰기·자동 수입·튜토리얼 숫자", function()
		T.eq(parseNumber(configRows["밤 성장 배율"]), Config.NIGHT_GROWTH_MULTIPLIER)
		T.eq(parseNumber(configRows["열매 최대 (식물마다)"]), Config.FRUIT_MAX_PER_PLANT)
		T.eq(parseNumber(configRows["성체가 될 때 달린 열매"]), Config.FRUITS_ON_ADULT)
		T.eq(parseNumber(configRows["열매 가방 최대"]), Config.FRUIT_BAG_MAX)
		T.eq(configRows["성체 뽑아서 팔기"], "열매 1개 값 × " .. Config.PLANT_SELL_FRUIT_MULTIPLIER)
		T.truthy(startsWith(configRows["건너뛰기"], "남은 1분당 " .. Config.SKIP_COINS_PER_MINUTE .. " 코인"))
		T.eq(parseNumber(configRows["자동 수입"]), Config.PASSIVE_INCOME_PER_SECOND)
		T.eq(Config.PASSIVE_INCOME_PER_SECOND, 0)
		local fromSlots, toSlots = string.match(configRows["정원 칸"], "^(%d+) → (%d+)")
		T.eq(tonumber(fromSlots), Upgrades.Pen[1].slots)
		T.eq(tonumber(toSlots), Upgrades.Pen[#Upgrades.Pen].slots)
		T.eq(parseNumber(configRows["튜토리얼 보상"]), Tutorial.REWARD_MONEY)
	end)

	T.test(
		"러닝머신 최대 1초 1M: 문서의 최대 레벨 = 코드 레벨 수, 최대 레벨 1초 속도 = 정확히 1,000,000",
		function()
			local maxLevel, perSecond =
				string.match(configRows["러닝머신"], "^최대 (%d+)레벨 = 1초에 속도 ([%d,]+)")
			T.eq(tonumber(maxLevel), #Upgrades.Treadmill)
			T.eq(parseNumber(perSecond), 1000000)
			T.eq(Economy.treadmillGainPerSecond(#Upgrades.Treadmill), 1000000)
			T.truthy(hasText(SEED, "러닝머신 최대 1초 1M"), "SEED 문서에 사장님 지시 줄")
			T.truthy(hasText(DOC, "러닝머신 최대 1초 1M"), "GAME_DESIGN 9-2 에도")
		end
	)

	------------------------------------------------------------------
	T.suite("GAME_DESIGN 7장 ↔ Sizes")

	T.test(
		"7장 크기 표: 등장 확률·배율(6판: 열매 값)·속도 감소가 같고 확률 합은 100%",
		function()
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
				T.eq(tonumber(string.match(cells[3], "×([%d%.]+)")), size.incomeMultiplier, size.id .. " 배율")
				T.near(
					tonumber(string.match(cells[4], "%-(%d+)%%")) / 100,
					size.speedPenalty,
					1e-12,
					size.id .. " 속도 감소"
				)
			end
			T.eq(total, 100)
		end
	)

	------------------------------------------------------------------
	T.suite("GAME_DESIGN 9장 ↔ Upgrades (정원 칸·러닝머신·트레일 가격표)")

	T.test("9-1 정원 칸(5판 우리 표): 11단계 비용·칸 수가 같음 (1단계는 무료 7칸)", function()
		local rows = tableRows(subsection(sections["9"], "9-1"), "^%d+$")
		T.eq(#rows, 11, "표 줄 수")
		for i, cells in rows do
			local level = Upgrades.Pen[i]
			T.eq(tonumber(cells[1]), level.level)
			T.eq(if cells[2] == "무료" then 0 else parseNumber(cells[2]), level.cost, i .. "레벨 비용")
			T.eq(tonumber(string.match(cells[3], "^(%d+)")), level.slots, i .. "레벨 칸 수")
		end
	end)

	T.test(
		"9-2 러닝머신: 20단계 비용·걸음당 속도·1초 속도가 같음 (1단계 = 해금 $1,000, 20단계 1,000,000)",
		function()
			local rows = tableRows(subsection(sections["9"], "9-2"), "^%d+$")
			T.eq(#rows, #Upgrades.Treadmill)
			T.eq(#rows, 20)
			for i, cells in rows do
				local level = Upgrades.Treadmill[i]
				T.eq(tonumber(cells[1]), level.level)
				T.eq(parseNumber(string.match(cells[2], "%$[%w%.,]+")), level.cost, i .. "레벨 비용")
				T.eq(parseNumber(cells[3]), level.perStep, i .. "레벨 걸음당 속도")
				T.eq(parseNumber(cells[4]), Economy.treadmillGainPerSecond(i), i .. "레벨 1초 속도")
			end
			T.truthy(hasText(rows[#rows][3], "(최대)"))
			T.eq(parseNumber(rows[#rows][4]), 1000000)
			T.truthy(hasText(DOC, "정원 업그레이드 **$1,000** 으로 러닝머신 해금"))
		end
	)

	T.test("9-3 트레일: 16개 이름·배율·가격이 같음", function()
		local rows = {}
		for _, line in subsection(sections["9"], "9-3") do
			local cells = splitCells(line)
			if cells and cells[2] and hasText(cells[2], "×") then
				table.insert(rows, cells)
			end
		end
		T.eq(#rows, 16)
		for i, cells in rows do
			local trail = Upgrades.Trails[i]
			T.truthy(startsWith(cells[1], trail.name), trail.id .. " 이름")
			T.truthy(hasText(cells[1], trail.nameEn), trail.id .. " 영어 이름")
			T.eq(tonumber(string.match(cells[2], "×([%d%.]+)")), trail.multiplier, trail.id .. " 배율")
			T.eq(parseNumber(cells[3]), trail.cost, trail.id .. " 가격")
		end
	end)

	T.test(
		"9-5 도감 보상 예시(아기 데이지·이끼 고사리·부엉이 참나무)가 Index.reward 와 같음",
		function()
			local examples = {
				{ "sprout_daisy", "+420", "+100" },
				{ "mossy_fern", "+520", "+360" },
				{ "owl_oak", "+620", "+1,800" },
			}
			for _, e in examples do
				local plant = Plants.get(e[1])
				local pattern = escapePattern(plant.name .. " " .. e[2] .. " 속도 " .. e[3] .. " 코인")
				T.truthy(string.find(DOC, pattern), "문서 예시 못 찾음: " .. plant.name)
				local reward = Index.reward(plant.rarity, plant.fruitValue, Biomes.get(plant.biome).recommendedSpeed)
				T.eq(reward.speed, parseNumber(e[2]), e[1] .. " 속도 보상")
				T.eq(reward.money, parseNumber(e[3]), e[1] .. " 코인 보상")
			end
		end
	)

	------------------------------------------------------------------
	T.suite("GAME_DESIGN 흩어진 숫자 ↔ Config (6판에서 없앤 것 포함)")

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
		T.truthy(hasText(DOC, "알이 **30배** 빨리 자랍니다"))
		T.eq(Config.NIGHT_GROWTH_MULTIPLIER, 30)
	end)

	T.test(
		"서버 7명, 곰덫 5초 / 6판: 성장 G배·무료 보상·퓨전·제단·자동 수입 없음",
		function()
			T.truthy(hasText(DOC, "서버당 최대 **7명**"))
			T.eq(Config.MAX_PLAYERS, 7)
			T.eq(Config.PLOT_COUNT, 7)
			T.truthy(hasText(DOC, "**5초** 묶임"))
			T.eq(Config.BEAR_TRAP_STUN_SECONDS, 5)
			T.truthy(hasText(DOC, "`GROWTH_MULTIPLIER` 는 없앰"))
			T.eq(Config.GROWTH_MULTIPLIER, nil)
			T.truthy(hasText(DOC, "**무료 보상** — **(5판에서 제거됨"))
			T.eq(Config.FREE_REWARD_SPEED, nil)
			T.truthy(hasText(DOC, "### 9-4. 퓨전 머신 — **(6판에서 삭제됨"))
			T.falsy(fs.isFile("src/shared/FusionRules.luau"), "FusionRules 삭제")
			T.falsy(fs.isFile("src/shared/AltarRules.luau"), "AltarRules 삭제")
			T.falsy(fs.isFile("src/server/Services/FusionService.luau"))
			T.falsy(fs.isFile("src/server/Services/AltarService.luau"))
			T.falsy(fs.isFile("src/server/Services/IncomeService.luau"), "자동 수입 서비스 삭제")
			T.falsy(fs.isFile("src/server/Services/RewardService.luau"))
		end
	)

	T.test("GAME_DESIGN 3장: 신성 등장 확률 약 0.2%", function()
		T.truthy(hasText(DOC, "약 **0.2%**"))
		T.eq(EggSpawn.SPECIAL_CHANCE_PER_RESET.divine, 0.002)
	end)

	T.test("GAME_DESIGN 4장: 구역마다 둥지 8개", function()
		T.truthy(hasText(DOC, "둥지 8개"))
		T.eq(Config.NESTS_PER_BIOME, 8)
		for _, biome in Biomes.list do
			T.eq(biome.nests, 8, biome.id)
		end
	end)
end
