-- The client: draws the windows and sends the player's intentions to the server. It decides
-- nothing; every number on screen comes from the server.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local Ui = script.Parent:WaitForChild("Ui")
local Kit = require(Ui.Kit)
local Hud = require(Ui.Hud)
local InventoryWindow = require(Ui.Inventory)
local MerchantWindow = require(Ui.Merchant)
local FurnaceWindow = require(Ui.Furnace)
local WorkshopWindow = require(Ui.Workshop)
local ChestWindow = require(Ui.Chest)
local MachineWindow = require(Ui.Machine)
local GeneratorWindow = require(Ui.Generator)
local StationWindow = require(Ui.Station)
local MapWindow = require(Ui.WorldMap)
local ResearchWindow = require(Ui.Research)
local MarketWindow = require(Ui.Market)
local BuildBar = require(Ui.BuildBar)
require(script.Parent:WaitForChild("Game"))
local GridView = require(script.Parent:WaitForChild("GridView"))
local TrainView = require(script.Parent:WaitForChild("TrainView"))

local player = Players.LocalPlayer

local screen = Kit.New("ScreenGui", {
	Name = "FactoryWorld",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- One window open at a time.
local current = nil
local function show(open, ...)
	if current and current.Parent then
		current:Destroy()
	end
	current = open(screen, ...)
end

Hud.Mount(screen, function()
	show(InventoryWindow.Open)
end, BuildBar.Toggle, function()
	show(ResearchWindow.Open)
end, function()
	show(MarketWindow.Open)
end, function()
	show(MapWindow.Open)
end)
BuildBar.Mount(screen)
task.spawn(GridView.Start)
task.spawn(TrainView.Start)

UserInputService.InputBegan:Connect(function(input, processed)
	-- Esc closes the open window (Roblox may also open its menu; the window goes either way).
	if input.KeyCode == Enum.KeyCode.Escape and current and current.Parent then
		current:Destroy()
		current = nil
		return
	end
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.I then
		if current and current.Parent then
			current:Destroy()
			current = nil
		else
			show(InventoryWindow.Open)
		end
	elseif input.KeyCode == Enum.KeyCode.T then
		show(ResearchWindow.Open)
	elseif input.KeyCode == Enum.KeyCode.M then
		show(MarketWindow.Open)
	elseif input.KeyCode == Enum.KeyCode.N then
		show(MapWindow.Open)
	end
end)

-- Prompts on other players' plots are not for this player: hide them.
local function hideForeign(prompt)
	local owner = prompt:GetAttribute("Owner")
	if owner ~= nil and owner ~= player.UserId then
		prompt.MaxActivationDistance = 0
	end
end
for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") then
		hideForeign(descendant)
	end
end
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		hideForeign(descendant)
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local kind = prompt:GetAttribute("Kind")
	if kind == "merchant" then
		show(MerchantWindow.Open)
	elseif kind == "workbench" then
		show(WorkshopWindow.Open)
	elseif kind == "furnace" then
		show(FurnaceWindow.Open, prompt:GetAttribute("FurnaceId"))
	elseif kind == "chest" then
		show(ChestWindow.Open, prompt:GetAttribute("ChestId"))
	elseif kind == "machine" then
		show(MachineWindow.Open, prompt:GetAttribute("MachineId"))
	elseif kind == "station" then
		show(StationWindow.Open)
	elseif kind == "generator" then
		show(GeneratorWindow.Open, prompt:GetAttribute("GeneratorId"))
	end
end)
