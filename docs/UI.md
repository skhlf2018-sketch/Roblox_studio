# 화면·소리·생김새 (UI.md)

작성: 선임, 2026-10-18 · **5차 전면 갱신 (2판, 원작 스타일)** — 맵을 한 줄 복도로, 베이스·펫·경비·알을 원작 블록 스타일로, HUD·창을 원작 화면 그대로 다시 만듦.
(1~4차 기록은 git 이력에.) 게임이 **보이고 들리게** 만드는 부분을 정리한 문서입니다.
외부 에셋(메시·이미지·소리)을 올릴 계정이 없어서 **모든 모양은 기본 도형**(Block/Ball/Cylinder/Wedge + SpecialMesh)과 **UI 기본 요소(Frame)**로 코드에서 만듭니다.
원작 느낌의 핵심 = **Plastic 재질 + 표면 스터드(SurfaceType.Studs)** + 두 가지 색 체크무늬 + 굵은 검은 외곽선 글씨.
원작 스크린샷 46장(본부장 촬영)을 보고 맞췄습니다. 배치 숫자는 전부 수석의 `src/shared/Data/MapLayout.luau`.

---

## 1. 파일 목록

### 데이터 (shared)
| 파일 | 내용 |
|---|---|
| `src/shared/Data/Visuals.luau` | 펫 134종 + 경비 전용 생김새, **구역 15개 테마(2판: 바닥 두 색·담장 색·담장 위 띠·네온 줄·배너 이모지 `label`·천사&악마 오른쪽 지옥 `rightSide`)**, 희귀도/돌연변이 효과, 경비 크기(`height` 25~40), **베이스 울타리 색(`plotColors`)**, 연출용 태그(`UpgradeSign` 추가) |
| `src/shared/Data/Sounds.luau` | 소리 이름 → `rbxassetid://0` 자리 + 설명 (5장) |

### 서버 (모두가 같은 모양)
| 파일 | 내용 |
|---|---|
| `src/server/Services/MapBuilder.luau` | 2판 맵 전체 (2장) + 태그 색인 + 베이스 표지판·러닝머신 모양 갱신. 서버가 부르는 함수(start·getFolder·getNests·groundY·setNightWalls·setPlotOwner·plotCount) 유지, 나머지(getZone·isInPlot 등)도 MapLayout 기준으로 남겨 둠 |
| `src/server/Services/PetVisualService.luau` | 펫 블록 모델(체형 17종, 평균 45파트), 부모 동물(구역마다 2), 우리 진열(격자, 앞을 봄, 이름표 3줄), 거대 경비(25~40스터드, 잠자기/추격 자세 + Z), `ReplicatedStorage.PetModels` 도서관 |
| `src/server/Services/EggVisualService.luau` | 계단형 블록 알(6층, 줄무늬·점), 희귀도 빛, 돌연변이, 특별 알 빛기둥, 들고 있을 때 무게 "♂ 4,740Kg" |
| `src/server/Util/Gui.luau` | 월드 글자 도우미(billboard·surface·sign·tag) — 그대로 |

