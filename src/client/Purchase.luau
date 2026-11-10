--!strict
--[[
	Purchase — 로벅스 상품 사기 공통 (9판, 선임 · 사장님 2026-11-10)

	  Purchase.prompt("boost_8")   → 결과 "prompted" | "notready" | "busy" | "unknown"
	    · 상품이 없으면 "unknown"
	    · Products.isConfigured 가 false (productId 0 = 아직 Creator Dashboard 에서 안 만듦) → 구매창 없이
	      토스트 "준비 중이에요 — 어른과 함께 상품을 만들어야 살 수 있어요" → "notready"
	    · 설정됐으면 개발자 상품은 MarketplaceService:PromptProductPurchase(나, productId),
	      게임패스(product.isPass — 부스트 11개 · 코인 2배, 62번)는 PromptGamePassPurchase(나, productId = gamePassId) → "prompted"
	    · 연타 방지: 창을 띄운 뒤 BUSY_SECONDS 동안(또는 PromptProductPurchaseFinished · PromptGamePassPurchaseFinished 가 올 때까지)
	      다시 안 띄움 → "busy"
	  돈을 받고 지급하는 것은 전부 서버 (상품 ProcessReceipt · 패스 소유 확인 → ProductService). 클라는 구매창만 띄움.
	  서버 ProductGranted { key, kind } → 팡파레(ProductGranted 소리) + 화면 가운데 "🎉 ○○ 받았어요!" + Purchase.onGranted 구독자
	    (상점·스피드 배수 창·러닝머신 창이 다시 그림).
	  Purchase.robux(n) = "R$ 2,048" (가격 글자 통일)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Products = require(Shared.Data.Products)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Net = require(script.Parent.Net)
local Theme = require(script.Parent.UI.Theme)
local Ui = require(script.Parent.UI.Ui)
local NotifyController = require(script.Parent.Controllers.NotifyController)
local SoundController = require(script.Parent.Controllers.SoundController)

local Purchase = {}

Purchase.NOT_READY = "준비 중이에요 — 어른과 함께 상품을 만들어야 살 수 있어요"
Purchase.BUSY_SECONDS = 2
Purchase.TOAST_COOLDOWN = 1 -- "준비 중" 토스트는 1초에 한 번만

local C = Theme.Colors
local busyUntil = -math.huge
local lastNotReady = -math.huge
local listeners: { (Types.ProductGrant) -> () } = {}

-- "R$ 2,048"
function Purchase.robux(n: number): string
	local s = tostring(math.max(0, math.floor(n)))
	local out = s
	for _ = 1, 8 do -- 쉼표 넣기 (자리 수 24 까지면 충분, 끝없는 루프 없이)
		local replaced, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return "R$ " .. out
end

-- 상품이 준비됐나 (없는 key 도 false)
function Purchase.ready(key: string): boolean
	local product = Products.get(key)
	return product ~= nil and Products.isConfigured(product)
end

function Purchase.prompt(key: string): string
	local product = Products.get(key)
	if not product then
		warn("[Purchase] 모르는 상품: " .. tostring(key))
		return "unknown"
	end
	local now = os.clock()
	if not Products.isConfigured(product) then
		-- 같은 토스트가 줄줄이 쌓이지 않게 1초에 한 번만
		if now - lastNotReady > Purchase.TOAST_COOLDOWN then
			lastNotReady = now
			NotifyController.toast(Purchase.NOT_READY, "info")
			SoundController.play("Notify")
		end
		return "notready"
	end
	if now < busyUntil then
		return "busy"
	end
	busyUntil = now + Purchase.BUSY_SECONDS
	local ok, err = pcall(function()
		if product.isPass then
			-- 게임패스 (62번: 부스트 11개 · 코인 2배) — productId 칸이 gamePassId
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, product.productId)
		else
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.productId)
		end
	end)
	if not ok then
		busyUntil = -math.huge
		warn("[Purchase] 구매창을 못 띄움: " .. tostring(err))
		NotifyController.toast("구매창을 열 수 없어요. 잠시 뒤에 다시 해 봐요", "error")
		return "error"
	end
	return "prompted"
end

-- 상품을 받았을 때 부를 함수 (끊기 함수를 돌려줌)
function Purchase.onGranted(fn: (Types.ProductGrant) -> ()): () -> ()
	table.insert(listeners, fn)
	return function()
		local i = table.find(listeners, fn)
		if i then
			table.remove(listeners, i)
		end
	end
end

-- 화면 가운데 "🎉 ○○ 받았어요!" (잠깐)
local function celebrate(text: string)
	local holder: Frame = Ui.new("Frame", {
		Name = "ProductGrantedPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(560, 120),
		BackgroundTransparency = 1,
		Parent = Ui.layer("Popups"),
	})
	Ui.scaled(holder, Vector2.new(560, 120))
	local big = Ui.label("🎉 " .. text, UDim2.new(1, 0, 0, 64), 48, C.yellow, {
		Name = "Title",
		TextScaled = true,
		Parent = holder,
	})
	local stroke = big:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = C.winEdge
		stroke.Thickness = 5
	end
	Ui.label("고마워요!", UDim2.new(1, 0, 0, 36), 28, C.white, {
		Name = "Sub",
		Position = UDim2.fromOffset(0, 70),
		Parent = holder,
	})
	Ui.pop(holder, 1.5)
	task.delay(2.4, function()
		holder:Destroy()
	end)
end

-- ProductGranted 처리 (테스트도 부름). 알맞은 신호면 true
function Purchase.granted(payload: any): boolean
	if typeof(payload) ~= "table" or typeof(payload.key) ~= "string" then
		return false
	end
	local product = Products.get(payload.key)
	local grant: Types.ProductGrant = {
		key = payload.key,
		kind = if typeof(payload.kind) == "string" then payload.kind elseif product then product.kind else "",
	}
	busyUntil = -math.huge
	SoundController.play("ProductGranted")
	celebrate((if product then product.name else grant.key) .. " 받았어요!")
	for _, fn in table.clone(listeners) do
		task.spawn(fn, grant)
	end
	return true
end

local started = false
function Purchase.start()
	if started then
		return
	end
	started = true
	Net.onLater(Remotes.ToClient.ProductGranted, Purchase.granted)
	-- 구매창을 닫으면(샀든 안 샀든) 바로 다시 누를 수 있게
	pcall(function()
		MarketplaceService.PromptProductPurchaseFinished:Connect(function()
			busyUntil = -math.huge
		end)
	end)
	-- 게임패스 구매창도 (지급은 서버가 소유를 확인해서 ProductGranted 로 — 여기서는 창 닫기만)
	pcall(function()
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
			busyUntil = -math.huge
		end)
	end)
end

return Purchase
