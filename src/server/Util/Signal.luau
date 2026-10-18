--!strict
--[[
	Signal — 서비스끼리 이벤트를 주고받는 아주 작은 신호 (순환 require 를 피하려고 사용)
	  local changed = Signal.new()
	  local disconnect = changed:connect(function(phase) ... end)
	  changed:fire("Night")
	핸들러는 task.spawn 으로 따로 실행 → 한 핸들러가 멈추거나 에러 나도 다른 핸들러는 실행됨
]]

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { handlers: { (...any) -> () } }, Signal))

function Signal.new(): Signal
	return setmetatable({ handlers = {} }, Signal)
end

function Signal.connect(self: Signal, handler: (...any) -> ()): () -> ()
	table.insert(self.handlers, handler)
	return function()
		local index = table.find(self.handlers, handler)
		if index then
			table.remove(self.handlers, index)
		end
	end
end

function Signal.fire(self: Signal, ...: any)
	for _, handler in table.clone(self.handlers) do
		task.spawn(handler, ...)
	end
end

return Signal
