-- The railway station's window (Shared.Rail): what the station holds and the inventory to load it
-- from, trains on their way; sending goods to another of the player's plots or to another player
-- found by name; routes that send a train by themselves every few minutes. The server checks it all
-- again.
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
local Rail = require(Shared.Rail)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Recipes = require(script.Parent.Recipes)
local InventoryWindow = require(script.Parent.Inventory)
local Game = require(script.Parent.Parent.Game)

local Station = {}

local function box(parent, text, placeholder, width)
	return Kit.New("TextBox", {
		Size = UDim2.fromOffset(width, 30),
		BackgroundColor3 = Color3.fromRGB(24, 27, 33),
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = Kit.Colors.Text,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Kit.Colors.Muted,
		Text = text,
		ClearTextOnFocus = false,
		Parent = parent,
	}, { Kit.Corner(6), Kit.New("UIStroke", { Color = Color3.fromRGB(90, 98, 115) }) })
end

-- "1 min 20 s" until `at`.
local function until_(at)
	local left = math.max(0, math.ceil(at - Game.Now()))
	if left >= 60 then
		return math.floor(left / 60) .. " min " .. left % 60 .. " s"
	end
	return left .. " s"
end

local function describe(items)
	local parts = {}
	for _, entry in ipairs(items) do
		table.insert(parts, entry[2] .. " × " .. Items.Name(entry[1]))
	end
	return table.concat(parts, ", ")
end

