-- A wooden chest's window as in the 2D game: the chest's tiles above and the player's below. A
-- click on a tile moves the whole stack across (Shift-click: half). Inserters fill and empty the
-- chest too, so it asks again now and then.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local InventoryWindow = require(script.Parent.Inventory)
local Game = require(script.Parent.Parent.Game)

local Chest = {}

-- The chest's stacks laid on its tiles: a stack over SlotSize takes as many tiles as it fills.
local function tilesOf(reply)
	local entries = {}
	for _, stack in ipairs(reply.items) do
		local left = stack.quantity
		while left > 0 do
			local here = math.min(left, reply.slotSize)
			table.insert(entries, { item = stack.item, quantity = here, total = stack.quantity })
			left = left - here
		end
	end
	for i = #entries + 1, reply.slots do
		entries[i] = false
	end
	return entries
end

local function amount(quantity, half)
	return half and math.max(1, math.ceil(quantity / 2)) or quantity
end

function Chest.Open(screen, id)
	local reply = Game.Call("ChestGet", { id = id })
	if reply == nil then
		return nil
	end
	local connection
	local window, body = Kit.Window(screen, Items.Name(Items.WoodenChest), 330, 520, function()
		connection:Disconnect()
	end)
	local chestGrid, mineGrid

	local function render()
		chestGrid.Set(tilesOf(reply))
		mineGrid.Set(ItemGrid.Inventory(Game, InventoryWindow.Tiles, InventoryWindow.Columns))
	end

	Kit.Label(body, "Skrzynia (" .. reply.slots .. " miejsc po " .. reply.slotSize .. " szt.)", { Font = Enum.Font.GothamBold })
	chestGrid = ItemGrid.New(body, {
		columns = 4,
		tile = 54,
		onClick = function(_index, entry, half)
			reply = Game.Call("ChestTake", { id = id, item = entry.item, quantity = amount(entry.quantity, half) }) or reply
			render()
		end,
	})
	Kit.Label(body, "Ekwipunek: kliknij, aby włożyć (Shift: połowę)", { Font = Enum.Font.GothamBold })
	mineGrid = ItemGrid.New(body, {
		columns = InventoryWindow.Columns,
		tile = 54,
		onClick = function(_index, entry, half)
			if Items.Tools[entry.item] then
				return
			end
			local quantity = math.min(amount(entry.quantity, half), reply.slots * reply.slotSize)
			reply = Game.Call("ChestPut", { id = id, item = entry.item, quantity = quantity }) or reply
			render()
		end,
		onMove = function(_from, to, entry)
			Game.Call("InventoryMove", { item = entry.item, slot = to })
		end,
	})

	connection = Game.Changed.Event:Connect(render)
	render()
	task.spawn(function()
		while window.Parent do
			task.wait(2)
			if window.Parent then
				local again = Game.Call("ChestGet", { id = id })
				if again == nil then
					window:Destroy()
					return
				end
				reply = again
				render()
			end
		end
	end)
	return window
end

return Chest
