--!strict
--[[
	Tags — CollectionService 태그 이름과 Attribute 이름 (선임이 맵/UI 를 붙일 때 이 이름을 쓰세요)

	2판: 맵 배치(구역 z 범위·베이스 7개·둥지·경비 집·러닝머신 자리)는 shared/Data/MapLayout.luau 가 기준입니다.
	서버 로직은 구역·허브·베이스·배달·러닝머신 판정을 MapLayout 숫자로 하고, 아래 태그 파트는
	"보이는 것"(바닥·둥지·표지판·밤 벽)과 일부 위치(둥지 높이, 스폰 높이)에만 씁니다.

	6판 "씨앗을 훔치세요": 이름은 5판 그대로 (Egg = 씨앗, PenArea = 정원 바닥, Money = 코인).
	  + GardenPlant (정원의 성체 식물 자리 파트), IncubatingEgg 에 Attr Stage.
	  없앰: FusionMachine(퓨전 머신), Altar·Shrine(제단·비밀 통로), Attr IncomePerSecond(자동 수입)·SakuraUnlocked(해금)
]]

local Tags = {
	-- 구역 (판정은 MapLayout.zoneAt(z). 태그 파트는 겉모습용)
	Zone = "Zone", -- 구역 바닥. Attr: BiomeId, Order, RecommendedSpeed
	ZoneSign = "ZoneSign", -- 구역 표지판. Attr: BiomeId
	Nest = "Nest", -- 둥지(씨앗 주머니) (MapLayout.nestsFor 자리). Attr: BiomeId, NestIndex(1~8) — 서버가 씨앗을 이 파트 위에 놓음
	ParentAnimalSpot = "ParentAnimalSpot", -- 둥지 옆 장식 자리. Attr: BiomeId, NestIndex
	GuardSpawn = "GuardSpawn", -- [2판: 서버는 안 읽음 — 경비 집 = MapLayout.guardHome] Attr: BiomeId
	NightWall = "NightWall", -- 밤에 켜지는 벽 (2판: 허브 경계 z = 0 에 1장, MapLayout.NIGHT_WALL)
	Guardian = "Guardian", -- 경비(식물 괴물) NPC 모델 (서버가 만듦). Attr: BiomeId, GuardName, State, TargetUserId

	-- 베이스 (판정은 MapLayout.plots: rect/penRect/yardRect/treadmill ...)
	Plot = "Plot", -- 베이스 바닥. Attr: PlotIndex, OwnerUserId(0 = 빈 칸)
	PlotSpawn = "PlotSpawn", -- 베이스 스폰 위치 (MapLayout plot.spawn). Attr: PlotIndex
	PlotSign = "PlotSign", -- 주인 이름 표지판. Attr: PlotIndex
	DeliveryPad = "DeliveryPad", -- [1판 — 2판 서버는 안 씀(배달 = 베이스 영역 진입). 선임 맵·클라 교체 후 삭제]
	IncubatorSlot = "IncubatorSlot", -- [2판 수정: 부화 슬롯 없앰 — 씨앗은 정원 아무 데나(PlaceEgg). 선임 받침 지우면 삭제] Attr: PlotIndex, SlotIndex
	PenArea = "PenArea", -- 정원 바닥 (5판 우리). MapLayout penRect. Attr: PlotIndex
	Treadmill = "Treadmill", -- 러닝머신 벨트 (MapLayout plot.treadmill 중심, TREADMILL_PAD 크기, 윗면은 바닥 + 2 이하). Attr: PlotIndex
	IndexBoard = "IndexBoard", -- 도감 보드 자리(빈 파트). Attr: PlotIndex
	TrailShop = "TrailShop", -- 트레일 상점 (2판: 허브 MapLayout.hubSpots.trailShop)
	SellStall = "SellStall", -- 판매 가판대 (허브 hubSpots.sellStall / 베이스 plot.sellStall). SELL_RADIUS 안에서 SellFruits

	-- 구역 특수 장소. 자리는 MapLayout.specials. 맵에 없으면 서버가 그 자리에 임시 파트를 만듦 (Util/Landmarks)
	SakuraIncubator = "SakuraIncubator", -- 벚꽃 구역 사쿠라 나무 (6판 씨앗 버전: 성체 바치기 · 특별 씨앗 뽑기)
	-- (5판: 마법의 숲 퀘스트 문 QuestGate 없앰 · 6판: 천사&악마 제단 Altar·비밀 통로 Shrine 없앰)

	-- 동적 오브젝트 (서버가 만듦)
	Egg = "Egg", -- 둥지/바닥/머리 위 씨앗. Attr: EggUid, PetId(식물 id), BiomeId, Rarity, Size, Mutations, Special, EggState, WeightKg
	-- 정원에 심어 자라는 씨앗 (PlaceEgg 한 자리). Attr: EggUid, OwnerUserId, PlotIndex, PetId, Size, Mutations, Special,
	--   Progress, Required, Ready, Stage("sprout"|"stem"|"bud" — GardenRules.stage) · 다 자라면 지워지고 GardenPlant 가 생김
	IncubatingEgg = "IncubatingEgg",
	-- 6판: 정원의 성체 식물 (씨앗을 심었던 자리). Attr: PlantUid, OwnerUserId, PlotIndex, PetId, Size, Mutations, Stage("adult"),
	--   Fruits(달린 열매), FruitMax, FruitValue(1개 값), FruitInterval(초), FruitProgress(초) → 선임이 식물 모델·"열매 따기" 프롬프트
	GardenPlant = "GardenPlant",
	BearTrap = "BearTrap", -- 설치된 곰덫. Attr: OwnerUserId
	SakuraCrystal = "SakuraCrystal", -- 초기화 때 벚꽃 둥지 근처에 떨어지는 크리스탈 (ProximityPrompt "CrystalPrompt" 로 줍기)

	SpawnLocation = "MainSpawn", -- 허브 기본 스폰 (MapLayout.hubSpots.mainSpawn)
}

