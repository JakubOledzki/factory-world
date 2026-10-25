using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace FactoryWorld.Modules.Crafting;

/// <summary>One batch of a processing machine: the ingredients it takes and what comes out.</summary>
/// <param name="Id">The recipe's id, the same as the item it makes.</param>
/// <param name="Xp">Experience for each item taken out of the machine.</param>
public sealed record ProcessingRecipe(string Id, int Quantity, TimeSpan Time, IReadOnlyList<(string Item, int Quantity)> Ingredients, int Xp);

/// <param name="Kind">The machine's item id.</param>
/// <param name="Fired">Whether it burns fuel: one batch takes heat from the fire.</param>
/// <param name="Powered">Whether it runs on power: it works in its own time (<see cref="IPowerClock"/>), slower on too little power.</param>
/// <param name="Sea">Whether it works out on the water: a boat stays in port while a storm blows (<see cref="SeaClock"/>).</param>
/// <param name="Aurora">Whether tourists keep it busy: it works faster while the aurora shines (<see cref="AuroraClock"/>).</param>
public sealed record ProcessingMachine(
    string Kind, bool Fired, IReadOnlyList<ProcessingRecipe> Recipes, bool Powered = false, bool Sea = false, bool Aurora = false)
{
    public ProcessingRecipe? Recipe(string? id) => Recipes.FirstOrDefault(r => r.Id == id);
}

/// <summary>
/// Machines that turn crops into food, put on a plot like the furnace: a mill grinds grain into
/// flour, an oil press squeezes sunflowers, a barrel pickles cabbage, and the fired bakery and
/// field kitchen bake and cook from those; a sawmill saws wood into planks, beams and pellets. In the
/// mountains a quarry cuts stone, a crusher grinds stone and ore, a stonemason dresses stone and marble and a
/// fired foundry casts bronze and steel and fires bricks. On the shore boats fish, a smokehouse smokes fish, a
/// cannery cans it, a salt pan boils salt and a fish farm raises salmon and mussels. The mill, the crusher, the cannery,
/// oil press and the electric and industrial sawmills run on power from a
/// generator, through poles; they keep their times (<see cref="MachineState.StartedAt"/>) in their
/// own time, which stands still while they have no power. The player sets a recipe, then loads its ingredients
/// (and fuel, where the machine burns it); the machine makes one batch after another while the
/// player is away too, and the products wait in it until taken out.
/// </summary>
public static class Processing
{
    /// <summary>Of each ingredient, and of fuel.</summary>
    public const int MaxInput = 50;

    public const int MaxFuel = 50;

    /// <summary>A full machine stops until its products are taken out.</summary>
    public const int MaxOutput = 100;

    /// <summary>What a fired machine burns, and how many batches one piece lasts.</summary>
    public static readonly IReadOnlyDictionary<string, int> Fuels = new Dictionary<string, int>
    {
        [Items.Coal] = 4,
        [Items.Charcoal] = 4,
        [Items.Wood] = 1,
        [Items.WoodPellets] = 2,
    };

