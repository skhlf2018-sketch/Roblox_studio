--!strict
--[[
	Types — 송판 깨기 서버/클라가 같이 쓰는 타입 (저장 데이터 모양, Remote 로 오가는 데이터 모양). 설계서 7장.
]]

-- 설정 (SetSetting) — Config.SETTINGS 의 키
export type Settings = { [string]: boolean }

-- 통계 (저장됨, 화면 "도감"·순위·주임 검사용)
export type Stats = {
	trains: number, -- 아령 든 횟수
	hits: number, -- 친 횟수 (심사·대결 송판 포함)
	breaks: number, -- 깬 물건 수 (전부 합)
	moneyEarned: number, -- 번 돈 합
	examsPassed: number,
	examsFailed: number,
	duelsWon: number,
	duelsLost: number,
	playSeconds: number, -- 논 시간 (자동 저장 때 더함)
}

-- DataStore 에 저장되는 플레이어 데이터 (스키마 1 — Config.SCHEMA_VERSION)
export type PlayerData = {
	version: number,
	power: number, -- 저장된 힘 (아령으로 쌓임, 힘 배수 전 값이 아님 — 들 때 배수를 곱해서 쌓음)
	money: number,
	dumbbellLevel: number, -- 가진 가장 좋은 아령 (1~20)
	belt: number, -- 지금 띠 (1~12)
	world: number, -- 열린 월드 (1~3)
	broken: { [string]: number }, -- 물건 id → 깬 횟수
	powerBoost: number, -- 힘 배수 (1, 2, 4 … 2048)
	moneyPass: boolean, -- 돈 2배
	grandMaster: boolean, -- 월드 3 마지막 시험관을 이김 (엔딩)
	receipts: { string }, -- 처리한 영수증 번호 (최근 Config.RECEIPT_HISTORY_MAX 개)
	stats: Stats,
	settings: Settings,
	lastSaveTime: number, -- os.time()
}

-- Remote "Snapshot" 으로 보내는 전체 상태
export type Snapshot = {
	power: number,
	money: number,
	dumbbellLevel: number,
	belt: number,
	world: number,
	currentWorld: number,
	broken: { [string]: number },
	powerBoost: number,
	moneyPass: boolean,
	ownedPasses: { string }, -- 가진(소유 확인된·/buy 로 받은) 게임패스 key
	grandMaster: boolean,
	settings: Settings,
	saveEnabled: boolean,
	activity: string, -- "" | "exam" | "duel"
}

-- 서버 → 클라
export type Notify = { kind: string, text: string } -- kind: "info" | "success" | "error"

export type TrainResult = {
	gain: number, -- 이번에 오른 힘 (powerPerRep × PowerBoost)
	power: number, -- 오른 뒤 힘
}

export type HitResult = {
	targetId: string, -- Targets id 또는 "exam" / "duel"
	damage: number, -- 깎인 체력 (= 치는 힘, 힘 문턱 없음 — 사장님 결정 11번)
	hp: number, -- 남은 체력 (깨졌으면 다시 가득 = hpMax)
	hpMax: number,
	broken: boolean,
	reward: number?, -- 깨져서 받은 돈 (띠 배율·돈 2배 적용 후)
	reason: string?, -- 지금은 안 씀 (예전 "weak" 없앰 — 힘이 약해도 피해가 들어감)
}

export type ExamPhase = "start" | "progress" | "pass" | "fail"
export type ExamState = {
	phase: ExamPhase,
	broken: number, -- 깬 송판 수
	total: number, -- 깨야 할 송판 수 (10)
	secondsLeft: number,
	belt: number, -- 심사 보는 띠 (합격하면 이 띠가 됨)
	boardHp: number?, -- 지금 송판 남은 체력
	boardHpMax: number?, -- 송판 1장 체력
}

export type DuelPhase = "start" | "progress" | "win" | "lose"
export type DuelState = {
	phase: DuelPhase,
	mine: number, -- 내가 깬 송판 수
	theirs: number, -- 시험관이 깬 송판 수
	total: number, -- 15
	world: number,
	secondsLeft: number?, -- 대결 남은 시간 (DUEL_MAX_SECONDS 에서)
	boardHp: number?, -- 지금 내 송판 남은 체력
	boardHpMax: number?,
	examiner: string?, -- 시험관 이름
}

export type ProductGrant = { key: string, kind: string }

export type LeaderEntry = { name: string, value: number, userId: number }
export type LeaderboardUpdate = { power: { LeaderEntry }, money: { LeaderEntry } }

-- 선임 MapLayout 이 돌려주는 자리 (Vector3 아님 — 순수 데이터)
export type Point = { x: number, y: number, z: number }

return {}
