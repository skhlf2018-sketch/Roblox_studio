# 화면·소리·생김새 (UI.md)

작성: 선임, 2026-10-18. 게임이 **보이고 들리게** 만드는 부분(맵, 동물·알 모양, 화면, 소리, 효과)을 정리한 문서입니다.
외부 에셋(메시·이미지·소리)을 올릴 계정이 없어서 **모든 모양은 기본 도형**(Block/Ball/Cylinder/Wedge + SpecialMesh 타원체)과 **UI 기본 요소**로 코드에서 만듭니다.
소리는 이름만 정해 두었고, **사장님이 ID 만 채우면** 바로 납니다 (아래 5장).

---

## 1. 파일 목록

### 데이터 (shared)
| 파일 | 내용 |
|---|---|
| `src/shared/Data/Visuals.luau` | 펫 134종 + 경비 전용 5종 생김새(체형·색 3개·장식), 구역 15개 테마(바닥·장식·분위기 파티클·안개·배경음), 희귀도/돌연변이 효과, 베이스 색, 연출용 태그 이름 |
| `src/shared/Data/Sounds.luau` | 소리 이름 → `rbxassetid://0` 자리 + 설명 (5장 표) |

### 서버 (모두가 같은 모양을 봐야 하는 것)
| 파일 | 내용 |
|---|---|
| `src/server/Services/MapBuilder.luau` | 맵 전체 생성 + 태그 색인 (기존 공개 함수·태그·Attribute 그대로) |
| `src/server/Services/PetVisualService.luau` | 동물 모양 조립(체형 템플릿 17종 + 장식 약 80종), 부모 동물, 우리 진열, 경비 겉모습, `ReplicatedStorage.PetModels` 도서관 |
| `src/server/Services/EggVisualService.luau` | 알 겉모습(달걀 모양 껍데기·색·돌연변이·특별 알 빛기둥), 부화 중 알 반짝임 |
| `src/server/Util/Gui.luau` | 월드 글자: `billboard`/`surface`(기존 API 그대로) + `sign`(큰 제목·작은 부제 표지판) + `tag`(여러 줄 이름표) |

> PetVisualService / EggVisualService 는 지금 **MapBuilder.start() 끝에서** 시작합니다. 본부장이 `Main.server.luau` 에 정식 등록하면(MapBuilder 다음 줄에 `PetVisualService.start()`, `EggVisualService.start()`) 두 번 시작돼도 괜찮게 `started` 검사가 들어 있습니다.

### 클라 (내 화면에서만)
| 파일 | 내용 |
|---|---|
| `src/client/Main.client.luau` | 진입점. 컨트롤러를 하나씩 따로 시작 (하나가 오류여도 나머지는 동작). DebugController 는 스튜디오에서만 |
| `src/client/UI/Theme.luau` | 색·글꼴(FredokaOne)·애니메이션 상수 |
| `src/client/UI/Ui.luau` | ScreenGui 하나 + 층(Hud/Panels/Windows/Alerts/Popups/Toasts) + 위젯(버튼·창·카드·배지·스크롤) + 화면 배율(UIScale) |
| `src/client/UI/Windows.luau` | 큰 창 열고 닫기 (한 번에 하나, 열기/닫기 애니메이션, ESC) |
| `src/client/UI/PetViewport.luau` | 3D 펫을 UI 안에 (ViewportFrame, 발견 전엔 검은 실루엣) |
| `Controllers/HudController.luau` | 상단 돈·속도·낮밤 타이머, 밤 안내 띠, 구역/안전 구역 표시, 왼쪽 메뉴 버튼 5개 + 배지 |
| `Controllers/IndexController.luau` | 도감 창 |
| `Controllers/PetsController.luau` | 펫 창 (보관함·장착·Equip Best) |
| `Controllers/ShopController.luau` | 상점 창 (우리·러닝머신·트레일) |
| `Controllers/GiftController.luau` | 선물 창 (무료 보상) |
| `Controllers/SettingsController.luau` | 설정 창 (음악/효과음) |
| `Controllers/HotbarController.luau` | 오른쪽 아래 도구 핫바 (기본 Roblox 가방 UI 끔) |
| `Controllers/ChaseController.luau` | "RUN!!" + 경비 거리, "잡혔다!" + 화면 흔들림 + 빨간 비네트 |
| `Controllers/IncubatorController.luau` | "자라는 알" 패널 + 부화 버튼 |
| `Controllers/HatchController.luau` | 부화(·퓨전) 결과 카드 팝업 |
| `Controllers/NotifyController.luau` | 토스트, 상단 배너 공지, 오프라인 수입 팝업, 2단계 알림(선물 알·자동 판매·사쿠라·제단·비밀 통로) |
| `Controllers/SoundController.luau` | 효과음·배경음·추격 음악, 이벤트 연결, 음소거 |
| `Controllers/LightingController.luau` | 낮/밤/새벽 조명 Tween, 구역별 안개(Atmosphere), 색 보정·블룸 |
| `Controllers/ZoneController.luau` | 내가 있는 구역 계산 (보기용, 0.3초마다) |
| `Controllers/WorldFxController.luau` | 펫 통통·숨쉬기, 레인보우 알 색 순환, 든 알 흔들림, Highlight 개수 제한, 구역 분위기 파티클 켜기, 배달/부화/잡힘 파티클 |
| (기존) `AnnounceController`, `RagdollController`, `ToolController`, `DebugController` | 수석이 만든 것 그대로 |

