--!strict
--[[
	PetsController — 정원 식물 창 (오른쪽 주황 식물 버튼, 6판 "씨앗을 훔치세요")

	- 위: "정원 5/9 · 성체 3" (정원 칸 = 자라는 씨앗 + 성체 / penSlots), "열매 모두 따기"(PickAllFruit → PickFruit("all")),
	  "열매 가방 12/300"(FruitBagOpen → 열매 가방 창), 쪽 넘기기
	- 카드 (성체 식물마다): 3D 식물, 이름(등급 색), "열매 3/5 · 1개 40 코인"(FruitRules.fruitValue), 크기/돌연변이,
	  "다음 열매 12초"(1초마다 — fruitInterval - fruitProgress, 마지막 DataUpdate("pets") 뒤 흐른 시간만큼 이어 셈, 가득이면 "열매 가득!"),
	  버튼 "열매 따기 3/5"(PickFruit = PickFruit(uid)) · "먹이기"(Feed → 열매 고르기 → FeedFruit) · "팔기 N"(Sell → 확인 창 → SellPlant(uid))
	  (팔기 값 = GardenRules.sellPrice = 열매 1개 값 × 20, 서버가 다시 계산 — 내 정원 근처나 판매 가판대 근처에서만 됨)
	- 열매 값 높은 순. 한 쪽에 18그루.
	- 판매 가판대(SellStall) 프롬프트 "식물 팔기"(F — E 는 "열매 팔기") → 이 창.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Data.Pets)
local Config = require(Shared.Data.Config)
local Tags = require(Shared.Tags)
local Rarities = require(Shared.Data.Rarities)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local Economy = require(Shared.Economy)
local FruitRules = require(Shared.FruitRules)
local GardenRules = require(Shared.GardenRules)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local PetViewport = require(Client.UI.PetViewport)
local WorldPrompt = require(Client.UI.WorldPrompt)
local FruitBagController = require(script.Parent.FruitBagController)

local PetsController = {}

local C = Theme.Colors
local NAME = "Pets"
local PAGE = 18
local SIZE = Vector2.new(900, 570)
local CARD_W = 150

-- 판매 가판대 근처인가 (보기용 — 서버가 다시 검사)
local function nearSellStall(): boolean
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return false
	end
	for _, inst in CollectionService:GetTagged(Tags.SellStall) do
		if inst:IsA("BasePart") and WorldPrompt.distanceTo(inst, root.Position) <= Config.SELL_RADIUS then
			return true
		end
	end
	return false
end
PetsController.nearSellStall = nearSellStall

local function detail(record: Types.PetRecord): string
	local parts: { string } = {}
	local size = Sizes.get(record.size)
	if size and size.id ~= Sizes.DEFAULT then
		table.insert(parts, size.name)
	end
	for _, id in record.mutations do
		local m = Mutations.get(id)
		if m then
			table.insert(parts, m.name)
		end
	end
	return table.concat(parts, " · ")
end

local function plantName(petId: string): string
	local pet = Pets.get(petId)
	return if pet then pet.name else petId
end

-- 마지막으로 성체 목록을 받은 때 (다음 열매까지 남은 초를 이어 세는 기준)
local petsStamp = os.clock()

-- 다음 열매까지 남은 초 (가득이면 nil)
function PetsController.nextFruitIn(record: Types.PetRecord, now: number?): number?
	local fruits = tonumber(record.fruits) or 0
	if fruits >= Config.FRUIT_MAX_PER_PLANT then
		return nil
	end
	local interval = Economy.fruitInterval(record.petId)
	if interval == math.huge or interval <= 0 then
		return nil
	end
	local elapsed = (now or os.clock()) - petsStamp
	local progress = (tonumber(record.fruitProgress) or 0) + math.max(0, elapsed)
	return math.max(0, interval - progress % interval)
end

local function nextText(record: Types.PetRecord): string
	local left = PetsController.nextFruitIn(record)
	if not left then
		return "열매 가득! 따 주세요"
	end
	return string.format("다음 열매 %d초", math.ceil(left))
end

-- 뽑아서 팔기 확인 창
function PetsController.confirmSell(record: Types.PetRecord)
	local price = GardenRules.sellPrice(record)
	local fruits = tonumber(record.fruits) or 0
	local warn = if fruits > 0
		then string.format("\n달린 열매 %d개도 같이 없어져요 — 먼저 따세요!", fruits)
		else ""
	local uid = record.uid
	Ui.confirm(
		"뽑아서 팔기",
		string.format("%s 을(를) 뽑아서 %s 에 팔까요?%s", plantName(record.petId), Format.money(price), warn),
		"팔기 " .. Format.money(price),
		function()
			Net.trySend(Remotes.ToServer.SellPlant, uid)
		end,
		C.eggRed
	)
end

function PetsController.start()
	local window = Ui.window(NAME, "정원 식물", Theme.Menu.pets, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content

	local top: Frame = Ui.new("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundColor3 = C.winDark,
		Parent = content,
	})
	Ui.corner(16).Parent = top
	local slotsLabel = Ui.label("", UDim2.fromOffset(250, 60), 24, C.white, {
		Name = "Slots",
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Parent = top,
	})
	local pickAll = Ui.button("열매 모두 따기", C.orange, UDim2.fromOffset(190, 50), function()
		Net.send(Remotes.ToServer.PickFruit, "all")
	end, {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, 270, 0.5, 0),
		textSize = 22,
		parent = top,
	})
	pickAll.Name = "PickAllFruit"
	local bagButton = Ui.button("열매 가방", C.green, UDim2.fromOffset(180, 50), function()
		Windows.open(FruitBagController.NAME)
	end, {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, 470, 0.5, 0),
		textSize = 20,
		parent = top,
	})
	bagButton.Name = "FruitBagOpen"
	local pageLabel = Ui.label("1/1", UDim2.fromOffset(60, 60), 22, C.white, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, 0),
		Parent = top,
	})
	local page = 1
	local render: () -> ()
	local prevButton = Ui.button("<", C.blue, UDim2.fromOffset(50, 50), function()
		page = math.max(1, page - 1)
		render()
	end, { anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -132, 0.5, 0), textSize = 28, parent = top })
	local nextButton = Ui.button(">", C.blue, UDim2.fromOffset(50, 50), function()
		page += 1
		render()
	end, { anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -10, 0.5, 0), textSize = 28, parent = top })

	local grid = Ui.scroll(UDim2.new(1, 0, 1, -70), UDim2.fromOffset(0, 70), content)
	local gridLayout = Ui.grid(Vector2.new(CARD_W, 214), 10)
	gridLayout.Parent = grid
	Ui.padding(6).Parent = grid
	local empty = Ui.label(
		"아직 성체 식물이 없어요! 씨앗을 훔쳐서 정원에 심어요.",
		UDim2.new(1, 0, 0, 60),
		26,
		C.white,
		{
			Name = "Empty",
			Position = UDim2.fromOffset(0, 200),
			Visible = false,
			Parent = content,
		}
	)

	-- 1초마다 바꾸는 "다음 열매" 글
	local nextLabels: { [TextLabel]: Types.PetRecord } = {}

	render = function()
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(nextLabels)
		local snap = State.get()
		if not snap then
			return
		end
		local list = table.clone(snap.pets or {})
		table.sort(list, function(a: Types.PetRecord, b: Types.PetRecord): boolean
			local va, vb = FruitRules.fruitValue(a), FruitRules.fruitValue(b)
			if va ~= vb then
				return va > vb
			end
			return a.uid < b.uid
		end)
		-- 버튼: 폰에서도 46px 이상 (창 배율에 맞춰 키우고, 카드도 그만큼 길게)
		local buttonH = Ui.touch(48, SIZE)
		local cardH = 172 + buttonH * 2 + 8
		gridLayout.CellSize = UDim2.fromOffset(CARD_W, cardH)
		-- 위 막대 버튼도 같은 기준
		local topH = Ui.touch(50, SIZE)
		top.Size = UDim2.new(1, 0, 0, topH + 10)
		pickAll.Size = UDim2.fromOffset(190, topH)
		bagButton.Size = UDim2.fromOffset(180, topH)
		prevButton.Size = UDim2.fromOffset(math.max(50, topH), topH)
		nextButton.Size = UDim2.fromOffset(math.max(50, topH), topH)
		prevButton.Position = UDim2.new(1, -(20 + math.max(50, topH) + 62), 0.5, 0)
		slotsLabel.Size = UDim2.fromOffset(250, topH + 10)
		pageLabel.Size = UDim2.fromOffset(60, topH + 10)
		pageLabel.Position = UDim2.new(1, -(14 + math.max(50, topH)), 0, 0)
		grid.Position = UDim2.fromOffset(0, topH + 20)
		grid.Size = UDim2.new(1, 0, 1, -(topH + 20))
		local slots = snap.penSlots or 0
		local used = #list + #(snap.incubators or {})
		slotsLabel.Text = string.format("정원 %d/%d  ·  성체 %d", used, slots, #list)
		local bagCount = FruitRules.bagCount(snap.fruits or {})
		Ui.setButton(
			bagButton,
			string.format("열매 가방 %d/%d", bagCount, snap.fruitBagMax or Config.FRUIT_BAG_MAX)
		)
		local anyFruit = false
		for _, record in list do
			if (tonumber(record.fruits) or 0) > 0 then
				anyFruit = true
				break
			end
		end
		Ui.setButton(pickAll, nil, if anyFruit then C.orange else C.gray)
		local pages = math.max(1, math.ceil(#list / PAGE))
		page = math.clamp(page, 1, pages)
		pageLabel.Text = string.format("%d/%d", page, pages)
		empty.Visible = #list == 0
		for i = (page - 1) * PAGE + 1, math.min(#list, page * PAGE) do
			local record = list[i]
			local pet = Pets.get(record.petId)
			local rarityId = if pet then pet.rarity else "common"
			local rcolor = Theme.rarityColor(rarityId)
			local card = Ui.card(UDim2.fromOffset(CARD_W, cardH), Color3.fromRGB(62, 64, 78), rcolor)
			card.Name = record.uid
			card.LayoutOrder = i
			card.Parent = grid
			local view =
				PetViewport.new(record.petId, { size = UDim2.new(1, -10, 0, 82), position = UDim2.fromOffset(5, 4) })
			view.Parent = card
			Ui.label(plantName(record.petId), UDim2.new(1, -8, 0, 24), 19, rcolor, {
				Name = "PlantName",
				Position = UDim2.fromOffset(4, 86),
				TextScaled = true,
				Parent = card,
			})
			local fruits = tonumber(record.fruits) or 0
			local rarity = Rarities.get(rarityId)
			Ui.label(
				string.format(
					"%s열매 1개 %s",
					if rarity then rarity.name .. " · " else "",
					Format.money(FruitRules.fruitValue(record))
				),
				UDim2.new(1, -8, 0, 20),
				16,
				C.money,
				{ Name = "FruitValue", Position = UDim2.fromOffset(4, 110), TextScaled = true, Parent = card }
			)
			local nextLabel = Ui.label(nextText(record), UDim2.new(1, -8, 0, 18), 15, C.white, {
				Name = "NextFruit",
				Position = UDim2.fromOffset(4, 131),
				TextScaled = true,
				Parent = card,
			})
			nextLabels[nextLabel] = record
			Ui.label(detail(record), UDim2.new(1, -8, 0, 18), 14, C.orange, {
				Name = "Detail",
				Position = UDim2.fromOffset(4, 150),
				TextScaled = true,
				Parent = card,
			})
			local uid = record.uid
			local pick = Ui.button(
				string.format("열매 따기 %d/%d", fruits, Config.FRUIT_MAX_PER_PLANT),
				if fruits > 0 then C.green else C.gray,
				UDim2.new(1, -14, 0, buttonH),
				function()
					Net.send(Remotes.ToServer.PickFruit, uid)
				end,
				{
					anchor = Vector2.new(0.5, 1),
					position = UDim2.new(0.5, 0, 1, -(buttonH + 12)),
					textSize = 20,
					parent = card,
				}
			)
			pick.Name = "PickFruit"
			local feed = Ui.button("먹이기", C.purple, UDim2.new(0.5, -10, 0, buttonH), function()
				FruitBagController.feedPlant(uid)
			end, {
				anchor = Vector2.new(0, 1),
				position = UDim2.new(0, 7, 1, -6),
				textSize = 18,
				parent = card,
			})
			feed.Name = "Feed"
			local sell = Ui.button(
				"팔기 " .. Format.number(GardenRules.sellPrice(record)),
				C.eggRed,
				UDim2.new(0.5, -10, 0, buttonH),
				function()
					PetsController.confirmSell(record)
				end,
				{
					anchor = Vector2.new(1, 1),
					position = UDim2.new(1, -7, 1, -6),
					textSize = 16,
					parent = card,
					sound = "Click",
				}
			)
			sell.Name = "Sell"
		end
	end

	-- 판매 가판대 프롬프트 "식물 팔기" (F) → 이 창 (E 는 FruitBagController 의 "열매 팔기")
	WorldPrompt.attach({
		tag = Tags.SellStall,
		name = "SellPrompt",
		action = "식물 팔기",
		object = "판매 가판대",
		key = Enum.KeyCode.F,
		distance = Config.SELL_RADIUS - 2,
		onTrigger = function()
			Windows.open(NAME)
		end,
	})
	-- 열린 창의 "다음 열매 n초" 1초마다
	task.spawn(function()
		while true do
			task.wait(1)
			if Windows.isOpen(NAME) then
				for label, record in nextLabels do
					if label.Parent then
						label.Text = nextText(record)
					else
						nextLabels[label] = nil
					end
				end
			end
		end
	end)

	Windows.register(NAME, window, render)
	State.onChanged(function(section: string)
		if section == "pets" or section == "snapshot" then
			petsStamp = os.clock()
		end
		if
			Windows.isOpen(NAME)
			and (
				section == "pets"
				or section == "snapshot"
				or section == "upgrades"
				or section == "incubators"
				or section == "fruits"
			)
		then
			render()
		end
	end)
end

return PetsController
