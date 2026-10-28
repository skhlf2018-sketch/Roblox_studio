# 테스트 보고서

작성: 주임 (테스트 플레이어 · 고장 찾기), 2026-10-18
대상: 브랜치 `claude/festive-babbage-9vfuge`, 커밋 `fe23981` (선임 2차까지) + 이 폴더에 새로 만든 `tests/` `tools/` 파일 (아직 커밋 전)

**`src/` 는 한 줄도 고치지 않았습니다.** 고장은 3장에 "파일:줄 · 재현 · 제안"으로만 적었습니다. 본부장이 수석/선임에게 전달해 주세요.
Roblox Studio 는 실행하지 못했습니다. 그래서 "스튜디오에서 눈으로 봐야 아는 것"은 `docs/STUDIO_CHECKLIST.md` 로 넘겼습니다.

---

## 0. 한눈에 보기

| 항목 | 결과 |
|---|---|
| 자동 테스트 `lune run tests/run.luau` | **331개 중 329 통과, 2 실패** (110개 → 331개). 실패 2개는 진짜 고장을 가리키는 "고장" 테스트(고쳐 놓지 않음). 6초 |
| 선임 스모크 `smoke_visuals` / `smoke_client` | 둘 다 OK (건드리지 않고 실행만 함) |
| 타입 검사 `tools/luau-analyze.ps1` (HEAD) | type 77 · require 0 · syntax 0 · lint 1. **진짜 오류 없음**, 전부 새 타입 검사기의 한계/버릇 (9묶음, 5장) |
| 내 tests 파일 `stylua --check` / `selene` | 통과 / 0 오류 0 경고 |
| 밸런스 | 8구역이 목표보다 빠름(1.7h, 목표 3~5h), **9구역 앞에 벽(+11.3h)**, 14구역 앞에 두 번째 벽(+18.8h). 6장 |

### 가장 중요한 고장 5개

1. **[높음 · 스튜디오 확인] `GuardianService.luau:81-86`** 경비 Humanoid 에 `RequiresNeck = false` 가 없음. 목 관절이 없는 모델이라 경비가 태어나자마자 죽을 수 있고, 그러면 `ensureGuard`(:125-145)가 0.1초마다 다시 만들어서 **경비가 아무도 안 쫓는 게임**이 됨.
2. **[중간] `Main.server.luau:36-58`** `start()` 23개가 줄줄이 호출되는데 `pcall` 이 없음. 하나가 오류를 내면 **그 뒤 서비스가 전부 안 켜짐** (예: MapBuilder 가 오류 → PlayerLifecycle 이 안 붙어서 아무도 데이터를 못 받음).
3. **[중간 · 스튜디오 확인] `DevCommands.luau:99`** 채팅 명령이 `Player.Chatted` 하나에 기대고 있음. 새 채팅(TextChatService)에서 안 오면 `/money` 같은 명령이 전부 무반응.
4. **[중간 · 설계 확인] 표지판 "추천 속도"만으로는 일반 알도 못 지킴.** 일반 알을 들면 속도가 10% 줄어서 추천 속도의 **1.078배**가 있어야 경비를 따돌림 (큰 알 1.21배, 거대 1.49배, 초거대 1.94배). 아이가 "추천 속도 채웠는데 잡혀요" 라고 할 수 있음.
5. **[낮음] `DataSchema.luau:186-209`** 저장 데이터를 불러올 때 펫 500마리 상한을 안 지킴 (테스트가 "고장"으로 표시).

---

## 1. 만든 / 바꾼 파일

`src/` 변경 없음. 아래는 전부 새 파일이거나 내가 허락받은 영역입니다.

| 파일 | 설명 |
|---|---|
| `tools/luau-analyze.ps1` (새) | Luau 타입 검사 도구 설치 + `src/` 전체 검사 + 결과 분류. 5장 |
| `tests/ServerHarness.luau` (새, 약 960줄) | 진짜 서비스 코드를 Lune 에서 돌리는 가짜 세상: 가상 시간, 가짜 Instance/Players/DataStore/Humanoid/Part, 가짜 맵·낮밤. 2-5 |
| `tests/Loader.luau` (바꿈) | 가짜 모듈 끼워 넣기(`Loader.mock/service/globals/reset/clearFakes/root`) 추가. 기존 동작은 그대로 |
| `tests/run.luau` (바꿈) | 새 스펙 9개 등록 |
| `tests/services_core.spec.luau` (새, 25개) | Net, PetService, IncomeService, IndexService, UpgradeService, RewardService |
| `tests/services_gameplay.spec.luau` (새, 35개) | BaseService(배달·부화·알 자라기·베이스 배정), Fusion, Altar, Quest, Sakura |
| `tests/services_system.spec.luau` (새, 25개) | AntiCheat, DevCommands, DataService |
| `tests/services_tools.spec.luau` (새, 16개) | ToolService: 도구 지급, 근접 무기, 곰덫 |
| `tests/services_world.spec.luau` (새, 24개) | **EggService(알 놓기·줍기·놓치기·둥지 예약) + GuardianService(경비 추격·잡힘)** |
| `tests/design_doc.spec.luau` (새, 20개) | `docs/GAME_DESIGN.md` 를 읽어서 데이터와 비교 |
| `tests/rules_boundary.spec.luau` (새, 31개) | 경계값: 추천 속도, 알 무게, 밤 30배, 오프라인 24시간, 레이트 리밋, 퓨전·제단·퀘스트 |
| `tests/save_data.spec.luau` (새, 15개) | 저장 데이터: v1→v2, 엉터리 입력, 5,000개 퍼징 |
| `tests/crossrefs.spec.luau` (새, 30개) | 참조: Remote 이름, Config/Tags/소리/창 이름, 겉모습 데이터, 진입점, 위험한 버릇 글자 검사 |
| `docs/TEST_REPORT.md` (이 문서) / `docs/STUDIO_CHECKLIST.md` (새) | 보고서 / 사장님 체크리스트 |

`tests/smoke_*.luau` 는 만지지 않았습니다. `.luaurc` 는 읽기만 했습니다. git commit 은 하지 않았습니다.

---

## 2. 테스트

### 2-1. 결과 (전체 출력은 부록 A)

```
결과: 329 통과, 2 실패      (명령: lune run tests/run.luau, 종료 코드 1, 6초)
```

| 스펙 파일 | 개수 | 내용 |
|---|---|---|
| (기존) data, economy, speed, eggrules, eggroll, cycle, progression, server_logic, format, fusion, special, anticheat | 110 | 수석/선임이 만든 순수 로직 테스트 (그대로 통과) |
| services_core | 25 | 서비스 6개 |
| services_gameplay | 35 | 서비스 9묶음 |
| services_system | 25 | AntiCheat · DevCommands · DataService |
| services_tools | 16 | 15 통과 + 1 고장 |
| services_world | 24 | EggService · GuardianService |
| design_doc | 20 | 설계문서 ↔ 데이터 |
| rules_boundary | 31 | 경계값 |
| save_data | 15 | 14 통과 + 1 고장 |
| crossrefs | 30 | 이름 · 참조 · 글자 검사 |
| **합계** | **331** | 329 통과 / 2 고장 |

### 2-2. 실패 2개 = "고장" (테스트는 맞고 코드가 문제. 일부러 안 고침)

| 테스트 | 줄 | 뜻 |
|---|---|---|
| `서비스: ToolService 곰덫` > 곰덫을 얻을 방법: 시작 지급 3개 말고는 … 늘어나지 않음 — [설계 구멍] 다 쓰면 끝 | `tests/services_tools.spec.luau:405` | 곰덫은 `ToolService.luau:219` 에서 줄기만 함. 늘리는 코드가 없음 (3.3 B7) |
| `저장 데이터: 엉터리 입력` > 저장 데이터의 펫이 500마리가 넘으면 불러올 때 500마리까지만 남김 | `tests/save_data.spec.luau:572` | `DataSchema.reconcile` 이 펫 수 상한을 안 지킴 (3.3 B6) |

둘 다 고쳐지면 자동으로 초록이 됩니다. 아니면 "의도된 동작"이라고 정해서 테스트를 지우세요.

### 2-3. 테스트가 진짜 고장을 잡는지 (변이 시험)

테스트가 "항상 통과하는 가짜"가 아닌지 보려고, **복사본에서 소스를 일부러 망가뜨려** 봤습니다 (원본 `src/` 는 그대로). 세 묶음을 했고 망가뜨린 곳마다 테스트가 최소 1개 실패했습니다. 마지막 묶음 10개:

| 망가뜨린 곳 | 잡은 테스트 수 |
|---|---|
| 줍기 거리 검사 지우기 (`EggService`) | 1 |
| 경비 잡힘 높이 `dy <= 10` 지우기 | 1 |
| 줍고 1.5초 유예 지우기 | 1 |
| "다른 사람에게 맞으면 그 자리에 떨어짐" 규칙 지우기 (`EggRules`) | 2 |
| 밤에도 둥지 다시 채우기 | 1 |
| 경비 대상을 "가장 가까운 사람" 대신 아무나 | 1 |
| 떨어진 알 60초 뒤 사라짐 지우기 | 1 |
| 퀘스트 전용 알 검사 지우기 | 1 |
| 경비 추격 포기 반경 지우기 | 1 |
| 경비 안전 구역 검사 지우기 | 1 |

### 2-4. 무엇을 시험했나 (요청 항목 → 어디서)

| 요청 | 테스트 |
|---|---|
| 15구역 추천 속도·순서, 134 펫 희귀도·수입·부화 시간, 우리/러닝머신/트레일 가격, 돌연변이 배율, 크기 확률 합 100% | `design_doc.spec` (GAME_DESIGN.md 를 직접 읽어서 비교) |
| 추천 속도와 같을 때 경비, 알 무게 속도, 밤 30배, 오프라인 24시간 | `rules_boundary.spec` + `services_gameplay`(밤 30배·오프라인 실제 서비스) + `services_core`(오프라인) |
| 보관함 500 상한과 자동 판매, 레이트 리밋 폭주 | `services_core`(PetService, Net) + `rules_boundary`(모든 Remote 의 burst) |
| 퓨전 거부(거대 포함), 제단 같은 사람 두 번, 퀘스트 개수 조건, 치트 경고 감소 | `rules_boundary` + `services_gameplay` + `services_system`(AntiCheat) |
| 저장 v1→v2, 쓰레기(nil/문자열/음수/아주 큰 수/NaN) | `save_data.spec` (+ 무작위 5,000개 퍼징) |
| 알·경비 핵심 루프 | `services_world.spec` |
| 사장님 체크리스트의 `/money` 등 | `services_system`(DevCommands) |
| 이름이 실제로 있는지, 위험한 버릇 | `crossrefs.spec` |

### 2-5. 테스트 도구 쓰는 법 (수석/선임이 새 서비스 테스트를 쓸 때)

```lua
local ServerHarness = require("./ServerHarness")
local H = ServerHarness.install(Loader, T)      -- 진짜 EggService 를 쓰려면 { realEgg = true }
H.startNet()                                    -- 진짜 Net.start() (Remote 만들기)
local player = H.newPlayer(1001, "Tester")
local session, data = H.login(player)           -- 진짜 DataService.load 흐름
H.spawn(player, 0, 3, 0)
H.advance(2.5)                                  -- 가상 시간 2.5초 흘리기 (task.wait/delay 가 그 시간대로 동작)
H.uninstall()
```

- 가짜인 것: 엔진(Instance, Players, DataStore, task), 맵(`H.map`), 낮밤(`H.setPhase`), EggService(옵션), Gui. **서비스 코드 자체는 진짜**입니다.
- 한 테스트 안에서 `task.wait` 를 직접 부르면 안 됩니다 (`H.advance` 를 쓰세요).

### 2-6. 못 하는 것 (정직하게)

- 경비가 **실제로 걷는 것**(길찾기, 장애물에 걸림, 속도 체감)은 엔진 몫이라 Lune 으로 못 봄 → 체크리스트 11번.
- UI 의 모양·배치·느낌, 소리, 성능, 폰 화면 → 체크리스트.
- 맵 만드는 코드(`MapBuilder`, `PetVisualService`)는 선임의 스모크 테스트가 파트 이름·태그를 확인하고, 나는 글자 검사(`crossrefs.spec`)로 "구역 장식 종류가 구현돼 있나" 정도만 봤습니다.

---

## 3. 발견한 고장 (심각도 순)

심각도: **높음** = 게임의 핵심이 멈출 수 있음 / **중간** = 일부 기능이 멈추거나 아이가 헷갈림 / **낮음** = 모서리 / **참고** = 알고만 있으면 됨.
"확인" 표시는 Lune 으로는 못 확인하고 **스튜디오에서 눈으로 확인**해야 하는 것입니다.

### 3.1. 높음

**B1. 경비 Humanoid 가 태어나자마자 죽을 수 있음 [높음 · 스튜디오 확인]**
- 위치: `src/server/Services/GuardianService.luau:76-86` (머리를 `WeldConstraint` 로 몸통에 붙이고, `Humanoid` 에 `RequiresNeck` 을 안 건드림), `:125-145` (`ensureGuard`)
- 이유: Roblox 의 `Humanoid.RequiresNeck` 기본값은 true. 머리(`Head`)가 있는데 목 관절(`Neck`, Motor6D)이 없으면 사람 모양 캐릭터가 바로 죽는 경우가 흔합니다 ("직접 만든 NPC 가 생기자마자 죽어요" 의 대표 원인).
- 결과: 죽으면 `ensureGuard` 가 `Health > 0` 아님을 보고 지우고 다시 만듦 → 0.1초마다 반복. 경비는 안 쫓고 깜빡이기만 함.
- 재현: 스튜디오에서 F5 → `Workspace.Map.Guardians`(또는 태그 `Guardian`) 모델을 보고 경비가 계속 사라졌다 나타나는지, 출력창에 경고가 있는지. 알을 들어도 경비가 안 오면 이것.
- 제안: `buildGuard` 에 `humanoid.RequiresNeck = false` 와 `humanoid.BreakJointsOnDeath = false` 한 줄씩. (Lune 테스트는 Humanoid 가 가짜라서 못 잡음.)

### 3.2. 중간

**B2. 서버 시작이 한 줄 오류에 통째로 멈춤 [중간]**
- 위치: `src/server/Main.server.luau:36-58`
- 이유: `Net.start()` ~ `PlayerLifecycle.start()` 가 `pcall` 없이 순서대로 호출됨. 클라(`Main.client.luau`)는 컨트롤러마다 따로 시작해서 하나가 죽어도 나머지가 도는데, 서버는 반대.
- 결과: 예를 들어 `MapBuilder.start()` 가 파트 1만 개를 만들다 오류를 내면 그 뒤 `DataService/PlayerLifecycle/EggService/...` 가 전부 안 켜짐 → 아무것도 안 되는 게임.
- 재현(가짜로): 아무 `start()` 첫 줄에 `error("x")` 를 넣고 F5.
- 제안: `local function boot(name: string, fn: () -> ()) local ok, err = pcall(fn) if not ok then warn("[Main] " .. name .. " 시작 실패: " .. tostring(err)) end end` 로 감싸기. (`crossrefs.spec` 은 "모든 서비스가 start 되는지"만 보증하고 "하나가 죽어도 되는지"는 못 봄.)

**B3. 채팅 명령이 `Player.Chatted` 에만 기대고 있음 [중간 · 스튜디오 확인]**
- 위치: `src/server/Services/DevCommands.luau:99`
- 이유: 새 채팅(TextChatService)에서도 `Player.Chatted` 가 오는 걸로 알고 있지만 보장은 못 합니다. 안 오면 `/money` `/speed` `/skip` … 전부 무반응이고, 체크리스트의 많은 단계가 막힘.
- 재현: F5 → 채팅에 `/money 1e9` → 돈이 오르고 "[개발] /money 1e9" 알림이 떠야 함. 출력창에 "[DevCommands] 개발 명령 켜짐" 이 보여야 함.
- 제안: 안 되면 `TextChatService.TextChatCommands` 로 명령을 등록(서버 `Instance.new("TextChatCommand")`)하거나 `TextChatService.MessageReceived`. 로직(`handle`)은 그대로 재사용 가능 (이 부분은 `services_system.spec` 이 시험함).

**B4. 표지판의 "추천 속도"만으로는 알을 못 지킴 [중간 · 설계 확인]**
- 위치: `src/shared/SpeedMath.luau:60-64` (`guardChaseRatio`), `src/shared/Data/Config.luau:65` (`GUARD_CHASE_MARGIN = 0.97`), 표지판 `MapBuilder.luau:1140` (`buildZoneSign`)
- 숫자: 경비 속도 = 추천 속도. 알 무게로 내 속도가 줄고(일반 -10% / 큰 -20% / 거대 -35% / 초거대 -50%), 경비는 3% 느리게 쫓음. 따돌리려면 추천 속도의 **1.078배(일반) / 1.21배(큰) / 1.49배(거대) / 1.94배(초거대)** 필요.
- 결과: "추천 속도 700만" 을 딱 채운 아이가 일반 알을 들고도 잡힘(알의 70%가 일반 알). 설계 문서 `GAME_DESIGN.md:109` 는 "큰 알은 추천 속도보다 15~20% 더 빨라야 안전" 이라 쓰고 코드는 큰 알 +21% 라서 **큰 알은 문서와 맞음**. 일반 알(+7.8%)과 초거대(+94%)는 문서에 안 적혀 있어서, 의도인지 사장님이 확인해 주세요.
- 재현: `rules_boundary.spec` 의 "추천 속도와 경비" 묶음이 숫자로 확인함.
- 제안(둘 중 하나): (a) 표지판에 "추천 속도 (일반 알 기준 ×1.1)" 식으로 적기, (b) 화면의 RUN!! 경고가 이미 "속도가 부족해요 (내 N / 경비 M)" 를 보여주니(`ChaseController.luau:111-117`) 입구 표지판 쪽에 알 크기별 필요 속도를 작게 보여주기. 숫자 자체를 바꾸는 건 밸런스에 크게 번지니(6장) 비추천.

**B5. 부화 카드가 한 번 오류나면 영원히 안 뜸 [낮음~중간]**
- 위치: `src/client/Controllers/HatchController.luau:50-54` (`showing = true`), `:264` (`showing = false`), `:274`
- 이유: 카드를 만드는 도중(53~263줄) 오류가 나면 `showing` 이 true 로 남아서, 이후 모든 부화/퓨전/제단 카드가 줄(`queue`)에만 쌓이고 안 뜸 (재접속 전까지).
- 재현: 서버가 모르는 `petId` 를 보내거나 `record.mutations` 가 nil 인 `HatchResult` 를 보냄(예: 스모크 테스트에서 잘못된 payload).
- 제안: `showNext` 본문을 `pcall` 로 감싸고, 실패하면 `holder:Destroy()`, `showing = false`, `showNext()`.

### 3.3. 낮음

**B6. 불러올 때 펫 500마리 상한이 없음 [낮음] — 테스트 "고장" #1**
- 위치: `src/server/Logic/DataSchema.luau:186-209` (`reconcile` 의 펫 읽기 루프)
- 이유: `Config.PET_INVENTORY_MAX = 500` (`Config.luau:21`)이고 `docs/REMOTES.md` 는 "Snapshot.pets 최대 500" 이라는데, 읽을 때 개수를 안 막음. `PetService` 가 정상적으로는 500에서 막아서(자동 판매) 실제로는 거의 안 생기지만, 옛 저장/버그/수정된 상한이 있으면 Snapshot 이 커짐.
- 재현: `lune run tests/run.luau` → `tests/save_data.spec.luau:572`.
- 제안: 루프 첫 줄에 `if #data.pets >= Config.PET_INVENTORY_MAX then break end`.

