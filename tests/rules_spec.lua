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

test("A wild tree can be cut at once, a planted one when it has grown; cutting gives wood and sometimes a sapling", function()
	eq(Forestry.Grown(Forestry.New(1, 0, 0, nil), 0), true)
	local planted = Forestry.New(2, 0, 0, 100)
	eq(Forestry.Grown(planted, 100 + Forestry.Grow - 1), false)
	eq(Forestry.Grown(planted, 100 + Forestry.Grow), true)
	eq(#Forestry.Cut(Forestry.SaplingChance), 1)
	local lucky = Forestry.Cut(0)
	eq(lucky[1][1], Items.Wood)
	eq(lucky[2][1], Items.Sapling)
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
	"Metal", "CorrodedMetal", "Neon", "Fabric", "Grass", "LeafyGrass", "Ground", "Pebble", "Limestone", "Glass", "Pavement", "Marble", "Concrete", "DiamondPlate", "Sandstone", "Sand", "Rubber", "Foil", "Snow" }) do
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
		assert(p.group == nil or p.group == "crown" or p.group == "glow" or p.group == "arm" or p.group == "spin" or p.group == "train", where .. ": group")
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
	checkModel("Belt turning left", Models.Belt(-1), { "Body" })
	checkModel("Belt turning right", Models.Belt(1), { "Body" })
	checkModel("Sapling", Models.Sapling(3), { "Trunk" })
	checkModel("Inserter", Models.Inserter(), { "Body", "Hand" })
	checkModel("WoodenChest", Models.WoodenChest(), { "Body" })
	checkModel("BuildMarker", Models.BuildMarker(Items.Inserter, 4))
	checkModel("BuildMarker", Models.BuildMarker(Items.Furnace, 4))
	checkModel("Workbench", Models.Workbench(), { "Top" })
	checkModel("Stall", Models.Stall(), { "Counter", "Sign" })
	checkModel("Merchant", Models.Merchant())
	checkModel("Fountain", Models.Fountain())
	checkModel("Signpost", Models.Signpost(1), { "Board" })
	for _, kind in ipairs({ Items.Sawmill, Items.Stonemason, Items.Crusher, Items.Foundry }) do
		checkModel(kind, Models.Machine(kind), { "Body" })
		checkModel("BuildMarker", Models.BuildMarker(kind, 4))
	end
	checkModel("Generator", Models.Generator(), { "Body", "Fire", "Chimney" })
	checkModel("Pole", Models.Pole(), { "Body" })
	checkModel("Wire", Models.Wire({ 0, 9, 0 }, { 12, 9, 20 }))
	checkModel("BuildMarker", Models.BuildMarker(Items.Generator, 4))
	local PlotLayout = load_shared("PlotLayout")
	for index = 1, PlotLayout.Count do
		checkModel("PlotDecor", Models.PlotDecor(index * 100, PlotLayout.Size, PlotLayout.OpenSides(index)))
		assert(#PlotLayout.OpenSides(index) >= 1, "plot " .. index .. " has a gate")
	end
	local Lands = load_shared("Lands")
	for _, id in ipairs(Lands.Order) do
		checkModel("PlotDecor " .. id, Models.PlotDecor(101, PlotLayout.Size, {}, nil, Lands.Biomes[id]))
	end
	checkModel("Tree with snow", Models.Tree(7, true), { "Trunk" })
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
	-- Away from the mines, which take the first rows.
	local function belt(id, x, z, rot)
		return Logistics.New(id, Items.Belt, x, z + 8, rot)
	end
	local objects = { belt(1, 0, 0, 1) }
	local furnaces = { { id = 2, tile = { x = 3, z = 9 }, state = Smelting.Empty() } }
	eq(Logistics.CanPlace(objects, furnaces, Items.Belt, 1, 8), true)
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Belt, 0, 8)), "tile_taken")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.WoodenChest, 4, 10)), "tile_taken")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Furnace, 2, 8)), "tile_taken")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Belt, -1, 8)), "outside_grid")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Furnace, GridLayout.Grid.width - 1, 8)), "outside_grid")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Coal, 8, 8)), "not_buildable")
	eq(select(2, Logistics.CanPlace(objects, furnaces, Items.Belt, 27, 2)), "tile_blocked")
	eq(Logistics.CanPlace(objects, furnaces, Items.Sapling, 10, 12), true)
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

