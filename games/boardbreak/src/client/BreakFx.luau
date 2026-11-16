--!strict
--[[
	BreakFx — 깨질 때 소리·화면 흔들림 계획 (선임, 사장님 결정 18번: "부서질 때 클수록 콰쾅쾅쾅 소리"). 순수 계산 — 재생은 SoundController,
	흔들림은 BreakController. 내가 깬 것만 (물건 체력은 플레이어마다 따로 — 서버가 HitResult 를 친 사람에게만 보냄).

	t = 물건이 사다리에서 몇 번째인가 (Targets.list 순번 1…41 → 0…1, 솜 0 · 우주 1) — 솜에서 우주까지 꾸준히 커짐.
	  쾅 수      booms = 1 + round(t × (BOOM_MAX − 1))         솜 1 (오늘 그대로 "쨍") → 우주 5 ("콰쾅쾅쾅쾅")
	  높낮이     pitch = 1 − 0.45 t                            (낮아짐. 쾅마다 6% 씩 더 낮게)
	  크기       첫 쾅 0.7 + 0.3 t, 다음 쾅마다 × 0.78           (뒤로 갈수록 작게 → 콰-쾅-쾅-쾅, 같은 소리 반복이 아님)
	  간격       0.2 − 0.08 t 초 (0.2 → 0.12), 쾅마다 소리를 바꿔 가며 (돌 깨짐 1 · 2 · 나무 쪼개짐 · 돌 1)
	  첫 소리    t < 0.25 오늘의 Break (쨍그랑) · < 0.5 BreakBig (쿵) · 그 위 BreakBoom (폭발 쾅)
	  꼬리       t ≥ 0.7 이면 마지막 쾅 뒤에 BreakDebris (와르르)
	  전체 크기  모든 층 볼륨 합 ≤ LOUDNESS_CAP (넘으면 같은 비율로 줄임 — 깨짐은 드물지만 겹쳐도 찢어지지 않게)
	  흔들림     각도 0.1 + 1.9 t^1.5 도 · 0.12 + 0.38 t 초 (솜 아주 살짝 → 행성 세게·짧게). 저사양 설정이면 0
	소리 id 하나가 안 불러와지면 그 층만 빠짐 (SoundController.playLayer).
	공개: progress(id) · plan(id, lowGraphics?) · BOOM_MAX · LOUDNESS_CAP
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Targets = require(ReplicatedStorage.Shared.Data.Targets)

local BreakFx = {}

BreakFx.BOOM_MAX = 5
BreakFx.LOUDNESS_CAP = 3.6
BreakFx.GAP_MAX = 0.2
BreakFx.GAP_MIN = 0.12
BreakFx.FOLLOW = { "BreakStone1", "BreakStone2", "WoodCrack", "BreakStone1" } -- 2번째 쾅부터 돌아가며

export type Layer = { sound: string, delay: number, volume: number, speed: number }
export type Plan = {
	t: number,
	booms: number,
	pitch: number,
	volume: number, -- 모든 층 볼륨 합
	layers: { Layer },
	shake: { angle: number, seconds: number },
}

-- 0 (솜) … 1 (우주). 모르는 id 는 nil
function BreakFx.progress(id: string): number?
	local target = Targets.get(id)
	if not target then
		return nil
	end
	local n = #Targets.list
	return if n > 1 then (target.index - 1) / (n - 1) else 0
end

function BreakFx.plan(id: string, lowGraphics: boolean?): Plan
	local t = math.clamp(BreakFx.progress(id) or 0, 0, 1)
	local booms = 1 + math.floor(t * (BreakFx.BOOM_MAX - 1) + 0.5)
	local pitch = 1 - 0.45 * t
	local first = 0.7 + 0.3 * t
	local gap = BreakFx.GAP_MAX - (BreakFx.GAP_MAX - BreakFx.GAP_MIN) * t
	local layers: { Layer } = {}
	local firstSound = if t < 0.25 then "Break" elseif t < 0.5 then "BreakBig" else "BreakBoom"
	for k = 1, booms do
		table.insert(layers, {
			sound = if k == 1 then firstSound else BreakFx.FOLLOW[(k - 2) % #BreakFx.FOLLOW + 1],
			delay = (k - 1) * gap,
			volume = first * 0.78 ^ (k - 1),
			speed = pitch * (1 - 0.06 * (k - 1)),
		})
	end
	if t >= 0.7 then
		table.insert(layers, { sound = "BreakDebris", delay = booms * gap, volume = 0.45 * first, speed = pitch })
	end
	local sum = 0
	for _, l in layers do
		sum += l.volume
	end
	if sum > BreakFx.LOUDNESS_CAP then
		local k = BreakFx.LOUDNESS_CAP / sum
		for _, l in layers do
			l.volume *= k
		end
		sum = BreakFx.LOUDNESS_CAP
	end
	return {
		t = t,
		booms = booms,
		pitch = pitch,
		volume = sum,
		layers = layers,
		shake = {
			angle = if lowGraphics then 0 else 0.1 + 1.9 * t ^ 1.5,
			seconds = if lowGraphics then 0 else 0.12 + 0.38 * t,
		},
	}
end

return BreakFx
