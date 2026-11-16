--!strict
--[[
	Validate — Remote 인자 검사 (순수 로직, Lune 테스트 대상)
	클라가 보낸 값은 전부 unknown 으로 받고 여기서 좁힙니다. 실패하면 nil.
]]

local Validate = {}

local MAX_ID_LENGTH = 48

-- 펫/알 uid: 영문·숫자·_·- 만, 1~48자
function Validate.uid(value: unknown): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local s = value :: string
	if #s == 0 or #s > MAX_ID_LENGTH then
		return nil
	end
	if not string.match(s, "^[%w_%-]+$") then
		return nil
	end
	return s
end

-- 데이터 id (petId, trailId 등): uid 와 같은 규칙 + 허용 목록 확인
function Validate.idIn(value: unknown, allowed: { [string]: any }): string?
	local s = Validate.uid(value)
	if s and allowed[s] ~= nil then
		return s
	end
	return nil
end

-- 정해진 문자열 중 하나
function Validate.oneOf(value: unknown, options: { [string]: string }): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local s = value :: string
	for _, option in options do
		if option == s then
			return s
		end
	end
	return nil
end

-- 유한한 숫자 (NaN, inf 거부)
function Validate.finiteNumber(value: unknown): number?
	if typeof(value) ~= "number" then
		return nil
	end
	local n = value :: number
	if n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

return Validate
