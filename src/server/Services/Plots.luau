-- Each player gets one of the plots around the square while they are on this server, with
-- their mines, trees and furnaces. Mining and cutting are worked here: the server checks that
-- the plot is the player's, that they stand close, that they held the prompt long enough and
-- that they have the tool, then rolls the drops itself.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Mining = require(Shared.Mining)
local Forestry = require(Shared.Forestry)
local PlotLayout = require(Shared.PlotLayout)
local Models = require(Shared.Models)
local Build = require(script.Parent.Build)
local Clock = require(script.Parent.Clock)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Net = require(script.Parent.Net)

local Plots = {}

local folder = Instance.new("Folder")
folder.Name = "Plots"
folder.Parent = workspace

local owners = {} -- [index] = Player
local plotOf = {} -- [Player] = { index, model, mines = { [i] = model }, trees = { [i] = model } }
local holds = {} -- [Player] = { [ProximityPrompt] = os.clock() when the hold began }
local random = Random.new()

local placedCallbacks = {}

-- Seconds of slack for the hold time, for the delay between the client and the server.
local HoldSlack = 0.35

local function at(index, offset, y)
	local cx, cz = PlotLayout.Center(index)
	return Vector3.new(cx + offset.x, y or 0, cz + offset.z)
end

local function mineText(mine, now)
	mine = Mining.Refresh(mine, now)
	if mine.units > 0 then
		return "Kopalnia " .. mine.units .. "/" .. Mining.Units
	end
	return "Pusta, pełna za " .. math.ceil((mine.refillAt - now) / 60) .. " min"
end

local function showMine(player, i)
	local plot = plotOf[player]
	local profile = Data.Get(player)
	if plot == nil or profile == nil then
		return
	end
	local model = plot.mines[i]
	local now = Clock.Now()
	local mine = Mining.Refresh(profile.mines[i], now)
	profile.mines[i] = mine
	model.Rock.Label.Text.Text = mineText(mine, now)
	model.Rock.Prompt.Enabled = mine.units > 0
	if mine.refillAt then
		task.delay(mine.refillAt - now + 0.5, function()
			if plotOf[player] == plot then
				showMine(player, i)
			end
		end)
	end
end

local function showTree(player, i)
	local plot = plotOf[player]
	local profile = Data.Get(player)
	if plot == nil or profile == nil then
		return
	end
	local cutAt = profile.trees["t" .. i]
	local now = Clock.Now()
	local standing = Forestry.Standing(cutAt, now)
	Build.SetTreeStanding(plot.trees[i], standing)
	plot.trees[i].Trunk.Prompt.Enabled = standing
	if not standing then
		task.delay(cutAt + Forestry.Regrow - now + 0.5, function()
			if plotOf[player] == plot then
				showTree(player, i)
			end
		end)
	end
end

local function buildPlot(player, index)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Index", index)
	model.Parent = folder
	local cx, cz = PlotLayout.Center(index)

	Build.Part(model, {
		Name = "Ground",
		Size = Vector3.new(PlotLayout.Size, 1, PlotLayout.Size),
		CFrame = CFrame.new(cx, -0.45, cz),
		Color = Color3.fromRGB(116, 158, 78),
		Material = Enum.Material.Grass,
	})
	Build.FromModel(model, "Decor", Models.PlotDecor(index * 100, PlotLayout.Size, PlotLayout.OpenSides(index), PlotLayout.FurnaceSlots, PlotLayout.Grid), CFrame.new(cx, 0, cz))

	-- A signpost with the owner's name by the gate, facing the square.
	local half = PlotLayout.Size / 2
	local toSquare = Vector3.new(-cx, 0, -cz).Unit
	local signAt = at(index, { x = toSquare.X * (half - 5) + toSquare.Z * 6, z = toSquare.Z * (half - 5) - toSquare.X * 6 })
	local sign = Build.FromModel(model, "Sign", Models.Signpost(index), CFrame.lookAt(signAt, signAt + toSquare))
	Build.Label(sign.Board, "Działka gracza " .. player.DisplayName, 3, Color3.fromRGB(255, 240, 200))

	local plot = { index = index, model = model, mines = {}, trees = {} }
	for i, offset in ipairs(PlotLayout.Mines) do
		local mine = Build.Mine(model, at(index, offset), index * 10 + i, math.pi)
		mine.Name = "Mine" .. i
		Build.Label(mine.Rock, "", 10).Parent.Name = "Label"
		Build.Prompt(mine.Rock, {
			Name = "Prompt",
			ActionText = "Kop",
			ObjectText = "Kopalnia",
			HoldDuration = Mining.Time,
			MaxActivationDistance = 13,
		}, { Kind = "mine", Index = i, Owner = player.UserId })
		plot.mines[i] = mine
	end
	for i, offset in ipairs(PlotLayout.Trees) do
		local tree = Build.Tree(model, at(index, offset), index * 20 + i)
		tree.Name = "Tree" .. i
		Build.Prompt(tree.Trunk, {
			Name = "Prompt",
			ActionText = "Zetnij",
			ObjectText = "Sosna",
			HoldDuration = Forestry.ChopTime,
		}, { Kind = "tree", Index = i, Owner = player.UserId })
		plot.trees[i] = tree
	end
	for slot, offset in ipairs(PlotLayout.FurnaceSlots) do
		local pad = Build.Part(model, {
			Name = "FurnaceSlot" .. slot,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 8, 8),
			CFrame = CFrame.new(at(index, offset, 0.15)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(156, 150, 140),
			Material = Enum.Material.Slate,
		})
		Build.Prompt(pad, {
			Name = "Prompt",
			ActionText = "Postaw piec",
			ObjectText = "Miejsce na piec",
			HoldDuration = 0,
		}, { Kind = "furnaceSlot", Slot = slot, Owner = player.UserId })
	end
	return plot
