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
local Items = require(script.Parent.Items)

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
-- "crown". The trunk is named "Trunk". `snow`: snow lies on its tiers (a tree of the tundra).
function Models.Tree(seed, snow)
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
		if snow then
			-- A cap of snow on the upper part of the tier.
			for side = 0, 7 do
				local yaw = spin + side * math.pi / 4
				local r = radius * 0.62
				add(parts, {
					shape = "Wedge",
					size = { r * 0.86, tall * 0.4, r },
					pos = { -math.sin(yaw) * r / 2, y + tall * 0.32, -math.cos(yaw) * r / 2 },
					rot = { 0, yaw, 0 },
					color = { 240, 244, 248 },
					material = "Snow",
					group = "crown",
					noCollide = true,
				})
			end
		end
	end
	ball(parts, 1.4, { 0, base + 2 * 2.9 + 3.6, 0 }, snow and { 240, 244, 248 } or vary(green, rng, 6), snow and "Snow" or "LeafyGrass", { group = "crown" })
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
	-- A board at the back with tools hanging on it, a shelf with jars and a lamp over the top.
	for _, x in ipairs({ -3.6, 3.6 }) do
		add(parts, { size = { 0.4, 3.6, 0.4 }, pos = { x, 5.4, 1.55 }, color = vary(Wood, rng, 6), material = "Wood" })
	end
	add(parts, { size = { 7.6, 2.8, 0.2 }, pos = { 0, 5.3, 1.6 }, color = vary({ 196, 170, 130 }, rng, 6), material = "WoodPlanks" })
	add(parts, { size = { 0.15, 1.6, 0.12 }, pos = { -2.4, 5.4, 1.45 }, rot = { 0, 0, 0.1 }, color = vary(Wood, rng, 6), material = "Wood" })
	add(parts, { size = { 0.5, 0.35, 0.14 }, pos = { -2.3, 6.15, 1.44 }, color = Iron, material = "Metal" })
	add(parts, { size = { 1.6, 0.6, 0.06 }, pos = { -0.6, 5.5, 1.46 }, color = { 190, 194, 200 }, material = "Metal" })
	add(parts, { size = { 0.5, 0.3, 0.14 }, pos = { 0.3, 5.55, 1.44 }, color = { 150, 60, 44 }, material = "SmoothPlastic" })
	add(parts, { shape = "Cylinder", size = { 0.12, 1, 1 }, pos = { 1.6, 5.5, 1.45 }, rot = { 0, math.pi / 2, 0 }, color = { 60, 62, 68 }, material = "Metal" })
	add(parts, { size = { 2.6, 0.18, 0.7 }, pos = { 2.4, 6.75, 1.25 }, color = vary(Planks, rng, 8), material = "WoodPlanks" })
	for k = 0, 2 do
		post(parts, 0.55, 0.45, { 1.6 + k * 0.7, 7.1, 1.25 }, k == 1 and { 120, 160, 90 } or { 190, 150, 90 }, "Glass")
	end
	add(parts, { size = { 0.15, 0.15, 1.6 }, pos = { 0, 6.9, 0.85 }, color = { 40, 40, 44 }, material = "Metal" })
	ball(parts, 0.55, { 0, 6.7, 0.1 }, { 255, 226, 150 }, "Neon", { noCollide = true, light = { color = { 255, 214, 150 }, range = 10, brightness = 0.8 } })
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
	-- A low step round it, the basin's wall with a rim, the water, a pillar with a bowl on top.
	post(parts, 0.6, 14, { 0, 0.3, 0 }, vary({ 160, 154, 144 }, rng, 4), "Cobblestone")
	post(parts, 2.2, 12, { 0, 1.7, 0 }, vary({ 186, 180, 170 }, rng, 4), "Limestone")
	post(parts, 0.3, 12.6, { 0, 2.9, 0 }, { 204, 198, 188 }, "Limestone")
	post(parts, 0.3, 11, { 0, 2.55, 0 }, { 80, 150, 200 }, "Glass", { noCollide = true })
	post(parts, 3.6, 1.4, { 0, 4.3, 0 }, { 176, 170, 160 }, "Limestone")
	post(parts, 0.5, 4.4, { 0, 6.1, 0 }, { 176, 170, 160 }, "Limestone")
	post(parts, 0.25, 3.8, { 0, 6.35, 0 }, { 110, 180, 225 }, "Glass", { noCollide = true, sparkle = true })
	-- A second, smaller bowl over the first, water running down from both.
	post(parts, 1.6, 0.8, { 0, 7.3, 0 }, { 176, 170, 160 }, "Limestone")
	post(parts, 0.4, 2.4, { 0, 8.25, 0 }, { 176, 170, 160 }, "Limestone")
	post(parts, 0.2, 2, { 0, 8.45, 0 }, { 110, 180, 225 }, "Glass", { noCollide = true })
	ball(parts, 1.1, { 0, 9.1, 0 }, { 186, 180, 170 }, "Limestone")
	for i = 0, 7 do
		local a = i / 8 * 2 * math.pi
		add(parts, { size = { 0.08, 1.9, 0.25 }, pos = { math.cos(a) * 2.3, 5.3, math.sin(a) * 2.3 }, rot = { 0, -a, 0 }, color = { 140, 200, 235 }, material = "Glass", noCollide = true })
		if i % 2 == 0 then
			add(parts, { size = { 0.08, 1.3, 0.2 }, pos = { math.cos(a) * 1.25, 7.4, math.sin(a) * 1.25 }, rot = { 0, -a, 0 }, color = { 140, 200, 235 }, material = "Glass", noCollide = true })
		end
	end
	-- Lily pads on the water, and four stone fish spouting into it from the wall.
	for _ = 1, 5 do
		local a, r = rng.Num(0, 2 * math.pi), rng.Num(3, 5)
		post(parts, 0.08, rng.Num(0.8, 1.2), { math.cos(a) * r, 2.72, math.sin(a) * r }, { 70, 140, 70 }, "Grass", { noCollide = true })
	end
	for i = 0, 3 do
		local a = i / 4 * 2 * math.pi + math.pi / 4
		ball(parts, 0.9, { math.cos(a) * 5.9, 3.3, math.sin(a) * 5.9 }, { 176, 170, 160 }, "Limestone")
		add(parts, { size = { 0.15, 0.15, 1.6 }, pos = { math.cos(a) * 5.2, 3.15, math.sin(a) * 5.2 }, yaw = math.pi / 2 - a, rot = { 0.35, 0, 0 }, color = { 140, 200, 235 }, material = "Glass", noCollide = true })
	end
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

-- Everything on one plot that is not on its build grid: the fence (open on the sides in `open`, a
-- list of "x+", "x-", "z+", "z-") and the bare rocky ground under the mines. Coordinates from the
-- plot's centre. Everything else on a plot stands on the grid.
-- `gaps` (optional): more openings in the fence, { side, from, to } along the side (x for the
-- z sides, z for the x sides), like the one to the railway platform.
-- `biome` (optional, from Shared.Lands): the plot's ground.
function Models.PlotDecor(seed, size, open, gaps, biome)
	local parts = {}
	local half = size / 2
	if biome then
		add(parts, { size = { size, 0.2, size }, pos = { 0, -0.06, 0 }, color = biome.ground, material = biome.material, noCollide = true })
	end
	local sides = {
		{ "z-", 0, -half, 0 },
		{ "z+", 0, half, 0 },
		{ "x-", -half, 0, math.pi / 2 },
		{ "x+", half, 0, math.pi / 2 },
	}
	for i, side in ipairs(sides) do
		-- The gate for the path in the middle, and any other openings.
		local cuts = {}
		for _, s in ipairs(open) do
			if s == side[1] then
				table.insert(cuts, { -6, 6 })
			end
		end
		for _, g in ipairs(gaps or {}) do
			if g[1] == side[1] then
				table.insert(cuts, { g[2], g[3] })
			end
		end
		table.sort(cuts, function(a, b)
			return a[1] < b[1]
		end)
		local from = -half
		table.insert(cuts, { half, half })
		for k, cut in ipairs(cuts) do
			local length = cut[1] - from
			if length > 0.5 then
				local mid = (from + cut[1]) / 2
				local x, z = side[2], side[3]
				if side[4] == 0 then
					x = mid
				else
					z = mid
				end
				place(parts, Models.Fence(length, seed + i + 10 * (k - 1)), x, 0, z, side[4])
			end
			from = math.max(from, cut[2])
		end
	end
	-- Bare rocky ground under the mine.
	add(parts, { size = { 28, 0.2, 25 }, pos = { 0, 0.04, -half + 16 }, color = { 128, 112, 92 }, material = "Ground", noCollide = true })
	return parts
end

