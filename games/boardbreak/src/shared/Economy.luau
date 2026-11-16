--!strict
--[[
	Economy — 송판 깨기 힘·돈 계산 (순수 로직, Lune 테스트 대상). 설계서 5장·6장.

	  한 번 들 때 오르는 힘 = 아령 powerPerRep × PowerBoost              (Economy.trainGain)
	  한 번 칠 때 깎는 체력 = 저장된 힘(Power) × PowerBoost              (Economy.hitDamage)
	      → PowerBoost 는 **들 때와 칠 때 둘 다** 곱함 (설계서 5장). 물건 체력도 이 "치는 힘"만큼 깎임 (힘 문턱 없음)
	  깬 돈 = 물건 reward × 띠 moneyMultiplier × (돈 2배 패스면 2)         (Economy.breakReward)
	모든 수는 NaN·음수·무한을 0(또는 1)으로 막고, 힘·돈은 1e60(Config.POWER_MAX · MONEY_MAX)에서 멈춤.
]]

local Config = require(script.Parent.Data.Config)
local Dumbbells = require(script.Parent.Data.Dumbbells)
local Belts = require(script.Parent.Data.Belts)
local Products = require(script.Parent.Data.Products)

local Economy = {}

-- 쓸 수 있는 0 이상 유한수로 (NaN·무한·음수·숫자 아님 → 0), 상한 maxValue
function Economy.sanitize(value: unknown, maxValue: number?): number
	if typeof(value) ~= "number" then
		return 0
	end
	local n = value :: number
	if n ~= n or n < 0 or n == math.huge then
		return 0
	end
	local cap = maxValue or math.huge
	if n > cap then
		return cap
	end
	return n
end

-- 힘 배수 (1 또는 표의 배수 2 … 2048 만. 이상한 값 → 1)
function Economy.boost(value: unknown): number
	if typeof(value) == "number" and Products.isValidBoost(value :: number) then
		return value :: number
	end
	return 1
end

function Economy.clampPower(value: unknown): number
	return Economy.sanitize(value, Config.POWER_MAX)
end

function Economy.clampMoney(value: unknown): number
	return Economy.sanitize(value, Config.MONEY_MAX)
end

-- 아령 1번 들 때 오르는 힘
function Economy.trainGain(dumbbellLevel: number, powerBoost: number): number
	local dumbbell = Dumbbells.get(dumbbellLevel) or Dumbbells.list[1]
	return Economy.clampPower(dumbbell.powerPerRep * Economy.boost(powerBoost))
end

-- 힘 더하기 (1e60 에서 멈춤)
function Economy.addPower(power: number, gain: number): number
	return Economy.clampPower(Economy.clampPower(power) + Economy.clampPower(gain))
end

-- 한 번 칠 때 깎는 체력 (= 치는 힘)
function Economy.hitDamage(power: number, powerBoost: number): number
	return Economy.clampPower(Economy.clampPower(power) * Economy.boost(powerBoost))
end

-- 띠의 돈 배율 (모르는 띠 → 1)
function Economy.beltMultiplier(belt: number): number
	local b = Belts.get(belt)
	return if b then b.moneyMultiplier else 1
end

-- 깬 돈
function Economy.breakReward(reward: number, belt: number, moneyPass: boolean): number
	local passMultiplier = if moneyPass == true then Config.MONEY_PASS_MULTIPLIER else 1
	return Economy.clampMoney(Economy.clampMoney(reward) * Economy.beltMultiplier(belt) * passMultiplier)
end

-- 돈 더하기 (1e60 에서 멈춤)
function Economy.addMoney(money: number, amount: number): number
	return Economy.clampMoney(Economy.clampMoney(money) + Economy.clampMoney(amount))
end

-- 체력 hp 를 damage 로 몇 번 쳐야 깨지나 (damage 0 이면 math.huge)
function Economy.hitsToBreak(hp: number, damage: number): number
	local h = Economy.clampPower(hp)
	local d = Economy.clampPower(damage)
	if d <= 0 then
		return math.huge
	end
	return math.max(1, math.ceil(h / d))
end

return Economy
