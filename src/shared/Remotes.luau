--!strict
--[[
	Remotes — Remote 이름과 레이트 리밋을 한 곳에서 정의 (순수 데이터)

	- 서버(src/server/Net.luau)가 ReplicatedStorage.Remotes 폴더에 RemoteEvent 를 전부 만듭니다.
	- 클라(src/client/Net.luau)는 WaitForChild 로 받아 씁니다.
	- 자세한 인자 설명은 docs/REMOTES.md

	치트 방지 원칙: 돈/속도/펫을 직접 바꾸는 Remote 는 없습니다.
	클라는 "요청"만 보내고, 서버가 전부 검증합니다.
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
		EggDelivered = "EggDelivered",
		HatchResult = "HatchResult",
		OfflineIncome = "OfflineIncome",
		IndexRewarded = "IndexRewarded",
		-- 2단계
		FusionResult = "FusionResult",
		EggGranted = "EggGranted",
		SakuraResult = "SakuraResult",
		AltarUpdate = "AltarUpdate",
		ShrineResult = "ShrineResult",
		QuestUpdate = "QuestUpdate",
		PetsSold = "PetsSold",
		-- 2판
		ZoneEntered = "ZoneEntered", -- { biomeId, name, nameEn } 새 구역(z 범위)에 들어갈 때 1회
		IncomeTick = "IncomeTick", -- { petUid, amount } 장착 펫마다 INCOME_POPUP_INTERVAL(3)초에 1번, 그만큼의 돈 (팝업용)
		TreadmillStep = "TreadmillStep", -- { amount } 러닝머신 걸음(1초)마다 오른 속도
	},

	-- 클라 → 서버 (전부 서버에서 인자 검증 + 레이트 리밋)
	ToServer = {
		RequestSnapshot = "RequestSnapshot",
		HatchEgg = "HatchEgg",
		EquipPet = "EquipPet",
		UnequipPet = "UnequipPet",
		EquipBest = "EquipBest",
		PurchaseUpgrade = "PurchaseUpgrade",
		UseTool = "UseTool",
		ClaimIndexReward = "ClaimIndexReward",
		ClaimFreeReward = "ClaimFreeReward",
		-- 2단계
		FuseRequest = "FuseRequest",
		SakuraOffer = "SakuraOffer",
		SakuraApply = "SakuraApply",
		AltarOffer = "AltarOffer",
		ShrineFuse = "ShrineFuse",
		-- 2판
		DropEgg = "DropEgg", -- () 들고 있는 알을 그 자리에 떨어뜨림 (추격 끝)
		SellPet = "SellPet", -- (petUid) 판매 가게 근처에서 펫 팔기
		TreadmillLeave = "TreadmillLeave", -- () 러닝머신에서 내림 (클라가 점프할 때)
		EquipTrail = "EquipTrail", -- (trailId | "none") 가진 트레일 장착 / "none" 이면 해제
	},

	-- 클라 → 서버 레이트 리밋: burst = 한 번에 허용, perSecond = 초당 회복
	RateLimits = {
		RequestSnapshot = { burst = 3, perSecond = 0.5 },
		HatchEgg = { burst = 10, perSecond = 4 },
		EquipPet = { burst = 10, perSecond = 5 },
		UnequipPet = { burst = 10, perSecond = 5 },
		EquipBest = { burst = 2, perSecond = 0.5 },
		PurchaseUpgrade = { burst = 5, perSecond = 2 },
		UseTool = { burst = 4, perSecond = 2 },
		ClaimIndexReward = { burst = 5, perSecond = 1 },
		ClaimFreeReward = { burst = 2, perSecond = 0.2 },
		FuseRequest = { burst = 3, perSecond = 1 },
		SakuraOffer = { burst = 2, perSecond = 0.5 },
		SakuraApply = { burst = 5, perSecond = 2 },
		AltarOffer = { burst = 3, perSecond = 1 },
		ShrineFuse = { burst = 2, perSecond = 0.5 },
		DropEgg = { burst = 2, perSecond = 1 },
		SellPet = { burst = 10, perSecond = 4 },
		TreadmillLeave = { burst = 3, perSecond = 2 },
		EquipTrail = { burst = 5, perSecond = 2 },
	} :: { [string]: { burst: number, perSecond: number } },

	-- PurchaseUpgrade 의 kind
	UpgradeKinds = { Pen = "Pen", Treadmill = "Treadmill", Trail = "Trail" } :: { [string]: string },

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
