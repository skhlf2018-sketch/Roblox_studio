# Remote 목록 (서버 ↔ 클라)

> **[5판] 퀘스트·선물 없앰 · 튜토리얼 · 랭킹판 · 쓰다듬기 (수석, 2026-10-22)** — 사장님 지시. 서버는 다 됨, **클라 화면은 선임** (아래 8절 체크리스트).
> - **없앤 것:** `QuestUpdate`(서버→클라), `ClaimFreeReward`(클라→서버), Snapshot 의 `quests`·`questsDone`·`freeRewardClaimed`, DataUpdate 섹션 `"quests"`·`"flags"`, 플레이어 Attr `QuestsDone`, 태그 `QuestGate`(+ CollisionGroup `QuestGate`/`QuestPassed`), 알 파트 Attr `QuestOnly`, `Announce` 의 `questOnly`, `MapLayout.specials.questGate`, 소리 `QuestStep`·`GateOpen`. 마법의 숲은 **항상 열림**, **모든 알을 누구나 훔칠 수 있음**. 옛 퀘스트 알(지터버그·영혼 세계 수호자)은 초기화 때 마법의 숲 둥지에 나오는 **공지 특별 알** (`Announce` kind `"rareEgg"` 그대로, 지터버그 8% · 영혼 세계 수호자 1%, `EggSpawn.EXTRA_SPECIALS`). 도감 보상(`ClaimIndexReward`·`IndexRewarded`)은 **그대로**.
> - **새 Remote 4개:**
>   - `TutorialUpdate` (서버→나에게만) — 인자 1개 `TutorialView` = `{ step: number, total: number, text: string, hint: string, done: boolean, reward: number? }`. `step` 1~5 (= `total` 5), 끝나면 `step = 6`·`done = true`·`hint = ""`. `reward = 500` 은 **끝내는 순간의 한 번에만** 있음 ("튜토리얼 끝! 보상 $500" 축하 연출). 보내는 때: 접속 준비 때(튜토리얼이 안 끝난 사람만) · 단계가 바뀔 때 · `/tutorial reset`. 같은 모양이 `Snapshot.tutorial` 과 `DataUpdate("tutorial", { tutorial = TutorialView })` 에도 옴 (State 가 합침) → **끝난 사람은 `State.get().tutorial.done == true`, 패널을 숨기세요**.
>     단계 글(`text`, 사장님 문장 그대로): 1 "숲에서 알 훔치기" · 2 "안전 구역으로 돌아오기" · 3 "핫바에서 알을 골라 우리에 놓기" · 4 "부화!" · 5 "펫 장착". `hint` = 작은 설명 (`shared/Data/Tutorial.luau`).
>     진행: 알 줍기 1→2, 든 알을 놓침 2→1, 허브에 들어와 가방에 들어감 →3, `PlaceEgg` 성공 3→4, `PickUpPlacedEgg` 로 우리가 비면 4→3, 부화 →5, `EquipPet`/`EquipBest` 로 장착 펫 1마리 이상 5→끝(+$500 + `Notify` success). 건너뛰기 없음. **튜토리얼 중(끝나기 전)에는 부화한 펫이 자동 장착되지 않음** (`HatchResult.equipped = false` → 5단계에서 펫 창의 장착 버튼). 이미 놀던 사람은 처음부터 끝난 상태(스키마 4 → 5 마이그레이션).
>   - `LeaderboardUpdate` (서버→전체, `Config.LEADERBOARD_INTERVAL` 10초마다 + 새로 온 사람에게는 준비되자마자 그 사람에게만 한 번) — 인자 1개 `{ money: { LeaderboardEntry }, speed: { LeaderboardEntry } }`, `LeaderboardEntry = { name: string (DisplayName), value: number, userId: number }`. 각각 큰 값부터 최대 `Config.LEADERBOARD_SIZE` 10줄 (같으면 이름 순). `money` = 돈(`Format.money`), `speed` = 실효 속도(Attr `Speed` 와 같은 숫자, `Format.number`). 데이터를 불러온 사람만.
>   - `PetPet` (클라→서버) — 인자 `petUid: string` (내 우리에 서 있는 = **장착된** 펫 uid, PenPet 모델 Attr `PetUid`). 서버 검증: uid 형식 · 내 펫 · 장착 중 · 내 베이스가 있음 · 살아 있는 내 캐릭터가 **내 우리(`MapLayout.penRect`) 에서 `Config.PET_PET_RADIUS` 20 스터드 안** · 사람마다 `Config.PET_PET_COOLDOWN` 1초. 실패는 조용히 무시(알림 없음). 레이트 리밋 3 / 2.
>   - `PetPetted` (서버→전체) — 인자 **2개** `(ownerUserId: number, petUid: string)` → 그 주인 우리의 그 펫 위에 하트·소리 (다른 사람 화면에도). 펫 모델 = `PetVisualService` 의 PenPet 태그 모델 (Attr `PetUid` 만 있음). **uid 는 사람마다 따로 매겨서(p1, p2 …) 겹칠 수 있으니** 주인으로 한 번 더 거르세요: 주인 Player 의 Attr `PlotIndex` == `MapLayout.plotAt(model:GetPivot().Position)` (또는 선임이 PenPet 에 `OwnerUserId` Attr 을 붙여도 됨).
> - **저장 스키마 5:** + `tutorialStep` (1~5, 6 = 끝), `quests`·`questsRewarded`·`freeRewardClaimed` 칸 지움. 4 → 5: 펫·놓인 알·가방 알이 있거나 알을 훔친/배달한/부화한 적이 있으면 6(끝), 아니면 1. 무료 보상으로 받은 속도·퀘스트로 받은 알은 그대로.
> - 개발 명령: `/quests` 없앰, **`/tutorial reset`** (1단계부터 다시, 보상도 다시). 개(dog) 알 부화 **3초**.

> **[2판 수정] 알 가방 · 우리에 직접 놓기 · 속도 체감 · 떨어진 알 (수석, 2026-10-19)** — 사장님 지적 반영.
> - **배달 = 알을 든 채 허브(z < 0, `MapLayout.isInHub`)에 들어오는 순간** (경비 `ChaseEnded` reason `"safe"` 와 같은 순간). 알은 우리에 저절로 놓이지 않고 **알 가방**(`snap.eggs`, 최대 `Config.EGG_INVENTORY_MAX` 50 [추정])으로. `EggDelivered` = "가방에 넣음"(BagEgg). 베이스 없는 8번째 사람도 받음.
> - **부화 슬롯 없음.** 플레이어가 알 창에서 알을 고르고 **우리 바닥 아무 데나** 놓음 → 새 Remote **`PlaceEgg(eggUid, x, z)`** (월드 x, z). 놓은 알만 자람(밤 30배). 다시 가방으로: **`PickUpPlacedEgg(eggUid)`** (진행도 유지, `Config.ALLOW_EGG_PICKUP`). 우리에 놓을 수 있는 알 최대 `Config.PLACED_EGG_MAX` 8 [추정]. 규칙은 `shared/EggPlacement.luau` (클라 미리보기도 같은 함수로).
> - 선물 알(제단·비밀 통로·퀘스트)도 가방으로. **대기 줄(`eggQueue`) 없앰.** `Snapshot`·`DataUpdate` 에 `eggs` 섹션 추가, `incubators` 에 `x, z`(베이스 기준 좌표), `slot` 없음. 저장 스키마 4 (옛 슬롯 n번 알 → 우리 안 격자 n번 자리 = 옛 받침 자리, 옛 대기 줄 → 가방).
> - **속도 → 걷기 곡선 다시 맞춤** (원작 영상 기준): WalkSpeed = clamp(16 × (1 + log10(max(속도, 10) / 10)), 16, 150). 속도 20 → 20.8 / 200 → 36.8 / 10K → 64 / 64K → 76.9 / 1M → 96 / 5.8M → 108.2 / 1B → 144 / 2.37B~ → 150. 속도 숫자·러닝머신·도감 보상은 그대로. 경비는 플레이어 WalkSpeed × 비율이라 "추천 이상이면 못 잡고 모자라면 반드시 잡힘" 그대로, 추격 목표를 0.25초 앞으로 잡아 150 에서도 멈칫하지 않음.
> - **부화 시간 = 원작 그대로** (÷3 없앰, 밤 30배만): `IncubatorRecord.required`·`BagEgg.required` 가 길어짐 (닭 10초 · 전설 5분 · 비밀 1.5시간 · 신성 24시간). 저장된 알도 불러올 때 새 시간으로 다시 계산(자란 만큼은 그대로). **둥지 희귀도는 구역 순서대로** 올라감 (`EggRoll.centerRarity` / `nestWeight`, 뒤 구역은 비밀 이상이 공지 없는 보통 둥지 알로도 나옴 → `Special` Attribute 는 여전히 공지된 특별 알만 true).
> - **떨어진 알**: 그 자리에 60초(`Config.DROPPED_EGG_LIFETIME`, 120 → 60 [추정]) 남음. 알 파트 Attribute **`DroppedAt`·`ExpiresAt`**(서버 시각) → 머리 위 "32초" 카운트다운. 그 둥지는 떨어진 알이 사라진 뒤 30초(또는 다음 초기화)에 다시 채움. 둥지 복귀는 "알의 구역 안에서 경비에게 잡힘"일 때만.

