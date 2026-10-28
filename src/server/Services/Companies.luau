-- Companies of players on every server (Shared.Companies). Each company is one key of a DataStore
-- and the directory of all of them another, changed only by UpdateAsync, so two servers never lose
-- each other's steps. Without DataStore access (Studio without API access) they live in this
-- server's memory.
--
-- A step goes like a step on the market (PlayerMarket): the player's side is taken with no yield
-- between the check and the change (money for founding or shares, items for an order), the step is
-- written down in the profile as pending, the key is updated, and the player gets what the step
-- gave or what was taken back. Founding takes two steps: the name in the directory, then the
-- company itself. A server that stops in the middle leaves the step pending in the saved profile;
-- when the player comes back, the key's memory of the step (Companies.Done) says which way it went.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Companies = require(Shared.Companies)
local Money = require(Shared.Money)
local Clock = require(script.Parent.Clock)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Wallet = require(script.Parent.Wallet)
local Net = require(script.Parent.Net)

local Service = {}

local StoreName = "FactoryWorld3D_companies_v1"
local DirectoryKey = "directory"
-- How often members' dividends are collected and their company looked at.
local RefreshSeconds = 60
-- A pending step this old was cut off, not still on its way.
local PendingSeconds = 60

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(StoreName)
end)
local memory = {} -- [key] = record, without DataStore
local cache = {} -- [key] = { record, at }
local busy = {} -- [Player] = true while a step is on its way

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
end)

local function companyKey(id)
	return "c_" .. id
end

local function apply(key, record, action)
	if key == DirectoryKey then
		return Companies.ApplyDirectory(record, action)
	end
	return Companies.Apply(record, action)
end

local function useMemory(err)
	if store and RunService:IsStudio() and tostring(err):find("API") then
		warn("[Companies] DataStore unavailable in Studio, companies live on this server only: " .. tostring(err))
		store = nil
		return true
	end
	return false
end

-- The record under `key`, read at most `maxAge` seconds ago: true and the record (nil when there is
-- none), or false when the DataStore does not answer.
local function read(key, maxAge)
	if store == nil then
		return true, memory[key]
	end
	local kept = cache[key]
	if kept and os.clock() - kept.at <= maxAge then
		return true, kept.record
	end
	local ok, record = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
		if useMemory(record) then
			return read(key, maxAge)
		end
		warn("[Companies] reading " .. key .. " failed: " .. tostring(record))
		if kept then
			return true, kept.record
		end
		return false, nil
	end
	cache[key] = { record = record, at = os.clock() }
	return true, record
end

-- Applies `action` to the record under `key`: true and the result, or false and an error code.
local function update(key, action)
	if store == nil then
		local record, result = apply(key, memory[key], action)
		if record == nil then
			return false, result
		end
		memory[key] = record
		return true, result
	end
	local result, code
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			local record, r = apply(key, old, action)
			if record == nil then
				result, code = nil, r
				return nil
			end
			result, code = r, nil
			cache[key] = { record = record, at = os.clock() }
			return record
		end)
	end)
	if not ok then
		if useMemory(err) then
			return update(key, action)
		end
		warn("[Companies] updating " .. key .. " failed: " .. tostring(err))
		return false, "company_unavailable"
	end
	if code then
		return false, code
	end
	return true, result
end

local function me(player)
	return tostring(player.UserId)
end

local function pending(profile)
	if profile.companyPending == nil then
		profile.companyPending = {}
	end
	return profile.companyPending
end

local run

