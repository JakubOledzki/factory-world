-- What every object in the world is built of, as plain data: a list of parts in the object's own
-- coordinates (y = 0 is the ground under it, -z is its front). The server turns the list into
-- Roblox parts (Services/Build) and the browser preview draws the same list, so both look alike.
--
-- A part is { name, shape, size, pos, rot, color, material, ... }:
--   shape    "Block", "Ball", "Cylinder" (along x) or "Wedge" (tall at +z, sloping down to -z)
--   size     { x, y, z } in studs; pos is the centre; rot is { x, y, z } radians as CFrame.Angles
--   color    { r, g, b }; material is an Enum.Material name
--   group    parts of one group change together: "crown" (hidden when a tree is cut),
--            "glow" (lit while a furnace smelts)
--   fire, smoke, light, sparkle   effects the server adds to the part
--   noCollide   players walk through it
--   hidden      built invisible (shown by the game when needed, e.g. an inserter's load)
local Models = {}

-- A small random generator of its own, so the same seed gives the same model on the server and in
-- the preview (Lua and Luau alike).
function Models.Rng(seed)
	local state = (math.floor(seed) % 2147483646) + 1
	local rng = {}
	function rng.Next()
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
	function rng.Num(a, b)
		return a + (b - a) * rng.Next()
	end
	function rng.Int(a, b)
		return math.min(b, a + math.floor((b - a + 1) * rng.Next()))
	end
	return rng
end

-- `color` with each channel moved by up to ±`amount`.
local function vary(color, rng, amount)
	local d = rng.Num(-amount, amount)
	local out = {}
	for i = 1, 3 do
		out[i] = math.max(0, math.min(255, math.floor(color[i] + d + rng.Num(-amount, amount) * 0.4 + 0.5)))
	end
	return out
end

local function add(parts, part)
	part.shape = part.shape or "Block"
	part.rot = part.rot or { 0, 0, 0 }
	part.material = part.material or "SmoothPlastic"
	table.insert(parts, part)
	return part
end

local function ball(parts, d, pos, color, material, extra)
	local part = { shape = "Ball", size = { d, d, d }, pos = pos, color = color, material = material }
	for k, v in pairs(extra or {}) do
		part[k] = v
	end
	return add(parts, part)
end

-- A cylinder standing up.
local function post(parts, height, d, pos, color, material, extra)
	local part = { shape = "Cylinder", size = { height, d, d }, pos = pos, rot = { 0, 0, math.pi / 2 }, color = color, material = material }
	for k, v in pairs(extra or {}) do
		part[k] = v
	end
	return add(parts, part)
end

-- A cylinder lying along x, turned by `yaw` about the vertical.
local function log(parts, length, d, pos, yaw, color, material, extra)
	local part = { shape = "Cylinder", size = { length, d, d }, pos = pos, rot = { 0, yaw or 0, 0 }, color = color, material = material }
	for k, v in pairs(extra or {}) do
		part[k] = v
	end
	return add(parts, part)
end

-- Moves and turns every part of `model` by (x, y, z) and `yaw` about the vertical, and adds it to `parts`.
local function place(parts, model, x, y, z, yaw)
	local c, s = math.cos(yaw or 0), math.sin(yaw or 0)
	for _, part in ipairs(model) do
		local px, pz = part.pos[1], part.pos[3]
		part.pos = { x + px * c + pz * s, y + part.pos[2], z - px * s + pz * c }
		if yaw and yaw ~= 0 then
			if part.rot[1] == 0 and part.rot[3] == 0 then
				part.rot = { 0, part.rot[2] + yaw, 0 }
			else
				-- Turn about the world vertical first: kept as a separate yaw the builders apply before rot.
				part.yaw = (part.yaw or 0) + yaw
			end
		end
		table.insert(parts, part)
	end
end

local Wood = { 116, 82, 54 }
local DarkWood = { 84, 58, 40 }
local Planks = { 162, 120, 78 }
local Iron = { 96, 100, 108 }
local Stone = { 128, 124, 118 }

-- Ore colours showing in the rock.
local Veins = {
	{ color = { 34, 34, 38 }, material = "Basalt" }, -- coal
	{ color = { 176, 108, 84 }, material = "Rock" }, -- iron
	{ color = { 206, 118, 58 }, material = "Rock" }, -- copper
	{ color = { 196, 204, 210 }, material = "Rock" }, -- tin
	{ color = { 240, 196, 70 }, material = "Neon" }, -- gold
}

-- A rocky hill with a timbered mine entrance, rails and a cart of ore. The entrance faces -z.
-- The main rock is named "Rock".
function Models.Mine(seed)
	local rng = Models.Rng(seed)
	local parts = {}
	add(parts, { name = "Rock", shape = "Ball", size = { 13, 13, 13 }, pos = { 0, 0.5, 1 }, color = vary({ 112, 106, 100 }, rng, 6), material = "Slate" })
	for i = 1, 7 do
		local angle = i / 7 * 2 * math.pi + rng.Num(-0.3, 0.3)
		local d = rng.Num(5, 8.5)
		local r = rng.Num(5, 6.5)
		ball(parts, d, { math.cos(angle) * r, rng.Num(-0.5, 1.5), 1 + math.sin(angle) * r * 0.85 }, vary({ 118, 112, 104 }, rng, 12), i % 2 == 0 and "Rock" or "Slate")
	end
	-- Sharp boulders sticking out.
	for i = 1, 5 do
		local angle = rng.Num(0, 2 * math.pi)
		add(parts, {
			shape = "Wedge",
			size = { rng.Num(2, 3.5), rng.Num(2.5, 4.5), rng.Num(2, 3.5) },
			pos = { math.cos(angle) * 7.5, rng.Num(1, 2.5), 1 + math.sin(angle) * 7 },
			rot = { rng.Num(-0.4, 0.4), angle, rng.Num(-0.4, 0.4) },
			color = vary({ 138, 132, 124 }, rng, 10),
			material = "Rock",
		})
	end
	-- Ore veins.
	for i = 1, 14 do
		local vein = Veins[(i - 1) % #Veins + 1]
		local angle = rng.Num(math.pi * 0.15, math.pi * 1.85) + math.pi * 1.5
		local h = rng.Num(1.2, 5.5)
		local r = math.sqrt(math.max(0, 6.5 * 6.5 - (h - 0.5) ^ 2)) + 0.1
		ball(parts, rng.Num(0.8, 1.5), { math.cos(angle) * r, h, 1 + math.sin(angle) * r }, vary(vein.color, rng, 8), vein.material, { noCollide = true })
	end
	-- The entrance: a dark hole framed with timber.
	add(parts, { name = "Entrance", size = { 4.4, 5, 2 }, pos = { 0, 2.5, -5 }, color = { 16, 14, 13 }, material = "SmoothPlastic" })
	post(parts, 6, 0.9, { -2.7, 3, -6.1 }, vary(Wood, rng, 6), "Wood")
	post(parts, 6, 0.9, { 2.7, 3, -6.1 }, vary(Wood, rng, 6), "Wood")
	log(parts, 7.2, 1, { 0, 6.2, -6.1 }, 0, vary(DarkWood, rng, 6), "Wood")
	add(parts, { size = { 6.6, 0.3, 1.2 }, pos = { 0, 7, -6.3 }, color = vary(Planks, rng, 6), material = "WoodPlanks" })
	-- Rails out of the mine.
	for i = 0, 4 do
		add(parts, { size = { 3.4, 0.25, 0.7 }, pos = { 0, 0.12, -6.5 - i * 1.4 }, color = vary(DarkWood, rng, 8), material = "Wood" })
	end
	add(parts, { size = { 0.25, 0.3, 7.4 }, pos = { -1.1, 0.35, -9.3 }, color = Iron, material = "Metal" })
	add(parts, { size = { 0.25, 0.3, 7.4 }, pos = { 1.1, 0.35, -9.3 }, color = Iron, material = "Metal" })
	-- A cart with ore.
	local cz = -10.5
	add(parts, { size = { 2.8, 1.5, 2.2 }, pos = { 0, 1.35, cz }, color = { 92, 74, 58 }, material = "CorrodedMetal" })
	add(parts, { size = { 3, 0.2, 2.4 }, pos = { 0, 2.15, cz }, color = Iron, material = "Metal" })
	for _, x in ipairs({ -1.15, 1.15 }) do
		for _, z in ipairs({ -0.75, 0.75 }) do
			log(parts, 0.3, 0.9, { x * 1.05, 0.55, cz + z }, 0, { 50, 50, 54 }, "Metal")
		end
	end
	for i = 1, 6 do
		local vein = Veins[rng.Int(1, 4)]
		ball(parts, rng.Num(0.7, 1.1), { rng.Num(-0.9, 0.9), 2.3, cz + rng.Num(-0.6, 0.6) }, vary(vein.color, rng, 10), vein.material, { noCollide = true })
	end
	-- A lantern on the left post.
	add(parts, { size = { 0.6, 0.8, 0.6 }, pos = { -3.4, 4.6, -6.5 }, color = { 255, 210, 120 }, material = "Neon", noCollide = true, light = { color = { 255, 190, 110 }, range = 10, brightness = 1.2 } })
	return parts
end

-- A spruce: a trunk with roots and a crown of three tiers. Everything but the stump is in group
-- "crown". The trunk is named "Trunk".
function Models.Tree(seed)
	local rng = Models.Rng(seed)
	local parts = {}
	local height = rng.Num(10, 14)
	local bark = vary({ 104, 74, 50 }, rng, 8)
	post(parts, 0.9, 2.3, { 0, 0.45, 0 }, vary({ 132, 98, 66 }, rng, 6), "Wood", { name = "Stump" })
	post(parts, height * 0.55, 1.9, { 0, height * 0.275, 0 }, bark, "Wood", { name = "Trunk", group = "crown" })
	post(parts, height * 0.5, 1.3, { 0, height * 0.75, 0 }, bark, "Wood", { group = "crown" })
	for i = 1, 3 do
		local angle = i / 3 * 2 * math.pi + rng.Num(0, 1)
		add(parts, {
			shape = "Wedge",
			size = { 0.8, 1, 1.6 },
			pos = { math.cos(angle) * 1.2, 0.45, math.sin(angle) * 1.2 },
			rot = { 0, math.pi / 2 - angle, 0 },
			color = bark,
			material = "Wood",
			group = "crown",
		})
	end
	-- Each tier is a cone of eight wedges, their tall edges meeting at the trunk.
	local green = vary({ 44, 104, 58 }, rng, 10)
	local base = height * 0.3
	for tier = 1, 3 do
		local radius = 5 - tier * 1.1 + rng.Num(-0.25, 0.25)
		local tall = 4.2 - tier * 0.3
		local y = base + (tier - 1) * 2.9 + tall / 2
		local spin = rng.Num(0, math.pi / 4)
		local shade = vary(green, rng, 8)
		for side = 0, 7 do
			local yaw = spin + side * math.pi / 4
			add(parts, {
				shape = "Wedge",
				size = { radius * 0.86, tall, radius },
				pos = { -math.sin(yaw) * radius / 2, y, -math.cos(yaw) * radius / 2 },
				rot = { 0, yaw, 0 },
				color = side % 2 == 0 and shade or vary(shade, rng, 5),
				material = "LeafyGrass",
				group = "crown",
			})
		end
	end
	ball(parts, 1.4, { 0, base + 2 * 2.9 + 3.6, 0 }, vary(green, rng, 6), "LeafyGrass", { group = "crown" })
	return parts
end

-- A round stone furnace with a domed top, a chimney and a fire mouth facing -z. The body is named
-- "Body"; the coal bed and the mouth are in group "glow".
-- `compact` leaves out the coal box beside it, for a furnace on the build grid.
function Models.Furnace(compact)
	local rng = Models.Rng(7)
	local parts = {}
	post(parts, 0.6, 7.2, { 0, 0.3, 0 }, { 96, 92, 88 }, "Slate")
	post(parts, 4, 6.2, { 0, 2.6, 0 }, vary(Stone, rng, 4), "Cobblestone", { name = "Body" })
	post(parts, 0.5, 6.6, { 0, 4.7, 0 }, { 104, 98, 92 }, "Slate")
	ball(parts, 6, { 0, 4.9, 0 }, vary({ 136, 128, 118 }, rng, 4), "Cobblestone")
	-- Chimney with a cap.
	post(parts, 4.5, 1.6, { 1.2, 8.2, 1.2 }, { 150, 82, 64 }, "Brick")
	post(parts, 0.4, 2.1, { 1.2, 10.5, 1.2 }, { 80, 76, 72 }, "Slate", { smoke = true })
	-- The fire mouth: a round-topped opening framed by an arch of stones.
	add(parts, { size = { 2.6, 1.6, 1 }, pos = { 0, 1.7, -2.75 }, color = { 30, 24, 20 }, material = "SmoothPlastic", group = "glow", noCollide = true })
	add(parts, { shape = "Cylinder", size = { 1, 2.6, 2.6 }, pos = { 0, 2.5, -2.75 }, rot = { 0, math.pi / 2, 0 }, color = { 30, 24, 20 }, material = "SmoothPlastic", group = "glow", noCollide = true })
	for i = 0, 6 do
		local a = math.pi * i / 6
		add(parts, {
			size = { 0.8, 0.55, 1.1 },
			pos = { math.cos(a) * 1.75, 2.5 + math.sin(a) * 1.75, -2.95 },
			rot = { 0, 0, a + math.pi / 2 },
			color = vary({ 112, 106, 100 }, rng, 10),
			material = "Slate",
		})
	end
	add(parts, { size = { 3.8, 0.5, 1.2 }, pos = { 0, 0.85, -2.95 }, color = { 104, 98, 92 }, material = "Slate" })
	for i = 1, 5 do
		ball(parts, rng.Num(0.5, 0.8), { rng.Num(-0.9, 0.9), 1.1, -2.6 + rng.Num(-0.2, 0.2) }, { 40, 34, 30 }, "Basalt", { group = "glow", noCollide = true })
	end
	add(parts, { name = "Fire", size = { 1.6, 0.4, 0.8 }, pos = { 0, 1.2, -2.4 }, color = { 30, 26, 24 }, material = "SmoothPlastic", group = "glow", noCollide = true, fire = true, light = { color = { 255, 140, 50 }, range = 16, brightness = 3 } })
	if compact then
		return parts
	end
	-- A coal box and a little heap of ore beside it.
	add(parts, { size = { 2, 1.2, 1.6 }, pos = { -4.3, 0.6, -1.2 }, color = vary(Planks, rng, 8), material = "WoodPlanks" })
	for i = 1, 5 do
		ball(parts, rng.Num(0.6, 0.9), { -4.3 + rng.Num(-0.6, 0.6), 1.3, -1.2 + rng.Num(-0.4, 0.4) }, { 34, 34, 38 }, "Basalt", { noCollide = true })
	end
	return parts
end

-- The workbench: a thick top of boards on legs with a stretcher, a vice, tools and planks.
-- The top is named "Top". Its front (where the player stands) is -z.
function Models.Workbench()
	local rng = Models.Rng(11)
	local parts = {}
	for i = 0, 4 do
		add(parts, {
			name = i == 2 and "Top" or nil,
			size = { 8.4, 0.7, 0.86 },
			pos = { 0, 3.35, -1.72 + i * 0.86 },
			color = vary(Planks, rng, 10),
			material = "WoodPlanks",
		})
	end
	for _, x in ipairs({ -3.6, 3.6 }) do
		for _, z in ipairs({ -1.4, 1.4 }) do
			add(parts, { size = { 0.7, 3, 0.7 }, pos = { x, 1.5, z }, color = vary(Wood, rng, 6), material = "Wood" })
		end
		add(parts, { size = { 0.5, 0.5, 2.8 }, pos = { x, 0.7, 0 }, color = vary(Wood, rng, 6), material = "Wood" })
	end
	add(parts, { size = { 7.2, 0.5, 0.5 }, pos = { 0, 0.7, 0 }, color = vary(Wood, rng, 6), material = "Wood" })
	add(parts, { size = { 7.6, 0.25, 2.6 }, pos = { 0, 1, 0.1 }, color = vary(Planks, rng, 10), material = "WoodPlanks" })
	-- A vice on the left corner.
	add(parts, { size = { 1.2, 0.9, 1.4 }, pos = { -3.2, 4.15, -1.2 }, color = { 60, 92, 140 }, material = "Metal" })
	add(parts, { size = { 1.2, 0.9, 0.3 }, pos = { -3.2, 4.15, -2.1 }, color = { 60, 92, 140 }, material = "Metal" })
	log(parts, 1.8, 0.2, { -3.2, 4.1, -2.5 }, math.pi / 2, Iron, "Metal")
	-- A hammer and a saw lying on the top.
	log(parts, 1.8, 0.25, { 0.2, 3.85, -0.6 }, 0.4, vary(Wood, rng, 6), "Wood")
	add(parts, { size = { 0.45, 0.45, 1 }, pos = { 1.05, 3.92, -0.95 }, rot = { 0, 0.4, 0 }, color = Iron, material = "Metal" })
	add(parts, { size = { 2.4, 0.08, 0.8 }, pos = { 2.2, 3.74, 0.6 }, rot = { 0, -0.3, 0 }, color = { 190, 194, 200 }, material = "Metal" })
	add(parts, { size = { 0.6, 0.3, 0.7 }, pos = { 3.4, 3.8, 0.95 }, rot = { 0, -0.3, 0 }, color = { 150, 60, 44 }, material = "SmoothPlastic" })
	-- Planks leaning against the right end, and a toolbox.
	for i = 0, 2 do
		add(parts, { size = { 0.25, 5, 1 }, pos = { 4.7 + i * 0.3, 2.3, -0.6 + i * 0.9 }, rot = { 0, 0, -0.25 }, color = vary(Planks, rng, 12), material = "WoodPlanks" })
	end
	add(parts, { size = { 1.8, 0.9, 0.9 }, pos = { -1.6, 0.45, -2.6 }, color = { 176, 48, 40 }, material = "SmoothPlastic" })
	add(parts, { size = { 1, 0.15, 0.15 }, pos = { -1.6, 1.05, -2.6 }, color = Iron, material = "Metal" })
	return parts
end

-- The merchant's stall: a counter, a striped awning on round posts, crates, barrels and sacks, with
-- the counter (named "Counter") facing -z.
function Models.Stall()
	local rng = Models.Rng(5)
	local parts = {}
	for i = 0, 3 do
		add(parts, { name = i == 0 and "Counter" or nil, size = { 12, 0.85, 3 }, pos = { 0, 0.43 + i * 0.85, 0 }, color = vary({ 150, 104, 64 }, rng, 10), material = "WoodPlanks" })
	end
	add(parts, { size = { 12.6, 0.4, 3.4 }, pos = { 0, 3.6, 0 }, color = vary(DarkWood, rng, 4), material = "Wood" })
	for _, x in ipairs({ -6, 6 }) do
		post(parts, 9.5, 0.8, { x, 4.75, 3.2 }, vary(Wood, rng, 6), "Wood")
		post(parts, 7.5, 0.8, { x, 3.75, -1.6 }, vary(Wood, rng, 6), "Wood")
	end
	-- The awning: stripes sloping from the back down over the counter.
	for i = 0, 7 do
		add(parts, {
			size = { 1.7, 0.3, 6.4 },
			pos = { -5.95 + i * 1.7, 8.4, 0.75 },
			rot = { -0.38, 0, 0 },
			color = i % 2 == 0 and { 200, 58, 50 } or { 240, 232, 214 },
			material = "Fabric",
		})
	end
	for i = 0, 7 do
		add(parts, {
			shape = "Wedge",
			size = { 1.7, 0.9, 0.4 },
			pos = { -5.95 + i * 1.7, 6.75, -2.15 },
			rot = { math.pi, 0, 0 },
			color = i % 2 == 0 and { 200, 58, 50 } or { 240, 232, 214 },
			material = "Fabric",
		})
	end
	-- A sign board over the awning.
	add(parts, { name = "Sign", size = { 6, 1.6, 0.3 }, pos = { 0, 10.6, 2.8 }, color = vary(Planks, rng, 6), material = "WoodPlanks" })
	-- Goods on the counter.
	for i = 1, 4 do
		local vein = Veins[i]
		ball(parts, 0.8, { -4 + i * 1.1, 3.95, -0.6 }, vein.color, vein.material, { noCollide = true })
	end
	add(parts, { size = { 1.4, 0.6, 0.7 }, pos = { 3.4, 4.1, -0.4 }, color = { 170, 174, 180 }, material = "Metal" })
	-- Crates, barrels and sacks around it.
	local function crate(x, z, s, yaw)
		add(parts, { size = { s, s, s }, pos = { x, s / 2, z }, rot = { 0, yaw, 0 }, color = vary({ 168, 124, 76 }, rng, 10), material = "WoodPlanks" })
		add(parts, { size = { s + 0.1, 0.25, s + 0.1 }, pos = { x, s - 0.3, z }, rot = { 0, yaw, 0 }, color = vary(DarkWood, rng, 6), material = "Wood" })
	end
	crate(-8.2, 0.5, 2.2, 0.2)
	crate(-8.6, 3, 1.8, -0.3)
	crate(-8.3, 1.4, 1.5, 0.6)
	parts[#parts].pos[2] = parts[#parts].pos[2] + 2.2
	parts[#parts - 1].pos[2] = parts[#parts - 1].pos[2] + 2.2
	local function barrel(x, z)
		post(parts, 2.6, 2, { x, 1.3, z }, vary({ 140, 96, 58 }, rng, 10), "Wood")
		post(parts, 0.2, 2.1, { x, 0.5, z }, Iron, "Metal")
		post(parts, 0.2, 2.1, { x, 2.1, z }, Iron, "Metal")
	end
	barrel(8.3, 0.2)
	barrel(8.1, 2.6)
	for i = 1, 3 do
		ball(parts, rng.Num(1.5, 1.9), { 7.4 + i * 0.6, 0.75, -2.2 + i * 0.3 }, vary({ 214, 196, 150 }, rng, 10), "Fabric")
	end
	return parts
end

-- The merchant: a stout figure in an apron and a hat, facing -z.
function Models.Merchant()
	local parts = {}
	local skin = { 236, 196, 160 }
	add(parts, { size = { 0.9, 2.4, 1 }, pos = { -0.5, 1.2, 0 }, color = { 60, 56, 70 }, material = "Fabric" })
	add(parts, { size = { 0.9, 2.4, 1 }, pos = { 0.5, 1.2, 0 }, color = { 60, 56, 70 }, material = "Fabric" })
	add(parts, { size = { 2.4, 2.6, 1.4 }, pos = { 0, 3.7, 0 }, color = { 58, 112, 70 }, material = "Fabric" })
	add(parts, { size = { 2, 2.2, 0.2 }, pos = { 0, 3.3, -0.75 }, color = { 226, 216, 190 }, material = "Fabric" })
	ball(parts, 1.6, { -1.45, 4.3, 0 }, { 58, 112, 70 }, "Fabric")
	ball(parts, 1.6, { 1.45, 4.3, 0 }, { 58, 112, 70 }, "Fabric")
	add(parts, { size = { 0.8, 1.8, 0.8 }, pos = { -1.5, 3.4, -0.2 }, rot = { 0.3, 0, 0 }, color = skin })
	add(parts, { size = { 0.8, 1.8, 0.8 }, pos = { 1.5, 3.4, -0.2 }, rot = { 0.3, 0, 0 }, color = skin })
	ball(parts, 1.9, { 0, 5.9, 0 }, skin, "SmoothPlastic")
	ball(parts, 0.25, { -0.35, 6.05, -0.85 }, { 30, 30, 34 }, "SmoothPlastic")
	ball(parts, 0.25, { 0.35, 6.05, -0.85 }, { 30, 30, 34 }, "SmoothPlastic")
	add(parts, { size = { 1.2, 0.35, 0.3 }, pos = { 0, 5.5, -0.85 }, color = { 110, 70, 46 } })
	post(parts, 0.2, 2.8, { 0, 6.75, 0 }, { 92, 64, 44 }, "Fabric")
	post(parts, 1, 1.8, { 0, 7.3, 0 }, { 92, 64, 44 }, "Fabric")
	return parts
end

-- A round fountain for the middle of the square.
function Models.Fountain()
	local rng = Models.Rng(3)
	local parts = {}
	post(parts, 1.4, 12, { 0, 0.7, 0 }, vary({ 186, 180, 170 }, rng, 4), "Limestone")
	post(parts, 0.3, 10.6, { 0, 1.3, 0 }, { 80, 150, 200 }, "Glass", { noCollide = true })
	post(parts, 3.5, 1.4, { 0, 2.6, 0 }, { 176, 170, 160 }, "Limestone")
	post(parts, 0.5, 4.4, { 0, 4.3, 0 }, { 176, 170, 160 }, "Limestone")
	post(parts, 0.25, 3.8, { 0, 4.55, 0 }, { 110, 180, 225 }, "Glass", { noCollide = true, sparkle = true })
	ball(parts, 1.1, { 0, 5.2, 0 }, { 186, 180, 170 }, "Limestone")
	return parts
end

-- One length of fence along x, centred on the origin: round posts with two rails.
function Models.Fence(length, seed)
	local rng = Models.Rng(seed)
	local parts = {}
	local posts = math.max(2, math.floor(length / 6) + 1)
	for i = 0, posts - 1 do
		local x = -length / 2 + i * length / (posts - 1)
		post(parts, 3, 0.6, { x, 1.5, 0 }, vary(Wood, rng, 10), "Wood")
		ball(parts, 0.7, { x, 3.05, 0 }, vary(Wood, rng, 10), "Wood")
	end
	for _, y in ipairs({ 1.1, 2.3 }) do
		add(parts, { size = { length, 0.3, 0.25 }, pos = { 0, y, 0 }, color = vary({ 150, 110, 70 }, rng, 8), material = "WoodPlanks" })
	end
	return parts
end

-- A signpost with a board, facing -z, the board named "Board".
function Models.Signpost(seed)
	local rng = Models.Rng(seed)
	local parts = {}
	post(parts, 5, 0.5, { -2, 2.5, 0 }, vary(Wood, rng, 8), "Wood")
	post(parts, 5, 0.5, { 2, 2.5, 0 }, vary(Wood, rng, 8), "Wood")
	add(parts, { name = "Board", size = { 5.4, 1.6, 0.3 }, pos = { 0, 4, 0 }, color = vary(Planks, rng, 8), material = "WoodPlanks" })
	return parts
end

-- Stones, bushes, flowers and grass scattered in the rectangle from (x1, z1) to (x2, z2).
function Models.Scatter(seed, x1, z1, x2, z2, count)
	local rng = Models.Rng(seed)
	local parts = {}
	local flowers = { { 236, 90, 90 }, { 250, 220, 90 }, { 170, 120, 220 }, { 250, 250, 250 } }
	for _ = 1, count do
		local x, z = rng.Num(x1, x2), rng.Num(z1, z2)
		local kind = rng.Next()
		if kind < 0.25 then
			ball(parts, rng.Num(1, 2.4), { x, 0.1, z }, vary(Stone, rng, 14), "Rock")
		elseif kind < 0.5 then
			local green = vary({ 70, 130, 60 }, rng, 14)
			ball(parts, rng.Num(2, 3), { x, 0.8, z }, green, "LeafyGrass")
			ball(parts, rng.Num(1.5, 2.2), { x + rng.Num(-1, 1), 0.7, z + rng.Num(-1, 1) }, vary(green, rng, 8), "LeafyGrass")
		elseif kind < 0.8 then
			local color = flowers[rng.Int(1, #flowers)]
			for _ = 1, 4 do
				local fx, fz = x + rng.Num(-1, 1), z + rng.Num(-1, 1)
				post(parts, 0.8, 0.12, { fx, 0.4, fz }, { 70, 140, 60 }, "Grass", { noCollide = true })
				ball(parts, 0.45, { fx, 0.85, fz }, color, "SmoothPlastic", { noCollide = true })
			end
		else
			for _ = 1, 3 do
				add(parts, {
					shape = "Wedge",
					size = { 0.3, rng.Num(0.8, 1.4), 0.6 },
					pos = { x + rng.Num(-0.6, 0.6), 0.4, z + rng.Num(-0.6, 0.6) },
					rot = { 0, rng.Num(0, 6.28), 0 },
					color = vary({ 96, 150, 70 }, rng, 12),
					material = "Grass",
					noCollide = true,
				})
			end
		end
	end
	return parts
end

-- Everything on one plot apart from the mines, trees and furnaces, which have their own models:
-- the fence (open on the sides in `open`, a list of "x+", "x-", "z+", "z-"), the gravel yard under
-- the furnace slots, the concrete floor of the build grid (`grid`, PlotLayout.Grid), a woodpile,
-- and scattered stones and plants. Coordinates from the plot's centre.
function Models.PlotDecor(seed, size, open, slots, grid)
	local parts = {}
	local half = size / 2
	local isOpen = {}
	for _, side in ipairs(open) do
		isOpen[side] = true
	end
	local sides = {
		{ "z-", 0, -half, 0 },
		{ "z+", 0, half, 0 },
		{ "x-", -half, 0, math.pi / 2 },
		{ "x+", half, 0, math.pi / 2 },
	}
	for i, side in ipairs(sides) do
		if isOpen[side[1]] then
			-- Two short lengths either side of a gap for the path.
			place(parts, Models.Fence(half - 6, seed + i), side[2] + (side[4] == 0 and -(half + 6) / 2 or 0), 0, side[3] + (side[4] ~= 0 and -(half + 6) / 2 or 0), side[4])
			place(parts, Models.Fence(half - 6, seed + i + 10), side[2] + (side[4] == 0 and (half + 6) / 2 or 0), 0, side[3] + (side[4] ~= 0 and (half + 6) / 2 or 0), side[4])
		else
			place(parts, Models.Fence(size, seed + i), side[2], 0, side[3], side[4])
		end
	end
	-- Bare rocky ground in front of the mines.
	add(parts, { size = { size - 8, 0.2, 22 }, pos = { 0, 0.04, -31 }, color = { 128, 112, 92 }, material = "Ground", noCollide = true })
	-- Gravel yard under the furnaces.
	local first, last = slots[1], slots[#slots]
	add(parts, {
		size = { last.x - first.x + 10, 0.2, 11 },
		pos = { (first.x + last.x) / 2, 0.06, first.z },
		color = { 150, 140, 124 },
		material = "Pebble",
		noCollide = true,
	})
	-- The build grid: a concrete floor with a seam between the tiles.
	local gw, gd = grid.width * grid.tile, grid.depth * grid.tile
	local gx, gz = grid.x + gw / 2, grid.z + gd / 2
	add(parts, { size = { gw + 1, 0.2, gd + 1 }, pos = { gx, 0.05, gz }, color = { 158, 156, 150 }, material = "Concrete", noCollide = true })
	for i = 0, grid.width do
		add(parts, { size = { 0.15, 0.22, gd }, pos = { grid.x + i * grid.tile, 0.07, gz }, color = { 124, 122, 118 }, material = "Concrete", noCollide = true })
	end
	for i = 0, grid.depth do
		add(parts, { size = { gw, 0.22, 0.15 }, pos = { gx, 0.07, grid.z + i * grid.tile }, color = { 124, 122, 118 }, material = "Concrete", noCollide = true })
	end
	-- A woodpile by the trees.
	local rng = Models.Rng(seed + 99)
	for row = 0, 2 do
		for i = 0, 3 - row do
			log(parts, 3.4, 0.9, { -20, 0.45 + row * 0.8, 30 + (i - (3 - row) / 2) * 0.95 }, 0, vary({ 132, 96, 62 }, rng, 10), "Wood")
		end
	end
	local scatter = {
		Models.Scatter(seed + 1, 30, -22, 42, -15, 4),
		Models.Scatter(seed + 2, 8, 24, 40, 40, 8),
		Models.Scatter(seed + 3, -40, -44, 40, -40, 6),
		Models.Scatter(seed + 4, -20, 10, -8, 22, 4),
	}
	for _, list in ipairs(scatter) do
		place(parts, list, 0, 0, 0, 0)
	end
	return parts
end

-- A belt tile, 4 × 4 studs: a rubber belt between two rails with rollers at the ends and arrows the
-- way it runs, to its front (-z). Items ride on it at y = 0.95 (Models.BeltItem).
function Models.Belt()
	local parts = {}
	local rail = { 92, 96, 104 }
	add(parts, { name = "Body", size = { 3.3, 0.25, 4 }, pos = { 0, 0.6, 0 }, color = { 40, 40, 44 }, material = "Fabric" })
	for _, x in ipairs({ -1.83, 1.83 }) do
		add(parts, { size = { 0.36, 0.9, 4 }, pos = { x, 0.45, 0 }, color = rail, material = "Metal" })
		add(parts, { size = { 0.38, 0.08, 4 }, pos = { x, 0.93, 0 }, color = { 222, 176, 44 }, material = "SmoothPlastic" })
	end
	for _, z in ipairs({ -1.8, 1.8 }) do
		log(parts, 3.3, 0.5, { 0, 0.42, z }, 0, { 70, 72, 78 }, "Metal")
	end
	-- Bright arrows pointing the way the belt runs, standing a little off the belt.
	for _, tip in ipairs({ -1.5, 0.5 }) do
		add(parts, { size = { 0.26, 0.08, 1.15 }, pos = { -0.345, 0.77, tip + 0.46 }, rot = { 0, -0.6435, 0 }, color = { 240, 236, 220 }, material = "SmoothPlastic", noCollide = true })
		add(parts, { size = { 0.26, 0.08, 1.15 }, pos = { 0.345, 0.77, tip + 0.46 }, rot = { 0, 0.6435, 0 }, color = { 240, 236, 220 }, material = "SmoothPlastic", noCollide = true })
	end
	return parts
end

-- Where item `slot` (1..8, lane after lane, from where items come on to where they leave) rides on
-- a belt, in the belt's own coordinates: the left lane (as the belt runs to -z) is at -x.
function Models.BeltSlot(slot, slots)
	local lane = math.floor((slot - 1) / slots)
	local i = (slot - 1) % slots
	return { lane == 0 and -0.8 or 0.8, 0.95, 1.5 - i * (3 / (slots - 1)) }
end

-- An inserter on a turntable: a yellow arm on a column that swings from behind it (+z), where it
-- picks up, round to its front (-z), where it drops. The arm's parts are in group "arm" and drawn
-- pointing to the front; its load is the hidden ball named "Hand".
function Models.Inserter()
	local parts = {}
	local yellow = { 222, 176, 44 }
	local steel = { 92, 96, 104 }
	post(parts, 0.5, 2.8, { 0, 0.25, 0 }, { 66, 68, 74 }, "DiamondPlate", { name = "Body" })
	post(parts, 0.6, 1.9, { 0, 0.8, 0 }, yellow, "SmoothPlastic")
	post(parts, 1.4, 0.8, { 0, 1.8, 0 }, steel, "Metal")
	ball(parts, 1, { 0, 2.6, 0 }, yellow, "SmoothPlastic", { group = "arm" })
	add(parts, { size = { 0.45, 0.45, 1.9 }, pos = { 0, 2.6, -0.95 }, color = yellow, material = "SmoothPlastic", group = "arm" })
	add(parts, { size = { 0.32, 0.9, 0.32 }, pos = { 0, 2.15, -1.8 }, color = steel, material = "Metal", group = "arm" })
	for _, x in ipairs({ -0.3, 0.3 }) do
		add(parts, { size = { 0.12, 0.5, 0.45 }, pos = { x, 1.5, -1.8 }, color = { 50, 50, 54 }, material = "Metal", group = "arm" })
	end
	ball(parts, 0.7, { 0, 1.35, -1.8 }, { 200, 200, 200 }, "SmoothPlastic", { name = "Hand", group = "arm", hidden = true, noCollide = true })
	-- An arrow on the base plate pointing where it drops (-z), and a dark notch where it picks up.
	add(parts, { size = { 0.3, 0.08, 0.9 }, pos = { 0, 0.54, -0.95 }, color = { 240, 236, 220 }, material = "SmoothPlastic", noCollide = true })
	add(parts, { size = { 0.22, 0.08, 0.7 }, pos = { -0.2, 0.54, -1.1 }, rot = { 0, -0.7, 0 }, color = { 240, 236, 220 }, material = "SmoothPlastic", noCollide = true })
	add(parts, { size = { 0.22, 0.08, 0.7 }, pos = { 0.2, 0.54, -1.1 }, rot = { 0, 0.7, 0 }, color = { 240, 236, 220 }, material = "SmoothPlastic", noCollide = true })
	-- Hazard stripes round the turntable.
	for i = 0, 7 do
		local a = i / 8 * 2 * math.pi
		add(parts, { size = { 0.5, 0.52, 0.18 }, pos = { math.cos(a) * 1.3, 0.25, math.sin(a) * 1.3 }, rot = { 0, -a + math.pi / 2, 0 }, color = i % 2 == 0 and yellow or { 30, 30, 32 }, material = "SmoothPlastic" })
	end
	return parts
end

-- What the ghost of a thing about to be built shows besides the thing itself, in its own
-- coordinates (front -z): a big glowing arrow above it the way it faces and, for an inserter, the
-- tile it picks up from (blue, behind it) and the tile it drops on (green, in front).
function Models.BuildMarker(kind, tile)
	local parts = {}
	local glow = { 255, 220, 70 }
	local y = kind == "furniture_furnace" and 12.5 or 5
	add(parts, { size = { 0.5, 0.3, 2.4 }, pos = { 0, y, 0.6 }, color = glow, material = "Neon", noCollide = true })
	add(parts, { size = { 0.5, 0.3, 1.7 }, pos = { -0.5, y, -1 }, rot = { 0, -0.75, 0 }, color = glow, material = "Neon", noCollide = true })
	add(parts, { size = { 0.5, 0.3, 1.7 }, pos = { 0.5, y, -1 }, rot = { 0, 0.75, 0 }, color = glow, material = "Neon", noCollide = true })
	if kind == "logistics_inserter" then
		add(parts, { size = { tile - 0.4, 0.12, tile - 0.4 }, pos = { 0, 0.1, tile }, color = { 80, 150, 255 }, material = "Neon", noCollide = true })
		add(parts, { size = { tile - 0.4, 0.12, tile - 0.4 }, pos = { 0, 0.1, -tile }, color = { 90, 230, 120 }, material = "Neon", noCollide = true })
	end
	return parts
end

-- A wooden chest bound with iron, its lock on the front (-z). The box is named "Body".
function Models.WoodenChest()
	local rng = Models.Rng(31)
	local parts = {}
	for i = 0, 2 do
		add(parts, {
			name = i == 0 and "Body" or nil,
			size = { 3, 0.56, 2.2 },
			pos = { 0, 0.3 + i * 0.56, 0 },
			color = vary(Planks, rng, 10),
			material = "WoodPlanks",
		})
	end
	add(parts, { size = { 3.12, 0.5, 2.32 }, pos = { 0, 1.98, 0 }, color = vary(Wood, rng, 6), material = "WoodPlanks" })
	log(parts, 3.12, 0.9, { 0, 2.2, 0 }, 0, vary(Wood, rng, 6), "WoodPlanks")
	for _, x in ipairs({ -1.15, 1.15 }) do
		add(parts, { size = { 0.22, 2.1, 2.34 }, pos = { x, 1.08, 0 }, color = Iron, material = "Metal" })
		log(parts, 0.24, 0.96, { x, 2.2, 0 }, 0, Iron, "Metal")
	end
	add(parts, { size = { 0.55, 0.65, 0.16 }, pos = { 0, 1.75, -1.2 }, color = { 196, 164, 80 }, material = "Metal" })
	add(parts, { size = { 0.16, 0.2, 0.06 }, pos = { 0, 1.68, -1.29 }, color = { 30, 26, 22 }, material = "SmoothPlastic" })
	return parts
end

return Models
