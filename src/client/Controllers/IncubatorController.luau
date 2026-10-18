--!strict
--[[
	IncubatorController — 우리 안에서 자라는 알 (2판: 원작 "성장하는 달걀" 패널 + 알 머리 위 시간)

	- 오른쪽 "성장하는 달걀" 패널 (오른쪽 주황 알 버튼으로 열고 닫음 — HudController.setEggPanelToggle)
	  줄마다: 알 그림 + 초록 진행 막대 + 남은 시간 "5m 25s" + 초록 ▶ 버튼
	  ▶ : 다 자랐으면 HatchEgg(uid) 요청 (서버가 다시 검사), 아직이면 "우리에 가서 알 옆에서 E 로 부화" 안내
	  "모두 성장시키기" (로벅스) 는 어른 확인 전이라 꺼 둠.
	- 알 버튼 배지 = 지금 부화할 수 있는 알 수.
	- 월드: 우리 안 부화 중 알(태그 IncubatingEgg) 위에 "에그 / 1m 52s" 이름표, 다 자란 내 알에는 "부화!" 프롬프트(E) → HatchEgg
	진행값: 알 파트 Attribute Progress/Required(서버가 갱신) 우선, 없으면 Snapshot incubators.
	남은 시간 = (Required - Progress) / 성장 속도 (밤이면 Config 배율).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Economy)
local Visuals = require(Shared.Data.Visuals)
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

local IncubatorController = {}
IncubatorController.toggle = nil :: (() -> ())?
IncubatorController.panel = nil :: Frame?

local C = Theme.Colors

type Row = {
	frame: Frame,
	timeLabel: TextLabel,
	bar: Frame,
	play: TextButton,
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

local function findPart(uid: string): BasePart?
	local me = Players.LocalPlayer.UserId
	for _, inst in CollectionService:GetTagged(Tags.IncubatingEgg) do
		if inst:IsA("BasePart") and inst:GetAttribute("EggUid") == uid and inst:GetAttribute("OwnerUserId") == me then
			return inst
		end
	end
	return nil
end

local function phaseRate(): number
	local state = ReplicatedStorage:FindFirstChild(Tags.StateFolderName)
	local phase = if state then state:GetAttribute(Tags.StateAttributes.Phase) else "Day"
	return Economy.growthRate(phase == "Night", false)
end

local function partProgress(part: BasePart, fallbackP: number, fallbackR: number): (number, number)
	local p = part:GetAttribute("Progress")
	local r = part:GetAttribute("Required")
	return if typeof(p) == "number" then p else fallbackP, if typeof(r) == "number" then r else fallbackR
end

------------------------------------------------------------------
-- 월드: 알 위 "에그 / 1m 52s" + 부화 프롬프트
------------------------------------------------------------------

type EggTag = { gui: BillboardGui, title: TextLabel, time: TextLabel, prompt: ProximityPrompt? }
local eggTags: { [BasePart]: EggTag } = {}

local function decorate(inst: Instance)
	if not inst:IsA("BasePart") or eggTags[inst] then
		return
	end
	local part = inst
	local gui = Instance.new("BillboardGui")
	gui.Name = "GrowTag"
	gui.Size = UDim2.fromScale(6, 2.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2.6, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Adornee = part
	local function line(name: string, y: number, h: number, color: Color3): TextLabel
		local t = Ui.label("", UDim2.fromScale(1, h), 20, color, {
			Name = name,
			Position = UDim2.fromScale(0, y),
			TextScaled = true,
			Parent = gui,
		})
		local s = t:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = C.winEdge
			s.Thickness = 2.5
		end
		return t
	end
	local title = line("Title", 0, 0.46, C.white)
	title.Text = "에그"
	local time = line("Time", 0.46, 0.54, C.white)
	gui.Parent = part
	local tag: EggTag = { gui = gui, title = title, time = time }
	if part:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HatchPrompt"
		prompt.ActionText = "부화!"
		prompt.ObjectText = "에그"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Triggered:Connect(function()
			local uid = part:GetAttribute("EggUid")
			if typeof(uid) == "string" then
				Net.send(Remotes.ToServer.HatchEgg, uid)
			end
		end)
		prompt.Parent = part
		tag.prompt = prompt
	end
	eggTags[part] = tag
end

local function refreshEggTags(rate: number)
	for part, tag in eggTags do
		if part.Parent == nil then
			eggTags[part] = nil
		else
			local progress, required = partProgress(part, 0, 1)
			local ready = part:GetAttribute("Ready") == true or progress >= required
			if ready then
				tag.title.Text = "에그"
				tag.time.Text = "부화!"
				tag.time.TextColor3 = C.moneyGreen
			else
				tag.time.Text = shortTime(Economy.remainingSeconds(progress, required, rate))
				tag.time.TextColor3 = C.white
			end
			local prompt = tag.prompt
			if prompt then
				prompt.Enabled = ready
			end
		end
	end
end

------------------------------------------------------------------
-- 패널
------------------------------------------------------------------

function IncubatorController.start()
	local panel: Frame = Ui.new("Frame", {
		Name = "GrowingEggs",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -104, 0.46, 0),
		Size = UDim2.fromOffset(380, 240),
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
	Ui.label("성장하는 달걀", UDim2.new(1, -170, 1, 0), 26, C.white, {
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

	local list: ScrollingFrame = Ui.scroll(UDim2.new(1, -12, 1, -64), UDim2.fromOffset(6, 58), panel)
	list.Name = "List"
	Ui.list(Enum.FillDirection.Vertical, 6).Parent = list
	local empty = Ui.label(
		"자라는 알이 없어요!\n알을 훔쳐서 내 베이스로 가져와요",
		UDim2.new(1, 0, 0, 80),
		20,
		C.white,
		{
			Name = "Empty",
			Position = UDim2.fromOffset(0, 70),
			Parent = panel,
		}
	)

	local rows: { [string]: Row } = {}
	local playH = Ui.touch(44)

	local function makeRow(record: any, order: number): Row
		local f: Frame = Ui.new("Frame", {
			Name = tostring(record.uid),
			Size = UDim2.new(1, -6, 0, math.max(60, playH + 12)),
			BackgroundColor3 = Color3.fromRGB(62, 64, 78),
			LayoutOrder = order,
			Parent = list,
		})
		Ui.corner(6).Parent = f
		Ui.stroke(C.winEdge, 2).Parent = f
		local ec = Visuals.petColor(tostring(record.petId), 1)
		local eggBox: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(56, 48),
			BackgroundColor3 = Color3.fromRGB(90, 92, 108),
			Parent = f,
		})
		Ui.corner(4).Parent = eggBox
		local egg = Icons.draw("egg", eggBox, 42)
		for _, d in egg:GetDescendants() do
			if d:IsA("Frame") and d.BackgroundTransparency < 0.5 then
				d.BackgroundColor3 = Color3.fromRGB(ec[1], ec[2], ec[3])
				break
			end
		end
		local barBack: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 70, 0.5, 0),
			Size = UDim2.new(1, -140, 0, 30),
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
		local timeLabel = Ui.label("", UDim2.fromScale(1, 1), 22, C.white, {
			Name = "Time",
			ZIndex = 3,
			Parent = barBack,
		})
		local uid = tostring(record.uid)
		local row: Row
		local play = Ui.button("▶", C.shopGreen, UDim2.fromOffset(playH, playH), function()
			if row.ready then
				Net.send(Remotes.ToServer.HatchEgg, uid)
			else
				NotifyController.toast(
					"아직 자라는 중이에요! 다 자라면 우리에 가서 알 옆에서 E",
					"info"
				)
			end
		end, { anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -6, 0.5, 0), textSize = 24, parent = f })
		play.Name = "Play"
		row = { frame = f, timeLabel = timeLabel, bar = bar, play = play, ready = false }
		return row
	end

	local function rebuild()
		local snap = State.get()
		local incubators: { Types.IncubatorRecord } = if snap then snap.incubators or {} else {}
		local seen: { [string]: boolean } = {}
		for i, record in incubators do
			local uid = tostring(record.uid)
			seen[uid] = true
			if not rows[uid] then
				rows[uid] = makeRow(record, record.slot or i)
			end
		end
		for uid, row in rows do
			if not seen[uid] then
				row.frame:Destroy()
				rows[uid] = nil
			end
		end
		empty.Visible = #incubators == 0
		local h = math.min(math.max(#incubators, 1), 4) * (math.max(60, playH + 12) + 6) + 70
		panel.Size = UDim2.fromOffset(380, h)
	end

	local function toggle()
		panel.Visible = not panel.Visible
		if panel.Visible then
			rebuild()
			Ui.pop(panel, 0.85)
		end
	end
	HudController.setEggPanelToggle(toggle)
	IncubatorController.toggle = toggle
	IncubatorController.panel = panel

	State.onChanged(function(section: string)
		if section == "snapshot" or section == "incubators" then
			rebuild()
		end
	end)
	rebuild()

	for _, inst in CollectionService:GetTagged(Tags.IncubatingEgg) do
		decorate(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.IncubatingEgg):Connect(function(inst: Instance)
		task.defer(decorate, inst)
	end)

	-- 진행 갱신
	task.spawn(function()
		local lastReady = 0
		while true do
			local rate = phaseRate()
			refreshEggTags(rate)
			local snap = State.get()
			local ready = 0
			if snap then
				for _, record in (snap.incubators or {}) :: { Types.IncubatorRecord } do
					local uid = tostring(record.uid)
					local progress = tonumber(record.progress) or 0
					local required = tonumber(record.required) or 1
					local part = findPart(uid)
					if part then
						progress, required = partProgress(part, progress, required)
					end
					local isReady = progress >= required
					if isReady then
						ready += 1
					end
					local row = rows[uid]
					if row then
						row.ready = isReady
						row.bar.Size = UDim2.fromScale(math.clamp(progress / math.max(required, 0.01), 0.04, 1), 1)
						row.bar.BackgroundColor3 = if isReady then C.yellow else C.shopGreen
						row.timeLabel.Text = if isReady
							then "부화!"
							else shortTime(Economy.remainingSeconds(progress, required, rate))
					end
				end
			end
			local badge = HudController.eggBadge
			if badge then
				badge.Visible = ready > 0
				badge.Text = tostring(ready)
				if ready > lastReady then
					Ui.pop(badge, 1.5)
				end
			end
			lastReady = ready
			task.wait(0.5)
		end
	end)

	-- 새 알이 들어오면 알 버튼 통통
	Net.on(Remotes.ToClient.EggDelivered, function()
		local badge = HudController.eggBadge
		if badge and badge.Parent and badge.Parent:IsA("GuiObject") then
			Ui.pop(badge.Parent :: GuiObject, 1.25)
		end
		if panel.Visible then
			rebuild()
		end
	end)
end

return IncubatorController