    public static readonly IReadOnlyList<ProcessingMachine> Machines =
    [
        new(Items.Mill, false,
        [
            new(Items.Flour, 1, TimeSpan.FromSeconds(6), [(Items.Wheat, 2)], 1),
            new(Items.CornFlour, 1, TimeSpan.FromSeconds(6), [(Items.Corn, 2)], 1),
        ], Powered: true),
        new(Items.OilPress, false,
        [
            new(Items.SunflowerOil, 1, TimeSpan.FromSeconds(10), [(Items.Sunflower, 2)], 2),
        ], Powered: true),
        new(Items.PicklingBarrel, false,
        [
            new(Items.Sauerkraut, 2, TimeSpan.FromSeconds(60), [(Items.Cabbage, 2)], 1),
            new(Items.SaltedHerring, 3, TimeSpan.FromSeconds(60), [(Items.Herring, 3), (Items.Salt, 1)], 2),
        ]),
        new(Items.Bakery, true,
        [
            new(Items.Bread, 1, TimeSpan.FromSeconds(20), [(Items.Flour, 2)], 3),
            new(Items.CornBread, 1, TimeSpan.FromSeconds(20), [(Items.CornFlour, 2)], 3),
            new(Items.CarrotCake, 1, TimeSpan.FromSeconds(30), [(Items.Flour, 2), (Items.Carrot, 3), (Items.SunflowerOil, 1)], 6),
            new(Items.Gingerbread, 2, TimeSpan.FromSeconds(30), [(Items.Flour, 2), (Items.Honey, 1)], 5),
        ]),
        new(Items.Kitchen, true,
        [
            new(Items.Fries, 2, TimeSpan.FromSeconds(15), [(Items.Potato, 3), (Items.SunflowerOil, 1)], 2),
            new(Items.VegetableSoup, 1, TimeSpan.FromSeconds(20), [(Items.Carrot, 2), (Items.Potato, 2), (Items.Cabbage, 1)], 4),
            new(Items.Bigos, 2, TimeSpan.FromSeconds(25), [(Items.Sauerkraut, 2), (Items.Potato, 2)], 3),
            new(Items.ScrambledEggs, 2, TimeSpan.FromSeconds(15), [(Items.Egg, 3), (Items.SunflowerOil, 1)], 3),
            new(Items.FriedCarp, 1, TimeSpan.FromSeconds(15), [(Items.Carp, 1), (Items.SunflowerOil, 1)], 3),
            new(Items.FishSoup, 2, TimeSpan.FromSeconds(20), [(Items.Pike, 1), (Items.Potato, 2), (Items.Carrot, 1)], 4),
            new(Items.MushroomSoup, 2, TimeSpan.FromSeconds(20), [(Items.Mushrooms, 3), (Items.Potato, 1)], 4),
            new(Items.BerryPierogi, 2, TimeSpan.FromSeconds(25), [(Items.Flour, 2), (Items.Berries, 3)], 4),
            new(Items.HerbalTea, 2, TimeSpan.FromSeconds(10), [(Items.Herbs, 2)], 2),
            // Provisions for the crew of an orbital station.
            new(Items.Provisions, 2, TimeSpan.FromSeconds(10), [(Items.CannedFish, 1), (Items.Bread, 2), (Items.Cardboard, 1)], 2),
        ]),
        // Sawmills of three levels: the plain one saws by hand, the electric and the industrial one run on
        // power, work faster and glue plywood from planks; the industrial one gets three planks from a log.
        new(Items.Sawmill, false,
        [
            new(Items.Planks, 2, TimeSpan.FromSeconds(8), [(Items.Wood, 1)], 1),
            new(Items.Beams, 1, TimeSpan.FromSeconds(10), [(Items.Wood, 2)], 2),
            new(Items.WoodPellets, 3, TimeSpan.FromSeconds(8), [(Items.Wood, 2)], 1),
        ]),
        new(Items.ElectricSawmill, false,
        [
            new(Items.Planks, 2, TimeSpan.FromSeconds(4), [(Items.Wood, 1)], 1),
            new(Items.Beams, 1, TimeSpan.FromSeconds(5), [(Items.Wood, 2)], 2),
            new(Items.WoodPellets, 3, TimeSpan.FromSeconds(4), [(Items.Wood, 2)], 1),
            new(Items.Plywood, 1, TimeSpan.FromSeconds(12), [(Items.Planks, 3)], 3),
        ], Powered: true),
        new(Items.IndustrialSawmill, false,
        [
            new(Items.Planks, 3, TimeSpan.FromSeconds(2), [(Items.Wood, 1)], 1),
            new(Items.Beams, 1, TimeSpan.FromSeconds(2.5), [(Items.Wood, 2)], 2),
            new(Items.WoodPellets, 4, TimeSpan.FromSeconds(2), [(Items.Wood, 2)], 1),
            new(Items.Plywood, 1, TimeSpan.FromSeconds(5), [(Items.Planks, 3)], 3),
        ], Powered: true),
        // The mountain industry. A quarry cuts stone out of the mountain with nothing put in; it stands on mountain plots only.
        new(Items.Quarry, false,
        [
            new(Items.Stone, 2, TimeSpan.FromSeconds(6), [], 1),
        ]),
        // A crusher grinds stone into sand and ore into crushed ore, three from two, which smelts into as many ingots.
        new(Items.Crusher, false,
        [
            new(Items.Sand, 3, TimeSpan.FromSeconds(3), [(Items.Stone, 1)], 1),
            new(Items.CrushedIronOre, 3, TimeSpan.FromSeconds(5), [(Items.IronOre, 2)], 2),
            new(Items.CrushedCopperOre, 3, TimeSpan.FromSeconds(5), [(Items.CopperOre, 2)], 2),
            new(Items.CrushedTinOre, 3, TimeSpan.FromSeconds(6), [(Items.TinOre, 2)], 3),
        ], Powered: true),
        new(Items.Stonemason, false,
        [
            new(Items.StoneBlocks, 1, TimeSpan.FromSeconds(8), [(Items.Stone, 3)], 2),
            new(Items.MarbleSlabs, 2, TimeSpan.FromSeconds(10), [(Items.Marble, 1)], 3),
            // Refractory lining of firebricks.
            new(Items.RefractoryLining, 1, TimeSpan.FromSeconds(15), [(Items.Firebrick, 8), (Items.PrecastConcrete, 1)], 3),
        ]),
        // A foundry casts bronze and steel and fires bricks, on coal or wood.
        new(Items.Foundry, true,
        [
            new(Items.BronzeIngot, 4, TimeSpan.FromSeconds(12), [(Items.CopperIngot, 3), (Items.TinIngot, 1)], 4),
            new(Items.SteelIngot, 1, TimeSpan.FromSeconds(15), [(Items.IronIngot, 2), (Items.Coal, 1)], 3),
            new(Items.Bricks, 4, TimeSpan.FromSeconds(10), [(Items.Sand, 2), (Items.Stone, 2)], 2),
            // Firebricks of clay and quartz.
            new(Items.Firebrick, 4, TimeSpan.FromSeconds(10), [(Items.Clay, 2), (Items.Quartz, 1)], 2),
        ]),
        // Boats on the shore fish by themselves, 30% faster than a rod does on the same water; they stay in port in a storm.
        new(Items.FishingBoat, false,
        [
            new(Items.Herring, 3, TimeSpan.FromSeconds(12), [], 1),
            new(Items.Cod, 2, TimeSpan.FromSeconds(16), [], 2),
        ], Sea: true),
        new(Items.RowingBoat, false,
        [
            new(Items.Carp, 2, TimeSpan.FromSeconds(12), [], 1),
            new(Items.Pike, 1, TimeSpan.FromSeconds(12), [], 2),
        ], Sea: true),
        // A smokehouse smokes over a wood fire; a cannery on power cans herring in oil and grinds what is left into meal.
        new(Items.Smokehouse, true,
        [
            new(Items.SmokedFish, 1, TimeSpan.FromSeconds(20), [(Items.Cod, 2)], 3),
            new(Items.SmokedSalmon, 1, TimeSpan.FromSeconds(25), [(Items.Salmon, 1)], 4),
        ]),
        new(Items.Cannery, false,
        [
            new(Items.CannedFish, 2, TimeSpan.FromSeconds(15), [(Items.Herring, 2), (Items.SunflowerOil, 1), (Items.TinIngot, 1)], 4),
            new(Items.FishMeal, 2, TimeSpan.FromSeconds(8), [(Items.Herring, 3)], 1),
            new(Items.FishOil, 1, TimeSpan.FromSeconds(10), [(Items.Herring, 4)], 2),
        ], Powered: true),
        // A salt pan boils salt out of the sea in the sun; it stands on the coast, by the water.
        new(Items.SaltPan, false,
        [
            new(Items.Salt, 1, TimeSpan.FromSeconds(20), [], 1),
        ]),
        // A fish farm keeps salmon in cages fed on fish meal; mussels grow on its ropes by themselves.
        new(Items.FishFarm, false,
        [
            new(Items.Salmon, 2, TimeSpan.FromSeconds(40), [(Items.FishMeal, 1)], 3),
            new(Items.Mussels, 2, TimeSpan.FromSeconds(60), [], 2),
        ]),
        // Oil: a fired distillery boils crude oil into kerosene or leaves asphalt; a refinery on power splits it into
        // any fuel, faster and more of it; a cracker breaks heavy fuels into petrol; a chemical plant makes plastic,
        // rubber, fertiliser and tyres.
        new(Items.Distillery, true,
        [
            new(Items.Kerosene, 1, TimeSpan.FromSeconds(12), [(Items.CrudeOil, 2)], 2),
            new(Items.Asphalt, 1, TimeSpan.FromSeconds(10), [(Items.CrudeOil, 2)], 1),
            // Lubricant for bearings and gearboxes, of kerosene and wax.
            new(Items.Lubricant, 2, TimeSpan.FromSeconds(10), [(Items.Kerosene, 2), (Items.Wax, 1)], 2),
        ]),
        new(Items.Refinery, false,
        [
            new(Items.Gasoline, 2, TimeSpan.FromSeconds(8), [(Items.CrudeOil, 3)], 3),
            new(Items.Diesel, 2, TimeSpan.FromSeconds(8), [(Items.CrudeOil, 3)], 3),
            new(Items.Kerosene, 2, TimeSpan.FromSeconds(6), [(Items.CrudeOil, 2)], 2),
            new(Items.Asphalt, 2, TimeSpan.FromSeconds(6), [(Items.CrudeOil, 2)], 1),
            // Rocket fuel: kerosene chilled with coolant.
            new(Items.RocketFuel, 2, TimeSpan.FromSeconds(15), [(Items.Kerosene, 3), (Items.Coolant, 1)], 3),
        ], Powered: true),
        new(Items.Cracker, false,
        [
            new(Items.Gasoline, 4, TimeSpan.FromSeconds(10), [(Items.Diesel, 2), (Items.Kerosene, 2)], 4),
            new(Items.Diesel, 3, TimeSpan.FromSeconds(10), [(Items.Asphalt, 2), (Items.NaturalGas, 1)], 3),
        ], Powered: true),
        new(Items.ChemicalPlant, false,
        [
            new(Items.Plastic, 2, TimeSpan.FromSeconds(8), [(Items.NaturalGas, 2)], 3),
            new(Items.SyntheticRubber, 1, TimeSpan.FromSeconds(10), [(Items.Kerosene, 1), (Items.Sulfur, 1)], 3),
            new(Items.Fertilizer, 3, TimeSpan.FromSeconds(10), [(Items.NaturalGas, 2)], 2),
            new(Items.Tyres, 1, TimeSpan.FromSeconds(20), [(Items.SyntheticRubber, 4), (Items.SteelIngot, 1)], 8),
            new(Items.Insecticide, 2, TimeSpan.FromSeconds(10), [(Items.Turpentine, 1), (Items.NaturalGas, 1)], 3),
            // Glass laminate, coolant and carbon composite for the crafting tree.
            new(Items.GlassLaminate, 2, TimeSpan.FromSeconds(10), [(Items.Glass, 2), (Items.Resin, 1), (Items.Plastic, 1)], 2),
            new(Items.Coolant, 2, TimeSpan.FromSeconds(10), [(Items.NaturalGas, 2), (Items.Water, 2), (Items.Ice, 2)], 2),
            new(Items.CarbonComposite, 2, TimeSpan.FromSeconds(15), [(Items.GlassLaminate, 2), (Items.Charcoal, 2), (Items.CaseinGlue, 1)], 3),
        ], Powered: true),
        // The desert: a fired glassworks melts sand into glass (30% faster on sand) and blows bottles from waste glass;
        // an arc furnace on power makes silicon from quartz and cuts it into wafers for solar panels.
        new(Items.Glassworks, true,
        [
            new(Items.Glass, 2, TimeSpan.FromSeconds(10), [(Items.Sand, 3)], 2),
            new(Items.GlassBottles, 3, TimeSpan.FromSeconds(8), [(Items.WasteGlass, 2)], 2),
            new(Items.WindowPane, 2, TimeSpan.FromSeconds(12), [(Items.Glass, 3), (Items.TinIngot, 1)], 4),
            new(Items.Mirror, 1, TimeSpan.FromSeconds(12), [(Items.Glass, 2), (Items.SilverIngot, 1)], 5),
            new(Items.OpticalFiber, 1, TimeSpan.FromSeconds(15), [(Items.Glass, 2), (Items.Plastic, 1)], 6),
        ]),
        new(Items.ArcFurnace, false,
        [
            new(Items.Silicon, 1, TimeSpan.FromSeconds(10), [(Items.Quartz, 2), (Items.Coal, 1)], 4),
            new(Items.SiliconWafer, 2, TimeSpan.FromSeconds(8), [(Items.Silicon, 1)], 4),
            // The iridium alloy, of the glacier's iridium and meteoric iron.
            new(Items.IridiumAlloy, 1, TimeSpan.FromSeconds(10), [(Items.Iridium, 1), (Items.MeteoricIron, 2), (Items.SteelIngot, 2)], 2),
        ], Powered: true),
        // Water: a deep well on power draws it out of the ground (half as fast in the desert, twice in an oasis);
        // a desalinator on the sea coast makes it from the sea and leaves salt.
        new(Items.WaterWell, false,
        [
            new(Items.Water, 1, TimeSpan.FromSeconds(3), [], 1),
        ], Powered: true),
        new(Items.Desalinator, false,
        [
            new(Items.Water, 2, TimeSpan.FromSeconds(4), [], 1),
            new(Items.Salt, 1, TimeSpan.FromSeconds(8), [], 1),
        ], Powered: true),
        // Building: bricks dried in the sun from sand, clay and water; a fired kiln burns cement, a mixer on power makes concrete.
        new(Items.DryingYard, false,
        [
            new(Items.AdobeBricks, 2, TimeSpan.FromSeconds(30), [(Items.Sand, 2), (Items.Clay, 1), (Items.Water, 1)], 2),
        ]),
        new(Items.CementKiln, true,
        [
            new(Items.Cement, 2, TimeSpan.FromSeconds(12), [(Items.Stone, 2), (Items.Clay, 1)], 3),
        ]),
        new(Items.ConcreteMixer, false,
        [
            new(Items.Concrete, 3, TimeSpan.FromSeconds(8), [(Items.Cement, 1), (Items.Sand, 2), (Items.Water, 1)], 3),
            // Precast concrete, reinforced with steel.
            new(Items.PrecastConcrete, 1, TimeSpan.FromSeconds(10), [(Items.Concrete, 4), (Items.SteelIngot, 1)], 2),
        ], Powered: true),
        // The glacier: a fired melter turns ice into water; a cold store freezes fish and makes ice cream, and a server room
        // on power computes for research: both cool themselves for free on the glacier and on a block of ice per batch elsewhere.
        new(Items.IceMelter, true,
        [
            new(Items.Water, 2, TimeSpan.FromSeconds(4), [(Items.Ice, 1)], 1),
        ]),
        new(Items.ColdStore, false,
        [
            new(Items.FrozenFish, 2, TimeSpan.FromSeconds(20), [(Items.Cod, 2)], 2),
            new(Items.FrozenSalmon, 2, TimeSpan.FromSeconds(20), [(Items.Salmon, 2)], 3),
            new(Items.IceCream, 2, TimeSpan.FromSeconds(25), [(Items.Milk, 2), (Items.Egg, 1)], 3),
        ]),
        new(Items.ServerRoom, false,
        [
            new(Items.ComputingPower, 1, TimeSpan.FromSeconds(10), [], 2),
        ], Powered: true),
        // An ice core drill on power brings up cores of the glacier's ice, which a fired polar station studies.
        new(Items.IceCoreDrill, false,
        [
            new(Items.IceCore, 1, TimeSpan.FromSeconds(30), [], 3),
        ], Powered: true),
        new(Items.PolarStation, true,
        [
            new(Items.ResearchData, 1, TimeSpan.FromSeconds(20), [(Items.IceCore, 1)], 5),
        ]),
        // Tourists: a hotel of ice, heated by its fire, and a viewpoint take money from guests, three times as much under the aurora.
        new(Items.IceHotel, true,
        [
            new(Items.Takings, 4, TimeSpan.FromSeconds(60), [], 2),
        ], Aurora: true),
        new(Items.Viewpoint, false,
        [
            new(Items.Takings, 1, TimeSpan.FromSeconds(60), [], 1),
        ], Aurora: true),
        // Cities: an assembly hall puts together what the other biomes make; a multi-storey factory does the same twice as fast on one tile.
        new(Items.AssemblyHall, false, Assembly, Powered: true),
        new(Items.MultistoreyFactory, false, Assembly.Select(r => r with { Time = r.Time / 2 }).ToList(), Powered: true),
        // The crafting tree: a machine shop makes parts, a robotic hall the top of the tree; steelworks make steel, sheet and alloys
        // better than the foundry and the machine shop, and the steel combine and the megafactory do everything their parts do, three times as fast.
        new(Items.MachineShop, false, MachineShop, Powered: true),
        new(Items.RoboticHall, false, RoboticHall, Powered: true),
        new(Items.OxygenConverter, false, Converter, Powered: true),
        new(Items.RollingMill, false, Rolling, Powered: true),
        new(Items.ContinuousCaster, false, Casting, Powered: true),
        new(Items.SteelCombine, false, Combined(CombinedSpeed, Converter, Rolling, Casting), Powered: true),
        new(Items.Megafactory, false, Combined(CombinedSpeed, MachineShop, Assembly, RoboticHall), Powered: true),
        // A municipal sorting plant sorts the town's rubbish.
        new(Items.CitySorter, false,
        [
            new(Items.WastePaper, 2, TimeSpan.FromSeconds(8), [(Items.Trash, 4)], 1),
            new(Items.WastePlastic, 2, TimeSpan.FromSeconds(8), [(Items.Trash, 6)], 1),
            new(Items.WasteGlass, 2, TimeSpan.FromSeconds(8), [(Items.Trash, 6)], 1),
            new(Items.WasteAluminium, 1, TimeSpan.FromSeconds(10), [(Items.Trash, 10)], 1),
            new(Items.WasteCopper, 1, TimeSpan.FromSeconds(10), [(Items.Trash, 25)], 1),
        ], Powered: true),
        // Offices that also sell their services to other players (see the world's cities).
        new(Items.DesignOffice, false,
        [
            new(Items.Blueprint, 1, TimeSpan.FromSeconds(40), [(Items.WastePaper, 2)], 3),
        ], Powered: true),
        new(Items.Laboratory, false,
        [
            new(Items.ResearchData, 1, TimeSpan.FromSeconds(60), [(Items.SiliconWafer, 2), (Items.GlassBottles, 4), (Items.Water, 2)], 5),
        ], Powered: true),
        new(Items.ServiceWorkshop, false,
        [
            new(Items.Gasket, 4, TimeSpan.FromSeconds(20), [(Items.SteelIngot, 1), (Items.SyntheticRubber, 1)], 3),
        ], Powered: true),
        // Forestry: a paper mill on power pulps pellets into paper and presses waste paper into cardboard; a carpenter's shop makes
        // furniture, the oak dresser of oak wood; a charcoal kiln chars wood slowly in its own fire; a fired tar kiln boils resin.
        new(Items.PaperMill, false,
        [
            new(Items.Pulp, 2, TimeSpan.FromSeconds(12), [(Items.WoodPellets, 3), (Items.Water, 1)], 2),
            new(Items.Paper, 3, TimeSpan.FromSeconds(8), [(Items.Pulp, 2)], 2),
            // Cardboard is pressed from waste paper.
            new(Items.Cardboard, 2, TimeSpan.FromSeconds(8), [(Items.WastePaper, 3)], 2),
        ], Powered: true),
        new(Items.Carpentry, false,
        [
            new(Items.Chair, 1, TimeSpan.FromSeconds(20), [(Items.Planks, 4), (Items.Nails, 2)], 3),
            new(Items.Table, 1, TimeSpan.FromSeconds(30), [(Items.Planks, 6), (Items.Beams, 2), (Items.Nails, 4)], 5),
            new(Items.Wardrobe, 1, TimeSpan.FromSeconds(45), [(Items.Plywood, 4), (Items.Planks, 4), (Items.Nails, 6)], 8),
            new(Items.OakDresser, 1, TimeSpan.FromSeconds(60), [(Items.OakWood, 6), (Items.Nails, 4), (Items.Rosin, 1)], 12),
            // Insulation boards of wool between plywood.
            new(Items.InsulationBoard, 1, TimeSpan.FromSeconds(10), [(Items.Wool, 2), (Items.Plywood, 1)], 2),
        ]),
        new(Items.CharcoalKiln, false,
        [
            new(Items.Charcoal, 2, TimeSpan.FromSeconds(60), [(Items.Wood, 4)], 2),
        ]),
        new(Items.TarKiln, true,
        [
            new(Items.Tar, 2, TimeSpan.FromSeconds(20), [(Items.Resin, 3)], 2),
            new(Items.Turpentine, 1, TimeSpan.FromSeconds(15), [(Items.Resin, 2)], 3),
            new(Items.Rosin, 2, TimeSpan.FromSeconds(15), [(Items.Resin, 2)], 2),
            // Paint and casein glue.
            new(Items.Paint, 3, TimeSpan.FromSeconds(10), [(Items.Turpentine, 1), (Items.SunflowerOil, 1), (Items.Clay, 1)], 2),
            new(Items.CaseinGlue, 2, TimeSpan.FromSeconds(10), [(Items.Milk, 2), (Items.Rosin, 1)], 2),
        ]),
    ];

