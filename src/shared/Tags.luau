--!strict
--[[
	Tags — CollectionService 태그 이름과 Attribute 이름 (선임이 맵/UI 를 붙일 때 이 이름을 쓰세요)

	맵 파트는 MapBuilder 가 임시로 만들지만, Workspace.Map 을 선임이 직접 만들어 두면
	MapBuilder 는 새로 만들지 않고 아래 태그가 붙은 파트를 그대로 씁니다.
]]

local Tags = {
	-- 구역
	Zone = "Zone", -- 구역 바닥(축 정렬 직사각형). Attr: BiomeId, Order, RecommendedSpeed
	ZoneSign = "ZoneSign", -- 입구 표지판. Attr: BiomeId
	Nest = "Nest", -- 둥지. Attr: BiomeId, NestIndex(1~8)
	ParentAnimalSpot = "ParentAnimalSpot", -- 둥지 옆 부모 동물 자리. Attr: BiomeId, NestIndex
	GuardSpawn = "GuardSpawn", -- 경비 집 위치. Attr: BiomeId
	NightWall = "NightWall", -- 밤에 켜지는 입구 벽. Attr: BiomeId
	Guardian = "Guardian", -- 경비 NPC 모델 (서버가 만듦). Attr: BiomeId, GuardName, State, TargetUserId

	-- 베이스
	Plot = "Plot", -- 베이스 바닥. Attr: PlotIndex, OwnerUserId(0 = 빈 칸)
	PlotSpawn = "PlotSpawn", -- 베이스 스폰 위치. Attr: PlotIndex
	PlotSign = "PlotSign", -- 주인 이름 표지판. Attr: PlotIndex
	DeliveryPad = "DeliveryPad", -- 배달 패드. Attr: PlotIndex
	IncubatorSlot = "IncubatorSlot", -- 부화 슬롯 자리. Attr: PlotIndex, SlotIndex
	PenArea = "PenArea", -- 우리(펫 진열) 자리. Attr: PlotIndex
	Treadmill = "Treadmill", -- 러닝머신 패드. Attr: PlotIndex
	FusionMachine = "FusionMachine", -- 퓨전 머신 자리(빈 파트). Attr: PlotIndex
	IndexBoard = "IndexBoard", -- 도감 보드 자리(빈 파트). Attr: PlotIndex
	TrailShop = "TrailShop", -- 트레일 상점 자리(빈 파트). Attr: PlotIndex

	-- 구역 특수 장소 (2단계). 맵에 없으면 서버가 구역 안에 임시 파트를 만들어 둠 (Util/Landmarks)
	--   선임이 같은 태그·Attribute 로 진짜 모델 파트를 두면 임시 파트는 안 만들어짐.
	SakuraIncubator = "SakuraIncubator", -- 벚꽃 구역 사쿠라 인큐베이터. Attr: Unlocked 는 플레이어 Attr SakuraUnlocked 참고
	Altar = "Altar", -- 천사&악마 제단 2개. Attr: Side ("light" = 천국 / "dark" = 지옥), PendingCount(대기 중인 제물 수)
	Shrine = "Shrine", -- 천사&악마 비밀 통로(폭포 옆) 합성 제단
	QuestGate = "QuestGate", -- 마법의 숲 퀘스트 문 (퀘스트 3개 끝낸 사람만 통과: CollisionGroup "QuestGate")

	-- 동적 오브젝트 (서버가 만듦)
	Egg = "Egg", -- 둥지/바닥/머리 위 알. Attr: EggUid, PetId, BiomeId, Rarity, Size, Mutations, Special, EggState, QuestOnly
	IncubatingEgg = "IncubatingEgg", -- 부화 슬롯 위 알. Attr: EggUid, OwnerUserId, PetId, Progress, Required, Ready, Mutations
	BearTrap = "BearTrap", -- 설치된 곰덫. Attr: OwnerUserId
	SakuraCrystal = "SakuraCrystal", -- 초기화 때 벚꽃 둥지 근처에 떨어지는 크리스탈 (ProximityPrompt "CrystalPrompt" 로 줍기)

	SpawnLocation = "MainSpawn",
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
	InSafeZone = "InSafeZone",
	DataLoaded = "DataLoaded",
	SaveEnabled = "SaveEnabled",
	-- 2단계
	SakuraCrystals = "SakuraCrystals", -- 사쿠라 크리스탈 개수
	SakuraUnlocked = "SakuraUnlocked", -- 사쿠라 인큐베이터 해금했나
	QuestsDone = "QuestsDone", -- 마법의 숲 퀘스트 3개 완료 (문 통과 가능)
	MoveWarnings = "MoveWarnings", -- 비정상 이동 경고 수 (저장 안 함, 5 = Kick)
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
