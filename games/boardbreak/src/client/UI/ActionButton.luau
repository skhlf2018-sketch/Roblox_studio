--!strict
--[[
	ActionButton — 화면의 큰 둥근 버튼 "들기"(slot 0) · "치기"(slot 1) (선임)
	  local b = ActionButton.new("TrainButton", "들기", color, 0, "dumbbell", function() Net.send("Train") end)
	  b.setVisible(true) · b.setText("치기!", "솜") · b.isHolding()
	누르는 순간 한 번 + 누르고 있으면 Config.AUTO_REPEAT_SECONDS(0.22초)마다 다시 (초당 4.5번, 서버 한도 5번).
	자리는 UI/Layout.actionRect — PC 아래 가운데 / 터치 오른쪽 점프 버튼 위 (조이스틱·점프와 안 겹침, 46px 이상).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Data.Config)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Layout = require(script.Parent.Layout)
local Ui = require(script.Parent.Ui)

local ActionButton = {}

export type Handle = {
	button: TextButton,
	title: TextLabel,
	sub: TextLabel,
	setVisible: (boolean) -> (),
	setText: (string, string?) -> (),
	isHolding: () -> boolean,
	press: () -> (), -- 테스트: 누르기 시작
	release: () -> (), -- 테스트: 손 떼기
	rect: () -> Layout.Rect,
}

local C = Theme.Colors

function ActionButton.new(
	name: string,
	text: string,
	color: Color3,
	slot: number,
	icon: string,
	onFire: () -> ()
): Handle
	local button: TextButton = Ui.new("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(120, 120),
		Visible = false,
		Parent = Ui.layer("Panels"),
	})
	Ui.corner(1).Parent = button
	Ui.stroke(C.winEdge, 4).Parent = button
	Ui.gradient(Theme.lighter(color, 0.3), color).Parent = button
	local iconFrame = Icons.draw(icon, button, 40, UDim2.fromScale(0.5, 0.3))
	local title = Ui.label(text, UDim2.fromScale(0.9, 0.3), 30, C.white, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.48),
		TextScaled = true,
		Parent = button,
	})
	local sub = Ui.label("", UDim2.fromScale(0.8, 0.16), 16, C.yellow, {
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.76),
		TextScaled = true,
		Parent = button,
	})
	local press = Instance.new("UIScale")
	press.Name = "Press"
	press.Parent = button

	local holdId = 0
	local holding = false
	local function fire()
		local ok, err = pcall(function(): string?
			onFire()
			return nil
		end)
		if not ok then
			warn("[ActionButton] " .. name .. ": " .. tostring(err))
		end
	end
	local function startHold()
		if holding or not button.Visible then
			return
		end
		holding = true
		holdId += 1
		local my = holdId
		Ui.tween(press, Theme.Tween.fast, { Scale = 0.9 })
		fire()
		task.spawn(function()
			while holdId == my and holding and button.Visible do
				task.wait(Config.AUTO_REPEAT_SECONDS)
				if holdId ~= my or not holding or not button.Visible then
					break
				end
				fire()
			end
		end)
	end
	local function stopHold()
		if not holding then
			return
		end
		holding = false
		holdId += 1
		Ui.tween(press, Theme.Tween.pop, { Scale = 1 })
	end
	button.MouseButton1Down:Connect(startHold)
	button.MouseButton1Up:Connect(stopHold)
	button.MouseLeave:Connect(stopHold)
	button.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			stopHold()
		end
	end)

	local function rect(): Layout.Rect
		return Layout.actionRect(Ui.area(), Ui.scale(), Ui.isTouch(), slot)
	end
	local function place()
		local r = rect()
		button.Position = UDim2.fromOffset(r.x, r.y)
		button.Size = UDim2.fromOffset(r.w, r.h)
		local iconScale = iconFrame:FindFirstChildOfClass("UIScale")
		if iconScale then
			iconScale.Scale = r.w / 120
		end
	end
	Ui.onLayout(place)
	place()

	return {
		button = button,
		title = title,
		sub = sub,
		setVisible = function(on: boolean)
			if button.Visible ~= on then
				button.Visible = on
				if on then
					Ui.pop(button, 0.8)
				else
					stopHold()
				end
			end
		end,
		setText = function(t: string, s: string?)
			title.Text = t
			sub.Text = s or ""
		end,
		isHolding = function(): boolean
			return holding
		end,
		press = startHold,
		release = stopHold,
		rect = rect,
	}
end

return ActionButton
