--!nocheck
--[[
	서버 겉모습 스모크 테스트 (선임) — 저장소 루트에서:  lune run tests/smoke_visuals.luau
	(tests/run.luau 에는 안 들어감. 로블록스 없이 @lune/roblox 진짜 인스턴스로 만들어 보며
	 속성 이름·타입 오타, nil 인덱싱 같은 실행 오류를 잡습니다. 모양이 예쁜지는 스튜디오에서 봐야 함)

	검사: MapBuilder.start() (맵 15구역·베이스 7개·특수 장소 = 6판 사쿠라 나무만), PetVisualService.build(식물 134종 — 아직 5판 동물 모양),
	      6판 정원 펫 진열 없음, 경비 겉모습, EggVisualService (씨앗 껍데기 — 아직 알 모양)
	      + 특수 장소 태그 파트 개수/Attribute/구역 안에 있는지 (서버 Landmarks 가 임시 파트를 안 만들게)
	      + 4판: 파트 수 상한 (구역 ≤ 400, 맵 ≤ 7,000, 러닝머신 7개가 모두 가장 큰 모양이어도), 입구 아치·큰 바닥 판,
	        둥지 태그 파트 높이 그대로, 경비 전용 소품(키 그대로), 등급 10개 알 모양(매끈한 타원 + 띠·점, ≤ 8 파트, 희귀 이상 반짝이)
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./Loader")

local Instance = roblox.Instance
local game = Instance.new("DataModel")
local Workspace = game:GetService("Workspace")

local failures = 0
local function check(cond, message)
	if cond then
		print("  ok   " .. message)
	else
		failures += 1
		print("  FAIL " .. message)
	end
end

-- Lune 에 없는 메서드/이벤트 채우기
local function noopSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
		Wait = function() end,
	}
end
local CLASSES = {
	"Part",
	"SpawnLocation",
	"Model",
	"Folder",
	"Highlight",
	"BillboardGui",
	"SurfaceGui",
	"TextLabel",
	"Frame",
}
for _, class in CLASSES do
	pcall(roblox.implementMethod, class, "GetAttributeChangedSignal", function()
		return noopSignal()
	end)
	pcall(roblox.implementMethod, class, "GetPropertyChangedSignal", function()
		return noopSignal()
	end)
	pcall(roblox.implementProperty, class, "Destroying", function()
		return noopSignal()
	end)
	pcall(roblox.implementProperty, class, "AncestryChanged", function()
		return noopSignal()
	end)
end
-- 5판 주임 검수: PivotTo 호출·옮긴 파트 수를 세어 둠 (펫 126마리 부하 측정용)
local pivotCalls, pivotParts = 0, 0
roblox.implementMethod("Model", "PivotTo", function(model, cf)
	pivotCalls += 1
	local primary = model.PrimaryPart
	local pivot = if primary then primary.CFrame else roblox.CFrame.new()
	local delta = cf * pivot:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			pivotParts += 1
			d.CFrame = delta * d.CFrame
		end
	end
end)
roblox.implementMethod("Model", "GetPivot", function(model)
	local primary = model.PrimaryPart
	return if primary then primary.CFrame else roblox.CFrame.new()
end)
for _, cls in { "Part", "SpawnLocation" } do
	roblox.implementProperty(cls, "Position", function(part)
		return part.CFrame.Position
	end, function(part, v)
		part.CFrame = roblox.CFrame.new(v) * part.CFrame.Rotation
	end)
	roblox.implementMethod(cls, "SetNetworkOwner", function() end)
end

local tagged = {}
local CollectionService = {
	AddTag = function(_, inst, tag)
		tagged[tag] = tagged[tag] or {}
		table.insert(tagged[tag], inst)
	end,
	GetTagged = function(_, tag)
		return table.clone(tagged[tag] or {})
	end,
	GetInstanceAddedSignal = function()
		return noopSignal()
	end,
	GetInstanceRemovedSignal = function()
		return noopSignal()
	end,
}
local Players = {
	GetPlayerByUserId = function()
		return nil
	end,
	-- (선임 B-1) 우리 펫은 우리 100 스터드 안에 누군가 있을 때만 걸음 → 테스트가 바꿔 끼움
	GetPlayers = function()
		return {}
	end,
}

local sharedNode = Loader.get("ReplicatedStorage")
-- fs 호출이 메타메서드 안에서 일어나지 않게 트리를 미리 다 읽어 둠
local function warm(node)
	local getChildren = node.GetChildren
	for _, child in getChildren(node) do
		warm(child)
	end
end
warm(Loader.get("ReplicatedStorage"))
warm(Loader.get("ServerScriptService"))
local ReplicatedProxy = setmetatable({}, {
	__index = function(_, key)
		if key == "Shared" or key == "Client" then
			return sharedNode[key]
		end
		if key == "FindFirstChild" or key == "WaitForChild" then
			return function()
				return nil
			end
		end
		return nil
	end,
})

local fakeGame = {
	GetService = function(_, name)
		if name == "CollectionService" then
			return CollectionService
		elseif name == "Players" then
			return Players
		elseif name == "ReplicatedStorage" then
			return ReplicatedProxy
		elseif name == "Workspace" then
			return Workspace
		end
		return game:GetService(name)
	end,
}

local taskStub = {
	spawn = function() end, -- 무한 루프 서비스는 돌리지 않음
	defer = function(fn, ...)
		fn(...)
	end,
	wait = function() end,
	delay = function() end,
}

local function seededRandom(seed)
	local s = seed or 1
	local function nxt()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
	return {
		NextNumber = function(_, a, b)
			a = a or 0
			b = b or 1
			return a + (b - a) * nxt()
		end,
		NextInteger = function(_, a, b)
			return a + math.floor(nxt() * (b - a + 1))
		end,
	}
end

local cache = {}
local requireNode
local function makeEnv(node)
	return setmetatable({
		script = node,
		game = fakeGame,
		require = function(target)
			return requireNode(target)
		end,
		Instance = roblox.Instance,
		CFrame = roblox.CFrame,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Random = { new = seededRandom },
		RaycastParams = roblox.RaycastParams,
		task = taskStub,
		warn = function(...)
			print("WARN:", ...)
		end,
		typeof = roblox.typeof or typeof,
	}, { __index = _G })
end
requireNode = function(node)
	local props = rawget(node, "__props")
	local file = props.file
	if cache[file] ~= nil then
		return cache[file]
	end
	local source = fs.readFile(file)
	-- Lune 은 CFrame 에서 Position 을 계산해 주지 않을 때가 있어 테스트에서만 파트 위치 읽기를 CFrame.Position 으로
	for _, name in { "p", "floor", "spot", "pen" } do
		source = string.gsub(source, "%f[%w]" .. name .. "%.Position", name .. ".CFrame.Position")
	end
	local chunk = luau.load(source, { debugName = file, environment = makeEnv(node) })
	local result = chunk()
	cache[file] = result
	return result
end

local function count(inst)
	local n = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function body()
	print("[맵]")
	local MapBuilder = requireNode(Loader.get("ServerScriptService/Server/Services/MapBuilder"))
	MapBuilder.start()
	local map = Workspace:FindFirstChild("Map")
	check(map ~= nil, "Workspace.Map 생김")
	print("  map parts:", count(map))
	for _, z in { "Zones", "Plots", "Hub" } do
		print("    " .. z, count(map:FindFirstChild(z)))
	end
	print("[4판 비주얼: 파트 수 상한]")
	local budget = MapBuilder.PART_BUDGET
	check(budget ~= nil and budget.zone == 400 and budget.map == 7000, "PART_BUDGET = 구역 400 / 맵 7,000")
	local counts = MapBuilder.partCounts()
	check(counts.total == count(map), "partCounts().total = 실제 맵 파트 수: " .. counts.total)
	local zoneOver, zoneSeen, items, skippedAll = {}, 0, 0, 0
	local Biomes0 = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Biomes"))
	for _, b in Biomes0.list do
		local zf = map.Zones:FindFirstChild(b.id)
		local n = counts.zones[b.id] or -1
		zoneSeen += 1
		local dec = zf and zf:FindFirstChild("Decor")
		local floors, arch = 0, zf and zf:FindFirstChild("EntranceArch")
		for _, d in (zf and zf:GetChildren() or {}) do
			if d:IsA("BasePart") and d.Name == "Floor" then
				floors += 1
			end
		end
		local it, sk = zf and zf:GetAttribute("DecorItems") or 0, zf and zf:GetAttribute("DecorSkipped") or 0
		items += it
		skippedAll += sk
		print(
			string.format(
				"    %-17s parts %3d  decor %3d  items %3d  skipped %d  floor %d",
				b.id,
				n,
				dec and count(dec) or 0,
				it,
				sk,
				floors
			)
		)
		if n < 0 or n > budget.zone then
			table.insert(zoneOver, b.id .. "=" .. n)
		end
		check(zf and zf:GetAttribute("PartCount") == n, b.id .. " PartCount Attribute = 실제 수")
		check(floors >= 1 and floors <= 2, b.id .. " 바닥 = 큰 판 1~2장 (작은 칸 대신): " .. floors)
		check(
			arch ~= nil and arch:FindFirstChild("ArchBanner") ~= nil,
			b.id .. " 입구 아치 + 이름 현수막 (EntranceArch/ArchBanner)"
		)
	end
	print(
		string.format(
			"    hub %d  plots %d  total %d  (장식 물건 %d개, 상한 때문에 못 놓음 %d)",
			counts.hub,
			counts.plots,
			counts.total,
			items,
			skippedAll
		)
	)
	check(zoneSeen == 15 and #zoneOver == 0, "구역마다 파트 ≤ 400: " .. table.concat(zoneOver, ", "))
	check(counts.total <= budget.map, "맵 전체 파트 ≤ 7,000: " .. counts.total)
	check(
		skippedAll == 0,
		"장식이 상한에 막혀 빠진 것 없음 (Visuals 장식 개수가 상한 안): " .. skippedAll
	)
	-- 둥지 태그 파트는 크기·높이 그대로 (서버가 윗면에 알을 놓음): 윗면 = 바닥 + 1.2
	local nestTopOk = true
	for _, b in Biomes0.list do
		for _, nest in MapBuilder.getNests(b.id) do
			local top = nest.CFrame.Position.Y + 0.6
			if math.abs(top - 1.2) > 0.01 or math.abs(nest.Size.X - 1.2) > 0.01 then
				nestTopOk = false
			end
		end
	end
	check(nestTopOk, "둥지 태그 파트 윗면 높이 1.2 그대로 (알 놓는 높이)")
	check(MapBuilder.plotCount() == 7, "베이스 7개")
	check(#MapBuilder.getNests("forest") == 8, "숲 둥지 8개")

	print("[2판 복도 맵]")
	local MapLayout = requireNode(Loader.get("ReplicatedStorage/Shared/Data/MapLayout"))
	local Biomes = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Biomes"))
	local total = count(map)
	check(total <= 12000, "맵 파트 1만 2천 이하: " .. total)
	local tooBig = 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and (d.Size.X > 2048 or d.Size.Y > 2048 or d.Size.Z > 2048) then
			tooBig += 1
		end
	end
	check(tooBig == 0, "한 변 2048 넘는 파트 없음: " .. tooBig)
	local zonesOk = true
	for _, b in Biomes.list do
		local z = MapBuilder.getZone(b.id)
		local r = MapLayout.biome(b.id)
		if not z or math.abs(z.centerZ - r.centerZ) > 0.01 or math.abs(z.halfZ * 2 - (r.zMax - r.zMin)) > 0.01 then
			zonesOk = false
		end
		if #MapBuilder.getNests(b.id) ~= 8 then
			zonesOk = false
		end
	end
	check(zonesOk, "구역 15개 = MapLayout z 범위, 둥지 8개씩")
	local nestOk = true
	for i, spot in MapLayout.nestsFor("snow") do
		local p = MapBuilder.getNests("snow")[i].CFrame.Position
		if math.abs(p.X - spot.x) > 0.01 or math.abs(p.Z - spot.z) > 0.01 then
			nestOk = false
		end
	end
	check(nestOk, "둥지 자리 = MapLayout.nestsFor")
	check(MapBuilder.findBiomeAt(roblox.Vector3.new(0, 3, 250)) == "lake", "z=250 은 호수")
	check(MapBuilder.findBiomeAt(roblox.Vector3.new(0, 3, -20)) == nil, "허브는 구역 아님")
	check(MapBuilder.isInSafeZone(roblox.Vector3.new(0, 3, -20)), "허브 = 안전 구역")
	check(not MapBuilder.isInSafeZone(roblox.Vector3.new(0, 3, 20)), "z=20 은 안전 구역 아님")
	check(#(tagged.SellStall or {}) == 8, "판매 가게 8개 (허브 1 + 베이스 7, SellStall)")
	check(#(tagged.TrailShop or {}) == 1, "트레일 상점 1개")
	check(#(tagged.NightWall or {}) == 1, "밤 벽 1장 (허브 경계)")
	check(#(tagged.MainSpawn or {}) == 1, "기본 스폰 1개")
	check(
		#(tagged.IncubatorSlot or {}) == 0,
		"부화 알 받침 없음 (2판 수정: 알은 우리 바닥 아무 데나)"
	)
	local plotOk = true
	for i = 1, 7 do
		local plot = MapBuilder.getPlot(i)
		local layout = MapLayout.plot(i)
		local pen = plot and plot.pen
		local pad = plot and plot.treadmill
		if not (plot and pen and pad and plot.spawn and plot.sign) then
			plotOk = false
		else
			-- 우리 바닥은 앞(복도) 쪽을 봄, 러닝머신은 MapLayout 자리
			local look = pen.CFrame.LookVector
			if math.abs(look.X - layout.facing) > 0.01 then
				plotOk = false
			end
			if math.abs(pad.CFrame.Position.X - layout.treadmill.x) > 0.01 then
				plotOk = false
			end
			if not MapLayout.isInPlot(plot.spawn.CFrame.Position, i) then
				plotOk = false
			end
			if not pad.Parent:FindFirstChild("TreadmillLook") then
				plotOk = false
			end
		end
	end
	check(plotOk, "베이스 7개: 우리(앞을 봄)·러닝머신(MapLayout 자리, 모양 모델)·스폰·간판")
	-- 주인이 생기면: 간판 이름, 업그레이드 표지판 숫자, 러닝머신 모양(레벨 0~10)
	local kidLevels = { TreadmillLevel = 0, PenLevel = 5 }
	local kid = {
		UserId = 99,
		DisplayName = "Kid",
		GetAttribute = function(_, name)
			return kidLevels[name]
		end,
		GetAttributeChangedSignal = function()
			return noopSignal()
		end,
	}
	Players.GetPlayerByUserId = function(_, id)
		return if id == 99 then kid else nil
	end
	local looksOk = true
	local mapBefore, lookBefore, maxLook = count(map), 0, 0
	for i = 1, 7 do
		local look0 = MapBuilder.getPlot(i).treadmill.Parent:FindFirstChild("TreadmillLook")
		lookBefore += if look0 then count(look0) else 0
	end
	local padColors = {}
	for level = 0, 20 do
		kidLevels.TreadmillLevel = level
		MapBuilder.setPlotOwner(2, kid)
		local look = MapBuilder.getPlot(2).treadmill.Parent:FindFirstChild("TreadmillLook")
		if not look or look:GetAttribute("Level") ~= level or count(look) < 12 then
			looksOk = false
			print("    러닝머신 레벨 " .. level .. " 모양 문제")
		end
		if level >= 1 then
			local pad = MapBuilder.getPlot(2).treadmill
			padColors[tostring(pad.Color) .. "|" .. tostring(pad.Material) .. "|" .. (look and count(look) or 0)] = true
		end
		maxLook = math.max(maxLook, look and count(look) or 0)
	end
	check(looksOk, "러닝머신 레벨 0~20 모양 모델 (레벨마다 교체)")
	local distinct = 0
	for _ in padColors do
		distinct += 1
	end
	check(
		distinct == 20,
		"6판: 러닝머신 1~20레벨 모양이 전부 다름 (벨트 색·재질·파트 수): " .. distinct
	)
	-- 7 베이스 모두 가장 파트가 많은 러닝머신 모양이어도 맵 7,000 이하
	local worst = mapBefore - lookBefore + 7 * maxLook
	check(
		worst <= 7000,
		string.format("러닝머신 7개 모두 가장 큰 모양(%d)이어도 맵 ≤ 7,000: %d", maxLook, worst)
	)
	-- 6판 (사장님: 러닝머신 최대 1초 1M): 20레벨까지, 11~20레벨 모양 10개 더 (정글·바다·사탕·벚꽃·용암·수정·유령·은하·무지개·황제)
	local Upgrades = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Upgrades"))
	check(#Upgrades.Treadmill == 20, "러닝머신 20레벨: " .. #Upgrades.Treadmill)
	local levelsSeen = {}
	for _, level in { 10, #Upgrades.Treadmill } do
		kidLevels.TreadmillLevel = level
		MapBuilder.setPlotOwner(2, kid)
		local look = MapBuilder.getPlot(2).treadmill.Parent:FindFirstChild("TreadmillLook")
		check(look and look:GetAttribute("Level") == level, "러닝머신 " .. level .. "레벨 모양 모델")
		for _, d in MapBuilder.getPlot(2).sign.Parent:GetDescendants() do
			if d:IsA("TextLabel") and d.Name == "Level" then
				table.insert(levelsSeen, d.Text)
			end
		end
	end
	check(
		table.find(levelsSeen, "레벨 10 > 레벨 11") ~= nil,
		"10레벨 표지판 '레벨 10 > 레벨 11' (최대 아님)"
	)
	local sign = MapBuilder.getPlot(2).sign
	local title = sign and sign:FindFirstChild("Title", true)
	check(title and title.Text == "Kid의 베이스", "주인 이름 간판: " .. tostring(title and title.Text))
	local levelLabels = {}
	for _, d in sign.Parent:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "Level" then
			table.insert(levelLabels, d.Text)
		end
	end
	check(
		table.find(levelLabels, "레벨 5 > 레벨 6") ~= nil and table.find(levelLabels, "최대 레벨!") ~= nil,
		"업그레이드 표지판 숫자: " .. table.concat(levelLabels, " / ")
	)
	MapBuilder.setPlotOwner(2, nil)
	check(title.Text == "빈 베이스", "주인이 나가면 '빈 베이스'")
	Players.GetPlayerByUserId = function()
		return nil
	end

	print("[2단계 특수 장소 모델]")
	local function inZone(part, biomeId)
		local zone = MapBuilder.getZone(biomeId)
		local p = part.CFrame.Position
		return zone ~= nil and math.abs(p.X - zone.centerX) <= zone.halfX and math.abs(p.Z - zone.centerZ) <= zone.halfZ
	end
	-- 6판 (사장님 결정): 퓨전 머신·제단·비밀 통로 없앰 → 사쿠라 나무 하나만
	check(#(tagged.FusionMachine or {}) == 0, "6판: FusionMachine 태그 없음")
	check(#(tagged.Altar or {}) == 0, "6판: Altar 태그 없음")
	check(#(tagged.Shrine or {}) == 0, "6판: Shrine 태그 없음")
	local sakura = tagged.SakuraIncubator or {}
	check(#sakura == 1 and inZone(sakura[1], "cherry_blossom"), "SakuraIncubator 1개, 벚꽃 구역 안")
	-- 5판: 마법의 숲 퀘스트 문(QuestGate)은 퀘스트와 함께 없앰 → 마법의 숲은 항상 열림
	check(#(tagged.QuestGate or {}) == 0, "5판: QuestGate 태그 파트 없음 (마법의 숲 항상 열림)")
	-- 5판 주임 검수: 눈에 보이는 문·잠금도 없어야 함 — 구역 경계(마법의 숲 입구 포함)를 가로막는 단단한 파트가 없음
	--   (캐릭터 높이 y 3~4 에서 복도 폭의 40 이상을 막는 CanCollide 파트. 바닥·모래띠(낮음)·담장(얇음)·아치 현수막(높음)은 해당 없음)
	do
		local function corners(part)
			local h = part.Size / 2
			local list = {}
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						table.insert(list, part.CFrame * roblox.Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
					end
				end
			end
			return list
		end
		local blockers = {}
		local gateZ = {}
		for _, b in MapLayout.biomes do
			if b.index > 1 then
				gateZ[b.id] = b.zMin
			end
		end
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide then
				local minX, maxX, minY, maxY, minZ, maxZ =
					math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
				for _, c in corners(d) do
					minX, maxX = math.min(minX, c.X), math.max(maxX, c.X)
					minY, maxY = math.min(minY, c.Y), math.max(maxY, c.Y)
					minZ, maxZ = math.min(minZ, c.Z), math.max(maxZ, c.Z)
				end
				if maxX - minX >= 40 and minY <= 4 and maxY >= 3 then
					for id, z in gateZ do
						if minZ <= z + 3 and maxZ >= z - 3 and minX <= 100 and maxX >= -100 then
							table.insert(blockers, id .. ":" .. d.Name)
						end
					end
				end
			end
		end
		check(
			#blockers == 0,
			"구역 경계 14곳 어디에도 복도를 가로막는 단단한 파트(문·잠금)가 없음: "
				.. table.concat(blockers, ", ")
		)
		check(
			gateZ.enchanted_forest ~= nil,
			"마법의 숲 입구도 검사 대상에 들어 있음 (z=" .. tostring(gateZ.enchanted_forest) .. ")"
		)
	end
	-- 서버 Landmarks 가 이 파트들을 찾으면 임시 파트를 안 만듦
	local Landmarks = requireNode(Loader.get("ServerScriptService/Server/Util/Landmarks"))
	check(#Landmarks.find("SakuraIncubator") == 1, "Landmarks.find(SakuraIncubator) = 1")
	check(Landmarks.plotPart("Treadmill", 3) ~= nil, "Landmarks.plotPart(Treadmill, 3)")
	local before = #(tagged.SakuraIncubator or {})
	Landmarks.ensure({
		tag = "SakuraIncubator",
		name = "SakuraIncubator",
		label = "x",
		position = roblox.Vector3.new(0, 0, 0),
		size = roblox.Vector3.new(1, 1, 1),
		color = roblox.Color3.new(1, 1, 1),
	})
	check(#(tagged.SakuraIncubator or {}) == before, "Landmarks.ensure 가 임시 사쿠라 나무를 안 만듦")

	-- 6판: 사쿠라 나무 모양 (태그 꽃밭 파트 크기 그대로 + 줄기·가지·분홍 꽃 덩어리·꽃잎)
	do
		local pedestal = sakura[1]
		local treeModel = pedestal and pedestal.Parent
		local wood, pinkBalls, petals = 0, 0, nil
		for _, d in (treeModel and treeModel:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				if d.Material == roblox.Enum.Material.Wood then
					wood += 1
				elseif d.Shape == roblox.Enum.PartType.Ball and d.Color.R > 0.9 and d.Color.G < 0.85 then
					pinkBalls += 1
				end
				if d.Name == "PetalEmitter" then
					petals = d:FindFirstChildOfClass("ParticleEmitter")
				end
			end
		end
		check(
			pedestal ~= nil and math.abs(pedestal.Size.Y - 7) < 0.01 and math.abs(pedestal.Size.X - 1.6) < 0.01,
			"사쿠라 나무 꽃밭(SakuraIncubator) 크기 그대로 (지름 7)"
		)
		check(treeModel and treeModel.Name == "SakuraIncubatorModel", "사쿠라 나무 모델 이름 그대로")
		check(
			wood >= 8 and pinkBalls >= 9 and petals ~= nil,
			string.format(
				"사쿠라 나무: 줄기·가지 %d, 분홍 꽃 덩어리 %d, 꽃잎 파티클",
				wood,
				pinkBalls
			)
		)
		check(treeModel and treeModel:FindFirstChild("SakuraEgg", true) == nil, "6판: 5판 알 돔(SakuraEgg) 없음")
	end
end

-- 식물·씨앗 단계·경비(식물 괴물)·씨앗 껍데기 검사 (맵 검사가 실패해도 따로 돎)
local function petsBody()
	local Pets = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Pets"))
	local Visuals = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Visuals"))
	local Rarities = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Rarities"))
	local PVS = requireNode(Loader.get("ServerScriptService/Server/Services/PetVisualService"))
	local PlantVS = requireNode(Loader.get("ServerScriptService/Server/Services/PlantVisualService"))
	local function has(list, inst)
		for _, x in list or {} do
			if x == inst then
				return true
			end
		end
		return false
	end
	local function fxOf(inst)
		local emitters, lights, on = 0, 0, 0
		for _, d in inst:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				emitters += 1
				if d.Enabled then
					on += 1
				end
			elseif d:IsA("PointLight") then
				lights += 1
				if d.Enabled then
					on += 1
				end
			end
		end
		return emitters, lights, on
	end
	local function visibleFruits(model)
		local n, total = 0, 0
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") and string.match(d.Name, "^Fruit%d$") then
				total += 1
				if d.Transparency < 1 then
					n += 1
				end
			end
		end
		return n, total
	end

	print("[6판 식물 134종]")
	local total, maxParts, maxId, minParts, minId = 0, 0, "", math.huge, ""
	local byForm = {}
	local rootOk, swayOk, fruitOk, auraOk, heightOk = 0, 0, 0, 0, 0
	local auraLine = {}
	for _, pet in Pets.list do
		local m = PlantVS.build(pet.id, { fx = true, fruits = 0 })
		local n = count(m)
		total += n
		if n > maxParts then
			maxParts, maxId = n, pet.id
		end
		if n < minParts then
			minParts, minId = n, pet.id
		end
		local form = m:GetAttribute("Form")
		byForm[form] = (byForm[form] or 0) + 1
		if m.PrimaryPart and m.PrimaryPart.Name == "Root" and m.PrimaryPart.Anchored then
			local welded = true
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d ~= m.PrimaryPart then
					if d.Anchored or d.CanCollide or d.CanTouch or d.CanQuery then
						welded = false
					end
				end
			end
			if welded then
				rootOk += 1
			end
		end
		if m:GetAttribute("Sway") == true then
			swayOk += 1
		end
		local h = m:GetAttribute("Height")
		if type(h) == "number" and h > 1.2 and h < 14 then
			heightOk += 1
		end
		local shown, fruits = visibleFruits(m)
		PlantVS.setFruits(m, 3)
		local shown3 = visibleFruits(m)
		if fruits == 5 and shown == 0 and shown3 == 3 then
			fruitOk += 1
		end
		-- 아우라: 희귀(rare) 이상만 파티클·빛, 전부 꺼진 채 + AuraFx 태그
		local r = Rarities.get(pet.rarity)
		local aura = m:FindFirstChild("Aura")
		local emitters, lights, on = fxOf(m)
		local good
		if r.order >= 3 then
			good = aura ~= nil and has(tagged.AuraFx, aura) and emitters + lights >= 1 and on == 0
		else
			good = aura == nil and emitters == 0 and lights == 0
		end
		if good then
			auraOk += 1
		else
			table.insert(auraLine, pet.id)
		end
	end
	local avg = total / #Pets.list
	local forms = {}
	for name, k in byForm do
		table.insert(forms, name .. " " .. k)
	end
	table.sort(forms)
	print(
		string.format(
			"  plants built: %d  avg parts: %.1f  min: %d (%s)  max: %d (%s)",
			#Pets.list,
			avg,
			minParts,
			minId,
			maxParts,
			maxId
		)
	)
	print("  모양별 식물 수: " .. table.concat(forms, ", "))
	check(#forms == 16, "식물 모양 16종 모두 쓰임: " .. #forms)
	check(maxParts <= 40 and minParts >= 8, string.format("식물 하나 파트 8~40 (평균 %.1f)", avg))
	check(rootOk == #Pets.list, "Root(Anchored) + 나머지 용접·충돌/터치/쿼리 꺼짐: " .. rootOk)
	check(swayOk == #Pets.list, "모델 Attr Sway = true: " .. swayOk)
	check(heightOk == #Pets.list, "키(Height) 1.2~14: " .. heightOk)
	check(fruitOk == #Pets.list, "열매 파트 5개, setFruits(3) 이면 3개만 보임: " .. fruitOk)
	check(
		auraOk == #Pets.list,
		"아우라 파티클·빛은 희귀 이상만 + 꺼진 채 + AuraFx 태그: " .. table.concat(auraLine, ",")
	)
	-- 슈퍼 울트라디바인 하늘 빛기둥은 늘 켜짐
	local sky = PlantVS.build("sky_pillar_flower", { fx = true })
	local beam = sky:FindFirstChild("SkyPillar", true)
	check(
		beam ~= nil and beam:IsA("Beam") and beam.Enabled == true,
		"슈퍼 울트라디바인 하늘 빛기둥(SkyPillar) 켜짐"
	)
	check(sky:FindFirstChild("AuraRing") ~= nil, "슈퍼 울트라디바인 고리(AuraRing)")
	local lib = PlantVS.build("owl_oak", { fx = false, fruits = 3 })
	local le, ll = fxOf(lib)
	check(le == 0 and ll == 0 and lib:FindFirstChild("Aura") == nil, "UI 모델(fx = false)은 아우라 없음")
	-- 돌연변이: 무지개 = 꽃잎·열매에 EggShell 태그 + Rainbow, 원소 = 파티클
	local rainbowPlant = PlantVS.build("sprout_daisy", { mutations = { "rainbow" } })
	local rainbowParts = 0
	for _, d in rainbowPlant:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Rainbow") == true and has(tagged.EggShell, d) then
			rainbowParts += 1
		end
	end
	check(rainbowParts >= 3, "무지개 돌연변이 식물: 꽃잎·열매가 색 순환 대상 " .. rainbowParts)
	local frozen = PlantVS.build("sprout_daisy", { mutations = { "frozen" } })
	check(
		frozen:FindFirstChild("Mutation_frozen", true) ~= nil,
		"얼음 돌연변이 파티클 (일반 식물이어도)"
	)
	-- 크기 등급
	local small = PlantVS.build("sprout_daisy", { size = "normal" }):GetAttribute("Height")
	local giant = PlantVS.build("sprout_daisy", { size = "giant" }):GetAttribute("Height")
	check(giant > small * 1.4, string.format("크기 등급 반영: 보통 %.1f → 초거대 %.1f", small, giant))
	-- 등급이 높을수록 큼 (키 배율 tall 을 빼고 비교)
	local common = PlantVS.build("sprout_daisy", {}):GetAttribute("Height") / Visuals.plantLook("sprout_daisy").tall
	local secret = PlantVS.build("lollipop_flower", {}):GetAttribute("Height")
		/ Visuals.plantLook("lollipop_flower").tall
	check(secret > common, "등급이 높을수록 큰 식물")

	print("[6판 자라는 씨앗 4단계]")
	local heights = {}
	for _, stage in { "seed", "sprout", "stem", "bud" } do
		local m = PlantVS.buildStage("owl_oak", stage, { fx = true })
		table.insert(heights, m:GetAttribute("Height"))
		check(m:GetAttribute("Stage") == stage and count(m) <= 14, stage .. " 모양 (" .. count(m) .. " 파트)")
		local _, _, on = fxOf(m)
		check(on == 0, stage .. " 아우라 꺼진 채 (희귀 owl_oak)")
	end
	check(
		heights[1] < heights[2] and heights[2] < heights[3] and heights[3] < heights[4],
		"단계가 갈수록 키가 큼: " .. table.concat(heights, " < ")
	)
	check(PlantVS.visualStage("sprout", 0, 100) == "seed", "처음 10% 는 씨앗(땅에 묻힘)")
	check(PlantVS.visualStage("sprout", 20, 100) == "sprout", "그다음 새싹")
	check(PlantVS.visualStage("bud", 80, 100) == "bud", "봉오리")
	local commonSeed = PlantVS.buildStage("sprout_daisy", "bud", { fx = true })
	local ce, cl = fxOf(commonSeed)
	check(ce == 0 and cl == 0, "일반 등급 씨앗은 파티클·빛 없음")

	print("[6판 정원 파트에 붙이기]")
	local garden = Instance.new("Folder")
	garden.Name = "FakeGarden"
	garden.Parent = Workspace
	local function ball(name, d, hs, attrs)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = roblox.Enum.PartType.Ball
		p.Size = roblox.Vector3.new(d, d, d)
		p.Anchored = true
		local mesh = Instance.new("SpecialMesh")
		mesh.Name = "EggShape"
		mesh.MeshType = roblox.Enum.MeshType.Sphere
		mesh.Scale = roblox.Vector3.new(1, hs, 1)
		mesh.Parent = p
		p.CFrame = roblox.CFrame.new(300, d * hs / 2, 300)
		for k, v in attrs do
			p:SetAttribute(k, v)
		end
		local label = Instance.new("BillboardGui")
		label.Name = "Label"
		label.Parent = p
		p.Parent = garden
		return p
	end
	local seedPart = ball("Incubating_i1", 2, 1.25, {
		EggUid = "i1",
		OwnerUserId = 77,
		PetId = "owl_oak",
		Size = "normal",
		Mutations = "",
		Progress = 0,
		Required = 100,
		Stage = "sprout",
	})
	PlantVS.attachSeed(seedPart)
	local sv = seedPart:FindFirstChild("SeedVisual")
	check(sv ~= nil and sv:GetAttribute("Stage") == "seed", "자라는 씨앗: SeedVisual 붙음 (처음엔 씨앗)")
	check(seedPart.Transparency == 1, "원래 공 파트는 투명")
	local vh = seedPart:GetAttribute("VisualHeight")
	check(type(vh) == "number" and vh > 0, "VisualHeight Attr: " .. tostring(vh))
	local root = sv and sv.PrimaryPart
	check(root and math.abs(root.CFrame.Position.Y - 0) < 0.01, "씨앗 모델 바닥 = 공 파트 바닥 (y 0)")
	seedPart:SetAttribute("Progress", 30)
	PlantVS.refreshSeed(seedPart)
	check(seedPart:FindFirstChild("SeedVisual"):GetAttribute("Stage") == "sprout", "Progress 30% → 새싹")
	seedPart:SetAttribute("Stage", "bud")
	PlantVS.refreshSeed(seedPart)
	local bud = seedPart:FindFirstChild("SeedVisual")
	check(
		bud:GetAttribute("Stage") == "bud" and #seedPart:GetChildren() == 3,
		"Stage bud → 봉오리 (옛 모델은 지움)"
	)
	local label = seedPart:FindFirstChild("Label")
	check(
		label.StudsOffsetWorldSpace.Y >= seedPart:GetAttribute("VisualHeight") - 1.25,
		"이름표가 식물 위로 올라감"
	)

	local plantPart = ball("Plant_p1", 3.2, 1.6, {
		PlantUid = "p1",
		OwnerUserId = 77,
		PetId = "moon_lotus",
		Size = "normal",
		Mutations = "",
		Stage = "adult",
		Fruits = 2,
		FruitMax = 5,
	})
	PlantVS.attachPlant(plantPart)
	local pv = plantPart:FindFirstChild("moon_lotus")
	check(pv ~= nil and pv:IsA("Model"), "성체: 식물 모델 붙음")
	check(pv and select(1, visibleFruits(pv)) == 2, "Fruits 2 → 열매 2개 보임")
	plantPart:SetAttribute("Fruits", 5)
	PlantVS.refreshPlant(plantPart)
	check(
		pv and pv.Parent == plantPart and select(1, visibleFruits(pv)) == 5,
		"Fruits 5 → 같은 모델에서 5개 보임"
	)
	plantPart:SetAttribute("Fruits", 0)
	PlantVS.refreshPlant(plantPart)
	check(pv and select(1, visibleFruits(pv)) == 0, "Fruits 0 → 열매 없음")
	plantPart:SetAttribute("Mutations", "golden")
	PlantVS.refreshPlant(plantPart)
	local golden = plantPart:FindFirstChild("moon_lotus")
	local neonPetals = 0
	for _, d in (golden and golden:GetChildren() or {}) do
		if d:IsA("BasePart") and d.Name == "Petal" and d.Material == roblox.Enum.Material.Neon then
			neonPetals += 1
		end
	end
	check(
		golden ~= pv and neonPetals > 0,
		"Mutations golden → 다시 만들고 꽃잎이 금빛 네온: " .. neonPetals
	)
	check(#plantPart:GetChildren() == 3, "옛 식물 모델은 지움 (메시·이름표·모델)")
	garden.Parent = nil

	print("[경비 = 식물 괴물]")
	-- 경비 겉모습 (Lune 에는 Attribute 변경 신호가 없어서 State 를 바꾼 뒤 refreshGuard 를 직접 부름)
	local function fire(inst, _name)
		PVS.refreshGuard(inst)
	end
	local guards = {}
	local x = 0
	for biomeId, spec in Visuals.guards do
		x += 200
		local guard = Instance.new("Model")
		guard.Name = "Guard_" .. biomeId
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.Size = roblox.Vector3.new(4, 4, 3)
		hrp.CFrame = roblox.CFrame.new(x, 4.5, 0)
		hrp.Parent = guard
		local hum = Instance.new("Humanoid")
		hum.HipHeight = 2.5
		hum.Parent = guard
		guard.PrimaryPart = hrp
		guard:SetAttribute("BiomeId", biomeId)
		guard:SetAttribute("State", "Idle")
		guard.Parent = Workspace
		CollectionService:AddTag(guard, "Guardian")
		guards[biomeId] = { guard = guard, model = spec.model }
	end
	PVS.started = false
	PVS.start()
	local dressed, tall = 0, 0
	local minH, maxH = math.huge, 0
	for _, g in guards do
		local visual = g.guard:FindFirstChild(g.model)
		if visual then
			dressed += 1
			local h = visual:GetAttribute("Height")
			minH = math.min(minH, h)
			maxH = math.max(maxH, h)
			if h >= 25 and h <= 40 then
				tall += 1
			end
			fire(g.guard, "State") -- Idle → 잠
		end
	end
	check(dressed == 15, "경비 겉모습 15구역 전부 붙음: " .. dressed)
	local guardIds = {}
	for _, spec in Visuals.guards do
		table.insert(guardIds, spec.model)
		if spec.darkModel then
			table.insert(guardIds, spec.darkModel)
		end
	end
	local faceOk, partLine, partsOk = 0, {}, 0
	for _, id in guardIds do
		check(Visuals.monsters[id] ~= nil, id .. " 식물 괴물 모양 표")
		local m = PVS.buildMonster(id, 1, nil)
		local brows, closed, open = 0, 0, 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "Brow" and d.Transparency == 1 then
					brows += 1
				elseif d.Name == "EyeClosed" and d.Transparency < 1 then
					closed += 1
				elseif d.Name == "EyeOpen" and d.Transparency == 1 then
					open += 1
				end
			end
		end
		if brows == 2 and closed == 2 and open >= 2 then
			faceOk += 1
		end
		local n = count(m)
		if n >= 12 and n <= 70 then
			partsOk += 1
		end
		table.insert(partLine, id .. " " .. n)
	end
	print("  괴물 파트: " .. table.concat(partLine, ", "))
	check(#guardIds == 16, "식물 괴물 16종 (15구역 + 악마 장미): " .. #guardIds)
	check(
		faceOk == #guardIds,
		"괴물 모두 자는 얼굴로 시작 (눈썹 숨김·감은 눈 2·뜬 눈 숨김): " .. faceOk
	)
	check(partsOk == #guardIds, "괴물 파트 12~70")
	local heightOk2 = true
	for biomeId, g in guards do
		local visual = g.guard:FindFirstChild(g.model)
		local want = Visuals.guards[biomeId].height
		if not visual or math.abs(visual:GetAttribute("Height") - want) > 0.01 then
			heightOk2 = false
		end
	end
	check(heightOk2, "경비 겉모습 Height = Visuals.guards[..].height (GuardianService 잡힘 거리)")
	check(tall == 15, string.format("경비 키 25~40 스터드: %d (최소 %.1f, 최대 %.1f)", tall, minH, maxH))
	local forest = guards.forest
	if forest then
		local visual = forest.guard:FindFirstChild(forest.model)
		local z = visual and visual:FindFirstChild("SleepZ", true)
		check(z ~= nil and z:IsA("BillboardGui") and z.Enabled == true, "Idle 이면 머리 위 Z (SleepZ 켜짐)")
		local glow = visual and visual:FindFirstChild("GuardGlow")
		check(glow ~= nil and glow.Enabled == false, "Idle 이면 빨간 테두리 꺼짐")
		local function face(name)
			local n, shown = 0, 0
			for _, d in visual:GetDescendants() do
				if d:IsA("BasePart") and d.Name == name then
					n += 1
					if d.Transparency < 1 then
						shown += 1
					end
				end
			end
			return n, shown
		end
		local browN, browShown = face("Brow")
		local closedN, closedShown = face("EyeClosed")
		local _, openShown = face("EyeOpen")
		check(
			browN == 2 and browShown == 0 and closedN == 2 and closedShown == 2 and openShown == 0,
			string.format(
				"처음엔 눈썹 안 보임·눈 감김 (눈썹 %d/%d, 감은 눈 %d/%d)",
				browShown,
				browN,
				closedShown,
				closedN
			)
		)
		forest.guard:SetAttribute("State", "Chase")
		fire(forest.guard, "State")
		check(z ~= nil and z.Enabled == false, "Chase 면 Z 숨김")
		check(glow ~= nil and glow.Enabled == true, "Chase 면 빨간 테두리 켜짐")
		local _, browChase = face("Brow")
		local _, closedChase = face("EyeClosed")
		local openN, openChase = face("EyeOpen")
		check(
			browChase == 2 and closedChase == 0 and openN > 0 and openChase == openN,
			"Chase 면 화난 눈썹·뜬 눈 보이고 감은 눈 숨김"
		)
		forest.guard:SetAttribute("State", "Return")
		fire(forest.guard, "State")
		local _, browReturn = face("Brow")
		check(browReturn == 0 and select(2, face("EyeClosed")) == 2, "Return 이면 다시 눈 감고 눈썹 숨김")
		forest.guard:SetAttribute("State", "Chase")
		fire(forest.guard, "State")
		local pose = visual and visual.PrimaryPart and visual.PrimaryPart:FindFirstChild("GuardPose")
		check(pose ~= nil and pose:IsA("Weld"), "경비 자세 Weld(GuardPose)")
		if pose then
			local rootY = forest.guard.HumanoidRootPart.CFrame.Position.Y
			local footY = rootY + pose.C0.Position.Y
			check(math.abs(footY) < 0.01, "서 있을 때 발이 땅(0): " .. footY)
		end
		forest.guard:SetAttribute("State", "Idle")
		fire(forest.guard, "State")
		check(z ~= nil and z.Enabled == true, "다시 Idle 이면 Z 다시 보임")
	end

	print("[둥지 옆 장식 식물]")
	local spots = 0
	for _, spot in tagged.ParentAnimalSpot or {} do
		if spot.Parent then
			spots += 1
		end
	end
	PlantVS.started = false
	PlantVS.start()
	local decorations = 0
	for _, m in tagged.ParentAnimal or {} do
		if m.Parent and m:IsA("Model") and m:FindFirstChild("PetTag", true) then
			decorations += 1
		end
	end
	check(
		spots == 0 or decorations == spots,
		string.format("둥지 옆 장식 식물 %d / 자리 %d", decorations, spots)
	)

	print("[씨앗 껍데기]")
	local eggs = Instance.new("Folder")
	eggs.Parent = Workspace
	local carrier = {
		UserId = 5,
		attrs = { CarryingEgg = "egg-carried", CarryWeightKg = 4740 },
	}
	function carrier:GetAttribute(name)
		return self.attrs[name]
	end
	Players.GetPlayers = function()
		return { carrier }
	end
	local carriedEgg
	for i, spec in
		{
			{ "sprout_daisy", "", false, "common" },
			{ "world_tree", "golden", true, "divine" },
			{ "lollipop_flower", "rainbow", true, "secret" },
			{ "yeti_cabbage", "silver", false, "secret" },
		}
	do
		local p = Instance.new("Part")
		p.Shape = roblox.Enum.PartType.Ball
		p.Size = roblox.Vector3.new(2, 2, 2)
		p.Anchored = true
		p:SetAttribute("PetId", spec[1])
		p:SetAttribute("Mutations", spec[2])
		p:SetAttribute("Special", spec[3])
		p:SetAttribute("Rarity", spec[4])
		p:SetAttribute("EggUid", if i == 1 then "egg-carried" else "egg-" .. i)
		p:SetAttribute("EggState", if i == 1 then "Carried" else "Nest")
		if i == 1 then
			carriedEgg = p
		end
		p.Parent = eggs
		CollectionService:AddTag(p, "Egg")
	end
	local EVS = requireNode(Loader.get("ServerScriptService/Server/Services/EggVisualService"))
	EVS.started = false
	EVS.start()
	-- 6판 씨앗: Ball 껍데기 1개(Shell) + SpecialMesh Sphere(Scale (0.82, 1.25, 1)) + 끝(Tip) + 줄무늬
	local function seedShell(v)
		local shell = v and v:FindFirstChild("Shell")
		if not (shell and shell:IsA("Part") and shell.Shape == roblox.Enum.PartType.Ball) then
			return nil
		end
		local mesh = shell:FindFirstChildOfClass("SpecialMesh")
		if not (mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere and math.abs(mesh.Scale.Y - 1.25) < 1e-6) then
			return nil
		end
		if mesh.Scale.X >= 1 or v:FindFirstChild("Tip") == nil then
			return nil
		end
		return shell
	end
	local shells, seedOk = 0, 0
	for _, e in eggs:GetChildren() do
		local v = e:FindFirstChild("EggVisual")
		if v then
			shells += 1
			if seedShell(v) and count(v) <= 8 then
				seedOk += 1
			end
		end
	end
	check(shells == 4, "씨앗 껍데기 4개 (둥지·든 씨앗): " .. shells)
	check(seedOk == 4, "씨앗 = 아몬드 껍데기 + 끝 + 줄무늬, ≤ 8 파트: " .. seedOk)
	check(#(tagged.EggShell or {}) > 0, "EggShell 태그 붙음")
	local weight = carriedEgg and carriedEgg:FindFirstChild("WeightTag")
	check(weight ~= nil and weight.Enabled == true, "든 씨앗 무게 이름표(WeightTag) 켜짐")
	if weight then
		local kg = weight:FindFirstChild("Kg")
		check(kg ~= nil and kg.Text == "4,740Kg", "무게 글자 4,740Kg: " .. tostring(kg and kg.Text))
	end
	local nestEgg = eggs:GetChildren()[3]
	local nestWeight = nestEgg and nestEgg:FindFirstChild("WeightTag")
	check(nestWeight == nil or nestWeight.Enabled == false, "둥지 씨앗은 무게 이름표 숨김")
	local special = eggs:GetChildren()[2]
	check(special and special:FindFirstChild("SpecialBeam") ~= nil, "특별 씨앗 빛기둥(SpecialBeam) 그대로")

	-- 등급 11개 씨앗 모양 + 아우라 (희귀 이상 꺼진 파티클·빛 + AuraFx)
	local rarityEggs = Instance.new("Folder")
	rarityEggs.Parent = Workspace
	local made = {}
	for i, r in Rarities.list do
		local p = Instance.new("Part")
		p.Shape = roblox.Enum.PartType.Ball
		p.Size = roblox.Vector3.new(2, 2, 2)
		p.CFrame = roblox.CFrame.new(i * 10, 1.25, 900)
		p.Anchored = true
		p:SetAttribute("PetId", "sprout_daisy")
		p:SetAttribute("Mutations", "")
		p:SetAttribute("Rarity", r.id)
		p:SetAttribute("EggUid", "egg-r" .. i)
		p:SetAttribute("EggState", "Nest")
		p.Parent = rarityEggs
		CollectionService:AddTag(p, "Egg")
		made[r.id] = p
	end
	EVS.started = false
	EVS.start()
	local looksOk, auraOk2, line = 0, 0, {}
	for _, r in Rarities.list do
		local p = made[r.id]
		local v = p:FindFirstChild("EggVisual")
		local n = v and count(v) or 0
		local shell = seedShell(v)
		local lowest = if shell then shell.CFrame.Position.Y - shell.Size.Y / 2 * 1.25 else math.huge
		check(Visuals.eggLooks[r.id] ~= nil, r.id .. " 씨앗 모양 표(Visuals.eggLooks)")
		if shell and n >= 3 and n <= 8 then
			looksOk += 1
		end
		local emitters, lights, on = fxOf(v or p)
		local tagged2 = shell and has(tagged.AuraFx, shell)
		if r.order >= 3 then
			if tagged2 and emitters + lights >= 1 and on == 0 then
				auraOk2 += 1
			end
		elseif not tagged2 and emitters + lights == 0 then
			auraOk2 += 1
		end
		check(
			math.abs(lowest - 0) < 0.01,
			r.id .. " 씨앗 바닥이 둥지 위에 붙음: " .. string.format("%.3f", lowest)
		)
		table.insert(line, r.id .. " " .. n)
	end
	print("  등급별 씨앗 파트: " .. table.concat(line, ", "))
	check(looksOk == #Rarities.list, "등급 11개 씨앗: 아몬드 껍데기 + 무늬, 3~8 파트: " .. looksOk)
	check(
		auraOk2 == #Rarities.list,
		"희귀(rare) 이상만 아우라 (꺼진 채 + AuraFx 태그, 클라가 가까운 것만 켬): " .. auraOk2
	)
end

local mapOk, mapErr = xpcall(body, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)
if not mapOk then
	failures += 1
	print("ERROR (맵): " .. tostring(mapErr))
end
local ok, err = xpcall(petsBody, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)
if not ok then
	print("ERROR: " .. tostring(err))
	process.exit(1)
end
if failures > 0 then
	print(string.format("SMOKE VISUALS: %d 실패", failures))
	process.exit(1)
end
print("SMOKE VISUALS OK")
