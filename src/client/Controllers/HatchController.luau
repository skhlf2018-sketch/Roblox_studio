--!strict
--[[
	HatchController — 성체 카드 "성체가 됐어요!" (6판 PlantGrown { plant, isNew, fruitValue, fruitInterval })
	정원에 심은 씨앗이 그 자리에서 성체가 되면: 씨앗이 흔들리다 퐁! → 카드
	(등급 색 테두리 + 빙글 도는 3D 식물 + 뒤에서 도는 빛살 + "NEW!" (도감 첫 발견) + 열매 1개 값 · 열매 간격).
	접속 때 오프라인으로 여러 그루가 한꺼번에 성체가 되면 카드는 MAX_QUEUE 장까지만 (새 발견·전설 이상 먼저 남김).
	HatchController.show(payload) 로 다른 컨트롤러도 씀:
	  payload = { pet = { petId, size, mutations }, fruitValue?, fruitInterval?, title?, titleColor?, ribbon?, footer?, isNew?, delay? }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local PetViewport = require(Client.UI.PetViewport)

local HatchController = {}

local C = Theme.Colors
local MAX_QUEUE = 4
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

local function rarityOrder(payload: any): number
	local pet = Pets.get(tostring(payload.pet.petId))
	return if pet then Rarities.order(pet.rarity) else 0
end

local showNext: () -> ()

-- 카드 한 장 만들기 (오류가 나도 showNext 의 pcall 이 받아서 다음 카드가 막히지 않음)
local function buildCard(payload: any, track: (Frame) -> ())
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
	track(holder)

	-- 1) 씨앗이 흔들림 (등급 색 아몬드 + 새싹)
	local seed: Frame = Ui.new("Frame", {
		Name = "Seed",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(120, 170),
		BackgroundColor3 = Theme.lighter(rcolor, 0.1),
		Parent = holder,
	})
	Ui.corner(1).Parent = seed
	Ui.stroke(C.white, 5).Parent = seed
	local sprout: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(46, 30),
		BackgroundColor3 = C.green,
		Parent = seed,
	})
	Ui.corner(1).Parent = sprout
	for i = 1, 6 do
		Ui.tween(seed, TweenInfo.new(0.08), { Rotation = if i % 2 == 0 then -12 else 12 }).Completed:Wait()
	end
	Ui.tween(seed, TweenInfo.new(0.15), { Size = UDim2.fromOffset(200, 250), BackgroundTransparency = 1 }).Completed
		:Wait()
	seed:Destroy()

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

	local titleText = if typeof(payload.title) == "string" then payload.title else "성체가 됐어요!"
	local titleColor = if typeof(payload.titleColor) == "Color3" then payload.titleColor else C.green
	Ui.label(titleText, UDim2.new(1, 0, 0, 50), 40, titleColor, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 10),
		Parent = card,
	})
	-- 왼쪽 위 리본 (직접 준 글)
	local ribbonText: string? = if typeof(payload.ribbon) == "string" then payload.ribbon else nil
	if ribbonText then
		local ribbon: TextLabel = Ui.new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(46, 26),
			Size = UDim2.fromOffset(130, 40),
			Rotation = -12,
			BackgroundColor3 = C.purple,
			TextColor3 = C.white,
			TextSize = 22,
			Text = ribbonText,
			ZIndex = 5,
			Parent = card,
		})
		Ui.corner(14).Parent = ribbon
		Ui.stroke(C.white, 3).Parent = ribbon
		Ui.textStroke(2).Parent = ribbon
		task.delay(0.3, function()
			Ui.pop(ribbon, 1.5)
		end)
	end
	local view = PetViewport.new(tostring(record.petId), {
		size = UDim2.fromOffset(240, 200),
		position = UDim2.new(0.5, 0, 0, 62),
		anchor = Vector2.new(0.5, 0),
	})
	view.Parent = card
	PetViewport.spin(view, 0.9)
	Ui.label(if pet then pet.name else tostring(record.petId), UDim2.new(1, -20, 0, 46), 38, rcolor, {
		Name = "PlantName",
		Position = UDim2.fromOffset(10, 266),
		TextScaled = true,
		Parent = card,
	})
	local rarityTag: TextLabel = Ui.new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 314),
		Size = UDim2.fromOffset(170, 34),
		BackgroundColor3 = rcolor,
		TextColor3 = Theme.rarityText(rarityId),
		TextSize = 22,
		Text = if rarity then rarity.name else rarityId,
		Parent = card,
	})
	Ui.corner(1).Parent = rarityTag
	-- 열매 1개 값 · 열매 간격
	local extra = describe(record)
	local value = tonumber(payload.fruitValue) or 0
	local interval = tonumber(payload.fruitInterval) or 0
	local fruitText = "열매 1개 " .. Format.money(value)
	if interval > 0 and interval == interval then
		fruitText ..= string.format(" · %d초마다", math.floor(interval + 0.5))
	end
	local fruitLabel = Ui.label(
		fruitText .. (if extra ~= "" then "  ·  " .. extra else ""),
		UDim2.new(1, -20, 0, 32),
		24,
		C.money,
		{ Name = "Fruit", Position = UDim2.fromOffset(10, 354), TextScaled = true, Parent = card }
	)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 24
	limit.Parent = fruitLabel
	local footer = if typeof(payload.footer) == "string"
		then payload.footer
		elseif payload.isNew then "도감 새 발견! 정원에 열매가 달렸어요 — 따서 팔아요"
		else "정원에 열매가 달렸어요 — 따서 팔아요!"
	Ui.label(footer, UDim2.new(1, -20, 0, 24), 18, C.ink, {
		Name = "Footer",
		Position = UDim2.fromOffset(10, 386),
		TextScaled = true,
		Parent = card,
	})
	if payload.isNew then
		local new: TextLabel = Ui.new("TextLabel", {
			Name = "New",
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
		pcall(function()
			local pop = card:FindFirstChild("Pop")
			if pop and pop:IsA("UIScale") then
				Ui.tween(pop, Theme.Tween.close, { Scale = 0 }).Completed:Wait()
			end
		end)
		holder:Destroy()
		showing = false
		showNext()
	end
	local ok = Ui.button("좋아요!", C.green, UDim2.fromOffset(190, 56), close, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -14),
		textSize = 28,
		parent = card,
	})
	ok.Name = "Ok"
	Ui.pop(card, 0.3)
	task.delay(8, close)
