--!strict
--[[
	AntiCheatService — 치트 방지 2단계: 서버 위치 검증 (속도핵·순간이동)

	1초(MOVE_CHECK_INTERVAL)마다 HumanoidRootPart 위치를 기록해서
	  수평 이동 거리 > (서버가 정한 WalkSpeed × 1.5) × 경과초 + 30   (Logic/MoveCheck)
	이면 마지막 정상 위치로 되돌리고 경고 +1. 경고 MOVE_CHECK_KICK_WARNINGS(5)개면 Kick.
	  - WalkSpeed 는 서버 값(session.walkSpeed)을 씀. 지난번과 이번 중 큰 값 기준 (알을 내려놓아 빨라진 경우)
	  - 쉬는 경우: 래그돌·곰덫(Stunned), 서버 순간이동 직후(session.moveExemptUntil), 앉음, 죽음, 막 스폰
	  - 경고는 저장하지 않고, MOVE_CHECK_WARNING_DECAY_SECONDS 마다 1개씩 줄어듦 (렉 오탐이 쌓여 Kick 되지 않게)
	  - 수평 거리만 봄 (떨어지기·점프는 검사 안 함)
	다른 서비스가 수상한 일을 발견하면 AntiCheatService.flag(player, 이유) → 경고 +1 (배달 검사 등)
	선임 주의: 클라에서 캐릭터를 순간이동시키는 기능(점프대·텔레포트 버튼)을 만들면 걸립니다.
	          그런 기능은 서버가 옮기고 Sessions.exemptMovement 를 부르도록 수석에게 요청하세요.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Character = require(Server.Util.Character)
local MoveCheck = require(Server.Logic.MoveCheck)

type Track = {
	cframe: CFrame,
	time: number,
	walkSpeed: number,
}

local Attr = Tags.PlayerAttributes

local AntiCheatService = {}

local tracks: { [Player]: Track } = {}
local warnings: { [Player]: MoveCheck.Warnings } = {}

local function warningsFor(player: Player): MoveCheck.Warnings
	local w = warnings[player]
	if not w then
		w = MoveCheck.newWarnings(os.clock())
		warnings[player] = w
	end
	return w
end

-- 경고 1개 (이유는 서버 로그 + 플레이어 알림)
function AntiCheatService.flag(player: Player, reason: string)
	local count, kick = MoveCheck.addWarning(warningsFor(player), os.clock())
	player:SetAttribute(Attr.MoveWarnings, count)
	warn(string.format("[AntiCheat] %s 경고 %d/%d: %s", player.Name, count, Config.MOVE_CHECK_KICK_WARNINGS, reason))
	if kick then
		player:Kick(
			"비정상적인 움직임이 여러 번 감지되어 연결이 끊겼어요. 다시 접속해 주세요."
		)
		return
	end
	Net.notify(
		player,
		"error",
		"비정상적인 움직임이 감지됐어요. (" .. count .. "/" .. Config.MOVE_CHECK_KICK_WARNINGS .. ")"
	)
end

-- 위치 검증을 seconds 동안 쉼
function AntiCheatService.exempt(player: Player, seconds: number)
	local session = Sessions.get(player)
	if session then
		Sessions.exemptMovement(session, seconds)
	end
	tracks[player] = nil
end

local function isExempt(player: Player, session: Sessions.Session, humanoid: Humanoid, now: number): boolean
	if now < session.moveExemptUntil or Sessions.isStunned(session, now) then
		return true
	end
	if humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand or humanoid.SeatPart ~= nil then
		return true
	end
	return player:GetAttribute(Attr.Stunned) == true
end

local function checkPlayer(player: Player, session: Sessions.Session, now: number)
	local _, humanoid, root = Character.get(player)
	if not humanoid or not root then
		tracks[player] = nil
		return
	end
	local last = tracks[player]
	local current: Track = { cframe = root.CFrame, time = now, walkSpeed = session.walkSpeed }
	if not last or isExempt(player, session, humanoid, now) then
		tracks[player] = current
		return
	end
	local from, to = last.cframe.Position, root.Position
	local distance = MoveCheck.horizontalDistance(from.X, from.Z, to.X, to.Z)
	local walkSpeed = math.max(last.walkSpeed, session.walkSpeed)
	if MoveCheck.isViolation(distance, walkSpeed, now - last.time) then
		-- 마지막 정상 위치로 되돌림 (기준점은 그대로, 시각만 갱신)
		root.AssemblyLinearVelocity = Vector3.zero
		local character = player.Character
		if character then
			character:PivotTo(last.cframe)
		end
		tracks[player] = { cframe = last.cframe, time = now, walkSpeed = walkSpeed }
		AntiCheatService.flag(
			player,
			string.format(
				"1초에 %.0f 스터드 이동 (허용 %.0f)",
				distance,
				MoveCheck.allowedDistance(walkSpeed, now - last.time)
			)
		)
		return
	end
	tracks[player] = current
end

local function tick()
	local now = os.clock()
	for player, session in Sessions.all() do
		if session.loaded and player.Parent ~= nil then
			checkPlayer(player, session, now)
			local w = warnings[player]
			if w and w.count > 0 then
				local before = w.count
				MoveCheck.decay(w, now)
				if w.count ~= before then
					player:SetAttribute(Attr.MoveWarnings, w.count)
				end
			end
		end
	end
end

function AntiCheatService.onCharacterAdded(player: Player, _character: Model)
	AntiCheatService.exempt(player, Config.MOVE_CHECK_EXEMPT_AFTER_TELEPORT + 1)
end

function AntiCheatService.onPlayerLeaving(player: Player)
	tracks[player] = nil
	warnings[player] = nil
end

function AntiCheatService.start()
	Players.PlayerRemoving:Connect(AntiCheatService.onPlayerLeaving)
	task.spawn(function()
		while true do
			task.wait(Config.MOVE_CHECK_INTERVAL)
			local ok, err = pcall(tick)
			if not ok then
				warn("[AntiCheatService] tick 오류: " .. tostring(err))
			end
		end
	end)
end

return AntiCheatService
