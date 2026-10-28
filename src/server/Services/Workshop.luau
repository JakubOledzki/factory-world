-- The workbench on the square, and the ones players put on their plots: all of them take orders for
-- the same queue. Finished orders are handed out whenever the player's data is
-- touched (here, on joining, and each time the workbench is opened); nothing runs in a loop.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PlotLayout = require(Shared.PlotLayout)
local Items = require(Shared.Items)
local Rules = require(Shared.Workshop)
local Research = require(Shared.Research)
local Clock = require(script.Parent.Clock)
local Data = require(script.Parent.Data)
local Grid = require(script.Parent.Grid)
local Inventory = require(script.Parent.Inventory)
local Net = require(script.Parent.Net)

local Workshop = {}

local Reach = 16
local BenchPosition = Vector3.new(PlotLayout.Workbench.x, 3, PlotLayout.Workbench.z)

-- Whether the player stands at the square's workbench or one of their own.
local function atBench(player, profile)
	if Net.Near(player, BenchPosition, Reach) then
		return true
	end
	for _, o in ipairs(profile.grid.objects) do
		if o.kind == Items.Workbench then
			local model = Grid.Model(player, o.id)
			if model and Net.Near(player, model.Top.Position, Reach) then
				return true
			end
		end
	end
	return false
end

-- Hands the finished orders to the player; true if there were any.
function Workshop.Deliver(player, profile)
	local done, waiting = Rules.Finished(profile.workshop, Clock.Now())
	if #done == 0 then
		return false
	end
	profile.workshop = waiting
	local parts = {}
	for _, order in ipairs(done) do
		Inventory.Add(profile, order.item, order.quantity)
		table.insert(parts, "+" .. order.quantity .. " " .. Items.Name(order.item))
	end
	Net.Toast(player, "Gotowe: " .. table.concat(parts, ", "))
	Net.PushState(player)
	return true
end

local function reply(profile)
	local recipes = {}
	local now = Clock.Now()
	for _, recipe in ipairs(Rules.Recipes) do
		table.insert(recipes, {
			id = recipe.id,
			quantity = recipe.quantity,
			time = recipe.time,
			ingredients = recipe.ingredients,
			locked = not Research.Unlocked(profile.research, recipe.id, now),
		})
	end
	return { ok = true, recipes = recipes, queue = profile.workshop, maxQueue = Rules.MaxQueue, serverTime = Clock.Now() }
end

function Workshop.Start()
	Data.OnLoaded(function(player, profile)
		Workshop.Deliver(player, profile)
		Net.PushState(player)
	end)

	Net.Handle("WorkshopGet", function(player, profile)
		Workshop.Deliver(player, profile)
		return reply(profile)
	end)

	Net.Handle("WorkshopOrder", function(player, profile, payload)
		Workshop.Deliver(player, profile)
		local recipe = type(payload.recipe) == "string" and Rules.Recipe(payload.recipe)
		if not recipe then
			return Net.Error("unknown_recipe")
		end
		if not atBench(player, profile) then
			return Net.Error("too_far")
		end
		if not Research.Unlocked(profile.research, recipe.id, Clock.Now()) then
			return Net.Error("not_researched")
		end
		if not Inventory.HasAll(profile, recipe.ingredients) then
			return Net.Error("not_enough_items")
		end
		local queue, code = Rules.Order(profile.workshop, recipe, Clock.Now())
		if queue == nil then
			return Net.Error(code)
		end
		for _, entry in ipairs(recipe.ingredients) do
			Inventory.TryRemove(profile, entry[1], entry[2])
		end
		profile.workshop = queue
		Net.PushState(player)
		return reply(profile)
	end)
end

return Workshop
