-- The build grid on each player's plot: putting belts, inserters, chests, machines, furnaces and
-- saplings on it, turning and taking them back, cutting trees, and the chests' contents. What is on the grid is worked out on demand from the
-- time it was last looked at (Factory.CatchUp); while the owner is on the server it is looked at
-- every Logistics.Tick only so that clients can draw what moves. The server puts what a belt or an
-- inserter holds in attributes of its model ("Items", "Arm") and each client animates the items and
-- arms smoothly between them (client/GridView).
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Lands = require(Shared.Lands)
local Forestry = require(Shared.Forestry)
local Farming = require(Shared.Farming)
local Logistics = require(Shared.Logistics)
local Models = require(Shared.Models)
local PlotLayout = require(Shared.PlotLayout)
local Smelting = require(Shared.Smelting)
local Processing = require(Shared.Processing)
local Power = require(Shared.Power)
local Rail = require(Shared.Rail)
local Build = require(script.Parent.Build)
local Clock = require(script.Parent.Clock)
local Data = require(script.Parent.Data)
local Factory = require(script.Parent.Factory)
local Furnaces = require(script.Parent.Furnaces)
local Inventory = require(script.Parent.Inventory)
local Net = require(script.Parent.Net)
local Plots = require(script.Parent.Plots)
local TestMode = require(script.Parent.TestMode)

local Grid = {}

local views = {} -- [Player] = { [id] = Model }

local random = Random.new()

-- The model of an object as it is now: a belt by the way it turns, a tree by whether it has grown.
local function specOf(o, bend, now)
	if o.kind == Items.Belt then
		return Models.Belt(bend)
	elseif o.kind == Items.Inserter then
		return Models.Inserter()
	elseif o.kind == Items.WoodenChest then
		return Models.WoodenChest()
	elseif Processing.IsMachine(o.kind) then
		return Models.Machine(o.kind)
	elseif o.kind == Items.Generator then
		return Models.Generator()
	elseif o.kind == Items.Pole then
		return Models.Pole()
	elseif o.kind == Items.Workbench then
		return Models.Workbench()
	elseif o.kind == Rail.StationKind then
		return Models.Station()
	elseif o.kind == Farming.Field then
		return Models.Field(o.crop, Farming.Stage(o, now), o.id)
	elseif Forestry.Grown(o, now) then
		return Models.Tree(o.id, o.snow)
	end
	return Models.Sapling(o.id)
end

local function find(profile, id)
	for i, o in ipairs(profile.grid.objects) do
		if o.id == id then
			return o, i
		end
	end
	return nil
end
Grid.Find = find

-- The model of the player's object `id`, while it is shown.
function Grid.Model(player, id)
	return views[player] and views[player][id]
end

-- The middle of a tile of the player's grid in the world, for checking how near the player is.
local function tilePosition(player, x, z, size)
	local cx, cz = PlotLayout.Center(Plots.Of(player).index)
	local ox, oz = PlotLayout.TileCenter(x, z, size)
	return Vector3.new(cx + ox, 2, cz + oz)
end

-- Puts what an object holds now in its model's attributes: a belt's items, with ">" after each
-- that slid into its place in the last tick (`slid`), and an inserter's swing and load. `tick`
-- makes the items change each tick even when the pattern repeats, so clients see every step.
local function draw(model, o, slid, tick)
	if o.belt then
		local entries = {}
		for slot, item in ipairs(o.belt) do
			entries[slot] = item and (item .. ((slid and slid[slot]) and ">" or "")) or ""
		end
		local text = tick .. "|" .. table.concat(entries, ",")
		if model:GetAttribute("Items") ~= text then
			model:SetAttribute("Items", text)
		end
	elseif o.kind == Items.Inserter then
		local text = o.swing .. "," .. (o.hand or "")
		if model:GetAttribute("Arm") ~= text then
			model:SetAttribute("Arm", text)
		end
	end
end

local show

-- Builds the model of object `o` anew (when it is put down, turned, or a belt next to it changed).
local function rebuild(player, o, bend)
	local old = views[player][o.id]
	if old then
		old:Destroy()
	end
	show(player, o, bend)
end