**B7. 곰덫을 다시 얻을 방법이 없음 [낮음 · 설계] — 테스트 "고장" #2**
- 위치: 줄어드는 곳 `src/server/Services/ToolService.luau:219`; 처음 3개 `DataSchema.luau:56` + `Config.luau:127`; 늘리는 곳은 `DevCommands.luau:72` 뿐.
- 설계 문서 10장: "곰덫 — 도감 보상, 초반엔 개수 제한". 지금은 처음 3개를 쓰면 끝.
- 제안: `IndexService` 구역 완성 보상에 곰덫 +N, 또는 일정 시간마다 +1(상한). 정하기 전엔 테스트를 "의도"로 바꾸세요.

**B8. 폰에서 "자라는 알" 패널이 접힌 채로 시작 [낮음~중간 · UX]**
- 위치: `src/client/Controllers/IncubatorController.luau:85` (`collapsed = TouchEnabled and not KeyboardEnabled`)
- 결과: 폰/태블릿 아이는 부화 버튼이 어디 있는지 모르고 "알이 안 나와요" 가 될 수 있음.
- 제안: `Ready` 인 알이 생기면 자동으로 펼치거나, 접힌 제목에 "부화 가능 N" 배지.

**B9. "속도가 부족해요!" 경고가 서버보다 엄격 [낮음]**
- 위치: `src/client/Controllers/ChaseController.luau:106` (`slow = yours < guard`)
- 이유: 서버는 경비를 3% 느리게 쫓게 해서 `yours > guard × 0.97` 이면 따돌릴 수 있음. 화면은 100% 기준이라 97~100% 구간에서 빨간 경고가 거짓으로 뜸.
- 제안: `slow = yours <= guard * Config.GUARD_CHASE_MARGIN` (Config 는 shared).

**B10. 다른 사람이 휘두르는 모습이 안 보임 [낮음]**
- 위치: `src/client/Controllers/WeaponController.luau:12,458` 가 Tool Attribute `SwingTick` 이 바뀌길 기다리는데, 서버에는 그 값을 쓰는 코드가 없음 (`src` 전체 검색 결과 없음). UI.md 7장에도 "수석 요청"으로 적혀 있음.
- 제안: `ToolService` 의 `UseTool` 성공 지점에서 `tool:SetAttribute("SwingTick", os.clock())`.

**B11. 밤 벽에 갇힘 [낮음]**
- 위치: `src/server/Services/MapBuilder.luau:2143-2163` (밤 벽 4개), `:2967-2971` (`setNightWalls`)
- 이유: 밤이 되면 구역 사방의 벽이 `CanCollide = true` 가 되는데 그 구역 안에 있던 사람은 안 옮겨짐 (`BaseService.luau:585-597` 은 알 든 사람만 집으로 보냄). 밤 10초 + 대기 3초 = 최대 약 13초 갇힘. 큰 문제는 아니지만 아이가 "벽에 갇혔다" 고 신고할 수 있음.
- 제안: 밤 시작 때 구역 안 사람을 길 쪽으로 밀어내거나, 벽을 "구역 밖에서 들어오는 방향만" 막기.

**B12. 경비가 길찾기 없이 직선으로만 걸음 [낮음 · 스튜디오 확인]**
- 위치: `src/server/Services/GuardianService.luau:160-170` (`Humanoid:MoveTo`)
- 이유: 나무/바위/연못(선임의 구역 장식) 사이를 직선으로 걸으면 걸릴 수 있음. 걸리면 플레이어가 장식 뒤에 서서 경비를 따돌리는 "버그 기술"이 됨.
- 확인: 체크리스트 11번 + 장식이 경비 집↔둥지 사이 길에 없는지 눈으로.

### 3.4. 참고 (알고만 있으면 됨)

| # | 내용 | 위치 |
|---|---|---|
| R1 | `version` 이 이상한 값(0, 음수)이면 v1 으로 보고 v2 칸(무기·퀘스트·사쿠라)을 초기화함. 정상 서버가 쓴 데이터에는 안 생김 | `DataSchema.luau:134-143, 386-396` |
| R2 | 돈/속도에 상한 없음 (`1e300` 도 그대로). `newUid` 는 번호가 1e15 이상이면 `tostring` 이 `1e+15` 꼴이 되어 uid 가 겹칠 수 있음(현실적으로 불가능) | `DataSchema.luau:174-175, 404-408` |
| R3 | 무료 보상(+10,000 속도)은 `FREE_REWARD_GROUP_ID = 0` 이면 클릭 한 번으로 누구나. 3번 구역 사막(추천 10K)을 바로 통과할 속도 | `RewardService.luau:51-72`, `Config.luau:107-108` |
| R4 | 초기화(ALL EGG RESET) 때 든 알의 둥지 예약이 풀려서, 그 뒤 같은 구역 안에서 잡히면 빈 둥지가 없어 그 자리에 떨어짐(`returnToNest` 가 false). 허용 가능한 모서리 | `EggService.luau:382-390, 609-626` (테스트로 확인) |
| R5 | `RewardService.luau:59` `player:IsInGroup` 는 deprecated → `IsInGroupAsync` (타입 검사기 경고) | `RewardService.luau:59` |
| R6 | 서버 `ProximityPrompt.Triggered` 는 레이트 리밋 밖(밤에 E 연타 → 알림 연타). 해로울 정도는 아님 | `EggService.luau:279-283, 529-532` |
| R7 | 설계문서 3장(희귀도 표) 상위 범위가 12~15번 구역 펫과 안 맞음 (테스트는 1~11번 구역만 비교). 설계문서 `GAME_DESIGN.md:303` "약 207종" 은 원본 게임 전체 숫자, 우리 데이터는 134종 | `docs/GAME_DESIGN.md:66-79, 303` |

---

## 4. 코드 리뷰 노트

점검한 것: nil 인덱스, 잘못된 API 이름, yield 금지 자리, 무한 루프, 연결(Connection) 누수, 스튜디오 혼자 테스트 순서, 모바일 조작. "테스트"는 진짜 서비스 코드를 돌려 본 것, "읽음"은 눈으로 읽은 것.

### 4-1. 서버

| 대상 | 방법 | 결과 |
|---|---|---|
| Main.server | 읽음 + crossrefs | 모든 서비스가 등록·시작됨(CycleService.run 마지막). **B2** |
| Net, RateLimiter, Validate | 테스트(진짜 코드) | 핸들러 오류는 `pcall` 로 막힘, 레이트 리밋 burst/초당 회복 확인. 이상 없음 |
| Sessions, Snapshot, DataService | 테스트 + 읽음 | UpdateAsync 재시도, 세션 락(stale 300초), 메모리 모드, BindToClose, 나가는 중 로드. 이상 없음 |
| DataSchema | 테스트(퍼징 5,000) | 쓰레기 입력에도 안 죽음. **B6, R1, R2** |
| PlayerLifecycle | 읽음 | 이미 들어와 있는 플레이어(스튜디오 혼자 테스트)를 `GetPlayers()` 로 처리함 — 순서 문제 없음. 각 단계가 `safely()` 로 감싸짐 |
| PetService, Wallet, IncomeService, IndexService, UpgradeService, RewardService | 테스트 | 500 상한·자동 판매, 도감 보상 지수, 오프라인 24시간 상한, 러닝머신 경계 이상 없음. **R3, R5** |
| BaseService | 테스트 | 배달·부화·밤 30배·오프라인 자라기·베이스 배정 이상 없음. 밤에 알 든 사람만 집으로 (**B11**) |
| EggService | 테스트(새) | 줍기 거리/밤/기절/죽음/퀘스트 전용, 구역 안/밖 잡힘, 둥지 예약·30초 뒤 채움, 60초 뒤 사라짐 이상 없음. **R4, R6** |
| GuardianService | 테스트(새) + 읽음 | 대상 고르기(가장 가까운 사람), 추격 속도, 잡힘 경계(수평 6 · 높이 10 · 1.5초 유예), 추격 포기 반경, 죽은 경비 재생성 이상 없음. **B1, B12** |
| FusionService, AltarService, QuestService, SakuraService | 테스트 | 거부 규칙, 같은 사람 두 번, 3개 조건 이상 없음 |
| AntiCheatService, MoveCheck | 테스트 | 속도핵/순간이동 경고와 감소, 서버 텔레포트 예외 이상 없음 |
| ToolService | 테스트 | 사거리·방향·쿨다운·안전 구역, 곰덫 5초/수명 이상 없음. **B7, B10** |
| DevCommands | 테스트 + 읽음 | 8개 명령 이상 없음. **B3** |
| CycleService | 테스트 + 읽음 | 낮 285초/밤 10초/대기 3초, `/skip`, 스튜디오 `DebugDaySeconds` |
| MapBuilder, PetVisualService, EggVisualService | 일부 읽음 + 선임 스모크 + crossrefs(글자) | 매우 큼(2,900줄/2,100줄). 전부 읽진 못함. 파트 수 1만 이상 → 성능은 스튜디오에서 (체크리스트 28번). **B11** |

yield 금지 자리: 이벤트 콜백 안에서 `task.wait` 가 필요한 곳은 전부 `task.spawn` 으로 분리돼 있음(`crossrefs.spec` "위험한 버릇"이 옛 `wait/spawn/delay` 전역과 시간 제한 없는 `WaitForChild` 를 막고 있음).
무한 루프: `while true do` 는 전부 `task.wait` 가 들어 있음(글자 검사로 확인).
연결 누수: 캐릭터마다 걸리는 연결(`Humanoid.Died` 등)은 캐릭터가 지워지면 같이 사라지고, 플레이어 단위 상태는 `PlayerRemoving` 에서 정리됨(테스트로 확인). 큰 누수는 못 찾음.

### 4-2. 클라이언트

| 대상 | 결과 |
|---|---|
| Main.client | 컨트롤러마다 따로 `pcall` 시작, 마지막에 `RequestSnapshot` — 늦게 켜져도 데이터를 받음. 이상 없음 |
| Net/State | 이름 오타는 `crossrefs.spec` 이 잡음. `State` 가 `DataUpdate` 를 합침. 이상 없음 |
| Hud, Notify, Hotbar, Pets, Index, Shop, Gift, Settings | 읽음. 폰: 핫바는 점프 버튼 위, 버튼 46px 이상. 알려진 한계(창 X 버튼 약 40px)는 UI.md 7장에 있음 |
| Chase | **B9** |
| Incubator | **B8** |
| Hatch | **B5** |
| Fusion, Altar, Sakura, Quest + PetPicker/WorldPrompt/Fx | 읽음. 서버로 보내는 인자 순서가 REMOTES.md 와 같음. 타입 검사 경고만 있음(5장) |
| Weapon | **B10** |
| Lighting, Zone, WorldFx, Sound, Debug, Ragdoll, Tool, Announce | 읽음. 이상 없음 (소리는 전부 ID 0 이라 조용한 게 정상) |

### 4-3. Remote 이름·인자 교차 점검 (선임 클라 ↔ 수석 `docs/REMOTES.md`)

- 이름: `crossrefs.spec` 8개가 `Remotes.luau` ↔ `REMOTES.md` ↔ 서버(`Net.on/fire`) ↔ 클라(`Net.on/send`) 를 비교. **불일치 0**.
- 인자 순서: 클라의 `Net.send` 호출 18곳을 REMOTES.md 의 서버→받는 쪽 표와 하나씩 대조 — `HatchEgg(uid)`, `EquipPet/UnequipPet(uid)`, `PurchaseUpgrade(kind, trailId?)`, `UseTool(kind)`, `ClaimIndexReward("all" | petId)`, `FuseRequest(u1,u2,u3)`, `SakuraOffer/SakuraApply(uid)`, `AltarOffer(uid)`, `ShrineFuse(a,b)`, `RequestSnapshot()`, `ClaimFreeReward()`, `EquipBest()`. **불일치 0**.
- 문서에 없는 약속 하나: 클라가 기다리는 `SwingTick` Attribute 를 서버가 안 씀 (**B10**).

---

## 5. 타입 검사

### 5-1. 도구

```powershell
powershell -ExecutionPolicy Bypass -File tools\luau-analyze.ps1                  # 처음 한 번 설치(약 40MB) + src 검사
powershell -ExecutionPolicy Bypass -File tools\luau-analyze.ps1 -Ref HEAD        # 커밋된 코드만 검사
powershell -ExecutionPolicy Bypass -File tools\luau-analyze.ps1 -Path src\server -Report build\typecheck.md
```

- 먼저 `tools/setup-roblox-tools.ps1` 로 `rojo.exe` 를 받아 두세요(sourcemap 만들 때 씀. `-Dest\bin` 또는 PATH). `-NoFail` 을 주면 오류가 있어도 종료 코드 0, `-InstallOnly` 는 도구 설치만.
- 설치되는 것: `luau-analyze 0.743`, `luau-lsp 1.70.1`, 로블록스 전역 타입(`globalTypes.None.d.luau`) — 버전 고정, GitHub 에서 받음. 위치는 `-Dest` (기본 `%LOCALAPPDATA%\roblox-tools`). 다운로드는 잘 됐습니다.
- **왜 `luau-lsp analyze` 인가**: 받아 보니 `luau-analyze.exe` 는 `--defs` 가 없어서 로블록스 전역(`game`, `Instance.new`)과 Rojo 경로 `require(script.Parent.X)` 를 못 읽습니다. 같은 Luau 엔진을 쓰면서 `--definitions` 와 `--sourcemap`(rojo 로 만듦)을 받는 `luau-lsp analyze` 를 씁니다. `luau-analyze.exe` 도 같이 설치(순수 Luau 파일 빠른 검사용).
- `.luaurc`(strict) 를 `--base-luaurc` 로 그대로 적용. 저장소 경로에 한글이 있으면 luau-lsp 가 못 읽어서 ASCII 이름 바로가기(junction)를 자동으로 만들어 거기서 실행.
- 결과 분류: **type**(종료 코드 1) · **require**(환경 문제, 따로 셈) · **lint** · **syntax**(종료 코드 1). 한 줄 요약 + 파일별 목록(`-Report`).
- 이번 검사에서 require 해석 실패는 0건(환경 문제 없음).

### 5-2. 결과 (HEAD `fe23981`): type 77 · require 0 · syntax 0 · lint 1

파일별 전체 목록은 부록 C. **진짜 오류(없는 API 이름, 없는 속성, nil 인덱스가 실제로 일어나는 곳)는 0건**이고, 77개는 아홉 묶음의 "새 타입 검사기가 못 따라오는 모양"입니다.

| 묶음 | 개수 | 원인 | 고치는 법 (복사본에서 확인) |
|---|---|---|---|
| G1 `pcall` 이 값을 2개 못 줌 | 12 | `local ok, err = pcall(f)` 에서 `f` 가 아무것도 안 돌려주면 새 검사기는 `err` 가 없다고 봄 | `f` 의 반환을 `: ...any` 로 (예: `local function tick(): ...any`, `Net.on(name, handler: (Player, ...unknown) -> ...any)`). 12곳 모두 사라짐 |
| G2 `for _, name in Remotes.ToClient` 가 `unknown` | 2 | 이름 표의 값 타입을 못 알아냄 | `for _, name in Remotes.ToClient :: { [string]: string } do` |
| G3 `x or {}` 를 for 로 돌림 | 16 | "표 \| 빈 표" 합집합은 순회 불가 | `for _, v in (x or {}) :: { T } do` 또는 `x or ({} :: { T })` |
| G4 `ButtonOptions` 에 Frame 을 넘김 | 25 | `opts: ButtonOptions?` 칸에 `{ parent = frame }` 을 쓰면 새 검사기가 `Frame` 을 `Instance?` 로 못 받아들임 (옵션 표 + 하위 클래스 조합) | **`Ui.luau` 한 줄**: `parent: Instance?` → `parent: any`. 25개가 한 번에 사라짐 |
| G5 문자열 → 글자 합집합 | 4 | `FusionError`, `Phase` 같은 글자 종류가 `string` 으로 퍼짐 | 지역 변수에 타입 쓰기 (`local nextPhase: Phase = …`, `local ok: boolean, err: FusionError? = …`) |
| G6 nil 로 좁혀진 변수에 다시 대입 | 9 | `if not x then x = make() … end` 후에도 `x` 를 nil 로 봄 (`ToolService` 5, `BaseService:143`, `MapBuilder` 2, `HotbarController:188`) | 재대입 대신 "있으면 쓰고 없으면 만드는" 작은 함수 (`ensureTool`) 또는 새 지역 변수. 8곳 사라짐 (`Hotbar` 는 안 해 봄) |
| G7 하위 타입 표 칸 | 4 | `part: BasePart` 칸에 `Part`, `style: Style` 칸에 `string` 등 | `part :: BasePart`, `style :: Style`; `plotOwners: { [number]: Player? }`. 3곳 사라짐 (`WorldFxController:60` 은 안 해 봄) |
| G8 숫자와 UDim2 섞인 배열 | 5 | `ChaseController:187-201` 의 `{ UDim2, UDim2, 90 }` 목록 | 칸 이름 있는 표 `{ position: UDim2, size: UDim2, rotation: number }` 로 바꾸기 (안 해 봄) |
| G9 lint | 1 | `IsInGroup` deprecated | `IsInGroupAsync` (R5) |

**검증**: 복사본(`scratchpad`)에서 위 고침을 적용하고 다시 돌리면 **78 → 17**. 남은 17은 같은 묶음의 클라이언트 쪽(G3 클라 9, G8 5, Hotbar 1, WorldFx 1)과 lint 1입니다. G3 클라 9곳은 `(x or {}) :: { Types.PetRecord }` 처럼 그 파일에서 쓰는 타입 이름으로 같은 고침을 하면 됩니다. 모양만 바꾸는 고침이라 동작은 같고, `ToolService` 는 새 도구를 가방에 넣는 부분만 `ensureTool` 함수로 옮겼습니다.

**권고**: 지금은 이 77개를 "전부 고치지 말고", 새 코드에서 `: ...any` / `:: {T}` 를 습관으로. 가장 값싼 이득은 **G4 한 줄**(25개)과 **G1**(12개)입니다. 스튜디오가 어느 검사기(예전/새)를 쓰는지에 따라 같은 경고가 안 보일 수도 있습니다.

---

## 6. 밸런스 (11살 아이 기준)

실행: `lune run tests/sim_progress.luau` (부록 B 에 전체 출력). 모델: 러닝머신 배율 3 × 초당 1걸음, 성장 배율 G = 3, 한 주기(5분)에 알 1개, 시드 9개. **가장 빨리 하는 "착실한 플레이어"**입니다. 아이는 쉬고, 구경하고, 잡히고, 길을 잃으니 실제 시간은 2~3배로 보세요.