-- 플레이어 Attribute (player:GetAttribute) — 서버만 씀, 클라는 읽기만
Tags.PlayerAttributes = {
	Money = "Money", -- 6판: 코인
	Speed = "Speed", -- 실효 속도 (모은 속도 × 트레일)
	BaseSpeed = "BaseSpeed", -- 모은 속도
	WalkSpeed = "WalkSpeed", -- 서버가 정한 WalkSpeed
	PlotIndex = "PlotIndex",
	PenLevel = "PenLevel", -- 정원 레벨
	PenSlots = "PenSlots", -- 정원 칸 수
	TreadmillLevel = "TreadmillLevel",
	TrailMultiplier = "TrailMultiplier", -- 장착한 트레일 배율 (없으면 1)
	EquippedTrail = "EquippedTrail", -- 장착한 트레일 id ("none" = 없음) — 다른 사람 캐릭터 트레일 꾸밀 때
	CarryingEgg = "CarryingEgg", -- 든 씨앗 uid ("" = 없음)
	CarryingBiome = "CarryingBiome",
	Stunned = "Stunned", -- 래그돌/곰덫 중
	InSafeZone = "InSafeZone", -- 2판: 허브(z < 0) 안
	DataLoaded = "DataLoaded",
	SaveEnabled = "SaveEnabled",
	-- 2단계
	SakuraCrystals = "SakuraCrystals", -- 사쿠라 크리스탈 개수
	MoveWarnings = "MoveWarnings", -- 비정상 이동 경고 수 (저장 안 함, 5 = Kick)
	-- 2판
	OnTreadmill = "OnTreadmill", -- 러닝머신 위에 고정돼 달리는 중 (bool)
	CurrentZone = "CurrentZone", -- 지금 있는 곳: 구역 id | "hub" | "" (맵 밖)
	CarryWeightKg = "CarryWeightKg", -- 들고 있는 씨앗 무게(kg, 표시용). 0 = 안 듦
	-- 6판
	FruitCount = "FruitCount", -- 열매 가방 속 열매 수 (HUD 배지)
	FruitBagValue = "FruitBagValue", -- 열매 가방을 다 팔면 받는 코인 (판매 가판대 미리보기)
}

-- ReplicatedStorage.GameState 폴더 Attribute
Tags.StateFolderName = "GameState"
Tags.StateAttributes = {
	Phase = "Phase", -- "Day" | "Night" | "Intermission"
	PhaseEndsAt = "PhaseEndsAt", -- workspace:GetServerTimeNow() 기준 끝나는 시각
	PhaseDuration = "PhaseDuration",
	CycleNumber = "CycleNumber",
	HeavenSide = "HeavenSide", -- 천사&악마 이번 주기 쪽 "light" | "dark" (둥지 씨앗 풀이 바뀜)
}

return Tags
