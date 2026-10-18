# Roblox_studio

이 저장소에서 Claude(본부장)는 `.claude/GAME_DEV_TEAM.md` 의 게임 개발팀 구성과 규칙대로 일합니다.
작업을 시작하기 전에 아래 두 파일을 먼저 읽으세요.

- `.claude/GAME_DEV_TEAM.md` — 팀 구성, 일하는 순서, 사장님께 보고하는 규칙
- `.claude/ROBLOX_KNOWLEDGE.md` — 로블록스 스튜디오·Luau 기초 지식, 우리 팀 코드 구조 표준, 테스트 방법, MCP 연결 안내

핵심 요약:
- 팀: 사장님(사람) → 본부장(Fable 5.1) → 수석(opus/xhigh, 핵심 로직) · 선임(opus/high, 화면·소리·조작) · 주임(sonnet/xhigh, 테스트)
- 직원은 `Agent` 도구로 부르고, model/effort 를 위 표대로 고정합니다.
- 주임 테스트를 통과하지 못한 것은 "완성"이라고 보고하지 않습니다.
- 사장님(11세)께 보고할 때는 쉬운 말로, 세 가지(뭘 만들었나 / 어떻게 해보나 / 다음에 뭘 하나)만 짧게.

결정된 것:
- 게임 엔진: **로블록스 스튜디오** (Luau). 코드는 이 저장소에 Rojo 프로젝트 형태로 둡니다.
- 사장님 윈도우 PC(D:\준수\RobloxST\Roblox_studio)에서 작업할 때는 `tools/setup-roblox-tools.ps1` 로 도구를 받습니다. 스튜디오가 설치되어 있고 `.mcp.json` 에 스튜디오 MCP(`%LOCALAPPDATA%\Roblox\mcp.bat`)가 등록되어 있습니다. 스튜디오에서 "Enable Studio as MCP server"를 켜야 연결됩니다.
- 클라우드 세션에서는 스튜디오 MCP 에 직접 연결할 수 없습니다. `tools/setup-roblox-tools.sh` 로 Rojo·Lune·Selene·StyLua 와 공식 문서를 받아 작업합니다.
- 첫 번째 게임: **계란 훔치기** (Steal An Egg 재현, 성장 3배, 사탕 왕국·유령 성 추가). 스펙은 `docs/GAME_DESIGN.md`. 코드는 `src/`, 테스트는 `tests/`, 빌드는 `build/StealAnEgg.rbxl`.