-- What the player gets once the key took the step.
local function finish(player, profile, key, action, result)
	local kind = action.kind
	if kind == "add" then
		-- The name is theirs: now the company itself.
		run(player, profile, companyKey(action.id), {
			kind = "create", id = action.id, name = action.name, owner = action.owner,
			ownerName = action.ownerName, cents = action.cents, at = Clock.Now(),
		})
	elseif kind == "create" or kind == "join" then
		-- On a join `name` is the member's; the company's is in the record the step just wrote.
		local name = action.name
		if kind == "join" then
			local _, record = read(key, 60)
			name = record and record.name or "?"
		end
		profile.company = { id = action.id, name = name }
		if player and player.Parent then
			Net.Toast(player, (kind == "create" and "Założyłeś spółkę " or "Dołączyłeś do spółki ") .. name .. ".")
		end
	elseif kind == "leave" then
		if result.cents > 0 then
			Wallet.Credit(profile, result.cents, "company_left")
		end
		local company = profile.company
		profile.company = nil
		local _, record = read(key, 60)
		if record and record.closed and company then
			update(DirectoryKey, { tx = HttpService:GenerateGUID(false), kind = "remove", id = company.id })
		end
	elseif kind == "deposit" then
		if result.change > 0 then
			Wallet.Credit(profile, result.change, "company_change")
		end
	elseif kind == "sell" then
		Wallet.Credit(profile, result.cents, "company_shares_sold")
	elseif kind == "deliver" then
		if action.quantity > result.quantity then
			Inventory.Add(profile, action.item, action.quantity - result.quantity)
		end
	elseif kind == "collect" then
		Wallet.Credit(profile, result.cents, "company_dividend")
		if player and player.Parent then
			Net.Toast(player, "Spółka: +" .. Money.Format(result.cents) .. " dla Ciebie")
		end
	end
end

-- What the player gets back when the key said no.
local function refund(profile, action)
	local kind = action.kind
	if kind == "add" or kind == "create" then
		Wallet.Credit(profile, action.cents, "company_refund")
	elseif kind == "deposit" then
		Wallet.Credit(profile, action.cents, "company_refund")
	elseif kind == "deliver" then
		Inventory.Add(profile, action.item, action.quantity)
	end
end

-- Takes the step on the key, after the caller took the player's side; true or false and a code.
run = function(player, profile, key, action)
	local steps = pending(profile)
	action.tx = HttpService:GenerateGUID(false)
	action.at = action.at or Clock.Now()
	steps[action.tx] = { key = key, action = action, at = Clock.Now() }
	busy[player] = true
	local ok, result = update(key, action)
	busy[player] = nil
	steps[action.tx] = nil
	if ok then
		finish(player, profile, key, action, result)
	else
		refund(profile, action)
	end
	if player.Parent then
		Net.PushState(player)
	end
	return ok, result
end

-- Settles steps a stopped server left pending, by what the keys remember of them.
local function recover(player, profile)
	for tx, p in pairs(pending(profile)) do
		if Clock.Now() - p.at >= PendingSeconds then
			local ok, record = read(p.key, 0)
			if ok then
				pending(profile)[tx] = nil
				local done = Companies.Done(record, tx)
				if done then
					finish(player, profile, p.key, p.action, done.result)
				else
					refund(profile, p.action)
				end
			end
		end
	end
end

-- The player's company as last read (nil when they have none or it was not read yet).
local function cached(profile)
	if profile.company == nil then
		return nil
	end
	local kept = store == nil and { record = memory[companyKey(profile.company.id)] } or cache[companyKey(profile.company.id)]
	return kept and kept.record
end

-- Collects the player's dividends and notices when they were removed or the company closed.
local function refresh(player, profile, maxAge)
	if busy[player] or profile.company == nil then
		return
	end
	local key = companyKey(profile.company.id)
	local ok, record = read(key, maxAge)
	if not ok then
		return
	end
	local id = me(player)
	local owed = record and (record.owed[id] or 0) > 0
	if owed then
		owed = not run(player, profile, key, { kind = "collect", member = id })
	end
	-- Forgets the company only once nothing is left to collect from it.
	if not owed and (record == nil or record.closed or record.members[id] == nil) then
		if player.Parent and record then
			Net.Toast(player, "Nie jesteś już w spółce " .. record.name .. ".")
		end
		profile.company = nil
	end
