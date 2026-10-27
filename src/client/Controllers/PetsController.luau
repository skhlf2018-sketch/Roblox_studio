--!strict
--[[
	PetsController — 펫 창 (보관함 · 장착 · Equip Best)
	[6판 수석 임시 — 선임이 "정원 식물" 창으로 다시 꾸밀 예정] 장착 개념이 없어져서:
	  "최고 펫 장착"(EquipBest) → "열매 모두 따기" PickFruit("all"), 카드의 장착/해제 → "열매 따기" PickFruit(uid),
	  판매(SellPet) → 뽑아서 팔기 SellPlant(uid) (값 = GardenRules.sellPrice = 열매 1개 값 × 20)
	- 위: 장착 칸 "장착 3/7", "최고 펫 장착" 버튼(EquipBest), 쪽 넘기기
	- 카드: 3D 펫, 이름(희귀도 색), 초당 수입(Economy.recordIncome), 크기/돌연변이, 장착/해제 버튼
	- 장착한 펫이 먼저, 그다음 수입 높은 순. 한 쪽에 18마리.
	- 2판: 판매 가게(태그 SellStall: 허브 1곳 + 베이스마다) 근처(Config.SELL_RADIUS)면 카드마다 "판매 $가격" 버튼 → SellPet(uid)
	  (가격 = 초당 수입 × Config.PET_SELL_SECONDS, 서버가 다시 계산·검사). 판매 가게 프롬프트 "펫 팔기" 로 이 창이 열림.
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

local PetsController = {}

local C = Theme.Colors
local NAME = "Pets"
local PAGE = 18
local SIZE = Vector2.new(900, 570)

-- 판매 가게 근처인가 (보기용 — 서버가 다시 검사)
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
	if size then
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
	local slotsLabel = Ui.label("", UDim2.fromOffset(300, 60), 26, C.white, {
		Position = UDim2.fromOffset(16, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = top,
	})
	local bestButton = Ui.button("열매 모두 따기", C.orange, UDim2.fromOffset(210, 50), function()
		Net.send(Remotes.ToServer.PickFruit, "all")
	end, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		textSize = 24,
		parent = top,
		sound = "Equip",
	})
	local pageLabel = Ui.label("1/1", UDim2.fromOffset(80, 60), 22, C.white, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, 0),
		Parent = top,
	})
	local page = 1
	local render: () -> ()
	local prevButton = Ui.button("<", C.blue, UDim2.fromOffset(50, 50), function()
		page = math.max(1, page - 1)
		render()
	end, { anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -152, 0.5, 0), textSize = 28, parent = top })
	local nextButton = Ui.button(">", C.blue, UDim2.fromOffset(50, 50), function()
		page += 1
		render()
	end, { anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -10, 0.5, 0), textSize = 28, parent = top })

	local grid = Ui.scroll(UDim2.new(1, 0, 1, -70), UDim2.fromOffset(0, 70), content)
	local gridLayout = Ui.grid(Vector2.new(140, 214), 10)
	gridLayout.Parent = grid
	Ui.padding(6).Parent = grid
	local empty = Ui.label(
		"아직 성체 식물이 없어요! 씨앗을 훔쳐서 정원에 심어요.",
		UDim2.new(1, 0, 0, 60),
		26,
		C.white,
		{
			Position = UDim2.fromOffset(0, 200),
			Visible = false,
			Parent = content,
		}
	)

	render = function()
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local snap = State.get()
		if not snap then
			return
		end
		local list = table.clone(snap.pets or {})
		table.sort(list, function(a: Types.PetRecord, b: Types.PetRecord): boolean
			local ia, ib = Economy.recordIncome(a), Economy.recordIncome(b)
			if ia ~= ib then
				return ia > ib
			end
			return a.uid < b.uid
		end)
		-- 장착 버튼: 폰에서도 46px 이상 (창 배율에 맞춰 키우고, 카드도 그만큼 길게)
		local buttonH = Ui.touch(52, SIZE)
		local sellNear = nearSellStall()
		local cardH = 162 + buttonH + (if sellNear then buttonH + 6 else 0)
		gridLayout.CellSize = UDim2.fromOffset(140, cardH)
		-- 위 막대 버튼도 같은 기준
		local topH = Ui.touch(50, SIZE)
		top.Size = UDim2.new(1, 0, 0, topH + 10)
		bestButton.Size = UDim2.fromOffset(210, topH)
		prevButton.Size = UDim2.fromOffset(math.max(50, topH), topH)
		nextButton.Size = UDim2.fromOffset(math.max(50, topH), topH)
		prevButton.Position = UDim2.new(1, -(30 + math.max(50, topH) + 80), 0.5, 0)
		slotsLabel.Size = UDim2.fromOffset(300, topH + 10)
		pageLabel.Size = UDim2.fromOffset(80, topH + 10)
		pageLabel.Position = UDim2.new(1, -(20 + math.max(50, topH)), 0, 0)
		grid.Position = UDim2.fromOffset(0, topH + 20)
		grid.Size = UDim2.new(1, 0, 1, -(topH + 20))
		local slots = snap.penSlots or 0
		local used = #list + #(snap.incubators or {})
		slotsLabel.Text = string.format("정원 %d/%d  ·  성체 %d", used, slots, #list)
		local pages = math.max(1, math.ceil(#list / PAGE))
		page = math.clamp(page, 1, pages)
		pageLabel.Text = string.format("%d/%d", page, pages)
		empty.Visible = #list == 0
		for i = (page - 1) * PAGE + 1, math.min(#list, page * PAGE) do
			local record = list[i]
			local pet = Pets.get(record.petId)
			local rarityId = if pet then pet.rarity else "common"
			local rcolor = Theme.rarityColor(rarityId)
			local isEquipped = false -- 6판: 장착 없음
			local card = Ui.card(
				UDim2.fromOffset(140, cardH),
				if isEquipped then Color3.fromRGB(78, 70, 34) else Color3.fromRGB(62, 64, 78),
				if isEquipped then C.yellow else rcolor
			)
			card.LayoutOrder = i
			card.Parent = grid
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke and isEquipped then
				stroke.Thickness = 5
			end
			local view =
				PetViewport.new(record.petId, { size = UDim2.new(1, -10, 0, 82), position = UDim2.fromOffset(5, 4) })
			view.Parent = card
			Ui.label(if pet then pet.name else record.petId, UDim2.new(1, -8, 0, 24), 19, rcolor, {
				Position = UDim2.fromOffset(4, 86),
				TextScaled = true,
				Parent = card,
			})
			local rarity = Rarities.get(rarityId)
			Ui.label(
				(if rarity then rarity.name .. " · " else "") .. Format.money(Economy.recordIncome(record)) .. "/초",
				UDim2.new(1, -8, 0, 20),
				16,
				C.money,
				{ Position = UDim2.fromOffset(4, 110), TextScaled = true, Parent = card }
			)
			Ui.label(detail(record), UDim2.new(1, -8, 0, 18), 14, C.orange, {
				Position = UDim2.fromOffset(4, 131),
				TextScaled = true,
				Parent = card,
			})
			local uid = record.uid
			do
				local fruits = tonumber(record.fruits) or 0
				local b = Ui.button(
					string.format("열매 따기 %d/%d", fruits, Config.FRUIT_MAX_PER_PLANT),
					if fruits > 0 then C.green else C.gray,
					UDim2.new(1, -14, 0, buttonH),
					function()
						Net.send(Remotes.ToServer.PickFruit, uid)
					end,
					{
						anchor = Vector2.new(0.5, 1),
						position = UDim2.new(0.5, 0, 1, -6),
						textSize = 20,
						parent = card,
						sound = "Equip",
					}
				)
				b.Name = "PickFruit"
			end
			if sellNear then
				local price = GardenRules.sellPrice(record)
				local sell = Ui.button(
					"뽑아서 팔기 " .. Format.number(price),
					C.eggRed,
					UDim2.new(1, -14, 0, buttonH),
					function()
						Net.trySend(Remotes.ToServer.SellPlant, uid)
					end,
					{
						anchor = Vector2.new(0.5, 1),
						position = UDim2.new(0.5, 0, 1, -(buttonH + 12)),
						textSize = 20,
						parent = card,
						sound = "Sell",
					}
				)
				sell.Name = "Sell"
			end
		end
	end

	-- 판매 가판대 프롬프트 "식물 팔기" → 이 창 (뽑아서 팔기 버튼이 보임)
	WorldPrompt.attach({
		tag = Tags.SellStall,
		name = "SellPrompt",
		action = "식물 팔기",
		object = "판매",
		distance = Config.SELL_RADIUS - 2,
		onTrigger = function()
			Windows.open(NAME)
		end,
	})
	-- 창이 열린 채 판매 가게에 가까워지거나 멀어지면 판매 버튼을 다시 그림
	task.spawn(function()
		local last = false
		while true do
			task.wait(1)
			local near = nearSellStall()
			if near ~= last and Windows.isOpen(NAME) then
				render()
			end
			last = near
		end
	end)

	Windows.register(NAME, window, render)
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "pets" or section == "snapshot" or section == "upgrades") then
			render()
		end
	end)
end

return PetsController
