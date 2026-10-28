-- A tilled field's window: every crop with how long it grows, what a field of it gives and what the
-- merchant pays for that. A click sows it (seeds are free); the server checks the field again.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Farming = require(Shared.Farming)
local Prices = require(Shared.Prices)
local Money = require(Shared.Money)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Game = require(script.Parent.Parent.Game)

local Field = {}

local function minutes(seconds)
	return math.floor(seconds / 60 + 0.5) .. " min"
end

function Field.Open(screen, id)
	local window, body = Kit.Window(screen, "Pole", 380, 470)
	Kit.Label(body, "Wybierz, co zasiać. Nasiona nic nie kosztują.", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
	for i, crop in ipairs(Farming.Crops) do
		local row = Kit.Row(body, 60)
		row.LayoutOrder = i
		local slot = ItemGrid.Slot(row, { size = 48, layoutOrder = 1 })
		slot.Set(crop.item, "")
		local worth = (Prices.Buys[crop.item] or 0) * crop.yield
		Kit.Label(row, Items.Name(crop.item) .. "\n" .. minutes(crop.grow) .. " · " .. crop.yield .. " szt. · " .. Money.Format(worth), {
			Size = UDim2.new(1, -150, 1, 0),
			TextSize = 14,
			TextWrapped = true,
			LayoutOrder = 2,
		})
		Kit.Button(row, "Zasiej", function()
			if Game.Call("FieldSow", { id = id, crop = crop.item }) then
				window:Destroy()
			end
		end, { LayoutOrder = 3, Size = UDim2.fromOffset(70, 30) })
	end
	return window
end

return Field
