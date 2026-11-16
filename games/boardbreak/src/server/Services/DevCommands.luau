--!strict
--[[
	DevCommands — 시험용 채팅 명령 (설계서 7장) — 첫 게임 DevCommands 와 같은 방식
	  - Config.DEV_USER_IDS 가 비어 있으면: 스튜디오에서만, 누구나 (실서버에서는 아예 연결 안 됨)
	  - DEV_USER_IDS 에 UserId 를 넣으면: 그 사람만 (스튜디오·실서버 둘 다)
	받는 길: Player.Chatted + TextChatService 의 TextChatCommand (같은 메시지는 한 번만)

	  /power 1e9      힘을 그 값으로 (1e60 까지)
	  /money 1e9      돈을 그 값으로
	  /belt 8         띠를 그 번호로 (1~12). 열린 월드도 띠에 맞춤 (띠 4 → 월드 2, 띠 8 → 월드 3), 12 = 그랜드 마스터
	  /world 3        그 월드를 열고 (띠가 모자라면 그 월드 첫 띠로 올림) 그리로 순간이동
	  /dumbbell 20    아령 레벨 (1~20)
	  /buy power_8    게임패스를 무료로 받기 (Data/Products 의 key — ProductService.grant, 스튜디오/DEV 만)
	  /unbuy          힘 배수·돈 2배를 처음으로 되돌림 + 이 접속 동안 게임패스 확인 쉼 (새 플레이어 화면 시험용)
	  /reset          처음부터 (힘·돈·아령·띠·월드·깬 기록·패스. 영수증 기록은 남김) → 월드 1 스폰
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Products = require(Shared.Data.Products)
local Belts = require(Shared.Data.Belts)
local Dumbbells = require(Shared.Data.Dumbbells)
local Worlds = require(Shared.Data.Worlds)
local Format = require(Shared.Format)
local Progression = require(Shared.Progression)
local Server = script.Parent.Parent
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Attributes = require(Server.Attributes)
local Validate = require(Server.Logic.Validate)
local DataSchema = require(Server.Logic.DataSchema)
local Net = require(Server.Net)
local Wallet = require(script.Parent.Wallet)
local ProductService = require(script.Parent.ProductService)
local ExamService = require(script.Parent.ExamService)
local WorldService = require(script.Parent.WorldService)

local DevCommands = {}

local COMMAND_NAMES = { "power", "money", "belt", "world", "dumbbell", "buy", "unbuy", "reset" }

function DevCommands.isAllowed(player: Player): boolean
	if #Config.DEV_USER_IDS > 0 then
		return table.find(Config.DEV_USER_IDS, player.UserId) ~= nil
	end
	return RunService:IsStudio()
end

local function parseNumber(text: string?): number?
	if not text then
		return nil
	end
	return Validate.finiteNumber(tonumber(text))
end

local function integerArg(text: string?, minValue: number, maxValue: number): number?
	local n = parseNumber(text)
	if not n or n % 1 ~= 0 or n < minValue or n > maxValue then
		return nil
	end
	return n
end

-- 명령 하나 처리 (테스트도 부름). 처리했으면 true
function DevCommands.handle(player: Player, message: string): boolean
	if typeof(message) ~= "string" or string.sub(message, 1, 1) ~= "/" or not DevCommands.isAllowed(player) then
		return false
	end
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return false
	end
	local words: { string } = {}
	for word in string.gmatch(message, "%S+") do
		table.insert(words, word)
	end
	local command = string.lower(string.sub(words[1] or "", 2))
	local arg = words[2]
	local text: string
	if command == "power" then
		local n = parseNumber(arg)
		if not n or n < 0 then
			Net.notify(player, "error", "[개발] /power <0 이상 숫자> (예: /power 1e9)")
			return true
		end
		Wallet.set(player, n, nil)
		text = "힘 = " .. Format.number(data.power)
	elseif command == "money" then
		local n = parseNumber(arg)
		if not n or n < 0 then
			Net.notify(player, "error", "[개발] /money <0 이상 숫자>")
			return true
		end
		Wallet.set(player, nil, n)
		text = "돈 = " .. Format.number(data.money)
	elseif command == "belt" then
		local n = integerArg(arg, 1, Belts.COUNT)
		if not n then
			Net.notify(player, "error", "[개발] /belt <1~12>")
			return true
		end
		ExamService.cancel(player)
		data.belt = n
		data.world = Progression.worldsFromBelt(n)
		data.grandMaster = Progression.isGrandMaster(n)
		if session.currentWorld > data.world then
			session.currentWorld = data.world
			WorldService.placeAtSpawn(player, data.world)
		end
		local belt = Belts.get(n)
		text = "띠 = " .. (if belt then belt.name else tostring(n))
	elseif command == "world" then
		local n = integerArg(arg, 1, Worlds.COUNT)
		if not n then
			Net.notify(player, "error", "[개발] /world <1~3>")
			return true
		end
		ExamService.cancel(player)
		-- 그 월드가 열리게 띠를 맞춤 (월드 w 의 첫 띠 = 4(w-1), 저장 데이터가 앞뒤가 맞게)
		data.belt = math.max(data.belt, 4 * (n - 1))
		data.belt = math.max(1, data.belt)
		data.world = math.max(data.world, Progression.worldsFromBelt(data.belt))
		data.grandMaster = Progression.isGrandMaster(data.belt)
		session.currentWorld = n
		WorldService.placeAtSpawn(player, n)
		local info = Worlds.get(n)
		text = "월드 = " .. (if info then info.name else tostring(n))
	elseif command == "dumbbell" then
		local n = integerArg(arg, 1, Dumbbells.COUNT)
		if not n then
			Net.notify(player, "error", "[개발] /dumbbell <1~20>")
			return true
		end
		data.dumbbellLevel = n
		local d = Dumbbells.get(n)
		text = "아령 = " .. (if d then d.name else tostring(n))
	elseif command == "buy" then
		local key = arg or ""
		if not Products.get(key) or not ProductService.grant(player, key, "dev") then
			Net.notify(player, "error", "[개발] 모르는 상품: " .. key .. " (power_2 … power_2048, money_2)")
			return true
		end
		text = "받음: " .. key
	elseif command == "unbuy" then
		ProductService.setIgnorePassesForTest(player, true)
		data.powerBoost = 1
		data.moneyPass = false
		table.clear(session.ownedPasses)
		Snapshot.section(player, "passes")
		text =
			"힘 배수·돈 2배를 처음으로 되돌렸어요 (다시 접속하면 가진 게임패스가 다시 적용돼요)"
	elseif command == "reset" then
		ExamService.cancel(player)
		local fresh = DataSchema.default(os.time())
		local keep = data.receipts
		for key, value in fresh :: any do
			(data :: any)[key] = value
		end
		data.receipts = keep
		table.clear(session.targetHp)
		table.clear(session.ownedPasses)
		session.currentWorld = 1
		WorldService.placeAtSpawn(player, 1)
		text = "처음부터 다시!"
	else
		return false
	end
	Attributes.sync(player)
	Snapshot.send(player)
	Net.notify(player, "info", "[개발] " .. text)
	return true
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
	local ok, err = pcall(DevCommands.handle, player, message)
	if not ok then
		warn("[DevCommands] 오류: " .. tostring(err))
	end
end

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
