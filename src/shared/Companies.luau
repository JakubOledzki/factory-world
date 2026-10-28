-- Companies (Companies.cs and CompanyEconomyRules.cs on main): players on any server found a
-- company together. Its money is the members' shares: a member buys new shares at the share
-- price (the company's cash per share, at least MinSharePriceCents) and sells them back to the
-- company for a little less. Each week the company gets orders for goods; members deliver them
-- from their inventories, the company is paid more than the merchant would pay, and the one who
-- delivered gets shares worth what the merchant pays, so the rest raises the price of everyone's
-- shares. Once a day the owner can pay part of the cash out to all members by their shares. Big
-- projects (BigProjects in CompanyEconomyRules.cs) take thousands of parts from the members and a
-- day or two to build, and then help every member: more members, more orders, cheaper trains
-- between members (Shared.Rail).
--
-- Each company is one DataStore key, changed one step at a time (Companies.Apply), and a directory
-- key lists every company by name (Companies.ApplyDirectory), so the server can make each step in
-- a single atomic update. Members are user ids written as strings. Pure functions: nothing yields.
--
-- A company: { id, name, owner, ownerName, members = { [userId] = { name, shares, joinedAt } },
-- shares, cashCents, owed = { [userId] = cents }, week, delivered = { [order] = quantity },
-- dividendDay, project = { id, delivered = { [item] = quantity }, readyAt }, built = { [id] = at },
-- log = { { at, text } }, closed, done = { { tx, result } } }.
local Items = require(script.Parent.Items)
local Money = require(script.Parent.Money)
local Prices = require(script.Parent.Prices)

local Companies = {}

-- What founding a company costs: it all goes into the company's cash, for the founder's shares.
Companies.FoundingCents = 1000000
Companies.FounderShares = 1000
Companies.MinSharePriceCents = 100
-- A member selling shares gets this percent of the share price.
Companies.BuybackPercent = 95
-- The owner pays out this percent of the cash once a day.
Companies.DividendPercent = 20
Companies.MaxMembers = 10
Companies.MaxMembersWithHq = 20
Companies.NameMin = 3
Companies.NameMax = 24
-- Most a member puts in at once, in cents.
Companies.MaxDepositCents = 100000000000
-- Orders each week (more with a warehouse), and how much more than the merchant they pay.
Companies.OrdersPerWeek = 3
Companies.OrdersWithWarehouse = 5
Companies.RewardPercent = 160
Companies.WeekSeconds = 7 * 24 * 3600
Companies.DaySeconds = 24 * 3600
-- What orders ask for, and the merchant's value of one order between these (cents).
Companies.OrderItems = {
	Items.Wood, Items.Stone, Items.Coal, Items.IronOre, Items.CopperOre, Items.Planks, Items.Beams,
	Items.StoneBlocks, Items.IronIngot, Items.CopperIngot, Items.TinIngot, Items.SilverIngot,
	Items.Nails, Items.Bricks, Items.BronzeIngot, Items.SteelIngot,
}
Companies.OrderValueCents = { 100000, 400000 }
-- The big projects, in the order the window shows them. `parts` are { item, quantity }; `hours` the
-- time it takes to build once every part is in; `requires` a project built before.
Companies.Projects = {
	{
		id = "hq",
		name = "Siedziba spółki",
		text = "Biuro spółki. Spółka może mieć do 20 wspólników zamiast 10.",
		parts = { { Items.StoneBlocks, 500 }, { Items.Beams, 400 }, { Items.Bricks, 200 }, { Items.IronIngot, 150 } },
		hours = 24,
	},
	{
		id = "warehouse",
		name = "Magazyn spółki",
		text = "Co tydzień 5 zleceń zamiast 3.",
		parts = { { Items.Planks, 2000 }, { Items.IronIngot, 800 }, { Items.CopperIngot, 500 }, { Items.BronzeIngot, 200 } },
		hours = 24,
		requires = "hq",
	},
	{
		id = "railway",
		name = "Kolej spółki",
		text = "Pociągi między wspólnikami płacą o 30% mniej za odległość, także na trasach.",
		parts = { { Items.SteelIngot, 600 }, { Items.Beams, 1500 }, { Items.StoneBlocks, 1000 }, { Items.Bricks, 400 } },
		hours = 48,
		requires = "hq",
	},
}

function Companies.Project(id)
	for _, p in ipairs(Companies.Projects) do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- Whether the company has project `id` built by `now`.
function Companies.Built(company, id, now)
	if company.built and company.built[id] then
		return true
	end
	local p = company.project
	return p ~= nil and p.id == id and p.readyAt ~= nil and p.readyAt <= now
end

function Companies.MaxMembersOf(company, now)
	return Companies.Built(company, "hq", now) and Companies.MaxMembersWithHq or Companies.MaxMembers
end

function Companies.OrderCount(company, now)
	return Companies.Built(company, "warehouse", now) and Companies.OrdersWithWarehouse or Companies.OrdersPerWeek
end

-- How many of `item` the company's project still needs (0 when the project does not take it).
function Companies.Needed(company, item)
	local p = company.project
	local info = p and Companies.Project(p.id)
	if info == nil or p.readyAt then
		return 0
	end
	for _, part in ipairs(info.parts) do
		if part[1] == item then
			return part[2] - (p.delivered[item] or 0)
		end
	end
	return 0
end

Companies.LogKept = 30
Companies.DoneKept = 300
Companies.DirectoryMax = 500

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

local function remember(record, tx, result)
	table.insert(record.done, { tx = tx, result = result })
	while #record.done > Companies.DoneKept do
		table.remove(record.done, 1)
	end
end

-- What step `tx` did, if the record (a company or the directory) remembers it: { tx, result }.
function Companies.Done(record, tx)
	for _, entry in ipairs((record and record.done) or {}) do
		if entry.tx == tx then
			return entry
		end
	end
	return nil
end

-- The name the player typed, trimmed, or nil when it is too short or too long.
function Companies.CleanName(text)
	if type(text) ~= "string" then
		return nil
	end
	local name = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	name = string.gsub(name, "%s+", " ")
	local length = utf8 and utf8.len(name) or #name
	if length == nil or length < Companies.NameMin or length > Companies.NameMax then
		return nil
	end
	return name
end

function Companies.Week(now)
	return math.floor(now / Companies.WeekSeconds)
end

function Companies.Day(now)
	return math.floor(now / Companies.DaySeconds)
end

-- The price of one new share, in cents.
function Companies.SharePrice(company)
	if company.shares <= 0 then
		return Companies.MinSharePriceCents
	end
	return math.max(Companies.MinSharePriceCents, math.floor(company.cashCents / company.shares))
end

-- What the company pays for `n` of its shares sold back.
function Companies.BuybackCents(company, n)
	if company.shares <= 0 or n <= 0 then
		return 0
	end
	return math.min(company.cashCents, math.floor(company.cashCents * (n / company.shares) * Companies.BuybackPercent / 100))
end

local function seeded(text)
	local state = 17
	for i = 1, #text do
		state = (state * 31 + string.byte(text, i)) % 2147483647
	end
	return function(n)
		state = (state * 16807) % 2147483647
		return state % n
	end
end

-- The orders of company `id` in week `week`, always the same: { { item, quantity, rewardCents } },
-- rewardCents for one piece. As many as a company with a warehouse gets; the first
-- OrdersPerWeek are the same either way (Companies.OrderCount says how many a company has).
function Companies.Orders(id, week)
	local random = seeded(tostring(id) .. ":" .. tostring(week))
	local pool = {}
	for _, item in ipairs(Companies.OrderItems) do
		if Prices.Buys[item] then
			table.insert(pool, item)
		end
	end
	local orders = {}
	while #orders < Companies.OrdersWithWarehouse and #pool > 0 do
		local item = table.remove(pool, random(#pool) + 1)
		local unit = Prices.Buys[item]
		local low, high = Companies.OrderValueCents[1], Companies.OrderValueCents[2]
		local value = low + random(high - low + 1)
		local quantity = math.max(5, math.min(2000, math.floor(value / unit / 5 + 0.5) * 5))
		table.insert(orders, { item = item, quantity = quantity, rewardCents = math.floor(unit * Companies.RewardPercent / 100) })
	end
	return orders
end

-- How many of order `index` are still wanted this week.
function Companies.Left(company, index, now)
	local order = Companies.Orders(company.id, Companies.Week(now))[index]
	if order == nil or index > Companies.OrderCount(company, now) then
		return 0
	end
	local delivered = 0
	if company.week == Companies.Week(now) then
		delivered = company.delivered[index] or 0
	end
	return order.quantity - delivered
end

local function log(c, at, text)
	table.insert(c.log, { at = at, text = text })
	while #c.log > Companies.LogKept do
		table.remove(c.log, 1)
	end
end

local function addShares(c, member, n)
	local m = c.members[member]
	m.shares = m.shares + n
	c.shares = c.shares + n
end

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

-- The company after one step, and the step's result; or nil and an error code (the company is
-- left as it was). `action`: { tx, kind, at, ... } with kind
--   "create": id, name, owner, ownerName, cents -> {} (a company that does not exist yet)
--   "join": member, name -> {}
--   "leave": member -> { cents } (shares sold back; the owner leaves last and closes the company)
--   "kick": owner, member -> {} (the member's shares are sold back into `owed`)
--   "deposit": member, cents -> { shares, cents } bought, and `change` of the cents put in
--   "sell": member, shares -> { cents }
--   "deliver": member, order, quantity -> { quantity, shares } taken of the quantity brought
--   "dividend": owner -> { cents } paid out into `owed`
--   "project": owner, project -> {} (starts a big project; one at a time)
--   "contribute": member, item, quantity -> { quantity } taken for the project
--   "collect": member -> { cents } owed to them (also after they left)
function Companies.Apply(company, action)
	if action.kind == "create" then
		if company ~= nil then
			return nil, "duplicate"
		end
		local c = {
			id = action.id,
			name = action.name,
			owner = action.owner,
			ownerName = action.ownerName,
			members = { [action.owner] = { name = action.ownerName, shares = Companies.FounderShares, joinedAt = action.at } },
			shares = Companies.FounderShares,
			cashCents = action.cents,
			owed = {},
			week = Companies.Week(action.at),
			delivered = {},
			dividendDay = nil,
			log = {},
			done = {},
		}
		log(c, action.at, action.ownerName .. " zakłada spółkę.")
		remember(c, action.tx, {})
		return c, {}
	end
	if company == nil then
		return nil, "no_company"
	end
	local c = copy(company)
	if Companies.Done(c, action.tx) then
		return nil, "duplicate"
	end
	c.built = c.built or {}
	if c.project and c.project.readyAt and c.project.readyAt <= action.at then
		c.built[c.project.id] = c.project.readyAt
		c.project = nil
	end
	local kind = action.kind
	local member = action.member or action.owner
	local m = c.members[member]
	if kind ~= "collect" then
		if c.closed then
			return nil, "company_closed"
		end
		if kind ~= "join" and m == nil then
			return nil, "not_member"
		end
		if (kind == "kick" or kind == "dividend" or kind == "project") and member ~= c.owner then
			return nil, "not_owner"
		end
	end
	local result
	if kind == "join" then
		if m ~= nil then
			return nil, "already_member"
		end
		if count(c.members) >= Companies.MaxMembersOf(c, action.at) then
			return nil, "company_full"
		end
		c.members[member] = { name = action.name, shares = 0, joinedAt = action.at }
		log(c, action.at, action.name .. " dołącza do spółki.")
		result = {}
	elseif kind == "leave" then
		local cents
		if member == c.owner then
			if count(c.members) > 1 then
				return nil, "owner_cannot_leave"
			end
			cents = c.cashCents
			c.cashCents = 0
			c.shares = 0
			c.closed = true
		else
			cents = Companies.BuybackCents(c, m.shares)
			c.cashCents = c.cashCents - cents
			c.shares = c.shares - m.shares
		end
		cents = cents + (c.owed[member] or 0)
		c.owed[member] = nil
		c.members[member] = nil
		log(c, action.at, m.name .. (c.closed and " zamyka spółkę." or " odchodzi ze spółki."))
		result = { cents = cents }
	elseif kind == "kick" then
		local target = c.members[action.target]
		if target == nil or action.target == c.owner then
			return nil, "not_member"
		end
		local cents = Companies.BuybackCents(c, target.shares)
		c.cashCents = c.cashCents - cents
		c.shares = c.shares - target.shares
		c.owed[action.target] = (c.owed[action.target] or 0) + cents
		c.members[action.target] = nil
		log(c, action.at, target.name .. " zostaje usunięty ze spółki.")
		result = {}
	elseif kind == "deposit" then
		local price = Companies.SharePrice(c)
		local shares = math.floor(action.cents / price)
		if shares <= 0 then
			return nil, "too_little"
		end
		local cents = shares * price
		c.cashCents = c.cashCents + cents
		addShares(c, member, shares)
		log(c, action.at, m.name .. " kupuje " .. shares .. " udziałów za " .. Money.Format(cents) .. ".")
		result = { shares = shares, cents = cents, change = action.cents - cents }
	elseif kind == "sell" then
		local n = action.shares
		if n > m.shares then
			return nil, "not_enough_shares"
		end
		if member == c.owner and n >= m.shares then
			return nil, "owner_keeps_share"
		end
		local cents = Companies.BuybackCents(c, n)
		c.cashCents = c.cashCents - cents
		m.shares = m.shares - n
		c.shares = c.shares - n
		log(c, action.at, m.name .. " sprzedaje " .. n .. " udziałów za " .. Money.Format(cents) .. ".")
		result = { cents = cents }
	elseif kind == "deliver" then
		local week = Companies.Week(action.at)
		if c.week ~= week then
			c.week = week
			c.delivered = {}
		end
		local order = Companies.Orders(c.id, week)[action.order]
		if order == nil or action.order > Companies.OrderCount(c, action.at) then
			return nil, "bad_payload"
		end
		local taken = math.min(action.quantity, order.quantity - (c.delivered[action.order] or 0))
		if taken <= 0 then
			return nil, "order_done"
		end
		-- Shares for what the merchant would pay, at the price before the reward comes in.
		local shares = math.floor(taken * Prices.Buys[order.item] / Companies.SharePrice(c))
		c.delivered[action.order] = (c.delivered[action.order] or 0) + taken
		c.cashCents = c.cashCents + taken * order.rewardCents
		addShares(c, member, shares)
		log(c, action.at, m.name .. " oddaje " .. taken .. " × " .. Items.Name(order.item) .. " do zlecenia.")
		result = { quantity = taken, shares = shares }
	elseif kind == "dividend" then
		local day = Companies.Day(action.at)
		if c.dividendDay == day then
			return nil, "dividend_today"
		end
		local pool = math.floor(c.cashCents * Companies.DividendPercent / 100)
		local paid = 0
		for id, mm in pairs(c.members) do
			local part = math.floor(pool * (mm.shares / c.shares))
			if part > 0 then
				c.owed[id] = (c.owed[id] or 0) + part
				paid = paid + part
			end
		end
		if paid <= 0 then
			return nil, "nothing_to_pay"
		end
		c.cashCents = c.cashCents - paid
		c.dividendDay = day
		log(c, action.at, "Dywidenda: " .. Money.Format(paid) .. " dla wspólników.")
		result = { cents = paid }
	elseif kind == "project" then
		local info = Companies.Project(action.project)
		if info == nil then
			return nil, "bad_payload"
		end
		if c.built[info.id] then
			return nil, "project_built"
		end
		if c.project then
			return nil, "project_busy"
		end
		if info.requires and not c.built[info.requires] then
			return nil, "project_locked"
		end
		c.project = { id = info.id, delivered = {} }
		log(c, action.at, "Spółka zaczyna projekt: " .. info.name .. ".")
		result = {}
	elseif kind == "contribute" then
		if c.project == nil then
			return nil, "no_project"
		end
		if c.project.readyAt then
			return nil, "project_building"
		end
		local taken = math.min(action.quantity, Companies.Needed(c, action.item))
		if taken <= 0 then
			return nil, "part_done"
		end
		c.project.delivered[action.item] = (c.project.delivered[action.item] or 0) + taken
		local info = Companies.Project(c.project.id)
		log(c, action.at, m.name .. " oddaje " .. taken .. " × " .. Items.Name(action.item) .. " na projekt.")
		local complete = true
		for _, part in ipairs(info.parts) do
			if (c.project.delivered[part[1]] or 0) < part[2] then
				complete = false
			end
		end
		if complete then
			c.project.readyAt = action.at + info.hours * 3600
			log(c, action.at, "Wszystkie części są. Budowa: " .. info.name .. " (" .. info.hours .. " h).")
		end
		result = { quantity = taken }
	elseif kind == "collect" then
		local cents = c.owed[member] or 0
		if cents <= 0 then
			return nil, "nothing_owed"
		end
		c.owed[member] = nil
		result = { cents = cents }
	else
		return nil, "bad_payload"
	end
	remember(c, action.tx, result)
	return c, result
end

function Companies.EmptyDirectory()
	return { list = {}, done = {} }
end

local function lower(name)
	return string.lower(name)
end

-- The directory after one step: "add" (id, name, ownerName) or "remove" (id); or nil and a code.
function Companies.ApplyDirectory(directory, action)
	local d = copy(directory or Companies.EmptyDirectory())
	if Companies.Done(d, action.tx) then
		return nil, "duplicate"
	end
	if action.kind == "add" then
		if #d.list >= Companies.DirectoryMax then
			return nil, "too_many_companies"
		end
		for _, e in ipairs(d.list) do
			if lower(e.name) == lower(action.name) then
				return nil, "name_taken"
			end
		end
		table.insert(d.list, { id = action.id, name = action.name, ownerName = action.ownerName })
	elseif action.kind == "remove" then
		for i, e in ipairs(d.list) do
			if e.id == action.id then
				table.remove(d.list, i)
				break
			end
		end
	else
		return nil, "bad_payload"
	end
	remember(d, action.tx, {})
	return d, {}
end

-- A member's part of the company, as the windows show it.
function Companies.Stake(company, member)
	local m = company.members[member]
	if m == nil or company.shares <= 0 then
		return 0, 0
	end
	return m.shares, Companies.BuybackCents(company, m.shares)
end

return Companies
