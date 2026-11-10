--!strict
--[[
	Config — 게임 전체 상수 (순수 데이터, 로블록스 API 없음 → Lune 테스트에서도 require 가능)

	[추정] 표시는 설계문서에 숫자가 없어서 수석이 정한 값입니다. 밸런스 조정은 여기 숫자만 바꾸면 됩니다.

	6판 "씨앗을 훔치세요" 용어 (코드 이름은 5판 그대로 둔 곳이 많음):
	  알(egg) → 씨앗 · 우리(pen) → 정원 · 부화(hatch) → 성체 되기 · 펫(pet) → 성체 식물 · 돈(money) → 코인
	  EGG_* = 씨앗, PEN = 정원, 저장 칸 pets = 정원의 성체 식물, incubators = 자라는 씨앗
	6판에서 없앤 것: GROWTH_MULTIPLIER(펫 수입 ×3 — 열매 값은 Data/Plants 숫자 그대로), 펫 보관함(PET_INVENTORY_MAX)·
	  자동 수입(INCOME_*)·오프라인 수입·펫 판매(PET_SELL_SECONDS)·퓨전(FUSION_*)·제단/비밀 통로(ALTAR_*, SHRINE_*)·
	  사쿠라 해금(SAKURA_UNLOCK_PET)·블룸(SAKURA_APPLY_COST)·우리에 놓는 알 상한(PLACED_EGG_MAX → 정원 칸 수 = 정원 업그레이드)
	7판: 등급 16개(SKIP_RARITY_MULTIPLIER·SAKURA_OFFER_CRYSTALS 칸 6개 추가, super_ultradivine 없앰), 성장 속도 3배
	  (GROWTH_SPEED_MULTIPLIER — 성장 시간에만. 5판 GROWTH_MULTIPLIER 처럼 열매 값·러닝머신에 곱하지 않음), 저장 스키마 7
	8판 (사장님 2026-11-08): 떨어진 씨앗(DROPPED_EGG_RETURN_SECONDS 5 — 그 씨앗 구역 밖이면 5초 뒤 둥지로, 안이면 그대로),
	  둥지 무리(NESTS_PER_BIOME 8 → 5), 경비 잡힘 시간(GUARD_CATCH_CLOSE/FAR_SECONDS · CLOSE_RATIO · RUSH), 식물 크기 배율
	  한 곳(RARITY_PLANT_SCALE · STAGE_SCALE · PLANT_SIZE_SCALE · PLANT_FOOTPRINT · PLANT_GAP_MAX).
	  없앰: DROPPED_EGG_LIFETIME(60초 뒤 사라짐), GUARD_CATCH_GRACE_SECONDS(잡힘은 이제 거리 대신 시간으로 정함)
	8판 추가 (사장님 2026-11-09): 크기 곡선 1 → 6 (RARITY_PLANT_SCALE), 맨 위 등급 거대 크기(LOBBY_FILL_RARITY · LOBBY_FILL_SCALE ·
	  LOBBY_FILL_MAX_PER_GARDEN), 정원 프롬프트 높이 상한(PLANT_PROMPT_MAX_HEIGHT). 특별 추첨 확률은 Data/EggSpawn
	8판 추가 2 (사장님 2026-11-09 "사쿠라 뽑기가 너무 쉬움"): SAKURA_DRAW_COST 10 → 100, SAKURA_OFFER_CRYSTALS 낮은 등급을 짜게
	  (일반 0 = 못 바침 · 고급 1 · 에픽 5 · 코스믹 40 · 슈퍼 200 · 해커 글리치 700)
9판 (사장님 2026-11-10): 열매 먹이기 삭제 (열매는 팔기만). 로벅스 상품(Data/Products, 서버 ProductService) —
  코인 2배 게임패스 플래그(GAMEPASS_MONEY_MULTIPLIER) → 로벅스 상품 money_pass (MONEY_PASS_MULTIPLIER, 저장 data.moneyPass),
  영수증 기록 RECEIPT_HISTORY_MAX, 저장 스키마 8
9-10 (사장님 2026-11-10): 64번 슈퍼 씨앗(로벅스, 가방이 가득 차도 지급 → 저장 스키마 9) · 65번 경비가 깨어나는 시간
  GUARD_WAKE_SECONDS(1.78초 — 둥지에서 훔친 사람은 그동안 안 쫓고 닿아도 안 잡힘. 지나도 닿아야만 잡힘)
]]

