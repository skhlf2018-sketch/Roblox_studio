--!strict
--[[
	State (클라) — 서버가 보낸 Snapshot + DataUpdate 를 합쳐 둔 "내 상태" (화면이 읽는 곳, 첫 게임과 같은 방식)

	  State.onChanged(function(section) ... end)   -- section: "snapshot" | "stats" | "progress" | "passes" | "settings"
	  State.get()                                  -- Types.Snapshot? (아직 안 받았으면 nil)
	  State.number("Power", "power", 0)            -- 플레이어 Attribute 먼저, 없으면 Snapshot 칸, 없으면 기본값
	  State.power() · money() · belt() · dumbbell() · world() · currentWorld() · boost() · broken(id) · activity()

	자주 바뀌는 힘·돈은 서버가 플레이어 Attribute 로도 씀 (Tags.PlayerAttributes). 이 모듈은 표시용 복사본 — 진짜 값은 서버.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local MapLayout = require(Shared.Data.MapLayout)
local Types = require(Shared.Types)
local Net = require(script.Parent.Net)

local State = {}

local Attr = Tags.PlayerAttributes
local snapshot: Types.Snapshot? = nil
local listeners: { (string) -> () } = {}

local function emit(section: string)
	for _, listener in table.clone(listeners) do
		task.spawn(listener, section)
	end
end

function State.get(): Types.Snapshot?
	return snapshot
end

function State.onChanged(listener: (string) -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v
end

-- 플레이어 Attribute → Snapshot 칸 → 기본값
function State.number(attr: string, key: string, default: number): number
	local a = Players.LocalPlayer:GetAttribute(attr)
	if isNumber(a) then
		return a
	end
	local snap = snapshot :: any
	local s = if snap then snap[key] else nil
	if isNumber(s) then
		return s
	end
	return default
end

function State.power(): number
	return State.number(Attr.Power, "power", 0)
end
function State.money(): number
	return State.number(Attr.Money, "money", 0)
end
function State.belt(): number
	return State.number(Attr.Belt, "belt", 1)
end
function State.dumbbell(): number
	return State.number(Attr.DumbbellLevel, "dumbbellLevel", 1)
end
function State.world(): number
	return State.number(Attr.World, "world", 1)
end
function State.currentWorld(): number
	return State.number(Attr.CurrentWorld, "currentWorld", 1)
end
function State.boost(): number
	return math.max(1, State.number(Attr.PowerBoost, "powerBoost", 1))
end

-- 몸 배율 (사장님 결정 13번 — 서버 SizeService 가 Attr BodyScale 로 씀, 1 … Sizes.MAX_SCALE)
function State.bodyScale(): number
	local a = Players.LocalPlayer:GetAttribute(Attr.BodyScale or "BodyScale")
	return if isNumber(a) and (a :: number) >= 1 then a :: number else 1
end

-- 지금 있는 월드의 배율 (MapLayout.worldScale — 월드 1 = 1)
function State.worldScale(): number
	return MapLayout.worldScale(State.currentWorld())
end

function State.moneyPass(): boolean
	local a = Players.LocalPlayer:GetAttribute(Attr.MoneyPass)
	if type(a) == "boolean" then
		return a
	end
	local snap = snapshot
	return snap ~= nil and snap.moneyPass == true
end

-- "" | "exam" | "duel"
function State.activity(): string
	local a = Players.LocalPlayer:GetAttribute(Attr.Activity)
	if type(a) == "string" then
		return a
	end
	local snap = snapshot
	return if snap and type(snap.activity) == "string" then snap.activity else ""
end

-- 물건을 깬 횟수 (도감)
function State.broken(id: string): number
	local snap = snapshot
	local b = if snap and type(snap.broken) == "table" then snap.broken[id] else nil
	return if isNumber(b) then b :: number else 0
end

function State.setting(key: string, default: boolean): boolean
	local snap = snapshot
	local v = if snap and type(snap.settings) == "table" then snap.settings[key] else nil
	if type(v) == "boolean" then
		return v
	end
	return default
end

-- 테스트·다른 컨트롤러가 직접 넣을 때 (서버 이벤트와 같은 처리)
function State.applySnapshot(data: any)
	if type(data) ~= "table" then
		return
	end
	snapshot = data :: Types.Snapshot
	emit("snapshot")
end

function State.applyUpdate(section: string, payload: any)
	local current = snapshot
	if current and type(payload) == "table" then
		local target = current :: any
		for key, value in payload do
			target[key] = value
		end
	end
	emit(tostring(section))
end

function State.start()
	Net.on(Remotes.ToClient.Snapshot, State.applySnapshot)
	Net.on(Remotes.ToClient.DataUpdate, State.applyUpdate)
	-- 힘·돈·띠·월드 Attribute 가 바뀌어도 화면이 다시 그리게
	local player = Players.LocalPlayer
	for _, name in
		{
			Attr.Power,
			Attr.Money,
			Attr.Belt,
			Attr.DumbbellLevel,
			Attr.World,
			Attr.CurrentWorld,
			Attr.PowerBoost,
			Attr.MoneyPass,
			Attr.Activity,
			Attr.BodyScale,
		}
	do
		player:GetAttributeChangedSignal(name):Connect(function()
			emit("attr:" .. name)
		end)
	end
end

return State
