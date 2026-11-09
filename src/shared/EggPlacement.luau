--!strict
--[[
	EggPlacement — 정원(5판 우리) 안에 씨앗 심기 규칙 (2판 수정, 순수 로직 → Lune 테스트 대상)
	6판 "씨앗을 훔치세요": 알 → 씨앗, 우리 → 정원, 펫 → 성체 식물 (성체도 심은 자리 x, z 에 그대로 있음)

	서버 PlaceEgg 검증(BaseService), 저장 데이터 보정(DataSchema), 클라 미리보기(선임: 놓을 자리가 초록/빨강)
	셋이 같은 함수를 씁니다. 좌표는 전부 베이스 기준(로컬) — MapLayout.toLocal / toWorld.

	놓을 수 있는 자리 (check):
	  1) 우리 안: MapLayout.isInPenLocal(lx, lz, EGG_PLACE_FENCE_MARGIN) — 울타리에서 2 안쪽까지
	  2) 8판 추가: 거대 식물(GardenRules.isLobbyFill — 해커 글리치)은 정원에 Config.LOBBY_FILL_MAX_PER_GARDEN(1)그루만
	     (placed·pets 에 이미 거대 식물이 그만큼 있으면 reason "giant")
	  3) 다른 자리(자라는 씨앗·성체, placed 와 pets 둘 다)와 간격 ≥ gap(두 자리)
	  (정원 칸 수 = 자라는 씨앗 + 성체 < 정원 칸 수(GardenRules.hasRoom) 는 서버가 따로 확인 — reason "full")

	8판 (사장님 2026-11-08 "등급 높을수록 성체가 크게"): 간격 = 다 자랐을 때 성체 폭 평균까지 (씨앗을 심을 때부터 큰 식물
	  자리를 비워 둠 → 자라서 안 겹침):
	    footprint(식물 id, 크기) = Config.PLANT_FOOTPRINT(2.6) × 간격용 배율(GardenRules.spacingScale = RARITY_PLANT_SCALE 표 1 ~ 6.16
	                                × 크기 배율 1 ~ 1.5) — 8판 추가: 거대 식물도 표 값(6.16)이라 모양(× 16)보다 훨씬 좁게 봄
	    gap(a, b) = min(PLANT_GAP_MAX 14, max(EGG_PLACE_SPACING 4, 씨앗 지름 평균, 성체 폭 평균))
	  → 일반 식물끼리는 7판과 같은 4, 에픽 보통 크기끼리 7.8, 울트라디바인·해커 글리치끼리는 14 (상한)
	    (14 간격 4 × 5 = 20칸이 울타리 2 안쪽 42 × 56 에 들어가서 정원 칸 최대 18 이 언제나 다 들어감).
	  Spot.petId 가 없으면 일반 등급으로 봄 (7판 클라 미리보기 호환 — 선임: placedSpots 에 petId 를 넣고 check 6번째 인자에
	  심을 씨앗의 petId). 저장된 옛 자리는 DataSchema 가 checkSaved(7판 간격)로 그대로 둠 (불러오다 식물이 팔리지 않게 —
	  거대 식물이 여러 그루 저장돼 있어도 그대로).

	firstFreeGrid: 8판 추가 넓은 격자(WIDE_GRID, 14 간격 20칸) → MapLayout.eggGridLocal 1번부터(작은 식물) 놓을 수 있는 첫 자리,
	  없으면 정원을 1 스터드 간격으로 훑어 첫 자리 — 모든 식물이 넓은 격자부터 써서 18칸이 섞어 심어도 다 들어감
	  (저장 데이터 위치가 깨졌을 때·옛 슬롯 변환·개발 명령 /plant·폰 미리보기 첫 자리). 자리(정원 안 + 간격)만 보고
	  거대 식물 1그루 규칙은 안 봄 (저장 데이터 보정이 그 규칙 때문에 식물을 팔지 않게 — 규칙은 check/PlaceEgg 에서)
]]

local Config = require(script.Parent.Data.Config)
local MapLayout = require(script.Parent.Data.MapLayout)
local Sizes = require(script.Parent.Data.Sizes)
local GardenRules = require(script.Parent.GardenRules)

export type Spot = { x: number, z: number, size: string?, petId: string? }
export type Reason = "full" | "outside" | "giant" | "tooClose"

local EggPlacement = {}

-- 알 지름 (스터드) = EGG_BASE_DIAMETER × 크기 배율 (모르는 크기는 보통)
function EggPlacement.diameter(sizeId: string?): number
	local size = if sizeId then Sizes.get(sizeId) else nil
	return Config.EGG_BASE_DIAMETER * (if size then size.eggScale else 1)
