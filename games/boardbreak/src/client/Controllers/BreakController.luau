--!strict
--[[
	BreakController — 물건 치기 (선임)
	  - 물건(태그 BreakTarget) 을 마우스로 누르거나 폰으로 탭 (모델의 ClickDetector "Click") → Hit(targetId)
	      멀리 있으면 그 물건 앞 길(MapLayout.roadPoint)로 걸어가서 침.
	  - 물건 가까이(MapLayout.targetReach 안)에 서면 큰 "치기" 버튼 (아래 가운데 / 터치 오른쪽). 누르고 있으면 초당 4번.
	  - 심사·대결 중(Attr Activity "exam"/"duel")에는 "치기" 버튼이 늘 보이고 Hit("exam"/"duel") 을 보냄.
	  - HitResult { targetId, damage, hp, hpMax, broken, reward?, reason? } 받으면 (내 화면에서만):
	      체력 막대 (물건 위, 4초 뒤 사라짐) · "-N" 숫자 · 흔들림 · 깨지면 조각 + "+💰N" 금색 숫자 + 잠깐 사라졌다 다시 톡
	      금 가는 연출 (Client/Cracks): 체력 75·50·25% 에서 금 1·2·3단계 (+ 작은 조각 · 흔들림), 깨지면/다시 생기면 지움.
	        마지막으로 안 체력을 기억해 두었다가 물건이 다시 연결되면(스트리밍) 같은 단계로 다시 그림.
	      힘 문턱 없음 — "힘이 부족해요" 글 없음. 물건 위 "💪 추천 힘 N" 은 내 치는 힘이 모자라면 주황색.
	      체력 막대에 남은 타격 수 어림 "약 N번".
  큰 월드 (사장님 결정 13번): 거리는 MapLayout (배율 곱한 값), 글 높이·조각 크기·흔들림 상한은 그 물건 월드 배율(scaleOf) 배.
	  물건 체력은 플레이어마다 따로라 서버는 모델을 안 바꿈 — 막대·깨짐은 전부 이 컨트롤러가 그림.
	공개: nearest() · hitTarget(id) · onHitResult(r) · button · models()
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local MapLayout = require(Shared.Data.MapLayout)
local Targets = require(Shared.Data.Targets)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Walk = require(Client.Walk)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local ActionButton = require(Client.UI.ActionButton)
local NotifyController = require(script.Parent.NotifyController)
local Cracks = require(Client.Cracks)
local BreakFx = require(Client.BreakFx)

local BreakController = {}
BreakController.button = nil :: ActionButton.Handle?
BreakController.HP_BAR_SECONDS = 4

local C = Theme.Colors
local PA = Tags.PartAttributes
local models: { [string]: Model } = {}
local hooked: { [Instance]: boolean } = {}
type HpBar = { gui: BillboardGui, fill: Frame, text: TextLabel, shownAt: number }
local hpBars: { [string]: HpBar } = {}
local homes: { [Model]: CFrame } = {}
local currentNearest: string? = nil
type Known = { hp: number, hpMax: number, damage: number }
local known: { [string]: Known } = {}
local lastHitAt = 0

local function popupGui(): Instance
	return Players.LocalPlayer:FindFirstChild("PlayerGui") or Workspace
end

local function hitboxOf(model: Model): BasePart?
	local p = model.PrimaryPart
	if p then
		return p
	end
	local h = model:FindFirstChild("Hitbox")
	return if h and h:IsA("BasePart") then h else nil
end

local function heightOf(model: Model): number
	local h = model:GetAttribute("Height")
	return if type(h) == "number" then h else 6
end

local function targetVector(id: string): Vector3?
	local p = MapLayout.targetPosition(id)
	return if p then Vector3.new(p.x, p.y, p.z) else nil
end

function BreakController.models(): { [string]: Model }
	return models
end

-- 물건이 있는 월드의 배율 (사장님 결정 13번 — 글 높이·조각 크기·흔들림이 월드 크기에 맞게). 모르면 1
function BreakController.scaleOf(model: Model): number
	local w = model:GetAttribute(PA.World)
	return if type(w) == "number" then MapLayout.worldScale(w) else 1
end

-- 지금 칠 수 있는 가장 가까운 물건 (지금 월드, reach 안). 없으면 nil
function BreakController.nearest(): string?
	local root = Walk.root()
	if not root then
		return nil
	end
	local world = State.currentWorld()
	local best: string? = nil
	local bestScore = math.huge
	for _, t in Targets.byWorld(world) do
		local pos = targetVector(t.id)
		if pos then
			local d = Walk.flatDistance(pos)
			local reach = MapLayout.targetReach(t.id)
			if d <= reach then
				local score = d / math.max(reach, 1)
				if score < bestScore then
					best, bestScore = t.id, score
				end
			end
		end
	end
	return best
end

local function activity(): string
	return State.activity()
end

-- 치기 한 번 (버튼·클릭 공통). 심사·대결 중이면 그 송판
function BreakController.fire()
	local act = activity()
	lastHitAt = os.clock()
	if act == "exam" then
		Net.send(Remotes.ToServer.Hit, Remotes.EXAM_TARGET)
		return
	elseif act == "duel" then
		Net.send(Remotes.ToServer.Hit, Remotes.DUEL_TARGET)
		return
	end
	local id = currentNearest or BreakController.nearest()
	if id then
		Net.send(Remotes.ToServer.Hit, id)
	end
end

-- 물건을 눌렀을 때: 가까우면 바로, 멀면 걸어가서
function BreakController.hitTarget(id: string)
	if activity() ~= "" then
		BreakController.fire()
		return
	end
	local target = Targets.get(id)
	local pos = targetVector(id)
	if not target or not pos then
		return
	end
	if target.world ~= State.currentWorld() then
		return
	end
	local reach = MapLayout.targetReach(id)
	if Walk.flatDistance(pos) <= reach then
		lastHitAt = os.clock()
		Net.send(Remotes.ToServer.Hit, id)
		return
	end
	local road = MapLayout.roadPoint(id)
	if not road then
		return
	end
	NotifyController.toast(target.name .. " 앞으로 이동", "info")
	Walk.to(Vector3.new(road.x, road.y, road.z), reach - MapLayout.worldScale(target.world), function()
		lastHitAt = os.clock()
		Net.send(Remotes.ToServer.Hit, id)
	end)
end

------------------------------------------------------------------
-- 연출 (내 화면에서만)
------------------------------------------------------------------

local function floatText(
	adornee: BasePart,
	offsetY: number,
	text: string,
	color: Color3,
	size: number,
	seconds: number,
	rise: number?
)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatText"
	gui.Size = UDim2.fromOffset(260, size + 14)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local label = Ui.label(text, UDim2.fromScale(1, 1), size, color, { Name = "Text", TextScaled = true, Parent = gui })
	gui.Parent = popupGui()
	Ui.tween(
		gui,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad),
		{ StudsOffsetWorldSpace = Vector3.new(0, offsetY + (rise or 3), 0) }
	)
	Ui.tween(label, TweenInfo.new(seconds), { TextTransparency = 1 })
	task.delay(seconds + 0.05, function()
		gui:Destroy()
	end)
end

local function hpBar(id: string, model: Model): HpBar?
	local entry = hpBars[id]
	if entry and entry.gui.Parent then
		return entry
	end
	local hitbox = hitboxOf(model)
	if not hitbox then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "HpBar_" .. id
	gui.Size = UDim2.fromOffset(210, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (heightOf(model) + 1) / 2 + BreakController.scaleOf(model), 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = hitbox
	local back: Frame = Ui.new("Frame", {
		Name = "Back",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.winDark,
		Parent = gui,
	})
	Ui.corner(8).Parent = back
	Ui.stroke(C.winEdge, 3).Parent = back
	local fill: Frame = Ui.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.green,
		Parent = back,
	})
	Ui.corner(8).Parent = fill
	local text =
		Ui.label("", UDim2.fromScale(1, 1), 18, C.white, { Name = "Hp", TextScaled = true, ZIndex = 2, Parent = back })
	gui.Parent = popupGui()
	local made: HpBar = { gui = gui, fill = fill, text = text, shownAt = os.clock() }
	hpBars[id] = made
	return made
