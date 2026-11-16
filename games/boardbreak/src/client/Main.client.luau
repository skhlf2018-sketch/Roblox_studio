--!strict
--[[
	송판 깨기 — 클라 진입점 (ReplicatedStorage.Client.Main — Script, RunContext = Client)
	팀 표준: 진입점은 이것 하나. 나머지는 ModuleScript + start(). 화면·소리·조작 컨트롤러는 선임 (docs/UI.md).
	컨트롤러 하나가 오류가 나도 나머지는 계속 돌도록 각각 따로 시작합니다.
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- 소리 → 알림 → 늘 보이는 화면 → 창들(메뉴 버튼 순서: 아령 가게 · 도감 · 힘 배수 · 띠 · 설정) → 조작 → 연출
boot("SoundController")
boot("NotifyController")
boot("HudController")
boot("DumbbellShopController")
boot("IndexController")
boot("BoostController")
boot("BeltController")
boot("SettingsController")
boot("TrainController")
boot("BreakController")
boot("ExamController")
boot("WorldController")
boot("TutorialController")
boot("AuraController")
boot("CameraController")
task.spawn(function()
	local ok, err = pcall(function()
		(require :: any)(Client.Purchase).start()
	end)
	if not ok then
		warn("[Client] Purchase 시작 실패: " .. tostring(err))
	end
end)

-- 화면이 준비됨 → 서버가 Snapshot 을 (다시) 보냄
Net.send(Remotes.ToServer.ClientReady)

print("[송판 깨기] 클라이언트 시작 완료")
