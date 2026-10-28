-- The market between players on every server (Shared.Market). Each item's book is one key of a
-- DataStore, changed only by UpdateAsync, so two servers never lose each other's steps. Without
-- DataStore access (Studio without API access) the books live in this server's memory.
--
-- A step goes in three parts. First the player's side is taken with no yield between the check
-- and the change (items for a listing or a sale, money for an order or a purchase), and the step
-- is written down in the profile as pending. Then the book is updated. Then the player gets what
-- the step gave, or what was taken back if the book said no. A server that stops in the middle
-- leaves the step pending in the saved profile; when the player comes back, the book's memory of
-- the step (Market.Done) says which way it went.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Market = require(Shared.Market)
local Money = require(Shared.Money)
local Research = require(Shared.Research)
local Clock = require(script.Parent.Clock)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Wallet = require(script.Parent.Wallet)
local Net = require(script.Parent.Net)

local PlayerMarket = {}

local StoreName = "FactoryWorld3D_market_v1"
-- How often a player's earnings are collected from the books, and every book is read for the list.
local CollectSeconds = 60
local SummarySeconds = 120
-- A pending step this old was cut off, not still on its way.
local PendingSeconds = 60

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(StoreName)
end)
local memory = {} -- [item] = book, without DataStore
local cache = {} -- [item] = { book, at }
local busy = {} -- [Player] = true while a step is on its way

local function useMemory(err)
	if store and RunService:IsStudio() and tostring(err):find("API") then
		warn("[Market] DataStore unavailable in Studio, the market lives on this server only: " .. tostring(err))
		store = nil
		return true
	end
	return false
end

-- The item's book, read at most `maxAge` seconds ago; nil when the DataStore does not answer.
local function read(item, maxAge)
	if store == nil then
		return memory[item] or Market.EmptyBook()
	end
	local kept = cache[item]
	if kept and os.clock() - kept.at <= maxAge then
		return kept.book
	end
	local ok, book = pcall(function()
		return store:GetAsync(item)
	end)
	if not ok then
		if useMemory(book) then
			return read(item, maxAge)
		end
		warn("[Market] reading " .. item .. " failed: " .. tostring(book))
		return kept and kept.book
	end
	book = book or Market.EmptyBook()
	cache[item] = { book = book, at = os.clock() }
	return book
end

-- Applies `action` to the item's book: true and the result, or false and an error code.
local function update(item, action)
	if store == nil then
		local book, result = Market.Apply(memory[item], action)
		if book == nil then
			return false, result
		end
		memory[item] = book
		return true, result
	end
	local result, code
	local ok, err = pcall(function()
		store:UpdateAsync(item, function(old)
			local book, r = Market.Apply(old, action)
			if book == nil then
				result, code = nil, r
				return nil
			end
			result, code = r, nil
			cache[item] = { book = book, at = os.clock() }
			return book
		end)
	end)
	if not ok then
		if useMemory(err) then
			return update(item, action)
		end
		warn("[Market] updating " .. item .. " failed: " .. tostring(err))
		return false, "market_unavailable"
	end
	if code then
		return false, code
	end
	return true, result
end

local function owner(player)
	return tostring(player.UserId)
end

local function state(profile)
	if profile.market == nil then
		profile.market = {}
	end
	local m = profile.market
	m.items = m.items or {} -- [item] = true: books where the player has offers or earnings
	m.offers = m.offers or {} -- { item, offerKind, id }: the player's open offers, as last seen
	m.pending = m.pending or {} -- [tx] = { item, action, at }
	return m
end

-- What the player gets once the book took the step.
local function finish(player, profile, item, action, result)
	local m = state(profile)
	local kind = action.kind
	if kind == "list" or kind == "order" then
		table.insert(m.offers, { item = item, offerKind = kind == "list" and "listing" or "order", id = result.id })
		m.items[item] = true
	elseif kind == "buy" then
		Inventory.Add(profile, item, action.quantity)
	elseif kind == "fill" then
		Wallet.Credit(profile, action.quantity * action.priceCents, "market_filled:" .. item)
	elseif kind == "cancel" then
		for i, o in ipairs(m.offers) do
			if o.item == item and o.offerKind == action.offerKind and o.id == action.id then
				table.remove(m.offers, i)
				break
			end
		end
		if result.quantity > 0 then
			Inventory.Add(profile, item, result.quantity)
		end
		if result.cents > 0 then
			Wallet.Credit(profile, result.cents, "market_cancelled:" .. item)
		end
	elseif kind == "collect" then
		local parts = {}
		if result.cents > 0 then
			Wallet.Credit(profile, result.cents, "market_sold:" .. item)
			table.insert(parts, "+" .. Money.Format(result.cents) .. " za " .. Items.Name(item))
		end
		if result.quantity > 0 then
			Inventory.Add(profile, item, result.quantity)
			table.insert(parts, "+" .. result.quantity .. " × " .. Items.Name(item))
		end
		if player then
			Net.Toast(player, "Rynek: " .. table.concat(parts, ", "))
		end
	end
