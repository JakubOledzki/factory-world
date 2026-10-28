-- Turns a model of Shared.Models (a plain list of parts) into a Roblox Model. The server builds the
-- world with it (Services/Build) and the client the see-through ghost of what the player is about
-- to build, so both look the same.
local Assemble = {}

local Shapes = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end
Assemble.Rgb = rgb

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

-- A Model named `name` made of the parts in `spec`, placed at `cframe`. The first part with a name
-- of "Rock", "Body", "Trunk", "Top" or "Counter" becomes the PrimaryPart. A `ghost` model is
-- see-through, has no effects and nothing touches or hits it.
function Assemble.Model(parent, name, spec, cframe, ghost)
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
		part.CanCollide = not p.noCollide and not ghost
		part.CastShadow = p.material ~= "Neon" and not ghost
		if p.hidden then
			part.Transparency = 1
		elseif ghost then
			part.Transparency = 0.55
		end
		if ghost then
			part.CanQuery = false
			part.CanTouch = false
		end
		if p.group then
			part:SetAttribute("Group", p.group)
			if p.group == "glow" then
				part:SetAttribute("ColdColor", part.Color)
				part:SetAttribute("ColdMaterial", p.material)
			end
		end
		if not ghost then
			effects(part, p)
		end
		part.Parent = model
		if model.PrimaryPart == nil and (p.name == "Rock" or p.name == "Body" or p.name == "Trunk" or p.name == "Top" or p.name == "Counter") then
			model.PrimaryPart = part
		end
	end
	model.Parent = parent
	return model
end

return Assemble
