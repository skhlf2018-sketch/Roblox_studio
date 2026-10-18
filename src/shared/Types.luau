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

-- DataStore 에 저장되는 플레이어 데이터 (스키마 버전 1)
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
	freeRewardClaimed: boolean,
	plotIndex: number,
	saveEnabled: boolean,
}

return {}
