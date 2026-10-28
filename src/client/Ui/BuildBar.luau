-- Build mode (key B or the button): a bar of what can be put on the build grid, the grid's lines on
-- the player's own plot, a ghost of the thing under the pointer, R to turn it and a click to build.
-- A drag lays a line of belts that turns where the drag turns. The pick-up tool takes back what is
-- clicked. The server checks it all again.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Logistics = require(Shared.Logistics)
local Models = require(Shared.Models)
local PlotLayout = require(Shared.PlotLayout)
local Assemble = require(Shared.Assemble)
local Kit = require(script.Parent.Kit)
local Game = require(script.Parent.Parent.Game)

local BuildBar = {}

local Pickup = "pickup"
local Buildable = { Items.Belt, Items.Inserter, Items.WoodenChest, Items.Furnace, Items.Sapling }
local ModelOf = {
	[Items.Sapling] = function()
		return Models.Sapling(1)
	end,
	[Items.Belt] = Models.Belt,
	[Items.Inserter] = Models.Inserter,
	[Items.WoodenChest] = Models.WoodenChest,
	[Items.Furnace] = function()
		return Models.Furnace(true)
	end,
}

local player = Players.LocalPlayer
local active = false
local selected = Items.Belt
local rot = 1
local ghost, ghostKey, highlight
local bar, buttons = nil, {}
local holding = false
local lastPlaced = nil
local pointer = nil -- the last screen point touched, for touch screens
local lines = nil -- the grid's lines, while building
local queue, working = {}, false -- what to send to the server, one after another
local dragBelt = nil -- { id, x, z, rot } of the belt the current drag laid last

local function myPlot()
	local plots = workspace:FindFirstChild("Plots")
	for _, plot in ipairs(plots and plots:GetChildren() or {}) do
		if plot:GetAttribute("Owner") == player.UserId then
			return plot, plot:GetAttribute("Index")
		end
	end
	return nil
end

local function ray()
	local camera = workspace.CurrentCamera
	if pointer then
		return camera:ScreenPointToRay(pointer.X, pointer.Y)
	end
	local mouse = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end

-- The tile under the pointer for something `size` tiles across, and where it would stand.
local function aim(size)
	local _, index = myPlot()
	if index == nil then
		return nil
	end
	local r = ray()
	if r.Direction.Y >= -0.01 then
		return nil
	end
	local point = r.Origin + r.Direction * (-r.Origin.Y / r.Direction.Y)
	local cx, cz = PlotLayout.Center(index)
	local half = (size - 1) * PlotLayout.Grid.tile / 2
	local tx, tz = PlotLayout.TileAt(point.X - cx - half, point.Z - cz - half)
	local ox, oz = PlotLayout.TileCenter(tx, tz, size)
	local inside = tx >= 0 and tz >= 0 and tx + size <= PlotLayout.Grid.width and tz + size <= PlotLayout.Grid.depth
	for dx = 0, size - 1 do
		for dz = 0, size - 1 do
			if PlotLayout.Blocked(tx + dx, tz + dz) then
				inside = false
			end
		end
	end
	return tx, tz, CFrame.new(cx + ox, 0, cz + oz) * CFrame.Angles(0, PlotLayout.Yaw(rot), 0), inside
end

-- The thing on the player's grid under the pointer, if any.
local function aimedObject()
	local r = ray()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, ghost }
	local hit = workspace:Raycast(r.Origin, r.Direction * 400, params)
	local node = hit and hit.Instance
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("GridId") then
			if node:GetAttribute("Owner") == player.UserId then
				return node
			end
			return nil
		end
		node = node.Parent
	end
	return nil
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
	end
	ghost, ghostKey = nil, nil
end

local function setHighlight(target, color, fill)
	if highlight == nil then
		highlight = Instance.new("Highlight")
		highlight.OutlineTransparency = 0.1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	end
	highlight.FillTransparency = fill or 0.6
	highlight.Adornee = target
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.Parent = target and workspace or nil
end

local function refreshBar()
	for item, button in pairs(buttons) do
		local on = item == selected
		button.BackgroundColor3 = on and Kit.Colors.Button or (item == Pickup and Kit.Colors.Danger or Kit.Colors.ButtonAlt)
		if item ~= Pickup then
			button.Text = Items.Name(item) .. " (" .. Game.Count(item) .. ")"
		end
	end
end

local function work()
	if working then
		return
	end
	working = true
	while #queue > 0 do
		local job = table.remove(queue, 1)
		job()
	end
	working = false
end

local function enqueue(job)
	table.insert(queue, job)
	task.spawn(work)
end