| 구역 | 추천 속도 | 도달 시간(중앙값) | 느낌 |
|---|---|---|---|
| 1 숲 · 2 호수 · 3 사막 | 10 / 900 / 10K | 0.0h | **너무 쉬움**: 시작 속도 20 이 숲 경비(10)보다 빨라서 숲은 위험이 0. 도감 보상 몇 개로 호수까지 몇 분 |
| 4 정글 · 5 눈 · 6 화산 · 7 심연의 바다 | 40K~2.5M | 0.1 → 0.7h | 순조로움. 7구역까지 합쳐 **42분** |
| **8 선사시대** | 18M | **1.7h** | 목표(3~5h)보다 빠름 |
| **9 코스믹** | 700M | **13.0h** | **벽**: 8 → 9 가 +11.3h(7.6배). 추천 속도가 18M → 700M(39배) |
| 10 벚꽃 · 11 타이탄 | 2.5B / 7B | 16.6h / 20.0h | 구역당 3~4h, 적당 |
| 12 천사&악마 · 13 마법의 숲 | 20B / 50B | 26.4h / 27.0h | 목표(13구역 20~30h) 안. 12→13 은 +0.6h 로 거의 붙어 있음 |
| **14 사탕 왕국** | 150B | **45.8h** | **두 번째 벽**: 13 → 14 가 +18.8h |
| 15 유령 성 | 500B | 56.5h | 목표(40~60h) 안 |

- 구역 하나 안에서도 운(큰 알·희귀 알) 때문에 최소~최대가 크게 갈림 (14구역 31.6h ~ 52.1h).
- 도감 속도 보상 없이 러닝머신만으로는 12구역 이후 100시간이 넘음 → **도감을 채워야만 진행**됩니다. 아이에게 도감 창이 "받기!" 로 잘 보이게 해 줘야 함 (배지는 이미 있음).
- 민감도: 도감 속도 보상 지수가 0.8 → 0.75 가 되면 13구역이 27.0h → 53.5h, 0.85 면 16.1h. **한 칸 바꿔도 시간이 두 배로 흔들리는 칼날 균형**이니 지수는 건드리지 마세요. 추천 속도를 바꿀 때도 조심: 도감 보상이 추천 속도에 비례해서, 14구역 추천 속도를 150B → 100B 로 낮췄더니 오히려 **15구역이 56h → 96h** 로 늘었습니다.

**제안 (사장님이 정하세요; 복사본에서 sim 으로 확인)**

| 시나리오 | 8구역 | 9구역 | 13구역 | 14구역 | 15구역 |
|---|---|---|---|---|---|
| 지금 | 1.7h | 13.0h | 27.0h | 45.8h | 56.5h |
| S1 8구역 18M → 40M | **3.2h** | 11.3h | 24.8h | 31.4h | 54.4h |
| S2 9구역 700M → 350M | 1.7h | **7.2h** | 26.5h | 34.0h | 53.5h |
| **S3 = S1 + S2** | **3.2h** | **7.6h** | **23.7h** | 30.2h | 54.2h |

S3 이면 8구역 3~5h, 13구역 20~30h, 15구역 40~60h 목표를 모두 지키면서 9구역 벽이 +11.3h → +4.4h 로 줄어듭니다. 다만 8·9구역 추천 속도는 설계문서 4장 숫자이므로 문서와 데이터(`Biomes.luau`)를 같이 고쳐야 `design_doc.spec` 이 통과합니다. 그래서 "숫자는 원본 그대로"가 우선이면 대신 **설계 목표를 "8구역 1.5~2.5h"로 고치는 것**도 방법입니다.

아이가 쉽게 느낄 곳: 1~3구역(위험 0), 무료 보상 한 번(속도 +10,000)으로 3구역을 바로 통과. 어렵게 느낄 곳: 9구역 앞(13시간), 14구역 앞(19시간), 초거대 알(속도 1.94배 필요, B4).

---

## 7. 걱정되는 점

1. **스튜디오에서 처음 켜는 순간이 제일 위험합니다.** Lune 으로 못 보는 것(경비 Humanoid 생존 **B1**, 채팅 명령 **B3**, 서버 시작 시간, 파트 1만 개의 성능, 폰 화면)이 한꺼번에 시험대에 오릅니다. 체크리스트 1~11번을 먼저 하세요.
2. **서버 시작이 한 번에 파트 8,400개 이상을 만드는 동기 작업**입니다(`MapBuilder.start`). 서버 시작이 오래 걸리면 처음 접속한 사람이 빈 화면을 오래 봅니다. `StreamingEnabled` 는 꺼져 있고(`default.project.json` 에 없음) 폰은 맵 전체를 한 번에 받습니다. 폰에서 끊기면 구역 장식 개수부터 줄이세요.
3. **밸런스가 칼날 위**입니다(6장). 추천 속도 하나를 바꾸면 도감 보상이 같이 움직여 뒤 구역 시간이 크게 변합니다. 바꿀 때는 꼭 `lune run tests/sim_progress.luau` 로 확인.
4. **소리가 전부 비어 있음**(`rbxassetid://0`). 문제는 아니지만 사장님에게는 "조용한 게임"으로 보입니다. 설정 창의 음소거는 저장이 안 됨.
5. **테스트와 문서의 약속**: `design_doc.spec` 은 `GAME_DESIGN.md` 의 표 모양(열 순서, `|` 표)에 기대서 읽습니다. 문서를 고치다가 표 모양이 바뀌면 테스트가 "파서 점검" 에서 먼저 실패합니다(의도된 경보).
6. **내가 못 본 곳**: `MapBuilder`/`PetVisualService`의 전체, 실제 Roblox 물리(래그돌 날아가기, 경비 걷기), 실제 DataStore 지연. 이 셋은 눈으로 봐야 합니다.

---

## 부록 A. `lune run tests/run.luau` 전체 출력

