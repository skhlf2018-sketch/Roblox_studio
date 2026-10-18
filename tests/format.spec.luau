--!nocheck
-- 숫자/시간 표시

return function(T, Loader)
	local Format = Loader.require("ReplicatedStorage/Shared/Format")

	T.suite("Format")

	T.test("숫자 단위 K/M/B/T/Qa", function()
		T.eq(Format.number(0), "0")
		T.eq(Format.number(999), "999")
		T.eq(Format.number(1000), "1K")
		T.eq(Format.number(1500), "1.5K")
		T.eq(Format.number(16e6), "16M")
		T.eq(Format.number(2.5e9), "2.5B")
		T.eq(Format.number(12.5e12), "12.5T")
		T.eq(Format.number(5e15), "5Qa")
		T.eq(Format.number(123456), "123K")
		T.eq(Format.number(-1500), "-1.5K")
		T.eq(Format.money(180000), "$180K")
	end)

	T.test("시간", function()
		T.eq(Format.duration(20), "20s")
		T.eq(Format.duration(90), "1m 30s")
		T.eq(Format.duration(300), "5m")
		T.eq(Format.duration(5400), "1h 30m")
		T.eq(Format.duration(86400), "24h")
		T.eq(Format.duration(3.2), "4s")
	end)
end
