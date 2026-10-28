-- A processing machine's window: a grid of what it can make and a card for the chosen recipe, what
-- is in it as tiles (ingredients, fuel, the batch's progress and what is ready), and the inventory
-- to load it from. The progress is worked out here from the state the server sent (the same
-- Processing.Advance). A machine that runs on power says how its network is doing.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Processing = require(Shared.Processing)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Recipes = require(script.Parent.Recipes)
local InventoryWindow = require(script.Parent.Inventory)
local Game = require(script.Parent.Parent.Game)

local Machine = {}

-- A row of tiles for what is in a machine or furnace, with an arrow and a progress bar before what
-- is ready. Returns the row, a function adding a tile ({ caption, onClick }) and the bar.
function Machine.Contents(parent)
	local row = Kit.Row(parent, 84)
	row.BackgroundTransparency = 1
	local order = 0
	local function slot(caption, onClick)
		order = order + 1
		return ItemGrid.Slot(row, { size = 56, caption = caption, layoutOrder = order, onClick = onClick })
	end
	local function arrow()
		order = order + 1
		local holder = Kit.New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(90, 56),
			LayoutOrder = order,
			Parent = row,
		})
		Kit.Label(holder, "➜", {
			Size = UDim2.new(1, 0, 0, 34),
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Kit.Colors.Muted,
		})
		local track = Kit.New("Frame", {
			Position = UDim2.fromOffset(4, 38),
			Size = UDim2.new(1, -8, 0, 10),
			BackgroundColor3 = Color3.fromRGB(24, 27, 33),
			Parent = holder,
		}, { Kit.Corner(5) })
		return Kit.New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 140, 50), Parent = track }, { Kit.Corner(5) })
	end
	return row, slot, arrow
end

-- A line on how a machine's power is: full, too little (slower) or none.
function Machine.PowerLine(parent, power)
	local net = power.network
	local text, color
	if net == nil then
		text = "⚡ Brak prądu: postaw obok słup energetyczny połączony z generatorem."
		color = Recipes.Colors.Short
	elseif net.supply <= 0 then
		text = "⚡ Brak prądu: generator w tej sieci nie ma paliwa."
		color = Recipes.Colors.Short
	elseif net.speed < 1 then
		text = "⚡ Za mało prądu (" .. net.supply .. " z " .. net.demand .. " kW): pracuje na " .. math.floor(net.speed * 100) .. "%."
		color = Color3.fromRGB(240, 190, 80)
	else
		text = "⚡ Zasilana: pobiera " .. power.kw .. " kW (sieć " .. net.demand .. " / " .. net.supply .. " kW)."
		color = Recipes.Colors.Enough
	end
	return Kit.Label(parent, text, { TextColor3 = color, TextSize = 14, Font = Enum.Font.GothamBold })
end