-- The rotation that faces from tile a to the next tile b, or nil when they are not neighbours.
local function facing(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	if dx == 0 and dz == 1 then
		return 0
	elseif dx == 1 and dz == 0 then
		return 1
	elseif dx == 0 and dz == -1 then
		return 2
	elseif dx == -1 and dz == 0 then
		return 3
	end
	return nil
end

local function place(dragging)
	if selected == Pickup then
		local target = aimedObject()
		if target then
			Game.Call("GridPickup", { id = target:GetAttribute("GridId") })
		end
		return
	end
	local size = Logistics.Sizes[selected]
	local tx, tz, _, inside = aim(size)
	if tx == nil or not inside then
		return
	end
	local key = tx .. "," .. tz
	if key == lastPlaced then
		return
	end
	lastPlaced = key
	if Game.Count(selected) < 1 then
		Game.Toast:Fire("Nie masz: " .. Items.Name(selected) .. ". Zrób to na stole warsztatowym albo kup u handlarza.")
		holding = false
		return
	end
	local item = selected
	if item ~= Items.Belt then
		local r = rot
		enqueue(function()
			Game.Call("GridPlace", { item = item, x = tx, z = tz, rot = r })
		end)
		return
	end
	if not dragging then
		dragBelt = nil
	end
	enqueue(function()
		-- Dragged on from the belt laid last: both face the way the drag goes, so it turns there.
		local r = rot
		local last = dragBelt
		local way = last and facing(last.x, last.z, tx, tz)
		if way then
			r = way
			rot = way
			if last.rot ~= way then
				Game.Call("GridRotate", { id = last.id, rot = way })
			end
		end
		local reply = Game.Call("GridPlace", { item = item, x = tx, z = tz, rot = r })
		dragBelt = reply and { id = reply.id, x = tx, z = tz, rot = r } or nil
	end)
end

-- Thin lines on the tile edges of the player's grid, seen only by them while they build.
local function showLines(show)
	if lines then
		lines:Destroy()
		lines = nil
	end
	local _, index = myPlot()
	if not show or index == nil then
		return
	end
	local g = PlotLayout.Grid
	local cx, cz = PlotLayout.Center(index)
	lines = Instance.new("Folder")
	lines.Name = "BuildGridLines"
	local function line(size, position)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(255, 255, 255)
		part.Transparency = 0.55
		part.Size = size
		part.Position = position
		part.Parent = lines
	end
	local w, d = g.width * g.tile, g.depth * g.tile
	for i = 0, g.width do
		line(Vector3.new(0.12, 0.05, d), Vector3.new(cx + g.x + i * g.tile, 0.08, cz + g.z + d / 2))
	end
	for i = 0, g.depth do
		line(Vector3.new(w, 0.05, 0.12), Vector3.new(cx + g.x + w / 2, 0.08, cz + g.z + i * g.tile))
	end
	lines.Parent = workspace
end

local function choose(item)
	selected = item
	clearGhost()
	refreshBar()
end

function BuildBar.Toggle()
	active = not active
	bar.Visible = active
	showLines(active)
	if not active then
		clearGhost()
		setHighlight(nil)
		holding = false
	else
		refreshBar()
	end
end

function BuildBar.Active()
	return active
end

function BuildBar.Mount(screen)
	bar = Kit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(900, 86),
		BackgroundColor3 = Kit.Colors.Panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = screen,
	}, { Kit.Corner(10), Kit.New("UISizeConstraint", { MaxSize = Vector2.new(900, 86) }) })
	local row = Kit.New("Frame", {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 40),
		BackgroundTransparency = 1,
		Parent = bar,
	}, { Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) })
	for i, item in ipairs(Buildable) do
		buttons[item] = Kit.Button(row, "", function()
			choose(item)
		end, { Size = UDim2.fromOffset(130, 40), LayoutOrder = i, TextWrapped = true })
	end
	buttons[Pickup] = Kit.Button(row, "Rozbiórka [X]", function()
		choose(Pickup)
	end, { Size = UDim2.fromOffset(110, 40), LayoutOrder = 10 })
	Kit.Button(row, "Obróć [R]", function()
		rot = (rot + 1) % 4
	end, { Size = UDim2.fromOffset(80, 40), LayoutOrder = 11, BackgroundColor3 = Kit.Colors.ButtonAlt })
	Kit.Label(bar, "Kliknij, by postawić. Przeciągnij, by ułożyć taśmę (skręca razem z ruchem). 1–5 wybór, R obrót, X rozbiórka, B koniec.", {
		Position = UDim2.fromOffset(12, 54),
		Size = UDim2.new(1, -24, 0, 24),
		TextSize = 14,
		TextColor3 = Kit.Colors.Muted,
	})
	Game.Changed.Event:Connect(refreshBar)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			BuildBar.Toggle()
			return
		end
		if not active then
			return
		end
		local number = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5 }
		if number[input.KeyCode] then
			choose(Buildable[number[input.KeyCode]])
		elseif input.KeyCode == Enum.KeyCode.X then
			choose(Pickup)
		elseif input.KeyCode == Enum.KeyCode.R then
			rot = (rot + 1) % 4
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pointer = input.UserInputType == Enum.UserInputType.Touch and input.Position or nil
			holding = true
			lastPlaced = nil
			place()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and holding then
			pointer = input.Position
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = false
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not active then
			return
		end
		if selected == Pickup then
			setHighlight(aimedObject(), Color3.fromRGB(230, 80, 60))
			return
		end
		local size = Logistics.Sizes[selected]
		local tx, _, cframe, inside = aim(size)
		if tx == nil then
			clearGhost()
			setHighlight(nil)
			return
		end
		if ghostKey ~= selected then
			clearGhost()
			local spec = ModelOf[selected]()
			for _, part in ipairs(Models.BuildMarker(selected, PlotLayout.Grid.tile)) do
				table.insert(spec, part)
			end
			ghost = Assemble.Model(workspace, "BuildGhost", spec, cframe, true)
			ghostKey = selected
		end
		ghost:PivotTo(cframe)
		-- Mostly an outline, so the model and its arrow stay readable.
		setHighlight(ghost, inside and Color3.fromRGB(90, 220, 120) or Color3.fromRGB(230, 80, 60), 0.9)
		-- A drag lays a line of belts.
		if holding and selected == Items.Belt then
			place(true)
		end
	end)
end

return BuildBar
