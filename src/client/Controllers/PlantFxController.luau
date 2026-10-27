--!strict
--[[
	PlantFxController — 식물·씨앗 아우라 켜고 끄기 + 가까운 식물 살랑살랑 (6판, 선임). 내 화면에서만.

	- 아우라: 서버(PlantVisualService·EggVisualService)는 등급 아우라 파티클·빛을 Enabled = false 로 만들고 그 파트에 태그
	  Visuals.Tags.AuraFx 를 붙임. 여기서 0.5초마다 내 캐릭터에서 AURA_RANGE(100) 스터드 안인 파트 아래
	  ParticleEmitter·PointLight 만 켬 (멀면 끔). 하늘 빛기둥 Beam 은 서버가 늘 켜 둠 (안 건드림).
	  켜짐/꺼짐이 바뀔 때만 자식들을 훑고, 5초마다 한 번은 다시 맞춤 (돌연변이로 파티클이 새로 생긴 경우).
	- 살랑살랑: Attr Sway == true 인 모델 (정원 성체 = GardenPlant 의 자식 모델, 자라는 씨앗 "SeedVisual",
	  둥지 옆 장식 식물 ParentAnimal) 중 SWAY_RANGE(60) 안 것만 Root(PrimaryPart) 를 TweenService 로 ±3° 앞뒤로 기울임
	  (Reverse, 무한 반복). 멀어지거나 모델이 바뀌면 Cancel 하고 원래 CFrame 으로. 매 프레임 루프 없음 · Instance 안 만듦.
	공개: PlantFxController.step() (0.5초 한 번 — 테스트), auraOn(part), swaying(model), swayCount(), AURA_RANGE, SWAY_RANGE
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Tags)
local Visuals = require(Shared.Data.Visuals)

local PlantFxController = {}
PlantFxController.AURA_RANGE = 100
PlantFxController.SWAY_RANGE = 60

local VT = Visuals.Tags
local SWAY_DEG = 3
local RESYNC_EVERY = 10 -- step 10번(5초)마다 한 번 다시 맞춤

local auraParts: { [BasePart]: boolean } = {} -- 태그 붙은 파트 → 지금 켜졌나
local hosts: { [BasePart]: boolean } = {} -- 정원 파트 (GardenPlant / IncubatingEgg) — 자식 모델에 Sway
type Sway = { tween: Tween, root: BasePart, base: CFrame }
local sways: { [Model]: Sway } = {}
local stepCount = 0

local function myPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function setAura(part: BasePart, on: boolean)
	for _, d in part:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("PointLight") then
			local fx = d :: any -- 둘 다 Enabled 가 있음 (타입 검사기가 합친 타입의 속성을 못 읽어서)
			if fx.Enabled ~= on then
				fx.Enabled = on
			end
		end
	end
	auraParts[part] = on
end

function PlantFxController.auraOn(part: BasePart): boolean
	return auraParts[part] == true
end

local function stopSway(model: Model)
	local s = sways[model]
	if not s then
		return
	end
	sways[model] = nil
	s.tween:Cancel()
	if s.root.Parent then
		s.root.CFrame = s.base
	end
end

local function startSway(model: Model)
	if sways[model] then
		return
	end
	local root = model.PrimaryPart
	if not root then
		return
	end
	local base = root.CFrame
	local tilt = math.rad(SWAY_DEG)
	-- 모델마다 기울기 방향을 조금씩 다르게 (이름 길이로 — 해시까지는 필요 없음)
	local yaw = (#model.Name % 6) * math.pi / 3
	local info =
		TweenInfo.new(1.6 + (#model.Name % 5) * 0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(root, info, {
		CFrame = base * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0) * CFrame.Angles(0, -yaw, 0),
	})
	tween:Play()
	sways[model] = { tween = tween, root = root, base = base }
end

-- 지금 흔들리는 모델 수 (테스트용)
function PlantFxController.swayCount(): number
	local n = 0
	for _ in sways do
		n += 1
	end
	return n
end

function PlantFxController.swaying(model: Model): boolean
	return sways[model] ~= nil
end

-- 흔들 모델 후보: 정원 파트의 자식 모델(Sway) + 둥지 옆 장식 식물
local function swayModels(): { Model }
	local list: { Model } = {}
	for part in hosts do
		if part.Parent == nil then
			hosts[part] = nil
		else
			for _, child in part:GetChildren() do
				if child:IsA("Model") and child:GetAttribute("Sway") == true then
					table.insert(list, child)
				end
			end
		end
	end
	for _, inst in CollectionService:GetTagged(VT.ParentAnimal) do
		if inst:IsA("Model") and inst:GetAttribute("Sway") == true then
			table.insert(list, inst)
		end
	end
	return list
end

local function modelPosition(model: Model): Vector3?
	local root = model.PrimaryPart
	return if root then root.Position else nil
end

-- 0.5초 한 번: 아우라 켜고 끄기 + 흔들기 시작·멈춤
function PlantFxController.step()
	stepCount += 1
	local resync = stepCount % RESYNC_EVERY == 0
	local me = myPosition()
	for part, wasOn in auraParts do
		if part.Parent == nil then
			auraParts[part] = nil
		else
			local on = me ~= nil and (part.Position - me).Magnitude <= PlantFxController.AURA_RANGE
			if on ~= wasOn or resync then
				setAura(part, on)
			end
		end
	end
	local alive: { [Model]: boolean } = {}
	for _, model in swayModels() do
		local pos = modelPosition(model)
		local near = me ~= nil and pos ~= nil and (pos - me).Magnitude <= PlantFxController.SWAY_RANGE
		if near then
			alive[model] = true
			startSway(model)
		end
	end
	for model in sways do
		if not alive[model] or model.Parent == nil then
			stopSway(model)
		end
	end
end

local function addAura(inst: Instance)
	if inst:IsA("BasePart") and auraParts[inst] == nil then
		auraParts[inst] = false
		setAura(inst, false)
	end
end

local function addHost(inst: Instance)
	if inst:IsA("BasePart") then
		hosts[inst] = true
	end
end

function PlantFxController.start()
	for _, inst in CollectionService:GetTagged(VT.AuraFx) do
		addAura(inst)
	end
	CollectionService:GetInstanceAddedSignal(VT.AuraFx):Connect(addAura)
	CollectionService:GetInstanceRemovedSignal(VT.AuraFx):Connect(function(inst: Instance)
		if inst:IsA("BasePart") then
			auraParts[inst] = nil
		end
	end)
	for _, tag in { Tags.GardenPlant, Tags.IncubatingEgg } do
		for _, inst in CollectionService:GetTagged(tag) do
			addHost(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(addHost)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
			if inst:IsA("BasePart") then
				hosts[inst] = nil
			end
		end)
	end
	task.spawn(function()
		while true do
			PlantFxController.step()
			task.wait(0.5)
		end
	end)
end

return PlantFxController
