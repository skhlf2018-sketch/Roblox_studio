--!strict
--[[
	ZoneController — 내가 지금 어느 구역에 있는지 (클라 계산, 표시·소리·분위기용)
	서버에는 "현재 구역" Attribute 가 없어서, Zone 태그 바닥(축 정렬 직사각형) 위치로 0.3초마다 계산.
	  ZoneController.current()  → biomeId 또는 "base"(베이스·광장) 또는 nil(길)
	  ZoneController.changed(function(zoneId) end)
	판정·보상은 전부 서버. 이건 보기용입니다.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Shared.Tags)

local ZoneController = {}

type ZoneBox = { id: string, minX: number, maxX: number, minZ: number, maxZ: number }

local boxes: { ZoneBox } = {}
local current: string? = nil
local listeners: { (string?) -> () } = {}

local function rebuild()
	table.clear(boxes)
	for _, inst in CollectionService:GetTagged(Tags.Zone) do
		if inst:IsA("BasePart") then
			local id = inst:GetAttribute("BiomeId")
			if typeof(id) == "string" then
				local p, s = inst.Position, inst.Size
				table.insert(boxes, {
					id = id,
					minX = p.X - s.X / 2,
					maxX = p.X + s.X / 2,
					minZ = p.Z - s.Z / 2,
					maxZ = p.Z + s.Z / 2,
				})
			end
		end
	end
end

local function find(position: Vector3): string?
	for _, b in boxes do
		if position.X >= b.minX and position.X <= b.maxX and position.Z >= b.minZ and position.Z <= b.maxZ then
			return b.id
		end
	end
	return nil
end

function ZoneController.current(): string?
	return current
end

function ZoneController.changed(fn: (string?) -> ())
	table.insert(listeners, fn)
end

function ZoneController.start()
	local player = Players.LocalPlayer
	rebuild()
	CollectionService:GetInstanceAddedSignal(Tags.Zone):Connect(rebuild)
	task.spawn(function()
		while true do
			task.wait(0.3)
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				local zone = find(root.Position)
				-- 베이스 안전 구역 또는 광장(길 시작 전)은 "base"
				local inSafe = player:GetAttribute(Tags.PlayerAttributes.InSafeZone) == true
				if not zone and (inSafe or root.Position.Z < 30) then
					zone = "base"
				end
				if zone ~= current then
					current = zone
					for _, fn in listeners do
						task.spawn(fn, zone)
					end
				end
			end
		end
	end)
end

return ZoneController
