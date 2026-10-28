-- Power on the plot's build grid, as on main (PowerRules in Grid.cs). A generator burns coal, wood
-- or pellets and gives up to GeneratorKw; a pole powers the tiles around it (SupplyRadius each
-- way) and is wired to every pole up to WireReach tiles away. Poles wired together make one
-- network: its generators share the load of all the machines on it. Machines draw their power
-- whenever they stand on a network, busy or not; with too little power they all work slower, and
-- without any they stop (Processing speed). Nothing runs in a loop: between two moments the power
-- of a network stays the same until its first generator runs dry (Power.Next), so the grid is
-- worked out in stretches (server Factory.CatchUp).
--
-- A generator on the grid keeps `generator` = { fuelItem, fuel (pieces not burning yet), energy
-- (kJ left in the piece burning now) }.
local Items = require(script.Parent.Items)
local Processing = require(script.Parent.Processing)

local Power = {}

Power.GeneratorKw = 100
-- Pieces of fuel a generator holds.
Power.MaxFuel = 50
-- A pole powers a square of tiles this far from it each way: 5 × 5 tiles.
Power.SupplyRadius = 2
-- Poles at most this many tiles apart are wired together.
Power.WireReach = 7

-- The energy (kJ) in one piece: coal lasts 200 s at full power, wood 50 s, a pellet 40 s.
Power.Fuels = {
	[Items.Coal] = 20000,
	[Items.Wood] = 5000,
	[Items.WoodPellets] = 4000,
}

-- Machines that run on power, and what they draw (kW).
Power.Demand = {
	[Items.Crusher] = 40,
}

-- Less than this is nothing (what is left after sums of fractions).
local Spent = 1e-6

function Power.EmptyGenerator()
	return { fuelItem = nil, fuel = 0, energy = 0 }
end

-- kJ left in a generator, the fuel not burning yet included.
function Power.Total(g)
	return g.energy + (g.fuelItem and g.fuel * (Power.Fuels[g.fuelItem] or 0) or 0)
end

function Power.Running(g)
	return Power.Total(g) > Spent
end

-- The generator after giving `kj`: the burning piece first, then more pieces lit one by one.
function Power.Burn(g, kj)
	if kj <= g.energy then
		return { fuelItem = g.fuelItem, fuel = g.fuel, energy = g.energy - kj }
	end
	local piece = g.fuelItem and Power.Fuels[g.fuelItem] or 0
	local needed = kj - g.energy
	if piece <= 0 or needed >= g.fuel * piece - Spent then
		return Power.EmptyGenerator()
	end
	local lit = math.ceil(needed / piece - 1e-9)
	local left = g.fuel - lit
	return { fuelItem = left > 0 and g.fuelItem or nil, fuel = left, energy = lit * piece - needed }
end

-- Pieces of `item` the generator takes now.
function Power.Room(g, item)
	if Power.Fuels[item] == nil or (g.fuelItem ~= nil and g.fuelItem ~= item and g.fuel > 0) then
		return 0
	end
	return Power.MaxFuel - g.fuel
end

-- The generator with `quantity` more of `item` by the fire; or nil and an error code.
function Power.Load(g, item, quantity)
	if Power.Fuels[item] == nil then
		return nil, "not_fuel"
	elseif g.fuelItem ~= nil and g.fuelItem ~= item and g.fuel > 0 then
		return nil, "generator_busy"
	elseif g.fuel + quantity > Power.MaxFuel then
		return nil, "generator_full"
	end
	return { fuelItem = item, fuel = g.fuel + quantity, energy = g.energy }
end

-- Whether a pole powers an object `size` tiles across: it reaches any tile the object covers.
function Power.Covers(pole, o, size)
	local r = Power.SupplyRadius
	return o.x <= pole.x + r and o.x + size - 1 >= pole.x - r and o.z <= pole.z + r and o.z + size - 1 >= pole.z - r
end

function Power.Wired(a, b)
	local dx, dz = a.x - b.x, a.z - b.z
	return dx * dx + dz * dz <= Power.WireReach * Power.WireReach
end

