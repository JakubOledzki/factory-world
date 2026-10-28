-- A wooden chest's window: what is in it, with buttons to take it out, and what the player has,
-- with buttons to put it in. Inserters fill and empty the chest too, so it asks again now and then.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Kit = require(script.Parent.Kit)
local Game = require(script.Parent.Parent.Game)

local Chest = {}

local function slotsUsed(items, slotSize)
	local used = 0
	for _, stack in ipairs(items) do
		used = used + math.ceil(stack.quantity / slotSize)
	end
	return used
end

function Chest.Open(screen, id)
	local reply = Game.Call("ChestGet", { id = id })
	if reply == nil then
		return nil
	end
	local connection
	local window, body = Kit.Window(screen, Items.Name(Items.WoodenChest), 460, 480, function()
		connection:Disconnect()
	end)

	local function render()
		Kit.Clear(body)
		Kit.Label(body, "Zajęte miejsca: " .. slotsUsed(reply.items, reply.slotSize) .. " / " .. reply.slots .. " (po " .. reply.slotSize .. " szt.)", { TextColor3 = Kit.Colors.Muted })
		if #reply.items == 0 then
			Kit.Label(body, "Skrzynia jest pusta.")
		end
		for _, stack in ipairs(reply.items) do
			local row = Kit.Row(body)
			Kit.Swatch(row, Items.Colors[stack.item])
			Kit.Label(row, Items.Name(stack.item) .. " × " .. stack.quantity, { Size = UDim2.new(0, 230, 1, 0) })
			Kit.Button(row, "Weź wszystko", function()
				reply = Game.Call("ChestTake", { id = id, item = stack.item, quantity = stack.quantity }) or reply
				render()
			end, { Size = UDim2.fromOffset(120, 28), BackgroundColor3 = Kit.Colors.ButtonAlt })
		end
		Kit.Label(body, "Włóż z ekwipunku:", { TextColor3 = Kit.Colors.Muted })
		for _, item in ipairs(Items.Order) do
			local have = Game.Count(item)
			if have > 0 and not Items.Tools[item] then
				local row = Kit.Row(body)
				Kit.Swatch(row, Items.Colors[item])
				Kit.Label(row, Items.Name(item) .. " (" .. have .. ")", { Size = UDim2.new(0, 230, 1, 0) })
				Kit.Button(row, "Włóż wszystko", function()
					reply = Game.Call("ChestPut", { id = id, item = item, quantity = math.min(Game.Count(item), reply.slots * reply.slotSize) }) or reply
					render()
				end, { Size = UDim2.fromOffset(120, 28) })
			end
		end
	end

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
