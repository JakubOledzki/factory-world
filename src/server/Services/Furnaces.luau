-- Stone furnaces on the player's plot. A furnace is bought as an item (made at the workbench),
-- set on one of the plot's furnace slots and taken back when empty. Its state is saved with the
-- player and worked out on demand (Smelting.Advance) whenever someone looks at it.
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Smelting = require(Shared.Smelting)
local PlotLayout = require(Shared.PlotLayout)
local Build = require(script.Parent.Build)
local Clock = require(script.Parent.Clock)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Net = require(script.Parent.Net)
local Plots = require(script.Parent.Plots)

local Furnaces = {}

local models = {} -- [Player] = { [id] = Model }

local function find(profile, id)
	for _, furnace in ipairs(profile.furnaces) do
		if furnace.id == id then
			return furnace
		end
	end
	return nil
end

local function bySlot(profile, slot)
	for _, furnace in ipairs(profile.furnaces) do
		if furnace.slot == slot then
			return furnace
		end
	end
	return nil
end

-- Glows while it smelts, and goes out by itself when the ore or the coal runs out.
local function show(player, furnace)
	local model = models[player] and models[player][furnace.id]
	if model == nil then
		return
	end
	local now = Clock.Now()
	local state = Smelting.Advance(furnace.state, now)
	Build.SetFurnaceLit(model, state.startedAt ~= nil)
	if state.startedAt ~= nil then
		local recipe = Smelting.Recipes[state.input]
		local pieces = math.min(state.inputQuantity, state.heat + state.fuel * Smelting.SmeltsPerCoal)
		local token = {}
		model:SetAttribute("Token", tostring(token))
		local tokenText = tostring(token)
		task.delay(state.startedAt + pieces * recipe.time - now + 0.5, function()
			if model.Parent and model:GetAttribute("Token") == tokenText then
				show(player, furnace)
			end
		end)
	end
end

local function place(player, furnace)
	local pad = Plots.SlotPad(player, furnace.slot)
	if pad == nil then
		return
	end
	local model = Build.Furnace(Plots.Of(player).model, Plots.SlotCFrame(player, furnace.slot))
	model.Name = "Furnace" .. furnace.id
	Build.Prompt(model.Body, {
		Name = "Prompt",
		ActionText = "Otwórz",
		ObjectText = "Piec kamienny",
		HoldDuration = 0,
	}, { Kind = "furnace", FurnaceId = furnace.id, Owner = player.UserId })
	pad.Prompt.Enabled = false
	models[player][furnace.id] = model
	show(player, furnace)
end

local function reply(furnace, extra)
	local result = { ok = true, id = furnace.id, state = furnace.state, serverTime = Clock.Now() }
	for k, v in pairs(extra or {}) do
		result[k] = v
	end
	return result
end

-- The player's furnace `id` advanced to now, if it is theirs and they stand at it.
local function open(player, profile, payload)
	local id = Net.Int(payload.id, 1, 1e9)
	local furnace = id and find(profile, id)
	if furnace == nil then
		return nil, "not_owner"
	end
	local model = models[player] and models[player][furnace.id]
	if model == nil or not Net.Near(player, model.Body.Position, PlotLayout.Reach) then
		return nil, "too_far"
	end
	furnace.state = Smelting.Advance(furnace.state, Clock.Now())
	return furnace
end

local function handOut(player, profile, items)
	for _, entry in ipairs(items) do
		if entry[2] > 0 then
			Inventory.Add(profile, entry[1], entry[2])
		end
	end
end

function Furnaces.Start()
	Plots.OnPlaced(function(player, _plot)
		models[player] = {}
		local profile = Data.Get(player)
		for _, furnace in ipairs(profile.furnaces) do
			place(player, furnace)
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		models[player] = nil
	end)

	-- Setting a furnace on a free slot of the player's own plot.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt:GetAttribute("Kind") ~= "furnaceSlot" or prompt:GetAttribute("Owner") ~= player.UserId then
			return
		end
		local profile = Data.Get(player)
		local slot = prompt:GetAttribute("Slot")
		if profile == nil or Plots.Of(player) == nil or bySlot(profile, slot) ~= nil then
			return
		end
		if not Net.Near(player, prompt.Parent.Position, PlotLayout.Reach) then
			return
		end
		if not Inventory.TryRemove(profile, Items.Furnace, 1) then
			Net.Toast(player, "Nie masz pieca. Zrób go na stole warsztatowym z 20 kamieni.")
			return
		end
		local furnace = { id = Data.NextId(profile), slot = slot, state = Smelting.Empty() }
		table.insert(profile.furnaces, furnace)
		place(player, furnace)
		Net.PushState(player)
	end)

	Net.Handle("FurnaceGet", function(player, profile, payload)
		local furnace, code = open(player, profile, payload)
		if furnace == nil then
			return Net.Error(code)
		end
		return reply(furnace)
	end)

	Net.Handle("FurnaceLoad", function(player, profile, payload)
		local furnace, code = open(player, profile, payload)
		if furnace == nil then
			return Net.Error(code)
		end
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Smelting.MaxFuel + Smelting.MaxInput)
		if item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		if Inventory.Count(profile, item) < quantity then
			return Net.Error("not_enough_items")
		end
		local state, handed = Smelting.Load(furnace.state, item, quantity, Clock.Now())
		if state == nil then
			return Net.Error(handed)
		end
		Inventory.TryRemove(profile, item, quantity)
		handOut(player, profile, handed)
		furnace.state = state
		show(player, furnace)
		Net.PushState(player)
		return reply(furnace, { taken = handed })
	end)

	Net.Handle("FurnaceTake", function(player, profile, payload)
		local furnace, code = open(player, profile, payload)
		if furnace == nil then
			return Net.Error(code)
		end
		local state, taken = Smelting.Take(furnace.state, payload.what)
		if state == nil then
			return Net.Error(taken)
		end
		handOut(player, profile, taken)
		furnace.state = state
		show(player, furnace)
		Net.PushState(player)
		return reply(furnace, { taken = taken })
	end)

	Net.Handle("FurnacePickup", function(player, profile, payload)
		local furnace, code = open(player, profile, payload)
		if furnace == nil then
			return Net.Error(code)
		end
		local s = furnace.state
		if s.inputQuantity > 0 or s.fuel > 0 or s.outputQuantity > 0 then
			return Net.Error("furnace_not_empty")
		end
		for i, other in ipairs(profile.furnaces) do
			if other.id == furnace.id then
				table.remove(profile.furnaces, i)
				break
			end
		end
		Inventory.Add(profile, Items.Furnace, 1)
		models[player][furnace.id]:Destroy()
		models[player][furnace.id] = nil
		local pad = Plots.SlotPad(player, furnace.slot)
		if pad then
			pad.Prompt.Enabled = true
		end
		Net.PushState(player)
		return { ok = true }
	end)
end

return Furnaces
