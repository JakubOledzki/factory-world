-- Research (Shared.Research): the player starts a technology from anywhere; its cost is taken at
-- once, together with the start, and it is done when its time has passed, also while the player is
-- away. Nothing runs in a loop.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Research = require(Shared.Research)
local Clock = require(script.Parent.Clock)
local Inventory = require(script.Parent.Inventory)
local Net = require(script.Parent.Net)
local Tutorial = require(script.Parent.Tutorial)

local Lab = {}

local function reply(profile)
	local now = Clock.Now()
	local list = {}
	for _, t in ipairs(Research.Technologies) do
		local r = profile.research[t.id]
		table.insert(list, {
			id = t.id,
			name = t.name,
			description = t.description,
			requires = t.requires,
			cost = t.cost,
			time = t.time,
			unlocks = t.unlocks,
			status = Research.Status(profile.research, t.id, now),
			startsAt = r and r.startsAt,
			finishesAt = r and r.finishesAt,
		})
	end
	return { ok = true, technologies = list, serverTime = now }
end

function Lab.Start()
	Net.Handle("ResearchGet", function(_player, profile)
		return reply(profile)
	end)

	Net.Handle("ResearchStart", function(player, profile, payload)
		local id = type(payload.id) == "string" and payload.id or nil
		local t = id and Research.ById[id]
		if t == nil then
			return Net.Error("bad_payload")
		end
		local after, code = Research.Start(profile.research, id, Clock.Now())
		if after == nil then
			return Net.Error(code)
		end
		if not Inventory.HasAll(profile, t.cost) then
			return Net.Error("not_enough_items")
		end
		for _, entry in ipairs(t.cost) do
			Inventory.TryRemove(profile, entry[1], entry[2])
		end
		profile.research = after
		Net.PushState(player)
		Tutorial.Note(player, profile, "research", id)
		return reply(profile)
	end)
end

return Lab
