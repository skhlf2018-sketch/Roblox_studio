--!strict
--[[
	SakuraController — 벚꽃 구역 사쿠라 인큐베이터 (Tag SakuraIncubator) + 사쿠라 크리스탈 (Tag SakuraCrystal)
	- 프롬프트: 해금 전 "학 바치기" / 해금 후 "꽃피우기" (Attr SakuraUnlocked)
	- 해금 전: 학(crane) 고르기(1마리) → SakuraOffer(uid)
	- 해금 후: 부화 중 알 + 보관 펫 고르기(1개) → SakuraApply(uid). 블룸이 이미 있으면 회색 (SakuraRules.hasBloom)
	- 크리스탈 개수(Attr SakuraCrystals): 창 제목 + 인큐베이터 위 이름표(내 화면)
	- SakuraResult → 해금: 배너 + 꽃잎 / 블룸: 분홍 꽃잎 팝업 / 스피릿 블룸: 보라 빛기둥 + 큰 팝업
	- 크리스탈: 반짝이 + 천천히 빙글 (내 화면)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local SakuraRules = require(Shared.SakuraRules)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local PetPicker = require(Client.UI.PetPicker)
local WorldPrompt = require(Client.UI.WorldPrompt)
local Fx = require(Client.UI.Fx)
local SoundController = require(script.Parent.SoundController)
local NotifyController = require(script.Parent.NotifyController)

local SakuraController = {}

local C = Theme.Colors
local Attr = Tags.PlayerAttributes
local PINK = Color3.fromRGB(255, 150, 200)
local SPIRIT = Color3.fromRGB(180, 120, 255)
local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"

local function crystals(): number
	local n = Players.LocalPlayer:GetAttribute(Attr.SakuraCrystals)
	return if typeof(n) == "number" then n else 0
end

local function unlocked(): boolean
	return Players.LocalPlayer:GetAttribute(Attr.SakuraUnlocked) == true
end

local function myRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function tooFar(part: BasePart): () -> boolean
	return function(): boolean
		local root = myRoot()
		return part.Parent == nil
			or WorldPrompt.distanceTo(part, if root then root.Position else nil) > Config.SAKURA_RADIUS + 4
	end
end

local function openOffer(part: BasePart)
	local crane = Pets.get(Config.SAKURA_UNLOCK_PET)
	local craneName = if crane then crane.name else "학"
	PetPicker.open({
		title = "사쿠라 인큐베이터 (잠김)",
		color = Color3.fromRGB(240, 110, 170),
		hint = craneName .. " 1마리를 바치면 인큐베이터가 영원히 열려요!",
		count = 1,
		items = function(): { PetPicker.Item }
			local list: { PetPicker.Item } = {}
			for _, item in PetPicker.myPets() do
				if item.petId == Config.SAKURA_UNLOCK_PET then
					table.insert(list, item)
				end
			end
			return list
		end,
		empty = craneName .. " 펫이 없어요! 벚꽃 구역에서 " .. craneName .. " 알을 훔쳐 와요.",
		confirmText = "학 바치기",
		onConfirm = function(selected: { PetPicker.Item })
			Net.send(Remotes.ToServer.SakuraOffer, selected[1].uid)
		end,
		closeWhen = tooFar(part),
	})
end

local function openApply(part: BasePart)
	local function title(): string
		return string.format("사쿠라 인큐베이터 · 크리스탈 %d개", crystals())
	end
	PetPicker.open({
		title = title(),
		liveTitle = title,
		color = Color3.fromRGB(240, 110, 170),
		hint = string.format(
			"크리스탈 %d개 → 블룸(×1.5) 97.5%% / 스피릿 블룸(×3) 2.5%%",
			Config.SAKURA_APPLY_COST
		),
		count = 1,
		items = function(): { PetPicker.Item }
			local list = PetPicker.myEggs()
			for _, item in PetPicker.myPets() do
				table.insert(list, item)
			end
			return list
		end,
		filters = {
			{
				id = "nobloom",
				label = "블룸 없는 것만",
				default = true,
				test = function(item: PetPicker.Item): boolean
					return not SakuraRules.hasBloom(item.mutations)
				end,
			},
		},
		check = function(item: PetPicker.Item): (boolean, string?)
			if SakuraRules.hasBloom(item.mutations) then
				return false, "이미 블룸"
			end
			return true, nil
		end,
		ready = function(): (boolean, string?)
			if not SakuraRules.canAfford(crystals()) then
				return false,
					string.format(
						"크리스탈이 %d개 필요해요! (벚꽃 알 배달 / 초기화 때 둥지 근처에서 줍기)",
						Config.SAKURA_APPLY_COST
					)
			end
			return true, nil
		end,
		empty = "꽃피울 알이나 펫이 없어요!",
		confirmText = "꽃피우기!",
		onConfirm = function(selected: { PetPicker.Item })
			Net.send(Remotes.ToServer.SakuraApply, selected[1].uid)
		end,
		closeWhen = tooFar(part),
	})
end

-- 블룸 팝업 (가운데, 2.5초)
local function bloomPopup(spirit: boolean, targetName: string)
	local color = if spirit then SPIRIT else PINK
	local holder: Frame = Ui.new("Frame", {
		Name = "BloomPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- 화면 가운데보다 아래: 인큐베이터 위 이름표(캐릭터 머리 위쪽에 보임)와 안 겹치게
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromOffset(420, 300),
		BackgroundTransparency = 1,
		Parent = Ui.layer("Popups"),
	})
	Ui.scaled(holder, Vector2.new(420, 300))
	-- 꽃 (꽃잎 5장 + 가운데)
	local flower: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(160, 160),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		local petal: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.cos(a) * 0.3, 0.5 + math.sin(a) * 0.3),
			Size = UDim2.fromOffset(70, 70),
			BackgroundColor3 = Theme.lighter(color, 0.2),
			Parent = flower,
		})
		Ui.corner(1).Parent = petal
		Ui.stroke(C.white, 3).Parent = petal
	end
	local center: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = C.yellow,
		Parent = flower,
	})
	Ui.corner(1).Parent = center
	Ui.stroke(C.white, 3).Parent = center
	Ui.tween(flower, TweenInfo.new(2.5, Enum.EasingStyle.Linear), { Rotation = 180 })
	Ui.pop(flower, 0.2)
	Ui.label(
		if spirit then "스피릿 블룸!! ×3" else "블룸! ×1.5",
		UDim2.new(1, 0, 0, 60),
		if spirit then 50 else 44,
		color,
		{ Position = UDim2.fromScale(0, 0.66), Parent = holder }
	)
	Ui.label(targetName .. "에 꽃이 피었어요", UDim2.new(1, 0, 0, 32), 24, C.white, {
		Position = UDim2.fromScale(0, 0.87),
		Parent = holder,
	})
	task.delay(2.6, function()
		holder:Destroy()
	end)
