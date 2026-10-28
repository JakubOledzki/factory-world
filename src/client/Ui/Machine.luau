-- A processing machine's window: what it makes, what is in it, how far the batch has got, and
-- buttons to choose the recipe, load it and empty it. The progress is worked out here from the
-- state the server sent (the same Processing.Advance).
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Processing = require(Shared.Processing)
local Kit = require(script.Parent.Kit)
local Game = require(script.Parent.Parent.Game)

local Machine = {}

local function list(entries)
	local parts = {}
	for _, entry in ipairs(entries) do
		table.insert(parts, entry[2] .. " × " .. Items.Name(entry[1]))
	end
	return table.concat(parts, ", ")
end

function Machine.Open(screen, id)
	local reply = Game.Call("MachineGet", { id = id })
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connections = {}
	local window, body = Kit.Window(screen, Items.Name(reply.kind), 560, 560, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)
	local labels = {}
	local bar

	local function apply(r)
		if r then
			Game.SyncTime(r.serverTime)
			reply = r
		end
	end

	local function current()
		for _, r in ipairs(reply.recipes) do
			if r.id == reply.state.recipe then
				return r
			end
		end
		return nil
	end

	local function render()
		Kit.Clear(body)
		labels = {}
		local kind = reply.kind
		Kit.Label(body, "Co robić:", { TextColor3 = Kit.Colors.Muted })
		for _, r in ipairs(reply.recipes) do
			local row = Kit.Row(body, 48)
			Kit.Swatch(row, Items.Colors[r.id], 26)
			local text = Kit.Label(row, "", { Size = UDim2.new(0, 330, 1, 0), TextWrapped = true, RichText = true, TextSize = 15 })
			text.Text = "<b>" .. Items.Name(r.id) .. " × " .. r.quantity .. "</b>  (" .. r.time .. " s)\n"
				.. '<font color="#a0a6b2">z: ' .. list(r.ingredients) .. "</font>"
			if r.locked then
				Kit.Label(row, "Wymaga badań", { Size = UDim2.new(0, 110, 1, 0), TextColor3 = Kit.Colors.Muted, TextSize = 14 })
			elseif r.id == reply.state.recipe then
				Kit.Label(row, "Wybrane", { Size = UDim2.new(0, 90, 1, 0), Font = Enum.Font.GothamBold, TextColor3 = Kit.Colors.Money })
			else
				Kit.Button(row, "Wybierz", function()
					apply(Game.Call("MachineRecipe", { id = id, recipe = r.id }))
					render()
				end, { Size = UDim2.fromOffset(90, 30) })
			end
		end

		local recipe = current()
		if recipe == nil then
			Kit.Label(body, "Wybierz przepis, potem włóż składniki.", { TextColor3 = Kit.Colors.Muted })
			return
		end
		for i, entry in ipairs(recipe.ingredients) do
			labels[i] = Kit.Label(body, "")
		end
		if reply.fired then
			labels.fuel = Kit.Label(body, "")
		end
		labels.output = Kit.Label(body, "", { Font = Enum.Font.GothamBold })
		local track = Kit.New("Frame", { Size = UDim2.new(1, -8, 0, 12), BackgroundColor3 = Kit.Colors.Row, Parent = body }, { Kit.Corner(6) })
		bar = Kit.New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 140, 50), Parent = track }, { Kit.Corner(6) })

		-- What can go in: the recipe's ingredients and, in a fired machine, fuel.
		local loadable, seen = {}, {}
		for _, entry in ipairs(recipe.ingredients) do
			table.insert(loadable, entry[1])
			seen[entry[1]] = true
		end
		if reply.fired then
			for fuel in pairs(Processing.Fuels) do
				if not seen[fuel] then
					table.insert(loadable, fuel)
				end
			end
		end
		Kit.Label(body, "Włóż z ekwipunku:", { TextColor3 = Kit.Colors.Muted })
		for _, item in ipairs(loadable) do
			local have = Game.Count(item)
			if have > 0 then
				local row = Kit.Row(body)
				Kit.Swatch(row, Items.Colors[item])
				local fuel = Processing.Fuels[item] and reply.fired
				Kit.Label(row, Items.Name(item) .. " (" .. have .. ")" .. (fuel and not seen[item] and "  paliwo" or ""), { Size = UDim2.new(0, 260, 1, 0) })
				Kit.Button(row, "Włóż wszystko", function()
					local s = Processing.Advance(kind, reply.state, Game.Now())
					local quantity = math.min(Game.Count(item), Processing.Room(kind, s, item))
					if quantity <= 0 then
						Game.Toast:Fire(Game.ErrorText("machine_full"))
						return
					end
					apply(Game.Call("MachineLoad", { id = id, item = item, quantity = quantity }))
				end, { Size = UDim2.fromOffset(120, 28) })
			end
		end

		local actions = Kit.Row(body, 40)
		actions.BackgroundTransparency = 1
		Kit.Button(actions, "Weź gotowe", function()
			apply(Game.Call("MachineTake", { id = id, what = "output" }))
		end, { Size = UDim2.fromOffset(120, 30) })
		Kit.Button(actions, "Weź składniki", function()
			apply(Game.Call("MachineTake", { id = id, what = "input" }))
		end, { Size = UDim2.fromOffset(120, 30), BackgroundColor3 = Kit.Colors.ButtonAlt })
		if reply.fired then
			Kit.Button(actions, "Weź paliwo", function()
				apply(Game.Call("MachineTake", { id = id, what = "fuel" }))
			end, { Size = UDim2.fromOffset(110, 30), BackgroundColor3 = Kit.Colors.ButtonAlt })
		end
	end

	table.insert(connections, Game.Changed.Event:Connect(render))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local recipe = current()
		if recipe == nil or labels.output == nil or labels.output.Parent == nil then
			return
		end
		local now = Game.Now()
		local s = Processing.Advance(reply.kind, reply.state, now)
		for i, entry in ipairs(recipe.ingredients) do
			labels[i].Text = Items.Name(entry[1]) .. ": " .. (s.inputs[i] or 0) .. " / " .. Processing.MaxInput
		end
		if labels.fuel then
			local fuel = s.fuelItem and (Items.Name(s.fuelItem) .. " × " .. s.fuel) or "brak"
			labels.fuel.Text = "Paliwo: " .. fuel .. " / " .. Processing.MaxFuel .. "   (żar na " .. s.heat .. " wsad.)"
		end
		labels.output.Text = "Gotowe: " .. Items.Name(recipe.id) .. " × " .. s.output .. " / " .. Processing.MaxOutput
		local progress = 0
		if s.startedAt then
			progress = math.clamp((now - s.startedAt) / recipe.time, 0, 1)
		end
		bar.Size = UDim2.fromScale(progress, 1)
	end))
	render()
	return window
end

return Machine
