--!strict
--[[
	클라 진입점 (ReplicatedStorage.Client.Main — Script, RunContext = Client)
	팀 표준: 진입점은 이것 하나. 나머지는 ModuleScript + start().
	화면(UI)·소리·조명·연출 컨트롤러는 선임 담당 (docs/UI.md 참고).
	컨트롤러 하나가 오류가 나도 나머지는 계속 돌도록 각각 따로 시작합니다.
]]

-- 처음 복제가 끝난 뒤에 시작 (ReplicatedStorage 모듈을 바로 인덱싱하므로)
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Client = script.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Controllers = Client.Controllers

local function boot(name: string)
	local module = Controllers:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn("[Client] 컨트롤러 없음: " .. name)
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local controller = (require :: any)(module)
			controller.start()
		end)
		if not ok then
			warn("[Client] " .. name .. " 시작 실패: " .. tostring(err))
		end
	end)
end

State.start()

if RunService:IsStudio() then
	boot("DebugController") -- 출력 창에 서버 이벤트 찍기 (스튜디오에서만)
end
boot("AnnounceController")
boot("RagdollController")
boot("ToolController")

-- 선임: 화면·소리·연출 (순서: 구역 판정 → 소리 → 조명 → 화면들 → 월드 연출)
boot("ZoneController")
boot("SoundController")
boot("LightingController")
boot("HudController")
boot("NotifyController")
boot("ChaseController")
boot("IncubatorController")
boot("HatchController")
boot("IndexController")
boot("FruitBagController") -- 6판: 열매 가방 창 · 판매 가판대 "열매 팔기" · 열매 먹이기
boot("PetsController")
boot("ShopController")
boot("SettingsController")
boot("HotbarController")
boot("WorldFxController")
-- 선임 2차: 특수 장소 화면 (6판 사쿠라 나무, 고르기 창 공용 UI/PetPicker) + 무기 손 모양
boot("SakuraController")
boot("WeaponController")
-- 선임 5차 (2판): 러닝머신 입력·걸음 팝업, 트레일 상점 창
boot("TreadmillController")
boot("TrailController")
boot("SpeedFxController") -- 4판: 빠를수록 시야를 넓혀 속도 체감
-- 선임 5판·6판: 정원 프롬프트(열매 따기·물 주기)·물방울, 식물 아우라·살랑살랑, 랭킹판, 튜토리얼 패널·가리키기 (위 가운데 것들을 내리므로 맨 뒤)
boot("PetFxController")
boot("PlantFxController")
boot("LeaderboardController")
boot("TutorialController")

-- 접속 직후 서버가 보낸 Snapshot 을 놓쳤을 수 있으니 한 번 요청
Net.send(Remotes.ToServer.RequestSnapshot)

print("[씨앗을 훔치세요] 클라이언트 시작 완료")
