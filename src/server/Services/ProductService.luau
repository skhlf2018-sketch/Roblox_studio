--!strict
--[[
	ProductService — 로벅스 개발자 상품 (9판, 사장님 2026-11-10) — 서버 권위. 상품 표는 shared/Data/Products

	- 구매창은 클라가 MarketplaceService:PromptProductPurchase(player, productId) 로 엶 (선임). 서버로 "사 줘" Remote 는 없음
	  (위조 방지 — 돈은 로블록스가 받고, 여기 ProcessReceipt 만 지급함).
	- MarketplaceService.ProcessReceipt = ProductService.processReceipt (게임 전체에 하나만):
	    1) 그 플레이어가 서버에 없으면 NotProcessedYet (로블록스가 나중에 다시 부름)
	    2) 데이터를 불러오는 중이면 LOAD_WAIT_SECONDS 까지 기다림, 그래도 안 되면 NotProcessedYet
	    3) receipt.PurchaseId(64자까지) 가 data.receipts(최근 Config.RECEIPT_HISTORY_MAX 개 고리)에 있으면 이미 준 것 → PurchaseGranted (중복 지급 없음).
	       단 지급은 했는데 저장이 아직 안 된 영수증(unsaved)은 저장을 다시 해 보고 성공해야 PurchaseGranted (주임 9판 F-1)
	    4) 모르는 productId(Products.IDS 에 없음) → NotProcessedYet (경고 — 돈 받고 못 주는 일이 없게: 처리 안 된 구매는 로블록스가 다시 알려 주고, 끝내 처리 안 되면 환불될 수 있음)
	    5) 영수증을 먼저 적고(yield 전) grant → 저장(DataService.save) 성공이면 PurchaseGranted.
	       저장 실패면 NotProcessedYet (영수증은 메모리에 남아 이번 접속에서 다시 와도 두 번 안 줌 — 다시 오면 저장부터 다시 해 봄). 메모리 모드는 스튜디오만 저장 없이 PurchaseGranted
	- 지급 ProductService.grant(player, key, source) — 순수 지급 로직 (테스트·개발 명령 /buy 가 같이 씀, 영수증 확인 없음):
	    treadmillBoost : data.treadmillBoost = max(지금, 배수) (곱 아님). 이하를 또 사면 그대로 (소비 처리, 안내). Attr TreadmillBoost
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
function ProductService.grant(player: Player, key: string, source: string?): boolean
	local _, data = Sessions.getLoaded(player)
	local product = Products.get(key)
	if not data or not product then
		return false
	end
	local value = product.value or 0
	local kind = product.kind
	if kind == Kinds.treadmillBoost then
		if value > data.treadmillBoost then
			data.treadmillBoost = value
			Net.notify(
				player,
				"success",
				string.format(
					"러닝머신 부스트 x%s! 러닝머신에서 오르는 속도가 %s배예요.",
					Format.number(value),
					Format.number(value)
				)
			)
		else
			Net.notify(
				player,
				"info",
				string.format(
					"이미 러닝머신 부스트 x%s 가 있어서 그대로예요. (부스트는 가장 큰 것 하나만 적용돼요)",
					Format.number(data.treadmillBoost)
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

-- MarketplaceService.ProcessReceipt 콜백 (yield 할 수 있음)
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
	local waited = 0
	while not Sessions.getLoaded(player) and player.Parent ~= nil and waited < ProductService.LOAD_WAIT_SECONDS do
		task.wait(0.5)
		waited += 0.5
	end
	local session, data = Sessions.getLoaded(player)
	if not session or not data or player.Parent == nil then
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

-- 접속 준비: Attr TreadmillBoost · MoneyPass
function ProductService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	if data then
		syncAttributes(player, data)
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
end

return ProductService
