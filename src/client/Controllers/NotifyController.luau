--!strict
--[[
	NotifyController — 알림
	- Notify      → 화면 아래쪽 작은 토스트 (성공 초록 / 실패 빨강 / 안내 파랑)
	- Announce    → 상단 가운데 큰 배너 ("ALL EGG RESET!", "OO 구역에 OO 알 등장!", 밤/낮)
	- EggDelivered → "배달 성공!" 토스트, IndexRewarded → 보상 토스트
	- OfflineIncome → 접속 때 "자리 비운 동안 $X 벌었어요!" 팝업
	  NotifyController.toast(text, kind) 는 다른 컨트롤러도 씀.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Pets = require(Shared.Data.Pets)
local Remotes = require(Shared.Remotes)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local Ui = require(Client.UI.Ui)

local NotifyController = {}

local C = Theme.Colors
local toastStack: Frame? = nil
local bannerHolder: Frame? = nil
local bannerQueue: { { text: string, color: Color3 } } = {}
local bannerBusy = false

local KIND_COLORS: { [string]: Color3 } = {
	success = C.green,
	error = C.red,
	info = C.blue,
	money = Color3.fromRGB(60, 190, 90),
}

function NotifyController.toast(text: string, kind: string?)
	local stack = toastStack
	if not stack then
		return
	end
	local color = KIND_COLORS[kind or "info"] or C.blue
	local t: TextLabel = Ui.new("TextLabel", {
		Name = "Toast",
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		TextColor3 = C.white,
		TextSize = 24,
		Text = text,
		LayoutOrder = -math.floor(os.clock() * 100),
		Parent = stack,
	})
	Ui.padding(18, 4).Parent = t
	Ui.corner(1).Parent = t
	Ui.stroke(C.white, 3).Parent = t
	Ui.textStroke(2).Parent = t
	Ui.pop(t, 1.3)
	local children = 0
	for _, child in stack:GetChildren() do
		if child:IsA("TextLabel") then
			children += 1
		end
	end
	if children > 4 then
		-- 너무 많으면 가장 오래된 것부터
		local oldest: TextLabel? = nil
		for _, child in stack:GetChildren() do
			if child:IsA("TextLabel") and (oldest == nil or child.LayoutOrder > oldest.LayoutOrder) then
				oldest = child
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(3.2, function()
		if t.Parent then
			local fade = Ui.tween(t, TweenInfo.new(0.35), { BackgroundTransparency = 1, TextTransparency = 1 })
			local stroke = t:FindFirstChildOfClass("UIStroke")
			if stroke then
				Ui.tween(stroke, TweenInfo.new(0.35), { Transparency = 1 })
			end
			fade.Completed:Wait()
			t:Destroy()
		end
	end)
end

local function showNextBanner()
	local holder = bannerHolder
	if bannerBusy or not holder or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local item = table.remove(bannerQueue, 1) :: { text: string, color: Color3 }
	local banner: TextLabel = Ui.new("TextLabel", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 70),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = item.color,
		TextColor3 = C.white,
		TextSize = 38,
		Text = item.text,
		Parent = holder,
	})
	Ui.padding(30, 6).Parent = banner
	Ui.corner(22).Parent = banner
	Ui.stroke(C.white, 4).Parent = banner
	Ui.textStroke(3).Parent = banner
	Ui.gradient(Theme.lighter(item.color, 0.3), item.color).Parent = banner
	Ui.pop(banner, 0.3)
	task.delay(3, function()
		local fade = Ui.tween(banner, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 })
		for _, d in banner:GetChildren() do
			if d:IsA("UIStroke") then
				Ui.tween(d, TweenInfo.new(0.4), { Transparency = 1 })
			end
		end
		fade.Completed:Wait()
		banner:Destroy()
		bannerBusy = false
		showNextBanner()
	end)
end

function NotifyController.banner(text: string, color: Color3?)
	table.insert(bannerQueue, { text = text, color = color or C.orange })
	showNextBanner()
end

local function offlinePopup(amount: number, perDay: number)
	local layer = Ui.layer("Popups")
	local holder: Frame = Ui.new("Frame", {
		Name = "OfflinePopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 330),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Ui.scaled(holder, Vector2.new(520, 330))
	local card: Frame = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.panel,
		Parent = holder,
	})
	Ui.corner(28).Parent = card
	Ui.stroke(C.money, 6).Parent = card
	Ui.label(
		"돌아왔네요!",
		UDim2.new(1, 0, 0, 60),
		40,
		C.orange,
		{ Position = UDim2.fromOffset(0, 18), Parent = card }
	)
	Ui.label(
		"자리 비운 동안",
		UDim2.new(1, 0, 0, 36),
		26,
		C.ink,
		{ Position = UDim2.fromOffset(0, 84), Parent = card }
	)
	local money = Ui.label(Format.money(amount), UDim2.new(1, 0, 0, 70), 60, C.money, {
		Position = UDim2.fromOffset(0, 120),
		Parent = card,
	})
	Ui.label("벌었어요!  (하루에 " .. Format.money(perDay) .. ")", UDim2.new(1, 0, 0, 32), 22, C.ink, {
		Position = UDim2.fromOffset(0, 192),
		Parent = card,
	})
	Ui.button("받기!", C.green, UDim2.fromOffset(200, 64), function()
		holder:Destroy()
	end, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -20),
		textSize = 32,
		parent = card,
		sound = "Reward",
	})
	Ui.pop(card, 0.4)
	task.delay(0.4, function()
		Ui.pop(money, 1.4)
	end)
