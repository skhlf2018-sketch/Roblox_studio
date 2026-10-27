--!nocheck
--[[
	모든 순수 로직 테스트 실행 (저장소 루트에서):
	  lune run tests/run.luau
	몇 개만 (6판): lune run tests/run.luau garden data   → garden.spec · data.spec 만 (이름은 정확히, .spec 은 빼도 됨)
	실패가 있으면 종료 코드 1.
]]

local process = require("@lune/process")
local T = require("./TestKit")
local Loader = require("./Loader")

-- 이름 = tests/<이름>.luau (require 는 글자 그대로 써야 해서 아래 표에 함께 적음)
local specs = {
	{ "data.spec", require("./data.spec") },
	{ "economy.spec", require("./economy.spec") },
	{ "speed.spec", require("./speed.spec") },
	{ "eggrules.spec", require("./eggrules.spec") },
	{ "eggroll.spec", require("./eggroll.spec") },
	{ "cycle.spec", require("./cycle.spec") },
	{ "progression.spec", require("./progression.spec") },
	{ "server_logic.spec", require("./server_logic.spec") },
	{ "format.spec", require("./format.spec") },
	{ "special.spec", require("./special.spec") },
	{ "anticheat.spec", require("./anticheat.spec") },
	{ "services_core.spec", require("./services_core.spec") },
	{ "services_gameplay.spec", require("./services_gameplay.spec") },
	{ "services_system.spec", require("./services_system.spec") },
	{ "services_tools.spec", require("./services_tools.spec") },
	{ "services_world.spec", require("./services_world.spec") },
	{ "design_doc.spec", require("./design_doc.spec") },
	{ "rules_boundary.spec", require("./rules_boundary.spec") },
	{ "save_data.spec", require("./save_data.spec") },
	{ "crossrefs.spec", require("./crossrefs.spec") },
	{ "maplayout.spec", require("./maplayout.spec") },
	-- 5판
	{ "tutorial.spec", require("./tutorial.spec") },
	{ "social.spec", require("./social.spec") },
	-- 5판 주임 검수 (구멍 찾기)
	{ "holes_tutorial.spec", require("./holes_tutorial.spec") },
	{ "holes_social.spec", require("./holes_social.spec") },
	{ "holes_world.spec", require("./holes_world.spec") },
	-- 6판 씨앗을 훔치세요: 성장 단계·성체·열매·건너뛰기·팔기·도감·사쿠라 씨앗·스키마 v6
	{ "garden.spec", require("./garden.spec") },
	-- 6판 주임 검수
	{ "holes_garden.spec", require("./holes_garden.spec") },
}

local filters: { string } = {}
for i = 1, #process.args do
	filters[i] = tostring(process.args[i])
end
local function wanted(name: string): boolean
	if #filters == 0 then
		return true
	end
	for _, f in filters do
		if name == f or name == f .. ".spec" then
			return true
		end
	end
	return false
end

-- 폴더 목록을 미리 읽어 둠: Loader 는 script.Parent.X (__index 메타메서드) 안에서 폴더를 처음 읽으면
-- Lune 의 fs 가 양보(yield)해서 "yield across metamethod" 오류가 남. 전에는 data.spec 이 맨 앞에서 우연히 채웠음
-- (6판: 몇 개만 돌릴 때도 되게 여기서 채움)
for _, path in
	{
		"ReplicatedStorage/Shared/Data/Config",
		"ReplicatedStorage/Client/Controllers/HudController",
		"ReplicatedStorage/Client/UI/Ui",
		"ServerScriptService/Server/Services/BaseService",
		"ServerScriptService/Server/Logic/Validate",
		"ServerScriptService/Server/Util/Signal",
	}
do
	Loader.get(path)
end

for _, entry in specs do
	if wanted(entry[1]) then
		entry[2](T, Loader)
	end
end

local failed = T.summary()
process.exit(if failed > 0 then 1 else 0)
