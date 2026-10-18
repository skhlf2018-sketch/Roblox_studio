--!strict
--[[
	Tags — CollectionService 태그 이름과 Attribute 이름 (선임이 맵/UI 를 붙일 때 이 이름을 쓰세요)

	2판: 맵 배치(구역 z 범위·베이스 7개·둥지·경비 집·러닝머신 자리)는 shared/Data/MapLayout.luau 가 기준입니다.
	서버 로직은 구역·허브·베이스·배달·러닝머신 판정을 MapLayout 숫자로 하고, 아래 태그 파트는
	"보이는 것"(바닥·둥지·표지판·밤 벽)과 일부 위치(둥지 높이, 스폰 높이)에만 씁니다.
]]

local Tags = {
	-- 구역 (판정은 MapLayout.zoneAt(z). 태그 파트는 겉모습용)
	Zone = "Zone", -- 구역 바닥. Attr: BiomeId, Order, RecommendedSpeed
	ZoneSign = "ZoneSign", -- 구역 표지판. Attr: BiomeId
	Nest = "Nest", -- 둥지 (MapLayout.nestsFor 자리). Attr: BiomeId, NestIndex(1~8) — 서버가 알을 이 파트 위에 놓음
	ParentAnimalSpot = "ParentAnimalSpot", -- 둥지 옆 부모 동물 자리. Attr: BiomeId, NestIndex
	GuardSpawn = "GuardSpawn", -- [2판: 서버는 안 읽음 — 경비 집 = MapLayout.guardHome] Attr: BiomeId
	NightWall = "NightWall", -- 밤에 켜지는 벽 (2판: 허브 경계 z = 0 에 1장, MapLayout.NIGHT_WALL)
	Guardian = "Guardian", -- 경비 NPC 모델 (서버가 만듦). Attr: BiomeId, GuardName, State, TargetUserId

	-- 베이스 (판정은 MapLayout.plots: rect/penRect/yardRect/treadmill ...)
	Plot = "Plot", -- 베이스 바닥. Attr: PlotIndex, OwnerUserId(0 = 빈 칸)
	PlotSpawn = "PlotSpawn", -- 베이스 스폰 위치 (MapLayout plot.spawn). Attr: PlotIndex
	PlotSign = "PlotSign", -- 주인 이름 표지판. Attr: PlotIndex
	DeliveryPad = "DeliveryPad", -- [1판 — 2판 서버는 안 씀(배달 = 베이스 영역 진입). 선임 맵·클라 교체 후 삭제]
	IncubatorSlot = "IncubatorSlot", -- (선택) 부화 알 받침. MapLayout.incubatorSpots 자리. Attr: PlotIndex, SlotIndex
	PenArea = "PenArea", -- 우리(펫 진열) 바닥. MapLayout penRect. Attr: PlotIndex
	Treadmill = "Treadmill", -- 러닝머신 벨트 (MapLayout plot.treadmill 중심, TREADMILL_PAD 크기, 윗면은 바닥 + 2 이하). Attr: PlotIndex
	FusionMachine = "FusionMachine", -- 퓨전 머신 (MapLayout plot.fusion). Attr: PlotIndex
	IndexBoard = "IndexBoard", -- 도감 보드 자리(빈 파트). Attr: PlotIndex
	TrailShop = "TrailShop", -- 트레일 상점 (2판: 허브 MapLayout.hubSpots.trailShop)
	SellStall = "SellStall", -- 2판: 판매 가게 (허브 hubSpots.sellStall / 베이스 plot.sellStall). SELL_RADIUS 안에서 SellPet

	-- 구역 특수 장소 (2단계). 자리는 MapLayout.specials. 맵에 없으면 서버가 그 자리에 임시 파트를 만듦 (Util/Landmarks)
	SakuraIncubator = "SakuraIncubator", -- 벚꽃 구역 사쿠라 인큐베이터
	Altar = "Altar", -- 천사&악마 제단 2개. Attr: Side ("light" = 천국 / "dark" = 지옥), PendingCount(대기 중인 제물 수)
	Shrine = "Shrine", -- 천사&악마 비밀 통로(폭포 옆) 합성 제단
	QuestGate = "QuestGate", -- 마법의 숲 퀘스트 문 (퀘스트 3개 끝낸 사람만 통과: CollisionGroup "QuestGate")

	-- 동적 오브젝트 (서버가 만듦)
	Egg = "Egg", -- 둥지/바닥/머리 위 알. Attr: EggUid, PetId, BiomeId, Rarity, Size, Mutations, Special, EggState, QuestOnly, WeightKg
	IncubatingEgg = "IncubatingEgg", -- 우리 안 부화 중 알. Attr: EggUid, OwnerUserId, PetId, SlotIndex, Progress, Required, Ready, Mutations
	BearTrap = "BearTrap", -- 설치된 곰덫. Attr: OwnerUserId
	SakuraCrystal = "SakuraCrystal", -- 초기화 때 벚꽃 둥지 근처에 떨어지는 크리스탈 (ProximityPrompt "CrystalPrompt" 로 줍기)

	SpawnLocation = "MainSpawn", -- 허브 기본 스폰 (MapLayout.hubSpots.mainSpawn)
}

