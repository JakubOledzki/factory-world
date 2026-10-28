-- A grid of item tiles like the 2D game's (InventoryGrid on main): each tile shows one kind with
-- its count in the corner. A click or tap on a tile calls `onClick` (Shift-click for half the stack);
-- dragging an item onto another tile of the same grid calls `onMove`. Hovering names the item in
-- the grid's info line. It only draws and reports; the windows ask the server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Kit = require(script.Parent.Kit)

local ItemGrid = {}

-- A press that moves less than this many pixels is a click, not a drag.
local ClickSlop = 8

local function rgb(c, k)
	k = k or 1
	return Color3.fromRGB(math.min(255, c[1] * k), math.min(255, c[2] * k), math.min(255, c[3] * k))
end

local function shape(parent, props, radius)
	props.BorderSizePixel = 0
	props.Parent = parent
	local frame = Kit.New("Frame", props)
	if radius then
		Kit.New("UICorner", { CornerRadius = radius, Parent = frame })
	end
	return frame
end

-- Draws a small picture of `item` filling `parent`, made of frames in the item's colour: a lump
-- of ore, crushed ore, an ingot, a tool, a building, or a block of material.
function ItemGrid.Icon(parent, item)
	local c = Items.Colors[item] or { 200, 200, 200 }
	local round = UDim.new(0.5, 0)
	if string.sub(item, 1, 8) == "crushed_" then
		for _, p in ipairs({ { 0.3, 0.62 }, { 0.62, 0.66 }, { 0.46, 0.4 }, { 0.72, 0.38 }, { 0.26, 0.34 } }) do
			shape(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(p[1], p[2]), Size = UDim2.fromScale(0.3, 0.3), BackgroundColor3 = rgb(c) }, round)
		end
	elseif string.sub(item, -4) == "_ore" or item == "coal" or item == "stone" then
		local lump = shape(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.78, 0.66), BackgroundColor3 = item == "coal" and rgb(c) or Color3.fromRGB(128, 124, 118) }, UDim.new(0.4, 0))
		if item ~= "stone" and item ~= "coal" then
			for _, p in ipairs({ { 0.3, 0.35 }, { 0.62, 0.55 }, { 0.42, 0.72 } }) do
				shape(lump, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(p[1], p[2]), Size = UDim2.fromScale(0.24, 0.28), BackgroundColor3 = rgb(c, 1.1) }, round)
			end
		end
	elseif string.sub(item, -6) == "_ingot" then
		local bar = shape(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromScale(0.82, 0.4), BackgroundColor3 = rgb(c, 0.8) }, UDim.new(0.15, 0))
		shape(bar, { Position = UDim2.fromScale(0.1, 0), Size = UDim2.fromScale(0.8, 0.45), BackgroundColor3 = rgb(c, 1.15) }, UDim.new(0.2, 0))
	elseif string.sub(item, 1, 5) == "tool_" then
		local handle = shape(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.14, 0.8), BackgroundColor3 = Color3.fromRGB(140, 96, 60), Rotation = 35 }, UDim.new(0.3, 0))
		shape(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.62, 0.32), Size = UDim2.fromScale(0.6, 0.18), BackgroundColor3 = item == "tool_axe" and Color3.fromRGB(170, 176, 186) or rgb(c), Rotation = 35 }, UDim.new(0.3, 0))
		handle.ZIndex = handle.ZIndex + 1
	elseif string.sub(item, 1, 10) == "furniture_" or string.sub(item, 1, 10) == "logistics_" or string.sub(item, 1, 8) == "storage_" then
		local body = shape(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.8, 0.7), BackgroundColor3 = rgb(c) }, UDim.new(0.12, 0))
		shape(body, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromScale(0.5, 0.4), BackgroundColor3 = rgb(c, 0.6) }, UDim.new(0.15, 0))
		shape(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromScale(0.9, 0.12), BackgroundColor3 = rgb(c, 0.75) }, UDim.new(0.3, 0))
	else
		local block = shape(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.72, 0.72), BackgroundColor3 = rgb(c) }, UDim.new(0.18, 0))
		Kit.New("UIGradient", {
			Color = ColorSequence.new(rgb(c, 1.2), rgb(c, 0.75)),
			Rotation = 60,
			Parent = block,
		})
	end
end

