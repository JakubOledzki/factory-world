-- Faster work for testing in Roblox Studio only: holding a prompt to mine or cut takes a moment,
-- mines never run dry and saplings grow in seconds. A published game runs at the 2D game's pace.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Forestry = require(Shared.Forestry)

local TestMode = {}

TestMode.On = RunService:IsStudio()

local HoldSeconds = 0.3

if TestMode.On then
	-- Only this server's copy of the rules; the clients and the tests keep the real time.
	Forestry.Grow = 20
end

-- How long a prompt of `seconds` is held.
function TestMode.Hold(seconds)
	if TestMode.On then
		return math.min(seconds, HoldSeconds)
	end
	return seconds
end

return TestMode
