-- Small building blocks for the game's windows, made in code: one look for all of them (dark
-- panels with a warm gold accent, buttons that light up under the pointer and give when pressed,
-- windows that pop open).
local TweenService = game:GetService("TweenService")

local Kit = {}

Kit.Colors = {
	Panel = Color3.fromRGB(30, 34, 42),
	Header = Color3.fromRGB(44, 50, 62),
	Row = Color3.fromRGB(42, 47, 58),
	Text = Color3.fromRGB(238, 239, 243),
	Muted = Color3.fromRGB(160, 166, 178),
	Button = Color3.fromRGB(64, 150, 92),
	ButtonAlt = Color3.fromRGB(72, 96, 146),
	Danger = Color3.fromRGB(176, 72, 60),
	Disabled = Color3.fromRGB(78, 84, 96),
	Money = Color3.fromRGB(255, 214, 90),
	Accent = Color3.fromRGB(232, 182, 76),
	Stroke = Color3.fromRGB(78, 86, 104),
}

local quick = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function lighter(color, by)
	return color:Lerp(Color3.new(1, 1, 1), by)
end

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

-- A button with a soft top light and a dark edge; it brightens under the pointer and shrinks a
-- little while pressed. Its colour is its BackgroundColor3, which the caller may change later.
function Kit.Button(parent, text, onClick, props)
	local button = Kit.New("TextButton", {
		BackgroundColor3 = Kit.Colors.Button,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.75,
		Text = text,
		Size = UDim2.fromOffset(90, 28),
		Parent = parent,
	}, {
		Kit.Corner(7),
		Kit.New("UIStroke", {
			Color = Color3.new(0, 0, 0),
			Transparency = 0.55,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Kit.New("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 204)),
			Rotation = 90,
		}),
	})
	local scale = Kit.New("UIScale", { Parent = button })
	for name, value in pairs(props or {}) do
		button[name] = value
	end
	local base = button.BackgroundColor3
	local hovered = false
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		if not hovered then
			base = button.BackgroundColor3
		end
	end)
	button.MouseEnter:Connect(function()
		hovered = true
		button.BackgroundColor3 = lighter(base, 0.14)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		button.BackgroundColor3 = base
		scale.Scale = 1
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, quick, { Scale = 0.95 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, quick, { Scale = 1 }):Play()
	end)
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
	}, {
		Kit.Corner(12),
		Kit.New("UISizeConstraint", { MaxSize = Vector2.new(width, height) }),
		-- A little lighter at the top, like light falling on the panel.
		Kit.New("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 208, 216)),
			Rotation = 90,
		}),
	})
	Kit.New("UIStroke", { Color = Kit.Colors.Stroke, Thickness = 2, Transparency = 0.1, Parent = window })
	local header = Kit.New("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Kit.Colors.Header,
		Parent = window,
	}, {
		Kit.Corner(12),
		Kit.New("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 194, 204)),
			Rotation = 90,
		}),
	})
	-- The header's lower corners stay square where it meets the body, with a gold line under it.
	Kit.New("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Kit.Colors.Header:Lerp(Color3.new(0, 0, 0), 0.12),
		Position = UDim2.new(0, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 12),
		Parent = header,
	})
	Kit.New("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Kit.Colors.Accent,
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2),
		Parent = header,
	})
	Kit.New("Frame", {
		BackgroundColor3 = Kit.Colors.Accent,
		Position = UDim2.fromOffset(14, 13),
		Size = UDim2.fromOffset(6, 18),
		Parent = header,
	}, { Kit.Corner(3) })
	Kit.Label(header, title, {
		Font = Enum.Font.GothamBold,
		TextSize = 21,
		TextStrokeTransparency = 0.7,
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -76, 1, 0),
		ZIndex = 2,
	})
	if onClose then
		window.Destroying:Connect(onClose)
	end
	Kit.Button(header, "✕", function()
		window:Destroy()
	end, {
		BackgroundColor3 = Kit.Colors.Danger,
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(1, -40, 0, 6),
		TextSize = 16,
		ZIndex = 2,
	})
	-- Pops open: a quick grow from a little smaller.
	local pop = Kit.New("UIScale", { Scale = 0.92, Parent = window })
	TweenService:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local body = Kit.New("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 1, -68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Kit.Colors.Accent,
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
		Kit.Corner(8),
		Kit.New("UIStroke", { Color = Kit.Colors.Stroke, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
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
