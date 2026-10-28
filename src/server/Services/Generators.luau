-- The generators on the build grid (Shared.Power): the player loads fuel from the inventory, takes
-- back what is not burning yet and sees how the generator's network is doing. Inserters can bring
-- fuel too (Shared.Logistics). Each request works the grid out to now first (Factory.CatchUp); the
-- check and the change of items never yield.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local PlotLayout = require(Shared.PlotLayout)
local Power = require(Shared.Power)
local Clock = require(script.Parent.Clock)
local Factory = require(script.Parent.Factory)
local Grid = require(script.Parent.Grid)
local Inventory = require(script.Parent.Inventory)
local Net = require(script.Parent.Net)

local Generators = {}

-- The player's generator `id` worked out until now, if they stand at it.
local function open(player, profile, payload)
	local id = Net.Int(payload.id, 1, 1e9)
	local o = id and Grid.Find(profile, id)
	if o == nil or o.kind ~= Items.Generator then
		return nil, "not_owner"
	end
	local model = Grid.Model(player, o.id)
	if model == nil or not Net.Near(player, model.Body.Position, PlotLayout.Reach + 4) then
		return nil, "too_far"
	end
	Factory.CatchUp(profile)
	return o
end

local function reply(profile, o)
	local fuels = {}
	for _, item in ipairs({ Items.Coal, Items.Wood, Items.WoodPellets }) do
		table.insert(fuels, { id = item, kj = Power.Fuels[item] })
	end
	return {
		ok = true,
		id = o.id,
		generator = o.generator,
		fuels = fuels,
		maxFuel = Power.MaxFuel,
		kw = Power.GeneratorKw,
		network = Factory.NetworkInfo(profile, o),
		serverTime = Clock.Now(),
	}
end

function Generators.Start()
	Net.Handle("GeneratorGet", function(player, profile, payload)
		local o, code = open(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		return reply(profile, o)
	end)

	Net.Handle("GeneratorLoad", function(player, profile, payload)
		local o, code = open(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Power.MaxFuel)
		if item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		local moved = math.min(quantity, Inventory.Count(profile, item), Power.Room(o.generator, item))
		local after, err = Power.Load(o.generator, item, math.max(moved, 1))
		if after == nil then
			return Net.Error(err)
		end
		if moved <= 0 then
			return Net.Error("not_enough_items")
		end
		Inventory.TryRemove(profile, item, moved)
		o.generator = after
		Factory.Changed(profile)
		Net.PushState(player)
		return reply(profile, o)
	end)

	-- Takes back the fuel not burning yet; the piece in the fire burns on.
	Net.Handle("GeneratorTake", function(player, profile, payload)
		local o, code = open(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		local g = o.generator
		if g.fuelItem == nil or g.fuel <= 0 then
			return Net.Error("generator_empty")
		end
		Inventory.Add(profile, g.fuelItem, g.fuel)
		o.generator = { fuelItem = nil, fuel = 0, energy = g.energy }
		Factory.Changed(profile)
		Net.PushState(player)
		return reply(profile, o)
	end)
end

return Generators
