-- The market between players (PlayerMarket.cs on main): each item has a book of offers shared by
-- every server. A listing holds items put up for sale (already out of the seller's inventory), an
-- order holds the money of a buyer (already out of their wallet). Other players take part of an
-- offer or all of it; what an owner earns waits in the book (`owed`) until their server collects
-- it, even while they are away. Every change is one step on one book (Market.Apply), so the
-- server can make it in a single atomic DataStore update. Pure functions: nothing yields.
--
-- A book: { listings = { offer }, orders = { offer }, nextId, owed = { [owner] = { cents, quantity } },
-- done = { { tx, result } } }, where an offer is { id, owner, name, quantity, left, priceCents, at }.
-- Owners are user ids written as strings (DataStore keys must be strings).
local Market = {}

-- Open listings, and separately open orders, one player may have at once.
Market.MaxOpenOffers = 20
Market.MaxQuantity = 10000
-- 1 000 000 $ a piece.
Market.MaxPriceCents = 100000000
-- How many offers of each kind the board of one item shows.
Market.BoardSize = 50
-- Steps remembered by their transaction id, so a server that lost the answer can find it.
Market.DoneKept = 1000

function Market.EmptyBook()
	return { listings = {}, orders = {}, nextId = 1, owed = {}, done = {} }
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

local function find(list, id)
	for i, offer in ipairs(list) do
		if offer.id == id then
			return i, offer
		end
	end
	return nil, nil
end

-- What step `tx` did, if the book remembers it: { tx, result }.
function Market.Done(book, tx)
	for _, entry in ipairs((book and book.done) or {}) do
		if entry.tx == tx then
			return entry
		end
	end
	return nil
end

-- The book after one step, and the step's result; or nil and an error code (the book is left as
-- it was). `action`: { tx, kind, ... } with kind
--   "list"/"order": owner, name, quantity, priceCents, at -> { id }
--   "buy"/"fill": taker, id, quantity, priceCents (the price the taker saw) -> { owner }
--   "cancel": owner, offerKind ("listing"/"order"), id -> { quantity, cents } given back
--   "collect": owner -> { cents, quantity } earned
function Market.Apply(book, action)
	local b = copy(book or Market.EmptyBook())
	if Market.Done(b, action.tx) then
		return nil, "duplicate"
	end
	local result
	local kind = action.kind
	if kind == "list" or kind == "order" then
		local list = kind == "list" and b.listings or b.orders
		local offer = {
			id = b.nextId,
			owner = action.owner,
			name = action.name,
			quantity = action.quantity,
			left = action.quantity,
			priceCents = action.priceCents,
			at = action.at,
		}
		b.nextId = b.nextId + 1
		table.insert(list, offer)
		result = { id = offer.id }
	elseif kind == "buy" or kind == "fill" then
		local list = kind == "buy" and b.listings or b.orders
		local i, offer = find(list, action.id)
		if offer == nil then
			return nil, "no_offer"
		elseif offer.owner == action.taker then
			return nil, "own_offer"
		elseif offer.priceCents ~= action.priceCents then
			return nil, "price_changed"
		elseif offer.left < action.quantity then
			return nil, "not_enough_offered"
		end
		offer.left = offer.left - action.quantity
		if offer.left == 0 then
			table.remove(list, i)
		end
		local owed = b.owed[offer.owner] or { cents = 0, quantity = 0 }
		if kind == "buy" then
			owed.cents = owed.cents + action.quantity * offer.priceCents
		else
			owed.quantity = owed.quantity + action.quantity
		end
		b.owed[offer.owner] = owed
		result = { owner = offer.owner }
	elseif kind == "cancel" then
		local list = action.offerKind == "listing" and b.listings or b.orders
		local i, offer = find(list, action.id)
		if offer == nil or offer.owner ~= action.owner then
			return nil, "no_offer"
		end
		table.remove(list, i)
		if action.offerKind == "listing" then
			result = { quantity = offer.left, cents = 0 }
		else
			result = { quantity = 0, cents = offer.left * offer.priceCents }
		end
	elseif kind == "collect" then
		local owed = b.owed[action.owner]
		if owed == nil or (owed.cents == 0 and owed.quantity == 0) then
			return nil, "nothing_owed"
		end
		b.owed[action.owner] = nil
		result = { cents = owed.cents, quantity = owed.quantity }
	else
		return nil, "bad_payload"
	end
	table.insert(b.done, { tx = action.tx, result = result })
	while #b.done > Market.DoneKept do
		table.remove(b.done, 1)
	end
	return b, result
end

local function sorted(list, better)
	local out = {}
	for _, offer in ipairs(list) do
		table.insert(out, offer)
	end
	table.sort(out, function(a, b)
		if a.priceCents ~= b.priceCents then
			return better(a.priceCents, b.priceCents)
		end
		return a.id < b.id
	end)
	while #out > Market.BoardSize do
		table.remove(out)
	end
	return out
end

-- The open offers to show: cheapest listings and best-paying orders first.
function Market.Board(book)
	book = book or Market.EmptyBook()
	return {
		listings = sorted(book.listings, function(a, b)
			return a < b
		end),
		orders = sorted(book.orders, function(a, b)
			return a > b
		end),
	}
end

-- The best prices and amounts: { lowestCents, listed, highestCents, wanted } (prices nil when none).
function Market.Summary(book)
	local s = { listed = 0, wanted = 0 }
	for _, offer in ipairs((book and book.listings) or {}) do
		s.listed = s.listed + offer.left
		s.lowestCents = math.min(s.lowestCents or offer.priceCents, offer.priceCents)
	end
	for _, offer in ipairs((book and book.orders) or {}) do
		s.wanted = s.wanted + offer.left
		s.highestCents = math.max(s.highestCents or offer.priceCents, offer.priceCents)
	end
	return s
end

-- The owner's open offers in the book, each with offerKind.
function Market.Mine(book, owner)
	local out = {}
	for _, pair in ipairs({ { "listing", "listings" }, { "order", "orders" } }) do
		for _, offer in ipairs((book and book[pair[2]]) or {}) do
			if offer.owner == owner then
				local o = copy(offer)
				o.offerKind = pair[1]
				table.insert(out, o)
			end
		end
	end
	return out
end

-- What waits in the book for `owner`: { cents, quantity } or nil.
function Market.Owed(book, owner)
	local owed = book and book.owed and book.owed[owner]
	if owed and (owed.cents > 0 or owed.quantity > 0) then
		return owed
	end
	return nil
end

return Market
