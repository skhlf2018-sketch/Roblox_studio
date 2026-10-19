--!nocheck
-- 치트 방지 2단계: 서버 위치 검증 계산 (server/Logic/MoveCheck)

return function(T, Loader)
	local MoveCheck = Loader.require("ServerScriptService/Server/Logic/MoveCheck")
	local Config = Loader.require("ReplicatedStorage/Shared/Data/Config")

	T.suite("MoveCheck")

	T.test("1초 허용 거리 = WalkSpeed × 1.5 + 30", function()
		T.eq(MoveCheck.allowedDistance(16, 1), 16 * 1.5 + 30)
		T.eq(MoveCheck.allowedDistance(100, 1), 180)
		T.eq(MoveCheck.allowedDistance(100, 2), 330, "서버가 늦게 돌면 경과초만큼")
		T.eq(MoveCheck.allowedDistance(-5, 1), Config.MOVE_CHECK_SLACK)
		T.falsy(MoveCheck.isViolation(54, 16, 1))
		T.truthy(MoveCheck.isViolation(54.1, 16, 1))
		T.falsy(
			MoveCheck.isViolation(Config.SPEED_WALK_MAX, Config.SPEED_WALK_MAX, 1),
			"최대 WalkSpeed(150) 로 1초 달리기는 정상"
		)
		-- 알 든 사람 0.2초 틱도 최대 걷기에서 안 걸림 (150 × 0.2 = 30 < 150 × 0.2 × 1.5 + 8 = 53)
		T.falsy(MoveCheck.isCarryJump(Config.SPEED_WALK_MAX * 0.2, Config.SPEED_WALK_MAX, 0.2))
	end)

	T.test("수평 거리만 (위아래는 안 봄)", function()
		T.eq(MoveCheck.horizontalDistance(0, 0, 3, 4), 5)
	end)

	T.test("알 든 사람 0.2초 틱: WalkSpeed × dt × 1.5 + 8", function()
		T.near(MoveCheck.carryAllowedDistance(50, 0.2), 50 * 0.2 * 1.5 + 8, 1e-9)
		T.falsy(MoveCheck.isCarryJump(10, 50, 0.2), "정상 이동")
		T.truthy(MoveCheck.isCarryJump(200, 50, 0.2), "순간이동")
	end)

	T.test("배달 최소 시간 = 거리 ÷ (WalkSpeed × 1.3)", function()
		T.eq(MoveCheck.minTravelSeconds(1300, 50), 20)
		T.truthy(MoveCheck.isTooFastDelivery(1300, 5, 50))
		T.falsy(MoveCheck.isTooFastDelivery(1300, 30, 50))
		T.falsy(MoveCheck.isTooFastDelivery(0, 0, 50), "제자리 배달")
		T.eq(MoveCheck.minTravelSeconds(100, 0), 100 / Config.DELIVERY_TIME_SPEED_FACTOR, "WalkSpeed 최소 1")
	end)

	T.test("경고 5개면 Kick, 시간이 지나면 1개씩 줄어듦", function()
		local w = MoveCheck.newWarnings(0)
		for i = 1, Config.MOVE_CHECK_KICK_WARNINGS - 1 do
			local count, kick = MoveCheck.addWarning(w, i)
			T.eq(count, i)
			T.falsy(kick)
		end
		local _, kick = MoveCheck.addWarning(w, 5)
		T.truthy(kick)

		local d = MoveCheck.newWarnings(0)
		MoveCheck.addWarning(d, 0)
		MoveCheck.addWarning(d, 1)
		MoveCheck.decay(d, Config.MOVE_CHECK_WARNING_DECAY_SECONDS + 1)
		T.eq(d.count, 1)
		MoveCheck.decay(d, Config.MOVE_CHECK_WARNING_DECAY_SECONDS * 10)
		T.eq(d.count, 0)
		local count = MoveCheck.addWarning(d, Config.MOVE_CHECK_WARNING_DECAY_SECONDS * 10 + 1)
		T.eq(count, 1, "다 줄어든 뒤 새로 시작")
	end)
end
