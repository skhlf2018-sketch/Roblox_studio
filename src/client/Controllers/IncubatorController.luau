--!strict
--[[
	IncubatorController — "자라는 알 (Growing Eggs)" 패널 (오른쪽)
	- 목록: State.incubators (배달 때 추가, 부화 때 제거)
	- 진행: 내 IncubatingEgg 파트의 Progress/Required/Ready Attribute (서버가 1초마다 갱신)
	- 남은 시간 = (Required - Progress) / 성장 속도 (밤 30배)
	- 다 자라면 "부화!" 버튼 → HatchEgg(uid). "모두 부화!" 버튼도 있음.
	제목을 누르면 접고 펼 수 있음 (작은 화면용).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Pets = require(Shared.Data.Pets)
local Visuals = require(Shared.Data.Visuals)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)

local IncubatorController = {}

local C = Theme.Colors

type Row = {
	frame: Frame,
	timeLabel: TextLabel,
	bar: Frame,
	hatch: TextButton,
}

local function findPart(uid: string): BasePart?
	local me = Players.LocalPlayer.UserId
	for _, inst in CollectionService:GetTagged(Tags.IncubatingEgg) do
		if inst:IsA("BasePart") and inst:GetAttribute("EggUid") == uid and inst:GetAttribute("OwnerUserId") == me then
			return inst
		end
	end
	return nil
end

function IncubatorController.start()
	local panel: Frame = Ui.new("Frame", {
		Name = "GrowingEggs",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.42, 0),
		Size = UDim2.fromOffset(330, 60),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = Ui.layer("Panels"),
	})
	Ui.scaled(panel)
	Ui.corner(20).Parent = panel
	Ui.stroke(C.white, 4).Parent = panel
	Ui.padding(10).Parent = panel
	Ui.list(Enum.FillDirection.Vertical, 6).Parent = panel

	local header = Ui.button("자라는 알 0/" .. Config.INCUBATOR_SLOTS, C.mint, UDim2.new(1, 0, 0, 64), nil, {
		textSize = 24,
		layoutOrder = 0,
		parent = panel,
	})
	local hatchAll = Ui.button("모두 부화!", C.orange, UDim2.new(1, 0, 0, 64), nil, {
		textSize = 26,
		layoutOrder = 1,
		parent = panel,
	})
	hatchAll.Visible = false
	local list: ScrollingFrame = Ui.scroll(UDim2.fromScale(1, 0), nil, panel)
	list.LayoutOrder = 2
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Ui.list(Enum.FillDirection.Vertical, 6).Parent = list

	-- 폰에서는 접힌 채 시작하지만, 다 자란 알이 새로 생기면 저절로 펼침 + 제목에 "부화 가능 N" 배지
	local collapsed = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local readyBadge = Ui.badge(header)
	readyBadge.Position = UDim2.new(1, -8, 0, 8)
	readyBadge.Size = UDim2.fromOffset(40, 40)
	readyBadge.TextSize = 22
	local rows: { [string]: Row } = {}

	local function sendHatch(uid: string)
		Net.send(Remotes.ToServer.HatchEgg, uid)
	end

	local function makeRow(record: any, order: number): Row
		local pet = Pets.get(tostring(record.petId))
		local rarity = if pet then pet.rarity else "common"
		local f: Frame = Ui.new("Frame", {
			Name = tostring(record.uid),
			Size = UDim2.new(1, -12, 0, 72),
			BackgroundColor3 = C.white,
			LayoutOrder = order,
			Parent = list,
		})
		Ui.corner(14).Parent = f
		Ui.stroke(Theme.rarityColor(rarity), 3).Parent = f
		local ec = Visuals.petColor(tostring(record.petId), 1)
		local egg: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(36, 46),
			BackgroundColor3 = Color3.fromRGB(ec[1], ec[2], ec[3]),
			Parent = f,
		})
		Ui.corner(1).Parent = egg
		Ui.stroke(C.ink, 2).Parent = egg
		Ui.label(
			if pet then pet.name else tostring(record.petId),
			UDim2.new(1, -150, 0, 28),
			22,
			Theme.rarityColor(rarity),
			{
				Position = UDim2.fromOffset(52, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextScaled = true,
				Parent = f,
			}
		)
		local barBack: Frame = Ui.new("Frame", {
			Position = UDim2.fromOffset(52, 38),
			Size = UDim2.new(1, -150, 0, 14),
			BackgroundColor3 = Color3.fromRGB(225, 220, 210),
			Parent = f,
		})
		Ui.corner(1).Parent = barBack
		local bar: Frame = Ui.new("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.green,
			Parent = barBack,
		})
		Ui.corner(1).Parent = bar
		local timeLabel = Ui.label("", UDim2.fromOffset(90, 50), 22, C.ink, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			TextScaled = true,
			Parent = f,
		})
		local uid = tostring(record.uid)
		local hatch = Ui.button("부화!", C.orange, UDim2.fromOffset(96, 64), function()
			sendHatch(uid)
		end, { anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -6, 0.5, 0), textSize = 24, parent = f })
		hatch.Visible = false
		return { frame = f, timeLabel = timeLabel, bar = bar, hatch = hatch }
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
		panel.Visible = #incubators > 0
		header.Text = string.format(
			"자라는 알 %d/%d %s",
			#incubators,
			Config.INCUBATOR_SLOTS,
			if collapsed then "▼" else "▲"
		)
		local count = #incubators
		list.Visible = not collapsed
		list.Size = UDim2.new(1, 0, 0, math.min(count, 4) * 78)
	end

	header.Activated:Connect(function()
		collapsed = not collapsed
		rebuild()
	end)
	hatchAll.Activated:Connect(function()
		local snap = State.get()
		if not snap then
			return
		end
		task.spawn(function()
			for _, record in (snap.incubators or {}) :: { Types.IncubatorRecord } do
				local row = rows[tostring(record.uid)]
				if row and row.hatch.Visible then
					sendHatch(tostring(record.uid))
					task.wait(0.3)
				end
			end
		end)
	end)

	State.onChanged(function(section: string)
		if section == "snapshot" or section == "incubators" then
			rebuild()
		end
	end)
	rebuild()

	-- 진행 갱신
	task.spawn(function()
		local stateFolder = ReplicatedStorage:WaitForChild(Tags.StateFolderName, 30)
		local lastReady = 0
		while true do
			task.wait(0.5)
			local snap = State.get()
			if snap and panel.Visible then
				local phase = if stateFolder then stateFolder:GetAttribute(Tags.StateAttributes.Phase) else "Day"
				local rate = Economy.growthRate(phase == "Night", false)
				local ready = 0
				for _, record in (snap.incubators or {}) :: { Types.IncubatorRecord } do
					local uid = tostring(record.uid)
					local row = rows[uid]
					if row then
						local part = findPart(uid)
						local progress = tonumber(record.progress) or 0
						local required = tonumber(record.required) or 1
						if part then
							local p = part:GetAttribute("Progress")
							local r = part:GetAttribute("Required")
							if typeof(p) == "number" then
								progress = p
							end
							if typeof(r) == "number" then
								required = r
							end
						end
						local isReady = progress >= required
						row.bar.Size = UDim2.fromScale(math.clamp(progress / math.max(required, 0.01), 0, 1), 1)
						row.bar.BackgroundColor3 = if isReady
							then C.orange
							elseif phase == "Night" then C.purple
							else C.green
						row.hatch.Visible = isReady
						row.timeLabel.Visible = not isReady
						if not isReady then
							row.timeLabel.Text = Format.duration(Economy.remainingSeconds(progress, required, rate))
						else
							ready += 1
						end
					end
				end
				hatchAll.Visible = ready >= 2
				readyBadge.Visible = ready > 0
				readyBadge.Text = tostring(ready)
				if ready > lastReady then
					Ui.pop(header, 1.15)
					Ui.pop(readyBadge, 1.4)
					if collapsed then
						collapsed = false
						rebuild()
					end
				end
				lastReady = ready
			end
		end
	end)
end

return IncubatorController
