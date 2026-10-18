--!strict
--[[
	PetPicker — "펫 N마리 고르기" 공용 창 (퓨전 머신 · 사쿠라 인큐베이터 · 제단 · 비밀 통로)

	  PetPicker.open({
	      title = "퓨전 머신", color = Theme.Colors.purple,
	      hint = "같은 펫 3마리를 골라요",
	      count = 3,                                  -- 정확히 이만큼 고르면 확인 버튼이 켜짐
	      filters = { PetPicker.sameSpecies(3) },     -- 위쪽 필터 버튼 (켜면 안 맞는 카드는 숨김)
	      check = function(item, selected) return true end,   -- false, "이유" = 회색 카드(못 고름)
	      ready = function(selected) return true end,         -- 확인 버튼 조건 (기본: count 만큼 골랐나)
	      status = function(selected) return "나올 수 있는 펫: ..." end, -- 안내 줄을 고른 것에 따라 바꿈
	      onConfirm = function(selected) Net.send(...) end,
	      closeWhen = function() return 멀어졌나 end,       -- true 가 되면 저절로 닫힘
	  })

	- 카드: 희귀도 색 테두리 + 3D 펫(알이면 알 모양) + 이름·희귀도·수입·크기/돌연변이. 카드 전체가 버튼(폰에서도 큼).
	- 고른 카드는 노란 두꺼운 테두리 + 순서 번호. 한 쪽 24장, < > 로 넘김.
	- 항목(items)을 안 주면 내 보관함 펫 전부. State 가 바뀌면 다시 그림 (없어진 펫은 선택에서 빠짐).
	- 아래 버튼(필터·취소·확인)은 화면에서 46px 이상 (Ui.touch).
	- 확인을 누르면 창을 닫고 onConfirm 만 부름. 결과는 서버 이벤트로 옴.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local Visuals = require(Shared.Data.Visuals)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local Client = script.Parent.Parent
local State = require(Client.State)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)
local PetViewport = require(script.Parent.PetViewport)

local PetPicker = {}

local C = Theme.Colors
local NAME = "PetPicker"
local BASE = Vector2.new(920, 560)
local PAGE = 24
local CARD = Vector2.new(132, 178)

export type Item = {
	uid: string,
	petId: string,
	size: string,
	mutations: { string },
	kind: string?, -- "pet"(기본) | "egg"
	note: string?, -- 카드 아래 작은 글 ("부화 중 알" 등)
	equipped: boolean?,
}

export type Filter = {
	id: string,
	label: string,
	default: boolean?,
	test: (item: Item, selected: { Item }) -> boolean,
}

export type Options = {
	title: string,
	liveTitle: (() -> string)?, -- 있으면 다시 그릴 때마다 제목을 이걸로 (크리스탈 수 등)
	color: Color3?,
	hint: string?,
	count: number,
	items: (() -> { Item })?,
	filters: { Filter }?,
	check: ((item: Item, selected: { Item }) -> (boolean, string?))?,
	ready: ((selected: { Item }) -> (boolean, string?))?,
	status: ((selected: { Item }) -> string?)?,
	confirmText: string?,
	empty: string?,
	onConfirm: (selected: { Item }) -> (),
	onCancel: (() -> ())?,
	closeWhen: (() -> boolean)?,
}

------------------------------------------------------------------
-- 기본 항목 / 필터
------------------------------------------------------------------

-- 내 보관함 펫 → Item
function PetPicker.myPets(): { Item }
	local snap = State.get()
	local list: { Item } = {}
	if not snap then
		return list
	end
	local equipped: { [string]: boolean } = {}
	for _, uid in (snap.equipped or {}) :: { string } do
		equipped[uid] = true
	end
	for _, record in (snap.pets or {}) :: { Types.PetRecord } do
		table.insert(list, {
			uid = record.uid,
			petId = record.petId,
			size = record.size,
			mutations = record.mutations or {},
			kind = "pet",
			equipped = equipped[record.uid] == true,
		})
	end
	return list
end

-- 내 부화 중 알 → Item
function PetPicker.myEggs(): { Item }
	local snap = State.get()
	local list: { Item } = {}
	if not snap then
		return list
	end
	for _, record in (snap.incubators or {}) :: { Types.IncubatorRecord } do
		table.insert(list, {
			uid = record.uid,
			petId = record.petId,
			size = record.size,
			mutations = record.mutations or {},
			kind = "egg",
			note = "부화 중 알",
		})
	end
	return list
end

local function speciesCounts(items: { Item }): { [string]: number }
	local counts: { [string]: number } = {}
	for _, item in items do
		counts[item.petId] = (counts[item.petId] or 0) + 1
	end
	return counts
end

-- "같은 펫만": 아직 안 골랐으면 minCount 마리 이상 가진 펫만, 골랐으면 그 펫만
function PetPicker.sameSpecies(minCount: number): Filter
	local counts: { [string]: number } = {}
	local stamp: { Item }? = nil
	return {
		id = "same",
		label = "같은 펫만",
		default = true,
		test = function(item: Item, selected: { Item }): boolean
			if #selected > 0 then
				return item.petId == selected[1].petId
			end
			-- 목록이 바뀔 때만 다시 셈
			local all = PetPicker.currentItems()
			if stamp ~= all then
				stamp = all
				counts = speciesCounts(all)
			end
			return (counts[item.petId] or 0) >= minCount
		end,
	}
end

-- "같은 쪽만": 천국(light)/지옥(dark) 쪽 펫만
function PetPicker.sameSide(side: string): Filter
	return {
		id = "side",
		label = "같은 쪽만",
		default = true,
		test = function(item: Item): boolean
			local pet = Pets.get(item.petId)
			return pet ~= nil and pet.side == side
		end,
	}
end

------------------------------------------------------------------
-- 창
------------------------------------------------------------------

type Session = {
	opts: Options,
	selected: { Item },
	filterOn: { [string]: boolean },
	page: number,
	items: { Item },
	render: () -> (),
	window: Ui.Window,
	alive: boolean,
	unsubscribe: (() -> ())?,
}

local session: Session? = nil
local hooked = false

function PetPicker.currentItems(): { Item }
	local s = session
	return if s then s.items else {}
end

function PetPicker.isOpen(): boolean
	return session ~= nil and Windows.isOpen(NAME)
end

-- 열린 창 다시 그리기 (크리스탈 수처럼 State 밖의 값이 바뀌었을 때)
function PetPicker.refresh()
	local s = session
	if s and s.alive then
		s.render()
	end
end

local function detail(item: Item): string
	local parts: { string } = {}
	local size = Sizes.get(item.size)
	if size and size.id ~= Sizes.DEFAULT then
		table.insert(parts, size.name)
	end
	for _, id in item.mutations do
		local m = Mutations.get(id)
		if m then
			table.insert(parts, m.name)
		end
	end
	return table.concat(parts, " · ")
end

local function rarityOrder(item: Item): number
	local pet = Pets.get(item.petId)
	return if pet then Rarities.order(pet.rarity) else 0
end

local function incomeOf(item: Item): number
	return Economy.petIncome(item.petId, item.size, item.mutations)
end

local function destroy(s: Session, immediate: boolean?)
	if not s.alive then
		return
	end
	s.alive = false
	if session == s then
		session = nil
	end
	local unsubscribe = s.unsubscribe
	if unsubscribe then
		unsubscribe()
	end
	local holder = s.window.holder
	if immediate then
		holder:Destroy()
	else
		task.delay(0.3, function()
			holder:Destroy()
		end)
	end
end

-- 다른 창이 열리거나 닫히면 (ESC·X·취소·확인) 정리. 취소였으면 onCancel
local function hook()
	if hooked then
		return
	end
	hooked = true
	Windows.changed(function(openName: string?)
		local s = session
		if s and openName ~= NAME then
			local onCancel = s.opts.onCancel
			destroy(s)
			if onCancel then
				onCancel()
			end
		end
	end)
end

function PetPicker.close()
	local s = session
	if s then
		Windows.close(NAME)
	end
end

-- 카드 하나
local function makeCard(s: Session, item: Item, order: number, parent: Instance)
	local pet = Pets.get(item.petId)
	local rarityId = if pet then pet.rarity else "common"
	local rcolor = Theme.rarityColor(rarityId)
	local index = 0
	for i, sel in s.selected do
		if sel.uid == item.uid then
			index = i
		end
	end
	local isSelected = index > 0
	local ok, reason = true, nil :: string?
	local check = s.opts.check
	if not isSelected and check then
		ok, reason = check(item, s.selected)
	end
	if not isSelected and #s.selected >= s.opts.count and s.opts.count > 1 then
		ok, reason = false, nil
	end

	local card: TextButton = Ui.new("TextButton", {
		Name = item.uid,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = if isSelected
			then Color3.fromRGB(255, 250, 215)
			elseif ok then C.white
			else Color3.fromRGB(205, 200, 210),
		LayoutOrder = order,
		Parent = parent,
	})
	Ui.corner(16).Parent = card
	local stroke = Ui.stroke(if isSelected then C.yellow else rcolor, if isSelected then 6 else 3)
	stroke.Parent = card

	if item.kind == "egg" then
		local ec = Visuals.petColor(item.petId, 1)
		local egg: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(58, 74),
			BackgroundColor3 = Color3.fromRGB(ec[1], ec[2], ec[3]),
			Parent = card,
		})
		Ui.corner(1).Parent = egg
		Ui.stroke(C.white, 3).Parent = egg
	else
		local view = PetViewport.new(item.petId, { size = UDim2.new(1, -10, 0, 84), position = UDim2.fromOffset(5, 4) })
		view.Parent = card
		if not ok then
			view.ImageTransparency = 0.5
		end
	end
	Ui.label(if pet then pet.name else item.petId, UDim2.new(1, -8, 0, 22), 18, rcolor, {
		Position = UDim2.fromOffset(4, 88),
		TextScaled = true,
		Parent = card,
	})
	local rarity = Rarities.get(rarityId)
	Ui.label(
		(if rarity then rarity.name .. " · " else "") .. Format.money(incomeOf(item)) .. "/초",
		UDim2.new(1, -8, 0, 18),
		15,
		C.money,
		{ Position = UDim2.fromOffset(4, 111), TextScaled = true, Parent = card }
	)
	local extra = detail(item)
	local note = if reason then reason elseif item.note then item.note else extra
	Ui.label(note, UDim2.new(1, -8, 0, 34), 14, if reason then C.red else C.orange, {
		Position = UDim2.fromOffset(4, 131),
		TextScaled = true,
		Parent = card,
	})
	if item.equipped then
		local tag: TextLabel = Ui.new("TextLabel", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(44, 20),
			BackgroundColor3 = C.yellow,
			TextColor3 = C.ink,
			TextSize = 13,
			Text = "장착",
			ZIndex = 3,
			Parent = card,
		})
		Ui.corner(1).Parent = tag
	end
	if isSelected then
		local badge: TextLabel = Ui.new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -10, 0, 10),
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = C.green,
			TextColor3 = C.white,
			TextSize = 22,
			Text = tostring(index),
			ZIndex = 4,
			Parent = card,
		})
		Ui.corner(1).Parent = badge
		Ui.stroke(C.white, 3).Parent = badge
		Ui.textStroke(2).Parent = badge
	end

	card.Activated:Connect(function()
		if not s.alive then
			return
		end
		if isSelected then
			table.remove(s.selected, index)
		elseif ok then
			if s.opts.count == 1 then
				s.selected = { item }
			elseif #s.selected < s.opts.count then
				table.insert(s.selected, item)
			end
		else
			Ui.pop(card, 0.9)
			return
		end
		s.render()
	end)
