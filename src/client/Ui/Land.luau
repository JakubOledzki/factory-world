-- The player's plots (key L): the ones they have, with the one shown on their place on the server
-- and a button to show another there instead, and a card for each biome they can still buy, with
-- what its mine gives and how many trees it has. The server checks and charges (Services/Plots).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Lands = require(Shared.Lands)
local Mining = require(Shared.Mining)
local Money = require(Shared.Money)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local Land = {}

-- The meadow, the home plot, as the windows show it.
local Meadow = { name = Lands.HomeName, ground = { 96, 140, 64 }, drops = Mining.Drops, text = "Twoja pierwsza działka, ze stacją kolejową." }

local function infoOf(id)
	return id == Lands.Home and Meadow or Lands.Biomes[id]
end

-- A row of the items the mine gives, each with its chance in a load.
local function drops(parent, list, position)
	local row = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Position = position,
		Size = UDim2.new(1, -130, 0, 32),
		Parent = parent,
	}, { Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
	-- Commonest first.
	for k = #list, 1, -1 do
		local drop = list[k]
		local percent = math.floor(drop[2] / 10 + 0.5)
		local entry = Kit.New("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromOffset(72, 30), LayoutOrder = #list - k, Parent = row })
		ItemGrid.Icon(Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(30, 30), Parent = entry }), drop[1])
		Kit.Label(entry, math.max(percent, 1) .. "%", { TextSize = 13, Position = UDim2.fromOffset(33, 0), Size = UDim2.fromOffset(40, 30) })
		entry.Activated:Connect(function()
			Game.Toast:Fire(Items.Name(drop[1]) .. ": " .. math.max(percent, 1) .. "% szans przy każdym kopaniu")
		end)
	end
end

-- A card of a plot: its ground's colour, name, text, what the mine gives and room for a button.
local function card(body, id, order)
	local info = infoOf(id)
	local frame = Kit.New("Frame", {
		Size = UDim2.new(1, -8, 0, 112),
		BackgroundColor3 = Kit.Colors.Row,
		LayoutOrder = order,
		Parent = body,
	}, { Kit.Corner(8) })
	Kit.New("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(92, 92),
		BackgroundColor3 = Color3.fromRGB(info.ground[1], info.ground[2], info.ground[3]),
		Parent = frame,
	}, { Kit.Corner(8), Kit.New("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.6 }) })
	Kit.Label(frame, info.name, { Font = Enum.Font.GothamBold, TextSize = 18, Position = UDim2.fromOffset(114, 8), Size = UDim2.new(1, -290, 0, 22) })
	local text = info.text
	if info.trees and info.trees > 0 then
		text = text .. " Drzew na start: " .. info.trees .. "."
	end
	Kit.Label(frame, text, {
		TextSize = 13,
		TextColor3 = Kit.Colors.Muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(114, 32),
		Size = UDim2.new(1, -290, 0, 36),
	})
	drops(frame, info.drops, UDim2.fromOffset(114, 72))
	return frame
end

local function corner(button)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -10, 0, 10)
	return button
end

function Land.Open(screen)
	local reply = Game.Call("LandList")
	if reply == nil then
		return nil
	end
	local window, body = Kit.Window(screen, "Moje działki", 640, 660)

	local function render()
		Kit.Clear(body)
		local owned = {}
		Kit.Label(body, "Na serwerze stoi jedna twoja działka naraz. Te, których nie widać, dalej pracują i po powrocie wszystko jest przeliczone.", {
			TextSize = 14, TextColor3 = Kit.Colors.Muted, TextWrapped = true, Size = UDim2.new(1, -8, 0, 36), LayoutOrder = 1,
		})
		for i, id in ipairs(reply.owned) do
			owned[id] = true
			local frame = card(body, id, 10 + i)
			if id == reply.shown then
				corner(Kit.Label(frame, "Tu stoi", { Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Recipes.Colors.Enough, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(150, 32) }))
			else
				corner(Recipes.Action(frame, "Pokaż tutaj", true, function()
					if Game.Call("LandSwitch", { to = id }) then
						window:Destroy()
					end
				end))
			end
		end
		if reply.priceCents == nil then
			Kit.Label(body, "Masz już wszystkie działki.", { TextSize = 15, LayoutOrder = 50 })
			return
		end
		local afford = Game.BalanceCents >= reply.priceCents
		Kit.Label(body, "<b>Kup nową działkę</b> za " .. Money.Format(reply.priceCents) .. " (masz " .. Money.Format(Game.BalanceCents) .. ")", {
			RichText = true, TextSize = 16, LayoutOrder = 50, Size = UDim2.new(1, -8, 0, 30),
			TextColor3 = afford and Kit.Colors.Money or Recipes.Colors.Short,
		})
		for i, id in ipairs(Lands.Order) do
			if not owned[id] then
				local frame = card(body, id, 60 + i)
				corner(Recipes.Action(frame, "Kup: " .. Lands.Biomes[id].name, afford, function()
					local r = Game.Call("LandBuy", { biome = id })
					if r then
						reply = r
						Game.Toast:Fire("Kupiłeś działkę: " .. Lands.Biomes[id].name .. ". Pokaż ją, aby na niej pracować.")
						render()
					end
				end))
			end
		end
	end

	render()
	return window
end

return Land
