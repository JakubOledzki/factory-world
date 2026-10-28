-- Always on screen: the money, the inventory button and messages from the game.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Money = require(Shared.Money)
local Kit = require(script.Parent.Kit)
local Game = require(script.Parent.Parent.Game)

local Hud = {}

function Hud.Mount(screen, openInventory)
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

return Hud
