-- The research window: every technology with its picture, what it costs (tiles, red when short),
-- what it unlocks and how far it has got. Starting one takes its cost from the inventory at once.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Research = require(Shared.Research)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local ResearchWindow = {}

local function names(ids)
	local parts = {}
	for _, id in ipairs(ids) do
		table.insert(parts, Items.Name(id))
	end
	return table.concat(parts, ", ")
end

local function clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 60 then
		return math.floor(seconds / 60) .. " min " .. (seconds % 60) .. " s"
	end
	return seconds .. " s"
end

function ResearchWindow.Open(screen)
	local reply = Game.Call("ResearchGet")
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connections = {}
	local window, body = Kit.Window(screen, "Badania", 620, 560, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)
	local timers = {}
	local asked = false

	local function render()
		Kit.Clear(body)
		timers = {}
		Kit.Label(body, "Badanie zużywa surowce od razu i trwa swój czas, także gdy cię nie ma. Jedno naraz.", {
			TextColor3 = Kit.Colors.Muted, TextWrapped = true, TextSize = 14, Size = UDim2.new(1, 0, 0, 36),
		})
		for _, t in ipairs(reply.technologies) do
			local row = Kit.New("Frame", {
				Size = UDim2.new(1, -8, 0, 174),
				BackgroundColor3 = Kit.Colors.Row,
				Parent = body,
			}, { Kit.Corner(8) })
			local icon = ItemGrid.Slot(row, { size = 64 })
			icon.frame.Position = UDim2.fromOffset(10, 10)
			icon.Set(t.unlocks[1], "", t.status == "locked")
			local text = Kit.Label(row, "", {
				Position = UDim2.fromOffset(86, 6),
				Size = UDim2.new(1, -220, 0, 54),
				TextWrapped = true,
				RichText = true,
				TextSize = 14,
				TextYAlignment = Enum.TextYAlignment.Top,
			})
			text.Text = "<b>" .. t.name .. "</b>  (" .. clock(t.time) .. ")\n" .. t.description
			Kit.Label(row, "Koszt:", { Position = UDim2.fromOffset(86, 62), Size = UDim2.fromOffset(120, 16), TextSize = 12, TextColor3 = Kit.Colors.Muted })
			local cost = Recipes.Ingredients(row, t.cost, 36)
			cost.Position = UDim2.fromOffset(86, 80)
			cost.Size = UDim2.new(1, -220, 0, 54)
			Kit.Label(row, "Odblokowuje: " .. names(t.unlocks), {
				Position = UDim2.fromOffset(86, 140),
				Size = UDim2.new(1, -96, 0, 28),
				TextSize = 12,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextColor3 = Kit.Colors.Muted,
			})
			local side = Kit.New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 12),
				Size = UDim2.fromOffset(120, 60),
				Parent = row,
			})
			if t.status == "done" then
				Kit.Label(side, "✓ Zbadane", { Size = UDim2.new(1, 0, 0, 32), Font = Enum.Font.GothamBold, TextColor3 = Recipes.Colors.Enough })
			elseif t.status == "active" then
				local label = Kit.Label(side, "", { Size = UDim2.new(1, 0, 0, 40), Font = Enum.Font.GothamBold, TextWrapped = true, TextSize = 14 })
				table.insert(timers, { label = label, t = t })
			elseif t.status == "locked" then
				local needs = {}
				for _, need in ipairs(t.requires) do
					table.insert(needs, Research.ById[need] and Research.ById[need].name or need)
				end
				Kit.Label(side, "🔒 Najpierw: " .. table.concat(needs, ", "), { Size = UDim2.new(1, 0, 1, 0), TextColor3 = Kit.Colors.Muted, TextWrapped = true, TextSize = 13 })
			else
				local ready = true
				for _, entry in ipairs(t.cost) do
					ready = ready and Game.Count(entry[1]) >= entry[2]
				end
				Kit.Button(side, "Badaj", function()
					local r = Game.Call("ResearchStart", { id = t.id })
					if r then
						reply = r
						Game.SyncTime(r.serverTime)
						render()
					end
				end, { Size = UDim2.fromOffset(120, 34), TextSize = 15, BackgroundColor3 = ready and Kit.Colors.Button or Color3.fromRGB(78, 84, 96) })
			end
		end
	end

	table.insert(connections, Game.Changed.Event:Connect(render))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local now = Game.Now()
		for _, entry in ipairs(timers) do
			local left = entry.t.finishesAt - now
			entry.label.Text = left > 0 and ("Bada się: " .. clock(left)) or "Gotowe"
			if left <= 0 and not asked then
				asked = true
				task.spawn(function()
					local r = Game.Call("ResearchGet")
					if r then
						reply = r
						Game.SyncTime(r.serverTime)
						Game.Toast:Fire("Zbadane: " .. entry.t.name)
						render()
					end
					asked = false
				end)
			end
		end
	end))
	render()
	return window
end

return ResearchWindow
