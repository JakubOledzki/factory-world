-- The railway (Railway.cs on main): every plot has a station. Goods loaded into it, by hand or by
-- inserters, can be sent by train to the station of another player, on any server; the train
-- takes time and costs a fee by distance, and the goods wait in the other station until its owner
-- unloads them. A route sends a train by itself every few minutes with what the station holds.
--
-- Shipments on their way wait in the receiver's inbox, one DataStore key per player, changed by
-- one step at a time (Rail.Apply) so the server can make it in a single atomic update. An inbox:
-- { shipments = { { tx, from, fromName, items = { { item, quantity } }, sentAt, arriveAt } },
-- done = { { tx, result } } }. Pure functions: nothing yields.
local WorldMap = require(script.Parent.WorldMap)

local Rail = {}

-- The station's kind on the build grid: a fixture of every plot, 3 × 3 tiles, never picked up.
Rail.StationKind = "rail_station"
Rail.StationName = "Stacja kolejowa"

-- Real seconds a train needs per 100 km, and the shortest trip.
Rail.SecondsPer100Km = 5
Rail.MinTrip = 10
-- Fee: a fixed part plus cents per item per 100 km.
Rail.BaseFeeCents = 100
Rail.CentsPerItemPer100Km = 1
Rail.MaxQuantity = 100000
-- Most items one train of a route carries.
Rail.RouteCapacity = 2000
-- How often a route's train may leave, in minutes.
Rail.RouteMinutes = { 1, 5, 15, 60 }
Rail.MaxRoutes = 5
Rail.MaxRouteItems = 8
-- Trains between the plots of one player (Shared.Lands): every one takes this long and costs the
-- fixed part of the fee only. A destination of such a train is "plot:" and the plot's id.
Rail.OwnTrip = 20
Rail.PlotPrefix = "plot:"

-- The plot a destination names, or nil when it is another player.
function Rail.PlotOf(to)
	if type(to) == "string" and string.sub(to, 1, #Rail.PlotPrefix) == Rail.PlotPrefix then
		return string.sub(to, #Rail.PlotPrefix + 1)
	end
	return nil
end

-- Inserters stop putting an item into the station when it holds this many of it.
Rail.InserterStockLimit = 10000
-- Trains on their way to one station at most, and steps an inbox remembers by transaction id.
Rail.MaxShipments = 200
Rail.DoneKept = 200

-- The world players' stations stand in (Shared.WorldMap); each player's station has its own place
-- on its land, always the same.
Rail.WorldKm = WorldMap.Km

local function hash(n)
	local state = (n % 2147483646) + 1
	for _ = 1, 4 do
		state = (state * 16807) % 2147483647
	end
	return state / 2147483647
end

-- Where the station of player `userId` stands in the world, in km.
function Rail.Location(userId)
	local id = math.abs(math.floor(tonumber(userId) or 0))
	return WorldMap.Land(hash(id) * Rail.WorldKm.width, (0.1 + 0.8 * hash(id + 7919)) * Rail.WorldKm.height)
end

-- Km between two players' stations, wrapping east-west.
function Rail.DistanceKm(fromId, toId)
	local ax, ay = Rail.Location(fromId)
	local bx, by = Rail.Location(toId)
	local dx = math.abs(ax - bx)
	dx = math.min(dx, Rail.WorldKm.width - dx)
	return math.sqrt(dx * dx + (ay - by) * (ay - by))
end

function Rail.TripSeconds(km)
	return math.max(Rail.MinTrip, math.floor(km / 100 * Rail.SecondsPer100Km + 0.5))
end

function Rail.FeeCents(km, quantity)
	return Rail.BaseFeeCents + math.ceil(km / 100 * quantity * Rail.CentsPerItemPer100Km - 1e-9)
end

-- Items of a station's stock (a table [item] = quantity) in a steady order: by id.
function Rail.Items(stock)
	local out = {}
	for item, quantity in pairs(stock) do
		if quantity > 0 then
			table.insert(out, item)
		end
	end
	table.sort(out)
	return out
end

-- What a train of a route takes from the stock: only the route's items (all when it has none), in
-- the route's order, then by id, up to Rail.RouteCapacity. A list of { item, quantity }.
function Rail.Cargo(stock, items)
	local order
	if items and #items > 0 then
		order = items
	else
		order = Rail.Items(stock)
	end
	local cargo = {}
	local room = Rail.RouteCapacity
	for _, item in ipairs(order) do
		local take = math.min(room, stock[item] or 0)
		if take > 0 then
			table.insert(cargo, { item, take })
			room = room - take
		end
	end
	return cargo
end

function Rail.Count(cargo)
	local n = 0
	for _, entry in ipairs(cargo) do
		n = n + entry[2]
	end
	return n
end

function Rail.Add(stock, item, quantity)
	stock[item] = (stock[item] or 0) + quantity
end

-- Takes up to `quantity` of `item` from the stock; returns how many it took.
function Rail.Take(stock, item, quantity)
	local taken = math.min(quantity, stock[item] or 0)
	if taken > 0 then
		stock[item] = stock[item] - taken
		if stock[item] == 0 then
			stock[item] = nil
		end
	end
	return math.max(taken, 0)
end

function Rail.EmptyInbox()
	return { shipments = {}, done = {} }
end

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = copy(v)
	end
	return out
end

-- What step `tx` did, if the inbox remembers it: { tx, result }.
function Rail.Done(inbox, tx)
	for _, entry in ipairs((inbox and inbox.done) or {}) do
		if entry.tx == tx then
			return entry
		end
	end
	return nil
end

-- The inbox after one step, and the step's result; or nil and an error code (the inbox is left as
-- it was). `action`: { tx, kind, ... } with kind
--   "open": the owner's station is ready to receive -> {}
--   "ship": from, fromName, items, sentAt, arriveAt -> {} (the inbox must be open: "no_station")
--   "collect": now -> { shipments } that have arrived, taken out of the inbox
function Rail.Apply(inbox, action)
	if action.kind == "open" then
		return inbox or Rail.EmptyInbox(), {}
	end
	if inbox == nil then
		return nil, "no_station"
	end
	local b = copy(inbox)
	if Rail.Done(b, action.tx) then
		return nil, "duplicate"
	end
	local result
	if action.kind == "ship" then
		if #b.shipments >= Rail.MaxShipments then
			return nil, "station_busy"
		end
		table.insert(b.shipments, {
			tx = action.tx,
			from = action.from,
			fromName = action.fromName,
			items = action.items,
			sentAt = action.sentAt,
			arriveAt = action.arriveAt,
		})
		result = {}
	elseif action.kind == "collect" then
		local arrived, waiting = {}, {}
		for _, s in ipairs(b.shipments) do
			table.insert(s.arriveAt <= action.now and arrived or waiting, s)
		end
		if #arrived == 0 then
			return nil, "nothing_arrived"
		end
		b.shipments = waiting
		result = { shipments = arrived }
	else
		return nil, "bad_payload"
	end
	table.insert(b.done, { tx = action.tx, result = result })
	while #b.done > Rail.DoneKept do
		table.remove(b.done, 1)
	end
	return b, result
end

-- Whether any shipment in the inbox has arrived by `now`.
function Rail.Arrived(inbox, now)
	for _, s in ipairs((inbox and inbox.shipments) or {}) do
		if s.arriveAt <= now then
			return true
		end
	end
	return false
end

return Rail
