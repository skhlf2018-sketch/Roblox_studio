--!nocheck
--[[
	클라 화면 스모크 테스트 (선임) — 저장소 루트에서:  lune run tests/smoke_client.luau
	(tests/run.luau 에는 안 들어감. 로블록스 없이 @lune/roblox 진짜 GUI 인스턴스로 화면을 만들어 보며
	 속성 이름·타입 오타, nil 인덱싱 같은 실행 오류를 잡습니다. 보기 좋은지는 스튜디오 기기 에뮬레이터로)

	하는 일: 클라 컨트롤러 전부 start() → Snapshot → 창 전부 열기·버튼 누르기
	        → 2단계: 퓨전 머신·사쿠라·제단·비밀 통로 프롬프트 누르기 → 펫 고르기 창에서 카드 고르고 확인
	          → 보낸 Remote 이름·인자 확인 → 결과 이벤트(FusionResult/SakuraResult/AltarUpdate/ShrineResult/QuestUpdate)
	        → 무기 손 모양 붙이기·휘두르기, 폰 화면에서 버튼 크기(46px 이상) 계산 확인
	task.wait 는 바로 멈추고(무한 루프 방지), task.delay 는 바로 실행합니다.
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

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end }
		end,
		Wait = function() end,
		Fire = function(_, ...)
			for _, h in table.clone(handlers) do
				h(...)
			end
		end,
	}
end

local CLASSES = {
	"Frame",
	"TextLabel",
	"TextButton",
	"ScrollingFrame",
	"ViewportFrame",
	"ScreenGui",
	"Folder",
	"NumberValue",
	"Model",
	"Part",
	"Camera",
	"BillboardGui",
	"UIScale",
	"Player",
	"Workspace",
	"Highlight",
	"ProximityPrompt",
	"Tool",
	"Backpack",
	"Weld",
	"Humanoid",
	"Backpack",
}
local EVENTS = {
	"MouseButton1Down",
	"MouseButton1Up",
	"MouseLeave",
	"MouseEnter",
	"Activated",
	"Destroying",
	"AncestryChanged",
	"ChildAdded",
	"ChildRemoved",
	"Changed",
	"CharacterAdded",
	"Triggered",
}
local signalCache = {}
local sidCounter = 0
local function sigOf(inst, ev)
	local id = inst:GetAttribute("__sid")
	if not id then
		sidCounter += 1
		id = sidCounter
		inst:SetAttribute("__sid", id)
	end
	signalCache[id] = signalCache[id] or {}
	local s = signalCache[id][ev]
	if not s then
		s = signal()
		signalCache[id][ev] = s
	end
	return s
end
for _, cls in CLASSES do
	for _, ev in EVENTS do
		pcall(roblox.implementProperty, cls, ev, function(inst)
			return sigOf(inst, ev)
		end)
	end
	pcall(roblox.implementMethod, cls, "GetAttributeChangedSignal", function(inst, name)
		return sigOf(inst, "Attr_" .. name)
	end)
	pcall(roblox.implementMethod, cls, "GetPropertyChangedSignal", function()
		return signal()
	end)
	pcall(roblox.implementMethod, cls, "WaitForChild", function(self, name)
		return self:FindFirstChild(name)
	end)
end
roblox.implementMethod("Model", "PivotTo", function() end)
roblox.implementMethod("Model", "GetBoundingBox", function()
	return roblox.CFrame.new(0, 1.5, 0), roblox.Vector3.new(2, 3, 2)
end)
roblox.implementMethod("Model", "GetPivot", function()
	return roblox.CFrame.new()
end)

pcall(roblox.implementMethod, "Humanoid", "EquipTool", function() end)
pcall(roblox.implementMethod, "ParticleEmitter", "Emit", function() end)
pcall(roblox.implementMethod, "Humanoid", "UnequipTools", function() end)

-- 태그 (테스트가 직접 채움)
local tagged = {}
local function tag(inst, name)
	tagged[name] = tagged[name] or {}
	table.insert(tagged[name], inst)
end
local CollectionService = {
	AddTag = function(_, inst, name)
		tag(inst, name)
	end,
	GetTagged = function(_, name)
		return table.clone(tagged[name] or {})
	end,
	GetInstanceAddedSignal = function()
		return signal()
	end,
	GetInstanceRemovedSignal = function()
		return signal()
	end,
}

local player = Instance.new("Player")
pcall(function()
	player.UserId = 77
end)
local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
local backpack = Instance.new("Backpack")
backpack.Parent = player
player:SetAttribute("Money", 12345)
player:SetAttribute("Speed", 999)
player:SetAttribute("PlotIndex", 1)
player:SetAttribute("SakuraCrystals", 3)
player:SetAttribute("SakuraUnlocked", false)

-- 캐릭터 (R15 RightHand)
local character = Instance.new("Model")
character.Name = "Tester"
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.CFrame = roblox.CFrame.new(0, 3, 0)
root.Position = roblox.Vector3.new(0, 3, 0)
root.Parent = character
local hand = Instance.new("Part")
hand.Name = "RightHand"
hand.CFrame = roblox.CFrame.new(1.5, 3, 0)
hand.Position = roblox.Vector3.new(1.5, 3, 0)
hand.Parent = character
local head = Instance.new("Part")
head.Name = "Head"
head.Position = roblox.Vector3.new(0, 4.5, 0)
head.Parent = character
Instance.new("Humanoid").Parent = character
character.Parent = Workspace
player.Character = character

local Players = {
	LocalPlayer = player,
	PlayerAdded = signal(),
	GetPlayers = function()
		return { player }
	end,
}
local waits = 0
local tweenStub = {
	Create = function()
		local done = signal()
		done.Wait = function()
			waits += 1
			if waits > 400 then
				error("__STOP__")
			end
		end
		return { Play = function() end, Cancel = function() end, Completed = done }
	end,
}
local fakeServices = {
	CollectionService = CollectionService,
	Players = Players,
	TweenService = tweenStub,
	RunService = {
		RenderStepped = signal(),
		Heartbeat = signal(),
		IsStudio = function()
			return false
		end,
	},
	UserInputService = {
		TouchEnabled = true,
		KeyboardEnabled = false,
		MouseEnabled = false,
		InputBegan = signal(),
		LastInputTypeChanged = signal(),
		GetLastInputType = function()
			return roblox.Enum.UserInputType.Touch
		end,
	},
	-- 새 로블록스 상단 메뉴 인셋 58px (스튜디오 에뮬레이터 측정: 381 - 323)
	GuiService = {
		GetGuiInset = function()
			return roblox.Vector2.new(0, 58), roblox.Vector2.new(0, 0)
		end,
	},
	StarterGui = { SetCoreGuiEnabled = function() end },
	SoundService = game:GetService("SoundService"),
	Lighting = game:GetService("Lighting"),
	TextChatService = {
		FindFirstChild = function()
			return nil
		end,
	},
	Workspace = Workspace,
}

