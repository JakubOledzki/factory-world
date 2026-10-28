-- Trees on a plot, as in the 2D game (Forestry.cs): a tree stands on a tile of the build grid; a
-- player with an axe cuts it for ChopTime seconds and gets one wood and, now and then, a sapling,
-- and the tile is free again. A sapling (bought from the merchant or dropped) is planted on a free
-- tile and grows into a tree in Grow seconds. A new plot starts with wild, grown trees.
local Items = require(script.Parent.Items)

local Forestry = {}

-- The kind of a tree on the grid (it is not an item: it is cut, not picked up).
Forestry.Tree = "tree"

Forestry.ChopTime = 5

Forestry.Grow = 10 * 60

-- Chance (percent) that a cut tree drops a sapling.
Forestry.SaplingChance = 30

-- A tree planted at `now`, or a wild one already grown (`now` nil), with its corner on (x, z).
function Forestry.New(id, x, z, now)
	return { id = id, kind = Forestry.Tree, x = x, z = z, rot = 0, plantedAt = now }
end

-- Whether a tree can be cut at `now`.
function Forestry.Grown(tree, now)
	return tree.plantedAt == nil or now >= tree.plantedAt + Forestry.Grow
end

-- What cutting a tree gives, with `roll` a whole number from 0 to 99 the server drew.
function Forestry.Cut(roll)
	local out = { { Items.Wood, 1 } }
	if roll < Forestry.SaplingChance then
		table.insert(out, { Items.Sapling, 1 })
	end
	return out
end

return Forestry
