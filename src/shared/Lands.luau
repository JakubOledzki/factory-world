-- Plots a player buys besides their home plot (the meadow), one of each biome: its ground, its wild
-- trees and what its mine gives. A player has one place for a plot on the server and shows one of
-- their plots there at a time; the others wait in their data and catch up when shown again.
--
-- In the profile the plot shown is where the home plot always was (grid, furnaces, mines[1]) and
-- `active` says which one it is (nil: home). The others: `home` = { grid, furnaces, mine } while a
-- bought plot is shown, and lands[biome] = { grid, furnaces, mine } ({ shown = true } for the one
-- shown). Pure functions: the server checks and charges.
local Forestry = require(script.Parent.Forestry)
local Items = require(script.Parent.Items)
local Mining = require(script.Parent.Mining)
local PlotLayout = require(script.Parent.PlotLayout)

local Lands = {}

-- The home plot, as a "biome" for the windows.
Lands.Home = "home"
Lands.HomeName = "Łąka"

-- The biomes in the order the buying window shows them. `drops` are like Mining.Drops (chance in
-- thousandths, rarest first); `trees` how many wild trees a new plot of it has.
Lands.Order = { "forest", "desert", "mountains", "tundra" }
Lands.Biomes = {
	forest = {
		name = "Las",
		text = "Gęsty las pełen drzew. Kopalnia daje dużo węgla.",
		ground = { 70, 118, 60 },
		material = "LeafyGrass",
		trees = 60,
		drops = {
			{ Items.IronOre, 120 },
			{ Items.Coal, 650 },
			{ Items.Stone, 800 },
		},
	},
	desert = {
		name = "Pustynia",
		text = "Piasek, miedź i cyna, a czasem złoto. Drzew tu nie ma.",
		ground = { 222, 196, 132 },
		material = "Sand",
		trees = 0,
		drops = {
			{ Items.GoldOre, 10 },
			{ Items.TinOre, 200 },
			{ Items.CopperOre, 450 },
			{ Items.Sand, 900 },
		},
	},
	mountains = {
		name = "Góry",
		text = "Twarda skała z żelazem i srebrem. Kilka drzew.",
		ground = { 132, 124, 114 },
		material = "Slate",
		trees = 8,
		drops = {
			{ Items.GoldOre, 4 },
			{ Items.SilverOre, 150 },
			{ Items.Coal, 250 },
			{ Items.IronOre, 520 },
			{ Items.Stone, 990 },
		},
	},
	tundra = {
		name = "Tundra",
		text = "Śnieg i zmarzlina z cyną, srebrem i złotem. Ośnieżone świerki.",
		ground = { 226, 232, 238 },
		material = "Snow",
		trees = 16,
		snow = true,
		drops = {
			{ Items.GoldOre, 30 },
			{ Items.SilverOre, 130 },
			{ Items.TinOre, 380 },
			{ Items.Stone, 900 },
		},
	},
}

-- What the plots bought cost, in cents: the first (the player's second plot) 50 000 $, then
-- 500 000 $ and 5 000 000 $, and every one after that a billion.
Lands.Prices = { 5000000, 50000000, 500000000 }
Lands.LaterPrice = 100000000000

-- The new plot of `biome`, with its wild trees (`nextId()` gives each tree its id).
function Lands.New(biome, nextId, layout)
	local objects = {}
	for _, t in ipairs(Lands.WildTrees(biome)) do
		local tree = Forestry.New(nextId(), t.x, t.z, nil)
		tree.snow = Lands.Biomes[biome].snow
		table.insert(objects, tree)
	end
	return { grid = { objects = objects, layout = layout }, furnaces = {}, mine = Mining.New() }
end

-- Which plot the player shows: Lands.Home or a biome.
function Lands.Shown(profile)
	return profile.active or Lands.Home
end

-- The home plot's grid, shown or not (its railway station stays on it).
function Lands.HomeGrid(profile)
	if profile.active then
		return profile.home.grid
	end
	return profile.grid
end

-- Shows plot `to` (Lands.Home or a biome the player bought) in place of the one shown; true, or
-- false and an error code. Whatever was shown should be worked out up to now first.
function Lands.Switch(profile, to)
	local from = Lands.Shown(profile)
	if to == from then
		return false, "land_shown"
	end
	if to ~= Lands.Home and (type(to) ~= "string" or profile.lands[to] == nil) then
		return false, "not_owner"
	end
	local current = { grid = profile.grid, furnaces = profile.furnaces, mine = profile.mines[1] }
	if from == Lands.Home then
		profile.home = current
	else
		profile.lands[from] = current
	end
	local target
	if to == Lands.Home then
		target = profile.home
		profile.home = nil
		profile.active = nil
	else
		target = profile.lands[to]
		profile.lands[to] = { shown = true }
		profile.active = to
	end
	profile.grid, profile.furnaces, profile.mines = target.grid, target.furnaces, { target.mine }
	return true
end

-- How many plots the player bought.
function Lands.Count(lands)
	local n = 0
	for _ in pairs(lands or {}) do
		n = n + 1
	end
	return n
end

-- The price of the next plot for a player with `lands`, or nil when they have them all.
function Lands.Price(lands)
	local n = Lands.Count(lands)
	if n >= #Lands.Order then
		return nil
	end
	return Lands.Prices[n + 1] or Lands.LaterPrice
end

-- Whether a plot of `biome` can be bought by a player with `lands`; or false and an error code.
function Lands.CanBuy(lands, biome)
	if type(biome) ~= "string" or Lands.Biomes[biome] == nil then
		return false, "bad_payload"
	end
	if lands[biome] ~= nil or Lands.Price(lands) == nil then
		return false, "land_owned"
	end
	return true
end

-- The tiles of the wild trees a new plot of `biome` starts with: spread over its grid at random but
-- always the same, off the mine and the way in from where the player appears.
function Lands.WildTrees(biome)
	local info = Lands.Biomes[biome]
	local g = PlotLayout.Grid
	local sx, sz = PlotLayout.TileAt(PlotLayout.Spawn.x, PlotLayout.Spawn.z)
	local state = 7919 + #biome * 104729 + string.byte(biome) * 31
	local function random(n)
		state = (state * 16807) % 2147483647
		return state % n
	end
	local out, taken = {}, {}
	local tries = 0
	while #out < info.trees and tries < info.trees * 20 do
		tries = tries + 1
		local x, z = random(g.width), random(g.depth)
		local free = not PlotLayout.Blocked(x, z) and (math.abs(x - sx) > 3 or math.abs(z - sz) > 3)
		-- A tile apart from the others, so the trees do not stand trunk to trunk.
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
	return out
end

return Lands