end

local function spawnOnPlot(player, character)
	local plot = plotOf[player]
	local root = character:WaitForChild("HumanoidRootPart", 10)
	-- Let Roblox finish placing the character at the spawn before moving it.
	task.wait()
	if plot and root and character.Parent then
		local position = at(plot.index, PlotLayout.Spawn, 4)
		character:PivotTo(CFrame.lookAt(position, Vector3.new(0, 4, 0)))
	end
end

function Plots.Of(player)
	return plotOf[player]
end

-- The ground point of furnace slot `slot` on the player's plot.
function Plots.SlotCFrame(player, slot)
	local plot = plotOf[player]
	-- The fire mouth faces the plot's spawn side (+z).
	return CFrame.new(at(plot.index, PlotLayout.FurnaceSlots[slot], 0)) * CFrame.Angles(0, math.pi, 0)
end

-- The ground point under something `size` tiles across with its corner on tile (tx, tz) of the
-- player's build grid, turned to face rotation `rot`.
function Plots.TileCFrame(player, tx, tz, size, rot)
	local plot = plotOf[player]
	local x, z = PlotLayout.TileCenter(tx, tz, size)
	return CFrame.new(at(plot.index, { x = x, z = z }, 0)) * CFrame.Angles(0, PlotLayout.Yaw(rot), 0)
end

function Plots.SlotPad(player, slot)
	local plot = plotOf[player]
	return plot and plot.model:FindFirstChild("FurnaceSlot" .. slot)
end

-- Calls `callback(player, plot)` once a player's plot stands.
function Plots.OnPlaced(callback)
	table.insert(placedCallbacks, callback)
end

local function owns(player, prompt)
	return prompt:GetAttribute("Owner") == player.UserId and plotOf[player] ~= nil
end

local function heldLongEnough(player, prompt)
	local began = holds[player] and holds[player][prompt]
	if holds[player] then
		holds[player][prompt] = nil
	end
	return began ~= nil and os.clock() - began >= prompt.HoldDuration - HoldSlack
end

local function gather(player, profile, items)
	local parts = {}
	for _, entry in ipairs(items) do
		Inventory.Add(profile, entry[1], entry[2])
		table.insert(parts, "+" .. entry[2] .. " " .. Items.Name(entry[1]))
	end
	Net.PushState(player)
	Net.Toast(player, table.concat(parts, ", "))
end

local function workMine(player, profile, prompt)
	local i = prompt:GetAttribute("Index")
	if Inventory.Count(profile, Items.Pickaxe) < 1 then
		Net.Toast(player, "Potrzebujesz kilofa. Kupisz go u handlarza.")
		return
	end
	local mine, code = Mining.Work(profile.mines[i], Clock.Now())
	if mine == nil then
		Net.Toast(player, code == "mine_empty" and "Kopalnia jest pusta." or code)
		return
	end
	profile.mines[i] = mine
	gather(player, profile, Mining.Load(Mining.Roll(random)))
	showMine(player, i)
end

local function chopTree(player, profile, prompt)
	local i = prompt:GetAttribute("Index")
	if Inventory.Count(profile, Items.Axe) < 1 then
		Net.Toast(player, "Potrzebujesz siekiery. Kupisz ją u handlarza.")
		return
	end
	local now = Clock.Now()
	if not Forestry.Standing(profile.trees["t" .. i], now) then
		return
	end
	profile.trees["t" .. i] = now
	gather(player, profile, Forestry.Yield)
	showTree(player, i)
end

function Plots.Start()
	Data.OnLoaded(function(player, profile)
		local index = nil
		for i = 1, PlotLayout.Count do
			if owners[i] == nil then
				index = i
				break
			end
		end
		if index == nil then
			player:Kick("Ten serwer jest pełny. Dołącz do innego.")
			return
		end
		owners[index] = player
		holds[player] = {}
		plotOf[player] = buildPlot(player, index)
		for i in ipairs(PlotLayout.Mines) do
			if profile.mines[i] == nil then
				profile.mines[i] = Mining.New()
			end
			showMine(player, i)
		end
		for i in ipairs(PlotLayout.Trees) do
			showTree(player, i)
		end
		for _, callback in ipairs(placedCallbacks) do
			callback(player, plotOf[player])
		end
		player.CharacterAdded:Connect(function(character)
			spawnOnPlot(player, character)
		end)
		if player.Character then
			task.spawn(spawnOnPlot, player, player.Character)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local plot = plotOf[player]
		if plot then
			owners[plot.index] = nil
			plot.model:Destroy()
		end
		plotOf[player] = nil
		holds[player] = nil
	end)

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
		if holds[player] then
			holds[player][prompt] = os.clock()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local kind = prompt:GetAttribute("Kind")
		if kind ~= "mine" and kind ~= "tree" then
			return
		end
		local profile = Data.Get(player)
		local part = prompt.Parent
		if profile == nil or not owns(player, prompt) or not heldLongEnough(player, prompt) then
			return
		end
		if not (part:IsA("BasePart") and Net.Near(player, part.Position, PlotLayout.Reach)) then
			return
		end
		if kind == "mine" then
			workMine(player, profile, prompt)
		else
			chopTree(player, profile, prompt)
		end
	end)
end

return Plots
