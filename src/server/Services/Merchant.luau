-- The merchant on the square: sells tools and buys everything the player makes, at the prices
-- of Shared.Prices. The money and the items change together, with nothing that yields between
-- the check and the change, so a trade is all or nothing.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PlotLayout = require(Shared.PlotLayout)
local Items = require(Shared.Items)
local Prices = require(Shared.Prices)
local Inventory = require(script.Parent.Inventory)
local Wallet = require(script.Parent.Wallet)
local Net = require(script.Parent.Net)

local Merchant = {}

-- Studs from the stall within which a player can trade.
local Reach = 20
local StallPosition = Vector3.new(PlotLayout.Stall.x, 2, PlotLayout.Stall.z)

local function list()
	local items = {}
	for _, id in ipairs(Items.Order) do
		if Prices.Sells[id] or Prices.Buys[id] then
			table.insert(items, { id = id, buyCents = Prices.Sells[id], sellCents = Prices.Buys[id] })
		end
	end
	return items
end

function Merchant.Start()
	Net.Handle("Prices", function()
		return { ok = true, items = list() }
	end)

	Net.Handle("Buy", function(player, profile, payload)
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Prices.MaxQuantity)
		if item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		if not Net.Near(player, StallPosition, Reach) then
			return Net.Error("too_far")
		end
		local price = Prices.Sells[item]
		if price == nil then
			return Net.Error("not_sold")
		end
		if not Wallet.TryDebit(profile, price * quantity, "merchant_buy:" .. item) then
			return Net.Error("not_enough_money")
		end
		Inventory.Add(profile, item, quantity)
		Net.PushState(player)
		return { ok = true, balanceCents = profile.balanceCents }
	end)

	Net.Handle("Sell", function(player, profile, payload)
		local item = Net.Item(payload.item)
		local quantity = Net.Int(payload.quantity, 1, Prices.MaxQuantity)
		if item == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		if not Net.Near(player, StallPosition, Reach) then
			return Net.Error("too_far")
		end
		local price = Prices.Buys[item]
		if price == nil then
			return Net.Error("not_bought")
		end
		if not Inventory.TryRemove(profile, item, quantity) then
			return Net.Error("not_enough_items")
		end
		Wallet.Credit(profile, price * quantity, "merchant_sell:" .. item)
		Net.PushState(player)
		return { ok = true, balanceCents = profile.balanceCents }
	end)
end

return Merchant
