--!strict
--[[
	Groups — 충돌 그룹 이름 (선임, 사장님 결정 13번). 맵(Build)과 몸(PlayerVisualService)이 같이 씀. 불러올 때 서비스를 안 부름.
	  PASS = 도장 지붕·윗벽·천장·문 위 들보 · PLAYER = 플레이어 캐릭터 파트 → 둘은 안 부딪힘
	  (문·천장보다 큰 거인이 작은 월드에 와도 안 끼임. 카메라·다른 물체와는 그대로 부딪혀서 보통 몸 카메라는 천장 아래에서 멈춤)
	  Groups.register() → 등록 성공 여부 (PhysicsService 없으면 false — 테스트)
]]

local Groups = {}

Groups.PASS = "GiantPass"
Groups.PLAYER = "Players"
Groups.LIGHT_RANGE_MAX = 60 -- PointLight/SpotLight/SurfaceLight Range 상한 (로블록스)

function Groups.register(): boolean
	return pcall(function()
		local PhysicsService = game:GetService("PhysicsService") :: any
		for _, name in { Groups.PASS, Groups.PLAYER } do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(Groups.PASS, Groups.PLAYER, false)
	end)
end

return Groups
