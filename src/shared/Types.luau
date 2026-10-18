--!strict
--[[
	Types — 서버/클라가 같이 쓰는 타입 (저장 데이터 모양, Remote 로 오가는 데이터 모양)
]]

export type Phase = "Day" | "Night" | "Intermission"

-- 보관함에 있는 펫 1마리
export type PetRecord = {
	uid: string,
	petId: string,
	size: string,
	mutations: { string },
}

-- 부화 슬롯에서 자라는 알 1개 (저장됨)
export type IncubatorRecord = {
	uid: string,
	petId: string,
	size: string,
	mutations: { string },
	biomeId: string,
	slot: number,
	progress: number, -- 지금까지 자란 시간(초)
	required: number, -- 다 자라는 데 필요한 시간(초) = 원본 ÷ GROWTH_MULTIPLIER
}

-- 부화 슬롯이 가득 찼을 때 기다리는 선물 알 (제단·비밀 통로 합성·퀘스트 보상, 저장됨)
export type QueuedEgg = {
	petId: string,
	size: string,
	mutations: { string },
	source: string, -- "altar" | "shrine" | "quest"
}

-- DataStore 에 저장되는 플레이어 데이터 (스키마 버전 2)
export type PlayerData = {
	version: number,
	money: number,
	speed: number, -- 모은 속도 (트레일 배율 적용 전)
	pets: { PetRecord },
	equipped: { string }, -- 장착된 펫 uid 목록
	penLevel: number,
	treadmillLevel: number, -- 0 = 잠김
	trails: { string }, -- 산 트레일 id 목록
	indexDiscovered: { [string]: boolean }, -- 도감 발견 (petId → true)
	indexClaimed: { [string]: boolean }, -- 도감 보상 수령 (petId → true)
	indexCompleteClaimed: boolean,
	tools: { [string]: number }, -- 소모 도구 개수 (bearTrap)
	incubators: { IncubatorRecord },
	lastSaveTime: number, -- os.time()
	freeRewardClaimed: boolean,
	nextUid: number,
	stats: { [string]: number },
	-- 버전 2 (2단계)
	weapons: { string }, -- 해금한 구역 무기 id (Data/Weapons, 기본 방망이 제외)
	sakuraCrystals: number, -- 사쿠라 크리스탈 개수
	sakuraUnlocked: boolean, -- 사쿠라 인큐베이터 해금 (학 바침)
	shrineUsed: { [string]: boolean }, -- 비밀 통로 합성 사용 (결과 petId → true, 계정당 1번)
	quests: { [string]: number }, -- 마법의 숲 퀘스트 진행도 (quest id → 숫자)
	questsRewarded: boolean, -- 퀘스트 3개 완료 보상(문 열림 + 지터버그 알)을 받았나
	eggQueue: { QueuedEgg },
}

-- 알 정보 (RunAlert, 공지 등에 쓰는 가벼운 모양)
export type EggInfo = {
	uid: string,
	petId: string,
	biomeId: string,
	rarity: string,
	size: string,
	mutations: { string },
	special: boolean,
}

-- 퀘스트 1개 진행 상황 (Snapshot.quests / QuestUpdate)
export type QuestView = {
	id: string,
	name: string,
	progress: number,
	target: number,
	done: boolean,
}

-- 클라이언트로 보내는 전체 상태 (Snapshot)
export type Snapshot = {
	money: number,
	speed: number,
	effectiveSpeed: number,
	incomePerSecond: number,
	pets: { PetRecord },
	equipped: { string },
	penLevel: number,
	penSlots: number,
	treadmillLevel: number,
	trails: { string },
	trailMultiplier: number,
	indexDiscovered: { [string]: boolean },
	indexClaimed: { [string]: boolean },
	indexCompleteClaimed: boolean,
	unlockedWeapons: { string },
	tools: { [string]: number },
	incubators: { IncubatorRecord },
	eggQueue: { QueuedEgg },
	freeRewardClaimed: boolean,
	plotIndex: number,
	saveEnabled: boolean,
	-- 2단계
	sakuraCrystals: number,
	sakuraUnlocked: boolean,
	shrineUsed: { [string]: boolean },
	quests: { QuestView },
	questsDone: boolean,
	petInventoryMax: number,
}

return {}
