--!strict
--[[
	BoostController — 힘 배수 창 "BoostWindow" (선임, 첫 게임 BoostController 를 복사해 바꿈)

	- 왼쪽 메뉴 "힘 배수"(번개, order 3) → 이 창.
	- 카드 12장: 힘 배수 11장 (Products.powerBoosts: power_2 … power_2048, "2배 힘" … "2048배", 가격 "R$ 2" …)
	  + 돈 2배 1장 (money_2, R$ 199). 누르면 Purchase.prompt(key) (게임패스 id 가 아직 0 이면 "준비 중이에요…" 토스트).
	- 힘 배수는 **순서대로만 열림** (2배를 사야 4배 — Products.powerBoostState, 서버도 같은 규칙):
	    바로 다음 배수만 초록 가격 버튼, 그 뒤는 회색 "🔒 R$ N" + "N배를 먼저 사요", 지나온 배수 "보유 중", 지금 배수 "적용 중".
	  돈 2배는 따로 (가졌으면 "보유 중").
	- 설명: "아령으로 오르는 힘과 칠 때 깎는 힘이 둘 다 N배". 위에 "지금 ×N 적용 중".
	- 지금 배수 = Attr PowerBoost (없으면 Snapshot powerBoost). 효과·지급은 전부 서버.
	공개: NAME · current() · cardState(value) · render()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Products = require(Shared.Data.Products)
local Client = script.Parent.Parent
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local Purchase = require(Client.Purchase)
local HudController = require(script.Parent.HudController)

local BoostController = {}
local NAME = "BoostWindow"
BoostController.NAME = NAME

local C = Theme.Colors
local SIZE = Vector2.new(820, 560)
local CARD = Vector2.new(144, 190)
local BOOST_COLOR = Theme.Menu.boost
local MONEY_KEY = "money_2"

function BoostController.current(): number
	return State.boost()
end

-- "active" | "owned" | "buy" | "locked"
function BoostController.cardState(value: number): string
	return Products.powerBoostState(BoostController.current(), value)
end

local function title(value: number, first: boolean): string
	return if first then string.format("%d배 힘", value) else string.format("%d배", value)
end

local renderFn: (() -> ())? = nil
function BoostController.render()
	local fn = renderFn
	if fn then
		fn()
	end
end

type Card = { card: Frame, button: TextButton, state: TextLabel }

function BoostController.start()
	local window = Ui.window(NAME, "⚡ 힘 배수", BOOST_COLOR, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content
	Ui.label("아령 힘·타격 힘 모두 N배 (영구)", UDim2.new(1, 0, 0, 28), 20, C.yellow, {
		Name = "Hint",
		TextScaled = true,
		Parent = content,
	})
	local nowLabel = Ui.label("", UDim2.new(1, 0, 0, 30), 24, C.white, {
		Name = "Current",
		Position = UDim2.fromOffset(0, 30),
		Parent = content,
	})
	local grid = Ui.scroll(UDim2.new(1, 0, 1, -66), UDim2.fromOffset(0, 66), content)
	Ui.grid(CARD, 10).Parent = grid
	Ui.padding(6).Parent = grid
	local cards: { [string]: Card } = {}

	local function makeCard(
		key: string,
		value: number,
		order: number,
		icon: string,
		text: string,
		robux: number,
		color: Color3
	): Card
		local card = Ui.card(UDim2.fromOffset(CARD.X, CARD.Y), Color3.fromRGB(70, 60, 40), color)
		card.Name = "Boost_" .. key
		card.LayoutOrder = order
		card.Parent = grid
		Icons.draw(icon, card, 48, UDim2.new(0.5, 0, 0, 34))
		Ui.label(text, UDim2.new(1, -8, 0, 30), 24, C.white, {
			Name = "Title",
			Position = UDim2.fromOffset(4, 62),
			TextScaled = true,
			Parent = card,
		})
		local state = Ui.label("", UDim2.new(1, -8, 0, 20), 16, C.yellow, {
			Name = "State",
			Position = UDim2.fromOffset(4, 94),
			TextScaled = true,
			Parent = card,
		})
		local button = Ui.button(Purchase.robux(robux), C.shopGreen, UDim2.new(1, -14, 0, 56), function()
			if key == MONEY_KEY then
				if not State.moneyPass() then
					Purchase.prompt(key)
				end
			elseif BoostController.cardState(value) == "buy" then
				Purchase.prompt(key)
			end
		end, {
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -8),
			textSize = 24,
			parent = card,
		})
		button.Name = "BuyBoost"
		local entry: Card = { card = card, button = button, state = state }
		cards[key] = entry
		return entry
	end

	for i, product in Products.powerBoosts do
		local value = product.value or 1
		makeCard(product.key, value, i, "bolt", title(value, i == 1), product.robux, BOOST_COLOR)
	end
	local money = Products.get(MONEY_KEY)
	if money then
		makeCard(MONEY_KEY, 0, 0, "coin", "돈 2배", money.robux, C.money)
	end

	local function render()
		local now = BoostController.current()
		nowLabel.Text = if now > 1 then string.format("×%s 적용 중", tostring(now)) else "힘 배수 없음 (×1)"
		local buttonH = Ui.touch(56, SIZE)
		for _, product in Products.powerBoosts do
			local entry = cards[product.key]
			if entry then
				local value = product.value or 1
				local s = BoostController.cardState(value)
				entry.button.Size = UDim2.new(1, -14, 0, buttonH)
				if s == "buy" then
					Ui.setButton(entry.button, Purchase.robux(product.robux), C.shopGreen, true)
					entry.state.Text = if Purchase.ready(product.key) then "" else "준비 중"
					entry.card.BackgroundColor3 = Color3.fromRGB(70, 60, 40)
				elseif s == "locked" then
					local need = Products.nextPowerBoost(now)
					Ui.setButton(entry.button, "🔒 " .. Purchase.robux(product.robux), C.gray, false)
					entry.state.Text = if need then string.format("%d배 먼저 필요", need.value or 2) else "잠김"
					entry.card.BackgroundColor3 = Color3.fromRGB(48, 48, 54)
				else
					Ui.setButton(entry.button, if s == "active" then "적용 중" else "보유 중", C.gray, false)
					entry.state.Text = if s == "active" then "현재 배수" else "구매 완료 ✔"
					entry.card.BackgroundColor3 = Color3.fromRGB(60, 62, 70)
				end
			end
		end
		local m = cards[MONEY_KEY]
		local mp = Products.get(MONEY_KEY)
		if m and mp then
			m.button.Size = UDim2.new(1, -14, 0, buttonH)
			if State.moneyPass() then
				Ui.setButton(m.button, "보유 중", C.gray, false)
				m.state.Text = "깬 돈 2배 ✔"
				m.card.BackgroundColor3 = Color3.fromRGB(60, 62, 70)
			else
				Ui.setButton(m.button, Purchase.robux(mp.robux), C.shopGreen, true)
				m.state.Text = if Purchase.ready(MONEY_KEY) then "깬 돈 2배" else "준비 중"
				m.card.BackgroundColor3 = Color3.fromRGB(70, 60, 40)
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
	Purchase.onGranted(function()
		render()
	end)

	HudController.addMenuButton("boost", "힘 배수", 3, function()
		Windows.toggle(NAME)
	end)
end

return BoostController
