-- What the workbench and the machines make, drawn like the 2D game's crafting panel: tabs, a grid
-- of recipe tiles with the item's picture, and a card for the chosen recipe with its ingredients
-- as pictures and what the player has of each (red when short). It only draws; the windows ask
-- the server.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Processing = require(Shared.Processing)
local Research = require(Shared.Research)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Game = require(script.Parent.Parent.Game)

local Recipes = {}

Recipes.Colors = {
	Short = Color3.fromRGB(240, 105, 95),
	Enough = Color3.fromRGB(140, 215, 125),
	Selected = Color3.fromRGB(255, 214, 90),
}

-- Whether the player has the ingredients of `recipe`.
function Recipes.Ready(recipe)
	for _, entry in ipairs(recipe.ingredients) do
		if Game.Count(entry[1]) < entry[2] then
			return false
		end
	end
	return true
end

-- The tab a workbench recipe goes under.
function Recipes.Category(id)
	if Processing.IsMachine(id) then
		return "machines"
	elseif string.match(id, "^furniture_") or string.match(id, "^logistics_") or string.match(id, "^storage_") then
		return "buildings"
	end
	return "materials"
end

Recipes.Categories = {
	{ id = "all", name = "Wszystko" },
	{ id = "buildings", name = "Budowle" },
	{ id = "machines", name = "Maszyny" },
	{ id = "materials", name = "Materiały" },
}

-- A row of tab buttons; `tabs` is a list of { id, name }. `onPick(id)` when one is clicked.
function Recipes.Tabs(parent, tabs, current, onPick)
	local row = Kit.Row(parent, 38)
	row.BackgroundTransparency = 1
	for _, tab in ipairs(tabs) do
		Kit.Button(row, tab.name, function()
			onPick(tab.id)
		end, {
			BackgroundColor3 = tab.id == current and Kit.Colors.ButtonAlt or Kit.Colors.Row,
			Size = UDim2.fromOffset(112, 32),
		})
	end
	return row
end

-- Small tab buttons that wrap onto more rows: "Wszystko" and the item groups (Items.Categories)
-- that have something in `ids`. `onPick(id)` when one is clicked; returns the frame.
function Recipes.CategoryTabs(parent, ids, current, onPick)
	local present = {}
	for _, id in ipairs(ids) do
		present[Items.Category(id)] = true
	end
	local holder = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		Kit.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(98, 28),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local tabs = { { id = "all", name = "Wszystko" } }
	for _, c in ipairs(Items.Categories) do
		if present[c.id] then
			table.insert(tabs, c)
		end
	end
	for i, tab in ipairs(tabs) do
		Kit.Button(holder, tab.name, function()
			onPick(tab.id)
		end, {
			LayoutOrder = i,
			TextSize = 13,
			BackgroundColor3 = tab.id == current and Color3.fromRGB(110, 92, 40) or Kit.Colors.Row,
		})
	end
	return holder
end

-- A grid of recipe tiles. `opts`: selected (recipe id), marked (recipe id shown with ▶, the one a
-- machine is set to), columns, tile, onSelect(recipe). A tile's frame is gold when chosen, green
-- when the player has the ingredients; a recipe that needs research is faded with a lock.
function Recipes.Picker(parent, recipes, opts)
	local size = opts.tile or 56
	local holder = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		Kit.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(size, size),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index, recipe in ipairs(recipes) do
		local slot = ItemGrid.Slot(holder, {
			size = size,
			layoutOrder = index,
			onClick = function()
				opts.onSelect(recipe)
			end,
		})
		slot.Set(recipe.id, recipe.quantity > 1 and ("×" .. recipe.quantity) or "", recipe.locked)
		if recipe.id == opts.selected then
			slot.stroke.Color = Recipes.Colors.Selected
			slot.stroke.Thickness = 2.5
		elseif not recipe.locked and Recipes.Ready(recipe) then
			slot.stroke.Color = Recipes.Colors.Enough
			slot.stroke.Thickness = 1.5
		end
		local badge = recipe.locked and "🔒" or (recipe.id == opts.marked and "▶" or nil)
		if badge then
			Kit.Label(slot.button, badge, {
				Position = UDim2.fromOffset(3, 1),
				Size = UDim2.fromOffset(18, 18),
				TextSize = 13,
				Font = Enum.Font.GothamBold,
				TextColor3 = Recipes.Colors.Selected,
				ZIndex = 6,
			})
		end
	end
	return holder
end

-- Ingredient tiles in a row, each with "have/need" under it (red when short). `times` multiplies
-- the need.
function Recipes.Ingredients(parent, entries, size, times)
	size = size or 44
	local row = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 18),
		Parent = parent,
	}, {
		Kit.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, entry in ipairs(entries) do
		local need = entry[2] * (times or 1)
		local have = Game.Count(entry[1])
		local slot = ItemGrid.Slot(row, {
			size = size,
			layoutOrder = i,
			caption = have .. "/" .. need,
			captionColor = have >= need and Recipes.Colors.Enough or Recipes.Colors.Short,
		})
		slot.Set(entry[1], tostring(need))
		slot.button.MouseEnter:Connect(function()
			slot.caption.Text = Items.Name(entry[1])
		end)
		slot.button.MouseLeave:Connect(function()
			slot.caption.Text = have .. "/" .. need
		end)
	end
	return row
end

-- The card of the chosen recipe: its picture, name, time, ingredients and a row for the window's
-- buttons (returned). A recipe that needs research says which.
function Recipes.Card(parent, recipe, subtitle)
	local card = Kit.New("Frame", {
		Size = UDim2.new(1, -8, 0, 156),
		BackgroundColor3 = Kit.Colors.Row,
		Parent = parent,
	}, { Kit.Corner(8) })
	local big = ItemGrid.Slot(card, { size = 88 })
	big.frame.Position = UDim2.fromOffset(10, 10)
	big.Set(recipe.id, recipe.quantity > 1 and ("×" .. recipe.quantity) or "", recipe.locked)
	Kit.Label(card, Items.Name(recipe.id) .. (recipe.quantity > 1 and (" × " .. recipe.quantity) or ""), {
		Position = UDim2.fromOffset(110, 8),
		Size = UDim2.new(1, -120, 0, 22),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
	})
	Kit.Label(card, "Czas: " .. recipe.time .. " s" .. (subtitle and ("   " .. subtitle) or ""), {
		Position = UDim2.fromOffset(110, 30),
		Size = UDim2.new(1, -120, 0, 18),
		TextSize = 13,
		TextColor3 = Kit.Colors.Muted,
	})
	local ingredients = Recipes.Ingredients(card, recipe.ingredients, 40)
	ingredients.Position = UDim2.fromOffset(110, 52)
	ingredients.Size = UDim2.new(1, -120, 0, 58)
	local actions = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(110, 116),
		Size = UDim2.new(1, -120, 0, 32),
		Parent = card,
	}, {
		Kit.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	if recipe.locked then
		local t = Research.LockedBy(recipe.id)
		Kit.Label(actions, "🔒 Wymaga badań: " .. (t and t.name or "?") .. " [T]", {
			Size = UDim2.new(1, 0, 1, 0),
			TextColor3 = Recipes.Colors.Selected,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
		})
	end
	return card, actions
end

-- A big button for the card's main action, green when it can be done.
function Recipes.Action(actions, text, ready, onClick)
	return Kit.Button(actions, text, onClick, {
		Size = UDim2.fromOffset(150, 32),
		TextSize = 15,
		BackgroundColor3 = ready and Kit.Colors.Button or Color3.fromRGB(78, 84, 96),
	})
end

return Recipes
