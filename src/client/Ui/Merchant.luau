-- The merchant's window: buy tools and buildings, sell what the plot gave. Items are tiles with
-- their price under them; a click picks one and the card above says what it costs and trades it.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
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
	local window, body = Kit.Window(screen, "Handlarz", 560, 600, function()
		connection:Disconnect()
	end)
	local tab = "sell"
	local selected = { sell = nil, buy = nil }

	local function trade(kind, item, quantity)
		if quantity > 0 then
			Game.Call(kind, { item = item, quantity = quantity })
		end
	end

	local function render()
		Kit.Clear(body)
		Recipes.Tabs(body, { { id = "sell", name = "Sprzedaj" }, { id = "buy", name = "Kup" } }, tab, function(id)
			tab = id
			render()
		end)

		local shown = {}
		for _, entry in ipairs(reply.items) do
			if tab == "buy" and entry.buyCents then
				table.insert(shown, entry)
			elseif tab == "sell" and entry.sellCents and Game.Count(entry.id) > 0 then
				table.insert(shown, entry)
			end
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
		Kit.Label(card, (tab == "buy" and "Cena: " or "Płaci: ") .. Money.Format(cents) .. " za sztukę   ·   masz " .. have, {
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
			local slot = ItemGrid.Slot(grid, {
				size = 56,
				caption = Money.Format(price),
				captionColor = Kit.Colors.Money,
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