end

local function nameOfTarget(uid: string): string
	local snap = State.get()
	if snap then
		for _, record in (snap.incubators or {}) :: { Types.IncubatorRecord } do
			if record.uid == uid then
				local pet = Pets.get(record.petId)
				return (if pet then pet.name else record.petId) .. " 알"
			end
		end
		for _, record in (snap.eggs or {}) :: { Types.BagEgg } do
			if record.uid == uid then
				local pet = Pets.get(record.petId)
				return (if pet then pet.name else record.petId) .. " 알"
			end
		end
		for _, record in (snap.pets or {}) :: { Types.PetRecord } do
			if record.uid == uid then
				local pet = Pets.get(record.petId)
				return if pet then pet.name else record.petId
			end
		end
	end
	return "대상"
end

-- 인큐베이터 위 이름표 (내 화면): 크리스탈 수 + 잠김/열림
local function decorateIncubator(part: BasePart): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "SakuraStatus"
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 230, 245)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(120, 30, 80)
	label.Parent = gui
	gui.Parent = part
	return label
end

-- 크리스탈: 반짝이 + 빙글
local function decorateCrystal(inst: Instance)
	if not inst:IsA("BasePart") or inst:FindFirstChild("CrystalFx") then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "CrystalFx"
	e.Texture = SPARKLE_TEX
	e.Rate = 6
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(1, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 235))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Parent = inst
	local light = Instance.new("PointLight")
	light.Color = PINK
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = inst
	local base = inst.CFrame
	local spin = TweenService:Create(
		inst,
		TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ CFrame = base * CFrame.Angles(0, math.pi, 0) }
	)
	spin:Play()
	inst.Destroying:Connect(function()
		spin:Cancel()
	end)
