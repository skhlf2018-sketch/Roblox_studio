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
	} :: { [string]: { burst: number, perSecond: number } },

	-- PurchaseUpgrade 의 kind
	UpgradeKinds = { Pen = "Pen", Treadmill = "Treadmill", Trail = "Trail" },

	-- UseTool 의 kind
	ToolKinds = { Bat = "Bat", BearTrap = "BearTrap" },
}

return Remotes
