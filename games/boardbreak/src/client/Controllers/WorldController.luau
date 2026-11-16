--!strict
--[[
	WorldController — 월드 문 · 월드 이동 화면 전환 · 월드 조명 (선임)
	  - 로비의 월드 문(태그 WorldDoor, Attr TargetWorld)을 누르거나 탭:
	      열린 월드(Attr World ≥ TargetWorld) → 화면이 까맣게 → Travel(worldIndex) → 서버가 순간이동 → 밝아짐
	      잠긴 월드 → "🔒 월드 2 는 시험관을 이기면 열려요" (자물쇠는 잠긴 문에만 보임, 내 화면에서만)
	  - 지금 월드(Attr CurrentWorld)가 바뀌면: 큰 배너 "🌏 지구 한 바퀴" + 조명 (1·2 낮 / 3 우주 = 밤하늘)
	  - 심사·대결 중에는 문이 안 열림.
	공개: travel(world) · isUnlocked(world) · paintDoors() · applyLighting(world) · fade
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Worlds = require(Shared.Data.Worlds)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)

local WorldController = {}
WorldController.fade = nil :: Frame?

local PA = Tags.PartAttributes
local lastTravel = -math.huge

local LIGHTS: { { clock: number, ambient: Color3, outdoor: Color3, brightness: number } } = {
	{ clock = 14, ambient = Color3.fromRGB(140, 130, 120), outdoor = Color3.fromRGB(150, 140, 130), brightness = 2.2 },
	{ clock = 13, ambient = Color3.fromRGB(130, 140, 160), outdoor = Color3.fromRGB(140, 150, 170), brightness = 2.4 },
	{ clock = 0, ambient = Color3.fromRGB(70, 60, 110), outdoor = Color3.fromRGB(90, 80, 140), brightness = 1 },
}

function WorldController.isUnlocked(world: number): boolean
	return world <= State.world()
end

function WorldController.applyLighting(world: number)
	local l = LIGHTS[math.clamp(world, 1, #LIGHTS)]
	Lighting.ClockTime = l.clock
	Lighting.Ambient = l.ambient
	Lighting.OutdoorAmbient = l.outdoor
	Lighting.Brightness = l.brightness
end

-- 잠긴 문에만 자물쇠 · 열린 문은 빛나는 문 (내 화면에서만)
function WorldController.paintDoors()
	for _, model in CollectionService:GetTagged(Tags.WorldDoor) do
		local target = model:GetAttribute(PA.TargetWorld)
		if type(target) == "number" then
			local open = WorldController.isUnlocked(target)
			local lock = model:FindFirstChild("Lock")
			if lock then
				for _, p in lock:GetDescendants() do
					if p:IsA("BasePart") then
						p.LocalTransparencyModifier = if open then 1 else 0
					end
				end
			end
			local portal = model:FindFirstChild("Portal")
			if portal and portal:IsA("BasePart") then
				portal.LocalTransparencyModifier = if open then 0 else 0.6
			end
		end
	end
end

local function fadeTo(alpha: number, seconds: number)
	local f = WorldController.fade
	if f then
		f.Visible = true
		Ui.tween(f, TweenInfo.new(seconds), { BackgroundTransparency = alpha })
		if alpha >= 1 then
			task.delay(seconds, function()
				if f.BackgroundTransparency >= 0.99 then
					f.Visible = false
				end
			end)
		end
	end
end

-- 문을 눌렀을 때. 보냈으면 true
function WorldController.travel(world: number): boolean
	local w = Worlds.get(world)
	if not w then
		return false
	end
	if State.activity() ~= "" then
		NotifyController.toast("심사·대결 종료 후 이동 가능", "info")
		return false
	end
	if not WorldController.isUnlocked(world) then
		NotifyController.toast(
			string.format("🔒 월드 %d %s · 시험관 승리 시 열림", world, w.name),
			"error"
		)
		SoundController.play("Error")
		return false
	end
	if world == State.currentWorld() then
		return false
	end
	local now = os.clock()
	if now - lastTravel < 1.5 then
		return false
	end
	lastTravel = now
	SoundController.play("Travel")
	fadeTo(0, 0.25)
	task.delay(0.25, function()
		Net.send(Remotes.ToServer.Travel, world)
	end)
	-- 서버가 CurrentWorld 를 안 바꿔도(거절) 2초 뒤에는 밝아짐
	task.delay(2, function()
		fadeTo(1, 0.4)
	end)
	return true
end

local shownWorld = 0
local function onWorldChanged()
	local world = State.currentWorld()
	WorldController.applyLighting(world)
	if world ~= shownWorld then
		local first = shownWorld == 0
		shownWorld = world
		local w = Worlds.get(world)
		if w and not first then
			NotifyController.banner(string.format("월드 %d · %s", world, w.name), Theme.worldColor(world))
		end
		fadeTo(1, 0.5)
	end
end

function WorldController.start()
	local fade: Frame = Ui.new("Frame", {
		Name = "TravelFade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.layer("Dialogs"),
	})
	fade.Active = false
	WorldController.fade = fade

	local function hook(inst: Instance)
		local click = inst:FindFirstChild("Click")
		local target = inst:GetAttribute(PA.TargetWorld)
		if click and click:IsA("ClickDetector") and type(target) == "number" then
			click.MouseClick:Connect(function()
				WorldController.travel(target)
			end)
		end
	end
	for _, inst in CollectionService:GetTagged(Tags.WorldDoor) do
		hook(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.WorldDoor):Connect(function(inst: Instance)
		hook(inst)
		WorldController.paintDoors()
	end)

	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.World):Connect(WorldController.paintDoors)
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.CurrentWorld):Connect(onWorldChanged)
	State.onChanged(function(section: string)
		if section == "snapshot" or section == "progress" then
			WorldController.paintDoors()
			onWorldChanged()
		end
	end)
	WorldController.paintDoors()
	onWorldChanged()
end

return WorldController
