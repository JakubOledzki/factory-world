-- The player's items: { [item id] = quantity }. Nothing here yields.
local Inventory = {}

function Inventory.Count(profile, item)
	return profile.inventory[item] or 0
end

function Inventory.Add(profile, item, quantity)
	assert(type(quantity) == "number" and quantity > 0 and quantity % 1 == 0, "bad quantity")
	profile.inventory[item] = Inventory.Count(profile, item) + quantity
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
	else
		profile.inventory[item] = have - quantity
	end
	return true
end

return Inventory
