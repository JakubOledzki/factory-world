-- The inventory window: the player's items on tiles as in the 2D game. Drag an item onto another
-- tile to move it there; pointing at one names it with the merchant's price.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MarketEvents = require(Shared.MarketEvents)
local Money = require(Shared.Money)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Game = require(script.Parent.Parent.Game)

local Inventory = {}

Inventory.Columns = 5
Inventory.Tiles = 20

function Inventory.Open(screen)
	local connection
	local window, body = Kit.Window(screen, "Ekwipunek", 330, 430, function()
		connection:Disconnect()
	end)
	local grid = ItemGrid.New(body, {
		columns = Inventory.Columns,
		tile = 54,
		hint = function(entry)
			local price = MarketEvents.Prices(Game.Now()).buys[entry.item]
			return price and ("skup " .. Money.Format(price)) or nil
		end,
		onMove = function(_from, to, entry)
			Game.Call("InventoryMove", { item = entry.item, slot = to })
		end,
	})
	Kit.Label(body, "Przeciągnij, aby przenieść.", { TextColor3 = Kit.Colors.Muted, TextSize = 13 })
	local function render()
		grid.Set(ItemGrid.Inventory(Game, Inventory.Tiles, Inventory.Columns))
	end
	connection = Game.Changed.Event:Connect(render)
	render()
	return window
end

return Inventory
