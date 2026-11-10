--!strict
--[[
	ProductService — 로벅스 상품 (9판, 사장님 2026-11-10) — 서버 권위. 상품 표는 shared/Data/Products

	사장님 2026-11-10 (62번) "영구적인 것은 게임패스, 소모품은 개발자 상품":
	  - 개발자 상품 24개 (tskip_*, coins_*, speed_*) = 아래 ProcessReceipt (영수증 기록·저장 확인 그대로)
	  - 게임패스 12개 (boost_* 11 + money_pass) = ProcessReceipt 가 **안 옴**. 소유 확인 UserOwnsGamePassAsync 로만 반영:
	      · ProductService.syncPasses(player) — 접속 준비(onPlayerReady → task.spawn) 때 id 붙은 패스를 전부 (동시에, 실패하면
	        PASS_CHECK_RETRIES 번 더, 사이 PASS_RETRY_SECONDS) 확인 → data.moneyPass = 원래 값 or 가짐,
	        data.treadmillBoost = max(원래 값, Products.boostFromOwnedPasses(가진 배수들)) — **절대 낮추지 않음**. 전부 실패면 그대로 + false
	      · MarketplaceService.PromptGamePassPurchaseFinished (서버에서만 믿음): wasPurchased 이고 우리 패스면 소유를 다시 확인해서
	        true 일 때만 반영 + ProductGranted · Notify · stats.productsBought · 저장 시도. 같은 패스로 ProductGranted 는 접속당 1번.
	        확인이 안 되면 지급 없이 info "구매를 확인하는 중이에요…" (다음 접속 syncPasses 가 다시 맞춤)
	      · 웹(게임 페이지 상점)에서 순서를 건너뛰어 산 패스는 낸 값만큼만 (boostFromOwnedPasses)
	- 구매창은 클라가 연다 (Purchase.prompt — 상품 PromptProductPurchase / 패스 PromptGamePassPurchase). 서버로 "사 줘" Remote 는 없음
	  (위조 방지 — 돈은 로블록스가 받고, 여기 ProcessReceipt·패스 소유 확인만 지급함).
	- MarketplaceService.ProcessReceipt = ProductService.processReceipt (게임 전체에 하나만):
	    1) 그 플레이어가 서버에 없으면 NotProcessedYet (로블록스가 나중에 다시 부름)
	    2) 데이터를 불러오는 중이면 LOAD_WAIT_SECONDS 까지 기다림, 그래도 안 되면 NotProcessedYet
	    3) receipt.PurchaseId(64자까지) 가 data.receipts(최근 Config.RECEIPT_HISTORY_MAX 개 고리)에 있으면 이미 준 것 → PurchaseGranted (중복 지급 없음).
	       단 지급은 했는데 저장이 아직 안 된 영수증(unsaved)은 저장을 다시 해 보고 성공해야 PurchaseGranted (주임 9판 F-1)
	    4) 모르는 productId(Products.IDS 에 없음 · 게임패스 id — byProductId 는 개발자 상품만) → NotProcessedYet (경고 — 돈 받고 못 주는 일이 없게: 처리 안 된 구매는 로블록스가 다시 알려 주고, 끝내 처리 안 되면 환불될 수 있음)
	    5) 영수증을 먼저 적고(yield 전) grant → 저장(DataService.save) 성공이면 PurchaseGranted.
	       저장 실패면 NotProcessedYet (영수증은 메모리에 남아 이번 접속에서 다시 와도 두 번 안 줌 — 다시 오면 저장부터 다시 해 봄). 메모리 모드는 스튜디오만 저장 없이 PurchaseGranted
	- 지급 ProductService.grant(player, key, source) — 순수 지급 로직 (테스트·개발 명령 /buy 가 같이 씀, 영수증 확인 없음).
	  패스 key 도 바로 줌 (스튜디오 시험용 — **진짜 서버에서는 패스는 소유 확인(syncPasses · PromptGamePassPurchaseFinished)으로만**):
	    treadmillBoost : 순서대로만 열림 (2배 → 4배 → … 사장님 2026-11-10). 바로 다음 배수를 사면 그 배수 (곱 아님).
	                     순서가 안 맞으면 (잠긴 것을 위조로 삼·가진 것을 또 삼) **산 로벅스만큼만** — 다음 배수부터 차례로,
	                     남은 로벅스는 속도 (Products.treadmillBoostOutcome). Attr TreadmillBoost
	                     러닝머신 1초 이득 = 레벨 이득 × 트레일 배율 × 부스트 (TreadmillService — 러닝머신 탈 때만)
	    treadmillSkip  : tskip_N 은 지금 레벨이 N-1 이면 N 으로 (코인 안 듦). 레벨이 안 맞으면 (창이 늦게 바뀜·두 번 누름·위조)
	                     **산 로벅스만큼만** — 다음 레벨 가격부터 차례로 빼며 살 수 있는 레벨만, 남은 로벅스는 속도
	                     (× PRODUCT_SPEED_PER_ROBUX, 속도 상품보다 유리하지 않게, Products.treadmillSkipOutcome — 주임 F-3).
	                     최대 레벨이면 전부 속도. 돈을 받았으니 언제나 뭔가 줌 (0 지급 없음)
	    coins / speed  : Wallet.addMoney / addSpeed (MONEY_MAX · SPEED_MAX 에서 자름)
	    moneyPass      : data.moneyPass = true (영원히 열매 판매·성체 팔기 × MONEY_PASS_MULTIPLIER — PetService.coinMultiplier). Attr MoneyPass
	  → ProductGranted { key, kind } + Notify + (러닝머신·코인 2배면) DataUpdate("upgrades")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Products = require(Shared.Data.Products)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Wallet = require(script.Parent.Wallet)
