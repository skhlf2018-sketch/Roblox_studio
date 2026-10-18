--!strict
--[[
	DataService — DataStore 저장/불러오기 (ProfileService 없이 직접)

	저장 모양 (키 "player_<UserId>"):
	  { data = PlayerData, _lock = { jobId = 서버 JobId, time = os.time() } | nil }

	- 불러오기: UpdateAsync 로 읽으면서 세션 락을 겁니다.
	    다른 서버의 락이 SESSION_LOCK_STALE_SECONDS 보다 새것이면 기다렸다 재시도,
	    SESSION_LOCK_WAIT_ATTEMPTS 번 기다려도 안 풀리면 락을 가져옴 (단순화).
	- 저장: UpdateAsync. 다른 서버가 락을 가져갔으면 덮어쓰지 않음 (데이터 롤백 방지).
	- 자동저장 AUTOSAVE_SECONDS(60초), 나갈 때 저장 + 락 해제, BindToClose 로 서버 종료 때 전부 저장.
	- 실패 대비: pcall + 재시도. 스튜디오에서 DataStore 접근이 막혀 있으면 "메모리 모드"(저장 안 함) + warn.
	  실서버에서 끝내 못 불러오면 그 플레이어는 기본 데이터로 놀고 저장은 꺼둠 (원래 데이터 덮어쓰기 방지).
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Data.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Server = script.Parent.Parent
local DataSchema = require(Server.Logic.DataSchema)
local Sessions = require(Server.Sessions)

type PlayerData = Types.PlayerData

local DataService = {}

local JOB_ID = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

local store: DataStore? = nil
local memoryMode = false

local function enterMemoryMode(reason: string)
	if memoryMode then
		return
	end
	memoryMode = true
	warn("[DataService] 메모리 모드 (이번 서버는 저장 안 함): " .. reason)
end

function DataService.isMemoryMode(): boolean
	return memoryMode
end

local function keyFor(userId: number): string
	return Config.DATASTORE_KEY_PREFIX .. tostring(userId)
end

type StoredLock = { jobId: string, time: number }

local function readLock(stored: unknown): StoredLock?
	if typeof(stored) ~= "table" then
		return nil
	end
	local lock = (stored :: { [string]: unknown })._lock
	if typeof(lock) ~= "table" then
		return nil
	end
	local l = lock :: { [string]: unknown }
	if typeof(l.jobId) ~= "string" or typeof(l.time) ~= "number" then
		return nil
	end
	return { jobId = l.jobId :: string, time = l.time :: number }
end

local function lockedByOther(stored: unknown, now: number): boolean
	local lock = readLock(stored)
	return lock ~= nil and lock.jobId ~= JOB_ID and (now - lock.time) < Config.SESSION_LOCK_STALE_SECONDS
end

-- 한 번 시도: (성공, 원시 데이터, 다른 서버가 잠금 중)
local function tryLoad(ds: DataStore, key: string, force: boolean): (boolean, unknown, boolean)
	local rawData: unknown = nil
	local locked = false
	local ok, err = pcall(function()
		ds:UpdateAsync(key, function(old: any): any
			local now = os.time()
			if not force and lockedByOther(old, now) then
				locked = true
				return nil -- 쓰지 않고 취소
			end
			locked = false
			local wrapper: { [string]: any } = if typeof(old) == "table" then old else {}
			rawData = wrapper.data
			wrapper._lock = { jobId = JOB_ID, time = now }
			return wrapper
		end)
	end)
	if not ok then
		warn("[DataService] 불러오기 실패: " .. tostring(err))
		return false, nil, false
	end
	return true, rawData, locked
end

-- (데이터, 저장 가능 여부). 오래 걸릴 수 있음 (yield).
function DataService.load(player: Player): (PlayerData, boolean)
	local ds = store
	if memoryMode or not ds then
		return DataSchema.default(os.time()), false
	end
	local key = keyFor(player.UserId)
	local lockWaits = 0
	local failures = 0
	while true do
		local force = lockWaits >= Config.SESSION_LOCK_WAIT_ATTEMPTS
		local ok, raw, locked = tryLoad(ds, key, force)
		if ok and not locked then
			if force then
				warn("[DataService] 오래된 세션 락을 가져옴: " .. player.Name)
			end
			return DataSchema.reconcile(DataSchema.migrate(raw), os.time()), true
		elseif ok and locked then
			lockWaits += 1
			warn(
				string.format(
					"[DataService] %s 데이터가 다른 서버에서 사용 중 — 기다리는 중 (%d)",
					player.Name,
					lockWaits
				)
			)
			task.wait(Config.SESSION_LOCK_WAIT_SECONDS)
		else
			failures += 1
			if RunService:IsStudio() then
				enterMemoryMode(
					"스튜디오에서 DataStore 를 쓸 수 없음 (게임 설정 > 보안 > 'Studio에서 API 서비스 접근 허용' 확인)"
				)
				return DataSchema.default(os.time()), false
			end
			if failures >= Config.DATASTORE_RETRIES then
				warn(
					"[DataService] "
						.. player.Name
						.. " 불러오기 최종 실패 — 이번 접속은 저장하지 않음"
				)
				return DataSchema.default(os.time()), false
			end
			task.wait(Config.DATASTORE_RETRY_DELAY * failures)
		end
		if player.Parent == nil then
			return DataSchema.default(os.time()), false
		end
	end
end

-- 저장 (release = true 면 세션 락 해제). 성공하면 true.
function DataService.save(player: Player, release: boolean): boolean
	local session = Sessions.get(player)
	if not session or not session.loaded then
		return false
	end
	local data = session.data
	if not data then
		return false
	end
	data.lastSaveTime = os.time()
	local ds = store
	if memoryMode or not ds or not session.saveEnabled or session.released then
		return false
	end
	if session.saving and not release then
		return false
	end
	session.saving = true
	if release then
		session.released = true -- 이후 자동저장이 다시 락을 걸지 않도록
	end
	local key = keyFor(player.UserId)
	local success = false
	for attempt = 1, Config.DATASTORE_RETRIES do
		local aborted = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key, function(old: any): any
				if lockedByOther(old, os.time()) then
					aborted = true
					return nil
				end
				return {
					data = data,
					_lock = if release then nil else { jobId = JOB_ID, time = os.time() },
				}
			end)
		end)
		if ok then
			if aborted then
				warn(
					"[DataService] 다른 서버가 " .. player.Name .. " 데이터를 가져가서 저장을 취소함"
				)
				session.saveEnabled = false
			end
			success = not aborted
			break
		end
		warn(
			string.format(
				"[DataService] 저장 실패 %d/%d (%s): %s",
				attempt,
				Config.DATASTORE_RETRIES,
				player.Name,
				tostring(err)
			)
		)
		task.wait(Config.DATASTORE_RETRY_DELAY * attempt)
	end
	session.saving = false
	return success
end

function DataService.start()
	local ok, result = pcall(function(): DataStore
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		enterMemoryMode("GetDataStore 실패: " .. tostring(result))
	end

	-- 자동 저장
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_SECONDS)
			for player, session in Sessions.all() do
				if session.loaded and session.saveEnabled and not session.released and not session.saving then
					task.spawn(DataService.save, player, false)
				end
			end
		end
	end)

	-- 서버 종료 때 전부 저장 (최대 약 25초)
	game:BindToClose(function()
		if memoryMode then
			return
		end
		local pending = 0
		for player, session in Sessions.all() do
			if session.loaded and session.saveEnabled and not session.released then
				pending += 1
				task.spawn(function()
					DataService.save(player, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
