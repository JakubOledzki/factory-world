-- Item ids are the same as on the web server (Contracts/Items.cs) and are saved in player data:
-- never change an existing id.
local Items = {}

Items.Wood = "wood"
Items.Stone = "stone"
Items.Coal = "coal"
Items.IronOre = "iron_ore"
Items.CopperOre = "copper_ore"
Items.TinOre = "tin_ore"
Items.SilverOre = "silver_ore"
Items.GoldOre = "gold_ore"
Items.IronIngot = "iron_ingot"
Items.CopperIngot = "copper_ingot"
Items.TinIngot = "tin_ingot"
Items.SilverIngot = "silver_ingot"
Items.GoldIngot = "gold_ingot"
Items.Nails = "nails"
Items.Axe = "tool_axe"
Items.Pickaxe = "tool_pickaxe"
Items.Furnace = "furniture_furnace"

-- What the player sees.
Items.Names = {
	[Items.Wood] = "Drewno",
	[Items.Stone] = "Kamień",
	[Items.Coal] = "Węgiel",
	[Items.IronOre] = "Ruda żelaza",
	[Items.CopperOre] = "Ruda miedzi",
	[Items.TinOre] = "Ruda cyny",
	[Items.SilverOre] = "Ruda srebra",
	[Items.GoldOre] = "Ruda złota",
	[Items.IronIngot] = "Sztabka żelaza",
	[Items.CopperIngot] = "Sztabka miedzi",
	[Items.TinIngot] = "Sztabka cyny",
	[Items.SilverIngot] = "Sztabka srebra",
	[Items.GoldIngot] = "Sztabka złota",
	[Items.Nails] = "Gwoździe",
	[Items.Axe] = "Siekiera",
	[Items.Pickaxe] = "Kilof",
	[Items.Furnace] = "Piec kamienny",
}

-- Colour of the item's icon tile and of the ore veins in a mine, as {r, g, b}.
Items.Colors = {
	[Items.Wood] = { 133, 94, 66 },
	[Items.Stone] = { 140, 140, 140 },
	[Items.Coal] = { 40, 40, 44 },
	[Items.IronOre] = { 168, 110, 90 },
	[Items.CopperOre] = { 196, 112, 60 },
	[Items.TinOre] = { 190, 196, 200 },
	[Items.SilverOre] = { 220, 224, 232 },
	[Items.GoldOre] = { 236, 190, 60 },
	[Items.IronIngot] = { 160, 164, 170 },
	[Items.CopperIngot] = { 210, 120, 70 },
	[Items.TinIngot] = { 200, 205, 210 },
	[Items.SilverIngot] = { 230, 232, 240 },
	[Items.GoldIngot] = { 250, 205, 70 },
	[Items.Nails] = { 120, 124, 130 },
	[Items.Axe] = { 150, 100, 60 },
	[Items.Pickaxe] = { 110, 110, 120 },
	[Items.Furnace] = { 110, 105, 100 },
}

-- Order of items in the inventory and in the merchant's lists.
Items.Order = {
	Items.Pickaxe, Items.Axe, Items.Furnace,
	Items.Wood, Items.Stone, Items.Coal,
	Items.IronOre, Items.CopperOre, Items.TinOre, Items.SilverOre, Items.GoldOre,
	Items.IronIngot, Items.CopperIngot, Items.TinIngot, Items.SilverIngot, Items.GoldIngot,
	Items.Nails,
}

Items.Tools = { [Items.Axe] = true, [Items.Pickaxe] = true }

function Items.IsKnown(id)
	return type(id) == "string" and Items.Names[id] ~= nil
end

function Items.Name(id)
	return Items.Names[id] or id
end

return Items
