--!nocheck
--[[
	송판 깨기 — 서버 맵 스모크 테스트 (선임). 저장소 루트에서:
	  lune run games/boardbreak/tests/smoke_visuals.luau
	(tests/run.luau 에는 안 들어감. @lune/roblox 진짜 인스턴스로 MapBuilder 를 돌려 보며 속성 이름 오타·nil 인덱싱을 잡고,
	 자리 규칙을 숫자로 검사합니다. 예쁜지는 스튜디오에서 — docs/STUDIO_CHECKLIST.md)

	검사: 월드 3개 · 물건 41개가 Targets 표와 1:1 (MapLayout.TARGET_IDS 순서도) · 태그 BreakTarget·Attr TargetId/World
	      · ClickDetector "Click" · 머리 위 글 · 물건끼리/길/로비와 안 겹침 (실제 파트 크기로) · targetReach 안에 설 자리(길)
	      · 파트 수 상한 (맵 6,000 · 월드 2,200 · 물건 15) · 로비 태그 (매트 6×3, 가게·띠판·심사대·대결장 각 3, 문 6, 스폰 3)
	      · isOnTrainMat · 표지판·가게·심사대·대결장·문이 스폰·매트와 안 겹침 · 심사·대결 송판 이름 (Board_1.. · Mine_1.. · Theirs_1..)
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./Loader")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
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

local function noopSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
		Wait = function() end,
	}
end
for _, class in { "Part", "SpawnLocation", "Model", "Folder", "BillboardGui", "SurfaceGui", "TextLabel", "Frame" } do
	pcall(roblox.implementMethod, class, "GetAttributeChangedSignal", function()
		return noopSignal()
	end)
	pcall(roblox.implementMethod, class, "GetPropertyChangedSignal", function()
		return noopSignal()
	end)
end
roblox.implementMethod("Model", "PivotTo", function(model, cf)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local delta = cf * primary.CFrame:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)
pcall(roblox.implementMethod, "Model", "WaitForChild", function(model, name)
	return model:FindFirstChild(name)
end)
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
	HasTag = function(_, inst, tag)
		return table.find(tagged[tag] or {}, inst) ~= nil
	end,
	GetInstanceAddedSignal = function()
		return noopSignal()
	end,
	GetInstanceRemovedSignal = function()
		return noopSignal()
	end,
}

local sharedNode = Loader.get("ReplicatedStorage")
local function warm(node)
	for _, child in node.GetChildren(node) do
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
		return nil
	end,
})
local fakeGame = {
	GetService = function(_, name)
		if name == "CollectionService" then
			return CollectionService
		elseif name == "ReplicatedStorage" then
			return ReplicatedProxy
		elseif name == "Workspace" then
			return Workspace
		end
		return game:GetService(name)
	end,
}

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
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		task = { spawn = function() end, defer = function() end, wait = function() end, delay = function() end },
		warn = function(...)
			print("WARN:", ...)
		end,
	}, { __index = _G })
end
requireNode = function(node)
	local props = rawget(node, "__props")
	local file = props.file
	if cache[file] ~= nil then
		return cache[file]
	end
	local chunk = luau.load(fs.readFile(file), { debugName = file, environment = makeEnv(node) })
	local result = chunk()
	cache[file] = result
	return result
end

local function count(inst)
	local n = if inst:IsA("BasePart") then 1 else 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- 파트 하나가 바닥에서 차지하는 범위: (가운데 x, z) 에서 가장 먼 수평 거리, 그리고 xz 사각형
local function partCorners(p)
	local cf = p.CFrame
	local s = p.Size
	local pts = {}
	if p.Shape == roblox.Enum.PartType.Ball then
		local r = s.X / 2
		local c = cf.Position
		for _, o in { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } } do
			table.insert(pts, Vector3.new(c.X + o[1], c.Y, c.Z + o[2]))
		end
		return pts
	end
	if p.Shape == roblox.Enum.PartType.Cylinder then
		-- 원기둥: 축(X) 양 끝 원판. 원판 가장자리는 축과 수직인 수평 방향으로 반지름만큼
		local r = s.Y / 2
		local axis = cf.RightVector
		for _, e in { cf.Position + axis * (s.X / 2), cf.Position - axis * (s.X / 2) } do
			local flat = Vector3.new(axis.X, 0, axis.Z)
			local perp = if math.abs(axis.Y) > 0.5 then nil else Vector3.new(-flat.Z, 0, flat.X).Unit
			local dirs = if perp
				then { perp, -perp, Vector3.new(0, 1, 0), Vector3.new(0, -1, 0) }
				else {
					Vector3.new(1, 0, 0),
					Vector3.new(-1, 0, 0),
					Vector3.new(0, 0, 1),
					Vector3.new(0, 0, -1),
					Vector3.new(0.7071, 0, 0.7071),
					Vector3.new(-0.7071, 0, 0.7071),
					Vector3.new(0.7071, 0, -0.7071),
					Vector3.new(-0.7071, 0, -0.7071),
				}
			for _, d in dirs do
				table.insert(pts, e + d * r)
			end
		end
		return pts
	end
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(pts, cf * Vector3.new(sx * s.X / 2, sy * s.Y / 2, sz * s.Z / 2))
			end
		end
	end
	return pts
end

local function horizontalReach(model, center)
	local worst = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Hitbox" then
			for _, pt in partCorners(d) do
				local dx, dz = pt.X - center.X, pt.Z - center.Z
				worst = math.max(worst, math.sqrt(dx * dx + dz * dz))
			end
		end
	end
	return worst
end

local function xzRect(p, pad)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, pt in partCorners(p) do
		x0, x1 = math.min(x0, pt.X), math.max(x1, pt.X)
		z0, z1 = math.min(z0, pt.Z), math.max(z1, pt.Z)
	end
	return { x0 = x0 - (pad or 0), x1 = x1 + (pad or 0), z0 = z0 - (pad or 0), z1 = z1 + (pad or 0) }
end
local function rectsOverlap(a, b)
	return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1
end
local function spotRect(s, pad)
	return {
		x0 = s.x - s.sizeX / 2 - pad,
		x1 = s.x + s.sizeX / 2 + pad,
		z0 = s.z - s.sizeZ / 2 - pad,
		z1 = s.z + s.sizeZ / 2 + pad,
	}
end