### 클라 (내 화면)
| 파일 | 내용 |
|---|---|
| `src/client/Main.client.luau` | 진입점. 컨트롤러를 하나씩 따로 시작 (2판: `TreadmillController`, `TrailController` 추가) |
| `src/client/Net.luau` | + `Net.onLater(name, fn)` (기다리는 동안 부른 쪽을 안 멈춤) · `Net.trySend(name, ...)` (없으면 조용히 버림) |
| `UI/Theme.luau` | 색 — 2판 원작 색 추가: `win`/`winDark`/`winEdge`(진한 창), `shopGreen`·`indexCyan`·`trailPurple`·`eggRed`·`pawOrange`·`speedRed`·`moneyGreen`·`runRed` |
| `UI/Ui.luau` | 창 = **진한 회남색 + 두꺼운 검은 테두리 + 줄무늬 제목 띠(`Ui.stripes`) + 빨간 네모 X**. 버튼 모서리 10 |
| `UI/Icons.luau` | **새 파일.** HUD 그림을 Frame 으로: cart·book·egg·paw·shoe·money·moon·sun·trash·star·lock·gear·gift·scroll·sell·trail |
| `UI/Layout.luau` | 반응형 자리 계산. `Layout.menu(..., topLimit, bottomOverride)` 추가, 핫바 칸 64(원작처럼 작게) |
| `UI/Windows.luau`, `UI/PetViewport.luau`, `UI/PetPicker.luau`, `UI/WorldPrompt.luau`, `UI/Fx.luau` | 그대로 (PetPicker 글자색만 진한 창에 맞춤) |
| `Controllers/HudController.luau` | **다시 씀.** 3장 HUD 전부 + 슬로우 모드 |
| `Controllers/ChaseController.luau` | **다시 씀.** "달리기!!" 배너·빨간 비네트·드롭 버튼, 잡힘 연출 |
| `Controllers/IncubatorController.luau` | **다시 씀.** "성장하는 달걀" 패널 + 우리 안 알 "에그 / 1m 52s" + "부화!" 프롬프트 |
| `Controllers/TreadmillController.luau` | **새 파일.** 러닝머신 위에선 이동 입력 끄기, 점프 → `TreadmillLeave`, "+500" 분홍 팝업 |
| `Controllers/TrailController.luau` | **새 파일.** 트레일 상점 창 + 허브 가게 프롬프트 |
| `Controllers/IndexController.luau` | **다시 씀.** 원작 "펫 인덱스" 창 |
| `Controllers/ShopController.luau` | **다시 씀.** 원작 초록 상점 창 + 오른쪽 세로 탭 + 베이스 업그레이드 표지판 프롬프트 |
| `Controllers/PetsController.luau` | 진한 카드 + **판매 버튼**(판매 가게 근처) + 판매 가게 프롬프트 |
| `Controllers/HotbarController.luau` | 아래 가운데 작은 어두운 칸 + 알 칸 |
| `Controllers/NotifyController.luau` | 원작 글씨 토스트("에그를 훔쳤어요!")·공지(색 조각 RichText) |
| `Controllers/WorldFxController.luau` | + 펫 돈 팝업 "+$34K"(IncomeTick), 자는 경비 Z 둥실둥실, 배달 반짝은 내 베이스 스폰 자리 |
| `Controllers/ZoneController.luau` | 구역 = `CurrentZone` Attribute 또는 `MapLayout.zoneAt(z)` ("hub" → "base") |
| 나머지 (Gift·Settings·Hatch·Fusion·Sakura·Altar·Quest·Weapon·Sound·Lighting·Debug 등) | 그대로 (새 창 스타일만 자동 적용) |

---

## 2. 맵 배치 (MapBuilder, 2판)

```
            +Z (멀리)
  z=3600 ── 끝 벽 ─────────────────────────────
           15 유령 성 … 2 호수 (구역마다 240, 벽·문 없음, 경계에 베이지 모래띠)
  z=0    ── "안전 구역" 검은 글씨 + 빨간 점선 + 밤 벽(NightWall 1장) ──
           [1]  허브(안전 구역, 잔디 스터드)  [2]      베이스: 왼쪽 x=-75 (1·3·5·7), 오른쪽 x=+75 (2·4·6)
           [3]       기본 스폰(0,-140)      [4]      z = -40 / -110 / -180 / -250
           [5]                              [6]
           [7]               판매 가게 · 트레일 상점 · 이벤트 포털 (오른쪽 z≈-250)
  z=-290 ── 허브 뒤 흰 벽 (구름 + 달 그림) ──
             x = -110 ……… 0 ……… +110   (양옆 담장 높이 60, 체크무늬 스터드)
```
- **바닥**: 구역마다 20×20 칸 체크무늬(`floor`/`floor2`, Plastic + 스터드). 천사&악마는 왼쪽 흰금(천국) / 오른쪽 검붉(지옥).
- **담장**: 30×30 칸 체크무늬, 구역 색(숲~눈 황토, 사막 노랑, 화산 검정+주황 네온 줄, 심연 남색, 코스믹 검정+흰 네온 별 …). 숲·호수 등은 담장 위 초록 띠(`wallCap`). 구역 시작 쪽 담장 위에 이름판 "숲 🙂 / 추천 속도 10".
- **구역 장식**: 담장 쪽 띠(|x| ≥ 89)에만, 둥지·부모 동물·특수 장소를 피해서. 가운데는 비움(경비가 직선으로 쫓아옴).
  2판 새 블록 장식: `blockytree`, `bushblock`, `chick`, `duck`, `swan`, `cactusblock`, `blockypalm`, `icecrystal`(눈: 하늘색 블록 결정), `bigbone`, `coralblock` + 특수 처리 `lakewater`(호수 큰 물), `sandedge`(심연 모래 테두리), `lavawall`(화산 담장 용암 줄), `wallstars`(코스믹 담장 별).
