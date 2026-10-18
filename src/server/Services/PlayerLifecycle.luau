--!strict
--[[
	PlayerLifecycle — 접속/나감/캐릭터 생성 순서를 한 곳에서 관리

	접속:
	  1) 세션 만들기 → 2) 베이스 배정(바로) → 3) 데이터 불러오기(기다림)
	  4) 준비: 펫 수입 계산 → 속도 → 부화 슬롯(오프라인 성장) → 오프라인 수입 → 도구 → Snapshot 전송
	나감:
	  들고 있던 알 놓기 → 곰덫 정리 → 베이스 비우기 → 저장 + 세션 락 해제 → 세션 삭제
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

local Attr = Tags.PlayerAttributes

local PlayerLifecycle = {}

local function onCharacterAdded(player: Player, character: Model)
	task.spawn(EggService.onCharacterAdded, player, character)
	task.spawn(SpeedService.onCharacterAdded, player, character)
	task.spawn(BaseService.onCharacterAdded, player, character)
	local session = Sessions.get(player)
	if session and session.loaded then
		task.spawn(ToolService.onCharacterAdded, player, character)
	end
end

local function onPlayerAdded(player: Player)
	local session = Sessions.create(player)
	player:SetAttribute(Attr.DataLoaded, false)
	player:SetAttribute(Attr.CarryingEgg, "")
	BaseService.assignPlot(player)

	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		EggService.dropCarried(player, "death")
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end

	local data, saveEnabled = DataService.load(player)
	session.data = data
	session.saveEnabled = saveEnabled
	session.loaded = true
	if player.Parent == nil then
		-- 불러오는 사이에 나감: 락만 풀고 끝
		DataService.save(player, true)
		Sessions.remove(player)
		return
	end

	PetService.onPlayerReady(player)
	Wallet.setupLeaderstats(player)
	SpeedService.refresh(player)
	BaseService.onPlayerReady(player)
	RewardService.onPlayerReady(player)
	UpgradeService.onPlayerReady(player)
	ToolService.onPlayerReady(player)

	player:SetAttribute(Attr.SaveEnabled, saveEnabled)
	player:SetAttribute(Attr.DataLoaded, true)
	if not saveEnabled and not DataService.isMemoryMode() then
		Net.notify(
			player,
			"error",
			"저장 데이터를 불러오지 못했어요. 이번 접속은 저장되지 않아요. 다시 접속해 주세요."
		)
	end
	Snapshot.send(player)
end

local function onPlayerRemoving(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	EggService.onPlayerLeaving(player)
	ToolService.onPlayerLeaving(player)
	BaseService.onPlayerLeaving(player)
	if session.loaded then
		DataService.save(player, true)
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
