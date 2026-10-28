--!strict
--[[
	Upgrades — 베이스 업그레이드 (설계문서 9장 표 그대로)

	- Pen: 정원 레벨 → 정원 칸 수 (6판: 자라는 씨앗 + 성체 식물, 5판 우리 장착 칸 숫자 그대로). level 1 은 무료(시작 상태)
	- Treadmill: 러닝머신 레벨 → 한 걸음당 속도(원본). level 0 = 잠김, level 1 구매 = 해금(1K 코인)
	  실제 증가량은 Economy.treadmillGainPerSecond = 걸음당 속도 × Config.TREADMILL_MULTIPLIER(4) × 1걸음/초
	  6판 (사장님 추가 지시): 20레벨까지, 최대 레벨이면 1초에 속도 정확히 1,000,000 (250,000 × 4).
	  1~10레벨 숫자는 5판 그대로 (배율만 3 → 4: 1레벨 6 → 8/초), 11~20레벨은 2,000 → 250,000 을 약 1.6배씩,
	  비용은 10레벨(1Qa)부터 약 3배씩 (Format: Qa = 1e15, Qi = 1e18)
	- Trails: 속도 배율. 중첩 아님 — **장착한 트레일 하나**만 적용 (원작 장착/장착 해제 버튼).
	  사면 바로 장착. NO_TRAIL("none") = 장착 안 함 (배율 1)
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
local Qi = 1e18
local Sx = 1e21

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
	{ level = 1, cost = 1 * K, perStep = 2 }, -- 해금 비용 1,000 코인
	{ level = 2, cost = 15 * K, perStep = 5 },
	{ level = 3, cost = 250 * K, perStep = 12 },
	{ level = 4, cost = 5 * M, perStep = 30 },
	{ level = 5, cost = 120 * M, perStep = 80 },
	{ level = 6, cost = 3 * B, perStep = 100 },
	{ level = 7, cost = 75 * B, perStep = 200 },
	{ level = 8, cost = 2 * T, perStep = 500 },
	{ level = 9, cost = 50 * T, perStep = 1000 },
	{ level = 10, cost = 1 * Qa, perStep = 2000 },
	-- 6판: 11 ~ 20레벨 (최대 1초 1M)
	{ level = 11, cost = 3 * Qa, perStep = 3000 },
	{ level = 12, cost = 9 * Qa, perStep = 5000 },
	{ level = 13, cost = 27 * Qa, perStep = 8000 },
	{ level = 14, cost = 80 * Qa, perStep = 12000 },
	{ level = 15, cost = 240 * Qa, perStep = 20000 },
	{ level = 16, cost = 720 * Qa, perStep = 30000 },
	{ level = 17, cost = 2.2 * Qi, perStep = 50000 },
	{ level = 18, cost = 6.5 * Qi, perStep = 80000 },
	{ level = 19, cost = 20 * Qi, perStep = 150000 },
	{ level = 20, cost = 60 * Qi, perStep = 250000 },
}

local Trails: { Trail } = {
	{
		id = "grey",
		order = 1,
		name = "회색",
		nameEn = "Grey",
		multiplier = 1.5,
		cost = 100,
		color = { 150, 150, 150 },
	},
	{
		id = "green",
		order = 2,
		name = "초록",
		nameEn = "Green",
		multiplier = 2,
		cost = 5 * K,
		color = { 80, 200, 80 },
	},
	{
		id = "blue",
		order = 3,
		name = "파랑",
		nameEn = "Blue",
		multiplier = 2.5,
		cost = 75 * K,
		color = { 60, 120, 255 },
	},
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
	-- 사장님 2026-10-28: 트레일 5개 추가 (12~16)
	{
		id = "rainbow",
		order = 12,
		name = "무지개",
		nameEn = "Rainbow",
		multiplier = 28,
		cost = 100 * Qa,
		color = { 255, 120, 200 },
	},
	{
		id = "lava",
		order = 13,
		name = "용암",
		nameEn = "Lava",
		multiplier = 40,
		cost = 2 * Qi,
		color = { 255, 90, 30 },
	},
	{
		id = "starlight",
		order = 14,
		name = "별빛",
		nameEn = "Starlight",
		multiplier = 55,
		cost = 40 * Qi,
		color = { 255, 250, 170 },
	},
	{
		id = "cosmic",
		order = 15,
		name = "우주",
		nameEn = "Cosmic",
		multiplier = 75,
		cost = 800 * Qi,
		color = { 90, 40, 160 },
	},
	{
		id = "super_ultradivine",
		order = 16,
		name = "슈퍼 울트라디바인",
		nameEn = "Super Ultradivine",
		multiplier = 100,
		cost = 15 * Sx,
		color = { 255, 255, 255 },
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
	NO_TRAIL = "none", -- 트레일 장착 안 함 (저장 데이터 equippedTrail / EquipTrail Remote 인자)
}

function Upgrades.getTrail(id: string): Trail?
	return trailById[id]
end

return Upgrades