- **둥지**: `MapLayout.nestsFor` 자리 8개. 건초 링(막대 10개) / 선사시대 통나무·뼈 큰 둥지 / 코스믹 작은 둥근 그릇 / 눈 덮인 둥지 / 심연 조개 둥지. `Nest` 태그 파트(원기둥)는 1판과 같은 크기라 서버가 알을 그 위에 놓음.
- **경비 집**: 구역 가운데(`guardHome`) 살짝 어두운 둥근 자국 + `GuardSpawn` 파트(표시용).
- **부모 동물 자리**: 1번·8번 둥지 옆 담장 쪽 2곳 (`ParentAnimalSpot`).
- **특수 장소**: `MapLayout.specials` 자리 — 사쿠라 인큐베이터(벚꽃 왼쪽), 천국/지옥 제단(천사&악마 x=∓55), 비밀 통로+폭포(왼쪽 담장), 퀘스트 문+비밀 정원(마법의 숲 왼쪽).
- **허브**: 잔디 체크무늬, 양옆 황토 담장, 뒤 흰 벽 + 구름·달 그림 2개, z=0 "안전 구역" 글씨·빨간 점선·파란 반원, 판매 가게(빨강·흰 천막 + "판매" + 청록 링, `SellStall`), 트레일 상점(천막 + "트레일 상점", `TrailShop`), 이벤트 포털(검붉은 바위 아치 + 주황 소용돌이, "HALLOWEEN DIMENSION / 오픈"), 기본 스폰, 인덱스 보드.
- **베이스(7개)** — `MapLayout.plot(i)`:
  - 우리(뒤 46, `PenArea` 파트가 우리 전체를 덮고 LookVector = 복도 쪽) + 앞마당(24).
  - **나무 X자 울타리**: 검은 기둥(10 간격) + 위·아래 가로대 + X 보강재, 가로대 색 = `Visuals.plotColors[i]`(갈색·흰·노랑·하늘·분홍·연두·보라). 우리 앞 가운데 12 출입구.
  - 우리 안 앞쪽 부화 알 받침 8개(`IncubatorSlot`, `MapLayout.incubatorSpots`), 펫은 뒤쪽(`petRect`).
  - 앞마당: 스폰(흰 원), **러닝머신**(벨트 = `Treadmill` 태그, `treadmillRect` 12×8, 윗면 = 바닥+1, Attr `Level`), **퓨즈 머신**(파란 기계 + "?" 화면(`Core`) + 별 패널 + 빨간 표시등 `Tube1~3` + 청록 링 + "퓨즈 머신 / 0/3" 빌보드 `FuseLabel`), **판매 가게**(작은 천막, `SellStall` + `PlotIndex`), 업그레이드 표지판 2개(남색 판 "펫 우리 업그레이드 / 레벨 5 > 레벨 6 / [$50B]", "러닝머신 업그레이드 …", `UpgradeSign` 태그 + Attr `Kind`/`PlotIndex`), 주인 이름 간판(`PlotSign`), 러닝머신 위 "+100/스텝" 분홍 빌보드.
  - 표지판 숫자·러닝머신 모양은 주인 Attribute `PenLevel`/`TreadmillLevel` 이 바뀔 때마다 갱신 (`Economy.nextPenCost`/`nextTreadmillCost`/`treadmillPerStep`).
- **러닝머신 모양 10단계**(`TREAD_STYLES`): 1 기본(회색 벨트) · 2 사이파이(흰 틀 + 청록 네온) · 3 불꽃(검붉은 틀 + 화로 불) · 4 셀럽(레드카펫 + 금 기둥·벨벳 줄) · 5 황금(반짝) · 6 얼음(파란 틀 + 하늘색 얼음 결정, 원작 사진) · 7 럭키블록("?" 노란 블록) · 8 해커(검정 + 초록 네온 모니터) · 9 악마(뿔 + 붉은 불) · 10 천사(날개 + 금 링). 레벨 0(잠김) = 기본 모양 반투명 + "잠김 ($1K)".
- **파트 수**: 맵 약 7,650개 (구역 6,200 · 베이스 1,110 · 허브 310), 한 변 2048 넘는 파트 없음. 구역·베이스마다 `task.wait()`.

