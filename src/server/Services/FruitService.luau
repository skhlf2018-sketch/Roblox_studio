--!strict
--[[
	FruitService — 열매 (6판 "씨앗을 훔치세요" 새 서비스, 사장님 결정 1: 성체 열매를 따서 팔아야 코인). 규칙은 shared/FruitRules

	- 맺기 (1초마다): 정원의 성체 식물마다 fruitIntervalSeconds(Data/Plants)마다 열매 +1, 최대 FRUIT_MAX_PER_PLANT(5).
	    밤에도 빠르기 그대로. 오프라인 동안에도 맺음 (접속할 때 한 번에, 상한 24시간 — 어차피 5개까지)
	    열매 수가 바뀌면 DataUpdate("pets") (BaseService 가 GardenPlant 파트 Attribute Fruits 를 맞춤)
	- Remote PickFruit(plantUid | "all"): 내 정원 GARDEN_ACTION_RADIUS(20) 안에서 그 성체(또는 전부)의 열매를 전부 따서
	    열매 가방(data.fruits)으로 (가방 자리만큼만). 열매 1개 값 = 딸 때의 FruitRules.fruitValue (크기·돌연변이)
	    → FruitPicked { plantUid, petId, count, value } (식물마다) + DataUpdate("fruits"/"pets")
	- Remote SellFruits(): 판매 가판대 SELL_RADIUS(14) 안에서 가방의 열매를 전부 팜 → 코인 (코인 2배 게임패스면 × 2)
	    → FruitsSold { count, coins } + Notify + FruitService.sold:fire(player, count, coins) (튜토리얼 5단계)
	- Remote FeedFruit(plantUid, fruitId): 내 정원 20 안에서 가방의 그 열매(fruitId = 열매를 맺은 식물 id) 1개를
	    성체에게 먹임 → 확률로 돌연변이 (FruitRules.feedOptions: 황금·무지개·얼음·불·번개). 더 붙을 것이 없는
	    식물이면 거부(열매 그대로). → FeedResult { plantUid, fruitId, mutation? } + Notify
	- 플레이어 Attr FruitCount(가방 열매 수) · FruitBagValue(다 팔면 받는 코인, 게임패스 배율 전)
	(자동 수입 IncomeService 는 6판에서 없앰)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Plants = require(Shared.Data.Plants)
local Mutations = require(Shared.Data.Mutations)
local Economy = require(Shared.Economy)
local FruitRules = require(Shared.FruitRules)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)
local Signal = require(Server.Util.Signal)
local Wallet = require(script.Parent.Wallet)
local PetService = require(script.Parent.PetService)

type PetRecord = Types.PetRecord

local Attr = Tags.PlayerAttributes

local FruitService = {}

-- 열매를 팖 (player, count, coins) → TutorialService (5단계 "열매 따서 팔기")
FruitService.sold = Signal.new()

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local function coins(n: number): string
	return Format.number(n) .. " 코인"
end

local function plantName(petId: string): string
	local plant = Plants.get(petId)
	return if plant then plant.name else petId
end

-- 가방 Attribute (HUD 배지·가판대 미리보기)
local function syncBag(player: Player, data: Types.PlayerData)
	player:SetAttribute(Attr.FruitCount, FruitRules.bagCount(data.fruits))
	player:SetAttribute(Attr.FruitBagValue, FruitRules.bagValue(data.fruits))
end

-- 열매 가방이 밖에서 바뀐 뒤 (개발 명령 /fruit): Attribute + DataUpdate("fruits")
function FruitService.refreshBag(player: Player)
	local _, data = Sessions.getLoaded(player)
	if data then
		syncBag(player, data)
		Snapshot.section(player, "fruits")
	end
end

-- 성체마다 dt 초만큼 열매 맺기. 열매 수가 바뀐 식물이 있으면 true
local function produce(data: Types.PlayerData, dt: number): boolean
	local changed = false
	for _, plant in data.pets do
		local before = plant.fruits
		plant.fruits, plant.fruitProgress =
			FruitRules.produce(plant.fruits, plant.fruitProgress, dt, Economy.fruitInterval(plant.petId))
		if plant.fruits ~= before then
			changed = true
		end
	end
	return changed
end

-- 1초마다: 모든 사람의 성체가 열매를 맺음
local function fruitTick(dt: number): ...any
	for player, session in Sessions.all() do
		local data = session.data
		if session.loaded and data and #data.pets > 0 then
			if produce(data, dt) then
				Snapshot.section(player, "pets")
			end
		end
	end
end

------------------------------------------------------------------
-- 따기 / 팔기 / 먹이기
------------------------------------------------------------------

-- PickFruit: 그 성체("all" 이면 전부)의 열매를 가방으로. 딴 열매 수
function FruitService.pick(player: Player, which: string): number
	local _, data = Sessions.getLoaded(player)
	if not data then
		return 0
	end
	local targets: { PetRecord } = {}
	if which == "all" then
		targets = data.pets
	else
		local plant = PetService.findPlant(player, which)
		if not plant then
			return 0 -- 남의 식물·자라는 씨앗·이상한 uid (조용히)
		end
		targets = { plant }
	end
	if not PetService.isNearOwnPen(player, Config.GARDEN_ACTION_RADIUS) then
		Net.notify(player, "error", "내 정원 가까이에서 열매를 딸 수 있어요!")
		return 0
	end
	local hadFruit, picked = false, 0
	for _, plant in targets do
		if plant.fruits > 0 then
			hadFruit = true
			local value = FruitRules.fruitValue(plant)
			local n = FruitRules.addToBag(data.fruits, plant.petId, plant.fruits, value)
			if n > 0 then
				plant.fruits -= n
				picked += n
				Net.fire(player, Remotes.ToClient.FruitPicked, {
					plantUid = plant.uid,
					petId = plant.petId,
					count = n,
					value = n * value,
				})
			end
		end
	end
	if picked == 0 then
		if hadFruit then
			Net.notify(
				player,
				"error",
				string.format(
					"열매 가방이 가득 찼어요 (%d개)! 판매 가판대에서 먼저 파세요.",
					Config.FRUIT_BAG_MAX
				)
			)
		else
			Net.notify(player, "info", "아직 딸 열매가 없어요. 조금만 기다려 주세요!")
		end
		return 0
	end
	data.stats.fruitsPicked = (data.stats.fruitsPicked or 0) + picked
	syncBag(player, data)
	Snapshot.section(player, "fruits")
	PetService.changed(player)
	return picked
end

-- SellFruits: 가방의 열매를 전부 팖. 받은 코인 (못 팔면 nil)
function FruitService.sellAll(player: Player): number?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	if not PetService.isNearSellStall(player) then
		Net.notify(player, "error", "판매 가판대 가까이에서 열매를 팔 수 있어요!")
		return nil
	end
	local count = FruitRules.bagCount(data.fruits)
	if count <= 0 then
		Net.notify(player, "info", "팔 열매가 없어요! 정원에서 열매를 먼저 따 오세요.")
		return nil
	end
	local earned = FruitRules.bagValue(data.fruits) * PetService.coinMultiplier(player)
	table.clear(data.fruits)
	Wallet.addMoney(player, earned)
	data.stats.fruitsSold = (data.stats.fruitsSold or 0) + count
	syncBag(player, data)
	Snapshot.section(player, "fruits")
	Net.fire(player, Remotes.ToClient.FruitsSold, { count = count, coins = earned })
	Net.notify(player, "success", string.format("열매 %d개를 팔았어요! +%s", count, coins(earned)))
	FruitService.sold:fire(player, count, earned)
	return earned
end

-- FeedFruit: 가방의 열매(fruitId = 식물 id) 1개를 성체에게 → 확률로 돌연변이. 붙은 돌연변이 id (안 붙거나 못 하면 nil)
function FruitService.feed(player: Player, plantUid: string, fruitId: string): string?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	local plant = PetService.findPlant(player, plantUid)
	local stack = data.fruits[fruitId]
	if not plant or not stack or stack.count < 1 then
		return nil -- 내 성체가 아니거나 그 열매가 가방에 없음 (조용히)
	end
	if not PetService.isNearOwnPen(player, Config.GARDEN_ACTION_RADIUS) then
		Net.notify(player, "error", "내 정원 가까이에서 열매를 먹일 수 있어요!")
		return nil
	end
	if #FruitRules.feedOptions(fruitId, plant.mutations) == 0 then
		Net.notify(player, "error", plantName(plant.petId) .. " 에게는 더 생길 돌연변이가 없어요!")
		return nil
	end
	FruitRules.takeOne(data.fruits, fruitId)
	local mutationId = FruitRules.rollFeed(fruitId, plant.mutations, rand)
	if mutationId then
		plant.mutations = FruitRules.applyMutation(plant.mutations, mutationId)
	end
	data.stats.fruitsFed = (data.stats.fruitsFed or 0) + 1
	syncBag(player, data)
	Snapshot.section(player, "fruits")
	PetService.changed(player)
	Net.fire(player, Remotes.ToClient.FeedResult, { plantUid = plant.uid, fruitId = fruitId, mutation = mutationId })
	local mutation = if mutationId then Mutations.get(mutationId) else nil
	if mutation then
		Net.notify(
			player,
			"success",
			string.format(
				"%s 에 %s 돌연변이가 생겼어요! 열매 값 ×%s",
				plantName(plant.petId),
				mutation.name,
				tostring(mutation.multiplier)
			)
		)
	else
		Net.notify(player, "info", "냠냠… 이번엔 아무 일도 없었어요. 다른 열매도 먹여 보세요!")
	end
	return mutationId
end

------------------------------------------------------------------
-- 플레이어 / 시작
------------------------------------------------------------------

-- 접속 준비 (BaseService.onPlayerReady 보다 먼저: 이미 성체였던 식물만 오프라인 열매를 맺음)
function FruitService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	local offline = Economy.offlineGrowthSeconds(data.lastSaveTime, os.time())
	if offline > 0 then
		produce(data, offline)
	end
	syncBag(player, data)
end

function FruitService.start()
	Net.on(Remotes.ToServer.PickFruit, function(player: Player, which: unknown)
		local uid = Validate.uid(which)
		if uid then
			FruitService.pick(player, uid)
		end
	end)
	Net.on(Remotes.ToServer.SellFruits, function(player: Player)
		FruitService.sellAll(player)
	end)
	Net.on(Remotes.ToServer.FeedFruit, function(player: Player, uid: unknown, fruit: unknown)
		local plantUid = Validate.uid(uid)
		local fruitId = Validate.uid(fruit)
		if plantUid and fruitId and Plants.get(fruitId) then
			FruitService.feed(player, plantUid, fruitId)
		end
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local dt = math.clamp(now - last, 0, 5) -- 서버가 잠깐 멈춰도 한 번에 너무 많이 주지 않음
			last = now
			local ok, err = pcall(fruitTick, dt)
			if not ok then
				warn("[FruitService] 열매 오류: " .. tostring(err))
			end
		end
	end)
end

return FruitService
