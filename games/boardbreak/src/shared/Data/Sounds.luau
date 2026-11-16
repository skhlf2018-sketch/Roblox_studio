--!strict
--[[
	Sounds — 송판 깨기 소리 목록 (선임, 순수 데이터)

	id 는 첫 게임(src/shared/Data/Sounds.luau)에서 본부장이 스튜디오로 확인한 무료 소리를 다시 씀.
	아직 맞는 소리를 못 고른 것은 0 (조용히 건너뜀) — 본부장이 스튜디오에서 크리에이터 스토어 무료 소리로 채움.
	  재생: src/client/Controllers/SoundController.luau  (SoundController.play("Hit"))
]]

export type SoundDef = {
	id: string,
	volume: number,
	looped: boolean?,
	pitchVariation: number?,
	music: boolean?, -- true 면 "음악" 설정을 따름 (아니면 "효과음")
	speed: number?,
	description: string,
}

local EMPTY = "rbxassetid://0"

local function rbx(id: number?): string
	if id == nil or id == 0 then
		return EMPTY
	end
	return "rbxassetid://" .. tostring(id)
end

local function sfx(id: number?, volume: number, description: string, pitchVariation: number?): SoundDef
	return { id = rbx(id), volume = volume, pitchVariation = pitchVariation, description = description }
end

local function music(id: number?, volume: number, description: string): SoundDef
	return { id = rbx(id), volume = volume, looped = true, music = true, description = description }
end

local Sounds: { [string]: SoundDef } = {
	-- 버튼·창 (첫 게임과 같은 id)
	Click = sfx(127036696152728, 0.5, "버튼 클릭 (짧은 '톡')", 0.08),
	Open = sfx(88442833509532, 0.4, "창 열림 (뿅)", 0.05),
	Close = sfx(73554069341939, 0.35, "창 닫힘 (슉)", 0.05),
	Error = sfx(9119103113, 0.5, "실패 / 힘 부족 (뿡 낮은 소리)"),
	Notify = sfx(127036696152728, 0.4, "작은 알림 (띵)"),
	Purchase = sfx(134810204798705, 0.6, "아령 사기 (차링!)"),
	Coin = sfx(135483737426662, 0.18, "돈 받기 (짤랑, 아주 작게)", 0.12),
	ProductGranted = sfx(4757565956, 0.9, "로벅스 상품 받음 (짠! 팡파레)"),
	-- 수련 (아령 들기)
	Lift = sfx(9120972444, 0.35, "아령 들기 (휙, 작게)", 0.12),
	-- 치기 · 깨기
	Hit = sfx(9120972321, 0.55, "치기 (퍽!)", 0.12),
	HitWeak = sfx(9119103113, 0.35, "힘이 부족해서 튕김 (뿡)", 0.05),
	Break = sfx(74041775202019, 0.7, "물건이 깨짐 (쨍그랑/와장창)", 0.1),
	BreakBig = sfx(9113540599, 0.8, "큰 물건이 깨짐 (쿵 + 반짝)"),
	-- 사장님 결정 18번 "부서질 때 클수록 콰쾅쾅쾅": 큰 물건일수록 아래 층을 여러 번 겹침 (client/BreakFx 가 순서·크기·높낮이를 정함).
	--   본부장이 스튜디오에서 불러와지는 것만 확인함 (소리는 아직 안 들어 봄) — 하나가 안 불러와지면 그 층만 빠짐.
	--   volume 은 기본값 (BreakFx 가 층마다 다시 정함)
	BreakBoom = sfx(138533090376585, 0.9, "큰 폭발 쾅 (Explosion Blast Impact Boom, 3.06초)"),
	BreakStone1 = sfx(114854126016837, 0.8, "돌덩이 깨짐 1 (StoneBlock_Break1, 2.74초)"),
	BreakStone2 = sfx(140038243287227, 0.8, "돌덩이 깨짐 2 (StoneBlock_Break2, 3.44초)"),
	BreakDebris = sfx(94676636060460, 0.6, "와르르 잔해 꼬리 ([SFX] Debris, 2.55초)"),
	WoodCrack = sfx(9126240449, 0.7, "두꺼운 나무 쪼개짐 (Wood Crack Thick Splintering, 3.36초)"),
	-- 심사·대결·띠
	ExamStart = sfx(601149073, 0.6, "승급 심사 시작 (반짝 알림)"),
	DuelStart = sfx(16903690359, 0.6, "시험관 대결 시작 (삐용 신호)"),
	Pass = sfx(4612374495, 0.8, "합격 / 대결 승리 (반짝반짝 상승음)"),
	Fail = sfx(9119103113, 0.6, "불합격 / 대결 패배 (뿡)"),
	BeltUp = sfx(1840076509, 0.85, "띠가 올라감 (빠밤! 팡파레)"),
	Travel = sfx(123796710194563, 0.6, "다른 월드로 이동 (휘리릭)"),
	TutorialStep = sfx(601149073, 0.55, "안내 다음 단계 (반짝 알림)"),
	TutorialDone = sfx(4757565956, 0.85, "안내 끝 (짠!)"),
	Tick = sfx(0, 0.4, "심사 마지막 5초 째깍 (아직 못 고름 — 0)"),

	-- 음악 (월드마다)
	Bgm_world1 = music(84797666595507, 0.3, "월드 1 태권도장 마을 (밝고 신나는 음악)"),
	Bgm_world2 = music(1845532170, 0.3, "월드 2 지구 한 바퀴 (구름 위 꿈결 음악)"),
	Bgm_world3 = music(71997529567005, 0.3, "월드 3 우주 (우주 신스 음)"),
	Bgm_exam = music(96879968020213, 0.4, "심사·대결 중 (긴장 음악)"),
}

return Sounds
