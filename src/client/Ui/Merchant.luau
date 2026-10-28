-- The merchant's window: buy tools and buildings, sell what the plot gave. Items are tiles with
-- their price under them (green when better than usual, red when worse); a click picks one and the
-- card above says what it costs and trades it. On top, the market's event now or the next one.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
local MarketEvents = require(Shared.MarketEvents)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local Merchant = {}

function Merchant.Open(screen)
	local reply = Game.Call("Prices")
	if reply == nil then
		return nil
	end
	local connection
	local window, body = Kit.Window(screen, "Handlarz", 580, 680, function()
		connection:Disconnect()
	end)
	Game.SyncTime(reply.serverTime)
	local tab = "sell"
	local selected = { sell = nil, buy = nil }
	local category = { sell = "all", buy = "all" }

	-- "3 h 12 min" until `at`.
	local function until_(at)
		local left = math.max(0, math.floor(at - Game.Now()))
		local h, m = math.floor(left / 3600), math.floor(left % 3600 / 60)
		return h > 0 and (h .. " h " .. m .. " min") or (m .. " min")
	end

	-- How a price compares with the usual one, for the player: better is green.
	local function compare(cents, usual, higherIsBetter)
		if usual == nil or cents == usual then
			return nil, nil
		end
		local change = MarketEvents.Change(cents, usual)
		if change == 0 then
			return nil, nil
		end
		local better = (change > 0) == higherIsBetter
		return (change > 0 and "+" or "") .. change .. "%", better and Recipes.Colors.Enough or Recipes.Colors.Short
	end

	local function trade(kind, item, quantity)
		if quantity > 0 then
			Game.Call(kind, { item = item, quantity = quantity })
		end
	end

	local function render()
		Kit.Clear(body)
		local e = reply.event
		local banner = Kit.New("Frame", {
			Size = UDim2.new(1, -8, 0, 46),
			BackgroundColor3 = e and Color3.fromRGB(92, 72, 30) or Kit.Colors.Row,
			Parent = body,
		}, { Kit.Corner(8), Kit.New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
		local text
		if e then
			text = "<b>" .. e.name .. "</b> (jeszcze " .. until_(e.endsAt) .. "): " .. e.description
		elseif reply.nextEvent then
			text = "Spokojny rynek. Ceny skupu wahają się codziennie do 10%. Następne wydarzenie: <b>"
				.. reply.nextEvent.name .. "</b> za " .. until_(reply.nextEvent.startsAt) .. "."
		else
			text = "Spokojny rynek. Ceny skupu wahają się codziennie do 10%."
		end
		Kit.Label(banner, text, { Size = UDim2.fromScale(1, 1), RichText = true, TextWrapped = true, TextSize = 13 })
		Recipes.Tabs(body, { { id = "sell", name = "Sprzedaj" }, { id = "buy", name = "Kup" } }, tab, function(id)
			tab = id
			render()
		end)

		local offered, ids = {}, {}
		for _, entry in ipairs(reply.items) do
			if (tab == "buy" and entry.buyCents) or (tab == "sell" and entry.sellCents and Game.Count(entry.id) > 0) then
				table.insert(offered, entry)
				table.insert(ids, entry.id)
			end
		end
		-- The group tabs: a group with nothing in it here falls back to all.
		local shown = {}
		for _, entry in ipairs(offered) do
			if category[tab] == "all" or Items.Category(entry.id) == category[tab] then
				table.insert(shown, entry)
			end
		end
		if #shown == 0 and category[tab] ~= "all" then
			category[tab] = "all"
			shown = offered
		end
		if #offered > 0 then
			Recipes.CategoryTabs(body, ids, category[tab], function(id)
				category[tab] = id
				render()
			end)
		end
		if #shown == 0 then
			Kit.Label(body, "Nie masz nic, co handlarz kupi. Wykop rudę albo zetnij drzewo.", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
			return
		end
		local chosen = shown[1]
		for _, entry in ipairs(shown) do
			if entry.id == selected[tab] then
				chosen = entry
			end
		end

		-- The card of the chosen item.
		local id = chosen.id
		local have = Game.Count(id)
		local card = Kit.New("Frame", {
			Size = UDim2.new(1, -8, 0, 112),
			BackgroundColor3 = Kit.Colors.Row,
			Parent = body,
		}, { Kit.Corner(8) })
		local big = ItemGrid.Slot(card, { size = 88 })
		big.frame.Position = UDim2.fromOffset(10, 12)
		big.Set(id, have > 0 and tostring(have) or "")
		Kit.Label(card, Items.Name(id), {
			Position = UDim2.fromOffset(110, 10),
			Size = UDim2.new(1, -120, 0, 22),
			Font = Enum.Font.GothamBold,
			TextSize = 18,
		})
		local cents = tab == "buy" and chosen.buyCents or chosen.sellCents
		local usual = tab == "buy" and chosen.usualBuyCents or chosen.usualSellCents
		local change = compare(cents, usual, tab == "sell")
		Kit.Label(card, (tab == "buy" and "Cena: " or "Płaci: ") .. Money.Format(cents) .. " za sztukę"
			.. (change and ("  (" .. change .. ", zwykle " .. Money.Format(usual) .. ")") or "") .. "   ·   masz " .. have, {
			Position = UDim2.fromOffset(110, 34),
			Size = UDim2.new(1, -120, 0, 20),
			TextSize = 15,
			TextColor3 = Kit.Colors.Money,
		})
		local actions = Kit.New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(110, 66),
			Size = UDim2.new(1, -120, 0, 34),
			Parent = card,
		}, {
			Kit.New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local size = UDim2.fromOffset(120, 32)
		if tab == "buy" then
			Kit.Button(actions, "Kup 1", function()
				trade("Buy", id, 1)
			end, { Size = size })
			if not Items.Tools[id] then
				Kit.Button(actions, "Kup 10", function()
					trade("Buy", id, 10)
				end, { Size = size })
			end
		else
			Kit.Button(actions, "Sprzedaj 1", function()
				trade("Sell", id, 1)
			end, { Size = size })
			if have >= 10 then
				Kit.Button(actions, "Sprzedaj 10", function()
					trade("Sell", id, 10)
				end, { Size = size })
			end
			Kit.Button(actions, "Wszystko", function()
				trade("Sell", id, Game.Count(id))
			end, { Size = size, BackgroundColor3 = Kit.Colors.ButtonAlt })
		end

		-- The tiles, with the price under each.
		local grid = Kit.New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = body,
		}, {
			Kit.New("UIGridLayout", {
				CellSize = UDim2.fromOffset(56, 76),
				CellPadding = UDim2.fromOffset(8, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for index, entry in ipairs(shown) do
			local price = tab == "buy" and entry.buyCents or entry.sellCents
			local _, color = compare(price, tab == "buy" and entry.usualBuyCents or entry.usualSellCents, tab == "sell")
			local slot = ItemGrid.Slot(grid, {
				size = 56,
				caption = Money.Format(price),
				captionColor = color or Kit.Colors.Money,
				layoutOrder = index,
				onClick = function()
					selected[tab] = entry.id
					render()
				end,
			})
			local count = Game.Count(entry.id)
			slot.Set(entry.id, count > 0 and tostring(count) or "")
			if entry == chosen then
				slot.stroke.Color = Recipes.Colors.Selected
				slot.stroke.Thickness = 2.5
			end
		end
	end
	connection = Game.Changed.Event:Connect(render)
	render()
	return window
end

return Merchant
