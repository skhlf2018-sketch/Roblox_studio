--!strict
--[[
	WorldPrompt — 태그 붙은 월드 물건에 클라 전용 ProximityPrompt 붙이기 (사쿠라 나무·판매 가판대·트레일 상점 등)

	  local handle = WorldPrompt.attach({
	      tag = Tags.SellStall, name = "SellFruitsPrompt", action = "열매 팔기", object = "열매 12개",
	      key = Enum.KeyCode.F, hold = 0.2,   -- (없으면 E, 0초)
	      enabled = function(part) return 내 베이스인가 end,
	      onTrigger = function(part) 창 열기 end,
	  })
	  handle.refresh()        -- enabled/action 다시 계산 (Attribute 가 바뀌었을 때)
	  handle.parts()          -- 지금 붙어 있는 파트 목록

	8판 (사장님 2026-11-08 "글자가 겹쳐 안 보여요"): 한 물건에 프롬프트가 둘 이상이면 같은 자리에 겹쳐 그려짐.
	  spec.slot (1, 2, …) 을 주면 그 칸 전용 Attachment "PromptSlot<n>" 에 붙임:
	    · 높이 = baseY + (칸 - 1) × SLOT_STEP (칸마다 다름 → 위로 조금씩 올라감)
	    · 화면에서는 켜진 프롬프트끼리 옆으로 나란히 (UIOffset X = 글자 폭으로 계산, 가운데 정렬)
	  다른 컨트롤러가 같은 파트에 붙인 것도 칸 번호로 함께 정렬 (예: 가판대 E 열매 팔기 = 1칸, F 식물 팔기 = 2칸).
	  직접 만든 프롬프트는 WorldPrompt.stack(part, prompt, slot) · 켜고 끈 뒤 WorldPrompt.relayout(part).

	프롬프트는 내 화면에서만 보이고, 누르면 창만 엽니다. 실제 요청 검사(거리 등)는 전부 서버가 다시 함.
	태그가 Model 에 붙어 있으면 PrimaryPart(없으면 첫 BasePart)에 붙임 (서버 Landmarks 와 같은 규칙).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local WorldPrompt = {}

export type Spec = {
	tag: string,
	name: string,
	action: string | (BasePart) -> string,
	object: string | (BasePart) -> string,
	distance: number?,
	enabled: ((BasePart) -> boolean)?,
	key: Enum.KeyCode?, -- 기본 E (한 물건에 프롬프트가 둘이면 키를 다르게)
	hold: number?, -- 누르고 있는 시간 (기본 0)
	slot: number?, -- 8판: 한 파트에 프롬프트가 여럿이면 칸 번호 (없으면 파트에 바로 = 칸 없음)
	onTrigger: (BasePart) -> (),
}

export type Handle = {
	refresh: () -> (),
	parts: () -> { BasePart },
}

local function resolve(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function textOf(value: string | (BasePart) -> string, part: BasePart): string
	if typeof(value) == "function" then
		return value(part)
	end
	return value :: string
end

------------------------------------------------------------------
-- 8판: 한 파트의 프롬프트 칸 (안 겹치게)
------------------------------------------------------------------

WorldPrompt.SLOT_STEP = 1.2 -- 칸 사이 높이 (스터드)
WorldPrompt.SLOT_GAP = 10 -- 나란히 놓인 프롬프트 사이 화면 간격 (px)
local MAX_SLOTS = 4

-- 파트 → 칸 번호 → 프롬프트 (파트가 없어지면 저절로 빠짐)
local stacks: { [BasePart]: { [number]: ProximityPrompt } } = setmetatable({}, { __mode = "k" }) :: any

local function textWidth(text: string, size: number): number
	local ok, measured = pcall(function(): number
		local TextService = game:GetService("TextService")
		return TextService:GetTextSize(text, size, Enum.Font.GothamMedium, Vector2.new(1000, 1000)).X
	end)
	if ok and typeof(measured) == "number" and measured > 0 then
		return measured
	end
	-- 잴 수 없으면 대충: 한글 = 글자 크기, 영어·숫자 = 0.55배
	local width = 0
	local okCodes = pcall(function()
		for _, code in utf8.codes(text) do
			width += if code > 127 then size else size * 0.55
		end
	end)
	return if okCodes then width else #text * size * 0.55
end

-- 기본 프롬프트 화면 폭 (로블록스 기본 모양과 같은 계산: 글자 폭 + 키 그림 72 + 여백 24)
function WorldPrompt.promptWidth(prompt: ProximityPrompt): number
	if prompt.ActionText == "" and prompt.ObjectText == "" then
		return 72
	end
	return math.max(textWidth(prompt.ActionText, 19), textWidth(prompt.ObjectText, 14)) + 96
end

-- 켜진 프롬프트끼리 옆으로 나란히 (칸 순서대로 왼쪽 → 오른쪽). 하나뿐이면 가운데
function WorldPrompt.relayout(part: BasePart)
	local group = stacks[part]
	if not group then
		return
	end
	local shown: { ProximityPrompt } = {}
	local widths: { number } = {}
	local total = 0
	for slot = 1, MAX_SLOTS do
		local prompt = group[slot]
		if prompt then
			if prompt.Parent == nil then
				group[slot] = nil
			elseif prompt.Enabled then
				local w = WorldPrompt.promptWidth(prompt)
				table.insert(shown, prompt)
				table.insert(widths, w)
				total += w
			else
				prompt.UIOffset = Vector2.new(0, 0)
			end
		end
	end
	if next(group) == nil then
		stacks[part] = nil
		return
	end
	total += WorldPrompt.SLOT_GAP * math.max(0, #shown - 1)
	local left = -total / 2
	for i, prompt in shown do
		prompt.UIOffset = Vector2.new(math.floor(left + widths[i] / 2 + 0.5), 0)
		left += widths[i] + WorldPrompt.SLOT_GAP
	end
end

-- 프롬프트를 파트의 칸 Attachment 에 붙임 (baseY = 1칸 높이, 파트 가운데 기준)
function WorldPrompt.stack(part: BasePart, prompt: ProximityPrompt, slot: number, baseY: number?): Attachment
	local index = math.clamp(math.floor(slot), 1, MAX_SLOTS)
	local name = "PromptSlot" .. index
	local found = part:FindFirstChild(name)
	local attach: Attachment
	if found and found:IsA("Attachment") then
		attach = found
	else
		attach = Instance.new("Attachment")
		attach.Name = name
		attach.Parent = part
	end
	attach.Position = Vector3.new(0, (baseY or 0) + (index - 1) * WorldPrompt.SLOT_STEP, 0)
	prompt.Parent = attach
	local group = stacks[part]
	if not group then
		group = {}
		stacks[part] = group
	end
	group[index] = prompt
	WorldPrompt.relayout(part)
	return attach
end

function WorldPrompt.attach(spec: Spec): Handle
	local prompts: { [BasePart]: ProximityPrompt } = {}

	local function apply(part: BasePart, prompt: ProximityPrompt)
		prompt.ActionText = textOf(spec.action, part)
		prompt.ObjectText = textOf(spec.object, part)
		local enabled = spec.enabled
		prompt.Enabled = if enabled then enabled(part) else true
		if spec.slot then
			WorldPrompt.relayout(part)
		end
	end

	local function add(inst: Instance)
		local part = resolve(inst)
		if not part or prompts[part] or not part:IsDescendantOf(Workspace) then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = spec.name
		prompt.KeyboardKeyCode = spec.key or Enum.KeyCode.E
		prompt.HoldDuration = spec.hold or 0
		prompt.MaxActivationDistance = spec.distance or 10
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Triggered:Connect(function()
			spec.onTrigger(part)
		end)
		local slot = spec.slot
		if slot then
			WorldPrompt.stack(part, prompt, slot)
		else
			prompt.Parent = part
		end
		apply(part, prompt)
		prompts[part] = prompt
	end

	for _, inst in CollectionService:GetTagged(spec.tag) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(spec.tag):Connect(function(inst: Instance)
		task.defer(add, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(spec.tag):Connect(function(inst: Instance)
		local part = resolve(inst)
		local prompt = if part then prompts[part] else nil
		if part and prompt then
			prompt:Destroy()
			prompts[part] = nil
		end
	end)

	return {
		refresh = function()
			for part, prompt in prompts do
				if part.Parent == nil then
					prompts[part] = nil
				else
					apply(part, prompt)
				end
			end
		end,
		parts = function(): { BasePart }
			local list: { BasePart } = {}
			for part in prompts do
				if part.Parent ~= nil then
					table.insert(list, part)
				end
			end
			return list
		end,
	}
end

-- 내 캐릭터와 파트 상자 표면 사이 거리 (서버 Landmarks.distanceToPart 와 같은 계산, 없으면 math.huge)
function WorldPrompt.distanceTo(part: BasePart, position: Vector3?): number
	if not position then
		return math.huge
	end
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	return (localPos - clamped).Magnitude
end

return WorldPrompt
