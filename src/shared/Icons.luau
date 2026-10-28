-- The pictures of items in the inventory and other item grids: a small 3D model of each item,
-- drawn in a ViewportFrame on the client (client/Ui/ItemGrid) and in the preview, as plain data
-- like Models. Things that stand on the plot show their own model; materials show a lump, a pile,
-- a bar or a stack of them. The front of a model faces -z; the camera looks at it from the front,
-- a little from the right and above.
local Items = require(script.Parent.Items)
local Models = require(script.Parent.Models)

local Icons = {}

local function add(parts, part)
	part.shape = part.shape or "Block"
	part.rot = part.rot or { 0, 0, 0 }
	part.material = part.material or "SmoothPlastic"
	table.insert(parts, part)
	return part
end

local function shade(c, k)
	return { math.min(255, math.floor(c[1] * k + 0.5)), math.min(255, math.floor(c[2] * k + 0.5)), math.min(255, math.floor(c[3] * k + 0.5)) }
end

-- A faceted rock of a few turned blocks around (x, y, z), `size` across.
local function rock(parts, rng, x, y, z, size, color, material)
	for i = 1, 3 do
		local s = size * rng.Num(0.55, 0.8)
		add(parts, {
			size = { s, s * rng.Num(0.6, 0.85), s * rng.Num(0.7, 1) },
			pos = { x + rng.Num(-0.15, 0.15) * size, y + (i - 2) * 0.08 * size, z + rng.Num(-0.15, 0.15) * size },
			rot = { rng.Num(-0.6, 0.6), rng.Num(0, 3), rng.Num(-0.6, 0.6) },
			color = shade(color, rng.Num(0.9, 1.08)),
			material = material or "Rock",
		})
	end
end

local OreMaterials = {
	[Items.GoldOre] = "Foil",
	[Items.SilverOre] = "Foil",
	[Items.CopperOre] = "Metal",
	[Items.TinOre] = "Metal",
	[Items.IronOre] = "CorrodedMetal",
}