### 2-1. 클라 이름 규칙 (연출이 찾는 이름 — 모델을 바꿀 때 유지)
| 이름 | 쓰는 곳 |
|---|---|
| 퓨즈 머신 모델 `Core`, `Tube1~3` | FusionController 번쩍임 |
| `Treadmill` 태그 Attr `Level`, 형제 모델 `TreadmillLook` | (표시) |
| `UpgradeSign` 태그 (Visuals.Tags) Attr `Kind`·`PlotIndex` | ShopController "업그레이드" 프롬프트 |
| `SellStall` 태그 (허브 1 + 베이스 7) | PetsController "펫 팔기" 프롬프트·판매 버튼 거리 |
| `TrailShop` 태그 (허브) | TrailController "열기" 프롬프트 |
| `PlotSpawn` 태그 | WorldFx 배달 반짝 |
| 경비 겉모습 `SleepZ` 빌보드(`Z1~Z3`), `GuardPose` 용접, `GuardGlow` | WorldFx Z 둥실둥실 |
| 우리 펫 `PetUid` Attr + `PenPet` 태그, 빌보드 `PetTag`(`Rarity`/`PetName`/`Income`/`Extra`) | WorldFx 돈 팝업·통통 |
| 알 `EggVisual` 폴더(`Layer`·`Spot1~2`), 빌보드 `WeightTag`(`Gender`/`Kg`) | WorldFx 레인보우 순환 |
| 부화 중 알 빌보드 `GrowTag`(`Title`/`Time`), 프롬프트 `HatchPrompt` (클라가 붙임) | IncubatorController |

---

## 3. 동물·알 생김새

### 펫 (PetVisualService)
- 모든 큰 타원체·공·굵은 원기둥 → **모서리 깎인 블록(직육면체 3개 겹침)**, 넓은 면 스터드, 기본 Plastic. 눈 = 검은 네모 + 흰 하이라이트.
- 체형 17종(quad·bird·fish·snake·bug·spider·dragon·ghost·humanoid·frog·turtle·whale·jelly·lizard·blob·dino·penguin)을 블록 디테일로 보강 → **134종 평균 44.6 파트(최소 31, 최대 73)**.
- 희귀도 외곽 빛(Highlight, 전설 금 · 신화 빨강 · 코스믹 보라 …) + 전설 이상 반짝이.
- **우리 진열**: `PenArea` 사각형 뒤쪽 2/3 에 격자(앞줄부터), 모두 앞(복도)을 봄. 머리 위 3줄 **[희귀도 색 글씨] / 이름 / $수입/s** (+크기·돌연변이 한 줄).
- **경비**: 높이 25~40 스터드(캐릭터 5~8배). `State = "Sleeping"`(또는 Idle) 이면 엎드린 자세 + 머리 위 파란 "Z" 세 개, `"Chase"` 면 일어서고 빨간 테두리.

### 알 (EggVisualService)
- 계단형 블록 달걀 6층(아래 넓게, 위 좁게) + 둘째 색 줄무늬 2층 + 점 2개, 윗면 스터드.
- 돌연변이(실버/골든/레인보우/블룸), 특별 알(비밀/영원/신성) 하늘 빛기둥 + "비밀 알!" 이름표, 전설 이상 빛.
- 들고 있을 때(`EggState = "Carried"`) 알 위 **"♂ 4,740Kg"** (알 `WeightKg`, 없으면 들고 있는 사람 `CarryWeightKg`).

---

## 4. 화면 (원작 Steal An Egg HUD 그대로)

