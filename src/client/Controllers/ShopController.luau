--!strict
--[[
	ShopController — 상점 창 (2판: 원작 초록 창 + 오른쪽 세로 탭) · 베이스 업그레이드 표지판 누르기 (9판)

	  탭 "업그레이드"(기본): 카드 2장 — 정원(칸 수 Economy.penSlots) / 러닝머신(1초 속도
	      Economy.treadmillGainPerSecond, 20레벨 = 1,000,000, 레벨 모양 이름 20개)
	      사기 버튼 → PurchaseUpgrade("Pen" | "Treadmill"). 코인이 모자라면 회색 (서버가 다시 검사)
	      9판: 러닝머신 카드에 "⏩ 건너뛰기 · R$ N" (Products.nextTreadmillSkip, 최대 레벨이면 없음) → Purchase.prompt
	  탭 "트레일": 트레일 상점 창(TrailController)을 엶
	  9판 (사장님 2026-11-10): "추천" 탭 없앰. 로벅스 상품은 Data/Products.shop 그대로 —
	      "속도": speed_10m(10M 스피드 · R$ 199) · speed_100m(100M 스피드 · R$ 259)
	      "코인": money_pass(코인 2배 영원히 · R$ 199, 샀으면 "보유 중") · coins_1m(1M 코인 · R$ 99) · coins_1b(1B 코인 · R$ 199)
	      누르면 Purchase.prompt(key) (상품 id 0 이면 "준비 중이에요…" 토스트, 아니면 로블록스 구매창)

	베이스 업그레이드 표지판 (9판: 회색 E 프롬프트 없앰 → 표지판을 마우스로 누르거나 폰으로 터치):
	  태그 Visuals.Tags.UpgradeSign (Attr Kind "Pen"|"Treadmill", PlotIndex) 파트의 ClickDetector "SignClick"
	  (서버 MapBuilder 가 만듦, 없으면 클라가 만듦). 내 베이스 것만 눌림 (남의 것은 내 화면에서 MaxActivationDistance 0).
	    누르면 바로 PurchaseUpgrade(kind) — 한 번 누르면 한 레벨 (0.35초 연타 방지)
	    코인이 모자라면 표지판 가격 칸이 회색 + 토스트 "코인이 부족해요" (최대 레벨 = "최대 레벨이에요!")
	    마우스를 올리면 테두리가 노랗게 + 가격 칸이 살짝 커짐 (내 것만)
	  태그 Visuals.Tags.TreadmillSkipSign (러닝머신 표지판 옆 "⏩ 건너뛰기 · R$ N") → Purchase.prompt(tskip_n)
	공개: ShopController.TREADMILL_NAMES · clickSign(part) · signCost(kind) · hookSign(part) · ROBUX_TABS
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Products = require(Shared.Data.Products)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Visuals = require(Shared.Data.Visuals)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Purchase = require(Client.Purchase)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)

local ShopController = {}
ShopController.CLICK_COOLDOWN = 0.35 -- 표지판 연타 방지 (초)

local C = Theme.Colors
local Attr = Tags.PlayerAttributes
local NAME = "Shop"
local SIZE = Vector2.new(820, 520)
local ROBUX_GREEN = Color3.fromRGB(0, 176, 111)
local SIGN_DISTANCE = 20 -- 표지판을 누를 수 있는 거리 (스터드)
local SIGN_RED = Color3.fromRGB(225, 30, 40) -- MapBuilder 가격 칸 색
local SIGN_POOR = Color3.fromRGB(120, 120, 130) -- 코인이 모자랄 때
local SIGN_EDGE_HOVER = Color3.fromRGB(255, 220, 60)

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

-- 9판 로벅스 탭: 상품 key · 카드 제목 · 아래 줄 · 그림 · 색
type RobuxCard = { key: string, title: string, sub: string, icon: string, color: Color3 }
local SPEED_BLUE = Color3.fromRGB(40, 150, 255)
local COIN_GOLD = Color3.fromRGB(230, 170, 30)
local ROBUX_TABS: { [string]: { RobuxCard } } = {
	speed = {
		{ key = "speed_10m", title = "10M 스피드", sub = "속도 +10,000,000", icon = "shoe", color = SPEED_BLUE },
		{
			key = "speed_100m",
			title = "100M 스피드",
			sub = "속도 +100,000,000",
			icon = "shoe",
			color = SPEED_BLUE,
		},
	},
	money = {
		{
			key = "money_pass",
			title = "코인 2배",
			sub = "영원히! (열매·식물 팔기)",
			icon = "coin",
			color = COIN_GOLD,
		},
		{ key = "coins_1m", title = "1M 코인", sub = "코인 +1,000,000", icon = "coin", color = COIN_GOLD },
		{ key = "coins_1b", title = "1B 코인", sub = "코인 +1,000,000,000", icon = "coin", color = COIN_GOLD },
	},
}
ShopController.ROBUX_TABS = ROBUX_TABS

local function money(): number
	local m = Players.LocalPlayer:GetAttribute(Attr.Money)
	return if typeof(m) == "number" then m else 0
end

local function levelOf(attr: string, snapKey: string, default: number): number
	local a = Players.LocalPlayer:GetAttribute(attr)
	if typeof(a) == "number" then
		return math.max(0, math.floor(a))
	end
	local snap = State.get() :: any
	local v = if snap then snap[snapKey] else nil
	return if typeof(v) == "number" then math.max(0, math.floor(v)) else default
end

local function penLevel(): number
	return levelOf(Attr.PenLevel, "penLevel", 1)
end

local function treadLevel(): number
	return levelOf(Attr.TreadmillLevel, "treadmillLevel", 0)
end

-- 코인 2배(영원히)를 가졌나
local function hasMoneyPass(): boolean
	local a = Players.LocalPlayer:GetAttribute(Attr.MoneyPass)
	if typeof(a) == "boolean" then
		return a
	end
	local snap = State.get() :: any
	return snap ~= nil and snap.moneyPass == true
end
ShopController.hasMoneyPass = hasMoneyPass

-- 다음 레벨 가격 (nil = 최대 레벨)
function ShopController.signCost(kind: string): number?
	if kind == Remotes.UpgradeKinds.Pen then
		return Economy.nextPenCost(penLevel())
	elseif kind == Remotes.UpgradeKinds.Treadmill then
		return Economy.nextTreadmillCost(treadLevel())
	end
	return nil
end

-- 지금 러닝머신 레벨의 "다음 레벨 건너뛰기" 상품 (최대면 nil)
function ShopController.skipProduct(): Products.Product?
	return Products.nextTreadmillSkip(treadLevel())
end

------------------------------------------------------------------
-- 베이스 표지판 누르기 (9판)
------------------------------------------------------------------

type SignHook = {
	detector: ClickDetector,
	conns: { RBXScriptConnection },
	hover: boolean,
}
local signs: { [BasePart]: SignHook } = {}
local lastClick = -math.huge

local function isMine(part: Instance): boolean
	local plot = Players.LocalPlayer:GetAttribute(Attr.PlotIndex)
	return typeof(plot) == "number" and plot > 0 and part:GetAttribute("PlotIndex") == plot
end

local function isSkipSign(part: Instance): boolean
	return part:GetAttribute("Kind") == "TreadmillSkip" -- MapBuilder 건너뛰기 표지판 (태그 TreadmillSkipSign)
end

-- 표지판 색 다시 (내 것: 코인 모자라면 가격 칸 회색, 마우스 올리면 노란 테두리 + 살짝 큼)
local function paintSign(part: BasePart, hook: SignHook)
	local mine = isMine(part)
	local hidden = part:GetAttribute("Hidden") == true
	hook.detector.MaxActivationDistance = if mine and not hidden then SIGN_DISTANCE else 0
	local edge = part:FindFirstChild("Edge", true)
	if edge and edge:IsA("UIStroke") then
		local hot = hook.hover and mine
		edge.Color = if hot then SIGN_EDGE_HOVER else Color3.fromRGB(12, 14, 26)
		edge.Thickness = if hot then 14 else 8
	end
	local button = part:FindFirstChild("PriceButton", true)
	if button and button:IsA("Frame") then
		local grow = if hook.hover and mine then 1.08 else 1
		if isSkipSign(part) then
			button.Size = UDim2.fromScale(0.84 * grow, 0.4 * grow)
		else
			button.Size = UDim2.fromScale(0.78 * grow, 0.34 * grow)
			local cost = ShopController.signCost(tostring(part:GetAttribute("Kind")))
			local poor = mine and (cost == nil or money() < cost)
			button.BackgroundColor3 = if poor then SIGN_POOR else SIGN_RED
		end
	end
end

local function repaintAll()
	for part, hook in signs do
		if part.Parent then
			paintSign(part, hook)
		end
	end
end
ShopController.repaintSigns = repaintAll

-- 표지판을 누름. 결과: "upgrade" | "poor" | "max" | "notmine" | "busy" | 스킵 표지판이면 Purchase.prompt 결과
function ShopController.clickSign(part: Instance): string
	if not isMine(part) then
		return "notmine"
	end
	local now = os.clock()
	if now - lastClick < ShopController.CLICK_COOLDOWN then
		return "busy"
	end
	lastClick = now
	if isSkipSign(part) then
		if part:GetAttribute("Hidden") == true then
			return "max"
		end
		local product = ShopController.skipProduct()
		if not product then
			NotifyController.toast("최대 레벨이에요!", "info")
			return "max"
		end
		return Purchase.prompt(product.key)
	end
	local kind = part:GetAttribute("Kind")
	if kind ~= Remotes.UpgradeKinds.Pen and kind ~= Remotes.UpgradeKinds.Treadmill then
		return "unknown"
	end
	local cost = ShopController.signCost(kind :: string)
	if cost == nil then
		NotifyController.toast("최대 레벨이에요!", "info")
		SoundController.play("Error")
		return "max"
	end
	if money() < cost then
		NotifyController.toast("코인이 부족해요", "error")
		SoundController.play("Error")
		return "poor"
	end
	SoundController.play("Click")
	Net.send(Remotes.ToServer.PurchaseUpgrade, kind)
	return "upgrade"
end

local function unhookSign(part: BasePart)
	local hook = signs[part]
	if not hook then
		return
	end
	signs[part] = nil
	for _, c in hook.conns do
		c:Disconnect()
	end
end

-- 표지판 하나에 클릭 연결 (한 번만). 붙였으면 true
function ShopController.hookSign(inst: Instance): boolean
	if not inst:IsA("BasePart") or signs[inst] then
		return false
	end
	local part = inst
	local found = part:FindFirstChildOfClass("ClickDetector")
	local detector: ClickDetector
	if found then
		detector = found
	else
		-- 옛 서버(ClickDetector 없음): 내 화면에만 만듦
		local made = Instance.new("ClickDetector")
		made.Name = "SignClick"
		made.MaxActivationDistance = SIGN_DISTANCE
		made.Parent = part
		detector = made
	end
	local hook: SignHook = { detector = detector, conns = {}, hover = false }
	signs[part] = hook
	table.insert(
		hook.conns,
		detector.MouseClick:Connect(function()
			ShopController.clickSign(part)
		end)
	)
	table.insert(
		hook.conns,
		detector.MouseHoverEnter:Connect(function()
			hook.hover = true
			paintSign(part, hook)
		end)
	)
	table.insert(
		hook.conns,
		detector.MouseHoverLeave:Connect(function()
			hook.hover = false
			paintSign(part, hook)
		end)
	)
	table.insert(
		hook.conns,
		part:GetAttributeChangedSignal("Hidden"):Connect(function()
			paintSign(part, hook)
		end)
	)
	table.insert(
		hook.conns,
		part.Destroying:Connect(function()
			unhookSign(part)
		end)
	)
	paintSign(part, hook)
	return true
end

-- 지금 연결된 표지판 수 (테스트용)
function ShopController.signCount(): number
	local n = 0
	for _ in signs do
		n += 1
	end
	return n
end

------------------------------------------------------------------
-- 상점 창
------------------------------------------------------------------

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

	-- 오른쪽 세로 탭 (창 밖, 원작처럼 그림 + 글자) — 9판: "추천" 없앰
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
			local pLevel = penLevel()
			local penCost = Economy.nextPenCost(pLevel)
			local pen = card(row, 1, Color3.fromRGB(70, 170, 60), "plant", "정원 업그레이드", {
				string.format("레벨 %d > 레벨 %d", pLevel, if penCost then pLevel + 1 else pLevel),
				if penCost
					then string.format("정원 칸 %d → %d", Economy.penSlots(pLevel), Economy.penSlots(pLevel + 1))
					else string.format("정원 칸 %d (최대!)", Economy.penSlots(pLevel)),
				"씨앗과 식물을 더 많이 심어요",
			})
			pen.Name = "PenCard"
			buyButton(pen, penCost, function()
				Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Pen)
			end)
			local tLevel = treadLevel()
			local tCost = Economy.nextTreadmillCost(tLevel)
			local nextName = TREADMILL_NAMES[math.clamp(tLevel + 1, 1, #TREADMILL_NAMES)]
			-- 9판: 셋째 줄 자리에 "⏩ 건너뛰기" 버튼이 들어가서 설명은 두 줄
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
			})
			tread.Name = "TreadmillCard"
			local buy = buyButton(tread, tCost, function()
				Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Treadmill)
			end)
			local skip = ShopController.skipProduct()
			if skip then
				local key = skip.key
				local h = Ui.touch(48, SIZE)
				local b = Ui.button(
					"⏩ 건너뛰기 · " .. Purchase.robux(skip.robux),
					ROBUX_GREEN,
					UDim2.new(1, -24, 0, h),
					function()
						Purchase.prompt(key)
					end,
					{
						anchor = Vector2.new(0.5, 1),
						position = UDim2.new(0.5, 0, 1, -(12 + buy.Size.Y.Offset + 8)),
						textSize = 22,
						parent = tread,
					}
				)
				b.Name = "SkipRobux"
			end
		else
			local items = ROBUX_TABS[tab]
			if not items then
				return
			end
			local anyNotReady = false
			for i, item in items do
				local product = Products.get(item.key)
				if product then
					local f = card(row, i, item.color, item.icon, item.title, { item.sub })
					f.Name = "Product_" .. item.key
					f.Size = UDim2.fromOffset(220, 330)
					local owned = item.key == "money_pass" and hasMoneyPass()
					local key = item.key
					local b = Ui.button(
						if owned then "보유 중" else Purchase.robux(product.robux),
						if owned then C.gray else ROBUX_GREEN,
						UDim2.new(1, -24, 0, Ui.touch(56, SIZE)),
						function()
							if not owned then
								Purchase.prompt(key)
							end
						end,
						{
							anchor = Vector2.new(0.5, 1),
							position = UDim2.new(0.5, 0, 1, -12),
							textSize = 28,
							parent = f,
						}
					)
					b.Name = "BuyProduct"
					if owned then
						Ui.setButton(b, nil, nil, false)
					end
					if not Products.isConfigured(product) then
						anyNotReady = true
					end
				end
			end
			if anyNotReady then
				Ui.label(
					"로벅스 상품은 어른과 함께 만들면 살 수 있어요 (준비 중)",
					UDim2.new(1, 0, 0, 30),
					22,
					C.yellow,
					{
						Name = "NotReady",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 1),
						Parent = body,
					}
				)
			end
		end
	end

	Windows.register(NAME, window, render)
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "upgrades" or section == "snapshot") then
			render()
		end
	end)
	-- 9판: 로벅스 상품을 받으면 창·표지판 다시
	Purchase.onGranted(function()
		if Windows.isOpen(NAME) then
			render()
		end
		repaintAll()
	end)
	for _, name in { Attr.MoneyPass, Attr.TreadmillLevel, Attr.PenLevel } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if Windows.isOpen(NAME) then
				render()
			end
			repaintAll()
		end)
	end
	-- 돈이 바뀌면 살 수 있는지 색만 다시 (1초에 한 번까지)
	local pending = false
	player:GetAttributeChangedSignal(Attr.Money):Connect(function()
		if not pending then
			pending = true
			task.delay(1, function()
				pending = false
				if Windows.isOpen(NAME) then
					render()
				end
				repaintAll()
			end)
		end
	end)

	-- 9판 베이스 표지판: 업그레이드 2개 + 러닝머신 건너뛰기 → 누르기 (프롬프트 없음)
	for _, tagName in { Visuals.Tags.UpgradeSign, Visuals.Tags.TreadmillSkipSign } do
		for _, inst in CollectionService:GetTagged(tagName) do
			ShopController.hookSign(inst)
		end
		CollectionService:GetInstanceAddedSignal(tagName):Connect(function(inst: Instance)
			task.defer(ShopController.hookSign, inst)
		end)
		CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(inst: Instance)
			if inst:IsA("BasePart") then
				unhookSign(inst)
			end
		end)
	end
	player:GetAttributeChangedSignal(Attr.PlotIndex):Connect(repaintAll)
end

return ShopController
