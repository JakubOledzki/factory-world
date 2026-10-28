-- Small building blocks for the game's windows, made in code.
local Kit = {}

Kit.Colors = {
	Panel = Color3.fromRGB(34, 38, 46),
	Header = Color3.fromRGB(52, 58, 70),
	Row = Color3.fromRGB(44, 49, 59),
	Text = Color3.fromRGB(235, 236, 240),
	Muted = Color3.fromRGB(160, 166, 178),
	Button = Color3.fromRGB(70, 130, 90),
	ButtonAlt = Color3.fromRGB(80, 96, 130),
	Danger = Color3.fromRGB(150, 70, 60),
	Money = Color3.fromRGB(255, 214, 90),
}

function Kit.New(className, props, children)
	local instance = Instance.new(className)
	for name, value in pairs(props or {}) do
		if name ~= "Parent" then
			instance[name] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if props and props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function Kit.Corner(radius)
	return Kit.New("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function Kit.Label(parent, text, props)
	local label = Kit.New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextColor3 = Kit.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = parent,
	})
	for name, value in pairs(props or {}) do
		label[name] = value
	end
	return label
end

function Kit.Button(parent, text, onClick, props)
	local button = Kit.New("TextButton", {
		BackgroundColor3 = Kit.Colors.Button,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
		Size = UDim2.fromOffset(90, 28),
		Parent = parent,
	}, { Kit.Corner(6) })
	for name, value in pairs(props or {}) do
		button[name] = value
	end
	button.Activated:Connect(onClick)
	return button
end

-- A coloured square standing for an item's icon.
function Kit.Swatch(parent, rgb, size)
	return Kit.New("Frame", {
		BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
		Size = UDim2.fromOffset(size or 20, size or 20),
		Parent = parent,
	}, { Kit.Corner(4), Kit.New("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Transparency = 0.6 }) })
end

-- A window in the middle of the screen with a title, a close button and a scrolling body.
-- Returns the window frame and its body; `onClose` runs when the window goes, however it is closed.
function Kit.Window(screen, title, width, height, onClose)
	local window = Kit.New("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Kit.Colors.Panel,
		Parent = screen,
	}, { Kit.Corner(10), Kit.New("UISizeConstraint", { MaxSize = Vector2.new(width, height) }) })
	Kit.New("UIStroke", { Color = Color3.fromRGB(90, 98, 115), Thickness = 1.5, Parent = window })
	local header = Kit.New("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Kit.Colors.Header,
		Parent = window,
	}, { Kit.Corner(10) })
	Kit.Label(header, title, {
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -60, 1, 0),
	})
	if onClose then
		window.Destroying:Connect(onClose)
	end
	Kit.Button(header, "✕", function()
		window:Destroy()
	end, {
		BackgroundColor3 = Kit.Colors.Danger,
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, -36, 0, 5),
	})
	local body = Kit.New("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 50),
		Size = UDim2.new(1, -24, 1, -62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = window,
	}, { Kit.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	return window, body
end

-- A row in a window's body: a horizontal strip children are laid out on from the left.
function Kit.Row(body, height)
	return Kit.New("Frame", {
		Size = UDim2.new(1, -8, 0, height or 36),
		BackgroundColor3 = Kit.Colors.Row,
		Parent = body,
	}, {
		Kit.Corner(6),
		Kit.New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		Kit.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

function Kit.Clear(body)
	for _, child in ipairs(body:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

return Kit