function Machine.Open(screen, id)
	local reply = Game.Call("MachineGet", { id = id })
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connections = {}
	local window, body = Kit.Window(screen, Items.Name(reply.kind), 560, 680, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)
	local kind = reply.kind
	local viewing = reply.state.recipe or (reply.recipes[1] and reply.recipes[1].id)
	local live -- { inputs = { slot }, fuel = slot, output = slot, bar, recipe }

	local function apply(r)
		if r then
			Game.SyncTime(r.serverTime)
			reply = r
		end
	end

	local function find(recipeId)
		for _, r in ipairs(reply.recipes) do
			if r.id == recipeId then
				return r
			end
		end
		return nil
	end

	local function render()
		Kit.Clear(body)
		live = nil
		Kit.Label(body, "Co robić:", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
		Recipes.Picker(body, reply.recipes, {
			selected = viewing,
			marked = reply.state.recipe,
			tile = 56,
			onSelect = function(r)
				viewing = r.id
				render()
			end,
		})
		local shown = find(viewing)
		if shown then
			local _, actions = Recipes.Card(body, shown, "za wsad")
			if not shown.locked then
				if shown.id == reply.state.recipe then
					Kit.Label(actions, "▶ Maszyna robi ten przepis", {
						Size = UDim2.new(1, 0, 1, 0),
						Font = Enum.Font.GothamBold,
						TextSize = 14,
						TextColor3 = Recipes.Colors.Selected,
					})
				else
					Recipes.Action(actions, "Ustaw przepis", true, function()
						apply(Game.Call("MachineRecipe", { id = id, recipe = shown.id }))
						render()
					end)
					Kit.Label(actions, "To, co jest w maszynie, wróci do ekwipunku.", {
						Size = UDim2.new(1, -160, 1, 0),
						TextSize = 13,
						TextColor3 = Kit.Colors.Muted,
					})
				end
			end
		end

		if reply.power then
			Machine.PowerLine(body, reply.power)
		end

		local recipe = find(reply.state.recipe)
		if recipe == nil then
			Kit.Label(body, "Wybierz przepis i kliknij „Ustaw przepis”, potem włóż składniki.", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
			return
		end
		Kit.Label(body, "W maszynie (kliknij kafelek, aby wyjąć):", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
		local _, slot, arrow = Machine.Contents(body)
		live = { inputs = {}, recipe = recipe }
		for i, entry in ipairs(recipe.ingredients) do
			live.inputs[i] = slot(Items.Name(entry[1]), function()
				apply(Game.Call("MachineTake", { id = id, what = "input" }))
			end)
		end
		if reply.fired then
			live.fuel = slot("Paliwo", function()
				apply(Game.Call("MachineTake", { id = id, what = "fuel" }))
			end)
		end
		live.bar = arrow()
		live.output = slot("Gotowe", function()
			apply(Game.Call("MachineTake", { id = id, what = "output" }))
		end)
		live.output.caption.Font = Enum.Font.GothamBold

		-- The inventory: a click puts what the machine takes in (Shift: half), as in the 2D game.
		Kit.Label(body, "Ekwipunek: kliknij składnik albo paliwo, aby włożyć (Shift: połowę)", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
		local grid = ItemGrid.New(body, {
			columns = 8,
			tile = 54,
			hint = function(entry)
				local s = Processing.Advance(kind, reply.state, Game.Now())
				return Processing.Room(kind, s, entry.item) > 0 and "kliknij, aby włożyć" or nil
			end,
			onClick = function(_index, entry, half)
				local s = Processing.Advance(kind, reply.state, Game.Now())
				local wanted = half and math.max(1, math.ceil(entry.quantity / 2)) or entry.quantity
				local quantity = math.min(wanted, Processing.Room(kind, s, entry.item))
				if quantity <= 0 then
					local takes = reply.fired and Processing.Fuels[entry.item] ~= nil
					for _, ingredient in ipairs(recipe.ingredients) do
						takes = takes or ingredient[1] == entry.item
					end
					Game.Toast:Fire(Game.ErrorText(takes and "machine_full" or "machine_wrong_item"))
					return
				end
				apply(Game.Call("MachineLoad", { id = id, item = entry.item, quantity = quantity }))
			end,
			onMove = function(_from, to, entry)
				Game.Call("InventoryMove", { item = entry.item, slot = to })
			end,
		})
		grid.Set(ItemGrid.Inventory(Game, InventoryWindow.Tiles, 8))
	end

	table.insert(connections, Game.Changed.Event:Connect(render))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if live == nil or live.bar.Parent == nil then
			return
		end
		local recipe = live.recipe
		local now = Game.Now()
		local s = Processing.Advance(kind, reply.state, now)
		for i, entry in ipairs(recipe.ingredients) do
			local n = s.inputs[i] or 0
			live.inputs[i].Set(entry[1], n .. "/" .. Processing.MaxInput, n == 0)
		end
		if live.fuel then
			live.fuel.Set(s.fuelItem or Items.Coal, s.fuel .. "/" .. Processing.MaxFuel, s.fuel == 0)
			live.fuel.caption.Text = s.heat > 0 and ("Paliwo (żar " .. s.heat .. ")") or "Paliwo"
		end
		live.output.Set(recipe.id, s.output .. "/" .. Processing.MaxOutput, s.output == 0)
		live.bar.Size = UDim2.fromScale(Processing.Progress(kind, s, now), 1)
	end))
	render()
	return window
end

return Machine
