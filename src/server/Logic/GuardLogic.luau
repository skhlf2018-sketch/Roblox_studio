--!strict
--[[
	GuardLogic — 경비 판단 계산 (순수 로직, Lune 테스트 대상). 실제 적용은 Services/GuardianService.

	1) 비켜 가기 (경비끼리 겹치지 않게): 다른 경비가 minDistance 보다 가까우면 그 반대쪽으로 밀어 주는 오프셋.
	   거대한 경비가 다른 구역을 지나갈 때 그 구역에서 자는 경비 몸을 뚫고 지나가지 않게.
	2) 추격이 끝난 이유: "caught"(잡음) | "safe"(허브에 들어감 = 배달) | "dropped"(알을 놓음) | "night"(밤) | "other"
	3) 잡힘 거리: 거대 경비일수록 조금 멀리서 잡음 (catchDistance) · 이름표 높이 (labelOffset)
	4) 빠른 추격 (2판 수정, 걷기 최대 150 → 0.1초 틱마다 15 스터드씩 움직임):
	   - leadPoint: 목표를 "플레이어 위치 + 이동 속도 × 몇 초" 앞으로 → MoveTo 가 0.1초 전 자리에 먼저 도착해 멈추지 않음
	   - closestApproach: 틱 사이 (플레이어 - 경비) 상대 위치가 가장 가까웠던 거리 (8판: 잡힘 판정은 시간이라 참고용)
	5) 8판 잡힘 시간: crossedForward(다음 구역 경계를 넘었나) · rushWalkSpeed(마지막 0.3초 따라붙는 속도)
	6) 65번 깨어나는 시간: isWaking(둥지에서 집은 시각, 지금, 1.78초) — 그동안 그 사람은 안 쫓고 닿아도 안 잡음
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

-- 추격 대상을 놓친 이유 (우선순위: 밤 → 허브 → 알 없음 → 기타)
-- 2판 수정: 허브에 들어오는 순간 배달(알이 가방으로)되므로, 배달이 경비 틱보다 먼저 처리돼 알이 없어졌어도 "safe"
function GuardLogic.endReason(isDay: boolean, stillCarrying: boolean, inHub: boolean): EndReason
	if not isDay then
		return "night"
	end
	if inHub then
		return "safe"
	end
	if not stillCarrying then
		return "dropped"
	end
	return "other"
end

-- 추격 목표 = (px, pz) + 속도 (vx, vz) × lead 초. 속도 크기는 maxSpeed 까지만 (순간이동·튕김으로 목표가 튀지 않게)
function GuardLogic.leadPoint(
	px: number,
	pz: number,
	vx: number,
	vz: number,
	lead: number,
	maxSpeed: number
): (number, number)
	local speed = math.sqrt(vx * vx + vz * vz)
	if speed ~= speed or speed < 1e-6 or lead ~= lead or lead <= 0 then
		return px, pz
	end
	local scale = math.min(speed, math.max(0, maxSpeed)) / speed * lead
	return px + vx * scale, pz + vz * scale
end

-- 8판: 다음 구역 경계를 넘었나 (z ≥ 그 구역 zMax). 도망칠 수 없는 사람이 넘으면 즉시 잡힘
function GuardLogic.crossedForward(z: number, zoneZMax: number): boolean
	return z == z and z >= zoneZMax
end

-- 8판: 잡히기 마지막 순간(남은 remaining 초) 경비가 따라붙는 WalkSpeed = 남은 거리 ÷ 남은 시간 (base ~ maxSpeed 사이).
-- 이상한 값(NaN·음수)이면 base
function GuardLogic.rushWalkSpeed(distance: number, remaining: number, base: number, maxSpeed: number): number
	if distance ~= distance or remaining ~= remaining or distance <= 0 then
		return base
	end
	local needed = distance / math.max(remaining, 0.05)
	return math.clamp(needed, base, math.max(base, maxSpeed))
end

-- 65번 (사장님 2026-11-10 "훔치고 1.78초 후에 쫓아오게"): 둥지에서 stolenAt 에 집은 씨앗을 든 사람에 대해 경비가 아직
-- 자는 중인가 (now - stolenAt < wakeSeconds). stolenAt = nil(바닥에서 주움)이거나 이상한 값(NaN)이면 false = 바로 평소 규칙
function GuardLogic.isWaking(stolenAt: number?, now: number, wakeSeconds: number): boolean
	if stolenAt == nil or stolenAt ~= stolenAt or now ~= now or wakeSeconds ~= wakeSeconds then
		return false
	end
	-- 주임 K-1: 집은 시각이 미래·무한이면 (경과 < 0) 영원히 자는 중이 되지 않게 — 자는 중 아님
	local elapsed = now - stolenAt
	if elapsed < 0 then
		return false
	end
	-- 1e-6 = os.clock 소수 오차 (정확히 1.78초가 지난 틱은 깬 것으로)
	return elapsed < wakeSeconds - 1e-6
end

-- 상대 위치가 (ax, az) → (bx, bz) 로 곧게 움직였을 때 원점(경비)에 가장 가까웠던 거리
-- (a = 지난 틱 "플레이어 - 경비", b = 이번 틱). 이상한 값이 섞이면 NaN → 잡힘 판정은 false
function GuardLogic.closestApproach(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 1e-12 then
		t = math.clamp(-(ax * dx + az * dz) / len2, 0, 1)
	end
	local cx, cz = ax + dx * t, az + dz * t
	return math.sqrt(cx * cx + cz * cz)
end

return GuardLogic
