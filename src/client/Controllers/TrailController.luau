--!strict
--[[
	TrailController — 트레일 상점 창 (2판: 원작 보라 제목 + 가로로 넘기는 카드)

	카드: 트레일 이름 + 등급 글자 + 캐릭터 그림(트레일 색 몸 + 꼬리) + "x4 스피드" 배지 + 아래 버튼
	  - 없으면 가격(초록, 돈 모자라면 회색) → PurchaseUpgrade("Trail", id) (산 뒤 서버가 바로 장착)
	  - 장착 중 (snap.equippedTrail == id) = "장착 해제" → EquipTrail("none")
	  - 가졌지만 장착 안 함 = "장착" → EquipTrail(id)
	캐릭터 꾸밈: 모든 플레이어 HumanoidRootPart 에 Trail "EquippedTrailFx" (Attribute EquippedTrail 색, 보기만)
	창 열기: 허브 트레일 상점 가게(태그 TrailShop) 프롬프트 "열기", 또는 상점 창 "트레일" 탭.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Upgrades = require(Shared.Data.Upgrades)
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
	"신화",
	"코스믹",
	"비밀",
	"영원",
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

local function trailColor(id: string?): Color3?
	local trail = if id then Upgrades.getTrail(id) else nil
	if not trail then
		return nil
	end
	return Color3.fromRGB(trail.color[1], trail.color[2], trail.color[3])
end

-- 캐릭터 꼬리 꾸밈 (보기만, 속도는 서버가 계산)
local FX_NAME = "EquippedTrailFx"
local function decorate(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local id = player:GetAttribute(Tags.PlayerAttributes.EquippedTrail)
	local color = trailColor(if typeof(id) == "string" then id else nil)
	local existing = root:FindFirstChild(FX_NAME)
	if not color then
		if existing then
			existing:Destroy()
		end
		return
	end
	local fx: Trail
	if existing and existing:IsA("Trail") then
		fx = existing
	else
		local a0 = Instance.new("Attachment")
		a0.Name = FX_NAME .. "Top"
		a0.Position = Vector3.new(0, 0.8, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = FX_NAME .. "Bottom"
		a1.Position = Vector3.new(0, -0.8, 0)
		a1.Parent = root
		fx = Instance.new("Trail")
		fx.Name = FX_NAME
		fx.Attachment0 = a0
		fx.Attachment1 = a1
		fx.Lifetime = 0.5
		fx.LightEmission = 0.4
		fx.Transparency = NumberSequence.new(0.2, 1)
		fx.Parent = root
	end
	fx.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.4))
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(decorate, player)
	end)
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.EquippedTrail):Connect(function()
		decorate(player)
	end)
	decorate(player)
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
		local attrEquipped = player:GetAttribute(Tags.PlayerAttributes.EquippedTrail)
		local equipped: string = if snap and typeof(snap.equippedTrail) == "string"
			then snap.equippedTrail
			elseif typeof(attrEquipped) == "string" then attrEquipped
			else Upgrades.NO_TRAIL
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
			local active = isOwned and equipped == id
			local affordable = money() >= trail.cost
			local text = if active then "장착 해제" elseif isOwned then "장착" else Format.money(trail.cost)
			local b = Ui.button(
				text,
				if active
					then C.yellow
					elseif isOwned then C.blue
					elseif affordable then C.shopGreen
					else Color3.fromRGB(150, 150, 160),
				UDim2.new(1, -20, 0, buttonH),
				function()
					if active then
						Net.send(Remotes.ToServer.EquipTrail, Upgrades.NO_TRAIL)
					elseif isOwned then
						Net.send(Remotes.ToServer.EquipTrail, id)
					else
						Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Trail, id)
					end
				end,
				{ anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -10), textSize = 28, parent = card }
			)
			b.Name = if active then "Unequip" elseif isOwned then "Equip" else "BuyTrail"
		end
	end

	Windows.register(NAME, window, render)
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "upgrades" or section == "snapshot") then
			render()
		end
	end)
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.EquippedTrail):Connect(function()
		if Windows.isOpen(NAME) then
			render()
		end
	end)

	-- 모든 플레이어 캐릭터에 장착 트레일 꼬리
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)

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
