# Remote 목록 (서버 ↔ 클라) — 6판 "씨앗을 훔치세요"

> **[6판] 씨앗을 훔치세요 (수석, 2026-10-27)** — 사장님이 만든 게임으로 바꿈 (설계: `docs/SEED_GAME_DESIGN.md`). **서버·공유 규칙은 다 됨, 클라 화면은 선임** (8장 "선임 할 일").
> - **용어** (Remote·모듈·태그 이름은 5판 그대로 둔 것이 많음): 알 → **씨앗** · 우리 → **정원** · 부화 → **성체가 됨**(저절로, 심은 그 자리에서) · 펫 → **성체 식물** · 돈 → **코인** · 쓰다듬기 → **물 주기**.
>   `PlaceEgg` = 씨앗 심기, `PickUpPlacedEgg` = 심은 씨앗 다시 줍기, `PetPet` = 물 주기, `IncubatingEgg` 태그 = 자라는 씨앗, `snap.pets` = 정원의 성체 식물, `petId` = 식물 id (`Data/Plants`, `Data/Pets` 는 같은 표).
> - **흐름**: 구역에서 씨앗 훔치기 → 허브(안전 구역)에 들어오면 씨앗 가방 → `PlaceEgg` 로 정원에 심기 → 새싹 → 줄기 → 봉오리 → **성체**(`PlantGrown`) → 열매가 맺힘(식물마다 최대 5개) → `PickFruit` 로 따서 열매 가방 → 판매 가판대에서 `SellFruits` → 코인. 코인으로 `SkipGrowth`(건너뛰기)·정원/러닝머신/트레일 업그레이드. 가방의 열매를 성체에게 `FeedFruit` → 확률로 돌연변이(열매 값 ↑). 남는 성체는 `SellPlant`(열매 값 × 20) 또는 사쿠라 나무에 `SakuraOffer`(크리스탈) → `SakuraDraw`(특별 씨앗).
> - **없앤 Remote** — 서버→클라: `HatchResult`(→ `PlantGrown`), `OfflineIncome`, `FusionResult`, `AltarUpdate`, `ShrineResult`, `PetsSold`, `IncomeTick` / 클라→서버: `HatchEgg`(성체는 저절로), `EquipPet`, `UnequipPet`, `EquipBest`(장착 없음), `FuseRequest`, `AltarOffer`, `ShrineFuse`, `SakuraApply`(→ `SakuraDraw`), `SellPet`(→ `SellPlant`).
> - **새 Remote** — 서버→클라: `PlantGrown`, `FruitPicked`, `FruitsSold`, `FeedResult` / 클라→서버: `PickFruit`, `SellFruits`, `FeedFruit`, `SkipGrowth`, `SellPlant`, `SakuraDraw`. **뜻이 바뀐 Remote**: `SakuraOffer(plantUid)`(학 해금 → 성체 바치고 크리스탈), `PetPet(uid)`(쓰다듬기 → 물 주기, 자라는 씨앗도 됨), `SakuraResult`(kind `"offered"`/`"draw"`), `EggGranted`(source `"sakura"`/`"dev"`), `PetPetted`(물방울 연출).
> - **없앤 것**: 장착·보관함(`equipped`, `petInventoryMax`, 보관함 500·자동 판매), 자동 수입·오프라인 수입(Attr `IncomePerSecond`), 퓨전 머신(`FusionMachine` 태그, `plot.fusion`), 제단·비밀 통로(`Altar`·`Shrine` 태그, `MapLayout.specials.altarLight/altarDark/shrine`, `shrineUsed`), 사쿠라 해금(`sakuraUnlocked`, Attr `SakuraUnlocked`), 블룸 돌연변이, 우리에 놓는 알 8개 상한(`PLACED_EGG_MAX` → 정원 칸 = 자라는 씨앗 + 성체).
> - **저장 스키마 6**: 5판 이하 데이터는 속도·트레일·장착 트레일·러닝머신 레벨만 남기고 초기화, 튜토리얼 1단계부터 (SEED 15장).
> - **러닝머신 최대 1초 1M** (사장님 추가 지시): 20레벨, 1초 속도 = 걸음당 속도 × 4 → 20레벨이면 **1,000,000** (`docs/GAME_DESIGN.md` 9-2 표). 상점 창이 10레벨을 가정한 곳이 없는지 선임 확인 (8장).
> - 5판 이전 기록(튜토리얼·랭킹판 도입, 2판 수정 등)은 git 기록에 있음. 이 문서는 6판 기준으로 다시 씀.

작성: 수석 (1단계 2026-10-18 · 2판 2026-10-18 · 5판 2026-10-22 · **6판 전면 갱신 2026-10-27**). 선임이 맵·UI·소리·연출을 붙일 때 보는 문서입니다.

- Remote 이름은 `src/shared/Remotes.luau` **한 곳**에서만 정의합니다. 서버(`src/server/Net.luau`)가 `ReplicatedStorage.Remotes` 폴더에 전부 RemoteEvent 로 만들고, 클라(`src/client/Net.luau`)는 `WaitForChild` 로 받습니다.
- RemoteFunction 은 쓰지 않습니다. 요청은 RemoteEvent 로 보내고, 결과는 서버가 다른 이벤트(`Notify`, `DataUpdate` 등)로 알려 줍니다.
- **치트 방지 원칙:** 코인·속도·식물을 직접 바꾸는 Remote 는 없습니다. 클라는 "요청"만 보내고 서버가 전부 검증합니다 (인자 타입 검사 + 플레이어·Remote 별 레이트 리밋 + 게임 규칙 검사 + "근처여야 하는" 요청은 서버가 캐릭터 위치로 거리 확인).
- **클라에서 캐릭터를 순간이동시키지 마세요.** 서버가 1초마다 이동 거리를 검사합니다(9장). 러닝머신 고정·밤 귀가처럼 캐릭터를 옮기는 일은 전부 서버가 합니다.

클라 코드에서 쓰는 법:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapLayout = require(ReplicatedStorage.Shared.Data.MapLayout)
local Net = require(ReplicatedStorage.Client.Net)
local State = require(ReplicatedStorage.Client.State)

Net.on(Remotes.ToClient.FruitsSold, function(p) --[[ "+1.2K 코인" 연출: p.coins, p.count ]] end)
Net.send(Remotes.ToServer.PickFruit, "all")
local zone = MapLayout.zoneAt(rootPart.Position.Z) -- 구역 id | "hub" | nil (서버와 같은 판정)
```

---

## 0. 2판 맵 배치 — `shared/Data/MapLayout.luau` (순수 데이터, 서버·클라·Lune 공용)

위에서 본 모습 (+z 가 "멀리"). 바닥 윗면 `FLOOR_Y = 0`, 복도 벽 안쪽 면 `x = ±110`, 벽 높이 `WALL_HEIGHT = 60`.

```
 z = 3600  ── 맵 끝 벽 ──────────────────────────  MAP_END_Z
 z = 3360~3600  15 유령 성
   ...          (구역 하나 = 복도 폭 220 × 길이 240, 사이에 벽·문 없음)
 z = 240~480    2 호수
 z = 0~240      1 숲
 z = 0     ══ 안전 구역 경계 (밤 벽 1장, "안전 구역" 글씨·점선) ══  SAFE_ZONE_Z
 z = -290~0     허브 (안전 구역): 베이스 7개가 양옆 벽에 붙어 복도 가운데를 바라봄
                왼쪽(x<0) 4개: z -40, -110, -180, -250 / 오른쪽(x>0) 3개: z -40, -110, -180
                오른쪽 z -250 자리 = 판매 가게·트레일 상점·이벤트 포털 (hubSpots)
 z = -290  ── 허브 뒤 흰 벽 ──
