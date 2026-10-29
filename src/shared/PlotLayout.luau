-- Where things stand: the merchant's square in the middle of the server and the plots in a ring
-- around it. Offsets on a plot are in studs from its centre, x to the east and z to the south.
local PlotLayout = {}

-- Plots on one server; a server takes at most this many players.
PlotLayout.Count = 8

-- A plot is Size × Size studs.
PlotLayout.Size = 232

-- Distance from the middle of the square to the middle of each plot: far enough apart for a strip
-- of forest between neighbouring plots (Forest).
PlotLayout.Ring = 380

-- Everything on a plot stands on its build grid (Grid below). The plot's one mine stays where it
-- is, given by the middle of the 6 × 6 tiles it takes (with its cart), in studs from the plot's
-- centre. Plots had three mines before; the middle one is the one kept (Data).
PlotLayout.Mines = {
	{ x = 0, z = -100 },
}
PlotLayout.MineTiles = 6

-- The tiles of the wild trees a new plot starts with; they are cut and planted like any other.
PlotLayout.WildTrees = {
	{ x = 18, z = 9 }, { x = 18, z = 12 }, { x = 18, z = 15 }, { x = 18, z = 18 },
	{ x = 20, z = 10 }, { x = 20, z = 13 }, { x = 20, z = 16 }, { x = 20, z = 19 },
}

-- The grove a new home plot starts with besides those trees: a band of forest along the west, north
-- and south fences, left open in the middle of each side (the gates) and around the mine and the
-- station, with a free tile between trunks. Always the same tiles, so old plots get the same (Data).
function PlotLayout.Grove()
	local g = PlotLayout.Grid
	local state = 48271
	local function random(n)
		state = (state * 16807) % 2147483647
		return state % n
	end
	local out, taken = {}, {}
	for _, t in ipairs(PlotLayout.WildTrees) do
		taken[t.x .. "," .. t.z] = true
	end
	local band = 9
	local lane = 4
	local mid = g.width / 2
	for z = 1, g.depth - 2 do
		for x = 1, g.width - 2 do
			local edge = x <= band or z <= band or z >= g.depth - 1 - band
			local gate = math.abs(x + 0.5 - mid) <= lane or math.abs(z + 0.5 - mid) <= lane
			local station = x >= PlotLayout.Station.x - 6
			local free = edge and not gate and not station and not PlotLayout.Blocked(x, z)
			-- Off the mine's way and a little open, so it reads as a wood and not a wall.
			if free and random(100) < 13 then
				for ax = -1, 1 do
					for az = -1, 1 do
						if taken[(x + ax) .. "," .. (z + az)] then
							free = false
						end
					end
				end
				if free then
					taken[x .. "," .. z] = true
					table.insert(out, { x = x, z = z })
				end
			end
		end
	end
	return out
end

-- Furnaces stood on four slots before they went on the grid; a furnace saved on slot i is put on
-- the grid with its corner on tile FurnaceSlotTiles[i].
PlotLayout.FurnaceSlotTiles = {
	{ x = 28, z = 13 }, { x = 31, z = 13 }, { x = 34, z = 13 }, { x = 37, z = 13 },
}

-- The square: where the merchant's stall, the workbench, the fountain and the spawn stand, and
-- which way each faces (yaw, radians about the vertical; 0 faces -z).
PlotLayout.Stall = { x = 0, z = -18, yaw = math.pi }
PlotLayout.Workbench = { x = 20, z = -4, yaw = math.pi / 2 }
PlotLayout.Board = { x = -20, z = -4, yaw = -math.pi / 2 }
PlotLayout.Fountain = { x = 0, z = 0 }
PlotLayout.SquareSpawn = { x = 0, z = 14 }

-- Where the player appears on their plot.
PlotLayout.Spawn = { x = 0, z = -40 }

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
PlotLayout.Grid = { x = -112, z = -112, width = 56, depth = 56, tile = 4, layout = 3 }

-- Where tile (0, 0) of older layouts lies on today's plot (so that the mines stay put), to move
-- what players built: [layout] = { x, z }.
PlotLayout.OldGrids = { [1] = { x = -20, z = -84 }, [2] = { x = -44, z = -112 } }

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

