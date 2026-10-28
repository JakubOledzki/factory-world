-- Boots the game's server. Every rule lives in Shared (pure functions) and in the services here;
-- the client only sends intentions through ReplicatedStorage.Remotes.
local Players = game:GetService("Players")

local Services = script.Parent:WaitForChild("Services")
local Data = require(Services.Data)
local Net = require(Services.Net)
local World = require(Services.World)
local Plots = require(Services.Plots)
local Furnaces = require(Services.Furnaces)
local Grid = require(Services.Grid)
local Machines = require(Services.Machines)
local Generators = require(Services.Generators)
local Lab = require(Services.Lab)
local Inventory = require(Services.Inventory)
local Merchant = require(Services.Merchant)
local Workshop = require(Services.Workshop)
local PlayerMarket = require(Services.PlayerMarket)
local Railway = require(Services.Railway)
local Companies = require(Services.Companies)

-- Remote events exist before any client looks for them.
Net.Event("State")
Net.Event("Toast")

World.Start()
Plots.Start()
Furnaces.Start()
Grid.Start()
Machines.Start()
Generators.Start()
Lab.Start()
Merchant.Start()
Workshop.Start()
PlayerMarket.Start()
Railway.Start()
Companies.Start()

local function addStats(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local money = Instance.new("IntValue")
	money.Name = "Pieniądze"
	money.Parent = stats
	stats.Parent = player
end
Players.PlayerAdded:Connect(addStats)
for _, player in ipairs(Players:GetPlayers()) do
	addStats(player)
end

Data.OnLoaded(function(player)
	Net.PushState(player)
end)

-- Moving an item to another tile of the inventory window.
Net.Handle("InventoryMove", function(player, profile, payload)
	local item = Net.Item(payload.item)
	local slot = Net.Int(payload.slot, 1, 200)
	if item == nil or slot == nil then
		return Net.Error("bad_payload")
	end
	if not Inventory.Move(profile, item, slot) then
		return Net.Error("not_enough_items")
	end
	Net.PushState(player)
	return { ok = true }
end)

-- Last: loads the players already here and those who join, which builds their plots.
Data.Start()

-- The forest only decorates, so it grows in after everything else is up.
task.spawn(World.PlantForest)