local function warm(node)
	local getChildren = node.GetChildren
	for _, child in getChildren(node) do
		warm(child)
	end
end
warm(Loader.get("ReplicatedStorage"))

-- PetModels 도서관 흉내
local library = Instance.new("Folder")
library.Name = "PetModels"
for _, id in { "chicken", "unicorn", "dog", "crane", "pegasus", "skeleton_horse" } do
	local m = Instance.new("Model")
	m.Name = id
	local p = Instance.new("Part")
	p.Parent = m
	m.PrimaryPart = p
	m.Parent = library
end

local sharedNode = Loader.get("ReplicatedStorage")
fakeServices.ReplicatedStorage = setmetatable({}, {
	__index = function(_, key)
		if key == "Shared" or key == "Client" then
			return sharedNode[key]
		end
		if key == "FindFirstChild" or key == "WaitForChild" then
			return function(_, name)
				if name == "PetModels" then
					return library
				end
				return nil
			end
		end
		return nil
	end,
})

local fakeGame = {
	GetService = function(_, name)
		local s = fakeServices[name]
		if s then
			return s
		end
		error("no service stub " .. name)
	end,
	IsLoaded = function()
		return true
	end,
}

-- Net 흉내: 핸들러를 모아 두고 직접 부름
local handlers = {}
local sent = {}
local NetStub = {
	on = function(name, fn)
		assert(typeof(name) == "string", "Net.on 이름이 문자열이 아님")
		handlers[name] = handlers[name] or {}
		table.insert(handlers[name], fn)
		return { Disconnect = function() end }
	end,
	send = function(name, ...)
		table.insert(sent, { name = name, args = { ... } })
	end,
	trySend = function(name, ...)
		table.insert(sent, { name = name, args = { ... } })
		return true
	end,
	get = function() end,
}
NetStub.onLater = NetStub.on
local function fire(name, ...)
	waits = 0
	for _, fn in handlers[name] or {} do
		fn(...)
	end
end
local function lastSent(name)
	for i = #sent, 1, -1 do
		if sent[i].name == name then
			return sent[i]
		end
	end
	return nil
end

local STOP = "__STOP__"
local function runSafe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not string.find(tostring(err), STOP, 1, true) then
		error(err, 0)
	end
end
local delayDepth = 0
local holdDelays = false -- true 면 task.delay 를 실행하지 않음 (잠깐 떠 있는 팝업을 검사할 때)
local taskStub = {
	spawn = runSafe,
	defer = function(fn, ...)
		runSafe(fn, ...)
	end,
	wait = function()
		error(STOP)
	end,
	delay = function(_, fn, ...)
		-- 바로 실행 (연출이 끝까지 도는지 확인). 깊은 재귀는 끊음
		if delayDepth > 20 or holdDelays then
			return
		end
		delayDepth += 1
		runSafe(fn, ...)
		delayDepth -= 1
	end,
}

local cache = {}
local requireNode
local function makeEnv(node)
	return setmetatable({
		script = node,
		game = fakeGame,
		workspace = Workspace,
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
		TweenInfo = {
			new = function()
				return {}
			end,
		},
		Random = {
			new = function()
				return {
					NextNumber = function(_, a, b)
						return (a or 0) + ((b or 1) - (a or 0)) * 0.5
					end,
					NextInteger = function(_, a)
						return a
					end,
				}
			end,
		},
		task = taskStub,
		warn = function(...)
			print("WARN:", ...)
		end,
	}, { __index = _G })
end
requireNode = function(node)
	local props = rawget(node, "__props")
	local file = props.file
	if string.find(file, "client[/\\]Net%.luau$") then
		return NetStub
	end
	if cache[file] ~= nil then
		return cache[file]
	end
	local result = luau.load(fs.readFile(file), { debugName = file, environment = makeEnv(node) })()
	cache[file] = result
	return result
end

local function ctrl(name)
	return requireNode(Loader.get("ReplicatedStorage/Client/Controllers/" .. name))
end
local function uiModule(name)
	return requireNode(Loader.get("ReplicatedStorage/Client/UI/" .. name))
end

------------------------------------------------------------------
-- 월드 특수 장소 흉내 (서버 MapBuilder 가 만드는 것과 같은 태그·Attribute)
------------------------------------------------------------------
local function worldPart(name, pos, size, parentModel)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or roblox.Vector3.new(4, 4, 4)
	p.CFrame = roblox.CFrame.new(pos)
	p.Position = pos -- Lune 은 CFrame 에서 Position 을 계산하지 않아서 둘 다 넣음
	p.Parent = parentModel or Workspace
	return p
end
local fusionModel = Instance.new("Model")
fusionModel.Name = "FusionMachineModel"
fusionModel.Parent = Workspace
local machine = worldPart("FusionMachine", roblox.Vector3.new(4, 3, 0), roblox.Vector3.new(8, 4.5, 5), fusionModel)
machine:SetAttribute("PlotIndex", 1)
worldPart("Core", roblox.Vector3.new(4, 12, 0), nil, fusionModel)
for i = 1, 3 do
	worldPart("Tube" .. i, roblox.Vector3.new(i, 8, 0), nil, fusionModel)
end
tag(machine, "FusionMachine")
local otherMachine = worldPart("FusionMachine", roblox.Vector3.new(200, 3, 0))
otherMachine:SetAttribute("PlotIndex", 2)
tag(otherMachine, "FusionMachine")
local incubator = worldPart("SakuraIncubator", roblox.Vector3.new(0, 1, 5))
tag(incubator, "SakuraIncubator")
local altarLight = worldPart("AltarLight", roblox.Vector3.new(-3, 2, 0))
altarLight:SetAttribute("Side", "light")
altarLight:SetAttribute("PendingCount", 0)
tag(altarLight, "Altar")
local altarDark = worldPart("AltarDark", roblox.Vector3.new(60, 2, 0))
altarDark:SetAttribute("Side", "dark")
altarDark:SetAttribute("PendingCount", 1)
tag(altarDark, "Altar")
local shrine = worldPart("SecretShrine", roblox.Vector3.new(0, 2, -5))
tag(shrine, "Shrine")
local gateModel = Instance.new("Model")
gateModel.Name = "QuestGateModel"
gateModel.Parent = Workspace
local door = worldPart("Door", roblox.Vector3.new(0, 6, 30), roblox.Vector3.new(1, 12, 10), gateModel)
for i = 1, 3 do
	worldPart("Rune" .. i, roblox.Vector3.new(i, 1, 26), nil, gateModel)
