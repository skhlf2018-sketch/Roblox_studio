--!strict
--[[
	NotifyController — 알림
	- Notify      → 화면 아래 가운데 굵은 외곽선 글씨 토스트 (원작 "에그를 훔쳤어요!")
	- Announce    → 상단 가운데 굵은 외곽선 글씨 한 줄 ("ALL EGG RESET!", "OO 구역에 OO 알 등장!", 밤/낮)
	- EggDelivered → "에그를 훔쳤어요! 가방에 들어갔어요" 토스트 (2판 수정: 알 가방), IndexRewarded → 보상 토스트
	- 희귀 알 공지는 원작처럼 색 조각 글씨: "Jungle에 비밀 킹 스네이크 에그 등장!" (NotifyController.rareEggText)
	- OfflineIncome → 접속 때 "자리 비운 동안 $X 벌었어요!" 팝업
	- EggGranted ("○○ 선물 알: 펫! 가방에 들어갔어요") / PetsSold 토스트 (사쿠라·제단·비밀 통로 결과 연출은 SakuraController / AltarController)
	  NotifyController.toast(text, kind) 는 다른 컨트롤러도 씀.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Pets = require(Shared.Data.Pets)
local Biomes = require(Shared.Data.Biomes)
local Rarities = require(Shared.Data.Rarities)
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
	success = Color3.new(1, 1, 1),
	error = Color3.fromRGB(255, 90, 90),
	info = Color3.fromRGB(220, 235, 255),
	money = Color3.fromRGB(110, 255, 90),
}

-- 원작 토스트: 바탕 없이 굵은 외곽선 흰 글씨 ("에그를 훔쳤어요!")
function NotifyController.toast(text: string, kind: string?)
	local stack = toastStack
	if not stack then
		return
	end
	local color = KIND_COLORS[kind or "info"] or C.white
	local t: TextLabel = Ui.new("TextLabel", {
		Name = "Toast",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		TextColor3 = color,
		TextSize = 30,
		Text = text,
		LayoutOrder = -math.floor(os.clock() * 100),
		Parent = stack,
	})
	Ui.padding(10, 2).Parent = t
	Ui.textStroke(3, C.winEdge).Parent = t
	Ui.pop(t, 1.25)
	local children = 0
	for _, child in stack:GetChildren() do
		if child:IsA("TextLabel") then
			children += 1
		end
	end
	if children > 3 then
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
	task.delay(3, function()
		if t.Parent then
			local fade = Ui.tween(t, TweenInfo.new(0.35), { TextTransparency = 1 })
			local stroke = t:FindFirstChildOfClass("UIStroke")
			if stroke then
				Ui.tween(stroke, TweenInfo.new(0.35), { Transparency = 1 })
			end
			fade.Completed:Wait()
			t:Destroy()
		end
	end)
end

-- 원작 공지: 화면 위 가운데 굵은 외곽선 글씨 한 줄 (RichText 색 조각: 구역 초록, 알 이름 금색)
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
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		TextColor3 = item.color,
		TextSize = 34,
		RichText = true,
		Text = item.text,
		Parent = holder,
	})
	Ui.padding(12, 2).Parent = banner
	Ui.textStroke(3.5, C.winEdge).Parent = banner
	Ui.pop(banner, 0.4)
	task.delay(3.4, function()
		local fade = Ui.tween(banner, TweenInfo.new(0.4), { TextTransparency = 1 })
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
	table.insert(bannerQueue, { text = text, color = color or C.white })
	showNextBanner()
end

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- "Jungle 에 시크릿 킹 스네이크 에그 등장!" (구역 초록, 희귀도 색 + 알 이름 금색)
function NotifyController.rareEggText(payload: any): string?
	local biome = Biomes.get(tostring(payload.biomeId))
	local pet = Pets.get(tostring(payload.petId))
	if not biome or not pet then
		return nil
	end
	local rarity = Rarities.get(tostring(payload.rarity or pet.rarity))
	local rarityName = if rarity then rarity.name else ""
	return string.format(
		'<font color="%s">%s</font>에 <font color="%s">%s</font> <font color="#FFD23C">%s</font> 에그 등장!',
		hex(Color3.fromRGB(90, 235, 90)),
		escape(biome.nameEn),
		hex(Theme.rarityColor(tostring(payload.rarity or pet.rarity))),
		escape(rarityName),
		escape(pet.name)
	)
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
		Position = UDim2.new(0.5, 0, 1, -184),
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
			elseif kind == "night" then Color3.fromRGB(255, 120, 140)
			elseif kind == "day" then Color3.fromRGB(255, 230, 120)
			else C.white
		local text = if kind == "rareEgg" then NotifyController.rareEggText(payload) else nil
		NotifyController.banner(text or escape(tostring(payload.text)), color)
	end)
	Net.on(E.EggDelivered, function()
		NotifyController.toast("에그를 훔쳤어요! 가방에 들어갔어요", "success")
	end)
	Net.on(E.IndexRewarded, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local text = string.format(
			"인덱스 보상! 속도 +%s, %s",
			Format.number(tonumber(payload.speed) or 0),
			Format.money(tonumber(payload.money) or 0)
		)
		NotifyController.toast(text, "money")
		if payload.completeBonus then
			NotifyController.banner("인덱스 전체 완성!! 엄청난 보너스!", C.purple)
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
	-- 선물 알 출처 (5판: 퀘스트·무료 보상 선물은 없어짐 — 제단·비밀 통로·개발 명령 /egg 만)
	local SOURCES: { [string]: string } = { altar = "제단", shrine = "비밀 통로", dev = "개발 명령" }
	local extra = E :: { [string]: string }
	onOptional(extra.EggGranted, function(p)
		-- 2판 수정: 선물 알도 알 가방으로 (대기 줄 없음, payload.queued 는 안 봄)
		local egg = p.egg or p.record or {}
		local from = SOURCES[tostring(p.source)] or "선물"
		NotifyController.toast(
			from .. " 선물 알: " .. petName(egg.petId) .. "! 가방에 들어갔어요",
			"success"
		)
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
	-- SakuraResult / AltarUpdate / ShrineResult 연출은 SakuraController / AltarController 가 함 (2차)
end

return NotifyController