```

== 데이터 표
  ok   성장 배율 3
  ok   희귀도 10등급, 순서 1~10
  ok   구역 15개, 순서·추천 속도 오름차순, 경비 속도 = 추천 속도
  ok   펫 134종 (설계문서 5장 목록 그대로)
  ok   모든 펫: 구역·희귀도 id 가 존재, 수입·부화 시간 양수
  ok   구역마다 둥지 펫 8종 (천사&악마는 쪽마다 8종)
  ok   원본 숫자 표본 확인
  ok   크기 확률 합 100, 돌연변이 8종
  ok   업그레이드 표: 우리 11, 러닝머신 10, 트레일 11
  ok   둥지 가중치: 비밀/영원/신성은 0 (초기화 특별 추첨으로만)
  ok   도감 보상: 설계문서 예시와 일치
  ok   도감 속도 보상: 뒤 구역은 (추천 속도/3600)^0.8 배 (정비례보다 느리게)

== Economy
  ok   펫 수입 = 기본 × 3 × 크기 × 돌연변이
  ok   돌연변이 중첩 곱 (균열 2.75 × 혼란 2.75 = 7.5625)
  ok   돌연변이 조합 규칙: 자연 돌연변이 2개 불가, 자연+블룸 가능
  ok   장착된 펫만 합산, 중복 uid 는 한 번만
  ok   Equip Best: 수입 높은 순으로 칸 수만큼
  ok   부화 시간 = 원본 ÷ 3
  ok   성장 속도: 밤 30배, 게임패스 2배, 둘 다 60배
  ok   부화 진행: 밤 10초면 300초만큼 자람, 필요량에서 멈춤
  ok   우리 칸 / 다음 비용
  ok   러닝머신: 잠김 0, 걸음당 속도 × 러닝머신 배율 × 초당 걸음
  ok   보관함 넘침: 장착 안 된 펫 중 수입이 가장 낮은 펫
  ok   트레일: 가장 높은 배율 하나만 (중첩 아님)
  ok   오프라인 수입: 차이 × 초당 수입, 상한 24시간, 시계 역행 0

== SpeedMath
  ok   WalkSpeed: 0 → 16, 상한 120, 단조 증가
  ok   NaN 은 0 취급
  ok   알 들면 WalkSpeed 감소, 하한 적용
  ok   추천 속도 이상이면 경비가 못 잡음 (ratio < 1)
  ok   모자랄수록 경비가 더 빨라짐, 상한 적용
  ok   시작 속도로 숲에서 초거대 알을 들어도 닭은 못 잡음
  ok   큰 알은 추천 속도보다 더 빨라야 안전 (requiredSpeed)
  ok   평소 경비 WalkSpeed = 같은 로그 곡선

== EggRules
  ok   구역 안/밖 판정 (경계 포함)
  ok   경비한테 구역 안에서 잡힘 → 둥지로
  ok   경비한테 구역 밖에서 잡힘 → 그 자리
  ok   다른 플레이어(방망이/곰덫)한테 당함 → 구역 안이라도 그 자리
  ok   죽거나 나가면 경비와 같은 규칙
  ok   구역 정보가 없으면 그 자리
  ok   추격 포기 반경 = halfSize × 2 × persistence
  ok   원 반경 판정 (안전 구역)

== EggRoll
  ok   weightedIndex: 경계값
  ok   크기 분포 ≈ 70/20/8/2 (20만 회)
  ok   자연 돌연변이 ≈ 실버 5% / 골든 2% / 레인보우 0.5%
  ok   둥지 풀: 퀘스트/합성/제단 펫 제외, 천사&악마는 쪽별
  ok   일반 추첨에 비밀/영원/신성이 절대 안 나옴
  ok   숲 확률: 닭이 파타핌보다 자주, 합 1
  ok   특별 추첨: 난수 0 이면 희귀한 것부터 최대 2개, 0.99 면 없음
  ok   특별 추첨 확률 ≈ 표 값 (정글 비밀 8%)
  ok   pickDistinct: 서로 다른 칸
  ok   rollTraits: 크기 + 자연 돌연변이 최대 1개
  ok   모든 둥지 펫 id 는 Pets 에 존재

== Cycle
  ok   낮 285 → 밤 10 → 대기 3 → 낮
  ok   경과 시간으로 상태 계산
  ok   알 훔치기는 낮에만
  ok   천사&악마: 주기마다 천국/지옥 번갈아

== Progression
  ok   구역 진행도
  ok   무기: 숲은 무기 없음, 호수 완성 → 물 방망이
  ok   천사&악마 무기는 합성 펫 2종 제외 18종이면 해금 (제단 펫은 필요)
  ok   마법의 숲 무기는 퀘스트 펫까지 10종 필요
  ok   무기 없는 구역은 요구 목록이 비어 있음
  ok   전체 도감 완성
  ok   미수령 보상: 닭 + 라쿤 = 속도 1040, 돈 $4,600 (받은 건 제외)

== RateLimiter
  ok   burst 만큼 허용 후 막고, 시간이 지나면 회복

== Validate
  ok   uid
  ok   oneOf / idIn / finiteNumber

== DataSchema
  ok   기본값
  ok   엉터리 값은 기본값으로
  ok   펫: 모르는 id·중복 uid 버림, 돌연변이 정리, 장착은 칸 수까지
  ok   도감: 발견 안 한 펫은 수령 목록에서 제거
  ok   부화 슬롯: 필요 시간 다시 계산, 슬롯 중복·범위 밖 제거
  ok   newUid 는 증가

== DataSchema v2
  ok   버전 2 기본값
  ok   마이그레이션 1 → 2: 도감 기록으로 무기 채움 (천사&악마 18종 규칙)
  ok   새 버전 서버가 저장한 데이터는 표시만 하고 버전을 내리지 않음
  ok   v2 필드 보정: 잘못된 값 버리기
  ok   무기: 저장된 무기 ∪ 도감으로 해금되는 무기

== Format
  ok   숫자 단위 K/M/B/T/Qa
  ok   시간

== FusionRules
  ok   입력 검사: 3마리, uid 다름, 같은 petId
  ok   후보: 같은 구역 희귀도 +1 둥지 펫, 천사&악마는 같은 쪽 우선
  ok   돌연변이: 셋이 같으면(순서 무관) 유지, 아니면 사라짐
  ok   닭 3마리 → 새 (희귀도 업, 보통 크기면 충분)
  ok   크기 보정: 초거대 골든 닭 3마리(합 108) → 거대 골든 새(144)
  ok   돌연변이가 다르면 사라지고 크기로 보정
  ok   위 희귀도가 없으면 같은 펫 크기 업 (가장 큰 입력 크기 + 1부터)
  ok   합보다 약해질 수밖에 없으면 거부 (거대 파타핌 3마리)
  ok   보너스 돌연변이: 난수 0 → 실버, 이미 더 좋은 자연 돌연변이가 있으면 유지
  ok   보너스 확률 ≈ 10%, 실버:골든:레인보우 ≈ 5:2:0.5 (40만 회)
  ok   모든 펫·크기: 성공하면 결과 수입 ≥ 3마리 합, 결과는 같은 구역 둥지 펫 또는 같은 펫

== SakuraRules
  ok   블룸끼리는 불가, 자연 돌연변이 위에는 가능
  ok   블룸 97.5% / 스피릿 블룸 2.5% (20만 회)
  ok   해금 제물: uid 없으면 수입이 가장 낮은 학, 학이 없으면 nil

== AltarRules
  ok   제물 쪽: 천국/지옥 둥지 펫만
  ok   같은 주기, 서로 다른 두 사람이 양쪽에 바치면 짝
  ok   주기가 바뀌면 기다리던 제물 취소, 유효하지 않은 제물은 건너뜀
  ok   링 가드 80% / 링로드 20%
  ok   비밀 통로 레시피 (순서 무관), 크기는 작은 쪽

== QuestRules
  ok   퀘스트 3개, 목표·보상 알이 데이터와 맞음
  ok   마법의 숲 알만 20개, 영원 알은 아무 구역, 합성 1회
  ok   마법의 숲 영원 알 하나는 두 퀘스트를 같이 올림

== Weapons
  ok   구역 무기 7개 = Biomes.weapon, 기본 방망이 = Config
  ok   뒤 구역 무기일수록 사거리·넉백은 크고 쿨다운은 짧음 (1.2초 → 0.8초)
  ok   모든 무기 Tool 이름이 Remotes.ToolKinds 에 있음 (+ 곰덫)
  ok   새 Remote 는 전부 레이트 리밋이 있음, 새 태그 정의

== MoveCheck
  ok   1초 허용 거리 = WalkSpeed × 1.5 + 30
  ok   수평 거리만 (위아래는 안 봄)
  ok   알 든 사람 0.2초 틱: WalkSpeed × dt × 1.5 + 8
  ok   배달 최소 시간 = 거리 ÷ (WalkSpeed × 1.3)
  ok   경고 5개면 Kick, 시간이 지나면 1개씩 줄어듦

== 서비스: Net (진짜 server/Net.luau)
  ok   start() 가 shared/Remotes 의 모든 RemoteEvent 를 만듦
  ok   레이트 리밋: HatchEgg 는 10번까지 통과, 11번째는 막힘, 0.25초 뒤 1개 회복
  ok   핸들러가 오류를 내도 서버는 안 멈추고 warn 만 남김
  ok   모르는 Remote 이름으로 Net.on 하면 즉시 오류 (오타 방지)
  ok   플레이어가 나가면 Net.fire 는 조용히 건너뜀

== 서비스: PetService (보관함 500 상한·자동 판매·장착)
  ok   처음 7마리는 자동 장착, 8번째부터는 보관함만
  ok   보관함 500 넘으면 장착 안 된 펫 중 제일 싼 펫이 자동 판매 (돈 = 수입 × 60초)
  ok   장착한 펫은 아무리 싸도 안 팔림
  ok   EquipPet / UnequipPet / EquipBest 요청 (Remote) — 이상한 인자는 무시
  ok   removePets: 하나라도 없으면 아무것도 안 지움, 있으면 장착도 같이 해제
  ok   돈 2배 게임패스 플래그가 켜지면 초당 수입 2배 (1차 버전은 꺼 둠)

== 서비스: IncomeService (1초마다 수입)
  ok   10초 지나면 초당 수입 × 10 이 돈에 쌓임, 수입 0 이면 그대로
  ok   데이터가 아직 안 불러와진 플레이어에게는 안 줌

== 서비스: IndexService (도감 발견·보상·구역 무기)
  ok   첫 발견만 true, 모르는 펫 id 는 false
  ok   호수 8마리를 다 발견하면 물 방망이 해금 + 알림 + 신호
  ok   보상 받기: 한 마리씩 / 모두 받기 / 두 번 받기 불가 (설계문서 예시 숫자)
  ok   전체 완성 보너스(속도 1T + 돈 1Qa)는 딱 한 번

== 서비스: UpgradeService (우리·러닝머신·트레일 구매)
  ok   우리 구매: 돈 부족이면 거부, 충분하면 정확히 차감 + 칸 수 증가, 최대면 안내
  ok   러닝머신: 해금 $1K, 레벨마다 정해진 가격, 최대 10레벨
  ok   트레일: 가진 것 중 가장 높은 배율 하나만 적용, 중복 구매 불가, 모르는 id 무시
  ok   러닝머신 패드 반경(5) 안에서만 속도가 오름 — 경계 포함

== 서비스: RewardService (오프라인 수입·무료 보상)
  ok   오프라인 수입: 비운 시간 × 초당 수입, 60초 이상이면 팝업
  ok   오프라인 수입 상한 24시간, 30초 비웠으면 돈은 주되 팝업 없음, 처음 접속은 0
  ok   무료 보상: 계정당 한 번 +10,000 속도
  ok   무료 보상: 그룹 ID 를 켜면 그룹 가입자만 (가입 안 했으면 안내)

== 서비스: BaseService 선물 알 (빈 슬롯 → 대기 줄 → 거부)
  ok   빈 슬롯에 바로, 8칸이 차면 대기 줄(최대 20), 그 이상은 거부

== 서비스: BaseService 배달 (알 → 부화 슬롯)
  ok   알을 들고 배달하면 슬롯 1번에 등록, 통계·알림·신호
  ok   부화 슬롯 8칸이 다 차면 배달 거부 (알은 그대로 손에), 안내는 3초에 한 번
  ok   순간이동 의심: 주운 곳에서 너무 빨리 패드에 오면 배달 거부 + 알은 둥지로 + 경고
  ok   배달 패드 반경 9: 걸어 들어오면 자동 배달 (경계 포함), 밖이면 안 됨
  ok   공중(높이 10 이상 차이)에서는 배달 안 됨
  ok   알 든 채 한 번에 너무 멀리 움직이면(순간이동) 그 자리에 알 떨어뜨림 + 경고
  ok   밤이 되면 알 든 사람이 베이스 밖에 있을 때만 집으로 텔레포트

== 서비스: BaseService 부화
  ok   다 자라기 전에는 부화 거부, 다 자라면 펫이 보관함·우리에 들어가고 도감 발견
  ok   남의 알 uid / 이상한 uid 로 부화 요청해도 아무 일 없음 (Remote)
  ok   부화하면 대기 줄 알이 빈 슬롯으로 자동 이동
  ok   보관함이 가득 찬 상태에서 제일 싼 펫이 부화되면 sold=true, 돈으로 바뀜

== 서비스: BaseService 알 자라기 (밤 30배, 오프라인)
  ok   낮에는 1초에 1초씩, 밤에는 30배, 다 자라면 한 번만 알림
  ok   성장 2배 게임패스 플래그 × 밤 = 60배
  ok   오프라인 동안 자란 만큼 (밤 가속 없음), 아주 오래 비워도 필요량에서 멈춤

== 서비스: BaseService 베이스 배정
  ok   베이스가 없는 사람은 누가 나가면 그 자리를 받음

== 서비스: FusionService (퓨전 머신)
  ok   닭 3마리 → 새: 재료는 사라지고 결과는 보관함·우리에, 결과 알림·도감
  ok   거부: 종류가 다름 / 같은 펫 두 번 / 없는 펫 / 남의 펫 — 재료는 그대로
  ok   거부: 퓨전 머신(내 베이스)에서 멀면 / 캐릭터가 없으면
  ok   거부: 더 강해질 수 없는 펫 (거대 파타핌 3마리) — 재료 그대로
  ok   퓨전은 레이트 리밋 (burst 3)

== 서비스: AltarService (제단 짝 맞추기·비밀 통로 합성)
  ok   서로 다른 두 사람이 같은 주기에 양쪽 제단에 바치면 둘 다 링 가드/링로드 알
  ok   같은 사람이 양쪽 제단에 두 번 바치는 건 불가 (한 주기에 한 번)
  ok   틀린 쪽 펫 / 제단에서 멀리 / 일반 펫은 거부
  ok   주기가 바뀌면 기다리던 제물 취소 (펫은 남고 알림), 나간 사람 제물도 취소
  ok   기다리는 사이 제물 펫이 없어졌으면 그 제물은 건너뛰고 새 사람은 계속 기다림
  ok   알 받을 자리가 없으면 제물을 못 바침
  ok   비밀 통로 합성: 페가수스 + 스켈레톤 말 → 에퀴녹스 알, 계정당 한 번

== 서비스: QuestService (마법의 숲 퀘스트 3개)
  ok   마법의 숲 알만 20개 센다 (다른 구역 알은 안 셈), 19개까지는 완료 아님
  ok   영원 알은 아무 구역이나 1개, 일반 알은 안 셈
  ok   진짜 퓨전 1번이 퀘스트 '합성'을 올림, 3개 다 끝나면 문 열림 + 지터버그 알
  ok   영혼 세계 수호자 알: 퀘스트 끝낸 사람이 없으면 절대 안 나옴, 있으면 초기화마다 약 1%

== 서비스: SakuraService (사쿠라 인큐베이터·크리스탈)
  ok   학을 바치면 인큐베이터 해금 (학 없으면/멀면/이미 열었으면 거부)
  ok   크리스탈 1개로 블룸: 펫/부화 중 알에 붙고, 이미 블룸이 있으면 거부(크리스탈 안 씀)
  ok   벚꽃 구역 알을 배달하면 크리스탈 +1 (다른 구역은 안 줌), 상한 999,999

== 서비스: AntiCheatService (속도핵·순간이동 감시)
  ok   걷는 속도(WalkSpeed × 1.5 + 30 이하)는 아무 일 없음, 정확히 경계 54 도 통과
  ok   1초에 54.2 스터드 이동 → 제자리로 되돌리고 경고 1 + 알림
  ok   경고가 5개 쌓이면 Kick (4개까지는 안 쫓겨남)
  ok   경고는 60초마다 1개씩 줄어듦 (렉 오탐이 쌓이지 않게)
  ok   쉬는 경우: 래그돌·곰덫(기절), 서버 순간이동 직후, 앉음, 죽음
  ok   WalkSpeed 가 빠르면(러닝머신으로 속도 상승) 허용 거리도 커짐
  ok   나간 플레이어는 기록이 지워지고 오류 없음

== 서비스: DevCommands (스튜디오 채팅 명령 — 사장님 체크리스트에 나오는 것들)
[DevCommands] 개발 명령 켜짐: /money /speed /skip /grow /trap /crystal /pet /quests
  ok   /money /speed: 숫자(1e9 도 됨)만큼 더함, 이상한 값은 무시
[DevCommands] 개발 명령 켜짐: /money /speed /skip /grow /trap /crystal /pet /quests
  ok   /skip: 낮/밤 단계를 넘김 요청, /grow: 부화 슬롯 알을 다 자란 상태로
[DevCommands] 개발 명령 켜짐: /money /speed /skip /grow /trap /crystal /pet /quests
  ok   /trap 5: 곰덫 +5 (처음 3개), /crystal 5: 사쿠라 크리스탈
[DevCommands] 개발 명령 켜짐: /money /speed /skip /grow /trap /crystal /pet /quests
  ok   /pet 이름 개수: 펫 바로 받기 (도감에도 기록), 최대 20마리, 없는 이름은 무시
[DevCommands] 개발 명령 켜짐: /money /speed /skip /grow /trap /crystal /pet /quests
  ok   /quests: 마법의 숲 퀘스트 3개를 한 번에 끝냄 (문 열림 + 지터버그 알)
  ok   스튜디오가 아니면 (DEV_USER_IDS 도 비었으면) 명령이 아예 안 켜짐
[DevCommands] 개발 명령 켜짐: /money /speed /skip /grow /trap /crystal /pet /quests
  ok   DEV_USER_IDS 에 넣은 사람만 (실서버에서도), 다른 사람은 안 됨

== 서비스: DataService (저장·불러오기·세션 락·재시도)
  ok   새 플레이어: 기본 데이터로 시작 + 이 서버 이름으로 락이 걸림
  ok   나갈 때 저장하면 락이 풀리고, 다시 접속하면 같은 데이터가 돌아옴
  ok   다른 서버가 락을 쥐고 있으면 5초씩 3번 기다린 뒤 가져옴 (데이터는 안 잃음), 옛 서버는 저장이 막힘
  ok   락이 300초보다 오래됐으면 기다리지 않고 바로 가져옴
  ok   더 새 버전(3) 데이터: 저장 끔 + 락 바로 풀기 + 원본(모르는 필드 포함)은 그대로
  ok   스튜디오에서 DataStore 가 막혀 있으면 '메모리 모드' (기본 데이터, 저장 안 함, 게임은 계속)
  ok   실서버에서 불러오기가 3번 실패하면 기본 데이터로 놀게 하되 저장은 끔 (원래 데이터 보호)
  ok   저장이 두 번 실패해도 세 번째에 성공, 세 번 다 실패하면 false
  ok   나갈 때 저장이 끝내 실패 → 대기열 → 자동저장 주기에 다시 시도해 성공
  ok   자동 저장(60초마다)과 서버 종료(BindToClose) 때 전부 저장
  ok   불러오는 중에 나가면 데이터는 건드리지 않고 락만 풂 (오프라인 수입 보존)

== 서비스: ToolService 도구 지급
  ok   처음에는 야구 방망이 + 곰덫(3개)만, 구역 무기는 도감을 완성해야 생김
  ok   모든 구역 무기 7개를 해금하면 Tool 이름이 Remotes.ToolKinds 와 같은 9개(방망이·곰덫 포함)
  ok   곰덫이 0개가 되면 곰덫 도구가 가방에서 사라짐

== 서비스: ToolService 근접 무기 (사거리·방향·쿨다운·안전 구역)
  ok   손에 든 방망이로 앞 사거리(9) 안의 사람을 때림 — 안 들었으면 안 맞음
  ok   사거리 경계: 9.0 은 맞고 9.1 은 안 맞음 / 뒤·옆은 안 맞고 방향 경계(내적 0.2)는 맞음
  ok   쿨다운 1.2초: 1.19초는 막고 1.21초는 통과, 무기를 바꿔도 같은 쿨다운
  ok   구역 무기는 사거리가 더 김: 카타나 12 는 맞고 12.1 은 안 맞음
  ok   안 가진 구역 무기를 요청해도 무시 (도구가 없음)
  ok   가장 가까운 한 명만 맞음
  ok   안전 구역: 내가 안에 있으면 못 쓰고(안내), 맞는 사람이 안에 있으면 안 맞음
  ok   기절한 사람은 못 때리고 기절한 사람도 안 맞음, 죽은 사람도 안 맞음, 이상한 kind 는 무시

== 서비스: ToolService 곰덫 (설치·5초 묶임·수명)
  ok   설치하면 개수 -1 + 도구 개수 표시 갱신, 1초 쿨다운, 동시에 3개까지
  ok   다른 사람이 반경 3 안에 들어오면 5초 묶임 + 알 떨어뜨림 + Caught(trap) 알림, 경계 3.01 은 안 걸림
  ok   자기 덫은 자기가 안 밟힘, 안전 구역의 사람은 안 걸림, 90초 지나면 저절로 사라짐
  ok   안전 구역에서는 설치 불가(안내), 설치한 사람이 나가면 그 덫도 사라짐
  FAIL 곰덫을 얻을 방법: 시작 지급 3개 말고는 도감·퀘스트 어디서도 늘어나지 않음 — [설계 구멍] 다 쓰면 끝
      D:\준수\RobloxST\Roblox_studio\tests\services_tools.spec:405: 곰덫을 늘리는 코드가 없음 (설계문서 10장: 곰덫 = 도감 보상): 값이 거짓

== 서비스: EggService 초기화·알 놓기
  ok   초기화마다 15구역 × 둥지 8개 = 알 120개, 'ALL EGG RESET!' 공지, 알은 둥지 위에 놓임
  ok   알의 펫은 그 구역 둥지 펫 풀에서만, 특별 알이 아니면 비밀·영원·신성 없음, 천사&악마는 이번 주기 쪽 펫만
  ok   초기화를 60번 반복해도 알이 새지 않고(항상 120개) 희귀 알 공지가 가끔 나옴 (비밀 8%·영원 2%·신성 0.2%)

== 서비스: EggService 줍기 (E 키) — 성공과 거부
  ok   낮에 둥지 알 옆에서 E: 머리 위로 듦 + RUN!! 알림(경비 이름·속도) + 속도 느려짐 + 통계
  ok   거부: 밤 / 이미 알을 들고 있음 / 남이 든 알 / 기절 / 죽음 / 없는 알 번호
  ok   줍기 거리 경계: 12 + 알 반지름 이내는 되고 0.1 더 멀면 안 됨 (서버가 거리를 직접 확인)
  ok   퀘스트 전용 알(영혼 세계 수호자): 퀘스트를 끝낸 사람만 주움

== 서비스: EggService 놓치기 (잡힘 규칙: 구역 안 → 둥지로, 밖 → 그 자리)
  ok   경비한테 알의 구역 안에서 잡히면 알이 원래 둥지로 돌아가고, 몸은 날아가 2.5초 기절
  ok   구역 밖에서 잡히면 알이 그 자리에 떨어지고(누구나 줍기), 60초 뒤 사라짐
  ok   다른 사람(방망이·곰덫)에게 당하면 구역 안이어도 그 자리에 떨어짐
  ok   죽으면 구역 규칙(안 → 둥지), 나가면(leave) 구역 밖이면 그 자리 / 알이 없으면 eggOutcome = None

== 서비스: EggService 둥지 예약·다시 채우기
  ok   알을 든 채 구역 안에 있는 동안은 둥지가 비어 있고, 구역을 벗어나 30초 뒤에야 새 알이 놓임 (낮에만)
  ok   밤에는 둥지 다시 채우기가 멈춤
  ok   초기화(대기)가 와도 든 알은 안 지워지고, 둥지 120개는 새 알로 전부 채워짐 (들고 있는 알 + 120 = 121)
  ok   takeCarried(배달): 알이 세상에서 사라지고 데이터만 돌려줌 / confiscate: 둥지로 돌아감 / dropCarriedAt: 지정 위치

== 서비스: GuardianService (경비 추격 판단·잡힘)
  ok   시작하면 15구역에 경비가 1마리씩 서 있음 (집 = 구역 중심, 상태 Idle, 대상 없음)
  ok   알 든 사람을 쫓음: 상태 Chase, 대상 UserId, 쫓는 속도 = SpeedMath, 목표 = 그 사람 위치
  ok   속도가 충분하면(추천 이상) 경비가 플레이어보다 느리고, 모자라면 더 빠르게 쫓음
  ok   잡힘 판정: 수평 6 이내 + 높이 10 이내 + 줍고 1.5초 지난 뒤 — 경계 포함, 잡히면 knockOut(guard) + 대상 해제
  ok   추격 포기 반경: 구역 반경 80 × 2 × 끈질김(숲 1) = 160 밖으로 나가면 경비가 포기하고 집으로 (ChaseEnded)
  ok   안 쫓는 경우: 밤·대기 / 안전 구역 / 기절 / 죽음 / 다른 구역 알 / 알 안 든 사람
  ok   여러 명이 알을 들면 경비에게 제일 가까운 사람을 쫓음
  ok   죽은 경비는 다시 만들어지고, 맵 밖으로 떨어진 경비는 집으로 순간이동
  ok   천사&악마 경비 이름은 이번 주기 쪽에 따라 천사/악마로 바뀜

== 설계문서 ↔ 데이터: 파서 자체 점검
  ok   숫자·시간 읽기 (K/M/B/T/Qa, 쉼표, +, 시·분·초)
  ok   문서에 필요한 장이 다 있음

== 설계문서 4장 ↔ Biomes (구역 15개)
  ok   구역 15개: 순서·이름·추천 속도·경비·도감 무기가 문서 표와 같음
  ok   추천 속도는 문서 표에서도 계속 커짐 (뒤 구역일수록 어려움)

== 설계문서 5장 ↔ Pets (펫 134종의 희귀도·수입·부화 시간)
  ok   문서 5장 펫 줄 수 = 코드 펫 수 (134)
  ok   모든 펫: 문서 순서대로 이름·희귀도·초당 수입(원본)·부화 시간(원본)이 코드와 같음
  ok   모든 펫: 문서 소제목의 구역·쪽(천국/지옥)·출처(퀘스트/합성)가 코드와 같음
  ok   같은 구역 둥지 펫은 문서 순서대로 희귀도가 내려가지 않음 (오타로 순서 뒤집힌 곳 찾기)
  ok   3장 희귀도 표: 이름·영어·순서, 가장 싼 펫 수입이 표의 최소값과 일치, 1~11번 구역 펫은 표 범위 안

== 설계문서 7·8장 ↔ Sizes, Mutations
  ok   7장 크기 표: 등장 확률·수입 배율·속도 감소가 같고 확률 합은 100%
  ok   8장 돌연변이 표: 배율이 같고, 자연 확률(5%/2%/0.5%)·획득 확률(97.5%/2.5%/10%/1.5%) 일치
  ok   8장: 중첩 예시 균열 2.75 × 혼란 2.75 = 7.56배

== 설계문서 9장 ↔ Upgrades (우리·러닝머신·트레일 가격표)
  ok   9-1 우리: 11단계 비용·칸 수가 같음 (1단계는 무료 7칸)
  ok   9-2 러닝머신: 10단계 비용·걸음당 속도(원본)가 같음 (1단계 = 해금 $1,000)
  ok   9-3 트레일: 11개 이름·배율·가격이 같음
  ok   9-5 도감 보상 예시(닭·라쿤·파타핌)가 Index.reward 와 같음

== 설계문서 1·2·3·10·11·14장 흩어진 숫자 ↔ Config
  ok   2장 낮/밤/대기 시간, 밤 30배
  ok   서버 7명, 곰덫 5초, 성장 3배, 무료 보상 +10,000 속도, 퓨전 3마리
  ok   3장: 신성 등장 확률 약 0.2%
  ok   4장: 구역마다 둥지 8개

== 경계: 추천 속도와 경비 (알 무게 포함)
  ok   알 없이 속도가 추천 속도와 정확히 같으면 경비가 못 잡음 (모든 구역)
  ok   보통 알(-10%)을 들면 추천 속도 그대로로는 잡힘 — 안전선은 추천 × 0.97 ÷ 0.9 (표지판 숫자보다 약 8% 더 필요)
  ok   크기별 안전선: 딱 경계는 안전, 경계보다 0.1% 모자라면 잡힘 (4크기 × 15구역)
  ok   큰 알일수록 필요한 속도가 커짐: 표지판 속도 대비 보통 1.078배, 큼 1.21배, 거대 1.49배, 초거대 1.94배
  ok   경비는 안전한 사람보다 느리고 위험한 사람보다 빠르게 쫓음 (WalkSpeed 기준)
  ok   속도가 0·NaN·음수여도 경비 계산이 터지지 않음
  ok   시작 속도(20)로: 숲은 초거대 알도 안전, 호수(900)는 보통 알도 위험

== 경계: 알 무게 감소 후 속도
  ok   알을 들면 WalkSpeed 가 크기 감소율만큼 줄고 하한 8 밑으로는 안 내려감
  ok   walkSpeedFor: 알 없으면(감소 0) 원래 속도, 감소가 있으면 느려짐, 감소율 1 이상도 터지지 않음
  ok   트레일 배율은 실효 속도에 곱해지고 1 미만은 1 로

== 경계: 밤 30배, 오프라인 24시간
  ok   낮 285초 + 밤 10초(×30) + 대기 3초 = 한 바퀴에 알이 자라는 양
  ok   부화 시간이 가장 긴 알(유령 왕 24시간 ÷ 3 = 8시간)은 몇 바퀴 만에 부화하나
  ok   부화 진행: 시간이 거꾸로(dt<0)여도 줄지 않고, 필요량에서 멈춤
  ok   오프라인 수입: 정확히 24시간은 전부, 24시간 1초 초과는 상한, 이상한 시각은 0
  ok   오프라인 성장: 상한 24시간, 첫 접속(0)은 안 자람

== 경계: 레이트 리밋 (모든 Remote)
  ok   Remote 마다 정확히 burst 번 통과 후 막힘, 다시 1개 회복하는 데 1/초당 회복 초
  ok   모든 Remote 의 한도가 말이 됨: burst ≥ 1, 초당 회복 > 0, 부화·장착 같은 UI 버튼은 burst ≥ 2
  ok   오래 쉬어도 토큰이 burst 를 넘게 쌓이지 않음, 시간이 거꾸로 가도 안전

== 경계: 퓨전 거부·선택
  ok   초거대 3마리는 더 강해질 수 없는 펫(신성·위가 없는 희귀도)에서 거부, 위가 있으면 허용
  ok   정확히 3마리가 아니면 거부 (0, 1, 2, 4마리)
  ok   결과 후보가 2개면 약 50:50 으로 고름 (링 가드 3마리 → 영원 둥지 펫 2종)
  ok   돌연변이: 셋 다 같을 때만 유지 (순서 달라도), 하나라도 다르면 전부 사라짐

== 경계: 제단·퀘스트·치트 경고 (순수 규칙)
  ok   제단: 같은 사람이 두 번 불가 (같은 쪽에도, 반대쪽에도), 다른 사람은 가능
  ok   제단: 줄 맨 앞 두 사람이 같은 사람이면 짝을 안 맺음
  ok   퀘스트: 마법의 숲 알 20개 — 정확히 19개/20개 경계, 영원 알은 희귀도만 봄
  ok   퀘스트: 구역/희귀도가 없는 이벤트·모르는 종류는 무시
  ok   치트 경고: 정확히 5번째에 Kick, 60초에 하나씩 줄고 줄어든 뒤에는 처음부터
  ok   치트 이동 허용 거리: 1초 54(WalkSpeed 16), 120 이면 210 — 경계 포함

== 경계: 구역 판정·낮밤
  ok   구역 가장자리 ±0.001: 안/밖, 추격 포기 반경(구역 반쪽 × 2 × 끈질김)
  ok   낮 경계: 285초 딱 되면 밤, 295초 딱 되면 대기, 298초면 다음 낮
  ok   둥지 알 추첨: 크기 확률 70/20/8/2 의 누적 경계에서 정확히 바뀜

== 저장 데이터: 버전 1 → 2 마이그레이션
  ok   옛 데이터가 하나도 안 사라지고, 새 필드는 기본값, 호수 도감 완성이라 물 방망이가 자동 해금
  ok   마이그레이션은 두 번 돌려도 같고, 이미 2 인 데이터는 새 필드를 지우지 않음
  ok   버전 표시가 없거나 이상하면 1 로 보고 변환 (v2 필드는 비워짐 — 옛 데이터에는 원래 없던 필드)
  ok   더 새 버전(3, 4.5, 1e9)은 새 버전으로 인식 — 변환하지 않음

== 저장 데이터: 엉터리 입력
  ok   통째로 엉터리 (nil, 숫자, 문자열, 불리언, 빈 표, 배열, NaN, inf) → 항상 올바른 기본값
  ok   숫자 칸마다 쓰레기: 음수·NaN·inf·문자열·표·불리언 → 기본값 (거대한 유한 수는 그대로)
  ok   아주 큰 유한 수(1e300)는 받아들임, 소수 레벨은 내림, 범위 밖은 끝값으로
  ok   표 칸마다 쓰레기 (pets/equipped/trails/incubators/... 에 숫자·문자열·불리언·NaN)
  ok   펫 항목이 엉터리: 필드 빠짐·타입 틀림·모르는 id·중복 uid·너무 긴 uid → 그 항목만 버림
  ok   uid 가 보관함과 부화 슬롯 사이에서도 겹치지 않음 (겹치면 뒤쪽을 버림)
  ok   nextUid 는 기존 uid 번호보다 항상 큼 (겹치는 새 uid 가 안 나옴), 반복해도 겹침 없음
  ok   v2 필드 쓰레기: 퀘스트·제단·대기 줄·무기
  FAIL 저장 데이터의 펫이 500마리가 넘으면 불러올 때 500마리까지만 남김 (REMOTES.md: Snapshot.pets 는 최대 500)
      D:\준수\RobloxST\Roblox_studio\tests\save_data.spec:572: 펫 800마리가 그대로 로드됨: 값이 거짓
  ok   펫 5,000마리 + 부화 슬롯 5,000개짜리 큰 데이터도 1초 안에 처리

== 저장 데이터: 무작위 퍼징 (쓰레기 5,000개)
  ok   아무 쓰레기를 넣어도 안 터지고 결과는 항상 올바른 PlayerData, 한 번 더 보정해도 그대로

== 참조: Remote 이름 (Remotes.luau ↔ REMOTES.md ↔ 서버 ↔ 클라)
  ok   REMOTES.md 1장 표 = Remotes.ToClient, 2장 표 = Remotes.ToServer (이름이 한 글자도 안 다름)
  ok   REMOTES.md 2장의 레이트 리밋 숫자(burst / 초당) = Remotes.RateLimits
  ok   코드에서 쓰는 Remotes.ToClient.X / Remotes.ToServer.X 는 전부 실제 이름 (서버·클라 모두)
  ok   클라→서버 Remote 14개 전부 서버에 처리기(Net.on)가 있음
  ok   서버→클라 Remote 19개 전부 서버 코드 어딘가에서 보냄 (Net.fire 에 쓰임)
  ok   클라→서버 Remote 14개 전부 클라가 보내는 코드(UI)가 있음 (퓨전·사쿠라·제단·비밀 통로 화면 포함)
  ok   클라가 받는 서버→클라 Remote 중 핵심 이벤트는 전부 수신 코드가 있음
  ok   ToolKinds: 서버가 주는 Tool 이름, 핫바 그림·이름·색이 모두 같은 9개

== 참조: Config / Tags / 소리 / 창 이름이 진짜 있는 이름인지
  ok   src 전체의 Config.X 는 전부 Config 에 있는 이름 (오타는 조용히 nil 이 됨)
  ok   src 전체의 Tags.X / Tags.PlayerAttributes.X / Attr.X / StateAttr.X / Groups.X 가 진짜 있는 이름
  ok   src 전체의 Visuals.Tags 별명(VT.X) 도 진짜 있는 이름
  ok   클라가 재생하는 소리 이름(SoundController.play / sound = / setMusic)은 전부 Sounds.luau 에 있음
  ok   구역 배경음 Bgm_<구역 id> 가 구역마다 있고 '음악'으로 표시됨, Visuals.biomes[..].music 과 같음
  ok   HUD 메뉴가 여는 창 이름(Windows.toggle)은 전부 컨트롤러가 등록한 이름
  ok   Config 안에 NaN/음수/이상한 값 없음 (숫자는 유한, 시간·거리는 0 이상)

== 참조: 겉모습 데이터(Visuals) ↔ 펫·구역 ↔ 서버 코드
  ok   서버 코드에서 체형 템플릿 17종, 장식 70종 이상, 구역 장식 종류 50종 이상을 읽어 옴 (파서 점검)
  ok   모든 펫(134종)에 생김새가 있고, 체형·장식이 PetVisualService 에 구현돼 있음
  ok   경비 전용 모델(Visuals.extra)과 15구역 경비 모양이 다 있고 구현돼 있음
  ok   15개 구역 테마: 구역 장식 종류가 MapBuilder 에 구현돼 있고, 재료 이름이 진짜 Enum.Material, 배경음이 있음
  ok   돌연변이마다 알 껍데기 모양, 희귀도 효과 이름, 특별 알 3종, 베이스 색 7개
  ok   펫 모양 색은 0~255 정수 3개, 구역 테마 색도 마찬가지

== 참조: 진입점이 모든 서비스·컨트롤러를 시작하는지
  ok   Main.server: Services 폴더의 start() 가 있는 서비스는 전부 require + start() 호출, CycleService.run() 이 마지막
  ok   Main.client: Controllers 폴더의 컨트롤러는 전부 boot 되거나 다른 모듈이 불러감
  ok   default.project.json: 경로가 실제로 있고 진입점 두 개가 RunContext 스크립트 이름임

== 참조: 위험한 버릇 찾기 (소스 글자 검사)
  ok   옛 전역 wait() / spawn() / delay() 를 안 씀 (task.wait / task.spawn / task.delay 만)
  ok   while true 무한 루프 안에는 반드시 task.wait 이 있음 (시간을 안 쉬면 서버가 멈춤)
  ok   서버 코드의 WaitForChild 는 전부 시간 제한이 있음 (없으면 파트가 안 생길 때 영원히 멈춤)
  ok   Instance.new 의 두 번째 인자(부모) 방식을 안 씀, 옛 Connect 소문자(:connect)는 Signal 에만
  ok   서버의 Remote 처리기는 전부 Net.on 으로만 (OnServerEvent 직접 연결 금지 = 레이트 리밋·pcall 우회)
  ok   클라가 서버 값을 바꾸려는 코드 없음: 클라 코드는 FireServer 대신 Net.send 만, 돈·속도 Attribute 를 쓰지 않음

결과: 329 통과, 2 실패

실패 목록:
  - 서비스: ToolService 곰덫 (설치·5초 묶임·수명) > 곰덫을 얻을 방법: 시작 지급 3개 말고는 도감·퀘스트 어디서도 늘어나지 않음 — [설계 구멍] 다 쓰면 끝
      D:\준수\RobloxST\Roblox_studio\tests\services_tools.spec:405: 곰덫을 늘리는 코드가 없음 (설계문서 10장: 곰덫 = 도감 보상): 값이 거짓
  - 저장 데이터: 엉터리 입력 > 저장 데이터의 펫이 500마리가 넘으면 불러올 때 500마리까지만 남김 (REMOTES.md: Snapshot.pets 는 최대 500)
      D:\준수\RobloxST\Roblox_studio\tests\save_data.spec:572: 펫 800마리가 그대로 로드됨: 값이 거짓
```

