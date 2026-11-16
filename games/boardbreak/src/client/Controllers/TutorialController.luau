--!strict
--[[
	TutorialController — 처음 하는 사람을 위한 화살표 안내 3단계 (선임)
	  1/3 💪 수련 매트에 올라가 "들기"를 눌러요       → 힘이 TUTORIAL_POWER(10) 이상이면 다음
	  2/3 🥊 솜을 눌러서 깨요!                        → 솜(cotton)을 한 번 깨면 다음
	  3/3 🏋️ 아령 가게에서 다음 아령을 사요            → 아령 레벨 2 이상이면 끝 ("안내 끝!" 토스트)
	단계는 저장된 값(힘 · 깬 횟수 · 아령 레벨)으로 정함 → 다시 들어와도 이어서, 이미 지난 사람은 안 보임.
	화면: 위 가운데 패널 "TutorialPanel" (단계 글 + 진행) + 월드의 목표 위에 노란 화살표(내 화면에만 있는 파트, 위아래로 통통).
	월드 1 에 있을 때만, 심사·대결 중에는 숨김. 3단계에서는 왼쪽 메뉴 "아령 가게" 버튼도 톡톡.
	공개: step() · refresh() · arrow · panel · TUTORIAL_POWER
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Dumbbells = require(Shared.Data.Dumbbells)
local MapLayout = require(Shared.Data.MapLayout)
local Format = require(Shared.Format)
local Client = script.Parent.Parent
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Layout = require(Client.UI.Layout)
local Ui = require(Client.UI.Ui)
local HudController = require(script.Parent.HudController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)

local TutorialController = {}
TutorialController.TUTORIAL_POWER = 10
TutorialController.arrow = nil :: Part?
TutorialController.panel = nil :: Frame?
TutorialController.PANEL = Vector2.new(520, 64)

local C = Theme.Colors
local shownStep = -1
local doneShown = false

-- 지금 단계 (1~3, 다 했으면 0)
function TutorialController.step(): number
	if State.dumbbell() >= 2 then
		return 0
	end
	if State.broken("cotton") > 0 then
		return 3
	end
	if State.power() >= TutorialController.TUTORIAL_POWER then
		return 2
	end
	return 1
end

local function goal(step: number): (Vector3?, number)
	local world = 1
	if step == 1 then
		local mat = MapLayout.trainMats(world)[1]
		return Vector3.new(mat.x, mat.y, mat.z), 6
	elseif step == 2 then
		local p = MapLayout.targetPosition("cotton")
		return if p then Vector3.new(p.x, p.y, p.z) else nil, 9
	elseif step == 3 then
		local s = MapLayout.dumbbellShop(world)
		return Vector3.new(s.x, s.y, s.z), 13
	end
	return nil, 0
end

local function text(step: number): (string, string)
	if step == 1 then
		return '1/3 💪 수련 매트에 올라가 "들기"를 눌러요',
			string.format("힘 %s / %d", Format.number(State.power()), TutorialController.TUTORIAL_POWER)
	elseif step == 2 then
		return "2/3 🥊 도장 밖 솜을 눌러서 깨요!", '가까이 가면 "치기" 버튼도 생겨요'
	elseif step == 3 then
		local nxt = Dumbbells.get(2)
		return "3/3 🏋️ 아령 가게에서 다음 아령을 사요",
			if nxt then string.format("%s · 💰 %s", nxt.name, Format.number(nxt.price)) else ""
	end
	return "", ""
end

local title: TextLabel? = nil
local sub: TextLabel? = nil
local bob = 0

function TutorialController.refresh()
	local panel = TutorialController.panel
	local arrow = TutorialController.arrow
	if not panel or not arrow then
		return
	end
	local step = TutorialController.step()
	local visible = step > 0 and State.currentWorld() == 1 and State.activity() == ""
	panel.Visible = visible
	arrow.Transparency = if visible then 0 else 1
	if step == 0 then
		if shownStep > 0 and not doneShown then
			doneShown = true
			NotifyController.toast("🎉 안내 끝! 이제 더 큰 물건을 깨 봐요", "success")
			SoundController.play("TutorialDone")
		end
		shownStep = 0
		return
	end
	if step ~= shownStep then
		if shownStep > 0 then
			SoundController.play("TutorialStep")
			Ui.pop(panel, 1.15)
		end
		shownStep = step
	end
	local t, s = text(step)
	local tl, sl = title, sub
	if tl and sl then
		tl.Text = t
		sl.Text = s
	end
	local pos, height = goal(step)
	if pos then
		arrow:SetAttribute("Goal", pos + Vector3.new(0, height, 0))
	end
	if step == 3 then
		local b = HudController.menuButton("shop")
		if b and math.floor(os.clock()) % 2 == 0 then
			Ui.pop(b, 1.08)
		end
	end
end

function TutorialController.start()
	local base = TutorialController.PANEL
	local panel: Frame = Ui.new("Frame", {
		Name = "TutorialPanel",
		Size = UDim2.fromOffset(base.X, base.Y),
		BackgroundColor3 = C.win,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = Ui.layer("Hud"),
	})
	Ui.corner(12).Parent = panel
	Ui.stroke(C.yellow, 4).Parent = panel
	local scale = Instance.new("UIScale")
	scale.Name = "PanelScale"
	scale.Parent = panel
	title = Ui.label("", UDim2.new(1, -16, 0, 34), 26, C.white, {
		Name = "Title",
		Position = UDim2.fromOffset(8, 2),
		TextScaled = true,
		Parent = panel,
	})
	sub = Ui.label("", UDim2.new(1, -16, 0, 22), 18, C.yellow, {
		Name = "Sub",
		Position = UDim2.fromOffset(8, 38),
		TextScaled = true,
		Parent = panel,
	})
	TutorialController.panel = panel
	local function place()
		local r = Layout.topPanel(Ui.area(), Ui.scale(), Ui.isTouch(), base.X, base.Y)
		panel.Position = UDim2.fromOffset(r.x, r.y)
		scale.Scale = Ui.scale()
	end
	Ui.onLayout(place)
	place()

	-- 화살표 (아래를 가리키는 쐐기 — 내 화면에만)
	local arrow = Instance.new("Part")
	arrow.Name = "TutorialArrow"
	arrow.Shape = Enum.PartType.Wedge
	arrow.Size = Vector3.new(1.2, 3, 3)
	arrow.Color = C.yellow
	arrow.Material = Enum.Material.Neon
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.CanTouch = false
	arrow.Transparency = 1
	arrow.Parent = Workspace
	TutorialController.arrow = arrow

	State.onChanged(function()
		TutorialController.refresh()
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		bob += dt
		acc += dt
		local g = arrow:GetAttribute("Goal")
		if typeof(g) == "Vector3" then
			-- 쐐기 뾰족한 곳이 아래로: 옆으로 눕혀 빙글빙글 + 위아래로
			arrow.CFrame = CFrame.new(g + Vector3.new(0, math.sin(bob * 3) * 0.8, 0))
				* CFrame.Angles(0, bob * 1.5, 0)
				* CFrame.Angles(math.rad(180), 0, 0)
		end
		if acc >= 0.5 then
			acc = 0
			TutorialController.refresh()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("Power"):Connect(TutorialController.refresh)
	TutorialController.refresh()
end

return TutorialController
