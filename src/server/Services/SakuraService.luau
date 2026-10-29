--!strict
--[[
	SakuraService — 벚꽃 구역 사쿠라 나무 + 사쿠라 크리스탈 (6판 "씨앗을 훔치세요" 씨앗 버전, 사장님 결정 4).
	규칙은 shared/SakuraRules.luau. 모듈·태그 이름은 5판 그대로 (SakuraIncubator 태그 = 사쿠라 나무)

	- 나무: Tag "SakuraIncubator" 파트 (맵에 없으면 벚꽃 구역 안 MapLayout.specials.sakuraIncubator 자리에 임시 파트)
	- Remote SakuraOffer(plantUid): 나무 SAKURA_RADIUS(14) 안에서 내 정원의 성체 식물 1그루를 바침 → 크리스탈
	    (등급별 Config.SAKURA_OFFER_CRYSTALS: 일반 1 … 슈퍼 100 … 해커 글리치 700, 7판). 정원 자리가 빔.
	    → SakuraResult { kind = "offered", consumed = plantUid, petId, gained, crystals } + Notify
	- Remote SakuraDraw(): 나무 근처에서 크리스탈 SAKURA_DRAW_COST(10) 개로 특별 씨앗 뽑기 → 씨앗 가방으로
	    벚꽃 씨앗(벚꽃 요정 나무) 97.5% / 정령 벚꽃 씨앗(정령 벚꽃 나무) 2.5%. 크기·자연 돌연변이는 둥지 씨앗처럼 굴림.
	    가방이 가득 차면 거부 (크리스탈 그대로). → EggGranted(source "sakura") + SakuraResult { kind = "draw", petId, egg, crystals }
	- 크리스탈 얻기 (저장: sakuraCrystals): 성체 바치기 · 벚꽃 구역 씨앗을 배달할 때마다 SAKURA_CRYSTALS_PER_DELIVERY 개 ·
	    초기화(대기 단계) 때마다 벚꽃 둥지 근처에 SAKURA_CRYSTAL_DROPS_PER_RESET 개가 떨어짐 → 먼저 줍는 사람 것 (E 키)
	(5판의 학 바쳐서 해금·블룸 돌연변이 붙이기(SakuraApply)는 없앰)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Plants = require(Shared.Data.Plants)
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

local function nearTree(player: Player): boolean
	return Landmarks.nearest(player, incubators, Config.SAKURA_RADIUS) ~= nil
end

------------------------------------------------------------------
-- 성체 바치기 → 크리스탈
------------------------------------------------------------------

-- 받은 크리스탈 수 (못 바치면 nil)
function SakuraService.offer(player: Player, plantUid: string): number?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	if not nearTree(player) then
		Net.notify(player, "error", "벚꽃 구역의 사쿠라 나무 가까이에서 바칠 수 있어요!")
		return nil
	end
	local plant = PetService.findPlant(player, plantUid)
	if not plant then
		Net.notify(
			player,
			"error",
			"바칠 성체 식물을 골라 주세요! (정원에 자란 식물만 바칠 수 있어요)"
		)
		return nil
	end
	local gained = SakuraRules.crystalsFor(plant.petId)
	if not PetService.removePlants(player, { plantUid }) then
		return nil
	end
	data.sakuraCrystals = math.min(Config.SAKURA_CRYSTAL_MAX, data.sakuraCrystals + gained)
	syncCrystals(player, data)
	local def = Plants.get(plant.petId)
	Net.fire(player, Remotes.ToClient.SakuraResult, {
		kind = "offered",
		consumed = plantUid,
		petId = plant.petId,
		gained = gained,
		crystals = data.sakuraCrystals,
	})
	Net.notify(
		player,
		"success",
		string.format(
			"%s 을(를) 바쳐서 사쿠라 크리스탈 %d개를 받았어요! (지금 %d개)",
			if def then def.name else plant.petId,
			gained,
			data.sakuraCrystals
		)
	)
	return gained
end

------------------------------------------------------------------
-- 특별 씨앗 뽑기
------------------------------------------------------------------

-- 뽑은 식물 id (못 뽑으면 nil)
function SakuraService.draw(player: Player): string?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	if not nearTree(player) then
		Net.notify(player, "error", "사쿠라 나무 가까이에서만 뽑을 수 있어요!")
		return nil
	end
	if not SakuraRules.canAfford(data.sakuraCrystals) then
		Net.notify(
			player,
			"error",
			string.format(
				"사쿠라 크리스탈이 %d개 필요해요! (지금 %d개)",
				Config.SAKURA_DRAW_COST,
				data.sakuraCrystals
			)
		)
		return nil
	end
	if not BaseService.canReceiveEgg(player) then
		Net.notify(player, "error", "씨앗 가방이 가득 찼어요! 씨앗을 먼저 정원에 심어 주세요.")
		return nil
	end
	local petId = SakuraRules.roll(rand)
	local traits = EggRoll.rollTraits(rand)
	if not BaseService.grantEgg(player, petId, traits.size, traits.mutations, "sakura") then
		return nil
	end
	data.sakuraCrystals -= Config.SAKURA_DRAW_COST
	syncCrystals(player, data)
	local egg = data.eggs[#data.eggs]
	Net.fire(player, Remotes.ToClient.SakuraResult, {
		kind = "draw",
		petId = petId,
		egg = egg,
		crystals = data.sakuraCrystals,
	})
	Net.notify(player, "success", Plants.seedName(petId) .. " 이(가) 나왔어요! 씨앗 가방을 확인하세요.")
	return petId
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
		label = "사쿠라 나무\n(성체 바치기 · 씨앗 뽑기)",
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
	end
end

function SakuraService.start()
	ensureIncubator()

	Net.on(Remotes.ToServer.SakuraOffer, function(player: Player, uid: unknown)
		local plantUid = Validate.uid(uid)
		if plantUid then
			SakuraService.offer(player, plantUid)
		end
	end)
	Net.on(Remotes.ToServer.SakuraDraw, function(player: Player)
		SakuraService.draw(player)
	end)

	BaseService.delivered:connect(function(player: Player, record: Types.BagEgg)
		if record.biomeId == BIOME then
			SakuraService.addCrystals(player, Config.SAKURA_CRYSTALS_PER_DELIVERY)
		end
	end)
	EggService.resetDone:connect(function()
		spawnCrystals()
	end)
end

return SakuraService
