-- Build mode (key B or the button): a bar of what can stand on the build grid, a see-through ghost
-- of it under the pointer on the player's own grid, R to turn it and a click (or a drag, for a line
-- of belts) to build; the pick-up tool takes back what is clicked. The server checks it all again.
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
local Buildable = { Items.Belt, Items.Inserter, Items.WoodenChest, Items.Furnace }
local ModelOf = {
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

local function place()
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
		Game.Toast:Fire("Nie masz: " .. Items.Name(selected) .. ". Zrób to na stole warsztatowym.")
		holding = false
		return
	end
	task.spawn(Game.Call, "GridPlace", { item = selected, x = tx, z = tz, rot = rot })
end

local function choose(item)
	selected = item
	clearGhost()
	refreshBar()
end

function BuildBar.Toggle()
	active = not active
	bar.Visible = active
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
		Size = UDim2.fromOffset(760, 86),
		BackgroundColor3 = Kit.Colors.Panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = screen,
	}, { Kit.Corner(10), Kit.New("UISizeConstraint", { MaxSize = Vector2.new(760, 86) }) })
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
		end, { Size = UDim2.fromOffset(150, 40), LayoutOrder = i, TextWrapped = true })
	end
	buttons[Pickup] = Kit.Button(row, "Rozbiórka [X]", function()
		choose(Pickup)
	end, { Size = UDim2.fromOffset(110, 40), LayoutOrder = 10 })
	Kit.Button(row, "Obróć [R]", function()
		rot = (rot + 1) % 4
	end, { Size = UDim2.fromOffset(80, 40), LayoutOrder = 11, BackgroundColor3 = Kit.Colors.ButtonAlt })
	Kit.Label(bar, "Kliknij, by postawić (przeciągnij, by ułożyć taśmę). 1–4 wybór, R obrót, X rozbiórka, B koniec.", {
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
		local number = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4 }
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
			place()
		end
	end)
end

return BuildBar