end

-- 8판: 다 자란 성체의 바닥 폭 (지름, 스터드) = PLANT_FOOTPRINT × 간격용 배율(GardenRules.spacingScale = 표 등급 × 크기)
--   (petId 가 없으면 일반 등급). 8판 추가: 거대 식물도 표 값(6.16)으로 — 모양은 훨씬 크지만 간격은 PLANT_GAP_MAX 에 묶임
function EggPlacement.footprint(petId: string?, sizeId: string?): number
	return Config.PLANT_FOOTPRINT * GardenRules.spacingScale(petId, sizeId)
end

-- 8판 추가: 이 자리들에 거대 식물(GardenRules.isLobbyFill)이 몇 그루 있나 (자라는 씨앗 + 성체)
function EggPlacement.lobbyFillCount(spots: { Spot }): number
	local n = 0
	for _, s in spots do
		if GardenRules.isLobbyFill(s.petId) then
			n += 1
		end
	end
	return n
end

-- 두 자리 가운데 사이 최소 거리 (8판: 성체 폭 평균까지, 최대 PLANT_GAP_MAX). petA/petB 는 없어도 됨 (일반 등급)
function EggPlacement.gap(sizeA: string?, sizeB: string?, petA: string?, petB: string?): number
	local eggs = (EggPlacement.diameter(sizeA) + EggPlacement.diameter(sizeB)) / 2
	local plants = (EggPlacement.footprint(petA, sizeA) + EggPlacement.footprint(petB, sizeB)) / 2
	return math.min(Config.PLANT_GAP_MAX, math.max(Config.EGG_PLACE_SPACING, eggs, plants))
end

-- 7판 간격 (씨앗 지름만 — 저장된 옛 자리를 그대로 두는 검사, checkSaved)
local function legacyGap(sizeA: string?, sizeB: string?): number
	return math.max(Config.EGG_PLACE_SPACING, (EggPlacement.diameter(sizeA) + EggPlacement.diameter(sizeB)) / 2)
end

-- 저장·비교용으로 0.1 스터드 단위로 반올림
function EggPlacement.round(v: number): number
	return math.round(v * 10) / 10
end

local function tooClose(lx: number, lz: number, gapOf: (Spot) -> number, spots: { Spot }): boolean
	for _, other in spots do
		local dx, dz = lx - other.x, lz - other.z
		if math.sqrt(dx * dx + dz * dz) < gapOf(other) then
			return true
		end
	end
	return false
end

-- 자리만 봄 (정원 안 + 간격) — check 와 firstFreeGrid 가 같이 씀
local function spotFits(
	lx: number,
	lz: number,
	sizeId: string?,
	placed: { Spot },
	pets: { Spot }?,
	petId: string?
): (boolean, Reason?)
	if not MapLayout.isInPenLocal(lx, lz, Config.EGG_PLACE_FENCE_MARGIN) then
		return false, "outside"
	end
	local function gapOf(other: Spot): number
		return EggPlacement.gap(sizeId, other.size, petId, other.petId)
	end
	if tooClose(lx, lz, gapOf, placed) or tooClose(lx, lz, gapOf, pets or {}) then
		return false, "tooClose"
	end
	return true, nil
end

-- (lx, lz) 에 sizeId 씨앗(식물 petId)을 심을 수 있나. placed = 이미 심은 자리 {x, z, size, petId}, pets = 더 넘길 자리
--   순서: 정원 밖 "outside" → 8판 추가: 거대 식물이 이미 LOBBY_FILL_MAX_PER_GARDEN 그루면 "giant" → 간격 "tooClose"
function EggPlacement.check(
	lx: number,
	lz: number,
	sizeId: string?,
	placed: { Spot },
	pets: { Spot }?,
	petId: string?
): (boolean, Reason?)
	if not MapLayout.isInPenLocal(lx, lz, Config.EGG_PLACE_FENCE_MARGIN) then
		return false, "outside"
	end
	if GardenRules.isLobbyFill(petId) then
		local count = EggPlacement.lobbyFillCount(placed) + EggPlacement.lobbyFillCount(pets or {})
		if count >= Config.LOBBY_FILL_MAX_PER_GARDEN then
			return false, "giant"
		end
	end
	return spotFits(lx, lz, sizeId, placed, pets, petId)
end