-- A tree of the forest between the plots, of few parts as there are thousands: a tiered spruce or
-- a leafy tree. Only to look at; its trunk is named "Trunk" and stops players.
function Models.ForestTree(seed)
	local rng = Models.Rng(seed)
	local parts = {}
	local bark = vary({ 96, 70, 48 }, rng, 10)
	if rng.Next() < 0.6 then
		local height = rng.Num(13, 20)
		post(parts, height * 0.9, 1.5, { 0, height * 0.45, 0 }, bark, "Wood", { name = "Trunk" })
		-- Three overlapping tiers, narrower going up, the trunk's tip showing above.
		local green = vary({ 38, 92, 52 }, rng, 10)
		local wide = rng.Num(9, 10.5)
		for tier = 1, 3 do
			local tall = height * 0.27
			post(parts, tall, wide * (1.25 - tier * 0.3), { 0, height * (0.2 + (tier - 1) * 0.22) + tall / 2, 0 }, vary(green, rng, 6), "LeafyGrass", { noCollide = true })
		end
	else
		local height = rng.Num(9, 13)
		post(parts, height * 0.7, 1.6, { 0, height * 0.35, 0 }, bark, "Wood", { name = "Trunk" })
		local green = vary({ 64, 122, 54 }, rng, 14)
		ball(parts, rng.Num(7, 9), { 0, height * 0.8, 0 }, green, "LeafyGrass", { noCollide = true })
		ball(parts, rng.Num(5, 6.5), { rng.Num(1.5, 2.5), height * 0.7, rng.Num(-1.5, 1.5) }, vary(green, rng, 8), "LeafyGrass", { noCollide = true })
		ball(parts, rng.Num(5, 6.5), { rng.Num(-2.5, -1.5), height * 0.72, rng.Num(-1.5, 1.5) }, vary(green, rng, 8), "LeafyGrass", { noCollide = true })
	end
	return parts
end

-- A sapling: a thin stem with a few small tufts of needles, in group "crown" like a grown tree.
function Models.Sapling(seed)
	local rng = Models.Rng(seed)
	local parts = {}
	add(parts, { name = "Trunk", size = { 1.4, 0.3, 1.4 }, pos = { 0, 0.15, 0 }, color = { 104, 82, 58 }, material = "Ground" })
	post(parts, 1.8, 0.22, { 0, 1, 0 }, vary({ 110, 78, 50 }, rng, 6), "Wood")
	for i = 0, 2 do
		local s = 1.3 - i * 0.35
		add(parts, { shape = "Wedge", size = { s, 0.7, s / 2 }, pos = { 0, 1.2 + i * 0.45, s / 4 }, color = vary({ 64, 128, 58 }, rng, 10), material = "LeafyGrass", noCollide = true })
		add(parts, { shape = "Wedge", size = { s, 0.7, s / 2 }, pos = { 0, 1.2 + i * 0.45, -s / 4 }, rot = { 0, math.pi, 0 }, color = vary({ 64, 128, 58 }, rng, 10), material = "LeafyGrass", noCollide = true })
	end
	return parts
end

-- A belt tile, 4 × 4 studs: a rubber belt between two rails with rollers at the ends and arrows the
-- way it runs, to its front (-z). Items ride on it at y = 0.95 (Models.BeltSlot). A belt fed from
-- one side only turns the corner (Logistics.Bend): `bend` -1 comes in from its left (-x), 1 from its
-- right (+x), and the belt is a quarter circle round the front corner on that side.
function Models.Belt(bend)
	local parts = {}
	local rail = { 92, 96, 104 }
	local trim = { 222, 176, 44 }
	local white = { 240, 236, 220 }
	if bend == nil or bend == 0 then
		add(parts, { name = "Body", size = { 3.3, 0.25, 4 }, pos = { 0, 0.6, 0 }, color = { 40, 40, 44 }, material = "Fabric" })
		for _, x in ipairs({ -1.83, 1.83 }) do
			add(parts, { size = { 0.36, 0.9, 4 }, pos = { x, 0.45, 0 }, color = rail, material = "Metal" })
			add(parts, { size = { 0.38, 0.08, 4 }, pos = { x, 0.93, 0 }, color = trim, material = "SmoothPlastic" })
		end
		for _, z in ipairs({ -1.8, 1.8 }) do
			log(parts, 3.3, 0.5, { 0, 0.42, z }, 0, { 70, 72, 78 }, "Metal")
		end
		-- Bright arrows pointing the way the belt runs, standing a little off the belt.
		for _, tip in ipairs({ -1.5, 0.5 }) do
			add(parts, { size = { 0.26, 0.08, 1.15 }, pos = { -0.345, 0.77, tip + 0.46 }, rot = { 0, -0.6435, 0 }, color = white, material = "SmoothPlastic", noCollide = true })
			add(parts, { size = { 0.26, 0.08, 1.15 }, pos = { 0.345, 0.77, tip + 0.46 }, rot = { 0, 0.6435, 0 }, color = white, material = "SmoothPlastic", noCollide = true })
		end
		return parts
	end
	-- The corner the belt turns round, and a point at radius r and angle a (0 where it comes in,
	-- pi/2 where it leaves), with the yaw of the way it runs there (local +z along the way).
	local cx, cz = 2 * bend, -2
	local function at(r, a)
		return cx - bend * r * math.sin(a), cz + r * math.cos(a), -bend * (math.pi / 2 + a)
	end
	local n = 8
	for k = 1, n do
		local a = (k - 0.5) / n * math.pi / 2
		local x, z, yaw = at(2, a)
		add(parts, { name = k == 1 and "Body" or nil, size = { 3.3, 0.25, 3.75 * math.pi / 2 / n + 0.05 }, pos = { x, 0.6, z }, rot = { 0, yaw, 0 }, color = { 40, 40, 44 }, material = "Fabric" })
		local ox, oz, oyaw = at(3.83, a)
		add(parts, { size = { 0.36, 0.9, 3.83 * math.pi / 2 / n + 0.12 }, pos = { ox, 0.45, oz }, rot = { 0, oyaw, 0 }, color = rail, material = "Metal" })
		add(parts, { size = { 0.38, 0.08, 3.83 * math.pi / 2 / n + 0.12 }, pos = { ox, 0.93, oz }, rot = { 0, oyaw, 0 }, color = trim, material = "SmoothPlastic" })
	end
	post(parts, 0.9, 0.7, { cx, 0.45, cz }, rail, "Metal")
	post(parts, 0.08, 0.72, { cx, 0.93, cz }, trim, "SmoothPlastic")
	-- Arrows along the curve, pointing the way it runs.
	for _, a in ipairs({ math.pi / 8, math.pi * 3 / 8 }) do
		local tx, tz, yaw = at(2, a + 0.12)
		-- The arrow's own front (-z) points the way the belt runs.
		local front = yaw + math.pi
		local c, sn = math.cos(front), math.sin(front)
		for _, side in ipairs({ -1, 1 }) do
			local lx, lz = side * 0.345, 0.46
			add(parts, {
				size = { 0.26, 0.08, 1.15 },
				pos = { tx + lx * c + lz * sn, 0.77, tz - lx * sn + lz * c },
				rot = { 0, front + side * 0.6435, 0 },
				color = white,
				material = "SmoothPlastic",
				noCollide = true,
			})
		end
	end
	return parts
end

-- Where item `slot` (1..8, lane after lane, from where items come on to where they leave) rides on
-- a belt with `bend` (see Models.Belt), in the belt's own coordinates; `back` is the place one slot
-- behind it, where it slid from. The left lane (as the belt runs) is the inner one of a left turn.
function Models.BeltSlot(slot, slots, bend, back)
	local lane = math.floor((slot - 1) / slots)
	local t = ((slot - 1) % slots + 0.5) / slots - (back and 1 / slots or 0)
	if bend == nil or bend == 0 then
		return { lane == 0 and -0.8 or 0.8, 0.95, 2 - 4 * t }
	end
	local r = 2 + (lane == 0 and 0.8 or -0.8) * bend
	local a = t * math.pi / 2
	return { 2 * bend - bend * r * math.sin(a), 0.95, -2 + r * math.cos(a) }
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
	-- A piston under the arm, a joint at its elbow and a cable down the column.
	add(parts, { shape = "Cylinder", size = { 1.1, 0.22, 0.22 }, pos = { 0, 2.15, -0.5 }, rot = { 0, math.pi / 2, 0.55 }, color = { 200, 204, 210 }, material = "Metal", group = "arm" })
	add(parts, { shape = "Cylinder", size = { 0.55, 0.36, 0.36 }, pos = { 0.27, 2.6, -1.8 }, color = steel, material = "Metal", group = "arm" })
	add(parts, { size = { 0.14, 1.3, 0.14 }, pos = { 0.42, 1.55, 0.25 }, color = { 30, 30, 32 }, material = "Rubber" })
	ball(parts, 0.3, { -0.42, 2.1, 0.3 }, { 80, 200, 90 }, "Neon", { noCollide = true })
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
-- tile it picks up from (blue outline, behind it) and the tile it drops on (green, in front).
function Models.BuildMarker(kind, tile)
	local parts = {}
	local glow = { 255, 220, 70 }
	local heights = { furniture_furnace = 12.5, furniture_foundry = 14, furniture_sawmill = 6.5, furniture_stonemason = 6.5, furniture_crusher = 7.5, power_generator = 12, power_pole = 11, furniture_workbench = 7 }
	local y = heights[kind] or 5
	add(parts, { size = { 0.5, 0.3, 2.4 }, pos = { 0, y, 0.6 }, color = glow, material = "Neon", noCollide = true })
	add(parts, { size = { 0.5, 0.3, 1.7 }, pos = { -0.5, y, -1 }, rot = { 0, -0.75, 0 }, color = glow, material = "Neon", noCollide = true })
	add(parts, { size = { 0.5, 0.3, 1.7 }, pos = { 0.5, y, -1 }, rot = { 0, 0.75, 0 }, color = glow, material = "Neon", noCollide = true })
	if kind == "logistics_inserter" then
		-- Outlines of the two tiles, so they do not hide what is on them.
		for _, mark in ipairs({ { tile, { 80, 150, 255 } }, { -tile, { 90, 230, 120 } } }) do
			local z, color = mark[1], mark[2]
			local h = tile / 2 - 0.3
			add(parts, { size = { 2 * h, 0.12, 0.2 }, pos = { 0, 0.15, z - h }, color = color, material = "Neon", noCollide = true })
			add(parts, { size = { 2 * h, 0.12, 0.2 }, pos = { 0, 0.15, z + h }, color = color, material = "Neon", noCollide = true })
			add(parts, { size = { 0.2, 0.12, 2 * h }, pos = { -h, 0.15, z }, color = color, material = "Neon", noCollide = true })
			add(parts, { size = { 0.2, 0.12, 2 * h }, pos = { h, 0.15, z }, color = color, material = "Neon", noCollide = true })
		end
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
	-- Iron corners, feet and a handle on each end.
	for _, x in ipairs({ -1.45, 1.45 }) do
		for _, z in ipairs({ -1.05, 1.05 }) do
			add(parts, { size = { 0.26, 0.5, 0.26 }, pos = { x, 0.35, z }, color = Iron, material = "Metal" })
			add(parts, { size = { 0.26, 0.4, 0.26 }, pos = { x, 1.55, z }, color = Iron, material = "Metal" })
		end
		add(parts, { size = { 0.12, 0.14, 0.9 }, pos = { x * 1.12, 1.15, 0 }, color = { 50, 50, 54 }, material = "Metal" })
	end
	for _, x in ipairs({ -0.75, 0.75 }) do
		add(parts, { size = { 0.22, 1.25, 0.08 }, pos = { x, 0.9, -1.12 }, color = Iron, material = "Metal" })
	end
	return parts
