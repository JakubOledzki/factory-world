-- Trees on a plot: a player with an axe cuts a tree for 5 s and gets one wood (a pine, Forestry.cs).
-- A cut tree grows back after Forestry.Regrow seconds.
local Items = require(script.Parent.Items)

local Forestry = {}

Forestry.ChopTime = 5

Forestry.Regrow = 3 * 60

Forestry.Yield = { { Items.Wood, 1 } }

-- Whether the tree cut at `cutAt` (nil if never) stands again at `now`.
function Forestry.Standing(cutAt, now)
	return cutAt == nil or now >= cutAt + Forestry.Regrow
end

return Forestry
