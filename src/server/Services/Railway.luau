-- The railway between players' stations on every server (Shared.Rail). Each player's inbox of
-- trains on their way is one key of a DataStore, changed only by UpdateAsync. Without DataStore
-- access (Studio without API access) the inboxes live in this server's memory.
--
-- A train goes like a step of the market (PlayerMarket): first the goods leave the station and
-- the fee the wallet, with no yield between the check and the change, and the step is written down
-- in the profile as pending; then the receiver's inbox is updated; then the train is on its way,
-- or the goods and the fee come back if the inbox said no. Trains that have arrived are collected
-- the same way into the receiver's station. A server that stops in the middle leaves the step
-- pending in the saved profile, and the inbox's memory of it (Rail.Done) settles it later.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Lands = require(Shared.Lands)
local Logistics = require(Shared.Logistics)
local Money = require(Shared.Money)
local PlotLayout = require(Shared.PlotLayout)
local Rail = require(Shared.Rail)
local Clock = require(script.Parent.Clock)
local Data = require(script.Parent.Data)
local Factory = require(script.Parent.Factory)
local Grid = require(script.Parent.Grid)
local Inventory = require(script.Parent.Inventory)
local Net = require(script.Parent.Net)
local Plots = require(script.Parent.Plots)
local Wallet = require(script.Parent.Wallet)

local Railway = {}

local StoreName = "FactoryWorld3D_rail_v1"
-- How often arrived trains are looked for, and routes looked at.
local CollectSeconds = 15
local RouteSeconds = 5
-- A pending step this old was cut off, not still on its way.
local PendingSeconds = 60
-- Lines of the station's log kept.
local LogKept = 12

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(StoreName)
end)
local memory = {} -- [key] = inbox, without DataStore
local cache = {} -- [key] = { inbox, at }
local busy = {} -- [Player] = true while a step is on its way
local found = {} -- [Player] = { [userId] = name }: players found to send to
local trains = 0

local function key(userId)
	return "in_" .. tostring(userId)
end

local function useMemory(err)
	if store and RunService:IsStudio() and tostring(err):find("API") then
		warn("[Rail] DataStore unavailable in Studio, trains run on this server only: " .. tostring(err))
		store = nil
		return true
	end
	return false
end

-- The player's inbox read at most `maxAge` seconds ago: true and the inbox (nil when the player
-- has no station yet), or false when the DataStore does not answer.
local function read(userId, maxAge)
	local k = key(userId)
	if store == nil then
		return true, memory[k]
	end
	local kept = cache[k]
	if kept and os.clock() - kept.at <= maxAge then
		return true, kept.inbox
	end
	local ok, inbox = pcall(function()
		return store:GetAsync(k)
	end)
	if not ok then
		if useMemory(inbox) then
			return read(userId, maxAge)
		end
		warn("[Rail] reading " .. k .. " failed: " .. tostring(inbox))
		return false, nil
	end
	cache[k] = { inbox = inbox, at = os.clock() }
	return true, inbox
end

-- Applies `action` to the player's inbox: true and the result, or false and an error code.
local function update(userId, action)
	local k = key(userId)
	if store == nil then
		local inbox, result = Rail.Apply(memory[k], action)
		if inbox == nil then
			return false, result
		end
		memory[k] = inbox
		return true, result
	end
	local result, code
	local ok, err = pcall(function()
		store:UpdateAsync(k, function(old)
			local inbox, r = Rail.Apply(old, action)
			if inbox == nil then
				result, code = nil, r
				return nil
			end
			result, code = r, nil
			cache[k] = { inbox = inbox, at = os.clock() }
			return inbox
		end)
	end)
	if not ok then
		if useMemory(err) then
			return update(userId, action)
		end
		warn("[Rail] updating " .. k .. " failed: " .. tostring(err))
		return false, "rail_unavailable"
	end
	if code then
		return false, code
	end
	return true, result
end

local function state(profile)
	if profile.rail == nil then
		profile.rail = {}
	end
	local r = profile.rail
	r.pending = r.pending or {} -- [tx] = { to, action, at }
	r.routes = r.routes or {} -- { id, to, toName, items, every, nextAt, problem }
	r.nextRoute = r.nextRoute or 1
	r.outgoing = r.outgoing or {} -- { toName, items, arriveAt }: trains sent, until they get there
	r.log = r.log or {} -- { at, text }, newest last
	return r
end

-- The station stands on the home plot, whichever of the player's plots is shown (Shared.Lands).
local function stationOf(profile)
	return Logistics.Station(Lands.HomeGrid(profile).objects)
end

local function describe(items)
	local parts = {}
	for _, entry in ipairs(items) do
		table.insert(parts, entry[2] .. " × " .. Items.Name(entry[1]))
	end
	return table.concat(parts, ", ")
