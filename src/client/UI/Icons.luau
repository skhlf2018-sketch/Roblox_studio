--!strict
--[[
	Icons — HUD 그림(카트·책·씨앗·새싹·열매·신발·코인·달·해·쓰레기통·별·자물쇠)을 기본 Frame 으로 그리기
	외부 이미지를 올릴 수 없어서 네모·동그라미 Frame 을 겹쳐 그립니다.

	  Icons.draw("cart", parent, 40)   → 40×40 기준 상자(Frame "Icon") 안에 그림. UIScale 로 크기 맞춤
	종류: cart, book, seed, plant, fruit, coin, shoe, moon, sun, trash, star, lock, gear, gift, scroll, sell, trail
	  6판 "씨앗을 훔치세요": 옛 이름 egg(= seed), paw(= plant), money(= coin) 도 같은 그림 (옛 코드 호환)
]]

local Theme = require(script.Parent.Theme)

local Icons = {}

local INK = Color3.fromRGB(20, 20, 28)

local function frame(parent: Instance, pos: UDim2, size: UDim2, color: Color3, round: number?, rotation: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rotation or 0
	local c = Instance.new("UICorner")
	if round and round <= 1 then
		c.CornerRadius = UDim.new(round, 0)
	else
		c.CornerRadius = UDim.new(0, round or 3)
	end
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = 2
	s.Parent = f
	f.Parent = parent
	return f
end

local function px(x: number, y: number): UDim2
	return UDim2.fromOffset(x, y)
end

local DRAW: { [string]: (Frame) -> () } = {}

DRAW.cart = function(h)
	local white = Color3.new(1, 1, 1)
	frame(h, px(22, 17), px(24, 14), white, 3)
	frame(h, px(8, 9), px(10, 3), white, 1)
	frame(h, px(13, 18), px(3, 14), white, 1, -20)
	frame(h, px(15, 33), px(6, 6), white, 1)
	frame(h, px(29, 33), px(6, 6), white, 1)
end

DRAW.book = function(h)
	local white = Color3.new(1, 1, 1)
	frame(h, px(20, 21), px(28, 30), white, 3, -12)
	frame(h, px(23, 21), px(22, 26), Color3.fromRGB(220, 230, 240), 2, -12)
	frame(h, px(10, 21), px(4, 30), Color3.fromRGB(90, 100, 120), 1, -12)
end

-- 씨앗: 비스듬한 아몬드 + 가운데 줄 + 반짝
DRAW.seed = function(h)
	frame(h, px(20, 21), px(20, 32), Color3.fromRGB(205, 150, 80), 1, 20)
	frame(h, px(20, 21), px(3, 24), Color3.fromRGB(150, 95, 45), 1, 20)
	frame(h, px(15, 13), px(5, 7), Color3.fromRGB(255, 235, 190), 1, 20).BackgroundTransparency = 0.1
end
DRAW.egg = DRAW.seed

-- 새싹(식물): 흙 + 줄기 + 잎 두 장
DRAW.plant = function(h)
	local green = Color3.fromRGB(90, 200, 80)
	frame(h, px(20, 33), px(28, 8), Color3.fromRGB(140, 90, 50), 3)
	frame(h, px(20, 22), px(4, 18), Color3.fromRGB(70, 160, 60), 1)
	frame(h, px(12, 14), px(16, 9), green, 1, -30)
	frame(h, px(28, 12), px(16, 9), green, 1, 30)
end
DRAW.paw = DRAW.plant

-- 열매: 빨간 동그라미 + 꼭지 + 잎
DRAW.fruit = function(h)
	frame(h, px(20, 24), px(26, 24), Color3.fromRGB(240, 70, 70), 1)
	frame(h, px(14, 19), px(6, 6), Color3.fromRGB(255, 190, 190), 1).BackgroundTransparency = 0.1
	frame(h, px(20, 10), px(3, 8), Color3.fromRGB(110, 70, 40), 1)
	frame(h, px(26, 9), px(10, 6), Color3.fromRGB(90, 200, 80), 1, -20)
end

DRAW.shoe = function(h)
	local blue = Color3.fromRGB(60, 140, 255)
	frame(h, px(16, 22), px(22, 14), blue, 4, -15)
	frame(h, px(11, 13), px(10, 12), blue, 3, -15)
	frame(h, px(18, 30), px(28, 5), Color3.new(1, 1, 1), 2, -15)
	local plus = frame(h, px(31, 29), px(14, 14), Color3.fromRGB(255, 220, 40), 3)
	frame(plus, px(7, 7), px(8, 3), INK, 0)
	frame(plus, px(7, 7), px(3, 8), INK, 0)
end

-- 코인: 금화 쌓기
DRAW.coin = function(h)
	local gold = Color3.fromRGB(255, 205, 50)
	for i = 0, 2 do
		frame(h, px(20, 31 - i * 6), px(30, 9), gold:Lerp(Color3.new(1, 1, 1), i * 0.08), 1)
	end
	local top = frame(h, px(20, 14), px(22, 22), gold, 1)
	frame(top, px(11, 11), px(10, 10), Color3.fromRGB(255, 235, 140), 1)
end
DRAW.money = DRAW.coin

DRAW.moon = function(h)
	frame(h, px(18, 20), px(26, 26), Color3.fromRGB(240, 240, 250), 1)
	local cut = frame(h, px(25, 15), px(22, 22), Color3.fromRGB(40, 40, 50), 1)
	cut.BackgroundTransparency = 1
	local s = cut:FindFirstChildOfClass("UIStroke")
	if s then
		s.Transparency = 1
	end
	frame(h, px(25, 30), px(26, 12), Color3.fromRGB(90, 95, 110), 1)
end

DRAW.sun = function(h)
	local yellow = Color3.fromRGB(255, 215, 40)
	for i = 0, 3 do
		frame(h, px(20, 20), px(34, 6), yellow, 2, i * 45)
	end
	frame(h, px(20, 20), px(22, 22), yellow, 1)
end

DRAW.trash = function(h)
	local white = Color3.new(1, 1, 1)
	frame(h, px(20, 24), px(20, 22), white, 3)
	frame(h, px(20, 10), px(26, 4), white, 1)
	frame(h, px(20, 6), px(8, 4), white, 1)
	for _, x in { 15, 20, 25 } do
		frame(h, px(x, 24), px(2, 14), Color3.fromRGB(200, 30, 40), 0)
	end
end

DRAW.star = function(h)
	local yellow = Color3.fromRGB(255, 220, 50)
	frame(h, px(20, 21), px(24, 24), yellow, 4, 45)
	frame(h, px(20, 21), px(24, 24), yellow, 4, 0)
end

DRAW.lock = function(h)
	frame(h, px(20, 14), px(16, 16), Color3.fromRGB(200, 200, 210), 1)
	frame(h, px(20, 26), px(24, 18), Color3.fromRGB(255, 200, 50), 3)
end

DRAW.gear = function(h)
	local gray = Color3.fromRGB(200, 200, 210)
	for i = 0, 3 do
		frame(h, px(20, 20), px(34, 8), gray, 2, i * 45)
	end
	frame(h, px(20, 20), px(24, 24), gray, 1)
	frame(h, px(20, 20), px(9, 9), Color3.fromRGB(60, 60, 70), 1)
end

DRAW.gift = function(h)
	frame(h, px(20, 25), px(30, 20), Color3.fromRGB(240, 60, 70), 3)
	frame(h, px(20, 13), px(34, 8), Color3.fromRGB(240, 60, 70), 2)
	frame(h, px(20, 20), px(6, 30), Color3.fromRGB(255, 220, 60), 1)
end

DRAW.scroll = function(h)
	frame(h, px(20, 20), px(24, 28), Color3.fromRGB(255, 240, 200), 3)
	frame(h, px(20, 7), px(32, 6), Color3.fromRGB(190, 130, 70), 2)
	frame(h, px(20, 33), px(32, 6), Color3.fromRGB(190, 130, 70), 2)
end

DRAW.sell = function(h)
	frame(h, px(20, 20), px(30, 30), Color3.fromRGB(255, 210, 50), 1)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Theme.Font
	t.TextScaled = true
	t.Text = "C"
	t.TextColor3 = Color3.fromRGB(170, 110, 20)
	t.Parent = h
end

DRAW.trail = function(h)
	for i = 0, 2 do
		frame(
			h,
			px(14 + i * 6, 22 - i * 4),
			px(26, 6),
			Color3.fromRGB(200, 120, 255):Lerp(Color3.new(1, 1, 1), i * 0.2),
			2,
			-20
		)
	end
end

-- size = 화면 기준 한 변 (그림은 40 기준으로 그리고 UIScale 로 맞춤)
function Icons.draw(kind: string, parent: Instance, size: number?, position: UDim2?, anchor: Vector2?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(40, 40)
	holder.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	holder.Position = position or UDim2.fromScale(0.5, 0.5)
	local scale = Instance.new("UIScale")
	scale.Scale = (size or 40) / 40
	scale.Parent = holder
	local fn = DRAW[kind]
	if fn then
		fn(holder)
	end
	holder.Parent = parent
	return holder
end

function Icons.has(kind: string): boolean
	return DRAW[kind] ~= nil
end

return Icons