end

-- The processing machines on the build grid (Shared.Processing), 2 × 2 tiles (8 studs) across but
-- the foundry 3 × 3. Each has a part named "Body" for its prompt; parts in group "spin" turn while
-- it works (a saw blade, rollers, a grinding wheel, about their own x axis) and parts in "glow"
-- light up like a furnace's fire.
local Steel = { 92, 96, 104 }
local Hazard = { 222, 176, 44 }

local function sawmill()
	local rng = Models.Rng(41)
	local parts = {}
	add(parts, { size = { 7.4, 0.5, 7.4 }, pos = { 0, 0.25, 0 }, color = vary(Planks, rng, 8), material = "WoodPlanks" })
	-- The saw table on four legs, a log on it and the blade through its middle.
	add(parts, { name = "Body", size = { 2.6, 0.5, 6.4 }, pos = { 0, 2.6, 0 }, color = vary(Wood, rng, 8), material = "WoodPlanks" })
	for _, x in ipairs({ -1.1, 1.1 }) do
		for _, z in ipairs({ -2.8, 2.8 }) do
			add(parts, { size = { 0.4, 2.1, 0.4 }, pos = { x, 1.4, z }, color = DarkWood, material = "Wood" })
		end
	end
	add(parts, { shape = "Cylinder", size = { 0.18, 3.4, 3.4 }, pos = { 0, 3.2, -0.4 }, color = { 200, 204, 210 }, material = "Metal", group = "spin", noCollide = true })
	post(parts, 0.3, 0.7, { 0, 3.2, -0.4 }, Steel, "Metal", { rot = { 0, 0, 0 }, noCollide = true })
	log(parts, 3.2, 1.3, { 0, 3.5, 1.7 }, math.pi / 2, vary({ 120, 86, 56 }, rng, 8), "Wood")
	-- A guard over the top of the blade.
	add(parts, { size = { 0.5, 0.5, 2.6 }, pos = { 0, 4.75, -0.4 }, color = Hazard, material = "Metal" })
	-- Logs waiting behind, and sawdust under the blade.
	for _, p in ipairs({ { -0.6, 0.95 }, { 0.6, 0.95 }, { 0, 1.95 } }) do
		log(parts, 3.2, 1.1, { 2.2, p[2], 2.8 + p[1] }, 0, vary({ 120, 86, 56 }, rng, 10), "Wood")
	end
	ball(parts, 1.4, { 0.4, 0.4, -1.6 }, { 214, 180, 120 }, "Sand", { noCollide = true })
	-- Planks sawn off, stacked by the table.
	for i = 0, 3 do
		add(parts, { size = { 1.6, 0.25, 4.6 }, pos = { -2.6, 0.62 + i * 0.26, 0.2 + rng.Num(-0.15, 0.15) }, color = vary({ 196, 152, 98 }, rng, 10), material = "WoodPlanks" })
	end
	-- The motor in a steel box, with a belt to the blade's shaft.
	add(parts, { size = { 1.8, 1.6, 1.8 }, pos = { 2.5, 1.3, -1.2 }, color = Steel, material = "DiamondPlate" })
	post(parts, 0.4, 1.2, { 2.5, 2.3, -1.2 }, Hazard, "SmoothPlastic", { rot = { 0, 0, 0 }, group = "spin" })
	add(parts, { size = { 2.4, 0.2, 0.2 }, pos = { 1.25, 2.8, -0.8 }, rot = { 0, 0, 0.35 }, color = { 30, 30, 32 }, material = "Rubber", noCollide = true })
	-- A lamp that lights while it saws.
	ball(parts, 0.5, { 2.5, 2.4, -2.2 }, { 60, 50, 40 }, "SmoothPlastic", { group = "glow", noCollide = true })
	return parts
end

local function stonemason()
	local rng = Models.Rng(43)
	local parts = {}
	local blue = { 54, 92, 132 }
	add(parts, { size = { 7.4, 0.4, 7.4 }, pos = { 0, 0.2, 0 }, color = vary(Stone, rng, 8), material = "Slate" })
	-- The saw's cabinet with a slab of stone on its sliding table.
	add(parts, { name = "Body", size = { 3.4, 1.8, 5.2 }, pos = { -0.8, 1.3, 0.2 }, color = blue, material = "Metal" })
	add(parts, { size = { 3.8, 0.25, 5.6 }, pos = { -0.8, 2.32, 0.2 }, color = Steel, material = "DiamondPlate" })
	for _, z in ipairs({ -2.1, 2.5 }) do
		add(parts, { size = { 3.9, 0.3, 0.3 }, pos = { -0.8, 2.6, z }, color = { 60, 62, 68 }, material = "Metal" })
	end
	add(parts, { size = { 2.8, 0.7, 3.2 }, pos = { -0.8, 2.8, 0.5 }, color = vary({ 180, 176, 168 }, rng, 6), material = "Limestone" })
	-- A column at the back with an arm over the table; the blade hangs from it in a guard.
	add(parts, { size = { 0.9, 5.4, 0.9 }, pos = { -0.8, 2.9, 3.1 }, color = blue, material = "Metal" })
	add(parts, { size = { 0.8, 0.8, 3.8 }, pos = { -0.8, 5.4, 1.5 }, color = blue, material = "Metal" })
	add(parts, { size = { 1.3, 1.1, 1.4 }, pos = { -0.8, 6.1, 2.4 }, color = { 70, 74, 80 }, material = "Metal" })
	add(parts, { shape = "Cylinder", size = { 0.16, 2.6, 2.6 }, pos = { -0.8, 3.9, 0 }, color = { 200, 204, 210 }, material = "Metal", group = "spin", noCollide = true })
	add(parts, { size = { 0.6, 0.9, 2.9 }, pos = { -0.8, 4.75, 0 }, color = Hazard, material = "Metal" })
	-- Water for the blade from a tank, so it cuts without dust.
	post(parts, 2.4, 1.3, { 2.6, 1.6, 2.6 }, { 80, 120, 150 }, "Metal")
	log(parts, 3.4, 0.18, { 0.9, 4.3, 2.6 }, 0, Iron, "Metal")
	-- Dressed blocks on a pallet in front, rough stone behind.
	add(parts, { size = { 2.6, 0.3, 2.6 }, pos = { 2.2, 0.55, -2.2 }, color = vary(Planks, rng, 8), material = "WoodPlanks" })
	for i = 0, 1 do
		for j = 0, 1 do
			add(parts, { size = { 1.15, 0.9, 1.15 }, pos = { 1.6 + i * 1.2, 1.15, -2.8 + j * 1.2 }, color = vary({ 176, 172, 164 }, rng, 8), material = "Limestone" })
		end
	end
	add(parts, { size = { 1.15, 0.9, 1.15 }, pos = { 1.6, 2.06, -2.8 }, color = vary({ 176, 172, 164 }, rng, 8), material = "Limestone" })
	for _ = 1, 4 do
		ball(parts, rng.Num(0.9, 1.4), { rng.Num(1.6, 3.2), 0.6, rng.Num(-0.6, 1) }, vary(Stone, rng, 12), "Rock")
	end
	-- A lamp on the arm that lights while it works.
	ball(parts, 0.5, { -0.8, 5.1, -0.4 }, { 60, 50, 40 }, "SmoothPlastic", { group = "glow", noCollide = true })
	return parts
end

