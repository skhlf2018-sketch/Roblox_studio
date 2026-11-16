--!strict
--[[
	Lift — 팔 움직이기 (선임). 애니메이션 에셋 없이 캐릭터 팔 Motor6D 의 C0 를 잠깐 돌렸다가 원래대로.
	  Animator·걷기 애니메이션은 Transform 을 쓰고 우리는 C0 만 바꾸므로 서로 싸우지 않음 (들기 중에만 바꾸고 끝나면 원래 C0).
	  R15: RightUpperArm.RightShoulder · RightLowerArm.RightElbow (+ 왼쪽) / R6: Torso["Right Shoulder"] (+ Left)
	  Lift.play(character, kind)  kind: "one" (한 손 들기) | "two" (두 손 들기) | "chop" (내리치기)
	  Lift.step(dt)               Heartbeat 에서 부름 (진행 중인 동작 전부)
	  Lift.isPlaying(character) · Lift.reset(character) · Lift.DURATION · Lift.restOf(motor)
	  몸이 커져도 (사장님 결정 13번 — 서버가 몸 크기를 바꾸면 관절 C0 도 바뀜) 쉬는 C0 를 매 프레임 R15 RigAttachment 에서 다시 읽어서
	  들기 도중에 커져도 팔이 몸에서 떨어지지 않고, 끝나면 새 크기 자리로 돌아감 (R6 은 기억한 C0 × 배율 비율).
	클라에서 바꾼 C0 는 서버로 복제되지 않으므로, 다른 플레이어 팔은 각 클라가 복제된 Attribute(Power 증가)를 보고
	같은 동작을 자기 화면에서 다시 그림 (TrainController). 사범님은 서버가 만든 모델이라 DuelState 로 각 클라가 그림.
]]

local Lift = {}

Lift.DURATION = 0.25

type Joint = { motor: Motor6D, base: CFrame, role: string }
type Play = { character: Model, kind: string, t: number, queued: boolean, joints: { Joint } }

local bases: { [Motor6D]: { cf: CFrame, scale: number } } = setmetatable({}, { __mode = "k" }) :: any
local playing: { [Model]: Play } = {}

local function motor(parent: Instance?, name: string): Motor6D?
	local m = parent and parent:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

-- 관절의 "쉬는" C0. R15 는 Part0 의 RigAttachment (몸이 커지면 엔진이 Attachment 와 C0 를 같이 다시 계산 — 서버가
--   몸을 키워도 들기 동작이 옛 크기 C0 로 되돌아가지 않음, 사장님 결정 13번). Attachment 가 없으면 처음 본 C0 를 기억.
local function restOf(m: Motor6D): CFrame
	local p0 = m.Part0
	local a = p0 and p0:FindFirstChild(m.Name .. "RigAttachment")
	if a and a:IsA("Attachment") then
		return a.CFrame
	end
	-- R6 (Attachment 없음): 처음 본 C0 를 그때 몸 배율과 함께 기억 → 배율이 바뀌면 자리만 그 비율로 (Model:ScaleTo 와 같게)
	local model = m:FindFirstAncestorWhichIsA("Model")
	local raw = model and model:GetAttribute("VisualScale")
	local scale = if type(raw) == "number" and raw > 0 then raw else 1
	local entry = bases[m]
	if not entry then
		entry = { cf = m.C0, scale = scale }
		bases[m] = entry
	end
	if entry.scale ~= scale then
		local k = scale / entry.scale
		return CFrame.new(entry.cf.Position * k) * entry.cf.Rotation
	end
	return entry.cf
end
Lift.restOf = restOf