end

local function log(profile, text)
	local r = state(profile)
	table.insert(r.log, { at = Clock.Now(), text = text })
	while #r.log > LogKept do
		table.remove(r.log, 1)
	end
end

-- A train runs past the player's platform (client/TrainView), carrying `items`.
local function showTrain(player, items)
	local plot = Plots.Of(player)
	local railway = plot and plot.model:FindFirstChild("Railway")
	if railway == nil then
		return
	end
	trains = trains + 1
	local ids = {}
	for i, entry in ipairs(items) do
		if i <= 4 then
			table.insert(ids, entry[1])
		end
	end
	railway:SetAttribute("Train", trains .. "|" .. table.concat(ids, ","))
end

-- What the player gets once the inbox took the step.
local function finish(player, profile, action, result)
	local r = state(profile)
	if action.kind == "ship" then
		table.insert(r.outgoing, { to = action.to, toName = action.toName, items = action.items, sentAt = action.sentAt, arriveAt = action.arriveAt })
		log(profile, "Wysłano do " .. action.toName .. ": " .. describe(action.items))
		if player then
			showTrain(player, action.items)
		end
	elseif action.kind == "collect" then
		local station = stationOf(profile)
		for _, s in ipairs(result.shipments) do
			for _, entry in ipairs(s.items) do
				Rail.Add(station.stock, entry[1], entry[2])
			end
			log(profile, "Przyjechał pociąg od " .. tostring(s.fromName) .. ": " .. describe(s.items))
			if player then
				Net.Toast(player, "Pociąg od " .. tostring(s.fromName) .. " przywiózł na stację: " .. describe(s.items))
				showTrain(player, s.items)
			end
		end
	end
end

-- What the player gets back when the inbox said no.
local function refund(profile, action)
	if action.kind == "ship" then
		local station = stationOf(profile)
		for _, entry in ipairs(action.items) do
			Rail.Add(station.stock, entry[1], entry[2])
		end
		if action.feeCents > 0 then
			Wallet.Credit(profile, action.feeCents, "rail_refund")
		end
	end
end

-- Takes the step on the inbox of `to`, after the caller took the player's side.
local function run(player, profile, to, action)
	local r = state(profile)
	action.tx = HttpService:GenerateGUID(false)
	r.pending[action.tx] = { to = to, action = action, at = Clock.Now() }
	busy[player] = true
	local ok, result = update(to, action)
	busy[player] = nil
	r.pending[action.tx] = nil
	if ok then
		finish(player, profile, action, result)
	else
		refund(profile, action)
	end
	if player.Parent then
		Net.PushState(player)
	end
	return ok, result
end

-- Settles steps a stopped server left pending, by what the inboxes remember of them.
local function recover(player, profile)
	local r = state(profile)
	for tx, p in pairs(r.pending) do
		if Clock.Now() - p.at >= PendingSeconds then
			local ok, inbox = read(p.to, 0)
			if ok then
				local done = Rail.Done(inbox, tx)
				if done then
					finish(player, profile, p.action, done.result)
				else
					refund(profile, p.action)
				end
				r.pending[tx] = nil
			end
		end
	end
end

-- Puts trains that have arrived into the player's station.
local function collect(player, profile, maxAge)
	if busy[player] or stationOf(profile) == nil then
		return
	end
	local ok, inbox = read(player.UserId, maxAge)
	if ok and Rail.Arrived(inbox, Clock.Now()) then
		Factory.CatchUp(profile)
		run(player, profile, player.UserId, { kind = "collect", now = Clock.Now() })
	end
end

-- Sends `items` (taken from the station already, with the fee) to `to`; true or false and a code.
local function ship(player, profile, to, toName, items, feeCents)
	local now = Clock.Now()
	local km = Rail.DistanceKm(player.UserId, to)
	return run(player, profile, to, {
		kind = "ship",
		to = to,
		from = player.UserId,
		fromName = player.Name,
		toName = toName,
		items = items,
		sentAt = now,
		arriveAt = now + Rail.TripSeconds(km),
		feeCents = feeCents,
	})
end

-- The name of a player the sender may send to: found this session, or the end of one of their routes.
local function partnerName(player, profile, to)
	if found[player] and found[player][to] then
		return found[player][to]
	end
	for _, route in ipairs(state(profile).routes) do
		if route.to == to then
			return route.toName
		end
	end
	return nil
end

