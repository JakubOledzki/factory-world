-- The market between players (server Services/PlayerMarket), on every server at once. On the left
-- every item as a tile with its lowest price; on the right the chosen item's offers: listings to
-- buy from (cheapest first) and orders to sell into (best-paying first), and a form to put up a
-- listing or an order. "Moje oferty" lists the player's own offers to cancel. What others buy from
-- the player or sell to them comes in by itself, also while the player is away.
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
local MarketEvents = require(Shared.MarketEvents)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local Market = {}

-- Cents from what the player typed as dollars ("3", "2,5", "2.50"), or nil.
function Market.ParseCents(text)
	local cleaned = string.gsub(string.gsub(text or "", "%s", ""), ",", ".")
	cleaned = string.gsub(cleaned, "%$", "")
	local n = tonumber(cleaned)
	if n == nil or n <= 0 then
		return nil
	end
	return math.floor(n * 100 + 0.5)
end

local function box(parent, text, placeholder, width)
	return Kit.New("TextBox", {
		Size = UDim2.fromOffset(width, 32),
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

local function pane(parent, x, width)
	return Kit.New("ScrollingFrame", {
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(0, width, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = parent,
	}, { Kit.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
end

function Market.Open(screen)
	local reply = Game.Call("MarketGet")
	if reply == nil then
		return nil
	end
	local connections = {}
	local window, body = Kit.Window(screen, "Rynek graczy", 900, 600, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)
	local tab = "market"
	local summary = reply.items
	local selected
	for _, s in ipairs(summary) do
		if selected == nil and not s.locked and (s.lowestCents or s.highestCents) then
			selected = s.item
		end
	end
	selected = selected or Items.Wood
	local board -- the chosen item's offers from the server
	local mine -- the player's offers
	local quantityText, priceText = "10", ""
	local category, searchText = "all", ""
	local render

	local function summaryOf(item)
		for _, s in ipairs(summary) do
			if s.item == item then
				return s
			end
		end
		return {}
	end

	local function loadBoard()
		local r = Game.Call("MarketBoard", { item = selected })
		board = r
		if r then
			summary = r.summary
		end
	end

	-- Every step that changes the market answers with the item's board.
	local function act(name, payload)
		local r = Game.Call(name, payload)
		if r then
			board = r
			summary = r.summary
			Game.Toast:Fire("Gotowe.")
		end
		render()
	end

	local function quantity()
		return tonumber(quantityText) and math.floor(tonumber(quantityText)) or nil
	end

	local function marketTab(holder)
		-- Left: the items of the chosen group, narrowed by what the player typed.
		local left = pane(holder, 0, 300)
		local search = box(left, searchText, "Szukaj, np. deski", 284)
		search.TextXAlignment = Enum.TextXAlignment.Left
		Kit.New("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = search })
		Kit.Label(left, "Towary (najniższa cena)", { TextColor3 = Kit.Colors.Muted, TextSize = 13 })
		local grid = Kit.New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = left,
		}, {
			Kit.New("UIGridLayout", {
				CellSize = UDim2.fromOffset(52, 72),
				CellPadding = UDim2.fromOffset(6, 2),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local function fill()
			for _, child in ipairs(grid:GetChildren()) do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local wanted = string.lower(searchText)
			local index = 0
			for _, s in ipairs(summary) do
				local fits = (category == "all" or Items.Category(s.item) == category)
					and (wanted == "" or string.find(string.lower(Items.Name(s.item)), wanted, 1, true) ~= nil)
				if fits then
					index = index + 1
					local slot = ItemGrid.Slot(grid, {
						size = 52,
						layoutOrder = index,
						caption = s.lowestCents and Money.Format(s.lowestCents) or (s.highestCents and "zam." or "—"),
						captionColor = s.lowestCents and Kit.Colors.Money or Kit.Colors.Muted,
						onClick = function()
							selected = s.item
							board = nil
							render()
						end,
					})
					slot.Set(s.item, s.listed > 0 and tostring(s.listed) or "", s.locked)
					if s.item == selected then
						slot.stroke.Color = Recipes.Colors.Selected
						slot.stroke.Thickness = 2.5
					end
					if s.locked then
						Kit.Label(slot.button, "🔒", { Position = UDim2.fromOffset(3, 1), Size = UDim2.fromOffset(18, 18), TextSize = 12, ZIndex = 6 })
					end
				end
			end
			if index == 0 then
				Kit.Label(grid, "Nic nie pasuje.", { TextColor3 = Kit.Colors.Muted, TextSize = 13 })
			end
		end
		search:GetPropertyChangedSignal("Text"):Connect(function()
			searchText = search.Text
			fill()
		end)
		fill()

		-- Right: the chosen item.
		local right = pane(holder, 312, 552)
		local s = summaryOf(selected)
		local card = Kit.New("Frame", { Size = UDim2.new(1, -10, 0, 100), BackgroundColor3 = Kit.Colors.Row, Parent = right }, { Kit.Corner(8) })
		local big = ItemGrid.Slot(card, { size = 76 })
		big.frame.Position = UDim2.fromOffset(10, 12)
		big.Set(selected, tostring(Game.Count(selected)), s.locked)
		Kit.Label(card, Items.Name(selected) .. "   (masz " .. Game.Count(selected) .. ")", {
			Position = UDim2.fromOffset(98, 8), Size = UDim2.new(1, -108, 0, 22), Font = Enum.Font.GothamBold, TextSize = 18,
		})
		local best = "Najtaniej: " .. (s.lowestCents and (Money.Format(s.lowestCents) .. " (" .. s.listed .. " szt.)") or "brak ofert")
			.. "   ·   Najwięcej płacą: " .. (s.highestCents and (Money.Format(s.highestCents) .. " (" .. s.wanted .. " szt.)") or "brak zamówień")
		Kit.Label(card, best, { Position = UDim2.fromOffset(98, 34), Size = UDim2.new(1, -108, 0, 18), TextSize = 13, TextColor3 = Kit.Colors.Money })
		local prices = MarketEvents.Prices(Game.Now())
		local merchant = {}
		if prices.buys[selected] then
			table.insert(merchant, "skupuje po " .. Money.Format(prices.buys[selected]))
		end
		if prices.sells[selected] then
			table.insert(merchant, "sprzedaje po " .. Money.Format(prices.sells[selected]))
		end
		Kit.Label(card, "Handlarz: " .. (#merchant > 0 and table.concat(merchant, ", ") or "nie handluje tym"), {
			Position = UDim2.fromOffset(98, 56), Size = UDim2.new(1, -108, 0, 18), TextSize = 13, TextColor3 = Kit.Colors.Muted,
		})
		if s.locked then
			Kit.Label(card, "🔒 Najpierw to zbadaj, wtedy kupisz to od graczy.", {
				Position = UDim2.fromOffset(98, 76), Size = UDim2.new(1, -108, 0, 18), TextSize = 13, TextColor3 = Recipes.Colors.Selected,
			})
		end

		-- The form: how many and at what price.
		local form = Kit.Row(right, 44)
		Kit.Label(form, "Ilość", { Size = UDim2.fromOffset(38, 32), TextSize = 14 })
		local q = box(form, quantityText, "10", 70)
		Kit.Label(form, "Cena za szt. ($)", { Size = UDim2.fromOffset(112, 32), TextSize = 14 })
		local p = box(form, priceText, s.lowestCents and Money.Format(s.lowestCents) or "np. 2,50", 90)
		local total = Kit.Label(form, "", { Size = UDim2.fromOffset(170, 32), TextSize = 13, TextColor3 = Kit.Colors.Muted })
		local function showTotal()
			local cents, n = Market.ParseCents(priceText), quantity()
			total.Text = (cents and n and n > 0) and ("razem " .. Money.Format(cents * n)) or ""
		end
		q:GetPropertyChangedSignal("Text"):Connect(function()
			quantityText = q.Text
			showTotal()
		end)
		p:GetPropertyChangedSignal("Text"):Connect(function()
			priceText = p.Text
			showTotal()
		end)
		showTotal()
		local buttons = Kit.Row(right, 40)
		buttons.BackgroundTransparency = 1
		local function offer(name)
			local n, cents = quantity(), Market.ParseCents(priceText)
			if n == nil or n <= 0 or cents == nil then
				Game.Toast:Fire("Wpisz ilość i cenę za sztukę.")
				return
			end
			act(name, { item = selected, quantity = n, priceCents = cents })
		end
		Kit.Button(buttons, "Wystaw na sprzedaż", function()
			offer("MarketList")
		end, { Size = UDim2.fromOffset(180, 32), TextSize = 14 })
		Kit.Button(buttons, "Złóż zamówienie", function()
			offer("MarketOrder")
		end, { Size = UDim2.fromOffset(160, 32), TextSize = 14, BackgroundColor3 = Kit.Colors.ButtonAlt })
		Kit.Label(buttons, "Towar lub pieniądze czekają w ofercie.", { Size = UDim2.fromOffset(190, 32), TextSize = 12, TextColor3 = Kit.Colors.Muted, TextWrapped = true })

		if board == nil then
			Kit.Label(right, "Wczytywanie ofert...", { TextColor3 = Kit.Colors.Muted })
			task.spawn(function()
				loadBoard()
				if window.Parent then
					render()
				end
			end)
			return
		end

		local function rows(title, list, verb, remote)
			Kit.Label(right, title, { Font = Enum.Font.GothamBold, TextSize = 15 })
			if #list == 0 then
				Kit.Label(right, "Brak.", { TextColor3 = Kit.Colors.Muted, TextSize = 13 })
			end
			for _, o in ipairs(list) do
				local row = Kit.Row(right, 36)
				Kit.Label(row, Money.Format(o.priceCents), { Size = UDim2.fromOffset(100, 30), Font = Enum.Font.GothamBold, TextColor3 = Kit.Colors.Money })
				Kit.Label(row, o.left .. " szt.", { Size = UDim2.fromOffset(80, 30), TextSize = 14 })
				Kit.Label(row, o.name or "?", { Size = UDim2.fromOffset(170, 30), TextSize = 14, TextColor3 = Kit.Colors.Muted, TextTruncate = Enum.TextTruncate.AtEnd })
				if o.mine then
					Kit.Label(row, "twoja oferta", { Size = UDim2.fromOffset(120, 30), TextSize = 13, TextColor3 = Recipes.Colors.Selected })
				else
					Kit.Button(row, verb, function()
						local n = math.min(quantity() or 1, o.left)
						act(remote, { item = selected, id = o.id, quantity = math.max(1, n), priceCents = o.priceCents })
					end, { Size = UDim2.fromOffset(120, 28), BackgroundColor3 = remote == "MarketBuy" and Kit.Colors.Button or Kit.Colors.ButtonAlt })
				end
			end
		end
		rows("Na sprzedaż (od najtańszych): kupujesz tyle, ile wpisane w Ilość", board.listings, "Kup", "MarketBuy")
		rows("Zamówienia (kto płaci najwięcej): sprzedajesz ze swojego ekwipunku", board.orders, "Sprzedaj", "MarketFill")
	end

	local function mineTab(holder)
		local list = pane(holder, 0, 864)
		Kit.Label(list, "Pieniądze za sprzedany towar i kupiony towar trafiają do ciebie same, także gdy cię nie ma (co minutę).", {
			TextColor3 = Kit.Colors.Muted, TextSize = 13, Size = UDim2.new(1, -10, 0, 20),
		})
		if mine == nil then
			Kit.Label(list, "Wczytywanie...", { TextColor3 = Kit.Colors.Muted })
			task.spawn(function()
				mine = Game.Call("MarketMine") or { offers = {}, maxOffers = 20 }
				if window.Parent then
					render()
				end
			end)
			return
		end
		if #mine.offers == 0 then
			Kit.Label(list, "Nie masz otwartych ofert.", { TextColor3 = Kit.Colors.Muted })
		end
		for _, o in ipairs(mine.offers) do
			local row = Kit.Row(list, 52)
			local slot = ItemGrid.Slot(row, { size = 42 })
			slot.Set(o.item, "")
			local verb = o.offerKind == "listing" and "Sprzedajesz" or "Kupujesz"
			local done = o.quantity - o.left
			Kit.Label(row, verb .. ": " .. Items.Name(o.item) .. " po " .. Money.Format(o.priceCents), { Size = UDim2.fromOffset(360, 40), Font = Enum.Font.GothamBold, TextSize = 15 })
			Kit.Label(row, "zostało " .. o.left .. " z " .. o.quantity .. (done > 0 and ("  (" .. done .. " już " .. (o.offerKind == "listing" and "sprzedane" or "kupione") .. ")") or ""), {
				Size = UDim2.fromOffset(280, 40), TextSize = 14, TextColor3 = Kit.Colors.Muted,
			})
			Kit.Button(row, "Anuluj", function()
				if Game.Call("MarketCancel", { item = o.item, offerKind = o.offerKind, id = o.id }) then
					Game.Toast:Fire("Oferta anulowana, reszta wróciła do ciebie.")
				end
				mine = nil
				board = nil
				render()
			end, { Size = UDim2.fromOffset(110, 30), BackgroundColor3 = Kit.Colors.Danger })
		end
		Kit.Label(list, "Najwięcej " .. mine.maxOffers .. " ofert sprzedaży i " .. mine.maxOffers .. " zamówień naraz.", { TextColor3 = Kit.Colors.Muted, TextSize = 13 })
	end

	render = function()
		if window.Parent == nil then
			return
		end
		Kit.Clear(body)
		Recipes.Tabs(body, { { id = "market", name = "Rynek" }, { id = "mine", name = "Moje oferty" } }, tab, function(id)
			tab = id
			mine = nil
			render()
		end)
		if tab == "market" then
			local ids = {}
			for _, s in ipairs(summary) do
				table.insert(ids, s.item)
			end
			Recipes.CategoryTabs(body, ids, category, function(id)
				category = id
				render()
			end)
		end
		local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, tab == "market" and 440 or 480), Parent = body })
		if tab == "market" then
			marketTab(holder)
		else
			mineTab(holder)
		end
	end

	table.insert(connections, Game.Changed.Event:Connect(function()
		-- The counts change; what the player typed stays, and nothing is redrawn while they type.
		if UserInputService:GetFocusedTextBox() == nil then
			render()
		end
	end))
	render()
	return window
end

return Market