---

## 2. 맵 배치 (MapBuilder)

```
            +Z (멀리)
   15 유령 성(오른쪽)      ← 가장 멀다 (Z ≈ 1840)
   14 사탕 왕국(왼쪽)
   ...                      길(폭 100) 양옆으로 번갈아
    2 호수(오른쪽)
    1 숲(왼쪽)              ← 가장 가깝다 (Z = 160)
   ── 입구 아치 "계란 훔치기" (Z ≈ 34)
   중앙 광장 + 스폰 (Z = 5)
   베이스 1~7 (Z = -75, 한 줄, 입구가 +Z 쪽)
            -Z
```
- 구역 = 160×160 축 정렬 바닥(`Zone` 태그), 길 중심에서 X ±145. 뒤 구역일수록 멀어서 돌아오는 데 오래 걸림.
- 구역마다: 테마 바닥 재질·색·테두리, 길 쪽 입구 길, **입구 표지판(구역 이름 크게 + 추천 속도 작게, 15·14번은 NEW! 리본)**, 경비 집(가운데), 둥지 8개(반지름 46, 갈색 원기둥 + 지푸라기), 부모 동물 자리(반지름 56, 둥지를 바라봄), 테마 장식, 분위기 파티클 상자, 밤 벽 4개(반투명 빨간 네온).
- 구역 장식 (Visuals.biomes.decor): 숲(나무·덤불·버섯·꽃), 호수(연못·갈대·연잎), 사막(선인장·피라미드·뼈), 정글(야자·큰 나무·덩굴), 눈(눈 덮인 소나무·눈사람·얼음 기둥), 화산(용암 웅덩이 네온·용암 바위·화산), 심연의 바다(산호·해초·조개), 선사시대(고사리·공룡 뼈), 코스믹(네온 별 바닥·떠 있는 행성·크리스탈), 벚꽃(벚나무·등불·도리이), 타이탄 사원(기둥·부서진 기둥·금 석상), 천사 & 악마(바닥 반은 천국 흰+금 / 반은 지옥 검+빨강, 구름·금기둥 / 불구덩이·검은 가시), 마법의 숲(빛나는 네온 버섯·마법 나무·요정 불빛), 사탕 왕국(초콜릿 강·막대사탕·지팡이 사탕·젤리·생강빵 집), 유령 성(성벽+탑·묘비·죽은 나무·호박 등불 + 보랏빛 짙은 안개).
- 베이스(90×90, 색 7가지): 울타리(앞 가운데 입구), 입구 아치 **주인 이름 표지판**(`OwnerUserId` 바뀌면 "OO의 베이스"), 스폰, **배달 패드**(빛나는 초록 원 + 반짝이 + "알 배달!"), **부화 슬롯 8개**(받침), **우리**(나무 울타리 잔디밭, 펫 진열), **러닝머신**(검은 벨트·난간·화면), **퓨전 머신**(보라 기계 + 빛나는 유리 돔), **도감 보드**("도감"), **트레일 상점**(줄무늬 차양 가게).
- 큰 바닥·길·투명 경계벽은 전부 **한 변 2048 이하로 나눠** 만듦 (`longPartZ`).
- `Workspace` 에 이름이 `Map` 인 무엇이든(Folder·Model) 있으면 새로 만들지 않고 태그만 읽음.
- 파트 수(스모크 테스트 기준): 맵 약 8,400개(부모 동물 120마리 포함) + 우리 펫(마리당 평균 23개) + 알.

