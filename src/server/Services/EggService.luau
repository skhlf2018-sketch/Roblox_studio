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
	초기화가 끝나면 EggService.resetDone:fire(cycleNumber) → 사쿠라 크리스탈·퀘스트 비밀 알이 이어서 놓임.

	2단계:
	  - spawnSpecialEgg: 다른 서비스가 특별 알을 둥지에 놓음 (예: 영혼 세계 수호자, questOnly = 퀘스트 끝낸 사람만 줍기)
	  - 순간이동 방지: 주운 위치·시각(pickedPosition/pickedAt)을 기억 → BaseService 가 배달 때 확인.
	    서버가 순간이동시키면 resetCarryOrigin 으로 기준점을 옮김.
	  - confiscate: 치트 의심 배달은 알을 원래 둥지로 돌려보냄 (그 자리에 떨어뜨리면 다시 주워 배달 가능하므로)
	  - 알 모양: Ball 파트 + SpecialMesh(Sphere, Y 1.25배) "EggShape" (선임 EggVisualService 가 모양을 바꾸면 지워도 됨)

	2판:
	  - 둥지 자리 = 맵의 Nest 태그 파트(MapBuilder.getNests) 윗면, 없으면 MapLayout.nestsFor 자리 바닥.
	  - "구역 안" = MapLayout.zoneAt(z) == 알의 구역 (일자 복도라 z 범위만 봄).
	  - DropEgg(): 스스로 알을 버림 → 항상 그 자리에 떨어짐 (경비 추격 끝). 다시 주우면 경비가 또 쫓음.
	  - 경비 잡힘 유예(GUARD_CATCH_GRACE_SECONDS)는 둥지에서 주울 때만 (바닥 알 다시 줍기는 유예 없음 → 버렸다 줍기 반복으로 못 버팀)
	  - 플레이어 Attr CarryWeightKg = 든 알 무게 (Sizes.carryKg, 표시용), 알 파트 Attr WeightKg 도 같음.
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
local MapLayout = require(Shared.Data.MapLayout)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Character = require(Server.Util.Character)
local Gui = require(Server.Util.Gui)
local Ragdoll = require(Server.Util.Ragdoll)
local Signal = require(Server.Util.Signal)
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
	questOnly: boolean, -- 퀘스트 3개를 끝낸 사람만 주울 수 있음
	part: BasePart,
	prompt: ProximityPrompt,
	state: EggState,
	nestBiome: string?,
	nestIndex: number?,
	carrier: Player?,
	pickedAt: number,
	graceUntil: number, -- 이 시각(os.clock)까지 경비가 못 잡음 (둥지에서 주울 때만 GUARD_CATCH_GRACE_SECONDS)
	pickedPosition: Vector3?, -- 마지막으로 주운(또는 서버가 순간이동시킨) 위치
	originAt: number, -- pickedPosition 을 기록한 시각 (os.clock)
	droppedAt: number,
}

export type SpecialEggOptions = {
	questOnly: boolean?,
	announce: boolean?,
}

type NestSlot = {
	biomeId: string,
	index: number,
	position: Vector3, -- 알 바닥이 닿는 점 (둥지 윗면 가운데)
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

-- 초기화(대기 단계) 알 배치가 끝난 뒤 (cycleNumber)
EggService.resetDone = Signal.new()

local EGG_HEIGHT_SCALE = 1.25 -- 알은 옆보다 위아래로 1.25배 김 (SpecialMesh Scale)

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

-- 들고 있을 때 보이는 무게(kg, 표시용)
local function carryKg(sizeId: string): number
	local size = Sizes.get(sizeId)
	return if size then size.carryKg else 0
end

-- 알 파트의 보이는 높이 (Ball 파트 지름 × 1.25)
local function eggHeight(part: BasePart): number
	return part.Size.Y * EGG_HEIGHT_SCALE
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
	questOnly: boolean,
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
	part.Size = Vector3.new(d, d, d) -- Ball 은 크기가 항상 같은 값 → 길쭉한 모양은 SpecialMesh 로
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "EggShape"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, EGG_HEIGHT_SCALE, 1)
	mesh.Parent = part
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
	part:SetAttribute("QuestOnly", egg.questOnly)
	part:SetAttribute("WeightKg", carryKg(egg.size))
	part:SetAttribute("EggState", "Nest")
	CollectionService:AddTag(part, Tags.Egg)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "훔치기"
	prompt.ObjectText = eggTitle(egg)
		.. (if egg.questOnly then "\n(마법의 숲 퀘스트를 끝낸 사람만)" else "")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	Gui.billboard(part, eggTitle(egg), d * EGG_HEIGHT_SCALE * 0.7 + 1.5, 70)
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
	local p = slot.position
	egg.part.Anchored = true
	egg.part.CFrame = CFrame.new(p.X, p.Y + eggHeight(egg.part) / 2, p.Z)
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

