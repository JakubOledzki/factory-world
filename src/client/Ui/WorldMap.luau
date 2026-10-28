-- The world map (key N): the land (Shared.WorldMap), the player's railway station and the ones of
-- the players on this server and of those they trade with, the player's routes and the trains on
-- their way, moving. A click on a station tells how far it is and what a train there costs, and
-- adds that player to the station's list of who to send to.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Money = require(Shared.Money)
local Rail = require(Shared.Rail)
local WorldMap = require(Shared.WorldMap)
local Kit = require(script.Parent.Kit)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local MapView = {}

local Width, Height = 840, 420
local Colors = {
	me = Color3.fromRGB(255, 214, 90),
	partner = Color3.fromRGB(140, 215, 125),
	server = Color3.fromRGB(130, 180, 255),
}

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Pixels on the map of a place in km.
local function toMap(x, y)
	return x / WorldMap.Km.width * Width, y / WorldMap.Km.height * Height
end

-- A line from a to b (pixels), the short way round east-west.
local function line(parent, ax, ay, bx, by, color, thickness, transparency)
	if bx - ax > Width / 2 then
		bx = bx - Width
	elseif ax - bx > Width / 2 then
		bx = bx + Width
	end
	local dx, dy = bx - ax, by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	return Kit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
		Size = UDim2.fromOffset(length, thickness),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = parent,
	}), bx, by
end

