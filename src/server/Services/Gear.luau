-- The player's tools worn on the back (axe, pickaxe, hoe), so a player sees what they own: built
-- from the same parts as the tools' pictures (Shared.Icons), welded to the character and shown or
-- taken off as the inventory changes. Only for the look: the server checks the inventory itself.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Icons = require(Shared.Icons)
local Assemble = require(Shared.Assemble)
local Data = require(script.Parent.Data)
local Net = require(script.Parent.Net)

local Gear = {}

-- Where each tool hangs, from the middle of the back: slanted across it, head up.
local Worn = {
	{ item = Items.Axe, offset = CFrame.new(0.45, 0.1, 0.7) * CFrame.Angles(0, math.pi / 2, math.rad(62)) },
	{ item = Items.Pickaxe, offset = CFrame.new(-0.45, 0.1, 0.75) * CFrame.Angles(0, math.pi / 2, math.rad(118)) },
	{ item = Items.Hoe, offset = CFrame.new(0, -0.2, 0.85) * CFrame.Angles(0, math.pi / 2, math.rad(90)) },
}

local function torsoOf(character)
	return character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
end

local function wear(character, torso, entry)
	local model = Assemble.Model(character, "Gear_" .. entry.item, Icons.Model(entry.item), torso.CFrame * entry.offset, false)
	pcall(function()
		model:ScaleTo(0.75)
	end)
	model:PivotTo(torso.CFrame * entry.offset)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = part
			weld.Parent = part
		end
	end
end

-- Puts on the tools the player has and takes off those they no longer have.
function Gear.Sync(player, profile)
	local character = player.Character
	local torso = torsoOf(character)
	if torso == nil or profile == nil then
		return
	end
	for _, entry in ipairs(Worn) do
		local has = (profile.inventory[entry.item] or 0) > 0
		local model = character:FindFirstChild("Gear_" .. entry.item)
		if has and model == nil then
			wear(character, torso, entry)
		elseif not has and model ~= nil then
			model:Destroy()
		end
	end
end

function Gear.Start()
	local function watch(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.5)
			Gear.Sync(player, Data.Get(player))
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Data.OnLoaded(function(player, profile)
		Gear.Sync(player, profile)
	end)
	Net.OnPush(Gear.Sync)
end

return Gear
