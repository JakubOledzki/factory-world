-- Belts, inserters and chests on the plot's build grid (LogisticsRules and PlotLogistics in
-- Simulation.cs on main). Nothing runs in a loop: the grid is worked out in steps of Tick seconds
-- from the time it was last looked at (Logistics.Run), whenever someone looks at it or changes it.
--
-- Belts move their items forward along two lanes onto the belt they face (not head on). A belt fed
-- from behind, or from one side only, carries both lanes on as they are, so belts can turn corners;
-- a belt joining another from the side puts all it carries on the near lane of that one. An inserter
-- picks one item from the tile behind it (a belt, a chest or a furnace's ingots), swings round and
-- drops it on the tile in front when that takes it: on a belt, on the far lane first.
--
-- An object on the grid is { id, kind, x, z, rot, ... } (trees too, see Forestry) with the tile of its corner and its
-- rotation (0 south, 1 east, 2 north, 3 west); a belt keeps `belt` (lane after lane, from where
-- items come on to where they leave, false when empty), an inserter `hand` and `swing`, a chest
-- `items` ({ item, quantity } stacks) and `next`, a processing machine `machine` (Processing). An
-- object bigger than one tile takes the tiles from its corner to +x and +z. Furnaces live in the
-- player's furnace list and stand on the grid when they have a `tile` ({ x, z }).
local Items = require(script.Parent.Items)
local Smelting = require(script.Parent.Smelting)
local Processing = require(script.Parent.Processing)
local PlotLayout = require(script.Parent.PlotLayout)
local Power = require(script.Parent.Power)

local Logistics = {}

Logistics.Tick = 0.2

-- Places for items along one lane of a belt tile; an item moves one place per tick.
Logistics.BeltSlots = 4
Logistics.BeltLanes = 2

-- Ticks an inserter's arm takes to swing from where it picks up to where it drops, and as many back.
Logistics.SwingTicks = 4

-- Ticks worked out in one catch-up without a pause: 30 minutes. Machinery that keeps busy for
-- longer while nobody looks rests for the rest of the time.
Logistics.MaxTicks = 9000

-- A wooden chest: slots of up to SlotSize pieces of one kind each.
Logistics.ChestSlots = 8
Logistics.SlotSize = 100

-- What can be put on the grid and how many tiles across it is. A sapling is planted as a tree.
Logistics.Sizes = {
	[Items.Sapling] = 1,
	[Items.Belt] = 1,
	[Items.Inserter] = 1,
	[Items.WoodenChest] = 1,
	[Items.Furnace] = 2,
	[Items.Sawmill] = 2,
	[Items.Stonemason] = 2,
	[Items.Crusher] = 2,
	[Items.Foundry] = 3,
	[Items.Generator] = 2,
	[Items.Pole] = 1,
	[Items.Workbench] = 2,
}

-- An inserter drops on a lane in the middle first, where the item has room to move on.
local DropOrder = { 1, 2, 0, 3 }

-- The tile a rotation faces, as dx, dz.
function Logistics.Facing(rot)
	rot = rot % 4
	if rot == 0 then
		return 0, 1
	elseif rot == 1 then
		return 1, 0
	elseif rot == 2 then
		return 0, -1
	end
	return -1, 0
end

-- The tile on the left of something going the way a rotation faces.
function Logistics.Left(rot)
	local dx, dz = Logistics.Facing(rot)
	return dz, -dx
end

local function key(x, z)
	return x .. "," .. z
end

-- What stands on each tile: [key] = { object = ... } or { furnace = ... }.
function Logistics.Occupied(objects, furnaces)
	local at = {}
	for _, o in ipairs(objects) do
		local size = Logistics.Sizes[o.kind] or 1
		for dx = 0, size - 1 do
			for dz = 0, size - 1 do
				at[key(o.x + dx, o.z + dz)] = { object = o }
			end
		end
	end
	for _, f in ipairs(furnaces) do
		if f.tile then
			for dx = 0, Logistics.Sizes[Items.Furnace] - 1 do
				for dz = 0, Logistics.Sizes[Items.Furnace] - 1 do
					at[key(f.tile.x + dx, f.tile.z + dz)] = { furnace = f }
				end
			end
		end
	end
	return at
end

-- Whether `kind` can be put with its corner on tile (x, z); or false and an error code.
function Logistics.CanPlace(objects, furnaces, kind, x, z)
	local size = Logistics.Sizes[kind]
	if size == nil then
		return false, "not_buildable"
	end
	local g = PlotLayout.Grid
	if x < 0 or z < 0 or x + size > g.width or z + size > g.depth then
		return false, "outside_grid"
	end
	local at = Logistics.Occupied(objects, furnaces)
	for dx = 0, size - 1 do
		for dz = 0, size - 1 do
			if PlotLayout.Blocked(x + dx, z + dz) then
				return false, "tile_blocked"
			end
			if at[key(x + dx, z + dz)] then
				return false, "tile_taken"
			end
		end
	end
	return true
end

-- A new object of `kind` on the grid.
function Logistics.New(id, kind, x, z, rot)
	local o = { id = id, kind = kind, x = x, z = z, rot = rot % 4 }
	if kind == Items.Belt then
		o.belt = {}
		for i = 1, Logistics.BeltSlots * Logistics.BeltLanes do
			o.belt[i] = false
		end
	elseif kind == Items.Inserter then
		o.swing = 0
	elseif kind == Items.WoodenChest then
		o.items = {}
		o.next = 0
	elseif Processing.IsMachine(kind) then
		o.machine = Processing.Empty()
	elseif kind == Items.Generator then
		o.generator = Power.EmptyGenerator()
	end
	return o
end

-- Everything an object holds, as a list of { item, quantity }, to hand back when it is picked up.
function Logistics.Contents(o)
	local out = {}
	for _, item in ipairs(o.belt or {}) do
		if item then
			table.insert(out, { item, 1 })
		end
	end
	if o.hand then
		table.insert(out, { o.hand, 1 })
	end
	for _, stack in ipairs(o.items or {}) do
		table.insert(out, { stack.item, stack.quantity })
	end
	if o.machine then
		for _, entry in ipairs(Processing.Contents(o.kind, o.machine)) do
			table.insert(out, entry)
		end
	end
	if o.generator and o.generator.fuelItem and o.generator.fuel > 0 then
		table.insert(out, { o.generator.fuelItem, o.generator.fuel })
	end
	return out
end

-- How many more pieces of `item` fit in a chest holding `stacks`.
function Logistics.Room(stacks, item)
	local mine, others = 0, 0
	for _, stack in ipairs(stacks) do
		if stack.item == item then
			mine = stack.quantity
		else
			others = others + math.ceil(stack.quantity / Logistics.SlotSize)
		end
	end
	return math.max(0, (Logistics.ChestSlots - others) * Logistics.SlotSize - mine)
end

function Logistics.Store(stacks, item, quantity)
	for _, stack in ipairs(stacks) do
		if stack.item == item then
			stack.quantity = stack.quantity + quantity
			return
		end
	end
	table.insert(stacks, { item = item, quantity = quantity })
end

-- Takes up to `quantity` pieces out; returns how many there were.
function Logistics.Unstore(stacks, item, quantity)
	for i, stack in ipairs(stacks) do
		if stack.item == item then
			local taken = math.min(quantity, stack.quantity)
			stack.quantity = stack.quantity - taken
			if stack.quantity == 0 then
				table.remove(stacks, i)
			end
			return taken
		end
	end
	return 0
end

-- A chest as inserters see it: anything stored can come out, anything with room can go in. They
-- take from its stacks in turn, so ore and coal stored together both reach a furnace.
local function chestPort(o)
	local port = {}
	function port.Output(wanted)
		local stacks = o.items
		for i = 0, #stacks - 1 do
			local stack = stacks[(o.next + i) % #stacks + 1]
			if stack.quantity > 0 and wanted(stack.item) then
				return stack.item
			end
		end
		return nil
	end
	function port.Take(item)
		local stacks = o.items
		local at = 0
		for i, stack in ipairs(stacks) do
			if stack.item == item then
				at = i - 1
			end
		end
		if Logistics.Unstore(stacks, item, 1) > 0 then
			-- The next stack comes next; one that ran out has made room for it already.
			if #stacks == 0 then
				o.next = 0
			elseif stacks[at + 1] and stacks[at + 1].item == item then
				o.next = (at + 1) % #stacks
			else
				o.next = at % #stacks
			end
		end
	end
	function port.Accepts(item)
		return Logistics.Room(o.items, item) > 0
	end
	function port.Put(item)
		Logistics.Store(o.items, item, 1)
	end
	function port.NextChange()
		return nil
	end
	return port
end

-- A furnace as inserters see it at time `t`: coal and ore go in, ingots come out.
local function furnacePort(f)
	local port = {}
	local function at(t)
		f.state = Smelting.Advance(f.state, t)
		return f.state
	end
	function port.Output(wanted, t)
		local s = at(t)
		if s.outputQuantity > 0 and wanted(s.output) then
			return s.output
		end
		return nil
	end
	function port.Take(_item, t)
		local s = at(t)
		s.outputQuantity = s.outputQuantity - 1
		if s.outputQuantity == 0 then
			s.output = nil
		end
	end
	function port.Accepts(item, t)
		local s = at(t)
		if item == Items.Coal then
			return s.fuel < Smelting.MaxFuel
		end
		local recipe = Smelting.Recipes[item]
		if recipe == nil then
			return false
		end
		return (s.input == nil or s.input == item)
			and s.inputQuantity < Smelting.MaxInput
			and (s.output == nil or s.outputQuantity == 0 or s.output == recipe.output)
	end
	function port.Put(item, t)
		local after = Smelting.Load(at(t), item, 1, t)
		if after then
			f.state = after
		end
	end
	-- When the next ingot is done, if it smelts.
	function port.NextChange(t)
		local s = at(t)
		if s.startedAt then
			return s.startedAt + Smelting.Recipes[s.input].time
		end
		return nil
	end
	return port
end

-- A processing machine as inserters see it at time `t`: ingredients and fuel go in, products come out.
local function machinePort(o)
	local port = {}
	local function at(t)
		o.machine = Processing.Advance(o.kind, o.machine, t)
		return o.machine
	end
	function port.Output(wanted, t)
		local s = at(t)
		if s.output > 0 and wanted(s.recipe) then
			return s.recipe
		end
		return nil
	end
	function port.Take(_item, t)
		local s = at(t)
		s.output = s.output - 1
		o.machine = Processing.Start(o.kind, s, t)
	end
	function port.Accepts(item, t)
		return Processing.Room(o.kind, at(t), item) > 0
	end
	function port.Put(item, t)
		local after = Processing.Load(o.kind, at(t), item, 1, t)
		if after then
			o.machine = after
		end
	end
	-- When the next batch is done, if one is being made.
	function port.NextChange(t)
		return Processing.NextChange(o.kind, at(t))
	end
	return port
end

-- A generator as inserters see it: fuel goes in, nothing comes out. Fuel brought to one that has
-- run dry counts from the next stretch of power (server Factory.CatchUp).
local function generatorPort(o)
	local port = {}
	function port.Output()
		return nil
	end
	function port.Take() end
	function port.Accepts(item)
		return Power.Room(o.generator, item) > 0
	end
	function port.Put(item)
		local after = Power.Load(o.generator, item, 1)
		if after then
			o.generator = after
		end
	end
	function port.NextChange()
		return nil
	end
	return port
end

-- Which side a belt turns in from: -1 when the only belt feeding it comes from its left, 1 from its
-- right, 0 when it runs straight (fed from behind, from both sides or not at all).
local function bend(belts, b)
	local function feeds(fx, fz)
		local other = belts[key(b.x + fx, b.z + fz)]
		if other == nil then
			return false
		end
		local dx, dz = Logistics.Facing(other.rot)
		return dx == -fx and dz == -fz
	end
	local fx, fz = Logistics.Facing(b.rot)
	local lx, lz = Logistics.Left(b.rot)
	local fromLeft, fromRight = feeds(lx, lz), feeds(-lx, -lz)
	if feeds(-fx, -fz) or fromLeft == fromRight then
		return 0
	end
	return fromLeft and -1 or 1
end

-- How items leave belt `b` the way it faces: onto the belt there, unless that one runs head on into
-- it. A link is { to, into = { lane for lane 0, lane for lane 1 }, entry }.
local function connect(belts, b)
	local wx, wz = Logistics.Facing(b.rot)
	local nextBelt = belts[key(b.x + wx, b.z + wz)]
	if nextBelt == nil then
		return nil
	end
	local fx, fz = Logistics.Facing(nextBelt.rot)
	if fx == -wx and fz == -wz then
		return nil
	end
	if (fx == wx and fz == wz) or bend(belts, nextBelt) ~= 0 then
		-- From behind onto the start of it, or round a corner.
		return { to = nextBelt, into = { 0, 1 }, entry = 0 }
	end
	-- From the side into the middle of the near lane.
	local lx, lz = Logistics.Left(nextBelt.rot)
	local near = (lx == -wx and lz == -wz) and 0 or 1
	return { to = nextBelt, into = { near, near }, entry = 1 }
end

-- Which way each belt of the grid turns, [id] = Bend (see above), for drawing the corners.
function Logistics.Bends(objects)
	local belts = {}
	for _, o in ipairs(objects) do
		if o.kind == Items.Belt then
			belts[key(o.x, o.z)] = o
		end
	end
	local out = {}
	for _, o in pairs(belts) do
		out[o.id] = bend(belts, o)
	end
	return out
end

local function byTile(a, b)
	if a.z ~= b.z then
		return a.z < b.z
	end
	return a.x < b.x
end

-- The grid's belts (downstream first, so a full line of items moves all together), inserters and
-- the machines they reach.
local function build(objects, furnaces)
	local sorted = {}
	for _, o in ipairs(objects) do
		table.insert(sorted, o)
	end
	table.sort(sorted, byTile)

	local at = Logistics.Occupied(objects, furnaces)
	local belts = {}
	local beltList = {}
	for _, o in ipairs(sorted) do
		if o.kind == Items.Belt then
			local b = { id = o.id, x = o.x, z = o.z, rot = o.rot, slots = o.belt }
			belts[key(o.x, o.z)] = b
			table.insert(beltList, b)
		end
	end
	for _, b in ipairs(beltList) do
		b.out = connect(belts, b)
	end
	local order, seen = {}, {}
	local function downstream(b)
		if seen[b] then
			return
		end
		seen[b] = true
		if b.out then
			downstream(b.out.to)
		end
		table.insert(order, b)
	end
	for _, b in ipairs(beltList) do
		downstream(b)
	end

	local ports = {}
	local portList = {}
	local function portAt(x, z)
		local here = at[key(x, z)]
		if here == nil then
			return nil
		end
		local thing = here.object or here.furnace
		if ports[thing] == nil then
			if here.furnace then
				ports[thing] = furnacePort(here.furnace)
			elseif thing.kind == Items.WoodenChest then
				ports[thing] = chestPort(thing)
			elseif thing.machine then
				ports[thing] = machinePort(thing)
			elseif thing.generator then
				ports[thing] = generatorPort(thing)
			else
				return nil
			end
			table.insert(portList, ports[thing])
		end
		return ports[thing]
	end

	local inserters = {}
	for _, o in ipairs(sorted) do
		if o.kind == Items.Inserter then
			local dx, dz = Logistics.Facing(o.rot)
			local ins = { object = o, lanes = { 1, 0 } }
			ins.fromBelt = belts[key(o.x - dx, o.z - dz)]
			ins.toBelt = belts[key(o.x + dx, o.z + dz)]
			if ins.fromBelt == nil then
				ins.fromPort = portAt(o.x - dx, o.z - dz)
			end
			if ins.toBelt == nil then
				ins.toPort = portAt(o.x + dx, o.z + dz)
			else
				local lx, lz = Logistics.Left(ins.toBelt.rot)
				if lx == dx and lz == dz then
					-- Standing on the belt's right, it reaches over to the left lane first.
					ins.lanes = { 0, 1 }
				end
			end
			table.insert(inserters, ins)
		end
	end
	return { belts = order, inserters = inserters, ports = portList }
end

-- Notes that the item now in `slot` of belt `b` slid there from the place behind it, for drawing.
local function slid(net, b, slot)
	if net.watch then
		local marks = net.watch.slid[b.id]
		if marks == nil then
			marks = {}
			net.watch.slid[b.id] = marks
		end
		marks[slot] = true
	end
end

local size = Logistics.BeltSlots

-- Puts the item at the end of a lane on the belt it goes on to, when there is room there.
local function pass(net, b, lane, item)
	local link = b.out
	if link == nil then
		return false
	end
	local at = link.into[lane + 1] * size + link.entry + 1
	if link.to.slots[at] then
		return false
	end
	link.to.slots[at] = item
	slid(net, link.to, at)
	return true
end

local function moveBelts(net)
	local moved = false
	for _, b in ipairs(net.belts) do
		local slots = b.slots
		for lane = 0, Logistics.BeltLanes - 1 do
			local first = lane * size + 1
			local last = first + size - 1
			local leaving = slots[last]
			if leaving and pass(net, b, lane, leaving) then
				slots[last] = false
				moved = true
			end
			for i = last - 1, first, -1 do
				if slots[i] and not slots[i + 1] then
					slots[i + 1] = slots[i]
					slots[i] = false
					slid(net, b, i + 1)
					moved = true
				end
			end
		end
	end
	return moved
end

-- What an inserter picks up at `t`, taken from where it was; or nil.
local function pick(ins, t)
	local wanted
	if ins.toBelt then
		wanted = function()
			return true
		end
	elseif ins.toPort then
		wanted = function(item)
			return ins.toPort.Accepts(item, t)
		end
	else
		return nil
	end
	if ins.fromBelt then
		-- The item furthest along goes first, from either lane.
		local slots = ins.fromBelt.slots
		for i = size - 1, 0, -1 do
			for lane = 0, Logistics.BeltLanes - 1 do
				local at = lane * size + i + 1
				local item = slots[at]
				if item and wanted(item) then
					slots[at] = false
					return item
				end
			end
		end
		return nil
	end
	if ins.fromPort then
		local item = ins.fromPort.Output(wanted, t)
		if item then
			ins.fromPort.Take(item, t)
			return item
		end
	end
	return nil
end

-- Drops what an inserter holds where it takes it; true when it went.
local function drop(ins, item, t)
	if ins.toBelt then
		local slots = ins.toBelt.slots
		for _, lane in ipairs(ins.lanes) do
			for _, i in ipairs(DropOrder) do
				local at = lane * size + i + 1
				if not slots[at] then
					slots[at] = item
					return true
				end
			end
		end
		return false
	end
	if ins.toPort and ins.toPort.Accepts(item, t) then
		ins.toPort.Put(item, t)
		return true
	end
	return false
end

-- One tick at time `t`; true when anything moved.
local function step(net, t)
	if net.watch then
		net.watch.slid = {}
	end
	local moved = moveBelts(net)
	for _, ins in ipairs(net.inserters) do
		local o = ins.object
		if o.hand then
			if o.swing < Logistics.SwingTicks then
				o.swing = o.swing + 1
				moved = true
			elseif drop(ins, o.hand, t) then
				o.hand = nil
				moved = true
			end
		elseif o.swing > 0 then
			o.swing = o.swing - 1
			moved = true
		else
			local picked = pick(ins, t)
			if picked then
				o.hand = picked
				moved = true
			end
		end
	end
	return moved
end

-- Runs the grid from `from` (on the grid of ticks) up to `now`, changing the objects and furnaces in
-- place; returns the last tick worked out, the start of the next run. A `watch` table, if given,
-- gets `slid`: for the last tick worked out, [belt id] = { [slot] = true } for each item that slid
-- into its place from the one behind it (the rest were dropped there or did not move).
function Logistics.Run(objects, furnaces, from, now, watch)
	local tick = Logistics.Tick
	local steps = math.floor((now - from) / tick + 1e-6)
	if steps <= 0 then
		return from
	end
	local last = from + steps * tick
	local net = build(objects, furnaces)
	net.watch = watch
	if #net.belts == 0 and #net.inserters == 0 then
		return last
	end
	local k, worked = 0, 0
	while k < steps do
		k = k + 1
		local t = from + k * tick
		if step(net, t) then
			worked = worked + 1
			if worked >= Logistics.MaxTicks then
				return last
			end
		else
			-- Nothing moved, so nothing will until a furnace makes something new by itself.
			local due = nil
			for _, port in ipairs(net.ports) do
				local n = port.NextChange(t)
				if n and n > t and (due == nil or n < due) then
					due = n
				end
			end
			if due == nil or due > last then
				return last
			end
			-- Next step on the first tick at or after it, after a pause that starts the count anew.
			worked = 0
			k = math.max(k, math.ceil((due - from) / tick - 1e-6) - 1)
		end
	end
	return last
end

-- Runs the grid as Logistics.Run does, with power (Shared.Power): power stays the same between two
-- moments until a generator runs dry, so the time is cut in stretches; in each, machines work at the
-- speed their network gives them and the generators burn what it takes. `powerAt` is when power was
-- worked out until. Returns the new `at` (the last tick) and `powerAt`; a very long absence with
-- many generators running dry one after another may stop short of `now` (the next run goes on).
Logistics.MaxStretches = 100

function Logistics.RunPowered(objects, furnaces, at, powerAt, now, watch)
	local t = math.max(powerAt or at, at)
	for _ = 1, Logistics.MaxStretches do
		local nets = Power.Apply(objects, Logistics.Sizes, t)
		local dry = Power.Next(nets)
		local stop = now
		if dry and t + dry < now then
			stop = t + dry
		end
		at = Logistics.Run(objects, furnaces, at, stop, watch)
		Power.Run(nets, stop - t)
		t = stop
		if stop >= now then
			break
		end
	end
	return at, t
end

return Logistics
