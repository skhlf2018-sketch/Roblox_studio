--!strict
--[[
	AltarController — 천사&악마 구역 제단 2개 (Tag Altar, Attr Side) + 비밀 통로 합성 제단 (Tag Shrine)

	제단:
	- 프롬프트 "제물 바치기" → 그 쪽(천국/지옥) 펫 1마리 고르기 → AltarOffer(uid)
	- 제단 위 이름표(내 화면): 서버가 쓰는 PendingCount 로 "기다리는 제물 N"
	- AltarUpdate → 화면 위 상태 띠: "제단: 기다리는 중 (1/2)" (계속) / "짝 성공!" + 알 카드 / "취소됨"
	비밀 통로:
	- 프롬프트 "비밀 합성" → 레시피 펫 2마리 고르기 → ShrineFuse(a, b) → ShrineResult 카드 + 마법진 연출
	- shrineUsed 로 다 쓴 레시피는 "이미 사용함" (둘 다 썼으면 창을 안 열고 알림)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local AltarRules = require(Shared.AltarRules)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local PetPicker = require(Client.UI.PetPicker)
local WorldPrompt = require(Client.UI.WorldPrompt)
local Fx = require(Client.UI.Fx)
local SoundController = require(script.Parent.SoundController)
local NotifyController = require(script.Parent.NotifyController)
local HatchController = require(script.Parent.HatchController)

local AltarController = {}

local C = Theme.Colors
local SIDE_NAME: { [string]: string } = { light = "천국", dark = "지옥" }
local SIDE_COLOR: { [string]: Color3 } = {
	light = Color3.fromRGB(255, 215, 90),
	dark = Color3.fromRGB(230, 50, 50),
}

local function sideOf(part: BasePart): string?
	local side = part:GetAttribute("Side")
	if side == nil and part.Parent and part.Parent:IsA("Model") then
		side = part.Parent:GetAttribute("Side")
	end
	return if typeof(side) == "string" and SIDE_NAME[side] then side else nil
end

local function myRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function tooFar(part: BasePart, radius: number): () -> boolean
	return function(): boolean
		local root = myRoot()
		return part.Parent == nil or WorldPrompt.distanceTo(part, if root then root.Position else nil) > radius + 4
	end
end

local function petName(id: any): string
	local pet = Pets.get(tostring(id))
	return if pet then pet.name else tostring(id)
end

local function shrineUsed(): { [string]: boolean }
	local snap = State.get()
	return if snap and snap.shrineUsed then snap.shrineUsed else {}
end

------------------------------------------------------------------
-- 이름표 (내 화면)
------------------------------------------------------------------

local function billboard(part: BasePart, offsetY: number, color: Color3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "AltarStatus"
	gui.Size = UDim2.fromOffset(230, 38)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(30, 20, 40)
	label.Parent = gui
	gui.Parent = part
	return label
end

------------------------------------------------------------------
-- 제단
------------------------------------------------------------------

local function openAltar(part: BasePart, allAltars: () -> { BasePart })
	local side = sideOf(part)
	if not side then
		return
	end
	local other = if side == "light" then "dark" else "light"
	local waiting = 0
	for _, altar in allAltars() do
		if sideOf(altar) == other then
			local n = altar:GetAttribute("PendingCount")
			waiting += if typeof(n) == "number" then n else 0
		end
	end
	local name = SIDE_NAME[side]
	PetPicker.open({
		title = name .. " 제단",
		color = if side == "light" then Color3.fromRGB(235, 185, 60) else Color3.fromRGB(170, 30, 40),
		hint = if waiting > 0
			then string.format(
				"%s 제단에 %d명이 기다리는 중! 지금 바치면 바로 짝이 돼요",
				SIDE_NAME[other],
				waiting
			)
			else string.format(
				"이번 주기 안에 다른 사람이 %s 제단에 바치면 둘 다 링 가드/링로드 알!",
				SIDE_NAME[other]
			),
		count = 1,
		filters = { PetPicker.sameSide(side) },
		check = function(item: PetPicker.Item): (boolean, string?)
			if AltarRules.sideOfPet(item.petId) ~= side then
				return false, name .. " 쪽 펫만"
			end
			return true, nil
		end,
		empty = name .. " 쪽 펫이 없어요! (천사&악마 구역 " .. name .. " 쪽 둥지 알)",
		confirmText = "바치기",
		onConfirm = function(selected: { PetPicker.Item })
			Net.send(Remotes.ToServer.AltarOffer, selected[1].uid)
			SoundController.play("AltarOffer")
		end,
		closeWhen = tooFar(part, Config.ALTAR_RADIUS),
	})
end

------------------------------------------------------------------
-- 비밀 통로
------------------------------------------------------------------

local function recipeInputs(): { [string]: boolean }
	local used = shrineUsed()
	local inputs: { [string]: boolean } = {}
	for _, recipe in AltarRules.RECIPES do
		if not used[recipe.result] then
			inputs[recipe.a] = true
			inputs[recipe.b] = true
		end
	end
	return inputs
end

local function recipeText(): string
	local used = shrineUsed()
	local parts: { string } = {}
	for _, recipe in AltarRules.RECIPES do
		table.insert(
			parts,
			string.format(
				"%s + %s → %s%s",
				petName(recipe.a),
				petName(recipe.b),
				petName(recipe.result),
				if used[recipe.result] then " (이미 사용함)" else ""
			)
		)
	end
	return table.concat(parts, "   /   ")
end

local function openShrine(part: BasePart)
	local inputs = recipeInputs()
	if next(inputs) == nil then
		NotifyController.toast("비밀 합성은 이미 사용함! (계정당 레시피마다 한 번)", "info")
		return
	end
	PetPicker.open({
		title = "비밀 통로 합성 제단",
		color = Color3.fromRGB(130, 90, 210),
		hint = recipeText(),
		count = 2,
		filters = {
			{
				id = "recipe",
				label = "재료만",
				default = true,
				test = function(item: PetPicker.Item): boolean
					return inputs[item.petId] == true
				end,
			},
		},
		check = function(item: PetPicker.Item, selected: { PetPicker.Item }): (boolean, string?)
			if not inputs[item.petId] then
				return false, "재료 아님"
			end
			if #selected == 1 then
				local recipe = AltarRules.recipeFor(selected[1].petId, item.petId)
				if not recipe or shrineUsed()[recipe.result] then
					return false, "짝이 아님"
				end
			end
			return true, nil
		end,
		ready = function(selected: { PetPicker.Item }): (boolean, string?)
			local recipe = AltarRules.recipeFor(selected[1].petId, selected[2].petId)
			if not recipe then
				return false, "이 두 펫은 합성할 수 없어요"
			end
			if shrineUsed()[recipe.result] then
				return false, petName(recipe.result) .. " 합성은 이미 사용함"
			end
			return true, nil
		end,
		status = function(selected: { PetPicker.Item }): string?
			if #selected == 2 then
				local recipe = AltarRules.recipeFor(selected[1].petId, selected[2].petId)
				if recipe then
					return "결과: " .. petName(recipe.result) .. " 알! (두 펫은 사라져요)"
				end
			end
			return nil
		end,
		empty = "합성 재료 펫이 없어요! " .. recipeText(),
		confirmText = "합성!",
		onConfirm = function(selected: { PetPicker.Item })
			Net.send(Remotes.ToServer.ShrineFuse, selected[1].uid, selected[2].uid)
		end,
		closeWhen = tooFar(part, Config.SHRINE_RADIUS),
	})
end

------------------------------------------------------------------
-- 상태 띠 (AltarUpdate)
------------------------------------------------------------------

local function makeStatus(): (TextLabel, (string, Color3, number?) -> (), () -> ())
	local pill: TextLabel = Ui.new("TextLabel", {
		Name = "AltarStatus",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 124),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.blue,
		TextColor3 = C.white,
		TextSize = 24,
		Text = "",
		Visible = false,
		Parent = Ui.layer("Panels"),
	})
	Ui.scaled(pill)
	Ui.padding(18, 4).Parent = pill
	Ui.corner(1).Parent = pill
	Ui.stroke(C.white, 3).Parent = pill
	Ui.textStroke(2).Parent = pill
	local token = 0
	local function show(text: string, color: Color3, seconds: number?)
		token += 1
		local mine = token
		pill.Text = text
		pill.BackgroundColor3 = color
		pill.Visible = true
		Ui.pop(pill, 1.2)
		if seconds then
			task.delay(seconds, function()
				if token == mine then
					pill.Visible = false
				end
			end)
		end
	end
	local function hide()
		token += 1
		pill.Visible = false
	end
	return pill, show, hide
end

function AltarController.start()
	local labels: { [BasePart]: TextLabel } = {}
	local handle: WorldPrompt.Handle
	local function altars(): { BasePart }
		return handle.parts()
	end
	handle = WorldPrompt.attach({
		tag = Tags.Altar,
		name = "AltarPrompt",
		action = "제물 바치기",
		object = function(part: BasePart): string
			local side = sideOf(part)
			return (if side then SIDE_NAME[side] else "") .. " 제단"
		end,
		distance = 12,
		onTrigger = function(part: BasePart)
			openAltar(part, altars)
		end,
	})

	local function refreshLabel(part: BasePart)
		local side = sideOf(part)
		if not side then
			return
		end
		local label = labels[part]
		if not label then
			label = billboard(part, 10, SIDE_COLOR[side])
			labels[part] = label
			part:GetAttributeChangedSignal("PendingCount"):Connect(function()
				refreshLabel(part)
			end)
		end
		local n = part:GetAttribute("PendingCount")
		local count = if typeof(n) == "number" then n else 0
		local l = label :: TextLabel
		l.Text = if count > 0
			then string.format("기다리는 제물 %d개!", count)
			else SIDE_NAME[side] .. " 쪽 펫을 바쳐요"
	end
	local function refreshAll()
		for _, part in handle.parts() do
			refreshLabel(part)
		end
	end
	CollectionService:GetInstanceAddedSignal(Tags.Altar):Connect(function()
		task.defer(refreshAll)
	end)
	refreshAll()

	local shrines = WorldPrompt.attach({
		tag = Tags.Shrine,
		name = "ShrinePrompt",
		action = function(): string
			return if next(recipeInputs()) == nil then "이미 사용함" else "비밀 합성"
		end,
		object = "비밀 통로 제단",
		distance = 12,
		onTrigger = openShrine,
	})
	State.onChanged(function(section: string)
		if section == "special" or section == "snapshot" then
			shrines.refresh()
		end
	end)

	-- AltarUpdate 상태 띠 + 연출
	local _, showStatus, hideStatus = makeStatus()
	local function altarOfSide(side: string): BasePart?
		for _, part in handle.parts() do
			if sideOf(part) == side then
				return part
			end
		end
		return nil
	end
	Net.on(Remotes.ToClient.AltarUpdate, function(p: any)
		if typeof(p) ~= "table" then
			return
		end
		local side = tostring(p.side)
		local name = SIDE_NAME[side] or side
		local altar = altarOfSide(side)
		if p.status == "pending" then
			showStatus(
				string.format("제단: 기다리는 중 (1/2) · %s 제단에 %s", name, petName(p.petId)),
				Theme.darker(SIDE_COLOR[side] or C.blue, 0.2)
			)
			if altar then
				Fx.burst(altar.Position + Vector3.new(0, 3, 0), SIDE_COLOR[side] or C.white, 30, 0.8, 8)
			end
		elseif p.status == "paired" then
			showStatus(
				"짝 성공! (2/2)" .. (if p.partner and p.partner ~= "" then " · " .. tostring(p.partner) else ""),
				C.green,
				5
			)
			SoundController.play("AltarPaired")
			NotifyController.banner("제단 짝 성공! 특별한 알!", C.yellow)
			if altar then
				local pos = altar.Position + Vector3.new(0, 3, 0)
				Fx.pillar(altar.Position, SIDE_COLOR[side] or C.white, 70, 2.2)
				Fx.burst(pos, Color3.new(1, 1, 1), 60, 1.2, 16)
				Fx.flash(pos, SIDE_COLOR[side] or C.white, 40, 1.2)
			end
			local eggId = tostring(p.eggPetId or AltarRules.RING_GUARD)
			HatchController.show({
				pet = { petId = eggId, size = "normal", mutations = {} },
				income = Economy.petIncome(eggId, "normal", {}),
				title = "제단 성공!",
				titleColor = C.yellow,
				ribbon = petName(eggId) .. " 알",
				footer = "알이 가방에 들어갔어요"
					.. (if p.partner and p.partner ~= "" then " (짝: " .. tostring(p.partner) .. ")" else ""),
				delay = 0.8,
			})
		elseif p.status == "expired" then
			showStatus("제단 제물 취소됨 (주기 끝, 펫은 그대로)", C.gray, 5)
		else
			hideStatus()
		end
	end)

	Net.on(Remotes.ToClient.ShrineResult, function(p: any)
		if typeof(p) ~= "table" then
			return
		end
		SoundController.play("Shrine")
		local part = shrines.parts()[1]
		if part then
			local pos = part.Position + Vector3.new(0, 3, 0)
			Fx.gather(pos, Color3.fromRGB(190, 140, 255), 1.0, 7)
			task.delay(1, function()
				Fx.pillar(part.Position, Color3.fromRGB(200, 160, 255), 60, 2)
			end)
		end
		local resultId = tostring(p.resultPetId)
		local mutations = if typeof(p.mutations) == "table" then p.mutations else {}
		local size = tostring(p.size or "normal")
		HatchController.show({
			pet = { petId = resultId, size = size, mutations = mutations },
			income = Economy.petIncome(resultId, size, mutations),
			title = "비밀 합성!",
			titleColor = C.purple,
			ribbon = "합성 알",
			footer = "알이 가방에 들어갔어요",
			delay = 1.1,
		})
		shrines.refresh()
	end)
end

return AltarController
