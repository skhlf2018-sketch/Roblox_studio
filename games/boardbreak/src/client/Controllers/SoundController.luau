--!strict
--[[
	SoundController — 효과음·배경음 (shared/Data/Sounds.luau 의 이름으로). 첫 게임 SoundController 를 줄여 복사.
	  SoundController.play("Hit")
	  SoundController.setMusic("Bgm_world1")      -- 월드 배경음 (부드럽게 바뀜)
	  SoundController.setTense(true)              -- 심사·대결 중 긴장 음악
	  SoundController.setMusicEnabled(false) / setSfxEnabled(false)  -- 설정 창
	ID 가 "rbxassetid://0" 이면 조용히 건너뜀.
	깨짐: SoundController.playBreak(targetId) — 클수록 콰쾅쾅쾅 (client/BreakFx, 사장님 결정 18번). 층마다 playLayer (못 불러온 층만 빠짐).
	서버 이벤트: Notify(error/success) · HitResult(치기·약함·깨짐) · TrainResult(들기, 0.2초에 한 번) · ExamState · DuelState
	  · 돈이 들어오면 짤랑 (2초에 한 번) · CurrentWorld 가 바뀌면 월드 음악.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Sounds = require(Shared.Data.Sounds)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Net = require(script.Parent.Parent.Net)
local BreakFx = require(script.Parent.Parent.BreakFx)

local SoundController = {}

local EMPTY = "rbxassetid://0"
local sfxEnabled = true
local musicEnabled = true
local folder: Folder? = nil
local cache: { [string]: Sound } = {}
local musicName: string? = nil
local tense = false
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
	s.PlaybackSpeed = def.speed or 1
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

-- 한 층: name 소리를 volume · speed 로, delay 초 뒤에 (효과음 설정이 꺼져 있으면 안 냄 — 기다리는 동안 꺼져도).
--   그 소리가 아직 안 불러와졌거나 못 불러오면 그 층만 빠짐 (나머지 층은 그대로). 보냈으면 true
function SoundController.playLayer(name: string, volume: number, speed: number, delay: number): boolean
	if not sfxEnabled then
		return false
	end
	local def = Sounds[name]
	if not def or not hasId(def) or def.music then
		return false
	end
	local base = getSound(name)
	if not base then
		return false
	end
	local okLoad, loaded = pcall(function(): boolean
		return base.IsLoaded
	end)
	if okLoad and loaded == false then
		return false -- 아직 못 불러옴 (다음 깨짐부터 남)
	end
	local variation = def.pitchVariation or 0
	local function go()
		if not sfxEnabled then
			return
		end
		local s = base:Clone()
		s.Volume = volume
		-- 그 소리의 높낮이 흔들기(pitchVariation, Break 는 ±0.1)도 오늘처럼 — 같은 물건을 여러 번 깨도 똑같지 않게
		local v = variation
		s.PlaybackSpeed = speed * (if v > 0 then 1 + rng:NextNumber(-v, v) else 1)
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
	end
	if delay > 0 then
		task.delay(delay, go)
	else
		go()
	end
	return true
end

-- 깨짐 소리 (사장님 결정 18번 — 클수록 콰쾅쾅쾅, client/BreakFx.plan). 물건이 아니면 (심사·대결 송판) 오늘의 Break 하나.
--   반환: 보낸 층 수 · 그 층들 볼륨 합 (테스트용)
function SoundController.playBreak(targetId: string?): (number, number)
	if not sfxEnabled then
		return 0, 0
	end
	if type(targetId) ~= "string" or BreakFx.progress(targetId) == nil then
		SoundController.play("Break")
		return 1, Sounds.Break.volume
	end
	local plan = BreakFx.plan(targetId)
	local count, sum = 0, 0
	for _, layer in plan.layers do
		if SoundController.playLayer(layer.sound, layer.volume, layer.speed, layer.delay) then
			count += 1
			sum += layer.volume
		end
	end
	return count, sum
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
	local sound = if tense then getSound("Bgm_exam") else nil
	if not sound then
		sound = if musicName then getSound(musicName) else nil
	end
	fadeTo(sound)
end

function SoundController.setMusic(name: string?)
	musicName = name
	refreshMusic()
end

function SoundController.musicName(): string?
	return musicName
end

function SoundController.setTense(on: boolean)
	if tense == on then
		return
	end
	tense = on
	refreshMusic()
end

local function changed()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function SoundController.setMusicEnabled(on: boolean)
	musicEnabled = on
	refreshMusic()
	changed()
end

function SoundController.setSfxEnabled(on: boolean)
	sfxEnabled = on
	changed()
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
	local Attr = Tags.PlayerAttributes
	-- 깨짐 층 소리를 미리 만들어 불러오기 시작 (처음 깰 때 빠지지 않게)
	for _, name in { "Break", "BreakBig", "BreakBoom", "BreakStone1", "BreakStone2", "BreakDebris", "WoodCrack" } do
		getSound(name)
	end

	Net.on(E.Notify, function(payload: any)
		local kind = if type(payload) == "table" then payload.kind else nil
		if kind == "error" then
			SoundController.play("Error")
		elseif kind == "success" then
			SoundController.play("Purchase")
		else
			SoundController.play("Notify")
		end
	end)
	Net.on(E.HitResult, function(r: any)
		if type(r) ~= "table" then
			return
		end
		if r.reason == "weak" then
			SoundController.play("HitWeak")
		elseif r.broken then
			SoundController.playBreak(r.targetId)
		else
			SoundController.play("Hit")
		end
	end)
	local lastLift = 0
	Net.on(E.TrainResult, function()
		local now = os.clock()
		if now - lastLift > 0.2 then
			lastLift = now
			SoundController.play("Lift")
		end
	end)
	Net.on(E.ExamState, function(s: any)
		local phase = if type(s) == "table" then s.phase else nil
		if phase == "start" then
			SoundController.play("ExamStart")
			SoundController.setTense(true)
		elseif phase == "pass" then
			SoundController.play("BeltUp")
			SoundController.setTense(false)
		elseif phase == "fail" then
			SoundController.play("Fail")
			SoundController.setTense(false)
		end
	end)
	Net.on(E.DuelState, function(s: any)
		local phase = if type(s) == "table" then s.phase else nil
		if phase == "start" then
			SoundController.play("DuelStart")
			SoundController.setTense(true)
		elseif phase == "win" then
			SoundController.play("Pass")
			task.delay(0.6, function()
				SoundController.play("BeltUp")
			end)
			SoundController.setTense(false)
		elseif phase == "lose" then
			SoundController.play("Fail")
			SoundController.setTense(false)
		end
	end)

	-- 월드 음악 (지금 있는 월드)
	local function worldMusic()
		local w = player:GetAttribute(Attr.CurrentWorld)
		local n = if type(w) == "number" then math.clamp(w, 1, 3) else 1
		SoundController.setMusic("Bgm_world" .. tostring(n))
	end
	player:GetAttributeChangedSignal(Attr.CurrentWorld):Connect(worldMusic)
	worldMusic()

	-- 돈 짤랑 (최대 2초에 한 번)
	local lastMoney = player:GetAttribute(Attr.Money)
	local lastCoin = 0
	player:GetAttributeChangedSignal(Attr.Money):Connect(function()
		local money = player:GetAttribute(Attr.Money)
		if type(money) == "number" and type(lastMoney) == "number" and money > lastMoney then
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