    /// <summary>What an assembly hall puts together.</summary>
    private static List<ProcessingRecipe> Assembly =>
    [
        new(Items.CircuitBoard, 2, TimeSpan.FromSeconds(15), [(Items.CopperIngot, 1), (Items.Plastic, 1), (Items.SiliconWafer, 1)], 2),
        new(Items.ElectricMotor, 1, TimeSpan.FromSeconds(20), [(Items.CopperIngot, 4), (Items.IronIngot, 2)], 2),
        // The crafting tree from level 3 up: parts, robots, rocket engines and the plasma chamber.
        new(Items.CompositePanel, 1, TimeSpan.FromSeconds(30), [(Items.CarbonComposite, 3), (Items.InsulationBoard, 1), (Items.CaseinGlue, 1)], 5),
        new(Items.Alternator, 1, TimeSpan.FromSeconds(45), [(Items.Rotor, 1), (Items.MachineHousing, 1), (Items.WiringHarness, 1)], 8),
        new(Items.ControlModule, 1, TimeSpan.FromSeconds(45), [(Items.CircuitBoard, 2), (Items.WiringHarness, 1), (Items.WindowPane, 1), (Items.MachineHousing, 1)], 8),
        new(Items.PressureVessel, 1, TimeSpan.FromSeconds(45), [(Items.CompositePanel, 2), (Items.PaintedSheet, 4), (Items.Gasket, 4)], 8),
        new(Items.ComputingCore, 1, TimeSpan.FromSeconds(90), [(Items.ControlModule, 2), (Items.OpticalFiber, 4), (Items.SiliconWafer, 4), (Items.Coolant, 2)], 12),
        new(Items.RobotArm, 1, TimeSpan.FromSeconds(90), [(Items.HydraulicActuator, 2), (Items.ControlModule, 1), (Items.WiringHarness, 2)], 12),
        new(Items.Turbopump, 1, TimeSpan.FromSeconds(90), [(Items.Rotor, 2), (Items.Gearbox, 1), (Items.CombustionChamber, 1), (Items.ControlModule, 1)], 12),
        new(Items.TurbineSet, 1, TimeSpan.FromSeconds(90), [(Items.CompositePanel, 4), (Items.Alternator, 1), (Items.Gearbox, 1)], 12),
        new(Items.CryogenicTank, 1, TimeSpan.FromSeconds(90), [(Items.PressureVessel, 1), (Items.InsulationBoard, 4), (Items.Coolant, 4), (Items.ControlModule, 1)], 12),
        new(Items.IndustrialRobot, 1, TimeSpan.FromSeconds(180), [(Items.RobotArm, 2), (Items.ComputingCore, 1), (Items.Alternator, 1)], 20),
        new(Items.NavigationSystem, 1, TimeSpan.FromSeconds(180), [(Items.ComputingCore, 1), (Items.Mirror, 4), (Items.Coil, 2), (Items.OpticalFiber, 4)], 20),
        new(Items.RocketEngine, 1, TimeSpan.FromSeconds(180), [(Items.Turbopump, 2), (Items.RocketNozzle, 1), (Items.CombustionChamber, 1), (Items.ControlModule, 1)], 20),
        new(Items.PlasmaChamber, 1, TimeSpan.FromSeconds(180), [(Items.SuperconductingMagnet, 8), (Items.RefractoryLining, 4), (Items.PressureVessel, 2), (Items.ComputingCore, 1)], 20),
    ];

