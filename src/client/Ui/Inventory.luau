-- The inventory window: every item the player has, with the merchant's price for it.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Prices = require(Shared.Prices)
local Money = require(Shared.Money)
local Kit = require(script.Parent.Kit)
local Game = require(script.Parent.Parent.Game)

local Inventory = {}

function Inventory.Open(screen)
	local connection
	local window, body = Kit.Window(screen, "Ekwipunek", 420, 460, function()
		connection:Disconnect()
	end)
	local function render()
		Kit.Clear(body)
		local any = false
		for _, id in ipairs(Items.Order) do
			local quantity = Game.Count(id)
			if quantity > 0 then
				any = true
				local row = Kit.Row(body)
				Kit.Swatch(row, Items.Colors[id])
				Kit.Label(row, Items.Name(id), { Size = UDim2.new(0, 190, 1, 0) })
				Kit.Label(row, "× " .. quantity, { Size = UDim2.new(0, 60, 1, 0), Font = Enum.Font.GothamBold })
				if Prices.Buys[id] then
					Kit.Label(row, Money.Format(Prices.Buys[id]), { Size = UDim2.new(0, 80, 1, 0), TextColor3 = Kit.Colors.Muted, TextSize = 14 })
				end
			end
		end
		if not any then
			Kit.Label(body, "Pusto. Kup kilof u handlarza i kop w kopalniach na swojej działce.", { TextWrapped = true, Size = UDim2.new(1, 0, 0, 44) })
		end
	end
	connection = Game.Changed.Event:Connect(render)
	render()
	return window
end

return Inventory
