--!nocheck
--[[
	ServerHarness — 송판 깨기 서버 서비스의 "진짜 코드"를 Lune 에서 돌려 보는 작은 가짜 세상 (첫 게임 tests/ServerHarness.luau 를 줄여 복사)

	가짜로 만드는 것 (로블록스 엔진 부분만):
	  - 가상 시간: task.spawn / task.wait / task.delay 와 os.clock / os.time. H.advance(초) 로 시간을 흘림 (진짜 기다리지 않음)
	  - Instance.new("RemoteEvent") 등 최소한의 가짜 → 진짜 server/Net.luau 가 그대로 올라옴 (속도 제한·pcall 포함)
	  - Players / CollectionService / DataStoreService / MarketplaceService 등 서비스, 가짜 플레이어·캐릭터
	  - 선임 MapLayout: 진짜 파일이 있으면 그대로 씀. 없으면 (또는 options.fakeMap = true) 아래 가짜 MapLayout 을 끼움
	진짜 그대로 쓰는 것: Sessions, Snapshot, Wallet, TrainService, BreakService, ShopService, ExamService, WorldService,
	  ProductService, DataService, DevCommands, LeaderboardService, Net ...

	사용:
	  local H = ServerHarness.install(Loader, T)            -- 가짜 세상 켜기 (모듈 캐시를 비움)
	  local player = H.newPlayer(1001, "Tester")
	  local session, data = H.login(player, { power = 100 }) -- 세션 + 기본 저장 데이터 (+ 덮어쓸 칸)
	  local Train = H.server("Services/TrainService")      -- 진짜 서비스
	  H.advance(10)                                          -- 가상으로 10초
	  H.uninstall()                                          -- 정리
]]

local fs = require("@lune/fs")

local ServerHarness = {}

-- 게임 폴더 (저장소 루트에서 돌리면 games/boardbreak)
local GAME_DIR = if fs.isFile("games/boardbreak/default.project.json") then "games/boardbreak" else "."

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

-- options.fakeMap = true 면 진짜 MapLayout 대신 가짜 (H.fakeMap 숫자) 를 씀
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
	----------------------------------------------------------------
	-- 가짜 MarketplaceService (게임패스 소유 확인 · 구매 끝 신호 · ProcessReceipt)
	--   H.market.owned[userId][gamePassId] = true 이면 가짐. H.market.failNext = n 이면 다음 n 번 확인이 오류
	----------------------------------------------------------------
	local market = {
		owned = {},
		failNext = 0,
		calls = 0,
		ProcessReceipt = nil,
		PromptGamePassPurchaseFinished = newSignal(),
	}
	function market:UserOwnsGamePassAsync(userId, gamePassId)
		self.calls += 1
		if self.failNext > 0 then
			self.failNext -= 1
			error("UserOwnsGamePassAsync 실패 (가짜)")
		end
		local set = self.owned[userId]
		return set ~= nil and set[gamePassId] == true
	end
	H.market = market
	Loader.service("MarketplaceService", market)

	----------------------------------------------------------------
	-- 맵 자리 (선임 shared/Data/MapLayout). 진짜 파일이 있으면 그대로, 없으면 가짜.
	--   가짜: 월드 w 원점 x = 2000·(w-1). 물건 i 는 (원점 + 0, 0, 100 + 20·i), 닿는 거리 10.
	--   수련 매트 = 원점 근처 |x|,|z| ≤ 10. 스폰 (원점, 0, -36). 심사대 (원점 + 30, 0, 30). 대결장 (원점 - 30, 0, 32)
	----------------------------------------------------------------
	local function fakeMapLayout()
		local Targets = Loader.require(SHARED .. "Data/Targets")
		local function origin(world)
			return (math.clamp(math.floor(tonumber(world) or 1), 1, 3) - 1) * 2000
		end
		local function readXYZ(pos)
			return tonumber(pos.x or pos.X) or 0, tonumber(pos.y or pos.Y) or 0, tonumber(pos.z or pos.Z) or 0
		end
		local M = {}
		function M.targetPosition(id)
			local t = Targets.get(id)
			if not t then
				return nil
			end
			return { x = origin(t.world), y = 0, z = 100 + 20 * t.index }
		end
		function M.targetReach(id)
			return if Targets.get(id) then 10 else 0
		end
		function M.isOnTrainMat(pos, world)
			if pos == nil then
				return false
			end
			local x, _, z = readXYZ(pos)
			return math.abs(x - origin(world)) <= 10 and math.abs(z) <= 10
		end
		function M.spawn(world)
			return { x = origin(world), y = 0, z = -36, sizeX = 10, sizeZ = 10, yaw = 0 }
		end
		function M.examPad(world)
			return { x = origin(world) + 30, y = 0, z = 30, sizeX = 16, sizeZ = 14, yaw = 0 }
		end
		function M.duelArena(world)
			local x = origin(world) - 30
			return {
				x = x,
				y = 0,
				z = 32,
				sizeX = 34,
				sizeZ = 22,
				yaw = 0,
				player = { x = x, y = 0, z = 27 },
				examiner = { x = x, y = 0, z = 37 },
				boards = 15,
			}
		end
		function M.worldAt(pos)
			local x = readXYZ(pos)
			return math.clamp(math.floor((x + 1000) / 2000) + 1, 1, 3)
		end
		return M
	end
	if options.fakeMap or not fs.isFile(GAME_DIR .. "/src/shared/Data/MapLayout.luau") then
		Loader.virtual("ReplicatedStorage/Shared/Data", "MapLayout", fakeMapLayout())
		H.usingFakeMap = true
	else
		H.usingFakeMap = false
	end
	local MapLayout = Loader.require(SHARED .. "Data/MapLayout")
	H.MapLayout = MapLayout

	-- 자주 쓰는 자리 (월드 좌표 x, y, z): 수련 매트 위 · 물건 앞 · 심사대 · 대결장
	local function center(spot)
		return spot.x, (spot.y or 0) + 3, spot.z
	end
	function H.matSpot(world)
		if H.usingFakeMap then
			return ((world or 1) - 1) * 2000, 3, 0
		end
		local mats = MapLayout.trainMats(world or 1)
		return center(mats[1])
	end
	function H.targetSpot(id)
		local p = assert(MapLayout.targetPosition(id), "물건 자리 없음 " .. tostring(id))
		return p.x, (p.y or 0) + 3, p.z
	end
	function H.examSpot(world)
		return center(MapLayout.examPad(world or 1))
	end
	function H.duelSpot(world)
		local arena = MapLayout.duelArena(world or 1)
		local p = arena.player or arena
		return p.x, (p.y or 0) + 3, p.z
	end
	function H.spawnSpot(world)
		return center(MapLayout.spawn(world or 1))
	end
	-- 플레이어를 그 자리로 (캐릭터가 없으면 만듦)
	function H.place(player, x, y, z)
		if not player.Character then
			H.spawn(player, x, y, z)
		else
			H.teleport(player, x, y, z)
		end
	end

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
		session.currentWorld = data.world
		return session, data
	end

	function H.uninstall()
		Loader.clearFakes()
	end

	return H
end

return ServerHarness
