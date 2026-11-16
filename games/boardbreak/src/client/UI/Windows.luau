--!strict
--[[
	Windows — 큰 창(도감·상점·트레일·정원 식물·열매 가방·사쿠라·설정·고르기) 열고 닫기. 한 번에 하나만 열림.
	  Windows.register("Index", window, onOpen?)   -- window = Ui.window(...) 결과
	  Windows.toggle("Index") / Windows.open("Index") / Windows.close()
	  Windows.changed(function(openName: string?) end)
	ESC/뒤로 키로 닫힘.
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)

type Entry = {
	window: Ui.Window,
	onOpen: (() -> ())?,
}

local Windows = {}

local entries: { [string]: Entry } = {}
local current: string? = nil
local listeners: { (string?) -> () } = {}
local hooked = false

local function emit()
	for _, fn in listeners do
		task.spawn(fn, current)
	end
end

local function hide(name: string)
	local entry = entries[name]
	if not entry then
		return
	end
	local panel = entry.window.panel
	local pop = panel:FindFirstChild("Pop")
	if pop and pop:IsA("UIScale") then
		local t = Ui.tween(pop, Theme.Tween.close, { Scale = 0.6 })
		t.Completed:Connect(function()
			if current ~= name then
				entry.window.holder.Visible = false
			end
		end)
	else
		entry.window.holder.Visible = false
	end
end

function Windows.register(name: string, window: Ui.Window, onOpen: (() -> ())?)
	entries[name] = { window = window, onOpen = onOpen }
	if not hooked then
		hooked = true
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
				Windows.close()
			end
		end)
	end
end

function Windows.open(name: string)
	local entry = entries[name]
	if not entry then
		return
	end
	if current and current ~= name then
		local previous = current
		current = nil
		hide(previous)
	end
	current = name
	local holder = entry.window.holder
	holder.Visible = true
	local pop = entry.window.panel:FindFirstChild("Pop")
	if pop and pop:IsA("UIScale") then
		pop.Scale = 0.6
		Ui.tween(pop, Theme.Tween.open, { Scale = 1 })
	end
	SoundController.play("Open")
	if entry.onOpen then
		task.spawn(entry.onOpen)
	end
	emit()
end

function Windows.close(name: string?)
	local target = name or current
	if not target or target ~= current then
		return
	end
	current = nil
	hide(target)
	emit()
end

function Windows.toggle(name: string)
	if current == name then
		Windows.close(name)
	else
		Windows.open(name)
	end
end

function Windows.isOpen(name: string): boolean
	return current == name
end

function Windows.changed(fn: (string?) -> ())
	table.insert(listeners, fn)
end

return Windows