```

| 이름 | 값 / 모양 | 쓰는 곳 |
|---|---|---|
| `CORRIDOR_WIDTH`, `HALF_WIDTH`, `WALL_HEIGHT`, `FLOOR_Y` | 220, 110, 60, 0 | 바닥·벽 |
| `HUB` | `{ zMin = -290, zMax = 0 }` | 허브 바닥·뒤 벽 |
| `SAFE_ZONE_Z` | 0 | 허브 경계 (z < 0 = 안전) |
| `BIOME_LENGTH`, `MAP_END_Z` | 240, 3600 | 구역 바닥 |
| `biomes[i]` | `{ id, index, zMin, zMax, centerZ, name, nameEn }` 15개 (Biomes.list 순서) | 구역 바닥·표지판 |
| `NIGHT_WALL` | `{ z = 0, xMin = -110, xMax = 110, height = 60, thickness = 2 }` | NightWall 태그 파트 |
| `plots[i]` (`plot(i)`) | `{ index, side "left"/"right", center {x,z}, size {w=60(z 방향), d=70(x 방향)}, facing (+1 = +x 를 봄 / -1), rect, penRect, yardRect, spawn, treadmill, sellStall, signs = { owner, penUpgrade, treadmillUpgrade } }` | 베이스 전부 |
| `penRect(i)` | 정원(5판 우리) = 뒤쪽 46 (벽 쪽) | 울타리·정원 바닥 · **6판: 씨앗을 심는 곳 (PlaceEgg) = 성체 식물이 서 있는 곳**, 열매 따기·먹이기·성체 팔기·물 주기 거리(20)도 이 사각형 기준 |
| `petRect(i)` | 우리 뒤쪽 (울타리 쪽 16 빼고, 가장자리 3 여유) | [6판: 서버는 안 씀 — 성체는 심은 자리(`PetRecord.x, z`)에 GardenPlant 파트로] |
| **`toLocal(i, pos)` / `toWorld(i, lx, lz)`** (2판 수정) | 베이스 기준 좌표 ↔ 월드. `lx = (x - 가운데 x) × facing` (+35 = 복도 쪽 앞 가장자리, -35 = 뒤 벽), `lz = z - 가운데 z`. 왼쪽·오른쪽 베이스가 거울이라 로컬 모양이 같음 | `snap.incubators[].x, z` 가 이 좌표 → 월드는 `toWorld(PlotIndex, x, z)` |
| **`PEN_LOCAL`**, `isInPenLocal(lx, lz, inset?)` | 우리를 로컬로: `lx -35 ~ 11, lz -30 ~ 30` (모든 베이스 같음) | 씨앗 심기 미리보기 |
| `eggGridLocal(n)` (1~20) | 정원 안 격자 (울타리 쪽부터 4칸씩, 줄 7·칸 14 간격). 1~8 = 옛 부화 슬롯 자리 | 저장 변환·깨진 자리 보정 (서버) |
| `incubatorSpots(i)` | **[옛 받침 — 서버는 안 씀]** `eggGridLocal(1~8)` 의 월드 자리 | MapBuilder 가 아직 받침(IncubatorSlot)을 지음 → 받침 지우면 같이 지움 |
| `TREADMILL_PAD`, `treadmillRect(i)` | `{ sizeX = 12, sizeZ = 8 }` (x 방향으로 달림), plot.treadmill 중심 | **러닝머신 벨트 파트는 정확히 이 크기·자리** |
| `nestsFor(biomeId)` | 8개 `{x,z}` (벽·구역 경계에서 20 이상, 경비 집에서 60 이상, 짝수 구역은 좌우 뒤집힘) | Nest 태그 파트 (NestIndex = 순서) |
| `guardHome(biomeId)` | `{ x = 0, z = centerZ }` | 경비가 자는 자리 (서버가 경비를 여기 만듦) |
| `hubSpots` | `mainSpawn (0,-140)`, `sellStall (60,-232)` (판매 가판대: 열매 팔기·성체 팔기), `trailShop (60,-268)`, `eventPortal (92,-250)`, `safeLine (0,0)` | 허브 시설 |
| `specials` | `sakuraIncubator` (벚꽃 구역 **사쿠라 나무**, 6판 씨앗 버전) `{ biomeId, x, z }` 하나뿐 (6판: 제단 `altarLight`·`altarDark`·비밀 통로 `shrine` 없앰, 5판: `questGate` 없앰) | 특수 장소 (같은 태그로 지으면 서버 임시 파트 안 생김) |

판정 함수 (위치는 `Vector3` 또는 `{x=, z=}` 둘 다 됨):

| 함수 | 뜻 |
|---|---|
| `zoneAt(z)` / `zoneAtPos(pos)` | 구역 id \| `"hub"`(z < 0, 허브 뒤 벽 앞까지) \| `nil`(맵 밖). 경계 z = 0 은 숲, z = 240 은 호수 |
| `isInHub(pos)` | 허브(안전 구역) 안 → **2판 수정: 배달 판정** (알을 든 채 들어오면 가방으로) |
| `isInPlot(pos, i)` | 베이스 i 영역(앞마당 + 정원) 안 (PlaceEgg "내 베이스 안에 서 있음") |
| `isInPen(pos, i, inset?)`, `plotAt(pos)` | 우리 안 (inset 만큼 울타리 안쪽까지만) / 위치가 든 베이스 번호 |
| `isOnTreadmill(pos, i, margin?)` | 베이스 i 러닝머신 벨트 위 |
| `sellSpots()` | 판매 자리 전부 (허브 1 + 베이스 7) — SellFruits·SellPlant |
| `inRect / rectCenter / rectSize` | 사각형 도우미 |

---

## 1. 서버 → 클라 (클라가 받는 이벤트)

| 이름 | 언제 | 인자 (payload) |
|---|---|---|
| `Snapshot` | 접속해서 데이터를 불러온 직후, `RequestSnapshot` 요청 때, 늦게 베이스를 받았을 때 | `Types.Snapshot` 전체 (아래 4장) |
| `DataUpdate` | 상태 일부가 바뀔 때 | `(section: string, payload: table)` — 5장 표. `State` 모듈이 자동으로 합쳐 줌 |
| `Notify` | 성공/실패 안내 한 줄 | `{ kind: "info" \| "success" \| "error", text: string }` — 6판: 글은 "씨앗·정원·성체·열매·코인" 말로 옴 |
| `Announce` | 서버 전체 공지 (채팅에도 표시됨) | `{ kind, text, ... }` — kind: `"reset"`("ALL SEED RESET! 모든 씨앗이 새로 놓였어요!"), `"rareEgg"`(초기화 공지 씨앗: + `biomeId, petId, rarity, eggUid`, text "OO 구역에 비밀 룬 장미 씨앗 등장!"), `"night"`, `"day"` |
| `PhaseChanged` | 낮/밤/대기 바뀔 때 | `{ phase: "Day"\|"Night"\|"Intermission", endsAt: number, duration: number, cycleNumber: number, heavenSide: "light"\|"dark"\|nil }` — `endsAt` 은 `workspace:GetServerTimeNow()` 기준 |
| `RunAlert` | 내가 씨앗을 든 순간 ("달리기!!") | `{ egg: EggInfo, guardName: string, guardSpeed: number, yourSpeed: number, weightKg: number }` — `guardName` = 그 구역 식물 괴물 이름 (`Biomes.guardName`, 예 "덥석 파리지옥"). 따돌림 조건 `SpeedMath.canEscape(guardSpeed, yourSpeed)` 그대로 |
| `ChaseEnded` | 나를 쫓던 경비가 멈춤 | `{ biomeId: string, reason: "safe"\|"caught"\|"dropped"\|"night"\|"other" }` — safe = 허브에 들어옴(= 배달) |
| `Caught` | 경비에게 잡힘 / 무기에 맞음 / 곰덫 밟음 | `{ cause: "guard"\|"player"\|"trap", by: string, eggOutcome: "ReturnToNest"\|"DropHere"\|"None", ragdollSeconds: number, knockback: Vector3?, stunSeconds: number? }` |
| `EggDelivered` | 씨앗을 든 채 허브(z < 0)에 들어와 **씨앗 가방**에 들어감 | `BagEgg` (`uid, petId, size, mutations, biomeId, special, progress, required`) |
| `IndexRewarded` | 도감 보상 수령 | `{ petIds: {string}, speed: number, money: number (코인), completeBonus: boolean }` — 6판: 코인 = 열매 1개 값 × 10 |
| `EggGranted` | 선물 씨앗(사쿠라 나무 뽑기·개발 명령 `/seed`)이 **씨앗 가방**에 들어감 | `{ egg: BagEgg, queued: false, source: "sakura"\|"dev" }` (`queued` 는 옛 클라 호환, 항상 false — 지울 예정) |
| `SakuraResult` | 사쿠라 나무에 성체를 바침 / 특별 씨앗을 뽑음 | 바치기: `{ kind: "offered", consumed: plantUid, petId, gained: number, crystals: number }` · 뽑기: `{ kind: "draw", petId, egg: BagEgg, crystals: number }` (뽑은 씨앗은 `EggGranted` 로도 옴) |
| **`ZoneEntered`** (2판) | 새 구역(z 범위)에 들어갈 때 1번 (서버 0.2초 틱). 허브는 안 보냄 | `{ biomeId: string, name: string, nameEn: string }` → 화면 위 가운데 구역 이름 배너 |
| **`TreadmillStep`** (2판) | 러닝머신 위에서 걸음(1초)마다 | `{ amount: number }` — 오른 속도 (= `Economy.treadmillGainPerSecond(레벨)`, 20레벨이면 1,000,000) → "+1M" 분홍 팝업 |
| **`TutorialUpdate`** (5판) | 나에게만: 접속 준비 때(튜토리얼이 안 끝난 사람만) · 단계가 바뀔 때 · `/tutorial reset` | `TutorialView = { step, total, text, hint, done, reward? }` — 6판 단계 글: 1 "숲에서 씨앗 훔치기" · 2 "안전 구역으로 돌아오기" · 3 "핫바에서 씨앗을 골라 정원에 심기" · 4 "성체가 될 때까지 기다리기" · 5 "열매 따서 팔기". 끝 = step 6·done true·`reward = 500`(코인, 끝내는 순간 한 번만) |
| **`LeaderboardUpdate`** (5판) | 10초마다 서버 전체 + 새로 온 사람에게 한 번 | `{ money: { LeaderboardEntry }, speed: { LeaderboardEntry } }` — `LeaderboardEntry = { name, value, userId }`, 큰 값부터 최대 10줄. money = 코인 |
| **`PetPetted`** (5판 → 6판 물 주기) | 누가 `PetPet` 으로 자기 정원 식물(자라는 씨앗 또는 성체)에 물을 줌 (서버 전체) | `(ownerUserId: number, uid: string)` — 인자 2개. uid = 자라는 씨앗(`IncubatingEgg` 파트 Attr `EggUid`) 또는 성체(`GardenPlant` 파트 Attr `PlantUid`). **uid 는 사람마다 따로 매겨서 겹칠 수 있으니 파트 Attr `OwnerUserId == ownerUserId` 로 한 번 더 거르세요** → 물방울·소리 |
| **`PlantGrown`** (6판) | 정원에 심은 씨앗이 **그 자리에서 성체가 됨** (1초 틱 · 건너뛰기 · 물 주기 다음 틱 · 접속 때 오프라인 성장 — 접속 때는 `Notify` 는 한 번에 모아서 1줄) | `{ plant: PetRecord, isNew: boolean (도감 첫 발견), fruitValue: number (열매 1개 값), fruitInterval: number (초) }` — 같은 uid 의 `IncubatingEgg` 파트가 없어지고 `GardenPlant` 파트가 생김. 열매 `Config.FRUITS_ON_ADULT`(1)개 달린 채 |
| **`FruitPicked`** (6판) | `PickFruit` 로 열매를 따서 열매 가방에 넣음 — **식물마다 1번** (`"all"` 이면 여러 번) | `{ plantUid: string, petId: string, count: number, value: number (이번에 딴 열매 값 합, 코인) }` → 그 식물(`GardenPlant` Attr `PlantUid`) 위 "+열매 3" 팝업 |
| **`FruitsSold`** (6판) | 판매 가판대에서 `SellFruits` 로 열매를 팜 | `{ count: number, coins: number }` (코인 2배 게임패스면 이미 × 2) — `Notify` success 도 같이 옴 |
| **`FeedResult`** (6판) | `FeedFruit` 결과 (열매는 먹었음) | `{ plantUid: string, fruitId: string, mutation: string? }` — `mutation` = 새로 붙은(또는 더 좋은 것으로 바뀐) 돌연변이 id, nil = 이번엔 안 붙음. `Notify` 도 같이 옴 |

`EggInfo` = `{ uid, petId, biomeId, rarity, size, mutations: {string}, special: boolean }` (`petId` = 식물 id)

`BagEgg` (가방 속 씨앗) = `{ uid, petId, size, mutations, biomeId, special, progress, required }` — 가방 속에서는 안 자람 (정원에서 다시 주운 씨앗은 자란 만큼 남음)
`IncubatorRecord` (정원에 심어 자라는 씨앗) = `{ uid, petId, size, mutations, biomeId, special, x, z, progress, required }` — `x, z` = 베이스 기준 좌표 (`MapLayout.toWorld(PlotIndex, x, z)` → 월드). 성장 단계 = `GardenRules.stage(progress, required)` (`"sprout"` 0% · `"stem"` 25% · `"bud"` 60% · `"adult"` 100%), 이름 `GardenRules.stageName` (새싹·줄기·봉오리·성체)
`PetRecord` (정원의 성체 식물) = `{ uid, petId, size, mutations, x, z, fruits, fruitProgress }` — 심은 씨앗과 **같은 uid·같은 자리**. `fruits` = 달린 열매 수(0 ~ `Config.FRUIT_MAX_PER_PLANT` 5), `fruitProgress` = 다음 열매까지 쌓인 초 (간격 = `Economy.fruitInterval(petId)`)
`FruitBag` (열매 가방) = `{ [식물 id]: { count: number, value: number (그 칸 열매 값 합) } }` — 같은 식물 열매끼리 한 칸, 다 합쳐 최대 `Config.FRUIT_BAG_MAX` 300개. 개수 `FruitRules.bagCount`, 값 `FruitRules.bagValue`

## 2. 클라 → 서버 (클라가 보내는 요청)

| 이름 | 인자 | 서버 검증 | 레이트 리밋 (burst / 초당) |
|---|---|---|---|
| `RequestSnapshot` | 없음 | — | 3 / 0.5 |
| `PurchaseUpgrade` | `kind: "Pen"\|"Treadmill"\|"Trail"`, `trailId: string?` (Trail 일 때만) | 종류·id 허용 목록, 다음 레벨 있는지, 코인 충분한지 (상점 화면 버튼이라 거리 검사 없음). `"Pen"` = 6판 **정원 업그레이드**(칸 7 → 18). 러닝머신은 **20레벨까지** (6판). 트레일은 사면 바로 장착 | 5 / 2 |
| `UseTool` | `kind`: `"Bat"\|"BearTrap"\|"WaterBat"\|"Katana"\|"Axe"\|"AngelSpear"\|"Hammer"\|"CandyCane"\|"Scythe"` (`Remotes.ToolKinds`) | 그 도구를 손에 들고 있는지, 구역 무기는 해금했는지, 근접 무기 공용 쿨다운, **허브(안전 구역)가 아닌지**, 곰덫 개수. 대상·위치는 서버가 찾음 | 4 / 2 |
| `ClaimIndexReward` | `"all"` 또는 식물 id | 발견했고(= 한 번이라도 성체가 됨) 아직 안 받았는지 | 5 / 1 |
| `SakuraOffer` | `plantUid: string` (내 정원의 **성체** uid) | 사쿠라 나무(`SakuraIncubator` 파트 표면) 14 스터드 안, 내 정원의 성체인지 (자라는 씨앗은 안 됨). 통과: 그 성체가 없어지고(정원 자리가 빔) 크리스탈 +등급별(`Config.SAKURA_OFFER_CRYSTALS`: 일반 1 … 비밀 20 … 슈퍼 울트라디바인 100) → `SakuraResult` offered + `Notify` + `DataUpdate("pets")`·`DataUpdate("special")` | 3 / 1 |
| **`DropEgg`** (2판) | 없음 | 씨앗을 들고 있는지. 씨앗은 그 자리에 떨어짐 → 경비 추격 끝(`ChaseEnded` dropped), 60초 뒤 사라짐 | 2 / 1 |
| **`TreadmillLeave`** (2판) | 없음 | 러닝머신 위인지. 내려서 벨트 앞으로 옮겨 줌. **클라가 러닝머신 위에서 점프할 때 보내세요** (`OnTreadmill` 이 true 일 때) | 3 / 2 |
| **`EquipTrail`** (2판 마무리) | `trailId: string` 또는 `"none"` | 허용 목록, 가진 트레일인지. 바꾸면 저장 + 속도 다시 계산 + `DataUpdate("upgrades")` + `Notify` | 5 / 2 |
| **`PlaceEgg`** (6판: 씨앗 심기) | `eggUid: string`, `x: number`, `z: number` (심을 자리 = **월드** x, z — 정원 바닥을 클릭/터치한 점) | uid 형식·x·z 유한한 숫자, **가방에 그 씨앗**, 내 베이스가 있음, **정원에 빈칸** (자라는 씨앗 + 성체 < 정원 칸 수 `Economy.penSlots(penLevel)`, `GardenRules.hasRoom`), 내가 내 베이스 안에 서 있거나 그 자리 14 안, 그 자리가 내 정원 안(울타리에서 2 안쪽), **다른 자라는 씨앗·성체 식물과 간격** (`EggPlacement`, 크기별 지름). 성공: 가방 → `incubators`, 그 자리에 `IncubatingEgg` 파트(Stage `"sprout"`), `DataUpdate("eggs")` + `DataUpdate("incubators")`. 실패: `Notify` error (`EggPlacement.message`, 예 "정원이 가득 찼어요") | 5 / 3 |
| **`PickUpPlacedEgg`** | `eggUid: string` (정원에서 **아직 자라는** 씨앗) | `Config.ALLOW_EGG_PICKUP`, 내 정원에 심은 씨앗, 가방에 빈칸. 자란 만큼 그대로 가방으로 (성체는 못 주움 → 팔기·바치기) | 5 / 3 |
| **`PetPet`** (6판: 물 주기) | `uid: string` — 내 정원의 자라는 씨앗(`IncubatingEgg` Attr `EggUid`) **또는** 성체(`GardenPlant` Attr `PlantUid`) | uid 형식, 내 정원의 것, 살아 있는 내 캐릭터가 **내 정원(`MapLayout.penRect`)에서 20 스터드 안**, 사람마다 1초(`PET_PET_COOLDOWN`), **식물마다 60초**(`Config.WATER_COOLDOWN`, 아직이면 `Notify` info "이 식물은 n초 뒤에…"). 효과: 씨앗은 성장 +10초(`WATER_GROWTH_SECONDS`, 다 자라면 다음 1초 틱에 성체), 성체는 다음 열매까지 +10초(열매가 5개면 효과 없음). 통과하면 `PetPetted(ownerUserId, uid)` 를 서버 전체에 | 3 / 2 |
| **`PickFruit`** (6판) | `plantUid: string` 또는 `"all"` | 내 정원(`penRect`)에서 **20 스터드 안**(`Config.GARDEN_ACTION_RADIUS`), uid 면 내 정원의 성체인지(아니면 조용히 무시). 그 성체(들)의 열매를 전부 **열매 가방 자리만큼** 땀 (열매 1개 값 = 딸 때 크기·돌연변이 반영, `FruitRules.fruitValue`). → 식물마다 `FruitPicked` + `DataUpdate("fruits")` + `DataUpdate("pets")`. 열매가 없으면 `Notify` info, 가방이 가득 차면 `Notify` error | 10 / 5 |
| **`SellFruits`** (6판) | 없음 | **판매 가판대 14 스터드 안** (`SellStall` 태그 파트 표면 또는 `MapLayout.sellSpots()` — 허브 1 + 베이스마다 1), 가방에 열매가 1개 이상. 가방을 전부 팖 → 코인 (`FruitRules.bagValue` × 코인 2배 게임패스) → `FruitsSold` + `Notify` + `DataUpdate("fruits")`. 튜토리얼 5단계는 이걸로 끝남 | 3 / 1 |
| **`FeedFruit`** (6판) | `plantUid: string`, `fruitId: string` (열매 가방의 칸 = 그 열매를 맺은 **식물 id**) | 내 정원 20 안, 내 정원의 성체, 가방에 그 열매가 1개 이상, **붙을 수 있는 돌연변이가 남아 있음** (`FruitRules.feedOptions(fruitId, plant.mutations)` 가 비면 거부 — 열매 그대로, `Notify` error). 통과: 열매 1개를 먹고 `FruitRules.rollFeed` 확률로 돌연변이 1개 (자연: 황금·무지개는 더 좋은 것으로만 바뀜 / 원소: 얼음·불·번개 중 하나만, 그 구역 열매면 ×3, 높은 등급 열매일수록 ↑, 합 상한 90%) → `FeedResult` + `Notify` + `DataUpdate("fruits"/"pets")`. 미리보기 확률은 `FruitRules.feedChance` | 5 / 2 |
| **`SkipGrowth`** (6판) | `eggUid: string` (정원에서 자라는 씨앗), `mode: "all"\|"half"` (`Remotes.SkipModes`) | 내 정원의 자라는 씨앗, 남은 시간 > 0, **코인 충분** (가격 = `GardenRules.skipCost(petId, progress, required, mode)` = 올림(건너뛸 분) × 10 코인 × 등급 배수, 일반 1 … 슈퍼 울트라디바인 500. 남은 시간은 씨앗 위 타이머 숫자(밤에도 같은 "성장 초")). `"all"` 이면 바로 성체(`PlantGrown`), `"half"` 면 남은 시간 절반. 화면 버튼이라 거리 검사 없음. 코인 부족은 `Notify` error | 5 / 2 |
| **`SellPlant`** (6판, 5판 `SellPet` 자리) | `plantUid: string` (내 정원의 **성체**) | 내 정원 20 안 **또는** 판매 가판대 14 안, 내 정원의 성체. 값 = 열매 1개 값 × 20 (`GardenRules.sellPrice(plant)`, 코인 2배 게임패스면 × 2) → 정원 자리가 빔 (달린 열매도 같이 없어짐 — 먼저 따세요) → `Notify` + `DataUpdate("pets")` | 10 / 4 |
| **`SakuraDraw`** (6판) | 없음 | 사쿠라 나무 14 안, 크리스탈 ≥ `Config.SAKURA_DRAW_COST`(10), 씨앗 가방에 빈칸 (가득 차면 거부, 크리스탈 그대로). 뽑기: 벚꽃 씨앗(벚꽃 요정 나무·코스믹) 97.5% / 정령 벚꽃 씨앗(정령 벚꽃 나무·비밀) 2.5% (`Config.SAKURA_SEEDS`), 크기·자연 돌연변이는 둥지 씨앗처럼 → `EggGranted`(source `"sakura"`) + `SakuraResult` draw | 5 / 2 |

- **씨앗 줍기**는 Remote 가 아니라 서버가 만든 `ProximityPrompt`(E 키, 씨앗 파트 안의 `StealPrompt`)로 합니다. 서버가 거리·낮인지·이미 들고 있는지 확인합니다.
- **사쿠라 크리스탈 줍기**도 `ProximityPrompt`(크리스탈 파트 안의 `CrystalPrompt`). 서버가 거리 확인. 벚꽃 구역 씨앗을 배달할 때마다 크리스탈 +1.
- **배달**도 Remote 없음: 씨앗을 든 채 **허브(안전 구역, `MapLayout.isInHub` = z < 0)에 들어오는 순간** 서버가 자동 처리 → 씨앗 가방으로 (`EggDelivered`). 가방이 가득 차면 씨앗은 손에 그대로 + 3초에 한 번 안내.
- **정원에 씨앗 심기**: 클라가 할 일 = 씨앗 창(핫바/가방, `snap.eggs`)에서 씨앗 고르기 → 심기 모드 → 내 정원 바닥 클릭/터치 → `PlaceEgg(uid, hit.X, hit.Z)`. 미리보기는 `EggPlacement.check(MapLayout.toLocal(PlotIndex, hit).x, ...z, egg.size, 정원 자리들, nil)` 로 초록/빨강 (자리 = 자라는 씨앗 + 성체 `x, z`).
- **성체 되기는 Remote 없음**: 다 자라면 서버가 저절로 바꿈 (`PlantGrown`). 5판 `HatchEgg`·"부화" 버튼은 없어짐.
- **러닝머신**: 내 베이스 러닝머신 벨트에 올라서면 서버가 자동으로 태움 (`OnTreadmill`). 내릴 때만 `TreadmillLeave`.
- 도구: 서버가 Backpack 에 `Tool`(이름 = kind, `RequiresHandle = false`, Attribute `ToolKind`, 무기는 `WeaponId`·`Range`, 곰덫은 `Count`)을 넣어 줌. `ToolController` 가 `Activated` 때 `UseTool` 을 보냄.

## 3. Attribute 로 복제되는 값 (자주 바뀌는 숫자)

### 플레이어 (`Players.LocalPlayer:GetAttribute(...)`, 이름은 `Tags.PlayerAttributes`)

| Attribute | 뜻 |
|---|---|
| `Money` | **코인** (number — 표시할 때 `Format.number(n) .. " 코인"`. `Format.money` 는 아직 "$" 를 붙임 → 선임이 화면 글을 코인으로) |
| `Speed` | 실효 속도 = 모은 속도 × 트레일 배율 (경비 비교에 쓰는 숫자) |
| `BaseSpeed` | 모은 속도 (트레일 전) |
| `WalkSpeed` | 서버가 정한 실제 이동 속도 (러닝머신 위·곰덫 = 0) |
| `PlotIndex` | 내 베이스 번호 (1~7, 0 = 없음). 위치는 `MapLayout.plot(PlotIndex)` |
| `PenLevel`, `PenSlots` | **정원** 레벨, 정원 칸 수 (자라는 씨앗 + 성체가 이만큼까지) |
| `TreadmillLevel` | 러닝머신 레벨 (0 = 잠김, 최대 20) |
| `TrailMultiplier`, `EquippedTrail` | 장착한 트레일 배율 (없으면 1) / id (`"none"` = 없음) |
| `CarryingEgg`, `CarryingBiome` | 든 씨앗 uid / 구역 id (`""` = 없음) |
| `CarryWeightKg` | 든 씨앗 무게(kg, 표시용). 0 = 안 듦 |
| `Stunned` | 래그돌·곰덫 중 |
| `InSafeZone`, `CurrentZone` | 허브(z < 0) 안 / 지금 있는 곳 (구역 id \| `"hub"` \| `""`) |
| `OnTreadmill` | 러닝머신 위에 고정돼 달리는 중 |
| `DataLoaded`, `SaveEnabled` | 데이터 로딩 끝났는지, 저장되는 세션인지 |
| `SakuraCrystals` | 사쿠라 크리스탈 개수 (6판: `SakuraUnlocked` 없앰 — 나무는 처음부터 씀) |
| **`FruitCount`** (6판) | 열매 가방 속 열매 수 → HUD 배지 "열매 12 / 300" (`snap.fruitBagMax`) |
| **`FruitBagValue`** (6판) | 열매 가방을 다 팔면 받는 코인 (게임패스 배율 전) → 판매 가판대 미리보기 |
| `MoveWarnings` | 비정상 이동 경고 수 (5 = Kick) |

(6판에서 없앰: `IncomePerSecond`, `SakuraUnlocked`.) leaderstats 에는 `코인`, `Speed` 가 보기 좋은 글자(StringValue, 예 `"1.5K"`)로 들어 있습니다.

### 서버 상태 (`ReplicatedStorage.GameState` 폴더, 이름은 `Tags.StateAttributes`)

| Attribute | 뜻 |
|---|---|
| `Phase` | `"Day"` / `"Night"` / `"Intermission"` |
| `PhaseEndsAt` | 끝나는 시각 (`workspace:GetServerTimeNow()` 기준) |
| `PhaseDuration` | 이번 단계 길이(초) |
| `CycleNumber` | 몇 번째 주기 |
| `HeavenSide` | 천사&악마 구역 이번 쪽 `"light"` / `"dark"` (둥지 씨앗 풀이 바뀜) |

### 월드 오브젝트 Attribute / 태그 (UI·연출용, 이름은 `Tags`)

- **경비 모델**(`Guardian` 태그, 6판: 식물 괴물 — 이름만 바뀌고 규칙 그대로): `BiomeId`, `GuardName`(예 "덥석 파리지옥"), `State` = `"Sleeping"` / `"Chase"` / `"Return"`, `TargetUserId`, `CatchDistance`.
- 씨앗 파트(`Egg` 태그 — 둥지·들고 있는·떨어진 씨앗): `EggUid, PetId(식물 id), BiomeId, Rarity, Size, Mutations("golden,frozen" 식), Special, EggState("Nest"/"Carried"/"Dropped"), WeightKg`, 떨어진 씨앗은 `DroppedAt, ExpiresAt`.
- **자라는 씨앗**(`IncubatingEgg` 태그): 내 정원 바닥, 심은 자리 (`MapLayout.toWorld(PlotIndex, record.x, record.z)`). `EggUid, OwnerUserId, PlotIndex, PetId, Size, Mutations, Special, Progress, Required, Ready`, **`Stage`**(6판: `"sprout"`/`"stem"`/`"bud"`) — 1초마다 갱신. 머리 위 남은 시간 = `(Required - Progress) / 성장 속도`(밤 30배). 서버는 단순한 공 + 이름표만 만듦 → **씨앗·새싹·줄기·봉오리 모양은 선임**. 다 자라면 이 파트는 지워지고 같은 자리에 `GardenPlant` 가 생김.
- **성체 식물**(`GardenPlant` 태그, 6판): `PlantUid, OwnerUserId, PlotIndex, PetId, Size, Mutations, Stage("adult"), Fruits, FruitMax, FruitValue(열매 1개 값), FruitInterval(초), FruitProgress` — 1초마다 갱신. 다음 열매까지 = `FruitInterval - FruitProgress` 초 (Fruits == FruitMax 면 멈춤). 서버는 단순한 파트 + 이름표만 → **식물 모양·열매 달린 모습·아우라는 선임**.
- **특수 장소** — 자리는 `MapLayout.specials`. 맵에 같은 태그 파트가 있으면 그걸 쓰고, 없으면 서버가 임시 파트(`Placeholder = true`)를 만듦. 6판에는 **`SakuraIncubator`(사쿠라 나무) 하나뿐**. `SakuraCrystal`(서버가 만듦): 초기화 때 벚꽃 둥지 근처 3개, 안에 `CrystalPrompt`.
- **`SellStall`** (판매 가판대: 허브 `hubSpots.sellStall` + 베이스마다 `plot.sellStall`) — `SellFruits`·`SellPlant` 거리 기준. `Treadmill` (Attr `PlotIndex`, `MapLayout.treadmillRect`).
- `NightWall`: 허브 경계 z = 0 에 1장. `DeliveryPad`·`IncubatorSlot`: 안 씀 (태그 이름만 남아 있음).
- (6판에서 없앰: `FusionMachine`, `Altar`, `Shrine`. 5판 `PenPet` 모델 — `PetVisualService` 는 6판에 정원 펫을 안 만듦, 8장)

## 4. Snapshot 모양 (`Types.Snapshot`)

```
money (코인), speed, effectiveSpeed,
pets: { PetRecord },               -- 6판: 정원의 성체 식물 (x, z, fruits, fruitProgress)
penLevel, penSlots,                -- 정원 레벨 / 칸 수 (자라는 씨앗 + 성체 합의 상한)
treadmillLevel,                    -- 0 ~ 20
trails: { trailId }, equippedTrail (trailId | "none"), trailMultiplier,
indexDiscovered: { [plantId]: true }, indexClaimed: { [plantId]: true }, indexCompleteClaimed,
unlockedWeapons: { weaponId },
tools: { bearTrap = n },
incubators: { IncubatorRecord },   -- 정원에 심어 자라는 씨앗 (x, z = 베이스 기준 좌표)
eggs: { BagEgg },                  -- 씨앗 가방 (최대 eggInventoryMax = 50)
eggInventoryMax,
placedEggMax,                      -- [호환] = penSlots (선임이 안 쓰게 되면 수석이 지움)
fruits: FruitBag,                  -- 6판: 열매 가방 { [plantId]: { count, value } }
fruitBagMax,                       -- 6판: 300
plotIndex, saveEnabled,
sakuraCrystals,
tutorial: TutorialView             -- { step, total, text, hint, done } (끝난 사람은 done = true, step 6)
-- 6판에서 없앰: incomePerSecond, equipped, sakuraUnlocked, shrineUsed, petInventoryMax
```

## 5. DataUpdate 섹션

| section | payload |
|---|---|
| `"pets"` | `{ pets, penSlots }` — 정원의 성체 (성체가 됨·열매가 맺힘/따짐·먹이기·팔기·바치기·물 주기 때). 6판: `equipped`·`incomePerSecond` 없음 |
| `"incubators"` | `{ incubators }` — 자라는 씨앗 (심기·다시 줍기·성체가 됨·건너뛰기·물 주기 때) |
| `"eggs"` | `{ eggs }` — 씨앗 가방 (배달·선물 씨앗·심기·다시 줍기 때) |
| **`"fruits"`** (6판) | `{ fruits }` — 열매 가방 (따기·팔기·먹이기·개발 명령 `/fruit`) |
| `"index"` | `{ indexDiscovered, indexClaimed, indexCompleteClaimed, unlockedWeapons }` |
| `"upgrades"` | `{ penLevel, penSlots, placedEggMax, treadmillLevel, trails, equippedTrail, trailMultiplier }` |
| `"tools"` | `{ tools }` |
| `"special"` | `{ sakuraCrystals }` (6판: `sakuraUnlocked`·`shrineUsed` 없음) |
| `"tutorial"` | `{ tutorial = TutorialView }` |

## 6. 화면별로 필요한 것 (6판)

| 화면 | 쓸 것 |
|---|---|
| 왼쪽 아래 신발+속도 / 코인 | Attr `Speed`, `Money` (코인) |
| 열매 가방 배지 | Attr `FruitCount` / `snap.fruitBagMax`, `FruitBagValue` |
| 오른쪽 아래 달·해 + 남은 시간 | GameState `Phase`, `PhaseEndsAt` |
| 위 가운데 구역 이름 배너 | `ZoneEntered` (+ Attr `CurrentZone`) |
| "달리기!!" 배너 + 경비(식물 괴물) 거리 | `RunAlert`(guardName), `ChaseEnded`, Attr `CarryingEgg`, 경비 `TargetUserId` |
| 아래 빨간 "드롭" 버튼 | Attr `CarryingEgg ~= ""` → `DropEgg()` |
| 핫바 (1 방망이, 2 곰덫, 3 씨앗) · 씨앗 가방 창 | Backpack Tool + `State.get().eggs` → 씨앗 고르기 → 정원 바닥 → `PlaceEgg(uid, x, z)` (미리보기 `EggPlacement.check`), 정원 `#incubators + #pets / penSlots`, 가방 `#eggs / eggInventoryMax` |
| 자라는 씨앗 (정원 위 + "자라는 씨앗" 패널) | `IncubatingEgg` 파트 `Stage`/`Progress`/`Required` 또는 `State.get().incubators` + `GardenRules.stage/stageName`, **건너뛰기 버튼 "전부 / 절반"** + 가격 `GardenRules.skipCost(petId, progress, required, mode)` → `SkipGrowth(uid, mode)`, 다시 줍기 → `PickUpPlacedEgg(uid)`, 물 주기 → `PetPet(uid)` |
| 성체가 됨 연출 | `PlantGrown { plant, isNew, fruitValue, fruitInterval }` (5판 부화 카드 자리 — `HatchController` 가 임시로 같은 카드) |
| 성체 식물 (정원 위) | `GardenPlant` 파트 (`Fruits`/`FruitMax`, `FruitInterval - FruitProgress`) + ProximityPrompt "열매 따기" → `PickFruit(PlantUid)`, "물 주기" → `PetPet(PlantUid)`, "+열매" 팝업 `FruitPicked` |
| 정원 식물 창 (5판 펫 보관함 자리) | `State.get().pets` — 식물마다 열매 수·열매 1개 값(`FruitRules.fruitValue`)·다음 열매, "모두 따기" → `PickFruit("all")`, "뽑아서 팔기" → `SellPlant(uid)` (가격 `GardenRules.sellPrice`), "열매 먹이기" → `FeedFruit(uid, fruitId)` |
| 열매 가방 창 | `State.get().fruits` — 칸마다 식물 이름·개수·값, 먹이기 미리보기 `FruitRules.feedOptions(fruitId, plant.mutations)` · `FruitRules.feedChance`, 결과 `FeedResult` |
| 판매 가판대 | `SellStall` 근처(14) ProximityPrompt "열매 팔기 (12개 · 3.4K 코인)" → `SellFruits()`, 결과 `FruitsSold { count, coins }` |
| 도감(인덱스) + 모두 획득 | `indexDiscovered/indexClaimed` (식물 id), `Progression.biomeProgress`, `ClaimIndexReward("all")`. 보상 코인 = 열매 1개 값 × 10 |
| 상점 (정원/러닝머신/트레일) | `Upgrades` + `Economy.nextPenCost/nextTreadmillCost`, `PurchaseUpgrade(kind, id)`. 러닝머신 **20레벨**, 1초 속도 `Economy.treadmillGainPerSecond(level)` |
| 사쿠라 나무 | 근처(14)에서 "성체 바치기" → 정원 성체 고르기 → `SakuraOffer(plantUid)` / "씨앗 뽑기 (크리스탈 10)" → `SakuraDraw()`, 결과 `SakuraResult`, Attr `SakuraCrystals` |
| 튜토리얼 패널 | `TutorialUpdate` / `State.get().tutorial`: "n / 5" + `text` + `hint`, `done` 이면 숨김, 끝내는 순간 `reward`(500 코인) 축하. 화살표: 1 숲 둥지 · 2 허브 경계 · 3 핫바 씨앗 + 내 정원 · 4 자라는 씨앗 · 5 성체 열매 → 판매 가판대 |
| 랭킹판 | `LeaderboardUpdate { money, speed }` (money = 코인) |
| 채팅 공지 / 잡힘 | `Announce`("ALL SEED RESET!", 공지 씨앗), `Caught` |

