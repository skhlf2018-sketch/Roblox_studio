--!strict
--[[
	RateLimiter — 토큰 버킷 레이트 리밋 (순수 로직, Lune 테스트 대상)
	  local limiter = RateLimiter.new(os.clock)
	  if limiter:allow(player.UserId, "HatchEgg", 10, 4) then ... end
	플레이어가 나가면 limiter:forget(userId)
]]

type Bucket = {
	tokens: number,
	updatedAt: number,
}

export type RateLimiter = {
	clock: () -> number,
	buckets: { [number]: { [string]: Bucket } },
	allow: (self: RateLimiter, userId: number, key: string, burst: number, perSecond: number) -> boolean,
	forget: (self: RateLimiter, userId: number) -> (),
}

local RateLimiter = {}

local function allow(self: RateLimiter, userId: number, key: string, burst: number, perSecond: number): boolean
	local now = self.clock()
	local perUser = self.buckets[userId]
	if not perUser then
		perUser = {}
		self.buckets[userId] = perUser
	end
	local bucket = perUser[key]
	if not bucket then
		bucket = { tokens = burst, updatedAt = now }
		perUser[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.tokens = math.min(burst, bucket.tokens + elapsed * perSecond)
	bucket.updatedAt = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

local function forget(self: RateLimiter, userId: number)
	self.buckets[userId] = nil
end

function RateLimiter.new(clock: (() -> number)?): RateLimiter
	return {
		clock = clock or os.clock,
		buckets = {},
		allow = allow,
		forget = forget,
	}
end

return RateLimiter
