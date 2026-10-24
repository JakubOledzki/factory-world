namespace FactoryWorld.Modules.Abstractions.Contracts;

/// <summary>Every item in the game. Ids are stored in the database, so never rename one.</summary>
public static class Items
{
    public const string Trash = "trash";
    public const string WastePaper = "waste_paper";
    public const string WasteAluminium = "waste_aluminium";
    public const string WasteCopper = "waste_copper";
    public const string WastePlastic = "waste_plastic";
    public const string WasteGlass = "waste_glass";

    // Furniture: stands in the garage, can be picked up into the inventory and placed again.
    public const string TrashBin = "furniture_trash_bin";
    public const string Workbench = "furniture_workbench";
    public const string Shelf = "furniture_shelf";
    public const string BarrelBlue = "furniture_barrel_blue";
    public const string BarrelRed = "furniture_barrel_red";
    public const string Tyres = "furniture_tyres";
    public const string Pallet = "furniture_pallet";
    public const string GasCylinder = "furniture_gas_cylinder";
    public const string SortingMachine = "furniture_sorting_machine";
    public const string Furnace = "furniture_furnace";
    public const string Anvil = "furniture_anvil";

    // Upgraded furnaces: they stand on plots only and smelt faster, holding more.
    public const string BrickFurnace = "furniture_brick_furnace";
    public const string BlastFurnace = "furniture_blast_furnace";

    // Tools: held in the character's tool bar (one slot, more with a backpack).
    public const string Axe = "tool_axe";
    public const string Shovel = "tool_shovel";
    public const string Pickaxe = "tool_pickaxe";
    public const string Hoe = "tool_hoe";
    public const string Chainsaw = "tool_chainsaw";
    public const string Shears = "tool_shears";

    // Better pickaxes, forged at the anvil: they mine and break rocks faster than the iron one.
    public const string BronzePickaxe = "tool_bronze_pickaxe";
    public const string SteelPickaxe = "tool_steel_pickaxe";

    // Backpacks: worn by the character, each adds tiles to the inventory and slots to the tool bar.
    public const string SchoolBackpack = "backpack_school";
    public const string HikingBackpack = "backpack_hiking";
    public const string TrekkingBackpack = "backpack_trekking";
    public const string ExpeditionBackpack = "backpack_expedition";
    public const string TycoonBackpack = "backpack_tycoon";

    // Raw materials gathered on plots.
    public const string Wood = "wood";
    public const string Stone = "stone";
    public const string Sand = "sand";
    public const string Coal = "coal";
    public const string IronOre = "iron_ore";
    public const string CopperOre = "copper_ore";
    public const string TinOre = "tin_ore";
    public const string SilverOre = "silver_ore";
    public const string GoldOre = "gold_ore";

    // Smelted in a furnace from ores, and made at a workbench.
    public const string IronIngot = "iron_ingot";
    public const string CopperIngot = "copper_ingot";
    public const string TinIngot = "tin_ingot";
    public const string SilverIngot = "silver_ingot";
    public const string GoldIngot = "gold_ingot";
    public const string Nails = "nails";

    // Forestry: a sapling is planted on a plot and grows into a tree.
    public const string Sapling = "sapling";

    // Husbandry: animals let out on a pasture, fed crops, give eggs, wool (cut with shears) and milk.
    public const string Chicken = "animal_chicken";
    public const string Sheep = "animal_sheep";
    public const string Cow = "animal_cow";
    public const string Egg = "egg";
    public const string Wool = "wool";
    public const string Milk = "milk";

    // Crops grown on fertile plots.
    public const string Wheat = "wheat";
    public const string Carrot = "carrot";
    public const string Cabbage = "cabbage";
    public const string Corn = "corn";
    public const string Potato = "potato";
    public const string Sunflower = "sunflower";

    // Logistics on plots: belts carry items, inserters move them between belts, machines and storage.
    public const string Belt = "logistics_belt";
    public const string Inserter = "logistics_inserter";
    public const string Splitter = "logistics_splitter";

