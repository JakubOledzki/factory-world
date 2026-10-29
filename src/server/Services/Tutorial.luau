-- The tutorial (Shared.Tutorial): other services report what the player did with Note, and this one
-- moves the player's task along and pays its reward. Nothing here yields.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
local Rules = require(Shared.Tutorial)
local Inventory = require(script.Parent.Inventory)
local Wallet = require(script.Parent.Wallet)
local Net = require(script.Parent.Net)

local Tutorial = {}

-- Counts `amount` (default 1) of `event` (with `item`, if any) towards the player's task.
function Tutorial.Note(player, profile, event, item, amount)
	if profile.tutorial == nil then
		return
	end
	local before = profile.tutorial.progress
	local step = Rules.Note(profile.tutorial, event, item, amount)
	if step == nil then
		if profile.tutorial.progress ~= before then
			Net.PushState(player)
		end
		return
	end
	local parts = { Money.Format(step.rewardCents) }
	Wallet.Credit(profile, step.rewardCents, "tutorial:" .. step.id)
	for _, entry in ipairs(step.rewardItems or {}) do
		Inventory.Add(profile, entry[1], entry[2])
		table.insert(parts, entry[2] .. " × " .. Items.Name(entry[1]))
	end
	Net.Toast(player, "Zadanie wykonane: " .. step.title .. " (+" .. table.concat(parts, ", ") .. ")")
	Net.PushState(player)
end

function Tutorial.Start()
	Net.Handle("TutorialSkip", function(player, profile)
		if profile.tutorial then
			Rules.Skip(profile.tutorial)
		end
		Net.PushState(player)
		return { ok = true }
	end)
end

return Tutorial
