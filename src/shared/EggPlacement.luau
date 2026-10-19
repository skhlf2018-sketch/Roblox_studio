--!strict
--[[
	EggPlacement — 우리 안에 알 놓기 규칙 (2판 수정, 순수 로직 → Lune 테스트 대상)

	서버 PlaceEgg 검증(BaseService), 저장 데이터 보정(DataSchema), 클라 미리보기(선임: 놓을 자리가 초록/빨강)
	셋이 같은 함수를 씁니다. 좌표는 전부 베이스 기준(로컬) — MapLayout.toLocal / toWorld.

	놓을 수 있는 자리 (check):
	  1) 우리 안: MapLayout.isInPenLocal(lx, lz, EGG_PLACE_FENCE_MARGIN) — 울타리에서 2 안쪽까지
	  2) 다른 놓인 알과 간격 ≥ gap(두 알 크기) = max(EGG_PLACE_SPACING 4, 두 알 지름의 평균)
	  3) 우리에 서 있는 펫과 간격 ≥ EGG_PLACE_SPACING 4
	  (놓인 알 수 < PLACED_EGG_MAX 는 서버가 따로 확인 — reason "full")

	firstFreeGrid: MapLayout.eggGridLocal 1번부터 놓을 수 있는 첫 자리 (저장 데이터 위치가 깨졌을 때·옛 슬롯 변환)
]]

local Config = require(script.Parent.Data.Config)
local MapLayout = require(script.Parent.Data.MapLayout)
local Sizes = require(script.Parent.Data.Sizes)

export type Spot = { x: number, z: number, size: string? }
export type Reason = "full" | "outside" | "tooClose"

local EggPlacement = {}

-- 알 지름 (스터드) = EGG_BASE_DIAMETER × 크기 배율 (모르는 크기는 보통)
function EggPlacement.diameter(sizeId: string?): number
	local size = if sizeId then Sizes.get(sizeId) else nil
	return Config.EGG_BASE_DIAMETER * (if size then size.eggScale else 1)
end

-- 두 알 가운데 사이 최소 거리
function EggPlacement.gap(sizeA: string?, sizeB: string?): number
	return math.max(Config.EGG_PLACE_SPACING, (EggPlacement.diameter(sizeA) + EggPlacement.diameter(sizeB)) / 2)
end

-- 저장·비교용으로 0.1 스터드 단위로 반올림
function EggPlacement.round(v: number): number
	return math.round(v * 10) / 10
end

-- (lx, lz) 에 sizeId 알을 놓을 수 있나. placed = 이미 놓인 알 {x, z, size}, pets = 우리 펫 {x, z}
function EggPlacement.check(
	lx: number,
	lz: number,
	sizeId: string?,
	placed: { Spot },
	pets: { Spot }?
): (boolean, Reason?)
	if not MapLayout.isInPenLocal(lx, lz, Config.EGG_PLACE_FENCE_MARGIN) then
		return false, "outside"
	end
	for _, other in placed do
		local dx, dz = lx - other.x, lz - other.z
		if math.sqrt(dx * dx + dz * dz) < EggPlacement.gap(sizeId, other.size) then
			return false, "tooClose"
		end
	end
	local petSpots: { Spot } = pets or {}
	for _, pet in petSpots do
		local dx, dz = lx - pet.x, lz - pet.z
		if math.sqrt(dx * dx + dz * dz) < Config.EGG_PLACE_SPACING then
			return false, "tooClose"
		end
	end
	return true, nil
end

-- 격자 자리(MapLayout.eggGridLocal) 중 놓을 수 있는 첫 자리 (없으면 nil)
function EggPlacement.firstFreeGrid(sizeId: string?, placed: { Spot }): MapLayout.XZ?
	for i = 1, MapLayout.EGG_GRID_COUNT do
		local spot = MapLayout.eggGridLocal(i)
		if spot and EggPlacement.check(spot.x, spot.z, sizeId, placed) then
			return spot
		end
	end
	return nil
end

-- 거부 이유(Reason) → 안내 글 (Notify)
function EggPlacement.message(reason: string?): string
	if reason == "full" then
		return string.format(
			"우리에는 알을 %d개까지 놓을 수 있어요. 다 자란 알을 먼저 부화시키세요!",
			Config.PLACED_EGG_MAX
		)
	elseif reason == "outside" then
		return "알은 내 우리(울타리) 안에만 놓을 수 있어요!"
	elseif reason == "tooClose" then
		return "다른 알이나 펫과 너무 가까워요. 조금 떨어진 곳에 놓아 주세요!"
	end
	return "여기에는 알을 놓을 수 없어요."
end

return EggPlacement
