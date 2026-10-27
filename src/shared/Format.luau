--!strict
--[[
	Format — 큰 숫자/시간 표시 (순수 로직)
	  Format.number(16000000) → "16M", Format.money(1500) → "1.5K 코인" (6판: 돈 = 코인), Format.duration(5400) → "1h 30m"
	돈 단위: K=천, M=백만, B=십억, T=조, Qa=천조 (설계문서 3장)
]]

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local Format = {}

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
	while value >= 1000 and tier < #SUFFIXES do
		value /= 1000
		tier += 1
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
	-- 1.50 → 1.5, 2.00 → 2
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return (if negative then "-" else "") .. text .. SUFFIXES[tier]
end

function Format.money(n: number): string
	return Format.number(n) .. " 코인"
end

function Format.duration(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
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