function show(player, o, bend)
	local now = Clock.Now()
	local cframe = Plots.TileCFrame(player, o.x, o.z, Logistics.Sizes[o.kind] or 1, o.rot)
	if o.kind == Forestry.Tree then
		-- Trees face any way, but always the same one.
		cframe = cframe * CFrame.Angles(0, (o.id % 7) * 0.9, 0)
	end
	local model = Build.FromModel(Plots.Of(player).model, "Grid" .. o.id, specOf(o, bend, now), cframe)
	pcall(function()
		-- With streaming on, the whole model reaches a client at once, so its arm can be animated.
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	model:SetAttribute("GridId", o.id)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Kind", o.kind)
	model:SetAttribute("Base", cframe)
	model:SetAttribute("Bend", bend or 0)
	if o.kind == Items.WoodenChest then
		Build.Prompt(model.Body, {
			Name = "Prompt",
			ActionText = "Otwórz",
			ObjectText = Items.Name(Items.WoodenChest),
			HoldDuration = 0,
		}, { Kind = "chest", ChestId = o.id, Owner = player.UserId })
	elseif Processing.IsMachine(o.kind) then
		Build.Prompt(model.Body, {
			Name = "Prompt",
			ActionText = "Obsługuj",
			ObjectText = Items.Name(o.kind),
			HoldDuration = 0,
			MaxActivationDistance = 12,
		}, { Kind = "machine", MachineId = o.id, Owner = player.UserId })
	elseif o.kind == Items.Generator then
		Build.Prompt(model.Body, {
			Name = "Prompt",
			ActionText = "Obsługuj",
			ObjectText = Items.Name(o.kind),
			HoldDuration = 0,
			MaxActivationDistance = 12,
		}, { Kind = "generator", GeneratorId = o.id, Owner = player.UserId })
	elseif o.kind == Rail.StationKind then
		Build.Prompt(model.Body, {
			Name = "Prompt",
			ActionText = "Otwórz",
			ObjectText = Rail.StationName,
			HoldDuration = 0,
			MaxActivationDistance = 14,
		}, { Kind = "station", Owner = player.UserId })
		Build.Label(model.Body, Rail.StationName, 7, Color3.fromRGB(255, 240, 200))
	elseif o.kind == Items.Workbench then
		-- The same workbench as on the square (Services/Workshop).
		Build.Prompt(model.Top, {
			Name = "Prompt",
			ActionText = "Wytwarzaj",
			ObjectText = Items.Name(o.kind),
			HoldDuration = 0,
		}, { Kind = "workbench", Owner = player.UserId })
	elseif o.kind == Forestry.Tree then
		if Forestry.Grown(o, now) then
			Build.Prompt(model.Trunk, {
				Name = "Prompt",
				ActionText = "Zetnij",
				ObjectText = "Sosna",
				HoldDuration = TestMode.Hold(Forestry.ChopTime),
			}, { Kind = "tree", TreeId = o.id, Owner = player.UserId })
		else
			-- A sapling turns into a tree when it has grown.
			task.delay(o.plantedAt + Forestry.Grow - now + 0.2, function()
				if model.Parent and views[player] and views[player][o.id] == model then
					rebuild(player, o)
				end
			end)
		end
	elseif o.kind == Farming.Field then
		local stage = Farming.Stage(o, now)
		if stage == 0 then
			Build.Prompt(model.Body, {
				Name = "Prompt",
				ActionText = "Zasiej",
				ObjectText = "Pole",
				HoldDuration = 0,
			}, { Kind = "field", FieldId = o.id, Owner = player.UserId })
		elseif stage == 3 then
			Build.Prompt(model.Body, {
				Name = "Prompt",
				ActionText = "Zbierz",
				ObjectText = Items.Name(o.crop),
				HoldDuration = TestMode.Hold(1),
			}, { Kind = "reap", FieldId = o.id, Owner = player.UserId })
		else
			Build.Label(model.Body, Items.Name(o.crop), 3, Color3.fromRGB(230, 255, 200))
		end
		-- The crop shows its next stage when it reaches it.
		local at = Farming.NextStage(o, now)
		if at then
			task.delay(at - now + 0.2, function()
				if model.Parent and views[player] and views[player][o.id] == model then
					rebuild(player, o)
				end
			end)
		end
	end
	views[player][o.id] = model
	draw(model, o, nil, 0)
end

-- Hangs the wires between the player's poles anew (Power.Wires).
local function rewire(player, profile)
	local plot = Plots.Of(player)
	if plot == nil then
		return
	end
	local old = plot.model:FindFirstChild("Wires")
	if old then
		old:Destroy()
	end
	local spec = {}
	for _, pair in ipairs(Power.Wires(profile.grid.objects)) do
		local a = Plots.TileCFrame(player, pair[1].x, pair[1].z, 1, 0).Position
		local b = Plots.TileCFrame(player, pair[2].x, pair[2].z, 1, 0).Position
		local top = Models.PoleTop
		for _, part in ipairs(Models.Wire({ a.X, a.Y + top, a.Z }, { b.X, b.Y + top, b.Z })) do
			table.insert(spec, part)
		end
	end
	if #spec > 0 then
		Build.FromModel(plot.model, "Wires", spec, CFrame.new())
	end
end

-- Rebuilds the belts whose turn changed after something was put down, turned or taken away.
local function restyle(player, profile)
	local bends = Logistics.Bends(profile.grid.objects)
	for _, o in ipairs(profile.grid.objects) do
		local model = views[player][o.id]
		if o.kind == Items.Belt and model and model:GetAttribute("Bend") ~= bends[o.id] then
			rebuild(player, o, bends[o.id])
		end
	end
end

local function refresh(player, profile)
	local mine = views[player]
	if mine == nil or #profile.grid.objects == 0 then
		return
	end
	local watch = { slid = {} }
	Factory.CatchUp(profile, watch)
	local tick = math.floor(profile.grid.at / Logistics.Tick + 0.5) % 1000
	local now = Clock.Now()
	local nets = nil
	for _, o in ipairs(profile.grid.objects) do
		local model = mine[o.id]
		if model then
			draw(model, o, watch.slid[o.id], tick)
			-- A machine at work glows and turns its saw or rollers (client/GridView); so does a
			-- generator that gives power.
			local working = nil
			if o.machine then
				working = Processing.Working(o.kind, o.machine, now)
			elseif o.generator then
				nets = nets or Factory.Networks(profile)
				local net = Power.NetworkOf(nets, o)
				working = Power.Running(o.generator) and net ~= nil and net.demand > 0
			end
			if working ~= nil then
				if model:GetAttribute("Working") ~= working then
					model:SetAttribute("Working", working)
					Build.SetFurnaceLit(model, working)
				end
			end
		end
	end
	-- Furnaces that inserters feed light up and go out with what they bring.
	for _, furnace in ipairs(profile.furnaces) do
		local model = furnace.tile and Furnaces.Model(player, furnace.id)
		if model then
			local lit = Smelting.Advance(furnace.state, now).startedAt ~= nil
			if model:GetAttribute("Lit") ~= lit then
				model:SetAttribute("Lit", lit)
				Build.SetFurnaceLit(model, lit)
			end
		end
	end
end

-- The player's chest `id` worked out until now, if they stand at it.
local function openChest(player, profile, payload)
	local id = Net.Int(payload.id, 1, 1e9)
	local o = id and find(profile, id)
	if o == nil or o.kind ~= Items.WoodenChest then
		return nil, "not_owner"
	end
	local model = views[player] and views[player][o.id]
	if model == nil or not Net.Near(player, model.Body.Position, PlotLayout.Reach) then
		return nil, "too_far"
	end
	Factory.CatchUp(profile)
	return o
end

local function chestReply(o)
	return { ok = true, id = o.id, items = o.items, slots = Logistics.ChestSlots, slotSize = Logistics.SlotSize }
end

function Grid.Start()
	Plots.OnPlaced(function(player)
		views[player] = {}
		local profile = Data.Get(player)
		Factory.CatchUp(profile)
		local bends = Logistics.Bends(profile.grid.objects)
		for _, o in ipairs(profile.grid.objects) do
			show(player, o, bends[o.id])
		end
		rewire(player, profile)
	end)

	Players.PlayerRemoving:Connect(function(player)
		views[player] = nil
	end)

	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since = since + dt
		if since < Logistics.Tick then
			return
		end
		since = 0
		for player in pairs(views) do
			local profile = Data.Get(player)
			if profile then
				refresh(player, profile)
			end
		end
	end)

	Net.Handle("GridPlace", function(player, profile, payload)
		local item = Net.Item(payload.item)
		local x = Net.Int(payload.x, 0, PlotLayout.Grid.width - 1)
		local z = Net.Int(payload.z, 0, PlotLayout.Grid.depth - 1)
		local rot = Net.Int(payload.rot, 0, 3)
		if item == nil or x == nil or z == nil or rot == nil then
			return Net.Error("bad_payload")
		end
		local size = Logistics.Sizes[item]
		if size == nil then
			return Net.Error("not_buildable")
		end
		if Plots.Of(player) == nil or views[player] == nil then
			return Net.Error("not_loaded")
		end
		if not Net.Near(player, tilePosition(player, x, z, size), PlotLayout.BuildReach) then
			return Net.Error("too_far")
		end
		Factory.CatchUp(profile)
		local ok, code = Logistics.CanPlace(profile.grid.objects, profile.furnaces, item, x, z)
		if not ok then
			return Net.Error(code)
		end
		if item == Items.Hoe then
			-- The hoe tills a field and is kept.
			if not Lands.Fertile(profile) then
				return Net.Error("not_fertile")
			end
			if Inventory.Count(profile, Items.Hoe) < 1 then
				return Net.Error("not_enough_items")
			end
		elseif not Inventory.TryRemove(profile, item, 1) then
			return Net.Error("not_enough_items")
		end
		local id = Data.NextId(profile)
		if item == Items.Furnace then
			Furnaces.Add(player, profile, { id = id, tile = { x = x, z = z }, rot = rot, state = Smelting.Empty() })
		else
			local o
			if item == Items.Hoe then
				o = Farming.New(id, x, z)
			elseif item == Items.Sapling then
				o = Forestry.New(id, x, z, Clock.Now())
				-- A tree of the tundra grows up snowy.
				o.snow = profile.active and Lands.Biomes[profile.active].snow or nil
			else
				o = Logistics.New(id, item, x, z, rot)
			end
			table.insert(profile.grid.objects, o)
			show(player, o, Logistics.Bends(profile.grid.objects)[id])
			restyle(player, profile)
			Factory.Changed(profile)
			if item == Items.Pole then
				rewire(player, profile)
			end
		end
		Net.PushState(player)
		return { ok = true, id = id }
	end)

	Net.Handle("GridPickup", function(player, profile, payload)
		local id = Net.Int(payload.id, 1, 1e9)
		if id == nil then
			return Net.Error("bad_payload")
		end
		if Plots.Of(player) == nil or views[player] == nil then
			return Net.Error("not_loaded")
		end
		Factory.CatchUp(profile)
		local o, index = find(profile, id)
		if o then
			if o.kind == Forestry.Tree then
				return Net.Error("cut_tree")
			end
			if o.kind == Rail.StationKind then
				return Net.Error("fixture")
			end
			if not Net.Near(player, tilePosition(player, o.x, o.z, Logistics.Sizes[o.kind] or 1), PlotLayout.BuildReach) then
				return Net.Error("too_far")
			end
			table.remove(profile.grid.objects, index)
			if o.kind == Farming.Field then
				-- The ground goes back to grass; a ripe crop is reaped on the way.
				local item, count = Farming.Reap(o, Clock.Now())
				if item then
					Inventory.Add(profile, item, count)
				end
			else
				Inventory.Add(profile, o.kind, 1)
			end
			for _, entry in ipairs(Logistics.Contents(o)) do
				Inventory.Add(profile, entry[1], entry[2])
			end
			local model = views[player][o.id]
			if model then
				model:Destroy()
				views[player][o.id] = nil
			end
			restyle(player, profile)
			Factory.Changed(profile)
			if o.kind == Items.Pole then
				rewire(player, profile)
			end
			Net.PushState(player)
			return { ok = true }
		end
		for _, furnace in ipairs(profile.furnaces) do
			if furnace.id == id and furnace.tile then
				if not Net.Near(player, tilePosition(player, furnace.tile.x, furnace.tile.z, 2), PlotLayout.BuildReach) then
					return Net.Error("too_far")
				end
				local removed, code = Furnaces.Remove(player, profile, furnace)
				if not removed then
					return Net.Error(code)
				end
				Net.PushState(player)
				return { ok = true }
			end
		end
		return Net.Error("not_owner")
	end)

	-- Turning a belt or an inserter where it stands, keeping what it holds.
	Net.Handle("GridRotate", function(player, profile, payload)
		local id = Net.Int(payload.id, 1, 1e9)
		local rot = Net.Int(payload.rot, 0, 3)
		if id == nil or rot == nil then
			return Net.Error("bad_payload")
		end
		if Plots.Of(player) == nil or views[player] == nil then
			return Net.Error("not_loaded")
		end
		Factory.CatchUp(profile)
		local o = find(profile, id)
		if o == nil or (o.kind ~= Items.Belt and o.kind ~= Items.Inserter) then
			return Net.Error("not_owner")
		end
		if not Net.Near(player, tilePosition(player, o.x, o.z, 1), PlotLayout.BuildReach) then
			return Net.Error("too_far")
		end
		o.rot = rot
		rebuild(player, o, Logistics.Bends(profile.grid.objects)[o.id])
		restyle(player, profile)
		return { ok = true }
	end)

	-- Cutting a tree: the server checks the axe, the hold and the distance, and rolls the sapling.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt:GetAttribute("Kind") ~= "tree" or prompt:GetAttribute("Owner") ~= player.UserId then
			return
		end
		local profile = Data.Get(player)
		if profile == nil or views[player] == nil or not Plots.HeldLongEnough(player, prompt) then
			return
		end
		if not Net.Near(player, prompt.Parent.Position, PlotLayout.Reach) then
			return
		end
		local o, index = find(profile, prompt:GetAttribute("TreeId"))
		if o == nil or o.kind ~= Forestry.Tree or not Forestry.Grown(o, Clock.Now()) then
			return
		end
		if Inventory.Count(profile, Items.Axe) < 1 then
			Net.Toast(player, "Potrzebujesz siekiery. Kupisz ją u handlarza.")
			return
		end
		table.remove(profile.grid.objects, index)
		local model = views[player][o.id]
		if model then
			model:Destroy()
			views[player][o.id] = nil
		end
		Plots.Gather(player, profile, Forestry.Cut(random:NextInteger(0, 99)))
	end)

	-- Reaping a ripe field by hand; the field stays tilled for the next crop.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt:GetAttribute("Kind") ~= "reap" or prompt:GetAttribute("Owner") ~= player.UserId then
			return
		end
		local profile = Data.Get(player)
		if profile == nil or views[player] == nil or not Plots.HeldLongEnough(player, prompt) then
			return
		end
		if not Net.Near(player, prompt.Parent.Position, PlotLayout.Reach) then
			return
		end
		local o = find(profile, prompt:GetAttribute("FieldId"))
		if o == nil or o.kind ~= Farming.Field then
			return
		end
		local item, count = Farming.Reap(o, Clock.Now())
		if item == nil then
			return
		end
		rebuild(player, o)
		Plots.Gather(player, profile, { { item, count } })
	end)

	-- Sowing a crop on an empty field; seeds cost nothing, as on main.
	Net.Handle("FieldSow", function(player, profile, payload)
		local id = Net.Int(payload.id, 1, 1e9)
		local crop = Net.Item(payload.crop)
		if id == nil or crop == nil then
			return Net.Error("bad_payload")
		end
		if views[player] == nil then
			return Net.Error("not_loaded")
		end
		local o = find(profile, id)
		if o == nil or o.kind ~= Farming.Field then
			return Net.Error("not_owner")
		end
		local model = views[player][o.id]
		if model == nil or not Net.Near(player, model.Body.Position, PlotLayout.Reach) then
			return Net.Error("too_far")
		end
		local ok, code = Farming.Sow(o, crop, Clock.Now())
		if not ok then
			return Net.Error(code)
		end
		rebuild(player, o)
		return { ok = true }
	end)

	Net.Handle("ChestGet", function(player, profile, payload)
		local o, code = openChest(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		return chestReply(o)
	end)

	Net.Handle("ChestPut", function(player, profile, payload)
		local o, code = openChest(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Logistics.ChestSlots * Logistics.SlotSize)
		if item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		if Inventory.Count(profile, item) < quantity then
			return Net.Error("not_enough_items")
		end
		local moved = math.min(quantity, Logistics.Room(o.items, item))
		if moved <= 0 then
			return Net.Error("chest_full")
		end
		Inventory.TryRemove(profile, item, moved)
		Logistics.Store(o.items, item, moved)
		Net.PushState(player)
		return chestReply(o)
	end)

	Net.Handle("ChestTake", function(player, profile, payload)
		local o, code = openChest(player, profile, payload)
		if o == nil then
			return Net.Error(code)
		end
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Logistics.ChestSlots * Logistics.SlotSize)
		if item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		local taken = Logistics.Unstore(o.items, item, quantity)
		if taken <= 0 then
			return Net.Error("chest_empty")
		end
		Inventory.Add(profile, item, taken)
		Net.PushState(player)
		return chestReply(o)
	end)
end

return Grid
