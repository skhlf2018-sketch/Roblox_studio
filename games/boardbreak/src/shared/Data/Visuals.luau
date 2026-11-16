--!strict
--[[
	Visuals — 겉모습 숫자 표 (선임). 아우라 단계 문턱은 띠가 아니라 힘의 크기(자릿수)로.
	  Visuals.AURA = { { power, name, color, rate, size, light } … } (단계 1 부터, 힘 < 첫 문턱이면 단계 0 = 아우라 없음)
	  Visuals.auraTier(power) → 0 ~ #AURA
	마지막 단계(무지개·우주)는 게임 끝 힘 근처: 6단 띠 추천 힘 3.68e38 과 9단 띠(그랜드 마스터) 1.67e43 사이 1e39.
	파티클 Rate 는 폰을 위해 단계당 8~30 (플레이어당 합 상한 Visuals.AURA_RATE_CAP = 60).
]]

export type Aura = {
	power: number,
	name: string,
	color: Color3,
	color2: Color3,
	rate: number,
	size: number,
	light: number,
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Visuals = {}

Visuals.AURA_RATE_CAP = 60

Visuals.AURA = {
	{
		power = 100,
		name = "옅은 흰 기운",
		color = c(255, 255, 255),
		color2 = c(220, 230, 255),
		rate = 8,
		size = 0.25,
		light = 0,
	},
	{
		power = 1e4,
		name = "파랑",
		color = c(70, 150, 255),
		color2 = c(170, 210, 255),
		rate = 10,
		size = 0.3,
		light = 0.6,
	},
	{
		power = 1e7,
		name = "초록",
		color = c(60, 220, 110),
		color2 = c(180, 255, 190),
		rate = 12,
		size = 0.32,
		light = 0.8,
	},
	{
		power = 1e10,
		name = "노랑",
		color = c(255, 225, 60),
		color2 = c(255, 250, 180),
		rate = 14,
		size = 0.35,
		light = 1,
	},
	{
		power = 1e14,
		name = "주황",
		color = c(255, 140, 30),
		color2 = c(255, 210, 120),
		rate = 16,
		size = 0.38,
		light = 1.2,
	},
	{
		power = 1e18,
		name = "빨강",
		color = c(255, 50, 50),
		color2 = c(255, 160, 120),
		rate = 18,
		size = 0.4,
		light = 1.4,
	},
	{
		power = 1e24,
		name = "보라",
		color = c(170, 70, 255),
		color2 = c(230, 170, 255),
		rate = 22,
		size = 0.45,
		light = 1.6,
	},
	{
		power = 1e31,
		name = "금색 번쩍",
		color = c(255, 200, 40),
		color2 = c(255, 255, 255),
		rate = 26,
		size = 0.5,
		light = 2,
	},
	{
		power = 1e39,
		name = "무지개 우주",
		color = c(255, 80, 200),
		color2 = c(80, 220, 255),
		rate = 30,
		size = 0.55,
		light = 2.4,
	},
} :: { Aura }

function Visuals.auraTier(power: number?): number
	local p = tonumber(power) or 0
	if p ~= p then
		return 0
	end
	local tier = 0
	for i, a in Visuals.AURA do
		if p >= a.power then
			tier = i
		end
	end
	return tier
end

function Visuals.aura(tier: number): Aura?
	return Visuals.AURA[tier]
end

return Visuals
