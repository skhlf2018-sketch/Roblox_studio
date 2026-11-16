--!strict
--[[
	SettingsController — 설정 창 "Settings" (선임)
	  토글 3개: 🎵 음악 · 🔊 효과음 · ✨ 그래픽 줄이기 (조각 효과 적게, 폰)
	  누르면 바로 내 화면에 적용 + SetSetting(key, value) 로 서버에 저장 (Config.SETTINGS 키, boolean).
	  처음 값은 Snapshot.settings (없으면 Config.SETTINGS 기본값).
	공개: NAME · toggle(key) · value(key)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)
local HudController = require(script.Parent.HudController)
local SoundController = require(script.Parent.SoundController)

local SettingsController = {}
local NAME = "Settings"
SettingsController.NAME = NAME

local C = Theme.Colors
local SIZE = Vector2.new(520, 400)

local ROWS: { { key: string, label: string } } = {
	{ key = "music", label = "🎵 음악" },
	{ key = "sfx", label = "🔊 효과음" },
	{ key = "lowGraphics", label = "✨ 그래픽 줄이기" },
}

local values: { [string]: boolean } = {}

function SettingsController.value(key: string): boolean
	local v = values[key]
	if v ~= nil then
		return v
	end
	return State.setting(key, Config.SETTINGS[key] == true)
end

local function apply()
	SoundController.setMusicEnabled(SettingsController.value("music"))
	SoundController.setSfxEnabled(SettingsController.value("sfx"))
end

local renderFn: (() -> ())? = nil

function SettingsController.toggle(key: string)
	local v = not SettingsController.value(key)
	values[key] = v
	-- 그래픽 줄이기는 State.setting 으로 읽으므로 내 복사본에도 넣음
	local snap = State.get() :: any
	if snap then
		snap.settings = snap.settings or {}
		snap.settings[key] = v
	end
	apply()
	Net.send(Remotes.ToServer.SetSetting, key, v)
	local fn = renderFn
	if fn then
		fn()
	end
end

function SettingsController.start()
	local window = Ui.window(NAME, "⚙️ 설정", Theme.Menu.settings, SIZE, function()
		Windows.close(NAME)
	end)
	local content = window.content
	Ui.list(Enum.FillDirection.Vertical, 12).Parent = content
	local buttons: { [string]: TextButton } = {}
	for i, row in ROWS do
		local line: Frame = Ui.new("Frame", {
			Name = "Row_" .. row.key,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 72),
			BackgroundColor3 = C.winDark,
			Parent = content,
		})
		Ui.corner(12).Parent = line
		Ui.label(row.label, UDim2.fromScale(0.6, 1), 28, C.white, {
			Name = "Label",
			Position = UDim2.fromOffset(16, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = line,
		})
		local b = Ui.button("켜짐", C.shopGreen, UDim2.fromOffset(150, 56), function()
			SettingsController.toggle(row.key)
		end, {
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -10, 0.5, 0),
			textSize = 26,
			parent = line,
		})
		b.Name = "Toggle"
		buttons[row.key] = b
	end
	local function render()
		local h = Ui.touch(56, SIZE)
		for key, b in buttons do
			local on = SettingsController.value(key)
			b.Size = UDim2.fromOffset(150, h)
			Ui.setButton(b, if on then "켜짐" else "꺼짐", if on then C.shopGreen else C.gray, true)
		end
	end
	renderFn = render
	Windows.register(NAME, window, render)
	render()
	State.onChanged(function(section: string)
		if section == "snapshot" or section == "settings" then
			table.clear(values)
			apply()
			render()
		end
	end)
	apply()

	HudController.addMenuButton("settings", "설정", 5, function()
		Windows.toggle(NAME)
	end)
end

return SettingsController