local function body()
	local MapLayout = requireNode(Loader.get("ReplicatedStorage/Shared/Data/MapLayout"))
	local Targets = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Targets"))
	local Tags = requireNode(Loader.get("ReplicatedStorage/Shared/Tags"))

	print("[MapLayout ↔ Targets]")
	check(#Targets.list == 41, "Targets 41개 (" .. #Targets.list .. ")")
	local layoutCount = 0
	local orderOk = true
	for w = 1, 3 do
		local ids = MapLayout.targetIds(w)
		local list = Targets.byWorld(w)
		layoutCount += #ids
		if #ids ~= #list then
			orderOk = false
		end
		for i, t in list do
			if ids[i] ~= t.id then
				orderOk = false
				print("    순서 다름: 월드 " .. w .. " #" .. i .. " " .. tostring(ids[i]) .. " ≠ " .. t.id)
			end
		end
	end
	check(
		layoutCount == 41 and orderOk,
		"MapLayout.TARGET_IDS 가 Targets.byWorld 와 같은 순서 (월드 1: 13 · 2: 14 · 3: 14)"
	)
	local posOk, worldOk = true, true
	for _, t in Targets.list do
		local p = MapLayout.targetPosition(t.id)
		if not p then
			posOk = false
		elseif MapLayout.worldAt(p) ~= t.world or MapLayout.targetWorld(t.id) ~= t.world then
			worldOk = false
		end
	end
	check(posOk, "물건 41개 모두 targetPosition 있음")
	check(worldOk, "물건 자리가 그 월드 땅 안 (worldAt = Targets.world)")
	check(
		MapLayout.targetPosition("nope") == nil and MapLayout.targetReach("nope") == 0,
		"모르는 id → nil / reach 0"
	)
	-- 로비에서 점점 멀어지고 뒤 물건일수록 큼
	local farther, bigger = true, true
	for w = 1, 3 do
		local ids = MapLayout.targetIds(w)
		for i = 2, #ids do
			local a, b = MapLayout.targetPosition(ids[i - 1]), MapLayout.targetPosition(ids[i])
			if b.z <= a.z then
				farther = false
			end
			if MapLayout.targetRadius(ids[i]) <= MapLayout.targetRadius(ids[i - 1]) then
				bigger = false
			end
		end
	end
	check(farther, "뒤 물건일수록 로비에서 멀어짐 (z 증가)")
	check(bigger, "뒤 물건일수록 큼 (반지름 증가)")
	-- 설 자리 (길 위) 가 targetReach 안
	local reachOk = true
	for _, t in Targets.list do
		local road = MapLayout.roadPoint(t.id)
		local p = MapLayout.targetPosition(t.id)
		local ox = MapLayout.worldOrigin(t.world).x
		local ws = MapLayout.worldScale(t.world)
		local dist = math.sqrt((road.x - p.x) ^ 2 + (road.z - p.z) ^ 2)
		if math.abs(road.x - ox) > MapLayout.ROAD_HALF * ws or dist > MapLayout.targetReach(t.id) - ws then
			reachOk = false
			print("    설 자리 없음: " .. t.id .. " dist " .. dist .. " reach " .. MapLayout.targetReach(t.id))
		end
	end
	check(reachOk, "물건마다 길 위에 targetReach 안쪽 설 자리 (roadPoint)")
	-- 매트 판정
	local mats = MapLayout.trainMats(1)
	check(#mats >= 4 and #mats <= 6, "수련 매트 4~6칸 (" .. #mats .. ")")
	check(
		MapLayout.isOnTrainMat(Vector3.new(mats[1].x, 3, mats[1].z), 1),
		"매트 가운데 (Vector3, 몸 높이 3) → 매트 위"
	)
	check(
		MapLayout.isOnTrainMat({ x = mats[2].x + 4, y = 0.5, z = mats[2].z - 4 }, 1),
		"매트 가장자리 ({x,y,z} 표) → 매트 위"
	)
	local sp = MapLayout.spawn(1)
	check(not MapLayout.isOnTrainMat(Vector3.new(sp.x, 3, sp.z), 1), "스폰 자리 → 매트 아님")
	check(
		not MapLayout.isOnTrainMat(Vector3.new(mats[1].x, 3, mats[1].z), 2),
		"월드 1 매트 자리를 월드 2 로 물으면 아님"
	)
	check(
		not MapLayout.isOnTrainMat(Vector3.new(mats[1].x, 40, mats[1].z), 1),
		"매트 위 높이 40 (점프 아주 높이) → 아님"
	)
	check(not MapLayout.isOnTrainMat(nil, 1), "pos nil → false (오류 없음)")
	local m2 = MapLayout.trainMats(2)[1]
	check(MapLayout.isOnTrainMat(Vector3.new(m2.x, 3, m2.z), 2), "월드 2 매트 위")
	local d1 = MapLayout.duelArena(3)
	check(d1.boards == 15 and d1.player and d1.examiner, "duelArena: 송판 15 · player/examiner 줄")
	check(#MapLayout.doors(1) == 2 and #MapLayout.doors(3) == 2, "월드마다 다른 월드 문 2개")

	print("[맵 만들기]")
	-- 사범님: 월드 1 은 가짜 R15 몸(진짜 API 대신)으로 입히기 경로를, 월드 2·3 은 API 없음 → 블록 대체 경로를 검사
	local Dojo = requireNode(Loader.get("ServerScriptService/Server/Map/Dojo"))
	local realCreate = Dojo.createRig
	local rigCalls = 0
	Dojo.createRig = function()
		rigCalls += 1
		if rigCalls > 1 then
			return realCreate() -- Lune 에는 HumanoidDescription·CreateHumanoidModelFromDescription 이 없음 → nil
		end
		local rig = Instance.new("Model")
		local function part(name, size, y)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.CFrame = CFrame.new(0, y, 0)
			p.Parent = rig
			return p
		end
		part("HumanoidRootPart", Vector3.new(2, 2, 1), 3)
		local up = part("UpperTorso", Vector3.new(2, 1.6, 1), 3.4)
		part("LowerTorso", Vector3.new(2, 0.4, 1), 2.4)
		part("Head", Vector3.new(1.2, 1.2, 1.2), 4.8)
		for _, side in { "Left", "Right" } do
			local ua = part(side .. "UpperArm", Vector3.new(1, 1.2, 1), 3.4)
			local m = Instance.new("Motor6D")
			m.Name = side .. "Shoulder"
			m.Part0 = up
			m.Part1 = ua
			m.Parent = ua
			part(side .. "LowerArm", Vector3.new(1, 1.1, 1), 2.4)
			part(side .. "Hand", Vector3.new(1, 0.3, 1), 1.8)
			part(side .. "UpperLeg", Vector3.new(1, 1.2, 1), 1.6)
			part(side .. "LowerLeg", Vector3.new(1, 1.1, 1), 0.7)
			part(side .. "Foot", Vector3.new(1, 0.3, 1), 0.15)
		end
		local hum = Instance.new("Humanoid")
		hum.HipHeight = 2
		hum.Parent = rig
		return rig
	end
	local MapBuilder = requireNode(Loader.get("ServerScriptService/Server/Services/MapBuilder"))
	MapBuilder.start()
	MapBuilder.start() -- 두 번 불러도 한 번만
	local map = Workspace:FindFirstChild("Map")
	check(map ~= nil, "Workspace.Map 생김")
	local worldsFound = 0
	for w = 1, 3 do
		local f = map:FindFirstChild("World" .. w)
		if f and f:GetAttribute("World") == w then
			worldsFound += 1
		end
	end
	check(worldsFound == 3 and #map:GetChildren() == 3, "월드 폴더 3개 (World1..3, Attr World)")

	print("[파트 수 상한]")
	local budget = MapBuilder.PART_BUDGET
	local counts = MapBuilder.partCounts()
	print(
		string.format(
			"    맵 %d 파트 (월드1 %d · 월드2 %d · 월드3 %d)",
			counts.total,
			counts.worlds[1],
			counts.worlds[2],
			counts.worlds[3]
		)
	)
	check(count(map) == counts.total, "partCounts 합 = 실제 파트 수")
	check(counts.total <= budget.map and budget.map <= 6000, "맵 전체 ≤ " .. budget.map)
	for w = 1, 3 do
		check(counts.worlds[w] <= budget.world, "월드 " .. w .. " ≤ " .. budget.world)
	end

	print("[물건 41개]")
	local models = CollectionService:GetTagged(Tags.BreakTarget)
	check(#models == 41, "BreakTarget 태그 41개 (" .. #models .. ")")
	local seen = {}
	local dup, unknown, attrBad, clickBad, infoBad, partBad, primaryBad = 0, 0, 0, 0, 0, 0, 0
	local minParts, maxParts = math.huge, 0
	local extents = {}
	for _, m in models do
		local id = m:GetAttribute(Tags.PartAttributes.TargetId)
		local t = Targets.get(id)
		if seen[id] then
			dup += 1
		end
		seen[id] = true
		if not t then
			unknown += 1
		else
			if m:GetAttribute(Tags.PartAttributes.World) ~= t.world or not m:IsA("Model") then
				attrBad += 1
			end
			local click = m:FindFirstChild("Click")
			if
				not (click and click:IsA("ClickDetector") and click.MaxActivationDistance >= MapLayout.targetReach(id))
			then
				clickBad += 1
			end
			local hit = m.PrimaryPart
			if not (hit and hit.Name == "Hitbox" and hit.Transparency == 1 and hit.CanQuery and not hit.CanCollide) then
				primaryBad += 1
			end
			local gui = hit and hit:FindFirstChild("TargetInfo")
			local box = gui and gui:FindFirstChild("Box")
			if
				not (
					box
					and box:FindFirstChild("Name").Text == t.name
					and box:FindFirstChild("Reward")
					and box:FindFirstChild("Need")
				)
			then
				infoBad += 1
			end
			local n = count(m)
			local looks = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Look" then
					looks += 1
				end
			end
			minParts, maxParts = math.min(minParts, n), math.max(maxParts, n)
			if n > budget.target or looks < 3 or looks > 14 then
				partBad += 1
				print("    파트 수: " .. id .. " 전체 " .. n .. " · 모양 " .. looks)
			end
			local p = MapLayout.targetPosition(id)
			extents[id] = horizontalReach(m, Vector3.new(p.x, 0, p.z))
		end
	end
	check(dup == 0 and unknown == 0, "TargetId 가 겹치지 않고 전부 Targets 에 있음")
	local missing = 0
	for _, t in Targets.list do
		if not seen[t.id] then
			missing += 1
			print("    모델 없음: " .. t.id)
		end
	end
	check(missing == 0, "Targets 41개 모두 모델 있음 (1:1)")
	check(attrBad == 0, "Model + Attr World 가 Targets.world 와 같음")
	check(clickBad == 0, 'ClickDetector "Click" (거리 ≥ targetReach)')
	check(primaryBad == 0, "PrimaryPart = 보이지 않는 Hitbox (CanQuery, 안 부딪힘)")
	check(infoBad == 0, "머리 위 글 TargetInfo (이름 · 값 · 필요한 힘)")
	check(
		partBad == 0,
		string.format(
			"물건 파트 3~14 모양 + 전체 ≤ %d (가장 적은 %d · 많은 %d)",
			budget.target,
			minParts,
			maxParts
		)
	)

	print("[겹침]")
	local overlap, roadHit, lobbyHit, tooWide = 0, 0, 0, 0
	for w = 1, 3 do
		local ids = MapLayout.targetIds(w)
		local ox = MapLayout.worldOrigin(w).x
		local ws = MapLayout.worldScale(w)
		for i, a in ids do
			local pa = MapLayout.targetPosition(a)
			local ea = extents[a] or 0
			if ea > MapLayout.targetRadius(a) * 1.45 + ws then
				tooWide += 1
				print(
					string.format(
						"    너무 넓음: %s 실제 %.1f · 반지름 %.1f",
						a,
						ea,
						MapLayout.targetRadius(a)
					)
				)
			end
			if math.abs(pa.x - ox) - ea < MapLayout.ROAD_HALF * ws then
				roadHit += 1
				print(string.format("    길을 막음: %s (가운데 %.1f · 실제 %.1f)", a, pa.x - ox, ea))
			end
			if pa.z - ea < (MapLayout.LOBBY_HALF + 2) * ws then
				lobbyHit += 1
				print("    로비와 겹침: " .. a)
			end
			for j = i + 1, #ids do
				local b = ids[j]
				local pb = MapLayout.targetPosition(b)
				local dist = math.sqrt((pa.x - pb.x) ^ 2 + (pa.z - pb.z) ^ 2)
				if dist < ea + (extents[b] or 0) + ws then
					overlap += 1
					print(
						string.format(
							"    겹침: %s ↔ %s (거리 %.1f, 크기 %.1f + %.1f)",
							a,
							b,
							dist,
							ea,
							extents[b] or 0
						)
					)
				end
			end
		end
	end
	check(tooWide == 0, "물건 실제 크기가 MapLayout 반지름 × 1.45 안")
	check(overlap == 0, "물건끼리 안 겹침 (실제 파트 크기)")
	check(roadHit == 0, "물건이 가운데 길을 안 막음")
	check(lobbyHit == 0, "물건이 로비(도장)와 안 겹침")

	print("[로비 태그]")
	local A = Tags.PartAttributes
	local matParts = CollectionService:GetTagged(Tags.TrainMat)
	check(
		#matParts == 3 * #mats + #Targets.list,
		"TrainMat 파트 " .. #matParts .. " (도장 월드마다 " .. #mats .. " + 길가 " .. #Targets.list .. ")"
	)
	local matOk = true
	for _, p in matParts do
		local w = p:GetAttribute(A.World)
		local pos = p.CFrame.Position
		if not (w and MapLayout.isOnTrainMat(pos + Vector3.new(0, 3, 0), w) and p:IsA("BasePart")) then
			matOk = false
		end
	end
	check(matOk, "매트 파트 위 = isOnTrainMat (Attr World)")

	print("[길가 수련 매트 41칸]")
	local roadParts = {}
	for _, p in matParts do
		local tid = p:GetAttribute(A.TargetId)
		if tid then
			roadParts[tid] = p
		end
	end
	local rmTag, rmWalk, rmOn, rmTarget, rmRoad, rmMats, rmParts, rmInfo = 0, 0, 0, 0, 0, 0, 0, 0
	local maxWalk = 0
	for _, t in Targets.list do
		local mp = MapLayout.matPoint(t.id)
		local part = roadParts[t.id]
		local p = MapLayout.targetPosition(t.id)
		local ox = MapLayout.worldOrigin(t.world).x
		local ws = MapLayout.worldScale(t.world)
		if not (mp and part and part:GetAttribute(A.World) == t.world) then
			rmTag += 1
			print("    길가 매트 없음/태그·Attr 틀림: " .. t.id)
		else
			local walk = MapLayout.matWalkDistance(t.id)
			maxWalk = math.max(maxWalk, walk)
			if walk > 6 then
				rmWalk += 1
				print(string.format("    매트에서 멀다: %s %.1f", t.id, walk))
			end
			if not MapLayout.isOnTrainMat(Vector3.new(mp.x, 3, mp.z), t.world) then
				rmOn += 1
			end
			-- 물건(실제 파트 크기)과 안 겹침
			local half = math.max(part.Size.X, part.Size.Z) / 2
			local dist = math.sqrt((mp.x - p.x) ^ 2 + (mp.z - p.z) ^ 2)
			if dist < (extents[t.id] or 0) + 0.5 * ws then
				rmTarget += 1
				print("    물건과 겹침: " .. t.id)
			end
			for _, other in MapLayout.targetIds(t.world) do
				if other ~= t.id then
					local q = MapLayout.targetPosition(other)
					local ea = extents[other] or 0
					if math.sqrt((mp.x - q.x) ^ 2 + (mp.z - q.z) ^ 2) < ea + half - 0.5 * ws then
						-- 대략 원 판정이 겹치면 사각형으로 다시
						local rx = math.abs(mp.x - q.x) - part.Size.X / 2
						local rz = math.abs(mp.z - q.z) - part.Size.Z / 2
						if math.max(rx, rz) < ea then
							rmTarget += 1
							print("    다른 물건과 겹침: " .. t.id .. " ↔ " .. other)
						end
					end
				end
			end
			-- 길 위, 가운데 통로(±1.5)는 비워 둠, 안 부딪힘 (길을 막지 않음)
			local x0, x1 = mp.x - part.Size.X / 2 - ox, mp.x + part.Size.X / 2 - ox
			if
				math.abs(x0) > MapLayout.ROAD_HALF * ws
				or math.abs(x1) > MapLayout.ROAD_HALF * ws
				or (x0 < 1.5 * ws and x1 > -1.5 * ws)
				or part.CanCollide
			then
				rmRoad += 1
				print("    길을 막음/길 밖: " .. t.id)
			end
			-- 다른 매트와 안 겹침
			for _, m in MapLayout.roadMats(t.world) do
				if
					m.targetId ~= t.id
					and math.abs(m.x - mp.x) < (m.sizeX + part.Size.X) / 2
					and math.abs(m.z - mp.z) < (m.sizeZ + part.Size.Z) / 2
				then
					rmMats += 1
				end
			end
			if count(part) > 2 then
				rmParts += 1
			end
		end
		-- 머리 위 글 거리: 물건 크기에 맞게 (60 ~ 400)
		local model = MapBuilder.getTarget(t.id)
		local gui = model and model.PrimaryPart and model.PrimaryPart:FindFirstChild("TargetInfo")
		local r = MapLayout.targetRadius(t.id)
		local wsT = MapLayout.worldScale(t.world)
		local want = math.clamp(r / wsT * 6, 60, 400) * wsT -- 배율 1 로 정한 거리 × 월드 배율
		if not (gui and math.abs(gui.MaxDistance - want) < 0.01) then
			rmInfo += 1
			print("    글 거리 틀림: " .. t.id)
		end
	end
	check(rmTag == 0, "물건 41개마다 길가 매트 (TrainMat 태그 · Attr World·TargetId · matPoint)")
	check(rmWalk == 0, string.format("matWalkDistance ≤ 6 (가장 먼 %.1f)", maxWalk))
	check(maxWalk == 0, "길가 매트 위에서 바로 칠 수 있음 (matWalkDistance 0)")
	check(rmOn == 0, "길가 매트 가운데 = isOnTrainMat true")
	check(rmTarget == 0, "길가 매트가 물건(실제 파트)과 안 겹침")
	check(rmRoad == 0, "길가 매트는 길 위 · 가운데 통로 비움 · 안 부딪힘")
	check(rmMats == 0, "길가 매트끼리 안 겹침")
	check(rmParts == 0, "길가 매트 파트 1~2개")
	check(rmInfo == 0, "TargetInfo MaxDistance = 반지름 × 6 (60~400)")
	check(
		MapLayout.matPoint("nope") == nil and MapLayout.matWalkDistance("nope") == math.huge,
		"모르는 id → matPoint nil · matWalkDistance huge"
	)
	local spr = MapLayout.spawn(1)
	check(not MapLayout.isOnTrainMat(Vector3.new(spr.x, 3, 58), 1), "정문 앞 길 가운데 → 매트 아님")
	for _, name in { "DumbbellShop", "BeltBoard", "ExamPad", "DuelArena" } do
		local list = CollectionService:GetTagged(Tags[name])
		local ok = #list == 3
		for _, m in list do
			local click = m:FindFirstChild("Click")
			if
				not (
					m:IsA("Model")
					and m.PrimaryPart
					and click
					and click:IsA("ClickDetector")
					and m:GetAttribute(A.World)
				)
			then
				ok = false
			end
		end
		check(ok, name .. " 3개 (Model · PrimaryPart · ClickDetector · Attr World)")
	end
	local doors = CollectionService:GetTagged(Tags.WorldDoor)
	local doorOk = #doors == 6
	for _, d in doors do
		local tw, w = d:GetAttribute(A.TargetWorld), d:GetAttribute(A.World)
		if not (tw and w and tw ~= w and d:FindFirstChild("Click") and d:FindFirstChild("Lock")) then
			doorOk = false
		end
	end
	check(doorOk, "WorldDoor 6개 (TargetWorld ≠ World · Click · Lock)")
	local spawns = CollectionService:GetTagged(Tags.WorldSpawn)
	check(#spawns == 3, "WorldSpawn 3개")
	local spawnOk = true
	for _, s in spawns do
		local w = s:GetAttribute(A.World)
		local want = MapLayout.spawn(w)
		local pos = s.CFrame.Position
		if math.abs(pos.X - want.x) > 0.1 or math.abs(pos.Z - want.z) > 0.1 then
			spawnOk = false
		end
	end
	check(spawnOk, "스폰 파트 자리 = MapLayout.spawn")
	check(
		spawns[1]:IsA("SpawnLocation") or spawns[2]:IsA("SpawnLocation") or spawns[3]:IsA("SpawnLocation"),
		"월드 1 스폰은 SpawnLocation"
	)

	print("[표지판이 스폰·매트를 안 가림]")
	local blocked = 0
	for _, tag in { "DumbbellShop", "BeltBoard", "ExamPad", "DuelArena", "WorldDoor" } do
		for _, m in CollectionService:GetTagged(Tags[tag]) do
			local w = m:GetAttribute(A.World)
			local keep = { spotRect(MapLayout.spawn(w), 2) }
			for _, mat in MapLayout.trainMats(w) do
				table.insert(keep, spotRect(mat, 1))
			end
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					local r = xzRect(d)
					for _, k in keep do
						if rectsOverlap(r, k) then
							blocked += 1
							print("    겹침: " .. tag .. "." .. d.Name .. " (월드 " .. w .. ")")
							break
						end
					end
				end
			end
		end
	end
	check(blocked == 0, "가게·띠판·심사대·대결장·문 파트가 스폰·매트 자리와 안 겹침")
	-- 서로도 안 겹침 (월드 1 기준: 모델 xz 범위)
	local boxes = {}
	for _, tag in { "DumbbellShop", "BeltBoard", "ExamPad", "DuelArena", "WorldDoor" } do
		for _, m in CollectionService:GetTagged(Tags[tag]) do
			if m:GetAttribute(A.World) == 1 then
				local all
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						local r = xzRect(d)
						all = if all
							then {
								x0 = math.min(all.x0, r.x0),
								x1 = math.max(all.x1, r.x1),
								z0 = math.min(all.z0, r.z0),
								z1 = math.max(all.z1, r.z1),
							}
							else r
					end
				end
				table.insert(boxes, { name = tag .. "/" .. m.Name, r = all })
			end
		end
	end
	local cross = 0
	for i = 1, #boxes do
		for j = i + 1, #boxes do
			if rectsOverlap(boxes[i].r, boxes[j].r) then
				cross += 1
				print("    서로 겹침: " .. boxes[i].name .. " ↔ " .. boxes[j].name)
			end
		end
	end
	check(cross == 0, "로비 시설끼리 안 겹침 (월드 1)")

	print("[심사·대결 송판]")
	local exam = CollectionService:GetTagged(Tags.ExamPad)[1]
	local rack = exam:FindFirstChild("Rack")
	local boardsOk = rack ~= nil
	for i = 1, 10 do
		if not (rack and rack:FindFirstChild("Board_" .. i)) then
			boardsOk = false
		end
	end
	check(boardsOk, "심사대 송판 Board_1..10")
	local duel = CollectionService:GetTagged(Tags.DuelArena)[1]
	local duelOk = duel:FindFirstChild("Mine") and duel:FindFirstChild("Theirs")
	for i = 1, 15 do
		if not (duelOk and duel.Mine:FindFirstChild("Mine_" .. i) and duel.Theirs:FindFirstChild("Theirs_" .. i)) then
			duelOk = false
		end
	end
	check(duelOk, "대결장 송판 Mine_1..15 · Theirs_1..15")
	local npc = duel:FindFirstChild("Examiner")
	check(
		npc and npc:FindFirstChild("Belt") and npc:FindFirstChild("Head") and npc.PrimaryPart,
		"시험관 NPC (머리·도복·띠)"
	)
	print("[사범님 3명]")
	local rigKinds = {}
	local exOk = true
	for _, arena in CollectionService:GetTagged(Tags.DuelArena) do
		local w = arena:GetAttribute(A.World)
		local ex = arena:FindFirstChild("Examiner")
		local spot = MapLayout.duelArena(w)
		local tag = ex and ex:FindFirstChild("NameTag", true)
		local nameLabel = tag and tag:FindFirstChild("Name")
		local nameText = nameLabel and nameLabel.Text or ""
		local blocks = false
		local onArena = true
		if ex then
			for _, d in ex:GetDescendants() do
				if d:IsA("BasePart") then
					if d.CanCollide then
						blocks = true
					end
					local p = d.CFrame.Position
					if
						math.abs(p.X - spot.x) > spot.sizeX / 2 + 1
						or math.abs(p.Z - spot.z) > spot.sizeZ / 2 + 1
						or p.Y < 0
					then
						onArena = false
					end
				end
			end
		end
		local kind = ex and ex:GetAttribute("Rig")
		table.insert(rigKinds, tostring(kind))
		local worldName = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Worlds")).get(w).examiner
		if
			not (
				ex
				and ex.PrimaryPart
				and ex:FindFirstChild("Belt")
				and ex:FindFirstChild("Head")
				and string.find(nameText, worldName, 1, true)
				and not blocks
				and onArena
			)
		then
			exOk = false
			print(
				string.format(
					"    사범님 월드 %d: %s 이름 '%s' 막음 %s 대결장 위 %s",
					w,
					tostring(kind),
					nameText,
					tostring(blocks),
					tostring(onArena)
				)
			)
		end
	end
	check(
		exOk and #rigKinds == 3,
		"사범님 3명: 띠·머리·이름표(Worlds 이름) · 대결장 위 · 안 부딪힘 ("
			.. table.concat(rigKinds, ",")
			.. ")"
	)
	local r15Count, blockCount = 0, 0
	for _, k in rigKinds do
		if k == "R15" then
			r15Count += 1
		elseif k == "block" then
			blockCount += 1
		end
	end
	check(r15Count == 1 and blockCount == 2, "R15 몸 입히기 경로 1 · API 없을 때 블록 대체 2")
	local r15 = nil
	for _, arena in CollectionService:GetTagged(Tags.DuelArena) do
		local ex = arena:FindFirstChild("Examiner")
		if ex and ex:GetAttribute("Rig") == "R15" then
			r15 = ex
		end
	end
	check(
		r15
			and r15.HumanoidRootPart.Anchored
			and r15.UpperTorso.Color == roblox.Color3.fromRGB(22, 22, 26)
			and r15:FindFirstChild("Collar")
			and r15:FindFirstChild("Hair")
			and r15:FindFirstChild("BeltKnot")
			and r15.Head:FindFirstChildOfClass("Decal"),
		"R15 사범님: 뿌리 고정 · 검은 도복(사장님 2026-11-16) · 깃 · 머리카락 · 띠 매듭 · 얼굴"
	)
	local foot = r15 and r15.LeftFoot.CFrame.Position.Y - 0.15
	check(foot and math.abs(foot - 0.6) < 0.05, "사범님 발이 대결장 바닥 위 (" .. tostring(foot) .. ")")

	print("[도장 천장]")
	local roofOk = true
	for w = 1, 3 do
		local lobby = map["World" .. w]:FindFirstChild("Lobby")
		local roof = lobby and lobby:FindFirstChild("Roof")
		local ceil = roof and roof:FindFirstChild("Ceiling")
		local rect = MapLayout.lobbyRect(w)
		local ws = MapLayout.worldScale(w)
		if not ceil then
			roofOk = false
			print("    천장 없음: 월드 " .. w)
		else
			local r = xzRect(ceil)
			local bottom = ceil.CFrame.Position.Y - ceil.Size.Y / 2
			if r.x0 > rect.x0 or r.x1 < rect.x1 or r.z0 > rect.z0 or r.z1 < rect.z1 or bottom < 18 * ws then
				roofOk = false
				print(string.format("    천장이 덜 덮음/낮음: 월드 %d 아랫면 %.1f", w, bottom))
			end
			local lamps = 0
			for _, d in roof:GetChildren() do
				if d.Name == "CeilingLamp" and d:FindFirstChildOfClass("PointLight") then
					lamps += 1
				end
			end
			if lamps < 4 then
				roofOk = false
				print("    천장 등 부족: 월드 " .. w)
			end
			-- 정문(가운데 x ±9, 높이 0~14)과 월드 문 앞(x ±3.5, 높이 0~9.5)은 비어 있어야 함
			local cx = (rect.x0 + rect.x1) / 2
			local holes =
				{ { x0 = cx - 9 * ws, x1 = cx + 9 * ws, z0 = rect.z1 - 2 * ws, z1 = rect.z1 + 3 * ws, y1 = 14 * ws } }
			for _, d in MapLayout.doors(w) do
				table.insert(
					holes,
					{ x0 = d.x - d.halfX, x1 = d.x + d.halfX, z0 = d.z - ws, z1 = d.z + 4 * ws, y1 = 9.5 * ws }
				)
			end
			for _, d in roof:GetDescendants() do
				if d:IsA("BasePart") then
					local pr = xzRect(d)
					local low = math.huge
					for _, pt in partCorners(d) do
						low = math.min(low, pt.Y)
					end
					for _, h in holes do
						if rectsOverlap(pr, h) and low < h.y1 then
							roofOk = false
							print("    문을 막음: 월드 " .. w .. " " .. d.Name)
						end
					end
				end
			end
		end
	end
	check(
		roofOk,
		"세 월드 도장 천장: 로비를 다 덮음 · 높이 ≥ 18 · 천장 등 · 정문·월드 문 뚫림"
	)

	do
		print("[도장 천장 높이 (사장님 결정 17번 — 천장만 겁나 높임)]")
		local SizesR = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Sizes"))
		local needClear = Dojo.CLEAR * SizesR.MAX_SCALE * SizesR.AVATAR_HEIGHT
		local clearOk, keepOk, lampOk, attrOk = true, true, true, true
		for w = 1, 3 do
			local ws = MapLayout.worldScale(w)
			local lobby = map["World" .. w].Lobby
			local ceil = lobby.Roof.Ceiling
			local bottom = ceil.CFrame.Position.Y - ceil.Size.Y / 2
			print(
				string.format(
					"    월드 %d: 천장 아랫면 %.1f (필요 %.1f = %.1f × 가장 큰 몸 %.1f) · 배율 1 숫자 %d",
					w,
					bottom,
					needClear,
					Dojo.CLEAR,
					SizesR.MAX_SCALE * SizesR.AVATAR_HEIGHT,
					Dojo.roofY(w)
				)
			)
			if bottom < needClear then
				clearOk = false
			end
			if math.abs((ceil:GetAttribute("RoofBottom") or -1) - bottom) > 0.01 then
				attrOk = false
			end
			-- 등은 옛 천장 높이(19)에 매달림 → 바닥 밝기 그대로
			for _, d in lobby.Roof:GetChildren() do
				if
					d.Name == "CeilingLamp"
					and math.abs(d.CFrame.Position.Y - (Dojo.LAMP_CEIL - 1) * ws) > 0.01 * ws
				then
					lampOk = false
				end
			end
			-- 쓰는 것들은 높이 그대로: 문 구멍 위 9.4 · 정문 간판 15 · 띠 표지판 위 16 (× 배율)
			for _, door in CollectionService:GetTagged(Tags.WorldDoor) do
				if door:GetAttribute(A.World) == w then
					local p = door.Portal
					if math.abs(p.CFrame.Position.Y + p.Size.Y / 2 - 9.4 * ws) > 0.01 * ws then
						keepOk = false
					end
				end
			end
			local gs = lobby:FindFirstChild("GateSign")
			if not gs or math.abs(gs.CFrame.Position.Y - 15 * ws) > 0.01 * ws then
				keepOk = false
			end
			for _, b in CollectionService:GetTagged(Tags.BeltBoard) do
				if b:GetAttribute(A.World) == w then
					local bp = b.PrimaryPart
					if math.abs(bp.CFrame.Position.Y + bp.Size.Y / 2 - 16 * ws) > 0.01 * ws then
						keepOk = false
					end
				end
			end
		end
		check(
			clearOk,
			string.format(
				"세 월드 천장 아랫면 ≥ 1.3 × 가장 큰 몸 키 = %.1f (진짜 스터드)",
				needClear
			)
		)
		check(attrOk, "Ceiling Attr RoofBottom = 진짜 천장 아랫면")
		check(
			lampOk,
			"천장 등은 옛 천장 높이(19 × 배율)에 매달림 — 빛 범위 60 안에 바닥 (밝기 그대로)"
		)
		check(keepOk, "문 구멍 · 정문 간판 · 띠 표지판 높이는 그대로 (천장만 높아짐)")
		local decor = { Banner = 0, ClerestoryWindow = 0, WallBand = 0, LampCord = 0 }
		for _, d in map.World1.Lobby.Roof:GetChildren() do
			if decor[d.Name] then
				decor[d.Name] += 1
			end
		end
		check(
			decor.Banner >= 5 and decor.ClerestoryWindow >= 8 and decor.WallBand >= 12 and decor.LampCord == 6,
			string.format(
				"월드 1 높은 윗벽 꾸밈: 태권도 현수막 %d · 채광창 %d · 나무 띠 %d · 등 끈 %d",
				decor.Banner,
				decor.ClerestoryWindow,
				decor.WallBand,
				decor.LampCord
			)
		)
		local pillarOk = true
		for _, d in map.World1.Lobby:GetChildren() do
			if d.Name == "Pillar" and d.CFrame.Position.Y + d.Size.Y / 2 < Dojo.roofY(1) then
				pillarOk = false
			end
		end
		check(pillarOk, "모서리 기둥이 새 천장까지 올라감")
	end

	print("[가게 진열 아령]")
	local Dumbbells = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Dumbbells"))
	local shopM = CollectionService:GetTagged(Tags.DumbbellShop)[1]
	local display = shopM:FindFirstChild("Display")
	local want = math.min(#Dumbbells.list, Dojo.SHOP_MAX)
	local shown = display and #display:GetChildren() or 0
	check(
		shown == want,
		string.format("진열 아령 = 표 길이 %d (상한 %d) → %d", #Dumbbells.list, Dojo.SHOP_MAX, shown)
	)
	local first = display and display:FindFirstChild("Dumbbell_1")
	check(
		first and first:GetAttribute("Classic") == true and count(first) == 5,
		"진열 1번 아령 = 무료 모델 Dumbell 모양 (원기둥 5개)"
	)

	print("[플레이어 아우라 (서버)]")
	local Visuals = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Visuals"))
	local PVS = requireNode(Loader.get("ServerScriptService/Server/Services/PlayerVisualService"))
	local edgeOk = Visuals.auraTier(99) == 0 and Visuals.auraTier(100) == 1 and Visuals.auraTier(9999) == 1
	for i, a in Visuals.AURA do
		if Visuals.auraTier(a.power) ~= i or (i > 1 and Visuals.auraTier(a.power * 0.999) ~= i - 1) then
			edgeOk = false
		end
	end
	check(
		edgeOk and Visuals.auraTier(0 / 0) == 0,
		"아우라 단계 경계값 (99→0 · 100→1 · 문턱마다 한 단계)"
	)
	local function fakeChar()
		local ch = Instance.new("Model")
		local rp = Instance.new("Part")
		rp.Name = "HumanoidRootPart"
		rp.Size = Vector3.new(2, 2, 1)
		rp.Parent = ch
		local hm = Instance.new("Humanoid")
		hm.Parent = ch
		ch.Parent = Workspace
		return ch
	end
	local ch = fakeChar()
	local t3 = PVS.apply(ch, 2e7)
	local attach = ch.HumanoidRootPart:FindFirstChild("AuraAttach")
	attach:SetAttribute("Mark", 1)
	PVS.apply(ch, 5e7)
	local same = ch.HumanoidRootPart:FindFirstChild("AuraAttach")
	check(
		t3 == 3 and same and same:GetAttribute("Mark") == 1,
		"단계가 그대로면 다시 만들지 않음 (2e7·5e7 → 3단계)"
	)
	local t4 = PVS.apply(ch, 2e10)
	local fresh = ch.HumanoidRootPart:FindFirstChild("AuraAttach")
	check(
		t4 == 4 and fresh:GetAttribute("Mark") == nil and ch:FindFirstChild("AuraRing"),
		"단계가 바뀌면 갈아 끼움 (+ 발밑 고리)"
	)
	local rateOk = true
	for i, a in Visuals.AURA do
		local c2 = fakeChar()
		PVS.apply(c2, a.power)
		local sum = 0
		for _, d in c2:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				sum += d.Rate
			end
		end
		if sum > Visuals.AURA_RATE_CAP or sum < 8 then
			rateOk = false
		end
	end
	check(rateOk, "단계마다 파티클 Rate 합 8 ~ " .. Visuals.AURA_RATE_CAP)
	local respawned = fakeChar()
	check(
		PVS.apply(respawned, 1e40) == #Visuals.AURA and respawned.HumanoidRootPart:FindFirstChild("AuraAttach"),
		"새 몸(리스폰)에도 붙음 · 끝 단계 1e40"
	)
	check(PVS.apply(fakeChar(), 5) == 0, "힘 100 미만 → 아우라 없음")

	do
		print("[띠 표지판 (사장님 결정 16번 — Belts.COUNT 개)]")
		local Belts = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Belts"))
		local BeltLook = requireNode(Loader.get("ReplicatedStorage/Shared/BeltLook"))
		for _, board in CollectionService:GetTagged(Tags.BeltBoard) do
			local w = board:GetAttribute(A.World)
			local sg = board.PrimaryPart and board.PrimaryPart:FindFirstChild("Sign")
			local grid = sg and sg.Board:FindFirstChild("Belts")
			local cellsOk, inside, overlapCells, gradOk = 0, true, 0, true
			local rects = {}
			for i = 1, Belts.COUNT do
				local cell = grid and grid:FindFirstChild("Belt_" .. i)
				if cell then
					cellsOk += 1
					local p, s = cell.Position, cell.Size
					local r = { x0 = p.X.Scale, x1 = p.X.Scale + s.X.Scale, z0 = p.Y.Scale, z1 = p.Y.Scale + s.Y.Scale }
					if
						r.x0 < 0
						or r.z0 < 0
						or r.x1 > 1 + 1e-6
						or r.z1 > 1 + 1e-6
						or p.X.Offset ~= 0
						or p.Y.Offset ~= 0
					then
						inside = false
						print(string.format("    표지판 밖: 월드 %d Belt_%d", w, i))
					end
					for _, o in rects do
						if rectsOverlap(r, o) then
							overlapCells += 1
						end
					end
					table.insert(rects, r)
					local stripe = cell:FindFirstChild("Stripe")
					local many = #BeltLook.colors(Belts.get(i)) > 1
					if not stripe or (many and not stripe:FindFirstChild("BeltGradient")) then
						gradOk = false
					end
				end
			end
			check(
				cellsOk == Belts.COUNT and inside and overlapCells == 0 and gradOk,
				string.format(
					"월드 %d 띠 표지판: Belt_1..%d 칸이 다 판 안 · 안 겹침 · 여러 색 띠는 그러데이션 (%d칸)",
					w,
					Belts.COUNT,
					cellsOk
				)
			)
		end
		local board1 = CollectionService:GetTagged(Tags.BeltBoard)[1]
		local top = board1.PrimaryPart.CFrame.Position.Y + board1.PrimaryPart.Size.Y / 2
		local ws1 = MapLayout.worldScale(board1:GetAttribute(A.World))
		check(
			top < Dojo.ROOF_Y * ws1,
			string.format("띠 표지판 위 끝 %.1f < 천장 %.0f", top / ws1, Dojo.ROOF_Y)
		)
		local rb = Belts.byId and Belts.byId("rainbow")
		if rb then
			check(#BeltLook.colors(rb) >= 6, "무지개 띠 = 무지개 6색")
		end
		local yt = Belts.byId and Belts.byId("youtube")
		if yt then
			local cell
			for _, d in board1:GetDescendants() do
				if d.Name == "Belt_" .. yt.index then
					cell = d
				end
			end
			local imgs = 0
			for _, d in cell and cell:GetDescendants() or {} do
				if d:IsA("ImageLabel") or d:IsA("Decal") then
					imgs += 1
				end
			end
			check(cell and imgs == 0, "유튜브 띠 칸: 이름 + 빨강·흰 천만 (그림·로고 없음)")
		end
	end
	print("[크기 (사장님 결정 13번) — 월드 배율 · 맵]")
	local Sizes = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Sizes"))
	local Build = requireNode(Loader.get("ServerScriptService/Server/Map/Build"))
	local function ser(v)
		if type(v) == "table" then
			local keys = {}
			for k in v do
				table.insert(keys, tostring(k))
			end
			table.sort(keys)
			local out = {}
			for _, k in keys do
				local val = v[k]
				if val == nil then
					val = v[tonumber(k)]
				end
				table.insert(out, k .. "=" .. ser(val))
			end
			return "{" .. table.concat(out, ",") .. "}"
		elseif type(v) == "number" then
			return string.format("%.6f", v)
		end
		return tostring(v)
	end
	local base = MapLayout.base
	local same1 = true
	for _, f in
		{
			"spawn",
			"trainMats",
			"roadMats",
			"dumbbellShop",
			"beltBoard",
			"examPad",
			"duelArena",
			"doors",
			"lobbyRect",
			"targetArea",
			"worldOrigin",
		}
	do
		if ser(MapLayout[f](1)) ~= ser(base[f](1)) then
			same1 = false
			print("    월드 1 다름: " .. f)
		end
	end
	for _, id in MapLayout.targetIds(1) do
		for _, f in { "targetPosition", "targetRadius", "targetReach", "roadPoint", "matPoint", "matWalkDistance" } do
			if ser(MapLayout[f](id)) ~= ser(base[f](id)) then
				same1 = false
				print("    월드 1 다름: " .. f .. " " .. id)
			end
		end
	end
	check(
		same1 and MapLayout.worldScale(1) == 1,
		"월드 1 = 배율 1 그대로 (자리·반지름·reach·매트·문 전부 옛 숫자와 같음)"
	)
	check(
		MapLayout.targetReach("cotton") == 2.5 * 1.35 + 8 and MapLayout.spawn(1).z == -36,
		"월드 1 숫자 그대로 (솜 reach 11.375 · 스폰 z -36)"
	)
	local scaledOk = true
	for w = 2, 3 do
		local s = MapLayout.worldScale(w)
		local o = MapLayout.worldOrigin(w).x
		if math.abs(s - Sizes.worldScale(w)) > 1e-9 then
			scaledOk = false
		end
		for _, id in MapLayout.targetIds(w) do
			local p, b = MapLayout.targetPosition(id), base.targetPosition(id)
			if
				math.abs(p.x - (o + (b.x - o) * s)) > 1e-6
				or math.abs(p.z - b.z * s) > 1e-6
				or math.abs(p.y - b.y * s) > 1e-6
				or math.abs(MapLayout.targetReach(id) - base.targetReach(id) * s) > 1e-6
				or math.abs(MapLayout.targetRadius(id) - base.targetRadius(id) * s) > 1e-6
				or MapLayout.matWalkDistance(id) ~= 0
			then
				scaledOk = false
				print("    배율 틀림: " .. id)
			end
		end
		local sp, bs = MapLayout.spawn(w), base.spawn(w)
		if math.abs(sp.sizeX - bs.sizeX * s) > 1e-6 or math.abs(sp.z - bs.z * s) > 1e-6 then
			scaledOk = false
		end
	end
	check(
		scaledOk,
		string.format(
			"월드 2·3 = 원점 기준 × worldScale (%.1f · %.1f): 자리·반지름·reach(여유 포함)·스폰 · 매트에서 바로 침",
			MapLayout.worldScale(2),
			MapLayout.worldScale(3)
		)
	)
	-- 실제로 지은 월드: 폴더 Attr Scale · 물건 자리 · 가장 긴 파트 · 월드끼리 거리
	local builtOk = true
	for w = 1, 3 do
		local f = map["World" .. w]
		if f:GetAttribute("Scale") ~= MapLayout.worldScale(w) then
			builtOk = false
		end
	end
	for _, t in Targets.list do
		local m = MapBuilder.getTarget(t.id)
		local p = MapLayout.targetPosition(t.id)
		local hb = m and m.PrimaryPart
		if
			not hb
			or math.abs(hb.CFrame.Position.X - p.x) > 0.05 -- float32: x 30,000 근처는 0.002 단위
			or math.abs(hb.CFrame.Position.Z - p.z) > 0.05
			or math.abs(m:GetAttribute("Radius") - MapLayout.targetRadius(t.id)) > 1e-6
		then
			builtOk = false
			print(
				string.format(
					"    지은 자리 틀림: %s hb %s want %.2f,%.2f r %s %s",
					t.id,
					tostring(hb and hb.CFrame.Position),
					p.x,
					p.z,
					tostring(m and m:GetAttribute("Radius")),
					tostring(MapLayout.targetRadius(t.id))
				)
			)
		end
	end
	check(
		builtOk,
		"지은 물건 41개 = MapLayout 자리(배율 곱함) · Attr Radius = targetRadius · 월드 폴더 Attr Scale"
	)
	local longest, which = MapBuilder.maxPartAxis()
	check(
		longest <= 2048,
		string.format("가장 긴 파트 축 %.0f ≤ 2048 (%s)", longest, which and which:GetFullName() or "-")
	)
	local boxes3 = {}
	for w = 1, 3 do
		local x0, x1, z0, z1, y1 = math.huge, -math.huge, math.huge, -math.huge, -math.huge
		for _, d in map["World" .. w]:GetDescendants() do
			if d:IsA("BasePart") then
				for _, pt in partCorners(d) do
					x0, x1 = math.min(x0, pt.X), math.max(x1, pt.X)
					z0, z1 = math.min(z0, pt.Z), math.max(z1, pt.Z)
					y1 = math.max(y1, pt.Y)
				end
			end
		end
		boxes3[w] = { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
		print(
			string.format(
				"    월드 %d (배율 %.1f, 원점 x %d): x %.0f..%.0f (%.0f) · z %.0f..%.0f (%.0f) · 가장 높은 곳 %.0f",
				w,
				MapLayout.worldScale(w),
				MapLayout.worldOrigin(w).x,
				x0,
				x1,
				x1 - x0,
				z0,
				z1,
				z1 - z0,
				y1
			)
		)
	end
	local gapMin = math.min(boxes3[2].x0 - boxes3[1].x1, boxes3[3].x0 - boxes3[2].x1)
	check(
		gapMin >= 3000,
		string.format("월드끼리 안 겹치고 멀리 (가장 가까운 틈 %.0f ≥ 3000)", gapMin)
	)
	local whereOk = true
	for w = 1, 3 do
		for _, d in map["World" .. w]:GetDescendants() do
			if d:IsA("BasePart") and MapLayout.worldAt(d.CFrame.Position) ~= w then
				whereOk = false
			end
		end
	end
	check(whereOk, "모든 파트가 자기 월드 땅 (worldAt)")
	-- 아파트 높이 = Sizes.APARTMENT_HEIGHT (마지막 아령 = 그 2배)
	local apt = MapBuilder.getTarget("apartment")
	local aptBase = MapLayout.targetPosition("apartment").y
	local aptTop = -math.huge
	for _, d in apt:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Hitbox" then
			for _, pt in partCorners(d) do
				aptTop = math.max(aptTop, pt.Y)
			end
		end
	end
	local aptH = aptTop - aptBase
	check(
		math.abs(aptH - Sizes.APARTMENT_HEIGHT) <= Sizes.APARTMENT_HEIGHT * 0.01,
		string.format(
			"지은 월드 1 아파트 높이 %.3f = Sizes.APARTMENT_HEIGHT %.3f (±1%%)",
			aptH,
			Sizes.APARTMENT_HEIGHT
		)
	)
	-- 빛·글·클릭 거리
	local lightOk, ppsOk, clickOk = true, true, true
	for w = 1, 3 do
		local ws = MapLayout.worldScale(w)
		for _, d in map["World" .. w]:GetDescendants() do
			if (d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight")) and d.Range > 60 then
				lightOk = false
			elseif d:IsA("SurfaceGui") and w == 3 and d.Name == "Sign" and d.PixelsPerStud > 40 / ws + 1e-6 then
				ppsOk = false
			end
		end
	end
	for _, t in Targets.list do
		local click = MapBuilder.getTarget(t.id):FindFirstChild("Click")
		if click.MaxActivationDistance < MapLayout.targetReach(t.id) + MapBuilder.CLICK_BODY_PAD then
			clickOk = false
		end
	end
	check(lightOk, "빛 범위 ≤ 60 (로블록스 상한)")
	check(ppsOk, "월드 3 표지판 글 픽셀 밀도 = 월드 1 ÷ 11 (같은 글자 크기·그림 메모리)")
	check(
		clickOk,
		"물건 ClickDetector 거리 ≥ targetReach(배율 곱함) + 몸 여유 " .. MapBuilder.CLICK_BODY_PAD
	)
	-- 거인이 안 끼임: 지붕 전체 + 문 위 들보 = GiantPass
	local passOk = true
	for w = 1, 3 do
		local roof = map["World" .. w].Lobby.Roof
		for _, d in roof:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("GiantPass") ~= true then
				passOk = false
			end
		end
	end
	for _, door in CollectionService:GetTagged(Tags.WorldDoor) do
		local l = door:FindFirstChild("Lintel")
		if not (l and l:GetAttribute("GiantPass") == true) then
			passOk = false
		end
	end
	check(
		passOk and Build.PASS_GROUP ~= nil and Build.PLAYER_GROUP ~= nil,
		"지붕·윗벽·천장·문 위 들보 = 플레이어 몸과 안 부딪힘 (GiantPass 충돌 그룹)"
	)
	for w = 1, 3 do
		local roofY = map["World" .. w].Lobby.Roof.Ceiling.CFrame.Position.Y
			- map["World" .. w].Lobby.Roof.Ceiling.Size.Y / 2
		local portal
		for _, door in CollectionService:GetTagged(Tags.WorldDoor) do
			if door:GetAttribute(A.World) == w then
				portal = door:FindFirstChild("Portal")
			end
		end
		print(
			string.format(
				"    월드 %d: 천장 아랫면 %.0f · 문 구멍 위 %.1f (가장 큰 몸 키 ≈ %.0f)",
				w,
				roofY,
				portal.CFrame.Position.Y + portal.Size.Y / 2,
				Sizes.AVATAR_HEIGHT * Sizes.MAX_SCALE
			)
		)
	end
	-- 엔진은 Part.Size 를 넣는 순간 한 축 2048 로 자름 (본부장 2026-11-16 스튜디오: 그 때문에 월드 2·3 바닥이 잘려 허공).
	--   Build.setSize 가 엔진과 똑같이 자르고 횟수를 셈 → 맵을 다 지은 뒤 0 이어야 함
	check(
		Build.clamped == 0,
		"맵 짓는 동안 엔진이 잘랐을 크기(한 축 > 2048)를 한 번도 안 넣음 ("
			.. Build.clamped
			.. ")"
	)
	do
		local probe = Instance.new("Part")
		local before = Build.clamped
		Build.setSize(probe, Vector3.new(3000, 2, 5))
		check(
			probe.Size.X == 2048 and Build.clamped == before + 1,
			"Build.setSize = 엔진처럼 2048 로 자름 (Lune 가짜에도 같은 규칙)"
		)
		Build.clamped = before
		probe:Destroy()
	end
	-- 바닥: 월드마다 Ground 조각이 worldRect 를 빈틈없이 덮고, 서는 자리 아래에 부딪히는 바닥이 있음
	local function aabb(p)
		local x0, x1, y1, z0, z1 = math.huge, -math.huge, -math.huge, math.huge, -math.huge
		for _, pt in partCorners(p) do
			x0, x1 = math.min(x0, pt.X), math.max(x1, pt.X)
			z0, z1 = math.min(z0, pt.Z), math.max(z1, pt.Z)
			y1 = math.max(y1, pt.Y)
		end
		return x0, x1, z0, z1, y1
	end
	for w = 1, 3 do
		local ws = MapLayout.worldScale(w)
		local floors, grounds = {}, {}
		for _, d in map["World" .. w]:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide then
				local x0, x1, z0, z1, top = aabb(d)
				local box = { x0 = x0, x1 = x1, z0 = z0, z1 = z1, top = top, name = d.Name }
				table.insert(floors, box)
				if d.Name == "Ground" then
					table.insert(grounds, box)
				end
			end
		end
		local rect = MapLayout.worldRect(w)
		local holes = 0
		local n = 40
		for i = 0, n do
			for j = 0, n do
				local x = rect.x0 + 0.5 + (rect.x1 - rect.x0 - 1) * i / n
				local z = rect.z0 + 0.5 + (rect.z1 - rect.z0 - 1) * j / n
				local hit = false
				for _, g in grounds do
					if x >= g.x0 and x <= g.x1 and z >= g.z0 and z <= g.z1 then
						hit = true
						break
					end
				end
				if not hit then
					holes += 1
				end
			end
		end
		check(
			holes == 0,
			string.format(
				"월드 %d 땅(Ground %d조각)이 worldRect %.0f × %.0f 를 빈틈없이 덮음 (빈 곳 %d / %d)",
				w,
				#grounds,
				rect.x1 - rect.x0,
				rect.z1 - rect.z0,
				holes,
				(n + 1) * (n + 1)
			)
		)
		-- 아래로 쏘기: 그 자리 바닥 높이(y0) 근처(-3·배율 ~ +10·배율)에 위가 있는 부딪히는 파트
		local function landed(x, y0, z)
			for _, f in floors do
				if
					x >= f.x0
					and x <= f.x1
					and z >= f.z0
					and z <= f.z1
					and f.top <= y0 + 10 * ws
					and f.top >= y0 - 3 * ws
				then
					return true
				end
			end
			return false
		end
		local spots = {}
		for _, id in MapLayout.targetIds(w) do
			local p = MapLayout.targetPosition(id)
			table.insert(spots, { "물건 " .. id, p.x, p.y, p.z })
			local rp = MapLayout.roadPoint(id)
			table.insert(spots, { "길 " .. id, rp.x, 0, rp.z })
		end
		for _, m in MapLayout.roadMats(w) do
			table.insert(spots, { "길가 매트 " .. m.targetId, m.x, 0, m.z })
		end
		for i, m in MapLayout.trainMats(w) do
			table.insert(spots, { "도장 매트 " .. i, m.x, 0, m.z })
		end
		local sp, ep, da = MapLayout.spawn(w), MapLayout.examPad(w), MapLayout.duelArena(w)
		table.insert(spots, { "스폰", sp.x, 0, sp.z })
		table.insert(spots, { "심사대", ep.x, 0, ep.z })
		table.insert(spots, { "대결장", da.x, 0, da.z })
		for _, d in MapLayout.doors(w) do
			table.insert(spots, { "포털 → " .. d.world, d.x, 0, d.z + d.front / 2 })
		end
		local fell = {}
		for _, s in spots do
			if not landed(s[2], s[3], s[4]) then
				table.insert(fell, s[1])
			end
		end
		check(
			#fell == 0,
			string.format(
				"월드 %d: 서는 자리 %d곳(물건·길·길가 매트·도장 매트·스폰·심사대·대결장·포털) 아래에 부딪히는 바닥%s",
				w,
				#spots,
				if #fell > 0 then " — 없음: " .. table.concat(fell, ", ") else ""
			)
		)
	end

	-- 투명벽 (사장님 결정 19번: "맵은 투명벽으로 사방이 막혀있어")
	do
		print("[투명벽 (결정 19번)]")
		local SizesW = requireNode(Loader.get("ReplicatedStorage/Shared/Data/Sizes"))
		local needH = 3 * (SizesW.jumpHeight(SizesW.MAX_SCALE) + SizesW.MAX_SCALE * SizesW.AVATAR_HEIGHT)
		local halfW = SizesW.MAX_SCALE * 1.45 -- 가장 큰 몸 반 너비 (보통 몸 너비 2 × 너비 배율(근육 1) ÷ 2)
		for w = 1, 3 do
			local ws = MapLayout.worldScale(w)
			local wf = map["World" .. w]
			local walls, grounds = {}, {}
			local propOk, maxW, lowest, highest = true, 0, math.huge, -math.huge
			local groundBottom = math.huge
			for _, d in wf:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "BoundaryWall" then
					local x0, x1, z0, z1, top = aabb(d)
					local bottom = d.CFrame.Position.Y - d.Size.Y / 2
					table.insert(walls, { x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
					lowest = math.min(lowest, bottom)
					highest = math.min(if highest == -math.huge then math.huge else highest, top)
					maxW = math.max(maxW, d.Size.X, d.Size.Y, d.Size.Z)
					if
						d.Transparency ~= 1
						or not d.CanCollide
						or d.CanQuery
						or d.CanTouch
						or d.CastShadow
						or d:GetAttribute("GiantPass")
						or d.CollisionGroup == Build.PASS_GROUP
						or d.Parent.Name ~= "Boundary"
					then
						propOk = false
					end
				elseif d:IsA("BasePart") and d.Name == "Ground" then
					local x0, x1, z0, z1 = aabb(d)
					table.insert(grounds, { x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
					groundBottom = math.min(groundBottom, d.CFrame.Position.Y - d.Size.Y / 2)
				end
			end
			check(
				#walls >= 4 and propOk,
				string.format(
					"월드 %d 투명벽 %d조각: 안 보임 · 그림자 없음 · 부딪힘 · GiantPass 아님 · CanQuery/CanTouch 꺼짐",
					w,
					#walls
				)
			)
			check(
				highest >= needH and lowest < groundBottom and maxW <= 2048,
				string.format(
					"월드 %d 벽 높이 %.0f ≥ %.0f (3 × (가장 큰 점프 + 키)) · 아래 끝 %.1f < 땅 아랫면 %.1f · 가장 긴 축 %.0f ≤ 2048",
					w,
					highest,
					needH,
					lowest,
					groundBottom,
					maxW
				)
			)
			local function inAny(list, x, z)
				for _, b in list do
					if x >= b.x0 and x <= b.x1 and z >= b.z0 and z <= b.z1 then
						return true
					end
				end
				return false
			end
			-- 스폰에서 16 방향으로 걸어 나가면 땅을 벗어나기 전에 벽
			local sp = MapLayout.spawn(w)
			local escaped = {}
			for k = 0, 15 do
				local a = k * math.pi / 8
				local dx, dz = math.cos(a), math.sin(a)
				local step = 0.5 * ws
				local hitWall = false
				for i = 1, 40000 do
					local x, z = sp.x + dx * step * i, sp.z + dz * step * i
					if inAny(walls, x, z) then
						hitWall = true
						break
					elseif not inAny(grounds, x, z) then
						break
					end
				end
				if not hitWall then
					table.insert(escaped, tostring(k * 22.5) .. "°")
				end
			end
			check(
				#escaped == 0,
				string.format(
					"월드 %d: 스폰에서 16 방향 모두 땅을 벗어나기 전에 벽%s",
					w,
					if #escaped > 0 then " — 빠져나감: " .. table.concat(escaped, ", ") else ""
				)
			)
			-- 모서리 닫힘: 땅 네 모서리 바로 바깥(대각선)이 벽 안
			local rect = MapLayout.worldRect(w)
			local tt = MapBuilder.WALL_THICK * ws
			local cornerOk = true
			for _, c in
				{
					{ rect.x0, rect.z0, -1, -1 },
					{ rect.x1, rect.z0, 1, -1 },
					{ rect.x0, rect.z1, -1, 1 },
					{ rect.x1, rect.z1, 1, 1 },
				}
			do
				if not inAny(walls, c[1] + c[3] * tt / 2, c[2] + c[4] * tt / 2) then
					cornerOk = false
				end
			end
			check(cornerOk, "월드 " .. w .. " 벽 네 모서리가 닫힘 (두께 " .. tt .. ")")
			-- 쓰는 자리는 전부 벽 안, 가장 큰 몸 반 너비 이상 떨어짐
			local spots = {}
			for _, id in MapLayout.targetIds(w) do
				local p = MapLayout.targetPosition(id)
				local r = MapLayout.targetRadius(id) * MapLayout.FOOTPRINT
				table.insert(spots, { id, p.x, p.z, r })
			end
			for _, m in MapLayout.roadMats(w) do
				table.insert(spots, { "길가 매트 " .. m.targetId, m.x, m.z, 0 })
			end
			for i, m in MapLayout.trainMats(w) do
				table.insert(spots, { "도장 매트 " .. i, m.x, m.z, 0 })
			end
			local ep, da = MapLayout.examPad(w), MapLayout.duelArena(w)
			table.insert(spots, { "스폰", sp.x, sp.z, 0 })
			table.insert(spots, { "심사대", ep.x, ep.z, 0 })
			table.insert(spots, { "대결장", da.x, da.z, 0 })
			for _, d in MapLayout.doors(w) do
				table.insert(spots, { "포털 → " .. d.world, d.x, d.z, 0 })
			end
			local tight = {}
			for _, s in spots do
				local m = math.min(s[2] - rect.x0, rect.x1 - s[2], s[3] - rect.z0, rect.z1 - s[3]) - s[4]
				if m < halfW then
					table.insert(tight, string.format("%s %.1f", s[1], m))
				end
			end
			check(
				#tight == 0,
				string.format(
					"월드 %d: 물건(가장자리)·매트·심사대·대결장·포털·스폰 %d곳 모두 벽 안쪽 %.1f 이상%s",
					w,
					#spots,
					halfW,
					if #tight > 0 then " — 가까움: " .. table.concat(tight, ", ") else ""
				)
			)
		end
	end

	-- 큰 월드가 어둡지 않게 (본부장 2026-11-16: 월드 3 도장 안이 거의 까맘)
	local function lum(col)
		return (col.R + col.G + col.B) / 3
	end
	local shadowOk = true
	for w = 1, 3 do
		for _, d in map["World" .. w].Lobby.Roof:GetDescendants() do
			if d:IsA("BasePart") and d.CastShadow then
				shadowOk = false
				print("    그림자 드리움: 월드 " .. w .. " " .. d.Name)
			end
		end
	end
	check(
		shadowOk,
		"세 월드 도장 지붕은 그림자를 안 드리움 (해·하늘빛이 안으로 — 천장이 높아져도 바닥 밝기 그대로)"
	)
	local lobby3 = map.World3.Lobby
	local glow, glowBad = 0, false
	for _, d in lobby3:GetChildren() do
		if d.Name == "GlowTrim" then
			glow += 1
			if d.Material ~= roblox.Enum.Material.Neon or d.CanCollide or d.CastShadow then
				glowBad = true
			end
		end
	end
	check(
		glow >= 8 and not glowBad,
		"월드 3 도장 벽 아래·위 네온 띠 " .. glow .. "개 (스스로 빛남 · 안 부딪힘)"
	)
	local inside = {
		{ "바닥", lobby3:FindFirstChild("DojoFloor") },
		{ "왼쪽 벽", lobby3:FindFirstChild("WallL") },
		{ "뒤 벽", lobby3:FindFirstChild("WallB") },
		{ "천장", lobby3.Roof:FindFirstChild("Ceiling") },
	}
	local brightOk = true
	for _, e in inside do
		local p = e[2]
		if not p or lum(p.Color) < 0.35 or p.Material == roblox.Enum.Material.Metal then
			brightOk = false
			print(string.format("    어두움: 월드 3 %s %s", e[1], p and tostring(p.Color) or "없음"))
		end
	end
	check(
		brightOk,
		"월드 3 도장 바닥·벽·천장 = 밝은 색 (≥ 0.35) · 어두운 곳에서 검게 보이는 Metal 아님"
	)
	local roadOk, groundOk, pedOk = true, true, true
	for _, d in map.World3:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Road" and (d.Transparency > 0 or lum(d.Color) < 0.3) then
			roadOk = false
		elseif d:IsA("BasePart") and d.Name == "Ground" and lum(d.Color) < 0.15 then
			groundOk = false
		end
	end
	for _, t in Targets.byWorld(3) do
		local ped = MapBuilder.getTarget(t.id):FindFirstChild("Pedestal")
		if not ped or lum(ped.Color) < 0.4 then
			pedOk = false
		end
	end
	check(
		roadOk and groundOk and pedOk,
		"월드 3 밖: 길 불투명·밝음 (≥ 0.3) · 땅 짙은 남색 (≥ 0.15) · 받침대 밝음 (≥ 0.4) — 하늘은 그대로 깜깜"
	)

	-- 포털 칸 (사장님 결정 15번)
	local doorOk = true
	for w = 1, 3 do
		local ws = MapLayout.worldScale(w)
		for _, d in MapLayout.doors(w) do
			if MapLayout.doorAt({ x = d.x, y = 3 * ws, z = d.z + 0.3 * ws }, w) ~= d.world then
				doorOk = false
				print("    포털 안인데 아님: 월드 " .. w .. " → " .. d.world)
			end
		end
		local sp = MapLayout.spawn(w)
		for _, body in { 1, ws, Sizes.MAX_SCALE } do
			if MapLayout.doorAt({ x = sp.x, y = 3 * body, z = sp.z }, w, body) ~= nil then
				doorOk = false
				print(string.format("    스폰이 포털 안: 월드 %d 몸 %.1f", w, body))
			end
		end
		if MapLayout.doorAt({ x = sp.x, y = 3 * ws, z = sp.z + 30 * ws }, w) ~= nil then
			doorOk = false
		end
	end
	check(
		doorOk,
		"포털 칸: 문 안 = 그 월드 · 스폰(보통 몸 · 그 월드 몸 · 가장 큰 몸)은 포털 밖 (도착해도 바로 안 돌아감)"
	)

	print("[크기 — 몸 · 근육 · 아령 (서버 PlayerVisualService)]")
	local DumbbellLook2 = requireNode(Loader.get("ReplicatedStorage/Shared/DumbbellLook"))
	local lastLv = #Dumbbells.list
	check(
		math.abs(DumbbellLook2.barLength(lastLv, 1) - (Sizes.LAST_DUMBBELL_LENGTH or 2.42)) < 1e-6,
		string.format(
			"마지막 아령 봉 길이 (배율 1) %.3f = Sizes.LAST_DUMBBELL_LENGTH",
			DumbbellLook2.barLength(lastLv, 1)
		)
	)
	local finalK = Sizes.MAX_SCALE * Sizes.dumbbellScale(lastLv)
	local finalModel = DumbbellLook2.build(nil, lastLv, finalK, false)
	local finalLen = 0
	for _, p in finalModel:GetDescendants() do
		if p:IsA("BasePart") then
			finalLen = math.max(finalLen, p.Size.X, p.Size.Y, p.Size.Z)
		end
	end
	local wantFinal = 2 * Sizes.APARTMENT_HEIGHT
	check(
		math.abs(finalLen - wantFinal) <= wantFinal * 0.02,
		string.format(
			"가장 큰 몸 + 마지막 아령: 실제로 만든 봉 %.2f = 아파트 높이 × 2 %.2f (±2%%)",
			finalLen,
			wantFinal
		)
	)
	local noCollide = true
	for _, p in finalModel:GetDescendants() do
		if p:IsA("BasePart") and (p.CanCollide or p.CanTouch or p.CanQuery or p.Anchored) then
			noCollide = false
		end
	end
	check(noCollide, "손 아령은 안 부딪힘 · 안 맞음 · 고정 안 됨 (75 스터드여도)")
	local function r15Char(heightBase)
		local ch = fakeChar()
		local hm = ch:FindFirstChildOfClass("Humanoid")
		hm.RigType = roblox.Enum.HumanoidRigType.R15
		local v = Instance.new("NumberValue")
		v.Name = "BodyHeightScale"
		v.Value = heightBase or 1
		v.Parent = hm
		return ch, hm
	end
	local chB, hmB = r15Char(1.05)
	local sc = PVS.applyBody(chB, 10, 1)
	local function val(name)
		local v = hmB:FindFirstChild(name)
		return v and v.Value or -1
	end
	local shape = PVS.bodyShape(10, 1)
	check(
		sc == 10
			and math.abs(val("BodyHeightScale") - 10 * 1.05) < 1e-6
			and math.abs(val("BodyWidthScale") - shape.width) < 1e-6
			and math.abs(val("BodyDepthScale") - shape.depth) < 1e-6
			and math.abs(val("HeadScale") - shape.head) < 1e-6
			and chB:GetAttribute("VisualScale") == 10,
		string.format(
			"R15 몸 배율 10 · 근육 1 → 키 %.2f (원래 1.05 × 10) · 너비 %.1f · 깊이 %.1f · 머리 %.1f (머리는 덜 큼)",
			val("BodyHeightScale"),
			val("BodyWidthScale"),
			val("BodyDepthScale"),
			val("HeadScale")
		)
	)
	check(
		shape.width > shape.height and shape.depth > shape.height and shape.head < shape.height,
		"근육 = 어깨·가슴·팔다리 넓고 두꺼움 · 머리는 몸보다 덜 커짐"
	)
	local s0 = PVS.bodyShape(1, 0)
	check(
		s0.height == 1 and s0.width == 1 and s0.depth == 1 and s0.head == 1,
		"힘 0 (배율 1 · 근육 0) = 원래 몸 그대로"
	)
	hmB:FindFirstChild("BodyWidthScale"):SetAttribute("Mark", 1)
	local w0 = val("BodyWidthScale")
	PVS.applyBody(chB, 10, 1)
	check(val("BodyWidthScale") == w0, "같은 배율이면 아무것도 다시 안 씀 (깜빡임 없음)")
	PVS.applyBody(chB, 10.2, 1)
	check(
		math.abs(val("BodyHeightScale") - 10.2 * 1.05) < 1e-6,
		"2% 커지면 값만 바꿈 (원래 비율 1.05 는 기억)"
	)
	-- 두 번 곱하기 없음 (본부장 2026-11-16 스튜디오: 리스폰 뒤 키 10.98² = 120.6). 아바타 로딩 = 크기 값 4개를 그 사람 값으로 덮어씀
	local AVATAR = { BodyHeightScale = 1.05, BodyWidthScale = 0.9, BodyDepthScale = 1, HeadScale = 0.95 }
	local function freshR15(startValues)
		local ch = fakeChar()
		local hm = ch:FindFirstChildOfClass("Humanoid")
		hm.RigType = roblox.Enum.HumanoidRigType.R15
		for _, name in PVS.SCALE_VALUES do
			local v = Instance.new("NumberValue")
			v.Name = name
			v.Value = if startValues then startValues[name] else 1
			v.Parent = hm
		end
		return ch, hm
	end
	local function appearanceLoads(hm)
		for name, value in AVATAR do
			hm:FindFirstChild(name).Value = value
		end
	end
	local function exact(hm, scale, muscle)
		local sh = PVS.bodyShape(scale, muscle)
		local mult =
			{ BodyHeightScale = sh.height, BodyWidthScale = sh.width, BodyDepthScale = sh.depth, HeadScale = sh.head }
		local bad = {}
		for name, orig in AVATAR do
			local got = hm:FindFirstChild(name).Value
			if math.abs(got - orig * mult[name]) > 1e-4 then
				table.insert(bad, string.format("%s %.3f (기대 %.3f)", name, got, orig * mult[name]))
			end
		end
		return #bad == 0, table.concat(bad, " · ")
	end
	local S = 10.98
	-- 1) 리스폰 (본부장이 본 순서): 아바타 값이 이미 들어온 새 몸 → 키움 → 아바타 로딩 끝 신호(값은 그대로) → 다시 맞춤 × 3
	local c1, h1 = freshR15(AVATAR)
	PVS.applyBody(c1, S, 0.6)
	for _ = 1, 3 do
		PVS.applyBody(c1, S, 0.6) -- CharacterAppearanceLoaded · BodyScale · Muscle 이벤트가 몇 번 와도
	end
	local ok1, why1 = exact(h1, S, 0.6)
	check(
		ok1,
		"리스폰: 아바타가 먼저 들어온 몸을 여러 번 맞춰도 원래 × " .. S .. " 한 번만 " .. why1
	)
	-- 2) 첫 접속 (실제 서버 순서): 기본값 1 인 몸 → 키움 → 그 뒤에 아바타 로딩이 값을 덮어씀 → 다시 맞춤
	local c2, h2 = freshR15(nil)
	PVS.applyBody(c2, S, 0.6)
	appearanceLoads(h2)
	PVS.applyBody(c2, S, 0.6)
	PVS.applyBody(c2, S, 0.6)
	local ok2, why2 = exact(h2, S, 0.6)
	check(
		ok2,
		"첫 접속: 키운 뒤 아바타가 늦게 들어와도 아바타 값 × " .. S .. " 한 번만 " .. why2
	)
	-- 3) 그 몸이 커짐 (12) → 작아짐 (5) → 다시 S: 언제나 아바타 값 × 그 배율
	PVS.applyBody(c2, 12, 0.8)
	PVS.applyBody(c2, 5, 0.3)
	PVS.applyBody(c2, S, 0.6)
	local ok3, why3 = exact(h2, S, 0.6)
	check(ok3, "커졌다 작아졌다 해도 원래 값은 그대로 (× 배율 한 번) " .. why3)
	-- 4) 리스폰: 새 몸(값 1)에서 다시 — 앞 몸의 기억이 안 섞임, 아바타는 늦게
	local c4, h4 = freshR15(nil)
	PVS.applyBody(c4, S, 0.6)
	PVS.applyBody(c4, S, 0.6)
	appearanceLoads(h4)
	PVS.applyBody(c4, S, 0.6)
	local ok4, why4 = exact(h4, S, 0.6)
	check(ok4, "새 몸 + 늦은 아바타 로딩 뒤에도 정확 " .. why4)
	check(
		h4:FindFirstChild("BodyHeightScale").Value < Sizes.MAX_SCALE * 1.2,
		string.format(
			"키 값이 배율 상한 근처 (%.2f — 120 같은 두 번 곱한 값 아님)",
			h4:FindFirstChild("BodyHeightScale").Value
		)
	)

	-- 5) 진짜 이벤트 순서로 (PlayerVisualService.watch — CharacterAdded · CharacterAppearanceLoaded · Attr 바뀜)
	local function sig()
		local hs = {}
		return {
			Connect = function(_, fn)
				table.insert(hs, fn)
				return {
					Disconnect = function()
						local i = table.find(hs, fn)
						if i then
							table.remove(hs, i)
						end
					end,
				}
			end,
			Fire = function(_, ...)
				for _, h in table.clone(hs) do
					h(...)
				end
			end,
		}
	end
	local fp = {
		Character = nil,
		attrs = { BodyScale = S, Muscle = 0.6, Power = 0 },
		sigs = {},
		CharacterAdded = sig(),
		CharacterAppearanceLoaded = sig(),
	}
	function fp:GetAttribute(k)
		return self.attrs[k]
	end
	function fp:GetAttributeChangedSignal(k)
		self.sigs[k] = self.sigs[k] or sig()
		return self.sigs[k]
	end
	function fp:SetAttribute(k, v)
		self.attrs[k] = v
		if self.sigs[k] then
			self.sigs[k]:Fire()
		end
	end
	PVS.watch(fp)
	-- 리스폰 (아바타가 먼저): CharacterAdded → 키움 → CharacterAppearanceLoaded (값 그대로) → 다시
	local c5, h5 = freshR15(AVATAR)
	fp.Character = c5
	fp.CharacterAdded:Fire(c5)
	fp.CharacterAppearanceLoaded:Fire(c5)
	fp:SetAttribute("Power", 1e20)
	fp.CharacterAppearanceLoaded:Fire(c5)
	local ok5, why5 = exact(h5, S, 0.6)
	check(
		ok5,
		"이벤트 순서 (리스폰: 아바타 먼저 → 키움 → 로딩 끝 신호 ×2 · 힘 바뀜): 원래 × 배율 한 번 "
			.. why5
	)
	-- 첫 접속 (아바타가 나중): CharacterAdded → 키움 → 아바타 값이 덮어씀 → CharacterAppearanceLoaded
	local c6, h6 = freshR15(nil)
	fp.Character = c6
	fp.CharacterAdded:Fire(c6)
	appearanceLoads(h6)
	fp.CharacterAppearanceLoaded:Fire(c6)
	fp.CharacterAppearanceLoaded:Fire(c6)
	local ok6, why6 = exact(h6, S, 0.6)
	check(
		ok6,
		"이벤트 순서 (첫 접속: 키움 → 아바타가 덮어씀 → 로딩 끝 신호 ×2): 아바타 값 × 배율 한 번 "
			.. why6
	)
	fp:SetAttribute("BodyScale", 12)
	fp:SetAttribute("BodyScale", S)
	local ok7, why7 = exact(h6, S, 0.6)
	check(ok7, "그 뒤 몸 배율이 바뀌었다 돌아와도 정확 " .. why7)
	PVS.unwatch(fp)

	-- 아우라도 몸 배율로 (다시 안 만들고 크기만)
	local chA = fakeChar()
	PVS.apply(chA, 2e7)
	local attachA = chA.HumanoidRootPart:FindFirstChild("AuraAttach")
	attachA:SetAttribute("Mark", 1)
	PVS.rememberBase(chA, chA.HumanoidRootPart)
	chA:SetAttribute("VisualScale", 10)
	PVS.apply(chA, 2e7)
	local ringA = PVS.ringPart(chA)
	local lightA = chA.HumanoidRootPart:FindFirstChild("AuraLight")
	local same3 = chA.HumanoidRootPart:FindFirstChild("AuraAttach")
	check(
		same3:GetAttribute("Mark") == 1
			and math.abs(same3.Position.Y - -15) < 1e-6
			and ringA
			and (ringA.Size - PVS.ringSize(10, 0, 3)).Magnitude < 1e-3
			and (not lightA or lightA.Range <= 60),
		string.format(
			"몸 배율 10 → 아우라 그대로 두고 크기만 (고리 지름 %.1f · 높이 %.0f · 빛 ≤ 60)",
			ringA and ringA.Size.Y or -1,
			same3.Position.Y
		)
	)

	-- 발밑 고리 (본부장 2026-11-16 스튜디오: 배율 10.98 에서 675 × 972 타원 — 엔진이 캐릭터 바로 아래 파트를 한 번 더 키움)
	print("[아우라 고리 — 몸 너비만큼 둥글게 · 한 번만]")
	local holderA = chA:FindFirstChild("AuraRing")
	check(
		holderA and holderA:IsA("Model") and not holderA:IsA("BasePart") and ringA and ringA.Parent == holderA,
		"고리 파트는 캐릭터 바로 아래가 아님 (Model AuraRing 안 Ring) — 엔진 R15 자동 크기 조절은 바로 아래 파트만 키움"
	)
	local origA = same3:FindFirstChild("OriginalPosition")
	check(
		origA and origA:IsA("Vector3Value") and origA.Value == Vector3.new(0, -1.5, 0),
		"AuraAttach OriginalPosition = 배율 1 자리 (엔진이 옮겨도 0, -1.5 × 키 배율 — 한 번만)"
	)
	local ringRule, roundOk, onceOk = true, true, true
	local worst = ""
	local tierN = #Visuals.AURA
	for _, case in { { 1, 0 }, { 2.5, 0.2 }, { 5.6, 0.5 }, { 10.98, 0.8 }, { Sizes.MAX_SCALE, 1 } } do
		local sc, mu = case[1], case[2]
		local chR = fakeChar()
		chR:SetAttribute("VisualScale", sc)
		chR:SetAttribute("VisualMuscle", mu)
		PVS.apply(chR, Visuals.AURA[tierN].power)
		PVS.apply(chR, Visuals.AURA[tierN].power) -- 두 번
		local r = PVS.ringPart(chR)
		local want = PVS.ringSize(sc, mu, tierN)
		local bodyW = 2 * PVS.bodyShape(sc, mu).width -- 보통 몸 너비 ≈ 2 × 너비 배율
		if not r or (r.Size - want).Magnitude > 1e-3 then
			onceOk = false
			worst = string.format("배율 %.2f: %s (기대 %s)", sc, tostring(r and r.Size), tostring(want))
		elseif math.abs(r.Size.Y - r.Size.Z) > 1e-6 then
			roundOk = false
		elseif r.Size.Y < bodyW or r.Size.Y > bodyW * 2 or r.Size.Y > Sizes.AVATAR_HEIGHT * sc then
			ringRule = false
			worst = string.format("배율 %.2f: 지름 %.1f · 몸 너비 %.1f", sc, r.Size.Y, bodyW)
		end
		-- 누가(엔진) 고리를 키워 버려도 다음 갱신에서 정한 크기로 되돌림
		if r then
			r.Size = Vector3.new(r.Size.X * 14.93, r.Size.Y * 10.98, r.Size.Z * 15.81)
			PVS.apply(chR, Visuals.AURA[tierN].power)
			if (r.Size - want).Magnitude > 1e-3 then
				onceOk = false
				worst = "남이 키운 고리를 안 되돌림 " .. tostring(r.Size)
			end
		end
		-- 리스폰: 새 몸
		local chN = fakeChar()
		chN:SetAttribute("VisualScale", sc)
		chN:SetAttribute("VisualMuscle", mu)
		PVS.apply(chN, Visuals.AURA[tierN].power)
		local rn = PVS.ringPart(chN)
		if not rn or (rn.Size - want).Magnitude > 1e-3 then
			onceOk = false
			worst = "리스폰 새 몸 고리 " .. tostring(rn and rn.Size)
		end
	end
	check(
		onceOk,
		"고리 크기 = ringSize(배율, 근육, 단계) 한 번만 (두 번 맞춰도 · 엔진이 키워도 되돌림 · 리스폰) "
			.. worst
	)
	check(roundOk, "고리는 늘 동그라미 (지름 두 축이 같음 — 근육이 붙어도 타원 아님)")
	check(ringRule, "고리 지름 = 몸 너비의 1 ~ 2배 (몸 키보다 작음) " .. worst)
	local rr = PVS.ringPart(fakeChar())
	check(
		PVS.RING_TRANSPARENCY >= 0.75,
		"고리 투명 "
			.. PVS.RING_TRANSPARENCY
			.. " (네온이 바닥을 하얗게 덮지 않게 — 월드 3 밝기 보정 +0.4)"
	)
	check(rr == nil, "아우라 없는 몸(힘 0)에는 고리 없음")
	-- 몸 배율이 바뀌면 다시 만들지 않고 맞춤 (근육만 바뀌어도)
	local chM = fakeChar()
	PVS.apply(chM, 2e7)
	PVS.ringPart(chM):SetAttribute("Mark", 1)
	chM:SetAttribute("VisualScale", 6)
	chM:SetAttribute("VisualMuscle", 0.4)
	PVS.apply(chM, 2e7)
	chM:SetAttribute("VisualMuscle", 0.9)
	PVS.apply(chM, 2e7)
	local rm = PVS.ringPart(chM)
	check(
		rm:GetAttribute("Mark") == 1 and (rm.Size - PVS.ringSize(6, 0.9, 3)).Magnitude < 1e-3,
		"근육만 바뀌어도 같은 고리를 새 크기로 (다시 안 만듦)"
	)
	-- 사범님 이름표: 큰 월드에서 길 위 물건 글과 안 겹치게 (도장 안·정문 앞에서만)
	local tagOk = true
	for _, arena in CollectionService:GetTagged(Tags.DuelArena) do
		local w = arena:GetAttribute(A.World)
		local tag = arena:FindFirstChild("NameTag", true)
		local want = Dojo.NAME_TAG_DISTANCE[w] * MapLayout.worldScale(w)
		if not tag or math.abs(tag.MaxDistance - want) > 1e-3 then
			tagOk = false
		end
	end
	check(
		tagOk,
		"사범님 이름표 거리 = 월드 1 그대로 90 · 큰 월드 50 × 배율 (월드 3 = 550 — 화성 매트 ≈ 800 에서는 안 보임)"
	)
end

local ok, err = pcall(body)
if not ok then
	failures += 1
	print("  FAIL 실행 오류: " .. tostring(err))
end
print(if failures == 0 then "\nsmoke_visuals: 전부 통과" else string.format("\nsmoke_visuals: 실패 %d", failures))
process.exit(if failures == 0 then 0 else 1)