end

-- Whether user `userId` is in the player's company (as last read; nothing yields).
function Service.IsMate(player, profile, userId)
	local record = cached(profile)
	return record ~= nil and tostring(userId) ~= me(player) and record.members[tostring(userId)] ~= nil
end

-- The other members of the player's company, as last read: { { id, name } }.
function Service.Mates(player, profile)
	local out = {}
	local record = cached(profile)
	if record then
		for id, m in pairs(record.members) do
			if id ~= me(player) and tonumber(id) then
				table.insert(out, { id = tonumber(id), name = m.name })
			end
		end
		table.sort(out, function(a, b)
			return a.name < b.name
		end)
	end
	return out
end

-- What the window shows.
local function view(player, profile)
	local now = Clock.Now()
	if profile.company == nil then
		local ok, directory = read(DirectoryKey, 15)
		if not ok then
			return Net.Error("company_unavailable")
		end
		local list = {}
		for _, e in ipairs((directory and directory.list) or {}) do
			table.insert(list, { id = e.id, name = e.name, ownerName = e.ownerName })
		end
		return { ok = true, list = list, foundingCents = Companies.FoundingCents }
	end
	local ok, c = read(companyKey(profile.company.id), 3)
	if not ok or c == nil then
		return Net.Error("company_unavailable")
	end
	local id = me(player)
	local members = {}
	for uid, m in pairs(c.members) do
		table.insert(members, { id = uid, name = m.name, shares = m.shares, owner = uid == c.owner, me = uid == id })
	end
	table.sort(members, function(a, b)
		if a.shares ~= b.shares then
			return a.shares > b.shares
		end
		return a.name < b.name
	end)
	local week = Companies.Week(now)
	local orders = {}
	for i, o in ipairs(Companies.Orders(c.id, week)) do
		table.insert(orders, { item = o.item, quantity = o.quantity, left = Companies.Left(c, i, now), rewardCents = o.rewardCents, sharesFor = Companies.SharePrice(c) })
	end
	local log = {}
	for i = #c.log, math.max(1, #c.log - 11), -1 do
		table.insert(log, c.log[i])
	end
	local shares, value = Companies.Stake(c, id)
	return {
		ok = true,
		company = {
			name = c.name,
			ownerName = c.ownerName,
			isOwner = c.owner == id,
			cashCents = c.cashCents,
			shares = c.shares,
			sharePriceCents = Companies.SharePrice(c),
			buybackPercent = Companies.BuybackPercent,
			myShares = shares,
			myValueCents = value,
			members = members,
			maxMembers = Companies.MaxMembers,
			orders = orders,
			weekEndsAt = (week + 1) * Companies.WeekSeconds,
			dividendReady = c.dividendDay ~= Companies.Day(now),
			dividendCents = math.floor(c.cashCents * Companies.DividendPercent / 100),
			dividendPercent = Companies.DividendPercent,
			log = log,
		},
		serverTime = now,
	}
end

-- Runs a step on the player's company and answers with the window; `prepare` takes the player's
-- side first and returns the action, or nil and an error code.
local function onCompany(prepare)
	return function(player, profile, payload)
		if profile.company == nil then
			return Net.Error("no_company")
		end
		if busy[player] then
			return Net.Error("company_busy")
		end
		local action, code = prepare(player, profile, payload)
		if action == nil then
			return Net.Error(code)
		end
		action.member = action.member or me(player)
		local ok, err = run(player, profile, companyKey(profile.company.id), action)
		if not ok then
			return Net.Error(err)
		end
		return view(player, profile)
	end
end