```
 ┌─────────────────────────────────────────────────────────────────┐
 │                  [ 달리기!! ]   ← 알 들었을 때 (빨간 배너 + 빨간 비네트)
 │                  Jungle 😬      ← 구역 배너 (ZoneEntered)
 │                  Jungle에 비밀 킹 스네이크 에그 등장!  ← 공지
 │ [🛒 상점    ]                                             [🥚]① │
 │ [📘 인덱스  ]                                             [🐾]  │
 │ [ (퀘스트)  ]        성장하는 달걀 패널 (알 버튼으로 열기) →      │
 │ [ (선물)    ]                                                   │
 │ [■ 슬로우 모드]                                                 │
 │ [⚙ 설정     ]                                                   │
 │ 👟 5.7M         (빨강)               에그를 훔쳤어요!            │
 │ 💵 $18.7B       (초록)               [ 🗑 드롭 ]                │
 │ 친구 부스트: +10%            [1 방망이][2 곰덫 x3][3 알]   🌙 3분 58초 │
 └─────────────────────────────────────────────────────────────────┘
```
| 화면 | 파일 | 데이터 |
|---|---|---|
| 왼쪽 메뉴 (넓은 버튼: 아이콘 + 글자) | HudController | 상점 → Shop 창, 인덱스 → Index 창(배지 = 받을 보상 수), 퀘스트(QuestController 가 `addMenuButton`), 선물(받을 게 있을 때만), 슬로우 모드, 설정 |
| 슬로우 모드 | HudController | 켜면 `Humanoid.WalkSpeed` = 플레이어 Attr `WalkSpeed` ÷ 2 (서버가 속도를 바꿔도 다시 절반으로). 느려지기만 하므로 치트 검사와 충돌 없음 |
| 왼쪽 아래 속도·돈·친구 부스트 | HudController | Attr `Speed`(빨강), `Money`(초록, 숫자 올라가는 애니메이션). "친구 부스트" 는 장식 |
| 오른쪽 알 버튼 / 발바닥 버튼 | HudController + IncubatorController | 알 → "성장하는 달걀" 패널 열고 닫기, 초록 배지 = 지금 부화 가능 수. 발바닥 → Pets 창 |
| 오른쪽 아래 시간 | HudController | GameState `Phase`/`PhaseEndsAt`. 낮엔 달 그림(밤까지), 밤엔 해 그림(낮까지). "3분 58초" / 1분 아래는 "52초 안에" |
| 구역 배너 | HudController | `ZoneEntered{nameEn}` + 테마 `label` 이모지 ("Jungle 😬"), 2.6초 |
| 공지 | NotifyController | `Announce` — 희귀 알은 `rareEggText`: 구역(초록) + 희귀도(색) + 알 이름(금) "에그 등장!" |
| 토스트 | NotifyController | `Notify`, `EggDelivered` → "에그를 훔쳤어요!" (바탕 없는 굵은 외곽선 글씨) |
| 달리기!! | ChaseController | Attr `CarryingEgg` ≠ "" 동안 배너 + 비네트(맥박) + 드롭 버튼(`DropEgg`). `RunAlert` 속도 부족 경고, `ChaseEnded.reason` 안내, 허브에선 "베이스로!" |
| 잡힘 | ChaseController | `Caught` → "잡혔다!" + 화면 흔들림 + 빨간 번쩍 |
| 성장하는 달걀 패널 | IncubatorController | 줄: 알 그림 + 초록 막대 + "5m 25s" + ▶(다 자랐으면 `HatchEgg`, 아니면 안내). "모두 성장시키기"(로벅스)는 꺼 둠 |
| 우리 안 알 이름표·부화 | IncubatorController | `IncubatingEgg` 위 "에그 / 1m 52s" → 다 자라면 "부화!" + 내 알에만 프롬프트(E) → `HatchEgg(uid)` |
| 러닝머신 | TreadmillController | Attr `OnTreadmill` 동안 이동 입력 끔 + "점프하면 내려와요"(터치 "내리기" 버튼). 점프 → `TreadmillLeave`. `TreadmillStep{amount}` → 분홍 "+500" |
| 돈 팝업 | WorldFxController | `IncomeTick{petUid, amount}` → 그 펫 위 큰 초록 "+$34K" 떠오름 |
| 핫바 | HotbarController | PC 아래 가운데, 작은 어두운 칸(번호·그림·"x3"), 알 들면 마지막 칸에 알 |

### 창 (진한 창 + 줄무늬 제목 + 빨간 X)
- **펫 인덱스**(하늘): 왼쪽 구역 그림 탭 15개(받을 보상 "!") · 가운데 희귀도 색 카드(미발견 검은 실루엣 "???") + 진행바 "1/8" · 오른쪽 큰 펫 + 이름/희귀도/수입 + 빨간 ">" + 보상(돈·속도) + **획득!** · 아래 **모두 획득 (n)!** 또는 "잠금 해제: n/134" · 창 밖 **월드** 버튼(준비 중 안내).
- **상점**(초록): 카드 2장(펫 우리 / 러닝머신 업그레이드, 다음 러닝머신 모양 이름·스텝당 속도) + 창 밖 오른쪽 세로 탭(업그레이드·트레일·추천·속도·돈). 로벅스 탭은 "준비 중"(살 수 없음).
- **트레일 상점**(보라): 가로로 넘기는 카드 11장 — 이름·등급·캐릭터 그림·"x4 스피드" 배지·버튼: 안 가짐 = 가격(초록, `PurchaseUpgrade("Trail", id)`, 산 뒤 서버가 자동 장착) / 가졌음 = "장착"(파랑, `EquipTrail(id)`) / 장착 중(`snap.equippedTrail`, 없으면 Attr `EquippedTrail`) = "장착 해제"(노랑, `EquipTrail("none")`). `DataUpdate("upgrades")`·Attr 바뀌면 카드 다시 그림. 캐릭터 꾸밈: 모든 플레이어 HumanoidRootPart 에 `EquippedTrailFx` Trail(Attr `EquippedTrail` 색, "none" 이면 지움).
- **펫**(주황): 진한 카드, 장착/해제, 최고 펫 장착, **판매 가게 근처면 "판매 $가격"**(`SellPet`, 가격 = 수입 × 60초).
- 선물·설정·펫 고르기·부화 카드는 그대로(새 창 스타일만).