end
tag(door, "QuestGate")
local crystal = worldPart("SakuraCrystal_c1", roblox.Vector3.new(3, 1, 3))
tag(crystal, "SakuraCrystal")
-- 2판 월드 흉내: 우리 펫(PenPet) · 우리 안 부화 중 알 · 업그레이드 표지판 · 판매 가게(가까이) · 트레일 상점
local penPet = Instance.new("Model")
penPet.Name = "chicken"
local penPetRoot = worldPart("Root", roblox.Vector3.new(20, 1, 20), nil, penPet)
penPet.PrimaryPart = penPetRoot
penPet:SetAttribute("PetUid", "p1")
penPet.Parent = Workspace
penPet:SetAttribute("Height", 3)
tag(penPet, "PenPet")
local growingEgg = worldPart("Incubating_i2", roblox.Vector3.new(25, 1, 20), roblox.Vector3.new(2, 2.5, 2))
growingEgg:SetAttribute("EggUid", "i2")
growingEgg:SetAttribute("OwnerUserId", player.UserId)
growingEgg:SetAttribute("PetId", "chicken")
growingEgg:SetAttribute("Progress", 5)
growingEgg:SetAttribute("Required", 5)
growingEgg:SetAttribute("Ready", true)
tag(growingEgg, "IncubatingEgg")
local upgradeSign = worldPart("UpgradeSign", roblox.Vector3.new(30, 4, 20), roblox.Vector3.new(8, 4.6, 0.8))
upgradeSign:SetAttribute("Kind", "Treadmill")
upgradeSign:SetAttribute("PlotIndex", 1)
tag(upgradeSign, "UpgradeSign")
local sellStall = worldPart("SellStall", roblox.Vector3.new(4, 2, 4), roblox.Vector3.new(7, 3.4, 3))
tag(sellStall, "SellStall")
local trailShop = worldPart("TrailShop", roblox.Vector3.new(60, 2, -260), roblox.Vector3.new(12, 3.4, 3))
tag(trailShop, "TrailShop")

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------
game:GetService("Lighting").ClockTime = 14
local cam = Instance.new("Camera")
cam.ViewportSize = roblox.Vector2.new(844, 390) -- 폰 가로
cam.Parent = Workspace
Workspace.CurrentCamera = cam

