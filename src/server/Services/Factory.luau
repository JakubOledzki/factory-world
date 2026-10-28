-- Works out the player's build grid (Shared.Logistics) up to now. Everything that reads or changes
-- what is on the grid, or a furnace inserters may reach, calls CatchUp first, so all of it sees the
-- same moment.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Logistics = require(Shared.Logistics)
local Clock = require(script.Parent.Clock)

local Factory = {}

function Factory.CatchUp(profile)
	local grid = profile.grid
	local now = Clock.Now()
	if grid.at == nil or #grid.objects == 0 then
		grid.at = now
		return
	end
	grid.at = Logistics.Run(grid.objects, profile.furnaces, grid.at, now)
end

return Factory
