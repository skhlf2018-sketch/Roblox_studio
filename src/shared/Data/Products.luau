--!strict
--[[
	Products — 로벅스 상품 표 (9판, 사장님 2026-11-10) — 순수 데이터

	사장님 2026-11-10 (62번): "영구적인 것은 게임패스, 소모품은 개발자 상품"
	  - 게임패스 12개 (isPass = true, 한 번만 삼): boost_2 … boost_2048 (11) + money_pass
	      구매창 MarketplaceService:PromptGamePassPurchase(player, productId) (클라 Purchase). ProcessReceipt 는 안 옴 →
	      서버 ProductService 가 UserOwnsGamePassAsync 로 소유를 확인해서 반영 (접속할 때 syncPasses + PromptGamePassPurchaseFinished)
	  - 개발자 상품 24개 (isPass = false, 소모품): tskip_1 … tskip_20, coins_1m, coins_1b, speed_10m, speed_100m
	      구매창 MarketplaceService:PromptProductPurchase(player, productId). 돈을 받으면 로블록스가 서버 ProcessReceipt 를 부르고,
	      서버 ProductService 가 지급 → ProductGranted { key, kind } + Snapshot section.
	  서버로 "사 줘" 하는 Remote 는 없음 (위조 방지).
	- id 는 아래 **Products.IDS 한 곳**에만 적음 (product.productId 칸 — 패스면 그 숫자가 gamePassId, 상품이면 developer productId).
	  0 = 아직 Creator Dashboard 에서 안 만듦 (Products.isConfigured = false → 클라는 "준비 중").
	  아빠가 만들고 받은 id 숫자를 여기 붙여 넣으면 끝 (docs/ROBUX_SETUP.md). 패스 id 와 상품 id 를 섞지 말 것.
	- Products.byProductId(id) = 개발자 상품만 (패스 id 를 넣으면 nil — 영수증으로 패스를 지급하는 일이 없게),
	  Products.byPassId(id) = 패스만.

	kind (효과는 서버 ProductService.grant):
	  - "treadmillBoost" [게임패스]: 러닝머신 부스트 ×value (영구, 웹에서 건너뛰어 산 패스는 낸 값만큼만 — boostFromOwnedPasses). 산 것 중 **가장 큰 배수**만 적용 (곱이 아님).
	      **순서대로만 열림** (2배를 사야 4배가 열림 — Products.nextTreadmillBoost · treadmillBoostState · treadmillBoostOutcome)
	      러닝머신 1초 이득 = 레벨 이득 × 트레일 배율 × 부스트 (러닝머신 탈 때만, 걷는 속도 배수 아님)
	  - "treadmillSkip": 러닝머신을 value 레벨로 바로 올림 (코인 안 듦). 지금 레벨 + 1 = value 일 때 파는 상품
	  - "coins": 코인 +value · "speed": 속도 +value
	  - "moneyPass" [게임패스]: 코인 2배 (영원히) — 열매 판매·성체 팔기 코인 × value(2)
	가격(로벅스): 부스트 = 배수와 같은 숫자 · 러닝머신 레벨 = TREADMILL_SKIP_ROBUX (18~20레벨은 [추정]) · 상점 5개
]]

local Config = require(script.Parent.Config)

-- isPass = true 면 게임패스 (productId = gamePassId), false 면 개발자 상품 (productId = developer productId)
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
	treadmillBoost = "treadmillBoost",
	treadmillSkip = "treadmillSkip",
	coins = "coins",
	speed = "speed",
	moneyPass = "moneyPass",
}

