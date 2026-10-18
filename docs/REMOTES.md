# Remote 목록 (서버 ↔ 클라)

작성: 수석, 2026-10-18 (1단계) · 2단계 갱신 2026-10-18 (퓨전·구역 무기·사쿠라·제단·퀘스트·치트 방지). 선임이 UI·소리·연출을 붙일 때 보는 문서입니다.

- Remote 이름은 `src/shared/Remotes.luau` **한 곳**에서만 정의합니다. 서버(`src/server/Net.luau`)가 `ReplicatedStorage.Remotes` 폴더에 전부 RemoteEvent 로 만들고, 클라(`src/client/Net.luau`)는 `WaitForChild` 로 받습니다.
- RemoteFunction 은 쓰지 않습니다. 요청은 RemoteEvent 로 보내고, 결과는 서버가 다른 이벤트(`Notify`, `DataUpdate` 등)로 알려 줍니다.
- **치트 방지 원칙:** 돈·속도·펫을 직접 바꾸는 Remote 는 없습니다. 클라는 "요청"만 보내고 서버가 전부 검증합니다 (인자 타입 검사 + 플레이어·Remote 별 레이트 리밋 + 게임 규칙 검사 + "근처여야 하는" 요청은 서버가 캐릭터 위치로 거리 확인).
- **클라에서 캐릭터를 순간이동시키지 마세요.** 서버가 1초마다 이동 거리를 검사합니다(9절). 점프대·텔레포트 버튼이 필요하면 수석에게 서버 기능으로 요청.

클라 코드에서 쓰는 법:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Net = require(ReplicatedStorage.Client.Net)
local State = require(ReplicatedStorage.Client.State)

Net.on(Remotes.ToClient.RunAlert, function(payload) --[[ "RUN!!" 띄우기 ]] end)
Net.send(Remotes.ToServer.HatchEgg, eggUid)

