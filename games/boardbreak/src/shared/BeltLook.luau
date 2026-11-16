--!strict
--[[
	BeltLook — 띠 천 색 (선임, 사장님 결정 16번). 화면(띠 창 · 왼쪽 아래 띠 칩)과 도장 띠 표지판(서버)이 같은 규칙.
	  BeltLook.colors(belt)   → { Color3 } 1~6개, 왼쪽 → 오른쪽. 표의 belt.colors (수석, 1~3 RGB) · 없으면 { belt.color }
	                            무지개 띠(id "rainbow")는 무지개 6색 전체.
	  BeltLook.sequence(belt) → ColorSequence (색마다 띠를 고르게 나누고 경계만 살짝 섞음 — 태극 띠가 보라로 뭉개지지 않게)
	  BeltLook.paint(frame, belt) → frame 을 그 띠 색으로 (한 색이면 BackgroundColor3, 여러 색이면 흰 바탕 + UIGradient "BeltGradient")
	유튜브 띠는 이름 + 빨강·흰색 천만 (로고·재생 버튼 그림 없음 — 사장님 결정 16번 지시).
]]

local BeltLook = {}

BeltLook.RAINBOW = {
	Color3.fromRGB(230, 50, 50),
	Color3.fromRGB(245, 140, 40),
	Color3.fromRGB(250, 215, 50),
	Color3.fromRGB(70, 190, 90),
	Color3.fromRGB(60, 120, 230),
	Color3.fromRGB(150, 80, 210),
}
BeltLook.BLEND = 0.06 -- 색 경계에서 섞는 폭 (띠 길이의 비율)

local function rgb(t: any): Color3?
	if type(t) == "table" and type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number" then
		return Color3.fromRGB(t[1], t[2], t[3])
	end
	return nil
end

function BeltLook.colors(belt: any): { Color3 }
	if type(belt) ~= "table" then
		return { Color3.new(1, 1, 1) }
	end
	if belt.id == "rainbow" then
		return table.clone(BeltLook.RAINBOW)
	end
	local out: { Color3 } = {}
	if type(belt.colors) == "table" then
		for _, t in belt.colors do
			local c = rgb(t)
			if c then
				table.insert(out, c)
			end
		end
	end
	if #out == 0 then
		table.insert(out, rgb(belt.color) or Color3.new(1, 1, 1))
	end
	return out
end

function BeltLook.sequence(belt: any): ColorSequence
	local list = BeltLook.colors(belt)
	local n = #list
	if n == 1 then
		return ColorSequence.new(list[1])
	end
	local keys: { ColorSequenceKeypoint } = {}
	local blend = BeltLook.BLEND
	for i, c in list do
		local a = (i - 1) / n
		local b = i / n
		local from = if i == 1 then 0 else a + blend / 2
		local to = if i == n then 1 else b - blend / 2
		table.insert(keys, ColorSequenceKeypoint.new(from, c))
		table.insert(keys, ColorSequenceKeypoint.new(to, c))
	end
	return ColorSequence.new(keys)
end

function BeltLook.paint(frame: GuiObject, belt: any)
	local list = BeltLook.colors(belt)
	local old = frame:FindFirstChild("BeltGradient")
	if #list == 1 then
		frame.BackgroundColor3 = list[1]
		if old then
			old:Destroy()
		end
		return
	end
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	local g: UIGradient
	if old and old:IsA("UIGradient") then
		g = old
	else
		g = Instance.new("UIGradient")
		g.Name = "BeltGradient"
		g.Parent = frame
	end
	g.Color = BeltLook.sequence(belt)
	g.Rotation = 0
end

-- 띠 위 글자 색 (밝은 띠 = 어두운 글자): 색들의 평균 밝기
function BeltLook.isLight(belt: any): boolean
	local list = BeltLook.colors(belt)
	local sum = 0
	for _, c in list do
		sum += c.R * 0.3 + c.G * 0.59 + c.B * 0.11
	end
	return sum / #list > 0.7
end

return BeltLook
