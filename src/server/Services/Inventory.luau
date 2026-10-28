-- The player's items: { [item id] = quantity }, and the tiles of the inventory window they lie on
-- (`slots`, as on main: each tile holds one kind; "" is an empty tile). A new kind goes on the
-- first empty tile; the player moves items between tiles (Move). Nothing here yields.
local Inventory = {}

-- Tiles of the inventory window (InventoryGrid MIN_TILES on main). Kinds beyond them still fit;
-- the window shows them after these.
Inventory.Tiles = 20

function Inventory.Count(profile, item)
	return profile.inventory[item] or 0
end

local function place(profile, item)
	local slots = profile.slots
	for i, at in ipairs(slots) do
		if at == item then
			return
		end
	end
	for i, at in ipairs(slots) do
		if at == "" then
			slots[i] = item
			return
		end
	end
	table.insert(slots, item)
end

local function clear(profile, item)
	for i, at in ipairs(profile.slots) do
		if at == item then
			profile.slots[i] = ""
		end
	end
end

function Inventory.Add(profile, item, quantity)
	assert(type(quantity) == "number" and quantity > 0 and quantity % 1 == 0, "bad quantity")
	profile.inventory[item] = Inventory.Count(profile, item) + quantity
	if profile.slots then
		place(profile, item)
	end
end

-- Whether the player has all of `items` (a list of { item, quantity }).
function Inventory.HasAll(profile, items, times)
	times = times or 1
	for _, entry in ipairs(items) do
		if Inventory.Count(profile, entry[1]) < entry[2] * times then
			return false
		end
	end
	return true
end

-- Takes `quantity` of `item` if the player has it; false otherwise (nothing changes).
function Inventory.TryRemove(profile, item, quantity)
	assert(type(quantity) == "number" and quantity > 0 and quantity % 1 == 0, "bad quantity")
	local have = Inventory.Count(profile, item)
	if have < quantity then
		return false
	end
	if have == quantity then
		profile.inventory[item] = nil
		if profile.slots then
			clear(profile, item)
		end
	else
		profile.inventory[item] = have - quantity
	end
	return true
end

-- The tiles, put right first: every kind held on one tile, no tile with what is not held, and
-- (for data from before tiles) the kinds in `order`.
function Inventory.Slots(profile, order)
	if profile.slots == nil then
		profile.slots = {}
	end
	local seen = {}
	for i, item in ipairs(profile.slots) do
		if item ~= "" and (seen[item] or Inventory.Count(profile, item) <= 0) then
			profile.slots[i] = ""
		elseif item ~= "" then
			seen[item] = true
		end
	end
	for _, item in ipairs(order or {}) do
		if not seen[item] and Inventory.Count(profile, item) > 0 then
			place(profile, item)
			seen[item] = true
		end
	end
	for item, quantity in pairs(profile.inventory) do
		if not seen[item] and quantity > 0 then
			place(profile, item)
		end
	end
	-- No empty tiles kept past the window's own.
	while #profile.slots > Inventory.Tiles and profile.slots[#profile.slots] == "" do
		table.remove(profile.slots)
	end
	return profile.slots
end

-- Moves `item` onto tile `slot` (from 1); what lies there takes its old tile. False when the
-- player has no such item or the tile is not in the window.
function Inventory.Move(profile, item, slot)
	local slots = Inventory.Slots(profile)
	if Inventory.Count(profile, item) <= 0 or slot < 1 or slot > math.max(Inventory.Tiles, #slots) then
		return false
	end
	local from
	for i, at in ipairs(slots) do
		if at == item then
			from = i
		end
	end
	while #slots < slot do
		table.insert(slots, "")
	end
	slots[from] = slots[slot]
	slots[slot] = item
	return true
end

return Inventory
