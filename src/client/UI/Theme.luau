--!strict
--[[
	Theme — UI 색·글꼴·애니메이션 상수 (밝고 귀엽고 알록달록, 모바일 친화)
	기준 화면 1100×720. 실제 크기는 Ui 의 UIScale 이 화면에 맞춰 줄이고 늘림 (버튼 최소 44px 보장).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rarities = require(ReplicatedStorage.Shared.Data.Rarities)

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.FontBody = Enum.Font.GothamBold

Theme.Colors = {
	ink = Color3.fromRGB(45, 30, 70), -- 글자 테두리/진한 글자
	panel = Color3.fromRGB(255, 249, 238),
	panelDark = Color3.fromRGB(255, 236, 214),
	white = Color3.new(1, 1, 1),
	money = Color3.fromRGB(110, 225, 90),
	speed = Color3.fromRGB(90, 185, 255),
	day = Color3.fromRGB(255, 200, 70),
	night = Color3.fromRGB(235, 60, 80),
	pink = Color3.fromRGB(255, 120, 175),
	orange = Color3.fromRGB(255, 160, 60),
	yellow = Color3.fromRGB(255, 215, 70),
	green = Color3.fromRGB(85, 205, 95),
	blue = Color3.fromRGB(80, 150, 255),
	purple = Color3.fromRGB(165, 105, 245),
	red = Color3.fromRGB(240, 70, 80),
	gray = Color3.fromRGB(160, 160, 170),
	mint = Color3.fromRGB(80, 215, 185),
}

-- 메뉴 버튼 색
Theme.Menu = {
	index = Theme.Colors.orange,
	gift = Theme.Colors.yellow,
	shop = Theme.Colors.green,
	pets = Theme.Colors.pink,
	settings = Theme.Colors.purple,
}

Theme.Tween = {
	fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	pop = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	open = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	close = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	slow = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

function Theme.rarityColor(id: string): Color3
	local r = Rarities.get(id)
	if r then
		return Color3.fromRGB(r.color[1], r.color[2], r.color[3])
	end
	return Theme.Colors.gray
end

function Theme.rarityText(id: string): Color3
	local r = Rarities.get(id)
	if r then
		return Color3.fromRGB(r.textColor[1], r.textColor[2], r.textColor[3])
	end
	return Theme.Colors.white
end

function Theme.darker(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount or 0.25)
end

function Theme.lighter(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount or 0.3)
end

return Theme
