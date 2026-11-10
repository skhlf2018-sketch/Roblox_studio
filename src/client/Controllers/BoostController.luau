--!strict
--[[
	BoostController — 러닝머신 스피드 배수 창 "BoostWindow" (9판, 선임 · 사장님 2026-11-10)

	- 왼쪽 메뉴 "인덱스"(2) 와 "슬로우 모드"(8) 사이에 번개 버튼 "스피드 배수"(order 3, kind "boost") → 이 창.
	- 카드 11장 (Products.treadmillBoosts: boost_2 … boost_2048): "2배 스피드" · "4배" … "2048배" + 가격 버튼 "R$ 2" …
	  누르면 Purchase.prompt(key) (상품 id 가 아직 0 이면 "준비 중이에요…" 토스트).
	  이미 가진 배수 이하 카드 = 회색 "보유 중" (지금 적용 배수 카드는 "적용 중"). 위에 "지금 ×N 적용 중".
	  설명: "러닝머신을 탈 때 속도가 N배로 올라요 (걷는 속도가 아니에요)".
	- 지금 배수 = 플레이어 Attr TreadmillBoost (없으면 Snapshot treadmillBoost, 없으면 1). 효과·지급은 전부 서버.
	- 격자 스크롤 (폰은 창 배율로 작아짐, 버튼 46px 이상).
	공개: BoostController.NAME · current() · cardState(value) · render()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Products = require(Shared.Data.Products)
local Tags = require(Shared.Tags)
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
local SIZE = Vector2.new(820, 540)
local CARD = Vector2.new(144, 190)
local BOOST_COLOR = Color3.fromRGB(255, 150, 20)

-- 지금 적용 중인 러닝머신 부스트 배수 (1 = 없음)
function BoostController.current(): number
	local a = Players.LocalPlayer:GetAttribute(Tags.PlayerAttributes.TreadmillBoost)
	if typeof(a) == "number" and a >= 1 then
		return a
	end
	local snap = State.get() :: any
	local s = if snap then snap.treadmillBoost else nil
	if typeof(s) == "number" and s >= 1 then
		return s
	end
	return 1
end

-- 카드 상태: "active"(지금 적용) | "owned"(더 작은 배수 = 이미 가진 것보다 아래) | "buy"
function BoostController.cardState(value: number): string
	local now = BoostController.current()
	if value == now then
		return "active"
	elseif value < now then
		return "owned"
	end
	return "buy"
end

local function title(value: number, first: boolean): string
	return if first then string.format("%d배 스피드", value) else string.format("%d배", value)
end

local renderFn: (() -> ())? = nil
function BoostController.render()
	local fn = renderFn
	if fn then
		fn()
	end
end

function BoostController.start()
	local window = Ui.window(NAME, "⚡ 스피드 배수", BOOST_COLOR, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content
	local hint = Ui.label(
		"러닝머신을 탈 때 속도가 N배로 올라요 (걷는 속도가 아니에요)",
		UDim2.new(1, 0, 0, 28),
		20,
		C.yellow,
		{ Name = "Hint", TextScaled = true, Parent = content }
	)
	local nowLabel = Ui.label("", UDim2.new(1, 0, 0, 30), 24, C.white, {
		Name = "Current",
		Position = UDim2.fromOffset(0, 30),
		Parent = content,
	})
	local grid = Ui.scroll(UDim2.new(1, 0, 1, -66), UDim2.fromOffset(0, 66), content)
	local gridLayout = Ui.grid(CARD, 10)
	gridLayout.Parent = grid
	Ui.padding(6).Parent = grid
	local cards: { [string]: { card: Frame, button: TextButton, state: TextLabel } } = {}

	for i, product in Products.treadmillBoosts do
		local value = product.value or 1
		local card = Ui.card(UDim2.fromOffset(CARD.X, CARD.Y), Color3.fromRGB(70, 60, 40), BOOST_COLOR)
		card.Name = "Boost_" .. tostring(value)
		card.LayoutOrder = i
		card.Parent = grid
		Icons.draw("bolt", card, 48, UDim2.new(0.5, 0, 0, 34))
		Ui.label(title(value, i == 1), UDim2.new(1, -8, 0, 30), 24, C.white, {
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
		local key = product.key
		local button = Ui.button(Purchase.robux(product.robux), C.shopGreen, UDim2.new(1, -14, 0, 56), function()
			if BoostController.cardState(value) == "buy" then
				Purchase.prompt(key)
			end
		end, {
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -8),
			textSize = 24,
			parent = card,
		})
		button.Name = "BuyBoost"
		cards[key] = { card = card, button = button, state = state }
	end

	local function render()
		local now = BoostController.current()
		nowLabel.Text = if now > 1
			then string.format("지금 ×%s 적용 중!", tostring(now))
			else "아직 스피드 배수가 없어요 (×1)"
		local buttonH = Ui.touch(56, SIZE)
		for _, product in Products.treadmillBoosts do
			local entry = cards[product.key]
			if entry then
				local value = product.value or 1
				local s = BoostController.cardState(value)
				entry.button.Size = UDim2.new(1, -14, 0, buttonH)
				if s == "buy" then
					Ui.setButton(entry.button, Purchase.robux(product.robux), C.shopGreen, true)
					entry.state.Text = if Purchase.ready(product.key) then "" else "준비 중"
					entry.card.BackgroundColor3 = Color3.fromRGB(70, 60, 40)
				else
					Ui.setButton(entry.button, if s == "active" then "적용 중" else "보유 중", C.gray, false)
					entry.state.Text = if s == "active" then "지금 이 배수!" else "더 큰 배수가 있어요"
					entry.card.BackgroundColor3 = Color3.fromRGB(60, 62, 70)
				end
			end
		end
		hint.Visible = true
	end
	renderFn = render
	Windows.register(NAME, window, render)
	render()

	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.TreadmillBoost):Connect(function()
		if Windows.isOpen(NAME) then
			render()
		end
	end)
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "upgrades" or section == "snapshot") then
			render()
		end
	end)
	Purchase.onGranted(function()
		if Windows.isOpen(NAME) then
			render()
		end
	end)

	-- 왼쪽 메뉴: 인덱스(2) 와 슬로우 모드(8) 사이
	HudController.addMenuButton("boost", "스피드 배수", 3, function()
		Windows.toggle(NAME)
	end)
end

return BoostController