end

function SakuraController.start()
	local player = Players.LocalPlayer
	local labels: { [BasePart]: TextLabel } = {}
	local handle = WorldPrompt.attach({
		tag = Tags.SakuraIncubator,
		name = "SakuraPrompt",
		action = function(): string
			return if unlocked() then "꽃피우기" else "학 바치기"
		end,
		object = "사쿠라 인큐베이터",
		distance = 12,
		onTrigger = function(part: BasePart)
			if unlocked() then
				openApply(part)
			else
				openOffer(part)
			end
		end,
	})

	local function refresh()
		handle.refresh()
		for _, part in handle.parts() do
			local label = labels[part]
			if not label then
				label = decorateIncubator(part)
				labels[part] = label
			end
			local l = label :: TextLabel
			l.Text = if unlocked()
				then string.format("크리스탈 %d개 · 열림", crystals())
				else string.format("잠김 · 학을 바쳐요 (크리스탈 %d개)", crystals())
		end
		-- 크리스탈 수가 바뀌면 열린 창(확인 버튼)도 다시
		PetPicker.refresh()
	end
	player:GetAttributeChangedSignal(Attr.SakuraUnlocked):Connect(refresh)
	player:GetAttributeChangedSignal(Attr.SakuraCrystals):Connect(refresh)
	CollectionService:GetInstanceAddedSignal(Tags.SakuraIncubator):Connect(function()
		task.defer(refresh)
	end)
	refresh()

	for _, inst in CollectionService:GetTagged(Tags.SakuraCrystal) do
		decorateCrystal(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.SakuraCrystal):Connect(function(inst: Instance)
		task.defer(decorateCrystal, inst)
	end)

	local function nearestIncubator(): BasePart?
		local root = myRoot()
		local best: BasePart? = nil
		local bestD = math.huge
		for _, part in handle.parts() do
			local d = WorldPrompt.distanceTo(part, if root then root.Position else nil)
			if d < bestD then
				best, bestD = part, d
			end
		end
		return best
	end

	Net.on(Remotes.ToClient.SakuraResult, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local part = nearestIncubator()
		local pos = if part then part.Position + Vector3.new(0, 4, 0) else nil
		if payload.kind == "unlocked" then
			SoundController.play("Unlock")
			NotifyController.banner("사쿠라 인큐베이터가 열렸어요!", Color3.fromRGB(255, 130, 190))
			if pos then
				Fx.petals(pos, PINK, 80)
				Fx.burst(pos, Color3.fromRGB(255, 230, 245), 40, 1, 14)
			end
		else
			local spirit = payload.mutation == "spirit_bloom"
			SoundController.play(if spirit then "SpiritBloom" else "Bloom")
			bloomPopup(spirit, nameOfTarget(tostring(payload.targetUid)))
			if pos then
				Fx.petals(pos, if spirit then SPIRIT else PINK, if spirit then 140 else 70)
				if spirit then
					Fx.pillar(pos, SPIRIT, 60, 2)
					Fx.flash(pos, SPIRIT, 40, 1.2)
				end
			end
		end
		refresh()
	end)
end

return SakuraController
