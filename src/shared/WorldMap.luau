-- The world map (WorldMap.cs on main draws the real Earth; here the world is made up): a world
-- of Km, every player's railway station somewhere on its land (Rail.Location), and the land.
-- Land is worked out from the place alone, the same everywhere: snow at the poles, then tundra and taiga, then forest, plains and steppe, and desert about the middle, with
-- mountains, lakes and seas where the noise says. Pure functions.
local WorldMap = {}

-- The world, km across (east-west wraps round) and from north to south.
WorldMap.Km = { width = 2400, height = 1200 }

-- The map is drawn as Columns × Rows cells.
WorldMap.Columns = 60
WorldMap.Rows = 30

WorldMap.Biomes = {
	sea = { name = "Morze", color = { 58, 104, 160 } },
	lake = { name = "Jezioro", color = { 78, 130, 186 } },
	snow = { name = "Lodowiec", color = { 232, 238, 244 } },
	tundra = { name = "Tundra", color = { 166, 172, 146 } },
	taiga = { name = "Tajga", color = { 62, 102, 72 } },
	forest = { name = "Las", color = { 74, 130, 70 } },
	plains = { name = "Równiny", color = { 132, 172, 92 } },
	steppe = { name = "Step", color = { 186, 180, 112 } },
	desert = { name = "Pustynia", color = { 222, 196, 132 } },
	mountains = { name = "Góry", color = { 128, 116, 104 } },
}

local function hash(x, y, seed)
	local v = math.sin(x * 12.9898 + y * 78.233 + seed * 37.719) * 43758.5453
	return v - math.floor(v)
end

-- Smooth noise from 0 to 1 over a grid of `cell` km (a divisor of the width), wrapping east-west.
local function noise(x, y, cell, seed)
	local width = math.floor(WorldMap.Km.width / cell + 0.5)
	local gx, gy = x / cell, y / cell
	local x0, y0 = math.floor(gx), math.floor(gy)
	local fx, fy = gx - x0, gy - y0
	fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
	local function at(i, j)
		return hash(i % width, j, seed)
	end
	local a = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * fx
	local b = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * fx
	return a + (b - a) * fy
end

-- The land at x, y km: an id of WorldMap.Biomes.
function WorldMap.Biome(x, y)
	local h = 0.55 * noise(x, y, 240, 1) + 0.3 * noise(x, y, 120, 2) + 0.15 * noise(x, y, 48, 4)
	-- From the equator (0) to a pole (1).
	local lat = math.abs(y / WorldMap.Km.height - 0.5) * 2
	if lat > 0.93 then
		return "snow"
	end
	if h < 0.36 then
		return "sea"
	elseif h < 0.39 then
		return "lake"
	elseif h > 0.68 then
		return "mountains"
	end
	local wet = 0.7 * noise(x, y, 200, 3) + 0.3 * noise(x, y, 80, 5)
	if lat > 0.78 then
		return "tundra"
	elseif lat > 0.6 then
		return "taiga"
	elseif lat > 0.35 then
		return wet > 0.45 and "forest" or "plains"
	elseif lat > 0.15 then
		return wet > 0.55 and "forest" or (wet > 0.35 and "plains" or "steppe")
	end
	return wet > 0.6 and "plains" or "desert"
end

function WorldMap.IsWater(biome)
	return biome == "sea" or biome == "lake"
end

-- The nearest land to x, y km: the place itself, or one on rings of 25 km around it.
function WorldMap.Land(x, y)
	if not WorldMap.IsWater(WorldMap.Biome(x, y)) then
		return x, y
	end
	for ring = 1, 40 do
		local r = ring * 25
		local steps = 8 * ring
		for k = 0, steps - 1 do
			local a = k / steps * 2 * math.pi
			local px = (x + math.cos(a) * r) % WorldMap.Km.width
			local py = math.min(WorldMap.Km.height, math.max(0, y + math.sin(a) * r))
			if not WorldMap.IsWater(WorldMap.Biome(px, py)) then
				return px, py
			end
		end
	end
	return x, y
end

-- The cells of the map: rows of runs { biome, from, to } (columns, from 1) of the same land, so a
-- row is drawn with few pieces.
function WorldMap.Runs()
	local w, h = WorldMap.Km.width / WorldMap.Columns, WorldMap.Km.height / WorldMap.Rows
	local rows = {}
	for r = 1, WorldMap.Rows do
		local runs = {}
		for c = 1, WorldMap.Columns do
			local biome = WorldMap.Biome((c - 0.5) * w, (r - 0.5) * h)
			local last = runs[#runs]
			if last and last.biome == biome then
				last.to = c
			else
				table.insert(runs, { biome = biome, from = c, to = c })
			end
		end
		rows[r] = runs
	end
	return rows
end

return WorldMap