## 7. 6판 규칙 요약 (자세한 건 코드 맨 위 주석)

- **속도 → 걷기·경비·잡힘·떨어진 씨앗·배달·밤 귀가·치트 방지**: 5판 그대로 (`SpeedMath`, `GuardianService`, `EggRules`, `BaseService`, `AntiCheatService`). 경비는 이름만 식물 괴물.
- **둥지 씨앗** (`EggService`, `EggRoll`, `Data/EggSpawn`): 구역마다 등급 가중치(`BIOME_RARITY_WEIGHTS`, SEED 12장) → 그 등급 식물 중 고르게. 초기화 때 특별 추첨(슈퍼 울트라디바인 0.5% · 신성 0.2% · 영원 2% · 비밀 8%)과 공지 씨앗(춤추는 버섯·세계수·황혼 꽃·균형의 나무)은 전체 공지. 자연 돌연변이 실버 5% · 황금 2% · 무지개 0.5%.
- **정원** (`BaseService`, `shared/GardenRules`, `shared/EggPlacement`): 칸 = 정원 업그레이드 칸 수(7 → 18) = 자라는 씨앗 + 성체. 심은 씨앗만 자람(밤 30배, 게임패스 2배, 오프라인 24시간까지). 단계 새싹 0% · 줄기 25% · 봉오리 60% · 성체 100%. 다 자라면 그 자리에서 성체 + 도감 발견 + 열매 1개.
- **열매** (`FruitService`, `shared/FruitRules`): 성체마다 `fruitIntervalSeconds`(Data/Plants, 일반 30초 … 슈퍼 9초)마다 +1, 최대 5. 밤에도 빠르기 그대로, 오프라인에도 맺음. 열매 1개 값 = 식물 열매 값 × 크기(보통 1 · 큼 1.5 · 거대 3 · 초거대 6) × 돌연변이(곱). 가방 300개. **자동 수입 없음**.
- **건너뛰기** (`GardenRules.skipCost`): 올림(남은 분) × 10 코인 × 등급 배수 (전부 / 절반).
- **성체 팔기** (`GardenRules.sellPrice`): 열매 1개 값 × 20. **물 주기**: +10초, 식물마다 60초.
- **열매 먹이기 돌연변이** (`Data/Mutations` + `FruitRules`): 자연(황금 4% · 무지개 1% — 더 좋은 것으로만) · 원소(얼음 5% · 불 5% · 번개 3% — 하나만). 그 구역 열매 ×3, 열매 등급 보너스 1 + (등급 순서 - 1) × 0.1, 합 상한 90%.
- **사쿠라 나무** (`SakuraService`, `shared/SakuraRules`): 성체 바치기 → 크리스탈, 10개 → 특별 씨앗 뽑기 (97.5% / 2.5%).
- **러닝머신** (`TreadmillService`): 1초마다 속도 += 걸음당 속도 × 4 (`Config.TREADMILL_MULTIPLIER`) + `TreadmillStep`. 20레벨 = 1초 1,000,000.
- **튜토리얼** (`TutorialService`, `shared/TutorialRules`, `Data/Tutorial`): 줍기 1→2, 놓침 2→1, 배달 →3, 심기 3→4, 다시 줍기로 정원이 비면 4→3, 성체 →5, 열매 팔기 5→끝(+500 코인). 튜토리얼 씨앗 = 숲 강아지풀(3초).
- **개발 명령** (Studio·허용 목록만, `DevCommands`): `/coins n`(= `/money`), `/speed n`, `/seed 식물id`(씨앗 가방에), `/plant 식물id 개수`(정원 빈자리에 바로 성체, 열매 1개), `/fruit 개수 [식물id]`(열매 가방에), `/grow`(자라는 씨앗 전부 성체), `/skip`(지금 낮/밤/대기를 바로 끝냄), `/trap n`, `/crystal n`, `/tutorial reset`, `/zone 구역id`.