> **[2판 마무리] 트레일 장착 (수석, 2026-10-18)** — 새 Remote `EquipTrail(trailId | "none")`. 트레일 배율은 이제 **장착한 트레일 하나만** (사면 바로 장착). `Snapshot`·`DataUpdate("upgrades")` 에 `equippedTrail`, Player Attribute `EquippedTrail`. 저장 스키마 3 (기존 사용자는 가진 것 중 최고 트레일이 장착된 상태로 변환 → 속도 그대로). 경비 잡힘 거리 = 6 + 경비 키 × 0.25 (최대 16), 경비 이름표는 겉모습 꼭대기 + 3.

> **[2판] MapLayout 완료 (수석, 2026-10-18)** — `src/shared/Data/MapLayout.luau` (+ `tests/maplayout.spec.luau`). 선임은 `require(ReplicatedStorage.Shared.Data.MapLayout)` 로 맵을 지으세요. **달라진 숫자 1개: `HUB.zMin = -290`** (베이스 폭 60 × 4개가 한쪽에 들어가도록. `zMax = 0`·`SAFE_ZONE_Z = 0` 은 약속 그대로). 베이스 번호: 1 왼z-40 / 2 오른z-40 / 3 왼z-110 / 4 오른z-110 / 5 왼z-180 / 6 오른z-180 / 7 왼z-250, 오른쪽 z-250 자리는 허브 가게(`MapLayout.hubSpots`). 사용법은 0장과 파일 맨 위 주석.

작성: 수석, 2026-10-18 (1단계) · 2단계 갱신 (퓨전·구역 무기·사쿠라·제단·퀘스트·치트 방지) · **2판 전면 갱신 2026-10-18 저녁** (일자 복도 맵·경비 무한 추격·알 버리기·자동 배달·러닝머신 고정·돈 팝업·판매). 선임이 맵·UI·소리·연출을 붙일 때 보는 문서입니다.

- Remote 이름은 `src/shared/Remotes.luau` **한 곳**에서만 정의합니다. 서버(`src/server/Net.luau`)가 `ReplicatedStorage.Remotes` 폴더에 전부 RemoteEvent 로 만들고, 클라(`src/client/Net.luau`)는 `WaitForChild` 로 받습니다.
- RemoteFunction 은 쓰지 않습니다. 요청은 RemoteEvent 로 보내고, 결과는 서버가 다른 이벤트(`Notify`, `DataUpdate` 등)로 알려 줍니다.
- **치트 방지 원칙:** 돈·속도·펫을 직접 바꾸는 Remote 는 없습니다. 클라는 "요청"만 보내고 서버가 전부 검증합니다 (인자 타입 검사 + 플레이어·Remote 별 레이트 리밋 + 게임 규칙 검사 + "근처여야 하는" 요청은 서버가 캐릭터 위치로 거리 확인).
- **클라에서 캐릭터를 순간이동시키지 마세요.** 서버가 1초마다 이동 거리를 검사합니다(9절). 러닝머신 고정·밤 귀가처럼 캐릭터를 옮기는 일은 전부 서버가 합니다.

클라 코드에서 쓰는 법:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapLayout = require(ReplicatedStorage.Shared.Data.MapLayout)
local Net = require(ReplicatedStorage.Client.Net)
local State = require(ReplicatedStorage.Client.State)

Net.on(Remotes.ToClient.ZoneEntered, function(p) --[[ "Jungle 😬" 배너: p.nameEn / p.name ]] end)
Net.send(Remotes.ToServer.DropEgg)
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
| `plots[i]` (`plot(i)`) | `{ index, side "left"/"right", center {x,z}, size {w=60(z 방향), d=70(x 방향)}, facing (+1 = +x 를 봄 / -1), rect, penRect, yardRect, spawn, treadmill, fusion, sellStall, signs = { owner, penUpgrade, treadmillUpgrade } }` | 베이스 전부 |
| `penRect(i)` | 우리 = 뒤쪽 46 (벽 쪽) | 울타리·펫 우리 바닥 · **2판 수정: 알을 놓는 곳 (PlaceEgg)** |
| `petRect(i)` | 우리 뒤쪽 (울타리 쪽 16 빼고, 가장자리 3 여유) | **PetVisualService 펫 배치** |
| **`toLocal(i, pos)` / `toWorld(i, lx, lz)`** (2판 수정) | 베이스 기준 좌표 ↔ 월드. `lx = (x - 가운데 x) × facing` (+35 = 복도 쪽 앞 가장자리, -35 = 뒤 벽), `lz = z - 가운데 z`. 왼쪽·오른쪽 베이스가 거울이라 로컬 모양이 같음 | `snap.incubators[].x, z` 가 이 좌표 → 월드는 `toWorld(PlotIndex, x, z)` |
| **`PEN_LOCAL`**, `isInPenLocal(lx, lz, inset?)` | 우리를 로컬로: `lx -35 ~ 11, lz -30 ~ 30` (모든 베이스 같음) | 알 놓기 미리보기 |
| `eggGridLocal(n)` (1~20) | 우리 안 격자 (울타리 쪽부터 4칸씩, 줄 7·칸 14 간격). 1~8 = 옛 부화 슬롯 자리 | 저장 변환·깨진 자리 보정 (서버) |
| `incubatorSpots(i)` | **[옛 받침 — 서버는 안 씀]** `eggGridLocal(1~8)` 의 월드 자리 | MapBuilder 가 아직 받침(IncubatorSlot)을 지음 → 받침 지우면 같이 지움 |
| `TREADMILL_PAD`, `treadmillRect(i)` | `{ sizeX = 12, sizeZ = 8 }` (x 방향으로 달림), plot.treadmill 중심 | **러닝머신 벨트 파트는 정확히 이 크기·자리** |
| `nestsFor(biomeId)` | 8개 `{x,z}` (벽·구역 경계에서 20 이상, 경비 집에서 60 이상, 짝수 구역은 좌우 뒤집힘) | Nest 태그 파트 (NestIndex = 순서) |
| `guardHome(biomeId)` | `{ x = 0, z = centerZ }` | 경비가 자는 자리 (서버가 경비를 여기 만듦) |
| `hubSpots` | `mainSpawn (0,-140)`, `sellStall (60,-232)`, `trailShop (60,-268)`, `eventPortal (92,-250)`, `safeLine (0,0)` | 허브 시설 |
| `specials` | `sakuraIncubator`(벚꽃), `altarLight`·`altarDark`·`shrine`(천사&악마) 각 `{ biomeId, x, z }` (5판: 마법의 숲 `questGate` 없앰) | 2단계 특수 장소 (같은 태그로 지으면 서버 임시 파트 안 생김) |