    /// <summary>What a machine shop makes: wire and the mechanical parts of the crafting tree.</summary>
    private static List<ProcessingRecipe> MachineShop =>
    [
        new(Items.ElectricWire, 4, TimeSpan.FromSeconds(10), [(Items.CopperIngot, 1), (Items.Plastic, 1)], 2),
        new(Items.Bearing, 2, TimeSpan.FromSeconds(15), [(Items.SteelIngot, 1), (Items.Lubricant, 1)], 3),
        new(Items.PaintedSheet, 2, TimeSpan.FromSeconds(15), [(Items.SteelIngot, 1), (Items.Paint, 1)], 3),
        new(Items.Coil, 1, TimeSpan.FromSeconds(15), [(Items.ElectricWire, 6), (Items.GlassLaminate, 1)], 3),
        new(Items.WiringHarness, 1, TimeSpan.FromSeconds(15), [(Items.ElectricWire, 8), (Items.SyntheticRubber, 1), (Items.CaseinGlue, 1)], 3),
        new(Items.SuperconductingWire, 4, TimeSpan.FromSeconds(15), [(Items.IridiumAlloy, 1), (Items.ElectricWire, 4), (Items.Coolant, 2)], 3),
        new(Items.Gearbox, 1, TimeSpan.FromSeconds(30), [(Items.BronzeIngot, 2), (Items.Bearing, 2), (Items.Lubricant, 1)], 5),
        new(Items.Rotor, 1, TimeSpan.FromSeconds(30), [(Items.Coil, 2), (Items.Bearing, 2), (Items.SteelIngot, 2)], 5),
        new(Items.MachineHousing, 1, TimeSpan.FromSeconds(30), [(Items.PaintedSheet, 4), (Items.InsulationBoard, 1), (Items.Gasket, 2)], 5),
        new(Items.CombustionChamber, 1, TimeSpan.FromSeconds(30), [(Items.RefractoryLining, 2), (Items.SteelIngot, 4), (Items.Gasket, 2)], 5),
        new(Items.SuperconductingMagnet, 1, TimeSpan.FromSeconds(30), [(Items.SuperconductingWire, 4), (Items.Coil, 2), (Items.Coolant, 2)], 5),
        new(Items.HydraulicActuator, 1, TimeSpan.FromSeconds(45), [(Items.Gearbox, 1), (Items.Gasket, 2), (Items.Lubricant, 2), (Items.SteelIngot, 2)], 8),
        new(Items.RocketNozzle, 1, TimeSpan.FromSeconds(45), [(Items.CombustionChamber, 1), (Items.SteelIngot, 2), (Items.Firebrick, 4)], 8),
    ];

