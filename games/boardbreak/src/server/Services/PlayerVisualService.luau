--!strict
--[[
	PlayerVisualService — 플레이어 겉모습 (선임). 서버에서 바꿔서 모두에게 보임. Main.server 가 "*VisualService" 를 자동으로 시작.

	1) 몸 크기 · 근육 (사장님 결정 13번) — 플레이어 Attr BodyScale (수석 SizeService, Sizes.quantize 로 2% 단위) · Muscle (0~1, 0.05 단위)
	   R15: Humanoid 안의 NumberValue 4개로 키움 (공식 문서 Humanoid: "BodyDepthScale · BodyHeightScale · BodyWidthScale · HeadScale"
	        NumberValue 를 바꾸면 AutomaticScalingEnabled 가 켜져 있을 때 몸 부위와 액세서리가 같이 커짐 → 옷·액세서리·얼굴은 그 사람 것 그대로)
	        키 = 그 사람 원래 값 × BodyScale
	        너비 = 원래 × BodyScale × (1 + WIDTH_GAIN × 근육)   — 어깨·가슴·팔다리가 굵어짐
	        깊이 = 원래 × BodyScale × (1 + DEPTH_GAIN × 근육)   — 가슴·팔다리 두께
	        머리 = 원래 × BodyScale × (1 − HEAD_SHRINK × 근육)  — 머리는 몸보다 덜 커짐 (몸이 우람해 보임)
	        원래 값 = Humanoid Attr "Base<이름>": 처음(아직 안 씀) 읽은 값. 그 뒤로는 값이 내가 마지막에 쓴 값(Attr "Wrote<이름>")과
	        다를 때만 (아바타 로딩이 덮어씀) 그 값을 새 원래 값으로 → 몇 번·어떤 순서로 불려도 "원래 × 배율" 이 한 번만.
	        값이 실제로 바뀔 때만 씀 (깜빡임 없음). 남이 값을 바꾸면 (watchScaleValues — Changed) 한 번 다시 맞춤.
	        엉덩이 높이(HipHeight)는 자동 크기 조절이 다시 계산함.
	   R6 (NumberValue 가 안 먹음): Model:ScaleTo(BodyScale) — 근육 모양은 없음.
	   캐릭터 Attr VisualScale · VisualMuscle = 지금 적용한 값 (클라 카메라·손 아령·글 높이가 읽음).
	   Humanoid NameDisplayDistance · HealthDisplayDistance = 100 × 몸 배율 (큰 월드에서도 이름이 보이게).
	2) 아우라 — 힘(Attr Power)이 바뀌어 아우라 단계(shared/Data/Visuals.auraTier)가 달라졌을 때만 갈아 끼움.
	   HumanoidRootPart 아래: Attachment "AuraAttach" + ParticleEmitter "AuraSparks"(기본 모양, 위로 올라가는 빛 알갱이)
	     + PointLight "AuraLight" · 발밑 고리 Part "AuraRing"(얇은 원판, 뿌리에 Weld, 안 부딪힘). 캐릭터 Attr AuraTier.
	   몸 배율이 바뀌면 다시 만들지 않고 크기·속도·고리 자리만 그 배율로 맞춤 (fitAura).
	3) 충돌 그룹: 캐릭터 파트 = Groups.PLAYER (도장 지붕·문 위 들보 = PASS_GROUP 과 안 부딪힘 → 거인이 작은 월드에서 안 끼임)
	손에 든 아령은 각 클라가 그림 (TrainController — 클라에서 만든 파트라 서버가 키울 수 없음): BodyScale × Sizes.dumbbellScale(level).
	외부 텍스처 id 없음. 저사양 설정이면 클라(AuraController)가 남의 파티클을 자기 화면에서 끔.
	공개 (테스트): apply(character, power) → 단계 · applyBody(character, scale, muscle) → 적용한 배율 · bodyShape(scale, muscle)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Visuals = require(Shared.Data.Visuals)
local Sizes = require(Shared.Data.Sizes)
local Tags = require(Shared.Tags)
local Groups = require(script.Parent.Parent.Map.Groups)

local PlayerVisualService = {}

local POWER = Tags.PlayerAttributes.Power
local BODY = Tags.PlayerAttributes.BodyScale or "BodyScale"
local MUSCLE = Tags.PlayerAttributes.Muscle or "Muscle"

PlayerVisualService.WIDTH_GAIN = 0.45
PlayerVisualService.DEPTH_GAIN = 0.55
PlayerVisualService.HEAD_SHRINK = 0.25
PlayerVisualService.SCALE_VALUES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }

------------------------------------------------------------------
-- 몸 크기 · 근육
------------------------------------------------------------------

