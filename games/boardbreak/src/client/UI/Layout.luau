--!strict
--[[
	Layout — 화면 크기에 맞춘 HUD 자리 계산 (첫 게임 Layout 을 줄여 복사 + 송판 깨기 큰 버튼). 숫자만 → 테스트하기 쉬움.
	좌표는 "화면 영역" 픽셀 (ScreenGui 안쪽, 위쪽 로블록스 메뉴 인셋 아래부터 0).
	  Layout.menu(area, count, hudScale, touch, maxRight?, topLimit?, bottom?) → 왼쪽 메뉴 버튼 크기·열 수·시작 위치
	  Layout.menuRect(plan, k)        → k번째(0부터) 버튼 자리
	  Layout.joystickZone / jumpZone  → 로블록스 터치 조이스틱·점프 버튼 자리 (PlayerModule 규칙)
	  Layout.statsRect(area, s, touch) → 힘·돈·띠 묶음 (PC 왼쪽 아래 / 터치 위 왼쪽 한 줄)
	  Layout.actionRect(area, s, touch, slot) → 큰 "들기"(slot 0) · "치기"(slot 1) 버튼
	      PC: 아래 가운데 (나란히) / 터치: 오른쪽, 점프 버튼 위 (조이스틱·점프와 안 겹침), 화면에서 46px 이상
	  Layout.topPanel(area, s, touch, w, h) → 위 가운데 패널 (튜토리얼·심사 진행). 터치는 위 한 줄 아래
]]

local Layout = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type MenuPlan = {
	x: number,
	y: number,
	size: number,
	gap: number,
	cols: number,
	rows: number,
	scale: number,
}

Layout.MENU_BASE = 72
Layout.MENU_GAP = 8
Layout.MIN_TOUCH = 46 -- 손가락 최소 (화면 픽셀) — 송판 깨기는 46
Layout.SAFE_TOP = 8
Layout.SIDE = 10
Layout.SMALL_SCREEN = 500
Layout.COMPACT_HEIGHT = 480
Layout.BADGE_OVERHANG = 9

Layout.STATS_W = 340
Layout.STATS_H = 150 -- PC (3줄: 힘 · 돈 · 띠)
Layout.STATS_TOUCH_W = 600
Layout.STATS_TOUCH_H = 48 -- 터치 (한 줄)
Layout.ACTION_BASE = 132 -- 큰 버튼 기준 지름 (PC)
Layout.ACTION_TOUCH = 104 -- 터치 화면 픽셀 지름 (배율 안 받음 — 손가락 크기)

local function small(area: Vector2): boolean
	return math.min(area.X, area.Y) <= Layout.SMALL_SCREEN
end

function Layout.joystickSize(area: Vector2): number
	return if small(area) then 130 else 200
end

function Layout.joystickZone(area: Vector2): Rect
	local s = Layout.joystickSize(area)
	return { x = 0, y = area.Y - s, w = s, h = s }
end

function Layout.jumpZone(area: Vector2): Rect
	if small(area) then
		return { x = area.X - 95, y = area.Y - 90, w = 70, h = 70 }
	end
	return { x = area.X - 170, y = area.Y - 210, w = 120, h = 120 }
end

function Layout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

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
		local scale = math.ceil(size / Layout.MENU_BASE * 10000) / 10000
		local top = math.max(Layout.SAFE_TOP, minTop, math.ceil(Layout.BADGE_OVERHANG * scale) + 2)
		local height = rows * size + (rows - 1) * gap
		local y = top + math.max(0, math.floor((bottomLimit - top - height) / 2))
		return { x = Layout.SIDE, y = y, size = size, gap = gap, cols = cols, rows = rows, scale = scale }
	end

	for cols = 1, 3 do
		local rows = math.ceil(n / cols)
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
	return plan(3, Layout.MIN_TOUCH)
end

function Layout.menuCell(plan: MenuPlan, k: number): (number, number)
	return k // plan.rows, k % plan.rows
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

function Layout.statsRect(area: Vector2, hudScale: number, touch: boolean): Rect
	if touch then
		return { x = 10, y = 4, w = Layout.STATS_TOUCH_W * hudScale, h = Layout.STATS_TOUCH_H * hudScale }
	end
	local h = Layout.STATS_H * hudScale
	return { x = 10, y = area.Y - 8 - h, w = Layout.STATS_W * hudScale, h = h }
end

-- 큰 "들기"(0) · "치기"(1) 버튼 자리 (화면 픽셀, 정사각형)
function Layout.actionRect(area: Vector2, hudScale: number, touch: boolean, slot: number): Rect
	if touch then
		local size = math.max(Layout.MIN_TOUCH, Layout.ACTION_TOUCH)
		local jump = Layout.jumpZone(area)
		local gap = 12
		-- 점프 버튼 바로 위 (화면 오른쪽), slot 1 은 그 왼쪽
		local x = area.X - 14 - size - slot * (size + gap)
		local y = jump.y - gap - size
		if y < 60 then
			y = 60
		end
		return { x = x, y = y, w = size, h = size }
	end
	local size = math.max(Layout.MIN_TOUCH, math.floor(Layout.ACTION_BASE * hudScale))
	local gap = 24
	local cx = area.X / 2 + (slot - 0.5) * (size + gap)
	return { x = cx - size / 2, y = area.Y - 26 - size, w = size, h = size }
end

-- 위 가운데 패널 (튜토리얼·심사 진행). w, h = 기준 크기
function Layout.topPanel(area: Vector2, hudScale: number, touch: boolean, w: number, h: number): Rect
	local sw, sh = w * hudScale, h * hudScale
	local top = if touch then math.ceil(4 + Layout.STATS_TOUCH_H * hudScale + 6) else 8
	return { x = (area.X - sw) / 2, y = top, w = sw, h = sh }
end

return Layout
