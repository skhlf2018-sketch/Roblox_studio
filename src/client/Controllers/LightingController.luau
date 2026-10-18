--!strict
--[[
	LightingController — 낮/밤 조명 (클라에서 부드럽게 TweenService)
	- GameState.Phase: "Day" 밝고 따뜻하게 / "Night" 어둡고 파랗게 / "Intermission" 새벽
	- 시계(ClockTime)는 항상 앞으로만 감 (낮 14시 → 밤 22시 → 새벽 5시半 → 낮 14시)
	- 구역마다 안개·공기 색(Atmosphere)을 바꿈 (Visuals.biomes[id].atmosphere). 유령 성은 보랏빛 짙은 안개.
	서버 CycleService 도 Lighting.ClockTime 을 바로 바꾸지만, 이 컨트롤러가 매 프레임 덮어써서 부드럽게 보임.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Tags)
local Visuals = require(Shared.Data.Visuals)
local ZoneController = require(script.Parent.ZoneController)

local LightingController = {}

type Look = {
	clock: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	tint: Color3,
	exposure: number,
}

local LOOKS: { [string]: Look } = {
	Day = {
		clock = 14,
		brightness = 2.6,
		ambient = Color3.fromRGB(135, 125, 115),
		outdoor = Color3.fromRGB(160, 150, 140),
		tint = Color3.fromRGB(255, 250, 240),
		exposure = 0.15,
	},
	Night = {
		clock = 22,
		brightness = 0.7,
		ambient = Color3.fromRGB(55, 55, 95),
		outdoor = Color3.fromRGB(70, 70, 120),
		tint = Color3.fromRGB(200, 205, 255),
		exposure = -0.1,
	},
	Intermission = {
		clock = 5.6,
		brightness = 1.4,
		ambient = Color3.fromRGB(110, 95, 120),
		outdoor = Color3.fromRGB(150, 120, 140),
		tint = Color3.fromRGB(255, 225, 225),
		exposure = 0,
	},
}

local TRANSITION = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local ZONE_FADE = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local clockValue = Instance.new("NumberValue")
local colorCorrection: ColorCorrectionEffect? = nil
local atmosphere: Atmosphere? = nil
local phase = "Day"
local zone: string? = nil

local function rgb(c: Visuals.Color): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ensureEffects()
	local cc = Lighting:FindFirstChild("CuteColor")
	if not cc then
		local n = Instance.new("ColorCorrectionEffect")
		n.Name = "CuteColor"
		n.Saturation = 0.18
		n.Contrast = 0.06
		n.Parent = Lighting
		cc = n
	end
	colorCorrection = cc :: ColorCorrectionEffect
	if not Lighting:FindFirstChild("CuteBloom") then
		local b = Instance.new("BloomEffect")
		b.Name = "CuteBloom"
		b.Intensity = 0.35
		b.Size = 20
		b.Threshold = 1.6
		b.Parent = Lighting
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		local a = Instance.new("Atmosphere")
		a.Density = 0.25
		a.Offset = 0.1
		a.Parent = Lighting
		atm = a
	end
	atmosphere = atm
end

local function applyPhase(p: string, instant: boolean)
	local look = LOOKS[p] or LOOKS.Day
	-- 시계는 앞으로만
	local target = look.clock
	while target < clockValue.Value - 0.01 do
		target += 24
	end
	local info = if instant then TweenInfo.new(0) else TRANSITION
	TweenService:Create(clockValue, info, { Value = target }):Play()
	TweenService:Create(Lighting, info, {
		Brightness = look.brightness,
		Ambient = look.ambient,
		OutdoorAmbient = look.outdoor,
		ExposureCompensation = look.exposure,
	}):Play()
	local cc = colorCorrection
	if cc then
		TweenService:Create(cc, info, { TintColor = look.tint }):Play()
	end
end

local function applyZone()
	local atm = atmosphere
	if not atm then
		return
	end
	local theme = if zone and zone ~= "base" then Visuals.biomes[zone] else nil
	local a = if theme and theme.atmosphere then theme.atmosphere else Visuals.hubAtmosphere
	local night = phase ~= "Day"
	local color = rgb(a.color)
	local decay = rgb(a.decay)
	if night then
		color = color:Lerp(Color3.fromRGB(40, 40, 80), 0.5)
		decay = decay:Lerp(Color3.fromRGB(20, 20, 50), 0.5)
	end
	TweenService:Create(atm, ZONE_FADE, {
		Density = a.density + (if night then 0.1 else 0),
		Haze = a.haze,
		Color = color,
		Decay = decay,
	}):Play()
end

function LightingController.start()
	ensureEffects()
	clockValue.Value = Lighting.ClockTime
	clockValue.Changed:Connect(function(v: number)
		Lighting.ClockTime = v % 24
	end)

	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild(Tags.StateFolderName, 60)
		if not state then
			return
		end
		local function read(instant: boolean)
			local p = state:GetAttribute(Tags.StateAttributes.Phase)
			phase = if typeof(p) == "string" then p else "Day"
			applyPhase(phase, instant)
			applyZone()
		end
		read(true)
		state:GetAttributeChangedSignal(Tags.StateAttributes.Phase):Connect(function()
			read(false)
		end)
	end)

	ZoneController.changed(function(z: string?)
		zone = z
		applyZone()
	end)
	applyZone()
end

return LightingController