function Service.Start()
	Data.OnLoaded(function(player, profile)
		recover(player, profile)
		refresh(player, profile, 0)
	end)
	task.spawn(function()
		while true do
			task.wait(RefreshSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = Data.Get(player)
				if profile then
					task.spawn(function()
						recover(player, profile)
						refresh(player, profile, RefreshSeconds / 2)
					end)
				end
			end
		end
	end)

	Net.Handle("CompanyGet", function(player, profile)
		refresh(player, profile, 3)
		return view(player, profile)
	end)

	Net.Handle("CompanyCreate", function(player, profile, payload)
		if profile.company ~= nil then
			return Net.Error("in_company")
		end
		local name = Companies.CleanName(payload.name)
		if name == nil then
			return Net.Error("bad_name")
		end
		if busy[player] then
			return Net.Error("company_busy")
		end
		-- Everyone sees the name: Roblox's filter must leave it as it is.
		local filtered
		local ok = pcall(function()
			filtered = TextService:FilterStringAsync(name, player.UserId):GetNonChatStringForBroadcastAsync()
		end)
		if not ok or filtered ~= name then
			return Net.Error("bad_name")
		end
		if profile.company ~= nil then
			return Net.Error("in_company")
		end
		if busy[player] then
			return Net.Error("company_busy")
		end
		if not Wallet.TryDebit(profile, Companies.FoundingCents, "company_founding") then
			return Net.Error("not_enough_money")
		end
		local done, code = run(player, profile, DirectoryKey, {
			kind = "add", id = HttpService:GenerateGUID(false), name = name,
			owner = me(player), ownerName = player.Name, cents = Companies.FoundingCents,
		})
		if not done then
			return Net.Error(code)
		end
		if profile.company == nil then
			return Net.Error("company_unavailable")
		end
		return view(player, profile)
	end)

	Net.Handle("CompanyJoin", function(player, profile, payload)
		if profile.company ~= nil then
			return Net.Error("in_company")
		end
		if type(payload.id) ~= "string" or #payload.id > 64 then
			return Net.Error("bad_payload")
		end
		if busy[player] then
			return Net.Error("company_busy")
		end
		local ok, code = run(player, profile, companyKey(payload.id), {
			kind = "join", id = payload.id, name = player.Name, member = me(player),
		})
		if not ok then
			return Net.Error(code)
		end
		return view(player, profile)
	end)

	Net.Handle("CompanyLeave", onCompany(function()
		return { kind = "leave" }
	end))

	Net.Handle("CompanyKick", onCompany(function(_, _, payload)
		local target = Net.Int(payload.member, -1e12, 1e15)
		if target == nil then
			return nil, "bad_payload"
		end
		return { kind = "kick", target = tostring(target) }
	end))

	Net.Handle("CompanyDeposit", onCompany(function(_, profile, payload)
		local cents = Net.Int(payload.cents, 1, Companies.MaxDepositCents)
		if cents == nil then
			return nil, "bad_payload"
		end
		if not Wallet.TryDebit(profile, cents, "company_shares_bought") then
			return nil, "not_enough_money"
		end
		return { kind = "deposit", cents = cents }
	end))

	Net.Handle("CompanySell", onCompany(function(_, _, payload)
		local shares = Net.Int(payload.shares, 1, 1e12)
		if shares == nil then
			return nil, "bad_payload"
		end
		return { kind = "sell", shares = shares }
	end))

	Net.Handle("CompanyDeliver", onCompany(function(_, profile, payload)
		local order = Net.Int(payload.order, 1, Companies.OrdersPerWeek)
		local quantity = Net.Int(payload.quantity, 1, 100000)
		if order == nil or quantity == nil then
			return nil, "bad_payload"
		end
		local o = Companies.Orders(profile.company.id, Companies.Week(Clock.Now()))[order]
		quantity = math.min(quantity, Inventory.Count(profile, o.item))
		if quantity <= 0 or not Inventory.TryRemove(profile, o.item, quantity) then
			return nil, "not_enough_items"
		end
		return { kind = "deliver", order = order, item = o.item, quantity = quantity }
	end))

	Net.Handle("CompanyDividend", onCompany(function(player)
		return { kind = "dividend", owner = me(player) }
	end))
end

return Service
