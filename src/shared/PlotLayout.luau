-- Where things stand: the merchant's square in the middle of the server and the plots in a ring
-- around it. Offsets on a plot are in studs from its centre, x to the east and z to the south.
local PlotLayout = {}

-- Plots on one server; a server takes at most this many players.
PlotLayout.Count = 8

-- A plot is Size × Size studs.
PlotLayout.Size = 90

-- Distance from the middle of the square to the middle of each plot.
PlotLayout.Ring = 140

-- Everything on a plot stands on its build grid (Grid below). The mines stay where they are, given
-- by the middle of the 6 × 6 tiles each takes (with its cart), in studs from the plot's centre.
PlotLayout.Mines = {
	{ x = -24, z = -30 },
	{ x = 0, z = -30 },
	{ x = 24, z = -30 },
}
PlotLayout.MineTiles = 6

-- The tiles of the wild trees a new plot starts with; they are cut and planted like any other.
PlotLayout.WildTrees = {
	{ x = 1, z = 9 }, { x = 1, z = 12 }, { x = 1, z = 15 }, { x = 1, z = 18 },
	{ x = 3, z = 10 }, { x = 3, z = 13 }, { x = 3, z = 16 }, { x = 3, z = 19 },
}

-- Furnaces stood on four slots before they went on the grid; a furnace saved on slot i is put on
-- the grid with its corner on tile FurnaceSlotTiles[i].
PlotLayout.FurnaceSlotTiles = {
	{ x = 11, z = 13 }, { x = 14, z = 13 }, { x = 17, z = 13 }, { x = 20, z = 13 },
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

-- The build grid over the whole plot: `width` × `depth` tiles of `tile` studs, with the corner of
-- tile (0, 0) at (x, z) from the plot's centre. Tile x grows to the east and tile z to the south,
-- like the studs. The tiles of the mines are taken for good (Blocked).
-- `layout` counts changes of the grid: player data from an older one is moved over (Data).
PlotLayout.Grid = { x = -44, z = -42, width = 22, depth = 21, tile = 4, layout = 2 }

-- Where tile (0, 0) was in older layouts, to move what players built: [layout] = { x, z }.
PlotLayout.OldGrids = { [1] = { x = -20, z = -14 } }

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

-- The tiles the mines take, as { x1, z1, x2, z2 } in studs from the plot's centre.
local function blockedAreas()
	local areas = {}
	local half = PlotLayout.MineTiles * PlotLayout.Grid.tile / 2
	for _, m in ipairs(PlotLayout.Mines) do
		table.insert(areas, { m.x - half, m.z - half, m.x + half, m.z + half })
	end
	return areas
end
local blocked = nil

-- Whether tile (tx, tz) is taken by something the plot always has (a mine).
function PlotLayout.Blocked(tx, tz)
	if blocked == nil then
		blocked = blockedAreas()
	end
	local g = PlotLayout.Grid
	local x1, z1 = g.x + tx * g.tile, g.z + tz * g.tile
	local x2, z2 = x1 + g.tile, z1 + g.tile
	for _, a in ipairs(blocked) do
		if x1 < a[3] and x2 > a[1] and z1 < a[4] and z2 > a[2] then
			return true
		end
	end
	return false
end

-- The yaw that turns a model's front (-z) the way rotation `rot` faces: 0 south (+z), 1 east (+x),
-- 2 north (-z), 3 west (-x).
local Yaws = { math.pi, -math.pi / 2, 0, math.pi / 2 }
function PlotLayout.Yaw(rot)
	return Yaws[rot % 4 + 1]
end

return PlotLayout