-- The networks of a grid: poles wired together, with the generators and machines they power.
-- Something within reach of poles of two networks belongs to the one of the first pole (by z,
-- then x). Each is { poles, generators, consumers, demand (kW) }. `sizes`: tiles across of each
-- kind (Logistics.Sizes).
function Power.Networks(objects, sizes)
	local poles = {}
	for _, o in ipairs(objects) do
		if o.kind == Items.Pole then
			table.insert(poles, o)
		end
	end
	table.sort(poles, function(a, b)
		if a.z ~= b.z then
			return a.z < b.z
		end
		return a.x < b.x
	end)
	local component = {}
	local nets = {}
	for i, pole in ipairs(poles) do
		if component[i] == nil then
			local net = { poles = {}, generators = {}, consumers = {}, demand = 0 }
			table.insert(nets, net)
			component[i] = net
			local queue = { i }
			while #queue > 0 do
				local at = table.remove(queue)
				table.insert(net.poles, poles[at])
				for j, other in ipairs(poles) do
					if component[j] == nil and Power.Wired(poles[at], other) then
						component[j] = net
						table.insert(queue, j)
					end
				end
			end
		end
	end
	for _, o in ipairs(objects) do
		if o.kind == Items.Generator or Power.Demand[o.kind] then
			for i, pole in ipairs(poles) do
				if Power.Covers(pole, o, sizes[o.kind] or 1) then
					local net = component[i]
					if o.kind == Items.Generator then
						table.insert(net.generators, o)
					else
						table.insert(net.consumers, o)
						net.demand = net.demand + Power.Demand[o.kind]
					end
					break
				end
			end
		end
	end
	return nets
end

-- What a network's running generators can give together (kW).
function Power.Supply(net)
	local kw = 0
	for _, g in ipairs(net.generators) do
		if Power.Running(g.generator) then
			kw = kw + Power.GeneratorKw
		end
	end
	return kw
end

-- How fast the network's machines work: 1 with enough power, less with too little, 0 without.
function Power.Speed(net)
	if net.demand <= 0 then
		return 1
	end
	return math.min(1, Power.Supply(net) / net.demand)
end

-- What each running generator of the network gives now (kW): the load shared among them.
local function share(net)
	local running = 0
	for _, g in ipairs(net.generators) do
		if Power.Running(g.generator) then
			running = running + 1
		end
	end
	if running == 0 or net.demand <= 0 then
		return 0
	end
	return math.min(net.demand, running * Power.GeneratorKw) / running
end

-- Seconds until the first running generator with a load runs dry, or nil when none will.
function Power.Next(nets)
	local soonest = nil
	for _, net in ipairs(nets) do
		local kw = share(net)
		if kw > 0 then
			for _, g in ipairs(net.generators) do
				if Power.Running(g.generator) then
					local left = Power.Total(g.generator) / kw
					if soonest == nil or left < soonest then
						soonest = left
					end
				end
			end
		end
	end
	return soonest
end

-- Burns what the networks give in `seconds` (no generator runs dry within them: see Power.Next).
function Power.Run(nets, seconds)
	if seconds <= 0 then
		return
	end
	for _, net in ipairs(nets) do
		local kw = share(net)
		if kw > 0 then
			for _, g in ipairs(net.generators) do
				if Power.Running(g.generator) then
					g.generator = Power.Burn(g.generator, kw * seconds)
				end
			end
		end
	end
end

-- Sets how fast every machine that runs on power works from time `now`, by its network; one on
-- no network stops. Returns the networks.
function Power.Apply(objects, sizes, now)
	local nets = Power.Networks(objects, sizes)
	local speeds = {}
	for _, net in ipairs(nets) do
		local speed = Power.Speed(net)
		for _, o in ipairs(net.consumers) do
			speeds[o] = speed
		end
	end
	for _, o in ipairs(objects) do
		if Power.Demand[o.kind] and o.machine then
			o.machine = Processing.SetSpeed(o.kind, o.machine, speeds[o] or 0, now)
		end
	end
	return nets
end

-- The wires to draw: pairs of poles, the shortest ones that join each network (a pole wired to
-- every pole in reach would make a tangle).
function Power.Wires(objects)
	local poles = {}
	for _, o in ipairs(objects) do
		if o.kind == Items.Pole then
			table.insert(poles, o)
		end
	end
	local pairs_ = {}
	for i = 1, #poles do
		for j = i + 1, #poles do
			if Power.Wired(poles[i], poles[j]) then
				local dx, dz = poles[i].x - poles[j].x, poles[i].z - poles[j].z
				table.insert(pairs_, { poles[i], poles[j], dx * dx + dz * dz })
			end
		end
	end
	table.sort(pairs_, function(a, b)
		if a[3] ~= b[3] then
			return a[3] < b[3]
		end
		if a[1].id ~= b[1].id then
			return a[1].id < b[1].id
		end
		return a[2].id < b[2].id
	end)
	local root = {}
	local function find(o)
		while root[o] do
			o = root[o]
		end
		return o
	end
	local out = {}
	for _, pair in ipairs(pairs_) do
		local a, b = find(pair[1]), find(pair[2])
		if a ~= b then
			root[a] = b
			table.insert(out, { pair[1], pair[2] })
		end
	end
	return out
end

-- The network an object is on, if any.
function Power.NetworkOf(nets, o)
	for _, net in ipairs(nets) do
		for _, list in ipairs({ net.poles, net.generators, net.consumers }) do
			for _, other in ipairs(list) do
				if other == o then
					return net
				end
			end
		end
	end
	return nil
end

return Power
