-- Orders from NPC companies (Shared.Contracts), three of the player's own at a time. The board on
-- the square (and key J) shows them; the pieces go from the inventory, also a few at a time, and
-- the reward comes with the last one. Taking the pieces and paying happen with nothing that yields
-- between, so a delivery is all or nothing.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
local Research = require(Shared.Research)
local Rules = require(Shared.Contracts)
local Clock = require(script.Parent.Clock)
local Inventory = require(script.Parent.Inventory)
local Wallet = require(script.Parent.Wallet)
local Net = require(script.Parent.Net)
local Tutorial = require(script.Parent.Tutorial)

local Contracts = {}

local random = Random.new()

local function roll(a, b)
	return random:NextInteger(a, b)
end

local function unlockedFor(profile, now)
	return function(item)
		return Research.Unlocked(profile.research, item, now)
	end
end

-- Ends the orders past their deadline (their pieces go back) and fills the empty places.
local function refresh(player, profile, now)
	profile.contracts = profile.contracts or Rules.New()
	local back = Rules.Refresh(profile.contracts, now, unlockedFor(profile, now), roll)
	if #back > 0 then
		local parts = {}
		for _, entry in ipairs(back) do
			Inventory.Add(profile, entry[1], entry[2])
			table.insert(parts, entry[2] .. " × " .. Items.Name(entry[1]))
		end
		Net.Toast(player, "Termin zlecenia minął, wraca do ciebie: " .. table.concat(parts, ", "))
		Net.PushState(player)
	end
end

local function reply(profile, now)
	local open, nextAt = Rules.Open(profile.contracts, now)
	return { ok = true, contracts = open, nextAt = nextAt, refill = Rules.Refill, serverTime = now }
end

function Contracts.Start()
	Net.Handle("ContractsGet", function(player, profile)
		local now = Clock.Now()
		refresh(player, profile, now)
		return reply(profile, now)
	end)

	Net.Handle("ContractDeliver", function(player, profile, payload)
		local id = Net.Int(payload.id, 1, 1e9)
		local quantity = Net.Int(payload.quantity, 1, 100000)
		if id == nil or quantity == nil then
			return Net.Error("bad_payload")
		end
		local now = Clock.Now()
		refresh(player, profile, now)
		local state = profile.contracts
		local open = Rules.Open(state, now)
		local item
		for _, o in ipairs(open) do
			if o.id == id then
				item = o.item
			end
		end
		if item == nil then
			return Net.Error("no_contract")
		end
		local given, o = Rules.Deliver(state, id, quantity, Inventory.Count(profile, item), now, unlockedFor(profile, now), roll)
		if given == nil then
			return Net.Error(o)
		end
		assert(Inventory.TryRemove(profile, item, given))
		if o.delivered >= o.quantity then
			Wallet.Credit(profile, o.rewardCents, "contract:" .. o.item)
			Net.Toast(player, "Zlecenie wykonane: " .. o.issuer .. " płaci " .. Money.Format(o.rewardCents))
			Tutorial.Note(player, profile, "contract")
		end
		Net.PushState(player)
		return reply(profile, now)
	end)

	Net.Handle("ContractDrop", function(player, profile, payload)
		local id = Net.Int(payload.id, 1, 1e9)
		if id == nil then
			return Net.Error("bad_payload")
		end
		local now = Clock.Now()
		refresh(player, profile, now)
		local o, code = Rules.Drop(profile.contracts, id, now, unlockedFor(profile, now), roll)
		if o == nil then
			return Net.Error(code)
		end
		if o.delivered > 0 then
			Inventory.Add(profile, o.item, o.delivered)
		end
		Net.PushState(player)
		return reply(profile, now)
	end)
end

return Contracts
