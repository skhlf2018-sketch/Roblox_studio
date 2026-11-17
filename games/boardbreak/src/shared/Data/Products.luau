--!strict
--[[
	Products — 송판 깨기 로벅스 상품 표 (설계서 5장) — 순수 데이터. 첫 게임 Products 를 줄여 복사.

	게임패스 12개 (전부 isPass = true, 영구, 한 번만 삼):
	  - power_2 … power_2048 (11개, kind "powerBoost"): 힘 ×value — 아령으로 오르는 힘과 칠 때 깎는 힘 둘 다.
	      **순서대로만 열림** (2배를 사야 4배). 가진 것 중 가장 큰 배수 하나만 (곱이 아님). 가격 = 배수 로벅스 (사장님 확인)
	  - money_2 (kind "moneyPass"): 깬 돈 2배 (199 로벅스, 사장님)
	구매창은 클라 MarketplaceService:PromptGamePassPurchase(player, productId). ProcessReceipt 는 안 옴 →
	서버 ProductService 가 UserOwnsGamePassAsync 로 소유를 확인해서 반영 (접속할 때 syncPasses + PromptGamePassPurchaseFinished
	— 구매 끝 신호가 와도 서버가 다시 확인). 서버로 "사 줘" 하는 Remote 는 없음 (위조 방지).

	id 는 아래 IDS 한 곳에만 — 2026-11-17 게시한 체험 (universe 10777294360 · place 87244998186948) 에 만든 진짜 게임패스 12개.
	Products.isConfigured(product) = id 가 있나 (없으면 화면 "준비 중" — 지금은 12개 전부 있음). 개발 명령 /buy <key> 로도 시험.
]]

local Config = require(script.Parent.Config)

export type Product = {
	key: string,
	kind: string,
	name: string,
	robux: number,
	productId: number,
	value: number?,
	isPass: boolean,
}

local Kinds = {
	powerBoost = "powerBoost",
	moneyPass = "moneyPass",
}

-- ★ 게임패스 id (Creator Dashboard → Monetization → Passes 의 Pass ID)
--   2026-11-17 게시한 체험 (universe 10777294360) 에 Open Cloud 로 만든 진짜 id — 바꾸지 말 것
local IDS: { [string]: number } = {
	power_2 = 2092088488,
	power_4 = 2092238475,
	power_8 = 2094368437,
	power_16 = 2092472455,
	power_32 = 2092538462,
	power_64 = 2093432475,
	power_128 = 2092700472,
	power_256 = 2092844452,
	power_512 = 2093798444,
	power_1024 = 2092364442,
	power_2048 = 2093090450,
	money_2 = 2093966468,
}

-- 힘 배수 (= 로벅스 가격)
local BOOST_MULTIPLIERS: { number } = { 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048 }

local list: { Product } = {}
local byKey: { [string]: Product } = {}
local byId: { [number]: Product } = {} -- 개발자 상품만 (지금은 없음 — ProcessReceipt 는 늘 "모르는 상품")
local byPass: { [number]: Product } = {} -- 게임패스만
local boostByValue: { [number]: Product } = {}
local powerBoosts: { Product } = {}
local passes: { Product } = {}

local function add(product: Product)
	table.insert(list, product)
	byKey[product.key] = product
	if product.isPass then
		table.insert(passes, product)
	end
	if product.productId > 0 then
		if product.isPass then
			byPass[product.productId] = product
		else
			byId[product.productId] = product
		end
	end
end

for _, multiplier in BOOST_MULTIPLIERS do
	local product: Product = {
		key = `power_{multiplier}`,
		kind = Kinds.powerBoost,
		name = `힘 {multiplier}배`,
		robux = multiplier,
		productId = IDS[`power_{multiplier}`] or 0,
		value = multiplier,
		isPass = true,
	}
	add(product)
	table.insert(powerBoosts, product)
	boostByValue[multiplier] = product
end

local moneyPass: Product = {
	key = "money_2",
	kind = Kinds.moneyPass,
	name = "돈 2배 (영원히)",
	robux = 199,
	productId = IDS.money_2 or 0,
	value = Config.MONEY_PASS_MULTIPLIER,
	isPass = true,
}
add(moneyPass)

