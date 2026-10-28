-- A grid of item tiles like the 2D game's (InventoryGrid on main): each tile shows one kind, as a
-- small 3D picture (Shared.Icons), with its count in the corner. A click or tap on a tile calls `onClick` (Shift-click for half the stack);
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

local Assemble = require(Shared.Assemble)
local Icons = require(Shared.Icons)

-- Each item's picture is built once, then copied into each tile that shows it.
local templates = {}
local store = Instance.new("Folder")
store.Name = "IconTemplates"

local function template(item)
	if templates[item] == nil then
		local model = Assemble.Model(store, item, Icons.Model(item), CFrame.new(), false)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Light") or d:IsA("ParticleEmitter") then
				d:Destroy()
			elseif d:IsA("BasePart") and d.Transparency >= 1 then
				d:Destroy()
			end
		end
		local cframe, size = model:GetBoundingBox()
		local corners = {}
		for _, sx in ipairs({ -0.5, 0.5 }) do
			for _, sy in ipairs({ -0.5, 0.5 }) do
				for _, sz in ipairs({ -0.5, 0.5 }) do
					table.insert(corners, cframe * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz))
				end
			end
		end
		templates[item] = { model = model, center = cframe.Position, corners = corners }
	end
	return templates[item]
end

-- Draws a small 3D picture of `item` filling `parent` (Shared.Icons), lit like a sunny day.
function ItemGrid.Icon(parent, item)
	local t = template(item)
	local view = Kit.New("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 150, 160),
		LightColor = Color3.fromRGB(255, 248, 235),
		LightDirection = Vector3.new(-0.6, -1, 0.4),
		Parent = parent,
	})
	local model = t.model:Clone()
	model.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local d = Icons.ViewDirection
	local direction = Vector3.new(d[1], d[2], d[3]).Unit
	-- Near enough that the box around the picture just fills the tile as the camera sees it.
	local right = direction:Cross(Vector3.new(0, 1, 0)).Unit
	local up = right:Cross(direction).Unit
	local slope = math.tan(math.rad(camera.FieldOfView / 2)) * 0.94
	local distance = 0
	for _, corner in ipairs(t.corners) do
		local offset = corner - t.center
		local side = math.max(math.abs(offset:Dot(right)), math.abs(offset:Dot(up)))
		distance = math.max(distance, offset:Dot(direction) + side / slope)
	end
	camera.CFrame = CFrame.lookAt(t.center + direction * distance, t.center)
	camera.Parent = view
	view.CurrentCamera = camera
	return view
end

-- One tile like the grid's, for windows that show single items (a recipe, what is in a machine).
-- `opts`: size (pixels), caption (text under the tile, or nil), captionColor, layoutOrder, onClick.
-- Returns { frame, button, caption, Set(item, text, dim) }: Set shows `item`'s picture (false or nil
-- for an empty tile) with `text` in the corner, faded when `dim`; the picture is only rebuilt when
-- the item changes, so Set can run every frame.
function ItemGrid.Slot(parent, opts)
	opts = opts or {}
	local size = opts.size or 54
	local frame = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size + (opts.caption and 18 or 0)),
		LayoutOrder = opts.layoutOrder or 0,
		Parent = parent,
	})
	local button = Kit.New("TextButton", {
		Text = "",
		AutoButtonColor = opts.onClick ~= nil,
		BackgroundColor3 = Color3.fromRGB(64, 70, 84),
		Size = UDim2.fromOffset(size, size),
		Parent = frame,
	}, {
		Kit.Corner(6),
		Kit.New("UIStroke", { Color = Color3.fromRGB(96, 104, 122), Thickness = 1 }),
		-- Lighter at the top, like a recessed slot lit from above.
		Kit.New("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 160)),
			Rotation = 90,
		}),
	})
	local art = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.08, 0.06),
		Size = UDim2.fromScale(0.84, 0.84),
		Parent = button,
	})
	local count = Kit.New("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -3, 1, -1),
		Size = UDim2.fromOffset(size - 6, 16),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		ZIndex = 5,
		Parent = button,
	})
	local caption
	if opts.caption then
		caption = Kit.Label(frame, opts.caption, {
			Position = UDim2.fromOffset(-8, size + 1),
			Size = UDim2.fromOffset(size + 16, 16),
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = opts.captionColor or Kit.Colors.Muted,
		})
	end
	if opts.onClick then
		button.Activated:Connect(opts.onClick)
	end
	local slot = { frame = frame, button = button, caption = caption, stroke = button:FindFirstChildOfClass("UIStroke") }
	local shown, view
	function slot.Set(item, text, dim)
		item = item or false
		if item ~= shown then
			if view then
				view:Destroy()
				view = nil
			end
			if item then
				view = ItemGrid.Icon(art, item)
			end
			shown = item
		end
		if view then
			view.ImageTransparency = dim and 0.55 or 0
		end
		count.Text = text or ""
	end
	return slot
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
			local slot = ItemGrid.Slot(tiles, { size = size, layoutOrder = index })
			local tile = slot.button
			tile.AutoButtonColor = entry ~= false
			tile:SetAttribute("GridTile", index)
			if entry then
				slot.Set(entry.item, tostring(entry.quantity))
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
				BackgroundColor3 = Color3.fromRGB(64, 70, 84),
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