    /// <summary>What a robotic hall builds: the top of the crafting tree, rockets, satellites and fusion reactors.</summary>
    private static List<ProcessingRecipe> RoboticHall =>
    [
        new(Items.Avionics, 1, TimeSpan.FromSeconds(300), [(Items.NavigationSystem, 1), (Items.ComputingCore, 2), (Items.WiringHarness, 4)], 30),
        new(Items.PlasmaControl, 1, TimeSpan.FromSeconds(300), [(Items.ComputingCore, 2), (Items.SuperconductingMagnet, 4), (Items.ControlModule, 2), (Items.IndustrialRobot, 1)], 30),
        new(Items.RocketStage, 1, TimeSpan.FromSeconds(600), [(Items.RocketEngine, 4), (Items.CryogenicTank, 2), (Items.Avionics, 1), (Items.CompositePanel, 8)], 50),
        new(Items.Satellite, 1, TimeSpan.FromSeconds(600), [(Items.SolarPanel, 8), (Items.Avionics, 1), (Items.CompositePanel, 4), (Items.SuperconductingMagnet, 1)], 50),
        new(Items.FusionReactor, 1, TimeSpan.FromSeconds(600), [(Items.PlasmaChamber, 2), (Items.PlasmaControl, 1), (Items.TurbineSet, 2), (Items.CryogenicTank, 2)], 50),
        new(Items.LaunchRocket, 1, TimeSpan.FromSeconds(1200), [(Items.RocketStage, 2), (Items.Avionics, 1), (Items.CompositePanel, 6)], 80),
    ];

    /// <summary>What an oxygen converter, a rolling mill and a continuous caster make, each better than the machine it outdoes.</summary>
    private static List<ProcessingRecipe> Converter =>
    [
        new(Items.SteelIngot, 2, TimeSpan.FromSeconds(12), [(Items.IronIngot, 3), (Items.Coal, 1)], 3),
    ];

    private static List<ProcessingRecipe> Rolling =>
    [
        new(Items.PaintedSheet, 3, TimeSpan.FromSeconds(10), [(Items.SteelIngot, 1), (Items.Paint, 1)], 3),
        new(Items.ElectricWire, 6, TimeSpan.FromSeconds(6), [(Items.CopperIngot, 1), (Items.Plastic, 1)], 2),
    ];

    private static List<ProcessingRecipe> Casting =>
    [
        new(Items.BronzeIngot, 5, TimeSpan.FromSeconds(10), [(Items.CopperIngot, 3), (Items.TinIngot, 1)], 4),
        new(Items.IridiumAlloy, 2, TimeSpan.FromSeconds(30), [(Items.Iridium, 1), (Items.MeteoricIron, 2), (Items.SteelIngot, 2)], 20),
    ];

    /// <summary>Recipes of several machines in one, <paramref name="faster"/> times as fast.</summary>
    private static List<ProcessingRecipe> Combined(double faster, params List<ProcessingRecipe>[] lists) =>
        lists.SelectMany(l => l).GroupBy(r => r.Id).Select(g => g.First() with { Time = g.First().Time / faster }).ToList();

    /// <summary>How much faster the steel combine and the megafactory work than the machines they combine.</summary>
    public const double CombinedSpeed = 3;

    /// <summary>How much faster every machine works in a city: industry and assembly +25%.</summary>
    public const double CityBonus = 1.25;

    /// <summary>What one piece of takings a tourist pays, in cents.</summary>
    public const long TakingsCents = 500;

    /// <summary>The biome number of a city.</summary>
    public const int City = 9;

    /// <summary>Machines that cool themselves with a block of ice per batch off the glacier.</summary>
    private static bool Iced(string kind, int biome) => kind is Items.ColdStore or Items.ServerRoom && biome != Blizzard.Biome;

    public static readonly IReadOnlyDictionary<string, ProcessingMachine> ByKind = Machines.ToDictionary(m => m.Kind);

    private static readonly System.Collections.Concurrent.ConcurrentDictionary<(string, double, bool), ProcessingMachine> Variants = new();

    /// <summary>How much faster a machine of <paramref name="kind"/> works on a plot of <paramref name="biome"/>: a glassworks on sand,
    /// a smokehouse and a cannery by the water, a deep well slower in the desert and faster in an oasis.</summary>
    public static double Bonus(string kind, int biome) => kind switch
    {
        Items.Glassworks when Oasis.Sandy(biome) => 1.3,
        Items.Smokehouse or Items.Cannery when biome is 10 or 11 => 1.15,
        Items.WaterWell when biome == Oasis.Desert => 0.5,
        Items.WaterWell when biome == Oasis.Biome => 2,
        // The cold air of the glacier cools what runs hot.
        Items.Refinery or Items.Cracker or Items.ArcFurnace or Items.ChemicalPlant when biome == Blizzard.Biome => 1.2,
        _ when biome == City => CityBonus,
        _ => 1,
    };

    /// <summary>How much faster a machine on power works on a plot with a control center.</summary>
    public const double ControlBonus = 1.2;

    /// <summary>The machine of <paramref name="kind"/> as it works on a plot of <paramref name="biome"/>: its recipes shorter by its <see cref="Bonus"/>
    /// (and by <see cref="ControlBonus"/> on power when the plot has a control center), and off the glacier with a block of ice more for a machine that has to be cooled.</summary>
    public static ProcessingMachine? For(string kind, int biome, bool controlled = false)
    {
        if (!ByKind.TryGetValue(kind, out var machine))
        {
            return null;
        }

        var (bonus, iced) = (Bonus(kind, biome) * (controlled && machine.Powered ? ControlBonus : 1), Iced(kind, biome));
        return bonus == 1 && !iced ? machine : Variants.GetOrAdd((kind, bonus, iced), _ => machine with
        {
            Recipes = machine.Recipes.Select(r => r with
            {
                Time = r.Time / bonus,
                Ingredients = iced ? [.. r.Ingredients, (Items.Ice, 1)] : r.Ingredients,
            }).ToList(),
        });
    }

    /// <summary>The machine of <paramref name="kind"/> as it was when it loaded <paramref name="state"/>: cooled with ice when it holds a slot more
    /// than its plain recipe has. For a machine taken off its plot, which no longer tells its biome.</summary>
    public static ProcessingMachine? ForState(string kind, MachineState state) =>
        ByKind.TryGetValue(kind, out var machine) && machine.Recipe(state.Recipe) is { } recipe && state.Inputs.Count > recipe.Ingredients.Count
            ? For(kind, 0)
            : machine;

    /// <summary>The biome of the plot a machine stands on, or 0 when it stands on none.</summary>
    public static async Task<int> BiomeOfAsync(IPlotObjects plots, IPlotRegistry registry, Guid id, CancellationToken cancellationToken) =>
        await plots.PlotOfAsync(id, cancellationToken) is { } at ? (await registry.FindAsync(at.X, at.Y, cancellationToken))?.Biome ?? 0 : 0;

    /// <summary>The machine of <paramref name="kind"/> as it works where the object <paramref name="id"/> stands: by the plot's biome and its control center.</summary>
    public static async Task<ProcessingMachine?> OnPlotAsync(
        string kind, IPlotObjects plots, IPlotRegistry registry, Guid id, CancellationToken cancellationToken)
    {
        if (await plots.PlotOfAsync(id, cancellationToken) is not { } at)
        {
            return For(kind, 0);
        }

        var biome = (await registry.FindAsync(at.X, at.Y, cancellationToken))?.Biome ?? 0;
        var controlled = (await plots.ObjectsAsync(at.X, at.Y, cancellationToken)).Any(o => o.Kind == Items.ControlCenter);
        return For(kind, biome, controlled);
    }

    /// <summary>The clock a machine works by: its own time on the power grid, the boats' time that stands still in a storm, or plain time.</summary>
    public static async Task<IPowerClock> ClockAsync(ProcessingMachine machine, IPlotPower power, Guid id, CancellationToken cancellationToken) =>
        machine.Powered ? await power.ClockAsync(id, cancellationToken) : machine.Sea ? SeaClock.Instance : machine.Aurora ? AuroraClock.Instance : PlainTime.Instance;

