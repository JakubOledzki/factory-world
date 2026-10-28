-- Item ids are the same as on the web server (Contracts/Items.cs) and are saved in player data:
-- never change an existing id.
local Items = {}

Items.Wood = "wood"
Items.Sapling = "sapling"
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
Items.Belt = "logistics_belt"
Items.Inserter = "logistics_inserter"
Items.WoodenChest = "storage_wooden_chest"
Items.Planks = "planks"
Items.Beams = "beams"
Items.WoodPellets = "wood_pellets"
Items.Sand = "sand"
Items.StoneBlocks = "stone_blocks"
Items.CrushedIronOre = "crushed_iron_ore"
Items.CrushedCopperOre = "crushed_copper_ore"
Items.CrushedTinOre = "crushed_tin_ore"
Items.BronzeIngot = "bronze_ingot"
Items.SteelIngot = "steel_ingot"
Items.Bricks = "bricks"
Items.Sawmill = "furniture_sawmill"
Items.Stonemason = "furniture_stonemason"
Items.Crusher = "furniture_crusher"
Items.Foundry = "furniture_foundry"

-- What the player sees.
Items.Names = {
	[Items.Wood] = "Drewno",
	[Items.Sapling] = "Sadzonka",
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
	[Items.Belt] = "Taśmociąg",
	[Items.Inserter] = "Podajnik",
	[Items.WoodenChest] = "Drewniana skrzynia",
	[Items.Planks] = "Deski",
	[Items.Beams] = "Belki",
	[Items.WoodPellets] = "Pellet drzewny",
	[Items.Sand] = "Piasek",
	[Items.StoneBlocks] = "Bloki kamienne",
	[Items.CrushedIronOre] = "Kruszywo żelaza",
	[Items.CrushedCopperOre] = "Kruszywo miedzi",
	[Items.CrushedTinOre] = "Kruszywo cyny",
	[Items.BronzeIngot] = "Sztabka brązu",
	[Items.SteelIngot] = "Sztabka stali",
	[Items.Bricks] = "Cegły",
	[Items.Sawmill] = "Tartak",
	[Items.Stonemason] = "Warsztat kamieniarski",
	[Items.Crusher] = "Kruszarka",
	[Items.Foundry] = "Odlewnia",
}

-- Colour of the item's icon tile and of the ore veins in a mine, as {r, g, b}.
Items.Colors = {
	[Items.Wood] = { 133, 94, 66 },
	[Items.Sapling] = { 96, 160, 70 },
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
	[Items.Belt] = { 74, 76, 82 },
	[Items.Inserter] = { 222, 176, 44 },
	[Items.WoodenChest] = { 156, 112, 68 },
	[Items.Planks] = { 196, 152, 98 },
	[Items.Beams] = { 150, 104, 62 },
	[Items.WoodPellets] = { 176, 140, 90 },
	[Items.Sand] = { 222, 200, 140 },
	[Items.StoneBlocks] = { 170, 168, 160 },
	[Items.CrushedIronOre] = { 150, 96, 80 },
	[Items.CrushedCopperOre] = { 180, 100, 56 },
	[Items.CrushedTinOre] = { 176, 182, 188 },
	[Items.BronzeIngot] = { 190, 130, 60 },
	[Items.SteelIngot] = { 120, 130, 145 },
	[Items.Bricks] = { 170, 74, 54 },
	[Items.Sawmill] = { 168, 120, 70 },
	[Items.Stonemason] = { 150, 146, 138 },
	[Items.Crusher] = { 96, 104, 116 },
	[Items.Foundry] = { 140, 70, 50 },
}

-- Order of items in the inventory and in the merchant's lists.
Items.Order = {
	Items.Pickaxe, Items.Axe, Items.Furnace, Items.Belt, Items.Inserter, Items.WoodenChest,
	Items.Sawmill, Items.Stonemason, Items.Crusher, Items.Foundry,
	Items.Sapling, Items.Wood, Items.Stone, Items.Coal,
	Items.IronOre, Items.CopperOre, Items.TinOre, Items.SilverOre, Items.GoldOre,
	Items.CrushedIronOre, Items.CrushedCopperOre, Items.CrushedTinOre,
	Items.IronIngot, Items.CopperIngot, Items.TinIngot, Items.SilverIngot, Items.GoldIngot,
	Items.BronzeIngot, Items.SteelIngot,
	Items.Planks, Items.Beams, Items.WoodPellets, Items.Sand, Items.StoneBlocks, Items.Bricks,
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
