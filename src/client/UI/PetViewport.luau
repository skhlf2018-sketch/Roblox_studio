--!strict
--[[
	PetViewport — 식물 3D 모습을 UI 안에 (ViewportFrame)
	서버 PlantVisualService 가 만든 ReplicatedStorage.PetModels[식물 id] (식물 134종) 를 복제해서 비춤.
	  PetViewport.new(petId, { silhouette = true })  → 발견 전 "검은 실루엣"
	  PetViewport.spin(viewport)                      → 천천히 빙글 (성체 카드 한 개에만)
	아직 모델 도서관이 안 왔으면 동그라미를 보여 주고 도착하면 채움.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetViewport = {}

export type Options = {
	silhouette: boolean?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
}

local library: Instance? = nil

local function getLibrary(timeout: number): Instance?
	local lib = library
	if lib and lib.Parent then
		return lib
	end
	local found = ReplicatedStorage:FindFirstChild("PetModels")
	if not found and timeout > 0 then
		found = ReplicatedStorage:WaitForChild("PetModels", timeout)
	end
	library = found
	return found
end

local function frame(viewport: ViewportFrame, model: Model, camera: Camera, yaw: number)
	local cf, size = model:GetBoundingBox()
	local extent = math.max(size.X, size.Y, size.Z)
	local distance = extent / (2 * math.tan(math.rad(camera.FieldOfView) / 2)) * 1.25
	local center = cf.Position
	local dir = (CFrame.Angles(0, yaw, 0) * Vector3.new(0.55, 0.42, -1)).Unit
	camera.CFrame = CFrame.lookAt(center + dir * distance, center)
	viewport.CurrentCamera = camera
end

local function fill(viewport: ViewportFrame, petId: string, silhouette: boolean)
	local lib = getLibrary(0)
	local template = if lib then lib:FindFirstChild(petId) else nil
	if not template or not template:IsA("Model") then
		return false
	end
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child.Name == "Placeholder" then
			child:Destroy()
		end
	end
	local model = template:Clone()
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local camera = viewport:FindFirstChildOfClass("Camera") or Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = viewport
	frame(viewport, model, camera, 0)
	if silhouette then
		viewport.ImageColor3 = Color3.new(0, 0, 0)
		viewport.Ambient = Color3.new(0, 0, 0)
		viewport.LightColor = Color3.new(0, 0, 0)
	end
	return true
end

function PetViewport.new(petId: string, opts: Options?): ViewportFrame
	local o: Options = opts or {}
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "PetView"
	viewport.BackgroundTransparency = 1
	viewport.Size = o.size or UDim2.fromScale(1, 1)
	viewport.Position = o.position or UDim2.new()
	viewport.AnchorPoint = o.anchor or Vector2.zero
	viewport.Ambient = Color3.fromRGB(190, 190, 200)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.6, -1, 0.8)
	local silhouette = o.silhouette == true
	if not fill(viewport, petId, silhouette) then
		local placeholder = Instance.new("Frame")
		placeholder.Name = "Placeholder"
		placeholder.AnchorPoint = Vector2.new(0.5, 0.5)
		placeholder.Position = UDim2.fromScale(0.5, 0.5)
		placeholder.Size = UDim2.fromScale(0.5, 0.5)
		placeholder.BackgroundColor3 = if silhouette then Color3.new(0, 0, 0) else Color3.fromRGB(255, 230, 200)
		placeholder.Parent = viewport
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = placeholder
		task.spawn(function()
			if getLibrary(60) then
				-- 도서관은 서버가 다 만든 뒤 한 번에 넣음
				task.wait(0.5)
				if viewport.Parent then
					fill(viewport, petId, silhouette)
				end
			end
		end)
	end
	return viewport
end

-- 천천히 빙글 돌리기 (뷰포트가 사라지면 자동 해제)
function PetViewport.spin(viewport: ViewportFrame, speed: number?)
	local yaw = 0
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function(dt: number)
		if viewport.Parent == nil then
			if connection then
				connection:Disconnect()
			end
			return
		end
		local model = viewport:FindFirstChildOfClass("Model")
		local camera = viewport.CurrentCamera
		if model and camera then
			yaw += dt * (speed or 0.8)
			frame(viewport, model, camera, yaw)
		end
	end)
end

return PetViewport
