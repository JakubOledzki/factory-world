-- Money is kept in cents (whole numbers) and shown as "1 234,56 $".
local Money = {}

function Money.Format(cents)
	local negative = cents < 0
	if negative then
		cents = -cents
	end
	local whole = math.floor(cents / 100)
	local rest = cents - whole * 100
	local digits = tostring(whole)
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	local text = grouped
	if rest ~= 0 then
		text = text .. "," .. string.format("%02d", rest)
	end
	return (negative and "-" or "") .. text .. " $"
end

return Money
