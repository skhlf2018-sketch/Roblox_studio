--!strict
--[[
	Walk — 내 캐릭터 자리 · 걸어가기 도우미 (선임)
	  Walk.root()                         → HumanoidRootPart?
	  Walk.flatDistance(pos)              → 내 캐릭터에서 pos 까지 수평 거리 (캐릭터 없으면 math.huge)
	  Walk.to(pos, within, onArrive)      → pos 로 걸어감 (Humanoid:MoveTo). 도착해서 within 안이면 onArrive()
	                                         이미 within 안이면 바로 onArrive. 걷다가 다른 곳을 누르면 앞의 것은 취소.
	물건을 멀리서 눌렀을 때 · "심사 보기"를 심사대 밖에서 눌렀을 때 씀 (서버는 거리를 다시 검사).
]]

local Players = game:GetService("Players")

local Walk = {}

local walkId = 0

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
	local conn: RBXScriptConnection? = nil
	conn = humanoid.MoveToFinished:Connect(function()
		local c = conn
		if c then
			c:Disconnect()
		end
		if walkId == my and Walk.flatDistance(pos) <= within + 2 then
			onArrive()
		end
	end)
	return false
end

function Walk.cancel()
	walkId += 1
end

return Walk
