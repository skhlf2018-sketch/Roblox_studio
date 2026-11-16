--!strict
--[[
	Character — 플레이어 캐릭터 부품을 안전하게 꺼내는 도우미 (nil 검사 한 곳에서)
]]

local Character = {}

function Character.get(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, if root and root:IsA("BasePart") then root else nil
end

function Character.getRoot(player: Player): BasePart?
	local _, _, root = Character.get(player)
	return root
end

function Character.getHumanoid(player: Player): Humanoid?
	local _, humanoid = Character.get(player)
	return humanoid
end

function Character.isAlive(player: Player): boolean
	local _, humanoid, root = Character.get(player)
	return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

function Character.getHead(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return Character.getRoot(player)
end

return Character
