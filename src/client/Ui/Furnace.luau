-- A furnace's window: what is in it as tiles, how far the smelting has got, and the inventory to
-- load it from.
-- The progress is worked out here from the state the server sent (the same Smelting.Advance).
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Smelting = require(Shared.Smelting)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local InventoryWindow = require(script.Parent.Inventory)
local MachineWindow = require(script.Parent.Machine)
local Game = require(script.Parent.Parent.Game)

local Furnace = {}

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

	local live -- the tiles of what is in the furnace, set every frame

	local function apply(r)
		if r then
			Game.SyncTime(r.serverTime)
			state = r.state
		end
	end

	local function render()
		Kit.Clear(body)
		Kit.Label(body, "W piecu (kliknij kafelek, aby wyjąć):", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
		local _, slot, arrow = MachineWindow.Contents(body)
		live = {}
		live.input = slot("Ruda", function()
			apply(Game.Call("FurnaceTake", { id = id, what = "input" }))
		end)
		live.fuel = slot("Węgiel", function()
			apply(Game.Call("FurnaceTake", { id = id, what = "fuel" }))
		end)
		live.bar = arrow()
		live.output = slot("Gotowe", function()
			apply(Game.Call("FurnaceTake", { id = id, what = "output" }))
		end)
		live.output.caption.Font = Enum.Font.GothamBold

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
		Kit.Button(actions, "Schowaj piec", function()
			if Game.Call("FurnacePickup", { id = id }) then
				window:Destroy()
			end
		end, { Size = UDim2.fromOffset(120, 30), BackgroundColor3 = Kit.Colors.Danger })
	end

	table.insert(connections, Game.Changed.Event:Connect(render))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if live == nil or live.bar.Parent == nil then
			return
		end
		local now = Game.Now()
		local s = Smelting.Advance(state, now)
		live.input.Set(s.input, s.inputQuantity > 0 and (s.inputQuantity .. "/" .. Smelting.MaxInput) or "", s.inputQuantity == 0)
		live.fuel.Set(Items.Coal, s.fuel .. "/" .. Smelting.MaxFuel, s.fuel == 0)
		live.fuel.caption.Text = s.heat > 0 and ("Węgiel (żar " .. s.heat .. ")") or "Węgiel"
		live.output.Set(s.output, s.outputQuantity > 0 and tostring(s.outputQuantity) or "", s.outputQuantity == 0)
		local progress = 0
		if s.startedAt and s.input then
			progress = math.clamp((now - s.startedAt) / Smelting.Recipes[s.input].time, 0, 1)
		end
		live.bar.Size = UDim2.fromScale(progress, 1)
	end))
	render()
	return window
end

return Furnace
