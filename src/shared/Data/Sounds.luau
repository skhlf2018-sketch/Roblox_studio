--!strict
--[[
	Sounds — 소리 목록 (설계문서 13장). 선임 담당. 순수 데이터.

	사장님이 할 일: 각 줄의 id 를 "rbxassetid://숫자" 로 바꾸기만 하면 됩니다.
	  (Creator Store 오디오에서 고른 뒤 숫자 복사. 0 이면 그 소리는 조용히 건너뜀)
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

local function sfx(volume: number, description: string, pitchVariation: number?): SoundDef
	return { id = EMPTY, volume = volume, pitchVariation = pitchVariation, description = description }
end

local function music(volume: number, description: string): SoundDef
	return { id = EMPTY, volume = volume, looped = true, music = true, description = description }
end

local Sounds: { [string]: SoundDef } = {
	-- 효과음
	Click = sfx(0.5, "버튼 클릭 (짧은 '톡')", 0.08),
	Open = sfx(0.4, "창 열림 (뿅)", 0.05),
	Close = sfx(0.35, "창 닫힘 (슉)", 0.05),
	Pickup = sfx(0.7, "알 줍기 (퐁!)", 0.1),
	RunAlert = sfx(0.8, "RUN!! 경고 (삐용삐용 사이렌 한 번)"),
	Caught = sfx(0.8, "잡힘 (퍽! + 휘익 날아가는 소리)", 0.05),
	Trap = sfx(0.8, "곰덫 밟음 (철컥!)"),
	Bat = sfx(0.6, "방망이 휘두르기 (붕)", 0.1),
	Deliver = sfx(0.7, "배달 성공 (띠링~ 상쾌한 성공음)"),
	HatchReady = sfx(0.5, "알이 다 자람 (반짝 알림)"),
	Hatch = sfx(0.8, "부화 (빠직 + 반짝반짝)"),
	HatchRare = sfx(0.9, "희귀 펫 부화 (빠직 + 짠! 팡파레)"),
	Coin = sfx(0.18, "돈 벌기 (짤랑, 아주 작게)", 0.12),
	Purchase = sfx(0.6, "업그레이드 구매 (차링!)"),
	Error = sfx(0.5, "안 돼요 (뿡 낮은 소리)"),
	Notify = sfx(0.4, "작은 알림 (띵)"),
	Reward = sfx(0.7, "도감/무료 보상 받기 (반짝반짝 상승음)"),
	NightBell = sfx(0.7, "밤 시작 (댕~ 종소리)"),
	DayStart = sfx(0.5, "아침 (꼬끼오 또는 밝은 차임)"),
	Reset = sfx(0.6, "ALL EGG RESET! (휘리릭)"),
	RareEgg = sfx(0.8, "희귀 알 공지 (빠밤! 팡파레)"),
	Offline = sfx(0.6, "오프라인 수입 팝업 (돈 쏟아지는 소리)"),
	Equip = sfx(0.4, "펫 장착 (뾱)", 0.08),
	Fusion = sfx(0.8, "퓨전 머신 (윙윙~ 펑!)"),

	-- 음악 (반복)
	Chase = music(0.45, "추격 긴장 음악 (알 들고 있는 동안)"),
	Bgm_base = music(0.3, "베이스/광장 배경음 (밝고 신나는 음악)"),
	Bgm_forest = music(0.3, "숲 (새소리 + 잔잔한 음악)"),
	Bgm_lake = music(0.3, "호수 (물소리 + 개구리)"),
	Bgm_desert = music(0.3, "사막 (바람 + 아라비안 느낌)"),
	Bgm_jungle = music(0.3, "정글 (북소리 + 벌레 소리)"),
	Bgm_snow = music(0.3, "눈 (바람 + 방울 소리)"),
	Bgm_volcano = music(0.3, "화산 (용암 끓는 소리)"),
	Bgm_abyss_ocean = music(0.3, "심연의 바다 (물속 웅웅 + 거품)"),
	Bgm_prehistoric = music(0.3, "선사시대 (원시 북 + 공룡 울음 멀리)"),
	Bgm_cosmic = music(0.3, "코스믹 (우주 신스 음)"),
	Bgm_cherry_blossom = music(0.3, "벚꽃 (동양풍 현악기)"),
	Bgm_titan_temple = music(0.3, "타이탄 사원 (웅장한 고대 음악)"),
	Bgm_angels_demons = music(0.3, "천사 & 악마 (합창 + 어두운 오르간)"),
	Bgm_enchanted_forest = music(0.3, "마법의 숲 (반짝이는 요정 음악)"),
	Bgm_candy_kingdom = music(0.3, "사탕 왕국 (통통 튀는 귀여운 음악)"),
	Bgm_haunted_castle = music(0.3, "유령 성 (으스스한 오르간 + 바람)"),
}

return Sounds
