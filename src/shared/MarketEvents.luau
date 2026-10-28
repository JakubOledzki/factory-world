-- The merchant's calendar and prices, as on main (MarketEvents.cs), the same on every server:
-- time is cut into slots of SlotLength, and a hash of the slot's number picks its event, or a
-- calm one. On top of that, what the merchant pays for each item drifts by up to Drift percent,
-- a new target every day, changing hour by hour. What it charges only changes with events.
-- Nothing is stored: any time has its prices, so players can see the next event coming.
local Items = require(script.Parent.Items)
local Prices = require(script.Parent.Prices)

local MarketEvents = {}

MarketEvents.SlotLength = 6 * 3600
-- The most the merchant's buying prices drift, in percent, either way.
MarketEvents.Drift = 10
-- The merchant always pays at most this many percent of what it charges for the same item.
MarketEvents.MaxPayOfCharge = 90
-- Of every #Events + CalmWeight slots, about this many have no event.
local CalmWeight = 7

local function all(items, percent)
	local changes = {}
	for _, item in ipairs(items) do
		changes[item] = percent
	end
	return changes
end

-- Ids are only shown, never saved. `pays`: how much more (or less) the merchant pays for these
-- items, in percent; `charges`: how much more (or less) it charges.
MarketEvents.Events = {
	{
		id = "steel_boom",
		name = "Boom na stal",
		description = "Huty nie nadążają z zamówieniami. Ruda żelaza, sztabki, stal i gwoździe są w cenie.",
		pays = { [Items.IronOre] = 50, [Items.CrushedIronOre] = 50, [Items.IronIngot] = 60, [Items.SteelIngot] = 40, [Items.Nails] = 40 },
		charges = {},
	},
	{
		id = "building_boom",
		name = "Boom budowlany",
		description = "Wszyscy budują. Drewno, deski, belki, kamień, piasek, bloki i cegły schodzą na pniu.",
		pays = {
			[Items.Wood] = 50, [Items.Planks] = 50, [Items.Beams] = 50, [Items.Stone] = 50, [Items.Sand] = 80,
			[Items.StoneBlocks] = 40, [Items.Bricks] = 40,
		},
		charges = {},
	},
	{
		id = "winter",
		name = "Sroga zima",
		description = "Mróz trzyma od tygodnia. Węgiel, drewno i pellet na opał drożeją.",
		pays = { [Items.Coal] = 80, [Items.Wood] = 30, [Items.WoodPellets] = 50 },
		charges = {},
	},
	{
		id = "copper_rush",
		name = "Gorączka miedzi",
		description = "Elektrownie kupują kable. Handlarz płaci więcej za miedź.",
		pays = { [Items.CopperOre] = 50, [Items.CrushedCopperOre] = 50, [Items.CopperIngot] = 50 },
		charges = {},
	},
	{
		id = "bronze_fashion",
		name = "Moda na brąz",
		description = "Wszyscy chcą brązowych dzwonów i pomników. Cyna i brąz są w cenie.",
		pays = { [Items.TinOre] = 50, [Items.CrushedTinOre] = 50, [Items.TinIngot] = 50, [Items.BronzeIngot] = 50 },
		charges = {},
	},
	{
		id = "gold_rush",
		name = "Gorączka złota",
		description = "Niepewne czasy, ludzie uciekają w kruszce. Złoto i srebro drożeją.",
		pays = { [Items.GoldOre] = 40, [Items.GoldIngot] = 40, [Items.SilverOre] = 25, [Items.SilverIngot] = 25 },
		charges = {},
	},
	{
		id = "stone_glut",
		name = "Zalew kamienia",
		description = "Nowy kamieniołom zasypał rynek. Za kamień, piasek i bloki handlarz płaci mniej.",
		pays = { [Items.Stone] = -40, [Items.Sand] = -40, [Items.StoneBlocks] = -25 },
		charges = {},
	},
	{
		id = "machine_sale",
		name = "Wyprzedaż maszyn",
		description = "Handlarz czyści magazyn. Maszyny, piece, taśmy, podajniki i skrzynie są o ćwierć tańsze.",
		pays = {},
		charges = all({
			Items.Furnace, Items.Belt, Items.Inserter, Items.WoodenChest,
			Items.Sawmill, Items.Stonemason, Items.Crusher, Items.Foundry, Items.Mill, Items.Bakery,
		}, -25),
	},
}

-- A well-mixed whole number from 0 to 2^31 - 2 for any whole number, the same on every machine.
-- (Park-Miller steps: every product stays below 2^53, so doubles keep it exact.)
local Modulus = 2147483647
local function hash(n)
	local x = n % Modulus
	for round = 1, 4 do
		x = (x * 48271 + 12345 * round) % Modulus
		x = (x * 16807 + round) % Modulus
	end
	return x
end

local function text(s)
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % Modulus
	end
	return h
end

local function slot(now)
	return math.floor(now / MarketEvents.SlotLength)
end

local function pick(n)
	local events = MarketEvents.Events
	local i = hash(n * 7 + 5) % (#events + CalmWeight) + 1
	return events[i]
end

-- The event at time `now` (Unix seconds) as { event, startsAt, endsAt }, or nil when the market
-- is calm. An event that already ran in the slot before is over: the market calms down.
function MarketEvents.At(now)
	local s = slot(now)
	local e = pick(s)
	if e == nil or pick(s - 1) == e then
		return nil
	end
	return { event = e, startsAt = s * MarketEvents.SlotLength, endsAt = (s + 1) * MarketEvents.SlotLength }
end

-- The next event that starts after `now`, looking a few days ahead.
function MarketEvents.Next(now)
	local start = (slot(now) + 1) * MarketEvents.SlotLength
	for _ = 1, 16 do
		local e = MarketEvents.At(start)
		if e then
			return e
		end
		start = start + MarketEvents.SlotLength
	end
	return nil
end

local function target(seed, day)
	local span = 2 * MarketEvents.Drift * 100 + 1
	return hash(seed + day * 7919) % span / 100 - MarketEvents.Drift
end

-- The drift of what the merchant pays for `item` at `now`, in percent: a straight line, hour by
-- hour, between one day's target and the next.
function MarketEvents.DriftAt(item, now)
	local hours = math.floor(now / 3600)
	local day = math.floor(hours / 24)
	local hour = hours - day * 24
	local seed = text(item)
	local a, b = target(seed, day), target(seed, day + 1)
	return a + (b - a) * hour / 24
end

local function apply(cents, percent)
	return math.max(1, math.floor(cents * (100 + percent) / 100 + 0.5))
end

-- The merchant's prices at `now`: { sells, buys } in cents (what it charges and what it pays,
-- like Shared.Prices) and the event, if any.
function MarketEvents.Prices(now)
	local current = MarketEvents.At(now)
	local e = current and current.event
	local sells, buys = {}, {}
	for item, cents in pairs(Prices.Sells) do
		sells[item] = apply(cents, e and e.charges[item] or 0)
	end
	for item, cents in pairs(Prices.Buys) do
		local drifted = math.floor(cents * (1 + MarketEvents.DriftAt(item, now) / 100) + 0.5)
		local price = apply(drifted, e and e.pays[item] or 0)
		if sells[item] then
			price = math.min(price, math.floor(sells[item] * MarketEvents.MaxPayOfCharge / 100))
		end
		buys[item] = price
	end
	return { sells = sells, buys = buys, event = current }
end

-- How far a price is from the usual one, in whole percent.
function MarketEvents.Change(cents, usual)
	return math.floor((cents - usual) * 100 / usual + 0.5)
end

return MarketEvents
