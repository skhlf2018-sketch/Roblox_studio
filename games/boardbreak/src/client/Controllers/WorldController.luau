--!strict
--[[
	WorldController — 월드 문 · 월드 이동 화면 전환 · 월드 조명 (선임)
	  - 로비의 월드 문(태그 WorldDoor, Attr TargetWorld)에 걸어 들어가면 바로 (사장님 결정 15번 — 클릭·확인 창 없음,
	    문 칸 = MapLayout.doorAt, 몸 크기·월드 배율에 맞춤. 문을 눌러도 같은 동작):
	      열린 월드(Attr World ≥ TargetWorld) → Travel(worldIndex) 바로 보냄 + 화면이 까맣게 → 서버가 순간이동 → 밝아짐
	      잠긴 월드 → "🔒 월드 2 … 시험관 승리 시 열림" (포털 안에 서 있어도 TOAST_GAP 3초에 한 번. 자물쇠는 잠긴 문에만, 내 화면에서만)
	      한 번 보내면 모든 포털 밖으로 나왔다가 다시 들어가야 또 보냄 (핑퐁 없음)
	  - 지금 월드(Attr CurrentWorld)가 바뀌면: 큰 배너 "🌏 지구 한 바퀴" + 조명 (1·2 낮 / 3 우주 = 밤하늘)
	  - 심사·대결 중에는 문이 안 열림.
	공개: travel(world) · checkPortal() · portalAt() · isArmed() · isUnlocked(world) · paintDoors() · applyLighting(world) · fade
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Worlds = require(Shared.Data.Worlds)
local MapLayout = require(Shared.Data.MapLayout)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Walk = require(Client.Walk)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)

local WorldController = {}
WorldController.fade = nil :: Frame?

local PA = Tags.PartAttributes
local lastTravel = -math.huge
local lastRefusal = -math.huge
WorldController.TOAST_GAP = 3 -- 거절 알림 간격 (초)
WorldController.TRAVEL_GAP = 1.5 -- 이동 연타 막기 (초)
WorldController.PORTAL_CHECK = 0.1 -- 포털 검사 간격 (초)

-- 월드 조명 (내 화면). ambient = 지붕 아래·그늘 (하늘이 안 보이는 곳) 빛 · outdoor = 밖 그늘 빛 · exposure = 화면 전체 밝기 보정.
--   월드 3 (본부장 2026-11-16 확인: 11배 우주 도장 안이 거의 까맘 — 밤 + 천장 등 빛 범위 상한 60):
--   하늘은 밤(ClockTime 0, 별)으로 두고, 그늘 빛을 밝은 보라로 올려 바닥·벽·매트·시설이 보이게. 스스로 빛나는 네온(벽 띠·길 가장자리)은 그대로 빛남
type Light = { clock: number, ambient: Color3, outdoor: Color3, brightness: number, exposure: number }
local LIGHTS: { Light } = {
	{
		clock = 14,
		ambient = Color3.fromRGB(140, 130, 120),
		outdoor = Color3.fromRGB(150, 140, 130),
		brightness = 2.2,
		exposure = 0,
	},
	{
		clock = 13,
		ambient = Color3.fromRGB(130, 140, 160),
		outdoor = Color3.fromRGB(140, 150, 170),
		brightness = 2.4,
		exposure = 0,
	},
	{
		clock = 0,
		ambient = Color3.fromRGB(165, 155, 215),
		outdoor = Color3.fromRGB(150, 140, 200),
		brightness = 1.5,
		exposure = 0.4,
	},
}
WorldController.LIGHTS = LIGHTS
WorldController.MIN_AMBIENT = 0.5 -- 모든 월드: 지붕 아래 빛 밝기(0~1, R·G·B 평균)가 이 이상 (스모크 검사)

function WorldController.isUnlocked(world: number): boolean
	return world <= State.world()
end

function WorldController.applyLighting(world: number)
	local l = LIGHTS[math.clamp(world, 1, #LIGHTS)]
	Lighting.ClockTime = l.clock
	Lighting.Ambient = l.ambient
	Lighting.OutdoorAmbient = l.outdoor
	Lighting.Brightness = l.brightness
	pcall(function()
		Lighting.ExposureCompensation = l.exposure
	end)
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

-- 거절 알림 (심사 중 · 잠긴 월드): 포털 안에 서 있어도 TOAST_GAP 초에 한 번만
local function refuse(text: string, kind: string, sound: boolean)
	local now = os.clock()
	if now - lastRefusal < WorldController.TOAST_GAP then
		return
	end
	lastRefusal = now
	NotifyController.toast(text, kind)
	if sound then
		SoundController.play("Error")
	end
end

-- 문에 들어갔을 때 · 문을 눌렀을 때. 보냈으면 true (서버가 다시 검사: 열린 월드 · 심사·대결 중 아님)
function WorldController.travel(world: number): boolean
	local w = Worlds.get(world)
	if not w then
		return false
	end
	if State.activity() ~= "" then
		refuse("심사·대결 종료 후 이동 가능", "info", false)
		return false
	end
	if not WorldController.isUnlocked(world) then
		refuse(string.format("🔒 월드 %d %s · 시험관 승리 시 열림", world, w.name), "error", true)
		return false
	end
	if world == State.currentWorld() then
		return false
	end
	local now = os.clock()
	if now - lastTravel < WorldController.TRAVEL_GAP then
		return false
	end
	lastTravel = now
	SoundController.play("Travel")
	-- 바로 보냄 (사장님 결정 15번: 들어가면 바로 이동). 화면은 그동안 까맣게
	Net.send(Remotes.ToServer.Travel, world)
	fadeTo(0, 0.2)
	-- 서버가 CurrentWorld 를 안 바꿔도(거절) 2초 뒤에는 밝아짐
	task.delay(2, function()
		fadeTo(1, 0.4)
	end)
	return true
end

------------------------------------------------------------------
-- 포털에 들어가면 바로 이동 (사장님 결정 15번). 클릭·창·버튼 없음.
--   판정: 내 HumanoidRootPart 자리가 MapLayout.doorAt(자리, 지금 월드, 몸 배율) 칸 안 (칸 = 문틀 안쪽 × 월드 배율,
--         몸이 크면 몸 반지름만큼 넓힘 → 문보다 큰 거인도 몸이 문에 닿으면 들어감). Touched 를 안 써서 몸 파트가
--         여러 개 닿아도 한 번만.
--   핑퐁 없음: 보낸 뒤에는 "모든 포털 밖"에 한 번 나와야 다시 들어갈 수 있음 (armed). 도착 자리(스폰)는 포털 칸 밖.
------------------------------------------------------------------

local armed = false -- 처음엔 꺼 둠: 포털 밖을 한 번 확인한 뒤에 켬 (포털 안에서 태어나도 바로 안 감)

function WorldController.portalAt(): number?
	local root = Walk.root()
	if not root then
		return nil
	end
	return MapLayout.doorAt(root.CFrame.Position, State.currentWorld(), State.bodyScale())
end

-- 한 번 검사 (Heartbeat 에서 PORTAL_CHECK 초마다). 보냈으면 그 월드 번호
function WorldController.checkPortal(): number?
	local target = WorldController.portalAt()
	if target == nil then
		armed = true
		return nil
	end
	if not armed then
		return nil
	end
	armed = false -- 나왔다가 다시 들어갈 때까지 안 보냄 (거절돼도)
	if WorldController.travel(target) then
		return target
	end
	return nil
end

function WorldController.isArmed(): boolean
	return armed
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

	-- 포털 (사장님 결정 15번): 들어가면 바로 이동
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= WorldController.PORTAL_CHECK then
			acc = 0
			WorldController.checkPortal()
		end
	end)
	player.CharacterAdded:Connect(function()
		armed = false -- 새 몸: 포털 밖을 한 번 확인한 뒤에 켬
	end)
end

return WorldController
