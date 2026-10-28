-- The merchant's square in the middle of the server: the merchant's stall, the workbench, a
-- fountain, the spawn and the paths to the plots.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PlotLayout = require(Shared.PlotLayout)
local Models = require(Shared.Models)
local Build = require(script.Parent.Build)

local World = {}

local function placed(spot, y)
	return CFrame.new(spot.x, y or 0, spot.z) * CFrame.Angles(0, spot.yaw or 0, 0)
end

function World.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Square"
	folder.Parent = workspace

	Build.Part(folder, {
		Name = "Ground",
		Size = Vector3.new(2 * PlotLayout.Ring + PlotLayout.Size + 80, 2, 2 * PlotLayout.Ring + PlotLayout.Size + 80),
		CFrame = CFrame.new(0, -1.5, 0),
		Color = Color3.fromRGB(92, 136, 66),
		Material = Enum.Material.Grass,
	})
	-- Paving in two rings of stone.
	Build.Part(folder, {
		Name = "Paving",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 64, 64),
		CFrame = CFrame.new(0, -0.45, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(168, 160, 148),
		Material = Enum.Material.Cobblestone,
	})
	Build.Part(folder, {
		Name = "PavingInner",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 22, 22),
		CFrame = CFrame.new(0, -0.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(190, 184, 172),
		Material = Enum.Material.Pavement,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Shape = Enum.PartType.Cylinder
	spawn.Size = Vector3.new(0.4, 7, 7)
	spawn.CFrame = placed(PlotLayout.SquareSpawn, 0.1) * CFrame.Angles(0, 0, math.pi / 2)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(200, 186, 150)
	spawn.Material = Enum.Material.Marble
	spawn.Parent = folder

	Build.FromModel(folder, "Fountain", Models.Fountain(), placed(PlotLayout.Fountain))

	-- The merchant's stall with the merchant behind the counter.
	local stall = Build.FromModel(folder, "Stall", Models.Stall(), placed(PlotLayout.Stall))
	Build.FromModel(folder, "Merchant", Models.Merchant(), placed(PlotLayout.Stall) * CFrame.new(0, 0, 2.6))
	Build.Label(stall.Sign, "Handlarz", 1.8, Color3.fromRGB(255, 230, 120))
	Build.Prompt(stall.Counter, { ActionText = "Handluj", ObjectText = "Handlarz", HoldDuration = 0, KeyboardKeyCode = Enum.KeyCode.E }, { Kind = "merchant" })

	local bench = Build.FromModel(folder, "Workbench", Models.Workbench(), placed(PlotLayout.Workbench))
	Build.Label(bench.Top, "Stół warsztatowy", 3.5, Color3.fromRGB(220, 230, 255))
	Build.Prompt(bench.Top, { ActionText = "Wytwarzaj", ObjectText = "Stół warsztatowy", HoldDuration = 0, KeyboardKeyCode = Enum.KeyCode.E }, { Kind = "workbench" })

	-- Dirt paths from the square to each plot, edged with a darker strip.
	for index = 1, PlotLayout.Count do
		local x, z = PlotLayout.Center(index)
		local length = PlotLayout.Ring - PlotLayout.Size / 2 - 30
		local direction = Vector3.new(x, 0, z).Unit
		local middle = direction * (31 + length / 2)
		local cframe = CFrame.lookAt(middle, middle + direction)
		Build.Part(folder, {
			Name = "PathEdge",
			Size = Vector3.new(7.4, 0.2, length + 2),
			CFrame = cframe * CFrame.new(0, -0.48, 0),
			Color = Color3.fromRGB(112, 96, 70),
			Material = Enum.Material.Ground,
		})
		Build.Part(folder, {
			Name = "Path",
			Size = Vector3.new(6, 0.2, length + 2),
			CFrame = cframe * CFrame.new(0, -0.42, 0),
			Color = Color3.fromRGB(156, 134, 100),
			Material = Enum.Material.Ground,
		})
	end
end

return World