### 4-1. 펫 고르기 창 (`UI/PetPicker.luau`)
```lua
PetPicker.open({
	title = "퓨전 머신", color = Theme.Colors.purple, hint = "같은 펫 3마리를 골라요",
	count = 3,                                   -- 정확히 이만큼 고르면 확인 버튼 켜짐
	items = function() return PetPicker.myPets() end,  -- 생략 = 내 보관함 펫 전부 (myEggs() = 부화 중 알)
	filters = { PetPicker.sameSpecies(3) },      -- 아래 필터 버튼 ("같은 펫만" / PetPicker.sameSide(side) "같은 쪽만" / 직접)
	check = function(item, selected) return ok, "이유" end,   -- 못 고르는 카드 = 회색 + 빨간 이유
	ready = function(selected) return ok, "이유" end,          -- 확인 버튼 조건 (이유는 안내 줄에 빨갛게)
	status = function(selected) return "안내" end,             -- 고른 것에 따라 안내 줄
	onConfirm = function(selected) Net.send(...) end,
	closeWhen = function() return 멀어짐 end,    -- 0.5초마다 확인, true 면 닫힘
})
```
- 카드 132×178: 희귀도 색 테두리, 3D 펫(알은 알 모양), 이름(희귀도 색)·희귀도·수입·크기/돌연변이 또는 이유, "장착" 표시. 카드 전체가 버튼. 고르면 노란 두꺼운 테두리 + 순서 번호.
- 정렬: 고를 수 있는 것 → 희귀도 높은 순 → 같은 펫끼리 → 수입. 한 쪽 24장.
- 아래 막대: 필터 버튼 · "고름 2/3" · 취소 · 확인. 위 줄: 안내 · `<` 쪽 `>`. 버튼은 전부 `Ui.touch` 로 **폰에서도 46px 이상**.
- 창은 Windows 에 "PetPicker" 로 등록(한 번에 하나, ESC 로 닫힘). 확인을 누르면 닫고 요청만 보냄 — 결과는 서버 이벤트로 옴.
- State 가 바뀌면 다시 그림 (팔리거나 퓨전된 펫은 선택에서 빠짐).

조명: 낮 14시 밝고 따뜻하게 → 밤 22시 어둡고 파랗게 → 새벽 5시半 → 낮 (시계는 앞으로만 2.5초 Tween). 구역마다 안개 색(유령 성 보랏빛 짙게, 화산 주황, 바다 파랑, 눈 하양 …), 밤엔 더 어둡게.


### 4-2. 반응형 HUD (`UI/Layout.luau`)
- **PC**: 왼쪽 메뉴 = 넓은 1열 버튼(150 × 52 기준), 속도·돈 묶음(왼쪽 아래) 위쪽 공간 가운데쯤. 핫바 아래 가운데. 시간 오른쪽 아래.
- **터치(폰)**: 속도·돈을 **화면 위 왼쪽 한 줄**로 올리고(친구 부스트 숨김), 시간은 **오른쪽 위**로 (점프 버튼 자리 비움). 메뉴는 `Layout.menu(area, n, scale, touch, nil, topLimit = 속도·돈 아래, …)` 로 조이스틱 위까지, 버튼 44px 이상, 모자라면 2~3열 **정사각 아이콘 버튼**(작은 글자). 핫바는 점프 버튼 왼쪽.
- 창 버튼(닫기 X·획득!·사기·장착·판매·탭)은 `Ui.touch` 로 폰에서도 46px 이상.
- 측정 (스모크): 750×381 폰 = 메뉴 2열 45px, 844×390 = 2열 48px, 1428×750 PC = 1열 53px 높이, 핫바 칸 44.8~66.7px.