local function body()
	print("[컨트롤러 시작]")
	local State = requireNode(Loader.get("ReplicatedStorage/Client/State"))
	State.start()
	for _, name in
		{
			"ZoneController",
			"SoundController",
			"LightingController",
			"HudController",
			"NotifyController",
			"ChaseController",
			"IncubatorController",
			"HatchController",
			"IndexController",
			"PetsController",
			"ShopController",
			"GiftController",
			"SettingsController",
			"HotbarController",
			"WorldFxController",
			"FusionController",
			"SakuraController",
			"AltarController",
			"QuestController",
			"WeaponController",
			"TreadmillController",
			"TrailController",
		}
	do
		ctrl(name).start()
		check(true, "start " .. name)
	end

	local snapshot = {
		money = 12345,
		speed = 100,
		effectiveSpeed = 100,
		incomePerSecond = 10,
		pets = {
			{ uid = "p1", petId = "chicken", size = "normal", mutations = {} },
			{ uid = "p2", petId = "chicken", size = "big", mutations = {} },
			{ uid = "p3", petId = "chicken", size = "normal", mutations = {} },
			{ uid = "p4", petId = "unicorn", size = "giant", mutations = { "golden" } },
			{ uid = "p5", petId = "crane", size = "normal", mutations = {} },
			{ uid = "p6", petId = "pegasus", size = "normal", mutations = {} },
			{ uid = "p7", petId = "skeleton_horse", size = "normal", mutations = {} },
			{ uid = "p8", petId = "dog", size = "normal", mutations = { "bloom" } },
		},
		equipped = { "p1" },
		penLevel = 1,
		penSlots = 7,
		treadmillLevel = 0,
		trails = { "grey", "blue" },
		equippedTrail = "grey",
		trailMultiplier = 1.5,
		indexDiscovered = { chicken = true, dog = true },
		indexClaimed = { chicken = true },
		indexCompleteClaimed = false,
		unlockedWeapons = {},
		tools = { bearTrap = 3 },
		incubators = {
			{
				uid = "i1",
				petId = "dog",
				size = "normal",
				mutations = {},
				biomeId = "forest",
				slot = 1,
				progress = 3,
				required = 5,
			},
			{
				uid = "i2",
				petId = "chicken",
				size = "normal",
				mutations = {},
				biomeId = "forest",
				slot = 2,
				progress = 5,
				required = 5,
			},
		},
		eggQueue = {},
		freeRewardClaimed = false,
		plotIndex = 1,
		saveEnabled = true,
		sakuraCrystals = 3,
		sakuraUnlocked = false,
		shrineUsed = {},
		quests = {
			{
				id = "deliver_eggs",
				name = "마법의 숲 알 20개 배달하기",
				progress = 4,
				target = 20,
				done = false,
			},
			{
				id = "fuse_once",
				name = "퓨전 머신으로 동물 합성하기",
				progress = 0,
				target = 1,
				done = false,
			},
			{ id = "deliver_eternal", name = "영원 알 1개 배달하기", progress = 0, target = 1, done = false },
		},
		questsDone = false,
		petInventoryMax = 500,
	}
	fire("Snapshot", snapshot)
	check(true, "Snapshot 처리")

	local Windows = uiModule("Windows")
	local Ui = uiModule("Ui")
	local function findButton(text, under)
		for _, d in (under or playerGui):GetDescendants() do
			if d:IsA("TextButton") and string.find(d.Text, text, 1, true) and d.Parent ~= nil then
				return d
			end
		end
		return nil
	end
	local function click(button)
		if not button then
			return false
		end
		local id = button:GetAttribute("__sid")
		local s = id and signalCache[id] and signalCache[id].Activated
		if s then
			s:Fire()
			return true
		end
		return false
	end
	local function clickText(text, under)
		return click(findButton(text, under))
	end
	local function promptOf(part, name)
		local prompt = part:FindFirstChild(name)
		return prompt
	end
	local function trigger(prompt)
		local id = prompt and prompt:GetAttribute("__sid")
		local s = id and signalCache[id] and signalCache[id].Triggered
		if s then
			s:Fire(player)
			return true
		end
		return false
	end
	local function pickerRoot()
		local screen = playerGui:FindFirstChild("StealAnEggUI")
		local layer = screen and screen:FindFirstChild("Windows")
		local picker = layer and layer:FindFirstChild("PetPicker")
		return picker
	end
	local function pickCard(uid)
		local picker = pickerRoot()
		local card = picker and picker:FindFirstChild(uid, true)
		return click(card)
	end
	local function pickerConfirm()
		local picker = pickerRoot()
		local b = picker and picker:FindFirstChild("Confirm", true)
		return b, click(b)
	end

	print("[창 (2판 원작 스타일)]")
	for _, w in { "Index", "Pets", "Shop", "Gift", "Settings", "Trail" } do
		Windows.open(w)
		check(Windows.isOpen(w), "창 열기 " .. w)
	end
	-- 상점: 업그레이드 카드 사기 / 트레일 탭 → 트레일 상점 창 / 로벅스 탭은 준비 중
	Windows.open("Shop")
	local penCard = playerGui:FindFirstChild("PenCard", true)
	check(penCard and click(penCard:FindFirstChild("Buy")), "상점 펫 우리 업그레이드 사기 누름")
	check(lastSent("PurchaseUpgrade") and lastSent("PurchaseUpgrade").args[1] == "Pen", "PurchaseUpgrade(Pen) 보냄")
	check(click(playerGui:FindFirstChild("Tab_speed", true)), "상점 속도 탭 (로벅스)")
	check(findButton("준비 중") ~= nil, "로벅스 상품은 '준비 중'")
	check(
		click(playerGui:FindFirstChild("Tab_trail", true)) and Windows.isOpen("Trail"),
		"상점 트레일 탭 → 트레일 상점 창"
	)
	local trailCard = playerGui:FindFirstChild("Trail_green", true)
	check(
		trailCard and trailCard:FindFirstChild("SpeedBadge") and trailCard.SpeedBadge.Text == "x2 스피드",
		"트레일 카드 'x2 스피드' 배지"
	)
	check(click(trailCard and trailCard:FindFirstChild("BuyTrail")), "트레일 사기 누름")
	local tr = lastSent("PurchaseUpgrade")
	check(tr and tr.args[1] == "Trail" and tr.args[2] == "green", "PurchaseUpgrade(Trail, green) 보냄")
	local greyCard = playerGui:FindFirstChild("Trail_grey", true)
	check(
		greyCard and greyCard:FindFirstChild("Unequip") and greyCard.Unequip.Text == "장착 해제",
		"장착 중인 트레일 = '장착 해제'"
	)
	check(click(greyCard and greyCard:FindFirstChild("Unequip")), "트레일 장착 해제 누름")
	local eq = lastSent("EquipTrail")
	check(eq and eq.args[1] == "none", "EquipTrail(none) 보냄")
	local blueCard = playerGui:FindFirstChild("Trail_blue", true)
	check(
		blueCard and blueCard:FindFirstChild("Equip") and blueCard.Equip.Text == "장착",
		"가졌지만 장착 안 한 트레일 = '장착'"
	)
	check(click(blueCard and blueCard:FindFirstChild("Equip")), "트레일 장착 누름")
	eq = lastSent("EquipTrail")
	check(eq and eq.args[1] == "blue", "EquipTrail(blue) 보냄")
	fire("DataUpdate", "upgrades", { equippedTrail = "blue", trailMultiplier = 2.5 })
	blueCard = playerGui:FindFirstChild("Trail_blue", true)
	greyCard = playerGui:FindFirstChild("Trail_grey", true)
	check(
		blueCard and blueCard:FindFirstChild("Unequip") and greyCard and greyCard:FindFirstChild("Equip"),
		"DataUpdate(upgrades) 뒤 카드 갱신 (blue 장착 해제 / grey 장착)"
	)
	player:SetAttribute("EquippedTrail", "blue")
	sigOf(player, "Attr_EquippedTrail"):Fire()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	check(
		hrp and hrp:FindFirstChild("EquippedTrailFx") and hrp.EquippedTrailFx:IsA("Trail"),
		"캐릭터에 장착 트레일 꼬리"
	)
	player:SetAttribute("EquippedTrail", "none")
	sigOf(player, "Attr_EquippedTrail"):Fire()
	check(hrp and hrp:FindFirstChild("EquippedTrailFx") == nil, "해제하면 꼬리 사라짐")
	-- 인덱스: 숲 카드 → 개 고르기 → 획득! / 다른 구역 탭 / 모두 획득
	Windows.open("Index")
	check(click(playerGui:FindFirstChild("Tab_lake", true)), "인덱스 구역 탭 (호수)")
	check(click(playerGui:FindFirstChild("Tab_forest", true)), "인덱스 구역 탭 (숲)")
	check(click(playerGui:FindFirstChild("Card_dog", true)), "인덱스 카드 (개) 고름")
	local detailName = playerGui:FindFirstChild("Detail", true):FindFirstChild("PetName", true)
	check(
		detailName and detailName.Text ~= "???",
		"고른 펫 이름 보임: " .. tostring(detailName and detailName.Text)
	)
	check(click(playerGui:FindFirstChild("Claim", true)), "인덱스 획득! 누름")
	check(
		lastSent("ClaimIndexReward") and lastSent("ClaimIndexReward").args[1] == "dog",
		"ClaimIndexReward(dog) 보냄"
	)
	local claimAll = playerGui:FindFirstChild("ClaimAll", true)
	check(claimAll and claimAll.Visible and claimAll.Text == "모두 획득 (1)!", "모두 획득 (1)! 버튼")
	check(click(claimAll) and lastSent("ClaimIndexReward").args[1] == "all", "ClaimIndexReward(all) 보냄")
	check(click(playerGui:FindFirstChild("NextPet", true)), "다음 펫 > 버튼")
	-- 펫 창: 장착 / 최고 펫 / 판매 가게 근처면 판매 버튼
	Windows.open("Pets")
	check(click(playerGui:FindFirstChild("Equip", true)), "펫 장착 누름")
	check(lastSent("EquipPet") ~= nil, "EquipPet 보냄")
	check(clickText("최고 펫"), "최고 펫 장착 누름")
	local sell = playerGui:FindFirstChild("Sell", true)
	check(
		sell ~= nil and string.find(sell.Text, "판매", 1, true) ~= nil,
		"판매 가게 근처: 카드에 판매 버튼 (" .. tostring(sell and sell.Text) .. ")"
	)
	check(click(sell) and lastSent("SellPet") ~= nil, "SellPet(uid) 보냄")
	Windows.open("Settings")
	check(clickText("켜짐"), "설정 토글")

	print("[폰 버튼 크기 (844x390, 46px 이상)]")
	local screen = playerGui:FindFirstChild("StealAnEggUI")
	local windowsLayer = screen and screen:FindFirstChild("Windows")
	local function px(button, holderName)
		local holder = windowsLayer:FindFirstChild(holderName)
		local s = Ui.fitScale(roblox.Vector2.new(holder.Size.X.Offset, holder.Size.Y.Offset))
		return (button and button.Size.Y.Offset or 0) * s
	end
	for _, w in { "Index", "Pets", "Shop", "Gift", "Settings", "PetPicker", "Trail" } do
		local holder = windowsLayer and windowsLayer:FindFirstChild(w)
		local header = holder and holder:FindFirstChild("Header", true)
		local x = header and header:FindFirstChild("Button")
		if holder then
			check(px(x, w) >= 45.9, string.format("%s 창 닫기 X %.1fpx", w, px(x, w)))
		end
	end
	Windows.open("Pets")
	local equipButton = playerGui:FindFirstChild("Equip", true)
	check(px(equipButton, "Pets") >= 45.9, string.format("펫 장착 버튼 %.1fpx", px(equipButton, "Pets")))
	check(px(playerGui:FindFirstChild("Sell", true), "Pets") >= 45.9, "펫 판매 버튼 46px 이상")
	Windows.open("Index")
	check(px(playerGui:FindFirstChild("Claim", true), "Index") >= 45.9, "인덱스 획득! 버튼 46px 이상")
	check(px(playerGui:FindFirstChild("ClaimAll", true), "Index") >= 45.9, "인덱스 모두 획득 46px 이상")
	check(px(playerGui:FindFirstChild("Tab_forest", true), "Index") >= 45.9, "인덱스 구역 탭 46px 이상")
	Windows.open("Shop")
	click(playerGui:FindFirstChild("Tab_upgrades", true))
	check(px(playerGui:FindFirstChild("Buy", true), "Shop") >= 45.9, "상점 사기 버튼 46px 이상")
	check(px(playerGui:FindFirstChild("Tab_featured", true), "Shop") >= 45.9, "상점 탭 46px 이상")
	Windows.open("Trail")
	check(px(playerGui:FindFirstChild("BuyTrail", true), "Trail") >= 45.9, "트레일 사기 버튼 46px 이상")
	Windows.close()

	print("[2판 HUD · 알 들기 · 러닝머신 · 구역 배너 · 돈 팝업 · 부화]")
	local hudLayer0 = screen:FindFirstChild("Hud")
	check(
		hudLayer0:FindFirstChild("Stats") and hudLayer0.Stats:FindFirstChild("Speed", true),
		"왼쪽 아래 속도·돈"
	)
	check(hudLayer0:FindFirstChild("Timer") ~= nil, "오른쪽 아래 남은 시간")
	local Hud0 = ctrl("HudController")
	check(
		Hud0.koreanClock(238) == "3분 58초" and Hud0.koreanClock(52) == "52초 안에",
		"시간 글자 '3분 58초' / '52초 안에'"
	)
	-- 알 버튼 → 성장하는 달걀 패널
	check(click(playerGui:FindFirstChild("EggButton", true)), "주황 알 버튼 누름")
	local panel = playerGui:FindFirstChild("GrowingEggs", true)
	check(panel and panel.Visible, "성장하는 달걀 패널 열림")
	check(
		panel and panel:FindFirstChild("i1", true) and panel:FindFirstChild("i2", true),
		"패널에 자라는 알 2줄"
	)
	check(click(panel and panel:FindFirstChild("Play", true)), "▶ 버튼")
	local Inc = ctrl("IncubatorController")
	check(Inc.shortTime(112) == "1m 52s" and Inc.shortTime(300) == "5m", "알 시간 글자 '1m 52s' / '5m'")
	check(
		click(playerGui:FindFirstChild("PetsButton", true)) and Windows.isOpen("Pets"),
		"주황 발바닥 버튼 → 펫 창"
	)
	Windows.close()
	-- 우리 안 부화 중 알: "에그 / 시간" 이름표 + 부화 프롬프트
	check(growingEgg:FindFirstChild("GrowTag") ~= nil, "우리 안 알 위 '에그' 이름표")
	local hatchPrompt = growingEgg:FindFirstChild("HatchPrompt")
	check(hatchPrompt and hatchPrompt.ActionText == "부화!", "내 알에 '부화!' 프롬프트")
	check(trigger(hatchPrompt) and lastSent("HatchEgg").args[1] == "i2", "프롬프트 → HatchEgg(i2)")
	-- 업그레이드 표지판 프롬프트
	local signPrompt = upgradeSign:FindFirstChild("UpgradePrompt")
	check(signPrompt and signPrompt.Enabled == true, "내 베이스 업그레이드 표지판 프롬프트")
	check(
		trigger(signPrompt) and lastSent("PurchaseUpgrade").args[1] == "Treadmill",
		"표지판 → PurchaseUpgrade(Treadmill)"
	)
	-- 판매 가게 / 트레일 상점 프롬프트
	check(
		trigger(sellStall:FindFirstChild("SellPrompt")) and Windows.isOpen("Pets"),
		"판매 가게 프롬프트 → 펫 창"
	)
	check(
		trigger(trailShop:FindFirstChild("TrailPrompt")) and Windows.isOpen("Trail"),
		"트레일 상점 프롬프트 → 트레일 창"
	)
	Windows.close()
	-- 알 들기: 달리기!! 배너 + 비네트 + 드롭 버튼 + 핫바 알 칸
	player:SetAttribute("CarryingEgg", "e1")
	sigOf(player, "Attr_CarryingEgg"):Fire()
	local runBanner = playerGui:FindFirstChild("RunBanner", true)
	check(runBanner and runBanner.Visible and runBanner.Text == "달리기!!", "'달리기!!' 배너")
	check(playerGui:FindFirstChild("RunVignette", true).Visible, "빨간 비네트")
	check(playerGui:FindFirstChild("EggSlot", true).Visible, "핫바 알 칸")
	local dropButton = playerGui:FindFirstChild("DropButton", true)
	check(dropButton and dropButton.Parent.Visible, "드롭 버튼 보임")
	check(click(dropButton) and lastSent("DropEgg") ~= nil, "드롭 → DropEgg 보냄")
	fire("RunAlert", { egg = { petId = "dog" }, guardName = "닭", guardSpeed = 1000, yourSpeed = 5, weightKg = 4740 })
	check(string.find(runBanner.SpeedWarning.Text, "속도가 부족", 1, true) ~= nil, "속도 부족 경고")
	fire("ChaseEnded", { biomeId = "forest", reason = "safe" })
	player:SetAttribute("CarryingEgg", "")
	sigOf(player, "Attr_CarryingEgg"):Fire()
	check(
		not runBanner.Visible and not playerGui:FindFirstChild("EggSlot", true).Visible,
		"알 내려놓으면 배너·알 칸 사라짐"
	)
	-- 러닝머신
	player:SetAttribute("OnTreadmill", true)
	sigOf(player, "Attr_OnTreadmill"):Fire()
	check(playerGui:FindFirstChild("TreadmillHint", true).Visible, "러닝머신 안내 보임")
	fakeServices.UserInputService.InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Space }, false)
	check(lastSent("TreadmillLeave") ~= nil, "점프(스페이스) → TreadmillLeave")
	holdDelays = true
	fire("TreadmillStep", { amount = 500 })
	local pop = root:FindFirstChild("StepPop")
	check(pop and pop:FindFirstChildWhichIsA("TextLabel").Text == "+500", "걸음 팝업 '+500'")
	player:SetAttribute("OnTreadmill", false)
	sigOf(player, "Attr_OnTreadmill"):Fire()
	-- 구역 배너 · 돈 팝업
	fire("ZoneEntered", { biomeId = "jungle", name = "정글", nameEn = "Jungle" })
	local zb = playerGui:FindFirstChild("ZoneBanner", true)
	check(zb and zb.Text == "Jungle 😬", "구역 배너 'Jungle 😬': " .. tostring(zb and zb.Text))
	fire("IncomeTick", { petUid = "p1", amount = 34000 })
	local moneyPop = penPetRoot:FindFirstChild("MoneyPop")
	local moneyText = moneyPop and moneyPop:FindFirstChildWhichIsA("TextLabel").Text
	holdDelays = false
	check(moneyText == "+$34K", "펫 돈 팝업 '+$34K': " .. tostring(moneyText))
	-- 슬로우 모드
	player:SetAttribute("WalkSpeed", 32)
	local hum = character:FindFirstChildOfClass("Humanoid")
	hum.WalkSpeed = 32
	check(click(playerGui:FindFirstChild("slow", true)), "슬로우 모드 누름")
	check(Hud0.isSlow() and hum.WalkSpeed == 16, "슬로우 모드: 걷기 속도 절반 (" .. hum.WalkSpeed .. ")")
	click(playerGui:FindFirstChild("slow", true))
	check(not Hud0.isSlow() and hum.WalkSpeed == 32, "슬로우 모드 끔: 원래 속도")
	-- 희귀 알 공지 (색 조각 글씨)
	local Notify = ctrl("NotifyController")
	local text = Notify.rareEggText({ biomeId = "jungle", petId = "dog", rarity = "secret" })
	check(
		text and string.find(text, "Jungle", 1, true) and string.find(text, "에그 등장!", 1, true),
		"희귀 알 공지 글자: " .. tostring(text)
	)

	print("[퓨전 머신]")
	local fusionPrompt = promptOf(machine, "FusionPrompt")
	check(fusionPrompt ~= nil and fusionPrompt.Enabled == true, "내 퓨전 머신에 프롬프트(켜짐)")
	local otherPrompt = promptOf(otherMachine, "FusionPrompt")
	check(otherPrompt ~= nil and otherPrompt.Enabled == false, "남의 퓨전 머신 프롬프트는 꺼짐")
	check(trigger(fusionPrompt), "퓨전 프롬프트 누름")
	check(Windows.isOpen("PetPicker"), "펫 고르기 창 열림")
	check(
		pickerRoot() and pickerRoot():FindFirstChild("p4", true) == nil,
		"같은 펫만: 1마리뿐인 유니콘은 숨김"
	)
	check(pickCard("p1") and pickCard("p2"), "치킨 2마리 고름")
	local confirm = pickerConfirm()
	check(confirm and confirm.Active == false, "2마리일 때 확인 버튼 꺼짐")
	check(pickCard("p3"), "3번째 치킨 고름")
	local _, clicked = pickerConfirm()
	local fuse = lastSent("FuseRequest")
	check(clicked and fuse ~= nil and #fuse.args == 3, "FuseRequest(u1,u2,u3) 보냄")
	check(not Windows.isOpen("PetPicker"), "확인 후 창 닫힘")
	fire("FusionResult", {
		consumed = { "p1", "p2", "p3" },
		pet = { uid = "p9", petId = "unicorn", size = "normal", mutations = { "silver" } },
		upgraded = true,
		bonusMutation = "silver",
		inputIncome = 30,
		income = 45,
		isNew = true,
		equipped = false,
	})
	check(true, "FusionResult 연출")

	print("[사쿠라 인큐베이터]")
	local sakuraPrompt = promptOf(incubator, "SakuraPrompt")
	check(sakuraPrompt and sakuraPrompt.ActionText == "학 바치기", "잠김: 프롬프트 '학 바치기'")
	check(trigger(sakuraPrompt), "사쿠라 프롬프트 누름")
	check(pickCard("p5"), "학 고름")
	pickerConfirm()
	local offer = lastSent("SakuraOffer")
	check(offer and offer.args[1] == "p5", "SakuraOffer(학 uid) 보냄")
	player:SetAttribute("SakuraUnlocked", true)
	sigOf(player, "Attr_SakuraUnlocked"):Fire()
	fire("SakuraResult", { kind = "unlocked", consumed = "p5", crystals = 3 })
	check(sakuraPrompt.ActionText == "꽃피우기", "열림: 프롬프트 '꽃피우기'")
	trigger(sakuraPrompt)
	local picker = pickerRoot()
	check(picker and picker:FindFirstChild("i1", true) ~= nil, "부화 중 알도 고를 수 있음")
	check(picker and picker:FindFirstChild("p8", true) == nil, "블룸 있는 펫은 숨김 (필터)")
	check(pickCard("i1"), "알 고름")
	pickerConfirm()
	local apply = lastSent("SakuraApply")
	check(apply and apply.args[1] == "i1", "SakuraApply(알 uid) 보냄")
	fire("SakuraResult", { kind = "bloom", targetUid = "i1", target = "egg", mutation = "spirit_bloom", crystals = 2 })
	check(true, "스피릿 블룸 연출")

	print("[제단]")
	local altarPrompt = promptOf(altarLight, "AltarPrompt")
	check(altarPrompt and altarPrompt.ObjectText == "천국 제단", "천국 제단 프롬프트")
	trigger(altarPrompt)
	check(Windows.isOpen("PetPicker"), "제단 고르기 창 열림")
	-- 테스트 펫 중 천국 쪽 펫이 없으면 빈 화면 안내
	local Pets = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Pets"))
	local lightPet = nil
	for _, pet in Pets.list do
		if pet.side == "light" and pet.biome == "angels_demons" then
			lightPet = pet.id
			break
		end
	end
	check(lightPet ~= nil, "천국 쪽 펫 데이터 있음: " .. tostring(lightPet))
	table.insert(snapshot.pets, { uid = "p20", petId = lightPet, size = "normal", mutations = {} })
	fire("DataUpdate", "pets", { pets = snapshot.pets })
	check(pickCard("p20"), "천국 쪽 펫 고름")
	pickerConfirm()
	check(lastSent("AltarOffer") and lastSent("AltarOffer").args[1] == "p20", "AltarOffer(uid) 보냄")
	fire("AltarUpdate", { status = "pending", side = "light", petId = lightPet })
	local status = playerGui:FindFirstChild("AltarStatus", true)
	check(status and status.Visible and string.find(status.Text, "1/2", 1, true), "상태: 기다리는 중 (1/2)")
	fire(
		"AltarUpdate",
		{ status = "paired", side = "light", petId = lightPet, partner = "친구", eggPetId = "ringlord" }
	)
	check(status and string.find(status.Text, "짝 성공", 1, true), "상태: 짝 성공!")
	fire("AltarUpdate", { status = "expired", side = "light", petId = lightPet })
	check(status and string.find(status.Text, "취소", 1, true), "상태: 취소됨")
	local label = altarDark:FindFirstChild("AltarStatus")
	check(label ~= nil, "제단 위 기다리는 제물 이름표")

	print("[비밀 통로]")
	local shrinePrompt = promptOf(shrine, "ShrinePrompt")
	check(shrinePrompt and shrinePrompt.ActionText == "비밀 합성", "비밀 통로 프롬프트")
	trigger(shrinePrompt)
	check(pickCard("p6") and pickCard("p7"), "페가수스 + 스켈레톤 말 고름")
	pickerConfirm()
	local fuse2 = lastSent("ShrineFuse")
	check(fuse2 and #fuse2.args == 2, "ShrineFuse(a, b) 보냄")
	fire("ShrineResult", { consumed = { "p6", "p7" }, resultPetId = "equinox", size = "normal", mutations = {} })
	fire("DataUpdate", "special", { shrineUsed = { equinox = true, aetheron = true } })
	check(shrinePrompt.ActionText == "이미 사용함", "다 쓰면 '이미 사용함'")
	local before = #sent
	trigger(shrinePrompt)
	check(not Windows.isOpen("PetPicker") and #sent == before, "이미 사용함이면 창 안 열림")

	print("[퀘스트]")
	local questPanel = playerGui:FindFirstChild("QuestPanel", true)
	check(questPanel ~= nil, "퀘스트 패널 있음")
	check(findButton("") ~= nil and playerGui:FindFirstChild("quest", true) ~= nil, "왼쪽 메뉴 '퀘스트' 버튼")
	click(playerGui:FindFirstChild("quest", true))
	check(questPanel.Visible == true, "메뉴 버튼으로 패널 열림")
	fire("QuestUpdate", {
		quests = {
			{
				id = "deliver_eggs",
				name = "마법의 숲 알 20개 배달하기",
				progress = 20,
				target = 20,
				done = true,
			},
			{
				id = "fuse_once",
				name = "퓨전 머신으로 동물 합성하기",
				progress = 1,
				target = 1,
				done = true,
			},
			{ id = "deliver_eternal", name = "영원 알 1개 배달하기", progress = 0, target = 1, done = false },
		},
		allDone = false,
		gateOpen = false,
	})
	local rune2 = gateModel:FindFirstChild("Rune2")
	local rune3 = gateModel:FindFirstChild("Rune3")
	check(
		rune2.Material == roblox.Enum.Material.Neon and rune3.Material ~= roblox.Enum.Material.Neon,
		"룬 2개 빛남 (끝낸 퀘스트 2개)"
	)
	player:SetAttribute("QuestsDone", true)
	sigOf(player, "Attr_QuestsDone"):Fire()
	check(rune3.Material == roblox.Enum.Material.Neon, "문 열림: 룬 전부 빛남")
	check(door.LocalTransparencyModifier > 0, "문이 내 화면에서 반투명")

	print("[무기 손 모양]")
	local tool = Instance.new("Tool")
	tool.Name = "Katana"
	tool.Parent = character
	sigOf(character, "ChildAdded"):Fire(tool)
	local visual = character:FindFirstChild("WeaponVisual")
	check(visual ~= nil and visual:FindFirstChild("Blade") ~= nil, "카타나 모델이 손에 붙음")
	local weld = visual and visual:FindFirstChild("GripWeld", true)
	check(weld and weld.Part0 == hand, "오른손(RightHand)에 용접")
	local Weapon = ctrl("WeaponController")
	Weapon.swing("Katana")
	check(true, "휘두르기")
	tool.Parent = backpack
	sigOf(character, "ChildRemoved"):Fire(tool)
	check(character:FindFirstChild("WeaponVisual") == nil, "내려놓으면 모델 지움")
	for _, kind in { "Bat", "WaterBat", "Axe", "AngelSpear", "Hammer", "CandyCane", "Scythe", "BearTrap" } do
		local t = Instance.new("Tool")
		t.Name = kind
		t.Parent = character
		sigOf(character, "ChildAdded"):Fire(t)
		check(character:FindFirstChild("WeaponVisual") ~= nil, "무기 모양 " .. kind)
		t.Parent = backpack
		sigOf(character, "ChildRemoved"):Fire(t)
	end

	print("[기타 이벤트]")
	fire("Notify", { kind = "success", text = "테스트 성공" })
	fire("Announce", { kind = "rareEgg", text = "숲에 비밀 알!", rarity = "secret" })
	fire("RunAlert", { egg = { petId = "dog" }, guardName = "닭", guardSpeed = 10, yourSpeed = 5 })
	fire("Caught", { cause = "guard", by = "닭", eggOutcome = "ReturnToNest", ragdollSeconds = 2 })
	fire("EggDelivered", { petId = "dog", slot = 1, required = 5 })
	fire("HatchResult", {
		pet = { uid = "p30", petId = "unicorn", size = "giant", mutations = { "rainbow" } },
		isNew = true,
		income = 1e9,
		equipped = true,
	})
	fire("EggGranted", { record = { petId = "ringlord" }, queued = false, source = "altar" })
	fire("PetsSold", { pets = { {} }, money = 100 })
	check(true, "이벤트 처리")

	local n = 0
	for _ in playerGui:GetDescendants() do
		n += 1
	end
	print("  gui instances:", n)
	local names = {}
	for _, s in sent do
		table.insert(names, s.name)
	end
	print("  sent:", table.concat(names, ","))

	------------------------------------------------------------------
	-- 반응형 HUD: 왼쪽 메뉴 · 핫바 자리 (화면 영역 좌표 = 위 인셋 58px 아래부터 0)
	------------------------------------------------------------------
	print("[반응형 HUD (폰 750x381 · 844x390 · PC 1428x750)]")
	local Layout = uiModule("Layout")
	local Hud = ctrl("HudController")
	local UIS = fakeServices.UserInputService
	local INSET = 58
	local hudLayer = screen:FindFirstChild("Hud")
	local menu = hudLayer:FindFirstChild("LeftMenu")
	local bar = hudLayer:FindFirstChild("Hotbar")
	local questPanelNode = playerGui:FindFirstChild("QuestPanel", true)

	-- 핫바 칸 채우기 (도구를 가방에)
	local function setTools(kinds)
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then
				child.Parent = nil
				sigOf(backpack, "ChildRemoved"):Fire(child)
			end
		end
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				child.Parent = nil
				sigOf(character, "ChildRemoved"):Fire(child)
			end
		end
		for _, kind in kinds do
			local t = Instance.new("Tool")
			t.Name = kind
			t.Parent = backpack
			sigOf(backpack, "ChildAdded"):Fire(t)
		end
	end

	local function menuRects()
		local s = menu:FindFirstChild("MenuScale").Scale
		local list = {}
		for _, b in menu:GetChildren() do
			if b:IsA("TextButton") and b.Visible then
				-- 2판: 버튼 AnchorPoint (0, 0) — Position 이 왼쪽 위
				local x = menu.Position.X.Offset + b.Position.X.Offset * s
				local y = menu.Position.Y.Offset + b.Position.Y.Offset * s
				table.insert(list, {
					name = b.Name,
					order = b.LayoutOrder,
					x = x,
					y = y,
					w = b.Size.X.Offset * s,
					h = b.Size.Y.Offset * s,
					badgeTop = y + 6 * s - 15 * s,
				})
			end
		end
		table.sort(list, function(a, b)
			return a.order < b.order
		end)
		return list
	end
	local function hotbarRect(area)
		local s = bar:FindFirstChild("HotbarScale").Scale
		local w = bar.Size.X.Offset * s
		local h = bar.Size.Y.Offset * s
		local ax = bar.AnchorPoint.X
		return {
			x = area.X * bar.Position.X.Scale + bar.Position.X.Offset - w * ax,
			y = area.Y + bar.Position.Y.Offset - h,
			w = w,
			h = h,
			slot = Layout.SLOT * s,
		}
	end
	-- 속도·돈 묶음 자리 (PC: 왼쪽 아래 330x150, 터치: 위 한 줄 520x48 — HudController 와 같은 숫자)
	local function statsRect(area, touch)
		local k = Ui.scale()
		if touch then
			return { x = 10, y = 4, w = 520 * k, h = 48 * k }
		end
		return { x = 10, y = area.Y - 6 - 150 * k, w = 330 * k, h = 150 * k }
	end
	local function fmt(r)
		return string.format("(%d,%d %dx%d)", math.floor(r.x + 0.5), math.floor(r.y + 0.5), r.w, r.h)
	end

	local cases = {
		{ w = 750, h = 381, touch = true, tools = { "Bat", "BearTrap", "Katana" } },
		-- 무기 전부(9칸): 칸이 많아도 조이스틱·점프 버튼을 피하는지
		{
			w = 750,
			h = 381,
			touch = true,
			tools = { "Bat", "BearTrap", "WaterBat", "Katana", "Axe", "AngelSpear", "Hammer", "CandyCane", "Scythe" },
		},
		{ w = 844, h = 390, touch = true, tools = { "Bat", "BearTrap", "Katana" } },
		{ w = 1428, h = 750, touch = false, tools = { "Bat", "BearTrap", "Katana" } },
		{ w = 1428, h = 750, touch = true, tools = { "Bat", "BearTrap", "Katana" } },
	}
	for _, case in cases do
		UIS.TouchEnabled = case.touch
		UIS.MouseEnabled = not case.touch
		UIS.KeyboardEnabled = not case.touch
		cam.ViewportSize = roblox.Vector2.new(case.w, case.h)
		setTools(case.tools)
		Ui.relayout()
		local area = Ui.area()
		local tag = string.format("%dx%d %s %d칸", case.w, case.h, if case.touch then "터치" else "PC", #case.tools)
		check(area.X == case.w and area.Y == case.h - INSET, tag .. " 화면 영역 " .. area.X .. "x" .. area.Y)

		local rects = menuRects()
		local plan = Hud.menuPlan()
		check(#rects == 6, tag .. " 메뉴 버튼 6개")
		local joy = Layout.joystickZone(area)
		local inside, big, clearJoy, badgeOk = true, true, true, true
		local parts = {}
		for _, r in rects do
			inside = inside and r.y >= 0 and r.y + r.h <= area.Y and r.x >= 0
			big = big and r.w >= 44 and r.h >= 44
			if case.touch and Layout.overlaps(r, joy) then
				clearJoy = false
			end
			badgeOk = badgeOk and r.badgeTop >= 0
			table.insert(parts, r.name .. fmt(r))
		end
		print("    메뉴 " .. tag .. ": " .. plan.cols .. "열 " .. plan.size .. "px  " .. table.concat(parts, " "))
		check(inside, tag .. " 메뉴 버튼 전부 화면 안 (0 ≤ y, y+h ≤ " .. area.Y .. ")")
		check(big, tag .. " 메뉴 버튼 44px 이상 (" .. plan.size .. "px)")
		check(badgeOk, tag .. " 배지도 위로 안 잘림")
		if case.touch then
			check(clearJoy, tag .. " 메뉴가 왼쪽 아래 조이스틱과 안 겹침")
		end
		-- 겹치는 버튼 없음
		local overlap = false
		for i = 1, #rects do
			for j = i + 1, #rects do
				if Layout.overlaps(rects[i], rects[j]) then
					overlap = true
				end
			end
		end
		check(not overlap, tag .. " 메뉴 버튼끼리 안 겹침")
		-- 속도·돈 묶음(PC 왼쪽 아래 / 터치 위 한 줄)과 안 겹침
		local st = statsRect(area, case.touch)
		local hitStats = false
		for _, r in rects do
			if Layout.overlaps(r, st) then
				hitStats = true
			end
		end
		check(not hitStats, tag .. " 메뉴가 속도·돈 묶음과 안 겹침 " .. fmt(st))

		local hb = hotbarRect(area)
		print("    핫바 " .. tag .. ": " .. fmt(hb) .. string.format(" 칸 %.1fpx", hb.slot))
		check(
			#case.tools == 0 or (bar.Size.X.Offset == #case.tools * Layout.SLOT + (#case.tools - 1) * Layout.SLOT_GAP),
			tag .. " 핫바 너비 = 칸 수"
		)
		check(hb.x >= 0 and hb.y >= 0 and hb.x + hb.w <= area.X and hb.y + hb.h <= area.Y, tag .. " 핫바 화면 안")
		check(hb.slot >= 44, string.format("%s 핫바 칸 %.1fpx (44 이상)", tag, hb.slot))
		if case.touch then
			local jumpCorner = { x = area.X - 100, y = area.Y - 100, w = 100, h = 100 }
			check(
				not Layout.overlaps(hb, jumpCorner),
				tag .. " 핫바가 오른쪽 아래 점프 버튼 자리(100x100)와 안 겹침"
			)
			check(
				not Layout.overlaps(hb, Layout.jumpZone(area)),
				tag .. " 핫바가 점프 버튼 규칙 자리와 안 겹침"
			)
			check(not Layout.overlaps(hb, joy), tag .. " 핫바가 조이스틱과 안 겹침")
		else
			check(math.abs(hb.x + hb.w / 2 - area.X / 2) < 1, tag .. " PC 핫바는 원작처럼 아래 가운데")
			check(not Layout.overlaps(hb, statsRect(area, false)), tag .. " 핫바가 속도·돈과 안 겹침")
		end
		for _, r in rects do
			check(not Layout.overlaps(r, hb), tag .. " 메뉴 " .. r.name .. " 와 핫바 안 겹침")
		end
		check(
			questPanelNode and questPanelNode.Position.X.Offset >= Hud.menuRight(),
			tag .. " 퀘스트 패널이 메뉴 오른쪽에서 시작"
		)
	end
	-- 원래대로 (폰 가로)
	UIS.TouchEnabled, UIS.MouseEnabled, UIS.KeyboardEnabled = true, false, false
	cam.ViewportSize = roblox.Vector2.new(844, 390)
	Ui.relayout()
end

local ok, err = pcall(body)
if not ok then
	print("ERROR: " .. tostring(err))
	process.exit(1)
end
if failures > 0 then
	print(string.format("SMOKE CLIENT: %d 실패", failures))
	process.exit(1)
end
print("SMOKE CLIENT OK")