판정 함수 (위치는 `Vector3` 또는 `{x=, z=}` 둘 다 됨):

| 함수 | 뜻 |
|---|---|
| `zoneAt(z)` / `zoneAtPos(pos)` | 구역 id \| `"hub"`(z < 0, 허브 뒤 벽 앞까지) \| `nil`(맵 밖). 경계 z = 0 은 숲, z = 240 은 호수 |
| `isInHub(pos)` | 허브(안전 구역) 안 → **2판 수정: 배달 판정** (알을 든 채 들어오면 가방으로) |
| `isInPlot(pos, i)` | 베이스 i 영역(앞마당 + 우리) 안 (PlaceEgg "내 베이스 안에 서 있음") |
| `isInPen(pos, i, inset?)`, `plotAt(pos)` | 우리 안 (inset 만큼 울타리 안쪽까지만) / 위치가 든 베이스 번호 |
| `isOnTreadmill(pos, i, margin?)` | 베이스 i 러닝머신 벨트 위 |
| `sellSpots()` | 판매 자리 전부 (허브 1 + 베이스 7) |
| `inRect / rectCenter / rectSize` | 사각형 도우미 |

---

## 1. 서버 → 클라 (클라가 받는 이벤트)

| 이름 | 언제 | 인자 (payload) |
|---|---|---|
| `Snapshot` | 접속해서 데이터를 불러온 직후, `RequestSnapshot` 요청 때, 늦게 베이스를 받았을 때 | `Types.Snapshot` 전체 (아래 4절) |
| `DataUpdate` | 상태 일부가 바뀔 때 | `(section: string, payload: table)` — 5절 표. `State` 모듈이 자동으로 합쳐 줌 |
| `Notify` | 성공/실패 안내 한 줄 | `{ kind: "info" \| "success" \| "error", text: string }` |
| `Announce` | 서버 전체 공지 (채팅에도 표시됨) | `{ kind, text, ... }` — kind: `"reset"`("ALL EGG RESET!"), `"rareEgg"`(+ `biomeId, petId, rarity, eggUid` — 5판: `questOnly` 없앰), `"night"`, `"day"` |
| `PhaseChanged` | 낮/밤/대기 바뀔 때 | `{ phase: "Day"\|"Night"\|"Intermission", endsAt: number, duration: number, cycleNumber: number, heavenSide: "light"\|"dark"\|nil }` — `endsAt` 은 `workspace:GetServerTimeNow()` 기준 |
| `RunAlert` | 내가 알을 든 순간 ("달리기!!") | `{ egg: EggInfo, guardName: string, guardSpeed: number, yourSpeed: number, weightKg: number }` — `guardSpeed` = 추천 속도 × 0.9, `yourSpeed` = 알 무게까지 반영한 내 실효 속도, `weightKg` = 알 무게(표시용). **따돌림 조건: `SpeedMath.canEscape(guardSpeed, yourSpeed)`** (= `yourSpeed > guardSpeed × 0.99`) |
| `ChaseEnded` | 나를 쫓던 경비가 멈춤 | `{ biomeId: string, reason: "safe"\|"caught"\|"dropped"\|"night"\|"other" }` — safe = 허브에 들어옴(= 배달, 2판 수정), dropped = 알을 놓음(DropEgg), other = 기절·죽음·다른 사람으로 대상 바뀜 |
| `Caught` | 경비에게 잡힘 / 무기에 맞음 / 곰덫 밟음 | `{ cause: "guard"\|"player"\|"trap", by: string, eggOutcome: "ReturnToNest"\|"DropHere"\|"None", ragdollSeconds: number, knockback: Vector3?, stunSeconds: number? }` |
| `EggDelivered` | **2판 수정: 알을 든 채 허브(z < 0)에 들어와 알 가방에 들어감** ("에그를 훔쳤어요!" 토스트, 경비 `ChaseEnded` safe 와 같은 순간) | `BagEgg` (`uid, petId, size, mutations, biomeId, special, progress, required`) — 우리에는 아직 안 놓임 (`slot` 없음) |
| `HatchResult` | 부화 성공 | `{ pet: PetRecord, isNew: boolean (도감 첫 발견), income: number (초당), equipped: boolean, sold: boolean }` — `sold` = 보관함이 가득 차서 바로 팔림 |
| `OfflineIncome` | 접속 때 오프라인 수입 지급 (60초 이상 비웠을 때) | `{ amount: number, seconds: number, perDay: number, text: string }` |
| `IndexRewarded` | 도감 보상 수령 | `{ petIds: {string}, speed: number, money: number, completeBonus: boolean }` |
| `FusionResult` | 퓨전 성공 | `{ consumed: {uid}, pet: PetRecord, upgraded: boolean, bonusMutation: string?, inputIncome: number, income: number, isNew: boolean, equipped: boolean }` |
| `EggGranted` | 선물 알(제단·비밀 통로·개발 명령 `/egg`)이 **알 가방에 들어감** (2판 수정, 대기 줄 없음) | `{ egg: BagEgg, queued: false, source }` — source: `"altar"\|"shrine"\|"dev"` (5판: `"quest"` 없앰). `queued` 는 옛 클라 호환용으로 항상 false (지울 예정). 가방이 가득 차면 선물 알을 못 받음 (제단·비밀 통로는 미리 거부) |
| `SakuraResult` | 사쿠라 인큐베이터 해금 / 블룸 부여 | 해금: `{ kind: "unlocked", consumed: petUid, crystals }` · 블룸: `{ kind: "bloom", targetUid, target: "egg"\|"pet", mutation: "bloom"\|"spirit_bloom", crystals }` |
| `AltarUpdate` | 제단 제물 상태 | `{ status: "pending"\|"paired"\|"expired", side: "light"\|"dark", petId, partner?: string, eggPetId?: "ring_guard"\|"ringlord" }` |
| `ShrineResult` | 비밀 통로 합성 성공 | `{ consumed: {uid, uid}, resultPetId: "equinox"\|"aetheron", size, mutations }` (알은 `EggGranted` 로도 옴) |
| `PetsSold` | 보관함이 500마리를 넘어 싼 펫이 **자동** 판매됨 | `{ pets: { PetRecord }, money: number }` (SellPet 으로 직접 판 것은 `Notify` 만) |
| **`ZoneEntered`** (2판) | 새 구역(z 범위)에 들어갈 때 1번 (서버 0.2초 틱). 허브는 안 보냄 | `{ biomeId: string, name: string, nameEn: string }` → 화면 위 가운데 구역 이름 배너 ("Jungle 😬") |
| **`IncomeTick`** (2판) | 장착 펫마다 3초(`Config.INCOME_POPUP_INTERVAL`)에 1번, 펫들은 1초씩 엇갈려 옴 | `{ petUid: string, amount: number }` — amount = 그 펫 3초치 돈 → 펫 머리 위 "+$34K" 초록 팝업. **돈은 1초마다 따로 들어옴** (팝업은 표시용) |
| **`TreadmillStep`** (2판) | 러닝머신 위에서 걸음(1초)마다 | `{ amount: number }` — 오른 속도 → "+500" 분홍 팝업 |
| **`TutorialUpdate`** (5판) | 나에게만: 접속 준비 때(튜토리얼이 안 끝난 사람만) · 단계가 바뀔 때 · `/tutorial reset` | `TutorialView = { step, total, text, hint, done, reward? }` — step 1~5 (total 5), 끝 = step 6·done true·`reward = 500`(끝내는 순간 한 번만). Snapshot `tutorial`·DataUpdate `"tutorial"` 도 같은 모양 (맨 위 [5판] 상자) |
| **`LeaderboardUpdate`** (5판) | 10초마다 서버 전체 (`Config.LEADERBOARD_INTERVAL`) + 새로 온 사람에게 한 번 | `{ money: { LeaderboardEntry }, speed: { LeaderboardEntry } }` — `LeaderboardEntry = { name, value, userId }`, 큰 값부터 최대 10줄 (`Config.LEADERBOARD_SIZE`), speed = 실효 속도(Attr `Speed`) |
| **`PetPetted`** (5판) | 누가 `PetPet` 으로 자기 우리 펫을 쓰다듬음 (서버 전체) | `(ownerUserId: number, petUid: string)` — 인자 2개 → 그 펫(PenPet 모델 Attr `PetUid` + 주인 `PlotIndex` == `MapLayout.plotAt(모델 위치)`) 위에 하트·소리 |

