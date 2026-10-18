--!nocheck
--[[
	ServerHarness — 서버 서비스(PetService, BaseService, AltarService ...)의 "진짜 코드"를 Lune 에서 돌려 보는 작은 가짜 세상

	왜: 순수 로직(Economy, FusionRules ...)은 이미 테스트가 있지만, 서비스가 그 로직을 올바르게 이어 붙였는지
	    (돈이 빠졌나, 알림이 갔나, 저장 데이터가 바뀌었나, 시간이 지나면 수입이 쌓이나)는 서비스를 실제로 돌려 봐야 압니다.

	무엇을 가짜로 만드나 (로블록스 엔진 부분만):
	  - 가상 시간: task.spawn / task.wait / task.delay 와 os.clock / os.time 을 가짜로 교체.
	      H.advance(초) 를 부르면 그만큼 시간이 흘러 서비스의 1초 루프 등이 실제로 돕니다. (진짜 기다리지 않음)
	  - Instance.new("RemoteEvent") 등 최소한의 가짜 → 진짜 server/Net.luau 가 그대로 올라옴 (레이트 리밋·pcall 포함)
	  - Players / CollectionService / DataStoreService 등 서비스, 가짜 플레이어·캐릭터
	  - 맵(MapBuilder)·알(EggService)·월드 UI(Gui, Landmarks)·주기(CycleService) 서비스는 아래 mockModules 에서 가짜로 교체
	진짜 그대로 쓰는 것: Sessions, Snapshot, Wallet, SpeedService, PetService, IndexService, UpgradeService, RewardService,
	  BaseService, FusionService, AltarService, SakuraService, QuestService, AntiCheatService, DataService, DevCommands, Net ...

	사용:
	  local H = ServerHarness.install(Loader, T)        -- 가짜 세상 켜기 (모듈 캐시를 비움)
	  local player = H.newPlayer(1001, "Tester")
	  local session, data = H.login(player)              -- 세션 + 기본 저장 데이터
	  local PetService = H.server("Services/PetService") -- 진짜 서비스
	  H.advance(10)                                      -- 가상으로 10초
	  H.uninstall()                                      -- 정리 (다른 테스트에 영향 없게)
]]

local ServerHarness = {}

local BASE_CLOCK = 1000 -- os.clock() 가상 시작값 (0 이면 "처음" 판정과 헷갈려서)
local BASE_TIME = 1700000000 -- os.time() 가상 시작값

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

