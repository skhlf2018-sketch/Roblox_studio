--!strict
--[[
	Theme — UI 색·글꼴·애니메이션 상수 (밝고 귀엽고 알록달록, 모바일 친화) — 6판 "씨앗을 훔치세요"
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
	money = Color3.fromRGB(255, 210, 60), -- 6판: 코인 (금색)
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
	-- 2판 원작 스타일 (진한 창·버튼)
	win = Color3.fromRGB(46, 48, 60), -- 창 바탕 (진한 회남색)
	winDark = Color3.fromRGB(30, 32, 42), -- 창 안 칸·푸터
	winEdge = Color3.fromRGB(14, 15, 22), -- 두꺼운 테두리
	shopGreen = Color3.fromRGB(70, 210, 50), -- 상점 버튼
	indexCyan = Color3.fromRGB(30, 190, 245), -- 도감 버튼·창 제목
	trailPurple = Color3.fromRGB(170, 70, 225), -- 트레일 상점 제목
	eggRed = Color3.fromRGB(230, 40, 50), -- 오른쪽 씨앗 버튼
	pawOrange = Color3.fromRGB(255, 150, 40), -- 오른쪽 정원(식물) 버튼
	speedRed = Color3.fromRGB(255, 70, 110), -- 왼쪽 아래 속도 숫자
	moneyGreen = Color3.fromRGB(255, 205, 40), -- 왼쪽 아래 코인 숫자 (6판: 금색, 이름은 5판 그대로)
	fruitRed = Color3.fromRGB(240, 80, 80), -- 6판: 열매 가방 배지·창
	water = Color3.fromRGB(70, 170, 255), -- 6판: 물 주기
	runRed = Color3.fromRGB(200, 15, 25), -- "달리기!!" 배너·드롭 버튼
}

Theme.FontBold = Enum.Font.FredokaOne -- 굵은 외곽선 숫자 (원작 HUD)

-- 메뉴 버튼·창 색 (왼쪽 메뉴 = 상점·도감·슬로우 모드·설정 4개. pets = 6판 정원 식물 창, fruits = 열매 가방 창)
Theme.Menu = {
	index = Theme.Colors.indexCyan,
	shop = Theme.Colors.shopGreen,
	pets = Theme.Colors.pawOrange,
	fruits = Theme.Colors.fruitRed,
	settings = Theme.Colors.purple,
	trail = Theme.Colors.trailPurple,
}

Theme.Tween = {
	fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	pop = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	open = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	close = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	slow = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

-- 등급 색 16개 (7판): 색은 Rarities 표 하나에서만 읽음 (common … divine · super · hacker · original · developer ·
--   ultradivine · hacker_glitch). 무지개 글씨를 쓸 등급 (신성·슈퍼·울트라디바인·해커 글리치)
-- [7판 수석 임시] super_ultradivine 이 없어져서 새 id 로만 바꿈 — 해커 글리치 깨진 글자 연출 등은 선임
Theme.RainbowRarities =
	{ divine = true, super = true, ultradivine = true, hacker_glitch = true } :: { [string]: boolean }
Theme.RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 70)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 230, 120)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 100, 255)),
})

-- 등급 id 목록 (낮은 것 → 높은 것)
function Theme.rarityIds(): { string }
	local ids: { string } = {}
	for _, r in Rarities.list do
		table.insert(ids, r.id)
	end
	return ids
end

function Theme.rarityName(id: string): string
	local r = Rarities.get(id)
	return if r then r.name else id
end

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