local function crusher()
	local rng = Models.Rng(45)
	local parts = {}
	local dark = { 62, 64, 70 }
	add(parts, { size = { 7.4, 0.5, 7.4 }, pos = { 0, 0.25, 0 }, color = { 70, 72, 78 }, material = "DiamondPlate" })
	-- The housing on four steel legs, ribbed, with a heavy flywheel on each side.
	for _, x in ipairs({ -1.8, 1.8 }) do
		for _, z in ipairs({ -0.7, 2.1 }) do
			add(parts, { size = { 0.5, 2.2, 0.5 }, pos = { x, 1.6, z }, color = dark, material = "Metal" })
		end
	end
	add(parts, { name = "Body", size = { 4.2, 2.6, 3.4 }, pos = { 0, 4, 0.7 }, color = Steel, material = "Metal" })
	for _, x in ipairs({ -1.4, 0, 1.4 }) do
		add(parts, { size = { 0.3, 2.7, 3.55 }, pos = { x, 4, 0.7 }, color = dark, material = "Metal" })
	end
	for _, x in ipairs({ -2.35, 2.35 }) do
		add(parts, { shape = "Cylinder", size = { 0.35, 3.2, 3.2 }, pos = { x, 3.8, 0.7 }, color = { 48, 50, 56 }, material = "Metal", group = "spin", noCollide = true })
		add(parts, { shape = "Cylinder", size = { 0.5, 0.9, 0.9 }, pos = { x * 1.06, 3.8, 0.7 }, color = Hazard, material = "Metal", group = "spin", noCollide = true })
	end
	-- The hopper on top, and the two rollers in it that crush the stone.
	add(parts, { shape = "Wedge", size = { 5, 1.8, 1.7 }, pos = { 0, 6.2, 2.4 }, rot = { 0, math.pi, 0 }, color = Hazard, material = "Metal" })
	add(parts, { shape = "Wedge", size = { 5, 1.8, 1.7 }, pos = { 0, 6.2, -1 }, color = Hazard, material = "Metal" })
	for _, x in ipairs({ -2.4, 2.4 }) do
		add(parts, { size = { 0.25, 1.8, 5.1 }, pos = { x, 6.2, 0.7 }, color = Hazard, material = "Metal" })
	end
	for _, z in ipairs({ 0.1, 1.3 }) do
		add(parts, { shape = "Cylinder", size = { 4.4, 1.1, 1.1 }, pos = { 0, 5.6, z }, color = { 58, 60, 64 }, material = "CorrodedMetal", group = "spin", noCollide = true })
	end
	for i = 0, 4 do
		ball(parts, rng.Num(0.5, 0.8), { rng.Num(-1.6, 1.6), 6.4, rng.Num(0, 1.4) }, vary(Stone, rng, 12), "Rock", { noCollide = true })
	end
	-- A conveyor from under the rollers out to a heap at the front.
	local tilt = 0.42
	add(parts, { size = { 1.8, 0.3, 3.6 }, pos = { 0, 1.75, -2.2 }, rot = { -tilt, 0, 0 }, color = { 32, 32, 34 }, material = "Rubber" })
	for _, x in ipairs({ -1, 1 }) do
		add(parts, { size = { 0.2, 0.6, 3.6 }, pos = { x, 1.85, -2.2 }, rot = { -tilt, 0, 0 }, color = Hazard, material = "Metal" })
	end
	for _ = 1, 6 do
		ball(parts, rng.Num(0.8, 1.3), { rng.Num(-0.8, 0.8), 0.6, rng.Num(-3.6, -2.9) }, vary({ 150, 140, 120 }, rng, 10), "Sand", { noCollide = true })
	end
	-- The motor behind, under a guard over the drive, and a ladder up to the hopper.
	add(parts, { size = { 2.2, 1.4, 1.4 }, pos = { 0.6, 1.2, 3 }, color = { 50, 90, 140 }, material = "Metal" })
	add(parts, { shape = "Cylinder", size = { 2.3, 1.1, 1.1 }, pos = { 0.6, 1.2, 3 }, color = { 40, 72, 112 }, material = "Metal" })
	add(parts, { size = { 0.3, 3, 1 }, pos = { 2.75, 2.5, 2.4 }, rot = { 0.5, 0, 0 }, color = Hazard, material = "Metal" })
	for _, z in ipairs({ 2.3, 3.1 }) do
		add(parts, { size = { 0.15, 5.8, 0.15 }, pos = { -2.9, 3.4, z }, color = dark, material = "Metal" })
	end
	for i = 0, 6 do
		add(parts, { size = { 0.12, 0.12, 0.9 }, pos = { -2.9, 1 + i * 0.75, 2.7 }, color = dark, material = "Metal" })
	end
	-- A warning light that glows while it runs.
	post(parts, 0.5, 0.5, { 1.9, 7.35, 2.9 }, { 60, 50, 40 }, "SmoothPlastic", { group = "glow", noCollide = true })
	return parts
end

local function foundry()
	local rng = Models.Rng(47)
	local parts = {}
	local brick = { 156, 70, 52 }
	add(parts, { size = { 11.4, 0.5, 11.4 }, pos = { 0, 0.25, 0 }, color = vary(Stone, rng, 8), material = "Cobblestone" })
	-- A brick hall with the fire mouth at the front and a tall chimney.
	add(parts, { name = "Body", size = { 8, 5.5, 7 }, pos = { 0, 3.25, 1 }, color = vary(brick, rng, 6), material = "Brick" })
	add(parts, { shape = "Wedge", size = { 8.6, 2.2, 3.8 }, pos = { 0, 7.1, -0.9 }, color = { 90, 60, 50 }, material = "Slate" })
	add(parts, { shape = "Wedge", size = { 8.6, 2.2, 3.8 }, pos = { 0, 7.1, 2.9 }, rot = { 0, math.pi, 0 }, color = { 90, 60, 50 }, material = "Slate" })
	add(parts, { size = { 2, 11, 2 }, pos = { 2.6, 6, 3.2 }, color = vary(brick, rng, 6), material = "Brick" })
	add(parts, { name = "Chimney", size = { 2.4, 0.5, 2.4 }, pos = { 2.6, 11.7, 3.2 }, color = { 60, 50, 46 }, material = "Slate", smoke = true })
	add(parts, { size = { 3.2, 2.6, 0.6 }, pos = { -1, 2.1, -2.6 }, color = { 30, 24, 20 }, material = "SmoothPlastic", group = "glow", noCollide = true })
	add(parts, { name = "Fire", size = { 2.4, 0.5, 0.8 }, pos = { -1, 1.1, -2.5 }, color = { 30, 26, 24 }, material = "SmoothPlastic", group = "glow", noCollide = true, fire = true, light = { color = { 255, 140, 50 }, range = 18, brightness = 3 } })
	-- A crucible on a stand pouring into moulds in front.
	post(parts, 1.6, 1.8, { 3, 2.4, -3.4 }, Steel, "Metal")
	post(parts, 1.2, 1.4, { 3, 3.6, -3.4 }, { 70, 64, 60 }, "Metal")
	post(parts, 0.2, 1.1, { 3, 4.15, -3.4 }, { 40, 30, 26 }, "SmoothPlastic", { group = "glow", noCollide = true })
	for i = 0, 2 do
		add(parts, { size = { 1.2, 0.5, 0.7 }, pos = { -3.6 + i * 1.5, 0.75, -4.4 }, color = Iron, material = "Metal" })
		add(parts, { size = { 0.9, 0.1, 0.45 }, pos = { -3.6 + i * 1.5, 1.02, -4.4 }, color = { 40, 30, 26 }, material = "SmoothPlastic", group = "glow", noCollide = true })
	end
	-- Windows on the sides, glowing while it works, and a steel door.
	for _, z in ipairs({ -0.6, 2.6 }) do
		for _, x in ipairs({ -4.05, 4.05 }) do
			add(parts, { size = { 0.2, 1.4, 1.2 }, pos = { x, 3.6, z }, color = { 40, 30, 26 }, material = "SmoothPlastic", group = "glow", noCollide = true })
			add(parts, { size = { 0.3, 0.25, 1.5 }, pos = { x * 1.01, 2.8, z }, color = { 210, 196, 170 }, material = "Sandstone" })
		end
	end
	add(parts, { size = { 1.8, 3, 0.3 }, pos = { 2.2, 2, -2.6 }, color = { 70, 72, 78 }, material = "DiamondPlate" })
	-- Coal by the door.
	for _ = 1, 4 do
		ball(parts, rng.Num(0.7, 1.1), { rng.Num(-4.6, -3.6), 0.7, rng.Num(-1.5, 0.5) }, { 40, 40, 44 }, "Basalt")
	end
	return parts
end

