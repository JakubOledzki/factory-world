-- The processing machines on the build grid (Shared.Processing): the player sets a recipe, loads
-- ingredients and fuel from the inventory and takes the products out. Inserters do the same on
-- their own (Shared.Logistics). Each request works the grid out to now first (Factory.CatchUp), so
-- the window and the inserters see the same moment; the check and the change of items never yield.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PlotLayout = require(Shared.PlotLayout)
local Processing = require(Shared.Processing)
local Power = require(Shared.Power)
local Research = require(Shared.Research)
local Clock = require(script.Parent.Clock)
local Factory = require(script.Parent.Factory)
local Grid = require(script.Parent.Grid)
local Inventory = require(script.Parent.Inventory)
local Net = require(script.Parent.Net)

local Machines = {}

-- The player's machine `id` worked out until now, if they stand at it.
local function open(player, profile, payload)
	local id = Net.Int(payload.id, 1, 1e9)
	local o = id and Grid.Find(profile, id)
	if o == nil or o.machine == nil then
		return nil, "not_owner"
	end
	local model = Grid.Model(player, o.id)
	if model == nil or not Net.Near(player, model.Body.Position, PlotLayout.Reach + 4) then
		return nil, "too_far"
	end
	Factory.CatchUp(profile)
	o.machine = Processing.Advance(o.kind, o.machine, Clock.Now())
	return o
end

local function reply(profile, o)
	local now = Clock.Now()
	local machine = Processing.Machines[o.kind]
	local recipes = {}
	for _, r in ipairs(machine.recipes) do
		table.insert(recipes, {
			id = r.id,
			quantity = r.quantity,
			time = r.time,
			ingredients = r.ingredients,
			locked = not Research.Unlocked(profile.research, r.id, now),
		})
	end
	return {
		ok = true,
		id = o.id,
		kind = o.kind,
		state = o.machine,
		recipes = recipes,
		fired = machine.fired,
		-- For a machine that runs on power: { kw it draws, and its network's supply, demand and speed
		-- (nil when no pole reaches it) }.
		power = Power.Demand[o.kind] and {
			kw = Power.Demand[o.kind],
			network = Factory.NetworkInfo(profile, o),
		} or nil,
		serverTime = now,
	}
end

-- Hands `entries` (a list of { item, quantity }) to the player.
local function give(profile, entries)
	for _, entry in ipairs(entries) do
		if entry[2] > 0 then
			Inventory.Add(profile, entry[1], entry[2])
		end
	end
end

function Machines.Start()
	Net.Handle("MachineGet", function(player, profile, payload)
		local o, code = open(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		return reply(profile, o)
	end)

	Net.Handle("MachineRecipe", function(player, profile, payload)
		local o, code = open(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		local id = Net.Item(payload.recipe)
		if id == nil or Processing.Recipe(o.kind, id) == nil then
			return Net.Error("bad_recipe")
		end
		if not Research.Unlocked(profile.research, id, Clock.Now()) then
			return Net.Error("not_researched")
		end
		local after, handed = Processing.SetRecipe(o.kind, o.machine, id, Clock.Now())
		if after == nil then
			return Net.Error(handed)
		end
		o.machine = after
		give(profile, handed)
		Net.PushState(player)
		return reply(profile, o)
	end)

	Net.Handle("MachineLoad", function(player, profile, payload)
		local o, code = open(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Processing.MaxInput + Processing.MaxFuel)
		if item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		if Inventory.Count(profile, item) < quantity then
			return Net.Error("not_enough_items")
		end
		local moved = math.min(quantity, Processing.Room(o.kind, o.machine, item))
		local after, err = Processing.Load(o.kind, o.machine, item, math.max(moved, 1), Clock.Now())
		if after == nil or moved <= 0 then
			return Net.Error(err or "machine_full")
		end
		Inventory.TryRemove(profile, item, moved)
		o.machine = after
		Net.PushState(player)
		return reply(profile, o)
	end)

	Net.Handle("MachineTake", function(player, profile, payload)
		local o, code = open(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		local after, taken = Processing.Take(o.kind, o.machine, payload.what, Clock.Now())
		if after == nil then
			return Net.Error(taken)
		end
		o.machine = after
		give(profile, taken)
		Net.PushState(player)
		return reply(profile, o)
	end)
end

return Machines