local Products = {
	Kinds = Kinds,
	IDS = IDS,
	list = list,
	byKey = byKey,
	powerBoosts = powerBoosts,
	-- 게임패스 12개 (힘 배수 11 + money_2, 표 순서)
	passes = passes,
	BOOST_MULTIPLIERS = BOOST_MULTIPLIERS,
	MAX_BOOST = BOOST_MULTIPLIERS[#BOOST_MULTIPLIERS],
}

function Products.get(key: string): Product?
	if type(key) ~= "string" then
		return nil
	end
	return byKey[key]
end

-- ProcessReceipt 의 receipt.ProductId → 개발자 상품만 (지금은 없음 → 언제나 nil)
function Products.byProductId(id: number): Product?
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return byId[id]
end

-- PromptGamePassPurchaseFinished 의 gamePassId → 게임패스만 (0·음수·모르는 id = nil)
function Products.byPassId(id: number): Product?
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return byPass[id]
end

-- 지금 배수 바로 다음 힘 배수 상품 (1 → power_2, 2 → power_4 …, 2048 이면 nil). 이것 하나만 살 수 있음
function Products.nextPowerBoost(current: number): Product?
	local now = if type(current) == "number" and current == current then current else 1
	for _, product in powerBoosts do
		if (product.value or 0) > now then
			return product
		end
	end
	return nil
end

-- 카드 상태 (순수 — 화면이 씀): "active" 지금 적용 중 · "owned" 이미 지나온 배수 · "buy" 바로 다음 · "locked" 앞의 것을 먼저
function Products.powerBoostState(current: number, value: number): string
	local now = if type(current) == "number" and current == current then current else 1
	if value == now then
		return "active"
	elseif value < now then
		return "owned"
	end
	local nextProduct = Products.nextPowerBoost(now)
	if nextProduct and nextProduct.value == value then
		return "buy"
	end
	return "locked"
end

-- 힘 배수 상품을 지금 배수에서 받았을 때 새 배수 (개발 명령 /buy · 시험용 grant). 바로 다음 배수면 그 배수.
-- 순서가 안 맞으면 그 상품 로벅스만큼만 — 다음 배수부터 차례로 가격을 빼며 올릴 수 있는 데까지 (건너뛰기 없음)
function Products.powerBoostOutcome(current: number, product: Product): number
	local now = if type(current) == "number" and current == current then math.max(1, current) else 1
	local nextProduct = Products.nextPowerBoost(now)
	if nextProduct and nextProduct.key == product.key then
		return nextProduct.value or now
	end
	local budget = math.max(0, product.robux)
	for _ = 1, #powerBoosts do
		local step = Products.nextPowerBoost(now)
		if not step or step.robux > budget then
			break
		end
		budget -= step.robux
		now = step.value or now
	end
	return now
end

-- 가진 힘 배수 게임패스들로 정해지는 배수 (첫 게임 boostFromOwnedPasses 와 같음 — 서버 ProductService.syncPasses 가 씀).
--   웹에서 순서를 건너뛰어 샀어도 "2배를 사야 4배" + 낸 값만큼: 예산 = 가진 패스 가격 합, 2배부터 차례로 빼며 올림.
--   예: {2,4,8} → 8 · {2048} → 1024 · {4} → 2 · {} → 1 · {2,8} → 4. 중복·모르는 값·NaN 은 무시
function Products.boostFromOwnedPasses(ownedMultipliers: { number }): number
	local budget = 0
	local counted: { [Product]: boolean } = {}
	if type(ownedMultipliers) == "table" then
		for _, multiplier in ownedMultipliers do
			if type(multiplier) == "number" and multiplier == multiplier then
				local product = boostByValue[multiplier]
				if product and not counted[product] then
					counted[product] = true
					budget += product.robux
				end
			end
		end
	end
	local now = 1
	for _, product in powerBoosts do
		if product.robux > budget then
			break
		end
		budget -= product.robux
		now = product.value or now
	end
	return now
end

-- 올바른 힘 배수인가 (1 또는 표의 배수)
function Products.isValidBoost(value: number): boolean
	return value == 1 or boostByValue[value] ~= nil
end

-- id 가 붙어 있나 (false 면 화면은 "준비 중" — 지금은 12개 전부 true)
function Products.isConfigured(product: Product): boolean
	return product.productId > 0
end

return Products