local function mill()
	local rng = Models.Rng(59)
	local parts = {}
	add(parts, { size = { 7.4, 0.5, 7.4 }, pos = { 0, 0.25, 0 }, color = vary(Stone, rng, 8), material = "Cobblestone" })
	-- A stone plinth with the millstones on it under a little roof on four posts.
	add(parts, { name = "Body", size = { 4.2, 1.6, 4.2 }, pos = { -0.6, 1.3, 0.4 }, color = vary({ 150, 144, 134 }, rng, 6), material = "Cobblestone" })
	post(parts, 0.6, 3.6, { -0.6, 2.4, 0.4 }, { 160, 156, 150 }, "Limestone")
	post(parts, 0.5, 3.4, { -0.6, 2.95, 0.4 }, { 176, 172, 164 }, "Limestone", { group = "spin" })
	post(parts, 0.55, 0.6, { -0.6, 3.25, 0.4 }, DarkWood, "Wood", { group = "spin" })
	-- The hopper of grain over the stones.
	add(parts, { shape = "Wedge", size = { 2, 1, 1 }, pos = { -0.6, 4.3, 0.9 }, rot = { 0, math.pi, 0 }, color = Planks, material = "WoodPlanks" })
	add(parts, { shape = "Wedge", size = { 2, 1, 1 }, pos = { -0.6, 4.3, -0.1 }, color = Planks, material = "WoodPlanks" })
	add(parts, { size = { 1.8, 0.2, 0.9 }, pos = { -0.6, 4.65, 0.4 }, color = { 226, 196, 100 }, material = "Sand", noCollide = true })
	for _, x in ipairs({ -2.9, 1.7 }) do
		for _, z in ipairs({ -1.9, 2.7 }) do
			add(parts, { size = { 0.4, 5.2, 0.4 }, pos = { x, 3.1, z }, color = vary(Wood, rng, 6), material = "Wood" })
		end
	end
	add(parts, { shape = "Wedge", size = { 5.4, 1.4, 2.6 }, pos = { -0.6, 6.4, -0.9 }, color = { 150, 70, 52 }, material = "Slate" })
	add(parts, { shape = "Wedge", size = { 5.4, 1.4, 2.6 }, pos = { -0.6, 6.4, 1.7 }, rot = { 0, math.pi, 0 }, color = { 150, 70, 52 }, material = "Slate" })
	-- The electric motor with a shaft to the stones, and a lamp that lights while it grinds.
	add(parts, { size = { 1.4, 1.2, 1.6 }, pos = { 2.6, 1.1, 0.4 }, color = { 50, 90, 140 }, material = "Metal" })
	log(parts, 1.6, 0.3, { 1.4, 1.5, 0.4 }, 0, Iron, "Metal", { group = "spin" })
	ball(parts, 0.45, { 2.6, 2, 0.4 }, { 60, 50, 40 }, "SmoothPlastic", { group = "glow", noCollide = true })
	-- Sacks of flour in front and wheat behind.
	for i = 0, 2 do
		ball(parts, 1.1, { 1.2 + i * 0.9, 0.95, -2.7 }, vary({ 236, 230, 214 }, rng, 6), "Fabric")
	end
	for _ = 1, 3 do
		post(parts, 1.2, 0.9, { rng.Num(1.6, 3.2), 1.1, rng.Num(2.2, 3.2) }, vary({ 216, 184, 96 }, rng, 10), "Fabric")
	end
	return parts
end

local function bakery()
	local rng = Models.Rng(61)
	local parts = {}
	local brick = { 172, 86, 60 }
	add(parts, { size = { 7.4, 0.5, 7.4 }, pos = { 0, 0.25, 0 }, color = vary({ 176, 160, 140 }, rng, 6), material = "Pavement" })
	-- A brick base with the round oven on it, its mouth to the front and a chimney behind.
	add(parts, { name = "Body", size = { 5, 2, 4.6 }, pos = { 0, 1.5, 0.8 }, color = vary(brick, rng, 6), material = "Brick" })
	ball(parts, 4.6, { 0, 2.5, 0.9 }, vary(brick, rng, 6), "Brick")
	add(parts, { size = { 1.8, 1.4, 0.4 }, pos = { 0, 3, -1.25 }, color = { 30, 24, 20 }, material = "SmoothPlastic", group = "glow", noCollide = true })
	add(parts, { size = { 2.2, 0.3, 0.6 }, pos = { 0, 3.85, -1.3 }, color = { 210, 196, 170 }, material = "Sandstone" })
	add(parts, { name = "Fire", size = { 1.2, 0.3, 0.6 }, pos = { 0, 2.45, -1 }, color = { 30, 26, 24 }, material = "SmoothPlastic", group = "glow", noCollide = true, fire = true, light = { color = { 255, 150, 60 }, range = 12, brightness = 2 } })
	add(parts, { size = { 1, 3.4, 1 }, pos = { 0, 5.2, 2.4 }, color = vary(brick, rng, 6), material = "Brick" })
	add(parts, { name = "Chimney", size = { 1.3, 0.3, 1.3 }, pos = { 0, 7, 2.4 }, color = { 60, 50, 46 }, material = "Slate", smoke = true })
	-- A peel leaning on the oven, a rack of loaves and a sack of flour.
	add(parts, { size = { 0.2, 4, 0.2 }, pos = { 2.2, 2.4, -1.4 }, rot = { 0, 0, -0.3 }, color = vary(Wood, rng, 6), material = "Wood" })
	add(parts, { size = { 0.9, 0.12, 0.9 }, pos = { 1.6, 0.7, -1.4 }, color = vary(Planks, rng, 6), material = "WoodPlanks" })
	for _, y in ipairs({ 1, 2.2 }) do
		add(parts, { size = { 2.4, 0.15, 1 }, pos = { -2.4, y, -2.6 }, color = vary(Planks, rng, 8), material = "WoodPlanks" })
		for k = 0, 2 do
			ball(parts, 0.65, { -3.1 + k * 0.7, y + 0.3, -2.6 }, vary({ 196, 130, 70 }, rng, 10), "Sand")
		end
	end
	for _, x in ipairs({ -3.5, -1.3 }) do
		add(parts, { size = { 0.15, 2.4, 0.15 }, pos = { x, 1.4, -2.6 }, color = DarkWood, material = "Wood" })
	end
	ball(parts, 1.3, { 2.9, 1.1, 2.6 }, vary({ 236, 230, 214 }, rng, 6), "Fabric")
	return parts
end

local function plant(parts, rng, crop, stage, x, z)
	local green = vary({ 76, 150, 60 }, rng, 10)
	if stage == 1 then
		ball(parts, 0.45, { x, 0.55, z }, green, "Grass", { noCollide = true })
		return
	end
	local grow = stage == 3 and 1 or 0.55
	if crop == Items.Wheat or crop == Items.Corn then
		local tall = (crop == Items.Corn and 3.4 or 2.2) * grow
		local stalk = stage == 3 and crop == Items.Wheat and { 214, 180, 90 } or green
		for _, d in ipairs({ -0.25, 0.25 }) do
			add(parts, { size = { 0.12, tall, 0.12 }, pos = { x + d, 0.4 + tall / 2, z + d * 0.6 }, rot = { rng.Num(-0.12, 0.12), 0, rng.Num(-0.12, 0.12) }, color = stalk, material = "Grass", noCollide = true })
		end
		if stage == 3 then
			if crop == Items.Wheat then
				for _, d in ipairs({ -0.25, 0.25 }) do
					add(parts, { size = { 0.22, 0.6, 0.22 }, pos = { x + d, 0.4 + tall + 0.2, z + d * 0.6 }, color = vary({ 232, 196, 100 }, rng, 8), material = "Sand", noCollide = true })
				end
			else
				add(parts, { size = { 0.35, 0.9, 0.35 }, pos = { x + 0.25, 0.4 + tall * 0.6, z }, rot = { 0, 0, -0.3 }, color = vary({ 246, 210, 70 }, rng, 8), material = "Sand", noCollide = true })
				add(parts, { size = { 0.8, 0.12, 0.3 }, pos = { x, 0.4 + tall * 0.75, z }, rot = { 0, 0, 0.5 }, color = green, material = "Grass", noCollide = true })
			end
		end
	elseif crop == Items.Sunflower then
		local tall = 3.6 * grow
		post(parts, tall, 0.2, { x, 0.4 + tall / 2, z }, green, "Grass", { noCollide = true })
		add(parts, { size = { 0.7, 0.1, 0.3 }, pos = { x + 0.3, 0.4 + tall * 0.5, z }, color = green, material = "Grass", noCollide = true })
		if stage == 3 then
			add(parts, { shape = "Cylinder", size = { 0.15, 1.3, 1.3 }, pos = { x, 0.4 + tall, z - 0.15 }, rot = { 0, math.pi / 2, 0 }, color = { 250, 200, 40 }, material = "SmoothPlastic", noCollide = true })
			add(parts, { shape = "Cylinder", size = { 0.2, 0.6, 0.6 }, pos = { x, 0.4 + tall, z - 0.2 }, rot = { 0, math.pi / 2, 0 }, color = { 90, 60, 30 }, material = "Sand", noCollide = true })
		end
	elseif crop == Items.Cabbage then
		ball(parts, 1.2 * grow + 0.2, { x, 0.4 + 0.5 * grow, z }, stage == 3 and vary({ 150, 200, 110 }, rng, 8) or green, "Grass", { noCollide = true })
	else
		-- Carrots and potatoes: leafy tufts, with the orange tops of carrots or the flowers of potatoes.
		for _, d in ipairs({ -0.2, 0.2 }) do
			add(parts, { size = { 0.2, 0.9 * grow + 0.2, 0.5 }, pos = { x + d, 0.4 + (0.9 * grow + 0.2) / 2, z }, rot = { 0, d * 2, d }, color = green, material = "Grass", noCollide = true })
		end
		if stage == 3 then
			if crop == Items.Carrot then
				post(parts, 0.3, 0.35, { x, 0.5, z }, { 236, 128, 40 }, "SmoothPlastic", { noCollide = true })
			else
				ball(parts, 0.25, { x, 1.2, z }, { 240, 236, 250 }, "SmoothPlastic", { noCollide = true })
			end
		end
	end
end

