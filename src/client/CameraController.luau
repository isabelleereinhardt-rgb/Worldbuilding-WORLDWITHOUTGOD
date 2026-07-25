--!strict
-- Board-game camera: slightly angled top-down view that smoothly follows
-- the local player's character, zooming out during movement and back in
-- when stopped (matching the Board Game Insanity reference).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraController = {}

local FOLLOW_OFFSET = Vector3.new(0, 34, 26)
local MOVE_OFFSET = Vector3.new(0, 44, 34) -- zoomed out while moving
local LERP_SPEED = 4

local enabled = false
local connection: RBXScriptConnection? = nil

-- Screen shake (hits, explosions, deaths): decays linearly over `shakeDuration`.
local shakeMagnitude = 0
local shakeStartTime = 0
local shakeDuration = 0

function CameraController.shake(magnitude: number, duration: number)
	shakeMagnitude = magnitude
	shakeStartTime = os.clock()
	shakeDuration = duration
end

local function shakeOffset(): Vector3
	if shakeDuration <= 0 then
		return Vector3.zero
	end
	local elapsed = os.clock() - shakeStartTime
	if elapsed >= shakeDuration then
		return Vector3.zero
	end
	local falloff = 1 - (elapsed / shakeDuration)
	local m = shakeMagnitude * falloff
	return Vector3.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
end

function CameraController.enable()
	if enabled then
		return
	end
	enabled = true
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	connection = RunService.RenderStepped:Connect(function(dt)
		local character = Players.LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		local moving = hrp.AssemblyLinearVelocity.Magnitude > 2
		local offset = moving and MOVE_OFFSET or FOLLOW_OFFSET
		local targetCFrame = CFrame.lookAt(hrp.Position + offset, hrp.Position)
		camera.CFrame = camera.CFrame:Lerp(targetCFrame, math.clamp(dt * LERP_SPEED, 0, 1))
			* CFrame.new(shakeOffset())
	end)
end

function CameraController.disable()
	enabled = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

-- Spectator free-follow: watch any character (dead players use this).
function CameraController.followCharacter(character: Model?)
	if not character then
		return
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	if connection then
		connection:Disconnect()
	end
	connection = RunService.RenderStepped:Connect(function(dt)
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		local targetCFrame = CFrame.lookAt(hrp.Position + FOLLOW_OFFSET, hrp.Position)
		camera.CFrame = camera.CFrame:Lerp(targetCFrame, math.clamp(dt * LERP_SPEED, 0, 1))
			* CFrame.new(shakeOffset())
	end)
	enabled = true
end

return CameraController
