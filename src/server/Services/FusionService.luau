--!strict
--[[
	FusionService — 퓨전 머신 (설계문서 9-4). 규칙은 shared/FusionRules.luau (Lune 테스트)

	Remote: FuseRequest(petUid1, petUid2, petUid3)
	  - 내 베이스 FusionMachine 태그 파트(Attr PlotIndex = 내 베이스) 표면에서 FUSION_RADIUS 안이어야 함
	    (맵에 퓨전 머신 파트가 없으면 내 베이스 안이면 됨)
	  - 같은 petId 3마리만. 장착 중이면 자동 해제 후 소모. 즉시, 비용 없음, 되돌릴 수 없음.
	  - 결과 펫은 보관함에 들어감(빈 칸이면 자동 장착) + 도감 발견 처리
	  - 성공하면 FusionResult 이벤트 + FusionService.fused:fire(player, pet) (5판: 퀘스트가 없어져 지금은 듣는 곳 없음)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local FusionRules = require(Shared.FusionRules)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local MapLayout = require(Shared.Data.MapLayout)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Character = require(Server.Util.Character)
local Landmarks = require(Server.Util.Landmarks)
local Signal = require(Server.Util.Signal)
local Validate = require(Server.Logic.Validate)
local DataSchema = require(Server.Logic.DataSchema)
local PetService = require(script.Parent.PetService)
local IndexService = require(script.Parent.IndexService)

type PetRecord = Types.PetRecord

local FusionService = {}

-- 합성 성공 (player, 결과 PetRecord). 5판: 퀘스트 "합성 1회" 가 없어져 듣는 곳은 없지만 신호는 남김 (나중 업적 등)
FusionService.fused = Signal.new()

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

-- 내 베이스 퓨전 머신 근처인가
function FusionService.isNearMachine(player: Player): boolean
	local session = Sessions.get(player)
	if not session or session.plotIndex <= 0 then
		return false
	end
	local machine = Landmarks.plotPart(Tags.FusionMachine, session.plotIndex)
	if machine then
		return Landmarks.isPlayerNear(player, machine, Config.FUSION_RADIUS)
	end
	local root = Character.getRoot(player)
	return root ~= nil and Character.isAlive(player) and MapLayout.isInPlot(root.Position, session.plotIndex)
end

function FusionService.fuse(player: Player, uids: { string })
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return
	end
	if not FusionService.isNearMachine(player) then
		Net.notify(player, "error", "내 베이스의 퓨전 머신 가까이에서 합칠 수 있어요!")
		return
	end
	local inputs: { PetRecord } = {}
	for _, uid in uids do
		local record = PetService.findPet(player, uid)
		if not record then
			Net.notify(player, "error", FusionRules.errorText("unknown"))
			return
		end
		table.insert(inputs, record)
	end
	local result, err = FusionRules.fuse(inputs, rand)
	if not result then
		Net.notify(player, "error", FusionRules.errorText(err or "count"))
		return
	end
	local consumed = PetService.removePets(player, uids)
	if not consumed then
		return
	end
	local pet: PetRecord = {
		uid = DataSchema.newUid(data, "p"),
		petId = result.petId,
		size = result.size,
		mutations = result.mutations,
	}
	local isNew = IndexService.discover(player, pet.petId)
	PetService.addPet(player, pet)
	data.stats.fusions = (data.stats.fusions or 0) + 1

	local def = Pets.get(pet.petId)
	Net.fire(player, Remotes.ToClient.FusionResult, {
		consumed = uids,
		pet = pet,
		upgraded = result.upgraded,
		bonusMutation = result.bonusMutation,
		inputIncome = result.inputIncome,
		income = result.resultIncome,
		isNew = isNew,
		equipped = table.find(data.equipped, pet.uid) ~= nil,
	})
	Net.notify(
		player,
		"success",
		"합성 성공! " .. (if def then def.name else pet.petId) .. " 이(가) 나왔어요!"
	)
	FusionService.fused:fire(player, pet)
end

function FusionService.start()
	Net.on(Remotes.ToServer.FuseRequest, function(player: Player, a: unknown, b: unknown, c: unknown)
		local u1, u2, u3 = Validate.uid(a), Validate.uid(b), Validate.uid(c)
		if not u1 or not u2 or not u3 then
			return
		end
		if u1 == u2 or u2 == u3 or u1 == u3 then
			Net.notify(player, "error", FusionRules.errorText("duplicate"))
			return
		end
		FusionService.fuse(player, { u1, u2, u3 })
	end)
end

return FusionService
