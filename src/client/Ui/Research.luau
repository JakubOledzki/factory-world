-- The research window: the technology tree (Shared.Research), roots on the left and what they lead
-- to on the right, joined by lines that light up once the requirement is done. Clicking a
-- technology shows its card below: what it costs (tiles, red when short), what it unlocks and the
-- button to start it. Starting one takes its cost from the inventory at once.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Research = require(Shared.Research)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local ResearchWindow = {}

-- A node of the tree and the gaps between them, in pixels.
local NodeWidth, NodeHeight = 220, 74
local ColumnGap, RowGap = 86, 20

local StatusColors = {
	done = Color3.fromRGB(110, 200, 110),
	active = Color3.fromRGB(255, 205, 90),
	available = Color3.fromRGB(110, 160, 240),
	locked = Color3.fromRGB(90, 96, 110),
}

local function clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 60 then
		return math.floor(seconds / 60) .. " min " .. (seconds % 60) .. " s"
	end
	return seconds .. " s"
end

-- Where each technology stands: its column is its depth, its row the middle of its requirements'
-- rows, pushed down where another stands already. Returns { [id] = { column, row } } and the rows used.
local function layout(technologies)
	local spots, columns, rows = {}, {}, 0
	for _, t in ipairs(technologies) do
		local column = Research.Depth(t.id)
		local row = 0
		if #t.requires > 0 then
			local sum = 0
			for _, need in ipairs(t.requires) do
				sum = sum + spots[need].row
			end
			row = sum / #t.requires
		end
		local taken = columns[column] or {}
		columns[column] = taken
		local moved = true
		while moved do
			moved = false
			for _, other in ipairs(taken) do
				if math.abs(other - row) < 1 then
					row = other + 1
					moved = true
				end
			end
		end
		table.insert(taken, row)
		spots[t.id] = { column = column, row = row }
		rows = math.max(rows, row + 1)
	end
	return spots, rows
end

local function line(parent, x1, y1, x2, y2, color)
	local horizontal = y1 == y2
	return Kit.New("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(math.min(x1, x2) - (horizontal and 0 or 1.5), math.min(y1, y2) - (horizontal and 1.5 or 0)),
		Size = UDim2.fromOffset(horizontal and math.abs(x2 - x1) or 3, horizontal and 3 or math.abs(y2 - y1) + 3),
		Parent = parent,
	})
end