    /// <summary>Batches the machine can still make from what it holds, ignoring time.</summary>
    public static int Batches(ProcessingMachine machine, MachineState s)
    {
        if (machine.Recipe(s.Recipe) is not { } recipe)
        {
            return 0;
        }

        var n = (MaxOutput - s.Output) / recipe.Quantity;
        for (var i = 0; i < recipe.Ingredients.Count; i++)
        {
            n = Math.Min(n, s.Input(i) / recipe.Ingredients[i].Quantity);
        }

        if (machine.Fired)
        {
            n = Math.Min(n, s.Heat + s.Fuel * FuelBatches(s.FuelItem));
        }

        return Math.Max(0, n);
    }

    private static int FuelBatches(string? fuel) => fuel is not null && Fuels.TryGetValue(fuel, out var batches) ? batches : 0;

    /// <summary>What the machine holds after working until <paramref name="now"/>.</summary>
    public static MachineState Advance(ProcessingMachine machine, MachineState s, DateTimeOffset now)
    {
        if (s.StartedAt is not { } started || machine.Recipe(s.Recipe) is not { } recipe)
        {
            return s with { StartedAt = null };
        }

        var possible = (int)Math.Min(int.MaxValue, Math.Max(0, (now - started).Ticks / recipe.Time.Ticks));
        var n = Math.Min(possible, Batches(machine, s));
        var inputs = s.Inputs.ToArray();
        for (var i = 0; i < recipe.Ingredients.Count; i++)
        {
            inputs[i] -= n * recipe.Ingredients[i].Quantity;
        }

        var after = s with { Inputs = inputs, Output = s.Output + n * recipe.Quantity };
        if (machine.Fired)
        {
            var perFuel = FuelBatches(s.FuelItem);
            var burnt = n > s.Heat ? (n - s.Heat + perFuel - 1) / perFuel : 0;
            after = after with { Fuel = s.Fuel - burnt, Heat = s.Heat + burnt * perFuel - n };
            if (after.Fuel == 0)
            {
                after = after with { FuelItem = null };
            }
        }

        return Batches(machine, after) > 0
            ? after with { StartedAt = started + recipe.Time * n }
            : after with { StartedAt = null };
    }

    /// <summary>Starts an idle machine that has everything for a batch.</summary>
    public static MachineState Start(ProcessingMachine machine, MachineState s, DateTimeOffset now) =>
        s.StartedAt is null && Batches(machine, s) > 0 ? s with { StartedAt = now } : s;
}

/// <param name="Recipe">The recipe the player set, or null.</param>
/// <param name="Inputs">How much of each of the recipe's ingredients is loaded, in the recipe's order.</param>
/// <param name="FuelItem">What lies by the fire (coal or wood), or null.</param>
/// <param name="Heat">Batches left from fuel already burning.</param>
/// <param name="Output">Products made from the recipe, waiting to be taken out.</param>
/// <param name="StartedAt">When the batch being made now started; null while the machine stands idle.</param>
public sealed record MachineState(
    string? Recipe, IReadOnlyList<int> Inputs, string? FuelItem, int Fuel, int Heat, int Output, DateTimeOffset? StartedAt)
{
    public static readonly MachineState Empty = new(null, [], null, 0, 0, 0, null);

    public int Input(int i) => i < Inputs.Count ? Inputs[i] : 0;
}

/// <param name="MachineTime">The machine's own time at <paramref name="ServerTime"/>, which <see cref="MachineState.StartedAt"/> is in.</param>
/// <param name="Speed">How fast it works on the power it has: 1 for machines that need none.</param>
public sealed record MachineReply(
    Guid Id, ProcessingMachine Machine, MachineState State, DateTimeOffset ServerTime, IReadOnlyList<(string Item, int Quantity)> Taken, XpGain? Xp,
    DateTimeOffset MachineTime = default, double Speed = 1);

/// <summary>Rows of <c>crafting.machines</c>; a machine gets one when it is first used.</summary>
internal static class MachineRows
{
    /// <summary>The machine's kind and what it holds, locked until the transaction ends.</summary>
    public static async Task<(string Kind, MachineState State)?> ReadAsync(GameDb db, Guid id, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            SELECT kind, recipe, inputs, fuel_item, fuel, heat, output, started_at
            FROM crafting.machines WHERE object_id = @id FOR UPDATE
            """, cancellationToken);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return (reader.GetString(0), new MachineState(
            reader.IsDBNull(1) ? null : reader.GetString(1), reader.GetFieldValue<int[]>(2),
            reader.IsDBNull(3) ? null : reader.GetString(3), reader.GetInt32(4), reader.GetInt32(5), reader.GetInt32(6),
            reader.IsDBNull(7) ? null : reader.GetFieldValue<DateTimeOffset>(7)));
    }

    public static async Task WriteAsync(GameDb db, Guid owner, Guid id, string kind, MachineState s, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            INSERT INTO crafting.machines (object_id, owner_id, kind, recipe, inputs, fuel_item, fuel, heat, output, started_at)
            VALUES (@id, @owner, @kind, @recipe, @inputs, @fuelItem, @fuel, @heat, @output, @started)
            ON CONFLICT (object_id) DO UPDATE SET
                recipe = @recipe, inputs = @inputs, fuel_item = @fuelItem, fuel = @fuel, heat = @heat,
                output = @output, started_at = @started
            """, cancellationToken);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("kind", kind);
        command.Parameters.AddWithValue("recipe", (object?)s.Recipe ?? DBNull.Value);
        command.Parameters.AddWithValue("inputs", s.Inputs.ToArray());
        command.Parameters.AddWithValue("fuelItem", (object?)s.FuelItem ?? DBNull.Value);
        command.Parameters.AddWithValue("fuel", s.Fuel);
        command.Parameters.AddWithValue("heat", s.Heat);
        command.Parameters.AddWithValue("output", s.Output);
        command.Parameters.Add(new NpgsqlParameter("started", NpgsqlTypes.NpgsqlDbType.TimestampTz) { Value = (object?)s.StartedAt ?? DBNull.Value });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>Everything the machine holds, as item stacks.</summary>
    public static IEnumerable<(string Item, int Quantity)> Contents(ProcessingMachine machine, MachineState s)
    {
        if (machine.Recipe(s.Recipe) is { } recipe)
        {
            if (s.Output > 0)
            {
                yield return (recipe.Id, s.Output);
            }

            for (var i = 0; i < recipe.Ingredients.Count; i++)
            {
                if (s.Input(i) > 0)
                {
                    yield return (recipe.Ingredients[i].Item, s.Input(i));
                }
            }
        }

        if (s.FuelItem is { } fuel && s.Fuel > 0)
        {
            yield return (fuel, s.Fuel);
        }
    }

    /// <summary>The machine is being picked up: what it holds goes to the owner's inventory.</summary>
    public static async Task ReleaseAsync(
        GameDb db, IInventory inventory, IWallet wallet, IProductionStats stats, IPlotPower power, Guid owner, Guid id, DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (await ReadAsync(db, id, cancellationToken) is not { } row || Processing.ForState(row.Kind, row.State) is not { } machine)
        {
            return;
        }

        var clock = await Processing.ClockAsync(machine, power, id, cancellationToken);
        var state = Processing.Advance(machine, row.State, clock.At(now));
        await stats.RecordAsync(owner, MachineProduction.Processed(machine, row.State, state, clock, now), cancellationToken);
        foreach (var (item, quantity) in Contents(machine, state))
        {
            if (Items.IsMoney(item))
            {
                await wallet.CreditAsync(owner, quantity * Processing.TakingsCents, $"takings {id}", cancellationToken);
            }
            else
            {
                await inventory.AddAsync(owner, item, quantity, cancellationToken);
            }
        }

        await using var delete = await db.CommandAsync("DELETE FROM crafting.machines WHERE object_id = @id", cancellationToken);
        delete.Parameters.AddWithValue("id", id);
        await delete.ExecuteNonQueryAsync(cancellationToken);
    }
}

