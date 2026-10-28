-- Player data in a DataStore, one key per player. A key is locked to the server that loaded it,
-- so two servers never write the same player at once (the lock goes stale after LockSeconds,
-- e.g. when a server crashed). Without DataStore access (Studio without API access) the data
-- lives in memory only.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Prices = require(Shared.Prices)
local Items = require(Shared.Items)
local Mining = require(Shared.Mining)
local Forestry = require(Shared.Forestry)
local Logistics = require(Shared.Logistics)
local PlotLayout = require(Shared.PlotLayout)
local Clock = require(script.Parent.Clock)

local Data = {}

Data.Version = 1
local StoreName = "FactoryWorld3D_v1"
local LockSeconds = 5 * 60
local AutosaveSeconds = 60
local Retries = 5

local store = nil
local okStore = pcall(function()
	store = DataStoreService:GetDataStore(StoreName)
end)
if not okStore then
	store = nil
end

local profiles = {} -- [Player] = profile
local loadedCallbacks = {}

local function newProfile()
	local mines = {}
	for i = 1, 3 do
		mines[i] = Mining.New()
	end
	return {
		version = Data.Version,
		balanceCents = Prices.StartingCents,
		ledger = { { at = Clock.Now(), cents = Prices.StartingCents, reason = "starting_money" } },
		-- A pickaxe and an axe to start with, so the first money comes from the plot.
		inventory = { [Items.Pickaxe] = 1, [Items.Axe] = 1 },
		mines = mines,
		furnaces = {},
		workshop = {},
		-- The build grid: trees, belts, inserters and chests (furnaces are in `furnaces`), the time it
		-- was worked out until and the grid layout it was saved in (PlotLayout.Grid.layout).
		grid = { objects = {}, layout = PlotLayout.Grid.layout },
		nextId = 1,
		lock = nil,
	}
end

local function key(player)
	return "player_" .. player.UserId
end

-- Loads the profile and takes the lock; nil when the player is still locked elsewhere or the
-- DataStore does not answer.
local function load(player)
	if store == nil then
		return newProfile()
	end
	for attempt = 1, Retries do
		local locked = false
		local ok, result = pcall(function()
			return store:UpdateAsync(key(player), function(old)
				local profile = old or newProfile()
				if profile.lock and profile.lock.job ~= game.JobId and os.time() - profile.lock.at < LockSeconds then
					locked = true
					return nil
				end
				profile.lock = { job = game.JobId, at = os.time() }
				return profile
			end)
		end)
		if ok and result and not locked then
			return result
		end
		if not ok and RunService:IsStudio() and tostring(result):find("API") then
			warn("[Data] DataStore unavailable in Studio, progress is not saved: " .. tostring(result))
			store = nil
			return newProfile()
		end
		task.wait(attempt * 2)
	end
	return nil
end

local function save(player, release)
	local profile = profiles[player]
	if profile == nil or store == nil then
		return true
	end
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function(old)
			if old and old.lock and old.lock.job ~= game.JobId then
				-- Another server took the player over; this copy is stale.
				return nil
			end
			profile.lock = (not release) and { job = game.JobId, at = os.time() } or nil
			return profile
		end)
	end)
	if not ok then
		warn("[Data] saving " .. player.Name .. " failed: " .. tostring(err))
	end
	return ok
end

function Data.Get(player)
	return profiles[player]
end

-- Calls `callback(player, profile)` for every player whose data is loaded, now and later.
function Data.OnLoaded(callback)
	table.insert(loadedCallbacks, callback)
	for player, profile in pairs(profiles) do
		task.spawn(callback, player, profile)
	end
end

-- A fresh id for an object the player owns (furnaces and everything on the build grid).
function Data.NextId(profile)
	local id = profile.nextId
	profile.nextId = id + 1
	return id
end

-- Brings data saved by an older version of the game up to date.
local function migrate(profile)
	local g = PlotLayout.Grid
	local grid = profile.grid
	if grid == nil then
		grid = { objects = {}, layout = g.layout }
		profile.grid = grid
	end
	-- What was built on an older, smaller grid stays where it stood on the plot.
	local old = PlotLayout.OldGrids[grid.layout or 1]
	if (grid.layout or 1) ~= g.layout and old then
		local dx, dz = (old.x - g.x) / g.tile, (old.z - g.z) / g.tile
		for _, o in ipairs(grid.objects) do
			o.x = o.x + dx
			o.z = o.z + dz
		end
		for _, f in ipairs(profile.furnaces) do
			if f.tile then
				f.tile = { x = f.tile.x + dx, z = f.tile.z + dz }
			end
		end
	end
	grid.layout = g.layout
	-- Furnaces from the slots of before go onto the grid.
	for _, f in ipairs(profile.furnaces) do
		if f.tile == nil then
			local t = PlotLayout.FurnaceSlotTiles[f.slot or 1]
			f.tile = { x = t.x, z = t.z }
			f.rot = 0
			f.slot = nil
		end
	end
	-- The plot's wild trees, once: before, trees stood in fixed places (`trees`).
	if not profile.wildTrees then
		for _, t in ipairs(PlotLayout.WildTrees) do
			if Logistics.CanPlace(grid.objects, profile.furnaces, Items.Sapling, t.x, t.z) then
				table.insert(grid.objects, Forestry.New(Data.NextId(profile), t.x, t.z, nil))
			end
		end
		profile.wildTrees = true
		profile.trees = nil
	end
end

local function onPlayerAdded(player)
	local profile = load(player)
	if profile == nil then
		player:Kick("Nie udało się wczytać postępu. Spróbuj ponownie za chwilę.")
		return
	end
	if not player:IsDescendantOf(Players) then
		profiles[player] = profile
		save(player, true)
		profiles[player] = nil
		return
	end
	migrate(profile)
	profiles[player] = profile
	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(callback, player, profile)
	end
end

function Data.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player, true)
		profiles[player] = nil
	end)
	game:BindToClose(function()
		local waiting = 0
		for player in pairs(profiles) do
			waiting = waiting + 1
			task.spawn(function()
				save(player, true)
				waiting = waiting - 1
			end)
		end
		local deadline = os.clock() + 25
		while waiting > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AutosaveSeconds)
			for player in pairs(profiles) do
				task.spawn(save, player, false)
			end
		end
	end)
end

return Data