-- One train of a route, when it is due: what the station holds of the route's items, if the
-- player can pay. Without goods or money it waits for the next time.
local function runRoute(player, profile, route)
	local now = Clock.Now()
	route.nextAt = now + route.every * 60
	Factory.CatchUp(profile)
	local station = stationOf(profile)
	local cargo = Rail.Cargo(station.stock, route.items)
	local count = Rail.Count(cargo)
	if count == 0 then
		route.problem = "empty"
		return
	end
	local fee = Rail.FeeCents(Rail.DistanceKm(player.UserId, route.to), count)
	if not Wallet.TryDebit(profile, fee, "rail_route") then
		route.problem = "no_money"
		return
	end
	for _, entry in ipairs(cargo) do
		Rail.Take(station.stock, entry[1], entry[2])
	end
	local ok, code = ship(player, profile, route.to, route.toName, cargo, fee)
	route.problem = (not ok) and code or nil
end

local function runRoutes(player, profile)
	if busy[player] or stationOf(profile) == nil then
		return
	end
	for _, route in ipairs(state(profile).routes) do
		if route.nextAt <= Clock.Now() and not busy[player] then
			runRoute(player, profile, route)
		end
	end
end

-- The station the player stands at, worked out until now; or nil and an error code.
local function open(player, profile)
	local station = stationOf(profile)
	local model = station and Grid.Model(player, station.id)
	if model == nil then
		return nil, "not_loaded"
	end
	if not Net.Near(player, model.Body.Position, PlotLayout.Reach + 8) then
		return nil, "too_far"
	end
	Factory.CatchUp(profile)
	return station
end

local function reply(player, profile, station)
	local now = Clock.Now()
	local r = state(profile)
	for i = #r.outgoing, 1, -1 do
		if r.outgoing[i].arriveAt <= now then
			table.remove(r.outgoing, i)
		end
	end
	local stock = {}
	for _, item in ipairs(Rail.Items(station.stock)) do
		table.insert(stock, { item = item, quantity = station.stock[item] })
	end
	local incoming = {}
	local _, inbox = read(player.UserId, 30)
	for _, s in ipairs((inbox and inbox.shipments) or {}) do
		table.insert(incoming, { fromName = s.fromName, items = s.items, arriveAt = s.arriveAt })
	end
	local partners = {}
	local seen = {}
	local function addPartner(id, name)
		if not seen[id] then
			seen[id] = true
			local km = Rail.DistanceKm(player.UserId, id)
			table.insert(partners, { id = id, name = name, km = math.floor(km + 0.5), trip = Rail.TripSeconds(km) })
		end
	end
	for _, route in ipairs(r.routes) do
		addPartner(route.to, route.toName)
	end
	for id, name in pairs(found[player] or {}) do
		addPartner(id, name)
	end
	local routes = {}
	for _, route in ipairs(r.routes) do
		table.insert(routes, { id = route.id, toName = route.toName, items = route.items, every = route.every, nextAt = route.nextAt, problem = route.problem })
	end
	return {
		ok = true,
		stock = stock,
		routes = routes,
		outgoing = r.outgoing,
		incoming = incoming,
		log = r.log,
		partners = partners,
		minutes = Rail.RouteMinutes,
		maxRoutes = Rail.MaxRoutes,
		maxRouteItems = Rail.MaxRouteItems,
		baseFeeCents = Rail.BaseFeeCents,
		centsPerItemPer100Km = Rail.CentsPerItemPer100Km,
		serverTime = now,
	}
end

-- A user id from the payload: a whole number, not 0 (test players in Studio have negative ids).
local function userIdOf(value)
	local id = Net.Int(value, -1e12, 1e15)
	if id == nil or id == 0 then
		return nil
	end
	return id
end

-- Finds a player by name: on this server first, then any Roblox user. Yields.
local function lookUp(name)
	local lower = string.lower(name)
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == lower or string.lower(p.DisplayName) == lower then
			return p.UserId, p.Name
		end
	end
	local ok, id = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	if not ok or id == nil then
		return nil
	end
	local okName, real = pcall(function()
		return Players:GetNameFromUserIdAsync(id)
	end)
	return id, okName and real or name
end

