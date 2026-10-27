--!strict
--[[
	DevCommands — 테스트용 채팅 명령 (6판 "씨앗을 훔치세요")
	  - Config.DEV_USER_IDS 가 비어 있으면: 스튜디오에서만, 누구나 (실서버에서는 아예 연결 안 됨)
	  - DEV_USER_IDS 에 UserId 를 넣으면: 그 사람만 (스튜디오·실서버 둘 다)
	주임·선임이 뒤 구역을 바로 시험해 볼 수 있게.
	받는 길: Player.Chatted + TextChatService 의 TextChatCommand (새 채팅에서 Chatted 가 안 올 때 대비, 같은 메시지는 한 번만)

	  /coins 1e9        코인 더하기 (/money 도 같음)
	  /speed 1e9        속도 더하기
	  /skip             지금 낮/밤/대기 단계를 바로 끝냄
	  /grow             정원에 심은 내 씨앗을 전부 바로 성체로
	  /trap 5           곰덫 개수 더하기
	  /crystal 5        사쿠라 크리스탈 더하기
	  /seed moon_lotus  그 식물의 씨앗을 가방에 바로 넣기 (심기·성장·밤 30배 시험용) — 5판 /egg
	  /plant star_mushroom 3  정원 빈자리에 그 식물 성체를 바로 (최대 20그루, 정원 칸까지, 열매 1개 달림) — 5판 /pet
	  /fruit 20 [식물id]  열매 가방에 열매 받기 (식물 id 를 안 쓰면 정원 첫 성체의 열매, 없으면 아기 데이지)
	  /tutorial reset   튜토리얼을 1단계부터 다시 (보상도 다시 받음)
	  /zone lake        그 구역 입구로 순간이동 (구역 id 또는 번호 1~15, "hub" = 허브 기본 스폰) — 긴 복도 시험용
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Data.Config)
local Plants = require(ReplicatedStorage.Shared.Data.Plants)
local MapLayout = require(ReplicatedStorage.Shared.Data.MapLayout)
local FruitRules = require(ReplicatedStorage.Shared.FruitRules)
local Types = require(ReplicatedStorage.Shared.Types)
local Server = script.Parent.Parent
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)
local DataSchema = require(Server.Logic.DataSchema)
local Net = require(Server.Net)
local Character = require(Server.Util.Character)
local Wallet = require(script.Parent.Wallet)
local CycleService = require(script.Parent.CycleService)
local ToolService = require(script.Parent.ToolService)
local PetService = require(script.Parent.PetService)
local IndexService = require(script.Parent.IndexService)
local SakuraService = require(script.Parent.SakuraService)
local TutorialService = require(script.Parent.TutorialService)
local EggService = require(script.Parent.EggService)
local BaseService = require(script.Parent.BaseService)
local FruitService = require(script.Parent.FruitService)

local DevCommands = {}

local COMMAND_NAMES =
	{ "coins", "money", "speed", "skip", "grow", "trap", "crystal", "seed", "plant", "fruit", "tutorial", "zone" }

local function isAllowed(player: Player): boolean
	if #Config.DEV_USER_IDS > 0 then
		return table.find(Config.DEV_USER_IDS, player.UserId) ~= nil
	end
	return RunService:IsStudio()
end

-- /zone: 구역 입구(구역 시작선 + 12) 또는 허브 기본 스폰으로 서버 순간이동 (위치 검증 쉼)
local function zoneTarget(arg: string): MapLayout.XZ?
	if arg == "hub" then
		return MapLayout.hubSpots.mainSpawn
	end
	local index = tonumber(arg)
	local range = if index then MapLayout.biomes[math.floor(index)] else MapLayout.biome(arg)
	if not range then
		return nil
	end
	return { x = 0, z = range.zMin + 12 }
end

local function teleportTo(player: Player, target: MapLayout.XZ): boolean
	local session = Sessions.get(player)
	local character = player.Character
	if not session or not character or not Character.getRoot(player) then
		return false
	end
	local position = Vector3.new(target.x, MapLayout.FLOOR_Y + 4, target.z)
	Sessions.exemptMovement(session, Config.MOVE_CHECK_EXEMPT_AFTER_TELEPORT)
	character:PivotTo(CFrame.new(position))
	EggService.resetCarryOrigin(player, position)
	return true
end

