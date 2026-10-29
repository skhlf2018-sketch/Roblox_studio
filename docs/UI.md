# 화면·소리·생김새 (UI.md) — 7판 "씨앗을 훔치세요" (등급 16개 · 구역 18개)

작성: 선임 (2026-10-18 처음 · 2판 원작 스타일 · 5판 2026-10-22 · **7차 전면 갱신 = 6판 "씨앗을 훔치세요", 2026-10-27**).
게임이 **보이고 들리게** 만드는 부분을 정리한 문서입니다. 이전 기록(알·펫·퓨전·제단·우리 펫 걷기)은 git 이력에.
외부 에셋(메시·이미지·소리)을 올릴 계정이 없어서 **모든 모양은 기본 도형**(Block/Ball/Cylinder/Wedge + SpecialMesh)과 **UI 기본 요소(Frame)**로 코드에서 만듭니다.
원작 느낌의 핵심 = **Plastic 재질 + 표면 스터드** + 두 가지 색 체크무늬 + 굵은 검은 외곽선 글씨. 배치 숫자는 전부 수석의 `src/shared/Data/MapLayout.luau`, Remote 는 `docs/REMOTES.md`, 규칙은 `docs/SEED_GAME_DESIGN.md`.

**6판 용어** (화면 글): 알 → **씨앗** · 우리 → **정원** · 부화 → **성체가 됨** · 펫 → **(성체) 식물** · 돈 `$` → **코인** (`Format.money(n)` = "1.5K 코인") · 쓰다듬기 → **물 주기** · 경비 → **식물 괴물**. Remote·모듈·태그·변수 이름은 5판 그대로인 것이 많음 (`PetPet`, `IncubatingEgg`, `PetsController`, `PetModels` …).

## 0. 7판 (선임 2026-10-29) — 등급 16개 · 구역 18개 · 식물 158종 · 성장 3배

- **등급 글자 = 영어**: 화면의 등급은 전부 `Rarities.displayName` (`Theme.rarityName(id)` 가 이것을 돌려줌) — Common … Divine · Super · Hacker · Original · Developer · Ultradivine · **"H?a.(cke_r!#"**(16번 해커 글리치, 글자 그대로). 쓰는 곳: 도감(상세 + 카드 아래 `RarityTag`) · 성체 카드 · 자라는 씨앗/가방 카드 · 정원 식물 창 · 열매 가방 · 고르기 창(PetPicker) · 희귀 씨앗 배너(`NotifyController.rareEggText`) · 채팅 공지(`AnnounceController.textFor` — 서버 글의 한국어 등급을 payload `rarity` 로 다시 씀) · 둥지 씨앗 이름표·프롬프트(`EggService.eggTitle`) · 둥지 옆 장식 식물 이름표 · 특별 씨앗 글자("Secret 씨앗!" … "H?a.(cke_r!# 씨앗!") · 트레일 카드 등급(Common … Divine, 11~16은 Moonbloom · Rainbow · Lava · Starlight · Galaxy · Super Ultradivine).
- **무지개 띠** `Theme.RainbowRarities` = 신성 · 슈퍼 · 울트라디바인 · 해커 글리치. 해커 글리치는 무지개 대신 **깨진 띠** `Theme.GLITCH` (`Theme.bandFor(id)`).
- **깨진 색 깜빡임**: 파트에 `EggShell` 태그 + Attr **`Glitch`** → `WorldFxController` 가 무지개 순환과 같은 루프(0.08초)에서 분홍·초록·흰·검정·하늘 중 하나로 뚝뚝 바꿈 (Instance 안 만듦). 해커 글리치 씨앗 줄무늬 4개 · glitch_static 고리 픽셀 6개 · glitch 모양 식물 꽃잎 · 글리치 장미 괴물 픽셀 6개. 실버·황금·무지개 돌연변이 식물은 꽃잎 Glitch 를 지움(돌연변이 색이 보이게).
- **새 아우라 5개** (`Visuals.auras`, 파티클·빛은 지금처럼 희귀 이상 + 꺼진 채 + 100 스터드 안만 켬, 고리는 정원 식물 모델에만):

