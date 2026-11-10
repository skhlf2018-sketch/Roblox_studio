--!strict
--[[
	판정은 전부 서버 (FruitService · PetService.petPet). 여기는 내 화면의 프롬프트와 연출만.

	- 내 정원 파트(Attr OwnerUserId == 나)에만 클라 ProximityPrompt (Attachment "GardenPromptAttach", 높이 = Attr VisualHeight 의 60%,
	  8판 추가: 최대 Config.PLANT_PROMPT_MAX_HEIGHT 7 — GardenRules.promptHeight):
	    성체 식물(GardenPlant): "PickFruitPrompt" 열매 따기 (E, 열매 0개면 꺼짐) → PickFruit(PlantUid)
	  남의 정원 파트에는 프롬프트를 안 만듦 (서버가 어차피 거절).
	  파트가 없어지면(태그 빠짐·Destroying) 연결·프롬프트 정리 (5판 B-3 처럼 연결이 쌓이지 않게 파트마다 한 번만).
	  uid 는 사람마다 따로 매겨서 겹칠 수 있으니 파트 Attr OwnerUserId == ownerUserId 로 한 번 더 거름 (REMOTES 1장)
	- 9판 (2026-11-10): 열매 먹이기 결과 연출(FeedResult "냠냠")은 먹이기 기능과 함께 삭제.
	공개: PetFxController.findPlant(ownerUserId, uid) · hookPart(part) · hookedCount() (테스트도 씀)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GardenRules = require(Shared.GardenRules)
local Pets = require(Shared.Data.Pets)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)

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
	-- 8판 추가: 키의 60%, 단 Config.PLANT_PROMPT_MAX_HEIGHT 까지 (거대 식물·울트라디바인도 손이 닿게)
	h.attach.Position = Vector3.new(0, -part.Size.Y / 2 + math.max(1, GardenRules.promptHeight(heightOf(part), 0.6)), 0)
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
end

return PetFxController