end

function NotifyController.start()
	local hud = Ui.layer("Toasts")
	local stack: Frame = Ui.new("Frame", {
		Name = "ToastStack",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(700, 260),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	Ui.scaled(stack)
	Ui.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom).Parent =
		stack
	toastStack = stack

	local banner: Frame = Ui.new("Frame", {
		Name = "BannerHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(900, 80),
		BackgroundTransparency = 1,
		Parent = Ui.layer("Alerts"),
	})
	Ui.scaled(banner)
	bannerHolder = banner

	local E = Remotes.ToClient
	Net.on(E.Notify, function(payload: any)
		if typeof(payload) == "table" then
			NotifyController.toast(tostring(payload.text), tostring(payload.kind))
		end
	end)
	Net.on(E.Announce, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local kind = payload.kind
		local color = if kind == "reset"
			then C.yellow
			elseif kind == "rareEgg" then Theme.rarityColor(tostring(payload.rarity))
			elseif kind == "night" then C.night
			else C.blue
		if kind == "rareEgg" and payload.rarity == "secret" then
			color = Color3.fromRGB(40, 40, 50)
		end
		NotifyController.banner(tostring(payload.text), color)
	end)
	Net.on(E.EggDelivered, function(record: any)
		local pet = if typeof(record) == "table" then Pets.get(record.petId) else nil
		NotifyController.toast(
			"배달 성공! "
				.. (if pet then pet.name .. " 알이 자라기 시작해요" else "알이 자라기 시작해요"),
			"success"
		)
	end)
	Net.on(E.IndexRewarded, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local text = string.format(
			"도감 보상! 속도 +%s, %s",
			Format.number(tonumber(payload.speed) or 0),
			Format.money(tonumber(payload.money) or 0)
		)
		NotifyController.toast(text, "money")
		if payload.completeBonus then
			NotifyController.banner("도감 전체 완성!! 엄청난 보너스!", C.purple)
		end
	end)
	Net.on(E.OfflineIncome, function(payload: any)
		if typeof(payload) == "table" then
			offlinePopup(tonumber(payload.amount) or 0, tonumber(payload.perDay) or 0)
		end
	end)

	-- 2단계 알림 (수석 Remote, docs/REMOTES.md). Remote 가 아직 없으면 조용히 건너뜀.
	local function onOptional(name: string?, fn: (any) -> ())
		if not name then
			return
		end
		task.spawn(function()
			local ok = pcall(function()
				Net.on(name, function(payload: any)
					if typeof(payload) == "table" then
						fn(payload)
					end
				end)
			end)
			if not ok then
				warn("[NotifyController] Remote 없음: " .. name)
			end
		end)
	end
	local function petName(id: any): string
		local pet = Pets.get(tostring(id))
		return if pet then pet.name else tostring(id)
	end
	local SOURCES: { [string]: string } = { altar = "제단", shrine = "비밀 통로", quest = "퀘스트" }
	local extra = E :: { [string]: string }
	onOptional(extra.EggGranted, function(p)
		local egg = p.record or p.egg or {}
		local from = SOURCES[tostring(p.source)] or "선물"
		if p.queued then
			NotifyController.toast(
				from .. " 선물 알! 부화 슬롯이 가득 차서 기다리는 중이에요",
				"info"
			)
		else
			NotifyController.toast(
				from .. " 선물 알: " .. petName(egg.petId) .. "! 부화 슬롯에 들어갔어요",
				"success"
			)
		end
	end)
	onOptional(extra.PetsSold, function(p)
		local n = if typeof(p.pets) == "table" then #p.pets else 0
		NotifyController.toast(
			string.format(
				"보관함이 가득 차서 펫 %d마리를 %s에 팔았어요",
				n,
				Format.money(tonumber(p.money) or 0)
			),
			"info"
		)
	end)
	onOptional(extra.SakuraResult, function(p)
		if p.kind == "unlocked" then
			NotifyController.banner("사쿠라 인큐베이터가 열렸어요!", Color3.fromRGB(255, 150, 200))
		else
			local spirit = p.mutation == "spirit_bloom"
			NotifyController.toast(if spirit then "스피릿 블룸! (3배)" else "블룸! (1.5배)", "success")
		end
	end)
	onOptional(extra.AltarUpdate, function(p)
		if p.status == "pending" then
			NotifyController.toast(
				"제단에 " .. petName(p.petId) .. " 바침! 반대쪽 제단에 짝이 오길 기다려요",
				"info"
			)
		elseif p.status == "paired" then
			NotifyController.banner(
				"제단 성공! " .. (if p.partner then tostring(p.partner) .. "와(과) " else "") .. "특별 알!",
				C.yellow
			)
		elseif p.status == "expired" then
			NotifyController.toast("제단 시간이 끝났어요. 펫이 돌아왔어요", "error")
		end
	end)
	onOptional(extra.ShrineResult, function(p)
		NotifyController.banner("비밀 합성 성공! " .. petName(p.resultPetId) .. " 알!", C.purple)
	end)
end

return NotifyController