`EggInfo` = `{ uid, petId, biomeId, rarity, size, mutations: {string}, special: boolean }`

`BagEgg` (2판 수정, 가방 속 알) = `{ uid, petId, size, mutations, biomeId, special, progress, required }` — 가방 속에서는 안 자람 (`progress` 그대로, 우리에서 다시 주운 알은 자란 만큼 남음)
`IncubatorRecord` (우리에 놓인 알) = `{ uid, petId, size, mutations, biomeId, special, x, z, progress, required }` — `x, z` = 베이스 기준 좌표 (`MapLayout.toWorld(PlotIndex, x, z)` → 월드). 놓으면 같은 uid 그대로

## 2. 클라 → 서버 (클라가 보내는 요청)

| 이름 | 인자 | 서버 검증 | 레이트 리밋 (burst / 초당) |
|---|---|---|---|
| `RequestSnapshot` | 없음 | — | 3 / 0.5 |
| `HatchEgg` | `eggUid: string` (우리에 놓인 알 uid, `"i12"` 형태) | uid 형식, 내 우리에 놓인 알인지(가방 속 알은 안 됨), 다 자랐는지. 우리 안 알 `ProximityPrompt`(선임) / Growing Eggs 패널 버튼 둘 다 이것 (거리 검사 없음) | 10 / 4 |
| **`PlaceEgg`** (2판 수정) | `eggUid: string`, `x: number`, `z: number` (놓을 자리 = **월드** x, z — 우리 바닥을 클릭/터치한 점) | uid 형식·x·z 유한한 숫자, **가방에 그 알**, 내 베이스가 있음, 놓인 알 < `PLACED_EGG_MAX`(8), **내가 내 베이스 안에 서 있거나 그 자리 14 안**(`EGG_PLACE_RADIUS`), **그 자리가 내 우리 안**(울타리에서 2 안쪽, `EGG_PLACE_FENCE_MARGIN`), **다른 놓인 알과 4 이상**(큰 알끼리는 두 알 지름 평균, 초거대끼리 4.8) **· 내 우리 펫(PenPet 모델)과 4 이상**. 자리는 0.1 단위 반올림해 베이스 기준 좌표로 저장. 성공: 가방 → `incubators`, 그 자리에 `IncubatingEgg` 파트, `DataUpdate("eggs")` + `DataUpdate("incubators")`. 실패: `Notify` error (`EggPlacement.message`) | 5 / 3 |
| **`PickUpPlacedEgg`** (2판 수정) | `eggUid: string` | `Config.ALLOW_EGG_PICKUP`(true [추정]), 내 우리에 놓인 알, 가방에 빈칸. 진행도 그대로 가방으로 (가방 속에서는 안 자람), 알 파트 사라짐. 거리 검사 없음 (가방으로 옮길 뿐) | 5 / 3 |
| `EquipPet` | `petUid: string` | 내 펫인지, 이미 장착인지, 우리 칸 남았는지 | 10 / 5 |
| `UnequipPet` | `petUid: string` | 장착돼 있는지 | 10 / 5 |
| `EquipBest` | 없음 | 서버가 수입 순으로 칸 수만큼 고름 | 2 / 0.5 |
| `PurchaseUpgrade` | `kind: "Pen"\|"Treadmill"\|"Trail"`, `trailId: string?` (Trail 일 때만) | 종류·id 허용 목록, 다음 레벨 있는지, 돈 충분한지 (상점 화면 버튼이라 거리 검사 없음). **트레일은 사면 바로 장착** (2판 마무리) | 5 / 2 |
| `UseTool` | `kind`: `"Bat"\|"BearTrap"\|"WaterBat"\|"Katana"\|"Axe"\|"AngelSpear"\|"Hammer"\|"CandyCane"\|"Scythe"` (`Remotes.ToolKinds`) | 그 도구를 손에 들고 있는지, 구역 무기는 해금했는지, 근접 무기 공용 쿨다운, **허브(안전 구역)가 아닌지**, 곰덫 개수. 대상·위치는 서버가 찾음 | 4 / 2 |
| `ClaimIndexReward` | `"all"` 또는 `petId` | 발견했고 아직 안 받았는지 | 5 / 1 |
| `FuseRequest` | `petUid1, petUid2, petUid3` | 내 베이스 퓨전 머신 12스터드 안(파트가 없으면 내 베이스 안), 서로 다른 내 펫 3마리, 같은 petId | 3 / 1 |
| `SakuraOffer` | `petUid?` | 사쿠라 인큐베이터 14스터드 안, 아직 해금 안 함, 학(Crane) 펫 | 2 / 0.5 |
| `SakuraApply` | `targetUid` (부화 중 알 `"i.."` 또는 보관 펫 `"p.."`) | 인큐베이터 14스터드 안, 해금함, 크리스탈 1개 이상, 블룸 계열이 아직 없음 | 5 / 2 |
| `AltarOffer` | `petUid` | 천국/지옥 제단 14스터드 안, 그 쪽 펫, 이번 주기에 아직 안 바침, 알 받을 자리 | 3 / 1 |
| `ShrineFuse` | `petUidA, petUidB` | 비밀 통로 제단 14스터드 안, 레시피, 계정당 1번, 알 받을 자리 | 2 / 0.5 |
| **`DropEgg`** (2판) | 없음 | 알을 들고 있는지. **알은 항상 그 자리에 떨어짐**(알의 구역 안이어도 둥지로 안 감) → 경비 추격 끝(`ChaseEnded` reason dropped), **60초 뒤 사라짐**(2판 수정, 알 파트 `ExpiresAt`). 그 둥지는 떨어진 알이 사라질 때까지 비어 있음. 다시 주우면 경비가 또 쫓고 **유예 1.5초 없음** | 2 / 1 |
| **`SellPet`** (2판) | `petUid: string` | **판매 가게 14스터드 안** (SellStall 태그 파트 표면 또는 `MapLayout.sellSpots()` 자리), 내 펫인지. 장착 중이면 해제 후 판매. 가격 = `Economy.recordIncome(pet) × Config.PET_SELL_SECONDS(60)`. 결과는 `Notify` | 10 / 4 |
| **`TreadmillLeave`** (2판) | 없음 | 러닝머신 위인지. 내려서 벨트 앞(복도 쪽)으로 옮겨 줌. **클라가 러닝머신 위에서 점프할 때 보내세요** (`OnTreadmill` 이 true 일 때 Humanoid.Jumping / 점프 버튼). 안 보내도 점프로 몸이 바닥 + 8 위로 뜨면 서버가 그 자리에서 내려 줌 (벨트 윗면은 바닥 + 2 이하로 만들어 주세요) | 3 / 2 |
| **`EquipTrail`** (2판 마무리) | `trailId: string` 또는 `"none"` (`Upgrades.NO_TRAIL`) | 허용 목록(트레일 id + `"none"`), **가진 트레일인지**. 바꾸면 `data.equippedTrail` 저장 + 속도 다시 계산 + `DataUpdate("upgrades")` + `Notify`. `"none"` = 해제(배율 1). 이미 장착한 것을 또 보내면 무시. 상점 창 버튼이라 거리 검사 없음 | 5 / 2 |
| **`PetPet`** (5판) | `petUid: string` (내 우리의 **장착된** 펫, PenPet 모델 Attr `PetUid`) | uid 형식, 내 펫이고 장착 중, 내 베이스가 있음, 살아 있는 내 캐릭터가 **내 우리(`MapLayout.penRect`)에서 20 스터드 안**(`Config.PET_PET_RADIUS`), 사람마다 쿨다운 1초(`Config.PET_PET_COOLDOWN`). 통과하면 `PetPetted(ownerUserId, petUid)` 를 서버 전체에. 실패는 조용히 무시 | 3 / 2 |

