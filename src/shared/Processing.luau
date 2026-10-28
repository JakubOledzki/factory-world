-- Processing machines on the build grid (Crafting Processing.cs on main): a sawmill, a stonemason's
-- workshop, a crusher, a foundry, and for food a mill and a bakery. The player sets a recipe and loads its ingredients (and fuel,
-- where the machine burns it); the machine makes one batch after another while the player is away
-- too, and the products wait in it until taken out, by hand or by an inserter. Nothing runs in a
-- loop: the state is worked out from `startedAt` whenever someone looks (Processing.Advance).
--
-- A machine's state is { recipe, inputs = { quantity of each ingredient, in the recipe's order },
-- fuelItem, fuel, heat (batches left from fuel already burning), output, startedAt }.
local Items = require(script.Parent.Items)

local Processing = {}

-- Of each ingredient, and of fuel.
Processing.MaxInput = 50
Processing.MaxFuel = 50

-- A full machine stops until its products are taken out.
Processing.MaxOutput = 100

-- What a fired machine burns, and how many batches one piece lasts.
Processing.Fuels = {
	[Items.Coal] = 4,
	[Items.Wood] = 1,
	[Items.WoodPellets] = 2,
}

local function recipe(id, quantity, time, ingredients)
	return { id = id, quantity = quantity, time = time, ingredients = ingredients }
end

-- [kind] = { fired, recipes }. A recipe's id is the item it makes.
-- The crusher runs on power, as on main (Shared.Power sets its speed).
Processing.Machines = {
	[Items.Sawmill] = {
		fired = false,
		recipes = {
			recipe(Items.Planks, 2, 8, { { Items.Wood, 1 } }),
			recipe(Items.Beams, 1, 10, { { Items.Wood, 2 } }),
			recipe(Items.WoodPellets, 3, 8, { { Items.Wood, 2 } }),
		},
	},
	[Items.Stonemason] = {
		fired = false,
		recipes = {
			recipe(Items.StoneBlocks, 1, 8, { { Items.Stone, 3 } }),
		},
	},
	[Items.Crusher] = {
		fired = false,
		recipes = {
			recipe(Items.Sand, 3, 3, { { Items.Stone, 1 } }),
			recipe(Items.CrushedIronOre, 3, 5, { { Items.IronOre, 2 } }),
			recipe(Items.CrushedCopperOre, 3, 5, { { Items.CopperOre, 2 } }),
			recipe(Items.CrushedTinOre, 3, 6, { { Items.TinOre, 2 } }),
		},
	},
	[Items.Foundry] = {
		fired = true,
		recipes = {
			recipe(Items.BronzeIngot, 4, 12, { { Items.CopperIngot, 3 }, { Items.TinIngot, 1 } }),
			recipe(Items.SteelIngot, 1, 15, { { Items.IronIngot, 2 }, { Items.Coal, 1 } }),
			recipe(Items.Bricks, 4, 10, { { Items.Sand, 2 }, { Items.Stone, 2 } }),
		},
	},
	-- The mill runs on power, the bakery burns fuel, as on main.
	[Items.Mill] = {
		fired = false,
		recipes = {
			recipe(Items.Flour, 1, 6, { { Items.Wheat, 2 } }),
			recipe(Items.CornFlour, 1, 6, { { Items.Corn, 2 } }),
		},
	},
	[Items.Bakery] = {
		fired = true,
		recipes = {
			recipe(Items.Bread, 1, 20, { { Items.Flour, 2 } }),
			recipe(Items.CornBread, 1, 20, { { Items.CornFlour, 2 } }),
		},
	},
}

-- The order machines are listed in.
Processing.Kinds = { Items.Sawmill, Items.Stonemason, Items.Crusher, Items.Foundry, Items.Mill, Items.Bakery }

function Processing.IsMachine(kind)
	return Processing.Machines[kind] ~= nil
end

function Processing.Recipe(kind, id)
	local machine = Processing.Machines[kind]
	if machine == nil or id == nil then
		return nil
	end
	for _, r in ipairs(machine.recipes) do
		if r.id == id then
			return r
		end
	end
	return nil
end

function Processing.Empty()
	return { recipe = nil, inputs = {}, fuelItem = nil, fuel = 0, heat = 0, output = 0, startedAt = nil }
end

local function copy(s)
	local inputs = {}
	for i, n in ipairs(s.inputs) do
		inputs[i] = n
	end
	return {
		recipe = s.recipe,
		inputs = inputs,
		fuelItem = s.fuelItem,
		fuel = s.fuel,
		heat = s.heat,
		output = s.output,
		startedAt = s.startedAt,
		speed = s.speed,
		frozen = s.frozen,
	}
end

