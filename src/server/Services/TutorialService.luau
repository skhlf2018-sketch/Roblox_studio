--!strict
--[[
	TutorialService — 처음 온 사람 튜토리얼 5단계 (5판, 사장님 지시). 단계·글은 shared/Data/Tutorial, 규칙은 shared/TutorialRules

	저장: data.tutorialStep (1~5 = 지금 단계, 6 = 끝). 새 사람은 1, 이미 놀던 사람은 마이그레이션 때 6.
	진행 (기존 서비스 신호 → TutorialRules.advance):
	  EggService.pickedUp   알을 주움            1 → 2
	  EggService.lost       든 알을 놓침         2 → 1
	  BaseService.delivered 가방에 들어감        1, 2 → 3
	  BaseService.placed    우리에 놓음          3 → 4
	  BaseService.unplaced  다시 가방으로        4 → 3 (우리가 비었을 때)
	  BaseService.hatched   부화                 3, 4 → 5   (튜토리얼 중엔 자동 장착 안 함: BaseService/TutorialRules.holdsAutoEquip)
	  PetService.equipChanged 장착               5 → 끝 (장착 펫 1마리 이상)
	단계가 바뀌면: data 저장 + TutorialUpdate(TutorialView) + DataUpdate("tutorial", { tutorial }) (State 가 합침)
	끝나면: 돈 + Data/Tutorial.REWARD_MONEY($500), Notify, TutorialUpdate { done = true, reward = 500 } (한 번만)
	접속 때: TutorialRules.normalize 로 저장된 단계를 지금 상태에 맞춤 (알 든 채 나갔으면 2 → 1 등) → 끝나지 않았으면 TutorialUpdate.
	개발 명령: /tutorial reset → TutorialService.reset (1단계부터 다시, 보상도 다시 받음)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tutorial = require(Shared.Data.Tutorial)
local TutorialRules = require(Shared.TutorialRules)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Wallet = require(script.Parent.Wallet)
local EggService = require(script.Parent.EggService)
local BaseService = require(script.Parent.BaseService)
local PetService = require(script.Parent.PetService)

local TutorialService = {}

-- 판정에 쓰는 지금 상태
local function contextFor(player: Player): TutorialRules.Context?
	local _, data = Sessions.getLoaded(player)
	if not data then
		return nil
	end
	return {
		carrying = EggService.getCarried(player) ~= nil,
		bagEggs = #data.eggs,
		placedEggs = #data.incubators,
		pets = #data.pets,
		equipped = #data.equipped,
	}
end

-- 지금 단계를 클라에 (reward 는 끝내는 순간에만)
local function send(player: Player, step: number, reward: number?)
	Net.fire(player, Remotes.ToClient.TutorialUpdate, TutorialRules.view(step, reward))
	Snapshot.section(player, "tutorial")
end

-- 단계를 바꿈 (같으면 아무것도 안 함). 끝으로 바뀌면 보상
local function setStep(player: Player, step: number)
	local _, data = Sessions.getLoaded(player)
	if not data or data.tutorialStep == step then
		return
	end
	data.tutorialStep = step
	if TutorialRules.isDone(step) then
		Wallet.addMoney(player, Tutorial.REWARD_MONEY)
		Net.notify(
			player,
			"success",
			"튜토리얼 끝! 보상 " .. Format.money(Tutorial.REWARD_MONEY) .. " 을 받았어요!"
		)
		send(player, step, Tutorial.REWARD_MONEY)
	else
		send(player, step)
	end
end

-- 일이 하나 일어남 → 다음 단계 (튜토리얼이 끝난 사람은 아무것도 안 함)
function TutorialService.record(player: Player, event: TutorialRules.Event)
	local _, data = Sessions.getLoaded(player)
	if not data or TutorialRules.isDone(data.tutorialStep) then
		return
	end
	local ctx = contextFor(player)
	if not ctx then
		return
	end
	setStep(player, TutorialRules.advance(data.tutorialStep, event, ctx))
end

-- 지금 단계 (테스트·개발 명령용). 데이터가 없으면 nil
function TutorialService.getStep(player: Player): number?
	local _, data = Sessions.getLoaded(player)
	return if data then data.tutorialStep else nil
end

-- 개발 명령 /tutorial reset: 1단계부터 다시
function TutorialService.reset(player: Player)
	local _, data = Sessions.getLoaded(player)
	if not data then
		return
	end
	data.tutorialStep = 1
	send(player, 1)
end

-- PlayerLifecycle 준비 단계 (Snapshot 보다 먼저: Snapshot.tutorial 이 맞춘 단계로 나가게)
function TutorialService.onPlayerReady(player: Player)
	local _, data = Sessions.getLoaded(player)
	local ctx = contextFor(player)
	if not data or not ctx or TutorialRules.isDone(data.tutorialStep) then
		return
	end
	data.tutorialStep = TutorialRules.normalize(data.tutorialStep, ctx)
	Net.fire(player, Remotes.ToClient.TutorialUpdate, TutorialRules.view(data.tutorialStep))
end

function TutorialService.start()
	EggService.pickedUp:connect(function(player: Player)
		TutorialService.record(player, "steal")
	end)
	EggService.lost:connect(function(player: Player)
		TutorialService.record(player, "lost")
	end)
	BaseService.delivered:connect(function(player: Player)
		TutorialService.record(player, "deliver")
	end)
	BaseService.placed:connect(function(player: Player)
		TutorialService.record(player, "place")
	end)
	BaseService.unplaced:connect(function(player: Player)
		TutorialService.record(player, "unplace")
	end)
	BaseService.hatched:connect(function(player: Player)
		TutorialService.record(player, "hatch")
	end)
	PetService.equipChanged:connect(function(player: Player)
		TutorialService.record(player, "equip")
	end)
end

return TutorialService