    // Upgraded belts and inserters: the same, only faster.
    public const string FastBelt = "logistics_fast_belt";
    public const string ExpressBelt = "logistics_express_belt";
    public const string FastInserter = "logistics_fast_inserter";
    public const string ExpressInserter = "logistics_express_inserter";

    // Storage put on plots: chests take anything, piles, heaps and silos one kind of bulk goods.
    public const string WoodenChest = "storage_wooden_chest";
    public const string IronChest = "storage_iron_chest";
    public const string WoodPile = "storage_wood_pile";
    public const string Heap = "storage_heap";
    public const string GrainSilo = "storage_grain_silo";

    // Food processing: machines put on a plot turn crops into food, step by step.
    public const string Mill = "furniture_mill";
    public const string OilPress = "furniture_oil_press";
    public const string PicklingBarrel = "furniture_pickling_barrel";
    public const string Bakery = "furniture_bakery";
    public const string Kitchen = "furniture_kitchen";
    public const string Flour = "flour";
    public const string CornFlour = "corn_flour";
    public const string SunflowerOil = "sunflower_oil";
    public const string Sauerkraut = "sauerkraut";
    public const string Bread = "bread";
    public const string CornBread = "corn_bread";
    public const string CarrotCake = "carrot_cake";
    public const string Fries = "fries";
    public const string VegetableSoup = "vegetable_soup";
    public const string Bigos = "bigos";
    public const string ScrambledEggs = "scrambled_eggs";

    // Office: a computer put on a plot opens the market there, far from the garage.
    public const string Computer = "furniture_computer";

    // Power on plots: a generator burns wood or coal, poles carry its power to machines near them.
    public const string Generator = "power_generator";
    public const string Pole = "power_pole";

    // Forestry industry: a forester's building stands on 3 × 3 tiles of a plot, plants saplings around
    // itself and cuts the grown trees by itself; a sawmill works the wood. Each comes in three levels.
    public const string ForesterHut = "furniture_forester_hut";
    public const string ForesterLodge = "furniture_forester_lodge";
    public const string ForestryStation = "furniture_forestry_station";
    public const string Sawmill = "furniture_sawmill";
    public const string ElectricSawmill = "furniture_electric_sawmill";
    public const string IndustrialSawmill = "furniture_industrial_sawmill";
    public const string Planks = "planks";
    public const string Beams = "beams";
    public const string WoodPellets = "wood_pellets";
    public const string Plywood = "plywood";

    // Mountain industry: minerals some mountain plots have in their mines (a geological survey tells which),
    // ore crushed for more ingots, alloys from the foundry, stonework, dynamite and props for deep mines.
    public const string Sulfur = "sulfur";
    public const string Salt = "salt";
    public const string Marble = "marble";
    public const string Quartz = "quartz";
    public const string CrushedIronOre = "crushed_iron_ore";
    public const string CrushedCopperOre = "crushed_copper_ore";
    public const string CrushedTinOre = "crushed_tin_ore";
    public const string BronzeIngot = "bronze_ingot";
    public const string SteelIngot = "steel_ingot";
    public const string StoneBlocks = "stone_blocks";
    public const string MarbleSlabs = "marble_slabs";
    public const string Bricks = "bricks";
    public const string Dynamite = "dynamite";
    public const string MineSupport = "mine_support";

    // Mountain machines: a drill stands at a mine and digs it by itself, a quarry cuts stone, a crusher
    // grinds stone and ore, a stonemason dresses stone and marble, a foundry casts alloys and fires bricks.
    public const string Drill = "furniture_drill";
    public const string HeavyDrill = "furniture_heavy_drill";
    public const string Quarry = "furniture_quarry";
    public const string Crusher = "furniture_crusher";
    public const string Stonemason = "furniture_stonemason";
    public const string Foundry = "furniture_foundry";

    // Water power: a water wheel and a small hydro plant give power without fuel, by a river or the sea.
    public const string WaterWheel = "power_water_wheel";
    public const string HydroPlant = "power_hydro_plant";

