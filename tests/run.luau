--!nocheck
--[[
	모든 순수 로직 테스트 실행 (저장소 루트에서):
	  lune run tests/run.luau
	실패가 있으면 종료 코드 1.
]]

local process = require("@lune/process")
local T = require("./TestKit")
local Loader = require("./Loader")

local specs = {
	require("./data.spec"),
	require("./economy.spec"),
	require("./speed.spec"),
	require("./eggrules.spec"),
	require("./eggroll.spec"),
	require("./cycle.spec"),
	require("./progression.spec"),
	require("./server_logic.spec"),
	require("./format.spec"),
}

for _, spec in specs do
	spec(T, Loader)
end

local failed = T.summary()
process.exit(if failed > 0 then 1 else 0)