## 8. 선임 할 일 (6판 체크리스트)

서버·공유 규칙은 끝남. 아래는 화면·모양·소리 (지금은 수석이 클라를 **안 깨질 만큼만** 고쳐 둠 — `[6판 수석 임시]` 주석이 붙은 곳).

**새 Remote 붙이기** (붙이면 `tests/crossrefs.spec.luau` 의 `AWAITING_CLIENT` 에서 그 이름을 지우세요 — 안 지우면 테스트가 알려 줌)
- [ ] **`SellFruits()`**: 판매 가판대(`SellStall` 태그, 허브 + 베이스마다)에 ProximityPrompt "열매 팔기" — 글에 `FruitCount`·`FruitBagValue` (예 "열매 12개 · 3.4K 코인"). `FruitsSold { count, coins }` → "+3.4K 코인" 연출·소리 (`SoundController` 에 임시 소리 있음)
- [ ] **`SkipGrowth(uid, "all" | "half")`**: 자라는 씨앗 패널(`IncubatorController`)·씨앗 위에 "건너뛰기" 버튼 2개 + 가격 `GardenRules.skipCost(petId, progress, required, mode)` (코인이 모자라면 회색) + 확인 창. 남은 시간은 1초마다 줄어드니 가격도 1초마다 다시 계산
- [ ] **`FeedFruit(plantUid, fruitId)`**: 열매 가방 창(새로) → 열매 고르기 → 성체 고르기(정원 식물 창 또는 `GardenPlant` 프롬프트). 붙을 수 있는 것 `FruitRules.feedOptions`, 확률 `FruitRules.feedChance` 미리보기, `FeedResult` 연출 (붙으면 반짝 + 돌연변이 색 `Visuals.mutationLooks`, 안 붙으면 "냠냠")