local function newSignal()
	local signal = { handlers = {} }
	function signal:Connect(fn)
		table.insert(self.handlers, fn)
		return {
			Disconnect = function()
				local i = table.find(self.handlers, fn)
				if i then
					table.remove(self.handlers, i)
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, fn in table.clone(self.handlers) do
			fn(...)
		end
	end
	return signal
end

------------------------------------------------------------------
-- 가짜 Vector3 / Color3 / Enum (서비스가 맨 위에서 쓰는 것만)
------------------------------------------------------------------

local V3 = {}
local vec
V3.__index = function(v, key)
	if key == "Unit" then
		local m = v.Magnitude
		return if m == 0 then vec(0, 0, 0) else vec(v.X / m, v.Y / m, v.Z / m)
	end
	return V3[key]
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function vec(x, y, z)
	local v = setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
	v.Magnitude = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	return v
end
V3.__add = function(a, b)
	return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return vec(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return vec(a.X * b, a.Y * b, a.Z * b)
	end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
local Vector3 = { new = vec, zero = vec(0, 0, 0) }

local Color3Meta = {}
Color3Meta.__index = Color3Meta
local function color(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, Color3Meta)
end
function Color3Meta.Lerp(a, b, t)
	return color(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
local Color3 = {
	new = function(r, g, b)
		return color(r or 0, g or 0, b or 0)
	end,
	fromRGB = function(r, g, b)
		return color(r / 255, g / 255, b / 255)
	end,
}

-- CFrame 은 위치(+바라보는 방향)만 흉내 (서비스가 CFrame.new(위치) 로 캐릭터를 옮길 때)
local CFrameMeta = {
	__mul = function(a)
		return a
	end,
}
local function cframeOf(position, look)
	return setmetatable({ Position = position, LookVector = look }, CFrameMeta)
end
local CFrame = {
	new = function(x, y, z)
		if type(x) == "table" then
			return setmetatable({ Position = x, LookVector = vec(0, 0, -1) }, CFrameMeta)
		end
		return setmetatable({ Position = vec(x, y, z), LookVector = vec(0, 0, -1) }, CFrameMeta)
	end,
	Angles = function()
		return setmetatable({}, CFrameMeta)
	end,
	-- 2판: 서버 순간이동이 바라보는 방향을 정할 때 (위치 + 방향만)
	lookAt = function(position, target)
		local d = target - position
		return cframeOf(position, if d.Magnitude > 0 then d.Unit else vec(0, 0, -1))
	end,
}

local function enumProxy()
	return setmetatable({}, {
		__index = function(t, enumName)
			local e = setmetatable({}, {
				__index = function(_, item)
					return enumName .. "." .. item
				end,
			})
			rawset(t, enumName, e)
			return e
		end,
	})
end

------------------------------------------------------------------
-- 설치
------------------------------------------------------------------

-- options.realEgg = true 이면 EggService 를 진짜로 (가짜 대신) 씀 — 알 줍기·놓치기·둥지 테스트용
function ServerHarness.install(Loader, T, options)
	options = options or {}
	Loader.clearFakes()

	local H = {}
	H.warnings = {} -- warn() 로 찍힌 글
	H.created = {} -- Instance.new("RemoteEvent") 로 만들어진 것들

	----------------------------------------------------------------
	-- 가상 시간 + task
	----------------------------------------------------------------
	local now = 0
	local queue = {}
	local seq = 0

	local function resumeThread(co, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			error("[Harness] 예약된 작업에서 오류: " .. tostring(err), 0)
		end
	end
	local function schedule(at, item)
		seq += 1
		item.at = at
		item.seq = seq
		table.insert(queue, item)
	end
	local function toThread(f)
		return if type(f) == "thread" then f else coroutine.create(f)
	end

	local fakeTask = {}
	function fakeTask.spawn(f, ...)
		local co = toThread(f)
		resumeThread(co, ...)
		return co
	end
	function fakeTask.defer(f, ...)
		local co = toThread(f)
		schedule(now, { co = co, args = table.pack(...) })
		return co
	end
	function fakeTask.delay(seconds, f, ...)
		local co = toThread(f)
		schedule(now + seconds, { co = co, args = table.pack(...) })
		return co
	end
	function fakeTask.wait(seconds)
		assert(
			coroutine.isyieldable(),
			"Harness: task.wait 는 task.spawn 안에서만 부를 수 있어요 (테스트 본문에서는 H.advance 를 쓰세요)"
		)
		local started = now
		schedule(now + (seconds or 0.03), { co = coroutine.running() })
		coroutine.yield()
		return now - started
	end
	function fakeTask.cancel(co)
		for i = #queue, 1, -1 do
			if queue[i].co == co then
				table.remove(queue, i)
			end
		end
	end

	local function nowClock()
		return BASE_CLOCK + now
	end

	-- 가상으로 seconds 초 흘리기: 그 사이에 예약된 일을 시간 순서대로 실행
	function H.advance(seconds)
		local target = now + seconds
		while true do
			local bestIndex, best = nil, nil
			for i, item in queue do
				if
					item.at <= target
					and (best == nil or item.at < best.at or (item.at == best.at and item.seq < best.seq))
				then
					bestIndex, best = i, item
				end
			end
			if not best then
				break
			end
			table.remove(queue, bestIndex)
			now = math.max(now, best.at)
			if best.args then
				resumeThread(best.co, table.unpack(best.args, 1, best.args.n))
			else
				resumeThread(best.co)
			end
		end
		now = target
	end

	function H.clock()
		return nowClock()
	end

	function H.time()
		return BASE_TIME + math.floor(now)
	end

	-- 코루틴 안에서 함수를 돌리고 (yield 해도 됨) 시간을 흘려서 결과를 받음: H.run(function() return svc.load(p) end, 30)
	function H.run(fn, maxSeconds)
		local result = { done = false }
		fakeTask.spawn(function()
			result.value = table.pack(fn())
			result.done = true
		end)
		local waited = 0
		while not result.done and waited < (maxSeconds or 60) do
			H.advance(0.5)
			waited += 0.5
		end
		assert(result.done, "Harness.run: 제한 시간 안에 안 끝남 (끝없이 기다리는 코드?)")
		return table.unpack(result.value, 1, result.value.n)
	end

	local fakeOs = setmetatable({
		clock = nowClock,
		time = function(t)
			if t ~= nil then
				return os.time(t)
			end
			return H.time()
		end,
	}, { __index = os })

	----------------------------------------------------------------
	-- 가짜 난수 (진짜 Random 흉내)
	----------------------------------------------------------------
	local FakeRandom = {}
	FakeRandom.__index = FakeRandom
	function FakeRandom.new(seed)
		return setmetatable({ rng = T.rng(seed or 424242) }, FakeRandom)
	end
	function FakeRandom:NextNumber(minValue, maxValue)
		local r = self.rng()
		if minValue ~= nil then
			return minValue + r * (maxValue - minValue)
		end
		return r
	end
	function FakeRandom:NextInteger(minValue, maxValue)
		return minValue + math.floor(self.rng() * (maxValue - minValue + 1))
	end

	----------------------------------------------------------------
	-- 가짜 Instance (Net 이 RemoteEvent 를 만들 수 있게)
	----------------------------------------------------------------
	-- Tool / Part 처럼 Parent·CFrame 을 바꾸면 따라 움직이는 가짜 (Backpack·캐릭터의 children 목록에 들어가고 나감)
	local function trackedObject(className, init)
		local raw = {
			ClassName = className,
			Name = className,
			attributes = {},
			children = {},
			Position = vec(0, 0, 0),
			Size = vec(2, 2, 2),
		}
		local methods = {}
		local obj
		obj = setmetatable({}, {
			__index = function(_, key)
				local value = raw[key]
				if value ~= nil then
					return value
				end
				return methods[key]
			end,
			__newindex = function(_, key, value)
				if key == "Parent" then
					local old = raw.Parent
					if old and old.children then
						local i = table.find(old.children, obj)
						if i then
							table.remove(old.children, i)
						end
					end
					raw.Parent = value
					if value and value.children then
						table.insert(value.children, obj)
					end
				elseif key == "CFrame" then
					raw.CFrame = value
					raw.Position = value.Position
				else
					raw[key] = value
				end
			end,
		})
		function methods.SetAttribute(_, key, value)
			raw.attributes[key] = value
		end
		function methods.GetAttribute(_, key)
			return raw.attributes[key]
		end
		function methods.IsA(_, name)
			return name == className or (className == "Part" and name == "BasePart")
		end
		function methods.Destroy()
			obj.Parent = nil
			raw.destroyed = true
		end
		function methods.FindFirstChild(_, name)
			for _, child in raw.children do
				if child.Name == name then
					return child
				end
			end
			return nil
		end
		function methods.SetNetworkOwner() end
		function methods.PivotTo(_, cf)
			local primary = raw.PrimaryPart
			if primary then
				primary.CFrame = cf
			end
		end
		if init then
			init(raw, methods)
		end
		return obj
	end

	local TRACKED_CLASSES = {
		Tool = true,
		Part = true,
		Model = true,
		Weld = true,
		Humanoid = function(raw, methods)
			raw.Health = 100
			raw.WalkSpeed = 16
			raw.moves = 0
			function methods.SetStateEnabled() end
			function methods.MoveTo(_, position)
				raw.moveTarget = position
				raw.moves += 1
			end
		end,
		ProximityPrompt = function(raw)
			raw.Triggered = newSignal()
			raw.Enabled = true
		end,
	}

	local fakeInstance = {}
	function fakeInstance.new(className)
		local tracked = TRACKED_CLASSES[className]
		if tracked then
			return trackedObject(className, if type(tracked) == "function" then tracked else nil)
		end
		local inst = { ClassName = className, Name = className }
		if className == "RemoteEvent" then
			inst.OnServerEvent = newSignal()
			inst.fired = {} -- FireClient 로 보낸 것: { player, args }
			inst.firedAll = {}
			function inst:FireClient(player, ...)
				table.insert(self.fired, { player = player, args = table.pack(...) })
			end
			function inst:FireAllClients(...)
				table.insert(self.firedAll, table.pack(...))
			end
			table.insert(H.created, inst)
		end
		return inst
	end

	----------------------------------------------------------------
	-- 가짜 서비스
	----------------------------------------------------------------
	local Players = { list = {}, PlayerAdded = newSignal(), PlayerRemoving = newSignal() }
	function Players:GetPlayers()
		return table.clone(self.list)
	end
	function Players:GetPlayerByUserId(userId)
		for _, p in self.list do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end
	H.Players = Players

	local CollectionService = {
		AddTag = function() end,
		GetTagged = function()
			return {}
		end,
		GetInstanceAddedSignal = function()
			return newSignal()
		end,
		GetInstanceRemovedSignal = function()
			return newSignal()
		end,
	}
	local RunService = {
		studio = true,
		IsStudio = function(self)
			return self.studio
		end,
	}
	local Workspace = {
		GetServerTimeNow = function()
			return nowClock()
		end,
		GetAttribute = function()
			return nil
		end,
		FindFirstChild = function()
			return nil
		end,
	}
	local PhysicsService = {
		RegisterCollisionGroup = function() end,
		CollisionGroupSetCollidable = function() end,
	}
	local HttpService = {
		GenerateGUID = function()
			return "guid-" .. tostring(seq)
		end,
	}

	-- 가짜 DataStore: UpdateAsync 의 취소(nil)·재시도 규칙까지 흉내
	local store = { data = {}, failNext = 0, calls = 0, log = {} }
	function store:UpdateAsync(key, transform)
		self.calls += 1
		if self.failNext > 0 then
			self.failNext -= 1
			error("DataStore 요청 실패 (가짜)")
		end
		local old = deepCopy(self.data[key])
		local new = transform(old)
		if new == nil then
			return old
		end
		self.data[key] = deepCopy(new)
		return deepCopy(new)
	end
	local DataStoreService = {
		available = true,
		GetDataStore = function(self)
			if not self.available then
				error("DataStore 를 쓸 수 없음 (가짜)")
			end
			return store
		end,
	}
	H.store = store
	H.DataStoreService = DataStoreService

	local fakeGame = { JobId = "job-A", closeCallbacks = {} }
	function fakeGame:GetService(name)
		return Loader.root():GetService(name)
	end
	function fakeGame:BindToClose(fn)
		table.insert(self.closeCallbacks, fn)
	end
	H.game = fakeGame

	Loader.service("Players", Players)
	Loader.service("CollectionService", CollectionService)
	Loader.service("RunService", RunService)
	Loader.service("Workspace", Workspace)
	Loader.service("PhysicsService", PhysicsService)
	Loader.service("HttpService", HttpService)
	Loader.service("DataStoreService", DataStoreService)
	Loader.service("Debris", {
		AddItem = function() end,
	})
	H.RunService = RunService

	Loader.globals({
		game = fakeGame,
		task = fakeTask,
		os = fakeOs,
		Instance = fakeInstance,
		Random = FakeRandom,
		Vector3 = Vector3,
		Color3 = Color3,
		CFrame = CFrame,
		Enum = enumProxy(),
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			table.insert(H.warnings, table.concat(parts, " "))
		end,
	})

	----------------------------------------------------------------
	-- 가짜 모듈 (엔진/맵 쪽)
	----------------------------------------------------------------
	local SERVER = "ServerScriptService/Server/"
	local SHARED = "ReplicatedStorage/Shared/"
	function H.server(path)
		return Loader.require(SERVER .. path)
	end
	function H.shared(path)
		return Loader.require(SHARED .. path)
	end
	local Signal = H.server("Util/Signal")

	-- 맵 (2판): 판정은 서비스가 진짜 shared/Data/MapLayout 으로 함 (허브 z < 0, 구역 z 범위, 베이스 7개 사각형).
	--   여기 가짜 MapBuilder 는 폴더·바닥 높이·둥지 파트(MapLayout.nestsFor 자리)만 줌.
	--   H.map.zones[biomeId] = { centerX, centerZ, halfX, halfZ } 는 테스트 편의용 (MapLayout 구역 사각형)
	local MapLayout = H.shared("Data/MapLayout")
	H.MapLayout = MapLayout
	H.map = {
		folders = {},
		zones = {},
		nests = {},
		plots = {},
		groundY = 0.2,
	}
	Loader.mock(SERVER .. "Services/MapBuilder", {
		getPlot = function(index)
			return H.map.plots[index]
		end,
		plotCount = function()
			return MapLayout.PLOT_COUNT
		end,
		getFolder = function(name)
			local folder = H.map.folders[name]
			if not folder then
				folder = { Name = name, children = {} }
				H.map.folders[name] = folder
			end
			return folder
		end,
		setPlotOwner = function(index, player)
			H.map.owners = H.map.owners or {}
			H.map.owners[index] = player
		end,
		getZonePart = function()
			return nil
		end,
		getNests = function(biomeId)
			return H.map.nests[biomeId] or {}
		end,
		groundY = function()
			return H.map.groundY
		end,
		setNightWalls = function(on)
			H.map.nightWalls = on
		end,
	})

	-- 구역·둥지: MapLayout 그대로 (구역 = 복도 폭 220 × 240, 둥지 8개 = nestsFor 자리, 둥지 파트 윗면 1.4)
	do
		for _, b in MapLayout.biomes do
			H.map.zones[b.id] = { centerX = 0, centerZ = b.centerZ, halfX = MapLayout.HALF_WIDTH, halfZ = 120 }
			local nests = {}
			for i, spot in MapLayout.nestsFor(b.id) do
				local position = vec(spot.x, 0.8, spot.z)
				table.insert(nests, {
					Name = "Nest" .. i,
					Position = position,
					Size = vec(6, 1.2, 6),
					CFrame = {
						Position = position,
						VectorToWorldSpace = function(_, v)
							return v
						end,
					},
				})
			end
			H.map.nests[b.id] = nests
		end
	end

	-- 자주 쓰는 자리 (x, z): 허브 / 구역 가운데 / 베이스 안 / 러닝머신 / 판매 가게
	function H.hubSpot()
		return 0, -60
	end
	function H.zoneSpot(biomeId)
		local b = MapLayout.biome(biomeId)
		return 0, b.centerZ
	end
	function H.plotSpot(plotIndex)
		local p = MapLayout.plot(plotIndex or 1)
		return p.spawn.x, p.spawn.z
	end

	-- 주기: 낮/밤을 H.setPhase 로 바꿈
	H.cycle = { phase = "Day", number = 1, changed = Signal.new() }
	Loader.mock(SERVER .. "Services/CycleService", {
		changed = H.cycle.changed,
		getPhase = function()
			return H.cycle.phase
		end,
		isNight = function()
			return H.cycle.phase == "Night"
		end,
		getCycleNumber = function()
			return H.cycle.number
		end,
		sideFor = function(biomeId)
			local biome = H.shared("Data/Biomes").get(biomeId)
			return if biome then H.shared("Data/Biomes").sideForCycle(biome, H.cycle.number) else nil
		end,
		skip = function()
			H.cycle.skipped = (H.cycle.skipped or 0) + 1
		end,
	})
	function H.setPhase(phase, cycleNumber)
		H.cycle.phase = phase
		if cycleNumber then
			H.cycle.number = cycleNumber
		end
		H.cycle.changed:fire(phase, H.cycle.number)
	end

	-- 알(EggService): 누가 알을 들고 있는지 H.carry(player, egg) 로 정함
	H.eggs = { carried = {}, taken = 0, confiscated = 0, droppedAt = {}, specials = {}, knockouts = {}, dropped = {} }
	if not options.realEgg then
		Loader.mock(SERVER .. "Services/EggService", {
			resetDone = Signal.new(),
			carriers = function()
				return table.clone(H.eggs.carried)
			end,
			getCarried = function(player)
				return H.eggs.carried[player]
			end,
			takeCarried = function(player)
				local egg = H.eggs.carried[player]
				if egg then
					H.eggs.carried[player] = nil
					H.eggs.taken += 1
				end
				return egg
			end,
			confiscate = function(player)
				H.eggs.carried[player] = nil
				H.eggs.confiscated += 1
			end,
			dropCarriedAt = function(player, position)
				H.eggs.carried[player] = nil
				table.insert(H.eggs.droppedAt, position)
			end,
			resetCarryOrigin = function() end,
			nestPositions = function(biomeId)
				local list = {}
				for _, nest in H.map.nests[biomeId] or {} do
					table.insert(list, vec(nest.Position.X, 1.4, nest.Position.Z))
				end
				return list
			end,
			dropEgg = function(player)
				local had = H.eggs.carried[player]
				H.eggs.carried[player] = nil
				table.insert(H.eggs.dropped, { player = player, cause = "drop", hadEgg = had ~= nil })
				return had ~= nil
			end,
			spawnSpecialEgg = function(biomeId, petId, specialOptions)
				table.insert(H.eggs.specials, { biomeId = biomeId, petId = petId, options = specialOptions })
				return "e-special"
			end,
			dropCarried = function(player, cause)
				local had = H.eggs.carried[player]
				H.eggs.carried[player] = nil
				table.insert(H.eggs.dropped, { player = player, cause = cause, hadEgg = had ~= nil })
				return if had then "DropHere" else nil
			end,
			knockOut = function(player, fromPosition, cause, byName, power)
				H.eggs.carried[player] = nil -- 진짜처럼 알을 놓침
				table.insert(H.eggs.knockouts, {
					player = player,
					from = fromPosition,
					cause = cause,
					by = byName,
					power = power,
				})
			end,
		})
	end
	function H.carry(player, egg)
		egg.mutations = egg.mutations or {}
		egg.size = egg.size or "normal"
		egg.special = egg.special or false
		egg.pickedPosition = egg.pickedPosition or vec(0, 0, 100)
		egg.originAt = egg.originAt or nowClock() - 1000 -- 한참 전에 주움 (너무 빠른 배달로 안 걸리게)
		egg.pickedAt = egg.pickedAt or nowClock() - 1000 -- 경비 유예(1.5초)가 이미 지남
		egg.graceUntil = egg.graceUntil or egg.pickedAt + 1.5 -- 둥지에서 주운 것처럼 (EggService 와 같은 규칙)
		H.eggs.carried[player] = egg
	end

	-- 월드 이름표 (Util/Gui)
	local function label()
		return { Text = "" }
	end
	Loader.mock(SERVER .. "Util/Gui", {
		billboard = label,
		surface = label,
		sign = function()
			return { frame = {}, title = label() }
		end,
		tag = function()
			return {}
		end,
	})

	-- 특수 장소 (Util/Landmarks): H.landmarks.nearName 이 가까이 있는 파트 이름
	H.landmarks = { nearName = nil, parts = {} }
	local function makePart(spec)
		local p = { Name = spec.name, attributes = spec.attributes or {}, Position = spec.position, Size = spec.size }
		function p:GetAttribute(name)
			return self.attributes[name]
		end
		function p:SetAttribute(name, value)
			self.attributes[name] = value
		end
		return p
	end
	Loader.mock(SERVER .. "Util/Landmarks", {
		folder = function()
			return {}
		end,
		tagged = function()
			return {}
		end,
		find = function()
			return {}
		end,
		plotPart = function()
			return nil
		end,
		distanceToPart = function()
			return 0
		end,
		isPlayerNear = function()
			return false
		end,
		nearest = function(_, parts)
			for _, p in parts do
				if H.landmarks.nearName == "*" or H.landmarks.nearName == p.Name then
					return p
				end
			end
			return nil
		end,
		placeholder = function(spec)
			return makePart(spec)
		end,
		ensure = function(spec)
			local p = makePart(spec)
			H.landmarks.parts[spec.name] = p
			return { p }
		end,
	})

	----------------------------------------------------------------
	-- 가짜 플레이어 / 캐릭터
	----------------------------------------------------------------
	function H.newPlayer(userId, name)
		local player = {
			UserId = userId,
			Name = name or ("Player" .. userId),
			DisplayName = name or ("Player" .. userId),
			Parent = Players,
			attrs = {},
			Chatted = newSignal(),
			kicked = nil,
			groups = {},
		}
		function player:SetAttribute(key, value)
			self.attrs[key] = value
		end
		function player:GetAttribute(key)
			return self.attrs[key]
		end
		function player:FindFirstChild()
			return nil
		end
		function player:FindFirstChildOfClass(className)
			if className == "Backpack" then
				return self.backpack
			end
			return nil
		end
		function player:IsInGroup(groupId)
			return self.groups[groupId] == true
		end
		function player:Kick(message)
			self.kicked = message
		end
		table.insert(Players.list, player)
		return player
	end

	function H.spawn(player, x, y, z)
		local root = {
			Name = "HumanoidRootPart",
			Position = vec(x or 0, y or 3, z or 0),
			Size = vec(2, 2, 1),
			AssemblyLinearVelocity = vec(0, 0, 0),
		}
		root.CFrame = cframeOf(root.Position, vec(0, 0, -1))
		function root:IsA(className)
			return className == "BasePart" or className == "Part"
		end
		local humanoid = {
			Health = 100,
			WalkSpeed = 16,
			JumpHeight = 7.2,
			JumpPower = 50,
			Sit = false,
			PlatformStand = false,
		}
		function humanoid:IsA(className)
			return className == "Humanoid"
		end
		local character =
			{ Name = player.Name, root = root, humanoid = humanoid, DescendantAdded = newSignal(), children = {} }
		function character:GetDescendants()
			return { root, humanoid }
		end
		function character:FindFirstChild(childName)
			if childName == "HumanoidRootPart" or childName == "Head" then
				return root
			end
			for _, child in self.children do
				if child.Name == childName then
					return child
				end
			end
			return nil
		end
		function character:FindFirstChildOfClass(className)
			return if className == "Humanoid" then humanoid else nil
		end
		function character:PivotTo(cf)
			local position = cf.Position or cf
			root.Position = position
			root.CFrame = cframeOf(position, cf.LookVector or root.CFrame.LookVector)
		end
		humanoid.Parent = character
		player.Character = character
		return character
	end

	-- 가방 만들기 (서버가 Tool 을 여기에 넣어 줌): H.giveBackpack(player) → backpack.children
	function H.giveBackpack(player)
		local backpack = { ClassName = "Backpack", children = {} }
		function backpack:FindFirstChild(name)
			for _, child in self.children do
				if child.Name == name then
					return child
				end
			end
			return nil
		end
		function backpack:IsA(className)
			return className == "Backpack"
		end
		player.backpack = backpack
		return backpack
	end

	-- 가방의 Tool 을 손에 듦 (Tool.Parent = 캐릭터) / 내려놓음
	function H.equip(player, toolName)
		local tool = player.backpack:FindFirstChild(toolName)
		assert(tool, "가방에 " .. toolName .. " 없음")
		tool.Parent = player.Character
		return tool
	end

	function H.unequip(player, toolName)
		local tool = player.Character:FindFirstChild(toolName)
		if tool then
			tool.Parent = player.backpack
		end
	end

	-- 캐릭터가 바라보는 방향 (공격 방향 판정용). 기본은 -Z
	function H.face(player, x, y, z)
		local root = player.Character.root
		root.CFrame = cframeOf(root.Position, vec(x, y, z))
	end

	function H.teleport(player, x, y, z)
		local root = player.Character.root
		root.Position = vec(x, y, z)
		root.CFrame = cframeOf(root.Position, root.CFrame.LookVector)
	end

	function H.vec(x, y, z)
		return vec(x, y, z)
	end

	function H.leave(player)
		Players.PlayerRemoving:Fire(player)
		local i = table.find(Players.list, player)
		if i then
			table.remove(Players.list, i)
		end
		player.Parent = nil
	end

	----------------------------------------------------------------
	-- 네트워크 (진짜 server/Net.luau) 와 보낸 것 읽기
	----------------------------------------------------------------
	H.remotes = {}

	-- 진짜 Net.start(): 모든 RemoteEvent 를 만듦. 서비스의 start() 보다 먼저 부를 것.
	function H.startNet()
		local Net = H.server("Net")
		Net.start()
		for _, inst in H.created do
			H.remotes[inst.Name] = inst
		end
		return Net
	end

	-- 클라가 서버로 보낸 척: H.client(player, "HatchEgg", "i1")
	function H.client(player, remoteName, ...)
		local remote = assert(H.remotes[remoteName], "Harness: 없는 Remote — " .. remoteName)
		for _, fn in table.clone(remote.OnServerEvent.handlers) do
			fn(player, ...)
		end
	end

	-- 서버가 그 플레이어에게 보낸 것들 (인자 묶음 목록)
	function H.sent(player, remoteName)
		local remote = assert(H.remotes[remoteName], "Harness: 없는 Remote — " .. remoteName)
		local list = {}
		for _, item in remote.fired do
			if item.player == player then
				table.insert(list, item.args)
			end
		end
		return list
	end

	function H.clearSent()
		for _, remote in H.remotes do
			table.clear(remote.fired)
			table.clear(remote.firedAll)
		end
	end

	-- 알림(Notify) 글 목록: { { kind, text } }
	function H.notifications(player)
		local list = {}
		for _, args in H.sent(player, "Notify") do
			table.insert(list, args[1])
		end
		return list
	end

	function H.lastNotify(player)
		local list = H.notifications(player)
		return list[#list]
	end

	function H.hasNotify(player, kind, fragment)
		for _, n in H.notifications(player) do
			if (kind == nil or n.kind == kind) and string.find(n.text, fragment, 1, true) then
				return true
			end
		end
		return false
	end

	----------------------------------------------------------------
	-- 로그인 (PlayerLifecycle 이 하는 일 중 서비스 테스트에 필요한 만큼)
	----------------------------------------------------------------
	function H.login(player, overrides)
		local Sessions = H.server("Sessions")
		local DataSchema = H.server("Logic/DataSchema")
		local session = Sessions.create(player)
		local data = DataSchema.default(H.time())
		for key, value in overrides or {} do
			data[key] = value
		end
		session.data = data
		session.loaded = true
		session.saveEnabled = false
		return session, data
	end

	function H.uninstall()
		Loader.clearFakes()
	end

	return H
end

return ServerHarness