end

-- What the player gets back when the book said no.
local function refund(profile, item, action)
	local kind = action.kind
	if kind == "list" or kind == "fill" then
		Inventory.Add(profile, item, action.quantity)
	elseif kind == "order" or kind == "buy" then
		Wallet.Credit(profile, action.quantity * action.priceCents, "market_refund:" .. item)
	end
end

-- Takes the step on the book, after the caller took the player's side; true or false and a code.
local function run(player, profile, item, action)
	local m = state(profile)
	action.tx = HttpService:GenerateGUID(false)
	m.pending[action.tx] = { item = item, action = action, at = Clock.Now() }
	busy[player] = true
	local ok, result = update(item, action)
	busy[player] = nil
	m.pending[action.tx] = nil
	if ok then
		finish(player, profile, item, action, result)
	else
		refund(profile, item, action)
	end
	if player.Parent then
		Net.PushState(player)
	end
	return ok, result
end

-- Settles steps a stopped server left pending, by what the books remember of them.
local function recover(player, profile)
	local m = state(profile)
	for tx, p in pairs(m.pending) do
		if Clock.Now() - p.at >= PendingSeconds then
			local book = read(p.item, 0)
			if book then
				local done = Market.Done(book, tx)
				if done then
					finish(player, profile, p.item, p.action, done.result)
				else
					refund(profile, p.item, p.action)
				end
				m.pending[tx] = nil
			end
		end
	end
end

-- Collects what the player earned on the books and forgets offers that are gone.
local function collect(player, profile)
	if busy[player] then
		return
	end
	local m = state(profile)
	local id = owner(player)
	for item in pairs(m.items) do
		local book = read(item, 20)
		if book and Market.Owed(book, id) then
			run(player, profile, item, { kind = "collect", owner = id })
			book = read(item, 20)
		end
		if book then
			local open = {}
			for _, o in ipairs(Market.Mine(book, id)) do
				open[o.offerKind .. ":" .. o.id] = true
			end
			for i = #m.offers, 1, -1 do
				local o = m.offers[i]
				if o.item == item and not open[o.offerKind .. ":" .. o.id] then
					table.remove(m.offers, i)
				end
			end
			if next(open) == nil and not Market.Owed(book, id) then
				m.items[item] = nil
			end
		end
	end
end

local function countOpen(profile, offerKind)
	local n = 0
	for _, o in ipairs(state(profile).offers) do
		if o.offerKind == offerKind then
			n = n + 1
		end
	end
	return n
end

-- The list of every item with its best prices, as last read.
local function summary(profile)
	local now = Clock.Now()
	local items = {}
	for _, item in ipairs(Items.Order) do
		local kept = store == nil and { book = memory[item] } or cache[item]
		local s = Market.Summary(kept and kept.book)
		s.item = item
		s.locked = not Research.Unlocked(profile.research, item, now)
		table.insert(items, s)
	end
	return items
end

local function board(player, profile, item, maxAge)
	local book = read(item, maxAge)
	if book == nil then
		return Net.Error("market_unavailable")
	end
	local id = owner(player)
	local b = Market.Board(book)
	local function public(list)
		local out = {}
		for _, o in ipairs(list) do
			table.insert(out, { id = o.id, left = o.left, priceCents = o.priceCents, name = o.name, mine = o.owner == id })
		end
		return out
	end
	return {
		ok = true,
		item = item,
		listings = public(b.listings),
		orders = public(b.orders),
		summary = summary(profile),
	}
end

-- Checks shared by every step that names an item, a quantity and a price.
local function offerPayload(payload)
	local item = Net.Item(payload.item)
	local quantity = Net.Int(payload.quantity, 1, Market.MaxQuantity)
	local price = Net.Int(payload.priceCents, 1, Market.MaxPriceCents)
	return item, quantity, price
end

