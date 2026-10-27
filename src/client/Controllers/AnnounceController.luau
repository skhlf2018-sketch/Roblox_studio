--!strict
--[[
	AnnounceController — 서버 공지("ALL SEED RESET!", "OO 구역에 OO 씨앗 등장!", 밤/낮)를 채팅창 시스템 메시지로
	TextChatService 가 없거나 실패하면 출력 창에만 찍음.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Net = require(script.Parent.Parent.Net)

local AnnounceController = {}

local COLORS: { [string]: string } = {
	reset = "#FFD84A",
	rareEgg = "#FF5CF0",
	night = "#8FA8FF",
	day = "#FFFFFF",
}

local function systemMessage(text: string, color: string?)
	local ok = pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = if channels then channels:FindFirstChild("RBXGeneral") else nil
		if general and general:IsA("TextChannel") then
			local body = if color then string.format('<font color="%s"><b>%s</b></font>', color, text) else text
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
		local text = tostring(payload.text)
		print("[공지] " .. text)
		systemMessage(text, COLORS[tostring(payload.kind)])
	end)
end

return AnnounceController
