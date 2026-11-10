--!strict
--[[
	Products — 로벅스 개발자 상품 표 (9판, 사장님 2026-11-10) — 순수 데이터

	- 구매창은 클라가 MarketplaceService:PromptProductPurchase(player, product.productId) 로 엶 (선임).
	  서버로 "사 줘" 하는 Remote 는 없음 (위조 방지) — 돈을 받으면 로블록스가 서버 ProcessReceipt 를 부르고,
	  서버 ProductService 가 지급 → ProductGranted { key, kind } + Snapshot section.
	- productId 는 아래 **Products.IDS 한 곳**에만 적음. 0 = 아직 Creator Dashboard 에서 안 만듦 (Products.isConfigured = false
	  → 클라는 "준비 중"). 아빠가 상품을 만들고 받은 id 숫자를 여기 붙여 넣으면 끝 (docs/ROBUX_SETUP.md).

	kind (효과는 서버 ProductService.grant):
	  - "treadmillBoost": 러닝머신 부스트 ×value (영구). 산 것 중 **가장 큰 배수**만 적용 (곱이 아님).
	      러닝머신 1초 이득 = 레벨 이득 × 트레일 배율 × 부스트 (러닝머신 탈 때만, 걷는 속도 배수 아님)
	  - "treadmillSkip": 러닝머신을 value 레벨로 바로 올림 (코인 안 듦). 지금 레벨 + 1 = value 일 때 파는 상품
	  - "coins": 코인 +value · "speed": 속도 +value
	  - "moneyPass": 코인 2배 (영원히) — 열매 판매·성체 팔기 코인 × value(2)
	가격(로벅스): 부스트 = 배수와 같은 숫자 · 러닝머신 레벨 = TREADMILL_SKIP_ROBUX (18~20레벨은 [추정]) · 상점 5개
]]

local Config = require(script.Parent.Config)

export type Product = { key: string, kind: string, name: string, robux: number, productId: number, value: number? }

local Kinds = {
	treadmillBoost = "treadmillBoost",
	treadmillSkip = "treadmillSkip",
	coins = "coins",
	speed = "speed",
	moneyPass = "moneyPass",
}

-- ★ 아빠가 Creator Dashboard → Monetization → Developer Products 에서 만든 상품 id 를 여기에 붙여 넣기 (0 = 아직 없음)
local IDS: { [string]: number } = {
	-- 러닝머신 부스트 (영구)
	boost_2 = 0,
	boost_4 = 0,
	boost_8 = 0,
	boost_16 = 0,
	boost_32 = 0,
	boost_64 = 0,
	boost_128 = 0,
	boost_256 = 0,
	boost_512 = 0,
	boost_1024 = 0,
	boost_2048 = 0,
	-- 러닝머신 레벨 바로 올리기 (tskip_N = N레벨로)
	tskip_1 = 0,
	tskip_2 = 0,
	tskip_3 = 0,
	tskip_4 = 0,
	tskip_5 = 0,
	tskip_6 = 0,
	tskip_7 = 0,
	tskip_8 = 0,
	tskip_9 = 0,
	tskip_10 = 0,
	tskip_11 = 0,
	tskip_12 = 0,
	tskip_13 = 0,
	tskip_14 = 0,
	tskip_15 = 0,
	tskip_16 = 0,
	tskip_17 = 0,
	tskip_18 = 0,
	tskip_19 = 0,
	tskip_20 = 0,
	-- 상점 창
	money_pass = 0,
	coins_1m = 0,
	coins_1b = 0,
	speed_10m = 0,
	speed_100m = 0,
}

-- 러닝머신 부스트 배수 (= 로벅스 가격)
local BOOST_MULTIPLIERS: { number } = { 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048 }

-- 러닝머신 N레벨로 올리기 가격 (N = 1 ~ 20). 18~20레벨(15000·20000 앞뒤)은 [추정] — 사장님 "끝까지 쭉"
local TREADMILL_SKIP_ROBUX: { number } = {
	3,
	10,
	30,
	50,
	100,
	399,
	599,
	799,
	1099,
	1599,
	1999,
	2599,
	3900,
	5000,
	6000,
	8000,
	10000,
	12000, -- [추정] 18레벨
	15000, -- [추정] 19레벨
	20000, -- [추정] 20레벨
}

local function make(key: string, kind: string, name: string, robux: number, value: number?): Product
	return { key = key, kind = kind, name = name, robux = robux, productId = IDS[key] or 0, value = value }
end

