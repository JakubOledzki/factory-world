-- Draws what moves on the build grids smoothly. The server says what each belt and inserter holds
-- in attributes of its model, once a tick (Logistics.Tick): "Items" on a belt (with ">" after an
-- item that slid into its place) and "Arm" on an inserter (its swing and its load). Here the items
-- glide from the place behind to their new one and the arms swing round over that tick, every
-- frame. A machine the server marks "Working" turns its parts of group "spin" (a saw blade, rollers).
-- It only draws; nothing here changes the game.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Logistics = require(Shared.Logistics)
local Models = require(Shared.Models)

local GridView = {}

local Tick = Logistics.Tick
local slotCount = Logistics.BeltSlots * Logistics.BeltLanes

local belts = {} -- [Model] = { parts = { Part }, moving = { [Part] = { from, to, t0 } } }
local arms = {} -- [Model] = { parts = { { Part, CFrame } }, hand, from, to, t0, angle }
local working = {} -- [Model] = true while a machine works

-- Radians a working machine's spinning parts turn each second.
local SpinSpeed = 9

local function split(text, sep)
	local out = {}
	local start = 1
	while true do
		local at = string.find(text, sep, start, true)
		if at == nil then
			table.insert(out, string.sub(text, start))
			return out
		end
		table.insert(out, string.sub(text, start, at - 1))
		start = at + 1
	end
end

local function colorOf(item)
	local c = Items.Colors[item] or { 200, 200, 200 }
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Where an item rides in `slot` of a belt that turns `bend`, or the place behind it (`back`).
local function slotCFrame(base, slot, bend, back)
	local p = Models.BeltSlot(slot, Logistics.BeltSlots, bend, back)
	return base * CFrame.new(p[1], p[2], p[3])
end

local function updateBelt(model)
	local base = model:GetAttribute("Base")
	local text = model:GetAttribute("Items")
	if base == nil or text == nil then
		return
	end
	local bend = model:GetAttribute("Bend") or 0
	local view = belts[model]
	if view == nil then
		view = { parts = {}, moving = {} }
		for slot = 1, slotCount do
			local part = Instance.new("Part")
			part.Name = "Item"
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.new(0.75, 0.75, 0.75)
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Transparency = 1
			part.CFrame = slotCFrame(base, slot, bend)
			part.Parent = model
			view.parts[slot] = part
		end
		belts[model] = view
	end
	local bar = string.find(text, "|", 1, true)
	local entries = split(string.sub(text, (bar or 0) + 1), ",")
	local now = os.clock()
	for slot, part in ipairs(view.parts) do
		local entry = entries[slot] or ""
		if entry == "" then
			part.Transparency = 1
			view.moving[part] = nil
		else
			local slid = string.sub(entry, -1) == ">"
			local item = slid and string.sub(entry, 1, -2) or entry
			part.Color = colorOf(item)
			part.Transparency = 0
			local target = slotCFrame(base, slot, bend)
			if slid then
				view.moving[part] = { from = slotCFrame(base, slot, bend, true), to = target, t0 = now }
				part.CFrame = view.moving[part].from
			else
				view.moving[part] = nil
				part.CFrame = target
			end
		end
	end
end

local function updateArm(model)
	local base = model:GetAttribute("Base")
	local text = model:GetAttribute("Arm")
	if base == nil or text == nil then
		return
	end
	local view = arms[model]
	if view == nil then
		view = { parts = {}, known = {}, angle = 0 }
		arms[model] = view
	end
	-- The server builds the arm pointing to the front and never moves it: remember each part against
	-- the inserter's base when it first shows up (parts can reach the client after the attributes).
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("Group") == "arm" and not view.known[part] then
			view.known[part] = true
			table.insert(view.parts, { part, base:ToObjectSpace(part.CFrame) })
			if part.Name == "Hand" then
				view.hand = part
			end
		end
	end
	local fields = split(text, ",")
	local swing = tonumber(fields[1]) or 0
	local hand = fields[2] or ""
	-- Pointing to the front (where it drops) at the end of its swing, to the back at the start.
	view.from = view.angle
	view.to = math.pi * (1 - swing / Logistics.SwingTicks)
	view.t0 = os.clock()
	view.base = base
	if view.hand then
		view.hand.Transparency = hand == "" and 1 or 0
		if hand ~= "" then
			view.hand.Color = colorOf(hand)
		end
	end
end

local function update(model)
	if model:GetAttribute("Items") ~= nil then
		updateBelt(model)
	elseif model:GetAttribute("Arm") ~= nil then
		updateArm(model)
	end
end

local function watch(model)
	if not model:IsA("Model") then
		return
	end
	model.AttributeChanged:Connect(function(name)
		if name == "Items" or name == "Arm" or name == "Base" then
			update(model)
		elseif name == "Working" then
			working[model] = model:GetAttribute("Working") or nil
		end
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			belts[model] = nil
			arms[model] = nil
			working[model] = nil
		end
	end)
	working[model] = model:GetAttribute("Working") or nil
	update(model)
end

function GridView.Start()
	local plots = workspace:WaitForChild("Plots")
	for _, descendant in ipairs(plots:GetDescendants()) do
		watch(descendant)
	end
	plots.DescendantAdded:Connect(watch)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		for model in pairs(working) do
			for _, part in ipairs(model:GetChildren()) do
				if part:IsA("BasePart") and part:GetAttribute("Group") == "spin" then
					part.CFrame = part.CFrame * CFrame.Angles(dt * SpinSpeed, 0, 0)
				end
			end
		end
		for _, view in pairs(belts) do
			for part, move in pairs(view.moving) do
				local alpha = math.clamp((now - move.t0) / Tick, 0, 1)
				part.CFrame = move.from:Lerp(move.to, alpha)
				if alpha >= 1 then
					view.moving[part] = nil
				end
			end
		end
		for _, view in pairs(arms) do
			if view.to ~= nil and view.angle ~= view.to then
				local alpha = math.clamp((now - view.t0) / Tick, 0, 1)
				view.angle = alpha >= 1 and view.to or view.from + (view.to - view.from) * alpha
				local turn = view.base * CFrame.Angles(0, view.angle, 0)
				for _, entry in ipairs(view.parts) do
					entry[1].CFrame = turn * entry[2]
				end
			end
		end
	end)
end

return GridView
