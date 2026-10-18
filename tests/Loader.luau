--!nocheck
--[[
	Loader — Lune 에서 로블록스식 require(script.Parent.X) / game:GetService("ReplicatedStorage").Shared.X 를 흉내냄

	왜 필요하나:
	  게임 코드는 로블록스 방식(인스턴스 경로)으로 require 합니다. Lune 은 문자열 경로만 압니다.
	  그래서 default.project.json 을 읽어 Rojo 와 같은 규칙으로 "가짜 인스턴스 트리"를 만들고,
	  모듈을 luau.load 로 불러올 때 환경에 가짜 script / game / require 를 넣어 줍니다.

	규칙 (Rojo 와 동일):
	  X.luau / X.lua         → ModuleScript "X"
	  X.server.luau 등       → Script (require 불가)
	  폴더/init.luau         → 폴더 자체가 ModuleScript
	  그 밖의 폴더            → Folder

	사용 (저장소 루트에서 실행):
	  local Loader = require("./Loader")
	  local Economy = Loader.require("ReplicatedStorage/Shared/Economy")

	주의: 로블록스 API(Instance.new, Players 등)를 쓰는 모듈은 여기서 require 하면 에러가 납니다.
	      순수 로직 모듈만 테스트하세요.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

local Loader = {}

local PROJECT_FILE = "default.project.json"

local nodeMeta = {}
local cache = {} -- fsPath → 모듈 반환값
local loading = {} -- 순환 require 감지
-- 서비스 테스트용 (tests/ServerHarness.luau 가 씀): 순수 로직 테스트는 이 셋을 안 건드림
local mocks = {} -- fsPath → 가짜 모듈 값 (require 하면 진짜 파일 대신 이것을 돌려줌)
local serviceOverrides = {} -- 서비스 이름 → 가짜 서비스 (game:GetService 가 먼저 돌려줌)
local extraGlobals = {} -- 모듈 환경에 더해 줄 전역 (task, Instance, os ...)

local function joinPath(a, b)
	if a == "" then
		return b
	end
	return a .. "/" .. b
end

local function stripModuleExtension(name)
	for _, ext in { ".server.luau", ".client.luau", ".server.lua", ".client.lua" } do
		if string.sub(name, -#ext) == ext then
			return string.sub(name, 1, -#ext - 1), "script"
		end
	end
	for _, ext in { ".luau", ".lua" } do
		if string.sub(name, -#ext) == ext then
			return string.sub(name, 1, -#ext - 1), "module"
		end
	end
	return nil, nil
end

-- 노드 만들기
-- kind: "virtual"(project.json 의 노드) | "dir" | "module" | "script"
local function makeNode(props)
	return setmetatable({ __props = props }, nodeMeta)
end

local function initFile(dirPath)
	for _, name in { "init.luau", "init.lua" } do
		local p = joinPath(dirPath, name)
		if fs.isFile(p) then
			return p
		end
	end
	for _, name in { "init.server.luau", "init.client.luau" } do
		local p = joinPath(dirPath, name)
		if fs.isFile(p) then
			return p, "script"
		end
	end
	return nil
end

-- 디스크 경로 하나를 노드로
local function nodeFromPath(name, path, parent)
	if fs.isDir(path) then
		local init, initKind = initFile(path)
		if init then
			return makeNode({
				kind = initKind or "module",
				name = name,
				parent = parent,
				dir = path,
				file = init,
			})
		end
		return makeNode({ kind = "dir", name = name, parent = parent, dir = path })
	end
	if fs.isFile(path) then
		local _, kind = stripModuleExtension(path)
		return makeNode({ kind = kind or "file", name = name, parent = parent, file = path })
	end
	return nil
end

-- 디렉터리 안의 자식 이름 → 노드
local function childrenOfDir(node, dirPath)
	local props = node.__props
	if props.childCache then
		return props.childCache
	end
	local result = {}
	if dirPath and fs.isDir(dirPath) then
		for _, entry in fs.readDir(dirPath) do
			local full = joinPath(dirPath, entry)
			if fs.isDir(full) then
				result[entry] = nodeFromPath(entry, full, node)
			else
				local base, kind = stripModuleExtension(entry)
				if base and base ~= "init" then
					result[base] = makeNode({ kind = kind, name = base, parent = node, file = full })
				end
			end
		end
	end
	props.childCache = result
	return result
end

local function getChildren(node)
	local props = node.__props
	if props.kind == "virtual" then
		local result = {}
		if props.path then
			for k, v in childrenOfDir(node, props.dir) do
				result[k] = v
			end
		end
		for k, v in props.virtualChildren do
			result[k] = v
		end
		return result
	elseif props.kind == "dir" or ((props.kind == "module" or props.kind == "script") and props.dir) then
		return childrenOfDir(node, props.dir)
	end
	return {}
end

local function findChild(node, name)
	return getChildren(node)[name]
end

nodeMeta.__index = function(self, key)
	local props = rawget(self, "__props")
	if key == "Name" then
		return props.name
	elseif key == "Parent" then
		return props.parent
	elseif key == "FindFirstChild" then
		return function(_, name)
			return findChild(self, name)
		end
	elseif key == "WaitForChild" then
		return function(_, name)
			local child = findChild(self, name)
			assert(child, "Loader: WaitForChild 실패 — " .. props.name .. "." .. tostring(name))
			return child
		end
	elseif key == "GetChildren" then
		return function()
			local list = {}
			for _, child in getChildren(self) do
				table.insert(list, child)
			end
			return list
		end
	elseif key == "IsA" then
		return function(_, className)
			if props.kind == "module" then
				return className == "ModuleScript" or className == "LuaSourceContainer" or className == "Instance"
			end
			return className == "Folder" or className == "Instance"
		end
	elseif key == "GetService" then
		return function(_, serviceName)
			local override = serviceOverrides[serviceName]
			if override ~= nil then
				return override
			end
			local child = findChild(self, serviceName)
			assert(child, "Loader: 서비스 없음 — " .. tostring(serviceName))
			return child
		end
	end
	local child = findChild(self, key)
	if child == nil then
		error(string.format("Loader: %s 는 %s 의 자식이 아닙니다", tostring(key), tostring(props.name)), 2)
	end
	return child
end

nodeMeta.__tostring = function(self)
	return "LoaderNode(" .. self.__props.name .. ")"
end

-- project.json 트리 → 가상 노드
local function buildVirtual(name, def, parent)
	local node = makeNode({
		kind = "virtual",
		name = name,
		parent = parent,
		virtualChildren = {},
	})
	local props = node.__props
	if def["$path"] then
		local path = def["$path"]
		props.path = path
		if fs.isDir(path) then
			local init, initKind = initFile(path)
			if init then
				-- 폴더 모듈을 루트로 둔 경우
				props.kind = initKind or "module"
				props.dir = path
				props.file = init
			else
				props.dir = path
			end
		elseif fs.isFile(path) then
			local _, kind = stripModuleExtension(path)
			props.kind = kind or "file"
			props.file = path
		end
	end
	for key, value in def do
		if string.sub(key, 1, 1) ~= "$" and typeof(value) == "table" then
			props.virtualChildren[key] = buildVirtual(key, value, node)
		end
	end
	return node
end

local root = nil

local function getRoot()
	if root then
		return root
	end
	assert(fs.isFile(PROJECT_FILE), "Loader: 저장소 루트에서 실행하세요 (default.project.json 없음)")
	local project = serde.decode("json", fs.readFile(PROJECT_FILE))
	root = buildVirtual("game", project.tree, nil)
	return root
end

local requireNode -- forward

local function makeEnvironment(node)
	local env = {
		script = node,
		game = getRoot(),
		require = function(target)
			if typeof(target) == "string" then
				error("Loader: 문자열 require 는 지원하지 않습니다 (" .. target .. ")", 2)
			end
			return requireNode(target)
		end,
	}
	for key, value in extraGlobals do
		env[key] = value
	end
	return env
end

requireNode = function(node)
	local props = rawget(node, "__props")
	assert(props, "Loader: require 대상이 노드가 아닙니다")
	if props.kind ~= "module" then
		error("Loader: ModuleScript 가 아닙니다 — " .. tostring(props.name), 2)
	end
	local file = props.file
	if mocks[file] ~= nil then
		return mocks[file]
	end
	if cache[file] ~= nil then
		return cache[file]
	end
	if loading[file] then
		error("Loader: 순환 require — " .. file, 2)
	end
	loading[file] = true
	local source = fs.readFile(file)
	local chunk = luau.load(source, {
		debugName = file,
		environment = makeEnvironment(node),
	})
	local result = chunk()
	loading[file] = nil
	cache[file] = if result == nil then true else result
	return result
end

-- "ReplicatedStorage/Shared/Economy" 같은 경로로 노드 얻기
function Loader.get(path)
	local node = getRoot()
	for part in string.gmatch(path, "[^/%.]+") do
		local child = findChild(node, part)
		assert(child, "Loader: 경로를 찾을 수 없음 — " .. path .. " (" .. part .. ")")
		node = child
	end
	return node
end

function Loader.require(path)
	return requireNode(Loader.get(path))
end

------------------------------------------------------------------
-- 서비스 테스트용 도구 (ServerHarness 가 사용)
------------------------------------------------------------------

-- 가짜 모듈: Loader.mock("ServerScriptService/Server/Services/MapBuilder", { ... })
function Loader.mock(path, value)
	local node = Loader.get(path)
	local props = rawget(node, "__props")
	assert(props.kind == "module" and props.file, "Loader.mock: ModuleScript 가 아님 — " .. path)
	mocks[props.file] = value
end

-- 가짜 서비스: Loader.service("Players", { ... }) → game:GetService("Players") 가 이것을 돌려줌
function Loader.service(name, value)
	serviceOverrides[name] = value
end

-- 모듈 환경에 더할 전역 (Loader.globals({ task = ..., Instance = ... })). 이미 불러온 모듈에는 적용 안 됨.
function Loader.globals(values)
	for key, value in values do
		extraGlobals[key] = value
	end
end

-- 루트(game) 노드: 가짜 game 이 GetService 를 이쪽으로 넘길 때 씀
function Loader.root()
	return getRoot()
end

-- 불러온 모듈 캐시 비우기 (다음 require 때 다시 불러옴). 가짜들은 그대로.
function Loader.reset()
	table.clear(cache)
	table.clear(loading)
end

-- 가짜 모듈·서비스·전역을 전부 치우고 캐시도 비움 (서비스 테스트가 끝난 뒤)
function Loader.clearFakes()
	table.clear(mocks)
	table.clear(serviceOverrides)
	table.clear(extraGlobals)
	Loader.reset()
end

return Loader
