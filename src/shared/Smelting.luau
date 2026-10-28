-- The stone furnace (Crafting Furnace.cs): it burns coal and smelts the ore put into it, one piece
-- after another, while the player is away too. One coal lasts for SmeltsPerCoal smelts. It holds
-- one kind of ore at a time; ingots wait in it until taken out. Nothing runs in a loop: the state
-- is worked out from `startedAt` whenever someone looks at the furnace (Smelting.Advance).
local Items = require(script.Parent.Items)

local Smelting = {}

Smelting.MaxInput = 50
Smelting.MaxFuel = 50
Smelting.SmeltsPerCoal = 5

-- Ore -> ingot and seconds per piece.
Smelting.Recipes = {
	[Items.IronOre] = { output = Items.IronIngot, time = 10 },
	[Items.CopperOre] = { output = Items.CopperIngot, time = 10 },
	[Items.TinOre] = { output = Items.TinIngot, time = 10 },
	[Items.SilverOre] = { output = Items.SilverIngot, time = 15 },
	[Items.GoldOre] = { output = Items.GoldIngot, time = 20 },
	-- Crushed ore smelts quicker; a crusher makes three of it from two ores.
	[Items.CrushedIronOre] = { output = Items.IronIngot, time = 8 },
	[Items.CrushedCopperOre] = { output = Items.CopperIngot, time = 8 },
	[Items.CrushedTinOre] = { output = Items.TinIngot, time = 8 },
}

function Smelting.Empty()
	return { input = nil, inputQuantity = 0, fuel = 0, heat = 0, output = nil, outputQuantity = 0, startedAt = nil }
end

local function copy(s)
	return {
		input = s.input,
		inputQuantity = s.inputQuantity,
		fuel = s.fuel,
		heat = s.heat,
		output = s.output,
		outputQuantity = s.outputQuantity,
		startedAt = s.startedAt,
	}
end

-- What the furnace holds after smelting until `now` (seconds).
function Smelting.Advance(s, now)
	local recipe = s.input and Smelting.Recipes[s.input]
	if s.startedAt == nil or recipe == nil then
		local after = copy(s)
		after.startedAt = nil
		return after
	end

	local perCoal = Smelting.SmeltsPerCoal
	local possible = math.max(0, math.floor((now - s.startedAt) / recipe.time))
	local n = math.min(possible, s.inputQuantity, s.heat + s.fuel * perCoal)
	local coal = 0
	if n > s.heat then
		coal = math.floor((n - s.heat + perCoal - 1) / perCoal)
	end

	local after = copy(s)
	after.inputQuantity = s.inputQuantity - n
	after.fuel = s.fuel - coal
	after.heat = s.heat + coal * perCoal - n
	if n > 0 then
		after.output = recipe.output
	end
	after.outputQuantity = s.outputQuantity + n
	if after.inputQuantity == 0 then
		after.input = nil
	end
	if after.inputQuantity > 0 and after.heat + after.fuel > 0 then
		after.startedAt = s.startedAt + recipe.time * n
	else
		after.startedAt = nil
	end
	return after
end

-- Lights an idle furnace that has both ore and coal.
function Smelting.Start(s, now)
	if s.startedAt == nil and s.inputQuantity > 0 and s.heat + s.fuel > 0 then
		local after = copy(s)
		after.startedAt = now
		return after
	end
	return s
end

-- The furnace after `quantity` of `item` is put in at `now` (already advanced), and the ingots
-- of another ore handed back first (a list of { item, quantity }); or nil and an error code.
function Smelting.Load(s, item, quantity, now)
	local after = copy(s)
	local handed = {}
	if item == Items.Coal then
		if s.fuel + quantity > Smelting.MaxFuel then
			return nil, "furnace_full"
		end
		after.fuel = s.fuel + quantity
	elseif Smelting.Recipes[item] then
		if s.input ~= nil and s.input ~= item then
			return nil, "furnace_busy"
		end
		if s.inputQuantity + quantity > Smelting.MaxInput then
			return nil, "furnace_full"
		end
		if s.output ~= nil and s.output ~= Smelting.Recipes[item].output and s.outputQuantity > 0 then
			table.insert(handed, { s.output, s.outputQuantity })
			after.output = nil
			after.outputQuantity = 0
		end
		after.input = item
		after.inputQuantity = s.inputQuantity + quantity
	else
		return nil, "not_smeltable"
	end
	return Smelting.Start(after, now), handed
end

-- The furnace after the ingots ("output"), the ore ("input") or the coal ("fuel") are taken out,
-- and what was taken (a list of { item, quantity }); or nil and an error code.
function Smelting.Take(s, what)
	local after = copy(s)
	local taken = {}
	if what == "output" then
		if s.output ~= nil and s.outputQuantity > 0 then
			table.insert(taken, { s.output, s.outputQuantity })
			after.output = nil
			after.outputQuantity = 0
		end
	elseif what == "input" then
		if s.input ~= nil then
			table.insert(taken, { s.input, s.inputQuantity })
			after.input = nil
			after.inputQuantity = 0
			after.startedAt = nil
		end
	elseif what == "fuel" then
		if s.fuel > 0 then
			table.insert(taken, { Items.Coal, s.fuel })
			after.fuel = 0
			-- The piece in the fire keeps burning on the coal already lit, if there is any.
			if s.heat == 0 then
				after.startedAt = nil
			end
		end
	else
		return nil, "bad_payload"
	end
	return after, taken
end

return Smelting
