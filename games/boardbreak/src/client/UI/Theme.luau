--!strict
--[[
	Theme — 송판 깨기 화면 색·글꼴·애니메이션 (첫 게임 Theme 을 줄여 복사). 기준 화면 1100×720.
	진한 창 + 두꺼운 테두리 + 굵은 외곽선 숫자 (첫 게임과 같은 느낌), 색은 도장(빨강·하양) · 힘(빨강) · 돈(금색).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Belts = require(ReplicatedStorage.Shared.Data.Belts)
local Worlds = require(ReplicatedStorage.Shared.Data.Worlds)

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.FontBody = Enum.Font.GothamBold
Theme.FontBold = Enum.Font.FredokaOne

Theme.Colors = {
	ink = Color3.fromRGB(45, 30, 70),
	panel = Color3.fromRGB(255, 249, 238),
	panelDark = Color3.fromRGB(255, 236, 214),
	white = Color3.new(1, 1, 1),
	money = Color3.fromRGB(255, 210, 60),
	power = Color3.fromRGB(255, 80, 95),
	pink = Color3.fromRGB(255, 120, 175),
	orange = Color3.fromRGB(255, 160, 60),
	yellow = Color3.fromRGB(255, 215, 70),
	green = Color3.fromRGB(85, 205, 95),
	blue = Color3.fromRGB(80, 150, 255),
	purple = Color3.fromRGB(165, 105, 245),
	red = Color3.fromRGB(240, 70, 80),
	gray = Color3.fromRGB(160, 160, 170),
	mint = Color3.fromRGB(80, 215, 185),
	win = Color3.fromRGB(46, 48, 60), -- 창 바탕
	winDark = Color3.fromRGB(30, 32, 42), -- 창 안 칸
	winEdge = Color3.fromRGB(14, 15, 22), -- 두꺼운 테두리
	shopGreen = Color3.fromRGB(70, 210, 50), -- 사기 버튼
	indexCyan = Color3.fromRGB(30, 190, 245),
	eggRed = Color3.fromRGB(230, 40, 50), -- 창 닫기 X (Ui.window 가 씀)
	moneyGreen = Color3.fromRGB(255, 205, 40), -- 왼쪽 아래 돈 숫자 (금색)
	speedRed = Color3.fromRGB(255, 80, 95), -- 왼쪽 아래 힘 숫자
	trainRed = Color3.fromRGB(235, 60, 60), -- "들기" 버튼
	hitOrange = Color3.fromRGB(255, 140, 30), -- "치기" 버튼
	weak = Color3.fromRGB(255, 70, 70), -- "힘이 부족해요"
}

-- 왼쪽 메뉴 버튼·창 색
Theme.Menu = {
	shop = Color3.fromRGB(70, 210, 50), -- 아령 가게
	index = Color3.fromRGB(30, 190, 245), -- 도감
	boost = Color3.fromRGB(255, 150, 20), -- 힘 배수
	belt = Color3.fromRGB(200, 70, 60), -- 띠·심사
	settings = Color3.fromRGB(165, 105, 245), -- 설정
}

Theme.Tween = {
	fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	pop = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	open = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	close = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	slow = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

function Theme.darker(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount or 0.25)
end

function Theme.lighter(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount or 0.3)
end

local function rgb(t: { number }?): Color3
	if not t then
		return Theme.Colors.gray
	end
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- 띠 색 (1~12, 없으면 회색)
function Theme.beltColor(index: number): Color3
	local belt = Belts.get(index)
	return rgb(if belt then belt.color else nil)
end

-- 띠 위 글자 색 (흰·노랑 띠는 어두운 글자)
function Theme.beltText(index: number): Color3
	local c = Theme.beltColor(index)
	local light = c.R * 0.3 + c.G * 0.59 + c.B * 0.11
	return if light > 0.7 then Theme.Colors.ink else Theme.Colors.white
end

function Theme.worldColor(index: number): Color3
	local w = Worlds.get(index)
	return rgb(if w then w.color else nil)
end

return Theme
