--!strict
--[[
	DebugController — UI 가 생기기 전까지 서버 이벤트를 출력 창에 찍어 보여줌 (선임이 UI 를 붙이면 지워도 됨)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Data = Shared.Data
local Pets = require(Data.Pets)
local Net = require(script.Parent.Parent.Net)

local DebugController = {}

local function petName(petId: string): string
	local pet = Pets.get(petId)
	return if pet then pet.name else petId
end

function DebugController.start()
	local E = Remotes.ToClient

	Net.on(E.Snapshot, function(snapshot: any)
		print(
			string.format(
				"[Snapshot] 코인 %s, 속도 %s, 정원 %d/%d (성체 %d · 자라는 씨앗 %d), 씨앗 가방 %d개, 베이스 %d번",
				Format.number(snapshot.money),
				Format.number(snapshot.effectiveSpeed),
				#(snapshot.pets or {}) + #(snapshot.incubators or {}),
				snapshot.penSlots,
				#(snapshot.pets or {}),
				#(snapshot.incubators or {}),
				#(snapshot.eggs or {}),
				snapshot.plotIndex
			)
		)
	end)
	Net.on(E.DataUpdate, function(section: string)
		print("[DataUpdate] " .. section)
	end)
	Net.on(E.Notify, function(payload: any)
		local text = if typeof(payload) == "table" then tostring(payload.text) else tostring(payload)
		if typeof(payload) == "table" and payload.kind == "error" then
			warn("[알림] " .. text)
		else
			print("[알림] " .. text)
		end
	end)
	Net.on(E.PhaseChanged, function(payload: any)
		print(
			string.format(
				"[주기] %s (%d초, %d번째)",
				tostring(payload.phase),
				math.floor(tonumber(payload.duration) or 0),
				math.floor(tonumber(payload.cycleNumber) or 0)
			)
		)
	end)
	Net.on(E.RunAlert, function(payload: any)
		warn(
			string.format(
				"RUN!! %s 씨앗을 들었어요! 경비 %s (경비 속도 %s / 내 속도 %s)",
				petName(payload.egg.petId),
				tostring(payload.guardName),
				Format.number(payload.guardSpeed),
				Format.number(payload.yourSpeed)
			)
		)
	end)
	Net.on(E.ChaseEnded, function(payload: any)
		print("[추격 끝] " .. tostring(payload.biomeId))
	end)
	Net.on(E.Caught, function(payload: any)
		warn(
			string.format(
				"[잡힘] %s 에게 (%s) — 씨앗: %s",
				tostring(payload.by),
				payload.cause,
				payload.eggOutcome
			)
		)
	end)
	-- 2판 수정: 배달한 씨앗은 씨앗 가방으로 (slot 없음 — BagEgg)
	Net.on(E.EggDelivered, function(record: any)
		if typeof(record) ~= "table" then
			return
		end
		print(
			string.format(
				"[배달] %s 씨앗 → 씨앗 가방 (성체까지 %s)",
				petName(tostring(record.petId)),
				Format.duration(tonumber(record.required) or 0)
			)
		)
	end)
	-- 6판: 씨앗이 정원에서 성체가 됨 (5판 HatchResult 자리). 오프라인 수입(OfflineIncome)은 없어짐
	Net.on(E.PlantGrown, function(payload: any)
		print(
			string.format(
				"[성체] %s! 열매 1개 %s 코인%s",
				petName(payload.plant.petId),
				Format.number(payload.fruitValue),
				if payload.isNew then " (도감 새로 발견!)" else ""
			)
		)
	end)
	Net.on(E.IndexRewarded, function(payload: any)
		print(
			string.format(
				"[도감 보상] 속도 +%s, 코인 +%s",
				Format.number(payload.speed),
				Format.number(payload.money)
			)
		)
	end)
end

return DebugController
