--!strict
--[[
	SakuraService — 벚꽃 구역 사쿠라 인큐베이터 + 사쿠라 크리스탈 (설계문서 4장). 규칙은 shared/SakuraRules.luau

	- 인큐베이터: Tag "SakuraIncubator" 파트 (맵에 없으면 벚꽃 구역 안에 임시 파트를 만듦)
	- Remote SakuraOffer(petUid?): 인큐베이터 근처에서 학(Crane) 1마리를 바쳐 해금 (저장: sakuraUnlocked)
	    uid 를 안 주면 가진 학 중 수입이 가장 낮은 학을 바침. 장착 중이면 자동 해제.
	- Remote SakuraApply(targetUid): 인큐베이터 근처에서 크리스탈 SAKURA_APPLY_COST 개를 써서
	    부화 중인 알(uid "i..") 또는 보관 펫(uid "p..")에 블룸 97.5% / 스피릿 블룸 2.5%.
	    블룸은 자연 돌연변이 위에 겹칠 수 있고, 블룸끼리는 안 됨.
	- 크리스탈 얻기 (저장: sakuraCrystals):
	    벚꽃 구역 알을 내 베이스에 배달할 때마다 SAKURA_CRYSTALS_PER_DELIVERY 개
	    초기화(대기 단계) 때마다 벚꽃 둥지 근처에 SAKURA_CRYSTAL_DROPS_PER_RESET 개가 떨어짐 → 먼저 줍는 사람 것 (E 키)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local Mutations = require(Shared.Data.Mutations)
local Economy = require(Shared.Economy)
local EggRoll = require(Shared.EggRoll)
local SakuraRules = require(Shared.SakuraRules)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local MapLayout = require(Shared.Data.MapLayout)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Character = require(Server.Util.Character)
local Landmarks = require(Server.Util.Landmarks)
local Validate = require(Server.Logic.Validate)
local MapBuilder = require(script.Parent.MapBuilder)
local EggService = require(script.Parent.EggService)
local BaseService = require(script.Parent.BaseService)
local PetService = require(script.Parent.PetService)

local BIOME = "cherry_blossom"
local Attr = Tags.PlayerAttributes

local SakuraService = {}

local incubators: { BasePart } = {}
local crystals: { [string]: BasePart } = {}
local crystalCounter = 0
local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local function syncCrystals(player: Player, data: Types.PlayerData)
	player:SetAttribute(Attr.SakuraCrystals, data.sakuraCrystals)
	player:SetAttribute(Attr.SakuraUnlocked, data.sakuraUnlocked)
	Snapshot.section(player, "special")
end

function SakuraService.addCrystals(player: Player, amount: number)
	local _, data = Sessions.getLoaded(player)
	if not data or amount <= 0 then
		return
	end
	data.sakuraCrystals = math.min(Config.SAKURA_CRYSTAL_MAX, data.sakuraCrystals + math.floor(amount))
	syncCrystals(player, data)
end

local function nearIncubator(player: Player): boolean
	return Landmarks.nearest(player, incubators, Config.SAKURA_RADIUS) ~= nil
end

------------------------------------------------------------------
-- 해금 (학 바치기)
------------------------------------------------------------------

function SakuraService.offer(player: Player, requestedUid: string?)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	if data.sakuraUnlocked then
		Net.notify(player, "info", "사쿠라 인큐베이터는 이미 열려 있어요.")
		return
	end
	if not nearIncubator(player) then
		Net.notify(player, "error", "벚꽃 구역의 사쿠라 인큐베이터 가까이에서 바칠 수 있어요!")
		return
	end
	local pets = data.pets
	local index = SakuraRules.pickOffering(pets, function(i: number): number
		return Economy.recordIncome(pets[i])
	end, requestedUid)
	if not index then
		local crane = Pets.get(Config.SAKURA_UNLOCK_PET)
		Net.notify(
			player,
			"error",
			(if crane then crane.name else "학") .. " 펫이 있어야 사쿠라 인큐베이터를 열 수 있어요!"
		)
		return
	end
	local uid = pets[index].uid
	if not PetService.removePets(player, { uid }) then
		return
	end
	data.sakuraUnlocked = true
	syncCrystals(player, data)
	Net.fire(
		player,
		Remotes.ToClient.SakuraResult,
		{ kind = "unlocked", consumed = uid, crystals = data.sakuraCrystals }
	)
	Net.notify(
		player,
		"success",
		"사쿠라 인큐베이터가 열렸어요! 크리스탈로 알과 펫을 꽃피워 보세요."
	)
end

------------------------------------------------------------------
-- 블룸 부여
------------------------------------------------------------------

function SakuraService.apply(player: Player, targetUid: string)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	if not data.sakuraUnlocked then
		Net.notify(player, "error", "먼저 학 펫을 바쳐 사쿠라 인큐베이터를 여세요!")
		return
	end
	if not nearIncubator(player) then
		Net.notify(player, "error", "사쿠라 인큐베이터 가까이에서만 쓸 수 있어요!")
		return
	end
	if not SakuraRules.canAfford(data.sakuraCrystals) then
		Net.notify(
			player,
			"error",
			string.format("사쿠라 크리스탈이 %d개 필요해요!", Config.SAKURA_APPLY_COST)
		)
		return
	end
	local egg = BaseService.findIncubator(player, targetUid)
	local pet = if egg then nil else PetService.findPet(player, targetUid)
	local current = if egg then egg.mutations elseif pet then pet.mutations else nil
	if not current then
		return
	end
	local ok, reason = SakuraRules.canApply(current)
	if not ok then
		Net.notify(player, "error", reason or "블룸을 붙일 수 없어요.")
		return
	end
	local bloomId = SakuraRules.roll(rand)
	data.sakuraCrystals -= Config.SAKURA_APPLY_COST
	if egg then
		egg.mutations = SakuraRules.apply(egg.mutations, bloomId)
		BaseService.refreshIncubator(player, egg.uid)
	elseif pet then
		pet.mutations = SakuraRules.apply(pet.mutations, bloomId)
		PetService.changed(player)
	end
	syncCrystals(player, data)
	local mutation = Mutations.get(bloomId)
	Net.fire(player, Remotes.ToClient.SakuraResult, {
		kind = "bloom",
		targetUid = targetUid,
		target = if egg then "egg" else "pet",
		mutation = bloomId,
		crystals = data.sakuraCrystals,
	})
	Net.notify(
		player,
		"success",
		(if mutation then mutation.name else bloomId)
			.. " 돌연변이가 피었어요! (×"
			.. (if mutation then tostring(mutation.multiplier) else "?")
			.. ")"
	)
end

------------------------------------------------------------------
-- 크리스탈 줍기 (초기화 때 벚꽃 둥지 근처에 떨어짐)
------------------------------------------------------------------

local function clearCrystals()
	for uid, part in crystals do
		part:Destroy()
		crystals[uid] = nil
	end
end

local function pickupCrystal(player: Player, uid: string)
	local part = crystals[uid]
	local _, data = Sessions.getLoaded(player)
	local root = Character.getRoot(player)
	if not part or not data or not root or not Character.isAlive(player) then
		return
	end
	if (root.Position - part.Position).Magnitude > Config.SAKURA_CRYSTAL_PICKUP_DISTANCE then
		return -- 너무 멀리서 요청
	end
	crystals[uid] = nil
	part:Destroy()
	SakuraService.addCrystals(player, 1)
	Net.notify(player, "success", "사쿠라 크리스탈을 주웠어요! (" .. data.sakuraCrystals .. "개)")
end

local function spawnCrystals()
	clearCrystals()
	local nests = EggService.nestPositions(BIOME)
	if #nests == 0 then
		return
	end
	local picks = EggRoll.pickDistinct(#nests, Config.SAKURA_CRYSTAL_DROPS_PER_RESET, rand)
	for _, index in picks do
		local nest = nests[index]
		local angle = rand() * math.pi * 2
		local around = nest + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (5 + rand() * 4)
		local y = MapBuilder.groundY(around, {})
		crystalCounter += 1
		local uid = "c" .. tostring(crystalCounter)
		local part = Instance.new("Part")
		part.Name = "SakuraCrystal_" .. uid
		part.Size = Vector3.new(1.2, 2, 1.2)
		part.CFrame = CFrame.new(around.X, y + 1.4, around.Z) * CFrame.Angles(0, angle, math.rad(15))
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 160, 210)
		part:SetAttribute("CrystalUid", uid)
		CollectionService:AddTag(part, Tags.SakuraCrystal)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CrystalPrompt"
		prompt.ActionText = "줍기"
		prompt.ObjectText = "사쿠라 크리스탈"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Config.PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		prompt.Triggered:Connect(function(player: Player)
			pickupCrystal(player, uid)
		end)
		part.Parent = Landmarks.folder()
		crystals[uid] = part
	end
end

------------------------------------------------------------------
-- 시작
------------------------------------------------------------------

local function ensureIncubator()
	-- 자리 = MapLayout.specials.sakuraIncubator (선임이 같은 태그로 진짜 모델을 두면 임시 파트는 안 생김)
	local spot = MapLayout.specials.sakuraIncubator
	incubators = Landmarks.ensure({
		tag = Tags.SakuraIncubator,
		name = "SakuraIncubator",
		label = "사쿠라 인큐베이터\n(학을 바쳐 열기)",
		position = Vector3.new(spot.x, MapLayout.FLOOR_Y + 3, spot.z),
		size = Vector3.new(8, 6, 8),
		color = Color3.fromRGB(255, 170, 210),
		material = Enum.Material.Glass,
		transparency = 0.2,
	})
end

function SakuraService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	if data then
		player:SetAttribute(Attr.SakuraCrystals, data.sakuraCrystals)
		player:SetAttribute(Attr.SakuraUnlocked, data.sakuraUnlocked)
	end
end

function SakuraService.start()
	ensureIncubator()

	Net.on(Remotes.ToServer.SakuraOffer, function(player: Player, uid: unknown)
		if uid ~= nil and Validate.uid(uid) == nil then
			return
		end
		SakuraService.offer(player, Validate.uid(uid))
	end)
	Net.on(Remotes.ToServer.SakuraApply, function(player: Player, uid: unknown)
		local targetUid = Validate.uid(uid)
		if targetUid then
			SakuraService.apply(player, targetUid)
		end
	end)

	BaseService.delivered:connect(function(player: Player, record: Types.IncubatorRecord)
		if record.biomeId == BIOME then
			SakuraService.addCrystals(player, Config.SAKURA_CRYSTALS_PER_DELIVERY)
		end
	end)
	EggService.resetDone:connect(function()
		spawnCrystals()
	end)
end

return SakuraService