function PlayerMarket.Start()
	Data.OnLoaded(function(player, profile)
		recover(player, profile)
		collect(player, profile)
	end)
	-- Earnings come in while the player plays, even when the buyer is on another server.
	task.spawn(function()
		while true do
			task.wait(CollectSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = Data.Get(player)
				if profile then
					task.spawn(function()
						recover(player, profile)
						collect(player, profile)
					end)
				end
			end
		end
	end)
	-- Every book is read now and then for the list of best prices.
	task.spawn(function()
		while true do
			if store then
				for _, item in ipairs(Items.Order) do
					read(item, SummarySeconds / 2)
					task.wait(SummarySeconds / #Items.Order)
				end
			else
				task.wait(SummarySeconds)
			end
		end
	end)

	Net.Handle("MarketGet", function(player, profile)
		task.spawn(collect, player, profile)
		return { ok = true, items = summary(profile), maxOffers = Market.MaxOpenOffers }
	end)

	Net.Handle("MarketBoard", function(player, profile, payload)
		local item = Net.Item(payload.item)
		if item == nil then
			return Net.Error("bad_payload")
		end
		if not Research.Unlocked(profile.research, item, Clock.Now()) then
			return Net.Error("not_researched")
		end
		return board(player, profile, item, 3)
	end)

	Net.Handle("MarketMine", function(player, profile)
		collect(player, profile)
		local id = owner(player)
		local offers = {}
		for _, o in ipairs(state(profile).offers) do
			local book = read(o.item, 20)
			for _, mine in ipairs(Market.Mine(book, id)) do
				if mine.offerKind == o.offerKind and mine.id == o.id then
					table.insert(offers, {
						item = o.item, offerKind = o.offerKind, id = o.id,
						quantity = mine.quantity, left = mine.left, priceCents = mine.priceCents,
					})
				end
			end
		end
		return { ok = true, offers = offers, maxOffers = Market.MaxOpenOffers }
	end)

	-- Puts items up for sale (kind "list") or orders them (kind "order").
	local function offer(kind)
		return function(player, profile, payload)
			local item, quantity, price = offerPayload(payload)
			if item == nil or quantity == nil or price == nil then
				return Net.Error("bad_payload")
			end
			if busy[player] then
				return Net.Error("market_busy")
			end
			local offerKind = kind == "list" and "listing" or "order"
			if countOpen(profile, offerKind) >= Market.MaxOpenOffers then
				return Net.Error("too_many_offers")
			end
			if kind == "list" then
				if not Inventory.TryRemove(profile, item, quantity) then
					return Net.Error("not_enough_items")
				end
			else
				if not Research.Unlocked(profile.research, item, Clock.Now()) then
					return Net.Error("not_researched")
				end
				if not Wallet.TryDebit(profile, quantity * price, "market_order:" .. item) then
					return Net.Error("not_enough_money")
				end
			end
			local ok, code = run(player, profile, item, {
				kind = kind, owner = owner(player), name = player.Name, quantity = quantity, priceCents = price, at = Clock.Now(),
			})
			if not ok then
				return Net.Error(code)
			end
			return board(player, profile, item, 0)
		end
	end
	Net.Handle("MarketList", offer("list"))
	Net.Handle("MarketOrder", offer("order"))

	-- Buys from a listing (kind "buy") or sells into an order (kind "fill").
	local function take(kind)
		return function(player, profile, payload)
			local item, quantity, price = offerPayload(payload)
			local id = Net.Int(payload.id, 1, 2 ^ 50)
			if item == nil or quantity == nil or price == nil or id == nil then
				return Net.Error("bad_payload")
			end
			if busy[player] then
				return Net.Error("market_busy")
			end
			if kind == "buy" then
				if not Research.Unlocked(profile.research, item, Clock.Now()) then
					return Net.Error("not_researched")
				end
				if not Wallet.TryDebit(profile, quantity * price, "market_buy:" .. item) then
					return Net.Error("not_enough_money")
				end
			elseif not Inventory.TryRemove(profile, item, quantity) then
				return Net.Error("not_enough_items")
			end
			local ok, code = run(player, profile, item, {
				kind = kind, taker = owner(player), id = id, quantity = quantity, priceCents = price,
			})
			if not ok then
				return Net.Error(code)
			end
			return board(player, profile, item, 0)
		end
	end
	Net.Handle("MarketBuy", take("buy"))
	Net.Handle("MarketFill", take("fill"))

	Net.Handle("MarketCancel", function(player, profile, payload)
		local item = Net.Item(payload.item)
		local id = Net.Int(payload.id, 1, 2 ^ 50)
		local offerKind = payload.offerKind
		if item == nil or id == nil or (offerKind ~= "listing" and offerKind ~= "order") then
			return Net.Error("bad_payload")
		end
		if busy[player] then
			return Net.Error("market_busy")
		end
		local ok, code = run(player, profile, item, { kind = "cancel", owner = owner(player), offerKind = offerKind, id = id })
		if not ok then
			return Net.Error(code)
		end
		return { ok = true }
	end)
end

return PlayerMarket
