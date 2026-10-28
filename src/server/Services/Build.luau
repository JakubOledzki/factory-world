-- Turns the models of Shared.Models (plain lists of parts) into Roblox parts, and the labels and
-- prompts put on them.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Models = require(Shared.Models)

local Build = {}

local Shapes = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end
Build.Rgb = rgb

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

local function effects(part, spec)
	if spec.light then
		local light = Instance.new("PointLight")
		light.Color = rgb(spec.light.color)
		light.Range = spec.light.range
		light.Brightness = spec.light.brightness
		light.Shadows = true
		light.Parent = part
	end
	if spec.fire then
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 140, 40)
		fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
		fire.Parent = part
	end
	if spec.smoke then
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(150, 150, 150)
		smoke.Opacity = 0.15
		smoke.RiseVelocity = 4
		smoke.Size = 1.5
		smoke.Parent = part
	end
	if spec.sparkle then
		local spray = Instance.new("ParticleEmitter")
		spray.Color = ColorSequence.new(Color3.fromRGB(190, 225, 255))
		spray.LightEmission = 0.4
		spray.Size = NumberSequence.new(0.25, 0)
		spray.Speed = NumberRange.new(6, 8)
		spray.SpreadAngle = Vector2.new(18, 18)
		spray.Lifetime = NumberRange.new(0.6, 0.9)
		spray.Rate = 60
		spray.Acceleration = Vector3.new(0, -20, 0)
		spray.EmissionDirection = Enum.NormalId.Right
		spray.Parent = part
	end
end

-- A Model named `name` made of the parts in `spec` (a list from Shared.Models), placed at `cframe`.
-- The first part with a name of "Rock", "Body", "Trunk", "Top" or "Counter" becomes the PrimaryPart.
function Build.FromModel(parent, name, spec, cframe)
	local model = Instance.new("Model")
	model.Name = name
	for _, p in ipairs(spec) do
		local part
		if p.shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			part.Shape = Shapes[p.shape]
		end
		part.Name = p.name or (p.group == "crown" and "Crown") or "Part"
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		part.CFrame = cframe
			* CFrame.new(p.pos[1], p.pos[2], p.pos[3])
			* CFrame.Angles(0, p.yaw or 0, 0)
			* CFrame.Angles(p.rot[1], p.rot[2], p.rot[3])
		part.Color = rgb(p.color)
		part.Material = Enum.Material[p.material]
		part.CanCollide = not p.noCollide
		part.CastShadow = p.material ~= "Neon"
		if p.group then
			part:SetAttribute("Group", p.group)
			if p.group == "glow" then
				part:SetAttribute("ColdColor", part.Color)
				part:SetAttribute("ColdMaterial", p.material)
			end
		end
		effects(part, p)
		part.Parent = model
		if model.PrimaryPart == nil and (p.name == "Rock" or p.name == "Body" or p.name == "Trunk" or p.name == "Top" or p.name == "Counter") then
			model.PrimaryPart = part
		end
	end
	model.Parent = parent
	return model
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

function Build.Tree(parent, at, seed)
	return Build.FromModel(parent, "Tree", Models.Tree(seed), yawed(at, (seed % 7) * 0.9))
end

-- Shows a tree standing, or only its stump when it was cut.
function Build.SetTreeStanding(model, standing)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("Group") == "crown" then
			part.Transparency = standing and 0 or 1
			part.CanCollide = standing
		end
	end
end

function Build.Furnace(parent, cframe)
	return Build.FromModel(parent, "Furnace", Models.Furnace(), cframe)
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
