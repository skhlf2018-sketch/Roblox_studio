--!strict
--[[
	IndexController — 식물 도감 창 (2판 원작 화면 → 6판 "씨앗을 훔치세요" 성체 도감)

	  ┌ 식물 도감 ────────────────────────────── [X] ┐   [월드]
	  │ [구역  ]  [카드][카드][카드][카드]   [ 선택 식물 3D ] │
	  │ [그림  ]  [카드][카드][카드][카드]   ???  일반  [>] │
	  │ [목록 ↕]  [■■■□□□□□ 1/8      ]     보상: 100 코인 +420 │
	  │                                    [  획득!  ]     │
	  │ [📘 모두 획득 (n)!  /  잠금 해제: 18/158         ] │
	  └───────────────────────────────────────────────────┘
	- 왼쪽: 구역 18개(7판) 그림 탭 (세로 스크롤). 받을 보상이 있는 구역은 "!" 표시
	- 가운데: 구역 식물 카드 (등급 색 바탕 — 등급 16개(7판), Theme.RainbowRarities 는 무지개 띠, 발견 전 검은 실루엣 "???")
	  + 진행바 "발견/전체". 발견 = 한 번이라도 성체가 됨
	- 오른쪽: 고른 식물 크게 + 이름·등급 + "열매 1개 N 코인 · N초마다" + 빨간 ">" (다음 식물)
	  + 보상(코인·속도) + "획득!" → ClaimIndexReward(plantId)
	- 아래: "모두 획득 (n)!" → ClaimIndexReward("all"), 받을 게 없으면 "잠금 해제: 발견/158 (7판, 전체 수는 Pets.list)"
	- 창 오른쪽 위 밖의 "월드" 버튼: 다른 월드는 준비 중 안내
	데이터: State.indexDiscovered / indexClaimed, 보상 미리보기 Index.reward (shared, 코인 = 열매 1개 값 × 10)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Biomes = require(Shared.Data.Biomes)
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Index = require(Shared.Data.Index)
local Visuals = require(Shared.Data.Visuals)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local PetViewport = require(Client.UI.PetViewport)
local NotifyController = require(script.Parent.NotifyController)

local IndexController = {}

local C = Theme.Colors
local NAME = "Index"
local SIZE = Vector2.new(900, 560)

local function rgb(c: Visuals.Color): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- 구역 그림 (하늘 + 바닥 + 담장 + 장식 블록) — 원작 왼쪽 숲 그림처럼
local function zonePicture(parent: Instance, biomeId: string)
	local theme = Visuals.biomes[biomeId]
	if not theme then
		return
	end
	local sky: Frame = Ui.new("Frame", {
		Name = "Picture",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 190, 255),
		ZIndex = 1,
		Parent = parent,
	})
	Ui.corner(6).Parent = sky
	Ui.gradient(Color3.fromRGB(150, 210, 255), Color3.fromRGB(90, 160, 240)).Parent = sky
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.38),
		BackgroundColor3 = rgb(theme.floor),
		ZIndex = 2,
		Parent = sky,
	})
	Ui.new("Frame", {
		Position = UDim2.fromScale(0, 0.3),
		Size = UDim2.fromScale(0.16, 0.34),
		BackgroundColor3 = rgb(theme.wall),
		ZIndex = 2,
		Parent = sky,
	})
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0.3),
		Size = UDim2.fromScale(0.16, 0.34),
		BackgroundColor3 = rgb(theme.wall),
		ZIndex = 2,
		Parent = sky,
	})
	-- 나무/장식 덩어리 2개
	for _, spec in { { 0.32, 0.36, 0.3 }, { 0.68, 0.44, 0.22 } } do
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(spec[1], 0.66),
			Size = UDim2.fromScale(0.05, spec[2] * 0.5),
			BackgroundColor3 = Color3.fromRGB(120, 80, 45),
			ZIndex = 3,
			Parent = sky,
		})
		local leaf: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(spec[1], 0.66 - spec[2] * 0.4),
			Size = UDim2.fromScale(spec[3], spec[2] * 0.45),
			BackgroundColor3 = rgb(theme.accent),
			ZIndex = 3,
			Parent = sky,
		})
		Ui.corner(4).Parent = leaf
	end
