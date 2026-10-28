-- The workbench at the merchant's square, and any the player put on their plot (Crafting.cs Workshop): the player orders a recipe, the
-- ingredients are taken at once and the item is made after the recipe's time, one order after
-- another, and lands in the inventory even when the player has walked away.
local Items = require(script.Parent.Items)

local Workshop = {}

-- Orders that can wait in the queue, the one being made included.
Workshop.MaxQueue = 5

Workshop.Recipes = {
	{ id = Items.Furnace, quantity = 1, time = 45, ingredients = { { Items.Stone, 20 } } },
	{ id = Items.Nails, quantity = 5, time = 10, ingredients = { { Items.IronIngot, 1 } } },
	{ id = Items.Belt, quantity = 4, time = 10, ingredients = { { Items.IronIngot, 2 }, { Items.Wood, 1 } } },
	{ id = Items.Inserter, quantity = 1, time = 15, ingredients = { { Items.IronIngot, 2 }, { Items.CopperIngot, 1 }, { Items.Nails, 5 } } },
	{ id = Items.WoodenChest, quantity = 1, time = 10, ingredients = { { Items.Wood, 10 }, { Items.Nails, 5 } } },
	-- A workbench of the player's own, to put on the plot: it makes the same as this one.
	{ id = Items.Workbench, quantity = 1, time = 30, ingredients = { { Items.Wood, 20 }, { Items.Nails, 5 } } },
	-- Power (Shared.Power): a steam generator and poles with wires.
	{ id = Items.Generator, quantity = 1, time = 60, ingredients = { { Items.Stone, 10 }, { Items.IronIngot, 8 }, { Items.CopperIngot, 4 } } },
	{ id = Items.Pole, quantity = 2, time = 5, ingredients = { { Items.Wood, 2 }, { Items.CopperIngot, 1 } } },
	-- Machines, once researched (Research).
	{ id = Items.Sawmill, quantity = 1, time = 60, ingredients = { { Items.Wood, 30 }, { Items.IronIngot, 6 }, { Items.Nails, 10 } } },
	{ id = Items.Stonemason, quantity = 1, time = 45, ingredients = { { Items.Stone, 30 }, { Items.IronIngot, 10 }, { Items.Wood, 10 } } },
	{ id = Items.Crusher, quantity = 1, time = 60, ingredients = { { Items.IronIngot, 25 }, { Items.Stone, 30 }, { Items.CopperIngot, 8 } } },
	{ id = Items.Foundry, quantity = 1, time = 90, ingredients = { { Items.Stone, 40 }, { Items.Sand, 20 }, { Items.IronIngot, 20 }, { Items.CopperIngot, 10 } } },
	-- Farming (Shared.Farming): the hoe for fields, the mill and the bakery once researched.
	{ id = Items.Hoe, quantity = 1, time = 20, ingredients = { { Items.IronIngot, 2 }, { Items.Wood, 2 } } },
	{ id = Items.Mill, quantity = 1, time = 60, ingredients = { { Items.Stone, 30 }, { Items.Wood, 10 }, { Items.IronIngot, 2 } } },
	{ id = Items.Bakery, quantity = 1, time = 90, ingredients = { { Items.Stone, 40 }, { Items.IronIngot, 3 }, { Items.Sand, 10 } } },
}

function Workshop.Recipe(id)
	for _, recipe in ipairs(Workshop.Recipes) do
		if recipe.id == id then
			return recipe
		end
	end
	return nil
end

-- The queue with one more order of `recipe` put in at `now`, or nil and an error code.
function Workshop.Order(queue, recipe, now)
	if #queue >= Workshop.MaxQueue then
		return nil, "queue_full"
	end
	local start = now
	if #queue > 0 then
		start = math.max(now, queue[#queue].finishesAt)
	end
	local after = {}
	for i, order in ipairs(queue) do
		after[i] = order
	end
	table.insert(after, { item = recipe.id, quantity = recipe.quantity, finishesAt = start + recipe.time })
	return after
end

-- Splits the queue at `now` into the orders done (to hand out) and those still waiting.
function Workshop.Finished(queue, now)
	local done, waiting = {}, {}
	for _, order in ipairs(queue) do
		if order.finishesAt <= now then
			table.insert(done, order)
		else
			table.insert(waiting, order)
		end
	end
	return done, waiting
end

return Workshop
