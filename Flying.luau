-- made by MaidModeZen; github: spectralize-d; im getting desperate for my application to be accepted!!

-- Services
const UserInputService = game:GetService("UserInputService")

-- Settings
local flightSpeed    = 50                 -- The speed at which the player flies
local keyToToggleFly = Enum.KeyCode.F  -- Key to toggle fly mode on PC (mobile uses a button)

-- constants start
const player    = game.Players.LocalPlayer
const character = player.Character or player.CharacterAdded:Wait()
const Humanoid  = character:WaitForChild("Humanoid")

-- Load animations for each flying direction
const FlyUpAnim      = Humanoid:LoadAnimation(script.FlyUpAnim)
const FlyDownAnim    = Humanoid:LoadAnimation(script.FlyDownAnim)
const FlyLeftAnim    = Humanoid:LoadAnimation(script.FlyLeftAnim)
const FlyRightAnim   = Humanoid:LoadAnimation(script.FlyRightAnim)
const FlyForwardAnim = Humanoid:LoadAnimation(script.FlyFowardAnim)
const FlyBackAnim    = Humanoid:LoadAnimation(script.FlyBackAnim)
const FlyIdleAnim    = Humanoid:LoadAnimation(script.FlyIdleAnim)

const isMobile = UserInputService.TouchEnabled
-- constants end

local mouse = player:GetMouse()
local flying = false
local bodyGyro, bodyVelocity


-- Input states for direction
local moveForward = false
local moveBackward = false
local moveLeft = false
local moveRight = false
local moveUp = false
local moveDown = false

-- Mobile UI buttons
local forwardButton, backwardButton, leftButton, rightButton, upButton, downButton, activateButton

-- start flying
local function startFlying()
	FlyIdleAnim:Play()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

	-- Create BodyVelocity and BodyGyro for movement
	bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Velocity = Vector3.new(0, 0, 0)
	bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
	bodyVelocity.Parent = humanoidRootPart

	bodyGyro = Instance.new("BodyGyro")
	bodyGyro.CFrame = humanoidRootPart.CFrame
	bodyGyro.MaxTorque = Vector3.new(100000, 100000, 100000)
	bodyGyro.P = 10000
	bodyGyro.Parent = humanoidRootPart

	-- Flying loop; runs every frame before being rendered
	local flyLoop
	flyLoop = game:GetService("RunService").RenderStepped:Connect(function()
		-- Update BodyGyro to match the player's camera orientation
		bodyGyro.CFrame = workspace.CurrentCamera.CFrame

		-- Get direction based on player's input
		local moveDirection = Vector3.new()

		if moveForward then
			moveDirection = moveDirection + (workspace.CurrentCamera.CFrame.LookVector * flightSpeed)
		end
		if moveBackward then
			moveDirection = moveDirection - (workspace.CurrentCamera.CFrame.LookVector * flightSpeed)
		end
		if moveLeft then
			moveDirection = moveDirection - (workspace.CurrentCamera.CFrame.RightVector * flightSpeed)
		end
		if moveRight then
			moveDirection = moveDirection + (workspace.CurrentCamera.CFrame.RightVector * flightSpeed)
		end
		if moveUp then
			moveDirection = moveDirection + Vector3.new(0, flightSpeed, 0)
		end
		if moveDown then
			moveDirection = moveDirection - Vector3.new(0, flightSpeed, 0)
		end

		-- Update velocity
		bodyVelocity.Velocity = moveDirection
	end)

	-- Stop flying when the player dies
	Humanoid.Died:Connect(function()
		flyLoop:Disconnect()
	end)
end

local function stopFlying()
	FlyIdleAnim:Stop()
	-- Destroy BodyVelocity and BodyGyro
	if bodyVelocity then bodyVelocity:Destroy() end
	if bodyGyro then bodyGyro:Destroy() end
end

