--!strict
--[[
	Sessions — 접속 중인 플레이어마다 서버 런타임 상태 (저장 안 되는 것) + 저장 데이터 참조 (첫 게임과 같은 모양)

	data 는 DataService 가 불러온 뒤에만 채워집니다 (loaded = true).
	다른 서비스는 Sessions.getLoaded(player) 로 (session, data) 를 한 번에 받으세요.
	송판 깨기 칸:
	  targetHp      물건 id → 남은 체력 (플레이어마다 따로 — BreakRules). 저장 안 함 (다시 들어오면 가득)
	  currentWorld  지금 있는 월드 (WorldService 가 순간이동할 때 · 캐릭터 위치로 맞춤)
	  exam / duel   진행 중인 승급 심사 · 시험관 대결 (ExamRules 상태, 없으면 nil — 동시에 하나만)
	  ownedPasses   이번 접속에서 소유가 확인된(또는 /buy 로 받은) 게임패스 key
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local ExamRules = require(ReplicatedStorage.Shared.ExamRules)

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
	targetHp: { [string]: number },
	currentWorld: number,
	exam: ExamRules.Exam?,
	duel: ExamRules.Duel?,
	ownedPasses: { [string]: boolean },
	joinedAt: number, -- os.clock() (논 시간 통계)
	countedPlaySeconds: number, -- stats.playSeconds 에 이미 더한 초
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
		releasing = false,
		released = false,
		targetHp = {},
		currentWorld = 1,
		exam = nil,
		duel = nil,
		ownedPasses = {},
		joinedAt = os.clock(),
		countedPlaySeconds = 0,
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

-- 지금 심사·대결 중인가 ("" | "exam" | "duel")
function Sessions.activity(session: Session): string
	if session.exam and not session.exam.finished then
		return "exam"
	elseif session.duel and not session.duel.finished then
		return "duel"
	end
	return ""
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
