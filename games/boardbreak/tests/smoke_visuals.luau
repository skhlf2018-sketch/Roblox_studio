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
		local dist = math.sqrt((road.x - p.x) ^ 2 + (road.z - p.z) ^ 2)
		if math.abs(road.x - ox) > MapLayout.ROAD_HALF or dist > MapLayout.targetReach(t.id) - 1 then
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
		for i, a in ids do
			local pa = MapLayout.targetPosition(a)
			local ea = extents[a] or 0
			if ea > MapLayout.targetRadius(a) * 1.45 + 1 then
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
			if math.abs(pa.x - ox) - ea < MapLayout.ROAD_HALF then
				roadHit += 1
				print(string.format("    길을 막음: %s (가운데 %.1f · 실제 %.1f)", a, pa.x - ox, ea))
			end
			if pa.z - ea < MapLayout.LOBBY_HALF + 2 then
				lobbyHit += 1
				print("    로비와 겹침: " .. a)
			end
			for j = i + 1, #ids do
				local b = ids[j]
				local pb = MapLayout.targetPosition(b)
				local dist = math.sqrt((pa.x - pb.x) ^ 2 + (pa.z - pb.z) ^ 2)
				if dist < ea + (extents[b] or 0) + 1 then
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
			if dist < (extents[t.id] or 0) + 0.5 then
				rmTarget += 1
				print("    물건과 겹침: " .. t.id)
			end
			for _, other in MapLayout.targetIds(t.world) do
				if other ~= t.id then
					local q = MapLayout.targetPosition(other)
					local ea = extents[other] or 0
					if math.sqrt((mp.x - q.x) ^ 2 + (mp.z - q.z) ^ 2) < ea + half - 0.5 then
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
				math.abs(x0) > MapLayout.ROAD_HALF
				or math.abs(x1) > MapLayout.ROAD_HALF
				or (x0 < 1.5 and x1 > -1.5)
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
		local want = math.clamp(r * 6, 60, 400)
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
			and r15.UpperTorso.Color == roblox.Color3.fromRGB(250, 250, 252)
			and r15:FindFirstChild("Collar")
			and r15:FindFirstChild("Hair")
			and r15:FindFirstChild("BeltKnot")
			and r15.Head:FindFirstChildOfClass("Decal"),
		"R15 사범님: 뿌리 고정 · 흰 도복 · 깃 · 머리카락 · 띠 매듭 · 얼굴"
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
		if not ceil then
			roofOk = false
			print("    천장 없음: 월드 " .. w)
		else
			local r = xzRect(ceil)
			local bottom = ceil.CFrame.Position.Y - ceil.Size.Y / 2
			if r.x0 > rect.x0 or r.x1 < rect.x1 or r.z0 > rect.z0 or r.z1 < rect.z1 or bottom < 18 then
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
			local holes = { { x0 = cx - 9, x1 = cx + 9, z0 = rect.z1 - 2, z1 = rect.z1 + 3, y1 = 14 } }
			for _, d in MapLayout.doors(w) do
				table.insert(holes, { x0 = d.x - 3.5, x1 = d.x + 3.5, z0 = d.z - 1, z1 = d.z + 4, y1 = 9.5 })
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

	local board = CollectionService:GetTagged(Tags.BeltBoard)[1]
	local sg = board.PrimaryPart and board.PrimaryPart:FindFirstChild("Sign")
	local grid = sg and sg.Board:FindFirstChild("Belts")
	check(grid and grid:FindFirstChild("Belt_1") and grid:FindFirstChild("Belt_12"), "띠 표지판 Belt_1..12 칸")
end

local ok, err = pcall(body)
if not ok then
	failures += 1
	print("  FAIL 실행 오류: " .. tostring(err))
end
print(if failures == 0 then "\nsmoke_visuals: 전부 통과" else string.format("\nsmoke_visuals: 실패 %d", failures))
process.exit(if failures == 0 then 0 else 1)