local DataService = require(script.Parent.DataService)

local Attr = Tags.PlayerAttributes
local Kinds = Products.Kinds

local ProductService = {}

ProductService.LOAD_WAIT_SECONDS = 15 -- ProcessReceipt 가 데이터 불러오는 중에 오면 이만큼 기다림
ProductService.SAVE_WAIT_SECONDS = 10 -- 자동저장이 진행 중이면 끝날 때까지 이만큼 기다렸다 저장
ProductService.RECEIPT_ID_MAX = 64 -- 영수증 기록 글자 수 (DataSchema.cleanReceipts 와 같음)
ProductService.PASS_CHECK_RETRIES = 2 -- 게임패스 소유 확인(UserOwnsGamePassAsync)이 실패하면 이만큼 더 해 봄
ProductService.PASS_RETRY_SECONDS = 1 -- 그 사이 기다림
ProductService.PASS_CHECK_TIMEOUT = 30 -- 패스 여러 개를 동시에 확인할 때 이 이상은 안 기다림 (끝나지 않은 확인은 실패로)
ProductService.PASS_CHECKING_TEXT = "구매를 확인하는 중이에요. 잠시 뒤 다시 접속하면 적용돼요"

local function syncAttributes(player: Player, data: Types.PlayerData)
	player:SetAttribute(Attr.TreadmillBoost, data.treadmillBoost)
	player:SetAttribute(Attr.MoneyPass, data.moneyPass)
end

local function setTreadmillLevel(player: Player, data: Types.PlayerData, level: number)
	data.treadmillLevel = level
	player:SetAttribute(Attr.TreadmillLevel, level)
	Net.notify(
		player,
		"success",
		string.format(
			"러닝머신 %d레벨! 1초에 +%s 속도",
			level,
			Format.number(Economy.treadmillGainPerSecond(level))
		)
	)
end

