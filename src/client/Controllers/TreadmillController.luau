--!strict
--[[
	TreadmillController — 러닝머신 (2판: 원작처럼 올라서면 제자리 달리기)

	- 플레이어 Attribute OnTreadmill = true 인 동안: 이동 입력(WASD·조이스틱)을 끔 (PlayerModule Controls:Disable)
	  아래 가운데 "점프하면 내려와요" 안내 + 터치 기기는 "내리기" 버튼
	- 점프 입력(스페이스·게임패드 A·JumpRequest·내리기 버튼) → TreadmillLeave (서버가 내려 줌)
	- TreadmillStep({ amount }) 마다 캐릭터 주변에 분홍 "+500" 글씨가 떠오름 (원작)
	판정·속도 증가는 전부 서버. 이 컨트롤러는 입력과 연출만.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local SoundController = require(script.Parent.SoundController)

local TreadmillController = {}

local C = Theme.Colors
local Attr = Tags.PlayerAttributes
local PINK = Color3.fromRGB(255, 90, 170)

local controls: any = nil
local function getControls(): any
	if controls then
		return controls
	end
	local ok, result = pcall(function(): any
		local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
		local module = if scripts then scripts:FindFirstChild("PlayerModule") else nil
		if module and module:IsA("ModuleScript") then
			return (require :: any)(module):GetControls()
		end
		return nil
	end)
	if ok then
		controls = result
	end
	return controls
end

local function onTreadmill(): boolean
	return Players.LocalPlayer:GetAttribute(Attr.OnTreadmill) == true
end

local leaving = false
local function leave()
	if not onTreadmill() or leaving then
		return
	end
	leaving = true
	Net.trySend(Remotes.ToServer.TreadmillLeave)
	task.delay(0.4, function()
		leaving = false
	end)
end

-- "+500" 분홍 글씨 (캐릭터 옆에서 위로 떠오름)
function TreadmillController.popStep(amount: number)
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "StepPop"
	gui.Size = UDim2.fromOffset(150, 44)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local start = Vector3.new(math.random() * 4 - 2, 1.5 + math.random() * 1.5, math.random() * 2 - 1)
	gui.StudsOffset = start
	gui.Adornee = root
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Font
	label.TextScaled = true
	label.Text = "+" .. Format.number(amount)
	label.TextColor3 = PINK
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.winEdge
	stroke.Thickness = 2.5
	stroke.Parent = label
	gui.Parent = root
	Ui.tween(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { StudsOffset = start + Vector3.new(0, 3.5, 0) })
	Ui.tween(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
	Ui.tween(stroke, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
	task.delay(1, function()
		gui:Destroy()
	end)
end

function TreadmillController.start()
	local player = Players.LocalPlayer

	local hint: Frame = Ui.new("Frame", {
		Name = "TreadmillHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.fromOffset(420, 64),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.layer("Hud"),
	})
	Ui.scaled(hint)
	Ui.label("러닝머신 달리는 중! 점프하면 내려와요", UDim2.new(1, 0, 0, 30), 24, C.white, {
		Name = "Text",
		Parent = hint,
	})
	local leaveButton = Ui.button("내리기", C.pawOrange, UDim2.fromOffset(150, Ui.touch(48)), leave, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 32),
		textSize = 24,
		parent = hint,
	})
	leaveButton.Name = "LeaveButton"

	local function refresh()
		local on = onTreadmill()
		hint.Visible = on
		leaveButton.Visible = Ui.isTouch()
		local c = getControls()
		if c then
			pcall(function()
				if on then
					c:Disable()
				else
					c:Enable()
				end
			end)
		end
		if on then
			Ui.pop(hint, 1.15)
		end
	end
	player:GetAttributeChangedSignal(Attr.OnTreadmill):Connect(refresh)
	player.CharacterAdded:Connect(function()
		task.defer(refresh)
	end)
	refresh()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			leave()
		end
	end)
	pcall(function()
		UserInputService.JumpRequest:Connect(leave)
	end)

	Net.onLater(Remotes.ToClient.TreadmillStep, function(payload: any)
		local amount = if typeof(payload) == "table" then tonumber(payload.amount) else tonumber(payload)
		if amount and amount > 0 then
			TreadmillController.popStep(amount)
			SoundController.play("TreadmillStep")
		end
	end)
end

return TreadmillController
