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

-- 가방에 있는 알 1개 (2판 수정, 저장됨): 허브에 들고 들어온 알 · 선물 알(제단·비밀 통로·퀘스트) · 우리에서 다시 주운 알.
-- 가방 속 알은 자라지 않음 (progress 그대로). PlaceEgg 로 우리에 놓으면 같은 uid 로 IncubatorRecord 가 됨
export type BagEgg = {
	uid: string,
	petId: string,
	size: string,
	mutations: { string },
	biomeId: string,
	special: boolean, -- 초기화 특별 알이었나 (빛남 연출용)
	progress: number, -- 지금까지 자란 시간(초) — 우리에서 다시 주운 알은 그대로 남음
	required: number, -- 다 자라는 데 필요한 시간(초) = 원본 부화 시간 그대로 (2판 수정: ÷3 없앰)
}

-- 우리에 놓여 자라는 알 1개 (저장됨)
export type IncubatorRecord = {
	uid: string,
	petId: string,
	size: string,
	mutations: { string },
	biomeId: string,
	special: boolean,
	-- 2판 수정: 놓은 자리 = 베이스 기준(로컬) 좌표 (MapLayout.toWorld(plotIndex, x, z) → 월드). 슬롯 번호 없음
	x: number,
	z: number,
	slot: number?, -- [2판 수정 전 부화 슬롯 번호 — 서버는 이제 안 씀(nil). 클라 IncubatorController 교체 후 지움]
	progress: number, -- 지금까지 자란 시간(초)
	required: number, -- 다 자라는 데 필요한 시간(초) = 원본 부화 시간 그대로 (2판 수정: ÷3 없앰)
}

-- DataStore 에 저장되는 플레이어 데이터 (스키마 버전 4)
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
	incubators: { IncubatorRecord }, -- 우리에 놓인 알 (최대 Config.PLACED_EGG_MAX)
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
	-- 버전 3 (2판 마무리)
	equippedTrail: string, -- 장착한 트레일 id (trails 안에 있는 것만), "none" = 장착 안 함
	-- 버전 4 (2판 수정): 2단계 eggQueue(선물 알 대기 줄)는 없어지고 가방으로 합쳐짐
	eggs: { BagEgg }, -- 알 가방 (최대 Config.EGG_INVENTORY_MAX)
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
	equippedTrail: string, -- "none" = 장착 안 함
	trailMultiplier: number, -- 장착한 트레일 배율 (없으면 1)
	indexDiscovered: { [string]: boolean },
	indexClaimed: { [string]: boolean },
	indexCompleteClaimed: boolean,
	unlockedWeapons: { string },
	tools: { [string]: number },
	incubators: { IncubatorRecord }, -- 우리에 놓인 알 (x, z = 베이스 기준 좌표)
	eggs: { BagEgg }, -- 2판 수정: 알 가방
	eggInventoryMax: number, -- 가방 상한 (Config.EGG_INVENTORY_MAX)
	placedEggMax: number, -- 우리에 놓을 수 있는 알 수 (Config.PLACED_EGG_MAX)
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
