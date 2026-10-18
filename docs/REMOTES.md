# Remote 목록 (서버 ↔ 클라)

작성: 수석, 2026-10-18 (1단계). 선임이 UI·소리·연출을 붙일 때 보는 문서입니다.

- Remote 이름은 `src/shared/Remotes.luau` **한 곳**에서만 정의합니다. 서버(`src/server/Net.luau`)가 `ReplicatedStorage.Remotes` 폴더에 전부 RemoteEvent 로 만들고, 클라(`src/client/Net.luau`)는 `WaitForChild` 로 받습니다.
- RemoteFunction 은 쓰지 않습니다. 요청은 RemoteEvent 로 보내고, 결과는 서버가 다른 이벤트(`Notify`, `DataUpdate` 등)로 알려 줍니다.
- **치트 방지 원칙:** 돈·속도·펫을 직접 바꾸는 Remote 는 없습니다. 클라는 "요청"만 보내고 서버가 전부 검증합니다 (인자 타입 검사 + 플레이어·Remote 별 레이트 리밋 + 게임 규칙 검사).

클라 코드에서 쓰는 법:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Net = require(ReplicatedStorage.Client.Net)
local State = require(ReplicatedStorage.Client.State)

Net.on(Remotes.ToClient.RunAlert, function(payload) --[[ "RUN!!" 띄우기 ]] end)
Net.send(Remotes.ToServer.HatchEgg, eggUid)

