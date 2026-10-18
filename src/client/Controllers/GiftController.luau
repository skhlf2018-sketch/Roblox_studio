--!strict
--[[
	GiftController — 선물 창 (무료 보상: 좋아요 + 즐겨찾기 + 그룹 가입 → 속도 +10,000)
	받기 → ClaimFreeReward (계정당 1번, 서버가 확인). 받았으면 "받았어요!"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)

local GiftController = {}

local C = Theme.Colors
local NAME = "Gift"

function GiftController.start()
	local window = Ui.window(NAME, "선물", Theme.Menu.gift, Vector2.new(560, 420), function()
		Windows.close(NAME)
	end)
	local content = window.content

	local box: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(110, 90),
		BackgroundColor3 = C.red,
		Parent = content,
	})
	Ui.corner(14).Parent = box
	Ui.stroke(C.white, 4).Parent = box
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 18, 1, 0),
		BackgroundColor3 = C.yellow,
		Parent = box,
	})
	Ui.label(
		"무료 보상!",
		UDim2.new(1, 0, 0, 46),
		36,
		C.orange,
		{ Position = UDim2.fromOffset(0, 104), Parent = content }
	)
	Ui.label(
		"게임 좋아요 + 즐겨찾기 + 그룹 가입을 하면\n속도 +"
			.. Format.number(Config.FREE_REWARD_SPEED)
			.. " 을 줘요!",
		UDim2.new(1, -20, 0, 70),
		24,
		C.ink,
		{ Position = UDim2.fromOffset(10, 150), Parent = content }
	)
	local claim = Ui.button("받기!", C.green, UDim2.fromOffset(240, 66), function()
		Net.send(Remotes.ToServer.ClaimFreeReward)
	end, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -6),
		textSize = 32,
		parent = content,
		sound = "Reward",
	})

	local function render()
		local snap = State.get()
		if snap and snap.freeRewardClaimed then
			Ui.setButton(claim, "받았어요!", C.gray, false)
		else
			Ui.setButton(claim, "받기!", C.green, true)
		end
	end
	Windows.register(NAME, window, function()
		render()
		Ui.pop(box, 1.3)
	end)
	State.onChanged(function(section: string)
		if section == "flags" or section == "snapshot" then
			render()
		end
	end)
end

return GiftController