end

local function setHp(id: string, model: Model, hp: number, hpMax: number)
	local bar = hpBar(id, model)
	if not bar then
		return
	end
	local ratio = if hpMax > 0 then math.clamp(hp / hpMax, 0, 1) else 0
	bar.fill.Size = UDim2.fromScale(ratio, 1)
	bar.fill.BackgroundColor3 = if ratio > 0.5 then C.green elseif ratio > 0.2 then C.yellow else C.red
	local k = known[id]
	local left = if k and k.damage > 0 and hp > 0 then math.ceil(hp / k.damage) else 0
	bar.text.Text = Format.number(hp)
		.. " / "
		.. Format.number(hpMax)
		.. (if left > 1 then "  · 약 " .. Format.number(left) .. "번" else "")
	bar.gui.Enabled = true
	bar.shownAt = os.clock()
	local shown = bar.shownAt
	task.delay(BreakController.HP_BAR_SECONDS, function()
		local b = hpBars[id]
		if b and b.shownAt == shown then
			b.gui.Enabled = false
		end
	end)
end

local function shake(model: Model, strength: number)
	local home = homes[model]
	if not home then
		home = model:GetPivot()
		homes[model] = home
	end
	local h = home
	model:PivotTo(h * CFrame.new(strength, 0, 0))
	task.delay(0.05, function()
		model:PivotTo(h * CFrame.new(-strength * 0.6, 0, 0))
	end)
	task.delay(0.1, function()
		model:PivotTo(h)
	end)
