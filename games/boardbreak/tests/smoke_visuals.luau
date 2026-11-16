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
	check(#matParts == 3 * #mats, "TrainMat 파트 " .. #matParts .. " (월드마다 " .. #mats .. ")")
	local matOk = true
	for _, p in matParts do
		local w = p:GetAttribute(A.World)
		local pos = p.CFrame.Position
		if not (w and MapLayout.isOnTrainMat(pos + Vector3.new(0, 3, 0), w) and p:IsA("BasePart")) then
			matOk = false
		end
	end
	check(matOk, "매트 파트 위 = isOnTrainMat (Attr World)")
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