## 부록 B. 밸런스 시뮬레이션 출력

### `lune run tests/sim_progress.luau`

```
== 밸런스 1차: 구역 추천 속도 도달 시간 ==
러닝머신 배율 3 × 초당 걸음 1, 성장 배율 G = 3, 주기당 알 1개, 시드 9개, 최대 100시간

구역                추천 속도     중앙값      최소~최대           러닝머신만(도감 속도 보상 제외)
1. 숲              10        0.0h     0.0h~0.0h       0.0h
2. 호수             900       0.0h     0.0h~0.0h       0.0h
3. 사막             10K       0.0h     0.0h~0.0h       0.0h
4. 정글             40K       0.1h     0.1h~0.1h       0.1h
5. 눈              170K      0.2h     0.2h~0.3h       0.3h
6. 화산             700K      0.5h     0.4h~0.5h       0.5h
7. 심연의 바다         2.5M      0.7h     0.7h~0.8h       1.0h
8. 선사시대           18M       1.7h     1.5h~2.3h       2.5h
9. 코스믹            700M      13.0h    12.0h~14.4h     15.5h
10. 벚꽃            2.5B      16.6h    15.8h~19.9h     27.8h
11. 타이탄 사원        7B        20.0h    18.7h~23.5h     54.4h
12. 천사 & 악마       20B       26.4h    21.9h~33.7h     96.5h
13. 마법의 숲         50B       27.0h    22.7h~34.1h     >100h
14. 사탕 왕국         150B      45.8h    31.6h~52.1h     >100h
15. 유령 성          500B      56.5h    47.6h~60.4h     >100h

목표 8구역 3~5시간 → 1.7h 벗어남
목표 13구역 20~30시간 → 27.0h OK
목표 15구역 40~60시간 → 56.5h OK

(시드 1 마지막 상태: 러닝머신 10레벨, 트레일 ×20, 우리 10레벨, 실효 속도 553B, 초당 수입 $117B)
```

### `lune run tests/sim_progress.luau sweep` (러닝머신 배율)

```
러닝머신 배율 스윕 (TREADMILL_STEPS_PER_SECOND = 1, 시드 5개 중앙값)
배율      8구역         13구역        15구역        | 러닝머신만 8 / 13 / 15
1       2.9h        36.3h       65.5h       | 5.1h / >100h / >100h
2       2.2h        27.9h       59.3h       | 3.4h / >100h / >100h
3       1.8h        27.0h       58.2h       | 2.7h / >100h / >100h
4       1.7h        25.1h       58.1h       | 2.2h / >100h / >100h
6       1.4h        21.3h       48.7h       | 1.8h / 86.1h / >100h
8       1.2h        19.9h       42.9h       | 1.6h / 76.3h / >100h
12      1.0h        18.4h       38.3h       | 1.2h / 66.3h / >100h
16      0.9h        16.5h       35.7h       | 1.2h / 55.8h / >100h
24      0.8h        12.8h       33.1h       | 0.9h / 45.6h / >100h
32      0.7h        13.0h       30.4h       | 0.8h / 37.5h / >100h
48      0.6h        11.6h       34.0h       | 0.6h / 28.0h / 92.4h
```

### `lune run tests/sim_progress.luau whatif` (도감 속도 보상 지수)

```
도감 속도 보상 지수 what-if (속도 보상 = 희귀도 기본 × (추천 속도/3600)^지수, 시드 5개 중앙값)
러닝머신     지수     8구역       13구역      15구역
3        1      1.0h      7.5h      7.8h
3        0.9    1.3h      12.3h     13.1h
3        0.85   1.5h      16.1h     20.1h
3        0.8    1.8h      27.0h     58.2h
3        0.75   2.0h      53.5h     >100h
6        0.8    1.4h      21.3h     48.7h
6        0.75   1.5h      41.2h     >100h
12       0.75   1.0h      27.1h     >100h
12       0.7    1.0h      45.1h     >100h
24       0.7    0.9h      29.2h     >100h
```

## 부록 C. 타입 검사 파일별 목록 (HEAD `fe23981`, 도구 `tools/luau-analyze.ps1`)

검사: 커밋 fe23981 (HEAD), luau-lsp 1.70.1 (Luau 0.743 엔진), 경로: src
합계: type 77, require 0, lint 1, syntax 0

### src/client/Controllers/ChaseController.luau (5)
- 줄 187 [type] Expected this to be 'UDim2', but got 'number'
- 줄 188 [type] Expected this to be 'UDim2', but got 'number'
- 줄 189 [type] Expected this to be 'UDim2', but got 'number'
- 줄 190 [type] Expected this to be 'UDim2', but got 'number'
- 줄 201 [type] Expected this to be 'number', but got 'UDim2'

### src/client/Controllers/FusionController.luau (1)
- 줄 114 [type] Expected this to be '"count" | "duplicate" | "mismatch" | "unknown" | "weaker"', but got 'string'; none of the union options are compatible

### src/client/Controllers/GiftController.luau (1)
- 줄 65 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, sound: string, textSize: number |}' caused by: None of the union options are compatible. For example: Expecte...

### src/client/Controllers/HatchController.luau (1)
- 줄 267 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...

### src/client/Controllers/HotbarController.luau (2)
- 줄 187 [type] Expected this to be 'ButtonOptions?' but got '{| parent: Frame |}' caused by: None of the union options are compatible. For example: Expected this to be exactly 'ButtonOptions' but got '{| parent: Frame |}' ...
- 줄 188 [type] Expected this to be 'Instance', but got 'nil'

### src/client/Controllers/IncubatorController.luau (6)
- 줄 69 [type] Expected this to be 'ButtonOptions?' but got '{| layoutOrder: number, parent: Frame, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be exactly 'Button...
- 줄 74 [type] Expected this to be 'ButtonOptions?' but got '{| layoutOrder: number, parent: Frame, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be exactly 'Button...
- 줄 148 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...
- 줄 157 [type] Cannot call a value of type {IncubatorRecord} in union: {IncubatorRecord} | {| |} | {| |}
- 줄 192 [type] Cannot call a value of type {IncubatorRecord} in union: {IncubatorRecord} | {| |}
- 줄 220 [type] Cannot call a value of type {IncubatorRecord} in union: {IncubatorRecord} | {| |}

### src/client/Controllers/IndexController.luau (3)
- 줄 76 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, sound: string, textSize: number |}' caused by: None of the union options are compatible. For example: Expecte...
- 줄 145 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, sound: string, textSize: number |}' caused by: None of the union options are compatible. For example: Expecte...
- 줄 204 [type] Expected this to be 'ButtonOptions?' but got '{| layoutOrder: number, parent: ScrollingFrame, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be exactl...

### src/client/Controllers/NotifyController.luau (1)
- 줄 177 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, sound: string, textSize: number |}' caused by: None of the union options are compatible. For example: Expecte...

### src/client/Controllers/PetsController.luau (6)
- 줄 70 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, sound: string, textSize: number |}' caused by: None of the union options are compatible. For example: Expecte...
- 줄 87 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...
- 줄 91 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...
- 줄 120 [type] Cannot call a value of type {string} in union: {string} | {| |}
- 줄 208 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...
- 줄 219 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, sound: string, textSize: number |}' caused by: None of the union options are compatible. For example: Expecte...

### src/client/Controllers/QuestController.luau (1)
- 줄 152 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, sound: string, textSize: number |}' caused by: None of the union options are compatible. For example: Expecte...

### src/client/Controllers/SakuraController.luau (2)
- 줄 208 [type] Cannot call a value of type {IncubatorRecord} in union: {IncubatorRecord} | {| |}
- 줄 214 [type] Cannot call a value of type {PetRecord} in union: {PetRecord} | {| |}

### src/client/Controllers/SettingsController.luau (1)
- 줄 43 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...

### src/client/Controllers/ShopController.luau (3)
- 줄 61 [type] Expected this to be 'ButtonOptions?' but got '{| layoutOrder: number, parent: Frame, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be exactly 'Button...
- 줄 174 [type] Cannot call a value of type {string} in union: {string} | {| |}
- 줄 230 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...

### src/client/Controllers/WeaponController.luau (1)
- 줄 365 [type] Expected this to be exactly 'Attached', but got '{| model: Model, style: string | string | string, swinging: boolean, trail: Trail?, weld: Weld |}' caused by: Property 'style' is not compatible. Expected thi...

### src/client/Controllers/WorldFxController.luau (1)
- 줄 60 [type] Types Instance and nil cannot be compared with == because they do not have the same metatable

### src/client/UI/PetPicker.luau (11)
- 줄 96 [type] Cannot call a value of type {string} in union: {string} | {| |}
- 줄 99 [type] Cannot call a value of type {PetRecord} in union: {PetRecord} | {| |}
- 줄 119 [type] Cannot call a value of type {IncubatorRecord} in union: {IncubatorRecord} | {| |}
- 줄 481 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, sound: string, textSize: number |}' caused by: None of the union options are compatible. For example: Expecte...
- 줄 506 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...
- 줄 524 [type] Cannot call a value of type {Filter} in union: {Filter} | {| |}
- 줄 556 [type] Cannot call a value of type {Filter} in union: {Filter} | {| |}
- 줄 627 [type] Cannot call a value of type {Filter} in union: {Filter} | {| |}
- 줄 633 [type] Expected this to be 'ButtonOptions?' but got '{| layoutOrder: *error-type*, parent: Frame, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be exactly '...
- 줄 641 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...
- 줄 646 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, textSize: number |}' caused by: None of the union options are compatible. For example: Expected this to be ex...

### src/client/UI/Ui.luau (1)
- 줄 427 [type] Expected this to be 'ButtonOptions?' but got '{| anchor: Vector2, parent: Frame, position: UDim2, sound: string, textSize: number |}' caused by: None of the union options are compatible. For example: Expecte...

### src/server/Net.luau (3)
- 줄 39 [type] Expected this to be 'string', but got 'unknown'
- 줄 42 [type] Expected this to be 'string', but got 'unknown'
- 줄 80 [type] Function only returns 1 value, but 2 are required here

### src/server/Services/AntiCheatService.luau (1)
- 줄 155 [type] Function only returns 1 value, but 2 are required here

### src/server/Services/BaseService.luau (4)
- 줄 143 [type] Value of type '{ [string]: Visual }?' could be nil
- 줄 193 [type] Types Player and nil cannot be compared with == because they do not have the same metatable
- 줄 604 [type] Function only returns 1 value, but 2 are required here
- 줄 614 [type] Function only returns 1 value, but 2 are required here

### src/server/Services/CycleService.luau (1)
- 줄 148 [type] Expected this to be '"Day" | "Intermission" | "Night"' but got 'string | string | string' caused by: Not all union options are compatible. Expected this to be '"Day" | "Intermission" | "Night"', but got 'str...

### src/server/Services/EggService.luau (2)
- 줄 619 [type] Cannot call a value of type {NestSlot} in union: {NestSlot} | {| |}
- 줄 812 [type] Function only returns 1 value, but 2 are required here

### src/server/Services/EggVisualService.luau (1)
- 줄 289 [type] Function only returns 1 value, but 2 are required here

### src/server/Services/FusionService.luau (1)
- 줄 80 [type] Expected this to be '"count" | "duplicate" | "mismatch" | "unknown" | "weaker"' but got '"count" | string' caused by: Not all union options are compatible. Expected this to be '"count" | "duplicate" | "misma...

### src/server/Services/IncomeService.luau (1)
- 줄 25 [type] Function only returns 1 value, but 2 are required here

### src/server/Services/MapBuilder.luau (2)
- 줄 2833 [type] Expected this to be '{TextLabel}', but got 'nil'
- 줄 2837 [type] Expected this to be '{TextLabel}', but got 'nil'

### src/server/Services/PetVisualService.luau (2)
- 줄 2097 [type] Function only returns 1 value, but 2 are required here
- 줄 2130 [type] Function only returns 1 value, but 2 are required here

### src/server/Services/PlayerLifecycle.luau (1)
- 줄 47 [type] Function only returns 1 value, but 2 are required here

### src/server/Services/RewardService.luau (1)
- 줄 59 [lint] Member 'IsInGroup' is deprecated, use 'Player:IsInGroupAsync' instead

### src/server/Services/ToolService.luau (7)
- 줄 101 [type] Expected type table, got 'nil' instead
- 줄 103 [type] Value of type 'Tool?' could be nil
- 줄 104 [type] Value of type 'Tool?' could be nil
- 줄 114 [type] Expected type table, got 'nil' instead
- 줄 116 [type] Value of type 'Tool?' could be nil
- 줄 235 [type] Expected this to be exactly 'Trap', but got '{| owner: Player, part: Part, placedAt: number |}' caused by: Property 'part' is not compatible. Expected this to be exactly 'BasePart', but got 'Part'
- 줄 328 [type] Function only returns 1 value, but 2 are required here

