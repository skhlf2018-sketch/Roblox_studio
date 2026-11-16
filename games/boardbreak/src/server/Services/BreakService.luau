--!strict
--[[
	BreakService — 물건 치기 (Remote Hit(targetId)) — 서버 판정 (설계서 2장·3장, 규칙은 shared/BreakRules)
	  - targetId = "exam" / "duel" 이면 심사·대결 송판 → ExamService.hit (같은 Remote · 같은 속도 제한)
	  - 없는 id · 닫힌 월드의 물건 · 너무 먼 거리 → 무시 (거리 = 선임 MapLayout.targetPosition(id) 와 캐릭터 위치,
	    닿는 거리 MapLayout.targetReach(id) + 여유. 여유 = Config.HIT_REACH_SLACK × 그 물건 월드의 Sizes.worldScale
	    + 몸이 커진 만큼 SizeService.bodyExtra, 높이 여유 = BreakRules.VERTICAL_SLACK × worldScale — BreakService.slackFor)
	  - 힘 문턱 없음 (사장님 결정 11번): 피해 = 치는 힘(힘 × PowerBoost) 그대로 — 약하면 여러 번 쳐야 할 뿐. recommendPower 는 화면 표시용
	  - 체력은 플레이어마다 따로 (session.targetHp). 깨지면 돈 = reward × 띠 배율 × (돈 2배면 2) · broken[id] += 1 · 체력 다시 가득
	  - 속도 제한: Remotes.RateLimits.Hit (초당 5번, 넘으면 버림 — Net.on)
	  → HitResult { targetId, damage, hp, hpMax, broken, reward?, reason? } (나에게만) · Attr Money (Wallet)
	    처음 깬 물건이면 DataUpdate "progress" (도감)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local MapLayout = require(Shared.Data.MapLayout)
local Sizes = require(Shared.Data.Sizes)
local Targets = require(Shared.Data.Targets)
local Economy = require(Shared.Economy)
local BreakRules = require(Shared.BreakRules)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)
local Character = require(Server.Util.Character)
local Wallet = require(script.Parent.Wallet)
local SizeService = require(script.Parent.SizeService)
local ExamService = require(script.Parent.ExamService)

local BreakService = {}

-- 이 플레이어가 이 물건을 칠 때 여유 (targetReach 에 더함): (수평 여유, 높이 여유)
--   월드가 크면 그만큼 (worldScale), 몸이 크면 팔·뿌리 높이만큼 (bodyExtra — 수평 여유에 넣으면 높이 여유에도 들어감)
function BreakService.slackFor(player: Player, id: string): (number, number)
	local target = Targets.get(id)
	local scale = Sizes.worldScale(if target then target.world else 1)
	return Config.HIT_REACH_SLACK * scale + SizeService.bodyExtra(player), BreakRules.VERTICAL_SLACK * scale
end

-- 한 번 치기 (Remote 와 테스트가 같이 씀). 판정이 났으면 HitResult, 무시했으면 nil
function BreakService.hit(player: Player, rawId: unknown): Types.HitResult?
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return nil
	end
	local id = Validate.uid(rawId)
	if not id or not Character.isAlive(player) then
		return nil -- 죽은 캐릭터(Health 0)는 못 침 (A-1)
	end
	if id == Remotes.EXAM_TARGET or id == Remotes.DUEL_TARGET then
		ExamService.hit(player, id)
		return nil
	end
	local root = Character.getRoot(player)
	if not root then
		return nil
	end
	local slack, vertical = BreakService.slackFor(player, id)
	local target = BreakRules.check(
		id,
		data.world,
		root.Position,
		MapLayout.targetPosition(id),
		MapLayout.targetReach(id),
		slack,
		vertical
	)
	if not target then
		return nil
	end
	data.stats.hits += 1
	local outcome = BreakRules.hit(session.targetHp, target, Economy.hitDamage(data.power, data.powerBoost))
	local result: Types.HitResult = {
		targetId = target.id,
		damage = outcome.damage,
		hp = outcome.hp,
		hpMax = outcome.hpMax,
		broken = outcome.broken,
		reward = nil,
		reason = outcome.reason,
	}
	if outcome.broken then
		local reward = Wallet.addMoney(player, Economy.breakReward(target.reward, data.belt, data.moneyPass))
		local first = (data.broken[target.id] or 0) == 0
		data.broken[target.id] = math.min(1e15, (data.broken[target.id] or 0) + 1)
		data.stats.breaks += 1
		data.stats.moneyEarned = Economy.addMoney(data.stats.moneyEarned, reward)
		result.reward = reward
		if first then
			Snapshot.section(player, "progress")
		end
	end
	Net.fire(player, Remotes.ToClient.HitResult, result)
	return result
end

function BreakService.start()
	Net.on(Remotes.ToServer.Hit, function(player: Player, targetId: unknown)
		BreakService.hit(player, targetId)
	end)
end

return BreakService
