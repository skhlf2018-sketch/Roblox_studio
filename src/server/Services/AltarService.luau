--!strict
--[[
	AltarService — 천사&악마 구역 제단 2개 + 비밀 통로 합성 (설계문서 4장). 규칙은 shared/AltarRules.luau

	제단 (Tag "Altar", Attribute Side = "light"(천국) / "dark"(지옥)):
	  Remote AltarOffer(petUid): 가까운 제단(ALTAR_RADIUS)에 그 쪽 펫을 제물로 걸어 둠.
	  같은 낮/밤 주기에 반대쪽 제단에 다른 사람이 제물을 걸면 → 두 사람 펫이 사라지고
	  각자 링 가드(80%) / 링로드(20%) 알을 받음 (베이스 부화 슬롯에 바로, 가득 차면 대기 줄).
	  기다리는 동안 펫은 보관함에 그대로 있음. 주기가 바뀌면 제물 취소 (펫은 남음).
	  제단 파트 Attribute PendingCount = 기다리는 제물 수 (연출용)

	비밀 통로 합성 (Tag "Shrine"):
	  Remote ShrineFuse(petUidA, petUidB): 페가수스 + 스켈레톤 말 → 에퀴녹스 알,
	  대천사 + 세계를 불태우는 자 → 에테론 알. 계정당 레시피마다 1번 (저장: shrineUsed).
	  알 크기 = 두 펫 중 작은 크기, 돌연변이 = 두 펫이 똑같으면 유지 [추정]

	제단·비밀 통로 파트가 맵에 없으면 천사&악마 구역 안에 임시 파트를 만듦 (Util/Landmarks).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local AltarRules = require(Shared.AltarRules)
local FusionRules = require(Shared.FusionRules)
local EggRoll = require(Shared.EggRoll)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local MapLayout = require(Shared.Data.MapLayout)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Landmarks = require(Server.Util.Landmarks)
local Validate = require(Server.Logic.Validate)
local CycleService = require(script.Parent.CycleService)
local BaseService = require(script.Parent.BaseService)
local PetService = require(script.Parent.PetService)

type Offer = AltarRules.Offer

local SIDE_NAMES: { [string]: string } = { light = "천국", dark = "지옥" }

local AltarService = {}

local state = AltarRules.new(1)
local altars: { BasePart } = {}
local shrines: { BasePart } = {}
local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local function sideOfAltar(part: BasePart): string?
	local side = part:GetAttribute("Side")
	if side == nil and part.Parent and part.Parent:IsA("Model") then
		side = part.Parent:GetAttribute("Side")
	end
	return if typeof(side) == "string" and SIDE_NAMES[side] then side else nil
end

local function refreshAltarAttributes()
	for _, part in altars do
		local side = sideOfAltar(part)
		if side then
			part:SetAttribute("PendingCount", AltarRules.pendingCount(state, side))
		end
	end
end

local function playerOf(userId: number): Player?
	local player = Players:GetPlayerByUserId(userId)
	if player and Sessions.getLoaded(player) then
		return player
	end
	return nil
end

-- 기다리는 제물이 아직 유효한가 (사람이 있고, 펫이 그대로 있고, 알 받을 자리가 있음)
local function isValid(offer: Offer): boolean
	local player = playerOf(offer.userId)
	if not player then
		return false
	end
	local pet = PetService.findPet(player, offer.petUid)
	return pet ~= nil and pet.petId == offer.petId and BaseService.canReceiveEgg(player)
end

local function reward(offer: Offer, partner: Offer)
	local player = playerOf(offer.userId)
	if not player or not PetService.removePets(player, { offer.petUid }) then
		return
	end
	local ringId = AltarRules.rollRingEgg(rand)
	local traits = EggRoll.rollTraits(rand)
	BaseService.grantEgg(player, ringId, traits.size, traits.mutations, "altar")
	local partnerPlayer = playerOf(partner.userId)
	local ring = Pets.get(ringId)
	Net.fire(player, Remotes.ToClient.AltarUpdate, {
		status = "paired",
		side = offer.side,
		petId = offer.petId,
		partner = if partnerPlayer then partnerPlayer.DisplayName else "",
		eggPetId = ringId,
	})
	Net.notify(player, "success", "제단의 힘! " .. (if ring then ring.name else ringId) .. " 알을 받았어요!")
end

function AltarService.offer(player: Player, petUid: string)
	local session = Sessions.getLoaded(player)
	if not session then
		return
	end
	local altar = Landmarks.nearest(player, altars, Config.ALTAR_RADIUS)
	local side = if altar then sideOfAltar(altar) else nil
	if not side then
		Net.notify(player, "error", "천사&악마 구역의 제단 가까이에서 바칠 수 있어요!")
		return
	end
	local pet = PetService.findPet(player, petUid)
	if not pet then
		return
	end
	if AltarRules.sideOfPet(pet.petId) ~= side then
		Net.notify(
			player,
			"error",
			(SIDE_NAMES[side] or side)
				.. " 제단에는 "
				.. (SIDE_NAMES[side] or side)
				.. " 쪽 펫만 바칠 수 있어요!"
		)
		return
	end
	if not BaseService.canReceiveEgg(player) then
		Net.notify(player, "error", "알을 받을 자리가 없어요! 부화 슬롯을 비워 주세요.")
		return
	end
	local offer: Offer = { userId = player.UserId, petUid = pet.uid, petId = pet.petId, side = side }
	local ok, reason = AltarRules.add(state, offer, CycleService.getCycleNumber())
	if not ok then
		Net.notify(
			player,
			"error",
			if reason == "already"
				then "이번 주기에는 이미 제물을 바쳤어요. 반대쪽 제단에 다른 친구가 바치길 기다려요!"
				else "이 펫은 바칠 수 없어요."
		)
		return
	end
	Net.fire(player, Remotes.ToClient.AltarUpdate, { status = "pending", side = side, petId = pet.petId })
	local a, b = AltarRules.tryPair(state, isValid)
	if a and b then
		reward(a, b)
		reward(b, a)
	else
		local other = if side == "light" then "dark" else "light"
		Net.notify(
			player,
			"info",
			"제물을 올렸어요! 이번 주기 안에 다른 사람이 "
				.. (SIDE_NAMES[other] or other)
				.. " 제단에 바치면 둘 다 특별한 알을 받아요."
		)
	end
	refreshAltarAttributes()
end

function AltarService.shrineFuse(player: Player, uidA: string, uidB: string)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	if not Landmarks.nearest(player, shrines, Config.SHRINE_RADIUS) then
		Net.notify(player, "error", "비밀 통로의 합성 제단 가까이에서만 합성할 수 있어요!")
		return
	end
	local a, b = PetService.findPet(player, uidA), PetService.findPet(player, uidB)
	if not a or not b then
		return
	end
	local recipe = AltarRules.recipeFor(a.petId, b.petId)
	if not recipe then
		Net.notify(
			player,
			"error",
			"이 두 펫은 합성할 수 없어요. (페가수스+스켈레톤 말, 대천사+세계를 불태우는 자)"
		)
		return
	end
	local result = Pets.get(recipe.result)
	local resultName = if result then result.name else recipe.result
	if data.shrineUsed[recipe.result] then
		Net.notify(player, "error", resultName .. " 합성은 계정당 한 번만 할 수 있어요.")
		return
	end
	if not BaseService.canReceiveEgg(player) then
		Net.notify(player, "error", "알을 받을 자리가 없어요! 부화 슬롯을 비워 주세요.")
		return
	end
	local size = AltarRules.shrineSize(a.size, b.size)
	local mutations = FusionRules.commonMutations({ a, b })
	if not PetService.removePets(player, { uidA, uidB }) then
		return
	end
	data.shrineUsed[recipe.result] = true
	BaseService.grantEgg(player, recipe.result, size, mutations, "shrine")
	Snapshot.section(player, "special")
	Net.fire(player, Remotes.ToClient.ShrineResult, {
		consumed = { uidA, uidB },
		resultPetId = recipe.result,
		size = size,
		mutations = mutations,
	})
	Net.notify(player, "success", "비밀 합성 성공! " .. resultName .. " 알이 부화 슬롯에 들어갔어요!")
end

local function ensurePlaces()
	-- 자리 = MapLayout.specials (선임이 같은 태그·Side 로 진짜 모델을 두면 임시 파트는 안 생김)
	local S = MapLayout.specials
	local floorY = MapLayout.FLOOR_Y
	local light = Landmarks.ensure({
		tag = Tags.Altar,
		name = "AltarLight",
		label = "천국 제단\n(천국 쪽 펫 바치기)",
		position = Vector3.new(S.altarLight.x, floorY + 2, S.altarLight.z),
		size = Vector3.new(6, 4, 6),
		color = Color3.fromRGB(255, 245, 200),
		material = Enum.Material.Marble,
		attributes = { Side = "light", PendingCount = 0 },
	}, "Side", "light")
	local dark = Landmarks.ensure({
		tag = Tags.Altar,
		name = "AltarDark",
		label = "지옥 제단\n(지옥 쪽 펫 바치기)",
		position = Vector3.new(S.altarDark.x, floorY + 2, S.altarDark.z),
		size = Vector3.new(6, 4, 6),
		color = Color3.fromRGB(120, 20, 20),
		material = Enum.Material.Basalt,
		attributes = { Side = "dark", PendingCount = 0 },
	}, "Side", "dark")
	altars = {}
	for _, part in light do
		table.insert(altars, part)
	end
	for _, part in dark do
		table.insert(altars, part)
	end
	shrines = Landmarks.ensure({
		tag = Tags.Shrine,
		name = "SecretShrine",
		label = "비밀 통로 합성 제단",
		position = Vector3.new(S.shrine.x, floorY + 3, S.shrine.z),
		size = Vector3.new(6, 6, 6),
		color = Color3.fromRGB(150, 120, 220),
		material = Enum.Material.Glass,
		transparency = 0.2,
	})
end

function AltarService.onPlayerLeaving(player: Player)
	if AltarRules.cancel(state, player.UserId) then
		refreshAltarAttributes()
	end
end

function AltarService.start()
	ensurePlaces()
	state = AltarRules.new(CycleService.getCycleNumber())

	Net.on(Remotes.ToServer.AltarOffer, function(player: Player, uid: unknown)
		local petUid = Validate.uid(uid)
		if petUid then
			AltarService.offer(player, petUid)
		end
	end)
	Net.on(Remotes.ToServer.ShrineFuse, function(player: Player, a: unknown, b: unknown)
		local uidA, uidB = Validate.uid(a), Validate.uid(b)
		if uidA and uidB and uidA ~= uidB then
			AltarService.shrineFuse(player, uidA, uidB)
		end
	end)

	-- 주기가 바뀌면 기다리던 제물 취소 (펫은 그대로)
	CycleService.changed:connect(function(_phase: Types.Phase, cycleNumber: number)
		local expired = AltarRules.rollover(state, cycleNumber)
		for _, offer in expired do
			local player = playerOf(offer.userId)
			if player then
				Net.fire(
					player,
					Remotes.ToClient.AltarUpdate,
					{ status = "expired", side = offer.side, petId = offer.petId }
				)
				Net.notify(
					player,
					"info",
					"이번 주기가 끝나서 제단 제물이 취소됐어요. (펫은 그대로 있어요)"
				)
			end
		end
		if #expired > 0 then
			refreshAltarAttributes()
		end
	end)
end

return AltarService
