-- The merchant's window: buy tools, sell what the plot gave.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
local Kit = require(script.Parent.Kit)
local Game = require(script.Parent.Parent.Game)

local Merchant = {}

function Merchant.Open(screen)
	local reply = Game.Call("Prices")
	if reply == nil then
		return nil
	end
	local connection
	local window, body = Kit.Window(screen, "Handlarz", 560, 500, function()
		connection:Disconnect()
	end)
	local tab = "sell"

	local function trade(kind, item, quantity)
		if quantity > 0 then
			Game.Call(kind, { item = item, quantity = quantity })
		end
	end

	local function render()
		Kit.Clear(body)
		local tabs = Kit.Row(body, 40)
		tabs.BackgroundTransparency = 1
		Kit.Button(tabs, "Sprzedaj", function()
			tab = "sell"
			render()
		end, { BackgroundColor3 = tab == "sell" and Kit.Colors.Button or Kit.Colors.Row, Size = UDim2.fromOffset(120, 32) })
		Kit.Button(tabs, "Kup", function()
			tab = "buy"
			render()
		end, { BackgroundColor3 = tab == "buy" and Kit.Colors.Button or Kit.Colors.Row, Size = UDim2.fromOffset(120, 32) })

		for _, entry in ipairs(reply.items) do
			local id = entry.id
			if tab == "buy" and entry.buyCents then
				local row = Kit.Row(body)
				Kit.Swatch(row, Items.Colors[id])
				Kit.Label(row, Items.Name(id), { Size = UDim2.new(0, 170, 1, 0) })
				Kit.Label(row, Money.Format(entry.buyCents), { Size = UDim2.new(0, 90, 1, 0), TextColor3 = Kit.Colors.Money })
				Kit.Button(row, "Kup 1", function()
					trade("Buy", id, 1)
				end, { Size = UDim2.fromOffset(70, 28) })
				if not Items.Tools[id] then
					Kit.Button(row, "Kup 10", function()
						trade("Buy", id, 10)
					end, { Size = UDim2.fromOffset(70, 28) })
				end
			elseif tab == "sell" and entry.sellCents and Game.Count(id) > 0 then
				local have = Game.Count(id)
				local row = Kit.Row(body)
				Kit.Swatch(row, Items.Colors[id])
				Kit.Label(row, Items.Name(id) .. " (" .. have .. ")", { Size = UDim2.new(0, 170, 1, 0) })
				Kit.Label(row, Money.Format(entry.sellCents), { Size = UDim2.new(0, 90, 1, 0), TextColor3 = Kit.Colors.Money })
				Kit.Button(row, "Sprzedaj 1", function()
					trade("Sell", id, 1)
				end, { Size = UDim2.fromOffset(80, 28) })
				Kit.Button(row, "Wszystko", function()
					trade("Sell", id, Game.Count(id))
				end, { Size = UDim2.fromOffset(80, 28), BackgroundColor3 = Kit.Colors.ButtonAlt })
			end
		end
	end
	connection = Game.Changed.Event:Connect(render)
	render()
	return window
end

return Merchant