---

## 3. 동물·알 생김새

### 펫 (PetVisualService)
- 체형 템플릿 17종: `bird quad fish snake bug spider dragon ghost humanoid frog turtle whale jelly lizard blob dino penguin`
- 장식(features) 약 80종: 귀(뾰족/둥근/긴/큰/처진), 뿔·사슴뿔, 왕관, 후광, 날개/박쥐 날개, 갈기, 꼬리(복슬/아홉 꼬리/악마), 줄무늬·점, 이빨·송곳니·상아·코, 크리스탈, 불꽃(Fire), 선글라스, 머리 3개, 해골, 갑옷·투구·두건, 칼·낫·막대사탕, 사탕 장식(아이싱·스프링클·단추), 호박, 붕대, 바느질 등.
- **펫을 추가하려면**: `Visuals.luau` 에 `pet("id", "체형", "색1", "색2", "색3", "장식1,장식2", 옵션)` 한 줄 (색 이름은 같은 파일 팔레트 `C`).
- 희귀도 효과: 전설 금빛 테두리, 신화 빨강, 코스믹 보라 테두리 + 보라 반짝이, 비밀 검정 테두리 + 검은 연기, 영원 청록 테두리 + 청록 빛, 신성 흰 테두리 + 무지개 반짝이.
  Highlight 는 로블록스가 한 화면에 31개까지만 그려서, 클라가 **카메라에 가까운 26개만** 켭니다.
- 부모 동물: 둥지 순서대로 그 구역 펫(천사&악마는 이번 주기 쪽 `HeavenSide`에 따라 천국/지옥 펫으로 바뀜), 크기 2.2배, 이름·희귀도 이름표, 클라에서 살짝 숨쉬기.
- 우리: 주인이 장착한 펫 최대 18마리를 원형 2줄로(바깥 10 + 안쪽 8), 1초마다 바뀐 것만 다시 만듦. 크기 등급만큼 커짐(초거대 1.5배), 돌연변이 펫은 그 색으로 반짝임. 머리 위: 이름(희귀도 색) / `$X/초` / 크기·돌연변이. 클라에서 통통 튐.
- 경비: `Visuals.guards` (숲 닭, 호수 백조, … 사탕 왕국 생강빵 거인, 유령 성 사신, 천사&악마는 천사↔악마로 바뀜). HumanoidRootPart 에 용접, 원래 상자는 투명, 빨간 테두리.
- `ReplicatedStorage.PetModels`: 크기 1·효과 없는 모델 도서관 (UI 의 3D 미리보기용).

### 알 (EggVisualService)
- 서버 EggService 가 만든 공 모양 파트는 **투명하게** 하고(판정·`StealPrompt`·이름표는 그대로), **타원체 껍데기 2개(아래 넓은 것 + 위 좁은 것) + 점무늬 3개**를 WeldConstraint 로 자식에 붙임 → 달걀 모양. 크기 등급은 원래 파트 크기를 그대로 따라감.
- 색 = 펫 대표 색, 점 = 펫 둘째 색. 돌연변이: 실버(은색 Foil 반사), 골든(금색 네온 + 반짝), 레인보우(네온 + 클라가 무지개 색 순환), 블룸·스피릿 블룸(분홍/보라 꽃잎 파티클).
- 특별 알(`Special`, 비밀/영원/신성): 하늘로 솟는 빛 기둥(Beam, 알과 함께 움직임) + **지도 어디서나 보이는 "비밀 알!/영원 알!/신성 알!" 이름표**(AlwaysOnTop).
- 부화 중 알(`IncubatingEgg`): 같은 달걀 모양 + `Ready` 가 되면 반짝임.
- 머리 위에 든 알은 클라에서 흔들흔들(내 화면만, `CarryWeld.C0`).

---

## 4. 화면 (설계문서 12장)

화면 배율: 기준 1100×720. HUD 는 최소 0.7배(폰 가로 844×390 에서 메뉴 버튼 57px, 핫바 62px), 창·팝업은 화면 안에 다 들어오게 맞춤.
글꼴 FredokaOne(한글은 로블록스 기본 한글 글꼴로 대체되어 보임), 둥근 모서리·흰 테두리·글자 외곽선.

