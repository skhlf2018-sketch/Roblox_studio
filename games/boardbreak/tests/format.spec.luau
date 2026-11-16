--!nocheck
-- Format: 단위 K M B T Qa Qi Sx Sp Oc No Dc Ud … Nod Vg (1e60 까지), NaN·무한
return function(T, Loader)
	local Format = Loader.require("ReplicatedStorage/Shared/Format")

	T.suite("format")

	T.test("작은 수 · 단위 경계", function()
		T.eq(Format.number(0), "0")
		T.eq(Format.number(3), "3")
		T.eq(Format.number(999), "999")
		T.eq(Format.number(1000), "1K")
		T.eq(Format.number(1500), "1.5K")
		T.eq(Format.number(524288), "524K")
		T.eq(Format.number(1e6), "1M")
		T.eq(Format.number(16e6), "16M")
		T.eq(Format.number(2.42e3), "2.42K")
		T.eq(Format.number(999999), "999K")
	end)

	T.test("설계서 단위 순서 K < M < B < T < Qa < Qi < Sx < Sp < Oc < No < Dc", function()
		local units = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
		for i, u in units do
			T.eq(Format.number(10 ^ (3 * i)), "1" .. u, u)
		end
	end)

	T.test("1e60 까지 단위로 (Ud … Nod), 1e63 = Vg, 그 뒤는 지수", function()
		local more = { "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg" }
		for i, u in more do
			T.eq(Format.number(10 ^ (33 + 3 * i)), "1" .. u, u)
		end
		T.eq(Format.number(1e60), "1Nod", "1e60")
		T.eq(Format.number(1.5e24), "1.5Sp", "우주 값")
		T.eq(Format.number(1e66), "1e66", "단위 너머")
		T.eq(Format.number(2.5e70), "2.5e70", "지수")
	end)

	T.test("오차가 쌓이지 않음 (1e29 = 100Oc, 99.9 아님)", function()
		T.eq(Format.number(1e29), "100Oc")
		T.eq(Format.number(1e38), "100Ud")
		T.eq(Format.number(1e40), "10Dd")
		T.eq(Format.number(1.67e43), "16.7Td")
	end)

	T.test("NaN · 무한 · 음수", function()
		T.eq(Format.number(0 / 0), "0", "NaN")
		T.eq(Format.number(math.huge), "inf", "inf")
		T.eq(Format.number(-math.huge), "-inf", "-inf")
		T.eq(Format.number(-1500), "-1.5K", "음수")
	end)

	T.test("comma · duration · money", function()
		T.eq(Format.comma(1024), "1,024")
		T.eq(Format.comma(1000000), "1,000,000")
		T.eq(Format.comma(999), "999")
		T.eq(Format.money(1e9), "1B")
		T.eq(Format.duration(5400), "1h 30m")
		T.eq(Format.duration(65), "1m 5s")
		T.eq(Format.duration(0 / 0), "0s")
	end)
end
