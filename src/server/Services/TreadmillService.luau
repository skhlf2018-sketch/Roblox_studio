--!strict
--[[
	TreadmillService — 러닝머신 2판 (설계 2판 D: 원작처럼 올라서면 고정돼 제자리에서 달림)

	- 내 베이스 러닝머신 벨트(MapLayout.treadmillRect(plotIndex), 앞마당) 위에 올라서면 서버가 태움:
	    플레이어 Attr OnTreadmill = true, WalkSpeed 0 (WASD 무시), 캐릭터를 벨트 가운데로 옮겨 복도 쪽을 보게 함.
	    (HumanoidRootPart Anchored·PlatformStand 안 씀 → 점프는 됨)
	- 1초(TREADMILL_TICK_SECONDS)마다 걸음 1번: 속도 += 걸음당 속도(Upgrades 러닝머신 레벨) × TREADMILL_MULTIPLIER(6판 4)
	    × 장착 트레일 배율 × 9판 로벅스 러닝머신 부스트(data.treadmillBoost, 산 것 중 가장 큰 배수 — Attr TreadmillBoost)
	    → Wallet.addSpeed + TreadmillStep { amount } (클라 "+500" 분홍 팝업)
	    (TreadmillTouched 의 gainPerSecond·nextGainPerSecond 는 트레일·부스트 전 숫자 그대로)
	- 내리기: 클라가 점프할 때 TreadmillLeave() → 벨트 옆(마당 가운데 쪽)으로 내려 줌 (2026-11-10: 앞은 표지판 자리라 낌).
	    클라가 안 보내도 점프하면 몸통이 TREADMILL_MAX_HEIGHT(8) 위로 떠서 서버가 내려 줌 (그 자리 착지 → 걸어서 나가면 됨).
	    서버도 0.2초마다 확인해서 벨트 위를 벗어났거나(높이 TREADMILL_MAX_HEIGHT 위로 떴거나) 알을 들었거나
	    기절·죽음이면 자동으로 내림. 내린 뒤에는 벨트 밖으로 한 번 나가야 다시 탈 수 있음 (점프 착지로 바로 다시 타지 않게).
	- 벨트 위에서 밀려나면(물리) 가운데로 되돌림 (TREADMILL_PIN_TOLERANCE). 서버 순간이동이라 위치 검증(AntiCheat)은 잠깐 쉼.
	- 러닝머신 0레벨(잠김)이면 안 탐 (8판: "먼저 사세요" 회색 안내는 없앰).
	- 8판 (사장님 2026-11-08, 원작처럼 "올라서면 다음 레벨로 올리기"): 벨트에 **올라서는 순간**(0레벨이어도) 서버가
	    TreadmillTouched { level, nextLevel, nextCost, maxed, gainPerSecond, nextGainPerSecond } 를 그 사람에게 1번 보냄
	    → 클라(선임)가 "레벨 n → n+1 올리기 (가격)" 창을 열고, 버튼은 기존 PurchaseUpgrade("Treadmill").
	    벨트 위에 서 있는 동안 플레이어 Attr TreadmillTouching = true (내려오면 false → 창 닫기). 다시 올라서면 또 보냄.
	    0레벨에서 해금하면 내려왔다 올라올 필요 없이 다음 틱에 바로 탐.
	- 다른 사람 베이스 러닝머신은 못 씀 (허브 = 안전 구역이라 방해도 못 함).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local MapLayout = require(Shared.Data.MapLayout)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
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

-- 내리기. stepOff = true 면 벨트 옆(마당 가운데 쪽)으로 내려 줌 (점프로 내릴 때) — 앞은 표지판 자리
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
			-- 사장님 2026-11-10: 벨트 앞(복도 쪽)에는 업그레이드 표지판이 있어서 내리면 표지판에 낌 →
			--   **옆(마당 가운데 쪽, +z)** 으로 내림. 왼쪽 베이스에서는 달리는 방향의 오른쪽. 표지판·건너뛰기 표지판은 앞과 -z 쪽
			local offset = MapLayout.TREADMILL_PAD.sizeZ / 2 + 3
			placeAt(player, session, plot.treadmill.x, plot.treadmill.z + offset, plot.facing)
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

-- 8판: 이 레벨의 러닝머신 업그레이드 창 정보 (TreadmillTouched payload)
function TreadmillService.touchInfo(level: number): Types.TreadmillTouch
	local nextCost = Economy.nextTreadmillCost(level)
	return {
		level = level,
		nextLevel = if nextCost then level + 1 else nil,
		nextCost = nextCost,
		maxed = nextCost == nil,
		gainPerSecond = if level >= 1 then Economy.treadmillGainPerSecond(level) else 0,
		nextGainPerSecond = if nextCost then Economy.treadmillGainPerSecond(level + 1) else nil,
	}
end

-- 8판: 벨트 위에 서 있는지 (Attr TreadmillTouching). 올라서는 순간 TreadmillTouched 1번
local function setTouching(player: Player, session: Sessions.Session, touching: boolean, level: number)
	if session.treadmillTouching == touching then
		return
	end
	session.treadmillTouching = touching
	player:SetAttribute(Attr.TreadmillTouching, touching)
	if touching then
		Net.fire(player, Remotes.ToClient.TreadmillTouched, TreadmillService.touchInfo(level))
	end
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
			-- 8판: 벨트 위(수평만 — 벨트 위에서 점프해도 창이 깜빡이지 않게)면 업그레이드 창 신호 (0레벨도)
			local touching = MapLayout.isOnTreadmill(root.Position, session.plotIndex, Config.TREADMILL_PAD_MARGIN)
				and session.carryingUid == nil
				and Character.isAlive(player)
			setTouching(player, session, touching, data.treadmillLevel)
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
			end
			-- (8판: 0레벨이면 안 타고 TreadmillTouched 창만 — 7판 "러닝머신이 잠겨 있어요! 먼저 사세요" 안내 없앰)
		else
			if session.onTreadmill then
				TreadmillService.leave(player, false)
			end
			setTouching(player, session, false, 0)
		end
	end
end

-- 1초마다: 러닝머신 위에 있는 사람 걸음 1번
local function stepTick(): ...any
	for player, session in Sessions.all() do
		local data = session.data
		if session.onTreadmill and session.loaded and data and data.treadmillLevel >= 1 then
			-- 사장님 2026-10-28: 러닝머신 이득도 장착한 트레일 배율만큼 · 9판: × 로벅스 러닝머신 부스트 (data.treadmillBoost)
			local gain = Economy.treadmillGainPerSecond(
				data.treadmillLevel,
				Economy.trailMultiplier(data.equippedTrail),
				data.treadmillBoost
			) * Config.TREADMILL_TICK_SECONDS
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
		session.treadmillTouching = false
		player:SetAttribute(Attr.OnTreadmill, false)
		player:SetAttribute(Attr.TreadmillTouching, false)
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
