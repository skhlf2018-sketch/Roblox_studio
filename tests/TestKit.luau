--!nocheck
--[[
	TestKit — 아주 작은 테스트 도구 (Lune 전용)
]]

local TestKit = {}

local passed = 0
local failed = 0
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
	if failed > 0 then
		print("\n실패 목록:")
		for _, f in failures do
			print("  - " .. f)
		end
	end
	return failed
end

return TestKit
