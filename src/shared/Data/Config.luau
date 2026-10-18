--!strict
--[[
	Config — 게임 전체 상수 (순수 데이터, 로블록스 API 없음 → Lune 테스트에서도 require 가능)

	[추정] 표시는 설계문서에 숫자가 없어서 수석이 정한 값입니다. 밸런스 조정은 여기 숫자만 바꾸면 됩니다.
]]

local Config = {
	------------------------------------------------------------------
	-- 성장 배율 (설계문서 14-1): 부화 시간 ÷G, 펫 수입 ×G, 러닝머신 걸음당 속도 ×G
	------------------------------------------------------------------
	GROWTH_MULTIPLIER = 3,

	------------------------------------------------------------------
	-- 서버 / 베이스
	------------------------------------------------------------------
	MAX_PLAYERS = 7,
	PLOT_COUNT = 7,
	INCUBATOR_SLOTS = 8, -- [추정] 베이스 하나의 부화 슬롯 수
	-- 펫 보관함 상한 (DataStore 4MB·네트워크 보호). 넘치면 장착 안 된 펫 중 수입이 가장 낮은 펫을 자동 판매
	PET_INVENTORY_MAX = 500,
	PET_AUTO_SELL_SECONDS = 60, -- 자동 판매 가격 = 그 펫 초당 수입 × 이 초

	------------------------------------------------------------------
	-- 낮/밤 주기 (설계문서 2장)
	------------------------------------------------------------------
	DAY_SECONDS = 285, -- 4분 45초
	NIGHT_SECONDS = 10,
	INTERMISSION_SECONDS = 3,
	NIGHT_GROWTH_MULTIPLIER = 30, -- 밤에는 알이 30배 빨리 자람
	GAMEPASS_GROWTH_MULTIPLIER = 2, -- 게임패스 "성장 속도 2배" (1차 버전에서는 플래그만)
	GAMEPASS_MONEY_MULTIPLIER = 2, -- 게임패스 "돈 2배" (1차 버전에서는 플래그만)
	DAY_CLOCK_TIME = 14,
	NIGHT_CLOCK_TIME = 0,

	------------------------------------------------------------------
	-- 둥지 / 알
	------------------------------------------------------------------
	NESTS_PER_BIOME = 8,
	NEST_RESPAWN_SECONDS = 30, -- [추정] 낮 동안 빈 둥지가 다시 채워지는 시간 (0이면 다시 안 채움)
	DROPPED_EGG_LIFETIME = 120, -- [추정] 바닥에 떨어진 알이 사라지는 시간(초)
	PICKUP_DISTANCE = 12, -- 서버에서 확인하는 줍기 최대 거리(스터드)
	PROMPT_DISTANCE = 10, -- ProximityPrompt 표시 거리
	EGG_BASE_DIAMETER = 2, -- 보통 크기 알 지름(스터드), 크기 등급의 eggScale 을 곱함

	------------------------------------------------------------------
	-- 속도 → WalkSpeed 변환 (설계문서 9-3: 로그 곡선, 수석이 정함)
	--   walkSpeed = MIN + (MAX - MIN) * log10(1 + speed) / log10(1 + SPEED_CURVE_MAX)
	------------------------------------------------------------------
	WALKSPEED_MIN = 16,
	WALKSPEED_MAX = 120,
	SPEED_CURVE_MAX = 1e13, -- 이 속도(10T)에서 WALKSPEED_MAX 도달
	CARRY_WALKSPEED_MIN = 8, -- 알을 들었을 때 WalkSpeed 하한
	STARTING_SPEED = 20, -- [추정] 시작 속도 (숲 추천 속도 10 → 초거대 알을 들어도 숲 경비는 못 잡음)
	STARTING_MONEY = 0,
	-- 상한 (숫자가 터지거나 저장이 이상해지지 않게). 정상 플레이로는 닿지 않는 값.
	MONEY_MAX = 1e30,
	SPEED_MAX = 1e24,

	------------------------------------------------------------------
	-- 경비 동물 (GuardianService)
	--   경비 속도 = 구역 추천 속도 × GUARD_SPEED_RATIO × (1 - 보통 알 무게 감소 0.10)  (SpeedMath.guardSpeedFor)
	--   추격 속도 = 알 든 플레이어의 WalkSpeed × 비율
	--   비율 = clamp((경비 속도 / 알 든 실효 속도) ^ EXPONENT × MARGIN, MIN, MAX)
	--   → 추천 속도면 보통 알은 안전 (필요 배율 보통 0.99 / 큼 1.11 / 거대 1.37 / 초거대 1.78)
	------------------------------------------------------------------
	GUARD_SPEED_RATIO = 1, -- 경비 속도 배율 (위 식의 첫 번째 곱)
	GUARD_CHASE_EXPONENT = 1,
	GUARD_CHASE_MARGIN = 0.99, -- 속도가 딱 같으면 경비가 1% 느림 (2단계 B4: 0.97 → 0.99)
	GUARD_CHASE_MIN_RATIO = 0.5,
	GUARD_CHASE_MAX_RATIO = 2.5,
	GUARD_MAX_WALKSPEED = 250,
	GUARD_LEASH_FACTOR = 2, -- 구역 반경(halfSize) × 이 값 × biome.guardPersistence 를 넘어가면 추격 포기
	GUARD_CATCH_DISTANCE = 6, -- 서버 거리 기준 잡힘 판정(스터드)
	GUARD_CATCH_GRACE_SECONDS = 1.5, -- 줍자마자 바로 잡히지 않도록 주는 유예
	GUARD_TICK_SECONDS = 0.1,
	GUARD_HOME_TOLERANCE = 4,

	------------------------------------------------------------------
	-- 잡힘 / 래그돌
	------------------------------------------------------------------
	RAGDOLL_SECONDS = 2.5,
	KNOCKBACK_SPEED = 70,
	KNOCKBACK_UP_SPEED = 45,
	KNOCKBACK_SECONDS = 0.2,

	------------------------------------------------------------------
	-- 베이스 / 안전 구역
	------------------------------------------------------------------
	SAFE_ZONE_RADIUS = 48, -- 베이스 중심에서 이 반경 안 = 안전 구역 (도구 사용 불가, 알 못 뺏음)
	DELIVERY_RADIUS = 9, -- 배달 패드 중심에서 이 반경 안에 알을 들고 오면 부화 슬롯에 등록
	TREADMILL_RADIUS = 5, -- 러닝머신 패드 중심에서 이 반경 안에 서 있으면 속도 증가
	BASE_TICK_SECONDS = 0.2,

	------------------------------------------------------------------
	-- 수입 / 러닝머신
	------------------------------------------------------------------
	INCOME_TICK_SECONDS = 1,
	TREADMILL_TICK_SECONDS = 1,
	TREADMILL_STEPS_PER_SECOND = 1, -- 설계문서 9-2 "한 걸음 = 1초" [추정]
	-- 러닝머신 배율: 걸음당 속도 × 이 값 (설계문서 14-1 은 G = 3). 밸런스 조정용으로 G 와 따로 둠.
	-- tests/sim_progress.luau 로 확인 (2단계 수석: 결과는 docs/REMOTES.md 가 아니라 보고서에)
	TREADMILL_MULTIPLIER = 3,
	OFFLINE_INCOME_CAP_SECONDS = 24 * 60 * 60, -- 오프라인 수입 상한 24시간
	OFFLINE_INCOME_RATE = 1, -- 오프라인 수입 비율 (1 = 100%)
	OFFLINE_POPUP_MIN_SECONDS = 60, -- 이보다 짧게 나갔다 오면 팝업 안 띄움

	------------------------------------------------------------------
	-- 무료 보상 (설계문서 11장)
	------------------------------------------------------------------
	FREE_REWARD_SPEED = 10000,
	FREE_REWARD_GROUP_ID = 0, -- 0 = 그룹 확인 안 함. 그룹을 만들면 ID를 넣으세요.

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

	------------------------------------------------------------------
	-- 퓨전 머신 (설계문서 9-4, FusionService / shared/FusionRules)
	------------------------------------------------------------------
	FUSION_RADIUS = 12, -- 내 베이스 퓨전 머신 파트 표면에서 이 거리 안이어야 함
	FUSION_BONUS_MUTATION_CHANCE = 0.10, -- 결과에 새 자연 돌연변이가 붙을 확률
	FUSION_BONUS_MUTATION_WEIGHTS = { silver = 5, golden = 2, rainbow = 0.5 } :: { [string]: number },

	------------------------------------------------------------------
	-- 벚꽃: 사쿠라 인큐베이터 (설계문서 4장, SakuraService)
	------------------------------------------------------------------
	SAKURA_UNLOCK_PET = "crane", -- 학 1마리를 바치면 해금
	SAKURA_RADIUS = 14, -- 인큐베이터 파트 표면에서 이 거리 안
	SAKURA_APPLY_COST = 1, -- [추정] 블룸 1번에 크리스탈 몇 개
	SAKURA_CRYSTALS_PER_DELIVERY = 1, -- 벚꽃 구역 알을 베이스에 배달할 때마다
	SAKURA_CRYSTAL_DROPS_PER_RESET = 3, -- [추정] 초기화 때 벚꽃 둥지 근처에 떨어지는 크리스탈 수
	SAKURA_CRYSTAL_PICKUP_DISTANCE = 12,
	SAKURA_CRYSTAL_MAX = 999999,

	------------------------------------------------------------------
	-- 천사&악마: 제단 / 비밀 통로 합성 (설계문서 4장, AltarService)
	------------------------------------------------------------------
	ALTAR_RADIUS = 14,
	ALTAR_RINGLORD_CHANCE = 0.20, -- 링로드 20% / 링 가드 80%
	SHRINE_RADIUS = 14,
	EGG_QUEUE_MAX = 20, -- 부화 슬롯이 가득 찼을 때 선물 알(제단·합성·퀘스트)이 기다리는 줄 길이

	------------------------------------------------------------------
	-- 마법의 숲 퀘스트 (설계문서 4장, QuestService / shared/Data/Quests)
	------------------------------------------------------------------
	QUEST_SECRET_EGG_CHANCE = 0.01, -- 퀘스트를 끝낸 사람이 서버에 있으면 초기화마다 영혼 세계 수호자 알 등장 확률

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
	-- 배달: 알을 주운 곳에서 배달 패드까지 거리 ÷ (WalkSpeed × FACTOR) 보다 빨리 오면 거부 (알은 둥지로)
	DELIVERY_TIME_SPEED_FACTOR = 1.3,

	------------------------------------------------------------------
	-- 저장 (DataService)
	------------------------------------------------------------------
	DATASTORE_NAME = "StealAnEgg_PlayerData",
	DATASTORE_KEY_PREFIX = "player_",
	SCHEMA_VERSION = 2,
	AUTOSAVE_SECONDS = 60,
	SESSION_LOCK_STALE_SECONDS = 300, -- 이보다 오래된 세션 락은 무시
	DATASTORE_RETRIES = 3,
	DATASTORE_RETRY_DELAY = 2,
	SESSION_LOCK_WAIT_ATTEMPTS = 3,
	SESSION_LOCK_WAIT_SECONDS = 5,

	------------------------------------------------------------------
	-- 임시 맵 (MapBuilder) — 선임이 맵을 새로 만들면 이 값들은 무시됨
	------------------------------------------------------------------
	MAP = {
		ZONE_SIZE = 170, -- 정사각형 구역 한 변
		ZONE_FIRST_Z = 190, -- 1번 구역 중심 Z
		ZONE_STEP_Z = 115, -- 구역 사이 Z 간격 (좌우 번갈아 배치)
		ZONE_SIDE_X = 140, -- 길 중심에서 구역 중심까지 X 거리
		NEST_RING_RADIUS = 45, -- 구역 중심에서 둥지까지 거리
		NIGHT_WALL_HEIGHT = 40,
		PLOT_SIZE = 90,
		PLOT_SPACING = 110,
		PLOT_Z = -70,
		SPAWN_Z = 25,
		ROAD_WIDTH = 100,
	},
}

return Config