**정원·식물 모양**
- [ ] **자라는 씨앗 모양**: `IncubatingEgg` 파트 Attr `Stage` 로 씨앗(땅에 묻힘) → 새싹 → 줄기 → 봉오리 (지금은 서버가 만든 공 + 이름표). 등급 아우라 `Rarities.aura` (11개: none · lime_glow · blue_sparkle · purple_flame · gold_ring · red_lightning · stardust_swirl · black_mist · white_clock · rainbow_beam · sky_pillar)
- [ ] **성체 식물 모양**: `GardenPlant` 파트 자리에 식물 134종 모델 + 열매(`Fruits` 개수만큼 달림) + 다음 열매 타이머 + 돌연변이 색 (원소 3종 frozen/burning/shocked 모양 `Visuals.mutationLooks` 에 추가됨). 지금 `Visuals.pets` 는 5판 동물 모양을 같은 자리 식물 id 에 임시로 붙여 둔 것 → 식물 모양으로 바꾸기
- [ ] **`PetVisualService` 정원 펫**: 6판에서 `penRecords` 가 빈 표 (정원 펫 모델 안 만듦). 식물 모델을 여기서 만들려면 `data.pets` 의 `x, z`(베이스 기준 → `MapLayout.toWorld`) 자리에 — `GardenPlant` 파트와 같은 자리
- [ ] **`GardenPlant` 프롬프트**: "열매 따기"(E) → `PickFruit(PlantUid)` (지금은 정원 식물 창 버튼만), "물 주기" → `PetPet(PlantUid)`. `IncubatingEgg` 에도 "물 주기" → `PetPet(EggUid)`. **5판 PenPet 모델이 없어져서 지금 물 주기 프롬프트가 화면에 없음** (`PetFxController` 는 PenPet 을 찾음 → `GardenPlant`/`IncubatingEgg` 로 바꾸기)
- [ ] **`PetPetted(ownerUserId, uid)`**: 하트 → **물방울** 연출, 파트 Attr `OwnerUserId` 로 거르기
- [ ] **`FruitPicked { plantUid, count, value }`**: 그 식물 위 "+열매 3" 팝업 (`WorldFxController` 265줄 메모 — 5판 `IncomeTick` 돈 팝업 자리)
- [ ] **경비 = 식물 괴물 모양** (`Visuals.guards`, 이름 `Biomes.guardName`: 덥석 파리지옥 · 연꽃 개구리풀 · 가시 선인장 대장 · 덩굴 호랑이꽃 · 서리 가시나무 · 용암 머리꽃 · 심해 해초 괴물 · 공룡 고사리 · 우주 버섯 거인 · 벚꽃 여우나무 · 돌 거인 나무 · 천사 백합/악마 장미 · 정령 버섯 · 사탕수수 거인 · 호박 머리 덩굴). 둥지 씨앗 모양도 알 → 씨앗
- [ ] **사쿠라 나무** 모양 (`SakuraIncubator`, MapBuilder 이름표 "사쿠라 나무"), 제단·비밀 통로·퓨전 머신 자리는 비어 있음 (MapBuilder 에서 지움)