-- 캐릭터의 팔 관절 (R15 우선, 없으면 R6)
function Lift.joints(character: Model): { Joint }
	local list: { Joint } = {}
	local function add(m: Motor6D?, role: string)
		if m then
			table.insert(list, { motor = m, base = restOf(m), role = role })
		end
	end
	local rs = motor(character:FindFirstChild("RightUpperArm"), "RightShoulder")
	if rs then
		add(rs, "RS")
		add(motor(character:FindFirstChild("RightLowerArm"), "RightElbow"), "RE")
		add(motor(character:FindFirstChild("LeftUpperArm"), "LeftShoulder"), "LS")
		add(motor(character:FindFirstChild("LeftLowerArm"), "LeftElbow"), "LE")
		return list
	end
	local torso = character:FindFirstChild("Torso")
	add(motor(torso, "Right Shoulder"), "RS6")
	add(motor(torso, "Left Shoulder"), "LS6")
	return list
end

-- u: 0 → 1 (동작 진행). 각 관절의 추가 회전
local function pose(kind: string, role: string, u: number): CFrame?
	local p = math.sin(math.pi * u) -- 0 → 1 → 0
	if kind == "chop" then
		-- 오른팔을 머리 위로 올렸다가 앞으로 내리침 (앞쪽 = -Z, X 축 + 회전이 앞으로 올림)
		local up = if u < 0.5 then u / 0.5 else 1 - (u - 0.5) / 0.5
		if role == "RS" then
			return CFrame.Angles(2.6 * up, 0, 0)
		elseif role == "RE" then
			return CFrame.Angles(0.6 * up, 0, 0)
		elseif role == "RS6" then
			return CFrame.Angles(0, 0, 2.6 * up)
		end
		return nil
	end
	local right = role == "RS" or role == "RE" or role == "RS6"
	if not right and kind ~= "two" then
		return nil
	end
	-- 아래 → 가슴 (팔꿈치 굽힘) → 머리 위 (팔 쭉) → 아래
	local shoulder = 2.7 * p
	local elbow = 1.7 * math.sin(math.pi * p)
	if role == "RS" or role == "LS" then
		return CFrame.Angles(shoulder, 0, 0)
	elseif role == "RE" or role == "LE" then
		return CFrame.Angles(elbow, 0, 0)
	elseif role == "RS6" then
		-- R6 오른 어깨 C0 는 축이 옆을 봄: Z 축 + 회전이 앞으로 올림
		return CFrame.Angles(0, 0, shoulder)
	elseif role == "LS6" then
		return CFrame.Angles(0, 0, -shoulder)
	end
	return nil
end

local function apply(play: Play, u: number)
	for _, j in play.joints do
		if j.motor.Parent then
			-- 쉬는 자리는 매번 다시 읽음 (들기 도중에 몸이 커져도 팔이 몸에서 안 떨어짐)
			j.base = restOf(j.motor)
			local extra = pose(play.kind, j.role, u)
			j.motor.C0 = if extra then j.base * extra else j.base
		end
	end
end

function Lift.reset(character: Model)
	local play = playing[character]
	playing[character] = nil
	if play then
		for _, j in play.joints do
			j.motor.C0 = restOf(j.motor)
		end
	end
end

function Lift.isPlaying(character: Model): boolean
	return playing[character] ~= nil
end

-- 한 번 들기 (0.25초 왕복). 이미 하는 중이면 끝나고 한 번 더 (누르고 있으면 계속 반복)
function Lift.play(character: Model?, kind: string?): boolean
	if not character then
		return false
	end
	local existing = playing[character]
	if existing then
		if existing.t > Lift.DURATION * 0.4 then
			existing.queued = true
		end
		return true
	end
	local joints = Lift.joints(character)
	if #joints == 0 then
		return false
	end
	playing[character] = { character = character, kind = kind or "one", t = 0, queued = false, joints = joints }
	return true
end

function Lift.step(dt: number)
	for character, play in playing do
		play.t += dt
		if not character.Parent then
			playing[character] = nil
		elseif play.t >= Lift.DURATION then
			if play.queued then
				play.queued = false
				play.t = 0
				apply(play, 0)
			else
				Lift.reset(character)
			end
		else
			apply(play, play.t / Lift.DURATION)
		end
	end
end

return Lift
