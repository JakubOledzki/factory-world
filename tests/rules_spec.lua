-- Tests of the pure game rules in src/shared, run outside Roblox by tests/run.js (Lua 5.3 via fengari).
-- `load_shared(name)` loads src/shared/<name>.luau; `test(name, fn)` and `eq(a, b)` come from the runner.
local Items = load_shared("Items")
local Prices = load_shared("Prices")
local Mining = load_shared("Mining")
local Forestry = load_shared("Forestry")
local Smelting = load_shared("Smelting")
local Workshop = load_shared("Workshop")
local Money = load_shared("Money")

test("The merchant pays less than it takes for every item it both sells and buys", function()
	for item, sells in pairs(Prices.Sells) do
		if Prices.Buys[item] then
			assert(Prices.Buys[item] < sells, item)
		end
	end
end)

test("Every item in the game has a name, a colour and a place in the order", function()
	local ordered = {}
	for _, id in ipairs(Items.Order) do
		ordered[id] = true
	end
	for id in pairs(Items.Names) do
		assert(Items.Colors[id], "colour of " .. id)
		assert(ordered[id], "order of " .. id)
	end
	for id in pairs(Prices.Sells) do assert(Items.Names[id], id) end
	for id in pairs(Prices.Buys) do assert(Items.Names[id], id) end
	for ore, r in pairs(Smelting.Recipes) do
		assert(Items.Names[ore] and Items.Names[r.output], ore)
	end
	for _, r in ipairs(Workshop.Recipes) do
		assert(Items.Names[r.id], r.id)
	end
end)

