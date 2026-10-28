-- A generator's window: the fuel in it as a tile, how much of the piece in the fire is left, what
-- it gives and how its network is doing, and the inventory to load fuel from. The burning is worked
-- out here from what the server sent (the same Power.Burn), at the load the network had then.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Power = require(Shared.Power)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local InventoryWindow = require(script.Parent.Inventory)
local MachineWindow = require(script.Parent.Machine)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local Generator = {}

-- What one running generator of the network gives (kW), as Power shares the load.
local function load(net)
	if net == nil or net.supply <= 0 then
		return 0
	end
	local running = net.supply / Power.GeneratorKw
	return math.min(net.demand, net.supply) / running
end

function Generator.Open(screen, id)
	local reply = Game.Call("GeneratorGet", { id = id })
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connections = {}
	local window, body = Kit.Window(screen, Items.Name(Items.Generator), 520, 600, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)

	local live -- { fuel = slot, bar, power = label }

	local function apply(r)
		if r then
			Game.SyncTime(r.serverTime)
			reply = r
		end
	end

	-- The generator now, burnt since the reply.
	local function now()
		local g = reply.generator
		if not Power.Running(g) then
			return g, 0
		end
		local kw = load(reply.network)
		return Power.Burn(g, kw * math.max(0, Game.Now() - reply.serverTime)), kw
	end

	local function render()
		Kit.Clear(body)
		local net = reply.network
		local text, color
		if net == nil then
			text = "⚡ Nie jest podłączony: postaw słup energetyczny obok (zasięg słupa to 5 × 5 pól)."
			color = Recipes.Colors.Short
		elseif not Power.Running(reply.generator) then
			text = "⚡ Brak paliwa: włóż węgiel, drewno albo pellet."
			color = Recipes.Colors.Short
		elseif net.demand <= 0 then
			text = "⚡ Gotowy. Żadna maszyna w sieci nie pobiera teraz prądu, więc nic nie spala."
			color = Kit.Colors.Muted
		else
			text = "⚡ Pracuje i zasila sieć."
			color = Recipes.Colors.Enough
		end
		Kit.Label(body, text, { TextColor3 = color, TextSize = 14, Font = Enum.Font.GothamBold, TextWrapped = true, Size = UDim2.new(1, -8, 0, 36) })

		Kit.Label(body, "W generatorze (kliknij paliwo, aby wyjąć):", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
		local row, slot, arrow = MachineWindow.Contents(body)
		live = {}
		live.fuel = slot("Paliwo", function()
			apply(Game.Call("GeneratorTake", { id = id }))
		end)
		live.bar = arrow()
		live.bar.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
		live.power = Kit.Label(row, "", {
			Size = UDim2.fromOffset(200, 56),
			LayoutOrder = 10,
			TextSize = 22,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(255, 214, 90),
		})

		if net then
			Kit.Label(body, "Sieć: " .. net.poles .. " słup(y), " .. net.generators .. " generator(y), " .. net.machines
				.. " maszyn(y). Pobór " .. net.demand .. " kW, moc " .. net.supply .. " kW.", {
				TextSize = 14,
				TextWrapped = true,
				Size = UDim2.new(1, -8, 0, 36),
			})
		end
		local fuels = {}
		for _, f in ipairs(reply.fuels) do
			table.insert(fuels, Items.Name(f.id) .. " " .. math.floor(f.kj / reply.kw) .. " s")
		end
		Kit.Label(body, "Przy pełnej mocy (" .. reply.kw .. " kW) jedna sztuka starcza: " .. table.concat(fuels, ", ") .. ".", {
			TextColor3 = Kit.Colors.Muted,
			TextSize = 13,
			TextWrapped = true,
			Size = UDim2.new(1, -8, 0, 36),
		})

		-- The inventory: a click puts fuel in (Shift: half).
		Kit.Label(body, "Ekwipunek: kliknij paliwo, aby włożyć (Shift: połowę)", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
		local grid = ItemGrid.New(body, {
			columns = 7,
			tile = 54,
			hint = function(entry)
				return Power.Room(reply.generator, entry.item) > 0 and "kliknij, aby włożyć" or nil
			end,
			onClick = function(_index, entry, half)
				if Power.Fuels[entry.item] == nil then
					Game.Toast:Fire(Game.ErrorText("not_fuel"))
					return
				end
				local wanted = half and math.max(1, math.ceil(entry.quantity / 2)) or entry.quantity
				local quantity = math.min(wanted, Power.Room(reply.generator, entry.item))
				if quantity <= 0 then
					local busy = reply.generator.fuelItem ~= nil and reply.generator.fuelItem ~= entry.item
					Game.Toast:Fire(Game.ErrorText(busy and "generator_busy" or "generator_full"))
					return
				end
				apply(Game.Call("GeneratorLoad", { id = id, item = entry.item, quantity = quantity }))
			end,
			onMove = function(_from, to, entry)
				Game.Call("InventoryMove", { item = entry.item, slot = to })
			end,
		})
		grid.Set(ItemGrid.Inventory(Game, InventoryWindow.Tiles, 7))
	end

	table.insert(connections, Game.Changed.Event:Connect(render))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if live == nil or live.bar.Parent == nil then
			return
		end
		local g, kw = now()
		live.fuel.Set(g.fuelItem or reply.generator.fuelItem or Items.Coal, g.fuel .. "/" .. reply.maxFuel, g.fuel == 0)
		local piece = Power.Fuels[g.fuelItem or reply.generator.fuelItem or Items.Coal] or 1
		live.bar.Size = UDim2.fromScale(math.clamp(g.energy / piece, 0, 1), 1)
		live.power.Text = math.floor(kw + 0.5) .. " / " .. reply.kw .. " kW"
	end))
	render()
	return window
end

return Generator