-- 지급 (영수증 확인 없음 — processReceipt·개발 명령 /buy·테스트). source = "purchase" | "dev" | … (기록용). 줬으면 true
-- 게임패스 key(boost_* · money_pass)도 여기서 바로 줌 = 스튜디오 시험용(/buy). 진짜 서버에서는 패스는 소유 확인으로만
-- (syncPasses · PromptGamePassPurchaseFinished — 영수증이 오지 않고, byProductId 가 패스 id 에 nil 이라 processReceipt 로도 안 옴)
function ProductService.grant(player: Player, key: string, source: string?): boolean
	local _, data = Sessions.getLoaded(player)
	local product = Products.get(key)
	if not data or not product then
		return false
	end
	local value = product.value or 0
	local kind = product.kind
	if kind == Kinds.treadmillBoost then
		-- 사장님 2026-11-10: 순서대로만 열림 (2배 → 4배 → …). 순서가 안 맞게 산 것은 산 로벅스만큼만 (남은 값은 속도)
		local before = data.treadmillBoost
		local boost, leftover = Products.treadmillBoostOutcome(before, product)
		data.treadmillBoost = boost
		if leftover <= 0 then
			Net.notify(
				player,
				"success",
				string.format(
					"러닝머신 부스트 x%s! 러닝머신에서 오르는 속도가 %s배예요.",
					Format.number(boost),
					Format.number(boost)
				)
			)
		else
			local speed = leftover * Config.PRODUCT_SPEED_PER_ROBUX
			Wallet.addSpeed(player, speed)
			Net.notify(
				player,
				"success",
				string.format(
					"스피드 배수는 순서대로 열려요. 산 값(R$ %d)만큼 받았어요: 지금 부스트 x%s · 속도 +%s",
					product.robux,
					Format.number(boost),
					Format.number(speed)
				)
			)
		end
		syncAttributes(player, data)
		Snapshot.section(player, "upgrades")
	elseif kind == Kinds.treadmillSkip then
		local before = data.treadmillLevel
		local level, leftover = Products.treadmillSkipOutcome(before, product)
		if level == math.floor(value) and before == level - 1 then
			setTreadmillLevel(player, data, level)
		else
			-- 주임 F-3: 레벨이 안 맞음 → 산 로벅스만큼만 (살 수 있는 레벨 + 남은 로벅스는 속도)
			local speed = leftover * Config.PRODUCT_SPEED_PER_ROBUX
			data.treadmillLevel = level
			player:SetAttribute(Attr.TreadmillLevel, level)
			if speed > 0 then
				Wallet.addSpeed(player, speed)
			end
			Net.notify(
				player,
				"success",
				string.format(
					"러닝머신 레벨이 이미 바뀌어서 산 값(R$ %d)만큼 받았어요: 러닝머신 +%d레벨 · 속도 +%s",
					product.robux,
					level - before,
					Format.number(speed)
				)
			)
		end
		Snapshot.section(player, "upgrades")
	elseif kind == Kinds.coins then
		Wallet.addMoney(player, value)
		Net.notify(player, "success", string.format("코인 +%s!", Format.number(value)))
	elseif kind == Kinds.speed then
		Wallet.addSpeed(player, value)
		Net.notify(player, "success", string.format("속도 +%s!", Format.number(value)))
	elseif kind == Kinds.moneyPass then
		if data.moneyPass then
			Net.notify(player, "info", "이미 코인 2배를 갖고 있어요! (영원히 적용 중)")
		else
			data.moneyPass = true
			Net.notify(
				player,
				"success",
				"코인 2배! 이제 열매·식물을 팔 때 코인을 2배로 받아요 (영원히)."
			)
		end
		syncAttributes(player, data)
		Snapshot.section(player, "upgrades")
	else
		return false
	end
	if source ~= "dev" then
		data.stats.productsBought = (data.stats.productsBought or 0) + 1
	end
	Net.fire(player, Remotes.ToClient.ProductGranted, { key = product.key, kind = product.kind } :: Types.ProductGrant)
	return true
end

