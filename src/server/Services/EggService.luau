--!strict
--[[
	EggService — 둥지 알 생성, 줍기, 들고 다니기, 놓치기 (서버 권한)

	알 상태:
	  "Nest"    둥지 위 (ProximityPrompt E 로 줍기)
	  "Carried" 누군가 머리 위에 들고 있음 (Weld)
	  "Dropped" 바닥에 떨어짐 (누구나 다시 주울 수 있음, DROPPED_EGG_LIFETIME 뒤 사라짐)

	둥지 예약 규칙 (잡힘 규칙을 지키기 위해):
	  둥지에서 알을 들면 그 둥지는 "예약" 상태로 비어 있음 (다시 채워지지 않음).
	  들고 있는 사람이 알의 구역 밖으로 나가면 예약이 풀리고 NEST_RESPAWN_SECONDS 뒤 새 알이 놓임.
	  구역 안에서 잡히면 → 예약된 원래 둥지로 돌아감 (EggRules.dropOutcome = "ReturnToNest").
	  구역 밖에서 잡히면 → 그 자리에 떨어짐.

	대기(Intermission) 때: 둥지·바닥 알 전부 지우고 새로 놓음 + "ALL EGG RESET!" + 희귀 알 추첨/공지.
	들고 있는 알은 지우지 않음 (밤에 베이스로 텔레포트되어 배달 가능).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Biomes = require(Shared.Data.Biomes)
local Pets = require(Shared.Data.Pets)
local Rarities = require(Shared.Data.Rarities)
local Sizes = require(Shared.Data.Sizes)
local Mutations = require(Shared.Data.Mutations)
local EggRoll = require(Shared.EggRoll)
local EggRules = require(Shared.EggRules)
local Cycle = require(Shared.Cycle)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Character = require(Server.Util.Character)
local Gui = require(Server.Util.Gui)
local Ragdoll = require(Server.Util.Ragdoll)
local MapBuilder = require(script.Parent.MapBuilder)
local CycleService = require(script.Parent.CycleService)
local SpeedService = require(script.Parent.SpeedService)

type EggInfo = Types.EggInfo
type CatchCause = EggRules.CatchCause
type EggOutcome = EggRules.EggOutcome

export type EggState = "Nest" | "Carried" | "Dropped"

export type Egg = {
	uid: string,
	petId: string,
	biomeId: string,
	rarity: string,
	size: string,
	mutations: { string },
	special: boolean,
	part: BasePart,
	prompt: ProximityPrompt,
	state: EggState,
	nestBiome: string?,
	nestIndex: number?,
	carrier: Player?,
	pickedAt: number,
	droppedAt: number,
}

type NestSlot = {
	biomeId: string,
	index: number,
	part: BasePart,
	eggUid: string?,
	respawnAt: number?,
}

-- 배달할 때 넘겨주는 알 데이터
export type DeliveredEgg = {
	petId: string,
	biomeId: string,
	size: string,
	mutations: { string },
	special: boolean,
}

local Attr = Tags.PlayerAttributes

local EggService = {}

local eggs: { [string]: Egg } = {}
local nests: { [string]: { NestSlot } } = {}
local eggCounter = 0
local rng = Random.new()

local function rand(): number
	return rng:NextNumber()
end

------------------------------------------------------------------
-- 알 정보 / 겉모습
------------------------------------------------------------------

function EggService.info(egg: Egg): EggInfo
	return {
		uid = egg.uid,
		petId = egg.petId,
		biomeId = egg.biomeId,
		rarity = egg.rarity,
		size = egg.size,
		mutations = table.clone(egg.mutations),
		special = egg.special,
	}
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function eggDiameter(sizeId: string): number
	local size = Sizes.get(sizeId)
	return Config.EGG_BASE_DIAMETER * (if size then size.eggScale else 1)
end

-- 파트를 만들 때 필요한 알 정보
type EggSeed = {
	uid: string,
	petId: string,
	biomeId: string,
	rarity: string,
	size: string,
	mutations: { string },
	special: boolean,
}

local function eggTitle(egg: EggSeed): string
	local pet = Pets.get(egg.petId)
	local rarity = Rarities.get(egg.rarity)
	local size = Sizes.get(egg.size)
	local parts: { string } = {}
	for _, id in egg.mutations do
		local m = Mutations.get(id)
		if m then
			table.insert(parts, m.name)
		end
	end
	if size and size.id ~= "normal" then
		table.insert(parts, size.name)
	end
	table.insert(parts, (if pet then pet.name else egg.petId) .. " 알")
	return table.concat(parts, " ") .. "\n" .. (if rarity then rarity.name else egg.rarity)
end

-- 알 파트 만들기 (선임이 나중에 메시로 바꿀 자리: 크기·색만 간단히)
local function makeEggPart(egg: EggSeed): (BasePart, ProximityPrompt)
	local d = eggDiameter(egg.size)
	local part = Instance.new("Part")
	part.Name = "Egg_" .. egg.uid
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(d, d * 1.25, d)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local rarity = Rarities.get(egg.rarity)
	part.Color = if rarity then rgb(rarity.color) else Color3.new(1, 1, 1)
	part.Material = Enum.Material.SmoothPlastic
	local natural = egg.mutations[1]
	local mutation = if natural then Mutations.get(natural) else nil
	if mutation then
		part.Color = rgb(mutation.color)
		part.Material = if mutation.id == "rainbow" then Enum.Material.Neon else Enum.Material.Foil
	end
	if egg.special then
		part.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Range = 14
		light.Brightness = 3
		light.Color = part.Color
		light.Parent = part
	end

	part:SetAttribute("EggUid", egg.uid)
	part:SetAttribute("PetId", egg.petId)
	part:SetAttribute("BiomeId", egg.biomeId)
	part:SetAttribute("Rarity", egg.rarity)
	part:SetAttribute("Size", egg.size)
	part:SetAttribute("Mutations", table.concat(egg.mutations, ","))
	part:SetAttribute("Special", egg.special)
	part:SetAttribute("EggState", "Nest")
	CollectionService:AddTag(part, Tags.Egg)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "훔치기"
	prompt.ObjectText = eggTitle(egg)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	Gui.billboard(part, eggTitle(egg), d * 0.9 + 1.5, 70)
	part.Parent = MapBuilder.getFolder("Eggs")
	return part, prompt
end

local function setState(egg: Egg, state: EggState)
	egg.state = state
	egg.part:SetAttribute("EggState", state)
end

-- 둥지 파트 윗면 높이 (회전된 원기둥도 처리)
local function nestTop(nestPart: BasePart): number
	local worldSize = nestPart.CFrame:VectorToWorldSpace(nestPart.Size)
	return nestPart.Position.Y + math.abs(worldSize.Y) / 2
end

local function placeOnNest(egg: Egg, slot: NestSlot)
	local weld = egg.part:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	local p = slot.part.Position
	egg.part.Anchored = true
	egg.part.CFrame = CFrame.new(p.X, nestTop(slot.part) + egg.part.Size.Y / 2, p.Z)
	egg.prompt.ActionText = "훔치기"
	egg.prompt.Enabled = true
	egg.carrier = nil
	egg.nestBiome = slot.biomeId
	egg.nestIndex = slot.index
	slot.eggUid = egg.uid
	slot.respawnAt = nil
	setState(egg, "Nest")
end

------------------------------------------------------------------
-- 생성 / 삭제
------------------------------------------------------------------

local function connectPrompt(prompt: ProximityPrompt, uid: string)
	prompt.Triggered:Connect(function(player: Player)
		EggService.tryPickup(player, uid)
	end)
end

local function spawnEgg(slot: NestSlot, pet: Pets.Pet, traits: EggRoll.EggTraits, special: boolean): Egg
	eggCounter += 1
	local seed: EggSeed = {
		uid = "e" .. tostring(eggCounter),
		petId = pet.id,
		biomeId = pet.biome,
		rarity = pet.rarity,
		size = traits.size,
		mutations = traits.mutations,
		special = special,
	}
	local part, prompt = makeEggPart(seed)
	local egg: Egg = {
		uid = seed.uid,
		petId = seed.petId,
		biomeId = seed.biomeId,
		rarity = seed.rarity,
		size = seed.size,
		mutations = seed.mutations,
		special = seed.special,
		part = part,
		prompt = prompt,
		state = "Nest",
		nestBiome = slot.biomeId,
		nestIndex = slot.index,
		carrier = nil,
		pickedAt = 0,
		droppedAt = 0,
	}
	eggs[egg.uid] = egg
	placeOnNest(egg, slot)
	connectPrompt(prompt, egg.uid)
	return egg
end

-- 알 파트가 엔진에 의해 지워졌으면(예: 들고 있던 사람이 맵 아래로 떨어짐) 다시 만듦
local function ensurePart(egg: Egg)
	if egg.part.Parent ~= nil then
		return
	end
	local part, prompt = makeEggPart(egg)
	egg.part = part
	egg.prompt = prompt
	connectPrompt(prompt, egg.uid)
end

local function destroyEgg(egg: Egg)
	if egg.nestBiome and egg.nestIndex then
		local slots = nests[egg.nestBiome]
		local slot = if slots then slots[egg.nestIndex] else nil
		if slot and slot.eggUid == egg.uid then
			slot.eggUid = nil
		end
	end
	eggs[egg.uid] = nil
	egg.part:Destroy()
end

local function spawnNormal(slot: NestSlot, side: string?)
	local pet = EggRoll.rollNestPet(slot.biomeId, side, rand)
	if pet then
		spawnEgg(slot, pet, EggRoll.rollTraits(rand), false)
	end
end

-- 둥지 예약 풀기 (이후 NEST_RESPAWN_SECONDS 뒤 새 알)
local function releaseNest(egg: Egg)
	local biomeId, index = egg.nestBiome, egg.nestIndex
	egg.nestBiome = nil
	egg.nestIndex = nil
	if not biomeId or not index then
		return
	end
	local slots = nests[biomeId]
	local slot = if slots then slots[index] else nil
	if slot and slot.eggUid == egg.uid then
		slot.eggUid = nil
		if Config.NEST_RESPAWN_SECONDS > 0 then
			slot.respawnAt = os.clock() + Config.NEST_RESPAWN_SECONDS
		end
	end
end

------------------------------------------------------------------
-- 초기화 (대기 단계)
------------------------------------------------------------------

function EggService.resetAll(cycleNumber: number)
	for _, egg in table.clone(eggs) do
		if egg.state == "Carried" then
			egg.nestBiome = nil
			egg.nestIndex = nil
		else
			eggs[egg.uid] = nil
			egg.part:Destroy()
		end
	end
	for _, slots in nests do
		for _, slot in slots do
			slot.eggUid = nil
			slot.respawnAt = nil
		end
	end

	Net.fireAll(Remotes.ToClient.Announce, { kind = "reset", text = "ALL EGG RESET!" })

	for _, biome in Biomes.list do
		local slots = nests[biome.id]
		if slots and #slots > 0 then
			local side = Biomes.sideForCycle(biome, cycleNumber)
			for _, slot in slots do
				spawnNormal(slot, side)
			end
			local specials = EggRoll.rollSpecials(biome.id, side, rand)
			if #specials > 0 then
				local picks = EggRoll.pickDistinct(#slots, #specials, rand)
				for i, pet in specials do
					local slot = slots[picks[i]]
					if slot then
						local old = if slot.eggUid then eggs[slot.eggUid] else nil
						if old then
							destroyEgg(old)
						end
						local egg = spawnEgg(slot, pet, EggRoll.rollTraits(rand), true)
						local rarity = Rarities.get(pet.rarity)
						Net.fireAll(Remotes.ToClient.Announce, {
							kind = "rareEgg",
							text = string.format(
								"%s 구역에 %s %s 알 등장!",
								biome.name,
								if rarity then rarity.name else pet.rarity,
								pet.name
							),
							biomeId = biome.id,
							petId = pet.id,
							rarity = pet.rarity,
							eggUid = egg.uid,
						})
					end
				end
			end
		end
	end
end

------------------------------------------------------------------
-- 줍기 / 들기
------------------------------------------------------------------

local function attachToHead(egg: Egg, player: Player): boolean
	local head = Character.getHead(player)
	if not head then
		return false
	end
	local offset = head.Size.Y / 2 + egg.part.Size.Y / 2 + 0.3
	egg.part.CFrame = head.CFrame * CFrame.new(0, offset, 0)
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = head
	weld.Part1 = egg.part
	weld.C0 = CFrame.new(0, offset, 0)
	weld.Parent = egg.part
	egg.part.Anchored = false -- 용접 후 고정 해제 (고정한 채로 용접하면 캐릭터가 굳음)
	return true
end

local function clearCarry(player: Player)
	local session = Sessions.get(player)
	if session then
		session.carryingUid = nil
		session.carryPenalty = 0
	end
	player:SetAttribute(Attr.CarryingEgg, "")
	player:SetAttribute(Attr.CarryingBiome, "")
	SpeedService.refresh(player)
end

function EggService.tryPickup(player: Player, uid: string)
	local egg = eggs[uid]
	if not egg or egg.state == "Carried" then
		return
	end
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	if not Cycle.canStealEggs(CycleService.getPhase()) then
		Net.notify(player, "error", "밤에는 알을 훔칠 수 없어요!")
		return
	end
	if session.carryingUid then
		Net.notify(player, "error", "이미 알을 들고 있어요!")
		return
	end
	local now = os.clock()
	if Sessions.isStunned(session, now) then
		return
	end
	local _, humanoid, root = Character.get(player)
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if (root.Position - egg.part.Position).Magnitude > Config.PICKUP_DISTANCE + egg.part.Size.X / 2 then
		return -- 너무 멀리서 요청 (익스플로잇 또는 지연)
	end
	if not attachToHead(egg, player) then
		return
	end

	egg.prompt.Enabled = false
	egg.carrier = player
	egg.pickedAt = now
	setState(egg, "Carried")
	-- 둥지 예약은 유지 (구역을 벗어날 때 풀림). 바닥 알은 예약 없음.

	local size = Sizes.get(egg.size)
	session.carryingUid = egg.uid
	session.carryPenalty = if size then size.speedPenalty else 0
	player:SetAttribute(Attr.CarryingEgg, egg.uid)
	player:SetAttribute(Attr.CarryingBiome, egg.biomeId)
	SpeedService.refresh(player)
	data.stats.eggsStolen = (data.stats.eggsStolen or 0) + 1

	local biome = Biomes.get(egg.biomeId)
	Net.fire(player, Remotes.ToClient.RunAlert, {
		egg = EggService.info(egg),
		guardName = if biome then Biomes.guardDisplayName(biome, CycleService.sideFor(egg.biomeId)) else "",
		guardSpeed = if biome then biome.guardSpeed else 0,
		yourSpeed = session.carrySpeed,
	})
end

function EggService.getCarried(player: Player): Egg?
	local session = Sessions.get(player)
	local uid = if session then session.carryingUid else nil
	return if uid then eggs[uid] else nil
end

-- 지금 알을 들고 있는 사람 목록 (복사본)
function EggService.carriers(): { [Player]: Egg }
	local result: { [Player]: Egg } = {}
	for _, egg in eggs do
		local carrier = egg.carrier
		if egg.state == "Carried" and carrier then
			result[carrier] = egg
		end
	end
	return result
end

------------------------------------------------------------------
-- 놓치기
------------------------------------------------------------------

local function returnToNest(egg: Egg): boolean
	if egg.nestBiome and egg.nestIndex then
		local slots = nests[egg.nestBiome]
		local slot = if slots then slots[egg.nestIndex] else nil
		if slot and slot.eggUid == egg.uid then
			placeOnNest(egg, slot)
			return true
		end
	end
	-- 예약이 풀린 알이면 같은 구역의 빈 둥지로
	for _, slot in nests[egg.biomeId] or {} do
		if slot.eggUid == nil then
			placeOnNest(egg, slot)
			return true
		end
	end
	return false
end

local function placeDropped(egg: Egg, position: Vector3, ignore: { Instance })
	releaseNest(egg)
	local weld = egg.part:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	local y = MapBuilder.groundY(position, ignore)
	egg.part.Anchored = true
	egg.part.CFrame = CFrame.new(position.X, y + egg.part.Size.Y / 2, position.Z)
	egg.part.AssemblyLinearVelocity = Vector3.zero
	egg.prompt.ActionText = "줍기"
	egg.prompt.Enabled = true
	egg.carrier = nil
	egg.droppedAt = os.clock()
	setState(egg, "Dropped")
end

-- 들고 있던 알을 놓침. cause 에 따라 둥지로 돌아가거나 그 자리에 떨어짐.
function EggService.dropCarried(player: Player, cause: CatchCause): EggOutcome?
	local egg = EggService.getCarried(player)
	if not egg then
		return nil
	end
	local character = player.Character
	local root = Character.getRoot(player)
	local position = if root then root.Position else egg.part.Position
	clearCarry(player)
	ensurePart(egg)

	local outcome = EggRules.dropOutcome(cause, MapBuilder.getZone(egg.biomeId), position.X, position.Z)
	if outcome == "ReturnToNest" and returnToNest(egg) then
		return "ReturnToNest"
	end
	placeDropped(egg, position, if character then { character } else {})
	return "DropHere"
end

-- 잡힘/맞음: 알 놓치기 + 래그돌 + Caught 알림
function EggService.knockOut(player: Player, fromPosition: Vector3?, cause: CatchCause, byName: string)
	local outcome = EggService.dropCarried(player, cause)
	local velocity = Ragdoll.apply(player, fromPosition)
	Net.fire(player, Remotes.ToClient.Caught, {
		cause = cause,
		by = byName,
		eggOutcome = outcome or "None",
		ragdollSeconds = Config.RAGDOLL_SECONDS,
		knockback = velocity,
	})
end

-- 배달: 들고 있던 알을 세상에서 지우고 데이터만 돌려줌
function EggService.takeCarried(player: Player): DeliveredEgg?
	local egg = EggService.getCarried(player)
	if not egg then
		return nil
	end
	clearCarry(player)
	releaseNest(egg)
	local delivered: DeliveredEgg = {
		petId = egg.petId,
		biomeId = egg.biomeId,
		size = egg.size,
		mutations = table.clone(egg.mutations),
		special = egg.special,
	}
	destroyEgg(egg)
	return delivered
end

------------------------------------------------------------------
-- 주기 처리 (0.2초마다)
------------------------------------------------------------------

local function tick()
	local now = os.clock()

	for _, egg in table.clone(eggs) do
		if egg.state == "Carried" then
			local carrier = egg.carrier
			local session = if carrier then Sessions.get(carrier) else nil
			if carrier == nil or session == nil or session.carryingUid ~= egg.uid then
				-- 이상 상태 정리 (들고 있던 사람이 이미 나갔는데 이벤트를 놓친 경우)
				ensurePart(egg)
				if not returnToNest(egg) then
					destroyEgg(egg)
				end
			elseif egg.part.Parent == nil or not Character.isAlive(carrier) then
				EggService.dropCarried(carrier, "death")
			elseif egg.nestBiome then
				local root = Character.getRoot(carrier)
				local zone = MapBuilder.getZone(egg.biomeId)
				if root and zone and not EggRules.isInsideZone(zone, root.Position.X, root.Position.Z) then
					releaseNest(egg)
				end
			end
		elseif egg.state == "Dropped" then
			if now - egg.droppedAt > Config.DROPPED_EGG_LIFETIME then
				destroyEgg(egg)
			end
		end
	end

	if CycleService.getPhase() == "Day" and Config.NEST_RESPAWN_SECONDS > 0 then
		for biomeId, slots in nests do
			for _, slot in slots do
				local respawnAt = slot.respawnAt
				if slot.eggUid == nil and respawnAt and now >= respawnAt then
					spawnNormal(slot, CycleService.sideFor(biomeId))
				end
			end
		end
	end
end

------------------------------------------------------------------
-- 시작 / 플레이어 이벤트
------------------------------------------------------------------

function EggService.onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			EggService.dropCarried(player, "death")
		end)
	end
end

function EggService.onPlayerLeaving(player: Player)
	EggService.dropCarried(player, "leave")
end

function EggService.start()
	for _, biome in Biomes.list do
		local slots: { NestSlot } = {}
		for i, part in MapBuilder.getNests(biome.id) do
			table.insert(slots, { biomeId = biome.id, index = i, part = part, eggUid = nil, respawnAt = nil })
		end
		nests[biome.id] = slots
	end

	CycleService.changed:connect(function(phase: Types.Phase, cycleNumber: number)
		if phase == "Intermission" then
			EggService.resetAll(cycleNumber)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			local ok, err = pcall(tick)
			if not ok then
				warn("[EggService] tick 오류: " .. tostring(err))
			end
		end
	end)
end

return EggService
