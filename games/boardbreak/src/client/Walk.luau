--!strict
--[[
	Walk — 내 캐릭터 자리 · 걸어가기 도우미 (선임)
	  Walk.root()                         → HumanoidRootPart?
	  Walk.flatDistance(pos)              → 내 캐릭터에서 pos 까지 수평 거리 (캐릭터 없으면 math.huge)
	  Walk.to(pos, within, onArrive)      → pos 로 걸어감 (Humanoid:MoveTo). 도착해서 within 안이면 onArrive()
	                                         이미 within 안이면 바로 onArrive. 걷다가 다른 곳을 누르면 앞의 것은 취소.
	물건을 멀리서 눌렀을 때 · "심사 보기"를 심사대 밖에서 눌렀을 때 씀 (서버는 거리를 다시 검사).
  큰 월드(사장님 결정 13번): MoveTo 8초 제한에 걸리면 다시 걸음 · 도착 여유 2 × Walk.scale() (월드·몸 배율 중 큰 것).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapLayout = require(ReplicatedStorage.Shared.Data.MapLayout)

local Walk = {}

Walk.MAX_LEGS = 12 -- MoveTo 다시 걸기 상한 (8초 × 12 = 96초)

local walkId = 0

-- 도착 여유에 곱하는 배율: 지금 월드 배율과 내 몸 배율 중 큰 것 (Attr 만 읽음 — State 를 안 불러서 순환 없음)
function Walk.scale(): number
	local lp = Players.LocalPlayer
	local body = lp:GetAttribute("BodyScale")
	local world = lp:GetAttribute("CurrentWorld")
	local ws = if type(world) == "number" then MapLayout.worldScale(world) else 1
	return math.max(ws, if type(body) == "number" then body else 1)
end

function Walk.root(): BasePart?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function Walk.humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

function Walk.flatDistance(pos: Vector3): number
	local root = Walk.root()
	if not root then
		return math.huge
	end
	local p = root.CFrame.Position
	local dx, dz = p.X - pos.X, p.Z - pos.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Walk.to(pos: Vector3, within: number, onArrive: () -> ()): boolean
	walkId += 1
	local my = walkId
	if Walk.flatDistance(pos) <= within then
		onArrive()
		return true
	end
	local humanoid = Walk.humanoid()
	if not humanoid then
		return false
	end
	humanoid:MoveTo(pos)
	-- Humanoid:MoveTo 는 8초가 지나면 저절로 멈춤 → 큰 월드(길 수천 스터드)에서는 아직 멀면 다시 걸음 (최대 MAX_LEGS 번)
	local legs = 1
	local slack = 2 * Walk.scale()
	local conn: RBXScriptConnection? = nil
	conn = humanoid.MoveToFinished:Connect(function()
		if walkId ~= my then
			local c = conn
			if c then
				c:Disconnect()
			end
			return
		end
		local d = Walk.flatDistance(pos)
		if d > within + slack and legs < Walk.MAX_LEGS and humanoid.Parent ~= nil and humanoid.Health > 0 then
			legs += 1
			humanoid:MoveTo(pos)
			return
		end
		local c = conn
		if c then
			c:Disconnect()
		end
		if d <= within + slack then
			onArrive()
		end
	end)
	return false
end

function Walk.cancel()
	walkId += 1
end

return Walk