local list: { Product } = {}
local byKey: { [string]: Product } = {}
local byId: { [number]: Product } = {}
local treadmillBoosts: { Product } = {}
local treadmillSkips: { Product } = {}
local shop: { Product } = {}

local function add(group: { Product }, product: Product)
	table.insert(group, product)
	table.insert(list, product)
	byKey[product.key] = product
	if product.productId > 0 then
		byId[product.productId] = product
	end
end

for _, multiplier in BOOST_MULTIPLIERS do
	add(
		treadmillBoosts,
		make(`boost_{multiplier}`, Kinds.treadmillBoost, `러닝머신 부스트 x{multiplier}`, multiplier, multiplier)
	)
end

for level, robux in TREADMILL_SKIP_ROBUX do
	local name = if level == 1 then "러닝머신 열기 (1레벨)" else `러닝머신 {level}레벨로 올리기`
	add(treadmillSkips, make(`tskip_{level}`, Kinds.treadmillSkip, name, robux, level))
end

add(shop, make("money_pass", Kinds.moneyPass, "코인 2배 (영원히)", 199, Config.MONEY_PASS_MULTIPLIER))
add(shop, make("coins_1m", Kinds.coins, "코인 1M", 99, 1e6))
add(shop, make("coins_1b", Kinds.coins, "코인 1B", 199, 1e9))
add(shop, make("speed_10m", Kinds.speed, "속도 10M", 199, 1e7))
add(shop, make("speed_100m", Kinds.speed, "속도 100M", 259, 1e8))

local Products = {
	Kinds = Kinds,
	IDS = IDS,
	list = list,
	byKey = byKey,
	treadmillBoosts = treadmillBoosts,
	treadmillSkips = treadmillSkips,
	shop = shop,
	BOOST_MULTIPLIERS = BOOST_MULTIPLIERS,
	TREADMILL_SKIP_ROBUX = TREADMILL_SKIP_ROBUX,
	-- 러닝머신 레벨 가격 중 [추정] 한 레벨 (사장님이 안 정해 준 숫자 — 문서·보고용)
	ESTIMATED_SKIP_LEVELS = { 18, 19, 20 } :: { number },
}

function Products.get(key: string): Product?
	return byKey[key]
end

-- ProcessReceipt 의 receipt.ProductId → 상품 (0·음수·모르는 id = nil)
function Products.byProductId(id: number): Product?
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return byId[id]
end

-- 지금 러닝머신 레벨의 "다음 레벨로 올리기" 상품 (0레벨 → tskip_1, 최대 레벨이면 nil)
function Products.nextTreadmillSkip(level: number): Product?
	local nextLevel = math.floor(level) + 1
	if nextLevel < 1 then
		nextLevel = 1
	end
	return treadmillSkips[nextLevel]
end

-- 러닝머신 레벨 상품을 지금 레벨에서 샀을 때 받는 것 (순수 — 서버 ProductService.grant 가 씀):
--   (새 레벨, 남은 로벅스). 남은 로벅스는 서버가 속도로 바꿔 줌 (× Config.PRODUCT_SPEED_PER_ROBUX).
--   - 레벨이 N-1 이면 N (값 그대로, 남는 것 0)
--   - 안 맞으면 (창이 늦게 바뀜·두 번 누름·위조 클라 — 주임 F-3): 예산 = 그 상품 로벅스. 지금 레벨의 다음 레벨 가격부터
--     차례로 빼며 살 수 있는 만큼만 올림 (한 칸도 못 사면 0칸), 남은 예산은 속도로. 최대 레벨이면 전부 속도.
--     → 싼 상품(tskip_1, 3 R$)을 여러 번 사서 비싼 레벨을 얻을 수 없음. 예산 > 0 이라 "돈 받고 0 지급"도 없음
function Products.treadmillSkipOutcome(level: number, product: Product): (number, number)
	local maxLevel = #treadmillSkips
	local current = if level == level then math.clamp(math.floor(level), 0, maxLevel) else 0
	local target = math.floor(product.value or 0)
	if current == target - 1 and target >= 1 and target <= maxLevel then
		return target, 0
	end
	local budget = math.max(0, product.robux)
	while current < maxLevel do
		local price = treadmillSkips[current + 1].robux
		if price > budget then
			break
		end
		budget -= price
		current += 1
	end
	return current, budget
end

-- Creator Dashboard 에서 만든 id 가 붙어 있나 (false 면 클라는 "준비 중")
function Products.isConfigured(product: Product): boolean
	return product.productId > 0
end

return Products
