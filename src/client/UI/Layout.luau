--!strict
--[[
	Layout — 화면 크기에 맞춘 HUD 자리 계산 (서비스 안 씀, 숫자만 → 테스트하기 쉬움)

	좌표는 전부 "화면 영역" 픽셀 (ScreenGui 안쪽, 위쪽 로블록스 메뉴 인셋 아래부터 0).
	  Layout.menu(area, count, hudScale, touch)    → 왼쪽 메뉴: 버튼 크기·간격·열 수·시작 위치
	  Layout.menuRect(plan, k)                     → k번째(0부터) 버튼 자리
	  Layout.hotbar(area, count, hudScale, touch, leftLimit, jump?) → 핫바 오른쪽·아래 여백, 배율
	  Layout.jumpZone(area)                         → 터치 점프 버튼 자리 (PlayerModule TouchJump 규칙)
	  Layout.joystickZone(area)                     → 터치 조이스틱 자리 (왼쪽 아래 정사각형)

	규칙 (docs/UI.md 4-2):
	  - 메뉴 버튼은 화면에서 44px 이상. 위는 y ≥ 8 (배지가 안 잘리게 조금 더), 아래는 PC 8px / 터치는 조이스틱 위.
	  - 1열로 안 들어가면(버튼이 44px 보다 작아져야 하면) 2열 → 3열. 열이 늘면 버튼은 다시 HUD 크기까지 커짐.
	    단 여러 열일 때는 위쪽 돈·속도 막대 왼쪽 끝(maxRight)을 넘지 않게 버튼을 줄임.
	  - 높이 480 미만이면 간격 4px.
	  - 터치 기기의 핫바는 점프 버튼 왼쪽에, 조이스틱과 안 겹치게. 칸이 많으면 배율을 줄임(칸 44px 까지).
]]

local Layout = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type MenuPlan = {
	x: number,
	y: number,
	size: number, -- 버튼 한 변 (화면 픽셀)
	gap: number, -- 버튼 사이 (화면 픽셀)
	cols: number,
	rows: number,
	scale: number, -- 기준 72px → size 배율 (메뉴 UIScale)
}
export type HotbarPlan = {
	right: number, -- 화면 오른쪽에서 핫바 오른쪽 끝까지
	bottom: number, -- 화면 아래에서 핫바 아래 끝까지
	scale: number, -- 핫바 UIScale
	baseWidth: number, -- 칸 수에 맞춘 기준 너비
}

Layout.MENU_BASE = 72 -- 메뉴 버튼 기준 크기 (HudController 가 그림을 이 크기로 그림)
Layout.MENU_GAP = 8 -- 기준 간격
Layout.MIN_TOUCH = 44 -- 손가락 최소 (화면 픽셀)
Layout.SAFE_TOP = 8
Layout.SIDE = 10
Layout.SMALL_SCREEN = 500 -- 짧은 변이 이 이하면 폰 (PlayerModule 과 같은 기준)
Layout.COMPACT_HEIGHT = 480
Layout.BADGE_OVERHANG = 9 -- Ui.badge 가 버튼 위로 튀어나오는 기준 픽셀 (중심 6, 반지름 15)

Layout.SLOT = 64 -- 핫바 칸 기준 크기 (2판: 원작처럼 작은 칸)
Layout.SLOT_GAP = 8
Layout.HOTBAR_HEIGHT = 70
Layout.HOTBAR_MARGIN = 10

local function small(area: Vector2): boolean
	return math.min(area.X, area.Y) <= Layout.SMALL_SCREEN
end

-- 터치 조이스틱(왼쪽 아래)이 차지하는 정사각형 한 변
function Layout.joystickSize(area: Vector2): number
	return if small(area) then 130 else 200
end

function Layout.joystickZone(area: Vector2): Rect
	local s = Layout.joystickSize(area)
	return { x = 0, y = area.Y - s, w = s, h = s }
end

-- 로블록스 기본 점프 버튼 (PlayerModule TouchJump): 폰 70px, 태블릿 120px
function Layout.jumpZone(area: Vector2): Rect
	if small(area) then
		return { x = area.X - 95, y = area.Y - 90, w = 70, h = 70 }
	end
	return { x = area.X - 170, y = area.Y - 210, w = 120, h = 120 }
end

