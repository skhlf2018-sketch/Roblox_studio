--!strict
--[[
	ProductService — 송판 깨기 로벅스 게임패스 (설계서 5장) — 서버 권위. 첫 게임 ProductService 를 그대로 가져와 줄임.

	게임패스 12개 (Data/Products): power_2 … power_2048 (힘 배수, 순서대로만 열림) · money_2 (돈 2배)
	  - 게임패스는 ProcessReceipt 가 **안 옴**. 소유 확인 UserOwnsGamePassAsync 로만 반영:
	      · syncPasses(player) — 접속 준비(onPlayerReady → task.spawn) 때 id 붙은 패스를 전부 (동시에, 실패하면
	        PASS_CHECK_RETRIES 번 더) 확인 → data.moneyPass = 원래 값 or 가짐,
	        data.powerBoost = max(원래 값, Products.boostFromOwnedPasses(가진 배수들)) — **절대 낮추지 않음**
	      · MarketplaceService.PromptGamePassPurchaseFinished (서버에서만 믿음): wasPurchased 이고 우리 패스면 소유를 다시 확인해서
	        true 일 때만 반영 + ProductGranted · Notify · 저장 시도. 같은 패스로 ProductGranted 는 접속당 1번
	      · 웹에서 순서를 건너뛰어 산 패스는 낸 값만큼만 (boostFromOwnedPasses — 2배를 사야 4배)
	  - 패스 id 12개는 Data/Products IDS (2026-11-17 게시한 체험 universe 10777294360). 개발 명령 /buy <key> 로도 시험 (grant)
	  - 구매가 끝났다는 신호만으로는 주지 않음 — 서버가 UserOwnsGamePassAsync 로 다시 확인 (거짓이면 PURCHASE_CONFIRM_TRIES 번까지
	    PURCHASE_CONFIRM_SECONDS 마다 다시 — 로블록스 쪽 소유 반영이 늦는 경우). 그래도 아니면 안내 글만 (다음 접속 때 syncPasses)
	  - 게임을 만든 사람은 자기 게임패스를 처음부터 전부 가진 것으로 나옴 (로블록스 규칙) → 스튜디오에서 새 플레이어 화면을 보려면
	    개발 명령 /unbuy (setIgnorePassesForTest — 이 접속 동안 소유 확인을 쉼, 이미 돌고 있던 확인 결과도 안 씀)
	- ProcessReceipt = processReceipt: 개발자 상품용 (지금은 없음 → 모르는 상품 = NotProcessedYet + 경고). 영수증 기록·저장 확인은
	  첫 게임과 같음 (나중에 개발자 상품을 더하면 그대로 씀)
	- grant(player, key, source): 시험·개발 명령 지급 (영수증 확인 없음)
	    powerBoost : Products.powerBoostOutcome — 바로 다음 배수면 그 배수, 순서가 안 맞으면 그 로벅스만큼만 차례로 (건너뛰기 없음)
	    moneyPass  : data.moneyPass = true
	  → Attr PowerBoost · MoneyPass + DataUpdate "passes" + ProductGranted { key, kind } + Notify
	서버로 "사 줘" Remote 는 없음 (위조 방지 — 돈은 로블록스가 받음).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Products = require(Shared.Data.Products)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Attributes = require(Server.Attributes)
local DataService = require(script.Parent.DataService)

local Kinds = Products.Kinds

local ProductService = {}

ProductService.LOAD_WAIT_SECONDS = 15
ProductService.SAVE_WAIT_SECONDS = 10
ProductService.RECEIPT_ID_MAX = 64
ProductService.PASS_CHECK_RETRIES = 2
ProductService.PASS_RETRY_SECONDS = 1
ProductService.PASS_CHECK_TIMEOUT = 30
ProductService.PURCHASE_CONFIRM_TRIES = 3 -- 구매 직후 소유 확인이 "아니요" 면 이만큼 (처음 포함)
ProductService.PURCHASE_CONFIRM_SECONDS = 3
ProductService.PASS_CHECKING_TEXT = "구매 확인 중 · 잠시 후 재접속 시 적용"

local function boostText(boost: number): string
	return string.format("힘 %s배! 아령 힘·타격 힘 모두 %s배", Format.number(boost), Format.number(boost))
end

local MONEY_PASS_TEXT = "돈 2배! 격파 보상 2배 (영구)"

-- 지급 (영수증 확인 없음 — 개발 명령 /buy · 테스트). 줬으면 true
function ProductService.grant(player: Player, key: string, _source: string?): boolean
	local session, data = Sessions.getLoaded(player)
	local product = Products.get(key)
	if not session or not data or not product then
		return false
	end
	if product.kind == Kinds.powerBoost then
		local before = data.powerBoost
		data.powerBoost = math.max(before, Products.powerBoostOutcome(before, product))
		if data.powerBoost > before then
			Net.notify(player, "success", boostText(data.powerBoost))
		else
			Net.notify(
				player,
				"info",
				string.format("힘 배수는 순서대로 구매 · 현재 %s배", Format.number(data.powerBoost))
			)
		end
		for _, boost in Products.powerBoosts do
			if (boost.value or 0) <= data.powerBoost then
				session.ownedPasses[boost.key] = true
			end
		end
	elseif product.kind == Kinds.moneyPass then
		if data.moneyPass then
			Net.notify(player, "info", "돈 2배 보유 중 (영구 적용)")
		else
			data.moneyPass = true
			Net.notify(player, "success", MONEY_PASS_TEXT)
		end
		session.ownedPasses[product.key] = true
	else
		return false
	end
	Attributes.sync(player)
	Snapshot.section(player, "passes")
	Net.fire(player, Remotes.ToClient.ProductGranted, { key = product.key, kind = product.kind } :: Types.ProductGrant)
	return true
end

--------------------------------------------------------------------------------
-- 개발자 상품 영수증 (지금은 상품이 없음 — 첫 게임과 같은 안전 장치만)
--------------------------------------------------------------------------------

local unsaved: { [Types.PlayerData]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

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

function ProductService.processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local granted = Enum.ProductPurchaseDecision.PurchaseGranted
	local playerId, productId, purchaseId = receipt.PlayerId, receipt.ProductId, receipt.PurchaseId
	if typeof(playerId) ~= "number" or typeof(productId) ~= "number" or purchaseId == nil then
		return notYet
	end
	local receiptId = string.sub(tostring(purchaseId), 1, ProductService.RECEIPT_ID_MAX)
	if receiptId == "" then
		return notYet
	end
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return notYet
	end
	local session, data = waitLoaded(player)
	if not session or not data then
		return notYet
	end
	if table.find(data.receipts, receiptId) then
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
	local product = Products.byProductId(productId)
	if not product then
		warn(
			string.format(
				"[ProductService] 모르는 상품 id %s (%s) — Products.IDS 확인 필요. 지급 안 함",
				tostring(productId),
				player.Name
			)
		)
		return notYet
	end
	remember(data, receiptId)
	local pending = unsaved[data]
	if not pending then
		pending = {}
		unsaved[data] = pending
	end
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
	return notYet
end

--------------------------------------------------------------------------------
-- 게임패스 소유 확인
--------------------------------------------------------------------------------

type PassSet = { [string]: boolean }

local announcedPasses: { [Types.PlayerData]: PassSet } = setmetatable({}, { __mode = "k" }) :: any
local ignoringPasses: { [Player]: boolean? } = setmetatable({}, { __mode = "k" }) :: any

local function marketplace(): MarketplaceService?
	local ok, service = pcall(function()
		return game:GetService("MarketplaceService")
	end)
	if ok and service then
		return service :: any
	end
	return nil
end

-- 패스 하나 소유 확인 (yield). true/false = 답, nil = 재시도까지 전부 실패
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

local function stillHere(player: Player, data: Types.PlayerData): boolean
	local _, nowData = Sessions.getLoaded(player)
	return nowData == data and player.Parent ~= nil
end

local function configuredPasses(): { Products.Product }
	local list: { Products.Product } = {}
	for _, product in Products.passes do
		if Products.isConfigured(product) then
			table.insert(list, product)
		end
	end
	return list
end

-- 확인된 패스 집합 → 데이터 (절대 낮추지 않음). 바뀌었으면 true
local function applyOwnedPasses(player: Player, session: Sessions.Session, data: Types.PlayerData): boolean
	local multipliers: { number } = {}
	local hasMoneyPass = false
	for key, owned in session.ownedPasses do
		local product = Products.get(key)
		if owned and product and product.kind == Kinds.powerBoost and product.value then
			table.insert(multipliers, product.value)
		elseif owned and product and product.kind == Kinds.moneyPass then
			hasMoneyPass = true
		end
	end
	local beforeBoost, beforeMoneyPass = data.powerBoost, data.moneyPass
	data.moneyPass = data.moneyPass or hasMoneyPass
	data.powerBoost = math.max(data.powerBoost, Products.boostFromOwnedPasses(multipliers))
	Attributes.sync(player)
	local changed = data.powerBoost ~= beforeBoost or data.moneyPass ~= beforeMoneyPass
	if changed then
		Snapshot.section(player, "passes")
	end
	return changed
end

-- 시험용 (개발 명령 /unbuy): 이 접속 동안 패스 소유 확인을 쉼
function ProductService.setIgnorePassesForTest(player: Player, ignore: boolean)
	ignoringPasses[player] = if ignore then true else nil
end

-- id 붙은 패스를 전부 소유 확인해서 데이터에 반영 (yield). 확인할 패스가 없으면(id 를 아직 안 붙임) true
function ProductService.syncPasses(player: Player): boolean
	local session, data = Sessions.getLoaded(player)
	if not session or not data or ignoringPasses[player] then
		return false
	end
	local list = configuredPasses()
	if #list == 0 then
		return true
	end
	local answers = checkPasses(player, list)
	if not stillHere(player, data) or ignoringPasses[player] then
		return false -- 확인하는 사이 나감 · 확인하는 사이 /unbuy (시험용 — 늦게 온 결과로 다시 올리지 않음)
	end
	local answered = false
	for key, has in answers do
		answered = true
		if has then
			session.ownedPasses[key] = true
		end
	end
	if not answered then
		if marketplace() then
			warn("[ProductService] 게임패스 소유 확인 실패 — 다음 접속 때 다시: " .. player.Name)
		end
		return false
	end
	applyOwnedPasses(player, session, data)
	return true
end

function ProductService.onGamePassPurchaseFinished(player: Player, gamePassId: number, wasPurchased: boolean)
	if wasPurchased ~= true then
		return
	end
	local product = Products.byPassId(gamePassId)
	if not product then
		return -- 모르는 id · 남의 게임 패스 · 0 · 음수 · NaN · 글자
	end
	local session, data = waitLoaded(player)
	if not session or not data then
		return
	end
	local announced = announcedPasses[data]
	if not announced then
		announced = {}
		announcedPasses[data] = announced
	end
	if announced[product.key] then
		return
	end
	announced[product.key] = true -- yield 전에 표시 → 동시에 두 번 와도 한 번만
	-- 구매가 끝났다는 신호만 믿지 않고 서버가 소유를 다시 확인 ("아니요" 면 조금 뒤 몇 번 더 — 반영이 늦을 때)
	local owned = ownsPass(player, product.productId)
	for _ = 2, ProductService.PURCHASE_CONFIRM_TRIES do
		if owned ~= false or not stillHere(player, data) then
			break
		end
		task.wait(ProductService.PURCHASE_CONFIRM_SECONDS)
		owned = ownsPass(player, product.productId)
	end
	if not stillHere(player, data) then
		announced[product.key] = nil
		return
	end
	if owned ~= true then
		announced[product.key] = nil
		Net.notify(player, "info", ProductService.PASS_CHECKING_TEXT)
		return
	end
	ignoringPasses[player] = nil -- 진짜로 샀으면 시험용 "패스 확인 쉼"은 풀림
	session.ownedPasses[product.key] = true
	ProductService.syncPasses(player)
	if not stillHere(player, data) then
		return
	end
	applyOwnedPasses(player, session, data)
	if product.kind == Kinds.powerBoost then
		if data.powerBoost >= (product.value or 0) then
			Net.notify(player, "success", boostText(data.powerBoost))
		else
			Net.notify(
				player,
				"success",
				string.format(
					"힘 배수는 순서대로 구매 · 현재 %s배 (앞 배수 구매 시 상승)",
					Format.number(data.powerBoost)
				)
			)
		end
	elseif product.kind == Kinds.moneyPass then
		Net.notify(player, "success", MONEY_PASS_TEXT)
	end
	Net.fire(player, Remotes.ToClient.ProductGranted, { key = product.key, kind = product.kind } :: Types.ProductGrant)
	persist(player, session)
end

function ProductService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	if data then
		Attributes.sync(player)
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
