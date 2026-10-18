--!strict
--[[
	HatchController — 부화 결과 팝업 (HatchResult)
	펫 카드: 희귀도 색 테두리 + 빙글 도는 3D 펫 + 뒤에서 도는 빛살 + "NEW!" (도감 첫 발견) + 초당 수입.
	잠깐 흔들리는 알 → 펑! 하고 카드가 나오는 순서 (기대감 → 보상).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local Visuals = require(Shared.Data.Visuals)
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local PetViewport = require(Client.UI.PetViewport)

local HatchController = {}

local C = Theme.Colors
local queue: { any } = {}
local showing = false

local function describe(record: any): string
	local parts: { string } = {}
	local size = Sizes.get(tostring(record.size))
	if size and size.id ~= "normal" then
		table.insert(parts, size.name)
	end
	if typeof(record.mutations) == "table" then
		for _, id in record.mutations do
			local m = Mutations.get(id)
			if m then
				table.insert(parts, m.name)
			end
		end
	end
	return table.concat(parts, " · ")
end

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local payload = table.remove(queue, 1)
	local record = payload.pet
	local pet = Pets.get(tostring(record.petId))
	local rarityId = if pet then pet.rarity else "common"
	local rarity = Rarities.get(rarityId)
	local rcolor = Theme.rarityColor(rarityId)

	local layer = Ui.layer("Popups")
	local holder: Frame = Ui.new("Frame", {
		Name = "HatchPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 520),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Ui.scaled(holder, Vector2.new(440, 520))

	-- 1) 알이 흔들림
	local eggColor = Visuals.petColor(tostring(record.petId), 1)
	local egg: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(150, 190),
		BackgroundColor3 = Color3.fromRGB(eggColor[1], eggColor[2], eggColor[3]),
		Parent = holder,
	})
	Ui.corner(1).Parent = egg
	Ui.stroke(C.white, 5).Parent = egg
	for i = 1, 6 do
		Ui.tween(egg, TweenInfo.new(0.08), { Rotation = if i % 2 == 0 then -12 else 12 }).Completed:Wait()
	end
	Ui.tween(egg, TweenInfo.new(0.15), { Size = UDim2.fromOffset(220, 260), BackgroundTransparency = 1 }).Completed
		:Wait()
	egg:Destroy()

	-- 2) 카드
	local rays: Frame = Ui.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(560, 560),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	for i = 1, 8 do
		local ray: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(60, 560),
			Rotation = i * 22.5,
			BackgroundColor3 = rcolor,
			BackgroundTransparency = 0.55,
			Parent = rays,
		})
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Rotation = 90
		g.Parent = ray
	end
	task.spawn(function()
		while rays.Parent do
			Ui.tween(rays, TweenInfo.new(6, Enum.EasingStyle.Linear), { Rotation = rays.Rotation + 90 }).Completed
				:Wait()
		end
	end)

	local card: Frame = Ui.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 470),
		BackgroundColor3 = C.panel,
		Parent = holder,
	})
	Ui.corner(30).Parent = card
	local stroke = Ui.stroke(rcolor, 8)
	stroke.Parent = card
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(rcolor, Theme.lighter(rcolor, 0.8))
	shine.Rotation = 45
	shine.Parent = stroke
	task.spawn(function()
		while card.Parent do
			Ui.tween(shine, TweenInfo.new(1.2, Enum.EasingStyle.Linear), { Rotation = shine.Rotation + 180 }).Completed
				:Wait()
		end
	end)

	Ui.label(
		if payload.fusion then "퓨전!" else "부화!",
		UDim2.new(1, 0, 0, 50),
		42,
		if payload.fusion then C.purple else C.orange,
		{ Position = UDim2.fromOffset(0, 10), Parent = card }
	)
	local view = PetViewport.new(tostring(record.petId), {
		size = UDim2.fromOffset(240, 200),
		position = UDim2.new(0.5, 0, 0, 62),
		anchor = Vector2.new(0.5, 0),
	})
	view.Parent = card
	PetViewport.spin(view, 0.9)
	Ui.label(if pet then pet.name else tostring(record.petId), UDim2.new(1, -20, 0, 46), 38, rcolor, {
		Position = UDim2.fromOffset(10, 266),
		TextScaled = true,
		Parent = card,
	})
	local rarityTag: TextLabel = Ui.new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 314),
		Size = UDim2.fromOffset(150, 34),
		BackgroundColor3 = rcolor,
		TextColor3 = Theme.rarityText(rarityId),
		TextSize = 22,
		Text = if rarity then rarity.name else rarityId,
		Parent = card,
	})
	Ui.corner(1).Parent = rarityTag
	local extra = describe(record)
	Ui.label(
		Format.money(tonumber(payload.income) or 0) .. "/초" .. (if extra ~= "" then "  ·  " .. extra else ""),
		UDim2.new(1, -20, 0, 32),
		24,
		C.money,
		{ Position = UDim2.fromOffset(10, 354), Parent = card }
	)
	Ui.label(
		if payload.equipped then "우리에 들어갔어요!" else "보관함으로 갔어요",
		UDim2.new(1, 0, 0, 24),
		18,
		C.ink,
		{
			Position = UDim2.fromOffset(0, 386),
			Parent = card,
		}
	)
	if payload.isNew then
		local new: TextLabel = Ui.new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -30, 0, 26),
			Size = UDim2.fromOffset(110, 44),
			Rotation = 12,
			BackgroundColor3 = C.red,
			TextColor3 = C.white,
			TextSize = 26,
			Text = "NEW!",
			ZIndex = 5,
			Parent = card,
		})
		Ui.corner(14).Parent = new
		Ui.stroke(C.white, 3).Parent = new
		task.delay(0.35, function()
			Ui.pop(new, 1.6)
		end)
	end
	local done = false
	local function close()
		if done then
			return
		end
		done = true
		local pop = card:FindFirstChild("Pop")
		if pop and pop:IsA("UIScale") then
			Ui.tween(pop, Theme.Tween.close, { Scale = 0 }).Completed:Wait()
		end
		holder:Destroy()
		showing = false
		showNext()
	end
	Ui.button("좋아요!", C.green, UDim2.fromOffset(190, 56), close, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -14),
		textSize = 28,
		parent = card,
	})
	Ui.pop(card, 0.3)
	task.delay(8, close)
end

function HatchController.start()
	Net.on(Remotes.ToClient.HatchResult, function(payload: any)
		if typeof(payload) == "table" and typeof(payload.pet) == "table" then
			table.insert(queue, payload)
			task.spawn(showNext)
		end
	end)
	-- 퓨전 결과도 같은 카드로 (2단계, FusionResult 의 pet/income/isNew/equipped 가 HatchResult 와 같은 모양)
	local fusionRemote = (Remotes.ToClient :: { [string]: string }).FusionResult
	if fusionRemote then
		task.spawn(function()
			Net.on(fusionRemote, function(payload: any)
				if typeof(payload) == "table" and typeof(payload.pet) == "table" then
					payload.fusion = true
					table.insert(queue, payload)
					task.spawn(showNext)
				end
			end)
		end)
	end
end

return HatchController
