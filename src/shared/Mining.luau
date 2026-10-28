-- Mines on a plot (WorldModule Mining.cs, level 1): a player with a pickaxe works a mine for
-- 5 s and gets up to two ores. A mine gives 50 loads in a row; 10 minutes after the last one
-- it is full again. Pure functions: the server passes the time and the random rolls in.
local Items = require(script.Parent.Items)

local Mining = {}

-- Seconds one load takes with a pickaxe.
Mining.Time = 5

-- Loads a full mine gives before it runs dry.
Mining.Units = 50

-- Seconds a dry mine takes to fill up again, counted from its last load.
Mining.Refill = 10 * 60

-- A load holds at most this many ores; when more drop, the rarest are kept.
Mining.MaxOres = 2

-- Each ore drops on its own roll (0-999) with this chance in thousandths; rarest first.
Mining.Drops = {
	{ Items.GoldOre, 1 },
	{ Items.SilverOre, 50 },
	{ Items.TinOre, 100 },
	{ Items.CopperOre, 200 },
	{ Items.IronOre, 200 },
	{ Items.Coal, 350 },
	{ Items.Stone, 990 },
}

-- What one load gives for one roll per entry of Mining.Drops: a list of { item, quantity }.
function Mining.Load(rolls)
	local items = {}
	for i, drop in ipairs(Mining.Drops) do
		if #items < Mining.MaxOres and rolls[i] < drop[2] then
			table.insert(items, { drop[1], 1 })
		end
	end
	return items
end

-- Rolls for Mining.Load from a Random object (the server's own).
function Mining.Roll(random)
	local rolls = {}
	for i = 1, #Mining.Drops do
		rolls[i] = random:NextInteger(0, 999)
	end
	return rolls
end

function Mining.New()
	return { units = Mining.Units, refillAt = nil }
end

-- The mine as it is at `now` (seconds): a dry one fills up again once its time has come.
function Mining.Refresh(mine, now)
	if mine.refillAt ~= nil and now >= mine.refillAt then
		return { units = Mining.Units, refillAt = nil }
	end
	return mine
end

-- The mine after one load taken at `now`, or nil and an error code when it is dry.
function Mining.Work(mine, now)
	mine = Mining.Refresh(mine, now)
	if mine.units <= 0 then
		return nil, "mine_empty"
	end
	local units = mine.units - 1
	return { units = units, refillAt = units == 0 and now + Mining.Refill or nil }
end

return Mining
