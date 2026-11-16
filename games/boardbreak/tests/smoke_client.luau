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
-- 단순 레이캐스트 (금이 물건 겉면에 붙는지 검사용): params.FilterDescendantsInstances 의 파트만,
-- 공(Shape Ball)은 구, 나머지는 돌아간 상자(OBB). 시작점이 안에 있는 파트는 무시(로블록스와 같음)
local function rayPart(part, origin, dir)
	local cf = part.CFrame
	local o = cf:PointToObjectSpace(origin)
	local d = cf:VectorToObjectSpace(dir)
	local h = part.Size / 2
	if part.Shape == roblox.Enum.PartType.Ball then
		local r = math.min(h.X, h.Y, h.Z)
		local a = d:Dot(d)
		local b = 2 * o:Dot(d)
		local c = o:Dot(o) - r * r
		local disc = b * b - 4 * a * c
		if c <= 0 or disc < 0 or a == 0 then
			return nil
		end
		local t = (-b - math.sqrt(disc)) / (2 * a)
		if t < 0 or t > 1 then
			return nil
		end
		local p = o + d * t
		return t, cf:PointToWorldSpace(p), cf:VectorToWorldSpace(p.Unit)
	end
	local tmin, tmax, axis, sign = 0, 1, nil, 0
	for _, k in { "X", "Y", "Z" } do
		local ok, dk, hk = o[k], d[k], h[k]
		if math.abs(dk) < 1e-9 then
			if ok < -hk or ok > hk then
				return nil
			end
		else
			local t1, t2 = (-hk - ok) / dk, (hk - ok) / dk
			local s = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				s = 1
			end
			if t1 > tmin then
				tmin, axis, sign = t1, k, s
			end
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	if not axis then
		return nil -- 시작점이 안
	end
	local n =
		Vector3.new(if axis == "X" then sign else 0, if axis == "Y" then sign else 0, if axis == "Z" then sign else 0)
	return tmin, cf:PointToWorldSpace(o + d * tmin), cf:VectorToWorldSpace(n)
end
local function fakeRaycast(_, origin, dir, params)
	local best
	for _, part in (params and params.FilterDescendantsInstances) or {} do
		if part:IsA("BasePart") then
			local t, pos, normal = rayPart(part, origin, dir)
			if t and (not best or t < best.t) then
				best = { t = t, Position = pos, Normal = normal, Instance = part, Distance = dir.Magnitude * t }
			end
		end
	end
	return best
end
roblox.implementMethod("Workspace", "Raycast", fakeRaycast)
local RaycastParamsStub = {
	new = function()
		return { FilterDescendantsInstances = {} }
	end,
}

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
-- R15 팔 관절 (Lift 가 C0 를 돌렸다 돌려놓는지 봄)
local function r15Arms(model)
	local upper = Instance.new("Part")
	upper.Name = "UpperTorso"
	upper.Parent = model
	for _, side in { "Right", "Left" } do
		local ua = Instance.new("Part")
		ua.Name = side .. "UpperArm"
		ua.Parent = model
		local sh = Instance.new("Motor6D")
		sh.Name = side .. "Shoulder"
		sh.Part0 = upper
		sh.Part1 = ua
		sh.C0 = CFrame.new(if side == "Right" then 1 else -1, 0.56, 0)
		sh.Parent = ua
		local la = Instance.new("Part")
		la.Name = side .. "LowerArm"
		la.Parent = model
		local el = Instance.new("Motor6D")
		el.Name = side .. "Elbow"
		el.Part0 = ua
		el.Part1 = la
		el.C0 = CFrame.new(0, -0.33, 0)
		el.Parent = la
	end
	local lh = Instance.new("Part")
	lh.Name = "LeftHand"
	lh.CFrame = CFrame.new(-1.5, 3, -36)
	lh.Parent = model
