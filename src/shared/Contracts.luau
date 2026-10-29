-- Orders from NPC companies (Contracts and NpcContracts.cs on main): every player has Slots orders of
-- their own at a time, each for a number of pieces of one item before a deadline, for a reward paid
-- when the last piece arrives. Pieces may go in parts and wait on the order; if the player gives up
-- or the deadline passes they go back to the player. After an order ends, the next one comes Refill
-- seconds later. Orders only ask for what the player could make: items research still locks are left out.
local Items = require(script.Parent.Items)

local Contracts = {}

Contracts.Slots = 3
Contracts.Refill = 5 * 60

local Builders = { "Firma budowlana „Mur-Bud”", "Tartak „Leśny Dwór”", "Spółdzielnia „Pod Strzechą”" }
local Steelworks = { "Huta „Stal-Pol”", "Odlewnia „Żeliwiak”", "Kuźnia u Kowala Jana" }
local Bakers = { "Piekarnia „Złoty Kłos”", "Bar mleczny „Pod Kogutem”", "Stołówka szkolna nr 7" }
local Shops = { "Sklep „Społem”", "Targowisko miejskie", "Gospoda „Pod Lipą”" }
local Factories = { "Zakłady „Taśmex”", "Fabryka mebli „Dąb”", "Magazyny portowe w Gdyni" }

-- { item, min, max, step, cents per piece, hours, issuers }. A piece pays more than the merchant
-- gives for it and less than the merchant takes, so buying from him to deliver never pays (tests).
Contracts.Templates = {
	{ Items.Wood, 20, 80, 10, 400, 4, Builders },
	{ Items.Stone, 30, 120, 10, 200, 4, Builders },
	{ Items.Coal, 10, 50, 5, 800, 8, Steelworks },
	{ Items.IronOre, 10, 40, 5, 1200, 8, Steelworks },
	{ Items.CopperOre, 10, 30, 5, 2400, 8, Steelworks },
	{ Items.IronIngot, 10, 50, 5, 1800, 12, Steelworks },
	{ Items.CopperIngot, 10, 30, 5, 3200, 12, Steelworks },
	{ Items.Nails, 20, 100, 10, 450, 8, Builders },
	{ Items.Belt, 8, 32, 4, 900, 12, Factories },
	{ Items.WoodenChest, 1, 4, 1, 6500, 24, Factories },
	{ Items.Planks, 20, 100, 10, 250, 8, Builders },
	{ Items.Beams, 5, 30, 5, 1200, 12, Builders },
	{ Items.StoneBlocks, 10, 40, 5, 900, 12, Builders },
	{ Items.Bricks, 20, 80, 10, 220, 12, Builders },
	{ Items.SteelIngot, 5, 20, 5, 6000, 24, Factories },
	{ Items.Wheat, 20, 100, 10, 120, 6, Bakers },
	{ Items.Carrot, 10, 60, 10, 180, 6, Shops },
	{ Items.Potato, 10, 50, 10, 300, 8, Shops },
	{ Items.Cabbage, 10, 40, 5, 500, 8, Shops },
	{ Items.Flour, 10, 40, 5, 380, 12, Bakers },
	{ Items.Bread, 5, 20, 5, 1400, 12, Bakers },
}

function Contracts.New()
	return { list = {}, nextId = 1 }
end

-- A new order for an item not in `avoid` (a set) whose `unlocked(item)` is true, appearing at `at`.
-- `roll(a, b)` gives a whole number from a to b (the server's Random).
local function make(state, avoid, unlocked, roll, at)
	local free, open = {}, {}
	for _, t in ipairs(Contracts.Templates) do
		if unlocked(t[1]) then
			table.insert(open, t)
			if not avoid[t[1]] then
				table.insert(free, t)
			end
		end
	end
	local pool = #free > 0 and free or open
	local t = pool[roll(1, #pool)]
	local quantity = t[2] + roll(0, math.floor((t[3] - t[2]) / t[4])) * t[4]
	local order = {
		id = state.nextId,
		item = t[1],
		quantity = quantity,
		delivered = 0,
		rewardCents = quantity * t[5],
		issuer = t[7][roll(1, #t[7])],
		createdAt = at,
		deadline = at + t[6] * 3600,
	}
	state.nextId = state.nextId + 1
	table.insert(state.list, order)
	return order
end

local function items(state, also)
	local set = {}
	for _, o in ipairs(state.list) do
		set[o.item] = true
	end
	if also then
		set[also] = true
	end
	return set
end

local function find(state, id)
	for i, o in ipairs(state.list) do
		if o.id == id then
			return o, i
		end
	end
	return nil
end

-- Ends the orders past their deadline and gives the player new ones up to Slots. Returns the pieces
-- that go back to the player: a list of { item, quantity }.
function Contracts.Refresh(state, now, unlocked, roll)
	local back = {}
	for i = #state.list, 1, -1 do
		local o = state.list[i]
		if o.deadline <= now then
			table.remove(state.list, i)
			if o.delivered > 0 then
				table.insert(back, { o.item, o.delivered })
			end
		end
	end
	while #state.list < Contracts.Slots do
		make(state, items(state), unlocked, roll, now)
	end
	return back
end

-- The orders the player sees now and when the next waiting one appears (nil if none waits).
function Contracts.Open(state, now)
	local open, nextAt = {}, nil
	for _, o in ipairs(state.list) do
		if o.createdAt <= now then
			table.insert(open, o)
		elseif nextAt == nil or o.createdAt < nextAt then
			nextAt = o.createdAt
		end
	end
	return open, nextAt
end

-- The order that replaces a finished or abandoned one, for another item, after Refill.
local function replace(state, o, now, unlocked, roll)
	make(state, items(state, o.item), unlocked, roll, now + Contracts.Refill)
end

-- Puts up to `quantity` pieces on order `id`, of `have` the player has. Returns how many it took and
-- the order, or nil and an error code. The caller takes the pieces from the inventory; when the
-- order is complete (order.delivered == order.quantity) it is gone and the caller pays the reward.
function Contracts.Deliver(state, id, quantity, have, now, unlocked, roll)
	local o = find(state, id)
	if o == nil or o.createdAt > now then
		return nil, "no_contract"
	end
	if o.deadline <= now then
		return nil, "contract_expired"
	end
	local give = math.min(quantity, have, o.quantity - o.delivered)
	if give <= 0 then
		return nil, "not_enough_items"
	end
	o.delivered = o.delivered + give
	if o.delivered >= o.quantity then
		local _, i = find(state, id)
		table.remove(state.list, i)
		replace(state, o, now, unlocked, roll)
	end
	return give, o
end

-- Gives up order `id`. Returns the order (its delivered pieces go back to the player), or nil and a code.
function Contracts.Drop(state, id, now, unlocked, roll)
	local o, i = find(state, id)
	if o == nil or o.createdAt > now then
		return nil, "no_contract"
	end
	table.remove(state.list, i)
	replace(state, o, now, unlocked, roll)
	return o
end

return Contracts
