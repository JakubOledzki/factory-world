-- A furnace's window: what is in it, how far the smelting has got, and buttons to load and empty it.
-- The progress is worked out here from the state the server sent (the same Smelting.Advance).
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Smelting = require(Shared.Smelting)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local InventoryWindow = require(script.Parent.Inventory)
local Game = require(script.Parent.Parent.Game)

local Furnace = {}

local function describe(item, quantity)
	if item == nil or quantity == 0 then
		return "pusto"
	end
	return Items.Name(item) .. " × " .. quantity
end

function Furnace.Open(screen, id)
	local reply = Game.Call("FurnaceGet", { id = id })
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local state = reply.state
	local connections = {}
	local window, body = Kit.Window(screen, "Piec kamienny", 480, 560, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)

	local inputLabel, fuelLabel, outputLabel, bar

	local function apply(r)
		if r then
			Game.SyncTime(r.serverTime)
			state = r.state
		end
	end

	local function render()
		Kit.Clear(body)
		inputLabel = Kit.Label(body, "")
		fuelLabel = Kit.Label(body, "")
		outputLabel = Kit.Label(body, "", { Font = Enum.Font.GothamBold })
		local track = Kit.New("Frame", { Size = UDim2.new(1, -8, 0, 12), BackgroundColor3 = Kit.Colors.Row, Parent = body }, { Kit.Corner(6) })
		bar = Kit.New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 140, 50), Parent = track }, { Kit.Corner(6) })

		-- The inventory: a click puts ore or coal in (Shift: half), as in the 2D game.
		Kit.Label(body, "Ekwipunek: kliknij rudę albo węgiel, aby włożyć (Shift: połowę)", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
		local grid = ItemGrid.New(body, {
			columns = 7,
			tile = 54,
			onClick = function(_index, entry, half)
				local item = entry.item
				if item ~= Items.Coal and Smelting.Recipes[item] == nil then
					Game.Toast:Fire(Game.ErrorText("not_smeltable"))
					return
				end
				local s = Smelting.Advance(state, Game.Now())
				local room = item == Items.Coal and Smelting.MaxFuel - s.fuel or Smelting.MaxInput - s.inputQuantity
				local wanted = half and math.max(1, math.ceil(entry.quantity / 2)) or entry.quantity
				local quantity = math.min(wanted, room)
				if quantity <= 0 then
					Game.Toast:Fire(Game.ErrorText("furnace_full"))
					return
				end
				apply(Game.Call("FurnaceLoad", { id = id, item = item, quantity = quantity }))
			end,
			onMove = function(_from, to, entry)
				Game.Call("InventoryMove", { item = entry.item, slot = to })
			end,
		})
		grid.Set(ItemGrid.Inventory(Game, InventoryWindow.Tiles, 7))

		local actions = Kit.Row(body, 40)
		actions.BackgroundTransparency = 1
		Kit.Button(actions, "Weź sztabki", function()
			apply(Game.Call("FurnaceTake", { id = id, what = "output" }))
		end, { Size = UDim2.fromOffset(110, 30) })
		Kit.Button(actions, "Weź rudę", function()
			apply(Game.Call("FurnaceTake", { id = id, what = "input" }))
		end, { Size = UDim2.fromOffset(100, 30), BackgroundColor3 = Kit.Colors.ButtonAlt })
		Kit.Button(actions, "Weź węgiel", function()
			apply(Game.Call("FurnaceTake", { id = id, what = "fuel" }))
		end, { Size = UDim2.fromOffset(100, 30), BackgroundColor3 = Kit.Colors.ButtonAlt })
		Kit.Button(actions, "Schowaj", function()
			if Game.Call("FurnacePickup", { id = id }) then
				window:Destroy()
			end
		end, { Size = UDim2.fromOffset(80, 30), BackgroundColor3 = Kit.Colors.Danger })
	end

	table.insert(connections, Game.Changed.Event:Connect(render))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if inputLabel == nil or inputLabel.Parent == nil then
			return
		end
		local now = Game.Now()
		local s = Smelting.Advance(state, now)
		inputLabel.Text = "Ruda: " .. describe(s.input, s.inputQuantity) .. " / " .. Smelting.MaxInput
		fuelLabel.Text = "Węgiel: " .. s.fuel .. " / " .. Smelting.MaxFuel .. "   (żar na " .. s.heat .. " szt.)"
		outputLabel.Text = "Gotowe: " .. describe(s.output, s.outputQuantity)
		local progress = 0
		if s.startedAt and s.input then
			progress = math.clamp((now - s.startedAt) / Smelting.Recipes[s.input].time, 0, 1)
		end
		bar.Size = UDim2.fromScale(progress, 1)
	end))
	render()
	return window
end

return Furnace
