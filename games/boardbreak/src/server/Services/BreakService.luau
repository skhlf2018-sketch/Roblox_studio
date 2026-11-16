--!strict
--[[
	BreakService — 물건 치기 (Remote Hit(targetId)) — 서버 판정 (설계서 2장·3장, 규칙은 shared/BreakRules)
	  - targetId = "exam" / "duel" 이면 심사·대결 송판 → ExamService.hit (같은 Remote · 같은 속도 제한)
	  - 없는 id · 닫힌 월드의 물건 · 너무 먼 거리 → 무시 (거리 = 선임 MapLayout.targetPosition(id) 와 캐릭터 위치,
	    닿는 거리 MapLayout.targetReach(id) + Config.HIT_REACH_SLACK)
	  - 치는 힘(힘 × PowerBoost) < minPower → 피해 0 + HitResult reason "weak" + 알림 "힘이 부족해요" (2초에 한 번)
	  - 체력은 플레이어마다 따로 (session.targetHp). 깨지면 돈 = reward × 띠 배율 × (돈 2배면 2) · broken[id] += 1 · 체력 다시 가득
	  - 속도 제한: Remotes.RateLimits.Hit (초당 5번, 넘으면 버림 — Net.on)
	  → HitResult { targetId, damage, hp, hpMax, broken, reward?, reason? } (나에게만) · Attr Money (Wallet)
	    처음 깬 물건이면 DataUpdate "progress" (도감)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local MapLayout = require(Shared.Data.MapLayout)
local Economy = require(Shared.Economy)
local BreakRules = require(Shared.BreakRules)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Snapshot = require(Server.Snapshot)
local Validate = require(Server.Logic.Validate)
local Character = require(Server.Util.Character)
local Wallet = require(script.Parent.Wallet)
local ExamService = require(script.Parent.ExamService)

local BreakService = {}

BreakService.WEAK_TEXT = "힘이 부족해요! 아령을 더 들어요."

-- 한 번 치기 (Remote 와 테스트가 같이 씀). 판정이 났으면 HitResult, 무시했으면 nil
function BreakService.hit(player: Player, rawId: unknown): Types.HitResult?
	local session, data = Sessions.getLoaded(player)
	if not session or not data then
		return nil
	end
	local id = Validate.uid(rawId)
	if not id then
		return nil
	end
	if id == Remotes.EXAM_TARGET or id == Remotes.DUEL_TARGET then
		ExamService.hit(player, id)
		return nil
	end
	local root = Character.getRoot(player)
	if not root then
		return nil
	end
	local target = BreakRules.check(
		id,
		data.world,
		root.Position,
		MapLayout.targetPosition(id),
		MapLayout.targetReach(id),
		Config.HIT_REACH_SLACK
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
	if outcome.reason == "weak" then
		if Sessions.useCooldown(session, "weak", 2, os.clock()) then
			Net.notify(
				player,
				"error",
				string.format(
					"%s (%s 은 힘 %s 부터)",
					BreakService.WEAK_TEXT,
					target.name,
					Format.number(target.minPower)
				)
			)
		end
	elseif outcome.broken then
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
