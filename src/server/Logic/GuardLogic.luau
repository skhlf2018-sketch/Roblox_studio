--!strict
--[[
	GuardLogic — 경비 판단 계산 (순수 로직, Lune 테스트 대상). 실제 적용은 Services/GuardianService.

	1) 비켜 가기 (경비끼리 겹치지 않게): 다른 경비가 minDistance 보다 가까우면 그 반대쪽으로 밀어 주는 오프셋.
	   거대한 경비가 다른 구역을 지나갈 때 그 구역에서 자는 경비 몸을 뚫고 지나가지 않게.
	2) 추격이 끝난 이유: "caught"(잡음) | "safe"(허브에 들어감) | "dropped"(알을 놓음·배달) | "night"(밤) | "other"
	3) 잡힘 거리: 거대 경비일수록 조금 멀리서 잡음 (catchDistance) · 이름표 높이 (labelOffset)
]]

export type Point = { x: number, z: number }
export type EndReason = "caught" | "safe" | "dropped" | "night" | "other"

local GuardLogic = {}

-- (x, z) 에 있는 경비를 others 에서 minDistance 만큼 떨어뜨리는 오프셋 (겹친 만큼 바깥으로).
-- 완전히 같은 자리면 +x 쪽으로 민다.
function GuardLogic.separationOffset(x: number, z: number, others: { Point }, minDistance: number): (number, number)
	local ox, oz = 0, 0
	for _, other in others do
		local dx, dz = x - other.x, z - other.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < minDistance then
			local push = minDistance - d
			if d < 1e-6 then
				ox += push
			else
				ox += dx / d * push
				oz += dz / d * push
			end
		end
	end
	return ox, oz
end

-- 잡힘 판정 거리 (수평): base + 경비 키 × factor, 최대 maxDistance. 키가 이상한 값(음수·NaN)이면 0 으로 봄
-- 기본값: Config.GUARD_CATCH_DISTANCE(6) + 키 × 0.25, 최대 16 → 키 8 = 8, 키 28 = 13, 키 40 = 16
function GuardLogic.catchDistance(height: number, base: number, factor: number, maxDistance: number): number
	local h = if height == height and height > 0 then math.min(height, 1e6) else 0
	return math.min(maxDistance, base + h * factor)
end

-- 머리 위 이름표 높이 (머리 가운데 기준 StudsOffset): 경비 겉모습 꼭대기 + margin.
-- height = 바닥에서 겉모습 꼭대기까지, headY = 바닥에서 머리 파트 가운데까지. 작은 경비도 최소 margin 만큼 위
function GuardLogic.labelOffset(height: number, headY: number, margin: number): number
	local h = if height == height and height > 0 then math.min(height, 1e4) else 0
	return math.max(margin, h - headY + margin)
end

-- 추격 대상을 놓친 이유 (우선순위: 밤 → 알 없음 → 허브 → 기타)
function GuardLogic.endReason(isDay: boolean, stillCarrying: boolean, inHub: boolean): EndReason
	if not isDay then
		return "night"
	end
	if not stillCarrying then
		return "dropped"
	end
	if inHub then
		return "safe"
	end
	return "other"
end

return GuardLogic