-- A field, 2 × 2 tiles: tilled soil in four furrows, and `crop` on it at `stage` (Shared.Farming:
-- 0 nothing, 1 sprouts, 2 growing, 3 ripe). The soil is named "Body".
function Models.Field(crop, stage, seed)
	local rng = Models.Rng(seed or 1)
	local parts = {}
	add(parts, { name = "Body", size = { 7.8, 0.3, 7.8 }, pos = { 0, 0.15, 0 }, color = { 96, 66, 44 }, material = "Ground" })
	for i = 0, 3 do
		add(parts, { size = { 7.4, 0.25, 0.9 }, pos = { 0, 0.4, -2.85 + i * 1.9 }, color = vary({ 110, 76, 50 }, rng, 6), material = "Ground", noCollide = true })
	end
	if crop and stage and stage > 0 then
		for i = 0, 3 do
			for j = 0, 3 do
				plant(parts, rng, crop, stage, -2.85 + j * 1.9, -2.85 + i * 1.9)
			end
		end
	end
	return parts
end

local Machines = {
	furniture_sawmill = sawmill,
	furniture_stonemason = stonemason,
	furniture_crusher = crusher,
	furniture_foundry = foundry,
	furniture_mill = mill,
	furniture_bakery = bakery,
}

-- A steam generator, 2 × 2 tiles: a boiler over a firebox, a chimney, and a steam engine whose
-- flywheel turns a dynamo while it runs ("spin"); the fire and a lamp glow ("glow"). The boiler is
-- named "Body".
function Models.Generator()
	local rng = Models.Rng(53)
	local parts = {}
	local copper = { 196, 112, 60 }
	local brass = { 200, 160, 70 }
	local green = { 66, 112, 82 }
	add(parts, { size = { 7.4, 0.5, 7.4 }, pos = { 0, 0.25, 0 }, color = { 74, 76, 82 }, material = "DiamondPlate" })
	-- The firebox of bricks and the boiler lying on it, banded, with a dome and a safety valve.
	add(parts, { size = { 3.2, 1.8, 5.8 }, pos = { -1.8, 1.4, 0.3 }, color = vary({ 150, 70, 52 }, rng, 6), material = "Brick" })
	add(parts, { name = "Body", shape = "Cylinder", size = { 5.6, 2.8, 2.8 }, pos = { -1.8, 3.6, 0.3 }, rot = { 0, math.pi / 2, 0 }, color = green, material = "Metal" })
	for _, z in ipairs({ -2.2, -0.4, 1.4, 3 }) do
		add(parts, { shape = "Cylinder", size = { 0.22, 2.95, 2.95 }, pos = { -1.8, 3.6, z }, rot = { 0, math.pi / 2, 0 }, color = brass, material = "Metal" })
	end
	add(parts, { shape = "Cylinder", size = { 0.2, 2.6, 2.6 }, pos = { -1.8, 3.6, -2.55 }, rot = { 0, math.pi / 2, 0 }, color = { 50, 52, 58 }, material = "Metal" })
	post(parts, 1, 1.1, { -1.8, 5.3, -0.9 }, brass, "Metal")
	ball(parts, 1.1, { -1.8, 5.8, -0.9 }, brass, "Metal")
	post(parts, 0.7, 0.35, { -1.8, 5.3, 1.6 }, brass, "Metal")
	-- The pressure gauge on the boiler's front, and the fire door under it.
	add(parts, { shape = "Cylinder", size = { 0.15, 0.9, 0.9 }, pos = { -1.8, 4.2, -2.7 }, rot = { 0, math.pi / 2, 0 }, color = { 240, 236, 220 }, material = "SmoothPlastic" })
	add(parts, { size = { 0.08, 0.4, 0.06 }, pos = { -1.7, 4.3, -2.8 }, rot = { 0, 0, -0.6 }, color = { 180, 30, 30 }, material = "SmoothPlastic", noCollide = true })
	add(parts, { size = { 1.6, 1.1, 0.3 }, pos = { -1.8, 1.3, -2.6 }, color = { 30, 24, 20 }, material = "SmoothPlastic", group = "glow", noCollide = true })
	add(parts, { name = "Fire", size = { 1.2, 0.3, 0.8 }, pos = { -1.8, 0.9, -2.2 }, color = { 30, 26, 24 }, material = "SmoothPlastic", group = "glow", noCollide = true, fire = true, light = { color = { 255, 150, 60 }, range = 14, brightness = 2 } })
	-- The chimney at the back.
	post(parts, 5.8, 0.9, { -1.8, 7.7, 2.5 }, { 50, 52, 58 }, "Metal")
	add(parts, { name = "Chimney", shape = "Cylinder", size = { 0.3, 1.3, 1.3 }, pos = { -1.8, 10.65, 2.5 }, rot = { 0, 0, math.pi / 2 }, color = { 40, 40, 44 }, material = "Metal", smoke = true })
	-- The steam engine on a frame: steam over from the boiler into its cylinder, a rod to the
	-- flywheel and a belt from the flywheel to the dynamo.
	add(parts, { size = { 3, 0.9, 6.2 }, pos = { 1.9, 0.95, 0.3 }, color = { 60, 62, 68 }, material = "Metal" })
	log(parts, 3.2, 0.35, { 0, 5.1, 1.6 }, 0, copper, "Metal")
	post(parts, 2.6, 0.35, { 1.5, 3.85, 1.6 }, copper, "Metal")
	add(parts, { shape = "Cylinder", size = { 2.2, 1.3, 1.3 }, pos = { 1.5, 2.1, 1.7 }, rot = { 0, math.pi / 2, 0 }, color = green, material = "Metal" })
	log(parts, 1.6, 0.2, { 1.5, 2.1, 0 }, math.pi / 2, { 200, 204, 210 }, "Metal")
	add(parts, { shape = "Cylinder", size = { 0.4, 3.2, 3.2 }, pos = { 3, 2.9, -0.9 }, color = { 44, 46, 52 }, material = "Metal", group = "spin", noCollide = true })
	add(parts, { shape = "Cylinder", size = { 0.6, 0.8, 0.8 }, pos = { 3.1, 2.9, -0.9 }, color = Hazard, material = "Metal", group = "spin", noCollide = true })
	log(parts, 1.6, 0.3, { 2.2, 2.9, -0.9 }, 0, Iron, "Metal")
	-- The dynamo: a copper coil in a blue frame, insulators on top where the wires leave.
	add(parts, { size = { 1.8, 1.4, 2 }, pos = { 1.3, 2.1, -2.2 }, color = { 50, 90, 140 }, material = "Metal" })
	add(parts, { shape = "Cylinder", size = { 1.6, 1.5, 1.5 }, pos = { 1.3, 3.1, -2.2 }, color = copper, material = "Metal" })
	add(parts, { size = { 0.2, 1, 0.2 }, pos = { 2.5, 3.2, -1.6 }, rot = { 0.9, 0, 0 }, color = { 30, 30, 32 }, material = "Rubber", noCollide = true })
	for _, x in ipairs({ 0.8, 1.8 }) do
		post(parts, 0.6, 0.35, { x, 4.1, -2.2 }, { 236, 236, 228 }, "Glass")
	end
	ball(parts, 0.5, { 2.4, 2.9, -3.3 }, { 60, 50, 40 }, "SmoothPlastic", { group = "glow", noCollide = true })
	-- Coal by the firebox.
	for _ = 1, 4 do
		ball(parts, rng.Num(0.6, 0.9), { rng.Num(-3.3, -2.5), 0.75, rng.Num(-3.4, -2.6) }, { 40, 40, 44 }, "Basalt")
	end
	return parts
end

-- Where a pole's wires hang from, above the middle of its tile.
Models.PoleTop = 9.1

-- A wooden power pole, 1 tile: a post, a cross-arm and three insulators. The post is named "Body".
function Models.Pole()
	local parts = {}
	post(parts, 0.5, 1.4, { 0, 0.25, 0 }, { 120, 116, 108 }, "Concrete")
	post(parts, 9.4, 0.55, { 0, 4.9, 0 }, { 104, 78, 52 }, "Wood", { name = "Body" })
	add(parts, { size = { 3.2, 0.3, 0.35 }, pos = { 0, 8.6, 0 }, color = { 90, 66, 44 }, material = "Wood" })
	for _, x in ipairs({ -1.3, 0, 1.3 }) do
		post(parts, 0.45, 0.3, { x, 8.95, 0 }, { 236, 236, 228 }, "Glass")
	end
	return parts
end

