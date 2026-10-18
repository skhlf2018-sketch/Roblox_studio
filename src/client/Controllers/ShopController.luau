--!strict
--[[
	ShopController — 상점 창 (우리 / 러닝머신 / 트레일 업그레이드)
	- 가격·효과는 shared Upgrades + Economy (nextPenCost, nextTreadmillCost, treadmillGainPerSecond)
	- 사기 버튼 → PurchaseUpgrade(kind, trailId?). 돈이 모자라면 회색 (서버가 다시 검사)
	- 트레일 11개: 배율·가격·보유/적용 중 (가진 것 중 최고 배율 하나만 적용)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Upgrades = require(Shared.Data.Upgrades)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)

local ShopController = {}

local C = Theme.Colors
local NAME = "Shop"

function ShopController.start()
	local player = Players.LocalPlayer
	local window = Ui.window(NAME, "상점", Theme.Menu.shop, Vector2.new(820, 560), function()
		Windows.close(NAME)
	end)
	local content = window.content

	local tabBar: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundTransparency = 1,
		Parent = content,
	})
	Ui.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent =
		tabBar
	local body: Frame = Ui.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 1, -66),
		BackgroundTransparency = 1,
		Parent = content,
	})

	local tab = "Pen"
	local tabButtons: { [string]: TextButton } = {}
	local render: () -> ()

	for i, spec in { { "Pen", "우리" }, { "Treadmill", "러닝머신" }, { "Trail", "트레일" } } do
		local id = spec[1]
		tabButtons[id] = Ui.button(spec[2], C.blue, UDim2.fromOffset(200, 52), function()
			tab = id
			render()
		end, { layoutOrder = i, parent = tabBar, textSize = 26 })
	end

	local function money(): number
		local m = player:GetAttribute(Tags.PlayerAttributes.Money)
		return if typeof(m) == "number" then m else 0
	end

	local function buyButton(
		parent: Instance,
		cost: number?,
		onBuy: () -> (),
		position: UDim2,
		size: UDim2?
	): TextButton
		local affordable = cost ~= nil and money() >= cost
		local text = if cost == nil
			then "최대 레벨!"
			elseif cost == 0 then "무료"
			else "사기  " .. Format.money(cost)
		local b = Ui.button(
			text,
			if cost == nil then C.gray elseif affordable then C.green else Color3.fromRGB(150, 150, 160),
			size or UDim2.fromOffset(260, 64),
			function()
				if cost ~= nil then
					onBuy()
				end
			end,
			{ anchor = Vector2.new(0.5, 0), position = position, textSize = 28, parent = parent, sound = "Click" }
		)
		return b
	end

	local function bigCard(title: string, lines: { string }, color: Color3): Frame
		local card = Ui.card(UDim2.new(1, -40, 0, 270), C.white, color)
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, 10)
		card.Parent = body
		Ui.label(title, UDim2.new(1, 0, 0, 56), 40, color, { Position = UDim2.fromOffset(0, 10), Parent = card })
		for i, line in lines do
			Ui.label(line, UDim2.new(1, -20, 0, 36), 26, C.ink, {
				Position = UDim2.fromOffset(10, 66 + (i - 1) * 40),
				Parent = card,
			})
		end
		return card
	end

	render = function()
		for _, child in body:GetChildren() do
			child:Destroy()
		end
		for id, b in tabButtons do
			Ui.setButton(b, nil, if id == tab then C.orange else C.blue)
		end
		local snap = State.get()
		if not snap then
			return
		end
		if tab == "Pen" then
			local level = snap.penLevel or 1
			local cost = Economy.nextPenCost(level)
			local lines = { string.format("지금: %d레벨 · 장착 칸 %d개", level, Economy.penSlots(level)) }
			if cost then
				table.insert(
					lines,
					string.format("다음: %d레벨 → 장착 칸 %d개!", level + 1, Economy.penSlots(level + 1))
				)
			else
				table.insert(lines, "가장 큰 우리예요!")
			end
			table.insert(lines, "펫을 더 많이 장착하면 돈을 더 벌어요")
			local card = bigCard("우리 (펫 칸)", lines, C.green)
			buyButton(card, cost, function()
				Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Pen)
			end, UDim2.new(0.5, 0, 1, -76))
		elseif tab == "Treadmill" then
			local level = snap.treadmillLevel or 0
			local cost = Economy.nextTreadmillCost(level)
			local lines: { string } = {}
			if level <= 0 then
				table.insert(lines, "아직 잠겨 있어요!")
			else
				table.insert(
					lines,
					string.format(
						"지금: %d레벨 · 1초에 속도 +%s",
						level,
						Format.number(Economy.treadmillGainPerSecond(level))
					)
				)
			end
			if cost then
				table.insert(
					lines,
					string.format(
						"%s: %d레벨 → 1초에 +%s",
						if level <= 0 then "해금" else "다음",
						level + 1,
						Format.number(Economy.treadmillGainPerSecond(level + 1))
					)
				)
			else
				table.insert(lines, "최고 러닝머신이에요!")
			end
			table.insert(lines, "베이스 러닝머신 위에 서 있으면 속도가 계속 올라요")
			local card = bigCard("러닝머신 (속도)", lines, C.blue)
			buyButton(card, cost, function()
				Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Treadmill)
			end, UDim2.new(0.5, 0, 1, -76))
		else
			local owned: { [string]: boolean } = {}
			for _, id in snap.trails or {} do
				owned[id] = true
			end
			local best = Economy.bestTrailMultiplier(snap.trails or {})
			local list = Ui.scroll(UDim2.fromScale(1, 1), nil, body)
			Ui.list(Enum.FillDirection.Vertical, 8).Parent = list
			Ui.padding(6).Parent = list
			for _, trail in Upgrades.Trails do
				local color = Color3.fromRGB(trail.color[1], trail.color[2], trail.color[3])
				local row = Ui.card(UDim2.new(1, -20, 0, 70), C.white, color)
				row.LayoutOrder = trail.order
				row.Parent = list
				local swatch: Frame = Ui.new("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 10, 0.5, 0),
					Size = UDim2.fromOffset(120, 18),
					BackgroundColor3 = color,
					Parent = row,
				})
				Ui.corner(1).Parent = swatch
				Ui.gradient(Theme.lighter(color, 0.6), color, 0).Parent = swatch
				Ui.label(
					string.format("%s 트레일  속도 ×%s", trail.name, tostring(trail.multiplier)),
					UDim2.new(1, -420, 1, 0),
					26,
					C.ink,
					{
						Position = UDim2.fromOffset(142, 0),
						TextXAlignment = Enum.TextXAlignment.Left,
						Parent = row,
					}
				)
				if owned[trail.id] then
					local active = trail.multiplier >= best
					local tagLabel: TextLabel = Ui.new("TextLabel", {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -10, 0.5, 0),
						Size = UDim2.fromOffset(240, 52),
						BackgroundColor3 = if active then C.yellow else C.gray,
						TextColor3 = C.white,
						TextSize = 24,
						Text = if active then "적용 중!" else "보유",
						Parent = row,
					})
					Ui.corner(14).Parent = tagLabel
					Ui.textStroke(2).Parent = tagLabel
				else
					local id = trail.id
					local affordable = money() >= trail.cost
					Ui.button(
						"사기  " .. Format.money(trail.cost),
						if affordable then C.green else Color3.fromRGB(150, 150, 160),
						UDim2.fromOffset(240, 52),
						function()
							Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Trail, id)
						end,
						{
							anchor = Vector2.new(1, 0.5),
							position = UDim2.new(1, -10, 0.5, 0),
							textSize = 24,
							parent = row,
						}
					)
				end
			end
		end
	end

	Windows.register(NAME, window, render)
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "upgrades" or section == "snapshot") then
			render()
		end
	end)
	-- 돈이 바뀌면 살 수 있는지 색만 다시 (1초에 한 번까지)
	local pending = false
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.Money):Connect(function()
		if Windows.isOpen(NAME) and not pending then
			pending = true
			task.delay(1, function()
				pending = false
				if Windows.isOpen(NAME) then
					render()
				end
			end)
		end
	end)
end

return ShopController
