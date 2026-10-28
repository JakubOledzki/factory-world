-- Fields on the build grid (Farming.cs on main): the hoe tills two by two tiles of fertile ground
-- into a field, a crop is sown on it for free and grows for its own time, then it is reaped by hand
-- and the field can be sown again. Nothing runs in a loop: a crop is ripe once its time from
-- `sownAt` has passed.
--
-- A field on the grid is { id, kind = Farming.Field, x, z, rot = 0, crop, sownAt } (crop nil: tilled,
-- nothing growing).
local Items = require(script.Parent.Items)

local Farming = {}

Farming.Field = "field"
-- Tiles across a field (the hoe's ghost is as big).
Farming.Size = 2

-- Every crop, in the order the window lists them: seconds to grow and pieces a ripe field gives
-- (twice a field on main, which is one tile of the 2D game).
Farming.Crops = {
	{ item = Items.Wheat, grow = 5 * 60, yield = 8 },
	{ item = Items.Carrot, grow = 7 * 60, yield = 8 },
	{ item = Items.Cabbage, grow = 8 * 60, yield = 4 },
	{ item = Items.Corn, grow = 10 * 60, yield = 6 },
	{ item = Items.Potato, grow = 15 * 60, yield = 10 },
	{ item = Items.Sunflower, grow = 20 * 60, yield = 6 },
}

Farming.ById = {}
for _, c in ipairs(Farming.Crops) do
	Farming.ById[c.item] = c
end

function Farming.New(id, x, z)
	return { id = id, kind = Farming.Field, x = x, z = z, rot = 0 }
end

-- Sows `crop` on an empty field at `now`; true, or false and an error code.
function Farming.Sow(field, crop, now)
	if Farming.ById[crop] == nil then
		return false, "bad_payload"
	end
	if field.crop ~= nil then
		return false, "field_sown"
	end
	field.crop = crop
	field.sownAt = now
	return true
end

-- How far the crop has grown, 0 to 1 (nil when nothing grows).
function Farming.Growth(field, now)
	local info = field.crop and Farming.ById[field.crop]
	if info == nil then
		return nil
	end
	return math.max(0, math.min(1, (now - field.sownAt) / info.grow))
end

function Farming.Ripe(field, now)
	local g = Farming.Growth(field, now)
	return g ~= nil and g >= 1
end

-- When the crop is ripe (nil when nothing grows).
function Farming.ReadyAt(field)
	local info = field.crop and Farming.ById[field.crop]
	return info and field.sownAt + info.grow
end

-- Reaps a ripe crop: the item and how many; or nil and an error code. The field stays tilled.
function Farming.Reap(field, now)
	if field.crop == nil then
		return nil, "nothing_here"
	end
	if not Farming.Ripe(field, now) then
		return nil, "not_ripe"
	end
	local info = Farming.ById[field.crop]
	field.crop = nil
	field.sownAt = nil
	return info.item, info.yield
end

-- The stage the model shows: 0 tilled, 1 sprouts, 2 growing, 3 ripe.
function Farming.Stage(field, now)
	local g = Farming.Growth(field, now)
	if g == nil then
		return 0
	elseif g >= 1 then
		return 3
	elseif g >= 0.5 then
		return 2
	end
	return 1
end

-- When the stage shown changes next (nil when it will not).
function Farming.NextStage(field, now)
	local info = field.crop and Farming.ById[field.crop]
	if info == nil then
		return nil
	end
	local half = field.sownAt + info.grow / 2
	if now < half then
		return half
	end
	local ripe = field.sownAt + info.grow
	if now < ripe then
		return ripe
	end
	return nil
end

return Farming
