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
				"[Snapshot] 돈 %s, 속도 %s, 펫 %d마리(장착 %d/%d), 부화 중 %d개, 베이스 %d번",
				Format.money(snapshot.money),
				Format.number(snapshot.effectiveSpeed),
				#snapshot.pets,
				#snapshot.equipped,
				snapshot.penSlots,
				#snapshot.incubators,
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
				"RUN!! %s 알을 들었어요! 경비 %s (경비 속도 %s / 내 속도 %s)",
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
				"[잡힘] %s 에게 (%s) — 알: %s",
				tostring(payload.by),
				payload.cause,
				payload.eggOutcome
			)
		)
	end)
	Net.on(E.EggDelivered, function(record: any)
		print(
			string.format(
				"[배달] %s 알 → 부화 슬롯 %d (%s)",
				petName(record.petId),
				record.slot,
				Format.duration(record.required)
			)
		)
	end)
	Net.on(E.HatchResult, function(payload: any)
		print(
			string.format(
				"[부화] %s! 초당 %s%s",
				petName(payload.pet.petId),
				Format.money(payload.income),
				if payload.isNew then " (도감 새로 발견!)" else ""
			)
		)
	end)
	Net.on(E.OfflineIncome, function(payload: any)
		print(
			string.format(
				"[오프라인 수입] %s (하루 %s)",
				Format.money(payload.amount),
				Format.money(payload.perDay)
			)
		)
	end)
	Net.on(E.IndexRewarded, function(payload: any)
		print(
			string.format(
				"[도감 보상] 속도 +%s, 돈 +%s",
				Format.number(payload.speed),
				Format.money(payload.money)
			)
		)
	end)
end

return DebugController
