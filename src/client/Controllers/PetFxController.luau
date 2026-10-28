--!strict
--[[
	판정은 전부 서버 (FruitService · PetService.petPet). 여기는 내 화면의 프롬프트와 연출만.

	- 내 정원 파트(Attr OwnerUserId == 나)에만 클라 ProximityPrompt (Attachment "GardenPromptAttach", 높이 = Attr VisualHeight 의 60%):
	    성체 식물(GardenPlant): "PickFruitPrompt" 열매 따기 (E, 열매 0개면 꺼짐) → PickFruit(PlantUid)
	  남의 정원 파트에는 프롬프트를 안 만듦 (서버가 어차피 거절).
	  파트가 없어지면(태그 빠짐·Destroying) 연결·프롬프트 정리 (5판 B-3 처럼 연결이 쌓이지 않게 파트마다 한 번만).
	  uid 는 사람마다 따로 매겨서 겹칠 수 있으니 파트 Attr OwnerUserId == ownerUserId 로 한 번 더 거름 (REMOTES 1장)
	- FeedResult { plantUid, fruitId, mutation? }: 내 성체 위 — 붙으면 돌연변이 색(Visuals.mutationLooks) 반짝 + "황금!" / 아니면 "냠냠"
	공개: PetFxController.petted(ownerUserId, uid) · findPlant(ownerUserId, uid) · fed(payload) · hookPart(part) (테스트도 씀)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Mutations = require(Shared.Data.Mutations)
local Pets = require(Shared.Data.Pets)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Visuals = require(Shared.Data.Visuals)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Fx = require(Client.UI.Fx)

local PetFxController = {}

type Hooked = {
	attach: Attachment,
	pick: ProximityPrompt?,
	uid: string,
	conns: { RBXScriptConnection },
}
local hooked: { [BasePart]: Hooked } = {}

local function ownerOf(part: Instance): number?
	local owner = part:GetAttribute("OwnerUserId")
	return if typeof(owner) == "number" then owner else nil
end

local function uidOf(part: Instance): string?
	local uid = part:GetAttribute("PlantUid")
	if typeof(uid) ~= "string" then
		uid = part:GetAttribute("EggUid")
	end
	return if typeof(uid) == "string" then uid else nil
end

-- 모델 꼭대기 높이 (파트 바닥 기준). 겉모습이 아직 없으면 파트 높이
local function heightOf(part: BasePart): number
	local h = part:GetAttribute("VisualHeight")
	return if typeof(h) == "number" and h > 0 then h else part.Size.Y
end

-- 식물 꼭대기 월드 위치
local function topOf(part: BasePart): Vector3
	return part.Position + Vector3.new(0, -part.Size.Y / 2 + heightOf(part), 0)
end

local function plantName(part: BasePart): string
	local id = part:GetAttribute("PetId")
	local pet = if typeof(id) == "string" then Pets.get(id) else nil
	return if pet then pet.name else "식물"
end

-- 그 주인 정원의 그 성체/씨앗 파트
function PetFxController.findPlant(ownerUserId: number, uid: string): BasePart?
	for _, tag in { Tags.GardenPlant, Tags.IncubatingEgg } do
		for _, inst in CollectionService:GetTagged(tag) do
			if inst:IsA("BasePart") and uidOf(inst) == uid and ownerOf(inst) == ownerUserId then
				return inst
			end
		end
	end
	return nil
end

------------------------------------------------------------------
-- 프롬프트
------------------------------------------------------------------

local function newPrompt(
	name: string,
	action: string,
	key: Enum.KeyCode,
	hold: number,
	parent: Instance
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function refreshHooked(part: BasePart, h: Hooked)
	h.attach.Position = Vector3.new(0, -part.Size.Y / 2 + math.max(1, heightOf(part) * 0.6), 0)
	local objectText = plantName(part)
	local pick = h.pick
	if pick then
		local fruits = part:GetAttribute("Fruits")
		local n = if typeof(fruits) == "number" then fruits else 0
		pick.ObjectText = objectText
		pick.ActionText = string.format("열매 따기 (%d)", n)
		pick.Enabled = n > 0
	end
end

local function unhook(part: BasePart)
	local h = hooked[part]
	if not h then
		return
	end
	hooked[part] = nil
	for _, c in h.conns do
		c:Disconnect()
	end
	h.attach:Destroy()
end

-- 내 정원 파트에 프롬프트 (한 번만). 붙였으면 true
function PetFxController.hookPart(inst: Instance): boolean
	if not inst:IsA("BasePart") or hooked[inst] then
		return false
	end
	local part = inst
	local uid = uidOf(part)
	if not uid or ownerOf(part) ~= Players.LocalPlayer.UserId then
		return false
	end
	local isPlant = typeof(part:GetAttribute("PlantUid")) == "string"
	if not isPlant then
		return false -- 자라는 씨앗(IncubatingEgg)에는 프롬프트 없음 (사장님 2026-10-28: 씨앗 물 주기 없앰 — "집기"·"건너뛰기" 는 IncubatorController)
	end
	local attach = Instance.new("Attachment")
	attach.Name = "GardenPromptAttach"
	attach.Parent = part
	local pick: ProximityPrompt? = nil
	if isPlant then
		local p = newPrompt("PickFruitPrompt", "열매 따기", Enum.KeyCode.E, 0, attach)
		p.Triggered:Connect(function()
			Net.send(Remotes.ToServer.PickFruit, uid)
		end)
		pick = p
	end
	local h: Hooked = { attach = attach, pick = pick, uid = uid, conns = {} }
	hooked[part] = h
	local function refresh()
		if hooked[part] == h then
			refreshHooked(part, h)
		end
	end
	table.insert(h.conns, part:GetAttributeChangedSignal("Fruits"):Connect(refresh))
	table.insert(h.conns, part:GetAttributeChangedSignal("VisualHeight"):Connect(refresh))
	table.insert(
		h.conns,
		part.Destroying:Connect(function()
			unhook(part)
		end)
	)
	refreshHooked(part, h)
	return true
end

-- 지금 프롬프트를 붙인 파트 수 (테스트용)
function PetFxController.hookedCount(): number
	local n = 0
	for part in hooked do
		if part.Parent then
			n += 1
		end
	end
	return n
end

------------------------------------------------------------------
-- 물방울 연출
------------------------------------------------------------------

-- 식물 위 글자 한 번 ("황금!" / "냠냠")
local function popWord(part: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FeedPop"
	gui.Adornee = part
	gui.Size = UDim2.fromOffset(200, 60)
	local start = Vector3.new(0, -part.Size.Y / 2 + heightOf(part) + 2, 0)
	gui.StudsOffsetWorldSpace = start
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = part
	TweenService
		:Create(
			gui,
			TweenInfo.new(1.3, Enum.EasingStyle.Quad),
			{ StudsOffsetWorldSpace = start + Vector3.new(0, 4, 0) }
		)
		:Play()
	TweenService:Create(
		label,
		TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	task.delay(1.4, function()
		gui:Destroy()
	end)
end

-- 먹이기 결과 연출 (FeedResult). 내 식물을 찾았으면 true
function PetFxController.fed(payload: any): boolean
	if typeof(payload) ~= "table" or typeof(payload.plantUid) ~= "string" then
		return false
	end
	local part = PetFxController.findPlant(Players.LocalPlayer.UserId, payload.plantUid)
	if not part then
		return false
	end
	local mutationId = if typeof(payload.mutation) == "string" then payload.mutation else nil
	local m = if mutationId then Mutations.get(mutationId) else nil
	if m and mutationId then
		local look = Visuals.mutationLooks[mutationId]
		local c = if look then look.color else m.color
		local color = Color3.fromRGB(c[1], c[2], c[3])
		popWord(part, m.name .. "!", color)
		Fx.burst(topOf(part), color, 40, 1, 12)
		Fx.flash(topOf(part), color, 16, 0.8)
	else
		popWord(part, "냠냠", Color3.fromRGB(255, 235, 150))
		Fx.burst(topOf(part), Color3.fromRGB(255, 220, 120), 10, 0.5, 5)
	end
	return true
end

function PetFxController.start()
	for _, tag in { Tags.GardenPlant, Tags.IncubatingEgg } do
		for _, inst in CollectionService:GetTagged(tag) do
			PetFxController.hookPart(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst: Instance)
			-- Attribute 가 파트보다 조금 늦게 올 수 있어 한 번 미룸
			task.defer(PetFxController.hookPart, inst)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
			if inst:IsA("BasePart") then
				unhook(inst)
			end
		end)
	end
	Net.on(Remotes.ToClient.FeedResult, PetFxController.fed)
end

return PetFxController