## 5. 소리 — 사장님이 채울 ID 목록 (`src/shared/Data/Sounds.luau`)

ID 가 `rbxassetid://0` 이면 조용히 건너뜁니다. Creator Store → 오디오에서 고른 뒤 숫자만 바꾸세요. (예: `id = "rbxassetid://1234567890"`)

| 이름 | 소리 | 언제 |
|---|---|---|
| `Click` | 버튼 클릭 '톡' | 모든 버튼 |
| `Open` / `Close` | 창 열림 '뿅' / 닫힘 '슉' | 창 |
| `Pickup` | 알 줍기 '퐁!' | `RunAlert` |
| `RunAlert` | 사이렌 한 번 | `RunAlert` |
| `Chase` (음악) | 추격 긴장 음악 | 알 들고 있는 동안 (배경음 대신) |
| `Caught` | '퍽! + 휘익' | 잡힘/맞음 |
| `Trap` | 곰덫 '철컥!' | 곰덫 밟음 |
| `Bat` | 방망이 '붕' | (예비) |
| `Deliver` | 배달 성공 '띠링~' | `EggDelivered` |
| `HatchReady` | 다 자람 반짝 | (예비) |
| `Hatch` / `HatchRare` | 부화 '빠직+반짝' / 희귀(전설 이상) 팡파레 | `HatchResult` |
| `Fusion` | 퓨전 '윙윙~ 펑!' | `FusionResult` |
| `Coin` | 돈 '짤랑' (아주 작게, 2초에 한 번까지) | 돈이 늘 때 |
| `Purchase` | 구매 '차링!' | 성공 알림 |
| `Error` | '뿡' | 실패 알림 |
| `Notify` | '띵' | 안내 알림 |
| `Reward` | 보상 반짝 상승음 | 도감/무료 보상 |
| `NightBell` | 밤 종소리 '댕~' | 밤 공지 |
| `DayStart` | 아침 차임 | 낮 공지 |
| `Reset` | '휘리릭' | ALL EGG RESET |
| `RareEgg` | 희귀 알 팡파레 | 희귀 알 공지 |
| `Offline` | 돈 쏟아지는 소리 | 오프라인 수입 팝업 |
| `Equip` | '뾱' | 장착 버튼 |
| `Drop` (2판) | 알 내려놓기 '툭' | 드롭 버튼 |
| `ZoneEnter` (2판) | 새 구역 '휙+짠' | 구역 배너 ("Jungle 😬") |
| `TreadmillStep` (2판) | 러닝머신 걸음 '탁' (작게) | `TreadmillStep` "+500" 팝업 |
| `Sell` (2판) | 펫 판매 '짤랑짤랑' | 펫 창 판매 버튼 |
| `Swing` (2차) | 무기 휘두르기 '휙!' | 손 모양 휘두를 때 (쿨다운마다 한 번) |
| `FusionCharge` (2차) | 퓨전 빛 모으기 '우우웅~' | `FusionResult` 직후 (`Fusion` '펑!' 은 1.2초 뒤) |
| `Bloom` / `SpiritBloom` (2차) | 꽃잎 반짝 / 신비로운 합창 | `SakuraResult` 블룸 / 스피릿 블룸 |
| `Unlock` (2차) | 철컥 + 반짝 | 사쿠라 인큐베이터 해금 |
| `AltarOffer` / `AltarPaired` (2차) | 낮은 종 '웅~' / 천사 합창 + 쿵! | 제물 바치기 / 짝 성공 |
| `Shrine` (2차) | 마법진 '위잉~ 쾅!' | `ShrineResult` |
| `QuestStep` / `GateOpen` (2차) | 딩동! / 큰 문 열리는 소리 | 퀘스트 하나 완료 / 퀘스트 문 열림 |
| `Bgm_base` (음악) | 밝고 신나는 음악 | 베이스·광장·길 |
| `Bgm_forest` … `Bgm_haunted_castle` (음악 15개) | 구역 분위기 (Sounds.luau 설명 참고) | 그 구역에 들어가면 부드럽게 바뀜 |

---


## 6. 스튜디오에서 꼭 볼 것 (체크리스트, 2판)