| 등급 | 아우라 | 파티클 | 고정 파트 (`AuraRing`) | 빛기둥 |
|---|---|---|---|---|
| Hacker | code_rain | `code` 초록 줄이 튀었다 주르륵 (Squash 세로) | 세로 코드 줄 6 | – |
| Original | first_light | `motes` 금빛 먼지가 천천히 떠오름 | 뒤에 세운 햇살 원판 + 빛살 6 | – |
| Developer | build_grid | `grid` 제자리 파란 점 깜빡 | 빛 격자 상자 (기둥 4 + 윗변 4) | – |
| Ultradivine | ultra_halo | rainbow | 흰 후광 6 + 무지개 후광 6 (두 겹) | 무지개 |
| H?a.(cke_r!# | glitch_static | `glitch` 아주 짧게 튀는 분홍·초록 찌그러진 조각 | 떠 있는 깨진 픽셀 6 (Glitch) | 분홍·초록 끊긴 띠 |

- **씨앗 껍데기** (`Visuals.eggLooks`, ≤ 8 파트 그대로): 해커 검정 + 초록 회로 줄 · 오리지널 상아 + 구리 줄 + 금 끝 · 개발자 흰 + 파란 줄 + 흰 보석 · 울트라디바인 흰 + 무지개 줄 + 금 별 · 해커 글리치 검보라 + Glitch 줄. 특별 씨앗 빛기둥 `specialEggs[..].beam` = "rainbow"(신성·슈퍼·울트라디바인) / "glitch"(해커 글리치). 성체 크기 `RARITY_SCALE` 16칸 (11번 위로 2.04 ~ 2.2).
- **식물 모양 19종** (`PLANT_FORMS` + 7판 `circuit` 네모 줄기·회로 줄·칩 / `blocky` 스터드 블록 쌓기 / `glitch` 거꾸로 + 떠 있는 깨진 픽셀). 이름 낱말: mainframe·wifi·circuit → circuit, block_·keyboard·studio·monitor → blocky, upside_down·static·broken_pixel → glitch, 나머지는 구역 테마 forms(해커 연구소 circuit/vine · 개발자의 방 blocky/cup · 버그 차원 glitch/rose).
- **새 구역 3개** (`Visuals.biomes` + MapBuilder, 구역 하나 약 300 파트 · 맵 약 7,240 / 상한 8,000 그대로):

| 구역 | 바닥 무늬 | 아치 (머리 · 가운데) | 담장 | 장식 (담장 쪽 · 가운데 흩기) | 둥지 | 분위기 |
|---|---|---|---|---|---|---|
| 16 해커 연구소 💻 | `circuit` 초록 회로 줄 + 패드 (검정 바닥, 검은 길) | `terminal` (LED · 자물쇠) | `screens` 모니터 | serverrack · codecolumn(떠다니는 코드) · satellite / cables · glowmoss | `circuit` 검은 블록 + 초록 빛 구슬 | `code` 초록 코드 비 |
| 17 개발자의 방 🛠️ | `baseplate` 스튜디오 회색 기본 바닥 + 격자 + 색 블록 판 | `toyblocks` (블록 · 톱니) | `toyshelf` 선반 + 블록 | desk(모니터·키보드·커피) · toyblock · giantmug / stickynote · pencil | `toy` 파랑·노랑 스터드 블록 | `dust` |
| 18 버그 차원 👾 | `pixels` 깨진 픽셀 (8칸 격자, 안 겹침) | `glitch` (어긋난 픽셀 · 빨간 경고) | `glitchwall` 찢어진 분홍·초록 조각 | upsidetree(거꾸로 나무) · missingtex(분홍·검정 체크 상자) · darkspike / glitchpixel · stars | `pixel` 분홍·검정 블록 | `glitch` 2~22 높이 깜빡 조각 |

- **새 경비 3마리** (`Visuals.monsters`, scale·height 는 수석 값): 바이러스 덩굴 `virus_vine` (몸 `vines` + 머리 `virus` 돌기 공 + `tendrils` + `codebits`) · 디버그 선인장 `debug_cactus` (선인장 몸 + `glasses` 네모 안경 + `magnifier` 돋보기 + 파란 꽃) · 글리치 장미 괴물 `glitch_rose_monster` (분홍 장미 + `ghostlayer` 어긋난 겹 머리 + `pixelshards`). 자는 얼굴 ↔ 추격 눈썹 그대로.
- **배경음**: `Bgm_hacker_lab` · `Bgm_developer_room` · `Bgm_bug_dimension` — 새 무료 id 를 못 골라서 있는 음악을 빠르기(`Sounds[..].speed` → PlaybackSpeed)만 바꿔 씀: 코스믹 ×1.15 · 베이스 ×0.85 · 유령 성 ×0.72.
- **도감**: 구역 탭 18개 세로 스크롤, 카드 격자 스크롤(AutomaticCanvasSize), "잠금 해제 n/158"(전체 수는 데이터에서), 카드 아래 영어 등급.
- **성장 3배**: 화면은 서버 `Required`(이미 ÷3)만 씀 — 표 시간(`Plants.growSeconds`)을 직접 보여 주는 곳 없음.

---

## 1. 파일 목록

### 데이터 (shared)
| 파일 | 내용 |
|---|---|
| `src/shared/Data/Visuals.luau` | **식물 생김새** `plantThemes`(15구역) · `PLANT_FORMS`(16 기본 모양) · `plantLook(id)`(구역 테마 + 이름 낱말 + id 해시 → 모양·색·꽃잎/잎 수·열매 모양) · `petColor(id, 1/2/3)`(꽃잎/잎/열매 색, 클라 UI 가 씀), **아우라** `auras`(11종), 경비 `guards`(식물 괴물 id·scale·height) + `monsters`, `rarityEffects` 11개, `mutationLooks`(+ 원소 frozen/burning/shocked `effect`), 씨앗 줄무늬 `eggLooks`, 구역 15개 테마, `plotColors`, 태그 `Tags`(+ `AuraFx`) |
| `src/shared/Data/Sounds.luau` | 소리 이름 → id + 설명 (5장) |
| `src/shared/Format.luau` | `Format.money` = "N 코인" (6판) |

### 서버 (모두가 같은 모양)
| 파일 | 내용 |
|---|---|
| `src/server/Services/MapBuilder.luau` | 맵 전체 (2장). 6판: **사쿠라 나무**(줄기·가지 5·분홍 꽃 덩어리 9·빛 꽃·등불·꽃잎, 태그 파트 지름 7 그대로), **러닝머신 모양 20단계**(`TREAD_STYLES`, 장식 2개 `extra2`), 표지판 글 코인·"+N/초"·정원, 허브 판 "씨앗을 훔치세요". 서버가 부르는 공개 함수(start·getFolder·getNests·groundY·setNightWalls·setPlotOwner·plotCount·getPlot) 이름 그대로 |
| `src/server/Services/PlantVisualService.luau` | **새 파일 (6판).** 자라는 씨앗(`IncubatingEgg`) 단계 모양, 정원 성체(`GardenPlant`) 식물 모델 + 열매, 등급 아우라, 둥지 옆 장식 식물(5판 부모 동물 자리), `ReplicatedStorage.PetModels` 도서관(식물 134종, UI 뷰포트용). 공개: `build(plantId, opts)` · `buildStage(plantId, stage, opts)` · `visualStage` · `setFruits(model, n)` · `addAura(host, rarityId, scale, opts)` |
| `src/server/Services/PetVisualService.luau` | 6판: **경비 = 식물 괴물 16종**만 (`buildMonster`, `build` 는 별칭). 5판 동물 체형·우리 펫 걷기·부모 동물·도서관은 지움. GuardPose·SleepZ·GuardGlow·자는/추격 얼굴 그대로 |
| `src/server/Services/EggVisualService.luau` | 둥지·들고 있는·떨어진 **씨앗**(`Egg` 태그): 아몬드 모양 껍데기 + 뾰족한 끝 + 세로 줄무늬 + 별·보석 점(≤ 8 파트), 등급 아우라(`addAura`), 특별 씨앗 빛기둥 + 이름표, 들고 있을 때 "♂ 4,740Kg" |
| `src/server/Util/Gui.luau` | 월드 글자 도우미 — 그대로 |

### 클라 (내 화면)
| 파일 | 내용 |
|---|---|
| `Controllers/IncubatorController.luau` | 씨앗 창(오른쪽 빨간 씨앗 버튼): "자라는 중" 탭(단계 이름 `GardenRules.stageName`·막대·남은 시간·가방 버튼·⏩ 건너뛰기) + "가방" 탭(심기) · **씨앗 심기 모드** · **건너뛰기 창**(`SkipDialog`) · 자라는 씨앗 프롬프트 "집기"(E)·"건너뛰기"(R) |
| `Controllers/PetsController.luau` | **정원 식물 창**(오른쪽 주황 버튼): "정원 n/칸 · 성체 n", 열매 모두 따기, 카드마다 열매·값·다음 열매·따기·먹이기·팔기(확인 창) · 판매 가판대 "식물 팔기"(F) |
| `Controllers/FruitBagController.luau` | **새 파일.** 열매 가방 창 · 먹이기(열매 ↔ 성체 고르기 + 확률 미리보기) · 판매 가판대 "열매 팔기"(E) · "+N 코인" 연출 |
| `Controllers/PetFxController.luau` | 다시 씀. 내 정원 파트에만 프롬프트 "열매 따기"(E) (물 주기는 2026-10-28 삭제) · 먹이기 결과 반짝/냠냠(`FeedResult`) |
| `Controllers/PlantFxController.luau` | **새 파일.** 아우라 100 스터드 안만 켜기 · 가까운(60) 식물 살랑살랑 |
| `Controllers/HatchController.luau` | **성체 카드** "성체가 됐어요!" (`PlantGrown`) |
| `Controllers/SakuraController.luau` | 사쿠라 창: "성체 바치기" / "씨앗 뽑기 · 크리스탈 10" |
| `Controllers/HudController.luau` | HUD (3장) + 오른쪽 **초록 열매 버튼·배지 "12/300"** |
| `Controllers/IndexController.luau` | "식물 도감" (등급 11개, 열매 1개 값, 신성 이상 무지개 띠) |
| `Controllers/ShopController.luau` | 상점: 정원 업그레이드("정원 칸 7 → 8") · 러닝머신(20단계 이름, "1초에 속도 +N") · 트레일 |
| `Controllers/TutorialController.luau` | 6판 5단계 가리키기 (4-3장) |
| `Controllers/SoundController.luau` | 소리 (5장) — 결과 이벤트에서 스스로 냄 |
| `Controllers/WorldFxController.luau` | "+열매 N" 팝업(`FruitPicked`), 떨어진 씨앗 "32초", 자는 경비 Z, 무지개 순환 |
| `Controllers/LeaderboardController.luau`, `NotifyController.luau`, `ChaseController.luau`, `HotbarController.luau`, `AnnounceController.luau` 등 | 글자만 6판으로 (코인·씨앗·식물 괴물·안전 구역) |
| `UI/Ui.luau` | + **`Ui.dialog` / `Ui.confirm`** (확인 창, 화면 층 "Dialogs") |
| `UI/PetPicker.luau` | 식물·씨앗·열매 고르기 창 (장착 개념 없앰, 카드 둘째 줄 `info` 옵션) |
| `UI/Theme.luau`, `UI/Icons.luau` | 등급 색 11개(Rarities 표에서 읽음) + `RainbowRarities`·`rarityName`, 코인 금색, 그림 `seed`·`plant`·`fruit`·`coin` (옛 이름 egg·paw·money 도 같은 그림) |
| `UI/Layout.luau` | 오른쪽 버튼 묶음 3개(씨앗·식물·열매)로 높이 맞춤 |

---

## 2. 맵 배치 (MapBuilder — 6판은 2판 배치 그대로)

```
            +Z (멀리)
  z=3600 ── 끝 벽 ─────────────────────────────
           15 유령 성 … 2 호수 (구역마다 240, 벽·문 없음, 경계에 베이지 모래띠)
  z=0    ── "안전 구역" 글씨 + 빨간 점선 + 밤 벽(NightWall 1장) ──
           [1]  허브(안전 구역, 잔디 스터드)  [2]      베이스: 왼쪽 x=-75 (1·3·5·7), 오른쪽 x=+75 (2·4·6)
           [3]       기본 스폰(0,-140)      [4]      z = -40 / -110 / -180 / -250
           [5]                              [6]
           [7]        판매 가판대 · 트레일 상점 · 이벤트 포털 (오른쪽 z≈-250)
  z=-290 ── 허브 뒤 흰 벽 ──
```
- **바닥·담장·구역 장식·둥지·경비 집**: 5판 그대로 (구역 테마 `Visuals.biomes`). 둥지 `Nest` 태그 파트 크기 그대로 → 서버가 씨앗을 그 위에 놓음.
- **둥지 옆 장식 식물** (`ParentAnimalSpot` 자리, 5판 부모 동물): 그 구역 식물을 작게 + 이름표 (`ParentAnimal` 태그, Attr `Sway`).
- **특수 장소**: 6판은 **사쿠라 나무**(`SakuraIncubator`, 벚꽃 구역) 하나뿐. 제단·비밀 통로·퓨전 머신 자리는 비어 있음.
- **베이스(7개)**: 정원(뒤 46, `PenArea`) + 앞마당. 앞마당에 스폰·**러닝머신**(`Treadmill`, 12×8)·**판매 가판대**(`SellStall` + `PlotIndex`, 간판 "열매 판매")·업그레이드 표지판 2개("정원 업그레이드 / 레벨 n > n+1 / [N 코인]", "러닝머신 업그레이드 … +N/초", `UpgradeSign` Attr `Kind`/`PlotIndex`)·주인 간판.
- **러닝머신 모양 20단계** (`TREAD_STYLES`): 1 기본 · 2 사이파이 · 3 불꽃 · 4 셀럽 · 5 황금 · 6 얼음 · 7 럭키블록 · 8 해커 · 9 악마 · 10 천사 · **11 정글 · 12 바다 · 13 사탕 · 14 벚꽃 · 15 용암 · 16 수정 · 17 유령 · 18 은하 · 19 무지개 · 20 황제** (상점 `TREADMILL_NAMES` 와 같은 순서). 레벨 0(잠김) = 기본 모양 반투명.
- **파트 수**: 맵 약 7,240 (7판 18구역, 상한 8,000, `smoke_visuals` 가 검사).

### 2-1. 클라 이름 규칙 (연출이 찾는 이름 — 모델을 바꿀 때 유지)
| 이름 | 쓰는 곳 |
|---|---|
| `IncubatingEgg` 파트(투명) > 모델 **`SeedVisual`** (Attr `Stage` "seed"/"sprout"/"stem"/"bud", `Sway`), 파트 Attr **`VisualHeight`** | PlantFx 흔들기 · 프롬프트·팝업 높이 |
| `GardenPlant` 파트(투명) > 모델 이름 = **식물 id** (PrimaryPart `Root` Anchored, 나머지 WeldConstraint, Attr `Sway`·`Height`·`Form`·`Fruits`·`PetId`), 열매 파트 **`Fruit1`~`Fruit5`**(서버가 Attr `Fruits` 개수만 보이게), 파트 Attr `VisualHeight` | PlantFx · PetFx · WorldFx "+열매" |
| 태그 **`AuraFx`** (`Visuals.Tags.AuraFx`): 그 파트 아래 ParticleEmitter·PointLight 는 서버가 `Enabled = false` → 클라가 100 안만 켬. 정원 모델은 투명 파트 `Aura`, 씨앗은 껍데기 `Shell` 에 붙음. 빛기둥 Beam `SkyPillar`·`SpecialBeam` 은 늘 켜짐 | PlantFxController |
| 무지개 돌연변이: 꽃잎·열매 파트에 `EggShell` 태그 + Attr `Rainbow` | WorldFx 색 순환 |
| 클라 프롬프트 (내 것에만, Attachment `GardenPromptAttach`): 성체 `PickFruitPrompt`(E) · `WaterPrompt`(F) / 씨앗 `WaterPrompt`(F) · "집기"(E) · "건너뛰기"(R) / 가판대 `SellFruitsPrompt`(E) · `SellPrompt`(F, 식물 팔기) / 사쿠라 `SakuraPrompt`(E) | PetFx · Incubator · FruitBag · Pets · Sakura |
| 정원 식물 창 버튼 `PickFruit`(카드)·`PickAllFruit`·`FruitBagOpen`·`Feed`·`Sell` · 열매 가방 `FeedButton` · 건너뛰기 창 `SkipDialog`(`SkipAll`/`SkipHalf`) · 사쿠라 `OfferButton`/`DrawButton` | Tutorial 반짝 · smoke_client |
| `UpgradeSign` 태그 Attr `Kind`·`PlotIndex` / `TrailShop` / `PlotSpawn` / `LeaderboardBoard` | Shop · Trail · WorldFx · Leaderboard |
| 경비 겉모습 `SleepZ`(`Z1~Z3`), `GuardPose`, `GuardGlow`, 눈 `EyeOpen`/`EyeClosed`/`Brow` | WorldFx Z 둥실 · 얼굴 |
| 핫바 `BagEgg_<uid>`·`MoreEggs`, `TutorialPanel`·`TutorialArrow`·`TutorialGlow`·`TutorialDone`, Workspace `TutorialGuide`, 씨앗 미리보기 `EggPlacePreview`/`EggPlaceRing`, 떨어진 씨앗 `DropTimer` | Hotbar · Tutorial · Incubator · WorldFx |

---

## 3. 생김새 (서버)

### 자라는 씨앗 (PlantVisualService — `IncubatingEgg`)
- 서버 공 파트는 투명(판정·이름표 그대로), 자식 `SeedVisual` 을 Attr `Stage` 가 바뀔 때만 다시 만듦 (일생에 4번).
- **4 모양**: 씨앗(흙 둔덕 + 반쯤 묻힌 씨앗, 0% 막 심음) → **새싹**(떡잎 2장) → **줄기**(줄기 + 잎) → **봉오리**(등급 색 봉오리). 이름표 "Label" 은 모델 위로.

### 성체 식물 (PlantVisualService — `GardenPlant`)
- **절차적**: 134종을 손으로 만들지 않고 `Visuals.plantLook(id)` = 구역 테마(숲 꽃·나무, 호수 수초·연꽃, 사막 선인장·야자, 정글 덩굴·대나무, 눈 소나무, 화산 불꽃꽃, 바다 해초·산호, 선사 고사리, 코스믹 버섯, 벚꽃 나무 …) + 이름 낱말(버섯·장미·선인장 …) + **id 해시**(잎 수·꽃잎 수·색조·열매 모양) → 16 기본 모양(`PLANT_FORMS`) 중 하나로. 134종 모두 서로 다름 (평균 약 20 파트, 14~29).
- **등급**: 크기·색 진하기, **크기 등급**(보통·큼·거대·초거대)도 키에 반영. **돌연변이 색** `Visuals.mutationLooks` (실버 Foil · 황금 네온 · 무지개 순환 · 얼음/불/번개 파티클).
- **열매**: `Fruit1~5` 를 미리 만들고 Attr `Fruits` 개수만큼만 보임 (바뀌면 Transparency 만 — 다시 안 만듦).
- **흔들기**: 모델 Attr `Sway` → 클라 PlantFxController 가 60 스터드 안만 Root 를 ±3° Tween (Reverse·무한, 멀어지면 Cancel + 원래 자리). 5판 펫 걷기 코드는 지움.

### 아우라 (`Rarities.aura` 16종, `Visuals.auras` — 7판 5개는 0장)
| 등급 | 아우라 | 모양 |
|---|---|---|
| 일반 | none | 없음 |
| 고급 | lime_glow | 파티클 없이 연두 네온 테두리/색 |
| 희귀 | blue_sparkle | 파란 반짝 파티클 |
| 에픽 | purple_flame | 보라 불꽃 |
| 전설 | gold_ring | 금빛 링(정적 파트) + 반짝 |
| 신화 | red_lightning | 빨간 번개 |
| 코스믹 | stardust_swirl | 별가루 소용돌이 |
| 비밀 | black_mist | 검은 안개 + 보라 눈 |
| 영원 | white_clock | 흰 시계 링 |
| 신성 | rainbow_beam | 무지개 광선 |
| 슈퍼 (7판, 6판 슈퍼 울트라디바인 것) | sky_pillar | 무지개 + 번개 + **하늘 빛기둥 Beam (늘 켜짐, 맵 어디서나)** |
| 해커 · 오리지널 · 개발자 · 울트라디바인 · 해커 글리치 | code_rain · first_light · build_grid · ultra_halo · glitch_static | 0장 표 (7판) |
- **가볍게**: 파티클·빛은 **희귀(rare) 이상만**, 서버는 꺼진 채로 만들고(`AuraFx` 태그) 클라가 내 캐릭터 **100 스터드 안**만 켬 (0.5초마다 검사, 켜짐이 바뀔 때만 자식을 훑음). Rate 작게.

### 씨앗 (EggVisualService — `Egg` 태그: 둥지·들고 있는·떨어진)
- 아몬드 모양 껍데기 `Shell` + 뾰족한 끝 `Tip` + 세로 줄무늬(등급 색, `eggLooks`) + 별·보석 점, ≤ 8 파트. 판정 파트 높이에 맞춰 바닥에 붙음. 아우라 위 규칙.
- 특별 씨앗(비밀 이상 `Special`): 빛기둥 `SpecialBeam` + "비밀 씨앗!" 이름표. 들고 있을 때 "♂ 4,740Kg".

### 경비 = 식물 괴물 (PetVisualService)
- `Biomes.guardName` 15구역 + 천사&악마 밤 쪽 = 16종: 덥석 파리지옥 · 연꽃 개구리풀 · 가시 선인장 대장 · 덩굴 호랑이꽃 · 서리 가시나무 · 용암 머리꽃 · 심해 해초 괴물 · 공룡 고사리 · 우주 버섯 거인 · 벚꽃 여우나무 · 돌 거인 나무 · 천사 백합 / 악마 장미 · 정령 버섯 · 사탕수수 거인 · 호박 머리 덩굴 (15~31 파트).
- **키(`Height`)·scale 은 `Visuals.guards` 그대로** (GuardianService 잡힘 거리). 잘 때(Sleeping/Idle/Return) 감은 눈 + Z, 쫓을 때(Chase)만 눈 뜸 + 화난 눈썹.

### 사쿠라 나무 (MapBuilder)
- 태그 파트 지름 7·자리 그대로, 겉모습만 벚꽃 나무 (줄기·가지 5·분홍 꽃 덩어리 9·빛 꽃·등불·꽃잎 파티클).

---

## 4. 화면

```
 ┌─────────────────────────────────────────────────────────────────┐
 │        [1/5 숲에서 씨앗 훔치기 · 작은 설명]   ← 튜토리얼     [🏆 랭킹 −]│
 │                  [ 달리기!! ]   ← 씨앗 들었을 때       [코인][속도] │
 │                  Jungle 😬      ← 구역 배너                         │
 │ [🛒 상점    ]                                          [🌰 씨앗]① │
 │ [📘 도감    ]                                          [🌿 식물]  │
 │ [■ 슬로우 모드]                                        [🍎 12/300]│
 │ [⚙ 설정     ]                                                     │
 │ 👟 5.7M   (빨강)                    씨앗을 훔쳤어요!               │
 │ 🪙 18.7B 코인 (금색)                [ 🗑 드롭 ]                    │
 │       [1 방망이][2 곰덫 x3][3 🌰][4 🌰][5 +3]            🌙 3분 58초 │
 └─────────────────────────────────────────────────────────────────┘
```
| 화면 | 파일 | 데이터 |
|---|---|---|
| 왼쪽 메뉴 | HudController | 상점 · 도감(배지 = 받을 보상 수) · 슬로우 모드 · 설정 |
| 왼쪽 아래 속도·코인 | HudController | Attr `Speed`, `Money` (`Format.money` = "N 코인") |
| 오른쪽 씨앗 / 식물 / **열매** 버튼 | HudController | 씨앗 → 씨앗 창(배지 = 가방 씨앗 수) · 식물 → 정원 식물 창 · 열매 → 열매 가방 창 (배지 "`FruitCount`/`fruitBagMax`") |
| 오른쪽 아래 시간 | HudController | GameState `Phase`/`PhaseEndsAt` |
| 달리기!! / 잡힘 | ChaseController | 씨앗 들면 배너 + 비네트 + 드롭, 식물 괴물 이름, 안전 구역 들어오면 "안전 구역!" |
| 씨앗 창 "자라는 중" | IncubatorController | `snap.incubators` (또는 파트 Attr `Progress`/`Required`): 씨앗 그림 + 이름 · **단계(새싹/줄기/봉오리)** + 막대 + 남은 시간(다 자라면 "곧 성체!") + 가방(`PickUpPlacedEgg`) + **⏩**(건너뛰기 창). 탭 "자라는 중 · 정원 n/칸"(`#incubators + #pets` / `penSlots`) |
| 씨앗 창 "가방" | IncubatorController | `snap.eggs` 카드 → "심기" → 심기 모드 |
| 씨앗 심기 모드 | IncubatorController | 정원 바닥 미리보기 초록/빨강 = `EggPlacement.check(toLocal, 자라는 씨앗 + 성체 자리)` + 정원 칸 + 서 있는 곳. PC 클릭 / 폰 "여기 심기" → `PlaceEgg(uid, 월드 x, z)` |
| **건너뛰기 창** | IncubatorController + `Ui.dialog` | "전부 · N 코인" / "절반 · N 코인" / 취소 — `GardenRules.skipCost(petId, progress, required, mode)`, **1초마다 다시 계산**, 코인 모자라면 회색 → `SkipGrowth(uid, "all"\|"half")` |
| **성체 카드** | HatchController | `PlantGrown` → 씨앗 퐁! → "성체가 됐어요!" + 3D 식물 + "열매 1개 N 코인 · N초마다" + NEW!(도감 첫 발견). 한꺼번에 여러 그루면 4장까지 |
| **정원 식물 창** | PetsController | `snap.pets`: "정원 n/칸 · 성체 n", **열매 모두 따기**(`PickFruit("all")`), 열매 가방 버튼, 카드: 열매 n/5 · 1개 값(`FruitRules.fruitValue`) · 다음 열매 n초(1초마다) · 따기(`PickFruit(uid)`) · 먹이기 · **팔기 N 코인**(`GardenRules.sellPrice`, 확인 창 → `SellPlant`) |
| **열매 가방 창** | FruitBagController | `snap.fruits`: "열매 12/300 · 다 팔면 N 코인", 칸마다 열매 색 · 이름 · ×개수 · 값 · **먹이기** → 성체 고르기(카드에 `feedOptions`·`feedChance`, 더 붙을 게 없으면 회색) → `FeedFruit(plantUid, fruitId)` |
| 판매 가판대 | FruitBagController / PetsController | E "열매 팔기 · 열매 12개 · 3.4K 코인"(Attr `FruitCount`·`FruitBagValue`, 0개면 안내만) → `SellFruits()` → `FruitsSold` "+3.4K 코인" / F "식물 팔기" → 정원 식물 창 |
| 정원 프롬프트 | PetFxController / IncubatorController | 내 성체: "열매 따기 (n)"(E, 0개면 꺼짐) / 내 씨앗: "집기"(E) · "건너뛰기"(R). 높이 = `VisualHeight`. (물 주기는 2026-10-28 삭제) |
| 물방울 · 먹이기 결과 | PetFxController | `PetPetted(owner, uid)` → 💧 + 파란 반짝 + `Water` (Attr `OwnerUserId` 로 거름) / `FeedResult` → 돌연변이 색 반짝 + "황금!" 또는 "냠냠" |
| "+열매 N" | WorldFxController | `FruitPicked{plantUid,count}` → 그 식물 위 팝업 |
| 사쿠라 창 | SakuraController | "성체 바치기"(카드에 `SakuraRules.crystalsFor` → `SakuraOffer`) / "씨앗 뽑기 · 크리스탈 10"(모자라면 회색 → `SakuraDraw`), `SakuraResult` 꽃잎·꽃 팝업 |
| 도감 | IndexController | "식물 도감", 구역 탭 18(7판), 등급 16개 색·영어 이름(신성·슈퍼·울트라디바인 무지개 띠, 해커 글리치 깨진 띠), "열매 1개 N 코인 · N초마다", 보상 코인·속도, 모두 획득 |
| 상점 | ShopController | 정원 업그레이드 "정원 칸 7 → 8"(최대면 "(최대!)") · 러닝머신 "○○ 러닝머신: 1초에 속도 +N"(`Economy.treadmillGainPerSecond`, 20레벨 "+1M") · 트레일 |
| 러닝머신 | TreadmillController | `OnTreadmill` 동안 입력 끔, 점프 → `TreadmillLeave`, `TreadmillStep` "+1M" 분홍 팝업 |
| 랭킹판 | LeaderboardController | 코인 / 속도 탭 + 허브 3D 판 |

### 4-1. 확인 창 (`Ui.dialog` / `Ui.confirm`)
- 화면 층 "Dialogs" (창 위). 버튼은 `Ui.touch` 로 폰에서도 46px 이상. 건너뛰기 · 식물 팔기 · 먹이기 확인에 씀.

### 4-2. 반응형 HUD (`UI/Layout.luau`)
- PC: 왼쪽 메뉴 넓은 1열, 속도·코인 왼쪽 아래, 오른쪽 버튼 3개(씨앗·식물·열매, 묶음 높이 240). 터치: 속도·코인 위 왼쪽 한 줄, 시간 오른쪽 위, 메뉴는 조이스틱 위 정사각 아이콘 2~3열, 오른쪽 버튼은 점프 버튼과 안 겹치게.

### 4-3. 튜토리얼 가리키기 (TutorialController, 6판 단계)
1 숲에서 씨앗 훔치기 → 노란 빔 "숲으로!"(허브) / "씨앗 훔치기!"(가장 가까운 둥지) · 2 안전 구역으로 → 경계 "안전 구역" · 3 핫바에서 씨앗을 골라 정원에 심기 → 핫바 씨앗 칸 반짝 + 내 정원 "정원에 심기" · 4 성체까지 기다리기 → 남은 시간이 가장 적은 내 씨앗 "자라는 중… n초"/"곧 성체가 돼요!" · 5 열매 따서 팔기 → 열매 가방이 비면 열매 달린 내 성체 "열매 따기!"(+ 정원 식물 창 `PickFruit`/`PickAllFruit` 반짝), 가방에 열매가 있으면 가장 가까운 판매 가판대 "열매 팔기!". 끝 = 색종이 + "500 코인 받았어요!".

---

## 5. 소리 (`src/shared/Data/Sounds.luau`)

ID 가 `rbxassetid://0` 이면 조용히 건너뜁니다. 6판 정원 소리는 기존 무료 ID 를 다시 씀 — 더 좋은 소리를 찾으면 숫자만 바꾸세요.

| 이름 | 소리 | 언제 |
|---|---|---|
| `Click` / `Open` / `Close` | 톡 / 뿅 / 슉 | 버튼·창 |
| `Pickup` · `RunAlert` · `Chase`(음악) | 퐁! · 사이렌 · 추격 음악 | 씨앗 줍기 (`RunAlert`) |
| `Caught` / `Trap` / `Bat` / `Swing` | 퍽 / 철컥 / 붕 / 휙 | 잡힘·곰덫·무기 |
| `Deliver` · `Drop` | 띠링~ · 툭 | 씨앗 가방에 (`EggDelivered`) · 드롭 |
| **`Grown` / `GrownRare`** (6판) | 짠 / 팡파레 (전설 이상) | `PlantGrown` |
| **`FruitPick`** (6판) | 뽁! (0.15초에 한 번) | `FruitPicked` |
| **`FruitSell`** (6판) | 짤랑짤랑 | `FruitsSold` |
| **`Feed` / `FeedMutate`** (6판) | 냠냠 / 반짝 | `FeedResult` (mutation 없음 / 있음) |
| `SakuraOffer` · `Bloom` / `SpiritBloom` | 철컥+반짝 · 꽃잎 반짝 / 합창 | `SakuraResult` offered · draw (정령 벚꽃 = 비밀 이상) |
| `Coin` · `Purchase` · `Error` · `Notify` · `Reward` | 짤랑(작게) · 차링 · 뿡 · 띵 · 반짝 상승 | 코인 늘 때 · 성공 · 실패 · 안내 · 도감 보상 |
| `NightBell` / `DayStart` / `Reset` / `RareEgg` | 종 / 차임 / 휘리릭 / 팡파레 | 밤 · 낮 · ALL SEED RESET · 특별 씨앗 공지 |
| `ZoneEnter` · `TreadmillStep` | 휙+짠 · 탁 | 구역 배너 · 러닝머신 |
| `TutorialStep` / `TutorialDone` | 반짝 / 팡파레 | 튜토리얼 단계 / 끝 (500 코인) |
| `Bgm_base`, `Bgm_forest` … `Bgm_haunted_castle` (음악) | 베이스 / 구역 분위기 | 있는 곳이 바뀌면 |

6판에서 지운 소리: `Hatch`·`HatchRare`·`HatchReady`(→ `Grown`), `Offline`(오프라인 수입), `Equip`(장착), `Sell`(펫 판매), `Pet`(쓰다듬기 → `Water`), `Unlock`(→ `SakuraOffer`). 퓨전·제단·비밀 통로 소리도 없음.

---

## 6. 스튜디오에서 꼭 볼 것

사장님용 번호 체크리스트는 `docs/STUDIO_CHECKLIST.md` (씨앗 줍기 → 심기 → 단계 → 성체 → 열매 따기 → 팔기 → 먹이기 → 건너뛰기 → 물 주기 → 사쿠라 → 도감 → 러닝머신 20레벨). 선임이 특히 걱정하는 것:
1. **씨앗 4단계·성체 모양**: 단계마다 모양이 바뀌는지, 식물이 바닥에 붙어 있는지(떠 있거나 묻히지 않음), 이름표·프롬프트·"+열매" 팝업 높이(`VisualHeight`)가 모양에 맞는지, 열매 개수가 따기에 맞게 보이고 사라지는지.
2. **흔들기·아우라**: 가까운 식물만 살랑살랑(원래 자리에서 밀리지 않음), 희귀 이상 아우라가 100 스터드 안에서만 켜지고 정원에 식물이 많아도 안 끊기는지.
3. **식물 괴물 16종**: 키·발 위치(땅에 닿음), 자는 얼굴 ↔ 추격 얼굴, 잡힘 거리가 5판과 같은지.
4. **판매 가판대 E/F 두 프롬프트**가 겹치지 않고 따로 눌리는지, 건너뛰기 확인 창 가격이 1초마다 줄어드는지.
5. **사쿠라 나무**·**러닝머신 11~20레벨 모양**·폰 에뮬레이터(오른쪽 버튼 3개와 점프 버튼).

## 7. 알려진 한계 / 다음 할 일
- 둥지 파트는 아직 5판 둥지 모양 ("씨앗 주머니/꽃받침" 은 다음에).
- 로벅스 건너뛰기·"모두 성장시키기"·"월드" 버튼은 준비 중(꺼 둠, 어른 확인 필요).
- 식물·괴물 모양은 Lune 에서 만들어지는 것(파트 수·이름·Attr)까지만 확인 → 생김새는 스튜디오에서.
- 6판 소리는 기존 무료 ID 재사용 — 더 어울리는 소리로 바꾸면 좋음.

## 8. 스모크 테스트 (Lune, 스튜디오 없이)

저장소 루트에서 (정식 테스트 `tests/run.luau` 에는 안 들어감):
```powershell
lune run tests/smoke_visuals.luau   # 서버: 맵(18구역·파트 상한 8,000·사쿠라 나무·러닝머신 20 모양), 식물 158종 모델(모양 19종·파트 수·모양 다 다름, 7판 아우라 5개 고리·빛기둥·Glitch), 씨앗 4단계, Fruits → 보이는 열매 수, 아우라(rare 이상·Enabled false·AuraFx), 씨앗 껍데기, 경비 식물 괴물(Height 그대로·얼굴)
lune run tests/smoke_client.luau    # 클라: 컨트롤러 전부 시작 → 창·버튼·프롬프트 → 보낸 Remote (SellFruits·SkipGrowth all/half·FeedFruit·PickFruit uid/all·PetPet 씨앗/성체·SellPlant·SakuraOffer·SakuraDraw·PlaceEgg…), 결과 이벤트(PlantGrown·FruitPicked·FruitsSold·FeedResult·PetPetted·SakuraResult), PlantFx 거리 켜기/끄기·흔들기, 연결 수 안 샘, 폰 버튼 46px·HUD 겹침
```
`@lune/roblox` 진짜 인스턴스로 만들어 보므로 속성 이름·타입 오타와 nil 오류를 잡음. 모양·배치·느낌은 6장 / STUDIO_CHECKLIST 로 스튜디오에서.