end

showNext = function()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local payload = table.remove(queue, 1)
	local holder: Frame? = nil
	local ok, err = pcall(buildCard, payload, function(frame: Frame)
		holder = frame
	end)
	if not ok then
		-- 카드 하나가 망가져도 다음 카드는 뜨게
		warn("[HatchController] 카드 만들기 실패: " .. tostring(err))
		local h = holder
		if h then
			h:Destroy()
		end
		showing = false
		task.defer(showNext)
	end
end

-- 줄이 너무 길면 (접속 때 오프라인 성장으로 여러 그루) 새 발견도 아니고 등급도 낮은 것부터 뺌
local function trimQueue()
	while #queue > MAX_QUEUE do
		local drop = 1
		local worst = math.huge
		for i, p in queue do
			local score = rarityOrder(p) + (if p.isNew then 100 else 0)
			if score < worst then
				worst, drop = score, i
			end
		end
		table.remove(queue, drop)
	end
end

function HatchController.queued(): number
	return #queue
end

-- 다른 컨트롤러도 같은 카드를 띄울 수 있음
function HatchController.show(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.pet) ~= "table" then
		return
	end
	local wait = tonumber(payload.delay) or 0
	local function push()
		table.insert(queue, payload)
		trimQueue()
		task.spawn(showNext)
	end
	if wait > 0 then
		task.delay(wait, push)
	else
		push()
	end
end

function HatchController.start()
	-- 씨앗이 정원에서 성체가 됨 → 카드
	Net.on(Remotes.ToClient.PlantGrown, function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.plant) ~= "table" then
			return
		end
		HatchController.show({
			pet = payload.plant,
			isNew = payload.isNew == true,
			fruitValue = tonumber(payload.fruitValue) or 0,
			fruitInterval = tonumber(payload.fruitInterval) or 0,
		})
	end)
end

return HatchController