test("A mining load keeps at most the two rarest ores that dropped", function()
	local all = {}
	for i = 1, #Mining.Drops do all[i] = 0 end
	local load = Mining.Load(all)
	eq(#load, 2)
	eq(load[1][1], Items.GoldOre)
	eq(load[2][1], Items.SilverOre)

	local none = {}
	for i = 1, #Mining.Drops do none[i] = 999 end
	eq(#Mining.Load(none), 0)

	local stone = {}
	for i = 1, #Mining.Drops do stone[i] = 995 end
	stone[#Mining.Drops] = 10
	eq(Mining.Load(stone)[1][1], Items.Stone)
end)

test("A mine runs dry after its loads and fills up again ten minutes after the last one", function()
	local mine = Mining.New()
	for i = 1, Mining.Units do
		mine = assert(Mining.Work(mine, 1000 + i))
	end
	eq(mine.units, 0)
	eq(mine.refillAt, 1000 + Mining.Units + Mining.Refill)
	local dry, code = Mining.Work(mine, 1000 + Mining.Units + 1)
	eq(dry, nil)
	eq(code, "mine_empty")
	local again = assert(Mining.Work(mine, mine.refillAt))
	eq(again.units, Mining.Units - 1)
end)

test("A cut tree stands again after it regrows", function()
	eq(Forestry.Standing(nil, 0), true)
	eq(Forestry.Standing(100, 100 + Forestry.Regrow - 1), false)
	eq(Forestry.Standing(100, 100 + Forestry.Regrow), true)
end)

test("The furnace smelts while the player is away and stops when the coal runs out", function()
	local s = Smelting.Empty()
	s = assert(Smelting.Load(s, Items.IronOre, 10, 0))
	eq(s.startedAt, nil)
	s = assert(Smelting.Load(s, Items.Coal, 1, 0))
	eq(s.startedAt, 0)

	local mid = Smelting.Advance(s, 25)
	eq(mid.outputQuantity, 2)
	eq(mid.startedAt, 20)
	eq(mid.fuel, 0)
	eq(mid.heat, 3)

	local later = Smelting.Advance(s, 1000)
	eq(later.outputQuantity, Smelting.SmeltsPerCoal)
	eq(later.inputQuantity, 10 - Smelting.SmeltsPerCoal)
	eq(later.startedAt, nil)
	eq(later.output, Items.IronIngot)

	-- Coal put in later lights it from that moment, not from when it went cold.
	local relit = assert(Smelting.Load(later, Items.Coal, 1, 2000))
	eq(relit.startedAt, 2000)
	local done = Smelting.Advance(relit, 2000 + 10 * 5)
	eq(done.outputQuantity, 10)
	eq(done.input, nil)
	eq(done.heat, 0)
end)

test("Advancing in steps gives the same furnace as advancing at once", function()
	local s = assert(Smelting.Load(Smelting.Empty(), Items.SilverOre, 17, 0))
	s = assert(Smelting.Load(s, Items.Coal, 3, 0))
	local stepped = s
	for t = 7, 400, 7 do
		stepped = Smelting.Advance(stepped, t)
	end
	local once = Smelting.Advance(s, 399)
	for _, k in ipairs({ "inputQuantity", "fuel", "heat", "outputQuantity" }) do
		eq(stepped[k], once[k], k)
	end
end)

test("The furnace holds one ore at a time and hands back ingots of another", function()
	local s = assert(Smelting.Load(Smelting.Empty(), Items.IronOre, 5, 0))
	local busy, code = Smelting.Load(s, Items.CopperOre, 1, 0)
	eq(busy, nil)
	eq(code, "furnace_busy")
	local _, wrong = Smelting.Load(s, Items.Wood, 1, 0)
	eq(wrong, "not_smeltable")
	local _, full = Smelting.Load(s, Items.IronOre, Smelting.MaxInput, 0)
	eq(full, "furnace_full")

	s = assert(Smelting.Load(s, Items.Coal, 1, 0))
	s = Smelting.Advance(s, 1000)
	eq(s.input, nil)
	local copper, handed = Smelting.Load(s, Items.CopperOre, 2, 1000)
	eq(handed[1][1], Items.IronIngot)
	eq(handed[1][2], 5)
	eq(copper.outputQuantity, 0)
end)

test("Taking coal out keeps the piece in the fire burning on the heat left", function()
	local s = assert(Smelting.Load(Smelting.Empty(), Items.IronOre, 5, 0))
	s = assert(Smelting.Load(s, Items.Coal, 2, 0))
	s = Smelting.Advance(s, 10)
	local after, taken = Smelting.Take(s, "fuel")
	eq(taken[1][2], 1)
	eq(after.fuel, 0)
	eq(after.startedAt, 10)
	local _, bad = Smelting.Take(s, "everything")
	eq(bad, "bad_payload")
end)

test("Workbench orders are made one after another and the queue has a limit", function()
	local furnace = Workshop.Recipe(Items.Furnace)
	local q = assert(Workshop.Order({}, furnace, 100))
	q = assert(Workshop.Order(q, furnace, 110))
	eq(q[1].finishesAt, 145)
	eq(q[2].finishesAt, 190)
	local done, waiting = Workshop.Finished(q, 150)
	eq(#done, 1)
	eq(#waiting, 1)
	for _ = 3, Workshop.MaxQueue do
		q = assert(Workshop.Order(q, furnace, 120))
	end
	local full, code = Workshop.Order(q, furnace, 120)
	eq(full, nil)
	eq(code, "queue_full")
end)

test("Money is shown in dollars with a space between thousands", function()
	eq(Money.Format(123456), "1 234,56 $")
	eq(Money.Format(500), "5 $")
	eq(Money.Format(5), "0,05 $")
	eq(Money.Format(-100000000), "-1 000 000 $")
end)

local Models = load_shared("Models")

local Materials = {}
for _, m in ipairs({ "SmoothPlastic", "Plastic", "Wood", "WoodPlanks", "Slate", "Rock", "Basalt", "Cobblestone", "Brick",
	"Metal", "CorrodedMetal", "Neon", "Fabric", "Grass", "LeafyGrass", "Ground", "Pebble", "Limestone", "Glass", "Pavement", "Marble", "Concrete", "DiamondPlate" }) do
	Materials[m] = true
end
local Shapes = { Block = true, Ball = true, Cylinder = true, Wedge = true }

local function checkModel(name, parts, required)
	assert(#parts > 0, name .. " is empty")
	local named = {}
	for i, p in ipairs(parts) do
		local where = name .. " part " .. i
		assert(Shapes[p.shape], where .. ": shape " .. tostring(p.shape))
		assert(Materials[p.material], where .. ": material " .. tostring(p.material))
		for k = 1, 3 do
			assert(p.size[k] > 0, where .. ": size")
			assert(p.color[k] >= 0 and p.color[k] <= 255 and p.color[k] % 1 == 0, where .. ": colour")
			assert(p.pos[k] == p.pos[k] and p.rot[k] == p.rot[k], where .. ": NaN")
		end
		if p.shape == "Ball" then
			assert(p.size[1] == p.size[2] and p.size[2] == p.size[3], where .. ": a ball is round")
		end
		assert(p.group == nil or p.group == "crown" or p.group == "glow" or p.group == "arm", where .. ": group")
		if p.name then
			named[p.name] = true
		end
	end
	for _, n in ipairs(required or {}) do
		assert(named[n], name .. " has no part named " .. n)
	end
end

test("Every model is made of parts Roblox can build, with the parts the game looks for", function()
	for seed = 1, 30 do
		checkModel("Mine", Models.Mine(seed), { "Rock" })
		checkModel("Tree", Models.Tree(seed), { "Trunk", "Stump" })
	end
	checkModel("Furnace", Models.Furnace(), { "Body", "Fire" })
	checkModel("Furnace on the grid", Models.Furnace(true), { "Body", "Fire" })
	checkModel("Belt", Models.Belt(), { "Body" })
	checkModel("Inserter", Models.Inserter(), { "Body", "Hand" })
	checkModel("WoodenChest", Models.WoodenChest(), { "Body" })
	checkModel("BuildMarker", Models.BuildMarker(Items.Inserter, 4))
	checkModel("BuildMarker", Models.BuildMarker(Items.Furnace, 4))
	checkModel("Workbench", Models.Workbench(), { "Top" })
	checkModel("Stall", Models.Stall(), { "Counter", "Sign" })
	checkModel("Merchant", Models.Merchant())
	checkModel("Fountain", Models.Fountain())
	checkModel("Signpost", Models.Signpost(1), { "Board" })
	local PlotLayout = load_shared("PlotLayout")
	for index = 1, PlotLayout.Count do
		checkModel("PlotDecor", Models.PlotDecor(index * 100, PlotLayout.Size, PlotLayout.OpenSides(index), PlotLayout.FurnaceSlots, PlotLayout.Grid))
		assert(#PlotLayout.OpenSides(index) >= 1, "plot " .. index .. " has a gate")
	end
end)

test("The same seed builds the same model", function()
	local a, b = Models.Tree(5), Models.Tree(5)
	eq(#a, #b)
	for i = 1, #a do
		for k = 1, 3 do
			eq(a[i].pos[k], b[i].pos[k])
			eq(a[i].color[k], b[i].color[k])
		end
	end
	local c = Models.Tree(6)
	assert(c[2].size[1] ~= a[2].size[1], "another seed, another tree")
end)

local Logistics = load_shared("Logistics")
local GridLayout = load_shared("PlotLayout")

local function belt(id, x, z, rot)
	return Logistics.New(id, Items.Belt, x, z, rot)
end

local function count(slots)
	local n = 0
	for _, item in ipairs(slots) do
		if item then n = n + 1 end
	end
	return n
end

test("Things go on the grid only inside it and on free tiles; a furnace takes 2 × 2 tiles", function()
	local objects = { belt(1, 0, 0, 1) }
	local furnaces = { { id = 2, tile = { x = 3, z = 1 }, state = Smelting.Empty() } }
	eq(Logistics.CanPlace(objects, furnaces, Items.Belt, 1, 0), true)
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Belt, 0, 0)), "tile_taken")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.WoodenChest, 4, 2)), "tile_taken")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Furnace, 2, 0)), "tile_taken")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Belt, -1, 0)), "outside_grid")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Furnace, GridLayout.Grid.width - 1, 0)), "outside_grid")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Coal, 8, 0)), "not_buildable")
end)

