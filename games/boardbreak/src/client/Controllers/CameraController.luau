--!strict
--[[
	CameraController — 몸 크기에 맞춘 카메라 (선임, 사장님 결정 13번)
	  몸 배율 s (Attr BodyScale, 1 … Sizes.MAX_SCALE ≈ 14 → 키 약 75 스터드):
	    - 가장 멀리 당기는 거리 CameraMaxZoomDistance = 처음 값(StarterPlayer, 보통 128) × s
	    - 가장 가까이 CameraMinZoomDistance = 처음 값 × s (거인 머리 속으로 안 들어감)
	    - 몸 배율이 바뀌면 (2% 단위) 지금 줌 거리도 같은 비율로 → 내가 고른 "몸에 비해 얼마나 멀리" 는 그대로 (내 줌 입력과 안 싸움)
	      (로블록스에는 줌을 직접 정하는 속성이 없어서 한 프레임만 Min = Max = 원하는 거리로 묶었다가 바로 풂)
	    - 새 몸으로 태어났을 때 줌이 몸에 비해 너무 가까우면 (DEFAULT_ZOOM × s 의 절반보다 가까우면) DEFAULT_ZOOM × s 로
	  걷기 빠르기·점프는 서버가 정함 (여기서 안 바꿈).
	공개: CameraController.apply(scale) · zoomFor(scale) · limits(scale) · DEFAULT_ZOOM
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Sizes = require(ReplicatedStorage.Shared.Data.Sizes)
local Client = script.Parent.Parent
local State = require(Client.State)

local CameraController = {}

CameraController.DEFAULT_ZOOM = 12.5 -- 로블록스 기본 카메라 거리 (몸 배율 1)
local baseMax = 128
local baseMin = 0.5
local applied = 1 -- 마지막으로 맞춘 몸 배율
local busy = false

-- 몸 배율 s 일 때 (최소, 최대) 줌 거리
function CameraController.limits(scale: number): (number, number)
	local s = math.clamp(scale, 1, Sizes.MAX_SCALE)
	return baseMin * s, baseMax * s
end

function CameraController.zoomFor(scale: number): number
	return CameraController.DEFAULT_ZOOM * math.clamp(scale, 1, Sizes.MAX_SCALE)
end

-- 지금 카메라 거리 (카메라 → 초점). 알 수 없으면 nil
local function currentZoom(): number?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ok, d = pcall(function(): number
		return (camera.CFrame.Position - camera.Focus.Position).Magnitude
	end)
	return if ok and d > 0 then d else nil
end

-- 한 프레임만 줌을 d 로 묶었다가 풂
local function forceZoom(player: Player, d: number, minZ: number, maxZ: number)
	if busy then
		return
	end
	busy = true
	local want = math.clamp(d, minZ, maxZ)
	player.CameraMinZoomDistance = want
	player.CameraMaxZoomDistance = want
	task.spawn(function()
		pcall(function()
			RunService.RenderStepped:Wait()
		end)
		player.CameraMaxZoomDistance = maxZ
		player.CameraMinZoomDistance = minZ
		busy = false
	end)
end

-- 몸 배율 scale 에 맞춤. fresh = 새 몸 (너무 가까우면 기본 거리로)
function CameraController.apply(scale: number, fresh: boolean?)
	local player = Players.LocalPlayer
	local s = math.clamp(scale, 1, Sizes.MAX_SCALE)
	local minZ, maxZ = CameraController.limits(s)
	local zoom = currentZoom()
	local want: number? = nil
	if zoom and s ~= applied then
		want = zoom * s / applied -- 같은 비율 유지
	end
	if fresh and s > 1.5 then
		local base = CameraController.zoomFor(s)
		local now = want or zoom
		if now == nil or now < base * 0.5 then
			want = base
		end
	end
	applied = s
	if want then
		forceZoom(player, want, minZ, maxZ)
	elseif not busy then
		player.CameraMaxZoomDistance = maxZ
		player.CameraMinZoomDistance = minZ
	end
end

function CameraController.start()
	local player = Players.LocalPlayer
	pcall(function()
		baseMax = math.max(1, player.CameraMaxZoomDistance)
		baseMin = math.max(0.5, player.CameraMinZoomDistance)
	end)
	CameraController.apply(State.bodyScale())
	player:GetAttributeChangedSignal("BodyScale"):Connect(function()
		CameraController.apply(State.bodyScale())
	end)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			CameraController.apply(State.bodyScale(), true)
		end)
	end)
end

return CameraController