-- How fast the machine works: 1 normally, less on a network short of power, 0 without power
-- (Shared.Power). A batch takes the recipe's time divided by it; while it is 0 the batch keeps how
-- far it got in `frozen` (0 to 1) and `startedAt` means nothing.
local function speedOf(s)
	return s.speed or 1
end

local function input(s, i)
	return s.inputs[i] or 0
end

local function fuelBatches(item)
	return item and Processing.Fuels[item] or 0
end

-- Batches the machine can still make from what it holds, ignoring time.
function Processing.Batches(kind, s)
	local r = Processing.Recipe(kind, s.recipe)
	if r == nil then
		return 0
	end
	local n = math.floor((Processing.MaxOutput - s.output) / r.quantity)
	for i, ingredient in ipairs(r.ingredients) do
		n = math.min(n, math.floor(input(s, i) / ingredient[2]))
	end
	if Processing.Machines[kind].fired then
		n = math.min(n, s.heat + s.fuel * fuelBatches(s.fuelItem))
	end
	return math.max(0, n)
end

-- What the machine holds after working until `now` (seconds).
function Processing.Advance(kind, s, now)
	local r = Processing.Recipe(kind, s.recipe)
	local after = copy(s)
	if s.startedAt == nil or r == nil then
		after.startedAt = nil
		after.frozen = nil
		return after
	end
	if speedOf(s) <= 0 then
		return after
	end
	local span = r.time / speedOf(s)
	local possible = math.max(0, math.floor((now - s.startedAt) / span + 1e-9))
	local n = math.min(possible, Processing.Batches(kind, s))
	for i, ingredient in ipairs(r.ingredients) do
		after.inputs[i] = input(s, i) - n * ingredient[2]
	end
	after.output = s.output + n * r.quantity
	if Processing.Machines[kind].fired then
		local perFuel = fuelBatches(s.fuelItem)
		local burnt = 0
		if n > s.heat then
			burnt = math.floor((n - s.heat + perFuel - 1) / perFuel)
		end
		after.fuel = s.fuel - burnt
		after.heat = s.heat + burnt * perFuel - n
		if after.fuel == 0 then
			after.fuelItem = nil
		end
	end
	if Processing.Batches(kind, after) > 0 then
		after.startedAt = s.startedAt + span * n
	else
		after.startedAt = nil
	end
	return after
end

-- The machine working at `speed` from `now` on, the batch keeping how far it got.
function Processing.SetSpeed(kind, s, speed, now)
	if speedOf(s) == speed then
		return s
	end
	local r = Processing.Recipe(kind, s.recipe)
	local after = Processing.Advance(kind, s, now)
	if after.startedAt and r then
		local progress = Processing.Progress(kind, after, now)
		if speed <= 0 then
			after.frozen = progress
		else
			after.startedAt = now - progress * r.time / speed
			after.frozen = nil
		end
	end
	after.speed = speed
	return after
end

-- How far the batch being made has got at `now`, from 0 to 1 (0 when none is).
function Processing.Progress(kind, s, now)
	local r = Processing.Recipe(kind, s.recipe)
	if s.startedAt == nil or r == nil then
		return 0
	end
	if speedOf(s) <= 0 then
		return s.frozen or 0
	end
	return math.max(0, math.min(1, (now - s.startedAt) * speedOf(s) / r.time))
end

-- Whether the machine is making something at `now` (not idle, not stopped for lack of power).
function Processing.Working(kind, s, now)
	return Processing.Advance(kind, s, now).startedAt ~= nil and speedOf(s) > 0
end

-- Starts an idle machine that has everything for a batch.
function Processing.Start(kind, s, now)
	if s.startedAt == nil and Processing.Batches(kind, s) > 0 then
		local after = copy(s)
		after.startedAt = now
		if speedOf(s) <= 0 then
			after.frozen = 0
		end
		return after
	end
	return s
end

-- When the batch being made now is done, if one is.
function Processing.NextChange(kind, s)
	local r = Processing.Recipe(kind, s.recipe)
	if s.startedAt and r and speedOf(s) > 0 then
		return s.startedAt + r.time / speedOf(s)
	end
	return nil
end

-- What the machine holds that can be handed back, as a list of { item, quantity }: ingredients,
-- fuel and products.
function Processing.Contents(kind, s)
	local out = {}
	local r = Processing.Recipe(kind, s.recipe)
	if r then
		for i, ingredient in ipairs(r.ingredients) do
			if input(s, i) > 0 then
				table.insert(out, { ingredient[1], input(s, i) })
			end
		end
		if s.output > 0 then
			table.insert(out, { r.id, s.output })
		end
	end
	if s.fuel > 0 and s.fuelItem then
		table.insert(out, { s.fuelItem, s.fuel })
	end
	return out
end