test("A belt carries an item along to the end of the line and keeps it there", function()
	local objects = { belt(1, 0, 0, 1), belt(2, 1, 0, 1), belt(3, 2, 0, 1) }
	objects[1].belt[1] = Items.Stone
	local last = Logistics.Run(objects, {}, 1000, 1000 + 60)
	eq(last, 1000 + 60)
	eq(count(objects[1].belt) + count(objects[2].belt), 0)
	eq(objects[3].belt[4], Items.Stone, "at the end of the left lane")
	-- What slid in the last tick is reported for drawing.
	local line = { belt(1, 0, 0, 1), belt(2, 1, 0, 1) }
	line[1].belt[4] = Items.Coal
	line[1].belt[2] = Items.Stone
	local watch = { slid = {} }
	Logistics.Run(line, {}, 0, 0.2, watch)
	eq(line[2].belt[1], Items.Coal)
	eq(watch.slid[2][1], true, "slid onto the next belt")
	eq(watch.slid[1][3], true, "slid along the belt")
	eq(watch.slid[1][2], nil)
end)

test("Belts turn corners keeping their lanes, and join from the side onto the near lane", function()
	-- East along z = 0, then south at x = 1.
	local corner = { belt(1, 0, 0, 1), belt(2, 1, 0, 0), belt(3, 1, 1, 0) }
	corner[1].belt[1] = Items.Coal -- left lane
	corner[1].belt[5] = Items.Stone -- right lane
	Logistics.Run(corner, {}, 0, 10)
	eq(corner[3].belt[4], Items.Coal)
	eq(corner[3].belt[8], Items.Stone)
	-- A belt joining a straight line from its east side: east is the left of a belt going south.
	local join = { belt(1, 1, 0, 0), belt(2, 1, 1, 0), belt(3, 1, 2, 0), belt(4, 2, 1, 3) }
	join[4].belt[1] = Items.Coal
	join[4].belt[5] = Items.Stone
	Logistics.Run(join, {}, 0, 10)
	eq(count(join[4].belt), 0)
	eq(join[3].belt[4], Items.Coal, "near lane is the left one")
	eq(join[3].belt[3], Items.Stone)
	eq(count({ join[3].belt[5], join[3].belt[6], join[3].belt[7], join[3].belt[8] }), 0)
end)