-- 지급은 했지만 저장이 아직 확인 안 된 영수증 (플레이어 데이터 표 → { [영수증 번호]: true }, 약한 키).
-- (주임 9판 F-1) 이런 영수증이 로블록스 재시도로 다시 오면 "이미 준 것"이라고 바로 PurchaseGranted 하지 않고
-- 저장을 다시 해 보고, 저장이 성공해야 PurchaseGranted — 안 그러면 저장이 안 된 채 확인해 버려서
-- 서버가 꺼지면 돈만 받고 상품이 사라짐
local unsaved: { [Types.PlayerData]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

-- 영수증 기록 (뒤가 최신, RECEIPT_HISTORY_MAX 개 고리)
local function remember(data: Types.PlayerData, purchaseId: string)
	table.insert(data.receipts, purchaseId)
	while #data.receipts > Config.RECEIPT_HISTORY_MAX do
		table.remove(data.receipts, 1)
	end
end

local function forget(data: Types.PlayerData, purchaseId: string)
	local index = table.find(data.receipts, purchaseId)
	if index then
		table.remove(data.receipts, index)
	end
end

-- 지급 뒤 저장. 저장할 수 없는 서버(스튜디오 메모리 모드)는 true
-- (주임 9판: 실서버가 메모리 모드면 저장이 안 되니 false → NotProcessedYet. 스튜디오는 진짜 돈이 아니라서 true)
local function persist(player: Player, session: Sessions.Session): boolean
	if DataService.isMemoryMode() then
		return RunService:IsStudio()
	end
	local waited = 0
	while session.saving and waited < ProductService.SAVE_WAIT_SECONDS do
		task.wait(0.1)
		waited += 0.1
	end
	return DataService.save(player, false)
end

-- 데이터 불러오는 중이면 LOAD_WAIT_SECONDS 까지 기다림 (접속하자마자 밀린 영수증·구매 알림이 옴). 끝내 안 되거나 나가면 nil
local function waitLoaded(player: Player): (Sessions.Session?, Types.PlayerData?)
	local waited = 0
	while not Sessions.getLoaded(player) and player.Parent ~= nil and waited < ProductService.LOAD_WAIT_SECONDS do
		task.wait(0.5)
		waited += 0.5
	end
	local session, data = Sessions.getLoaded(player)
	if not session or not data or player.Parent == nil then
		return nil, nil
	end
	return session, data
end

-- MarketplaceService.ProcessReceipt 콜백 (yield 할 수 있음) — 개발자 상품만 (게임패스는 영수증이 안 옴)
function ProductService.processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local granted = Enum.ProductPurchaseDecision.PurchaseGranted
	local playerId, productId, purchaseId = receipt.PlayerId, receipt.ProductId, receipt.PurchaseId
	if typeof(playerId) ~= "number" or typeof(productId) ~= "number" or purchaseId == nil then
		return notYet
	end
	-- 기록은 저장 데이터 정리 규칙(DataSchema.cleanReceipts: 1 ~ 64자)과 같게 — 안 그러면 불러올 때 기록이 사라져 중복 방지가 풀림
	local receiptId = string.sub(tostring(purchaseId), 1, ProductService.RECEIPT_ID_MAX)
	if receiptId == "" then
		return notYet
	end
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return notYet
	end
	-- 데이터 불러오는 중이면 조금 기다림 (접속하자마자 밀린 영수증이 옴)
	local session, data = waitLoaded(player)
	if not session or not data then
		return notYet
	end
	if table.find(data.receipts, receiptId) then
		-- 이미 준 영수증 (다시 와도 한 번만). 단 저장이 아직 확인 안 된 것은 저장이 되어야 확인 (F-1)
		local pending = unsaved[data]
		if pending and pending[receiptId] then
			if persist(player, session) then
				pending[receiptId] = nil
				return granted
			end
			return notYet
		end
		return granted
	end
	-- byProductId 는 개발자 상품만: 게임패스 id 와 같은 ProductId 가 와도 nil → "모르는 상품" (NotProcessedYet + 경고).
	-- 영수증으로 패스를 지급하는 일은 없음 (패스는 소유 확인으로만 — syncPasses · onGamePassPurchaseFinished)
	local product = Products.byProductId(productId)
	if not product then
		warn(
			string.format(
				"[ProductService] 모르는 상품 id %s (%s) — Products.IDS 를 확인하세요. 지급 안 함",
				tostring(productId),
				player.Name
			)
		)
		return notYet
	end
	-- yield 전에 먼저 적음 → 같은 영수증이 동시에 와도 한 번만 지급
	remember(data, receiptId)
	local pending = unsaved[data]
	if not pending then
		pending = {}
		unsaved[data] = pending
	end
	-- 저장이 성공할 때까지 "저장 안 됨" 표시 (같은 영수증이 또 와도 저장 뒤에야 확인). grant 보다 먼저 적어 둠:
	-- grant 가 도중에 오류를 내도 (효과는 이미 적용됨) 다시 올 때 저장부터 확인
	pending[receiptId] = true
	if not ProductService.grant(player, product.key, "purchase") then
		forget(data, receiptId)
		pending[receiptId] = nil
		return notYet
	end
	if persist(player, session) then
		pending[receiptId] = nil
		return granted
	end
	warn("[ProductService] 지급 뒤 저장 실패 — 나중에 다시 확인: " .. player.Name .. " " .. product.key)
	return notYet
end

--------------------------------------------------------------------------------
-- 게임패스 (62번 — boost_* 11개 + money_pass). ProcessReceipt 가 안 오므로 소유 확인으로만 반영
--------------------------------------------------------------------------------

type PassSet = { [string]: boolean }

-- 이번 접속에서 소유가 확인된 패스 key (플레이어 데이터 표 → 집합, 약한 키). 배수는 이 집합 전부로 정해짐
local ownedPasses: { [Types.PlayerData]: PassSet } = setmetatable({}, { __mode = "k" }) :: any
-- 이번 접속에서 ProductGranted 를 보낸(또는 확인 중인) 패스 key — 같은 패스로 두 번 안 알림
local announcedPasses: { [Types.PlayerData]: PassSet } = setmetatable({}, { __mode = "k" }) :: any

local function passSet(map: { [Types.PlayerData]: PassSet }, data: Types.PlayerData): PassSet
	local set = map[data]
	if not set then
		set = {}
		map[data] = set
	end
	return set
end

-- MarketplaceService (지금 코드처럼 그때그때 game:GetService — 테스트는 Loader.service 로 가짜를 끼움). 없으면 nil
local function marketplace(): MarketplaceService?
	local ok, service = pcall(function()
		return game:GetService("MarketplaceService")
	end)
	if ok and service then
		return service :: any
	end
	return nil
end

-- 패스 하나 소유 확인 (yield). true/false = 답, nil = 재시도까지 전부 실패 (또는 MarketplaceService 없음 · 나감)
local function ownsPass(player: Player, gamePassId: number): boolean?
	local found = marketplace()
	if not found then
		return nil
	end
	local market: MarketplaceService = found
	for attempt = 0, ProductService.PASS_CHECK_RETRIES do
		if attempt > 0 then
			if player.Parent == nil then
				return nil
			end
			task.wait(ProductService.PASS_RETRY_SECONDS)
		end
		local ok, owned = pcall(function()
			return market:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)
		if ok and type(owned) == "boolean" then
			return owned
		end
	end
	return nil
end

-- 여러 패스를 동시에 확인 → { [key]: 가짐? } (답이 온 것만, 실패한 것은 칸 없음)
local function checkPasses(player: Player, list: { Products.Product }): PassSet
	local answers: PassSet = {}
	local pending = #list
	for _, product in list do
		task.spawn(function()
			local owned = ownsPass(player, product.productId)
			if owned ~= nil then
				answers[product.key] = owned
			end
			pending -= 1
		end)
	end
	local waited = 0
	while pending > 0 and waited < ProductService.PASS_CHECK_TIMEOUT do
		task.wait(0.1)
		waited += 0.1
	end
	return table.clone(answers)
end

-- yield 뒤: 그 사람이 아직 서버에 있고 같은 데이터인가 (나갔다 들어왔으면 새 데이터 — 옛 것은 건드리지 않음)
local function stillHere(player: Player, data: Types.PlayerData): boolean
	local _, nowData = Sessions.getLoaded(player)
	return nowData == data and player.Parent ~= nil
end

-- id 가 붙은(isConfigured) 패스만
local function configuredPasses(): { Products.Product }
	local list: { Products.Product } = {}
	for _, product in Products.passes do
		if Products.isConfigured(product) then
			table.insert(list, product)
		end
	end
	return list
end

-- 확인된 패스 집합 → 데이터 (절대 낮추지 않음 — 저장값·/buy 로 받은 것 유지). Attr 맞춤, 바뀌었으면 DataUpdate("upgrades")
local function applyOwnedPasses(player: Player, data: Types.PlayerData): boolean
	local multipliers: { number } = {}
	local hasMoneyPass = false
	for key in passSet(ownedPasses, data) do
		local product = Products.get(key)
		if product and product.kind == Kinds.treadmillBoost and product.value then
			table.insert(multipliers, product.value)
		elseif product and product.kind == Kinds.moneyPass then
			hasMoneyPass = true
		end
	end
	local beforeBoost, beforeMoneyPass = data.treadmillBoost, data.moneyPass
	data.moneyPass = data.moneyPass or hasMoneyPass
	data.treadmillBoost = math.max(data.treadmillBoost, Products.boostFromOwnedPasses(multipliers))
	syncAttributes(player, data)
	local changed = data.treadmillBoost ~= beforeBoost or data.moneyPass ~= beforeMoneyPass
	if changed then
		Snapshot.section(player, "upgrades")
	end
	return changed
end

-- 접속 준비·구매 뒤: id 붙은 패스를 전부 소유 확인해서 데이터에 반영 (yield). 데이터가 안 불려 왔거나 나갔으면 아무것도 안 함(false).
-- 확인이 전부 실패하면 데이터 그대로 false. 확인할 패스가 없으면(id 를 아직 안 붙임) true
-- 시험용 (개발 명령 /unbuy): 이 접속 동안 패스 소유 확인을 쉼. 게임을 만든 사람은 자기 게임패스를 처음부터 전부
--   가진 것으로 나와서(로블록스 규칙) 스튜디오에서 언제나 x2048 · 코인 2배가 됨 → 새 플레이어 화면을 보려면 잠깐 꺼야 함.
--   다시 접속하거나 진짜로 패스를 사면 풀림
local ignoringPasses: { [Player]: boolean? } = setmetatable({}, { __mode = "k" }) :: any

function ProductService.setIgnorePassesForTest(player: Player, ignore: boolean)
	ignoringPasses[player] = if ignore then true else nil
end

function ProductService.syncPasses(player: Player): boolean
	local _, data = Sessions.getLoaded(player)
	if not data then
		return false
	end
	if ignoringPasses[player] then
		return false
	end
	local list = configuredPasses()
	if #list == 0 then
		return true
	end
	local answers = checkPasses(player, list)
	if not stillHere(player, data) then
		return false -- 확인하는 사이 나감 (다음 접속 때 다시)
	end
	local answered = false
	local owned = passSet(ownedPasses, data)
	for key, has in answers do
		answered = true
		if has then
			owned[key] = true
		end
	end
	if not answered then
		if marketplace() then
			warn("[ProductService] 게임패스 소유 확인 실패 — 다음 접속 때 다시: " .. player.Name)
		end
		return false
	end
	applyOwnedPasses(player, data)
	return true
end

-- MarketplaceService.PromptGamePassPurchaseFinished (서버 — 여기서는 wasPurchased 가 최종 결과). yield 할 수 있음
function ProductService.onGamePassPurchaseFinished(player: Player, gamePassId: number, wasPurchased: boolean)
	if wasPurchased ~= true then
		return
	end
	local product = Products.byPassId(gamePassId)
	if not product then
		return -- 모르는 id · 남의 게임 패스 · 개발자 상품 id
	end
	ignoringPasses[player] = nil -- 진짜로 샀으면 시험용 "패스 확인 쉼"은 풀림
	local session, data = waitLoaded(player)
	if not session or not data then
		return -- 못 불러옴 (다음 접속 syncPasses 가 맞춤)
	end
	local announced = passSet(announcedPasses, data)
	if announced[product.key] then
		return -- 같은 패스 알림이 또 옴 (ProductGranted 는 한 번만)
	end
	announced[product.key] = true -- yield 전에 표시 → 동시에 두 번 와도 한 번만
	local owned = ownsPass(player, product.productId)
	if not stillHere(player, data) then
		announced[product.key] = nil
		return
	end
	if owned ~= true then
		-- 로블록스가 아직 소유를 확인해 주지 않음 → 지급 안 함 (다음 접속 syncPasses 가 다시 맞춤)
		announced[product.key] = nil
		Net.notify(player, "info", ProductService.PASS_CHECKING_TEXT)
		return
	end
	passSet(ownedPasses, data)[product.key] = true
	-- 다른 패스도 다시 확인 (배수는 가진 패스 전부로 정해짐 — 접속 때 확인이 실패했던 것까지)
	ProductService.syncPasses(player)
	if not stillHere(player, data) then
		return
	end
	applyOwnedPasses(player, data)
	if product.kind == Kinds.treadmillBoost then
		local boost = data.treadmillBoost
		if boost >= (product.value or 0) then
			Net.notify(
				player,
				"success",
				string.format(
					"러닝머신 부스트 x%s! 러닝머신에서 오르는 속도가 %s배예요.",
					Format.number(boost),
					Format.number(boost)
				)
			)
		else
			-- 웹에서 순서를 건너뛰어 삼 → 낸 값만큼만 (boostFromOwnedPasses)
			Net.notify(
				player,
				"success",
				string.format(
					"스피드 배수는 순서대로 열려요. 지금 x%s 이에요 — 앞의 배수 패스를 사면 올라가요.",
					Format.number(boost)
				)
			)
		end
	elseif product.kind == Kinds.moneyPass then
		Net.notify(
			player,
			"success",
			"코인 2배! 이제 열매·식물을 팔 때 코인을 2배로 받아요 (영원히)."
		)
	end
	data.stats.productsBought = (data.stats.productsBought or 0) + 1
	Net.fire(player, Remotes.ToClient.ProductGranted, { key = product.key, kind = product.kind } :: Types.ProductGrant)
	-- 저장 시도 (실패해도 다음 접속 때 syncPasses 가 소유로 다시 맞춤)
	persist(player, session)
end

-- 접속 준비: Attr TreadmillBoost · MoneyPass + 게임패스 소유 확인 (yield 하므로 따로)
function ProductService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	if data then
		syncAttributes(player, data)
		task.spawn(ProductService.syncPasses, player)
	end
end

function ProductService.start()
	local ok, err = pcall(function()
		local MarketplaceService = game:GetService("MarketplaceService")
		MarketplaceService.ProcessReceipt = ProductService.processReceipt
	end)
	if not ok then
		warn("[ProductService] ProcessReceipt 연결 실패: " .. tostring(err))
	end
	-- 게임패스 구매 (서버에서만 믿음 — 클라 쪽 같은 이벤트는 창 닫기 용)
	local passOk, passErr = pcall(function()
		local MarketplaceService = game:GetService("MarketplaceService")
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(
			function(player: Player, gamePassId: number, wasPurchased: boolean)
				ProductService.onGamePassPurchaseFinished(player, gamePassId, wasPurchased)
			end
		)
	end)
	if not passOk then
		warn("[ProductService] PromptGamePassPurchaseFinished 연결 실패: " .. tostring(passErr))
	end
end

return ProductService
