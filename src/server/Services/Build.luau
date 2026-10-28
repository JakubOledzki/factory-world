-- Turns the models of Shared.Models (plain lists of parts) into Roblox parts, and the labels and
-- prompts put on them.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Models = require(Shared.Models)
local Assemble = require(Shared.Assemble)

local Build = {}

Build.Rgb = Assemble.Rgb

-- A new anchored part; `props` sets any of its properties.
function Build.Part(parent, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for name, value in pairs(props) do
		part[name] = value
	end
	part.Parent = parent
	return part
end

-- A Model named `name` made of the parts in `spec` (a list from Shared.Models), placed at `cframe`.
function Build.FromModel(parent, name, spec, cframe)
	return Assemble.Model(parent, name, spec, cframe)
end

function Build.Prompt(parent, props, attributes)
	local prompt = Instance.new("ProximityPrompt")
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	for name, value in pairs(props) do
		prompt[name] = value
	end
	for name, value in pairs(attributes or {}) do
		prompt:SetAttribute(name, value)
	end
	prompt.Parent = parent
	return prompt
end

function Build.Label(parent, text, offsetY, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function yawed(at, yaw)
	return CFrame.new(at) * CFrame.Angles(0, yaw or 0, 0)
end

-- A mine with its entrance facing `yaw`; `at` is the ground point under its middle.
function Build.Mine(parent, at, seed, yaw)
	return Build.FromModel(parent, "Mine", Models.Mine(seed), yawed(at, yaw))
end

-- A furnace; `compact` for one on the build grid, without the coal box beside it.
function Build.Furnace(parent, cframe, compact)
	return Build.FromModel(parent, "Furnace", Models.Furnace(compact), cframe)
end

-- Lights the furnace's coal bed and fire while it smelts.
function Build.SetFurnaceLit(model, lit)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("Group") == "glow" then
			part.Color = lit and Color3.fromRGB(255, 120 + (part.Name == "Fire" and 40 or 0), 30) or part:GetAttribute("ColdColor")
			part.Material = lit and Enum.Material.Neon or Enum.Material[part:GetAttribute("ColdMaterial")]
			for _, effect in ipairs(part:GetChildren()) do
				if effect:IsA("Fire") or effect:IsA("Light") then
					effect.Enabled = lit
				end
			end
		elseif part:IsA("Smoke") then
			part.Enabled = lit
		end
	end
end

return Build