State.onChanged(function(section) -- "snapshot" | "pets" | "incubators" | "index" | "upgrades" | "tools" | "flags"
	local snap = State.get() -- Types.Snapshot (src/shared/Types.luau)
end)
```

---

## 1. 서버 → 클라 (클라가 받는 이벤트)

| 이름 | 언제 | 인자 (payload) |
|---|---|---|
| `Snapshot` | 접속해서 데이터를 불러온 직후, `RequestSnapshot` 요청 때 | `Types.Snapshot` 전체 (아래 4절) |
| `DataUpdate` | 상태 일부가 바뀔 때 | `(section: string, payload: table)` — 5절 표. `State` 모듈이 자동으로 합쳐 줌 |
| `Notify` | 성공/실패 안내 한 줄 | `{ kind: "info" \| "success" \| "error", text: string }` |
| `Announce` | 서버 전체 공지 (채팅에도 표시됨) | `{ kind, text, ... }` — kind: `"reset"`("ALL EGG RESET!"), `"rareEgg"`(+ `biomeId, petId, rarity, eggUid`), `"night"`, `"day"` |
| `PhaseChanged` | 낮/밤/대기 바뀔 때 | `{ phase: "Day"\|"Night"\|"Intermission", endsAt: number, duration: number, cycleNumber: number, heavenSide: "light"\|"dark"\|nil }` — `endsAt` 은 `workspace:GetServerTimeNow()` 기준 |
| `RunAlert` | 내가 알을 든 순간 ("RUN!!") | `{ egg: EggInfo, guardName: string, guardSpeed: number, yourSpeed: number }` |
| `ChaseEnded` | 나를 쫓던 경비가 포기/멈춤 | `{ biomeId: string }` |
| `Caught` | 경비에게 잡힘 / 방망이에 맞음 / 곰덫 밟음 | `{ cause: "guard"\|"player"\|"trap", by: string, eggOutcome: "ReturnToNest"\|"DropHere"\|"None", ragdollSeconds: number, knockback: Vector3?, stunSeconds: number? }` |
| `EggDelivered` | 배달 패드에 알을 올려 부화 슬롯에 등록됨 | `IncubatorRecord` (`uid, petId, size, mutations, biomeId, slot, progress, required`) |
| `HatchResult` | 부화 성공 | `{ pet: PetRecord, isNew: boolean (도감 첫 발견), income: number (초당), equipped: boolean }` |
| `OfflineIncome` | 접속 때 오프라인 수입 지급 (60초 이상 비웠을 때) | `{ amount: number, seconds: number, perDay: number, text: string }` → "You earn $16M/Day offline!" 팝업 |
| `IndexRewarded` | 도감 보상 수령 | `{ petIds: {string}, speed: number, money: number, completeBonus: boolean }` |

`EggInfo` = `{ uid, petId, biomeId, rarity, size, mutations: {string}, special: boolean }`

## 2. 클라 → 서버 (클라가 보내는 요청)

| 이름 | 인자 | 서버 검증 | 레이트 리밋 (burst / 초당) |
|---|---|---|---|
| `RequestSnapshot` | 없음 | — | 3 / 0.5 |
| `HatchEgg` | `eggUid: string` (부화 슬롯 uid, `"i12"` 형태) | uid 형식, 내 슬롯에 있는지, 다 자랐는지 | 10 / 4 |
| `EquipPet` | `petUid: string` | 내 펫인지, 이미 장착인지, 우리 칸 남았는지 | 10 / 5 |
| `UnequipPet` | `petUid: string` | 장착돼 있는지 | 10 / 5 |
| `EquipBest` | 없음 | 서버가 수입 순으로 칸 수만큼 고름 | 2 / 0.5 |
| `PurchaseUpgrade` | `kind: "Pen"\|"Treadmill"\|"Trail"`, `trailId: string?` (Trail 일 때만) | 종류·id 허용 목록, 다음 레벨 있는지, 돈 충분한지 | 5 / 2 |
| `UseTool` | `kind: "Bat"\|"BearTrap"` | 도구를 손에 들고 있는지, 쿨다운, 안전 구역 아닌지, 곰덫 개수. **대상·위치는 서버가 찾음** | 4 / 2 |
| `ClaimIndexReward` | `"all"` 또는 `petId` | 발견했고 아직 안 받았는지 | 5 / 1 |
| `ClaimFreeReward` | 없음 | 계정당 1번 (그룹 ID 설정 시 가입 확인) | 2 / 0.2 |

- **알 줍기**는 Remote 가 아니라 서버가 만든 `ProximityPrompt`(E 키, 알 파트 안의 `StealPrompt`)로 합니다. 서버가 거리·낮인지·이미 들고 있는지 확인합니다.
- **배달**도 Remote 없음: 알을 든 채 내 베이스 `DeliveryPad` 반경 안에 들어가면 서버가 자동 처리.
- **러닝머신**도 Remote 없음: 내 베이스 `Treadmill` 패드 위에 서 있으면 서버가 1초마다 속도를 올림.
- 도구: 서버가 Backpack 에 `Tool`(이름 = `"Bat"`, `"BearTrap"`, `RequiresHandle = false`)을 넣어 줌. 기본 클라(`ToolController`)가 `Tool.Activated` 때 `UseTool` 을 보냄. 모바일 버튼을 따로 만들면 `Net.send("UseTool", "Bat")` 만 부르면 됩니다 (단, 서버는 그 도구를 **손에 들고 있어야** 처리함).

## 3. Attribute 로 복제되는 값 (자주 바뀌는 숫자)

### 플레이어 (`Players.LocalPlayer:GetAttribute(...)`, 이름은 `Tags.PlayerAttributes`)

| Attribute | 뜻 |
|---|---|
| `Money` | 돈 (number, 소수 가능 — 표시할 때 `Format.money`) |
| `Speed` | 실효 속도 = 모은 속도 × 트레일 배율 (경비 비교에 쓰는 숫자) |
| `BaseSpeed` | 모은 속도 (트레일 전) |
| `WalkSpeed` | 서버가 정한 실제 이동 속도 |
| `IncomePerSecond` | 장착 펫 초당 수입 합 |
| `PlotIndex` | 내 베이스 번호 (1~7, 0 = 없음) |
| `PenLevel`, `PenSlots` | 우리 레벨, 장착 칸 수 |
| `TreadmillLevel` | 러닝머신 레벨 (0 = 잠김) |
| `TrailMultiplier` | 적용 중인 트레일 배율 |
| `CarryingEgg`, `CarryingBiome` | 든 알 uid / 구역 id (`""` = 없음) → "RUN!!" 화면 유지 조건 |
| `Stunned` | 래그돌·곰덫 중 |
| `InSafeZone` | 안전 구역(베이스 근처) 안인지 → "안전 구역" 표시 |
| `DataLoaded`, `SaveEnabled` | 데이터 로딩 끝났는지, 저장되는 세션인지 |

leaderstats 에는 `Money`, `Speed` 가 보기 좋은 글자(StringValue, 예 `"$1.5K"`)로 들어 있습니다.

### 서버 상태 (`ReplicatedStorage.GameState` 폴더, 이름은 `Tags.StateAttributes`)

| Attribute | 뜻 |
|---|---|
| `Phase` | `"Day"` / `"Night"` / `"Intermission"` |
| `PhaseEndsAt` | 끝나는 시각 (`workspace:GetServerTimeNow()` 기준) → 남은 시간 = `PhaseEndsAt - workspace:GetServerTimeNow()` |
| `PhaseDuration` | 이번 단계 길이(초) |
| `CycleNumber` | 몇 번째 주기 |
| `HeavenSide` | 천사&악마 구역 이번 쪽 `"light"` / `"dark"` |

### 월드 오브젝트 Attribute (UI·연출용)

- 경비 모델(`Guardian` 태그): `BiomeId`, `GuardName`, `State`(`"Idle"`/`"Chase"`/`"Return"`), `TargetUserId` → **경비 거리 표시**는 클라에서 `TargetUserId == 내 UserId` 인 경비의 `HumanoidRootPart` 와 내 거리로 계산.
- 알 파트(`Egg` 태그): `EggUid, PetId, BiomeId, Rarity, Size, Mutations("silver,bloom" 식), Special, EggState("Nest"/"Carried"/"Dropped")`
- 부화 중 알(`IncubatingEgg` 태그): `EggUid, OwnerUserId, PetId, SlotIndex, Progress, Required, Ready` (1초마다 갱신)

## 4. Snapshot 모양 (`Types.Snapshot`)

```
money, speed, effectiveSpeed, incomePerSecond,
pets: { PetRecord },            -- PetRecord = { uid, petId, size, mutations }
equipped: { uid },
penLevel, penSlots, treadmillLevel,
trails: { trailId }, trailMultiplier,
indexDiscovered: { [petId]: true }, indexClaimed: { [petId]: true }, indexCompleteClaimed,
unlockedWeapons: { weaponId },
tools: { bearTrap = n },
incubators: { IncubatorRecord },
freeRewardClaimed, plotIndex, saveEnabled
```

## 5. DataUpdate 섹션

| section | payload |
|---|---|
| `"pets"` | `{ pets, equipped, penSlots, incomePerSecond }` |
| `"incubators"` | `{ incubators }` (배달·부화·다 자람 때) |
| `"index"` | `{ indexDiscovered, indexClaimed, indexCompleteClaimed, unlockedWeapons }` |
| `"upgrades"` | `{ penLevel, penSlots, treadmillLevel, trails, trailMultiplier }` |
| `"tools"` | `{ tools }` |
| `"flags"` | `{ freeRewardClaimed }` |

## 6. 화면별로 필요한 것 (설계문서 12장 기준)

| 화면 | 쓸 것 |
|---|---|
| 상단 돈/속도/낮밤 타이머 | Attr `Money`, `Speed` / GameState `Phase`, `PhaseEndsAt` |
| "RUN!!" + 경비 거리 | `RunAlert`, `ChaseEnded`, Attr `CarryingEgg`, 경비 `TargetUserId` |
| Growing Eggs 패널 + Hatch 버튼 | `State.get().incubators` + `IncubatingEgg` 파트의 `Progress`/`Required`, 버튼 → `HatchEgg(uid)`. 남은 시간 = `(Required - Progress) / 성장속도` (밤 30배: `Phase == "Night"`) |
| 펫 보관함 + Equip Best | `State.get().pets/equipped/penSlots`, `EquipPet`, `UnequipPet`, `EquipBest`. 수입 표시는 `Economy.recordIncome(record)` (shared) |
| 도감 + Claim All | `indexDiscovered/indexClaimed`, `Progression.biomeProgress`, `ClaimIndexReward("all")`, 보상 미리보기 `Progression.pendingRewards` |
| 상점(우리/러닝머신/트레일) | `Upgrades` 데이터 + `Economy.nextPenCost/nextTreadmillCost`, `PurchaseUpgrade(kind, id)` |
| 선물상자(무료 보상) | `freeRewardClaimed`, `ClaimFreeReward` |
| 오프라인 수입 팝업 | `OfflineIncome` |
| 채팅 공지 | `Announce` (기본 `AnnounceController` 가 이미 채팅에 띄움) |
| 잡힘 연출(퍽+휘익) | `Caught` (기본 `RagdollController` 가 넘어뜨림) |
| 부화 연출(빠직+반짝) | `HatchResult` |
