--!strict
--[[
	FruitBagController — 열매 가방 창 · 열매 팔기 (6판 "씨앗을 훔치세요", 선임 · 9판: 먹이기 없앰)

	- 열매 가방 창 ("FruitBag"): 위 "열매 12/300 · 다 팔면 3.4K 코인", 칸마다 열매(식물 열매 색) · "꿀 튤립 열매" · ×개수 ·
	  "1개 40 · 모두 480 코인" · 아래 "가판대에서 파세요"(SellHint). 오른쪽 HUD 열매 버튼(HudController)으로 열림.
	- 9판 (2026-11-10 사장님 지시): 열매 먹이기(FeedFruit / FeedResult)는 화면에서 완전히 삭제.
	- 판매 가판대(SellStall, 허브 + 베이스마다) 클라 프롬프트 "SellFruitsPrompt"(E): "열매 팔기" · "열매 12개 · 3.4K 코인"
	  (Attr FruitCount · FruitBagValue). 누르면 SellFruits() (열매가 없으면 안내만). FruitsSold { count, coins } → 화면 가운데 "+3.4K 코인"
	  (식물 팔기 = PetsController 의 "SellPrompt"(F))
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Visuals = require(Shared.Data.Visuals)
local FruitRules = require(Shared.FruitRules)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local PetPicker = require(Client.UI.PetPicker)
local WorldPrompt = require(Client.UI.WorldPrompt)
local NotifyController = require(script.Parent.NotifyController)

local FruitBagController = {}
local NAME = "FruitBag"
FruitBagController.NAME = NAME

local C = Theme.Colors
local Attr = Tags.PlayerAttributes
local SIZE = Vector2.new(820, 540)
local CARD = Vector2.new(170, 236)

local function plantName(petId: string): string
	local pet = Pets.get(petId)
	return if pet then pet.name else petId
end

local function fruitCount(): number
	local n = Players.LocalPlayer:GetAttribute(Attr.FruitCount)
	if typeof(n) == "number" then
		return n
	end
	local snap = State.get()
	return if snap then FruitRules.bagCount(snap.fruits or {}) else 0
end

local function fruitValue(): number
	local n = Players.LocalPlayer:GetAttribute(Attr.FruitBagValue)
	if typeof(n) == "number" then
		return n
	end
	local snap = State.get()
	return if snap then FruitRules.bagValue(snap.fruits or {}) else 0
end

local function bagMax(): number
	local snap = State.get()
	local n = if snap then snap.fruitBagMax else nil
	return if typeof(n) == "number" then n else Config.FRUIT_BAG_MAX
end
FruitBagController.fruitCount = fruitCount
FruitBagController.bagMax = bagMax

------------------------------------------------------------------
-- 팔기
------------------------------------------------------------------

function FruitBagController.sellText(): string
	local n = fruitCount()
	if n <= 0 then
		return "열매가 없어요"
	end
	return string.format("열매 %d개 · %s", n, Format.money(fruitValue()))
end

function FruitBagController.sell(): boolean
	if fruitCount() <= 0 then
		NotifyController.toast("열매 가방이 비었어요! 정원에서 열매를 따 와요", "info")
		return false
	end
	Net.send(Remotes.ToServer.SellFruits)
	return true
end

-- 화면 가운데 "+3.4K 코인" (FruitsSold)
local function coinPopup(coins: number, count: number)
	local holder: Frame = Ui.new("Frame", {
		Name = "FruitsSoldPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(460, 140),
		BackgroundTransparency = 1,
		Parent = Ui.layer("Popups"),
	})
	Ui.scaled(holder, Vector2.new(460, 140))
	local big = Ui.label("+" .. Format.money(coins), UDim2.new(1, 0, 0, 80), 64, C.moneyGreen, {
		Name = "Coins",
		Parent = holder,
	})
	local stroke = big:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = C.winEdge
		stroke.Thickness = 5
	end
	Ui.label(string.format("열매 %d개를 팔았어요!", count), UDim2.new(1, 0, 0, 40), 28, C.white, {
		Name = "Count",
		Position = UDim2.fromOffset(0, 84),
		Parent = holder,
	})
	Ui.pop(holder, 1.4)
	Ui.tween(holder, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.32) })
	task.delay(1.8, function()
		holder:Destroy()
	end)
end
FruitBagController.coinPopup = coinPopup

------------------------------------------------------------------
-- 창
------------------------------------------------------------------

