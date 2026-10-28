-- The workbench's window: recipes with their ingredients and the queue of orders.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Kit = require(script.Parent.Kit)
local Game = require(script.Parent.Parent.Game)

local Workshop = {}

function Workshop.Open(screen)
	local reply = Game.Call("WorkshopGet")
	if reply == nil then
		return nil
	end
	Game.SyncTime(reply.serverTime)
	local connections = {}
	local window, body = Kit.Window(screen, "Stół warsztatowy", 520, 480, function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)
	local queueLabels = {}
	local asked = false

	local function render()
		Kit.Clear(body)
		queueLabels = {}
		for _, recipe in ipairs(reply.recipes) do
			local row = Kit.Row(body, 52)
			Kit.Swatch(row, Items.Colors[recipe.id], 26)
			local parts = {}
			local enough = true
			for _, entry in ipairs(recipe.ingredients) do
				table.insert(parts, entry[2] .. " × " .. Items.Name(entry[1]))
				if Game.Count(entry[1]) < entry[2] then
					enough = false
				end
			end
			local text = Kit.Label(row, "", { Size = UDim2.new(0, 300, 1, 0), TextWrapped = true, RichText = true })
			text.Text = "<b>" .. Items.Name(recipe.id) .. " × " .. recipe.quantity .. "</b>  (" .. recipe.time .. " s)\n"
				.. '<font color="#a0a6b2">' .. table.concat(parts, ", ") .. "</font>"
			Kit.Button(row, "Zamów", function()
				local r = Game.Call("WorkshopOrder", { recipe = recipe.id })
				if r then
					reply = r
					Game.SyncTime(r.serverTime)
					render()
				end
			end, { BackgroundColor3 = enough and Kit.Colors.Button or Kit.Colors.Row })
		end
		Kit.Label(body, "Kolejka (" .. #reply.queue .. "/" .. reply.maxQueue .. "):", { TextColor3 = Kit.Colors.Muted })
		for _, order in ipairs(reply.queue) do
			local label = Kit.Label(body, "")
			table.insert(queueLabels, { label = label, order = order })
		end
	end

	table.insert(connections, Game.Changed.Event:Connect(render))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local now = Game.Now()
		local due = false
		for _, entry in ipairs(queueLabels) do
			local left = math.max(0, math.ceil(entry.order.finishesAt - now))
			entry.label.Text = Items.Name(entry.order.item) .. " × " .. entry.order.quantity .. ": " .. (left > 0 and (left .. " s") or "gotowe")
			if left == 0 then
				due = true
			end
		end
		-- Ask the server to hand out what is done, once per finished order.
		if due and not asked then
			asked = true
			task.spawn(function()
				local r = Game.Call("WorkshopGet")
				if r then
					reply = r
					Game.SyncTime(r.serverTime)
					render()
				end
				asked = false
			end)
		end
	end))
	render()
	return window
end

return Workshop