    // A cable car: stations facing the same way carry what a belt brings them over anything in between.
    public const string CableStation = "logistics_cable_station";

    // Coastal plots: the sea along the coast and a lake on the lakeshore, fished with a rod or from boats;
    // fish smoked, salted and canned, salt boiled from the sea, salmon and mussels farmed, and the beach
    // combed for what the sea throws up.
    public const string FishingRod = "tool_fishing_rod";
    public const string Herring = "herring";
    public const string Cod = "cod";
    public const string Carp = "carp";
    public const string Pike = "pike";
    public const string Salmon = "salmon";
    public const string Mussels = "mussels";
    public const string Seaweed = "seaweed";
    public const string Amber = "amber";
    public const string SmokedFish = "smoked_fish";
    public const string SmokedSalmon = "smoked_salmon";
    public const string SaltedHerring = "salted_herring";
    public const string CannedFish = "canned_fish";
    public const string FishMeal = "fish_meal";
    public const string FishOil = "fish_oil";
    public const string FriedCarp = "fried_carp";
    public const string FishSoup = "fish_soup";

    // Coastal buildings: they stand on the shore, right next to the water.
    public const string FishingBoat = "furniture_fishing_boat";
    public const string RowingBoat = "furniture_rowing_boat";
    public const string Smokehouse = "furniture_smokehouse";
    public const string Cannery = "furniture_cannery";
    public const string SaltPan = "furniture_salt_pan";
    public const string FishFarm = "furniture_fish_farm";
    public const string Shipyard = "furniture_shipyard";
    public const string Port = "furniture_port";
    public const string Breakwater = "furniture_breakwater";
    public const string Lighthouse = "furniture_lighthouse";
    public const string TidalPlant = "power_tidal_plant";

    // Oil and gas: wells pump what the survey found under a plot, pipes carry the fluids, a distillery and a refinery
    // split crude oil into fuels and asphalt, a cracker makes more petrol of the heavier ones and a chemical plant
    // makes plastic, rubber and fertiliser of gas.
    public const string CrudeOil = "crude_oil";
    public const string NaturalGas = "natural_gas";
    public const string Gasoline = "gasoline";
    public const string Diesel = "diesel";
    public const string Kerosene = "kerosene";
    public const string Asphalt = "asphalt";
    public const string Plastic = "plastic";
    public const string SyntheticRubber = "synthetic_rubber";
    public const string Fertilizer = "fertilizer";
    public const string Gasket = "gasket";

    public const string Pumpjack = "furniture_pumpjack";
    public const string GasWell = "furniture_gas_well";
    public const string OffshorePlatform = "furniture_offshore_platform";
    public const string WaterInjector = "furniture_water_injector";
    public const string OilSeparator = "furniture_oil_separator";
    public const string Distillery = "furniture_distillery";
    public const string Refinery = "furniture_refinery";
    public const string Cracker = "furniture_cracker";
    public const string ChemicalPlant = "furniture_chemical_plant";
    public const string GasPlant = "power_gas_plant";
    public const string DieselGenerator = "power_diesel_generator";
    public const string Pipe = "logistics_pipe";
    public const string Pump = "logistics_pump";
    public const string Tank = "storage_tank";
    public const string Road = "logistics_road";