local Config = {
	------------------------------------------------------------------
	-- 서버 / 베이스
	------------------------------------------------------------------
	MAX_PLAYERS = 7,
	PLOT_COUNT = 7,
	-- 씨앗 가방 / 정원에 심기 (5판 알 가방·우리에 놓기 그대로: 허브에 들고 들어오면 씨앗은 가방으로, 정원 안 원하는 자리에 심음)
	EGG_INVENTORY_MAX = 50, -- [추정] 가방에 넣어 둘 수 있는 씨앗 수 (가득 차면 배달·선물 씨앗을 못 받음 — 로벅스 슈퍼 씨앗만 예외, 64번)
	-- 정원 칸 수 = 정원 업그레이드(Upgrades.Pen) 칸 수 (7 → 18). 자라는 씨앗 + 성체 식물 합이 이 수까지 (Economy.penSlots)
	EGG_PLACE_SPACING = 4, -- 심는 씨앗 ↔ 다른 씨앗·성체 식물 최소 간격(스터드). 큰 씨앗끼리는 두 씨앗 지름 평균까지 늘어남
	--   8판: 두 자리가 다 자랐을 때 성체 폭 평균(EggPlacement.footprint, 아래 식물 크기 배율)까지 늘어남 — 최대 PLANT_GAP_MAX
	EGG_PLACE_FENCE_MARGIN = 2, -- 씨앗 가운데가 정원 울타리에서 이만큼 안쪽이어야 함
	EGG_PLACE_RADIUS = 14, -- 내 베이스 밖에 서 있으면 심을 자리에서 이 거리 안이어야 PlaceEgg 가능
	ALLOW_EGG_PICKUP = true, -- PickUpPlacedEgg(심은 씨앗을 다시 가방으로, 자란 만큼 유지) 허용

	------------------------------------------------------------------
	-- 6판 정원: 성장 단계 · 열매 · 건너뛰기 · 성체 팔기 (shared/GardenRules, shared/FruitRules)
	------------------------------------------------------------------
	-- 성장 단계: 자란 비율(progress / required)이 from 이상이면 그 단계. 100% = 성체 (그 자리에서 성체 식물이 됨)
	GROWTH_STAGES = {
		{ id = "sprout", name = "새싹", from = 0 },
		{ id = "stem", name = "줄기", from = 0.25 },
		{ id = "bud", name = "봉오리", from = 0.60 },
		{ id = "adult", name = "성체", from = 1 },
	} :: { { id: string, name: string, from: number } },
	-- 8판 (사장님 2026-11-08 "등급 높을수록 성체가 3~5배 크게, 자라면서 점점 커지게") — 식물 크기 배율은 **여기 한 곳**.
	--   보이는 크기 = RARITY_PLANT_SCALE[등급] × PLANT_SIZE_SCALE[크기] × 자람 배율(GardenRules.growthScale: STAGE_SCALE 사이를
	--   자란 비율로 이어 줌 — 새싹 0.3 → 줄기 0.55 → 봉오리 0.8 → 성체 1). 모양은 선임 PlantVisualService 가 이 숫자로.
	--   정원 간격: 성체 폭(지름) = PLANT_FOOTPRINT × 등급 배율 × 크기 배율 (EggPlacement.footprint) — 씨앗을 심을 때부터
	--   다 자란 폭만큼 띄움 (큰 식물끼리 안 겹치게). 간격은 PLANT_GAP_MAX(14)까지만 → 14 간격 4 × 5 = 20칸이 정원
	--   (울타리 2 안쪽: 42 × 56)에 들어가서 정원 칸 최대 18 이 맨 위 등급 식물로도 다 들어감 (tests/holes_v8)
	-- 8판 추가 (사장님 2026-11-09 "등급이 높을수록 3~6배"): 매끄러운 로그 곡선 = 1 + 2.876 × ln(1 + 0.335 × (등급 순서 - 1))
	--   → 일반 1 · 희귀 2.47 · 에픽 3 · 신성 5 · 울트라디바인 6 (등급마다 커지는 폭이 조금씩 줄어듦, 단조 증가).
	--   16번 해커 글리치 칸(6.16 = 곡선 그대로)은 **정원 간격용** — 모양은 아래 LOBBY_FILL_SCALE(베이스를 덮는 거대 크기)
	RARITY_PLANT_SCALE = {
		common = 1,
		uncommon = 1.83,
		rare = 2.47,
		epic = 3,
		legendary = 3.44,
		mythic = 3.83,
		cosmic = 4.17,
		secret = 4.47,
		eternity = 4.75,
		divine = 5,
		super = 5.23,
		hacker = 5.44,
		original = 5.64,
		developer = 5.83,
		ultradivine = 6,
		hacker_glitch = 6.16, -- 간격용 (모양 = LOBBY_FILL_SCALE)
	} :: { [string]: number },
	-- 8판 추가 (사장님 2026-11-09): 맨 위 등급 "H?a.(cke_r!#" 성체는 **내 베이스 전체를 덮는 거대 크기** (모양만 — 간격은 위 표 값)
	--   모양 등급 배율 = LOBBY_FILL_SCALE (GardenRules.rarityScale/plantScale), 크기 등급·자람 배율은 똑같이 곱함.
	--   16 이유: 정원 모델(PlantVisualService GARDEN_BASE 1.35) 배율 1 의 해커 글리치 9종 키 3.6 ~ 4.6 (평균 4.2) · 잎 폭 1.6 ~ 3.3
	--   → × 16 = 키 57 ~ 74 (평균 67) · 폭 26 ~ 52 (나무 모양 52) ≈ 베이스 PLOT_SIZE 60 × 70 (초거대 씨앗이면 × 1.5 = 키 약 100)
	--   정원 간격·심기(EggPlacement)는 표 값 6.16 으로 계산해서 PLANT_GAP_MAX 14 에 묶임 → 심을 수 있음. 정원에 **1그루만**
	--   (자라는 씨앗 + 성체 합, LOBBY_FILL_MAX_PER_GARDEN — 이미 있으면 PlaceEgg 거절 "거대 식물은 정원에 하나만").
	--   모양 파트는 전부 CanCollide/CanTouch/CanQuery false 라 옆 베이스·복도를 덮어도 막히지 않음.
	LOBBY_FILL_RARITY = "hacker_glitch",
	LOBBY_FILL_SCALE = 16,
	LOBBY_FILL_MAX_PER_GARDEN = 1,
	STAGE_SCALE = { sprout = 0.3, stem = 0.55, bud = 0.8, adult = 1 } :: { [string]: number },
	PLANT_SIZE_SCALE = { normal = 1, big = 1.15, huge = 1.3, giant = 1.5 } :: { [string]: number }, -- 씨앗 크기 등급(Sizes) → 식물 크기
	PLANT_FOOTPRINT = 2.6, -- 배율 1 성체의 바닥 폭(지름, 스터드) — PlantVisualService 나무 잎 1.6 + 옆 잎 ≈ 2.6
	PLANT_GAP_MAX = 14, -- 정원 간격 상한 (위 설명: 18칸이 다 들어가게)
	-- 8판 추가 (2026-11-09): 정원 프롬프트(집기·건너뛰기 = 키의 50%, 열매 따기 = 키의 60%) 높이 상한(바닥에서, 스터드).
	--   큰 식물(울트라디바인 키 약 24 · 거대 식물 67)도 프롬프트가 손 닿는 높이(MaxActivationDistance 10 ~ 12)에 있게 (GardenRules.promptHeight)
	PLANT_PROMPT_MAX_HEIGHT = 7,
	PASSIVE_INCOME_PER_SECOND = 0, -- 6판(사장님 결정 1): 자동 수입 없음 — 코인은 열매를 따서 팔아야 들어옴
	EARLY_COIN_MULTIPLIER = { common = 2, uncommon = 2 } :: { [string]: number }, -- 사장님(2026-10-28): 초반 코인 수급 2배 — 초반 구역 등급(일반·고급) 열매 값 ×2 (성체 팔기 값도 따라 ×2)
	FRUIT_SPEED_MULTIPLIER = 1.8, -- 사장님(2026-10-28): 열매가 1.8배 더 빨리 맺힘 (Economy.fruitInterval = 표 간격 ÷ 1.8)
	FRUIT_MAX_PER_PLANT = 5, -- 안 따면 식물마다 열매가 이만큼까지만 쌓임 (설계 7장 결정 1)
	FRUITS_ON_ADULT = 1, -- [수석] 성체가 되는 순간 달려 있는 열매 (튜토리얼 5단계 "열매 따서 팔기" 를 바로 할 수 있게)
	FRUIT_BAG_MAX = 300, -- [추정] 열매 가방에 넣어 둘 수 있는 열매 수 (가득 차면 판매 가판대에서 팔기)
	PLANT_SELL_FRUIT_MULTIPLIER = 20, -- 성체 뽑아서 팔기 값 = 그 식물 열매 1개 값 × 20 (FruitRules.fruitValue)
	GARDEN_ACTION_RADIUS = 20, -- 열매 따기·성체 뽑기: 내 정원(울타리 사각형)에서 이 거리 안 (9판: 먹이기 없앰)
	-- 건너뛰기 (SkipGrowth): 가격 = ceil(건너뛸 남은 시간(분)) × SKIP_COINS_PER_MINUTE × 등급 배수. "half" 는 남은 시간의 절반만
	SKIP_COINS_PER_MINUTE = 10,
	SKIP_FRUIT_FACTOR = 10, -- 사장님(2026-10-29 "올려"): 건너뛰기 가격에 (건너뛸 비율 × 그 식물 열매 1개 값 × 10) 을 더함 — 높은 등급이 거의 공짜였던 것 수정
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
		-- 7판 새 등급 (super = 6판 슈퍼 울트라디바인 500 그대로)
		super = 500,
		hacker = 800,
		original = 1200,
		developer = 2000,
		ultradivine = 3000,
		hacker_glitch = 5000,
	} :: { [string]: number },

	------------------------------------------------------------------
	-- 낮/밤 주기 (설계문서 2장)
	------------------------------------------------------------------
	DAY_SECONDS = 285, -- 4분 45초
	NIGHT_SECONDS = 10,
	INTERMISSION_SECONDS = 3,
	NIGHT_GROWTH_MULTIPLIER = 30, -- 밤에는 씨앗이 30배 빨리 자람 (6판 사장님 결정 3: 그대로). 열매 맺는 빠르기는 밤에도 그대로
	-- 7판 사장님 지시 "성장 속도 3배": 성체까지 걸리는 시간 = 식물 표(Data/Plants.growSeconds) ÷ 이 값 (Economy.growSeconds 한 곳).
	--   표 숫자는 그대로 두고 계산에서만 나눔 → 씨앗 Required·타이머·건너뛰기 가격(남은 시간)이 전부 ÷3 된 값.
	--   밤 30배·게임패스 2배와는 곱 (밤 + 3배 = 표 시간의 1/90). 열매 맺는 빠르기(FRUIT_SPEED_MULTIPLIER)와는 따로
	GROWTH_SPEED_MULTIPLIER = 3,
	GAMEPASS_GROWTH_MULTIPLIER = 2, -- 게임패스 "성장 속도 2배" (1차 버전에서는 플래그만)
	-- 9판: 로벅스 상품 "코인 2배 (영원히)" (Data/Products money_pass, 저장 data.moneyPass) — 열매 판매·성체 팔기 코인에 곱함
	MONEY_PASS_MULTIPLIER = 2,
	DAY_CLOCK_TIME = 14,
	NIGHT_CLOCK_TIME = 0,

	------------------------------------------------------------------
	-- 둥지 / 알
	------------------------------------------------------------------
	-- 8판 (사장님 2026-11-08, 원작처럼): 구역마다 둥지 5개가 끝쪽 오른쪽 귀퉁이에 바짝 모여 있음 (MapLayout.nestsFor).
	--   씨앗 종류(구역마다 8종)는 그대로 추첨 — 둥지 수만 8 → 5
	NESTS_PER_BIOME = 5,
	NEST_RESPAWN_SECONDS = 30, -- [추정] 낮 동안 빈 둥지가 다시 채워지는 시간 (0이면 다시 안 채움)
	-- 8판 떨어진 씨앗 규칙 (사장님 2026-11-08, EggRules.groundFate):
	--   그 씨앗 구역 **안**에 떨어지면 → 둥지로 안 가고 그 자리에 그대로 (누구나 줍기, 다음 초기화까지. 카운트다운 없음)
	--   그 구역 **밖**(다른 구역·허브 쪽)에 떨어지면 → 이 초 뒤 둥지로 돌아감 (알 파트 Attr ExpiresAt = 돌아가는 시각 →
	--   클라 머리 위 "5초" 카운트다운, ReturnsToNest = true). 7판까지는 60초 뒤 사라짐(DROPPED_EGG_LIFETIME)
	DROPPED_EGG_RETURN_SECONDS = 5,
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
	-- 잡힘 거리 (8판: 잡힘 판정은 시간 — 이 거리는 경비가 따라붙어 멈추는 거리·모델 Attr CatchDistance 표시용)
	GUARD_CATCH_DISTANCE = 6, -- 기본 거리(스터드). 실제 = 이 값 + 경비 키 × 아래 배율 (GuardLogic.catchDistance)
	GUARD_CATCH_HEIGHT_FACTOR = 0.25, -- 거대 경비일수록 손이 길게: 키 1스터드당 +0.25
	GUARD_CATCH_DISTANCE_MAX = 16, -- 잡힘 거리 상한
	GUARD_DEFAULT_HEIGHT = 8, -- 경비 키를 모를 때 (겉모습 모델 Height Attribute → Visuals.guards[..].height → 이 값)
	-- 8판 (사장님 2026-11-08) 잡히는 규칙 = **시간** (GuardianService, SpeedMath.catchSeconds) — 물리 거리로는 안 잡음:
	--   도망칠 수 없으면(SpeedMath.canEscape false) 추격 시간이 이만큼 쌓이는 순간 잡힘 (씨앗은 놓친 규칙대로):
	--     내 실효 속도 ≥ 경비 추격 기준(경비 속도 × MARGIN)의 CLOSE_RATIO(70%) → CLOSE_SECONDS(2.5초), 그보다 느리면 FAR_SECONDS(1초)
	--     추격 시간은 그 씨앗·그 사람마다 쌓임 (내려놓았다 다시 주워도 이어서 — 버렸다 줍기로 못 버팀, 둥지로 돌아가면 0)
	--     마지막 RUSH_SECONDS(0.3초)는 경비가 빠르게 다가감 (WalkSpeed ≤ RUSH_MAX_WALKSPEED, 순간이동처럼 안 보이게)
	--   도망칠 수 없는 채로 **다음 구역 경계(그 구역 zMax)** 를 넘으면 즉시 잡힘 + 씨앗은 둥지로 (다음 구역 절대 못 감)
	--   도망칠 수 있으면 자유 (경비는 쫓아오기만 하고 못 잡음 — 경비가 둥지 바로 옆에서 자고 뒤 구역은 걷기 차이가 0.1 이라
	--   거리로 잡으면 추천 속도를 넘어도 억울하게 잡힘)
	GUARD_CATCH_CLOSE_SECONDS = 2.5,
	GUARD_CATCH_FAR_SECONDS = 1,
	GUARD_CATCH_CLOSE_RATIO = 0.7,
	GUARD_CATCH_RUSH_SECONDS = 0.3,
	GUARD_CATCH_RUSH_MAX_WALKSPEED = 400,
	GUARD_TICK_SECONDS = 0.1,
	-- 2판 수정: 추격 목표 = 플레이어 위치 + 서버가 본 이동 속도 × 이 초 (150 스터드/초면 틱당 15 스터드 →
	-- 0.1초 전 자리를 목표로 주면 경비가 거기 먼저 도착해 멈췄다 달렸다 함). 잡힘은 틱 사이 가장 가까웠던 거리로 판정
	GUARD_LEAD_SECONDS = 0.25,
	GUARD_HOME_TOLERANCE = 4, -- 집에서 이 거리 안이면 도착 → 다시 잠듦 (State "Sleeping")
	-- 65번 (사장님 2026-11-10 "사람이 계란을 훔치고 1.78초 후에 쫓아오게"): 둥지에서 그 구역 씨앗을 집은 사람은 이 초 동안
	--   그 경비가 계속 잠 — 안 쫓고 **닿아도 안 잡음** (GuardianService, egg.stolenAt). 지나면 평소 규칙 (닿아야만 잡힘 —
	--   이 시간은 깨어나는 시간일 뿐, 지나도 시간으로는 아무 일도 없음). 바닥에 떨어진 씨앗을 다시 주우면 지연 없음.
	--   도망칠 수 없는 채로 다음 구역 경계를 넘으면 즉시 잡힘은 이 시간과 상관없음
	GUARD_WAKE_SECONDS = 1.78,
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
	-- 5판: 랭킹판 (LeaderboardService)
	------------------------------------------------------------------
	LEADERBOARD_INTERVAL = 10, -- 이 초마다 LeaderboardUpdate (서버 전체)
	LEADERBOARD_SIZE = 10, -- 코인·속도 각각 상위 몇 명

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
	-- 8판 추가 2 (사장님 2026-11-09 "사쿠라 뽑기가 너무 쉬움"): 뽑기 10 → 100, 낮은 등급 크리스탈을 짜게
	SAKURA_DRAW_COST = 100, -- 특별 씨앗 뽑기 1번에 크리스탈 몇 개 (7판 10)
	-- 성체 1그루를 바치면 받는 크리스탈 (등급별, 단조 증가). 0 = 못 바침 (SakuraRules.canOffer — "너무 흔해서 안 받아요")
	-- 뽑기 1번(100) = 고급 100그루 · 에픽 20그루 · 코스믹 2.5그루 · 영원 1그루
	SAKURA_OFFER_CRYSTALS = {
		common = 0, -- 7판 1
		uncommon = 1,
		rare = 2,
		epic = 5, -- 7판 3
		legendary = 10, -- 7판 5
		mythic = 20, -- 7판 8
		cosmic = 40, -- 7판 12
		secret = 70, -- 7판 20
		eternity = 100, -- 7판 30
		divine = 150, -- 7판 50
		super = 200, -- 7판 100 (6판 슈퍼 울트라디바인 값)
		hacker = 260, -- 7판 150
		original = 330, -- 7판 220
		developer = 400, -- 7판 320
		ultradivine = 500, -- 7판 480
		hacker_glitch = 700,
	} :: { [string]: number },
	-- 뽑기 결과: 벚꽃 씨앗 97.5% / 정령 벚꽃 씨앗 2.5% (5판 블룸 97.5% / 스피릿 블룸 2.5% 확률 그대로)
	SAKURA_SEEDS = {
		{ plantId = "blossom_fairy", chance = 0.975 },
		{ plantId = "spirit_blossom", chance = 0.025 },
	} :: { { plantId: string, chance: number } },
	-- 줍기·배달은 1개씩 그대로 (8판 추가 2: 뽑기가 100 이라 상대 가치가 이미 1/10 — 줍기만으로 뽑기 1번 = 초기화 약 34번 ≈ 2.8시간)
	SAKURA_CRYSTALS_PER_DELIVERY = 1, -- 벚꽃 구역 씨앗을 배달할 때마다 (들고 허브에 들어올 때)
	SAKURA_CRYSTAL_DROPS_PER_RESET = 3, -- [추정] 초기화 때 벚꽃 둥지 근처에 떨어지는 크리스탈 수 (1개 = 크리스탈 1)
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
	-- 7 (7판): 칸 모양은 6 그대로. 성장 3배라 저장된 씨앗 진행도(progress)를 새 Required 에 맞춰 같은 비율로 줄임
	--   (6 → 7 마이그레이션, Logic/DataSchema). 등급 id 는 저장하지 않으므로 옛 super_ultradivine 보정은 없음
	-- 8 (9판 로벅스 상품): + treadmillBoost(1) · moneyPass(false) · receipts({}) — 옛 데이터는 기본값으로 채움 (7 → 8 은 칸만 추가)
	-- 9 (64번 슈퍼 씨앗): 가방 씨앗에 bought(로벅스로 산 씨앗 — 가방 상한을 넘어도 안 잘림). 8 → 9 는 고칠 것 없음
	SCHEMA_VERSION = 9,
	-- 지급한 로벅스 영수증 PurchaseId 를 최근 이만큼 저장 (중복 지급 방지, 고리). 주임 F-2: 100 → 500 (밀려난 옛 영수증 재지급 여유)
	RECEIPT_HISTORY_MAX = 500,

	------------------------------------------------------------------
	-- 9판 로벅스 상품 (Data/Products, ProductService)
	------------------------------------------------------------------
	-- 주임 F-3: 레벨이 안 맞는 러닝머신 레벨 상품(tskip)은 **산 로벅스만큼만** — 다음 레벨 가격부터 차례로 빼며 살 수 있는
	--   레벨만 올리고, 남은 로벅스는 속도로 (Products.treadmillSkipOutcome). 환산율 = 가장 비싼 속도 상품 speed_100m
	--   (1e8 ÷ 259 R$ = 386,100.39…) 을 내림 — 속도 상품보다 유리하지 않게. (8판 "최대면 속도 600M 고정"은 없앰)
	PRODUCT_SPEED_PER_ROBUX = 386100,
	AUTOSAVE_SECONDS = 60,
	SESSION_LOCK_STALE_SECONDS = 300, -- 이보다 오래된 세션 락은 무시
	DATASTORE_RETRIES = 3,
	DATASTORE_RETRY_DELAY = 2,
	SESSION_LOCK_WAIT_ATTEMPTS = 3,
	SESSION_LOCK_WAIT_SECONDS = 5,

	-- (1판 Config.MAP 임시 맵 숫자는 2판에서 shared/Data/MapLayout.luau 로 옮김)
}

return Config
