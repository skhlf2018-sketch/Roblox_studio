--!strict
--[[
	IncubatorController — 씨앗 창 (오른쪽 빨간 씨앗 버튼) + 정원에 씨앗 심기 + 자라는 씨앗 프롬프트 (6판)

	씨앗 창 = "자라는 씨앗" 패널 + 탭 2개
	  - "자라는 중" 탭: 정원에 심은 씨앗(snap.incubators) 줄마다 씨앗 그림 + 식물 이름 · 단계(GardenRules.stageName 새싹/줄기/봉오리)
	    + 초록 진행 막대 + 남은 시간 "5m 25s" (다 자라면 "곧 성체!" — 서버가 저절로 성체로 바꿈, PlantGrown)
	    + 가방 버튼(PickUpPlacedEgg) + ⏩ 건너뛰기 버튼 → 건너뛰기 창 (openSkip)
	  - "가방" 탭: 씨앗 가방(snap.eggs) 카드 — 등급 색 테두리, 씨앗 그림, 식물 이름, 등급·크기·돌연변이, "심기" 버튼
	  - 탭 글자의 정원 칸 = 자라는 씨앗 + 성체 / penSlots (6판 정원 칸 수)
	  - "모두 성장시키기" (로벅스) 는 어른 확인 전이라 꺼 둠.
	  - 씨앗 버튼 배지 = 가방 속 씨앗 수 (할 일 수)

	건너뛰기 창 (openSkip(uid), Ui.dialog "SkipDialog"): "전부 · N 코인" (SkipAll) / "절반 · N 코인" (SkipHalf) / 취소.
	  가격 = GardenRules.skipCost(petId, progress, required, mode) — 남은 시간이 1초마다 줄어서 가격도 1초마다 다시 계산.
	  코인이 모자라면 회색 (누르면 안내만). 누르면 SkipGrowth(uid, "all"|"half") — 결과(성체·코인)는 서버가 알려 줌.

	씨앗 심기 모드 (아래 핫바의 씨앗 칸을 누르면 바로 — HotbarController. 가방 탭 카드 "심기" 도 그대로):
	  - 내 정원 바닥에 반투명 씨앗 미리보기 + 바닥 동그라미. 초록 = 심을 수 있음 / 빨강 = 안 됨 (위 안내 줄에 이유)
	    판정 = EggPlacement.check(MapLayout.toLocal(내 베이스, 자리), 자라는 씨앗 + 성체 자리) + 정원 칸 수 + 서 있는 곳(서버와 같은 규칙)
	  - PC: 마우스를 따라 미리보기, 왼쪽 클릭 → PlaceEgg(uid, x, z) (월드 x, z)
	  - 폰: 바닥을 톡 누른 곳으로 미리보기 (처음엔 정원 안 첫 빈자리), "여기 심기" 버튼 → PlaceEgg
	  - ESC / "취소" 버튼으로 끝. 그 씨앗이 가방에서 사라지면(심기 성공 등) 저절로 끝.
	  공개: beginPlace(uid) / previewAt(x, z) / confirmPlace() / cancelPlace() / isPlacing() / placingUid() / onPlaceChanged(fn)
	        / openSkip(uid) (핫바·튜토리얼·정원 프롬프트·테스트도 씀)

	월드: 내 자라는 씨앗(태그 IncubatingEgg)에 프롬프트 — "집기"(E, PickUpPlacedEgg · Config.ALLOW_EGG_PICKUP)
	  · "건너뛰기"(R, 건너뛰기 창). 머리 위 이름표는 서버(BaseService) 것.
	진행값: 씨앗 파트 Attribute Progress/Required(서버가 1초마다 갱신) 우선, 없으면 Snapshot incubators.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local GardenRules = require(Shared.GardenRules)
local EggPlacement = require(Shared.EggPlacement)
local MapLayout = require(Shared.Data.MapLayout)
local Mutations = require(Shared.Data.Mutations)
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Sizes = require(Shared.Data.Sizes)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Ui = require(Client.UI.Ui)
local HudController = require(script.Parent.HudController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)

local IncubatorController = {}
IncubatorController.toggle = nil :: (() -> ())?
IncubatorController.panel = nil :: Frame?
IncubatorController.setTab = nil :: ((string) -> ())?

local C = Theme.Colors
local Attr = Tags.PlayerAttributes

type Row = {
	frame: Frame,
	nameLabel: TextLabel,
	timeLabel: TextLabel,
	bar: Frame,
	skip: TextButton,
	pickUp: TextButton,
	ready: boolean,
}

-- 원작 "1m 52s" / "5m" / "45s"
local function shortTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local m = math.floor(s / 60)
	if m >= 60 then
		return string.format("%dh %dm", math.floor(m / 60), m % 60)
	elseif m > 0 then
		return if s % 60 == 0 then string.format("%dm", m) else string.format("%dm %ds", m, s % 60)
	end
	return string.format("%ds", s)
end
IncubatorController.shortTime = shortTime

local function petName(petId: string): string
	local pet = Pets.get(petId)
	return if pet then pet.name else petId
end

local function rarityOf(petId: string): string
	local pet = Pets.get(petId)
	return if pet then pet.rarity else "common"
end

-- "전설 · 큼 · 골든" (보통 크기는 안 씀)
local function eggDetail(record: any): string
	local parts: { string } = {}
	local rarity = Rarities.get(rarityOf(tostring(record.petId)))
	if rarity then
		table.insert(parts, rarity.displayName)
	end
	local size = Sizes.get(tostring(record.size))
	if size and size.id ~= "normal" then
		table.insert(parts, size.name)
	end
	if typeof(record.mutations) == "table" then
		for _, id in record.mutations do
			local m = Mutations.get(tostring(id))
			if m then
				table.insert(parts, m.name)
			end
		end
	end
	return table.concat(parts, " · ")
end

-- 씨앗 그림 (등급 색으로 칠함)
local function eggIcon(parent: GuiObject, petId: string, size: number, position: UDim2?): Frame
	local icon = Icons.draw("seed", parent, size, position)
	local color = Theme.lighter(Theme.rarityColor(rarityOf(petId)), 0.1)
	for _, d in icon:GetDescendants() do
		if d:IsA("Frame") and d.BackgroundTransparency < 0.5 then
			d.BackgroundColor3 = color
			break
		end
	end
	return icon
end

local function findPart(uid: string): BasePart?
	local me = Players.LocalPlayer.UserId
	for _, inst in CollectionService:GetTagged(Tags.IncubatingEgg) do
		if inst:IsA("BasePart") and inst:GetAttribute("EggUid") == uid and inst:GetAttribute("OwnerUserId") == me then
			return inst
		end
	end
	return nil
end

local function partProgress(part: BasePart, fallbackP: number, fallbackR: number): (number, number)
	local p = part:GetAttribute("Progress")
	local r = part:GetAttribute("Required")
	return if typeof(p) == "number" then p else fallbackP, if typeof(r) == "number" then r else fallbackR
end

local function snapIncubators(): { Types.IncubatorRecord }
	local snap = State.get()
	return if snap then snap.incubators or {} else {}
end

local function snapEggs(): { Types.BagEgg }
	local snap = State.get()
	return if snap then snap.eggs or {} else {}
end

local function snapPlants(): { Types.PetRecord }
	local snap = State.get()
	return if snap then snap.pets or {} else {}
end

-- 6판: 정원 칸 수 (자라는 씨앗 + 성체 합의 상한)
local function gardenSlots(): number
	local snap = State.get()
	local slots = if snap then snap.penSlots else nil
	if typeof(slots) == "number" then
		return slots
	end
	local attr = Players.LocalPlayer:GetAttribute(Attr.PenSlots)
	return if typeof(attr) == "number" then attr else Economy.penSlots(0)
end

local function gardenUsed(): number
	return #snapIncubators() + #snapPlants()
end
IncubatorController.gardenSlots = gardenSlots
IncubatorController.gardenUsed = gardenUsed

local function myMoney(): number
	local m = Players.LocalPlayer:GetAttribute(Attr.Money)
	return if typeof(m) == "number" then m else 0
end

local function bagMax(): number
	local snap = State.get()
	local n = if snap then snap.eggInventoryMax else nil
	return if typeof(n) == "number" then n else Config.EGG_INVENTORY_MAX
end

local function myPlot(): number
	local index = Players.LocalPlayer:GetAttribute(Attr.PlotIndex)
	if typeof(index) == "number" and index > 0 then
		return index
	end
	local snap = State.get()
	local fromSnap = if snap then snap.plotIndex else 0
	return if typeof(fromSnap) == "number" then fromSnap else 0
end

local function myRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

------------------------------------------------------------------
-- 건너뛰기 창 (전부 / 절반, 가격은 1초마다 다시 계산)
------------------------------------------------------------------

type SkipQuote = { petId: string, progress: number, required: number }

-- 지금 진행도 (씨앗 파트 Attribute 우선, 없으면 State)
local function quoteOf(uid: string): SkipQuote?
	for _, record in snapIncubators() do
		if tostring(record.uid) == uid then
			local progress = tonumber(record.progress) or 0
			local required = tonumber(record.required) or 1
			local part = findPart(uid)
			if part then
				progress, required = partProgress(part, progress, required)
			end
			return { petId = tostring(record.petId), progress = progress, required = required }
		end
	end
	return nil
end

-- 건너뛰기 값 (코인). 다 자랐거나 모르는 씨앗이면 nil
function IncubatorController.skipCost(uid: string, mode: GardenRules.SkipMode): number?
	local q = quoteOf(uid)
	if not q or q.progress >= q.required then
		return nil
	end
	return GardenRules.skipCost(q.petId, q.progress, q.required, mode)
end

local skipDialog: Ui.Dialog? = nil

local function skipBody(uid: string): string
	local q = quoteOf(uid)
	if not q then
		return "이 씨앗은 이제 정원에 없어요."
	end
	if q.progress >= q.required then
		return petName(q.petId) .. " 씨앗이 다 자랐어요! 곧 성체가 돼요."
	end
	return string.format(
		"%s 씨앗 · %s\n남은 시간 %s (밤에는 30배 빨리 자라요)\n내 코인 %s",
		petName(q.petId),
		GardenRules.stageName(GardenRules.stage(q.progress, q.required)),
		shortTime(Economy.timerSeconds(q.progress, q.required)),
		Format.money(myMoney())
	)
end

local function refreshSkipDialog(uid: string)
	local dialog = skipDialog
	if not dialog or not dialog.alive() then
		return
	end
	dialog.setBody(skipBody(uid))
	local SKIP_BUTTONS: { [string]: string } = { all = "SkipAll", half = "SkipHalf" }
	for mode, name in SKIP_BUTTONS do
		local button = dialog.buttons[name]
		if button then
			local cost = IncubatorController.skipCost(uid, mode :: GardenRules.SkipMode)
			local label = if mode == "all" then "전부" else "절반"
			local afford = cost ~= nil and myMoney() >= cost
			Ui.setButton(
				button,
				if cost then label .. " · " .. Format.money(cost) else label,
				if afford then (if mode == "all" then C.shopGreen else C.blue) else C.gray,
				afford
			)
		end
	end
end

-- 건너뛰기 창 열기. 열었으면 true
function IncubatorController.openSkip(uid: string): boolean
	if not quoteOf(uid) then
		return false
	end
	local function choose(mode: GardenRules.SkipMode)
		local cost = IncubatorController.skipCost(uid, mode)
		if not cost then
			NotifyController.toast("다 자랐어요! 곧 성체가 돼요", "info")
			return
		end
		if myMoney() < cost then
			NotifyController.toast(
				"코인이 모자라요! (" .. Format.money(cost) .. " 필요) 열매를 따서 팔아 보세요",
				"error"
			)
			return
		end
		Net.send(Remotes.ToServer.SkipGrowth, uid, mode)
	end
	local dialog = Ui.dialog("SkipDialog", "⏩ 성장 건너뛰기", skipBody(uid), {
		{
			name = "SkipAll",
			text = "전부",
			color = C.shopGreen,
			sound = "Purchase",
			onClick = function()
				choose("all")
			end,
		},
		{
			name = "SkipHalf",
			text = "절반",
			color = C.blue,
			sound = "Purchase",
			onClick = function()
				choose("half")
			end,
		},
		{ name = "DialogCancel", text = "취소", color = C.gray, sound = "Close" },
	}, Color3.fromRGB(230, 150, 60))
	skipDialog = dialog
	refreshSkipDialog(uid)
	task.spawn(function()
		while dialog.alive() do
			task.wait(1)
			if not dialog.alive() then
				break
			end
			if not quoteOf(uid) then
				dialog.close() -- 성체가 됐거나 다시 주움
				break
			end
			refreshSkipDialog(uid)
		end
	end)
	return true
end

------------------------------------------------------------------
-- 월드: 내 자라는 씨앗 프롬프트 ("집기" E / "건너뛰기" R)
------------------------------------------------------------------

type EggPrompts = { skip: ProximityPrompt, pickUp: ProximityPrompt }
local eggPrompts: { [BasePart]: EggPrompts } = {}

local function makePrompt(
	part: BasePart,
	name: string,
	action: string,
	hold: number,
	key: Enum.KeyCode,
	onTrigger: (string) -> ()
)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = petName(tostring(part:GetAttribute("PetId") or "")) .. " 씨앗"
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Triggered:Connect(function()
		local uid = part:GetAttribute("EggUid")
		if typeof(uid) == "string" then
			onTrigger(uid)
		end
	end)
	prompt.Parent = part
	return prompt
end

local function decorate(inst: Instance)
	if not inst:IsA("BasePart") or eggPrompts[inst] then
		return
	end
	local part = inst
	if part:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
		return -- 남의 씨앗은 이름표(서버)만
	end
	-- 6판: 다 자라면 서버가 그 자리에서 성체로 바꿈 (부화 버튼 없음) → 아직 자랄 때 "건너뛰기" 창
	local skip = makePrompt(part, "SkipPrompt", "건너뛰기", 0, Enum.KeyCode.R, function(uid)
		IncubatorController.openSkip(uid)
	end)
	local pickUp = makePrompt(part, "PickUpPrompt", "집기", 0.4, Enum.KeyCode.E, function(uid)
		Net.send(Remotes.ToServer.PickUpPlacedEgg, uid)
	end)
	eggPrompts[part] = { skip = skip, pickUp = pickUp }
end

local function refreshPrompts()
	for part, prompts in eggPrompts do
		if part.Parent == nil then
			eggPrompts[part] = nil
		else
			local progress, required = partProgress(part, 0, 1)
			local ready = part:GetAttribute("Ready") == true or progress >= required
			prompts.skip.Enabled = not ready
			prompts.pickUp.Enabled = not ready and Config.ALLOW_EGG_PICKUP
		end
	end
end

------------------------------------------------------------------
-- 씨앗 심기 모드
------------------------------------------------------------------

type Placing = {
	uid: string,
	size: string,
	ghost: BasePart,
	ring: BasePart,
	point: Vector3?,
	ok: boolean,
	reason: string?,
}
local placing: Placing? = nil
local placeBar: Frame? = nil
local placeHint: TextLabel? = nil
local placeHere: TextButton? = nil

local GREEN = Color3.fromRGB(80, 235, 90)
local RED = Color3.fromRGB(240, 60, 60)

-- 정원 자리 = 자라는 씨앗 + 성체 식물 (6판 서버도 둘 다 placed 로 넘김)
local function placedSpots(): { EggPlacement.Spot }
	local spots: { EggPlacement.Spot } = {}
	for _, record in snapIncubators() do
		local x, z = tonumber(record.x), tonumber(record.z)
		if x and z then
			table.insert(spots, { x = x, z = z, size = record.size })
		end
	end
	for _, record in snapPlants() do
		local x, z = tonumber(record.x), tonumber(record.z)
		if x and z then
			table.insert(spots, { x = x, z = z, size = record.size })
		end
	end
	return spots
end

-- (x, z)(월드)에 지금 씨앗을 심을 수 있나 — 서버 PlaceEgg 와 같은 순서로 검사. 안 되면 안내 글
local function canPlaceAt(sizeId: string, x: number, z: number): (boolean, string?)
	local plotIndex = myPlot()
	if plotIndex == 0 then
		return false, "아직 내 베이스가 없어요! 베이스를 받으면 씨앗을 심을 수 있어요."
	end
	if gardenUsed() >= gardenSlots() then
		return false, EggPlacement.message("full")
	end
	local l = MapLayout.toLocal(plotIndex, { x = x, z = z })
	if not l then
		return false, EggPlacement.message("outside")
	end
	local ok, reason = EggPlacement.check(EggPlacement.round(l.x), EggPlacement.round(l.z), sizeId, placedSpots(), {})
	if not ok then
		return false, EggPlacement.message(reason)
	end
	local root = myRoot()
	if root then
		local dx, dz = root.Position.X - x, root.Position.Z - z
		local near = math.sqrt(dx * dx + dz * dz) <= Config.EGG_PLACE_RADIUS
		if not near and not MapLayout.isInPlot(root.Position, plotIndex) then
			return false, "내 정원 가까이에서 심어 주세요!"
		end
	end
	return true, nil
end

local function previewPart(name: string, shape: Enum.PartType, size: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 0.45
	p.Color = GREEN
	return p
end

local function makeGhost(sizeId: string): (BasePart, BasePart)
	local d = EggPlacement.diameter(sizeId)
	local ghost = previewPart("EggPlacePreview", Enum.PartType.Ball, Vector3.new(d, d, d))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.25, 1)
	mesh.Parent = ghost
	-- 바닥 동그라미 = 같은 크기 씨앗끼리 띄워야 하는 거리
	local gap = EggPlacement.gap(sizeId, sizeId)
	local ring = previewPart("EggPlaceRing", Enum.PartType.Cylinder, Vector3.new(0.15, gap, gap))
	ring.Transparency = 0.6
	ring.Parent = ghost
	ghost.Parent = Workspace
	return ghost, ring
end

local function touchMode(): boolean
	return Ui.isTouch()
end

local function setHint(text: string, color: Color3)
	local hint = placeHint
	if hint then
		hint.Text = text
		hint.TextColor3 = color
	end
end

local function refreshPlaceUi()
	local state = placing
	local bar = placeBar
	if bar then
		bar.Visible = state ~= nil
	end
	local here = placeHere
	if here then
		here.Visible = state ~= nil and touchMode()
		Ui.setButton(here, nil, nil, state ~= nil and state.ok)
	end
	if not state then
		return
	end
	if not state.point then
		setHint(
			if touchMode()
				then "정원 바닥을 톡 눌러서 씨앗 심을 자리를 골라요"
				else "정원 바닥에 마우스를 올려 씨앗 심을 자리를 골라요",
			C.white
		)
	elseif state.ok then
		setHint(
			if touchMode()
				then "여기 심을 수 있어요! '여기 심기'를 눌러요"
				else "여기 심을 수 있어요! 클릭해서 심기",
			GREEN
		)
	else
		setHint(state.reason or "여기에는 씨앗을 심을 수 없어요.", Color3.fromRGB(255, 120, 120))
	end
end

-- 미리보기를 (x, z)(월드)로 옮기고 심을 수 있는지 돌려줌
function IncubatorController.previewAt(x: number, z: number): (boolean, string?)
	local state = placing
	if not state then
		return false, nil
	end
	local ok, reason = canPlaceAt(state.size, x, z)
	local d = EggPlacement.diameter(state.size)
	local floorY = MapLayout.FLOOR_Y
	state.point = Vector3.new(x, floorY, z)
	state.ok = ok
	state.reason = reason
	local color = if ok then GREEN else RED
	state.ghost.CFrame = CFrame.new(x, floorY + d * 1.25 / 2, z)
	state.ghost.Color = color
	state.ghost.Transparency = 0.45
	state.ring.CFrame = CFrame.new(x, floorY + 0.08, z) * CFrame.Angles(0, 0, math.rad(90))
	state.ring.Color = color
	refreshPlaceUi()
	return ok, reason
end

-- 심기 모드가 시작·끝·다른 씨앗으로 바뀔 때 (핫바가 고른 씨앗 칸을 강조)
local placeListeners: { () -> () } = {}
local function emitPlace()
	for _, fn in placeListeners do
		task.spawn(fn)
	end
end

function IncubatorController.onPlaceChanged(fn: () -> ())
	table.insert(placeListeners, fn)
end

function IncubatorController.cancelPlace()
	local state = placing
	placing = nil
	if state then
		state.ghost:Destroy()
	end
	refreshPlaceUi()
	if state then
		emitPlace()
	end
end

function IncubatorController.isPlacing(): boolean
	return placing ~= nil
end

-- 지금 심으려는 가방 씨앗 uid (심기 모드가 아니면 nil)
function IncubatorController.placingUid(): string?
	local state = placing
	return if state then state.uid else nil
end

-- 지금 미리보기 자리에 심기 (PlaceEgg). 보냈으면 true
function IncubatorController.confirmPlace(): boolean
	local state = placing
	if not state then
		return false
	end
	local point = state.point
	if not point then
		setHint("먼저 정원 바닥에서 자리를 골라요!", C.yellow)
		return false
	end
	-- 그 사이 정원이 바뀌었을 수도 있으니 한 번 더
	local ok = IncubatorController.previewAt(point.X, point.Z)
	if not ok then
		local bar = placeBar
		if bar then
			Ui.pop(bar, 1.08)
		end
		SoundController.play("Error")
		return false
	end
	Net.send(Remotes.ToServer.PlaceEgg, state.uid, point.X, point.Z)
	IncubatorController.cancelPlace()
	return true
end

-- 가방 씨앗 uid 로 심기 모드 시작. 시작했으면 true
function IncubatorController.beginPlace(uid: string): boolean
	local egg: Types.BagEgg? = nil
	for _, e in snapEggs() do
		if e.uid == uid then
			egg = e
			break
		end
	end
	if not egg then
		return false
	end
	if myPlot() == 0 then
		NotifyController.toast(
			"아직 내 베이스가 없어요! 베이스를 받으면 씨앗을 심을 수 있어요",
			"error"
		)
		return false
	end
	if gardenUsed() >= gardenSlots() then
		NotifyController.toast(EggPlacement.message("full"), "error")
		return false
	end
	IncubatorController.cancelPlace()
	local ghost, ring = makeGhost(egg.size)
	placing = { uid = uid, size = egg.size, ghost = ghost, ring = ring, point = nil, ok = false, reason = nil }
	ghost.Transparency = 1
	ring.Transparency = 1
	-- 폰: 처음엔 정원 안 첫 빈자리에 미리보기 (바로 "여기 심기" 가능)
	local plotIndex = myPlot()
	local spot = EggPlacement.firstFreeGrid(egg.size, placedSpots())
	local world = if spot then MapLayout.toWorld(plotIndex, spot.x, spot.z) else nil
	if world and touchMode() then
		IncubatorController.previewAt(world.x, world.z)
		ring.Transparency = 0.6
	end
	local panel = IncubatorController.panel
	if panel then
		panel.Visible = false
	end
	refreshPlaceUi()
	local bar = placeBar
	if bar then
		Ui.pop(bar, 1.15)
	end
	emitPlace()
	return true
end

-- 화면 점 → 바닥(y = FLOOR_Y) 위 점
local function floorPoint(ray: Ray): Vector3?
	local dy = ray.Direction.Y
	if dy > -1e-3 then
		return nil
	end
	local t = (MapLayout.FLOOR_Y - ray.Origin.Y) / dy
	if t < 0 or t > 1500 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

local function previewRay(ray: Ray)
	local state = placing
	local p = floorPoint(ray)
	if state and p then
		state.ring.Transparency = 0.6
		IncubatorController.previewAt(p.X, p.Z)
	end
end

local function buildPlaceBar()
	local bar: Frame = Ui.new("Frame", {
		Name = "PlaceBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(520, 1),
		BackgroundColor3 = C.win,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = Ui.layer("Panels"),
	})
	Ui.scaled(bar)
	Ui.corner(10).Parent = bar
	Ui.stroke(C.winEdge, 4).Parent = bar
	local btnH = Ui.touch(44)
	bar.Size = UDim2.fromOffset(520, 44 + btnH + 18)
	local hint = Ui.label("", UDim2.new(1, -16, 0, 40), 20, C.white, {
		Name = "PlaceHint",
		Position = UDim2.fromOffset(8, 6),
		TextScaled = true,
		Parent = bar,
	})
	local here = Ui.button("여기 심기", C.shopGreen, UDim2.fromOffset(200, btnH), function()
		IncubatorController.confirmPlace()
	end, {
		anchor = Vector2.new(1, 1),
		position = UDim2.new(0.5, -6, 1, -8),
		textSize = 24,
		parent = bar,
	})
	here.Name = "PlaceHere"
	local cancel = Ui.button("취소", C.eggRed, UDim2.fromOffset(140, btnH), function()
		IncubatorController.cancelPlace()
	end, {
		anchor = Vector2.new(0, 1),
		position = UDim2.new(0.5, 6, 1, -8),
		textSize = 24,
		sound = "Close",
		parent = bar,
	})
	cancel.Name = "PlaceCancel"
	placeBar = bar
	placeHint = hint
	placeHere = here
	-- PC 는 "여기 심기" 가 없으니 취소를 가운데로
	Ui.onLayout(function()
		local touch = touchMode()
		here.Visible = placing ~= nil and touch
		cancel.AnchorPoint = if touch then Vector2.new(0, 1) else Vector2.new(0.5, 1)
		cancel.Position = if touch then UDim2.new(0.5, 6, 1, -8) else UDim2.new(0.5, 0, 1, -8)
	end)
	local touch = touchMode()
	cancel.AnchorPoint = if touch then Vector2.new(0, 1) else Vector2.new(0.5, 1)
	cancel.Position = if touch then UDim2.new(0.5, 6, 1, -8) else UDim2.new(0.5, 0, 1, -8)
end

local function hookPlaceInput()
	-- PC: 마우스를 따라 미리보기
	RunService.RenderStepped:Connect(function()
		if not placing or touchMode() then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local mouse = UserInputService:GetMouseLocation()
		previewRay(camera:ViewportPointToRay(mouse.X, mouse.Y))
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not placing then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			IncubatorController.cancelPlace()
			return
		end
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not touchMode() then
			IncubatorController.confirmPlace()
		end
	end)
	-- 폰: 바닥을 톡 누른 자리 (끌어서 카메라 돌리기는 안 셈)
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
		if not placing or processedByUI then
			return
		end
		local camera = Workspace.CurrentCamera
		if camera then
			previewRay(camera:ScreenPointToRay(position.X, position.Y))
		end
	end)
end

------------------------------------------------------------------
-- 패널
------------------------------------------------------------------

local PANEL_W = 400
local GRID_COLS = 3

function IncubatorController.start()
	local panel: Frame = Ui.new("Frame", {
		Name = "GrowingEggs",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -104, 0.5, 0),
		Size = UDim2.fromOffset(PANEL_W, 240),
		BackgroundColor3 = C.win,
		Visible = false,
		Parent = Ui.layer("Panels"),
	})
	Ui.scaled(panel)
	Ui.corner(10).Parent = panel
	Ui.stroke(C.winEdge, 4).Parent = panel

	local header: Frame = Ui.new("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, 48),
		BackgroundColor3 = Color3.fromRGB(230, 150, 60),
		Parent = panel,
	})
	Ui.corner(6).Parent = header
	Ui.gradient(Color3.fromRGB(150, 95, 60), Color3.fromRGB(240, 170, 80), 0).Parent = header
	Ui.label("자라는 씨앗", UDim2.new(1, -170, 1, 0), 26, C.white, {
		Name = "Title",
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	local growAll = Ui.button(
		"모두 성장시키기",
		Color3.fromRGB(240, 190, 40),
		UDim2.fromOffset(150, 34),
		function()
			NotifyController.toast("로벅스 상품은 준비 중이에요!", "info")
		end,
		{
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -8, 0.5, 0),
			textSize = 16,
			textColor = Color3.fromRGB(70, 40, 0),
			parent = header,
		}
	)
	growAll.Name = "GrowAll"
	Ui.setButton(growAll, nil, nil, false)

	-- 탭: 자라는 중 / 가방
	local playH = Ui.touch(44)
	local tabH = playH
	local tabTop = 58
	local contentTop = tabTop + tabH + 6
	local currentTab = "grow"
	local tabGrow = Ui.button("자라는 중", C.shopGreen, UDim2.new(0.5, -9, 0, tabH), nil, {
		position = UDim2.fromOffset(6, tabTop),
		textSize = 20,
		parent = panel,
	})
	tabGrow.Name = "Tab_grow"
	local tabBag = Ui.button("가방", C.pawOrange, UDim2.new(0.5, -9, 0, tabH), nil, {
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -6, 0, tabTop),
		textSize = 20,
		parent = panel,
	})
	tabBag.Name = "Tab_bag"

	local list: ScrollingFrame =
		Ui.scroll(UDim2.new(1, -12, 1, -(contentTop + 6)), UDim2.fromOffset(6, contentTop), panel)
	list.Name = "List"
	Ui.list(Enum.FillDirection.Vertical, 6).Parent = list

	local cardW = math.floor((PANEL_W - 12 - 10 - (GRID_COLS - 1) * 6) / GRID_COLS)
	local cardH = 128 + playH
	local bag: ScrollingFrame =
		Ui.scroll(UDim2.new(1, -12, 1, -(contentTop + 6)), UDim2.fromOffset(6, contentTop), panel)
	bag.Name = "Bag"
	bag.Visible = false
	Ui.grid(Vector2.new(cardW, cardH), 6).Parent = bag

	local emptyGrow = Ui.label(
		"정원에 심은 씨앗이 없어요!\n아래 핫바의 씨앗 칸을 눌러 정원에 심어요",
		UDim2.new(1, -20, 0, 80),
		20,
		C.white,
		{ Name = "EmptyGrow", Position = UDim2.fromOffset(10, contentTop + 8), Parent = panel }
	)
	local emptyBag = Ui.label(
		"가방이 비었어요!\n씨앗을 들고 안전 구역으로 들어오면 가방에 들어가요",
		UDim2.new(1, -20, 0, 80),
		20,
		C.white,
		{ Name = "EmptyBag", Position = UDim2.fromOffset(10, contentTop + 8), Visible = false, Parent = panel }
	)

	local rows: { [string]: Row } = {}
	local rowH = math.max(64, playH + 14)

	local function makeRow(record: Types.IncubatorRecord, order: number): Row
		local f: Frame = Ui.new("Frame", {
			Name = tostring(record.uid),
			Size = UDim2.new(1, -6, 0, rowH),
			BackgroundColor3 = Color3.fromRGB(62, 64, 78),
			LayoutOrder = order,
			Parent = list,
		})
		Ui.corner(6).Parent = f
		Ui.stroke(Theme.rarityColor(rarityOf(record.petId)), 2).Parent = f
		local eggBox: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(56, 52),
			BackgroundColor3 = Color3.fromRGB(90, 92, 108),
			Parent = f,
		})
		Ui.corner(4).Parent = eggBox
		eggIcon(eggBox, record.petId, 44)
		local right = 2 * playH + 18
		local nameLabel = Ui.label(
			petName(record.petId),
			UDim2.new(1, -(70 + right), 0, 22),
			18,
			Theme.rarityColor(rarityOf(record.petId)),
			{
				Name = "EggName",
				Position = UDim2.fromOffset(70, 4),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = f,
			}
		)
		local barBack: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 70, 1, -6),
			Size = UDim2.new(1, -(70 + right), 0, math.max(26, rowH - 36)),
			BackgroundColor3 = Color3.fromRGB(28, 30, 38),
			Parent = f,
		})
		Ui.corner(4).Parent = barBack
		local bar: Frame = Ui.new("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.shopGreen,
			Parent = barBack,
		})
		Ui.corner(4).Parent = bar
		local timeLabel = Ui.label("", UDim2.fromScale(1, 1), 20, C.white, {
			Name = "Time",
			ZIndex = 3,
			TextScaled = true,
			Parent = barBack,
		})
		local uid = tostring(record.uid)
		local pickUp = Ui.button("가방", C.pawOrange, UDim2.fromOffset(playH, playH), function()
			Net.send(Remotes.ToServer.PickUpPlacedEgg, uid)
		end, {
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -(playH + 12), 0.5, 0),
			textSize = 16,
			parent = f,
		})
		pickUp.Name = "PickUp"
		pickUp.Visible = Config.ALLOW_EGG_PICKUP
		-- 6판: ⏩ 건너뛰기 (전부 / 절반 창). 다 자란 씨앗은 서버가 곧 성체로 바꿈 → 안내만
		local row: Row
		local skip = Ui.button("⏩", C.blue, UDim2.fromOffset(playH, playH), function()
			if row.ready then
				NotifyController.toast("다 자랐어요! 곧 성체가 돼요", "info")
			else
				IncubatorController.openSkip(uid)
			end
		end, { anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -6, 0.5, 0), textSize = 24, parent = f })
		skip.Name = "Skip"
		row = {
			frame = f,
			nameLabel = nameLabel,
			timeLabel = timeLabel,
			bar = bar,
			skip = skip,
			pickUp = pickUp,
			ready = false,
		}
		return row
	end

	local function makeCard(egg: Types.BagEgg, order: number)
		local rid = rarityOf(egg.petId)
		local rcolor = Theme.rarityColor(rid)
		local card = Ui.card(UDim2.fromOffset(cardW, cardH), Theme.darker(rcolor, 0.55), rcolor)
		card.Name = egg.uid
		card.LayoutOrder = order
		card.Parent = bag
		local glow: Frame = Ui.new("Frame", {
			Name = "EggBack",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, -12, 0, 58),
			BackgroundColor3 = Theme.darker(rcolor, 0.3),
			Parent = card,
		})
		Ui.corner(8).Parent = glow
		eggIcon(glow, egg.petId, 50)
		if egg.special then
			Ui.label("★", UDim2.fromOffset(24, 24), 22, C.yellow, {
				Position = UDim2.fromOffset(2, 0),
				Parent = glow,
			})
		end
		Ui.label(petName(egg.petId), UDim2.new(1, -8, 0, 24), 18, Theme.rarityText(rid), {
			Name = "EggName",
			Position = UDim2.fromOffset(4, 66),
			TextScaled = true,
			Parent = card,
		})
		Ui.label(eggDetail(egg), UDim2.new(1, -8, 0, 32), 14, C.white, {
			Name = "EggDetail",
			Position = UDim2.fromOffset(4, 90),
			TextScaled = true,
			Parent = card,
		})
		local uid = egg.uid
		local place = Ui.button("심기", C.shopGreen, UDim2.new(1, -12, 0, playH), function()
			IncubatorController.beginPlace(uid)
		end, { anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -6), textSize = 22, parent = card })
		place.Name = "Place"
	end

	local function visibleHeight(): number
		if currentTab == "bag" then
			local n = #snapEggs()
			local rowsN = math.min(math.max(math.ceil(n / GRID_COLS), 1), 2)
			return rowsN * (cardH + 6) + 8
		end
		local n = #snapIncubators()
		return math.min(math.max(n, 1), 3) * (rowH + 6) + 8
	end

	local function refreshTabs()
		local grow = currentTab == "grow"
		list.Visible = grow
		bag.Visible = not grow
		emptyGrow.Visible = grow and #snapIncubators() == 0
		emptyBag.Visible = not grow and #snapEggs() == 0
		Ui.setButton(
			tabGrow,
			string.format("자라는 중 %d · 정원 %d/%d", #snapIncubators(), gardenUsed(), gardenSlots()),
			if grow then C.shopGreen else C.gray
		)
		Ui.setButton(tabBag, string.format("가방 %d/%d", #snapEggs(), bagMax()), if grow then C.gray else C.pawOrange)
		-- 폰 화면에서도 위아래가 안 잘리게 (넘치면 목록이 스크롤)
		local maxH = Ui.area().Y / math.max(Ui.scale(), 0.01) - 24
		local wantH = contentTop + visibleHeight() + 6
		panel.Size = UDim2.fromOffset(PANEL_W, math.min(wantH, math.max(contentTop + 90, maxH)))
	end

	local function rebuildGrow()
		local incubators = snapIncubators()
		local seen: { [string]: boolean } = {}
		for i, record in incubators do
			local uid = tostring(record.uid)
			seen[uid] = true
			local row = rows[uid]
			if row then
				row.frame.LayoutOrder = i
			else
				rows[uid] = makeRow(record, i)
			end
		end
		for uid, row in rows do
			if not seen[uid] then
				row.frame:Destroy()
				rows[uid] = nil
			end
		end
	end

	local function rebuildBag()
		for _, child in bag:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, egg in snapEggs() do
			makeCard(egg, i)
		end
	end

	-- 막대·남은 시간·프롬프트·씨앗 버튼 배지
	local lastBadge = 0
	local function tick()
		refreshPrompts()
		for _, record in snapIncubators() do
			local uid = tostring(record.uid)
			local progress = tonumber(record.progress) or 0
			local required = tonumber(record.required) or 1
			local part = findPart(uid)
			if part then
				progress, required = partProgress(part, progress, required)
			end
			local isReady = progress >= required
			local row = rows[uid]
			if row then
				row.ready = isReady
				row.bar.Size = UDim2.fromScale(math.clamp(progress / math.max(required, 0.01), 0.04, 1), 1)
				row.bar.BackgroundColor3 = if isReady then C.yellow else C.shopGreen
				row.timeLabel.Text = if isReady
					then "곧 성체!"
					else shortTime(Economy.timerSeconds(progress, required)) -- 4판: 밤엔 이 숫자가 30배 빨리 줆
				row.timeLabel.TextColor3 = if isReady then Color3.fromRGB(70, 40, 0) else C.white
				-- 이름 · 단계 (새싹 / 줄기 / 봉오리)
				local stage = if isReady then "adult" else GardenRules.stage(progress, required)
				row.nameLabel.Text = petName(tostring(record.petId)) .. " · " .. GardenRules.stageName(stage)
				Ui.setButton(row.skip, nil, if isReady then C.gray else C.blue, not isReady)
				row.pickUp.Visible = Config.ALLOW_EGG_PICKUP and not isReady
			end
		end
		-- 배지 = 가방 속 씨앗 (심을 일). 6판: 다 자라면 저절로 성체라 "부화 가능" 수는 안 셈
		local count = #snapEggs()
		local badge = HudController.eggBadge
		if badge then
			badge.Visible = count > 0
			badge.Text = tostring(count)
			if count > lastBadge then
				Ui.pop(badge, 1.5)
			end
		end
		lastBadge = count
	end

	local function rebuild()
		rebuildGrow()
		rebuildBag()
		refreshTabs()
		tick()
	end

	local function setTab(name: string)
		currentTab = if name == "bag" then "bag" else "grow"
		refreshTabs()
	end
	tabGrow.Activated:Connect(function()
		setTab("grow")
	end)
	tabBag.Activated:Connect(function()
		setTab("bag")
	end)
	Ui.onLayout(refreshTabs)

	local function toggle()
		panel.Visible = not panel.Visible
		if panel.Visible then
			IncubatorController.cancelPlace()
			rebuild()
			Ui.pop(panel, 0.85)
		end
	end
	HudController.setEggPanelToggle(toggle)
	IncubatorController.toggle = toggle
	IncubatorController.panel = panel
	IncubatorController.setTab = setTab

	buildPlaceBar()
	hookPlaceInput()

	State.onChanged(function(section: string)
		if section == "snapshot" or section == "incubators" then
			rebuildGrow()
			refreshTabs()
		elseif section == "pets" or section == "upgrades" then
			refreshTabs() -- 정원 칸 (성체 수 · penSlots)
		end
		if section == "snapshot" or section == "eggs" then
			rebuildBag()
			refreshTabs()
			-- 심으려던 씨앗이 가방에서 없어짐 (심기 성공 등) → 심기 모드 끝
			local state = placing
			if state then
				local still = false
				for _, egg in snapEggs() do
					if egg.uid == state.uid then
						still = true
						break
					end
				end
				if not still then
					IncubatorController.cancelPlace()
				end
			end
		end
		if section == "snapshot" or section == "incubators" or section == "eggs" then
			tick()
		end
	end)
	rebuild()

	for _, inst in CollectionService:GetTagged(Tags.IncubatingEgg) do
		decorate(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.IncubatingEgg):Connect(function(inst: Instance)
		task.defer(decorate, inst)
	end)

	-- 진행 갱신 (0.5초마다 + 목록이 바뀔 때)
	task.spawn(function()
		while true do
			tick()
			task.wait(0.5)
		end
	end)

	-- 새 씨앗이 가방에 들어오면 씨앗 버튼 통통 + 다음에 열 때 가방 탭
	local function onNewEgg()
		local badge = HudController.eggBadge
		if badge and badge.Parent and badge.Parent:IsA("GuiObject") then
			Ui.pop(badge.Parent :: GuiObject, 1.25)
		end
		if not panel.Visible then
			setTab("bag")
		end
	end
	Net.on(Remotes.ToClient.EggDelivered, onNewEgg)
	Net.on(Remotes.ToClient.EggGranted, onNewEgg)
end

return IncubatorController