    /// <summary>Display names in Polish, keyed by id.</summary>
    public static readonly IReadOnlyDictionary<string, string> Names = new Dictionary<string, string>
    {
        [Trash] = "Śmieci",
        [WastePaper] = "Makulatura",
        [WasteAluminium] = "Złom aluminium",
        [WasteCopper] = "Złom miedzi",
        [WastePlastic] = "Plastik z odzysku",
        [WasteGlass] = "Stłuczka szklana",
        [TrashBin] = "Kosz na śmieci",
        [Workbench] = "Stół warsztatowy",
        [Shelf] = "Regał",
        [BarrelBlue] = "Niebieska beczka",
        [BarrelRed] = "Czerwona beczka",
        [Tyres] = "Opony",
        [Pallet] = "Paleta",
        [GasCylinder] = "Butla gazowa",
        [SortingMachine] = "Automatyczna sortownia",
        [Furnace] = "Piec kamienny",
        [Anvil] = "Kowadło",
        [BrickFurnace] = "Piec ceglany",
        [BlastFurnace] = "Piec hutniczy",
        [Axe] = "Siekiera",
        [Shovel] = "Łopata",
        [Pickaxe] = "Kilof",
        [Hoe] = "Motyka",
        [Chainsaw] = "Piła spalinowa",
        [Shears] = "Nożyce do strzyżenia",
        [SchoolBackpack] = "Plecak szkolny",
        [HikingBackpack] = "Plecak turystyczny",
        [TrekkingBackpack] = "Plecak trekkingowy",
        [ExpeditionBackpack] = "Plecak wyprawowy",
        [TycoonBackpack] = "Plecak magnata",
        [Wood] = "Drewno",
        [Stone] = "Kamień",
        [Sand] = "Piasek",
        [Coal] = "Węgiel",
        [IronOre] = "Ruda żelaza",
        [CopperOre] = "Ruda miedzi",
        [TinOre] = "Ruda cyny",
        [SilverOre] = "Ruda srebra",
        [GoldOre] = "Ruda złota",
        [IronIngot] = "Sztabka żelaza",
        [CopperIngot] = "Sztabka miedzi",
        [TinIngot] = "Sztabka cyny",
        [SilverIngot] = "Sztabka srebra",
        [GoldIngot] = "Sztabka złota",
        [Nails] = "Gwoździe",
        [Sapling] = "Sadzonka drzewa",
        [Chicken] = "Kura",
        [Sheep] = "Owca",
        [Cow] = "Krowa",
        [Egg] = "Jajka",
        [Wool] = "Wełna",
        [Milk] = "Mleko",
        [Wheat] = "Pszenica",
        [Carrot] = "Marchew",
        [Cabbage] = "Kapusta",
        [Corn] = "Kukurydza",
        [Potato] = "Ziemniaki",
        [Sunflower] = "Słonecznik",
        [Belt] = "Taśmociąg",
        [Inserter] = "Podajnik",
        [Splitter] = "Rozdzielacz",
        [FastBelt] = "Szybki taśmociąg",
        [ExpressBelt] = "Ekspresowy taśmociąg",
        [FastInserter] = "Szybki podajnik",
        [ExpressInserter] = "Ekspresowy podajnik",
        [WoodenChest] = "Skrzynia drewniana",
        [IronChest] = "Skrzynia żelazna",
        [WoodPile] = "Stos drewna",
        [Heap] = "Hałda",
        [GrainSilo] = "Silos zbożowy",
        [Mill] = "Młyn",
        [OilPress] = "Tłocznia oleju",
        [PicklingBarrel] = "Beczka do kiszenia",
        [Bakery] = "Piec piekarski",
        [Computer] = "Komputer",
        [Kitchen] = "Kuchnia polowa",
        [Flour] = "Mąka pszenna",
        [CornFlour] = "Mąka kukurydziana",
        [SunflowerOil] = "Olej słonecznikowy",
        [Sauerkraut] = "Kapusta kiszona",
        [Bread] = "Chleb",
        [CornBread] = "Chleb kukurydziany",
        [CarrotCake] = "Ciasto marchewkowe",
        [Fries] = "Frytki",
        [VegetableSoup] = "Zupa jarzynowa",
        [Bigos] = "Bigos",
        [ScrambledEggs] = "Jajecznica",
        [Generator] = "Generator parowy",
        [Pole] = "Słup energetyczny",
        [ForesterHut] = "Chata leśnika",
        [ForesterLodge] = "Leśniczówka",
        [ForestryStation] = "Nadleśnictwo",
        [Sawmill] = "Tartak",
        [ElectricSawmill] = "Tartak elektryczny",
        [IndustrialSawmill] = "Tartak przemysłowy",
        [Planks] = "Deski",
        [Beams] = "Belki",
        [WoodPellets] = "Pellet drzewny",
        [Plywood] = "Sklejka",
        [BronzePickaxe] = "Kilof z brązu",
        [SteelPickaxe] = "Kilof stalowy",
        [Sulfur] = "Siarka",
        [Salt] = "Sól",
        [Marble] = "Marmur",
        [Quartz] = "Kwarc",
        [CrushedIronOre] = "Kruszona ruda żelaza",
        [CrushedCopperOre] = "Kruszona ruda miedzi",
        [CrushedTinOre] = "Kruszona ruda cyny",
        [BronzeIngot] = "Sztabka brązu",
        [SteelIngot] = "Sztabka stali",
        [StoneBlocks] = "Bloki kamienne",
        [MarbleSlabs] = "Płyty marmurowe",
        [Bricks] = "Cegły",
        [Dynamite] = "Dynamit",
        [MineSupport] = "Obudowa górnicza",
        [Drill] = "Wiertło górnicze",
        [HeavyDrill] = "Wiertło udarowe",
        [Quarry] = "Kamieniołom",
        [Crusher] = "Kruszarka",
        [Stonemason] = "Warsztat kamieniarski",
        [Foundry] = "Odlewnia",
        [WaterWheel] = "Koło wodne",
        [HydroPlant] = "Mała elektrownia wodna",
        [CableStation] = "Stacja kolejki linowej",
        [FishingRod] = "Wędka",
        [Herring] = "Śledź",
        [Cod] = "Dorsz",
        [Carp] = "Karp",
        [Pike] = "Szczupak",
        [Salmon] = "Łosoś",
        [Mussels] = "Małże",
        [Seaweed] = "Algi",
        [Amber] = "Bursztyn",
        [SmokedFish] = "Ryba wędzona",
        [SmokedSalmon] = "Łosoś wędzony",
        [SaltedHerring] = "Śledzie w soli",
        [CannedFish] = "Konserwa rybna",
        [FishMeal] = "Mączka rybna",
        [FishOil] = "Olej rybny",
        [FriedCarp] = "Karp smażony",
        [FishSoup] = "Zupa rybna",
        [FishingBoat] = "Kuter rybacki",
        [RowingBoat] = "Łódź rybacka",
        [Smokehouse] = "Wędzarnia",
        [Cannery] = "Konserwiarnia",
        [SaltPan] = "Warzelnia soli",
        [FishFarm] = "Farma ryb",
        [Shipyard] = "Stocznia",
        [Port] = "Przystań",
        [Breakwater] = "Falochron",
        [Lighthouse] = "Latarnia morska",
        [TidalPlant] = "Elektrownia pływowa",
        [CrudeOil] = "Ropa naftowa",
        [NaturalGas] = "Gaz ziemny",
        [Gasoline] = "Benzyna",
        [Diesel] = "Olej napędowy",
        [Kerosene] = "Nafta",
        [Asphalt] = "Asfalt",
        [Plastic] = "Tworzywo sztuczne",
        [SyntheticRubber] = "Kauczuk syntetyczny",
        [Fertilizer] = "Nawóz",
        [Gasket] = "Uszczelka",
        [Pumpjack] = "Żuraw pompowy",
        [GasWell] = "Głowica gazowa",
        [OffshorePlatform] = "Platforma wiertnicza",
        [WaterInjector] = "Tłocznia wody",
        [OilSeparator] = "Separator ropy",
        [Distillery] = "Destylarnia",
        [Refinery] = "Rafineria",
        [Cracker] = "Instalacja krakingu",
        [ChemicalPlant] = "Zakład chemiczny",
        [GasPlant] = "Elektrownia gazowa",
        [DieselGenerator] = "Agregat spalinowy",
        [Pipe] = "Rura",
        [Pump] = "Pompa",
        [Tank] = "Zbiornik",
        [Road] = "Droga asfaltowa",
    };