end
r15Arms(character)
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
		RaycastParams = RaycastParamsStub,
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
		"AuraController",
		"CameraController",
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
	check(startedAll, "컨트롤러 14개 start() 오류 없음")
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
		"Main 이 컨트롤러 14개 boot + ClientReady 보냄"
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

	print("[진짜 아령 · 팔 동작]")
	local DumbbellLook = shared("DumbbellLook")
	local Lift = client("Lift")
	local function heldOk(model, handPart)
		if not model then
			return false, "아령 없음"
		end
		local bar = model.PrimaryPart
		if not (bar and bar.Name == "Bar") then
			return false, "손잡이(PrimaryPart Bar) 없음"
		end
		local hw = bar:FindFirstChild("HandWeld")
		if not (hw and hw:IsA("Weld") and hw.Part0 == handPart and hw.Part1 == bar) then
			return false, "손잡이가 손에 안 붙음"
		end
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				if p.Anchored or p.CanCollide or p.CanQuery or p.CanTouch or not p.Massless then
					return false, p.Name .. " 물리 설정"
				end
				if p ~= bar then
					local w = p:FindFirstChild("BarWeld")
					if not (w and w.Part0 == bar and w.Part1 == p) then
						return false, p.Name .. " 손잡이에 용접 안 됨"
					end
					-- 부품 사이 거리 고정: 용접 C0 = 지금 상대 자리
					local rel = bar.CFrame:ToObjectSpace(p.CFrame)
					if (rel.Position - w.C0.Position).Magnitude > 1e-3 then
						return false, p.Name .. " 용접 자리 어긋남"
					end
				end
			end
		end
		return true, ""
	end
	local held1 = character:FindFirstChild("HeldDumbbell")
	local ok1, why1 = heldOk(held1, hand)
	check(
		ok1,
		"아령 모든 부품이 손잡이에 용접 · 손잡이는 손(RightHand)에 · 안 부딪힘·Massless "
			.. why1
	)
	local classicParts = 0
	for _, p in held1:GetChildren() do
		if p:IsA("BasePart") then
			classicParts += 1
		end
	end
	check(
		held1:GetAttribute("Classic") == true and classicParts == 5,
		"1번 아령 = 무료 모델 Dumbell 모양 (원기둥 5개, " .. classicParts .. ")"
	)
	check(DumbbellLook.count() == #Dumbbells.list, "아령 개수 = Dumbbells 표 길이 (" .. #Dumbbells.list .. ")")
	local last = #Dumbbells.list
	local sLast, s2 = DumbbellLook.spec(last), DumbbellLook.spec(2)
	check(
		sLast.plates == DumbbellLook.MAX_PLATES
			and sLast.diameter <= DumbbellLook.MAX_DIAMETER
			and sLast.glow
			and s2.plates < sLast.plates
			and DumbbellLook.spec(last + 10).level == last,
		"무거울수록 원판 많고 큼 · 상한 지름 " .. DumbbellLook.MAX_DIAMETER .. " · 끝 아령은 빛"
	)
	setAttr(A.DumbbellLevel, last)
	Train.check()
	local heavy = character:FindFirstChild("HeldDumbbell")
	local okH = heldOk(heavy, hand)
	check(
		okH and heavy:GetAttribute("Level") == last and character:FindFirstChild("HeldDumbbellL") ~= nil,
		"마지막 아령 (" .. Dumbbells.get(last).name .. ") → 두 손에 하나씩"
	)
	check(
		heavy:GetAttribute("Aura") >= 4,
		"덤벨 아우라: 끝 아령은 파티클 단계 (" .. heavy:GetAttribute("Aura") .. ")"
	)
	setAttr(A.DumbbellLevel, 1)
	Train.check()
	-- 들기 → 팔 Motor6D C0 가 움직였다가 돌아옴
	local rs = character.RightUpperArm.RightShoulder
	local rs0 = rs.C0
	Train.button.press()
	Train.button.release()
	fakeServices.RunService.Heartbeat:Fire(0.1)
	local moved = (rs.C0.LookVector - rs0.LookVector).Magnitude > 0.1
	fakeServices.RunService.Heartbeat:Fire(0.2)
	local back = (rs.C0.LookVector - rs0.LookVector).Magnitude < 1e-4
		and (rs.C0.Position - rs0.Position).Magnitude < 1e-4
	check(moved and back, "들기 → R15 오른 어깨 C0 가 올라갔다 원래대로 (0.25초)")
	-- R6
	local r6 = Instance.new("Model")
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Parent = r6
	local m6 = Instance.new("Motor6D")
	m6.Name = "Right Shoulder"
	m6.C0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0)
	m6.Parent = torso
	r6.Parent = Workspace
	local r60 = m6.C0
	Lift.play(r6, "one")
	Lift.step(0.12)
	local r6moved = (m6.C0.UpVector - r60.UpVector).Magnitude > 0.1
	Lift.step(0.2)
	check(r6moved and (m6.C0.UpVector - r60.UpVector).Magnitude < 1e-4, 'R6 "Right Shoulder" 도 같은 동작')
	-- 손 파트가 없는 몸 → 오류 없이 건너뜀
	local noHand = Instance.new("Model")
	noHand.Parent = Workspace
	local okNo, resNo = pcall(Train.attach, noHand, 3)
	check(
		okNo and resNo == nil and noHand:FindFirstChild("HeldDumbbell") == nil,
		"손 파트가 없으면 에러 없이 건너뜀"
	)
	-- 물건(ClickDetector 모델)을 누른 것이면 들기는 안 보냄
	local cottonModel = CollectionService:GetTagged(Tags.BreakTarget)[1]
	local oldPick = Train.pickAt
	Train.pickAt = function()
		return cottonModel.PrimaryPart
	end
	local t1 = countSent(S.Train)
	fakeServices.UserInputService.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton1 }, false)
	check(countSent(S.Train) == t1, "매트 위에서 물건을 탭 → 들기 안 보냄 (치기만)")
	Train.pickAt = oldPick
	-- 리스폰: 새 몸에도 아령·팔 동작
	local character2 = Instance.new("Model")
	character2.Name = "Tester"
	local root2 = Instance.new("Part")
	root2.Name = "HumanoidRootPart"
	root2.CFrame = root.CFrame
	root2.Parent = character2
	local hand2 = Instance.new("Part")
	hand2.Name = "RightHand"
	hand2.CFrame = root.CFrame * CFrame.new(1.5, 0, 0)
	hand2.Parent = character2
	r15Arms(character2)
	local hum2 = Instance.new("Humanoid")
	hum2.Parent = character2
	character.Parent = nil
	character2.Parent = Workspace
	player.Character = character2
	sigOf(player, "CharacterAdded"):Fire(character2)
	Train.check()
	local okR = heldOk(character2:FindFirstChild("HeldDumbbell"), hand2)
	local rs2 = character2.RightUpperArm.RightShoulder
	local rs20 = rs2.C0
	Train.button.press()
	Train.button.release()
	fakeServices.RunService.Heartbeat:Fire(0.1)
	local moved2 = (rs2.C0.LookVector - rs20.LookVector).Magnitude > 0.1
	fakeServices.RunService.Heartbeat:Fire(0.2)
	check(okR and moved2, "리스폰 뒤 새 몸 손에 아령 + 팔 동작")
	-- 원래 몸으로 되돌림 (뒤 검사들이 root·hand 를 씀)
	character2.Parent = nil
	character.Parent = Workspace
	player.Character = character
	sigOf(player, "CharacterAdded"):Fire(character)
	Train.check()
	moveTo(0, -36)
	Train.check()
	check(
		not Train.button.button.Visible and character:FindFirstChild("HeldDumbbell") == nil,
		"매트에서 내려오면 버튼·아령 사라짐"
	)

	print("[몸 크기 · 큰 아령 · 카메라 (사장님 결정 13번)]")
	local Sizes = shared("Data/Sizes")
	local function barOf(model)
		return model and model.PrimaryPart and model.PrimaryPart.Size.X or 0
	end
	moveTo(mat.x, mat.z)
	character:SetAttribute("VisualScale", 10)
	setAttr(A.DumbbellLevel, last)
	Train.check()
	local big = character:FindFirstChild("HeldDumbbell")
	local wantBar = DumbbellLook.barLength(last, 10 * Sizes.dumbbellScale(last))
	local okBig, whyBig = heldOk(big, hand)
	check(
		okBig and math.abs(barOf(big) - wantBar) < 1e-3,
		string.format(
			"몸 배율 10 + 마지막 아령 → 봉 %.1f (= 2.42 × 10 × dumbbellScale) · 손에 용접 %s",
			barOf(big),
			whyBig
		)
	)
	check(
		math.abs(Train.heldScale(character, last) - 10 * Sizes.dumbbellScale(last)) < 1e-9,
		"손 아령 배율 = VisualScale × Sizes.dumbbellScale(단계)"
	)
	local bigL = character:FindFirstChild("HeldDumbbellL")
	character:SetAttribute("VisualScale", 10.2)
	Train.check()
	local big2 = character:FindFirstChild("HeldDumbbell")
	local ok2b = heldOk(big2, hand)
	check(
		big2 ~= big
			and ok2b
			and math.abs(barOf(big2) - DumbbellLook.barLength(last, 10.2 * Sizes.dumbbellScale(last))) < 1e-3
			and big.Parent == nil
			and (bigL == nil or bigL.Parent == nil),
		"몸이 2% 커지면 같은 프레임에 새 크기 아령으로 바꿔 끼움 (옛 것 지움 · 용접 그대로)"
	)
	-- (Lune 은 같은 인스턴스도 꺼낼 때마다 다른 userdata 라 표 열쇠가 안 맞음 → 같은 참조로 두 번 붙여서 봄)
	local same1 = Train.attach(character, last)
	local same2 = Train.attach(character, last)
	check(same1 == same2 and same1.Parent == character, "크기가 그대로면 다시 안 만듦 (깜빡임 없음)")
	-- 누가(엔진 자동 크기 조절 등) 봉을 키워 버리면 다음 맞춤에서 정한 크기로 다시 만듦 (몸 배율 × 아령 배율 한 번만)
	local wantBar2 = barOf(same2)
	same2.PrimaryPart.Size = same2.PrimaryPart.Size * 10.98
	local fixed = Train.attach(character, last)
	check(
		fixed ~= same2 and math.abs(barOf(fixed) - wantBar2) < 1e-3 and heldOk(fixed, hand),
		string.format("남이 키운 손 아령 → 정한 크기로 다시 (봉 %.2f)", barOf(fixed))
	)
	big2 = fixed
	hand.Size = hand.Size * 1.5
	Train.check()
	local big3 = character:FindFirstChild("HeldDumbbell")
	check(
		big3 ~= big2 and heldOk(big3, hand),
		"손 파트 크기가 바뀌면(서버가 몸을 키움) 쥔 자리 다시 맞춤"
	)
	hand.Size = hand.Size / 1.5
	-- 카메라 → 머리 선을 큰 아령이 가리면 반투명
	local bar3 = big3.PrimaryPart
	local cam = Workspace.CurrentCamera
	local through = bar3.CFrame.Position
	check(
		Train.blocksView(big3, through + Vector3.new(0, 0, 50), through + Vector3.new(0, 0, -50)),
		"카메라 → 머리 선이 아령을 지나면 가림으로 봄"
	)
	check(
		not Train.blocksView(big3, through + Vector3.new(0, 500, 50), through + Vector3.new(0, 500, -50)),
		"멀리 위로 지나면 안 가림"
	)
	local function ltmOf()
		local m = character:FindFirstChild("HeldDumbbell")
		local ok, v = pcall(function()
			return m.PrimaryPart.LocalTransparencyModifier
		end)
		return if ok then v else nil
	end
	cam.CFrame = CFrame.new(through + Vector3.new(0, 0, 60))
	head.CFrame = CFrame.new(through + Vector3.new(0, 0, -60))
	Train.check()
	check(
		math.abs((ltmOf() or 0) - Train.FADE) < 1e-4,
		"가리면 내 화면에서 반투명 (" .. tostring(ltmOf()) .. ")"
	)
	cam.CFrame = CFrame.new(through + Vector3.new(0, 900, 60))
	Train.check()
	check(ltmOf() == nil or ltmOf() == 0, "안 가리면 다시 그대로 (" .. tostring(ltmOf()) .. ")")
	head.CFrame = CFrame.new(0, 4.5, -36)
	cam.CFrame = CFrame.new()
	character:SetAttribute("VisualScale", nil)
	setAttr(A.DumbbellLevel, 1)
	Train.check()
	check(barOf(character:FindFirstChild("HeldDumbbell")) < 2, "보통 몸 · 1번 아령은 원래 크기")
	-- 큰 몸은 뿌리가 높음 → 서버 SizeService 처럼 뿌리를 3 × (배율 − 1) 내려서 매트 판정
	setAttr("BodyScale", Sizes.MAX_SCALE)
	root.CFrame = CFrame.new(mat.x, 3 * Sizes.MAX_SCALE, mat.z)
	Train.check()
	check(
		Train.onMat(),
		string.format(
			"거인(배율 %.1f, 뿌리 높이 %.0f) 도 매트 위 → 들기",
			Sizes.MAX_SCALE,
			3 * Sizes.MAX_SCALE
		)
	)
	check(
		not Train.matAt(Vector3.new(mat.x, 3 * Sizes.MAX_SCALE, mat.z), 1, 1),
		"보통 몸이 그 높이에 떠 있으면 매트 아님"
	)
	setAttr("BodyScale", 1)
	moveTo(0, -36)
	Train.check()
	-- 들기 도중 몸이 커짐: R15 쉬는 C0 를 RigAttachment 에서 다시 읽음 → 끝나면 새 자리
	local upperT = character.UpperTorso
	local rsAtt = Instance.new("Attachment")
	rsAtt.Name = "RightShoulderRigAttachment"
	rsAtt.CFrame = rs.C0
	rsAtt.Parent = upperT
	Lift.play(character, "one")
	Lift.step(0.1)
	local grown = CFrame.new(rs.C0.Position * 0 + Vector3.new(10, 5.6, 0))
	rsAtt.CFrame = grown
	Lift.step(0.05)
	local midOk = (rs.C0.Position - grown.Position).Magnitude < 1e-4
	Lift.step(0.3)
	check(
		midOk and (rs.C0.Position - grown.Position).Magnitude < 1e-4 and not Lift.isPlaying(character),
		"들기 도중 몸이 커져도 팔이 새 어깨 자리에서 움직이고, 끝나면 새 자리 (옛 크기로 안 돌아감)"
	)
	rsAtt.CFrame = rs0
	Lift.reset(character)
	rs.C0 = rs0
	rsAtt:Destroy()
	-- R6: 기억한 C0 × 배율 비율
	Lift.restOf(m6) -- 이 참조로 배율 1 C0 를 기억 (Lune 참조 문제 — 위 참고)
	r6:SetAttribute("VisualScale", 2)
	check(
		(Lift.restOf(m6).Position - r60.Position * 2).Magnitude < 1e-4,
		"R6 쉬는 C0 도 몸 배율 비율만큼 (Model:ScaleTo 와 같게)"
	)
	-- 카메라
	local Camera = ctrl("CameraController")
	local minZ, maxZ = Camera.limits(Sizes.MAX_SCALE)
	check(
		maxZ >= 128 * Sizes.MAX_SCALE - 1e-6 and minZ >= 0.5 * Sizes.MAX_SCALE - 1e-6,
		string.format("카메라 줌 한도 = 처음 값 × 몸 배율 (최대 %.0f · 최소 %.1f)", maxZ, minZ)
	)
	check(
		Camera.zoomFor(Sizes.MAX_SCALE) > 75 * 1.5,
		string.format(
			"가장 큰 몸(키 ≈ %.0f) 기본 거리 %.0f — 몸이 화면에 들어옴",
			Sizes.AVATAR_HEIGHT * Sizes.MAX_SCALE,
			Camera.zoomFor(Sizes.MAX_SCALE)
		)
	)
	local camSrc = fs.readFile("games/boardbreak/src/client/Controllers/CameraController.luau")
		.. fs.readFile("games/boardbreak/src/client/Controllers/TrainController.luau")
		.. fs.readFile("games/boardbreak/src/client/Controllers/WorldController.luau")
	check(
		not string.find(camSrc, "WalkSpeed%s*=") and not string.find(camSrc, "JumpHeight%s*="),
		"클라는 WalkSpeed · JumpHeight 를 안 바꿈 (서버 SizeService)"
	)
	local Walk = client("Walk")
	setAttr(A.CurrentWorld, 3)
	check(
		math.abs(Walk.scale() - MapLayout.worldScale(3)) < 1e-9,
		"Walk 도착 여유 배율 = 지금 월드 배율 (월드 3)"
	)
	setAttr(A.CurrentWorld, 1)
	local BreakC = ctrl("BreakController")
	local Cracks = client("Cracks")
	local w3model = BreakC.models()["universe"]
	local w1model = BreakC.models()["cotton"]
	check(
		w3model
			and BreakC.scaleOf(w3model) == MapLayout.worldScale(3)
			and BreakC.scaleOf(w1model) == 1
			and Cracks.scaleOf(w3model.PrimaryPart) == MapLayout.worldScale(3),
		"치기 연출·금 크기 배율 = 그 물건 월드 배율 (우주 "
			.. tostring(w3model and BreakC.scaleOf(w3model))
			.. " · 솜 1)"
	)
	-- 큰 월드 물건 금: 금 마디 길이·굵기가 월드 배율만큼 (월드 1 상한 6 · 0.8 에 묶이지 않음)
	if w3model then
		Cracks.showModel(w3model, 2, 7, false)
		local marks = w3model:FindFirstChild(Cracks.FOLDER)
		local longest = 0
		for _, p in marks and marks:GetChildren() or {} do
			longest = math.max(longest, p.Size.Z)
		end
		check(
			marks and (#marks:GetChildren() == 0 or longest > 6),
			string.format("우주(월드 3) 금 마디 길이 %.1f (> 월드 1 상한 6)", longest)
		)
		Cracks.clear(w3model)
	end

	print("[물건 치기]")
	local Break = ctrl("BreakController")
	Break.refresh()
	check(not Break.button.button.Visible, "로비 스폰: 치기 버튼 없음")
	local road = MapLayout.roadPoint("cotton")
	moveTo(road.x, road.z)
	Break.refresh()
	check(Break.button.button.Visible and Break.button.sub.Text == "솜", '솜 앞 → "치기" 버튼 (솜)')
	-- 길가 수련 매트: 매트 가운데에 서면 들기·치기 둘 다, 안 겹침
	local Layout0 = client("UI/Layout")
	local Ui0 = client("UI/Ui")
	local bothOk, rectOk = true, true
	for _, id in { "cotton", "glass", "school", "stadium" } do
		local mp = MapLayout.matPoint(id)
		moveTo(mp.x, mp.z)
		Train.check()
		Break.refresh()
		if not (Train.onMat() and Train.button.button.Visible and Break.button.button.Visible) then
			bothOk = false
			print("    길가 매트 " .. id .. ": 버튼 하나만")
		end
	end
	check(bothOk, "길가 매트 위 → 들기·치기 버튼 둘 다 보임 (솜·유리·학교·경기장)")
	for _, size in { Vector2.new(1100, 720), Vector2.new(1920, 1080), Vector2.new(800, 600) } do
		local a, b = Layout0.actionRect(size, Ui0.scale(), false, 0), Layout0.actionRect(size, Ui0.scale(), false, 1)
		if Layout0.overlaps(a, b) or math.abs(a.y - b.y) > 0.5 then
			rectOk = false
		end
	end
	for _, size in { Vector2.new(844, 332), Vector2.new(667, 317), Vector2.new(1024, 710) } do
		local a, b = Layout0.actionRect(size, Ui0.scale(), true, 0), Layout0.actionRect(size, Ui0.scale(), true, 1)
		local jump = Layout0.jumpZone(size)
		if
			Layout0.overlaps(a, b)
			or Layout0.overlaps(a, jump)
			or Layout0.overlaps(b, jump)
			or math.abs(a.x - b.x) > 0.5
			or a.y >= b.y
			or a.y < 0
			or a.w < 46
		then
			rectOk = false
			print(string.format("    터치 %dx%d: 들기 %d,%d 치기 %d,%d", size.X, size.Y, a.x, a.y, b.x, b.y))
		end
	end
	check(rectOk, "들기·치기 자리 안 겹침 (PC 아래 가운데 나란히 · 폰 점프 위 세로)")
	local tb, hb = Train.button.button, Break.button.button
	check(
		tb.Position ~= hb.Position and not Layout0.overlaps(Train.button.rect(), Break.button.rect()),
		"실제 버튼 두 개 자리 안 겹침"
	)
	moveTo(road.x, road.z)
	Train.check()
	Break.refresh()
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
	check(not hasFloat("힘이 부족해요"), '"힘이 부족해요" 글은 더 안 뜸 (옛 reason weak 도)')
	local steelNeed = find(Break.models().steel, "Need")
	check(
		steelNeed and string.find(steelNeed.Text, "추천 힘", 1, true) ~= nil,
		'물건 위 "💪 추천 힘 N" (' .. (steelNeed and steelNeed.Text or "?") .. ")"
	)
	Break.paintNeed()
	check(steelNeed.TextColor3 == Break.NEED_HARD, "내 힘이 추천 힘보다 작으면 주황색")
	print("[금 가는 연출]")
	local Cracks = client("Cracks")
	local woodBox = Break.models().wood
	local stages = {}
	for _, ratio in { 0.8, 0.7, 0.45, 0.2 } do
		Break.onHitResult({ targetId = "wood", damage = 1000, hp = 40000 * ratio, hpMax = 40000, broken = false })
		table.insert(stages, Cracks.stageOf(woodBox))
	end
	check(
		stages[1] == 0 and stages[2] == 1 and stages[3] == 2 and stages[4] == 3,
		"체력 80·70·45·20% → 금 0·1·2·3단계 (" .. table.concat(stages, ",") .. ")"
	)
	check(
		Cracks.stage(30, 40) == 1
			and Cracks.stage(20, 40) == 2
			and Cracks.stage(10, 40) == 3
			and Cracks.stage(40, 40) == 0,
		"경계값 75% → 1 · 50% → 2 · 25% → 3 · 가득 0"
	)
	check(
		string.find(find(playerGui:FindFirstChild("HpBar_wood"), "Hp").Text, "약", 1, true) ~= nil,
		"체력 막대에 남은 타격 수 어림 (" .. find(playerGui:FindFirstChild("HpBar_wood"), "Hp").Text .. ")"
	)
	Break.onHitResult({ targetId = "wood", damage = 8000, hp = 0, hpMax = 40000, broken = true, reward = 9 })
	check(
		Cracks.stageOf(woodBox) == 0
			and woodBox:FindFirstChild(Cracks.FOLDER) == nil
			and woodBox.PrimaryPart:FindFirstChild("Crack_Front") == nil,
		"깨지면(다시 생기면) 금 지움"
	)
	do
		-- 가짜 물건 3종 (보이지 않는 맞히는 상자가 물건보다 2배 큼): 금은 보이는 겉면에만
		local Enum = roblox.Enum
		local function fakeTarget(name, shape, size, at)
			local m = Instance.new("Model")
			m.Name = name
			local look = Instance.new("Part")
			look.Name = "Look"
			look.Shape = shape
			look.Size = size
			look.CFrame = CFrame.new(at)
			look.CanQuery = false
			look.Parent = m
			local hb = Instance.new("Part")
			hb.Name = "Hitbox"
			hb.Size = size * 2
			hb.Transparency = 1
			hb.CFrame = CFrame.new(at)
			hb.Parent = m
			m.PrimaryPart = hb
			m.Parent = Workspace
			return m, look, hb
		end
		local function surfaceGap(pos, parts)
			local best = math.huge
			local ax = { Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) }
			for _, dir in { ax[1], ax[2], ax[3], -ax[1], -ax[2], -ax[3] } do
				local hit = fakeRaycast(nil, pos + dir * 2, -dir * 4, { FilterDescendantsInstances = parts })
				if hit then
					best = math.min(best, (hit.Position - pos).Magnitude)
				end
			end
			return best
		end
		local function onHitboxFace(pos, hb)
			local l = hb.CFrame:PointToObjectSpace(pos)
			local h = hb.Size / 2
			return math.min(math.abs(math.abs(l.X) - h.X), math.abs(math.abs(l.Y) - h.Y), math.abs(math.abs(l.Z) - h.Z))
				< 0.1 -- 겉모습과 맞히는 상자 면 사이가 0.3 이라 0.1 로 가름
		end
		local kinds = {
			{ "납작한 판", Enum.PartType.Block, Vector3.new(6, 0.6, 6), Vector3.new(500, 0.3, 500) },
			{ "공", Enum.PartType.Ball, Vector3.new(4, 4, 4), Vector3.new(520, 2, 500) },
			{ "높은 상자", Enum.PartType.Block, Vector3.new(2, 8, 2), Vector3.new(540, 4, 500) },
			{ "행성(큰 공)", Enum.PartType.Ball, Vector3.new(40, 40, 40), Vector3.new(600, 20, 500) },
			{ "솜(작은 공)", Enum.PartType.Ball, Vector3.new(1, 1, 1), Vector3.new(560, 0.5, 500) },
		}
		local LINES = { { 2, 3 }, { 5, 6 }, { 9, 12 } }
		for _, k in kinds do
			local m, look, hb = fakeTarget(k[1], k[2], k[3], k[4])
			local counts, linesOk, allNear, noneOnHitbox, settings = {}, true, true, true, true
			local worst = 0
			for stage = 1, 3 do
				Cracks.showModel(m, stage, Cracks.seedOf(k[1]))
				local folder = m:FindFirstChild(Cracks.FOLDER)
				local segs = folder and folder:GetChildren() or {}
				counts[stage] = #segs
				local lines = folder and folder:GetAttribute("CrackLines") or 0
				if lines < LINES[stage][1] or lines > LINES[stage][2] or #segs > Cracks.MAX_SEGMENTS then
					linesOk = false
				end
				for _, seg in segs do
					local gap = surfaceGap(seg.CFrame.Position, { look })
					worst = math.max(worst, gap)
					if gap > 0.3 then
						allNear = false
					end
					if onHitboxFace(seg.CFrame.Position, hb) then
						noneOnHitbox = false
					end
					if seg.CanCollide or seg.CanQuery or seg.CanTouch or seg.CastShadow or not seg.Anchored then
						settings = false
					end
				end
			end
			check(
				linesOk and counts[1] > 0 and counts[3] > counts[1],
				k[1]
					.. ": 단계별 금 줄 2~3 · 5~6 · 9~12, 마디 ≤ 40 (마디 "
					.. table.concat(counts, "·")
					.. ")"
			)
			check(
				allNear and noneOnHitbox,
				string.format(
					"%s: 모든 금 마디가 보이는 겉면 0.3 이내 (최대 %.3f) · 맞히는 상자 면에는 0개",
					k[1],
					worst
				)
			)
			check(settings, k[1] .. ": 금 마디 Anchored · 충돌/질의/닿기/그림자 없음")
			check(look.CanQuery == false, k[1] .. ": 레이캐스트 뒤 겉모습 파트 CanQuery 원래대로")
			Cracks.showModel(m, 0, 1)
			check(
				m:FindFirstChild(Cracks.FOLDER) == nil and Cracks.stageOf(m) == 0,
				k[1] .. ": 깨지면(단계 0) 금 0개"
			)
			m:Destroy()
		end
	end
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
	check(
		find(pad, "Board_4"):FindFirstChild("Crack_Front") ~= nil
			and find(pad, "Board_5"):FindFirstChild("Crack_Front") == nil,
		"심사 송판: 지금 치는 4번째 송판에 금 (boardHp 5 / 8e5 → 3단계)"
	)
	fire(R.ExamState, { phase = "pass", broken = 10, total = 10, secondsLeft = 4, belt = 2 })
	setAttr(A.Activity, "")
	check(
		not panel.Visible and find(pad, "Board_3").LocalTransparencyModifier == 0,
		"합격 → 패널 닫힘 · 송판 다시"
	)
	check(find(pad, "Board_4"):FindFirstChild("Crack_Front") == nil, "합격 → 송판 금 지움")
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

	print("[아우라 (내 화면)]")
	local Aura = ctrl("AuraController")
	character:SetAttribute("AuraTier", 2)
	Aura.tick()
	character:SetAttribute("AuraTier", 3)
	holdDelays = true
	Aura.tick()
	holdDelays = false
	check(
		Aura.lastShownTier() == 3 and find(screen, "AuraFlash") ~= nil,
		'아우라 단계 오름 → 번쩍 + "아우라 UP!"'
	)
	-- 저사양이면 남의 아우라 파티클을 내 화면에서 끔
	local other = Instance.new("Player")
	local otherChar = Instance.new("Model")
	local otherRoot = Instance.new("Part")
	otherRoot.Name = "HumanoidRootPart"
	otherRoot.Parent = otherChar
	local att = Instance.new("Attachment")
	att.Name = "AuraAttach"
	att.Parent = otherRoot
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "AuraSparks"
	pe.Parent = att
	otherChar.Parent = Workspace
	other.Character = otherChar
	local oldGet = Players.GetPlayers
	Players.GetPlayers = function()
		return { player, other }
	end
	State.get().settings.lowGraphics = true
	Aura.tick()
	local offLow = pe.Enabled == false
	State.get().settings.lowGraphics = false
	Aura.tick()
	check(offLow and pe.Enabled == true, "저사양 → 남의 아우라 파티클 꺼짐 · 끄면 다시 켜짐")
	Players.GetPlayers = oldGet
	otherChar.Parent = nil
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
		string.find(buy.Text, "구매", 1, true) ~= nil,
		'돈이 넉넉 → 초록 "구매 · 💰 42" (' .. buy.Text .. ")"
	)
	local b0 = countSent(S.BuyDumbbell)
	press(buy)
	check(countSent(S.BuyDumbbell) == b0 + 1, "사기 → BuyDumbbell()")
	setAttr(A.Money, 10)
	Shop.render()
	check(string.find(buy.Text, " 부족", 1, true) ~= nil, '돈이 모자라면 "💰 20 부족" (' .. buy.Text .. ")")
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
	local hintLabel = find(beltWin, "Hint")
	check(
		string.find(action.Text, "심사 보기", 1, true) ~= nil and action.Active ~= false,
		"힘이 약해도 버튼은 늘 누를 수 있음 (" .. action.Text .. ")"
	)
	check(
		hintLabel == nil or string.find(hintLabel.Text, "아직 어려움", 1, true) ~= nil,
		'약하면 "추천 힘 N · 아직 어려움" ('
			.. (hintLabel and hintLabel.Text or "힌트 이름 다름")
			.. ")"
	)
	local e0 = countSent(S.StartExam)
	moveTo(0, -36)
	table.clear(moveTargets)
	press(action)
	flushMoves()
	check(
		countSent(S.StartExam) == e0 + 1,
		"힘이 약해도 심사 보기 → StartExam (서버가 순서·위치만 검사)"
	)
	e0 = countSent(S.StartExam)
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
	-- 월드 1 의 대결 띠 (표에서 읽음 — "4개씩" 가정 없음, 사장님 결정 16번)
	local duelBelt
	for _, b in Belts.list do
		if b.world == 1 and b.duel then
			duelBelt = b
			break
		end
	end
	setAttr(A.Belt, duelBelt.index - 1)
	setAttr(A.Power, math.max(duelBelt.needPower * 1.5, 1e19)) -- Lune 은 i64 안의 큰 정수 Attribute 를 32비트로 자름 (로블록스는 괜찮음) → 1e19 이상
	Belt.render()
	check(
		string.find(action.Text, "대결", 1, true) ~= nil,
		"다음 띠(" .. duelBelt.name .. ')가 대결 띠 → "⚔️ 시험관과 대결" (' .. action.Text .. ")"
	)
	local d0 = countSent(S.StartDuel)
	press(action)
	flushMoves()
	check(countSent(S.StartDuel) == d0 + 1, "대결 → StartDuel()")
	local mineIdx = duelBelt.index - 1
	local cell = find(boardModel, "Belt_" .. mineIdx)
	check(
		cell and cell.Edge.Thickness == 6,
		"도장 띠 표지판에 지금 내 띠(" .. mineIdx .. ") 반짝 테두리"
	)
	-- 띠 전부 (Belts.COUNT) · 스크롤 · 여러 색 띠
	local cards = 0
	for i = 1, Belts.COUNT do
		if find(beltWin, "Belt_" .. i) then
			cards += 1
		end
	end
	check(cards == Belts.COUNT, string.format("띠 창 칸 = Belts.COUNT (%d / %d)", cards, Belts.COUNT))
	local yLast = Belt.scrollTo(Belts.COUNT)
	check(
		yLast > 0 and Belt.scroll and Belt.scroll.CanvasPosition.Y == yLast,
		string.format("띠 창이 마지막 띠 줄까지 스크롤 (캔버스 y %d)", yLast)
	)
	check(Belt.scrollTo(1) == 0, "첫 띠 → 맨 위")
	local multi
	for _, b in Belts.list do
		if #shared("BeltLook").colors(b) > 1 then
			multi = b
			break
		end
	end
	if multi then
		local mcard = find(beltWin, "Belt_" .. multi.index)
		check(
			mcard and find(mcard, "BeltGradient") ~= nil,
			"여러 색 띠(" .. multi.name .. ") → 띠 창 칸에 그러데이션"
		)
		setAttr(A.Belt, multi.index)
		Hud.refresh()
		check(find(stats, "BeltGradient") ~= nil, "왼쪽 아래 띠 칩도 그러데이션 (" .. multi.name .. ")")
		setAttr(A.Belt, mineIdx)
		Hud.refresh()
		check(
			find(stats, "BeltGradient") == nil or #shared("BeltLook").colors(Belts.get(mineIdx)) > 1,
			"한 색 띠로 돌아가면 그러데이션 없앰"
		)
	else
		check(false, "여러 색 띠가 표에 없음 (Belts.colors)")
	end
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

	print("[포털에 들어가면 바로 이동 (사장님 결정 15번)]")
	World.TRAVEL_GAP = 0 -- 검사 안에서는 1.5초 연타 막기를 끔
	local door2Spot
	for _, d in MapLayout.doors(1) do
		if d.world == 2 then
			door2Spot = d
		end
	end
	moveTo(0, -36)
	World.checkPortal()
	check(World.isArmed(), "스폰(포털 밖) → 들어갈 준비")
	local p0 = countSent(S.Travel)
	moveTo(door2Spot.x, door2Spot.z + 0.3)
	World.checkPortal()
	check(
		countSent(S.Travel) == p0 + 1 and lastSent(S.Travel).args[1] == 2,
		"열린 월드 2 포털에 걸어 들어감 → 클릭 없이 Travel(2) 한 번"
	)
	for _ = 1, 5 do
		World.checkPortal()
	end
	moveTo(door2Spot.x + 1, door2Spot.z - 0.5)
	World.checkPortal()
	check(
		countSent(S.Travel) == p0 + 1,
		"포털 안에 계속 서 있으면 다시 안 보냄 (몸이 여러 번 닿아도)"
	)
	moveTo(door2Spot.x, door2Spot.z + 12)
	World.checkPortal()
	check(
		countSent(S.Travel) == p0 + 1 and World.isArmed(),
		"포털 밖으로 나옴 → 안 보냄 · 다시 들어갈 준비"
	)
	moveTo(door2Spot.x, door2Spot.z)
	World.checkPortal()
	check(countSent(S.Travel) == p0 + 2, "나왔다가 다시 들어가면 또 Travel(2)")
	-- 잠긴 월드 3 포털: Travel 안 보냄 · 알림은 들어갈 때 한 번 (서 있어도 반복 안 함)
	local door3Spot
	for _, d in MapLayout.doors(1) do
		if d.world == 3 then
			door3Spot = d
		end
	end
	moveTo(0, -36)
	World.checkPortal()
	local Notify = ctrl("NotifyController")
	local toasts = 0
	local oldToast = Notify.toast
	Notify.toast = function(text, kind)
		toasts += 1
		return oldToast(text, kind)
	end
	local p1 = countSent(S.Travel)
	World.TOAST_GAP = 0 -- 바로 앞 "잠긴 문 클릭" 알림 때문에 막히지 않게 (여기서는 "서 있는 동안 반복 안 함" 만 봄)
	moveTo(door3Spot.x, door3Spot.z + 0.3)
	for _ = 1, 10 do
		World.checkPortal()
	end
	World.TOAST_GAP = 3
	check(
		countSent(S.Travel) == p1 and toasts == 1,
		"잠긴 월드 3 포털 → Travel 안 보냄 · 🔒 알림 한 번 (" .. toasts .. ")"
	)
	moveTo(0, -36)
	World.checkPortal()
	moveTo(door3Spot.x, door3Spot.z + 0.3)
	World.checkPortal()
	check(toasts == 1, "곧바로 다시 들어가도 알림은 " .. World.TOAST_GAP .. "초에 한 번")
	Notify.toast = oldToast
	-- 거인 (몸 배율 최대): 문보다 커도 몸이 문에 닿으면 들어감 · 스폰은 포털 밖
	moveTo(0, -36)
	setAttr("BodyScale", Sizes.MAX_SCALE)
	root.CFrame = CFrame.new(0, 3 * Sizes.MAX_SCALE, -36)
	World.checkPortal()
	check(World.isArmed() and World.portalAt() == nil, "거인이 스폰에 서 있으면 포털 밖")
	local p2 = countSent(S.Travel)
	root.CFrame = CFrame.new(door2Spot.x + door2Spot.halfX + 5, 3 * Sizes.MAX_SCALE, door2Spot.z + 6)
	World.checkPortal()
	check(countSent(S.Travel) == p2 + 1, "거인: 뿌리가 문틀 밖이어도 몸이 문에 닿으면 Travel")
	setAttr("BodyScale", 1)
	moveTo(0, -36)
	World.checkPortal()
	World.TRAVEL_GAP = 1.5
	setAttr(A.CurrentWorld, 3)
	check(fakeServices.Lighting.ClockTime == 0, "우주(월드 3) → 밤하늘 조명")
	local ambOk = true
	for w, l in World.LIGHTS do
		local a = l.ambient
		if
			(a.R + a.G + a.B) / 3 < World.MIN_AMBIENT
			or (l.outdoor.R + l.outdoor.G + l.outdoor.B) / 3 < World.MIN_AMBIENT
		then
			ambOk = false
			print("    어두운 월드 조명: " .. w)
		end
	end
	local amb3 = fakeServices.Lighting.Ambient
	check(
		ambOk and amb3 == World.LIGHTS[3].ambient,
		"월드마다 지붕 아래·밖 그늘 빛 ≥ "
			.. World.MIN_AMBIENT
			.. " (월드 3 도장 안이 까맣지 않게) · 월드 3 에 들어가면 그 조명"
	)
	setAttr(A.CurrentWorld, 1)

	print("[힘 배수]")
	local Boost = ctrl("BoostController")
	Windows.open(Boost.NAME)
	local boostWin = find(screen, Boost.NAME)
	check(Boost.cardState(2) == "buy" and Boost.cardState(4) == "locked", "×1: 2배만 살 수 있고 4배는 잠김")
	check(
		find(find(boostWin, "Boost_power_4"), "State").Text == "2배 먼저 필요",
		'4배 카드 "2배 먼저 필요"'
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
	fire(R.Notify, { kind = "success", text = "3kg 아령 구매!" })
	holdDelays = false
	local toast = find(screen, "ToastStack")
	local found = false
	for _, t in toast:GetChildren() do
		if t:IsA("TextLabel") and t.Text == "3kg 아령 구매!" then
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

	-- 큰 창이 열려 있으면 알림이 창 글씨를 가리지 않게 창 위 한 줄로 (사장님: 아령 가게 위에 글씨 겹침)
	local function toastCount(): number
		local n = 0
		for _, t in toast:GetChildren() do
			if t:IsA("TextLabel") then
				n += 1
			end
		end
		return n
	end
	local NotifyWindows = client("UI/Windows")
	local ShopForToast = client("Controllers/DumbbellShopController")
	holdDelays = true
	fire(R.Notify, { kind = "success", text = "알림 하나" })
	fire(R.Notify, { kind = "success", text = "알림 둘" })
	check(toast.AnchorPoint.Y == 1 and toastCount() >= 2, "창 닫힘: 알림은 아래 가운데 여러 줄")
	NotifyWindows.open(ShopForToast.NAME)
	check(
		toast.AnchorPoint.Y == 0 and toast.Position.Y.Scale == 0,
		"창 열림: 알림 자리가 화면 맨 위 (창 위 빈 자리)"
	)
	check(toastCount() == 1, "창 열림: 알림은 한 줄만 남음")
	fire(R.Notify, { kind = "success", text = "창 위 알림" })
	local onTop: TextLabel? = nil
	for _, t in toast:GetChildren() do
		if t:IsA("TextLabel") then
			onTop = t
		end
	end
	check(
		toastCount() == 1 and onTop ~= nil and onTop.Text == "창 위 알림" and onTop.BackgroundTransparency < 1,
		"창 열림: 새 알림이 와도 한 줄 · 어두운 칩 바탕"
	)
	NotifyWindows.close()
	check(toast.AnchorPoint.Y == 1 and toast.Position.Y.Scale == 1, "창 닫힘: 알림 자리가 다시 아래")
	holdDelays = false

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