-- /plant: 정원 빈자리에 성체 count 그루 (정원 칸·빈 자리가 있는 만큼). 심은 수
local function plantNow(player: Player, data: Types.PlayerData, petId: string, count: number): number
	local planted = 0
	for _ = 1, count do
		local spot = BaseService.freeGardenSpot(player, "normal")
		if not spot or not PetService.hasGardenRoom(player) then
			break
		end
		local ok = PetService.addPlant(player, {
			uid = DataSchema.newUid(data, "p"),
			petId = petId,
			size = "normal",
			mutations = {},
			x = spot.x,
			z = spot.z,
			fruits = math.min(Config.FRUITS_ON_ADULT, Config.FRUIT_MAX_PER_PLANT),
			fruitProgress = 0,
		})
		if not ok then
			break
		end
		planted += 1
	end
	if planted > 0 then
		IndexService.discover(player, petId)
	end
	return planted
end

local function handle(player: Player, message: string)
	if not isAllowed(player) then
		return
	end
	local command, arg, arg2 = string.match(message, "^/(%a+)%s*(%S*)%s*(%S*)")
	if not command then
		return
	end
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	local amount = Validate.finiteNumber(tonumber(arg)) or 0
	if (command == "money" or command == "coins") and amount > 0 then
		Wallet.addMoney(player, amount)
	elseif command == "speed" and amount > 0 then
		Wallet.addSpeed(player, amount)
	elseif command == "skip" then
		CycleService.skip()
	elseif command == "grow" then
		for _, record in data.incubators do
			record.progress = record.required
		end
		Snapshot.section(player, "incubators")
		BaseService.growReadyNow(player)
	elseif command == "trap" and amount > 0 then
		data.tools.bearTrap = (data.tools.bearTrap or 0) + math.floor(amount)
		ToolService.refreshTools(player)
		Snapshot.section(player, "tools")
	elseif command == "crystal" and amount > 0 then
		SakuraService.addCrystals(player, amount)
	elseif command == "plant" and arg ~= nil and Plants.get(arg) then
		local count = math.clamp(math.floor(Validate.finiteNumber(tonumber(arg2)) or 1), 1, 20)
		if plantNow(player, data, arg, count) == 0 then
			Net.notify(player, "error", "[개발] 정원에 빈자리가 없어요")
			return
		end
	elseif command == "fruit" and amount > 0 then
		local wanted = arg2 or ""
		local fruitId: string = if wanted ~= "" and Plants.get(wanted)
			then wanted
			elseif data.pets[1] then data.pets[1].petId
			else "sprout_daisy"
		local plant = Plants.get(fruitId)
		if not plant then
			return
		end
		FruitRules.addToBag(data.fruits, fruitId, math.floor(amount), plant.fruitValue)
		FruitService.refreshBag(player)
	elseif command == "tutorial" and arg == "reset" then
		TutorialService.reset(player)
	elseif command == "seed" and arg ~= nil and Plants.get(arg) then
		if not BaseService.grantEgg(player, arg, "normal", {}, "dev") then
			return
		end
	elseif command == "zone" then
		local target = zoneTarget(arg or "")
		if not target or not teleportTo(player, target) then
			return
		end
	else
		return
	end
	Net.notify(player, "info", "[개발] " .. message)
end

-- 같은 메시지가 두 경로(Player.Chatted 와 TextChatCommand)로 같이 오면 한 번만 처리
local DEDUPE_SECONDS = 1
type Recent = { message: string, source: string, time: number }
local recent: { [Player]: Recent } = {}

local function receive(player: Player, message: string, source: string)
	local now = os.clock()
	local last = recent[player]
	if last and last.message == message and last.source ~= source and now - last.time < DEDUPE_SECONDS then
		return
	end
	recent[player] = { message = message, source = source, time = now }
	handle(player, message)
end

-- 새 채팅(TextChatService)용: TextChatCommand 로도 등록. 이 환경에 없으면 조용히 건너뜀 (Player.Chatted 는 그대로)
local function registerTextChatCommands()
	local ok, err = pcall(function(): ...any
		local TextChatService = game:GetService("TextChatService")
		local parent = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
		for _, name in COMMAND_NAMES do
			local command = Instance.new("TextChatCommand")
			command.Name = "Dev_" .. name
			command.PrimaryAlias = "/" .. name
			command.Triggered:Connect(function(source: TextSource, text: string)
				local player = Players:GetPlayerByUserId(source.UserId)
				if player then
					receive(player, text, "textchat")
				end
			end)
			command.Parent = parent
		end
	end)
	if not ok then
		warn("[DevCommands] TextChatCommand 등록 실패 (Player.Chatted 로만 받음): " .. tostring(err))
	end
end

function DevCommands.start()
	if #Config.DEV_USER_IDS == 0 and not RunService:IsStudio() then
		return
	end
	local function hook(player: Player)
		player.Chatted:Connect(function(message: string)
			receive(player, message, "chatted")
		end)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player: Player)
		recent[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	registerTextChatCommands()
	print("[DevCommands] 개발 명령 켜짐: /" .. table.concat(COMMAND_NAMES, " /"))
end

return DevCommands
