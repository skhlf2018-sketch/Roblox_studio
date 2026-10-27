--!strict
--[[
	Sessions — 접속 중인 플레이어마다 서버 런타임 상태 (저장 안 되는 것) + 저장 데이터 참조
	(6판: 자동 수입이 없어져 incomePerSecond 칸 없앰. 물 주기 식물별 쿨다운은 cooldowns["water:" .. uid])

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
	releasing: boolean, -- 나갈 때 저장(락 해제) 진행 중
	released: boolean, -- 락 해제 저장이 성공함 (이후 저장 안 함)
	plotIndex: number,
	carryingUid: string?,
	carryPenalty: number,
	stunnedUntil: number,
	frozenUntil: number,
	effectiveSpeed: number,
	carrySpeed: number,
	walkSpeed: number,
	hasGrowthPass: boolean,
	hasMoneyPass: boolean, -- 6판: 열매 판매 코인 × 2 (플래그만)
	inSafeZone: boolean,
	cooldowns: { [string]: number },
	moveExemptUntil: number, -- 이 시각(os.clock)까지 위치 검증 쉼 (서버 순간이동·래그돌)
	busy: { [string]: boolean }, -- yield 하는 요청 중복 방지 (5판: 무료 보상 그룹 확인이 없어져 지금은 쓰는 곳 없음)
	-- 2판
	currentZone: string, -- 지금 있는 곳 (MapLayout.zoneAt: 구역 id | "hub" | "")
	onTreadmill: boolean, -- 러닝머신 위에 고정됨 (WalkSpeed 0, 서버가 위치 고정)
	treadmillArmed: boolean, -- false = 방금 내림 → 러닝머신 밖으로 한 번 나가야 다시 탈 수 있음
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
		releasing = false,
		released = false,
		plotIndex = 0,
		carryingUid = nil,
		carryPenalty = 0,
		stunnedUntil = 0,
		frozenUntil = 0,
		effectiveSpeed = 0,
		carrySpeed = 0,
		walkSpeed = 16,
		hasGrowthPass = false, -- 게임패스는 1차 버전에서 꺼 둠 (플래그만)
		hasMoneyPass = false,
		inSafeZone = false,
		cooldowns = {},
		moveExemptUntil = 0,
		busy = {},
		currentZone = "",
		onTreadmill = false,
		treadmillArmed = true,
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

-- 위치 검증을 seconds 동안 쉼 (서버가 순간이동시키거나 날려 보낼 때)
function Sessions.exemptMovement(session: Session, seconds: number)
	session.moveExemptUntil = math.max(session.moveExemptUntil, os.clock() + seconds)
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
