# 로블록스 스튜디오 기초 지식 (팀 공용 메모)

본부장이 2026-10-18에 로블록스 공식 문서 저장소(github.com/Roblox/creator-docs, content/en-us, md 파일 1,028개 · 엔진 클래스 레퍼런스 626개)를 받아 읽고 정리한 내용입니다.
직원(수석·선임·주임)에게 일을 줄 때 이 파일을 함께 읽게 합니다.

## 1. 큰 그림

- 로블록스 게임은 **Luau** 언어로 만듭니다. Lua 5.1 기반이고, 타입 표기(`--!strict`), 문자열 보간(`` `{x}` ``), 일반화 반복(`for k, v in t do`)이 추가되어 있습니다. 배열은 1부터 시작합니다.
- 게임은 **처음부터 멀티플레이어**입니다. **서버**가 진짜 상태를 갖고, 각 플레이어의 **클라이언트**가 그 복사본을 받아 그립니다. 서버가 항상 최종 판정자여야 합니다(점수·아이템·승패는 서버에서 결정).
- 게임의 모든 것은 **데이터 모델**이라는 트리로 표현됩니다. 모든 객체는 `Instance`를 상속합니다.

## 2. 데이터 모델의 주요 컨테이너

| 컨테이너 | 역할 | 누가 보나 |
|---|---|---|
| `Workspace` | 3D 세계에 보이는 모든 것(파트, 모델, 지형, 카메라) | 서버+클라 |
| `Lighting`, `SoundService` | 조명·하늘·소리 설정 | 서버+클라 |
| `ReplicatedStorage` | 서버와 클라가 **같이 쓰는** 모듈·RemoteEvent 보관 | 서버+클라 |
| `ReplicatedFirst` | 접속 직후 가장 먼저 복제(로딩 화면용) | 서버+클라 |
| `ServerScriptService` | 서버 전용 스크립트 (클라에 절대 안 보임 = 치트 방지) | 서버만 |
| `ServerStorage` | 서버 전용 보관(맵, 복제용 모델). 여기 스크립트는 실행 안 됨 | 서버만 |
| `StarterPlayer/StarterPlayerScripts` | 플레이어 접속 시 각 클라에 복사되는 스크립트 | 클라 |
| `StarterPlayer/StarterCharacterScripts` | 캐릭터 스폰 시 캐릭터에 복사 | 클라 |
| `StarterGui` | 각 플레이어의 PlayerGui로 복사되는 UI | 클라 |
| `StarterPack` | 시작 아이템(Tool) | 클라 |
| `Players` | 접속한 `Player` 객체들 | 서버+클라 |

- 파트: `Part`(블록·공·원기둥·쐐기), `MeshPart`(외부 3D 메시), `TrussPart`(사다리). 기본적으로 물리 시뮬레이션 대상.
- 정리용: `Folder`(의미 없는 묶음), `Model`(파트 묶음).

## 3. 스크립트 종류와 위치 (가장 중요)

- `Script`: `RunContext` 속성에 따라 서버/클라에서 실행. 기본 `Legacy` = 서버 전용, `ServerScriptService`나 `Workspace`에 있어야 실행.
- `LocalScript`: 클라 전용. `Starter*` 컨테이너에만.
- `ModuleScript`: `require()`로 불러 쓰는 재사용 코드. 혼자서는 실행 안 됨.

**공식 권장 구조** (우리 팀 표준으로 채택):
- 서버 진입점 1개: `ServerScriptService`에 `Script` (RunContext=Server) 하나.
- 클라 진입점 1개: `ReplicatedStorage`에 `Script` (RunContext=Client) 하나.
- 나머지 로직은 전부 `ModuleScript`로 만들고, 각 모듈에 `start()` 함수를 둔다. 진입점이 모듈들을 `require`해서 `start()`를 호출.
- 공유 코드는 `ReplicatedStorage`의 ModuleScript.
- `Workspace`의 파트에 스크립트를 직접 붙이지 말고, 파트에 **태그**(`CollectionService`)를 붙여 모듈 하나에서 처리.

```lua
--!strict
-- 서버 진입점 예시
local ServerScriptService = game:GetService("ServerScriptService")
local RoundManager = require(ServerScriptService.Server.RoundManager)
RoundManager.start()
```

## 4. 서버 ↔ 클라 통신

`ReplicatedStorage`에 `RemoteEvent`/`RemoteFunction`을 두고 사용.

| 방향 | 보내는 쪽 | 받는 쪽 |
|---|---|---|
| 클라→서버 | `remote:FireServer(args)` | `remote.OnServerEvent:Connect(function(player, args))` |
| 서버→클라 1명 | `remote:FireClient(player, args)` | `remote.OnClientEvent:Connect(function(args))` |
| 서버→전체 | `remote:FireAllClients(args)` | 같음 |
| 클라→서버→답장 | `RemoteFunction:InvokeServer(args)` | `remoteFn.OnServerInvoke = function(player, args)` |

- 서버 핸들러의 첫 인자는 항상 `player`. **클라가 보낸 값은 절대 믿지 말고 서버에서 검증**.
- 서버→클라 `InvokeClient`는 클라가 응답 안 하면 서버가 멈출 수 있으니 쓰지 않는다.
- 매 프레임 바뀌는 비중요 데이터는 `UnreliableRemoteEvent`.

