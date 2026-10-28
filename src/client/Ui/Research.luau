-- The research window: every technology with what it costs, what it unlocks and how far it has
-- got. Starting one takes its cost from the inventory at once.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Research = require(Shared.Research)
local Kit = require(script.Parent.Kit)
local Game = require(script.Parent.Parent.Game)

local ResearchWindow = {}

local function list(entries)
	local parts = {}
	for _, entry in ipairs(entries) do
		local mark = Game.Count(entry[1]) >= entry[2] and "" or " ✗"
		table.insert(parts, entry[2] .. " × " .. Items.Name(entry[1]) .. mark)
	end
	return table.concat(parts, ", ")
end

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
			local row = Kit.Row(body, 96)
			Kit.Swatch(row, Items.Colors[t.unlocks[1]], 30)
			local text = Kit.Label(row, "", { Size = UDim2.new(0, 400, 1, 0), TextWrapped = true, RichText = true, TextSize = 14 })
			text.Text = "<b>" .. t.name .. "</b>  (" .. clock(t.time) .. ")\n" .. t.description
				.. '\n<font color="#a0a6b2">Koszt: ' .. list(t.cost) .. "</font>"
				.. '\n<font color="#a0a6b2">Odblokowuje: ' .. names(t.unlocks) .. "</font>"
			if t.status == "done" then
				Kit.Label(row, "Zbadane", { Size = UDim2.new(0, 110, 1, 0), Font = Enum.Font.GothamBold, TextColor3 = Kit.Colors.Money })
			elseif t.status == "active" then
				local label = Kit.Label(row, "", { Size = UDim2.new(0, 110, 1, 0), Font = Enum.Font.GothamBold })
				table.insert(timers, { label = label, t = t })
			elseif t.status == "locked" then
				local needs = {}
				for _, need in ipairs(t.requires) do
					table.insert(needs, Research.ById[need] and Research.ById[need].name or need)
				end
				Kit.Label(row, "Najpierw: " .. table.concat(needs, ", "), { Size = UDim2.new(0, 110, 1, 0), TextColor3 = Kit.Colors.Muted, TextWrapped = true, TextSize = 13 })
			else
				Kit.Button(row, "Badaj", function()
					local r = Game.Call("ResearchStart", { id = t.id })
					if r then
						reply = r
						Game.SyncTime(r.serverTime)
						render()
					end
				end, { Size = UDim2.fromOffset(100, 32) })
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
