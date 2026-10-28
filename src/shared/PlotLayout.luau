-- Where things stand: the merchant's square in the middle of the server and the plots in a ring
-- around it. Offsets on a plot are in studs from its centre, x to the east and z to the south.
local PlotLayout = {}

-- Plots on one server; a server takes at most this many players.
PlotLayout.Count = 8

-- A plot is Size × Size studs.
PlotLayout.Size = 90

-- Distance from the middle of the square to the middle of each plot.
PlotLayout.Ring = 140

PlotLayout.Mines = {
	{ x = -25, z = -30 },
	{ x = 0, z = -32 },
	{ x = 25, z = -30 },
}

PlotLayout.Trees = {
	{ x = -38, z = -6 }, { x = -38, z = 7 }, { x = -38, z = 20 }, { x = -38, z = 33 },
	{ x = -28, z = 0 }, { x = -28, z = 13 }, { x = -28, z = 26 }, { x = -28, z = 39 },
}

PlotLayout.FurnaceSlots = {
	{ x = 8, z = 14 }, { x = 18, z = 14 }, { x = 28, z = 14 }, { x = 38, z = 14 },
}

-- The square: where the merchant's stall, the workbench, the fountain and the spawn stand, and
-- which way each faces (yaw, radians about the vertical; 0 faces -z).
PlotLayout.Stall = { x = 0, z = -18, yaw = math.pi }
PlotLayout.Workbench = { x = 20, z = -4, yaw = math.pi / 2 }
PlotLayout.Fountain = { x = 0, z = 0 }
PlotLayout.SquareSpawn = { x = 0, z = 14 }

-- Where the player appears on their plot.
PlotLayout.Spawn = { x = 0, z = 30 }

-- The centre of plot `index` (1..Count) as x, z.
function PlotLayout.Center(index)
	local angle = (index - 1) / PlotLayout.Count * 2 * math.pi
	return math.floor(math.cos(angle) * PlotLayout.Ring + 0.5), math.floor(math.sin(angle) * PlotLayout.Ring + 0.5)
end

-- Sides of plot `index` whose fence has a gate for the path to the square: "x+", "x-", "z+", "z-".
function PlotLayout.OpenSides(index)
	local cx, cz = PlotLayout.Center(index)
	local length = math.sqrt(cx * cx + cz * cz)
	local tx, tz = -cx / length, -cz / length
	local open = {}
	if tx >= 0.7 then table.insert(open, "x+") end
	if tx <= -0.7 then table.insert(open, "x-") end
	if tz >= 0.7 then table.insert(open, "z+") end
	if tz <= -0.7 then table.insert(open, "z-") end
	return open
end

-- Studs within which a player can work something on their plot.
PlotLayout.Reach = 14

return PlotLayout
