-- The merchant's square in the middle of the server: the merchant's stall, the workbench, a
-- fountain, the spawn and the paths to the plots, and the forest all around.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PlotLayout = require(Shared.PlotLayout)
local Models = require(Shared.Models)
local Build = require(script.Parent.Build)

local World = {}

-- The top of the square's paving, a little above the grass: what stands on the square stands on it.
local Paving = 0.4

local function placed(spot, y)
	return CFrame.new(spot.x, Paving + (y or 0), spot.z) * CFrame.Angles(0, spot.yaw or 0, 0)
end

function World.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Square"
	folder.Parent = workspace

	-- The ground is Roblox terrain grass, flat with its top at y = 0 (one layer of 4-stud voxels).
	local terrain = workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(96, 140, 64))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(120, 98, 72))
	terrain:FillBlock(CFrame.new(0, -2, 0), Vector3.new(2 * PlotLayout.GroundHalf(), 4, 2 * PlotLayout.GroundHalf()), Enum.Material.Grass)
	-- Paving in two rings of stone.
	Build.Part(folder, {
		Name = "Paving",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 64, 64),
		CFrame = CFrame.new(0, Paving - 1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(168, 160, 148),
		Material = Enum.Material.Cobblestone,
	})
	Build.Part(folder, {
		Name = "PavingInner",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 22, 22),
		CFrame = CFrame.new(0, Paving - 0.95, 0) * CFrame.Angles(0, 0, math.pi / 2),
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

	local board = Build.FromModel(folder, "NoticeBoard", Models.NoticeBoard(), placed(PlotLayout.Board))
	Build.Label(board.Board, "Zlecenia", 5.6, Color3.fromRGB(255, 214, 150))
	Build.Prompt(board.Board, { ActionText = "Zlecenia", ObjectText = "Tablica zleceń", HoldDuration = 0, KeyboardKeyCode = Enum.KeyCode.E }, { Kind = "contracts" })

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
			CFrame = cframe * CFrame.new(0, 0.04, 0),
			Color = Color3.fromRGB(112, 96, 70),
			Material = Enum.Material.Ground,
		})
		Build.Part(folder, {
			Name = "Path",
			Size = Vector3.new(6, 0.2, length + 2),
			CFrame = cframe * CFrame.new(0, 0.08, 0),
			Color = Color3.fromRGB(156, 134, 100),
			Material = Enum.Material.Ground,
		})
	end
end

-- The forest between the plots: thousands of trees with no prompts, so nothing in it can be cut or
-- built on. Built a little at a time so the server keeps running meanwhile.
function World.PlantForest()
	local folder = Instance.new("Folder")
	folder.Name = "Forest"
	folder.Parent = workspace
	for i, t in ipairs(PlotLayout.ForestTrees()) do
		Build.FromModel(folder, "Tree", Models.ForestTree(t.seed), CFrame.new(t.x, 0, t.z) * CFrame.Angles(0, t.yaw, 0))
		if i % 250 == 0 then
			task.wait()
		end
	end
end

return World
