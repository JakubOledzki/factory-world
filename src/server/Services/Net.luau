-- Remotes and the checks every request goes through. A handler gets (player, profile, payload) and
-- returns a reply table; it never trusts the payload: numbers are checked for range and ids for
-- ownership. Errors go back as { ok = false, code = "snake_case" }.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Data = require(script.Parent.Data)

local Net = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

local events = {}

-- Requests one player may send in a second before the rest are refused.
local RateLimit = 20
local counts = {}

Players.PlayerRemoving:Connect(function(player)
	counts[player] = nil
end)

local function allowed(player)
	local now = os.clock()
	local c = counts[player]
	if c == nil or now - c.since >= 1 then
		c = { since = now, n = 0 }
		counts[player] = c
	end
	c.n = c.n + 1
	return c.n <= RateLimit
end

function Net.Event(name)
	if events[name] == nil then
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		events[name] = event
	end
	return events[name]
end

function Net.Handle(name, handler)
	assert(Remotes[name] == name, "unknown remote " .. name)
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	remote.OnServerInvoke = function(player, payload)
		if not allowed(player) then
			return { ok = false, code = "too_fast" }
		end
		local profile = Data.Get(player)
		if profile == nil then
			return { ok = false, code = "not_loaded" }
		end
		if payload ~= nil and type(payload) ~= "table" then
			return { ok = false, code = "bad_payload" }
		end
		local ok, reply = pcall(handler, player, profile, payload or {})
		if not ok then
			warn("[Net] " .. name .. " failed for " .. player.Name .. ": " .. tostring(reply))
			return { ok = false, code = "server_error" }
		end
		return reply
	end
end

function Net.Error(code)
	return { ok = false, code = code }
end

-- A known item id, or nil.
function Net.Item(value)
	if Items.IsKnown(value) then
		return value
	end
	return nil
end

-- A whole number from `min` to `max`, or nil.
function Net.Int(value, min, max)
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < min or value > max then
		return nil
	end
	return value
end

-- Whether the player's character stands within `range` studs of `position`.
function Net.Near(player, position, range)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - position).Magnitude <= range
end

-- Pushes the player's balance and inventory to their client and the leaderboard.
function Net.PushState(player)
	local profile = Data.Get(player)
	if profile == nil then
		return
	end
	Net.Event(Remotes.State):FireClient(player, {
		balanceCents = profile.balanceCents,
		inventory = profile.inventory,
	})
	local stats = player:FindFirstChild("leaderstats")
	local money = stats and stats:FindFirstChild("Pieniądze")
	if money then
		money.Value = math.floor(profile.balanceCents / 100)
	end
end

function Net.Toast(player, text)
	Net.Event(Remotes.Toast):FireClient(player, { text = text })
end

return Net
