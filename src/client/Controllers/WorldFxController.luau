--!strict
--[[
	WorldFxController — 월드 연출 (내 화면에서만, 판정과 상관없음)
	- 우리 펫(PenPet)은 제자리에서 통통, 부모 동물(ParentAnimal)은 살짝 숨쉬기 (TweenService)
	- 레인보우 알 껍데기(EggShell + Rainbow) 색 순환
	- 머리 위에 든 알 흔들흔들 (CarryWeld.C0 를 내 화면에서만 살짝 돌림)
	- 희귀도 Highlight 는 한 화면에 31개까지만 그려져서, 카메라에 가까운 26개만 켬
	- 내가 있는 구역의 분위기 파티클만 켬
	- 배달 성공: 내 베이스 스폰 자리에서 반짝 / 펫 돈 팝업 "+$34K"(IncomeTick) / 자는 경비 Z 둥실둥실 / 부화: 반짝 / 잡힘: 머리 위 "퍽!" + 별
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
WorldFxController.popMoney = nil :: ((Model, number) -> ())?

local VT = Visuals.Tags
local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local MAX_HIGHLIGHTS = 26

local rng = Random.new()

------------------------------------------------------------------
-- 통통 튀기
------------------------------------------------------------------

local function bounce(inst: Instance, amplitudeFactor: number, period: number)
	if not inst:IsA("Model") then
		return
	end
	local model = inst
	task.defer(function()
		local root = model.PrimaryPart
		if not root or model.Parent == nil then
			return
		end
		local h = model:GetAttribute("Height")
		local height = if typeof(h) == "number" then h else 3
		local base = root.CFrame
		local info =
			TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, true, rng:NextNumber(0, period))
		local tween = TweenService:Create(root, info, { CFrame = base * CFrame.new(0, height * amplitudeFactor, 0) })
		tween:Play()
		model.Destroying:Connect(function()
			tween:Cancel()
		end)
		model.AncestryChanged:Connect(function()
			if not model.Parent then
				tween:Cancel()
			end
		end)
	end)
end

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

-- 펫 머리 위 돈 팝업 "+$34K" (원작: 큰 초록 글씨가 떠오름)
local penPets: { [string]: Model } = {}
local function popMoney(model: Model, amount: number)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local h = model:GetAttribute("Height")
	local height = if typeof(h) == "number" then h else 3
	local gui = Instance.new("BillboardGui")
	gui.Name = "MoneyPop"
	gui.Size = UDim2.fromScale(9, 2.6)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	local start = Vector3.new(rng:NextNumber(-1, 1), height + 2.5, 0)
	gui.StudsOffsetWorldSpace = start
	gui.Adornee = root
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "+" .. Format.money(amount)
	label.TextColor3 = Color3.fromRGB(80, 245, 60)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(14, 15, 22)
	stroke.Thickness = 3
	stroke.Parent = label
	gui.Parent = root
	TweenService:Create(gui, TweenInfo.new(1.4, Enum.EasingStyle.Quad), {
		StudsOffsetWorldSpace = start + Vector3.new(0, 5, 0),
	}):Play()
	TweenService
		:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		:Play()
	TweenService
		:Create(stroke, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
		:Play()
	task.delay(1.5, function()
		gui:Destroy()
	end)
end
WorldFxController.popMoney = popMoney

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------

function WorldFxController.start()
	watchTag(VT.PenPet, function(inst)
		bounce(inst, 0.14, 0.32)
		local uid = inst:GetAttribute("PetUid")
		if inst:IsA("Model") and typeof(uid) == "string" then
			penPets[uid] = inst
		end
	end)
	-- 장착 펫이 돈을 벌 때마다 "+$34K" (서버 IncomeTick: 내 펫만 옴)
	Net.onLater(Remotes.ToClient.IncomeTick, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local model = penPets[tostring(payload.petUid)]
		local amount = tonumber(payload.amount)
		if model and model.Parent and amount and amount > 0 then
			popMoney(model, amount)
		end
	end)
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
	watchTag(VT.ParentAnimal, function(inst)
		bounce(inst, 0.035, 1.3)
	end)

	-- 레인보우 껍데기 + 든 알 흔들기 (한 프레임 루프)
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

	-- 희귀도 Highlight 제한
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
	Net.on(E.HatchResult, function()
		local head = myHead()
		if head then
			burst(head.Position, Color3.fromRGB(255, 235, 140), 50, 1, 14)
			burst(head.Position, Color3.fromRGB(255, 160, 220), 30, 0.8, 10)
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
