--!nocheck
-- 설계서 (docs/DESIGN.md) = 코드: 3장 물건 표 · 9장 숫자 표 · 7장 Remote/Attribute 이름
return function(T, Loader)
	local fs = require("@lune/fs")
	local Targets = Loader.require("ReplicatedStorage/Shared/Data/Targets")
	local Dumbbells = Loader.require("ReplicatedStorage/Shared/Data/Dumbbells")
	local Belts = Loader.require("ReplicatedStorage/Shared/Data/Belts")
	local Worlds = Loader.require("ReplicatedStorage/Shared/Data/Worlds")
	local Remotes = Loader.require("ReplicatedStorage/Shared/Remotes")
	local Tags = Loader.require("ReplicatedStorage/Shared/Tags")

	local path = if fs.isFile("games/boardbreak/docs/DESIGN.md")
		then "games/boardbreak/docs/DESIGN.md"
		else "docs/DESIGN.md"
	local doc = fs.readFile(path)

	-- "## N." 부터 다음 "## " 전까지
	local function section(n: number): string
		local start = string.find(doc, "\n## " .. n .. "%.")
		assert(start, "설계서 " .. n .. "장 없음")
		local stop = string.find(doc, "\n## ", start + 4)
		return string.sub(doc, start, (stop or #doc + 1) - 1)
	end

	-- 표 줄 → 칸 목록 (첫 칸이 숫자인 줄만)
	local function rows(text: string, after: string?): { { string } }
		local list = {}
		local body = text
		if after then
			local at = string.find(text, after, 1, true)
			assert(at, "표 제목 없음: " .. after)
			body = string.sub(text, at)
			local nextHeading = string.find(body, "\n###", 2)
			if nextHeading then
				body = string.sub(body, 1, nextHeading)
			end
		end
		for line in string.gmatch(body, "[^\n]+") do
			if string.match(line, "^|%s*%d+%s*|") then
				local cells = {}
				for cell in string.gmatch(string.sub(line, 2), "([^|]*)|") do
					table.insert(cells, (string.gsub(cell, "^%s*(.-)%s*$", "%1")))
				end
				table.insert(list, cells)
			end
		end
		return list
	end

	-- "1,024" · "4M" · "16Qa" · "1Sp" → 숫자
	local UNIT = {
		K = 1e3,
		M = 1e6,
		B = 1e9,
		T = 1e12,
		Qa = 1e15,
		Qi = 1e18,
		Sx = 1e21,
		Sp = 1e24,
		Oc = 1e27,
		No = 1e30,
		Dc = 1e33,
	}
	local function parseValue(text: string): number?
		local plain = string.gsub(text, ",", "")
		local n = tonumber(plain)
		if n then
			return n
		end
		local num, unit = string.match(plain, "^([%d%.]+)(%a+)$")
		if num and UNIT[unit] then
			return tonumber(num) * UNIT[unit]
		end
		return nil
	end

	local function near(a: number, b: number): boolean
		return math.abs(a - b) <= math.abs(b) * 1e-9
	end
	local function near3(a: number, b: number): boolean
		return math.abs(a - b) <= math.abs(b) * 5e-3 -- 3자리 반올림 칸
	end

	T.suite("design_doc")

	T.test("3장 물건 표 41줄 = Targets (id · 이름 · 월드 · 값)", function()
		local list = rows(section(3))
		T.eq(#list, 41, "줄 수")
		for i, cells in list do
			local t = Targets.list[i]
			T.eq(tonumber(cells[1]), i, "번호")
			T.eq(cells[2], t.id, "id " .. i)
			T.eq(cells[3], t.name, "이름 " .. t.id)
			T.eq(tonumber(cells[4]), t.world, "월드 " .. t.id)
			T.truthy(near(parseValue(cells[5]), t.reward), "값 " .. t.id .. " " .. cells[5])
		end
	end)

	T.test("9-1 물건 추천 힘 · hp = Targets", function()
		local list = rows(section(9), "### 9-1")
		T.eq(#list, 41)
		for i, cells in list do
			local t = Targets.list[i]
			T.eq(cells[2], t.id)
			T.truthy(near(tonumber(cells[3]), t.recommendPower), t.id .. " 추천 힘 " .. cells[3])
			T.truthy(near(tonumber(cells[4]), t.hp), t.id .. " hp " .. cells[4])
		end
	end)

	T.test("9-2 아령 weightKg · powerPerRep · price = Dumbbells (개수도)", function()
		local list = rows(section(9), "### 9-2")
		T.eq(#list, Dumbbells.COUNT)
		T.truthy(string.find(section(9), "### 9-2. 아령 " .. Dumbbells.COUNT .. "개", 1, true), "제목의 개수")
		T.truthy(string.find(section(7), "/dumbbell <1-N>", 1, true), "7장 개발 명령 /dumbbell <1-N>")
		for i, cells in list do
			local d = Dumbbells.list[i]
			T.eq(cells[2], d.id)
			T.eq(cells[3], d.name)
			T.truthy(near3(tonumber(cells[4]), d.weightKg), d.id .. " weightKg")
			T.truthy(near(tonumber(cells[5]), d.powerPerRep), d.id .. " powerPerRep")
			T.truthy(near(tonumber(cells[6]), d.price), d.id .. " price")
		end
	end)

	T.test("9-3 띠 배율 · needPower · 송판 = Belts", function()
		local list = rows(section(9), "### 9-3")
		T.eq(#list, 12)
		for i, cells in list do
			local b = Belts.list[i]
			T.eq(cells[2], b.id)
			T.eq(tonumber(cells[4]), b.moneyMultiplier, b.id .. " 배율")
			T.truthy(near(tonumber(cells[5]), b.needPower), b.id .. " needPower")
			T.eq(cells[6], if i == 1 then "처음" elseif b.duel then "대결" else "심사", b.id .. " 받는 법")
			local boardHp = if b.duel then b.duelBoardHp else b.examBoardHp
			T.truthy(boardHp == 0 and tonumber(cells[7]) == 0 or near3(tonumber(cells[7]), boardHp), b.id .. " 송판")
		end
	end)

	T.test("9-4 시험관 = Worlds", function()
		local list = rows(section(9), "### 9-4")
		T.eq(#list, 3)
		for i, cells in list do
			local w = Worlds.list[i]
			T.eq(cells[2], w.examiner)
			T.eq(tonumber(cells[3]), w.examinerSecondsPerBoard)
			T.truthy(near3(tonumber(cells[5]), w.duelBoardHp), "대결 송판 " .. i)
		end
	end)

	T.test("7장 Remote 이름이 Remotes.luau 에 있음 (양쪽 다)", function()
		local s7 = section(7)
		for name in Remotes.ToServer do
			T.truthy(string.find(s7, "`" .. name .. "(", 1, true), "클라→서버 " .. name)
		end
		for name in Remotes.ToClient do
			T.truthy(
				string.find(s7, "`" .. name .. " {", 1, true) or string.find(s7, "`" .. name .. "(", 1, true),
				"서버→클라 " .. name
			)
		end
		T.truthy(string.find(s7, '`Hit("exam")`', 1, true), "심사 치기 id 적혀 있음")
		T.eq(Remotes.EXAM_TARGET, "exam")
		T.eq(Remotes.DUEL_TARGET, "duel")
	end)

	T.test("7장 플레이어 Attribute · 태그 이름이 Tags.luau 에 있음", function()
		local s7 = section(7)
		for _, name in Tags.PlayerAttributes do
			T.truthy(string.find(s7, "`" .. name .. "`", 1, true), "Attribute " .. name)
		end
		for _, tag in { "BreakTarget", "ExamPad", "DuelArena", "DumbbellShop", "BeltBoard", "TrainMat" } do
			T.eq(Tags[tag], tag, "태그 " .. tag)
			T.truthy(string.find(s7, "`" .. tag .. "`", 1, true), "설계서에 " .. tag)
		end
		T.eq(Tags.PartAttributes.TargetId, "TargetId")
	end)
end
