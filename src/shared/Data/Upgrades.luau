--!strict
--[[
	Upgrades — 베이스 업그레이드 (설계문서 9장 표 그대로)

	- Pen: 우리 레벨 → 장착 칸 수. level 1 은 무료(시작 상태)
	- Treadmill: 러닝머신 레벨 → 한 걸음당 속도(원본). level 0 = 잠김, level 1 구매 = 해금($1K)
	  실제 증가량은 Economy.treadmillGainPerSecond (× GROWTH_MULTIPLIER)
	- Trails: 속도 배율. 중첩 아님 — 가진 것 중 가장 높은 배율 하나만 적용 [추정]
]]

export type PenLevel = { level: number, cost: number, slots: number }
export type TreadmillLevel = { level: number, cost: number, perStep: number }
export type Trail = {
	id: string,
	order: number,
	name: string,
	nameEn: string,
	multiplier: number,
	cost: number,
	color: { number },
}

local K = 1e3
local M = 1e6
local B = 1e9
local T = 1e12
local Qa = 1e15

local Pen: { PenLevel } = {
	{ level = 1, cost = 0, slots = 7 },
	{ level = 2, cost = 1 * K, slots = 8 },
	{ level = 3, cost = 1 * M, slots = 9 },
	{ level = 4, cost = 75 * M, slots = 10 },
	{ level = 5, cost = 1 * B, slots = 11 },
	{ level = 6, cost = 15 * B, slots = 12 },
	{ level = 7, cost = 200 * B, slots = 13 },
	{ level = 8, cost = 2.5 * T, slots = 14 },
	{ level = 9, cost = 30 * T, slots = 15 },
	{ level = 10, cost = 400 * T, slots = 16 },
	{ level = 11, cost = 5 * Qa, slots = 18 },
}

local Treadmill: { TreadmillLevel } = {
	{ level = 1, cost = 1 * K, perStep = 2 }, -- 해금 비용 $1,000
	{ level = 2, cost = 15 * K, perStep = 5 },
	{ level = 3, cost = 250 * K, perStep = 12 },
	{ level = 4, cost = 5 * M, perStep = 30 },
	{ level = 5, cost = 120 * M, perStep = 80 },
	{ level = 6, cost = 3 * B, perStep = 100 },
	{ level = 7, cost = 75 * B, perStep = 200 },
	{ level = 8, cost = 2 * T, perStep = 500 },
	{ level = 9, cost = 50 * T, perStep = 1000 },
	{ level = 10, cost = 1 * Qa, perStep = 2000 },
}

local Trails: { Trail } = {
	{ id = "grey", order = 1, name = "회색", nameEn = "Grey", multiplier = 1.5, cost = 100, color = { 150, 150, 150 } },
	{ id = "green", order = 2, name = "초록", nameEn = "Green", multiplier = 2, cost = 5 * K, color = { 80, 200, 80 } },
	{ id = "blue", order = 3, name = "파랑", nameEn = "Blue", multiplier = 2.5, cost = 75 * K, color = { 60, 120, 255 } },
	{
		id = "purple",
		order = 4,
		name = "보라",
		nameEn = "Purple",
		multiplier = 3,
		cost = 1.5 * M,
		color = { 160, 80, 230 },
	},
	{
		id = "golden",
		order = 5,
		name = "황금",
		nameEn = "Golden",
		multiplier = 3.5,
		cost = 30 * M,
		color = { 255, 200, 40 },
	},
	{ id = "red", order = 6, name = "빨강", nameEn = "Red", multiplier = 4, cost = 750 * M, color = { 230, 40, 40 } },
	{
		id = "galaxy",
		order = 7,
		name = "은하",
		nameEn = "Galaxy",
		multiplier = 5,
		cost = 20 * B,
		color = { 90, 60, 200 },
	},
	{
		id = "secret",
		order = 8,
		name = "비밀",
		nameEn = "Secret",
		multiplier = 7,
		cost = 500 * B,
		color = { 20, 20, 20 },
	},
	{
		id = "eternal",
		order = 9,
		name = "영원",
		nameEn = "Eternal",
		multiplier = 10,
		cost = 12.5 * T,
		color = { 40, 220, 210 },
	},
	{
		id = "divine",
		order = 10,
		name = "신성",
		nameEn = "Divine",
		multiplier = 14,
		cost = 300 * T,
		color = { 255, 120, 220 },
	},
	{
		id = "moonbloom",
		order = 11,
		name = "문블룸",
		nameEn = "Moonbloom",
		multiplier = 20,
		cost = 5 * Qa,
		color = { 200, 210, 255 },
	},
}

local trailById: { [string]: Trail } = {}
for _, trail in Trails do
	trailById[trail.id] = trail
end

local Upgrades = {
	Pen = Pen,
	Treadmill = Treadmill,
	Trails = Trails,
	trailById = trailById,
	PEN_MAX_LEVEL = #Pen,
	TREADMILL_MAX_LEVEL = #Treadmill,
}

function Upgrades.getTrail(id: string): Trail?
	return trailById[id]
end

return Upgrades
