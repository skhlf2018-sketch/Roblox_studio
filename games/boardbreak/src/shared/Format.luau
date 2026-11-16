--!strict
--[[
	Format — 큰 숫자/시간 표시 (순수 로직, 첫 게임 Format 을 복사해 단위를 1e63 까지 늘림)
	  Format.number(16000000) → "16M", Format.number(1.5e24) → "1.5Sp", Format.money(1500) → "1.5K",
	  Format.duration(5400) → "1h 30m"
	단위 (1000 배마다): K M B T Qa Qi Sx Sp Oc No Dc Ud Dd Td Qad Qid Sxd Spd Ocd Nod Vg
	  (1e3 … 1e63). 그보다 크면 "1.5e66" 처럼 지수로.
]]

local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
}

local Format = {}

Format.SUFFIXES = SUFFIXES

local function trimZeros(text: string): string
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

function Format.number(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	local value = math.abs(n)
	if value == math.huge then
		return if negative then "-inf" else "inf"
	end
	local tier = 1
	if value >= 1000 then
		-- 한 번에 나눔 (1000 으로 여러 번 나누면 1e29 → 99.99… 처럼 오차가 쌓여 "99.9Oc" 가 됨). 작은 여유를 더해 내림 오차를 막음
		tier = math.min(#SUFFIXES, math.floor(math.log10(value) / 3 + 1e-12) + 1)
		value = value / 10 ^ (3 * (tier - 1)) * (1 + 1e-12)
		if value < 1 and tier > 1 then
			tier -= 1
			value *= 1000
		end
	end
	if value >= 1000 then
		-- 단위를 넘어선 수: 지수로 (1.5e66)
		local exponent = math.floor(math.log10(math.abs(n)))
		local mantissa = math.abs(n) / 10 ^ exponent
		local m = trimZeros(string.format("%.2f", math.floor(mantissa * 100) / 100))
		return (if negative then "-" else "") .. m .. "e" .. tostring(exponent)
	end
	local text: string
	if tier == 1 then
		text = tostring(math.floor(value))
	elseif value >= 100 then
		text = string.format("%d", math.floor(value))
	elseif value >= 10 then
		text = string.format("%.1f", math.floor(value * 10) / 10)
	else
		text = string.format("%.2f", math.floor(value * 100) / 100)
	end
	return (if negative then "-" else "") .. trimZeros(text) .. SUFFIXES[tier]
end

-- 돈 (단위만, "코인" 같은 말은 붙이지 않음 — 화면에서 돈 아이콘을 붙임)
function Format.money(n: number): string
	return Format.number(n)
end

-- 1,024 처럼 세 자리마다 쉼표 (작은 수 표시용, 1e15 이상이면 Format.number)
function Format.comma(n: number): string
	if n ~= n or math.abs(n) >= 1e15 then
		return Format.number(n)
	end
	local negative = n < 0
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if negative then "-" else "") .. out
end

function Format.duration(seconds: number): string
	local s = math.max(0, math.ceil(if seconds ~= seconds then 0 else seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then
		return if m > 0 then string.format("%dh %dm", h, m) else string.format("%dh", h)
	elseif m > 0 then
		return if sec > 0 then string.format("%dm %ds", m, sec) else string.format("%dm", m)
	end
	return string.format("%ds", sec)
end

return Format