function Railway.Start()
	Data.OnLoaded(function(player, profile)
		recover(player, profile)
		-- The player's station can receive trains from now on.
		local r = state(profile)
		if not r.opened then
			if update(player.UserId, { kind = "open" }) then
				r.opened = true
			end
		end
		collect(player, profile, 0)
	end)
	Players.PlayerRemoving:Connect(function(player)
		found[player] = nil
		busy[player] = nil
	end)
	task.spawn(function()
		local since = 0
		while true do
			task.wait(RouteSeconds)
			since = since + RouteSeconds
			local collecting = since >= CollectSeconds
			if collecting then
				since = 0
			end
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = Data.Get(player)
				if profile and Plots.Of(player) then
					task.spawn(function()
						runRoutes(player, profile)
						if collecting then
							recover(player, profile)
							collect(player, profile, 0)
						end
					end)
				end
			end
		end
	end)

	Net.Handle("StationGet", function(player, profile)
		local station, code = open(player, profile)
		if station == nil then
			return Net.Error(code)
		end
		collect(player, profile, 5)
		return reply(player, profile, station)
	end)

	Net.Handle("StationLoad", function(player, profile, payload)
		local station, code = open(player, profile)
		if station == nil then
			return Net.Error(code)
		end
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Rail.MaxQuantity)
		if item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		if not Inventory.TryRemove(profile, item, quantity) then
			return Net.Error("not_enough_items")
		end
		Rail.Add(station.stock, item, quantity)
		Net.PushState(player)
		return reply(player, profile, station)
	end)

	Net.Handle("StationUnload", function(player, profile, payload)
		local station, code = open(player, profile)
		if station == nil then
			return Net.Error(code)
		end
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Rail.MaxQuantity)
		if item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		local taken = Rail.Take(station.stock, item, quantity)
		if taken <= 0 then
			return Net.Error("station_empty")
		end
		Inventory.Add(profile, item, taken)
		Net.PushState(player)
		return reply(player, profile, station)
	end)

	Net.Handle("StationFind", function(player, profile, payload)
		local name = payload.name
		if type(name) ~= "string" or #name < 3 or #name > 20 or name:find("[^%w_]") then
			return Net.Error("not_found")
		end
		local id, real = lookUp(name)
		if id == nil then
			return Net.Error("not_found")
		end
		if id == player.UserId then
			return Net.Error("own_station")
		end
		local ok, inbox = read(id, 30)
		if not ok then
			return Net.Error("rail_unavailable")
		end
		if inbox == nil then
			return Net.Error("no_station")
		end
		found[player] = found[player] or {}
		found[player][id] = real
		local station = stationOf(profile)
		return reply(player, profile, station)
	end)

	Net.Handle("StationSend", function(player, profile, payload)
		local station, code = open(player, profile)
		if station == nil then
			return Net.Error(code)
		end
		local to = userIdOf(payload.to)
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Rail.MaxQuantity)
		if to == nil or item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		local toName = partnerName(player, profile, to)
		if toName == nil or to == player.UserId then
			return Net.Error("unknown_partner")
		end
		if busy[player] then
			return Net.Error("rail_busy")
		end
		if (station.stock[item] or 0) < quantity then
			return Net.Error("station_empty")
		end
		local fee = Rail.FeeCents(Rail.DistanceKm(player.UserId, to), quantity)
		if not Wallet.TryDebit(profile, fee, "rail_send") then
			return Net.Error("not_enough_money")
		end
		Rail.Take(station.stock, item, quantity)
		local ok, err = ship(player, profile, to, toName, { { item, quantity } }, fee)
		if not ok then
			return Net.Error(err)
		end
		Net.Toast(player, "Pociąg do " .. toName .. " odjechał (" .. Money.Format(fee) .. ").")
		return reply(player, profile, station)
	end)

	Net.Handle("StationRoute", function(player, profile, payload)
		local station, code = open(player, profile)
		if station == nil then
			return Net.Error(code)
		end
		local to = userIdOf(payload.to)
		local every = Net.Int(payload.every, 1, 60)
		if to == nil or every == nil or type(payload.items) ~= "table" then
			return Net.Error("bad_payload")
		end
		local allowed = false
		for _, m in ipairs(Rail.RouteMinutes) do
			allowed = allowed or m == every
		end
		local items = {}
		for i, value in ipairs(payload.items) do
			local item = Net.Item(value)
			if item == nil or i > Rail.MaxRouteItems then
				return Net.Error("bad_payload")
			end
			table.insert(items, item)
		end
		local toName = partnerName(player, profile, to)
		if not allowed then
			return Net.Error("bad_payload")
		elseif toName == nil or to == player.UserId then
			return Net.Error("unknown_partner")
		end
		local r = state(profile)
		if #r.routes >= Rail.MaxRoutes then
			return Net.Error("too_many_routes")
		end
		table.insert(r.routes, { id = r.nextRoute, to = to, toName = toName, items = items, every = every, nextAt = Clock.Now() })
		r.nextRoute = r.nextRoute + 1
		return reply(player, profile, station)
	end)

	Net.Handle("StationUnroute", function(player, profile, payload)
		local station, code = open(player, profile)
		if station == nil then
			return Net.Error(code)
		end
		local id = Net.Int(payload.id, 1, 1e9)
		local r = state(profile)
		for i, route in ipairs(r.routes) do
			if route.id == id then
				table.remove(r.routes, i)
				return reply(player, profile, station)
			end
		end
		return Net.Error("bad_payload")
	end)
end

return Railway