- **알 줍기**는 Remote 가 아니라 서버가 만든 `ProximityPrompt`(E 키, 알 파트 안의 `StealPrompt`)로 합니다. 서버가 거리·낮인지·이미 들고 있는지 확인합니다 (5판: 퀘스트 전용 알 없앰 → 모든 알을 누구나 주움).
- **사쿠라 크리스탈 줍기**도 `ProximityPrompt`(크리스탈 파트 안의 `CrystalPrompt`). 서버가 거리 확인.
- **배달** (2판 수정)도 Remote 없음: 알을 든 채 **허브(안전 구역, `MapLayout.isInHub` = z < 0)에 들어오는 순간** 서버가 자동 처리 → 알 가방으로 (`EggDelivered`). 내 베이스까지 갈 필요 없음, 베이스 없는 사람도 받음. 가방이 가득 차면 알은 손에 그대로 + 3초에 한 번 안내. 바닥에서 20 넘게 떠 있으면 내려올 때까지 기다림. (주운 곳에서 너무 빨리 왔으면 거부 → 알은 둥지로)
- **우리에 알 놓기** (2판 수정): 클라가 할 일 = 알 창(오른쪽 주황 알 버튼, `snap.eggs`)에서 알 고르기 → 놓기 모드 → 내 우리 바닥 클릭/터치(마우스 레이캐스트 점) → `PlaceEgg(uid, hit.X, hit.Z)`. 미리보기는 `EggPlacement.check(MapLayout.toLocal(PlotIndex, hit).x, ...z, egg.size, 놓인 알들, nil)` 로 초록/빨강 (펫 간격은 서버만 봄).
- **러닝머신** (2판): 내 베이스 러닝머신 벨트에 올라서면 서버가 자동으로 태움 (아래 3절 `OnTreadmill`). 내릴 때만 `TreadmillLeave`.
- 도구: 서버가 Backpack 에 `Tool`(이름 = kind, `RequiresHandle = false`, Attribute `ToolKind`, 무기는 `WeaponId`·`Range`, 곰덫은 `Count`)을 넣어 줌. 기본 클라(`ToolController`)가 `Remotes.ToolKinds` 에 있는 이름의 Tool 이 `Activated` 될 때 `UseTool` 을 보냄. `SwingTick`(Tool Attribute) = 서버가 실제로 휘두름/설치를 처리한 시각 → 다른 사람 화면 재생용.

## 3. Attribute 로 복제되는 값 (자주 바뀌는 숫자)

### 플레이어 (`Players.LocalPlayer:GetAttribute(...)`, 이름은 `Tags.PlayerAttributes`)

| Attribute | 뜻 |
|---|---|
| `Money` | 돈 (number, 소수 가능 — 표시할 때 `Format.money`) |
| `Speed` | 실효 속도 = 모은 속도 × 트레일 배율 (경비 비교에 쓰는 숫자) |
| `BaseSpeed` | 모은 속도 (트레일 전) |
| `WalkSpeed` | 서버가 정한 실제 이동 속도 (러닝머신 위·곰덫 = 0) |
| `IncomePerSecond` | 장착 펫 초당 수입 합 |
| `PlotIndex` | 내 베이스 번호 (1~7, 0 = 없음 → 누가 나가면 바로 배정되고 `Snapshot` 다시 옴). 위치는 `MapLayout.plot(PlotIndex)` |
| `PenLevel`, `PenSlots` | 우리 레벨, 장착 칸 수 |
| `TreadmillLevel` | 러닝머신 레벨 (0 = 잠김) |
| `TrailMultiplier` | 적용 중인 트레일 배율 = **장착한 트레일** 배율 (없으면 1) |
| **`EquippedTrail`** (2판 마무리) | 장착한 트레일 id (`"none"` = 없음). 모든 플레이어에 있음 → 다른 사람 캐릭터 트레일 꾸밀 때 |
| `CarryingEgg`, `CarryingBiome` | 든 알 uid / 구역 id (`""` = 없음) → "달리기!!" 배너·빨간 비네트·핫바 3번 알 칸·"드롭" 버튼 유지 조건 |
| **`CarryWeightKg`** (2판) | 든 알 무게(kg, 표시용): 보통 50 / 큼 120 / 거대 400 / 초거대 1200 [추정]. 0 = 안 듦 (`Sizes.carryKg`) |
| `Stunned` | 래그돌·곰덫 중 |
| `InSafeZone` | **2판: 허브(z < 0) 안** → "안전 구역" 표시 |
| **`CurrentZone`** (2판) | 지금 있는 곳: 구역 id \| `"hub"` \| `""`(맵 밖). `ZoneEntered` 를 놓쳐도 이걸로 맞출 수 있음 |
| **`OnTreadmill`** (2판) | 러닝머신 위에 고정돼 달리는 중 → 제자리 달리기 애니메이션 + 점프하면 `TreadmillLeave` |
| `DataLoaded`, `SaveEnabled` | 데이터 로딩 끝났는지, 저장되는 세션인지 |
| `SakuraCrystals`, `SakuraUnlocked` | 사쿠라 크리스탈 개수 / 인큐베이터 해금 |
| `MoveWarnings` | 비정상 이동 경고 수 (5 = Kick, 시간이 지나면 줄어듦) |

leaderstats 에는 `Money`, `Speed` 가 보기 좋은 글자(StringValue, 예 `"$1.5K"`)로 들어 있습니다.

### 서버 상태 (`ReplicatedStorage.GameState` 폴더, 이름은 `Tags.StateAttributes`)

| Attribute | 뜻 |
|---|---|
| `Phase` | `"Day"` / `"Night"` / `"Intermission"` |
| `PhaseEndsAt` | 끝나는 시각 (`workspace:GetServerTimeNow()` 기준) → 남은 시간 = `PhaseEndsAt - workspace:GetServerTimeNow()` (오른쪽 아래 달/해 + "3분 58초") |
| `PhaseDuration` | 이번 단계 길이(초) |
| `CycleNumber` | 몇 번째 주기 |
| `HeavenSide` | 천사&악마 구역 이번 쪽 `"light"` / `"dark"` |

### 월드 오브젝트 Attribute / 태그 (UI·연출용, 이름은 `Tags`)

