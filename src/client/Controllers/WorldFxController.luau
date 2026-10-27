--!strict
--[[
	WorldFxController — 월드 연출 (내 화면에서만, 판정과 상관없음)
	- 레인보우 껍데기·꽃잎(EggShell + Rainbow — 씨앗·무지개 돌연변이 식물) 색 순환
	- 머리 위에 든 씨앗 흔들흔들 (CarryWeld.C0 를 내 화면에서만 살짝 돌림)
	- 등급 Highlight 는 한 화면에 31개까지만 그려져서, 카메라에 가까운 26개만 켬
	- 내가 있는 구역의 분위기 파티클만 켬
	- 바닥에 떨어진 씨앗(Egg, Attribute ExpiresAt) 머리 위 빨간 "32초" 카운트다운 (2판 수정, 10초부터 깜빡)
	- 배달 성공: 내 베이스 스폰 자리에서 반짝 / 자는 경비 Z 둥실둥실 / 성체가 됨: 반짝 / 잡힘: 머리 위 "퍽!" + 별
	- 6판 열매 따기: FruitPicked { plantUid, count, value } → 그 성체(GardenPlant 파트, Attr PlantUid + OwnerUserId == 나) 위
	  "+열매 3" 주황 글씨 + 작은 코인 값 (popFruit). 식물 살랑살랑·아우라 켜기는 PlantFxController.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Visuals = require(Shared.Data.Visuals)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local ZoneController = require(script.Parent.ZoneController)

local WorldFxController = {}
WorldFxController.popFruit = nil :: ((BasePart, number, number) -> ())?

local VT = Visuals.Tags
local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local MAX_HIGHLIGHTS = 26

local rng = Random.new()

local function watchTag(tag: string, fn: (Instance) -> ())
	for _, inst in CollectionService:GetTagged(tag) do
		fn(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(fn)
end

------------------------------------------------------------------
-- 파티클 한 번 터뜨리기
------------------------------------------------------------------

local function burst(position: Vector3, color: Color3, count: number, size: number, speed: number?)
	local holder = Instance.new("Part")
	holder.Name = "FxBurst"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(position)
	holder.Parent = Workspace
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE_TEX
	e.Enabled = false
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new((speed or 12) * 0.5, speed or 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -10, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(color)
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = holder
	e:Emit(count)
	task.delay(2, function()
		holder:Destroy()
	end)
end

local function myHead(): BasePart?
	local character = Players.LocalPlayer.Character
	local head = if character then character:FindFirstChild("Head") else nil
	return if head and head:IsA("BasePart") then head else nil
end

local function popText(adornee: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 70)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = adornee
	TweenService:Create(gui, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(
		label,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	task.delay(0.9, function()
		gui:Destroy()
	end)
end

------------------------------------------------------------------
-- 떨어진 씨앗 카운트다운 "32초" (2판 수정: 씨앗 파트 Attribute ExpiresAt, workspace:GetServerTimeNow 기준)
------------------------------------------------------------------

local dropTimers: { [BasePart]: TextLabel } = {}

local function refreshDropTimer(egg: BasePart)
	local expires = egg:GetAttribute("ExpiresAt")
	local label = dropTimers[egg]
	if typeof(expires) ~= "number" or egg.Parent == nil then
		if label then
			local gui = label.Parent
			if gui then
				gui:Destroy()
			end
			dropTimers[egg] = nil
		end
		return
	end
	if not label or label.Parent == nil then
		local gui = Instance.new("BillboardGui")
		gui.Name = "DropTimer"
		gui.Size = UDim2.fromOffset(110, 46)
		gui.StudsOffsetWorldSpace = Vector3.new(0, egg.Size.Y / 2 + 2.4, 0)
		gui.LightInfluence = 0
		gui.MaxDistance = 140
		gui.Adornee = egg
		local text = Instance.new("TextLabel")
		text.Name = "Time"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(255, 55, 55)
		text.TextStrokeTransparency = 0
		text.TextStrokeColor3 = Color3.fromRGB(60, 0, 0)
		text.Parent = gui
		gui.Parent = egg
		label = text
		dropTimers[egg] = text
	end
	local left = math.max(0, math.ceil(expires - Workspace:GetServerTimeNow()))
	local shown = label :: TextLabel
	shown.Text = tostring(left) .. "초"
	-- 10초 남으면 노랑 ↔ 빨강 깜빡
	shown.TextColor3 = if left <= 10 and left % 2 == 0
		then Color3.fromRGB(255, 220, 60)
		else Color3.fromRGB(255, 55, 55)
end

-- 2판: 배달 패드가 없어서 내 베이스 스폰 자리(앞마당 가운데)에서 반짝
local function myPad(): BasePart?
	local index = Players.LocalPlayer:GetAttribute(Tags.PlayerAttributes.PlotIndex)
	for _, inst in CollectionService:GetTagged(Tags.PlotSpawn) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotIndex") == index then
			return inst
		end
	end
	return nil
end

-- 6판: 열매를 딴 성체 위 "+열매 3" 팝업 (주황 큰 글씨 + 작은 코인 값, 떠오르며 사라짐)
local function popFruit(part: BasePart, count: number, value: number)
	local h = part:GetAttribute("VisualHeight")
	local height = if typeof(h) == "number" and h > 0 then h else part.Size.Y
	local gui = Instance.new("BillboardGui")
	gui.Name = "FruitPop"
	gui.Size = UDim2.fromScale(8, 3.2)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.AlwaysOnTop = true
	local start = Vector3.new(rng:NextNumber(-0.8, 0.8), -part.Size.Y / 2 + height + 2, 0)
	gui.StudsOffsetWorldSpace = start
	gui.Adornee = part
	local label = Instance.new("TextLabel")
	label.Name = "Fruits"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.62)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "+열매 " .. tostring(count)
	label.TextColor3 = Color3.fromRGB(255, 170, 60)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(14, 15, 22)
	stroke.Thickness = 3
	stroke.Parent = label
	local coins = Instance.new("TextLabel")
	coins.Name = "Value"
	coins.BackgroundTransparency = 1
	coins.Position = UDim2.fromScale(0, 0.62)
	coins.Size = UDim2.fromScale(1, 0.38)
	coins.Font = Enum.Font.FredokaOne
	coins.TextScaled = true
	coins.Text = Format.money(value)
	coins.TextColor3 = Color3.fromRGB(80, 245, 60)
	coins.TextStrokeTransparency = 0
	coins.Parent = gui
	gui.Parent = part
	local fade = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(gui, TweenInfo.new(1.4, Enum.EasingStyle.Quad), {
		StudsOffsetWorldSpace = start + Vector3.new(0, 4, 0),
	}):Play()
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	TweenService:Create(coins, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.5, function()
		gui:Destroy()
	end)
end
WorldFxController.popFruit = popFruit

-- 내 정원의 그 성체 파트 (uid 는 사람마다 겹칠 수 있으니 OwnerUserId 로 거름)
local function myPlantPart(uid: string): BasePart?
	local me = Players.LocalPlayer.UserId
	for _, inst in CollectionService:GetTagged(Tags.GardenPlant) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlantUid") == uid and inst:GetAttribute("OwnerUserId") == me then
			return inst
		end
	end
	return nil
end
WorldFxController.myPlantPart = myPlantPart

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------

function WorldFxController.start()
	-- 자는 경비 머리 위 Z 둥실둥실 (서버 PetVisualService 의 SleepZ 빌보드)
	local zLabels: { { label: TextLabel, base: UDim2, phase: number } } = {}
	local function watchZ(guard: Instance)
		task.delay(1, function()
			local gui = guard:FindFirstChild("SleepZ", true)
			if gui and gui:IsA("BillboardGui") then
				for i, child in gui:GetChildren() do
					if child:IsA("TextLabel") then
						table.insert(zLabels, { label = child, base = child.Position, phase = i * 0.9 })
					end
				end
			end
		end)
	end
	watchTag(Tags.Guardian, watchZ)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for i = #zLabels, 1, -1 do
			local z = zLabels[i]
			if z.label.Parent == nil then
				table.remove(zLabels, i)
			else
				local k = (now * 0.6 + z.phase) % 1
				z.label.Position = z.base + UDim2.fromScale(0.04 * math.sin(k * math.pi * 2), -0.12 * k)
				z.label.TextTransparency = math.max(0, (k - 0.7) / 0.3)
			end
		end
	end)

	-- 레인보우 껍데기 + 든 씨앗 흔들기 (한 프레임 루프)
	local shells: { [BasePart]: boolean } = {}
	watchTag(VT.EggShell, function(inst)
		if inst:IsA("BasePart") and inst:GetAttribute("Rainbow") == true then
			shells[inst] = true
		end
	end)
	CollectionService:GetInstanceRemovedSignal(VT.EggShell):Connect(function(inst)
		if inst:IsA("BasePart") then
			shells[inst] = nil
		end
	end)

	local weldBase: { [Weld]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
	local eggs: { [BasePart]: boolean } = {}
	watchTag(Tags.Egg, function(inst)
		if inst:IsA("BasePart") then
			eggs[inst] = true
		end
	end)
	CollectionService:GetInstanceRemovedSignal(Tags.Egg):Connect(function(inst)
		if inst:IsA("BasePart") then
			eggs[inst] = nil
			dropTimers[inst] = nil
		end
	end)
	-- 바닥에 떨어진 씨앗 머리 위 "32초" 카운트다운 (Attribute ExpiresAt = 서버 시각)
	watchTag(Tags.Egg, function(inst)
		if inst:IsA("BasePart") then
			refreshDropTimer(inst)
			inst:GetAttributeChangedSignal("ExpiresAt"):Connect(function()
				refreshDropTimer(inst)
			end)
		end
	end)
	task.spawn(function()
		while true do
			for egg in dropTimers do
				refreshDropTimer(egg)
			end
			task.wait(0.25)
		end
	end)

	local t = 0
	local hueAccum = 0
	RunService.RenderStepped:Connect(function(dt: number)
		t += dt
		hueAccum += dt
		if hueAccum > 0.08 then
			hueAccum = 0
			local hue = (t * 0.25) % 1
			for part in shells do
				if part.Parent then
					part.Color = Color3.fromHSV(hue, 0.65, 1)
				else
					shells[part] = nil
				end
			end
		end
		for egg in eggs do
			if egg.Parent == nil then
				eggs[egg] = nil
			elseif egg:GetAttribute("EggState") == "Carried" then
				local weld = egg:FindFirstChild("CarryWeld")
				if weld and weld:IsA("Weld") then
					local base = weldBase[weld]
					if not base then
						base = weld.C0
						weldBase[weld] = base
					end
					local wobble = math.sin(t * 7)
					weld.C0 = (base :: CFrame)
						* CFrame.new(0, math.abs(wobble) * 0.25, 0)
						* CFrame.Angles(0, 0, wobble * 0.14)
				end
			end
		end
	end)

	-- 등급 Highlight 제한
	task.spawn(function()
		while true do
			task.wait(0.5)
			local camera = Workspace.CurrentCamera
			if camera then
				local camPos = camera.CFrame.Position
				local list: { { h: Highlight, d: number } } = {}
				for _, inst in CollectionService:GetTagged(VT.RarityHighlight) do
					if inst:IsA("Highlight") then
						local adornee = inst.Adornee or inst.Parent
						local pos: Vector3? = nil
						if adornee and adornee:IsA("Model") then
							pos = adornee:GetPivot().Position
						elseif adornee and adornee:IsA("BasePart") then
							pos = adornee.Position
						end
						if pos then
							table.insert(list, { h = inst, d = (pos - camPos).Magnitude })
						end
					end
				end
				table.sort(list, function(a, b)
					return a.d < b.d
				end)
				for i, item in list do
					local on = i <= MAX_HIGHLIGHTS and item.d < 260
					if item.h.Enabled ~= on then
						item.h.Enabled = on
					end
				end
			end
		end
	end)

	-- 분위기 파티클: 내가 있는 구역만
	local function refreshAmbient(zone: string?)
		for _, inst in CollectionService:GetTagged(VT.Ambient) do
			local on = zone ~= nil and inst:GetAttribute("BiomeId") == zone
			for _, child in inst:GetChildren() do
				if child:IsA("ParticleEmitter") then
					child.Enabled = on
				end
			end
		end
	end
	ZoneController.changed(refreshAmbient)

	-- 이벤트 연출
	local E = Remotes.ToClient
	Net.on(E.EggDelivered, function()
		local pad = myPad()
		if pad then
			burst(pad.Position + Vector3.new(0, 1, 0), Color3.fromRGB(140, 255, 170), 60, 1.2, 18)
			burst(pad.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 240, 120), 30, 0.9, 12)
		end
	end)
	Net.on(E.PlantGrown, function(payload: any)
		-- 성체가 된 자리에서 반짝 (파트가 조금 늦게 올 수 있어 잠깐 뒤). 못 찾으면 내 머리 위
		local plant = if typeof(payload) == "table" then payload.plant else nil
		local uid = if typeof(plant) == "table" and typeof(plant.uid) == "string" then plant.uid else nil
		task.delay(0.3, function()
			local part = if uid then myPlantPart(uid) else nil
			local head = myHead()
			local pos = if part then part.Position + Vector3.new(0, 2, 0) elseif head then head.Position else nil
			if pos then
				burst(pos, Color3.fromRGB(255, 235, 140), 50, 1, 14)
				burst(pos, Color3.fromRGB(140, 255, 150), 30, 0.8, 10)
			end
		end)
	end)
	-- 6판: 열매 따기 → 그 식물 위 "+열매 3" (식물마다 한 번씩 옴)
	Net.on(E.FruitPicked, function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.plantUid) ~= "string" then
			return
		end
		local count = tonumber(payload.count) or 0
		local value = tonumber(payload.value) or 0
		local part = myPlantPart(payload.plantUid)
		if part and count > 0 and count == count then
			popFruit(part, math.floor(count), if value == value then value else 0)
			burst(part.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 180, 70), 12, 0.6, 6)
		end
	end)
	Net.on(E.Caught, function(payload: any)
		local head = myHead()
		if head then
			local cause = if typeof(payload) == "table" then payload.cause else nil
			burst(head.Position + Vector3.new(0, 1.5, 0), Color3.fromRGB(255, 230, 80), 25, 1.3, 8)
			popText(head, if cause == "trap" then "철컥!" else "퍽!", Color3.fromRGB(255, 240, 90))
		end
	end)
end

return WorldFxController
