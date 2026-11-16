--!strict
--[[
	IndexController — 도감 창 "Index" (선임)
	  물건 41개를 월드별로 (월드 1 태권도장 마을 · 2 지구 한 바퀴 · 3 우주). 카드마다 이름 · 💰 값 · 💪 필요한 힘 · "깬 횟수 N".
	  아직 안 깬 물건은 "???" + 큰 물음표 (값·힘은 보임 — 다음 목표를 알 수 있게).
	  위: "깬 물건 12 / 41". 깬 횟수는 Snapshot.broken (DataUpdate "progress" 로 갱신).
	공개: NAME · render() · discovered()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Targets = require(Shared.Data.Targets)
local Worlds = require(Shared.Data.Worlds)
local Format = require(Shared.Format)
local Client = script.Parent.Parent
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local HudController = require(script.Parent.HudController)

local IndexController = {}
local NAME = "Index"
IndexController.NAME = NAME

local C = Theme.Colors
local SIZE = Vector2.new(860, 580)
local CARD = Vector2.new(150, 150)

-- 한 번이라도 깬 물건 수
function IndexController.discovered(): number
	local n = 0
	for _, t in Targets.list do
		if State.broken(t.id) > 0 then
			n += 1
		end
	end
	return n
end

local renderFn: (() -> ())? = nil
function IndexController.render()
	local fn = renderFn
	if fn then
		fn()
	end
end

function IndexController.start()
	local window = Ui.window(NAME, "📖 도감", Theme.Menu.index, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content
	local summary = Ui.label("", UDim2.new(1, 0, 0, 30), 24, C.yellow, { Name = "Summary", Parent = content })
	local scroll = Ui.scroll(UDim2.new(1, 0, 1, -36), UDim2.fromOffset(0, 36), content)
	Ui.list(Enum.FillDirection.Vertical, 8).Parent = scroll
	Ui.padding(4).Parent = scroll

	type Card = { card: Frame, name: TextLabel, count: TextLabel, mark: TextLabel, target: Targets.Target }
	local cards: { Card } = {}
	for _, world in Worlds.list do
		local head = Ui.label(
			string.format("월드 %d · %s", world.index, world.name),
			UDim2.new(1, -8, 0, 34),
			26,
			Theme.worldColor(world.index),
			{
				Name = "World_" .. tostring(world.index),
				LayoutOrder = world.index * 100,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = scroll,
			}
		)
		head.TextScaled = false
		local group: Frame = Ui.new("Frame", {
			Name = "Group_" .. tostring(world.index),
			LayoutOrder = world.index * 100 + 1,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = scroll,
		})
		Ui.grid(CARD, 8).Parent = group
		for _, t in Targets.byWorld(world.index) do
			local card = Ui.card(UDim2.fromOffset(CARD.X, CARD.Y), C.winDark, C.winEdge)
			card.Name = "Target_" .. t.id
			card.LayoutOrder = t.index
			card.Parent = group
			local mark = Ui.label("?", UDim2.new(1, 0, 0, 52), 48, C.gray, {
				Name = "Mark",
				Position = UDim2.fromOffset(0, 4),
				Parent = card,
			})
			local name = Ui.label("???", UDim2.new(1, -8, 0, 28), 22, C.white, {
				Name = "Name",
				Position = UDim2.fromOffset(4, 56),
				TextScaled = true,
				Parent = card,
			})
			Ui.label("💰 " .. Format.number(t.reward), UDim2.new(1, -8, 0, 20), 18, C.money, {
				Name = "Reward",
				Position = UDim2.fromOffset(4, 84),
				TextScaled = true,
				Parent = card,
			})
			Ui.label("💪 " .. Format.number(t.minPower), UDim2.new(1, -8, 0, 18), 16, C.power, {
				Name = "Need",
				Position = UDim2.fromOffset(4, 104),
				TextScaled = true,
				Parent = card,
			})
			local count = Ui.label("", UDim2.new(1, -8, 0, 18), 16, C.yellow, {
				Name = "Count",
				Position = UDim2.fromOffset(4, 126),
				TextScaled = true,
				Parent = card,
			})
			table.insert(cards, { card = card, name = name, count = count, mark = mark, target = t })
		end
	end

	local function render()
		summary.Text = string.format("깬 물건 %d / %d", IndexController.discovered(), #Targets.list)
		for _, e in cards do
			local n = State.broken(e.target.id)
			if n > 0 then
				e.name.Text = e.target.name
				e.mark.Text = "★"
				e.mark.TextColor3 = C.yellow
				e.count.Text = "깬 횟수 " .. Format.number(n)
				e.card.BackgroundColor3 = Color3.fromRGB(44, 62, 84)
			else
				e.name.Text = "???"
				e.mark.Text = "?"
				e.mark.TextColor3 = C.gray
				e.count.Text = "아직 못 깼어요"
				e.card.BackgroundColor3 = C.winDark
			end
		end
	end
	renderFn = render
	Windows.register(NAME, window, render)
	render()
	State.onChanged(function(section: string)
		if Windows.isOpen(NAME) and (section == "progress" or section == "snapshot") then
			render()
		end
	end)

	HudController.addMenuButton("index", "도감", 2, function()
		Windows.toggle(NAME)
	end)
end

return IndexController
