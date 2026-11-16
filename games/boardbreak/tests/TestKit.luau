--!nocheck
--[[
	TestKit — 아주 작은 테스트 도구 (Lune 전용)
]]

local TestKit = {}

local passed = 0
local failed = 0
local skipped = 0
local failures = {}
local currentSuite = ""

local function fmt(v)
	if typeof(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

function TestKit.suite(name)
	currentSuite = name
	print("\n== " .. name)
end

function TestKit.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		table.insert(failures, currentSuite .. " > " .. name .. "\n      " .. tostring(err))
		print("  FAIL " .. name .. "\n      " .. tostring(err))
	end
end

-- 진짜 버그를 잡았지만 아직 고쳐지지 않은 테스트 ("알려진 버그" — 실패해도 전체를 빨갛게 만들지 않음).
--   fn 이 있으면 돌려 봄: 아직 실패하면 SKIP(버그 그대로), 통과하면 "고쳐졌어요" 안내 (그때 T.skip 을 T.test 로 바꾸세요).
--   fn 이 없으면 이유만 남김. 어느 쪽이든 통과/실패 개수에는 안 셈.
function TestKit.skip(name, reason, fn)
	skipped += 1
	if fn then
		local ok, err = pcall(fn)
		if ok then
			print(
				"  FIXED? "
					.. name
					.. "\n      (이제 통과해요! 고쳐진 것 같으니 T.skip 을 T.test 로 바꿔 주세요)"
			)
			return
		end
		print(
			"  SKIP "
				.. name
				.. "\n      (알려진 버그 재현됨 — "
				.. tostring(reason)
				.. ")\n      그때 실패 내용: "
				.. tostring(err)
		)
		return
	end
	print("  SKIP " .. name .. "\n      (알려진 버그 — " .. tostring(reason) .. ")")
end

function TestKit.eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: 기대 %s, 실제 %s", msg or "eq", fmt(expected), fmt(actual)), 2)
	end
end

function TestKit.near(actual, expected, tolerance, msg)
	if typeof(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		error(
			string.format("%s: 기대 %s ± %s, 실제 %s", msg or "near", fmt(expected), fmt(tolerance), fmt(actual)),
			2
		)
	end
end

function TestKit.truthy(value, msg)
	if not value then
		error((msg or "truthy") .. ": 값이 거짓", 2)
	end
end

function TestKit.falsy(value, msg)
	if value then
		error((msg or "falsy") .. ": 값이 참 (" .. fmt(value) .. ")", 2)
	end
end

-- 고정 시드 난수 (LCG) → [0, 1)
function TestKit.rng(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- 항상 같은 값을 돌려주는 가짜 난수
function TestKit.constant(value)
	return function()
		return value
	end
end

function TestKit.summary()
	print(string.format("\n결과: %d 통과, %d 실패", passed, failed))
	if skipped > 0 then
		print(string.format("건너뜀(알려진 버그, T.skip): %d", skipped))
	end
	if failed > 0 then
		print("\n실패 목록:")
		for _, f in failures do
			print("  - " .. f)
		end
	end
	return failed
end

return TestKit
