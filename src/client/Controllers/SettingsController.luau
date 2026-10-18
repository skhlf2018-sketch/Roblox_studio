--!strict
--[[
	SettingsController — 설정 창 (음악 / 효과음 켜고 끄기)
	SoundController.setMusicEnabled / setSfxEnabled 와 연결. (이번 접속 동안만 기억 — 저장용 Remote 없음)
]]

local Client = script.Parent.Parent
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local SoundController = require(script.Parent.SoundController)

local SettingsController = {}

local C = Theme.Colors
local NAME = "Settings"

function SettingsController.start()
	local window = Ui.window(NAME, "설정", Theme.Menu.settings, Vector2.new(520, 360), function()
		Windows.close(NAME)
	end)
	local content = window.content
	Ui.list(Enum.FillDirection.Vertical, 16, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent =
		content

	local function row(title: string, order: number, get: () -> boolean, set: (boolean) -> ()): () -> ()
		local card = Ui.card(UDim2.new(1, -20, 0, 92), C.white, C.purple)
		card.LayoutOrder = order
		card.Parent = content
		Ui.label(title, UDim2.fromScale(0.5, 1), 32, C.ink, {
			Position = UDim2.fromOffset(20, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		local toggle: TextButton
		local function refresh()
			local on = get()
			Ui.setButton(toggle, if on then "켜짐" else "꺼짐", if on then C.green else C.gray)
		end
		toggle = Ui.button("", C.green, UDim2.fromOffset(170, 64), function()
			set(not get())
			refresh()
		end, { anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -16, 0.5, 0), textSize = 30, parent = card })
		refresh()
		return refresh
	end

	local refreshMusic = row("음악", 1, SoundController.isMusicEnabled, SoundController.setMusicEnabled)
	local refreshSfx = row("효과음", 2, SoundController.isSfxEnabled, SoundController.setSfxEnabled)
	Windows.register(NAME, window, function()
		refreshMusic()
		refreshSfx()
	end)
end

return SettingsController
