--!strict
--[[
	ChaseController — 씨앗을 들었을 때 화면 (2판: 원작 그대로)
	- 씨앗을 들면(플레이어 Attribute CarryingEgg ≠ ""): 위 가운데 빨간 "달리기!!" 배너 + 화면 가장자리 빨간 비네트(맥박)
	  + 아래 가운데 빨간 "드롭" 버튼(쓰레기통) → DropEgg (그 자리에 씨앗을 내려놓고 추격 끝)
	- RunAlert: 속도가 모자라면 배너 아래 작은 경고 ("속도가 부족해요!")
	- 허브(안전 구역)에 들어오면 씨앗 가방으로 (배달 = 안전 구역에 들어가면 자동). 경비 = 그 구역 식물 괴물
	- Caught: "잡혔다!" + 화면 흔들림 + 빨간 번쩍 + 씨앗이 어떻게 됐는지
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local SpeedMath = require(Shared.SpeedMath)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Ui = require(Client.UI.Ui)

local ChaseController = {}

local C = Theme.Colors
local Attr = Tags.PlayerAttributes

local function carrying(): boolean
	local v = Players.LocalPlayer:GetAttribute(Attr.CarryingEgg)
	return typeof(v) == "string" and v ~= ""
end

-- 화면 가장자리 빨간 비네트 (4면 그라데이션)
local function makeVignette(parent: Instance, name: string): (Frame, { Frame })
	local vignette: Frame = Ui.new("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	local edges: { Frame } = {}
	for _, spec in
		{
			{ position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.22), rotation = 90 },
			{ position = UDim2.fromScale(0, 0.78), size = UDim2.fromScale(1, 0.22), rotation = -90 },
			{ position = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.16, 1), rotation = 0 },
			{ position = UDim2.fromScale(0.84, 0), size = UDim2.fromScale(0.16, 1), rotation = 180 },
		}
	do
		local e: Frame = Ui.new("Frame", {
			Position = spec.position,
			Size = spec.size,
			BackgroundColor3 = Color3.fromRGB(255, 30, 40),
			BackgroundTransparency = 0,
			Parent = vignette,
		})
		local g = Instance.new("UIGradient")
		g.Rotation = spec.rotation
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = e
		table.insert(edges, e)
	end
	return vignette, edges
end

function ChaseController.start()
	local player = Players.LocalPlayer
	local layer = Ui.layer("Alerts")

	------------------------------------------------------------------
	-- "달리기!!" 배너 + 비네트 + 드롭 버튼
	------------------------------------------------------------------
	local banner: TextLabel = Ui.new("TextLabel", {
		Name = "RunBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(300, 70),
		BackgroundColor3 = C.runRed,
		Text = "달리기!!",
		TextSize = 50,
		TextColor3 = C.white,
		Visible = false,
		Parent = layer,
	})
	Ui.scaled(banner)
	Ui.corner(12).Parent = banner
	Ui.stroke(Color3.fromRGB(255, 70, 80), 4).Parent = banner
	Ui.gradient(Color3.fromRGB(170, 10, 20), Color3.fromRGB(110, 0, 10)).Parent = banner
	Ui.textStroke(3, Color3.fromRGB(60, 0, 0)).Parent = banner
	local warnLabel = Ui.label("", UDim2.fromOffset(520, 34), 26, C.yellow, {
		Name = "SpeedWarning",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 8),
		Parent = banner,
	})

	local runVignette, runEdges = makeVignette(Ui.layer("World"), "RunVignette")

	local dropHolder: Frame = Ui.new("Frame", {
		Name = "DropHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(240, 66),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.layer("Hud"),
	})
	Ui.scaled(dropHolder)
	local drop = Ui.button("     드롭", C.runRed, UDim2.fromOffset(240, 66), function()
		Net.trySend(Remotes.ToServer.DropEgg)
	end, { parent = dropHolder, textSize = 32, sound = "Drop" })
	drop.Name = "DropButton"
	local dropStroke = drop:FindFirstChildOfClass("UIStroke")
	if dropStroke then
		dropStroke.Color = Color3.fromRGB(90, 0, 0)
		dropStroke.Thickness = 4
	end
	Icons.draw("trash", drop, 40, UDim2.new(0, 50, 0.5, 0))

	local guardSlow = false
	local function refresh()
		local on = carrying()
		banner.Visible = on
		runVignette.Visible = on
		dropHolder.Visible = on
		if not on then
			guardSlow = false
			warnLabel.Text = ""
		end
	end
	player:GetAttributeChangedSignal(Attr.CarryingEgg):Connect(function()
		local was = banner.Visible
		refresh()
		if banner.Visible and not was then
			Ui.pop(banner, 1.4)
			Ui.pop(drop, 1.2)
		end
	end)
	refresh()

	Net.on(Remotes.ToClient.RunAlert, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local yours = tonumber(payload.yourSpeed) or 0
		local guard = tonumber(payload.guardSpeed) or 0
		guardSlow = guard > 0 and not SpeedMath.canEscape(guard, yours)
		warnLabel.Text = if guardSlow
			then string.format(
				"속도가 부족해요! (내 %s / 추천 %s)",
				Format.number(yours),
				Format.number(guard)
			)
			else ""
		banner.Visible = true
		runVignette.Visible = true
		dropHolder.Visible = true
		Ui.pop(banner, 1.4)
	end)
	Net.on(Remotes.ToClient.ChaseEnded, function(payload: any)
		local reason = if typeof(payload) == "table" then payload.reason else nil
		if banner.Visible then
			warnLabel.Text = if reason == "safe"
				then "안전 구역 도착! 씨앗을 정원에 심어요!"
				elseif reason == "night" then "밤이 됐어요! 안전 구역으로!"
				else "식물 괴물이 멈췄어요! 안전 구역으로!"
			warnLabel.TextColor3 = C.moneyGreen
		end
	end)

	-- 배너 흔들림 + 비네트 맥박 + 허브 안내
	local t = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if not banner.Visible then
			return
		end
		t += dt
		banner.Rotation = math.sin(t * 18) * 2
		local pulse = 0.25 + (math.sin(t * 6) + 1) * 0.12
		for _, e in runEdges do
			e.BackgroundTransparency = pulse
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			if banner.Visible then
				local inSafe = player:GetAttribute(Attr.InSafeZone) == true
				banner.Text = if inSafe then "안전 구역!" else "달리기!!"
				if not guardSlow and warnLabel.TextColor3 ~= C.moneyGreen then
					warnLabel.TextColor3 = C.yellow
				end
			end
		end
	end)

	------------------------------------------------------------------
	-- 잡힘
	------------------------------------------------------------------
	local vignette, edges = makeVignette(Ui.layer("World"), "Vignette")

	local caughtHolder: Frame = Ui.new("Frame", {
		Name = "Caught",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.35),
		Size = UDim2.fromOffset(640, 180),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	Ui.scaled(caughtHolder)
	local caughtText: TextLabel = Ui.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 110),
		BackgroundTransparency = 1,
		Text = "잡혔다!",
		TextSize = 96,
		TextColor3 = C.white,
		Parent = caughtHolder,
	})
	Ui.textStroke(7, C.red).Parent = caughtText
	local caughtInfo = Ui.label("", UDim2.new(1, 0, 0, 40), 28, C.white, {
		Position = UDim2.fromOffset(0, 112),
		Parent = caughtHolder,
	})

	local function shakeCamera(seconds: number)
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not humanoid then
			return
		end
		local hum = humanoid
		local t0 = os.clock()
		local connection: RBXScriptConnection? = nil
		connection = RunService.RenderStepped:Connect(function()
			local elapsed = os.clock() - t0
			if elapsed > seconds or hum.Parent == nil then
				hum.CameraOffset = Vector3.zero
				if connection then
					connection:Disconnect()
				end
				return
			end
			local k = (1 - elapsed / seconds) * 0.8
			hum.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * k
		end)
	end

	Net.on(Remotes.ToClient.Caught, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local cause = payload.cause
		caughtText.Text = if cause == "trap"
			then "덫에 걸렸다!"
			elseif cause == "player" then "맞았다!"
			else "잡혔다!"
		local outcome = payload.eggOutcome
		local by = tostring(payload.by or "")
		local how = if cause == "player" or cause == "trap" then by .. "의 공격!" else by .. "에게 잡혔어요!"
		local egg = if outcome == "ReturnToNest"
			then " 씨앗이 둥지로 돌아갔어요"
			elseif outcome == "DropHere" then " 씨앗을 떨어뜨렸어요! 빨리 주워요"
			else ""
		caughtInfo.Text = how .. egg
		caughtHolder.Visible = true
		Ui.pop(caughtText, 1.8)
		vignette.Visible = true
		for _, e in edges do
			e.BackgroundTransparency = 0
			Ui.tween(
				e,
				TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ BackgroundTransparency = 1 }
			)
		end
		shakeCamera(0.45)
		task.delay(2.2, function()
			caughtHolder.Visible = false
			vignette.Visible = false
		end)
	end)
end

return ChaseController
