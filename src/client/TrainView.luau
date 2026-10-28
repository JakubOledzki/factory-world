-- Draws the trains on the plots' railways. The server sets a plot railway's "Train" attribute
-- ("<count>|<item>,<item>") each time a train leaves that station or arrives there; here a train
-- with wagons of those goods comes out of the south tunnel, stops at the platform and goes on
-- into the north tunnel. Parts inside a tunnel's hill are hidden. It only draws.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assemble = require(Shared.Assemble)
local Items = require(Shared.Items)
local Models = require(Shared.Models)
local PlotLayout = require(Shared.PlotLayout)

local TrainView = {}

local Rail = PlotLayout.Rail
-- Seconds of each part of the run: in to the platform, standing, out into the tunnel.
local InTime, StopTime, OutTime = 9, 5, 8
-- How far beyond a tunnel's mouth a train starts and ends, in studs.
local Beyond = 45

local running = {} -- [railway Model] = { model, t0, origin }
local queued = {} -- [railway Model] = { list of item lists }

local function split(text, sep)
	local out = {}
	for piece in string.gmatch(text, "[^" .. sep .. "]+") do
		table.insert(out, piece)
	end
	return out
end

-- Where the train's front is (z on the railway) `t` seconds into its run, or nil when it is over.
local function frontAt(t)
	local start, stop, finish = Rail.to + Beyond, Rail.stop, Rail.from - Beyond
	if t < InTime then
		local u = t / InTime
		return start + (stop - start) * (1 - (1 - u) * (1 - u))
	elseif t < InTime + StopTime then
		return stop
	elseif t < InTime + StopTime + OutTime then
		local u = (t - InTime - StopTime) / OutTime
		return stop + (finish - stop) * u * u
	end
	return nil
end

local function start(railway, items)
	local origin = railway:GetAttribute("Origin")
	if origin == nil then
		return
	end
	local colors = {}
	for _, item in ipairs(items) do
		table.insert(colors, Items.Colors[item] or { 200, 200, 200 })
	end
	local spec = Models.Train(math.max(2, math.min(4, #items)), colors)
	local model = Assemble.Model(workspace, "Train", spec, origin * CFrame.new(Rail.x, 0, Rail.to + Beyond))
	running[railway] = { model = model, t0 = os.clock(), origin = origin }
end

local function onTrain(railway)
	local text = railway:GetAttribute("Train")
	if type(text) ~= "string" then
		return
	end
	local bar = string.find(text, "|", 1, true)
	local items = split(string.sub(text, (bar or 0) + 1), ",")
	if running[railway] then
		queued[railway] = queued[railway] or {}
		table.insert(queued[railway], items)
	else
		start(railway, items)
	end
end

local function watch(descendant)
	if descendant:IsA("Model") and descendant.Name == "Railway" then
		descendant:GetAttributeChangedSignal("Train"):Connect(function()
			onTrain(descendant)
		end)
	end
end

function TrainView.Start()
	local plots = workspace:WaitForChild("Plots")
	for _, descendant in ipairs(plots:GetDescendants()) do
		watch(descendant)
	end
	plots.DescendantAdded:Connect(watch)

	RunService.RenderStepped:Connect(function()
		for railway, run in pairs(running) do
			local front = frontAt(os.clock() - run.t0)
			if front == nil or railway.Parent == nil then
				run.model:Destroy()
				running[railway] = nil
				local next_ = queued[railway] and table.remove(queued[railway], 1)
				if next_ and railway.Parent then
					start(railway, next_)
				end
			else
				local at = run.origin * CFrame.new(Rail.x, 0, front)
				run.model:PivotTo(at)
				-- Hide what is inside a tunnel's hill.
				for _, part in ipairs(run.model:GetChildren()) do
					if part:IsA("BasePart") then
						local z = run.origin:PointToObjectSpace(part.Position).Z
						part.LocalTransparencyModifier = (z < Rail.from or z > Rail.to) and 1 or 0
					end
				end
			end
		end
	end)
end

return TrainView
