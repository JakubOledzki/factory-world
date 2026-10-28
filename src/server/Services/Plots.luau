-- Each player gets one of the plots around the square while they are on this server, with their
-- mines; everything else on it stands on its build grid (Services/Grid). Mining is worked here: the
-- server checks that the plot is the player's, that they stand close, that they held the prompt
-- long enough and that they have the pickaxe, then rolls the drops itself.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Mining = require(Shared.Mining)
local PlotLayout = require(Shared.PlotLayout)
local Models = require(Shared.Models)
local Build = require(script.Parent.Build)
local Clock = require(script.Parent.Clock)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Net = require(script.Parent.Net)
local TestMode = require(script.Parent.TestMode)

local Plots = {}

local folder = Instance.new("Folder")
folder.Name = "Plots"
folder.Parent = workspace

local owners = {} -- [index] = Player
local plotOf = {} -- [Player] = { index, model, mines = { [i] = model } }
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
		return "Kopalnia (poziom " .. (mine.level or 1) .. ") " .. mine.units .. "/" .. Mining.Units
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

local function buildPlot(player, index)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Index", index)
	model.Parent = folder
	local cx, cz = PlotLayout.Center(index)

	Build.FromModel(model, "Decor", Models.PlotDecor(index * 100, PlotLayout.Size, PlotLayout.OpenSides(index), PlotLayout.FenceGaps()), CFrame.new(cx, 0, cz))
	-- The railway outside the east fence; trains run over it on the clients (client/TrainView).
	local stationFrom, stationTo = PlotLayout.StationSpan()
	local railway = Build.FromModel(model, "Railway", Models.Railway(PlotLayout.Rail, stationFrom, stationTo), CFrame.new(cx, 0, cz))
	railway:SetAttribute("Origin", CFrame.new(cx, 0, cz))

	-- A signpost with the owner's name by the gate, facing the square.
	local half = PlotLayout.Size / 2
	local toSquare = Vector3.new(-cx, 0, -cz).Unit
	local signAt = at(index, { x = toSquare.X * (half - 5) + toSquare.Z * 6, z = toSquare.Z * (half - 5) - toSquare.X * 6 })
	local sign = Build.FromModel(model, "Sign", Models.Signpost(index), CFrame.lookAt(signAt, signAt + toSquare))
	Build.Label(sign.Board, "Działka gracza " .. player.DisplayName, 3, Color3.fromRGB(255, 240, 200))

	local plot = { index = index, model = model, mines = {} }
	for i, offset in ipairs(PlotLayout.Mines) do
		local mine = Build.Mine(model, at(index, offset), index * 10 + i, math.pi)
		mine.Name = "Mine" .. i
		Build.Label(mine.Rock, "", 10).Parent.Name = "Label"
		Build.Prompt(mine.Rock, {
			Name = "Prompt",
			ActionText = "Kop",
			ObjectText = "Kopalnia",
			HoldDuration = TestMode.Hold(Mining.Time),
			MaxActivationDistance = 13,
		}, { Kind = "mine", Index = i, Owner = player.UserId })
		plot.mines[i] = mine
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

-- The ground point under something `size` tiles across with its corner on tile (tx, tz) of the
-- player's build grid, turned to face rotation `rot`.
function Plots.TileCFrame(player, tx, tz, size, rot)
	local plot = plotOf[player]
	local x, z = PlotLayout.TileCenter(tx, tz, size)
	return CFrame.new(at(plot.index, { x = x, z = z }, 0)) * CFrame.Angles(0, PlotLayout.Yaw(rot), 0)
end

-- Calls `callback(player, plot)` once a player's plot stands.
function Plots.OnPlaced(callback)
	table.insert(placedCallbacks, callback)
end

local function owns(player, prompt)
	return prompt:GetAttribute("Owner") == player.UserId and plotOf[player] ~= nil
end

-- Whether the player held `prompt` down for its whole HoldDuration (it is forgotten either way).
function Plots.HeldLongEnough(player, prompt)
	local began = holds[player] and holds[player][prompt]
	if holds[player] then
		holds[player][prompt] = nil
	end
	return began ~= nil and os.clock() - began >= prompt.HoldDuration - HoldSlack
end

-- Puts `items` (a list of { item, quantity }) in the player's inventory and tells them.
function Plots.Gather(player, profile, items)
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
	if TestMode.On then
		-- Never runs dry while testing in Studio.
		mine = Mining.New()
	end
	profile.mines[i] = mine
	Plots.Gather(player, profile, Mining.Load(Mining.Roll(random)))
	showMine(player, i)
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
		if kind ~= "mine" then
			return
		end
		local profile = Data.Get(player)
		local part = prompt.Parent
		if profile == nil or not owns(player, prompt) or not Plots.HeldLongEnough(player, prompt) then
			return
		end
		if not (part:IsA("BasePart") and Net.Near(player, part.Position, PlotLayout.Reach)) then
			return
		end
		workMine(player, profile, prompt)
	end)
end

return Plots
