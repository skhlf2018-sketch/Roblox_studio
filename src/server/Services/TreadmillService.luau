--!strict
--[[
	TreadmillService — 러닝머신 2판 (설계 2판 D: 원작처럼 올라서면 고정돼 제자리에서 달림)

	- 내 베이스 러닝머신 벨트(MapLayout.treadmillRect(plotIndex), 앞마당) 위에 올라서면 서버가 태움:
	    플레이어 Attr OnTreadmill = true, WalkSpeed 0 (WASD 무시), 캐릭터를 벨트 가운데로 옮겨 복도 쪽을 보게 함.
	    (HumanoidRootPart Anchored·PlatformStand 안 씀 → 점프는 됨)
	- 1초(TREADMILL_TICK_SECONDS)마다 걸음 1번: 속도 += 걸음당 속도(Upgrades 러닝머신 레벨) × TREADMILL_MULTIPLIER(6판 4)
	    → Wallet.addSpeed + TreadmillStep { amount } (클라 "+500" 분홍 팝업)
	- 내리기: 클라가 점프할 때 TreadmillLeave() → 벨트 앞(복도 쪽)으로 내려 줌.
	    클라가 안 보내도 점프하면 몸통이 TREADMILL_MAX_HEIGHT(8) 위로 떠서 서버가 내려 줌 (그 자리 착지 → 걸어서 나가면 됨).
	    서버도 0.2초마다 확인해서 벨트 위를 벗어났거나(높이 TREADMILL_MAX_HEIGHT 위로 떴거나) 알을 들었거나
	    기절·죽음이면 자동으로 내림. 내린 뒤에는 벨트 밖으로 한 번 나가야 다시 탈 수 있음 (점프 착지로 바로 다시 타지 않게).
	- 벨트 위에서 밀려나면(물리) 가운데로 되돌림 (TREADMILL_PIN_TOLERANCE). 서버 순간이동이라 위치 검증(AntiCheat)은 잠깐 쉼.
	- 러닝머신 0레벨(잠김)이면 안 탐 → 5초에 한 번 "러닝머신을 먼저 사세요" 안내.
	- 다른 사람 베이스 러닝머신은 못 씀 (허브 = 안전 구역이라 방해도 못 함).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local MapLayout = require(Shared.Data.MapLayout)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Server = script.Parent.Parent
local Net = require(Server.Net)
local Sessions = require(Server.Sessions)
local Character = require(Server.Util.Character)
local Wallet = require(script.Parent.Wallet)
local SpeedService = require(script.Parent.SpeedService)

local Attr = Tags.PlayerAttributes

local TreadmillService = {}

-- 캐릭터를 (x, z) 로 옮기고 lookX 쪽(복도)을 보게 함 — 서버 순간이동 (위치 검증 쉼)
local function placeAt(player: Player, session: Sessions.Session, x: number, z: number, lookX: number)
	local character = player.Character
	local root = Character.getRoot(player)
	if not character or not root then
		return
	end
	local position = Vector3.new(x, root.Position.Y, z)
	Sessions.exemptMovement(session, Config.MOVE_CHECK_EXEMPT_AFTER_TELEPORT)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(position, position + Vector3.new(lookX, 0, 0)))
end

local function setOn(player: Player, session: Sessions.Session, on: boolean)
	if session.onTreadmill == on then
		return
	end
	session.onTreadmill = on
	player:SetAttribute(Attr.OnTreadmill, on)
	SpeedService.refresh(player)
end

local function mount(player: Player, session: Sessions.Session)
	local plot = MapLayout.plot(session.plotIndex)
	if not plot then
		return
	end
	setOn(player, session, true)
	placeAt(player, session, plot.treadmill.x, plot.treadmill.z, plot.facing)
end

-- 내리기. stepOff = true 면 벨트 앞(복도 쪽)으로 내려 줌 (점프로 내릴 때)
function TreadmillService.leave(player: Player, stepOff: boolean?)
	local session = Sessions.get(player)
	if not session or not session.onTreadmill then
		return
	end
	setOn(player, session, false)
	session.treadmillArmed = false
	if stepOff then
		local plot = MapLayout.plot(session.plotIndex)
		if plot then
			local offset = MapLayout.TREADMILL_PAD.sizeX / 2 + 3
			placeAt(player, session, plot.treadmill.x + plot.facing * offset, plot.treadmill.z, plot.facing)
		end
	end
end

function TreadmillService.isOn(player: Player): boolean
	local session = Sessions.get(player)
	return session ~= nil and session.onTreadmill
end

-- 벨트 위인가 (수평 + 높이)
local function standingOn(root: BasePart, plotIndex: number): boolean
	return MapLayout.isOnTreadmill(root.Position, plotIndex, Config.TREADMILL_PAD_MARGIN)
		and root.Position.Y - MapLayout.FLOOR_Y < Config.TREADMILL_MAX_HEIGHT
end

-- 0.2초마다: 타기 / 내리기 / 가운데 고정
local function positionTick(): ...any
	local now = os.clock()
	for player, session in Sessions.all() do
		local data = session.data
		local root = Character.getRoot(player)
		if session.loaded and data and session.plotIndex > 0 and root then
			local on = standingOn(root, session.plotIndex)
			local blocked = session.carryingUid ~= nil
				or Sessions.isStunned(session, now)
				or not Character.isAlive(player)
				or data.treadmillLevel < 1
			if session.onTreadmill then
				if not on or blocked then
					TreadmillService.leave(player, false)
				else
					local plot = MapLayout.plot(session.plotIndex)
					if plot then
						local dx = root.Position.X - plot.treadmill.x
						local dz = root.Position.Z - plot.treadmill.z
						if math.sqrt(dx * dx + dz * dz) > Config.TREADMILL_PIN_TOLERANCE then
							placeAt(player, session, plot.treadmill.x, plot.treadmill.z, plot.facing)
						end
					end
				end
			elseif not on then
				session.treadmillArmed = true
			elseif session.treadmillArmed and not blocked then
				mount(player, session)
			elseif data.treadmillLevel < 1 and session.treadmillArmed then
				if Sessions.useCooldown(session, "treadmillLockedNotice", 5, now) then
					local cost = Economy.nextTreadmillCost(0)
					Net.notify(
						player,
						"info",
						"러닝머신이 잠겨 있어요! 상점에서 먼저 사세요"
							.. (if cost then " (" .. Format.money(cost) .. ")" else "")
					)
				end
			end
		elseif session.onTreadmill then
			TreadmillService.leave(player, false)
		end
	end
end

-- 1초마다: 러닝머신 위에 있는 사람 걸음 1번
local function stepTick(): ...any
	for player, session in Sessions.all() do
		local data = session.data
		if session.onTreadmill and session.loaded and data and data.treadmillLevel >= 1 then
			local gain = Economy.treadmillGainPerSecond(data.treadmillLevel) * Config.TREADMILL_TICK_SECONDS
			if gain > 0 then
				Wallet.addSpeed(player, gain)
				Net.fire(player, Remotes.ToClient.TreadmillStep, { amount = gain })
			end
		end
	end
end

function TreadmillService.onCharacterAdded(player: Player, _character: Model)
	local session = Sessions.get(player)
	if session then
		session.onTreadmill = false
		session.treadmillArmed = true
		player:SetAttribute(Attr.OnTreadmill, false)
	end
end

function TreadmillService.start()
	Net.on(Remotes.ToServer.TreadmillLeave, function(player: Player)
		TreadmillService.leave(player, true)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.BASE_TICK_SECONDS)
			local ok, err = pcall(positionTick)
			if not ok then
				warn("[TreadmillService] 위치 오류: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.TREADMILL_TICK_SECONDS)
			local ok, err = pcall(stepTick)
			if not ok then
				warn("[TreadmillService] 걸음 오류: " .. tostring(err))
			end
		end
	end)
end

return TreadmillService
