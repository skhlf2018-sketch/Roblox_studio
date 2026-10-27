--!strict
--[[
	Sounds — 소리 목록 (설계문서 13장). 선임 담당. 순수 데이터.

	ID 는 로블록스 크리에이터 스토어의 **무료 공개 오디오**(Pro Sound Effects, APM Music, Distrokid 등)에서
	본부장이 2026-10-19 에 골라 넣었습니다. 바꾸고 싶으면 id 의 숫자만 바꾸면 됩니다 (0 이면 그 소리는 조용히 건너뜀).
	- volume: 0~1, looped: 반복(배경음), pitchVariation: 재생할 때마다 살짝 다른 높이(같은 소리 질림 방지)
	- 재생: src/client/Controllers/SoundController.luau  (SoundController.play("Pickup"))
]]

export type SoundDef = {
	id: string,
	volume: number,
	looped: boolean?,
	pitchVariation: number?,
	music: boolean?, -- true 면 "음악" 설정을 따름 (아니면 "효과음")
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
	-- 효과음
	Click = sfx(127036696152728, 0.5, "버튼 클릭 (짧은 '톡')", 0.08),
	Open = sfx(88442833509532, 0.4, "창 열림 (뿅)", 0.05),
	Close = sfx(73554069341939, 0.35, "창 닫힘 (슉)", 0.05),
	Pickup = sfx(4612374393, 0.7, "알 줍기 (퐁!)", 0.1),
	RunAlert = sfx(16903690359, 0.8, "RUN!! 경고 (삐용삐용 사이렌 한 번)"),
	Caught = sfx(74041775202019, 0.8, "잡힘 (퍽! + 휘익 날아가는 소리)", 0.05),
	Trap = sfx(9117333878, 0.8, "곰덫 밟음 (철컥!)"),
	Bat = sfx(9120972321, 0.6, "방망이 휘두르기 (붕)", 0.1),
	Deliver = sfx(103516326607012, 0.7, "배달 성공 (띠링~ 상쾌한 성공음)"),
	HatchReady = sfx(601149073, 0.5, "알이 다 자람 (반짝 알림)"),
	Hatch = sfx(9113540599, 0.8, "부화 (빠직 + 반짝반짝)"),
	HatchRare = sfx(4757565956, 0.9, "희귀 펫 부화 (빠직 + 짠! 팡파레)"),
	Coin = sfx(135483737426662, 0.18, "돈 벌기 (짤랑, 아주 작게)", 0.12),
	Purchase = sfx(134810204798705, 0.6, "업그레이드 구매 (차링!)"),
	Error = sfx(9119103113, 0.5, "안 돼요 (뿡 낮은 소리)"),
	Notify = sfx(127036696152728, 0.4, "작은 알림 (띵)"),
	Reward = sfx(4612374495, 0.7, "도감·튜토리얼 보상 받기 (반짝반짝 상승음)"),
	NightBell = sfx(77402059079473, 0.7, "밤 시작 (댕~ 종소리)"),
	DayStart = sfx(725011552, 0.5, "아침 (꼬끼오 또는 밝은 차임)"),
	Reset = sfx(123796710194563, 0.6, "ALL EGG RESET! (휘리릭)"),
	RareEgg = sfx(1840076509, 0.8, "희귀 알 공지 (빠밤! 팡파레)"),
	Offline = sfx(135483737426662, 0.6, "오프라인 수입 팝업 (돈 쏟아지는 소리)"),
	Equip = sfx(4612374393, 0.4, "펫 장착 (뾱)", 0.08),
	-- 2판
	Drop = sfx(9120972444, 0.5, "알 내려놓기 (툭)"),
	ZoneEnter = sfx(1841997734, 0.5, "새 구역 들어감 (휙 + 짠)"),
	TreadmillStep = sfx(127036696152728, 0.25, "러닝머신 걸음 (탁, 작게)", 0.1),
	Sell = sfx(134810204798705, 0.6, "펫 판매 (짤랑짤랑)"),
	-- 2단계 (선임 2차)
	Swing = sfx(9120972444, 0.6, "무기 휘두르기 (휙!)", 0.12),
	Bloom = sfx(4612374495, 0.7, "사쿠라 블룸 (꽃잎 반짝 + 풍경 소리)"),
	SpiritBloom = sfx(128101439168480, 0.9, "스피릿 블룸 (신비로운 합창 + 반짝)"),
	Unlock = sfx(103516326607012, 0.7, "인큐베이터 열림 (철컥 + 반짝)"),
	-- (5판: 퀘스트 QuestStep·GateOpen 소리는 퀘스트와 함께 없앰)
	-- 5판 (선임): 쓰다듬기 · 튜토리얼 (전부 위의 무료 ID 를 다시 씀)
	Pet = sfx(4612374393, 0.55, "펫 쓰다듬기 (뾱 + 반짝, 하트가 날 때)", 0.15),
	TutorialStep = sfx(601149073, 0.55, "튜토리얼 다음 단계 (반짝 알림)"),
	TutorialDone = sfx(4757565956, 0.85, "튜토리얼 끝! $500 (짠! 팡파레 + 색종이)"),

	-- 음악 (반복)
	Chase = music(96879968020213, 0.45, "추격 긴장 음악 (알 들고 있는 동안)"),
	Bgm_base = music(84797666595507, 0.3, "베이스/광장 배경음 (밝고 신나는 음악)"),
	Bgm_forest = music(9112835056, 0.3, "숲 (새소리 + 잔잔한 음악)"),
	Bgm_lake = music(1836935447, 0.3, "호수 (물소리 + 개구리)"),
	Bgm_desert = music(1838006114, 0.3, "사막 (바람 + 아라비안 느낌)"),
	Bgm_jungle = music(9112807051, 0.3, "정글 (북소리 + 벌레 소리)"),
	Bgm_snow = music(103006284758182, 0.3, "눈 (바람 + 방울 소리)"),
	Bgm_volcano = music(9112823552, 0.3, "화산 (용암 끓는 소리)"),
	Bgm_abyss_ocean = music(9112889917, 0.3, "심연의 바다 (물속 웅웅 + 거품)"),
	Bgm_prehistoric = music(1845566969, 0.3, "선사시대 (원시 북 + 공룡 울음 멀리)"),
	Bgm_cosmic = music(71997529567005, 0.3, "코스믹 (우주 신스 음)"),
	Bgm_cherry_blossom = music(1835966836, 0.3, "벚꽃 (동양풍 현악기)"),
	Bgm_titan_temple = music(1848120001, 0.3, "타이탄 사원 (웅장한 고대 음악)"),
	Bgm_angels_demons = music(1848113516, 0.3, "천사 & 악마 (합창 + 어두운 오르간)"),
	Bgm_enchanted_forest = music(9038465993, 0.3, "마법의 숲 (반짝이는 요정 음악)"),
	Bgm_candy_kingdom = music(1835943156, 0.3, "사탕 왕국 (통통 튀는 귀여운 음악)"),
	Bgm_haunted_castle = music(1836013838, 0.3, "유령 성 (으스스한 오르간 + 바람)"),
}

return Sounds