test("The grid covers the plot; only the mines' tiles are taken for good, and wild trees stand on free tiles", function()
	local g = GridLayout.Grid
	assert(g.x >= -GridLayout.Size / 2 and g.x + g.width * g.tile <= GridLayout.Size / 2, "inside the fence (x)")
	assert(g.z >= -GridLayout.Size / 2 and g.z + g.depth * g.tile <= GridLayout.Size / 2, "inside the fence (z)")
	for _, m in ipairs(GridLayout.Mines) do
		local tx, tz = GridLayout.TileAt(m.x, m.z)
		eq(GridLayout.Blocked(tx, tz), true, "mine")
	end
	for _, t in ipairs(GridLayout.WildTrees) do
		eq(GridLayout.Blocked(t.x, t.z), false, "tree")
	end
	for _, t in ipairs(GridLayout.FurnaceSlotTiles) do
		eq(Logistics.CanPlace({}, {}, Items.Furnace, t.x, t.z), true, "old furnace slot")
	end
	local sx, sz = GridLayout.TileAt(GridLayout.Spawn.x, GridLayout.Spawn.z)
	eq(GridLayout.Blocked(sx, sz), false, "spawn")
	-- Old grid objects move by whole tiles.
	for _, old in pairs(GridLayout.OldGrids) do
		eq(((old.x - g.x) / g.tile) % 1, 0)
		eq(((old.z - g.z) / g.tile) % 1, 0)
	end
end)