function FruitBagController.start()
	local window = Ui.window(NAME, "열매 가방", C.green, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content
	local summary = Ui.label("", UDim2.new(1, 0, 0, 40), 26, C.white, {
		Name = "Summary",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Parent = content,
	})
	local hint = Ui.label("판매 가판대에서 E 로 팔아요", UDim2.new(1, 0, 0, 24), 18, C.yellow, {
		Name = "Hint",
		Position = UDim2.fromOffset(0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	local grid = Ui.scroll(UDim2.new(1, 0, 1, -72), UDim2.fromOffset(0, 72), content)
	local gridLayout = Ui.grid(CARD, 10)
	gridLayout.Parent = grid
	Ui.padding(6).Parent = grid
	local empty = Ui.label(
		"열매 가방이 비었어요!\n정원의 성체 식물에서 열매를 따요 (E 또는 '열매 모두 따기')",
		UDim2.new(1, -40, 0, 90),
		24,
		C.white,
		{ Name = "Empty", Position = UDim2.fromOffset(20, 180), Visible = false, Parent = content }
	)

	local function render()
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local items = PetPicker.myFruits()
		table.sort(items, function(a: PetPicker.Item, b: PetPicker.Item): boolean
			local va, vb = (a.value or 0) * (a.count or 0), (b.value or 0) * (b.count or 0)
			if va ~= vb then
				return va > vb
			end
			return a.petId < b.petId
		end)
		local snap = State.get()
		local count = if snap then FruitRules.bagCount(snap.fruits or {}) else 0
		local value = if snap then FruitRules.bagValue(snap.fruits or {}) else 0
		summary.Text = string.format("열매 %d / %d  ·  다 팔면 %s", count, bagMax(), Format.money(value))
		hint.Visible = #items > 0
		empty.Visible = #items == 0
		local buttonH = Ui.touch(50, SIZE)
		gridLayout.CellSize = UDim2.fromOffset(CARD.X, 176 + buttonH)
		for i, item in items do
			local pet = Pets.get(item.petId)
			local rarityId = if pet then pet.rarity else "common"
			local rcolor = Theme.rarityColor(rarityId)
			local card = Ui.card(UDim2.fromOffset(CARD.X, 176 + buttonH), Color3.fromRGB(62, 64, 78), rcolor)
			card.Name = "Fruit_" .. item.petId
			card.LayoutOrder = i
			card.Parent = grid
			local fc = Visuals.petColor(item.petId, 3)
			local fruit: Frame = Ui.new("Frame", {
				Name = "FruitIcon",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 10),
				Size = UDim2.fromOffset(64, 64),
				BackgroundColor3 = Color3.fromRGB(fc[1], fc[2], fc[3]),
				Parent = card,
			})
			Ui.corner(1).Parent = fruit
			Ui.stroke(C.white, 3).Parent = fruit
			local leaf: Frame = Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.6, 0, 0, 6),
				Size = UDim2.fromOffset(22, 12),
				Rotation = -25,
				BackgroundColor3 = C.green,
				Parent = fruit,
			})
			Ui.corner(1).Parent = leaf
			Ui.label("×" .. tostring(item.count or 0), UDim2.fromOffset(70, 30), 26, C.white, {
				Name = "Count",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 6),
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = card,
			})
			Ui.label(plantName(item.petId) .. " 열매", UDim2.new(1, -8, 0, 26), 20, rcolor, {
				Name = "FruitName",
				Position = UDim2.fromOffset(4, 80),
				TextScaled = true,
				Parent = card,
			})
			local rarity = Rarities.get(rarityId)
			Ui.label(if rarity then rarity.displayName else "", UDim2.new(1, -8, 0, 18), 15, C.white, {
				Position = UDim2.fromOffset(4, 106),
				TextScaled = true,
				Parent = card,
			})
			Ui.label(
				string.format(
					"1개 %s\n모두 %s",
					Format.money(item.value or 0),
					Format.money((item.value or 0) * (item.count or 0))
				),
				UDim2.new(1, -8, 0, 44),
				16,
				C.money,
				{ Name = "Value", Position = UDim2.fromOffset(4, 126), TextScaled = true, Parent = card }
			)
			Ui.label("가판대에서 파세요", UDim2.new(1, -14, 0, buttonH), 18, C.yellow, {
				Name = "SellHint",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -6),
				TextScaled = true,
				Parent = card,
			})
		end
	end
	Windows.register(NAME, window, render)
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "fruits" or section == "snapshot" or section == "pets") then
			render()
		end
	end)

	-- 판매 가판대: "열매 팔기" (E)
	local handle = WorldPrompt.attach({
		tag = Tags.SellStall,
		name = "SellFruitsPrompt",
		slot = 1, -- 8판: 같은 가판대 "식물 팔기"(F, 2칸) 와 안 겹치게
		action = function(): string
			return if fruitCount() > 0 then "열매 팔기" else "열매 팔기 (없음)"
		end,
		object = function(): string
			return FruitBagController.sellText()
		end,
		distance = Config.SELL_RADIUS - 2,
		onTrigger = function()
			FruitBagController.sell()
		end,
	})
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal(Attr.FruitCount):Connect(handle.refresh)
	player:GetAttributeChangedSignal(Attr.FruitBagValue):Connect(handle.refresh)
	State.onChanged(function(section: string)
		if section == "fruits" or section == "snapshot" then
			handle.refresh()
		end
	end)

	Net.on(Remotes.ToClient.FruitsSold, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local coins = tonumber(payload.coins)
		local count = tonumber(payload.count)
		if coins and count and coins == coins and count == count then
			coinPopup(coins, math.floor(count))
		end
	end)
end

return FruitBagController