-- Initialize mobile buttons and their variables
local function createMobileControls()
	forwardButton = (script.Parent.Parent.FlyForwardBtn)
	backwardButton = (script.Parent.Parent.FlyBackBtn)
	leftButton = (script.Parent.Parent.FlyLeftBtn)
	rightButton = (script.Parent.Parent.FlyRightBtn)
	upButton = (script.Parent.Parent.FlyUpBtn)
	downButton = (script.Parent.Parent.FlyDownBtn)
	activateButton = (script.Parent.Parent.FlyActBtn)

	-- Initialize all button controls and inputs
	forwardButton.MouseButton1Down:Connect(function() moveForward = true; FlyForwardAnim:Play() end)
	forwardButton.MouseButton1Up:Connect(function() moveForward = false; FlyForwardAnim:Stop() end)

	backwardButton.MouseButton1Down:Connect(function() moveBackward = true; FlyBackAnim:Play() end)
	backwardButton.MouseButton1Up:Connect(function() moveBackward = false; FlyBackAnim:Stop() end)

	leftButton.MouseButton1Down:Connect(function() moveLeft = true; FlyLeftAnim:Play() end)
	leftButton.MouseButton1Up:Connect(function() moveLeft = false; FlyLeftAnim:Stop() end)

	rightButton.MouseButton1Down:Connect(function() moveRight = true; FlyRightAnim:Play() end)
	rightButton.MouseButton1Up:Connect(function() moveRight = false; FlyRightAnim:Stop() end)

	upButton.MouseButton1Down:Connect(function() moveUp = true; FlyUpAnim:Play() end)
	upButton.MouseButton1Up:Connect(function() moveUp = false; FlyUpAnim:Stop() end)

	downButton.MouseButton1Down:Connect(function() moveDown = true; FlyDownAnim:Play() end)
	downButton.MouseButton1Up:Connect(function() moveDown = false; FlyDownAnim:Stop() end)
	activateButton.MouseButton1Up:Connect(function() if not flying then startFlying() else stopFlying() end end)
end

-- Handle input for flying directions
local function onInputBegan(input, proc)
	if proc then return end
	if flying then
		if input.KeyCode == Enum.KeyCode.W then
			FlyForwardAnim:Play()
			moveForward = true
		elseif input.KeyCode == Enum.KeyCode.S then
			FlyBackAnim:Play()
			moveBackward = true
		elseif input.KeyCode == Enum.KeyCode.A then
			FlyLeftAnim:Play()
			moveLeft = true
		elseif input.KeyCode == Enum.KeyCode.D then
			FlyRightAnim:Play()
			moveRight = true
		elseif input.KeyCode == Enum.KeyCode.Space then
			FlyUpAnim:Play()
			moveUp = true
		elseif input.KeyCode == Enum.KeyCode.LeftControl then
			FlyDownAnim:Play()
			moveDown = true
		end
	end
end

local function onInputEnded(input)
	if flying then
		if input.KeyCode == Enum.KeyCode.W then
			FlyForwardAnim:Stop()
			moveForward = false
		elseif input.KeyCode == Enum.KeyCode.S then
			FlyBackAnim:Stop()
			moveBackward = false
		elseif input.KeyCode == Enum.KeyCode.A then
			FlyLeftAnim:Stop()
			moveLeft = false
		elseif input.KeyCode == Enum.KeyCode.D then
			FlyRightAnim:Stop()
			moveRight = false
		elseif input.KeyCode == Enum.KeyCode.Space then
			FlyUpAnim:Stop()
			moveUp = false
		elseif input.KeyCode == Enum.KeyCode.LeftControl then
			FlyDownAnim:Stop()
			moveDown = false
		end
	end
end

-- Toggle flying on key press
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == keyToToggleFly then
		if not flying then
			startFlying()
		else
			stopFlying()
		end
		flying = not flying
	end
end)

-- Connect input events for directional control
UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)

-- Setup mobile controls if on mobile
if isMobile then
	createMobileControls()
end
