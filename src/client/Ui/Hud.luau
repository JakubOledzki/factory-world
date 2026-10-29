-- Always on screen: the money, the buttons of the windows, the tutorial's task and messages from the game.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
local Kit = require(script.Parent.Kit)
local Game = require(script.Parent.Parent.Game)

local Hud = {}

function Hud.Mount(screen, openInventory, toggleBuild, openResearch, openMarket, openLands, openCompany, openContracts)
	local money = Kit.New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(200, 44),
		BackgroundColor3 = Kit.Colors.Panel,
		BackgroundTransparency = 0.1,
		Parent = screen,
	}, { Kit.Corner(10) })
	local moneyLabel = Kit.Label(money, Money.Format(0), {
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextColor3 = Kit.Colors.Money,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	})
	Game.Changed.Event:Connect(function()
		moneyLabel.Text = Money.Format(Game.BalanceCents)
	end)

	Kit.Button(screen, "Ekwipunek [I]", openInventory, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 68),
		Size = UDim2.fromOffset(200, 36),
		BackgroundColor3 = Kit.Colors.ButtonAlt,
	})
	Kit.Button(screen, "Budowanie [B]", toggleBuild, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 110),
		Size = UDim2.fromOffset(200, 36),
		BackgroundColor3 = Kit.Colors.ButtonAlt,
	})
	Kit.Button(screen, "Badania [T]", openResearch, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 152),
		Size = UDim2.fromOffset(200, 36),
		BackgroundColor3 = Kit.Colors.ButtonAlt,
	})
	Kit.Button(screen, "Rynek graczy [M]", openMarket, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 194),
		Size = UDim2.fromOffset(200, 36),
		BackgroundColor3 = Kit.Colors.ButtonAlt,
	})
	Kit.Button(screen, "Moje działki [L]", openLands, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 236),
		Size = UDim2.fromOffset(200, 36),
		BackgroundColor3 = Kit.Colors.ButtonAlt,
	})
	Kit.Button(screen, "Spółka [K]", openCompany, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 278),
		Size = UDim2.fromOffset(200, 36),
		BackgroundColor3 = Kit.Colors.ButtonAlt,
	})
	Kit.Button(screen, "Zlecenia [J]", openContracts, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 320),
		Size = UDim2.fromOffset(200, 36),
		BackgroundColor3 = Kit.Colors.ButtonAlt,
	})

	Hud.MountTutorial(screen)

	local toasts = Kit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(420, 200),
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		Kit.New("UIListLayout", {
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})
	Game.Toast.Event:Connect(function(text)
		local toast = Kit.New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Kit.Colors.Panel,
			BackgroundTransparency = 0.15,
			Font = Enum.Font.GothamMedium,
			TextSize = 18,
			TextColor3 = Kit.Colors.Text,
			Text = text,
			Parent = toasts,
		}, { Kit.Corner(8), Kit.New("UIPadding", {
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		}) })
		task.delay(3, function()
			toast:Destroy()
		end)
	end)
end

-- The tutorial's task on the left: what to do, how far the player got, a hint and the reward.
function Hud.MountTutorial(screen)
	local panel = Kit.New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.Colors.Panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = screen,
	}, {
		Kit.Corner(10),
		Kit.New("UIStroke", { Color = Color3.fromRGB(200, 170, 90), Thickness = 1.5 }),
		Kit.New("UIPadding", {
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10),
		}),
		Kit.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function line(order, props)
		local label = Kit.Label(panel, "", {
			LayoutOrder = order,
			TextWrapped = true,
			RichText = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
		})
		for name, value in pairs(props or {}) do
			label[name] = value
		end
		return label
	end
	local header = line(1, { TextSize = 13, TextColor3 = Color3.fromRGB(230, 200, 120), Font = Enum.Font.GothamBold })
	local title = line(2, { TextSize = 18, Font = Enum.Font.GothamBold })
	local text = line(3, { TextSize = 15 })
	local hint = line(4, { TextSize = 13, TextColor3 = Kit.Colors.Muted })
	local reward = line(5, { TextSize = 13, TextColor3 = Kit.Colors.Money })
	local skip = Kit.Button(panel, "Pomiń samouczek", function() end, {
		LayoutOrder = 6,
		Size = UDim2.fromOffset(150, 24),
		TextSize = 12,
		BackgroundColor3 = Color3.fromRGB(78, 84, 96),
	})
	-- Skipping asks once more: the first click turns the button into "Na pewno?".
	local armed = false
	skip.Activated:Connect(function()
		if not armed then
			armed = true
			skip.Text = "Na pewno? Kliknij"
			task.delay(4, function()
				armed = false
				skip.Text = "Pomiń samouczek"
			end)
			return
		end
		Game.Call("TutorialSkip")
	end)

	local function render()
		local t = Game.Tutorial
		panel.Visible = t ~= nil
		if t == nil then
			return
		end
		header.Text = "SAMOUCZEK " .. t.number .. "/" .. t.count
		title.Text = t.title
		text.Text = t.text .. (t.goal > 1 and ("  <b>" .. t.progress .. "/" .. t.goal .. "</b>") or "")
		hint.Text = t.hint
		local parts = { Money.Format(t.rewardCents) }
		for _, entry in ipairs(t.rewardItems or {}) do
			table.insert(parts, entry[2] .. " × " .. Items.Name(entry[1]))
		end
		reward.Text = "Nagroda: " .. table.concat(parts, ", ")
	end
	Game.Changed.Event:Connect(render)
	render()
end

return Hud
