--!strict
--[[
	NotifyController — 알림 (첫 게임 NotifyController 를 줄여 복사)
	  - 서버 Notify { kind, text } → 화면 아래 가운데 굵은 외곽선 글씨 토스트 (3초)
  - 큰 창(아령 가게·도감…)이 열려 있으면 창 글씨와 겹치므로 창 위쪽 빈 자리에 한 줄만 (어두운 칩 바탕)
	  - NotifyController.toast(text, kind)  kind: "info" | "success" | "error" | "money"
	  - NotifyController.banner(text, color) 위 가운데 큰 글씨 한 줄 (줄 서서 하나씩) — 띠 승급·월드 이동·대결 결과
	  - NotifyController.mute(prefix) 다른 화면이 대신 보여 주는 서버 글은 토스트로 안 띄움
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local Windows = require(Client.UI.Windows)

local NotifyController = {}

local C = Theme.Colors
local toastStack: Frame? = nil
local toastList: UIListLayout? = nil
local windowOpen = false

-- 창이 닫혀 있을 때: 아래 가운데 3줄 · 열려 있을 때: 창 위 빈 자리 1줄
local MAX_TOASTS = 3
local MAX_TOASTS_WINDOW = 1
local bannerHolder: Frame? = nil
local bannerQueue: { { text: string, color: Color3 } } = {}
local bannerBusy = false

local KIND_COLORS: { [string]: Color3 } = {
	success = Color3.fromRGB(140, 255, 140),
	error = Color3.fromRGB(255, 90, 90),
	info = Color3.fromRGB(230, 240, 255),
	money = Color3.fromRGB(255, 215, 70),
}

local muted: { string } = {}
function NotifyController.mute(prefix: string)
	if prefix ~= "" and not table.find(muted, prefix) then
		table.insert(muted, prefix)
	end
end
function NotifyController.isMuted(text: string): boolean
	for _, prefix in muted do
		if string.sub(text, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- 같은 글이 1초 안에 또 오면 하나만 (치기 연타 때 "힘이 부족해요" 줄줄이 방지)
local lastText = ""
local lastAt = -math.huge
-- 새 글일수록 작은 번호 (같은 순간에 두 개가 와도 순서가 안 섞이게 시계 대신 번호)
local toastOrder = 0

local function toastLabels(stack: Frame): { TextLabel }
	local labels: { TextLabel } = {}
	for _, child in stack:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	-- LayoutOrder 가 작을수록 새 글
	table.sort(labels, function(a: TextLabel, b: TextLabel): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	return labels
end

-- 창 위에 뜰 때는 어두운 칩 바탕 (창 제목 띠와 살짝 겹쳐도 읽히게)
local function styleToast(t: TextLabel)
	t.BackgroundColor3 = C.winEdge
	t.BackgroundTransparency = if windowOpen then 0.25 else 1
end

local function trimToasts(stack: Frame)
	local labels = toastLabels(stack)
	local max = if windowOpen then MAX_TOASTS_WINDOW else MAX_TOASTS
	for i = max + 1, #labels do
		labels[i]:Destroy()
	end
end

local function placeStack()
	local stack, list = toastStack, toastList
	if not stack or not list then
		return
	end
	if windowOpen then
		stack.AnchorPoint = Vector2.new(0.5, 0)
		stack.Position = UDim2.new(0.5, 0, 0, 6)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
	else
		stack.AnchorPoint = Vector2.new(0.5, 1)
		stack.Position = UDim2.new(0.5, 0, 1, -190)
		list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
	trimToasts(stack)
	for _, t in toastLabels(stack) do
		styleToast(t)
	end
end

function NotifyController.toast(text: string, kind: string?)
	local stack = toastStack
	if not stack then
		return
	end
	local now = os.clock()
	if text == lastText and now - lastAt < 1 then
		return
	end
	lastText, lastAt = text, now
	toastOrder -= 1
	local t: TextLabel = Ui.new("TextLabel", {
		Name = "Toast",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		TextColor3 = KIND_COLORS[kind or "info"] or C.white,
		TextSize = 30,
		Text = text,
		LayoutOrder = toastOrder,
		Parent = stack,
	})
	Ui.padding(10, 2).Parent = t
	Ui.corner(10).Parent = t
	Ui.textStroke(3, C.winEdge).Parent = t
	styleToast(t)
	Ui.pop(t, 1.25)
	trimToasts(stack)
	task.delay(3, function()
		if t.Parent then
			local fade = Ui.tween(t, TweenInfo.new(0.35), { TextTransparency = 1, BackgroundTransparency = 1 })
			local stroke = t:FindFirstChildOfClass("UIStroke")
			if stroke then
				Ui.tween(stroke, TweenInfo.new(0.35), { Transparency = 1 })
			end
			fade.Completed:Wait()
			t:Destroy()
		end
	end)
end

local function showNextBanner()
	local holder = bannerHolder
	if bannerBusy or not holder or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local item = table.remove(bannerQueue, 1) :: { text: string, color: Color3 }
	local banner: TextLabel = Ui.new("TextLabel", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 60),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		TextColor3 = item.color,
		TextSize = 44,
		RichText = true,
		Text = item.text,
		Parent = holder,
	})
	Ui.padding(12, 2).Parent = banner
	Ui.textStroke(4, C.winEdge).Parent = banner
	Ui.pop(banner, 0.4)
	task.delay(2.6, function()
		local fade = Ui.tween(banner, TweenInfo.new(0.4), { TextTransparency = 1 })
		for _, d in banner:GetChildren() do
			if d:IsA("UIStroke") then
				Ui.tween(d, TweenInfo.new(0.4), { Transparency = 1 })
			end
		end
		fade.Completed:Wait()
		banner:Destroy()
		bannerBusy = false
		showNextBanner()
	end)
end

function NotifyController.banner(text: string, color: Color3?)
	table.insert(bannerQueue, { text = text, color = color or C.white })
	showNextBanner()
end

function NotifyController.start()
	local stack: Frame = Ui.new("Frame", {
		Name = "ToastStack",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -190),
		Size = UDim2.fromOffset(760, 220),
		BackgroundTransparency = 1,
		Parent = Ui.layer("Toasts"),
	})
	Ui.scaled(stack)
	local list = Ui.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	list.Parent = stack
	toastStack = stack
	toastList = list
	Windows.changed(function(openName: string?)
		windowOpen = openName ~= nil
		placeStack()
	end)

	local banner: Frame = Ui.new("Frame", {
		Name = "BannerHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(900, 80),
		BackgroundTransparency = 1,
		Parent = Ui.layer("Alerts"),
	})
	Ui.scaled(banner)
	bannerHolder = banner

	Net.on(Remotes.ToClient.Notify, function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local text = tostring(payload.text)
		if not NotifyController.isMuted(text) then
			NotifyController.toast(text, tostring(payload.kind))
		end
	end)
end

return NotifyController
