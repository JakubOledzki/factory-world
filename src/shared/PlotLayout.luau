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

-- The build grid between the mines and the furnace yard: `width` × `depth` tiles of `tile` studs,
-- with the corner of tile (0, 0) at (x, z) from the plot's centre. Tile x grows to the east and
-- tile z to the south, like the studs.
PlotLayout.Grid = { x = -20, z = -14, width = 15, depth = 5, tile = 4 }

-- Studs from which a player can build on their grid.
PlotLayout.BuildReach = 48

-- The centre of something `size` tiles across whose corner tile is (tx, tz), as x, z from the
-- plot's centre.
function PlotLayout.TileCenter(tx, tz, size)
	local g = PlotLayout.Grid
	size = size or 1
	return g.x + (tx + size / 2) * g.tile, g.z + (tz + size / 2) * g.tile
end

-- The tile under the point x, z from the plot's centre (it may lie outside the grid).
function PlotLayout.TileAt(x, z)
	local g = PlotLayout.Grid
	return math.floor((x - g.x) / g.tile), math.floor((z - g.z) / g.tile)
end

-- The yaw that turns a model's front (-z) the way rotation `rot` faces: 0 south (+z), 1 east (+x),
-- 2 north (-z), 3 west (-x).
local Yaws = { math.pi, -math.pi / 2, 0, math.pi / 2 }
function PlotLayout.Yaw(rot)
	return Yaws[rot % 4 + 1]
end

return PlotLayout
