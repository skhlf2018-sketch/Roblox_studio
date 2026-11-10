--!nocheck
--[[
	ProductsPatch — 진짜 src/shared/Data/Products.luau 에서 id 칸(IDS 표의 `\tkey = 숫자,` 줄)만 바꾼 사본을 만드는 도우미
	(products.spec · holes_v9.spec 이 같이 씀. 글자 바꾸기라 진짜 파일의 나머지 코드는 그대로)

	왜 이렇게 하나:
	  진짜 파일에는 사장님이 만든 진짜 상품 id (게임패스 12 · 개발자 상품 25) 가 붙어 있음.
	  시험이 그 숫자에 기대면 id 를 고칠 때마다 깨지므로, 사본은 **언제나 37칸을 전부 0 으로 시작**하고
	  시험이 필요한 칸만 가짜 id 로 채움:
	    ProductsPatch.load({}, Config)                      → 37칸 전부 0 (아직 아무것도 안 만든 상태 = 전부 "준비 중")
	    ProductsPatch.load({ boost_2 = 11, tskip_1 = 13 }, Config) → 그 두 칸만 id 가 붙은 상태
	  (진짜 파일의 진짜 id 를 그대로 쓰는 시험은 이 도우미 없이 Loader.require 로 진짜 모듈을 씀)
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ProductsPatch = {}

local PRODUCTS_FILE = "src/shared/Data/Products.luau"
local ID_LINE = "\n\t([%a][%w_]*) = %d+," -- IDS 표의 한 줄 (이 줄의 숫자는 무엇이든)

-- IDS 표의 칸 수 (사장님 표: 부스트 11 + 코인 2배 1 + 러닝머신 레벨 20 + 상점 4 + 슈퍼 씨앗 1 — 64번)
ProductsPatch.SLOT_COUNT = 37

-- 소스 글자에서 IDS 표 37칸을 전부 0 으로 만들고, replacements 에 있는 칸만 그 값으로. 없는 칸 이름이 있으면 에러
function ProductsPatch.patchSource(source: string, replacements: { [string]: number }): string
	local startAt = string.find(source, "local IDS", 1, true)
	assert(startAt, PRODUCTS_FILE .. " 에 'local IDS' 표가 없음")
	local endAt = string.find(source, "\n}\n", startAt, true)
	assert(endAt, PRODUCTS_FILE .. " 의 IDS 표 끝('}')을 못 찾음")
	local block = string.sub(source, startAt, endAt)
	local seen, count = {}, 0
	block = string.gsub(block, ID_LINE, function(key)
		seen[key] = true
		count += 1
		return "\n\t" .. key .. " = " .. tostring(replacements[key] or 0) .. ","
	end)
	assert(
		count == ProductsPatch.SLOT_COUNT,
		PRODUCTS_FILE .. " IDS 칸이 " .. count .. "개 (" .. ProductsPatch.SLOT_COUNT .. "개여야 함)"
	)
	for key in replacements do
		assert(seen[key], PRODUCTS_FILE .. " 에 '" .. key .. " = 숫자,' 칸이 없음")
	end
	return string.sub(source, 1, startAt - 1) .. block .. string.sub(source, endAt + 1)
end

-- 바꾼 Products 모듈. Config = Products 가 require(script.Parent.Config) 로 받는 진짜 Config 모듈
function ProductsPatch.load(replacements: { [string]: number }, Config: any): any
	local source = ProductsPatch.patchSource(fs.readFile(PRODUCTS_FILE), replacements or {})
	local chunk = luau.load(source, {
		debugName = "Products(patched)",
		environment = {
			script = { Parent = { Config = "CONFIG" } },
			require = function()
				return Config
			end,
		},
	})
	return chunk()
end

return ProductsPatch
