--!strict
--[[
	AnnounceController — 서버 공지("ALL SEED RESET!", "OO 구역에 OO 씨앗 등장!", 밤/낮)를 채팅창 시스템 메시지로
	TextChatService 가 없거나 실패하면 출력 창에만 찍음.
	7판: 희귀 씨앗 공지(kind "rareEgg")는 서버 글의 한국어 등급 이름 대신 화면 영어 이름(Rarities.displayName)으로
	  다시 씀 — payload 의 biomeId·petId·rarity 로 (AnnounceController.textFor). 모르는 id 면 서버 글 그대로.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage.Shared
local Biomes = require(Shared.Data.Biomes)
local Plants = require(Shared.Data.Plants)
local Rarities = require(Shared.Data.Rarities)
local Remotes = require(Shared.Remotes)
local Net = require(script.Parent.Parent.Net)

local AnnounceController = {}

local COLORS: { [string]: string } = {
	reset = "#FFD84A",
	rareEgg = "#FF5CF0",
	night = "#8FA8FF",
	day = "#FFFFFF",
}

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- 채팅에 보일 글 (희귀 씨앗 공지는 등급 영어로: "유령 성 구역에 Super 하늘 기둥꽃 씨앗 등장!")
function AnnounceController.textFor(payload: any): string
	local text = tostring(payload.text)
	if payload.kind ~= "rareEgg" then
		return text
	end
	local plant = Plants.get(tostring(payload.petId))
	local biome = Biomes.get(tostring(payload.biomeId))
	if not plant then
		return text
	end
	local rarityId = tostring(payload.rarity or plant.rarity)
	return string.format(
		"%s 구역에 %s %s 등장!",
		if biome then biome.name else tostring(payload.biomeId),
		Rarities.displayName(rarityId),
		Plants.seedName(plant.id)
	)
end

local function systemMessage(text: string, color: string?)
	local ok = pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = if channels then channels:FindFirstChild("RBXGeneral") else nil
		if general and general:IsA("TextChannel") then
			local safe = escape(text)
			local body = if color then string.format('<font color="%s"><b>%s</b></font>', color, safe) else safe
			general:DisplaySystemMessage(body)
		end
	end)
	if not ok then
		print("[공지] " .. text)
	end
end

function AnnounceController.start()
	Net.on(Remotes.ToClient.Announce, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local text = AnnounceController.textFor(payload)
		print("[공지] " .. text)
		systemMessage(text, COLORS[tostring(payload.kind)])
	end)
end

return AnnounceController
