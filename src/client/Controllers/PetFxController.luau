--!strict
--[[
	PetFxController — 우리 펫 쓰다듬기 (5판, 사장님 지시). 내 화면 연출만, 판정은 서버 PetService.petPet.

	- 서버 PetVisualService 가 우리 펫(PenPet 태그 모델)마다 ProximityPrompt "PetPrompt"("쓰다듬기", 0.3초 누르기, F)를 붙여 둠.
	  · 내 펫(모델 Attr OwnerUserId == 나): 프롬프트를 켜고, 누르면 Net.send(PetPet, petUid)
	  · 남의 펫: 내 화면에서 프롬프트를 끔 (서버가 어차피 거절함)
	- PetPetted(ownerUserId, petUid) (서버 → 모두): 그 주인 우리의 그 펫 위에 하트 "♥" 팝업 + 분홍 반짝이 + 소리(Pet) + 폴짝
	  uid 는 사람마다 따로 매겨서(p1, p2 …) 겹칠 수 있으니 주인으로 한 번 더 거름:
	  모델 Attr OwnerUserId == ownerUserId, 없으면 주인 Player 의 Attr PlotIndex == MapLayout.plotAt(모델 자리) (REMOTES 6절)
	- 폴짝: 서버가 펫을 걷게 하며 Root 를 계속 옮기므로, 내 화면에서 "서버가 마지막으로 보낸 자리" 위로만 살짝 띄움
	  (서버가 새 자리를 보내면 그 자리를 기준으로 다시 계산 → 걷는 펫이 제자리로 끌려오지 않음)
	공개: PetFxController.petted(ownerUserId, petUid) (테스트도 씀), PetFxController.findPet(ownerUserId, petUid)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Visuals = require(Shared.Data.Visuals)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Fx = require(Client.UI.Fx)
local SoundController = require(script.Parent.SoundController)

local PetFxController = {}

local VT = Visuals.Tags
local PINK = Color3.fromRGB(255, 110, 170)
local HEART_COLORS = {
	Color3.fromRGB(255, 80, 130),
	Color3.fromRGB(255, 140, 190),
	Color3.fromRGB(255, 60, 90),
}
local HOP_TIME = 0.4
local SOUND_RANGE = 80 -- 남의 펫 쓰다듬기 소리는 이 거리 안에서만

type Hop = { model: Model, root: BasePart, start: number, height: number, base: CFrame, written: CFrame? }
local hops: { [Model]: Hop } = {}
local rng = Random.new()

local function ownerOf(model: Model): number?
	local owner = model:GetAttribute("OwnerUserId")
	return if typeof(owner) == "number" then owner else nil
end

local function rootOf(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	return if root and root:IsA("BasePart") then root else nil
end

local function heightOf(model: Model): number
	local h = model:GetAttribute("Height")
	return if typeof(h) == "number" then h else 3
end

-- 그 주인 우리의 그 펫 모델
function PetFxController.findPet(ownerUserId: number, petUid: string): Model?
	local ownerPlot: number? = nil
	local player = Players:GetPlayerByUserId(ownerUserId)
	if player then
		local plot = player:GetAttribute(Tags.PlayerAttributes.PlotIndex)
		ownerPlot = if typeof(plot) == "number" then plot else nil
	end
	for _, inst in CollectionService:GetTagged(VT.PenPet) do
		if inst:IsA("Model") and inst:GetAttribute("PetUid") == petUid then
			local owner = ownerOf(inst)
			if owner ~= nil then
				if owner == ownerUserId then
					return inst
				end
			elseif ownerPlot and MapLayout.plotAt(inst:GetPivot().Position) == ownerPlot then
				return inst
			end
		end
	end
	return nil
end

-- 하트 "♥" 몇 개가 펫 위로 떠오름
local function hearts(root: BasePart, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PetHearts"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(160, 140)
	gui.StudsOffset = Vector3.new(0, height + 1.5, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	for i = 1, 5 do
		local label = Instance.new("TextLabel")
		label.Name = "Heart" .. i
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromScale(0.2 + (i - 1) * 0.15, 1)
		label.Size = UDim2.fromOffset(44, 44)
		label.Font = Enum.Font.FredokaOne
		label.Text = "♥"
		label.TextScaled = true
		label.TextColor3 = HEART_COLORS[(i - 1) % #HEART_COLORS + 1]
		label.TextStrokeColor3 = Color3.fromRGB(120, 20, 60)
		label.TextStrokeTransparency = 0.2
		label.Rotation = rng:NextNumber(-20, 20)
		label.Parent = gui
		local rise = rng:NextNumber(0.55, 0.95)
		local info = TweenInfo.new(1 + i * 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(label, info, {
			Position = UDim2.fromScale(0.2 + (i - 1) * 0.15 + rng:NextNumber(-0.08, 0.08), 1 - rise),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end
	gui.Parent = root
	task.delay(1.6, function()
		gui:Destroy()
	end)
end

-- 펫 쓰다듬음 연출 (PetPetted)
function PetFxController.petted(ownerUserId: number, petUid: string): boolean
	local model = PetFxController.findPet(ownerUserId, petUid)
	local root = if model then rootOf(model) else nil
	if not model or not root then
		return false
	end
	local height = heightOf(model)
	hearts(root, height)
	Fx.burst(root.Position + Vector3.new(0, height * 0.7, 0), PINK, 14, 0.7, 7)
	-- 소리: 내 펫이면 늘, 남의 펫이면 가까울 때만
	local me = Players.LocalPlayer
	local character = me.Character
	local myRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local near = myRoot ~= nil and myRoot:IsA("BasePart") and (myRoot.Position - root.Position).Magnitude <= SOUND_RANGE
	if ownerUserId == me.UserId or near then
		SoundController.play("Pet")
	end
	hops[model] = {
		model = model,
		root = root,
		start = os.clock(),
		height = math.clamp(height * 0.45, 0.8, 2.5),
		base = root.CFrame,
		written = nil,
	}
	return true
end

-- 폴짝 한 프레임 (서버가 보낸 마지막 자리 위로)
local function stepHops()
	local now = os.clock()
	for model, hop in hops do
		if model.Parent == nil then
			hops[model] = nil
		else
			local current = hop.root.CFrame
			local written = hop.written
			if written == nil or (current.Position - written.Position).Magnitude > 1e-3 then
				hop.base = current -- 서버가 새 자리를 보냄 (걷는 중)
			end
			local t = (now - hop.start) / HOP_TIME
			if t >= 1 then
				model:PivotTo(hop.base)
				hops[model] = nil
			else
				local cf = hop.base + Vector3.new(0, math.sin(math.pi * t) * hop.height, 0)
				model:PivotTo(cf)
				hop.written = cf
			end
		end
	end
end

-- 우리 펫 프롬프트: 내 펫이면 켜고 PetPet, 남의 펫이면 끔
local hooked: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function hookPrompt(model: Model): boolean
	local prompt = model:FindFirstChild("PetPrompt", true)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return false
	end
	local mine = ownerOf(model) == Players.LocalPlayer.UserId
	prompt.Enabled = mine
	if mine and not hooked[prompt] then
		hooked[prompt] = true
		prompt.Triggered:Connect(function()
			local uid = model:GetAttribute("PetUid")
			if typeof(uid) == "string" then
				Net.send(Remotes.ToServer.PetPet, uid)
			end
		end)
	end
	return true
end

local function onPenPet(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local model = inst
	task.defer(function()
		-- 프롬프트가 모델보다 조금 늦게 복제될 수 있어 몇 번 더 찾아봄
		for _ = 1, 5 do
			if model.Parent == nil or hookPrompt(model) then
				return
			end
			task.wait(0.5)
		end
	end)
end
PetFxController.hookPrompt = hookPrompt

function PetFxController.start()
	for _, inst in CollectionService:GetTagged(VT.PenPet) do
		onPenPet(inst)
	end
	CollectionService:GetInstanceAddedSignal(VT.PenPet):Connect(onPenPet)
	Net.on(Remotes.ToClient.PetPetted, function(ownerUserId: any, petUid: any)
		if typeof(ownerUserId) == "number" and typeof(petUid) == "string" then
			PetFxController.petted(ownerUserId, petUid)
		end
	end)
	RunService.Heartbeat:Connect(stepHops)
end

return PetFxController
