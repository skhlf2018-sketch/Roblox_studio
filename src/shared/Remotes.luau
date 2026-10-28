--!strict
--[[
	Remotes — Remote 이름과 레이트 리밋을 한 곳에서 정의 (순수 데이터)

	- 서버(src/server/Net.luau)가 ReplicatedStorage.Remotes 폴더에 RemoteEvent 를 전부 만듭니다.
	- 클라(src/client/Net.luau)는 WaitForChild 로 받아 씁니다.
	- 자세한 인자 설명은 docs/REMOTES.md

	치트 방지 원칙: 코인/속도/식물을 직접 바꾸는 Remote 는 없습니다.
	클라는 "요청"만 보내고, 서버가 전부 검증합니다.

	6판 "씨앗을 훔치세요" (이름은 5판 그대로 둔 것이 많음: Egg = 씨앗, Pet = 성체 식물):
	  없앤 것 — 서버→클라: HatchResult(→ PlantGrown), OfflineIncome, FusionResult, AltarUpdate, ShrineResult, PetsSold, IncomeTick
	            클라→서버: HatchEgg(성체는 저절로), EquipPet, UnequipPet, EquipBest(장착 없음), FuseRequest, AltarOffer,
	                       ShrineFuse, SakuraApply(→ SakuraDraw), SellPet(→ SellPlant)
	  새것 — 서버→클라: PlantGrown, FruitPicked, FruitsSold, FeedResult
	         클라→서버: PickFruit, SellFruits, FeedFruit, SkipGrowth, SellPlant, SakuraDraw
]]

