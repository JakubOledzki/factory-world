-- Works out the player's build grid (Shared.Logistics) up to now. Everything that reads or changes
-- what is on the grid, or a furnace inserters may reach, calls CatchUp first, so all of it sees the
-- same moment, with power (Logistics.RunPowered).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Logistics = require(Shared.Logistics)
local Power = require(Shared.Power)
local Clock = require(script.Parent.Clock)

local Factory = {}

-- `watch` (optional) is passed to Logistics.Run, for drawing what moved in the last tick.
function Factory.CatchUp(profile, watch)
	local grid = profile.grid
	local now = Clock.Now()
	if grid.at == nil or #grid.objects == 0 then
		grid.at = now
		grid.powerAt = now
		return
	end
	grid.at, grid.powerAt = Logistics.RunPowered(grid.objects, profile.furnaces, grid.at, grid.powerAt, now, watch)
end

-- Sets the machines' speed again after the grid changed (something put down or taken away, fuel
-- brought or taken). Call after CatchUp.
function Factory.Changed(profile)
	Power.Apply(profile.grid.objects, Logistics.Sizes, profile.grid.powerAt or Clock.Now())
end

-- The networks of the grid as they are now (after CatchUp).
function Factory.Networks(profile)
	return Power.Networks(profile.grid.objects, Logistics.Sizes)
end

-- What the network `o` is on gives and takes, for the windows: { supply, demand (kW), speed,
-- generators, machines, poles }; nil when no pole reaches it.
function Factory.NetworkInfo(profile, o)
	local net = Power.NetworkOf(Factory.Networks(profile), o)
	if net == nil then
		return nil
	end
	return {
		supply = Power.Supply(net),
		demand = net.demand,
		speed = Power.Speed(net),
		generators = #net.generators,
		machines = #net.consumers,
		poles = #net.poles,
	}
end

return Factory