function MapView.Open(screen)
	local reply = Game.Call("WorldMapGet")
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connection
	local window, body = Kit.Window(screen, "Mapa świata", 880, 640, function()
		if connection then
			connection:Disconnect()
		end
	end)
	local chosen = nil
	local moving = {} -- { dot, ax, ay, bx, by, sentAt, arriveAt }

	local byId = {}
	for _, s in ipairs(reply.stations) do
		byId[s.id] = s
	end

	local render

	local function info(parent)
		local s = chosen and byId[chosen]
		local panel = Kit.New("Frame", {
			Size = UDim2.new(1, -8, 0, 76),
			BackgroundColor3 = Kit.Colors.Row,
			Parent = parent,
		}, { Kit.Corner(8), Kit.New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 6) }) })
		if s == nil then
			local me = byId[reply.me]
			local biome = WorldMap.Biomes[WorldMap.Biome(me.x, me.y)]
			Kit.Label(panel, "<b>Twoja stacja</b> stoi na terenie: " .. biome.name .. ". Kliknij stację innego gracza, aby zobaczyć, ile kosztuje pociąg.", {
				RichText = true, TextWrapped = true, TextSize = 14, Size = UDim2.new(1, -10, 0, 40),
			})
			return
		end
		local biome = WorldMap.Biomes[WorldMap.Biome(s.x, s.y)]
		local text = "<b>" .. s.name .. "</b>  ·  " .. biome.name
		if s.id ~= reply.me then
			text = text .. "  ·  " .. s.km .. " km, pociąg jedzie " .. s.trip .. " s, 100 szt. za " .. Money.Format(Rail.FeeCents(s.km, 100))
		else
			text = text .. "  ·  to Ty"
		end
		Kit.Label(panel, text, { RichText = true, TextSize = 14, Size = UDim2.new(1, -10, 0, 22) })
		if s.id ~= reply.me and s.kind ~= "partner" then
			Recipes.Action(Kit.New("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 30),
				Size = UDim2.new(1, -10, 0, 34),
				Parent = panel,
			}, { Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) }), "Dodaj do odbiorców pociągów", true, function()
				if Game.Call("StationFind", { name = s.name }) then
					s.kind = "partner"
					Game.Toast:Fire(s.name .. " jest na liście odbiorców na twojej stacji (zakładka Wyślij).")
					render()
				end
			end)
		elseif s.kind == "partner" then
			Kit.Label(panel, "Na liście odbiorców: wyślesz mu towar ze swojej stacji (zakładka Wyślij).", { Position = UDim2.fromOffset(0, 30), TextSize = 13, TextColor3 = Kit.Colors.Muted, Size = UDim2.new(1, -10, 0, 22) })
		end
	end

	function render()
		Kit.Clear(body)
		moving = {}
		local map = Kit.New("Frame", {
			Size = UDim2.fromOffset(Width, Height),
			BackgroundColor3 = rgb(WorldMap.Biomes.sea.color),
			ClipsDescendants = true,
			Parent = body,
		}, { Kit.Corner(8) })
		-- The land, row by row.
		local cw, ch = Width / WorldMap.Columns, Height / WorldMap.Rows
		for r, runs in ipairs(WorldMap.Runs()) do
			for _, run in ipairs(runs) do
				if run.biome ~= "sea" then
					Kit.New("Frame", {
						Position = UDim2.fromOffset(math.floor((run.from - 1) * cw), math.floor((r - 1) * ch)),
						Size = UDim2.fromOffset(math.ceil((run.to - run.from + 1) * cw), math.ceil(ch)),
						BackgroundColor3 = rgb(WorldMap.Biomes[run.biome].color),
						BorderSizePixel = 0,
						Parent = map,
					})
				end
			end
		end
		local me = byId[reply.me]
		local mx, my = toMap(me.x, me.y)
		-- The player's routes.
		for _, route in ipairs(reply.routes) do
			local s = byId[route.to]
			if s then
				local bx, by = toMap(s.x, s.y)
				line(map, mx, my, bx, by, Colors.me, 2, 0.35)
			end
		end
		-- Trains on their way: a line to where they go and a dot on it.
		for _, t in ipairs(reply.trains) do
			local a, b = byId[t.from], byId[t.to]
			if a and b then
				local ax, ay = toMap(a.x, a.y)
				local bx, by = toMap(b.x, b.y)
				local _, ex, ey = line(map, ax, ay, bx, by, Color3.fromRGB(40, 40, 46), 2, 0.4)
				local dot = Kit.New("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(10, 10),
					BackgroundColor3 = t.to == reply.me and Colors.partner or Colors.me,
					ZIndex = 5,
					Parent = map,
				}, { Kit.Corner(2), Kit.New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5 }) })
				table.insert(moving, { dot = dot, ax = ax, ay = ay, bx = ex, by = ey, sentAt = t.sentAt, arriveAt = t.arriveAt })
			end
		end
		-- The stations.
		for _, s in ipairs(reply.stations) do
			local x, y = toMap(s.x, s.y)
			local size = s.id == reply.me and 16 or 12
			local dot = Kit.New("TextButton", {
				Text = "",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = Colors[s.kind] or Colors.server,
				ZIndex = 6,
				Parent = map,
			}, { Kit.Corner(size), Kit.New("UIStroke", { Color = s.id == chosen and Color3.new(1, 1, 1) or Color3.new(0, 0, 0), Thickness = 2 }) })
			dot.Activated:Connect(function()
				chosen = s.id
				render()
			end)
			Kit.Label(map, s.id == reply.me and "Ty" or s.name, {
				Position = UDim2.fromOffset(x + 9, y - 9),
				Size = UDim2.fromOffset(150, 18),
				TextSize = 13,
				Font = Enum.Font.GothamBold,
				TextStrokeTransparency = 0.3,
				ZIndex = 7,
			})
		end
		info(body)
		Kit.Label(body, '<font color="#ffd65a">●</font> Ty   <font color="#8cd77d">●</font> komu wysyłasz   <font color="#82b4ff">●</font> gracze na tym serwerze   ■ pociągi w drodze', { RichText = true, TextSize = 13, TextColor3 = Kit.Colors.Muted })
	end

	connection = RunService.RenderStepped:Connect(function()
		local now = Game.Now()
		for _, m in ipairs(moving) do
			local u = math.clamp((now - m.sentAt) / math.max(1, m.arriveAt - m.sentAt), 0, 1)
			m.dot.Position = UDim2.fromOffset(m.ax + (m.bx - m.ax) * u, m.ay + (m.by - m.ay) * u)
		end
	end)
	render()
	return window
end

return MapView
