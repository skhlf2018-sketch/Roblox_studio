--!strict
--[[
	SoundController — 효과음·배경음 (shared/Data/Sounds.luau 의 이름으로)
	  SoundController.play("Pickup")
	  SoundController.setMusic("Bgm_forest")      -- 구역 배경음 (부드럽게 바뀜)
	  SoundController.setChase(true)              -- 씨앗 들고 있는 동안 긴장 음악이 배경음 대신
	  SoundController.setMusicEnabled(false) / setSfxEnabled(false)  -- 설정 창
	ID 가 "rbxassetid://0" 이면 조용히 건너뜀 (사장님이 나중에 ID 만 채우면 됨).
	서버 이벤트 연결은 여기 start() 에서 (줍기/RUN/잡힘/배달/코인/밤/희귀 씨앗 공지 …).
	6판: 성체 됨(PlantGrown → Grown · 전설 이상 GrownRare) · 열매 따기(FruitPicked → FruitPick) ·
	  열매 팔기(FruitsSold → FruitSell) · 먹이기(FeedResult → 돌연변이면 FeedMutate, 아니면 Feed).
	  물 주기(Water)는 PetFxController 가 PetPetted 연출과 함께 냄.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Sounds = require(Shared.Data.Sounds)
local Rarities = require(Shared.Data.Rarities)
local Pets = require(Shared.Data.Pets)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Net = require(script.Parent.Parent.Net)

local SoundController = {}

local EMPTY = "rbxassetid://0"
local sfxEnabled = true
local musicEnabled = true
local folder: Folder? = nil
local cache: { [string]: Sound } = {}
local musicName: string? = nil
local chasing = false
local playingMusic: Sound? = nil
local rng = Random.new()
local listeners: { () -> () } = {}

local function hasId(def: Sounds.SoundDef?): boolean
	return def ~= nil and def.id ~= "" and def.id ~= EMPTY
end

local function getFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local n = Instance.new("Folder")
	n.Name = "GameSounds"
	n.Parent = SoundService
	folder = n
	return n
end

local function getSound(name: string): Sound?
	local def = Sounds[name]
	if not def or not hasId(def) then
		return nil
	end
	local cached = cache[name]
	if cached and cached.Parent then
		return cached
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.id
	s.Volume = def.volume
	s.Looped = def.looped == true
	s.Parent = getFolder()
	cache[name] = s
	return s
end

function SoundController.play(name: string)
	if not sfxEnabled then
		return
	end
	local def = Sounds[name]
	if not def or not hasId(def) or def.music then
		return
	end
	local base = getSound(name)
	if not base then
		return
	end
	local variation = def.pitchVariation or 0
	if variation > 0 then
		-- 겹쳐 울릴 수 있게 복제본으로
		local s = base:Clone()
		s.PlaybackSpeed = 1 + rng:NextNumber(-variation, variation)
		s.Parent = getFolder()
		s.Ended:Connect(function()
			s:Destroy()
		end)
		s:Play()
		task.delay(10, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	else
		SoundService:PlayLocalSound(base)
	end
end

local function fadeTo(target: Sound?)
	local old = playingMusic
	if old == target then
		return
	end
	if old then
		local t = TweenService:Create(old, TweenInfo.new(0.8), { Volume = 0 })
		t:Play()
		t.Completed:Connect(function()
			if playingMusic ~= old then
				old:Stop()
			end
		end)
	end
	playingMusic = target
	if target then
		local def = Sounds[target.Name]
		target.Volume = 0
		if not target.Playing then
			target:Play()
		end
		TweenService:Create(target, TweenInfo.new(1), { Volume = if def then def.volume else 0.3 }):Play()
	end
end

local function refreshMusic()
	if not musicEnabled then
		fadeTo(nil)
		return
	end
	local name = if chasing then "Chase" else musicName
	local sound = if name then getSound(name) else nil
	if chasing and not sound then
		sound = if musicName then getSound(musicName) else nil
	end
	fadeTo(sound)
end

function SoundController.setMusic(name: string?)
	musicName = name
	refreshMusic()
end

function SoundController.setChase(on: boolean)
	if chasing == on then
		return
	end
	chasing = on
	refreshMusic()
end

function SoundController.setMusicEnabled(on: boolean)
	musicEnabled = on
	refreshMusic()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function SoundController.setSfxEnabled(on: boolean)
	sfxEnabled = on
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function SoundController.isMusicEnabled(): boolean
	return musicEnabled
end

function SoundController.isSfxEnabled(): boolean
	return sfxEnabled
end

function SoundController.onSettingsChanged(fn: () -> ())
	table.insert(listeners, fn)
end

function SoundController.start()
	local E = Remotes.ToClient
	local player = Players.LocalPlayer

	Net.on(E.RunAlert, function()
		SoundController.play("Pickup")
		task.delay(0.15, function()
			SoundController.play("RunAlert")
		end)
		SoundController.setChase(true)
	end)
	Net.on(E.Caught, function(payload: any)
		local cause = if typeof(payload) == "table" then payload.cause else nil
		SoundController.play(if cause == "trap" then "Trap" else "Caught")
	end)
	Net.on(E.EggDelivered, function()
		SoundController.play("Deliver")
	end)
	-- 6판: 씨앗이 성체가 됨 (전설 이상은 팡파레)
	Net.on(E.PlantGrown, function(payload: any)
		local plant = if typeof(payload) == "table" then payload.plant else nil
		local def = if typeof(plant) == "table" then Pets.get(tostring(plant.petId)) else nil
		local rare = def ~= nil and Rarities.order(def.rarity) >= 5
		SoundController.play(if rare then "GrownRare" else "Grown")
	end)
	-- 열매 따기: "모두 따기"면 식물마다 FruitPicked 가 와서 0.15초에 한 번만
	local lastPick = 0
	Net.on(E.FruitPicked, function()
		local now = os.clock()
		if now - lastPick > 0.15 then
			lastPick = now
			SoundController.play("FruitPick")
		end
	end)
	Net.on(E.FruitsSold, function()
		SoundController.play("FruitSell")
	end)
	Net.on(E.FeedResult, function(payload: any)
		local mutation = if typeof(payload) == "table" then payload.mutation else nil
		SoundController.play(if typeof(mutation) == "string" then "FeedMutate" else "Feed")
	end)
	Net.on(E.IndexRewarded, function()
		SoundController.play("Reward")
	end)
	-- 사쿠라 나무: 성체 바침 → SakuraOffer, 씨앗 뽑기 → 벚꽃(Bloom) / 정령 벚꽃(비밀 이상, SpiritBloom)
	Net.on(E.SakuraResult, function(payload: any)
		local kind = if typeof(payload) == "table" then payload.kind else nil
		if kind == "offered" then
			SoundController.play("SakuraOffer")
		elseif kind == "draw" then
			local def = Pets.get(tostring(payload.petId))
			local rare = def ~= nil and Rarities.order(def.rarity) >= Rarities.order("secret")
			SoundController.play(if rare then "SpiritBloom" else "Bloom")
		end
	end)
	Net.on(E.Notify, function(payload: any)
		local kind = if typeof(payload) == "table" then payload.kind else nil
		if kind == "error" then
			SoundController.play("Error")
		elseif kind == "success" then
			SoundController.play("Purchase")
		else
			SoundController.play("Notify")
		end
	end)
	Net.on(E.Announce, function(payload: any)
		local kind = if typeof(payload) == "table" then payload.kind else nil
		if kind == "rareEgg" then
			SoundController.play("RareEgg")
		elseif kind == "reset" then
			SoundController.play("Reset")
		elseif kind == "night" then
			SoundController.play("NightBell")
		elseif kind == "day" then
			SoundController.play("DayStart")
		end
	end)

	-- 씨앗을 내려놓으면(배달·놓침) 추격 음악 끝
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.CarryingEgg):Connect(function()
		local carrying = player:GetAttribute(Tags.PlayerAttributes.CarryingEgg)
		if carrying == nil or carrying == "" then
			SoundController.setChase(false)
		end
	end)

	-- 구역 배경음: 내가 있는 구역이 바뀌면 교체 (베이스·광장·길 = Bgm_base)
	local ZoneController = require(script.Parent.ZoneController)
	local Visuals = require(Shared.Data.Visuals)
	ZoneController.changed(function(zone: string?)
		local theme = if zone and zone ~= "base" then Visuals.biomes[zone] else nil
		SoundController.setMusic(if theme then theme.music else "Bgm_base")
	end)
	SoundController.setMusic("Bgm_base")

	-- 코인 짤랑 (코인이 들어올 때, 최대 2초에 한 번)
	local lastMoney = player:GetAttribute(Tags.PlayerAttributes.Money)
	local lastCoin = 0
	player:GetAttributeChangedSignal(Tags.PlayerAttributes.Money):Connect(function()
		local money = player:GetAttribute(Tags.PlayerAttributes.Money)
		if typeof(money) == "number" and typeof(lastMoney) == "number" and money > lastMoney then
			local now = os.clock()
			if now - lastCoin > 2 then
				lastCoin = now
				SoundController.play("Coin")
			end
		end
		lastMoney = money
	end)
end

return SoundController