State.onChanged(function(section) -- "snapshot" | "pets" | "incubators" | "index" | "upgrades" | "tools" | "flags" | "special" | "quests"
	local snap = State.get() -- Types.Snapshot (src/shared/Types.luau)
end)
```

---

## 1. 서버 → 클라 (클라가 받는 이벤트)

| 이름 | 언제 | 인자 (payload) |
|---|---|---|
| `Snapshot` | 접속해서 데이터를 불러온 직후, `RequestSnapshot` 요청 때, 늦게 베이스를 받았을 때 | `Types.Snapshot` 전체 (아래 4절) |
| `DataUpdate` | 상태 일부가 바뀔 때 | `(section: string, payload: table)` — 5절 표. `State` 모듈이 자동으로 합쳐 줌 |
| `Notify` | 성공/실패 안내 한 줄 | `{ kind: "info" \| "success" \| "error", text: string }` |
| `Announce` | 서버 전체 공지 (채팅에도 표시됨) | `{ kind, text, ... }` — kind: `"reset"`("ALL EGG RESET!"), `"rareEgg"`(+ `biomeId, petId, rarity, eggUid, questOnly?`), `"night"`, `"day"` |
| `PhaseChanged` | 낮/밤/대기 바뀔 때 | `{ phase: "Day"\|"Night"\|"Intermission", endsAt: number, duration: number, cycleNumber: number, heavenSide: "light"\|"dark"\|nil }` — `endsAt` 은 `workspace:GetServerTimeNow()` 기준 |
| `RunAlert` | 내가 알을 든 순간 ("RUN!!") | `{ egg: EggInfo, guardName: string, guardSpeed: number, yourSpeed: number }` |
| `ChaseEnded` | 나를 쫓던 경비가 포기/멈춤 | `{ biomeId: string }` |
| `Caught` | 경비에게 잡힘 / 무기에 맞음 / 곰덫 밟음 | `{ cause: "guard"\|"player"\|"trap", by: string, eggOutcome: "ReturnToNest"\|"DropHere"\|"None", ragdollSeconds: number, knockback: Vector3?, stunSeconds: number? }` — 곰덫도 이제 알이 없었으면 `"None"` |
| `EggDelivered` | 배달 패드에 알을 올려 부화 슬롯에 등록됨 | `IncubatorRecord` (`uid, petId, size, mutations, biomeId, slot, progress, required`) |
| `HatchResult` | 부화 성공 | `{ pet: PetRecord, isNew: boolean (도감 첫 발견), income: number (초당), equipped: boolean, sold: boolean }` — `sold` = 보관함이 가득 차서 바로 팔림 |
| `OfflineIncome` | 접속 때 오프라인 수입 지급 (60초 이상 비웠을 때) | `{ amount: number, seconds: number, perDay: number, text: string }` → "You earn $16M/Day offline!" 팝업 |
| `IndexRewarded` | 도감 보상 수령 | `{ petIds: {string}, speed: number, money: number, completeBonus: boolean }` |
| **`FusionResult`** (2단계) | 퓨전 성공 | `{ consumed: {uid}, pet: PetRecord, upgraded: boolean (희귀도 업 / false = 같은 펫 크기 업), bonusMutation: string? (새로 붙은 실버/골든/레인보우), inputIncome: number, income: number, isNew: boolean, equipped: boolean }` |
| **`EggGranted`** (2단계) | 선물 알(제단·비밀 통로·퀘스트)이 부화 슬롯에 들어감 / 대기 줄에 섬 | `{ record: IncubatorRecord, queued: false, source }` 또는 `{ egg: QueuedEgg, queued: true, source }` — source: `"altar"\|"shrine"\|"quest"` |
| **`SakuraResult`** (2단계) | 사쿠라 인큐베이터 해금 / 블룸 부여 | 해금: `{ kind: "unlocked", consumed: petUid, crystals }` · 블룸: `{ kind: "bloom", targetUid, target: "egg"\|"pet", mutation: "bloom"\|"spirit_bloom", crystals }` |
| **`AltarUpdate`** (2단계) | 제단 제물 상태 | `{ status: "pending"\|"paired"\|"expired", side: "light"\|"dark", petId, partner?: string (짝 이름), eggPetId?: "ring_guard"\|"ringlord" }` |
| **`ShrineResult`** (2단계) | 비밀 통로 합성 성공 | `{ consumed: {uid, uid}, resultPetId: "equinox"\|"aetheron", size, mutations }` (알은 `EggGranted` 로도 옴) |
| **`QuestUpdate`** (2단계) | 마법의 숲 퀘스트 진행도가 바뀜 | `{ quests: { QuestView }, allDone: boolean, gateOpen: boolean }` — `QuestView = { id, name, progress, target, done }` |
| **`PetsSold`** (2단계) | 보관함이 500마리를 넘어 싼 펫이 자동 판매됨 | `{ pets: { PetRecord }, money: number }` |

`EggInfo` = `{ uid, petId, biomeId, rarity, size, mutations: {string}, special: boolean }`

## 2. 클라 → 서버 (클라가 보내는 요청)

| 이름 | 인자 | 서버 검증 | 레이트 리밋 (burst / 초당) |
|---|---|---|---|
| `RequestSnapshot` | 없음 | — | 3 / 0.5 |
| `HatchEgg` | `eggUid: string` (부화 슬롯 uid, `"i12"` 형태) | uid 형식, 내 슬롯에 있는지, 다 자랐는지 (Growing Eggs 패널 버튼이라 거리 검사 없음) | 10 / 4 |
| `EquipPet` | `petUid: string` | 내 펫인지, 이미 장착인지, 우리 칸 남았는지 | 10 / 5 |
| `UnequipPet` | `petUid: string` | 장착돼 있는지 | 10 / 5 |
| `EquipBest` | 없음 | 서버가 수입 순으로 칸 수만큼 고름 | 2 / 0.5 |
| `PurchaseUpgrade` | `kind: "Pen"\|"Treadmill"\|"Trail"`, `trailId: string?` (Trail 일 때만) | 종류·id 허용 목록, 다음 레벨 있는지, 돈 충분한지 (상점 화면 버튼이라 거리 검사 없음) | 5 / 2 |
| `UseTool` | `kind`: `"Bat"\|"BearTrap"\|"WaterBat"\|"Katana"\|"Axe"\|"AngelSpear"\|"Hammer"\|"CandyCane"\|"Scythe"` (`Remotes.ToolKinds`) | 그 도구를 손에 들고 있는지, 구역 무기는 해금했는지, 근접 무기 공용 쿨다운, 안전 구역 아닌지, 곰덫 개수. **대상·위치는 서버가 찾음** | 4 / 2 |
| `ClaimIndexReward` | `"all"` 또는 `petId` | 발견했고 아직 안 받았는지 | 5 / 1 |
| `ClaimFreeReward` | 없음 | 계정당 1번 (그룹 ID 설정 시 가입 확인) | 2 / 0.2 |
| **`FuseRequest`** (2단계) | `petUid1, petUid2, petUid3` | **내 베이스 퓨전 머신 12스터드 안**, 서로 다른 내 펫 3마리, 같은 petId, 결과가 3마리 합보다 약해질 수밖에 없으면 거부. 장착 중이면 자동 해제 | 3 / 1 |
| **`SakuraOffer`** (2단계) | `petUid?` (생략하면 가진 학 중 수입이 가장 낮은 학) | **사쿠라 인큐베이터 14스터드 안**, 아직 해금 안 함, 학(Crane) 펫 | 2 / 0.5 |
| **`SakuraApply`** (2단계) | `targetUid` (부화 중 알 `"i.."` 또는 보관 펫 `"p.."`) | **인큐베이터 14스터드 안**, 해금함, 크리스탈 1개 이상, 대상에 블룸 계열이 아직 없음 | 5 / 2 |
| **`AltarOffer`** (2단계) | `petUid` | **천국/지옥 제단 14스터드 안**(가까운 제단의 Side), 그 쪽 펫인지, 이번 주기에 아직 안 바쳤는지, 알 받을 자리(빈 슬롯 또는 대기 줄)가 있는지 | 3 / 1 |
| **`ShrineFuse`** (2단계) | `petUidA, petUidB` | **비밀 통로 제단 14스터드 안**, 레시피(페가수스+스켈레톤 말 / 대천사+세계를 불태우는 자), 계정당 1번, 알 받을 자리 | 2 / 0.5 |

- **알 줍기**는 Remote 가 아니라 서버가 만든 `ProximityPrompt`(E 키, 알 파트 안의 `StealPrompt`)로 합니다. 서버가 거리·낮인지·이미 들고 있는지·(퀘스트 전용 알이면) 퀘스트 완료했는지 확인합니다.
- **사쿠라 크리스탈 줍기**도 `ProximityPrompt`(크리스탈 파트 안의 `CrystalPrompt`). 서버가 거리 확인.
- **배달**도 Remote 없음: 알을 든 채 내 베이스 `DeliveryPad` 반경 안에 들어가면 서버가 자동 처리 (주운 곳에서 너무 빨리 왔으면 거부 → 알은 둥지로).
- **러닝머신**도 Remote 없음: 내 베이스 `Treadmill` 패드 위에 서 있으면 서버가 1초마다 속도를 올림.
- 도구: 서버가 Backpack 에 `Tool`(이름 = kind, `RequiresHandle = false`, Attribute `ToolKind`, 무기는 `WeaponId`·`Range`, 곰덫은 `Count`)을 넣어 줌. 기본 클라(`ToolController`)가 `Remotes.ToolKinds` 에 있는 이름의 Tool 이 `Activated` 될 때 `UseTool` 을 보냄 → **구역 무기도 따로 할 일 없이 동작**. 무기 모양(손잡이 메시)·휘두르기 애니메이션·소리는 선임 몫. 사거리·넉백·쿨다운 표는 `src/shared/Data/Weapons.luau`.

## 3. Attribute 로 복제되는 값 (자주 바뀌는 숫자)

### 플레이어 (`Players.LocalPlayer:GetAttribute(...)`, 이름은 `Tags.PlayerAttributes`)

| Attribute | 뜻 |
|---|---|
| `Money` | 돈 (number, 소수 가능 — 표시할 때 `Format.money`) |
| `Speed` | 실효 속도 = 모은 속도 × 트레일 배율 (경비 비교에 쓰는 숫자) |
| `BaseSpeed` | 모은 속도 (트레일 전) |
| `WalkSpeed` | 서버가 정한 실제 이동 속도 |
| `IncomePerSecond` | 장착 펫 초당 수입 합 |
| `PlotIndex` | 내 베이스 번호 (1~7, 0 = 없음 → 누가 나가면 바로 배정되고 `Snapshot` 다시 옴) |
| `PenLevel`, `PenSlots` | 우리 레벨, 장착 칸 수 |
| `TreadmillLevel` | 러닝머신 레벨 (0 = 잠김) |
| `TrailMultiplier` | 적용 중인 트레일 배율 |
| `CarryingEgg`, `CarryingBiome` | 든 알 uid / 구역 id (`""` = 없음) → "RUN!!" 화면 유지 조건 |
| `Stunned` | 래그돌·곰덫 중 |
| `InSafeZone` | 안전 구역(베이스 근처) 안인지 → "안전 구역" 표시 |
| `DataLoaded`, `SaveEnabled` | 데이터 로딩 끝났는지, 저장되는 세션인지 (다른 서버가 데이터를 가져가면 도중에 false 로 바뀜) |
| **`SakuraCrystals`** (2단계) | 사쿠라 크리스탈 개수 |
| **`SakuraUnlocked`** (2단계) | 사쿠라 인큐베이터 해금 |
| **`QuestsDone`** (2단계) | 마법의 숲 퀘스트 3개 완료 → 퀘스트 문을 통과할 수 있음 (문을 반투명하게 보여 주는 등 연출용) |
| **`MoveWarnings`** (2단계) | 비정상 이동 경고 수 (5 = Kick, 시간이 지나면 줄어듦) |

leaderstats 에는 `Money`, `Speed` 가 보기 좋은 글자(StringValue, 예 `"$1.5K"`)로 들어 있습니다.

### 서버 상태 (`ReplicatedStorage.GameState` 폴더, 이름은 `Tags.StateAttributes`)

| Attribute | 뜻 |
|---|---|
| `Phase` | `"Day"` / `"Night"` / `"Intermission"` |
| `PhaseEndsAt` | 끝나는 시각 (`workspace:GetServerTimeNow()` 기준) → 남은 시간 = `PhaseEndsAt - workspace:GetServerTimeNow()` |
| `PhaseDuration` | 이번 단계 길이(초) |
| `CycleNumber` | 몇 번째 주기 (제단 제물은 같은 주기 안에서만 짝이 맞음) |
| `HeavenSide` | 천사&악마 구역 이번 쪽 `"light"` / `"dark"` |

### 월드 오브젝트 Attribute / 태그 (UI·연출용, 이름은 `Tags`)

- 경비 모델(`Guardian` 태그): `BiomeId`, `GuardName`, `State`(`"Idle"`/`"Chase"`/`"Return"`), `TargetUserId` → **경비 거리 표시**는 클라에서 `TargetUserId == 내 UserId` 인 경비의 `HumanoidRootPart` 와 내 거리로 계산.
- 알 파트(`Egg` 태그): `EggUid, PetId, BiomeId, Rarity, Size, Mutations("silver,bloom" 식), Special, QuestOnly, EggState("Nest"/"Carried"/"Dropped")`. 파트는 Ball + 기본 `SpecialMesh` "EggShape"(Y 1.25배) — EggVisualService 가 껍데기를 따로 붙이면 지워도 됨.
- 부화 중 알(`IncubatingEgg` 태그): `EggUid, OwnerUserId, PetId, SlotIndex, Size, Mutations, Progress, Required, Ready` (1초마다 갱신, 사쿠라 블룸이 붙으면 `Mutations` 바뀜)
- **2단계 특수 장소** — 맵(`Workspace.Map`)에 같은 태그·Attribute 파트가 있으면 그걸 쓰고, 없으면 서버가 구역 안에 임시 파트를 `Workspace.Map.Specials` 에 만듦(Attribute `Placeholder = true`). 선임이 진짜 모델을 두면 임시 파트는 안 생김. 거리 판정은 파트 상자 표면 기준.
  - `SakuraIncubator` (벚꽃 구역): 인큐베이터
  - `Altar` (천사&악마): Attribute `Side` = `"light"`(천국) / `"dark"`(지옥) **꼭 필요**, 서버가 `PendingCount`(기다리는 제물 수)를 씀
  - `Shrine` (천사&악마 비밀 통로, 폭포 옆): 합성 제단
  - `QuestGate` (마법의 숲): 퀘스트 문. 서버가 `CollisionGroup = "QuestGate"` 로 바꿈, 퀘스트를 끝낸 사람 캐릭터는 `"QuestPassed"` 그룹(문과 안 부딪힘). 문 파트는 `CanCollide = true` 로 두세요.
  - `SakuraCrystal` (서버가 만듦): 초기화 때 벚꽃 둥지 근처 3개, Attribute `CrystalUid`, 안에 `CrystalPrompt`. 다음 초기화 때 사라짐.
- `FusionMachine` (베이스, `PlotIndex`): 퓨전 머신. 없으면 "내 베이스 안"이면 퓨전 가능.

## 4. Snapshot 모양 (`Types.Snapshot`)

```
money, speed, effectiveSpeed, incomePerSecond,
pets: { PetRecord },            -- PetRecord = { uid, petId, size, mutations }  (최대 petInventoryMax = 500)
equipped: { uid },
penLevel, penSlots, treadmillLevel,
trails: { trailId }, trailMultiplier,
indexDiscovered: { [petId]: true }, indexClaimed: { [petId]: true }, indexCompleteClaimed,
unlockedWeapons: { weaponId },  -- 저장된 해금 무기 (Data/Weapons id, 기본 방망이 제외)
tools: { bearTrap = n },
incubators: { IncubatorRecord },
eggQueue: { QueuedEgg },        -- 부화 슬롯이 가득 차서 기다리는 선물 알 { petId, size, mutations, source }
freeRewardClaimed, plotIndex, saveEnabled,
-- 2단계
sakuraCrystals, sakuraUnlocked,
shrineUsed: { [resultPetId]: true },  -- "equinox" / "aetheron" 합성 사용 여부
quests: { QuestView }, questsDone,
petInventoryMax
```

## 5. DataUpdate 섹션

| section | payload |
|---|---|
| `"pets"` | `{ pets, equipped, penSlots, incomePerSecond }` — **장착만 바뀔 때는 `pets` 가 빠짐** (`State` 가 합치므로 `State.get().pets` 는 그대로) |
| `"incubators"` | `{ incubators, eggQueue }` (배달·부화·다 자람·선물 알·블룸 때) |
| `"index"` | `{ indexDiscovered, indexClaimed, indexCompleteClaimed, unlockedWeapons }` |
| `"upgrades"` | `{ penLevel, penSlots, treadmillLevel, trails, trailMultiplier }` |
| `"tools"` | `{ tools }` |
| `"flags"` | `{ freeRewardClaimed }` |
| **`"special"`** (2단계) | `{ sakuraCrystals, sakuraUnlocked, shrineUsed }` |
| **`"quests"`** (2단계) | `{ quests, questsDone }` |

## 6. 화면별로 필요한 것 (설계문서 12장 기준)

| 화면 | 쓸 것 |
|---|---|
| 상단 돈/속도/낮밤 타이머 | Attr `Money`, `Speed` / GameState `Phase`, `PhaseEndsAt` |
| "RUN!!" + 경비 거리 | `RunAlert`, `ChaseEnded`, Attr `CarryingEgg`, 경비 `TargetUserId` |
| Growing Eggs 패널 + Hatch 버튼 | `State.get().incubators` + `IncubatingEgg` 파트의 `Progress`/`Required`, 버튼 → `HatchEgg(uid)`. 남은 시간 = `(Required - Progress) / 성장속도` (밤 30배: `Phase == "Night"`). 대기 줄 `eggQueue` 개수도 표시 |
| 펫 보관함 + Equip Best | `State.get().pets/equipped/penSlots`, `EquipPet`, `UnequipPet`, `EquipBest`. 수입 표시는 `Economy.recordIncome(record)` (shared). `n / petInventoryMax` 표시, `PetsSold` 알림 |
| 도감 + Claim All | `indexDiscovered/indexClaimed`, `Progression.biomeProgress`, 무기까지 남은 수 `Progression.weaponProgress`(천사&악마는 18종), `ClaimIndexReward("all")`, 보상 미리보기 `Progression.pendingRewards` |
| 상점(우리/러닝머신/트레일) | `Upgrades` 데이터 + `Economy.nextPenCost/nextTreadmillCost`, `PurchaseUpgrade(kind, id)` |
| 선물상자(무료 보상) | `freeRewardClaimed`, `ClaimFreeReward` |
| 오프라인 수입 팝업 | `OfflineIncome` |
| 채팅 공지 | `Announce` (기본 `AnnounceController` 가 이미 채팅에 띄움) |
| 잡힘 연출(퍽+휘익) | `Caught` (기본 `RagdollController` 가 넘어뜨림) |
| 부화 연출(빠직+반짝) | `HatchResult` |
| **퓨전 머신 화면** (2단계) | 퓨전 머신 근처에서 열기(`ProximityPrompt` 를 클라에서 만들거나 거리로 판단) → 같은 펫 3마리 고르기 → `FuseRequest(u1,u2,u3)` → `FusionResult` 연출. 미리보기는 `FusionRules.candidates(petId)`(나올 수 있는 펫), `FusionRules.fuse` 는 서버만 |
| **사쿠라 인큐베이터 화면** (2단계) | Attr `SakuraUnlocked`/`SakuraCrystals`. 잠김: "학 바치기" → `SakuraOffer()`. 열림: 부화 중 알·보관 펫 목록에서 고르기 → `SakuraApply(uid)` → `SakuraResult`. 블룸 이미 있는 대상은 회색(`SakuraRules.hasBloom`) |
| **제단** (2단계) | 제단 근처에서 그 쪽 펫 고르기 → `AltarOffer(uid)` → `AltarUpdate`(pending → paired/expired). 제단 파트 `PendingCount` 로 "누군가 기다리는 중" 표시 |
| **비밀 통로 합성** (2단계) | 두 펫 고르기 → `ShrineFuse(a, b)` → `ShrineResult` + `EggGranted`. `shrineUsed` 로 "이미 사용" 표시 |
| **퀘스트 패널** (2단계) | `State.get().quests` / `QuestUpdate` (진행도 막대), Attr `QuestsDone` → 문 연출 |
| **선물 알 알림** (2단계) | `EggGranted` (queued = true 면 "슬롯이 가득 차서 기다리는 중") |
| **경고 표시** (2단계) | Attr `MoveWarnings` (선택) + `Notify` |

## 7. 2단계 규칙 요약 (자세한 건 코드 맨 위 주석)

- 퓨전 (`shared/FusionRules.luau`): 같은 펫 3마리 → 같은 구역 희귀도 +1 둥지 펫 중 하나(천사&악마는 같은 쪽 우선, 퀘스트·합성·제단 펫 제외). 없으면 같은 펫 크기 +1. 결과 수입 < 3마리 합이면 크기를 올려 보정, 초거대로도 안 되면 거부. 돌연변이는 셋이 같을 때만 유지. 10% 로 실버/골든/레인보우(5:2:0.5) 보너스(더 좋은 자연 돌연변이가 있으면 유지).
- 구역 무기 (`shared/Data/Weapons.luau`): 구역 도감 완성(천사&악마는 합성 2종 제외 18종) → 무기 해금(저장) → 바로 Backpack 에 Tool 지급.
- 사쿠라 (`shared/SakuraRules.luau`): 학 1마리로 해금, 크리스탈 1개 → 블룸 97.5%(×1.5) / 스피릿 블룸 2.5%(×3). 크리스탈 = 벚꽃 알 배달마다 1개 + 초기화마다 벚꽃 둥지 근처 3개.
- 제단 (`shared/AltarRules.luau`): 같은 주기, 천국 제단·지옥 제단에 서로 다른 두 사람 → 둘 다 링 가드 80% / 링로드 20% 알.
- 마법의 숲 퀘스트 (`shared/Data/Quests.luau`): 마법의 숲 알 20개 배달 / 퓨전 1회 / 영원 알 1개 배달 → 문 + 지터버그 알, 이후 초기화마다 1% 로 영혼 세계 수호자 알(퀘스트 끝낸 사람만 주움).

## 8. 선임이 붙여야 할 것 (체크리스트)

- [ ] 퓨전 머신 화면 (`FuseRequest`, `FusionResult`)
- [ ] 무기 Tool 7개 모양·휘두르기 애니메이션·맞는 소리 (`Tool.Name` = `Remotes.ToolKinds`, `Activated` 처리는 기존 `ToolController` 가 함)
- [ ] 사쿠라 인큐베이터 모델(Tag `SakuraIncubator`) + 화면 (`SakuraOffer`, `SakuraApply`, `SakuraResult`) + 크리스탈 반짝임(Tag `SakuraCrystal`)
- [ ] 제단 2개 모델(Tag `Altar`, Attr `Side`) + 제물 고르기 화면 (`AltarOffer`, `AltarUpdate`)
- [ ] 비밀 통로(폭포 옆) 모델(Tag `Shrine`) + 합성 화면 (`ShrineFuse`, `ShrineResult`)
- [ ] 퀘스트 문 모델(Tag `QuestGate`, CanCollide true) + 퀘스트 패널 (`QuestUpdate`, Attr `QuestsDone`)
- [ ] 선물 알 알림 (`EggGranted`), 자동 판매 알림 (`PetsSold`), 보관함 `n/500`
- [ ] Growing Eggs 패널에 대기 줄(`eggQueue`) 개수

## 9. 치트 방지 (서버, 클라는 할 일 없음)

- 1초마다 `HumanoidRootPart` 수평 이동 거리 > `WalkSpeed × 1.5 + 30` (경과초 비례) → 마지막 정상 위치로 되돌림 + 경고, 5번이면 Kick (경고는 2분마다 1개씩 줄어듦, 저장 안 함). 래그돌·곰덫·서버 순간이동 직후는 검사 쉼.
- 알을 든 사람: 0.2초에 `WalkSpeed × 0.2 × 1.5 + 8` 스터드보다 멀리 가면 알을 이전 위치에 떨어뜨림. 배달은 주운 곳 → 패드 거리 ÷ (`WalkSpeed × 1.3`) 보다 빨리 오면 거부(알은 둥지로).
- "근처여야 하는" 요청은 전부 서버가 거리 확인: 알 줍기(12), 크리스탈 줍기(12), 배달 패드(9), 러닝머신(5), 퓨전 머신(12), 사쿠라 인큐베이터(14), 제단(14), 비밀 통로(14). 무기 사거리·곰덫 설치 위치도 서버가 계산.