**창·글**
- [ ] **정원 식물 창** (`PetsController` 다시 꾸미기, 지금은 임시: 장착 버튼 자리에 "열매 따기", 판매 버튼 → `SellPlant`): 칸 `#incubators + #pets / penSlots`, 식물마다 열매·열매 값·다음 열매·팔기 가격·먹이기. `PetPicker` 의 `equipped`/장착 정렬 정리
- [ ] **자라는 씨앗 패널** (`IncubatorController`): 5판 "Hatch" 버튼 자리 정리(지금은 토스트), 단계 이름 `GardenRules.stageName`, `snap.placedEggMax` 대신 `penSlots`, `record.slot` 안 쓰기 → 다 되면 수석이 `placedEggMax`·`IncubatorRecord.slot` 을 지움
- [ ] **성체 카드** (`HatchController` — 지금 `PlantGrown` 을 5판 부화 카드로 임시 표시): "성체가 됐어요!" + 열매 1개 값 · 열매 간격
- [ ] **열매 가방 HUD 배지** (`FruitCount / fruitBagMax`) + 열매 가방 창
- [ ] **사쿠라 창** (`SakuraController` 임시: 크리스탈 ≥ 10 이면 "씨앗 뽑기", 아니면 "성체 바치기") → 두 버튼 + 바칠 성체 고르기 + 등급별 크리스탈 미리보기 `SakuraRules.crystalsFor`
- [ ] **도감** (`IndexController`): 식물 134종·등급 11개(영원 = `eternity`, 슈퍼 울트라디바인 색·아우라), 열매 1개 값 표시(임시) 모양
- [ ] **상점 러닝머신 11~20레벨**: `ShopController.TREADMILL_NAMES` 와 `MapBuilder.TREAD_STYLES` 는 10개라 11레벨 위는 10번 모양으로 보임 (깨지지는 않음) → 이름·모양 10개 더. 카드 글 "+N/스텝" 대신 1초 속도 `Economy.treadmillGainPerSecond` (20레벨 1M). 정원 카드 "펫이 많을수록 돈을…" → 정원 칸 글
- [ ] **글자 바꾸기**: 게임 이름 "씨앗을 훔치세요", 화면의 돈 `$`(`Format.money`) → 코인, 알 → 씨앗, 우리 → 정원, 부화 → 성체, 펫 → 식물 (`NotifyController`·`TutorialController`·`LeaderboardController`·`Theme.Menu` 등). 서버 글은 이미 바뀜
- [ ] **등급 색** (`Theme`/`Visuals.rarityEffects`): 11개 (eternity 이름 바뀜, super_ultradivine 추가)
- [ ] **소리**: 열매 따기·팔기·먹이기·성체 됨·물 주기 (Fusion·FusionCharge·AltarOffer·AltarPaired·Shrine 소리는 지움)
- [ ] **튜토리얼 화살표** 6판 단계에 맞게 (6장 표)
- [ ] 문서: `docs/UI.md`, `docs/STUDIO_CHECKLIST.md` 의 알·펫·퓨전·제단 설명