-- 저장된 자리 검사 (DataSchema): 정원 안 + 7판 간격(씨앗 지름)만 — 8판 큰 식물 간격 때문에 옛 정원의 식물이 팔리지 않게
function EggPlacement.checkSaved(lx: number, lz: number, sizeId: string?, placed: { Spot }): boolean
	if not MapLayout.isInPenLocal(lx, lz, Config.EGG_PLACE_FENCE_MARGIN) then
		return false
	end
	return not tooClose(lx, lz, function(other: Spot): number
		return legacyGap(sizeId, other.size)
	end, placed)
end

-- 격자(eggGridLocal) 줄 간격 — 같은 식물끼리 간격이 이보다 넓으면 격자 대신 울타리 모서리부터 훑음 (큰 식물이 촘촘히)
local GRID_ROW_SPACING = 7

-- 8판 추가 (2026-11-09 크기 곡선 1 → 6): 넓은 격자 = PLANT_GAP_MAX(14) 간격 4 × 5 = 20칸 (울타리 2 안쪽 42 × 56,
--   울타리 쪽 모서리 (9, -28) 부터). 간격은 언제나 14 이하라 이 20칸끼리는 어떤 식물·크기든 안 겹침 → 모든 식물이 여기부터
--   쓰면 정원 칸 최대 18 이 섞어 심어도 **언제나** 다 들어감 (곡선이 커져 에픽 7.8 · 신성 13 처럼 4 ~ 14 사이 간격이 많아서,
--   8판처럼 7 격자 → 1 스터드 훑기만 하면 무작위로 섞은 18그루가 가끔 안 들어감)
local WIDE_GRID: { MapLayout.XZ } = {}
do
	local pen = MapLayout.PEN_LOCAL
	local m = Config.EGG_PLACE_FENCE_MARGIN
	local step = Config.PLANT_GAP_MAX
	local lx = pen.xMax - m
	while lx >= pen.xMin + m - 1e-9 do
		local lz = pen.zMin + m
		while lz <= pen.zMax - m + 1e-9 do
			table.insert(WIDE_GRID, { x = lx, z = lz })
			lz += step
		end
		lx -= step
	end
end
EggPlacement.WIDE_GRID = WIDE_GRID

-- 놓을 수 있는 첫 자리: 8판 추가 넓은 격자(WIDE_GRID 20칸) → 격자 자리(MapLayout.eggGridLocal, 작은 식물만) →
--   정원을 1 스터드 간격으로 훑음 (없으면 nil)
-- 8판: 큰 식물(같은 식물끼리 간격 > 7)은 7 격자를 건너뜀
-- 8판 추가: 자리(정원 안 + 간격)만 봄 — 거대 식물 1그루 규칙은 check(PlaceEgg)에서 (저장 보정이 이 규칙으로 식물을 팔지 않게)
function EggPlacement.firstFreeGrid(sizeId: string?, placed: { Spot }, petId: string?): MapLayout.XZ?
	for _, spot in WIDE_GRID do
		if spotFits(spot.x, spot.z, sizeId, placed, nil, petId) then
			return { x = spot.x, z = spot.z }
		end
	end
	if EggPlacement.gap(sizeId, sizeId, petId, petId) <= GRID_ROW_SPACING then
		for i = 1, MapLayout.EGG_GRID_COUNT do
			local spot = MapLayout.eggGridLocal(i)
			if spot and spotFits(spot.x, spot.z, sizeId, placed, nil, petId) then
				return spot
			end
		end
	end
	local pen = MapLayout.PEN_LOCAL
	local m = Config.EGG_PLACE_FENCE_MARGIN
	for lx = pen.xMax - m, pen.xMin + m, -1 do
		for lz = pen.zMin + m, pen.zMax - m do
			if spotFits(lx, lz, sizeId, placed, nil, petId) then
				return { x = lx, z = lz }
			end
		end
	end
	return nil
end

-- 거부 이유(Reason) → 안내 글 (Notify)
function EggPlacement.message(reason: string?): string
	if reason == "full" then
		return "정원이 가득 찼어요! 성체를 뽑아서 팔거나 정원을 업그레이드하세요."
	elseif reason == "outside" then
		return "씨앗은 내 정원(울타리) 안에만 심을 수 있어요!"
	elseif reason == "giant" then
		return "거대 식물은 정원에 하나만 심을 수 있어요! 지금 있는 거대 식물을 팔거나 집은 뒤에 심어 주세요."
	elseif reason == "tooClose" then
		return "다른 씨앗이나 식물과 너무 가까워요. 큰 식물일수록 넓게 띄워 심어 주세요!"
	end
	return "여기에는 씨앗을 심을 수 없어요."
end

return EggPlacement