- **경비 모델**(`Guardian` 태그): `BiomeId`, `GuardName`, **`State` = `"Sleeping"`(집에서 잠, Z 표시) / `"Chase"`(쫓는 중) / `"Return"`(집으로 걸어감)**, `TargetUserId`. 집 = `MapLayout.guardHome`. 경비 파트는 CollisionGroup `"Guardians"`(경비끼리 안 부딪힘 — 붙이는 겉모습 파트도 서버가 자동으로 같은 그룹으로 바꿈). 경비 거리 표시는 `TargetUserId == 내 UserId` 인 경비의 `HumanoidRootPart` 와 내 거리.
- 알 파트(`Egg` 태그): `EggUid, PetId, BiomeId, Rarity, Size, Mutations("silver,bloom" 식), Special, EggState("Nest"/"Carried"/"Dropped"), WeightKg`(2판). 들고 있을 때는 머리 위에 용접됨.
  - **`DroppedAt`, `ExpiresAt`** (2판 수정, number, `workspace:GetServerTimeNow()` 기준): `EggState == "Dropped"` 일 때만 있음 (둥지·들고 있을 때는 nil). 머리 위 카운트다운 = `math.ceil(ExpiresAt - workspace:GetServerTimeNow())` 초 ("32초"). 0 이 되면 서버가 알을 지움.
- **부화 중 알**(`IncubatingEgg` 태그): **2판 수정: 플레이어가 `PlaceEgg` 로 고른 우리 안 자리 바닥 위** (`MapLayout.toWorld(PlotIndex, record.x, record.z)`). `EggUid, OwnerUserId, PlotIndex, PetId, Size, Mutations, Special, Progress, Required, Ready` (1초마다 갱신, `SlotIndex` 없음) → 머리 위 "에그 1m 52s" = `(Required - Progress) / 성장속도`(밤 30배). 다 자라면 선임이 붙인 `ProximityPrompt`(E) → `HatchEgg(EggUid)`. 다시 줍기 프롬프트(선택) → `PickUpPlacedEgg(EggUid)`.
- `IncubatorSlot` 태그(부화 알 받침): **2판 수정에서 안 씀** — 받침을 지우면 `MapLayout.incubatorSpots` 도 지웁니다.
- **2단계 특수 장소** — 자리는 `MapLayout.specials`. 맵(`Workspace.Map`)에 같은 태그·Attribute 파트가 있으면 그걸 쓰고, 없으면 서버가 그 자리에 임시 파트를 `Workspace.Map.Specials` 에 만듦(Attribute `Placeholder = true`). 거리 판정은 파트 상자 표면 기준.
  - `SakuraIncubator` (벚꽃) / `Altar` (천사&악마, Attr `Side` = `"light"`/`"dark"` 꼭 필요, 서버가 `PendingCount` 씀) / `Shrine` (비밀 통로). (5판: 마법의 숲 `QuestGate` 와 CollisionGroup `QuestGate`/`QuestPassed` 없앰)
  - `SakuraCrystal` (서버가 만듦): 초기화 때 벚꽃 둥지 근처 3개, 안에 `CrystalPrompt`.
- `FusionMachine` (Attr `PlotIndex`, 자리 `plot.fusion`), **`SellStall`** (2판, 자리 `hubSpots.sellStall` 또는 `plot.sellStall`), `Treadmill` (Attr `PlotIndex`, 자리·크기 `MapLayout.treadmillRect` — 서버 판정은 MapLayout 숫자로 함).
- `NightWall`: 2판은 허브 경계 z = 0 에 1장 (`MapLayout.NIGHT_WALL`). 서버가 밤·대기에 `MapBuilder.setNightWalls(true)`.
- `DeliveryPad`: **2판에서 안 씀** (태그 이름만 남아 있음, 선임 맵·클라 교체 후 지움).

## 4. Snapshot 모양 (`Types.Snapshot`)

```
money, speed, effectiveSpeed, incomePerSecond,
pets: { PetRecord },            -- PetRecord = { uid, petId, size, mutations }  (최대 petInventoryMax = 500)
equipped: { uid },
penLevel, penSlots, treadmillLevel,
trails: { trailId }, equippedTrail (trailId | "none"), trailMultiplier (= 장착한 트레일 배율),
indexDiscovered: { [petId]: true }, indexClaimed: { [petId]: true }, indexCompleteClaimed,
unlockedWeapons: { weaponId },
tools: { bearTrap = n },
incubators: { IncubatorRecord },   -- 우리에 놓인 알 (x, z = 베이스 기준 좌표, 최대 placedEggMax = 8)
eggs: { BagEgg },                  -- 2판 수정: 알 가방 (최대 eggInventoryMax = 50). eggQueue 는 없어짐
eggInventoryMax, placedEggMax,
plotIndex, saveEnabled,
sakuraCrystals, sakuraUnlocked, shrineUsed: { [resultPetId]: true },
petInventoryMax,
tutorial: TutorialView             -- 5판: { step, total, text, hint, done } (끝난 사람은 done = true, step 6)
                                   -- 5판에서 없앰: freeRewardClaimed, quests, questsDone
```

## 5. DataUpdate 섹션

| section | payload |
|---|---|
| `"pets"` | `{ pets, equipped, penSlots, incomePerSecond }` — **장착만 바뀔 때는 `pets` 가 빠짐** (SellPet 은 pets 포함) |
| `"incubators"` | `{ incubators }` — 우리에 놓인 알 (PlaceEgg·PickUpPlacedEgg·부화·다 자람·블룸 때) |
| **`"eggs"`** (2판 수정) | `{ eggs }` — 알 가방 (배달·선물 알·PlaceEgg·PickUpPlacedEgg·가방 알 블룸 때). 놓기·다시 줍기는 `eggs` 와 `incubators` 둘 다 옴 |
| `"index"` | `{ indexDiscovered, indexClaimed, indexCompleteClaimed, unlockedWeapons }` |
| `"upgrades"` | `{ penLevel, penSlots, treadmillLevel, trails, equippedTrail, trailMultiplier }` (트레일 구매·`EquipTrail` 때도) |
| `"tools"` | `{ tools }` |
| `"special"` | `{ sakuraCrystals, sakuraUnlocked, shrineUsed }` |
| **`"tutorial"`** (5판) | `{ tutorial = TutorialView }` — 튜토리얼 단계가 바뀔 때 (`TutorialUpdate` 와 같이 옴). 5판에서 `"flags"`(무료 보상)·`"quests"` 섹션 없앰 |

## 6. 화면별로 필요한 것 (2판 F)