-- ★ 아빠가 Creator Dashboard 에서 만든 id 를 여기에 붙여 넣기 (0 = 아직 없음). 한 표지만 두 종류 — 섞지 말 것:
--   [게임패스] Monetization → Passes 의 Pass ID : boost_2 … boost_2048, money_pass (12개)
--   [개발자 상품] Monetization → Developer Products 의 Product ID : tskip_1 … tskip_20, coins_1m, coins_1b, speed_10m, speed_100m (24개)
local IDS: { [string]: number } = {
	-- [게임패스] 러닝머신 부스트 (영구) — 2배부터 차례로 다 붙일 것
	boost_2 = 2076130863,
	boost_4 = 2075134948,
	boost_8 = 2074624960,
	boost_16 = 2075716833,
	boost_32 = 2074408955,
	boost_64 = 2078090427,
	boost_128 = 2075374875,
	boost_256 = 2074589014,
	boost_512 = 2074666905,
	boost_1024 = 2074420889,
	boost_2048 = 2076040753,
	-- [게임패스] 상점 창: 코인 2배 (영원히)
	money_pass = 2075434982,
	-- [개발자 상품] 러닝머신 레벨 바로 올리기 (tskip_N = N레벨로)
	tskip_1 = 3730160835,
	tskip_2 = 3730160910,
	tskip_3 = 3730160843,
	tskip_4 = 3730160854,
	tskip_5 = 3730160990,
	tskip_6 = 3730160992,
	tskip_7 = 3730160997,
	tskip_8 = 3730161003,
	tskip_9 = 3730161257,
	tskip_10 = 3730161174,
	tskip_11 = 3730161104,
	tskip_12 = 3730161108,
	tskip_13 = 3730161117,
	tskip_14 = 3730161178,
	tskip_15 = 3730161263,
	tskip_16 = 3730161184,
	tskip_17 = 3730161188,
	tskip_18 = 3730161196,
	tskip_19 = 3730161265,
	tskip_20 = 3730161203,
	-- [개발자 상품] 상점 창
	coins_1m = 3730160803,
	coins_1b = 3730161170,
	speed_10m = 3730160982,
	speed_100m = 3730161284,
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

local function make(key: string, kind: string, name: string, robux: number, value: number?, isPass: boolean): Product
	return {
		key = key,
		kind = kind,
		name = name,
		robux = robux,
		productId = IDS[key] or 0,
		value = value,
		isPass = isPass,
	}
end

local list: { Product } = {}
local byKey: { [string]: Product } = {}
local byId: { [number]: Product } = {} -- 개발자 상품만 (영수증 ProcessReceipt 용)
local byPass: { [number]: Product } = {} -- 게임패스만 (PromptGamePassPurchaseFinished · UserOwnsGamePassAsync 용)
local boostByValue: { [number]: Product } = {}
local treadmillBoosts: { Product } = {}
local treadmillSkips: { Product } = {}
local shop: { Product } = {}
local passes: { Product } = {}

local function add(group: { Product }, product: Product)
	table.insert(group, product)
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
	local product = make(
		`boost_{multiplier}`,
		Kinds.treadmillBoost,
		`러닝머신 부스트 x{multiplier}`,
		multiplier,
		multiplier,
		true
	)
	add(treadmillBoosts, product)
	boostByValue[multiplier] = product
end

for level, robux in TREADMILL_SKIP_ROBUX do
	local name = if level == 1 then "러닝머신 열기 (1레벨)" else `러닝머신 {level}레벨로 올리기`
	add(treadmillSkips, make(`tskip_{level}`, Kinds.treadmillSkip, name, robux, level, false))
end

add(shop, make("money_pass", Kinds.moneyPass, "코인 2배 (영원히)", 199, Config.MONEY_PASS_MULTIPLIER, true))
add(shop, make("coins_1m", Kinds.coins, "코인 1M", 99, 1e6, false))
add(shop, make("coins_1b", Kinds.coins, "코인 1B", 199, 1e9, false))
add(shop, make("speed_10m", Kinds.speed, "속도 10M", 199, 1e7, false))
add(shop, make("speed_100m", Kinds.speed, "속도 100M", 259, 1e8, false))

local Products = {
	Kinds = Kinds,
	IDS = IDS,
	list = list,
	byKey = byKey,
	treadmillBoosts = treadmillBoosts,
	treadmillSkips = treadmillSkips,
	shop = shop,
	-- 게임패스 12개 (부스트 11 + money_pass, 표 순서)
	passes = passes,
	BOOST_MULTIPLIERS = BOOST_MULTIPLIERS,
	TREADMILL_SKIP_ROBUX = TREADMILL_SKIP_ROBUX,
	-- 러닝머신 레벨 가격 중 [추정] 한 레벨 (사장님이 안 정해 준 숫자 — 문서·보고용)
	ESTIMATED_SKIP_LEVELS = { 18, 19, 20 } :: { number },
}

function Products.get(key: string): Product?
	return byKey[key]
end

-- ProcessReceipt 의 receipt.ProductId → **개발자 상품만** (0·음수·모르는 id·게임패스 id = nil — 영수증으로 패스를 주지 않음)
function Products.byProductId(id: number): Product?
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return byId[id]
end

-- PromptGamePassPurchaseFinished 의 gamePassId → **게임패스만** (0·음수·모르는 id·개발자 상품 id = nil)
function Products.byPassId(id: number): Product?
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return byPass[id]
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

-- 스피드 배수는 순서대로만 열림 (사장님 2026-11-10: "2배를 사야 4배가 열리는 식") ------------------------
-- 지금 배수 바로 다음 상품 (1 → boost_2, 2 → boost_4 …, 최대(2048)면 nil). 이것 하나만 살 수 있음
function Products.nextTreadmillBoost(current: number): Product?
	local now = if current == current then current else 1
	for _, product in treadmillBoosts do
		if (product.value or 0) > now then
			return product
		end
	end
	return nil
end

-- 카드 상태 (순수 — 클라 BoostController 가 씀):
--   "active" 지금 적용 중 · "owned" 이미 지나온 배수 · "buy" 바로 다음 (살 수 있음) · "locked" 앞의 것을 먼저 사야 함
function Products.treadmillBoostState(current: number, value: number): string
	local now = if current == current then current else 1
	if value == now then
		return "active"
	elseif value < now then
		return "owned"
	end
	local nextProduct = Products.nextTreadmillBoost(now)
	if nextProduct and nextProduct.value == value then
		return "buy"
	end
	return "locked"
end

-- 부스트 상품을 지금 배수에서 샀을 때 받는 것 (순수 — 서버 ProductService.grant 가 씀): (새 배수, 남은 로벅스).
--   - 바로 다음 배수면 그 배수 (남는 것 0)
--   - 순서가 안 맞으면 (잠긴 것을 위조 클라로 삼 · 가진 것을 또 삼 · 두 번 누름): 예산 = 그 상품 로벅스. 다음 배수 가격부터
--     차례로 빼며 살 수 있는 만큼만 올림, 남은 예산은 서버가 속도로 바꿔 줌 (× Config.PRODUCT_SPEED_PER_ROBUX).
--     → boost_8 (8 R$) 하나로 2·4배 값(6 R$)을 건너뛸 수 없음 (×4 + 남은 2 R$ 는 속도). 돈을 받았으니 언제나 뭔가 줌
function Products.treadmillBoostOutcome(current: number, product: Product): (number, number)
	local now = if current == current then math.max(1, current) else 1
	local nextProduct = Products.nextTreadmillBoost(now)
	if nextProduct and nextProduct.key == product.key then
		return nextProduct.value or now, 0
	end
	local budget = math.max(0, product.robux)
	for _ = 1, #treadmillBoosts do
		local step = Products.nextTreadmillBoost(now)
		if not step or step.robux > budget then
			break
		end
		budget -= step.robux
		now = step.value or now
	end
	return now, budget
end

-- 가진 부스트 게임패스들로 정해지는 배수 (순수 — 서버 ProductService.syncPasses 가 씀, 62번).
--   게임패스는 웹(게임 페이지 상점)에서 순서를 건너뛰어 살 수 있음 → 사장님 규칙 "2배를 사야 4배가 열림" + 낸 값만큼은 받게:
--   예산 = 가진 패스들의 가격 합. 2배부터 차례로 가격을 빼며 올릴 수 있는 데까지 (treadmillBoostOutcome 의 걷기와 같음).
--   순서대로 다 가졌으면 그 최댓값. 중복·모르는 값·NaN 은 무시. 예: {2,4,8} → 8 · {2048} → 1024 · {4} → 2 · {} → 1 · {2,8} → 4
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
	for _, product in treadmillBoosts do
		if product.robux > budget then
			break
		end
		budget -= product.robux
		now = product.value or now
	end
	return now
end

-- Creator Dashboard 에서 만든 id 가 붙어 있나 (false 면 클라는 "준비 중")
function Products.isConfigured(product: Product): boolean
	return product.productId > 0
end

return Products
