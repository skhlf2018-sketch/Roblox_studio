# 계란 훔치기 (StealAnEgg)

로블록스 "Steal An Egg" 를 규칙·숫자 그대로 재현한 우리 버전. 스펙은 `docs/GAME_DESIGN.md` 하나뿐입니다.
Remote/Attribute/태그 목록은 `docs/REMOTES.md`.

## 폴더

```
default.project.json   Rojo 프로젝트 (emitLegacyScripts=false → *.server/*.client.luau 는 RunContext 가 있는 Script)
src/shared/   → ReplicatedStorage.Shared   데이터표(Data/), 순수 로직(Economy, SpeedMath, EggRules, EggRoll, Cycle ...)
src/client/   → ReplicatedStorage.Client   클라 진입점 Main.client.luau (RunContext=Client) + Controllers
src/server/   → ServerScriptService.Server 서버 진입점 Main.server.luau + Services/ + Logic/(순수 로직) + Util/
tests/        Lune 테스트 (로블록스 없이 순수 로직만)
```

## 명령 (저장소 루트에서, 도구는 tools/setup-roblox-tools.* 로 설치)

```powershell
rojo build default.project.json -o build/StealAnEgg.rbxl   # 스튜디오에서 열 파일 만들기
rojo serve                                                # 스튜디오 Rojo 플러그인으로 실시간 동기화
selene src                                                # 린트
stylua --check src tests                                  # 포맷 검사 (고치려면 stylua src tests)
lune run tests/run.luau                                   # 순수 로직 테스트
lune run tests/sim_progress.luau                          # 밸런스 리포트 (구역별 추천 속도 도달 시간, 테스트 아님)
lune run tests/sim_progress.luau sweep                    #   러닝머신 배율 바꿔 보기 / whatif = 도감 속도 보상 공식 바꿔 보기
```

## 스튜디오에서 해보기

1. `build/StealAnEgg.rbxl` 열기 → 플레이(F5).
2. 저장을 시험하려면: 게임을 게시하고 게임 설정 > 보안 > "Studio에서 API 서비스 접근 허용" 켜기. 안 켜면 "메모리 모드"(저장 안 됨) 경고가 뜨고 게임은 그대로 돌아갑니다.
3. 스튜디오 전용 채팅 명령: `/money 1e9`, `/speed 1e9`, `/skip`(낮/밤 넘기기), `/grow`(부화 슬롯 알 다 키우기), `/trap 5`,
   `/crystal 5`(사쿠라 크리스탈), `/pet crane 3`(펫 바로 받기 — 퓨전·제단·합성 시험), `/quests`(마법의 숲 퀘스트 전부 끝내기).
   `Config.DEV_USER_IDS` 에 UserId 를 넣으면 그 사람만 (실서버에서도) 쓸 수 있음.
4. 낮 길이를 줄이려면 Workspace 에 숫자 Attribute `DebugDaySeconds` 추가 (스튜디오에서만 적용).

## 게시할 때 꼭 할 것

- **Game Settings > Places 에서 Max Players 를 7 로 설정.** (`default.project.json` 의 `Players.MaxPlayers` 는 읽기 전용이라 적용되지 않음.)
  베이스가 7칸이라 8번째 사람은 베이스 없이 들어오고(배달·러닝머신 불가), 누가 나가면 그때 베이스를 받습니다.
- 저장을 켜려면 게임 설정 > 보안 > "Studio에서 API 서비스 접근 허용" (스튜디오 테스트용).
