-- The merchant's prices in cents, the same as on the web server (MarketModule.Sells / Buys).
-- The merchant always pays less than it takes for the same item (checked in tests/rules_spec.lua).
local Items = require(script.Parent.Items)

local Prices = {}

-- What the merchant takes from the player.
Prices.Sells = {
	[Items.Sapling] = 200,
	[Items.Nails] = 500,
	[Items.Axe] = 10000,
	[Items.Pickaxe] = 10000,
	[Items.Belt] = 1000,
	[Items.Inserter] = 9000,
	[Items.WoodenChest] = 7000,
	[Items.Sawmill] = 40000,
	[Items.Planks] = 300,
	[Items.Sand] = 50,
}

-- What the merchant pays the player.
Prices.Buys = {
	[Items.Sapling] = 100,
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
	[Items.Belt] = 700,
	[Items.Inserter] = 6500,
	[Items.WoodenChest] = 5000,
	[Items.Sawmill] = 22000,
	[Items.Stonemason] = 21500,
	[Items.Crusher] = 60000,
	[Items.Foundry] = 61000,
	[Items.Planks] = 150,
	[Items.Beams] = 600,
	[Items.WoodPellets] = 200,
	[Items.StoneBlocks] = 450,
	[Items.CrushedIronOre] = 560,
	[Items.CrushedCopperOre] = 1100,
	[Items.CrushedTinOre] = 2300,
	[Items.BronzeIngot] = 3100,
	[Items.SteelIngot] = 3400,
	[Items.Bricks] = 110,
}

-- Most pieces bought or sold in one trade.
Prices.MaxQuantity = 10000

-- Money a new player starts with.
Prices.StartingCents = 5000

return Prices
