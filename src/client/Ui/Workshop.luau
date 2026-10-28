-- The workbench's window, like the 2D game's crafting panel: tabs, a grid of what can be made, a
-- card for the chosen recipe with its ingredients and a "Wytwórz" button, and the queue of orders
-- as tiles counting down.
local RunService = game:GetService("RunService")

local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local Workshop = {}

local function clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 60 then
		return math.floor(seconds / 60) .. ":" .. string.format("%02d", seconds % 60)
	end
	return seconds .. " s"
end

function Workshop.Open(screen)
	local reply = Game.Call("WorkshopGet")
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connections = {}
	local window, body = Kit.Window(screen, "Stół warsztatowy", 560, 600, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)
	local tab = "all"
	local selected = reply.recipes[1] and reply.recipes[1].id
	local queueSlots = {}
	local asked = false

	local function apply(r)
		if r then
			reply = r
			Game.SyncTime(r.serverTime)
		end
	end

	local function render()
		Kit.Clear(body)
		queueSlots = {}
		local tabs = {}
		for _, category in ipairs(Recipes.Categories) do
			for _, recipe in ipairs(reply.recipes) do
				if category.id == "all" or Recipes.Category(recipe.id) == category.id then
					table.insert(tabs, category)
					break
				end
			end
		end
		Recipes.Tabs(body, tabs, tab, function(id)
			tab = id
			render()
		end)

		local shown = {}
		local chosen
		for _, recipe in ipairs(reply.recipes) do
			if tab == "all" or Recipes.Category(recipe.id) == tab then
				table.insert(shown, recipe)
			end
			if recipe.id == selected then
				chosen = recipe
			end
		end
		Recipes.Picker(body, shown, {
			selected = selected,
			columns = 8,
			tile = 56,
			onSelect = function(recipe)
				selected = recipe.id
				render()
			end,
		})

		if chosen then
			local _, actions = Recipes.Card(body, chosen)
			if not chosen.locked then
				local ready = Recipes.Ready(chosen)
				Recipes.Action(actions, "Wytwórz", ready, function()
					apply(Game.Call("WorkshopOrder", { recipe = chosen.id }))
					render()
				end)
				Kit.Label(actions, ready and "Składniki zostaną zabrane od razu." or "Brakuje składników (na czerwono).", {
					Size = UDim2.new(1, -160, 1, 0),
					TextSize = 13,
					TextColor3 = Kit.Colors.Muted,
				})
			end
		end

		Kit.Label(body, "Kolejka (" .. #reply.queue .. "/" .. reply.maxQueue .. ")  ·  gotowe trafia do ekwipunku, także gdy odejdziesz", {
			TextColor3 = Kit.Colors.Muted,
			TextSize = 14,
		})
		local row = Kit.Row(body, 84)
		row.BackgroundTransparency = 1
		for i = 1, reply.maxQueue do
			local order = reply.queue[i]
			local slot = ItemGrid.Slot(row, { size = 56, caption = order and "" or "wolne", layoutOrder = i })
			if order then
				slot.Set(order.item, order.quantity > 1 and ("×" .. order.quantity) or "")
				local bar = Kit.New("Frame", {
					BackgroundColor3 = Color3.fromRGB(255, 140, 50),
					BorderSizePixel = 0,
					Position = UDim2.new(0, 3, 1, -5),
					Size = UDim2.new(0, 0, 0, 3),
					ZIndex = 6,
					Parent = slot.button,
				})
				table.insert(queueSlots, { slot = slot, order = order, bar = bar })
			end
		end
	end

	table.insert(connections, Game.Changed.Event:Connect(render))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local now = Game.Now()
		local due = false
		for i, entry in ipairs(queueSlots) do
			local left = entry.order.finishesAt - now
			entry.slot.caption.Text = left > 0 and clock(left) or "gotowe"
			entry.slot.caption.TextColor3 = i == 1 and Kit.Colors.Text or Kit.Colors.Muted
			local recipe
			for _, r in ipairs(reply.recipes) do
				if r.id == entry.order.item then
					recipe = r
				end
			end
			if i == 1 and recipe then
				local progress = math.clamp(1 - left / recipe.time, 0, 1)
				entry.bar.Size = UDim2.new(progress, -6, 0, 3)
			end
			if left <= 0 then
				due = true
			end
		end
		-- Ask the server to hand out what is done, once per finished order.
		if due and not asked then
			asked = true
			task.spawn(function()
				apply(Game.Call("WorkshopGet"))
				render()
				asked = false
			end)
		end
	end))
	render()
	return window
end

return Workshop