public sealed class MachineService(
    GameDb db, IEnumerable<IPlacedObjects> places, IInventory inventory, ICharacterProgress progress, IProductionStats stats, ITechnologies technologies,
    IPlotPower power, IPlotObjects plots, IPlotRegistry registry, IWallet wallet, TimeProvider time)
{
    public Task<MachineReply> StateAsync(Guid owner, Guid id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (machine, state, clock) = await OpenAsync(owner, id, cancellationToken);
            return Reply(id, machine, state, clock, [], null);
        }, cancellationToken);

    /// <summary>Sets what the machine makes. Ingredients and products of the old recipe go back to the inventory; the fire keeps burning.</summary>
    public Task<MachineReply> SetRecipeAsync(Guid owner, Guid id, string recipeId, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (machine, state, clock) = await OpenAsync(owner, id, cancellationToken);
            var recipe = machine.Recipe(recipeId) ?? throw new GameException("no_recipe", "This machine has no such recipe.");
            await technologies.RequireUnlockedAsync(owner, recipe.Id, cancellationToken);
            var taken = new List<(string, int)>();
            XpGain? xp = null;
            if (state.Recipe != recipe.Id)
            {
                (state, xp) = await TakeOutputAsync(owner, machine, state, taken, cancellationToken);
                state = await TakeInputsAsync(owner, machine, state, taken, cancellationToken);
                state = Processing.Start(machine, state with { Recipe = recipe.Id, Inputs = new int[recipe.Ingredients.Count] }, clock.At(time.GetUtcNow()));
                await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
            }

            return Reply(id, machine, state, clock, taken, xp);
        }, cancellationToken);

    /// <summary>Puts items from the inventory into the machine: fuel by the fire, an ingredient of the recipe in its place.</summary>
    public Task<MachineReply> LoadAsync(Guid owner, Guid id, string item, int quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (quantity < 1)
            {
                throw new GameException("bad_quantity", "Put in at least one.");
            }

            var (machine, state, clock) = await OpenAsync(owner, id, cancellationToken);
            var recipe = machine.Recipe(state.Recipe);
            var slot = recipe is null ? -1 : recipe.Ingredients.ToList().FindIndex(i => i.Item == item);
            if (slot >= 0)
            {
                if (state.Input(slot) + quantity > Processing.MaxInput)
                {
                    throw new GameException("machine_full", $"The machine holds at most {Processing.MaxInput} of each ingredient.");
                }

                var inputs = state.Inputs.ToArray();
                inputs[slot] += quantity;
                state = state with { Inputs = inputs };
            }
            else if (machine.Fired && Processing.Fuels.ContainsKey(item))
            {
                if (state.FuelItem is { } fuel && fuel != item && state.Fuel > 0)
                {
                    throw new GameException("machine_busy", $"{Items.Names[fuel]} lies by the fire; take it out first.");
                }

                if (state.Fuel + quantity > Processing.MaxFuel)
                {
                    throw new GameException("machine_full", $"The machine holds at most {Processing.MaxFuel} fuel.");
                }

                state = state with { FuelItem = item, Fuel = state.Fuel + quantity };
            }
            else
            {
                throw recipe is null
                    ? new GameException("choose_recipe", "Choose what the machine makes first.")
                    : new GameException("not_processable", "This does not go into the machine.");
            }

            await inventory.RemoveAsync(owner, item, quantity, cancellationToken);
            state = Processing.Start(machine, state, clock.At(time.GetUtcNow()));
            await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
            return Reply(id, machine, state, clock, [], null);
        }, cancellationToken);

    /// <summary>Takes the products (<c>output</c>), the ingredients not used yet (<c>input</c>) or the fuel (<c>fuel</c>) out.</summary>
    public Task<MachineReply> TakeAsync(Guid owner, Guid id, string what, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (machine, state, clock) = await OpenAsync(owner, id, cancellationToken);
            var taken = new List<(string, int)>();
            XpGain? xp = null;
            switch (what)
            {
                case "output":
                    (state, xp) = await TakeOutputAsync(owner, machine, state, taken, cancellationToken);
                    // Room again for what was waiting on a full machine.
                    state = Processing.Start(machine, state, clock.At(time.GetUtcNow()));
                    break;
                case "input":
                    state = await TakeInputsAsync(owner, machine, state, taken, cancellationToken);
                    break;
                case "fuel":
                    if (state.FuelItem is { } fuel && state.Fuel > 0)
                    {
                        await inventory.AddAsync(owner, fuel, state.Fuel, cancellationToken);
                        taken.Add((fuel, state.Fuel));
                    }

                    // The batch in the fire keeps going on the fuel already lit, if there is any.
                    state = state with { FuelItem = null, Fuel = 0 };
                    if (state.Heat == 0)
                    {
                        state = state with { StartedAt = null };
                    }

                    break;
                default:
                    throw new GameException("bad_payload", "Take out output, input or fuel.");
            }

            await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
            return Reply(id, machine, state, clock, taken, xp);
        }, cancellationToken);

    private async Task<(MachineState, XpGain?)> TakeOutputAsync(
        Guid owner, ProcessingMachine machine, MachineState state, List<(string, int)> taken, CancellationToken cancellationToken)
    {
        if (machine.Recipe(state.Recipe) is not { } recipe || state.Output == 0)
        {
            return (state, null);
        }

        // What tourists paid goes into the wallet.
        if (Items.IsMoney(recipe.Id))
        {
            await wallet.CreditAsync(owner, state.Output * Processing.TakingsCents, $"takings {machine.Kind}", cancellationToken);
        }
        else
        {
            await inventory.ReceiveAsync(owner, recipe.Id, state.Output, cancellationToken);
        }

        taken.Add((recipe.Id, state.Output));
        var xp = await progress.AddXpAsync(owner, (long)state.Output * recipe.Xp, cancellationToken);
        return (state with { Output = 0 }, xp);
    }

    private async Task<MachineState> TakeInputsAsync(
        Guid owner, ProcessingMachine machine, MachineState state, List<(string, int)> taken, CancellationToken cancellationToken)
    {
        if (machine.Recipe(state.Recipe) is not { } recipe)
        {
            return state;
        }

        for (var i = 0; i < recipe.Ingredients.Count; i++)
        {
            if (state.Input(i) > 0)
            {
                await inventory.AddAsync(owner, recipe.Ingredients[i].Item, state.Input(i), cancellationToken);
                taken.Add((recipe.Ingredients[i].Item, state.Input(i)));
            }
        }

        return state with { Inputs = new int[recipe.Ingredients.Count], StartedAt = null };
    }

    private MachineReply Reply(Guid id, ProcessingMachine machine, MachineState state, IPowerClock clock, IReadOnlyList<(string, int)> taken, XpGain? xp)
    {
        var now = time.GetUtcNow();
        return new MachineReply(id, machine, state, now, taken, xp, clock.At(now), clock.Speed(now));
    }

    /// <summary>The player's machine, locked until the transaction ends and worked up to now, with the
    /// clock it works by: its own time on the power grid if it runs on power.</summary>
    private async Task<(ProcessingMachine, MachineState, IPowerClock)> OpenAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        ProcessingMachine? machine = null;
        foreach (var place in places)
        {
            if (await place.KindAsync(owner, id, cancellationToken) is { } kind)
            {
                machine = (await Processing.OnPlotAsync(kind, plots, registry, id, cancellationToken));
                break;
            }
        }

        if (machine is null)
        {
            throw new GameException("no_object", "There is no machine of yours here.");
        }

        // The grid is locked before the machine, as when inserters work it.
        var clock = await Processing.ClockAsync(machine, power, id, cancellationToken);
        var stored = (await MachineRows.ReadAsync(db, id, cancellationToken))?.State ?? MachineState.Empty;
        var now = time.GetUtcNow();
        var state = Processing.Advance(machine, stored, clock.At(now));
        var made = MachineProduction.Processed(machine, stored, state, clock, now);
        if (made.Count > 0)
        {
            await stats.RecordAsync(owner, made, cancellationToken);
            await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
        }

        return (machine, state, clock);
    }
}