export type Shape = { height: number, width: number, depth: number, head: number }

-- 배율·근육 → 4개 값에 곱할 배율
function PlayerVisualService.bodyShape(scale: number, muscle: number): Shape
	local s = math.clamp(tonumber(scale) or 1, 1, Sizes.MAX_SCALE)
	local m = math.clamp(tonumber(muscle) or 0, 0, 1)
	return {
		height = s,
		width = s * (1 + PlayerVisualService.WIDTH_GAIN * m),
		depth = s * (1 + PlayerVisualService.DEPTH_GAIN * m),
		head = s * (1 - PlayerVisualService.HEAD_SHRINK * m),
	}
end

local function numberValue(humanoid: Humanoid, name: string): NumberValue
	local v = humanoid:FindFirstChild(name)
	if v and v:IsA("NumberValue") then
		return v
	end
	local made = Instance.new("NumberValue")
	made.Name = name
	made.Value = 1
	made.Parent = humanoid
	return made
end

local function isR6(humanoid: Humanoid): boolean
	local ok, r6 = pcall(function(): boolean
		return humanoid.RigType == Enum.HumanoidRigType.R6
	end)
	return ok and r6
end

-- 몸을 scale 배 · 근육 muscle 로 (바뀐 값만 씀). 적용한 배율을 돌려줌
function PlayerVisualService.applyBody(character: Model?, scale: number?, muscle: number?): number
	if not character then
		return 1
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return 1
	end
	local shape = PlayerVisualService.bodyShape(scale or 1, muscle or 0)
	if isR6(humanoid) then
		if character:GetAttribute("VisualScale") ~= shape.height then
			pcall(function()
				(character :: any):ScaleTo(shape.height)
			end)
		end
	else
		pcall(function()
			humanoid.AutomaticScalingEnabled = true
		end)
		local wants = {
			BodyHeightScale = shape.height,
			BodyWidthScale = shape.width,
			BodyDepthScale = shape.depth,
			HeadScale = shape.head,
		}
		-- 원래 값(Base<이름>) 정하기 — 언제·몇 번 불려도 "원래 × 배율" 이 딱 한 번만 (본부장 2026-11-16 스튜디오:
		--   리스폰 뒤 키 10.98² = 120.6 — 옛 코드는 아바타 로딩 뒤 Base 를 지우고 "지금 값" 을 다시 읽었는데, 그 값이 이미
		--   내가 키운 값이라 두 번 곱해짐).
		--   규칙: 처음 (아직 한 번도 안 씀) → 지금 값이 원래 값. 그 뒤로는 지금 값이 "내가 마지막에 쓴 값(Wrote<이름>)" 과
		--   다를 때만 남(아바타 로딩)이 바꾼 것 → 그 값을 새 원래 값으로. 같으면 원래 값 그대로.
		--   쓰기 전에 Wrote 를 먼저 적어서 Changed 를 듣는 쪽이 내 쓰기를 남의 쓰기로 착각하지 않게 함.
		for _, name in PlayerVisualService.SCALE_VALUES do
			local v = numberValue(humanoid, name)
			local baseKey, wroteKey = "Base" .. name, "Wrote" .. name
			local base = humanoid:GetAttribute(baseKey)
			local wrote = humanoid:GetAttribute(wroteKey)
			local now = if v.Value > 0 then v.Value else 1
			if type(base) ~= "number" or (type(wrote) == "number" and math.abs(now - wrote) > 1e-4) then
				base = now
				humanoid:SetAttribute(baseKey, base)
			end
			local want = (base :: number) * wants[name]
			humanoid:SetAttribute(wroteKey, want)
			if math.abs(v.Value - want) > 1e-4 then
				v.Value = want
			end
		end
	end
	pcall(function()
		humanoid.NameDisplayDistance = 100 * shape.height
		humanoid.HealthDisplayDistance = 100 * shape.height
	end)
	character:SetAttribute("VisualScale", shape.height)
	character:SetAttribute("VisualMuscle", muscle or 0)
	return shape.height
end

------------------------------------------------------------------
-- 아우라
------------------------------------------------------------------