local function ore(item)
	local rng = Models.Rng(#item * 37)
	local parts = {}
	rock(parts, rng, 0, 1, 0, 2.2, { 118, 112, 104 })
	-- Veins of the ore showing on the rock.
	for _ = 1, 6 do
		local a = rng.Num(0, 2 * math.pi)
		add(parts, {
			shape = "Ball",
			size = { 0.55, 0.55, 0.55 },
			pos = { math.cos(a) * 0.75, 1 + rng.Num(-0.35, 0.55), math.sin(a) * 0.75 },
			color = Items.Colors[item],
			material = OreMaterials[item] or "Metal",
		})
	end
	return parts
end

local function crushed(item)
	local rng = Models.Rng(#item * 53)
	local parts = {}
	local color = Items.Colors[item]
	for i = 1, 14 do
		local a, r = rng.Num(0, 2 * math.pi), rng.Num(0, 1.1)
		local s = rng.Num(0.45, 0.7)
		add(parts, {
			size = { s, s * 0.8, s },
			pos = { math.cos(a) * r, 0.3 + (1.1 - r) * 0.55 + (i > 10 and 0.35 or 0), math.sin(a) * r },
			rot = { rng.Num(-0.7, 0.7), rng.Num(0, 3), rng.Num(-0.7, 0.7) },
			color = i % 3 == 0 and { 120, 116, 108 } or shade(color, rng.Num(0.85, 1.1)),
			material = i % 3 == 0 and "Rock" or "Slate",
		})
	end
	return parts
end

local function ingot(item)
	local color = Items.Colors[item]
	local material = (item == Items.GoldIngot or item == Items.CopperIngot or item == Items.BronzeIngot) and "Foil" or "Metal"
	local parts = {}
	-- A cast bar: a body narrower at the top, with sloping sides.
	add(parts, { size = { 2.6, 0.7, 0.9 }, pos = { 0, 0.35, 0 }, color = color, material = material })
	add(parts, { shape = "Wedge", size = { 2.6, 0.7, 0.3 }, pos = { 0, 0.35, -0.6 }, rot = { 0, math.pi, 0 }, color = shade(color, 0.92), material = material })
	add(parts, { shape = "Wedge", size = { 2.6, 0.7, 0.3 }, pos = { 0, 0.35, 0.6 }, color = shade(color, 0.92), material = material })
	add(parts, { size = { 2.3, 0.08, 0.7 }, pos = { 0, 0.72, 0 }, color = shade(color, 1.12), material = material })
	-- A second bar behind, across, for a stack.
	add(parts, { size = { 2.6, 0.7, 0.9 }, pos = { 0.2, 0.35, 1.3 }, color = shade(color, 0.95), material = material })
	return parts
end

local function logs()
	local parts = {}
	local bark, cut = { 104, 74, 50 }, { 200, 160, 110 }
	for i, p in ipairs({ { -0.6, 0.55 }, { 0.6, 0.55 }, { 0, 1.5 } }) do
		add(parts, { shape = "Cylinder", size = { 2.8, 1.1, 1.1 }, pos = { 0, p[2], p[1] }, color = shade(bark, 0.95 + i * 0.03), material = "Wood" })
		add(parts, { shape = "Cylinder", size = { 0.06, 0.95, 0.95 }, pos = { 1.41, p[2], p[1] }, color = cut, material = "WoodPlanks" })
	end
	return parts
end

local function planks()
	local parts = {}
	for i = 0, 3 do
		add(parts, { size = { 3, 0.22, 0.75 }, pos = { 0, 0.15 + i * 0.24, (i % 2) * 0.82 - 0.4 }, color = shade(Items.Colors[Items.Planks], 0.95 + (i % 2) * 0.08), material = "WoodPlanks" })
	end
	return parts
end

local function beams()
	local parts = {}
	for i, p in ipairs({ { -0.5, 0.4 }, { 0.5, 0.4 }, { 0, 1.2 } }) do
		add(parts, { size = { 3, 0.8, 0.8 }, pos = { 0, p[2], p[1] }, color = shade(Items.Colors[Items.Beams], 0.95 + i * 0.03), material = "Wood" })
	end
	return parts
end

local function pellets()
	local rng = Models.Rng(71)
	local parts = {}
	add(parts, { shape = "Cylinder", size = { 0.5, 2.2, 2.2 }, pos = { 0, 0.25, 0 }, rot = { 0, 0, math.pi / 2 }, color = { 150, 116, 74 }, material = "Fabric" })
	for _ = 1, 16 do
		local a, r = rng.Num(0, 2 * math.pi), rng.Num(0, 0.9)
		add(parts, {
			shape = "Cylinder",
			size = { 0.45, 0.18, 0.18 },
			pos = { math.cos(a) * r, 0.6 + (0.9 - r) * 0.3, math.sin(a) * r },
			rot = { 0, rng.Num(0, 3), rng.Num(-0.5, 0.5) },
			color = shade(Items.Colors[Items.WoodPellets], rng.Num(0.85, 1.1)),
			material = "Wood",
		})
	end
	return parts
end

local function pile(color, material)
	local parts = {}
	for i, d in ipairs({ 2.6, 1.9, 1.1 }) do
		add(parts, { shape = "Cylinder", size = { 0.45, d, d }, pos = { 0, 0.22 + (i - 1) * 0.36, 0 }, rot = { 0, 0, math.pi / 2 }, color = shade(color, 1 - i * 0.03), material = material })
	end
	return parts
end

local function blocks(color, material, size)
	local parts = {}
	local rng = Models.Rng(89)
	for i, p in ipairs({ { -0.55, 0, -0.3 }, { 0.6, 0, -0.2 }, { 0, 1, 0 } }) do
		add(parts, {
			size = size,
			pos = { p[1], size[2] / 2 + p[2] * size[2], p[3] },
			rot = { 0, rng.Num(-0.15, 0.15), 0 },
			color = shade(color, 0.95 + i * 0.04),
			material = material,
		})
	end
	return parts
end

local function nails()
	local parts = {}
	local steel = Items.Colors[Items.Nails]
	for i = 0, 4 do
		local z = -0.8 + i * 0.4
		add(parts, { shape = "Cylinder", size = { 2.2, 0.14, 0.14 }, pos = { 0, 0.12 + (i % 2) * 0.14, z }, rot = { 0, 0.15 * (i - 2), 0 }, color = steel, material = "Metal" })
		add(parts, { shape = "Cylinder", size = { 0.08, 0.36, 0.36 }, pos = { -1.1, 0.12 + (i % 2) * 0.14, z - 0.16 * (i - 2) }, rot = { 0, 0.15 * (i - 2), 0 }, color = shade(steel, 1.1), material = "Metal" })
	end
	return parts
end

-- A tool lying across the picture: a wooden handle with a steel head at its top end.
local function tool(head)
	local parts = {}
	local wood, steel, edge = { 150, 104, 64 }, { 84, 88, 96 }, { 186, 192, 200 }
	add(parts, { shape = "Cylinder", size = { 4.2, 0.42, 0.42 }, pos = { 0, 0, 0 }, color = wood, material = "Wood" })
	add(parts, { shape = "Cylinder", size = { 0.5, 0.5, 0.5 }, pos = { -1.9, 0, 0 }, color = { 60, 40, 30 }, material = "Fabric" })
	add(parts, { size = { 0.7, 0.75, 0.75 }, pos = { 1.8, 0, 0 }, color = steel, material = "Metal" })
	if head == "hoe" then
		-- A flat blade bent down from the end of the handle.
		add(parts, { size = { 0.3, 0.9, 1.4 }, pos = { 1.95, -0.3, -0.5 }, color = steel, material = "Metal" })
		add(parts, { size = { 0.32, 0.25, 1.4 }, pos = { 1.95, -0.8, -0.5 }, color = edge, material = "Metal" })
	elseif head == "pick" then
		-- Two curved points either side, each of a block and a sloping tip.
		for _, side in ipairs({ -1, 1 }) do
			add(parts, { size = { 0.5, 0.55, 0.9 }, pos = { 1.75, 0, side * 0.8 }, rot = { 0, side * 0.25, 0 }, color = steel, material = "Metal" })
			add(parts, { shape = "Wedge", size = { 0.4, 0.45, 0.9 }, pos = { 1.6, 0, side * 1.65 }, rot = { 0, side > 0 and math.pi + 0.45 or -0.45, 0 }, color = edge, material = "Metal" })
		end
	else
		-- A broad blade on one side, its edge bright.
		add(parts, { size = { 1.3, 0.22, 1.3 }, pos = { 1.75, 0, -0.95 }, color = steel, material = "Metal" })
		add(parts, { size = { 1.6, 0.24, 0.25 }, pos = { 1.75, 0, -1.65 }, color = edge, material = "Metal" })
	end
	-- Lay it down across the view (Icons.ViewDirection) at a slant, so it shows its full length
	-- running corner to corner and the head is not hidden behind the handle.
	for _, part in ipairs(parts) do
		local x, z = part.pos[1], part.pos[3]
		local a = -0.15
		part.pos = { x * math.cos(a) + z * math.sin(a), 0.5 + part.pos[2], -x * math.sin(a) + z * math.cos(a) }
		part.yaw = a
	end
	return parts
end

local function pickaxe()
	return tool("pick")
end

local function axe()
	return tool("axe")
end

local function hoe()
	return tool("hoe")
end

-- A few of a crop or a food lying together.
local function crop(id)
	local parts = {}
	local c = Items.Colors[id]
	local green = { 80, 150, 60 }
	if id == Items.Wheat then
		for i = -2, 2 do
			add(parts, { size = { 0.14, 3, 0.14 }, pos = { i * 0.18, 1.5, 0 }, rot = { 0, 0, i * 0.12 }, color = { 214, 184, 100 }, material = "Grass" })
			add(parts, { size = { 0.3, 0.9, 0.3 }, pos = { i * 0.36, 3.1, 0 }, rot = { 0, 0, i * 0.12 }, color = c, material = "Sand" })
		end
		add(parts, { shape = "Cylinder", size = { 0.3, 0.8, 0.8 }, pos = { 0, 1.2, 0 }, rot = { 0, 0, math.pi / 2 }, color = { 150, 110, 60 }, material = "Fabric" })
	elseif id == Items.Carrot then
		for i = -1, 1 do
			add(parts, { shape = "Cylinder", size = { 2.4, 0.5, 0.5 }, pos = { i * 0.3, 0.4, i * 0.5 }, rot = { 0, 0.4 * i, 0 }, color = c, material = "SmoothPlastic" })
			add(parts, { size = { 0.6, 0.15, 0.4 }, pos = { 1.4 + i * 0.3, 0.45, i * 0.5 + 0.2 }, color = green, material = "Grass" })
		end
	elseif id == Items.Cabbage then
		add(parts, { shape = "Ball", size = { 2.6, 2.6, 2.6 }, pos = { 0, 1.3, 0 }, color = c, material = "Grass" })
		add(parts, { shape = "Ball", size = { 1.8, 1.8, 1.8 }, pos = { 0, 1.7, -0.5 }, color = shade(c, 1.1), material = "Grass" })
	elseif id == Items.Corn then
		add(parts, { shape = "Cylinder", size = { 2.6, 0.8, 0.8 }, pos = { 0, 0.45, 0 }, rot = { 0, 0.4, 0 }, color = c, material = "Sand" })
		add(parts, { shape = "Wedge", size = { 0.9, 0.5, 1.6 }, pos = { 0.6, 0.5, 0.4 }, rot = { 0, 1.9, 0 }, color = green, material = "Grass" })
	elseif id == Items.Potato then
		for i, p in ipairs({ { -0.6, 0.2 }, { 0.6, 0 }, { 0, -0.5 } }) do
			add(parts, { shape = "Ball", size = { 1.2, 1.2, 1.2 }, pos = { p[1], 0.55 + (i == 3 and 0.5 or 0), p[2] }, color = shade(c, 0.95 + i * 0.03), material = "Sand" })
		end
	elseif id == Items.Sunflower then
		add(parts, { shape = "Cylinder", size = { 0.25, 2.8, 2.8 }, pos = { 0, 1.6, 0 }, rot = { 0, math.pi / 2, 0 }, color = c, material = "SmoothPlastic" })
		add(parts, { shape = "Cylinder", size = { 0.3, 1.4, 1.4 }, pos = { 0, 1.6, -0.1 }, rot = { 0, math.pi / 2, 0 }, color = { 90, 60, 30 }, material = "Sand" })
	elseif id == Items.Flour or id == Items.CornFlour then
		add(parts, { shape = "Ball", size = { 2.4, 2.4, 2.4 }, pos = { 0, 1.1, 0 }, color = { 236, 230, 214 }, material = "Fabric" })
		add(parts, { shape = "Cylinder", size = { 0.5, 0.9, 0.9 }, pos = { 0, 2.3, 0 }, rot = { 0, 0, math.pi / 2 }, color = { 220, 214, 196 }, material = "Fabric" })
		add(parts, { size = { 1.2, 0.8, 0.1 }, pos = { 0, 1.2, -1.15 }, color = c, material = "SmoothPlastic" })
	else
		-- A loaf: a long rounded body with a few cuts on top.
		add(parts, { shape = "Cylinder", size = { 2.8, 1.4, 1.4 }, pos = { 0, 0.7, 0 }, color = c, material = "Sand" })
		add(parts, { size = { 2.6, 0.7, 1.3 }, pos = { 0, 0.4, 0 }, color = shade(c, 0.95), material = "Sand" })
		for i = -1, 1 do
			add(parts, { size = { 0.1, 0.12, 0.9 }, pos = { i * 0.7, 1.4, 0 }, rot = { 0, 0.5, 0 }, color = shade(c, 1.2), material = "SmoothPlastic" })
		end
	end
	return parts
end

local Makers = {
	[Items.Stone] = function()
		local parts = {}
		local rng = Models.Rng(11)
		rock(parts, rng, -0.5, 0.7, 0.2, 1.8, { 132, 128, 120 })
		rock(parts, rng, 0.8, 0.5, -0.3, 1.3, { 120, 116, 110 })
		return parts
	end,
	[Items.Coal] = function()
		local parts = {}
		local rng = Models.Rng(13)
		rock(parts, rng, -0.5, 0.6, 0.2, 1.6, { 58, 58, 64 }, "Slate")
		rock(parts, rng, 0.7, 0.5, -0.3, 1.3, { 50, 50, 56 }, "Slate")
		rock(parts, rng, 0.1, 1.3, 0.1, 1, { 66, 66, 72 }, "Slate")
		return parts
	end,
	[Items.Wood] = logs,
	[Items.Sapling] = function()
		return Models.Sapling(1)
	end,
	[Items.Planks] = planks,
	[Items.Beams] = beams,
	[Items.WoodPellets] = pellets,
	[Items.Sand] = function()
		return pile(Items.Colors[Items.Sand], "Sand")
	end,
	[Items.StoneBlocks] = function()
		return blocks(Items.Colors[Items.StoneBlocks], "Limestone", { 1.1, 1, 1.1 })
	end,
	[Items.Bricks] = function()
		return blocks(Items.Colors[Items.Bricks], "Sandstone", { 1.2, 0.5, 0.6 })
	end,
	[Items.Nails] = nails,
	[Items.Pickaxe] = pickaxe,
	[Items.Axe] = axe,
	[Items.Hoe] = hoe,
	[Items.Furnace] = function()
		return Models.Furnace(true)
	end,
	[Items.Belt] = function()
		return Models.Belt(0)
	end,
	[Items.Inserter] = Models.Inserter,
	[Items.WoodenChest] = Models.WoodenChest,
	[Items.Generator] = Models.Generator,
	[Items.Pole] = Models.Pole,
	[Items.Workbench] = Models.Workbench,
}

-- The model of item `id`'s picture, as a list of parts like Models'.
function Icons.Model(id)
	if Makers[id] then
		return Makers[id]()
	elseif Items.Category(id) == "food" then
		return crop(id)
	elseif string.sub(id, 1, 8) == "crushed_" then
		return crushed(id)
	elseif string.sub(id, -4) == "_ore" then
		return ore(id)
	elseif string.sub(id, -6) == "_ingot" then
		return ingot(id)
	elseif string.sub(id, 1, 10) == "furniture_" then
		return Models.Machine(id)
	end
	-- Anything else: a block in the item's colour.
	return { { shape = "Block", size = { 1.6, 1.6, 1.6 }, pos = { 0, 0.8, 0 }, rot = { 0, 0, 0 }, color = Items.Colors[id] or { 200, 200, 200 }, material = "SmoothPlastic" } }
end

-- The way the camera looks at a picture: from the front (-z), a little from the right and above.
Icons.ViewDirection = { 0.75, 0.75, -1 }

return Icons
