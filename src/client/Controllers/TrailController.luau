--!strict
--[[
	TrailController — 트레일 상점 창 (2판: 원작 보라 제목 + 가로로 넘기는 카드)

	카드: 트레일 이름 + 등급 글자 + 캐릭터 그림(트레일 색 몸 + 꼬리) + "x4 스피드" 배지 + 아래 버튼
	  - 없으면 가격(초록, 돈 모자라면 회색) → PurchaseUpgrade("Trail", id)
	  - 가진 것 중 가장 빠른 것 = "장착됨" (서버가 가장 높은 배율 하나만 적용)
	  - 그 밖에 가진 것 = "보유"
	창 열기: 허브 트레일 상점 가게(태그 TrailShop) 프롬프트 "열기", 또는 상점 창 "트레일" 탭.
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
local WorldPrompt = require(Client.UI.WorldPrompt)

local TrailController = {}

local C = Theme.Colors
local NAME = "Trail"
local SIZE = Vector2.new(860, 470)
local GRADES = {
	"일반",
	"일반",
	"희귀",
	"희귀",
	"전설",
	"신화적인",
	"코스믹",
	"비밀",
	"영원한",
	"신성",
	"문블룸",
}

-- 블록 캐릭터 그림 (트레일 색 옷 + 뒤로 흐르는 꼬리)
local function figure(parent: Instance, color: Color3)
	local holder: Frame = Ui.new("Frame", {
		Name = "Figure",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local function part(x: number, y: number, w: number, h: number, c: Color3, rot: number?)
		local f: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = c,
			Rotation = rot or 0,
			Parent = holder,
		})
		Ui.corner(4).Parent = f
		Ui.stroke(C.winEdge, 2).Parent = f
	end
	-- 꼬리 (뒤로 흐르는 띠)
	for i = 0, 2 do
		part(40 - i * 14, 80 + i * 10, 70, 18, color:Lerp(C.white, 0.15 + i * 0.15), -20)
	end
	part(80, 82, 34, 40, color, 8) -- 몸
	part(84, 46, 30, 30, color:Lerp(C.white, 0.2), 8) -- 머리
	part(62, 84, 14, 38, color:Lerp(C.winEdge, 0.15), 30) -- 팔
	part(100, 80, 14, 38, color:Lerp(C.winEdge, 0.15), -35)
	part(72, 122, 15, 38, color:Lerp(C.winEdge, 0.25), 20) -- 다리
	part(92, 122, 15, 38, color:Lerp(C.winEdge, 0.25), -20)
end

function TrailController.start()
	local player = Players.LocalPlayer
	local window = Ui.window(NAME, "트레일 상점", C.trailPurple, SIZE, function()
		Windows.close(NAME)
	end)
	local list: ScrollingFrame = Ui.new("ScrollingFrame", {
		Name = "Cards",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.white,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = window.content,
	})
	Ui.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top).Parent = list

	local function money(): number
		local m = player:GetAttribute(Tags.PlayerAttributes.Money)
		return if typeof(m) == "number" then m else 0
	end

	local function render()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local snap = State.get()
		local ownedList: { string } = if snap then snap.trails or {} else {}
		local owned: { [string]: boolean } = {}
		for _, id in ownedList do
			owned[id] = true
		end
		local best = Economy.bestTrailMultiplier(ownedList)
		local buttonH = Ui.touch(52, SIZE)
		for _, trail in Upgrades.Trails do
			local color = Color3.fromRGB(trail.color[1], trail.color[2], trail.color[3])
			local cardH = 330 + buttonH
			local card: Frame = Ui.new("Frame", {
				Name = "Trail_" .. trail.id,
				Size = UDim2.fromOffset(200, cardH),
				BackgroundColor3 = color,
				LayoutOrder = trail.order,
				Parent = list,
			})
			Ui.corner(10).Parent = card
			Ui.stroke(C.winEdge, 4).Parent = card
			Ui.gradient(Theme.lighter(color, 0.45), color).Parent = card
			Ui.label(trail.name .. " 트레일", UDim2.new(1, -10, 0, 34), 28, C.white, {
				Position = UDim2.fromOffset(5, 8),
				TextScaled = true,
				Parent = card,
			})
			Ui.label(GRADES[trail.order] or "", UDim2.new(1, -10, 0, 22), 18, C.white, {
				Position = UDim2.fromOffset(5, 42),
				Parent = card,
			})
			figure(card, color)
			local badge: TextLabel = Ui.new("TextLabel", {
				Name = "SpeedBadge",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 236),
				Size = UDim2.fromOffset(170, 42),
				BackgroundColor3 = Color3.fromRGB(50, 50, 60),
				BackgroundTransparency = 0.15,
				TextColor3 = C.white,
				TextSize = 28,
				Text = "x" .. tostring(trail.multiplier) .. " 스피드",
				Parent = card,
			})
			Ui.corner(6).Parent = badge
			Ui.textStroke(2.5, C.winEdge).Parent = badge
			local id = trail.id
			local isOwned = owned[id] == true
			local active = isOwned and trail.multiplier >= best
			local affordable = money() >= trail.cost
			local text = if active then "장착됨" elseif isOwned then "보유" else Format.money(trail.cost)
			local b = Ui.button(
				text,
				if active
					then C.yellow
					elseif isOwned then C.gray
					elseif affordable then C.shopGreen
					else Color3.fromRGB(150, 150, 160),
				UDim2.new(1, -20, 0, buttonH),
				function()
					if not isOwned then
						Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Trail, id)
					end
				end,
				{ anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -10), textSize = 28, parent = card }
			)
			b.Name = if isOwned then "Owned" else "BuyTrail"
		end
	end

	Windows.register(NAME, window, render)
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "upgrades" or section == "snapshot") then
			render()
		end
	end)

	-- 허브 트레일 상점 가게 프롬프트
	WorldPrompt.attach({
		tag = Tags.TrailShop,
		name = "TrailPrompt",
		action = "열기",
		object = "트레일 상점",
		distance = 14,
		onTrigger = function()
			Windows.open(NAME)
		end,
	})
end

return TrailController
