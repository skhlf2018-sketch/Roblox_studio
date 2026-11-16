--!strict
--[[
	PlayerLifecycle — 접속/나감/캐릭터 생성 순서를 한 곳에서 (첫 게임과 같은 방식)

	접속: 세션 만들기 → 데이터 불러오기(기다림) → 준비 (leaderstats · 지금 월드 · Attribute · 게임패스 확인) → SaveEnabled ·
	      DataLoaded → Snapshot → 순위판 한 번. 준비 단계는 하나씩 pcall (하나가 터져도 나머지는 진행)
	나감: 심사·대결 정리 → 저장 + 세션 락 해제 → 세션 삭제 (저장이 끝내 실패하면 DataService 가 나중에 다시)
	      불러오는 중에 나가면 data 는 저장하지 않고 락만 풂
	ClientReady Remote: 클라 화면이 준비되면 → Snapshot (접속 직후 Snapshot 을 놓친 경우 대비)
	캐릭터가 생기면 지금 월드 스폰으로 (WorldService)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Attributes = require(Server.Attributes)
local Services = script.Parent
local DataService = require(Services.DataService)
local Wallet = require(Services.Wallet)
local WorldService = require(Services.WorldService)
local ExamService = require(Services.ExamService)
local ProductService = require(Services.ProductService)
local LeaderboardService = require(Services.LeaderboardService)

local Attr = Tags.PlayerAttributes

local PlayerLifecycle = {}

local function safely(name: string, fn: (Player) -> ...any, player: Player)
	local ok, err = pcall(fn, player)
	if not ok then
		warn(string.format("[PlayerLifecycle] %s 실패 (%s): %s", name, player.Name, tostring(err)))
	end
end

-- 논 시간을 통계에 더함 (자동 저장 전·나갈 때)
function PlayerLifecycle.countPlayTime(session: Sessions.Session)
	local data = session.data
	if not data then
		return
	end
	local total = math.max(0, os.clock() - session.joinedAt)
	data.stats.playSeconds += math.max(0, total - session.countedPlaySeconds)
	session.countedPlaySeconds = total
end

function PlayerLifecycle.onPlayerAdded(player: Player)
	local session = Sessions.create(player)
	player:SetAttribute(Attr.DataLoaded, false)
	player:SetAttribute(Attr.Activity, "")

	player.CharacterAdded:Connect(function()
		WorldService.onCharacterAdded(player)
	end)

	local data, saveEnabled, newerVersion = DataService.load(player)
	if player.Parent == nil then
		DataService.abandonLoad(session, data, saveEnabled)
		Sessions.remove(player)
		return
	end
	session.data = data
	session.saveEnabled = saveEnabled
	session.loaded = true
	session.joinedAt = os.clock()

	safely("leaderstats", Wallet.setupLeaderstats, player)
	safely("WorldService", WorldService.onPlayerReady, player)
	safely("Attributes", Attributes.sync, player)
	safely("ProductService", ProductService.onPlayerReady, player)

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
	safely("LeaderboardService", LeaderboardService.onPlayerReady, player)
end

function PlayerLifecycle.onPlayerRemoving(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	safely("ExamService", ExamService.cancel, player)
	if session.loaded then
		PlayerLifecycle.countPlayTime(session)
		if not DataService.save(player, true) then
			DataService.queueRelease(session)
		end
		Sessions.remove(player)
	end
	-- 아직 불러오는 중이면 onPlayerAdded 가 끝날 때 정리함
end

-- SetSetting(key, value): Config.SETTINGS 의 키 + boolean 만. 바뀌었으면 true
function PlayerLifecycle.setSetting(player: Player, rawKey: unknown, rawValue: unknown): boolean
	local _, data = Sessions.getLoaded(player)
	if not data or typeof(rawKey) ~= "string" or typeof(rawValue) ~= "boolean" then
		return false
	end
	local key = rawKey :: string
	if Config.SETTINGS[key] == nil then
		return false
	end
	data.settings[key] = rawValue :: boolean
	Snapshot.section(player, "settings")
	return true
end

function PlayerLifecycle.start()
	Net.on(Remotes.ToServer.ClientReady, function(player: Player)
		Snapshot.send(player)
	end)
	Net.on(Remotes.ToServer.SetSetting, function(player: Player, key: unknown, value: unknown)
		PlayerLifecycle.setSetting(player, key, value)
	end)
	Players.PlayerAdded:Connect(PlayerLifecycle.onPlayerAdded)
	Players.PlayerRemoving:Connect(PlayerLifecycle.onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerLifecycle.onPlayerAdded, player)
	end
	-- 논 시간 통계 (자동 저장 주기와 같게)
	task.spawn(function()
		while true do
			task.wait(30)
			for _, session in Sessions.all() do
				if session.loaded then
					PlayerLifecycle.countPlayTime(session)
				end
			end
		end
	end)
end

return PlayerLifecycle