-- The machine with recipe `id` set at `now` (already advanced), and what it handed back of the
-- recipe before (its ingredients and products; the fuel stays); or nil and an error code.
function Processing.SetRecipe(kind, s, id, now)
	local r = Processing.Recipe(kind, id)
	if r == nil then
		return nil, "bad_recipe"
	end
	if s.recipe == id then
		return s, {}
	end
	local handed = {}
	local old = Processing.Recipe(kind, s.recipe)
	if old then
		for i, ingredient in ipairs(old.ingredients) do
			if input(s, i) > 0 then
				table.insert(handed, { ingredient[1], input(s, i) })
			end
		end
		if s.output > 0 then
			table.insert(handed, { old.id, s.output })
		end
	end
	local after = copy(s)
	after.recipe = id
	after.inputs = {}
	after.output = 0
	after.startedAt = nil
	return Processing.Start(kind, after, now), handed
end

-- Whether `item` can go by the fire now.
function Processing.FireTakes(kind, s, item)
	return Processing.Machines[kind].fired
		and Processing.Fuels[item] ~= nil
		and (s.fuelItem == nil or s.fuelItem == item or s.fuel == 0)
		and s.fuel < Processing.MaxFuel
end

-- The ingredient slot of the recipe that takes `item`, or nil.
local function slotOf(kind, s, item)
	local r = Processing.Recipe(kind, s.recipe)
	if r == nil then
		return nil
	end
	for i, ingredient in ipairs(r.ingredients) do
		if ingredient[1] == item then
			return i
		end
	end
	return nil
end

-- Whether `item` that is both fuel and an ingredient (coal for steel) goes by the fire: while the
-- fire lasts for fewer batches than the ingredient, so neither runs out first.
local function toFire(kind, s, item)
	if not Processing.FireTakes(kind, s, item) then
		return false
	end
	local slot = slotOf(kind, s, item)
	if slot == nil or input(s, slot) >= Processing.MaxInput then
		return true
	end
	local r = Processing.Recipe(kind, s.recipe)
	local item0 = s.fuel > 0 and s.fuelItem or item
	local fire = s.heat + s.fuel * fuelBatches(item0)
	return fire < math.floor(input(s, slot) / r.ingredients[slot][2])
end

-- How many of `item` the machine takes now.
function Processing.Room(kind, s, item)
	local slot = slotOf(kind, s, item)
	local room = 0
	if slot then
		room = Processing.MaxInput - input(s, slot)
	end
	if Processing.FireTakes(kind, s, item) then
		room = room + Processing.MaxFuel - s.fuel
	end
	return math.max(0, room)
end

-- The machine after `quantity` of `item` is put in at `now` (already advanced), or nil and an
-- error code. Fuel that is also an ingredient is shared between the two.
function Processing.Load(kind, s, item, quantity, now)
	if Processing.Room(kind, s, item) < quantity then
		if slotOf(kind, s, item) == nil and not Processing.FireTakes(kind, s, item) then
			return nil, "machine_wrong_item"
		end
		return nil, "machine_full"
	end
	local after = copy(s)
	local slot = slotOf(kind, s, item)
	for _ = 1, quantity do
		if toFire(kind, after, item) then
			after.fuelItem = item
			after.fuel = after.fuel + 1
		else
			after.inputs[slot] = input(after, slot) + 1
		end
	end
	-- Ingredient slots before `slot` hold 0, not nil, so the list stays a list.
	local r = Processing.Recipe(kind, after.recipe)
	if r then
		for i = 1, #r.ingredients do
			after.inputs[i] = input(after, i)
		end
	end
	return Processing.Start(kind, after, now)
end

-- The machine after its products ("output"), ingredients ("input") or fuel ("fuel") are taken out
-- at `now` (already advanced), and what was taken (a list of { item, quantity }); or nil and an
-- error code. A machine that stood full starts again once its products are out.
function Processing.Take(kind, s, what, now)
	local after = copy(s)
	local taken = {}
	local r = Processing.Recipe(kind, s.recipe)
	if what == "output" then
		if r and s.output > 0 then
			table.insert(taken, { r.id, s.output })
			after.output = 0
		end
	elseif what == "input" then
		if r then
			for i, ingredient in ipairs(r.ingredients) do
				if input(s, i) > 0 then
					table.insert(taken, { ingredient[1], input(s, i) })
				end
				after.inputs[i] = 0
			end
			after.startedAt = nil
		end
	elseif what == "fuel" then
		if s.fuel > 0 and s.fuelItem then
			table.insert(taken, { s.fuelItem, s.fuel })
			after.fuel = 0
			after.fuelItem = nil
			if s.heat == 0 then
				after.startedAt = nil
			end
		end
	else
		return nil, "bad_payload"
	end
	return Processing.Start(kind, after, now), taken
end

return Processing