local Remotes = {
	FOLDER_NAME = "Remotes",

	-- 서버 → 클라
	ToClient = {
		Snapshot = "Snapshot",
		DataUpdate = "DataUpdate",
		Notify = "Notify",
		Announce = "Announce",
		PhaseChanged = "PhaseChanged",
		RunAlert = "RunAlert",
		ChaseEnded = "ChaseEnded",
		Caught = "Caught",
		EggDelivered = "EggDelivered", -- 씨앗을 들고 허브에 들어와 가방에 들어감 (BagEgg)
		IndexRewarded = "IndexRewarded",
		EggGranted = "EggGranted", -- 선물 씨앗 (사쿠라 나무 뽑기·개발 명령)이 가방에 들어감
		SakuraResult = "SakuraResult",
		-- 2판
		ZoneEntered = "ZoneEntered", -- { biomeId, name, nameEn } 새 구역(z 범위)에 들어갈 때 1회
		TreadmillStep = "TreadmillStep", -- { amount } 러닝머신 걸음(1초)마다 오른 속도
		-- 5판
		TutorialUpdate = "TutorialUpdate", -- TutorialView { step, total, text, hint, done, reward? } 튜토리얼 단계가 바뀔 때 (나에게만)
		LeaderboardUpdate = "LeaderboardUpdate", -- { money = { {name, value, userId} }, speed = {...} } 10초마다 서버 전체 (상위 10명)
		-- 6판
		PlantGrown = "PlantGrown", -- { plant: PetRecord, isNew, fruitValue, fruitInterval } 심은 씨앗이 그 자리에서 성체가 됨
		FruitPicked = "FruitPicked", -- { plantUid, petId, count, value } 열매를 따서 가방에 넣음 (식물마다 1번, "all" 이면 여러 번)
		FruitsSold = "FruitsSold", -- { count, coins } 판매 가판대에서 열매를 팜
		FeedResult = "FeedResult", -- { plantUid, fruitId, mutation: string? } 열매 먹이기 결과 (nil = 아무것도 안 붙음)
	},

	-- 클라 → 서버 (전부 서버에서 인자 검증 + 레이트 리밋)
	ToServer = {
		RequestSnapshot = "RequestSnapshot",
		PurchaseUpgrade = "PurchaseUpgrade",
		UseTool = "UseTool",
		ClaimIndexReward = "ClaimIndexReward",
		SakuraOffer = "SakuraOffer", -- (plantUid) 6판: 정원의 성체 1그루를 바쳐 크리스탈
		-- 2판
		DropEgg = "DropEgg", -- () 들고 있는 씨앗을 그 자리에 떨어뜨림 (추격 끝)
		TreadmillLeave = "TreadmillLeave", -- () 러닝머신에서 내림 (클라가 점프할 때)
		EquipTrail = "EquipTrail", -- (trailId | "none") 가진 트레일 장착 / "none" 이면 해제
		PlaceEgg = "PlaceEgg", -- (eggUid, x, z) 가방의 씨앗을 내 정원 안 그 자리(월드 x, z)에 심음 → 자라기 시작
		PickUpPlacedEgg = "PickUpPlacedEgg", -- (eggUid) 정원에 심은(아직 자라는) 씨앗을 다시 가방으로 (자란 만큼 유지)
		-- 5판
		-- 6판
		PickFruit = "PickFruit", -- (plantUid | "all") 내 정원 성체의 열매를 전부 따서 열매 가방으로
		SellFruits = "SellFruits", -- () 판매 가판대 근처에서 열매 가방을 전부 팔기 → 코인
		FeedFruit = "FeedFruit", -- (plantUid, fruitId) 가방의 열매(식물 id) 1개를 성체에게 먹임 → 확률로 돌연변이
		SkipGrowth = "SkipGrowth", -- (eggUid, "all" | "half") 코인으로 자라는 씨앗의 남은 시간 전부/절반 건너뛰기
		SellPlant = "SellPlant", -- (plantUid) 성체를 뽑아서 팔기 (열매 값 × 20 코인) → 정원 자리가 빔
		SakuraDraw = "SakuraDraw", -- () 사쿠라 나무 근처에서 크리스탈로 특별 씨앗 뽑기 → 씨앗 가방
	},

	-- 클라 → 서버 레이트 리밋: burst = 한 번에 허용, perSecond = 초당 회복
	RateLimits = {
		RequestSnapshot = { burst = 3, perSecond = 0.5 },
		PurchaseUpgrade = { burst = 5, perSecond = 2 },
		UseTool = { burst = 4, perSecond = 2 },
		ClaimIndexReward = { burst = 5, perSecond = 1 },
		SakuraOffer = { burst = 3, perSecond = 1 },
		DropEgg = { burst = 2, perSecond = 1 },
		TreadmillLeave = { burst = 3, perSecond = 2 },
		EquipTrail = { burst = 5, perSecond = 2 },
		PlaceEgg = { burst = 5, perSecond = 3 },
		PickUpPlacedEgg = { burst = 5, perSecond = 3 },
		PickFruit = { burst = 10, perSecond = 5 },
		SellFruits = { burst = 3, perSecond = 1 },
		FeedFruit = { burst = 5, perSecond = 2 },
		SkipGrowth = { burst = 5, perSecond = 2 },
		SellPlant = { burst = 10, perSecond = 4 },
		SakuraDraw = { burst = 5, perSecond = 2 },
	} :: { [string]: { burst: number, perSecond: number } },

	-- PurchaseUpgrade 의 kind ("Pen" = 6판 정원 업그레이드)
	UpgradeKinds = { Pen = "Pen", Treadmill = "Treadmill", Trail = "Trail" } :: { [string]: string },

	-- SkipGrowth 의 mode
	SkipModes = { all = "all", half = "half" } :: { [string]: string },

	-- UseTool 의 kind = 서버가 Backpack 에 넣어 주는 Tool 이름
	--   Bat(기본 야구 방망이), BearTrap(곰덫), 나머지는 구역 도감 완성 무기 (shared/Data/Weapons.luau 의 toolKind)
	ToolKinds = {
		Bat = "Bat",
		BearTrap = "BearTrap",
		WaterBat = "WaterBat",
		Katana = "Katana",
		Axe = "Axe",
		AngelSpear = "AngelSpear",
		Hammer = "Hammer",
		CandyCane = "CandyCane",
		Scythe = "Scythe",
	} :: { [string]: string },
}

return Remotes
