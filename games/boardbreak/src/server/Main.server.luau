--!strict
--[[
	송판 깨기 서버 진입점 (ServerScriptService.Server.Main — Script, RunContext = Server)
	팀 표준: 진입점은 이것 하나. 나머지는 전부 ModuleScript + start(). 시작 순서 (위에서 아래로):
	  Net → MapBuilder(선임 — 맵) → *VisualService(선임 — 겉모습, Services 폴더에서 이름이 VisualService 로 끝나는 것 전부) →
	  DataService → TrainService · ExamService · BreakService · ShopService · WorldService → ProductService → LeaderboardService
	  → DevCommands → PlayerLifecycle (맨 마지막: 접속 처리)
	서비스 하나의 start() 가 오류를 내도 나머지는 계속 켜짐 (출력창에 warn).
]]

local Server = script.Parent
local Services = Server.Services

local Net = require(Server.Net)
local DataService = require(Services.DataService)
local TrainService = require(Services.TrainService)
local ExamService = require(Services.ExamService)
local BreakService = require(Services.BreakService)
local ShopService = require(Services.ShopService)
local WorldService = require(Services.WorldService)
local ProductService = require(Services.ProductService)
local LeaderboardService = require(Services.LeaderboardService)
local DevCommands = require(Services.DevCommands)
local PlayerLifecycle = require(Services.PlayerLifecycle)

local failed: { string } = {}
local function boot(name: string, fn: () -> ...any)
	local ok, err = pcall(fn)
	if not ok then
		table.insert(failed, name)
		warn("[BoardBreak] " .. name .. " 시작 실패: " .. tostring(err))
	end
end

-- 선임 모듈 (맵·겉모습): 있으면 require + start. 없거나 start 가 없으면 건너뜀
local function bootOptional(module: Instance)
	boot(module.Name, function()
		local service = (require :: any)(module)
		if type(service) == "table" and type(service.start) == "function" then
			service.start()
		end
	end)
end

boot("Net", function()
	Net.start()
end)
local mapBuilder = Services:FindFirstChild("MapBuilder")
if mapBuilder and mapBuilder:IsA("ModuleScript") then
	bootOptional(mapBuilder)
end
for _, child in Services:GetChildren() do
	if child:IsA("ModuleScript") and string.sub(child.Name, -#"VisualService") == "VisualService" then
		bootOptional(child)
	end
end
boot("DataService", function()
	DataService.start()
end)
boot("TrainService", function()
	TrainService.start()
end)
boot("ExamService", function()
	ExamService.start()
end)
boot("BreakService", function()
	BreakService.start()
end)
boot("ShopService", function()
	ShopService.start()
end)
boot("WorldService", function()
	WorldService.start()
end)
boot("ProductService", function()
	ProductService.start()
end)
boot("LeaderboardService", function()
	LeaderboardService.start()
end)
boot("DevCommands", function()
	DevCommands.start()
end)
boot("PlayerLifecycle", function()
	PlayerLifecycle.start()
end)

if #failed == 0 then
	print("[BoardBreak] 서버 시작 완료")
else
	warn("[BoardBreak] 서버 시작 — 일부 실패: " .. table.concat(failed, ", "))
end