| 화면 | 쓸 것 |
|---|---|
| 왼쪽 아래 신발+속도 / 돈다발+돈 | Attr `Speed`, `Money` |
| 오른쪽 아래 달·해 + 남은 시간 | GameState `Phase`, `PhaseEndsAt` |
| 위 가운데 구역 이름 배너 | `ZoneEntered` (+ Attr `CurrentZone`) |
| "달리기!!" 배너 + 빨간 비네트 + 경비 거리 | `RunAlert`, `ChaseEnded`(reason), Attr `CarryingEgg`, 경비 `TargetUserId` |
| 아래 빨간 "드롭" 버튼 | Attr `CarryingEgg ~= ""` 일 때 보이기 → `DropEgg()` |
| 머리 위 알 무게 | Attr `CarryWeightKg` (또는 알 파트 `WeightKg`) |
| 핫바 (1 방망이, 2 곰덫 x3, 3 알) | Backpack Tool + Attr `CarryingEgg` |
| 성장하는 달걀 패널 + ▶ 버튼 | `State.get().incubators` + `IncubatingEgg` 파트 `Progress`/`Required`, 버튼 → `HatchEgg(uid)` |
| **알 창 (가방, 2판 수정)** — 오른쪽 주황 알 버튼 배지 = `#snap.eggs` | `State.get().eggs` (`"eggs"` 섹션), 알 고르기 → 우리 바닥 클릭/터치 → `PlaceEgg(uid, x, z)`, 미리보기 `EggPlacement.check`, 우리 `#incubators / placedEggMax`, 가방 `#eggs / eggInventoryMax` |
| 우리 안 알 "에그 1m 52s" + E 부화 | `IncubatingEgg` 파트 (ProximityPrompt 는 선임이 붙임 → `HatchEgg`, 다시 줍기 → `PickUpPlacedEgg`) |
| 바닥 알 머리 위 "32초" (2판 수정) | `Egg` 파트 `EggState == "Dropped"` + `ExpiresAt` (서버 시각) |
| 펫 머리 위 "+$34K" 팝업 | `IncomeTick { petUid, amount }` (펫 모델은 PetVisualService 가 `petRect` 안에 배치) |
| 러닝머신 "+500" 팝업 + 제자리 달리기 | `TreadmillStep { amount }`, Attr `OnTreadmill` → 점프 시 `TreadmillLeave()` |
| 판매 가게 창 | 판매 가게 근처(14)에서 열기 → 펫 고르기 → `SellPet(uid)` → `Notify`. 미리보기 가격 = `Economy.recordIncome(pet) × Config.PET_SELL_SECONDS` |
| 펫 보관함 + Equip Best | `State.get().pets/equipped/penSlots`, `EquipPet`, `UnequipPet`, `EquipBest`, `n / petInventoryMax`, `PetsSold` |
| 도감(인덱스) + 모두 획득 | `indexDiscovered/indexClaimed`, `Progression.biomeProgress`, `ClaimIndexReward("all")` |
| 상점(우리/러닝머신/트레일) + 표지판 가격 | `Upgrades` 데이터 + `Economy.nextPenCost/nextTreadmillCost`, `PurchaseUpgrade(kind, id)` |
| 퓨전 머신 / 사쿠라 / 제단 / 비밀 통로 | 2단계와 같음 (`FuseRequest`·`FusionResult`, `SakuraOffer`·`SakuraApply`·`SakuraResult`, `AltarOffer`·`AltarUpdate`, `ShrineFuse`·`ShrineResult`). 5판: 퀘스트 창·문 없앰 |
| **튜토리얼 패널 (5판)** | `TutorialUpdate` / `State.get().tutorial` (`TutorialView`): "n / 5" + `text` 큰 글씨 + `hint` 작은 글씨, `done` 이면 숨김. 끝내는 순간 `reward`(500) 축하 연출. 화살표·강조는 선임 자유 (1 숲 둥지 · 2 허브 경계 `MapLayout.SAFE_ZONE_Z` · 3 핫바/알 창 + 내 우리 · 4 우리 안 알 · 5 펫 창 장착 버튼) |
| **랭킹판 (5판)** — 오른쪽 위 / 허브 판 | `LeaderboardUpdate { money, speed }` → 이름 + `Format.money(value)` / `Format.number(value)`, 내 줄(`userId == LocalPlayer.UserId`) 강조. 처음 들어오면 바로 한 번 옴 |
| **펫 쓰다듬기 (5판)** | 내 우리 PenPet 모델(Attr `PetUid`)에 ProximityPrompt/클릭 → `PetPet(petUid)` (서버가 20 스터드·1초 쿨다운 확인). `PetPetted(ownerUserId, petUid)` 받으면 그 펫 위 하트 + 소리 (모두의 화면) |
| 채팅 공지 / 잡힘 / 부화 / 오프라인 | `Announce`, `Caught`, `HatchResult`, `OfflineIncome` |

## 7. 2판 규칙 요약 (자세한 건 코드 맨 위 주석)

- **속도 → 걷기** (2판 수정, `SpeedMath.toWalkSpeed`): WalkSpeed = clamp(16 × (1 + log10(max(속도, 10) / 10)), 16, 150) → 속도 20 → 20.8 / 200 → 36.8 / 10K → 64 / 64K → 76.9 / 1M → 96 / 5.8M → 108.2 / 1B → 144 / 2.37B~ → 150. 알 무게 감소는 그대로 곱함(최소 8). Attr `WalkSpeed` 도 이 값.
- **경비** (`GuardianService`, `SpeedMath`, `Logic/GuardLogic`): 평소 집(구역 가운데)에서 잠(`Sleeping`). 그 구역 알을 누가 들면 깨어나 쫓음. **추격 포기 거리 없음** — 허브(z < 0)에 들어가거나(= 배달) / 잡히거나 / 알을 놓거나(DropEgg) / 밤이 될 때까지. 추격 목표 = 플레이어 위치 + 서버가 본 이동 속도 × 0.25초 (150 으로 도망가도 멈칫 없이 따라옴), 잡힘은 틱(0.1초) 사이 가장 가까웠던 거리로 판정. 먼 구역 알을 들고 앞 구역들을 지나가도 **그 구역 경비는 안 깨어남**. 추격 속도 = 플레이어 WalkSpeed × clamp(경비 속도 / 알 든 실효 속도 × 0.99, 0.85, 3.0), 1 이상이면 최소 1.2 → 추천 속도 이상(보통 알)이면 못 잡고, 모자라면 반드시 따라잡음. 잡힘 = 수평 (6 + 경비 키 × 0.25, 최대 16 — 키는 겉모습 모델 `Height` Attribute → `Visuals.guards.height` → 8, 경비 모델 Attribute `CatchDistance` 에 적힘) + 높이 10 이내, 둥지에서 주운 뒤 1.5초 유예(바닥 알 다시 줍기는 유예 없음). 경비끼리 30 안이면 옆으로 비켜 감.
- **잡힘 → 알**: 알의 구역(z 범위) 안에서 경비에게 잡히면 둥지로 (둥지 복귀는 이때만), 앞 구역·허브에서 잡히면 그 자리 (`EggRules.dropOutcome`). 플레이어 무기·곰덫·DropEgg 는 항상 그 자리.
- **떨어진 알** (2판 수정): 60초 동안 그 자리 (`ExpiresAt`), 누구나 다시 주움. 알이 구역 안에서 떨어져 둥지 예약을 갖고 있으면 그 둥지는 알이 사라질 때까지 비어 있다가 사라진 뒤 30초(낮)에 새 알, 아니면 다음 초기화(대기)에 새 알. 다시 주우면 예약도 넘어감.
- **배달** (2판 수정): 알을 든 채 허브(z < 0)에 들어오면 자동 → 알 가방 (높이 20 이상 공중이면 안 됨). 순간이동 의심 검사는 그대로.
- **알 가방 · 우리** (2판 수정): 가방(최대 50) → `PlaceEgg` 로 우리 안 원하는 자리 (최대 8개, 간격 4) → 놓인 알만 자람(밤 30배, 오프라인 24시간) → 다 자라면 `HatchEgg`. `PickUpPlacedEgg` 로 진행도 그대로 다시 가방.
- **러닝머신** (`TreadmillService`): 내 베이스 벨트에 올라서면 고정(WalkSpeed 0, 가운데로, 복도 쪽을 봄). 1초마다 속도 += 걸음당 속도 × 3 + `TreadmillStep`. 점프(`TreadmillLeave`)·벨트 이탈·알 듦·기절이면 내림. 내린 뒤엔 벨트 밖으로 한 번 나가야 다시 탐. 0레벨이면 안 타고 5초에 한 번 안내.
- **밤**: 허브 경계 벽 1장. 밤 시작 때 허브 밖(z ≥ 0)에 있던 사람(알을 들었든 아니든)은 내 베이스 앞마당으로 순간이동 (베이스가 없으면 `hubSpots.mainSpawn`) → 알을 들고 있었으면 허브라 바로 가방으로 배달.
- **판매**: 판매 가게 14 안, 가격 = 초당 수입 × 60 [추정].
- 퓨전·구역 무기·사쿠라·제단 규칙은 2단계 그대로 (`FusionRules`, `Data/Weapons`, `SakuraRules`, `AltarRules`). 5판: 퀘스트(`Data/Quests`·`QuestRules`) 없앰.
- **5판 튜토리얼** (`TutorialService`, `shared/TutorialRules`, `Data/Tutorial`): 저장 `tutorialStep` 1~5 / 6 = 끝. 진행·되돌림은 맨 위 [5판] 상자. 튜토리얼 중엔 부화 펫 자동 장착 안 함 (`Data/Tutorial.HOLD_AUTO_EQUIP`).
- **5판 랭킹판** (`LeaderboardService`): 10초마다 돈·실효 속도 상위 10명 fireAll. **5판 쓰다듬기** (`PetService.petPet`): 내 우리 20 안 · 장착 펫 · 1초 쿨다운.

