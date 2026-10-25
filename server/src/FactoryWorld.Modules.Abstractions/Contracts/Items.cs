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

    // A wardrobe in the garage keeps clothes and saved outfits to change into at once.
    public const string ClothesWardrobe = "furniture_wardrobe";
    /// <summary>Where research is done; every garage has one from the start.</summary>
    public const string ResearchTable = "furniture_research_table";

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

    // The desert: glass from sand, silicon and solar power, water drawn or made, sun-dried bricks and concrete,
    // dates from an oasis, camels, and fossils the dunes give up now and then.
    public const string Glass = "glass";
    public const string WindowPane = "window_pane";
    public const string GlassBottles = "glass_bottles";
    public const string OpticalFiber = "optical_fiber";
    public const string Silicon = "silicon";
    public const string SiliconWafer = "silicon_wafer";
    public const string Water = "water";
    public const string Clay = "clay";
    public const string AdobeBricks = "adobe_bricks";
    public const string Cement = "cement";
    public const string Concrete = "concrete";
    public const string Dates = "dates";
    public const string Mirror = "mirror";
    public const string Ammonite = "ammonite";
    public const string AncientCoin = "ancient_coin";
    public const string DinosaurBone = "dinosaur_bone";

    public const string Glassworks = "furniture_glassworks";
    public const string ArcFurnace = "furniture_arc_furnace";
    public const string WaterWell = "furniture_water_well";
    public const string Desalinator = "furniture_desalinator";
    public const string DryingYard = "furniture_drying_yard";
    public const string CementKiln = "furniture_cement_kiln";
    public const string ConcreteMixer = "furniture_concrete_mixer";
    public const string ReedFence = "furniture_reed_fence";
    public const string SolarPanel = "power_solar_panel";
    public const string SolarTower = "power_solar_tower";
    public const string Battery = "power_battery";
    public const string Camel = "animal_camel";

    // The glacier: wind turbines, ice cut and melted, a cold store, a server room and a polar station that speed research up,
    // meteorites, heaters against the frost, tourists who come for the aurora, dog sleds and snowmobiles, and bridges over crevasses.
    public const string Ice = "ice";
    public const string MeteoricIron = "meteoric_iron";
    public const string Iridium = "iridium";
    public const string MeteoritePickaxe = "tool_meteorite_pickaxe";
    public const string FrozenFish = "frozen_fish";
    public const string FrozenSalmon = "frozen_salmon";
    public const string IceCream = "ice_cream";
    public const string ComputingPower = "computing_power";
    public const string IceCore = "ice_core";
    public const string ResearchData = "research_data";
    public const string Takings = "tourist_takings";

    public const string WindTurbine = "power_wind_turbine";
    public const string LargeWindTurbine = "power_large_wind_turbine";
    public const string Heater = "power_heater";
    public const string IceMelter = "furniture_ice_melter";
    public const string ColdStore = "furniture_cold_store";
    public const string ServerRoom = "furniture_server_room";
    public const string IceCoreDrill = "furniture_ice_core_drill";
    public const string PolarStation = "furniture_polar_station";
    public const string IceHotel = "furniture_ice_hotel";
    public const string Viewpoint = "furniture_viewpoint";
    public const string DogKennel = "furniture_dog_kennel";
    public const string SnowmobileGarage = "furniture_snowmobile_garage";
    public const string TrackFoundation = "furniture_track_foundation";

    // Cities: an assembly hall puts goods of every biome together, the towns of the map want goods and grow on them,
    // players keep shops, high-bay stores, multi-storey factories, municipal sorting, freight terminals, company
    // headquarters and offices that sell their services, and a town hall where the town's players elect a mayor.
    public const string Bicycle = "bicycle";
    public const string CircuitBoard = "circuit_board";
    public const string ElectricMotor = "electric_motor";
    public const string Radio = "radio";
    public const string WashingMachine = "washing_machine";
    public const string Car = "car";
    public const string Blueprint = "blueprint";

    public const string AssemblyHall = "furniture_assembly_hall";
    public const string MultistoreyFactory = "furniture_multistorey_factory";
    public const string Shop = "furniture_shop";
    public const string HighBay = "storage_high_bay";
    public const string CitySorter = "furniture_city_sorter";
    public const string FreightTerminal = "furniture_freight_terminal";
    public const string CompanyHq = "furniture_company_hq";
    public const string DesignOffice = "furniture_design_office";
    public const string Laboratory = "furniture_laboratory";
    public const string ServiceWorkshop = "furniture_service_workshop";

    // Clothes: sewn at a tailor's in town and worn in four slots; each makes some industry's work go faster
    // (or, for trade, makes the trader pay more), see Clothes.
    public const string Tailor = "furniture_tailor";
    public const string MinerHelmet = "clothes_miner_helmet";
    public const string SouWester = "clothes_sou_wester";
    public const string StrawHat = "clothes_straw_hat";
    public const string Beanie = "clothes_beanie";
    public const string FlannelJacket = "clothes_flannel_jacket";
    public const string SmithApron = "clothes_smith_apron";
    public const string Oilskin = "clothes_oilskin";
    public const string SuitJacket = "clothes_suit_jacket";
    public const string Overalls = "clothes_overalls";
    public const string WorkTrousers = "clothes_work_trousers";
    public const string SuitTrousers = "clothes_suit_trousers";
    public const string RubberBoots = "clothes_rubber_boots";
    public const string WorkBoots = "clothes_work_boots";
    public const string DressShoes = "clothes_dress_shoes";

    // Forestry: trees of five kinds with their own saplings, what the forest floor gives, paper, furniture, charcoal,
    // resin and what is made of it, honey, and the fight against fires and the bark beetle.
    public const string SaplingSpruce = "sapling_spruce";
    public const string SaplingBirch = "sapling_birch";
    public const string SaplingOak = "sapling_oak";
    public const string SaplingLinden = "sapling_linden";
    public const string OakWood = "oak_wood";
    public const string Resin = "resin";
    public const string Pulp = "pulp";
    public const string Paper = "paper";
    public const string Cardboard = "cardboard";
    public const string Chair = "chair";
    public const string Table = "table";
    public const string Wardrobe = "wardrobe";
    public const string OakDresser = "oak_dresser";
    public const string Charcoal = "charcoal";
    public const string Mushrooms = "mushrooms";
    public const string Berries = "berries";
    public const string Herbs = "herbs";
    public const string MushroomSoup = "mushroom_soup";
    public const string BerryPierogi = "berry_pierogi";
    public const string HerbalTea = "herbal_tea";
    public const string Honey = "honey";
    public const string Wax = "wax";
    public const string Gingerbread = "gingerbread";
    public const string Candles = "candles";
    public const string Tar = "tar";
    public const string Turpentine = "turpentine";
    public const string Rosin = "rosin";
    public const string Insecticide = "insecticide";

    public const string PaperMill = "furniture_paper_mill";
    public const string Carpentry = "furniture_carpentry";
    public const string CharcoalKiln = "furniture_charcoal_kiln";
    public const string TarKiln = "furniture_tar_kiln";
    public const string Beehive = "furniture_beehive";
    public const string Watchtower = "furniture_fire_watchtower";
    public const string FireStation = "furniture_fire_station";

    // The crafting tree of eleven levels: half-products that join branches of production (level 1), parts made of them
    // (levels 2-6), and at the top rockets, satellites and fusion (levels 7-9). Each level is made of the ones below it.
    public const string Lubricant = "lubricant";
    public const string ElectricWire = "electric_wire";
    public const string GlassLaminate = "glass_laminate";
    public const string Paint = "paint";
    public const string CaseinGlue = "casein_glue";
    public const string InsulationBoard = "insulation_board";
    public const string Firebrick = "firebrick";
    public const string PrecastConcrete = "precast_concrete";
    public const string Coolant = "coolant";
    public const string IridiumAlloy = "iridium_alloy";
    public const string Provisions = "provisions";
    public const string Bearing = "bearing";
    public const string PaintedSheet = "painted_sheet";
    public const string Coil = "coil";
    public const string WiringHarness = "wiring_harness";
    public const string RefractoryLining = "refractory_lining";
    public const string CarbonComposite = "carbon_composite";
    public const string SuperconductingWire = "superconducting_wire";
    public const string RocketFuel = "rocket_fuel";
    public const string Gearbox = "gearbox";
    public const string Rotor = "rotor";
    public const string MachineHousing = "machine_housing";
    public const string CombustionChamber = "combustion_chamber";
    public const string CompositePanel = "composite_panel";
    public const string SuperconductingMagnet = "superconducting_magnet";
    public const string Alternator = "alternator";
    public const string ControlModule = "control_module";
    public const string HydraulicActuator = "hydraulic_actuator";
    public const string RocketNozzle = "rocket_nozzle";
    public const string PressureVessel = "pressure_vessel";
    public const string ComputingCore = "computing_core";
    public const string RobotArm = "robot_arm";
    public const string Turbopump = "turbopump";
    public const string TurbineSet = "turbine_set";
    public const string CryogenicTank = "cryogenic_tank";
    public const string IndustrialRobot = "industrial_robot";
    public const string NavigationSystem = "navigation_system";
    public const string RocketEngine = "rocket_engine";
    public const string PlasmaChamber = "plasma_chamber";
    public const string Avionics = "avionics";
    public const string PlasmaControl = "plasma_control";
    public const string RocketStage = "rocket_stage";
    public const string Satellite = "satellite";
    public const string FusionReactor = "fusion_reactor";
    public const string LaunchRocket = "launch_rocket";
    public const string MachineShop = "furniture_machine_shop";
    public const string RoboticHall = "furniture_robotic_hall";
    public const string OxygenConverter = "furniture_oxygen_converter";
    public const string RollingMill = "furniture_rolling_mill";
    public const string ControlCenter = "furniture_control_center";
    public const string ContinuousCaster = "furniture_continuous_caster";
    public const string AutomatedWarehouse = "storage_automated_warehouse";
    public const string SteelCombine = "furniture_steel_combine";
    public const string Megafactory = "furniture_megafactory";
    public const string FusionPlant = "power_fusion_plant";

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
        [ClothesWardrobe] = "Szafa na ubrania",
        [BarrelBlue] = "Niebieska beczka",
        [BarrelRed] = "Czerwona beczka",
        [Tyres] = "Opony",
        [Pallet] = "Paleta",
        [GasCylinder] = "Butla gazowa",
        [SortingMachine] = "Automatyczna sortownia",
        [Furnace] = "Piec kamienny",
        [Anvil] = "Kowadło",
        [ResearchTable] = "Stół badawczy",
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
        [Sapling] = "Sadzonka sosny",
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
        [Glass] = "Szkło",
        [WindowPane] = "Szyba",
        [GlassBottles] = "Butelki szklane",
        [OpticalFiber] = "Światłowód",
        [Silicon] = "Krzem",
        [SiliconWafer] = "Płytka krzemowa",
        [Water] = "Woda",
        [Clay] = "Glina",
        [AdobeBricks] = "Cegła suszona",
        [Cement] = "Cement",
        [Concrete] = "Beton",
        [Dates] = "Daktyle",
        [Mirror] = "Lustro",
        [Ammonite] = "Amonit",
        [AncientCoin] = "Starożytna moneta",
        [DinosaurBone] = "Kość dinozaura",
        [Glassworks] = "Huta szkła",
        [ArcFurnace] = "Piec łukowy",
        [WaterWell] = "Studnia głębinowa",
        [Desalinator] = "Odsalarka",
        [DryingYard] = "Suszarnia cegieł",
        [CementKiln] = "Piec cementowy",
        [ConcreteMixer] = "Betoniarka",
        [ReedFence] = "Płot trzcinowy",
        [SolarPanel] = "Panel słoneczny",
        [SolarTower] = "Elektrownia słoneczna z lustrami",
        [Battery] = "Akumulator",
        [Camel] = "Wielbłąd",
        [Ice] = "Lód",
        [MeteoricIron] = "Żelazo meteorytowe",
        [Iridium] = "Iryd",
        [MeteoritePickaxe] = "Kilof meteorytowy",
        [FrozenFish] = "Mrożona ryba",
        [FrozenSalmon] = "Mrożony łosoś",
        [IceCream] = "Lody",
        [ComputingPower] = "Moc obliczeniowa",
        [IceCore] = "Rdzeń lodowy",
        [ResearchData] = "Dane naukowe",
        [Takings] = "Utarg od turystów",
        [WindTurbine] = "Turbina wiatrowa",
        [LargeWindTurbine] = "Duża turbina wiatrowa",
        [Heater] = "Kocioł grzewczy",
        [IceMelter] = "Topielnik lodu",
        [ColdStore] = "Chłodnia",
        [ServerRoom] = "Serwerownia",
        [IceCoreDrill] = "Wiertnica lodowa",
        [PolarStation] = "Stacja polarna",
        [IceHotel] = "Hotel lodowy",
        [Viewpoint] = "Punkt widokowy",
        [DogKennel] = "Psiarnia z zaprzęgiem",
        [SnowmobileGarage] = "Garaż skuterów śnieżnych",
        [TrackFoundation] = "Fundament toru",
        [Bicycle] = "Rower",
        [CircuitBoard] = "Płytka drukowana",
        [ElectricMotor] = "Silnik elektryczny",
        [Radio] = "Radio",
        [WashingMachine] = "Pralka",
        [Car] = "Samochód",
        [Blueprint] = "Plany budynku",
        [AssemblyHall] = "Hala montażowa",
        [MultistoreyFactory] = "Fabryka wielopiętrowa",
        [Shop] = "Sklep",
        [HighBay] = "Magazyn wysokiego składowania",
        [CitySorter] = "Sortownia miejska",
        [FreightTerminal] = "Dworzec towarowy",
        [CompanyHq] = "Siedziba spółki",
        [DesignOffice] = "Biuro projektowe",
        [Laboratory] = "Laboratorium",
        [ServiceWorkshop] = "Warsztat serwisowy",
        [Tailor] = "Pracownia krawiecka",
        [MinerHelmet] = "Kask górniczy z czołówką",
        [SouWester] = "Kapelusz rybacki",
        [StrawHat] = "Słomkowy kapelusz",
        [Beanie] = "Czapka drwala",
        [FlannelJacket] = "Kurtka flanelowa",
        [SmithApron] = "Fartuch kowalski",
        [Oilskin] = "Sztormiak",
        [SuitJacket] = "Marynarka",
        [Overalls] = "Ogrodniczki",
        [WorkTrousers] = "Spodnie robocze",
        [SuitTrousers] = "Spodnie od garnituru",
        [RubberBoots] = "Kalosze",
        [WorkBoots] = "Trapery",
        [DressShoes] = "Półbuty",
        [SaplingSpruce] = "Sadzonka świerku",
        [SaplingBirch] = "Sadzonka brzozy",
        [SaplingOak] = "Sadzonka dębu",
        [SaplingLinden] = "Sadzonka lipy",
        [OakWood] = "Drewno dębowe",
        [Resin] = "Żywica",
        [Pulp] = "Masa celulozowa",
        [Paper] = "Papier",
        [Cardboard] = "Karton",
        [Chair] = "Krzesło",
        [Table] = "Stół",
        [Wardrobe] = "Szafa",
        [OakDresser] = "Komoda dębowa",
        [Charcoal] = "Węgiel drzewny",
        [Mushrooms] = "Grzyby",
        [Berries] = "Jagody",
        [Herbs] = "Zioła",
        [MushroomSoup] = "Zupa grzybowa",
        [BerryPierogi] = "Pierogi z jagodami",
        [HerbalTea] = "Herbata ziołowa",
        [Honey] = "Miód",
        [Wax] = "Wosk",
        [Gingerbread] = "Piernik",
        [Candles] = "Świece",
        [Tar] = "Smoła",
        [Turpentine] = "Terpentyna",
        [Rosin] = "Kalafonia",
        [Insecticide] = "Środek na kornika",
        [PaperMill] = "Papiernia",
        [Carpentry] = "Stolarnia",
        [CharcoalKiln] = "Mielerz",
        [TarKiln] = "Smolarnia",
        [Beehive] = "Ul",
        [Watchtower] = "Wieża obserwacyjna",
        [FireStation] = "Strażnica",
        [Lubricant] = "Smar techniczny",
        [ElectricWire] = "Przewód elektryczny",
        [GlassLaminate] = "Laminat szklany",
        [Paint] = "Farba",
        [CaseinGlue] = "Klej kazeinowy",
        [InsulationBoard] = "Płyta izolacyjna",
        [Firebrick] = "Cegła szamotowa",
        [PrecastConcrete] = "Prefabrykat żelbetowy",
        [Coolant] = "Płyn chłodniczy",
        [IridiumAlloy] = "Stop irydowy",
        [Provisions] = "Prowiant",
        [Bearing] = "Łożysko",
        [PaintedSheet] = "Blacha lakierowana",
        [Coil] = "Cewka",
        [WiringHarness] = "Wiązka kablowa",
        [RefractoryLining] = "Okładzina ogniotrwała",
        [CarbonComposite] = "Kompozyt węglowy",
        [SuperconductingWire] = "Drut nadprzewodzący",
        [RocketFuel] = "Paliwo rakietowe",
        [Gearbox] = "Przekładnia",
        [Rotor] = "Wirnik",
        [MachineHousing] = "Obudowa przemysłowa",
        [CombustionChamber] = "Komora spalania",
        [CompositePanel] = "Panel kompozytowy",
        [SuperconductingMagnet] = "Elektromagnes nadprzewodzący",
        [Alternator] = "Prądnica",
        [ControlModule] = "Moduł sterujący",
        [HydraulicActuator] = "Siłownik hydrauliczny",
        [RocketNozzle] = "Dysza rakietowa",
        [PressureVessel] = "Zbiornik ciśnieniowy",
        [ComputingCore] = "Rdzeń obliczeniowy",
        [RobotArm] = "Ramię robotyczne",
        [Turbopump] = "Turbopompa",
        [TurbineSet] = "Turbozespół",
        [CryogenicTank] = "Zbiornik kriogeniczny",
        [IndustrialRobot] = "Robot przemysłowy",
        [NavigationSystem] = "System nawigacji",
        [RocketEngine] = "Silnik rakietowy",
        [PlasmaChamber] = "Komora plazmowa",
        [Avionics] = "Awionika",
        [PlasmaControl] = "Układ sterowania plazmą",
        [RocketStage] = "Człon rakiety",
        [Satellite] = "Satelita",
        [FusionReactor] = "Reaktor fuzyjny",
        [LaunchRocket] = "Rakieta nośna",
        [MachineShop] = "Warsztat mechaniczny",
        [RoboticHall] = "Zrobotyzowana hala",
        [OxygenConverter] = "Konwerter tlenowy",
        [RollingMill] = "Walcownia",
        [ControlCenter] = "Centrum sterowania",
        [ContinuousCaster] = "Odlewnia ciągła",
        [AutomatedWarehouse] = "Magazyn zautomatyzowany",
        [SteelCombine] = "Kombinat hutniczy",
        [Megafactory] = "Megafabryka",
        [FusionPlant] = "Elektrownia fuzyjna",
    };

    public static bool Exists(string id) => Names.ContainsKey(id);

    public static bool IsTool(string id) => id is Axe or Shovel or Pickaxe or Hoe or Chainsaw or Shears or BronzePickaxe or SteelPickaxe or FishingRod or MeteoritePickaxe;

    /// <summary>Pickaxes of every kind and how many times faster than the iron one each mines and breaks rocks.</summary>
    public static readonly IReadOnlyDictionary<string, double> Pickaxes = new Dictionary<string, double>
    {
        [Pickaxe] = 1,
        [BronzePickaxe] = 1.25,
        [SteelPickaxe] = 1.5,
        [MeteoritePickaxe] = 2,
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
    public static bool IsFluid(string id) => id is CrudeOil or NaturalGas or Gasoline or Diesel or Kerosene or Water;

    /// <summary>What carries fluids: a pipe instead of a belt, a pump instead of an inserter.</summary>
    public static bool CarriesFluids(string kind) => kind is Pipe or Pump;

    /// <summary>Wells, which pump the oil or gas under their plot by themselves.</summary>
    public static bool IsWell(string id) => id is Pumpjack or GasWell or OffshorePlatform;

    /// <summary>Generators that burn fuel: the steam generator, the gas power plant, the diesel generator and the fusion plant, which uses up coolant.</summary>
    public static bool IsGenerator(string id) => id is Generator or GasPlant or DieselGenerator or FusionPlant;

    /// <summary>What turns sunlight into power: by day only, and less in a sandstorm.</summary>
    public static bool IsSolar(string id) => id is SolarPanel or SolarTower;

    /// <summary>What turns the wind into power: as much as the wind blows, nothing in a blizzard.</summary>
    public static bool IsWind(string id) => id is WindTurbine or LargeWindTurbine;

    /// <summary>What gives power without fuel: water power, the sun and the wind.</summary>
    public static bool IsRenewable(string id) => IsHydro(id) || IsSolar(id) || IsWind(id);

    /// <summary>A heater burns fuel to warm the machines around it against the frost of the glacier; it gives no power.</summary>
    public static bool IsHeater(string id) => id == Heater;

    /// <summary>What tourists pay: taken out of a hotel or a viewpoint, it goes into the wallet, not the inventory.</summary>
    public static bool IsMoney(string id) => id == Takings;

    /// <summary>What speeds research up, and by how many seconds each piece.</summary>
    public static readonly IReadOnlyDictionary<string, int> ResearchBoost = new Dictionary<string, int>
    {
        [ResearchData] = 60,
        [ComputingPower] = 15,
        [Blueprint] = 120,
    };

    /// <summary>What stands in a city only.</summary>
    public static bool IsCityOnly(string id) => id is MultistoreyFactory or Shop or HighBay or FreightTerminal or CompanyHq or DesignOffice or Laboratory or ServiceWorkshop
        or Tailor;

    public static bool IsClothing(string id) => Clothes.ContainsKey(id);

    /// <summary>Where each piece of clothing is worn and what it gives, in percent per industry (see <see cref="Industries"/>).</summary>
    public static readonly IReadOnlyDictionary<string, Garment> Clothes = new Dictionary<string, Garment>
    {
        [MinerHelmet] = new(ClothingSlots.Head, new Dictionary<string, int> { [Industries.Mining] = 15 }),
        [SouWester] = new(ClothingSlots.Head, new Dictionary<string, int> { [Industries.Fishing] = 15 }),
        [StrawHat] = new(ClothingSlots.Head, new Dictionary<string, int> { [Industries.Farming] = 15 }),
        [Beanie] = new(ClothingSlots.Head, new Dictionary<string, int> { [Industries.Forestry] = 10 }),
        [FlannelJacket] = new(ClothingSlots.Body, new Dictionary<string, int> { [Industries.Forestry] = 20 }),
        [SmithApron] = new(ClothingSlots.Body, new Dictionary<string, int> { [Industries.Crafting] = 20 }),
        [Oilskin] = new(ClothingSlots.Body, new Dictionary<string, int> { [Industries.Fishing] = 20 }),
        [SuitJacket] = new(ClothingSlots.Body, new Dictionary<string, int> { [Industries.Trade] = 4 }),
        [Overalls] = new(ClothingSlots.Legs, new Dictionary<string, int> { [Industries.Farming] = 20 }),
        [WorkTrousers] = new(ClothingSlots.Legs, new Dictionary<string, int> { [Industries.Mining] = 15, [Industries.Crafting] = 10 }),
        [SuitTrousers] = new(ClothingSlots.Legs, new Dictionary<string, int> { [Industries.Trade] = 3 }),
        [RubberBoots] = new(ClothingSlots.Feet, new Dictionary<string, int> { [Industries.Fishing] = 10, [Industries.Farming] = 10 }),
        [WorkBoots] = new(ClothingSlots.Feet, new Dictionary<string, int> { [Industries.Forestry] = 10, [Industries.Mining] = 10 }),
        [DressShoes] = new(ClothingSlots.Feet, new Dictionary<string, int> { [Industries.Trade] = 3 }),
    };

    /// <summary>City offices that sell a service to any player who comes by, for their owner.</summary>
    public static bool IsService(string id) => id is DesignOffice or Laboratory or ServiceWorkshop;

    /// <summary>The saplings of each kind of tree; the plain sapling grows a pine.</summary>
    public static bool IsSapling(string id) => id is Sapling or SaplingSpruce or SaplingBirch or SaplingOak or SaplingLinden;

    /// <summary>What the forest certificate makes dearer at the trader.</summary>
    public static bool IsTimber(string id) => id is Wood or OakWood or Planks or Beams;

    /// <summary>Coal and charcoal, which furnaces burn alike.</summary>
    public static bool IsCoal(string id) => id is Coal or Charcoal;

    /// <summary>Fossils the dunes give up now and then, a collection of three.</summary>
    public static bool IsFossil(string id) => id is Ammonite or AncientCoin or DinosaurBone;
}

