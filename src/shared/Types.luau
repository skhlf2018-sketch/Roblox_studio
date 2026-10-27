--!strict
--[[
	Types — 서버/클라가 같이 쓰는 타입 (저장 데이터 모양, Remote 로 오가는 데이터 모양)

	6판 "씨앗을 훔치세요" 용어 (칸 이름은 5판 그대로 둔 곳이 많음 — 큰 이름 바꾸기는 위험해서):
	  petId = 식물 id (Data/Plants) · pets = 정원의 성체 식물 · incubators = 정원에 심어 자라는 씨앗 ·
	  eggs = 씨앗 가방 · fruits = 열매 가방 · money = 코인 · penLevel/penSlots = 정원 레벨/정원 칸 수
]]

export type Phase = "Day" | "Night" | "Intermission"

-- 정원에 심어진 성체 식물 1그루 (6판, 저장됨). 5판 "보관함 펫" 자리라 타입 이름은 PetRecord 그대로 (PlantRecord 별칭)
-- 씨앗이 다 자라면 그 자리(x, z)·uid 그대로 이 모양이 됨. 정원 칸을 차지함 (SellPlant 로 뽑아서 팔면 빔)
export type PetRecord = {
	uid: string,
	petId: string, -- 식물 id
	size: string,
	mutations: { string },
	x: number, -- 심은 자리 = 베이스 기준(로컬) 좌표 (MapLayout.toWorld(plotIndex, x, z) → 월드)
	z: number,
	fruits: number, -- 달려 있는 열매 수 (0 ~ Config.FRUIT_MAX_PER_PLANT)
	fruitProgress: number, -- 다음 열매까지 쌓인 초 (0 ~ fruitIntervalSeconds)
}
export type PlantRecord = PetRecord

-- 가방에 있는 씨앗 1개 (저장됨): 허브에 들고 들어온 씨앗 · 선물 씨앗(사쿠라 나무 뽑기·개발 명령 /seed) · 정원에서 다시 주운 씨앗.
-- 가방 속 씨앗은 자라지 않음 (progress 그대로). PlaceEgg 로 정원에 심으면 같은 uid 로 IncubatorRecord 가 됨
export type BagEgg = {
	uid: string,
	petId: string, -- 식물 id
	size: string,
	mutations: { string },
	biomeId: string,
	special: boolean, -- 초기화 공지 씨앗이었나 (빛남 연출용)
	progress: number, -- 지금까지 자란 시간(초) — 정원에서 다시 주운 씨앗은 그대로 남음
	required: number, -- 성체까지 필요한 시간(초) = Data/Plants.growSeconds
}

-- 정원에 심어 자라는 씨앗 1개 (저장됨). 다 자라면(progress >= required) 그 자리에서 PetRecord(성체)가 됨
export type IncubatorRecord = {
	uid: string,
	petId: string, -- 식물 id
	size: string,
	mutations: { string },
	biomeId: string,
	special: boolean,
	-- 심은 자리 = 베이스 기준(로컬) 좌표 (MapLayout.toWorld(plotIndex, x, z) → 월드). 슬롯 번호 없음
	x: number,
	z: number,
	slot: number?, -- [2판 수정 전 부화 슬롯 번호 — 서버는 안 씀(nil). 클라 IncubatorController 교체 후 지움]
	progress: number, -- 지금까지 자란 시간(초) → 성장 단계 = GardenRules.stage(progress, required)
	required: number, -- 성체까지 필요한 시간(초)
}

-- 6판: 열매 가방의 한 칸 (같은 식물 열매끼리 묶음). 키 = 그 열매를 맺은 식물 id
export type FruitStack = {
	count: number, -- 열매 수
	value: number, -- 이 칸 열매 전부의 코인 값 합 (딸 때 크기·돌연변이까지 반영한 값을 더함)
}
export type FruitBag = { [string]: FruitStack }