    public static bool Exists(string id) => Names.ContainsKey(id);

    public static bool IsTool(string id) => id is Axe or Shovel or Pickaxe or Hoe or Chainsaw or Shears or BronzePickaxe or SteelPickaxe or FishingRod;

    /// <summary>Pickaxes of every kind and how many times faster than the iron one each mines and breaks rocks.</summary>
    public static readonly IReadOnlyDictionary<string, double> Pickaxes = new Dictionary<string, double>
    {
        [Pickaxe] = 1,
        [BronzePickaxe] = 1.25,
        [SteelPickaxe] = 1.5,
    };

    public static bool IsBackpack(string id) => Backpacks.ContainsKey(id);

    /// <summary>What each backpack gives while worn: extra inventory tiles and tool bar slots in all.</summary>
    public static readonly IReadOnlyDictionary<string, Backpack> Backpacks = new Dictionary<string, Backpack>
    {
        [SchoolBackpack] = new(20, 2),
        [HikingBackpack] = new(40, 2),
        [TrekkingBackpack] = new(60, 2),
        [ExpeditionBackpack] = new(80, 2),
        [TycoonBackpack] = new(100, 3),
    };

    /// <summary>Inventory tiles without a backpack.</summary>
    public const int InventorySlots = 20;

    /// <summary>Tool bar slots without a backpack.</summary>
    public const int ToolSlots = 1;