function ResearchWindow.Open(screen)
	local reply = Game.Call("ResearchGet")
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connections = {}
	local window, body = Kit.Window(screen, "Drzewko badań", 900, 640, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)
	local timers = {}
	local asked = false
	local selected = nil

	local function byId(id)
		for _, t in ipairs(reply.technologies) do
			if t.id == id then
				return t
			end
		end
		return nil
	end

	local function statusText(t)
		if t.status == "done" then
			return "✓ Zbadane"
		elseif t.status == "active" then
			return "Bada się…"
		elseif t.status == "locked" then
			return "🔒 Zablokowane"
		end
		return "Dostępne · " .. clock(t.time)
	end

	local render

	local function card(t)
		local panel = Kit.New("Frame", {
			Size = UDim2.new(1, -8, 0, 196),
			BackgroundColor3 = Kit.Colors.Row,
			LayoutOrder = 3,
			Parent = body,
		}, { Kit.Corner(10), Kit.New("UIStroke", { Color = StatusColors[t.status], Thickness = 1.5, Transparency = 0.3 }) })
		local icon = ItemGrid.Slot(panel, { size = 84 })
		icon.frame.Position = UDim2.fromOffset(14, 14)
		icon.Set(t.unlocks[1], "", t.status == "locked")
		local text = Kit.Label(panel, "", {
			Position = UDim2.fromOffset(112, 10),
			Size = UDim2.new(1, -290, 0, 56),
			TextWrapped = true,
			RichText = true,
			TextSize = 15,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		text.Text = "<font size=\"20\"><b>" .. t.name .. "</b></font>   <font color=\"#a0a6b2\">" .. clock(t.time) .. "</font>\n" .. t.description
		Kit.Label(panel, "Koszt", { Position = UDim2.fromOffset(112, 68), Size = UDim2.fromOffset(200, 16), TextSize = 12, TextColor3 = Kit.Colors.Muted })
		local cost = Recipes.Ingredients(panel, t.cost, 44)
		cost.Position = UDim2.fromOffset(112, 86)
		cost.Size = UDim2.new(0.5, -90, 0, 62)
		Kit.Label(panel, "Odblokowuje", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -176, 0, 68), Size = UDim2.fromOffset(240, 16),
			TextSize = 12, TextColor3 = Kit.Colors.Muted,
		})
		local unlocks = Kit.New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -176, 0, 86),
			Size = UDim2.fromOffset(240, 62),
			Parent = panel,
		}, { Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })
		for _, item in ipairs(t.unlocks) do
			local slot = ItemGrid.Slot(unlocks, { size = 44, caption = "" })
			slot.Set(item, "")
			slot.button.MouseEnter:Connect(function()
				slot.caption.Text = Items.Name(item)
			end)
			slot.button.MouseLeave:Connect(function()
				slot.caption.Text = ""
			end)
		end
		local side = Kit.New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 14),
			Size = UDim2.fromOffset(150, 60),
			Parent = panel,
		})
		if t.status == "done" then
			Kit.Label(side, "✓ Zbadane", { Size = UDim2.new(1, 0, 0, 32), Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = StatusColors.done })
		elseif t.status == "active" then
			local label = Kit.Label(side, "", { Size = UDim2.new(1, 0, 0, 40), Font = Enum.Font.GothamBold, TextWrapped = true, TextSize = 15, TextColor3 = StatusColors.active })
			table.insert(timers, { label = label, t = t })
		elseif t.status == "locked" then
			local needs = {}
			for _, need in ipairs(t.requires) do
				local n = byId(need)
				if n and n.status ~= "done" then
					table.insert(needs, n.name)
				end
			end
			Kit.Label(side, "🔒 Najpierw: " .. table.concat(needs, ", "), {
				Size = UDim2.new(1, 0, 1, 0), TextColor3 = Kit.Colors.Muted, TextWrapped = true, TextSize = 13,
				TextYAlignment = Enum.TextYAlignment.Top,
			})
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
			end, {
				Size = UDim2.fromOffset(150, 40), TextSize = 17,
				BackgroundColor3 = ready and Kit.Colors.Button or Kit.Colors.Disabled,
			})
		end
	end

	function render()
		Kit.Clear(body)
		timers = {}
		Kit.Label(body, "Badanie zużywa surowce od razu i trwa swój czas, także gdy cię nie ma. Bada się jedno naraz; kliknij technologię, aby zobaczyć szczegóły.", {
			TextColor3 = Kit.Colors.Muted, TextWrapped = true, TextSize = 14, Size = UDim2.new(1, -8, 0, 36), LayoutOrder = 1,
		})
		local spots, rows = layout(reply.technologies)
		local tree = Kit.New("Frame", {
			Size = UDim2.new(1, -8, 0, rows * (NodeHeight + RowGap) + RowGap),
			BackgroundColor3 = Color3.fromRGB(26, 29, 36),
			LayoutOrder = 2,
			Parent = body,
		}, { Kit.Corner(10) })
		local function corner(id)
			local s = spots[id]
			return 18 + s.column * (NodeWidth + ColumnGap), RowGap + s.row * (NodeHeight + RowGap)
		end
		-- Lines first, so the nodes cover their ends.
		for _, t in ipairs(reply.technologies) do
			local x2, y2 = corner(t.id)
			y2 = y2 + NodeHeight / 2
			for _, need in ipairs(t.requires) do
				local x1, y1 = corner(need)
				x1, y1 = x1 + NodeWidth, y1 + NodeHeight / 2
				local n = byId(need)
				local color = (n and n.status == "done") and StatusColors.done or StatusColors.locked
				local mid = x1 + ColumnGap / 2
				line(tree, x1, y1, mid, y1, color)
				line(tree, mid, y1, mid, y2, color)
				line(tree, mid, y2, x2, y2, color)
			end
		end
		if selected == nil then
			for _, t in ipairs(reply.technologies) do
				if selected == nil and (t.status == "active" or t.status == "available") then
					selected = t.id
				end
			end
			selected = selected or reply.technologies[1].id
		end
		for _, t in ipairs(reply.technologies) do
			local x, y = corner(t.id)
			local chosen = t.id == selected
			local node = Kit.New("Frame", {
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(NodeWidth, NodeHeight),
				BackgroundColor3 = chosen and Color3.fromRGB(62, 70, 88) or Kit.Colors.Row,
				Parent = tree,
			}, {
				Kit.Corner(10),
				Kit.New("UIStroke", {
					Color = chosen and Kit.Colors.Money or StatusColors[t.status],
					Thickness = chosen and 2.5 or 1.5,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			})
			local icon = ItemGrid.Slot(node, { size = 56 })
			icon.frame.Position = UDim2.fromOffset(9, 9)
			icon.Set(t.unlocks[1], "", t.status == "locked")
			Kit.Label(node, t.name, {
				Position = UDim2.fromOffset(74, 10),
				Size = UDim2.new(1, -80, 0, 24),
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			local status = Kit.Label(node, statusText(t), {
				Position = UDim2.fromOffset(74, 38),
				Size = UDim2.new(1, -80, 0, 20),
				TextSize = 13,
				TextColor3 = StatusColors[t.status],
			})
			if t.status == "active" then
				table.insert(timers, { label = status, t = t })
			end
			-- A see-through button over the whole node, above the icon's own button.
			Kit.New("TextButton", {
				Text = "",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 10,
				Parent = node,
			}).Activated:Connect(function()
				selected = t.id
				render()
			end)
		end
		card(byId(selected))
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