-- DataStore 에 저장되는 플레이어 데이터 (스키마 버전 6)
export type PlayerData = {
	version: number,
	money: number, -- 코인
	speed: number, -- 모은 속도 (트레일 배율 적용 전)
	pets: { PetRecord }, -- 6판: 정원의 성체 식물 (자라는 씨앗 + 성체 ≤ 정원 칸 수)
	penLevel: number, -- 정원 레벨 (Upgrades.Pen)
	treadmillLevel: number, -- 0 = 잠김
	trails: { string }, -- 산 트레일 id 목록
	indexDiscovered: { [string]: boolean }, -- 도감 발견 (성체가 된 식물 id → true)
	indexClaimed: { [string]: boolean }, -- 도감 보상 수령 (식물 id → true)
	indexCompleteClaimed: boolean,
	tools: { [string]: number }, -- 소모 도구 개수 (bearTrap)
	incubators: { IncubatorRecord }, -- 정원에 심어 자라는 씨앗
	lastSaveTime: number, -- os.time()
	nextUid: number,
	stats: { [string]: number },
	weapons: { string }, -- 해금한 구역 무기 id (Data/Weapons, 기본 방망이 제외)
	sakuraCrystals: number, -- 사쿠라 크리스탈 개수
	equippedTrail: string, -- 장착한 트레일 id (trails 안에 있는 것만), "none" = 장착 안 함
	eggs: { BagEgg }, -- 씨앗 가방 (최대 Config.EGG_INVENTORY_MAX)
	tutorialStep: number, -- 튜토리얼 단계 1~5, 6(Data/Tutorial.DONE) = 끝남
	-- 버전 6 (6판)
	fruits: FruitBag, -- 열매 가방 (열매 합 최대 Config.FRUIT_BAG_MAX)
	-- (6판에서 없앤 칸: equipped(장착), sakuraUnlocked(인큐베이터 해금), shrineUsed(비밀 통로))
}

-- 씨앗 정보 (RunAlert, 공지 등에 쓰는 가벼운 모양)
export type EggInfo = {
	uid: string,
	petId: string, -- 식물 id
	biomeId: string,
	rarity: string,
	size: string,
	mutations: { string },
	special: boolean,
}

-- 튜토리얼 상황 (TutorialUpdate / Snapshot.tutorial / DataUpdate("tutorial")) — shared/TutorialRules.view
export type TutorialView = {
	step: number, -- 지금 단계 1 ~ total, 끝나면 total + 1
	total: number, -- 단계 수 (5)
	text: string, -- 큰 글씨 ("숲에서 씨앗 훔치기" ...)
	hint: string, -- 작은 설명 (끝나면 "")
	done: boolean,
	reward: number?, -- 끝내는 순간의 TutorialUpdate 에만: 받은 코인 (500)
}

-- 5판: 랭킹판 한 줄 (LeaderboardUpdate)
export type LeaderboardEntry = {
	name: string, -- 표시 이름 (DisplayName)
	value: number, -- 코인 또는 속도
	userId: number, -- 내 줄 강조·아바타 사진용
}

-- 5판: 랭킹판 (LeaderboardUpdate, 10초마다 서버 전체). 큰 값부터 최대 10줄
export type Leaderboard = {
	money: { LeaderboardEntry }, -- 코인
	speed: { LeaderboardEntry }, -- 실효 속도 (Attr Speed 와 같은 숫자)
}

-- 클라이언트로 보내는 전체 상태 (Snapshot)
export type Snapshot = {
	money: number, -- 코인
	speed: number,
	effectiveSpeed: number,
	pets: { PetRecord }, -- 6판: 정원의 성체 식물
	penLevel: number, -- 정원 레벨
	penSlots: number, -- 정원 칸 수 (자라는 씨앗 + 성체 식물이 이만큼까지)
	treadmillLevel: number,
	trails: { string },
	equippedTrail: string, -- "none" = 장착 안 함
	trailMultiplier: number, -- 장착한 트레일 배율 (없으면 1)
	indexDiscovered: { [string]: boolean },
	indexClaimed: { [string]: boolean },
	indexCompleteClaimed: boolean,
	unlockedWeapons: { string },
	tools: { [string]: number },
	incubators: { IncubatorRecord }, -- 정원에 심어 자라는 씨앗 (x, z = 베이스 기준 좌표)
	eggs: { BagEgg }, -- 씨앗 가방
	eggInventoryMax: number, -- 씨앗 가방 상한 (Config.EGG_INVENTORY_MAX)
	placedEggMax: number, -- [호환] = penSlots (5판 "우리에 놓을 수 있는 알 수" 칸 — 선임 정리 후 지움)
	fruits: FruitBag, -- 6판: 열매 가방
	fruitBagMax: number, -- 6판: 열매 가방 상한 (Config.FRUIT_BAG_MAX)
	plotIndex: number,
	saveEnabled: boolean,
	sakuraCrystals: number,
	tutorial: TutorialView,
	-- (6판에서 없앤 칸: incomePerSecond, equipped, sakuraUnlocked, shrineUsed, petInventoryMax)
}

return {}
