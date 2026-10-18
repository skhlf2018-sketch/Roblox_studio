--!strict
--[[
	IndexController — 도감 창
	- 위: 구역 탭 15개 (가로 스크롤)
	- 가운데: 펫 카드 (발견 전 = 검은 실루엣 "???", 발견 = 3D 펫 + 이름 + 희귀도)
	  발견했고 아직 안 받은 펫은 "받기!" 버튼 → ClaimIndexReward(petId)
	- 아래: 이 구역 진행도 + 무기 보상 + "모두 받기" → ClaimIndexReward("all")
	데이터: State.indexDiscovered / indexClaimed, 보상 미리보기 Index.reward (shared)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Biomes = require(Shared.Data.Biomes)
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Index = require(Shared.Data.Index)
local Format = require(Shared.Format)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local PetViewport = require(Client.UI.PetViewport)

local IndexController = {}

local C = Theme.Colors
local NAME = "Index"
local SIZE = Vector2.new(880, 560)

function IndexController.start()
	local window = Ui.window(NAME, "도감", Theme.Menu.index, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content

	-- 탭
	local tabs: ScrollingFrame = Ui.new("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 62),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = content,
	})
	Ui.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent =
		tabs

	local grid = Ui.scroll(UDim2.new(1, 0, 1, -146), UDim2.fromOffset(0, 68), content)
	local gridLayout = Ui.grid(Vector2.new(146, 192), 10)
	gridLayout.Parent = grid
	Ui.padding(6).Parent = grid

	local footer: Frame = Ui.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundColor3 = C.panelDark,
		Parent = content,
	})
	Ui.corner(16).Parent = footer
	local progressLabel = Ui.label("", UDim2.new(1, -260, 1, 0), 24, C.ink, {
		Position = UDim2.fromOffset(16, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = footer,
	})
	local claimAll = Ui.button("모두 받기", C.green, UDim2.fromOffset(230, 56), function()
		Net.send(Remotes.ToServer.ClaimIndexReward, "all")
	end, {
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -8, 0.5, 0),
		textSize = 24,
		parent = footer,
		sound = "Reward",
	})

	local selected = Biomes.list[1].id
	local tabButtons: { [string]: TextButton } = {}

	local function renderCards()
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local snap = State.get()
		local discovered = if snap then snap.indexDiscovered or {} else {}
		local claimed = if snap then snap.indexClaimed or {} else {}
		local biome = Biomes.get(selected)
		-- "받기!" 버튼: 폰에서도 46px 이상 (창 배율 기준으로 키우고 카드도 그만큼 길게)
		local claimH = Ui.touch(40, SIZE)
		local cardH = 152 + claimH
		gridLayout.CellSize = UDim2.fromOffset(146, cardH)
		for i, pet in Pets.inBiome(selected) do
			local found = discovered[pet.id] == true
			local rcolor = Theme.rarityColor(pet.rarity)
			local card = Ui.card(
				UDim2.fromOffset(146, cardH),
				if found then C.white else Color3.fromRGB(70, 65, 85),
				if found then rcolor else C.gray
			)
			card.LayoutOrder = i
			card.Parent = grid
			local view = PetViewport.new(pet.id, {
				silhouette = not found,
				size = UDim2.new(1, -10, 0, 96),
				position = UDim2.fromOffset(5, 4),
			})
			view.Parent = card
			Ui.label(
				if found then pet.name else "???",
				UDim2.new(1, -8, 0, 26),
				20,
				if found then rcolor else C.white,
				{
					Position = UDim2.fromOffset(4, 100),
					TextScaled = true,
					Parent = card,
				}
			)
			local rarity = Rarities.get(pet.rarity)
			local tag: TextLabel = Ui.new("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 126),
				Size = UDim2.fromOffset(90, 20),
				BackgroundColor3 = rcolor,
				TextColor3 = Theme.rarityText(pet.rarity),
				TextSize = 15,
				Text = if rarity then rarity.name else pet.rarity,
				Parent = card,
			})
			Ui.corner(1).Parent = tag
			if found and not claimed[pet.id] then
				local reward = Index.reward(pet.rarity, pet.income, if biome then biome.recommendedSpeed else 0)
				local petId = pet.id
				local b = Ui.button("받기!", C.green, UDim2.new(1, -12, 0, claimH), function()
					Net.send(Remotes.ToServer.ClaimIndexReward, petId)
				end, {
					anchor = Vector2.new(0.5, 1),
					position = UDim2.new(0.5, 0, 1, -4),
					textSize = 18,
					parent = card,
					sound = "Reward",
				})
				b.Name = "Claim"
				local hint = Ui.label(
					"+" .. Format.number(reward.speed) .. " 속도 " .. Format.money(reward.money),
					UDim2.new(1, 0, 0, 18),
					13,
					C.money,
					{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -10), Parent = b }
				)
				hint.ZIndex = 3
			elseif found then
				Ui.label("받음", UDim2.new(1, 0, 0, 22), 18, C.gray, {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -4),
					Parent = card,
				})
			end
		end
		-- 아래 정보
		local foundCount, total = Progression.biomeProgress(discovered, selected)
		local weapon = if biome and biome.weapon then biome.weapon.name else nil
		progressLabel.Text = string.format(
			"%s  %d/%d 발견%s",
			if biome then biome.name else selected,
			foundCount,
			total,
			if weapon then "  ·  다 모으면 무기: " .. weapon else ""
		)
		local ids = Progression.pendingRewards(discovered, claimed)
		if #ids > 0 then
			Ui.setButton(claimAll, string.format("모두 받기 (%d)", #ids), C.green, true)
		else
			Ui.setButton(claimAll, "받을 보상 없음", C.gray, false)
		end
	end

	local function renderTabs()
		local snap = State.get()
		local discovered = if snap then snap.indexDiscovered or {} else {}
		local claimed = if snap then snap.indexClaimed or {} else {}
		for _, biome in Biomes.list do
			local button = tabButtons[biome.id]
			if not button then
				local id = biome.id
				button = Ui.button(
					string.format("%d. %s", biome.order, biome.name),
					C.blue,
					UDim2.fromOffset(140, 50),
					function()
						selected = id
						renderTabs()
						renderCards()
					end,
					{ layoutOrder = biome.order, parent = tabs, textSize = 19 }
				)
				tabButtons[biome.id] = button
			end
			local b = button :: TextButton
			local isSel = biome.id == selected
			local found, total = Progression.biomeProgress(discovered, biome.id)
			local pending = false
			for _, pet in Pets.inBiome(biome.id) do
				if discovered[pet.id] and not claimed[pet.id] then
					pending = true
					break
				end
			end
			local color = if isSel then C.orange elseif found >= total and total > 0 then C.green else C.blue
			Ui.setButton(b, string.format("%d. %s%s", biome.order, biome.name, if pending then " !" else ""), color)
		end
	end

	-- 탭·"모두 받기"도 폰에서 46px 이상 (창 배율 기준, 열 때마다 다시)
	local function layout()
		local tabH = Ui.touch(50, SIZE)
		local footH = Ui.touch(56, SIZE)
		tabs.Size = UDim2.new(1, 0, 0, tabH + 12)
		footer.Size = UDim2.new(1, 0, 0, footH + 14)
		claimAll.Size = UDim2.fromOffset(230, footH)
		grid.Position = UDim2.fromOffset(0, tabH + 18)
		grid.Size = UDim2.new(1, 0, 1, -(tabH + 18 + footH + 22))
		for _, button in tabButtons do
			button.Size = UDim2.fromOffset(140, tabH)
		end
	end

	local function render()
		renderTabs()
		layout()
		renderCards()
	end

	Windows.register(NAME, window, render)
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "index" or section == "snapshot") then
			render()
		end
	end)
end

return IndexController
