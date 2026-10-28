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
	"Metal", "CorrodedMetal", "Neon", "Fabric", "Grass", "LeafyGrass", "Ground", "Pebble", "Limestone", "Glass", "Pavement", "Marble" }) do
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
		assert(p.group == nil or p.group == "crown" or p.group == "glow", where .. ": group")
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
	checkModel("Workbench", Models.Workbench(), { "Top" })
	checkModel("Stall", Models.Stall(), { "Counter", "Sign" })
	checkModel("Merchant", Models.Merchant())
	checkModel("Fountain", Models.Fountain())
	checkModel("Signpost", Models.Signpost(1), { "Board" })
	local PlotLayout = load_shared("PlotLayout")
	for index = 1, PlotLayout.Count do
		checkModel("PlotDecor", Models.PlotDecor(index * 100, PlotLayout.Size, PlotLayout.OpenSides(index), PlotLayout.FurnaceSlots))
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
