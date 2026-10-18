--!strict
--[[
	WorldPrompt — 태그 붙은 월드 물건에 클라 전용 ProximityPrompt 붙이기 (퓨전 머신·사쿠라·제단·비밀 통로)

	  local handle = WorldPrompt.attach({
	      tag = Tags.FusionMachine, name = "FusionPrompt", action = "퓨전", object = "퓨전 머신",
	      enabled = function(part) return 내 베이스인가 end,
	      onTrigger = function(part) 창 열기 end,
	  })
	  handle.refresh()        -- enabled/action 다시 계산 (Attribute 가 바뀌었을 때)
	  handle.parts()          -- 지금 붙어 있는 파트 목록

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

function WorldPrompt.attach(spec: Spec): Handle
	local prompts: { [BasePart]: ProximityPrompt } = {}

	local function apply(part: BasePart, prompt: ProximityPrompt)
		prompt.ActionText = textOf(spec.action, part)
		prompt.ObjectText = textOf(spec.object, part)
		local enabled = spec.enabled
		prompt.Enabled = if enabled then enabled(part) else true
	end

	local function add(inst: Instance)
		local part = resolve(inst)
		if not part or prompts[part] or not part:IsDescendantOf(Workspace) then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = spec.name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = spec.distance or 10
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Default
		apply(part, prompt)
		prompt.Triggered:Connect(function()
			spec.onTrigger(part)
		end)
		prompt.Parent = part
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
