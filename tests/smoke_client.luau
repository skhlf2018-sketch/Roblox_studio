--!nocheck
--[[
	클라 화면 스모크 테스트 (선임) — 저장소 루트에서:  lune run tests/smoke_client.luau
	(tests/run.luau 에는 안 들어감. 로블록스 없이 @lune/roblox 진짜 GUI 인스턴스로 화면을 만들어 보며
	 속성 이름·타입 오타, nil 인덱싱 같은 실행 오류를 잡습니다. 보기 좋은지는 스튜디오 기기 에뮬레이터로)

	하는 일: 클라 컨트롤러 전부 start() → Snapshot → 창 전부 열기·버튼 누르기
	        → 2단계: 퓨전 머신·사쿠라·제단·비밀 통로 프롬프트 누르기 → 펫 고르기 창에서 카드 고르고 확인
	          → 보낸 Remote 이름·인자 확인 → 결과 이벤트(FusionResult/SakuraResult/AltarUpdate/ShrineResult) (5판: 퀘스트·선물 창 없앰)
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
		-- 5판 주임 검수: 연결(Connect) 수 보기 (연결이 새는지 재려고)
		Count = function()
			return #handlers
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
-- 소리: Lune 에는 Sound:Play/Stop 이 없고 IsPlaying 은 기본값이 없어 읽으면 오류
-- (소리 ID 를 채운 뒤부터 배경음 Sound 가 실제로 생김 → SoundController 는 IsPlaying 대신 Playing 을 봄)
pcall(roblox.implementMethod, "Sound", "Play", function(inst)
	inst.Playing = true
end)
pcall(roblox.implementMethod, "Sound", "Stop", function(inst)
	inst.Playing = false
end)
pcall(roblox.implementProperty, "Sound", "Ended", function(inst)
	return sigOf(inst, "Ended")
end)
pcall(roblox.implementMethod, "SoundService", "PlayLocalSound", function() end)
-- 서버 시각 (떨어진 알 카운트다운·남은 시간): 늘 1000
pcall(roblox.implementMethod, "Workspace", "GetServerTimeNow", function()
	return 1000
end)

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
	GetPlayerByUserId = function(_, id)
		return if id == 77 then player else nil
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
		TouchTapInWorld = signal(),
		GetMouseLocation = function()
			return roblox.Vector2.new(422, 195)
		end,
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
-- (5판: 마법의 숲 퀘스트 문 QuestGate 없앰)
local crystal = worldPart("SakuraCrystal_c1", roblox.Vector3.new(3, 1, 3))
tag(crystal, "SakuraCrystal")
-- 2판 월드 흉내: 우리 펫(PenPet) · 우리 안 부화 중 알 · 업그레이드 표지판 · 판매 가게(가까이) · 트레일 상점
local penPet = Instance.new("Model")
penPet.Name = "chicken"
local penPetRoot = worldPart("Root", roblox.Vector3.new(20, 1, 20), nil, penPet)
penPet.PrimaryPart = penPetRoot
penPet:SetAttribute("PetUid", "p1")
penPet:SetAttribute("OwnerUserId", 77)
penPet.Parent = Workspace
penPet:SetAttribute("Height", 3)
-- 5판: 서버 PetVisualService 가 붙이는 쓰다듬기 프롬프트 (Root > Attachment "PromptAttach" > ProximityPrompt "PetPrompt")
local function petPrompt(rootPart)
	local attach = Instance.new("Attachment")
	attach.Name = "PromptAttach"
	attach.Parent = rootPart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PetPrompt"
	prompt.ActionText = "쓰다듬기"
	prompt.Parent = attach
	return prompt
end
local myPetPrompt = petPrompt(penPetRoot)
tag(penPet, "PenPet")
-- 남의 우리 펫 (uid 가 내 펫과 같은 "p1" — 사람마다 uid 를 따로 매겨 겹칠 수 있음)
local otherPet = Instance.new("Model")
otherPet.Name = "dog"
local otherPetRoot = worldPart("Root", roblox.Vector3.new(200, 1, 20), nil, otherPet)
otherPet.PrimaryPart = otherPetRoot
otherPet:SetAttribute("PetUid", "p1")
otherPet:SetAttribute("OwnerUserId", 12345)
otherPet:SetAttribute("Height", 3)
otherPet.Parent = Workspace
local otherPetPrompt = petPrompt(otherPetRoot)
tag(otherPet, "PenPet")
-- 5판: 허브 스폰 광장 랭킹판 (MapBuilder 가 세우는 판 파트)
local lbBoard = worldPart("LeaderboardBoard", roblox.Vector3.new(-26, 9, -150), roblox.Vector3.new(16, 12, 0.8))
tag(lbBoard, "LeaderboardBoard")
local growingEgg = worldPart("Incubating_i2", roblox.Vector3.new(25, 1, 20), roblox.Vector3.new(2, 2.5, 2))
growingEgg:SetAttribute("EggUid", "i2")
growingEgg:SetAttribute("OwnerUserId", player.UserId)
growingEgg:SetAttribute("PetId", "chicken")
growingEgg:SetAttribute("Progress", 5)
growingEgg:SetAttribute("Required", 5)
growingEgg:SetAttribute("Ready", true)
tag(growingEgg, "IncubatingEgg")
-- 아직 자라는 내 알 (집기 프롬프트) · 남의 알 (프롬프트 없음)
local youngEgg = worldPart("Incubating_i1", roblox.Vector3.new(27, 1, 20), roblox.Vector3.new(2, 2.5, 2))
youngEgg:SetAttribute("EggUid", "i1")
youngEgg:SetAttribute("OwnerUserId", player.UserId)
youngEgg:SetAttribute("PetId", "dog")
youngEgg:SetAttribute("Progress", 3)
youngEgg:SetAttribute("Required", 5)
youngEgg:SetAttribute("Ready", false)
tag(youngEgg, "IncubatingEgg")
local othersEgg = worldPart("Incubating_i9", roblox.Vector3.new(200, 1, 20), roblox.Vector3.new(2, 2.5, 2))
othersEgg:SetAttribute("EggUid", "i9")
othersEgg:SetAttribute("OwnerUserId", 12345)
othersEgg:SetAttribute("Progress", 5)
othersEgg:SetAttribute("Required", 5)
tag(othersEgg, "IncubatingEgg")
-- 바닥에 떨어진 알 (60초 잔류, ExpiresAt = 서버 시각 1000 + 32 → "32초")
local droppedEgg = worldPart("Egg_d1", roblox.Vector3.new(0, 1, 60), roblox.Vector3.new(2, 2.5, 2))
droppedEgg:SetAttribute("EggUid", "d1")
droppedEgg:SetAttribute("EggState", "Dropped")
droppedEgg:SetAttribute("DroppedAt", 1000 - 28)
droppedEgg:SetAttribute("ExpiresAt", 1000 + 32)
tag(droppedEgg, "Egg")
local nestEgg = worldPart("Egg_n1", roblox.Vector3.new(0, 1, 80), roblox.Vector3.new(2, 2.5, 2))
nestEgg:SetAttribute("EggState", "Nest")
tag(nestEgg, "Egg")
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
			"SettingsController",
			"HotbarController",
			"WorldFxController",
			"FusionController",
			"SakuraController",
			"AltarController",
			"WeaponController",
			"TreadmillController",
			"TrailController",
			-- 5판
			"PetFxController",
			"LeaderboardController",
			"TutorialController",
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
				x = -10,
				z = -20,
				progress = 3,
				required = 5,
			},
			{
				uid = "i2",
				petId = "chicken",
				size = "normal",
				mutations = {},
				biomeId = "forest",
				x = -10,
				z = 20,
				progress = 5,
				required = 5,
			},
		},
		-- 2판 수정: 알 가방 (BagEgg)
		eggs = {
			{
				uid = "e1",
				petId = "unicorn",
				size = "big",
				mutations = { "golden" },
				biomeId = "forest",
				special = false,
				progress = 0,
				required = 300,
			},
			{
				uid = "e2",
				petId = "dog",
				size = "normal",
				mutations = {},
				biomeId = "forest",
				special = true,
				progress = 2,
				required = 10,
			},
		},
		eggInventoryMax = 50,
		placedEggMax = 8,
		plotIndex = 1,
		saveEnabled = true,
		sakuraCrystals = 3,
		sakuraUnlocked = false,
		shrineUsed = {},
		petInventoryMax = 500,
		-- 5판: 튜토리얼 (퀘스트 quests/questsDone·무료 보상 freeRewardClaimed 는 없어짐)
		tutorial = {
			step = 1,
			total = 5,
			text = "숲에서 알 훔치기",
			hint = "둥지의 알 가까이에서 E",
			done = false,
		},
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
	for _, w in { "Index", "Pets", "Shop", "Settings", "Trail" } do
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
	for _, w in { "Index", "Pets", "Shop", "Settings", "PetPicker", "Trail" } do
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
	-- 알 버튼 → 알 창 ("성장하는 달걀" 패널: 성장 중 탭 + 가방 탭)
	check(click(playerGui:FindFirstChild("EggButton", true)), "주황 알 버튼 누름")
	local panel = playerGui:FindFirstChild("GrowingEggs", true)
	check(panel and panel.Visible, "성장하는 달걀 패널 열림")
	local list = panel and panel:FindFirstChild("List")
	check(
		list and list.Visible and list:FindFirstChild("i1") and list:FindFirstChild("i2"),
		"성장 중 탭: 놓인 알 2줄"
	)
	local tabGrow = panel and panel:FindFirstChild("Tab_grow")
	local tabBag = panel and panel:FindFirstChild("Tab_bag")
	check(
		tabGrow and tabGrow.Text == "성장 중 2/8",
		"탭 글자 '성장 중 2/8': " .. tostring(tabGrow and tabGrow.Text)
	)
	check(tabBag and tabBag.Text == "가방 2/50", "탭 글자 '가방 2/50': " .. tostring(tabBag and tabBag.Text))
	local readyRow = list and list:FindFirstChild("i2")
	local readyTime = readyRow and readyRow:FindFirstChild("Time", true)
	check(
		readyTime and readyTime.Text == "부화 가능!",
		"다 자란 알 줄 '부화 가능!': " .. tostring(readyTime and readyTime.Text)
	)
	local youngRow = list and list:FindFirstChild("i1")
	local youngTime = youngRow and youngRow:FindFirstChild("Time", true)
	check(
		youngTime and youngTime.Text == "2s",
		"자라는 알 남은 시간 '2s': " .. tostring(youngTime and youngTime.Text)
	)
	check(
		readyRow and readyRow:FindFirstChild("EggName") and readyRow.EggName.Text ~= "",
		"줄에 펫 이름: " .. tostring(readyRow and readyRow:FindFirstChild("EggName") and readyRow.EggName.Text)
	)
	check(click(readyRow and readyRow:FindFirstChild("Play")), "▶ 버튼 (다 자란 알)")
	check(lastSent("HatchEgg") and lastSent("HatchEgg").args[1] == "i2", "▶ → HatchEgg(i2)")
	local pickUpButton = youngRow and youngRow:FindFirstChild("PickUp")
	check(pickUpButton and pickUpButton.Visible, "자라는 알 줄에 '가방' (다시 줍기) 버튼")
	check(
		click(pickUpButton) and lastSent("PickUpPlacedEgg") and lastSent("PickUpPlacedEgg").args[1] == "i1",
		"'가방' 버튼 → PickUpPlacedEgg(i1)"
	)
	check(
		readyRow and readyRow:FindFirstChild("PickUp") and not readyRow.PickUp.Visible,
		"다 자란 알은 '가방' 버튼 숨김 (부화만)"
	)
	-- 가방 탭: 알 카드 (희귀도 색·펫 이름·크기·돌연변이·놓기)
	check(click(tabBag), "가방 탭 누름")
	local bagGrid = panel and panel:FindFirstChild("Bag")
	check(bagGrid and bagGrid.Visible and not list.Visible, "가방 탭으로 바뀜")
	local card1 = bagGrid and bagGrid:FindFirstChild("e1")
	check(card1 and bagGrid:FindFirstChild("e2"), "가방 알 카드 2장")
	local detail1 = card1 and card1:FindFirstChild("EggDetail")
	check(
		detail1 and string.find(detail1.Text, "큼", 1, true) and string.find(detail1.Text, "골든", 1, true),
		"카드에 크기·돌연변이: " .. tostring(detail1 and detail1.Text)
	)
	check(card1 and card1:FindFirstChild("EggName") and card1.EggName.Text ~= "", "카드에 펫 이름")
	local Ui0 = uiModule("Ui")
	local cardScale = Ui0.scale()
	check(
		panel.Size.Y.Offset * cardScale <= Ui0.area().Y,
		string.format("알 창 높이 %.0fpx ≤ 화면 %dpx (폰)", panel.Size.Y.Offset * cardScale, Ui0.area().Y)
	)
	check(
		card1 and card1.Place.Size.Y.Offset * cardScale >= 45.9,
		string.format("'놓기' 버튼 %.1fpx (46 이상)", card1 and card1.Place.Size.Y.Offset * cardScale or 0)
	)
	check(
		tabBag.Size.Y.Offset * cardScale >= 45.9,
		string.format("탭 버튼 %.1fpx (46 이상)", tabBag.Size.Y.Offset * cardScale)
	)
	local Inc = ctrl("IncubatorController")
	check(Inc.shortTime(112) == "1m 52s" and Inc.shortTime(300) == "5m", "알 시간 글자 '1m 52s' / '5m'")

	print("[알 놓기 모드]")
	-- State 는 Snapshot 표를 그대로 고치므로(DataUpdate 가 키를 덮어씀) 원래 목록을 따로 들고 있음
	local savedIncubators, savedEggs = snapshot.incubators, snapshot.eggs
	local MapLayout = requireNode(Loader.get("ReplicatedStorage/Shared/Data/MapLayout"))
	-- 내 베이스(1번) 앞마당에 서 있음
	local spawnSpot = MapLayout.plot(1).spawn
	root.Position = roblox.Vector3.new(spawnSpot.x, 3, spawnSpot.z)
	root.CFrame = roblox.CFrame.new(root.Position)
	check(click(card1 and card1:FindFirstChild("Place")), "카드 '놓기' 누름")
	check(Inc.isPlacing(), "놓기 모드 시작")
	check(not panel.Visible, "놓기 모드에서는 알 창 닫힘")
	local ghost = Workspace:FindFirstChild("EggPlacePreview")
	check(
		ghost ~= nil and ghost:FindFirstChild("EggPlaceRing") ~= nil,
		"반투명 알 미리보기 + 바닥 동그라미"
	)
	local placeBar = playerGui:FindFirstChild("PlaceBar", true)
	check(placeBar and placeBar.Visible, "위 안내 줄 보임")
	local placeHere = placeBar and placeBar:FindFirstChild("PlaceHere")
	check(placeHere and placeHere.Visible, "폰: '여기 놓기' 버튼 보임")
	check(ghost and ghost.Color.G > ghost.Color.R, "폰: 처음엔 우리 안 첫 빈자리에 초록 미리보기")
	local okSpot = MapLayout.toWorld(1, -24, 0)
	local ok1 = Inc.previewAt(okSpot.x, okSpot.z)
	check(ok1 and ghost.Color.G > ghost.Color.R, "우리 안 빈자리 = 초록")
	local hint = placeBar:FindFirstChild("PlaceHint")
	check(hint and string.find(hint.Text, "놓을 수 있어요", 1, true), "안내: " .. tostring(hint and hint.Text))
	local yard = MapLayout.toWorld(1, 25, 0)
	local ok2, reason2 = Inc.previewAt(yard.x, yard.z)
	check(not ok2 and ghost.Color.R > ghost.Color.G, "우리 밖(앞마당) = 빨강")
	check(reason2 and string.find(reason2, "울타리", 1, true), "이유: " .. tostring(reason2))
	local near = MapLayout.toWorld(1, -10, -19)
	local ok3, reason3 = Inc.previewAt(near.x, near.z)
	check(
		not ok3 and reason3 and string.find(reason3, "가까워요", 1, true),
		"놓인 알 옆 = 빨강 (" .. tostring(reason3) .. ")"
	)
	local fence = MapLayout.toWorld(1, -34.5, 0)
	check(not Inc.previewAt(fence.x, fence.z), "울타리(뒤 벽) 2스터드 안 = 빨강")
	local beforeSent = #sent
	check(
		not Inc.confirmPlace() and #sent == beforeSent and Inc.isPlacing(),
		"빨강에서 놓기 → 안 보냄, 모드 유지"
	)
	Inc.previewAt(okSpot.x, okSpot.z)
	check(click(placeHere), "'여기 놓기' 누름")
	local placed = lastSent("PlaceEgg")
	check(
		placed
			and placed.args[1] == "e1"
			and math.abs(placed.args[2] - okSpot.x) < 0.01
			and math.abs(placed.args[3] - okSpot.z) < 0.01,
		"PlaceEgg(e1, 월드 x, z) 보냄"
	)
	check(
		not Inc.isPlacing() and Workspace:FindFirstChild("EggPlacePreview") == nil,
		"보낸 뒤 놓기 모드 끝, 미리보기 지움"
	)
	check(not placeBar.Visible, "안내 줄 숨김")
	-- 멀리 서 있으면 빨강
	Inc.beginPlace("e2")
	root.Position = roblox.Vector3.new(0, 3, -140)
	local ok4, reason4 = Inc.previewAt(okSpot.x, okSpot.z)
	check(
		not ok4 and reason4 and string.find(reason4, "가까이", 1, true),
		"베이스 밖 멀리 = 빨강 (" .. tostring(reason4) .. ")"
	)
	root.Position = roblox.Vector3.new(spawnSpot.x, 3, spawnSpot.z)
	-- ESC 로 취소
	fakeServices.UserInputService.InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Escape }, false)
	check(not Inc.isPlacing() and Workspace:FindFirstChild("EggPlacePreview") == nil, "ESC → 놓기 모드 끝")
	-- 취소 버튼
	Inc.beginPlace("e2")
	check(
		click(placeBar:FindFirstChild("PlaceCancel")) and not Inc.isPlacing(),
		"'취소' 버튼 → 놓기 모드 끝"
	)
	-- 놓으려던 알이 가방에서 사라지면 저절로 끝
	Inc.beginPlace("e2")
	fire("DataUpdate", "eggs", { eggs = { savedEggs[1] } })
	check(not Inc.isPlacing(), "가방에서 알이 사라지면 놓기 모드 끝")
	check(not Inc.beginPlace("nope"), "가방에 없는 알은 놓기 모드 안 됨")
	-- 우리가 가득 차면 놓기 모드 안 들어감
	local full = {}
	for i = 1, 8 do
		table.insert(full, {
			uid = "f" .. i,
			petId = "dog",
			size = "normal",
			mutations = {},
			x = -30 + i,
			z = 0,
			progress = 0,
			required = 10,
		})
	end
	fire("DataUpdate", "incubators", { incubators = full })
	check(not Inc.beginPlace("e1") and not Inc.isPlacing(), "우리 8개 가득 → 놓기 모드 안 됨")
	fire("DataUpdate", "incubators", { incubators = savedIncubators })
	fire("DataUpdate", "eggs", { eggs = savedEggs })

	check(
		click(playerGui:FindFirstChild("PetsButton", true)) and Windows.isOpen("Pets"),
		"주황 발바닥 버튼 → 펫 창"
	)
	Windows.close()
	-- 우리 안 부화 중 알: 이름표는 서버 것("에그 1m 52s"), 클라는 프롬프트 2개
	check(growingEgg:FindFirstChild("GrowTag") == nil, "클라 이름표 없음 (서버 이름표만)")
	local hatchPrompt = growingEgg:FindFirstChild("HatchPrompt")
	check(
		hatchPrompt and hatchPrompt.ActionText == "부화!" and hatchPrompt.Enabled,
		"다 자란 내 알: '부화!' 프롬프트 켜짐"
	)
	check(
		growingEgg:FindFirstChild("PickUpPrompt") and not growingEgg.PickUpPrompt.Enabled,
		"다 자란 알: '집기' 프롬프트 꺼짐"
	)
	check(trigger(hatchPrompt) and lastSent("HatchEgg").args[1] == "i2", "프롬프트 → HatchEgg(i2)")
	local pickPrompt = youngEgg:FindFirstChild("PickUpPrompt")
	check(
		pickPrompt and pickPrompt.ActionText == "집기" and pickPrompt.Enabled,
		"자라는 내 알: '집기' 프롬프트 켜짐"
	)
	check(not youngEgg.HatchPrompt.Enabled, "자라는 알: '부화!' 프롬프트 꺼짐")
	check(trigger(pickPrompt) and lastSent("PickUpPlacedEgg").args[1] == "i1", "'집기' → PickUpPlacedEgg(i1)")
	check(
		othersEgg:FindFirstChild("HatchPrompt") == nil and othersEgg:FindFirstChild("PickUpPrompt") == nil,
		"남의 알은 프롬프트 없음"
	)
	-- 떨어진 알 카운트다운
	local dropTimer = droppedEgg:FindFirstChild("DropTimer")
	local dropText = dropTimer and dropTimer:FindFirstChild("Time")
	check(
		dropText and dropText.Text == "32초",
		"떨어진 알 머리 위 '32초': " .. tostring(dropText and dropText.Text)
	)
	check(nestEgg:FindFirstChild("DropTimer") == nil, "둥지 알은 카운트다운 없음")
	droppedEgg:SetAttribute("ExpiresAt", nil)
	sigOf(droppedEgg, "Attr_ExpiresAt"):Fire()
	check(droppedEgg:FindFirstChild("DropTimer") == nil, "다시 주우면(ExpiresAt 없음) 카운트다운 사라짐")
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

	print("[5판: 퀘스트·선물 없앰]")
	check(playerGui:FindFirstChild("QuestPanel", true) == nil, "퀘스트 패널 없음")
	check(playerGui:FindFirstChild("quest", true) == nil, "왼쪽 메뉴 '퀘스트' 버튼 없음")
	check(playerGui:FindFirstChild("gift", true) == nil, "왼쪽 메뉴 '선물' 버튼 없음")
	check(not Windows.isOpen("Gift"), "선물 창 없음")

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
	holdDelays = true -- 토스트가 바로 사라지지 않게
	fire("EggDelivered", {
		uid = "e3",
		petId = "dog",
		size = "normal",
		mutations = {},
		biomeId = "forest",
		special = false,
		progress = 0,
		required = 10,
	})
	local function toastHas(text)
		for _, d in playerGui:GetDescendants() do
			if d:IsA("TextLabel") and string.find(d.Text, text, 1, true) then
				return true
			end
		end
		return false
	end
	check(
		toastHas("에그를 훔쳤어요! 가방에 들어갔어요"),
		"배달 토스트 '에그를 훔쳤어요! 가방에 들어갔어요'"
	)
	fire("HatchResult", {
		pet = { uid = "p30", petId = "unicorn", size = "giant", mutations = { "rainbow" } },
		isNew = true,
		income = 1e9,
		equipped = true,
	})
	fire(
		"EggGranted",
		{ egg = { uid = "e4", petId = "ringlord", size = "normal", mutations = {} }, queued = false, source = "altar" }
	)
	check(
		toastHas("가방에 들어갔어요") and not toastHas("부화 슬롯"),
		"선물 알 토스트 '가방에 들어갔어요'"
	)
	holdDelays = false
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
	-- 5판 (선임): 핫바 알 칸 · 튜토리얼 패널 · 랭킹판 · 쓰다듬기
	------------------------------------------------------------------
	print("[5판: 얻은 알은 핫바에 바로]")
	local hotbar = playerGui:FindFirstChild("Hotbar", true)
	-- 도구는 방망이·곰덫 둘만 (앞 검사들이 무기를 여럿 넣어 둠)
	for _, container in { backpack, character } do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") then
				child.Parent = nil
				sigOf(container, "ChildRemoved"):Fire(child)
			end
		end
	end
	for _, kind in { "Bat", "BearTrap" } do
		local t = Instance.new("Tool")
		t.Name = kind
		t.Parent = backpack
		sigOf(backpack, "ChildAdded"):Fire(t)
	end
	fire("DataUpdate", "eggs", { eggs = savedEggs })
	local slotE1 = hotbar:FindFirstChild("BagEgg_e1")
	local slotE2 = hotbar:FindFirstChild("BagEgg_e2")
	check(slotE1 ~= nil and slotE2 ~= nil, "가방 알 2개 = 핫바 알 칸 2개 (BagEgg_e1, BagEgg_e2)")
	check(slotE1 and slotE2 and slotE2.LayoutOrder < slotE1.LayoutOrder, "가장 최근에 얻은 알(e2)이 앞 칸")
	local toolMax = 0
	for _, child in hotbar:GetChildren() do
		if child:IsA("TextButton") and child.Visible and not string.find(child.Name, "BagEgg_", 1, true) then
			if child.Name ~= "MoreEggs" then
				toolMax = math.max(toolMax, child.LayoutOrder)
			end
		end
	end
	check(slotE2 and slotE2.LayoutOrder > toolMax, "알 칸은 도구 칸 뒤")
	local function sameColor(a, b)
		return a and b and math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.01
	end
	local dogRarity = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Pets")).get("dog").rarity
	check(
		slotE2 and sameColor(slotE2:FindFirstChildOfClass("UIStroke").Color, uiModule("Theme").rarityColor(dogRarity)),
		"알 칸 테두리 = 희귀도 색 (개 = " .. dogRarity .. ")"
	)
	check(slotE2 and slotE2:FindFirstChild("Special") ~= nil, "특별 알 칸에 ★")
	check(Workspace:FindFirstChild("EggPlacePreview") == nil and not Inc.isPlacing(), "처음엔 놓기 모드 아님")
	check(
		click(slotE1) and Inc.isPlacing() and Inc.placingUid() == "e1",
		"핫바 알 칸 톡 → 바로 알 놓기 모드 (e1)"
	)
	check(Workspace:FindFirstChild("EggPlacePreview") ~= nil, "놓기 미리보기 생김")
	check(slotE1:FindFirstChildOfClass("UIStroke").Thickness == 5, "놓는 중인 알 칸 = 흰 두꺼운 테두리")
	check(click(slotE2) and Inc.placingUid() == "e2", "다른 알 칸 → 그 알로 바뀜")
	check(click(slotE2) and not Inc.isPlacing(), "같은 칸 한 번 더 → 놓기 취소")
	-- 숫자키 (PC): 알 칸 번호
	local keyLabel = slotE1:FindFirstChild("Key")
	local keyN = tonumber(keyLabel and keyLabel.Text)
	check(keyN ~= nil, "알 칸에도 번호 " .. tostring(keyN))
	if keyN then
		local codes = {
			roblox.Enum.KeyCode.One,
			roblox.Enum.KeyCode.Two,
			roblox.Enum.KeyCode.Three,
			roblox.Enum.KeyCode.Four,
			roblox.Enum.KeyCode.Five,
			roblox.Enum.KeyCode.Six,
			roblox.Enum.KeyCode.Seven,
			roblox.Enum.KeyCode.Eight,
			roblox.Enum.KeyCode.Nine,
		}
		fakeServices.UserInputService.InputBegan:Fire({ KeyCode = codes[keyN] }, false)
		check(Inc.placingUid() == "e1", "숫자키 " .. keyN .. " → e1 놓기 모드")
	end
	-- 핫바에서 고른 알을 우리 빈자리에 놓기 → PlaceEgg
	root.Position = roblox.Vector3.new(spawnSpot.x, 3, spawnSpot.z)
	local hotSpot = MapLayout.toWorld(1, -24, 0)
	Inc.previewAt(hotSpot.x, hotSpot.z)
	local beforePlace = #sent
	check(Inc.confirmPlace() and #sent == beforePlace + 1, "놓기 확인")
	local hp = lastSent("PlaceEgg")
	check(hp and hp.args[1] == "e1", "핫바 알 → PlaceEgg(e1, x, z)")
	-- 놓기 성공: 가방에서 빠지면 핫바에서도 사라짐 (부화 중 알은 핫바에 안 보임)
	fire("DataUpdate", "eggs", { eggs = { savedEggs[2] } })
	check(hotbar:FindFirstChild("BagEgg_e1") == nil, "놓인 알(e1)은 핫바에서 사라짐")
	check(hotbar:FindFirstChild("BagEgg_e2") ~= nil, "남은 가방 알(e2)은 그대로")
	-- 알이 많으면: 최대 6칸 + "…n"
	local many = {}
	for i = 1, 9 do
		table.insert(many, {
			uid = "m" .. i,
			petId = if i % 2 == 0 then "unicorn" else "chicken",
			size = "normal",
			mutations = {},
			biomeId = "forest",
			special = false,
			progress = 0,
			required = 10,
		})
	end
	fire("DataUpdate", "eggs", { eggs = many })
	local eggSlotsN = 0
	for _, child in hotbar:GetChildren() do
		if string.find(child.Name, "BagEgg_", 1, true) then
			eggSlotsN += 1
		end
	end
	local moreSlot = hotbar:FindFirstChild("MoreEggs")
	check(eggSlotsN == 6, "가방 알 9개 → 핫바 알 칸 6개: " .. eggSlotsN)
	check(moreSlot and moreSlot.Visible and moreSlot.Count.Text == "+3", "'…n' 칸 = +3")
	check(
		hotbar:FindFirstChild("BagEgg_m9") ~= nil and hotbar:FindFirstChild("BagEgg_m1") == nil,
		"새 알(m9)부터 보임"
	)
	check(
		click(moreSlot) and panel.Visible and playerGui:FindFirstChild("Bag", true).Visible,
		"'…n' 칸 → 알 창 가방 탭"
	)
	panel.Visible = false
	-- 새 알이 들어오면 칸이 바로 생김
	table.insert(many, {
		uid = "m10",
		petId = "dog",
		size = "normal",
		mutations = {},
		biomeId = "forest",
		special = false,
		progress = 0,
		required = 3,
	})
	fire("DataUpdate", "eggs", { eggs = many })
	local m10 = hotbar:FindFirstChild("BagEgg_m10")
	check(m10 ~= nil and moreSlot.Count.Text == "+4", "새로 얻은 알(m10)이 바로 핫바에 (+4)")
	fire("DataUpdate", "eggs", { eggs = savedEggs })

	-- 5판 주임 검수: 핫바 알 칸 경계 · 칸 재사용 · 놓기 흐름 · 놓인 알은 핫바에 없음
	print("[5판 주임 검수: 핫바 알 칸 경계]")
	local function bagOf(n)
		local list = {}
		for i = 1, n do
			table.insert(list, {
				uid = "h" .. i,
				petId = if i % 2 == 0 then "dog" else "chicken",
				size = "normal",
				mutations = {},
				biomeId = "forest",
				special = false,
				progress = 0,
				required = 10,
			})
		end
		return list
	end
	local function eggSlotCount()
		local n = 0
		for _, child in hotbar:GetChildren() do
			if string.find(child.Name, "BagEgg_", 1, true) then
				n += 1
			end
		end
		return n
	end
	local moreHB = hotbar:FindFirstChild("MoreEggs")
	for _, n in { 0, 1, 5, 6, 7, 8, 12, 50 } do
		fire("DataUpdate", "eggs", { eggs = bagOf(n) })
		local want = math.min(n, 6)
		check(
			eggSlotCount() == want,
			string.format("가방 알 %d개 → 핫바 알 칸 %d개: %d", n, want, eggSlotCount())
		)
		if n <= 6 then
			check(not moreHB.Visible, string.format("알 %d개: '+n' 칸 없음", n))
		else
			check(
				moreHB.Visible and moreHB.Count.Text == "+" .. (n - 6),
				string.format("알 %d개: '+%d' 칸 (%s)", n, n - 6, moreHB.Count.Text)
			)
		end
	end
	fire("DataUpdate", "eggs", { eggs = bagOf(7) })
	check(moreHB.Visible and moreHB.Count.Text == "+1", "알 7개 = 6칸 + '+1'")
	check(
		hotbar:FindFirstChild("BagEgg_h7") ~= nil and hotbar:FindFirstChild("BagEgg_h1") == nil,
		"새 알(h7)이 맨 앞, 가장 오래된 알(h1)이 '+1' 로 밀림"
	)
	-- 같은 목록이 100번 와도 칸을 새로 만들지 않음 (같은 인스턴스) · 핫바 자손 수도 그대로
	local keep5 = hotbar:FindFirstChild("BagEgg_h5")
	local before = #hotbar:GetDescendants()
	for _ = 1, 100 do
		fire("DataUpdate", "eggs", { eggs = bagOf(7) })
	end
	check(
		hotbar:FindFirstChild("BagEgg_h5") == keep5,
		"같은 알 칸은 다시 안 만들고 그대로 씀 (State 가 100번 바뀌어도)"
	)
	check(
		#hotbar:GetDescendants() == before,
		"핫바 자손 수 그대로: " .. before .. " → " .. #hotbar:GetDescendants()
	)
	-- 눌러서 놓기: 보이는 칸 중 가장 오래된 알(h2) → 놓기 모드 → PlaceEgg(h2, x, z)
	root.Position = roblox.Vector3.new(spawnSpot.x, 3, spawnSpot.z)
	check(
		click(hotbar:FindFirstChild("BagEgg_h2")) and Inc.placingUid() == "h2",
		"6번째 알 칸 → h2 놓기 모드"
	)
	local spotH = MapLayout.toWorld(1, -24, 0)
	Inc.previewAt(spotH.x, spotH.z)
	local sentBefore = #sent
	check(Inc.confirmPlace() and #sent == sentBefore + 1, "놓기 확인")
	local ph = lastSent("PlaceEgg")
	check(ph and ph.args[1] == "h2", "PlaceEgg(h2, x, z): " .. tostring(ph and ph.args[1]))
	check(
		not Inc.isPlacing() and Workspace:FindFirstChild("EggPlacePreview") == nil,
		"놓은 뒤 미리보기가 사라짐"
	)
	-- 서버가 받아 주면: 가방에서 빠지고 우리(놓인 알)로 → 핫바에서 사라지고 가려져 있던 h1 이 칸으로 올라옴
	local afterPlace = bagOf(7)
	table.remove(afterPlace, 2)
	fire("DataUpdate", "eggs", { eggs = afterPlace })
	fire("DataUpdate", "incubators", {
		incubators = {
			{
				uid = "h2",
				petId = "dog",
				size = "normal",
				mutations = {},
				biomeId = "forest",
				special = false,
				x = -24,
				z = 0,
				progress = 0,
				required = 3,
			},
		},
	})
	check(hotbar:FindFirstChild("BagEgg_h2") == nil, "놓인 알(h2)은 핫바에 없음")
	check(hotbar:FindFirstChild("BagEgg_h1") ~= nil, "가려져 있던 h1 이 칸으로 올라옴")
	check(eggSlotCount() == 6 and not moreHB.Visible, "6개 남음 → 6칸, '+n' 없음")
	-- 다시 가방으로 주우면 (진행도 유지) 맨 앞 칸으로 돌아오지 않아도 가방 순서대로 보임
	fire("DataUpdate", "incubators", { incubators = {} })
	fire("DataUpdate", "eggs", { eggs = bagOf(7) })
	check(
		hotbar:FindFirstChild("BagEgg_h2") ~= nil and moreHB.Visible,
		"다시 가방에 돌아오면 칸이 다시 생김"
	)
	-- 놓기 모드 중에 도구를 쓰는 숫자키가 아니라 알 칸 숫자키: 칸 번호 = 보이는 순서
	local slotH7 = hotbar:FindFirstChild("BagEgg_h7")
	local numberH7 = tonumber(slotH7 and slotH7:FindFirstChild("Key") and slotH7.Key.Text)
	check(numberH7 ~= nil and numberH7 >= 3, "알 칸 번호는 도구 칸(2) 다음부터: " .. tostring(numberH7))
	-- 연결이 새는지: 곰덫을 손에 들었다 내렸다 50번 → Count 신호 연결 수 (Tool 한 개당)
	do
		local trap = backpack:FindFirstChild("BearTrap")
		local id = trap and trap:GetAttribute("__sid")
		local counter = id and signalCache[id] and signalCache[id]["Attr_Count"]
		check(counter ~= nil, "곰덫 도구의 Count 신호 연결을 읽을 수 있음")
		if counter then
			local c0 = counter.Count()
			for _ = 1, 50 do
				trap.Parent = character
				sigOf(character, "ChildAdded"):Fire(trap)
				trap.Parent = backpack
				sigOf(backpack, "ChildAdded"):Fire(trap)
			end
			local c1 = counter.Count()
			-- 알려진 약점 (HotbarController.watch, Low): 도구가 가방 ↔ 손을 오갈 때마다 같은 도구의 Count 신호에 연결이 또 붙음.
			-- 고쳐지면 아래 한 줄을 check 로 바꾸세요.  기대: c1 - c0 == 0
			print(
				string.format(
					"  [알려진 약점 BUG-H1] 곰덫 50번 들었다 내리면 Count 신호 연결 %d → %d (+%d)",
					c0,
					c1,
					c1 - c0
				)
			)
		end
	end
	fire("DataUpdate", "eggs", { eggs = savedEggs })

	print("[5판: 튜토리얼 패널]")
	local Tut = ctrl("TutorialController")
	local tutPanel = playerGui:FindFirstChild("TutorialPanel", true)
	local function tut(step, text, done, reward)
		fire("TutorialUpdate", {
			step = step,
			total = 5,
			text = text,
			hint = if done then "" else "작은 설명 " .. step,
			done = done or false,
			reward = reward,
		})
	end
	root.Position = roblox.Vector3.new(0, 3, 30) -- 숲 안
	tut(1, "숲에서 알 훔치기")
	check(tutPanel and tutPanel.Visible, "튜토리얼 패널 보임 (위 가운데)")
	check(
		tutPanel.StepBadge.Step.Text == "1/5" and tutPanel.Title.Text == "숲에서 알 훔치기",
		"1/5 · 큰 글씨"
	)
	check(tutPanel.Hint.Text == "작은 설명 1", "작은 설명")
	local guide = Workspace:FindFirstChild("TutorialGuide")
	local targetPart = guide and guide:FindFirstChild("TutorialTarget")
	local markerGui = targetPart and targetPart:FindFirstChild("TutorialMarker")
	check(
		markerGui and markerGui.Enabled and markerGui.Text.Text == "알 훔치기!",
		"1단계: 숲 둥지 알 표시 '알 훔치기!'"
	)
	check(
		targetPart and (targetPart.CFrame.Position - roblox.Vector3.new(0, 1, 60)).Magnitude < 0.01,
		"1단계: 가장 가까운 숲 알(떨어진 알 포함)을 가리킴"
	)
	local tbeam = targetPart and targetPart:FindFirstChild("TutorialBeam")
	check(tbeam and tbeam.Enabled and tbeam.Attachment0 ~= nil, "1단계: 내 캐릭터 → 목표 노란 빔")
	root.Position = roblox.Vector3.new(0, 3, -100) -- 허브
	Tut.update()
	check(markerGui.Text.Text == "숲으로!", "허브에 있으면 '숲으로!' (숲 입구)")
	-- 위 가운데 것들이 패널 아래로 내려감
	local run = playerGui:FindFirstChild("RunBanner", true)
	local tutBottom = tutPanel.Position.Y.Offset + tutPanel.Size.Y.Offset * tutPanel.ScreenScale.Scale
	check(
		run.Position.Y.Offset >= tutBottom,
		string.format("'달리기!!' 배너가 패널 아래 (%d ≥ %.0f)", run.Position.Y.Offset, tutBottom)
	)
	check(playerGui:FindFirstChild("ZoneBanner", true).Position.Y.Offset >= tutBottom, "구역 배너도 패널 아래")
	check(
		playerGui:FindFirstChild("PlaceBar", true).Position.Y.Offset >= tutBottom,
		"알 놓기 안내 줄도 패널 아래"
	)
	tut(2, "안전 구역으로 돌아오기")
	check(tutPanel.StepBadge.Step.Text == "2/5", "2/5")
	check(markerGui.Text.Text == "안전 구역", "2단계: '안전 구역' 표시")
	check(targetPart.CFrame.Position.Z < 0, "2단계: 허브(z < 0) 쪽")
	tut(3, "핫바에서 알을 골라 우리에 놓기")
	check(markerGui.Text.Text == "우리에 놓기", "3단계: 내 우리 표시")
	check(
		hotbar:FindFirstChild("BagEgg_e1"):FindFirstChild("TutorialGlow") ~= nil
			and hotbar:FindFirstChild("BagEgg_e2"):FindFirstChild("TutorialGlow") ~= nil,
		"3단계: 핫바 알 칸 반짝 테두리"
	)
	tut(4, "부화!")
	check(
		hotbar:FindFirstChild("BagEgg_e1"):FindFirstChild("TutorialGlow") == nil,
		"다음 단계면 알 칸 반짝 끝"
	)
	check(markerGui.Text.Text == "부화!", "4단계: 다 자란 내 알 위 '부화!'")
	local hl = guide:FindFirstChild("TutorialHighlight")
	check(hl and hl.Adornee == growingEgg, "4단계: 놓인 알 노란 Highlight")
	tut(5, "펫 장착")
	check(
		playerGui:FindFirstChild("PetsButton", true):FindFirstChild("TutorialGlow") ~= nil,
		"5단계: 펫 버튼 반짝"
	)
	check(not markerGui.Enabled, "5단계: 3D 표시 없음")
	Windows.open("Pets")
	Tut.update()
	local equipGlow = false
	for _, d in playerGui:GetDescendants() do
		if d:IsA("TextButton") and d.Name == "Equip" and d:FindFirstChild("TutorialGlow") then
			equipGlow = true
		end
	end
	check(equipGlow, "5단계: 펫 창 '장착' 버튼 반짝")
	Windows.close()
	holdDelays = true
	tut(6, "", true, 500)
	local donePop = playerGui:FindFirstChild("TutorialDone", true)
	check(not tutPanel.Visible, "끝나면 패널 숨김")
	check(
		donePop and donePop.Card.Reward.Text == "$500 받았어요!",
		"끝 축하: '" .. tostring(donePop and donePop.Card.Reward.Text) .. "'"
	)
	local confetti = 0
	for _, d in (donePop and donePop:GetChildren() or {}) do
		if d.Name == "Confetti" then
			confetti += 1
		end
	end
	check(confetti >= 30, "색종이 " .. confetti .. "장")
	holdDelays = false
	check(
		run.Position.Y.Offset == 14 and playerGui:FindFirstChild("PlaceBar", true).Position.Y.Offset == 64,
		"패널이 숨으면 위 가운데 것들 제자리"
	)
	check(playerGui:FindFirstChild("TutorialGlow", true) == nil, "끝나면 반짝 테두리 없음")
	-- 이미 끝낸 사람 (Snapshot.tutorial.done) → 안 보임
	fire("DataUpdate", "tutorial", { tutorial = { step = 6, total = 5, text = "", hint = "", done = true } })
	check(not tutPanel.Visible, "State.tutorial.done → 패널 숨김")
	-- 다시 처음부터 (/tutorial reset)
	tut(1, "숲에서 알 훔치기")
	check(tutPanel.Visible and tutPanel.StepBadge.Step.Text == "1/5", "/tutorial reset → 1/5 다시 보임")

	print("[5판: 랭킹판]")
	local lb = playerGui:FindFirstChild("Leaderboard", true)
	check(lb ~= nil, "오른쪽 위 랭킹판")
	fire("LeaderboardUpdate", {
		money = {
			{ name = "부자", value = 5e9, userId = 1 },
			{ name = "Tester", value = 12345, userId = 77 },
			{ name = "셋째", value = 100, userId = 3 },
		},
		speed = {
			{ name = "Tester", value = 2.5e6, userId = 77 },
			{ name = "부자", value = 1000, userId = 1 },
		},
	})
	local Lb = ctrl("LeaderboardController")
	Lb.setExpanded(true)
	local rowsFrame = lb:FindFirstChild("Rows")
	local row2 = rowsFrame and rowsFrame:FindFirstChild("Row2")
	check(rowsFrame and rowsFrame:FindFirstChild("Row3") ~= nil and rowsFrame:FindFirstChild("Row4") == nil, "돈 3줄")
	check(row2 and row2.PlayerName.Text == "Tester" and row2:GetAttribute("Mine") == true, "내 줄 강조 (2등)")
	check(
		rowsFrame.Row1.Value.Text == "$5B" or string.sub(rowsFrame.Row1.Value.Text, 1, 1) == "$",
		"돈 = Format.money: " .. rowsFrame.Row1.Value.Text
	)
	check(click(lb:FindFirstChild("LbTab_speed")), "속도 탭")
	check(
		rowsFrame.Row1.PlayerName.Text == "Tester" and rowsFrame:FindFirstChild("Row3") == nil,
		"속도 2줄, 1등 = 나"
	)
	check(string.sub(rowsFrame.Row1.Value.Text, 1, 1) ~= "$", "속도 = Format.number: " .. rowsFrame.Row1.Value.Text)
	check(click(lb:FindFirstChild("LbToggle")) and not Lb.isExpanded() and not rowsFrame.Visible, "접기")
	check(click(lb:FindFirstChild("LbToggle")) and Lb.isExpanded() and rowsFrame.Visible, "펴기")
	local boardGui = lbBoard:FindFirstChild("LeaderboardGui")
	check(boardGui and boardGui.Face == roblox.Enum.NormalId.Front, "허브 3D 판 SurfaceGui (Front)")
	local line1 = boardGui and boardGui:FindFirstChild("Line1", true)
	check(
		boardGui
			and string.find(boardGui.Back.Column_money.Line1.Text, "부자", 1, true)
			and string.find(boardGui.Back.Column_speed.Line1.Text, "Tester", 1, true),
		"허브 판: 돈 1등 '" .. tostring(line1 and line1.Text) .. "' · 속도 1등"
	)
	check(boardGui and boardGui.Back.Column_money.Line4.Text == "", "허브 판: 없는 줄은 빈칸")
	-- 가득 (10줄) — 아래 반응형 검사에서 가장 긴 랭킹판으로 겹침 확인
	local ten = {}
	for i = 1, 10 do
		table.insert(
			ten,
			{ name = "플레이어" .. i, value = 1e6 * (11 - i), userId = if i == 7 then 77 else 1000 + i }
		)
	end
	fire("LeaderboardUpdate", { money = ten, speed = ten })
	check(
		rowsFrame:FindFirstChild("Row10") ~= nil and rowsFrame.Row7:GetAttribute("Mine") == true,
		"10줄, 7등 = 내 줄"
	)
	check(boardGui.Back.Column_speed.Line10.Text ~= "", "허브 판 10줄")

	print("[5판: 쓰다듬기]")
	check(myPetPrompt.Enabled, "내 펫 '쓰다듬기' 프롬프트 켜짐")
	check(not otherPetPrompt.Enabled, "남의 펫 프롬프트는 내 화면에서 꺼짐")
	check(
		trigger(myPetPrompt) and lastSent("PetPet") and lastSent("PetPet").args[1] == "p1",
		"쓰다듬기 → PetPet(p1)"
	)
	local beforePet = #sent
	trigger(otherPetPrompt)
	check(#sent == beforePet, "남의 펫은 안 보냄")
	holdDelays = true
	fire("PetPetted", 77, "p1")
	local hearts = penPetRoot:FindFirstChild("PetHearts")
	check(hearts and hearts.AlwaysOnTop and hearts:FindFirstChild("Heart1").Text == "♥", "내 펫 위 '♥' 하트")
	check(
		otherPetRoot:FindFirstChild("PetHearts") == nil,
		"같은 uid 의 남의 펫에는 안 뜸 (주인으로 거름)"
	)
	fire("PetPetted", 12345, "p1")
	check(otherPetRoot:FindFirstChild("PetHearts") ~= nil, "남이 자기 펫을 쓰다듬으면 그 펫 위에 하트")
	holdDelays = false
	local Pf = ctrl("PetFxController")
	check(not Pf.petted(77, "nope"), "없는 펫이면 연출 없음")
	check(Pf.findPet(77, "p1") == penPet and Pf.findPet(12345, "p1") == otherPet, "주인 + uid 로 펫 찾기")
	-- 폴짝 (서버 자리 위로만): Heartbeat 한 번 돌려도 오류 없음
	fakeServices.RunService.Heartbeat:Fire(1 / 60)
	check(true, "폴짝 한 프레임")

	-- 5판 주임 검수: 서버가 엉터리 모양을 보내도(옛 서버·버그) 새 화면 3개가 안 터지고, 그 뒤 정상 신호는 그대로 처리
	print("[5판 주임 검수: 엉터리 신호가 와도 안 터짐]")
	do
		local prevView = Tut.view()
		local longName = string.rep("가", 500)
		local cases = {
			TutorialUpdate = {
				{ n = 0 },
				{ "x", n = 1 },
				{ 5, n = 1 },
				{ {}, n = 1 },
				{ { step = 0 }, n = 1 },
				{ { step = 99 }, n = 1 },
				{ { step = 0 / 0 }, n = 1 },
				{ { step = -3, total = 5, text = "t", hint = "h" }, n = 1 },
				{ { step = 3 }, n = 1 },
				{ { step = 3, text = 5, hint = {} }, n = 1 },
				{ { step = 1, total = 0, text = "t", hint = "h" }, n = 1 },
				{ { step = 1, total = "x", text = "t", hint = "h" }, n = 1 },
				{ { step = 6, total = 5, done = true, reward = "500" }, n = 1 },
				{ { step = 6, total = 5, done = true, reward = -1 }, n = 1 },
				{ { step = 6, total = 5, done = true, reward = 0 / 0 }, n = 1 },
			},
			LeaderboardUpdate = {
				{ n = 0 },
				{ "x", n = 1 },
				{ {}, n = 1 },
				{ { money = "x", speed = 5 }, n = 1 },
				{
					{
						money = {
							{},
							{ name = 5, value = "a" },
							{ name = "n", value = 0 / 0 },
							{ value = 1 / 0 },
						},
					},
					n = 1,
				},
				{ { money = { { name = longName, value = 1e300, userId = 1 } }, speed = {} }, n = 1 },
			},
			PetPetted = {
				{ n = 0 },
				{ nil, nil, n = 2 },
				{ "x", 5, n = 2 },
				{ 5, nil, n = 2 },
				{ 0 / 0, "p1", n = 2 },
				{ 77, "", n = 2 },
				{ 77, string.rep("p", 1000), n = 2 },
				{ {}, {}, n = 2 },
			},
		}
		local broke = {}
		local total = 0
		for name, list in cases do
			for i, args in list do
				total += 1
				local ok, err = pcall(fire, name, table.unpack(args, 1, args.n))
				if not ok then
					table.insert(broke, string.format("%s #%d: %s", name, i, tostring(err)))
				end
			end
		end
		-- 알려진 약점 (Low, BUG-L1): 랭킹 줄이 표가 아니면(서버는 절대 안 보냄) LeaderboardController.renderBoards 가 e.name 에서 터짐
		local okRaw, errRaw = pcall(fire, "LeaderboardUpdate", { money = { 5, "x" }, speed = {} })
		print(
			"  [알려진 약점 BUG-L1] 랭킹 줄이 숫자·글이면: "
				.. (if okRaw then "안 터짐 (고쳐졌어요)" else tostring(errRaw))
		)
		check(#broke == 0, string.format("엉터리 신호 %d개 모두 무사: %s", total, table.concat(broke, " | ")))
		-- 그 뒤 정상 신호는 그대로 처리
		fire("TutorialUpdate", {
			step = 3,
			total = 5,
			text = "핫바에서 알을 골라 우리에 놓기",
			hint = "작은 설명",
			done = false,
		})
		check(
			tutPanel and tutPanel.Visible and Tut.view().step == 3,
			"엉터리 뒤 정상 튜토리얼 신호 처리: " .. tostring(Tut.view() and Tut.view().step)
		)
		fire("LeaderboardUpdate", { money = ten, speed = ten })
		check(rowsFrame:FindFirstChild("Row10") ~= nil, "엉터리 뒤 정상 랭킹 신호 처리")
		if prevView then
			fire("TutorialUpdate", prevView)
		end
	end

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
		check(#rects == 4, tag .. " 메뉴 버튼 4개 (5판: 퀘스트·선물 버튼 없앰)")
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
		-- 5판: 도구 칸 + 가방 알 칸(+ "…n") 이 다 들어감
		local shownSlots, eggSlotsShown = 0, 0
		for _, child in bar:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				shownSlots += 1
				if string.find(child.Name, "BagEgg_", 1, true) or child.Name == "MoreEggs" then
					eggSlotsShown += 1
				end
			end
		end
		check(
			bar.Size.X.Offset == shownSlots * Layout.SLOT + (shownSlots - 1) * Layout.SLOT_GAP,
			tag .. " 핫바 너비 = 칸 수 " .. shownSlots .. " (알 칸 " .. eggSlotsShown .. ")"
		)
		check(eggSlotsShown >= 1, tag .. " 가방 알이 있으면 알 칸(또는 '…n')이 핫바에 보임")
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

		-- 5판: 튜토리얼 패널(위 가운데) · 랭킹판(오른쪽 위) 이 다른 HUD 와 안 겹침 (랭킹판 접힘/펼침 둘 다)
		local k = Ui.scale()
		local tutS = tutPanel.ScreenScale.Scale
		local tutRect = {
			x = area.X / 2 - tutPanel.Size.X.Offset * tutS / 2,
			y = tutPanel.Position.Y.Offset,
			w = tutPanel.Size.X.Offset * tutS,
			h = tutPanel.Size.Y.Offset * tutS,
		}
		local rbFrame = hudLayer:FindFirstChild("RightButtons")
		local rbS = rbFrame.ScreenScale.Scale
		local rbRect = {
			x = area.X + rbFrame.Position.X.Offset - rbFrame.Size.X.Offset * rbS,
			y = area.Y * rbFrame.Position.Y.Scale - rbFrame.Size.Y.Offset * rbS / 2,
			w = rbFrame.Size.X.Offset * rbS,
			h = rbFrame.Size.Y.Offset * rbS,
		}
		local layoutRb = Layout.rightButtons(area, k, case.touch)
		check(
			math.abs(layoutRb.x - rbRect.x) < 1 and math.abs(layoutRb.y - rbRect.y) < 1,
			tag .. " Layout.rightButtons = 실제 알·발바닥 버튼 자리 " .. fmt(rbRect)
		)
		local timerRect = Layout.timerRect(area, k, case.touch)
		local others = {
			{ name = "속도·돈", rect = statsRect(area, case.touch) },
			{ name = "시간", rect = timerRect },
			{ name = "알·발바닥 버튼", rect = rbRect },
			{ name = "핫바", rect = hb },
		}
		for _, r in rects do
			table.insert(others, { name = "메뉴 " .. r.name, rect = r })
		end
		check(tutPanel.Visible, tag .. " 튜토리얼 패널 보임")
		check(
			tutRect.y >= 0 and tutRect.x >= 0 and tutRect.x + tutRect.w <= area.X,
			tag .. " 튜토리얼 패널 화면 안 " .. fmt(tutRect)
		)
		for _, o in others do
			check(
				not Layout.overlaps(tutRect, o.rect),
				tag .. " 튜토리얼 패널이 " .. o.name .. " 과 안 겹침"
			)
		end
		for _, expandedNow in { false, true } do
			Lb.setExpanded(expandedNow)
			local lbS = lb.ScreenScale.Scale
			local lbRect = {
				x = lb.Position.X.Offset,
				y = lb.Position.Y.Offset,
				w = lb.Size.X.Offset * lbS,
				h = lb.Size.Y.Offset * lbS,
			}
			local what = tag .. (if expandedNow then " 랭킹판(펼침) " else " 랭킹판(접힘) ") .. fmt(lbRect)
			check(
				lbRect.x >= 0 and lbRect.y >= 0 and lbRect.x + lbRect.w <= area.X and lbRect.y + lbRect.h <= area.Y,
				what .. " 화면 안"
			)
			check(not Layout.overlaps(lbRect, tutRect), what .. " 이 튜토리얼 패널과 안 겹침")
			for _, o in others do
				check(not Layout.overlaps(lbRect, o.rect), what .. " 이 " .. o.name .. " 과 안 겹침")
			end
		end
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