local function spawnEgg(
	slot: NestSlot,
	pet: Pets.Pet,
	traits: EggRoll.EggTraits,
	special: boolean,
	questOnly: boolean?
): Egg
	eggCounter += 1
	local seed: EggSeed = {
		uid = "e" .. tostring(eggCounter),
		petId = pet.id,
		biomeId = pet.biome,
		rarity = pet.rarity,
		size = traits.size,
		mutations = traits.mutations,
		special = special,
		questOnly = questOnly == true,
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
		questOnly = seed.questOnly,
		part = part,
		prompt = prompt,
		state = "Nest",
		nestBiome = slot.biomeId,
		nestIndex = slot.index,
		carrier = nil,
		pickedAt = 0,
		graceUntil = 0,
		pickedPosition = nil,
		originAt = 0,
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
	EggService.resetDone:fire(cycleNumber)
end

-- 특별 알 하나를 그 구역의 무작위 둥지에 놓음 (원래 있던 알은 지움). 놓은 알 uid (둥지가 없으면 nil)
function EggService.spawnSpecialEgg(biomeId: string, petId: string, options: SpecialEggOptions?): string?
	local pet = Pets.get(petId)
	local slots = nests[biomeId]
	if not pet or not slots or #slots == 0 then
		return nil
	end
	-- 누가 들고 있는 알의 예약 둥지는 피함
	local free: { NestSlot } = {}
	for _, slot in slots do
		local current = if slot.eggUid then eggs[slot.eggUid] else nil
		if not current or current.state ~= "Carried" then
			table.insert(free, slot)
		end
	end
	if #free == 0 then
		return nil
	end
	local slot = free[math.clamp(math.floor(rand() * #free) + 1, 1, #free)]
	local old = if slot.eggUid then eggs[slot.eggUid] else nil
	if old then
		destroyEgg(old)
	end
	local questOnly = options ~= nil and options.questOnly == true
	local egg = spawnEgg(slot, pet, EggRoll.rollTraits(rand), true, questOnly)
	if options and options.announce then
		local biome = Biomes.get(biomeId)
		local rarity = Rarities.get(pet.rarity)
		Net.fireAll(Remotes.ToClient.Announce, {
			kind = "rareEgg",
			text = string.format(
				"%s 구역에 %s %s 알 등장!%s",
				if biome then biome.name else biomeId,
				if rarity then rarity.name else pet.rarity,
				pet.name,
				if questOnly then " (퀘스트를 끝낸 사람만 주울 수 있어요)" else ""
			),
			biomeId = biomeId,
			petId = pet.id,
			rarity = pet.rarity,
			eggUid = egg.uid,
			questOnly = questOnly,
		})
	end
	return egg.uid
end

------------------------------------------------------------------
-- 줍기 / 들기
------------------------------------------------------------------

local function attachToHead(egg: Egg, player: Player): boolean
	local head = Character.getHead(player)
	if not head then
		return false
	end
	local offset = head.Size.Y / 2 + eggHeight(egg.part) / 2 + 0.3
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
	player:SetAttribute(Attr.CarryWeightKg, 0)
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
	if egg.questOnly and not data.questsRewarded then
		if Sessions.useCooldown(session, "questOnlyNotice", 3, os.clock()) then
			Net.notify(
				player,
				"error",
				"마법의 숲 퀘스트를 모두 끝낸 사람만 주울 수 있는 알이에요!"
			)
		end
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

	local fromNest = egg.state == "Nest"
	egg.prompt.Enabled = false
	egg.carrier = player
	egg.pickedAt = now
	-- 경비 유예는 둥지에서 주울 때만 (바닥 알을 버렸다 다시 줍기로 유예를 계속 받지 못하게)
	egg.graceUntil = if fromNest then now + Config.GUARD_CATCH_GRACE_SECONDS else now
	egg.pickedPosition = root.Position
	egg.originAt = now
	setState(egg, "Carried")
	-- 둥지 예약은 유지 (구역을 벗어날 때 풀림). 바닥 알은 예약 없음.

	local size = Sizes.get(egg.size)
	session.carryingUid = egg.uid
	session.carryPenalty = if size then size.speedPenalty else 0
	player:SetAttribute(Attr.CarryingEgg, egg.uid)
	player:SetAttribute(Attr.CarryingBiome, egg.biomeId)
	player:SetAttribute(Attr.CarryWeightKg, carryKg(egg.size))
	SpeedService.refresh(player)
	data.stats.eggsStolen = (data.stats.eggsStolen or 0) + 1

	local biome = Biomes.get(egg.biomeId)
	Net.fire(player, Remotes.ToClient.RunAlert, {
		egg = EggService.info(egg),
		guardName = if biome then Biomes.guardDisplayName(biome, CycleService.sideFor(egg.biomeId)) else "",
		guardSpeed = if biome then biome.guardSpeed else 0,
		yourSpeed = session.carrySpeed,
		weightKg = carryKg(egg.size),
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
	for _, slot in (nests[egg.biomeId] or {}) :: { NestSlot } do
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
	egg.part.CFrame = CFrame.new(position.X, y + eggHeight(egg.part) / 2, position.Z)
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

	local outcome = EggRules.dropOutcome(cause, egg.biomeId, MapLayout.zoneAt(position.Z))
	if outcome == "ReturnToNest" and returnToNest(egg) then
		return "ReturnToNest"
	end
	placeDropped(egg, position, if character then { character } else {})
	return "DropHere"
end

-- 알을 지정한 위치에 떨어뜨림 (치트 의심: 순간이동하기 전 마지막 정상 위치에)
function EggService.dropCarriedAt(player: Player, position: Vector3): EggOutcome?
	local egg = EggService.getCarried(player)
	if not egg then
		return nil
	end
	local character = player.Character
	clearCarry(player)
	ensurePart(egg)
	placeDropped(egg, position, if character then { character } else {})
	return "DropHere"
end

-- 치트 의심 배달: 알을 원래 둥지(없으면 같은 구역 빈 둥지)로 돌려보냄, 둥지가 없으면 없앰
function EggService.confiscate(player: Player)
	local egg = EggService.getCarried(player)
	if not egg then
		return
	end
	clearCarry(player)
	ensurePart(egg)
	if not returnToNest(egg) then
		destroyEgg(egg)
	end
end

-- 서버가 알 든 사람을 순간이동시켰을 때: 배달 거리 검사 기준점을 새 위치로
function EggService.resetCarryOrigin(player: Player, position: Vector3)
	local egg = EggService.getCarried(player)
	if egg then
		egg.pickedPosition = position
		egg.originAt = os.clock()
	end
end

-- 잡힘/맞음: 알 놓치기 + 래그돌 + Caught 알림. power = 무기 넉백 배율 (기본 1)
function EggService.knockOut(player: Player, fromPosition: Vector3?, cause: CatchCause, byName: string, power: number?)
	local outcome = EggService.dropCarried(player, cause)
	local velocity = Ragdoll.apply(player, fromPosition, nil, power)
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

local function tick(): ...any
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
				if root and MapLayout.zoneAt(root.Position.Z) ~= egg.biomeId then
					releaseNest(egg) -- 알의 구역(z 범위)을 벗어남 → 둥지 예약 풀림
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

-- 2판 DropEgg: 들고 있는 알을 스스로 그 자리에 떨어뜨림 (항상 그 자리, 경비 추격은 다음 틱에 끝남)
function EggService.dropEgg(player: Player): boolean
	local egg = EggService.getCarried(player)
	if not egg then
		return false
	end
	EggService.dropCarried(player, "drop")
	Net.notify(player, "info", "알을 내려놓았어요.")
	return true
end

-- 이 구역 둥지 자리 (알 바닥이 닿는 점) — 사쿠라 크리스탈 등
function EggService.nestPositions(biomeId: string): { Vector3 }
	local result: { Vector3 } = {}
	local slots: { NestSlot } = nests[biomeId] or {}
	for _, slot in slots do
		table.insert(result, slot.position)
	end
	return result
end

-- 둥지 자리 만들기: 맵에 Nest 파트가 있으면 그 윗면, 없으면 MapLayout.nestsFor 자리 바닥
local function buildNestSlots(biomeId: string): { NestSlot }
	local slots: { NestSlot } = {}
	local parts = MapBuilder.getNests(biomeId)
	if #parts > 0 then
		for i, part in parts do
			local p = part.Position
			local position = Vector3.new(p.X, nestTop(part), p.Z)
			table.insert(slots, { biomeId = biomeId, index = i, position = position, eggUid = nil, respawnAt = nil })
		end
		return slots
	end
	for i, spot in MapLayout.nestsFor(biomeId) do
		local y = MapBuilder.groundY(Vector3.new(spot.x, MapLayout.FLOOR_Y + 1, spot.z), {})
		local position = Vector3.new(spot.x, y, spot.z)
		table.insert(slots, { biomeId = biomeId, index = i, position = position, eggUid = nil, respawnAt = nil })
	end
	return slots
end

function EggService.start()
	for _, biome in Biomes.list do
		nests[biome.id] = buildNestSlots(biome.id)
	end

	Net.on(Remotes.ToServer.DropEgg, function(player: Player)
		EggService.dropEgg(player)
	end)

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