| 화면 | 위치 | 데이터 | 동작 |
|---|---|---|---|
| 돈 | 상단 가운데 | Attr `Money` (`Format.money`) | 숫자가 올라가는 애니메이션, 크게 벌면 톡 튐 |
| 속도 | 상단 | Attr `Speed` | 바뀌면 톡 |
| 낮/밤 타이머 | 상단 | GameState `Phase`, `PhaseEndsAt` | 낮 노랑 "낮 4:32" / 밤 빨강 "밤 0:08" + 띠 "밤! 알이 30배 빨리 자라요" / 대기 보라 "알 초기화!" |
| 구역 표시 | 상단 아래 | ZoneController, Attr `InSafeZone` | "3. 사막 · 추천 속도 10K" / "안전 구역 (베이스)" |
| 왼쪽 메뉴 | 왼쪽 가운데 | | 도감·선물·상점·펫·설정 (받을 도감 보상 수 / 선물 미수령 빨간 배지) |
| 도감 창 | 가운데 | `indexDiscovered/indexClaimed`, `Index.reward` | 구역 탭 15개, 카드(발견 전 검은 실루엣 "???"), "받기!" → `ClaimIndexReward(petId)`, "모두 받기 (N)" → `ClaimIndexReward("all")`, 구역 진행도·무기 보상 |
| 펫 창 | 가운데 | `pets/equipped/penSlots/petInventoryMax` | 장착 먼저·수입 순, 18마리씩 쪽 넘김, 장착/해제(`EquipPet/UnequipPet`), "최고 펫 장착"(`EquipBest`) |
| 상점 창 | 가운데 | `penLevel/treadmillLevel/trails`, `Upgrades`, `Economy` | 우리/러닝머신 다음 레벨 효과·가격, 트레일 11개(배율·가격·보유/적용 중) → `PurchaseUpgrade` |
| 선물 창 | 가운데 | `freeRewardClaimed` | `ClaimFreeReward` |
| 설정 창 | 가운데 | | 음악/효과음 켜기·끄기 (이번 접속 동안만 기억) |
| 도구 핫바 | 오른쪽 아래 (터치 기기는 점프 버튼 위) | Backpack 의 Tool (`Remotes.ToolKinds`), 곰덫 `Count` | 누르면 들기, 든 채 한 번 더 누르면 `UseTool`, 숫자키 1~9 |
| RUN!! | 가운데 위 | `RunAlert`, `ChaseEnded`, 경비 `TargetUserId`, Attr `CarryingEgg` | 빨간 "RUN!!" 덜덜 + "닭까지 23m", 속도가 모자라면 경고, 베이스 안에서는 "배달 패드에 올라가요!" |
| 잡혔다! | 가운데 | `Caught` | "잡혔다!/맞았다!/덫에 걸렸다!" + 알이 어떻게 됐는지 + 화면 흔들림 + 빨간 비네트 + 머리 위 "퍽!" 별 |
| 자라는 알 | 오른쪽 가운데 | `incubators` + `IncubatingEgg` 파트 `Progress/Required` | 이름·남은 시간·진행 막대(밤엔 보라), 다 자라면 "부화!" → `HatchEgg(uid)`, 2개 이상이면 "모두 부화!", 제목 눌러 접기 |
| 부화 결과 | 가운데 팝업 | `HatchResult` (+ `FusionResult`) | 알 흔들 → 펑 → 카드(희귀도 색 반짝 테두리, 빙글 도는 3D 펫, 빛살, NEW!, `$X/초`) |
| 공지 배너 | 상단 | `Announce` | "ALL EGG RESET!"(노랑), "OO 구역에 OO 알 등장!"(희귀도 색), 밤/낮 — 채팅에도 나옴(AnnounceController) |
| 토스트 | 아래 가운데 | `Notify`, `EggDelivered`, `IndexRewarded`, 2단계 알림 | 성공 초록 / 실패 빨강 / 안내 파랑 |
| 오프라인 수입 | 가운데 팝업 | `OfflineIncome` | "자리 비운 동안 $X 벌었어요! (하루에 $Y)" |

