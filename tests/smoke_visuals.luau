--!nocheck
--[[
	서버 겉모습 스모크 테스트 (선임) — 저장소 루트에서:  lune run tests/smoke_visuals.luau
	(tests/run.luau 에는 안 들어감. 로블록스 없이 @lune/roblox 진짜 인스턴스로 만들어 보며
	 속성 이름·타입 오타, nil 인덱싱 같은 실행 오류를 잡습니다. 모양이 예쁜지는 스튜디오에서 봐야 함)

	검사: MapBuilder.start() (맵 15구역·베이스 7개·2단계 특수 장소 모델), PetVisualService.build(펫 전부),
	      우리 진열, 경비 겉모습, EggVisualService (알 껍데기)
	      + 특수 장소 태그 파트 개수/Attribute/구역 안에 있는지 (서버 Landmarks 가 임시 파트를 안 만들게)
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
roblox.implementMethod("Model", "PivotTo", function(model, cf)
	local primary = model.PrimaryPart
	local pivot = if primary then primary.CFrame else roblox.CFrame.new()
	local delta = cf * pivot:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
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
	for level = 0, 10 do
		kidLevels.TreadmillLevel = level
		MapBuilder.setPlotOwner(2, kid)
		local look = MapBuilder.getPlot(2).treadmill.Parent:FindFirstChild("TreadmillLook")
		if not look or look:GetAttribute("Level") ~= level or count(look) < 12 then
			looksOk = false
			print("    러닝머신 레벨 " .. level .. " 모양 문제")
		end
	end
	check(looksOk, "러닝머신 레벨 0~10 모양 모델 (레벨마다 교체)")
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
	local fusion = tagged.FusionMachine or {}
	check(#fusion == 7, "FusionMachine 태그 7개 (베이스마다): " .. #fusion)
	local plotSeen = {}
	for _, part in fusion do
		plotSeen[part:GetAttribute("PlotIndex")] = true
		local model = part.Parent
		check(
			model:IsA("Model") and model:FindFirstChild("Core") and model:FindFirstChild("Tube3"),
			"퓨전 머신 " .. tostring(part:GetAttribute("PlotIndex")) .. " 모델에 Core·Tube1~3"
		)
	end
	check(plotSeen[1] and plotSeen[7], "퓨전 머신 PlotIndex 1~7")
	local sakura = tagged.SakuraIncubator or {}
	check(#sakura == 1 and inZone(sakura[1], "cherry_blossom"), "SakuraIncubator 1개, 벚꽃 구역 안")
	local altars = tagged.Altar or {}
	local sides = {}
	for _, part in altars do
		sides[part:GetAttribute("Side")] = part
		check(
			part:GetAttribute("PendingCount") == 0,
			"제단 PendingCount = 0 (" .. tostring(part:GetAttribute("Side")) .. ")"
		)
		check(inZone(part, "angels_demons"), "제단이 천사&악마 구역 안")
	end
	check(#altars == 2 and sides.light ~= nil and sides.dark ~= nil, "Altar 2개 (Side light / dark)")
	if sides.light and sides.dark then
		local zone = MapBuilder.getZone("angels_demons")
		check(sides.light.CFrame.Position.X < zone.centerX, "천국 제단은 천국(왼쪽 -X) 쪽")
		check(sides.dark.CFrame.Position.X > zone.centerX, "지옥 제단은 지옥(오른쪽 +X) 쪽")
	end
	local shrine = tagged.Shrine or {}
	check(#shrine == 1 and inZone(shrine[1], "angels_demons"), "Shrine 1개, 천사&악마 구역 안")
	if shrine[1] then
		check(shrine[1].Parent:FindFirstChild("Waterfall") ~= nil, "비밀 통로 옆 폭포")
	end
	local gates = tagged.QuestGate or {}
	check(#gates == 1 and inZone(gates[1], "enchanted_forest"), "QuestGate 1개, 마법의 숲 구역 안")
	if gates[1] then
		check(gates[1].CanCollide == true, "퀘스트 문 CanCollide = true")
		for i = 1, 3 do
			check(gates[1].Parent:FindFirstChild("Rune" .. i) ~= nil, "룬 돌 Rune" .. i)
		end
	end
	-- 서버 Landmarks 가 이 파트들을 찾으면 임시 파트를 안 만듦
	local Landmarks = requireNode(Loader.get("ServerScriptService/Server/Util/Landmarks"))
	check(#Landmarks.find("Altar", "Side", "light") == 1, "Landmarks.find(Altar, Side=light) = 1")
	check(Landmarks.plotPart("FusionMachine", 3) ~= nil, "Landmarks.plotPart(FusionMachine, 3)")
	local before = #(tagged.Shrine or {})
	Landmarks.ensure({
		tag = "Shrine",
		name = "SecretShrine",
		label = "x",
		position = roblox.Vector3.new(0, 0, 0),
		size = roblox.Vector3.new(1, 1, 1),
		color = roblox.Color3.new(1, 1, 1),
	})
	check(#(tagged.Shrine or {}) == before, "Landmarks.ensure 가 임시 Shrine 을 안 만듦")

	print("[펫]")
end

-- 펫·우리·경비·알 검사 (맵 검사가 실패해도 따로 돎: 가짜 베이스·우리 파트를 직접 만듦)
local function petsBody()
	local Pets = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Pets"))
	local Visuals = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Visuals"))
	local PVS = requireNode(Loader.get("ServerScriptService/Server/Services/PetVisualService"))
	local total, maxParts, maxId, minParts, minId = 0, 0, "", math.huge, ""
	local byBody = {}
	for _, pet in Pets.list do
		local m = PVS.build(pet.id, 1, { effects = true })
		local n = count(m)
		total += n
		local body = Visuals.pet(pet.id).body
		byBody[body] = byBody[body] or { n = 0, sum = 0, min = math.huge }
		byBody[body].n += 1
		byBody[body].sum += n
		byBody[body].min = math.min(byBody[body].min, n)
		if n > maxParts then
			maxParts, maxId = n, pet.id
		end
		if n < minParts then
			minParts, minId = n, pet.id
		end
		local h = m:GetAttribute("Height")
		check(type(h) == "number" and h > 0.5 and h < 8, pet.id .. " Height " .. tostring(h))
		check(m.PrimaryPart ~= nil and m.PrimaryPart.Name == "Root", pet.id .. " Root")
	end
	for id in Visuals.extra do
		PVS.build(id, 2.4, { effects = false, rarity = "secret" })
	end
	local avg = total / #Pets.list
	print(
		string.format(
			"  pets built: %d  avg parts: %.1f  min: %d (%s)  max: %d (%s)",
			#Pets.list,
			avg,
			minParts,
			minId,
			maxParts,
			maxId
		)
	)
	local bodyNames = {}
	for name in byBody do
		table.insert(bodyNames, name)
	end
	table.sort(bodyNames)
	local bodyLine = {}
	for _, name in bodyNames do
		local b = byBody[name]
		table.insert(bodyLine, string.format("%s %d/%d", name, b.min, math.floor(b.sum / b.n)))
	end
	print("  체형별 최소/평균: " .. table.concat(bodyLine, ", "))
	check(#Pets.list > 100, "펫 모델 전부 만듦")
	check(avg >= 30 and avg <= 80, "펫 평균 파트 수 30~80: " .. string.format("%.1f", avg))
	check(minParts >= 20 and maxParts <= 110, "펫 파트 수 범위 (최소 20, 최대 110)")

	-- 우리 진열: 가짜 베이스(PlotIndex 99) + 우리 파트(앞 = +X 쪽으로 돌림)
	local Sessions = requireNode(Loader.get("ServerScriptService/Server/Sessions"))
	local fakePlayer = { UserId = 77, Name = "Tester", DisplayName = "Tester" }
	Players.GetPlayerByUserId = function(_, id)
		return if id == 77 then fakePlayer else nil
	end
	local session = Sessions.create(fakePlayer)
	local petsList, equipped = {}, {}
	for i = 1, 20 do
		local pet = Pets.list[(i * 7) % #Pets.list + 1]
		table.insert(petsList, {
			uid = "p" .. i,
			petId = pet.id,
			size = if i % 3 == 0 then "giant" else "normal",
			mutations = if i % 4 == 0 then { "golden" } else {},
		})
		table.insert(equipped, "p" .. i)
	end
	session.data = { pets = petsList, equipped = equipped }
	session.loaded = true
	local base = Instance.new("Folder")
	base.Name = "FakePlot"
	base.Parent = Workspace
	local floor = Instance.new("Part")
	floor.Size = roblox.Vector3.new(60, 1, 60)
	floor.CFrame = roblox.CFrame.new(500, 0, 500)
	floor:SetAttribute("PlotIndex", 99)
	floor:SetAttribute("OwnerUserId", 77)
	floor.Parent = base
	CollectionService:AddTag(floor, "Plot")
	local pen = Instance.new("Part")
	pen.Size = roblox.Vector3.new(36, 0.2, 24)
	-- LookVector = +X (우리 앞이 +X 쪽)
	pen.CFrame = roblox.CFrame.lookAt(roblox.Vector3.new(500, 0.6, 500), roblox.Vector3.new(501, 0.6, 500))
	pen:SetAttribute("PlotIndex", 99)
	pen.Parent = base
	CollectionService:AddTag(pen, "PenArea")
	PVS.refreshPens()
	local penPets = {}
	for _, m in base:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("PetUid") then
			table.insert(penPets, m)
		end
	end
	check(#penPets == 18, "우리 진열 18마리 (최대): " .. #penPets)
	local inside, facing, inBack, labels = 0, 0, 0, 0
	for _, m in penPets do
		local cf = m.PrimaryPart.CFrame
		local lp = pen.CFrame:PointToObjectSpace(cf.Position)
		if math.abs(lp.X) <= pen.Size.X / 2 and math.abs(lp.Z) <= pen.Size.Z / 2 then
			inside += 1
		end
		-- 펫 앞(-Z) = 우리 LookVector
		if cf.LookVector:Dot(pen.CFrame.LookVector) > 0.99 then
			facing += 1
		end
		-- 우리 뒤쪽 2/3 (앞 = 로컬 -Z)
		if lp.Z >= -pen.Size.Z / 6 - 0.01 then
			inBack += 1
		end
		local tag = m.PrimaryPart:FindFirstChild("PetTag")
		if tag and tag:FindFirstChild("Rarity") and tag:FindFirstChild("PetName") then
			local income = tag:FindFirstChild("Income")
			if income and string.sub(income.Text, 1, 1) == "$" and string.sub(income.Text, -2) == "/s" then
				labels += 1
			end
		end
	end
	check(inside == #penPets, "우리 펫이 전부 우리 직사각형 안: " .. inside)
	check(facing == #penPets, "우리 펫이 전부 우리 앞(LookVector)을 봄: " .. facing)
	check(inBack == #penPets, "우리 펫이 전부 우리 뒤쪽 2/3: " .. inBack)
	check(labels == #penPets, "이름표 3줄 (희귀도/이름/$수입/s): " .. labels)
	if penPets[1] then
		local tag = penPets[1].PrimaryPart:FindFirstChild("PetTag")
		print("  label:", tag.Rarity.Text, "/", tag.PetName.Text, "/", tag.Income.Text)
	end
	local penTotal = 0
	for _, m in penPets do
		penTotal += count(m)
	end
	print("  pen parts (18 pets):", penTotal)

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
	local dressed, tall, grounded = 0, 0, 0
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
			-- 서 있을 때 발바닥(Root) 높이 = 땅(0)
			fire(g.guard, "State") -- Idle → 잠
		end
	end
	check(dressed == 15, "경비 겉모습 15구역 전부 붙음: " .. dressed)
	check(tall == 15, string.format("경비 키 25~40 스터드: %d (최소 %.1f, 최대 %.1f)", tall, minH, maxH))
	local forest = guards.forest
	if forest then
		local visual = forest.guard:FindFirstChild(forest.model)
		local z = visual and visual:FindFirstChild("SleepZ", true)
		check(z ~= nil and z:IsA("BillboardGui") and z.Enabled == true, "Idle 이면 머리 위 Z (SleepZ 켜짐)")
		local glow = visual and visual:FindFirstChild("GuardGlow")
		check(glow ~= nil and glow.Enabled == false, "Idle 이면 빨간 테두리 꺼짐")
		forest.guard:SetAttribute("State", "Chase")
		fire(forest.guard, "State")
		check(z ~= nil and z.Enabled == false, "Chase 면 Z 숨김")
		check(glow ~= nil and glow.Enabled == true, "Chase 면 빨간 테두리 켜짐")
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

	print("[알]")
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
			{ "chicken", "", false, "common" },
			{ "unicorn", "golden,bloom", true, "divine" },
			{ "kraken", "rainbow", true, "secret" },
			{ "yeti", "silver", false, "secret" },
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
		local inc = Instance.new("Part")
		inc.Size = roblox.Vector3.new(2, 2, 2)
		inc:SetAttribute("PetId", spec[1])
		inc:SetAttribute("Mutations", spec[2])
		inc.Parent = eggs
		CollectionService:AddTag(inc, "IncubatingEgg")
	end
	local EVS = requireNode(Loader.get("ServerScriptService/Server/Services/EggVisualService"))
	EVS.started = false
	EVS.start()
	local shells, layered = 0, 0
	for _, e in eggs:GetChildren() do
		local v = e:FindFirstChild("EggVisual")
		if v then
			shells += 1
			local layers = 0
			for _, c in v:GetChildren() do
				if c.Name == "Layer" then
					layers += 1
				end
			end
			if layers >= 5 and layers <= 7 then
				layered += 1
			end
		end
	end
	check(shells == 8, "알 껍데기 8개 (둥지 알 4 + 부화 중 4): " .. shells)
	check(layered == 8, "알이 계단형 층 5~7개: " .. layered)
	check(#(tagged.EggShell or {}) > 0, "EggShell 태그 붙음")
	local weight = carriedEgg and carriedEgg:FindFirstChild("WeightTag")
	check(weight ~= nil and weight.Enabled == true, "든 알 무게 이름표(WeightTag) 켜짐")
	if weight then
		local kg = weight:FindFirstChild("Kg")
		check(kg ~= nil and kg.Text == "4,740Kg", "무게 글자 4,740Kg: " .. tostring(kg and kg.Text))
		print("  weight:", weight.Gender.Text, kg and kg.Text)
	end
	local nestEgg = eggs:GetChildren()[3]
	local nestWeight = nestEgg and nestEgg:FindFirstChild("WeightTag")
	check(nestWeight == nil or nestWeight.Enabled == false, "둥지 알은 무게 이름표 숨김")
	print("  egg visual parts:", count(eggs))
end

local mapOk, mapErr = pcall(body)
if not mapOk then
	failures += 1
	print("ERROR (맵): " .. tostring(mapErr))
end
local ok, err = pcall(petsBody)
if not ok then
	print("ERROR: " .. tostring(err))
	process.exit(1)
end
if failures > 0 then
	print(string.format("SMOKE VISUALS: %d 실패", failures))
	process.exit(1)
end
print("SMOKE VISUALS OK")
