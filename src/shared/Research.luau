-- The technology tree (Research.cs TechTree on main), the part that fits this stage: each
-- technology unlocks machines the player may then make at the workbench and buy. Research uses up
-- its cost at once and takes time, one technology at a time, and goes on while the player is away.
-- Belts, inserters and chests came before research did and stay unlocked.
--
-- A player's research is saved as { [technology id] = { startsAt, finishesAt } }.
local Items = require(script.Parent.Items)

local Research = {}

-- Ids are saved in player data: never rename one (the same as on main).
Research.Technologies = {
	{
		id = "forestry_industry",
		name = "Gospodarka leśna",
		description = "Tartak tnie drewno na deski, belki i pellet.",
		requires = {},
		cost = { { Items.Sapling, 20 }, { Items.Wood, 50 } },
		time = 90,
		unlocks = { Items.Sawmill, Items.Planks, Items.Beams, Items.WoodPellets },
	},
	{
		id = "stonemasonry",
		name = "Kamieniarstwo",
		description = "Warsztat kamieniarski ciosa z kamienia bloki.",
		requires = {},
		cost = { { Items.Stone, 100 }, { Items.IronIngot, 10 } },
		time = 90,
		unlocks = { Items.Stonemason, Items.StoneBlocks },
	},
	{
		-- On main it follows mining automation, which this game does not have yet.
		id = "crushing",
		name = "Kruszenie",
		description = "Kruszarka mieli kamień na piasek, a rudę na kruszywo, z którego wytopisz więcej sztabek.",
		requires = {},
		cost = { { Items.Stone, 100 }, { Items.IronIngot, 30 } },
		time = 180,
		unlocks = { Items.Crusher, Items.Sand, Items.CrushedIronOre, Items.CrushedCopperOre, Items.CrushedTinOre },
	},
	{
		id = "metallurgy",
		name = "Metalurgia",
		description = "Odlewnia stapia brąz i stal i wypala cegły.",
		requires = {},
		cost = { { Items.CopperIngot, 30 }, { Items.TinIngot, 10 }, { Items.IronIngot, 30 }, { Items.Coal, 30 } },
		time = 180,
		unlocks = { Items.Foundry, Items.BronzeIngot, Items.SteelIngot, Items.Bricks },
	},
}

Research.ById = {}
for _, t in ipairs(Research.Technologies) do
	Research.ById[t.id] = t
end

-- The technology that unlocks `item`, if research locks it.
local lockedBy = {}
for _, t in ipairs(Research.Technologies) do
	for _, item in ipairs(t.unlocks) do
		lockedBy[item] = t.id
	end
end

function Research.IsDone(research, id, now)
	local r = research[id]
	return r ~= nil and r.finishesAt <= now
end

-- The technology being researched at `now`, if any.
function Research.Active(research, now)
	for id, r in pairs(research) do
		if r.finishesAt > now then
			return id
		end
	end
	return nil
end

-- "done", "active", "available" or "locked" (its requirements are not done).
function Research.Status(research, id, now)
	if Research.IsDone(research, id, now) then
		return "done"
	elseif research[id] then
		return "active"
	end
	for _, need in ipairs(Research.ById[id].requires) do
		if not Research.IsDone(research, need, now) then
			return "locked"
		end
	end
	return "available"
end

-- Whether the player may make or buy `item`.
function Research.Unlocked(research, item, now)
	local id = lockedBy[item]
	return id == nil or Research.IsDone(research, id, now)
end

-- Research with technology `id` started at `now`, or nil and an error code. The cost is taken by
-- the caller in the same step.
function Research.Start(research, id, now)
	local t = Research.ById[id]
	if t == nil then
		return nil, "bad_payload"
	end
	local status = Research.Status(research, id, now)
	if status == "done" or status == "active" then
		return nil, "research_done"
	elseif status == "locked" then
		return nil, "research_locked"
	elseif Research.Active(research, now) then
		return nil, "research_busy"
	end
	local after = {}
	for k, v in pairs(research) do
		after[k] = v
	end
	after[id] = { startsAt = now, finishesAt = now + t.time }
	return after
end

return Research