조명: 낮 14시 밝고 따뜻하게 → 밤 22시 어둡고 파랗게 → 새벽 5시半 → 낮 (시계는 앞으로만 2.5초 Tween). 구역마다 안개 색(유령 성 보랏빛 짙게, 화산 주황, 바다 파랑, 눈 하양 …), 밤엔 더 어둡게.

---

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
| `Bgm_base` (음악) | 밝고 신나는 음악 | 베이스·광장·길 |
| `Bgm_forest` … `Bgm_haunted_castle` (음악 15개) | 구역 분위기 (Sounds.luau 설명 참고) | 그 구역에 들어가면 부드럽게 바뀜 |

---

## 6. 스튜디오에서 꼭 볼 것 (체크리스트)

- [ ] 플레이(F5) 시작 시 출력 창에 `[MapBuilder] … 시작 실패` / `[Client] … 시작 실패` / `[PetVisualService]` 경고가 없는지
- [ ] 맵 전체를 위에서 보기: 15개 구역이 길 양옆 번갈아, 표지판이 길 쪽을 보는지, 구역 이름이 크고 추천 속도가 작게 보이는지
- [ ] 둥지 위 알이 **달걀 모양**인지 (공 모양이 아님), 들었을 때 머리 위에서 흔들리는지, 크기 등급별로 커지는지
- [ ] 부모 동물 120마리의 모양·크기·방향(둥지를 보는지), 이름표 겹침
- [ ] 경비가 동물 모양으로 걷는지, 발이 땅에 붙는지 (HipHeight 기준으로 맞춤), 추격·잡힘 판정이 전과 같은지
- [ ] 베이스: 배달 패드에서 배달 → 반짝 + 토스트, 부화 슬롯 위 알, "자라는 알" 패널 시간·부화 버튼, 부화 카드
- [ ] 우리에 장착 펫이 원형으로 서서 통통 튀는지, 장착/해제/Equip Best 하면 1초 안에 바뀌는지
- [ ] 밤이 되면 조명이 부드럽게 어두워지고 밤 벽(빨간 반투명)이 보이는지, 아침에 돌아오는지
- [ ] 유령 성·화산·바다에 들어가면 안개 색이 바뀌는지, 분위기 파티클(눈·꽃잎·거품…)이 그 구역에서만 보이는지
- [ ] 특별 알(비밀/영원/신성): 빛 기둥 + 멀리서도 보이는 이름표 (`/skip` 으로 초기화 반복해서 확인)
- [ ] 기기 에뮬레이터(폰 가로, 태블릿, PC)에서 모든 창이 화면 안에 들어오는지, 버튼이 손가락으로 누르기 충분한지, 핫바가 점프 버튼과 안 겹치는지
- [ ] 한글이 FredokaOne 대신 기본 한글 글꼴로 제대로 보이는지 (네모 깨짐 없는지)
- [ ] 성능: 마이크로프로파일러/메모리 — 파트 약 1만 2천~1만 5천 개(맵 + 펫 + 우리). 폰에서 끊기면 장식 개수(`Visuals.biomes.decor` count)부터 줄이기
- [ ] 소리 ID 를 몇 개 넣고 소리가 나는지, 설정 창 음소거가 되는지

## 7. 알려진 한계 / 다음 할 일

- 2단계 화면 중 **고르기 화면**(퓨전 머신에서 펫 3마리 고르기, 사쿠라 인큐베이터, 제단 제물, 비밀 통로 합성, 퀘스트 패널)은 아직 없음. 지금은 결과 알림(토스트·배너·퓨전 카드)만 있음.
- 사쿠라 인큐베이터·제단·비밀 통로·퀘스트 문 **진짜 모델**은 아직 없음 (수석 `Landmarks` 의 임시 파트가 쓰임).
- 구역 무기(물 방망이·카타나…)와 방망이는 손에 보이는 모양이 없음 (Tool 이 `RequiresHandle = false`). 핫바에는 그림이 있음.
- 설정(음소거)은 저장 안 됨 (저장용 Remote 없음).
- 창 안의 작은 버튼(도감 카드 "받기!", 펫 카드 장착)은 아주 작은 폰에서 44px 보다 조금 작을 수 있음.
- Lune 스모크 테스트(맵·펫 134종·알·우리·경비 서버 생성, 클라 UI 전체 시작·창 열기·클릭)는 선임 작업 폴더에서 돌렸음 — 필요하면 `tests/` 로 옮겨 정식 테스트로 만들 수 있음.