### src/server/Services/UpgradeService.luau (1)
- 줄 147 [type] Function only returns 1 value, but 2 are required here

### src/shared/AltarRules.luau (2)
- 줄 75 [type] Cannot call a value of type {Offer} in union: {Offer} | {| |}
- 줄 86 [type] Cannot call a value of type {Offer} in union: {Offer} | {| |}

### src/shared/FusionRules.luau (1)
- 줄 193 [type] Expected this to be '("count" | "duplicate" | "mismatch" | "unknown" | "weaker")?' but got '(string | string | string | string | string)?' caused by: Not all union options are compatible. Expected this to be...

## 8. 스튜디오 실제 플레이 테스트 (본부장, 2026-10-18, 커밋 8558d23 + 채팅 설정 변경)

사장님 PC의 로블록스 스튜디오에 MCP로 직접 연결해서 `build/StealAnEgg.rbxl` 을 플레이(F5)하고 확인했습니다. 캐릭터 이동은 클라이언트 PathfindingService + `Humanoid:MoveTo` 로, 줍기는 ProximityPrompt `InputHoldBegin/End` 로, 나머지는 Remote 로 흉내 냈습니다.

| # | 확인한 것 | 결과 |
|---|---|---|
| 1 | 서버 시작, 출력창 빨간 오류 | **통과** — 우리 코드 오류 0건. 로블록스 내부 `UIBlox FoundationProvider` 경고만 반복(무시해도 됨) |
| 2 | 맵 생성 | **통과** — 구역 15, 둥지 120, 알 120, 베이스 7, 특수 장소 태그 전부 존재, 임시 파트 없음(`Specials` 에는 사쿠라 크리스탈 3개만) |
| 3 | 경비 15마리 | **통과** — 전부 체력 100, `RequiresNeck=false`, Idle 상태로 대기 (B1 고침 확인) |
| 4 | 화면(HUD·메뉴 6개·핫바·베이스 표지판) | **통과** — 스크린샷 확인 |
| 5 | 알 줍기 → RUN!! → 경비 추격 → 잡힘 | **통과** — 가만히 서 있으면 닭에게 잡히고, 래그돌로 약 70스터드 날아가고, **구역 안이라 알이 둥지로 복귀** |
| 6 | 알 들고 집까지 도망 → 배달 → 부화 슬롯 | **통과** — 속도 20(알 들면 18) vs 닭 9. 12초 만에 배달, 슬롯 1에 5초 부화 |
| 7 | 밤 30배 성장, "다 자랐어요" 알림 | **통과** |
| 8 | 부화(HatchEgg) → 펫 카드 → 수입 | **통과** — 개 $6/초(=2×3배), 돈이 1초마다 오름, 우리에 펫 모델 + `$6/초` 이름표 |
| 9 | 도감 보상(ClaimIndexReward) | **통과** — 개: 속도 +420, 돈 +$200 |
| 10 | 무료 보상(ClaimFreeReward) | **통과** — 1회 +10,000 속도, 2회째 거부 |
| 11 | 상점: 우리 L2($1K, 8칸), 러닝머신 L1($1K)·L2($15K) | **통과** |
| 12 | 트레일: 회색($100, ×1.5) → 파랑(×2.5), 회색 재구매 시 돈 안 빠짐 | **통과** |
| 13 | 러닝머신 위 5초 | **통과** — +75 속도(레벨 2 = 걸음당 5 × 3배 × 5초) |
| 14 | 곰덫: 베이스 밖에서 설치, 개수 8→7 | **통과** |
| 15 | 방망이: UseTool 시 Tool `SwingTick` 갱신(B10) | **통과** |
| 16 | 낮/밤/초기화 `/skip` 3회 | **통과** — 밤·초기화에 벽 60/60 켜짐, 낮에 0/60, 조명 ClockTime 변화, "ALL EGG RESET!"·특별 알 공지 |
| 17 | 퓨전: 닭 3마리($9) → 새(고급, $24/초), 장착 유지 | **통과** |
| 18 | 장착 해제 / Equip Best | **통과** |
| 19 | 퀘스트 `/quests` → 문 CollisionGroup 전환 | **통과** |
| 20 | 치트 방지 | **통과** — 테스트 도구가 캐릭터를 96스터드/초로 옮겼을 때 "경고 1/5" 발생 |
| 21 | 채팅 치트 명령 | **고쳐서 통과** — 아래 고장 S1 |

### 스튜디오에서 발견해 고친 것
- **S1 (중간) 채팅 명령 무반응.** 자리(place)가 옛 채팅(`LegacyChatService`)이라 `/money …` 가 Player.Chatted 로 오지 않았고, 수석이 등록한 `TextChatCommand` 도 새 채팅에서만 동작합니다. `default.project.json` 에 `TextChatService.ChatVersion = TextChatService` 를 넣어 새 채팅으로 바꿨습니다. 바꾼 뒤 `/money`, `/speed`, `/trap`, `/skip`, `/pet`, `/quests` 전부 동작 확인.
- **S2 (낮음) 길찾기 걸림.** 숲 둥지 `Egg_e3`(−162, 202) 로 가는 길에서 PathfindingService 경로가 23번째 지점에서 막혔습니다(장식 또는 둥지 테두리로 추정). 다른 둥지(`Egg_e7`)는 문제없음. 실제 플레이어는 돌아가면 되지만, 선임이 장식 배치를 한 번 더 볼 것.

### 아직 스튜디오에서 못 본 것
- 사쿠라 인큐베이터·제단·비밀 통로(먼 구역까지 걸어가는 테스트 생략), 폰 에뮬레이터 화면, 실제 DataStore 저장(게시 전), 2인 플레이(서로 알 뺏기), 소리(ID 전부 0).
- 키보드로 `/` 를 눌러 채팅창에 치는 경로는 테스트 도구의 한계로 자동화하지 못했습니다. 사장님이 직접 쳐 보면 됩니다.

### 테스트에 쓴 도구
- `tools/studio-mcp.ps1`: 스튜디오 MCP(`%LOCALAPPDATA%\Roblox\mcp.bat`)에 명령 하나를 보내는 다리. Claude 세션에 MCP 가 안 붙었을 때 사용.
- `tools/studio-run.ps1`: Luau 파일을 스튜디오 Edit/Client/Server 에서 실행(CRLF→LF 변환 포함).

## 9. 스튜디오 추가 테스트: 사쿠라 인큐베이터 · 제단 · 폰 화면 (본부장, 2026-10-18)

이동은 치트 `/speed 1e9` + 클라 PathfindingService 로 베이스→벚꽃 구역(1,300스터드)을 21초에 갔습니다. 특수 장소는 Remote 로 직접 호출.

| # | 확인한 것 | 결과 |
|---|---|---|
| 22 | 사쿠라 인큐베이터 해금(`SakuraOffer`, 학 바치기) | **통과** — 학 1마리 소모, `SakuraUnlocked=true`, 안내 알림 |
| 23 | 블룸 부여(`SakuraApply`) | **통과** — 크리스탈 5→4, 학에 `bloom`(×1.5), 큰 꽃 연출 + "블룸 돌연변이가 피었어요! (×1.5)" 토스트 |
| 24 | 벚꽃 구역 표시 | **통과** — 상단 띠 "10. 벚꽃 · 추천 속도 2.5B" |
| 25 | 제단 제물(`AltarOffer`, 천국 제단 + 빛의 비둘기) | **통과** — `AltarUpdate pending`, 제단 `PendingCount` 1, 상태 띠 "제단: 기다리는 중 (1/2)", 제단 위 "기다리는 제물 1개!", 빛기둥 |
| 26 | 같은 사람이 같은 주기에 두 번 바치기 | **통과(거부)** — "이번 주기에는 이미 제물을 바쳤어요" |
| 27 | 주기 끝나면 제물 취소 | **통과** — 초기화 때 `PendingCount` 0, "제단 제물이 취소됐어요 (펫은 그대로)" |
| 28 | 폰(iPhone 17 Pro, 뷰포트 750×381) HUD | **문제 3개 — 아래 P1~P3** |
| 29 | 폰에서 창 크기 | **통과(숫자로)** — 도감 520×331, 펫 523×331, 상점 485×331, 선물 392×294, 설정 364×252 전부 뷰포트 안 |
| 30 | 치트 명령 `/pet`, `/crystal`, `/skip` 새 채팅에서 | **통과** |

### 폰 화면 고장 (선임 담당)
- **P1 (중간) 왼쪽 메뉴 6개가 세로로 안 들어감.** `Hud.LeftMenu` 가 56×336 인데 y=−7 에서 시작해 맨 위 "도감" 버튼(및 배지)이 위로 잘리고, 맨 아래 "퀘스트" 가 화면 아래로 잘림(뷰포트 높이 381). 제안: 뷰포트 높이가 ~450 미만이면 UIScale 을 0.8 정도로 줄이거나, 버튼을 2열(3+3)로 배치.
- **P2 (중간) 로블록스 터치 조이스틱과 겹침.** 폰 스크린샷에서 왼쪽 아래 조이스틱이 "설정·퀘스트" 버튼 위에 놓임. P1 을 고치면서 메뉴를 위쪽에 모으거나 조이스틱 영역(왼쪽 아래 약 120×120)을 비울 것.
- **P3 (낮음, 확인 필요) 핫바와 점프 버튼.** 핫바가 오른쪽 아래(456,242 크기 280×67)에 있어 터치 점프 버튼 자리와 겹칠 가능성. 에뮬레이터에서는 `CoreGui.TouchGui` 를 못 읽어 숫자로 확인 못 함. 실제 폰이나 에뮬레이터 화면에서 눈으로 확인하고, 겹치면 핫바를 왼쪽으로 옮기기.
- (참고) 사쿠라 블룸 토스트 "학 에 꽃이 피었어요" 가 인큐베이터 이름표와 잠깐 겹쳐 보임 — 연출 위치만 살짝 조정.
- (참고) 출력창의 `[DevCommands] 개발 명령 켜짐: quests` 는 명령 이름 전체가 아니라 하나만 찍힘(표시만 문제).

### 에뮬레이터 한계
- 디바이스 전환은 Client 데이터모델에서 `StudioDeviceSimulatorService:SetDeviceAsync` 로 플레이 중에도 됐음(끝나고 `StopSimulationAsync` 로 복구).
- MCP 가짜 마우스 클릭은 에뮬레이터 화면의 버튼에 닿지 않아 폰에서 창 열기는 자동화 못 함(크기 숫자로만 확인).

### 9-1. 폰 화면 고장 수정 확인 (본부장, 스튜디오 iPhone 17 Pro 750×381, 터치 모드)
- 메뉴 6개: 2열 3줄, 각 44×44, x 10~101 / y 27~167 — 전부 화면 안, 위·아래 잘림 없음 (P1 해결)
- 조이스틱(ThumbstickStart 29,230 74×74)과 메뉴가 겹치지 않음 (P2 해결)
- 핫바 (510,241) 130×67, 점프 버튼 (655,233) 70×70 — 겹치지 않음 (P3 해결)
- 화면 밖으로 나간 UI 요소 0개. `tests/smoke_client.luau` 에 750×381/844×390/1428×750 반응형 검사 추가(203 ok).

## 10. 2판(원작 구조) 스튜디오 확인 (본부장, 2026-10-18 밤, 커밋 976eb52)

| # | 확인한 것 | 결과 |
|---|---|---|
| 31 | 서버 시작, 출력창 오류 | **통과** — 오류 0, 파트 약 17,200개 |
| 32 | 일자 복도 맵 | **통과** — 양옆 벽돌 담장, 구역별 스터드 바닥, 모래띠, 경비 15마리가 z=120부터 240 간격으로 **잠자기(Sleeping)** |
| 33 | 허브·베이스 7개 | **통과** — 안전 구역 점선, 흰 구름 벽, X 울타리, 퓨즈 머신+청록 링, 판매 가게 8개, 러닝머신 7개, 배달 패드 0개 |
| 34 | 스폰 위치 | **통과** — 1번 베이스 앞마당(−52, −40), CurrentZone=hub |
| 35 | 알 줍기(E) | **통과** — 무게 50kg 표시, RunAlert |
| 36 | 경비 추격·잡힘(숲, 가만히 서 있기) | **통과** — 닭이 깨어나 64→37→13 접근 후 잡음, 알 둥지로, 약 200스터드 날아감, 경비 복귀 후 다시 잠듦 |
| 37 | **속도 모자라면 반드시 잡힘** (호수 900 vs 내 속도 200, 집으로 도망) | **통과** — 백조가 끝까지 쫓아와 잡음(reason=caught) |
| 38 | 속도 충분하면 도망(숲 10 vs 200) | **통과** — 허브 진입 시 ChaseEnded reason=safe |
| 39 | **베이스 울타리 안 진입 = 자동 배달** | **통과** — EggDelivered, 알이 우리 안(−68, −61)에 놓이고 프롬프트 생김 |
| 40 | `/grow` → 우리 안 알 프롬프트로 부화 | **통과** — 새(고급) $24/초, IncomeTick 팝업 신호 |
| 41 | 러닝머신 2판 | **통과** — 잠김 상태 안내($1K), 구매 후 올라서면 **고정(걷기 0, 밀어도 안 움직임)**, 1초마다 +6, **점프하면 내려옴** |
| 42 | 구역 배너 신호 | **통과** — ZoneEntered{숲/Forest} |
| 43 | HUD | **통과** — 원작 배치(왼쪽 메뉴 6개, 속도·돈·부스트, 핫바, 알·발바닥 버튼, 달/해 타이머) |

### 테스트 도구 주의
- `screen_capture`로 카메라를 옮겨 두면 **ProximityPrompt가 화면 밖이라 안 뜸** → 줍기 실패처럼 보인다. 테스트 전 `CameraType=Custom, CameraSubject=Humanoid`로 되돌릴 것. (게임 고장 아님)
- 파트가 많아 `screen_capture`가 자주 시간 초과됨.

### 남은 작은 일 (수석)
- 거대 경비 이름표가 몸 안에 묻힘(Head+3) → 겉모습 Height 위로.
- 거대 경비 잡힘 거리 6이 "몸 안에서 잡힘"처럼 보임 → 경비 크기에 비례(예: 6 + 높이×0.25).
- 트레일 장착/해제 Remote `EquipTrail(id)` 없음(지금은 표시만).
- crossrefs 테스트의 `PENDING_UI` 임시 목록 삭제.

## 11. 3판(알 가방·알 놓기·밤 30배) 스튜디오 확인 (본부장, 2026-10-19, 커밋 0ce7f4f)

빌드 `build/StealAnEgg.rbxl` 을 스튜디오에서 열고 플레이. 측정은 클라이언트 `execute_luau` 로 놓인 알 파트의 `Progress` 속성을 시간차로 읽음.

