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
		check(sides.light.CFrame.Position.Z < zone.centerZ, "천국 제단은 천국(-Z) 쪽")
		check(sides.dark.CFrame.Position.Z > zone.centerZ, "지옥 제단은 지옥(+Z) 쪽")
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
	local Pets = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Pets"))
	local Visuals = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Visuals"))
	local PVS = requireNode(Loader.get("ServerScriptService/Server/Services/PetVisualService"))
	local total, maxParts, maxId = 0, 0, ""
	for _, pet in Pets.list do
		local m = PVS.build(pet.id, 1.3, { effects = true })
		local n = count(m)
		total += n
		if n > maxParts then
			maxParts, maxId = n, pet.id
		end
	end
	for id in Visuals.extra do
		PVS.build(id, 2.4, { effects = false, rarity = "secret" })
	end
	print("  pets built:", #Pets.list, "avg parts:", math.floor(total / #Pets.list), "max:", maxParts, maxId)
	check(#Pets.list > 100, "펫 모델 전부 만듦")

	-- 우리 진열: 가짜 플레이어 세션
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
	local plot1 = MapBuilder.getPlot(1)
	plot1.floor:SetAttribute("OwnerUserId", 77)
	PVS.refreshPens()
	local penPets = 0
	for _, m in plot1.floor.Parent:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("PetUid") then
			penPets += 1
		end
	end
	check(penPets == 18, "우리 진열 18마리 (최대): " .. penPets)

	-- 경비 겉모습
	local guard = Instance.new("Model")
	guard.Name = "Guard_forest"
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = roblox.Vector3.new(4, 4, 3)
	hrp.CFrame = roblox.CFrame.new(0, 5, 0)
	hrp.Parent = guard
	local hum = Instance.new("Humanoid")
	hum.HipHeight = 2.5
	hum.Parent = guard
	guard.PrimaryPart = hrp
	guard:SetAttribute("BiomeId", "forest")
	guard.Parent = Workspace
	CollectionService:AddTag(guard, "Guardian")
	PVS.started = false
	PVS.start()
	check(guard:FindFirstChild("chicken") ~= nil, "경비 겉모습(닭) 붙음")

	print("[알]")
	local eggs = Instance.new("Folder")
	eggs.Parent = Workspace
	for _, spec in
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
		p.Parent = eggs
		CollectionService:AddTag(p, "Egg")
		local inc = Instance.new("Part")
		inc.Size = roblox.Vector3.new(2, 2, 2)
		inc:SetAttribute("PetId", spec[1])
		inc.Parent = eggs
		CollectionService:AddTag(inc, "IncubatingEgg")
	end
	local EVS = requireNode(Loader.get("ServerScriptService/Server/Services/EggVisualService"))
	EVS.started = false
	EVS.start()
	local shells = 0
	for _, e in eggs:GetChildren() do
		if e:FindFirstChild("EggVisual") then
			shells += 1
		end
	end
	check(shells == 8, "알 껍데기 8개 (둥지 알 4 + 부화 중 4): " .. shells)
	print("  egg visual parts:", count(eggs))
end

local ok, err = pcall(body)
if not ok then
	print("ERROR: " .. tostring(err))
	process.exit(1)
end
if failures > 0 then
	print(string.format("SMOKE VISUALS: %d 실패", failures))
	process.exit(1)
end
print("SMOKE VISUALS OK")
