--!strict
--[[
	PlayerLifecycle — 접속/나감/캐릭터 생성 순서를 한 곳에서 관리

	접속:
	  1) 세션 만들기 → 2) 베이스 배정(바로, 가득 차면 0 = 누가 나갈 때 배정) → 3) 데이터 불러오기(기다림)
	  4) 준비: 펫 수입 계산 → 속도 → 부화 슬롯(오프라인 성장) → 오프라인 수입 → 업그레이드 → 도구
	          → 사쿠라·퀘스트 Attribute → Snapshot 전송
	     준비 단계는 하나씩 pcall 로 감쌈 (하나가 터져도 나머지·DataLoaded·Snapshot 은 진행)
	나감:
	  들고 있던 알 놓기 → 곰덫·제단 제물 정리 → 베이스 비우기 → 저장 + 세션 락 해제 → 세션 삭제
	  (저장이 끝내 실패하면 DataService 가 나중에 다시 시도)
	  불러오는 중에 나가면 data 는 저장하지 않고 락만 풂 (오프라인 수입 보존)
	RequestSnapshot Remote: 클라가 준비되면 요청 (접속 직후 Snapshot 을 놓친 경우 대비)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Services = script.Parent
local DataService = require(Services.DataService)
local SpeedService = require(Services.SpeedService)
local Wallet = require(Services.Wallet)
local EggService = require(Services.EggService)
local BaseService = require(Services.BaseService)
local PetService = require(Services.PetService)
local UpgradeService = require(Services.UpgradeService)
local ToolService = require(Services.ToolService)
local RewardService = require(Services.RewardService)
local SakuraService = require(Services.SakuraService)
local AltarService = require(Services.AltarService)
local QuestService = require(Services.QuestService)
local AntiCheatService = require(Services.AntiCheatService)

local Attr = Tags.PlayerAttributes

local PlayerLifecycle = {}

local function safely(name: string, fn: (Player) -> ...any, player: Player)
	local ok, err = pcall(fn, player)
	if not ok then
		warn(string.format("[PlayerLifecycle] %s 실패 (%s): %s", name, player.Name, tostring(err)))
	end
end

local function onCharacterAdded(player: Player, character: Model)
	task.spawn(AntiCheatService.onCharacterAdded, player, character)
	task.spawn(EggService.onCharacterAdded, player, character)
	task.spawn(SpeedService.onCharacterAdded, player, character)
	task.spawn(BaseService.onCharacterAdded, player, character)
	local session = Sessions.get(player)
	if session and session.loaded then
		task.spawn(ToolService.onCharacterAdded, player, character)
		task.spawn(QuestService.onCharacterAdded, player, character)
	end
end

local function onPlayerAdded(player: Player)
	local session = Sessions.create(player)
	player:SetAttribute(Attr.DataLoaded, false)
	player:SetAttribute(Attr.CarryingEgg, "")
	if BaseService.assignPlot(player) == 0 then
		Net.notify(player, "error", "빈 베이스가 없어요. 누가 나가면 바로 베이스를 드릴게요!")
	end

	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		EggService.dropCarried(player, "death")
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end

	local data, saveEnabled, newerVersion = DataService.load(player)
	if player.Parent == nil then
		-- 불러오는 사이에 나감: data 는 건드리지 않고 락만 풂 (lastSaveTime 을 새로 찍지 않아 오프라인 수입 보존)
		DataService.abandonLoad(session, data, saveEnabled)
		Sessions.remove(player)
		return
	end
	session.data = data
	session.saveEnabled = saveEnabled
	session.loaded = true

	safely("PetService", PetService.onPlayerReady, player)
	safely("leaderstats", Wallet.setupLeaderstats, player)
	safely("SpeedService", SpeedService.refresh, player)
	safely("BaseService", BaseService.onPlayerReady, player)
	safely("RewardService", RewardService.onPlayerReady, player)
	safely("UpgradeService", UpgradeService.onPlayerReady, player)
	safely("ToolService", ToolService.onPlayerReady, player)
	safely("SakuraService", SakuraService.onPlayerReady, player)
	safely("QuestService", QuestService.onPlayerReady, player)

	player:SetAttribute(Attr.SaveEnabled, saveEnabled)
	player:SetAttribute(Attr.DataLoaded, true)
	if newerVersion then
		Net.notify(
			player,
			"error",
			"게임이 업데이트되는 중이에요. 이번 접속은 저장되지 않으니 잠시 뒤 다시 접속해 주세요."
		)
	elseif not saveEnabled and not DataService.isMemoryMode() then
		Net.notify(
			player,
			"error",
			"저장 데이터를 불러오지 못했어요. 이번 접속은 저장되지 않아요. 다시 접속해 주세요."
		)
	end
	safely("Snapshot", Snapshot.send, player)
end

local function onPlayerRemoving(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	safely("EggService", EggService.onPlayerLeaving, player)
	safely("ToolService", ToolService.onPlayerLeaving, player)
	safely("AltarService", AltarService.onPlayerLeaving, player)
	safely("QuestService", QuestService.onPlayerLeaving, player)
	safely("BaseService", BaseService.onPlayerLeaving, player)
	if session.loaded then
		if not DataService.save(player, true) then
			DataService.queueRelease(session)
		end
		Sessions.remove(player)
	end
	-- 아직 불러오는 중이면 onPlayerAdded 가 끝날 때 정리함
end

function PlayerLifecycle.start()
	Net.on(Remotes.ToServer.RequestSnapshot, function(player: Player)
		Snapshot.send(player)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerLifecycle
