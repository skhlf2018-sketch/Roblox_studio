--!nocheck
--[[
	참조 검사 ("오타 하나가 조용히 nil 이 되는" 곳 찾기):
	  Lua/Luau 는 없는 열쇠를 읽어도 오류 없이 nil 을 줍니다. 그래서 Config.오타, Tags.오타, Remotes.오타 는
	  스튜디오에서 한참 뒤에야 "그냥 안 되는" 모습으로 나타납니다. 소스 글자를 직접 읽어서 미리 찾습니다.

	  1) Remote 이름: shared/Remotes ↔ docs/REMOTES.md ↔ 서버 처리/전송 ↔ 클라 전송/수신 (인자 순서는 서비스 테스트가 확인)
	  2) Config / Tags / Attribute / 소리 이름 / 창 이름이 실제로 있는 이름인지
	  3) 겉모습 데이터(Visuals) ↔ 펫·구역·돌연변이, 장식/체형 이름이 서버 코드에 구현돼 있는지
	  4) 서버 진입점(Main.server)이 모든 서비스를 시작하는지, 클라 진입점이 모든 컨트롤러를 시작하는지
	  5) 위험한 버릇: 옛 전역 wait/spawn, 시간 안 쉬는 무한 루프, 시간 제한 없는 WaitForChild(서버)
]]

local fs = require("@lune/fs")