-- The railway station, 3 × 3 tiles: a brick house with a pitched roof, a clock and a canopy over
-- its front (-z), where the platform is. The house is named "Body".
function Models.Station()
	local rng = Models.Rng(71)
	local parts = {}
	local brick = { 160, 78, 58 }
	local trim = { 226, 214, 190 }
	add(parts, { size = { 11.6, 0.4, 11.6 }, pos = { 0, 0.2, 0 }, color = { 120, 116, 110 }, material = "Concrete" })
	add(parts, { name = "Body", size = { 10, 7, 7 }, pos = { 0, 3.9, 1.6 }, color = vary(brick, rng, 6), material = "Brick" })
	-- Corners and a cornice of light stone.
	for _, x in ipairs({ -5, 5 }) do
		for _, z in ipairs({ -1.9, 5.1 }) do
			add(parts, { size = { 0.7, 7, 0.7 }, pos = { x, 3.9, z }, color = trim, material = "Sandstone" })
		end
	end
	add(parts, { size = { 10.8, 0.5, 7.8 }, pos = { 0, 7.6, 1.6 }, color = trim, material = "Sandstone" })
	-- The roof: two slopes and a ridge.
	add(parts, { shape = "Wedge", size = { 11.2, 2.6, 4.2 }, pos = { 0, 9.15, -0.5 }, color = { 70, 74, 84 }, material = "Slate" })
	add(parts, { shape = "Wedge", size = { 11.2, 2.6, 4.2 }, pos = { 0, 9.15, 3.7 }, rot = { 0, math.pi, 0 }, color = { 70, 74, 84 }, material = "Slate" })
	-- Door and windows on the front, the clock above the door.
	add(parts, { size = { 2, 3.6, 0.2 }, pos = { 0, 2.2, -2 }, color = { 92, 60, 40 }, material = "WoodPlanks" })
	for _, x in ipairs({ -3.4, 3.4 }) do
		add(parts, { size = { 2, 2.2, 0.2 }, pos = { x, 3.6, -2 }, color = { 150, 190, 210 }, material = "Glass" })
		add(parts, { size = { 2.4, 0.3, 0.4 }, pos = { x, 2.4, -2.1 }, color = trim, material = "Sandstone" })
	end
	add(parts, { name = "Clock", shape = "Cylinder", size = { 0.3, 1.8, 1.8 }, pos = { 0, 5.6, -2.1 }, rot = { 0, math.pi / 2, 0 }, color = { 240, 236, 220 }, material = "SmoothPlastic" })
	add(parts, { size = { 0.12, 0.7, 0.1 }, pos = { 0, 5.85, -2.3 }, color = { 30, 30, 30 }, material = "SmoothPlastic" })
	add(parts, { size = { 0.5, 0.12, 0.1 }, pos = { 0.2, 5.6, -2.3 }, color = { 30, 30, 30 }, material = "SmoothPlastic" })
	-- The canopy on posts over the way out to the platform.
	add(parts, { size = { 11, 0.3, 3.6 }, pos = { 0, 6.2, -3.8 }, color = { 60, 90, 70 }, material = "Metal" })
	for _, x in ipairs({ -5, 5 }) do
		post(parts, 6, 0.3, { x, 3.1, -5.4 }, { 60, 90, 70 }, "Metal")
	end
	-- A chimney on the roof, flower boxes under the windows and a bench under the canopy.
	add(parts, { size = { 1, 2.4, 1 }, pos = { 3, 10.2, 2.6 }, color = vary(brick, rng, 6), material = "Brick" })
	add(parts, { size = { 1.3, 0.3, 1.3 }, pos = { 3, 11.5, 2.6 }, color = trim, material = "Sandstone" })
	for _, x in ipairs({ -3.4, 3.4 }) do
		add(parts, { size = { 2.2, 0.5, 0.6 }, pos = { x, 2.1, -2.3 }, color = { 92, 60, 40 }, material = "WoodPlanks" })
		for k = 0, 3 do
			ball(parts, 0.45, { x - 0.75 + k * 0.5, 2.45, -2.3 }, k % 2 == 0 and { 210, 60, 70 } or { 240, 200, 70 }, "SmoothPlastic", { noCollide = true })
		end
	end
	add(parts, { size = { 2.8, 0.25, 0.9 }, pos = { 2.2, 1.3, -3 }, color = Planks, material = "WoodPlanks" })
	add(parts, { size = { 2.8, 0.8, 0.2 }, pos = { 2.2, 1.85, -2.6 }, color = Planks, material = "WoodPlanks" })
	for _, x in ipairs({ 1, 3.4 }) do
		add(parts, { size = { 0.2, 0.9, 0.8 }, pos = { x, 0.85, -3 }, color = { 40, 40, 44 }, material = "Metal" })
	end
	-- A board with the station's colours over the canopy.
	add(parts, { size = { 5, 1, 0.25 }, pos = { 0, 6.9, -5.4 }, color = { 30, 60, 110 }, material = "SmoothPlastic" })
	add(parts, { size = { 4.6, 0.12, 0.27 }, pos = { 0, 6.9, -5.4 }, color = { 240, 236, 220 }, material = "SmoothPlastic", noCollide = true })
	-- Crates waiting to go, and a lamp.
	add(parts, { size = { 1.6, 1.4, 1.6 }, pos = { -3.5, 1.1, -4 }, color = Planks, material = "WoodPlanks" })
	add(parts, { size = { 1.2, 1, 1.2 }, pos = { -3.3, 2.3, -4.1 }, rot = { 0, 0.4, 0 }, color = { 140, 100, 64 }, material = "WoodPlanks" })
	ball(parts, 0.6, { 4, 5.6, -3.8 }, { 255, 226, 150 }, "Neon", { noCollide = true, light = { color = { 255, 214, 150 }, range = 14, brightness = 1 } })
	return parts
end

-- The railway along a plot's east fence, in the plot's own frame: ballast, sleepers and rails
-- along z at `rail.x` from `rail.from` to `rail.to`, the platform by the station (from `stationFrom`
-- to `stationTo` along z) and a tunnel in a rocky hill at each end, its mouth named "North" and
-- "South". Trains run over it (Models.Train).
function Models.Railway(rail, stationFrom, stationTo)
	local rng = Models.Rng(808)
	local parts = {}
	local length = rail.to - rail.from
	local mid = (rail.from + rail.to) / 2
	add(parts, { size = { 5.4, 0.3, length }, pos = { rail.x, 0.15, mid }, color = { 112, 106, 100 }, material = "Pebble" })
	local sleepers = math.floor(length / 2.4)
	for i = 0, sleepers - 1 do
		add(parts, { size = { 4.4, 0.25, 0.7 }, pos = { rail.x, 0.4, rail.from + 1.2 + i * 2.4 }, color = vary({ 86, 64, 46 }, rng, 6), material = "Wood" })
	end
	for _, dx in ipairs({ -1.25, 1.25 }) do
		add(parts, { size = { 0.3, 0.35, length }, pos = { rail.x + dx, 0.7, mid }, color = { 150, 150, 156 }, material = "Metal" })
	end
	-- The platform between the fence and the track.
	local pFrom, pTo = stationFrom - 12, stationTo + 12
	local px = rail.x - 4.6
	add(parts, { size = { 4.6, 1.2, pTo - pFrom }, pos = { px, 0.6, (pFrom + pTo) / 2 }, color = { 150, 146, 140 }, material = "Concrete" })
	add(parts, { size = { 0.4, 0.06, pTo - pFrom }, pos = { px + 2, 1.23, (pFrom + pTo) / 2 }, color = { 230, 196, 50 }, material = "SmoothPlastic", noCollide = true })
	add(parts, { shape = "Wedge", size = { 4.6, 1.2, 3 }, pos = { px, 0.6, pFrom - 1.5 }, color = { 150, 146, 140 }, material = "Concrete" })
	add(parts, { shape = "Wedge", size = { 4.6, 1.2, 3 }, pos = { px, 0.6, pTo + 1.5 }, rot = { 0, math.pi, 0 }, color = { 150, 146, 140 }, material = "Concrete" })
	for _, z in ipairs({ pFrom + 4, pTo - 4 }) do
		post(parts, 5, 0.3, { px - 1.4, 3.7, z }, { 50, 54, 60 }, "Metal")
		ball(parts, 0.7, { px - 1.4, 6.3, z }, { 255, 226, 150 }, "Neon", { noCollide = true })
	end
	add(parts, { size = { 3, 0.3, 1 }, pos = { px - 1, 1.9, (pFrom + pTo) / 2 + 6 }, color = Planks, material = "WoodPlanks" })
	-- A tunnel at each end: a stone face with a dark mouth, in a hill of rocks behind it.
	for _, e in ipairs({ { "North", rail.from, -1 }, { "South", rail.to, 1 } }) do
		local z, out = e[2], e[3]
		add(parts, { size = { 16, 11, 2 }, pos = { rail.x, 5.5, z }, color = vary(Stone, rng, 8), material = "Cobblestone" })
		add(parts, { name = e[1], size = { 5.6, 6.4, 2.2 }, pos = { rail.x, 3.2, z }, color = { 14, 14, 16 }, material = "SmoothPlastic", noCollide = true })
		add(parts, { shape = "Cylinder", size = { 2.2, 5.6, 5.6 }, pos = { rail.x, 6.4, z }, rot = { 0, math.pi / 2, 0 }, color = { 14, 14, 16 }, material = "SmoothPlastic", noCollide = true })
		add(parts, { size = { 16.5, 0.8, 2.4 }, pos = { rail.x, 11.2, z }, color = { 100, 96, 90 }, material = "Slate" })
		-- The hill: rocks either side of the face and over it, grassy ones behind.
		for k, h in ipairs({ { -9, 3, 3 }, { 9, 3, 3 }, { -5, 9, 5 }, { 5, 9, 5 }, { 0, 11, 8 }, { -8, 5, 10 }, { 8, 5, 10 }, { 0, 6, 13 } }) do
			ball(parts, rng.Num(10, 14), { rail.x + h[1], h[2], z + out * h[3] }, vary(k <= 2 and { 120, 116, 108 } or { 98, 120, 74 }, rng, 10), k <= 2 and "Rock" or "Grass")
		end
	end
	return parts
end