/// <param name="ExtraSlots">Inventory tiles the backpack adds.</param>
/// <param name="ToolSlots">Tool bar slots in all while it is worn.</param>
public sealed record Backpack(int ExtraSlots, int ToolSlots);

/// <param name="Slot">One of <see cref="ClothingSlots.All"/>.</param>
/// <param name="Bonuses">Percent per industry: work in it goes this much faster (trade: the trader pays this much more).</param>
public sealed record Garment(string Slot, IReadOnlyDictionary<string, int> Bonuses);

/// <summary>Where clothes are worn.</summary>
public static class ClothingSlots
{
    public const string Head = "head";
    public const string Body = "body";
    public const string Legs = "legs";
    public const string Feet = "feet";

    public static readonly IReadOnlyList<string> All = [Head, Body, Legs, Feet];
}

/// <summary>The branches of work clothes help in.</summary>
public static class Industries
{
    /// <summary>Cutting trees, pulling out bushes and picking mushrooms by hand.</summary>
    public const string Forestry = "forestry";

    /// <summary>Breaking rocks and ice, digging snow and working mines with a pickaxe.</summary>
    public const string Mining = "mining";

    /// <summary>Tilling, sowing and reaping with a hoe.</summary>
    public const string Farming = "farming";

    /// <summary>Fishing with a rod.</summary>
    public const string Fishing = "fishing";

    /// <summary>Orders at the workbench, the anvil, the shipyard and the tailor's.</summary>
    public const string Crafting = "crafting";

    /// <summary>Selling to the trader.</summary>
    public const string Trade = "trade";

    public static readonly IReadOnlyList<string> All = [Forestry, Mining, Farming, Fishing, Crafting, Trade];

    /// <summary>How many times faster work goes with <paramref name="percent"/> from clothes.</summary>
    public static double Speed(int percent) => 1 + percent / 100.0;
}
