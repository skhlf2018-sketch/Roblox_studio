--!strict
--[[
	SakuraController — 벚꽃 구역 사쿠라 나무 (Tag SakuraIncubator, 6판 씨앗 버전) + 사쿠라 크리스탈 (Tag SakuraCrystal)

	- 프롬프트 "SakuraPrompt" (E, "바치기 · 뽑기") → 사쿠라 창 ("Sakura"): 크리스탈 수 + 버튼 두 개
	    "성체 바치기" (OfferButton) → 정원 성체 고르기 (카드마다 SakuraRules.crystalsFor 크리스탈 미리보기) → SakuraOffer(plantUid)
	    "씨앗 뽑기 · 크리스탈 10" (DrawButton, 모자라면 회색 + 안내) → SakuraDraw()
	    벚꽃 씨앗 97.5% · 정령 벚꽃 씨앗 2.5% (Config.SAKURA_SEEDS). 나무에서 멀어지면 창이 저절로 닫힘.
	- SakuraResult kind "offered"(바침 → 크리스탈 +gained, 꽃잎) / "draw"(특별 씨앗 → 가방, 꽃 팝업 · 정령이면 보라 빛기둥)
	- 크리스탈 개수(Attr SakuraCrystals): 창 + 나무 위 이름표(내 화면)
	- 크리스탈: 반짝이 + 천천히 빙글 (내 화면)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Plants = require(Shared.Data.Plants)
local SakuraRules = require(Shared.SakuraRules)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local PetPicker = require(Client.UI.PetPicker)
local WorldPrompt = require(Client.UI.WorldPrompt)
local Fx = require(Client.UI.Fx)
local SoundController = require(script.Parent.SoundController)
local NotifyController = require(script.Parent.NotifyController)

local SakuraController = {}
local NAME = "Sakura"
SakuraController.NAME = NAME

local C = Theme.Colors
local Attr = Tags.PlayerAttributes
local PINK = Color3.fromRGB(255, 150, 200)
local SAKURA = Color3.fromRGB(240, 110, 170)
local SPIRIT = Color3.fromRGB(180, 120, 255)
local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SIZE = Vector2.new(640, 420)

local function crystals(): number
	local n = Players.LocalPlayer:GetAttribute(Attr.SakuraCrystals)
	return if typeof(n) == "number" then n else 0
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

local currentTree: BasePart? = nil

-- 정원의 성체 1그루 바치기 → 크리스탈 (등급이 높을수록 많이)
function SakuraController.openOffer(part: BasePart?)
	local function title(): string
		return string.format("성체 바치기 · 크리스탈 %d개", crystals())
	end
	PetPicker.open({
		title = title(),
		liveTitle = title,
		color = SAKURA,
		hint = string.format(
			"성체 1그루를 바치면 크리스탈 (등급이 높을수록 많이)! 크리스탈 %d개로 특별 씨앗 뽑기",
			Config.SAKURA_DRAW_COST
		),
		count = 1,
		items = PetPicker.myPets,
		info = function(item: PetPicker.Item): string?
			return string.format("크리스탈 +%d", SakuraRules.crystalsFor(item.petId))
		end,
		status = function(selected: { PetPicker.Item }): string?
			local item = selected[1]
			if not item then
				return nil
			end
			return string.format(
				"바치면 크리스탈 +%d → %d개 (정원 자리가 비어요)",
				SakuraRules.crystalsFor(item.petId),
				crystals() + SakuraRules.crystalsFor(item.petId)
			)
		end,
		empty = "바칠 성체 식물이 없어요! 정원에서 씨앗을 키워 와요.",
		confirmText = "바치기",
		onConfirm = function(selected: { PetPicker.Item })
			Net.send(Remotes.ToServer.SakuraOffer, selected[1].uid)
		end,
		closeWhen = if part then tooFar(part) else nil,
	})
end

-- 크리스탈로 특별 씨앗 뽑기 — 결과는 SakuraResult kind "draw". 보냈으면 true
function SakuraController.drawSeed(): boolean
	if not SakuraRules.canAfford(crystals()) then
		NotifyController.toast(
			string.format(
				"크리스탈이 %d개 필요해요! (성체 바치기 · 벚꽃 씨앗 배달 · 초기화 때 줍기)",
				Config.SAKURA_DRAW_COST
			),
			"error"
		)
		return false
	end
	Net.send(Remotes.ToServer.SakuraDraw)
	return true
end

-- 뽑기 팝업 (가운데, 2.5초)
local function seedPopup(spirit: boolean, seedName: string)
	local color = if spirit then SPIRIT else PINK
	local holder: Frame = Ui.new("Frame", {
		Name = "SakuraSeedPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- 화면 가운데보다 아래: 나무 위 이름표(캐릭터 머리 위쪽에 보임)와 안 겹치게
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
	Ui.label(seedName .. "!", UDim2.new(1, 0, 0, 60), if spirit then 50 else 44, color, {
		Name = "SeedName",
		Position = UDim2.fromScale(0, 0.66),
		Parent = holder,
	})
	Ui.label("씨앗 가방에 들어갔어요 — 정원에 심어요", UDim2.new(1, 0, 0, 32), 24, C.white, {
		Position = UDim2.fromScale(0, 0.87),
		Parent = holder,
	})
	task.delay(2.6, function()
		holder:Destroy()
	end)
end

-- 나무 위 이름표 (내 화면): 크리스탈 수
local function decorateTree(part: BasePart): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "SakuraStatus"
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
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

	-- 사쿠라 창: 크리스탈 + 버튼 두 개
	local window = Ui.window(NAME, "사쿠라 나무", SAKURA, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content
	local crystalLabel = Ui.label("", UDim2.new(1, 0, 0, 50), 34, Color3.fromRGB(255, 200, 230), {
		Name = "Crystals",
		Parent = content,
	})
	Ui.label(
		"남는 성체를 바치면 크리스탈! 크리스탈로 특별 씨앗을 뽑아요\n벚꽃 씨앗 97.5% · 정령 벚꽃 씨앗 2.5%",
		UDim2.new(1, 0, 0, 64),
		20,
		C.white,
		{ Name = "Info", Position = UDim2.fromOffset(0, 52), TextScaled = true, Parent = content }
	)
	local btnH = Ui.touch(80, SIZE)
	local offerButton = Ui.button("성체 바치기", SAKURA, UDim2.new(0.5, -10, 0, btnH), function()
		Windows.close(NAME)
		SakuraController.openOffer(currentTree)
	end, {
		anchor = Vector2.new(0, 1),
		position = UDim2.new(0, 0, 1, -6),
		textSize = 28,
		parent = content,
	})
	offerButton.Name = "OfferButton"
	local drawButton = Ui.button("씨앗 뽑기", SPIRIT, UDim2.new(0.5, -10, 0, btnH), function()
		SakuraController.drawSeed()
	end, {
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, 0, 1, -6),
		textSize = 26,
		parent = content,
		sound = "Purchase",
	})
	drawButton.Name = "DrawButton"

	local function renderWindow()
		local n = crystals()
		crystalLabel.Text = string.format("💎 크리스탈 %d개", n)
		local afford = SakuraRules.canAfford(n)
		Ui.setButton(
			drawButton,
			string.format("씨앗 뽑기 · 크리스탈 %d", Config.SAKURA_DRAW_COST),
			if afford then SPIRIT else C.gray,
			afford
		)
	end
	Windows.register(NAME, window, renderWindow)

	-- 나무가 멀어지면 창 닫기
	task.spawn(function()
		while true do
			task.wait(0.5)
			local tree = currentTree
			if Windows.isOpen(NAME) and tree and tooFar(tree)() then
				Windows.close(NAME)
			end
		end
	end)

	local labels: { [BasePart]: TextLabel } = {}
	local handle = WorldPrompt.attach({
		tag = Tags.SakuraIncubator,
		name = "SakuraPrompt",
		action = "바치기 · 뽑기",
		object = "사쿠라 나무",
		distance = 12,
		onTrigger = function(part: BasePart)
			currentTree = part
			Windows.open(NAME)
		end,
	})

	local function refresh()
		handle.refresh()
		for _, part in handle.parts() do
			local label = labels[part]
			if not label then
				label = decorateTree(part)
				labels[part] = label
			end
			local l = label :: TextLabel
			l.Text = string.format("크리스탈 %d개 · 뽑기 %d개", crystals(), Config.SAKURA_DRAW_COST)
		end
		if Windows.isOpen(NAME) then
			renderWindow()
		end
		-- 크리스탈 수가 바뀌면 열린 고르기 창(제목)도 다시
		PetPicker.refresh()
	end
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

	local function nearestTree(): BasePart?
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
		local part = nearestTree()
		local pos = if part then part.Position + Vector3.new(0, 4, 0) else nil
		if payload.kind == "offered" then
			-- 성체를 바침 → 크리스탈
			SoundController.play("Reward")
			local gained = tonumber(payload.gained)
			if gained and gained == gained then
				NotifyController.banner(string.format("💎 크리스탈 +%d", math.floor(gained)), PINK)
			end
			if pos then
				Fx.petals(pos, PINK, 80)
				Fx.burst(pos, Color3.fromRGB(255, 230, 245), 40, 1, 14)
			end
		elseif payload.kind == "draw" then
			-- 특별 씨앗 뽑기 (정령 벚꽃 씨앗이면 보라 빛기둥)
			local id = tostring(payload.petId)
			local spirit = id == "spirit_blossom"
			SoundController.play(if spirit then "GrownRare" else "Reward")
			seedPopup(spirit, if Plants.get(id) then Plants.seedName(id) else "특별 씨앗")
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