local function clearAura(root: BasePart)
	for _, name in { "AuraAttach", "AuraLight" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local character = root.Parent
	local ring = character and character:FindFirstChild("AuraRing")
	if ring then
		ring:Destroy()
	end
end

local function visualScale(character: Model): number
	local s = character:GetAttribute("VisualScale")
	return if type(s) == "number" and s > 0 then s else 1
end

-- 배율 1 일 때 숫자를 기억해 둔 기본 키 (캐릭터 Attr: 처음 붙일 때 그 순간 몸 → 배율로 나눔)
local function baseBody(character: Model, root: BasePart): (number, number)
	local hip0 = character:GetAttribute("BaseHip")
	local root0 = character:GetAttribute("BaseRootY")
	if type(hip0) == "number" and type(root0) == "number" then
		return hip0, root0
	end
	local s = visualScale(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	local hip = (if hum and hum.HipHeight > 0 then hum.HipHeight else 2 * s) / s
	local ry = root.Size.Y / s
	character:SetAttribute("BaseHip", hip)
	character:SetAttribute("BaseRootY", ry)
	return hip, ry
end
PlayerVisualService.rememberBase = baseBody

-- 이미 붙은 아우라를 몸 배율에 맞춤 (다시 만들지 않음 — 파티클이 끊기지 않음)
local function fitAura(character: Model, root: BasePart, tier: number)
	local a = Visuals.aura(tier)
	if not a then
		return
	end
	local s = visualScale(character)
	local hip, ry = baseBody(character, root)
	local attach = root:FindFirstChild("AuraAttach")
	if attach and attach:IsA("Attachment") then
		attach.Position = Vector3.new(0, -1.5 * s, 0)
		local sparks = attach:FindFirstChild("AuraSparks")
		if sparks and sparks:IsA("ParticleEmitter") then
			sparks.Speed = NumberRange.new(2 * s, (4 + tier * 0.4) * s)
			sparks.Acceleration = Vector3.new(0, 2 * s, 0)
			sparks.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, math.min(a.size * s, 10)),
				NumberSequenceKeypoint.new(1, 0),
			})
		end
	end
	local light = root:FindFirstChild("AuraLight")
	if light and light:IsA("PointLight") then
		light.Range = math.min(Groups.LIGHT_RANGE_MAX, (8 + tier) * s)
	end
	local ring = character:FindFirstChild("AuraRing")
	if ring and ring:IsA("BasePart") then
		local d = (4 + tier * 0.2) * s
		ring.Size = Vector3.new(0.1 * math.max(1, s * 0.5), d, d)
		local offset = CFrame.new(0, -(hip + ry / 2) * s + 0.08 * s, 0) * CFrame.Angles(0, 0, math.pi / 2)
		local weld = ring:FindFirstChildOfClass("Weld")
		if weld then
			weld.C0 = offset
		end
	end
	character:SetAttribute("AuraScale", s)
end

function PlayerVisualService.apply(character: Model?, power: number?): number
	if not character then
		return 0
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return 0
	end
	local tier = Visuals.auraTier(power)
	local had = character:GetAttribute("AuraTier")
	if had == tier and (tier == 0 or root:FindFirstChild("AuraAttach")) then
		-- 단계가 그대로면 다시 만들지 않음 (몸 배율만 바뀌었으면 크기만 맞춤)
		if tier > 0 and character:GetAttribute("AuraScale") ~= visualScale(character) then
			fitAura(character, root, tier)
		end
		return tier
	end
	clearAura(root)
	character:SetAttribute("AuraTier", tier)
	local a = Visuals.aura(tier)
	if not a then
		return tier
	end
	local attach = Instance.new("Attachment")
	attach.Name = "AuraAttach"
	attach.Position = Vector3.new(0, -1.5, 0)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "AuraSparks"
	sparks.Rate = math.min(a.rate, Visuals.AURA_RATE_CAP)
	sparks.Lifetime = NumberRange.new(0.8, 1.4)
	sparks.Speed = NumberRange.new(2, 4 + tier * 0.4)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.Acceleration = Vector3.new(0, 2, 0)
	sparks.LightEmission = 0.8
	sparks.LightInfluence = 0
	sparks.Color = ColorSequence.new(a.color, a.color2)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, a.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Parent = attach
	attach.Parent = root
	if a.light > 0 then
		local light = Instance.new("PointLight")
		light.Name = "AuraLight"
		light.Color = a.color
		light.Range = 8 + tier
		light.Brightness = a.light
		light.Shadows = false
		light.Parent = root
	end
	-- 발밑 고리
	local hum = character:FindFirstChildOfClass("Humanoid")
	local hip = if hum and hum.HipHeight > 0 then hum.HipHeight else 2
	local ring = Instance.new("Part")
	ring.Name = "AuraRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, 4 + tier * 0.2, 4 + tier * 0.2)
	ring.Color = a.color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.6
	ring.Anchored = false
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Massless = true
	local offset = CFrame.new(0, -(hip + root.Size.Y / 2) + 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2)
	ring.CFrame = root.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = ring
	weld.C0 = offset
	weld.Parent = ring
	ring.Parent = character
	character:SetAttribute("AuraScale", 1)
	if visualScale(character) ~= 1 then
		fitAura(character, root, tier)
	end
	return tier
