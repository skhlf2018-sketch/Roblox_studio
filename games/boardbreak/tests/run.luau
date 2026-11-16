--!nocheck
--[[
	송판 깨기 — 모든 Lune 테스트 실행 (저장소 루트에서):
	  lune run games/boardbreak/tests/run.luau
	몇 개만: lune run games/boardbreak/tests/run.luau data economy   → data.spec · economy.spec 만 (.spec 은 빼도 됨)
	실패가 있으면 종료 코드 1.
	(선임 smoke_client.luau · smoke_visuals.luau, 숫자 시뮬레이션 sim_progress.luau 는 따로 돌림)
]]

local process = require("@lune/process")
local T = require("./TestKit")
local Loader = require("./Loader")

-- 이름 = tests/<이름>.luau (require 는 글자 그대로 써야 해서 아래 표에 함께 적음)
local specs = {
	{ "data.spec", require("./data.spec") },
	{ "format.spec", require("./format.spec") },
	{ "economy.spec", require("./economy.spec") },
	{ "break_rules.spec", require("./break_rules.spec") },
	{ "exam_rules.spec", require("./exam_rules.spec") },
	{ "progression.spec", require("./progression.spec") },
	{ "products.spec", require("./products.spec") },
	{ "services.spec", require("./services.spec") },
	{ "services_exam.spec", require("./services_exam.spec") },
	{ "save_data.spec", require("./save_data.spec") },
	{ "design_doc.spec", require("./design_doc.spec") },
	{ "holes_v1.spec", require("./holes_v1.spec") },
	{ "holes_v2.spec", require("./holes_v2.spec") },
	{ "sizes.spec", require("./sizes.spec") },
	{ "size_service.spec", require("./size_service.spec") },
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

-- 폴더 목록을 전부 미리 읽어 둠: Loader 는 script.Parent.X (__index 메타메서드) 안에서 폴더를 처음 읽으면
-- Lune 의 fs 가 양보(yield)해서 "yield across metamethod" 오류가 남 (첫 게임과 같은 이유)
Loader.preload()

for _, entry in specs do
	if wanted(entry[1]) then
		entry[2](T, Loader)
	end
end

local failed = T.summary()
process.exit(if failed > 0 then 1 else 0)
