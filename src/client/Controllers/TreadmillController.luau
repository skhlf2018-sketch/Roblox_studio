--!strict
--[[
	TreadmillController — 러닝머신 (2판: 원작처럼 올라서면 제자리 달리기)

	- 플레이어 Attribute OnTreadmill = true 인 동안: 이동 입력(WASD·조이스틱)을 끔 (PlayerModule Controls:Disable)
	  아래 가운데 "점프하면 내려와요" 안내 + 터치 기기는 "내리기" 버튼
	- 점프 입력(스페이스·게임패드 A·JumpRequest·내리기 버튼) → TreadmillLeave (서버가 내려 줌)
	- TreadmillStep({ amount }) 마다 위 가운데 분홍 속도 배지 "👟 +500" (8판: SpeedFxController.popGain 으로 통일)
	판정·속도 증가는 전부 서버. 이 컨트롤러는 입력과 연출만.

	8판 러닝머신 터치 창 (원작처럼, 사장님 2026-11-08):
	  내 베이스 러닝머신 벨트에 올라서거나 닿으면 "TreadmillDialog" 창 (Ui.dialog):
	    레벨 n → n+1 · 1초에 속도 +A → +B (Economy.treadmillGainPerSecond) · 가격 (Economy.nextTreadmillCost)
	    "올리기 · N 코인" → PurchaseUpgrade("Treadmill") (코인이 모자라면 회색), 0레벨(잠김)이면 "러닝머신 사기 · N 코인"
	    최대 레벨이면 "최대 레벨!" 회색. 레벨·코인이 바뀌면 창 글·버튼이 바로 바뀜 (창은 열린 채)
	    9판: 가운데 "⏩ 건너뛰기 · R$ N" (TreadmillSkip, Products.nextTreadmillSkip → Purchase.prompt, 최대면 숨김)
	  한 번 열면(또는 닫으면) 벨트에서 내려올 때까지 다시 안 뜸. 벨트에서 내려오면 창이 저절로 닫힘.
	  벨트 판정은 TreadmillController.setTouching(on) 한 곳으로 모음:
	    · 서버(수석 8판): 올라선 순간 Remote TreadmillTouched → setTouching(true), 서 있는 동안 Attr TreadmillTouching
	    · checkBelt(0.25초마다 + Attr 바뀔 때): Attr TreadmillTouching 이 있으면 그것, 없으면(옛 서버) 클라 판정
	      (OnTreadmill 이거나 MapLayout.treadmillRect 위, 또는 내 베이스 Treadmill 태그 파트에 닿음)
	  옛 서버의 "러닝머신이 잠겨 있어요!…" 토스트는 이 창이 대신하므로 NotifyController.mute 로 숨김.
	공개: popStep(amount) · checkBelt() · onBelt() · setTouching(on) · openDialog() · dialogBody() · costInfo()
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Data.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local MapLayout = require(Shared.Data.MapLayout)
local Products = require(Shared.Data.Products)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Purchase = require(Client.Purchase)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)
local WorldPrompt = require(Client.UI.WorldPrompt)
local NotifyController = require(script.Parent.NotifyController)
local ShopController = require(script.Parent.ShopController)
local SoundController = require(script.Parent.SoundController)
local SpeedFxController = require(script.Parent.SpeedFxController)

local TreadmillController = {}

local C = Theme.Colors
local Attr = Tags.PlayerAttributes
local DIALOG = "TreadmillDialog"
local TREAD_BLUE = Color3.fromRGB(40, 120, 230) -- 상점 러닝머신 카드와 같은 색
local ROBUX_GREEN = Color3.fromRGB(0, 176, 111) -- 9판: 로벅스 버튼
local TOUCH_DISTANCE = 2.5 -- 벨트 파트 상자에서 몸통까지 이만큼(+ TREADMILL_PAD_MARGIN)이면 "닿음" (몸통은 벨트 윗면 위 약 3)

local controls: any = nil
local function getControls(): any
	if controls then
		return controls
	end
	local ok, result = pcall(function(): any
		local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
		local module = if scripts then scripts:FindFirstChild("PlayerModule") else nil
		if module and module:IsA("ModuleScript") then
			return (require :: any)(module):GetControls()
		end
		return nil
	end)
	if ok then
		controls = result
	end
	return controls
end

local function onTreadmill(): boolean
	return Players.LocalPlayer:GetAttribute(Attr.OnTreadmill) == true
end

local leaving = false
local function leave()
	if not onTreadmill() or leaving then
		return
	end
	leaving = true
	Net.trySend(Remotes.ToServer.TreadmillLeave)
	task.delay(0.4, function()
		leaving = false
	end)
end

-- 러닝머신 걸음 "+500" → 위 가운데 분홍 속도 배지 (8판: 캐릭터 옆 떠오르는 글씨 대신)
function TreadmillController.popStep(amount: number)
	SpeedFxController.popGain(amount)
end

------------------------------------------------------------------
-- 8판: 러닝머신 터치 창
------------------------------------------------------------------

local function myRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function myPlot(): number
	local p = Players.LocalPlayer:GetAttribute(Attr.PlotIndex)
	return if typeof(p) == "number" then p else 0
end

local function myMoney(): number
	local m = Players.LocalPlayer:GetAttribute(Attr.Money)
	return if typeof(m) == "number" then m else 0
end

-- 8판: 서버 TreadmillTouched payload (Types.TreadmillTouch) 를 받은 시각·레벨 — Attr 이 아직 안 왔을 때 잠깐 씀
local lastTouchAt = -math.huge
local lastTouchLevel: number? = nil

local function treadLevel(): number
	local level = 0
	local a = Players.LocalPlayer:GetAttribute(Attr.TreadmillLevel)
	if typeof(a) == "number" then
		level = math.max(0, math.floor(a))
	else
		local snap = State.get()
		local saved = if snap then tonumber(snap.treadmillLevel) else nil
		level = if saved then math.max(0, math.floor(saved)) else 0
	end
	-- 신호 레벨이 더 높으면(Attr 복제가 늦음) 신호를 믿음 — 산 뒤에는 Attr 이 올라가서 그쪽이 큼
	local touched = lastTouchLevel
	if touched and os.clock() - lastTouchAt < 1 and touched > level then
		level = touched
	end
	return level
end

-- 내 베이스 러닝머신 벨트 파트들 (태그 Treadmill + Attr PlotIndex)
local function myBelts(plot: number): { BasePart }
	local list: { BasePart } = {}
	for _, inst in CollectionService:GetTagged(Tags.Treadmill) do
		local part: BasePart? = nil
		if inst:IsA("BasePart") then
			part = inst
		elseif inst:IsA("Model") then
			part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		end
		local owner = inst:GetAttribute("PlotIndex")
		if part and owner == plot then
			table.insert(list, part)
		end
	end
	return list
end

-- 내 몸통이 벨트에서 얼마나 떨어졌나 (MapLayout 사각형 · 태그 파트 중 가까운 것, 모르면 math.huge)
local function beltDistance(root: BasePart, plot: number): number
	local best = math.huge
	local rect = MapLayout.treadmillRect(plot)
	if rect then
		local p = root.Position
		local dx = math.max(rect.xMin - p.X, 0, p.X - rect.xMax)
		local dz = math.max(rect.zMin - p.Z, 0, p.Z - rect.zMax)
		if p.Y - MapLayout.FLOOR_Y < Config.TREADMILL_MAX_HEIGHT then
			best = math.sqrt(dx * dx + dz * dz)
		end
	end
	for _, part in myBelts(plot) do
		local d = math.max(0, WorldPrompt.distanceTo(part, root.Position) - TOUCH_DISTANCE)
		if d < best then
			best = d
		end
	end
	return best
end

-- 지금 내 벨트 위(또는 닿음)인가
function TreadmillController.onBelt(): boolean
	if onTreadmill() then
		return true
	end
	local root = myRoot()
	local plot = myPlot()
	if not root or plot <= 0 then
		return false
	end
	return beltDistance(root, plot) <= Config.TREADMILL_PAD_MARGIN
end

-- 가격·속도 정보: level, cost(nil = 최대), 지금 1초 속도, 다음 1초 속도, 다음 모양 이름
function TreadmillController.costInfo(): (number, number?, number, number, string)
	local level = treadLevel()
	local cost = Economy.nextTreadmillCost(level)
	local now = Economy.treadmillGainPerSecond(level)
	local nextGain = if cost then Economy.treadmillGainPerSecond(level + 1) else now
	local names = ShopController.TREADMILL_NAMES
	local name = names[math.clamp(if cost then level + 1 else level, 1, #names)] or ""
	return level, cost, now, nextGain, name
end

function TreadmillController.dialogBody(): string
	local level, cost, now, nextGain, name = TreadmillController.costInfo()
	local coins = "내 코인 " .. Format.money(myMoney())
	if level <= 0 then
		return string.format(
			"아직 러닝머신이 없어요!\n사면 올라서 있는 동안 1초에 속도 +%s\n%s",
			Format.number(nextGain),
			coins
		)
	end
	if not cost then
		return string.format(
			"최고 러닝머신! (레벨 %d)\n1초에 속도 +%s\n%s",
			level,
			Format.number(now),
			coins
		)
	end
	return string.format(
		"레벨 %d → 레벨 %d (%s 러닝머신)\n1초에 속도 +%s → +%s\n%s",
		level,
		level + 1,
		name,
		Format.number(now),
		Format.number(nextGain),
		coins
	)
end

local dialog: Ui.Dialog? = nil

local function refreshDialog()
	local d = dialog
	if not d or not d.alive() then
		return
	end
	d.setBody(TreadmillController.dialogBody())
	local button = d.buttons.TreadmillUpgrade
	if button then
		local level, cost = TreadmillController.costInfo()
		if not cost then
			Ui.setButton(button, "최대 레벨!", C.gray, false)
		else
			local afford = myMoney() >= cost
			local verb = if level <= 0 then "러닝머신 사기" else "올리기"
			Ui.setButton(button, verb .. " · " .. Format.money(cost), if afford then C.shopGreen else C.gray, afford)
		end
	end
	-- 9판: "⏩ R$ N" 로벅스로 다음 레벨 (최대 레벨이면 숨김)
	local skip = d.buttons.TreadmillSkip
	if skip then
		local product = Products.nextTreadmillSkip(treadLevel())
		skip.Visible = product ~= nil
		if product then
			Ui.setButton(skip, "⏩ 건너뛰기 · " .. Purchase.robux(product.robux), ROBUX_GREEN, true)
		end
	end
end

function TreadmillController.isDialogOpen(): boolean
	local d = dialog
	return d ~= nil and d.alive()
end

-- 창 열기 (이미 열려 있으면 글만 다시)
function TreadmillController.openDialog()
	if TreadmillController.isDialogOpen() then
		refreshDialog()
		return
	end
	local d = Ui.dialog(DIALOG, "👟 러닝머신 업그레이드", TreadmillController.dialogBody(), {
		{ name = "DialogCancel", text = "닫기", color = C.gray, sound = "Close" },
		{
			-- 9판: 로벅스로 다음 레벨 (Purchase.prompt — 상품이 아직 없으면 "준비 중" 토스트)
			name = "TreadmillSkip",
			text = "⏩ 건너뛰기",
			color = ROBUX_GREEN,
			keepOpen = true,
			onClick = function()
				local product = Products.nextTreadmillSkip(treadLevel())
				if product then
					Purchase.prompt(product.key)
				end
			end,
		},
		{
			name = "TreadmillUpgrade",
			text = "올리기",
			color = C.shopGreen,
			keepOpen = true, -- 사고 나서도 창은 그대로 (다음 레벨 가격이 바로 보이게)
			sound = "Purchase",
			onClick = function()
				local _, cost = TreadmillController.costInfo()
				if cost and myMoney() >= cost then
					Net.send(Remotes.ToServer.PurchaseUpgrade, Remotes.UpgradeKinds.Treadmill)
				end
			end,
		},
	}, TREAD_BLUE)
	dialog = d
	refreshDialog()
end

-- 벨트 판정 한 곳: 올라서면(닿기 시작) 창 한 번, 내려오면 창을 닫고 다음 번을 위해 다시 준비
local touching = false
function TreadmillController.setTouching(on: boolean)
	if on == touching then
		return
	end
	touching = on
	if on then
		TreadmillController.openDialog()
	else
		local d = dialog
		if d and d.alive() then
			d.close() -- 벨트에서 내려옴
		end
	end
end

function TreadmillController.isTouching(): boolean
	return touching
end

-- 판정 한 번 (0.25초마다 + 서버 Attr 이 바뀔 때): 서버 Attr TreadmillTouching 이 있으면 그것, 없으면(옛 서버) 클라 판정
function TreadmillController.checkBelt()
	local attr = Players.LocalPlayer:GetAttribute(Attr.TreadmillTouching)
	if typeof(attr) == "boolean" then
		TreadmillController.setTouching(attr or onTreadmill())
	else
		TreadmillController.setTouching(TreadmillController.onBelt())
	end
end

function TreadmillController.start()
	local player = Players.LocalPlayer

	local hint: Frame = Ui.new("Frame", {
		Name = "TreadmillHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.fromOffset(420, 64),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.layer("Hud"),
	})
	Ui.scaled(hint)
	Ui.label("러닝머신 달리는 중! 점프하면 내려와요", UDim2.new(1, 0, 0, 30), 24, C.white, {
		Name = "Text",
		Parent = hint,
	})
	local leaveButton = Ui.button("내리기", C.pawOrange, UDim2.fromOffset(150, Ui.touch(48)), leave, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 32),
		textSize = 24,
		parent = hint,
	})
	leaveButton.Name = "LeaveButton"

	local function refresh()
		local on = onTreadmill()
		hint.Visible = on
		leaveButton.Visible = Ui.isTouch()
		local c = getControls()
		if c then
			pcall(function()
				if on then
					c:Disable()
				else
					c:Enable()
				end
			end)
		end
		if on then
			Ui.pop(hint, 1.15)
		end
	end
	player:GetAttributeChangedSignal(Attr.OnTreadmill):Connect(refresh)
	player.CharacterAdded:Connect(function()
		task.defer(refresh)
	end)
	refresh()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			leave()
		end
	end)
	pcall(function()
		UserInputService.JumpRequest:Connect(leave)
	end)

	Net.onLater(Remotes.ToClient.TreadmillStep, function(payload: any)
		local amount = if typeof(payload) == "table" then tonumber(payload.amount) else tonumber(payload)
		if amount and amount > 0 then
			TreadmillController.popStep(amount)
			SoundController.play("TreadmillStep")
		end
	end)

	-- 8판 러닝머신 터치 창
	NotifyController.mute("러닝머신이 잠겨 있어요") -- 서버 잠김 안내 → 이 창이 대신
	player:GetAttributeChangedSignal(Attr.TreadmillLevel):Connect(refreshDialog)
	player:GetAttributeChangedSignal(Attr.Money):Connect(refreshDialog)
	Purchase.onGranted(refreshDialog) -- 9판: 로벅스로 레벨을 올리면 창 글·가격 다시
	State.onChanged(function(section: string)
		if section == "upgrades" or section == "snapshot" then
			refreshDialog()
		end
	end)
	-- 8판 서버 신호 (수석): 올라선 순간 Remote TreadmillTouched + 서 있는 동안 Attr TreadmillTouching
	--   → 둘 다 같은 함수(setTouching)로. 옛 서버(신호 없음)면 0.25초 클라 판정만
	local touchedRemote = (Remotes.ToClient :: any).TreadmillTouched
	if typeof(touchedRemote) == "string" then
		Net.onLater(touchedRemote, function(payload: any)
			-- payload = Types.TreadmillTouch { level, nextLevel, nextCost, maxed, gainPerSecond, nextGainPerSecond }
			--   창 숫자는 Economy 로 다시 계산 (TreadmillService.touchInfo 와 같은 식) — level 만 Attr 이 늦을 때 씀
			local level = if typeof(payload) == "table" then tonumber(payload.level) else nil
			if level then
				lastTouchLevel = math.max(0, math.floor(level))
				lastTouchAt = os.clock()
			end
			TreadmillController.setTouching(true)
			refreshDialog()
		end)
	end
	player:GetAttributeChangedSignal(Attr.TreadmillTouching):Connect(TreadmillController.checkBelt)
	task.spawn(function()
		while true do
			task.wait(0.25)
			TreadmillController.checkBelt()
		end
	end)
end

return TreadmillController
