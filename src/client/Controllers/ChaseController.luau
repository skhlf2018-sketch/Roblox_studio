--!strict
--[[
	ChaseController — 알을 들었을 때 화면
	- RunAlert: 가운데 위쪽 큰 빨간 "RUN!!" (덜덜 흔들림) + 경비까지 거리 (ChaseEnded 까지)
	  알을 내려놓으면(배달/놓침, CarryingEgg = "") 사라짐
	- Caught: "잡혔다!" + 화면 흔들림 + 빨간 테두리(비네트) + 알이 어떻게 됐는지
	거리 = TargetUserId 가 나인 경비(Guardian 태그) HumanoidRootPart 와 내 캐릭터 거리 (보기용)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)

local ChaseController = {}

local C = Theme.Colors
local Attr = Tags.PlayerAttributes

local function myRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function chasingGuard(): BasePart?
	local me = Players.LocalPlayer.UserId
	for _, guard in CollectionService:GetTagged(Tags.Guardian) do
		if guard:GetAttribute("TargetUserId") == me then
			local root = guard:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root
			end
		end
	end
	return nil
end

function ChaseController.start()
	local player = Players.LocalPlayer
	local layer = Ui.layer("Alerts")

	local holder: Frame = Ui.new("Frame", {
		Name = "Run",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(620, 220),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	Ui.scaled(holder)
	local run: TextLabel = Ui.new("TextLabel", {
		Name = "RunText",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(560, 120),
		BackgroundTransparency = 1,
		Text = "RUN!!",
		TextSize = 110,
		TextColor3 = C.red,
		Parent = holder,
	})
	local runStroke = Ui.textStroke(6, C.white)
	runStroke.Parent = run
	local info = Ui.label("", UDim2.fromOffset(620, 40), 28, C.white, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 118),
		Parent = holder,
	})
	local distance = Ui.label("", UDim2.fromOffset(620, 40), 30, C.yellow, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 160),
		Parent = holder,
	})

	local carrying = false
	local chased = false
	local guardName = "경비"
	local slow = false
	local shakeTime = 0

	local function hideRun()
		carrying = false
		holder.Visible = false
	end

	Net.on(Remotes.ToClient.RunAlert, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		carrying = true
		chased = true
		guardName = tostring(payload.guardName or "경비")
		local yours = tonumber(payload.yourSpeed) or 0
		local guard = tonumber(payload.guardSpeed) or 0
		slow = yours < guard
		info.Text = guardName .. "이(가) 쫓아와요! 내 베이스로 달려요!"
		info.TextColor3 = C.white
		holder.Visible = true
		Ui.pop(run, 1.6)
		if slow then
			distance.Text = string.format(
				"속도가 부족해요! (내 %s / 경비 %s)",
				Format.number(yours),
				Format.number(guard)
			)
			distance.TextColor3 = C.red
		else
			distance.Text = ""
		end
	end)
	Net.on(Remotes.ToClient.ChaseEnded, function()
		chased = false
		if carrying then
			distance.Text = "경비를 따돌렸어요! 베이스로 가져가요!"
			distance.TextColor3 = C.money
		end
	end)
	player:GetAttributeChangedSignal(Attr.CarryingEgg):Connect(function()
		local v = player:GetAttribute(Attr.CarryingEgg)
		if v == nil or v == "" then
			hideRun()
		end
	end)

	-- 흔들림 + 거리
	RunService.RenderStepped:Connect(function(dt: number)
		if holder.Visible then
			shakeTime += dt
			run.Rotation = math.sin(shakeTime * 30) * 4
			run.Position = UDim2.new(0.5, math.sin(shakeTime * 47) * 4, 0, math.cos(shakeTime * 39) * 3)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.15)
			if carrying then
				local inSafe = player:GetAttribute(Attr.InSafeZone) == true
				if inSafe then
					run.Text = "거의 다 왔어요!"
					run.TextSize = 70
					info.Text = "초록색 배달 패드에 올라가요!"
					distance.Text = ""
				else
					run.Text = "RUN!!"
					run.TextSize = 110
					if chased then
						local guard = chasingGuard()
						local root = myRoot()
						if guard and root then
							local d = (guard.Position - root.Position).Magnitude
							distance.Text = string.format("%s까지 %dm", guardName, math.floor(d))
							distance.TextColor3 = if d < 15 then C.red elseif d < 40 then C.orange else C.yellow
						elseif not slow then
							distance.Text = guardName .. "이(가) 오고 있어요..."
							distance.TextColor3 = C.yellow
						end
					end
				end
			end
		end
	end)

	------------------------------------------------------------------
	-- 잡힘
	------------------------------------------------------------------
	local vignette: Frame = Ui.new("Frame", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.layer("World"),
	})
	local edges: { Frame } = {}
	for _, spec in
		{
			{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.25), 90 },
			{ UDim2.fromScale(0, 0.75), UDim2.fromScale(1, 0.25), -90 },
			{ UDim2.fromScale(0, 0), UDim2.fromScale(0.2, 1), 0 },
			{ UDim2.fromScale(0.8, 0), UDim2.fromScale(0.2, 1), 180 },
		}
	do
		local e: Frame = Ui.new("Frame", {
			Position = spec[1],
			Size = spec[2],
			BackgroundColor3 = Color3.fromRGB(255, 20, 40),
			BackgroundTransparency = 0,
			Parent = vignette,
		})
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = e
		table.insert(edges, e)
	end

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
			local t = os.clock() - t0
			if t > seconds or hum.Parent == nil then
				hum.CameraOffset = Vector3.zero
				if connection then
					connection:Disconnect()
				end
				return
			end
			local k = (1 - t / seconds) * 0.8
			hum.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * k
		end)
	end

	Net.on(Remotes.ToClient.Caught, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		hideRun()
		local cause = payload.cause
		caughtText.Text = if cause == "trap"
			then "덫에 걸렸다!"
			elseif cause == "player" then "맞았다!"
			else "잡혔다!"
		local outcome = payload.eggOutcome
		local by = tostring(payload.by or "")
		local how = if cause == "player" or cause == "trap" then by .. "의 공격!" else by .. "에게 잡혔어요!"
		local egg = if outcome == "ReturnToNest"
			then " 알이 둥지로 돌아갔어요"
			elseif outcome == "DropHere" then " 알을 떨어뜨렸어요! 빨리 주워요"
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