| 항목 | 결과 |
|---|---|
| `/egg axolotl` → 가방에 알 | ✅ `EggGranted` 수신 (uid i2, i3, i4), HUD 알 버튼 배지 4 |
| `PlaceEgg(uid, x, z)` 우리 안 아무 자리 | ✅ `Incubating_<uid>` 파트가 그 자리(−87,−40 / −77,−34 / −97,−46)에 생김, 이름표 "아홀로틀 / 4m 56s" |
| 낮 성장 속도 | **1.010 /s** (5초 측정, ClockTime 14) |
| 밤 성장 속도 (`/skip` 직후) | **30.002 /s** (4초 측정, ClockTime 22) → **29.7배** ✅ |
| 밤 10초 동안 | 5분짜리 알(300)이 밤 한 번에 다 자람 (68 → 189 → 300 "부화 준비 완료!") |
| 소리 | ✅ `Bgm_base`(rbxassetid://84797666595507) `Playing=true, IsLoaded=true` — 스토어 오디오 ID 재생됨 |

사장님이 "30배로 안 자란다"고 느끼신 건 아마 **가방 속 알은 안 자라고(의도), 우리에 놓은 알만** 자라기 때문. 놓은 알은 위 표대로 밤에 30배로 자람.

### 스튜디오 MCP 측정 팁 (다음에 또 쓸 것)
- `execute_luau` 안에서 `require` 한 모듈은 게임 스크립트와 **다른 복사본** (State/Sessions 가 비어 있음). 살아 있는 상태는 Instance·Attribute·Remote 로만 읽을 것.
- `TextChannel:SendAsync` 는 명령은 전달되지만 **돌아오지 않음** → `task.defer` 로 감싸서 호출. 안 그러면 호출이 5분 타임아웃.
- 긴 측정은 `task.spawn` 스레드에서 돌리고 결과를 `workspace:SetAttribute` 로 남긴 뒤, 짧은 호출로 읽기 (스레드는 호출이 끝나도 계속 돎).

## 12. 4판 스튜디오 확인 (본부장, 2026-10-22, 커밋 10c1c8f 빌드)

| 항목 | 결과 |
|---|---|
| 알 타이머 표시 (밤 30배) | ✅ 낮: 4m58s → 4m55s (3초에 3초) / `/skip` 밤: 3m55s → 3m24s → 2m54s → 2m23s (1초마다 30초씩) — 숫자가 ÷30 으로 점프하지 않음 |
| 경비 추격 속도 고정 | ✅ 숲 경비 추격 중 WalkSpeed 20.0, 내 속도를 18 → 1M(걷기 24.9 → 115)으로 바꿔도 20.0 그대로 |
| 걷기 곡선 | ✅ `/speed 1000000` → WalkSpeed 115.0, 허브에서 실제 이동 110.9 스터드/초 |
| 달릴 때 시야(FOV) | ⚠️ 컨트롤러는 돌지만(FOV 를 50 으로 바꾸면 70 으로 되돌림) MoveTo 이동은 MoveDirection 이 0 이라 안 넓어짐 → 수평 속도(AssemblyLinearVelocity)로 판단하게 고침, 다음 빌드에서 재확인 |
| 참고 | 시험 스크립트가 알을 줍고 경비 집(구역 가운데) 쪽으로 달려서 1.5초 유예 뒤 바로 잡힘 — 경비 집은 둥지에서 75~120 스터드 떨어져 있어 허브 쪽으로 달리면 시작 속도(걷기 24.9 > 경비 20)로 숲 경비는 따돌릴 수 있음 |

## 13. 4판 비주얼 스튜디오 확인 (본부장, 2026-10-22, 커밋 cf8ca14)

| 항목 | 결과 |
|---|---|
| 구역 입구 아치·현수막 | ✅ "1 숲 🙂 추천 속도 10" 글씨 보임, 아치 위 알 장식, 담장 기둥·덩굴, 흙길·잔디 줄 |
| 둥지·알 | ✅ 짚 링 + 매끈한 타원 알(개 알 일반: 점 2), 짚 막대가 알을 안 뚫음 (첫 판의 "블록 6층" 알은 고침) |
| 경비 얼굴 | ✅ 잘 때 ─ ─ 감은 눈·눈썹 없음(Brow 투명 1) → 알 훔치면 Chase: 눈 뜨고 화난 눈썹(투명 0) |
| 베이스·허브 | ✅ 뒤 벽 헛간, 울타리, 짚 바닥, 퓨즈 머신 안테나, 허브 분수·돌길·가로등, 베이스 7개 지붕 |
| 달릴 때 시야 | ✅ 가만히 70 → 속도 1M(걷기 115)로 달릴 때 81.3 → 멈추면 70 |
| 파트 수 | 맵 6,540 (전 7,534), 구역 최대 383 |
| 주의 | screen_capture 뒤에는 카메라를 Custom 으로 되돌려야 ProximityPrompt 줍기가 됨 (안 그러면 "훔치기"가 조용히 실패) |

## 14. 주임 5판 검수 (주임, 2026-10-22, HEAD d19acf9)

수석·선임이 끝낸 5판(퀘스트·선물 제거, 개 알 3초, 튜토리얼, 랭킹판, 쓰다듬기, 핫바 알 칸, 우리 안 펫 돌아다니기)과 4판의 경비 고정 속도·알 타이머 표시를 **"구멍 찾기"** 로 검사했습니다. `src/` 는 한 줄도 안 고쳤고(테스트·문서만), `rojo build`·commit 도 안 했습니다.

### 14-1. 검사 결과 (전부 통과)

| 검사 | 5판 시작 | 지금 | 비고 |
|---|---|---|---|
| `selene src` | 0 오류 · 0 경고 | 0 오류 · 0 경고 · 0 파싱 오류 | |
| `stylua --check src tests` | 통과 | 통과 | 새 테스트 파일도 stylua 로 정리함 |
| `lune run tests/run.luau` | 400 통과 | **460 통과 · 0 실패** | +60, 건너뜀(알려진 버그) 2 |
| `lune run tests/smoke_client.luau` | ok 531 | **ok 564 · FAIL 0** | +33 (핫바 경계·엉터리 신호) |
| `lune run tests/smoke_visuals.luau` | ok 429 | **ok 441 · FAIL 0** | +12 (복도 막힘·펫 126마리), 약 18초 |
| `lune run tests/sim_progress.luau` | 13구역 29.0h · 15구역 56.1h OK | 같음 | 8구역 2.2h("3~5시간 벗어남")는 전부터 있던 참고 줄 |
| `tools/luau-analyze.ps1` | type 0 · require 0 · lint 0 · syntax 0 | 같음 | |

### 14-2. 추가한 테스트 (60개 + 알려진 버그 2개 + 스모크 45줄)

**`tests/holes_tutorial.spec.luau` (17개 + 알려진 버그 1)** — 앞서 `tutorial.spec` 은 가짜 EggService 신호로 돌렸는데, 여기서는 **진짜 EggService·BaseService·PetService·DataService(가짜 저장소)** 로 끝까지 돌립니다.

| 무엇을 보나 | 결과 |
|---|---|
| 접속(1) → 줍기(2) → 허브 배달(3) → 놓기(4) → 부화(5, 자동 장착 안 됨) → 장착(끝) $500, 단계 알림 순서 `1,2,3,4,5,6` | 통과 |
| 든 알을 놓치는 8가지 길(경비 잡힘·방망이·곰덫·드롭 버튼 Remote·죽음·치트 압수·순간이동 의심·나감) 전부 2 → 1, 다시 주우면 2 | 통과 |
| 알 든 채 밤이 되면 서버가 베이스로 옮겨 배달 → 3단계 | 통과 |
| 3단계에서 알을 또 줍거나 놓쳐도 그대로, 1단계에서 빈 손 놓치기는 아무 일 없음, 끝난 사람은 어떤 일을 해도 TutorialUpdate·돈 변화 없음 | 통과 |
| **다시 접속해도 단계 유지** (1·3·4·5·끝을 저장 → 나감 → 다시 불러오기), 끝난 사람은 접속해도 안 뜨고 $500 도 다시 안 줌 | 통과 |
| 알 든 채(2단계) 나가면 저장된 단계는 1 | 통과 |
| 저장된 단계가 지금 상태와 안 맞으면(3인데 가방이 비었음, 4인데 우리가 비고 가방에 알, 5인데 펫도 알도 없음) 접속 때 1·3·1 로 맞춤 | 통과 |
| **스키마 4 → 5 (저장소 통과)**: 펫 있는 사람은 끝 상태·튜토리얼 안 뜸, 저장하면 5판 모양, `quests`·`questsRewarded`·`freeRewardClaimed` 칸 삭제, 받은 속도 10,020 그대로. 아무것도 안 한 사람은 1단계 + TutorialUpdate 1. 놀던 흔적 6가지(펫·놓인 알·가방 알·훔침·배달·부화) 중 하나만 있어도 끝, 빈 표·글자 숫자·음수는 "안 놀았음" | 통과 |
| 마이그레이션 멱등, 조작된 `tutorialStep=6`(안 놀았는데)은 무시, 5판 데이터의 이상한 단계(없음·글자·NaN·음수·99·2.9) 보정 | 통과 |
| 신호 연결: 7개 신호에 1번씩만 연결, 사람 12명이 오가도 연결 수 그대로(사람별 연결 없음), `start()` 를 두 번 불러도 보상 한 번 | 통과 |
| 거부된 EquipPet(없는 uid·이상한 글·숫자)은 단계 안 올림, `/tutorial reset` 뒤 순서대로 다시 | 통과 |
| `TutorialRules.advance` 는 모르는 사건·이상한 단계에도 안 터지고, 한 번에 두 단계 이상 안 뜀(배달 1→3, 부화 3→5 만 예외) | 통과 |
| **알려진 버그 B-2**: 5단계에서 펫이 "자동 장착"되면 안 끝남 | T.skip (재현됨) |

**`tests/holes_social.spec.luau` (26개 + 알려진 버그 1)**

| 무엇을 보나 | 결과 |
|---|---|
| 랭킹판: 정확히 10명 → 10줄, 11명 → 꼴찌만 빠짐(이름이 앞서도), 25명(섞어서 입장) → 큰 값부터 정확히 10명, 돈·속도 순위는 따로 | 통과 |
| 같은 값 → 이름 순 → 같은 이름이면 userId 순 (대소문자 포함, 세 번 불러도 같은 순서) | 통과 |
| 제외: 세션만 있고 불러오는 중 · 세션 없음 · loaded 인데 data 없음 · 나갔는데 세션이 남은 사람 | 통과 |
| 나가면 다음 10초 방송에서 빠지고 다시 들어오면 다시 나옴 · 아무도 없어도 안 터짐 · 100.5초에 정확히 10번 · 매번 새 표 · 표시 이름(빈 DisplayName → Name, 한글·이모지) | 통과 |
| NaN·무한대·음수 값이 섞여도 `build()` 가 안 터짐, 무한 속도 1등·음수 꼴찌 | 통과 |
| **알려진 버그 B-4**: NaN 한 명이 있으면 나머지 순서가 뒤섞임 | T.skip (재현됨) |
| 쓰다듬기: 가짜 uid 17가지 + 이상한 타입 10가지(없는 uid·49자·공백·대소문자·전각 숫자·`__index`·표·NaN·불리언·인자 없음·인자 여러 개) 전부 무시, **알림·방송 0, 처리 중 오류(warn) 0** | 통과 |
| 남의 펫 uid, 같은 uid 이름(p1)이 겹칠 때 "알림의 주인 = 보낸 사람" | 통과 |
| 장착 안 한 펫 · 장착 해제 · 다시 장착 · 장착 목록에만 있는 유령 uid | 통과 |
| 거리: 앞·뒤·옆 네 방향 19.9 는 되고 20.1 은 안 됨, **대각선 모서리 (15,15)=21.2 는 안 되고 (14,14)=19.8 은 됨**(축별로만 보는 버그 없음), 멀리·2000 스터드 | 통과 |
| 쿨다운: 0.99초 ✕ / 1.01초 ○, 거부된 시도는 쿨다운을 안 씀(가짜 뒤 진짜가 바로 통과), 두 사람이 같은 순간 각자 | 통과 |
| 캐릭터 없음·죽음·없는 베이스 번호(99, -1)·불러오기 전 | 통과 |
| 정상: `PetPetted(ownerUserId, uid)` fireAll 한 번, 인자 정확히 2개 · 레이트 리밋 100번 → 처리기 3번 | 통과 |
| 제거 청소: Remotes 에 QuestUpdate/ClaimFreeReward/quest 이름 없음(이름·레이트 리밋·실제 만든 RemoteEvent), 정의 개수 = 만든 개수, ToServer ↔ RateLimits 일치 | 통과 |
| `MapLayout.specials.questGate` · `Tags.QuestGate` · `QuestsDone` 없음, 마법의 숲(`enchanted_forest`)에 특수 장소 없음, 저장 기본값·Snapshot·DataUpdate 에 quests/flags 없음, `/quests` 는 무반응 | 통과 |
| 초기화 60번 동안 모든 알에 `QuestOnly` 없음 + 공지에 `questOnly` 없음 + 120개 전부 새 사람이 주울 수 있음 | 통과 |
| **옛 퀘스트 알 2종이 EXTRA_SPECIALS 로 계속 나옴**: 400번 초기화에서 지터버그(8%)·영혼 세계 수호자(1%) 둘 다, 자기 구역(마법의 숲) 둥지에, `Special` 공지와 함께. `EggRoll.rollExtraSpecials` 난수 0/0.999/경계/모르는 펫 id/2만 번 통계 | 통과 |

**`tests/holes_world.spec.luau` (17개)**

| 무엇을 보나 | 결과 |
|---|---|
| **경비 고정 속도(4판)**: 15구역 모두 추격 WalkSpeed = `toWalkSpeed(경비 속도 × 0.99)`(상한 250). 플레이어 속도 5·1천·1e15·1e30 × 알 무게 0·0.5·0.9 = 12가지에서도 같음 | 통과 |
| 추격 도중 플레이어 속도·WalkSpeed 를 40번 바꿔도 경비 속도는 **한 가지**(`distinct = 1`) | 통과 |
| 추격이 끝나면 평소 속도 `toWalkSpeed(경비 속도)` 로 돌아가 집으로 · 두 사람이면 가까운 사람, 속도는 같음 · 다른 구역 알이면 안 깨움 · 밤이면 추격 멈춤 | 통과 |
| **알 타이머(4판)**: `Economy.timerSeconds` = 남은 알 시간, 낮밤 상관없이 같은 값·0 아래로 안 내려감, 낮 1초 -1 / 밤 1초 -30, 낮↔밤을 오가도 늘거나 ÷30 으로 튀지 않음 | 통과 |
| 우리 알 이름표(서버 BaseService): 5분 이상 알이 낮 1초 -1, 밤 1초 -30, "부화 준비 완료!" · 개 알 3초(밤이면 첫 1초에 다 자람) · `/egg dog` → 가방에 개 알(부화 3초), 알 번호 중복 없음 | 통과 |
| 핫바 계산(`Layout.hotbarEggs`): 알 7개 → 6칸 + "+1", 6개 → 6칸, 50개 → 6칸 + "+44". 자리 1~16 × 고정 칸 0~12 × 알 0~60 모든 조합에서 규칙(자리 안 넘음·알 있으면 칸이나 "+n" 하나는 보임·못 보인 알이 있을 때만 "+n") | 통과 |
| 실제 화면 자리: PC 1428×750 은 10칸 이상, 폰 844×390 = 12칸, 750×381 = 10칸, 667×375 = 8칸(알 7개 → 5칸 + "+n") | 통과 (정보 줄) |
| **서버 Remote 막 던지기**: 모든 `ToServer` 에 핸들러가 붙어 있음 · 19개 Remote × 30가지 엉터리 인자(없음·nil·빈 글·7만 자·SQL 글·NaN/inf/-1/1e308·표·불리언·인자 10개…) 약 570번 → **오류(warn) 0, 돈·속도·펫·알·단계 그대로** | 통과 |
| `PlaceEgg` 좌표 NaN/inf/1e308/-1e308/먼 곳/남의 베이스 한가운데 → 놓이지 않고 오류도 없음 · 남의 알 uid·이미 놓은 uid 로 Place/PickUp/Hatch → 아무 일 없음 | 통과 |

**스모크 (스튜디오 없이 진짜 인스턴스)**
- `smoke_visuals.luau` +12줄: ① 구역 경계 14곳(마법의 숲 입구 포함)에 복도를 가로막는 단단한 파트(문·잠금)가 없음 — 일부러 `QuestDoor` 벽을 끼워 넣어 보니 **잡아냄**(검사가 살아 있음), ② **펫 126마리**(7베이스 × 18, 서버 최대) 부하·정리: 14-4 숫자, 나간 3명의 펫과 걷기 등록이 같이 사라짐, 장착을 바꿔 8번 다시 만들어도 걷기 등록이 안 샘(유령 0), 새 주인이 오면 다시 18마리, 15초 동안 메모리가 계속 늘지 않음. `xpcall` 로 오류 위치(traceback)도 찍게 함.
- `smoke_client.luau` +33줄: ① 핫바 알 칸 경계 — 알 0·1·5·6·7·8·12·50개 각각 칸 수와 "+n" 글자, **7개 = 6칸 + "+1"**, 새 알이 맨 앞·가장 오래된 알이 "+1" 로 밀림, **같은 목록이 100번 와도 칸을 다시 안 만들고(같은 인스턴스) 핫바 자손 수 그대로(179)**, 6번째 칸 누름 → `PlaceEgg(h2, x, z)`, 놓인 알은 핫바에서 사라지고 가려졌던 알이 올라옴, 다시 가방에 오면 칸이 다시 생김. ② 서버가 엉터리 모양(옛 서버·버그)을 보내도 `TutorialUpdate`·`LeaderboardUpdate`·`PetPetted` 29가지에 화면이 안 터지고 그 뒤 정상 신호는 그대로 처리.
- `TestKit.luau`: `T.skip(이름, 이유, 함수?)` 추가 — "알려진 버그"는 실패로 안 세지만, 함수를 주면 돌려 봐서 **아직 실패하면 SKIP(재현됨), 통과하면 "FIXED? T.skip 을 T.test 로 바꿔 주세요"** 라고 알려 줌. `tests/run.luau` 에 세 파일 등록.

### 14-3. 발견한 문제 (심각도 순) — 높음·치명 0건

| # | 심각도 | 어디 | 무슨 일 | 재현 / 확인 | 고치는 법 (제안) |
|---|---|---|---|---|---|
| **B-1** | **중간** (성능 위험, 스튜디오 확인 필요) | `PetVisualService.luau` `stepWalker` 2861줄(`w.model:PivotTo`), `stepPens` 2867, Heartbeat 연결 3208 | 서버가 **매 프레임(60Hz) 걷는 펫마다 모델 전체를 `PivotTo`**. 펫 1마리 ≈ 45.5 파트. 서버 최대(7 × 18 = 126마리)에서 측정: **프레임당 PivotTo 62.5번, 옮긴 파트 2,831개 → 초당 약 17만 번 파트 CFrame 쓰기** (루트만 복제된다면 초당 약 3,750번). 로블록스는 이 변화를 클라이언트에 복제하므로 폰·느린 인터넷에서 끊김, 서버 Heartbeat 시간 증가 가능 (Lune 숫자는 흉내라 ms 는 믿지 말 것) | `lune run tests/smoke_visuals.luau` 의 `[정보] 126마리 15초(900프레임)` 줄. 스튜디오: 펫 `/pet chicken 7` × 여러 명(또는 우리 업그레이드 뒤 18마리) → Ctrl+Shift+F3(네트워크 통계)에서 서버→클라 바이트, 서버 Heartbeat 시간 | ① 걷는 갱신을 15~20Hz 로 낮춤(복제도 그 정도라 눈에 안 띔) ② `PivotTo` 대신 `Root.CFrame` 만 바꿔 용접(WeldConstraint)된 파트가 따라오게 ③ 아무 플레이어도 우리 근처(예: 80 스터드)에 없으면 그 우리 펫은 멈춤 ④ 클라에서 걷게(서버는 목표 지점만) |
| **B-2** | 낮음 | `PetService.luau` `addPet`(자동 장착)과 `equipChanged`(equip·equipBest 에서만 발사), 호출처 `FusionService.luau:94`, `DevCommands.luau` `/pet` | 튜토리얼 5단계("펫 장착")는 `equipChanged` 신호로만 끝나는데, **빈 칸에 펫이 "자동 장착"되는 길(퓨전 결과·`/pet` 개발 명령)은 이 신호를 안 냄** → 장착 펫이 있는데도 5단계에 머무름 (펫 창에서 해제했다 다시 장착하거나 "모두 장착"을 눌러야 끝). 실제 새 사람은 5단계에서 펫이 1마리라 거의 안 생기지만, 개발 시험 때 `/pet` 을 쓰면 반드시 걸림 | `tests/holes_tutorial.spec.luau` 의 `T.skip("5단계에서 펫이 자동 장착되면…")` — 돌려 보면 "기대 6, 실제 5" | `addPet` 이 자동 장착을 했으면 `PetService.equipChanged:fire(player)` 도 부르기 |
| **B-3** | 낮음 | `HotbarController.luau` `watch()` 566~584줄 (ChildAdded 안 570~575, 시작 때 579~583) | 도구가 가방 ↔ 손을 오갈 때마다 **같은 도구의 `Count` 신호에 `refresh` 연결이 또 붙음**(끊는 코드 없음). 곰덫을 50번 들었다 내리면 연결 1 → 101. `Count` 가 바뀔 때(곰덫 설치·구매)마다 `refresh` 가 연결 수만큼 불림. 가방 `watch` 가 두 곳에서 불려(`player.ChildAdded` · `CharacterAdded` 뒤) 처음부터 2배. 오래 놀수록 설치 한 번에 갱신이 수백 번 | `lune run tests/smoke_client.luau` 의 `[알려진 약점 BUG-H1]` 줄 (c0 → c1) | 도구마다 연결을 한 번만(예: `connected[tool]` 표) 또는 `Destroying` 에서 끊기, 가방 `watch` 중복 호출 제거 |
| **B-4** | 낮음 (방어용) | `LeaderboardService.luau` `top()` 34~49줄 | 돈/속도 값이 **NaN** 이면 `table.sort` 비교 함수가 일관되지 않아 나머지 순서가 뒤섞임(Bob 900 이 5등으로 밀림). 지금은 NaN 이 생길 길이 없음(`Wallet` 이 막고 `DataSchema.reconcile` 이 고침) | `tests/holes_social.spec.luau` 의 `T.skip("NaN 돈이 한 명…")` | 정렬 전에 `value ~= value` 이면 0 으로 |
| **B-5** | 낮음 (방어용) | `LeaderboardController.luau:276` (그리고 115) `tostring(e.name)` | 랭킹 줄이 표가 아닌 값(숫자·글)이면 `attempt to index number with 'name'` 오류. 서버는 항상 표만 보내서 지금은 안 일어남 | `smoke_client` 의 `[알려진 약점 BUG-L1]` 줄 | `typeof(e) == "table"` 확인 |
| **B-6** | 낮음 (낭비) | `TutorialController.luau` 744~755줄(0.25초 루프), 688줄(`RenderStepped`) | 튜토리얼이 **끝난 사람도** 접속하는 내내 0.25초마다 `update()`(→ `layoutPanel` → `pushOthers` 로 UI 4개를 찾음)와 매 프레임 `RenderStepped` 를 계속 돌림. 한 명당 아주 작지만 대부분의 접속자가 해당 | 코드 읽기 | `done` 이 되면 루프를 멈추고 `/tutorial reset` 때 다시 켜기 |
| **B-7** | 낮음 (보기) | `PetVisualService.luau` `refreshPens` 2892~2950줄 (`signatureOf` 가 바뀌면 `m:Destroy()` 2915) | 장착 목록이 **조금만 바뀌어도**(펫 1마리 장착·해제) 그 우리 펫 **전부 파괴하고 다시 만들어** 걷던 펫이 모두 격자 자리로 순간이동하고, 최대 18마리 × 45파트를 한꺼번에 만듦(1초에 한 번까지) | `smoke_visuals` 의 "8번 다시 만든 뒤" 검사 | 바뀐 펫만 만들고 지우기(uid 로 비교) |
| **B-8** | 참고 | `BaseService.luau` `hatch`(549)·`pickUpEgg`(517) | 부화·다시 줍기에 **거리 검사가 없음**(맵 끝 구역에서 `HatchEgg` 를 보내도 부화됨 — 확인함). 자기 알이라 이득은 없지만 클라이언트를 고친 사람이 멀리서도 부화 가능 | 임시 스크립트로 확인 | 필요하면 `MapLayout.isInPlot` 확인 한 줄 |
| **B-9** | 참고 | `TutorialService.luau` / `PetService.removePets` | 5단계에서 펫을 **팔면** 그 접속 동안은 5단계 그대로("펫 장착" 인데 펫이 없음, 확인함). 다시 접속하면 `normalize` 가 3/1단계로 되돌림. 알을 더 부화하면 계속할 수 있음 | 임시 스크립트로 확인 | 팔 때도 `normalize` 하거나 그냥 둠 |
| **B-10** | 참고 | `default.project.json` `MaxPlayers 7` / `Config.LEADERBOARD_SIZE 10` | 서버 최대 인원이 7이라 랭킹판이 10줄 찰 일이 없음("10명 넘으면" 규칙은 최대 인원을 늘릴 때만 의미) | 설정 비교 | 그대로 둬도 됨 |
| **B-11** | 참고 (밸런스) | `Pets.luau:260` 지터버그 | 비밀 등급인데 **부화 20초**(비밀은 원래 1.5시간)이고 수입 130M/s. 5판에서 퀘스트가 없어져 누구나 초기화마다 8% 로 마법의 숲에서 훔칠 수 있음 | 코드 읽기 | 의도라면 문서에 적기, 아니면 hours() 로 |
| **B-12** | 참고 | `TutorialService.start` | 중복 시작 방지(`PetVisualService.started` 같은 것)가 없음. 두 번 불러도 `setStep` 이 같은 단계를 무시해서 **해는 없음**(테스트로 확인) | `holes_tutorial` "start 를 두 번 불러도" | 필요 없음 |

**확인했는데 문제 없던 것 (구멍이 없었음)**: 튜토리얼 신호 연결(사람별 연결 없음 → 해제할 것 없음) · 튜토리얼 저장/복원/마이그레이션 · 쓰다듬기 서버 검증 전부(대각선 거리 포함) · 랭킹판 정렬·제외·방송 주기 · 모든 `ToServer` Remote 의 엉터리 인자 · 경비 고정 속도 15구역 · 알 타이머 표시 · 퀘스트 찌꺼기 · 마법의 숲 입구 · 핫바 칸 재사용(State 가 바뀌어도 칸을 다시 안 만듦) · 펫 걷기의 나간 사람 정리·유령 등록·메모리.

### 14-4. 펫 126마리 측정 (Lune, 60fps 기준)

| 항목 | 값 |
|---|---|
| 펫 / 파트 | 126마리, 마리당 평균 45.5 파트 (총 약 5,700 파트) |
| 프레임당 `PivotTo` 호출 | 평균 62.5 (절반쯤 걷는 중) |
| 프레임당 옮긴 파트 | 평균 2,831 → 초당 약 169,900 |
| 메모리(15초 동안) | 앞 7.5초 최대 3,846 KB → 뒤 7.5초 최대 3,697 KB (**계속 늘지 않음**) |
| 장착 바꿔 8번 다시 만든 뒤 | 모델 1,008개가 사라졌고 걷기 등록 유령 0, 살아있는 126마리 모두 등록 |
| 주인 3명 나감 | 126 → 72마리, 나간 사람 펫의 걷기 등록 0 |
| 새 주인 입장 | 다시 18마리 (90마리) |

### 14-5. 스튜디오에서 사장님이 봐 줄 것 (자세한 말은 `docs/STUDIO_CHECKLIST.md` 31~38번)
튜토리얼 5단계($500 한 번), 중간 실수·재접속, 핫바 알 칸("+1")·놓기, 펫 돌아다니기(끊김 여부 — **B-1 확인**), 쓰다듬기(하트·소리·남의 화면), 랭킹판(10초·내 줄 노랑·3D 판 글씨 방향). 개발 명령 `/egg dog`(개 알 3초)·`/tutorial reset`. 또 이전 항목 중 5판과 안 맞던 말(2번 배달 패드, 4번·27번 버튼 수, 14·15번 배달/부화 설명, 30번 소리)도 고쳐 두었습니다.

### 14-6. 아직 못 한 것
- 스튜디오에서 직접 눈으로 보는 것(모양, 소리, 체감 끊김, 폰 화면)은 Lune 으로 못 봄 → 위 체크리스트.
- B-1 의 진짜 숫자(ms, 네트워크 바이트)는 스튜디오 측정 필요.
- `build/StealAnEgg.rbxl` 은 새로 만들지 않음(금지 사항) — 본부장이 `rojo build` 해야 5판이 담김.
## 15. 5판 스튜디오 확인 (본부장, 2026-10-22, 커밋 d19acf9)

| 항목 | 결과 |
|---|---|
| 화면 | ✅ 위 가운데 튜토리얼 "1/5 숲에서 알 훔치기 + 설명", 오른쪽 위 랭킹판(돈/속도 탭, 내 줄), 메뉴 4개(상점·인덱스·슬로우 모드·설정), 퀘스트·선물 버튼 없음 |
| 핫바 알 | ✅ `/egg dog` → 핫바 3번 칸에 알 바로 생김 → 3번 키 → 놓기 모드(초록/빨강 미리보기, "우리 바닥에 마우스를 올려…") → 우리 안 클릭 → 알 놓임, 핫바 칸 사라짐 |
| 개 알 3초 | ✅ 놓자마자 3초 안에 "부화 준비 완료!" → E → "부화!"·NEW! 팝업 |
| 우리 안 펫 | ✅ `/pet chicken 3` → 6초 동안 1.6~6.8 스터드 이동(걷기/쉬기), 쓰다듬기 프롬프트 3개 |
| 튜토리얼 규칙 | ✅ `/egg` 로 받은 알은 1단계(훔치기)를 안 넘김(의도), 튜토리얼 중엔 부화한 펫 자동 장착 안 함(의도) |
| 주의 | 놓기 클릭을 스크립트로 흉내 낼 때 마우스 y 에 GuiInset(58) 더해야 함; 카메라 Scriptable 이면 미리보기가 빨강 |


## 16. 주임 버그 수정 뒤 스튜디오 확인 (본부장, 2026-10-22, 커밋 9065ed9)

| 항목 | 결과 |
|---|---|
| 펫 걷기 20Hz | ✅ 닭 4마리, 6초 동안 13.8 스터드 이동, 0.05초당 최대 0.53 스터드(끊김 없음), 루트 1개만 Anchored + WeldConstraint 35개, 루트만 움직여도 몸 파트 어긋남 0.000 |
| 화면 | ✅ 우리 안에 펫 4마리 흩어져 걷고 수입 팝업(+$9), 헛간·"펫 우리" 아치, 튜토리얼 1/5, 랭킹판 $36 |
| 검사 | selene 0 / stylua 통과 / Lune 461 통과(건너뜀 1 = B-4 NaN 방어, 낮음) / smoke client·visuals OK / 타입 0 |
| 남은 것 | B-4(랭킹 NaN 정렬, 지금은 생길 길 없음)·B-5·B-8~B-12 참고 사항은 그대로. 폰 화면(750×381) 5판 겹침은 Lune 반응형 검사로만 확인 |

## 17. 주임 6판 검수 (주임, 2026-10-28, HEAD e6b03fd 위에서, 아직 커밋 전)

**결론: 심각한 구멍 없음.** 새 Remote 11개(PickFruit·SellFruits·FeedFruit·SkipGrowth·SellPlant·PetPet·SakuraOffer·SakuraDraw·PlaceEgg·PickUpPlacedEgg·ClaimIndexReward)를 코드로 읽고, 무작위 시험으로도 던져 봤는데 코인·가방·남의 것이 뚫리는 곳이 없었어요.

| 한 것 | 결과 |
|---|---|
| 서버 읽기 (FruitService·BaseService 건너뛰기/선물·SakuraService·PetService 팔기/물주기·FruitRules·GardenRules·Wallet·Net·Validate) | 모든 uid·fruitId·"all"/"half" 가 `Validate` 를 거치고, 내 정원 목록(`findPlant`/`findIncubator`)에서만 찾아서 남의 식물·열매는 못 건드림. 건너뛰기 값·팔기 값은 전부 서버가 계산(클라 값은 안 씀). `Wallet` 이 NaN·음수·무한 거부 + 코인 상한. 열매 가방 300은 `addToBag` 가 자리만큼만. 식물당 열매 5는 `FruitRules.produce`. 레이트 리밋은 11개 전부 있음. 밤 30배는 `BaseService.growTick` 한 곳만(열매 틱은 그대로) |
| 무작위 시험 `tests/holes_garden.spec` (새 테스트 2개) | 두 사람(A·B)이 한 서버에서 A 가 온갖 값(남의 uid, NaN, ∞, 1e308, 표, 아주 긴 글, "ALL")을 온갖 자리(정원·가판대·숲·사쿠라 나무 앞/뒤)·낮밤·시간 경과 속에서 1,500번 보냄. 매번 확인: 코인 유한·0 이상·상한 이하 / 열매 가방 ≤ 300·개수 정수·값 유한 / 식물 열매 0~5 정수 / 정원 칸 안 넘음 / uid 겹침 없음 / 크리스탈 정수 / 서버 warn 0 / 돈은 팔기·도감으로만 늘고 건너뛰기는 **정확히 표 가격만큼만** 빠짐 / **멀리서는 따기·팔기·먹이기·물주기·바치기·뽑기가 안 됨** / B 의 코인·열매 가방·씨앗 가방·크리스탈·돌연변이는 그대로. 통과. (시험이 진짜 무는지: `addToBag` 의 300 제한을 일부러 뺐더니 16번째 줄에서 "열매 가방 345" 로 잡힘 → 되돌림) |
| 성장 시간 실측 (새 테스트) | 일반 10초는 10초 뒤 성체. 비밀 `rune_rose` 86,400초: 낮 1시간 = 정확히 3,600 성장초, 건너뛰기 값 = 올림(분) × 10 × 100, 밤으로 바꾸면 남은 시간이 30배 빨리 줄어 약 46분 뒤 성체(전체 밤이면 48분). 성체가 되면 열매 1개 |
| 숫자 대조 (lune) | 건너뛰기 배수 11등급 = SEED 3·11장 (1·2·4·8·15·30·60·100·180·300·500), 11등급 대표 식물 건너뛰기 "전부" 값 = 올림(분) × 10 × 배수 전부 일치. 러닝머신 20레벨 = 정확히 1,000,000/초(걸음 250,000 × 배율 4), 서버 `stepTick` 10초 = 10,000,000 (기존 `services_core`·`design_doc` 이 이미 지킴) |
| 클라 ↔ 서버 (FruitBag·PetFx·PlantFx·Incubator·Pets·Sakura·Hotbar) | 받는 이벤트 이름·필드(plant/isNew/fruitValue/fruitInterval, plantUid/count/value, count/coins, plantUid/mutation, kind/gained/crystals, (ownerUserId, uid))가 REMOTES.md 1장과 같음. 보내는 쪽 인자 순서(`FeedFruit(식물 uid, 열매 식물 id)`, `SkipGrowth(uid, mode)`, `PlaceEgg(uid, x, z)`)도 같음. 읽는 Attribute 전부 서버가 세팅(`VisualHeight` 포함). Connect 누수 없음: 파트마다 거는 것은 `hooked`/`eggPrompts` 표로 한 번만 + `Destroying`/`Parent == nil` 에서 끊음, `Hotbar` 는 `Tracked` 로 끊음, 나머지는 시작할 때 한 번. RenderStepped 는 `IncubatorController` 심기 모드 하나(Instance 안 만듦) |

### 발견 (모두 낮음·참고, 고치지 않음 / 주석 1개만 고침)

| 번호 | 심각도 | 어디 | 내용 · 재현 |
|---|---|---|---|
| C-1 | 낮음 (설계 확인) | `Config.SAKURA_OFFER_CRYSTALS` · `SAKURA_DRAW_COST` | 일반·고급 성체 1그루 = 크리스탈 1, 10개면 코스믹 "벚꽃 요정 나무" 씨앗(97.5%, 열매 60만 코인 · 18초). 숲 강아지풀(3초)을 10그루 키워 바치면 코스믹 씨앗 1개 → 8시간(밤이면 16분) 또는 건너뛰기 288,000 코인이면 성체. 5판 숫자 그대로라 설계 확인만 (사장님이 "너무 쉽다"면 `SAKURA_DRAW_COST` 를 올리거나 낮은 등급 크리스탈 수를 줄이면 됨) |
| C-2 | 참고 | `PetService.luau:262` · `PetFxController.luau:56,260` | 물 쿨다운(서버 `session.cooldowns["water:uid"]`, 클라 `waterUntil[uid]`)이 식물을 팔거나 바친 뒤에도 남음. 한 접속 동안 물 준 uid 수만큼(수십 개)이라 무시 가능 |
| C-3 | 참고 | `PetService.luau:250` | 물 쿨다운이 씨앗과 성체가 같은 uid 라서, 씨앗에 물을 주고 곧 성체가 되면 성체에게 60초 못 줌 (안내 글은 나옴) |
| C-4 | 참고 (성능) | `PlantFxController.luau:107,136` | 0.5초마다 `swayModels()` 가 새 표를 만들고 `GetTagged(ParentAnimal)` 를 부르며, 5초마다 모든 아우라 파트를 `GetDescendants` 로 다시 맞춤. 아우라 파트는 태그된 것만이라 `GetDescendants` 전체 훑기는 아님. 파트가 수백 개여도 가벼움 |
| C-5 | 참고 (표시) | `PetsController.luau:114` · `FruitService` 가판대 배지 | 코인 2배 게임패스가 있으면 "뽑아서 팔기"·"열매 n개 · x 코인" 표시가 실제(×2)의 절반. 서버 지급은 맞음 |
| C-6 | 참고 (주석) | `TreadmillService.luau:8` | 머리말에 "TREADMILL_MULTIPLIER(3)" → 6판 4 로 고침 (코드는 처음부터 `Config` 값 사용) |

### 이번에 추가·고친 것
- 새 파일 `tests/holes_garden.spec.luau` (테스트 2개: 무작위 1,500번 / 성장 시간 실측), `tests/run.luau` 에 등록. 시험 장치 메모: `H.setPhase("Night")` 는 서버가 허브 밖 사람을 베이스로 옮기므로, 거리 시험은 부르기 직전에 `H.spawn`.
- `src/` 는 주석 1줄만.
- 검사: Lune 458 통과 (건너뜀 1 = B-4) / selene 0 / stylua 통과 / smoke client·visuals OK / luau-analyze 타입 0·require 0·lint 0·syntax 0.
- 스튜디오에서 꼭 볼 것: ① 낮에 일반 씨앗을 심어 10초 뒤 성체가 되는지 + 밤에 비밀 씨앗이 훨씬 빨리 크는지(씨앗 위 숫자가 1초에 30씩 줄어듦) ② 정원에서 멀리 서서 "열매 따기"·"물 주기"가 안 되는지(걸어가면 됨) ③ 판매 가판대에서 열매 팔기 → 코인 팝업 + 튜토리얼 5단계 완료, 건너뛰기 창의 가격이 눌렀을 때 낮아진 코인과 같은지.

## 18. 6판 스튜디오 확인 (본부장, 2026-10-28, 커밋 2319609)

빌드 `build/StealAnEgg.rbxl`, 스튜디오 플레이(서버·클라 1명). 출력 창 오류 0. 개발 명령 `/coins` `/plant` `/fruit` `/seed` 동작.

| # | 확인 | 결과 |
|---|---|---|
| 1 | 일반 씨앗(아기 데이지, 10초) 심기 → 단계 | sprout 0.5s → stem 2.6s → bud 5.7s → adult 9.7s (설계 0/25/60/100%) ✅ |
| 2 | 정원에서 22스터드 밖에서 `PickFruit` | 열매 가방 0 → 0, 막힘 ✅ / 정원 안에서는 1개 땀, 식물 Fruits 1 → 0 ✅ |
| 3 | 건너뛰기 `SkipGrowth(i3, "all")` 파라오 야자(에픽 16분) | 화면 가격 `GardenRules.skipCost` 1,280 = 실제 빠진 코인 1,280, 바로 성체 ✅ |
| 4 | 판매 가판대(허브 60,−232)에서 `SellFruits` | 열매 1개 값 7,200 → 코인 +7,200, 가방 0 ✅ |
| 5 | 모양 | 별 버섯(금빛 고리 아우라, 열매 2/5 이름표), 숲 경비 "덥석 파리지옥"(자는 Z), HUD "100K 코인"·열매 20/300·핫바 씨앗 칸 ✅ |

안 본 것: 튜토리얼 5단계 완료 연출, 사쿠라 창, 러닝머신 11~20레벨 모양, 폰 화면 (체크리스트 10~15번) — 다음 세션.

## 19. 사장님 수정 3건 + 공중부양 식물 (본부장, 2026-10-28)

| # | 바뀐 것 | 확인 |
|---|---|---|
| 1 | 자라는 씨앗 물 주기 없앰 (성체만 F "물 주기") | 서버 PetPet 씨앗 uid 조용히 거절(테스트 social/holes_social), 클라 씨앗에 WaterPrompt 없음(smoke, 스튜디오 false) ✅ |
| 2 | 열매 1.8배 빨리 (`Config.FRUIT_SPEED_MULTIPLIER`) | 아기 데이지 30초 → 스튜디오 FruitInterval 16.67 ✅ |
| 3 | 초반 코인 2배 (`Config.EARLY_COIN_MULTIPLIER` 일반·고급 열매 값 ×2) | 아기 데이지 열매 값 10 → 20, 성체 팔기 400 ✅ |
| 4 | **공중부양 나무**: `MapBuilder.groundY` 광선이 심는 사람 캐릭터(발 0.96·다리 2.14·머리 4.97)에 맞아 그 높이에 심김 | 캐릭터 제외 + 정원 바닥은 FLOOR_Y+2 로 상한. 씨앗 자리에 서서 심어도 바닥 0.00 ✅ (사장님 세션의 떠 있는 식물은 새 빌드로 다시 열면 바닥으로) |

검사: 테스트 458 통과, smoke client/visuals OK, selene/stylua/luau-analyze 0.

### 19-2. 트레일 상점 "안 사진다" (2026-10-28)
- 원인: 트레일 상점 창 높이 470 이 카드(330 + 버튼 52) 보다 짧아 **사기 버튼이 창 밖으로 잘려** 안 보임 (서버·Remote 는 정상 — 직접 보내면 삼).
- 수정: 창 860×560. 스튜디오: 상점 → 트레일 탭 → 초록 5K 사기 → 코인 100,000 → 95,000, 속도 20 → 40(×2), 버튼 "장착 해제" ✅
