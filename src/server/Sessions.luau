--!strict
--[[
	Sessions — 접속 중인 플레이어마다 서버 런타임 상태 (저장 안 되는 것) + 저장 데이터 참조

	data 는 DataService 가 불러온 뒤에만 채워집니다 (loaded = true).
	다른 서비스는 Sessions.getLoaded(player) 로 (session, data) 를 한 번에 받으세요.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

type PlayerData = Types.PlayerData

export type Session = {
	player: Player,
	userId: number,
	data: PlayerData?,
	loaded: boolean,
	saveEnabled: boolean,
	saving: boolean,
	released: boolean,
	plotIndex: number,
	carryingUid: string?,
	carryPenalty: number,
	stunnedUntil: number,
	frozenUntil: number,
	effectiveSpeed: number,
	carrySpeed: number,
	walkSpeed: number,
	incomePerSecond: number,
	hasGrowthPass: boolean,
	hasMoneyPass: boolean,
	inSafeZone: boolean,
	cooldowns: { [string]: number },
}

local Sessions = {}

local sessions: { [Player]: Session } = {}

function Sessions.create(player: Player): Session
	local existing = sessions[player]
	if existing then
		return existing
	end
	local session: Session = {
		player = player,
		userId = player.UserId,
		data = nil,
		loaded = false,
		saveEnabled = false,
		saving = false,
		released = false,
		plotIndex = 0,
		carryingUid = nil,
		carryPenalty = 0,
		stunnedUntil = 0,
		frozenUntil = 0,
		effectiveSpeed = 0,
		carrySpeed = 0,
		walkSpeed = 16,
		incomePerSecond = 0,
		hasGrowthPass = false, -- 게임패스는 1차 버전에서 꺼 둠 (플래그만)
		hasMoneyPass = false,
		inSafeZone = false,
		cooldowns = {},
	}
	sessions[player] = session
	return session
end

function Sessions.get(player: Player): Session?
	return sessions[player]
end

-- 데이터가 불러와진 세션만
function Sessions.getLoaded(player: Player): (Session?, PlayerData?)
	local session = sessions[player]
	if session and session.loaded and session.data then
		return session, session.data
	end
	return nil, nil
end

function Sessions.remove(player: Player)
	sessions[player] = nil
end

function Sessions.all(): { [Player]: Session }
	return sessions
end

function Sessions.isStunned(session: Session, now: number): boolean
	return now < session.stunnedUntil or now < session.frozenUntil
end

-- 쿨다운 확인 + 통과하면 시각 기록
function Sessions.useCooldown(session: Session, key: string, seconds: number, now: number): boolean
	local last = session.cooldowns[key]
	if last and now - last < seconds then
		return false
	end
	session.cooldowns[key] = now
	return true
end

return Sessions