function Layout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- maxRight: 메뉴 오른쪽 끝 한계 (위쪽 돈·속도 막대의 왼쪽 끝). 2열이 막대 밑으로 파고들지 않게
function Layout.menu(
	area: Vector2,
	count: number,
	hudScale: number,
	touch: boolean,
	maxRight: number?,
	topLimit: number?,
	bottomOverride: number?
): MenuPlan
	local n = math.max(count, 1)
	local normal = math.floor(Layout.MENU_BASE * hudScale)
	local compact = area.Y < Layout.COMPACT_HEIGHT
	local gap = if compact then 4 else math.max(4, math.floor(Layout.MENU_GAP * hudScale))
	local bottomLimit = if touch then area.Y - Layout.joystickSize(area) - 4 else area.Y - 8
	if bottomOverride then
		bottomLimit = math.min(bottomLimit, bottomOverride)
	end
	local minTop = topLimit or 0

	local function plan(cols: number, size: number): MenuPlan
		local rows = math.ceil(n / cols)
		-- 살짝 올림: UIScale 은 float32 라 44/72 가 43.999px 로 줄어드는 것 방지
		local scale = math.ceil(size / Layout.MENU_BASE * 10000) / 10000
		local top = math.max(Layout.SAFE_TOP, minTop, math.ceil(Layout.BADGE_OVERHANG * scale) + 2)
		local height = rows * size + (rows - 1) * gap
		local y = top + math.max(0, math.floor((bottomLimit - top - height) / 2))
		return { x = Layout.SIDE, y = y, size = size, gap = gap, cols = cols, rows = rows, scale = scale }
	end

	for cols = 1, 3 do
		local rows = math.ceil(n / cols)
		-- 배지 여백은 버튼 크기에 따라 조금 다름 → 보수적으로 HUD 크기 기준
		local top = math.max(Layout.SAFE_TOP, minTop, math.ceil(Layout.BADGE_OVERHANG * normal / Layout.MENU_BASE) + 2)
		local fit = math.floor(((bottomLimit - top) - (rows - 1) * gap) / rows)
		local size = math.min(normal, fit)
		if maxRight and cols > 1 then
			size = math.min(size, math.floor((maxRight - Layout.SIDE - (cols - 1) * gap) / cols))
		end
		if size >= Layout.MIN_TOUCH then
			return plan(cols, size)
		end
	end
	-- 정말 작은 화면: 3열 44px (넘치더라도 손가락 크기 우선)
	return plan(3, Layout.MIN_TOUCH)
end

-- k: 0부터. 열 먼저 채움 (2열이면 1열에 위 3개, 2열에 아래 3개)
function Layout.menuCell(plan: MenuPlan, k: number): (number, number)
	local col = k // plan.rows
	local row = k % plan.rows
	return col, row
end

function Layout.menuRect(plan: MenuPlan, k: number): Rect
	local col, row = Layout.menuCell(plan, k)
	return {
		x = plan.x + col * (plan.size + plan.gap),
		y = plan.y + row * (plan.size + plan.gap),
		w = plan.size,
		h = plan.size,
	}
end

function Layout.menuWidth(plan: MenuPlan): number
	return plan.cols * plan.size + (plan.cols - 1) * plan.gap
end

-- leftLimit: 핫바가 넘어가면 안 되는 왼쪽 끝 (터치면 조이스틱, PC 면 메뉴 오른쪽)
-- jump: 실제 점프 버튼 자리를 알면 넘김 (없으면 jumpZone 규칙)
function Layout.hotbar(
	area: Vector2,
	count: number,
	hudScale: number,
	touch: boolean,
	leftLimit: number,
	jump: Rect?
): HotbarPlan
	local n = math.max(count, 1)
	local baseWidth = n * Layout.SLOT + (n - 1) * Layout.SLOT_GAP
	local right = Layout.HOTBAR_MARGIN
	local left = leftLimit
	if touch then
		local j = jump or Layout.jumpZone(area)
		right = math.max(right, math.ceil(area.X - j.x) + Layout.HOTBAR_MARGIN)
		left = math.max(left, Layout.joystickSize(area) + 8)
	end
	local room = area.X - right - left
	local scale = hudScale
	if baseWidth * scale > room then
		scale = math.max(Layout.MIN_TOUCH / Layout.SLOT, room / baseWidth)
	end
	return { right = right, bottom = Layout.HOTBAR_MARGIN, scale = scale, baseWidth = baseWidth }
end

function Layout.hotbarRect(area: Vector2, plan: HotbarPlan): Rect
	local w = plan.baseWidth * plan.scale
	local h = Layout.HOTBAR_HEIGHT * plan.scale
	return { x = area.X - plan.right - w, y = area.Y - plan.bottom - h, w = w, h = h }
end

return Layout