1. **복도 전체**: 허브에서 +Z 쪽을 보면 담장·체크무늬 바닥이 원작처럼 이어지는지, 구역 경계 모래띠, 담장 위 초록 띠. 스터드가 보이는지(Plastic + Studs). 너무 어둡거나 안개가 짙지 않은지(구역 Atmosphere 를 0.2~0.3 으로 낮춤).
2. **"안전 구역" 글씨 방향**: z=0 바닥 글씨가 허브에서 복도를 볼 때 똑바로 읽히는지 (SurfaceGui Top 면 + Y 180도 회전 — 거꾸로면 `SafeZoneText` 회전만 0 으로).
3. **베이스**: 울타리 X자 보강재 각도, 출입구, 업그레이드 표지판 글씨 방향(복도 쪽에서 읽힘), 판매 가게·주인 간판·러닝머신·퓨즈 머신이 서로 안 겹치는지. 러닝머신 레벨 1~10 모양(`/` 명령이나 DevCommands 로 레벨 올려 보기).
4. **구역 장식**: 둥지·경비 길을 막지 않는지, 담장 쪽에만 있는지. 호수 물·심연 모래 테두리·화산 용암 줄·코스믹 별.
5. **펫·경비·알**: 펫 블록 모양이 또렷한지, 우리 격자 진열·이름표 3줄, 거대 경비(25~40) 발이 땅에 닿는지·자는 자세·Z, 계단형 알과 "♂ 4,740Kg".
6. **HUD**: 원작 사진과 나란히 — 왼쪽 버튼, 왼쪽 아래 숫자 크기·색, 오른쪽 알/발바닥 버튼, 오른쪽 아래 시간, 알 들 때 "달리기!!" + 비네트 + 드롭, 구역 배너, "+$34K", "+500".
7. **폰 에뮬레이터**(844×390, 750×381): 메뉴가 조이스틱과 안 겹치는지, 위 한 줄 속도·돈, 오른쪽 위 시간, 핫바·드롭 버튼·러닝머신 "내리기".
8. **슬로우 모드**: 켜면 걷기가 절반, 끄면 원래. 러닝머신에서 WASD 안 먹고 점프로 내려오는지.
9. 출력 창에 `[Net] Remote 아직 없음` / 빨간 오류가 없는지.

## 7. 알려진 한계 / 다음 할 일
- ~~트레일 장착/장착 해제~~ — 됨 (2판 마무리, `EquipTrail`).
- 리더보드(이름 / Money/s / 속도)는 서버 leaderstats(수석) — 화면은 로블록스 기본 리더보드.
- 로벅스 상품·"모두 성장시키기"·"월드" 버튼은 준비 중(꺼 둠).
- 러닝머신 위 제자리 달리기 애니메이션(캐릭터 고정·발 움직임)은 서버 TreadmillService 담당 — 클라는 입력만 끔.
- 구역 장식·펫 모양은 Lune 에서 만들어지는 것까지만 확인 → 스튜디오에서 모양 확인 필요(6장).
- 경비 이름표(GuardianService, 수석)가 머리 3스터드 위라 거대 경비 몸 안에 묻힐 수 있음 → 겉모습 `Height` 위로 올려야 함.

## 8. 스모크 테스트 (Lune, 스튜디오 없이)

저장소 루트에서 (정식 테스트 `tests/run.luau` 에는 안 들어감):
```powershell
lune run tests/smoke_visuals.luau   # 서버: 2판 맵(구역 15 = MapLayout z 범위, 둥지 자리, 파트 수 ≤ 12000, 2048 한계, 판매 8·트레일 1·밤 벽 1, 베이스 7 우리 방향·러닝머신 자리·레벨 0~10 모양·표지판 숫자·주인 간판), 특수 장소 모델, 펫 134종(평균 30~80 파트), 우리 격자, 경비 15종 크기·자세, 알 6층·무게 라벨
lune run tests/smoke_client.luau    # 클라: 컨트롤러 전부 시작, 창 6개(인덱스·상점·트레일·펫 판매…), 폰 버튼 46px, 2판 HUD(알 버튼·패널·▶·발바닥·시간 글자), 부화 프롬프트, 업그레이드 표지판·판매 가게·트레일 상점 프롬프트, 달리기!!·드롭·알 칸, 러닝머신(점프→TreadmillLeave, +500), 구역 배너, +$34K, 슬로우 모드, 희귀 알 공지, 퓨전·사쿠라·제단·비밀 통로·퀘스트·무기, 반응형 HUD(750×381·844×390·1428×750)
```
`@lune/roblox` 진짜 인스턴스로 만들어 보므로 속성 이름·타입 오타와 nil 오류를 잡음. 모양·배치·느낌은 6장 체크리스트로 스튜디오에서.
