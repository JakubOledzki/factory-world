-- The merchant on the square: sells tools and buys everything the player makes, at the prices
-- of Shared.Prices changed by the market's events and drift (Shared.MarketEvents). The money and the items change together, with nothing that yields between
-- the check and the change, so a trade is all or nothing.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PlotLayout = require(Shared.PlotLayout)
local Items = require(Shared.Items)
local Prices = require(Shared.Prices)
local MarketEvents = require(Shared.MarketEvents)
local Research = require(Shared.Research)
local Clock = require(script.Parent.Clock)
local Inventory = require(script.Parent.Inventory)
local Wallet = require(script.Parent.Wallet)
local Net = require(script.Parent.Net)
local Tutorial = require(script.Parent.Tutorial)

local Merchant = {}

-- Studs from the stall within which a player can trade.
local Reach = 20
local StallPosition = Vector3.new(PlotLayout.Stall.x, 2, PlotLayout.Stall.z)

local function event(e)
	return e and {
		id = e.event.id,
		name = e.event.name,
		description = e.event.description,
		startsAt = e.startsAt,
		endsAt = e.endsAt,
	}
end

-- What the merchant trades now, with the usual prices to compare, and the market's events.
local function list()
	local now = Clock.Now()
	local prices = MarketEvents.Prices(now)
	local items = {}
	for _, id in ipairs(Items.Order) do
		if prices.sells[id] or prices.buys[id] then
			table.insert(items, {
				id = id,
				buyCents = prices.sells[id],
				sellCents = prices.buys[id],
				usualBuyCents = Prices.Sells[id],
				usualSellCents = Prices.Buys[id],
			})
		end
	end
	return { ok = true, items = items, event = event(prices.event), nextEvent = event(MarketEvents.Next(now)), serverTime = now }
end

function Merchant.Start()
	Net.Handle("Prices", function()
		return list()
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
		local price = MarketEvents.Prices(Clock.Now()).sells[item]
		if price == nil then
			return Net.Error("not_sold")
		end
		if not Research.Unlocked(profile.research, item, Clock.Now()) then
			return Net.Error("not_researched")
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
		local price = MarketEvents.Prices(Clock.Now()).buys[item]
		if price == nil then
			return Net.Error("not_bought")
		end
		if not Inventory.TryRemove(profile, item, quantity) then
			return Net.Error("not_enough_items")
		end
		Wallet.Credit(profile, price * quantity, "merchant_sell:" .. item)
		Net.PushState(player)
		Tutorial.Note(player, profile, "sell", item, quantity)
		return { ok = true, balanceCents = profile.balanceCents }
	end)
end

return Merchant