end

local function lookColor(model: Model): Color3
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Look" then
			return d.Color
		end
	end
	return C.white
end

local function setHidden(model: Model, hidden: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Hitbox" and d.Name ~= "Pedestal" and d.Name ~= "PedestalGlow" then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function shards(model: Model)
	local hitbox = hitboxOf(model)
	if not hitbox then
		return
	end
	local low = State.setting("lowGraphics", false)
	local count = if low then 3 else 8
	local color = lookColor(model)
	local r = model:GetAttribute("Radius")
	local radius = if type(r) == "number" then r else 3
	local center = hitbox.CFrame.Position
	local k = BreakController.scaleOf(model)
	for i = 1, count do
		local p = Instance.new("Part")
		p.Name = "Shard"
		p.Size = Vector3.one * math.clamp(radius * 0.3, 0.4 * k, 6 * k)
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Anchored = false
		local a = (i / count) * math.pi * 2
		p.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * radius * 0.4, 0, math.sin(a) * radius * 0.4))
		p.Parent = Workspace
		pcall(function()
			local v = math.sqrt(k) -- 큰 월드: 같은 시간에 크기에 맞게 더 멀리 (높이 ∝ v²)
			p.AssemblyLinearVelocity = Vector3.new(math.cos(a) * 18 * v, (28 + (i % 3) * 6) * v, math.sin(a) * 18 * v)
		end)
		task.delay(1.1, function()
			p:Destroy()
		end)
	end
end

-- 화면 흔들림: 카메라가 자리를 정한 바로 뒤(RenderPriority.Camera + 1)에 작은 회전을 곱함 — 카메라 스크립트와 안 싸우고
--   쌓이지 않음 (다음 프레임에 카메라가 다시 정함). angle 도 · seconds 초 동안 점점 줄어듦. 반환: 흔들었나
BreakController.lastShake = nil :: { angle: number, seconds: number }?
local shakeAngle, shakeSeconds, shakeStart = 0, 0, 0
local shakeBound = false
function BreakController.shakeCamera(angle: number, seconds: number): boolean
	if angle <= 0 or seconds <= 0 then
		return false
	end
	BreakController.lastShake = { angle = angle, seconds = seconds }
	-- 더 센 흔들림이 오면 덮어씀 (약한 것이 센 것을 끊지 않게)
	local now = os.clock()
	local remain = shakeSeconds - (now - shakeStart)
	if remain > 0 and shakeAngle * remain / math.max(shakeSeconds, 1e-3) > angle then
		return true
	end
	shakeAngle, shakeSeconds, shakeStart = angle, seconds, now
	if shakeBound then
		return true
	end
	shakeBound = true
	pcall(function()
		RunService:BindToRenderStep("BreakShake", Enum.RenderPriority.Camera.Value + 1, function()
			local camera = Workspace.CurrentCamera
			local u = 1 - (os.clock() - shakeStart) / math.max(shakeSeconds, 1e-3)
			if u <= 0 or not camera then
				shakeBound = false
				RunService:UnbindFromRenderStep("BreakShake")
				return
			end
			local a = math.rad(shakeAngle) * u
			camera.CFrame = camera.CFrame
				* CFrame.Angles(
					(math.random() * 2 - 1) * a,
					(math.random() * 2 - 1) * a,
					(math.random() * 2 - 1) * a * 0.5
				)
		end)
	end)
	return true
end