    /// <summary>Inventory tiles with the most a backpack adds.</summary>
    public static readonly int MaxInventorySlots = InventorySlots + Backpacks.Values.Max(b => b.ExtraSlots);

    /// <summary>Tool bar slots with the most a backpack gives.</summary>
    public static readonly int MaxToolSlots = Backpacks.Values.Max(b => b.ToolSlots);

    /// <summary>Furnaces of every level: the stone one and its upgrades.</summary>
    public static bool IsFurnace(string id) => id is Furnace or BrickFurnace or BlastFurnace;

    /// <summary>Forester's buildings of every level: the hut and its upgrades.</summary>
    public static bool IsForester(string id) => id is ForesterHut or ForesterLodge or ForestryStation;

    /// <summary>Drills of every level, which stand at a mine and dig it by themselves.</summary>
    public static bool IsDrill(string id) => id is Drill or HeavyDrill;

    /// <summary>What gives power without fuel: the water wheel, the hydro plant and the tidal plant.</summary>
    public static bool IsHydro(string id) => id is WaterWheel or HydroPlant or TidalPlant;

    /// <summary>Boats, which fish the water their plot's shore stands on by themselves.</summary>
    public static bool IsBoat(string id) => id is FishingBoat or RowingBoat;

    /// <summary>Belts of every level (not splitters).</summary>
    public static bool IsBelt(string id) => id is Belt or FastBelt or ExpressBelt or Pipe;

    /// <summary>Inserters of every level.</summary>
    public static bool IsInserter(string id) => id is Inserter or FastInserter or ExpressInserter or Pump;

    /// <summary>Fluids: they go only through pipes and pumps, never on belts or by inserters.</summary>
    public static bool IsFluid(string id) => id is CrudeOil or NaturalGas or Gasoline or Diesel or Kerosene;

    /// <summary>What carries fluids: a pipe instead of a belt, a pump instead of an inserter.</summary>
    public static bool CarriesFluids(string kind) => kind is Pipe or Pump;

    /// <summary>Wells, which pump the oil or gas under their plot by themselves.</summary>
    public static bool IsWell(string id) => id is Pumpjack or GasWell or OffshorePlatform;

    /// <summary>Generators that burn fuel: the steam generator, the gas power plant and the diesel generator.</summary>
    public static bool IsGenerator(string id) => id is Generator or GasPlant or DieselGenerator;
}

/// <param name="ExtraSlots">Inventory tiles the backpack adds.</param>
/// <param name="ToolSlots">Tool bar slots in all while it is worn.</param>
public sealed record Backpack(int ExtraSlots, int ToolSlots);
