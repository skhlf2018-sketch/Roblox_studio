--!strict
--[[
	Tags — 송판 깨기 CollectionService 태그 · 파트 Attribute · 플레이어 Attribute 이름 (설계서 7장)

	판정(자리·거리)은 서버가 선임 shared/Data/MapLayout.luau 숫자로 합니다:
	  MapLayout.targetPosition(id) · targetReach(id) · isOnTrainMat(pos, world) · spawn(world) · examPad(world) · duelArena(world)
	아래 태그 파트는 "보이는 것"과 클릭/탭 받는 곳 (선임 MapBuilder 가 만듦).
]]

local Tags = {
	-- 물건 모델 (월드마다). Attr: TargetId (Targets 의 id), World. 클릭/탭(ClickDetector) 또는 화면 "치기" 버튼 → Hit(targetId)
	BreakTarget = "BreakTarget",
	-- 수련 매트 (도장). Attr: World. 그 위에서 화면을 누르거나 "들기" 버튼 → Train()
	TrainMat = "TrainMat",
	-- 승급 심사대. Attr: World → StartExam()
	ExamPad = "ExamPad",
	-- 시험관 대결장. Attr: World → StartDuel()
	DuelArena = "DuelArena",
	-- 아령 가게. Attr: World → 가게 창 → BuyDumbbell()
	DumbbellShop = "DumbbellShop",
	-- 띠 표지판 (띠 Belts.COUNT 개(지금 22)와 지금 내 띠). Attr: World
	BeltBoard = "BeltBoard",
	-- 월드 이동 문 (로비). Attr: World(문이 있는 월드), TargetWorld(가는 월드) → Travel(TargetWorld)
	WorldDoor = "WorldDoor",
	-- 월드 스폰 자리. Attr: World
	WorldSpawn = "WorldSpawn",
}

-- 맵 파트 Attribute 이름
Tags.PartAttributes = {
	TargetId = "TargetId",
	World = "World",
	TargetWorld = "TargetWorld",
}

-- 플레이어 Attribute (player:GetAttribute) — 서버만 씀, 클라는 읽기만
Tags.PlayerAttributes = {
	Power = "Power", -- 저장된 힘 (number)
	Money = "Money", -- 돈 (number)
	DumbbellLevel = "DumbbellLevel", -- 가진 가장 좋은 아령 (1~Dumbbells.COUNT)
	Belt = "Belt", -- 지금 띠 (1~Belts.COUNT, 지금 22)
	World = "World", -- 열린 월드 (1~3)
	CurrentWorld = "CurrentWorld", -- 지금 있는 월드 (1~3)
	PowerBoost = "PowerBoost", -- 힘 배수 (1, 2, 4 … 2048) — 들 때와 칠 때 둘 다 곱함
	MoneyPass = "MoneyPass", -- 돈 2배 게임패스 (bool)
	DataLoaded = "DataLoaded",
	SaveEnabled = "SaveEnabled",
	-- 수석 추가 (설계서 7장에 적음)
	Activity = "Activity", -- "" | "exam" | "duel" (지금 심사·대결 중인가)
	GrandMaster = "GrandMaster", -- 월드 3 마지막 시험관을 이김 (bool, 엔딩)
	-- 결정 13번 (Sizes): 서버 SizeService 가 정함, 겉모습은 PlayerVisualService 가 읽어서 키움
	BodyScale = "BodyScale", -- 몸 배율 1 … Sizes.MAX_SCALE (Sizes.quantize 로 내린 값)
	Muscle = "Muscle", -- 근육 0 … 1 (0.05 단위)
}

return Tags