-- 플레이어 Attribute (player:GetAttribute) — 서버만 씀, 클라는 읽기만
Tags.PlayerAttributes = {
	Money = "Money",
	Speed = "Speed", -- 실효 속도 (모은 속도 × 트레일)
	BaseSpeed = "BaseSpeed", -- 모은 속도
	WalkSpeed = "WalkSpeed", -- 서버가 정한 WalkSpeed
	IncomePerSecond = "IncomePerSecond",
	PlotIndex = "PlotIndex",
	PenLevel = "PenLevel",
	PenSlots = "PenSlots",
	TreadmillLevel = "TreadmillLevel",
	TrailMultiplier = "TrailMultiplier",
	CarryingEgg = "CarryingEgg", -- 든 알 uid ("" = 없음)
	CarryingBiome = "CarryingBiome",
	Stunned = "Stunned", -- 래그돌/곰덫 중
	InSafeZone = "InSafeZone", -- 2판: 허브(z < 0) 안
	DataLoaded = "DataLoaded",
	SaveEnabled = "SaveEnabled",
	-- 2단계
	SakuraCrystals = "SakuraCrystals", -- 사쿠라 크리스탈 개수
	SakuraUnlocked = "SakuraUnlocked", -- 사쿠라 인큐베이터 해금했나
	QuestsDone = "QuestsDone", -- 마법의 숲 퀘스트 3개 완료 (문 통과 가능)
	MoveWarnings = "MoveWarnings", -- 비정상 이동 경고 수 (저장 안 함, 5 = Kick)
	-- 2판
	OnTreadmill = "OnTreadmill", -- 러닝머신 위에 고정돼 달리는 중 (bool)
	CurrentZone = "CurrentZone", -- 지금 있는 곳: 구역 id | "hub" | "" (맵 밖)
	CarryWeightKg = "CarryWeightKg", -- 들고 있는 알 무게(kg, 표시용). 0 = 안 듦
}

-- 서버가 만드는 CollisionGroup 이름 (QuestService)
Tags.CollisionGroups = {
	QuestGate = "QuestGate", -- 퀘스트 문 파트
	QuestPassed = "QuestPassed", -- 퀘스트 끝낸 플레이어 캐릭터 → 문과 안 부딪힘
}

-- ReplicatedStorage.GameState 폴더 Attribute
Tags.StateFolderName = "GameState"
Tags.StateAttributes = {
	Phase = "Phase", -- "Day" | "Night" | "Intermission"
	PhaseEndsAt = "PhaseEndsAt", -- workspace:GetServerTimeNow() 기준 끝나는 시각
	PhaseDuration = "PhaseDuration",
	CycleNumber = "CycleNumber",
	HeavenSide = "HeavenSide", -- 천사&악마 이번 주기 쪽 "light" | "dark"
}

return Tags
