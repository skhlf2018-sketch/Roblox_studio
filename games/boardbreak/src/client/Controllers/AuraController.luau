--!strict
--[[
	AuraController — 아우라 (선임). 아우라 파트·파티클은 서버(PlayerVisualService)가 붙여서 모두에게 보임.
	  - 내 캐릭터 Attr AuraTier 가 오르면 한 번: 화면 가운데 "✨ 아우라 UP!" + 번쩍(흰 화면 잠깐) + 소리.
	  - 저사양(lowGraphics) 이 켜져 있으면 내 화면에서 다른 사람 아우라 파티클·고리를 끔 (1초마다 맞춤).
	공개: AuraController.tick() · AuraController.lastShownTier()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Visuals = require(ReplicatedStorage.Shared.Data.Visuals)
local Client = script.Parent.Parent
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local SoundController = require(script.Parent.SoundController)
local ExamController = require(script.Parent.ExamController)

local AuraController = {}

local shownTier = -1 -- 처음 한 번은 연출 없이 지금 단계를 기억

function AuraController.lastShownTier(): number
	return shownTier
end

local function flash(tier: number)
	local a = Visuals.aura(tier)
	local color = if a then a.color else Theme.Colors.yellow
	ExamController.big("✨ 아우라 UP! " .. (if a then a.name else ""), color, 1.6)
	SoundController.play("Pass")
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local screen = gui and gui:FindFirstChild("BoardBreakUI")
	if screen then
		local white: Frame = Ui.new("Frame", {
			Name = "AuraFlash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.5,
			ZIndex = 50,
			Parent = screen,
		})
		Ui.tween(white, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
		task.delay(0.55, function()
			white:Destroy()
		end)
	end
end

local function setOthers(visible: boolean)
	for _, p in Players:GetPlayers() do
		if p ~= Players.LocalPlayer then
			local character = p.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local attach = root and root:FindFirstChild("AuraAttach")
			local sparks = attach and attach:FindFirstChild("AuraSparks")
			if sparks and sparks:IsA("ParticleEmitter") then
				sparks.Enabled = visible
			end
			local ring = character and character:FindFirstChild("AuraRing")
			if ring and ring:IsA("BasePart") then
				ring.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
	end
end

function AuraController.tick()
	local character = Players.LocalPlayer.Character
	local tier = character and character:GetAttribute("AuraTier")
	if type(tier) == "number" then
		if shownTier >= 0 and tier > shownTier then
			flash(tier)
		end
		shownTier = tier
	end
	setOthers(not State.setting("lowGraphics", false))
end

function AuraController.start()
	Players.LocalPlayer.CharacterAdded:Connect(function()
		-- 리스폰은 단계가 그대로 다시 붙는 것이라 연출 안 함
		shownTier = -1
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 1 then
			acc = 0
			AuraController.tick()
		end
	end)
	AuraController.tick()
end

return AuraController
