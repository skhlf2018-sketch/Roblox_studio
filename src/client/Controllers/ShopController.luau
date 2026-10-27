--!strict
--[[
	ShopController — 상점 창 (2판: 원작 초록 창 + 오른쪽 세로 탭)

	  탭 "업그레이드"(기본): 카드 2장 — 정원(칸 수 Economy.penSlots) / 러닝머신(1초 속도
	      Economy.treadmillGainPerSecond, 20레벨 = 1,000,000, 레벨 모양 이름 20개)
	      사기 버튼 → PurchaseUpgrade("Pen" | "Treadmill"). 코인이 모자라면 회색 (서버가 다시 검사)
	  탭 "트레일": 트레일 상점 창(TrailController)을 엶
	  탭 "추천"·"속도"·"코인": 로벅스 상품 — 어른 확인 전이라 "준비 중" 카드만 보여 줌 (사지 못함)
	베이스 업그레이드 표지판(Visuals.Tags.UpgradeSign, 내 베이스 것만)에 "업그레이드" 프롬프트 → 같은 구매 요청.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Visuals = require(Shared.Data.Visuals)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local WorldPrompt = require(Client.UI.WorldPrompt)

local ShopController = {}

local C = Theme.Colors
local NAME = "Shop"
local SIZE = Vector2.new(820, 520)

-- 러닝머신 레벨 모양 이름 20개 (MapBuilder TREAD_STYLES 와 같은 순서, 6판 20레벨)
local TREADMILL_NAMES = {
	"기본",
	"사이파이",
	"불꽃",
	"셀럽",
	"황금",
	"얼음",
	"럭키블록",
	"해커",
	"악마",
	"천사",
	"정글",
	"바다",
	"사탕",
	"벚꽃",
	"용암",
	"수정",
	"유령",
	"은하",
	"무지개",
	"황제",
}
ShopController.TREADMILL_NAMES = TREADMILL_NAMES

local ROBUX_ITEMS: { [string]: { { title: string, sub: string, color: Color3, icon: string } } } = {
	featured = {
		{ title = "1 스타", sub = "마운트 스타", color = Color3.fromRGB(150, 70, 220), icon = "star" },
		{ title = "3 스타", sub = "마운트 스타", color = Color3.fromRGB(150, 70, 220), icon = "star" },
		{ title = "5 스타", sub = "최고의 가성비!", color = Color3.fromRGB(150, 70, 220), icon = "star" },
	},
	speed = {
		{ title = "x2 스피드", sub = "영원히", color = Color3.fromRGB(40, 150, 255), icon = "shoe" },
		{ title = "+1만 속도", sub = "한 번", color = Color3.fromRGB(40, 150, 255), icon = "shoe" },
		{ title = "+10만 속도", sub = "한 번", color = Color3.fromRGB(40, 150, 255), icon = "shoe" },
	},
	money = {
		{ title = "x2 코인", sub = "영원히", color = Color3.fromRGB(230, 170, 30), icon = "coin" },
		{ title = "1M 코인", sub = "한 번", color = Color3.fromRGB(230, 170, 30), icon = "coin" },
		{ title = "1B 코인", sub = "한 번", color = Color3.fromRGB(230, 170, 30), icon = "coin" },
	},
}

local function money(): number
	local m = Players.LocalPlayer:GetAttribute(Tags.PlayerAttributes.Money)
	return if typeof(m) == "number" then m else 0
end

function ShopController.start()
	local player = Players.LocalPlayer
	local window = Ui.window(NAME, "상점", C.shopGreen, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content
	local body: Frame = Ui.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = content,
	})

	-- 오른쪽 세로 탭 (창 밖, 원작처럼 그림 + 글자)
	local tabBar: Frame = Ui.new("Frame", {
		Name = "Tabs",
		Position = UDim2.new(1, 10, 0, 70),
		Size = UDim2.fromOffset(96, 420),
		BackgroundTransparency = 1,
		Parent = window.holder,
	})
	Ui.list(Enum.FillDirection.Vertical, 8).Parent = tabBar
	local tab = "upgrades"
	local tabButtons: { [string]: TextButton } = {}
	local render: () -> ()
	for i, spec in
		{
			{ "upgrades", "업그레이드", "cart" },
			{ "trail", "트레일", "trail" },
			{ "featured", "추천", "star" },
			{ "speed", "속도", "shoe" },
			{ "money", "코인", "coin" },
		}
	do
		local id = spec[1]
		local b = Ui.button("", C.win, UDim2.fromOffset(96, 84), function()
			if id == "trail" then
				Windows.open("Trail")
				return
			end
			tab = id
			render()
		end, { layoutOrder = i, parent = tabBar })
		b.Name = "Tab_" .. id
		Icons.draw(spec[3], b, 40, UDim2.new(0.5, 0, 0, 30))
		Ui.label(spec[2], UDim2.new(1, 0, 0, 24), 18, C.white, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -4),
			Parent = b,
		})
		tabButtons[id] = b
	end

	local function buyButton(parent: Instance, cost: number?, onBuy: () -> ()): TextButton
		local affordable = cost ~= nil and money() >= cost
		local h = Ui.touch(60, SIZE)
		local text = if cost == nil then "최대 레벨!" elseif cost == 0 then "무료" else Format.money(cost)
		local b = Ui.button(
			text,
			if cost == nil then C.gray elseif affordable then C.shopGreen else Color3.fromRGB(150, 150, 160),
			UDim2.new(1, -24, 0, h),
			function()
				if cost ~= nil then
					onBuy()
				end
			end,
			{ anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -12), textSize = 30, parent = parent }
		)
		b.Name = "Buy"
		return b
	end

	-- 원작 카드: 색 바탕 + 큰 그림 + 제목 + 설명 줄 + 아래 가격 버튼
	local function card(
		parent: Instance,
		order: number,
		color: Color3,
		icon: string,
		title: string,
		lines: { string }
	): Frame
		local f: Frame = Ui.new("Frame", {
			Name = "Card",
			Size = UDim2.fromOffset(330, 400),
			BackgroundColor3 = color,
			LayoutOrder = order,
			Parent = parent,
		})
		Ui.corner(10).Parent = f
		Ui.stroke(C.winEdge, 4).Parent = f
		Ui.gradient(Theme.lighter(color, 0.25), Theme.darker(color, 0.2)).Parent = f
		Icons.draw(icon, f, 90, UDim2.new(0.5, 0, 0, 70))
		Ui.label(title, UDim2.new(1, -16, 0, 40), 32, C.white, { Position = UDim2.fromOffset(8, 124), Parent = f })
		for i, line in lines do
			Ui.label(line, UDim2.new(1, -16, 0, 28), 21, C.white, {
				Position = UDim2.fromOffset(8, 166 + (i - 1) * 30),
				Parent = f,
			})
		end
		return f
	end

	render = function()
		for _, child in body:GetChildren() do
			child:Destroy()
		end
		for id, b in tabButtons do
			Ui.setButton(b, nil, if id == tab then C.shopGreen else C.win)
		end
		local snap = State.get()
		local row: Frame = Ui.new("Frame", {
			Name = "Row",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = body,
		})
		Ui.list(Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent =
			row
		if tab == "upgrades" then
			if not snap then
				return
			end
			local penLevel = snap.penLevel or 1
			local penCost = Economy.nextPenCost(penLevel)
			local pen = card(row, 1, Color3.fromRGB(70, 170, 60), "plant", "정원 업그레이드", {
				string.format("레벨 %d > 레벨 %d", penLevel, if penCost then penLevel + 1 else penLevel),
				if penCost
					then string.format(
						"정원 칸 %d → %d",
						Economy.penSlots(penLevel),
						Economy.penSlots(penLevel + 1)
					)
					else string.format("정원 칸 %d (최대!)", Economy.penSlots(penLevel)),
				"씨앗과 식물을 더 많이 심어요",
			})
			pen.Name = "PenCard"
			buyButton(pen, penCost, function()
				Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Pen)
			end)
			local tLevel = snap.treadmillLevel or 0
			local tCost = Economy.nextTreadmillCost(tLevel)
			local nextName = TREADMILL_NAMES[math.clamp(tLevel + 1, 1, #TREADMILL_NAMES)]
			local tread = card(row, 2, Color3.fromRGB(40, 120, 230), "shoe", "러닝머신 업그레이드", {
				if tLevel <= 0
					then "아직 잠겨 있어요!"
					else string.format("레벨 %d > 레벨 %d", tLevel, if tCost then tLevel + 1 else tLevel),
				if tCost
					then string.format(
						"%s 러닝머신: 1초에 속도 +%s",
						nextName,
						Format.number(Economy.treadmillGainPerSecond(tLevel + 1))
					)
					else string.format(
						"최고 러닝머신! 1초에 속도 +%s",
						Format.number(Economy.treadmillGainPerSecond(tLevel))
					),
				"올라서면 1초마다 속도가 올라요",
			})
			tread.Name = "TreadmillCard"
			buyButton(tread, tCost, function()
				Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Treadmill)
			end)
		else
			local items = ROBUX_ITEMS[tab]
			if not items then
				return
			end
			for i, item in items do
				local f = card(row, i, item.color, item.icon, item.title, { item.sub })
				f.Size = UDim2.fromOffset(220, 330)
				local soon = Ui.button(
					"준비 중",
					Color3.fromRGB(150, 150, 160),
					UDim2.new(1, -24, 0, Ui.touch(56, SIZE)),
					nil,
					{
						anchor = Vector2.new(0.5, 1),
						position = UDim2.new(0.5, 0, 1, -12),
						textSize = 26,
						parent = f,
					}
				)
				Ui.setButton(soon, nil, nil, false)
			end
			Ui.label("로벅스 상품은 어른 확인 후에 열려요", UDim2.new(1, 0, 0, 30), 22, C.yellow, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Parent = body,
			})
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

	-- 베이스 업그레이드 표지판: 내 베이스 것에만 "업그레이드" 프롬프트
	local handle = WorldPrompt.attach({
		tag = Visuals.Tags.UpgradeSign,
		name = "UpgradePrompt",
		action = "업그레이드",
		object = function(part: BasePart): string
			return if part:GetAttribute("Kind") == "Pen" then "정원" else "러닝머신"
		end,
		distance = 10,
		enabled = function(part: BasePart): boolean
			return part:GetAttribute("PlotIndex") == player:GetAttribute(Tags.PlayerAttributes.PlotIndex)
		end,
		onTrigger = function(part: BasePart)
			local kind = part:GetAttribute("Kind")
			if kind == "Pen" then
				Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Pen)
			elseif kind == "Treadmill" then
				Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Treadmill)
			end
		end,
	})
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.PlotIndex):Connect(handle.refresh)
end

return ShopController
