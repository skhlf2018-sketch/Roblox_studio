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

	-- 동적 오브젝트 (서버가 만듦)
	Egg = "Egg", -- 둥지/바닥/머리 위 알. Attr: EggUid, PetId, BiomeId, Rarity, Size, Mutations, Special, EggState
	IncubatingEgg = "IncubatingEgg", -- 부화 슬롯 위 알. Attr: EggUid, OwnerUserId, PetId, Progress, Required, Ready
	BearTrap = "BearTrap", -- 설치된 곰덫. Attr: OwnerUserId

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