end

function PetPicker.open(opts: Options)
	hook()
	local old = session
	if old then
		destroy(old, true)
	end
	local color = opts.color or C.purple
	local window = Ui.window(NAME, opts.title, color, BASE, function()
		PetPicker.close()
	end)
	local content = window.content
	local btnH = Ui.touch(64, BASE)
	local barH = btnH + 12

	-- 안내 줄
	local topH = btnH -- 위 줄(안내 + 쪽 넘기기)도 손가락 크기
	local hint = Ui.label(opts.hint or "", UDim2.new(1, -(topH * 2 + 96), 0, topH), 22, C.ink, {
		Name = "Hint",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Parent = content,
	})
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 24
	limit.Parent = hint
	local pageLabel = Ui.label("1/1", UDim2.fromOffset(70, topH), 20, C.ink, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(topH + 6), 0, 0),
		Parent = content,
	})

	local grid = Ui.scroll(UDim2.new(1, 0, 1, -(topH + 6 + barH + 8)), UDim2.fromOffset(0, topH + 6), content)
	Ui.grid(CARD, 10).Parent = grid
	Ui.padding(6).Parent = grid
	local emptyLabel =
		Ui.label(opts.empty or "고를 수 있는 펫이 없어요!", UDim2.new(1, -40, 0, 70), 26, C.ink, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Visible = false,
			Parent = content,
		})

	-- 아래 막대: 필터 · 고른 수 · 취소 · 확인
	local bar: Frame = Ui.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, barH),
		BackgroundColor3 = C.panelDark,
		Parent = content,
	})
	Ui.corner(16).Parent = bar
	local left: Frame = Ui.new("Frame", {
		Name = "Filters",
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(0, 330, 1, 0),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	Ui.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent =
		left
	local countLabel = Ui.label("", UDim2.fromOffset(150, barH), 24, C.ink, {
		Name = "Count",
		Position = UDim2.fromOffset(340, 0),
		Parent = bar,
	})

	local s: Session
	local confirm: TextButton
	local filterButtons: { [string]: TextButton } = {}

	local cancel = Ui.button("취소", C.gray, UDim2.fromOffset(140, btnH), function()
		PetPicker.close()
	end, {
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -224, 0.5, 0),
		textSize = 26,
		parent = bar,
		sound = "Close",
	})
	cancel.Name = "Cancel"
	confirm = Ui.button(opts.confirmText or "확인", C.green, UDim2.fromOffset(206, btnH), function()
		if not s.alive then
			return
		end
		local readyFn = opts.ready
		local okReady = #s.selected == opts.count
		if okReady and readyFn then
			okReady = readyFn(s.selected)
		end
		if not okReady then
			Ui.pop(confirm, 0.9)
			return
		end
		local chosen = table.clone(s.selected)
		s.opts.onCancel = nil -- 확인으로 닫힘
		PetPicker.close()
		opts.onConfirm(chosen)
	end, {
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -8, 0.5, 0),
		textSize = 26,
		parent = bar,
	})
	confirm.Name = "Confirm"

	s = {
		opts = opts,
		selected = {},
		filterOn = {},
		page = 1,
		items = {},
		render = function() end,
		window = window,
		alive = true,
	}
	for _, filter in (opts.filters or {}) :: { Filter } do
		s.filterOn[filter.id] = filter.default ~= false
	end

	local function refreshItems()
		local source = opts.items
		s.items = if source then source() else PetPicker.myPets()
		-- 없어진 항목은 선택에서 빼기
		local byUid: { [string]: Item } = {}
		for _, item in s.items do
			byUid[item.uid] = item
		end
		for i = #s.selected, 1, -1 do
			if not byUid[s.selected[i].uid] then
				table.remove(s.selected, i)
			end
		end
	end

	local function render()
		if not s.alive then
			return
		end
		for _, child in grid:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		-- 필터
		local visible: { Item } = {}
		for _, item in s.items do
			local show = true
			for _, filter in (opts.filters or {}) :: { Filter } do
				if s.filterOn[filter.id] and not filter.test(item, s.selected) then
					show = false
					break
				end
			end
			local selectedNow = false
			for _, sel in s.selected do
				if sel.uid == item.uid then
					selectedNow = true
				end
			end
			if show or selectedNow then
				table.insert(visible, item)
			end
		end
		-- 고를 수 있는 것 먼저 → 희귀도 높은 순 → 같은 펫끼리 → 수입 높은 순
		local okCache: { [string]: boolean } = {}
		local check = opts.check
		for _, item in visible do
			okCache[item.uid] = if check then (check(item, {})) else true
		end
		table.sort(visible, function(a: Item, b: Item): boolean
			local oa, ob = okCache[a.uid] == true, okCache[b.uid] == true
			if oa ~= ob then
				return oa
			end
			local ra, rb = rarityOrder(a), rarityOrder(b)
			if ra ~= rb then
				return ra > rb
			end
			if a.petId ~= b.petId then
				return a.petId < b.petId
			end
			local ia, ib = incomeOf(a), incomeOf(b)
			if ia ~= ib then
				return ia > ib
			end
			return a.uid < b.uid
		end)
		local pages = math.max(1, math.ceil(#visible / PAGE))
		s.page = math.clamp(s.page, 1, pages)
		pageLabel.Text = string.format("%d/%d", s.page, pages)
		for i = (s.page - 1) * PAGE + 1, math.min(#visible, s.page * PAGE) do
			makeCard(s, visible[i], i, grid)
		end
		emptyLabel.Visible = #visible == 0

		local liveTitle = opts.liveTitle
		if liveTitle then
			window.title.Text = liveTitle()
		end
		-- 아래 막대
		countLabel.Text = string.format("고름 %d/%d", #s.selected, opts.count)
		for id, button in filterButtons do
			local on = s.filterOn[id] == true
			Ui.setButton(button, nil, if on then C.blue else C.gray)
		end
		local okReady, why = #s.selected == opts.count, nil :: string?
		local readyFn = opts.ready
		if okReady and readyFn then
			okReady, why = readyFn(s.selected)
		end
		Ui.setButton(confirm, nil, if okReady then C.green else C.gray, okReady)
		local statusFn = opts.status
		local statusText = if statusFn then statusFn(s.selected) else nil
		hint.Text = why or statusText or opts.hint or ""
		hint.TextColor3 = if why then C.red else C.ink
	end
	s.render = render

	for i, filter in (opts.filters or {}) :: { Filter } do
		local id = filter.id
		local b = Ui.button(filter.label, C.blue, UDim2.fromOffset(156, btnH), function()
			s.filterOn[id] = not s.filterOn[id]
			s.page = 1
			render()
		end, { layoutOrder = i, parent = left, textSize = 22 })
		b.Name = "Filter_" .. id
		filterButtons[id] = b
	end
	-- 쪽 넘기기 (안내 줄 오른쪽)
	local prev = Ui.button("<", C.blue, UDim2.fromOffset(topH, topH), function()
		s.page -= 1
		render()
	end, { anchor = Vector2.new(1, 0), position = UDim2.new(1, -(topH + 82), 0, 0), textSize = 26, parent = content })
	prev.Name = "Prev"
	local nxt = Ui.button(">", C.blue, UDim2.fromOffset(topH, topH), function()
		s.page += 1
		render()
	end, { anchor = Vector2.new(1, 0), position = UDim2.fromScale(1, 0), textSize = 26, parent = content })
	nxt.Name = "Next"

	session = s
	refreshItems()
	Windows.register(NAME, window, render)

	s.unsubscribe = State.onChanged(function(section: string)
		if s.alive and (section == "pets" or section == "incubators" or section == "snapshot") then
			refreshItems()
			render()
		end
	end)
	-- 멀어지면 닫기
	local closeWhen = opts.closeWhen
	if closeWhen then
		task.spawn(function()
			while s.alive do
				task.wait(0.5)
				if s.alive and closeWhen() then
					PetPicker.close()
				end
			end
		end)
	end
	Windows.open(NAME)
end

return PetPicker
