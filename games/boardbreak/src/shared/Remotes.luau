--!strict
--[[
	Remotes — 송판 깨기 Remote 이름과 속도 제한 (순수 데이터). 설계서 docs/DESIGN.md 7장과 이름이 같아야 합니다.

	- 서버(src/server/Net.luau)가 ReplicatedStorage.Remotes 폴더에 RemoteEvent 를 전부 만듭니다.
	- 클라는 ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(이름) 으로 받아 씁니다.

	치트 방지: 힘·돈·띠·월드를 직접 바꾸는 Remote 는 없습니다. 클라는 "요청"만 보내고 서버가 판정합니다.
	  심사·대결의 "이겼다/합격했다"를 보내는 Remote 도 없습니다 (서버가 ExamState/DuelState 로 알려 줌).

	클라 → 서버 (인자):
	  ClientReady()            화면이 준비됨 → 서버가 Snapshot 을 (다시) 보냄
	  Train()                  아령 1번 들기 (수련 매트 위에서만). 누르고 있으면 클라가 0.22초마다 반복 (초당 4.5번, 서버 한도 5번)
	  Hit(targetId)            물건 1번 치기. targetId = Targets 의 id
	                           심사 중이면 "exam", 대결 중이면 "duel" (심사·대결 송판 치기 — 같은 Remote, 같은 속도 제한)
	  BuyDumbbell()            다음 아령 사기 (순서대로만)
	  StartExam()              승급 심사 시작 (심사대 ExamPad 근처, 다음 띠가 심사 띠일 때 — 힘 조건 없음, 약하면 떨어질 뿐)
	  StartDuel()              시험관 대결 시작 (대결장 DuelArena 근처, 다음 띠가 그 월드 대결 띠(마지막 띠 — Belts.duelOf)일 때)
	  Travel(worldIndex)       열린 월드로 이동 (서버가 순간이동: MapLayout.spawn(world))
	  SetSetting(key, value)   설정 (Config.SETTINGS 의 키, boolean)

	서버 → 클라 (payload):
	  Snapshot(data)                 Types.Snapshot 전체
	  DataUpdate(section, payload)   일부만: "stats" { power, money } · "progress" { dumbbellLevel, belt, world, broken, grandMaster }
	                                 · "passes" { powerBoost, moneyPass, ownedPasses } · "settings" { settings }
	  Notify { kind, text }          알림 한 줄 (kind: "info" | "success" | "error") — 표 하나로 보냄 (첫 게임과 같음)
	  TrainResult { gain, power }
	  HitResult { targetId, damage, hp, hpMax, broken, reward?, reason? }   reason 은 지금 안 씀 (힘 문턱 없음 — 약해도 피해가 들어감)
	  ExamState { phase, broken, total, secondsLeft, belt, boardHp? }      phase = "start"|"progress"|"pass"|"fail"
	  DuelState { phase, mine, theirs, total, world, secondsLeft?, boardHp? } phase = "start"|"progress"|"win"|"lose"
	  ProductGranted { key, kind }
	  LeaderboardUpdate { power = { {name, value, userId} }, money = {...} }   10초마다 서버 전체 (상위 10명)
]]

local Remotes = {
	FOLDER_NAME = "Remotes",

	-- 서버 → 클라
	ToClient = {
		Snapshot = "Snapshot",
		DataUpdate = "DataUpdate",
		Notify = "Notify",
		TrainResult = "TrainResult",
		HitResult = "HitResult",
		ExamState = "ExamState",
		DuelState = "DuelState",
		ProductGranted = "ProductGranted",
		LeaderboardUpdate = "LeaderboardUpdate",
	},

	-- 클라 → 서버 (전부 서버에서 인자 검증 + 속도 제한)
	ToServer = {
		ClientReady = "ClientReady",
		Train = "Train",
		Hit = "Hit",
		BuyDumbbell = "BuyDumbbell",
		StartExam = "StartExam",
		StartDuel = "StartDuel",
		Travel = "Travel",
		SetSetting = "SetSetting",
	},

	-- 심사·대결 송판을 칠 때 Hit 에 보내는 id (Targets 의 id 와 겹치지 않음)
	EXAM_TARGET = "exam",
	DUEL_TARGET = "duel",

	-- 클라 → 서버 속도 제한 (토큰 버킷): burst = 한 번에 허용, perSecond = 초당 회복. 넘는 요청은 버림
	-- 설계서 6장: 아령 들기 초당 5번, 치기 초당 5번까지
	RateLimits = {
		ClientReady = { burst = 3, perSecond = 0.5 },
		Train = { burst = 5, perSecond = 5 },
		Hit = { burst = 5, perSecond = 5 },
		BuyDumbbell = { burst = 3, perSecond = 2 },
		StartExam = { burst = 2, perSecond = 0.5 },
		StartDuel = { burst = 2, perSecond = 0.5 },
		Travel = { burst = 2, perSecond = 1 },
		SetSetting = { burst = 5, perSecond = 2 },
	} :: { [string]: { burst: number, perSecond: number } },
}

return Remotes
