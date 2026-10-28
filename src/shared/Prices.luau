-- The merchant's prices in cents, the same as on the web server (MarketModule.Sells / Buys).
-- The merchant always pays less than it takes for the same item (checked in tests/rules_spec.lua).
local Items = require(script.Parent.Items)

local Prices = {}

-- What the merchant takes from the player.
Prices.Sells = {
	[Items.Nails] = 500,
	[Items.Axe] = 10000,
	[Items.Pickaxe] = 10000,
}

-- What the merchant pays the player.
Prices.Buys = {
	[Items.Stone] = 100,
	[Items.Wood] = 200,
	[Items.Coal] = 400,
	[Items.IronOre] = 600,
	[Items.CopperOre] = 1200,
	[Items.TinOre] = 2500,
	[Items.SilverOre] = 6000,
	[Items.GoldOre] = 50000,
	[Items.IronIngot] = 1000,
	[Items.CopperIngot] = 1800,
	[Items.TinIngot] = 3500,
	[Items.SilverIngot] = 8000,
	[Items.GoldIngot] = 60000,
	[Items.Nails] = 300,
	[Items.Axe] = 5000,
	[Items.Pickaxe] = 5000,
	[Items.Furnace] = 3000,
}

-- Most pieces bought or sold in one trade.
Prices.MaxQuantity = 10000

-- Money a new player starts with.
Prices.StartingCents = 5000

return Prices
