-- The server's time in Unix seconds (with fractions). Saved times (furnaces, mines, orders) use it,
-- so they stay right when the player comes back on another server.
local Clock = {}

function Clock.Now()
	return DateTime.now().UnixTimestampMillis / 1000
end

return Clock