/// <summary>Processing machines as inserters see them: ingredients of the chosen recipe and fuel go in, products come out.</summary>
public sealed class ProcessingPorts(GameDb db, IProductionStats stats, IPlotPower power, IPlotObjects plots, IPlotRegistry registry) : IMachinePorts
{
    public async Task<IMachinePort?> OpenAsync(Guid owner, Guid id, string kind, CancellationToken cancellationToken)
    {
        if (!Processing.ByKind.ContainsKey(kind) || (await Processing.OnPlotAsync(kind, plots, registry, id, cancellationToken)) is not { } machine)
        {
            return null;
        }

        var clock = await Processing.ClockAsync(machine, power, id, cancellationToken);
        var state = (await MachineRows.ReadAsync(db, id, cancellationToken))?.State ?? MachineState.Empty;
        return new Port(db, stats, owner, id, machine, state, clock);
    }

    /// <summary>Every call is given the time on the plot; the machine works in its own (<paramref name="clock"/>).</summary>
    private sealed class Port(GameDb db, IProductionStats stats, Guid owner, Guid id, ProcessingMachine machine, MachineState state, IPowerClock clock) : IMachinePort
    {
        private readonly List<ProductionEntry> _made = [];
        private bool _changed;

        private ProcessingRecipe? Recipe => machine.Recipe(state.Recipe);

        public string? Output(DateTimeOffset now, Func<string, bool> wanted)
        {
            Advance(now);
            // Money is no good on a belt: tourists' takings are taken out by hand.
            return Recipe is { } recipe && state.Output > 0 && !Items.IsMoney(recipe.Id) && wanted(recipe.Id) ? recipe.Id : null;
        }

        public void Take(string item, DateTimeOffset now)
        {
            Advance(now);
            if (Recipe?.Id == item && state.Output > 0)
            {
                // Room again for what was waiting on a full machine.
                state = Processing.Start(machine, state with { Output = state.Output - 1 }, clock.At(now));
                _changed = true;
            }
        }

        public bool Accepts(string item, DateTimeOffset now)
        {
            Advance(now);
            if (Slot(item) is var slot and >= 0)
            {
                return state.Input(slot) < Processing.MaxInput;
            }

            return machine.Fired && Processing.Fuels.ContainsKey(item)
                && (state.FuelItem is null || state.FuelItem == item || state.Fuel == 0) && state.Fuel < Processing.MaxFuel;
        }

        public void Put(string item, DateTimeOffset now)
        {
            if (Slot(item) is var slot and >= 0)
            {
                var inputs = new int[Recipe!.Ingredients.Count];
                for (var i = 0; i < inputs.Length; i++)
                {
                    inputs[i] = state.Input(i);
                }

                inputs[slot]++;
                state = state with { Inputs = inputs };
            }
            else
            {
                state = state with { FuelItem = item, Fuel = state.Fuel + 1 };
            }

            state = Processing.Start(machine, state, clock.At(now));
            _changed = true;
        }

        public DateTimeOffset? NextChange(DateTimeOffset now)
        {
            Advance(now);
            return state.StartedAt is { } started && Recipe is { } recipe ? clock.When(started + recipe.Time, now) : null;
        }

        public async Task SaveAsync(CancellationToken cancellationToken)
        {
            if (_changed)
            {
                await stats.RecordAsync(owner, _made, cancellationToken);
                await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
            }
        }

        private void Advance(DateTimeOffset now)
        {
            var before = state;
            state = Processing.Advance(machine, state, clock.At(now));
            var made = MachineProduction.Processed(machine, before, state, clock, now);
            if (made.Count > 0)
            {
                _made.AddRange(made);
                _changed = true;
            }
        }

        private int Slot(string item) => Recipe is { } recipe ? recipe.Ingredients.ToList().FindIndex(i => i.Item == item) : -1;
    }
}

/// <summary>The clock of machines that need no power.</summary>
internal sealed class PlainTime : IPowerClock
{
    public static readonly PlainTime Instance = new();

    public DateTimeOffset At(DateTimeOffset now) => now;

    public DateTimeOffset? When(DateTimeOffset machineTime, DateTimeOffset now) => machineTime > now ? machineTime : now;

    public double Speed(DateTimeOffset now) => 1;
}

public sealed record MachineRequest(Guid Machine);

public sealed record MachineRecipeRequest(Guid Machine, string Recipe);

public sealed record LoadMachineRequest(Guid Machine, string Item, int Quantity);

public sealed record TakeMachineRequest(Guid Machine, string What);

public abstract class MachineHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var owner = client.RequireAccount();
        var reply = await RunAsync(scope.ServiceProvider.GetRequiredService<MachineService>(), owner, payload, cancellationToken);
        var locked = await scope.ServiceProvider.GetRequiredService<ITechnologies>().LockedAsync(owner, cancellationToken);
        var machine = reply.Machine;
        var s = reply.State;
        var recipe = machine.Recipe(s.Recipe);
        return new Reply("machine", new
        {
            id = reply.Id,
            kind = machine.Kind,
            name = Items.Names[machine.Kind],
            recipe = recipe?.Id,
            recipes = machine.Recipes.Select(r => new
            {
                id = r.Id,
                name = Items.Names[r.Id],
                quantity = r.Quantity,
                seconds = r.Time.TotalSeconds,
                ingredients = r.Ingredients.Select(i => new { id = i.Item, name = Items.Names[i.Item], quantity = i.Quantity }),
                xp = r.Xp,
                locked = locked.GetValueOrDefault(r.Id),
            }),
            inputs = recipe?.Ingredients.Select((ingredient, i) => new
            {
                id = ingredient.Item,
                name = Items.Names[ingredient.Item],
                quantity = s.Input(i),
                need = ingredient.Quantity,
            }) ?? [],
            output = recipe is null || s.Output == 0 ? null : new { id = recipe.Id, name = Items.Names[recipe.Id], quantity = s.Output },
            fired = machine.Fired,
            fuel = s.FuelItem is { } fuel && s.Fuel > 0 ? new { id = fuel, name = Items.Names[fuel], quantity = s.Fuel } : null,
            heat = s.Heat,
            fuels = machine.Fired
                ? Processing.Fuels.Select(f => new { id = f.Key, name = Items.Names[f.Key], batches = f.Value })
                : [],
            batches = Processing.Batches(machine, s),
            // Unix milliseconds of when the batch being made would have started at full power (a machine
            // short of power keeps its time on its own clock), and how long one takes.
            startedAt = s.StartedAt is { } started ? (reply.ServerTime - (reply.MachineTime - started)).ToUnixTimeMilliseconds() : (long?)null,
            powered = machine.Powered,
            // How fast it works on the power it has, 0 to 1.
            speed = reply.Speed,
            seconds = recipe?.Time.TotalSeconds,
            serverTime = reply.ServerTime.ToUnixTimeMilliseconds(),
            maxInput = Processing.MaxInput,
            maxFuel = Processing.MaxFuel,
            maxOutput = Processing.MaxOutput,
            taken = reply.Taken.Select(t => new { id = t.Item, name = Items.Names[t.Item], quantity = t.Quantity }),
            xp = reply.Xp is { } xp ? new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } : null,
        });
    }

    protected abstract Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken);
}

/// <summary>What the machine holds now; the client asks again when the next batch is due.</summary>
public sealed class GetMachineHandler(IServiceScopeFactory scopes) : MachineHandler(scopes)
{
    public override string Type => "machine.get";

    protected override Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        machines.StateAsync(owner, Payload.Read<MachineRequest>(payload).Machine, cancellationToken);
}

public sealed class SetMachineRecipeHandler(IServiceScopeFactory scopes) : MachineHandler(scopes)
{
    public override string Type => "machine.recipe";

    protected override Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<MachineRecipeRequest>(payload);
        return machines.SetRecipeAsync(owner, request.Machine, request.Recipe ?? "", cancellationToken);
    }
}

public sealed class LoadMachineHandler(IServiceScopeFactory scopes) : MachineHandler(scopes)
{
    public override string Type => "machine.load";

    protected override Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<LoadMachineRequest>(payload);
        return machines.LoadAsync(owner, request.Machine, request.Item ?? "", request.Quantity, cancellationToken);
    }
}

public sealed class TakeMachineHandler(IServiceScopeFactory scopes) : MachineHandler(scopes)
{
    public override string Type => "machine.take";

    protected override Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<TakeMachineRequest>(payload);
        return machines.TakeAsync(owner, request.Machine, request.What ?? "", cancellationToken);
    }
}