**서버가 계속 부르는 MapBuilder 공개 함수 (이름·모양 유지 부탁):** `start()`, `getFolder(name)` ("Eggs"/"Guardians"/"Traps"/"Incubating"), `getNests(biomeId): {BasePart}`, `groundY(position, ignore): number`, `setNightWalls(on)`, `setPlotOwner(index, player?)`, `plotCount()`, `getPlot(index)`. 6판: `buildAltar`·`buildShrine`·`buildFusionMachine` 없앰.

## 9. 치트 방지 (서버, 클라는 할 일 없음)

- 1초마다 `HumanoidRootPart` 수평 이동 거리 > `WalkSpeed × 1.5 + 30` (경과초 비례) → 마지막 정상 위치로 되돌림 + 경고, 5번이면 Kick (경고는 2분마다 1개씩 줄어듦). 래그돌·곰덫·서버 순간이동 직후는 검사 쉼.
- 씨앗을 든 사람: 0.2초에 `WalkSpeed × 0.2 × 1.5 + 8` 스터드보다 멀리 가면 씨앗을 이전 위치에 떨어뜨림. 배달은 주운 곳 → 배달한 곳 거리 ÷ (`WalkSpeed × 1.3`) 보다 빨리 오면 거부(씨앗은 둥지로).
- "근처여야 하는" 요청은 전부 서버가 거리 확인: 씨앗 줍기(12), 크리스탈 줍기(12), 판매 가판대(14 — `SellFruits`, `SellPlant`), 내 정원(20 — `PickFruit`, `FeedFruit`, `SellPlant`, `PetPet`), 사쿠라 나무(14 — `SakuraOffer`, `SakuraDraw`). 배달·러닝머신·허브는 `MapLayout` 사각형으로 판정. `SkipGrowth`·`PurchaseUpgrade` 는 화면 버튼이라 거리 검사 없음 (코인만 씀).
- 코인 = 서버만 바꿈 (열매 팔기·성체 팔기·도감·튜토리얼 보상·개발 명령). 열매 값은 딸 때 서버가 정해 가방에 저장 (클라가 보낸 값은 안 씀).