return function(T, Loader)
	local Remotes = Loader.require("ReplicatedStorage/Shared/Remotes")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")
	local Tags = Loader.require("ReplicatedStorage/Shared/Tags")
	local Pets = Loader.require("ReplicatedStorage/Shared/Data/Pets")
	local Biomes = Loader.require("ReplicatedStorage/Shared/Data/Biomes")
	local Rarities = Loader.require("ReplicatedStorage/Shared/Data/Rarities")
	local Mutations = Loader.require("ReplicatedStorage/Shared/Data/Mutations")
	local Sounds = Loader.require("ReplicatedStorage/Shared/Data/Sounds")
	local Visuals = Loader.require("ReplicatedStorage/Shared/Data/Visuals")

	------------------------------------------------------------------
	-- 소스 읽기 도우미
	------------------------------------------------------------------
	local function walk(dir, out)
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, out)
			elseif string.sub(name, -5) == ".luau" then
				out[path] = fs.readFile(path)
			end
		end
		return out
	end

	local SRC = walk("src", {})
	local function filesUnder(prefix)
		local list = {}
		for path, text in SRC do
			if string.sub(path, 1, #prefix) == prefix then
				list[path] = text
			end
		end
		return list
	end
	local SERVER = filesUnder("src/server/")
	local CLIENT = filesUnder("src/client/")

	local function setOf(map)
		local set = {}
		for _, v in map do
			set[v] = true
		end
		return set
	end

	local function sorted(set)
		local list = {}
		for k in set do
			table.insert(list, k)
		end
		table.sort(list)
		return list
	end

	-- 파일들에서 패턴에 걸리는 첫 번째 캡처를 모두 모음 (이름 → 처음 나온 파일)
	local function scan(files, pattern)
		local found = {}
		for path, text in files do
			for name in string.gmatch(text, pattern) do
				found[name] = found[name] or path
			end
		end
		return found
	end

	-- 주석(--[[ ... ]] 덩어리와 줄 끝 --)을 지운 코드만. 줄 수는 유지(줄 번호가 안 어긋나게).
	local function stripComments(text)
		local noBlocks = string.gsub(text, "%-%-%[(=*)%[(.-)%]%1%]", function(_, body)
			return (string.gsub(body, "[^\n]", ""))
		end)
		local out = {}
		for line in string.gmatch(noBlocks .. "\n", "(.-)\n") do
			local code = string.gsub(line, "%-%-.*$", "")
			table.insert(out, code)
		end
		return table.concat(out, "\n")
	end

	-- scan 과 같지만 주석은 빼고 찾음
	local function scanCode(files, pattern)
		local found = {}
		for path, text in files do
			for name in string.gmatch(stripComments(text), pattern) do
				found[name] = found[name] or path
			end
		end
		return found
	end

	------------------------------------------------------------------
	T.suite("참조: Remote 이름 (Remotes.luau ↔ REMOTES.md ↔ 서버 ↔ 클라)")

	local REMOTES_DOC = fs.readFile("docs/REMOTES.md")
	local docSections = {}
	do
		local current = nil
		for line in string.gmatch(REMOTES_DOC .. "\n", "(.-)\r?\n") do
			local number = string.match(line, "^## (%d+)%.")
			if number then
				current = number
				docSections[current] = {}
			elseif current then
				table.insert(docSections[current], line)
			end
		end
	end

	local function docRemoteRows(section)
		local rows = {}
		for _, line in docSections[section] do
			local first = string.match(line, "^|%s*([^|]+)|")
			local name = first and string.match(first, "`(%w+)`")
			if name then
				table.insert(rows, { name = name, line = line })
			end
		end
		return rows
	end

	T.test(
		"REMOTES.md 1장 표 = Remotes.ToClient, 2장 표 = Remotes.ToServer (이름이 한 글자도 안 다름)",
		function()
			local docClient, docServer = {}, {}
			for _, row in docRemoteRows("1") do
				docClient[row.name] = true
			end
			for _, row in docRemoteRows("2") do
				docServer[row.name] = true
			end
			local codeClient, codeServer = setOf(Remotes.ToClient), setOf(Remotes.ToServer)
			for name in codeClient do
				T.truthy(docClient[name], "REMOTES.md 1장에 없음: " .. name)
			end
			for name in docClient do
				T.truthy(codeClient[name], "코드(Remotes.ToClient)에 없음: " .. name)
			end
			for name in codeServer do
				T.truthy(docServer[name], "REMOTES.md 2장에 없음: " .. name)
			end
			for name in docServer do
				T.truthy(codeServer[name], "코드(Remotes.ToServer)에 없음: " .. name)
			end
			T.eq(#sorted(codeClient), 19)
			T.eq(#sorted(codeServer), 14)
		end
	)

	T.test("REMOTES.md 2장의 레이트 리밋 숫자(burst / 초당) = Remotes.RateLimits", function()
		for _, row in docRemoteRows("2") do
			local burst, per = string.match(row.line, "(%d+) / ([%d%.]+)%s*|%s*$")
			T.truthy(burst, row.name .. " 줄 끝에서 레이트 리밋을 못 읽음")
			local limit = Remotes.RateLimits[row.name]
			T.truthy(limit, row.name)
			T.eq(tonumber(burst), limit.burst, row.name .. " burst")
			T.eq(tonumber(per), limit.perSecond, row.name .. " perSecond")
		end
	end)

	T.test(
		"코드에서 쓰는 Remotes.ToClient.X / Remotes.ToServer.X 는 전부 실제 이름 (서버·클라 모두)",
		function()
			for path, text in SRC do
				if path ~= "src/shared/Remotes.luau" then
					local code = stripComments(text)
					for name in string.gmatch(code, "Remotes%.ToClient%.([%w_]+)") do
						T.truthy(Remotes.ToClient[name], path .. ": Remotes.ToClient." .. name .. " 는 없는 이름")
					end
					for name in string.gmatch(code, "Remotes%.ToServer%.([%w_]+)") do
						T.truthy(Remotes.ToServer[name], path .. ": Remotes.ToServer." .. name .. " 는 없는 이름")
					end
					if string.find(code, "local E = Remotes.ToClient", 1, true) then
						for name in string.gmatch(code, "[^%w_%.]E%.([%w_]+)") do
							T.truthy(
								Remotes.ToClient[name],
								path .. ": E." .. name .. " 는 ToClient 에 없는 이름"
							)
						end
					end
				end
			end
		end
	)

	T.test("클라→서버 Remote 14개 전부 서버에 처리기(Net.on)가 있음", function()
		local handled = scan(SERVER, "Net%.on%(%s*Remotes%.ToServer%.([%w_]+)")
		for name in Remotes.ToServer do
			T.truthy(handled[name], name .. " 를 받는 Net.on 이 서버에 없음")
		end
		for name in handled do
			T.truthy(Remotes.ToServer[name], name)
		end
	end)

	T.test("서버→클라 Remote 19개 전부 서버 코드 어딘가에서 보냄 (Net.fire 에 쓰임)", function()
		local sent = scan(SERVER, "Remotes%.ToClient%.([%w_]+)")
		for name in Remotes.ToClient do
			T.truthy(sent[name], name .. " 를 보내는 코드가 서버에 없음 (죽은 Remote)")
		end
	end)

	T.test(
		"클라→서버 Remote 14개 전부 클라가 보내는 코드(UI)가 있음 (퓨전·사쿠라·제단·비밀 통로 화면 포함)",
		function()
			local sentByClient = scan(CLIENT, "Remotes%.ToServer%.([%w_]+)")
			local missing = {}
			for name in Remotes.ToServer do
				if not sentByClient[name] then
					table.insert(missing, name)
				end
			end
			table.sort(missing)
			T.eq(
				table.concat(missing, ","),
				"",
				"클라가 한 번도 안 보내는 Remote: " .. table.concat(missing, ", ")
			)
		end
	)

	T.test("클라가 받는 서버→클라 Remote 중 핵심 이벤트는 전부 수신 코드가 있음", function()
		local listened = scan(CLIENT, "Remotes%.ToClient%.([%w_]+)")
		for path, text in CLIENT do
			if string.find(text, "local E = Remotes.ToClient", 1, true) then
				for name in string.gmatch(stripComments(text), "[^%w_%.]E%.([%w_]+)") do
					listened[name] = listened[name] or path
				end
			end
			-- 2단계 Remote 는 (Remotes.ToClient :: ...).Name 이나 extra.Name 으로 받기도 함
			for name in string.gmatch(stripComments(text), "extra%.([%w_]+)") do
				listened[name] = listened[name] or path
			end
			for name in string.gmatch(stripComments(text), "%)%.([%w_]+)") do
				if Remotes.ToClient[name] then
					listened[name] = listened[name] or path
				end
			end
		end
		for _, name in
			{
				"Snapshot",
				"DataUpdate",
				"Notify",
				"Announce",
				"RunAlert",
				"ChaseEnded",
				"Caught",
				"EggDelivered",
				"HatchResult",
				"OfflineIncome",
				"IndexRewarded",
				"FusionResult",
				"EggGranted",
				"SakuraResult",
				"AltarUpdate",
				"ShrineResult",
				"PetsSold",
			}
		do
			T.truthy(listened[name], name .. " 를 받는 클라 코드가 없음")
		end
	end)

	T.test("ToolKinds: 서버가 주는 Tool 이름, 핫바 그림·이름·색이 모두 같은 9개", function()
		local hotbar = CLIENT["src/client/Controllers/HotbarController.luau"]
		T.truthy(hotbar)
		local count = 0
		for _, kind in Remotes.ToolKinds do
			count += 1
			local occurrences = 0
			for _ in string.gmatch(hotbar, "%f[%w_]" .. kind .. '%s*=%s*["C]') do
				occurrences += 1
			end
			T.truthy(
				occurrences >= 2,
				"핫바 NAMES/COLORS 에 " .. kind .. " 가 둘 다 있어야 함 (" .. occurrences .. ")"
			)
		end
		T.eq(count, 9)
	end)

	------------------------------------------------------------------
	T.suite("참조: Config / Tags / 소리 / 창 이름이 진짜 있는 이름인지")

	T.test("src 전체의 Config.X 는 전부 Config 에 있는 이름 (오타는 조용히 nil 이 됨)", function()
		local used = scanCode(SRC, "[^%w_%.]Config%.([%w_]+)")
		local count = 0
		for name, path in used do
			count += 1
			T.truthy(Config[name] ~= nil, path .. ": Config." .. name .. " 가 Config 에 없음")
		end
		T.truthy(count > 80, "Config 를 쓰는 곳이 너무 적게 잡힘 " .. count)
	end)

	T.test(
		"src 전체의 Tags.X / Tags.PlayerAttributes.X / Attr.X / StateAttr.X / Groups.X 가 진짜 있는 이름",
		function()
			local top = scanCode(SRC, "[^%w_%.]Tags%.([%w_]+)")
			for name, path in top do
				T.truthy(Tags[name] ~= nil, path .. ": Tags." .. name)
			end
			local aliases = {
				{ "Tags%.PlayerAttributes", "PlayerAttributes", { "Attr", "Attributes" } },
				{ "Tags%.StateAttributes", "StateAttributes", { "StateAttr" } },
				{ "Tags%.CollisionGroups", "CollisionGroups", { "Groups" } },
			}
			for path, text in SRC do
				local code = stripComments(text)
				for _, alias in aliases do
					for name in string.gmatch(code, alias[1] .. "%.([%w_]+)") do
						T.truthy(Tags[alias[2]][name] ~= nil, path .. ": " .. alias[1] .. "." .. name)
					end
					for _, short in alias[3] do
						if string.find(code, "local " .. short .. " = " .. alias[1], 1) then
							for name in string.gmatch(code, "[^%w_%.]" .. short .. "%.([%w_]+)") do
								T.truthy(Tags[alias[2]][name] ~= nil, path .. ": " .. short .. "." .. name)
							end
						end
					end
				end
			end
		end
	)

	T.test("src 전체의 Visuals.Tags 별명(VT.X) 도 진짜 있는 이름", function()
		for path, text in SRC do
			local code = stripComments(text)
			if string.find(code, "local VT = Visuals.Tags", 1, true) then
				for name in string.gmatch(code, "[^%w_%.]VT%.([%w_]+)") do
					T.truthy(Visuals.Tags[name] ~= nil, path .. ": VT." .. name)
				end
			end
			for name in string.gmatch(code, "Visuals%.Tags%.([%w_]+)") do
				T.truthy(Visuals.Tags[name] ~= nil, path .. ": Visuals.Tags." .. name)
			end
		end
	end)

	T.test(
		"클라가 재생하는 소리 이름(SoundController.play / sound = / setMusic)은 전부 Sounds.luau 에 있음",
		function()
			local used = {}
			for path, text in CLIENT do
				local code = stripComments(text)
				for args in string.gmatch(code, "[%.:]play%(([^\n]-)%)") do
					for name in string.gmatch(args, '"([A-Z][%w_]*)"') do
						used[name] = used[name] or path
					end
				end
				for name in string.gmatch(code, 'sound%s*=%s*"([%w_]+)"') do
					used[name] = used[name] or path
				end
				for name in string.gmatch(code, 'setMusic%("([%w_]+)"') do
					used[name] = used[name] or path
				end
			end
			local count = 0
			for name, path in used do
				count += 1
				T.truthy(Sounds[name] ~= nil, path .. ": 소리 '" .. name .. "' 가 Sounds.luau 에 없음")
			end
			T.truthy(count >= 20, "소리 이름을 너무 적게 찾음 " .. count)
		end
	)

	T.test(
		"구역 배경음 Bgm_<구역 id> 가 구역마다 있고 '음악'으로 표시됨, Visuals.biomes[..].music 과 같음",
		function()
			for _, biome in Biomes.list do
				local def = Sounds["Bgm_" .. biome.id]
				T.truthy(def, biome.id .. " 배경음")
				T.truthy(def.music and def.looped, biome.id .. " 는 반복 음악이어야 함")
				T.eq(Visuals.biomes[biome.id].music, "Bgm_" .. biome.id)
			end
			T.truthy(Sounds.Chase.music and Sounds.Bgm_base.music)
		end
	)

	T.test("HUD 메뉴가 여는 창 이름(Windows.toggle)은 전부 컨트롤러가 등록한 이름", function()
		local registered = {}
		for _, text in CLIENT do
			local name = string.match(text, 'local NAME = "(%w+)"')
			if name and string.find(text, "Windows.register(NAME", 1, true) then
				registered[name] = true
			end
		end
		local toggles = scan(CLIENT, 'Windows%.toggle%("(%w+)"%)')
		local count = 0
		for name, path in toggles do
			count += 1
			T.truthy(registered[name], path .. ": 창 '" .. name .. "' 을 등록한 컨트롤러가 없음")
		end
		T.eq(count, 5)
	end)

	T.test("Config 안에 NaN/음수/이상한 값 없음 (숫자는 유한, 시간·거리는 0 이상)", function()
		for key, value in Config do
			if type(value) == "number" then
				T.truthy(value == value and value ~= math.huge and value ~= -math.huge, key)
				T.truthy(value >= 0, key .. " 음수")
			end
		end
		T.truthy(Config.GROWTH_MULTIPLIER >= 1)
		T.truthy(Config.WALKSPEED_MAX > Config.WALKSPEED_MIN)
		T.truthy(Config.GUARD_CHASE_MIN_RATIO < 1 and Config.GUARD_CHASE_MAX_RATIO > 1)
		T.truthy(
			Config.GUARD_CHASE_MARGIN > 0 and Config.GUARD_CHASE_MARGIN < 1,
			"마진이 1 이상이면 같은 속도에서 잡힘"
		)
		T.truthy(Config.MOVE_CHECK_KICK_WARNINGS >= 2)
		T.truthy(Config.PET_INVENTORY_MAX >= 18, "최대 우리 칸(18)보다 작으면 안 됨")
		T.truthy(Config.INCUBATOR_SLOTS >= 1 and Config.EGG_QUEUE_MAX >= 0)
		T.truthy(
			Config.SESSION_LOCK_STALE_SECONDS > Config.SESSION_LOCK_WAIT_ATTEMPTS * Config.SESSION_LOCK_WAIT_SECONDS - 1
		)
	end)

	------------------------------------------------------------------
	T.suite("참조: 겉모습 데이터(Visuals) ↔ 펫·구역 ↔ 서버 코드")

	local PETVIS = SERVER["src/server/Services/PetVisualService.luau"]
	local MAPB = SERVER["src/server/Services/MapBuilder.luau"]

	local templates = {}
	for name in string.gmatch(PETVIS, "\nTEMPLATES%.([%w_]+) =") do
		templates[name] = true
	end
	local features = {}
	for name in string.gmatch(PETVIS, "\nF%.([%w_]+) =") do
		features[name] = true
	end
	local decors = {}
	for name in string.gmatch(MAPB, "\nDECOR%.([%w_]+) =") do
		decors[name] = true
	end
	-- DECOR 표에 없이 buildDecor 안에서 따로 처리하는 종류 (kind == "heavenhell" 같은)
	for name in string.gmatch(stripComments(MAPB), 'kind == "([%w_]+)"') do
		decors[name] = true
	end

	T.test(
		"서버 코드에서 체형 템플릿 17종, 장식 70종 이상, 구역 장식 종류 50종 이상을 읽어 옴 (파서 점검)",
		function()
			T.eq(#sorted(templates), 17)
			T.truthy(#sorted(features) >= 70, #sorted(features))
			T.truthy(#sorted(decors) >= 50, #sorted(decors))
		end
	)

	T.test(
		"모든 펫(134종)에 생김새가 있고, 체형·장식이 PetVisualService 에 구현돼 있음",
		function()
			for _, pet in Pets.list do
				local look = Visuals.pets[pet.id]
				T.truthy(look, pet.id .. " 생김새 없음")
				T.truthy(templates[look.body], pet.id .. " 체형 '" .. look.body .. "' 구현 없음")
				T.eq(#look.colors, 3, pet.id)
				for _, feature in look.features do
					T.truthy(features[feature], pet.id .. " 장식 '" .. feature .. "' 구현 없음")
				end
			end
		end
	)

	T.test("경비 전용 모델(Visuals.extra)과 15구역 경비 모양이 다 있고 구현돼 있음", function()
		for id, look in Visuals.extra do
			T.truthy(templates[look.body], id .. " 체형 " .. look.body)
			for _, feature in look.features do
				T.truthy(features[feature], id .. " 장식 " .. feature)
			end
		end
		for _, biome in Biomes.list do
			local guard = Visuals.guards[biome.id]
			T.truthy(guard, biome.id .. " 경비 모양")
			T.truthy(
				Visuals.pets[guard.model] or Visuals.extra[guard.model],
				biome.id .. " 경비 모델 " .. guard.model
			)
			if guard.darkModel then
				T.truthy(
					Visuals.pets[guard.darkModel] or Visuals.extra[guard.darkModel],
					biome.id .. " 어두운 경비 모델"
				)
			end
			T.truthy(guard.scale > 0)
		end
	end)

	local VALID_MATERIALS = setOf({
		"Plastic",
		"SmoothPlastic",
		"Neon",
		"Wood",
		"WoodPlanks",
		"Marble",
		"Basalt",
		"Slate",
		"Concrete",
		"Granite",
		"Brick",
		"Pebble",
		"Cobblestone",
		"Rock",
		"Sand",
		"Fabric",
		"Glass",
		"Foil",
		"Ice",
		"Metal",
		"Grass",
		"Ground",
		"Mud",
		"Snow",
		"Salt",
		"Sandstone",
		"Limestone",
		"Asphalt",
		"Pavement",
		"Cardboard",
		"Carpet",
		"CeramicTiles",
		"ClayRoofTiles",
		"CorrodedMetal",
		"CrackedLava",
		"DiamondPlate",
		"ForceField",
		"Glacier",
		"LeafyGrass",
		"Leather",
		"Plaster",
		"Rubber",
		"RoofShingles",
		"Water",
		"Air",
	})

	T.test(
		"15개 구역 테마: 구역 장식 종류가 MapBuilder 에 구현돼 있고, 재료 이름이 진짜 Enum.Material, 배경음이 있음",
		function()
			for _, biome in Biomes.list do
				local theme = Visuals.biomes[biome.id]
				T.truthy(theme, biome.id .. " 테마 없음")
				T.truthy(VALID_MATERIALS[theme.floorMaterial], biome.id .. " 바닥 재료 " .. theme.floorMaterial)
				T.truthy(#theme.decor >= 3, biome.id .. " 장식이 너무 적음")
				for _, spec in theme.decor do
					T.truthy(decors[spec.kind], biome.id .. " 장식 '" .. spec.kind .. "' 구현 없음")
					T.truthy(
						spec.count >= 1 and spec.count <= 40,
						biome.id .. " " .. spec.kind .. " 개수 " .. spec.count
					)
				end
				T.truthy(Sounds[theme.music], biome.id .. " 배경음")
			end
		end
	)

	T.test(
		"돌연변이마다 알 껍데기 모양, 희귀도 효과 이름, 특별 알 3종, 베이스 색 7개",
		function()
			for _, mutation in Mutations.list do
				local look = Visuals.mutationLooks[mutation.id]
				T.truthy(look, mutation.id .. " 모양 없음")
				if look.material then
					T.truthy(VALID_MATERIALS[look.material], mutation.id .. " 재료 " .. look.material)
				end
			end
			local rarityIds = {}
			for _, r in Rarities.list do
				rarityIds[r.id] = true
			end
			for id in Visuals.rarityEffects do
				T.truthy(rarityIds[id], "희귀도 효과의 모르는 희귀도 " .. id)
			end
			for _, id in { "secret", "eternal", "divine" } do
				T.truthy(Visuals.specialEggs[id], id)
			end
			T.truthy(#Visuals.plotColors >= Config.PLOT_COUNT)
		end
	)

	T.test("펫 모양 색은 0~255 정수 3개, 구역 테마 색도 마찬가지", function()
		local function checkColor(c, where)
			T.eq(#c, 3, where)
			for _, v in c do
				T.truthy(type(v) == "number" and v >= 0 and v <= 255, where .. " 값 " .. tostring(v))
			end
		end
		for id, look in Visuals.pets do
			for i, c in look.colors do
				checkColor(c, id .. " 색" .. i)
			end
		end
		for id, theme in Visuals.biomes do
			for _, key in { "floor", "trim", "accent", "accent2" } do
				checkColor(theme[key], id .. "." .. key)
			end
		end
	end)

	------------------------------------------------------------------
	T.suite("참조: 진입점이 모든 서비스·컨트롤러를 시작하는지")

	T.test(
		"Main.server: Services 폴더의 start() 가 있는 서비스는 전부 require + start() 호출, CycleService.run() 이 마지막",
		function()
			local main = stripComments(fs.readFile("src/server/Main.server.luau"))
			local required, started = {}, {}
			for var, file in string.gmatch(main, "local (%w+) = require%(Services%.(%w+)%)") do
				required[file] = var
			end
			for var in string.gmatch(main, "(%w+)%.start%(%)") do
				started[var] = true
			end
			for path, text in SERVER do
				local file = string.match(path, "^src/server/Services/(%w+)%.luau$")
				if file and string.find(text, "\nfunction " .. file .. ".start%(") then
					T.truthy(required[file], file .. " 를 Main.server 에서 require 안 함")
					T.truthy(started[required[file] or ""], file .. ".start() 를 Main.server 에서 안 부름")
				end
			end
			local order = {}
			for var in string.gmatch(main, "(%w+)%.start%(%)") do
				table.insert(order, var)
			end
			local function indexOf(name)
				for i, v in order do
					if v == name then
						return i
					end
				end
				return math.huge
			end
			T.truthy(indexOf("Net") < indexOf("MapBuilder"), "Net 이 가장 먼저")
			T.truthy(indexOf("MapBuilder") < indexOf("EggService"), "맵이 알보다 먼저")
			for _, special in { "SakuraService", "AltarService", "QuestService" } do
				T.truthy(indexOf("MapBuilder") < indexOf(special), special .. " 는 MapBuilder 다음")
			end
			T.truthy(
				indexOf("DataService") < indexOf("PlayerLifecycle"),
				"저장 서비스가 접속 처리보다 먼저"
			)
			local lastRun = string.find(main, "CycleService.run()", 1, true)
			local lastStart = 0
			for position in string.gmatch(main, "()%w+%.start%(%)") do
				lastStart = position
			end
			T.truthy(lastRun and lastRun > lastStart, "CycleService.run() 은 모든 start() 뒤에")
		end
	)

	T.test(
		"Main.client: Controllers 폴더의 컨트롤러는 전부 boot 되거나 다른 모듈이 불러감",
		function()
			local main = fs.readFile("src/client/Main.client.luau")
			local booted = scan({ main = main }, 'boot%("(%w+)"%)')
			for path, text in CLIENT do
				local file = string.match(path, "^src/client/Controllers/(%w+)%.luau$")
				if file and string.find(text, "\nfunction " .. file .. ".start%(") then
					T.truthy(booted[file], file .. " 가 Main.client 에서 boot 되지 않음")
				end
			end
			for name in booted do
				T.truthy(
					CLIENT["src/client/Controllers/" .. name .. ".luau"],
					"boot 하는 컨트롤러 파일이 없음: " .. name
				)
			end
		end
	)

	T.test(
		"default.project.json: 경로가 실제로 있고 진입점 두 개가 RunContext 스크립트 이름임",
		function()
			local project = fs.readFile("default.project.json")
			for path in string.gmatch(project, '"%$path"%s*:%s*"([^"]+)"') do
				T.truthy(fs.isDir(path), "$path 가 없음: " .. path)
			end
			T.truthy(string.find(project, '"emitLegacyScripts"%s*:%s*false'))
			T.truthy(SERVER["src/server/Main.server.luau"] and CLIENT["src/client/Main.client.luau"])
		end
	)

	------------------------------------------------------------------
	T.suite("참조: 위험한 버릇 찾기 (소스 글자 검사)")

	T.test("옛 전역 wait() / spawn() / delay() 를 안 씀 (task.wait / task.spawn / task.delay 만)", function()
		for path, text in SRC do
			local code = stripComments(text)
			for name in string.gmatch(code, "%f[%w_.:](wait)%(") do
				T.truthy(false, path .. ": 옛 전역 " .. name .. "() 사용")
			end
			for name in string.gmatch(code, "%f[%w_.:](spawn)%(") do
				T.truthy(false, path .. ": 옛 전역 " .. name .. "() 사용")
			end
			for name in string.gmatch(code, "%f[%w_.:](delay)%(") do
				T.truthy(false, path .. ": 옛 전역 " .. name .. "() 사용")
			end
		end
	end)

	T.test(
		"while true 무한 루프 안에는 반드시 task.wait 이 있음 (시간을 안 쉬면 서버가 멈춤)",
		function()
			local loops = 0
			for path, text in SRC do
				local lines = {}
				for line in string.gmatch(stripComments(text) .. "\n", "(.-)\n") do
					table.insert(lines, line)
				end
				for i, line in lines do
					local indent = string.match(line, "^(%s*)while true do")
					if indent then
						loops += 1
						-- 같은 들여쓰기의 end 까지가 루프 몸통
						local ok = false
						for j = i + 1, #lines do
							if lines[j] == indent .. "end" then
								break
							end
							if
								string.find(lines[j], "task.wait", 1, true) or string.find(lines[j], ":Wait()", 1, true)
							then
								ok = true
							end
						end
						T.truthy(ok, path .. ":" .. i .. " while true 루프 안에 task.wait 이 없음")
					end
				end
			end
			T.truthy(loops >= 15, "무한 루프를 너무 적게 찾음 " .. loops)
		end
	)

	T.test(
		"서버 코드의 WaitForChild 는 전부 시간 제한이 있음 (없으면 파트가 안 생길 때 영원히 멈춤)",
		function()
			for path, text in SERVER do
				local code = stripComments(text)
				for args in string.gmatch(code, "WaitForChild%(([^%)]*)%)") do
					T.truthy(
						string.find(args, ",", 1, true),
						path .. ": WaitForChild(" .. args .. ") 시간 제한 없음"
					)
				end
			end
		end
	)

	T.test(
		"Instance.new 의 두 번째 인자(부모) 방식을 안 씀, 옛 Connect 소문자(:connect)는 Signal 에만",
		function()
			for path, text in SRC do
				local code = stripComments(text)
				T.falsy(
					string.find(code, 'Instance%.new%(%s*"[%w]+"%s*,'),
					path .. ": Instance.new(클래스, 부모) 사용"
				)
			end
		end
	)

	T.test(
		"서버의 Remote 처리기는 전부 Net.on 으로만 (OnServerEvent 직접 연결 금지 = 레이트 리밋·pcall 우회)",
		function()
			for path, text in SERVER do
				if path ~= "src/server/Net.luau" then
					T.falsy(
						string.find(stripComments(text), "OnServerEvent", 1, true),
						path .. ": OnServerEvent 를 직접 씀 (레이트 리밋 우회)"
					)
				end
			end
		end
	)

	T.test(
		"클라가 서버 값을 바꾸려는 코드 없음: 클라 코드는 FireServer 대신 Net.send 만, 돈·속도 Attribute 를 쓰지 않음",
		function()
			for path, text in CLIENT do
				local code = stripComments(text)
				T.falsy(
					string.find(code, ":FireServer", 1, true) and path ~= "src/client/Net.luau",
					path .. ": FireServer 직접 호출"
				)
				T.falsy(
					string.find(code, ":SetAttribute%(%s*Attr%.Money") or string.find(code, 'SetAttribute%("Money"'),
					path .. ": 돈 Attribute 를 클라에서 씀"
				)
			end
		end
	)
end