## 5. 자주 쓰는 API 요약

- 서비스: `game:GetService("Players")`, `"ReplicatedStorage"`, `"ServerScriptService"`, `"Workspace"`, `"RunService"`, `"UserInputService"`, `"TweenService"`, `"CollectionService"`, `"DataStoreService"`.
- 플레이어: `Players.PlayerAdded:Connect(fn)`, `player.CharacterAdded`, `character:FindFirstChildOfClass("Humanoid")`, `humanoid.Died`, `Players.LocalPlayer`(클라만).
- 기다리기: `task.wait(초)`, `task.spawn(fn)`, `task.delay(초, fn)`. 옛 `wait()`는 쓰지 않음.
- 충돌: `part.Touched:Connect(function(hit) ... end)` + 디바운스.
- 로그: `print()`, `warn()`. 출력(Output) 창에서 확인.
- 저장: `DataStoreService` (스튜디오에서 API 접근 허용 설정 필요, `pcall`로 감쌀 것).
- UI: `ScreenGui` > `Frame`/`TextLabel`/`TextButton`, `UDim2` 크기·위치. `StarterGui`에 넣음.
- 리더보드: 서버에서 `player`에 `Folder` 이름 `leaderstats` 만들고 `IntValue` 추가.

## 6. 우리 팀의 작업 방식 (클라우드 세션 기준)

이 세션은 클라우드 컨테이너에서 돌아갑니다. 로블록스 스튜디오는 사장님 컴퓨터(윈도우/맥)에 있습니다. 둘을 잇는 방법:

### 6-1. 코드는 Rojo 프로젝트로 관리
- 저장소에 `default.project.json` + `src/` 폴더 구조로 Luau 파일을 둡니다.
- 파일 이름 규칙: `*.server.luau`(Script, 서버), `*.client.luau`(LocalScript), `*.luau`(ModuleScript), 폴더에 `init.luau`면 그 폴더가 모듈.
- `rojo build -o game.rbxl`로 스튜디오에서 열 수 있는 파일을 만들 수 있습니다(이 환경에서 가능).
- 사장님 컴퓨터에서는 Rojo 플러그인(Creator Store `Rojo`)을 스튜디오에 설치하고 `rojo serve`로 실시간 동기화하거나, 만들어진 `.rbxl`을 그냥 열면 됩니다.

### 6-2. 테스트
- 순수 로직(점수 계산, 규칙, 상태 기계)은 **Lune**으로 이 환경에서 바로 돌려 자동 테스트합니다. (`lune run tests/xxx.luau`)
- 로블록스 API가 필요한 부분(파트, 캐릭터, UI)은 스튜디오에서 플레이 테스트해야 합니다 → 사장님께 "이렇게 해보세요" 안내 + 체크리스트.
- 코드 검사: `selene`(린트), `stylua`(포맷).

### 6-3. 스튜디오 MCP 서버 (최신 스튜디오에 내장)
- 스튜디오 **Assistant → … → Manage MCP Servers → Enable Studio as MCP server** 로 켭니다.
- 연결은 `stdio` 방식이라 **스튜디오와 같은 컴퓨터에서 돌아가는 MCP 클라이언트**만 붙을 수 있습니다. 즉 **이 클라우드 세션에서는 직접 연결이 안 됩니다.**
- 사장님 컴퓨터에 Claude Code(데스크톱 앱 또는 CLI)를 설치하면 Quick connect 목록에 떠서 바로 연결됩니다. 그러면 본부장이 스크립트 읽기·쓰기(`script_read`, `multi_edit`), 코드 실행(`execute_luau`), 플레이 시작/정지(`start_stop_play`), 콘솔 읽기, 화면 캡처(`screen_capture`), 캐릭터 이동·키 입력 시뮬레이션까지 직접 할 수 있습니다.
- 윈도우 설정 예: `cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat`, 맥: `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`.

## 7. 네트워크 메모 (이 클라우드 환경)
- `create.roblox.com`, `rojo.space`, `api.github.com`은 네트워크 정책에 막혀 있음(403).
- `github.com`, `raw.githubusercontent.com`은 열려 있음 → 공식 문서 git clone, 도구 바이너리 다운로드 가능.
- 다시 받으려면 `tools/setup-roblox-tools.sh` 실행.

## 8. 공식 문서 찾아보기
- 로컬 사본 경로(설치 스크립트 실행 후): `$SCRATCH/roblox-docs/creator-docs/content/en-us/`
  - 언어: `luau/`, 스크립팅: `scripting/`, 데이터모델·클라-서버: `projects/`, 스튜디오 사용법: `studio/`
  - API 레퍼런스: `reference/engine/classes/*.yaml`, `reference/engine/enums/`, `reference/engine/datatypes/`
  - 튜토리얼: `tutorials/use-case-tutorials/`, `tutorials/first-experience/`, 교육 커리큘럼: `education/`
- 클래스 하나 찾기: `grep -ril "name: Humanoid$" reference/engine/classes` 식으로 검색.
