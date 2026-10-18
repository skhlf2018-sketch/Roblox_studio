--!strict
--[[
	ZoneController — 내가 지금 어느 구역에 있는지 (클라 계산, 표시·소리·분위기용)
	2판: 맵이 한 줄 복도라 구역 = z 범위 (MapLayout.zoneAt). 서버 플레이어 Attribute CurrentZone 이 있으면 그걸 우선.
	  ZoneController.current()  → biomeId 또는 "base"(허브·베이스 = 안전 구역) 또는 nil(맵 밖)
	  ZoneController.changed(function(zoneId) end)
	판정·보상은 전부 서버. 이건 보기용입니다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapLayout = require(ReplicatedStorage.Shared.Data.MapLayout)
local Tags = require(ReplicatedStorage.Shared.Tags)

local ZoneController = {}

local current: string? = nil
local listeners: { (string?) -> () } = {}

local function normalize(zone: string?): string?
	if zone == "hub" then
		return "base"
	end
	if zone == "" then
		return nil
	end
	return zone
end

-- 위치 → biomeId | "base" | nil
function ZoneController.zoneAt(position: Vector3): string?
	return normalize(MapLayout.zoneAt(position.Z))
end

function ZoneController.current(): string?
	return current
end

function ZoneController.changed(fn: (string?) -> ())
	table.insert(listeners, fn)
end

local function set(zone: string?)
	if zone ~= current then
		current = zone
		for _, fn in listeners do
			task.spawn(fn, zone)
		end
	end
end

function ZoneController.start()
	local player = Players.LocalPlayer
	task.spawn(function()
		while true do
			task.wait(0.3)
			local attr = player:GetAttribute(Tags.PlayerAttributes.CurrentZone)
			if typeof(attr) == "string" and attr ~= "" then
				set(normalize(attr))
			else
				local character = player.Character
				local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
				if root and root:IsA("BasePart") then
					set(ZoneController.zoneAt(root.Position))
				end
			end
		end
	end)
end

return ZoneController
