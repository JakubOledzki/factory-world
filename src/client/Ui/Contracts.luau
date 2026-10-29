-- Orders from NPC companies (key J or the board on the square, server Services/Contracts): three
-- of the player's own, each with who orders, how much is delivered, the reward and the time left.
-- "Oddaj" gives what the inventory has (up to what is missing); the reward comes with the last piece.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local ContractsWindow = {}

local function timeLeft(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return math.floor(seconds / 3600) .. " h " .. math.floor(seconds % 3600 / 60) .. " min"
	end
	if seconds >= 60 then
		return math.floor(seconds / 60) .. " min " .. (seconds % 60) .. " s"
	end
	return seconds .. " s"
end

function ContractsWindow.Open(screen)
	local reply = Game.Call("ContractsGet")
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connections = {}
	local window, body = Kit.Window(screen, "Zlecenia firm", 600, 480, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)
	local timers = {}
	local asked = false

	local function call(name, payload)
		local r = Game.Call(name, payload)
		if r then
			reply = r
			Game.SyncTime(r.serverTime)
		end
	end

	local function render()
		Kit.Clear(body)
		timers = {}
		Kit.Label(body, "Firmy płacą za towar więcej niż handlarz. Oddawaj z ekwipunku, także po trochu; zapłata przychodzi z ostatnią sztuką. Gdy minie termin, oddane sztuki wracają do ciebie.", {
			TextColor3 = Kit.Colors.Muted, TextWrapped = true, TextSize = 14, Size = UDim2.new(1, -8, 0, 54),
		})
		for _, o in ipairs(reply.contracts) do
			local row = Kit.New("Frame", {
				Size = UDim2.new(1, -8, 0, 92),
				BackgroundColor3 = Kit.Colors.Row,
				Parent = body,
			}, { Kit.Corner(8) })
			local icon = ItemGrid.Slot(row, { size = 64 })
			icon.frame.Position = UDim2.fromOffset(10, 14)
			icon.Set(o.item, tostring(o.quantity - o.delivered))
			local text = Kit.Label(row, "", {
				Position = UDim2.fromOffset(86, 8),
				Size = UDim2.new(1, -250, 0, 56),
				TextWrapped = true,
				RichText = true,
				TextSize = 14,
				TextYAlignment = Enum.TextYAlignment.Top,
			})
			text.Text = "<b>" .. Items.Name(o.item) .. "</b>  " .. o.delivered .. " / " .. o.quantity
				.. "\n<font color=\"#a0a6b2\">" .. o.issuer .. "</font>"
				.. "\nZapłata: <font color=\"#ffd65a\"><b>" .. Money.Format(o.rewardCents) .. "</b></font>"
			local deadline = Kit.Label(row, "", {
				Position = UDim2.fromOffset(86, 66),
				Size = UDim2.new(1, -250, 0, 20),
				TextSize = 13,
				TextColor3 = Kit.Colors.Muted,
			})
			table.insert(timers, { label = deadline, at = o.deadline, prefix = "Termin: " })
			local side = Kit.New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 10),
				Size = UDim2.fromOffset(150, 72),
				Parent = row,
			}, { Kit.New("UIListLayout", { Padding = UDim.new(0, 6) }) })
			local give = math.min(Game.Count(o.item), o.quantity - o.delivered)
			Recipes.Action(side, give > 0 and ("Oddaj " .. give) or "Nie masz", give > 0, function()
				if give > 0 then
					call("ContractDeliver", { id = o.id, quantity = give })
					render()
				end
			end)
			local armed = false
			local drop
			drop = Kit.Button(side, "Zrezygnuj", function()
				if not armed then
					armed = true
					drop.Text = "Na pewno?"
					return
				end
				call("ContractDrop", { id = o.id })
				render()
			end, { Size = UDim2.fromOffset(150, 26), TextSize = 13, BackgroundColor3 = Kit.Colors.Danger })
		end
		if reply.nextAt then
			local label = Kit.Label(body, "", { TextColor3 = Kit.Colors.Muted, TextSize = 14, Size = UDim2.new(1, -8, 0, 24) })
			table.insert(timers, { label = label, at = reply.nextAt, prefix = "Następne zlecenie za ", refresh = true })
		end
	end

	table.insert(connections, Game.Changed.Event:Connect(render))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local now = Game.Now()
		for _, entry in ipairs(timers) do
			entry.label.Text = entry.prefix .. timeLeft(entry.at - now)
			if entry.at <= now and not asked then
				-- A new order came, or one ran out: ask the server again.
				asked = true
				task.spawn(function()
					call("ContractsGet")
					render()
					task.wait(1)
					asked = false
				end)
			end
		end
	end))
	render()
	return window
end

return ContractsWindow