## 8. 선임이 붙여야 할 것 (2판 체크리스트)

- [ ] 맵: `MapLayout` 숫자로 복도·허브·구역 15개·베이스 7개·둥지(Nest 태그 + NestIndex, `nestsFor` 자리)·밤 벽(`NIGHT_WALL`)·판매 가게(`SellStall` 태그)·러닝머신 벨트(`Treadmill` 태그, `treadmillRect` 크기 그대로)
- [ ] `ZoneController` 를 `MapLayout.zoneAt` 으로 (Zone 태그 사각형 판정 대신) + `ZoneEntered` 배너
- [ ] "드롭" 버튼 → `DropEgg()`, 알 무게 표시(`CarryWeightKg`)
- [ ] 러닝머신: `OnTreadmill` 이면 제자리 달리기 애니메이션 + 점프 시 `TreadmillLeave()`, `TreadmillStep` 팝업
- [ ] 펫 돈 팝업 (`IncomeTick`), 펫 배치는 `MapLayout.petRect`
- [ ] 우리 안 부화 알 E 프롬프트 → `HatchEgg`, 머리 위 남은 시간
- [ ] 판매 가게 창 → `SellPet(uid)`
- [ ] 경비 `State == "Sleeping"` 이면 Z 표시
- [ ] `DeliveryPad` 태그를 쓰는 코드 지우기 (WorldFxController, MapBuilder) → 그 뒤 수석이 Tags 에서 지움
- [x] ~~`tests/crossrefs.spec.luau` 의 `PENDING_UI`(DropEgg·SellPet·TreadmillLeave)~~ — 지움 (2판 마무리, 클라가 셋 다 보냄)
- [ ] **알 창 + 우리에 놓기 (2판 수정)**: 오른쪽 알 버튼 창에 `snap.eggs`(가방) 목록 → 알 고르면 놓기 모드 → 내 우리 바닥 클릭/터치 → `PlaceEgg(uid, hit.X, hit.Z)` (미리보기 `EggPlacement.check`). 놓인 알 다시 줍기 프롬프트/버튼 → `PickUpPlacedEgg(uid)`. 다 붙이면 `tests/crossrefs.spec.luau` 의 `AWAITING_CLIENT` 에서 `PlaceEgg`·`PickUpPlacedEgg` 지우기
- [ ] **2판 수정 클라 정리**: `EggDelivered` 토스트는 "가방에 넣었어요" 뜻으로, `EggGranted` 토스트 "부화 슬롯에 들어갔어요/기다리는 중" → "가방에 들어갔어요", `DebugController` 의 `EggDelivered` 출력(`record.slot` %d — 이제 nil 이라 에러), `IncubatorController` 의 `record.slot` 대신 순서, MapBuilder 받침(`IncubatorSlot`, `incubatorSpots`) 지우기, 바닥 알 "32초" 카운트다운(`ExpiresAt`)
- [x] (선임 5판 완료 — TutorialController) **5판 튜토리얼 패널**: `TutorialUpdate` / `State.get().tutorial` 로 "n/5 + 글" 패널, `done` 이면 숨김, 끝내는 순간 `reward` 축하 (6절). 튜토리얼 중엔 부화 펫이 자동 장착 안 되니 5단계에서 펫 창 장착 버튼을 눈에 띄게
- [x] (선임 5판 완료 — LeaderboardController + 허브 판 LeaderboardBoard) **5판 랭킹판**: `LeaderboardUpdate` → 오른쪽 위 리더보드(이름 / 돈 / 속도) + 허브 판(선택)
- [x] (선임 5판 완료 — PetVisualService 프롬프트·OwnerUserId + PetFxController, AWAITING_CLIENT 에서 PetPet 지움) **5판 쓰다듬기**: PenPet 모델에 프롬프트/클릭 → `PetPet(uid)`, `PetPetted(ownerUserId, uid)` → 하트·소리. 붙이면 `tests/crossrefs.spec.luau` 의 `AWAITING_CLIENT` 에서 `PetPet` 지우기
- [x] (선임 5판 완료) **5판 정리**: `Theme.Menu` 의 `quest`·`gift` 색(이제 안 씀), `NotifyController` 선물 알 출처 글, `docs/UI.md` 의 퀘스트·선물 설명
- [ ] **트레일 창 장착/장착 해제 버튼 → `EquipTrail(id)` / `EquipTrail("none")`** (2판 마무리). 버튼 글자는 `snap.equippedTrail == id` 이면 "장착 해제", 가졌으면 "장착", 아니면 가격. 붙이면 `tests/crossrefs.spec.luau` 의 `AWAITING_CLIENT` 에서 `EquipTrail` 지우기 (안 지우면 테스트가 알려 줌)

**서버가 계속 부르는 MapBuilder 공개 함수 (이름·모양 유지 부탁):** `start()`, `getFolder(name)` ("Eggs"/"Guardians"/"Traps"/"Incubating"), `getNests(biomeId): {BasePart}` (없으면 빈 표 → 서버가 `nestsFor` 자리 바닥에 놓음), `groundY(position, ignore): number`, `setNightWalls(on)`, `setPlotOwner(index, player?)`, `plotCount()`, `getPlot(index)` (서버는 이제 안 씀). **더 이상 안 부름:** `isInSafeZone`, `isInPlot`, `findBiomeAt`, `getZone`, `getZonePart`, `getGuardSpawn`.

## 9. 치트 방지 (서버, 클라는 할 일 없음)

- 1초마다 `HumanoidRootPart` 수평 이동 거리 > `WalkSpeed × 1.5 + 30` (경과초 비례) → 마지막 정상 위치로 되돌림 + 경고, 5번이면 Kick (경고는 2분마다 1개씩 줄어듦). 래그돌·곰덫·서버 순간이동(러닝머신 고정·밤 귀가) 직후는 검사 쉼. WalkSpeed 는 서버가 정한 새 곡선 값이라 자동으로 맞음 (2판 수정 최대 150 → 1초 255 까지 정상).
- 알을 든 사람: 0.2초에 `WalkSpeed × 0.2 × 1.5 + 8` 스터드보다 멀리 가면 알을 이전 위치에 떨어뜨림. 배달은 주운 곳 → 배달한 곳 거리 ÷ (`WalkSpeed × 1.3`) 보다 빨리 오면 거부(알은 둥지로).
- "근처여야 하는" 요청은 전부 서버가 거리 확인: 알 줍기(12), 크리스탈 줍기(12), 판매 가게(14), 퓨전 머신(12), 사쿠라 인큐베이터(14), 제단(14), 비밀 통로(14). 배달·러닝머신·허브는 `MapLayout` 사각형으로 판정.
