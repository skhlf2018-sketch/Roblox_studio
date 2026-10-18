--!strict
--[[
	QuestService — 마법의 숲 퀘스트 3개 (설계문서 4장). 목록은 shared/Data/Quests.luau, 규칙은 shared/QuestRules.luau

	진행도 (저장: data.quests):
	  - 알 배달 (BaseService.delivered): "마법의 숲 알 20개", "영원 알 1개"
	  - 퓨전 성공 (FusionService.fused): "합성 1회"
	  진행도가 바뀌면 QuestUpdate 이벤트 + DataUpdate("quests")
	전부 끝나면 (한 번만, data.questsRewarded):
	  - 퀘스트 문(Tag "QuestGate") 통과: 서버 CollisionGroup — 문 파트는 "QuestGate", 끝낸 사람 캐릭터는 "QuestPassed"
	    (둘은 서로 안 부딪힘, 다른 사람에게는 그대로 벽). 플레이어 Attribute QuestsDone = true (문 연출용)
	  - 지터버그 알 즉시 지급 (부화 슬롯, 가득 차면 대기 줄)
	  - 이후 초기화 때마다, 퀘스트를 끝낸 사람이 서버에 있으면 QUEST_SECRET_EGG_CHANCE(1%) 로
	    마법의 숲 둥지에 영혼 세계 수호자 알 등장 (퀘스트를 끝낸 사람만 주울 수 있음, 서버 공지)
	퀘스트 문 파트가 맵에 없으면 마법의 숲 구역 안에 임시 문을 만듦.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Pets = require(Shared.Data.Pets)
local Quests = require(Shared.Data.Quests)
local QuestRules = require(Shared.QuestRules)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local MapLayout = require(Shared.Data.MapLayout)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Landmarks = require(Server.Util.Landmarks)
local EggService = require(script.Parent.EggService)
local BaseService = require(script.Parent.BaseService)
local FusionService = require(script.Parent.FusionService)

local Attr = Tags.PlayerAttributes
local Groups = Tags.CollisionGroups

local QuestService = {}

local gates: { BasePart } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}
local rng = Random.new()

local function sendUpdate(player: Player, data: Types.PlayerData)
	Net.fire(player, Remotes.ToClient.QuestUpdate, {
		quests = QuestRules.view(data.quests),
		allDone = QuestRules.allDone(data.quests),
		gateOpen = data.questsRewarded,
	})
	Snapshot.section(player, "quests")
end

------------------------------------------------------------------
-- 퀘스트 문 (CollisionGroup)
------------------------------------------------------------------

local function setPartGroup(inst: Instance)
	if inst:IsA("BasePart") then
		inst.CollisionGroup = Groups.QuestPassed
	end
end

local function applyPassedGroup(player: Player)
	local character = player.Character
	if not character then
		return
	end
	for _, inst in character:GetDescendants() do
		setPartGroup(inst)
	end
	local old = characterConnections[player]
	if old then
		old:Disconnect()
	end
	characterConnections[player] = character.DescendantAdded:Connect(setPartGroup)
end

local function openGateFor(player: Player)
	player:SetAttribute(Attr.QuestsDone, true)
	applyPassedGroup(player)
end

------------------------------------------------------------------
-- 진행
------------------------------------------------------------------

local function complete(player: Player, data: Types.PlayerData)
	if data.questsRewarded or not QuestRules.allDone(data.quests) then
		return
	end
	data.questsRewarded = true
	openGateFor(player)
	BaseService.grantEgg(player, Quests.REWARD_EGG, "normal", {}, "quest")
	local egg = Pets.get(Quests.REWARD_EGG)
	Net.notify(
		player,
		"success",
		"마법의 숲 퀘스트 완료! 문이 열리고 "
			.. (if egg then egg.name else Quests.REWARD_EGG)
			.. " 알을 받았어요!"
	)
end

function QuestService.record(player: Player, event: QuestRules.QuestEvent)
	local _, data = Sessions.getLoaded(player)
	if not data or data.questsRewarded then
		return
	end
	local changed = QuestRules.apply(data.quests, event)
	if #changed == 0 then
		return
	end
	complete(player, data)
	sendUpdate(player, data)
end

-- 개발 명령용: 퀘스트 전부 끝내기
function QuestService.completeAll(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	for _, quest in Quests.list do
		data.quests[quest.id] = quest.target
	end
	complete(player, data)
	sendUpdate(player, data)
end

-- 초기화 때: 퀘스트를 끝낸 사람이 있으면 낮은 확률로 영혼 세계 수호자 알
local function rollSecretEgg()
	local anyone = false
	for _, session in Sessions.all() do
		local data = session.data
		if session.loaded and data and data.questsRewarded then
			anyone = true
			break
		end
	end
	if anyone and rng:NextNumber() < Config.QUEST_SECRET_EGG_CHANCE then
		EggService.spawnSpecialEgg(Quests.BIOME, Quests.SECRET_EGG, { questOnly = true, announce = true })
	end
end

------------------------------------------------------------------
-- 시작 / 플레이어
------------------------------------------------------------------

local function ensureGate()
	-- 자리 = MapLayout.specials.questGate (선임이 같은 태그로 진짜 문을 두면 임시 파트는 안 생김)
	local spot = MapLayout.specials.questGate
	gates = Landmarks.ensure({
		tag = Tags.QuestGate,
		name = "QuestGate",
		label = "퀘스트 문\n(퀘스트 3개를 끝내면 열려요)",
		position = Vector3.new(spot.x, MapLayout.FLOOR_Y + 6, spot.z),
		size = Vector3.new(14, 12, 2),
		color = Color3.fromRGB(80, 220, 180),
		material = Enum.Material.ForceField,
		transparency = 0.3,
	})
	for _, part in gates do
		part.CollisionGroup = Groups.QuestGate
	end
	-- 선임이 모델 전체에 태그를 붙였으면 모델 안 파트 전부
	for _, inst in CollectionService:GetTagged(Tags.QuestGate) do
		if inst:IsA("Model") and inst:IsDescendantOf(Workspace) then
			for _, child in inst:GetDescendants() do
				if child:IsA("BasePart") then
					child.CollisionGroup = Groups.QuestGate
				end
			end
		end
	end
end

local function setupCollisionGroups()
	local ok, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(Groups.QuestGate)
		PhysicsService:RegisterCollisionGroup(Groups.QuestPassed)
		PhysicsService:CollisionGroupSetCollidable(Groups.QuestGate, Groups.QuestPassed, false)
	end)
	if not ok then
		warn("[QuestService] CollisionGroup 설정 실패: " .. tostring(err))
	end
end

function QuestService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	player:SetAttribute(Attr.QuestsDone, data.questsRewarded)
	if data.questsRewarded then
		applyPassedGroup(player)
	elseif QuestRules.allDone(data.quests) then
		complete(player, data) -- 보상 직전에 서버가 꺼졌던 경우
	end
end

function QuestService.onCharacterAdded(player: Player, character: Model)
	local _, data = Sessions.getLoaded(player)
	if data and data.questsRewarded then
		character:WaitForChild("HumanoidRootPart", 10)
		applyPassedGroup(player)
	end
end

function QuestService.onPlayerLeaving(player: Player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end
end

function QuestService.start()
	setupCollisionGroups()
	ensureGate()

	BaseService.delivered:connect(function(player: Player, record: Types.IncubatorRecord)
		local pet = Pets.get(record.petId)
		QuestService.record(player, {
			kind = "deliver",
			biome = record.biomeId,
			rarity = if pet then pet.rarity else nil,
		})
	end)
	FusionService.fused:connect(function(player: Player)
		QuestService.record(player, { kind = "fuse" })
	end)
	EggService.resetDone:connect(function()
		rollSecretEgg()
	end)
end

return QuestService