test("The forest stands between the plots, off the plots, the paths and the square, and neighbouring plots have forest between them", function()
	local trees = GridLayout.ForestTrees()
	assert(#trees > 1000, "dense: " .. #trees)
	assert(#trees < 8000, "not too many parts: " .. #trees)
	local half = GridLayout.Size / 2
	for _, t in ipairs(trees) do
		assert(t.x * t.x + t.z * t.z > 50 * 50, "off the square")
		for index = 1, GridLayout.Count do
			local cx, cz = GridLayout.Center(index)
			assert(math.abs(t.x - cx) > half + 5 or math.abs(t.z - cz) > half + 5, "off plot " .. index)
		end
	end
	-- Each path from the square to a plot's gate is clear.
	for index = 1, GridLayout.Count do
		local cx, cz = GridLayout.Center(index)
		local length = math.sqrt(cx * cx + cz * cz)
		for d = 40, length - half, 5 do
			eq(GridLayout.ForestClear(cx / length * d, cz / length * d), false, "path " .. index)
		end
	end
	-- Neighbouring plots don't touch, and there is room for trees between them.
	for index = 1, GridLayout.Count do
		local ax, az = GridLayout.Center(index)
		local bx, bz = GridLayout.Center(index % GridLayout.Count + 1)
		local gap = math.max(math.abs(ax - bx), math.abs(az - bz)) - GridLayout.Size
		assert(gap >= 2 * GridLayout.Forest.plotMargin + 10, "forest between plots " .. index .. ": " .. gap)
	end
	eq(#GridLayout.ForestTrees(), #trees, "always the same")
	checkModel("ForestTree", Models.ForestTree(1))
	checkModel("ForestTree", Models.ForestTree(2))
end)

test("A belt fed from one side turns the corner, and items on it ride along the curve", function()
	-- East along z = 10, then south: the second belt is fed from its left... from its west side.
	local objects = { belt(1, 0, 10, 1), belt(2, 1, 10, 0), belt(3, 1, 11, 0) }
	local bends = Logistics.Bends(objects)
	eq(bends[1], 0)
	eq(bends[3], 0)
	-- Going south (rot 0), the belt's left is east (+x): fed from the west it comes in from its right.
	eq(bends[2], 1)
	-- On a curve the places run from the side the items come in to the front.
	local first = Models.BeltSlot(1, 4, 1)
	local last = Models.BeltSlot(4, 4, 1)
	assert(first[1] > 1, "comes in on the right (+x) side")
	assert(last[3] < -1, "leaves at the front (-z)")
	local back = Models.BeltSlot(2, 4, 1, true)
	local one = Models.BeltSlot(1, 4, 1)
	assert(math.abs(back[1] - one[1]) < 1e-9 and math.abs(back[3] - one[3]) < 1e-9, "the place behind is the previous place")
end)

local Processing = load_shared("Processing")
local Research = load_shared("Research")

test("A sawmill makes a batch after another from what it holds, and stops when it runs out", function()
	local kind = Items.Sawmill
	local s = Processing.SetRecipe(kind, Processing.Empty(), Items.Planks, 0)
	s = Processing.Load(kind, s, Items.Wood, 5, 0)
	eq(s.startedAt, 0, "starts once loaded")
	s = Processing.Advance(kind, s, 20)
	eq(s.output, 4, "two batches of 2 planks in 20 s")
	eq(s.inputs[1], 3)
	eq(s.startedAt, 16)
	s = Processing.Advance(kind, s, 1000)
	eq(s.output, 10)
	eq(s.inputs[1], 0)
	eq(s.startedAt, nil, "idle with nothing left")
	local nothing = Processing.Load(kind, s, Items.Coal, 1, 1000)
	eq(nothing, nil, "coal does not go in a sawmill")
	-- Changing the recipe hands back its ingredients and products.
	local after, handed = Processing.SetRecipe(kind, s, Items.Beams, 1000)
	eq(after.output, 0)
	eq(handed[1][1], Items.Planks)
	eq(handed[1][2], 10)
end)

test("A full machine stops until its products are taken out, then goes on", function()
	local kind = Items.Crusher
	local s = Processing.SetRecipe(kind, Processing.Empty(), Items.Sand, 0)
	s = Processing.Load(kind, s, Items.Stone, 50, 0)
	s = Processing.Advance(kind, s, 10000)
	eq(s.output, 99, "33 batches of 3 sand fit in 100")
	eq(s.startedAt, nil)
	local taken
	s, taken = Processing.Take(kind, s, "output", 10000)
	eq(taken[1][2], 99)
	eq(s.startedAt, 10000, "starts again")
end)

test("A foundry burns fuel: coal lasts 4 batches, and coal for steel is shared with the fire", function()
	local kind = Items.Foundry
	local s = Processing.SetRecipe(kind, Processing.Empty(), Items.BronzeIngot, 0)
	s = Processing.Load(kind, s, Items.CopperIngot, 30, 0)
	s = Processing.Load(kind, s, Items.TinIngot, 10, 0)
	eq(s.startedAt, nil, "no fire, no work")
	s = Processing.Load(kind, s, Items.Coal, 1, 0)
	s = Processing.Advance(kind, s, 1000)
	eq(s.output, 16, "4 batches of 4 bronze on one coal")
	eq(s.fuel, 0)
	eq(s.heat, 0)
	-- Steel takes coal as an ingredient too: loaded coal goes to both so neither runs out first.
	local steel = Processing.SetRecipe(kind, Processing.Empty(), Items.SteelIngot, 0)
	steel = Processing.Load(kind, steel, Items.IronIngot, 20, 0)
	steel = Processing.Load(kind, steel, Items.Coal, 13, 0)
	eq(steel.inputs[2] + steel.fuel, 13)
	assert(steel.inputs[2] >= 8 and steel.fuel >= 2, "split " .. steel.inputs[2] .. "/" .. steel.fuel)
	steel = Processing.Advance(kind, steel, 10000)
	eq(steel.output, 10, "all 20 iron made into steel")
end)

test("Inserters feed a sawmill from a chest and take the planks to another chest", function()
	local function at(id, kind, x, z, rot)
		return Logistics.New(id, kind, x, z + 8, rot)
	end
	local wood = at(1, Items.WoodenChest, 0, 0, 1)
	Logistics.Store(wood.items, Items.Wood, 10)
	local mill = at(3, Items.Sawmill, 2, 0, 1)
	mill.machine = Processing.SetRecipe(Items.Sawmill, mill.machine, Items.Planks, 0)
	local out = at(5, Items.WoodenChest, 5, 1, 1)
	local objects = { wood, at(2, Items.Inserter, 1, 0, 1), mill, at(4, Items.Inserter, 4, 1, 1), out }
	eq(select(2, Logistics.CanPlace(objects, {}, Items.Belt, 3, 9)), "tile_taken", "a sawmill takes 2 × 2 tiles")
	Logistics.Run(objects, {}, 0, 200)
	local planks = 0
	for _, stack in ipairs(out.items) do
		if stack.item == Items.Planks then planks = stack.quantity end
	end
	eq(planks, 20, "10 wood made 20 planks")
	eq(#wood.items, 0)
	-- Picked up, a machine hands back what it holds.
	mill.machine.output = 3
	local back = Logistics.Contents(mill)
	eq(back[1][1], Items.Planks)
end)

test("Research takes its time, one at a time, and unlocks machines", function()
	local r = {}
	eq(Research.Unlocked(r, Items.Sawmill, 0), false)
	eq(Research.Unlocked(r, Items.Belt, 0), true, "belts came before research")
	r = Research.Start(r, "forestry_industry", 100)
	eq(Research.Status(r, "forestry_industry", 150), "active")
	eq(select(2, Research.Start(r, "stonemasonry", 150)), "research_busy")
	eq(Research.Unlocked(r, Items.Sawmill, 150), false)
	eq(Research.Unlocked(r, Items.Sawmill, 190), true)
	eq(select(2, Research.Start(r, "forestry_industry", 200)), "research_done")
	local again = Research.Start(r, "stonemasonry", 200)
	assert(again and again.forestry_industry, "keeps what was done")
	-- Every machine is made at the workbench and unlocked by some technology.
	for _, kind in ipairs(Processing.Kinds) do
		assert(Workshop.Recipe(kind), "recipe for " .. kind)
		eq(Research.Unlocked({}, kind, 0), false, kind .. " is researched")
		assert(Logistics.Sizes[kind], "size of " .. kind)
	end
	for _, t in ipairs(Research.Technologies) do
		for _, entry in ipairs(t.cost) do assert(Items.Names[entry[1]], entry[1]) end
		for _, item in ipairs(t.unlocks) do assert(Items.Names[item], item) end
	end
end)

test("Every item has a picture of parts Roblox can build", function()
	local Icons = load_shared("Icons")
	for _, id in ipairs(Items.Order) do
		checkModel("Icon " .. id, Icons.Model(id))
	end
end)

test("Market events: the merchant always pays less than it charges, and prices drift at most 10%", function()
	local MarketEvents = load_shared("MarketEvents")
	local seen, last = {}, nil
	local start = 1790000000
	for h = 0, 24 * 60 do
		local now = start + h * 3600
		local p = MarketEvents.Prices(now)
		for item, pays in pairs(p.buys) do
			assert(pays >= 1 and pays % 1 == 0, item)
			if p.sells[item] then
				assert(pays < p.sells[item], item .. " at " .. now)
			end
			local drift = MarketEvents.DriftAt(item, now)
			assert(drift >= -10 and drift <= 10, item)
		end
		local e = MarketEvents.At(now)
		if e then
			seen[e.event.id] = true
			assert(e.startsAt <= now and now < e.endsAt, "event covers its time")
			assert(last == nil or last.startsAt == e.startsAt or last.event ~= e.event, "the same event never runs twice in a row")
		end
		last = e
		local nxt = MarketEvents.Next(now)
		assert(nxt == nil or nxt.startsAt > now, "the next event is ahead")
	end
	local kinds = 0
	for _ in pairs(seen) do kinds = kinds + 1 end
	assert(kinds >= 4, "several kinds of events in two months, saw " .. kinds)
	for _, e in ipairs(MarketEvents.Events) do
		for item in pairs(e.pays) do assert(Items.Names[item], item) end
		for item in pairs(e.charges) do assert(Items.Names[item], item) end
	end
	-- The same moment gives the same prices on every server.
	eq(MarketEvents.Prices(start).buys[Items.IronOre], MarketEvents.Prices(start).buys[Items.IronOre])
end)

test("Player market: listings are bought, orders filled, earnings wait in the book until collected", function()
	local Market = load_shared("Market")
	local book = Market.EmptyBook()
	local function step(action)
		local b, r = Market.Apply(book, action)
		if b then book = b end
		return r
	end
	local a = step({ tx = "1", kind = "list", owner = "10", name = "Ala", quantity = 100, priceCents = 300, at = 0 })
	local b = step({ tx = "2", kind = "list", owner = "10", name = "Ala", quantity = 5, priceCents = 250, at = 0 })
	eq(a.id, 1)
	eq(b.id, 2)
	eq(Market.Board(book).listings[1].priceCents, 250, "cheapest first")
	eq(Market.Summary(book).listed, 105)
	-- Not one's own offer, not at another price, not more than is left.
	eq(select(2, Market.Apply(book, { tx = "3", kind = "buy", taker = "10", id = 1, quantity = 1, priceCents = 300 })), "own_offer")
	eq(select(2, Market.Apply(book, { tx = "3", kind = "buy", taker = "20", id = 1, quantity = 1, priceCents = 200 })), "price_changed")
	eq(select(2, Market.Apply(book, { tx = "3", kind = "buy", taker = "20", id = 2, quantity = 6, priceCents = 250 })), "not_enough_offered")
	step({ tx = "3", kind = "buy", taker = "20", id = 2, quantity = 5, priceCents = 250 })
	step({ tx = "4", kind = "buy", taker = "20", id = 1, quantity = 40, priceCents = 300 })
	eq(#book.listings, 1, "a listing sold out is gone")
	eq(book.listings[1].left, 60)
	eq(Market.Owed(book, "10").cents, 5 * 250 + 40 * 300)
	-- A step is done once: the same transaction again is refused, and the book remembers its result.
	eq(select(2, Market.Apply(book, { tx = "4", kind = "buy", taker = "20", id = 1, quantity = 40, priceCents = 300 })), "duplicate")
	eq(Market.Done(book, "4").result.owner, "10")
	local got = step({ tx = "5", kind = "collect", owner = "10" })
	eq(got.cents, 13250)
	eq(Market.Owed(book, "10"), nil)
	eq(select(2, Market.Apply(book, { tx = "6", kind = "collect", owner = "10" })), "nothing_owed")
	-- An order: the buyer's money waits; a seller fills part, the items wait for the buyer.
	local o = step({ tx = "7", kind = "order", owner = "20", name = "Olek", quantity = 50, priceCents = 280, at = 0 })
	step({ tx = "8", kind = "fill", taker = "10", id = o.id, quantity = 30, priceCents = 280 })
	eq(Market.Owed(book, "20").quantity, 30)
	-- Cancelling gives back what is left: items of a listing, money of an order; only to the owner.
	eq(select(2, Market.Apply(book, { tx = "9", kind = "cancel", owner = "20", offerKind = "listing", id = 1 })), "no_offer")
	local back = step({ tx = "9", kind = "cancel", owner = "10", offerKind = "listing", id = 1 })
	eq(back.quantity, 60)
	back = step({ tx = "10", kind = "cancel", owner = "20", offerKind = "order", id = o.id })
	eq(back.cents, 20 * 280)
	eq(#Market.Mine(book, "20"), 0)
	eq(step({ tx = "11", kind = "collect", owner = "20" }).quantity, 30)
end)

test("Player market: no money or items appear or vanish, whatever the order of steps", function()
	local Market = load_shared("Market")
	local book = Market.EmptyBook()
	-- Two players as the server keeps them: their side is taken first, then the book decides.
	local players = { ["1"] = { cents = 100000, items = 500 }, ["2"] = { cents = 100000, items = 500 } }
	local function total()
		local cents, items = 0, 0
		for _, p in pairs(players) do cents = cents + p.cents; items = items + p.items end
		for _, o in ipairs(book.listings) do items = items + o.left end
		for _, o in ipairs(book.orders) do cents = cents + o.left * o.priceCents end
		for _, w in pairs(book.owed) do cents = cents + w.cents; items = items + w.quantity end
		return cents, items
	end
	local cents0, items0 = total()
	local seed = 7
	local function rnd(n) seed = (seed * 16807) % 2147483647; return seed % n + 1 end
	for i = 1, 600 do
		local who = tostring(rnd(2))
		local p = players[who]
		local kinds = { "list", "order", "buy", "fill", "cancel", "collect" }
		local kind = kinds[rnd(6)]
		local q, price = rnd(20), 100 + rnd(5) * 10
		local action = { tx = tostring(i), kind = kind, owner = who, taker = who, name = who, quantity = q, priceCents = price, at = 0 }
		local list = (kind == "buy" or kind == "fill") and (kind == "buy" and book.listings or book.orders) or nil
		if list and #list > 0 then
			local offer = list[rnd(#list)]
			action.id, action.priceCents = offer.id, offer.priceCents
		elseif kind == "cancel" then
			local mine = Market.Mine(book, who)
			if #mine > 0 then
				local m = mine[rnd(#mine)]
				action.id, action.offerKind = m.id, m.offerKind
			end
		end
		-- The player's side.
		local cost = (kind == "order" or kind == "buy") and action.quantity * action.priceCents or 0
		local give = (kind == "list" or kind == "fill") and action.quantity or 0
		if p.cents >= cost and p.items >= give then
			p.cents, p.items = p.cents - cost, p.items - give
			local b, r = Market.Apply(book, action)
			if b then
				book = b
				if kind == "buy" then p.items = p.items + action.quantity
				elseif kind == "fill" then p.cents = p.cents + action.quantity * action.priceCents
				elseif kind == "cancel" or kind == "collect" then p.cents = p.cents + r.cents; p.items = p.items + r.quantity end
			else
				p.cents, p.items = p.cents + cost, p.items + give
			end
		end
		local cents, items = total()
		eq(cents, cents0, "money after step " .. i)
		eq(items, items0, "items after step " .. i)
	end
end)

test("Every item belongs to one of the merchant's and the market's groups", function()
	local groups = {}
	for _, c in ipairs(Items.Categories) do groups[c.id] = 0 end
	for _, id in ipairs(Items.Order) do
		local c = Items.Category(id)
		assert(groups[c], id .. " in " .. tostring(c))
		groups[c] = groups[c] + 1
	end
	for id, n in pairs(groups) do assert(n > 0, "group " .. id .. " is empty") end
	eq(Items.Category(Items.Planks), "materials")
	eq(Items.Category(Items.CrushedIronOre), "ores")
end)

local Power = load_shared("Power")

-- A generator, a pole by it and a crusher crushing tin ore, all on one network.
local function powerPlant()
	local generator = Logistics.New(1, Items.Generator, 0, 8, 0)
	local pole = Logistics.New(2, Items.Pole, 3, 8, 0)
	local crusher = Logistics.New(3, Items.Crusher, 4, 9, 0)
	crusher.machine = Processing.SetRecipe(Items.Crusher, crusher.machine, Items.CrushedTinOre, 0)
	crusher.machine = Processing.Load(Items.Crusher, crusher.machine, Items.TinOre, 50, 0)
	return { generator, pole, crusher }, generator, crusher
end

test("A crusher works only on a network with a fuelled generator, and stops where it got to when the fuel runs out", function()
	local objects, generator, crusher = powerPlant()
	local nets = Power.Networks(objects, Logistics.Sizes)
	eq(#nets, 1)
	eq(#nets[1].generators, 1)
	eq(nets[1].demand, Power.Demand[Items.Crusher])
	local at, powerAt = Logistics.RunPowered(objects, {}, 0, 0, 100)
	eq(crusher.machine.output, 0, "no fuel, no work")
	eq(Processing.Working(Items.Crusher, crusher.machine, 100), false)
	-- One piece of wood: 5000 kJ at 40 kW lasts 125 s, enough for 20 batches of 6 s and 5 s more.
	generator.generator = Power.Load(generator.generator, Items.Wood, 1)
	Power.Apply(objects, Logistics.Sizes, powerAt)
	at, powerAt = Logistics.RunPowered(objects, {}, at, powerAt, 400)
	local s = Processing.Advance(Items.Crusher, crusher.machine, 400)
	eq(s.output, 60)
	eq(s.inputs[1], 10)
	assert(math.abs(Processing.Progress(Items.Crusher, s, 400) - 5 / 6) < 1e-6, "keeps 5 s of the batch")
	eq(Power.Running(generator.generator), false)
	-- Coal: the batch goes on from where it stopped and the last five are done 25 s later.
	generator.generator = Power.Load(generator.generator, Items.Coal, 1)
	Power.Apply(objects, Logistics.Sizes, powerAt)
	at, powerAt = Logistics.RunPowered(objects, {}, at, powerAt, 424)
	eq(Processing.Advance(Items.Crusher, crusher.machine, 424).output, 72, "4 batches in 24 s")
	at, powerAt = Logistics.RunPowered(objects, {}, at, powerAt, 1000)
	eq(Processing.Advance(Items.Crusher, crusher.machine, 1000).output, 75)
	-- An idle machine on the network still draws: the coal (500 s at 40 kW) is gone by 900 s.
	eq(Power.Running(generator.generator), false)
	eq(powerAt, 1000)
end)

test("Too little power slows every machine on the network; poles too far apart make two networks", function()
	local objects = { Logistics.New(1, Items.Generator, 0, 8, 0), Logistics.New(2, Items.Pole, 3, 8, 0) }
	for i = 1, 3 do
		table.insert(objects, Logistics.New(10 + i, Items.Crusher, 2 * i - 1, 10, 0))
	end
	objects[1].generator = Power.Load(objects[1].generator, Items.Coal, 10)
	local net = Power.Networks(objects, Logistics.Sizes)[1]
	eq(net.demand, 120)
	eq(Power.Speed(net), 100 / 120)
	local second = Logistics.New(4, Items.Generator, 0, 6, 0)
	second.generator = Power.Load(second.generator, Items.Coal, 1)
	table.insert(objects, second)
	eq(Power.Speed(Power.Networks(objects, Logistics.Sizes)[1]), 1, "two generators are enough")
	-- A pole 7 tiles away is wired in, one 8 tiles away is not.
	table.insert(objects, Logistics.New(5, Items.Pole, 10, 8, 0))
	eq(#Power.Networks(objects, Logistics.Sizes), 1)
	table.insert(objects, Logistics.New(6, Items.Pole, 18, 8, 0))
	eq(#Power.Networks(objects, Logistics.Sizes), 2)
	eq(#Power.Wires(objects), 1, "the far pole has no wire")
	-- A crusher no pole reaches stops.
	local far = Logistics.New(7, Items.Crusher, 40, 40, 0)
	far.machine = Processing.SetRecipe(Items.Crusher, far.machine, Items.Sand, 0)
	far.machine = Processing.Load(Items.Crusher, far.machine, Items.Stone, 5, 0)
	table.insert(objects, far)
	Power.Apply(objects, Logistics.Sizes, 0)
	eq(Processing.Advance(Items.Crusher, far.machine, 100).output, 0)
end)

test("Burning in steps gives the same generator as burning at once, and nothing is burnt twice", function()
	local g = Power.Load(Power.EmptyGenerator(), Items.Coal, 5)
	local once = Power.Burn(g, 73000)
	local steps = g
	for _ = 1, 73 do
		steps = Power.Burn(steps, 1000)
	end
	eq(steps.fuel, once.fuel)
	assert(math.abs(steps.energy - once.energy) < 1e-6)
	eq(Power.Total(once), 100000 - 73000)
	eq(Power.Running(Power.Burn(g, 100000)), false)
	eq(select(2, Power.Load(g, Items.Wood, 1)), "generator_busy")
	eq(select(2, Power.Load(g, Items.Stone, 1)), "not_fuel")
	eq(select(2, Power.Load(g, Items.Coal, Power.MaxFuel)), "generator_full")
	-- Picked up, a generator hands back the fuel not burning yet.
	local o = Logistics.New(1, Items.Generator, 0, 8, 0)
	o.generator = once
	eq(Logistics.Contents(o)[1][2], once.fuel)
end)

test("An inserter brings a generator coal from a chest", function()
	local chest = Logistics.New(1, Items.WoodenChest, 0, 8, 1)
	Logistics.Store(chest.items, Items.Coal, 70)
	Logistics.Store(chest.items, Items.Stone, 5)
	local generator = Logistics.New(3, Items.Generator, 2, 8, 0)
	local objects = { chest, Logistics.New(2, Items.Inserter, 1, 8, 1), generator }
	Logistics.Run(objects, {}, 0, 600)
	eq(generator.generator.fuelItem, Items.Coal)
	eq(generator.generator.fuel, Power.MaxFuel)
	local left = {}
	for _, stack in ipairs(chest.items) do left[stack.item] = stack.quantity end
	eq(left[Items.Coal], 20)
	eq(left[Items.Stone], 5, "stone is no fuel and stays")
end)

test("A workbench can be bought, made and put on the plot's grid on 2 × 2 tiles", function()
	assert(Prices.Sells[Items.Workbench] > Prices.Buys[Items.Workbench])
	eq(Workshop.Recipe(Items.Workbench).ingredients[1][1], Items.Wood)
	local objects = { Logistics.New(1, Items.Workbench, 10, 10, 0) }
	eq(select(2, Logistics.CanPlace(objects, {}, Items.Belt, 11, 11)), "tile_taken")
	eq(Logistics.CanPlace(objects, {}, Items.Belt, 12, 11), true)
	eq(Items.Category(Items.Workbench), "buildings")
end)

local Rail = load_shared("Rail")

test("Trains: fee and time by distance, cargo of a route, and every station somewhere on the map", function()
	eq(Rail.FeeCents(250, 100), 100 + 250)
	eq(Rail.TripSeconds(10), Rail.MinTrip)
	eq(Rail.TripSeconds(1000), 50)
	for id = 1, 50 do
		local x, y = Rail.Location(id * 7919)
		assert(x >= 0 and x <= Rail.WorldKm.width and y >= 0 and y <= Rail.WorldKm.height)
		eq(Rail.DistanceKm(id, id + 1), Rail.DistanceKm(id + 1, id))
	end
	local cargo = Rail.Cargo({ coal = 1500, wood = 900, stone = 10 }, {})
	eq(Rail.Count(cargo), Rail.RouteCapacity)
	eq(cargo[1][1], "coal")
	cargo = Rail.Cargo({ coal = 1500, wood = 900 }, { "wood", "planks" })
	eq(#cargo, 1)
	eq(cargo[1][2], 900)
end)

test("Trains: shipments wait in the inbox until they arrive, once each, and only to an open station", function()
	local ship = { tx = "a", kind = "ship", from = 1, fromName = "Ola", items = { { "coal", 5 } }, sentAt = 0, arriveAt = 30 }
	eq(select(2, Rail.Apply(nil, ship)), "no_station")
	local inbox = Rail.Apply(nil, { kind = "open" })
	inbox = Rail.Apply(inbox, ship)
	eq(select(2, Rail.Apply(inbox, ship)), "duplicate")
	eq(select(2, Rail.Apply(inbox, { tx = "b", kind = "collect", now = 10 })), "nothing_arrived")
	local after, result = Rail.Apply(inbox, { tx = "c", kind = "collect", now = 30 })
	eq(#result.shipments, 1)
	eq(#after.shipments, 0)
	eq(Rail.Done(after, "c").result.shipments[1].items[1][2], 5, "a server that lost the answer finds it")
	eq(Rail.Arrived(after, 1000), false)
end)

test("The station stands on every grid at the same tiles, inserters load and unload it, and the forest keeps off the railway", function()
	local chest0 = Logistics.New(1, Items.WoodenChest, GridLayout.Station.x + 1, GridLayout.Station.z + 1, 0)
	local objects = { chest0 }
	local station, removed = Logistics.EnsureStation(objects, 2)
	eq(#removed, 1, "what stood there goes back")
	eq(Logistics.EnsureStation(objects, 3), station, "only one station")
	eq(#objects, 1)
	eq(select(2, Logistics.CanPlace(objects, {}, Items.Belt, GridLayout.Station.x, GridLayout.Station.z + 2)), "tile_taken")
	-- A chest of coal → inserter → station → inserter → chest.
	local s = GridLayout.Station
	local chest = Logistics.New(10, Items.WoodenChest, s.x - 2, s.z + 1, 1)
	Logistics.Store(chest.items, Items.Coal, 20)
	table.insert(objects, chest)
	table.insert(objects, Logistics.New(11, Items.Inserter, s.x - 1, s.z + 1, 1))
	local out = Logistics.New(12, Items.WoodenChest, s.x - 2, s.z + 2, 1)
	table.insert(objects, out)
	Rail.Add(station.stock, Items.Wood, 3)
	table.insert(objects, Logistics.New(13, Items.Inserter, s.x - 1, s.z + 2, 3))
	Logistics.Run(objects, {}, 0, 120)
	local wood = 0
	for _, stack in ipairs(out.items) do
		if stack.item == Items.Wood then wood = stack.quantity end
	end
	eq(wood, 3, "the station's wood came out")
	eq(#chest.items, 0, "the coal went in (and on out again: an inserter takes anything from a station)")
	for index = 1, GridLayout.Count do
		local cx, cz = GridLayout.Center(index)
		local r = GridLayout.Rail
		for z = r.from, r.to, 10 do
			eq(GridLayout.ForestClear(cx + r.x, cz + z), false)
		end
	end
end)

local WorldMap = load_shared("WorldMap")

test("The trains' world: every station stands on land, and the poles are ice", function()
	for id = 1, 200 do
		local x, y = Rail.Location(id * 104729)
		assert(not WorldMap.IsWater(WorldMap.Biome(x, y)), "station " .. id .. " in water")
	end
	eq(WorldMap.Biome(100, 5), "snow")
	eq(WorldMap.Biome(700, 400), WorldMap.Biome(700 + WorldMap.Km.width, 400), "east-west wraps round")
end)

local Lands = load_shared("Lands")

test("Plots of biomes: one of each, dearer each time, with their own trees and mines", function()
	local lands = {}
	eq(Lands.Price(lands), Lands.Prices[1])
	eq(Lands.CanBuy(lands, "forest"), true)
	eq(select(2, Lands.CanBuy(lands, "ocean")), "bad_payload")
	local id = 100
	local function nextId()
		id = id + 1
		return id
	end
	lands.forest = Lands.New("forest", nextId, GridLayout.Grid.layout)
	eq(select(2, Lands.CanBuy(lands, "forest")), "land_owned", "one of each biome")
	eq(Lands.Price(lands), Lands.Prices[2])
	assert(Lands.Prices[2] > Lands.Prices[1], "dearer each time")
	eq(#lands.forest.grid.objects, Lands.Biomes.forest.trees, "all the forest's trees fit")
	for _, t in ipairs(lands.forest.grid.objects) do
		eq(Logistics.CanPlace({}, {}, Items.Sapling, t.x, t.z), true, "tree on a free tile")
	end
	eq(#Lands.New("desert", nextId, 3).grid.objects, 0, "no trees in the desert")
	eq(Lands.New("tundra", nextId, 3).grid.objects[1].snow, true, "snowy trees in the tundra")
	for _, id2 in ipairs(Lands.Order) do
		local b = Lands.Biomes[id2]
		assert(b.name and b.ground and b.material, id2)
		local last = 0
		for _, drop in ipairs(b.drops) do
			assert(Items.Names[drop[1]], id2 .. " drops a known item")
			assert(drop[2] >= 1 and drop[2] < 1000, id2 .. " chance")
			assert(drop[2] >= last, id2 .. ": rarest first")
			last = drop[2]
		end
		local all = {}
		for i = 1, #b.drops do all[i] = 0 end
		eq(#Mining.Load(all, b.drops), math.min(Mining.MaxOres, #b.drops))
	end
	eq(Lands.Price({ a = 1, b = 1, c = 1 }), Lands.LaterPrice, "a billion after the third")
	-- Every biome can be bought, then no more.
	for _, biome in ipairs(Lands.Order) do
		if lands[biome] == nil then
			lands[biome] = Lands.New(biome, nextId, 3)
		end
	end
	eq(Lands.Price(lands), nil)
end)

test("Switching plots puts the shown one away and brings the other, the home plot's station stays on it", function()
	local home = { objects = { { id = 1, kind = "rail_station" } } }
	local profile = { grid = home, furnaces = { { id = 2 } }, mines = { Mining.New() }, lands = {} }
	profile.lands.desert = Lands.New("desert", function() return 50 end, 3)
	local desertGrid = profile.lands.desert.grid
	eq(Lands.Shown(profile), Lands.Home)
	eq(select(2, Lands.Switch(profile, Lands.Home)), "land_shown")
	eq(select(2, Lands.Switch(profile, "forest")), "not_owner")
	eq(Lands.Switch(profile, "desert"), true)
	eq(profile.active, "desert")
	eq(profile.grid, desertGrid)
	eq(#profile.furnaces, 0)
	eq(Lands.HomeGrid(profile), home, "the station is found on the home plot")
	profile.mines[1].units = 7
	eq(Lands.Switch(profile, Lands.Home), true)
	eq(profile.grid, home)
	eq(profile.furnaces[1].id, 2)
	eq(profile.home, nil)
	eq(profile.lands.desert.grid, desertGrid, "the desert waits as it was")
	eq(profile.lands.desert.mine.units, 7, "with its mine")
	eq(Lands.Count(profile.lands), 1)
end)
