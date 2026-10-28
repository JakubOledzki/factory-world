-- Money, in cents. Every change is an entry in the player's ledger with a reason. Nothing here
-- yields, so a check and the change that follows it can never be split by another request.
local Clock = require(script.Parent.Clock)

local Wallet = {}

-- Ledger entries kept per player; the oldest go first.
Wallet.LedgerSize = 200

local function record(profile, cents, reason)
	table.insert(profile.ledger, { at = Clock.Now(), cents = cents, reason = reason })
	while #profile.ledger > Wallet.LedgerSize do
		table.remove(profile.ledger, 1)
	end
end

function Wallet.Balance(profile)
	return profile.balanceCents
end

function Wallet.Credit(profile, cents, reason)
	assert(type(cents) == "number" and cents > 0 and cents % 1 == 0, "bad amount")
	assert(type(reason) == "string", "a reason is required")
	profile.balanceCents = profile.balanceCents + cents
	record(profile, cents, reason)
end

-- Takes `cents` if the player has them; false otherwise (nothing changes).
function Wallet.TryDebit(profile, cents, reason)
	assert(type(cents) == "number" and cents > 0 and cents % 1 == 0, "bad amount")
	assert(type(reason) == "string", "a reason is required")
	if profile.balanceCents < cents then
		return false
	end
	profile.balanceCents = profile.balanceCents - cents
	record(profile, -cents, reason)
	return true
end

return Wallet