function BreakController.onHitResult(r: any)
	if type(r) ~= "table" or type(r.targetId) ~= "string" then
		return
	end
	local id = r.targetId
	local model = models[id]
	if not model then
		return -- "exam"/"duel" 송판은 ExamController 가 그림
	end
	local hitbox = hitboxOf(model)
	if not hitbox then
		return
	end
	local top = (heightOf(model) + 1) / 2
	local k = BreakController.scaleOf(model)
	-- (옛 서버의 reason "weak" 도 그냥 보통 타격으로 그림 — "힘이 부족해요" 글은 더 없음)
	local damage = tonumber(r.damage) or 0
	local hp = tonumber(r.hp) or 0
	local hpMax = tonumber(r.hpMax) or 1
	known[id] = { hp = if r.broken then hpMax else hp, hpMax = hpMax, damage = damage }
	if damage > 0 then
		floatText(hitbox, top + k, "-" .. Format.number(damage), C.white, 26, 0.6, 3 * k)
	end
	if r.broken then
		-- 클수록 크게 흔들림 (사장님 결정 18번 — 소리는 SoundController.playBreak, 둘 다 BreakFx.plan). 저사양이면 안 흔듦
		local fx = BreakFx.plan(id, State.setting("lowGraphics", false))
		BreakController.shakeCamera(fx.shake.angle, fx.shake.seconds)
		shards(model)
		Cracks.clear(model)
		known[id] = nil
		setHidden(model, true)
		task.delay(0.35, function()
			setHidden(model, false)
		end)
		local reward = tonumber(r.reward) or 0
		if reward > 0 then
			floatText(hitbox, top + 3 * k, "+💰 " .. Format.number(reward), C.money, 40, 1.2, 3 * k)
		end
		setHp(id, model, hpMax, hpMax)
	else
		-- 금은 맞히는 상자(Hitbox)가 아니라 물건의 보이는 겉면에 붙음 (단계가 바뀔 때만 레이캐스트)
		local before = Cracks.stageOf(model)
		local stage = Cracks.showModel(model, Cracks.stage(hp, hpMax), Cracks.seedOf(id))
		local radius = math.clamp(model:GetAttribute("Radius") :: number? or 2, 1, 20 * k)
		shake(model, radius * (if stage > before then 0.12 else 0.05))
		setHp(id, model, hp, hpMax)
	end
end

------------------------------------------------------------------
-- 물건 연결
------------------------------------------------------------------

local function hook(inst: Instance)
	if hooked[inst] or not inst:IsA("Model") then
		return
	end
	local id = inst:GetAttribute(PA.TargetId)
	if type(id) ~= "string" then
		return
	end
	hooked[inst] = true
	models[id] = inst
	homes[inst] = inst:GetPivot()
	-- 다시 연결된 물건(스트리밍으로 다시 생김): 마지막으로 안 체력의 금 단계로
	local k = known[id]
	if k then
		Cracks.showModel(inst, Cracks.stage(k.hp, k.hpMax), Cracks.seedOf(id), false)
	end
	local click = inst:FindFirstChild("Click")
	if click and click:IsA("ClickDetector") then
		click.MouseClick:Connect(function()
			BreakController.hitTarget(id)
		end)
	end
end

-- 물건 위 "💪 추천 힘 N": 내 치는 힘(힘 × 배수)이 모자라면 주황색, 아니면 노란색
BreakController.NEED_OK = Color3.fromRGB(255, 235, 150)
BreakController.NEED_HARD = Color3.fromRGB(255, 150, 40)
function BreakController.recommendPower(id: string): number
	local t: any = Targets.get(id)
	return if t then tonumber(t.recommendPower or t.minPower) or 0 else 0
end
function BreakController.paintNeed()
	local mine = State.power() * math.max(1, State.boost())
	for id, model in models do
		local hb = hitboxOf(model)
		local gui = hb and hb:FindFirstChild("TargetInfo")
		local box = gui and gui:FindFirstChild("Box")
		local need = box and box:FindFirstChild("Need")
		if need and need:IsA("TextLabel") then
			need.TextColor3 = if mine < BreakController.recommendPower(id)
				then BreakController.NEED_HARD
				else BreakController.NEED_OK
		end
	end
end

function BreakController.refresh()
	local act = activity()
	local b = BreakController.button
	if not b then
		return
	end
	if act == "exam" or act == "duel" then
		currentNearest = nil
		b.setText("송판 치기!", if act == "exam" then "승급 심사" else "시험관 대결")
		b.setVisible(true)
		return
	end
	local id = BreakController.nearest()
	currentNearest = id
	if id then
		local t = Targets.get(id)
		b.setText("치기", if t then t.name else "")
		b.setVisible(true)
	else
		b.setVisible(false)
	end
end

function BreakController.start()
	BreakController.button = ActionButton.new("HitButton", "치기", C.hitOrange, 1, "fist", BreakController.fire)
	-- 옛 서버가 "힘이 부족해요" 알림을 보내도 안 보이게 (이제 힘 문턱 없음)
	NotifyController.mute("힘이 부족해요")
	for _, inst in CollectionService:GetTagged(Tags.BreakTarget) do
		hook(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.BreakTarget):Connect(hook)
	Net.on(Remotes.ToClient.HitResult, BreakController.onHitResult)
	State.onChanged(function(section: string)
		if section == "attr:" .. Tags.PlayerAttributes.Activity or section == "snapshot" then
			BreakController.refresh()
		end
	end)
	local acc, needAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		needAcc += dt
		if acc >= 0.2 then
			acc = 0
			BreakController.refresh()
		end
		if needAcc >= 1 then
			needAcc = 0
			BreakController.paintNeed()
		end
	end)
	BreakController.refresh()
	BreakController.paintNeed()
end

-- 마지막으로 친 시각 (튜토리얼 등)
function BreakController.lastHit(): number
	return lastHitAt
end

return BreakController
