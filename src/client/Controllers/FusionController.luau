--!strict
--[[
	FusionController — 퓨전 머신 (베이스 FusionMachine 태그 파트)
	- 내 베이스 머신에만 ProximityPrompt "퓨전" (클라에서 붙임. 거리 검사는 서버 FUSION_RADIUS 12)
	- 누르면 펫 고르기 창: 같은 펫 3마리 → FuseRequest(u1, u2, u3)
	  고르는 동안 "나올 수 있는 펫"(FusionRules.candidates) 안내, 더 강해질 수 없으면("weaker") 확인 버튼 끔
	- FusionResult → 머신 유리통이 차례로 번쩍 + 가운데로 빛 모으기 → 펑! (카드는 HatchController 가 1.3초 뒤)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Data.Pets)
local Config = require(Shared.Data.Config)
local FusionRules = require(Shared.FusionRules)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local PetPicker = require(Client.UI.PetPicker)
local WorldPrompt = require(Client.UI.WorldPrompt)
local Fx = require(Client.UI.Fx)
local SoundController = require(script.Parent.SoundController)
local NotifyController = require(script.Parent.NotifyController)

local FusionController = {}

local C = Theme.Colors
local GLOW = Color3.fromRGB(230, 130, 255)

local function myRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function isMine(part: BasePart): boolean
	local index = Players.LocalPlayer:GetAttribute(Tags.PlayerAttributes.PlotIndex)
	return typeof(index) == "number" and index > 0 and part:GetAttribute("PlotIndex") == index
end

local machines: WorldPrompt.Handle? = nil

local function myMachine(): BasePart?
	local handle = machines
	if not handle then
		return nil
	end
	for _, part in handle.parts() do
		if isMine(part) then
			return part
		end
	end
	return nil
end

local function toRecords(items: { PetPicker.Item }): { Types.PetRecord }
	local records: { Types.PetRecord } = {}
	for _, item in items do
		table.insert(records, { uid = item.uid, petId = item.petId, size = item.size, mutations = item.mutations })
	end
	return records
end

local function candidateText(petId: string): string
	local names: { string } = {}
	for _, pet in FusionRules.candidates(petId) do
		table.insert(names, pet.name)
		if #names >= 4 then
			break
		end
	end
	if #names == 0 then
		local pet = Pets.get(petId)
		return "결과: " .. (if pet then pet.name else petId) .. " 크기 UP!"
	end
	return "나올 수 있는 펫: " .. table.concat(names, ", ")
end

local function openPicker(machine: BasePart)
	PetPicker.open({
		title = "퓨전 머신",
		color = C.purple,
		hint = "같은 펫 3마리를 골라요 → 더 강한 펫 1마리! (되돌릴 수 없어요)",
		count = FusionRules.INPUT_COUNT,
		filters = { PetPicker.sameSpecies(FusionRules.INPUT_COUNT) },
		empty = "같은 펫이 3마리 있어야 퓨전할 수 있어요!",
		confirmText = "퓨전!",
		check = function(item: PetPicker.Item, selected: { PetPicker.Item }): (boolean, string?)
			if #selected > 0 and item.petId ~= selected[1].petId then
				return false, "같은 펫만"
			end
			local n = 0
			for _, other in PetPicker.currentItems() do
				if other.petId == item.petId then
					n += 1
				end
			end
			if n < FusionRules.INPUT_COUNT then
				return false, string.format("%d/%d마리", n, FusionRules.INPUT_COUNT)
			end
			return true, nil
		end,
		ready = function(selected: { PetPicker.Item }): (boolean, string?)
			-- 서버와 같은 규칙으로 미리 확인 (보너스 없이). 진짜 결과는 서버가 정함.
			local _, err = FusionRules.fuse(toRecords(selected), function(): number
				return 0.999
			end)
			if err then
				return false, FusionRules.errorText(err :: FusionRules.FusionError)
			end
			return true, nil
		end,
		status = function(selected: { PetPicker.Item }): string?
			if #selected == 0 then
				return nil
			end
			return candidateText(selected[1].petId)
		end,
		onConfirm = function(selected: { PetPicker.Item })
			Net.send(Remotes.ToServer.FuseRequest, selected[1].uid, selected[2].uid, selected[3].uid)
		end,
		closeWhen = function(): boolean
			local root = myRoot()
			return machine.Parent == nil
				or WorldPrompt.distanceTo(machine, if root then root.Position else nil) > Config.FUSION_RADIUS + 4
		end,
	})
end

-- 머신 유리통(Tube1~3) 차례로 번쩍 + 가운데(Core)로 빛 모으기
local function playFusionFx(machine: BasePart)
	local model = machine.Parent
	local core = if model then model:FindFirstChild("Core") else nil
	local center = if core and core:IsA("BasePart")
		then core.Position
		else machine.Position + Vector3.new(0, machine.Size.Y / 2 + 3, 0)
	SoundController.play("FusionCharge")
	if model then
		for i = 1, 3 do
			local tube = model:FindFirstChild("Tube" .. i)
			if tube and tube:IsA("BasePart") then
				local original = tube.Color
				task.delay((i - 1) * 0.25, function()
					tube.Color = Color3.new(1, 1, 1)
					TweenService:Create(tube, TweenInfo.new(0.6), { Color = original }):Play()
					Fx.burst(tube.Position, GLOW, 12, 0.6, 5)
				end)
			end
		end
	end
	Fx.gather(center, GLOW, 1.2, 8)
	task.delay(1.2, function()
		Fx.flash(center, GLOW, 30, 0.8)
		Fx.pillar(center, Color3.fromRGB(255, 200, 255), 40, 1.4)
	end)
end

function FusionController.start()
	local player = Players.LocalPlayer
	local handle = WorldPrompt.attach({
		tag = Tags.FusionMachine,
		name = "FusionPrompt",
		action = "퓨전",
		object = "퓨전 머신",
		distance = 10,
		enabled = isMine,
		onTrigger = function(part: BasePart)
			if isMine(part) then
				openPicker(part)
			else
				NotifyController.toast("내 베이스의 퓨전 머신만 쓸 수 있어요", "error")
			end
		end,
	})
	machines = handle
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.PlotIndex):Connect(handle.refresh)

	Net.on(Remotes.ToClient.FusionResult, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local machine = myMachine()
		if machine then
			playFusionFx(machine)
		end
	end)
end

return FusionController
