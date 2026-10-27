--!strict
--[[
	Config — 게임 전체 상수 (순수 데이터, 로블록스 API 없음 → Lune 테스트에서도 require 가능)

	[추정] 표시는 설계문서에 숫자가 없어서 수석이 정한 값입니다. 밸런스 조정은 여기 숫자만 바꾸면 됩니다.

	6판 "씨앗을 훔치세요" 용어 (코드 이름은 5판 그대로 둔 곳이 많음):
	  알(egg) → 씨앗 · 우리(pen) → 정원 · 부화(hatch) → 성체 되기 · 펫(pet) → 성체 식물 · 돈(money) → 코인
	  EGG_* = 씨앗, PEN = 정원, PET_PET_* = 물 주기, 저장 칸 pets = 정원의 성체 식물, incubators = 자라는 씨앗
	6판에서 없앤 것: GROWTH_MULTIPLIER(펫 수입 ×3 — 열매 값은 Data/Plants 숫자 그대로), 펫 보관함(PET_INVENTORY_MAX)·
	  자동 수입(INCOME_*)·오프라인 수입·펫 판매(PET_SELL_SECONDS)·퓨전(FUSION_*)·제단/비밀 통로(ALTAR_*, SHRINE_*)·
	  사쿠라 해금(SAKURA_UNLOCK_PET)·블룸(SAKURA_APPLY_COST)·우리에 놓는 알 상한(PLACED_EGG_MAX → 정원 칸 수 = 정원 업그레이드)
]]