-- A grid in `parent`. `opts`: columns, tile (pixels), onClick(index, entry, half),
-- onMove(from, to, entry) (dragging; leave out for a grid that cannot be rearranged), hint (text
-- after the name in the info line, or nil). Returns an object with Set(entries): a list of
-- { item, quantity } or false for an empty tile.
function ItemGrid.New(parent, opts)
	local columns = opts.columns or 5
	local size = opts.tile or 54
	local holder = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, columns * (size + 4), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	local tiles = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = holder,
	}, {
		Kit.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(size, size),
			CellPadding = UDim2.fromOffset(4, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local info = Kit.Label(parent, " ", { TextColor3 = Kit.Colors.Muted, TextSize = 14 })
	local grid = { entries = {} }
	local press -- { index, at = Vector2, ghost }

	local function describe(entry)
		if not entry then
			return " "
		end
		local text = Items.Name(entry.item) .. " × " .. entry.quantity
		local extra = opts.hint and opts.hint(entry)
		return extra and (text .. "   " .. extra) or text
	end

	function grid.Set(entries)
		grid.entries = entries
		for _, child in ipairs(tiles:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, entry in ipairs(entries) do
			local tile = Kit.New("TextButton", {
				Text = "",
				AutoButtonColor = entry ~= false,
				BackgroundColor3 = Color3.fromRGB(26, 29, 36),
				LayoutOrder = index,
				Parent = tiles,
			}, { Kit.Corner(6), Kit.New("UIStroke", { Color = Color3.fromRGB(70, 78, 94), Thickness = 1 }) })
			tile:SetAttribute("GridTile", index)
			if entry then
				local art = Kit.New("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromScale(0.08, 0.06),
					Size = UDim2.fromScale(0.84, 0.84),
					Parent = tile,
				})
				ItemGrid.Icon(art, entry.item)
				Kit.New("TextLabel", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -3, 1, -1),
					Size = UDim2.fromOffset(size - 6, 16),
					Font = Enum.Font.GothamBold,
					TextSize = 13,
					TextColor3 = Color3.new(1, 1, 1),
					TextStrokeTransparency = 0.2,
					TextXAlignment = Enum.TextXAlignment.Right,
					Text = tostring(entry.quantity),
					ZIndex = 5,
					Parent = tile,
				})
				tile.MouseEnter:Connect(function()
					info.Text = describe(entry)
				end)
				tile.MouseLeave:Connect(function()
					info.Text = " "
				end)
				tile.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						press = { index = index, entry = entry, at = Vector2.new(input.Position.X, input.Position.Y) }
						info.Text = describe(entry)
					end
				end)
			end
		end
	end

	-- The tile of this grid under a screen point, if any.
	local function tileAt(x, y)
		local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
		for _, object in ipairs(gui:GetGuiObjectsAtPosition(x, y)) do
			if object:IsDescendantOf(tiles) then
				local node = object
				while node and node ~= tiles do
					if node:GetAttribute("GridTile") then
						return node:GetAttribute("GridTile")
					end
					node = node.Parent
				end
			end
		end
		return nil
	end

	local connections = {}
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if press == nil or opts.onMove == nil then
			return
		end
		local mouse = UserInputService:GetMouseLocation()
		local inset = game:GetService("GuiService"):GetGuiInset()
		local at = mouse - inset
		if press.ghost == nil and (at - press.at).Magnitude > ClickSlop then
			press.ghost = Kit.New("Frame", {
				BackgroundTransparency = 0.3,
				BackgroundColor3 = Color3.fromRGB(26, 29, 36),
				Size = UDim2.fromOffset(size, size),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 50,
				Parent = holder:FindFirstAncestorOfClass("ScreenGui"),
			}, { Kit.Corner(6) })
			ItemGrid.Icon(press.ghost, press.entry.item)
		end
		if press.ghost then
			press.ghost.Position = UDim2.fromOffset(at.X, at.Y)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if press == nil then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local p = press
		press = nil
		local at = Vector2.new(input.Position.X, input.Position.Y)
		if p.ghost then
			p.ghost:Destroy()
		end
		local moved = (at - p.at).Magnitude > ClickSlop
		if moved and opts.onMove then
			local target = tileAt(at.X, at.Y)
			if target and target ~= p.index then
				opts.onMove(p.index, target, p.entry)
			end
		elseif opts.onClick then
			local half = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			opts.onClick(p.index, p.entry, half)
		end
	end))
	holder.Destroying:Connect(function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)
	return grid
end

-- The player's inventory as tiles (Game.Slots), at least `tiles` of them and whole rows of
-- `columns`: a list for ItemGrid.Set.
function ItemGrid.Inventory(game, tiles, columns)
	local entries = {}
	for i, item in ipairs(game.Slots) do
		local quantity = item ~= "" and game.Count(item) or 0
		entries[i] = quantity > 0 and { item = item, quantity = quantity } or false
	end
	local count = math.max(tiles, #entries)
	count = math.ceil(count / columns) * columns
	for i = #entries + 1, count do
		entries[i] = false
	end
	return entries
end

return ItemGrid
