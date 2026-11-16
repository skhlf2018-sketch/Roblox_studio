--!strict
--[[
	DumbbellShopController — 아령 가게 창 "DumbbellShop" (선임)
	  열기: 왼쪽 메뉴 "아령 가게" · 도장의 아령 가게(태그 DumbbellShop)를 마우스로 누르거나 폰으로 탭.
	  위: 지금 아령 (이름 · 한 번 들 때 +N 힘) → 다음 아령 (이름 · 가격 · +N 힘) + 큰 "사기" 버튼 → BuyDumbbell()
	      돈이 모자라면 회색 "💰 N 더 필요해요". 마지막 아령이면 "가장 좋은 아령이에요!"
	  아래: 아령 20개 목록 (가진 것 ✔ · 다음 것 반짝 · 나머지 🔒). 순서대로만 살 수 있음 (서버도 같은 규칙).
	  힘 배수가 있으면 "+N × 배수" 로 실제 오르는 힘을 같이 보여 줌.
	공개: NAME · render() · nextDumbbell() · canBuy()
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Dumbbells = require(Shared.Data.Dumbbells)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local HudController = require(script.Parent.HudController)

local DumbbellShopController = {}
local NAME = "DumbbellShop"
DumbbellShopController.NAME = NAME

local C = Theme.Colors
local SIZE = Vector2.new(780, 560)
local COLOR = Theme.Menu.shop

function DumbbellShopController.nextDumbbell(): Dumbbells.Dumbbell?
	return Dumbbells.get(State.dumbbell() + 1)
end

function DumbbellShopController.canBuy(): boolean
	local nxt = DumbbellShopController.nextDumbbell()
	return nxt ~= nil and State.money() >= nxt.price
end

local renderFn: (() -> ())? = nil
function DumbbellShopController.render()
	local fn = renderFn
	if fn then
		fn()
	end
end

local function perRep(d: Dumbbells.Dumbbell): string
	local boost = State.boost()
	local base = "+" .. Format.number(d.powerPerRep) .. " 💪"
	if boost > 1 then
		return base .. "  (×" .. Format.number(boost) .. " = +" .. Format.number(d.powerPerRep * boost) .. ")"
	end
	return base
end

function DumbbellShopController.start()
	local window = Ui.window(NAME, "🏋️ 아령 가게", COLOR, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content

	-- 위: 지금 → 다음
	local top: Frame = Ui.new("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 190),
		BackgroundColor3 = C.winDark,
		Parent = content,
	})
	Ui.corner(12).Parent = top
	local function side(name: string, x: number): (TextLabel, TextLabel, TextLabel)
		local box: Frame = Ui.new("Frame", {
			Name = name,
			Position = UDim2.new(x, 8, 0, 8),
			Size = UDim2.new(0.5, -16, 0, 110),
			BackgroundTransparency = 1,
			Parent = top,
		})
		Icons.draw("dumbbell", box, 56, UDim2.fromOffset(36, 40))
		local caption = Ui.label("", UDim2.new(1, -76, 0, 24), 20, C.gray, {
			Name = "Caption",
			Position = UDim2.fromOffset(74, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = box,
		})
		local title = Ui.label("", UDim2.new(1, -76, 0, 36), 30, C.white, {
			Name = "Name",
			Position = UDim2.fromOffset(74, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
			Parent = box,
		})
		local gain = Ui.label("", UDim2.new(1, -76, 0, 28), 22, C.power, {
			Name = "Gain",
			Position = UDim2.fromOffset(74, 68),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
			Parent = box,
		})
		return caption, title, gain
	end
	local nowCaption, nowName, nowGain = side("Now", 0)
	local nextCaption, nextName, nextGain = side("Next", 0.5)
	nowCaption.Text = "지금 아령"
	nextCaption.Text = "다음 아령"
	Ui.label("→", UDim2.fromOffset(40, 40), 36, C.yellow, {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Parent = top,
	})
	local buy = Ui.button("사기", C.shopGreen, UDim2.new(1, -24, 0, 58), function()
		local nxt = DumbbellShopController.nextDumbbell()
		if not nxt then
			return
		end
		if State.money() < nxt.price then
			Ui.pop(top, 1.04)
			return
		end
		Net.send(Remotes.ToServer.BuyDumbbell)
	end, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -10),
		textSize = 28,
		sound = "Click",
		parent = top,
	})
	buy.Name = "BuyButton"

	-- 아래: 20개 목록
	local list = Ui.scroll(UDim2.new(1, 0, 1, -202), UDim2.fromOffset(0, 202), content)
	local grid = Ui.grid(Vector2.new(140, 118), 8)
	grid.Parent = list
	Ui.padding(4).Parent = list
	local cards: { [number]: { card: Frame, state: TextLabel } } = {}
	for _, d in Dumbbells.list do
		local card = Ui.card(UDim2.fromOffset(140, 118), C.winDark, C.winEdge)
		card.Name = "Dumbbell_" .. tostring(d.level)
		card.LayoutOrder = d.level
		card.Parent = list
		Icons.draw("dumbbell", card, 40, UDim2.new(0.5, 0, 0, 26))
		Ui.label(d.name, UDim2.new(1, -8, 0, 26), 20, C.white, {
			Name = "Name",
			Position = UDim2.fromOffset(4, 48),
			TextScaled = true,
			Parent = card,
		})
		Ui.label("+" .. Format.number(d.powerPerRep) .. " 💪", UDim2.new(1, -8, 0, 20), 16, C.power, {
			Name = "Gain",
			Position = UDim2.fromOffset(4, 74),
			TextScaled = true,
			Parent = card,
		})
		local state = Ui.label("", UDim2.new(1, -8, 0, 18), 16, C.yellow, {
			Name = "State",
			Position = UDim2.fromOffset(4, 96),
			TextScaled = true,
			Parent = card,
		})
		cards[d.level] = { card = card, state = state }
	end

	local function render()
		local level = State.dumbbell()
		local now = Dumbbells.get(level) or Dumbbells.list[1]
		nowName.Text = now.name
		nowGain.Text = perRep(now)
		local nxt = Dumbbells.get(level + 1)
		local buttonH = Ui.touch(58, SIZE)
		buy.Size = UDim2.new(1, -24, 0, buttonH)
		if nxt then
			nextName.Text = nxt.name
			nextGain.Text = perRep(nxt)
			local money = State.money()
			if money >= nxt.price then
				Ui.setButton(buy, "사기 · 💰 " .. Format.number(nxt.price), C.shopGreen, true)
			else
				Ui.setButton(buy, "💰 " .. Format.number(nxt.price - money) .. " 더 필요해요", C.gray, false)
			end
		else
			nextName.Text = "없음"
			nextGain.Text = ""
			Ui.setButton(buy, "가장 좋은 아령이에요!", C.gray, false)
		end
		for lv, entry in cards do
			local d = Dumbbells.get(lv)
			if lv <= level then
				entry.state.Text = if lv == level then "들고 있어요 ✔" else "가졌어요 ✔"
				entry.card.BackgroundColor3 = Color3.fromRGB(40, 70, 45)
			elseif lv == level + 1 then
				entry.state.Text = if d then "💰 " .. Format.number(d.price) else ""
				entry.card.BackgroundColor3 = Color3.fromRGB(70, 60, 40)
			else
				entry.state.Text = "🔒 " .. (if d then "💰 " .. Format.number(d.price) else "")
				entry.card.BackgroundColor3 = C.winDark
			end
		end
	end
	renderFn = render
	Windows.register(NAME, window, render)
	render()
	State.onChanged(function()
		if Windows.isOpen(NAME) then
			render()
		end
	end)

	HudController.addMenuButton("shop", "아령 가게", 1, function()
		Windows.toggle(NAME)
	end)

	-- 도장의 아령 가게를 누르면 창
	local function hook(inst: Instance)
		local click = inst:FindFirstChild("Click")
		if click and click:IsA("ClickDetector") then
			click.MouseClick:Connect(function()
				Windows.open(NAME)
			end)
		end
	end
	for _, inst in CollectionService:GetTagged(Tags.DumbbellShop) do
		hook(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.DumbbellShop):Connect(hook)
end

return DumbbellShopController