-- Every plot's railway station (Shared.Rail): a building of `size` × `size` tiles with its corner
-- on tile (x, z), at the east edge of the grid, and the track just outside the east fence: along z
-- at `x` studs from the plot's centre, from `from` to `to`, ending in a tunnel at each end. Trains
-- come out of the south tunnel, stop at the platform by the station (`stop`, z of the locomotive's
-- front) and go on into the north one. The same on every plot, so a grid fits any plot it is put on.
PlotLayout.Station = { x = 53, z = 4, size = 3 }
PlotLayout.Rail = { x = 124, from = -134, to = 134, stop = -104, clear = 9 }

-- The station's span along the east fence, in studs from the plot's centre: from, to.
function PlotLayout.StationSpan()
	local s, g = PlotLayout.Station, PlotLayout.Grid
	return g.z + s.z * g.tile, g.z + (s.z + s.size) * g.tile
end

-- Openings in the fence besides the gate (Models.PlotDecor): the way from the station to the platform.
function PlotLayout.FenceGaps()
	local from, to = PlotLayout.StationSpan()
	return { { "x+", from + 2, to - 2 } }
end

-- Whether tile (tx, tz) lies under the station.
function PlotLayout.StationTile(tx, tz)
	local s = PlotLayout.Station
	return tx >= s.x and tx < s.x + s.size and tz >= s.z and tz < s.z + s.size
end

-- The forest between the plots and around the square: only to look at, nothing in it can be cut
-- or built. It keeps clear of the plots, the square and the paths, and reaches out to the edge of
-- the ground (World), where it closes the world.
PlotLayout.Forest = {
	spacing = 11, -- studs between neighbouring trees, before each is moved a little at random
	plotMargin = 7, -- studs kept clear outside a plot's fence
	square = 52, -- radius kept clear around the middle of the square
	path = 9, -- studs kept clear either side of the middle of a path
	seed = 4242,
}

-- Half the width of the ground the world stands on.
function PlotLayout.GroundHalf()
	return PlotLayout.Ring + PlotLayout.Size / 2 + 40
end

-- Whether a forest tree may stand at x, z (from the middle of the square).
function PlotLayout.ForestClear(x, z)
	local f = PlotLayout.Forest
	if x * x + z * z < f.square * f.square then
		return false
	end
	local reach = PlotLayout.Size / 2 + f.plotMargin
	for index = 1, PlotLayout.Count do
		local cx, cz = PlotLayout.Center(index)
		if math.abs(x - cx) < reach and math.abs(z - cz) < reach then
			return false
		end
		-- The railway along the east fence, and its tunnels.
		local r = PlotLayout.Rail
		if math.abs(x - cx - r.x) < r.clear and z - cz > r.from - r.clear and z - cz < r.to + r.clear then
			return false
		end
		-- The path runs from the square straight to the plot's centre.
		local length = math.sqrt(cx * cx + cz * cz)
		local along = (x * cx + z * cz) / length
		local across = math.abs(x * cz - z * cx) / length
		if along > 0 and along < length and across < f.path then
			return false
		end
	end
	return true
end

-- The forest's trees as { x, z, seed, yaw }, always the same.
function PlotLayout.ForestTrees()
	local f = PlotLayout.Forest
	local state = f.seed
	local function random()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
	local trees = {}
	local edge = PlotLayout.GroundHalf() - 3
	local n = math.floor(edge / f.spacing)
	for i = -n, n do
		for j = -n, n do
			local x = i * f.spacing + (random() - 0.5) * f.spacing * 0.8
			local z = j * f.spacing + (random() - 0.5) * f.spacing * 0.8
			local seed = math.floor(random() * 100000)
			local yaw = random() * 2 * math.pi
			if math.abs(x) < edge and math.abs(z) < edge and PlotLayout.ForestClear(x, z) then
				table.insert(trees, { x = x, z = z, seed = seed, yaw = yaw })
			end
		end
	end
	return trees
end

-- The yaw that turns a model's front (-z) the way rotation `rot` faces: 0 south (+z), 1 east (+x),
-- 2 north (-z), 3 west (-x).
local Yaws = { math.pi, -math.pi / 2, 0, math.pi / 2 }
function PlotLayout.Yaw(rot)
	return Yaws[rot % 4 + 1]
end

return PlotLayout
