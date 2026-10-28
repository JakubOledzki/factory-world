-- The workbench at the merchant's square (Crafting.cs Workshop): the player orders a recipe, the
-- ingredients are taken at once and the item is made after the recipe's time, one order after
-- another, and lands in the inventory even when the player has walked away.
local Items = require(script.Parent.Items)

local Workshop = {}

-- Orders that can wait in the queue, the one being made included.
Workshop.MaxQueue = 5

Workshop.Recipes = {
	{ id = Items.Furnace, quantity = 1, time = 45, ingredients = { { Items.Stone, 20 } } },
	{ id = Items.Nails, quantity = 5, time = 10, ingredients = { { Items.IronIngot, 1 } } },
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