test("Inserters move items from a chest over belts into another chest", function()
	local from = Logistics.New(1, Items.WoodenChest, 0, 0, 0)
	Logistics.Store(from.items, Items.Stone, 10)
	local objects = {
		from,
		Logistics.New(2, Items.Inserter, 1, 0, 1),
		belt(3, 2, 0, 1), belt(4, 3, 0, 1),
		Logistics.New(5, Items.Inserter, 4, 0, 1),
		Logistics.New(6, Items.WoodenChest, 5, 0, 0),
	}
	Logistics.Run(objects, {}, 0, 600)
	eq(#from.items, 0)
	eq(objects[6].items[1].item, Items.Stone)
	eq(objects[6].items[1].quantity, 10)
	eq(objects[2].hand, nil)
	eq(objects[5].hand, nil)
end)

test("Inserters feed a furnace ore and coal from one chest and take the ingots to another", function()
	local supply = Logistics.New(1, Items.WoodenChest, 0, 0, 0)
	Logistics.Store(supply.items, Items.IronOre, 10)
	Logistics.Store(supply.items, Items.Coal, 2)
	local furnace = { id = 9, tile = { x = 2, z = 0 }, state = Smelting.Empty() }
	local objects = {
		supply,
		Logistics.New(2, Items.Inserter, 1, 0, 1),
		Logistics.New(3, Items.Inserter, 4, 0, 1),
		Logistics.New(4, Items.WoodenChest, 5, 0, 0),
	}
	local at = Logistics.Run(objects, { furnace }, 0, 3600)
	eq(at, 3600)
	eq(#supply.items, 0)
	eq(objects[4].items[1].item, Items.IronIngot)
	eq(objects[4].items[1].quantity, 10)
	eq(furnace.state.outputQuantity, 0)
end)

test("A chest holds 8 slots of 100 pieces, and the grid catches up a long absence quickly", function()
	local stacks = {}
	Logistics.Store(stacks, Items.Stone, 750)
	eq(Logistics.Room(stacks, Items.Stone), 50)
	eq(Logistics.Room(stacks, Items.Coal), 0)
	eq(Logistics.Unstore(stacks, Items.Stone, 1000), 750)
	eq(#stacks, 0)
	-- A loop of belts keeps busy forever: it rests after MaxTicks.
	local loop = { belt(1, 0, 0, 1), belt(2, 1, 0, 0), belt(3, 1, 1, 3), belt(4, 0, 1, 2) }
	loop[1].belt[1] = Items.Coal
	local at = Logistics.Run(loop, {}, 0, 7 * 24 * 3600)
	eq(at, 7 * 24 * 3600)
	local n = 0
	for _, b in ipairs(loop) do n = n + count(b.belt) end
	eq(n, 1, "nothing lost or made")
end)