local Config = {
	------------------------------------------------------------------
	-- 서버 / 베이스
	------------------------------------------------------------------
	MAX_PLAYERS = 7,
	PLOT_COUNT = 7,
	-- 씨앗 가방 / 정원에 심기 (5판 알 가방·우리에 놓기 그대로: 허브에 들고 들어오면 씨앗은 가방으로, 정원 안 원하는 자리에 심음)
	EGG_INVENTORY_MAX = 50, -- [추정] 가방에 넣어 둘 수 있는 씨앗 수 (가득 차면 배달·선물 씨앗을 못 받음)
	-- 정원 칸 수 = 정원 업그레이드(Upgrades.Pen) 칸 수 (7 → 18). 자라는 씨앗 + 성체 식물 합이 이 수까지 (Economy.penSlots)
	EGG_PLACE_SPACING = 4, -- 심는 씨앗 ↔ 다른 씨앗·성체 식물 최소 간격(스터드). 큰 씨앗끼리는 두 씨앗 지름 평균까지 늘어남
	EGG_PLACE_FENCE_MARGIN = 2, -- 씨앗 가운데가 정원 울타리에서 이만큼 안쪽이어야 함
	EGG_PLACE_RADIUS = 14, -- 내 베이스 밖에 서 있으면 심을 자리에서 이 거리 안이어야 PlaceEgg 가능
	ALLOW_EGG_PICKUP = true, -- PickUpPlacedEgg(심은 씨앗을 다시 가방으로, 자란 만큼 유지) 허용

	------------------------------------------------------------------
	-- 6판 정원: 성장 단계 · 열매 · 건너뛰기 · 성체 팔기 · 물 주기 (shared/GardenRules, shared/FruitRules)
	------------------------------------------------------------------
	-- 성장 단계: 자란 비율(progress / required)이 from 이상이면 그 단계. 100% = 성체 (그 자리에서 성체 식물이 됨)
	GROWTH_STAGES = {
		{ id = "sprout", name = "새싹", from = 0 },
		{ id = "stem", name = "줄기", from = 0.25 },
		{ id = "bud", name = "봉오리", from = 0.60 },
		{ id = "adult", name = "성체", from = 1 },
	} :: { { id: string, name: string, from: number } },
	PASSIVE_INCOME_PER_SECOND = 0, -- 6판(사장님 결정 1): 자동 수입 없음 — 코인은 열매를 따서 팔아야 들어옴
	FRUIT_MAX_PER_PLANT = 5, -- 안 따면 식물마다 열매가 이만큼까지만 쌓임 (설계 7장 결정 1)
	FRUITS_ON_ADULT = 1, -- [수석] 성체가 되는 순간 달려 있는 열매 (튜토리얼 5단계 "열매 따서 팔기" 를 바로 할 수 있게)
	FRUIT_BAG_MAX = 300, -- [추정] 열매 가방에 넣어 둘 수 있는 열매 수 (가득 차면 판매 가판대에서 팔기)
	PLANT_SELL_FRUIT_MULTIPLIER = 20, -- 성체 뽑아서 팔기 값 = 그 식물 열매 1개 값 × 20 (FruitRules.fruitValue)
	GARDEN_ACTION_RADIUS = 20, -- 열매 따기·먹이기·성체 뽑기·물 주기: 내 정원(울타리 사각형)에서 이 거리 안
	-- 건너뛰기 (SkipGrowth): 가격 = ceil(건너뛸 남은 시간(분)) × SKIP_COINS_PER_MINUTE × 등급 배수. "half" 는 남은 시간의 절반만
	SKIP_COINS_PER_MINUTE = 10,
	SKIP_RARITY_MULTIPLIER = {
		common = 1,
		uncommon = 2,
		rare = 4,
		epic = 8,
		legendary = 15,
		mythic = 30,
		cosmic = 60,
		secret = 100,
		eternity = 180,
		divine = 300,
		super_ultradivine = 500,
	} :: { [string]: number },
	-- 물 주기 (5판 쓰다듬기 PetPet 자리): 자라는 씨앗은 성장 +10초, 성체는 다음 열매까지 +10초. 식물마다 60초에 한 번
	WATER_GROWTH_SECONDS = 10,
	WATER_COOLDOWN = 60,

	------------------------------------------------------------------
	-- 낮/밤 주기 (설계문서 2장)
	------------------------------------------------------------------
	DAY_SECONDS = 285, -- 4분 45초
	NIGHT_SECONDS = 10,
	INTERMISSION_SECONDS = 3,
	NIGHT_GROWTH_MULTIPLIER = 30, -- 밤에는 씨앗이 30배 빨리 자람 (6판 사장님 결정 3: 그대로). 열매 맺는 빠르기는 밤에도 그대로
	GAMEPASS_GROWTH_MULTIPLIER = 2, -- 게임패스 "성장 속도 2배" (1차 버전에서는 플래그만)
	GAMEPASS_MONEY_MULTIPLIER = 2, -- 게임패스 "코인 2배" (플래그만 — 6판: 열매 판매 값에 곱함)
	DAY_CLOCK_TIME = 14,
	NIGHT_CLOCK_TIME = 0,

	------------------------------------------------------------------
	-- 둥지 / 알
	------------------------------------------------------------------
	NESTS_PER_BIOME = 8,
	NEST_RESPAWN_SECONDS = 30, -- [추정] 낮 동안 빈 둥지가 다시 채워지는 시간 (0이면 다시 안 채움)
	-- [추정] 바닥에 떨어진 알이 사라지는 시간(초). 2판 수정: 120 → 60 (사장님 "짧은 편이 좋음").
	-- 알 파트 Attribute ExpiresAt 으로 클라가 머리 위 카운트다운. 그 둥지는 알이 사라진 뒤에야 다시 채움
	DROPPED_EGG_LIFETIME = 60,
	PICKUP_DISTANCE = 12, -- 서버에서 확인하는 줍기 최대 거리(스터드)
	PROMPT_DISTANCE = 10, -- ProximityPrompt 표시 거리
	EGG_BASE_DIAMETER = 2, -- 보통 크기 알 지름(스터드), 크기 등급의 eggScale 을 곱함

	------------------------------------------------------------------
	-- 속도 → WalkSpeed 변환 (2판 수정: 원작 영상 관찰로 다시 맞춤, SpeedMath.toWalkSpeed)
	--   walkSpeed = clamp(BASE × (1 + log10(max(speed, FLOOR) / FLOOR)), BASE, MAX)
	--   속도 20 → 20.8 / 200 → 36.8 / 10K → 64 / 64K → 76.9 / 1M → 96 / 5.8M → 108.2 / 1B → 144 / 약 2.37B 이상 → 150
	--   (원작: 시작 ≈ 기본 걷기 16, 200 ≈ 35~40, 5.8M = 구역 하나(240)를 약 2초, 1B 넘으면 물리 한계로 상한)
	------------------------------------------------------------------
	-- 4판(사장님: "체감 속도 더 빠르게"): BASE 16 → 20, 10배마다 +19 (SLOPE 0.95), 상한 150 → 230 (약 1.1T 이상)
	--   속도 20 → 25.7 / 200 → 44.7 / 10K → 77 / 1M → 115 / 5.8M → 129.5 / 1B → 172 / 500B → 222 / 1.1T~ → 230
	SPEED_LOG_BASE = 20, -- 최소 WalkSpeed (속도 10 이하)
	SPEED_LOG_SLOPE = 0.95, -- 10배마다 BASE × SLOPE 만큼 빨라짐
	SPEED_LOG_FLOOR = 10, -- 속도가 이 값 이하면 BASE
	SPEED_WALK_MAX = 230, -- WalkSpeed 상한 (맨 끝 구역 경비 222 보다 커야 추월 가능)
	CARRY_WALKSPEED_MIN = 8, -- 알을 들었을 때 WalkSpeed 하한
	STARTING_SPEED = 20, -- [추정] 시작 속도 (숲 추천 속도 10 → 초거대 알을 들어도 숲 경비는 못 잡음)
	STARTING_MONEY = 0,
	-- 상한 (숫자가 터지거나 저장이 이상해지지 않게). 정상 플레이로는 닿지 않는 값.
	MONEY_MAX = 1e30,
	SPEED_MAX = 1e24,

	------------------------------------------------------------------
	-- 경비 동물 (GuardianService) — 2판: 추격 포기 거리 없음 (허브에 들어가거나·잡히거나·알을 놓을 때까지)
	--   경비 속도(기준) = 구역 추천 속도 × GUARD_SPEED_RATIO × (1 - 보통 알 무게 감소 0.10)  (SpeedMath.guardSpeedFor)
	--   추격 WalkSpeed = 알 든 플레이어의 WalkSpeed × 비율   (SpeedMath.guardChaseSpeed)
	--   비율 = clamp((경비 속도 / 알 든 실효 속도) ^ EXPONENT × MARGIN, MIN 0.85, MAX 3.0)
	--          단, 1 이상(= 속도가 모자람)이면 최소 SLOW_MIN_RATIO (조금만 모자라도 확실히 따라잡게)
	--   → 추천 속도 이상(보통 알)이면 0.85 ~ 0.99배라 절대 못 잡음, 모자라면 1.2 ~ 3배로 반드시 따라잡음
	--     (필요 배율 보통 0.99 / 큼 1.11 / 거대 1.37 / 초거대 1.78 — SpeedMath.requiredSpeed)
	------------------------------------------------------------------
	GUARD_SPEED_RATIO = 1, -- 경비 속도 배율 (위 식의 첫 번째 곱)
	GUARD_CHASE_EXPONENT = 1,
	GUARD_CHASE_MARGIN = 0.99, -- 속도가 딱 같으면 경비가 1% 느림 (2단계 B4: 0.97 → 0.99)
	GUARD_CHASE_MIN_RATIO = 0.85, -- 2판 (설계 2판 B: clamp 0.85 ~ 3.0)
	GUARD_CHASE_MAX_RATIO = 3.0,
	GUARD_CHASE_SLOW_MIN_RATIO = 1.2, -- [추정] 속도가 모자라면 경비는 최소 이 배율 (1.01배면 허브까지 못 따라잡음)
	GUARD_MAX_WALKSPEED = 250,
	GUARD_CATCH_DISTANCE = 6, -- 잡힘 판정 기본 거리(스터드). 실제 = 이 값 + 경비 키 × 아래 배율 (GuardLogic.catchDistance)
	GUARD_CATCH_HEIGHT_FACTOR = 0.25, -- 거대 경비일수록 손이 길게: 키 1스터드당 +0.25
	GUARD_CATCH_DISTANCE_MAX = 16, -- 잡힘 거리 상한
	GUARD_DEFAULT_HEIGHT = 8, -- 경비 키를 모를 때 (겉모습 모델 Height Attribute → Visuals.guards[..].height → 이 값)
	GUARD_CATCH_GRACE_SECONDS = 1.5, -- 둥지에서 줍자마자 바로 잡히지 않도록 주는 유예 (바닥 알 다시 줍기는 유예 없음)
	GUARD_TICK_SECONDS = 0.1,
	-- 2판 수정: 추격 목표 = 플레이어 위치 + 서버가 본 이동 속도 × 이 초 (150 스터드/초면 틱당 15 스터드 →
	-- 0.1초 전 자리를 목표로 주면 경비가 거기 먼저 도착해 멈췄다 달렸다 함). 잡힘은 틱 사이 가장 가까웠던 거리로 판정
	GUARD_LEAD_SECONDS = 0.25,
	GUARD_HOME_TOLERANCE = 4, -- 집에서 이 거리 안이면 도착 → 다시 잠듦 (State "Sleeping")
	GUARD_SEPARATION = 30, -- [추정] 경비끼리 이 거리보다 가까우면 옆으로 비켜 감 (거대 경비 겹침 방지)
	GUARD_COLLISION_GROUP = "Guardians", -- 경비끼리는 안 부딪힘 (서로 끼어 멈추지 않게, 겹침은 위 비켜 가기로)

	------------------------------------------------------------------
	-- 잡힘 / 래그돌
	------------------------------------------------------------------
	RAGDOLL_SECONDS = 2.5,
	KNOCKBACK_SPEED = 70,
	KNOCKBACK_UP_SPEED = 45,
	KNOCKBACK_SECONDS = 0.2,

	------------------------------------------------------------------
	-- 베이스 / 안전 구역 (2판: 맵 배치는 shared/Data/MapLayout)
	--   안전 구역 = 허브 (z < MapLayout.SAFE_ZONE_Z): 경비 추격 끝, 도구 사용·피격 불가
	--   배달 (2판 수정) = 알을 든 채 허브(MapLayout.isInHub)에 들어오는 순간 자동 → 알은 가방(data.eggs)으로
	------------------------------------------------------------------
	SAFE_ZONE_RADIUS = 48, -- [1판 — 서버 로직은 안 씀. 선임 MapBuilder 교체가 끝나면 지움]
	BASE_TICK_SECONDS = 0.2,
	SELL_RADIUS = 14, -- 판매 가판대(SellStall) 에서 이 거리 안이어야 SellFruits (성체 팔기 SellPlant 는 여기 또는 내 정원 근처)
	-- 들고 있는 씨앗 무게 표시(kg) = Sizes.carryKg (보통 50 / 큼 120 / 거대 400 / 초거대 1200 [추정])

	------------------------------------------------------------------
	-- 러닝머신 / 오프라인 (6판: 자동 수입·오프라인 수입 없음)
	------------------------------------------------------------------
	TREADMILL_TICK_SECONDS = 1,
	TREADMILL_STEPS_PER_SECOND = 1, -- 설계문서 9-2 "한 걸음 = 1초" [추정]
	TREADMILL_PAD_MARGIN = 1, -- 러닝머신 벨트(MapLayout.TREADMILL_PAD) 가장자리에서 이만큼 바깥까지 "위에 있음"
	TREADMILL_PIN_TOLERANCE = 1.5, -- 러닝머신 위에서 가운데서 이보다 밀리면 서버가 가운데로 되돌림
	TREADMILL_MAX_HEIGHT = 8, -- 캐릭터 몸통(HumanoidRootPart)이 바닥에서 이보다 높으면 러닝머신 위가 아님 → 점프하면 서버도 내려 줌 (벨트 윗면은 바닥 + 2 이하로)
	-- 러닝머신 배율: 걸음당 속도 × 이 값. 5판은 성장 3배(G = 3)에서 온 3, 6판(사장님 추가 지시 "끝까지 올리면 1초 1M")은 4:
	--   20레벨 걸음당 250,000 × 4 = 정확히 1,000,000/초 (1레벨 2 × 4 = 8/초). tests/sim_progress.luau 로 확인
	TREADMILL_MULTIPLIER = 4,
	-- 오프라인 동안: 심은 씨앗은 실제 시간만큼 자라고(밤 가속 없음) 성체는 열매를 맺음(식물마다 최대 5개). 상한 24시간
	OFFLINE_GROWTH_CAP_SECONDS = 24 * 60 * 60,

	-- (5판: 무료 보상(선물) FREE_REWARD_SPEED·FREE_REWARD_GROUP_ID 없앰 — 사장님 지시)

	------------------------------------------------------------------
	-- 5판: 랭킹판 (LeaderboardService) · 6판: 물 주기 (PetService PetPet, 5판 쓰다듬기 자리)
	------------------------------------------------------------------
	LEADERBOARD_INTERVAL = 10, -- 이 초마다 LeaderboardUpdate (서버 전체)
	LEADERBOARD_SIZE = 10, -- 코인·속도 각각 상위 몇 명
	PET_PET_RADIUS = 20, -- 물 주기: 내 정원(울타리 사각형)에서 이 거리 안 (= GARDEN_ACTION_RADIUS)
	PET_PET_COOLDOWN = 1, -- 물 주기 요청 사이 최소 간격(초, 사람마다 — 연타 막기). 식물마다 쿨다운은 WATER_COOLDOWN

	------------------------------------------------------------------
	-- 개발 명령 (DevCommands) 허용 목록
	--   비어 있으면: 스튜디오에서만, 누구나
	--   UserId 를 넣으면: 그 사람만 (스튜디오 + 실서버 둘 다)
	------------------------------------------------------------------
	DEV_USER_IDS = {} :: { number },

	------------------------------------------------------------------
	-- 도구 (설계문서 10장)
	------------------------------------------------------------------
	BAT_RANGE = 9,
	BAT_COOLDOWN_SECONDS = 1.2,
	BAT_FACING_DOT = 0.2, -- 앞쪽 판정 (내적 하한)
	BEAR_TRAP_STUN_SECONDS = 5,
	BEAR_TRAP_TRIGGER_RADIUS = 3,
	BEAR_TRAP_LIFETIME = 90,
	BEAR_TRAP_MAX_ACTIVE = 3,
	STARTING_BEAR_TRAPS = 3, -- [추정] "초반엔 개수 제한"
	BEAR_TRAP_MAX_OWNED = 99, -- [추정] 가질 수 있는 곰덫 최대 (도감 보상으로 늘어남: Data/Index TRAPS_*)
	-- 근접 무기(방망이·구역 무기)는 쿨다운을 같이 씀 (무기를 바꿔 들며 쿨다운 피하기 방지)
	-- 무기별 사거리·넉백·쿨다운은 shared/Data/Weapons.luau

	-- (6판: 퓨전 머신 FUSION_* 없앰 — 사장님 결정 4)

	------------------------------------------------------------------
	-- 벚꽃: 사쿠라 나무 — 씨앗 버전 (6판 사장님 결정 4, SakuraService / shared/SakuraRules)
	--   성체 식물을 바치면 크리스탈 (등급이 높을수록 많이) → 크리스탈로 특별 씨앗 뽑기 (가방으로)
	------------------------------------------------------------------
	SAKURA_RADIUS = 14, -- 사쿠라 나무 파트 표면에서 이 거리 안
	SAKURA_DRAW_COST = 10, -- [수석] 특별 씨앗 뽑기 1번에 크리스탈 몇 개
	-- [수석] 성체 1그루를 바치면 받는 크리스탈 (등급별)
	SAKURA_OFFER_CRYSTALS = {
		common = 1,
		uncommon = 1,
		rare = 2,
		epic = 3,
		legendary = 5,
		mythic = 8,
		cosmic = 12,
		secret = 20,
		eternity = 30,
		divine = 50,
		super_ultradivine = 100,
	} :: { [string]: number },
	-- 뽑기 결과: 벚꽃 씨앗 97.5% / 정령 벚꽃 씨앗 2.5% (5판 블룸 97.5% / 스피릿 블룸 2.5% 확률 그대로)
	SAKURA_SEEDS = {
		{ plantId = "blossom_fairy", chance = 0.975 },
		{ plantId = "spirit_blossom", chance = 0.025 },
	} :: { { plantId: string, chance: number } },
	SAKURA_CRYSTALS_PER_DELIVERY = 1, -- 벚꽃 구역 씨앗을 배달할 때마다 (들고 허브에 들어올 때)
	SAKURA_CRYSTAL_DROPS_PER_RESET = 3, -- [추정] 초기화 때 벚꽃 둥지 근처에 떨어지는 크리스탈 수
	SAKURA_CRYSTAL_PICKUP_DISTANCE = 12,
	SAKURA_CRYSTAL_MAX = 999999,

	-- (6판: 천사&악마 제단·비밀 통로 ALTAR_*·SHRINE_RADIUS 없앰 — 사장님 결정 4)
	-- (선물 알 대기 줄 EGG_QUEUE_MAX 는 2판 수정에서 없앰: 선물 씨앗도 가방으로, 상한 EGG_INVENTORY_MAX)
	-- (5판: 마법의 숲 퀘스트 QUEST_SECRET_EGG_CHANCE 없앰 — 공지 씨앗은 Data/EggSpawn.EXTRA_SPECIALS)

	------------------------------------------------------------------
	-- 치트 방지 2단계: 서버 위치 검증 (AntiCheatService / Logic/MoveCheck)
	--   1초마다 HumanoidRootPart 수평 이동 거리를 재서
	--   (WalkSpeed × SPEED_FACTOR) × 경과초 + SLACK 보다 멀면 마지막 정상 위치로 되돌림 + 경고
	------------------------------------------------------------------
	MOVE_CHECK_INTERVAL = 1,
	MOVE_CHECK_SPEED_FACTOR = 1.5,
	MOVE_CHECK_SLACK = 30,
	MOVE_CHECK_KICK_WARNINGS = 5, -- 경고가 이만큼 쌓이면 Kick (저장 안 함)
	MOVE_CHECK_WARNING_DECAY_SECONDS = 120, -- [추정] 경고 1개가 저절로 사라지는 시간 (렉 오탐이 오래 쌓이지 않게)
	MOVE_CHECK_EXEMPT_AFTER_TELEPORT = 2, -- 서버가 순간이동시킨 뒤 검사 쉬는 시간
	MOVE_CHECK_EXEMPT_AFTER_RAGDOLL = 1.5, -- 래그돌이 끝난 뒤 검사 쉬는 시간
	-- 알 든 사람 (BaseService 0.2초 틱): 한 틱에 WalkSpeed × 경과초 × FACTOR + SLACK 보다 멀리 움직이면 알을 원래 자리에 떨어뜨림
	CARRY_JUMP_SPEED_FACTOR = 1.5,
	CARRY_JUMP_SLACK = 8,
	-- 배달: 알을 주운 곳에서 배달한 곳(허브 안)까지 거리 ÷ (WalkSpeed × FACTOR) 보다 빨리 오면 거부 (알은 둥지로)
	DELIVERY_TIME_SPEED_FACTOR = 1.3,

	------------------------------------------------------------------
	-- 저장 (DataService)
	------------------------------------------------------------------
	DATASTORE_NAME = "StealAnEgg_PlayerData",
	DATASTORE_KEY_PREFIX = "player_",
	-- 3 (2판 마무리): + equippedTrail · 4 (2판 수정): + eggs(알 가방), 놓인 알 x/z, eggQueue 없앰 · 5 (5판): + tutorialStep, 퀘스트·무료 보상 칸 없앰
	-- 6 (6판 씨앗을 훔치세요): 새 게임 — 옛 데이터는 속도·트레일·러닝머신 레벨만 남기고 초기화. + fruits(열매 가방),
	--   pets = 정원 성체 식물(x, z, fruits, fruitProgress), equipped·sakuraUnlocked·shrineUsed 칸 없앰 (Logic/DataSchema)
	SCHEMA_VERSION = 6,
	AUTOSAVE_SECONDS = 60,
	SESSION_LOCK_STALE_SECONDS = 300, -- 이보다 오래된 세션 락은 무시
	DATASTORE_RETRIES = 3,
	DATASTORE_RETRY_DELAY = 2,
	SESSION_LOCK_WAIT_ATTEMPTS = 3,
	SESSION_LOCK_WAIT_SECONDS = 5,

	-- (1판 Config.MAP 임시 맵 숫자는 2판에서 shared/Data/MapLayout.luau 로 옮김)
}

return Config