end

------------------------------------------------------------------
-- 충돌 그룹
------------------------------------------------------------------

local function setGroup(part: Instance)
	if part:IsA("BasePart") then
		pcall(function()
			part.CollisionGroup = Groups.PLAYER
		end)
	end
end

------------------------------------------------------------------

-- 크기 값 4개를 "나 말고 누가" 바꾸면 (아바타 로딩이 늦게 덮어씀) 한 번 다시 맞춤. 내가 쓴 값(Wrote<이름>)과 같으면 무시.
--   연결은 Humanoid·NumberValue 에 붙어서 몸이 없어지면 같이 끊김
function PlayerVisualService.watchScaleValues(character: Model, onChange: () -> ())
	local pending = false
	local function hookValue(humanoid: Humanoid, v: Instance)
		if not (v:IsA("NumberValue") and table.find(PlayerVisualService.SCALE_VALUES, v.Name)) then
			return
		end
		pcall(function()
			v.Changed:Connect(function()
				local wrote = humanoid:GetAttribute("Wrote" .. v.Name)
				if type(wrote) == "number" and math.abs(v.Value - wrote) <= 1e-4 then
					return -- 내가 쓴 것
				end
				if not pending then
					pending = true
					task.defer(function()
						pending = false
						onChange()
					end)
				end
			end)
		end)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local hum = humanoid :: Humanoid
	for _, v in hum:GetChildren() do
		hookValue(hum, v)
	end
	pcall(function()
		hum.ChildAdded:Connect(function(v: Instance)
			hookValue(hum, v)
		end)
	end)
end

local connections: { [Player]: { RBXScriptConnection } } = {} -- 나갈 때 끊음 (B-5)

local function unwatch(player: Player)
	local list = connections[player]
	connections[player] = nil
	if list then
		for _, c in list do
			c:Disconnect()
		end
	end
end

local function watch(player: Player)
	unwatch(player) -- 두 번 불려도 연결은 하나씩만
	local function refresh()
		local character = player.Character
		if not character then
			return
		end
		-- 키우기 전에 배율 1 몸 숫자(엉덩이 높이·뿌리 키)를 한 번 기억 (아우라 고리 자리에 씀)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			PlayerVisualService.rememberBase(character, root)
		end
		-- 몸 먼저 (아우라 크기가 몸 배율을 읽음)
		local scale = tonumber(player:GetAttribute(BODY)) or 1
		local muscle = tonumber(player:GetAttribute(MUSCLE)) or 0
		PlayerVisualService.applyBody(character, scale, muscle)
		PlayerVisualService.apply(character, player:GetAttribute(POWER) :: number?)
	end
	local list = {
		player.CharacterAdded:Connect(function(character: Model)
			character:WaitForChild("HumanoidRootPart", 10)
			character:SetAttribute("AuraTier", nil)
			for _, d in character:GetDescendants() do
				setGroup(d)
			end
			pcall(function()
				character.DescendantAdded:Connect(setGroup) -- 액세서리·늦게 들어온 부위도 (몸이 없어지면 같이 끊김)
			end)
			refresh()
			PlayerVisualService.watchScaleValues(character, function()
				if player.Character == character then
					refresh()
				end
			end)
		end),
		player:GetAttributeChangedSignal(POWER):Connect(refresh),
		player:GetAttributeChangedSignal(BODY):Connect(refresh),
		player:GetAttributeChangedSignal(MUSCLE):Connect(refresh),
	}
	-- 아바타 모양이 늦게 들어오면 (HumanoidDescription 적용) 크기 값 4개가 그 사람 원래 값으로 바뀔 수 있음 → 다시 맞춤.
	--   아무것도 지우지 않음: applyBody 가 "내가 마지막에 쓴 값과 다르면 남이 바꾼 것" 으로 원래 값을 정함 (두 번 곱하지 않음)
	pcall(function()
		table.insert(
			list,
			(player :: any).CharacterAppearanceLoaded:Connect(function(character: Model)
				if player.Character == character then
					refresh()
				end
			end)
		)
	end)
	connections[player] = list
	if player.Character then
		for _, d in player.Character:GetDescendants() do
			setGroup(d)
		end
		refresh()
	end
end

-- 테스트용: 플레이어 하나를 지켜보기 시작 / 그만 (start 가 PlayerAdded 마다 부르는 것과 같음)
PlayerVisualService.watch = watch
PlayerVisualService.unwatch = unwatch

function PlayerVisualService.start()
	Groups.register()
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(unwatch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
end

return PlayerVisualService
