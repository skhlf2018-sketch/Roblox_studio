--!strict
--[[
	DataService — DataStore 저장/불러오기 (ProfileService 없이 직접)

	저장 모양 (키 "player_<UserId>"):
	  { data = PlayerData, _lock = { jobId = 서버 JobId, time = os.time() } | nil }

	- 불러오기: UpdateAsync 로 읽으면서 세션 락을 겁니다.
	    다른 서버의 락이 SESSION_LOCK_STALE_SECONDS 보다 새것이면 기다렸다 재시도,
	    SESSION_LOCK_WAIT_ATTEMPTS 번 기다려도 안 풀리면 락을 가져옴 (단순화).
	    저장된 version 이 이 서버보다 새것이면(롤백·순차 배포) 이번 접속은 저장 끔 + 락 바로 풀기.
	- 저장: UpdateAsync. 다른 서버가 락을 가져갔으면 덮어쓰지 않음 (데이터 롤백 방지)
	    → 그때는 저장을 끄고 플레이어에게 알림 (SaveEnabled Attribute = false).
	- 자동저장 AUTOSAVE_SECONDS(60초), 나갈 때 저장 + 락 해제, BindToClose 로 서버 종료 때 전부 저장.
	- 순서 보장:
	    나갈 때 저장(release)은 진행 중인 자동저장이 끝날 때까지 기다린 뒤 실행.
	    자동저장 transform 은 release 가 시작/성공했으면 쓰지 않고 중단 (락을 다시 걸지 않게).
	    released 는 쓰기가 성공했을 때만 true. 나갈 때 저장이 끝내 실패하면 retryQueue 에 남겨
	    자동저장 주기·BindToClose 에서 다시 시도 (같은 사람이 이 서버에 다시 들어오면 그 데이터를 그대로 이어 씀).
	    BindToClose 는 아직 끝나지 않은 저장(inFlight)까지 전부 기다림 (최대 25초).
	- 불러오는 중에 나가면 data 는 건드리지 않고 _lock 만 지움 (releaseLockOnly) → 오프라인 수입 보존.
	- 실패 대비: pcall + 재시도. 스튜디오에서 DataStore 접근이 막혀 있으면 "메모리 모드"(저장 안 함) + warn.
	  실서버에서 끝내 못 불러오면 그 플레이어는 기본 데이터로 놀고 저장은 꺼둠 (원래 데이터 덮어쓰기 방지).
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Data.Config)
local Tags = require(ReplicatedStorage.Shared.Tags)
local Types = require(ReplicatedStorage.Shared.Types)
local Server = script.Parent.Parent
local DataSchema = require(Server.Logic.DataSchema)
local Sessions = require(Server.Sessions)
local Net = require(Server.Net)

type PlayerData = Types.PlayerData
type Session = Sessions.Session

local DataService = {}

local JOB_ID = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

local store: DataStore? = nil
local memoryMode = false
local inFlight = 0 -- 지금 진행 중인 DataStore 쓰기 수 (BindToClose 가 기다림)
local retryQueue: { [number]: Session } = {} -- 나갈 때 저장이 실패한 세션 (userId → 세션)
-- load 가 retryQueue 에서 꺼내 돌려준 (아직 저장 안 된) 데이터 표시 (약한 키)
local leftovers: { [PlayerData]: boolean } = setmetatable({}, { __mode = "k" }) :: any

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

-- data 는 그대로 두고 우리 서버의 _lock 만 지움 (불러오는 중 나감, 새 버전 데이터)
function DataService.releaseLockOnly(userId: number)
	local ds = store
	if memoryMode or not ds then
		return
	end
	inFlight += 1
	for attempt = 1, Config.DATASTORE_RETRIES do
		local ok, err = pcall(function()
			ds:UpdateAsync(keyFor(userId), function(old: any): any
				local lock = readLock(old)
				if not lock or lock.jobId ~= JOB_ID then
					return nil -- 우리 락이 아니면 손대지 않음
				end
				old._lock = nil
				return old
			end)
		end)
		if ok then
			break
		end
		warn(
			string.format("[DataService] 락 해제 실패 %d/%d: %s", attempt, Config.DATASTORE_RETRIES, tostring(err))
		)
		task.wait(Config.DATASTORE_RETRY_DELAY * attempt)
	end
	inFlight -= 1
end

-- (데이터, 저장 가능 여부, 새 버전 데이터라서 저장을 껐나). 오래 걸릴 수 있음 (yield).
function DataService.load(player: Player): (PlayerData, boolean, boolean)
	local ds = store
	if memoryMode or not ds then
		return DataSchema.default(os.time()), false, false
	end

	-- 이 서버에서 나갈 때 저장이 실패해 남아 있던 데이터가 있으면 그것이 가장 최신
	local leftover = retryQueue[player.UserId]
	if leftover then
		while leftover.saving do
			task.wait(0.1)
		end
		retryQueue[player.UserId] = nil
		local leftoverData = leftover.data
		if not leftover.released and leftoverData then
			warn("[DataService] 저장 못 한 이전 접속 데이터를 이어서 사용: " .. player.Name)
			leftovers[leftoverData] = true
			return leftoverData, true, false
		end
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
			if DataSchema.isNewerVersion(raw) then
				warn(
					string.format(
						"[DataService] %s 데이터 버전 %d > 서버 %d — 이번 접속은 저장하지 않음",
						player.Name,
						DataSchema.versionOf(raw),
						Config.SCHEMA_VERSION
					)
				)
				task.spawn(DataService.releaseLockOnly, player.UserId)
				return DataSchema.reconcile(DataSchema.migrate(raw), os.time()), false, true
			end
			return DataSchema.reconcile(DataSchema.migrate(raw), os.time()), true, false
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
				return DataSchema.default(os.time()), false, false
			end
			if failures >= Config.DATASTORE_RETRIES then
				warn(
					"[DataService] "
						.. player.Name
						.. " 불러오기 최종 실패 — 이번 접속은 저장하지 않음"
				)
				return DataSchema.default(os.time()), false, false
			end
			task.wait(Config.DATASTORE_RETRY_DELAY * failures)
		end
		if player.Parent == nil then
			return DataSchema.default(os.time()), false, false
		end
	end
end

-- 다른 서버가 락을 가져감 → 이 세션은 더 저장하지 않음 + 알림
local function onLockStolen(session: Session)
	session.saveEnabled = false
	local player = session.player
	warn(
		"[DataService] 다른 서버가 " .. player.Name .. " 데이터를 가져가서 이 서버는 저장을 멈춤"
	)
	if player.Parent ~= nil then
		player:SetAttribute(Tags.PlayerAttributes.SaveEnabled, false)
		Net.notify(
			player,
			"error",
			"다른 곳에서 같은 계정으로 접속해서 이 서버는 저장을 멈췄어요. 다시 접속해 주세요."
		)
	end
end

-- 세션 저장 (release = true 면 세션 락 해제). 성공하면 true.
local function saveSession(session: Session, release: boolean): boolean
	if not session.loaded or not session.data then
		return false
	end
	local ds = store
	if memoryMode or not ds or not session.saveEnabled or session.released then
		return false
	end
	if release then
		-- 진행 중인 자동저장이 끝날 때까지 기다림 (두 UpdateAsync 가 엇갈리지 않게)
		while session.saving do
			task.wait(0.1)
		end
		if session.released or not session.saveEnabled then
			return session.released
		end
	elseif session.saving or session.releasing then
		return false
	end

	local data = session.data :: PlayerData
	session.saving = true
	if release then
		session.releasing = true
	end
	inFlight += 1
	data.lastSaveTime = os.time()

	local key = keyFor(session.userId)
	local success = false
	local stolen = false
	for attempt = 1, Config.DATASTORE_RETRIES do
		local aborted: string? = nil
		local ok, err = pcall(function()
			ds:UpdateAsync(key, function(old: any): any
				if lockedByOther(old, os.time()) then
					aborted = "stolen"
					return nil
				end
				if not release and (session.released or session.releasing) then
					aborted = "released" -- 나갈 때 저장이 이미 시작/완료됨 → 락을 다시 걸지 않음
					return nil
				end
				return {
					data = data,
					_lock = if release then nil else { jobId = JOB_ID, time = os.time() },
				}
			end)
		end)
		if ok then
			stolen = aborted == "stolen"
			success = aborted == nil
			break
		end
		warn(
			string.format(
				"[DataService] 저장 실패 %d/%d (%s): %s",
				attempt,
				Config.DATASTORE_RETRIES,
				session.player.Name,
				tostring(err)
			)
		)
		if not release and (session.released or session.releasing) then
			break -- 나갈 때 저장이 대신 처리함
		end
		task.wait(Config.DATASTORE_RETRY_DELAY * attempt)
	end

	session.saving = false
	if release then
		session.releasing = false
		if success then
			session.released = true
		end
	end
	inFlight -= 1
	if stolen then
		onLockStolen(session)
	end
	return success
end

-- 저장 (release = true 면 세션 락 해제). 성공하면 true.
function DataService.save(player: Player, release: boolean): boolean
	local session = Sessions.get(player)
	if not session then
		return false
	end
	return saveSession(session, release)
end

-- 나갈 때 저장이 실패한 세션을 다시 시도 목록에 넣음 (PlayerLifecycle 이 Sessions.remove 하기 전에)
function DataService.queueRelease(session: Session)
	if memoryMode or not session.loaded or not session.saveEnabled or session.released then
		return
	end
	retryQueue[session.userId] = session
	warn("[DataService] 나갈 때 저장 실패 — 나중에 다시 시도: " .. session.player.Name)
end

-- 불러오는 중에 나감: 보통은 data 를 건드리지 않고 락만 풂 (lastSaveTime 을 새로 찍지 않아 오프라인 수입 보존).
-- 단, 이 서버에 남아 있던 "저장 못 한" 데이터를 이어받은 경우는 그 데이터를 저장해야 함.
function DataService.abandonLoad(session: Session, data: PlayerData, saveEnabled: boolean)
	if not saveEnabled or memoryMode then
		return
	end
	if leftovers[data] then
		leftovers[data] = nil
		session.data = data
		session.saveEnabled = true
		session.loaded = true
		if not saveSession(session, true) then
			DataService.queueRelease(session)
		end
		return
	end
	DataService.releaseLockOnly(session.userId)
end

local function retryPending()
	for userId, session in retryQueue do
		if session.released or not session.saveEnabled then
			retryQueue[userId] = nil
		elseif not session.saving then
			task.spawn(function()
				if saveSession(session, true) or not session.saveEnabled then
					if retryQueue[userId] == session then
						retryQueue[userId] = nil
					end
				end
			end)
		end
	end
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

	-- 자동 저장 + 실패한 나가기 저장 재시도
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_SECONDS)
			for _, session in Sessions.all() do
				if
					session.loaded
					and session.saveEnabled
					and not session.released
					and not session.releasing
					and not session.saving
				then
					task.spawn(saveSession, session, false)
				end
			end
			retryPending()
		end
	end)

	-- 서버 종료 때 전부 저장 (진행 중인 저장까지 최대 약 25초 기다림)
	game:BindToClose(function()
		if memoryMode then
			return
		end
		local pending = 0
		local function run(session: Session)
			pending += 1
			task.spawn(function()
				saveSession(session, true)
				pending -= 1
			end)
		end
		for _, session in Sessions.all() do
			if session.loaded and session.saveEnabled and not session.released then
				run(session)
			end
		end
		for _, session in retryQueue do
			if session.saveEnabled and not session.released then
				run(session)
			end
		end
		local deadline = os.clock() + 25
		while (pending > 0 or inFlight > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