-- A steam train heading -z: a locomotive (front at z = 0) and `wagons` open wagons behind it, each
-- with crates of the colours `cargo` (a list of { r, g, b }, used in turn; none: empty). Every
-- part is in the group "train" and nothing collides.
function Models.Train(wagons, cargo)
	local parts = {}
	local black = { 34, 34, 38 }
	local red = { 160, 40, 36 }
	local green = { 40, 92, 62 }
	local brass = { 200, 160, 60 }
	local y0 = 0.9
	local function part(p)
		p.group = "train"
		p.noCollide = true
		return add(parts, p)
	end
	local function wheel(x, z, d, color)
		part({ shape = "Cylinder", size = { 0.4, d, d }, pos = { x, y0 + d / 2 - 0.65, z }, color = color, material = "Metal" })
		part({ shape = "Cylinder", size = { 0.45, d * 0.35, d * 0.35 }, pos = { x * 1.02, y0 + d / 2 - 0.65, z }, color = brass, material = "Metal" })
	end
	-- The locomotive: frame with buffers and a cowcatcher, boiler with bands and domes, chimney,
	-- cab with windows and roof, big driving wheels joined by rods.
	part({ size = { 3.2, 0.6, 10 }, pos = { 0, y0 + 0.6, 5 }, color = black, material = "Metal" })
	part({ size = { 3.4, 0.5, 0.4 }, pos = { 0, y0 + 0.8, -0.1 }, color = red, material = "Metal" })
	for _, x in ipairs({ -1.1, 1.1 }) do
		part({ shape = "Cylinder", size = { 0.6, 0.5, 0.5 }, pos = { x, y0 + 0.8, -0.5 }, rot = { 0, math.pi / 2, 0 }, color = black, material = "Metal" })
	end
	part({ shape = "Wedge", size = { 3, 0.9, 1.2 }, pos = { 0, y0 + 0.1, -0.4 }, color = { 60, 62, 68 }, material = "Metal" })
	part({ shape = "Cylinder", size = { 6.4, 2.6, 2.6 }, pos = { 0, y0 + 2.3, 3.6 }, rot = { 0, math.pi / 2, 0 }, color = green, material = "Metal" })
	for _, z in ipairs({ 1.6, 3.6, 5.6 }) do
		part({ shape = "Cylinder", size = { 0.18, 2.7, 2.7 }, pos = { 0, y0 + 2.3, z }, rot = { 0, math.pi / 2, 0 }, color = brass, material = "Metal" })
	end
	part({ shape = "Cylinder", size = { 0.3, 2.7, 2.7 }, pos = { 0, y0 + 2.3, 0.4 }, rot = { 0, math.pi / 2, 0 }, color = black, material = "Metal" })
	part({ shape = "Cylinder", size = { 1.8, 0.9, 0.9 }, pos = { 0, y0 + 4.2, 1.4 }, rot = { 0, 0, math.pi / 2 }, color = black, material = "Metal", smoke = true })
	part({ shape = "Cylinder", size = { 0.3, 1.25, 1.25 }, pos = { 0, y0 + 5.1, 1.4 }, rot = { 0, 0, math.pi / 2 }, color = black, material = "Metal" })
	part({ shape = "Ball", size = { 1.1, 1.1, 1.1 }, pos = { 0, y0 + 3.7, 3.4 }, color = brass, material = "Metal" })
	part({ shape = "Ball", size = { 0.9, 0.9, 0.9 }, pos = { 0, y0 + 3.6, 5 }, color = green, material = "Metal" })
	-- Cylinders by the front wheels.
	for _, x in ipairs({ -1.55, 1.55 }) do
		part({ shape = "Cylinder", size = { 1.6, 0.8, 0.8 }, pos = { x, y0 + 1.1, 1.3 }, rot = { 0, math.pi / 2, 0 }, color = black, material = "Metal" })
	end
	-- The cab.
	part({ size = { 3.2, 3.6, 3 }, pos = { 0, y0 + 2.9, 8.2 }, color = red, material = "Metal" })
	part({ size = { 3.7, 0.3, 3.6 }, pos = { 0, y0 + 4.85, 8.2 }, color = black, material = "Metal" })
	part({ size = { 3.3, 1.2, 1.2 }, pos = { 0, y0 + 3.4, 7.2 }, color = { 150, 190, 210 }, material = "Glass" })
	for _, x in ipairs({ -1.62, 1.62 }) do
		part({ size = { 0.1, 1.1, 1.4 }, pos = { x, y0 + 3.5, 8.6 }, color = { 150, 190, 210 }, material = "Glass" })
		part({ size = { 0.12, 0.25, 9 }, pos = { x, y0 + 1.2, 4.6 }, color = brass, material = "Metal" })
	end
	part({ size = { 3.3, 0.2, 0.2 }, pos = { 0, y0 + 1.95, 6.65 }, color = brass, material = "Metal" })
	ball(parts, 0.7, { 0, y0 + 2.4, -0.1 }, { 255, 236, 170 }, "Neon", { group = "train", noCollide = true })
	for _, z in ipairs({ 1.6 }) do
		for _, x in ipairs({ -1.5, 1.5 }) do
			wheel(x, z, 1.3, red)
		end
	end
	for _, z in ipairs({ 4.2, 6.8 }) do
		for _, x in ipairs({ -1.5, 1.5 }) do
			wheel(x, z, 2.1, red)
		end
	end
	-- The tender behind the cab, heaped with coal.
	local t0 = 10.2
	part({ size = { 3.2, 0.5, 4.2 }, pos = { 0, y0 + 0.6, t0 + 2.1 }, color = black, material = "Metal" })
	part({ size = { 3.3, 1.9, 4 }, pos = { 0, y0 + 1.8, t0 + 2.1 }, color = green, material = "Metal" })
	part({ size = { 3.4, 0.2, 4.1 }, pos = { 0, y0 + 2.8, t0 + 2.1 }, color = brass, material = "Metal" })
	for k = 0, 2 do
		ball(parts, 1.5, { (k - 1) * 0.8, y0 + 2.8, t0 + 1.1 + k * 0.9 }, { 32, 32, 36 }, "Basalt", { group = "train", noCollide = true })
	end
	for _, z in ipairs({ t0 + 1, t0 + 3.2 }) do
		for _, x in ipairs({ -1.5, 1.5 }) do
			wheel(x, z, 1.3, black)
		end
	end
	-- The wagons, coupled 1 stud apart.
	for w = 1, wagons do
		local z0 = t0 + 4.2 + (w - 1) * 9 + 1
		part({ size = { 3.2, 0.5, 8 }, pos = { 0, y0 + 0.6, z0 + 4 }, color = black, material = "Metal" })
		part({ size = { 3.4, 0.3, 8 }, pos = { 0, y0 + 0.95, z0 + 4 }, color = { 116, 76, 50 }, material = "WoodPlanks" })
		for _, x in ipairs({ -1.6, 1.6 }) do
			for k = 0, 2 do
				part({ size = { 0.2, 0.42, 8 }, pos = { x, y0 + 1.35 + k * 0.46, z0 + 4 }, color = k == 1 and { 128, 86, 56 } or { 108, 70, 46 }, material = "WoodPlanks" })
			end
			for k = 0, 3 do
				part({ size = { 0.26, 1.7, 0.26 }, pos = { x * 1.04, y0 + 1.75, z0 + 0.4 + k * 2.4 }, color = black, material = "Metal" })
			end
		end
		for _, z in ipairs({ z0 + 0.1, z0 + 7.9 }) do
			part({ size = { 3.4, 1.4, 0.2 }, pos = { 0, y0 + 1.8, z }, color = { 108, 70, 46 }, material = "WoodPlanks" })
		end
		part({ size = { 0.4, 0.3, 1.2 }, pos = { 0, y0 + 0.7, z0 - 0.5 }, color = black, material = "Metal" })
		local color = cargo and #cargo > 0 and cargo[(w - 1) % #cargo + 1]
		if color then
			for k = 0, 2 do
				part({ size = { 2.6, 1.2, 2.2 }, pos = { 0, y0 + 2.9, z0 + 1.4 + k * 2.6 }, color = color, material = "SmoothPlastic" })
			end
		end
		for _, z in ipairs({ z0 + 1.5, z0 + 6.5 }) do
			for _, x in ipairs({ -1.5, 1.5 }) do
				wheel(x, z, 1.3, black)
			end
		end
	end
	return parts
end

-- Luau has atan2; plain Lua 5.3 (the tests) has the two-argument atan.
local atan2 = math.atan2 or math.atan

-- A wire hanging between two pole tops `a` and `b` ({ x, y, z } in the same frame), sagging in
-- the middle: a few straight pieces.
function Models.Wire(a, b)
	local parts = {}
	local pieces = 6
	local dx, dz = b[1] - a[1], b[3] - a[3]
	local span = math.sqrt(dx * dx + dz * dz)
	local sag = math.min(1.2, 0.08 * span)
	local function at(f)
		return { a[1] + dx * f, a[2] + (b[2] - a[2]) * f - sag * 4 * f * (1 - f), a[3] + dz * f }
	end
	local yaw = atan2(dx, dz)
	for i = 1, pieces do
		local p, q = at((i - 1) / pieces), at(i / pieces)
		local h = span / pieces
		local dy = q[2] - p[2]
		add(parts, {
			size = { 0.1, 0.1, math.sqrt(h * h + dy * dy) + 0.05 },
			pos = { (p[1] + q[1]) / 2, (p[2] + q[2]) / 2, (p[3] + q[3]) / 2 },
			yaw = yaw,
			rot = { atan2(-dy, h), 0, 0 },
			color = { 30, 30, 32 },
			material = "SmoothPlastic",
			noCollide = true,
		})
	end
	return parts
end

-- The model of processing machine `kind` (an item id).
function Models.Machine(kind)
	return Machines[kind]()
end

return Models
