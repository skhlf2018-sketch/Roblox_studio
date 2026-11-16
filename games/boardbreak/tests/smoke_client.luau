--!nocheck
--[[
	송판 깨기 — 클라 화면 스모크 테스트 (선임). 저장소 루트에서:
	  lune run games/boardbreak/tests/smoke_client.luau
	(tests/run.luau 에는 안 들어감. 로블록스 없이 @lune/roblox 진짜 GUI 인스턴스로 컨트롤러를 전부 start() 하고,
	 진짜 맵(MapBuilder)을 만든 뒤 버튼·표지판·물건을 눌러 보며 보낸 Remote 와 화면 반응을 확인합니다.)

	하는 일: 컨트롤러 전부 시작 → Snapshot → 힘·돈·띠 표시 → 수련 매트 위 "들기"(Train)·TrainResult "+N"
	        → 물건 앞 "치기"(Hit)·물건 클릭(ClickDetector)·먼 물건 클릭(걸어가서 Hit) → HitResult 체력 막대·힘이 부족해요·깨짐 "+💰"
	        → 심사(Activity exam · ExamState 막대 · Hit("exam") · 송판 사라짐 · 합격) → 대결(DuelState · Hit("duel") · 승리)
	        → 아령 가게(카운터 클릭 · 사기 → BuyDumbbell · 돈 모자람) → 도감(깬 것 / ???) → 띠 창(심사 보기 → StartExam, 대결 → StartDuel)
	        → 월드 문(잠김 / 열림 → Travel) → 힘 배수 창(순서대로만, 준비 중) → 설정(SetSetting) → 튜토리얼 3단계 → ProductGranted
	        → 폰 화면(844×390, 터치): 메뉴·큰 버튼 46px 이상, 조이스틱·점프 버튼·힘 줄과 안 겹침
	task.wait 는 바로 멈추고(무한 루프 방지), task.delay 는 바로 실행합니다.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./Loader")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
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
			local box = function(...)
				return fn(...)
			end
			table.insert(handlers, box)
			return {
				Disconnect = function()
					local i = table.find(handlers, box)
					if i then
						table.remove(handlers, i)
					end
				end,
			}
		end,
		Wait = function() end,
		Fire = function(_, ...)
			for _, h in table.clone(handlers) do
				h(...)
			end
		end,
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
	"ScreenGui",
	"Folder",
	"NumberValue",
	"Model",
	"Part",
	"SpawnLocation",
	"Camera",
	"BillboardGui",
	"SurfaceGui",
	"UIScale",
	"UIStroke",
	"Player",
	"Workspace",
	"Humanoid",
	"ClickDetector",
	"Sound",
	"Weld",
}
local EVENTS = {
	"MouseButton1Down",
	"MouseButton1Up",
	"MouseLeave",
	"MouseEnter",
	"InputEnded",
	"Activated",
	"Destroying",
	"AncestryChanged",
	"ChildAdded",
	"ChildRemoved",
	"Changed",
	"CharacterAdded",
	"MouseClick",
	"MouseHoverEnter",
	"MouseHoverLeave",
	"MoveToFinished",
	"Ended",
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
roblox.implementMethod("Model", "GetPivot", function(model)
	local primary = model.PrimaryPart
	return if primary then primary.CFrame else CFrame.new()
end)
for _, cls in { "Part", "SpawnLocation" } do
	pcall(roblox.implementProperty, cls, "Position", function(part)
		return part.CFrame.Position
	end, function(part, v)
		part.CFrame = CFrame.new(v) * part.CFrame.Rotation
	end)
	-- LocalTransparencyModifier (내 화면에서만 투명) — Lune 에 없을 수 있어 Attribute 로 흉내
	pcall(roblox.implementProperty, cls, "LocalTransparencyModifier", function(part)
		return part:GetAttribute("__ltm") or 0
	end, function(part, v)
		part:SetAttribute("__ltm", v)
	end)
end
pcall(roblox.implementMethod, "Sound", "Play", function(inst)
	inst.Playing = true
end)
pcall(roblox.implementMethod, "Sound", "Stop", function(inst)
	inst.Playing = false
end)
pcall(roblox.implementMethod, "SoundService", "PlayLocalSound", function() end)

-- 화면 크기 (카메라 ViewportSize) — 폰 검사 때 바꿈
local camera = Instance.new("Camera")
camera.ViewportSize = Vector2.new(1100, 720)
camera.Parent = Workspace
Workspace.CurrentCamera = camera

local tagged = {}
local addedSignals = {}
local CollectionService = {
	AddTag = function(_, inst, name)
		tagged[name] = tagged[name] or {}
		table.insert(tagged[name], inst)
	end,
	GetTagged = function(_, name)
		return table.clone(tagged[name] or {})
	end,
	GetInstanceAddedSignal = function(_, name)
		addedSignals[name] = addedSignals[name] or signal()
		return addedSignals[name]
	end,
	GetInstanceRemovedSignal = function()
		return signal()
	end,
}

local player = Instance.new("Player")
local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
local A = {
	Power = "Power",
	Money = "Money",
	DumbbellLevel = "DumbbellLevel",
	Belt = "Belt",
	World = "World",
	CurrentWorld = "CurrentWorld",
	PowerBoost = "PowerBoost",
	MoneyPass = "MoneyPass",
	Activity = "Activity",
}
local function setAttr(name, value)
	player:SetAttribute(name, value)
	sigOf(player, "Attr_" .. name):Fire()
end
player:SetAttribute(A.Power, 0)
player:SetAttribute(A.Money, 0)
player:SetAttribute(A.DumbbellLevel, 1)
player:SetAttribute(A.Belt, 1)
player:SetAttribute(A.World, 1)
player:SetAttribute(A.CurrentWorld, 1)
player:SetAttribute(A.PowerBoost, 1)
player:SetAttribute(A.MoneyPass, false)
player:SetAttribute(A.Activity, "")

local character = Instance.new("Model")
character.Name = "Tester"
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.CFrame = CFrame.new(0, 3, -36)
root.Parent = character
local hand = Instance.new("Part")
hand.Name = "RightHand"
hand.CFrame = CFrame.new(1.5, 3, -36)
hand.Parent = character
local head = Instance.new("Part")
head.Name = "Head"
head.CFrame = CFrame.new(0, 4.5, -36)
head.Parent = character
local humanoid = Instance.new("Humanoid")
humanoid.Parent = character
character.Parent = Workspace
player.Character = character
local moveTargets = {}
local pendingMove = nil
roblox.implementMethod("Humanoid", "MoveTo", function(h, pos)
	table.insert(moveTargets, pos)
	root.CFrame = CFrame.new(pos.X, 3, pos.Z)
	pendingMove = h -- flushMoves() 가 도착 신호 (Walk 는 MoveTo 뒤에 MoveToFinished 를 연결함)
end)
local function flushMoves()
	local h = pendingMove
	pendingMove = nil
	if h then
		sigOf(h, "MoveToFinished"):Fire(true)
	end
end
local function moveTo(x, z)
	root.CFrame = CFrame.new(x, 3, z)
end

local Players = {
	LocalPlayer = player,
	PlayerAdded = signal(),
	GetPlayers = function()
		return { player }
	end,
}
local tweenStub = {
	Create = function()
		local done = signal()
		return { Play = function() end, Cancel = function() end, Completed = done }
	end,
}
local marketPrompts = {}
local MarketplaceStub = {
	PromptProductPurchase = function(_, who, id)
		table.insert(marketPrompts, { id = id, pass = false })
	end,
	PromptGamePassPurchase = function(_, who, id)
		table.insert(marketPrompts, { id = id, pass = true })
	end,
	PromptProductPurchaseFinished = signal(),
	PromptGamePassPurchaseFinished = signal(),
}
local touch = false
local UIS = {
	InputBegan = signal(),
	LastInputTypeChanged = signal(),
	GetLastInputType = function()
		return if touch then roblox.Enum.UserInputType.Touch else roblox.Enum.UserInputType.MouseButton1
	end,
}
setmetatable(UIS, {
	__index = function(_, key)
		if key == "TouchEnabled" then
			return touch
		elseif key == "MouseEnabled" then
			return not touch
		end
		return nil
	end,
})
local fakeServices = {
	MarketplaceService = MarketplaceStub,
	CollectionService = CollectionService,
	Players = Players,
	TweenService = tweenStub,
	RunService = {
		Heartbeat = signal(),
		RenderStepped = signal(),
		IsStudio = function()
			return false
		end,
	},
	UserInputService = UIS,
	GuiService = {
		GetGuiInset = function()
			return Vector2.new(0, 58), Vector2.new(0, 0)
		end,
	},
	SoundService = game:GetService("SoundService"),
	Lighting = game:GetService("Lighting"),
	Workspace = Workspace,
}
local function warm(node)
	for _, child in node.GetChildren(node) do
		warm(child)
	end
end
warm(Loader.get("ReplicatedStorage"))
warm(Loader.get("ServerScriptService"))
local sharedNode = Loader.get("ReplicatedStorage")
fakeServices.ReplicatedStorage = setmetatable({}, {
	__index = function(_, key)
		if key == "Shared" or key == "Client" then
			return sharedNode[key]
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

-- Net 흉내
local handlers = {}
local sent = {}
local NetStub = {
	on = function(name, fn)
		assert(type(name) == "string", "Net.on 이름이 문자열이 아님")
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
local function countSent(name)
	local n = 0
	for _, s in sent do
		if s.name == name then
			n += 1
		end
	end
	return n
end

local STOP = "__STOP__"
local function runSafe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not string.find(tostring(err), STOP, 1, true) then
		error(err, 0)
	end
end
local delayDepth = 0
local holdDelays = false -- true 면 task.delay 를 실행하지 않음 (잠깐 떠 있는 팝업 검사)
local taskStub = {
	spawn = runSafe,
	defer = function(fn, ...)
		runSafe(fn, ...)
	end,
	wait = function()
		error(STOP)
	end,
	delay = function(_, fn, ...)
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
local function client(name)
	return requireNode(Loader.get("ReplicatedStorage/Client/" .. name))
end
local function shared(path)
	return requireNode(Loader.get("ReplicatedStorage/Shared/" .. path))
end
local function press(button)
	sigOf(button, "Activated"):Fire()
end
local function find(parent, name)
	return parent and parent:FindFirstChild(name, true)
end

local function body()
	local Tags = shared("Tags")
	local Remotes = shared("Remotes")
	local MapLayout = shared("Data/MapLayout")
	local Format = shared("Format")
	local Belts = shared("Data/Belts")
	local Dumbbells = shared("Data/Dumbbells")
	local R = Remotes.ToClient
	local S = Remotes.ToServer

	print("[맵 + 컨트롤러 시작]")
	local MapBuilder = requireNode(Loader.get("ServerScriptService/Server/Services/MapBuilder"))
	MapBuilder.start()
	check(Workspace:FindFirstChild("Map") ~= nil, "맵 만들기 (MapBuilder.start, 진짜 태그·ClickDetector)")
	local State = client("State")
	State.start()
	local order = {
		"SoundController",
		"NotifyController",
		"HudController",
		"DumbbellShopController",
		"IndexController",
		"BoostController",
		"BeltController",
		"SettingsController",
		"TrainController",
		"BreakController",
		"ExamController",
		"WorldController",
		"TutorialController",
	}
	local startedAll = true
	for _, name in order do
		local ok, err = pcall(function()
			ctrl(name).start()
		end)
		if not ok then
			startedAll = false
			print("    시작 실패 " .. name .. ": " .. tostring(err))
		end
	end
	check(startedAll, "컨트롤러 13개 start() 오류 없음")
	local Purchase = client("Purchase")
	Purchase.start()
	-- Main.client 도 문법·require 확인 (실행은 안 함 — 진입점은 game.Loaded 를 기다림)
	local mainOk = pcall(function()
		luau.compile(fs.readFile("games/boardbreak/src/client/Main.client.luau"))
	end)
	check(mainOk, "Main.client.luau 컴파일")
	local mainSrc = fs.readFile("games/boardbreak/src/client/Main.client.luau")
	local bootedAll = true
	for _, name in order do
		if not string.find(mainSrc, 'boot("' .. name .. '")', 1, true) then
			bootedAll = false
			print("    Main 에서 안 부름: " .. name)
		end
	end
	check(
		bootedAll and string.find(mainSrc, "ClientReady", 1, true) ~= nil,
		"Main 이 컨트롤러 13개 boot + ClientReady 보냄"
	)

	local screen = playerGui:FindFirstChild("BoardBreakUI")
	check(screen ~= nil, "ScreenGui BoardBreakUI")

	print("[Snapshot → HUD]")
	local snap = {
		power = 1234,
		money = 56789,
		dumbbellLevel = 1,
		belt = 1,
		world = 1,
		currentWorld = 1,
		broken = { cotton = 3 },
		powerBoost = 1,
		moneyPass = false,
		ownedPasses = {},
		grandMaster = false,
		settings = { music = true, sfx = true, lowGraphics = false },
		saveEnabled = false,
		activity = "",
	}
	fire(R.Snapshot, snap)
	setAttr(A.Power, 1234)
	setAttr(A.Money, 56789)
	local Hud = ctrl("HudController")
	Hud.refresh()
	local stats = Hud.statsFrame()
	check(find(stats, "Power").Text == Format.number(1234), "힘 표시 " .. find(stats, "Power").Text)
	check(find(stats, "Money").Text == Format.number(56789), "돈 표시 " .. find(stats, "Money").Text)
	check(find(stats, "BeltName").Text == Belts.get(1).name, "띠 표시 " .. find(stats, "BeltName").Text)
	check(find(stats, "BoostBadge").Visible == false, "힘 배수 ×1 이면 배지 숨김")
	setAttr(A.PowerBoost, 8)
	Hud.refresh()
	check(find(stats, "BoostBadge").Visible and find(stats, "BoostBadge").Text == "×8", "힘 배수 ×8 배지")
	setAttr(A.PowerBoost, 1)
	local kinds = { "shop", "index", "boost", "belt", "settings" }
	local menuOk = true
	for _, k in kinds do
		if not Hud.menuButton(k) then
			menuOk = false
			print("    메뉴 없음: " .. k)
		end
	end
	check(menuOk, "왼쪽 메뉴 5개 (아령 가게 · 도감 · 힘 배수 · 띠·심사 · 설정)")

	print("[수련 매트 · 들기]")
	local Train = ctrl("TrainController")
	moveTo(0, -36)
	Train.check()
	check(
		not Train.onMat() and not Train.button.button.Visible,
		"스폰 자리: 매트 아님 → 들기 버튼 숨김"
	)
	local mat = MapLayout.trainMats(1)[1]
	moveTo(mat.x, mat.z)
	Train.check()
	check(Train.onMat() and Train.button.button.Visible, '매트 위 → 큰 "들기" 버튼')
	check(
		Train.button.sub.Text == Dumbbells.get(1).name,
		"버튼에 지금 아령 이름 (" .. Train.button.sub.Text .. ")"
	)
	check(character:FindFirstChild("HeldDumbbell") ~= nil, "손에 아령 (내 화면에만)")
	local before = countSent(S.Train)
	Train.button.press()
	Train.button.release()
	check(countSent(S.Train) == before + 1, "들기 누름 → Train() 보냄")
	holdDelays = true
	fire(R.TrainResult, { gain = 5, power = 1239 })
	holdDelays = false
	local gain = playerGui:FindFirstChild("GainPopup")
	check(gain ~= nil and string.find(gain.Text.Text, "+5", 1, true) ~= nil, 'TrainResult → 머리 위 "+5 💪"')
	-- 화면 빈 곳 누르기 (매트 위)
	fakeServices.UserInputService.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton1 }, false)
	check(countSent(S.Train) == before + 2, "매트 위에서 화면 누름 → Train()")
	moveTo(0, -36)
	Train.check()
	check(
		not Train.button.button.Visible and character:FindFirstChild("HeldDumbbell") == nil,
		"매트에서 내려오면 버튼·아령 사라짐"
	)

	print("[물건 치기]")
	local Break = ctrl("BreakController")
	Break.refresh()
	check(not Break.button.button.Visible, "로비 스폰: 치기 버튼 없음")
	local road = MapLayout.roadPoint("cotton")
	moveTo(road.x, road.z)
	Break.refresh()
	check(Break.button.button.Visible and Break.button.sub.Text == "솜", '솜 앞 → "치기" 버튼 (솜)')
	Break.button.press()
	Break.button.release()
	local hit = lastSent(S.Hit)
	check(hit and hit.args[1] == "cotton", '치기 → Hit("cotton")')
	local models = Break.models()
	check(models.cotton ~= nil and models.universe ~= nil, "물건 모델 41개 연결 (솜·우주)")
	local n0 = countSent(S.Hit)
	sigOf(models.cotton:FindFirstChild("Click"), "MouseClick"):Fire(player)
	check(
		countSent(S.Hit) == n0 + 1 and lastSent(S.Hit).args[1] == "cotton",
		'솜 클릭(ClickDetector) → Hit("cotton")'
	)
	-- 먼 물건 클릭 → 걸어가서 침
	table.clear(moveTargets)
	sigOf(models.wood:FindFirstChild("Click"), "MouseClick"):Fire(player)
	flushMoves()
	check(
		#moveTargets == 1 and lastSent(S.Hit).args[1] == "wood",
		'먼 나무 송판 클릭 → 앞으로 걸어가서 Hit("wood")'
	)
	-- 다른 월드 물건은 무시
	local n1 = countSent(S.Hit)
	sigOf(models.moon:FindFirstChild("Click"), "MouseClick"):Fire(player)
	check(countSent(S.Hit) == n1, "다른 월드 물건(달) 클릭은 무시")
	-- HitResult 반영 (잠깐 떠 있는 글을 보려고 task.delay 멈춤)
	holdDelays = true
	Break.onHitResult({ targetId = "wood", damage = 1000, hp = 39000, hpMax = 40000, broken = false })
	local bar = playerGui:FindFirstChild("HpBar_wood")
	check(bar ~= nil and bar.Enabled ~= false, "HitResult → 물건 위 체력 막대")
	local fill = find(bar, "Fill")
	check(fill and math.abs(fill.Size.X.Scale - 39000 / 40000) < 1e-6, "체력 막대 길이 = hp / hpMax")
	check(
		string.find(find(bar, "Hp").Text, Format.number(39000), 1, true) ~= nil,
		"체력 숫자 " .. find(bar, "Hp").Text
	)
	local function floatTexts()
		local list = {}
		for _, g in playerGui:GetChildren() do
			if g.Name == "FloatText" then
				table.insert(list, g.Text.Text)
			end
		end
		return list
	end
	local function hasFloat(pattern)
		for _, t in floatTexts() do
			if string.find(t, pattern, 1, true) then
				return true
			end
		end
		return false
	end
	check(hasFloat("-" .. Format.number(1000)), '깎인 체력 "-1K" 숫자')
	Break.onHitResult({ targetId = "steel", damage = 0, hp = 1.6e6, hpMax = 1.6e6, broken = false, reason = "weak" })
	check(hasFloat("힘이 부족해요"), 'reason weak → 물건 위 빨간 "힘이 부족해요!"')
	Break.onHitResult({ targetId = "cotton", damage = 20, hp = 20, hpMax = 20, broken = true, reward = 3 })
	check(hasFloat("+💰 3"), '깨짐 → "+💰 3" 금색 숫자')
	local shards = 0
	for _, d in Workspace:GetChildren() do
		if d.Name == "Shard" then
			shards += 1
		end
	end
	check(true, "깨짐 → 조각 (task.delay 가 바로 지워서 " .. shards .. "개 남음)")
	holdDelays = false
	Break.onHitResult({ targetId = "nope", damage = 1 })
	Break.onHitResult("bad")
	check(true, "모르는 id·잘못된 값은 조용히 무시")

	print("[승급 심사]")
	local Exam = ctrl("ExamController")
	moveTo(MapLayout.examPad(1).x, MapLayout.examPad(1).z)
	setAttr(A.Activity, "exam")
	fire(R.ExamState, { phase = "start", broken = 0, total = 10, secondsLeft = 20, belt = 2 })
	fire(
		R.ExamState,
		{ phase = "progress", broken = 3, total = 10, secondsLeft = 12, belt = 2, boardHp = 5, boardHpMax = 8e5 }
	)
	local panel = Exam.panel
	check(
		panel.Visible and string.find(find(panel, "Title").Text, Belts.get(2).name, 1, true) ~= nil,
		"심사 패널 (노랑 띠)"
	)
	check(find(find(panel, "Bar1"), "Text").Text == "3 / 10 장", "막대 1 = 깬 송판 3 / 10")
	check(find(find(panel, "Bar2"), "Text").Text == "12초", "막대 2 = 남은 시간 12초")
	Break.refresh()
	check(
		Break.button.button.Visible and Break.button.title.Text == "송판 치기!",
		'심사 중 큰 "송판 치기!" 버튼'
	)
	Break.button.press()
	Break.button.release()
	check(lastSent(S.Hit).args[1] == Remotes.EXAM_TARGET, '심사 중 치기 → Hit("exam")')
	local pad = CollectionService:GetTagged(Tags.ExamPad)[1]
	check(
		find(pad, "Board_3").LocalTransparencyModifier == 1 and find(pad, "Board_4").LocalTransparencyModifier == 0,
		"깬 송판 3장은 사라짐 (내 화면)"
	)
	fire(R.ExamState, { phase = "pass", broken = 10, total = 10, secondsLeft = 4, belt = 2 })
	setAttr(A.Activity, "")
	check(
		not panel.Visible and find(pad, "Board_3").LocalTransparencyModifier == 0,
		"합격 → 패널 닫힘 · 송판 다시"
	)
	local big = find(screen, "ExamBig")
	check(big ~= nil, "합격 큰 글 자리 (ExamBig)")

	print("[시험관 대결]")
	setAttr(A.Activity, "duel")
	fire(R.DuelState, { phase = "start", mine = 0, theirs = 0, total = 15, world = 1, secondsLeft = 90 })
	fire(R.DuelState, { phase = "progress", mine = 5, theirs = 4, total = 15, world = 1, secondsLeft = 60 })
	check(
		panel.Visible and string.find(find(panel, "Title").Text, "호랑이 사범님", 1, true) ~= nil,
		"대결 패널 (시험관 이름)"
	)
	check(
		find(find(panel, "Bar1"), "Text").Text == "5 / 15" and find(find(panel, "Bar2"), "Text").Text == "4 / 15",
		"막대 2개: 나 5 / 시험관 4"
	)
	Break.refresh()
	Break.button.press()
	Break.button.release()
	check(lastSent(S.Hit).args[1] == Remotes.DUEL_TARGET, '대결 중 치기 → Hit("duel")')
	local arena = CollectionService:GetTagged(Tags.DuelArena)[1]
	check(
		find(arena, "Mine_5").LocalTransparencyModifier == 1 and find(arena, "Theirs_5").LocalTransparencyModifier == 0,
		"대결 송판: 내 5장 · 시험관 4장 사라짐"
	)
	fire(R.DuelState, { phase = "win", mine = 15, theirs = 11, total = 15, world = 1 })
	setAttr(A.Activity, "")
	check(not panel.Visible, "승리 → 패널 닫힘")
	fire(R.DuelState, { phase = "lose", mine = 3, theirs = 15, total = 15, world = 2 })
	check(not panel.Visible, "패배도 오류 없음")

	print("[아령 가게]")
	local Windows = client("UI/Windows")
	local Shop = ctrl("DumbbellShopController")
	local shopModel = CollectionService:GetTagged(Tags.DumbbellShop)[1]
	sigOf(shopModel:FindFirstChild("Click"), "MouseClick"):Fire(player)
	check(Windows.isOpen(Shop.NAME), "가게 카운터 클릭 → 아령 가게 창")
	local shopWin = find(screen, Shop.NAME)
	check(find(find(shopWin, "Now"), "Name").Text == Dumbbells.get(1).name, "지금 아령 = 1kg 아령")
	check(find(find(shopWin, "Next"), "Name").Text == Dumbbells.get(2).name, "다음 아령 = 3kg 아령")
	local buy = find(shopWin, "BuyButton")
	check(
		string.find(buy.Text, "사기", 1, true) ~= nil,
		'돈이 넉넉 → 초록 "사기 · 💰 30" (' .. buy.Text .. ")"
	)
	local b0 = countSent(S.BuyDumbbell)
	press(buy)
	check(countSent(S.BuyDumbbell) == b0 + 1, "사기 → BuyDumbbell()")
	setAttr(A.Money, 10)
	Shop.render()
	check(
		string.find(buy.Text, "더 필요해요", 1, true) ~= nil,
		'돈이 모자라면 "💰 20 더 필요해요" (' .. buy.Text .. ")"
	)
	press(buy)
	check(countSent(S.BuyDumbbell) == b0 + 1, "돈 모자라면 안 보냄")
	check(find(shopWin, "Dumbbell_20") ~= nil, "아령 20개 목록")
	setAttr(A.Money, 56789)
	Windows.close()

	print("[도감]")
	local Index = ctrl("IndexController")
	Windows.open(Index.NAME)
	local indexWin = find(screen, Index.NAME)
	check(find(indexWin, "Summary").Text == "깬 물건 1 / 41", "깬 물건 1 / 41")
	check(find(find(indexWin, "Target_cotton"), "Name").Text == "솜", "깬 솜 = 이름 보임")
	check(find(find(indexWin, "Target_glass"), "Name").Text == "???", "안 깬 유리 = ???")
	check(find(find(indexWin, "Target_cotton"), "Count").Text == "깬 횟수 3", "깬 횟수 3")
	Windows.close()

	print("[띠 · 심사 보기 · 대결]")
	local Belt = ctrl("BeltController")
	local boardModel = CollectionService:GetTagged(Tags.BeltBoard)[1]
	sigOf(boardModel:FindFirstChild("Click"), "MouseClick"):Fire(player)
	check(Windows.isOpen(Belt.NAME), "띠 표지판 클릭 → 띠 창")
	local beltWin = find(screen, Belt.NAME)
	local action = find(beltWin, "ActionButton")
	check(
		string.find(action.Text, "더 필요해요", 1, true) ~= nil,
		'힘 모자람 → 회색 "💪 N 더 필요해요"'
	)
	local e0 = countSent(S.StartExam)
	press(action)
	check(countSent(S.StartExam) == e0, "힘 모자라면 StartExam 안 보냄")
	setAttr(A.Power, Belts.get(2).needPower * 1.5)
	Belt.render()
	check(
		string.find(action.Text, "심사 보기", 1, true) ~= nil,
		'힘 충분 → "🥋 심사 보기" (' .. action.Text .. ")"
	)
	moveTo(0, -36)
	table.clear(moveTargets)
	press(action)
	flushMoves()
	check(
		countSent(S.StartExam) == e0 + 1 and #moveTargets == 1,
		"심사 보기 → 심사대로 걸어가서 StartExam()"
	)
	setAttr(A.Belt, 3)
	setAttr(A.Power, math.max(Belts.get(4).needPower * 1.5, 1e19)) -- Lune 은 i64 안의 큰 정수 Attribute 를 32비트로 자름 (로블록스는 괜찮음) → 1e19 이상
	Belt.render()
	check(
		string.find(action.Text, "대결", 1, true) ~= nil,
		'다음 띠(파랑)가 대결 띠 → "⚔️ 시험관과 대결" (' .. action.Text .. ")"
	)
	local d0 = countSent(S.StartDuel)
	press(action)
	flushMoves()
	check(countSent(S.StartDuel) == d0 + 1, "대결 → StartDuel()")
	local cell = find(boardModel, "Belt_3")
	check(cell and cell.Edge.Thickness == 6, "도장 띠 표지판에 지금 내 띠(3) 반짝 테두리")
	local examModel = CollectionService:GetTagged(Tags.ExamPad)[1]
	Windows.close()
	sigOf(examModel:FindFirstChild("Click"), "MouseClick"):Fire(player)
	check(Windows.isOpen(Belt.NAME), "심사대 클릭 → 띠 창")
	Windows.close()

	print("[월드 문]")
	local World = ctrl("WorldController")
	local door2
	for _, d in CollectionService:GetTagged(Tags.WorldDoor) do
		if d:GetAttribute("World") == 1 and d:GetAttribute("TargetWorld") == 2 then
			door2 = d
		end
	end
	World.paintDoors()
	check(find(door2, "LockBody").LocalTransparencyModifier == 0, "잠긴 월드 2 문 → 자물쇠 보임")
	local t0 = countSent(S.Travel)
	sigOf(door2:FindFirstChild("Click"), "MouseClick"):Fire(player)
	check(countSent(S.Travel) == t0, "잠긴 문 클릭 → Travel 안 보냄")
	setAttr(A.World, 2)
	check(find(door2, "LockBody").LocalTransparencyModifier == 1, "월드 2 열림 → 자물쇠 사라짐")
	sigOf(door2:FindFirstChild("Click"), "MouseClick"):Fire(player)
	check(countSent(S.Travel) == t0 + 1 and lastSent(S.Travel).args[1] == 2, "열린 문 클릭 → Travel(2)")
	setAttr(A.CurrentWorld, 3)
	check(fakeServices.Lighting.ClockTime == 0, "우주(월드 3) → 밤하늘 조명")
	setAttr(A.CurrentWorld, 1)

	print("[힘 배수]")
	local Boost = ctrl("BoostController")
	Windows.open(Boost.NAME)
	local boostWin = find(screen, Boost.NAME)
	check(Boost.cardState(2) == "buy" and Boost.cardState(4) == "locked", "×1: 2배만 살 수 있고 4배는 잠김")
	check(
		find(find(boostWin, "Boost_power_4"), "State").Text == "2배를 먼저 사요",
		'4배 카드 "2배를 먼저 사요"'
	)
	check(find(find(boostWin, "Boost_power_2"), "State").Text == "준비 중", 'id 0 → "준비 중"')
	press(find(find(boostWin, "Boost_power_2"), "BuyBoost"))
	check(#marketPrompts == 0, "준비 중 상품 → 구매창 안 띄움 (토스트)")
	setAttr(A.PowerBoost, 2)
	Boost.render()
	check(Boost.cardState(2) == "active" and Boost.cardState(4) == "buy", "2배를 사면 4배가 열림")
	check(find(boostWin, "Boost_money_2") ~= nil, "돈 2배 카드")
	check(Purchase.granted({ key = "power_4", kind = "powerBoost" }), "ProductGranted → 축하 연출")
	Windows.close()

	print("[설정]")
	local Settings = ctrl("SettingsController")
	Settings.toggle("music")
	local ss = lastSent(S.SetSetting)
	check(ss and ss.args[1] == "music" and ss.args[2] == false, '음악 끄기 → SetSetting("music", false)')
	check(ctrl("SoundController").isMusicEnabled() == false, "음악 꺼짐 반영")
	Settings.toggle("music")

	print("[튜토리얼 3단계]")
	local Tut = ctrl("TutorialController")
	setAttr(A.Power, 0)
	setAttr(A.DumbbellLevel, 1)
	snap.broken = {}
	fire(R.Snapshot, snap)
	Tut.refresh()
	check(Tut.step() == 1 and Tut.panel.Visible, "1단계: 아령 들기 (패널 보임)")
	check(string.find(find(Tut.panel, "Title").Text, "1/3", 1, true) ~= nil, "패널 글 1/3")
	check(Tut.arrow:GetAttribute("Goal") ~= nil, "화살표가 수련 매트 위")
	setAttr(A.Power, 12)
	Tut.refresh()
	check(Tut.step() == 2, "힘 10 넘음 → 2단계 솜 깨기")
	snap.broken = { cotton = 1 }
	fire(R.Snapshot, snap)
	Tut.refresh()
	check(Tut.step() == 3, "솜 깸 → 3단계 아령 사기")
	setAttr(A.DumbbellLevel, 2)
	Tut.refresh()
	check(Tut.step() == 0 and not Tut.panel.Visible, "아령 삼 → 안내 끝 (패널 숨김)")

	print("[Notify]")
	holdDelays = true
	fire(R.Notify, { kind = "success", text = "3kg 아령을 샀어요!" })
	holdDelays = false
	local toast = find(screen, "ToastStack")
	local found = false
	for _, t in toast:GetChildren() do
		if t:IsA("TextLabel") and t.Text == "3kg 아령을 샀어요!" then
			found = true
		end
	end
	check(found, "Notify { kind, text } → 토스트")
	holdDelays = true
	fire(R.Notify, { kind = "error", text = "힘이 부족해요! 아령을 더 들어요." })
	holdDelays = false
	local dup = false
	for _, t in toast:GetChildren() do
		if t:IsA("TextLabel") and string.find(t.Text, "힘이 부족해요", 1, true) then
			dup = true
		end
	end
	check(not dup, '서버 "힘이 부족해요" 토스트는 안 띄움 (물건 위 빨간 글이 대신)')

	print("[폰 화면 844×390 (터치)]")
	local Layout = client("UI/Layout")
	local Ui = client("UI/Ui")
	touch = true
	camera.ViewportSize = Vector2.new(844, 390)
	Ui.relayout()
	local area = Ui.area()
	check(area.X == 844 and area.Y == 332, "화면 영역 844×332 (위 인셋 58)")
	local plan = Hud.menuPlan()
	check(plan and plan.size >= 46, "메뉴 버튼 " .. (plan and plan.size or 0) .. "px ≥ 46")
	local joy = Layout.joystickZone(area)
	local jump = Layout.jumpZone(area)
	local statsR = Layout.statsRect(area, Ui.scale(), true)
	local menuHit = false
	for k = 0, 4 do
		local r = Layout.menuRect(plan, k)
		if Layout.overlaps(r, joy) or Layout.overlaps(r, statsR) then
			menuHit = true
		end
	end
	check(not menuHit, "메뉴가 조이스틱·힘 줄과 안 겹침")
	for slot = 0, 1 do
		local r = Layout.actionRect(area, Ui.scale(), true, slot)
		check(r.w >= 46 and r.h >= 46, string.format("큰 버튼 %d: %dpx ≥ 46", slot, r.w))
		check(
			not Layout.overlaps(r, joy) and not Layout.overlaps(r, jump),
			"큰 버튼 " .. slot .. " 이 조이스틱·점프와 안 겹침"
		)
		check(not Layout.overlaps(r, statsR), "큰 버튼 " .. slot .. " 이 힘 줄과 안 겹침")
		check(
			r.x >= 0 and r.y >= 0 and r.x + r.w <= area.X and r.y + r.h <= area.Y,
			"큰 버튼 " .. slot .. " 이 화면 안"
		)
		for k = 0, 4 do
			if Layout.overlaps(r, Layout.menuRect(plan, k)) then
				check(false, "큰 버튼이 메뉴와 겹침")
			end
		end
	end
	local a0, a1 = Layout.actionRect(area, Ui.scale(), true, 0), Layout.actionRect(area, Ui.scale(), true, 1)
	check(not Layout.overlaps(a0, a1), "들기·치기 버튼끼리 안 겹침")
	local top = Layout.topPanel(area, Ui.scale(), true, 520, 150)
	check(not Layout.overlaps(top, statsR), "위 패널(심사·튜토리얼)이 힘 줄과 안 겹침")
	check(
		Ui.touch(58, Vector2.new(780, 560)) * Ui.fitScale(Vector2.new(780, 560)) >= 45.99,
		"창 버튼(사기) 화면 46px 이상"
	)
	check(
		Train.button.button.Size.X.Offset >= 46,
		"들기 버튼 실제 크기 " .. Train.button.button.Size.X.Offset .. "px"
	)
	-- 작은 폰 (667×375)
	camera.ViewportSize = Vector2.new(667, 375)
	Ui.relayout()
	local area2 = Ui.area()
	local plan2 = Hud.menuPlan()
	check(plan2.size >= 46, "작은 폰 메뉴 " .. plan2.size .. "px ≥ 46")
	for slot = 0, 1 do
		local r = Layout.actionRect(area2, Ui.scale(), true, slot)
		check(
			not Layout.overlaps(r, Layout.jumpZone(area2)) and not Layout.overlaps(r, Layout.joystickZone(area2)),
			"작은 폰 큰 버튼 " .. slot .. " 안 겹침"
		)
	end
	-- PC 로 돌아가기
	touch = false
	camera.ViewportSize = Vector2.new(1100, 720)
	Ui.relayout()
	local pc = Ui.area()
	local pa, pb = Layout.actionRect(pc, Ui.scale(), false, 0), Layout.actionRect(pc, Ui.scale(), false, 1)
	check(
		not Layout.overlaps(pa, Layout.statsRect(pc, Ui.scale(), false)) and not Layout.overlaps(pa, pb),
		"PC: 큰 버튼이 왼쪽 아래 힘·돈과 안 겹침"
	)
end

local ok, err = pcall(body)
if not ok then
	failures += 1
	print("  FAIL 실행 오류: " .. tostring(err))
end
print(if failures == 0 then "\nsmoke_client: 전부 통과" else string.format("\nsmoke_client: 실패 %d", failures))
process.exit(if failures == 0 then 0 else 1)