-- A wrapping grid of item tiles.
local function tiles(parent, size)
	return Kit.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		Kit.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(size, size + 4),
			CellPadding = UDim2.fromOffset(6, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

function Station.Open(screen)
	local reply = Game.Call("StationGet")
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connection
	local window, body = Kit.Window(screen, Rail.StationName, 640, 660, function()
		connection:Disconnect()
	end)
	local tab = "stock"
	local partner = reply.partners[1] and reply.partners[1].id
	local chosen = nil -- the item to send
	local routeItems = {} -- items of a new route, in order
	local every = reply.minutes[2] or reply.minutes[1]
	local typed = { name = "", quantity = "" }

	local function apply(r)
		if r then
			Game.SyncTime(r.serverTime)
			reply = r
		end
	end

	local function partnerOf(id)
		for _, p in ipairs(reply.partners) do
			if p.id == id then
				return p
			end
		end
		return nil
	end

	local function stockOf(item)
		for _, entry in ipairs(reply.stock) do
			if entry.item == item then
				return entry.quantity
			end
		end
		return 0
	end

	local render

	-- The station's goods as tiles; `onPick(item, half)`, `marked(item)` gives a gold frame.
	local function stockTiles(onPick, marked)
		if #reply.stock == 0 then
			Kit.Label(body, "Stacja jest pusta.", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
			return
		end
		local grid = tiles(body, 56)
		for i, entry in ipairs(reply.stock) do
			local slot = ItemGrid.Slot(grid, {
				size = 56,
				layoutOrder = i,
				onClick = function()
					onPick(entry.item, UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))
				end,
			})
			slot.Set(entry.item, tostring(entry.quantity))
			if marked and marked(entry.item) then
				slot.stroke.Color = Recipes.Colors.Selected
				slot.stroke.Thickness = 2.5
			end
		end
	end

	local function partners()
		if #reply.partners == 0 then
			Kit.Label(body, "Nikogo jeszcze nie znalazłeś. Wpisz nazwę gracza i kliknij Szukaj.", { TextColor3 = Kit.Colors.Muted, TextSize = 14, TextWrapped = true, Size = UDim2.new(1, -8, 0, 22) })
			return
		end
		for _, p in ipairs(reply.partners) do
			local row = Kit.Row(body, 34)
			if p.id == partner then
				row.BackgroundColor3 = Color3.fromRGB(110, 92, 40)
			end
			local how = p.own and ("pociąg jedzie " .. p.trip .. " s") or (p.km .. " km, pociąg jedzie " .. p.trip .. " s")
			Kit.Label(row, "<b>" .. p.name .. "</b>   " .. how, { RichText = true, Size = UDim2.new(1, -110, 1, 0), TextSize = 14 })
			Kit.Button(row, p.id == partner and "Wybrany" or "Wybierz", function()
				partner = p.id
				render()
			end, { Size = UDim2.fromOffset(90, 26), BackgroundColor3 = p.id == partner and Kit.Colors.ButtonAlt or Kit.Colors.Button })
		end
	end

	local function stockTab()
		Kit.Label(body, "Na stacji: kliknij, aby wyjąć do ekwipunku (Shift: połowę). Podajniki też ją ładują i rozładowują.", { TextColor3 = Kit.Colors.Muted, TextSize = 13, TextWrapped = true, Size = UDim2.new(1, -8, 0, 32) })
		stockTiles(function(item, half)
			local have = stockOf(item)
			local quantity = half and math.max(1, math.ceil(have / 2)) or have
			apply(Game.Call("StationUnload", { item = item, quantity = quantity }))
			render()
		end)
		if #reply.incoming > 0 or #reply.outgoing > 0 then
			Kit.Label(body, "<b>Pociągi w drodze</b>", { RichText = true, TextSize = 15 })
			for _, s in ipairs(reply.incoming) do
				Kit.Label(body, "⬅ od " .. tostring(s.fromName) .. ": " .. describe(s.items) .. " (za " .. until_(s.arriveAt) .. ")", { TextSize = 13, TextWrapped = true, Size = UDim2.new(1, -8, 0, 18), TextColor3 = Recipes.Colors.Enough })
			end
			for _, s in ipairs(reply.outgoing) do
				Kit.Label(body, "➡ do " .. tostring(s.toName) .. ": " .. describe(s.items) .. " (dojedzie za " .. until_(s.arriveAt) .. ")", { TextSize = 13, TextWrapped = true, Size = UDim2.new(1, -8, 0, 18) })
			end
		end
		Kit.Label(body, "Ekwipunek: kliknij, aby załadować na stację (Shift: połowę)", { TextColor3 = Kit.Colors.Muted, TextSize = 13 })
		local grid = ItemGrid.New(body, {
			columns = 9,
			tile = 54,
			onClick = function(_index, entry, half)
				local quantity = half and math.max(1, math.ceil(entry.quantity / 2)) or entry.quantity
				apply(Game.Call("StationLoad", { item = entry.item, quantity = quantity }))
				render()
			end,
			onMove = function(_from, to, entry)
				Game.Call("InventoryMove", { item = entry.item, slot = to })
			end,
		})
		grid.Set(ItemGrid.Inventory(Game, InventoryWindow.Tiles, 9))
		if #reply.log > 0 then
			Kit.Label(body, "<b>Ostatnio</b>", { RichText = true, TextSize = 15 })
			for i = #reply.log, math.max(1, #reply.log - 5), -1 do
				Kit.Label(body, reply.log[i].text, { TextSize = 13, TextWrapped = true, Size = UDim2.new(1, -8, 0, 18), TextColor3 = Kit.Colors.Muted })
			end
		end
	end

	local function findRow()
		local row = Kit.Row(body, 40)
		row.BackgroundTransparency = 1
		local name = box(row, typed.name, "Nazwa gracza", 220)
		name:GetPropertyChangedSignal("Text"):Connect(function()
			typed.name = name.Text
		end)
		Kit.Button(row, "Szukaj", function()
			local r = Game.Call("StationFind", { name = typed.name })
			if r then
				apply(r)
				for _, p in ipairs(reply.partners) do
					if string.lower(p.name) == string.lower(typed.name) then
						partner = p.id
					end
				end
				typed.name = ""
				render()
			end
		end, { Size = UDim2.fromOffset(90, 30) })
	end

	local function sendTab()
		Kit.Label(body, "Komu: na inną swoją działkę albo do gracza, którego znajdziesz po nazwie (na dowolnym serwerze).", { TextColor3 = Kit.Colors.Muted, TextSize = 13, TextWrapped = true, Size = UDim2.new(1, -8, 0, 32) })
		findRow()
		partners()
		local p = partnerOf(partner)
		Kit.Label(body, "Co: kliknij towar na stacji.", { TextColor3 = Kit.Colors.Muted, TextSize = 13 })
		if chosen and stockOf(chosen) == 0 then
			chosen = nil
		end
		stockTiles(function(item)
			chosen = item
			render()
		end, function(item)
			return item == chosen
		end)
		if p == nil or chosen == nil then
			return
		end
		local row = Kit.Row(body, 44)
		local have = stockOf(chosen)
		local amount = box(row, typed.quantity ~= "" and typed.quantity or tostring(have), "Ilość", 80)
		local fee = Kit.Label(row, "", { Size = UDim2.fromOffset(250, 30), TextSize = 14, TextColor3 = Kit.Colors.Money })
		local function quantity()
			return math.clamp(math.floor(tonumber(amount.Text) or 0), 0, have)
		end
		local function update()
			typed.quantity = amount.Text
			local q = quantity()
			fee.Text = q > 0 and ("Opłata " .. Money.Format(Rail.FeeCents(p.km, q)) .. ", " .. p.trip .. " s") or "Wpisz ilość"
		end
		amount:GetPropertyChangedSignal("Text"):Connect(update)
		update()
		Kit.Button(row, "Wyślij pociągiem", function()
			local q = quantity()
			if q > 0 then
				local r = Game.Call("StationSend", { to = p.id, item = chosen, quantity = q })
				if r then
					typed.quantity = ""
					apply(r)
					render()
				end
			end
		end, { Size = UDim2.fromOffset(150, 30) })
	end

	local function routesTab()
		Kit.Label(body, "Trasa wysyła pociąg sama co kilka minut, z tym, co jest na stacji (do " .. Rail.RouteCapacity .. " szt.), póki jesteś w grze.", { TextColor3 = Kit.Colors.Muted, TextSize = 13, TextWrapped = true, Size = UDim2.new(1, -8, 0, 32) })
		local problems = { empty = "ostatnio stacja była pusta", no_money = "zabrakło pieniędzy na opłatę" }
		for _, route in ipairs(reply.routes) do
			local row = Kit.Row(body, 46)
			local what = #route.items > 0 and table.concat((function()
				local names = {}
				for _, item in ipairs(route.items) do
					table.insert(names, Items.Name(item))
				end
				return names
			end)(), ", ") or "wszystko"
			local status = route.problem and (" · ⚠ " .. (problems[route.problem] or Game.ErrorText(route.problem))) or (" · następny za " .. until_(route.nextAt))
			Kit.Label(row, "<b>" .. route.fromName .. " ➡ " .. route.toName .. "</b> co " .. route.every .. " min: " .. what .. status, { RichText = true, TextWrapped = true, TextSize = 13, Size = UDim2.new(1, -90, 1, 0) })
			Kit.Button(row, "Usuń", function()
				apply(Game.Call("StationUnroute", { id = route.id }))
				render()
			end, { Size = UDim2.fromOffset(70, 26), BackgroundColor3 = Kit.Colors.Danger })
		end
		if #reply.routes >= reply.maxRoutes then
			return
		end
		Kit.Label(body, "<b>Nowa trasa</b> · dokąd:", { RichText = true, TextSize = 15 })
		findRow()
		partners()
		local p = partnerOf(partner)
		local row = Kit.Row(body, 36)
		row.BackgroundTransparency = 1
		Kit.Label(row, "Co ile:", { Size = UDim2.fromOffset(60, 30), TextSize = 14 })
		for _, m in ipairs(reply.minutes) do
			Kit.Button(row, m .. " min", function()
				every = m
				render()
			end, { Size = UDim2.fromOffset(70, 28), BackgroundColor3 = m == every and Color3.fromRGB(110, 92, 40) or Kit.Colors.ButtonAlt })
		end
		Kit.Label(body, "Co wozi: kliknij towary na stacji (do " .. reply.maxRouteItems .. "); bez wybranych wozi wszystko.", { TextColor3 = Kit.Colors.Muted, TextSize = 13, TextWrapped = true, Size = UDim2.new(1, -8, 0, 32) })
		local picked = {}
		for _, item in ipairs(routeItems) do
			picked[item] = true
		end
		stockTiles(function(item)
			if picked[item] then
				for i, other in ipairs(routeItems) do
					if other == item then
						table.remove(routeItems, i)
					end
				end
			elseif #routeItems < reply.maxRouteItems then
				table.insert(routeItems, item)
			end
			render()
		end, function(item)
			return picked[item]
		end)
		Recipes.Action(Kit.Row(body, 40), p and ("Dodaj trasę do " .. p.name) or "Wybierz, dokąd", p ~= nil, function()
			if p then
				local r = Game.Call("StationRoute", { to = p.id, items = routeItems, every = every })
				if r then
					routeItems = {}
					apply(r)
					render()
				end
			end
		end)
	end

	function render()
		Kit.Clear(body)
		Recipes.Tabs(body, {
			{ id = "stock", name = "Magazyn" },
			{ id = "send", name = "Wyślij" },
			{ id = "routes", name = "Trasy (" .. #reply.routes .. ")" },
		}, tab, function(id)
			tab = id
			render()
		end)
		if tab == "stock" then
			stockTab()
		elseif tab == "send" then
			sendTab()
		else
			routesTab()
		end
	end

	connection = Game.Changed.Event:Connect(function()
		if UserInputService:GetFocusedTextBox() == nil then
			local r = Game.Call("StationGet")
			apply(r)
			render()
		end
	end)
	render()
	return window
end

return Station