end

-- Theme.RainbowRarities (신성·슈퍼·울트라디바인·해커 글리치, 7판): 무지개 띠 (카드 바탕·등급 글씨)
local function rainbow(target: GuiObject, rarityId: string)
	if Theme.RainbowRarities[rarityId] then
		local g = Instance.new("UIGradient")
		g.Name = "Rainbow"
		g.Color = Theme.bandFor(rarityId) -- 해커 글리치 = 깨진 띠
		g.Rotation = 20
		g.Parent = target
	end
end

function IndexController.start()
	local window = Ui.window(NAME, "식물 도감", C.indexCyan, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content

	-- 창 밖 오른쪽 위 "월드" 버튼
	local world = Ui.button("월드", C.indexCyan, UDim2.fromOffset(150, 58), function()
		NotifyController.toast("다른 월드는 준비 중이에요!", "info")
	end, { anchor = Vector2.new(0, 0), position = UDim2.new(1, 12, 0, 40), textSize = 30, parent = window.holder })
	world.Name = "World"

	-- 왼쪽: 구역 그림 탭
	local tabs = Ui.scroll(UDim2.new(0, 150, 1, -80), UDim2.fromOffset(0, 0), content)
	tabs.Name = "Tabs"
	tabs.BackgroundColor3 = C.winDark
	tabs.BackgroundTransparency = 0
	Ui.corner(8).Parent = tabs
	Ui.list(Enum.FillDirection.Vertical, 6).Parent = tabs
	Ui.padding(5).Parent = tabs

	-- 가운데: 카드 + 진행바
	local middle: Frame = Ui.new("Frame", {
		Name = "Middle",
		Position = UDim2.fromOffset(160, 0),
		Size = UDim2.new(1, -160 - 260, 1, -80),
		BackgroundColor3 = C.winDark,
		Parent = content,
	})
	Ui.corner(8).Parent = middle
	Ui.stroke(C.winEdge, 3).Parent = middle
	local grid = Ui.scroll(UDim2.new(1, -12, 1, -66), UDim2.fromOffset(6, 6), middle)
	grid.Name = "Grid"
	local gridLayout = Ui.grid(Vector2.new(100, 104), 8)
	gridLayout.Parent = grid
	local barBack: Frame = Ui.new("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, 46),
		BackgroundColor3 = Color3.fromRGB(20, 21, 28),
		Parent = middle,
	})
	Ui.corner(6).Parent = barBack
	Ui.stroke(C.winEdge, 3).Parent = barBack
	local barFill: Frame = Ui.new("Frame", {
		Size = UDim2.fromScale(0.1, 1),
		BackgroundColor3 = C.shopGreen,
		Parent = barBack,
	})
	Ui.corner(6).Parent = barFill
	local barText = Ui.label("0/0", UDim2.fromScale(1, 1), 30, C.white, { Name = "Text", ZIndex = 3, Parent = barBack })

	-- 오른쪽: 상세
	local detail: Frame = Ui.new("Frame", {
		Name = "Detail",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 250, 1, -80),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local viewBox: Frame = Ui.new("Frame", {
		Name = "ViewBox",
		Size = UDim2.new(1, 0, 0, 230),
		BackgroundColor3 = Color3.fromRGB(70, 72, 86),
		Parent = detail,
	})
	Ui.corner(8).Parent = viewBox
	Ui.stroke(C.winEdge, 3).Parent = viewBox
	local detailName = Ui.label("???", UDim2.new(1, -60, 0, 30), 26, C.white, {
		Name = "PetName",
		Position = UDim2.fromOffset(10, 132),
		ZIndex = 3,
		Parent = viewBox,
	})
	local detailRarity = Ui.label("", UDim2.new(1, -60, 0, 26), 22, C.white, {
		Name = "Rarity",
		Position = UDim2.fromOffset(10, 164),
		ZIndex = 3,
		Parent = viewBox,
	})
	local detailIncome = Ui.label("???", UDim2.new(1, -60, 0, 26), 22, C.moneyGreen, {
		Name = "Income",
		Position = UDim2.fromOffset(10, 194),
		ZIndex = 3,
		Parent = viewBox,
	})
	local nextButton = Ui.button(">", C.eggRed, UDim2.fromOffset(46, 46), nil, {
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -8, 0, 160),
		textSize = 30,
		parent = viewBox,
	})
	nextButton.Name = "NextPet"
	nextButton.ZIndex = 4

	local rewardBox: Frame = Ui.new("Frame", {
		Name = "Reward",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 180),
		BackgroundColor3 = Color3.fromRGB(30, 80, 40),
		Parent = detail,
	})
	Ui.corner(8).Parent = rewardBox
	Ui.stroke(Color3.fromRGB(60, 200, 80), 3).Parent = rewardBox
	Ui.label("보상:", UDim2.fromOffset(80, 24), 20, C.white, {
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = rewardBox,
	})
	local function rewardTile(x: number, icon: string): TextLabel
		local tile: Frame = Ui.new("Frame", {
			Position = UDim2.fromOffset(x, 30),
			Size = UDim2.fromOffset(74, 66),
			BackgroundColor3 = Color3.fromRGB(50, 52, 66),
			Parent = rewardBox,
		})
		Ui.corner(6).Parent = tile
		Ui.stroke(C.winEdge, 2).Parent = tile
		Icons.draw(icon, tile, 40, UDim2.new(0.5, 0, 0, 24))
		return Ui.label("", UDim2.new(1, 0, 0, 22), 18, C.white, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -2),
			Parent = tile,
		})
	end
	local rewardMoney = rewardTile(40, "coin")
	local rewardSpeed = rewardTile(130, "shoe")
	local claimH = Ui.touch(56, SIZE)
	local claim = Ui.button("획득!", Color3.fromRGB(150, 150, 160), UDim2.new(1, -24, 0, claimH), nil, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -10),
		textSize = 30,
		parent = rewardBox,
		sound = "Reward",
	})
	claim.Name = "Claim"

	-- 아래: 모두 획득 / 잠금 해제
	local footer: Frame = Ui.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, -260, 0, 66),
		BackgroundColor3 = C.winDark,
		Parent = content,
	})
	Ui.corner(8).Parent = footer
	Icons.draw("book", footer, 50, UDim2.new(0, 34, 0.5, 0))
	local claimAll = Ui.button("모두 획득!", C.indexCyan, UDim2.new(1, -76, 1, -10), function()
		Net.send(Remotes.ToServer.ClaimIndexReward, "all")
	end, {
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -5, 0.5, 0),
		textSize = 30,
		parent = footer,
		sound = "Reward",
	})
	claimAll.Name = "ClaimAll"
	local unlockLabel = Ui.label("", UDim2.new(1, -76, 1, 0), 30, C.white, {
		Name = "Unlocked",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Parent = footer,
	})

	local selected = Biomes.list[1].id
	local selectedPet: string? = nil
	local tabButtons: { [string]: TextButton } = {}
	local currentView: Instance? = nil
	local render: () -> ()

	local function snapshotSets(): ({ [string]: boolean }, { [string]: boolean })
		local snap = State.get()
		return if snap then snap.indexDiscovered or {} else {}, if snap then snap.indexClaimed or {} else {}
	end

	local function renderDetail()
		local discovered, claimed = snapshotSets()
		local list = Pets.inBiome(selected)
		local petId = selectedPet
		if petId == nil or Pets.get(petId) == nil then
			petId = if list[1] then list[1].id else nil
			selectedPet = petId
		end
		local old = currentView
		if old then
			old:Destroy()
			currentView = nil
		end
		local pet = if petId then Pets.get(petId) else nil
		if not pet then
			detailName.Text = "???"
			detailRarity.Text = ""
			detailIncome.Text = ""
			return
		end
		local found = discovered[pet.id] == true
		local view = PetViewport.new(pet.id, {
			silhouette = not found,
			size = UDim2.new(1, -10, 0, 128),
			position = UDim2.fromOffset(5, 4),
		})
		view.Parent = viewBox
		currentView = view
		local rarity = Rarities.get(pet.rarity)
		detailName.Text = if found then pet.name else "???"
		detailRarity.Text = if rarity then rarity.displayName else pet.rarity
		detailRarity.TextColor3 = Theme.rarityColor(pet.rarity)
		local oldRainbow = detailRarity:FindFirstChild("Rainbow")
		if oldRainbow then
			oldRainbow:Destroy()
		end
		if Theme.RainbowRarities[pet.rarity] then
			detailRarity.TextColor3 = C.white
			rainbow(detailRarity, pet.rarity)
		end
		-- 열매 1개 값(보통 크기·돌연변이 없음) + 열매 맺는 간격
		detailIncome.Text = if found
			then string.format(
				"열매 1개 %s · %d초마다",
				Format.money(Economy.fruitValue(pet.id, "normal", {})),
				math.floor(Economy.fruitInterval(pet.id) + 0.5)
			)
			else "???"
		local biome = Biomes.get(selected)
		local reward = Index.reward(pet.rarity, pet.fruitValue, if biome then biome.recommendedSpeed else 0)
		rewardMoney.Text = Format.money(reward.money)
		rewardSpeed.Text = "+" .. Format.number(reward.speed)
		local canClaim = found and not claimed[pet.id]
		Ui.setButton(
			claim,
			if claimed[pet.id] then "획득함" else "획득!",
			if canClaim then C.shopGreen else Color3.fromRGB(150, 150, 160),
			canClaim
		)
	end

	local function renderCards()
		for _, child in grid:GetChildren() do
			if child:IsA("GuiButton") or child:IsA("Frame") then
				child:Destroy()
			end
		end
		local discovered, claimed = snapshotSets()
		local list = Pets.inBiome(selected)
		for i, pet in list do
			local found = discovered[pet.id] == true
			local rcolor = Theme.rarityColor(pet.rarity)
			local card: TextButton = Ui.new("TextButton", {
				Name = "Card_" .. pet.id,
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.fromOffset(100, 104),
				BackgroundColor3 = rcolor,
				LayoutOrder = i,
				Parent = grid,
			})
			Ui.corner(6).Parent = card
			if Theme.RainbowRarities[pet.rarity] then
				rainbow(card, pet.rarity)
			else
				Ui.gradient(Theme.lighter(rcolor, 0.3), Theme.darker(rcolor, 0.15)).Parent = card
			end
			local stroke =
				Ui.stroke(if pet.id == selectedPet then C.white else C.winEdge, if pet.id == selectedPet then 4 else 2)
			stroke.Parent = card
			local view = PetViewport.new(pet.id, {
				silhouette = not found,
				size = UDim2.new(1, -6, 1, -24),
				position = UDim2.fromOffset(3, 22),
			})
			view.Parent = card
			Ui.label(if found then pet.name else "???", UDim2.new(1, -4, 0, 22), 18, C.white, {
				Position = UDim2.fromOffset(2, 1),
				TextScaled = true,
				ZIndex = 3,
				Parent = card,
			})
			-- 7판: 카드 아래 등급 영어 이름 (16번은 "H?a.(cke_r!#" 글자 그대로)
			Ui.label(Theme.rarityName(pet.rarity), UDim2.new(1, -4, 0, 16), 13, C.white, {
				Name = "RarityTag",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 2, 1, -2),
				TextScaled = true,
				ZIndex = 3,
				Parent = card,
			})
			if found and not claimed[pet.id] then
				local dot = Ui.badge(card)
				dot.Visible = true
				dot.Size = UDim2.fromOffset(22, 22)
				dot.TextSize = 14
			end
			local id = pet.id
			card.Activated:Connect(function()
				selectedPet = id
				render()
			end)
		end
		local foundCount, total = Progression.biomeProgress(discovered, selected)
		barFill.Size = UDim2.fromScale(math.clamp(foundCount / math.max(total, 1), 0.03, 1), 1)
		barText.Text = string.format("%d/%d", foundCount, total)
		-- 아래: 모두 획득 / 잠금 해제
		local ids = Progression.pendingRewards(discovered, claimed)
		local allFound = 0
		for _ in discovered do
			allFound += 1
		end
		unlockLabel.Text = string.format("잠금 해제: %d/%d", allFound, #Pets.list)
		claimAll.Visible = #ids > 0
		unlockLabel.Visible = #ids == 0
		claimAll.Text = string.format("모두 획득 (%d)!", #ids)
	end

	local function renderTabs()
		local discovered, claimed = snapshotSets()
		for _, biome in Biomes.list do
			local button = tabButtons[biome.id]
			if not button then
				local id = biome.id
				local b: TextButton = Ui.new("TextButton", {
					Name = "Tab_" .. biome.id,
					Text = "",
					AutoButtonColor = false,
					Size = UDim2.new(1, -4, 0, 120),
					BackgroundColor3 = C.win,
					LayoutOrder = biome.order,
					Parent = tabs,
				})
				Ui.corner(6).Parent = b
				zonePicture(b, biome.id)
				local label =
					Ui.label(string.format("%d. %s", biome.order, biome.name), UDim2.new(1, 0, 0, 26), 20, C.white, {
						Name = "Caption",
						Position = UDim2.fromOffset(0, 4),
						ZIndex = 5,
						Parent = b,
					})
				label.TextScaled = true
				b.Activated:Connect(function()
					selected = id
					selectedPet = nil
					render()
				end)
				tabButtons[biome.id] = b
				button = b
			end
			local b = button :: TextButton
			local isSel = biome.id == selected
			local pending = false
			for _, pet in Pets.inBiome(biome.id) do
				if discovered[pet.id] and not claimed[pet.id] then
					pending = true
					break
				end
			end
			local stroke = b:FindFirstChild("SelStroke")
			if not stroke then
				local s = Ui.stroke(C.white, 3)
				s.Name = "SelStroke"
				s.Parent = b
				stroke = s
			end
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = if isSel then C.yellow else C.winEdge
				stroke.Thickness = if isSel then 4 else 2
			end
			local caption = b:FindFirstChild("Caption")
			if caption and caption:IsA("TextLabel") then
				caption.Text = string.format("%d. %s%s", biome.order, biome.name, if pending then " !" else "")
			end
		end
	end

	nextButton.Activated:Connect(function()
		local list = Pets.inBiome(selected)
		local at = 0
		for i, pet in list do
			if pet.id == selectedPet then
				at = i
			end
		end
		local nextPet = list[(at % math.max(#list, 1)) + 1]
		if nextPet then
			selectedPet = nextPet.id
			render()
		end
	end)
	claim.Activated:Connect(function()
		local discovered, claimed = snapshotSets()
		local id = selectedPet
		if id and discovered[id] and not claimed[id] then
			Net.send(Remotes.ToServer.ClaimIndexReward, id)
		end
	end)

	-- 손가락 버튼 46px 이상 (창 배율 기준, 열 때마다 다시)
	local function layout()
		local tabH = Ui.touch(100, SIZE)
		for _, b in tabButtons do
			b.Size = UDim2.new(1, -4, 0, math.max(120, tabH))
		end
		local footH = Ui.touch(56, SIZE)
		footer.Size = UDim2.new(1, -260, 0, footH + 10)
		claimAll.Size = UDim2.new(1, -76, 0, footH)
		claim.Size = UDim2.new(1, -24, 0, Ui.touch(56, SIZE))
	end

	render = function()
		renderTabs()
		layout()
		renderCards()
		renderDetail()
	end

	Windows.register(NAME, window, render)
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "index" or section == "snapshot") then
			render()
		end
	end)
end

return IndexController
